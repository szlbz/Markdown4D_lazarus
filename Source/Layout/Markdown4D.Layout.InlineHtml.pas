{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Layout.InlineHtml;

{$SCOPEDENUMS ON}

interface

type
  // What a tag inside a paragraph does to the text after it, following the
  // subset GitHub renders. Hidden tags show nothing themselves; the text
  // between them stays.
  TInlineHtmlEffect = (Hidden, Bold, Italic, Code, Strikethrough, Underline, Subscript, Superscript, Small, Mark,
    LineBreak, Link);

  TInlineHtmlTag = record
  private
    const
      CommentStart = '<!--';
      TagPattern = '^<\s*(/?)\s*([A-Za-z][A-Za-z0-9-]*)';
      HrefPattern = '\bhref\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^\s>]+))';

  public
    Name: string;
    IsClosing: Boolean;
    IsComment: Boolean;
    Href: string;
    class function Parse(const Literal: string): TInlineHtmlTag; static;
    function Effect: TInlineHtmlEffect;
  end;

implementation

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  StrUtils,
  Markdown4D.Compat.RegEx;

class function TInlineHtmlTag.Parse(const Literal: string): TInlineHtmlTag;
var
  Trimmed: string;
  TagMatch: TMatch;
  HrefMatch: TMatch;
  Group: Integer;
  Value: type of (HrefMatch.Groups[Group].Value);
begin
  Result := Default(TInlineHtmlTag);

  Trimmed := Literal.Trim;
  Result.IsComment := Trimmed.StartsWith(CommentStart);
  if Result.IsComment then
    Exit;

  TagMatch := TRegEx.Match(Trimmed, TagPattern);
  if not TagMatch.Success then
    Exit;

  Result.IsClosing := (TagMatch.Groups[1].Value = '/');
  Result.Name := TagMatch.Groups[2].Value.ToLower;

  HrefMatch := TRegEx.Match(Trimmed, HrefPattern, [roIgnoreCase]);
  if not HrefMatch.Success then
    Exit;

  // Only the alternative that matched holds a value; the others come back empty.
  for Group := 1 to HrefMatch.Groups.Count - 1 do
  begin
    Value := HrefMatch.Groups[Group].Value;
    if Value <> '' then
    begin
      Result.Href := Value;
      Exit;
    end;
  end;
end;

// GitHub drops <u> and everything else outside its subset, keeping the text.
function TInlineHtmlTag.Effect: TInlineHtmlEffect;
begin
  if MatchText(Name, ['b', 'strong']) then
    Result := TInlineHtmlEffect.Bold
  else if MatchText(Name, ['i', 'em', 'var']) then
    Result := TInlineHtmlEffect.Italic
  else if MatchText(Name, ['code', 'kbd', 'samp', 'tt']) then
    Result := TInlineHtmlEffect.Code
  else if MatchText(Name, ['s', 'del', 'strike']) then
    Result := TInlineHtmlEffect.Strikethrough
  else if MatchText(Name, ['ins']) then
    Result := TInlineHtmlEffect.Underline
  else if MatchText(Name, ['sub']) then
    Result := TInlineHtmlEffect.Subscript
  else if MatchText(Name, ['sup']) then
    Result := TInlineHtmlEffect.Superscript
  else if MatchText(Name, ['small']) then
    Result := TInlineHtmlEffect.Small
  else if MatchText(Name, ['mark']) then
    Result := TInlineHtmlEffect.Mark
  else if MatchText(Name, ['br']) then
    Result := TInlineHtmlEffect.LineBreak
  else if MatchText(Name, ['a']) then
    Result := TInlineHtmlEffect.Link
  else
    Result := TInlineHtmlEffect.Hidden;
end;

end.
