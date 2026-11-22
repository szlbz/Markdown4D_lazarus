{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Image.Glyphs.Gdi;

{$SCOPEDENUMS ON}

// Reads glyph outlines from the fonts installed on Windows. The system font
// engine picks the face, applies the metrics and hands back the curves, so a
// drawing gets the same letters the rest of the application shows.
//
// The unit registers itself, and does nothing at all off Windows.

interface

procedure RegisterGdiGlyphOutliner;

implementation

{$IFDEF MSWINDOWS}
uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  Math,
  Windows,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Image.Glyphs;

const
  // Points along a quadratic curve segment. A letter at reading size needs
  // little more than this to look round.
  CurveSegments = 6;
  FixedScale = 65536.0;
  // Not declared by the RTL: asks the font engine for the outline as the
  // designer drew it, without the grid fitting a screen size would impose.
  UnhintedOutline = $0100;

type
  // Turns a run of text into contours by asking the system font engine for the
  // outline of each glyph in turn.
  TGdiGlyphOutliner = class
  private
    const
      BoldWeight = 700;
      NormalWeight = 400;
    class function CreateFont(const FamilyName: string; const PixelSize: Single;
      const Bold, Italic: Boolean): HFONT; static;

  public
    class function TryOutline(const FamilyName: string; const PixelSize: Single; const Bold, Italic: Boolean;
      const Text: string; out Run: TMarkdownGlyphRun): Boolean; static;
  end;

  TM4DGen1 = TArray<TArray<TLayoutPointF>>;
  TOutlineReader = record
  private
    FData: TBytes;
    FIndex: Integer;
    FOffsetX: Single;
    function ReadWord: Word;
    function ReadLongWord: Cardinal;
    function ReadFixedPoint: TLayoutPointF;
  public
    class function Create(const Data: TBytes; const OffsetX: Single): TOutlineReader; static;
    function ReadContours: TM4DGen1;
  end;

class function TOutlineReader.Create(const Data: TBytes; const OffsetX: Single): TOutlineReader;
begin
  Result.FData := Data;
  Result.FIndex := 0;
  Result.FOffsetX := OffsetX;
end;

function TOutlineReader.ReadWord: Word;
begin
  Result := FData[FIndex] or (Word(FData[FIndex + 1]) shl 8);
  Inc(FIndex, 2);
end;

function TOutlineReader.ReadLongWord: Cardinal;
begin
  Result := FData[FIndex] or (Cardinal(FData[FIndex + 1]) shl 8) or (Cardinal(FData[FIndex + 2]) shl 16) or
    (Cardinal(FData[FIndex + 3]) shl 24);
  Inc(FIndex, 4);
end;

// A POINTFX is two 16.16 fixed point numbers, and the outline grows downwards
// from the baseline where a raster grows down the page, so Y is flipped.
function TOutlineReader.ReadFixedPoint: TLayoutPointF;
var
  RawX: type of (Integer(ReadLongWord));
  RawY: type of (Integer(ReadLongWord));
begin
  RawX := Integer(ReadLongWord);
  RawY := Integer(ReadLongWord);

  Result := TLayoutPointF.Create(FOffsetX + RawX / FixedScale, -RawY / FixedScale);
end;

function TOutlineReader.ReadContours: TM4DGen1;
var
  HeaderStart: Integer;
  HeaderSize: Cardinal;
  HeaderEnd: Cardinal;
  HeaderType: Cardinal;
  Points: TArray<TLayoutPointF>;
  CurveType: Word;
  CurveCount: Word;
  Step: Integer;
  Controls: TArray<TLayoutPointF>;
  Index: Integer;
  Start: TLayoutPointF;
  Control: TLayoutPointF;
  Stop: TLayoutPointF;
  Fraction: Double;
  Inverse: Double;
begin
  Result := nil;

  while FIndex + SizeOf(TTPolygonHeader) <= Length(FData) do
  begin
    HeaderStart := FIndex;
    HeaderSize := ReadLongWord;

    // The size comes from the font, so the end of the polygon is computed wide and
    // checked before it is used as an index. Adding it to FIndex directly would wrap
    // on a size above MaxInt and turn the bounds check below into a pass.
    HeaderEnd := Int64(HeaderStart) + HeaderSize;

    if (HeaderSize = 0) or (HeaderEnd > Length(FData)) then
      Exit;

    HeaderType := ReadLongWord;
    Points := [ReadFixedPoint];
    if HeaderType <> TT_POLYGON_TYPE then
      Exit;

    while FIndex < HeaderEnd do
    begin
      CurveType := ReadWord;
      CurveCount := ReadWord;

      if CurveType = TT_PRIM_LINE then
      begin
        for Step := 1 to CurveCount do
        begin
          Points := Points + [ReadFixedPoint];
        end;

        Continue;
      end;

      if CurveType <> TT_PRIM_QSPLINE then
        Exit;

      // Consecutive off-curve points share an implied on-curve point halfway
      // between them, which is how TrueType writes a run of curves.
      Controls := nil;
      for Step := 1 to CurveCount do
      begin
        Controls := Controls + [ReadFixedPoint];
      end;

      for Index := 0 to High(Controls) do
      begin
        Start := Points[High(Points)];
        Control := Controls[Index];

        Stop := Control;
        if Index < High(Controls) then
          Stop := TLayoutPointF.Create((Control.X + Controls[Index + 1].X) / 2,
            (Control.Y + Controls[Index + 1].Y) / 2)
        else
          Stop := Controls[Index];

        if Index = High(Controls) then
        begin
          Points := Points + [Stop];
          Continue;
        end;

        for Step := 1 to CurveSegments do
        begin
          Fraction := Step / CurveSegments;
          Inverse := 1 - Fraction;

          Points := Points + [TLayoutPointF.Create(
            Inverse * Inverse * Start.X + 2 * Inverse * Fraction * Control.X + Fraction * Fraction * Stop.X,
            Inverse * Inverse * Start.Y + 2 * Inverse * Fraction * Control.Y + Fraction * Fraction * Stop.Y)];
        end;
      end;
    end;

    if Length(Points) >= 3 then
      Result := Result + [Points];

    FIndex := Integer(HeaderEnd);
  end;
end;

class function TGdiGlyphOutliner.CreateFont(const FamilyName: string; const PixelSize: Single;
  const Bold, Italic: Boolean): HFONT;
var
  Description: TLogFont;
begin
  Description := Default(TLogFont);
  Description.lfHeight := -Round(PixelSize);
  Description.lfWeight := NormalWeight;
  if Bold then
    Description.lfWeight := BoldWeight;
  Description.lfItalic := Byte(Italic);
  Description.lfCharSet := DEFAULT_CHARSET;
  Description.lfOutPrecision := OUT_TT_ONLY_PRECIS;
  Description.lfQuality := DEFAULT_QUALITY;
  StrLCopy(PAnsiChar(@Description.lfFaceName[0]),
    PAnsiChar(AnsiString(FamilyName)), System.Length(Description.lfFaceName) - 1);

  Result := CreateFontIndirect(Description);
end;

class function TGdiGlyphOutliner.TryOutline(const FamilyName: string; const PixelSize: Single;
  const Bold, Italic: Boolean; const Text: string; out Run: TMarkdownGlyphRun): Boolean;
const
  Identity: TMat2 = (eM11: (fract: 0; value: 1); eM12: (fract: 0; value: 0); eM21: (fract: 0; value: 0);
    eM22: (fract: 0; value: 1));
var
  Screen: type of (GetDC(0));
  Memory: type of (CreateCompatibleDC(Screen));
  Font: HFONT;
  Previous: type of (SelectObject(Memory, Font));
  Pen: Single;
  Character: Char;
  Metrics: TGlyphMetrics;
  Size: type of (GetGlyphOutlineW(Memory, Ord(Character), GGO_NATIVE or UnhintedOutline, Metrics, 0, nil,
              Identity));
  Data: TBytes;
  Reader: TOutlineReader;
begin
  Run := Default(TMarkdownGlyphRun);

  Screen := GetDC(0);
  if Screen = 0 then
  begin
    Result := False;
    Exit;
  end;

  try
    Memory := CreateCompatibleDC(Screen);
    if Memory = 0 then
    begin
      Result := False;
      Exit;
    end;

    try
      Font := CreateFont(FamilyName, PixelSize, Bold, Italic);
      if Font = 0 then
      begin
        Result := False;
        Exit;
      end;

      try
        Previous := SelectObject(Memory, Font);
        try
          Pen := 0;

          for Character in Text do
          begin
            Metrics := Default(TGlyphMetrics);
            Size := GetGlyphOutlineW(Memory, Ord(Character), GGO_NATIVE or UnhintedOutline, Metrics, 0, nil,
              Identity);
            if Size = GDI_ERROR then
            begin
              Result := False;
              Exit;
            end;

            if Size > 0 then
            begin
              
              SetLength(Data, Size);
              if GetGlyphOutlineW(Memory, Ord(Character), GGO_NATIVE or UnhintedOutline, Metrics, Size, Data,
                Identity) = GDI_ERROR then
              begin
                Result := False;
                Exit;
              end;

              Reader := TOutlineReader.Create(Data, Pen);
              Run.Contours := Run.Contours + Reader.ReadContours;
            end;

            Pen := Pen + Metrics.gmCellIncX;
          end;

          Run.Advance := Pen;
          Result := Length(Run.Contours) > 0;
        finally
          SelectObject(Memory, Previous);
        end;
      finally
        DeleteObject(Font);
      end;
    finally
      DeleteDC(Memory);
    end;
  finally
    ReleaseDC(0, Screen);
  end;
end;

procedure RegisterGdiGlyphOutliner;
begin
  TMarkdownGlyphSupport.RegisterOutliner(TGdiGlyphOutliner.TryOutline);
end;

initialization
  RegisterGdiGlyphOutliner;

{$ELSE}

// No GDI to ask off Windows; the framework-specific layer registers its own
// outliner there instead, so this unit has nothing left to do.
procedure RegisterGdiGlyphOutliner;
begin
end;

{$ENDIF}

end.
