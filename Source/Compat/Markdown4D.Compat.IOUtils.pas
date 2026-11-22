unit Markdown4D.Compat.IOUtils;
{ The few System.IOUtils calls the library makes: TPath.Combine, GetFullPath,
  IsPathRooted, and TFile.ReadAllBytes / WriteAllBytes. }

{$mode delphiunicode}{$H+}

interface

uses
  SysUtils, Classes;

type
  TPath = class
  public
    class function Combine(const Path1, Path2: string): string; overload; static;
    class function Combine(const Paths: array of string): string; overload; static;
    class function GetFullPath(const Path: string): string; static;
    class function IsPathRooted(const Path: string): Boolean; static;
  end;

  TFile = class
  public
    class function ReadAllBytes(const FileName: string): TBytes; static;
    class procedure WriteAllBytes(const FileName: string;
      const Bytes: TBytes); static;
  end;

implementation

class function TPath.Combine(const Path1, Path2: string): string;
begin
  if Path1 = '' then
    Exit(Path2);
  if Path2 = '' then
    Exit(Path1);
  if IsPathRooted(Path2) then
    Exit(Path2);
  Result := IncludeTrailingPathDelimiter(Path1) + Path2;
end;

class function TPath.Combine(const Paths: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := Low(Paths) to High(Paths) do
    Result := Combine(Result, Paths[Index]);
end;

class function TPath.GetFullPath(const Path: string): string;
begin
  if Path = '' then
    Exit('');
  Result := ExpandFileName(Path);
end;

class function TPath.IsPathRooted(const Path: string): Boolean;
var
  First: Char;
begin
  // The set-of test `Path[1] in [PathDelim, DriveDelim]` reads the same here,
  // but a WideChar subscript is not an ordinal to every compiler switch, so
  // the two probes are spelled out.
  Result := False;
  if Path = '' then
    Exit;
  First := Path[1];
  Result := (First = PathDelim) or (First = DriveDelim);
end;

class function TFile.ReadAllBytes(const FileName: string): TBytes;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[0], Stream.Size);
  finally
    Stream.Free;
  end;
end;

class procedure TFile.WriteAllBytes(const FileName: string;
  const Bytes: TBytes);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    if System.Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], System.Length(Bytes));
  finally
    Stream.Free;
  end;
end;

end.
