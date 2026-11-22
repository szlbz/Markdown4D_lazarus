unit Markdown4D.Compat.Str;
{ The Unicode-correct replacement for the pieces of SysUtils that FPC
  implements on top of AnsiString:

    * TStringBuilder - FPC's is AnsiString based, so appending a Unicode
      string stores UTF-8 bytes;
    * Format('%s', ...) - funnels the argument through the system code page,
      turning every non-ASCII character into '?';
    * TStrings.LoadFromFile - same story, hence ReadFileUtf8;
    * TMonitor - FPC's crashes on a plain TObject;
    * MemoryBarrier - lives in System.SyncObjs on Delphi.

  Units list this one after SysUtils, and the later unit shadows the earlier. }

{$mode delphiunicode}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$H+}

interface

uses
  SysUtils, Classes;

function ReadFileUtf8(const FileName: string): string;
function FoldCase(const Value: string): string;
function Format(const Fmt: string; const Args: array of const): string;
procedure MemoryBarrier; inline;

type
  // Delphi's generic delegates live in System.SysUtils, which FPC does not
  // have; the ones the library names are declared here.
  TFunc<T, TResult> = reference to function(Arg1: T): TResult;
  TFunc<T1, T2, TResult> = reference to function(Arg1: T1; Arg2: T2): TResult;
  TProc = reference to procedure;
  TProc<T> = reference to procedure(Arg1: T);
  TProc<T1, T2> = reference to procedure(Arg1: T1; Arg2: T2);

  TMonitor = class sealed
  public
    class procedure Enter(const AObject: TObject); static;
    class procedure Exit(const AObject: TObject); static;
    class function TryEnter(const AObject: TObject): Boolean; static;
  end;

  TStringBuilder = class
  private
    FData: string;
    function GetLength: Integer;
    procedure SetLength(Value: Integer);
    function GetChars(Index: Integer): Char;
    procedure SetChars(Index: Integer; Value: Char);
  public
    constructor Create; overload;
    constructor Create(ACapacity: Integer); overload;
    constructor Create(const AValue: string); overload;

    function Append(const Value: string): TStringBuilder; overload;
    function Append(const Value: Char): TStringBuilder; overload;
    function Append(const Value: Char; RepeatCount: Integer): TStringBuilder; overload;
    function Append(Value: Integer): TStringBuilder; overload;
    function Append(Value: Int64): TStringBuilder; overload;
    function Append(Value: Boolean): TStringBuilder; overload;
    function Append(const Value: array of Char): TStringBuilder; overload;

    function AppendLine: TStringBuilder; overload;
    function AppendLine(const Value: string): TStringBuilder; overload;

    function Insert(Index: Integer; const Value: string): TStringBuilder; overload;
    function Remove(StartIndex, Count: Integer): TStringBuilder; overload;
    function Replace(const OldValue, NewValue: string): TStringBuilder; overload;

    function IndexOf(const Value: string): Integer; overload;
    function IndexOf(const Value: Char): Integer; overload;

    procedure Clear;
    function ToString: string;
    function Substring(StartIndex: Integer): string; overload;
    function Substring(StartIndex, ALength: Integer): string; overload;

    property Length: Integer read GetLength write SetLength;
    property Chars[Index: Integer]: Char read GetChars write SetChars; default;
  end;

implementation

var
  MonitorLock: TRTLCriticalSection;

{ TStrings.LoadFromFile funnels the text through the system code page and loses
  what it cannot represent; reading bytes and decoding UTF-8 keeps everything. }
function ReadFileUtf8(const FileName: string): string;
var
  Stream: TFileStream;
  Raw: RawByteString;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Raw, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Raw[1], Stream.Size);
  finally
    Stream.Free;
  end;
  Result := UTF8Decode(Raw);
  if (Length(Result) > 0) and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

{ FPC's ToLower only folds ASCII, which breaks link labels written in Greek,
  Cyrillic or with the German sharp S. This covers the ranges those use. }
function FoldCase(const Value: string): string;
var
  Index: Integer;
  Code: Integer;
begin
  Result := Value;
  for Index := 1 to Length(Result) do
  begin
    Code := Ord(Result[Index]);
    if (Code >= Ord('A')) and (Code <= Ord('Z')) then
      Inc(Result[Index], 32)
    else if (Code >= $00C0) and (Code <= $00DE) and (Code <> $00D7) then
      Inc(Result[Index], 32)
    else if (Code >= $0391) and (Code <= $03A9) and (Code <> $03A2) then
      Inc(Result[Index], 32)
    else if (Code >= $0410) and (Code <= $042F) then
      Inc(Result[Index], 32)
    else if Code = $0401 then
      Result[Index] := #$0451
    else if Code = $1E9E then
      Result[Index] := #$00DF;
  end;
