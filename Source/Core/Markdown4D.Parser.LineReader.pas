{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Parser.LineReader;

{$SCOPEDENUMS ON}

interface

type
  TSourceLine = record
    Text: string;
    StartOffset: Integer;
    EndOffset: Integer;
  end;

  TLineReader = class
  private
    FSource: string;
    FPosition: Integer;

  public
    constructor Create(const Source: string);
    function TryReadLine(out Line: TSourceLine): Boolean;
  end;

implementation

uses
  Markdown4D.Defines,
  Markdown4D.Compat.Str,
  character;

constructor TLineReader.Create(const Source: string);
begin
  inherited Create;

  FSource := Source;
  FPosition := 1;
end;

function TLineReader.TryReadLine(out Line: TSourceLine): Boolean;
var
  SourceLength: Integer;
  HasMore: Boolean;
  Index: Integer;
  HasCarriageReturn: Boolean;
  HasLineFeed: Boolean;
begin
  SourceLength := Length(FSource);
  HasMore := (FPosition <= SourceLength);
  if not HasMore then
  begin
    Result := False;
    Exit;
  end;

  Index := FPosition;

  while (Index <= SourceLength) and (FSource[Index] <> LineFeed) and (FSource[Index] <> CarriageReturn) do
  begin
    Inc(Index);
  end;

  Line.StartOffset := FPosition;
  Line.EndOffset := Index;
  Line.Text := Copy(FSource, FPosition, Index - FPosition);

  HasCarriageReturn := (Index <= SourceLength) and (FSource[Index] = CarriageReturn);
  if HasCarriageReturn then
    Inc(Index);

  HasLineFeed := (Index <= SourceLength) and (FSource[Index] = LineFeed);
  if HasLineFeed then
    Inc(Index);

  FPosition := Index;
  Result := True;
end;

end.
