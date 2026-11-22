unit Markdown4D.Lcl.Painter;
{ The IPainter the layout engine draws through, over an LCL canvas.

  Layout coordinates are document units; the painter scales and offsets them on
  the way out, so zooming and scrolling never touch the layout.  Text is always
  measured in those units - the engine lays out at scale 1 - and only the font
  used for drawing is scaled.

  An LCL canvas has no alpha channel, so a translucent colour is flattened
  against Background before it is drawn: the result is right on a plain page and
  close enough over other content, without dragging a software rasteriser in. }

{$mode delphiunicode}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}

interface

uses
  Classes, SysUtils, Graphics, Types, Math, LCLIntf, LCLType,
  Markdown4D.Layout.Interfaces;

type
  // Hands back the picture a `![alt](source)` refers to, or nil while it is
  // still being fetched. The callee keeps ownership: the same picture is drawn
  // on every repaint.
  TMarkdownImageResolver = function(const Source: string): TGraphic of object;
  // True once a source is known not to load, so a cross is drawn instead of an
  // empty frame.
  TMarkdownBrokenImageQuery = function(const Source: string): Boolean of object;

  TMarkdownLclPainter = class(TInterfacedObject, IPainter)
  private
    type
      TFontEntry = class
      public
        Font: TFont;
        Metrics: TTextMetric;
        destructor Destroy; override;
      end;
  private
    FCanvas: TCanvas;
    FScale: Single;
    FOriginX: Single;
    FOriginY: Single;
    FBackground: TColor;
    FFonts: TStringList;
    FMeasuring: TBitmap;
    FClipStack: array of TRect;
    FImageResolver: TMarkdownImageResolver;
    FBrokenImageQuery: TMarkdownBrokenImageQuery;
    function EntryFor(const Style: TMarkdownFontStyle; const FontScale: Single): TFontEntry;
    function Blended(const Color: TLayoutColor): TColor;
    function Scaled(const Value: Single): Integer;
    function PointOf(const Point: TLayoutPointF): TPoint;
    function RectOf(const Bounds: TLayoutRectF): TRect;
    procedure Polygon(const Points: TArray<TLayoutPointF>; const Color: TLayoutColor;
      const StrokeWidth: Single; const Filled: Boolean);
    procedure SetupPen(const Color: TLayoutColor; const StrokeWidth: Single);
  public
    constructor Create(const Canvas: TCanvas);
    destructor Destroy; override;

    // Document units -> device pixels.
    property Scale: Single read FScale write FScale;
    property OriginX: Single read FOriginX write FOriginX;
    property OriginY: Single read FOriginY write FOriginY;
    // What translucent colours are flattened onto.
    property Background: TColor read FBackground write FBackground;
    property ImageResolver: TMarkdownImageResolver
      read FImageResolver write FImageResolver;
    property BrokenImageQuery: TMarkdownBrokenImageQuery
      read FBrokenImageQuery write FBrokenImageQuery;

    function MeasureText(const Text: string; const Font: TMarkdownFontStyle): TLayoutSizeF;
    function LineHeight(const Font: TMarkdownFontStyle): Single;
    function Baseline(const Font: TMarkdownFontStyle): Single;

    procedure DrawTextRun(const TopLeft: TLayoutPointF; const Text: string;
      const Font: TMarkdownFontStyle; const Color: TLayoutColor);
    procedure FillRect(const Bounds: TLayoutRectF; const Color: TLayoutColor);
    procedure DrawRect(const Bounds: TLayoutRectF; const Color: TLayoutColor;
      const StrokeWidth: Single);
    procedure DrawLine(const StartPoint, EndPoint: TLayoutPointF;
      const Color: TLayoutColor; const StrokeWidth: Single);
    procedure DrawImage(const Bounds: TLayoutRectF; const Source: string;
      const SourceRect: TLayoutRectF);
    procedure FillWedge(const Center: TLayoutPointF; const OuterRadius,
      InnerRadius, StartAngle, SweepAngle: Single; const Color: TLayoutColor);
    procedure DrawWedge(const Center: TLayoutPointF; const OuterRadius,
      InnerRadius, StartAngle, SweepAngle: Single; const Color: TLayoutColor;
      const StrokeWidth: Single);
    procedure FillPolygon(const Points: TArray<TLayoutPointF>; const Color: TLayoutColor);
    procedure DrawPolygon(const Points: TArray<TLayoutPointF>;
      const Color: TLayoutColor; const StrokeWidth: Single);
    procedure SaveState;
    procedure SetClip(const Bounds: TLayoutRectF);
    procedure RestoreState;
  end;

