{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Extensions.Mermaid.Layout;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Ast.Interfaces,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Layout.DisplayList,
  Markdown4D.Layout.BlockOverride,
  Markdown4D.Theme,
  Markdown4D.Extensions.Mermaid,
  Markdown4D.Compat.Str,
  character;

type
  TMermaidLayouter = class
  public
    class procedure Draw(const Model: IMermaidModel; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
    class function BuildDisplayItems(const Model: IMermaidModel; const Bounds: TLayoutRectF;
      const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Node: IMarkdownNode): TArray<IDisplayItem>;
    class function PreferredHeight(const Model: IMermaidModel; const AvailableWidth: Single;
      const Theme: TMarkdownTheme; const Measurer: ITextMeasurer): Single;
  end;

implementation

uses
  Math,
  SysUtils,
  Generics.Collections,
  Generics.Defaults,
  Markdown4D.Defines,
  Markdown4D.Image.Rasterizer,
  Markdown4D.Layout.ExtensionCanvas;

type
  TMermaidNodeBox = record
    X: Single;
    Y: Single;
    Width: Single;
    Height: Single;
    Rank: Integer;
  end;

  TMermaidBaryKey = record
    Bary: Double;
    Node: Integer;
    Ordinal: Integer;
  end;

  TMermaidLayeredMetrics = record
    RankMainStart: TArray<Single>;
    RankMainSize: TArray<Single>;
    RankCrossWidth: TArray<Single>;
    TotalMain: Single;
    TotalCross: Single;
  end;

  // A node's place in a single depth-first walk of the flowchart's original
  // edges: still on the call stack (InProgress) is what tells a back edge apart
  // from an edge into an already-finished subtree.
  TMermaidDfsState = (Unvisited, InProgress, Done);

  // One frame of the depth-first walk's own call stack, kept explicit instead
  // of on the real one: which node, and which of its successor edges to
  // resume from. A frame comes off only once every edge from that node has
  // been visited, the same point the recursive version would set Done.
  TMermaidDfsFrame = record
    NodeIndex: Integer;
    NextEdgePosition: Integer;
  end;

  TMermaidBuilderBase = class
  protected
    const
      DashLength = 7.0;
      DashGap = 4.0;
    var
      FTheme: TMarkdownTheme;
      FMeasurer: ITextMeasurer;
      FCanvas: IExtensionCanvas;
    procedure EmitRectangle(const Bounds: TLayoutRectF; const FillColor, StrokeColor: TLayoutColor;
      const StrokeWidth: Single);
    procedure EmitPolygon(const Points: TArray<TLayoutPointF>; const Color: TLayoutColor);
    procedure EmitFilledAndStrokedPolygon(const Points: TArray<TLayoutPointF>; const FillColor, StrokeColor: TLayoutColor;
      const StrokeWidth: Single);
    procedure EmitFilledAndStrokedWedge(const Center: TLayoutPointF; const Radius: Single;
      const FillColor, StrokeColor: TLayoutColor; const StrokeWidth: Single);
    procedure EmitLine(const StartPoint, EndPoint: TLayoutPointF; const Color: TLayoutColor; const StrokeWidth: Single);
    procedure EmitDashedLine(const StartPoint, EndPoint: TLayoutPointF; const Color: TLayoutColor;
      const StrokeWidth: Single);
    procedure EmitText(const Text: string; const X, Top: Single; const Font: TMarkdownFontStyle;
      const Color: TLayoutColor);
    procedure EmitCenteredText(const Text: string; const CenterX, Top: Single; const Font: TMarkdownFontStyle;
      const Color: TLayoutColor);

  public
    constructor Create(const Theme: TMarkdownTheme; const Measurer: ITextMeasurer;
      const Canvas: IExtensionCanvas);
  end;

  TM4DGen1 = TArray<TArray<string>>;
  TM4DGen2 = TArray<TArray<Integer>>;
  TM4DGen4 = TObjectList<TList<Integer>>;
  TM4DGen3 = TArray<TList<Integer>>;
  TMermaidFlowchartBuilder = class(TMermaidBuilderBase)
  private
    var
      FModel: IMermaidGraph;
    const
      LabelFontSize = 13.0;
      NodePaddingX = 14.0;
      NodePaddingY = 10.0;
      MinNodeWidth = 40.0;
      MinNodeHeight = 30.0;
      RankGap = 46.0;
      SiblingGap = 30.0;
      DiagramMargin = 10.0;
      MaxLabelChars = 20;
      SolidStrokeWidth = 1.5;
      ThickStrokeWidth = 3.0;
      NodeBorderWidth = 1.5;
      ArrowLength = 11.0;
      ArrowHalfWidth = 5.0;
      DiamondWidthFactor = 1.5;
      DiamondHeightFactor = 1.9;
      RoundedCornerPadding = 6.0;
      OrderingSweeps = 2;
      EdgeLabelPadding = 3.0;
      EdgeLabelStub = 10.0;
      ParallelEdgeSpacing = 16.0;
      BackEdgeChannelGap = 22.0;
      UnhandledNodeShapeMessage = 'Unhandled node shape: %d';
    var
      FBounds: TLayoutRectF;
      FBoxes: TArray<TMermaidNodeBox>;
      FLabelLines: TM4DGen1;
      FSuccessors: TM4DGen2;
      FPredecessors: TM4DGen2;
      // Which edges close a cycle. Ranking reverses these, and EmitEdges routes
      // them around the outside of the diagram instead of straight through the
      // stacked nodes (a loop-back edge would otherwise cut a vertical line
      // through every box between its endpoints).
      FIsBackEdge: TArray<Boolean>;
      FContentWidth: Single;
      FContentHeight: Single;
    function LabelFont: TMarkdownFontStyle;
    function NodeFillColor: TLayoutColor;
    function NodeBorderColor: TLayoutColor;
    function EdgeColor: TLayoutColor;
    function LabelColor: TLayoutColor;
    function IsHorizontal: Boolean;
    function IsReversed: Boolean;
    function WrapCaption(const Caption: string): TArray<string>;
    procedure MeasureNodes;
    procedure BuildAdjacency;
    function FindBackEdges(const IsEdgeValid: TArray<Boolean>): TArray<Boolean>;
    procedure MarkBackEdges(const NodeIndex: Integer; const SuccessorEdges: TM4DGen3;
      const State: TArray<TMermaidDfsState>; const IsBackEdge: TArray<Boolean>);
    procedure RankNodes(out MaxRank: Integer);
    procedure LayoutLayered(const MaxRank: Integer);
    function BuildRankMembers(const Members: TM4DGen4;
      const MaxRank: Integer): TM4DGen3;
    function ComputeRankMainSizes(const Members: TM4DGen3; const MaxRank: Integer;
      const Horizontal: Boolean): TArray<Single>;
    function RankGapAfter(const Rank: Integer): Single;
    function ComputeRankMainStarts(const RankMainSize: TArray<Single>; const MaxRank: Integer;
      out TotalMain: Single): TArray<Single>;
    function ComputeRankCrossWidths(const Members: TM4DGen3; const MaxRank: Integer;
      const Horizontal: Boolean; out TotalCross: Single): TArray<Single>;
    procedure PlaceLayeredNodes(const Members: TM4DGen3; const MaxRank: Integer;
      const Horizontal: Boolean; const Metrics: TMermaidLayeredMetrics);
    procedure OrderRanks(const Members: TM4DGen3; const MaxRank: Integer);
    procedure SortRankByAdjacent(const Members: TM4DGen3; const Rank, ReferenceRank: Integer;
      const UsePredecessors: Boolean);
    function BuildReferencePositions(const Reference: TList<Integer>): TArray<Integer>;
    function ComputeBarycenterKeys(const Current: TList<Integer>; const ReferencePosition: TArray<Integer>;
      const UsePredecessors: Boolean): TArray<TMermaidBaryKey>;
    procedure EmitNodes;
    procedure EmitNodeShape(const Index: Integer);
    procedure EmitRectangleNode(const Box: TMermaidNodeBox);
    procedure EmitRoundedNode(const Box: TMermaidNodeBox);
    procedure EmitStadiumNode(const Box: TMermaidNodeBox);
    procedure EmitCircleNode(const Box: TMermaidNodeBox);
    procedure EmitDiamondNode(const Box: TMermaidNodeBox);
    class function BuildRoundedRectanglePoints(const Bounds: TLayoutRectF;
      const CornerRadius: Single): TArray<TLayoutPointF>; static;
    procedure EmitNodeLabel(const Index: Integer);
    procedure EmitEdges;
    procedure EmitArrowHead(const Tip, Direction: TLayoutPointF);
    procedure EmitEdgeLabel(const Caption: string; const Center: TLayoutPointF);
    function ParallelEdgeShift(const EdgeIndex: Integer): TLayoutPointF;
    class function NodeCenter(const Box: TMermaidNodeBox): TLayoutPointF; static;
    class function BorderPoint(const Box: TMermaidNodeBox; const Toward: TLayoutPointF): TLayoutPointF; static;
    class function MainSize(const Box: TMermaidNodeBox; const Horizontal: Boolean): Single; static;
    class function CrossSize(const Box: TMermaidNodeBox; const Horizontal: Boolean): Single; static;

  public
    constructor Create(const Model: IMermaidGraph; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
    procedure Build;
    function ContentHeight: Single;
  end;

  TMermaidActivationBar = record
    Participant: Integer;
    StartY: Single;
    EndY: Single;
  end;

  TMermaidSequenceBuilder = class(TMermaidBuilderBase)
  private
    var
      FModel: IMermaidSequence;
    const
      LabelFontSize = 13.0;
      BoxPaddingX = 12.0;
      BoxPaddingY = 8.0;
      MinBoxWidth = 60.0;
      BaseColumnGap = 60.0;
      LabelColumnPadding = 24.0;
      DiagramMargin = 10.0;
      LifelineTopGap = 12.0;
      LifelineBottomGap = 16.0;
      MessageGap = 40.0;
      MessageLabelGap = 5.0;
      ActivationWidth = 10.0;
      ArrowLength = 10.0;
      ArrowHalfWidth = 4.0;
      CrossHalf = 4.0;
      MessageStrokeWidth = 1.5;
      LifelineStrokeWidth = 1.0;
      ActivationBorderWidth = 1.0;
      NotePaddingX = 8.0;
      NotePaddingY = 6.0;
      NoteGap = 14.0;
      NoteMargin = 16.0;
      SelfLoopWidth = 34.0;
      SelfLoopHalfHeight = 8.0;
    var
      FBounds: TLayoutRectF;
      FBars: TList<TMermaidActivationBar>;
      FWidths: TArray<Single>;
      FCenters: TArray<Single>;
      FMessageY: TArray<Single>;
      FNoteTop: TArray<Single>;
      FNoteHeight: TArray<Single>;
      FBoxTop: Single;
      FBoxBottom: Single;
      FLifelineBottom: Single;
      FContentHeight: Single;
    function LabelFont: TMarkdownFontStyle;
    function BoxFillColor: TLayoutColor;
    function BoxBorderColor: TLayoutColor;
    function LifelineColor: TLayoutColor;
    function MessageColor: TLayoutColor;
    function NoteFillColor: TLayoutColor;
    function LabelColor: TLayoutColor;
    procedure MeasureParticipants;
    procedure LayoutColumns;
    procedure LayoutRows;
    procedure ComputeActivations;
    procedure EmitLifelines;
    procedure EmitParticipants;
    procedure EmitActivations;
    procedure EmitMessages;
    procedure EmitMessage(const Index: Integer);
    procedure EmitSelfMessage(const Index: Integer);
    procedure EmitMessageHead(const TipX, TipY, Direction: Single; const Head: TMermaidMessageHead);
    procedure EmitNotes;
    procedure EmitNote(const Index: Integer);
    procedure EmitConnector(const StartPoint, EndPoint: TLayoutPointF; const Line: TMermaidMessageLine;
      const StrokeWidth: Single);

  public
    constructor Create(const Model: IMermaidSequence; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
    destructor Destroy; override;
    procedure Build;
    function ContentHeight: Single;
  end;

  TMermaidPieBuilder = class(TMermaidBuilderBase)
  private
    var
      FModel: IMermaidPie;
    const
      LabelFontSize = 11.0;
      TitleFontSize = 16.0;
      Padding = 8.0;
      SwatchSize = 10.0;
      SwatchGap = 4.0;
      PieRadiusFactor = 0.9;
      MinLabelSweepDegrees = 18.0;
      AspectRatioWidth = 4.0;
      AspectRatioHeight = 3.0;
    var
      FLeft: Single;
      FTop: Single;
      FRight: Single;
      FBottom: Single;
      FContentHeight: Single;
    function LabelFont: TMarkdownFontStyle;
    function TitleFont: TMarkdownFontStyle;
    function SliceColor(const Index: Integer): TLayoutColor;
    procedure LayoutTitle;
    procedure LayoutLegend;
    procedure LayoutWedges;
    procedure EmitWedge(const CenterX, CenterY, OuterRadius, StartAngle, SweepAngle: Single; const Color: TLayoutColor);

  public
    constructor Create(const Model: IMermaidPie; const Bounds: TLayoutRectF; const Theme: TMarkdownTheme;
      const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
    class function PreferredHeightForWidth(const AvailableWidth: Single): Single; static;
    procedure Build;
    function ContentHeight: Single;
  end;

class function TMermaidLayouter.BuildDisplayItems(const Model: IMermaidModel; const Bounds: TLayoutRectF;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Node: IMarkdownNode): TArray<IDisplayItem>;
var
  Items: TList<IDisplayItem>;
  Canvas: IExtensionCanvas;
begin
  Items := TList<IDisplayItem>.Create;
  try
    Canvas := TDisplayListExtensionCanvas.Create(Measurer, Items, Node);
    Draw(Model, Bounds, Theme, Measurer, Canvas);

    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

class procedure TMermaidLayouter.Draw(const Model: IMermaidModel; const Bounds: TLayoutRectF;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
var
  Builder: TMermaidSequenceBuilder;
  Builder2: TMermaidPieBuilder;
  Builder3: TMermaidFlowchartBuilder;
begin
  case Model.DiagramKind of
    TMermaidDiagramKind.Sequence:
      begin
        Builder := TMermaidSequenceBuilder.Create(Model as IMermaidSequence, Bounds, Theme, Measurer, Canvas);
        try
          Builder.Build;
        finally
          Builder.Free;
        end;
      end;
    TMermaidDiagramKind.Pie:
      begin
        Builder2 := TMermaidPieBuilder.Create(Model as IMermaidPie, Bounds, Theme, Measurer, Canvas);
        try
          Builder2.Build;
        finally
          Builder2.Free;
        end;
      end;
  else
    begin
      Builder3 := TMermaidFlowchartBuilder.Create(Model as IMermaidGraph, Bounds, Theme, Measurer, Canvas);
      try
        Builder3.Build;
      finally
        Builder3.Free;
      end;
    end;
  end;
end;

class function TMermaidLayouter.PreferredHeight(const Model: IMermaidModel; const AvailableWidth: Single;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer): Single;
var
  Items: TList<IDisplayItem>;
  Canvas: IExtensionCanvas;
  Bounds: TLayoutRectF;
  Builder: TMermaidSequenceBuilder;
  PieBounds: TLayoutRectF;
  Builder2: TMermaidPieBuilder;
  Builder3: TMermaidFlowchartBuilder;
begin
  Items := TList<IDisplayItem>.Create;
  try
    Canvas := TDisplayListExtensionCanvas.Create(Measurer, Items, nil);
    Bounds := TLayoutRectF.Create(0, 0, AvailableWidth, AvailableWidth);

    case Model.DiagramKind of
      TMermaidDiagramKind.Sequence:
        begin
          Builder := TMermaidSequenceBuilder.Create(Model as IMermaidSequence, Bounds, Theme, Measurer, Canvas);
          try
            Builder.Build;
            Result := Builder.ContentHeight;
          finally
            Builder.Free;
          end;
        end;
      TMermaidDiagramKind.Pie:
        begin
          PieBounds := TLayoutRectF.Create(0, 0, AvailableWidth, TMermaidPieBuilder.PreferredHeightForWidth(AvailableWidth));
          Builder2 := TMermaidPieBuilder.Create(Model as IMermaidPie, PieBounds, Theme, Measurer, Canvas);
          try
            Builder2.Build;
            Result := Builder2.ContentHeight;
          finally
            Builder2.Free;
          end;
        end;
    else
      begin
        Builder3 := TMermaidFlowchartBuilder.Create(Model as IMermaidGraph, Bounds, Theme, Measurer, Canvas);
        try
          Builder3.Build;
          Result := Builder3.ContentHeight;
        finally
          Builder3.Free;
        end;
      end;
    end;
  finally
    Items.Free;
  end;
end;

constructor TMermaidBuilderBase.Create(const Theme: TMarkdownTheme;
  const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
begin
  inherited Create;

  FTheme := Theme;
  FMeasurer := Measurer;
  FCanvas := Canvas;
end;

procedure TMermaidBuilderBase.EmitRectangle(const Bounds: TLayoutRectF; const FillColor, StrokeColor: TLayoutColor;
  const StrokeWidth: Single);
begin
  FCanvas.FillAndStrokeRectangle(Bounds, FillColor, StrokeColor, StrokeWidth);
end;

procedure TMermaidBuilderBase.EmitPolygon(const Points: TArray<TLayoutPointF>; const Color: TLayoutColor);
begin
  FCanvas.FillPolygon(Points, Color);
end;

procedure TMermaidBuilderBase.EmitFilledAndStrokedPolygon(const Points: TArray<TLayoutPointF>;
  const FillColor, StrokeColor: TLayoutColor; const StrokeWidth: Single);
begin
  FCanvas.FillAndStrokePolygon(Points, FillColor, StrokeColor, StrokeWidth);
end;

procedure TMermaidBuilderBase.EmitFilledAndStrokedWedge(const Center: TLayoutPointF; const Radius: Single;
  const FillColor, StrokeColor: TLayoutColor; const StrokeWidth: Single);
begin
  FCanvas.FillAndStrokeWedge(Center, Radius, 0, 0, 360, FillColor, StrokeColor, StrokeWidth);
end;

procedure TMermaidBuilderBase.EmitLine(const StartPoint, EndPoint: TLayoutPointF; const Color: TLayoutColor;
  const StrokeWidth: Single);
begin
  FCanvas.DrawLine(StartPoint, EndPoint, Color, StrokeWidth);
end;

procedure TMermaidBuilderBase.EmitDashedLine(const StartPoint, EndPoint: TLayoutPointF; const Color: TLayoutColor;
  const StrokeWidth: Single);
var
  DeltaX: Single;
  DeltaY: Single;
  Distance: Double;
  DirectionX: Double;
  DirectionY: Double;
  Position: Double;
  SegmentEndDistance: Double;
  SegmentStart: TLayoutPointF;
  SegmentEnd: TLayoutPointF;
begin
  DeltaX := EndPoint.X - StartPoint.X;
  DeltaY := EndPoint.Y - StartPoint.Y;
  Distance := Sqrt(DeltaX * DeltaX + DeltaY * DeltaY);
  if Distance <= 0 then
    Exit;

  DirectionX := DeltaX / Distance;
  DirectionY := DeltaY / Distance;

  Position := 0.0;
  while Position < Distance do
  begin
    SegmentEndDistance := Min(Position + DashLength, Distance);
    SegmentStart := TLayoutPointF.Create(StartPoint.X + DirectionX * Position,
      StartPoint.Y + DirectionY * Position);
    SegmentEnd := TLayoutPointF.Create(StartPoint.X + DirectionX * SegmentEndDistance,
      StartPoint.Y + DirectionY * SegmentEndDistance);
    EmitLine(SegmentStart, SegmentEnd, Color, StrokeWidth);
    Position := SegmentEndDistance + DashGap;
  end;
end;

procedure TMermaidBuilderBase.EmitText(const Text: string; const X, Top: Single; const Font: TMarkdownFontStyle;
  const Color: TLayoutColor);
begin
  if Text = '' then
    Exit;

  FCanvas.DrawText(TLayoutPointF.Create(X, Top), Text, Font, Color);
end;

procedure TMermaidBuilderBase.EmitCenteredText(const Text: string; const CenterX, Top: Single;
  const Font: TMarkdownFontStyle; const Color: TLayoutColor);
var
  Size: TLayoutSizeF;
begin
  if Text = '' then
    Exit;

  Size := FMeasurer.MeasureText(Text, Font);
  EmitText(Text, CenterX - Size.Width / 2, Top, Font, Color);
end;

constructor TMermaidFlowchartBuilder.Create(const Model: IMermaidGraph; const Bounds: TLayoutRectF;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
begin
  inherited Create(Theme, Measurer, Canvas);

  FModel := Model;

  FBounds := Bounds;
end;

procedure TMermaidFlowchartBuilder.Build;
var
  NodeCount: Integer;
  MaxRank: Integer;
begin
  NodeCount := FModel.NodeCount;
  if NodeCount = 0 then
    Exit;

  MeasureNodes;
  BuildAdjacency;

  
  RankNodes(MaxRank);
  LayoutLayered(MaxRank);

  EmitNodes;
  EmitEdges;
end;

function TMermaidFlowchartBuilder.ContentHeight: Single;
begin
  Result := FContentHeight + 2 * DiagramMargin;
end;

function TMermaidFlowchartBuilder.LabelFont: TMarkdownFontStyle;
begin
  Result := TMarkdownFontStyle.Create(FTheme.BaseFont.FamilyName, LabelFontSize);
end;

function TMermaidFlowchartBuilder.NodeFillColor: TLayoutColor;
begin
  Result := FTheme.CodeBackgroundColor;
end;

function TMermaidFlowchartBuilder.NodeBorderColor: TLayoutColor;
begin
  Result := FTheme.ChartTextColor;
end;

function TMermaidFlowchartBuilder.EdgeColor: TLayoutColor;
begin
  Result := FTheme.ChartTextColor;
end;

function TMermaidFlowchartBuilder.LabelColor: TLayoutColor;
begin
  Result := FTheme.TextColor;
end;

function TMermaidFlowchartBuilder.IsHorizontal: Boolean;
begin
  Result := (FModel.Direction = TMermaidDirection.LR) or (FModel.Direction = TMermaidDirection.RL);
end;

function TMermaidFlowchartBuilder.IsReversed: Boolean;
begin
  Result := (FModel.Direction = TMermaidDirection.BT) or (FModel.Direction = TMermaidDirection.RL);
end;

function TMermaidFlowchartBuilder.WrapCaption(const Caption: string): TArray<string>;
var
  Trimmed: string;
  Words: TArray<string>;
  Collected: TList<string>;
  Current: string;
  Token: string;
begin
  Trimmed := Trim(Caption);
  if Trimmed = '' then
  begin
    Result := [''];
    Exit;
  end;

  Words := Trimmed.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(Words) = 0 then
  begin
    Result := [Trimmed];
    Exit;
  end;

  Collected := TList<string>.Create;
  try
    Current := '';
    for Token in Words do
    begin
      if Current = '' then
        Current := Token
      else if Length(Current) + 1 + Length(Token) <= MaxLabelChars then
        Current := Current + ' ' + Token
      else
      begin
        Collected.Add(Current);
        Current := Token;
      end;
    end;

    if Current <> '' then
      Collected.Add(Current);

    Result := Collected.ToArray;
  finally
    Collected.Free;
  end;
end;

procedure TMermaidFlowchartBuilder.MeasureNodes;
var
  NodeCount: Integer;
  Font: TMarkdownFontStyle;
  LineHeight: Single;
  Index: Integer;
  MermaidNode: IMermaidNode;
  Lines: TArray<string>;
  TextWidth: Double;
  Line: string;
  TextHeight: Single;
  Width: Double;
  Height: Double;
  Diameter: Double;
begin
  NodeCount := FModel.NodeCount;
  SetLength(FBoxes, NodeCount);
  SetLength(FLabelLines, NodeCount);

  Font := LabelFont;
  LineHeight := FMeasurer.LineHeight(Font);

  for Index := 0 to NodeCount - 1 do
  begin
    MermaidNode := FModel.Nodes[Index];
    Lines := WrapCaption(MermaidNode.Caption);
    FLabelLines[Index] := Lines;

    TextWidth := 0.0;
    for Line in Lines do
    begin
      TextWidth := Max(TextWidth, FMeasurer.MeasureText(Line, Font).Width);
    end;

    TextHeight := Length(Lines) * LineHeight;

    Width := Max(MinNodeWidth, TextWidth + 2 * NodePaddingX);
    Height := Max(MinNodeHeight, TextHeight + 2 * NodePaddingY);

    case MermaidNode.Shape of
      TMermaidNodeShape.Diamond:
        begin
          Width := Max(MinNodeWidth, TextWidth * DiamondWidthFactor + 2 * NodePaddingX);
          Height := Max(MinNodeHeight, TextHeight * DiamondHeightFactor + 2 * NodePaddingY);
        end;
      TMermaidNodeShape.Circle:
        begin
          Diameter := Max(TextWidth, TextHeight) + 2 * Max(NodePaddingX, NodePaddingY);
          Width := Max(MinNodeHeight, Diameter);
          Height := Width;
        end;
      TMermaidNodeShape.Stadium:
        Width := Max(MinNodeWidth, TextWidth + 2 * NodePaddingX + Height);
      TMermaidNodeShape.Rounded:
        Width := Max(MinNodeWidth, TextWidth + 2 * NodePaddingX + 2 * RoundedCornerPadding);
      TMermaidNodeShape.Rectangle:
        ;
    else
      raise EMarkdownError.CreateFmt(UnhandledNodeShapeMessage, [Ord(MermaidNode.Shape)]);
    end;

    FBoxes[Index].Width := Width;
    FBoxes[Index].Height := Height;
    FBoxes[Index].Rank := 0;
  end;
end;

// The ranking pass needs an acyclic graph to run a topological sort over, but a
// flowchart is free to loop back to an earlier node (a "no, try again" edge is
// what most decisions are for). A back edge found by depth-first search is
// treated as reversed for ranking only, so the cycle it closes cannot stop the
// sort; EmitEdges still reads FModel.Edges directly and draws every edge,
// back edges included, exactly the way its author pointed it.
procedure TMermaidFlowchartBuilder.BuildAdjacency;
var
  NodeCount: Integer;
  IsEdgeValid: TArray<Boolean>;
  Index: Integer;
  Edge: IMermaidEdge;
  IsBackEdge: TArray<Boolean>;
  SuccessorLists: TM4DGen4;
  PredecessorLists: TM4DGen4;
  RankSource: Integer;
  RankTarget: Integer;
begin
  NodeCount := FModel.NodeCount;

  
  SetLength(IsEdgeValid, FModel.EdgeCount);
  for Index := 0 to FModel.EdgeCount - 1 do
  begin
    Edge := FModel.Edges[Index];
    IsEdgeValid[Index] := (Edge.SourceIndex >= 0) and (Edge.SourceIndex < NodeCount) and
      (Edge.TargetIndex >= 0) and (Edge.TargetIndex < NodeCount) and (Edge.SourceIndex <> Edge.TargetIndex);
  end;

  IsBackEdge := FindBackEdges(IsEdgeValid);
  FIsBackEdge := IsBackEdge;

  SuccessorLists := TM4DGen4.Create(True);
  try
    PredecessorLists := TM4DGen4.Create(True);
    try
      for Index := 0 to NodeCount - 1 do
      begin
        SuccessorLists.Add(TList<Integer>.Create);
        PredecessorLists.Add(TList<Integer>.Create);
      end;

      for Index := 0 to FModel.EdgeCount - 1 do
      begin
        if not IsEdgeValid[Index] then
          Continue;

        Edge := FModel.Edges[Index];
        RankSource := Edge.SourceIndex;
        RankTarget := Edge.TargetIndex;
        if IsBackEdge[Index] then
        begin
          RankSource := Edge.TargetIndex;
          RankTarget := Edge.SourceIndex;
        end;

        SuccessorLists[RankSource].Add(RankTarget);
        PredecessorLists[RankTarget].Add(RankSource);
      end;

      SetLength(FSuccessors, NodeCount);
      SetLength(FPredecessors, NodeCount);

      for Index := 0 to NodeCount - 1 do
      begin
        FSuccessors[Index] := SuccessorLists[Index].ToArray;
        FPredecessors[Index] := PredecessorLists[Index].ToArray;
      end;
    finally
      PredecessorLists.Free;
    end;
  finally
    SuccessorLists.Free;
  end;
end;

// A depth-first search classifies every edge relative to its own traversal:
// an edge into a node still on the call stack is what closes a cycle. Nodes
// and each node's own edges are both visited in the diagram's declaration
// order, so the edge that reads as "loop back to an earlier step" in the
// source is the one found here, rather than an arbitrary other edge of the
// same cycle - the reading order the diagram was authored in is also the one
// that keeps the picture readable.
function TMermaidFlowchartBuilder.FindBackEdges(const IsEdgeValid: TArray<Boolean>): TArray<Boolean>;
var
  NodeCount: Integer;
  SuccessorEdgeLists: TM4DGen4;
  Index: Integer;
  SuccessorEdges: TM4DGen3;
  State: TArray<TMermaidDfsState>;
  NodeIndex: Integer;
begin
  NodeCount := FModel.NodeCount;

  SuccessorEdgeLists := TM4DGen4.Create(True);
  try
    for Index := 0 to NodeCount - 1 do
    begin
      SuccessorEdgeLists.Add(TList<Integer>.Create);
    end;

    for Index := 0 to FModel.EdgeCount - 1 do
    begin
      if IsEdgeValid[Index] then
        SuccessorEdgeLists[FModel.Edges[Index].SourceIndex].Add(Index);
    end;

    
    SetLength(SuccessorEdges, NodeCount);
    for Index := 0 to NodeCount - 1 do
    begin
      SuccessorEdges[Index] := SuccessorEdgeLists[Index];
    end;

    SetLength(Result, FModel.EdgeCount);

    
    SetLength(State, NodeCount);

    for NodeIndex := 0 to NodeCount - 1 do
    begin
      if State[NodeIndex] = TMermaidDfsState.Unvisited then
        MarkBackEdges(NodeIndex, SuccessorEdges, State, Result);
    end;
  finally
    SuccessorEdgeLists.Free;
  end;
end;

// Walked with an explicit TMermaidDfsFrame stack rather than self-recursion,
// so a long chain of nodes (a flowchart can have as many as the diagram
// source declares) cannot grow the call stack one frame per node.
procedure TMermaidFlowchartBuilder.MarkBackEdges(const NodeIndex: Integer;
  const SuccessorEdges: TM4DGen3; const State: TArray<TMermaidDfsState>;
  const IsBackEdge: TArray<Boolean>);
var
  Stack: TList<TMermaidDfsFrame>;
  StartFrame: TMermaidDfsFrame;
  TopIndex: Integer;
  CurrentNode: type of (Stack.List[TopIndex].NodeIndex);
  Edges: TList<Integer>;
  HasMoreEdges: Boolean;
  EdgeIndex: type of (Edges[Stack.List[TopIndex].NextEdgePosition]);
  Target: Integer;
  NextFrame: TMermaidDfsFrame;
begin
  Stack := TList<TMermaidDfsFrame>.Create;
  try
    State[NodeIndex] := TMermaidDfsState.InProgress;

    
    StartFrame.NodeIndex := NodeIndex;
    StartFrame.NextEdgePosition := 0;
    Stack.Add(StartFrame);

    while Stack.Count > 0 do
    begin
      TopIndex := Stack.Count - 1;
      CurrentNode := Stack.List[TopIndex].NodeIndex;
      Edges := SuccessorEdges[CurrentNode];

      HasMoreEdges := Stack.List[TopIndex].NextEdgePosition < Edges.Count;
      if not HasMoreEdges then
      begin
        State[CurrentNode] := TMermaidDfsState.Done;
        Stack.Delete(TopIndex);
        Continue;
      end;

      EdgeIndex := Edges[Stack.List[TopIndex].NextEdgePosition];
      Inc(Stack.List[TopIndex].NextEdgePosition);

      Target := FModel.Edges[EdgeIndex].TargetIndex;

      case State[Target] of
        TMermaidDfsState.InProgress:
          IsBackEdge[EdgeIndex] := True;
        TMermaidDfsState.Unvisited:
          begin
            State[Target] := TMermaidDfsState.InProgress;

            
            NextFrame.NodeIndex := Target;
            NextFrame.NextEdgePosition := 0;
            Stack.Add(NextFrame);
          end;
        TMermaidDfsState.Done:
          ; // A forward or cross edge: it does not close a cycle, ranking keeps it as authored.
      else
        raise EMarkdownError.CreateFmt('Unhandled depth-first search state: %d', [Ord(State[Target])]);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

// Reversing every back edge for ranking (see BuildAdjacency) always leaves an
// acyclic graph - a standard property of depth-first search: every edge that
// is not a back edge already runs from a later finish time to an earlier one,
// and a reversed back edge now does too, so the topological sort below cannot
// fail. If it ever does, that means a back edge was missed, which is a defect
// in this method, not a diagram shape to fall back away from silently.
procedure TMermaidFlowchartBuilder.RankNodes(out MaxRank: Integer);
var
  NodeCount: Integer;
  Indegree: TArray<Integer>;
  Index: Integer;
  Order: TList<Integer>;
  Ready: TQueue<Integer>;
  Current: Integer;
  Next: Integer;
begin
  MaxRank := 0;

  NodeCount := FModel.NodeCount;

  
  SetLength(Indegree, NodeCount);
  for Index := 0 to NodeCount - 1 do
  begin
    Indegree[Index] := Length(FPredecessors[Index]);
  end;

  Order := TList<Integer>.Create;
  try
    Ready := TQueue<Integer>.Create;
    try
      for Index := 0 to NodeCount - 1 do
      begin
        if Indegree[Index] = 0 then
          Ready.Enqueue(Index);
      end;

      while Ready.Count > 0 do
      begin
        Current := Ready.Dequeue;
        Order.Add(Current);

        for Next in FSuccessors[Current] do
        begin
          Dec(Indegree[Next]);
          if Indegree[Next] = 0 then
            Ready.Enqueue(Next);
        end;
      end;
    finally
      Ready.Free;
    end;

    if Order.Count < NodeCount then
      raise EMarkdownError.Create('Mermaid flowchart ranking produced a graph that is still cyclic after back ' +
        'edges were reversed');

    for Current in Order do
    begin
      for Next in FSuccessors[Current] do
      begin
        if FBoxes[Current].Rank + 1 > FBoxes[Next].Rank then
          FBoxes[Next].Rank := FBoxes[Current].Rank + 1;
      end;
    end;

    for Index := 0 to NodeCount - 1 do
    begin
      MaxRank := Max(MaxRank, FBoxes[Index].Rank);
    end;
  finally
    Order.Free;
  end;
end;

procedure TMermaidFlowchartBuilder.LayoutLayered(const MaxRank: Integer);
var
  Horizontal: Boolean;
  Members: TM4DGen4;
  MemberArray: TM4DGen3;
  Metrics: TMermaidLayeredMetrics;
begin
  Horizontal := IsHorizontal;

  Members := TM4DGen4.Create(True);
  try
    MemberArray := BuildRankMembers(Members, MaxRank);

    OrderRanks(MemberArray, MaxRank);

    
    Metrics.RankMainSize := ComputeRankMainSizes(MemberArray, MaxRank, Horizontal);
    Metrics.RankMainStart := ComputeRankMainStarts(Metrics.RankMainSize, MaxRank, Metrics.TotalMain);
    Metrics.RankCrossWidth := ComputeRankCrossWidths(MemberArray, MaxRank, Horizontal, Metrics.TotalCross);

    PlaceLayeredNodes(MemberArray, MaxRank, Horizontal, Metrics);
  finally
    Members.Free;
  end;
end;

function TMermaidFlowchartBuilder.BuildRankMembers(const Members: TM4DGen4;
  const MaxRank: Integer): TM4DGen3;
var
  Rank: Integer;
  NodeCount: Integer;
  Index: Integer;
begin
  for Rank := 0 to MaxRank do
  begin
    Members.Add(TList<Integer>.Create);
  end;

  SetLength(Result, MaxRank + 1);
  for Rank := 0 to MaxRank do
  begin
    Result[Rank] := Members[Rank];
  end;

  NodeCount := FModel.NodeCount;
  for Index := 0 to NodeCount - 1 do
  begin
    Result[FBoxes[Index].Rank].Add(Index);
  end;
end;

function TMermaidFlowchartBuilder.ComputeRankMainSizes(const Members: TM4DGen3;
  const MaxRank: Integer; const Horizontal: Boolean): TArray<Single>;
var
  Rank: Integer;
  Value: Double;
  NodeIndex: Integer;
begin
  SetLength(Result, MaxRank + 1);
  for Rank := 0 to MaxRank do
  begin
    Value := 0.0;
    for NodeIndex in Members[Rank] do
    begin
      Value := Max(Value, MainSize(FBoxes[NodeIndex], Horizontal));
    end;
    Result[Rank] := Value;
  end;
end;

function TMermaidFlowchartBuilder.ComputeRankMainStarts(const RankMainSize: TArray<Single>;
  const MaxRank: Integer; out TotalMain: Single): TArray<Single>;
var
  MainCursor: Double;
  Rank: Integer;
begin
  SetLength(Result, MaxRank + 1);
  MainCursor := 0.0;
  for Rank := 0 to MaxRank do
  begin
    Result[Rank] := MainCursor;
    MainCursor := MainCursor + RankMainSize[Rank];
    if Rank < MaxRank then
      MainCursor := MainCursor + RankGapAfter(Rank);
  end;
  TotalMain := MainCursor;

  if IsReversed then
  begin
    for Rank := 0 to MaxRank do
    begin
      Result[Rank] := TotalMain - Result[Rank] - RankMainSize[Rank];
    end;
  end;
end;

// A labelled edge carries its caption at the midpoint of the line, over an
// opaque background. The gap it crosses has to fit that caption plus visible
// line stubs and the arrowhead, or the label swallows the whole edge and bites
// into the node shapes on either side.
function TMermaidFlowchartBuilder.RankGapAfter(const Rank: Integer): Single;
var
  Font: TMarkdownFontStyle;
  Index: Integer;
  Edge: IMermaidEdge;
  IsValid: Boolean;
  LowRank: Integer;
  HighRank: Integer;
  CrossesThisBoundary: Boolean;
  LabelWidth: type of (FMeasurer.MeasureText(Edge.Caption, Font).Width);
  NeededGap: Double;
begin
  Result := RankGap;

  Font := LabelFont;
  for Index := 0 to FModel.EdgeCount - 1 do
  begin
    Edge := FModel.Edges[Index];
    if Edge.Caption = '' then
      Continue;

    IsValid := (Edge.SourceIndex >= 0) and (Edge.SourceIndex < FModel.NodeCount) and
      (Edge.TargetIndex >= 0) and (Edge.TargetIndex < FModel.NodeCount);
    if not IsValid then
      Continue;

    LowRank := Min(FBoxes[Edge.SourceIndex].Rank, FBoxes[Edge.TargetIndex].Rank);
    HighRank := Max(FBoxes[Edge.SourceIndex].Rank, FBoxes[Edge.TargetIndex].Rank);
    CrossesThisBoundary := (LowRank = Rank) and (HighRank = Rank + 1);
    if not CrossesThisBoundary then
      Continue;

    LabelWidth := FMeasurer.MeasureText(Edge.Caption, Font).Width;
    NeededGap := LabelWidth + 2 * EdgeLabelPadding + ArrowLength + 2 * EdgeLabelStub;
    Result := Max(Result, NeededGap);
  end;
end;

function TMermaidFlowchartBuilder.ComputeRankCrossWidths(const Members: TM4DGen3;
  const MaxRank: Integer; const Horizontal: Boolean; out TotalCross: Single): TArray<Single>;
var
  Rank: Integer;
  Width: Double;
  NodeIndex: Integer;
begin
  SetLength(Result, MaxRank + 1);
  TotalCross := 0.0;
  for Rank := 0 to MaxRank do
  begin
    Width := 0.0;
    for NodeIndex in Members[Rank] do
    begin
      Width := Width + CrossSize(FBoxes[NodeIndex], Horizontal) + SiblingGap;
    end;
    if Width > 0 then
      Width := Width - SiblingGap;
    Result[Rank] := Width;
    TotalCross := Max(TotalCross, Width);
  end;
end;

procedure TMermaidFlowchartBuilder.PlaceLayeredNodes(const Members: TM4DGen3;
  const MaxRank: Integer; const Horizontal: Boolean; const Metrics: TMermaidLayeredMetrics);
var
  OriginX: Double;
  OriginY: Double;
  OriginMain: Double;
  OriginCross: Double;
  Rank: Integer;
  Offset: Double;
  CrossCursor: Double;
  NodeIndex: Integer;
  CrossPos: Double;
  MainPos: Double;
begin
  if Horizontal then
  begin
    FContentWidth := Metrics.TotalMain;
    FContentHeight := Metrics.TotalCross;
  end
  else
  begin
    FContentWidth := Metrics.TotalCross;
    FContentHeight := Metrics.TotalMain;
  end;

  OriginX := FBounds.Left + Max(0.0, (FBounds.Width - FContentWidth) / 2);
  OriginY := FBounds.Top + DiagramMargin;

  OriginMain := OriginY;
  OriginCross := OriginX;
  if Horizontal then
  begin
    OriginMain := OriginX;
    OriginCross := OriginY;
  end;

  for Rank := 0 to MaxRank do
  begin
    Offset := (Metrics.TotalCross - Metrics.RankCrossWidth[Rank]) / 2;
    CrossCursor := 0.0;

    for NodeIndex in Members[Rank] do
    begin
      CrossPos := OriginCross + Offset + CrossCursor;
      MainPos := OriginMain + Metrics.RankMainStart[Rank] +
        (Metrics.RankMainSize[Rank] - MainSize(FBoxes[NodeIndex], Horizontal)) / 2;

      if Horizontal then
      begin
        FBoxes[NodeIndex].X := MainPos;
        FBoxes[NodeIndex].Y := CrossPos;
      end
      else
      begin
        FBoxes[NodeIndex].X := CrossPos;
        FBoxes[NodeIndex].Y := MainPos;
      end;

      CrossCursor := CrossCursor + CrossSize(FBoxes[NodeIndex], Horizontal) + SiblingGap;
    end;
  end;
end;

procedure TMermaidFlowchartBuilder.OrderRanks(const Members: TM4DGen3; const MaxRank: Integer);
var
  Sweep: Integer;
  Rank: Integer;
begin
  for Sweep := 1 to OrderingSweeps do
  begin
    for Rank := 1 to MaxRank do
    begin
      SortRankByAdjacent(Members, Rank, Rank - 1, True);
    end;

    for Rank := MaxRank - 1 downto 0 do
    begin
      SortRankByAdjacent(Members, Rank, Rank + 1, False);
    end;
  end;
end;

procedure TMermaidFlowchartBuilder.SortRankByAdjacent(const Members: TM4DGen3;
  const Rank, ReferenceRank: Integer; const UsePredecessors: Boolean);
var
  Current: TList<Integer>;
  ReferencePosition: TArray<Integer>;
  Keys: TArray<TMermaidBaryKey>;
  Index: Integer;
begin
  Current := Members[Rank];
  if Current.Count <= 1 then
    Exit;

  ReferencePosition := BuildReferencePositions(Members[ReferenceRank]);
  Keys := ComputeBarycenterKeys(Current, ReferencePosition, UsePredecessors);

  TArrayHelper<TMermaidBaryKey>.Sort(Keys, TComparer<TMermaidBaryKey>.Construct(
    function(const Left, Right: TMermaidBaryKey): Integer
    begin
      Result := CompareValue(Left.Bary, Right.Bary);
      if Result = 0 then
        Result := Left.Ordinal - Right.Ordinal;
    end));

  for Index := 0 to Current.Count - 1 do
  begin
    Current[Index] := Keys[Index].Node;
  end;
end;

function TMermaidFlowchartBuilder.BuildReferencePositions(const Reference: TList<Integer>): TArray<Integer>;
var
  Index: Integer;
  Position: Integer;
begin
  SetLength(Result, FModel.NodeCount);
  for Index := 0 to High(Result) do
  begin
    Result[Index] := -1;
  end;

  for Position := 0 to Reference.Count - 1 do
  begin
    Result[Reference[Position]] := Position;
  end;
end;

function TMermaidFlowchartBuilder.ComputeBarycenterKeys(const Current: TList<Integer>;
  const ReferencePosition: TArray<Integer>; const UsePredecessors: Boolean): TArray<TMermaidBaryKey>;
var
  Index: Integer;
  NodeIndex: Integer;
  Neighbors: TArray<Integer>;
  Sum: Double;
  Count: Integer;
  Neighbor: Integer;
begin
  SetLength(Result, Current.Count);

  for Index := 0 to Current.Count - 1 do
  begin
    NodeIndex := Current[Index];

    
    if UsePredecessors then
      Neighbors := FPredecessors[NodeIndex]
    else
      Neighbors := FSuccessors[NodeIndex];

    Sum := 0.0;
    Count := 0;
    for Neighbor in Neighbors do
    begin
      if ReferencePosition[Neighbor] >= 0 then
      begin
        Sum := Sum + ReferencePosition[Neighbor];
        Inc(Count);
      end;
    end;

    if Count > 0 then
      Result[Index].Bary := Sum / Count
    else
      Result[Index].Bary := Index;

    Result[Index].Node := NodeIndex;
    Result[Index].Ordinal := Index;
  end;
end;

procedure TMermaidFlowchartBuilder.EmitNodes;
var
  Index: Integer;
begin
  for Index := 0 to FModel.NodeCount - 1 do
  begin
    EmitNodeShape(Index);
    EmitNodeLabel(Index);
  end;
end;

procedure TMermaidFlowchartBuilder.EmitNodeShape(const Index: Integer);
var
  Box: TMermaidNodeBox;
begin
  Box := FBoxes[Index];

  case FModel.Nodes[Index].Shape of
    TMermaidNodeShape.Rectangle:
      EmitRectangleNode(Box);
    TMermaidNodeShape.Rounded:
      EmitRoundedNode(Box);
    TMermaidNodeShape.Stadium:
      EmitStadiumNode(Box);
    TMermaidNodeShape.Circle:
      EmitCircleNode(Box);
    TMermaidNodeShape.Diamond:
      EmitDiamondNode(Box);
  else
    raise EMarkdownError.CreateFmt(UnhandledNodeShapeMessage, [Ord(FModel.Nodes[Index].Shape)]);
  end;
end;

procedure TMermaidFlowchartBuilder.EmitRectangleNode(const Box: TMermaidNodeBox);
var
  Bounds: TLayoutRectF;
begin
  Bounds := TLayoutRectF.Create(Box.X, Box.Y, Box.X + Box.Width, Box.Y + Box.Height);
  EmitRectangle(Bounds, NodeFillColor, NodeBorderColor, NodeBorderWidth);
end;

procedure TMermaidFlowchartBuilder.EmitRoundedNode(const Box: TMermaidNodeBox);
var
  Bounds: TLayoutRectF;
  Points: TArray<TLayoutPointF>;
begin
  Bounds := TLayoutRectF.Create(Box.X, Box.Y, Box.X + Box.Width, Box.Y + Box.Height);
  Points := BuildRoundedRectanglePoints(Bounds, RoundedCornerPadding);
  EmitFilledAndStrokedPolygon(Points, NodeFillColor, NodeBorderColor, NodeBorderWidth);
end;

procedure TMermaidFlowchartBuilder.EmitStadiumNode(const Box: TMermaidNodeBox);
var
  Bounds: TLayoutRectF;
  Points: TArray<TLayoutPointF>;
begin
  Bounds := TLayoutRectF.Create(Box.X, Box.Y, Box.X + Box.Width, Box.Y + Box.Height);
  Points := BuildRoundedRectanglePoints(Bounds, Box.Height / 2);
  EmitFilledAndStrokedPolygon(Points, NodeFillColor, NodeBorderColor, NodeBorderWidth);
end;

procedure TMermaidFlowchartBuilder.EmitCircleNode(const Box: TMermaidNodeBox);
begin
  EmitFilledAndStrokedWedge(NodeCenter(Box), Min(Box.Width, Box.Height) / 2, NodeFillColor, NodeBorderColor,
    NodeBorderWidth);
end;

procedure TMermaidFlowchartBuilder.EmitDiamondNode(const Box: TMermaidNodeBox);
var
  Center: TLayoutPointF;
  Points: TArray<TLayoutPointF>;
begin
  Center := NodeCenter(Box);
  
  Points := [TLayoutPointF.Create(Center.X, Box.Y), TLayoutPointF.Create(Box.X + Box.Width, Center.Y),
    TLayoutPointF.Create(Center.X, Box.Y + Box.Height), TLayoutPointF.Create(Box.X, Center.Y)];
  EmitFilledAndStrokedPolygon(Points, NodeFillColor, NodeBorderColor, NodeBorderWidth);
end;

class function TMermaidFlowchartBuilder.BuildRoundedRectanglePoints(const Bounds: TLayoutRectF;
  const CornerRadius: Single): TArray<TLayoutPointF>;
var
  MaxRadius: Double;
  Radius: Double;
  CornerCenters: TArray<TLayoutPointF>;
  CornerSegments: Integer;
  Points: TArray<TLayoutPointF>;
  CornerIndex: Integer;
  CornerCenter: TLayoutPointF;
  StartAngle: Double;
  Step: Integer;
  Angle: Double;
begin
  MaxRadius := Min(Bounds.Width, Bounds.Height) / 2;
  Radius := Min(CornerRadius, MaxRadius);

  
  CornerCenters := [TLayoutPointF.Create(Bounds.Right - Radius, Bounds.Top + Radius),
    TLayoutPointF.Create(Bounds.Right - Radius, Bounds.Bottom - Radius),
    TLayoutPointF.Create(Bounds.Left + Radius, Bounds.Bottom - Radius),
    TLayoutPointF.Create(Bounds.Left + Radius, Bounds.Top + Radius)];

  // A quarter turn per corner, so each corner gets the same chord-length
  // smoothness a full circle of this radius would (TMarkdownPolygonRasterizer
  // scales its own segment count as an arc grows, and a rounded rectangle's
  // corner faces the same problem at a wide box or a large corner radius).
  CornerSegments := Max(1, TMarkdownPolygonRasterizer.SegmentsForRadius(Radius) div 4);

  Points := nil;
  for CornerIndex := 0 to High(CornerCenters) do
  begin
    CornerCenter := CornerCenters[CornerIndex];
    StartAngle := CornerIndex * 90.0 - 90.0;

    for Step := 0 to CornerSegments do
    begin
      Angle := DegToRad(StartAngle + Step * 90.0 / CornerSegments);
      Points := Points + [TLayoutPointF.Create(CornerCenter.X + Radius * Cos(Angle),
        CornerCenter.Y + Radius * Sin(Angle))];
    end;
  end;

  Result := Points;
end;

procedure TMermaidFlowchartBuilder.EmitNodeLabel(const Index: Integer);
var
  Box: TMermaidNodeBox;
  Lines: TArray<string>;
  Font: TMarkdownFontStyle;
  LineHeight: Single;
  TotalHeight: Single;
  Top: Double;
  CenterX: Double;
  Line: string;
begin
  Box := FBoxes[Index];
  Lines := FLabelLines[Index];
  Font := LabelFont;
  LineHeight := FMeasurer.LineHeight(Font);
  TotalHeight := Length(Lines) * LineHeight;

  Top := Box.Y + (Box.Height - TotalHeight) / 2;
  CenterX := Box.X + Box.Width / 2;

  for Line in Lines do
  begin
    EmitCenteredText(Line, CenterX, Top, Font, LabelColor);
    Top := Top + LineHeight;
  end;
end;

procedure TMermaidFlowchartBuilder.EmitEdges;
var
  NodeCount: Integer;
  Index: Integer;
  Edge: IMermaidEdge;
  Source: Integer;
  Target: Integer;
  IsValid: Boolean;
  SourceCenter: TLayoutPointF;
  TargetCenter: TLayoutPointF;
  Shift: TLayoutPointF;
  RawStart: TLayoutPointF;
  RawEnd: TLayoutPointF;
  StartPoint: TLayoutPointF;
  EndPoint: TLayoutPointF;
  StrokeWidth: Double;
  LineEnd: TLayoutPointF;
  DeltaX: Single;
  DeltaY: Single;
  Distance: Double;
  Direction: TLayoutPointF;
  Midpoint: TLayoutPointF;
  IsBackEdge: Boolean;
  Rightmost: Single;
  ChannelX: Single;
  NodeIndex: Integer;
  StartSide: TLayoutPointF;
  EndSide: TLayoutPointF;
  Corner1: TLayoutPointF;
  Corner2: TLayoutPointF;
  LastDir: TLayoutPointF;

  // Draw one straight segment with the edge's own stroke, shared by the normal
  // path and by each leg of a routed back edge.
  procedure DrawSegment(const A, B: TLayoutPointF);
  begin
    if Edge.Stroke = TMermaidEdgeStroke.Dashed then
      EmitDashedLine(A, B, EdgeColor, StrokeWidth)
    else
      EmitLine(A, B, EdgeColor, StrokeWidth);
  end;

begin
  NodeCount := FModel.NodeCount;

  // A loop-back edge is routed through a channel just outside the widest box.
  Rightmost := FBounds.Left;
  for NodeIndex := 0 to NodeCount - 1 do
    Rightmost := Max(Rightmost, FBoxes[NodeIndex].X + FBoxes[NodeIndex].Width);
  ChannelX := Rightmost + BackEdgeChannelGap;
  // Keep the channel inside the drawing area when there is room for it.
  if (ChannelX > FBounds.Right - BackEdgeChannelGap) and (FBounds.Right - Rightmost > BackEdgeChannelGap) then
    ChannelX := FBounds.Right - BackEdgeChannelGap;

  for Index := 0 to FModel.EdgeCount - 1 do
  begin
    Edge := FModel.Edges[Index];
    Source := Edge.SourceIndex;
    Target := Edge.TargetIndex;

    IsValid := (Source >= 0) and (Source < NodeCount) and (Target >= 0) and (Target < NodeCount) and
      (Source <> Target);
    if not IsValid then
      Continue;

    SourceCenter := NodeCenter(FBoxes[Source]);
    TargetCenter := NodeCenter(FBoxes[Target]);

    Shift := ParallelEdgeShift(Index);
    RawStart := BorderPoint(FBoxes[Source], TargetCenter);
    RawEnd := BorderPoint(FBoxes[Target], SourceCenter);
    StartPoint := TLayoutPointF.Create(RawStart.X + Shift.X, RawStart.Y + Shift.Y);
    EndPoint := TLayoutPointF.Create(RawEnd.X + Shift.X, RawEnd.Y + Shift.Y);

    StrokeWidth := SolidStrokeWidth;
    if Edge.Stroke = TMermaidEdgeStroke.Thick then
      StrokeWidth := ThickStrokeWidth;

    IsBackEdge := (Index < Length(FIsBackEdge)) and FIsBackEdge[Index];

    if IsBackEdge and not IsHorizontal then
    begin
      // Route the loop back around the right-hand side so it never cuts a
      // line through the boxes stacked between its source and target.
      StartSide := TLayoutPointF.Create(FBoxes[Source].X + FBoxes[Source].Width,
        FBoxes[Source].Y + FBoxes[Source].Height / 2);
      EndSide := TLayoutPointF.Create(FBoxes[Target].X + FBoxes[Target].Width,
        FBoxes[Target].Y + FBoxes[Target].Height / 2);
      Corner1 := TLayoutPointF.Create(ChannelX, StartSide.Y);
      Corner2 := TLayoutPointF.Create(ChannelX, EndSide.Y);

      DrawSegment(StartSide, Corner1);
      DrawSegment(Corner1, Corner2);

      // The last leg runs from the channel back into the target's right edge,
      // so its direction is horizontal towards the box.
      LastDir := TLayoutPointF.Create(-1.0, 0.0);
      LineEnd := TLayoutPointF.Create(EndSide.X + ArrowLength, EndSide.Y);
      if Edge.HasArrowHead then
        EmitArrowHead(EndSide, LastDir);
      DrawSegment(Corner2, LineEnd);

      if Edge.Caption <> '' then
        EmitEdgeLabel(Edge.Caption, TLayoutPointF.Create(ChannelX, (Corner1.Y + Corner2.Y) / 2));
      Continue;
    end;

    LineEnd := EndPoint;

    if Edge.HasArrowHead then
    begin
      DeltaX := EndPoint.X - StartPoint.X;
      DeltaY := EndPoint.Y - StartPoint.Y;
      Distance := Sqrt(DeltaX * DeltaX + DeltaY * DeltaY);

      if Distance > 0 then
      begin
        Direction := TLayoutPointF.Create(DeltaX / Distance, DeltaY / Distance);
        LineEnd := TLayoutPointF.Create(EndPoint.X - Direction.X * ArrowLength, EndPoint.Y - Direction.Y * ArrowLength);
        EmitArrowHead(EndPoint, Direction);
      end;
    end;

    if Edge.Stroke = TMermaidEdgeStroke.Dashed then
      EmitDashedLine(StartPoint, LineEnd, EdgeColor, StrokeWidth)
    else
      EmitLine(StartPoint, LineEnd, EdgeColor, StrokeWidth);

    if Edge.Caption <> '' then
    begin
      Midpoint := TLayoutPointF.Create((StartPoint.X + LineEnd.X) / 2, (StartPoint.Y + LineEnd.Y) / 2);
      EmitEdgeLabel(Edge.Caption, Midpoint);
    end;
  end;
end;

function TMermaidFlowchartBuilder.ParallelEdgeShift(const EdgeIndex: Integer): TLayoutPointF;
var
  Edge: IMermaidEdge;
  PairLow: Integer;
  PairHigh: Integer;
  Count: Integer;
  Position: Integer;
  Other: Integer;
  OtherEdge: IMermaidEdge;
  Offset: Double;
  LowCenter: TLayoutPointF;
  HighCenter: TLayoutPointF;
  DeltaX: Single;
  DeltaY: Single;
  Distance: Double;
begin
  Edge := FModel.Edges[EdgeIndex];
  PairLow := Min(Edge.SourceIndex, Edge.TargetIndex);
  PairHigh := Max(Edge.SourceIndex, Edge.TargetIndex);

  // Fan out every edge that connects the same node pair (parallel and
  // anti-parallel edges) so they no longer draw on top of each other. The
  // offset uses the pair's canonical low->high direction, so a back-edge lands
  // on the opposite side of the forward edge instead of cancelling it out.
  Count := 0;
  Position := 0;
  for Other := 0 to FModel.EdgeCount - 1 do
  begin
    OtherEdge := FModel.Edges[Other];
    if (Min(OtherEdge.SourceIndex, OtherEdge.TargetIndex) = PairLow) and
      (Max(OtherEdge.SourceIndex, OtherEdge.TargetIndex) = PairHigh) then
    begin
      if Other < EdgeIndex then
        Inc(Position);
      Inc(Count);
    end;
  end;

  if Count <= 1 then
  begin
    Result := TLayoutPointF.Create(0, 0);
    Exit;
  end;

  Offset := (Position - (Count - 1) / 2) * ParallelEdgeSpacing;

  LowCenter := NodeCenter(FBoxes[PairLow]);
  HighCenter := NodeCenter(FBoxes[PairHigh]);
  DeltaX := HighCenter.X - LowCenter.X;
  DeltaY := HighCenter.Y - LowCenter.Y;
  Distance := Sqrt(DeltaX * DeltaX + DeltaY * DeltaY);
  if Distance = 0 then
  begin
    Result := TLayoutPointF.Create(0, 0);
    Exit;
  end;

  Result := TLayoutPointF.Create(-DeltaY / Distance * Offset, DeltaX / Distance * Offset);
end;

procedure TMermaidFlowchartBuilder.EmitArrowHead(const Tip, Direction: TLayoutPointF);
var
  BaseX: Double;
  BaseY: Double;
  PerpX: Single;
  PerpY: Single;
  Points: TArray<TLayoutPointF>;
begin
  BaseX := Tip.X - Direction.X * ArrowLength;
  BaseY := Tip.Y - Direction.Y * ArrowLength;
  PerpX := -Direction.Y;
  PerpY := Direction.X;

  
  Points := [Tip, TLayoutPointF.Create(BaseX + PerpX * ArrowHalfWidth, BaseY + PerpY * ArrowHalfWidth),
    TLayoutPointF.Create(BaseX - PerpX * ArrowHalfWidth, BaseY - PerpY * ArrowHalfWidth)];

  EmitPolygon(Points, EdgeColor);
end;

procedure TMermaidFlowchartBuilder.EmitEdgeLabel(const Caption: string; const Center: TLayoutPointF);
var
  Font: TMarkdownFontStyle;
  Size: TLayoutSizeF;
  Bounds: TLayoutRectF;
begin
  Font := LabelFont;
  Size := FMeasurer.MeasureText(Caption, Font);

  Bounds := TLayoutRectF.Create(Center.X - Size.Width / 2 - EdgeLabelPadding,
    Center.Y - Size.Height / 2 - EdgeLabelPadding, Center.X + Size.Width / 2 + EdgeLabelPadding,
    Center.Y + Size.Height / 2 + EdgeLabelPadding);

  EmitRectangle(Bounds, FTheme.BackgroundColor, 0, 0);
  EmitCenteredText(Caption, Center.X, Center.Y - Size.Height / 2, Font, LabelColor);
end;

class function TMermaidFlowchartBuilder.NodeCenter(const Box: TMermaidNodeBox): TLayoutPointF;
begin
  Result := TLayoutPointF.Create(Box.X + Box.Width / 2, Box.Y + Box.Height / 2);
end;

class function TMermaidFlowchartBuilder.BorderPoint(const Box: TMermaidNodeBox;
  const Toward: TLayoutPointF): TLayoutPointF;
var
  CenterX: Double;
  CenterY: Double;
  DeltaX: Double;
  DeltaY: Double;
  HalfWidth: Double;
  HalfHeight: Double;
  Scale: type of (MaxSingle);
begin
  CenterX := Box.X + Box.Width / 2;
  CenterY := Box.Y + Box.Height / 2;
  DeltaX := Toward.X - CenterX;
  DeltaY := Toward.Y - CenterY;

  if (DeltaX = 0) and (DeltaY = 0) then
  begin
    Result := TLayoutPointF.Create(CenterX, CenterY);
    Exit;
  end;

  HalfWidth := Box.Width / 2;
  HalfHeight := Box.Height / 2;

  Scale := MaxSingle;
  if DeltaX <> 0 then
    Scale := Min(Scale, HalfWidth / Abs(DeltaX));
  if DeltaY <> 0 then
    Scale := Min(Scale, HalfHeight / Abs(DeltaY));

  Result := TLayoutPointF.Create(CenterX + DeltaX * Scale, CenterY + DeltaY * Scale);
end;

class function TMermaidFlowchartBuilder.MainSize(const Box: TMermaidNodeBox; const Horizontal: Boolean): Single;
begin
  if Horizontal then
    Result := Box.Width
  else
    Result := Box.Height;
end;

class function TMermaidFlowchartBuilder.CrossSize(const Box: TMermaidNodeBox; const Horizontal: Boolean): Single;
begin
  if Horizontal then
    Result := Box.Height
  else
    Result := Box.Width;
end;

constructor TMermaidSequenceBuilder.Create(const Model: IMermaidSequence; const Bounds: TLayoutRectF;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
begin
  inherited Create(Theme, Measurer, Canvas);

  FModel := Model;

  FBounds := Bounds;
  FBars := TList<TMermaidActivationBar>.Create;
end;

destructor TMermaidSequenceBuilder.Destroy;
begin
  FBars.Free;

  inherited Destroy;
end;

procedure TMermaidSequenceBuilder.Build;
begin
  if FModel.ParticipantCount = 0 then
    Exit;

  MeasureParticipants;
  LayoutColumns;
  LayoutRows;
  ComputeActivations;

  EmitLifelines;
  EmitParticipants;
  EmitActivations;
  EmitMessages;
  EmitNotes;
end;

function TMermaidSequenceBuilder.ContentHeight: Single;
begin
  Result := FContentHeight + 2 * DiagramMargin;
end;

function TMermaidSequenceBuilder.LabelFont: TMarkdownFontStyle;
begin
  Result := TMarkdownFontStyle.Create(FTheme.BaseFont.FamilyName, LabelFontSize);
end;

function TMermaidSequenceBuilder.BoxFillColor: TLayoutColor;
begin
  Result := FTheme.CodeBackgroundColor;
end;

function TMermaidSequenceBuilder.BoxBorderColor: TLayoutColor;
begin
  Result := FTheme.ChartTextColor;
end;

function TMermaidSequenceBuilder.LifelineColor: TLayoutColor;
begin
  Result := FTheme.ChartGridLineColor;
end;

function TMermaidSequenceBuilder.MessageColor: TLayoutColor;
begin
  Result := FTheme.ChartTextColor;
end;

function TMermaidSequenceBuilder.NoteFillColor: TLayoutColor;
begin
  Result := FTheme.CodeBackgroundColor;
end;

function TMermaidSequenceBuilder.LabelColor: TLayoutColor;
begin
  Result := FTheme.TextColor;
end;

procedure TMermaidSequenceBuilder.MeasureParticipants;
var
  Count: Integer;
  Font: TMarkdownFontStyle;
  Index: Integer;
  Participant: IMermaidParticipant;
  Caption: string;
  TextWidth: type of (FMeasurer.MeasureText(Caption, Font).Width);
begin
  Count := FModel.ParticipantCount;
  SetLength(FWidths, Count);

  Font := LabelFont;

  for Index := 0 to Count - 1 do
  begin
    Participant := FModel.Participants[Index];
    Caption := Participant.Caption;
    if Caption = '' then
      Caption := Participant.Id;

    TextWidth := FMeasurer.MeasureText(Caption, Font).Width;
    FWidths[Index] := Max(MinBoxWidth, TextWidth + 2 * BoxPaddingX);
  end;
end;

procedure TMermaidSequenceBuilder.LayoutColumns;
var
  Count: Integer;
  Font: TMarkdownFontStyle;
  MaxLabelWidth: Double;
  Index: Integer;
  Caption: string;
  ColumnGap: Double;
  Cursor: Double;
  TotalWidth: Double;
  OriginX: Double;
begin
  Count := FModel.ParticipantCount;
  Font := LabelFont;

  MaxLabelWidth := 0.0;
  for Index := 0 to FModel.MessageCount - 1 do
  begin
    Caption := FModel.Messages[Index].Caption;
    if Caption <> '' then
      MaxLabelWidth := Max(MaxLabelWidth, FMeasurer.MeasureText(Caption, Font).Width);
  end;

  ColumnGap := Max(BaseColumnGap, MaxLabelWidth + LabelColumnPadding);

  SetLength(FCenters, Count);
  Cursor := FWidths[0] / 2;
  FCenters[0] := Cursor;

  for Index := 1 to Count - 1 do
  begin
    Cursor := Cursor + FWidths[Index - 1] / 2 + ColumnGap + FWidths[Index] / 2;
    FCenters[Index] := Cursor;
  end;

  TotalWidth := FCenters[Count - 1] + FWidths[Count - 1] / 2;
  OriginX := FBounds.Left + Max(DiagramMargin, (FBounds.Width - TotalWidth) / 2);

  for Index := 0 to Count - 1 do
  begin
    FCenters[Index] := FCenters[Index] + OriginX;
  end;
end;

procedure TMermaidSequenceBuilder.LayoutRows;
var
  Font: TMarkdownFontStyle;
  LineHeight: Single;
  OriginY: Double;
  BoxHeight: Double;
  Cursor: Double;
  MessageCount: Integer;
  Index: Integer;
  NoteCount: Integer;
  NoteBoxHeight: Double;
begin
  Font := LabelFont;
  LineHeight := FMeasurer.LineHeight(Font);
  OriginY := FBounds.Top + DiagramMargin;

  FBoxTop := OriginY;
  BoxHeight := LineHeight + 2 * BoxPaddingY;
  FBoxBottom := FBoxTop + BoxHeight;

  Cursor := FBoxBottom + LifelineTopGap;

  MessageCount := FModel.MessageCount;
  SetLength(FMessageY, MessageCount);
  for Index := 0 to MessageCount - 1 do
  begin
    Cursor := Cursor + MessageGap;
    FMessageY[Index] := Cursor;
  end;

  NoteCount := FModel.NoteCount;
  SetLength(FNoteTop, NoteCount);
  SetLength(FNoteHeight, NoteCount);
  NoteBoxHeight := LineHeight + 2 * NotePaddingY;
  for Index := 0 to NoteCount - 1 do
  begin
    Cursor := Cursor + NoteGap;
    FNoteTop[Index] := Cursor;
    FNoteHeight[Index] := NoteBoxHeight;
    Cursor := Cursor + NoteBoxHeight;
  end;

  FLifelineBottom := Cursor + LifelineBottomGap;
  FContentHeight := FLifelineBottom - OriginY;
end;

procedure TMermaidSequenceBuilder.ComputeActivations;
var
  Count: Integer;
  Active: TArray<Boolean>;
  StartY: TArray<Single>;
  Index: Integer;
  Message: IMermaidMessage;
  Y: Single;
  Source: Integer;
  Target: Integer;
  Bar: TMermaidActivationBar;
begin
  Count := FModel.ParticipantCount;

  
  
  SetLength(Active, Count);
  SetLength(StartY, Count);

  for Index := 0 to FModel.MessageCount - 1 do
  begin
    Message := FModel.Messages[Index];
    Y := FMessageY[Index];
    Source := Message.SourceIndex;
    Target := Message.TargetIndex;

    if Message.Activate and (Target >= 0) and (Target < Count) then
    begin
      Active[Target] := True;
      StartY[Target] := Y;
    end;

    if Message.Deactivate and (Source >= 0) and (Source < Count) and Active[Source] then
    begin
      
      Bar.Participant := Source;
      Bar.StartY := StartY[Source];
      Bar.EndY := Y;
      FBars.Add(Bar);
      Active[Source] := False;
    end;
  end;

  for Index := 0 to Count - 1 do
  begin
    if Active[Index] then
    begin
      
      Bar.Participant := Index;
      Bar.StartY := StartY[Index];
      Bar.EndY := FLifelineBottom;
      FBars.Add(Bar);
    end;
  end;
end;

procedure TMermaidSequenceBuilder.EmitLifelines;
var
  Index: Integer;
  CenterX: Single;
begin
  for Index := 0 to FModel.ParticipantCount - 1 do
  begin
    CenterX := FCenters[Index];
    EmitLine(TLayoutPointF.Create(CenterX, FBoxBottom), TLayoutPointF.Create(CenterX, FLifelineBottom),
      LifelineColor, LifelineStrokeWidth);
  end;
end;

procedure TMermaidSequenceBuilder.EmitParticipants;
var
  Font: TMarkdownFontStyle;
  LineHeight: Single;
  TextTop: Double;
  Index: Integer;
  CenterX: Single;
  HalfWidth: Double;
  Bounds: TLayoutRectF;
  Caption: string;
begin
  Font := LabelFont;
  LineHeight := FMeasurer.LineHeight(Font);
  TextTop := FBoxTop + (FBoxBottom - FBoxTop - LineHeight) / 2;

  for Index := 0 to FModel.ParticipantCount - 1 do
  begin
    CenterX := FCenters[Index];
    HalfWidth := FWidths[Index] / 2;
    Bounds := TLayoutRectF.Create(CenterX - HalfWidth, FBoxTop, CenterX + HalfWidth, FBoxBottom);
    EmitRectangle(Bounds, BoxFillColor, BoxBorderColor, ActivationBorderWidth);

    Caption := FModel.Participants[Index].Caption;
    if Caption = '' then
      Caption := FModel.Participants[Index].Id;

    EmitCenteredText(Caption, CenterX, TextTop, Font, LabelColor);
  end;
end;

procedure TMermaidSequenceBuilder.EmitActivations;
var
  Bar: TMermaidActivationBar;
  CenterX: Single;
  Bounds: TLayoutRectF;
begin
  for Bar in FBars do
  begin
    CenterX := FCenters[Bar.Participant];
    Bounds := TLayoutRectF.Create(CenterX - ActivationWidth / 2, Bar.StartY, CenterX + ActivationWidth / 2,
      Bar.EndY);
    EmitRectangle(Bounds, BoxFillColor, BoxBorderColor, ActivationBorderWidth);
  end;
end;

procedure TMermaidSequenceBuilder.EmitMessages;
var
  Index: Integer;
begin
  for Index := 0 to FModel.MessageCount - 1 do
  begin
    EmitMessage(Index);
  end;
end;

procedure TMermaidSequenceBuilder.EmitMessage(const Index: Integer);
var
  Message: IMermaidMessage;
  Count: Integer;
  Source: Integer;
  Target: Integer;
  Y: Single;
  StartX: Single;
  EndX: Single;
  Direction: Double;
  LineEnd: Single;
  Font: TMarkdownFontStyle;
  TextHeight: type of (FMeasurer.MeasureText(Message.Caption, Font).Height);
begin
  Message := FModel.Messages[Index];
  Count := FModel.ParticipantCount;
  Source := Message.SourceIndex;
  Target := Message.TargetIndex;

  if (Source < 0) or (Source >= Count) or (Target < 0) or (Target >= Count) then
    Exit;

  if Source = Target then
  begin
    EmitSelfMessage(Index);
    Exit;
  end;

  Y := FMessageY[Index];
  StartX := FCenters[Source];
  EndX := FCenters[Target];

  Direction := 1.0;
  if EndX < StartX then
    Direction := -1.0;

  LineEnd := EndX;
  if Message.Head <> TMermaidMessageHead.Cross then
    LineEnd := EndX - Direction * ArrowLength;

  EmitConnector(TLayoutPointF.Create(StartX, Y), TLayoutPointF.Create(LineEnd, Y), Message.Line, MessageStrokeWidth);
  EmitMessageHead(EndX, Y, Direction, Message.Head);

  if Message.Caption <> '' then
  begin
    Font := LabelFont;
    TextHeight := FMeasurer.MeasureText(Message.Caption, Font).Height;
    EmitCenteredText(Message.Caption, (StartX + EndX) / 2, Y - MessageLabelGap - TextHeight, Font, LabelColor);
  end;
end;

procedure TMermaidSequenceBuilder.EmitSelfMessage(const Index: Integer);
var
  Message: IMermaidMessage;
  Y: Single;
  X: Single;
  RightX: Double;
  TopY: Double;
  BottomY: Double;
  LineEnd: Single;
  Font: TMarkdownFontStyle;
  TextHeight: type of (FMeasurer.MeasureText(Message.Caption, Font).Height);
begin
  Message := FModel.Messages[Index];
  Y := FMessageY[Index];
  X := FCenters[Message.SourceIndex];
  RightX := X + SelfLoopWidth;
  TopY := Y - SelfLoopHalfHeight;
  BottomY := Y + SelfLoopHalfHeight;

  LineEnd := X;
  if Message.Head <> TMermaidMessageHead.Cross then
    LineEnd := X + ArrowLength;

  EmitConnector(TLayoutPointF.Create(X, TopY), TLayoutPointF.Create(RightX, TopY), Message.Line, MessageStrokeWidth);
  EmitConnector(TLayoutPointF.Create(RightX, TopY), TLayoutPointF.Create(RightX, BottomY), Message.Line,
    MessageStrokeWidth);
  EmitConnector(TLayoutPointF.Create(RightX, BottomY), TLayoutPointF.Create(LineEnd, BottomY), Message.Line,
    MessageStrokeWidth);
  EmitMessageHead(X, BottomY, -1.0, Message.Head);

  if Message.Caption <> '' then
  begin
    Font := LabelFont;
    TextHeight := FMeasurer.MeasureText(Message.Caption, Font).Height;
    EmitCenteredText(Message.Caption, (X + RightX) / 2, TopY - MessageLabelGap - TextHeight, Font, LabelColor);
  end;
end;

procedure TMermaidSequenceBuilder.EmitMessageHead(const TipX, TipY, Direction: Single; const Head: TMermaidMessageHead);
var
  BaseX: Double;
  Points: TArray<TLayoutPointF>;
begin
  BaseX := TipX - Direction * ArrowLength;

  case Head of
    TMermaidMessageHead.Arrow:
      begin
        
        Points := [TLayoutPointF.Create(TipX, TipY), TLayoutPointF.Create(BaseX, TipY - ArrowHalfWidth),
          TLayoutPointF.Create(BaseX, TipY + ArrowHalfWidth)];
        EmitPolygon(Points, MessageColor);
      end;
    TMermaidMessageHead.Open:
      begin
        EmitLine(TLayoutPointF.Create(TipX, TipY), TLayoutPointF.Create(BaseX, TipY - ArrowHalfWidth), MessageColor,
          MessageStrokeWidth);
        EmitLine(TLayoutPointF.Create(TipX, TipY), TLayoutPointF.Create(BaseX, TipY + ArrowHalfWidth), MessageColor,
          MessageStrokeWidth);
      end;
    TMermaidMessageHead.Cross:
      begin
        EmitLine(TLayoutPointF.Create(TipX - CrossHalf, TipY - CrossHalf),
          TLayoutPointF.Create(TipX + CrossHalf, TipY + CrossHalf), MessageColor, MessageStrokeWidth);
        EmitLine(TLayoutPointF.Create(TipX - CrossHalf, TipY + CrossHalf),
          TLayoutPointF.Create(TipX + CrossHalf, TipY - CrossHalf), MessageColor, MessageStrokeWidth);
      end;
  else
    raise EMarkdownError.CreateFmt('Unhandled message head: %d', [Ord(Head)]);
  end;
end;

procedure TMermaidSequenceBuilder.EmitNotes;
var
  Index: Integer;
begin
  for Index := 0 to FModel.NoteCount - 1 do
  begin
    EmitNote(Index);
  end;
end;

procedure TMermaidSequenceBuilder.EmitNote(const Index: Integer);
var
  Note: IMermaidNote;
  Count: Integer;
  FromIndex: Integer;
  ToIndex: Integer;
  Font: TMarkdownFontStyle;
  TextWidth: type of (FMeasurer.MeasureText(Note.Text, Font).Width);
  Top: Single;
  Bottom: Single;
  BoxWidth: Double;
  Left: Single;
  CenterFrom: Single;
  CenterTo: Single;
  Span: Single;
  Right: Double;
begin
  Note := FModel.Notes[Index];
  Count := FModel.ParticipantCount;
  FromIndex := Note.FromIndex;
  ToIndex := Note.ToIndex;

  if (FromIndex < 0) or (FromIndex >= Count) or (ToIndex < 0) or (ToIndex >= Count) then
    Exit;

  Font := LabelFont;
  TextWidth := FMeasurer.MeasureText(Note.Text, Font).Width;
  Top := FNoteTop[Index];
  Bottom := Top + FNoteHeight[Index];

  BoxWidth := TextWidth + 2 * NotePaddingX;
  

  case Note.Placement of
    TMermaidNotePlacement.LeftOf:
      Left := FCenters[FromIndex] - NoteMargin - BoxWidth;
    TMermaidNotePlacement.RightOf:
      Left := FCenters[FromIndex] + NoteMargin;
    TMermaidNotePlacement.Over:
      begin
        CenterFrom := FCenters[FromIndex];
        CenterTo := FCenters[ToIndex];
        Span := Abs(CenterTo - CenterFrom);
        BoxWidth := Max(BoxWidth, Span + 2 * NotePaddingX);
        Left := (CenterFrom + CenterTo) / 2 - BoxWidth / 2;
      end;
  else
    raise EMarkdownError.CreateFmt('Unhandled note placement: %d', [Ord(Note.Placement)]);
  end;

  Right := Left + BoxWidth;
  EmitRectangle(TLayoutRectF.Create(Left, Top, Right, Bottom), NoteFillColor, BoxBorderColor, ActivationBorderWidth);
  EmitCenteredText(Note.Text, (Left + Right) / 2, Top + NotePaddingY, Font, LabelColor);
end;

procedure TMermaidSequenceBuilder.EmitConnector(const StartPoint, EndPoint: TLayoutPointF;
  const Line: TMermaidMessageLine; const StrokeWidth: Single);
begin
  if Line = TMermaidMessageLine.Dashed then
    EmitDashedLine(StartPoint, EndPoint, MessageColor, StrokeWidth)
  else
    EmitLine(StartPoint, EndPoint, MessageColor, StrokeWidth);
end;

constructor TMermaidPieBuilder.Create(const Model: IMermaidPie; const Bounds: TLayoutRectF;
  const Theme: TMarkdownTheme; const Measurer: ITextMeasurer; const Canvas: IExtensionCanvas);
var
  ClampedHeight: Single;
begin
  inherited Create(Theme, Measurer, Canvas);

  FModel := Model;

  ClampedHeight := Min(Bounds.Height, PreferredHeightForWidth(Bounds.Width));

  FLeft := Bounds.Left + Padding;
  FTop := Bounds.Top + Padding;
  FRight := Bounds.Left + Bounds.Width - Padding;
  FBottom := Bounds.Top + ClampedHeight - Padding;
  FContentHeight := ClampedHeight;
end;

class function TMermaidPieBuilder.PreferredHeightForWidth(const AvailableWidth: Single): Single;
begin
  Result := AvailableWidth * AspectRatioHeight / AspectRatioWidth;
end;

procedure TMermaidPieBuilder.Build;
var
  HasPlotArea: Boolean;
begin
  LayoutTitle;
  LayoutLegend;

  HasPlotArea := (FRight > FLeft) and (FBottom > FTop);
  if HasPlotArea then
    LayoutWedges;
end;

function TMermaidPieBuilder.ContentHeight: Single;
begin
  Result := FContentHeight;
end;

function TMermaidPieBuilder.LabelFont: TMarkdownFontStyle;
begin
  Result := TMarkdownFontStyle.Create(FTheme.BaseFont.FamilyName, LabelFontSize);
end;

function TMermaidPieBuilder.TitleFont: TMarkdownFontStyle;
begin
  Result := TMarkdownFontStyle.Create(FTheme.BaseFont.FamilyName, TitleFontSize, True);
end;

function TMermaidPieBuilder.SliceColor(const Index: Integer): TLayoutColor;
var
  Palette: TArray<TLayoutColor>;
  Count: Integer;
begin
  Palette := FTheme.ChartPalette;
  Count := Length(Palette);
  if Count = 0 then
  begin
    Result := FTheme.ChartTextColor;
    Exit;
  end;

  Result := Palette[Index mod Count];
end;

procedure TMermaidPieBuilder.LayoutTitle;
var
  Font: TMarkdownFontStyle;
  Height: Single;
begin
  if FModel.Title = '' then
    Exit;

  Font := TitleFont;
  Height := FMeasurer.LineHeight(Font);
  EmitCenteredText(FModel.Title, (FLeft + FRight) / 2, FTop, Font, FTheme.ChartTextColor);
  FTop := FTop + Height + Padding;
end;

procedure TMermaidPieBuilder.LayoutLegend;
var
  SliceCount: Integer;
  Font: TMarkdownFontStyle;
  RowHeight: Double;
  ColumnWidth: Double;
  Index: Integer;
  Width: Double;
  ColumnX: Double;
  RowY: Single;
  SwatchTop: Double;
begin
  SliceCount := FModel.SliceCount;
  if SliceCount = 0 then
    Exit;

  Font := LabelFont;
  RowHeight := Max(FMeasurer.LineHeight(Font), SwatchSize);

  ColumnWidth := 0.0;
  for Index := 0 to SliceCount - 1 do
  begin
    Width := SwatchSize + SwatchGap + FMeasurer.MeasureText(FModel.Slices[Index].Caption, Font).Width;
    ColumnWidth := Max(ColumnWidth, Width);
  end;

  ColumnX := FRight - ColumnWidth;

  RowY := FTop;
  for Index := 0 to SliceCount - 1 do
  begin
    SwatchTop := RowY + (RowHeight - SwatchSize) / 2;
    EmitRectangle(TLayoutRectF.Create(ColumnX, SwatchTop, ColumnX + SwatchSize, SwatchTop + SwatchSize),
      SliceColor(Index), 0, 0);
    EmitText(FModel.Slices[Index].Caption, ColumnX + SwatchSize + SwatchGap, RowY, Font, FTheme.ChartTextColor);
    RowY := RowY + RowHeight;
  end;

  FRight := FRight - ColumnWidth - Padding;
end;

procedure TMermaidPieBuilder.LayoutWedges;
var
  SliceCount: Integer;
  Total: Double;
  Index: Integer;
  PlotWidth: Single;
  PlotHeight: Single;
  CenterX: Double;
  CenterY: Double;
  OuterRadius: Double;
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
  SliceCount := FModel.SliceCount;
  if SliceCount = 0 then
    Exit;

  Total := 0.0;
  for Index := 0 to SliceCount - 1 do
  begin
    Total := Total + Max(0, FModel.Slices[Index].Value);
  end;

  PlotWidth := FRight - FLeft;
  PlotHeight := FBottom - FTop;
  CenterX := (FLeft + FRight) / 2;
  CenterY := (FTop + FBottom) / 2;

  OuterRadius := Min(PlotWidth, PlotHeight) / 2 * PieRadiusFactor;
  if OuterRadius <= 0 then
    OuterRadius := 1;

  Font := LabelFont;
  LabelRadius := OuterRadius / 2;

  StartAngle := 0.0;
  for Index := 0 to SliceCount - 1 do
  begin
    Value := Max(0, FModel.Slices[Index].Value);

    Sweep := 360 / SliceCount;
    if Total > 0 then
      Sweep := Value / Total * 360;

    EmitWedge(CenterX, CenterY, OuterRadius, StartAngle, Sweep, SliceColor(Index));

    if (Sweep >= MinLabelSweepDegrees) and (Total > 0) then
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

procedure TMermaidPieBuilder.EmitWedge(const CenterX, CenterY, OuterRadius, StartAngle, SweepAngle: Single;
  const Color: TLayoutColor);
begin
  FCanvas.FillWedge(TLayoutPointF.Create(CenterX, CenterY), OuterRadius, 0, StartAngle, SweepAngle, Color);
end;

end.
