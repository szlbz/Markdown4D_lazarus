{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Parser.Incremental;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Extensions.Interfaces,
  Markdown4D.Parser.Interfaces,
  Markdown4D.Compat.Str,
  character;

type
  TMarkdownIncrementalParser = class
  public
    class function CreateParser(const Pipeline: IMarkdownPipeline): IMarkdownIncrementalParser;
  end;

implementation

uses
  SysUtils,
  Math,
  Generics.Collections,
  Markdown4D.Defines,
  Markdown4D.Ast.Interfaces,
  Markdown4D.Pipeline.Configuration,
  Markdown4D.Parser.Blocks,
  Markdown4D.Parser.References,
  Markdown4D.Renderer.Html;

type
  TFrozenSegment = class
  private
    FSource: string;
    FBaseHtml: string;
    FMissedLabels: TArray<string>;
    FDefinitions: TLinkReferenceMap;
    FPromotedHtml: string;
    FPromotedMissedLabels: TArray<string>;
    FPromotedVersion: Integer;

  public
    constructor Create(const Source, BaseHtml: string; const MissedLabels: TArray<string>; const Definitions: TLinkReferenceMap);
    destructor Destroy; override;
    procedure Promote(const Html: string; const Labels: TArray<string>; const Version: Integer);
    function HasPromotionFor(const Version: Integer): Boolean;
    property Source: string read FSource;
    property BaseHtml: string read FBaseHtml;
    property MissedLabels: TArray<string> read FMissedLabels;
    property Definitions: TLinkReferenceMap read FDefinitions;
    property PromotedHtml: string read FPromotedHtml;
    property PromotedMissedLabels: TArray<string> read FPromotedMissedLabels;
  end;

  TStreamingIncrementalParser = class(TInterfacedObject, IMarkdownIncrementalParser)
  private
    const
      MinimumFreezableBlockCount = 2;
      NoRenderedGeneration = -1;
      InitialFrozenVersion = 1;
      SegmentTargetLength = 4096;
      BoundarySearchAttemptLimit = 3;
      ReplaceRangeOutOfBoundsMessageFormat = 'ReplaceRange with start index %d and count %d is out of bounds for a source of length %d';
    var
      FPipeline: IMarkdownPipeline;
      FConfiguration: TMarkdownPipelineConfiguration;
      FFrozenReferences: TLinkReferenceMap;
      FSegments: TObjectList<TFrozenSegment>;
      FTail: string;
      FAnalyzedCompleteLength: Integer;
      FGeneration: Integer;
      FRenderedGeneration: Integer;
      FCachedHtml: string;
      FFrozenVersion: Integer;
    procedure FreezeCompletedBlocks;
    function CompletedLength: Integer;
    function TryFindFreezeBoundary(const CompleteText: string; out Boundary: Integer; out ChildOffsets: TArray<Integer>): Boolean;
    procedure FreezeUpTo(const Boundary: Integer; const ChildOffsets: TArray<Integer>);
    function InsertFrozenSegments(const InsertIndex: Integer; const Source: string; const ChildOffsets: TArray<Integer>): Integer;
    function CreateFrozenSegment(const Source: string): TFrozenSegment;
    function TotalSourceLength: Integer;
    procedure ValidateRange(const StartIndex, Count, TotalLength: Integer);
    procedure ApplyEdit(const StartIndex, Count: Integer; const Replacement: string);
    function SegmentStarts: TArray<Integer>;
    function SourcesBetween(const FirstIndex, LimitIndex: Integer): string;
    procedure SpliceBeforeRetained(const WindowFirst, RetainedIndex: Integer; const EditedWindow: string);
    function TryVerifyCleanBreak(const WindowText, RetainedSource: string; out ChildOffsets: TArray<Integer>): Boolean;
    procedure MergeIntoTail(const WindowFirst: Integer; const MergedText: string);
    procedure RebuildFrozenReferences(const SegmentLimit: Integer);
    procedure ReconcileDefinitions(const PreviousDefinitions: TLinkReferenceMap);
    procedure RebuildFromScratch;
    function ComposeFullSource: string;
    function SegmentHtml(const Segment: TFrozenSegment; const AvailableReferences: TLinkReferenceMap): string;
    procedure PromoteSegment(const Segment: TFrozenSegment);
    class function AnyLabelAvailable(const Labels: TArray<string>; const References: TLinkReferenceMap): Boolean;
    function ParseWithReferences(const Source: string; const References: TLinkReferenceMap): IMarkdownDocument;
    function RenderHtml(const Document: IMarkdownDocument): string;

  public
    constructor Create(const Pipeline: IMarkdownPipeline; const Configuration: TMarkdownPipelineConfiguration);
    destructor Destroy; override;
    procedure Append(const Chunk: string);
    procedure ReplaceRange(const StartIndex, Count: Integer; const Replacement: string);
    function ToHtml: string;
  end;

class function TMarkdownIncrementalParser.CreateParser(const Pipeline: IMarkdownPipeline): IMarkdownIncrementalParser;
var
  Provider: IMarkdownPipelineConfigurationProvider;
  HasConfiguration: type of (Supports(Pipeline, IMarkdownPipelineConfigurationProvider, Provider));
begin
  
  HasConfiguration := Supports(Pipeline, IMarkdownPipelineConfigurationProvider, Provider);
  if not HasConfiguration then
    raise EMarkdownError.Create('Incremental parsing requires a pipeline that provides its configuration');

  Result := TStreamingIncrementalParser.Create(Pipeline, Provider.Configuration);
end;

constructor TFrozenSegment.Create(const Source, BaseHtml: string; const MissedLabels: TArray<string>; const Definitions: TLinkReferenceMap);
begin
  inherited Create;

  FSource := Source;
  FBaseHtml := BaseHtml;
  FMissedLabels := MissedLabels;
  FDefinitions := Definitions;
end;

destructor TFrozenSegment.Destroy;
begin
  FDefinitions.Free;

  inherited Destroy;
end;

procedure TFrozenSegment.Promote(const Html: string; const Labels: TArray<string>; const Version: Integer);
begin
  FPromotedHtml := Html;
  FPromotedMissedLabels := Labels;
  FPromotedVersion := Version;
end;

function TFrozenSegment.HasPromotionFor(const Version: Integer): Boolean;
begin
  Result := (FPromotedVersion = Version);
end;

constructor TStreamingIncrementalParser.Create(const Pipeline: IMarkdownPipeline;
                                               const Configuration: TMarkdownPipelineConfiguration);
begin
  inherited Create;

  FPipeline := Pipeline;
  FConfiguration := Configuration;
  FFrozenReferences := TLinkReferenceMap.Create;
  FSegments := TObjectList<TFrozenSegment>.Create(True);
  FRenderedGeneration := NoRenderedGeneration;
  FFrozenVersion := InitialFrozenVersion;
end;

destructor TStreamingIncrementalParser.Destroy;
begin
  FSegments.Free;
  FFrozenReferences.Free;

  inherited Destroy;
end;

procedure TStreamingIncrementalParser.Append(const Chunk: string);
begin
  if Chunk = '' then
    Exit;

  FTail := FTail + Chunk;
  Inc(FGeneration);

  FreezeCompletedBlocks;
end;

procedure TStreamingIncrementalParser.FreezeCompletedBlocks;
var
  CompleteLength: Integer;
  HasNewCompleteLines: Boolean;
  Boundary: Integer;
  ChildOffsets: TArray<Integer>;
begin
  CompleteLength := CompletedLength;
  HasNewCompleteLines := (CompleteLength > FAnalyzedCompleteLength);
  if not HasNewCompleteLines then
    Exit;

  
  
  if TryFindFreezeBoundary(Copy(FTail, 1, CompleteLength), Boundary, ChildOffsets) then
    FreezeUpTo(Boundary, ChildOffsets);

  FAnalyzedCompleteLength := CompletedLength;
end;

function TStreamingIncrementalParser.CompletedLength: Integer;
var
  TailLength: Integer;
  Index: Integer;
  Current: Char;
  IsSettledCarriageReturn: Boolean;
begin
  TailLength := Length(FTail);

  for Index := TailLength downto 1 do
  begin
    Current := FTail[Index];

    if Current = LineFeed then
    begin
      Result := Index;
      Exit;
    end;

    IsSettledCarriageReturn := (Current = CarriageReturn) and (Index < TailLength);
    if IsSettledCarriageReturn then
    begin
      Result := Index;
      Exit;
    end;
  end;

  Result := 0;
end;

function TStreamingIncrementalParser.TryFindFreezeBoundary(const CompleteText: string; out Boundary: Integer; out ChildOffsets: TArray<Integer>): Boolean;
var
  Working: TLinkReferenceMap;
  Document: IMarkdownDocument;
  HasFreezableBlocks: Boolean;
  Index: Integer;
begin
  Boundary := 0;
  ChildOffsets := nil;

  Working := TLinkReferenceMap.Create;
  try
    FFrozenReferences.CopyTo(Working);

    Document := ParseWithReferences(CompleteText, Working);
    HasFreezableBlocks := (Document.ChildCount >= MinimumFreezableBlockCount);
    if not HasFreezableBlocks then
    begin
      Result := False;
      Exit;
    end;

    SetLength(ChildOffsets, Document.ChildCount - 1);
    for Index := 0 to Document.ChildCount - 2 do
    begin
      ChildOffsets[Index] := Document.Children[Index].Segment.StartOffset;
    end;

    Boundary := Document.Children[Document.ChildCount - 1].Segment.StartOffset;
    Result := (Boundary > 1);
  finally
    Working.Free;
  end;
end;

procedure TStreamingIncrementalParser.FreezeUpTo(const Boundary: Integer; const ChildOffsets: TArray<Integer>);
var
  CountBefore: Integer;
  FrozenSource: string;
  HasNewDefinitions: Boolean;
begin
  CountBefore := FFrozenReferences.Count;
  FrozenSource := Copy(FTail, 1, Boundary - 1);

  InsertFrozenSegments(FSegments.Count, FrozenSource, ChildOffsets);
  FTail := Copy(FTail, Boundary, MaxInt);

  HasNewDefinitions := (FFrozenReferences.Count <> CountBefore);
  if HasNewDefinitions then
    Inc(FFrozenVersion);
end;

function TStreamingIncrementalParser.InsertFrozenSegments(const InsertIndex: Integer; const Source: string; const ChildOffsets: TArray<Integer>): Integer;
var
  GroupStart: Integer;
  Offset: Integer;
  CompletesGroup: Boolean;
begin
  Result := 0;
  if Source = '' then
    Exit;

  GroupStart := 1;
  for Offset in ChildOffsets do
  begin
    CompletesGroup := (Offset > GroupStart) and ((Offset - GroupStart) >= SegmentTargetLength);
    if not CompletesGroup then
      Continue;

    FSegments.Insert(InsertIndex + Result, CreateFrozenSegment(Copy(Source, GroupStart, Offset - GroupStart)));
    Inc(Result);
    GroupStart := Offset;
  end;

  FSegments.Insert(InsertIndex + Result, CreateFrozenSegment(Copy(Source, GroupStart, Length(Source) - GroupStart + 1)));
  Inc(Result);
end;

function TStreamingIncrementalParser.CreateFrozenSegment(const Source: string): TFrozenSegment;
var
  Definitions: TLinkReferenceMap;
  BaseHtml: string;
  Document: IMarkdownDocument;
begin
  Definitions := TLinkReferenceMap.Create;
  try
    FFrozenReferences.ClearMissedLabels;
    FFrozenReferences.SetCaptureTarget(Definitions);

    
    try
      Document := ParseWithReferences(Source, FFrozenReferences);
      BaseHtml := RenderHtml(Document);
    finally
      FFrozenReferences.SetCaptureTarget(nil);
    end;

    Result := TFrozenSegment.Create(Source, BaseHtml, FFrozenReferences.MissedLabels, Definitions);
  except
    Definitions.Free;
    raise;
  end;
end;

procedure TStreamingIncrementalParser.ReplaceRange(const StartIndex, Count: Integer; const Replacement: string);
var
  TotalLength: Integer;
  IsPureAppend: Boolean;
  IsNoOp: Boolean;
  PreviousDefinitions: TLinkReferenceMap;
begin
  TotalLength := TotalSourceLength;
  ValidateRange(StartIndex, Count, TotalLength);

  IsPureAppend := (StartIndex = TotalLength + 1);
  if IsPureAppend then
  begin
    Append(Replacement);
    Exit;
  end;

  IsNoOp := (Count = 0) and (Replacement = '');
  if IsNoOp then
    Exit;

  Inc(FGeneration);

  PreviousDefinitions := TLinkReferenceMap.Create;
  try
    FFrozenReferences.CopyTo(PreviousDefinitions);

    ApplyEdit(StartIndex, Count, Replacement);
    ReconcileDefinitions(PreviousDefinitions);
  finally
    PreviousDefinitions.Free;
  end;
end;

function TStreamingIncrementalParser.TotalSourceLength: Integer;
var
  Segment: TFrozenSegment;
begin
  Result := Length(FTail);

  for Segment in FSegments do
  begin
    Inc(Result, Length(Segment.Source));
  end;
end;

procedure TStreamingIncrementalParser.ValidateRange(const StartIndex, Count, TotalLength: Integer);
var
  StartIsValid: Boolean;
  CountIsValid: Boolean;
begin
  StartIsValid := (StartIndex >= 1) and (StartIndex <= TotalLength + 1);
  CountIsValid := (Count >= 0) and (Int64(StartIndex) + Int64(Count) <= Int64(TotalLength) + 1);
  if not (StartIsValid and CountIsValid) then
    raise EMarkdownError.CreateFmt(ReplaceRangeOutOfBoundsMessageFormat, [StartIndex, Count, TotalLength]);
end;

procedure TStreamingIncrementalParser.ApplyEdit(const StartIndex, Count: Integer; const Replacement: string);
var
  Starts: TArray<Integer>;
  SegmentCount: type of (FSegments.Count);
  FirstAffected: type of (SegmentCount);
  Index: Integer;
  WindowFirst: Integer;
  EndPosition: Integer;
  RetainedIndex: type of (SegmentCount);
  IncludesTail: Boolean;
  WindowText: string;
  LocalStart: Integer;
  EditedWindow: string;
begin
  Starts := SegmentStarts;
  SegmentCount := FSegments.Count;

  FirstAffected := SegmentCount;
  for Index := 0 to SegmentCount - 1 do
  begin
    if StartIndex < Starts[Index + 1] then
    begin
      FirstAffected := Index;
      Break;
    end;
  end;

  WindowFirst := Max(FirstAffected - 1, 0);

  EndPosition := StartIndex + Count;
  RetainedIndex := SegmentCount;
  for Index := WindowFirst + 1 to SegmentCount - 1 do
  begin
    if Starts[Index] >= EndPosition then
    begin
      RetainedIndex := Index;
      Break;
    end;
  end;

  IncludesTail := (RetainedIndex >= SegmentCount);
  WindowText := SourcesBetween(WindowFirst, RetainedIndex);
  if IncludesTail then
    WindowText := WindowText + FTail;

  LocalStart := StartIndex - Starts[WindowFirst] + 1;
  EditedWindow := Copy(WindowText, 1, LocalStart - 1) + Replacement + Copy(WindowText, LocalStart + Count, MaxInt);

  if IncludesTail then
    MergeIntoTail(WindowFirst, EditedWindow)
  else
    SpliceBeforeRetained(WindowFirst, RetainedIndex, EditedWindow);
end;

function TStreamingIncrementalParser.SegmentStarts: TArray<Integer>;
var
  Position: Integer;
  Index: Integer;
begin
  SetLength(Result, FSegments.Count + 1);

  Position := 1;
  for Index := 0 to FSegments.Count - 1 do
  begin
    Result[Index] := Position;
    Inc(Position, Length(FSegments[Index].Source));
  end;

  Result[FSegments.Count] := Position;
end;

function TStreamingIncrementalParser.SourcesBetween(const FirstIndex, LimitIndex: Integer): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    for Index := FirstIndex to LimitIndex - 1 do
    begin
      Builder.Append(FSegments[Index].Source);
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TStreamingIncrementalParser.SpliceBeforeRetained(const WindowFirst, RetainedIndex: Integer; const EditedWindow: string);
var
  CurrentWindow: string;
  CurrentRetained: Integer;
  Attempts: Integer;
  ChildOffsets: TArray<Integer>;
  Verified: Boolean;
  InsertedCount: Integer;
  Index: Integer;
begin
  CurrentWindow := EditedWindow;
  CurrentRetained := RetainedIndex;
  Attempts := 0;
  
  Verified := False;

  while (not Verified) and (CurrentRetained < FSegments.Count) and (Attempts < BoundarySearchAttemptLimit) do
  begin
    Verified := TryVerifyCleanBreak(CurrentWindow, FSegments[CurrentRetained].Source, ChildOffsets);

    if not Verified then
    begin
      CurrentWindow := CurrentWindow + FSegments[CurrentRetained].Source;
      Inc(CurrentRetained);
      Inc(Attempts);
    end;
  end;

  if not Verified then
  begin
    MergeIntoTail(WindowFirst, CurrentWindow + SourcesBetween(CurrentRetained, FSegments.Count) + FTail);
    Exit;
  end;

  FSegments.DeleteRange(WindowFirst, CurrentRetained - WindowFirst);
  RebuildFrozenReferences(WindowFirst);

  InsertedCount := InsertFrozenSegments(WindowFirst, CurrentWindow, ChildOffsets);
  for Index := WindowFirst + InsertedCount to FSegments.Count - 1 do
  begin
    FSegments[Index].Definitions.CopyTo(FFrozenReferences);
  end;
end;

function TStreamingIncrementalParser.TryVerifyCleanBreak(const WindowText, RetainedSource: string; out ChildOffsets: TArray<Integer>): Boolean;
var
  Scratch: TLinkReferenceMap;
  Document: IMarkdownDocument;
  BoundaryOffset: Integer;
  Index: Integer;
  ChildStart: type of (Document.Children[Index].Segment.StartOffset);
  Preceding: Integer;
  PassedBoundary: Boolean;
begin
  ChildOffsets := nil;

  Scratch := TLinkReferenceMap.Create;
  try
    Document := ParseWithReferences(WindowText + RetainedSource, Scratch);
    BoundaryOffset := Length(WindowText) + 1;

    for Index := 0 to Document.ChildCount - 1 do
    begin
      ChildStart := Document.Children[Index].Segment.StartOffset;

      if ChildStart = BoundaryOffset then
      begin
        SetLength(ChildOffsets, Index);
        for Preceding := 0 to Index - 1 do
        begin
          ChildOffsets[Preceding] := Document.Children[Preceding].Segment.StartOffset;
        end;

        Result := True;
        Exit;
      end;

      PassedBoundary := (ChildStart > BoundaryOffset);
      if PassedBoundary then
        Break;
    end;

    Result := False;
  finally
    Scratch.Free;
  end;
end;

procedure TStreamingIncrementalParser.MergeIntoTail(const WindowFirst: Integer; const MergedText: string);
begin
  FSegments.DeleteRange(WindowFirst, FSegments.Count - WindowFirst);
  RebuildFrozenReferences(FSegments.Count);

  FTail := MergedText;
  FAnalyzedCompleteLength := 0;

  FreezeCompletedBlocks;
end;

procedure TStreamingIncrementalParser.RebuildFrozenReferences(const SegmentLimit: Integer);
var
  Index: Integer;
begin
  FFrozenReferences.Clear;

  for Index := 0 to SegmentLimit - 1 do
  begin
    FSegments[Index].Definitions.CopyTo(FFrozenReferences);
  end;
end;

procedure TStreamingIncrementalParser.ReconcileDefinitions(const PreviousDefinitions: TLinkReferenceMap);
var
  PreservesPreviousDefinitions: Boolean;
  HasNewDefinitions: Boolean;
begin
  PreservesPreviousDefinitions := FFrozenReferences.ContainsAllEntriesOf(PreviousDefinitions);
  if not PreservesPreviousDefinitions then
  begin
    RebuildFromScratch;
    Exit;
  end;

  HasNewDefinitions := (FFrozenReferences.Count <> PreviousDefinitions.Count);
  if HasNewDefinitions then
    Inc(FFrozenVersion);
end;

procedure TStreamingIncrementalParser.RebuildFromScratch;
var
  FullSource: string;
begin
  FullSource := ComposeFullSource;

  FSegments.Clear;
  FFrozenReferences.Clear;
  FTail := FullSource;
  FAnalyzedCompleteLength := 0;

  FreezeCompletedBlocks;
end;

function TStreamingIncrementalParser.ComposeFullSource: string;
var
  Builder: TStringBuilder;
  Segment: TFrozenSegment;
begin
  Builder := TStringBuilder.Create;
  try
    for Segment in FSegments do
    begin
      Builder.Append(Segment.Source);
    end;

    Builder.Append(FTail);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TStreamingIncrementalParser.ToHtml: string;
var
  IsCurrent: Boolean;
  Working: TLinkReferenceMap;
  Output: TStringBuilder;
  TailDocument: IMarkdownDocument;
  TailHtml: string;
  Segment: TFrozenSegment;
begin
  IsCurrent := (FRenderedGeneration = FGeneration);
  if IsCurrent then
  begin
    Result := FCachedHtml;
    Exit;
  end;

  Working := TLinkReferenceMap.Create;
  try
    Output := TStringBuilder.Create;
    try
      FFrozenReferences.CopyTo(Working);
      TailDocument := ParseWithReferences(FTail, Working);
      TailHtml := RenderHtml(TailDocument);

      for Segment in FSegments do
      begin
        Output.Append(SegmentHtml(Segment, Working));
      end;

      Output.Append(TailHtml);
      FCachedHtml := Output.ToString;
    finally
      Output.Free;
    end;
  finally
    Working.Free;
  end;

  FRenderedGeneration := FGeneration;
  Result := FCachedHtml;
end;

function TStreamingIncrementalParser.SegmentHtml(const Segment: TFrozenSegment;
                                                 const AvailableReferences: TLinkReferenceMap): string;
var
  EffectiveHtml: string;
  EffectiveMissedLabels: TArray<string>;
  NeedsFrozenPromotion: Boolean;
  HasTailResolvableMisses: Boolean;
  Document: IMarkdownDocument;
begin
  EffectiveHtml := Segment.BaseHtml;
  EffectiveMissedLabels := Segment.MissedLabels;

  NeedsFrozenPromotion := AnyLabelAvailable(Segment.MissedLabels, FFrozenReferences);
  if NeedsFrozenPromotion then
  begin
    if not Segment.HasPromotionFor(FFrozenVersion) then
      PromoteSegment(Segment);

    EffectiveHtml := Segment.PromotedHtml;
    EffectiveMissedLabels := Segment.PromotedMissedLabels;
  end;

  HasTailResolvableMisses := AnyLabelAvailable(EffectiveMissedLabels, AvailableReferences);
  if not HasTailResolvableMisses then
  begin
    Result := EffectiveHtml;
    Exit;
  end;

  Document := ParseWithReferences(Segment.Source, AvailableReferences);
  Result := RenderHtml(Document);
end;

procedure TStreamingIncrementalParser.PromoteSegment(const Segment: TFrozenSegment);
var
  Document: IMarkdownDocument;
begin
  FFrozenReferences.ClearMissedLabels;

  Document := ParseWithReferences(Segment.Source, FFrozenReferences);
  Segment.Promote(RenderHtml(Document), FFrozenReferences.MissedLabels, FFrozenVersion);
end;

class function TStreamingIncrementalParser.AnyLabelAvailable(const Labels: TArray<string>;
                                                             const References: TLinkReferenceMap): Boolean;
var
  CurrentLabel: string;
begin
  for CurrentLabel in Labels do
  begin
    if References.ContainsNormalizedLabel(CurrentLabel) then
    begin
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

function TStreamingIncrementalParser.ParseWithReferences(const Source: string;
                                                         const References: TLinkReferenceMap): IMarkdownDocument;
var
  Parser: TBlockParser;
begin
  Parser := TBlockParser.Create(FConfiguration);
  try
    Result := Parser.Parse(Source, References);
  finally
    Parser.Free;
  end;
end;

function TStreamingIncrementalParser.RenderHtml(const Document: IMarkdownDocument): string;
begin
  Result := TMarkdownHtmlRenderer.RenderDocument(Document, FConfiguration.RendererOptions,
    FConfiguration.RendererHooks);
end;

end.
