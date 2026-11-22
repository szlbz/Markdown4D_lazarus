{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Parser.References;

{$SCOPEDENUMS ON}

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  Generics.Collections,
  Markdown4D.Parser.LinkSyntax;

type
  TLinkReference = record
    Destination: string;
    Title: string;
  end;

  TLinkReferenceMap = class
  private
    FEntries: TDictionary<string, TLinkReference>;
    FMissedLabels: TDictionary<string, Boolean>;
    FCaptureTarget: TLinkReferenceMap;

  public
    class function NormalizeLabel(const RawLabel: string): string;
    constructor Create;
    destructor Destroy; override;
    procedure AddIfAbsent(const RawLabel: string; const Reference: TLinkReference);
    function TryGet(const RawLabel: string; out Reference: TLinkReference): Boolean;
    procedure Clear;
    procedure CopyTo(const Target: TLinkReferenceMap);
    function ContainsNormalizedLabel(const NormalizedLabel: string): Boolean;
    function ContainsAllEntriesOf(const Other: TLinkReferenceMap): Boolean;
    function Count: Integer;
    procedure SetCaptureTarget(const Target: TLinkReferenceMap);
    function MissedLabels: TArray<string>;
    procedure ClearMissedLabels;
  end;

  TLinkReferenceParser = class
  private
    const
      Colon = ':';
    var
      FScanner: TLinkSyntaxScanner;
    function TryParse(out Consumed: Integer; out RawLabel: string; out Reference: TLinkReference): Boolean;

  public
    constructor Create;
    destructor Destroy; override;
    function TryConsumeReference(const Content: string; const Map: TLinkReferenceMap;
                                 out Consumed: Integer): Boolean;
  end;

implementation

uses
  Markdown4D.Text.Unescape;

constructor TLinkReferenceMap.Create;
begin
  inherited Create;

  FEntries := TDictionary<string, TLinkReference>.Create;
  FMissedLabels := TDictionary<string, Boolean>.Create;
end;

destructor TLinkReferenceMap.Destroy;
begin
  FMissedLabels.Free;
  FEntries.Free;

  inherited Destroy;
end;

procedure TLinkReferenceMap.AddIfAbsent(const RawLabel: string; const Reference: TLinkReference);
var
  HasCaptureTarget: Boolean;
  Key: string;
begin
  HasCaptureTarget := (FCaptureTarget <> nil);
  if HasCaptureTarget then
    FCaptureTarget.AddIfAbsent(RawLabel, Reference);

  Key := NormalizeLabel(RawLabel);
  if not FEntries.ContainsKey(Key) then
    FEntries.Add(Key, Reference);
end;

function TLinkReferenceMap.TryGet(const RawLabel: string; out Reference: TLinkReference): Boolean;
var
  Key: string;
begin
  Key := NormalizeLabel(RawLabel);
  Result := FEntries.TryGetValue(Key, Reference);

  if not Result then
    FMissedLabels.AddOrSetValue(Key, True);
end;

procedure TLinkReferenceMap.Clear;
begin
  FEntries.Clear;
  FMissedLabels.Clear;
end;

procedure TLinkReferenceMap.CopyTo(const Target: TLinkReferenceMap);
var
  Entry: TPair<string,TLinkReference>;
begin
  for Entry in FEntries do
  begin
    if not Target.FEntries.ContainsKey(Entry.Key) then
      Target.FEntries.Add(Entry.Key, Entry.Value);
  end;
end;

function TLinkReferenceMap.ContainsNormalizedLabel(const NormalizedLabel: string): Boolean;
begin
  Result := FEntries.ContainsKey(NormalizedLabel);
end;

function TLinkReferenceMap.ContainsAllEntriesOf(const Other: TLinkReferenceMap): Boolean;
var
  Entry: TPair<string,TLinkReference>;
  Existing: TLinkReference;
  SameReference: Boolean;
begin
  for Entry in Other.FEntries do
  begin
    
    if not FEntries.TryGetValue(Entry.Key, Existing) then
    begin
      Result := False;
      Exit;
    end;

    SameReference := (Existing.Destination = Entry.Value.Destination) and (Existing.Title = Entry.Value.Title);
    if not SameReference then
    begin
      Result := False;
      Exit;
    end;
  end;

  Result := True;
end;

function TLinkReferenceMap.Count: Integer;
begin
  Result := FEntries.Count;
end;

procedure TLinkReferenceMap.SetCaptureTarget(const Target: TLinkReferenceMap);
begin
  FCaptureTarget := Target;
end;

function TLinkReferenceMap.MissedLabels: TArray<string>;
begin
  Result := FMissedLabels.Keys.ToArray;
end;

procedure TLinkReferenceMap.ClearMissedLabels;
begin
  FMissedLabels.Clear;
end;

class function TLinkReferenceMap.NormalizeLabel(const RawLabel: string): string;
var
  Builder: TStringBuilder;
  PendingSpace: Boolean;
  HasContent: Boolean;
  Current: Char;
  IsWhitespace: type of (CharInSet(Current, [' ', #9, #10, #13]));
  SharpS: Char;
  Collapsed: string;
  Lowered: string;
  SharpSFolded: type of (Lowered.Replace(SharpS, 'ss', [rfReplaceAll]));
begin
  Builder := TStringBuilder.Create;
  try
    PendingSpace := False;
    HasContent := False;

    for Current in RawLabel do
    begin
      IsWhitespace := CharInSet(Current, [' ', #9, #10, #13]);

      if IsWhitespace then
      begin
        PendingSpace := HasContent;
        Continue;
      end;

      if PendingSpace then
      begin
        Builder.Append(' ');
        PendingSpace := False;
      end;

      Builder.Append(Current);
      HasContent := True;
    end;

    SharpS := #$00DF;
    Collapsed := Builder.ToString;
    Lowered := FoldCase(Collapsed);
    SharpSFolded := Lowered.Replace(SharpS, 'ss', [rfReplaceAll]);

    Result := SharpSFolded.ToUpper;
  finally
    Builder.Free;
  end;
end;

constructor TLinkReferenceParser.Create;
begin
  inherited Create;

  FScanner := TLinkSyntaxScanner.Create;
end;

destructor TLinkReferenceParser.Destroy;
begin
  FScanner.Free;

  inherited Destroy;
end;

function TLinkReferenceParser.TryConsumeReference(const Content: string; const Map: TLinkReferenceMap;
                                                  out Consumed: Integer): Boolean;
var
  RawLabel: string;
  Reference: TLinkReference;
begin
  FScanner.Reset(Content, 1);

  
  

  Result := TryParse(Consumed, RawLabel, Reference);

  if Result then
    Map.AddIfAbsent(RawLabel, Reference);
end;

function TLinkReferenceParser.TryParse(out Consumed: Integer; out RawLabel: string;
                                       out Reference: TLinkReference): Boolean;
var
  LabelLength: Integer;
  HasColon: Boolean;
  Destination: string;
  BeforeTitle: Integer;
  Title: string;
  HasTitle: Boolean;
  MovedPastDestination: Boolean;
  AtLineEnd: Boolean;
  MustRetryWithoutTitle: Boolean;
  NormalizedLabel: string;
  LabelIsEmpty: Boolean;
  UnescapedDestination: string;
begin
  Consumed := 0;
  Reference.Destination := '';
  Reference.Title := '';

  
  if not FScanner.TryParseLabel(RawLabel, LabelLength) then
  begin
    Result := False;
    Exit;
  end;

  HasColon := (FScanner.PeekChar = Colon);
  if not HasColon then
  begin
    Result := False;
    Exit;
  end;

  FScanner.Advance(1);
  FScanner.SkipSpacesWithOneNewline;

  
  if not FScanner.TryParseDestination(Destination) then
  begin
    Result := False;
    Exit;
  end;

  BeforeTitle := FScanner.Position;
  FScanner.SkipSpacesWithOneNewline;

  Title := '';
  HasTitle := False;

  MovedPastDestination := (FScanner.Position <> BeforeTitle);
  if MovedPastDestination then
    HasTitle := FScanner.TryParseTitle(Title);

  if not HasTitle then
    FScanner.MoveTo(BeforeTitle);

  AtLineEnd := FScanner.ConsumeSpacesToLineEnd;

  MustRetryWithoutTitle := (not AtLineEnd) and HasTitle;
  if MustRetryWithoutTitle then
  begin
    Title := '';
    FScanner.MoveTo(BeforeTitle);
    AtLineEnd := FScanner.ConsumeSpacesToLineEnd;
  end;

  if not AtLineEnd then
  begin
    Result := False;
    Exit;
  end;

  NormalizedLabel := TLinkReferenceMap.NormalizeLabel(RawLabel);
  LabelIsEmpty := (NormalizedLabel = '');
  if LabelIsEmpty then
  begin
    Result := False;
    Exit;
  end;

  UnescapedDestination := TMarkdownUnescape.Unescape(Destination);
  Reference.Destination := TMarkdownUnescape.NormalizeUri(UnescapedDestination);
  Reference.Title := TMarkdownUnescape.Unescape(Title);
  Consumed := FScanner.Position - 1;
  Result := True;
end;

end.