end;

function ArgToStr(const Value: TVarRec): string;
begin
  case Value.VType of
    vtInteger: Result := IntToStr(Value.VInteger);
    vtInt64: Result := IntToStr(Value.VInt64^);
    vtBoolean: if Value.VBoolean then Result := 'True' else Result := 'False';
    vtChar: Result := Value.VChar;
    vtWideChar: Result := Value.VWideChar;
    vtString: Result := string(Value.VString^);
    vtAnsiString: Result := string(AnsiString(Value.VAnsiString));
    vtUnicodeString: Result := UnicodeString(Value.VUnicodeString);
    vtPChar: Result := string(Value.VPChar);
    vtExtended: Result := FloatToStr(Value.VExtended^);
    vtCurrency: Result := CurrToStr(Value.VCurrency^);
  else
    Result := '';
  end;
end;

{ Applies the flags/width/precision part of a format specifier. Precision
  means decimals for %f, minimum digits for %x and truncation for %s. }
function ApplyWidth(const Body, Spec: string; const Kind: Char): string;
var
  Index, Width, Precision: Integer;
  Pad: Char;
  Left, Zero: Boolean;
begin
  Pad := ' ';
  Left := False;
  Zero := False;
  Width := 0;
  Precision := -1;
  Result := Body;

  Index := 1;
  while Index <= Length(Spec) do
  begin
    case Spec[Index] of
      '-':
        Left := True;
      '.':
        begin
          Inc(Index);
          Precision := 0;
          while (Index <= Length(Spec)) and (Spec[Index] in ['0'..'9']) do
          begin
            Precision := Precision * 10 + (Ord(Spec[Index]) - Ord('0'));
            Inc(Index);
          end;
          Continue;
        end;
      '0'..'9':
        begin
          if Index = 1 then
            Zero := Spec[Index] = '0';
          Width := 0;
          while (Index <= Length(Spec)) and (Spec[Index] in ['0'..'9']) do
          begin
            Width := Width * 10 + (Ord(Spec[Index]) - Ord('0'));
            Inc(Index);
          end;
          Continue;
        end;
    end;
    Inc(Index);
  end;

  case Kind of
    'f':
      if Precision >= 0 then
      begin
        if Pos('.', Result) = 0 then
          Result := Result + '.';
        while Length(Result) - Pos('.', Result) < Precision do
          Result := Result + '0';
      end;
    'x', 'X':
      if Precision > 0 then
        while Length(Result) < Precision do
          Result := '0' + Result;
    's':
      if (Precision >= 0) and (Length(Result) > Precision) then
        Result := Copy(Result, 1, Precision);
  end;

  if Left then
  begin
    while Length(Result) < Width do
      Result := Result + ' ';
  end
  else
  begin
    if Zero then
      Pad := '0';
    while Length(Result) < Width do
      Result := Pad + Result;
  end;
end;

function Format(const Fmt: string; const Args: array of const): string;
var
  Index, ArgIndex, SpecStart, Precision: Integer;
  Spec, Body: string;
  Kind: Char;
begin
  Result := '';
  ArgIndex := 0;
  Index := 1;
  while Index <= Length(Fmt) do
  begin
    if Fmt[Index] <> '%' then
    begin
      Result := Result + Fmt[Index];
      Inc(Index);
      Continue;
    end;

    Inc(Index);
    if (Index <= Length(Fmt)) and (Fmt[Index] = '%') then
    begin
      Result := Result + '%';
      Inc(Index);
      Continue;
    end;

    SpecStart := Index;
    while (Index <= Length(Fmt)) and not (Fmt[Index] in ['a'..'z', 'A'..'Z']) do
      Inc(Index);
    if Index > Length(Fmt) then
      Break;

    Kind := Fmt[Index];
    Spec := Copy(Fmt, SpecStart, Index - SpecStart);
    Inc(Index);

    if ArgIndex > High(Args) then
      Continue;

    case Kind of
      's':
        Body := ArgToStr(Args[ArgIndex]);
      'd':
        Body := IntToStr(Args[ArgIndex].VInteger);
      'f':
        begin
          Precision := 2;
          if Pos('.', Spec) > 0 then
            Precision := StrToIntDef(Copy(Spec, Pos('.', Spec) + 1, 10), 2);
          Body := FloatToStrF(Args[ArgIndex].VExtended^, ffFixed, 15, Precision);
        end;
      'x':
        Body := IntToHex(Args[ArgIndex].VInteger, 1);
      'X':
        Body := UpperCase(IntToHex(Args[ArgIndex].VInteger, 1));
    else
      Body := ArgToStr(Args[ArgIndex]);
    end;

    Result := Result + ApplyWidth(Body, Spec, Kind);
    Inc(ArgIndex);
  end;
