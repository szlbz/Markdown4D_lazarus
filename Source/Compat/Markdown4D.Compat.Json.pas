unit Markdown4D.Compat.Json;
{ A small, dependency-free subset of Delphi's System.JSON, enough for the
  chart/mermaid options and the theme import/export.  Everything is
  UnicodeString so it slips under delphiunicode mode without conversions. }

{$mode delphiunicode}

interface

uses
  SysUtils,
  Classes,
  Generics.Collections;

type
  TJSONValue = class
  protected
    function GetValueText: string; virtual;
    function GetIsNull: Boolean; virtual;
  public
    function ToJSON: string; virtual;
    property Value: string read GetValueText;
    property IsNull: Boolean read GetIsNull;
  end;

  TJSONString = class(TJSONValue)
  private
    FValue: string;
  protected
    function GetValueText: string; override;
  public
    constructor Create(const AValue: string);
    function ToJSON: string; override;
  end;

  TJSONNumber = class(TJSONValue)
  private
    FValue: Double;
    FText: string;
  protected
    function GetValueText: string; override;
  public
    constructor Create(const AValue: Double); overload;
    constructor Create(const AValue: Integer); overload;
    constructor Create(const AText: string; const IsText: Boolean); overload;
    function AsInt: Integer;
    function AsInt64: Int64;
    function AsDouble: Double;
    function ToJSON: string; override;
    property AsIntValue: Integer read AsInt;
  end;

  TJSONBool = class(TJSONValue)
  private
    FValue: Boolean;
  protected
    function GetValueText: string; override;
  public
    constructor Create(const AValue: Boolean);
    function AsBoolean: Boolean;
    function ToJSON: string; override;
  end;

  TJSONNull = class(TJSONValue)
  protected
    function GetValueText: string; override;
    function GetIsNull: Boolean; override;
  public
    constructor Create;
    function ToJSON: string; override;
  end;

  TJSONArray = class;

  TJSONPair = record
    Name: string;
    Value: TJSONValue;
  end;

  TJSONObject = class(TJSONValue)
  private
    FPairs: TArray<TJSONPair>;
    function IndexOfName(const Name: string): Integer;
    function GetCount: Integer;
    function GetPair(const Index: Integer): TJSONPair;
  protected
    function GetValueText: string; override;
  public
    destructor Destroy; override;
    function AddPair(const Name: string; const AValue: TJSONValue): TJSONObject; overload;
    function AddPair(const Name: string; const AValue: string): TJSONObject; overload;
    function AddPair(const Name: string; const AValue: Double): TJSONObject; overload;
    function AddPair(const Name: string; const AValue: Integer): TJSONObject; overload;
    function AddPair(const Name: string; const AValue: Boolean): TJSONObject; overload;
    function GetValue(const Name: string): TJSONValue;
    function TryGetValue(const Name: string; out AValue: TJSONValue): Boolean;
    property Count: Integer read GetCount;
    property Pairs[const Index: Integer]: TJSONPair read GetPair; default;
    function ToJSON: string; override;
    class function ParseJSONValue(const Data: string): TJSONValue; static;
  end;

  TJSONArray = class(TJSONValue)
  private
    FItems: TList<TJSONValue>;
    function GetCount: Integer;
    function GetItem(const Index: Integer): TJSONValue;
  protected
    function GetValueText: string; override;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const Element: TJSONValue): TJSONValue;
    function AddElement(const Element: TJSONValue): TJSONValue;
    property Count: Integer read GetCount;
    property Items[const Index: Integer]: TJSONValue read GetItem; default;
    function ToJSON: string; override;
  end;

function JSONEscape(const Value: string): string;

implementation

function JSONEscape(const Value: string): string;
var
  Index: Integer;
  Ch: Char;
begin
  Result := '';
  for Index := 1 to Length(Value) do
  begin
    Ch := Value[Index];
    case Ch of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      '/': Result := Result + '\/';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(Ch) < 32 then
        Result := Result + '\u' + IntToHex(Ord(Ch), 4)
      else
        Result := Result + Ch;
    end;
  end;
end;

{ TJSONValue }

function TJSONValue.GetValueText: string;
begin
  Result := '';
end;

function TJSONValue.GetIsNull: Boolean;
begin
  Result := False;
