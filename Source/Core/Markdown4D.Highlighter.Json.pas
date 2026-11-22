{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Highlighter.Json;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Highlighter.LineScanner,
  Markdown4D.Compat.Str,
  character;

type
  TJsonSyntaxHighlighter = class(TSyntaxHighlighter)
  protected
    function ScannerClass: TSyntaxLineScannerClass; override;
  end;

implementation

uses
  SysUtils,
  Markdown4D.Highlighter.Interfaces;

type
  TJsonLineScanner = class(TSyntaxLineScanner)
  private
    const
      QuoteCharacter = '"';
      EscapeCharacter = '\';
      KeySeparator = ':';
      UnicodeEscapeIndicator = 'u';
      ShortEscapeLength = 2;
      UnicodeEscapeLength = 6;
      TrueLiteral = 'true';
      FalseLiteral = 'false';
      NullLiteral = 'null';
      Letters = ['A'..'Z', 'a'..'z'];
      SignCharacters = ['+', '-'];
      WhitespaceCharacters = [' ', #9];
      MinusSign = '-';
      DecimalPoint = '.';
      ExponentIndicators = ['e', 'E'];
    procedure ScanString;
    function IsKeyString(const Start: Integer): Boolean;
    function FindStringClose(const Start: Integer): Integer;
    // A number here may carry a sign and an exponent, which the plain reader
    // this descends from does not allow.
    procedure ScanSignedNumber;
    procedure ScanWord;
    function EscapeLengthAt(const Position: Integer): Integer;

  protected
    procedure ScanNext; override;
  end;

function TJsonSyntaxHighlighter.ScannerClass: TSyntaxLineScannerClass;
begin
  Result := TJsonLineScanner;
end;

procedure TJsonLineScanner.ScanNext;
var
  Current: Char;
  StartsNumber: type of (CharInSet(Current, Digits) or
    ((Current = MinusSign) and CharInSet(CharAt(FPosition + 1), Digits)));
begin
  Current := FLine[FPosition];

  StartsNumber := CharInSet(Current, Digits) or
    ((Current = MinusSign) and CharInSet(CharAt(FPosition + 1), Digits));

  if Current = QuoteCharacter then
    ScanString
  else if StartsNumber then
    ScanSignedNumber
  else if CharInSet(Current, Letters) then
    ScanWord
  else
    AddPlainCharacter;
end;

procedure TJsonLineScanner.ScanString;
var
  Start: Integer;
  TextKind: TSyntaxTokenKind;
  SegmentStart: Integer;
  Current: Char;
  EscapeLength: Integer;
begin
  Start := FPosition;

  TextKind := TSyntaxTokenKind.StringLiteral;
  if IsKeyString(Start) then
    TextKind := TSyntaxTokenKind.JsonKey;

  SegmentStart := Start;
  Inc(FPosition);

  while FPosition <= Length(FLine) do
  begin
    Current := FLine[FPosition];

    if Current = EscapeCharacter then
    begin
      FBuilder.Add(TextKind, SegmentStart, FPosition - SegmentStart);

      EscapeLength := EscapeLengthAt(FPosition);
      FBuilder.Add(TSyntaxTokenKind.EscapeSequence, FPosition, EscapeLength);
      FPosition := FPosition + EscapeLength;
      SegmentStart := FPosition;
      Continue;
    end;

    Inc(FPosition);
    if Current = QuoteCharacter then
      Break;
  end;

  FBuilder.Add(TextKind, SegmentStart, FPosition - SegmentStart);
end;

function TJsonLineScanner.IsKeyString(const Start: Integer): Boolean;
var
  CloseIndex: Integer;
  Probe: Integer;
begin
  CloseIndex := FindStringClose(Start);
  if CloseIndex = 0 then
  begin
    Result := False;
    Exit;
  end;

  Probe := CloseIndex + 1;
  while (Probe <= Length(FLine)) and CharInSet(FLine[Probe], WhitespaceCharacters) do
  begin
    Inc(Probe);
  end;

  Result := (CharAt(Probe) = KeySeparator);
end;

function TJsonLineScanner.FindStringClose(const Start: Integer): Integer;
var
  Probe: Integer;
  Current: Char;
begin
  Probe := Start + 1;

  while Probe <= Length(FLine) do
  begin
    Current := FLine[Probe];

    if Current = EscapeCharacter then
    begin
      Probe := Probe + EscapeLengthAt(Probe);
      Continue;
    end;

    if Current = QuoteCharacter then
    begin
      Result := Probe;
      Exit;
    end;

    Inc(Probe);
  end;

  Result := 0;
end;

procedure TJsonLineScanner.ScanSignedNumber;
var
  Start: Integer;
  HasFraction: Boolean;
  HasSignedExponent: type of (CharInSet(CharAt(FPosition + 1), SignCharacters) and
    CharInSet(CharAt(FPosition + 2), Digits));
  HasExponent: type of (CharInSet(CharAt(FPosition), ExponentIndicators) and
    (CharInSet(CharAt(FPosition + 1), Digits) or HasSignedExponent));
begin
  Start := FPosition;

  if FLine[FPosition] = MinusSign then
    Inc(FPosition);

  while (FPosition <= Length(FLine)) and CharInSet(FLine[FPosition], Digits) do
  begin
    Inc(FPosition);
  end;

  HasFraction := (CharAt(FPosition) = DecimalPoint) and CharInSet(CharAt(FPosition + 1), Digits);
  if HasFraction then
  begin
    Inc(FPosition);

    while (FPosition <= Length(FLine)) and CharInSet(FLine[FPosition], Digits) do
    begin
      Inc(FPosition);
    end;
  end;

  HasSignedExponent := CharInSet(CharAt(FPosition + 1), SignCharacters) and
    CharInSet(CharAt(FPosition + 2), Digits);
  HasExponent := CharInSet(CharAt(FPosition), ExponentIndicators) and
    (CharInSet(CharAt(FPosition + 1), Digits) or HasSignedExponent);
  if HasExponent then
  begin
    Inc(FPosition);

    if CharInSet(FLine[FPosition], SignCharacters) then
      Inc(FPosition);

    while (FPosition <= Length(FLine)) and CharInSet(FLine[FPosition], Digits) do
    begin
      Inc(FPosition);
    end;
  end;

  FBuilder.Add(TSyntaxTokenKind.NumberLiteral, Start, FPosition - Start);
end;

procedure TJsonLineScanner.ScanWord;
var
  Start: Integer;
  WordText: string;
  IsLiteralKeyword: Boolean;
  Kind: TSyntaxTokenKind;
begin
  Start := FPosition;

  while (FPosition <= Length(FLine)) and CharInSet(FLine[FPosition], Letters) do
  begin
    Inc(FPosition);
  end;

  WordText := Copy(FLine, Start, FPosition - Start);
  IsLiteralKeyword := (WordText = TrueLiteral) or (WordText = FalseLiteral) or (WordText = NullLiteral);

  Kind := TSyntaxTokenKind.PlainText;
  if IsLiteralKeyword then
    Kind := TSyntaxTokenKind.Keyword;

  FBuilder.Add(Kind, Start, FPosition - Start);
end;

function TJsonLineScanner.EscapeLengthAt(const Position: Integer): Integer;
var
  EscapeLength: Integer;
  RemainingLength: Integer;
begin
  EscapeLength := ShortEscapeLength;
  if CharAt(Position + 1) = UnicodeEscapeIndicator then
    EscapeLength := UnicodeEscapeLength;

  RemainingLength := Length(FLine) - Position + 1;
  if EscapeLength > RemainingLength then
    EscapeLength := RemainingLength;

  Result := EscapeLength;
end;

end.