end;

procedure MemoryBarrier;
begin
  ReadWriteBarrier;
end;

class procedure TMonitor.Enter(const AObject: TObject);
begin
  EnterCriticalSection(MonitorLock);
end;

class procedure TMonitor.Exit(const AObject: TObject);
begin
  LeaveCriticalSection(MonitorLock);
end;

class function TMonitor.TryEnter(const AObject: TObject): Boolean;
begin
  Result := TryEnterCriticalSection(MonitorLock) <> 0;
end;

constructor TStringBuilder.Create;
begin
  inherited Create;
  FData := '';
end;

constructor TStringBuilder.Create(ACapacity: Integer);
begin
  inherited Create;
  FData := '';
end;

constructor TStringBuilder.Create(const AValue: string);
begin
  inherited Create;
  FData := AValue;
end;

function TStringBuilder.GetLength: Integer;
begin
  Result := System.Length(FData);
end;

procedure TStringBuilder.SetLength(Value: Integer);
begin
  System.SetLength(FData, Value);
end;

function TStringBuilder.GetChars(Index: Integer): Char;
begin
  Result := FData[Index + 1];
end;

procedure TStringBuilder.SetChars(Index: Integer; Value: Char);
begin
  FData[Index + 1] := Value;
end;

function TStringBuilder.Append(const Value: string): TStringBuilder;
begin
  FData := FData + Value;
  Result := Self;
end;

function TStringBuilder.Append(const Value: Char): TStringBuilder;
begin
  FData := FData + Value;
  Result := Self;
end;

function TStringBuilder.Append(const Value: Char; RepeatCount: Integer): TStringBuilder;
var
  Index: Integer;
begin
  for Index := 1 to RepeatCount do
    FData := FData + Value;
  Result := Self;
end;

function TStringBuilder.Append(Value: Integer): TStringBuilder;
begin
  FData := FData + IntToStr(Value);
  Result := Self;
end;

function TStringBuilder.Append(Value: Int64): TStringBuilder;
begin
  FData := FData + IntToStr(Value);
  Result := Self;
end;

function TStringBuilder.Append(Value: Boolean): TStringBuilder;
begin
  if Value then
    FData := FData + 'True'
  else
    FData := FData + 'False';
  Result := Self;
end;

function TStringBuilder.Append(const Value: array of Char): TStringBuilder;
var
  Index: Integer;
begin
  for Index := 0 to System.Length(Value) - 1 do
    FData := FData + Value[Index];
  Result := Self;
end;

function TStringBuilder.AppendLine: TStringBuilder;
begin
  FData := FData + sLineBreak;
  Result := Self;
end;

function TStringBuilder.AppendLine(const Value: string): TStringBuilder;
begin
  FData := FData + Value + sLineBreak;
  Result := Self;
end;

function TStringBuilder.Insert(Index: Integer; const Value: string): TStringBuilder;
begin
  System.Insert(Value, FData, Index + 1);
  Result := Self;
end;

function TStringBuilder.Remove(StartIndex, Count: Integer): TStringBuilder;
begin
  if Count > 0 then
    System.Delete(FData, StartIndex + 1, Count);
  Result := Self;
end;

function TStringBuilder.Replace(const OldValue, NewValue: string): TStringBuilder;
begin
  FData := StringReplace(FData, OldValue, NewValue, [rfReplaceAll]);
  Result := Self;
end;

function TStringBuilder.IndexOf(const Value: string): Integer;
begin
  Result := Pos(Value, FData) - 1;
end;

function TStringBuilder.IndexOf(const Value: Char): Integer;
begin
  Result := Pos(Value, FData) - 1;
end;

procedure TStringBuilder.Clear;
begin
  FData := '';
end;

function TStringBuilder.ToString: string;
begin
  Result := FData;
end;

function TStringBuilder.Substring(StartIndex: Integer): string;
begin
  Result := System.Copy(FData, StartIndex + 1, MaxInt);
end;

function TStringBuilder.Substring(StartIndex, ALength: Integer): string;
begin
  Result := System.Copy(FData, StartIndex + 1, ALength);
end;

initialization
  InitCriticalSection(MonitorLock);

finalization
  DoneCriticalSection(MonitorLock);

end.
