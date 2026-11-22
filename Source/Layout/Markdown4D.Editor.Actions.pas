{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Editor.Actions;

{$SCOPEDENUMS ON}

// Editing behaviour that is about the text, not about the screen: block indent,
// block outdent and the line break that continues what the current line started.
// Framework-neutral by construction, so every host editor behaves the same.

interface

uses
  Markdown4D.Editor.Model,
  Markdown4D.Compat.Str;

type
  TMarkdownEditorActions = record
  strict private
    class function LineTextAt(const Model: TMarkdownEditorModel; const LineIndex: Integer): string; static;
    class function LineEndOffset(const Model: TMarkdownEditorModel; const LineIndex: Integer): Integer; static;
    class procedure ReplaceLines(const Model: TMarkdownEditorModel; const FirstLine, LastLine: Integer;
      const Lines: TArray<string>); static;
    class function LeadingWhitespace(const Line: string): string; static;
    class function ListContinuation(const Line: string; out MarkerLength: Integer): string; static;
    class function BulletContinuation(const Line: string; const IndentLength: Integer;
      out MarkerLength: Integer): string; static;
    class function OrderedContinuation(const Line: string; const IndentLength: Integer;
      out MarkerLength: Integer): string; static;
    class function QuoteContinuation(const Line: string; const IndentLength: Integer;
      out MarkerLength: Integer): string; static;
    class function IsBlankAfter(const Line: string; const Offset: Integer): Boolean; static;
    class function OutdentedLine(const Line: string; const IndentWidth: Integer): string; static;
  public
    // Shifts every line the selection touches one indent step. A selection that
    // stays within one line is replaced by the indent, the way a plain editor
    // treats Tab.
    class procedure Indent(const Model: TMarkdownEditorModel; const IndentWidth: Integer); static;
    class procedure Outdent(const Model: TMarkdownEditorModel; const IndentWidth: Integer); static;
    // Enter that keeps the shape of the current line: its indent, and its list
    // or quote marker. An empty list item is cleared instead of continued.
    class procedure InsertLineBreak(const Model: TMarkdownEditorModel); static;
  end;

implementation

uses
  SysUtils,
  Math,
  character,
  Generics.Collections,
  Markdown4D.Defines;

const
  BulletMarkers = ['-', '*', '+'];
  OrderedSuffixes = ['.', ')'];
  TaskOpen = '[ ] ';
  TaskDone = '[x] ';
  QuoteMarker = '>';

class procedure TMarkdownEditorActions.Indent(const Model: TMarkdownEditorModel; const IndentWidth: Integer);
var
  Step: string;
  SelectionEnd: Integer;
  FirstLine: Integer;
  LastLine: Integer;
  SingleLine: Boolean;
  Lines: TList<string>;
  LineIndex: Integer;
begin
  Step := StringOfChar(Space, Max(IndentWidth, 1));

  SelectionEnd := Model.SelectionStart + Model.SelectionLength;
  FirstLine := Model.LineIndexOfOffset(Model.SelectionStart);
  LastLine := Model.LineIndexOfOffset(Max(SelectionEnd - 1, Model.SelectionStart));

  SingleLine := FirstLine = LastLine;
  if SingleLine then
  begin
    Model.Insert(Step);
    Exit;
  end;

  // A selection can span the whole document, so a TList avoids the O(n^2)
  // cost of growing an array one line at a time.
  Lines := TList<string>.Create;
  try
    for LineIndex := FirstLine to LastLine do
    begin
      Lines.Add(Step + LineTextAt(Model, LineIndex));
    end;

    ReplaceLines(Model, FirstLine, LastLine, Lines.ToArray);
  finally
    Lines.Free;
  end;
end;

class procedure TMarkdownEditorActions.Outdent(const Model: TMarkdownEditorModel; const IndentWidth: Integer);
var
  SelectionEnd: Integer;
  FirstLine: Integer;
  LastLine: Integer;
  Lines: TList<string>;
  Changed: Boolean;
  LineIndex: Integer;
  Original: string;
  Shortened: string;
begin
  SelectionEnd := Model.SelectionStart + Model.SelectionLength;
  FirstLine := Model.LineIndexOfOffset(Model.SelectionStart);
  LastLine := Model.LineIndexOfOffset(Max(SelectionEnd - 1, Model.SelectionStart));

  // A selection can span the whole document, so a TList avoids the O(n^2)
  // cost of growing an array one line at a time.
  Lines := TList<string>.Create;
  try
    Changed := False;

    for LineIndex := FirstLine to LastLine do
    begin
      Original := LineTextAt(Model, LineIndex);
      Shortened := OutdentedLine(Original, Max(IndentWidth, 1));

      Changed := Changed or (Shortened <> Original);
      Lines.Add(Shortened);
    end;

    if not Changed then
      Exit;

    ReplaceLines(Model, FirstLine, LastLine, Lines.ToArray);
  finally
    Lines.Free;
  end;
end;

class procedure TMarkdownEditorActions.InsertLineBreak(const Model: TMarkdownEditorModel);
var
  Caret: Integer;
  LineIndex: Integer;
  LineStart: Integer;
  Line: string;
  CaretColumn: Integer;
  MarkerLength: Integer;
  Continuation: string;
  OnEmptyItem: Boolean;
  Prefix: string;
begin
  Caret := Model.SelectionStart;
  LineIndex := Model.LineIndexOfOffset(Caret);
  LineStart := Model.OffsetOfLineStart(LineIndex);
  Line := LineTextAt(Model, LineIndex);
  CaretColumn := Caret - LineStart;

  MarkerLength := 0;
  Continuation := ListContinuation(Line, MarkerLength);

  // An empty list item means the user is done with the list: Enter wipes the
  // marker instead of producing another one.
  OnEmptyItem := (MarkerLength > 0) and (CaretColumn >= MarkerLength) and IsBlankAfter(Line, MarkerLength);
  if OnEmptyItem then
  begin
    Model.SetSelection(LineStart, Length(Line));
    Model.Insert(LineFeed);
    Exit;
  end;

  Prefix := Copy(Continuation, 1, Min(Length(Continuation), Max(CaretColumn, 0)));
  Model.Insert(LineFeed + Prefix);
end;

class function TMarkdownEditorActions.LineTextAt(const Model: TMarkdownEditorModel;
  const LineIndex: Integer): string;
var
  StartOffset: Integer;
begin
  StartOffset := Model.OffsetOfLineStart(LineIndex);
  Result := Copy(Model.Text, StartOffset + 1, LineEndOffset(Model, LineIndex) - StartOffset);
end;

class function TMarkdownEditorActions.LineEndOffset(const Model: TMarkdownEditorModel;
  const LineIndex: Integer): Integer;
begin
  if LineIndex < Model.LineCount - 1 then
  begin
    Result := Model.OffsetOfLineStart(LineIndex + 1) - 1;
    Exit;
  end;

  Result := Length(Model.Text);
end;

class procedure TMarkdownEditorActions.ReplaceLines(const Model: TMarkdownEditorModel;
  const FirstLine, LastLine: Integer; const Lines: TArray<string>);
var
  RegionStart: Integer;
  RegionEnd: Integer;
  Block: type of (string.Join(LineFeed, Lines));
begin
  RegionStart := Model.OffsetOfLineStart(FirstLine);
  RegionEnd := LineEndOffset(Model, LastLine);
  Block := string.Join(LineFeed, Lines);

  Model.ReplaceRange(RegionStart, RegionEnd - RegionStart, Block);
  Model.SetSelection(RegionStart, Length(Block));
end;

class function TMarkdownEditorActions.LeadingWhitespace(const Line: string): string;
var
  Count: Integer;
begin
  Count := 0;
  while (Count < Length(Line)) and ((Line[Count + 1] = Space) or (Line[Count + 1] = Tab)) do
    Inc(Count);

  Result := Copy(Line, 1, Count);
end;

class function TMarkdownEditorActions.ListContinuation(const Line: string; out MarkerLength: Integer): string;
var
  Indent: string;
  IndentLength: Integer;
begin
  Indent := LeadingWhitespace(Line);
  IndentLength := Length(Indent);

  Result := BulletContinuation(Line, IndentLength, MarkerLength);
  if MarkerLength > 0 then
    Exit;

  Result := OrderedContinuation(Line, IndentLength, MarkerLength);
  if MarkerLength > 0 then
    Exit;

  Result := QuoteContinuation(Line, IndentLength, MarkerLength);
  if MarkerLength > 0 then
    Exit;

  MarkerLength := 0;
  Result := Indent;
end;

class function TMarkdownEditorActions.BulletContinuation(const Line: string; const IndentLength: Integer;
  out MarkerLength: Integer): string;
var
  HasMarker: Boolean;
  Marker: string;
  Rest: string;
  IsTask: Boolean;
begin
  MarkerLength := 0;
  Result := '';

  HasMarker := (Length(Line) > IndentLength + 1) and CharInSet(Line[IndentLength + 1], BulletMarkers) and
    (Line[IndentLength + 2] = Space);
  if not HasMarker then
    Exit;

  Marker := Copy(Line, IndentLength + 1, 2);
  MarkerLength := IndentLength + 2;

  Rest := Copy(Line, MarkerLength + 1, Length(Line) - MarkerLength);
  IsTask := Rest.StartsWith(TaskOpen) or Rest.StartsWith(TaskDone);
  if IsTask then
  begin
    Marker := Marker + TaskOpen;
    MarkerLength := MarkerLength + Length(TaskOpen);
  end;

  Result := Copy(Line, 1, IndentLength) + Marker;
end;

class function TMarkdownEditorActions.OrderedContinuation(const Line: string; const IndentLength: Integer;
  out MarkerLength: Integer): string;
var
  DigitCount: Integer;
  HasMarker: Boolean;
  Number: type of (StrToInt64Def(Copy(Line, IndentLength + 1, DigitCount), 0));
  Suffix: Char;
begin
  MarkerLength := 0;
  Result := '';

  DigitCount := 0;
  while (IndentLength + DigitCount < Length(Line)) and Line[IndentLength + DigitCount + 1].IsDigit do
    Inc(DigitCount);

  HasMarker := (DigitCount > 0) and (Length(Line) > IndentLength + DigitCount + 1) and
    CharInSet(Line[IndentLength + DigitCount + 1], OrderedSuffixes) and
    (Line[IndentLength + DigitCount + 2] = Space);
  if not HasMarker then
    Exit;

  Number := StrToInt64Def(Copy(Line, IndentLength + 1, DigitCount), 0);
  Suffix := Line[IndentLength + DigitCount + 1];

  MarkerLength := IndentLength + DigitCount + 2;
  Result := Copy(Line, 1, IndentLength) + IntToStr(Number + 1) + Suffix + Space;
end;

class function TMarkdownEditorActions.QuoteContinuation(const Line: string; const IndentLength: Integer;
  out MarkerLength: Integer): string;
var
  MarkerCount: Integer;
  FollowedBySpace: Boolean;
begin
  MarkerLength := 0;
  Result := '';

  MarkerCount := 0;
  while (IndentLength + MarkerCount < Length(Line)) and (Line[IndentLength + MarkerCount + 1] = QuoteMarker) do
    Inc(MarkerCount);

  if MarkerCount = 0 then
    Exit;

  MarkerLength := IndentLength + MarkerCount;

  FollowedBySpace := (Length(Line) > MarkerLength) and (Line[MarkerLength + 1] = Space);
  if FollowedBySpace then
    Inc(MarkerLength);

  Result := Copy(Line, 1, MarkerLength);
end;

class function TMarkdownEditorActions.IsBlankAfter(const Line: string; const Offset: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := Offset + 1 to Length(Line) do
  begin
    if not Line[Index].IsWhiteSpace then
    begin
      Result := False;
      Exit;
    end;
  end;

  Result := True;
end;

class function TMarkdownEditorActions.OutdentedLine(const Line: string; const IndentWidth: Integer): string;
var
  Removable: Integer;
begin
  if Line.StartsWith(Tab) then
  begin
    Result := Copy(Line, 2, Length(Line) - 1);
    Exit;
  end;

  Removable := 0;
  while (Removable < IndentWidth) and (Removable < Length(Line)) and (Line[Removable + 1] = Space) do
    Inc(Removable);

  Result := Copy(Line, Removable + 1, Length(Line) - Removable);
end;

end.
