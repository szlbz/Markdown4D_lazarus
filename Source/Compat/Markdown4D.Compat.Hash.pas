unit Markdown4D.Compat.Hash;
{ THashBobJenkins from System.Hash, over FPC's BobJenkinsHash.  The library
  only uses it to fold the parts of a cache key into one Integer. }

{$mode delphiunicode}{$H+}

interface

uses
  SysUtils;

type
  THashBobJenkins = class
  public
    class function GetHashValue(const Value: string): Integer; overload; static;
    class function GetHashValue(const Value: Single; const Len: Integer;
      const Init: Integer): Integer; overload; static;
    class function GetHashValue(const Value: Integer; const Len: Integer;
      const Init: Integer): Integer; overload; static;
  end;

implementation

uses
  Generics.Defaults;

class function THashBobJenkins.GetHashValue(const Value: string): Integer;
var
  Data: RawByteString;
begin
  Data := UTF8Encode(Value);
  if Data = '' then
    Result := 0
  else
    Result := BobJenkinsHash(Data[1], System.Length(Data), 0);
end;

class function THashBobJenkins.GetHashValue(const Value: Single;
  const Len: Integer; const Init: Integer): Integer;
begin
  Result := BobJenkinsHash(Value, Len, Init);
end;

class function THashBobJenkins.GetHashValue(const Value: Integer;
  const Len: Integer; const Init: Integer): Integer;
begin
  Result := BobJenkinsHash(Value, Len, Init);
end;

end.
