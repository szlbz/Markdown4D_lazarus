{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Extensions.Chart.Layout;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Ast.Interfaces,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Layout.DisplayList,
  Markdown4D.Layout.BlockOverride,
  Markdown4D.Theme,
  Markdown4D.Extensions.Chart,
  Markdown4D.Compat.Str;

type
  TChartTickLabelFormatter = reference to function(const Value: Double): string;

  // Presentation settings for a chart. A zeroed record, Default(TChartLayoutOptions),
  // lays a chart out exactly as the overloads without options do, so a new
  // field must keep zero or nil as "unchanged".
  TChartLayoutOptions = record
  private
    const
      DefaultTickLabelFormat = '%g';

  public
    // Width over height of the chart. Zero or less keeps the 16:9 default.
    AspectRatio: Single;
    // Horizontal bar charts only: each label row becomes this many label line
    // heights tall, so the chart grows with its label count instead of
    // following the aspect ratio. Zero or less keeps the aspect ratio.
    BarRowHeightFactor: Single;
    // Bar charts only: the share of each label slot its bars fill, vertical or
    // horizontal. Zero or less keeps 0.8 for grouped bars and 0.6 for stacked
    // ones; above 1 counts as 1, bars touching their neighbours.
    BarFillFactor: Single;
    // Formats every value-axis label. Unassigned keeps the %g format with a
    // point as decimal separator, whatever the locale.
    TickLabelFormatter: TChartTickLabelFormatter;
    function HasAspectRatio: Boolean;
    function IsRowSized(const Model: IChartModel): Boolean;
    function BarFill(const DefaultFill: Single): Single;
    function FormatTickLabel(const Value: Double): string;
  end;

  TChartLayouter = class
  public
    const
      AspectRatioWidth = 16.0;
      AspectRatioHeight = 9.0;
    class procedure Draw(const Model: IChartModel; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas); overload;
    class procedure Draw(const Model: IChartModel; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas; const Options: TChartLayoutOptions); overload;
    class function BuildDisplayItems(const Model: IChartModel; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Node: IMarkdownNode): TArray<IDisplayItem>; overload;
    class function BuildDisplayItems(const Model: IChartModel; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Node: IMarkdownNode;
      const Options: TChartLayoutOptions): TArray<IDisplayItem>; overload;
    class function PreferredHeight(const AvailableWidth: Single; const Theme: TMarkdownTheme): Single; overload;
    class function PreferredHeight(const Model: IChartModel; const AvailableWidth: Single; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Options: TChartLayoutOptions): Single; overload;
    class function PaletteColor(const Theme: TMarkdownTheme; const DatasetIndex: Integer): TLayoutColor;
  end;

implementation

uses
  character,
  Math,
  SysUtils,
  Generics.Collections,
  Markdown4D.Defines,
  Markdown4D.Layout.ExtensionCanvas;

type
  TChartValueRange = record
    Minimum: Double;
    Maximum: Double;
  end;

  TChartValueAxis = record
    Minimum: Double;
    Maximum: Double;
    Ticks: TArray<Double>;
  end;

  TM4DGen1 = TArray<TArray<string>>;
  TChartLayoutBuilder = class
  private
    const
      Padding = 8.0;
      LabelFontSize = 11.0;
      TitleFontSize = 16.0;
      SwatchSize = 10.0;
      SwatchGap = 4.0;
      EntryGap = 12.0;
      AxisGap = 6.0;
      TargetTickCount = 5;
      // A tick count beyond this says the spacing does not fit the range, in
      // which case the axis falls back to its two ends.
      MaxTickCount = 64;
      TickTolerance = 0.001;
      // Typed so Power resolves to its Double overload: with an integer base
      // the Win64 compiler picks the Single one, and every tick label then
      // shows single-precision noise such as 0.200000002980232.
      DecimalBase: Double = 10.0;
      GroupedBarFill = 0.8;
      StackedBarFill = 0.6;
      GridStrokeWidth = 1.0;
      LineStrokeWidth = 2.0;
      MinLabelSweepDegrees = 18.0;
      PieRadiusFactor = 0.9;
      DoughnutInnerFactor = 0.55;
      AreaFillAlphaFactor = 0.3;
      RadarRingCount = 4;
      RadarMinAxes = 3;
      MarkerRadius = 3.5;
      FullCircleDegrees = 360.0;
      // A category label under the bars wraps onto this many lines at most,
      // and keeps this much room from the label beside it. Like the x axis in
      // Chart.js, the labels take no more than this share of the height under
      // the title and legend, so a narrow chart keeps room for its plot.
      MaxCategoryLabelLines = 3;
      CategoryLabelGap = 4.0;
      MaxCategoryBandShare = 0.5;
      Ellipsis = #$2026;
      WordSeparator = ' ';
      NoEmptyLine = -1;
    var
      FModel: IChartModel;
      FTheme: TMarkdownTheme;
      FMeasurer: ITextMeasurer;
      FCanvas: IExtensionCanvas;
      FOptions: TChartLayoutOptions;
      FLeft: Single;
      FTop: Single;
      FRight: Single;
      FBottom: Single;
    class function LabelFontFor(const Theme: TMarkdownTheme): TMarkdownFontStyle; static;
    class function TitleFontFor(const Theme: TMarkdownTheme): TMarkdownFontStyle; static;
    class function HasTitle(const Model: IChartModel): Boolean; static;
    class function HasLegend(const Model: IChartModel): Boolean; static;
    class function IsVerticalLegend(const Model: IChartModel): Boolean; static;
    class function LegendEntryCount(const Model: IChartModel): Integer; static;
    class function LegendRowHeight(const Theme: TMarkdownTheme; const Measurer: ITextMeasurer): Single; static;
    class function TitleBandHeight(const Model: IChartModel; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer): Single; static;
    class function LegendBandHeight(const Model: IChartModel; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer): Single; static;
    function LabelFont: TMarkdownFontStyle;
    function TitleFont: TMarkdownFontStyle;
    procedure EmitRectangle(const Bounds: TLayoutRectF; const FillColor, StrokeColor: TLayoutColor;
      const StrokeWidth: Single);
    procedure EmitText(const Text: string; const Left, Top: Single; const Font: TMarkdownFontStyle;
      const Color: TLayoutColor);
    procedure EmitCenteredText(const Text: string; const CenterX, Top: Single; const Font: TMarkdownFontStyle;
      const Color: TLayoutColor);
    procedure EmitLineSegment(const StartX, StartY, EndX, EndY: Single; const Color: TLayoutColor;
      const StrokeWidth: Single);
    procedure EmitWedge(const CenterX, CenterY, OuterRadius, InnerRadius, StartAngle, SweepAngle: Single;
      const Color: TLayoutColor);
    function EntryCount: Integer;
    function EntryColor(const Index: Integer): TLayoutColor;
    function EntryCaption(const Index: Integer): string;
    function DatasetColor(const Index: Integer): TLayoutColor;
    function BarColor(const DatasetIndex, LabelIndex: Integer): TLayoutColor;
    function SliceColor(const Index: Integer): TLayoutColor;
    class function IsColorSet(const Color: TLayoutColor): Boolean; static;
    procedure LayoutTitle;
    procedure LayoutLegend;
    procedure EmitLegendEntry(const Index: Integer; const X, RowY, RowHeight: Single; const Caption: string;
      const Font: TMarkdownFontStyle);
    procedure EmitVerticalLegend(const Font: TMarkdownFontStyle; const RowHeight: Single);
    procedure EmitHorizontalLegend(const Font: TMarkdownFontStyle; const RowHeight: Single);
    procedure LayoutAxes;
    function CategoryLabelLineLimit(const Font: TMarkdownFontStyle): Integer;
    function WrapCategoryLabels(const SlotWidth: Single; const LineLimit: Integer;
      const Font: TMarkdownFontStyle): TM4DGen1;
    function WrapLabel(const Text: string; const MaxWidth: Single; const LineLimit: Integer;
      const Font: TMarkdownFontStyle): TArray<string>;
    function FittedLines(const Text: string; const MaxWidth: Single; const LineLimit: Integer;
      const Font: TMarkdownFontStyle): TArray<string>;
    procedure BreakIntoLines(const Lines: TList<string>; const Text: string; const MaxWidth: Single;
      const LineLimit: Integer; const Font: TMarkdownFontStyle);
    procedure FitLines(const Lines: TList<string>; const MaxWidth: Single; const Font: TMarkdownFontStyle);
    function ShortenWithEllipsis(const Text: string; const MaxWidth: Single; const Font: TMarkdownFontStyle): string;
    class function PrefixWithEllipsis(const Text: string; const PrefixLength: Integer): string; static;
    function HasRoomFor(const Text: string; const MaxWidth: Single; const Font: TMarkdownFontStyle): Boolean;
    class function FirstEmptyLine(const Lines: TArray<string>): Integer; static;
    class function MostLines(const Labels: TM4DGen1): Integer; static;
    procedure EmitCategoryLabel(const Lines: TArray<string>; const CenterX, Top: Single;
      const Font: TMarkdownFontStyle);
    procedure LayoutBars(const PlotLeft, PlotTop, PlotRight, PlotBottom, AxisMin, AxisMax: Single);
    procedure EmitStackedBars(const LabelIndex: Integer; const SlotLeft, SlotWidth, BaseY, AxisSpan, PlotHeight: Single);
    procedure EmitGroupedBars(const LabelIndex: Integer; const SlotLeft, SlotWidth, BaseY, AxisMin, AxisSpan,
      PlotHeight, PlotBottom: Single);
    procedure LayoutLine(const PlotLeft, PlotTop, PlotRight, PlotBottom, AxisMin, AxisMax: Single);
    procedure LayoutPie;
    procedure LayoutHorizontalAxes;
    procedure LayoutHorizontalBars(const PlotLeft, PlotTop, PlotRight, PlotBottom, AxisMin, AxisMax: Single);
    procedure EmitHorizontalStackedBars(const LabelIndex: Integer; const SlotTop, SlotHeight, BaseX, AxisSpan,
      PlotWidth: Single);
    procedure EmitHorizontalGroupedBars(const LabelIndex: Integer; const SlotTop, SlotHeight, BaseX, AxisMin, AxisSpan,
      PlotWidth, PlotLeft: Single);
    procedure LayoutRadar;
    procedure LayoutScatter;
    procedure EmitFilledPolygon(const Points: TArray<TLayoutPointF>; const Color: TLayoutColor);
    class function Translucent(const Color: TLayoutColor; const Factor: Single): TLayoutColor; static;
    function NiceNum(const Value: Double; const RoundResult: Boolean): Double;
    // Rounding a value down or up to a whole number of steps stays in floating
    // point: Floor and Ceil return an integer, and a large value over a small
    // spacing is a quotient no integer holds, which would silently wrap and put
    // the axis somewhere else entirely.
    class function FloorToStep(const Value, Step: Double): Double; static;
    class function CeilToStep(const Value, Step: Double): Double; static;
    function BuildValueAxis(const Range: TChartValueRange): TChartValueAxis;
    function CollectValueRange: TChartValueRange;
    function CollectStackedRange(var HasValue: Boolean): TChartValueRange;
    function CollectUnstackedRange(var HasValue: Boolean): TChartValueRange;

  public
    class function RowSizedHeight(const Model: IChartModel; const Theme: TMarkdownTheme; const Measurer: ITextMeasurer;
      const RowHeightFactor: Single): Single; static;
    constructor Create(const Model: IChartModel; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas; const Options: TChartLayoutOptions);
    procedure Build;
  end;

function TChartLayoutOptions.HasAspectRatio: Boolean;
begin
  Result := AspectRatio > 0;
end;

function TChartLayoutOptions.IsRowSized(const Model: IChartModel): Boolean;
begin
  Result := (BarRowHeightFactor > 0) and (Model.ChartKind = TChartKind.Bar) and Model.Horizontal;
end;

function TChartLayoutOptions.BarFill(const DefaultFill: Single): Single;
var
  FullSlot: Single;
  KeepsDefaultFill: Boolean;
begin
  FullSlot := 1.0;

  KeepsDefaultFill := (BarFillFactor <= 0);
  if KeepsDefaultFill then
  begin
    Result := DefaultFill;
    Exit;
  end;

  Result := Min(BarFillFactor, FullSlot);
end;

function TChartLayoutOptions.FormatTickLabel(const Value: Double): string;
begin
  if Assigned(TickLabelFormatter) then
  begin
    Result := TickLabelFormatter(Value);
    Exit;
  end;

  Result := Format(DefaultTickLabelFormat, [Value], TFormatSettings.Invariant);
end;

class function TChartLayouter.PreferredHeight(const AvailableWidth: Single; const Theme: TMarkdownTheme): Single;
begin
  Result := AvailableWidth * AspectRatioHeight / AspectRatioWidth;
end;

class function TChartLayouter.PreferredHeight(const Model: IChartModel; const AvailableWidth: Single;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Options: TChartLayoutOptions): Single;
begin
  if Options.IsRowSized(Model) then
  begin
    Result := TChartLayoutBuilder.RowSizedHeight(Model, Theme, Measurer, Options.BarRowHeightFactor);
    Exit;
  end;

  if Options.HasAspectRatio then
  begin
    Result := AvailableWidth / Options.AspectRatio;
    Exit;
  end;

  Result := PreferredHeight(AvailableWidth, Theme);
end;

class function TChartLayouter.PaletteColor(const Theme: TMarkdownTheme; const DatasetIndex: Integer): TLayoutColor;
var
  Palette: TArray<TLayoutColor>;
  Count: Integer;
begin
  Palette := Theme.ChartPalette;
  Count := Length(Palette);
  if Count = 0 then
  begin
    Result := Theme.ChartTextColor;
    Exit;
  end;

  Result := Palette[DatasetIndex mod Count];
end;

class function TChartLayouter.BuildDisplayItems(const Model: IChartModel; const Bounds: TLayoutRectF;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Node: IMarkdownNode): TArray<IDisplayItem>;
begin
  Result := BuildDisplayItems(Model, Bounds, Theme, Measurer, Node, Default(TChartLayoutOptions));
end;

class function TChartLayouter.BuildDisplayItems(const Model: IChartModel; const Bounds: TLayoutRectF;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Node: IMarkdownNode;
  const Options: TChartLayoutOptions): TArray<IDisplayItem>;
var
  Items: TList<IDisplayItem>;
  Canvas: IExtensionCanvas;
begin
  Items := TList<IDisplayItem>.Create;
  try
    Canvas := TDisplayListExtensionCanvas.Create(Measurer, Items, Node);
    Draw(Model, Bounds, Theme, Measurer, Canvas, Options);

    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

class procedure TChartLayouter.Draw(const Model: IChartModel; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
  const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
begin
  Draw(Model, Bounds, Theme, Measurer, Canvas, Default(TChartLayoutOptions));
end;

class procedure TChartLayouter.Draw(const Model: IChartModel; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
  const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas; const Options: TChartLayoutOptions);
var
  Preferred: Single;
  ClampedHeight: Single;
  Clamped: TLayoutRectF;
  Builder: TChartLayoutBuilder;
begin
  Preferred := PreferredHeight(Model, Bounds.Width, Theme, Measurer, Options);
  ClampedHeight := Min(Bounds.Height, Preferred);
  Clamped := TLayoutRectF.Create(Bounds.Left, Bounds.Top, Bounds.Left + Bounds.Width, Bounds.Top + ClampedHeight);

  Builder := TChartLayoutBuilder.Create(Model, Clamped, Theme, Measurer, Canvas, Options);
  try
    Builder.Build;
  finally
    Builder.Free;
  end;
end;

// The row-sized height adds up the same bands Build takes off the chart, so
// the plot that remains holds each label row at exactly the requested height.
class function TChartLayoutBuilder.RowSizedHeight(const Model: IChartModel; const Theme: TMarkdownTheme;
  const Measurer: ITextMeasurer; const RowHeightFactor: Single): Single;
var
  Font: TMarkdownFontStyle;
  LabelLineHeight: Single;
  RowCount: Integer;
  AxisBand: Double;
  RowsHeight: Single;
  TitleBand: Single;
  LegendBand: Single;
begin
  Font := LabelFontFor(Theme);
  LabelLineHeight := Measurer.LineHeight(Font);
  RowCount := Max(1, Model.LabelCount);
  AxisBand := LabelLineHeight + AxisGap;
  RowsHeight := RowCount * RowHeightFactor * LabelLineHeight;
  TitleBand := TitleBandHeight(Model, Theme, Measurer);
  LegendBand := LegendBandHeight(Model, Theme, Measurer);

  Result := 2 * Padding + TitleBand + LegendBand + AxisBand + RowsHeight;
end;

constructor TChartLayoutBuilder.Create(const Model: IChartModel; const Bounds: TLayoutRectF;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas;
  const Options: TChartLayoutOptions);
begin
  inherited Create;

  FModel := Model;
  FTheme := Theme;
  FMeasurer := Measurer;
  FCanvas := Canvas;
  FOptions := Options;

  FLeft := Bounds.Left + Padding;
  FTop := Bounds.Top + Padding;
  FRight := Bounds.Left + Bounds.Width - Padding;
  FBottom := Bounds.Top + Bounds.Height - Padding;
end;

procedure TChartLayoutBuilder.Build;
var
  HasPlotArea: Boolean;
begin
  LayoutTitle;
  LayoutLegend;

  HasPlotArea := (FRight > FLeft) and (FBottom > FTop);
  if not HasPlotArea then
    Exit;

  case FModel.ChartKind of
    TChartKind.Bar:
      if FModel.Horizontal then
        LayoutHorizontalAxes
      else
        LayoutAxes;
    TChartKind.Line:
      LayoutAxes;
    TChartKind.Pie, TChartKind.Doughnut:
      LayoutPie;
    TChartKind.Radar:
      LayoutRadar;
    TChartKind.Scatter:
      LayoutScatter;
  else
    raise EMarkdownError.CreateFmt('Unhandled chart kind: %d', [Ord(FModel.ChartKind)]);
  end;
end;

class function TChartLayoutBuilder.TitleBandHeight(const Model: IChartModel; const Theme: TMarkdownTheme;
  const Measurer: ITextMeasurer): Single;
var
  Font: TMarkdownFontStyle;
begin
  if not HasTitle(Model) then
  begin
    Result := 0;
    Exit;
  end;

  Font := TitleFontFor(Theme);
  Result := Measurer.LineHeight(Font) + Padding;
end;

// A legend on the left or right takes width from the chart, not height.
class function TChartLayoutBuilder.LegendBandHeight(const Model: IChartModel; const Theme: TMarkdownTheme;
  const Measurer: ITextMeasurer): Single;
var
  TakesHeight: Boolean;
begin
  TakesHeight := (HasLegend(Model) and not IsVerticalLegend(Model));
  if not TakesHeight then
  begin
    Result := 0;
    Exit;
  end;

  Result := LegendRowHeight(Theme, Measurer) + Padding;
end;

class function TChartLayoutBuilder.HasTitle(const Model: IChartModel): Boolean;
begin
  Result := Model.TitleVisible and (Model.Title <> '');
end;

class function TChartLayoutBuilder.HasLegend(const Model: IChartModel): Boolean;
begin
  Result := Model.LegendVisible and (LegendEntryCount(Model) > 0);
end;

class function TChartLayoutBuilder.LegendEntryCount(const Model: IChartModel): Integer;
begin
  case Model.ChartKind of
    TChartKind.Pie, TChartKind.Doughnut:
      Result := Model.LabelCount;
  else
    Result := Model.DatasetCount;
  end;
end;

class function TChartLayoutBuilder.IsVerticalLegend(const Model: IChartModel): Boolean;
begin
  Result := (Model.LegendPosition = TChartLegendPosition.Left) or (Model.LegendPosition = TChartLegendPosition.Right);
end;

class function TChartLayoutBuilder.LegendRowHeight(const Theme: TMarkdownTheme; const Measurer: ITextMeasurer): Single;
var
  Font: TMarkdownFontStyle;
  LabelLineHeight: Single;
begin
  Font := LabelFontFor(Theme);
  LabelLineHeight := Measurer.LineHeight(Font);
  Result := Max(LabelLineHeight, SwatchSize);
end;

class function TChartLayoutBuilder.LabelFontFor(const Theme: TMarkdownTheme): TMarkdownFontStyle;
begin
  Result := TMarkdownFontStyle.Create(Theme.BaseFont.FamilyName, LabelFontSize);
end;

class function TChartLayoutBuilder.TitleFontFor(const Theme: TMarkdownTheme): TMarkdownFontStyle;
begin
  Result := TMarkdownFontStyle.Create(Theme.BaseFont.FamilyName, TitleFontSize, True);
end;

function TChartLayoutBuilder.LabelFont: TMarkdownFontStyle;
begin
  Result := LabelFontFor(FTheme);
end;

function TChartLayoutBuilder.TitleFont: TMarkdownFontStyle;
begin
  Result := TitleFontFor(FTheme);
end;

procedure TChartLayoutBuilder.EmitRectangle(const Bounds: TLayoutRectF; const FillColor, StrokeColor: TLayoutColor;
  const StrokeWidth: Single);
begin
  FCanvas.FillAndStrokeRectangle(Bounds, FillColor, StrokeColor, StrokeWidth);
end;

procedure TChartLayoutBuilder.EmitText(const Text: string; const Left, Top: Single; const Font: TMarkdownFontStyle;
  const Color: TLayoutColor);
begin
  if Text = '' then
    Exit;

  FCanvas.DrawText(TLayoutPointF.Create(Left, Top), Text, Font, Color);
end;

procedure TChartLayoutBuilder.EmitCenteredText(const Text: string; const CenterX, Top: Single;
  const Font: TMarkdownFontStyle; const Color: TLayoutColor);
var
  Size: TLayoutSizeF;
begin
  if Text = '' then
    Exit;

  Size := FMeasurer.MeasureText(Text, Font);
  EmitText(Text, CenterX - Size.Width / 2, Top, Font, Color);
end;

procedure TChartLayoutBuilder.EmitLineSegment(const StartX, StartY, EndX, EndY: Single; const Color: TLayoutColor;
  const StrokeWidth: Single);
begin
  FCanvas.DrawLine(TLayoutPointF.Create(StartX, StartY), TLayoutPointF.Create(EndX, EndY), Color, StrokeWidth);
end;

procedure TChartLayoutBuilder.EmitWedge(const CenterX, CenterY, OuterRadius, InnerRadius, StartAngle,
  SweepAngle: Single; const Color: TLayoutColor);
begin
  FCanvas.FillWedge(TLayoutPointF.Create(CenterX, CenterY), OuterRadius, InnerRadius, StartAngle, SweepAngle, Color);
end;

function TChartLayoutBuilder.EntryCount: Integer;
begin
  Result := LegendEntryCount(FModel);
end;

function TChartLayoutBuilder.EntryColor(const Index: Integer): TLayoutColor;
begin
  case FModel.ChartKind of
    TChartKind.Pie, TChartKind.Doughnut:
      Result := SliceColor(Index);
  else
    Result := DatasetColor(Index);
  end;
end;

function TChartLayoutBuilder.EntryCaption(const Index: Integer): string;
begin
  case FModel.ChartKind of
    TChartKind.Pie, TChartKind.Doughnut:
      Result := FModel.Labels[Index];
  else
    Result := FModel.Datasets[Index].Caption;
  end;
end;

function TChartLayoutBuilder.DatasetColor(const Index: Integer): TLayoutColor;
var
  Dataset: IChartDataset;
begin
  Dataset := FModel.Datasets[Index];

  if (Dataset.BackgroundColorCount > 0) and IsColorSet(Dataset.BackgroundColors[0]) then
  begin
    Result := Dataset.BackgroundColors[0];
    Exit;
  end;

  if (Dataset.BorderColorCount > 0) and IsColorSet(Dataset.BorderColors[0]) then
  begin
    Result := Dataset.BorderColors[0];
    Exit;
  end;

  Result := TChartLayouter.PaletteColor(FTheme, Index);
end;

// A dataset with more than one background colour colours each bar by its label
// index, as Chart.js does, starting over when there are more labels than colours.
function TChartLayoutBuilder.BarColor(const DatasetIndex, LabelIndex: Integer): TLayoutColor;
var
  Dataset: IChartDataset;
  ColorCount: Integer;
  HasColorPerBar: Boolean;
  Background: TLayoutColor;
begin
  Dataset := FModel.Datasets[DatasetIndex];
  ColorCount := Dataset.BackgroundColorCount;

  HasColorPerBar := (ColorCount > 1);
  if HasColorPerBar then
  begin
    Background := Dataset.BackgroundColors[LabelIndex mod ColorCount];
    if IsColorSet(Background) then
    begin
      Result := Background;
      Exit;
    end;
  end;

  Result := DatasetColor(DatasetIndex);
end;

function TChartLayoutBuilder.SliceColor(const Index: Integer): TLayoutColor;
var
  Dataset: IChartDataset;
begin
  if FModel.DatasetCount > 0 then
  begin
    Dataset := FModel.Datasets[0];
    if (Dataset.BackgroundColorCount > Index) and IsColorSet(Dataset.BackgroundColors[Index]) then
    begin
      Result := Dataset.BackgroundColors[Index];
      Exit;
    end;
  end;

  Result := TChartLayouter.PaletteColor(FTheme, Index);
end;

class function TChartLayoutBuilder.IsColorSet(const Color: TLayoutColor): Boolean;
begin
  Result := (Color shr 24) <> 0;
end;

procedure TChartLayoutBuilder.LayoutTitle;
begin
  if not HasTitle(FModel) then
    Exit;

  EmitCenteredText(FModel.Title, (FLeft + FRight) / 2, FTop, TitleFont, FTheme.ChartTextColor);
  FTop := FTop + TitleBandHeight(FModel, FTheme, FMeasurer);
end;

procedure TChartLayoutBuilder.LayoutLegend;
var
  Font: TMarkdownFontStyle;
  RowHeight: Single;
begin
  if not HasLegend(FModel) then
    Exit;

  Font := LabelFont;
  RowHeight := LegendRowHeight(FTheme, FMeasurer);

  if IsVerticalLegend(FModel) then
    EmitVerticalLegend(Font, RowHeight)
  else
    EmitHorizontalLegend(Font, RowHeight);
end;

procedure TChartLayoutBuilder.EmitLegendEntry(const Index: Integer; const X, RowY, RowHeight: Single;
  const Caption: string; const Font: TMarkdownFontStyle);
var
  SwatchTop: Double;
begin
  SwatchTop := RowY + (RowHeight - SwatchSize) / 2;
  EmitRectangle(TLayoutRectF.Create(X, SwatchTop, X + SwatchSize, SwatchTop + SwatchSize),
    EntryColor(Index), 0, 0);
  EmitText(Caption, X + SwatchSize + SwatchGap, RowY, Font, FTheme.ChartTextColor);
end;

procedure TChartLayoutBuilder.EmitVerticalLegend(const Font: TMarkdownFontStyle; const RowHeight: Single);
var
  ColumnWidth: Double;
  Index: Integer;
  Width: Double;
  ColumnX: Single;
  RowY: Single;
begin
  ColumnWidth := 0.0;
  for Index := 0 to EntryCount - 1 do
  begin
    Width := SwatchSize + SwatchGap + FMeasurer.MeasureText(EntryCaption(Index), Font).Width;
    ColumnWidth := Max(ColumnWidth, Width);
  end;

  ColumnX := FLeft;
  if FModel.LegendPosition = TChartLegendPosition.Right then
    ColumnX := FRight - ColumnWidth;

  RowY := FTop;
  for Index := 0 to EntryCount - 1 do
  begin
    EmitLegendEntry(Index, ColumnX, RowY, RowHeight, EntryCaption(Index), Font);
    RowY := RowY + RowHeight;
  end;

  if FModel.LegendPosition = TChartLegendPosition.Right then
    FRight := FRight - ColumnWidth - Padding
  else
    FLeft := FLeft + ColumnWidth + Padding;
end;

procedure TChartLayoutBuilder.EmitHorizontalLegend(const Font: TMarkdownFontStyle; const RowHeight: Single);
var
  RowY: Single;
  EntryX: Single;
  Index: Integer;
  Caption: string;
  CaptionWidth: type of (FMeasurer.MeasureText(Caption, Font).Width);
begin
  RowY := FTop;
  if FModel.LegendPosition = TChartLegendPosition.Bottom then
    RowY := FBottom - RowHeight;

  EntryX := FLeft;
  for Index := 0 to EntryCount - 1 do
  begin
    Caption := EntryCaption(Index);
    CaptionWidth := FMeasurer.MeasureText(Caption, Font).Width;
    EmitLegendEntry(Index, EntryX, RowY, RowHeight, Caption, Font);
    EntryX := EntryX + SwatchSize + SwatchGap + CaptionWidth + EntryGap;
  end;

  if FModel.LegendPosition = TChartLegendPosition.Bottom then
    FBottom := FBottom - RowHeight - Padding
  else
    FTop := FTop + RowHeight + Padding;
end;

function TChartLayoutBuilder.CollectValueRange: TChartValueRange;
var
  HasValue: Boolean;
begin
  HasValue := False;

  if FModel.Stacked then
    Result := CollectStackedRange(HasValue)
  else
    Result := CollectUnstackedRange(HasValue);

  if not HasValue then
    Result.Maximum := 1;

  if FModel.ChartKind = TChartKind.Bar then
    Result.Minimum := Min(Result.Minimum, 0);
end;

function TChartLayoutBuilder.CollectStackedRange(var HasValue: Boolean): TChartValueRange;
var
  LabelIndex: Integer;
  PositiveSum: Double;
  NegativeSum: Double;
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  Value: Double;
begin
  Result.Minimum := 0;
  Result.Maximum := 0;

  for LabelIndex := 0 to FModel.LabelCount - 1 do
  begin
    PositiveSum := 0.0;
    NegativeSum := 0.0;
    for DatasetIndex := 0 to FModel.DatasetCount - 1 do
    begin
      Dataset := FModel.Datasets[DatasetIndex];
      if LabelIndex >= Dataset.ValueCount then
        Continue;
      Value := Dataset.Values[LabelIndex];
      if Value >= 0 then
        PositiveSum := PositiveSum + Value
      else
        NegativeSum := NegativeSum + Value;
      HasValue := True;
    end;
    Result.Maximum := Max(Result.Maximum, PositiveSum);
    Result.Minimum := Min(Result.Minimum, NegativeSum);
  end;
end;

function TChartLayoutBuilder.CollectUnstackedRange(var HasValue: Boolean): TChartValueRange;
var
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  ValueIndex: Integer;
  Value: Double;
begin
  Result.Minimum := 0;
  Result.Maximum := 0;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    for ValueIndex := 0 to Dataset.ValueCount - 1 do
    begin
      Value := Dataset.Values[ValueIndex];
      if not HasValue then
      begin
        Result.Minimum := Value;
        Result.Maximum := Value;
        HasValue := True;
      end
      else
      begin
        Result.Minimum := Min(Result.Minimum, Value);
        Result.Maximum := Max(Result.Maximum, Value);
      end;
    end;
  end;
end;

function TChartLayoutBuilder.NiceNum(const Value: Double; const RoundResult: Boolean): Double;
var
  Exponent: Integer;
  PowerOfTen: Double;
  Fraction: Double;
  NiceFraction: Double;
begin
  if Value <= 0 then
  begin
    Result := 1;
    Exit;
  end;

  Exponent := Floor(Log10(Value));
  PowerOfTen := Power(DecimalBase, Exponent);
  Fraction := Value / PowerOfTen;
  

  if RoundResult then
  begin
    if Fraction < 1.5 then
      NiceFraction := 1
    else if Fraction < 3 then
      NiceFraction := 2
    else if Fraction < 7 then
      NiceFraction := 5
    else
      NiceFraction := 10;
  end
  else
  begin
    if Fraction <= 1 then
      NiceFraction := 1
    else if Fraction <= 2 then
      NiceFraction := 2
    else if Fraction <= 5 then
      NiceFraction := 5
    else
      NiceFraction := 10;
  end;

  Result := NiceFraction * PowerOfTen;
end;

class function TChartLayoutBuilder.FloorToStep(const Value, Step: Double): Double;
var
  Steps: type of (Int(Value / Step));
begin
  Steps := Int(Value / Step);
  if Steps * Step > Value then
    Steps := Steps - 1;

  Result := Steps * Step;
end;

class function TChartLayoutBuilder.CeilToStep(const Value, Step: Double): Double;
var
  Steps: type of (Int(Value / Step));
begin
  Steps := Int(Value / Step);
  if Steps * Step < Value then
    Steps := Steps + 1;

  Result := Steps * Step;
end;

function TChartLayoutBuilder.BuildValueAxis(const Range: TChartValueRange): TChartValueAxis;
var
  Low: Double;
  High: Double;
  Span: Double;
  Spacing: Double;
  Collected: TList<Double>;
  FirstTick: Double;
  RawStepCount: Double;
  Fits: Boolean;
  Index: Integer;
begin
  Low := Range.Minimum;
  High := Range.Maximum;

  if FModel.HasScaleMin then
    Low := FModel.ScaleMin;
  if FModel.HasScaleMax then
    High := FModel.ScaleMax;

  if High <= Low then
    High := Low + 1;

  Span := NiceNum(High - Low, False);
  Spacing := NiceNum(Span / (TargetTickCount - 1), True);

  if FModel.HasScaleMin then
    Result.Minimum := FModel.ScaleMin
  else
    Result.Minimum := FloorToStep(Low, Spacing);

  if FModel.HasScaleMax then
    Result.Maximum := FModel.ScaleMax
  else
    Result.Maximum := CeilToStep(High, Spacing);

  Collected := TList<Double>.Create;
  try
    // Each tick is computed from its index rather than added to the previous
    // one, so a long axis cannot drift away from its spacing.
    FirstTick := CeilToStep(Result.Minimum, Spacing);
    RawStepCount := (Result.Maximum - FirstTick) / Spacing + TickTolerance;
    Fits := (RawStepCount >= 0) and (RawStepCount <= MaxTickCount);

    if Fits then
    begin
      for Index := 0 to Trunc(RawStepCount) do
      begin
        Collected.Add(FirstTick + Index * Spacing);
      end;
    end;

    if Collected.Count = 0 then
    begin
      Collected.Add(Result.Minimum);
      Collected.Add(Result.Maximum);
    end;

    Result.Ticks := Collected.ToArray;
  finally
    Collected.Free;
  end;
end;

procedure TChartLayoutBuilder.LayoutAxes;
var
  Range: TChartValueRange;
  Axis: TChartValueAxis;
  Font: TMarkdownFontStyle;
  GutterWidth: Double;
  Tick: Double;
  Text: string;
  PlotLeft: Double;
  PlotTop: Single;
  PlotRight: Single;
  SlotWidth: Double;
  LineLimit: Integer;
  CategoryLabels: TM4DGen1;
  LabelLineCount: Integer;
  BottomGutter: Double;
  PlotBottom: Double;
  PlotAreaInvalid: Boolean;
  AxisSpan: Double;
  Ratio: Double;
  GridY: Double;
  Size: TLayoutSizeF;
  LabelIndex: Integer;
  CenterX: Double;
begin
  Range := CollectValueRange;
  Axis := BuildValueAxis(Range);

  Font := LabelFont;

  GutterWidth := 0.0;
  for Tick in Axis.Ticks do
  begin
    Text := FOptions.FormatTickLabel(Tick);
    GutterWidth := Max(GutterWidth, FMeasurer.MeasureText(Text, Font).Width);
  end;
  GutterWidth := GutterWidth + AxisGap;

  // The labels under the plot wrap to the width of their slot, so the room
  // they take below the axis follows from the slot width, and with it the
  // bottom of the plot.
  PlotLeft := FLeft + GutterWidth;
  PlotTop := FTop;
  PlotRight := FRight;
  SlotWidth := (PlotRight - PlotLeft) / Max(1, FModel.LabelCount);
  LineLimit := CategoryLabelLineLimit(Font);
  CategoryLabels := WrapCategoryLabels(SlotWidth, LineLimit, Font);
  LabelLineCount := Max(1, MostLines(CategoryLabels));
  BottomGutter := LabelLineCount * FMeasurer.LineHeight(Font) + AxisGap;
  PlotBottom := FBottom - BottomGutter;

  PlotAreaInvalid := ((PlotRight <= PlotLeft) or (PlotBottom <= PlotTop));
  if PlotAreaInvalid then
    Exit;

  AxisSpan := Axis.Maximum - Axis.Minimum;
  for Tick in Axis.Ticks do
  begin
    Ratio := (Tick - Axis.Minimum) / AxisSpan;
    GridY := PlotBottom - Ratio * (PlotBottom - PlotTop);
    EmitLineSegment(PlotLeft, GridY, PlotRight, GridY, FTheme.ChartGridLineColor, GridStrokeWidth);

    Text := FOptions.FormatTickLabel(Tick);
    Size := FMeasurer.MeasureText(Text, Font);
    EmitText(Text, PlotLeft - AxisGap - Size.Width, GridY - Size.Height / 2, Font, FTheme.ChartTextColor);
  end;

  for LabelIndex := 0 to FModel.LabelCount - 1 do
  begin
    CenterX := PlotLeft + SlotWidth * (LabelIndex + 0.5);
    EmitCategoryLabel(CategoryLabels[LabelIndex], CenterX, PlotBottom + AxisGap, Font);
  end;

  if FModel.ChartKind = TChartKind.Bar then
    LayoutBars(PlotLeft, PlotTop, PlotRight, PlotBottom, Axis.Minimum, Axis.Maximum)
  else
    LayoutLine(PlotLeft, PlotTop, PlotRight, PlotBottom, Axis.Minimum, Axis.Maximum);
end;

// A chart too low to spare even one line still gives its labels that line, so
// they stay visible.
function TChartLayoutBuilder.CategoryLabelLineLimit(const Font: TMarkdownFontStyle): Integer;
var
  MaxBandHeight: Double;
  LineHeight: Single;
  LinesInBand: Integer;
begin
  MaxBandHeight := (FBottom - FTop) * MaxCategoryBandShare;
  LineHeight := FMeasurer.LineHeight(Font);
  LinesInBand := Floor((MaxBandHeight - AxisGap) / LineHeight);

  Result := EnsureRange(LinesInBand, 1, MaxCategoryLabelLines);
end;

// A slot too narrow for even the ellipsis cannot shorten any label, so no label
// is measured any further.
function TChartLayoutBuilder.WrapCategoryLabels(const SlotWidth: Single; const LineLimit: Integer;
  const Font: TMarkdownFontStyle): TM4DGen1;
var
  MaxWidth: Double;
  HasRoomForTheEllipsis: Boolean;
  LabelIndex: Integer;
  Text: string;
  StaysWhole: Boolean;
begin
  MaxWidth := Max(0, SlotWidth - CategoryLabelGap);
  HasRoomForTheEllipsis := (HasRoomFor(Ellipsis, MaxWidth, Font));
  SetLength(Result, FModel.LabelCount);

  for LabelIndex := 0 to FModel.LabelCount - 1 do
  begin
    Text := FModel.Labels[LabelIndex];
    StaysWhole := (not HasRoomForTheEllipsis or HasRoomFor(Text, MaxWidth, Font));
    if StaysWhole then
      Result[LabelIndex] := [Text]
    else
      Result[LabelIndex] := WrapLabel(Text, MaxWidth, LineLimit, Font);
  end;
end;

// A line without room for one character before the ellipsis would show the
// ellipsis alone. Such a line is left out and the line above ends in the
// ellipsis instead; where that line has no room for it either, or the first
// line has none, the label stays whole on one line and takes no extra height.
function TChartLayoutBuilder.WrapLabel(const Text: string; const MaxWidth: Single; const LineLimit: Integer;
  const Font: TMarkdownFontStyle): TArray<string>;
var
  Lines: TArray<string>;
  EmptyLine: Integer;
  ShowsEveryLine: Boolean;
  HasLineAbove: Boolean;
  FewerLines: TArray<string>;
  ShowsFewerLines: Boolean;
begin
  Result := [Text];

  Lines := FittedLines(Text, MaxWidth, LineLimit, Font);
  EmptyLine := FirstEmptyLine(Lines);
  ShowsEveryLine := (EmptyLine = NoEmptyLine);
  if ShowsEveryLine then
  begin
    Result := Lines;
    Exit;
  end;

  HasLineAbove := (EmptyLine > 0);
  if not HasLineAbove then
    Exit;

  FewerLines := FittedLines(Text, MaxWidth, EmptyLine, Font);
  ShowsFewerLines := (FirstEmptyLine(FewerLines) = NoEmptyLine);
  if ShowsFewerLines then
    Result := FewerLines;
end;

function TChartLayoutBuilder.FittedLines(const Text: string; const MaxWidth: Single; const LineLimit: Integer;
  const Font: TMarkdownFontStyle): TArray<string>;
var
  Lines: TList<string>;
begin
  Lines := TList<string>.Create;
  try
    BreakIntoLines(Lines, Text, MaxWidth, LineLimit, Font);
    FitLines(Lines, MaxWidth, Font);

    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

// The last line allowed takes every word that is left, so that it ends in an
// ellipsis where words had to be dropped.
procedure TChartLayoutBuilder.BreakIntoLines(const Lines: TList<string>; const Text: string; const MaxWidth: Single;
  const LineLimit: Integer; const Font: TMarkdownFontStyle);
var
  Tokens: TArray<string>;
  CurrentLine: string;
  Token: string;
  StartsTheLine: Boolean;
  Candidate: type of (string.Join(WordSeparator, [CurrentLine, Token]));
  IsLastLine: Boolean;
  StaysOnTheLine: Boolean;
  HasLastLine: Boolean;
begin
  Tokens := Text.Split([WordSeparator], TStringSplitOptions.ExcludeEmpty);

  CurrentLine := '';
  for Token in Tokens do
  begin
    StartsTheLine := (CurrentLine.IsEmpty);
    if StartsTheLine then
    begin
      CurrentLine := Token;
      Continue;
    end;

    Candidate := string.Join(WordSeparator, [CurrentLine, Token]);
    IsLastLine := (Lines.Count >= LineLimit - 1);
    StaysOnTheLine := (IsLastLine or HasRoomFor(Candidate, MaxWidth, Font));
    if StaysOnTheLine then
    begin
      CurrentLine := Candidate;
      Continue;
    end;

    Lines.Add(CurrentLine);
    CurrentLine := Token;
  end;

  HasLastLine := (not CurrentLine.IsEmpty);
  if HasLastLine then
    Lines.Add(CurrentLine);
end;

procedure TChartLayoutBuilder.FitLines(const Lines: TList<string>; const MaxWidth: Single;
  const Font: TMarkdownFontStyle);
var
  Index: Integer;
  Line: string;
begin
  for Index := 0 to Lines.Count - 1 do
  begin
    Line := Lines[Index];
    if not HasRoomFor(Line, MaxWidth, Font) then
      Lines[Index] := ShortenWithEllipsis(Line, MaxWidth, Font);
  end;
end;

// The search can start from the empty prefix, which is known to fit: a label
// is only shortened where the ellipsis fits. An empty result tells the caller
// that not even one character fits before it.
function TChartLayoutBuilder.ShortenWithEllipsis(const Text: string; const MaxWidth: Single;
  const Font: TMarkdownFontStyle): string;
var
  FittingLength: Integer;
  OverflowLength: Integer;
  MiddleLength: Integer;
  Candidate: string;
  ShowsOnlyTheEllipsis: Boolean;
begin
  FittingLength := 0;
  OverflowLength := Text.Length + 1;

  while OverflowLength - FittingLength > 1 do
  begin
    MiddleLength := (FittingLength + OverflowLength) div 2;
    Candidate := PrefixWithEllipsis(Text, MiddleLength);
    if HasRoomFor(Candidate, MaxWidth, Font) then
      FittingLength := MiddleLength
    else
      OverflowLength := MiddleLength;
  end;

  Result := PrefixWithEllipsis(Text, FittingLength);

  ShowsOnlyTheEllipsis := (Result = Ellipsis);
  if ShowsOnlyTheEllipsis then
    Result := '';
end;

// A cut between the two halves of a surrogate pair would leave half a
// character, so such a cut moves one place to the left.
class function TChartLayoutBuilder.PrefixWithEllipsis(const Text: string; const PrefixLength: Integer): string;
var
  SplitsAPair: Boolean;
  KeptLength: Integer;
  Kept: string;
begin
  SplitsAPair := ((PrefixLength > 0) and (PrefixLength < Text.Length) and Text.Chars[PrefixLength].IsLowSurrogate);

  KeptLength := PrefixLength;
  if SplitsAPair then
    Dec(KeptLength);

  Kept := Text.Substring(0, KeptLength);
  Result := Kept.TrimRight + Ellipsis;
end;

function TChartLayoutBuilder.HasRoomFor(const Text: string; const MaxWidth: Single;
  const Font: TMarkdownFontStyle): Boolean;
var
  Size: TLayoutSizeF;
begin
  Size := FMeasurer.MeasureText(Text, Font);
  Result := (Size.Width <= MaxWidth);
end;

class function TChartLayoutBuilder.FirstEmptyLine(const Lines: TArray<string>): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Lines) do
  begin
    if Lines[Index].IsEmpty then
    begin
      Result := Index;
      Exit;
    end;
  end;

  Result := NoEmptyLine;
end;

class function TChartLayoutBuilder.MostLines(const Labels: TM4DGen1): Integer;
var
  Lines: TArray<string>;
begin
  Result := 0;

  for Lines in Labels do
  begin
    Result := Max(Result, Length(Lines));
  end;
end;

procedure TChartLayoutBuilder.EmitCategoryLabel(const Lines: TArray<string>; const CenterX, Top: Single;
  const Font: TMarkdownFontStyle);
var
  LineHeight: Single;
  Index: Integer;
  LineTop: Single;
begin
  LineHeight := FMeasurer.LineHeight(Font);

  for Index := 0 to High(Lines) do
  begin
    LineTop := Top + Index * LineHeight;
    EmitCenteredText(Lines[Index], CenterX, LineTop, Font, FTheme.ChartTextColor);
  end;
end;

procedure TChartLayoutBuilder.LayoutBars(const PlotLeft, PlotTop, PlotRight, PlotBottom, AxisMin, AxisMax: Single);
var
  AxisSpan: Single;
  PlotHeight: Single;
  SlotWidth: Double;
  BaseValue: Single;
  BaseY: Double;
  LabelIndex: Integer;
  SlotLeft: Double;
begin
  AxisSpan := AxisMax - AxisMin;
  if AxisSpan <= 0 then
    Exit;

  PlotHeight := PlotBottom - PlotTop;
  SlotWidth := (PlotRight - PlotLeft) / Max(1, FModel.LabelCount);
  BaseValue := Min(Max(0, AxisMin), AxisMax);
  BaseY := PlotBottom - (BaseValue - AxisMin) / AxisSpan * PlotHeight;

  for LabelIndex := 0 to FModel.LabelCount - 1 do
  begin
    SlotLeft := PlotLeft + SlotWidth * LabelIndex;

    if FModel.Stacked then
      EmitStackedBars(LabelIndex, SlotLeft, SlotWidth, BaseY, AxisSpan, PlotHeight)
    else
      EmitGroupedBars(LabelIndex, SlotLeft, SlotWidth, BaseY, AxisMin, AxisSpan, PlotHeight, PlotBottom);
  end;
end;

procedure TChartLayoutBuilder.EmitStackedBars(const LabelIndex: Integer; const SlotLeft, SlotWidth, BaseY,
  AxisSpan, PlotHeight: Single);
var
  BarWidth: Single;
  BarLeft: Double;
  StackTopY: Single;
  StackBottomY: Single;
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  Value: Double;
  SegmentHeight: Double;
  SegmentTop: Single;
  SegmentBottom: Single;
begin
  BarWidth := SlotWidth * FOptions.BarFill(StackedBarFill);
  BarLeft := SlotLeft + (SlotWidth - BarWidth) / 2;
  StackTopY := BaseY;
  StackBottomY := BaseY;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    if LabelIndex >= Dataset.ValueCount then
      Continue;

    Value := Dataset.Values[LabelIndex];
    SegmentHeight := Value / AxisSpan * PlotHeight;

    
    
    if Value >= 0 then
    begin
      SegmentTop := StackTopY - SegmentHeight;
      SegmentBottom := StackTopY;
      StackTopY := SegmentTop;
    end
    else
    begin
      SegmentTop := StackBottomY;
      SegmentBottom := StackBottomY - SegmentHeight;
      StackBottomY := SegmentBottom;
    end;

    EmitRectangle(TLayoutRectF.Create(BarLeft, Min(SegmentTop, SegmentBottom), BarLeft + BarWidth,
      Max(SegmentTop, SegmentBottom)), BarColor(DatasetIndex, LabelIndex), 0, 0);
  end;
end;

procedure TChartLayoutBuilder.EmitGroupedBars(const LabelIndex: Integer; const SlotLeft, SlotWidth, BaseY,
  AxisMin, AxisSpan, PlotHeight, PlotBottom: Single);
var
  GroupWidth: Single;
  BarWidth: Double;
  GroupLeft: Double;
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  Value: Double;
  ValueY: Double;
  BarLeft: Double;
begin
  GroupWidth := SlotWidth * FOptions.BarFill(GroupedBarFill);
  BarWidth := GroupWidth / Max(1, FModel.DatasetCount);
  GroupLeft := SlotLeft + (SlotWidth - GroupWidth) / 2;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    if LabelIndex >= Dataset.ValueCount then
      Continue;

    Value := Dataset.Values[LabelIndex];
    ValueY := PlotBottom - (Value - AxisMin) / AxisSpan * PlotHeight;
    BarLeft := GroupLeft + BarWidth * DatasetIndex;

    EmitRectangle(TLayoutRectF.Create(BarLeft, Min(BaseY, ValueY), BarLeft + BarWidth, Max(BaseY, ValueY)),
      BarColor(DatasetIndex, LabelIndex), 0, 0);
  end;
end;

procedure TChartLayoutBuilder.LayoutLine(const PlotLeft, PlotTop, PlotRight, PlotBottom, AxisMin, AxisMax: Single);
var
  AxisSpan: Single;
  PlotHeight: Single;
  SlotWidth: Double;
  BaseValue: Single;
  BaseY: Double;
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  Color: TLayoutColor;
  Count: Integer;
  Xs: TArray<Single>;
  Ys: TArray<Single>;
  ValueIndex: Integer;
  Polygon: TArray<TLayoutPointF>;
  Index: Integer;
begin
  AxisSpan := AxisMax - AxisMin;
  if AxisSpan <= 0 then
    Exit;

  PlotHeight := PlotBottom - PlotTop;
  SlotWidth := (PlotRight - PlotLeft) / Max(1, FModel.LabelCount);
  BaseValue := Min(Max(0, AxisMin), AxisMax);
  BaseY := PlotBottom - (BaseValue - AxisMin) / AxisSpan * PlotHeight;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    Color := DatasetColor(DatasetIndex);
    Count := Min(Dataset.ValueCount, FModel.LabelCount);
    if Count = 0 then
      Continue;

    
    
    SetLength(Xs, Count);
    SetLength(Ys, Count);

    for ValueIndex := 0 to Count - 1 do
    begin
      Xs[ValueIndex] := PlotLeft + SlotWidth * (ValueIndex + 0.5);
      Ys[ValueIndex] := PlotBottom - (Dataset.Values[ValueIndex] - AxisMin) / AxisSpan * PlotHeight;
    end;

    if Dataset.Fill then
    begin
      
      SetLength(Polygon, Count + 2);
      for Index := 0 to Count - 1 do
      begin
        Polygon[Index] := TLayoutPointF.Create(Xs[Index], Ys[Index]);
      end;
      Polygon[Count] := TLayoutPointF.Create(Xs[Count - 1], BaseY);
      Polygon[Count + 1] := TLayoutPointF.Create(Xs[0], BaseY);
      EmitFilledPolygon(Polygon, Translucent(Color, AreaFillAlphaFactor));
    end;

    for Index := 1 to Count - 1 do
    begin
      EmitLineSegment(Xs[Index - 1], Ys[Index - 1], Xs[Index], Ys[Index], Color, LineStrokeWidth);
    end;
  end;
end;

procedure TChartLayoutBuilder.LayoutPie;
var
  Dataset: IChartDataset;
  SliceCount: Integer;
  Total: Double;
  Index: Integer;
  PlotWidth: Single;
  PlotHeight: Single;
  CenterX: Double;
  CenterY: Double;
  OuterRadius: Double;
  InnerRadius: Double;
  Font: TMarkdownFontStyle;
  LabelRadius: Double;
  StartAngle: Double;
  Value: Double;
  Sweep: Double;
  MidAngle: Double;
  LabelX: Double;
  LabelY: Double;
  Percent: string;
begin
  if FModel.DatasetCount = 0 then
    Exit;

  Dataset := FModel.Datasets[0];
  SliceCount := Min(Dataset.ValueCount, FModel.LabelCount);
  if SliceCount = 0 then
    Exit;

  Total := 0.0;
  for Index := 0 to SliceCount - 1 do
  begin
    Total := Total + Max(0, Dataset.Values[Index]);
  end;

  if Total <= 0 then
    Exit;

  PlotWidth := FRight - FLeft;
  PlotHeight := FBottom - FTop;
  CenterX := (FLeft + FRight) / 2;
  CenterY := (FTop + FBottom) / 2;
  OuterRadius := Min(PlotWidth, PlotHeight) / 2 * PieRadiusFactor;
  if OuterRadius <= 0 then
    Exit;

  InnerRadius := 0.0;
  if FModel.ChartKind = TChartKind.Doughnut then
    InnerRadius := OuterRadius * DoughnutInnerFactor;

  Font := LabelFont;
  LabelRadius := (OuterRadius + InnerRadius) / 2;

  StartAngle := 0.0;
  for Index := 0 to SliceCount - 1 do
  begin
    Value := Max(0, Dataset.Values[Index]);
    Sweep := Value / Total * 360;
    EmitWedge(CenterX, CenterY, OuterRadius, InnerRadius, StartAngle, Sweep, SliceColor(Index));

    if Sweep >= MinLabelSweepDegrees then
    begin
      // Place the label with the same polar convention the wedge uses (0deg at
      // 3 o'clock, sweeping clockwise) so each percentage sits on its own slice.
      MidAngle := (StartAngle + Sweep / 2) * Pi / 180;
      LabelX := CenterX + LabelRadius * Cos(MidAngle);
      LabelY := CenterY + LabelRadius * Sin(MidAngle);
      Percent := Format('%.0f%%', [Value / Total * 100]);
      EmitCenteredText(Percent, LabelX, LabelY - FMeasurer.LineHeight(Font) / 2, Font, FTheme.ChartTextColor);
    end;

    StartAngle := StartAngle + Sweep;
  end;
end;

procedure TChartLayoutBuilder.LayoutHorizontalAxes;
var
  Range: TChartValueRange;
  Axis: TChartValueAxis;
  Font: TMarkdownFontStyle;
  GutterWidth: Double;
  LabelIndex: Integer;
  BottomGutter: Double;
  PlotLeft: Double;
  PlotTop: Single;
  PlotRight: Single;
  PlotBottom: Double;
  PlotAreaInvalid: Boolean;
  AxisSpan: Double;
  Tick: Double;
  Ratio: Double;
  GridX: Double;
  SlotHeight: Double;
  CenterY: Double;
  Size: TLayoutSizeF;
begin
  Range := CollectValueRange;
  Axis := BuildValueAxis(Range);
  Font := LabelFont;

  GutterWidth := 0.0;
  for LabelIndex := 0 to FModel.LabelCount - 1 do
  begin
    GutterWidth := Max(GutterWidth, FMeasurer.MeasureText(FModel.Labels[LabelIndex], Font).Width);
  end;
  GutterWidth := GutterWidth + AxisGap;

  BottomGutter := FMeasurer.LineHeight(Font) + AxisGap;

  PlotLeft := FLeft + GutterWidth;
  PlotTop := FTop;
  PlotRight := FRight;
  PlotBottom := FBottom - BottomGutter;

  PlotAreaInvalid := ((PlotRight <= PlotLeft) or (PlotBottom <= PlotTop));
  if PlotAreaInvalid then
    Exit;

  AxisSpan := Axis.Maximum - Axis.Minimum;
  for Tick in Axis.Ticks do
  begin
    Ratio := (Tick - Axis.Minimum) / AxisSpan;
    GridX := PlotLeft + Ratio * (PlotRight - PlotLeft);
    EmitLineSegment(GridX, PlotTop, GridX, PlotBottom, FTheme.ChartGridLineColor, GridStrokeWidth);
    EmitCenteredText(FOptions.FormatTickLabel(Tick), GridX, PlotBottom + AxisGap, Font, FTheme.ChartTextColor);
  end;

  SlotHeight := (PlotBottom - PlotTop) / Max(1, FModel.LabelCount);
  for LabelIndex := 0 to FModel.LabelCount - 1 do
  begin
    CenterY := PlotTop + SlotHeight * (LabelIndex + 0.5);
    Size := FMeasurer.MeasureText(FModel.Labels[LabelIndex], Font);
    EmitText(FModel.Labels[LabelIndex], PlotLeft - AxisGap - Size.Width, CenterY - Size.Height / 2, Font,
      FTheme.ChartTextColor);
  end;

  LayoutHorizontalBars(PlotLeft, PlotTop, PlotRight, PlotBottom, Axis.Minimum, Axis.Maximum);
end;

procedure TChartLayoutBuilder.LayoutHorizontalBars(const PlotLeft, PlotTop, PlotRight, PlotBottom, AxisMin,
  AxisMax: Single);
var
  AxisSpan: Single;
  PlotWidth: Single;
  SlotHeight: Double;
  BaseValue: Single;
  BaseX: Double;
  LabelIndex: Integer;
  SlotTop: Double;
begin
  AxisSpan := AxisMax - AxisMin;
  if AxisSpan <= 0 then
    Exit;

  PlotWidth := PlotRight - PlotLeft;
  SlotHeight := (PlotBottom - PlotTop) / Max(1, FModel.LabelCount);
  BaseValue := Min(Max(0, AxisMin), AxisMax);
  BaseX := PlotLeft + (BaseValue - AxisMin) / AxisSpan * PlotWidth;

  for LabelIndex := 0 to FModel.LabelCount - 1 do
  begin
    SlotTop := PlotTop + SlotHeight * LabelIndex;

    if FModel.Stacked then
      EmitHorizontalStackedBars(LabelIndex, SlotTop, SlotHeight, BaseX, AxisSpan, PlotWidth)
    else
      EmitHorizontalGroupedBars(LabelIndex, SlotTop, SlotHeight, BaseX, AxisMin, AxisSpan, PlotWidth, PlotLeft);
  end;
end;

procedure TChartLayoutBuilder.EmitHorizontalStackedBars(const LabelIndex: Integer; const SlotTop, SlotHeight, BaseX,
  AxisSpan, PlotWidth: Single);
var
  BarHeight: Single;
  BarTop: Double;
  StackRightX: Single;
  StackLeftX: Single;
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  Value: Double;
  SegmentWidth: Double;
  SegmentLeft: Single;
  SegmentRight: Single;
begin
  BarHeight := SlotHeight * FOptions.BarFill(StackedBarFill);
  BarTop := SlotTop + (SlotHeight - BarHeight) / 2;
  StackRightX := BaseX;
  StackLeftX := BaseX;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    if LabelIndex >= Dataset.ValueCount then
      Continue;

    Value := Dataset.Values[LabelIndex];
    SegmentWidth := Value / AxisSpan * PlotWidth;

    
    
    if Value >= 0 then
    begin
      SegmentLeft := StackRightX;
      SegmentRight := StackRightX + SegmentWidth;
      StackRightX := SegmentRight;
    end
    else
    begin
      SegmentRight := StackLeftX;
      SegmentLeft := StackLeftX + SegmentWidth;
      StackLeftX := SegmentLeft;
    end;

    EmitRectangle(TLayoutRectF.Create(Min(SegmentLeft, SegmentRight), BarTop, Max(SegmentLeft, SegmentRight),
      BarTop + BarHeight), BarColor(DatasetIndex, LabelIndex), 0, 0);
  end;
end;

procedure TChartLayoutBuilder.EmitHorizontalGroupedBars(const LabelIndex: Integer; const SlotTop, SlotHeight, BaseX,
  AxisMin, AxisSpan, PlotWidth, PlotLeft: Single);
var
  GroupHeight: Single;
  BarHeight: Double;
  GroupTop: Double;
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  Value: Double;
  ValueX: Double;
  BarTop: Double;
begin
  GroupHeight := SlotHeight * FOptions.BarFill(GroupedBarFill);
  BarHeight := GroupHeight / Max(1, FModel.DatasetCount);
  GroupTop := SlotTop + (SlotHeight - GroupHeight) / 2;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    if LabelIndex >= Dataset.ValueCount then
      Continue;

    Value := Dataset.Values[LabelIndex];
    ValueX := PlotLeft + (Value - AxisMin) / AxisSpan * PlotWidth;
    BarTop := GroupTop + BarHeight * DatasetIndex;

    EmitRectangle(TLayoutRectF.Create(Min(BaseX, ValueX), BarTop, Max(BaseX, ValueX), BarTop + BarHeight),
      BarColor(DatasetIndex, LabelIndex), 0, 0);
  end;
end;

procedure TChartLayoutBuilder.LayoutRadar;
var
  AxisCount: Integer;
  MaxValue: Double;
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  ValueIndex: Integer;
  CenterX: Double;
  CenterY: Double;
  Radius: Double;
  Font: TMarkdownFontStyle;
  LineHeight: Single;
  Angles: TArray<Single>;
  Index: Integer;
  Ring: Integer;
  RingRadius: Double;
  NextIndex: Integer;
  EdgeX: Double;
  EdgeY: Double;
  Color: TLayoutColor;
  PointCount: Integer;
  Polygon: TArray<TLayoutPointF>;
  Ratio: Double;
begin
  AxisCount := FModel.LabelCount;
  if AxisCount < RadarMinAxes then
    Exit;

  MaxValue := 0.0;
  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    for ValueIndex := 0 to Dataset.ValueCount - 1 do
    begin
      MaxValue := Max(MaxValue, Dataset.Values[ValueIndex]);
    end;
  end;

  if FModel.HasScaleMax then
    MaxValue := FModel.ScaleMax;
  if MaxValue <= 0 then
    MaxValue := 1;

  CenterX := (FLeft + FRight) / 2;
  CenterY := (FTop + FBottom) / 2;
  Radius := Min(FRight - FLeft, FBottom - FTop) / 2 * PieRadiusFactor;
  if Radius <= 0 then
    Exit;

  Font := LabelFont;
  LineHeight := FMeasurer.LineHeight(Font);

  
  SetLength(Angles, AxisCount);
  for Index := 0 to AxisCount - 1 do
  begin
    Angles[Index] := -Pi / 2 + 2 * Pi * Index / AxisCount;
  end;

  for Ring := 1 to RadarRingCount do
  begin
    RingRadius := Radius * Ring / RadarRingCount;
    for Index := 0 to AxisCount - 1 do
    begin
      NextIndex := (Index + 1) mod AxisCount;
      EmitLineSegment(CenterX + RingRadius * Cos(Angles[Index]), CenterY + RingRadius * Sin(Angles[Index]),
        CenterX + RingRadius * Cos(Angles[NextIndex]), CenterY + RingRadius * Sin(Angles[NextIndex]),
        FTheme.ChartGridLineColor, GridStrokeWidth);
    end;
  end;

  for Index := 0 to AxisCount - 1 do
  begin
    EdgeX := CenterX + Radius * Cos(Angles[Index]);
    EdgeY := CenterY + Radius * Sin(Angles[Index]);
    EmitLineSegment(CenterX, CenterY, EdgeX, EdgeY, FTheme.ChartGridLineColor, GridStrokeWidth);
    EmitCenteredText(FModel.Labels[Index], CenterX + (Radius + AxisGap) * Cos(Angles[Index]),
      CenterY + (Radius + AxisGap) * Sin(Angles[Index]) - LineHeight / 2, Font, FTheme.ChartTextColor);
  end;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    Color := DatasetColor(DatasetIndex);
    PointCount := Min(Dataset.ValueCount, AxisCount);
    if PointCount < RadarMinAxes then
      Continue;

    
    SetLength(Polygon, PointCount);
    for Index := 0 to PointCount - 1 do
    begin
      Ratio := Max(0, Dataset.Values[Index]) / MaxValue;
      Polygon[Index] := TLayoutPointF.Create(CenterX + Radius * Ratio * Cos(Angles[Index]),
        CenterY + Radius * Ratio * Sin(Angles[Index]));
    end;

    EmitFilledPolygon(Polygon, Translucent(Color, AreaFillAlphaFactor));

    for Index := 0 to PointCount - 1 do
    begin
      NextIndex := (Index + 1) mod PointCount;
      EmitLineSegment(Polygon[Index].X, Polygon[Index].Y, Polygon[NextIndex].X, Polygon[NextIndex].Y, Color,
        LineStrokeWidth);
    end;
  end;
end;

procedure TChartLayoutBuilder.LayoutScatter;
var
  MinX: Double;
  MaxX: Double;
  MinY: Double;
  MaxY: Double;
  HasPoint: Boolean;
  DatasetIndex: Integer;
  Dataset: IChartDataset;
  PointIndex: Integer;
  ValueX: Double;
  ValueY: Double;
  Font: TMarkdownFontStyle;
  BottomGutter: Double;
  GutterWidth: Double;
  PlotLeft: Double;
  PlotTop: Single;
  PlotRight: Single;
  PlotBottom: Double;
  PlotAreaInvalid: Boolean;
  SpanX: Double;
  SpanY: Double;
  Color: TLayoutColor;
  PlotX: Double;
  PlotY: Double;
begin
  MinX := 0.0;
  MaxX := 0.0;
  MinY := 0.0;
  MaxY := 0.0;
  HasPoint := False;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    for PointIndex := 0 to Dataset.PointCount - 1 do
    begin
      ValueX := Dataset.PointsX[PointIndex];
      ValueY := Dataset.PointsY[PointIndex];
      if not HasPoint then
      begin
        MinX := ValueX;
        MaxX := ValueX;
        MinY := ValueY;
        MaxY := ValueY;
        HasPoint := True;
      end
      else
      begin
        MinX := Min(MinX, ValueX);
        MaxX := Max(MaxX, ValueX);
        MinY := Min(MinY, ValueY);
        MaxY := Max(MaxY, ValueY);
      end;
    end;
  end;

  if not HasPoint then
    Exit;

  if MaxX <= MinX then
    MaxX := MinX + 1;
  if MaxY <= MinY then
    MaxY := MinY + 1;

  Font := LabelFont;
  BottomGutter := FMeasurer.LineHeight(Font) + AxisGap;
  GutterWidth := FMeasurer.MeasureText(FOptions.FormatTickLabel(MaxY), Font).Width + AxisGap;

  PlotLeft := FLeft + GutterWidth;
  PlotTop := FTop;
  PlotRight := FRight;
  PlotBottom := FBottom - BottomGutter;
  PlotAreaInvalid := ((PlotRight <= PlotLeft) or (PlotBottom <= PlotTop));
  if PlotAreaInvalid then
    Exit;

  EmitLineSegment(PlotLeft, PlotTop, PlotLeft, PlotBottom, FTheme.ChartGridLineColor, GridStrokeWidth);
  EmitLineSegment(PlotLeft, PlotBottom, PlotRight, PlotBottom, FTheme.ChartGridLineColor, GridStrokeWidth);

  EmitText(FOptions.FormatTickLabel(MinX), PlotLeft, PlotBottom + AxisGap, Font, FTheme.ChartTextColor);
  EmitCenteredText(FOptions.FormatTickLabel(MaxX), PlotRight, PlotBottom + AxisGap, Font, FTheme.ChartTextColor);
  EmitText(FOptions.FormatTickLabel(MaxY), FLeft, PlotTop, Font, FTheme.ChartTextColor);

  SpanX := MaxX - MinX;
  SpanY := MaxY - MinY;

  for DatasetIndex := 0 to FModel.DatasetCount - 1 do
  begin
    Dataset := FModel.Datasets[DatasetIndex];
    Color := DatasetColor(DatasetIndex);
    for PointIndex := 0 to Dataset.PointCount - 1 do
    begin
      PlotX := PlotLeft + (Dataset.PointsX[PointIndex] - MinX) / SpanX * (PlotRight - PlotLeft);
      PlotY := PlotBottom - (Dataset.PointsY[PointIndex] - MinY) / SpanY * (PlotBottom - PlotTop);
      EmitWedge(PlotX, PlotY, MarkerRadius, 0, 0, FullCircleDegrees, Color);
    end;
  end;
end;

procedure TChartLayoutBuilder.EmitFilledPolygon(const Points: TArray<TLayoutPointF>; const Color: TLayoutColor);
begin
  FCanvas.FillPolygon(Points, Color);
end;

class function TChartLayoutBuilder.Translucent(const Color: TLayoutColor; const Factor: Single): TLayoutColor;
var
  Alpha: Integer;
  NewAlpha: Int64;
begin
  Alpha := (Cardinal(Color) shr 24) and $FF;
  NewAlpha := Round(Alpha * Factor);
  Result := TLayoutColor((Cardinal(NewAlpha) shl 24) or (Cardinal(Color) and $00FFFFFF));
end;

end.
