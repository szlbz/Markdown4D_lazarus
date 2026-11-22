{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Editor.Model;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Editor.InlineStyle,
  Markdown4D.Editor.Folding,
  Markdown4D.Layout.TextSearch,
  Markdown4D.Compat.Str;

type
  TEditorCommand = (Bold, Italic, Link, CodeBlock, Heading1, Heading2, Heading3, BulletList, NumberedList, Quote,
    Strikethrough, Table);

  TEditorReplaceRange = record
    Start: Integer;
    Length: Integer;
    Replacement: string;
    class function Create(const Start, Length: Integer; const Replacement: string): TEditorReplaceRange; static;
    function Apply(const Source: string): string;
  end;

  TEditorChangeEvent = procedure(const Sender: TObject; const Range: TEditorReplaceRange) of object;

  TMarkdownUndoEntry = record
    Start: Integer;
    RemovedText: string;
    InsertedText: string;
    CaretBefore: Integer;
    AnchorBefore: Integer;
    CaretAfter: Integer;
  end;

  IMarkdownEditorState = interface
    ['{8F2D4A31-6B7C-4E19-9A03-2C5D8E1F4B60}']
  end;

  // Declared again here so code that finds through the editor keeps compiling
  // without naming the unit the options moved to.
  TMarkdownFindOptions = Markdown4D.Layout.TextSearch.TMarkdownFindOptions;

  TMarkdownEditorModel = class
  strict private
    type
      TCharCategory = (Word, Space, Other);
    var
      FText: string;
      FLineStarts: TArray<Integer>;
      FCaret: Integer;
      FAnchor: Integer;
      FUndoStack: TArray<TMarkdownUndoEntry>;
      FRedoStack: TArray<TMarkdownUndoEntry>;
      FCoalesceBroken: Boolean;
      FOnChange: TEditorChangeEvent;
      FCollapsedFolds: TArray<Integer>;
      FFoldRegions: TArray<TFoldRegion>;
      FFoldRegionsDirty: Boolean;
      FHiddenLines: TArray<Boolean>;
      FHiddenLinesDirty: Boolean;
    procedure NormalizeAndLoad(const Value: string);
    class function NormalizeLineEndings(const Value: string): string; static;
    class function CommonPrefixLength(const Left, Right: string): Integer; static;
    class function CommonSuffixLength(const Left, Right: string; const PrefixLength: Integer): Integer; static;
    class function OffsetAfterEdit(const Offset, Start, OldLength, Delta: Integer): Integer; static;
    procedure RebuildLineStarts;
    procedure UpdateLineStartsForEdit(const Start, OldLen: Integer; const Replacement: string);
    procedure DoReplace(const Start, OldLen: Integer; const Replacement: string);
    procedure ApplyReplace(const Start, OldLen: Integer; const Replacement: string; const Coalescable: Boolean);
    procedure RecordUndo(const Start: Integer; const Removed, Inserted: string; const Coalescable: Boolean);
    procedure ApplyCaretMove(const NewCaret: Integer; const Extend: Boolean);
    function NextCaret(const Offset: Integer): Integer;
    function PrevCaret(const Offset: Integer): Integer;
    function ClampOffset(const Offset: Integer): Integer;
    function SnapOffset(const Offset: Integer): Integer;
    function IndexOfNeedle(const Needle: string; const FromOffset: Integer;
      const Options: TMarkdownFindOptions): Integer;
    function MatchesAt(const Needle: string; const CandidateStart: Integer;
      const Options: TMarkdownFindOptions): Boolean;
    function CollectMatches(const Needle: string; const Options: TMarkdownFindOptions): TArray<Integer>;
    function WordLeftOffset(const FromOffset: Integer): Integer;
    function WordRightOffset(const FromOffset: Integer): Integer;
    function IsWordChar(const Ch: Char): Boolean;
    function CategoryOfChar(const Ch: Char): TCharCategory;
    function AllLines: TArray<string>;
    procedure ShiftFolds(const Start, OldLen, NewLen: Integer);
    procedure RebuildHiddenLines;
    function CollapsedIndexOf(const HeaderOffset: Integer): Integer;
    function TryRegionAtHeader(const HeaderLine: Integer; out Region: TFoldRegion): Boolean;
    procedure WrapOrToggle(const Marker: string);
    procedure ToggleInlineStyle(const Style: TMarkdownInlineStyle);
    procedure InsertLink;
    procedure WrapCodeBlock;
    procedure ToggleHeading(const Level: Integer);
    procedure ToggleLinePrefix(const Marker: string);
    procedure ToggleNumberedList;
    procedure InsertTable;
    procedure SelectedLineRegion(out RegionStart, RegionLen: Integer; out Lines: TArray<string>;
      out SingleLine: Boolean);
    procedure ReplaceRegionAndSelect(const RegionStart, RegionLen: Integer; const NewBlock: string);
    class function HeadingPrefixLen(const Line: string): Integer; static;
    class function OrderedPrefixLen(const Line: string): Integer; static;
    function GetText: string;
    procedure SetText(const Value: string);
    function GetCaretPosition: Integer;
    procedure SetCaretPosition(const Value: Integer);
    function GetSelectionStart: Integer;
    function GetSelectionLength: Integer;
    function GetSelectedText: string;
    function GetOnChange: TEditorChangeEvent;
    procedure SetOnChange(const Value: TEditorChangeEvent);

  public
    constructor Create;
    procedure LoadText(const Value: string);
    // Takes over Value as the new content through the smallest possible edit,
    // so the undo history survives and the caret keeps its place in the text.
    // Returns False when the normalized Value already matches the buffer.
    function MergeText(const Value: string): Boolean;
    function CaptureState: IMarkdownEditorState;
    procedure RestoreState(const State: IMarkdownEditorState);
    function LineCount: Integer;
    function LineIndexOfOffset(const Offset: Integer): Integer;
    function OffsetOfLineStart(const LineIndex: Integer): Integer;
    procedure Insert(const Value: string);
    procedure DeleteBackward;
    procedure DeleteForward;
    procedure DeleteWordLeft;
    procedure DeleteWordRight;
    procedure ReplaceRange(const Start, Length: Integer; const Replacement: string);
    procedure MoveCaret(const Delta: Integer; const Extend: Boolean);
    procedure MoveCaretTo(const Offset: Integer; const Extend: Boolean);
    procedure MoveWordLeft(const Extend: Boolean);
    procedure MoveWordRight(const Extend: Boolean);
    procedure SelectAll;
    procedure SetSelection(const Start, Length: Integer);
    // Selects the text inside the range, leaving the whitespace at either end
    // of it out. Style markers cannot sit against the whitespace they
    // enclose, so a range that came from somewhere else is pulled in to the
    // characters it really covers before a command wraps them.
    procedure SelectTextRange(const Start, CharacterCount: Integer);
    procedure SelectWordAt(const Offset: Integer);
    procedure SelectLineAt(const Offset: Integer);
    function HasSelection: Boolean;
    function OffsetInSelection(const Offset: Integer): Boolean;
    // Moves the selected text to Target as one undo step and keeps it selected
    // where it lands. A target inside the selection is a no-op.
    procedure MoveSelectionTo(const Target: Integer);
    // Every match in document order, for hosts that highlight all of them.
    function FindAllMatches(const Needle: string; const Options: TMarkdownFindOptions): TArray<Integer>;
    function FindMatchCount(const Needle: string): Integer; overload;
    function FindMatchCount(const Needle: string; const Options: TMarkdownFindOptions): Integer; overload;
    // Which match the selection covers, counted from 0; -1 when the selection
    // is not a match.
    function FindMatchIndex(const Needle: string; const Options: TMarkdownFindOptions): Integer;
    function FindNext(const Needle: string; const StartAfter: Integer): Integer; overload;
    function FindNext(const Needle: string; const StartAfter: Integer;
      const Options: TMarkdownFindOptions): Integer; overload;
    function FindPrevious(const Needle: string; const StartBefore: Integer;
      const Options: TMarkdownFindOptions): Integer;
    function ReplaceCurrent(const Needle, Replacement: string; const Options: TMarkdownFindOptions): Boolean;
    function ReplaceAll(const Needle, Replacement: string; const Options: TMarkdownFindOptions): Integer;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    procedure BreakUndoCoalescing;
    function FoldRegions: TArray<TFoldRegion>;
    function HasFoldRegions: Boolean;
    function IsFoldHeader(const LineIndex: Integer): Boolean;
    function IsRegionCollapsed(const HeaderLine: Integer): Boolean;
    function IsLineHidden(const LineIndex: Integer): Boolean;
    procedure ToggleFold(const HeaderLine: Integer);
    procedure ExpandAt(const Offset: Integer);
    procedure ExecuteCommand(const Command: TEditorCommand);
    property Text: string read GetText write SetText;
    property CaretPosition: Integer read GetCaretPosition write SetCaretPosition;
    property SelectionStart: Integer read GetSelectionStart;
    property SelectionLength: Integer read GetSelectionLength;
    property SelectedText: string read GetSelectedText;
    property OnChange: TEditorChangeEvent read GetOnChange write SetOnChange;
  end;

implementation

uses
  SysUtils,
  Math,
  character,
  Markdown4D.Defines;

type
  TMarkdownEditorStateObject = class(TInterfacedObject, IMarkdownEditorState)
  public
    Text: string;
    Caret: Integer;
    Anchor: Integer;
    UndoStack: TArray<TMarkdownUndoEntry>;
    RedoStack: TArray<TMarkdownUndoEntry>;
    CoalesceBroken: Boolean;
  end;

const
  HeadingMarkerChar = '#';
  SpaceStr = ' ';
  DotStr = '.';
  BulletMarker = '- ';
  QuoteMarker = '> ';
  OrderedMarkerFormat = '%d. ';
  TableHeaderLine = '| Header 1 | Header 2 | Header 3 |';
  TableDelimiterLine = '| --- | --- | --- |';
  TableBodyLine = '| Cell | Cell | Cell |';

class function TEditorReplaceRange.Create(const Start, Length: Integer;
  const Replacement: string): TEditorReplaceRange;
begin
  Result.Start := Start;
  Result.Length := Length;
  Result.Replacement := Replacement;
end;

function TEditorReplaceRange.Apply(const Source: string): string;
begin
  Result := Copy(Source, 1, Start) + Replacement + Copy(Source, Start + Length + 1, System.Length(Source));
end;

constructor TMarkdownEditorModel.Create;
begin
  inherited Create;

  FLineStarts := [0];
  FFoldRegionsDirty := True;
end;

procedure TMarkdownEditorModel.LoadText(const Value: string);
begin
  NormalizeAndLoad(Value);
end;

function TMarkdownEditorModel.MergeText(const Value: string): Boolean;
var
  Incoming: string;
  Start: Integer;
  TailLength: Integer;
  OldLength: Integer;
  Replacement: string;
  PreviousCaret: Integer;
  PreviousAnchor: Integer;
  Delta: Integer;
begin
  Incoming := NormalizeLineEndings(Value);
  if Incoming = FText then
  begin
    Result := False;
    Exit;
  end;

  Start := CommonPrefixLength(FText, Incoming);
  TailLength := CommonSuffixLength(FText, Incoming, Start);

  OldLength := System.Length(FText) - Start - TailLength;
  Replacement := Copy(Incoming, Start + 1, System.Length(Incoming) - Start - TailLength);

  PreviousCaret := FCaret;
  PreviousAnchor := FAnchor;

  BreakUndoCoalescing;
  ApplyReplace(Start, OldLength, Replacement, False);
  BreakUndoCoalescing;

  Delta := System.Length(Replacement) - OldLength;
  FCaret := SnapOffset(OffsetAfterEdit(PreviousCaret, Start, OldLength, Delta));
  FAnchor := SnapOffset(OffsetAfterEdit(PreviousAnchor, Start, OldLength, Delta));

  Result := True;
end;

function TMarkdownEditorModel.CaptureState: IMarkdownEditorState;
var
  Snapshot: TMarkdownEditorStateObject;
begin
  Snapshot := TMarkdownEditorStateObject.Create;

  Snapshot.Text := FText;
  Snapshot.Caret := FCaret;
  Snapshot.Anchor := FAnchor;
  Snapshot.UndoStack := FUndoStack;
  Snapshot.RedoStack := FRedoStack;
  Snapshot.CoalesceBroken := FCoalesceBroken;

  Result := Snapshot;
end;

procedure TMarkdownEditorModel.RestoreState(const State: IMarkdownEditorState);
var
  Snapshot: TMarkdownEditorStateObject;
begin
  Snapshot := State as TMarkdownEditorStateObject;

  FText := Snapshot.Text;
  RebuildLineStarts;

  FCaret := Snapshot.Caret;
  FAnchor := Snapshot.Anchor;
  FUndoStack := Snapshot.UndoStack;
  FRedoStack := Snapshot.RedoStack;
  FCoalesceBroken := Snapshot.CoalesceBroken;
  FCollapsedFolds := nil;
  FFoldRegionsDirty := True;
  FHiddenLinesDirty := True;
end;

function TMarkdownEditorModel.LineCount: Integer;
begin
  Result := System.Length(FLineStarts);
end;

function TMarkdownEditorModel.LineIndexOfOffset(const Offset: Integer): Integer;
var
  LowerBound: Integer;
  UpperBound: Integer;
  Candidate: Integer;
begin
  LowerBound := 0;
  UpperBound := High(FLineStarts);
  Result := 0;
  while LowerBound <= UpperBound do
  begin
    Candidate := (LowerBound + UpperBound) div 2;
    if FLineStarts[Candidate] <= Offset then
    begin
      Result := Candidate;
      LowerBound := Candidate + 1;
    end
    else
    begin
      UpperBound := Candidate - 1;
    end;
  end;
end;

function TMarkdownEditorModel.OffsetOfLineStart(const LineIndex: Integer): Integer;
var
  Clamped: type of (EnsureRange(LineIndex, 0, High(FLineStarts)));
begin
  Clamped := EnsureRange(LineIndex, 0, High(FLineStarts));
  Result := FLineStarts[Clamped];
end;

procedure TMarkdownEditorModel.Insert(const Value: string);
var
  Start: Integer;
  Len: Integer;
begin
  Start := SelectionStart;
  Len := SelectionLength;
  ApplyReplace(Start, Len, Value, Len = 0);
end;

procedure TMarkdownEditorModel.DeleteBackward;
var
  Previous: Integer;
begin
  if HasSelection then
  begin
    ApplyReplace(SelectionStart, SelectionLength, '', False);
    Exit;
  end;

  if FCaret <= 0 then
    Exit;

  Previous := PrevCaret(FCaret);
  ApplyReplace(Previous, FCaret - Previous, '', True);
end;

procedure TMarkdownEditorModel.DeleteForward;
var
  Next: Integer;
begin
  if HasSelection then
  begin
    ApplyReplace(SelectionStart, SelectionLength, '', False);
    Exit;
  end;

  if FCaret >= System.Length(FText) then
    Exit;

  Next := NextCaret(FCaret);
  ApplyReplace(FCaret, Next - FCaret, '', True);
end;

procedure TMarkdownEditorModel.DeleteWordLeft;
var
  Start: Integer;
begin
  if HasSelection then
  begin
    ApplyReplace(SelectionStart, SelectionLength, '', False);
    Exit;
  end;

  if FCaret <= 0 then
    Exit;

  Start := WordLeftOffset(FCaret);
  ApplyReplace(Start, FCaret - Start, '', True);
end;

procedure TMarkdownEditorModel.DeleteWordRight;
var
  EndOffset: Integer;
begin
  if HasSelection then
  begin
    ApplyReplace(SelectionStart, SelectionLength, '', False);
    Exit;
  end;

  if FCaret >= System.Length(FText) then
    Exit;

  EndOffset := WordRightOffset(FCaret);
  ApplyReplace(FCaret, EndOffset - FCaret, '', True);
end;

procedure TMarkdownEditorModel.ReplaceRange(const Start, Length: Integer; const Replacement: string);
begin
  ApplyReplace(Start, Length, Replacement, False);
end;

procedure TMarkdownEditorModel.MoveCaret(const Delta: Integer; const Extend: Boolean);
var
  NewCaret: Integer;
  Step: Integer;
begin
  NewCaret := FCaret;
  if Delta > 0 then
  begin
    for Step := 1 to Delta do
    begin
      NewCaret := NextCaret(NewCaret);
    end;
  end
  else
  begin
    for Step := 1 to -Delta do
    begin
      NewCaret := PrevCaret(NewCaret);
    end;
  end;

  ApplyCaretMove(NewCaret, Extend);
end;

procedure TMarkdownEditorModel.MoveCaretTo(const Offset: Integer; const Extend: Boolean);
begin
  ApplyCaretMove(SnapOffset(Offset), Extend);
end;

procedure TMarkdownEditorModel.MoveWordLeft(const Extend: Boolean);
begin
  ApplyCaretMove(WordLeftOffset(FCaret), Extend);
end;

procedure TMarkdownEditorModel.MoveWordRight(const Extend: Boolean);
begin
  ApplyCaretMove(WordRightOffset(FCaret), Extend);
end;

procedure TMarkdownEditorModel.SelectAll;
begin
  FAnchor := 0;
  FCaret := System.Length(FText);
end;

procedure TMarkdownEditorModel.SetSelection(const Start, Length: Integer);
begin
  FAnchor := SnapOffset(Start);
  FCaret := SnapOffset(Start + Length);
end;

procedure TMarkdownEditorModel.SelectTextRange(const Start, CharacterCount: Integer);
var
  First: Integer;
  Last: Integer;
begin
  First := ClampOffset(Start);
  Last := ClampOffset(Start + CharacterCount);

  while (First < Last) and FText[First + 1].IsWhiteSpace do
  begin
    Inc(First);
  end;

  while (Last > First) and FText[Last].IsWhiteSpace do
  begin
    Dec(Last);
  end;

  SetSelection(First, Last - First);
end;

procedure TMarkdownEditorModel.SelectWordAt(const Offset: Integer);
var
  Len: Integer;
  Clamped: Integer;
  RefIndex: Integer;
  PrefersLeft: Boolean;
  Category: TCharCategory;
  StartIndex: Integer;
  EndIndex: Integer;
begin
  Len := System.Length(FText);
  if Len = 0 then
  begin
    SetSelection(0, 0);
    Exit;
  end;

  Clamped := ClampOffset(Offset);

  RefIndex := Min(Clamped + 1, Len);
  PrefersLeft := (Clamped >= 1) and (Clamped < Len) and
    (CategoryOfChar(FText[RefIndex]) = TCharCategory.Space) and
    (CategoryOfChar(FText[Clamped]) <> TCharCategory.Space);
  if PrefersLeft then
    RefIndex := Clamped;

  Category := CategoryOfChar(FText[RefIndex]);

  StartIndex := RefIndex;
  while (StartIndex > 1) and (CategoryOfChar(FText[StartIndex - 1]) = Category) do
    Dec(StartIndex);

  EndIndex := RefIndex;
  while (EndIndex < Len) and (CategoryOfChar(FText[EndIndex + 1]) = Category) do
    Inc(EndIndex);

  SetSelection(StartIndex - 1, EndIndex - StartIndex + 1);
end;

procedure TMarkdownEditorModel.SelectLineAt(const Offset: Integer);
var
  Clamped: Integer;
  Line: Integer;
  Start: Integer;
  EndOffset: Integer;
begin
  Clamped := ClampOffset(Offset);
  Line := LineIndexOfOffset(Clamped);
  Start := OffsetOfLineStart(Line);

  
  if Line < LineCount - 1 then
    EndOffset := OffsetOfLineStart(Line + 1) - 1
  else
    EndOffset := System.Length(FText);

  SetSelection(Start, EndOffset - Start);
end;

function TMarkdownEditorModel.HasSelection: Boolean;
begin
  Result := FCaret <> FAnchor;
end;

function TMarkdownEditorModel.OffsetInSelection(const Offset: Integer): Boolean;
begin
  Result := HasSelection and (Offset > SelectionStart) and (Offset < SelectionStart + SelectionLength);
end;

procedure TMarkdownEditorModel.MoveSelectionTo(const Target: Integer);
var
  Start: Integer;
  Len: Integer;
  Landing: Integer;
  DropsOnItself: Boolean;
  Moved: string;
  Between: string;
begin
  if not HasSelection then
    Exit;

  Start := SelectionStart;
  Len := SelectionLength;
  Landing := SnapOffset(Target);

  DropsOnItself := (Landing >= Start) and (Landing <= Start + Len);
  if DropsOnItself then
    Exit;

  Moved := SelectedText;
  BreakUndoCoalescing;

  if Landing > Start + Len then
  begin
    Between := Copy(FText, Start + Len + 1, Landing - Start - Len);
    ApplyReplace(Start, Landing - Start, Between + Moved, False);
    FAnchor := Landing - Len;
    FCaret := Landing;
    Exit;
  end;

  Between := Copy(FText, Landing + 1, Start - Landing);
  ApplyReplace(Landing, Start + Len - Landing, Moved + Between, False);
  FAnchor := Landing;
  FCaret := Landing + Len;
end;

function TMarkdownEditorModel.FindAllMatches(const Needle: string;
  const Options: TMarkdownFindOptions): TArray<Integer>;
begin
  Result := CollectMatches(Needle, Options);
end;

function TMarkdownEditorModel.FindMatchCount(const Needle: string): Integer;
begin
  Result := FindMatchCount(Needle, Default(TMarkdownFindOptions));
end;

function TMarkdownEditorModel.FindMatchCount(const Needle: string; const Options: TMarkdownFindOptions): Integer;
begin
  Result := System.Length(CollectMatches(Needle, Options));
end;

function TMarkdownEditorModel.FindMatchIndex(const Needle: string; const Options: TMarkdownFindOptions): Integer;
var
  SelectsNeedleLength: Boolean;
  Matches: TArray<Integer>;
  Index: Integer;
  IsSelected: Boolean;
begin
  Result := -1;

  SelectsNeedleLength := (SelectionLength = System.Length(Needle));
  if not SelectsNeedleLength then
    Exit;

  Matches := CollectMatches(Needle, Options);
  for Index := 0 to High(Matches) do
  begin
    IsSelected := (Matches[Index] = SelectionStart);
    if IsSelected then
    begin
      Result := Index;
      Exit;
    end;
  end;
end;

function TMarkdownEditorModel.FindNext(const Needle: string; const StartAfter: Integer): Integer;
begin
  Result := FindNext(Needle, StartAfter, Default(TMarkdownFindOptions));
end;

function TMarkdownEditorModel.FindNext(const Needle: string; const StartAfter: Integer;
  const Options: TMarkdownFindOptions): Integer;
var
  Primary: Integer;
begin
  if Needle = '' then
  begin
    Result := -1;
    Exit;
  end;

  if System.Length(Needle) > System.Length(FText) then
  begin
    Result := -1;
    Exit;
  end;

  Primary := IndexOfNeedle(Needle, StartAfter + 1, Options);
  if Primary >= 0 then
  begin
    Result := Primary;
    Exit;
  end;

  Result := IndexOfNeedle(Needle, 0, Options);
end;

function TMarkdownEditorModel.FindPrevious(const Needle: string; const StartBefore: Integer;
  const Options: TMarkdownFindOptions): Integer;
var
  Matches: TArray<Integer>;
  Best: Integer;
  Start: Integer;
begin
  Matches := CollectMatches(Needle, Options);
  if System.Length(Matches) = 0 then
  begin
    Result := -1;
    Exit;
  end;

  Best := -1;
  for Start in Matches do
  begin
    if Start < StartBefore then
      Best := Start;
  end;

  if Best >= 0 then
  begin
    Result := Best;
    Exit;
  end;

  Result := Matches[High(Matches)];
end;

function TMarkdownEditorModel.ReplaceCurrent(const Needle, Replacement: string;
  const Options: TMarkdownFindOptions): Boolean;
var
  NextStart: Integer;
begin
  if Needle = '' then
  begin
    Result := False;
    Exit;
  end;

  Result := (SelectionLength = System.Length(Needle)) and MatchesAt(Needle, SelectionStart, Options);
  if Result then
    ReplaceRange(SelectionStart, SelectionLength, Replacement);

  NextStart := FindNext(Needle, SelectionStart + SelectionLength - 1, Options);
  if NextStart >= 0 then
    SetSelection(NextStart, System.Length(Needle));
end;

function TMarkdownEditorModel.ReplaceAll(const Needle, Replacement: string;
  const Options: TMarkdownFindOptions): Integer;
var
  Matches: TArray<Integer>;
  NeedleLen: Integer;
  SpanStart: Integer;
  SpanEnd: Integer;
  Builder: string;
  Cursor: Integer;
  Start: Integer;
begin
  Matches := CollectMatches(Needle, Options);
  Result := System.Length(Matches);
  if Result = 0 then
    Exit;

  NeedleLen := System.Length(Needle);
  SpanStart := Matches[0];
  SpanEnd := Matches[High(Matches)] + NeedleLen;

  Builder := '';
  Cursor := SpanStart;
  for Start in Matches do
  begin
    Builder := Builder + Copy(FText, Cursor + 1, Start - Cursor) + Replacement;
    Cursor := Start + NeedleLen;
  end;

  ReplaceRange(SpanStart, SpanEnd - SpanStart, Builder);
end;

procedure TMarkdownEditorModel.Undo;
var
  Entry: TMarkdownUndoEntry;
begin
  if System.Length(FUndoStack) = 0 then
    Exit;

  Entry := FUndoStack[High(FUndoStack)];
  SetLength(FUndoStack, System.Length(FUndoStack) - 1);

  FRedoStack := FRedoStack + [Entry];
  FCaret := Entry.CaretBefore;
  FAnchor := Entry.AnchorBefore;
  FCoalesceBroken := True;

  DoReplace(Entry.Start, System.Length(Entry.InsertedText), Entry.RemovedText);
end;

procedure TMarkdownEditorModel.Redo;
var
  Entry: TMarkdownUndoEntry;
begin
  if System.Length(FRedoStack) = 0 then
    Exit;

  Entry := FRedoStack[High(FRedoStack)];
  SetLength(FRedoStack, System.Length(FRedoStack) - 1);

  FUndoStack := FUndoStack + [Entry];
  FCaret := Entry.CaretAfter;
  FAnchor := Entry.CaretAfter;
  FCoalesceBroken := True;

  DoReplace(Entry.Start, System.Length(Entry.RemovedText), Entry.InsertedText);
end;

function TMarkdownEditorModel.CanUndo: Boolean;
begin
  Result := System.Length(FUndoStack) > 0;
end;

function TMarkdownEditorModel.CanRedo: Boolean;
begin
  Result := System.Length(FRedoStack) > 0;
end;

procedure TMarkdownEditorModel.BreakUndoCoalescing;
begin
  FCoalesceBroken := True;
end;

function TMarkdownEditorModel.FoldRegions: TArray<TFoldRegion>;
begin
  if FFoldRegionsDirty then
  begin
    FFoldRegions := TMarkdownFoldComputer.ComputeRegions(AllLines);
    FFoldRegionsDirty := False;
  end;

  Result := FFoldRegions;
end;

function TMarkdownEditorModel.HasFoldRegions: Boolean;
begin
  Result := System.Length(FoldRegions) > 0;
end;

function TMarkdownEditorModel.IsFoldHeader(const LineIndex: Integer): Boolean;
var
  Region: TFoldRegion;
begin
  for Region in FoldRegions do
  begin
    if Region.HeaderLine = LineIndex then
    begin
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

function TMarkdownEditorModel.IsRegionCollapsed(const HeaderLine: Integer): Boolean;
begin
  Result := CollapsedIndexOf(OffsetOfLineStart(HeaderLine)) >= 0;
end;

function TMarkdownEditorModel.IsLineHidden(const LineIndex: Integer): Boolean;
begin
  // Editors ask this for every line on every repaint, so the answer is kept as
  // a flat array instead of a scan over the fold regions per line.
  if FHiddenLinesDirty then
    RebuildHiddenLines;

  if (LineIndex < 0) or (LineIndex > High(FHiddenLines)) then
  begin
    Result := False;
    Exit;
  end;

  Result := FHiddenLines[LineIndex];
end;

procedure TMarkdownEditorModel.RebuildHiddenLines;
var
  Index: Integer;
  Region: TFoldRegion;
  Line: Integer;
begin
  FHiddenLinesDirty := False;
  SetLength(FHiddenLines, LineCount);

  for Index := 0 to High(FHiddenLines) do
  begin
    FHiddenLines[Index] := False;
  end;

  if System.Length(FCollapsedFolds) = 0 then
    Exit;

  for Region in FoldRegions do
  begin
    if not IsRegionCollapsed(Region.HeaderLine) then
      Continue;

    for Line := Region.StartLine to Min(Region.EndLine, High(FHiddenLines)) do
    begin
      FHiddenLines[Line] := True;
    end;
  end;
end;

procedure TMarkdownEditorModel.ToggleFold(const HeaderLine: Integer);
var
  Region: TFoldRegion;
  HeaderOffset: Integer;
  Existing: Integer;
  CaretLine: Integer;
begin
  
  if not TryRegionAtHeader(HeaderLine, Region) then
    Exit;

  HeaderOffset := OffsetOfLineStart(HeaderLine);
  Existing := CollapsedIndexOf(HeaderOffset);

  if Existing >= 0 then
  begin
    Delete(FCollapsedFolds, Existing, 1);
    FHiddenLinesDirty := True;
    Exit;
  end;

  FCollapsedFolds := FCollapsedFolds + [HeaderOffset];
  FHiddenLinesDirty := True;

  CaretLine := LineIndexOfOffset(FCaret);
  if Region.Contains(CaretLine) then
  begin
    FCaret := HeaderOffset;
    FAnchor := HeaderOffset;
  end;
end;

procedure TMarkdownEditorModel.ExpandAt(const Offset: Integer);
var
  Line: Integer;
  Region: TFoldRegion;
  Existing: Integer;
begin
  Line := LineIndexOfOffset(ClampOffset(Offset));

  for Region in FoldRegions do
  begin
    if not (Region.Contains(Line) and IsRegionCollapsed(Region.HeaderLine)) then
      Continue;

    Existing := CollapsedIndexOf(OffsetOfLineStart(Region.HeaderLine));
    if Existing >= 0 then
    begin
      Delete(FCollapsedFolds, Existing, 1);
      FHiddenLinesDirty := True;
    end;
  end;
end;

function TMarkdownEditorModel.AllLines: TArray<string>;
var
  Count: Integer;
  Index: Integer;
  StartOffset: Integer;
  EndExclusive: Integer;
begin
  Count := LineCount;
  SetLength(Result, Count);

  for Index := 0 to Count - 1 do
  begin
    StartOffset := FLineStarts[Index];

    
    if Index < Count - 1 then
      EndExclusive := FLineStarts[Index + 1] - 1
    else
      EndExclusive := System.Length(FText);

    Result[Index] := Copy(FText, StartOffset + 1, EndExclusive - StartOffset);
  end;
end;

procedure TMarkdownEditorModel.ShiftFolds(const Start, OldLen, NewLen: Integer);
var
  Delta: Integer;
  OldEnd: Integer;
  Kept: TArray<Integer>;
  Offset: Integer;
begin
  if System.Length(FCollapsedFolds) = 0 then
    Exit;

  Delta := NewLen - OldLen;
  OldEnd := Start + OldLen;

  Kept := [];
  for Offset in FCollapsedFolds do
  begin
    if Offset <= Start then
      Kept := Kept + [Offset]
    else if Offset >= OldEnd then
      Kept := Kept + [Offset + Delta];
  end;

  FCollapsedFolds := Kept;
end;

function TMarkdownEditorModel.CollapsedIndexOf(const HeaderOffset: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FCollapsedFolds) do
  begin
    if FCollapsedFolds[Index] = HeaderOffset then
    begin
      Result := Index;
      Exit;
    end;
  end;

  Result := -1;
end;

function TMarkdownEditorModel.TryRegionAtHeader(const HeaderLine: Integer; out Region: TFoldRegion): Boolean;
var
  Candidate: TFoldRegion;
begin
  for Candidate in FoldRegions do
  begin
    if Candidate.HeaderLine = HeaderLine then
    begin
      Region := Candidate;
      Result := True;
      Exit;
    end;
  end;

  Region := Default(TFoldRegion);
  Result := False;
end;

procedure TMarkdownEditorModel.ExecuteCommand(const Command: TEditorCommand);
begin
  BreakUndoCoalescing;

  case Command of
    TEditorCommand.Bold:
      ToggleInlineStyle(TMarkdownInlineStyle.Strong);
    TEditorCommand.Italic:
      ToggleInlineStyle(TMarkdownInlineStyle.Emphasis);
    TEditorCommand.Link:
      InsertLink;
    TEditorCommand.CodeBlock:
      WrapCodeBlock;
    TEditorCommand.Heading1:
      ToggleHeading(1);
    TEditorCommand.Heading2:
      ToggleHeading(2);
    TEditorCommand.Heading3:
      ToggleHeading(3);
    TEditorCommand.BulletList:
      ToggleLinePrefix(BulletMarker);
    TEditorCommand.NumberedList:
      ToggleNumberedList;
    TEditorCommand.Quote:
      ToggleLinePrefix(QuoteMarker);
    TEditorCommand.Strikethrough:
      ToggleInlineStyle(TMarkdownInlineStyle.Strikethrough);
    TEditorCommand.Table:
      InsertTable;
  else
    raise EMarkdownError.CreateFmt('Unhandled command: %d', [Ord(Command)]);
  end;

  BreakUndoCoalescing;
end;

procedure TMarkdownEditorModel.NormalizeAndLoad(const Value: string);
begin
  FText := NormalizeLineEndings(Value);
  RebuildLineStarts;
  FCaret := 0;
  FAnchor := 0;
  FUndoStack := nil;
  FRedoStack := nil;
  FCoalesceBroken := False;
  FCollapsedFolds := nil;
  FFoldRegionsDirty := True;
end;

class function TMarkdownEditorModel.NormalizeLineEndings(const Value: string): string;
begin
  Result := StringReplace(Value, CarriageReturn + LineFeed, LineFeed, [rfReplaceAll]);
  Result := StringReplace(Result, CarriageReturn, LineFeed, [rfReplaceAll]);
end;

class function TMarkdownEditorModel.CommonPrefixLength(const Left, Right: string): Integer;
var
  Limit: Integer;
  SplitsPair: Boolean;
begin
  Limit := Min(System.Length(Left), System.Length(Right));

  Result := 0;
  while (Result < Limit) and (Left[Result + 1] = Right[Result + 1]) do
    Inc(Result);

  SplitsPair := (Result > 0) and Left[Result].IsHighSurrogate;
  if SplitsPair then
    Dec(Result);
end;

class function TMarkdownEditorModel.CommonSuffixLength(const Left, Right: string;
  const PrefixLength: Integer): Integer;
var
  Limit: Integer;
  SplitsPair: Boolean;
begin
  Limit := Min(System.Length(Left), System.Length(Right)) - PrefixLength;

  Result := 0;
  while (Result < Limit) and
    (Left[System.Length(Left) - Result] = Right[System.Length(Right) - Result]) do
  begin
    Inc(Result);
  end;

  SplitsPair := (Result > 0) and Left[System.Length(Left) - Result + 1].IsLowSurrogate;
  if SplitsPair then
    Dec(Result);
end;

class function TMarkdownEditorModel.OffsetAfterEdit(const Offset, Start, OldLength, Delta: Integer): Integer;
begin
  if Offset <= Start then
  begin
    Result := Offset;
    Exit;
  end;

  if Offset >= Start + OldLength then
  begin
    Result := Offset + Delta;
    Exit;
  end;

  Result := Start + OldLength + Delta;
end;

procedure TMarkdownEditorModel.RebuildLineStarts;
var
  Index: Integer;
begin
  FLineStarts := [0];
  for Index := 1 to System.Length(FText) do
  begin
    if FText[Index] = #10 then
      FLineStarts := FLineStarts + [Index];
  end;
end;

procedure TMarkdownEditorModel.UpdateLineStartsForEdit(const Start, OldLen: Integer; const Replacement: string);
var
  Delta: Integer;
  OldEnd: Integer;
  NewStarts: TArray<Integer>;
  LineStart: Integer;
  Index: Integer;
begin
  Delta := System.Length(Replacement) - OldLen;
  OldEnd := Start + OldLen;

  NewStarts := [];
  for LineStart in FLineStarts do
  begin
    if LineStart <= Start then
      NewStarts := NewStarts + [LineStart];
  end;

  for Index := 1 to System.Length(Replacement) do
  begin
    if Replacement[Index] = #10 then
      NewStarts := NewStarts + [Start + Index];
  end;

  for LineStart in FLineStarts do
  begin
    if LineStart > OldEnd then
      NewStarts := NewStarts + [LineStart + Delta];
  end;

  FLineStarts := NewStarts;
end;

procedure TMarkdownEditorModel.DoReplace(const Start, OldLen: Integer; const Replacement: string);
begin
  FText := Copy(FText, 1, Start) + Replacement + Copy(FText, Start + OldLen + 1, System.Length(FText));
  UpdateLineStartsForEdit(Start, OldLen, Replacement);
  ShiftFolds(Start, OldLen, System.Length(Replacement));
  FFoldRegionsDirty := True;
  FHiddenLinesDirty := True;

  if Assigned(FOnChange) then
    FOnChange(Self, TEditorReplaceRange.Create(Start, OldLen, Replacement));
end;

procedure TMarkdownEditorModel.ApplyReplace(const Start, OldLen: Integer; const Replacement: string;
  const Coalescable: Boolean);
begin
  RecordUndo(Start, Copy(FText, Start + 1, OldLen), Replacement, Coalescable);

  { RecordUndo needs the caret from before the edit, DoReplace raises OnChange and every
    listener needs the caret from after it, so the move belongs between the two. }
  FRedoStack := nil;
  FCaret := Start + System.Length(Replacement);
  FAnchor := FCaret;

  DoReplace(Start, OldLen, Replacement);
end;

procedure TMarkdownEditorModel.RecordUndo(const Start: Integer; const Removed, Inserted: string;
  const Coalescable: Boolean);
var
  CanMerge: Boolean;
  Top: TMarkdownUndoEntry;
  IsContiguousInsertion: Boolean;
  IsDeletion: Boolean;
  ContinuesBackward: Boolean;
  ContinuesForward: Boolean;
  Entry: TMarkdownUndoEntry;
begin
  CanMerge := (Coalescable and not FCoalesceBroken and (System.Length(FUndoStack) > 0));
  if CanMerge then
  begin
    Top := FUndoStack[High(FUndoStack)];

    IsContiguousInsertion := (Removed = '') and (Top.RemovedText = '') and
      (Top.Start + System.Length(Top.InsertedText) = Start);
    if IsContiguousInsertion then
    begin
      Top.InsertedText := Top.InsertedText + Inserted;
      Top.CaretAfter := Start + System.Length(Inserted);
      FUndoStack[High(FUndoStack)] := Top;
      Exit;
    end;

    // A run of backspaces or deletes belongs to one undo step, the same way a
    // run of typed characters does.
    IsDeletion := (Inserted = '') and (Top.InsertedText = '') and (Removed <> '');

    ContinuesBackward := IsDeletion and (Start + System.Length(Removed) = Top.Start);
    if ContinuesBackward then
    begin
      Top.Start := Start;
      Top.RemovedText := Removed + Top.RemovedText;
      Top.CaretAfter := Start;
      FUndoStack[High(FUndoStack)] := Top;
      Exit;
    end;

    ContinuesForward := IsDeletion and (Start = Top.Start);
    if ContinuesForward then
    begin
      Top.RemovedText := Top.RemovedText + Removed;
      Top.CaretAfter := Start;
      FUndoStack[High(FUndoStack)] := Top;
      Exit;
    end;
  end;

  Entry := Default(TMarkdownUndoEntry);
  Entry.Start := Start;
  Entry.RemovedText := Removed;
  Entry.InsertedText := Inserted;
  Entry.CaretBefore := FCaret;
  Entry.AnchorBefore := FAnchor;
  Entry.CaretAfter := Start + System.Length(Inserted);
  FUndoStack := FUndoStack + [Entry];
  FCoalesceBroken := not Coalescable;
end;

procedure TMarkdownEditorModel.ApplyCaretMove(const NewCaret: Integer; const Extend: Boolean);
begin
  FCaret := NewCaret;
  if not Extend then
    FAnchor := NewCaret;
end;

function TMarkdownEditorModel.NextCaret(const Offset: Integer): Integer;
var
  IsPair: Boolean;
begin
  if Offset >= System.Length(FText) then
  begin
    Result := System.Length(FText);
    Exit;
  end;

  IsPair := FText[Offset + 1].IsHighSurrogate and (Offset + 2 <= System.Length(FText)) and
    FText[Offset + 2].IsLowSurrogate;
  if IsPair then
    Result := Offset + 2
  else
    Result := Offset + 1;
end;

function TMarkdownEditorModel.PrevCaret(const Offset: Integer): Integer;
var
  IsPair: Boolean;
begin
  if Offset <= 0 then
  begin
    Result := 0;
    Exit;
  end;

  IsPair := FText[Offset].IsLowSurrogate and (Offset - 1 >= 1) and FText[Offset - 1].IsHighSurrogate;
  if IsPair then
    Result := Offset - 2
  else
    Result := Offset - 1;
end;

function TMarkdownEditorModel.ClampOffset(const Offset: Integer): Integer;
begin
  Result := EnsureRange(Offset, 0, System.Length(FText));
end;

function TMarkdownEditorModel.SnapOffset(const Offset: Integer): Integer;
var
  IsMidPair: Boolean;
begin
  Result := ClampOffset(Offset);

  IsMidPair := (Result > 0) and (Result < System.Length(FText)) and FText[Result].IsHighSurrogate and
    FText[Result + 1].IsLowSurrogate;
  if IsMidPair then
    Inc(Result);
end;

function TMarkdownEditorModel.IndexOfNeedle(const Needle: string; const FromOffset: Integer;
  const Options: TMarkdownFindOptions): Integer;
var
  Start: type of (EnsureRange(FromOffset, 0, System.Length(FText)));
  Found: Integer;
begin
  Start := EnsureRange(FromOffset, 0, System.Length(FText));
  Found := TMarkdownTextSearch.IndexOf(Needle, FText, Start + 1, Options);
  Result := Found - 1;
end;

function TMarkdownEditorModel.MatchesAt(const Needle: string; const CandidateStart: Integer;
  const Options: TMarkdownFindOptions): Boolean;
begin
  Result := TMarkdownTextSearch.MatchesAt(Needle, FText, CandidateStart + 1, Options);
end;

function TMarkdownEditorModel.CollectMatches(const Needle: string;
  const Options: TMarkdownFindOptions): TArray<Integer>;
var
  Cursor: Integer;
  Hit: Integer;
begin
  Result := [];

  if Needle = '' then
    Exit;

  if System.Length(Needle) > System.Length(FText) then
    Exit;

  Cursor := 0;
  Hit := IndexOfNeedle(Needle, Cursor, Options);
  while Hit >= 0 do
  begin
    Result := Result + [Hit];
    Cursor := Hit + System.Length(Needle);
    Hit := IndexOfNeedle(Needle, Cursor, Options);
  end;
end;

function TMarkdownEditorModel.WordLeftOffset(const FromOffset: Integer): Integer;
var
  Offset: Integer;
  Category: TCharCategory;
begin
  Offset := ClampOffset(FromOffset);

  while (Offset > 0) and FText[Offset].IsWhiteSpace do
    Dec(Offset);

  if Offset = 0 then
  begin
    Result := 0;
    Exit;
  end;

  Category := CategoryOfChar(FText[Offset]);
  while (Offset > 0) and (CategoryOfChar(FText[Offset]) = Category) do
    Dec(Offset);

  Result := Offset;
end;

function TMarkdownEditorModel.WordRightOffset(const FromOffset: Integer): Integer;
var
  Limit: Integer;
  Offset: Integer;
  Category: TCharCategory;
begin
  Limit := System.Length(FText);
  Offset := ClampOffset(FromOffset);

  if (Offset < Limit) and not FText[Offset + 1].IsWhiteSpace then
  begin
    Category := CategoryOfChar(FText[Offset + 1]);
    while (Offset < Limit) and (CategoryOfChar(FText[Offset + 1]) = Category) do
      Inc(Offset);
  end;

  while (Offset < Limit) and FText[Offset + 1].IsWhiteSpace do
    Inc(Offset);

  Result := Offset;
end;

function TMarkdownEditorModel.IsWordChar(const Ch: Char): Boolean;
begin
  Result := TMarkdownTextSearch.IsWordCharacter(Ch);
end;

function TMarkdownEditorModel.CategoryOfChar(const Ch: Char): TCharCategory;
begin
  if IsWordChar(Ch) then
    Result := TCharCategory.Word
  else if Ch.IsWhiteSpace then
    Result := TCharCategory.Space
  else
    Result := TCharCategory.Other;
end;

procedure TMarkdownEditorModel.WrapOrToggle(const Marker: string);
var
  Start: Integer;
  Len: Integer;
  Selected: string;
  MarkerLen: Integer;
  IsWrapped: Boolean;
  Inner: string;
  Wrapped: string;
begin
  Start := SelectionStart;
  Len := SelectionLength;
  Selected := SelectedText;
  MarkerLen := System.Length(Marker);

  IsWrapped := (System.Length(Selected) >= 2 * MarkerLen) and Selected.StartsWith(Marker) and
    Selected.EndsWith(Marker);
  if IsWrapped then
  begin
    Inner := Copy(Selected, MarkerLen + 1, System.Length(Selected) - 2 * MarkerLen);
    ApplyReplace(Start, Len, Inner, False);
    FAnchor := Start;
    FCaret := Start + System.Length(Inner);
    Exit;
  end;

  Wrapped := Marker + Selected + Marker;
  ApplyReplace(Start, Len, Wrapped, False);
  FAnchor := Start + MarkerLen;
  FCaret := Start + MarkerLen + System.Length(Selected);
end;

// Reads what the markdown already says before changing it, so half covering a
// marked word widens it instead of cutting it in two, and running the command
// again on the same words takes the marks back off. Where the text gives
// nothing to read, across a block boundary or inside a table cell, the
// selection is wrapped as it stands.
procedure TMarkdownEditorModel.ToggleInlineStyle(const Style: TMarkdownInlineStyle);
var
  Edit: TMarkdownInlineStyleEdit;
begin
  
  if not TMarkdownInlineStyleNormalizer.TryNormalize(FText, SelectionStart, SelectionLength, Style, Edit) then
  begin
    WrapOrToggle(TMarkdownInlineStyleNormalizer.MarkerOf(Style));
    Exit;
  end;

  ApplyReplace(Edit.Start, Edit.Length, Edit.Replacement, False);

  FAnchor := SnapOffset(Edit.SelectionStart);
  FCaret := SnapOffset(Edit.SelectionStart + Edit.SelectionLength);
end;

procedure TMarkdownEditorModel.InsertLink;
var
  Start: Integer;
  Len: Integer;
  Selected: string;
  UrlPlaceholder: string;
  LinkPrefix: string;
  LinkMarkup: string;
  UrlStart: Integer;
begin
  Start := SelectionStart;
  Len := SelectionLength;
  Selected := SelectedText;
  UrlPlaceholder := 'url';
  LinkPrefix := OpenBracket + Selected + CloseBracket + OpenParen;
  LinkMarkup := LinkPrefix + UrlPlaceholder + CloseParen;

  ApplyReplace(Start, Len, LinkMarkup, False);

  UrlStart := Start + System.Length(LinkPrefix);
  FAnchor := UrlStart;
  FCaret := UrlStart + System.Length(UrlPlaceholder);
end;

procedure TMarkdownEditorModel.WrapCodeBlock;
var
  Start: Integer;
  Len: Integer;
  Selected: string;
  FenceMarker: string;
  Block: string;
begin
  Start := SelectionStart;
  Len := SelectionLength;
  Selected := SelectedText;
  FenceMarker := StringOfChar(Backtick, MinFenceLength);
  Block := FenceMarker + LineFeed + Selected + LineFeed + FenceMarker;

  ApplyReplace(Start, Len, Block, False);
end;

procedure TMarkdownEditorModel.ToggleHeading(const Level: Integer);
var
  RegionStart: Integer;
  RegionLen: Integer;
  Lines: TArray<string>;
  SingleLine: Boolean;
  Prefix: string;
  AllApplied: Boolean;
  HasEligible: Boolean;
  Index: Integer;
  Line: string;
  IsEligible: Boolean;
  Remove: Boolean;
  Existing: Integer;
  NewBlock: type of (string.Join(LineFeed, Lines));
begin
  
  
  
  SelectedLineRegion(RegionStart, RegionLen, Lines, SingleLine);

  Prefix := StringOfChar(HeadingMarkerChar, Level) + SpaceStr;

  AllApplied := True;
  HasEligible := False;
  for Index := 0 to High(Lines) do
  begin
    Line := Lines[Index];
    IsEligible := SingleLine or (Line <> '');
    if not IsEligible then
      Continue;

    HasEligible := True;
    if HeadingPrefixLen(Line) <> System.Length(Prefix) then
    begin
      AllApplied := False;
      Break;
    end;
  end;

  Remove := HasEligible and AllApplied;

  for Index := 0 to High(Lines) do
  begin
    Line := Lines[Index];
    IsEligible := SingleLine or (Line <> '');
    if not IsEligible then
      Continue;

    Existing := HeadingPrefixLen(Line);
    if Existing > 0 then
      Line := Copy(Line, Existing + 1, System.Length(Line) - Existing);

    if not Remove then
      Line := Prefix + Line;

    Lines[Index] := Line;
  end;

  NewBlock := string.Join(LineFeed, Lines);
  ReplaceRegionAndSelect(RegionStart, RegionLen, NewBlock);
end;

procedure TMarkdownEditorModel.ToggleLinePrefix(const Marker: string);
var
  RegionStart: Integer;
  RegionLen: Integer;
  Lines: TArray<string>;
  SingleLine: Boolean;
  MarkerLen: Integer;
  AllApplied: Boolean;
  HasEligible: Boolean;
  Index: Integer;
  Line: string;
  IsEligible: Boolean;
  Remove: Boolean;
  NewBlock: type of (string.Join(LineFeed, Lines));
begin
  
  
  
  SelectedLineRegion(RegionStart, RegionLen, Lines, SingleLine);

  MarkerLen := System.Length(Marker);

  AllApplied := True;
  HasEligible := False;
  for Index := 0 to High(Lines) do
  begin
    Line := Lines[Index];
    IsEligible := SingleLine or (Line <> '');
    if not IsEligible then
      Continue;

    HasEligible := True;
    if not Line.StartsWith(Marker) then
    begin
      AllApplied := False;
      Break;
    end;
  end;

  Remove := HasEligible and AllApplied;

  for Index := 0 to High(Lines) do
  begin
    Line := Lines[Index];
    IsEligible := SingleLine or (Line <> '');
    if not IsEligible then
      Continue;

    if Remove then
    begin
      if Line.StartsWith(Marker) then
        Line := Copy(Line, MarkerLen + 1, System.Length(Line) - MarkerLen);
    end
    else
    begin
      Line := Marker + Line;
    end;

    Lines[Index] := Line;
  end;

  NewBlock := string.Join(LineFeed, Lines);
  ReplaceRegionAndSelect(RegionStart, RegionLen, NewBlock);
end;

procedure TMarkdownEditorModel.ToggleNumberedList;
var
  RegionStart: Integer;
  RegionLen: Integer;
  Lines: TArray<string>;
  SingleLine: Boolean;
  AllApplied: Boolean;
  HasEligible: Boolean;
  Index: Integer;
  Line: string;
  IsEligible: Boolean;
  Remove: Boolean;
  Counter: Integer;
  Existing: Integer;
  NewBlock: type of (string.Join(LineFeed, Lines));
begin
  
  
  
  SelectedLineRegion(RegionStart, RegionLen, Lines, SingleLine);

  AllApplied := True;
  HasEligible := False;
  for Index := 0 to High(Lines) do
  begin
    Line := Lines[Index];
    IsEligible := SingleLine or (Line <> '');
    if not IsEligible then
      Continue;

    HasEligible := True;
    if OrderedPrefixLen(Line) = 0 then
    begin
      AllApplied := False;
      Break;
    end;
  end;

  Remove := HasEligible and AllApplied;

  Counter := 0;
  for Index := 0 to High(Lines) do
  begin
    Line := Lines[Index];
    IsEligible := SingleLine or (Line <> '');
    if not IsEligible then
      Continue;

    Existing := OrderedPrefixLen(Line);
    if Existing > 0 then
      Line := Copy(Line, Existing + 1, System.Length(Line) - Existing);

    if not Remove then
    begin
      Inc(Counter);
      Line := Format(OrderedMarkerFormat, [Counter]) + Line;
    end;

    Lines[Index] := Line;
  end;

  NewBlock := string.Join(LineFeed, Lines);
  ReplaceRegionAndSelect(RegionStart, RegionLen, NewBlock);
end;

procedure TMarkdownEditorModel.InsertTable;
var
  Start: Integer;
  Len: Integer;
  Skeleton: string;
  Lead: string;
  Insertion: string;
begin
  Start := SelectionStart;
  Len := SelectionLength;

  Skeleton := TableHeaderLine + LineFeed + TableDelimiterLine + LineFeed + TableBodyLine + LineFeed +
    TableBodyLine + LineFeed + TableBodyLine;

  Lead := '';
  if Start > 0 then
  begin
    if FText[Start] <> LineFeed then
      Lead := LineFeed + LineFeed
    else if (Start < 2) or (FText[Start - 1] <> LineFeed) then
      Lead := LineFeed;
  end;

  Insertion := Lead + Skeleton + LineFeed;
  ApplyReplace(Start, Len, Insertion, False);
end;

procedure TMarkdownEditorModel.SelectedLineRegion(out RegionStart, RegionLen: Integer; out Lines: TArray<string>;
  out SingleLine: Boolean);
var
  FirstLine: Integer;
  EndOffset: Integer;
  LastLine: Integer;
  RegionEnd: Integer;
begin
  FirstLine := LineIndexOfOffset(SelectionStart);

  EndOffset := SelectionStart + SelectionLength;
  if SelectionLength > 0 then
    Dec(EndOffset);

  LastLine := LineIndexOfOffset(EndOffset);

  RegionStart := OffsetOfLineStart(FirstLine);

  
  if LastLine < LineCount - 1 then
    RegionEnd := OffsetOfLineStart(LastLine + 1) - 1
  else
    RegionEnd := System.Length(FText);

  RegionLen := RegionEnd - RegionStart;

  Lines := Copy(FText, RegionStart + 1, RegionLen).Split([LineFeed]);
  if System.Length(Lines) = 0 then
    Lines := [''];

  SingleLine := (FirstLine = LastLine);
end;

procedure TMarkdownEditorModel.ReplaceRegionAndSelect(const RegionStart, RegionLen: Integer; const NewBlock: string);
begin
  ApplyReplace(RegionStart, RegionLen, NewBlock, False);
  FAnchor := RegionStart;
  FCaret := RegionStart + System.Length(NewBlock);
end;

class function TMarkdownEditorModel.HeadingPrefixLen(const Line: string): Integer;
var
  HashCount: Integer;
  IsHeading: Boolean;
begin
  HashCount := 0;
  while (HashCount < System.Length(Line)) and (Line[HashCount + 1] = HeadingMarkerChar) do
    Inc(HashCount);

  IsHeading := (HashCount >= 1) and (HashCount <= MaxHeadingLevel) and
    (System.Length(Line) > HashCount) and (Line[HashCount + 1] = SpaceStr);
  if IsHeading then
    Result := HashCount + 1
  else
    Result := 0;
end;

class function TMarkdownEditorModel.OrderedPrefixLen(const Line: string): Integer;
var
  DigitCount: Integer;
  IsOrdered: Boolean;
begin
  DigitCount := 0;
  while (DigitCount < System.Length(Line)) and Line[DigitCount + 1].IsDigit do
    Inc(DigitCount);

  IsOrdered := (DigitCount >= 1) and (System.Length(Line) >= DigitCount + 2) and
    (Line[DigitCount + 1] = DotStr) and (Line[DigitCount + 2] = SpaceStr);
  if IsOrdered then
    Result := DigitCount + 2
  else
    Result := 0;
end;

function TMarkdownEditorModel.GetText: string;
begin
  Result := FText;
end;

procedure TMarkdownEditorModel.SetText(const Value: string);
begin
  NormalizeAndLoad(Value);
end;

function TMarkdownEditorModel.GetCaretPosition: Integer;
begin
  Result := FCaret;
end;

procedure TMarkdownEditorModel.SetCaretPosition(const Value: Integer);
var
  Snapped: Integer;
begin
  Snapped := SnapOffset(Value);
  FCaret := Snapped;
  FAnchor := Snapped;
end;

function TMarkdownEditorModel.GetSelectionStart: Integer;
begin
  Result := Min(FCaret, FAnchor);
end;

function TMarkdownEditorModel.GetSelectionLength: Integer;
begin
  Result := Abs(FCaret - FAnchor);
end;

function TMarkdownEditorModel.GetSelectedText: string;
begin
  Result := Copy(FText, SelectionStart + 1, SelectionLength);
end;

function TMarkdownEditorModel.GetOnChange: TEditorChangeEvent;
begin
  Result := FOnChange;
end;

procedure TMarkdownEditorModel.SetOnChange(const Value: TEditorChangeEvent);
begin
  FOnChange := Value;
end;

end.
