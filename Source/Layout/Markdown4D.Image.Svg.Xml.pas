{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Image.Svg.Xml;

{$SCOPEDENUMS ON}

// A pull scanner over the subset of XML an SVG file is written in: elements,
// attributes and the nesting between them. Enough to walk a drawing, and small
// enough to stay in the framework-neutral layer, where the RTL's XML document
// cannot go because it reaches for a platform parser.
//
// Processing instructions, comments, doctypes and CDATA are stepped over
// rather than reported: nothing in the shape of a drawing lives there. The
// characters between an opening tag and whatever follows it are reported with
// the element, because a text element carries its words there.

interface

uses
  SysUtils,
  Markdown4D.Compat.Str;

type
  TSvgXmlAttribute = record
    Name: string;
    Value: string;
  end;

  TSvgXmlElement = record
    Name: string;
    Attributes: TArray<TSvgXmlAttribute>;
    // The character data that follows the opening tag, which is where the
    // words of a text element live.
    Text: string;
    // Where the tag began and where it ended, so a caller can lift a whole
    // element back out of the document it came from.
    Start: Integer;
    Stop: Integer;
    IsClosing: Boolean;
    IsSelfClosing: Boolean;
    function TryAttribute(const AttributeName: string; out Value: string): Boolean;
    function Attribute(const AttributeName: string; const Default: string = ''): string;
  end;

  TSvgXmlScanner = class
  private
    const
      TagOpen = '<';
      TagClose = '>';
      Slash = '/';
      Question = '?';
      Exclamation = '!';
      CommentOpen = '!--';
      CommentClose = '-->';
      CDataOpen = '![CDATA[';
      CDataClose = ']]>';
      Equals = '=';
      Ampersand = '&';
      Semicolon = ';';
      NumberSign = '#';
      HexMarker = 'x';
      MaxEntityLength = 12;
    var
      FText: string;
      FIndex: Integer;
    function AtEnd: Boolean;
    procedure SkipWhitespace;
    function SkipUntil(const Marker: string): Boolean;
    function ReadName: string;
    function ReadAttributeValue: string;
    function ReadAttributes: TArray<TSvgXmlAttribute>;
    function ReadContentText: string;
    class function DecodeEntities(const Value: string): string;
    class function TryDecodeEntity(const Entity: string; out Decoded: string): Boolean;

  public
    constructor Create(const Text: string);
    // Reports the next element, opening or closing. False once the document is
    // spent.
    function ReadElement(out Element: TSvgXmlElement): Boolean;
  end;

implementation

uses
  character;

function TSvgXmlElement.TryAttribute(const AttributeName: string; out Value: string): Boolean;
var
  Item: TSvgXmlAttribute;
begin
  for Item in Attributes do
  begin
    if SameText(Item.Name, AttributeName) then
    begin
      Value := Item.Value;
      Result := True;
      Exit;
    end;
  end;

  Value := '';
  Result := False;
end;

function TSvgXmlElement.Attribute(const AttributeName: string; const Default: string): string;
begin
  if not TryAttribute(AttributeName, Result) then
    Result := Default;
end;

constructor TSvgXmlScanner.Create(const Text: string);
begin
  inherited Create;

  FText := Text;
  FIndex := 1;
end;

function TSvgXmlScanner.AtEnd: Boolean;
begin
  Result := FIndex > Length(FText);
end;

procedure TSvgXmlScanner.SkipWhitespace;
begin
  while (not AtEnd) and (FText[FIndex] <= ' ') do
  begin
    Inc(FIndex);
  end;
end;

function TSvgXmlScanner.SkipUntil(const Marker: string): Boolean;
var
  Position: Integer;
begin
  Position := Pos(Marker, FText, FIndex);
  if Position = 0 then
  begin
    FIndex := Length(FText) + 1;
    Result := False;
    Exit;
  end;

  FIndex := Position + Length(Marker);
  Result := True;
end;

function TSvgXmlScanner.ReadName: string;
var
  Start: Integer;
  Current: Char;
  EndsName: Boolean;
begin
  Start := FIndex;

  while not AtEnd do
  begin
    Current := FText[FIndex];
    EndsName := (Current <= ' ') or (Current = TagClose) or (Current = Slash) or (Current = Equals);
    if EndsName then
      Break;

    Inc(FIndex);
  end;

  Result := Copy(FText, Start, FIndex - Start);
end;

function TSvgXmlScanner.ReadAttributeValue: string;
var
  Quote: Char;
  IsQuoted: Boolean;
  Start: Integer;
begin
  SkipWhitespace;
  if AtEnd then
  begin
    Result := '';
    Exit;
  end;

  Quote := FText[FIndex];
  IsQuoted := (Quote = '"') or (Quote = '''');
  if not IsQuoted then
  begin
    Result := DecodeEntities(ReadName);
    Exit;
  end;

  Inc(FIndex);
  Start := FIndex;
  while (not AtEnd) and (FText[FIndex] <> Quote) do
  begin
    Inc(FIndex);
  end;

  Result := DecodeEntities(Copy(FText, Start, FIndex - Start));

  if not AtEnd then
    Inc(FIndex);
end;

function TSvgXmlScanner.ReadAttributes: TArray<TSvgXmlAttribute>;
var
  Current: Char;
  Name: string;
  Value: string;
  Attribute: TSvgXmlAttribute;
begin
  Result := nil;

  while True do
  begin
    SkipWhitespace;
    if AtEnd then
      Exit;

    Current := FText[FIndex];
    if (Current = TagClose) or (Current = Slash) then
      Exit;

    Name := ReadName;
    if Name = '' then
    begin
      Inc(FIndex);
      Continue;
    end;

    SkipWhitespace;

    Value := '';
    if (not AtEnd) and (FText[FIndex] = Equals) then
    begin
      Inc(FIndex);
      Value := ReadAttributeValue;
    end;

    
    Attribute.Name := Name;
    Attribute.Value := Value;
    Result := Result + [Attribute];
  end;
end;

// Everything up to the next tag, left where it is so the caller reading the
// following element sees it unchanged.
function TSvgXmlScanner.ReadContentText: string;
var
  Start: Integer;
begin
  Start := FIndex;

  while (not AtEnd) and (FText[FIndex] <> TagOpen) do
  begin
    Inc(FIndex);
  end;

  Result := DecodeEntities(Copy(FText, Start, FIndex - Start));
end;

function TSvgXmlScanner.ReadElement(out Element: TSvgXmlElement): Boolean;
var
  Position: Integer;
  Current: Char;
begin
  Element := Default(TSvgXmlElement);

  while True do
  begin
    Position := Pos(TagOpen, FText, FIndex);
    if Position = 0 then
    begin
      FIndex := Length(FText) + 1;
      Result := False;
      Exit;
    end;

    Element.Start := Position;
    FIndex := Position + 1;
    if AtEnd then
    begin
      Result := False;
      Exit;
    end;

    if Copy(FText, FIndex, Length(CommentOpen)) = CommentOpen then
    begin
      SkipUntil(CommentClose);
      Continue;
    end;

    if Copy(FText, FIndex, Length(CDataOpen)) = CDataOpen then
    begin
      SkipUntil(CDataClose);
      Continue;
    end;

    Current := FText[FIndex];

    // A doctype or a processing instruction carries no shape, and neither can
    // nest, so running to the next '>' is enough to step over it.
    if (Current = Question) or (Current = Exclamation) then
    begin
      SkipUntil(TagClose);
      Continue;
    end;

    if Current = Slash then
    begin
      Inc(FIndex);
      Element.Name := ReadName;
      Element.IsClosing := True;
      SkipUntil(TagClose);
      Element.Stop := FIndex;
      Result := True;
      Exit;
    end;

    Element.Name := ReadName;
    if Element.Name = '' then
      Continue;

    Element.Attributes := ReadAttributes;

    SkipWhitespace;
    if (not AtEnd) and (FText[FIndex] = Slash) then
    begin
      Element.IsSelfClosing := True;
      Inc(FIndex);
    end;

    if (not AtEnd) and (FText[FIndex] = TagClose) then
      Inc(FIndex);

    Element.Stop := FIndex;

    if not Element.IsSelfClosing then
      Element.Text := ReadContentText;

    Result := True;
    Exit;
  end;
end;

class function TSvgXmlScanner.DecodeEntities(const Value: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  Stop: Integer;
  Fits: Boolean;
  Decoded: string;
begin
  if Pos(Ampersand, Value) = 0 then
  begin
    Result := Value;
    Exit;
  end;

  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(Value) do
    begin
      if Value[Index] <> Ampersand then
      begin
        Builder.Append(Value[Index]);
        Inc(Index);
        Continue;
      end;

      Stop := Pos(Semicolon, Value, Index);
      Fits := (Stop > 0) and (Stop - Index <= MaxEntityLength);

      Decoded := '';
      if Fits and TryDecodeEntity(Copy(Value, Index + 1, Stop - Index - 1), Decoded) then
      begin
        Builder.Append(Decoded);
        Index := Stop + 1;
        Continue;
      end;

      Builder.Append(Value[Index]);
      Inc(Index);
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TSvgXmlScanner.TryDecodeEntity(const Entity: string; out Decoded: string): Boolean;
var
  Code: Integer;
  IsHex: Boolean;
begin
  Decoded := '';
  if Entity = '' then
  begin
    Result := False;
    Exit;
  end;

  if Entity[1] = NumberSign then
  begin
    Code := 0;
    IsHex := (Length(Entity) > 1) and (LowerCase(Entity[2]) = HexMarker);

    if IsHex then
    begin
      if not TryStrToInt('$' + Copy(Entity, 3, MaxInt), Code) then
      begin
        Result := False;
        Exit;
      end;
    end
    else if not TryStrToInt(Copy(Entity, 2, MaxInt), Code) then
    begin
      Result := False;
      Exit;
    end;

    if (Code <= 0) or (Code > $10FFFF) then
    begin
      Result := False;
      Exit;
    end;

    Decoded := Char.ConvertFromUtf32(Code);
    Result := True;
    Exit;
  end;

  if SameText(Entity, 'amp') then
    Decoded := '&'
  else if SameText(Entity, 'lt') then
    Decoded := '<'
  else if SameText(Entity, 'gt') then
    Decoded := '>'
  else if SameText(Entity, 'quot') then
    Decoded := '"'
  else if SameText(Entity, 'apos') then
    Decoded := ''''
  else
  begin
    Result := False;
    Exit;
  end;

  Result := True;
end;

end.
