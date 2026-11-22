{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Highlighter.TokenBuilder;

{$SCOPEDENUMS ON}

interface

uses
  Generics.Collections,
  Markdown4D.Highlighter.Interfaces,
  Markdown4D.Compat.Str,
  character;

type
  TSyntaxTokenBuilder = class
  private
    FTokens: TList<TSyntaxToken>;

  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Kind: TSyntaxTokenKind; const StartIndex, TokenLength: Integer);
    function ToLine(const NextState: Integer): TSyntaxLine;
  end;

implementation

constructor TSyntaxTokenBuilder.Create;
begin
  inherited Create;

  FTokens := TList<TSyntaxToken>.Create;
end;

destructor TSyntaxTokenBuilder.Destroy;
begin
  FTokens.Free;

  inherited Destroy;
end;

procedure TSyntaxTokenBuilder.Add(const Kind: TSyntaxTokenKind; const StartIndex, TokenLength: Integer);
var
  HasContent: Boolean;
  LastIndex: Integer;
  Last: TSyntaxToken;
  CanMerge: Boolean;
begin
  HasContent := (TokenLength > 0);
  if not HasContent then
    Exit;

  LastIndex := FTokens.Count - 1;
  if LastIndex >= 0 then
  begin
    Last := FTokens[LastIndex];
    CanMerge := (Kind = TSyntaxTokenKind.PlainText) and (Last.Kind = TSyntaxTokenKind.PlainText) and
      (Last.Start + Last.Length = StartIndex);
    if CanMerge then
    begin
      Last.Length := Last.Length + TokenLength;
      FTokens[LastIndex] := Last;
      Exit;
    end;
  end;

  FTokens.Add(TSyntaxToken.Create(Kind, StartIndex, TokenLength));
end;

function TSyntaxTokenBuilder.ToLine(const NextState: Integer): TSyntaxLine;
begin
  Result := TSyntaxLine.Create(FTokens.ToArray, NextState);
end;

end.
