unit Markdown4D.Lcl.Images;
{ Turning the bytes of a picture into something an LCL canvas can draw.

  Two things get in the way.  An SVG is not a bitmap at all, so it goes through
  the library's rasteriser; and a bitmap with an alpha channel has nowhere to
  put it, because TCanvas composites nothing.  The alpha is therefore flattened
  onto the page colour, which is what the reader sees behind the picture
  anyway. }

{$mode delphiunicode}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}

interface

uses
  Classes, SysUtils, Graphics,
  Markdown4D.Layout.Interfaces;

type
  TMarkdownLclPictures = class
  public
    // Graphic is owned by the caller. False means the bytes are not a picture
    // this build can read; Graphic is nil then.
    class function FromBytes(const Data: TBytes; const Background: TLayoutColor;
      out Graphic: TGraphic): Boolean; static;
    class function FromFile(const FileName: string; const Background: TLayoutColor;
      out Graphic: TGraphic): Boolean; static;
    // Reads a whole file, without holding it in a string first.
    class function ReadAllBytes(const FileName: string): TBytes; static;
  end;

implementation

uses
  FPImage, IntfGraphics,
  Markdown4D.Image.Svg,
  Markdown4D.Image.Svg.Native;

type
  TRgb = record
    Red: Byte;
    Green: Byte;
    Blue: Byte;
  end;

function RgbOf(const Color: TLayoutColor): TRgb;
begin
  Result.Red := Byte(Color shr 16);
  Result.Green := Byte(Color shr 8);
  Result.Blue := Byte(Color);
end;

function FlattenChannel(const Value: Byte; const Alpha: Byte; const Under: Byte): Byte;
begin
  Result := Byte((Value * Alpha + Under * (255 - Alpha)) div 255);
end;

// The rasteriser hands back premultiplied BGRA, so compositing is a multiply
// and an add per channel.
function BitmapFromSvgRaster(const Raster: TMarkdownSvgRaster;
  const Background: TLayoutColor): TBitmap;
var
  Bitmap: TBitmap;
  Row, Column: Integer;
  Source: PByte;
  Dest: PByte;
  Under: TRgb;
  Alpha: Byte;
begin
  Result := nil;
  if (Raster.Width <= 0) or (Raster.Height <= 0) then
    Exit;
  if Length(Raster.Pixels) < Raster.Width * Raster.Height * 4 then
    Exit;

  Under := RgbOf(Background);
  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Raster.Width, Raster.Height);
    for Row := 0 to Raster.Height - 1 do
    begin
      Source := @Raster.Pixels[Row * Raster.Width * 4];
      Dest := Bitmap.ScanLine[Row];
      for Column := 0 to Raster.Width - 1 do
      begin
        Alpha := Source[3];
        if Alpha = 255 then
        begin
          Dest[0] := Source[0];
          Dest[1] := Source[1];
          Dest[2] := Source[2];
        end
        else if Alpha = 0 then
        begin
          Dest[0] := Under.Blue;
          Dest[1] := Under.Green;
          Dest[2] := Under.Red;
        end
        else
        begin
          Dest[0] := Byte(Source[0] + (Under.Blue * (255 - Alpha)) div 255);
          Dest[1] := Byte(Source[1] + (Under.Green * (255 - Alpha)) div 255);
          Dest[2] := Byte(Source[2] + (Under.Red * (255 - Alpha)) div 255);
        end;
        Dest[3] := 255;
        Inc(Source, 4);
        Inc(Dest, 4);
      end;
    end;
    Result := Bitmap;
  except
    Bitmap.Free;
    raise;
  end;
end;

// Pictures that carry no alpha are copied straight across; the rest are
// composited pixel by pixel, which only happens once per picture.
function FlattenPicture(const Picture: TPicture; const Background: TLayoutColor): TBitmap;
var
  Raster: TRasterImage;
  Source, Dest: TLazIntfImage;
  Row, Column: Integer;
  Pixel: TFPColor;
  Under: TRgb;
  Alpha: Byte;
