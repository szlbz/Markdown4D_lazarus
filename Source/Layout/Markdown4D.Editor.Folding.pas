{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Editor.Folding;

{$SCOPEDENUMS ON}

// Framework-neutral fold-region derivation for the source editor. A fold region
// has a visible header line that carries the toggle and a run of following lines
// that disappear when the region is collapsed. Two kinds are recognised: fenced
// code blocks (fence line to matching close) and heading sections (a heading down
// to the line before the next heading of equal or higher level).

interface

type
  TFoldRegion = record
    HeaderLine: Integer;
    StartLine: Integer;
    EndLine: Integer;
    class function Create(const HeaderLine, StartLine, EndLine: Integer): TFoldRegion; static;
    function Contains(const LineIndex: Integer): Boolean;
  end;

  TMarkdownFoldComputer = record
    class function ComputeRegions(const Lines: TArray<string>): TArray<TFoldRegion>; static;
  private
    const
      MaxHeadingLevel = 6;
      MinFenceLength = 3;
    type
      TOpenHeading = record
        Line: Integer;
        Level: Integer;
      end;
    class function IsFenceOpen(const Line: string; out FenceChar: Char; out FenceLength: Integer): Boolean; static;
    class function IsFenceClose(const Line: string; const FenceChar: Char; const FenceLength: Integer): Boolean; static;
    class function HeadingLevel(const Line: string): Integer; static;
    class function LeadingRun(const Text: string; const Ch: Char): Integer; static;
  end;

implementation

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  Generics.Collections;

class function TFoldRegion.Create(const HeaderLine, StartLine, EndLine: Integer): TFoldRegion;
begin
  Result.HeaderLine := HeaderLine;
  Result.StartLine := StartLine;
  Result.EndLine := EndLine;
end;

function TFoldRegion.Contains(const LineIndex: Integer): Boolean;
begin
  Result := (LineIndex >= StartLine) and (LineIndex <= EndLine);
end;

class function TMarkdownFoldComputer.ComputeRegions(const Lines: TArray<string>): TArray<TFoldRegion>;
var
  Regions: TList<TFoldRegion>;
  OpenHeadings: TArray<TOpenHeading>;
  LineCount: Integer;
  Index: Integer;
  FenceChar: Char;
  FenceLength: Integer;
  CloseLine: Integer;
  Scan: Integer;
  EndLine: Integer;
  Level: Integer;
  Top: TOpenHeading;
  Opened: TOpenHeading;
begin
  // Regions accumulate one per fence or heading found while scanning the whole
  // document, so a TList avoids the O(n^2) cost of growing an array one element
  // at a time; OpenHeadings never holds more than MaxHeadingLevel entries, so it
  // stays a plain array.
  Regions := TList<TFoldRegion>.Create;
  try
    OpenHeadings := [];
    LineCount := Length(Lines);

    Index := 0;
    while Index < LineCount do
    begin
      
      
      if IsFenceOpen(Lines[Index], FenceChar, FenceLength) then
      begin
        CloseLine := -1;
        Scan := Index + 1;
        while Scan < LineCount do
        begin
          if IsFenceClose(Lines[Scan], FenceChar, FenceLength) then
          begin
            CloseLine := Scan;
            Break;
          end;
          Inc(Scan);
        end;

        EndLine := CloseLine;
        if EndLine < 0 then
          EndLine := LineCount - 1;

        if EndLine > Index then
          Regions.Add(TFoldRegion.Create(Index, Index + 1, EndLine));

        Index := EndLine + 1;
        Continue;
      end;

      Level := HeadingLevel(Lines[Index]);
      if Level > 0 then
      begin
        while (Length(OpenHeadings) > 0) and (OpenHeadings[High(OpenHeadings)].Level >= Level) do
        begin
          Top := OpenHeadings[High(OpenHeadings)];
          SetLength(OpenHeadings, Length(OpenHeadings) - 1);
          if Index - 1 >= Top.Line + 1 then
            Regions.Add(TFoldRegion.Create(Top.Line, Top.Line + 1, Index - 1));
        end;

        Opened := Default(TOpenHeading);
        Opened.Line := Index;
        Opened.Level := Level;
        OpenHeadings := OpenHeadings + [Opened];
      end;

      Inc(Index);
    end;

    while Length(OpenHeadings) > 0 do
    begin
      Top := OpenHeadings[High(OpenHeadings)];
      SetLength(OpenHeadings, Length(OpenHeadings) - 1);
      if LineCount - 1 >= Top.Line + 1 then
        Regions.Add(TFoldRegion.Create(Top.Line, Top.Line + 1, LineCount - 1));
    end;

    Result := Regions.ToArray;
  finally
    Regions.Free;
  end;
end;

class function TMarkdownFoldComputer.IsFenceOpen(const Line: string; out FenceChar: Char;
  out FenceLength: Integer): Boolean;
var
  Trimmed: string;
  First: Char;
  Run: Integer;
begin
  FenceChar := #0;
  FenceLength := 0;

  Trimmed := TrimLeft(Line);
  if Trimmed = '' then
  begin
    Result := False;
    Exit;
  end;

  First := Trimmed[1];
  if (First <> '`') and (First <> '~') then
  begin
    Result := False;
    Exit;
  end;

  Run := LeadingRun(Trimmed, First);
  if Run < MinFenceLength then
  begin
    Result := False;
    Exit;
  end;

  FenceChar := First;
  FenceLength := Run;
  Result := True;
end;

class function TMarkdownFoldComputer.IsFenceClose(const Line: string; const FenceChar: Char;
  const FenceLength: Integer): Boolean;
var
  Trimmed: string;
  Run: Integer;
begin
  Trimmed := Trim(Line);
  if Trimmed = '' then
  begin
    Result := False;
    Exit;
  end;

  Run := LeadingRun(Trimmed, FenceChar);
  Result := (Run >= FenceLength) and (Run = Length(Trimmed));
end;

class function TMarkdownFoldComputer.HeadingLevel(const Line: string): Integer;
var
  Trimmed: string;
  Hashes: Integer;
  IsHeading: Boolean;
begin
  Trimmed := TrimLeft(Line);
  Hashes := LeadingRun(Trimmed, '#');

  IsHeading := (Hashes >= 1) and (Hashes <= MaxHeadingLevel) and
    ((Length(Trimmed) = Hashes) or (Trimmed[Hashes + 1] = ' '));
  if IsHeading then
    Result := Hashes
  else
    Result := 0;
end;

class function TMarkdownFoldComputer.LeadingRun(const Text: string; const Ch: Char): Integer;
begin
  Result := 0;
  while (Result < Length(Text)) and (Text[Result + 1] = Ch) do
    Inc(Result);
end;

end.