function LayoutColorToColor(const Color: TLayoutColor): TColor;
function ColorAlphaOf(const Color: TLayoutColor): Byte;

implementation

const
  // A wedge is a filled polygon rather than a canvas arc: the same code then
  // strokes a doughnut hole and a plain pie the same way.
  WedgeSegmentsPerTurn = 96;
  PlaceholderBorderColor = TLayoutColor($FF9E9E9E);
  PlaceholderStrokeWidth = 1.0;
  BrokenImageCrossColor = TLayoutColor($FFC0392B);

function LayoutColorToColor(const Color: TLayoutColor): TColor;
begin
  Result := TColor(RGB(Byte(Color shr 16), Byte(Color shr 8), Byte(Color)));
end;

function ColorAlphaOf(const Color: TLayoutColor): Byte;
begin
  Result := Byte(Color shr 24);
end;

destructor TMarkdownLclPainter.TFontEntry.Destroy;
begin
  Font.Free;
  inherited Destroy;
end;

constructor TMarkdownLclPainter.Create(const Canvas: TCanvas);
begin
  inherited Create;
  FCanvas := Canvas;
  FScale := 1;
  FBackground := clWhite;
  FFonts := TStringList.Create;
  FFonts.CaseSensitive := False;
  FFonts.Sorted := True;
  FFonts.OwnsObjects := True;
  FMeasuring := TBitmap.Create;
  FMeasuring.SetSize(64, 64);
end;

destructor TMarkdownLclPainter.Destroy;
begin
  FFonts.Free;
  FMeasuring.Free;
  inherited Destroy;
end;

function TMarkdownLclPainter.EntryFor(const Style: TMarkdownFontStyle;
  const FontScale: Single): TFontEntry;
var
  Key: string;
  Index: Integer;
  Entry: TFontEntry;
  Metrics: TTextMetric;
begin
  Key := Format('%.2f|%s|%.2f|%d|%d|%d|%d', [FontScale, Style.FamilyName,
    Style.Size, Ord(Style.Bold), Ord(Style.Italic), Ord(Style.Underline),
    Ord(Style.Strikeout)]);
  if FFonts.Find(Key, Index) then
    Exit(TFontEntry(FFonts.Objects[Index]));

  Entry := TFontEntry.Create;
  Entry.Font := TFont.Create;
  if Style.FamilyName <> '' then
    Entry.Font.Name := Style.FamilyName;
  // a negative height is the em size in pixels, which is what the layout uses
  Entry.Font.Height := -Max(1, Round(Style.Size * FontScale));
  Entry.Font.Style := [];
  if Style.Bold then
    Entry.Font.Style := Entry.Font.Style + [fsBold];
  if Style.Italic then
    Entry.Font.Style := Entry.Font.Style + [fsItalic];
  if Style.Underline then
    Entry.Font.Style := Entry.Font.Style + [fsUnderline];
  if Style.Strikeout then
    Entry.Font.Style := Entry.Font.Style + [fsStrikeOut];

  // Ascent and leading come from the device, so they are read once per font
  // rather than per run of text.
  FillChar(Metrics, SizeOf(Metrics), 0);
  FMeasuring.Canvas.Font.Assign(Entry.Font);
  GetTextMetrics(FMeasuring.Canvas.Handle, Metrics);
  if Metrics.tmHeight <= 0 then
  begin
    // a widgetset that does not report metrics: fall back on the measured text
    Metrics.tmHeight := FMeasuring.Canvas.TextHeight('Mg');
    Metrics.tmAscent := Metrics.tmHeight;
  end;
  Entry.Metrics := Metrics;

  FFonts.AddObject(Key, Entry);
  Result := Entry;
end;

function TMarkdownLclPainter.Blended(const Color: TLayoutColor): TColor;
var
  Alpha: Integer;
  Red, Green, Blue: Integer;
