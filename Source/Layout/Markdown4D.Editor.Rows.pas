{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Editor.Rows;

{$SCOPEDENUMS ON}

// Soft-wrapping the source into the rows an editor puts on screen. The only
// thing a framework has to supply is how wide a piece of text is, so the
// wrapping itself, the cache in front of it and the lookups between an offset
// and a row live here rather than in each component.

interface

uses
  Generics.Collections,
  Markdown4D.Editor.Model,
  Markdown4D.Compat.Str,
  character;

type
  // One on-screen line from soft-wrapping a source line. Offsets are absolute
  // into the model text and the range excludes the trailing line break.
  TVisualRow = record
    LineIndex: Integer;
    StartOffset: Integer;
    EndOffset: Integer;
    IsFirst: Boolean;
  end;

  // How wide the text is in the font the editor draws its source in.
  TMarkdownRowTextWidth = reference to function(const Text: string): Single;

  TMarkdownEditorRows = class
  private
    type
      // Where one source line wraps, cached per line so an edit only
      // re-measures the line that actually changed instead of the whole
      // document.
      TWrapCacheEntry = record
        Text: string;
        WrapWidth: Single;
        Breaks: TArray<Integer>;
      end;
    var
      FModel: TMarkdownEditorModel;
      FMeasure: TMarkdownRowTextWidth;
      FItems: TArray<TVisualRow>;
      FWrapCache: TArray<TWrapCacheEntry>;
      FWrapWidth: Single;
    procedure AppendWrappedRows(const Rows: TList<TVisualRow>; const LineIndex: Integer);
    function WrapBreaksFor(const LineIndex: Integer; const LineText: string): TArray<Integer>;
    function ComputeWrapBreaks(const LineText: string): TArray<Integer>;
    function NextWrapLength(const LineText: string; const StartCol: Integer): Integer;
    class function LastSpaceWithin(const LineText: string; const StartCol, MaxLength: Integer): Integer; static;
    class function MakeRow(const LineIndex, StartOffset, EndOffset: Integer; const IsFirst: Boolean): TVisualRow; static;

  public
    constructor Create(const Model: TMarkdownEditorModel; const Measure: TMarkdownRowTextWidth);
    procedure Rebuild(const WrapWidth: Single);
    function Count: Integer;
    function TextOf(const Row: TVisualRow): string;
    function IndexOfOffset(const Offset: Integer): Integer;
    // The offset in the row whose left edge sits closest to TargetX.
    function OffsetAtX(const RowIndex: Integer; const TargetX: Single): Integer;
    function LineTextAt(const LineIndex: Integer): string;
    function LineStartOffset(const LineIndex: Integer): Integer;
    property Items: TArray<TVisualRow> read FItems;
  end;

implementation

uses
  Math;

constructor TMarkdownEditorRows.Create(const Model: TMarkdownEditorModel; const Measure: TMarkdownRowTextWidth);
begin
  inherited Create;

  FModel := Model;
  FMeasure := Measure;
end;

procedure TMarkdownEditorRows.Rebuild(const WrapWidth: Single);
var
  Rows: TList<TVisualRow>;
  LineCount: Integer;
  LineIndex: Integer;
begin
  FWrapWidth := WrapWidth;

  Rows := TList<TVisualRow>.Create;
  try
    LineCount := FModel.LineCount;
    if Length(FWrapCache) < LineCount then
      SetLength(FWrapCache, LineCount);

    for LineIndex := 0 to LineCount - 1 do
    begin
      if FModel.IsLineHidden(LineIndex) then
        Continue;

      AppendWrappedRows(Rows, LineIndex);
    end;

    FItems := Rows.ToArray;
  finally
    Rows.Free;
  end;
end;

procedure TMarkdownEditorRows.AppendWrappedRows(const Rows: TList<TVisualRow>; const LineIndex: Integer);
var
  LineText: string;
  LineStart: Integer;
  LineIsEmpty: Boolean;
  Consumed: Integer;
  Index: Integer;
begin
  LineText := LineTextAt(LineIndex);
  LineStart := LineStartOffset(LineIndex);

  LineIsEmpty := (Length(LineText) = 0);
  if LineIsEmpty then
  begin
    Rows.Add(MakeRow(LineIndex, LineStart, LineStart, True));
    Exit;
  end;

  Consumed := 0;
  for Index in WrapBreaksFor(LineIndex, LineText) do
  begin
    Rows.Add(MakeRow(LineIndex, LineStart + Consumed, LineStart + Index, Consumed = 0));
    Consumed := Index;
  end;
end;

function TMarkdownEditorRows.WrapBreaksFor(const LineIndex: Integer; const LineText: string): TArray<Integer>;
var
  Reusable: Boolean;
begin
  Reusable := (LineIndex <= High(FWrapCache)) and (FWrapCache[LineIndex].WrapWidth = FWrapWidth) and
    (FWrapCache[LineIndex].Text = LineText);
  if Reusable then
  begin
    Result := FWrapCache[LineIndex].Breaks;
    Exit;
  end;

  Result := ComputeWrapBreaks(LineText);

  if LineIndex > High(FWrapCache) then
    SetLength(FWrapCache, LineIndex + 1);

  FWrapCache[LineIndex].Text := LineText;
  FWrapCache[LineIndex].WrapWidth := FWrapWidth;
  FWrapCache[LineIndex].Breaks := Result;
end;

function TMarkdownEditorRows.ComputeWrapBreaks(const LineText: string): TArray<Integer>;
var
  Len: Integer;
  Consumed: Integer;
begin
  Result := [];

  Len := Length(LineText);
  Consumed := 0;
  while Consumed < Len do
  begin
    Consumed := Consumed + NextWrapLength(LineText, Consumed);
    Result := Result + [Consumed];
  end;
end;

function TMarkdownEditorRows.NextWrapLength(const LineText: string; const StartCol: Integer): Integer;
var
  Remaining: Integer;
  RemainderWidth: type of (FMeasure(Copy(LineText, StartCol + 1, Remaining)));
  FitsWholeRemainder: Boolean;
  LowerBound: Integer;
  UpperBound: Integer;
  BestFit: Integer;
  Candidate: Integer;
  CandidateWidth: type of (FMeasure(Copy(LineText, StartCol + 1, Candidate)));
  CandidateFits: Boolean;
  WordBreak: Integer;
  CanBreakAtWord: Boolean;
begin
  Remaining := Length(LineText) - StartCol;

  RemainderWidth := FMeasure(Copy(LineText, StartCol + 1, Remaining));
  FitsWholeRemainder := (RemainderWidth <= FWrapWidth);
  if FitsWholeRemainder then
  begin
    Result := Remaining;
    Exit;
  end;

  LowerBound := 1;
  UpperBound := Remaining;
  BestFit := 1;
  while LowerBound <= UpperBound do
  begin
    Candidate := (LowerBound + UpperBound) div 2;
    CandidateWidth := FMeasure(Copy(LineText, StartCol + 1, Candidate));
    CandidateFits := (CandidateWidth <= FWrapWidth);
    if CandidateFits then
    begin
      BestFit := Candidate;
      LowerBound := Candidate + 1;
    end
    else
    begin
      UpperBound := Candidate - 1;
    end;
  end;

  WordBreak := LastSpaceWithin(LineText, StartCol, BestFit);
  CanBreakAtWord := WordBreak > 0;
  if CanBreakAtWord then
    Result := WordBreak
  else
    Result := BestFit;
end;

class function TMarkdownEditorRows.LastSpaceWithin(const LineText: string; const StartCol, MaxLength: Integer): Integer;
var
  Offset: Integer;
  IsSpace: Boolean;
begin
  for Offset := MaxLength downto 1 do
  begin
    IsSpace := (LineText[StartCol + Offset] = ' ');
    if IsSpace then
    begin
      Result := Offset;
      Exit;
    end;
  end;

  Result := 0;
end;

class function TMarkdownEditorRows.MakeRow(const LineIndex, StartOffset, EndOffset: Integer;
  const IsFirst: Boolean): TVisualRow;
begin
  Result.LineIndex := LineIndex;
  Result.StartOffset := StartOffset;
  Result.EndOffset := EndOffset;
  Result.IsFirst := IsFirst;
end;

function TMarkdownEditorRows.Count: Integer;
begin
  Result := Length(FItems);
end;

function TMarkdownEditorRows.TextOf(const Row: TVisualRow): string;
begin
  Result := Copy(FModel.Text, Row.StartOffset + 1, Row.EndOffset - Row.StartOffset);
end;

function TMarkdownEditorRows.IndexOfOffset(const Offset: Integer): Integer;
var
  Index: Integer;
  Row: TVisualRow;
  AtWrapBoundary: Boolean;
begin
  if Length(FItems) = 0 then
  begin
    Result := 0;
    Exit;
  end;

  for Index := 0 to High(FItems) do
  begin
    Row := FItems[Index];
    if Offset <= Row.EndOffset then
    begin
      AtWrapBoundary := (Offset = Row.EndOffset) and (Index < High(FItems)) and
        (FItems[Index + 1].LineIndex = Row.LineIndex);
      if AtWrapBoundary then
      begin
        Result := Index + 1;
        Exit;
      end;

      Result := Index;
      Exit;
    end;
  end;

  Result := High(FItems);
end;

function TMarkdownEditorRows.OffsetAtX(const RowIndex: Integer; const TargetX: Single): Integer;
var
  Row: TVisualRow;
  RowStr: string;
  BestColumn: Integer;
  BestDistance: Single;
  PrefixLength: Integer;
  Width: type of (FMeasure(Copy(RowStr, 1, PrefixLength)));
  Distance: Single;
begin
  if Length(FItems) = 0 then
  begin
    Result := 0;
    Exit;
  end;

  Row := FItems[EnsureRange(RowIndex, 0, High(FItems))];
  RowStr := TextOf(Row);

  BestColumn := 0;
  BestDistance := Abs(TargetX);
  for PrefixLength := 1 to Length(RowStr) do
  begin
    Width := FMeasure(Copy(RowStr, 1, PrefixLength));
    Distance := Abs(TargetX - Width);
    if Distance < BestDistance then
    begin
      BestDistance := Distance;
      BestColumn := PrefixLength;
    end;
  end;

  Result := Row.StartOffset + BestColumn;
end;

function TMarkdownEditorRows.LineTextAt(const LineIndex: Integer): string;
var
  Source: string;
  StartOffset: Integer;
  EndOffset: Integer;
begin
  Source := FModel.Text;
  StartOffset := FModel.OffsetOfLineStart(LineIndex);
  
  if LineIndex < FModel.LineCount - 1 then
    EndOffset := FModel.OffsetOfLineStart(LineIndex + 1) - 1
  else
    EndOffset := Length(Source);

  Result := Copy(Source, StartOffset + 1, EndOffset - StartOffset);
end;

function TMarkdownEditorRows.LineStartOffset(const LineIndex: Integer): Integer;
begin
  Result := FModel.OffsetOfLineStart(LineIndex);
end;

end.