end;

function TJSONValue.ToJSON: string;
begin
  Result := Value;
end;

{ TJSONString }

constructor TJSONString.Create(const AValue: string);
begin
  FValue := AValue;
end;

function TJSONString.GetValueText: string;
begin
  Result := FValue;
end;

function TJSONString.ToJSON: string;
begin
  Result := '"' + JSONEscape(FValue) + '"';
end;

{ TJSONNumber }

constructor TJSONNumber.Create(const AValue: Double);
begin
  FValue := AValue;
  FText := '';
end;

constructor TJSONNumber.Create(const AValue: Integer);
begin
  FValue := AValue;
  FText := IntToStr(AValue);
end;

constructor TJSONNumber.Create(const AText: string; const IsText: Boolean);
begin
  FText := AText;
  if not TryStrToFloat(AText, FValue) then
    FValue := 0;
end;

function TJSONNumber.AsInt: Integer;
begin
  Result := Round(FValue);
end;

function TJSONNumber.AsInt64: Int64;
begin
  Result := Round(FValue);
end;

function TJSONNumber.AsDouble: Double;
begin
  Result := FValue;
end;

function TJSONNumber.GetValueText: string;
begin
  if FText <> '' then
    Result := FText
  else
    Result := FloatToStr(FValue, TFormatSettings.Invariant);
end;

function TJSONNumber.ToJSON: string;
begin
  Result := GetValueText;
end;

{ TJSONBool }

constructor TJSONBool.Create(const AValue: Boolean);
begin
  FValue := AValue;
end;

function TJSONBool.AsBoolean: Boolean;
begin
  Result := FValue;
end;

function TJSONBool.GetValueText: string;
begin
  if FValue then
    Result := 'true'
  else
    Result := 'false';
end;

function TJSONBool.ToJSON: string;
begin
  Result := GetValueText;
end;

{ TJSONNull }

constructor TJSONNull.Create;
begin
  inherited Create;
end;

function TJSONNull.GetValueText: string;
begin
  Result := 'null';
end;

function TJSONNull.GetIsNull: Boolean;
begin
  Result := True;
end;

function TJSONNull.ToJSON: string;
begin
  Result := 'null';
end;

{ TJSONObject }

destructor TJSONObject.Destroy;
var
  Index: Integer;
begin
  for Index := 0 to High(FPairs) do
    FPairs[Index].Value.Free;
  inherited;
end;

function TJSONObject.IndexOfName(const Name: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FPairs) do
    if SameText(FPairs[Index].Name, Name) then
      Exit(Index);
  Result := -1;
end;

function TJSONObject.GetCount: Integer;
begin
  Result := Length(FPairs);
end;

function TJSONObject.GetPair(const Index: Integer): TJSONPair;
begin
  if (Index >= 0) and (Index < Length(FPairs)) then
    Result := FPairs[Index]
  else
  begin
    Result.Name := '';
    Result.Value := nil;
  end;
end;

function TJSONObject.GetValueText: string;
begin
  Result := ToJSON;
end;

function TJSONObject.AddPair(const Name: string; const AValue: TJSONValue): TJSONObject;
var
  Position: Integer;
begin
  Position := IndexOfName(Name);
  if Position >= 0 then
  begin
    FPairs[Position].Value.Free;
    FPairs[Position].Value := AValue;
  end
  else
  begin
    SetLength(FPairs, Length(FPairs) + 1);
    FPairs[High(FPairs)].Name := Name;
    FPairs[High(FPairs)].Value := AValue;
  end;
  Result := Self;
end;

function TJSONObject.AddPair(const Name: string; const AValue: string): TJSONObject;
begin
  Result := AddPair(Name, TJSONString.Create(AValue));
end;

function TJSONObject.AddPair(const Name: string; const AValue: Double): TJSONObject;
begin
  Result := AddPair(Name, TJSONNumber.Create(AValue));
end;

function TJSONObject.AddPair(const Name: string; const AValue: Integer): TJSONObject;
begin
  Result := AddPair(Name, TJSONNumber.Create(AValue));
end;

function TJSONObject.AddPair(const Name: string; const AValue: Boolean): TJSONObject;
begin
  Result := AddPair(Name, TJSONBool.Create(AValue));