begin
  Result := nil;
  if (Picture.Graphic = nil) or Picture.Graphic.Empty then
    Exit;
  if not (Picture.Graphic is TRasterImage) then
    Exit;

  Raster := TRasterImage(Picture.Graphic);
  Source := Raster.CreateIntfImage;
  try
    // Without alpha bits there is nothing to flatten, and the picture can be
    // copied across in one go.
    if Source.DataDescription.AlphaPrec = 0 then
    begin
      Result := TBitmap.Create;
      try
        Result.PixelFormat := pf32bit;
        Result.SetSize(Raster.Width, Raster.Height);
        Result.Canvas.Draw(0, 0, Picture.Graphic);
      except
        Result.Free;
        Result := nil;
        raise;
      end;
      Exit;
    end;

    Under := RgbOf(Background);
    Result := TBitmap.Create;
    try
      Result.PixelFormat := pf32bit;
      Result.SetSize(Source.Width, Source.Height);
      Dest := Result.CreateIntfImage;
      try
        for Row := 0 to Source.Height - 1 do
          for Column := 0 to Source.Width - 1 do
          begin
            Pixel := Source.Colors[Column, Row];
            Alpha := Byte(Pixel.Alpha shr 8);
            if Alpha = 255 then
              Dest.Colors[Column, Row] := Pixel
            else
              Dest.Colors[Column, Row] := FPColor(
                FlattenChannel(Byte(Pixel.Red shr 8), Alpha, Under.Red) shl 8 or $FF,
                FlattenChannel(Byte(Pixel.Green shr 8), Alpha, Under.Green) shl 8 or $FF,
                FlattenChannel(Byte(Pixel.Blue shr 8), Alpha, Under.Blue) shl 8 or $FF,
                $FFFF);
          end;
        Result.LoadFromIntfImage(Dest);
      finally
        Dest.Free;
      end;
    except
      Result.Free;
      Result := nil;
      raise;
    end;
  finally
    Source.Free;
  end;
end;

class function TMarkdownLclPictures.ReadAllBytes(const FileName: string): TBytes;
var
  Stream: TFileStream;
  Count: Int64;
begin
  Result := nil;
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Count := Stream.Size;
    if (Count <= 0) or (Count > High(Integer)) then
      Exit;
    SetLength(Result, Count);
    Stream.ReadBuffer(Result[0], Count);
  finally
    Stream.Free;
  end;
end;

class function TMarkdownLclPictures.FromBytes(const Data: TBytes;
  const Background: TLayoutColor; out Graphic: TGraphic): Boolean;
var
  Raster: TMarkdownSvgRaster;
  Stream: TBytesStream;
  Picture: TPicture;
  Bitmap: TBitmap;
begin
  Graphic := nil;
  Result := False;

  if TMarkdownSvgSupport.LooksLikeSvg(Data) then
  begin
    if not TMarkdownSvgSupport.IsAvailable then
      Exit;
    if not TMarkdownSvgSupport.TryRasterize(Data, 0, 0, Raster) then
      Exit;
    Graphic := BitmapFromSvgRaster(Raster, Background);
    Result := Graphic <> nil;
    Exit;
  end;

  Stream := TBytesStream.Create(Data);
  try
    Picture := TPicture.Create;
    try
      try
        Picture.LoadFromStream(Stream);
      except
        // bytes out of a document are an outside boundary: what cannot be read
        // is one picture that does not appear
        Exit;
      end;
      if (Picture.Graphic = nil) or Picture.Graphic.Empty then
        Exit;
      Bitmap := FlattenPicture(Picture, Background);
      if Bitmap = nil then
        Exit;
      Graphic := Bitmap;
      Result := True;
    finally
      Picture.Free;
    end;
  finally
    Stream.Free;
  end;
end;

class function TMarkdownLclPictures.FromFile(const FileName: string;
  const Background: TLayoutColor; out Graphic: TGraphic): Boolean;
var
  Data: TBytes;
begin
  Graphic := nil;
  Result := False;
  if not FileExists(FileName) then
    Exit;
  try
    Data := ReadAllBytes(FileName);
  except
    Exit;
  end;
  Result := FromBytes(Data, Background, Graphic);
end;

end.
