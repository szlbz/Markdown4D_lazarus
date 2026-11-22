{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Layout.Disclosure;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Ast.Interfaces,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Compat.Str,
  character;

type
  // A <details> section written the way GitHub and GitLab need it, with blank
  // lines around its markdown, is not one node but a run of siblings: an HTML
  // block that opens it and holds the summary, the blocks of its content, and
  // an HTML block that closes it. This finds those runs and says which blocks
  // a closed section hides. A section written as one HTML block, closing tag
  // included, is not a run and stays as it is.
  TMarkdownDisclosures = class
  private
    const
      OpenerTag = '<details';
      CloserTag = '</details';
      OpenAttribute = 'open';
    class function TryGetHtmlLiteral(const Node: IMarkdownNode; out Literal: string): Boolean; static;
    class function StartsWithTag(const Text, Tag: string): Boolean; static;
    class function HasOpenAttribute(const Literal: string): Boolean; static;

  public
    class function IsOpener(const Node: IMarkdownNode; out OpenByDefault: Boolean): Boolean; static;
    class function IsCloser(const Node: IMarkdownNode): Boolean; static;
    class function KeyOf(const Opener: IMarkdownNode): Integer; static;
    // A missing state means every section shows the way its tag asks for:
    // closed, unless it carries `open`.
    class function IsOpen(const State: IMarkdownDisclosureState; const Opener: IMarkdownNode;
      const OpenByDefault: Boolean): Boolean; static;
    // One flag per child of Container: True for a child inside a closed
    // section, and for the block that ends a section, which shows nothing but
    // would still add a gap. The opener of a closed section stays visible,
    // because its summary is what the reader clicks.
    class function HiddenChildren(const Container: IMarkdownNode;
      const State: IMarkdownDisclosureState): TArray<Boolean>; static;
  end;

implementation

uses
  SysUtils,
  StrUtils,
  Generics.Collections;

class function TMarkdownDisclosures.IsOpener(const Node: IMarkdownNode; out OpenByDefault: Boolean): Boolean;
var
  Literal: string;
  ClosesItself: type of (ContainsText(Literal, CloserTag));
begin
  OpenByDefault := False;
  Result := False;

  
  if not TryGetHtmlLiteral(Node, Literal) then
    Exit;

  if not StartsWithTag(Literal, OpenerTag) then
    Exit;

  ClosesItself := ContainsText(Literal, CloserTag);
  if ClosesItself then
    Exit;

  OpenByDefault := HasOpenAttribute(Literal);
  Result := True;
end;

class function TMarkdownDisclosures.IsCloser(const Node: IMarkdownNode): Boolean;
var
  Literal: string;
begin
  
  Result := TryGetHtmlLiteral(Node, Literal) and StartsWithTag(Literal, CloserTag);
end;

class function TMarkdownDisclosures.KeyOf(const Opener: IMarkdownNode): Integer;
begin
  Result := Opener.Segment.StartOffset;
end;

class function TMarkdownDisclosures.IsOpen(const State: IMarkdownDisclosureState; const Opener: IMarkdownNode;
  const OpenByDefault: Boolean): Boolean;
var
  Key: type of (KeyOf(Opener));
begin
  if State = nil then
  begin
    Result := OpenByDefault;
    Exit;
  end;

  Key := KeyOf(Opener);
  Result := State.IsDisclosureOpen(Key, OpenByDefault);
end;

class function TMarkdownDisclosures.HiddenChildren(const Container: IMarkdownNode;
  const State: IMarkdownDisclosureState): TArray<Boolean>;
var
  OpenSections: TList<Boolean>;
  ClosedDepth: Integer;
  Index: Integer;
  Child: IMarkdownNode;
  OpenByDefault: Boolean;
  SectionIsOpen: Boolean;
  ClosingIndex: Integer;
  ClosedSectionEnds: Boolean;
begin
  SetLength(Result, Container.ChildCount);

  OpenSections := TList<Boolean>.Create;
  try
    ClosedDepth := 0;

    for Index := 0 to Container.ChildCount - 1 do
    begin
      Child := Container.Children[Index];
      Result[Index] := (ClosedDepth > 0);

      
      if IsOpener(Child, OpenByDefault) then
      begin
        SectionIsOpen := IsOpen(State, Child, OpenByDefault);
        OpenSections.Add(SectionIsOpen);
        if not SectionIsOpen then
          Inc(ClosedDepth);
      end
      else if IsCloser(Child) and (OpenSections.Count > 0) then
      begin
        Result[Index] := True;

        ClosingIndex := OpenSections.Count - 1;
        ClosedSectionEnds := not OpenSections[ClosingIndex];
        OpenSections.Delete(ClosingIndex);
        if ClosedSectionEnds then
          Dec(ClosedDepth);
      end;
    end;
  finally
    OpenSections.Free;
  end;
end;

class function TMarkdownDisclosures.TryGetHtmlLiteral(const Node: IMarkdownNode; out Literal: string): Boolean;
var
  Html: IMarkdownText;
begin
  Literal := '';
  Result := False;

  if (Node = nil) or (Node.Kind <> TMarkdownNodeKind.HtmlBlock) then
    Exit;

  
  if not Supports(Node, IMarkdownText, Html) then
    Exit;

  Literal := Html.Literal;
  Result := True;
end;

// A tag name ends at a space, a line break, a slash or the closing bracket, so
// <detailsx> is not a <details> tag.
class function TMarkdownDisclosures.StartsWithTag(const Text, Tag: string): Boolean;
var
  Trimmed: string;
  NextIndex: Integer;
begin
  Trimmed := Text.TrimLeft;
  Result := False;

  if not StartsText(Tag, Trimmed) then
    Exit;

  NextIndex := Length(Tag) + 1;
  if NextIndex > Length(Trimmed) then
    Exit;

  Result := CharInSet(Trimmed[NextIndex], ['>', '/', ' ', #9, #10, #13]);
end;

class function TMarkdownDisclosures.HasOpenAttribute(const Literal: string): Boolean;
var
  Trimmed: string;
  TagEnd: Integer;
  AttributeText: string;
  Attributes: TArray<string>;
  Attribute: string;
  NameAndValue: TArray<string>;
  IsOpenAttribute: type of (SameText(NameAndValue[0], OpenAttribute));
begin
  Trimmed := Literal.TrimLeft;
  TagEnd := Pos('>', Trimmed);
  AttributeText := Copy(Trimmed, Length(OpenerTag) + 1, TagEnd - Length(OpenerTag) - 1);
  Attributes := AttributeText.Split([' ', #9, #10, #13, '/'], TStringSplitOptions.ExcludeEmpty);

  Result := False;
  for Attribute in Attributes do
  begin
    NameAndValue := Attribute.Split(['=']);
    IsOpenAttribute := SameText(NameAndValue[0], OpenAttribute);
    if IsOpenAttribute then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

end.
