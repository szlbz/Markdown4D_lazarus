unit Markdown4D.Compat.NetEncoding;
{ The two pieces of System.NetEncoding the library uses:

    * TNetEncoding.Base64.DecodeStringToBytes - FPC has no such class, and its
      base64 unit works on strings, so the decoder is spelled out here;
    * TNetEncoding.URL.Decode - percent-decoding into UTF-8.

  The call sites are rewritten to the functions below by the port script. }

{$mode delphiunicode}{$H+}

interface

uses
  SysUtils;

function M4DBase64Decode(const Value: string): TBytes;
function M4DUrlDecode(const Value: string): string;

implementation

const
  Base64Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

var
  Base64Values: array[0..255] of ShortInt;

procedure InitBase64;
var
  Index: Integer;
begin
  for Index := 0 to High(Base64Values) do
    Base64Values[Index] := -1;
  for Index := 1 to System.Length(Base64Alphabet) do
    Base64Values[Ord(Base64Alphabet[Index])] := Index - 1;
end;

function M4DBase64Decode(const Value: string): TBytes;
var
  Accumulator: Cardinal;
  Bits: Integer;
  Index: Integer;
  Ch: Char;
  Digit: ShortInt;
  Count: Integer;
begin
  SetLength(Result, 0);
  if Base64Values[Ord('A')] < 0 then
    InitBase64;

  Accumulator := 0;
  Bits := 0;
  Count := 0;
  SetLength(Result, (System.Length(Value) div 4 + 1) * 3);
  for Index := 1 to System.Length(Value) do
  begin
    Ch := Value[Index];
    // the payload is wrapped in the document, so whitespace is skipped
    if (Ch = '=') then
      Break;
    if Ord(Ch) > 255 then
      Continue;
    Digit := Base64Values[Ord(Ch)];
    if Digit < 0 then
      Continue;
    Accumulator := (Accumulator shl 6) or Cardinal(Digit);
    Inc(Bits, 6);
    if Bits >= 8 then
    begin
      Dec(Bits, 8);
      Result[Count] := Byte((Accumulator shr Bits) and $FF);
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function HexDigit(Ch: Char): Integer;
begin
  case Ch of
    '0'..'9': Result := Ord(Ch) - Ord('0');
    'a'..'f': Result := Ord(Ch) - Ord('a') + 10;
    'A'..'F': Result := Ord(Ch) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function M4DUrlDecode(const Value: string): string;
var
  Raw: RawByteString;
  Index: Integer;
  High1, Low1: Integer;
  Code: Integer;
begin
  Raw := '';
  Index := 1;
  while Index <= System.Length(Value) do
  begin
    if (Value[Index] = '%') and (Index + 2 <= System.Length(Value)) then
    begin
      High1 := HexDigit(Value[Index + 1]);
      Low1 := HexDigit(Value[Index + 2]);
      if (High1 >= 0) and (Low1 >= 0) then
      begin
        Code := High1 * 16 + Low1;
        Raw := Raw + AnsiChar(Code);
        Inc(Index, 3);
        Continue;
      end;
    end;
    if Ord(Value[Index]) < 128 then
      Raw := Raw + AnsiChar(Ord(Value[Index]))
    else
      Raw := Raw + UTF8Encode(Value[Index]);
    Inc(Index);
  end;
  Result := UTF8ToString(Raw);
end;

end.
