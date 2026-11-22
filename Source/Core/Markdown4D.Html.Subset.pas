{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Html.Subset;

{$SCOPEDENUMS ON}

// Translates the HTML that turns up inside markdown documents into markdown.
//
// Raw HTML is not rendered by the viewer: the HTML renderer omits it, and
// painting the markup as text would put tags in front of a reader. Dropping it
// wholesale is not right either, because a README leans on a handful of tags
// that markdown cannot express: centred images, <details> sections, <br>,
// <sub>, <kbd>. Those carry meaning a reader expects to see.
//
// So instead of a second rendering path, the allowed subset is translated to
// markdown and handed back to the parser. Everything downstream - layout,
// selection, hit-testing, theming, image loading - then works on it unchanged.
//
// The list of tags this understands is deliberately short. A tag that is not on
// it is dropped while its content is kept, which is what a browser would show
// with the styling removed. <script> and <style> are dropped with their content,
// because their content is not text a reader wants.

interface

type
  TMarkdownHtmlSubset = class
  public
    // Converts an HTML fragment to markdown. Returns an empty string when
    // nothing survives the translation.
    class function ToMarkdown(const Html: string): string; static;
    // True when the fragment holds nothing a reader would see.
    class function IsEmpty(const Html: string): Boolean; static;
  end;

implementation

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  StrUtils,
  Classes,
  Generics.Collections,
  Markdown4D.Html.Entities;

type
  TTagKind = (
    // Content is kept, the tag itself contributes nothing.
    Transparent,
    // Tag and content both disappear.
    Dropped,
    Paragraph,
    LineBreak,
    Heading,
    ThematicBreak,
    Strong,
    Emphasis,
    CodeSpan,
    Strikethrough,
    Anchor,
    Image,
    UnorderedList,
    OrderedList,
    ListItem,
    BlockQuote,
    Details,
    Summary,
    Preformatted);

  TTagInfo = record
    Kind: TTagKind;
    // Markdown emitted when the tag opens and when it closes. Blocks manage
    // their own spacing instead.
    Opener: string;
    Closer: string;
    IsBlock: Boolean;
  end;

  TParsedTag = record
    Name: string;
    IsClosing: Boolean;
    IsSelfClosing: Boolean;
    Attributes: TDictionary<string, string>;
  end;

  TOpenTag = record
    Name: string;
    Kind: TTagKind;
    Closer: string;
    class function Create(const Name: string; const Kind: TTagKind; const Closer: string): TOpenTag; static;
  end;

  TSubsetConverter = class
  strict private
    const
      MarkdownSpecials = ['\', '`', '*', '_', '[', ']', '<', '>', '#', '|', '~'];
      ListIndent = '  ';
    var
      FSource: string;
      FLowered: string;
      FPosition: Integer;
      FOutput: TStringBuilder;
      // A stack, but held as a list because closing a tag has to search it from
      // the top down and TStack enumerates the other way round.
      FOpen: TList<TOpenTag>;
      FListMarkers: TStack<string>;
      FQuoteDepth: Integer;
      FAtLineStart: Boolean;
      FPendingBlank: Boolean;
      FHasContent: Boolean;
      FAfterOpener: Boolean;
    class function TagInfoOf(const Name: string): TTagInfo; static;
    class function EscapeText(const Value: string): string; static;
    class function DecodeEntities(const Value: string): string; static;
    class function NormalizeWhitespace(const Value: string): string; static;
    class function FormatDestination(const Value: string): string; static;
    function LinePrefix: string;
    procedure Write(const Value: string);
    procedure WriteOpener(const Value: string);
    procedure StartLine;
    procedure StartBlock;
    procedure SkipTo(const ClosingTag: string);
    function ReadPreformatted: string;
    function TryReadTag(out Tag: TParsedTag): Boolean;
    function ReadText: string;
    procedure HandleOpenTag(const Tag: TParsedTag);
    procedure HandleCloseTag(const Name: string);
    procedure HandleImage(const Tag: TParsedTag);
    procedure HandleListItem;
  public
    constructor Create(const Html: string);
    destructor Destroy; override;
    function Convert: string;
  end;

{ TOpenTag }

class function TOpenTag.Create(const Name: string; const Kind: TTagKind; const Closer: string): TOpenTag;
begin
  Result.Name := Name;
  Result.Kind := Kind;
  Result.Closer := Closer;
end;

{ TSubsetConverter }

constructor TSubsetConverter.Create(const Html: string);
begin
  inherited Create;

  FSource := Html;
  FLowered := Html.ToLower;
  FPosition := 1;
  FOutput := TStringBuilder.Create;
  FOpen := TList<TOpenTag>.Create;
  FListMarkers := TStack<string>.Create;
  FAtLineStart := True;
end;

destructor TSubsetConverter.Destroy;
begin
  FListMarkers.Free;
  FOpen.Free;
  FOutput.Free;

  inherited;
end;

class function TSubsetConverter.TagInfoOf(const Name: string): TTagInfo;
begin
  Result := Default(TTagInfo);
  Result.Kind := TTagKind.Transparent;

  if (Name = 'script') or (Name = 'style') or (Name = 'head') or (Name = 'iframe') or (Name = 'object') then
    Result.Kind := TTagKind.Dropped
  else if (Name = 'p') or (Name = 'div') or (Name = 'center') or (Name = 'section') or (Name = 'article') then
  begin
    Result.Kind := TTagKind.Paragraph;
    Result.IsBlock := True;
  end
  else if Name = 'br' then
    Result.Kind := TTagKind.LineBreak
  else if (Length(Name) = 2) and (Name[1] = 'h') and CharInSet(Name[2], ['1'..'6']) then
  begin
    Result.Kind := TTagKind.Heading;
    Result.Opener := StringOfChar('#', StrToInt(Name[2])) + ' ';
    Result.IsBlock := True;
  end
  else if Name = 'hr' then
  begin
    Result.Kind := TTagKind.ThematicBreak;
    Result.IsBlock := True;
  end
  else if (Name = 'strong') or (Name = 'b') then
  begin
    Result.Kind := TTagKind.Strong;
    Result.Opener := '**';
    Result.Closer := '**';
  end
  else if (Name = 'em') or (Name = 'i') then
  begin
    Result.Kind := TTagKind.Emphasis;
    Result.Opener := '*';
    Result.Closer := '*';
  end
  else if (Name = 'code') or (Name = 'kbd') or (Name = 'samp') or (Name = 'tt') then
  begin
    Result.Kind := TTagKind.CodeSpan;
    Result.Opener := '`';
    Result.Closer := '`';
  end
  else if (Name = 'del') or (Name = 's') or (Name = 'strike') then
  begin
    Result.Kind := TTagKind.Strikethrough;
    Result.Opener := '~~';
    Result.Closer := '~~';
  end
  else if Name = 'a' then
    Result.Kind := TTagKind.Anchor
  else if Name = 'img' then
    Result.Kind := TTagKind.Image
  else if Name = 'ul' then
  begin
    Result.Kind := TTagKind.UnorderedList;
    Result.IsBlock := True;
  end
  else if Name = 'ol' then
  begin
    Result.Kind := TTagKind.OrderedList;
    Result.IsBlock := True;
  end
  else if Name = 'li' then
    Result.Kind := TTagKind.ListItem
  else if Name = 'blockquote' then
  begin
    Result.Kind := TTagKind.BlockQuote;
    Result.IsBlock := True;
  end
  else if Name = 'details' then
  begin
    Result.Kind := TTagKind.Details;
    Result.IsBlock := True;
  end
  else if Name = 'summary' then
  begin
    Result.Kind := TTagKind.Summary;
    Result.Opener := '**';
    Result.Closer := '**';
    Result.IsBlock := True;
  end
  else if Name = 'pre' then
  begin
    Result.Kind := TTagKind.Preformatted;
    Result.IsBlock := True;
  end;
end;

class function TSubsetConverter.EscapeText(const Value: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    for Index := 1 to Length(Value) do
    begin
      if CharInSet(Value[Index], MarkdownSpecials) then
        Builder.Append('\');

      Builder.Append(Value[Index]);
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TSubsetConverter.DecodeEntities(const Value: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  Semicolon: type of (PosEx(';', Value, Index + 1));
  Decoded: string;
  HasReference: Boolean;
  Reference: string;
  IsNumeric: Boolean;
begin
  if not Value.Contains('&') then
  begin
    Result := Value;
    Exit;
  end;

  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(Value) do
    begin
      if Value[Index] <> '&' then
      begin
        Builder.Append(Value[Index]);
        Inc(Index);
        Continue;
      end;

      Semicolon := PosEx(';', Value, Index + 1);
      Decoded := '';
      HasReference := (Semicolon > Index + 1) and (Semicolon - Index <= 32);
      if HasReference then
      begin
        Reference := Copy(Value, Index + 1, Semicolon - Index - 1);
        IsNumeric := Reference.StartsWith('#');
        if IsNumeric then
          THtmlEntities.TryDecodeNumeric(Reference, Decoded)
        else
          THtmlEntities.TryDecode(Reference, Decoded);
      end;

      if Decoded <> '' then
      begin
        Builder.Append(Decoded);
        Index := Semicolon + 1;
      end
      else
      begin
        Builder.Append(Value[Index]);
        Inc(Index);
      end;
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

// HTML collapses runs of whitespace, including newlines, into a single space.
class function TSubsetConverter.NormalizeWhitespace(const Value: string): string;
var
  Builder: TStringBuilder;
  InWhitespace: Boolean;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    InWhitespace := False;
    for Index := 1 to Length(Value) do
    begin
      if Value[Index].IsWhiteSpace then
      begin
        InWhitespace := True;
        Continue;
      end;

      if InWhitespace then
        Builder.Append(' ');

      InWhitespace := False;
      Builder.Append(Value[Index]);
    end;

    if InWhitespace then
      Builder.Append(' ');

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TSubsetConverter.FormatDestination(const Value: string): string;
begin
  Result := DecodeEntities(Value).Trim;
  if Result.Contains(' ') then
    Result := '<' + Result + '>';
end;

function TSubsetConverter.LinePrefix: string;
begin
  Result := DupeString('> ', FQuoteDepth);
  if FListMarkers.Count > 0 then
    Result := Result + DupeString(ListIndent, FListMarkers.Count);
end;

procedure TSubsetConverter.Write(const Value: string);
begin
  if Value = '' then
    Exit;

  if FPendingBlank and FHasContent then
  begin
    FOutput.Append(sLineBreak);
    if FQuoteDepth > 0 then
      FOutput.Append('>' + sLineBreak);

    FAtLineStart := True;
  end;

  FPendingBlank := False;

  if FAtLineStart then
    FOutput.Append(LinePrefix);

  FOutput.Append(Value);
  FAtLineStart := False;
  FHasContent := True;
  FAfterOpener := False;
end;

procedure TSubsetConverter.WriteOpener(const Value: string);
begin
  Write(Value);
  FAfterOpener := True;
end;

procedure TSubsetConverter.StartLine;
begin
  if FAtLineStart then
    Exit;

  FOutput.Append(sLineBreak);
  FAtLineStart := True;
end;

procedure TSubsetConverter.StartBlock;
begin
  StartLine;
  if FHasContent then
    FPendingBlank := True;
end;

// Steps over everything up to and including the closing tag, for content a
// reader should never see.
procedure TSubsetConverter.SkipTo(const ClosingTag: string);
var
  Closing: string;
  Found: type of (PosEx(Closing, FLowered, FPosition));
  Terminator: type of (PosEx('>', FSource, FPosition));
begin
  Closing := '</' + ClosingTag;
  Found := PosEx(Closing, FLowered, FPosition);
  if Found = 0 then
  begin
    FPosition := Length(FSource) + 1;
    Exit;
  end;

  FPosition := Found + Length(Closing);
  Terminator := PosEx('>', FSource, FPosition);
  if Terminator > 0 then
    FPosition := Terminator + 1;
end;

// <pre> keeps its line breaks and its spacing, so it is read raw and emitted as
// a fenced code block.
function TSubsetConverter.ReadPreformatted: string;
var
  Found: type of (PosEx('</pre', FLowered, FPosition));
  Content: string;
  Terminator: type of (PosEx('>', FSource, FPosition));
begin
  Found := PosEx('</pre', FLowered, FPosition);
  Content := '';
  if Found = 0 then
  begin
    Content := Copy(FSource, FPosition, MaxInt);
    FPosition := Length(FSource) + 1;
  end
  else
  begin
    Content := Copy(FSource, FPosition, Found - FPosition);
    FPosition := Found + Length('</pre');
    Terminator := PosEx('>', FSource, FPosition);
    if Terminator > 0 then
      FPosition := Terminator + 1;
  end;

  // A <code> wrapper inside <pre> is conventional and carries nothing extra.
  Content := Content.Replace('<code>', '', [rfReplaceAll, rfIgnoreCase]);
  Content := Content.Replace('</code>', '', [rfReplaceAll, rfIgnoreCase]);

  Result := DecodeEntities(Content).Trim([#10, #13, ' ']);
end;

function TSubsetConverter.TryReadTag(out Tag: TParsedTag): Boolean;
var
  Scan: Integer;
  CommentEnd: type of (PosEx('-->', FSource, Scan));
  Terminator: type of (PosEx('>', FSource, Scan));
  NameStart: Integer;
  AttributeStart: Integer;
  AttributeName: string;
  Value: string;
  Quote: Char;
  ValueStart: Integer;
begin
  Tag := Default(TParsedTag);

  if (FPosition > Length(FSource)) or (FSource[FPosition] <> '<') then
  begin
    Result := False;
    Exit;
  end;

  Scan := FPosition + 1;
  if Scan > Length(FSource) then
  begin
    Result := False;
    Exit;
  end;

  // Comments and declarations carry nothing for a reader.
  if Copy(FSource, Scan, 3) = '!--' then
  begin
    CommentEnd := PosEx('-->', FSource, Scan);
    if CommentEnd = 0 then
      FPosition := Length(FSource) + 1
    else
      FPosition := CommentEnd + 3;

    Result := False;
    Exit;
  end;

  if FSource[Scan] = '!' then
  begin
    Terminator := PosEx('>', FSource, Scan);
    if Terminator = 0 then
      FPosition := Length(FSource) + 1
    else
      FPosition := Terminator + 1;

    Result := False;
    Exit;
  end;

  Tag.IsClosing := FSource[Scan] = '/';
  if Tag.IsClosing then
    Inc(Scan);

  NameStart := Scan;
  while (Scan <= Length(FSource)) and (FLowered[Scan].IsLetterOrDigit) do
    Inc(Scan);

  if Scan = NameStart then
  begin
    Result := False;
    Exit;
  end;

  Tag.Name := Copy(FLowered, NameStart, Scan - NameStart);
  Tag.Attributes := TDictionary<string, string>.Create;

  while Scan <= Length(FSource) do
  begin
    while (Scan <= Length(FSource)) and FSource[Scan].IsWhiteSpace do
      Inc(Scan);

    if Scan > Length(FSource) then
      Break;

    if FSource[Scan] = '>' then
    begin
      Inc(Scan);
      Break;
    end;

    if FSource[Scan] = '/' then
    begin
      Tag.IsSelfClosing := True;
      Inc(Scan);
      Continue;
    end;

    AttributeStart := Scan;
    while (Scan <= Length(FSource)) and (FLowered[Scan].IsLetterOrDigit or (FSource[Scan] = '-')) do
      Inc(Scan);

    if Scan = AttributeStart then
    begin
      Inc(Scan);
      Continue;
    end;

    AttributeName := Copy(FLowered, AttributeStart, Scan - AttributeStart);

    while (Scan <= Length(FSource)) and FSource[Scan].IsWhiteSpace do
      Inc(Scan);

    Value := '';
    if (Scan <= Length(FSource)) and (FSource[Scan] = '=') then
    begin
      Inc(Scan);
      while (Scan <= Length(FSource)) and FSource[Scan].IsWhiteSpace do
        Inc(Scan);

      if Scan <= Length(FSource) then
      begin
        Quote := FSource[Scan];
        if (Quote = '"') or (Quote = '''') then
        begin
          Inc(Scan);
          ValueStart := Scan;
          while (Scan <= Length(FSource)) and (FSource[Scan] <> Quote) do
            Inc(Scan);

          Value := Copy(FSource, ValueStart, Scan - ValueStart);
          if Scan <= Length(FSource) then
            Inc(Scan);
        end
        else
        begin
          ValueStart := Scan;
          while (Scan <= Length(FSource)) and not FSource[Scan].IsWhiteSpace and (FSource[Scan] <> '>') do
            Inc(Scan);

          Value := Copy(FSource, ValueStart, Scan - ValueStart);
        end;
      end;
    end;

    Tag.Attributes.AddOrSetValue(AttributeName, Value);
  end;

  FPosition := Scan;
  Result := True;
end;

function TSubsetConverter.ReadText: string;
var
  Start: Integer;
begin
  Start := FPosition;
  while (FPosition <= Length(FSource)) and (FSource[FPosition] <> '<') do
    Inc(FPosition);

  Result := Copy(FSource, Start, FPosition - Start);
end;

procedure TSubsetConverter.HandleImage(const Tag: TParsedTag);
var
  Source: string;
  AltText: string;
begin
  Source := '';
  if not Tag.Attributes.TryGetValue('src', Source) or (Source.Trim = '') then
    Exit;

  AltText := '';
  Tag.Attributes.TryGetValue('alt', AltText);

  Write(Format('![%s](%s)', [EscapeText(DecodeEntities(AltText)), FormatDestination(Source)]));
end;

procedure TSubsetConverter.HandleListItem;
var
  Marker: string;
  Outer: string;
begin
  StartLine;

  Marker := '- ';
  if FListMarkers.Count > 0 then
    Marker := FListMarkers.Peek;

  // The marker sits one level out from the content indent the prefix adds.
  if FListMarkers.Count > 0 then
  begin
    Outer := FListMarkers.Pop;
    try
      Write(Marker);
    finally
      FListMarkers.Push(Outer);
    end;
  end
  else
    Write(Marker);
end;

procedure TSubsetConverter.HandleOpenTag(const Tag: TParsedTag);
var
  Info: TTagInfo;
  Content: string;
  Line: string;
  Destination: string;
begin
  Info := TagInfoOf(Tag.Name);

  case Info.Kind of
    TTagKind.Dropped:
      begin
        if not Tag.IsSelfClosing then
          SkipTo(Tag.Name);
        Exit;
      end;

    TTagKind.LineBreak:
      begin
        // Two trailing spaces are a hard break in markdown.
        if not FAtLineStart then
          FOutput.Append('  ');

        StartLine;
        Exit;
      end;

    TTagKind.ThematicBreak:
      begin
        StartBlock;
        Write('---');
        StartLine;
        FPendingBlank := True;
        Exit;
      end;

    TTagKind.Image:
      begin
        HandleImage(Tag);
        Exit;
      end;

    TTagKind.ListItem:
      begin
        HandleListItem;
        FOpen.Add(TOpenTag.Create(Tag.Name, Info.Kind, ''));
        Exit;
      end;

    TTagKind.UnorderedList,
    TTagKind.OrderedList:
      begin
        StartBlock;
        FListMarkers.Push(IfThen(Info.Kind = TTagKind.OrderedList, '1. ', '- '));
        FOpen.Add(TOpenTag.Create(Tag.Name, Info.Kind, ''));
        Exit;
      end;

    TTagKind.BlockQuote:
      begin
        StartBlock;
        Inc(FQuoteDepth);
        FOpen.Add(TOpenTag.Create(Tag.Name, Info.Kind, ''));
        Exit;
      end;

    TTagKind.Preformatted:
      begin
        StartBlock;
        Content := ReadPreformatted;
        if Content <> '' then
        begin
          Write('```');
          StartLine;
          for Line in Content.Split([#10]) do
          begin
            Write(Line.TrimRight([#13]));
            StartLine;
          end;
          Write('```');
          StartLine;
          FPendingBlank := True;
        end;
        Exit;
      end;
  else
    // Every other kind (Transparent, Paragraph, headings, inline styles,
    // anchors, Details/Summary, ...) shares the generic block/opener/closer
    // handling below instead of a dedicated branch here.
  end;

  if Info.IsBlock then
    StartBlock;

  if Info.Opener <> '' then
    WriteOpener(Info.Opener);

  if Info.Kind = TTagKind.Anchor then
  begin
    Destination := '';
    Tag.Attributes.TryGetValue('href', Destination);
    if Destination.Trim <> '' then
    begin
      WriteOpener('[');
      FOpen.Add(TOpenTag.Create(Tag.Name, Info.Kind, Format('](%s)', [FormatDestination(Destination)])));
      Exit;
    end;
  end;

  if not Tag.IsSelfClosing then
    FOpen.Add(TOpenTag.Create(Tag.Name, Info.Kind, Info.Closer));
end;

procedure TSubsetConverter.HandleCloseTag(const Name: string);
var
  Match: Integer;
  Index: Integer;
  Open: TOpenTag;
begin
  // Unwind to the nearest matching tag, so unbalanced markup cannot leave the
  // stack stuck on something that never closes.
  Match := -1;
  for Index := FOpen.Count - 1 downto 0 do
  begin
    if FOpen[Index].Name = Name then
    begin
      Match := Index;
      Break;
    end;
  end;

  if Match < 0 then
    Exit;

  while FOpen.Count > Match do
  begin
    Open := FOpen.Last;
    FOpen.Delete(FOpen.Count - 1);

    if Open.Closer <> '' then
      Write(Open.Closer);

    case Open.Kind of
      TTagKind.BlockQuote:
        begin
          Dec(FQuoteDepth);
          StartLine;
          FPendingBlank := True;
        end;
      TTagKind.UnorderedList,
      TTagKind.OrderedList:
        begin
          if FListMarkers.Count > 0 then
            FListMarkers.Pop;

          StartLine;
          FPendingBlank := True;
        end;
      TTagKind.ListItem:
        StartLine;
      TTagKind.Paragraph,
      TTagKind.Heading,
      TTagKind.Summary,
      TTagKind.Details:
        begin
          StartLine;
          FPendingBlank := True;
        end;
    else
      // Inline kinds (Strong, Emphasis, CodeSpan, Strikethrough, Anchor, ...)
      // only need their Closer text, already written above; nothing more to do.
    end;
  end;
end;

function TSubsetConverter.Convert: string;
var
  Tag: TParsedTag;
  Before: Integer;
  Text: string;
  DropsLeadingSpace: Boolean;
  Open: TOpenTag;
begin
  while FPosition <= Length(FSource) do
  begin
    if FSource[FPosition] = '<' then
    begin
      
      Before := FPosition;
      if TryReadTag(Tag) then
      begin
        try
          if Tag.IsClosing then
            HandleCloseTag(Tag.Name)
          else
            HandleOpenTag(Tag);
        finally
          Tag.Attributes.Free;
        end;
      end
      else if FPosition = Before then
      begin
        // Not a tag after all; treat the character as text.
        Write(EscapeText('<'));
        Inc(FPosition);
      end;

      Continue;
    end;

    Text := NormalizeWhitespace(DecodeEntities(ReadText));

    // A space at the start of a line would indent it, and one right after **
    // or [ stops markdown from seeing the emphasis or the link.
    DropsLeadingSpace := (FAtLineStart or FAfterOpener);
    if DropsLeadingSpace then
      Text := Text.TrimLeft;

    if Text <> '' then
      Write(EscapeText(Text));
  end;

  // Close whatever the document left open.
  while FOpen.Count > 0 do
  begin
    Open := FOpen.Last;
    FOpen.Delete(FOpen.Count - 1);

    if Open.Closer <> '' then
      Write(Open.Closer);
  end;

  Result := FOutput.ToString.Trim;
end;

{ TMarkdownHtmlSubset }

class function TMarkdownHtmlSubset.ToMarkdown(const Html: string): string;
var
  Converter: TSubsetConverter;
begin
  Converter := TSubsetConverter.Create(Html);
  try
    Result := Converter.Convert;
  finally
    Converter.Free;
  end;
end;

class function TMarkdownHtmlSubset.IsEmpty(const Html: string): Boolean;
begin
  Result := ToMarkdown(Html) = '';
end;

end.