begin
  Alpha := ColorAlphaOf(Color);
  if Alpha >= 255 then
    Exit(LayoutColorToColor(Color));
  Red := Byte(Color shr 16);
  Green := Byte(Color shr 8);
  Blue := Byte(Color);
  Red := (Red * Alpha + GetRValue(FBackground) * (255 - Alpha)) div 255;
  Green := (Green * Alpha + GetGValue(FBackground) * (255 - Alpha)) div 255;
  Blue := (Blue * Alpha + GetBValue(FBackground) * (255 - Alpha)) div 255;
  Result := TColor(RGB(Red, Green, Blue));
end;

function TMarkdownLclPainter.Scaled(const Value: Single): Integer;
begin
  Result := Round(Value * FScale);
end;

function TMarkdownLclPainter.PointOf(const Point: TLayoutPointF): TPoint;
begin
  Result.X := Round(Point.X * FScale + FOriginX);
  Result.Y := Round(Point.Y * FScale + FOriginY);
end;

function TMarkdownLclPainter.RectOf(const Bounds: TLayoutRectF): TRect;
begin
  Result.Left := Round(Bounds.Left * FScale + FOriginX);
  Result.Top := Round(Bounds.Top * FScale + FOriginY);
  Result.Right := Round(Bounds.Right * FScale + FOriginX);
  Result.Bottom := Round(Bounds.Bottom * FScale + FOriginY);
end;

function TMarkdownLclPainter.MeasureText(const Text: string;
  const Font: TMarkdownFontStyle): TLayoutSizeF;
var
  Entry: TFontEntry;
  Size: TSize;
begin
  Entry := EntryFor(Font, 1);
  if Text = '' then
    Exit(TLayoutSizeF.Create(0, Entry.Metrics.tmHeight + Entry.Metrics.tmExternalLeading));
  FMeasuring.Canvas.Font.Assign(Entry.Font);
  Size := FMeasuring.Canvas.TextExtent(Text);
  Result := TLayoutSizeF.Create(Size.cx,
    Entry.Metrics.tmHeight + Entry.Metrics.tmExternalLeading);
end;

function TMarkdownLclPainter.LineHeight(const Font: TMarkdownFontStyle): Single;
var
  Entry: TFontEntry;
begin
  Entry := EntryFor(Font, 1);
  Result := Entry.Metrics.tmHeight + Entry.Metrics.tmExternalLeading;
end;

function TMarkdownLclPainter.Baseline(const Font: TMarkdownFontStyle): Single;
begin
  Result := EntryFor(Font, 1).Metrics.tmAscent;
end;

procedure TMarkdownLclPainter.DrawTextRun(const TopLeft: TLayoutPointF;
  const Text: string; const Font: TMarkdownFontStyle; const Color: TLayoutColor);
var
  Point: TPoint;
begin
  if (Text = '') or (ColorAlphaOf(Color) = 0) then
    Exit;
  FCanvas.Font.Assign(EntryFor(Font, FScale).Font);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Pen.Style := psClear;
  FCanvas.Font.Color := Blended(Color);
  // the layout positions the top of the line box, and a top-aligned draw puts
  // the ascent of the cell there, which is the same place
  Point := PointOf(TopLeft);
  FCanvas.TextOut(Point.X, Point.Y, Text);
end;

procedure TMarkdownLclPainter.FillRect(const Bounds: TLayoutRectF;
  const Color: TLayoutColor);
var
  Box: TRect;
begin
  if ColorAlphaOf(Color) = 0 then
    Exit;
  Box := RectOf(Bounds);
  if (Box.Right <= Box.Left) or (Box.Bottom <= Box.Top) then
    Exit;
  FCanvas.Brush.Color := Blended(Color);
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Pen.Style := psClear;
  FCanvas.FillRect(Box);
end;

procedure TMarkdownLclPainter.SetupPen(const Color: TLayoutColor;
  const StrokeWidth: Single);
begin
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Color := Blended(Color);
  FCanvas.Pen.Width := Max(1, Scaled(StrokeWidth));
  FCanvas.Brush.Style := bsClear;
end;

procedure TMarkdownLclPainter.DrawRect(const Bounds: TLayoutRectF;
  const Color: TLayoutColor; const StrokeWidth: Single);
