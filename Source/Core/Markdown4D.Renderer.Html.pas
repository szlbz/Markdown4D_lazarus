{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Renderer.Html;

{$SCOPEDENUMS ON}

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  Generics.Collections,
  Markdown4D.Compat.RegEx,
  Markdown4D.Extensions.Interfaces,
  Markdown4D.Pipeline.Configuration,
  Markdown4D.Ast.Interfaces;

type
  TMarkdownHtmlRenderer = class
  private
    type
      TRenderPhase = (Enter, Leave);
      TRenderTask = record
        Node: IMarkdownNode;
        Phase: TRenderPhase;
        WasTightList: Boolean;
      end;
    const
      LanguageClassFormat = ' class="language-%s"';
      HeadingOpenFormat = '<h%d>';
      HeadingCloseFormat = '</h%d>';
      OrderedListStartFormat = '<ol start="%d">';
      AnchorOpenFormat = '<a href="%s"';
      ImageOpenFormat = '<img src="%s" alt="';
      TitleAttributeFormat = ' title="%s"';
      AnchorCloseTag = '</a>';
      AlertOpenFormat = '<div class="markdown-alert markdown-alert-%s">';
      AlertTitleFormat = '<p class="markdown-alert-title">%s</p>';
      AlertCloseTag = '</div>';
      TagCloseBracket = '>';
      OmittedHtmlComment = '<!-- raw HTML omitted -->';
      EscapedHtmlBlockFormat = '<p>%s</p>';
      NoOpenerAttribute = ' rel="noopener noreferrer"';
      RejectedLinkDestination = '#';
      RejectedImageSource = '';
      EscapedAmpersand = '&amp;';
      EscapedLessThan = '&lt;';
      EscapedGreaterThan = '&gt;';
      EscapedQuote = '&quot;';
      EscapedApostrophe = '&#39;';
      TableHeadOpenTag = '<thead>';
      TableHeadCloseTag = '</thead>';
      TableBodyOpenTag = '<tbody>';
      TableBodyCloseTag = '</tbody>';
      TableCellOpenFormat = '<%s';
      TableCellCloseFormat = '</%s>';
      TableAlignAttributeFormat = ' align="%s"';
      TableHeaderCellTag = 'th';
      TableDataCellTag = 'td';
      TableAlignmentNames: array[TMarkdownTableColumnAlignment] of string = ('', 'left', 'center', 'right');
      DisallowedTagPattern =
        '<(?=/?(?:title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)[\s/>])';
      InfoSplitChars: array[0..1] of Char = (' ', #9);
      MathSpanOpenTag = '<span class="math">';
      MathSpanCloseTag = '</span>';
      MathDivOpenTag = '<div class="math">';
      MathDivCloseTag = '</div>';
      InlineMathOpen = '\(';
      InlineMathClose = '\)';
      DisplayMathOpen = '\[';
      DisplayMathClose = '\]';
    var
      FOutput: TStringBuilder;
      FTasks: TStack<TRenderTask>;
      FTightList: Boolean;
      FInlineDepth: Integer;
      FTableInHeader: Boolean;
      FTableInBody: Boolean;
      FOptions: TMarkdownRendererOptions;
      FHooks: TDictionary<string, IMarkdownRendererHook>;
      FWriter: IMarkdownHtmlWriter;
      FTagFilterRegex: TRegEx;
    procedure Render(const Document: IMarkdownDocument);
    procedure EnterNode(const Node: IMarkdownNode);
    procedure LeaveNode(const Task: TRenderTask);
    procedure EnterParagraph(const Node: IMarkdownNode);
    procedure EnterHeading(const Node: IMarkdownHeading);
    procedure WriteThematicBreak;
    procedure WriteCodeBlock(const Node: IMarkdownCodeBlock);
    procedure EnterBlockQuote(const Node: IMarkdownNode);
    procedure EnterList(const Node: IMarkdownList);
    procedure EnterListItem(const Node: IMarkdownNode);
    procedure EnterHtmlBlock(const Node: IMarkdownText);
    function HtmlBlockOutput(const Literal: string): string;
    procedure EnterTable(const Node: IMarkdownNode);
    procedure EnterTableRow(const Node: IMarkdownTableRow);
    procedure EnterTableCell(const Node: IMarkdownTableCell);
    procedure WriteMath(const Node: IMarkdownMath);
    procedure WriteInlineMath(const Node: IMarkdownMath);
    procedure WriteMathBlock(const Node: IMarkdownMath);
    function CurrentTableCellTag: string;
    function RawHtmlOutput(const Literal: string): string;
    procedure EnterCustomInline(const Node: IMarkdownNode);
    procedure LeaveCustomInline(const Node: IMarkdownNode);
    function TryFindHook(const Node: IMarkdownNode; out Hook: IMarkdownRendererHook): Boolean;
    procedure EnterSpan(const Node: IMarkdownNode; const OpenTag: string);
    procedure WriteCodeSpan(const Node: IMarkdownText);
    procedure EnterAnchor(const Node: IMarkdownLink);
    procedure WriteImage(const Node: IMarkdownLink);
    function DestinationOutput(const Destination, RejectedValue: string): string;
    procedure AppendAltText(const Node: IMarkdownNode);
    class procedure PushChildrenReversed(const Pending: TStack<IMarkdownNode>; const Node: IMarkdownNode);
    procedure WriteHardBreak;
    procedure LeaveParagraph;
    procedure LeaveHeading(const Node: IMarkdownHeading);
    procedure LeaveBlockQuote(const Node: IMarkdownNode; const WasTightList: Boolean);
    procedure LeaveList(const Node: IMarkdownList; const WasTightList: Boolean);
    procedure LeaveListItem;
    procedure LeaveTable;
    procedure LeaveTableRow(const Node: IMarkdownTableRow);
    procedure LeaveTableCell;
    procedure ScheduleLeaveAndChildren(const Node: IMarkdownNode; const WasTightList: Boolean);
    procedure AppendLineBreak;
    class function FirstInfoWord(const InfoString: string): string;
    class function EscapeCore(const Value: string; const EscapeApostrophe: Boolean): string;
    class function EscapeHtml(const Value: string): string;

  public
    class function RenderDocument(const Document: IMarkdownDocument): string; overload;
    class function RenderDocument(const Document: IMarkdownDocument; const Options: TMarkdownRendererOptions;
                                  const Hooks: TDictionary<string, IMarkdownRendererHook>): string; overload;
    constructor Create(const Options: TMarkdownRendererOptions;
                       const Hooks: TDictionary<string, IMarkdownRendererHook>);
    destructor Destroy; override;
  end;

implementation

uses
  Markdown4D.Defines,
  Markdown4D.Extensions.Alerts,
  Markdown4D.Text.UrlSafety;

type
  TRendererHtmlWriter = class(TInterfacedObject, IMarkdownHtmlWriter)
  private
    FOutput: TStringBuilder;

  public
    constructor Create(const Output: TStringBuilder);
    procedure WriteRaw(const Html: string);
    procedure WriteEscaped(const Text: string);
    function EscapeAttribute(const Value: string): string;
    procedure WriteAttribute(const Name, Value: string);
  end;

class function TMarkdownHtmlRenderer.RenderDocument(const Document: IMarkdownDocument): string;
begin
  Result := RenderDocument(Document, TMarkdownRendererOptions.SpecDefaults, nil);
end;

class function TMarkdownHtmlRenderer.RenderDocument(const Document: IMarkdownDocument;
                                                    const Options: TMarkdownRendererOptions;
                                                    const Hooks: TDictionary<string, IMarkdownRendererHook>): string;
var
  Renderer: TMarkdownHtmlRenderer;
begin
  Renderer := TMarkdownHtmlRenderer.Create(Options, Hooks);
  try
    Renderer.Render(Document);

    Result := Renderer.FOutput.ToString;
  finally
    Renderer.Free;
  end;
end;

constructor TMarkdownHtmlRenderer.Create(const Options: TMarkdownRendererOptions;
                                         const Hooks: TDictionary<string, IMarkdownRendererHook>);
begin
  inherited Create;

  FOptions := Options;
  FHooks := Hooks;
  FOutput := TStringBuilder.Create;
  FTasks := TStack<TRenderTask>.Create;
  FWriter := TRendererHtmlWriter.Create(FOutput);

  if FOptions.ApplyTagFilter then
    FTagFilterRegex := TRegEx.Create(DisallowedTagPattern, [roIgnoreCase]);
end;

destructor TMarkdownHtmlRenderer.Destroy;
begin
  FTasks.Free;
  FOutput.Free;

  inherited Destroy;
end;

procedure TMarkdownHtmlRenderer.Render(const Document: IMarkdownDocument);
var
  Task: TRenderTask;
begin
  ScheduleLeaveAndChildren(Document, FTightList);

  while FTasks.Count > 0 do
  begin
    Task := FTasks.Pop;

    if Task.Phase = TRenderPhase.Enter then
      EnterNode(Task.Node)
    else
      LeaveNode(Task);
  end;
end;

procedure TMarkdownHtmlRenderer.EnterNode(const Node: IMarkdownNode);
begin
  case Node.Kind of
    TMarkdownNodeKind.Paragraph:
      EnterParagraph(Node);
    TMarkdownNodeKind.Heading:
      EnterHeading(Node as IMarkdownHeading);
    TMarkdownNodeKind.ThematicBreak:
      WriteThematicBreak;
    TMarkdownNodeKind.CodeBlock:
      WriteCodeBlock(Node as IMarkdownCodeBlock);
    TMarkdownNodeKind.BlockQuote:
      EnterBlockQuote(Node);
    TMarkdownNodeKind.List:
      EnterList(Node as IMarkdownList);
    TMarkdownNodeKind.ListItem:
      EnterListItem(Node);
    TMarkdownNodeKind.HtmlBlock:
      EnterHtmlBlock(Node as IMarkdownText);
    TMarkdownNodeKind.Text:
      FOutput.Append(EscapeHtml((Node as IMarkdownText).Literal));
    TMarkdownNodeKind.Emphasis:
      EnterSpan(Node, '<em>');
    TMarkdownNodeKind.Strong:
      EnterSpan(Node, '<strong>');
    TMarkdownNodeKind.CodeSpan:
      WriteCodeSpan(Node as IMarkdownText);
    TMarkdownNodeKind.Link, TMarkdownNodeKind.Autolink:
      EnterAnchor(Node as IMarkdownLink);
    TMarkdownNodeKind.Image:
      WriteImage(Node as IMarkdownLink);
    TMarkdownNodeKind.SoftLineBreak:
      FOutput.Append(LineFeed);
    TMarkdownNodeKind.HardLineBreak:
      WriteHardBreak;
    TMarkdownNodeKind.InlineHtml:
      FOutput.Append(RawHtmlOutput((Node as IMarkdownText).Literal));
    TMarkdownNodeKind.CustomInline:
      EnterCustomInline(Node);
    TMarkdownNodeKind.Table:
      EnterTable(Node);
    TMarkdownNodeKind.TableRow:
      EnterTableRow(Node as IMarkdownTableRow);
    TMarkdownNodeKind.TableCell:
      EnterTableCell(Node as IMarkdownTableCell);
    TMarkdownNodeKind.Math:
      WriteMath(Node as IMarkdownMath);
  else
    // Document is only ever scheduled for a Leave task (see Render), so this
    // guards a future node kind added without updating this dispatcher.
    raise ENotSupportedException.CreateFmt('Unsupported node kind: %d', [Ord(Node.Kind)]);
  end;
end;

procedure TMarkdownHtmlRenderer.LeaveNode(const Task: TRenderTask);
begin
  case Task.Node.Kind of
    TMarkdownNodeKind.Paragraph:
      LeaveParagraph;
    TMarkdownNodeKind.Heading:
      LeaveHeading(Task.Node as IMarkdownHeading);
    TMarkdownNodeKind.BlockQuote:
      LeaveBlockQuote(Task.Node, Task.WasTightList);
    TMarkdownNodeKind.List:
      LeaveList(Task.Node as IMarkdownList, Task.WasTightList);
    TMarkdownNodeKind.ListItem:
      LeaveListItem;
    TMarkdownNodeKind.Emphasis:
      FOutput.Append('</em>');
    TMarkdownNodeKind.Strong:
      FOutput.Append('</strong>');
    TMarkdownNodeKind.Link, TMarkdownNodeKind.Autolink:
      FOutput.Append(AnchorCloseTag);
    TMarkdownNodeKind.CustomInline:
      LeaveCustomInline(Task.Node);
    TMarkdownNodeKind.Table:
      LeaveTable;
    TMarkdownNodeKind.TableRow:
      LeaveTableRow(Task.Node as IMarkdownTableRow);
    TMarkdownNodeKind.TableCell:
      LeaveTableCell;
  else
    // Document is the root passed to Render; it closes nothing of its own.
    // Every other kind that reaches a Leave task is handled above.
  end;
end;

procedure TMarkdownHtmlRenderer.EnterParagraph(const Node: IMarkdownNode);
begin
  if not FTightList then
  begin
    AppendLineBreak;
    FOutput.Append('<p>');
  end;

  Inc(FInlineDepth);
  ScheduleLeaveAndChildren(Node, FTightList);
end;

procedure TMarkdownHtmlRenderer.EnterHeading(const Node: IMarkdownHeading);
begin
  AppendLineBreak;
  FOutput.Append(Format(HeadingOpenFormat, [Node.Level]));

  Inc(FInlineDepth);
  ScheduleLeaveAndChildren(Node, FTightList);
end;

procedure TMarkdownHtmlRenderer.WriteThematicBreak;
begin
  AppendLineBreak;
  FOutput.Append('<hr />');
  AppendLineBreak;
end;

procedure TMarkdownHtmlRenderer.WriteCodeBlock(const Node: IMarkdownCodeBlock);
var
  Language: string;
  HasLanguage: Boolean;
begin
  AppendLineBreak;
  FOutput.Append('<pre><code');

  Language := FirstInfoWord(Node.InfoString);
  HasLanguage := Node.IsFenced and (Language <> '');
  if HasLanguage then
    FOutput.Append(Format(LanguageClassFormat, [EscapeHtml(Language)]));

  FOutput.Append(TagCloseBracket);
  FOutput.Append(EscapeHtml(Node.Literal));
  FOutput.Append('</code></pre>');
  AppendLineBreak;
end;

// An alert is written the way GitHub writes it, so stylesheets made for
// GitHub's alerts apply: a div with the kind in its class and a title
// paragraph. GitHub's title also carries an icon, which is left out here.
procedure TMarkdownHtmlRenderer.EnterBlockQuote(const Node: IMarkdownNode);
var
  AlertKind: TMarkdownAlertKind;
  OpenTag: string;
  TitleParagraph: string;
begin
  ScheduleLeaveAndChildren(Node, FTightList);
  FTightList := False;

  AppendLineBreak;

  
  if TMarkdownAlerts.TryGetKind(Node, AlertKind) then
  begin
    OpenTag := Format(AlertOpenFormat, [AlertKind.CssName]);
    TitleParagraph := Format(AlertTitleFormat, [AlertKind.Title]);
    FOutput.Append(OpenTag);
    AppendLineBreak;
    FOutput.Append(TitleParagraph);
  end
  else
  begin
    FOutput.Append('<blockquote>');
  end;

  AppendLineBreak;
end;

procedure TMarkdownHtmlRenderer.EnterList(const Node: IMarkdownList);
var
  OpenTag: string;
  HasExplicitStart: Boolean;
begin
  ScheduleLeaveAndChildren(Node, FTightList);
  FTightList := Node.IsTight;

  OpenTag := '<ul>';

  if Node.IsOrdered then
  begin
    OpenTag := '<ol>';

    HasExplicitStart := (Node.StartNumber <> 1);
    if HasExplicitStart then
      OpenTag := Format(OrderedListStartFormat, [Node.StartNumber]);
  end;

  AppendLineBreak;
  FOutput.Append(OpenTag);
  AppendLineBreak;
end;

procedure TMarkdownHtmlRenderer.EnterListItem(const Node: IMarkdownNode);
begin
  FOutput.Append('<li>');

  ScheduleLeaveAndChildren(Node, FTightList);
end;

procedure TMarkdownHtmlRenderer.EnterHtmlBlock(const Node: IMarkdownText);
var
  Output: string;
begin
  Output := HtmlBlockOutput(Node.Literal);

  AppendLineBreak;
  FOutput.Append(Output);
  AppendLineBreak;
end;

// An escaped block reads as text, so it gets a paragraph as other text does,
// as commonmark-java writes it; inline HTML is escaped where it stands.
function TMarkdownHtmlRenderer.HtmlBlockOutput(const Literal: string): string;
var
  EscapedLiteral: string;
begin
  if FOptions.EscapeRawHtml then
  begin
    EscapedLiteral := EscapeHtml(Literal);
    Result := Format(EscapedHtmlBlockFormat, [EscapedLiteral]);
    Exit;
  end;

  Result := RawHtmlOutput(Literal);
end;

procedure TMarkdownHtmlRenderer.EnterTable(const Node: IMarkdownNode);
begin
  FTableInBody := False;

  AppendLineBreak;
  FOutput.Append('<table>');
  AppendLineBreak;

  ScheduleLeaveAndChildren(Node, FTightList);
end;

procedure TMarkdownHtmlRenderer.EnterTableRow(const Node: IMarkdownTableRow);
begin
  FTableInHeader := Node.IsHeader;

  if FTableInHeader then
  begin
    FOutput.Append(TableHeadOpenTag);
    AppendLineBreak;
  end
  else if not FTableInBody then
  begin
    FOutput.Append(TableBodyOpenTag);
    AppendLineBreak;
    FTableInBody := True;
  end;

  FOutput.Append('<tr>');
  AppendLineBreak;

  ScheduleLeaveAndChildren(Node, FTightList);
end;

procedure TMarkdownHtmlRenderer.EnterTableCell(const Node: IMarkdownTableCell);
var
  HasAlignment: Boolean;
begin
  FOutput.Append(Format(TableCellOpenFormat, [CurrentTableCellTag]));

  HasAlignment := (Node.Alignment <> TMarkdownTableColumnAlignment.None);
  if HasAlignment then
    FOutput.Append(Format(TableAlignAttributeFormat, [TableAlignmentNames[Node.Alignment]]));

  FOutput.Append(TagCloseBracket);

  Inc(FInlineDepth);
  ScheduleLeaveAndChildren(Node, FTightList);
end;

// A formula inside a paragraph, heading or table cell stays inline HTML, even
// when it is display math, because a div inside a p is not valid HTML. KaTeX
// and MathJax read the \( \) and \[ \] delimiters, so the span and the div
// carry the same class and the delimiters decide the style.
procedure TMarkdownHtmlRenderer.WriteMath(const Node: IMarkdownMath);
var
  IsInline: Boolean;
begin
  IsInline := (FInlineDepth > 0);
  if IsInline then
    WriteInlineMath(Node)
  else
    WriteMathBlock(Node);
end;

procedure TMarkdownHtmlRenderer.WriteInlineMath(const Node: IMarkdownMath);
var
  OpenDelimiter: string;
  CloseDelimiter: string;
begin
  OpenDelimiter := InlineMathOpen;
  CloseDelimiter := InlineMathClose;

  if Node.IsDisplay then
  begin
    OpenDelimiter := DisplayMathOpen;
    CloseDelimiter := DisplayMathClose;
  end;

  FOutput.Append(MathSpanOpenTag);
  FOutput.Append(OpenDelimiter);
  FOutput.Append(EscapeHtml(Node.Literal));
  FOutput.Append(CloseDelimiter);
  FOutput.Append(MathSpanCloseTag);
end;

procedure TMarkdownHtmlRenderer.WriteMathBlock(const Node: IMarkdownMath);
begin
  AppendLineBreak;
  FOutput.Append(MathDivOpenTag);
  FOutput.Append(DisplayMathOpen);
  FOutput.Append(LineFeed);
  FOutput.Append(EscapeHtml(Node.Literal));
  FOutput.Append(LineFeed);
  FOutput.Append(DisplayMathClose);
  FOutput.Append(MathDivCloseTag);
  AppendLineBreak;
end;

function TMarkdownHtmlRenderer.CurrentTableCellTag: string;
begin
  if FTableInHeader then
  begin
    Result := TableHeaderCellTag;
    Exit;
  end;

  Result := TableDataCellTag;
end;

// Escaping wins over UnsafeHtml, as comrak's escape option does: the stricter
// choice of the two is the one a host asked for on purpose.
function TMarkdownHtmlRenderer.RawHtmlOutput(const Literal: string): string;
begin
  if FOptions.EscapeRawHtml then
  begin
    Result := EscapeHtml(Literal);
    Exit;
  end;

  if not FOptions.AllowRawHtml then
  begin
    Result := OmittedHtmlComment;
    Exit;
  end;

  if FOptions.ApplyTagFilter then
  begin
    Result := FTagFilterRegex.Replace(Literal, EscapedLessThan);
    Exit;
  end;

  Result := Literal;
end;

procedure TMarkdownHtmlRenderer.EnterCustomInline(const Node: IMarkdownNode);
var
  Hook: IMarkdownRendererHook;
begin
  

  if TryFindHook(Node, Hook) then
    Hook.RenderEnter(FWriter, Node);

  ScheduleLeaveAndChildren(Node, FTightList);
end;

procedure TMarkdownHtmlRenderer.LeaveCustomInline(const Node: IMarkdownNode);
var
  Hook: IMarkdownRendererHook;
begin
  

  if TryFindHook(Node, Hook) then
    Hook.RenderLeave(FWriter, Node);
end;

function TMarkdownHtmlRenderer.TryFindHook(const Node: IMarkdownNode; out Hook: IMarkdownRendererHook): Boolean;
begin
  Hook := nil;

  if FHooks = nil then
  begin
    Result := False;
    Exit;
  end;

  Result := FHooks.TryGetValue((Node as IMarkdownCustomInline).NodeName, Hook);
end;

procedure TMarkdownHtmlRenderer.EnterSpan(const Node: IMarkdownNode; const OpenTag: string);
begin
  FOutput.Append(OpenTag);

  ScheduleLeaveAndChildren(Node, FTightList);
end;

procedure TMarkdownHtmlRenderer.WriteCodeSpan(const Node: IMarkdownText);
begin
  FOutput.Append('<code>');
  FOutput.Append(EscapeHtml(Node.Literal));
  FOutput.Append('</code>');
end;

procedure TMarkdownHtmlRenderer.EnterAnchor(const Node: IMarkdownLink);
var
  Href: string;
  EscapedHref: string;
  AnchorOpen: string;
  HasTitle: Boolean;
begin
  Href := DestinationOutput(Node.Destination, RejectedLinkDestination);
  EscapedHref := EscapeHtml(Href);
  AnchorOpen := Format(AnchorOpenFormat, [EscapedHref]);
  FOutput.Append(AnchorOpen);

  HasTitle := (Node.Title <> '');
  if HasTitle then
    FOutput.Append(Format(TitleAttributeFormat, [EscapeHtml(Node.Title)]));

  if FOptions.NoOpenerLinks then
    FOutput.Append(NoOpenerAttribute);

  FOutput.Append(TagCloseBracket);

  ScheduleLeaveAndChildren(Node, FTightList);
end;

procedure TMarkdownHtmlRenderer.WriteImage(const Node: IMarkdownLink);
var
  Source: string;
  EscapedSource: string;
  ImageOpen: string;
  HasTitle: Boolean;
begin
  Source := DestinationOutput(Node.Destination, RejectedImageSource);
  EscapedSource := EscapeHtml(Source);
  ImageOpen := Format(ImageOpenFormat, [EscapedSource]);
  FOutput.Append(ImageOpen);

  AppendAltText(Node);
  FOutput.Append('"');

  HasTitle := (Node.Title <> '');
  if HasTitle then
    FOutput.Append(Format(TitleAttributeFormat, [EscapeHtml(Node.Title)]));

  FOutput.Append(' />');
end;

// An allowlist of schemes applies even when unsafe links are allowed, for the
// same reason escaping wins over UnsafeHtml. A destination it rejects becomes
// RejectedValue, so a link stays a link that leads nowhere.
function TMarkdownHtmlRenderer.DestinationOutput(const Destination, RejectedValue: string): string;
var
  IsAllowed: Boolean;
begin
  if FOptions.RestrictUrlSchemes then
  begin
    IsAllowed := (TMarkdownUrlSafety.IsAllowed(Destination, FOptions.AllowedUrlSchemes));
    if IsAllowed then
      Result := Destination
    else
      Result := RejectedValue;
    Exit;
  end;

  if FOptions.AllowUnsafeLinks then
  begin
    Result := Destination;
    Exit;
  end;

  Result := TMarkdownUrlSafety.Sanitized(Destination);
end;

procedure TMarkdownHtmlRenderer.AppendAltText(const Node: IMarkdownNode);
var
  Pending: TStack<IMarkdownNode>;
  Current: IMarkdownNode;
begin
  Pending := TStack<IMarkdownNode>.Create;
  try
    PushChildrenReversed(Pending, Node);

    while Pending.Count > 0 do
    begin
      Current := Pending.Pop;

      case Current.Kind of
        // Alt text is the value of an attribute, so everything landing here is
        // plain text: markup is escaped whatever the raw HTML option says,
        // because an unescaped quote would end the attribute, and a line break
        // becomes a space because an attribute carries no lines.
        TMarkdownNodeKind.Text, TMarkdownNodeKind.CodeSpan, TMarkdownNodeKind.InlineHtml, TMarkdownNodeKind.Math:
          FOutput.Append(EscapeHtml((Current as IMarkdownText).Literal));
        TMarkdownNodeKind.SoftLineBreak, TMarkdownNodeKind.HardLineBreak:
          FOutput.Append(Space);
      else
        PushChildrenReversed(Pending, Current);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

class procedure TMarkdownHtmlRenderer.PushChildrenReversed(const Pending: TStack<IMarkdownNode>;
                                                           const Node: IMarkdownNode);
var
  Index: Integer;
begin
  for Index := Node.ChildCount - 1 downto 0 do
  begin
    Pending.Push(Node.Children[Index]);
  end;
end;

procedure TMarkdownHtmlRenderer.WriteHardBreak;
begin
  FOutput.Append('<br />');
  FOutput.Append(LineFeed);
end;

procedure TMarkdownHtmlRenderer.LeaveParagraph;
begin
  Dec(FInlineDepth);

  if FTightList then
    Exit;

  FOutput.Append('</p>');
  AppendLineBreak;
end;

procedure TMarkdownHtmlRenderer.LeaveHeading(const Node: IMarkdownHeading);
begin
  Dec(FInlineDepth);

  FOutput.Append(Format(HeadingCloseFormat, [Node.Level]));
  AppendLineBreak;
end;

procedure TMarkdownHtmlRenderer.LeaveBlockQuote(const Node: IMarkdownNode; const WasTightList: Boolean);
var
  AlertKind: TMarkdownAlertKind;
begin
  AppendLineBreak;

  
  if TMarkdownAlerts.TryGetKind(Node, AlertKind) then
    FOutput.Append(AlertCloseTag)
  else
    FOutput.Append('</blockquote>');

  AppendLineBreak;

  FTightList := WasTightList;
end;

procedure TMarkdownHtmlRenderer.LeaveList(const Node: IMarkdownList; const WasTightList: Boolean);
var
  CloseTag: string;
begin
  CloseTag := '</ul>';
  if Node.IsOrdered then
    CloseTag := '</ol>';

  AppendLineBreak;
  FOutput.Append(CloseTag);
  AppendLineBreak;

  FTightList := WasTightList;
end;

procedure TMarkdownHtmlRenderer.LeaveListItem;
begin
  FOutput.Append('</li>');
  AppendLineBreak;
end;

procedure TMarkdownHtmlRenderer.LeaveTable;
begin
  if FTableInBody then
  begin
    FOutput.Append(TableBodyCloseTag);
    AppendLineBreak;
    FTableInBody := False;
  end;

  FOutput.Append('</table>');
  AppendLineBreak;
end;

procedure TMarkdownHtmlRenderer.LeaveTableRow(const Node: IMarkdownTableRow);
begin
  FOutput.Append('</tr>');
  AppendLineBreak;

  if Node.IsHeader then
  begin
    FOutput.Append(TableHeadCloseTag);
    AppendLineBreak;
  end;
end;

procedure TMarkdownHtmlRenderer.LeaveTableCell;
begin
  Dec(FInlineDepth);

  FOutput.Append(Format(TableCellCloseFormat, [CurrentTableCellTag]));
  AppendLineBreak;
end;

procedure TMarkdownHtmlRenderer.ScheduleLeaveAndChildren(const Node: IMarkdownNode; const WasTightList: Boolean);
var
  LeaveTask: TRenderTask;
  Index: Integer;
  EnterTask: TRenderTask;
begin
  
  LeaveTask.Node := Node;
  LeaveTask.Phase := TRenderPhase.Leave;
  LeaveTask.WasTightList := WasTightList;
  FTasks.Push(LeaveTask);

  for Index := Node.ChildCount - 1 downto 0 do
  begin
    
    EnterTask.Node := Node.Children[Index];
    EnterTask.Phase := TRenderPhase.Enter;
    EnterTask.WasTightList := False;

    FTasks.Push(EnterTask);
  end;
end;

procedure TMarkdownHtmlRenderer.AppendLineBreak;
var
  IsAtLineStart: Boolean;
begin
  IsAtLineStart := (FOutput.Length = 0) or (FOutput.Chars[FOutput.Length - 1] = LineFeed);
  if not IsAtLineStart then
    FOutput.Append(LineFeed);
end;

class function TMarkdownHtmlRenderer.FirstInfoWord(const InfoString: string): string;
var
  Parts: TArray<string>;
begin
  Parts := InfoString.Split(InfoSplitChars, TStringSplitOptions.ExcludeEmpty);

  if Length(Parts) = 0 then
  begin
    Result := '';
    Exit;
  end;

  Result := Parts[0];
end;

class function TMarkdownHtmlRenderer.EscapeCore(const Value: string; const EscapeApostrophe: Boolean): string;
var
  WithAmpersands: string;
  WithLessThan: string;
  WithGreaterThan: string;
begin
  WithAmpersands := StringReplace(Value, '&', EscapedAmpersand, [rfReplaceAll]);
  WithLessThan := StringReplace(WithAmpersands, '<', EscapedLessThan, [rfReplaceAll]);
  WithGreaterThan := StringReplace(WithLessThan, '>', EscapedGreaterThan, [rfReplaceAll]);

  Result := StringReplace(WithGreaterThan, '"', EscapedQuote, [rfReplaceAll]);

  if EscapeApostrophe then
    Result := StringReplace(Result, '''', EscapedApostrophe, [rfReplaceAll]);
end;

class function TMarkdownHtmlRenderer.EscapeHtml(const Value: string): string;
begin
  Result := EscapeCore(Value, False);
end;

constructor TRendererHtmlWriter.Create(const Output: TStringBuilder);
begin
  inherited Create;

  FOutput := Output;
end;

procedure TRendererHtmlWriter.WriteRaw(const Html: string);
begin
  FOutput.Append(Html);
end;

procedure TRendererHtmlWriter.WriteEscaped(const Text: string);
begin
  FOutput.Append(TMarkdownHtmlRenderer.EscapeHtml(Text));
end;

function TRendererHtmlWriter.EscapeAttribute(const Value: string): string;
begin
  Result := TMarkdownHtmlRenderer.EscapeCore(Value, True);
end;

procedure TRendererHtmlWriter.WriteAttribute(const Name, Value: string);
begin
  FOutput.Append(' ');
  FOutput.Append(Name);
  FOutput.Append('="');
  FOutput.Append(EscapeAttribute(Value));
  FOutput.Append('"');
end;

end.
