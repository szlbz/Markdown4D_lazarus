{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Image.Rasterizer;

{$SCOPEDENUMS ON}

// Fills a polygon with anti-aliased edges into a pixel buffer, so a painter on
// a canvas without anti-aliasing of its own can still draw smooth shapes such
// as pie and doughnut wedges.
//
// Coverage is exact horizontally and sampled vertically: every pixel row is cut
// into sub-scanlines, each sub-scanline is intersected with the polygon edges,
// and the resulting spans add their exact horizontal overlap to the pixels they
// touch. That keeps a near-horizontal edge as smooth as a near-vertical one
// without the cost of sampling in both directions.

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  Generics.Collections,
  Markdown4D.Layout.Interfaces;

type
  TMarkdownFillRule = (NonZero, EvenOdd);

  TMarkdownPaintKind = (Solid, LinearGradient, RadialGradient, Tile);

  TMarkdownGradientStop = record
    Offset: Single;
    Color: TLayoutColor;
  end;

  // What a shape is filled with: one colour, or a colour that varies with the
  // position of the pixel. The geometry is in the same space as the contours,
  // so the caller transforms it before handing it over.
  TMarkdownPaint = record
    Kind: TMarkdownPaintKind;
    Color: TLayoutColor;
    StartPoint: TLayoutPointF;
    StopPoint: TLayoutPointF;
    Radius: Single;
    Stops: TArray<TMarkdownGradientStop>;
    // A tile is repeated from its origin in both directions, which is what a
    // pattern fill is.
    TilePixels: TBytes;
    TileWidth: Integer;
    TileHeight: Integer;
    class function SolidColor(const Color: TLayoutColor): TMarkdownPaint; static;
    class function Linear(const StartPoint, StopPoint: TLayoutPointF;
      const Stops: TArray<TMarkdownGradientStop>): TMarkdownPaint; static;
    class function Radial(const Centre: TLayoutPointF; const Radius: Single;
      const Stops: TArray<TMarkdownGradientStop>): TMarkdownPaint; static;
    class function Tiled(const Origin: TLayoutPointF; const Width, Height: Integer;
      const Pixels: TBytes): TMarkdownPaint; static;
    function ColorAt(const X, Y: Single): TLayoutColor;
  end;

  // Per-pixel coverage a fill is multiplied by, so a shape can be held inside
  // another one. Empty means no clipping.
  TMarkdownClipMask = TArray<Byte>;

  // A tightly packed, top-down, premultiplied BGRA buffer (stride = Width * 4),
  // the same shape the SVG rasterizer produces, so both drop into a VCL or FMX
  // bitmap without a per-pixel conversion.
  TMarkdownPixelRaster = record
    Width: Integer;
    Height: Integer;
    Pixels: TBytes;
    class function Create(const Width, Height: Integer): TMarkdownPixelRaster; static;
    function IsEmpty: Boolean;
  end;

  TM4DGen1 = TArray<TArray<TLayoutPointF>>;
  TM4DGen2 = TList<TArray<TLayoutPointF>>;
  TMarkdownPolygonRasterizer = class
  private
    const
      // Sub-scanlines per pixel row. Four steps of coverage in the vertical
      // direction is where the eye stops seeing a staircase on an arc.
      SubScanlines = 4;
      BytesPerPixel = 4;
      FullCoverage = 1.0;
      OpaqueAlpha = 255;
      // Target chord length per segment when flattening a circular arc into a
      // polyline, matching TSvgPathParser.FlatteningStep so a circle looks
      // equally smooth whether an SVG or a rasterizer shape drew it.
      ArcFlatteningStep = 3.0;
      MinArcSegments = 8;
      MaxArcSegments = 128;
      // Past this ratio of miter length to stroke width a sharp corner grows a
      // spike, which is where a bevel join cuts it off square instead.
      MiterLimit = 4.0;
    type
      TEdgeCrossing = record
        X: Single;
        Direction: Integer;
      end;
      // Counts its way along a scanline and says, at each gap between two
      // crossings, whether that gap lies inside the shape.
      TWindingCounter = record
        Total: Integer;
        function Accepts(const Crossing: TEdgeCrossing; const Rule: TMarkdownFillRule): Boolean;
      end;
    class function CollectCrossings(const Contours: TM4DGen1; const SampleY: Single;
      var Crossings: TArray<TEdgeCrossing>): Integer; static;
    class function CrossingCapacity(const Contours: TM4DGen1): Integer; static;
    class procedure SortCrossings(var Crossings: TArray<TEdgeCrossing>; const Count: Integer); static;
    class procedure AddSpan(var Coverage: TArray<Single>; const Left, Right, Weight: Single); static;
    class function JoinContours(const Previous, Corner, Next: TLayoutPointF;
      const HalfWidth: Single): TM4DGen1; static;

  public
    // Fills into a fresh buffer of the given size.
    class function Fill(const Points: TArray<TLayoutPointF>; const Color: TLayoutColor;
      const Width, Height: Integer;
      const Rule: TMarkdownFillRule = TMarkdownFillRule.NonZero): TMarkdownPixelRaster; static;
    // Composites onto what the buffer already holds, so a drawing built from
    // many shapes ends up as one image with its overlaps blended.
    class procedure FillInto(var Raster: TMarkdownPixelRaster; const Points: TArray<TLayoutPointF>;
      const Color: TLayoutColor; const Rule: TMarkdownFillRule = TMarkdownFillRule.NonZero); static;
    // Fills several contours as one shape, which is how a ring, a letter with a
    // counter, or a stroke built from many pieces stays a single figure: the
    // fill rule decides between them, and an overlap is covered once.
    class procedure FillContoursInto(var Raster: TMarkdownPixelRaster;
      const Contours: TM4DGen1; const Color: TLayoutColor;
      const Rule: TMarkdownFillRule = TMarkdownFillRule.NonZero); static;
    // The full form: any paint, and an optional mask the coverage is held to.
    class procedure FillPaintedContoursInto(var Raster: TMarkdownPixelRaster;
      const Contours: TM4DGen1; const Paint: TMarkdownPaint;
      const Rule: TMarkdownFillRule; const Mask: TMarkdownClipMask); static;
    // Coverage of the contours on their own, for use as a mask.
    class function CoverageOf(const Contours: TM4DGen1;
      const Width, Height: Integer; const Rule: TMarkdownFillRule): TMarkdownClipMask; static;
    // How many straight segments a circular arc of this radius needs to read as
    // a curve rather than a polygon: a fixed angle per segment would leave a
    // small join disc wasteful and a large circle faceted, so the count keeps
    // the chord length itself bounded and only clamps at the extremes.
    class function SegmentsForRadius(const Radius: Single): Integer; static;
    // A disc of points around a centre, used as a round join, a round cap, or
    // (at full circle) a plain circular outline in its own right.
    class function Disc(const Centre: TLayoutPointF; const Radius: Single): TArray<TLayoutPointF>; static;
    // Reverses point order if it runs clockwise, so every contour a stroke is
    // built from turns the same way: two overlapping pieces wound against each
    // other would cancel out under the non-zero rule, tearing a hole exactly
    // where the band should be at its thickest.
    class function Anticlockwise(const Points: TArray<TLayoutPointF>): TArray<TLayoutPointF>; static;
    // Turns a path into the band a stroke actually draws: a quad per segment
    // plus a join at every corner (round, or a mitre falling back to a bevel
    // past MiterLimit), filled together as one figure under the non-zero rule
    // so the pieces read as a single outline rather than N overlapping shapes.
    class function StrokeContours(const Points: TArray<TLayoutPointF>; const Closed: Boolean;
      const HalfWidth: Single; const RoundJoins, RoundCaps: Boolean): TM4DGen1; static;
  end;

implementation

uses
  Math;

class function TMarkdownPaint.SolidColor(const Color: TLayoutColor): TMarkdownPaint;
begin
  Result := Default(TMarkdownPaint);
  Result.Kind := TMarkdownPaintKind.Solid;
  Result.Color := Color;
end;

class function TMarkdownPaint.Linear(const StartPoint, StopPoint: TLayoutPointF;
  const Stops: TArray<TMarkdownGradientStop>): TMarkdownPaint;
begin
  Result := Default(TMarkdownPaint);
  Result.Kind := TMarkdownPaintKind.LinearGradient;
  Result.StartPoint := StartPoint;
  Result.StopPoint := StopPoint;
  Result.Stops := Stops;
end;

class function TMarkdownPaint.Radial(const Centre: TLayoutPointF; const Radius: Single;
  const Stops: TArray<TMarkdownGradientStop>): TMarkdownPaint;
begin
  Result := Default(TMarkdownPaint);
  Result.Kind := TMarkdownPaintKind.RadialGradient;
  Result.StartPoint := Centre;
  Result.Radius := Radius;
  Result.Stops := Stops;
end;

class function TMarkdownPaint.Tiled(const Origin: TLayoutPointF; const Width, Height: Integer;
  const Pixels: TBytes): TMarkdownPaint;
begin
  Result := Default(TMarkdownPaint);
  Result.Kind := TMarkdownPaintKind.Tile;
  Result.StartPoint := Origin;
  Result.TileWidth := Width;
  Result.TileHeight := Height;
  Result.TilePixels := Pixels;
end;

// Where the pixel falls along the gradient, and the colour the stops give at
// that distance. Beyond either end the nearest stop simply carries on.
function TMarkdownPaint.ColorAt(const X, Y: Single): TLayoutColor;
var
  Column: Integer;
  Row: Integer;
  Offset: Integer;
  Alpha: Byte;
  Scale: Double;
  Position: Single;
  AxisX: Single;
  AxisY: Single;
  Squared: Single;
  Last: Integer;
  Index: Integer;
  Span: Single;
  Ratio: Single;
  From: TLayoutColor;
  Onto: TLayoutColor;
  Blended: Cardinal;
  Shift: Integer;
  Bits: Integer;
  FromChannel: type of (Integer((From shr Bits) and $FF));
  OntoChannel: type of (Integer((Onto shr Bits) and $FF));
  Channel: type of (EnsureRange(Round(FromChannel + (OntoChannel - FromChannel) * Ratio), 0, 255));
begin
  if Kind = TMarkdownPaintKind.Tile then
  begin
    if (TileWidth <= 0) or (TileHeight <= 0) then
    begin
      Result := 0;
      Exit;
    end;

    Column := Trunc(X - StartPoint.X) mod TileWidth;
    if Column < 0 then
      Column := Column + TileWidth;
    Row := Trunc(Y - StartPoint.Y) mod TileHeight;
    if Row < 0 then
      Row := Row + TileHeight;

    Offset := (Row * TileWidth + Column) * 4;
    Alpha := TilePixels[Offset + 3];
    if Alpha = 0 then
    begin
      Result := 0;
      Exit;
    end;

    // The tile is premultiplied and a paint hands back plain colours, so the
    // coverage baked into the channels is taken back out here.
    Scale := 255 / Alpha;

    Result := TLayoutColor((Cardinal(Alpha) shl 24) or
      (Cardinal(Min(255, Round(TilePixels[Offset + 2] * Scale))) shl 16) or
      (Cardinal(Min(255, Round(TilePixels[Offset + 1] * Scale))) shl 8) or
      Cardinal(Min(255, Round(TilePixels[Offset] * Scale))));
    Exit;
  end;

  if (Kind = TMarkdownPaintKind.Solid) or (Length(Stops) = 0) then
  begin
    Result := Color;
    Exit;
  end;

  Position := 0;

  if Kind = TMarkdownPaintKind.LinearGradient then
  begin
    AxisX := StopPoint.X - StartPoint.X;
    AxisY := StopPoint.Y - StartPoint.Y;
    Squared := AxisX * AxisX + AxisY * AxisY;
    if Squared > 0 then
      Position := ((X - StartPoint.X) * AxisX + (Y - StartPoint.Y) * AxisY) / Squared;
  end
  else if Radius > 0 then
    Position := Sqrt(Sqr(X - StartPoint.X) + Sqr(Y - StartPoint.Y)) / Radius;

  if Position <= Stops[0].Offset then
  begin
    Result := Stops[0].Color;
    Exit;
  end;

  Last := High(Stops);
  if Position >= Stops[Last].Offset then
  begin
    Result := Stops[Last].Color;
    Exit;
  end;

  for Index := 1 to Last do
  begin
    if Position > Stops[Index].Offset then
      Continue;

    Span := Stops[Index].Offset - Stops[Index - 1].Offset;
    Ratio := 0;
    if Span > 0 then
      Ratio := (Position - Stops[Index - 1].Offset) / Span;

    From := Stops[Index - 1].Color;
    Onto := Stops[Index].Color;

    Blended := 0;
    for Shift := 0 to 3 do
    begin
      Bits := Shift * 8;
      // Signed, because one channel darkening towards the next stop is a
      // negative step, and an unsigned one wraps into the channels beside it.
      FromChannel := Integer((From shr Bits) and $FF);
      OntoChannel := Integer((Onto shr Bits) and $FF);
      Channel := EnsureRange(Round(FromChannel + (OntoChannel - FromChannel) * Ratio), 0, 255);

      Blended := Blended or (Cardinal(Channel) shl Bits);
    end;

    Result := TLayoutColor(Blended);
    Exit;
  end;

  Result := Stops[Last].Color;
end;

class function TMarkdownPixelRaster.Create(const Width, Height: Integer): TMarkdownPixelRaster;
begin
  Result.Width := Max(0, Width);
  Result.Height := Max(0, Height);
  SetLength(Result.Pixels, Result.Width * Result.Height * 4);
end;

function TMarkdownPixelRaster.IsEmpty: Boolean;
begin
  Result := (Width <= 0) or (Height <= 0) or (Length(Pixels) = 0);
end;

// Every edge the sample line passes through contributes one crossing, carrying
// the direction it was crossed in so the non-zero rule can tell a hole from a
// second shape. An edge is treated as closed at its top and open at its bottom,
// so a vertex shared by two edges is counted once.
class function TMarkdownPolygonRasterizer.CollectCrossings(const Contours: TM4DGen1;
  const SampleY: Single; var Crossings: TArray<TEdgeCrossing>): Integer;
var
  Contour: TArray<TLayoutPointF>;
  Index: Integer;
  Current: TLayoutPointF;
  NextIndex: Integer;
  Next: TLayoutPointF;
  Rises: Boolean;
  Falls: Boolean;
  Span: Single;
begin
  Result := 0;

  for Contour in Contours do
  begin
    for Index := 0 to High(Contour) do
    begin
      Current := Contour[Index];
      NextIndex := Index + 1;
      if NextIndex > High(Contour) then
        NextIndex := 0;
      Next := Contour[NextIndex];

      Rises := (Current.Y <= SampleY) and (Next.Y > SampleY);
      Falls := (Next.Y <= SampleY) and (Current.Y > SampleY);
      if not (Rises or Falls) then
        Continue;

      Span := Next.Y - Current.Y;
      if Span = 0 then
        Continue;

      Crossings[Result].X := Current.X + (SampleY - Current.Y) / Span * (Next.X - Current.X);
      if Rises then
        Crossings[Result].Direction := 1
      else
        Crossings[Result].Direction := -1;

      Inc(Result);
    end;
  end;
end;

class function TMarkdownPolygonRasterizer.CrossingCapacity(const Contours: TM4DGen1): Integer;
var
  Contour: TArray<TLayoutPointF>;
begin
  Result := 1;

  for Contour in Contours do
  begin
    Inc(Result, Length(Contour));
  end;
end;

// Insertion sort: a scanline crosses a handful of edges even for a shape built
// from hundreds of segments, and the crossings arrive nearly ordered.
class procedure TMarkdownPolygonRasterizer.SortCrossings(var Crossings: TArray<TEdgeCrossing>;
  const Count: Integer);
var
  Index: Integer;
  Current: TEdgeCrossing;
  Position: Integer;
begin
  for Index := 1 to Count - 1 do
  begin
    Current := Crossings[Index];
    Position := Index - 1;

    while (Position >= 0) and (Crossings[Position].X > Current.X) do
    begin
      Crossings[Position + 1] := Crossings[Position];
      Dec(Position);
    end;

    Crossings[Position + 1] := Current;
  end;
end;

// The even-odd rule counts crossings and the non-zero rule counts the direction
// they were crossed in, and both are inside the shape whenever the count is not
// back to nothing.
function TMarkdownPolygonRasterizer.TWindingCounter.Accepts(const Crossing: TEdgeCrossing;
  const Rule: TMarkdownFillRule): Boolean;
begin
  if Rule = TMarkdownFillRule.EvenOdd then
  begin
    Total := Total + 1;
    Result := Odd(Total);
    Exit;
  end;

  Total := Total + Crossing.Direction;
  Result := Total <> 0;
end;

// Adds the exact horizontal overlap of one span to the pixels it touches: the
// two end pixels get their fraction, everything between them gets the lot.
class procedure TMarkdownPolygonRasterizer.AddSpan(var Coverage: TArray<Single>;
  const Left, Right, Weight: Single);
var
  Width: Integer;
  Start: Double;
  Stop: type of (Min(Right, Single(Width)));
  FirstPixel: Int64;
  LastPixel: Integer;
  Pixel: Int64;
begin
  Width := Length(Coverage);
  if (Width = 0) or (Right <= Left) then
    Exit;

  Start := Max(Left, 0.0);
  Stop := Min(Right, Single(Width));
  if Stop <= Start then
    Exit;

  FirstPixel := Trunc(Start);
  LastPixel := Min(Ceil(Stop) - 1, Width - 1);

  if FirstPixel = LastPixel then
  begin
    Coverage[FirstPixel] := Coverage[FirstPixel] + (Stop - Start) * Weight;
    Exit;
  end;

  Coverage[FirstPixel] := Coverage[FirstPixel] + (FirstPixel + 1 - Start) * Weight;

  for Pixel := FirstPixel + 1 to LastPixel - 1 do
  begin
    Coverage[Pixel] := Coverage[Pixel] + Weight;
  end;

  Coverage[LastPixel] := Coverage[LastPixel] + (Stop - LastPixel) * Weight;
end;

class function TMarkdownPolygonRasterizer.Fill(const Points: TArray<TLayoutPointF>;
  const Color: TLayoutColor; const Width, Height: Integer; const Rule: TMarkdownFillRule): TMarkdownPixelRaster;
begin
  Result := TMarkdownPixelRaster.Create(Width, Height);
  if Length(Points) < 3 then
    Exit;

  FillInto(Result, Points, Color, Rule);
end;

class procedure TMarkdownPolygonRasterizer.FillInto(var Raster: TMarkdownPixelRaster;
  const Points: TArray<TLayoutPointF>; const Color: TLayoutColor; const Rule: TMarkdownFillRule);
begin
  FillContoursInto(Raster, [Points], Color, Rule);
end;

class procedure TMarkdownPolygonRasterizer.FillContoursInto(var Raster: TMarkdownPixelRaster;
  const Contours: TM4DGen1; const Color: TLayoutColor; const Rule: TMarkdownFillRule);
begin
  FillPaintedContoursInto(Raster, Contours, TMarkdownPaint.SolidColor(Color), Rule, nil);
end;

class function TMarkdownPolygonRasterizer.CoverageOf(const Contours: TM4DGen1;
  const Width, Height: Integer; const Rule: TMarkdownFillRule): TMarkdownClipMask;
var
  Raster: TMarkdownPixelRaster;
  Index: Integer;
begin
  Raster := TMarkdownPixelRaster.Create(Width, Height);
  FillPaintedContoursInto(Raster, Contours, TMarkdownPaint.SolidColor($FFFFFFFF), Rule, nil);

  SetLength(Result, Width * Height);
  for Index := 0 to High(Result) do
  begin
    Result[Index] := Raster.Pixels[Index * BytesPerPixel + 3];
  end;
end;

class procedure TMarkdownPolygonRasterizer.FillPaintedContoursInto(var Raster: TMarkdownPixelRaster;
  const Contours: TM4DGen1; const Paint: TMarkdownPaint; const Rule: TMarkdownFillRule;
  const Mask: TMarkdownClipMask);
var
  IsSolid: Boolean;
  HasMask: Boolean;
  SampleWeight: Double;
  Crossings: TArray<TEdgeCrossing>;
  Coverage: TArray<Single>;
  Row: Integer;
  Sample: Integer;
  SampleY: Double;
  Count: Integer;
  Winding: TWindingCounter;
  Index: Integer;
  Offset: Integer;
  Column: Integer;
  Covered: Double;
  Color: TLayoutColor;
  Alpha: Integer;
  Weight: Double;
  Remaining: Double;
begin
  if Raster.IsEmpty or (Length(Contours) = 0) then
    Exit;

  IsSolid := (Paint.Kind = TMarkdownPaintKind.Solid);
  if IsSolid and (Paint.Color shr 24 = 0) then
    Exit;

  HasMask := (Length(Mask) = Raster.Width * Raster.Height);
  SampleWeight := FullCoverage / SubScanlines;

  
  SetLength(Crossings, CrossingCapacity(Contours));

  
  SetLength(Coverage, Raster.Width);

  for Row := 0 to Raster.Height - 1 do
  begin
    FillChar(Coverage[0], Length(Coverage) * SizeOf(Single), 0);

    for Sample := 0 to SubScanlines - 1 do
    begin
      SampleY := Row + (Sample + 0.5) / SubScanlines;
      Count := CollectCrossings(Contours, SampleY, Crossings);
      if Count < 2 then
        Continue;

      SortCrossings(Crossings, Count);

      Winding := Default(TWindingCounter);
      for Index := 0 to Count - 2 do
      begin
        if Winding.Accepts(Crossings[Index], Rule) then
          AddSpan(Coverage, Crossings[Index].X, Crossings[Index + 1].X, SampleWeight);
      end;
    end;

    Offset := Row * Raster.Width * BytesPerPixel;
    for Column := 0 to Raster.Width - 1 do
    begin
      Covered := Min(FullCoverage, Max(0.0, Coverage[Column]));

      if HasMask then
        Covered := Covered * Mask[Row * Raster.Width + Column] / OpaqueAlpha;

      if Covered > 0 then
      begin
        Color := Paint.Color;
        if not IsSolid then
          Color := Paint.ColorAt(Column + 0.5, Row + 0.5);

        Alpha := Color shr 24;
        if Alpha > 0 then
        begin
          Weight := Covered * Alpha / OpaqueAlpha;

          // Source-over on premultiplied pixels: what arrives keeps the coverage
          // it was drawn with, and what was already there survives in proportion
          // to the transparency left over.
          Remaining := FullCoverage - Weight;
          Raster.Pixels[Offset] := Round((Color and $FF) * Weight + Raster.Pixels[Offset] * Remaining);
          Raster.Pixels[Offset + 1] :=
            Round(((Color shr 8) and $FF) * Weight + Raster.Pixels[Offset + 1] * Remaining);
          Raster.Pixels[Offset + 2] :=
            Round(((Color shr 16) and $FF) * Weight + Raster.Pixels[Offset + 2] * Remaining);
          Raster.Pixels[Offset + 3] := Round(OpaqueAlpha * Weight + Raster.Pixels[Offset + 3] * Remaining);
        end;
      end;

      Inc(Offset, BytesPerPixel);
    end;
  end;
end;

class function TMarkdownPolygonRasterizer.SegmentsForRadius(const Radius: Single): Integer;
var
  Circumference: Single;
begin
  Circumference := 2 * Pi * Abs(Radius);
  Result := Ceil(Circumference / ArcFlatteningStep);
  Result := Min(MaxArcSegments, Max(MinArcSegments, Result));
end;

class function TMarkdownPolygonRasterizer.Disc(const Centre: TLayoutPointF; const Radius: Single): TArray<TLayoutPointF>;
var
  Segments: Integer;
  Step: Integer;
  Angle: Double;
begin
  Segments := SegmentsForRadius(Radius);
  SetLength(Result, Segments);

  for Step := 0 to Segments - 1 do
  begin
    Angle := 2 * Pi * Step / Segments;
    Result[Step] := TLayoutPointF.Create(Centre.X + Radius * Cos(Angle), Centre.Y + Radius * Sin(Angle));
  end;
end;

class function TMarkdownPolygonRasterizer.Anticlockwise(const Points: TArray<TLayoutPointF>): TArray<TLayoutPointF>;
var
  Area: Double;
  Index: Integer;
  NextIndex: Integer;
  Reversed: TArray<TLayoutPointF>;
begin
  Result := Points;
  if Length(Points) < 3 then
    Exit;

  Area := 0.0;
  for Index := 0 to High(Points) do
  begin
    NextIndex := Index + 1;
    if NextIndex > High(Points) then
      NextIndex := 0;

    Area := Area + Points[Index].X * Points[NextIndex].Y - Points[NextIndex].X * Points[Index].Y;
  end;

  if Area >= 0 then
    Exit;

  // Into a buffer of its own: assigning a dynamic array shares it, so writing
  // the reversal in place would overwrite the points still to be read.
  
  SetLength(Reversed, Length(Points));
  for Index := 0 to High(Points) do
  begin
    Reversed[Index] := Points[High(Points) - Index];
  end;

  Result := Reversed;
end;

class function TMarkdownPolygonRasterizer.StrokeContours(const Points: TArray<TLayoutPointF>; const Closed: Boolean;
  const HalfWidth: Single; const RoundJoins, RoundCaps: Boolean): TM4DGen1;
var
  Contours: TM4DGen2;
  LastSegment: Integer;
  Index: Integer;
  Start: TLayoutPointF;
  StopIndex: Integer;
  Stop: TLayoutPointF;
  DeltaX: Single;
  DeltaY: Single;
  Span: Double;
  NormalX: Double;
  NormalY: Double;
  FirstCorner: Integer;
  LastCorner: Integer;
  Corner: Integer;
  PreviousIndex: Integer;
  NextIndex: Integer;
begin
  Result := nil;
  if Length(Points) < 2 then
    Exit;

  // Collected in a list rather than grown one concatenation at a time: a
  // flattened curve can leave the source path with a great many points, and
  // each of those contributes at least one contour here.
  Contours := TM4DGen2.Create;
  try
    LastSegment := High(Points) - 1;
    if Closed then
      LastSegment := High(Points);

    for Index := 0 to LastSegment do
    begin
      Start := Points[Index];
      StopIndex := Index + 1;
      if StopIndex > High(Points) then
        StopIndex := 0;
      Stop := Points[StopIndex];

      DeltaX := Stop.X - Start.X;
      DeltaY := Stop.Y - Start.Y;
      Span := Sqrt(DeltaX * DeltaX + DeltaY * DeltaY);
      if Span = 0 then
        Continue;

      NormalX := -DeltaY / Span * HalfWidth;
      NormalY := DeltaX / Span * HalfWidth;

      Contours.Add(Anticlockwise([TLayoutPointF.Create(Start.X + NormalX, Start.Y + NormalY),
        TLayoutPointF.Create(Stop.X + NormalX, Stop.Y + NormalY),
        TLayoutPointF.Create(Stop.X - NormalX, Stop.Y - NormalY),
        TLayoutPointF.Create(Start.X - NormalX, Start.Y - NormalY)]));
    end;

    FirstCorner := 1;
    LastCorner := High(Points) - 1;
    if Closed then
    begin
      FirstCorner := 0;
      LastCorner := High(Points);
    end;

    for Corner := FirstCorner to LastCorner do
    begin
      PreviousIndex := Corner - 1;
      if PreviousIndex < 0 then
        PreviousIndex := High(Points);
      NextIndex := Corner + 1;
      if NextIndex > High(Points) then
        NextIndex := 0;

      if RoundJoins then
        Contours.Add(Anticlockwise(Disc(Points[Corner], HalfWidth)))
      else
        Contours.AddRange(JoinContours(Points[PreviousIndex], Points[Corner], Points[NextIndex], HalfWidth));
    end;

    if Closed or (not RoundCaps) then
      Exit;

    Contours.Add(Anticlockwise(Disc(Points[0], HalfWidth)));
    Contours.Add(Anticlockwise(Disc(Points[High(Points)], HalfWidth)));
  finally
    Result := Contours.ToArray;
    Contours.Free;
  end;
end;

// Closes the wedge two segments leave between them. The bevel triangle covers
// the corner itself; the mitre tip extends it to the point the two edges would
// meet at, unless that point runs away from the corner.
class function TMarkdownPolygonRasterizer.JoinContours(const Previous, Corner, Next: TLayoutPointF;
  const HalfWidth: Single): TM4DGen1;
var
  InX: Single;
  InY: Single;
  OutX: Single;
  OutY: Single;
  InLength: Double;
  OutLength: Double;
  InNormalX: Double;
  InNormalY: Double;
  OutNormalX: Double;
  OutNormalY: Double;
  Side: Integer;
  FromX: Double;
  FromY: Double;
  ToX: Double;
  ToY: Double;
  Denominator: Double;
  GapX: Double;
  GapY: Double;
  Travel: Double;
  TipX: Double;
  TipY: Double;
  Reach: Double;
begin
  Result := nil;

  InX := Corner.X - Previous.X;
  InY := Corner.Y - Previous.Y;
  OutX := Next.X - Corner.X;
  OutY := Next.Y - Corner.Y;

  InLength := Sqrt(InX * InX + InY * InY);
  OutLength := Sqrt(OutX * OutX + OutY * OutY);
  if (InLength = 0) or (OutLength = 0) then
    Exit;

  InNormalX := -InY / InLength * HalfWidth;
  InNormalY := InX / InLength * HalfWidth;
  OutNormalX := -OutY / OutLength * HalfWidth;
  OutNormalY := OutX / OutLength * HalfWidth;

  for Side in [1, -1] do
  begin
    FromX := Corner.X + Side * InNormalX;
    FromY := Corner.Y + Side * InNormalY;
    ToX := Corner.X + Side * OutNormalX;
    ToY := Corner.Y + Side * OutNormalY;

    Result := Result + [Anticlockwise([Corner, TLayoutPointF.Create(FromX, FromY),
      TLayoutPointF.Create(ToX, ToY)])];

    // Where the two offset edges cross is the tip of the mitre.
    Denominator := InX / InLength * (OutY / OutLength) - InY / InLength * (OutX / OutLength);
    if Abs(Denominator) < 0.0001 then
      Continue;

    GapX := ToX - FromX;
    GapY := ToY - FromY;
    Travel := (GapX * (OutY / OutLength) - GapY * (OutX / OutLength)) / Denominator;

    TipX := FromX + InX / InLength * Travel;
    TipY := FromY + InY / InLength * Travel;

    Reach := Sqrt(Sqr(TipX - Corner.X) + Sqr(TipY - Corner.Y));
    if Reach > MiterLimit * HalfWidth then
      Continue;

    Result := Result + [Anticlockwise([TLayoutPointF.Create(FromX, FromY),
      TLayoutPointF.Create(TipX, TipY), TLayoutPointF.Create(ToX, ToY)])];
  end;
end;

end.