var
  Box: TRect;
  Width: Integer;
begin
  if (ColorAlphaOf(Color) = 0) or (StrokeWidth <= 0) then
    Exit;
  Box := RectOf(Bounds);
  if (Box.Right <= Box.Left) or (Box.Bottom <= Box.Top) then
    Exit;
  SetupPen(Color, StrokeWidth);
  Width := FCanvas.Pen.Width;
  // a pen of width n straddles the path; the layout box is the outer edge
  InflateRect(Box, -(Width div 2), -(Width div 2));
  FCanvas.Rectangle(Box);
end;

procedure TMarkdownLclPainter.DrawLine(const StartPoint, EndPoint: TLayoutPointF;
  const Color: TLayoutColor; const StrokeWidth: Single);
var
  FromPoint, ToPoint: TPoint;
begin
  if (ColorAlphaOf(Color) = 0) or (StrokeWidth <= 0) then
    Exit;
  FromPoint := PointOf(StartPoint);
  ToPoint := PointOf(EndPoint);
  SetupPen(Color, StrokeWidth);
  FCanvas.Line(FromPoint.X, FromPoint.Y, ToPoint.X, ToPoint.Y);
end;

procedure TMarkdownLclPainter.DrawImage(const Bounds: TLayoutRectF;
  const Source: string; const SourceRect: TLayoutRectF);
var
  Graphic: TGraphic;
  Box: TRect;
  Target: TRect;
  ScaleX, ScaleY: Single;
  Width, Height: Integer;
begin
  Graphic := nil;
  if Assigned(FImageResolver) then
    Graphic := FImageResolver(Source);

  if (Graphic = nil) or Graphic.Empty then
  begin
    DrawRect(Bounds, PlaceholderBorderColor, PlaceholderStrokeWidth);
    if Assigned(FBrokenImageQuery) and FBrokenImageQuery(Source) then
    begin
      DrawLine(TLayoutPointF.Create(Bounds.Left, Bounds.Top),
        TLayoutPointF.Create(Bounds.Right, Bounds.Bottom),
        BrokenImageCrossColor, PlaceholderStrokeWidth);
      DrawLine(TLayoutPointF.Create(Bounds.Right, Bounds.Top),
        TLayoutPointF.Create(Bounds.Left, Bounds.Bottom),
        BrokenImageCrossColor, PlaceholderStrokeWidth);
    end;
    Exit;
  end;

  Box := RectOf(Bounds);
  if (Box.Right <= Box.Left) or (Box.Bottom <= Box.Top) then
    Exit;

  if (SourceRect.Width <= 0) or (SourceRect.Height <= 0) then
  begin
    FCanvas.StretchDraw(Box, Graphic);
    Exit;
  end;

  // the layout reserved the box for part of the picture, so the stretch is
  // computed against the whole of it and the rest is clipped away
  ScaleX := Box.Width / SourceRect.Width;
  ScaleY := Box.Height / SourceRect.Height;
  Width := Graphic.Width;
  Height := Graphic.Height;
  Target.Left := Box.Left - Round(SourceRect.Left * ScaleX);
  Target.Top := Box.Top - Round(SourceRect.Top * ScaleY);
  Target.Right := Target.Left + Round(Width * ScaleX);
  Target.Bottom := Target.Top + Round(Height * ScaleY);

  SaveState;
  try
    SetClip(Bounds);
    FCanvas.StretchDraw(Target, Graphic);
  finally
    RestoreState;
  end;
end;

procedure TMarkdownLclPainter.Polygon(const Points: TArray<TLayoutPointF>;
  const Color: TLayoutColor; const StrokeWidth: Single; const Filled: Boolean);
var
  Index: Integer;
  Device: array of TPoint;
begin
  if Length(Points) < 2 then
    Exit;
  if ColorAlphaOf(Color) = 0 then
    Exit;
  SetLength(Device, Length(Points));
  for Index := 0 to High(Points) do
    Device[Index] := PointOf(Points[Index]);
  if Filled then
  begin
    FCanvas.Brush.Color := Blended(Color);
    FCanvas.Brush.Style := bsSolid;
    if StrokeWidth > 0 then
      SetupPen(Color, StrokeWidth)
    else
    begin
      FCanvas.Pen.Style := psClear;
      FCanvas.Pen.Width := 1;
    end;
  end
  else
    SetupPen(Color, StrokeWidth);
  FCanvas.Polygon(Device);
