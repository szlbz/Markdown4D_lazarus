{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Parser.LinkSyntax;

{$SCOPEDENUMS ON}

interface

type
  TLinkSyntaxScanner = class
  private
    const
      DoubleQuote = '"';
      SingleQuote = '''';
      MaxLabelUnits = 1000;
    var
      FContent: string;
      FPosition: Integer;
    function TryParsePointyDestination(out Destination: string): Boolean;

  public
    procedure Reset(const Content: string; const StartPosition: Integer);
    procedure Advance(const Count: Integer);
    procedure MoveTo(const Position: Integer);
    function TryParseLabel(out LabelContent: string; out ConsumedLength: Integer): Boolean;
    procedure SkipSpacesWithOneNewline;
    function TryParseDestination(out Destination: string): Boolean;
    function TryParseTitle(out Title: string): Boolean;
    function ConsumeSpacesToLineEnd: Boolean;
    function PeekChar: Char;
    property Position: Integer read FPosition;
  end;

implementation

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  Markdown4D.Defines,
  Markdown4D.Text.Unescape;

procedure TLinkSyntaxScanner.Reset(const Content: string; const StartPosition: Integer);
begin
  FContent := Content;
  FPosition := StartPosition;
end;

procedure TLinkSyntaxScanner.Advance(const Count: Integer);
begin
  Inc(FPosition, Count);
end;

procedure TLinkSyntaxScanner.MoveTo(const Position: Integer);
begin
  FPosition := Position;
end;

function TLinkSyntaxScanner.TryParseLabel(out LabelContent: string; out ConsumedLength: Integer): Boolean;
var
  StartsWithBracket: Boolean;
  Index: Integer;
  Units: Integer;
  Current: Char;
  HasEscapedChar: Boolean;
begin
  LabelContent := '';
  ConsumedLength := 0;

  StartsWithBracket := (PeekChar = OpenBracket);
  if not StartsWithBracket then
  begin
    Result := False;
    Exit;
  end;

  Index := FPosition + 1;
  Units := 0;

  while Index <= Length(FContent) do
  begin
    Current := FContent[Index];

    if Current = CloseBracket then
    begin
      LabelContent := Copy(FContent, FPosition + 1, Index - FPosition - 1);
      ConsumedLength := Index - FPosition + 1;
      FPosition := Index + 1;
      Result := True;
      Exit;
    end;

    if Current = OpenBracket then
    begin
      Result := False;
      Exit;
    end;

    HasEscapedChar := (Current = Backslash) and (Index < Length(FContent));
    if HasEscapedChar then
      Inc(Index, 2)
    else
      Inc(Index);

    Inc(Units);

    if Units > MaxLabelUnits then
    begin
      Result := False;
      Exit;
    end;
  end;

  Result := False;
end;

procedure TLinkSyntaxScanner.SkipSpacesWithOneNewline;
var
  HasNewline: Boolean;
begin
  while CharInSet(PeekChar, [Space, Tab]) do
  begin
    Inc(FPosition);
  end;

  HasNewline := (PeekChar = LineFeed);
  if not HasNewline then
    Exit;

  Inc(FPosition);

  while CharInSet(PeekChar, [Space, Tab]) do
  begin
    Inc(FPosition);
  end;
end;

function TLinkSyntaxScanner.TryParseDestination(out Destination: string): Boolean;
var
  StartPosition: Integer;
  OpenParens: Integer;
  Current: Char;
  IsEscapedPunctuation: Boolean;
  ConsumedNothing: Boolean;
  Unbalanced: Boolean;
begin
  Destination := '';

  if PeekChar = LessThan then
  begin
    Result := TryParsePointyDestination(Destination);
    Exit;
  end;

  StartPosition := FPosition;
  OpenParens := 0;

  while FPosition <= Length(FContent) do
  begin
    Current := FContent[FPosition];

    IsEscapedPunctuation := (Current = Backslash) and (FPosition < Length(FContent)) and
      TMarkdownUnescape.IsAsciiPunctuation(FContent[FPosition + 1]);
    if IsEscapedPunctuation then
    begin
      Inc(FPosition, 2);
      Continue;
    end;

    if Current = OpenParen then
    begin
      Inc(OpenParens);
      Inc(FPosition);
      Continue;
    end;

    if Current = CloseParen then
    begin
      if OpenParens < 1 then
        Break;

      Dec(OpenParens);
      Inc(FPosition);
      Continue;
    end;

    if TMarkdownUnescape.IsMarkdownWhitespace(Current) then
      Break;

    Inc(FPosition);
  end;

  ConsumedNothing := (FPosition = StartPosition) and (PeekChar <> CloseParen);
  if ConsumedNothing then
  begin
    Result := False;
    Exit;
  end;

  Unbalanced := (OpenParens <> 0);
  if Unbalanced then
  begin
    Result := False;
    Exit;
  end;

  Destination := Copy(FContent, StartPosition, FPosition - StartPosition);
  Result := True;
end;

function TLinkSyntaxScanner.TryParsePointyDestination(out Destination: string): Boolean;
var
  Index: Integer;
  Current: Char;
  IsForbidden: Boolean;
  SkipsEscapedChar: Boolean;
begin
  Destination := '';
  Index := FPosition + 1;

  while Index <= Length(FContent) do
  begin
    Current := FContent[Index];

    if Current = GreaterThan then
    begin
      Destination := Copy(FContent, FPosition + 1, Index - FPosition - 1);
      FPosition := Index + 1;
      Result := True;
      Exit;
    end;

    IsForbidden := (Current = LessThan) or (Current = LineFeed);
    if IsForbidden then
    begin
      Result := False;
      Exit;
    end;

    SkipsEscapedChar := (Current = Backslash) and (Index < Length(FContent)) and
      (FContent[Index + 1] <> LineFeed);
    if SkipsEscapedChar then
      Inc(Index, 2)
    else
      Inc(Index);
  end;

  Result := False;
end;

function TLinkSyntaxScanner.TryParseTitle(out Title: string): Boolean;
var
  Opener: Char;
  Closer: Char;
  IsQuoteOpener: Boolean;
  HasOpener: Boolean;
  Index: Integer;
  Current: Char;
  IsNestedParen: Boolean;
  IsEscapedPunctuation: Boolean;
begin
  Title := '';
  Opener := PeekChar;

  Closer := #0;
  IsQuoteOpener := (Opener = DoubleQuote) or (Opener = SingleQuote);
  if IsQuoteOpener then
    Closer := Opener
  else if Opener = OpenParen then
    Closer := CloseParen;

  HasOpener := (Closer <> #0);
  if not HasOpener then
  begin
    Result := False;
    Exit;
  end;

  Index := FPosition + 1;

  while Index <= Length(FContent) do
  begin
    Current := FContent[Index];

    if Current = Closer then
    begin
      Title := Copy(FContent, FPosition + 1, Index - FPosition - 1);
      FPosition := Index + 1;
      Result := True;
      Exit;
    end;

    IsNestedParen := (Closer = CloseParen) and (Current = OpenParen);
    if IsNestedParen then
    begin
      Result := False;
      Exit;
    end;

    IsEscapedPunctuation := (Current = Backslash) and (Index < Length(FContent)) and
      TMarkdownUnescape.IsAsciiPunctuation(FContent[Index + 1]);
    if IsEscapedPunctuation then
      Inc(Index, 2)
    else
      Inc(Index);
  end;

  Result := False;
end;

function TLinkSyntaxScanner.ConsumeSpacesToLineEnd: Boolean;
var
  Index: Integer;
  AtContentEnd: Boolean;
  AtLineEnd: Boolean;
begin
  Index := FPosition;

  while (Index <= Length(FContent)) and CharInSet(FContent[Index], [Space, Tab]) do
  begin
    Inc(Index);
  end;

  AtContentEnd := (Index > Length(FContent));
  if AtContentEnd then
  begin
    FPosition := Index;
    Result := True;
    Exit;
  end;

  AtLineEnd := (FContent[Index] = LineFeed);
  if AtLineEnd then
  begin
    FPosition := Index + 1;
    Result := True;
    Exit;
  end;

  Result := False;
end;

function TLinkSyntaxScanner.PeekChar: Char;
var
  OutOfRange: Boolean;
begin
  OutOfRange := (FPosition > Length(FContent));
  if OutOfRange then
  begin
    Result := #0;
    Exit;
  end;

  Result := FContent[FPosition];
end;

end.
