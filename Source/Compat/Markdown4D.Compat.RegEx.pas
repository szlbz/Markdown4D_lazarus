unit Markdown4D.Compat.RegEx;
{ Delphi System.RegularExpressions surface on top of FPC's Unicode TRegExpr. }

{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}

interface

uses
  SysUtils,
  Classes,
  Generics.Collections,
  uregexpr;

type
  TRegExOption = (roNone, roIgnoreCase, roMultiline, roSingleLine, roCompiled,
    roExplicitCapture, roIgnorePatternSpace);
  TRegExOptions = set of TRegExOption;

  TGroup = record
    Value: string;
    Index: Integer;
    Length: Integer;
    Success: Boolean;
    constructor Create(const AValue: string; const AIndex, ALength: Integer);
  end;

  TGroupCollection = record
  strict private
    FItems: TArray<TGroup>;
    function GetItem(const Index: Integer): TGroup;
    function GetCount: Integer;
  public
    class function Create(const Items: TArray<TGroup>): TGroupCollection; static;
    property Items[const Index: Integer]: TGroup read GetItem; default;
    property Count: Integer read GetCount;
  end;

  TMatch = record
  strict private
    FSuccess: Boolean;
    FIndex: Integer;
    FLength: Integer;
    FValue: string;
    FGroups: TGroupCollection;
    function GetSuccess: Boolean;
    function GetIndex: Integer;
    function GetLength: Integer;
    function GetValue: string;
    function GetGroups: TGroupCollection;
  public
    class function Empty: TMatch; static;
    class function Create(const ASuccess: Boolean; const AIndex, ALength: Integer;
      const AValue: string; const AGroups: TGroupCollection): TMatch; static;
    property Success: Boolean read GetSuccess;
    property Index: Integer read GetIndex;
    property Length: Integer read GetLength;
    property Value: string read GetValue;
    property Groups: TGroupCollection read GetGroups;
  end;

  TRegEx = class
  strict private
    FEngine: TRegExpr;
    FSubExprCount: Integer;
    FAnchored: Boolean;
    class var FCache: TDictionary<string, TRegEx>;
    function RunMatch(const Input: string; const Offset: Integer): TMatch;
  public
    constructor Create(const Pattern: string; const Options: TRegExOptions = []);
    destructor Destroy; override;
    function Match(const Input: string; const Start: Integer = 1): TMatch; overload;
    function IsMatch(const Input: string): Boolean; overload;
    function Replace(const Input, Replacement: string): string; overload;
    class function Match(const Input, Pattern: string;
      const Options: TRegExOptions = []): TMatch; overload; static;
    class function IsMatch(const Input, Pattern: string;
      const Options: TRegExOptions = []): Boolean; overload; static;
    class function Replace(const Input, Pattern, Replacement: string;
      const Options: TRegExOptions = []): string; overload; static;
    class destructor Destroy;
  end;

implementation

function ModifiersOf(const Options: TRegExOptions): string;
begin
  Result := '';
  if roIgnoreCase in Options then
    Result := Result + 'i';
  if roMultiline in Options then
    Result := Result + 'm';
  if roSingleLine in Options then
    Result := Result + 's';
  if roIgnorePatternSpace in Options then
    Result := Result + 'x';
end;

{ TGroup }

constructor TGroup.Create(const AValue: string; const AIndex, ALength: Integer);
begin
  Value := AValue;
  Index := AIndex;
  Length := ALength;
  Success := AIndex > 0;
end;

{ TGroupCollection }

class function TGroupCollection.Create(const Items: TArray<TGroup>): TGroupCollection;
begin
  Result.FItems := Items;
end;

function TGroupCollection.GetItem(const Index: Integer): TGroup;
begin
  if (Index >= 0) and (Index < Length(FItems)) then
    Result := FItems[Index]
  else
    Result := TGroup.Create('', 0, 0);
end;

function TGroupCollection.GetCount: Integer;
begin
  Result := Length(FItems);
end;

{ TMatch }

class function TMatch.Empty: TMatch;
begin
  Result.FSuccess := False;
  Result.FIndex := 0;
  Result.FLength := 0;
  Result.FValue := '';
  Result.FGroups := TGroupCollection.Create([]);
end;

class function TMatch.Create(const ASuccess: Boolean; const AIndex, ALength: Integer;
  const AValue: string; const AGroups: TGroupCollection): TMatch;
begin
  Result.FSuccess := ASuccess;
  Result.FIndex := AIndex;
  Result.FLength := ALength;
  Result.FValue := AValue;
  Result.FGroups := AGroups;
end;

function TMatch.GetSuccess: Boolean;
begin
  Result := FSuccess;
end;

function TMatch.GetIndex: Integer;
begin
  Result := FIndex;
end;

function TMatch.GetLength: Integer;
begin
  Result := FLength;
end;

function TMatch.GetValue: string;
begin
  Result := FValue;
end;

function TMatch.GetGroups: TGroupCollection;
begin
  Result := FGroups;
end;

{ TRegEx }

function CountCaptureGroups(const Pattern: string): Integer;
var
  Index: Integer;
  InClass: Boolean;
  Ch: Char;
begin
  Result := 0;
  InClass := False;
  Index := 1;
  while Index <= Length(Pattern) do
  begin
    Ch := Pattern[Index];
    if Ch = '\\' then
      Inc(Index, 2)
    else if InClass then
    begin
      if Ch = ']' then
        InClass := False;
      Inc(Index);
    end
    else if Ch = '[' then
    begin
      InClass := True;
      Inc(Index);
    end
    else if Ch = '(' then
    begin
      if (Index < Length(Pattern)) and (Pattern[Index + 1] = '?') then
      begin
        // (?: (?= (?! (?<= (?<! (?# are not capturing groups
        if (Index + 2 <= Length(Pattern)) and (Pattern[Index + 2] in ['P', '>', '#', '&', 'R']) then
          Inc(Index)
        else
          Inc(Index, 2);
      end
      else
      begin
        Inc(Result);
        Inc(Index);
      end;
    end
    else
      Inc(Index);
  end;
end;

constructor TRegEx.Create(const Pattern: string; const Options: TRegExOptions);
var
  Modifiers, Effective: string;
begin
  { TRegExpr has no \G, which Delphi's callers use for 'match right here'.
    Dropping it and checking the match position afterwards is equivalent. }
  Effective := Pattern;
  FAnchored := False;
  if Copy(Effective, 1, 2) = '\G' then
  begin
    FAnchored := True;
    Effective := Copy(Effective, 3);
  end;
  FEngine := TRegExpr.Create(Effective);
  FSubExprCount := CountCaptureGroups(Effective);
  Modifiers := ModifiersOf(Options);
  if Modifiers <> '' then
    FEngine.ModifierStr := Modifiers;
end;

destructor TRegEx.Destroy;
begin
  FEngine.Free;
  inherited;
end;

class destructor TRegEx.Destroy;
begin
  FCache.Free;
  FCache := nil;
end;

function TRegEx.RunMatch(const Input: string; const Offset: Integer): TMatch;
var
  Groups: TArray<TGroup>;
  Index: Integer;
  Found: Boolean;
begin
  { ExecPos only sees the subject once InputString is set; a fresh engine has
    none, which silently turned every in-place match into a failure. }
  FEngine.InputString := Input;
  if Offset > 1 then
    Found := FEngine.ExecPos(Offset)
  else
    Found := FEngine.Exec(Input);

  if not Found then
    Exit(TMatch.Empty);

  if FAnchored and (Offset > 1) and (FEngine.MatchPos[0] <> Offset) then
    Exit(TMatch.Empty);

  SetLength(Groups, FSubExprCount + 1);
  for Index := 0 to High(Groups) do
    if (FEngine.MatchPos[Index] > 0) and (FEngine.MatchLen[Index] >= 0) then
      Groups[Index] := TGroup.Create(FEngine.Match[Index],
        FEngine.MatchPos[Index], FEngine.MatchLen[Index])
    else
      Groups[Index] := TGroup.Create('', 0, 0);

  Result := TMatch.Create(True, FEngine.MatchPos[0], FEngine.MatchLen[0],
    FEngine.Match[0], TGroupCollection.Create(Groups));
end;

function TRegEx.Match(const Input: string; const Start: Integer): TMatch;
begin
  Result := RunMatch(Input, Start);
end;

function TRegEx.IsMatch(const Input: string): Boolean;
begin
  Result := Match(Input).Success;
end;

function TRegEx.Replace(const Input, Replacement: string): string;
var
  Builder: TStringBuilder;
  Position: Integer;
  Current: TMatch;
begin
  Builder := TStringBuilder.Create;
  try
    Position := 1;
    Current := RunMatch(Input, Position);
    while Current.Success do
    begin
      Builder.Append(Copy(Input, Position, Current.Index - Position));
      Builder.Append(FEngine.Substitute(Replacement));
      Position := Current.Index + Current.Length;
      if Current.Length = 0 then
        Inc(Position);
      if Position > Length(Input) then
        Break;
      Current := RunMatch(Input, Position);
    end;
    if Position <= Length(Input) then
      Builder.Append(Copy(Input, Position, Length(Input) - Position + 1));
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TRegEx.Match(const Input, Pattern: string;
  const Options: TRegExOptions): TMatch;
var
  Key: string;
  Engine: TRegEx;
begin
  Key := ModifiersOf(Options) + '|' + Pattern;
  if FCache = nil then
    FCache := TDictionary<string, TRegEx>.Create;
  if not FCache.TryGetValue(Key, Engine) then
  begin
    Engine := TRegEx.Create(Pattern, Options);
    FCache.Add(Key, Engine);
  end;
  Result := Engine.Match(Input);
end;

class function TRegEx.IsMatch(const Input, Pattern: string;
  const Options: TRegExOptions): Boolean;
begin
  Result := TRegEx.Match(Input, Pattern, Options).Success;
end;

class function TRegEx.Replace(const Input, Pattern, Replacement: string;
  const Options: TRegExOptions): string;
var
  Key: string;
  Engine: TRegEx;
begin
  Key := ModifiersOf(Options) + '|' + Pattern;
  if FCache = nil then
    FCache := TDictionary<string, TRegEx>.Create;
  if not FCache.TryGetValue(Key, Engine) then
  begin
    Engine := TRegEx.Create(Pattern, Options);
    FCache.Add(Key, Engine);
  end;
  Result := Engine.Replace(Input, Replacement);
end;

end.