end;

function TJSONObject.GetValue(const Name: string): TJSONValue;
var
  Position: Integer;
begin
  Position := IndexOfName(Name);
  if Position >= 0 then
    Result := FPairs[Position].Value
  else
    Result := nil;
end;

function TJSONObject.TryGetValue(const Name: string; out AValue: TJSONValue): Boolean;
begin
  AValue := GetValue(Name);
  Result := AValue <> nil;
end;

function TJSONObject.ToJSON: string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{');
    for Index := 0 to High(FPairs) do
    begin
      if Index > 0 then
        Builder.Append(',');
      Builder.Append('"' + JSONEscape(FPairs[Index].Name) + '":');
      if FPairs[Index].Value <> nil then
        Builder.Append(FPairs[Index].Value.ToJSON)
      else
        Builder.Append('null');
    end;
    Builder.Append('}');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ --- parsing --------------------------------------------------------- }

type
  TJsonReader = record
    Text: string;
    Position: Integer;
    Failed: Boolean;
  end;

function SkipWhitespace(var Reader: TJsonReader): Boolean;
begin
  while (Reader.Position <= Length(Reader.Text)) and
        (Reader.Text[Reader.Position] <= ' ') do
    Inc(Reader.Position);
  Result := Reader.Position <= Length(Reader.Text);
end;

function PeekChar(var Reader: TJsonReader): Char;
begin
  if Reader.Position <= Length(Reader.Text) then
    Result := Reader.Text[Reader.Position]
  else
    Result := #0;
end;

