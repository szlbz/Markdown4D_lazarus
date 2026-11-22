{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Viewer.Model;

{$SCOPEDENUMS ON}

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  Generics.Collections,
  Markdown4D.Ast.Interfaces,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Layout.DisplayList,
  Markdown4D.Layout.SourceLineMap,
  Markdown4D.Layout.TextAnchor,
  Markdown4D.Layout.TextSearch,
  Markdown4D.Theme;

type
  TMarkdownImageSlotState = (Unknown, Requested, Loaded, Failed);

  TMarkdownFoundRange = record
    ItemIndex: Integer;
    StartCharacter: Integer;
    CharacterCount: Integer;
    class function Create(const ItemIndex, StartCharacter, CharacterCount: Integer): TMarkdownFoundRange; static;
  end;

  TMarkdownCodeBlockRegion = record
    Rect: TLayoutRectF;
    Text: string;
    class function Create(const Rect: TLayoutRectF; const Text: string): TMarkdownCodeBlockRegion; static;
  end;

  // Raised when a block override or a document processor fails. The document
  // shows without what that extension would have drawn or added.
  TMarkdownExtensionErrorEvent = procedure(const Sender: TObject; const Extension: string;
    const Error: Exception) of object;

  TMarkdownViewerModel = class(TNoRefCountObject, IMarkdownImageSizeProvider, IMarkdownExtensionErrorSink,
    IMarkdownDisclosureState)
  private
    type
      TTextPosition = TMarkdownTextPosition;
      TImageSlot = record
        State: TMarkdownImageSlotState;
        Size: TLayoutSizeF;
      end;
      TTextRange = record
        StartPosition: TTextPosition;
        EndPosition: TTextPosition;
      end;
      TSelectionAnchors = record
        Anchor: TMarkdownTextAnchor;
        Extent: TMarkdownTextAnchor;
        UnitStart: TMarkdownTextAnchor;
        UnitEnd: TMarkdownTextAnchor;
      end;
      // What a press and a drag select by: characters after a single click,
      // whole words after a double click, whole lines after a triple click.
      TSelectionUnit = (Character, Word, Line);
      TCharacterClass = (WordCharacter, Space, Other);
    const
      DefaultFlushIntervalMilliseconds = 100;
      BottomEpsilon = 0.5;
      LineTopEpsilon = 0.5;
      CopiedIndentWidth = 2;
      CopiedSpace = ' ';
      CopiedTab = #9;
      AnchorMark = '#';
    var
      FTheme: TMarkdownTheme;
      FMeasurer: ITextMeasurer;
      FText: string;
      FPendingMarkdown: string;
      FDirty: Boolean;
      FDirtySince: Int64;
      FFlushIntervalMilliseconds: Cardinal;
      FViewportWidth: Single;
      FViewportHeight: Single;
      FScrollOffset: Single;
      FDisplayList: IMarkdownDisplayList;
      FDocument: IMarkdownDocument;
      FLayoutCount: Integer;
      FLastLayoutMilliseconds: Int64;
      FShouldAutoFollow: Boolean;
      FSelectionActive: Boolean;
      FAnchor: TTextPosition;
      FExtent: TTextPosition;
      FSelectionUnit: TSelectionUnit;
      FUnitRange: TTextRange;
      FHighlightNeedle: string;
      FHighlightOptions: TMarkdownFindOptions;
      FHighlightRects: TArray<TLayoutRectF>;
      FImageSlots: TDictionary<string, TImageSlot>;
      FImageSlotOrder: TList<string>;
      FOnExtensionError: TMarkdownExtensionErrorEvent;
      FZoom: Integer;
      FZoomedTheme: TMarkdownTheme;
      // The <details> sections the reader opened or closed, by the source
      // offset of their opening block; every other section shows as its tag asks.
      FToggledDisclosures: TList<Integer>;
      FScrollerOffsets: TDictionary<Integer, Single>;
      FScrollers: TArray<Integer>;
      FDraggedScroller: Integer;
      FThumbGrab: Single;
      FSourceLines: TMarkdownSourceLineMap;
      // The layout the source line map was built for; it is built again on
      // first use after the next layout.
      FSourceLinesLayoutCount: Integer;
    procedure Relayout;
    procedure RefreshSourceLines;
    function ZoomFactor: Single;
    function LayoutTheme: TMarkdownTheme;
    procedure RefreshZoomedTheme;
    function TryCaptureTopLine(out TopLine: TMarkdownTextAnchor; out Inset: Single): Boolean;
    procedure ScrollToTopLine(const TopLine: TMarkdownTextAnchor; const Inset: Single);
    function TryCaptureSelection(out Selection: TSelectionAnchors): Boolean;
    function TryRestoreSelection(const Selection: TSelectionAnchors): Boolean;
    procedure RegisterImageSlots;
    function TryFindTextRunBounds(out FirstIndex, LastIndex: Integer): Boolean;
    function TryGetEverythingRange(out Range: TTextRange): Boolean;
    function IsEverythingSelected: Boolean;
    function TryResolvePosition(const Point: TLayoutPointF; out Position: TTextPosition): Boolean;
    function NearestCharacterBoundary(const Run: IDisplayTextRun; const X: Single): Integer;
    function TrySelectableRun(const Index: Integer; out Run: IDisplayTextRun): Boolean;
    function TryResolveCharacter(const Point: TLayoutPointF; out Position: TTextPosition): Boolean;
    function CharacterUnderX(const Run: IDisplayTextRun; const X: Single): Integer;
    function SelectUnitAt(const Point: TLayoutPointF; const SelectionUnit: TSelectionUnit): Boolean;
    procedure ExtendUnitSelection(const Position: TTextPosition);
    function UnitRangeAt(const Position: TTextPosition): TTextRange;
    function WordRangeAt(const Position: TTextPosition): TTextRange;
    function WordStartFrom(const Position: TTextPosition): TTextPosition;
    function WordEndFrom(const Position: TTextPosition): TTextPosition;
    function LineRangeAt(const Position: TTextPosition): TTextRange;
    function LineOriginIndex(const ItemIndex: Integer): Integer;
    function LineStartIndexFrom(const ItemIndex: Integer): Integer;
    function LineEndIndexFrom(const ItemIndex: Integer): Integer;
    function TryAdjacentRun(const ItemIndex, Direction: Integer; out AdjacentIndex: Integer;
      out Run: IDisplayTextRun): Boolean;
    class function ContinuesWord(const Run, Before: IDisplayTextRun): Boolean; static;
    class function ContinuesLine(const Run, Before: IDisplayTextRun): Boolean; static;
    class function CharacterClassOf(const Character: Char): TCharacterClass; static;
    function TryFindScrollerAt(const Point: TLayoutPointF; out Index: Integer): Boolean;
    function TryFindScrollerOf(const ItemIndex: Integer; out Index: Integer): Boolean;
    function IsOverScrollerTrack(const Point: TLayoutPointF): Boolean;
    procedure SetScrollerOffset(const Index: Integer; const Offset: Single);
    procedure RestoreScrollerOffsets;
    procedure RevealInScroller(const ItemIndex: Integer);
    function ClipToScroller(const ItemIndex: Integer; const Rect: TLayoutRectF): TLayoutRectF;
    function NextMatchAfterSelection(const Matches: TArray<TMarkdownFoundRange>): TMarkdownFoundRange;
    function PreviousMatchBeforeSelection(const Matches: TArray<TMarkdownFoundRange>): TMarkdownFoundRange;
    function HasCaret: Boolean;
    procedure SelectMatch(const Match: TMarkdownFoundRange);
    function RangeOfMatch(const Match: TMarkdownFoundRange): TTextRange;
    function RangeInRun(const Run: IDisplayTextRun; const Match: TMarkdownFoundRange): TTextRange;
    function MatchRun(const Match: TMarkdownFoundRange): IDisplayTextRun;
    function DistinctMatches(const Matches: TArray<TMarkdownFoundRange>): TArray<TMarkdownFoundRange>;
    procedure RefreshHighlights;
    function BoundsInRun(const Run: IDisplayTextRun; const Range: TTextRange): TLayoutRectF;
    function MatchBounds(const Match: TMarkdownFoundRange): TLayoutRectF;
    function IsWithinViewport(const Bounds: TLayoutRectF): Boolean;
    function NormalizeSelection: TTextRange;
    class function ComparePositions(const Left, Right: TTextPosition): Integer;
    function SelectedCharacterRange(const Run: IDisplayTextRun; const ItemIndex: Integer;
      const StartPosition, EndPosition: TTextPosition; out CharFrom, CharTo: Integer): Boolean;
    function BlockIndexOfItem(const ItemIndex: Integer): Integer;
    class function SeparatorBefore(const Run: IDisplayTextRun; const StartsBlock: Boolean;
      const PreviousTop: Single): string; static;
    class function FallbackSeparator(const Run: IDisplayTextRun; const StartsBlock: Boolean;
      const PreviousTop: Single): string; static;
    function TryFindSelectionEdges(out FirstRun, LastRun: IDisplayTextRun;
                                   out FirstCharacter, LastCharacter: Integer): Boolean;
    function PrefixWidth(const Run: IDisplayTextRun; const CharacterCount: Integer): Single;
    class function CodeTextOf(const Code: IMarkdownCodeBlock): string; static;
    function GetText: string;
    procedure SetText(const Value: string);
    function GetPendingText: string;
    function GetFullText: string;
    function GetDisplayList: IMarkdownDisplayList;
    function GetLayoutCount: Integer;
    function GetIsDirty: Boolean;
    function GetShouldAutoFollow: Boolean;
    function GetFlushIntervalMilliseconds: Cardinal;
    procedure SetFlushIntervalMilliseconds(const Value: Cardinal);
    function GetScrollOffset: Single;
    procedure SetZoom(const Value: Integer);
    procedure SetScrollOffset(const Value: Single);

  public
    constructor Create(const Theme: TMarkdownTheme; const Measurer: ITextMeasurer);
    destructor Destroy; override;
    procedure SetViewport(const Width, Height: Single);
    procedure ApplyTheme(const Theme: TMarkdownTheme);
    procedure RefreshLayout;
    function IsScrolledToBottom: Boolean;
    procedure AppendMarkdown(const Markdown: string; const NowMilliseconds: Int64);
    function TryFlush(const NowMilliseconds: Int64): Boolean;
    procedure SetSelectionAnchor(const Point: TLayoutPointF);
    procedure SetSelectionExtent(const Point: TLayoutPointF);
    procedure ClearSelection;
    function SelectAll: Boolean;
    // Select the word or the line under the point, and make a drag that
    // follows extend the selection by whole words or lines. False when there
    // is no text to select.
    function SelectWordAt(const Point: TLayoutPointF): Boolean;
    function SelectLineAt(const Point: TLayoutPointF): Boolean;
    function HasSelectableText: Boolean;
    function HasSelection: Boolean;
    function SelectionRects: TArray<TLayoutRectF>;
    function SelectedText: string;
    // Answers the stretch of markdown source the selection was rendered from,
    // so a formatting command can change exactly those characters. False when
    // there is no selection, or when the runs it covers carry no source of
    // their own, as happens inside a diagram an extension drew.
    function TryGetSelectionSourceSegment(out Segment: TMarkdownSegment): Boolean;
    // The markdown behind the selection, for Copy as Markdown; empty without a
    // selection. A selection of everything gives the whole source, including
    // lines that render nothing.
    function SelectedMarkdown: string;
    // The scroll offset that brings the heading a link like #getting-started
    // points at to the top of the view. The anchor may be percent-encoded.
    function TryGetAnchorOffset(const Anchor: string; out Offset: Single): Boolean;
    // The parsed document, for hosts that build their own outline.
    function GetDocument: IMarkdownDocument;
    property Document: IMarkdownDocument read GetDocument;
    // Where a line of Text shows, as the scroll offset that brings it to the
    // top of the view, and which line shows at an offset. Lines count from 0.
    // A line that renders nothing of its own, such as a blank line, falls
    // between its neighbours.
    function SourceLineToScrollOffset(const SourceLine: Integer): Single;
    function ScrollOffsetToSourceLine(const Offset: Single): Integer;
    function PendingImageSources: TArray<string>;
    procedure NotifyImageArrived(const Source: string; const Size: TLayoutSizeF);
    procedure NotifyImageFailed(const Source: string);
    function ImageSlotState(const Source: string): TMarkdownImageSlotState;
    function TryGetImageSize(const Source: string; out Size: TLayoutSizeF): Boolean;
    procedure ExtensionFailed(const Extension: string; const Error: Exception);
    function FindText(const Needle: string): TArray<TMarkdownFoundRange>; overload;
    function FindText(const Needle: string; const Options: TMarkdownFindOptions): TArray<TMarkdownFoundRange>; overload;
    // How many stops a walk with TrySelectNextMatch makes: a formula counts
    // once, however often the needle occurs in its source.
    function MatchCount(const Needle: string): Integer; overload;
    function MatchCount(const Needle: string; const Options: TMarkdownFindOptions): Integer; overload;
    // Which of those stops the selection covers, counted from 0; -1 when the
    // selection is not a match.
    function MatchIndex(const Needle: string; const Options: TMarkdownFindOptions): Integer;
    // Select the first match after the start of the current selection, or
    // from the caret when nothing is selected, or else the first match in the
    // document, so a repeated search walks through every match. A match in a
    // formula selects the whole formula. False when the needle does not
    // occur; the selection is then left as is.
    function TrySelectNextMatch(const Needle: string; out Match: TMarkdownFoundRange): Boolean; overload;
    function TrySelectNextMatch(const Needle: string; const Options: TMarkdownFindOptions;
                                out Match: TMarkdownFoundRange): Boolean; overload;
    // The same walk backwards: the last match before the start of the
    // selection or the caret, or the last match in the document.
    function TrySelectPreviousMatch(const Needle: string; out Match: TMarkdownFoundRange): Boolean; overload;
    function TrySelectPreviousMatch(const Needle: string; const Options: TMarkdownFindOptions;
                                    out Match: TMarkdownFoundRange): Boolean; overload;
    // Mark every match of the needle, independently of the selection. The
    // marks follow the document through every relayout until they are
    // cleared or the needle is empty. A formula is marked once, however often
    // the needle occurs in its source.
    procedure HighlightMatches(const Needle: string); overload;
    procedure HighlightMatches(const Needle: string; const Options: TMarkdownFindOptions); overload;
    procedure ClearHighlights;
    function HighlightCount: Integer;
    function HighlightRectsWithin(const Viewport: TLayoutRectF): TArray<TLayoutRectF>;
    // The scroll offset that brings the match to the middle of the view, with
    // the lines around it, as a browser does. False when it is in view
    // already, so stepping through the matches on one screen does not make the
    // content jump.
    function TryGetScrollTarget(const Match: TMarkdownFoundRange; out Offset: Single): Boolean;
    function CodeBlockRegions: TArray<TMarkdownCodeBlockRegion>;
    // A display formula wider than the column scrolls sideways in its band.
    // ScrollSideways moves the one under Point by Delta (positive to the
    // right) and is False when there is none there. A press on its track
    // starts dragging the thumb, which DragScrollerThumb follows until
    // EndScrollerDrag.
    function ScrollSideways(const Point: TLayoutPointF; const Delta: Single): Boolean;
    function TryBeginScrollerDrag(const Point: TLayoutPointF): Boolean;
    procedure DragScrollerThumb(const Point: TLayoutPointF);
    procedure EndScrollerDrag;
    function IsDraggingScroller: Boolean;
    function TryGetCodeBlockAt(const Point: TLayoutPointF; out Region: TMarkdownCodeBlockRegion): Boolean;
    // The <details> section whose summary line is under the point. Key
    // identifies the section to ToggleDisclosure.
    function TryGetDisclosureAt(const Point: TLayoutPointF; out Key: Integer): Boolean;
    // Opens a closed section or closes an open one, and lays out again. Setting
    // Text shows every section as its tag asks once more.
    procedure ToggleDisclosure(const Key: Integer);
    function IsDisclosureOpen(const Key: Integer; const OpenByDefault: Boolean): Boolean;
    property Text: string read GetText write SetText;
    property PendingText: string read GetPendingText;
    property FullText: string read GetFullText;
    property DisplayList: IMarkdownDisplayList read GetDisplayList;
    property LayoutCount: Integer read GetLayoutCount;
    // How long the last layout took, so a host can pace work that lays out again.
    property LastLayoutMilliseconds: Int64 read FLastLayoutMilliseconds;
    property IsDirty: Boolean read GetIsDirty;
    property ShouldAutoFollow: Boolean read GetShouldAutoFollow;
    property FlushIntervalMilliseconds: Cardinal read GetFlushIntervalMilliseconds write SetFlushIntervalMilliseconds;
    property ScrollOffset: Single read GetScrollOffset write SetScrollOffset;
    // In percent. Every font, length and image of the theme grows with it;
    // the line at the top of the view stays there.
    property Zoom: Integer read FZoom write SetZoom;
    property OnExtensionError: TMarkdownExtensionErrorEvent read FOnExtensionError write FOnExtensionError;
  end;

implementation

uses
  Math,
  System.Diagnostics,
  character,
  Markdown4D.Compat.NetEncoding,
  Markdown4D,
  Markdown4D.Defines,
  Markdown4D.Layout.BlockOverride,
  Markdown4D.Layout.Engine,
  Markdown4D.Layout.HitTest,
  Markdown4D.Layout.SourceMapping,
  Markdown4D.Layout.SelectedMarkdown,
  Markdown4D.Toc,
  Markdown4D.Layout.Zoom;

class function TMarkdownFoundRange.Create(const ItemIndex, StartCharacter,
  CharacterCount: Integer): TMarkdownFoundRange;
begin
  Result.ItemIndex := ItemIndex;
  Result.StartCharacter := StartCharacter;
  Result.CharacterCount := CharacterCount;
end;

class function TMarkdownCodeBlockRegion.Create(const Rect: TLayoutRectF;
  const Text: string): TMarkdownCodeBlockRegion;
begin
  Result.Rect := Rect;
  Result.Text := Text;
end;

constructor TMarkdownViewerModel.Create(const Theme: TMarkdownTheme; const Measurer: ITextMeasurer);
begin
  inherited Create;

  FTheme := Theme;
  FMeasurer := Measurer;
  FFlushIntervalMilliseconds := DefaultFlushIntervalMilliseconds;
  FZoom := TMarkdownZoom.DefaultPercent;
  FImageSlots := TDictionary<string, TImageSlot>.Create;
  FImageSlotOrder := TList<string>.Create;
  FToggledDisclosures := TList<Integer>.Create;
  FScrollerOffsets := TDictionary<Integer, Single>.Create;
  FDraggedScroller := -1;
  FSourceLines := TMarkdownSourceLineMap.Create;
  FSourceLinesLayoutCount := -1;
end;

destructor TMarkdownViewerModel.Destroy;
begin
  FSourceLines.Free;
  FScrollerOffsets.Free;
  FToggledDisclosures.Free;
  FZoomedTheme.Free;
  FImageSlotOrder.Free;
  FImageSlots.Free;

  inherited Destroy;
end;

procedure TMarkdownViewerModel.SetViewport(const Width, Height: Single);
var
  WidthChanged: Boolean;
  HasPendingContent: Boolean;
  NeedsRelayout: Boolean;
begin
  WidthChanged := not SameValue(FViewportWidth, Width);
  FViewportWidth := Width;
  FViewportHeight := Height;

  HasPendingContent := (FText <> '') or (FPendingMarkdown <> '');
  NeedsRelayout := WidthChanged and (Width > 0) and ((FDisplayList <> nil) or HasPendingContent);
  if NeedsRelayout then
    Relayout;
end;

procedure TMarkdownViewerModel.ApplyTheme(const Theme: TMarkdownTheme);
begin
  FTheme := Theme;
  RefreshLayout;
end;

procedure TMarkdownViewerModel.RefreshLayout;
begin
  if FDisplayList <> nil then
    Relayout;
end;

function TMarkdownViewerModel.IsScrolledToBottom: Boolean;
begin
  if FDisplayList = nil then
  begin
    Result := True;
    Exit;
  end;

  Result := (FScrollOffset + FViewportHeight) >= (FDisplayList.Height - BottomEpsilon);
end;

procedure TMarkdownViewerModel.AppendMarkdown(const Markdown: string; const NowMilliseconds: Int64);
begin
  if Markdown = '' then
    Exit;

  if not FDirty then
    FDirtySince := NowMilliseconds;

  FPendingMarkdown := FPendingMarkdown + Markdown;
  FDirty := True;
end;

function TMarkdownViewerModel.TryFlush(const NowMilliseconds: Int64): Boolean;
var
  IsTooEarly: Boolean;
begin
  if not FDirty then
  begin
    Result := False;
    Exit;
  end;

  IsTooEarly := ((NowMilliseconds - FDirtySince) < FFlushIntervalMilliseconds);
  if IsTooEarly then
  begin
    Result := False;
    Exit;
  end;

  FShouldAutoFollow := IsScrolledToBottom;
  FText := FText + FPendingMarkdown;
  FPendingMarkdown := '';
  FDirty := False;
  Relayout;

  Result := True;
end;

procedure TMarkdownViewerModel.SetSelectionAnchor(const Point: TLayoutPointF);
begin
  FSelectionUnit := TSelectionUnit.Character;
  FSelectionActive := TryResolvePosition(Point, FAnchor);
  FExtent := FAnchor;
end;

procedure TMarkdownViewerModel.SetSelectionExtent(const Point: TLayoutPointF);
var
  Position: TTextPosition;
  Character: TTextPosition;
begin
  if not FSelectionActive then
    Exit;

  if FSelectionUnit = TSelectionUnit.Character then
  begin
    
    if TryResolvePosition(Point, Position) then
      FExtent := Position;
    Exit;
  end;

  
  if TryResolveCharacter(Point, Character) then
    ExtendUnitSelection(Character);
end;

function TMarkdownViewerModel.SelectWordAt(const Point: TLayoutPointF): Boolean;
begin
  Result := SelectUnitAt(Point, TSelectionUnit.Word);
end;

function TMarkdownViewerModel.SelectLineAt(const Point: TLayoutPointF): Boolean;
begin
  Result := SelectUnitAt(Point, TSelectionUnit.Line);
end;

function TMarkdownViewerModel.SelectUnitAt(const Point: TLayoutPointF; const SelectionUnit: TSelectionUnit): Boolean;
var
  Character: TTextPosition;
begin
  
  Result := TryResolveCharacter(Point, Character);
  FSelectionActive := Result;
  if not Result then
    Exit;

  FSelectionUnit := SelectionUnit;
  FUnitRange := UnitRangeAt(Character);
  FAnchor := FUnitRange.StartPosition;
  FExtent := FUnitRange.EndPosition;
end;

// The word or line picked first stays selected; the selection grows from it
// to the whole unit under the pointer, on whichever side the pointer is.
procedure TMarkdownViewerModel.ExtendUnitSelection(const Position: TTextPosition);
var
  Range: TTextRange;
  IsBefore: Boolean;
begin
  Range := UnitRangeAt(Position);

  IsBefore := (ComparePositions(Range.StartPosition, FUnitRange.StartPosition) < 0);
  if IsBefore then
  begin
    FAnchor := FUnitRange.EndPosition;
    FExtent := Range.StartPosition;
  end
  else
  begin
    FAnchor := FUnitRange.StartPosition;
    FExtent := Range.EndPosition;
  end;
end;

function TMarkdownViewerModel.UnitRangeAt(const Position: TTextPosition): TTextRange;
begin
  case FSelectionUnit of
    TSelectionUnit.Word : Result := WordRangeAt(Position);
    TSelectionUnit.Line : Result := LineRangeAt(Position);
  else
    raise EMarkdownError.CreateFmt('Unhandled selection unit: %d', [Ord(FSelectionUnit)]);
  end;
end;

// A word is a run of letters, digits and underscores, and carries on into the
// next run when the formatting changes mid-word. Spaces select as spaces, any
// other character on its own.
function TMarkdownViewerModel.WordRangeAt(const Position: TTextPosition): TTextRange;
var
  Run: IDisplayTextRun;
  IsAtomic: Boolean;
  CharacterClass: TCharacterClass;
begin
  
  TrySelectableRun(Position.ItemIndex, Run);

  Result.StartPosition := Position;
  Result.EndPosition := Position;

  IsAtomic := (Run.Role = TDisplayTextRunRole.Source);
  if IsAtomic then
  begin
    Result.StartPosition.CharacterIndex := 0;
    Result.EndPosition.CharacterIndex := Length(Run.Text);
    Exit;
  end;

  CharacterClass := CharacterClassOf(Run.Text[Position.CharacterIndex + 1]);
  if CharacterClass = TCharacterClass.Other then
  begin
    Result.EndPosition.CharacterIndex := Position.CharacterIndex + 1;
    Exit;
  end;

  Result.StartPosition := WordStartFrom(Position);
  Result.EndPosition := WordEndFrom(Position);
end;

function TMarkdownViewerModel.WordStartFrom(const Position: TTextPosition): TTextPosition;
var
  Run: IDisplayTextRun;
  CharacterClass: TCharacterClass;
  ReachedRunStart: Boolean;
  PreviousIndex: Integer;
  Previous: IDisplayTextRun;
  CanContinue: Boolean;
begin
  
  TrySelectableRun(Position.ItemIndex, Run);
  CharacterClass := CharacterClassOf(Run.Text[Position.CharacterIndex + 1]);

  Result := Position;
  while True do
  begin
    while (Result.CharacterIndex > 0) and (CharacterClassOf(Run.Text[Result.CharacterIndex]) = CharacterClass) do
      Result.CharacterIndex := Result.CharacterIndex - 1;

    ReachedRunStart := (Result.CharacterIndex = 0);
    
    
    CanContinue := (ReachedRunStart and (CharacterClass = TCharacterClass.WordCharacter) and
                         TryAdjacentRun(Result.ItemIndex, -1, PreviousIndex, Previous) and ContinuesWord(Run, Previous));
    if not CanContinue then
      Exit;

    Run := Previous;
    Result.ItemIndex := PreviousIndex;
    Result.CharacterIndex := Length(Run.Text);
  end;
end;

function TMarkdownViewerModel.WordEndFrom(const Position: TTextPosition): TTextPosition;
var
  Run: IDisplayTextRun;
  CharacterClass: TCharacterClass;
  ReachedRunEnd: Boolean;
  NextIndex: Integer;
  Next: IDisplayTextRun;
  CanContinue: Boolean;
begin
  
  TrySelectableRun(Position.ItemIndex, Run);
  CharacterClass := CharacterClassOf(Run.Text[Position.CharacterIndex + 1]);

  Result := Position;
  while True do
  begin
    while (Result.CharacterIndex < Length(Run.Text)) and
          (CharacterClassOf(Run.Text[Result.CharacterIndex + 1]) = CharacterClass) do
      Result.CharacterIndex := Result.CharacterIndex + 1;

    ReachedRunEnd := (Result.CharacterIndex = Length(Run.Text));
    
    
    CanContinue := (ReachedRunEnd and (CharacterClass = TCharacterClass.WordCharacter) and
                         TryAdjacentRun(Result.ItemIndex, 1, NextIndex, Next) and ContinuesWord(Next, Run));
    if not CanContinue then
      Exit;

    Run := Next;
    Result.ItemIndex := NextIndex;
    Result.CharacterIndex := 0;
  end;
end;

// A line is what a browser selects on a triple click: a paragraph with all
// its lines, a list item without its marker, a table row, a code line.
function TMarkdownViewerModel.LineRangeAt(const Position: TTextPosition): TTextRange;
var
  OriginIndex: Integer;
  EndIndex: Integer;
  EndRun: IDisplayTextRun;
begin
  OriginIndex := LineOriginIndex(Position.ItemIndex);
  EndIndex := LineEndIndexFrom(OriginIndex);

  
  TrySelectableRun(EndIndex, EndRun);

  Result.StartPosition.ItemIndex := LineStartIndexFrom(OriginIndex);
  Result.StartPosition.CharacterIndex := 0;
  Result.EndPosition.ItemIndex := EndIndex;
  Result.EndPosition.CharacterIndex := Length(EndRun.Text);
end;

// A click on a list marker selects the item's line, which starts after it.
function TMarkdownViewerModel.LineOriginIndex(const ItemIndex: Integer): Integer;
var
  Run: IDisplayTextRun;
  ContentIndex: Integer;
  Content: IDisplayTextRun;
  IsOnMarker: Boolean;
begin
  Result := ItemIndex;

  
  TrySelectableRun(ItemIndex, Run);

  
  
  IsOnMarker := ((Run.Role = TDisplayTextRunRole.Marker) and TryAdjacentRun(ItemIndex, 1, ContentIndex, Content));
  if IsOnMarker then
    Result := ContentIndex;
end;

function TMarkdownViewerModel.LineStartIndexFrom(const ItemIndex: Integer): Integer;
var
  Run: IDisplayTextRun;
  PreviousIndex: Integer;
  Previous: IDisplayTextRun;
begin
  Result := ItemIndex;

  
  TrySelectableRun(Result, Run);

  
  
  while TryAdjacentRun(Result, -1, PreviousIndex, Previous) and ContinuesLine(Run, Previous) do
  begin
    Result := PreviousIndex;
    Run := Previous;
  end;
end;

function TMarkdownViewerModel.LineEndIndexFrom(const ItemIndex: Integer): Integer;
var
  Run: IDisplayTextRun;
  NextIndex: Integer;
  Next: IDisplayTextRun;
begin
  Result := ItemIndex;

  
  TrySelectableRun(Result, Run);

  
  
  while TryAdjacentRun(Result, 1, NextIndex, Next) and ContinuesLine(Next, Run) do
  begin
    Result := NextIndex;
    Run := Next;
  end;
end;

function TMarkdownViewerModel.TryAdjacentRun(const ItemIndex, Direction: Integer; out AdjacentIndex: Integer;
  out Run: IDisplayTextRun): Boolean;
begin
  AdjacentIndex := ItemIndex + Direction;

  while (AdjacentIndex >= 0) and (AdjacentIndex < FDisplayList.ItemCount) do
  begin
    if TrySelectableRun(AdjacentIndex, Run) then
    begin
      Result := True;
      Exit;
    end;

    AdjacentIndex := AdjacentIndex + Direction;
  end;

  Run := nil;
  Result := False;
end;

// Two runs make one word when the second follows the first directly on the
// same line, as a change of formatting in the middle of a word does.
class function TMarkdownViewerModel.ContinuesWord(const Run, Before: IDisplayTextRun): Boolean;
var
  IsDirectlyAfter: type of (((Run.Join = TDisplayTextJoin.Adjacent) or
                           ((Run.Join = TDisplayTextJoin.None) and
                            SameValue(Run.Bounds.Top, Before.Bounds.Top, LineTopEpsilon))));
  BothAreText: Boolean;
  MeetAtWordCharacters: Boolean;
begin
  IsDirectlyAfter := ((Run.Join = TDisplayTextJoin.Adjacent) or
                           ((Run.Join = TDisplayTextJoin.None) and
                            SameValue(Run.Bounds.Top, Before.Bounds.Top, LineTopEpsilon)));
  BothAreText := ((Run.Role = TDisplayTextRunRole.Text) and (Before.Role = TDisplayTextRunRole.Text));
  MeetAtWordCharacters := ((Run.Text <> '') and (Before.Text <> '') and
                                (CharacterClassOf(Run.Text[1]) = TCharacterClass.WordCharacter) and
                                (CharacterClassOf(Before.Text[Length(Before.Text)]) = TCharacterClass.WordCharacter));

  Result := IsDirectlyAfter and BothAreText and MeetAtWordCharacters;
end;

class function TMarkdownViewerModel.ContinuesLine(const Run, Before: IDisplayTextRun): Boolean;
var
  StaysOnLine: Boolean;
  NeitherIsMarker: Boolean;
begin
  StaysOnLine := (Run.Join in [TDisplayTextJoin.None, TDisplayTextJoin.Adjacent, TDisplayTextJoin.Space,
                                    TDisplayTextJoin.Tab, TDisplayTextJoin.HardBreak]);
  NeitherIsMarker := ((Run.Role <> TDisplayTextRunRole.Marker) and (Before.Role <> TDisplayTextRunRole.Marker));

  Result := StaysOnLine and NeitherIsMarker;
end;

class function TMarkdownViewerModel.CharacterClassOf(const Character: Char): TCharacterClass;
var
  IsWordCharacter: Boolean;
begin
  IsWordCharacter := (Character.IsLetterOrDigit or (Character = '_'));
  if IsWordCharacter then
    Result := TCharacterClass.WordCharacter
  else if Character.IsWhiteSpace then
    Result := TCharacterClass.Space
  else
    Result := TCharacterClass.Other;
end;

procedure TMarkdownViewerModel.ClearSelection;
begin
  FSelectionActive := False;
end;

// The first and the last text run bracket everything the reader can see, so
// selecting all covers the same range a drag from above the document to below
// it would produce. Runs without characters are skipped: they would leave the
// selection collapsed on an edge and copy nothing.
function TMarkdownViewerModel.TryFindTextRunBounds(out FirstIndex, LastIndex: Integer): Boolean;
var
  Index: Integer;
  Run: IDisplayTextRun;
begin
  FirstIndex := -1;
  LastIndex := -1;
  if FDisplayList = nil then
  begin
    Result := False;
    Exit;
  end;

  for Index := 0 to FDisplayList.ItemCount - 1 do
  begin
    
    if not TrySelectableRun(Index, Run) then
      Continue;

    if Run.Text = '' then
      Continue;

    if FirstIndex < 0 then
      FirstIndex := Index;
    LastIndex := Index;
  end;

  Result := FirstIndex >= 0;
end;

function TMarkdownViewerModel.HasSelectableText: Boolean;
var
  FirstIndex: Integer;
  LastIndex: Integer;
begin
  
  Result := TryFindTextRunBounds(FirstIndex, LastIndex);
end;

function TMarkdownViewerModel.SelectAll: Boolean;
var
  Range: TTextRange;
begin
  
  Result := TryGetEverythingRange(Range);
  if not Result then
    Exit;

  FAnchor := Range.StartPosition;
  FExtent := Range.EndPosition;
  FSelectionActive := True;
end;

// From the first character of the first run to the last character of the last.
function TMarkdownViewerModel.TryGetEverythingRange(out Range: TTextRange): Boolean;
var
  FirstIndex: Integer;
  LastIndex: Integer;
  LastRun: IDisplayTextRun;
begin
  Range := Default(TTextRange);

  
  Result := TryFindTextRunBounds(FirstIndex, LastIndex);
  if not Result then
    Exit;

  
  Result := TrySelectableRun(LastIndex, LastRun);
  if not Result then
    Exit;

  Range.StartPosition.ItemIndex := FirstIndex;
  Range.StartPosition.CharacterIndex := 0;
  Range.EndPosition.ItemIndex := LastIndex;
  Range.EndPosition.CharacterIndex := Length(LastRun.Text);
end;

function TMarkdownViewerModel.HasSelection: Boolean;
begin
  Result := HasCaret and (ComparePositions(FAnchor, FExtent) <> 0);
end;

function TMarkdownViewerModel.SelectionRects: TArray<TLayoutRectF>;
var
  Range: TTextRange;
  Index: type of (Range.StartPosition.ItemIndex);
  Run: IDisplayTextRun;
  CharFrom: Integer;
  CharTo: Integer;
  RunRect: TLayoutRectF;
  LastIndex: Integer;
  MergesWithLast: Boolean;
begin
  Result := [];
  if not HasSelection then
    Exit;

  Range := NormalizeSelection;

  for Index := Range.StartPosition.ItemIndex to Range.EndPosition.ItemIndex do
  begin
    
    if not TrySelectableRun(Index, Run) then
      Continue;

    
    if not SelectedCharacterRange(Run, Index, Range.StartPosition, Range.EndPosition, CharFrom, CharTo) then
      Continue;

    RunRect := ClipToScroller(Index, TLayoutRectF.Create(Run.Bounds.Left + PrefixWidth(Run, CharFrom),
      Run.Bounds.Top, Run.Bounds.Left + PrefixWidth(Run, CharTo), Run.Bounds.Bottom));
    if RunRect.Right <= RunRect.Left then
      Continue;

    LastIndex := High(Result);
    MergesWithLast := (LastIndex >= 0) and SameValue(Result[LastIndex].Top, RunRect.Top, LineTopEpsilon);
    if MergesWithLast then
    begin
      Result[LastIndex].Left := Min(Result[LastIndex].Left, RunRect.Left);
      Result[LastIndex].Right := Max(Result[LastIndex].Right, RunRect.Right);
      Result[LastIndex].Bottom := Max(Result[LastIndex].Bottom, RunRect.Bottom);
    end
    else
      Result := Result + [RunRect];
  end;
end;

function TMarkdownViewerModel.SelectedText: string;
var
  Range: TTextRange;
  HasPrevious: Boolean;
  PreviousTop: Double;
  PreviousBlock: Integer;
  Index: type of (Range.StartPosition.ItemIndex);
  Run: IDisplayTextRun;
  CharFrom: Integer;
  CharTo: Integer;
  Segment: string;
  BlockIndex: Integer;
begin
  Result := '';
  if not HasSelection then
    Exit;

  Range := NormalizeSelection;

  HasPrevious := False;
  PreviousTop := 0.0;
  PreviousBlock := 0;

  for Index := Range.StartPosition.ItemIndex to Range.EndPosition.ItemIndex do
  begin
    
    if not TrySelectableRun(Index, Run) then
      Continue;

    
    if not SelectedCharacterRange(Run, Index, Range.StartPosition, Range.EndPosition, CharFrom, CharTo) then
      Continue;

    Segment := Copy(Run.Text, CharFrom + 1, CharTo - CharFrom);
    BlockIndex := BlockIndexOfItem(Index);

    if HasPrevious then
      Result := Result + SeparatorBefore(Run, BlockIndex <> PreviousBlock, PreviousTop);

    Result := Result + Segment;

    HasPrevious := True;
    PreviousTop := Run.Bounds.Top;
    PreviousBlock := BlockIndex;
  end;
end;

// A run the layout gave a join copies with that join. One without, drawn by an
// extension for instance, falls back on where it sits: a new block starts a
// new line, a new line within a block is a space.
class function TMarkdownViewerModel.SeparatorBefore(const Run: IDisplayTextRun; const StartsBlock: Boolean;
  const PreviousTop: Single): string;
var
  Indent: string;
begin
  Indent := StringOfChar(CopiedSpace, Run.IndentLevel * CopiedIndentWidth);

  case Run.Join of
    TDisplayTextJoin.None      : Result := FallbackSeparator(Run, StartsBlock, PreviousTop);
    TDisplayTextJoin.Adjacent  : Result := '';
    TDisplayTextJoin.Space     : Result := CopiedSpace;
    TDisplayTextJoin.Tab       : Result := CopiedTab;
    TDisplayTextJoin.HardBreak,
    TDisplayTextJoin.LineBreak : Result := sLineBreak + Indent;
    TDisplayTextJoin.BlankLine : Result := sLineBreak + sLineBreak + Indent;
  else
    raise EMarkdownError.CreateFmt('Unhandled text join: %d', [Ord(Run.Join)]);
  end;
end;

class function TMarkdownViewerModel.FallbackSeparator(const Run: IDisplayTextRun; const StartsBlock: Boolean;
  const PreviousTop: Single): string;
var
  StartsLine: Boolean;
begin
  StartsLine := not SameValue(Run.Bounds.Top, PreviousTop, LineTopEpsilon);

  if StartsBlock then
    Result := sLineBreak
  else if StartsLine then
    Result := CopiedSpace
  else
    Result := '';
end;

function TMarkdownViewerModel.SourceLineToScrollOffset(const SourceLine: Integer): Single;
begin
  RefreshSourceLines;
  Result := FSourceLines.SourceLineToOffset(SourceLine);
end;

function TMarkdownViewerModel.ScrollOffsetToSourceLine(const Offset: Single): Integer;
begin
  RefreshSourceLines;
  Result := FSourceLines.OffsetToSourceLine(Offset);
end;

procedure TMarkdownViewerModel.RefreshSourceLines;
var
  IsCurrent: Boolean;
begin
  IsCurrent := (FSourceLinesLayoutCount = FLayoutCount);
  if IsCurrent then
    Exit;

  FSourceLines.Build(FDocument, FDisplayList, FText);
  FSourceLinesLayoutCount := FLayoutCount;
end;

function TMarkdownViewerModel.TryGetAnchorOffset(const Anchor: string; out Offset: Single): Boolean;
var
  Name: type of (M4DUrlDecode(Anchor.TrimLeft([AnchorMark])));
  Heading: IMarkdownHeading;
  Segment: type of (Heading.Segment);
  Index: Integer;
  Run: IDisplayTextRun;
  Start: Integer;
  IsInHeading: Boolean;
begin
  Offset := 0;
  Result := False;
  if (FDocument = nil) or (FDisplayList = nil) then
    Exit;

  Name := M4DUrlDecode(Anchor.TrimLeft([AnchorMark]));
  
  if not TMarkdownToc.TryFindHeading(FDocument, Name, Heading) then
    Exit;

  Segment := Heading.Segment;
  for Index := 0 to FDisplayList.ItemCount - 1 do
  begin
    
    if not TrySelectableRun(Index, Run) then
      Continue;

    Start := Run.SourceNode.Segment.StartOffset;
    IsInHeading := ((Start >= Segment.StartOffset) and (Start < Segment.EndOffset));
    if IsInHeading then
    begin
      Offset := Run.Bounds.Top;
      Result := True;
      Exit;
    end;
  end;
end;

function TMarkdownViewerModel.GetDocument: IMarkdownDocument;
begin
  Result := FDocument;
end;

function TMarkdownViewerModel.SelectedMarkdown: string;
var
  Segment: TMarkdownSegment;
begin
  Result := '';
  if not HasSelection then
    Exit;

  if IsEverythingSelected then
  begin
    Result := TMarkdownSelectedSource.WithPlatformLineBreaks(FText);
    Exit;
  end;

  
  if TryGetSelectionSourceSegment(Segment) then
    Result := TMarkdownSelectedSource.Extract(FText, FDocument, Segment);
end;

function TMarkdownViewerModel.IsEverythingSelected: Boolean;
var
  Everything: TTextRange;
  Selection: TTextRange;
begin
  
  Result := TryGetEverythingRange(Everything);
  if not Result then
    Exit;

  Selection := NormalizeSelection;
  Result := ((ComparePositions(Selection.StartPosition, Everything.StartPosition) = 0) and
             (ComparePositions(Selection.EndPosition, Everything.EndPosition) = 0));
end;

function TMarkdownViewerModel.TryGetSelectionSourceSegment(out Segment: TMarkdownSegment): Boolean;
var
  FirstRun: IDisplayTextRun;
  LastRun: IDisplayTextRun;
  FirstCharacter: Integer;
  LastCharacter: Integer;
  StartOffset: Integer;
  EndOffset: Integer;
  IsStartMapped: Boolean;
  IsEndMapped: Boolean;
  CoversCharacters: Boolean;
begin
  Segment := Default(TMarkdownSegment);
  Result := False;

  
  
  if not TryFindSelectionEdges(FirstRun, LastRun, FirstCharacter, LastCharacter) then
    Exit;

  
  IsStartMapped := TMarkdownSourceMapper.TryMapLiteralOffset(FText, FirstRun.SourceNode,
    FirstRun.StartOffset + FirstCharacter, TMarkdownSourceEdge.Leading, StartOffset);
  IsEndMapped := TMarkdownSourceMapper.TryMapLiteralOffset(FText, LastRun.SourceNode,
    LastRun.StartOffset + LastCharacter, TMarkdownSourceEdge.Trailing, EndOffset);

  CoversCharacters := IsStartMapped and IsEndMapped and (EndOffset > StartOffset);
  if not CoversCharacters then
    Exit;

  Segment := TMarkdownSegment.Create(StartOffset, EndOffset);
  Result := True;
end;

// The runs between the two ends of the selection follow one another in the
// source as well, so the first and the last of them bracket the whole stretch.
function TMarkdownViewerModel.TryFindSelectionEdges(out FirstRun, LastRun: IDisplayTextRun;
  out FirstCharacter, LastCharacter: Integer): Boolean;
var
  Range: TTextRange;
  Index: type of (Range.StartPosition.ItemIndex);
  Run: IDisplayTextRun;
  CharFrom: Integer;
  CharTo: Integer;
begin
  FirstRun := nil;
  LastRun := nil;
  FirstCharacter := 0;
  LastCharacter := 0;

  if not HasSelection then
  begin
    Result := False;
    Exit;
  end;

  Range := NormalizeSelection;

  for Index := Range.StartPosition.ItemIndex to Range.EndPosition.ItemIndex do
  begin
    
    if not TrySelectableRun(Index, Run) then
      Continue;

    
    if not SelectedCharacterRange(Run, Index, Range.StartPosition, Range.EndPosition, CharFrom, CharTo) then
      Continue;

    if FirstRun = nil then
    begin
      FirstRun := Run;
      FirstCharacter := CharFrom;
    end;

    LastRun := Run;
    LastCharacter := CharTo;
  end;

  Result := (FirstRun <> nil);
end;

function TMarkdownViewerModel.PendingImageSources: TArray<string>;
var
  Source: string;
begin
  Result := [];

  for Source in FImageSlotOrder do
  begin
    if FImageSlots[Source].State = TMarkdownImageSlotState.Requested then
      Result := Result + [Source];
  end;
end;

procedure TMarkdownViewerModel.NotifyImageArrived(const Source: string; const Size: TLayoutSizeF);
var
  Slot: TImageSlot;
begin
  
  if not FImageSlots.TryGetValue(Source, Slot) then
    Exit;

  if Slot.State = TMarkdownImageSlotState.Loaded then
    Exit;

  Slot.State := TMarkdownImageSlotState.Loaded;
  Slot.Size := Size;
  FImageSlots[Source] := Slot;
  Relayout;
end;

procedure TMarkdownViewerModel.NotifyImageFailed(const Source: string);
var
  Slot: TImageSlot;
begin
  
  if not FImageSlots.TryGetValue(Source, Slot) then
    Exit;

  if Slot.State = TMarkdownImageSlotState.Loaded then
    Exit;

  Slot.State := TMarkdownImageSlotState.Failed;
  FImageSlots[Source] := Slot;
end;

function TMarkdownViewerModel.ImageSlotState(const Source: string): TMarkdownImageSlotState;
var
  Slot: TImageSlot;
begin
  
  if FImageSlots.TryGetValue(Source, Slot) then
  begin
    Result := Slot.State;
    Exit;
  end;

  Result := TMarkdownImageSlotState.Unknown;
end;

function TMarkdownViewerModel.TryGetImageSize(const Source: string; out Size: TLayoutSizeF): Boolean;
var
  Slot: TImageSlot;
begin
  Size := Default(TLayoutSizeF);

  
  Result := FImageSlots.TryGetValue(Source, Slot) and (Slot.State = TMarkdownImageSlotState.Loaded);
  if Result then
    Size := TLayoutSizeF.Create(Slot.Size.Width * ZoomFactor, Slot.Size.Height * ZoomFactor);
end;

procedure TMarkdownViewerModel.ExtensionFailed(const Extension: string; const Error: Exception);
begin
  if Assigned(FOnExtensionError) then
    FOnExtensionError(Self, Extension, Error);
end;

function TMarkdownViewerModel.FindText(const Needle: string): TArray<TMarkdownFoundRange>;
begin
  Result := FindText(Needle, Default(TMarkdownFindOptions));
end;

function TMarkdownViewerModel.FindText(const Needle: string;
  const Options: TMarkdownFindOptions): TArray<TMarkdownFoundRange>;
var
  IsSearchable: Boolean;
  NeedleLength: Integer;
  Index: Integer;
  Run: IDisplayTextRun;
  RunText: string;
  Offset: Integer;
  Found: Integer;
begin
  Result := [];

  IsSearchable := (Needle <> '') and (FDisplayList <> nil);
  if not IsSearchable then
    Exit;

  NeedleLength := Length(Needle);

  for Index := 0 to FDisplayList.ItemCount - 1 do
  begin
    
    if not TrySelectableRun(Index, Run) then
      Continue;

    RunText := Run.Text;
    Offset := 1;
    Found := TMarkdownTextSearch.IndexOf(Needle, RunText, Offset, Options);

    while Found > 0 do
    begin
      Result := Result + [TMarkdownFoundRange.Create(Index, Found, NeedleLength)];
      Offset := Found + NeedleLength;
      Found := TMarkdownTextSearch.IndexOf(Needle, RunText, Offset, Options);
    end;
  end;
end;

function TMarkdownViewerModel.TrySelectNextMatch(const Needle: string; out Match: TMarkdownFoundRange): Boolean;
begin
  Result := TrySelectNextMatch(Needle, Default(TMarkdownFindOptions), Match);
end;

function TMarkdownViewerModel.TrySelectNextMatch(const Needle: string; const Options: TMarkdownFindOptions;
  out Match: TMarkdownFoundRange): Boolean;
var
  Matches: TArray<TMarkdownFoundRange>;
begin
  Match := Default(TMarkdownFoundRange);

  Matches := FindText(Needle, Options);
  Result := (Length(Matches) > 0);
  if not Result then
    Exit;

  Match := NextMatchAfterSelection(Matches);
  SelectMatch(Match);
end;

function TMarkdownViewerModel.TrySelectPreviousMatch(const Needle: string; out Match: TMarkdownFoundRange): Boolean;
begin
  Result := TrySelectPreviousMatch(Needle, Default(TMarkdownFindOptions), Match);
end;

function TMarkdownViewerModel.TrySelectPreviousMatch(const Needle: string; const Options: TMarkdownFindOptions;
  out Match: TMarkdownFoundRange): Boolean;
var
  Matches: TArray<TMarkdownFoundRange>;
begin
  Match := Default(TMarkdownFoundRange);

  Matches := FindText(Needle, Options);
  Result := (Length(Matches) > 0);
  if not Result then
    Exit;

  Match := PreviousMatchBeforeSelection(Matches);
  SelectMatch(Match);
end;

// A bare caret sits between two characters, so a match that starts right at
// it is still ahead; a selection is past its own start.
function TMarkdownViewerModel.NextMatchAfterSelection(const Matches: TArray<TMarkdownFoundRange>): TMarkdownFoundRange;
var
  Selection: TTextRange;
  IsBareCaret: Boolean;
  Candidate: TMarkdownFoundRange;
  CandidateRange: TTextRange;
  Order: Integer;
  IsAhead: Boolean;
begin
  Result := Matches[0];
  if not HasCaret then
    Exit;

  Selection := NormalizeSelection;
  IsBareCaret := (not HasSelection);

  for Candidate in Matches do
  begin
    CandidateRange := RangeOfMatch(Candidate);
    Order := ComparePositions(CandidateRange.StartPosition, Selection.StartPosition);
    IsAhead := ((Order > 0) or (IsBareCaret and (Order = 0)));
    if IsAhead then
    begin
      Result := Candidate;
      Exit;
    end;
  end;
end;

function TMarkdownViewerModel.PreviousMatchBeforeSelection(
  const Matches: TArray<TMarkdownFoundRange>): TMarkdownFoundRange;
var
  Selection: TTextRange;
  Candidate: TMarkdownFoundRange;
  CandidateRange: TTextRange;
  IsBeforeSelectionStart: Boolean;
begin
  Result := Matches[High(Matches)];
  if not HasCaret then
    Exit;

  Selection := NormalizeSelection;

  for Candidate in Matches do
  begin
    CandidateRange := RangeOfMatch(Candidate);
    IsBeforeSelectionStart := (ComparePositions(CandidateRange.StartPosition, Selection.StartPosition) < 0);
    if not IsBeforeSelectionStart then
      Break;

    Result := Candidate;
  end;
end;

function TMarkdownViewerModel.HasCaret: Boolean;
begin
  if not FSelectionActive or (FDisplayList = nil) then
  begin
    Result := False;
    Exit;
  end;

  Result := (FAnchor.ItemIndex < FDisplayList.ItemCount) and
            (FExtent.ItemIndex < FDisplayList.ItemCount);
end;

procedure TMarkdownViewerModel.SelectMatch(const Match: TMarkdownFoundRange);
var
  Range: TTextRange;
begin
  Range := RangeOfMatch(Match);
  FSelectionUnit := TSelectionUnit.Character;
  FAnchor := Range.StartPosition;
  FExtent := Range.EndPosition;
  FSelectionActive := True;
  RevealInScroller(Match.ItemIndex);
end;

// The source of a formula is selected whole or not at all, the same rule a
// click on it follows, so a match inside it covers the whole run.
function TMarkdownViewerModel.RangeOfMatch(const Match: TMarkdownFoundRange): TTextRange;
var
  Run: IDisplayTextRun;
begin
  Run := MatchRun(Match);
  Result := RangeInRun(Run, Match);
end;

function TMarkdownViewerModel.RangeInRun(const Run: IDisplayTextRun; const Match: TMarkdownFoundRange): TTextRange;
var
  IsAtomic: Boolean;
begin
  Result.StartPosition.ItemIndex := Match.ItemIndex;
  Result.EndPosition.ItemIndex := Match.ItemIndex;

  IsAtomic := (Run.Role = TDisplayTextRunRole.Source);
  if IsAtomic then
  begin
    Result.StartPosition.CharacterIndex := 0;
    Result.EndPosition.CharacterIndex := Length(Run.Text);
    Exit;
  end;

  Result.StartPosition.CharacterIndex := Match.StartCharacter - 1;
  Result.EndPosition.CharacterIndex := Result.StartPosition.CharacterIndex + Match.CharacterCount;
end;

function TMarkdownViewerModel.MatchRun(const Match: TMarkdownFoundRange): IDisplayTextRun;
var
  Item: IDisplayItem;
begin
  Item := FDisplayList.Items[Match.ItemIndex];
  Result := Item as IDisplayTextRun;
end;

function TMarkdownViewerModel.MatchCount(const Needle: string): Integer;
begin
  Result := MatchCount(Needle, Default(TMarkdownFindOptions));
end;

function TMarkdownViewerModel.MatchCount(const Needle: string; const Options: TMarkdownFindOptions): Integer;
var
  Matches: TArray<TMarkdownFoundRange>;
  Stops: TArray<TMarkdownFoundRange>;
begin
  Matches := FindText(Needle, Options);
  Stops := DistinctMatches(Matches);
  Result := Length(Stops);
end;

function TMarkdownViewerModel.MatchIndex(const Needle: string; const Options: TMarkdownFindOptions): Integer;
var
  Selection: TTextRange;
  Matches: TArray<TMarkdownFoundRange>;
  Stops: TArray<TMarkdownFoundRange>;
  Index: Integer;
  Range: TTextRange;
  IsSelected: type of (((ComparePositions(Range.StartPosition, Selection.StartPosition) = 0) and
                        (ComparePositions(Range.EndPosition, Selection.EndPosition) = 0)));
begin
  Result := -1;
  if not HasSelection then
    Exit;

  Selection := NormalizeSelection;
  Matches := FindText(Needle, Options);
  Stops := DistinctMatches(Matches);

  for Index := 0 to High(Stops) do
  begin
    Range := RangeOfMatch(Stops[Index]);
    IsSelected := ((ComparePositions(Range.StartPosition, Selection.StartPosition) = 0) and
                        (ComparePositions(Range.EndPosition, Selection.EndPosition) = 0));
    if IsSelected then
    begin
      Result := Index;
      Exit;
    end;
  end;
end;

// Matches that select the same range, as several hits in one formula do,
// collapse into the first of them.
function TMarkdownViewerModel.DistinctMatches(
  const Matches: TArray<TMarkdownFoundRange>): TArray<TMarkdownFoundRange>;
var
  DistinctCount: Integer;
  PreviousStart: TTextPosition;
  Match: TMarkdownFoundRange;
  Range: TTextRange;
  RepeatsPrevious: Boolean;
begin
  SetLength(Result, Length(Matches));

  DistinctCount := 0;
  PreviousStart := Default(TTextPosition);

  for Match in Matches do
  begin
    Range := RangeOfMatch(Match);
    RepeatsPrevious := ((DistinctCount > 0) and (ComparePositions(Range.StartPosition, PreviousStart) = 0));
    if RepeatsPrevious then
      Continue;

    Result[DistinctCount] := Match;
    PreviousStart := Range.StartPosition;
    Inc(DistinctCount);
  end;

  SetLength(Result, DistinctCount);
end;

procedure TMarkdownViewerModel.HighlightMatches(const Needle: string);
begin
  HighlightMatches(Needle, Default(TMarkdownFindOptions));
end;

procedure TMarkdownViewerModel.HighlightMatches(const Needle: string; const Options: TMarkdownFindOptions);
begin
  FHighlightNeedle := Needle;
  FHighlightOptions := Options;
  RefreshHighlights;
end;

procedure TMarkdownViewerModel.ClearHighlights;
begin
  HighlightMatches('');
end;

function TMarkdownViewerModel.HighlightCount: Integer;
begin
  Result := Length(FHighlightRects);
end;

function TMarkdownViewerModel.HighlightRectsWithin(const Viewport: TLayoutRectF): TArray<TLayoutRectF>;
var
  VisibleCount: Integer;
  HighlightRect: TLayoutRectF;
  IsVisible: Boolean;
begin
  SetLength(Result, Length(FHighlightRects));

  VisibleCount := 0;

  for HighlightRect in FHighlightRects do
  begin
    IsVisible := ((HighlightRect.Bottom >= Viewport.Top) and (HighlightRect.Top <= Viewport.Bottom));
    if not IsVisible then
      Continue;

    Result[VisibleCount] := HighlightRect;
    Inc(VisibleCount);
  end;

  SetLength(Result, VisibleCount);
end;

function TMarkdownViewerModel.TryGetScrollTarget(const Match: TMarkdownFoundRange; out Offset: Single): Boolean;
var
  Bounds: TLayoutRectF;
begin
  Bounds := MatchBounds(Match);
  Offset := Bounds.Top - (FViewportHeight - Bounds.Height) / 2;
  Result := not IsWithinViewport(Bounds);
end;

// The rectangles are measured once per layout rather than on every paint,
// so scrolling through a document full of matches stays cheap.
procedure TMarkdownViewerModel.RefreshHighlights;
var
  Matches: TArray<TMarkdownFoundRange>;
  Marks: TArray<TMarkdownFoundRange>;
  Index: Integer;
  Run: IDisplayTextRun;
  Range: TTextRange;
begin
  Matches := FindText(FHighlightNeedle, FHighlightOptions);
  Marks := DistinctMatches(Matches);
  SetLength(FHighlightRects, Length(Marks));

  for Index := 0 to High(Marks) do
  begin
    Run := MatchRun(Marks[Index]);
    Range := RangeInRun(Run, Marks[Index]);
    FHighlightRects[Index] := ClipToScroller(Marks[Index].ItemIndex, BoundsInRun(Run, Range));
  end;
end;

function TMarkdownViewerModel.MatchBounds(const Match: TMarkdownFoundRange): TLayoutRectF;
var
  Run: IDisplayTextRun;
  Range: TTextRange;
begin
  Run := MatchRun(Match);
  Range := RangeInRun(Run, Match);
  Result := BoundsInRun(Run, Range);
end;

function TMarkdownViewerModel.BoundsInRun(const Run: IDisplayTextRun; const Range: TTextRange): TLayoutRectF;
var
  RunBounds: type of (Run.Bounds);
  Left: Double;
  Right: Double;
begin
  RunBounds := Run.Bounds;
  Left := RunBounds.Left + PrefixWidth(Run, Range.StartPosition.CharacterIndex);
  Right := RunBounds.Left + PrefixWidth(Run, Range.EndPosition.CharacterIndex);

  Result := TLayoutRectF.Create(Left, RunBounds.Top, Right, RunBounds.Bottom);
end;

function TMarkdownViewerModel.IsWithinViewport(const Bounds: TLayoutRectF): Boolean;
var
  ViewportBottom: Single;
begin
  ViewportBottom := FScrollOffset + FViewportHeight;
  Result := ((Bounds.Top >= FScrollOffset) and (Bounds.Bottom <= ViewportBottom));
end;

function TMarkdownViewerModel.TryGetCodeBlockAt(const Point: TLayoutPointF;
  out Region: TMarkdownCodeBlockRegion): Boolean;
var
  Candidate: TMarkdownCodeBlockRegion;
begin
  for Candidate in CodeBlockRegions do
  begin
    if Candidate.Rect.Contains(Point) then
    begin
      Region := Candidate;
      Result := True;
      Exit;
    end;
  end;

  Region := Default(TMarkdownCodeBlockRegion);
  Result := False;
end;

function TMarkdownViewerModel.TryGetDisclosureAt(const Point: TLayoutPointF; out Key: Integer): Boolean;
var
  Disclosure: IDisplayDisclosure;
begin
  Key := 0;
  Result := False;
  if FDisplayList = nil then
    Exit;

  
  Result := TMarkdownHitTester.TryFindDisclosure(FDisplayList, Point, Disclosure);
  if Result then
    Key := Disclosure.Key;
end;

procedure TMarkdownViewerModel.ToggleDisclosure(const Key: Integer);
var
  WasToggled: type of (FToggledDisclosures.Contains(Key));
begin
  WasToggled := FToggledDisclosures.Contains(Key);
  if WasToggled then
    FToggledDisclosures.Remove(Key)
  else
    FToggledDisclosures.Add(Key);

  RefreshLayout;
  // Closing a section near the end can leave the view scrolled past the
  // shorter document.
  SetScrollOffset(FScrollOffset);
end;

function TMarkdownViewerModel.IsDisclosureOpen(const Key: Integer; const OpenByDefault: Boolean): Boolean;
var
  IsToggled: type of (FToggledDisclosures.Contains(Key));
begin
  IsToggled := FToggledDisclosures.Contains(Key);
  Result := OpenByDefault xor IsToggled;
end;

function TMarkdownViewerModel.TryFindScrollerAt(const Point: TLayoutPointF; out Index: Integer): Boolean;
var
  Candidate: Integer;
begin
  Index := -1;
  Result := False;
  if FDisplayList = nil then
    Exit;

  for Candidate in FScrollers do
  begin
    if FDisplayList.Items[Candidate].Bounds.Contains(Point) then
    begin
      Index := Candidate;
      Result := True;
      Exit;
    end;
  end;
end;

// The scroller whose content the item at ItemIndex is, if any.
function TMarkdownViewerModel.TryFindScrollerOf(const ItemIndex: Integer; out Index: Integer): Boolean;
var
  Candidate: Integer;
  Count: type of ((FDisplayList.Items[Candidate] as IDisplayScroller).ItemCount);
begin
  Index := -1;
  Result := False;
  if FDisplayList = nil then
    Exit;

  for Candidate in FScrollers do
  begin
    Count := (FDisplayList.Items[Candidate] as IDisplayScroller).ItemCount;
    if (ItemIndex > Candidate) and (ItemIndex <= Candidate + Count) then
    begin
      Index := Candidate;
      Result := True;
      Exit;
    end;
  end;
end;

procedure TMarkdownViewerModel.SetScrollerOffset(const Index: Integer; const Offset: Single);
var
  OldOffset: type of ((FDisplayList.Items[Index] as IDisplayScroller).Offset);
  Scroller: IDisplayScroller;
  IsMoved: Boolean;
begin
  OldOffset := (FDisplayList.Items[Index] as IDisplayScroller).Offset;
  FDisplayList.SetScrollerOffset(Index, Offset);

  Scroller := FDisplayList.Items[Index] as IDisplayScroller;
  IsMoved := (Scroller.Offset <> OldOffset);
  if not IsMoved then
    Exit;

  FScrollerOffsets.AddOrSetValue(Scroller.Key, Scroller.Offset);
  RefreshHighlights;
end;

// A new layout draws every scroller unscrolled; each takes back the offset
// the reader left it at.
procedure TMarkdownViewerModel.RestoreScrollerOffsets;
var
  Index: Integer;
  Scroller: IDisplayScroller;
  Offset: Single;
begin
  FScrollers := [];
  for Index := 0 to FDisplayList.ItemCount - 1 do
  begin
    if FDisplayList.Items[Index].Kind = TDisplayItemKind.Scroller then
      FScrollers := FScrollers + [Index];
  end;

  for Index in FScrollers do
  begin
    Scroller := FDisplayList.Items[Index] as IDisplayScroller;

    
    if FScrollerOffsets.TryGetValue(Scroller.Key, Offset) then
      SetScrollerOffset(Index, Offset);
  end;
end;

// A match that find selects in a part of a formula out of view scrolls that
// part into view.
procedure TMarkdownViewerModel.RevealInScroller(const ItemIndex: Integer);
var
  Index: Integer;
  Bounds: TLayoutRectF;
  Target: TLayoutRectF;
  Scroller: IDisplayScroller;
begin
  
  if not TryFindScrollerOf(ItemIndex, Index) then
    Exit;

  Bounds := FDisplayList.Items[Index].Bounds;
  Target := FDisplayList.Items[ItemIndex].Bounds;
  Scroller := FDisplayList.Items[Index] as IDisplayScroller;
  if Target.Left < Bounds.Left then
    SetScrollerOffset(Index, Scroller.Offset - (Bounds.Left - Target.Left) - Bounds.Width / 4)
  else if Target.Right > Bounds.Right then
    SetScrollerOffset(Index, Scroller.Offset + (Target.Right - Bounds.Right) + Bounds.Width / 4);
end;

function TMarkdownViewerModel.ClipToScroller(const ItemIndex: Integer; const Rect: TLayoutRectF): TLayoutRectF;
var
  Index: Integer;
  Bounds: TLayoutRectF;
begin
  Result := Rect;

  
  if not TryFindScrollerOf(ItemIndex, Index) then
    Exit;

  Bounds := FDisplayList.Items[Index].Bounds;
  Result.Left := Max(Rect.Left, Bounds.Left);
  Result.Right := Min(Rect.Right, Bounds.Right);
end;

function TMarkdownViewerModel.ScrollSideways(const Point: TLayoutPointF; const Delta: Single): Boolean;
var
  Index: Integer;
begin
  
  Result := TryFindScrollerAt(Point, Index);
  if Result then
    SetScrollerOffset(Index, (FDisplayList.Items[Index] as IDisplayScroller).Offset + Delta);
end;

function TMarkdownViewerModel.IsOverScrollerTrack(const Point: TLayoutPointF): Boolean;
var
  Index: Integer;
begin
  
  Result := TryFindScrollerAt(Point, Index) and (FDisplayList.Items[Index] as IDisplayScroller).Track.Contains(Point);
end;

// A press on the thumb grabs it where it was pressed; a press elsewhere on
// the track first brings the thumb under the pointer.
function TMarkdownViewerModel.TryBeginScrollerDrag(const Point: TLayoutPointF): Boolean;
var
  Thumb: type of ((FDisplayList.Items[FDraggedScroller] as IDisplayScroller).Thumb);
begin
  Result := IsOverScrollerTrack(Point);
  if not Result then
    Exit;

  TryFindScrollerAt(Point, FDraggedScroller);
  Thumb := (FDisplayList.Items[FDraggedScroller] as IDisplayScroller).Thumb;
  if not Thumb.Contains(Point) then
  begin
    FThumbGrab := Thumb.Width / 2;
    DragScrollerThumb(Point);
    Exit;
  end;

  FThumbGrab := Point.X - Thumb.Left;
end;

procedure TMarkdownViewerModel.DragScrollerThumb(const Point: TLayoutPointF);
var
  Scroller: IDisplayScroller;
  Track: TLayoutRectF;
  Travel: Single;
  ThumbLeft: Single;
begin
  if not IsDraggingScroller then
    Exit;

  Scroller := FDisplayList.Items[FDraggedScroller] as IDisplayScroller;
  Track := Scroller.Track;
  Travel := Track.Width - Scroller.Thumb.Width;
  if Travel <= 0 then
    Exit;

  ThumbLeft := Point.X - FThumbGrab - Track.Left;
  SetScrollerOffset(FDraggedScroller, ThumbLeft / Travel * Scroller.MaxOffset);
end;

procedure TMarkdownViewerModel.EndScrollerDrag;
begin
  FDraggedScroller := -1;
end;

function TMarkdownViewerModel.IsDraggingScroller: Boolean;
begin
  Result := (FDraggedScroller >= 0) and (FDisplayList <> nil) and (FDraggedScroller < FDisplayList.ItemCount);
end;

function TMarkdownViewerModel.CodeBlockRegions: TArray<TMarkdownCodeBlockRegion>;
var
  Index: Integer;
  Item: IDisplayItem;
  Code: IMarkdownCodeBlock;
  Handler: ILayoutBlockOverride;
begin
  Result := [];
  if FDisplayList = nil then
    Exit;

  for Index := 0 to FDisplayList.ItemCount - 1 do
  begin
    Item := FDisplayList.Items[Index];
    if Item.Kind <> TDisplayItemKind.Rectangle then
      Continue;

    
    if (Item.Node = nil) or not Supports(Item.Node, IMarkdownCodeBlock, Code) then
      Continue;

    // Skip code blocks that a layout override (chart, mermaid, ...) renders as
    // graphics: their rectangles are the drawing, not copyable source, so the
    // hover copy button must not appear over them.
    
    if TLayoutBlockOverrideRegistry.TryFind(Item.Node, Handler) then
      Continue;

    Result := Result + [TMarkdownCodeBlockRegion.Create(Item.Bounds, CodeTextOf(Code))];
  end;
end;

class function TMarkdownViewerModel.CodeTextOf(const Code: IMarkdownCodeBlock): string;
begin
  Result := Code.Literal;
  if Result.EndsWith(LineFeed) then
    SetLength(Result, Length(Result) - 1);
end;

procedure TMarkdownViewerModel.Relayout;
var
  Selection: TSelectionAnchors;
  CanKeepSelection: Boolean;
  Watch: type of (TStopwatch.StartNew);
  Document: IMarkdownDocument;
  IsSelectionKept: Boolean;
begin
  if FViewportWidth <= 0 then
    Exit;

  
  CanKeepSelection := TryCaptureSelection(Selection);
  Watch := TStopwatch.StartNew;
  Document := TMarkdown.Parse(FText, TMarkdownDialect.Gfm);
  TLayoutDocumentProcessorRegistry.Process(Document, Self);
  FDocument := Document;
  RefreshZoomedTheme;

  FDisplayList := TMarkdownLayoutEngine.LayoutDocument(Document, FViewportWidth, LayoutTheme, FMeasurer, Self,
                                                       Self, Self);
  FLastLayoutMilliseconds := Watch.ElapsedMilliseconds;
  Inc(FLayoutCount);
  FDraggedScroller := -1;
  RestoreScrollerOffsets;

  // A selection whose text the new layout no longer has is dropped, rather
  // than drawn over whatever text now sits at its old place.
  IsSelectionKept := CanKeepSelection and TryRestoreSelection(Selection);
  if not IsSelectionKept then
    ClearSelection;

  RegisterImageSlots;
  RefreshHighlights;
end;

function TMarkdownViewerModel.TryCaptureSelection(out Selection: TSelectionAnchors): Boolean;
var
  Anchors: TMarkdownTextAnchors;
  HasUnitRange: Boolean;
begin
  Selection := Default(TSelectionAnchors);
  Result := False;
  if not HasCaret then
    Exit;

  Anchors := TMarkdownTextAnchors.Create(FDisplayList);
  try
    if not Anchors.TryAnchorOf(FAnchor, Selection.Anchor) then
      Exit;
    if not Anchors.TryAnchorOf(FExtent, Selection.Extent) then
      Exit;

    HasUnitRange := (FSelectionUnit <> TSelectionUnit.Character);
    if HasUnitRange then
    begin
      if not Anchors.TryAnchorOf(FUnitRange.StartPosition, Selection.UnitStart) then
        Exit;
      if not Anchors.TryAnchorOf(FUnitRange.EndPosition, Selection.UnitEnd) then
        Exit;
    end;

    Result := True;
  finally
    Anchors.Free;
  end;
end;

function TMarkdownViewerModel.TryRestoreSelection(const Selection: TSelectionAnchors): Boolean;
var
  Anchors: TMarkdownTextAnchors;
  HasUnitRange: Boolean;
begin
  Result := False;

  Anchors := TMarkdownTextAnchors.Create(FDisplayList);
  try
    if not Anchors.TryPositionOf(Selection.Anchor, FAnchor) then
      Exit;
    if not Anchors.TryPositionOf(Selection.Extent, FExtent) then
      Exit;

    HasUnitRange := (FSelectionUnit <> TSelectionUnit.Character);
    if HasUnitRange then
    begin
      if not Anchors.TryPositionOf(Selection.UnitStart, FUnitRange.StartPosition) then
        Exit;
      if not Anchors.TryPositionOf(Selection.UnitEnd, FUnitRange.EndPosition) then
        Exit;
    end;

    Result := True;
  finally
    Anchors.Free;
  end;
end;

procedure TMarkdownViewerModel.RegisterImageSlots;
var
  Index: Integer;
  Image: IDisplayImage;
  Slot: TImageSlot;
begin
  for Index := 0 to FDisplayList.ItemCount - 1 do
  begin
    
    if not Supports(FDisplayList.Items[Index], IDisplayImage, Image) then
      Continue;

    if FImageSlots.ContainsKey(Image.Source) then
      Continue;

    Slot := Default(TImageSlot);
    Slot.State := TMarkdownImageSlotState.Requested;
    FImageSlots.Add(Image.Source, Slot);
    FImageSlotOrder.Add(Image.Source);
  end;
end;

function TMarkdownViewerModel.TryResolvePosition(const Point: TLayoutPointF; out Position: TTextPosition): Boolean;
var
  BestIndex: Integer;
  BestRun: IDisplayTextRun;
  BestVertical: type of (MaxSingle);
  BestHorizontal: type of (MaxSingle);
  Index: Integer;
  Run: IDisplayTextRun;
  Bounds: type of (Run.Bounds);
  Vertical: Double;
  Horizontal: Double;
  VerticalComparison: type of (CompareValue(Vertical, BestVertical, LineTopEpsilon));
  IsCloser: Boolean;
begin
  Position := Default(TTextPosition);
  if FDisplayList = nil then
  begin
    Result := False;
    Exit;
  end;

  BestIndex := -1;
  BestRun := nil;
  BestVertical := MaxSingle;
  BestHorizontal := MaxSingle;

  for Index := 0 to FDisplayList.ItemCount - 1 do
  begin
    
    if not TrySelectableRun(Index, Run) then
      Continue;

    Bounds := Run.Bounds;
    Vertical := 0.0;
    if Point.Y < Bounds.Top then
      Vertical := Bounds.Top - Point.Y
    else if Point.Y >= Bounds.Bottom then
      Vertical := Point.Y - Bounds.Bottom;

    Horizontal := 0.0;
    if Point.X < Bounds.Left then
      Horizontal := Bounds.Left - Point.X
    else if Point.X > Bounds.Right then
      Horizontal := Point.X - Bounds.Right;

    VerticalComparison := CompareValue(Vertical, BestVertical, LineTopEpsilon);
    IsCloser := (VerticalComparison < 0) or ((VerticalComparison = 0) and (Horizontal < BestHorizontal));
    if IsCloser then
    begin
      BestIndex := Index;
      BestRun := Run;
      BestVertical := Vertical;
      BestHorizontal := Horizontal;
    end;
  end;

  if BestIndex < 0 then
  begin
    Result := False;
    Exit;
  end;

  Position.ItemIndex := BestIndex;
  Position.CharacterIndex := NearestCharacterBoundary(BestRun, Point.X);
  Result := True;
end;

// The character the pointer is on, rather than the boundary nearest to it: a
// double click picks the word that character belongs to.
function TMarkdownViewerModel.TryResolveCharacter(const Point: TLayoutPointF; out Position: TTextPosition): Boolean;
var
  Run: IDisplayTextRun;
begin
  Result := TryResolvePosition(Point, Position);
  if not Result then
    Exit;

  
  TrySelectableRun(Position.ItemIndex, Run);
  Result := (Run.Text <> '');
  if Result then
    Position.CharacterIndex := CharacterUnderX(Run, Point.X);
end;

function TMarkdownViewerModel.CharacterUnderX(const Run: IDisplayTextRun; const X: Single): Integer;
var
  LocalX: Single;
  Count: Integer;
  IsPastCharacter: Boolean;
begin
  LocalX := X - Run.Bounds.Left;

  Result := 0;
  for Count := 1 to Length(Run.Text) - 1 do
  begin
    IsPastCharacter := (PrefixWidth(Run, Count) <= LocalX);
    if not IsPastCharacter then
      Exit;

    Result := Count;
  end;
end;

function TMarkdownViewerModel.TrySelectableRun(const Index: Integer; out Run: IDisplayTextRun): Boolean;
begin
  Result := TMarkdownTextAnchors.TrySelectableRun(FDisplayList, Index, Run);
end;

// A source run is selected whole or not at all: the pointer picks the edge
// nearest to it, never a character inside the formula.
function TMarkdownViewerModel.NearestCharacterBoundary(const Run: IDisplayTextRun; const X: Single): Integer;
var
  LocalX: Single;
  IsAtomic: Boolean;
  PastMiddle: Boolean;
  BestDistance: Single;
  Count: Integer;
  Distance: Single;
begin
  LocalX := X - Run.Bounds.Left;

  IsAtomic := (Run.Role = TDisplayTextRunRole.Source);
  if IsAtomic then
  begin
    PastMiddle := (LocalX > Run.Bounds.Width / 2);
    if PastMiddle then
    begin
      Result := Length(Run.Text);
      Exit;
    end;

    Result := 0;
    Exit;
  end;

  Result := 0;
  BestDistance := Abs(LocalX);

  for Count := 1 to Length(Run.Text) do
  begin
    Distance := Abs(LocalX - PrefixWidth(Run, Count));
    if Distance < BestDistance then
    begin
      BestDistance := Distance;
      Result := Count;
    end;
  end;
end;

function TMarkdownViewerModel.NormalizeSelection: TTextRange;
begin
  if ComparePositions(FAnchor, FExtent) <= 0 then
  begin
    Result.StartPosition := FAnchor;
    Result.EndPosition := FExtent;
    Exit;
  end;

  Result.StartPosition := FExtent;
  Result.EndPosition := FAnchor;
end;

class function TMarkdownViewerModel.ComparePositions(const Left, Right: TTextPosition): Integer;
begin
  Result := CompareValue(Left.ItemIndex, Right.ItemIndex);
  if Result = 0 then
    Result := CompareValue(Left.CharacterIndex, Right.CharacterIndex);
end;

function TMarkdownViewerModel.SelectedCharacterRange(const Run: IDisplayTextRun; const ItemIndex: Integer;
  const StartPosition, EndPosition: TTextPosition; out CharFrom, CharTo: Integer): Boolean;
begin
  CharFrom := 0;
  CharTo := Length(Run.Text);

  if ItemIndex = StartPosition.ItemIndex then
    CharFrom := StartPosition.CharacterIndex;
  if ItemIndex = EndPosition.ItemIndex then
    CharTo := EndPosition.CharacterIndex;

  Result := CharTo > CharFrom;
end;

function TMarkdownViewerModel.BlockIndexOfItem(const ItemIndex: Integer): Integer;
var
  BlockIndex: Integer;
  Info: TLayoutBlockInfo;
  IsInsideBlock: Boolean;
begin
  for BlockIndex := 0 to FDisplayList.BlockCount - 1 do
  begin
    Info := FDisplayList.BlockInfos[BlockIndex];
    IsInsideBlock := (ItemIndex >= Info.FirstItemIndex) and (ItemIndex < Info.FirstItemIndex + Info.ItemCount);
    if IsInsideBlock then
    begin
      Result := BlockIndex;
      Exit;
    end;
  end;

  Result := -1;
end;

function TMarkdownViewerModel.PrefixWidth(const Run: IDisplayTextRun; const CharacterCount: Integer): Single;
var
  IsAtomic: Boolean;
begin
  if CharacterCount <= 0 then
  begin
    Result := 0;
    Exit;
  end;

  // The source of a drawing is as wide as the drawing, whatever its text measures.
  IsAtomic := (Run.Role = TDisplayTextRunRole.Source);
  if IsAtomic then
  begin
    Result := Run.Bounds.Width;
    Exit;
  end;

  Result := FMeasurer.MeasureText(Copy(Run.Text, 1, CharacterCount), Run.Font).Width;
end;

function TMarkdownViewerModel.GetText: string;
begin
  Result := FText;
end;

procedure TMarkdownViewerModel.SetText(const Value: string);
begin
  FText := Value;
  FPendingMarkdown := '';
  FDirty := False;
  FToggledDisclosures.Clear;
  ClearSelection;
  Relayout;
end;

function TMarkdownViewerModel.GetPendingText: string;
begin
  Result := FPendingMarkdown;
end;

function TMarkdownViewerModel.GetFullText: string;
begin
  Result := FText + FPendingMarkdown;
end;

function TMarkdownViewerModel.GetDisplayList: IMarkdownDisplayList;
begin
  Result := FDisplayList;
end;

function TMarkdownViewerModel.GetLayoutCount: Integer;
begin
  Result := FLayoutCount;
end;

function TMarkdownViewerModel.GetIsDirty: Boolean;
begin
  Result := FDirty;
end;

function TMarkdownViewerModel.GetShouldAutoFollow: Boolean;
begin
  Result := FShouldAutoFollow;
end;

function TMarkdownViewerModel.GetFlushIntervalMilliseconds: Cardinal;
begin
  Result := FFlushIntervalMilliseconds;
end;

procedure TMarkdownViewerModel.SetFlushIntervalMilliseconds(const Value: Cardinal);
begin
  FFlushIntervalMilliseconds := Value;
end;

function TMarkdownViewerModel.GetScrollOffset: Single;
begin
  Result := FScrollOffset;
end;

procedure TMarkdownViewerModel.SetZoom(const Value: Integer);
var
  Percent: Integer;
  PreviousFactor: Single;
  TopLine: TMarkdownTextAnchor;
  Inset: Single;
  HasTopLine: Boolean;
begin
  Percent := TMarkdownZoom.Clamp(Value);
  if Percent = FZoom then
    Exit;

  PreviousFactor := ZoomFactor;
  
  
  HasTopLine := TryCaptureTopLine(TopLine, Inset);

  FZoom := Percent;
  RefreshLayout;

  if HasTopLine then
    ScrollToTopLine(TopLine, Inset * ZoomFactor / PreviousFactor);
end;

function TMarkdownViewerModel.ZoomFactor: Single;
begin
  Result := FZoom / TMarkdownZoom.DefaultPercent;
end;

function TMarkdownViewerModel.LayoutTheme: TMarkdownTheme;
begin
  Result := FTheme;
  if FZoomedTheme <> nil then
    Result := FZoomedTheme;
end;

// Scaled again before every layout, so a change the application made to its
// theme reaches the zoomed copy too.
procedure TMarkdownViewerModel.RefreshZoomedTheme;
var
  IsZoomed: Boolean;
begin
  FreeAndNil(FZoomedTheme);

  IsZoomed := (FZoom <> TMarkdownZoom.DefaultPercent);
  if IsZoomed then
    FZoomedTheme := FTheme.Scaled(ZoomFactor);
end;

// The first line that still shows at the top of the view, and how far the
// view is scrolled past its top.
function TMarkdownViewerModel.TryCaptureTopLine(out TopLine: TMarkdownTextAnchor; out Inset: Single): Boolean;
var
  Anchors: TMarkdownTextAnchors;
  Index: Integer;
  Run: IDisplayTextRun;
  IsAboveView: Boolean;
  Position: TTextPosition;
begin
  TopLine := Default(TMarkdownTextAnchor);
  Inset := 0;
  Result := False;
  if FDisplayList = nil then
    Exit;

  Anchors := TMarkdownTextAnchors.Create(FDisplayList);
  try
    for Index := 0 to FDisplayList.ItemCount - 1 do
    begin
      
      if not TrySelectableRun(Index, Run) then
        Continue;

      IsAboveView := (Run.Bounds.Bottom <= FScrollOffset);
      if IsAboveView then
        Continue;

      
      Position.ItemIndex := Index;
      Position.CharacterIndex := 0;
      Inset := FScrollOffset - Run.Bounds.Top;
      Result := Anchors.TryAnchorOf(Position, TopLine);
      Exit;
    end;
  finally
    Anchors.Free;
  end;
end;

procedure TMarkdownViewerModel.ScrollToTopLine(const TopLine: TMarkdownTextAnchor; const Inset: Single);
var
  Anchors: TMarkdownTextAnchors;
  Position: TTextPosition;
  Run: IDisplayItem;
begin
  Anchors := TMarkdownTextAnchors.Create(FDisplayList);
  try
    
    if not Anchors.TryPositionOf(TopLine, Position) then
      Exit;

    Run := FDisplayList.Items[Position.ItemIndex];
    SetScrollOffset(Run.Bounds.Top + Inset);
  finally
    Anchors.Free;
  end;
end;

procedure TMarkdownViewerModel.SetScrollOffset(const Value: Single);
var
  Clamped: Single;
  MaxOffset: type of (Max(Single(0), FDisplayList.Height - FViewportHeight));
begin
  Clamped := Max(Single(0), Value);
  if FDisplayList <> nil then
  begin
    MaxOffset := Max(Single(0), FDisplayList.Height - FViewportHeight);
    Clamped := Min(Clamped, MaxOffset);
  end;

  FScrollOffset := Clamped;
end;

end.
