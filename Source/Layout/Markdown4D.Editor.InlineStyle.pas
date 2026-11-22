{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Editor.InlineStyle;

{$SCOPEDENUMS ON}

// Putting a style on a stretch of markdown, or taking it off, by reading what
// the markdown already says instead of adding another pair of markers. The
// parser answers where the styles, the code spans and the links are, so the
// result holds for text nobody wrote by hand.

interface

uses
  Markdown4D.Ast.Interfaces,
  Markdown4D.Compat.Str;

type
  // Strikethrough is not emphasis in the sense the HTML tags are, but for this
  // command it behaves as one: a symmetric pair of markers around inline text
  // that goes on and off the same way.
  TMarkdownInlineStyle = (Strong, Emphasis, Strikethrough);

  // The one replacement that carries out the command, with where the selection
  // belongs afterwards. Every offset counts from 0, the way the caret does.
  TMarkdownInlineStyleEdit = record
    Start: Integer;
    Length: Integer;
    Replacement: string;
    SelectionStart: Integer;
    SelectionLength: Integer;
  end;

  TMarkdownInlineStyleNormalizer = class
  private
    class function TryTrimRange(const Text: string; const RangeStart, RangeLength: Integer;
                                out Range: TMarkdownSegment): Boolean; static;
    class function TryFindHost(const Document: IMarkdownNode; const Range: TMarkdownSegment;
                               out Host: IMarkdownNode): Boolean; static;
    class function DescendantsOf(const Node: IMarkdownNode): TArray<IMarkdownNode>; static;
    class function AllCarrySource(const Nodes: TArray<IMarkdownNode>): Boolean; static;
    class function IsTargetNode(const Node: IMarkdownNode; const Style: TMarkdownInlineStyle): Boolean; static;
    class function IsStrikethrough(const Node: IMarkdownNode): Boolean; static;
    class function IsKeptWhole(const Kind: TMarkdownNodeKind): Boolean; static;
    class function HoldsStyledTextInside(const Kind: TMarkdownNodeKind): Boolean; static;
    class function ContentSpanOf(const Node: IMarkdownNode): TMarkdownSegment; static;
    class function Overlaps(const Left, Right: TMarkdownSegment): Boolean; static;
    class function Covers(const Outer, Inner: TMarkdownSegment): Boolean; static;
    class function Joined(const Left, Right: TMarkdownSegment): TMarkdownSegment; static;
    class function CoveredByAny(const Spans: TArray<TMarkdownSegment>; const Position: Integer): Boolean; static;
    class function WithoutSplitEscapes(const Text: string; const Range: TMarkdownSegment): TMarkdownSegment; static;
    class function StartsAnEscape(const Text: string; const Index: Integer): Boolean; static;
    class function WidenedOverWholeNodes(const Nodes: TArray<IMarkdownNode>; const Style: TMarkdownInlineStyle;
                                         const Range: TMarkdownSegment): TMarkdownSegment; static;
    class function TargetsOverlapping(const Nodes: TArray<IMarkdownNode>; const Style: TMarkdownInlineStyle;
                                      const Range: TMarkdownSegment): TArray<IMarkdownNode>; static;
    class function SpanOverAll(const Range: TMarkdownSegment;
                               const Targets: TArray<IMarkdownNode>): TMarkdownSegment; static;
    class function MarkersOf(const Targets: TArray<IMarkdownNode>): TArray<TMarkdownSegment>; static;
    class function ContentsOf(const Targets: TArray<IMarkdownNode>): TArray<TMarkdownSegment>; static;
    class function MarkerFlags(const Affected: TMarkdownSegment;
                               const Markers: TArray<TMarkdownSegment>): TArray<Boolean>; static;
    class function StyledFlags(const Range, Affected: TMarkdownSegment;
                                 const Contents: TArray<TMarkdownSegment>;
                                 const IsTakingOff: Boolean): TArray<Boolean>; static;
    class function IsTakingOff(const Range: TMarkdownSegment;
                               const Markers, Contents: TArray<TMarkdownSegment>): Boolean; static;
    class function WithoutWhitespaceEdges(const Text: string; const Affected: TMarkdownSegment;
                                          const IsMarker, Styled: TArray<Boolean>): TArray<Boolean>; static;
    class function EditFor(const Text: string; const Range, Affected: TMarkdownSegment;
                           const IsMarker, Styled: TArray<Boolean>;
                           const Marker: string): TMarkdownInlineStyleEdit; static;

  public
    // Answers the replacement that makes the whole range carry Style, or, when
    // the range already carries it throughout, the one that takes it off. Marks
    // of the same style that the range only half covers are taken in rather
    // than cut through, and a range that would end inside a code span, a link
    // or a formula is widened to take that whole thing in.
    //
    // False when the range is not one stretch of inline text: across a block
    // boundary, inside a code block, or somewhere that carries no source
    // offsets of its own, such as a table cell.
    class function TryNormalize(const Text: string; const RangeStart, RangeLength: Integer;
                                const Style: TMarkdownInlineStyle;
                                out Edit: TMarkdownInlineStyleEdit): Boolean; static;
    // How the style is spelled in markdown.
    class function MarkerOf(const Style: TMarkdownInlineStyle): string; static;
  end;

implementation

uses
  SysUtils,
  character,
  Markdown4D,
  Markdown4D.Defines,
  Markdown4D.Parser.Inlines,
  Markdown4D.Text.Unescape;

class function TMarkdownInlineStyleNormalizer.TryNormalize(const Text: string;
  const RangeStart, RangeLength: Integer; const Style: TMarkdownInlineStyle;
  out Edit: TMarkdownInlineStyleEdit): Boolean;
var
  Range: TMarkdownSegment;
  Document: IMarkdownDocument;
  Host: IMarkdownNode;
  Inlines: TArray<IMarkdownNode>;
  Whole: TMarkdownSegment;
  Widened: TMarkdownSegment;
  Targets: TArray<IMarkdownNode>;
  Affected: TMarkdownSegment;
  Markers: TArray<TMarkdownSegment>;
  Contents: type of (ContentsOf(Targets));
  TakingOff: Boolean;
  IsMarker: TArray<Boolean>;
  Styled: TArray<Boolean>;
  Trimmed: TArray<Boolean>;
begin
  Edit := Default(TMarkdownInlineStyleEdit);
  Result := False;

  
  if not TryTrimRange(Text, RangeStart, RangeLength, Range) then
    Exit;

  Document := TMarkdown.Parse(Text, TMarkdownDialect.Gfm);

  
  if not TryFindHost(Document, Range, Host) then
    Exit;

  Inlines := DescendantsOf(Host);
  if not AllCarrySource(Inlines) then
    Exit;

  Whole := WithoutSplitEscapes(Text, Range);
  Widened := WidenedOverWholeNodes(Inlines, Style, Whole);
  Targets := TargetsOverlapping(Inlines, Style, Widened);

  Affected := SpanOverAll(Widened, Targets);
  Markers := MarkersOf(Targets);
  Contents := ContentsOf(Targets);

  TakingOff := IsTakingOff(Widened, Markers, Contents);
  IsMarker := MarkerFlags(Affected, Markers);
  Styled := StyledFlags(Widened, Affected, Contents, TakingOff);
  Trimmed := WithoutWhitespaceEdges(Text, Affected, IsMarker, Styled);

  Edit := EditFor(Text, Widened, Affected, IsMarker, Trimmed, MarkerOf(Style));
  Result := True;
end;

// Markers standing against the whitespace inside them read as ordinary
// characters, so the range is pulled in to the text it really covers.
class function TMarkdownInlineStyleNormalizer.MarkerOf(const Style: TMarkdownInlineStyle): string;
begin
  case Style of
    TMarkdownInlineStyle.Strong        : Result := Asterisk + Asterisk;
    TMarkdownInlineStyle.Emphasis      : Result := Asterisk;
    TMarkdownInlineStyle.Strikethrough : Result := Tilde + Tilde;
  else
    raise ENotSupportedException.CreateFmt('Unsupported inline style: %d', [Ord(Style)]);
  end;
end;

class function TMarkdownInlineStyleNormalizer.TryTrimRange(const Text: string;
  const RangeStart, RangeLength: Integer; out Range: TMarkdownSegment): Boolean;
var
  Limit: Integer;
  First: Integer;
  Last: Integer;
begin
  Range := Default(TMarkdownSegment);

  Limit := System.Length(Text) + 1;

  First := RangeStart + 1;
  Last := RangeStart + RangeLength + 1;

  if First < 1 then
    First := 1;
  if Last > Limit then
    Last := Limit;

  while (First < Last) and Text[First].IsWhiteSpace do
  begin
    Inc(First);
  end;

  while (Last > First) and Text[Last - 1].IsWhiteSpace do
  begin
    Dec(Last);
  end;

  Range := TMarkdownSegment.Create(First, Last);
  Result := (Last > First);
end;

// A style lives inside one paragraph or heading; a range that does not sit in
// one of them has no single stretch of inline text to work on.
class function TMarkdownInlineStyleNormalizer.TryFindHost(const Document: IMarkdownNode;
  const Range: TMarkdownSegment; out Host: IMarkdownNode): Boolean;
var
  Pending: TArray<IMarkdownNode>;
  Node: IMarkdownNode;
  IsInlineHost: Boolean;
  Index: Integer;
begin
  Host := nil;

  Pending := [Document];

  while System.Length(Pending) > 0 do
  begin
    Node := Pending[High(Pending)];
    SetLength(Pending, System.Length(Pending) - 1);

    IsInlineHost := (Node.Kind = TMarkdownNodeKind.Paragraph) or (Node.Kind = TMarkdownNodeKind.Heading);
    if IsInlineHost and Covers(Node.Segment, Range) then
    begin
      Host := Node;
      Result := True;
      Exit;
    end;

    for Index := 0 to Node.ChildCount - 1 do
    begin
      Pending := Pending + [Node.Children[Index]];
    end;
  end;

  Result := False;
end;

class function TMarkdownInlineStyleNormalizer.DescendantsOf(const Node: IMarkdownNode): TArray<IMarkdownNode>;
var
  Pending: TArray<IMarkdownNode>;
  Current: IMarkdownNode;
  Index: Integer;
  Child: IMarkdownNode;
begin
  Result := [];

  Pending := [Node];

  while System.Length(Pending) > 0 do
  begin
    Current := Pending[High(Pending)];
    SetLength(Pending, System.Length(Pending) - 1);

    for Index := 0 to Current.ChildCount - 1 do
    begin
      Child := Current.Children[Index];
      Result := Result + [Child];
      Pending := Pending + [Child];
    end;
  end;
end;

// A node an extension built, or one inside a table cell, says nothing about
// where it came from. Moving markers around it would be guesswork.
class function TMarkdownInlineStyleNormalizer.AllCarrySource(const Nodes: TArray<IMarkdownNode>): Boolean;
var
  Node: IMarkdownNode;
  HasSource: Boolean;
begin
  for Node in Nodes do
  begin
    HasSource := (Node.Segment.StartOffset > 0) and (Node.Segment.EndOffset >= Node.Segment.StartOffset);
    if not HasSource then
    begin
      Result := False;
      Exit;
    end;
  end;

  Result := True;
end;

// Bold and italic are node kinds of their own; strikethrough is not.
class function TMarkdownInlineStyleNormalizer.IsTargetNode(const Node: IMarkdownNode;
  const Style: TMarkdownInlineStyle): Boolean;
begin
  case Style of
    TMarkdownInlineStyle.Strong        : Result := (Node.Kind = TMarkdownNodeKind.Strong);
    TMarkdownInlineStyle.Emphasis      : Result := (Node.Kind = TMarkdownNodeKind.Emphasis);
    TMarkdownInlineStyle.Strikethrough : Result := IsStrikethrough(Node);
  else
    raise ENotSupportedException.CreateFmt('Unsupported inline style: %d', [Ord(Style)]);
  end;
end;

// The GFM extension registers strikethrough under a name, and the renderer, the
// builder and the markdown writer all pick the node out by that same name. This
// follows them rather than inventing a second way to spell it.
class function TMarkdownInlineStyleNormalizer.IsStrikethrough(const Node: IMarkdownNode): Boolean;
var
  Custom: IMarkdownCustomInline;
begin
  
  if not Supports(Node, IMarkdownCustomInline, Custom) then
  begin
    Result := False;
    Exit;
  end;

  Result := (Custom.NodeName = TGfmInlineParser.StrikethroughNodeName);
end;

// Things a marker may not be dropped into: their source spells something other
// than the text it shows.
class function TMarkdownInlineStyleNormalizer.IsKeptWhole(const Kind: TMarkdownNodeKind): Boolean;
begin
  Result := (Kind = TMarkdownNodeKind.CodeSpan) or (Kind = TMarkdownNodeKind.Math) or
    (Kind = TMarkdownNodeKind.InlineHtml) or (Kind = TMarkdownNodeKind.Autolink) or
    (Kind = TMarkdownNodeKind.Link) or (Kind = TMarkdownNodeKind.Image) or
    (Kind = TMarkdownNodeKind.CustomInline) or (Kind = TMarkdownNodeKind.Emphasis) or
    (Kind = TMarkdownNodeKind.Strong);
end;

// A link label and the text inside a style take a style of their own, so a
// range that stays within one of those leaves the node alone.
class function TMarkdownInlineStyleNormalizer.HoldsStyledTextInside(const Kind: TMarkdownNodeKind): Boolean;
begin
  Result := (Kind = TMarkdownNodeKind.Link) or (Kind = TMarkdownNodeKind.Image) or
    (Kind = TMarkdownNodeKind.CustomInline) or (Kind = TMarkdownNodeKind.Emphasis) or
    (Kind = TMarkdownNodeKind.Strong);
end;

// What sits between the markers: from the first child to the last one.
class function TMarkdownInlineStyleNormalizer.ContentSpanOf(const Node: IMarkdownNode): TMarkdownSegment;
var
  HasChildren: Boolean;
  First: TMarkdownSegment;
  Last: TMarkdownSegment;
begin
  HasChildren := (Node.ChildCount > 0);
  if not HasChildren then
  begin
    Result := Node.Segment;
    Exit;
  end;

  First := Node.Children[0].Segment;
  Last := Node.Children[Node.ChildCount - 1].Segment;

  Result := TMarkdownSegment.Create(First.StartOffset, Last.EndOffset);
end;

class function TMarkdownInlineStyleNormalizer.Overlaps(const Left, Right: TMarkdownSegment): Boolean;
begin
  Result := (Left.StartOffset < Right.EndOffset) and (Right.StartOffset < Left.EndOffset);
end;

class function TMarkdownInlineStyleNormalizer.Covers(const Outer, Inner: TMarkdownSegment): Boolean;
begin
  Result := (Outer.StartOffset <= Inner.StartOffset) and (Outer.EndOffset >= Inner.EndOffset);
end;

class function TMarkdownInlineStyleNormalizer.Joined(const Left, Right: TMarkdownSegment): TMarkdownSegment;
var
  First: Integer;
  Last: Integer;
begin
  First := Left.StartOffset;
  if Right.StartOffset < First then
    First := Right.StartOffset;

  Last := Left.EndOffset;
  if Right.EndOffset > Last then
    Last := Right.EndOffset;

  Result := TMarkdownSegment.Create(First, Last);
end;

class function TMarkdownInlineStyleNormalizer.CoveredByAny(const Spans: TArray<TMarkdownSegment>;
  const Position: Integer): Boolean;
var
  Span: TMarkdownSegment;
  IsInside: Boolean;
begin
  for Span in Spans do
  begin
    IsInside := (Position >= Span.StartOffset) and (Position < Span.EndOffset);
    if IsInside then
    begin
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

// A marker dropped between a backslash and the character it protects would be
// escaped itself, so an end that splits an escape steps past it.
class function TMarkdownInlineStyleNormalizer.WithoutSplitEscapes(const Text: string;
  const Range: TMarkdownSegment): TMarkdownSegment;
var
  First: Integer;
  Last: Integer;
begin
  First := Range.StartOffset;
  Last := Range.EndOffset;

  if StartsAnEscape(Text, First - 1) then
    Dec(First);

  if StartsAnEscape(Text, Last - 1) then
    Inc(Last);

  Result := TMarkdownSegment.Create(First, Last);
end;

class function TMarkdownInlineStyleNormalizer.StartsAnEscape(const Text: string; const Index: Integer): Boolean;
var
  IsBackslash: Boolean;
  Run: Integer;
begin
  IsBackslash := (Index >= 1) and (Index < System.Length(Text)) and (Text[Index] = Backslash);
  if not IsBackslash then
  begin
    Result := False;
    Exit;
  end;

  if not TMarkdownUnescape.IsAsciiPunctuation(Text[Index + 1]) then
  begin
    Result := False;
    Exit;
  end;

  Run := 0;
  while (Index - Run >= 1) and (Text[Index - Run] = Backslash) do
  begin
    Inc(Run);
  end;

  Result := Odd(Run);
end;

// A range that ends inside something the parser reads as one piece takes that
// whole piece in, so the markers land outside it.
class function TMarkdownInlineStyleNormalizer.WidenedOverWholeNodes(const Nodes: TArray<IMarkdownNode>;
  const Style: TMarkdownInlineStyle; const Range: TMarkdownSegment): TMarkdownSegment;
var
  Grew: Boolean;
  Node: IMarkdownNode;
  Content: TMarkdownSegment;
  StaysInside: Boolean;
begin
  Result := Range;

  Grew := True;

  while Grew do
  begin
    Grew := False;

    for Node in Nodes do
    begin
      if IsTargetNode(Node, Style) then
        Continue;

      if not IsKeptWhole(Node.Kind) then
        Continue;

      if not Overlaps(Node.Segment, Result) then
        Continue;

      if Covers(Result, Node.Segment) then
        Continue;

      Content := ContentSpanOf(Node);
      StaysInside := HoldsStyledTextInside(Node.Kind) and Covers(Content, Result);
      if StaysInside then
        Continue;

      Result := Joined(Result, Node.Segment);
      Grew := True;
    end;
  end;
end;

class function TMarkdownInlineStyleNormalizer.TargetsOverlapping(const Nodes: TArray<IMarkdownNode>;
  const Style: TMarkdownInlineStyle; const Range: TMarkdownSegment): TArray<IMarkdownNode>;
var
  Node: IMarkdownNode;
  IsTarget: Boolean;
begin
  Result := [];

  for Node in Nodes do
  begin
    IsTarget := IsTargetNode(Node, Style) and Overlaps(Node.Segment, Range);
    if IsTarget then
      Result := Result + [Node];
  end;
end;

class function TMarkdownInlineStyleNormalizer.SpanOverAll(const Range: TMarkdownSegment;
  const Targets: TArray<IMarkdownNode>): TMarkdownSegment;
var
  Target: IMarkdownNode;
begin
  Result := Range;

  for Target in Targets do
  begin
    Result := Joined(Result, Target.Segment);
  end;
end;

// The characters that open and close each of the pairs about to be rewritten.
class function TMarkdownInlineStyleNormalizer.MarkersOf(
  const Targets: TArray<IMarkdownNode>): TArray<TMarkdownSegment>;
var
  Target: IMarkdownNode;
  Content: TMarkdownSegment;
  Opening: TMarkdownSegment;
  Closing: TMarkdownSegment;
begin
  Result := [];

  for Target in Targets do
  begin
    Content := ContentSpanOf(Target);
    Opening := TMarkdownSegment.Create(Target.Segment.StartOffset, Content.StartOffset);
    Closing := TMarkdownSegment.Create(Content.EndOffset, Target.Segment.EndOffset);

    Result := Result + [Opening] + [Closing];
  end;
end;

class function TMarkdownInlineStyleNormalizer.ContentsOf(
  const Targets: TArray<IMarkdownNode>): TArray<TMarkdownSegment>;
var
  Target: IMarkdownNode;
begin
  Result := [];

  for Target in Targets do
  begin
    Result := Result + [ContentSpanOf(Target)];
  end;
end;

class function TMarkdownInlineStyleNormalizer.MarkerFlags(const Affected: TMarkdownSegment;
  const Markers: TArray<TMarkdownSegment>): TArray<Boolean>;
var
  Index: Integer;
begin
  SetLength(Result, Affected.Length);

  for Index := 0 to High(Result) do
  begin
    Result[Index] := CoveredByAny(Markers, Affected.StartOffset + Index);
  end;
end;

// Taking the style off leaves it on what the range did not cover; putting it
// on adds the range to what already carried it.
class function TMarkdownInlineStyleNormalizer.StyledFlags(const Range, Affected: TMarkdownSegment;
  const Contents: TArray<TMarkdownSegment>; const IsTakingOff: Boolean): TArray<Boolean>;
var
  Index: Integer;
  Position: Integer;
  WasStyled: Boolean;
  IsInRange: Boolean;
begin
  SetLength(Result, Affected.Length);

  for Index := 0 to High(Result) do
  begin
    Position := Affected.StartOffset + Index;
    WasStyled := CoveredByAny(Contents, Position);
    IsInRange := (Position >= Range.StartOffset) and (Position < Range.EndOffset);

    if IsTakingOff then
      Result[Index] := WasStyled and not IsInRange
    else
      Result[Index] := WasStyled or IsInRange;
  end;
end;

// The command takes the style off when every character it was pointed at
// already carries it, and puts it on otherwise.
class function TMarkdownInlineStyleNormalizer.IsTakingOff(const Range: TMarkdownSegment;
  const Markers, Contents: TArray<TMarkdownSegment>): Boolean;
var
  Seen: Integer;
  Position: Integer;
begin
  Seen := 0;

  for Position := Range.StartOffset to Range.EndOffset - 1 do
  begin
    if CoveredByAny(Markers, Position) then
      Continue;

    Inc(Seen);

    if not CoveredByAny(Contents, Position) then
    begin
      Result := False;
      Exit;
    end;
  end;

  Result := (Seen > 0);
end;

// Markers may not stand against the whitespace they would enclose, so the
// whitespace at either end of a stretch stays outside them. Markers of the
// style being changed are about to go, so they do not break a stretch in two.
class function TMarkdownInlineStyleNormalizer.WithoutWhitespaceEdges(const Text: string;
  const Affected: TMarkdownSegment; const IsMarker, Styled: TArray<Boolean>): TArray<Boolean>;
var
  RunStart: Integer;
  RunEnd: Integer;
  Index: Integer;
  IsPastEnd: Boolean;
  Continues: Boolean;
begin
  Result := Copy(Styled);

  RunStart := -1;
  RunEnd := -1;

  for Index := 0 to System.Length(Result) do
  begin
    IsPastEnd := (Index = System.Length(Result));
    Continues := (not IsPastEnd) and (IsMarker[Index] or Result[Index]);

    if Continues then
    begin
      if not IsMarker[Index] then
      begin
        if RunStart < 0 then
          RunStart := Index;

        RunEnd := Index;
      end;

      Continue;
    end;

    while (RunStart >= 0) and (RunStart <= RunEnd) and Text[Affected.StartOffset + RunStart].IsWhiteSpace do
    begin
      Result[RunStart] := False;
      Inc(RunStart);
    end;

    while (RunStart >= 0) and (RunEnd >= RunStart) and Text[Affected.StartOffset + RunEnd].IsWhiteSpace do
    begin
      Result[RunEnd] := False;
      Dec(RunEnd);
    end;

    RunStart := -1;
    RunEnd := -1;
  end;
end;

class function TMarkdownInlineStyleNormalizer.EditFor(const Text: string; const Range, Affected: TMarkdownSegment;
  const IsMarker, Styled: TArray<Boolean>; const Marker: string): TMarkdownInlineStyleEdit;
var
  Builder: TStringBuilder;
  IsOpen: Boolean;
  SelectionFrom: Integer;
  SelectionTo: Integer;
  Index: Integer;
  Position: Integer;
  IsInRange: Boolean;
begin
  Result := Default(TMarkdownInlineStyleEdit);
  Result.Start := Affected.StartOffset - 1;
  Result.Length := Affected.Length;

  Builder := TStringBuilder.Create;
  try
    IsOpen := False;
    SelectionFrom := -1;
    SelectionTo := 0;

    for Index := 0 to System.Length(Styled) - 1 do
    begin
      if IsMarker[Index] then
        Continue;

      if Styled[Index] <> IsOpen then
      begin
        Builder.Append(Marker);
        IsOpen := Styled[Index];
      end;

      Position := Affected.StartOffset + Index;
      IsInRange := (Position >= Range.StartOffset) and (Position < Range.EndOffset);

      if IsInRange and (SelectionFrom < 0) then
        SelectionFrom := Builder.Length;

      Builder.Append(Text[Position]);

      if IsInRange then
        SelectionTo := Builder.Length;
    end;

    if IsOpen then
      Builder.Append(Marker);

    Result.Replacement := Builder.ToString;

    if SelectionFrom < 0 then
      SelectionFrom := 0;

    Result.SelectionStart := Result.Start + SelectionFrom;
    Result.SelectionLength := SelectionTo - SelectionFrom;
  finally
    Builder.Free;
  end;
end;

end.
