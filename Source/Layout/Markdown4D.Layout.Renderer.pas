{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Layout.Renderer;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Layout.Interfaces,
  Markdown4D.Layout.DisplayList,
  Markdown4D.Compat.Str,
  character;

type
  TMarkdownDisplayListRenderer = class
  private
    const
      CheckboxBorderColor = TLayoutColor($FF8C959F);
      CheckboxMarkColor = TLayoutColor($FF1F883D);
      CheckboxBorderStrokeWidthFactor = 0.0625;
      CheckboxMinimumBorderStrokeWidth = 1;
      CheckboxMarkStrokeWidthFactor = 0.125;
      CheckboxMarkCapSegments = 8;
      CheckboxMarkStartXFactor = 0.22;
      CheckboxMarkStartYFactor = 0.55;
      CheckboxMarkMiddleXFactor = 0.42;
      CheckboxMarkMiddleYFactor = 0.74;
      CheckboxMarkEndXFactor = 0.78;
      CheckboxMarkEndYFactor = 0.3;
      UnhandledItemKindMessage = 'Unhandled display item kind: %d';
    class function AlphaOf(const Color: TLayoutColor): Byte;
    class function IsVisible(const Bounds, Viewport: TLayoutRectF): Boolean;
    class procedure RenderItem(const Item: IDisplayItem; const Painter: IPainter);
    class procedure RenderTextRun(const Run: IDisplayTextRun; const Painter: IPainter);
    class procedure RenderRectangle(const Rectangle: IDisplayRectangle; const Painter: IPainter);
    class procedure RenderLine(const Line: IDisplayLine; const Painter: IPainter);
    class procedure RenderImage(const Image: IDisplayImage; const Painter: IPainter);
    class procedure RenderCheckbox(const Checkbox: IDisplayCheckbox; const Painter: IPainter);
    class function PixelAlignedBox(const Bounds: TLayoutRectF): TLayoutRectF;
    class function BorderStrokeWidth(const Box: TLayoutRectF): Single;
    class function CheckMarkOutline(const Box: TLayoutRectF): TArray<TLayoutPointF>;
    class function PointInBox(const Box: TLayoutRectF; const XFactor, YFactor: Single): TLayoutPointF;
    class function BentStrokeOutline(const StartPoint, CornerPoint, EndPoint: TLayoutPointF;
      const HalfWidth: Single): TArray<TLayoutPointF>;
    class function DirectionOf(const FromPoint, ToPoint: TLayoutPointF): Single;
    class function TurnBetween(const IncomingAngle, OutgoingAngle: Single): Single;
    class function RoundCap(const Center: TLayoutPointF; const StartAngle, Radius: Single): TArray<TLayoutPointF>;
    class function PointAt(const Origin: TLayoutPointF; const Angle, Distance: Single): TLayoutPointF;
    class procedure RenderWedge(const Wedge: IDisplayWedge; const Painter: IPainter);
    class procedure RenderPolygon(const Polygon: IDisplayPolygon; const Painter: IPainter);
    class procedure RenderDisclosure(const Disclosure: IDisplayDisclosure; const Painter: IPainter);
    class procedure RenderScroller(const DisplayList: IMarkdownDisplayList; const Index: Integer;
      const Painter: IPainter; const Viewport: TLayoutRectF);
    class function DisclosureTriangle(const Marker: TLayoutRectF; const IsOpen: Boolean): TArray<TLayoutPointF>;

  public
    class procedure Render(const DisplayList: IMarkdownDisplayList; const Painter: IPainter;
      const Viewport: TLayoutRectF; const BackgroundColor: TLayoutColor);
  end;

implementation

uses
  Math,
  Markdown4D.Defines;

class procedure TMarkdownDisplayListRenderer.Render(const DisplayList: IMarkdownDisplayList; const Painter: IPainter;
  const Viewport: TLayoutRectF; const BackgroundColor: TLayoutColor);
var
  Index: Integer;
  Item: IDisplayItem;
begin
  if AlphaOf(BackgroundColor) > 0 then
    Painter.FillRect(Viewport, BackgroundColor);

  if DisplayList = nil then
    Exit;

  Painter.SaveState;
  try
    Painter.SetClip(Viewport);

    Index := 0;
    while Index < DisplayList.ItemCount do
    begin
      Item := DisplayList.Items[Index];
      if Item.Kind = TDisplayItemKind.Scroller then
      begin
        if IsVisible(Item.Bounds, Viewport) then
          RenderScroller(DisplayList, Index, Painter, Viewport);
        Index := Index + 1 + (Item as IDisplayScroller).ItemCount;
        Continue;
      end;

      if IsVisible(Item.Bounds, Viewport) then
        RenderItem(Item, Painter);
      Inc(Index);
    end;
  finally
    Painter.RestoreState;
  end;
end;

class function TMarkdownDisplayListRenderer.AlphaOf(const Color: TLayoutColor): Byte;
begin
  Result := Color shr 24;
end;

class function TMarkdownDisplayListRenderer.IsVisible(const Bounds, Viewport: TLayoutRectF): Boolean;
begin
  Result := (Bounds.Bottom >= Viewport.Top) and (Bounds.Top <= Viewport.Bottom);
end;

class procedure TMarkdownDisplayListRenderer.RenderItem(const Item: IDisplayItem; const Painter: IPainter);
begin
  case Item.Kind of
    TDisplayItemKind.TextRun:
      RenderTextRun(Item as IDisplayTextRun, Painter);
    TDisplayItemKind.Rectangle:
      RenderRectangle(Item as IDisplayRectangle, Painter);
    TDisplayItemKind.Line:
      RenderLine(Item as IDisplayLine, Painter);
    TDisplayItemKind.Image:
      RenderImage(Item as IDisplayImage, Painter);
    TDisplayItemKind.Checkbox:
      RenderCheckbox(Item as IDisplayCheckbox, Painter);
    TDisplayItemKind.Wedge:
      RenderWedge(Item as IDisplayWedge, Painter);
    TDisplayItemKind.Polygon:
      RenderPolygon(Item as IDisplayPolygon, Painter);
    TDisplayItemKind.Disclosure:
      RenderDisclosure(Item as IDisplayDisclosure, Painter);
    TDisplayItemKind.Scroller:
      ; // Render draws a scroller together with the content it clips.
  else
    raise EMarkdownError.CreateFmt(UnhandledItemKindMessage, [Ord(Item.Kind)]);
  end;
end;

// The content of a scroller is clipped to its band; the track below it
// shows, as a thin bar, which part of the content is in view.
class procedure TMarkdownDisplayListRenderer.RenderScroller(const DisplayList: IMarkdownDisplayList;
  const Index: Integer; const Painter: IPainter; const Viewport: TLayoutRectF);
const
  TrackColor = TLayoutColor($20808080);
  ThumbColor = TLayoutColor($90808080);
var
  Scroller: IDisplayScroller;
  Bounds: type of (Scroller.Bounds);
  Clip: TLayoutRectF;
  LastIndex: Integer;
  ContentIndex: Integer;
  Item: IDisplayItem;
begin
  Scroller := DisplayList.Items[Index] as IDisplayScroller;
  Bounds := Scroller.Bounds;
  Clip := TLayoutRectF.Create(Max(Bounds.Left, Viewport.Left), Max(Bounds.Top, Viewport.Top),
    Min(Bounds.Right, Viewport.Right), Min(Bounds.Bottom, Viewport.Bottom));

  Painter.SaveState;
  try
    Painter.SetClip(Clip);
    LastIndex := Min(Index + Scroller.ItemCount, DisplayList.ItemCount - 1);
    for ContentIndex := Index + 1 to LastIndex do
    begin
      Item := DisplayList.Items[ContentIndex];
      if IsVisible(Item.Bounds, Viewport) then
        RenderItem(Item, Painter);
    end;
  finally
    Painter.RestoreState;
  end;

  Painter.FillRect(Scroller.Track, TrackColor);
  Painter.FillRect(Scroller.Thumb, ThumbColor);
end;

class procedure TMarkdownDisplayListRenderer.RenderTextRun(const Run: IDisplayTextRun; const Painter: IPainter);
var
  IsSource: Boolean;
  TopY: Single;
begin
  // A source run exists for selection and copy; the drawing it stands for is
  // painted by the runs around it.
  IsSource := (Run.Role = TDisplayTextRunRole.Source);
  if IsSource then
    Exit;

  TopY := Run.Bounds.Top + Run.Baseline - Painter.Baseline(Run.Font);
  Painter.DrawTextRun(TLayoutPointF.Create(Run.Bounds.Left, TopY), Run.Text, Run.Font, Run.Color);
end;

class procedure TMarkdownDisplayListRenderer.RenderRectangle(const Rectangle: IDisplayRectangle;
  const Painter: IPainter);
var
  HasStroke: Boolean;
begin
  if AlphaOf(Rectangle.FillColor) > 0 then
    Painter.FillRect(Rectangle.Bounds, Rectangle.FillColor);

  HasStroke := (Rectangle.StrokeWidth > 0) and (AlphaOf(Rectangle.StrokeColor) > 0);
  if HasStroke then
    Painter.DrawRect(Rectangle.Bounds, Rectangle.StrokeColor, Rectangle.StrokeWidth);
end;

class procedure TMarkdownDisplayListRenderer.RenderLine(const Line: IDisplayLine; const Painter: IPainter);
begin
  Painter.DrawLine(Line.StartPoint, Line.EndPoint, Line.Color, Line.StrokeWidth);
end;

class procedure TMarkdownDisplayListRenderer.RenderImage(const Image: IDisplayImage; const Painter: IPainter);
begin
  Painter.SaveState;
  try
    Painter.SetClip(Image.Bounds);
    Painter.DrawImage(Image.Bounds, Image.Source, TLayoutRectF.Create(0, 0, 0, 0));
  finally
    Painter.RestoreState;
  end;
end;

class procedure TMarkdownDisplayListRenderer.RenderCheckbox(const Checkbox: IDisplayCheckbox;
  const Painter: IPainter);
var
  Box: TLayoutRectF;
  BorderWidth: Single;
  HasMark: Boolean;
  Outline: TArray<TLayoutPointF>;
begin
  Box := PixelAlignedBox(Checkbox.Bounds);
  BorderWidth := BorderStrokeWidth(Box);
  Painter.DrawRect(Box, CheckboxBorderColor, BorderWidth);

  HasMark := (Checkbox.Checked and (Box.Width > 0) and (Box.Height > 0));
  if not HasMark then
    Exit;

  Outline := CheckMarkOutline(Box);
  Painter.FillPolygon(Outline, CheckboxMarkColor);
end;

class function TMarkdownDisplayListRenderer.PixelAlignedBox(const Bounds: TLayoutRectF): TLayoutRectF;
var
  Left: Int64;
  Top: Int64;
  Width: Int64;
  Height: Int64;
begin
  Left := Round(Bounds.Left);
  Top := Round(Bounds.Top);
  Width := Round(Bounds.Width);
  Height := Round(Bounds.Height);
  Result := TLayoutRectF.Create(Left, Top, Left + Width, Top + Height);
end;

class function TMarkdownDisplayListRenderer.BorderStrokeWidth(const Box: TLayoutRectF): Single;
var
  ScaledWidth: Int64;
begin
  ScaledWidth := Round(Box.Width * CheckboxBorderStrokeWidthFactor);
  Result := Max(CheckboxMinimumBorderStrokeWidth, ScaledWidth);
end;

class function TMarkdownDisplayListRenderer.CheckMarkOutline(const Box: TLayoutRectF): TArray<TLayoutPointF>;
var
  StartPoint: TLayoutPointF;
  MiddlePoint: TLayoutPointF;
  EndPoint: TLayoutPointF;
  HalfWidth: Double;
begin
  StartPoint := PointInBox(Box, CheckboxMarkStartXFactor, CheckboxMarkStartYFactor);
  MiddlePoint := PointInBox(Box, CheckboxMarkMiddleXFactor, CheckboxMarkMiddleYFactor);
  EndPoint := PointInBox(Box, CheckboxMarkEndXFactor, CheckboxMarkEndYFactor);
  HalfWidth := Box.Width * CheckboxMarkStrokeWidthFactor / 2;

  Result := BentStrokeOutline(StartPoint, MiddlePoint, EndPoint, HalfWidth);
end;

class function TMarkdownDisplayListRenderer.PointInBox(const Box: TLayoutRectF;
  const XFactor, YFactor: Single): TLayoutPointF;
begin
  Result := TLayoutPointF.Create(Box.Left + (XFactor * Box.Width), Box.Top + (YFactor * Box.Height));
end;

class function TMarkdownDisplayListRenderer.BentStrokeOutline(const StartPoint, CornerPoint, EndPoint: TLayoutPointF;
  const HalfWidth: Single): TArray<TLayoutPointF>;
var
  IncomingAngle: Single;
  OutgoingAngle: Single;
  HalfTurn: Double;
  MiterAngle: Double;
  MiterLength: Double;
  LeftCorner: TLayoutPointF;
  RightCorner: TLayoutPointF;
  StartCap: TArray<TLayoutPointF>;
  EndCap: TArray<TLayoutPointF>;
begin
  IncomingAngle := DirectionOf(StartPoint, CornerPoint);
  OutgoingAngle := DirectionOf(CornerPoint, EndPoint);
  HalfTurn := TurnBetween(IncomingAngle, OutgoingAngle) / 2;
  MiterAngle := IncomingAngle + (Pi / 2) + HalfTurn;
  MiterLength := HalfWidth / Cos(HalfTurn);

  LeftCorner := PointAt(CornerPoint, MiterAngle, MiterLength);
  RightCorner := PointAt(CornerPoint, MiterAngle, -MiterLength);
  StartCap := RoundCap(StartPoint, IncomingAngle - (Pi / 2), HalfWidth);
  EndCap := RoundCap(EndPoint, OutgoingAngle + (Pi / 2), HalfWidth);

  Result := StartCap + [LeftCorner] + EndCap + [RightCorner];
end;

class function TMarkdownDisplayListRenderer.DirectionOf(const FromPoint, ToPoint: TLayoutPointF): Single;
begin
  Result := ArcTan2(ToPoint.Y - FromPoint.Y, ToPoint.X - FromPoint.X);
end;

class function TMarkdownDisplayListRenderer.TurnBetween(const IncomingAngle, OutgoingAngle: Single): Single;
var
  Turn: Single;
  WrapsForward: Boolean;
  WrapsBackward: Boolean;
begin
  Turn := OutgoingAngle - IncomingAngle;
  WrapsForward := (Turn > Pi);
  if WrapsForward then
    Exit(Turn - (2 * Pi));

  WrapsBackward := (Turn <= -Pi);
  if WrapsBackward then
    Exit(Turn + (2 * Pi));

  Result := Turn;
end;

class function TMarkdownDisplayListRenderer.RoundCap(const Center: TLayoutPointF;
  const StartAngle, Radius: Single): TArray<TLayoutPointF>;
var
  Step: Integer;
  Angle: Double;
begin
  SetLength(Result, CheckboxMarkCapSegments + 1);
  for Step := 0 to CheckboxMarkCapSegments do
  begin
    Angle := StartAngle - (Pi * Step / CheckboxMarkCapSegments);
    Result[Step] := PointAt(Center, Angle, Radius);
  end;
end;

class function TMarkdownDisplayListRenderer.PointAt(const Origin: TLayoutPointF;
  const Angle, Distance: Single): TLayoutPointF;
var
  OffsetX: Double;
  OffsetY: Double;
begin
  OffsetX := Distance * Cos(Angle);
  OffsetY := Distance * Sin(Angle);
  Result := TLayoutPointF.Create(Origin.X + OffsetX, Origin.Y + OffsetY);
end;

class procedure TMarkdownDisplayListRenderer.RenderWedge(const Wedge: IDisplayWedge; const Painter: IPainter);
var
  HasStroke: Boolean;
begin
  if AlphaOf(Wedge.FillColor) > 0 then
    Painter.FillWedge(Wedge.Center, Wedge.OuterRadius, Wedge.InnerRadius, Wedge.StartAngle, Wedge.SweepAngle,
      Wedge.FillColor);

  HasStroke := (Wedge.StrokeWidth > 0) and (AlphaOf(Wedge.StrokeColor) > 0);
  if HasStroke then
    Painter.DrawWedge(Wedge.Center, Wedge.OuterRadius, Wedge.InnerRadius, Wedge.StartAngle, Wedge.SweepAngle,
      Wedge.StrokeColor, Wedge.StrokeWidth);
end;

class procedure TMarkdownDisplayListRenderer.RenderPolygon(const Polygon: IDisplayPolygon; const Painter: IPainter);
var
  PointCount: Integer;
  Points: TArray<TLayoutPointF>;
  Index: Integer;
  HasStroke: Boolean;
begin
  PointCount := Polygon.PointCount;
  
  SetLength(Points, PointCount);
  for Index := 0 to PointCount - 1 do
  begin
    Points[Index] := Polygon.Points[Index];
  end;

  if AlphaOf(Polygon.FillColor) > 0 then
    Painter.FillPolygon(Points, Polygon.FillColor);

  HasStroke := (Polygon.StrokeWidth > 0) and (AlphaOf(Polygon.StrokeColor) > 0);
  if HasStroke then
    Painter.DrawPolygon(Points, Polygon.StrokeColor, Polygon.StrokeWidth);
end;

class procedure TMarkdownDisplayListRenderer.RenderDisclosure(const Disclosure: IDisplayDisclosure;
  const Painter: IPainter);
var
  Triangle: TArray<TLayoutPointF>;
begin
  Triangle := DisclosureTriangle(Disclosure.Marker, Disclosure.IsOpen);
  Painter.FillPolygon(Triangle, Disclosure.Color);
end;

// The triangle a browser draws in front of a <summary>: pointing right while
// the section is closed, and down at its content once it opens.
class function TMarkdownDisplayListRenderer.DisclosureTriangle(const Marker: TLayoutRectF;
  const IsOpen: Boolean): TArray<TLayoutPointF>;
var
  MiddleX: Double;
  MiddleY: Double;
begin
  MiddleX := (Marker.Left + Marker.Right) / 2;
  MiddleY := (Marker.Top + Marker.Bottom) / 2;

  if IsOpen then
    Result := [TLayoutPointF.Create(Marker.Left, Marker.Top), TLayoutPointF.Create(Marker.Right, Marker.Top),
      TLayoutPointF.Create(MiddleX, Marker.Bottom)]
  else
    Result := [TLayoutPointF.Create(Marker.Left, Marker.Top), TLayoutPointF.Create(Marker.Right, MiddleY),
      TLayoutPointF.Create(Marker.Left, Marker.Bottom)];
end;

end.
