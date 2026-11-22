{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Text.Unescape;

{$SCOPEDENUMS ON}

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character;

type
  TMarkdownUnescape = class
  private
    const
      Semicolon = ';';
      NumberSign = '#';
    class function TryReadEntity(const Value: string; const Start: Integer; out Decoded: string;
                                 out Consumed: Integer): Boolean;
    class function IsEntityNameChar(const Value: Char): Boolean;

  public
    class function IsAsciiPunctuation(const Value: Char): Boolean;
    class function IsMarkdownWhitespace(const Value: Char): Boolean;
    class function Unescape(const Value: string): string;
    class function TryDecodeEntityAt(const Value: string; const Start: Integer; out Decoded: string;
                                     out Consumed: Integer): Boolean;
    class function NormalizeUri(const Value: string): string;
  end;

implementation

uses
  Markdown4D.Defines,
  Markdown4D.Html.Entities;

class function TMarkdownUnescape.Unescape(const Value: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  Current: Char;
  IsEscape: Boolean;
  Decoded: string;
  Consumed: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Index := 1;

    while Index <= Length(Value) do
    begin
      Current := Value[Index];

      IsEscape := (Current = Backslash) and (Index < Length(Value)) and IsAsciiPunctuation(Value[Index + 1]);
      if IsEscape then
      begin
        Builder.Append(Value[Index + 1]);
        Inc(Index, 2);
        Continue;
      end;

      if Current = Ampersand then
      begin
        
        

        if TryReadEntity(Value, Index, Decoded, Consumed) then
        begin
          Builder.Append(Decoded);
          Inc(Index, Consumed);
          Continue;
        end;
      end;

      Builder.Append(Current);
      Inc(Index);
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TMarkdownUnescape.TryDecodeEntityAt(const Value: string; const Start: Integer; out Decoded: string;
                                                   out Consumed: Integer): Boolean;
begin
  Result := TryReadEntity(Value, Start, Decoded, Consumed);
end;

class function TMarkdownUnescape.TryReadEntity(const Value: string; const Start: Integer; out Decoded: string;
                                               out Consumed: Integer): Boolean;
var
  StartsWithAmpersand: Boolean;
  IsNumeric: Boolean;
  Index: Integer;
  IsHex: Boolean;
  BodyStart: Integer;
  AllowedDigits: TSysCharSet;
  HasBody: Boolean;
  HasTerminator: Boolean;
  Body: string;
begin
  Decoded := '';
  Consumed := 0;

  StartsWithAmpersand := (Start <= Length(Value)) and (Value[Start] = Ampersand);
  if not StartsWithAmpersand then
  begin
    Result := False;
    Exit;
  end;

  IsNumeric := (Start < Length(Value)) and (Value[Start + 1] = NumberSign);
  Index := Start + 1;
  if IsNumeric then
    Inc(Index);

  IsHex := IsNumeric and (Index <= Length(Value)) and CharInSet(Value[Index], ['x', 'X']);
  if IsHex then
    Inc(Index);

  BodyStart := Index;

  if IsNumeric then
  begin
    AllowedDigits := ['0'..'9'];
    if IsHex then
      AllowedDigits := ['0'..'9', 'a'..'f', 'A'..'F'];

    while (Index <= Length(Value)) and CharInSet(Value[Index], AllowedDigits) do
    begin
      Inc(Index);
    end;
  end
  else
  begin
    while (Index <= Length(Value)) and IsEntityNameChar(Value[Index]) do
    begin
      Inc(Index);
    end;
  end;

  HasBody := (Index > BodyStart);
  HasTerminator := HasBody and (Index <= Length(Value)) and (Value[Index] = Semicolon);
  if not HasTerminator then
  begin
    Result := False;
    Exit;
  end;

  Body := Copy(Value, Start + 1, Index - Start - 1);

  if IsNumeric then
    Result := THtmlEntities.TryDecodeNumeric(Body, Decoded)
  else
    Result := THtmlEntities.TryDecode(Body, Decoded);

  if Result then
    Consumed := Index - Start + 1;
end;

class function TMarkdownUnescape.IsEntityNameChar(const Value: Char): Boolean;
begin
  Result := CharInSet(Value, ['0'..'9', 'a'..'z', 'A'..'Z']);
end;

class function TMarkdownUnescape.IsAsciiPunctuation(const Value: Char): Boolean;
begin
  Result := CharInSet(Value, ['!'..'/', ':'..'@', '['..'`', '{'..'~']);
end;

class function TMarkdownUnescape.IsMarkdownWhitespace(const Value: Char): Boolean;
begin
  Result := CharInSet(Value, [' ', #9, #10, #11, #12, #13]);
end;

class function TMarkdownUnescape.NormalizeUri(const Value: string): string;
const
  UnreservedChars: TSysCharSet = ['A'..'Z', 'a'..'z', '0'..'9', ';', ',', '/', '?', ':', '@', '&', '=', '+', '$',
    '-', '_', '.', '!', '~', '*', '''', '(', ')', '#', '%'];
  PercentEncodedFormat = '%%%2.2X';
var
  Builder: TStringBuilder;
  Utf8Bytes: TBytes;
  CurrentByte: Byte;
  IsUnreserved: Boolean;
begin
  Builder := TStringBuilder.Create;
  try
    Utf8Bytes := TEncoding.UTF8.GetBytes(Value);

    for CurrentByte in Utf8Bytes do
    begin
      IsUnreserved := (CurrentByte < $80) and CharInSet(Char(CurrentByte), UnreservedChars);

      if IsUnreserved then
        Builder.Append(Char(CurrentByte))
      else
        Builder.Append(Format(PercentEncodedFormat, [CurrentByte]));
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
