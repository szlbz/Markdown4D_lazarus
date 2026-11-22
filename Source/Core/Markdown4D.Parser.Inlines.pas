{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Parser.Inlines;

{$SCOPEDENUMS ON}

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  Generics.Collections,
  Markdown4D.Compat.RegEx,
  Markdown4D.Defines,
  Markdown4D.Extensions.Interfaces,
  Markdown4D.Pipeline.Configuration,
  Markdown4D.Parser.References,
  Markdown4D.Parser.SourceMap,
  Markdown4D.Parser.LinkSyntax,
  Markdown4D.Parser.HtmlBlocks,
  Markdown4D.Ast.Interfaces,
  Markdown4D.Ast;

type
  TInlineChainNode = class
  private
    FValue: IMarkdownNode;
    FPrev: TInlineChainNode;
    FNext: TInlineChainNode;

  public
    constructor Create(const Value: IMarkdownNode);
    property Value: IMarkdownNode read FValue;
    property Prev: TInlineChainNode read FPrev write FPrev;
    property Next: TInlineChainNode read FNext write FNext;
  end;

  TInlineDelimiter = class
  private
    FNode: TMarkdownTextNode;
    FChainNode: TInlineChainNode;
    FDelimiterChar: Char;
    FCount: Integer;
    FOriginalCount: Integer;
    FCanOpen: Boolean;
    FCanClose: Boolean;
    FProcessor: IMarkdownDelimiterProcessor;
    FPrev: TInlineDelimiter;
    FNext: TInlineDelimiter;

  public
    constructor Create(const Node: TMarkdownTextNode; const ChainNode: TInlineChainNode;
                       const DelimiterChar: Char; const Count: Integer; const CanOpen, CanClose: Boolean;
                       const Processor: IMarkdownDelimiterProcessor);
    property Node: TMarkdownTextNode read FNode;
    property ChainNode: TInlineChainNode read FChainNode;
    property DelimiterChar: Char read FDelimiterChar;
    property Count: Integer read FCount write FCount;
    property OriginalCount: Integer read FOriginalCount;
    property CanOpen: Boolean read FCanOpen;
    property CanClose: Boolean read FCanClose;
    property Processor: IMarkdownDelimiterProcessor read FProcessor;
    property Prev: TInlineDelimiter read FPrev write FPrev;
    property Next: TInlineDelimiter read FNext write FNext;
  end;

  TInlineBracket = class
  private
    FChainNode: TInlineChainNode;
    FContentStart: Integer;
    FDelimiterBottom: TInlineDelimiter;
    FIsImage: Boolean;
    FActive: Boolean;
    FBracketAfter: Boolean;

  public
    constructor Create(const ChainNode: TInlineChainNode; const ContentStart: Integer;
                       const DelimiterBottom: TInlineDelimiter; const IsImage: Boolean);
    property ChainNode: TInlineChainNode read FChainNode;
    property ContentStart: Integer read FContentStart;
    property DelimiterBottom: TInlineDelimiter read FDelimiterBottom;
    property IsImage: Boolean read FIsImage;
    property Active: Boolean read FActive write FActive;
    property BracketAfter: Boolean read FBracketAfter write FBracketAfter;
  end;

  TM4DGen1 = TObjectDictionary<Char, TList<IMarkdownInlineParser>>;
  TInlineParser = class
  private
    type
      TDelimiterRun = record
        Length: Integer;
        CanOpen: Boolean;
        CanClose: Boolean;
      end;
    const
      ImageOpenerText = '![';
      MailtoPrefix = 'mailto:';
      UrlAutolinkSchemes: array[0..2] of string = (HttpSchemePrefix, HttpsSchemePrefix, 'ftp://');
      HardBreakSpaceCount = 2;
      StrongDelimiterCount = 2;
      CollapsedLabelLength = 2;
      TaskMarkerLength = 3;
      RuleOfThreeDivisor = 3;
      OpenersBottomBucketsPerChar = 6;
      MaxMathDelimiterLength = 2;
      BacktickMathCloser = Backtick + Dollar;
      // Anchored with \G instead of ^ so each pattern can be matched in place at
      // the current index. Copying the remainder of the content first would cost
      // a full copy per '<', which is quadratic on a paragraph carrying many.
      UriAutolinkPattern = '\G<[A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\x00-\x20]*>';
      EmailAutolinkPattern = '\G<([a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
        + '(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>';
      HtmlTagPattern = '\G(?:' + THtmlBlockScanner.OpenTag + '|' + THtmlBlockScanner.CloseTag
        + '|<!-->|<!--->|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<![A-Za-z][^>]*>|<!\[CDATA\[[\s\S]*?\]\]>)';
    var
      FConfiguration: TMarkdownPipelineConfiguration;
      FContext: IMarkdownInlineParserContext;
      FTriggerMap: TM4DGen1;
      FParent: TMarkdownAstNode;
      FContent: string;
      FIndex: Integer;
      FTextBuffer: TStringBuilder;
      FFirstInline: TInlineChainNode;
      FLastInline: TInlineChainNode;
      FFirstDelimiter: TInlineDelimiter;
      FLastDelimiter: TInlineDelimiter;
      FOpenersBottom: TDictionary<Integer, TInlineDelimiter>;
      FBrackets: TObjectList<TInlineBracket>;
      FReferenceMap: TLinkReferenceMap;
      FSourceMap: TMarkdownContentSourceMap;
      FTextStart: Integer;
      FTextEnd: Integer;
      FLinkScanner: TLinkSyntaxScanner;
      FUriAutolinkRegex: TRegEx;
      FEmailAutolinkRegex: TRegEx;
      FHtmlTagRegex: TRegEx;
      FTaskListCandidate: Boolean;
    procedure BuildTriggerMap;
    function TryDispatch(const Current: Char): Boolean;
    function TryHandleCustomDelimiterRun(const Processor: IMarkdownDelimiterProcessor): Boolean;
    procedure HandleBackslash;
    procedure HandleLineEnding;
    procedure HandleBackticks;
    procedure EmitCodeSpan(const RawContent: string; const SyntaxStart, SyntaxEnd: Integer);
    procedure HandleLessThan;
    procedure EmitAutolink(const LabelText, Destination: string; const SyntaxStart: Integer;
                           const IsBracketed: Boolean);
    procedure HandleAmpersand;
    function TrimTrailingSpacesFromBuffer: Integer;
    procedure HandleDelimiterRun;
    function ScanDelimiterRun: TDelimiterRun;
    procedure EmitDelimiterRun(const Processor: IMarkdownDelimiterProcessor; const Run: TDelimiterRun);
    function CharBefore(const Index: Integer): Char;
    function CharAfter(const Index: Integer): Char;
    procedure HandleOpenBracket;
    procedure HandleBang;
    procedure PushBracket(const ChainNode: TInlineChainNode; const ContentStart: Integer; const IsImage: Boolean);
    procedure HandleCloseBracket;
    procedure AbandonBracket(const CloserPos: Integer);
    function TryParseInlineLinkSuffix(out Destination, Title: string): Boolean;
    function TryResolveReference(const Opener: TInlineBracket; const CloserPos: Integer;
                                 out Destination, Title: string): Boolean;
    procedure EmitLink(const Opener: TInlineBracket; const Destination, Title: string);
    procedure CloseBracketsAfterLink(const IsImage: Boolean);
    function TryParseTaskListMarker: Boolean;
    function TryParseWwwAutolink: Boolean;
    function TryParseUrlAutolink: Boolean;
    function TryParseEmailAutolink: Boolean;
    function TryScanEmailDomain(out DomainEnd: Integer): Boolean;
    function TryConsumePrecedingChars(const Count: Integer): Boolean;
    procedure RemoveTrailingInlineNode;
    function TryParseMath: Boolean;
    function TryParseBacktickMath: Boolean;
    function DollarRunLength(const StartIndex: Integer): Integer;
    function IsMathOpener(const ContentStart: Integer): Boolean;
    function TryFindMathCloser(const ContentStart, DelimiterLength: Integer; out ContentEnd: Integer): Boolean;
    function IsMathCloser(const ContentStart, CloserStart, DelimiterLength: Integer): Boolean;
    procedure EmitMath(const Literal: string; const IsDisplay: Boolean; const SyntaxStart, SyntaxEnd: Integer);
    function IsExtendedAutolinkBoundary: Boolean;
    function TryScanAutolinkDomain(const StartIndex: Integer; out DomainEnd: Integer): Boolean;
    function ScanExtendedAutolinkEnd(const StartIndex: Integer): Integer;
    function ApplyExtendedAutolinkTrailing(const StartIndex, CandidateEnd: Integer): Integer;
    class function IsAsciiAlphaNumeric(const Value: Char): Boolean;
    class function IsAsciiLetter(const Value: Char): Boolean;
    class function IsEmailUserChar(const Value: Char): Boolean;
    procedure ProcessEmphasis(const StackBottom: TInlineDelimiter);
    function FirstDelimiterAbove(const StackBottom: TInlineDelimiter): TInlineDelimiter;
    function FindOpener(const Closer, StackBottom: TInlineDelimiter): TInlineDelimiter;
    function OpenersBottomKey(const Closer: TInlineDelimiter): Integer;
    class function IsRuleOfThreeViolated(const Opener, Closer: TInlineDelimiter): Boolean;
    function ApplyMatch(const Opener, Closer: TInlineDelimiter): TInlineDelimiter;
    procedure WrapNodesInContainer(const Opener, Closer: TInlineDelimiter; const Container: TMarkdownAstNode);
    procedure ApplyContainerSegment(const Container: TMarkdownAstNode; const Opener, Closer: TInlineDelimiter;
                                    const UseCount: Integer);
    procedure ShrinkDelimiter(const Delimiter: TInlineDelimiter; const UseCount: Integer; const FromStart: Boolean);
    function RemoveDepletedDelimiters(const Opener, Closer: TInlineDelimiter): TInlineDelimiter;
    procedure AttachInlinesToParent;
    procedure FlushText;
    procedure AddBreak(const Kind: TMarkdownNodeKind; const ContentStart, ContentEnd: Integer);
    procedure BufferText(const Value: string; const ContentStart, ContentEnd: Integer);
    procedure ApplySegment(const Node: TMarkdownAstNode; const ContentStart, ContentEnd: Integer);
    procedure ApplyLinkSegment(const Node: TMarkdownAstNode; const StartOffset: Integer);
    procedure ShrinkSegmentEnd(const Node: TMarkdownAstNode; const Count: Integer);
    function AppendInline(const Node: IMarkdownNode): TInlineChainNode;
    procedure InsertInlineAfter(const ChainNode: TInlineChainNode; const Node: IMarkdownNode);
    procedure RemoveInlineChainNode(const ChainNode: TInlineChainNode);
    procedure ClearInlineChain;
    procedure AppendDelimiter(const Delimiter: TInlineDelimiter);
    procedure RemoveDelimiter(const Delimiter: TInlineDelimiter);
    procedure RemoveDelimitersAbove(const StackBottom: TInlineDelimiter);
    procedure ClearDelimiterStack;
    class function IsUnicodeWhitespace(const Value: Char): Boolean;
    class function IsUnicodePunctuation(const Value: Char): Boolean;

  public
    constructor Create(const Configuration: TMarkdownPipelineConfiguration);
    destructor Destroy; override;
    procedure ParseInto(const Parent: TMarkdownAstNode; const Content: string;
                        const ReferenceMap: TLinkReferenceMap; const SourceMap: TMarkdownContentSourceMap = nil);
    property TaskListCandidate: Boolean read FTaskListCandidate write FTaskListCandidate;
  end;

  TInlineParserContext = class(TInterfacedObject, IMarkdownInlineParserContext)
  private
    FEngine: TInlineParser;

  public
    constructor Create(const Engine: TInlineParser);
    function GetContent: string;
    function GetPosition: Integer;
    property Engine: TInlineParser read FEngine;
  end;

  TCommonMarkInlineKind = (Backslash, LineEnding, EmphasisRun, CodeSpan, AngleBracket, Entity, LinkOpener,
    ImageOpener, LinkCloser);

  TCommonMarkInlineParser = class(TInterfacedObject, IMarkdownInlineParser)
  private
    const
      Names: array[TCommonMarkInlineKind] of string = ('backslash', 'linebreak', 'emphasis', 'codespan',
        'anglebracket', 'entity', 'linkopener', 'imageopener', 'linkcloser');
    var
      FKind: TCommonMarkInlineKind;

  public
    constructor Create(const Kind: TCommonMarkInlineKind);
    function GetName: string;
    function TryParse(const Context: IMarkdownInlineParserContext): Boolean;
  end;

  TMathInlineParser = class(TInterfacedObject, IMarkdownInlineParser)
  public
    const
      MathParserName = 'math';
    function GetName: string;
    function TryParse(const Context: IMarkdownInlineParserContext): Boolean;
  end;

  TGfmInlineKind = (TaskListMarker, WwwAutolink, UrlAutolink, EmailAutolink);

  TGfmInlineParser = class(TInterfacedObject, IMarkdownInlineParser)
  private
    const
      Names: array[TGfmInlineKind] of string = ('tasklistmarker', 'wwwautolink', 'urlautolink', 'emailautolink');
    var
      FKind: TGfmInlineKind;

  public
    const
      TaskCheckedNodeName = 'gfm-task-checked';
      TaskUncheckedNodeName = 'gfm-task-unchecked';
      StrikethroughNodeName = 'del';
    constructor Create(const Kind: TGfmInlineKind);
    function GetName: string;
    function TryParse(const Context: IMarkdownInlineParserContext): Boolean;
  end;

implementation

uses
  character,
  Math,
  Markdown4D.Text.Unescape;

constructor TInlineChainNode.Create(const Value: IMarkdownNode);
begin
  inherited Create;

  FValue := Value;
end;

constructor TInlineDelimiter.Create(const Node: TMarkdownTextNode; const ChainNode: TInlineChainNode;
                                    const DelimiterChar: Char; const Count: Integer;
                                    const CanOpen, CanClose: Boolean;
                                    const Processor: IMarkdownDelimiterProcessor);
begin
  inherited Create;

  FNode := Node;
  FChainNode := ChainNode;
  FDelimiterChar := DelimiterChar;
  FCount := Count;
  FOriginalCount := Count;
  FCanOpen := CanOpen;
  FCanClose := CanClose;
  FProcessor := Processor;
end;

constructor TInlineBracket.Create(const ChainNode: TInlineChainNode; const ContentStart: Integer;
                                  const DelimiterBottom: TInlineDelimiter; const IsImage: Boolean);
begin
  inherited Create;

  FChainNode := ChainNode;
  FContentStart := ContentStart;
  FDelimiterBottom := DelimiterBottom;
  FIsImage := IsImage;
  FActive := True;
  FBracketAfter := False;
end;

constructor TInlineParser.Create(const Configuration: TMarkdownPipelineConfiguration);
begin
  inherited Create;

  FConfiguration := Configuration;
  FContext := TInlineParserContext.Create(Self);
  FTriggerMap := TM4DGen1.Create([doOwnsValues]);
  FTextBuffer := TStringBuilder.Create;
  FOpenersBottom := TDictionary<Integer, TInlineDelimiter>.Create;
  FBrackets := TObjectList<TInlineBracket>.Create(True);
  FLinkScanner := TLinkSyntaxScanner.Create;
  FUriAutolinkRegex := TRegEx.Create(UriAutolinkPattern);
  FEmailAutolinkRegex := TRegEx.Create(EmailAutolinkPattern);
  FHtmlTagRegex := TRegEx.Create(HtmlTagPattern);

  BuildTriggerMap;
end;

destructor TInlineParser.Destroy;
begin
  ClearDelimiterStack;
  ClearInlineChain;

  FLinkScanner.Free;
  FBrackets.Free;
  FOpenersBottom.Free;
  FTextBuffer.Free;
  FTriggerMap.Free;

  inherited Destroy;
end;

procedure TInlineParser.BuildTriggerMap;
var
  Registration: TMarkdownInlineParserRegistration;
  Trigger: Char;
  Parsers: TList<IMarkdownInlineParser>;
begin
  for Registration in FConfiguration.InlineParsers do
  begin
    for Trigger in Registration.TriggerCharacters do
    begin
      

      if not FTriggerMap.TryGetValue(Trigger, Parsers) then
      begin
        Parsers := TList<IMarkdownInlineParser>.Create;
        FTriggerMap.Add(Trigger, Parsers);
      end;

      Parsers.Add(Registration.Parser);
    end;
  end;
end;

procedure TInlineParser.ParseInto(const Parent: TMarkdownAstNode; const Content: string;
                                  const ReferenceMap: TLinkReferenceMap; const SourceMap: TMarkdownContentSourceMap);
var
  Current: Char;
begin
  FParent := Parent;
  FContent := Content;
  FReferenceMap := ReferenceMap;
  FSourceMap := SourceMap;
  FIndex := 1;
  FTextStart := 1;
  FTextEnd := 1;
  FTextBuffer.Clear;
  ClearDelimiterStack;
  ClearInlineChain;
  FBrackets.Clear;

  while FIndex <= System.Length(FContent) do
  begin
    Current := FContent[FIndex];

    if not TryDispatch(Current) then
    begin
      BufferText(Current, FIndex, FIndex + 1);
      Inc(FIndex);
    end;
  end;

  FlushText;

  ProcessEmphasis(nil);
  AttachInlinesToParent;
end;

function TInlineParser.TryDispatch(const Current: Char): Boolean;
var
  Parsers: TList<IMarkdownInlineParser>;
  Parser: IMarkdownInlineParser;
  Processor: IMarkdownDelimiterProcessor;
begin
  

  if FTriggerMap.TryGetValue(Current, Parsers) then
  begin
    for Parser in Parsers do
    begin
      if Parser.TryParse(FContext) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

  

  if FConfiguration.DelimiterProcessors.TryGetValue(Current, Processor) then
  begin
    Result := TryHandleCustomDelimiterRun(Processor);
    Exit;
  end;

  Result := False;
end;

function TInlineParser.TryHandleCustomDelimiterRun(const Processor: IMarkdownDelimiterProcessor): Boolean;
var
  Run: TDelimiterRun;
begin
  Run := ScanDelimiterRun;
  if Run.Length < Processor.MinimumLength then
  begin
    Result := False;
    Exit;
  end;

  EmitDelimiterRun(Processor, Run);
  Result := True;
end;

procedure TInlineParser.HandleBackslash;
var
  HasNext: Boolean;
  Next: Char;
begin
  HasNext := (FIndex < System.Length(FContent));
  if not HasNext then
  begin
    BufferText(Backslash, FIndex, FIndex + 1);
    Inc(FIndex);
    Exit;
  end;

  Next := FContent[FIndex + 1];

  if Next = LineFeed then
  begin
    FlushText;
    AddBreak(TMarkdownNodeKind.HardLineBreak, FIndex, FIndex + 2);
    Inc(FIndex, 2);
  end
  else if TMarkdownUnescape.IsAsciiPunctuation(Next) then
  begin
    BufferText(Next, FIndex, FIndex + 2);
    Inc(FIndex, 2);
  end
  else
  begin
    BufferText(Backslash, FIndex, FIndex + 1);
    Inc(FIndex);
  end;
end;

procedure TInlineParser.HandleLineEnding;
var
  RemovedSpaces: Integer;
  IsHardBreak: Boolean;
begin
  RemovedSpaces := TrimTrailingSpacesFromBuffer;

  FlushText;

  IsHardBreak := (RemovedSpaces >= HardBreakSpaceCount);
  if IsHardBreak then
  begin
    AddBreak(TMarkdownNodeKind.HardLineBreak, FIndex - RemovedSpaces, FIndex + 1);
  end
  else
  begin
    AddBreak(TMarkdownNodeKind.SoftLineBreak, FIndex, FIndex + 1);
  end;

  Inc(FIndex);
end;

function TInlineParser.TrimTrailingSpacesFromBuffer: Integer;
begin
  Result := 0;

  while (FTextBuffer.Length > 0) and (FTextBuffer.Chars[FTextBuffer.Length - 1] = Space) do
  begin
    FTextBuffer.Length := FTextBuffer.Length - 1;
    Inc(Result);
  end;

  Dec(FTextEnd, Result);
end;

procedure TInlineParser.HandleBackticks;
var
  RunStart: Integer;
  RunEnd: Integer;
  RunLength: Integer;
  SearchIndex: Integer;
  CloserEnd: Integer;
  CloserLength: Integer;
begin
  RunStart := FIndex;
  RunEnd := FIndex;

  while (RunEnd < System.Length(FContent)) and (FContent[RunEnd + 1] = Backtick) do
  begin
    Inc(RunEnd);
  end;

  RunLength := (RunEnd - RunStart + 1);
  SearchIndex := RunEnd + 1;

  while SearchIndex <= System.Length(FContent) do
  begin
    if FContent[SearchIndex] <> Backtick then
    begin
      Inc(SearchIndex);
      Continue;
    end;

    CloserEnd := SearchIndex;

    while (CloserEnd < System.Length(FContent)) and (FContent[CloserEnd + 1] = Backtick) do
    begin
      Inc(CloserEnd);
    end;

    CloserLength := (CloserEnd - SearchIndex + 1);
    if CloserLength = RunLength then
    begin
      EmitCodeSpan(Copy(FContent, RunEnd + 1, SearchIndex - RunEnd - 1), RunStart, CloserEnd + 1);
      FIndex := CloserEnd + 1;
      Exit;
    end;

    SearchIndex := CloserEnd + 1;
  end;

  BufferText(StringOfChar(Backtick, RunLength), RunStart, RunEnd + 1);
  FIndex := RunEnd + 1;
end;

procedure TInlineParser.EmitCodeSpan(const RawContent: string; const SyntaxStart, SyntaxEnd: Integer);
var
  Content: string;
  HasNonSpace: Boolean;
  CanStripPadding: Boolean;
  Node: TMarkdownTextNode;
begin
  Content := StringReplace(RawContent, LineFeed, Space, [rfReplaceAll]);

  HasNonSpace := (Content.Trim([Space]) <> '');
  CanStripPadding := HasNonSpace and (System.Length(Content) >= 2) and (Content[1] = Space) and
    (Content[System.Length(Content)] = Space);
  if CanStripPadding then
    Content := Copy(Content, 2, System.Length(Content) - 2);

  FlushText;

  Node := TMarkdownTextNode.Create(TMarkdownNodeKind.CodeSpan, Content);
  ApplySegment(Node, SyntaxStart, SyntaxEnd);

  AppendInline(Node);
end;

procedure TInlineParser.HandleLessThan;
var
  UriMatch: TMatch;
  Uri: string;
  EmailMatch: TMatch;
  Email: string;
  TagMatch: TMatch;
  HtmlNode: TMarkdownTextNode;
begin
  UriMatch := FUriAutolinkRegex.Match(FContent, FIndex);
  if UriMatch.Success then
  begin
    Uri := Copy(UriMatch.Value, 2, UriMatch.Length - 2);
    EmitAutolink(Uri, TMarkdownUnescape.NormalizeUri(Uri), FIndex, True);
    Inc(FIndex, UriMatch.Length);
    Exit;
  end;

  EmailMatch := FEmailAutolinkRegex.Match(FContent, FIndex);
  if EmailMatch.Success then
  begin
    Email := Copy(EmailMatch.Value, 2, EmailMatch.Length - 2);
    EmitAutolink(Email, TMarkdownUnescape.NormalizeUri(MailtoPrefix + Email), FIndex, True);
    Inc(FIndex, EmailMatch.Length);
    Exit;
  end;

  TagMatch := FHtmlTagRegex.Match(FContent, FIndex);
  if TagMatch.Success then
  begin
    FlushText;

    HtmlNode := TMarkdownTextNode.Create(TMarkdownNodeKind.InlineHtml, TagMatch.Value);
    ApplySegment(HtmlNode, FIndex, FIndex + TagMatch.Length);

    AppendInline(HtmlNode);
    Inc(FIndex, TagMatch.Length);
    Exit;
  end;

  BufferText(LessThan, FIndex, FIndex + 1);
  Inc(FIndex);
end;

// A bracketed autolink is its label between a pair of angle brackets, an
// extended one is the label and nothing else. Either way the label follows the
// source character for character, so its span falls out of its length.
procedure TInlineParser.EmitAutolink(const LabelText, Destination: string; const SyntaxStart: Integer;
                                     const IsBracketed: Boolean);
var
  BracketWidth: Integer;
  LabelStart: Integer;
  LabelEnd: Integer;
  Node: TMarkdownLinkNode;
  LabelNode: TMarkdownTextNode;
begin
  FlushText;

  BracketWidth := 0;
  if IsBracketed then
    BracketWidth := 1;

  LabelStart := SyntaxStart + BracketWidth;
  LabelEnd := LabelStart + System.Length(LabelText);

  Node := TMarkdownLinkNode.Create(TMarkdownNodeKind.Autolink, Destination, '');
  ApplySegment(Node, SyntaxStart, LabelEnd + BracketWidth);

  LabelNode := TMarkdownTextNode.Create(TMarkdownNodeKind.Text, LabelText);
  ApplySegment(LabelNode, LabelStart, LabelEnd);

  Node.AddChild(LabelNode);

  AppendInline(Node);
end;

procedure TInlineParser.HandleAmpersand;
var
  Decoded: string;
  Consumed: Integer;
begin
  
  

  if TMarkdownUnescape.TryDecodeEntityAt(FContent, FIndex, Decoded, Consumed) then
  begin
    BufferText(Decoded, FIndex, FIndex + Consumed);
    Inc(FIndex, Consumed);
    Exit;
  end;

  BufferText(Ampersand, FIndex, FIndex + 1);
  Inc(FIndex);
end;

procedure TInlineParser.HandleDelimiterRun;
begin
  EmitDelimiterRun(nil, ScanDelimiterRun);
end;

function TInlineParser.ScanDelimiterRun: TDelimiterRun;
var
  DelimiterChar: Char;
  RunStart: Integer;
  RunEnd: Integer;
  BeforeChar: Char;
  AfterChar: Char;
  FollowedByWhitespace: Boolean;
  FollowedByPunctuation: Boolean;
  PrecededByWhitespace: Boolean;
  PrecededByPunctuation: Boolean;
  LeftFlanking: type of ((not FollowedByWhitespace) and
    ((not FollowedByPunctuation) or PrecededByWhitespace or PrecededByPunctuation));
  RightFlanking: type of ((not PrecededByWhitespace) and
    ((not PrecededByPunctuation) or FollowedByWhitespace or FollowedByPunctuation));
  IsUnderscoreRun: Boolean;
begin
  DelimiterChar := FContent[FIndex];
  RunStart := FIndex;
  RunEnd := FIndex;

  while (RunEnd < System.Length(FContent)) and (FContent[RunEnd + 1] = DelimiterChar) do
  begin
    Inc(RunEnd);
  end;

  Result.Length := (RunEnd - RunStart + 1);

  BeforeChar := CharBefore(RunStart);
  AfterChar := CharAfter(RunEnd);
  FollowedByWhitespace := IsUnicodeWhitespace(AfterChar);
  FollowedByPunctuation := IsUnicodePunctuation(AfterChar);
  PrecededByWhitespace := IsUnicodeWhitespace(BeforeChar);
  PrecededByPunctuation := IsUnicodePunctuation(BeforeChar);
  LeftFlanking := (not FollowedByWhitespace) and
    ((not FollowedByPunctuation) or PrecededByWhitespace or PrecededByPunctuation);
  RightFlanking := (not PrecededByWhitespace) and
    ((not PrecededByPunctuation) or FollowedByWhitespace or FollowedByPunctuation);

  Result.CanOpen := LeftFlanking;
  Result.CanClose := RightFlanking;

  IsUnderscoreRun := (DelimiterChar = Underscore);
  if IsUnderscoreRun then
  begin
    Result.CanOpen := LeftFlanking and ((not RightFlanking) or PrecededByPunctuation);
    Result.CanClose := RightFlanking and ((not LeftFlanking) or FollowedByPunctuation);
  end;
end;

procedure TInlineParser.EmitDelimiterRun(const Processor: IMarkdownDelimiterProcessor; const Run: TDelimiterRun);
var
  DelimiterChar: Char;
  Node: TMarkdownTextNode;
  ChainNode: TInlineChainNode;
begin
  FlushText;

  DelimiterChar := FContent[FIndex];
  Node := TMarkdownTextNode.Create(TMarkdownNodeKind.Text, StringOfChar(DelimiterChar, Run.Length));
  ApplySegment(Node, FIndex, FIndex + Run.Length);

  ChainNode := AppendInline(Node);
  AppendDelimiter(TInlineDelimiter.Create(Node, ChainNode, DelimiterChar, Run.Length, Run.CanOpen, Run.CanClose,
    Processor));

  Inc(FIndex, Run.Length);
end;

function TInlineParser.CharBefore(const Index: Integer): Char;
var
  AtContentStart: Boolean;
begin
  AtContentStart := (Index <= 1);
  if AtContentStart then
  begin
    Result := LineFeed;
    Exit;
  end;

  Result := FContent[Index - 1];
end;

function TInlineParser.CharAfter(const Index: Integer): Char;
var
  AtContentEnd: Boolean;
begin
  AtContentEnd := (Index >= System.Length(FContent));
  if AtContentEnd then
  begin
    Result := LineFeed;
    Exit;
  end;

  Result := FContent[Index + 1];
end;

procedure TInlineParser.HandleOpenBracket;
var
  OpenerNode: TMarkdownTextNode;
  ChainNode: TInlineChainNode;
begin
  FlushText;

  OpenerNode := TMarkdownTextNode.Create(TMarkdownNodeKind.Text, OpenBracket);
  ApplySegment(OpenerNode, FIndex, FIndex + 1);

  ChainNode := AppendInline(OpenerNode);
  PushBracket(ChainNode, FIndex + 1, False);

  Inc(FIndex);
end;

procedure TInlineParser.HandleBang;
var
  StartsImage: Boolean;
  OpenerNode: TMarkdownTextNode;
  ChainNode: TInlineChainNode;
begin
  StartsImage := (FIndex < System.Length(FContent)) and (FContent[FIndex + 1] = OpenBracket);
  if not StartsImage then
  begin
    BufferText(ExclamationMark, FIndex, FIndex + 1);
    Inc(FIndex);
    Exit;
  end;

  FlushText;

  OpenerNode := TMarkdownTextNode.Create(TMarkdownNodeKind.Text, ImageOpenerText);
  ApplySegment(OpenerNode, FIndex, FIndex + 2);

  ChainNode := AppendInline(OpenerNode);
  PushBracket(ChainNode, FIndex + 2, True);

  Inc(FIndex, 2);
end;

procedure TInlineParser.PushBracket(const ChainNode: TInlineChainNode; const ContentStart: Integer;
                                    const IsImage: Boolean);
var
  HasOpenBrackets: Boolean;
begin
  HasOpenBrackets := (FBrackets.Count > 0);
  if HasOpenBrackets then
    FBrackets.Last.BracketAfter := True;

  FBrackets.Add(TInlineBracket.Create(ChainNode, ContentStart, FLastDelimiter, IsImage));
end;

procedure TInlineParser.HandleCloseBracket;
var
  CloserPos: Integer;
  HasOpener: Boolean;
  Opener: TInlineBracket;
  Destination: string;
  Title: string;
  Matched: Boolean;
begin
  CloserPos := FIndex;
  Inc(FIndex);

  FlushText;

  HasOpener := (FBrackets.Count > 0);
  if not HasOpener then
  begin
    BufferText(CloseBracket, CloserPos, CloserPos + 1);
    Exit;
  end;

  Opener := FBrackets.Last;
  if not Opener.Active then
  begin
    AbandonBracket(CloserPos);
    Exit;
  end;

  Destination := '';
  Title := '';
  Matched := TryParseInlineLinkSuffix(Destination, Title);

  if not Matched then
    Matched := TryResolveReference(Opener, CloserPos, Destination, Title);

  if not Matched then
  begin
    FIndex := CloserPos + 1;
    AbandonBracket(CloserPos);
    Exit;
  end;

  EmitLink(Opener, Destination, Title);
end;

procedure TInlineParser.AbandonBracket(const CloserPos: Integer);
begin
  FBrackets.Delete(FBrackets.Count - 1);
  BufferText(CloseBracket, CloserPos, CloserPos + 1);
end;

function TInlineParser.TryParseInlineLinkSuffix(out Destination, Title: string): Boolean;
var
  StartsInline: Boolean;
  RawDestination: string;
  BeforeSpaces: Integer;
  RawTitle: string;
  HasWhitespaceBeforeTitle: Boolean;
  HasCloser: Boolean;
  UnescapedDestination: string;
begin
  Destination := '';
  Title := '';

  FLinkScanner.Reset(FContent, FIndex);

  StartsInline := (FLinkScanner.PeekChar = OpenParen);
  if not StartsInline then
  begin
    Result := False;
    Exit;
  end;

  FLinkScanner.Advance(1);
  FLinkScanner.SkipSpacesWithOneNewline;

  
  if not FLinkScanner.TryParseDestination(RawDestination) then
  begin
    Result := False;
    Exit;
  end;

  BeforeSpaces := FLinkScanner.Position;
  FLinkScanner.SkipSpacesWithOneNewline;

  RawTitle := '';
  HasWhitespaceBeforeTitle := (FLinkScanner.Position > BeforeSpaces);
  if HasWhitespaceBeforeTitle then
    FLinkScanner.TryParseTitle(RawTitle);

  FLinkScanner.SkipSpacesWithOneNewline;

  HasCloser := (FLinkScanner.PeekChar = CloseParen);
  if not HasCloser then
  begin
    Result := False;
    Exit;
  end;

  FLinkScanner.Advance(1);
  FIndex := FLinkScanner.Position;

  UnescapedDestination := TMarkdownUnescape.Unescape(RawDestination);
  Destination := TMarkdownUnescape.NormalizeUri(UnescapedDestination);
  Title := TMarkdownUnescape.Unescape(RawTitle);
  Result := True;
end;

function TInlineParser.TryResolveReference(const Opener: TInlineBracket; const CloserPos: Integer;
                                           out Destination, Title: string): Boolean;
var
  LabelContent: string;
  LabelLength: Integer;
  RefLabel: string;
  HasLabel: Boolean;
  Reference: TLinkReference;
  Resolved: Boolean;
begin
  Destination := '';
  Title := '';

  FLinkScanner.Reset(FContent, FIndex);

  
  

  if FLinkScanner.TryParseLabel(LabelContent, LabelLength) then
    FIndex := FLinkScanner.Position;

  RefLabel := '';
  HasLabel := False;

  if LabelLength > CollapsedLabelLength then
  begin
    RefLabel := LabelContent;
    HasLabel := True;
  end
  else if not Opener.BracketAfter then
  begin
    RefLabel := Copy(FContent, Opener.ContentStart, CloserPos - Opener.ContentStart);
    HasLabel := (RefLabel <> '');
  end;

  
  Resolved := HasLabel and Assigned(FReferenceMap) and FReferenceMap.TryGet(RefLabel, Reference);
  if not Resolved then
  begin
    Result := False;
    Exit;
  end;

  Destination := Reference.Destination;
  Title := Reference.Title;
  Result := True;
end;

procedure TInlineParser.EmitLink(const Opener: TInlineBracket; const Destination, Title: string);
var
  Kind: TMarkdownNodeKind;
  OpenerSegment: TMarkdownSegment;
  LinkNode: TMarkdownLinkNode;
  Walker: TInlineChainNode;
  Successor: TInlineChainNode;
begin
  ProcessEmphasis(Opener.DelimiterBottom);

  Kind := TMarkdownNodeKind.Link;
  if Opener.IsImage then
    Kind := TMarkdownNodeKind.Image;

  OpenerSegment := Opener.ChainNode.Value.Segment;

  LinkNode := TMarkdownLinkNode.Create(Kind, Destination, Title);
  ApplyLinkSegment(LinkNode, OpenerSegment.StartOffset);

  Walker := Opener.ChainNode.Next;
  while Walker <> nil do
  begin
    Successor := Walker.Next;
    LinkNode.AddChild(Walker.Value);
    RemoveInlineChainNode(Walker);
    Walker := Successor;
  end;

  RemoveInlineChainNode(Opener.ChainNode);
  AppendInline(LinkNode);

  CloseBracketsAfterLink(Opener.IsImage);
end;

procedure TInlineParser.CloseBracketsAfterLink(const IsImage: Boolean);
var
  Bracket: TInlineBracket;
begin
  FBrackets.Delete(FBrackets.Count - 1);

  if IsImage then
    Exit;

  for Bracket in FBrackets do
  begin
    if not Bracket.IsImage then
      Bracket.Active := False;
  end;
end;

function TInlineParser.TryParseTaskListMarker: Boolean;
var
  AtTaskPosition: Boolean;
  HasMarkerShape: Boolean;
  NodeName: type of (TGfmInlineParser.TaskUncheckedNodeName);
  IsChecked: Boolean;
  MarkerNode: TMarkdownCustomInlineNode;
begin
  AtTaskPosition := FTaskListCandidate and (FIndex = 1);
  if not AtTaskPosition then
  begin
    Result := False;
    Exit;
  end;

  HasMarkerShape := (System.Length(FContent) > TaskMarkerLength) and (FContent[1] = OpenBracket) and
    CharInSet(FContent[2], [Space, 'x', 'X']) and (FContent[3] = CloseBracket) and
    CharInSet(FContent[TaskMarkerLength + 1], [Space, Tab]);
  if not HasMarkerShape then
  begin
    Result := False;
    Exit;
  end;

  NodeName := TGfmInlineParser.TaskUncheckedNodeName;

  IsChecked := (FContent[2] <> Space);
  if IsChecked then
    NodeName := TGfmInlineParser.TaskCheckedNodeName;

  MarkerNode := TMarkdownCustomInlineNode.Create(NodeName);
  ApplySegment(MarkerNode, FIndex, TaskMarkerLength + 1);

  AppendInline(MarkerNode);
  FIndex := TaskMarkerLength + 1;

  Result := True;
end;

function TInlineParser.TryParseWwwAutolink: Boolean;
var
  HasPrefix: Boolean;
  DomainEnd: Integer;
  LinkEnd: Integer;
  HasHost: Boolean;
  LabelText: string;
begin
  if not IsExtendedAutolinkBoundary then
  begin
    Result := False;
    Exit;
  end;

  HasPrefix := (Copy(FContent, FIndex, System.Length(WwwPrefix)) = WwwPrefix);
  if not HasPrefix then
  begin
    Result := False;
    Exit;
  end;

  
  if not TryScanAutolinkDomain(FIndex, DomainEnd) then
  begin
    Result := False;
    Exit;
  end;

  LinkEnd := ApplyExtendedAutolinkTrailing(FIndex, ScanExtendedAutolinkEnd(DomainEnd));

  HasHost := (LinkEnd - FIndex > System.Length(WwwPrefix));
  if not HasHost then
  begin
    Result := False;
    Exit;
  end;

  LabelText := Copy(FContent, FIndex, LinkEnd - FIndex);
  EmitAutolink(LabelText, TMarkdownUnescape.NormalizeUri(HttpSchemePrefix + LabelText), FIndex, False);
  FIndex := LinkEnd;

  Result := True;
end;

function TInlineParser.TryParseUrlAutolink: Boolean;
var
  SchemeLength: Integer;
  Scheme: string;
  HasScheme: Boolean;
  DomainEnd: Integer;
  LinkEnd: Integer;
  HasHost: Boolean;
  LabelText: string;
begin
  if not IsExtendedAutolinkBoundary then
  begin
    Result := False;
    Exit;
  end;

  SchemeLength := 0;

  for Scheme in UrlAutolinkSchemes do
  begin
    HasScheme := (Copy(FContent, FIndex, System.Length(Scheme)) = Scheme);
    if HasScheme then
    begin
      SchemeLength := System.Length(Scheme);
      Break;
    end;
  end;

  if SchemeLength = 0 then
  begin
    Result := False;
    Exit;
  end;

  
  if not TryScanAutolinkDomain(FIndex + SchemeLength, DomainEnd) then
  begin
    Result := False;
    Exit;
  end;

  LinkEnd := ApplyExtendedAutolinkTrailing(FIndex, ScanExtendedAutolinkEnd(DomainEnd));

  HasHost := (LinkEnd > FIndex + SchemeLength);
  if not HasHost then
  begin
    Result := False;
    Exit;
  end;

  LabelText := Copy(FContent, FIndex, LinkEnd - FIndex);
  EmitAutolink(LabelText, TMarkdownUnescape.NormalizeUri(LabelText), FIndex, False);
  FIndex := LinkEnd;

  Result := True;
end;

function TInlineParser.TryParseEmailAutolink: Boolean;
var
  Rewind: Integer;
  DomainEnd: Integer;
  LinkStart: Integer;
  LabelText: string;
begin
  Rewind := 0;

  while (FIndex - Rewind > 1) and IsEmailUserChar(FContent[FIndex - Rewind - 1]) do
  begin
    Inc(Rewind);
  end;

  if Rewind = 0 then
  begin
    Result := False;
    Exit;
  end;

  
  if not TryScanEmailDomain(DomainEnd) then
  begin
    Result := False;
    Exit;
  end;

  if not TryConsumePrecedingChars(Rewind) then
  begin
    Result := False;
    Exit;
  end;

  LinkStart := FIndex - Rewind;
  LabelText := Copy(FContent, LinkStart, DomainEnd - LinkStart);
  EmitAutolink(LabelText, TMarkdownUnescape.NormalizeUri(MailtoPrefix + LabelText), LinkStart, False);
  FIndex := DomainEnd;

  Result := True;
end;

function TInlineParser.TryScanEmailDomain(out DomainEnd: Integer): Boolean;
var
  Index: Integer;
  DotCount: Integer;
  Current: Char;
begin
  Index := FIndex + 1;
  DotCount := 0;

  while Index <= System.Length(FContent) do
  begin
    Current := FContent[Index];

    if IsAsciiAlphaNumeric(Current) or CharInSet(Current, ['-', '_']) then
      Inc(Index)
    else if (Current = '.') and (Index < System.Length(FContent)) and IsAsciiAlphaNumeric(FContent[Index + 1]) then
    begin
      Inc(DotCount);
      Inc(Index);
    end
    else
      Break;
  end;

  DomainEnd := Index;

  if DotCount = 0 then
  begin
    Result := False;
    Exit;
  end;

  Result := not CharInSet(FContent[Index - 1], ['-', '_']);
end;

function TInlineParser.TryConsumePrecedingChars(const Count: Integer): Boolean;
var
  FromBuffer: Integer;
  Remaining: Integer;
  NodesToRemove: Integer;
  PartialTrim: Integer;
  Walker: TInlineChainNode;
  CanExamineNode: Boolean;
  LiteralLength: Integer;
  RemoveIndex: Integer;
  TrimmedNode: TMarkdownTextNode;
  Literal: string;
begin
  FromBuffer := Min(FTextBuffer.Length, Count);
  Remaining := Count - FromBuffer;
  NodesToRemove := 0;
  PartialTrim := 0;
  Walker := FLastInline;

  while Remaining > 0 do
  begin
    CanExamineNode := (Walker <> nil) and (Walker.Value.Kind = TMarkdownNodeKind.Text);
    if not CanExamineNode then
    begin
      Result := False;
      Exit;
    end;

    LiteralLength := System.Length((Walker.Value as IMarkdownText).Literal);

    if LiteralLength <= Remaining then
    begin
      Inc(NodesToRemove);
      Dec(Remaining, LiteralLength);
      Walker := Walker.Prev;
    end
    else
    begin
      PartialTrim := Remaining;
      Remaining := 0;
    end;
  end;

  FTextBuffer.Length := FTextBuffer.Length - FromBuffer;
  Dec(FTextEnd, FromBuffer);

  for RemoveIndex := 1 to NodesToRemove do
  begin
    RemoveTrailingInlineNode;
  end;

  if PartialTrim > 0 then
  begin
    TrimmedNode := FLastInline.Value as TMarkdownTextNode;
    Literal := TrimmedNode.GetLiteral;

    TrimmedNode.SetLiteral(Copy(Literal, 1, System.Length(Literal) - PartialTrim));
    ShrinkSegmentEnd(TrimmedNode, PartialTrim);
  end;

  Result := True;
end;

procedure TInlineParser.RemoveTrailingInlineNode;
var
  Node: TMarkdownTextNode;
  TrailingDelimiterMatches: Boolean;
begin
  Node := FLastInline.Value as TMarkdownTextNode;

  TrailingDelimiterMatches := (FLastDelimiter <> nil) and (FLastDelimiter.Node = Node);
  if TrailingDelimiterMatches then
    RemoveDelimiter(FLastDelimiter);

  RemoveInlineChainNode(FLastInline);
end;

// Inline math follows the Pandoc and Markdig rules: the opening dollar run may
// not be glued to a preceding word and may not be followed by whitespace, the
// closing run may not be preceded by whitespace and may not be glued to a
// following word. This keeps "$100 and $200" ordinary text. A backslash
// escapes the character after it inside the formula, so "\$" never closes.
function TInlineParser.TryParseMath: Boolean;
var
  RunLength: Integer;
  DelimiterLength: Integer;
  ContentStart: Integer;
  IsBacktickForm: Boolean;
  ContentEnd: Integer;
  IsDisplay: Boolean;
begin
  RunLength := DollarRunLength(FIndex);
  DelimiterLength := Min(RunLength, MaxMathDelimiterLength);
  ContentStart := FIndex + DelimiterLength;

  IsBacktickForm := (DelimiterLength = 1) and (ContentStart <= System.Length(FContent)) and
    (FContent[ContentStart] = Backtick);
  if IsBacktickForm then
  begin
    Result := TryParseBacktickMath;
    Exit;
  end;

  if not IsMathOpener(ContentStart) then
  begin
    Result := False;
    Exit;
  end;

  
  if not TryFindMathCloser(ContentStart, DelimiterLength, ContentEnd) then
  begin
    Result := False;
    Exit;
  end;

  IsDisplay := (DelimiterLength = MaxMathDelimiterLength);
  EmitMath(Copy(FContent, ContentStart, ContentEnd - ContentStart), IsDisplay, FIndex,
           ContentEnd + DelimiterLength);
  FIndex := ContentEnd + DelimiterLength;

  Result := True;
end;

// The GitLab form: a dollar, a backtick, the formula, a backtick and a dollar.
// The backticks fence the formula off from the rest of the markdown, which is
// why GitHub accepts the form as well.
function TInlineParser.TryParseBacktickMath: Boolean;
var
  PrecededByWord: type of (CharBefore(FIndex).IsLetterOrDigit);
  ContentStart: Integer;
  CloserStart: Integer;
  HasContent: Boolean;
begin
  PrecededByWord := CharBefore(FIndex).IsLetterOrDigit;
  if PrecededByWord then
  begin
    Result := False;
    Exit;
  end;

  ContentStart := FIndex + System.Length(BacktickMathCloser);
  CloserStart := Pos(BacktickMathCloser, FContent, ContentStart);

  HasContent := (CloserStart > ContentStart);
  if not HasContent then
  begin
    Result := False;
    Exit;
  end;

  EmitMath(Copy(FContent, ContentStart, CloserStart - ContentStart), False, FIndex,
           CloserStart + System.Length(BacktickMathCloser));
  FIndex := CloserStart + System.Length(BacktickMathCloser);

  Result := True;
end;

function TInlineParser.DollarRunLength(const StartIndex: Integer): Integer;
begin
  Result := 0;

  while (StartIndex + Result <= System.Length(FContent)) and (FContent[StartIndex + Result] = Dollar) do
  begin
    Inc(Result);
  end;
end;

function TInlineParser.IsMathOpener(const ContentStart: Integer): Boolean;
var
  PrecededByWord: type of (CharBefore(FIndex).IsLetterOrDigit);
  HasContent: Boolean;
begin
  PrecededByWord := CharBefore(FIndex).IsLetterOrDigit;
  if PrecededByWord then
  begin
    Result := False;
    Exit;
  end;

  HasContent := (ContentStart <= System.Length(FContent));
  if not HasContent then
  begin
    Result := False;
    Exit;
  end;

  Result := not IsUnicodeWhitespace(FContent[ContentStart]);
end;

function TInlineParser.TryFindMathCloser(const ContentStart, DelimiterLength: Integer;
                                         out ContentEnd: Integer): Boolean;
var
  AllowsLineBreaks: Boolean;
  Index: Integer;
  Current: Char;
  BreaksInlineMath: Boolean;
  RunLength: Integer;
  CloserStart: Integer;
  ClosesHere: Boolean;
begin
  ContentEnd := 0;
  AllowsLineBreaks := (DelimiterLength = MaxMathDelimiterLength);
  Index := ContentStart;

  while Index <= System.Length(FContent) do
  begin
    Current := FContent[Index];

    // A code span outranks math, so a formula never runs into one; a single
    // dollar formula also stays on its line.
    BreaksInlineMath := (Current = Backtick) or ((Current = LineFeed) and (not AllowsLineBreaks));
    if BreaksInlineMath then
    begin
      Result := False;
      Exit;
    end;

    if Current = Backslash then
    begin
      Inc(Index, 2);
      Continue;
    end;

    if Current <> Dollar then
    begin
      Inc(Index);
      Continue;
    end;

    RunLength := DollarRunLength(Index);
    CloserStart := Index + RunLength - DelimiterLength;

    ClosesHere := (RunLength >= DelimiterLength) and IsMathCloser(ContentStart, CloserStart, DelimiterLength);
    if ClosesHere then
    begin
      ContentEnd := CloserStart;
      Result := True;
      Exit;
    end;

    Inc(Index, RunLength);
  end;

  Result := False;
end;

function TInlineParser.IsMathCloser(const ContentStart, CloserStart, DelimiterLength: Integer): Boolean;
var
  HasContent: Boolean;
  PrecededByWhitespace: Boolean;
begin
  HasContent := (CloserStart > ContentStart);
  if not HasContent then
  begin
    Result := False;
    Exit;
  end;

  PrecededByWhitespace := IsUnicodeWhitespace(FContent[CloserStart - 1]);
  if PrecededByWhitespace then
  begin
    Result := False;
    Exit;
  end;

  Result := not CharAfter(CloserStart + DelimiterLength - 1).IsLetterOrDigit;
end;

procedure TInlineParser.EmitMath(const Literal: string; const IsDisplay: Boolean;
                                 const SyntaxStart, SyntaxEnd: Integer);
var
  Node: TMarkdownMathNode;
begin
  FlushText;

  Node := TMarkdownMathNode.Create(Literal, IsDisplay);
  ApplySegment(Node, SyntaxStart, SyntaxEnd);

  AppendInline(Node);
end;

function TInlineParser.IsExtendedAutolinkBoundary: Boolean;
var
  AtContentStart: Boolean;
begin
  AtContentStart := (FIndex = 1);
  if AtContentStart then
  begin
    Result := True;
    Exit;
  end;

  Result := CharInSet(FContent[FIndex - 1], [Space, Tab, #10, #13, Asterisk, Underscore, Tilde, OpenParen]);
end;

function TInlineParser.TryScanAutolinkDomain(const StartIndex: Integer; out DomainEnd: Integer): Boolean;
var
  Index: Integer;
  DotCount: Integer;
  PreviousUnderscores: Integer;
  CurrentUnderscores: Integer;
  Current: Char;
begin
  Index := StartIndex;
  DotCount := 0;
  PreviousUnderscores := 0;
  CurrentUnderscores := 0;

  while Index <= System.Length(FContent) do
  begin
    Current := FContent[Index];

    if Current = Underscore then
      Inc(CurrentUnderscores)
    else if Current = '.' then
    begin
      PreviousUnderscores := CurrentUnderscores;
      CurrentUnderscores := 0;
      Inc(DotCount);
    end
    else if (not IsAsciiAlphaNumeric(Current)) and (Current <> '-') then
      Break;

    Inc(Index);
  end;

  DomainEnd := Index;
  Result := (Index > StartIndex) and (DotCount > 0) and (PreviousUnderscores = 0) and (CurrentUnderscores = 0);
end;

function TInlineParser.ScanExtendedAutolinkEnd(const StartIndex: Integer): Integer;
var
  Index: Integer;
begin
  Index := StartIndex;

  while (Index <= System.Length(FContent)) and (not CharInSet(FContent[Index], [Space, Tab, #10, #11, #12, #13])) and
    (FContent[Index] <> LessThan) do
  begin
    Inc(Index);
  end;

  Result := Index;
end;

function TInlineParser.ApplyExtendedAutolinkTrailing(const StartIndex, CandidateEnd: Integer): Integer;
var
  EndIndex: Integer;
  Current: Char;
  Opens: Integer;
  Closes: Integer;
  Index: Integer;
  ScanIndex: Integer;
  IsEntityLike: Boolean;
begin
  EndIndex := CandidateEnd;

  while EndIndex > StartIndex do
  begin
    Current := FContent[EndIndex - 1];

    if CharInSet(Current, ['?', '!', '.', ',', ':', '*', '_', '~', '''', '"']) then
      Dec(EndIndex)
    else if Current = CloseParen then
    begin
      Opens := 0;
      Closes := 0;

      for Index := StartIndex to EndIndex - 1 do
      begin
        if FContent[Index] = OpenParen then
          Inc(Opens)
        else if FContent[Index] = CloseParen then
          Inc(Closes);
      end;

      if Closes <= Opens then
        Break;

      Dec(EndIndex);
    end
    else if Current = ';' then
    begin
      ScanIndex := EndIndex - 2;

      while (ScanIndex >= StartIndex) and IsAsciiLetter(FContent[ScanIndex]) do
      begin
        Dec(ScanIndex);
      end;

      IsEntityLike := (ScanIndex < EndIndex - 2) and (ScanIndex >= StartIndex) and
        (FContent[ScanIndex] = Ampersand);
      if IsEntityLike then
        EndIndex := ScanIndex
      else
        Dec(EndIndex);
    end
    else
      Break;
  end;

  Result := EndIndex;
end;

class function TInlineParser.IsAsciiAlphaNumeric(const Value: Char): Boolean;
begin
  Result := CharInSet(Value, ['0'..'9', 'a'..'z', 'A'..'Z']);
end;

class function TInlineParser.IsAsciiLetter(const Value: Char): Boolean;
begin
  Result := CharInSet(Value, ['a'..'z', 'A'..'Z']);
end;

class function TInlineParser.IsEmailUserChar(const Value: Char): Boolean;
begin
  Result := IsAsciiAlphaNumeric(Value) or CharInSet(Value, ['.', '-', '_', '+']);
end;

procedure TInlineParser.ProcessEmphasis(const StackBottom: TInlineDelimiter);
var
  Closer: TInlineDelimiter;
  Opener: TInlineDelimiter;
  Unmatched: TInlineDelimiter;
begin
  FOpenersBottom.Clear;

  Closer := FirstDelimiterAbove(StackBottom);

  while Closer <> nil do
  begin
    if not Closer.CanClose then
    begin
      Closer := Closer.Next;
      Continue;
    end;

    Opener := FindOpener(Closer, StackBottom);
    if Opener <> nil then
    begin
      Closer := ApplyMatch(Opener, Closer);
      Continue;
    end;

    FOpenersBottom.AddOrSetValue(OpenersBottomKey(Closer), Closer.Prev);

    Unmatched := Closer;
    Closer := Closer.Next;
    if not Unmatched.CanOpen then
      RemoveDelimiter(Unmatched);
  end;

  RemoveDelimitersAbove(StackBottom);
end;

function TInlineParser.FirstDelimiterAbove(const StackBottom: TInlineDelimiter): TInlineDelimiter;
begin
  if StackBottom = nil then
  begin
    Result := FFirstDelimiter;
    Exit;
  end;

  Result := StackBottom.Next;
end;

function TInlineParser.FindOpener(const Closer, StackBottom: TInlineDelimiter): TInlineDelimiter;
var
  SearchBottom: TInlineDelimiter;
  BucketBottom: TInlineDelimiter;
  Candidate: TInlineDelimiter;
  Matches: Boolean;
  IsEmphasisRun: Boolean;
  RuleOfThreeBlocks: Boolean;
begin
  SearchBottom := StackBottom;
  

  if FOpenersBottom.TryGetValue(OpenersBottomKey(Closer), BucketBottom) then
    SearchBottom := BucketBottom;

  Candidate := Closer.Prev;

  while (Candidate <> nil) and (Candidate <> StackBottom) and (Candidate <> SearchBottom) do
  begin
    Matches := Candidate.CanOpen and (Candidate.DelimiterChar = Closer.DelimiterChar) and (Candidate.Count > 0);

    if Matches then
    begin
      IsEmphasisRun := (Closer.Processor = nil);
      RuleOfThreeBlocks := IsEmphasisRun and IsRuleOfThreeViolated(Candidate, Closer);
      if not RuleOfThreeBlocks then
      begin
        Result := Candidate;
        Exit;
      end;
    end;

    Candidate := Candidate.Prev;
  end;

  Result := nil;
end;

function TInlineParser.OpenersBottomKey(const Closer: TInlineDelimiter): Integer;
var
  CanOpenOffset: Integer;
begin
  CanOpenOffset := 0;
  if Closer.CanOpen then
    CanOpenOffset := RuleOfThreeDivisor;

  Result := (Ord(Closer.DelimiterChar) * OpenersBottomBucketsPerChar) + CanOpenOffset
    + (Closer.OriginalCount mod RuleOfThreeDivisor);
end;

class function TInlineParser.IsRuleOfThreeViolated(const Opener, Closer: TInlineDelimiter): Boolean;
var
  EitherServesBothRoles: Boolean;
  SumIsMultipleOfThree: Boolean;
  BothAreMultiplesOfThree: type of (((Opener.OriginalCount mod RuleOfThreeDivisor) = 0) and
    ((Closer.OriginalCount mod RuleOfThreeDivisor) = 0));
begin
  EitherServesBothRoles := (Closer.CanOpen or Opener.CanClose);
  if not EitherServesBothRoles then
  begin
    Result := False;
    Exit;
  end;

  SumIsMultipleOfThree := (((Opener.OriginalCount + Closer.OriginalCount) mod RuleOfThreeDivisor) = 0);
  BothAreMultiplesOfThree := ((Opener.OriginalCount mod RuleOfThreeDivisor) = 0) and
    ((Closer.OriginalCount mod RuleOfThreeDivisor) = 0);

  Result := SumIsMultipleOfThree and (not BothAreMultiplesOfThree);
end;

function TInlineParser.ApplyMatch(const Opener, Closer: TInlineDelimiter): TInlineDelimiter;
var
  IsCustomRun: Boolean;
  CustomUseCount: Integer;
  CustomNode: TMarkdownCustomInlineNode;
  UseStrong: Boolean;
  UseCount: Integer;
  Kind: TMarkdownNodeKind;
  Container: TMarkdownAstNode;
begin
  IsCustomRun := (Closer.Processor <> nil);
  if IsCustomRun then
  begin
    CustomUseCount := Min(Opener.Count, Closer.Count);
    CustomNode := TMarkdownCustomInlineNode.Create(Closer.Processor.NodeName);
    ApplyContainerSegment(CustomNode, Opener, Closer, CustomUseCount);
    WrapNodesInContainer(Opener, Closer, CustomNode);

    ShrinkDelimiter(Opener, CustomUseCount, False);
    ShrinkDelimiter(Closer, CustomUseCount, True);

    Result := RemoveDepletedDelimiters(Opener, Closer);
    Exit;
  end;

  UseStrong := (Opener.Count >= StrongDelimiterCount) and (Closer.Count >= StrongDelimiterCount);

  UseCount := 1;
  if UseStrong then
    UseCount := StrongDelimiterCount;

  Kind := TMarkdownNodeKind.Emphasis;
  if UseStrong then
    Kind := TMarkdownNodeKind.Strong;

  Container := TMarkdownAstNode.Create(Kind);
  ApplyContainerSegment(Container, Opener, Closer, UseCount);
  WrapNodesInContainer(Opener, Closer, Container);

  ShrinkDelimiter(Opener, UseCount, False);
  ShrinkDelimiter(Closer, UseCount, True);

  Result := RemoveDepletedDelimiters(Opener, Closer);
end;

procedure TInlineParser.WrapNodesInContainer(const Opener, Closer: TInlineDelimiter;
                                             const Container: TMarkdownAstNode);
var
  ContainerNode: IMarkdownNode;
  Walker: TInlineChainNode;
  Successor: TInlineChainNode;
begin
  ContainerNode := Container;
  Walker := Opener.ChainNode.Next;

  while Walker <> Closer.ChainNode do
  begin
    Successor := Walker.Next;
    Container.AddChild(Walker.Value);
    RemoveInlineChainNode(Walker);
    Walker := Successor;
  end;

  InsertInlineAfter(Opener.ChainNode, ContainerNode);
end;

// An opener gives up the characters closest to the content it wraps, so it
// loses its last ones and a closer loses its first ones.
procedure TInlineParser.ShrinkDelimiter(const Delimiter: TInlineDelimiter; const UseCount: Integer;
                                        const FromStart: Boolean);
var
  Segment: TMarkdownSegment;
  IsMapped: Boolean;
begin
  Delimiter.Count := Delimiter.Count - UseCount;

  Delimiter.Node.SetLiteral(StringOfChar(Delimiter.DelimiterChar, Delimiter.Count));

  Segment := Delimiter.Node.GetSegment;
  IsMapped := (Segment.StartOffset > 0);
  if not IsMapped then
    Exit;

  if FromStart then
    Delimiter.Node.SetSegment(TMarkdownSegment.Create(Segment.StartOffset + UseCount, Segment.EndOffset))
  else
    Delimiter.Node.SetSegment(TMarkdownSegment.Create(Segment.StartOffset, Segment.EndOffset - UseCount));
end;

// The container reaches from the delimiters the opener gives up to the ones the
// closer gives up, so the markers that made it are part of it.
procedure TInlineParser.ApplyContainerSegment(const Container: TMarkdownAstNode;
                                              const Opener, Closer: TInlineDelimiter; const UseCount: Integer);
var
  OpenerSegment: TMarkdownSegment;
  CloserSegment: TMarkdownSegment;
  AreMapped: Boolean;
begin
  OpenerSegment := Opener.Node.GetSegment;
  CloserSegment := Closer.Node.GetSegment;

  AreMapped := (OpenerSegment.StartOffset > 0) and (CloserSegment.StartOffset > 0);
  if not AreMapped then
    Exit;

  Container.SetSegment(TMarkdownSegment.Create(OpenerSegment.EndOffset - UseCount,
                                               CloserSegment.StartOffset + UseCount));
end;

function TInlineParser.RemoveDepletedDelimiters(const Opener, Closer: TInlineDelimiter): TInlineDelimiter;
var
  Walker: TInlineDelimiter;
  Predecessor: TInlineDelimiter;
  OpenerDepleted: Boolean;
  CloserDepleted: Boolean;
  Successor: TInlineDelimiter;
begin
  Walker := Closer.Prev;

  while Walker <> Opener do
  begin
    Predecessor := Walker.Prev;
    RemoveDelimiter(Walker);
    Walker := Predecessor;
  end;

  OpenerDepleted := (Opener.Count = 0);
  if OpenerDepleted then
  begin
    RemoveInlineChainNode(Opener.ChainNode);
    RemoveDelimiter(Opener);
  end;

  CloserDepleted := (Closer.Count = 0);
  if not CloserDepleted then
  begin
    Result := Closer;
    Exit;
  end;

  Successor := Closer.Next;
  RemoveInlineChainNode(Closer.ChainNode);
  RemoveDelimiter(Closer);
  Result := Successor;
end;

procedure TInlineParser.AttachInlinesToParent;
var
  Walker: TInlineChainNode;
  Successor: TInlineChainNode;
begin
  Walker := FFirstInline;

  while Walker <> nil do
  begin
    Successor := Walker.Next;
    FParent.AddChild(Walker.Value);
    Walker.Free;
    Walker := Successor;
  end;

  FFirstInline := nil;
  FLastInline := nil;
end;

procedure TInlineParser.FlushText;
var
  HasText: Boolean;
  Node: TMarkdownTextNode;
begin
  HasText := (FTextBuffer.Length > 0);
  if not HasText then
    Exit;

  Node := TMarkdownTextNode.Create(TMarkdownNodeKind.Text, FTextBuffer.ToString);
  ApplySegment(Node, FTextStart, FTextEnd);

  AppendInline(Node);
  FTextBuffer.Clear;
end;

procedure TInlineParser.AddBreak(const Kind: TMarkdownNodeKind; const ContentStart, ContentEnd: Integer);
var
  Node: TMarkdownAstNode;
begin
  Node := TMarkdownAstNode.Create(Kind);
  ApplySegment(Node, ContentStart, ContentEnd);

  AppendInline(Node);
end;

// Collects the characters that make up one text node, remembering the stretch
// of content they were read from. An escape or an entity buffers fewer
// characters than it consumed, which is why the caller states both ends.
procedure TInlineParser.BufferText(const Value: string; const ContentStart, ContentEnd: Integer);
var
  StartsNode: Boolean;
begin
  StartsNode := (FTextBuffer.Length = 0);
  if StartsNode then
    FTextStart := ContentStart;

  FTextEnd := ContentEnd;
  FTextBuffer.Append(Value);
end;

procedure TInlineParser.ApplySegment(const Node: TMarkdownAstNode; const ContentStart, ContentEnd: Integer);
var
  StartOffset: Integer;
  EndOffset: Integer;
  IsMapped: Boolean;
begin
  if FSourceMap = nil then
    Exit;

  StartOffset := FSourceMap.SourceOffsetOf(ContentStart);
  EndOffset := FSourceMap.SourceOffsetOf(ContentEnd);

  IsMapped := (StartOffset > TMarkdownContentSourceMap.UnknownOffset) and (EndOffset >= StartOffset);
  if not IsMapped then
    Exit;

  Node.SetSegment(TMarkdownSegment.Create(StartOffset, EndOffset));
end;

procedure TInlineParser.ApplyLinkSegment(const Node: TMarkdownAstNode; const StartOffset: Integer);
var
  EndOffset: Integer;
  IsMapped: Boolean;
begin
  if FSourceMap = nil then
    Exit;

  EndOffset := FSourceMap.SourceOffsetOf(FIndex);

  IsMapped := (StartOffset > TMarkdownContentSourceMap.UnknownOffset) and (EndOffset >= StartOffset);
  if not IsMapped then
    Exit;

  Node.SetSegment(TMarkdownSegment.Create(StartOffset, EndOffset));
end;

procedure TInlineParser.ShrinkSegmentEnd(const Node: TMarkdownAstNode; const Count: Integer);
var
  Segment: TMarkdownSegment;
  IsMapped: Boolean;
begin
  Segment := Node.GetSegment;

  IsMapped := (Segment.StartOffset > TMarkdownContentSourceMap.UnknownOffset);
  if not IsMapped then
    Exit;

  Node.SetSegment(TMarkdownSegment.Create(Segment.StartOffset, Segment.EndOffset - Count));
end;

function TInlineParser.AppendInline(const Node: IMarkdownNode): TInlineChainNode;
begin
  Result := TInlineChainNode.Create(Node);
  Result.Prev := FLastInline;

  if FLastInline = nil then
    FFirstInline := Result
  else
    FLastInline.Next := Result;

  FLastInline := Result;
end;

procedure TInlineParser.InsertInlineAfter(const ChainNode: TInlineChainNode; const Node: IMarkdownNode);
var
  Inserted: TInlineChainNode;
begin
  Inserted := TInlineChainNode.Create(Node);

  Inserted.Prev := ChainNode;
  Inserted.Next := ChainNode.Next;

  if ChainNode.Next = nil then
    FLastInline := Inserted
  else
    ChainNode.Next.Prev := Inserted;

  ChainNode.Next := Inserted;
end;

procedure TInlineParser.RemoveInlineChainNode(const ChainNode: TInlineChainNode);
begin
  if ChainNode.Prev = nil then
    FFirstInline := ChainNode.Next
  else
    ChainNode.Prev.Next := ChainNode.Next;

  if ChainNode.Next = nil then
    FLastInline := ChainNode.Prev
  else
    ChainNode.Next.Prev := ChainNode.Prev;

  ChainNode.Free;
end;

procedure TInlineParser.ClearInlineChain;
var
  Walker: TInlineChainNode;
  Successor: TInlineChainNode;
begin
  Walker := FFirstInline;

  while Walker <> nil do
  begin
    Successor := Walker.Next;
    Walker.Free;
    Walker := Successor;
  end;

  FFirstInline := nil;
  FLastInline := nil;
end;

procedure TInlineParser.AppendDelimiter(const Delimiter: TInlineDelimiter);
begin
  Delimiter.Prev := FLastDelimiter;

  if FLastDelimiter = nil then
    FFirstDelimiter := Delimiter
  else
    FLastDelimiter.Next := Delimiter;

  FLastDelimiter := Delimiter;
end;

procedure TInlineParser.RemoveDelimiter(const Delimiter: TInlineDelimiter);
begin
  if Delimiter.Prev = nil then
    FFirstDelimiter := Delimiter.Next
  else
    Delimiter.Prev.Next := Delimiter.Next;

  if Delimiter.Next = nil then
    FLastDelimiter := Delimiter.Prev
  else
    Delimiter.Next.Prev := Delimiter.Prev;

  Delimiter.Free;
end;

procedure TInlineParser.RemoveDelimitersAbove(const StackBottom: TInlineDelimiter);
begin
  while FLastDelimiter <> StackBottom do
  begin
    RemoveDelimiter(FLastDelimiter);
  end;
end;

procedure TInlineParser.ClearDelimiterStack;
begin
  RemoveDelimitersAbove(nil);
end;

class function TInlineParser.IsUnicodeWhitespace(const Value: Char): Boolean;
begin
  Result := Value.IsWhiteSpace;
end;

class function TInlineParser.IsUnicodePunctuation(const Value: Char): Boolean;
begin
  Result := Value.IsPunctuation or Value.IsSymbol;
end;

constructor TInlineParserContext.Create(const Engine: TInlineParser);
begin
  inherited Create;

  FEngine := Engine;
end;

function TInlineParserContext.GetContent: string;
begin
  Result := FEngine.FContent;
end;

function TInlineParserContext.GetPosition: Integer;
begin
  Result := FEngine.FIndex;
end;

constructor TCommonMarkInlineParser.Create(const Kind: TCommonMarkInlineKind);
begin
  inherited Create;

  FKind := Kind;
end;

function TCommonMarkInlineParser.GetName: string;
begin
  Result := Names[FKind];
end;

function TCommonMarkInlineParser.TryParse(const Context: IMarkdownInlineParserContext): Boolean;
var
  Engine: type of ((Context as TInlineParserContext).Engine);
begin
  Engine := (Context as TInlineParserContext).Engine;

  case FKind of
    TCommonMarkInlineKind.Backslash:
      Engine.HandleBackslash;
    TCommonMarkInlineKind.LineEnding:
      Engine.HandleLineEnding;
    TCommonMarkInlineKind.EmphasisRun:
      Engine.HandleDelimiterRun;
    TCommonMarkInlineKind.CodeSpan:
      Engine.HandleBackticks;
    TCommonMarkInlineKind.AngleBracket:
      Engine.HandleLessThan;
    TCommonMarkInlineKind.Entity:
      Engine.HandleAmpersand;
    TCommonMarkInlineKind.LinkOpener:
      Engine.HandleOpenBracket;
    TCommonMarkInlineKind.ImageOpener:
      Engine.HandleBang;
    TCommonMarkInlineKind.LinkCloser:
      Engine.HandleCloseBracket;
  else
    raise EMarkdownError.CreateFmt('Unhandled inline kind: %d', [Ord(FKind)]);
  end;

  Result := True;
end;

function TMathInlineParser.GetName: string;
begin
  Result := MathParserName;
end;

function TMathInlineParser.TryParse(const Context: IMarkdownInlineParserContext): Boolean;
var
  Engine: type of ((Context as TInlineParserContext).Engine);
begin
  Engine := (Context as TInlineParserContext).Engine;

  Result := Engine.TryParseMath;
end;

constructor TGfmInlineParser.Create(const Kind: TGfmInlineKind);
begin
  inherited Create;

  FKind := Kind;
end;

function TGfmInlineParser.GetName: string;
begin
  Result := Names[FKind];
end;

function TGfmInlineParser.TryParse(const Context: IMarkdownInlineParserContext): Boolean;
var
  Engine: type of ((Context as TInlineParserContext).Engine);
begin
  Engine := (Context as TInlineParserContext).Engine;

  case FKind of
    TGfmInlineKind.TaskListMarker:
      Result := Engine.TryParseTaskListMarker;
    TGfmInlineKind.WwwAutolink:
      Result := Engine.TryParseWwwAutolink;
    TGfmInlineKind.UrlAutolink:
      Result := Engine.TryParseUrlAutolink;
  else
    Result := Engine.TryParseEmailAutolink;
  end;
end;

end.
