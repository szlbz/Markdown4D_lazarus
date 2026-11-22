{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.AutoScroll.Icon;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Layout.Interfaces,
  Markdown4D.Compat.Str,
  character;

type
  // The mark left where autoscroll started: a disc with an arrow up and an
  // arrow down, drawn half transparent in the theme's colours so it reads on
  // both a light and a dark page.
  TMarkdownAutoScrollIcon = class
  private
    const
      Radius = 14.0;
      ArrowTip = 9.0;
      ArrowBase = 3.0;
      ArrowHalfWidth = 5.0;
      FullCircle = 360.0;
      DiscAlpha = $D0;
      MarkAlpha = $90;
    class function WithAlpha(const Color: TLayoutColor; const Alpha: Byte): TLayoutColor; static;
    class function Arrow(const Center: TLayoutPointF; const Scale, Sign: Single): TArray<TLayoutPointF>; static;

  public
    class procedure Paint(const Painter: IPainter; const Center: TLayoutPointF; const Scale: Single;
      const BackgroundColor, TextColor: TLayoutColor); static;
  end;

implementation

class procedure TMarkdownAutoScrollIcon.Paint(const Painter: IPainter; const Center: TLayoutPointF;
  const Scale: Single; const BackgroundColor, TextColor: TLayoutColor);
var
  DiscColor: TLayoutColor;
  MarkColor: TLayoutColor;
  DiscRadius: Double;
  UpArrow: TArray<TLayoutPointF>;
  DownArrow: TArray<TLayoutPointF>;
begin
  DiscColor := WithAlpha(BackgroundColor, DiscAlpha);
  MarkColor := WithAlpha(TextColor, MarkAlpha);
  DiscRadius := Radius * Scale;

  Painter.FillWedge(Center, DiscRadius, 0, 0, FullCircle, DiscColor);
  Painter.DrawWedge(Center, DiscRadius, 0, 0, FullCircle, MarkColor, Scale);

  UpArrow := Arrow(Center, Scale, -1);
  DownArrow := Arrow(Center, Scale, 1);
  Painter.FillPolygon(UpArrow, MarkColor);
  Painter.FillPolygon(DownArrow, MarkColor);
end;

class function TMarkdownAutoScrollIcon.WithAlpha(const Color: TLayoutColor; const Alpha: Byte): TLayoutColor;
begin
  Result := (Color and $00FFFFFF) or (TLayoutColor(Alpha) shl 24);
end;

// Sign -1 points the arrow up, +1 down.
class function TMarkdownAutoScrollIcon.Arrow(const Center: TLayoutPointF; const Scale,
  Sign: Single): TArray<TLayoutPointF>;
var
  TipY: Double;
  BaseY: Double;
  HalfWidth: Double;
begin
  TipY := Center.Y + Sign * ArrowTip * Scale;
  BaseY := Center.Y + Sign * ArrowBase * Scale;
  HalfWidth := ArrowHalfWidth * Scale;

  Result := [TLayoutPointF.Create(Center.X, TipY),
             TLayoutPointF.Create(Center.X - HalfWidth, BaseY),
             TLayoutPointF.Create(Center.X + HalfWidth, BaseY)];
end;

end.