function ReadString(var Reader: TJsonReader): string;
var
  Builder: TStringBuilder;
  Ch: Char;
  Code: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Inc(Reader.Position);  // opening quote
    while Reader.Position <= Length(Reader.Text) do
    begin
      Ch := Reader.Text[Reader.Position];
      if Ch = '"' then
      begin
        Inc(Reader.Position);
        Exit(Builder.ToString);
      end;
      if Ch = '\' then
      begin
        Inc(Reader.Position);
        if Reader.Position > Length(Reader.Text) then
          Break;
        Ch := Reader.Text[Reader.Position];
        case Ch of
          'n': Builder.Append(#10);
          'r': Builder.Append(#13);
          't': Builder.Append(#9);
          'b': Builder.Append(#8);
          'f': Builder.Append(#12);
          'u':
            begin
              if Reader.Position + 4 <= Length(Reader.Text) then
              begin
                Code := StrToIntDef('$' + Copy(Reader.Text, Reader.Position + 1, 4), 0);
                Builder.Append(WideChar(Code));
                Inc(Reader.Position, 4);
              end;
            end;
        else
          Builder.Append(Ch);
        end;
        Inc(Reader.Position);
        Continue;
      end;
      Builder.Append(Ch);
      Inc(Reader.Position);
    end;
    Reader.Failed := True;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function ParseValue(var Reader: TJsonReader): TJSONValue; forward;

function ParseObject(var Reader: TJsonReader): TJSONObject;
var
  Name: string;
begin
  Result := TJSONObject.Create;
  Inc(Reader.Position);  // {
  if not SkipWhitespace(Reader) then
  begin
    Reader.Failed := True;
    Exit;
  end;
  if PeekChar(Reader) = '}' then
  begin
    Inc(Reader.Position);
    Exit;
  end;
  while not Reader.Failed do
  begin
    if PeekChar(Reader) <> '"' then
    begin
      Reader.Failed := True;
      Break;
    end;
    Name := ReadString(Reader);
    if not SkipWhitespace(Reader) then
      Break;
    if PeekChar(Reader) <> ':' then
    begin
      Reader.Failed := True;
      Break;
    end;
    Inc(Reader.Position);
    if not SkipWhitespace(Reader) then
      Break;
    Result.AddPair(Name, ParseValue(Reader));
    if not SkipWhitespace(Reader) then
      Break;
    if PeekChar(Reader) = ',' then
    begin
      Inc(Reader.Position);
      SkipWhitespace(Reader);
      Continue;
    end;
    if PeekChar(Reader) = '}' then
    begin
      Inc(Reader.Position);
      Break;
    end;
    Reader.Failed := True;
    Break;
  end;
end;

function ParseArray(var Reader: TJsonReader): TJSONArray;
begin
  Result := TJSONArray.Create;
  Inc(Reader.Position);  // [
  if not SkipWhitespace(Reader) then
  begin
    Reader.Failed := True;
    Exit;
  end;
  if PeekChar(Reader) = ']' then
  begin
    Inc(Reader.Position);
    Exit;
  end;
  while not Reader.Failed do
  begin
    Result.Add(ParseValue(Reader));
    if not SkipWhitespace(Reader) then
      Break;
    if PeekChar(Reader) = ',' then
    begin
      Inc(Reader.Position);
      SkipWhitespace(Reader);
      Continue;
    end;
    if PeekChar(Reader) = ']' then
    begin
      Inc(Reader.Position);
      Break;
    end;
    Reader.Failed := True;
    Break;
  end;
end;

function ParseValue(var Reader: TJsonReader): TJSONValue;
var
  Start: Integer;
  Text: string;
  Ch: Char;
begin
  Result := nil;
  if not SkipWhitespace(Reader) then
  begin
    Reader.Failed := True;
    Exit;
  end;
  Ch := PeekChar(Reader);
  case Ch of
    '{': Result := ParseObject(Reader);
    '[': Result := ParseArray(Reader);
    '"': Result := TJSONString.Create(ReadString(Reader));
    't':
      begin
        if Copy(Reader.Text, Reader.Position, 4) = 'true' then
        begin
          Inc(Reader.Position, 4);
          Result := TJSONBool.Create(True);
        end
        else
          Reader.Failed := True;
      end;
    'f':
      begin
        if Copy(Reader.Text, Reader.Position, 5) = 'false' then
        begin
          Inc(Reader.Position, 5);
          Result := TJSONBool.Create(False);
        end
        else
          Reader.Failed := True;
      end;
    'n':
      begin
        if Copy(Reader.Text, Reader.Position, 4) = 'null' then
        begin
          Inc(Reader.Position, 4);
          Result := TJSONNull.Create;
        end
        else
          Reader.Failed := True;
      end;
  else
    Start := Reader.Position;
    while (Reader.Position <= Length(Reader.Text)) and
          (((Reader.Text[Reader.Position] >= '0') and (Reader.Text[Reader.Position] <= '9')) or
           (Reader.Text[Reader.Position] in ['-', '+', '.', 'e', 'E'])) do
      Inc(Reader.Position);
    if Reader.Position = Start then
      Reader.Failed := True
    else
    begin
      Text := Copy(Reader.Text, Start, Reader.Position - Start);
      Result := TJSONNumber.Create(Text, True);
    end;
  end;
end;

class function TJSONObject.ParseJSONValue(const Data: string): TJSONValue;
var
  Reader: TJsonReader;
begin
  Reader.Text := Data;
  Reader.Position := 1;
  Reader.Failed := False;
  Result := ParseValue(Reader);
  if Reader.Failed then
    FreeAndNil(Result);
end;

{ TJSONArray }

constructor TJSONArray.Create;
begin
  FItems := TList<TJSONValue>.Create;
end;

destructor TJSONArray.Destroy;
var
  Index: Integer;
begin
  for Index := 0 to FItems.Count - 1 do
    FItems[Index].Free;
  FItems.Free;
  inherited;
end;

function TJSONArray.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TJSONArray.GetItem(const Index: Integer): TJSONValue;
begin
  if (Index >= 0) and (Index < FItems.Count) then
    Result := FItems[Index]
  else
    Result := nil;
end;

function TJSONArray.GetValueText: string;
begin
  Result := ToJSON;
end;

function TJSONArray.Add(const Element: TJSONValue): TJSONValue;
begin
  FItems.Add(Element);
  Result := Element;
end;

function TJSONArray.AddElement(const Element: TJSONValue): TJSONValue;
begin
  Result := Add(Element);
end;

function TJSONArray.ToJSON: string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('[');
    for Index := 0 to FItems.Count - 1 do
    begin
      if Index > 0 then
        Builder.Append(',');
      if FItems[Index] <> nil then
        Builder.Append(FItems[Index].ToJSON)
      else
        Builder.Append('null');
    end;
    Builder.Append(']');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