end;

function WedgeOutline(const Center: TLayoutPointF; const OuterRadius,
  InnerRadius, StartAngle, SweepAngle: Single): TArray<TLayoutPointF>;
var
  Steps: Integer;
  Index: Integer;
  Angle: Single;
  Radians: Single;
  Points: TArray<TLayoutPointF>;
  Count: Integer;
begin
  Steps := Max(2, Round(Abs(SweepAngle) / 360 * WedgeSegmentsPerTurn));
  SetLength(Points, Steps * 2 + 2);
  Count := 0;
  for Index := 0 to Steps do
  begin
    Angle := StartAngle + SweepAngle * Index / Steps;
    Radians := DegToRad(Angle);
    Points[Count] := TLayoutPointF.Create(Center.X + OuterRadius * Cos(Radians),
      Center.Y + OuterRadius * Sin(Radians));
    Inc(Count);
  end;
  if InnerRadius > 0 then
    for Index := Steps downto 0 do
    begin
      Angle := StartAngle + SweepAngle * Index / Steps;
      Radians := DegToRad(Angle);
      Points[Count] := TLayoutPointF.Create(Center.X + InnerRadius * Cos(Radians),
        Center.Y + InnerRadius * Sin(Radians));
      Inc(Count);
    end;
  SetLength(Points, Count);
  Result := Points;
end;

procedure TMarkdownLclPainter.FillWedge(const Center: TLayoutPointF;
  const OuterRadius, InnerRadius, StartAngle, SweepAngle: Single;
  const Color: TLayoutColor);
begin
  if (OuterRadius <= 0) or (SweepAngle = 0) then
    Exit;
  Polygon(WedgeOutline(Center, OuterRadius, InnerRadius, StartAngle, SweepAngle),
    Color, 0, True);
end;

procedure TMarkdownLclPainter.DrawWedge(const Center: TLayoutPointF;
  const OuterRadius, InnerRadius, StartAngle, SweepAngle: Single;
  const Color: TLayoutColor; const StrokeWidth: Single);
begin
  if (OuterRadius <= 0) or (SweepAngle = 0) or (StrokeWidth <= 0) then
    Exit;
  Polygon(WedgeOutline(Center, OuterRadius, InnerRadius, StartAngle, SweepAngle),
    Color, StrokeWidth, False);
end;

procedure TMarkdownLclPainter.FillPolygon(const Points: TArray<TLayoutPointF>;
  const Color: TLayoutColor);
begin
  Polygon(Points, Color, 0, True);
end;

procedure TMarkdownLclPainter.DrawPolygon(const Points: TArray<TLayoutPointF>;
  const Color: TLayoutColor; const StrokeWidth: Single);
begin
  Polygon(Points, Color, StrokeWidth, False);
end;

procedure TMarkdownLclPainter.SaveState;
var
  Index: Integer;
begin
  // TCanvas has one clip rectangle, so the nesting the engine expects has to be
  // kept here; SetClip narrows what is current, RestoreState puts it back.
  Index := Length(FClipStack);
  SetLength(FClipStack, Index + 1);
  FClipStack[Index] := FCanvas.ClipRect;
end;

procedure TMarkdownLclPainter.SetClip(const Bounds: TLayoutRectF);
var
  Box: TRect;
begin
  Box := RectOf(Bounds);
  // TCanvas only honours ClipRect while Clipping is on, and assigning a
  // ClipRect replaces the region instead of narrowing it, so the narrowing is
  // done here against whatever is in force.
  IntersectRect(Box, Box, FCanvas.ClipRect);
  FCanvas.Clipping := True;
  FCanvas.ClipRect := Box;
end;

procedure TMarkdownLclPainter.RestoreState;
begin
  if Length(FClipStack) = 0 then
  begin
    FCanvas.Clipping := False;
    Exit;
  end;
  FCanvas.ClipRect := FClipStack[High(FClipStack)];
  SetLength(FClipStack, Length(FClipStack) - 1);
  if Length(FClipStack) = 0 then
    FCanvas.Clipping := False;
end;

end.
