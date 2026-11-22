{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Extensions.Chart;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Ast.Interfaces,
  Markdown4D.Extensions.Interfaces,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Compat.Str,
  character;

type
  TChartKind = (Bar, Line, Pie, Doughnut, Radar, Scatter);

  TChartLegendPosition = (Top, Left, Bottom, Right);

  IChartDataset = interface
    ['{7C1E9B04-4A62-4D38-9F51-08B3C6E52D71}']
    function GetLabel: string;
    function GetValueCount: Integer;
    function GetValue(const Index: Integer): Double;
    function GetBackgroundColorCount: Integer;
    function GetBackgroundColor(const Index: Integer): TLayoutColor;
    function GetBorderColorCount: Integer;
    function GetBorderColor(const Index: Integer): TLayoutColor;
    function GetFill: Boolean;
    function GetPointCount: Integer;
    function GetPointX(const Index: Integer): Double;
    function GetPointY(const Index: Integer): Double;
    property Values[const Index: Integer]: Double read GetValue;
    property BackgroundColors[const Index: Integer]: TLayoutColor read GetBackgroundColor;
    property BorderColors[const Index: Integer]: TLayoutColor read GetBorderColor;
    property PointsX[const Index: Integer]: Double read GetPointX;
    property PointsY[const Index: Integer]: Double read GetPointY;
    property Caption: string read GetLabel;
    property ValueCount: Integer read GetValueCount;
    property BackgroundColorCount: Integer read GetBackgroundColorCount;
    property BorderColorCount: Integer read GetBorderColorCount;
    property Fill: Boolean read GetFill;
    property PointCount: Integer read GetPointCount;
  end;

  IChartModel = interface
    ['{2D8F5A31-6E47-4C09-B152-93A0C4E7B6D8}']
    function GetChartKind: TChartKind;
    function GetTitle: string;
    function GetTitleVisible: Boolean;
    function GetLegendVisible: Boolean;
    function GetLegendPosition: TChartLegendPosition;
    function GetStacked: Boolean;
    function GetHorizontal: Boolean;
    function GetHasScaleMin: Boolean;
    function GetScaleMin: Double;
    function GetHasScaleMax: Boolean;
    function GetScaleMax: Double;
    function GetLabelCount: Integer;
    function GetLabel(const Index: Integer): string;
    function GetDatasetCount: Integer;
    function GetDataset(const Index: Integer): IChartDataset;
    property ChartKind: TChartKind read GetChartKind;
    property Title: string read GetTitle;
    property TitleVisible: Boolean read GetTitleVisible;
    property LegendVisible: Boolean read GetLegendVisible;
    property LegendPosition: TChartLegendPosition read GetLegendPosition;
    property Stacked: Boolean read GetStacked;
    property Horizontal: Boolean read GetHorizontal;
    property HasScaleMin: Boolean read GetHasScaleMin;
    property ScaleMin: Double read GetScaleMin;
    property HasScaleMax: Boolean read GetHasScaleMax;
    property ScaleMax: Double read GetScaleMax;
    property Labels[const Index: Integer]: string read GetLabel;
    property LabelCount: Integer read GetLabelCount;
    property Datasets[const Index: Integer]: IChartDataset read GetDataset;
    property DatasetCount: Integer read GetDatasetCount;
  end;

  TChartExtension = class(TInterfacedObject, IMarkdownExtension)
  public
    const
      ExtensionName = 'markdown4d.chart';
      ChartTypeKey = 'type';
      ChartTypeValue = 'chart';
      ChartDataKey = 'data';
      ChartModelExtensionKey = 'markdown4d.chart.model';
      ChartProcessorPriority = TMarkdownPriorities.ExtensionProcessor;
    procedure Setup(const Pipeline: IMarkdownPipelineBuilder);
    class function IsChartCodeBlock(const Node: IMarkdownNode): Boolean;
    class function TryParse(const Code: IMarkdownCodeBlock; out Model: IChartModel): Boolean;
    class function TryGetModel(const Node: IMarkdownNode; out Model: IChartModel): Boolean;
    class function CreateDocumentProcessor: IMarkdownDocumentProcessor;
    class procedure Process(const Document: IMarkdownDocument);
  end;

implementation

uses
  SysUtils,
  Math,
  Generics.Collections,
  Markdown4D.Compat.Json;

type
  TChartDataset = class(TInterfacedObject, IChartDataset)
  private
    FLabel: string;
    FValues: TArray<Double>;
    FBackgroundColors: TArray<TLayoutColor>;
    FBorderColors: TArray<TLayoutColor>;
    FFill: Boolean;
    FPointsX: TArray<Double>;
    FPointsY: TArray<Double>;
    function GetLabel: string;
    function GetValueCount: Integer;
    function GetValue(const Index: Integer): Double;
    function GetBackgroundColorCount: Integer;
    function GetBackgroundColor(const Index: Integer): TLayoutColor;
    function GetBorderColorCount: Integer;
    function GetBorderColor(const Index: Integer): TLayoutColor;
    function GetFill: Boolean;
    function GetPointCount: Integer;
    function GetPointX(const Index: Integer): Double;
    function GetPointY(const Index: Integer): Double;

  public
    constructor Create(const Caption: string; const Values: TArray<Double>;
      const BackgroundColors, BorderColors: TArray<TLayoutColor>; const Fill: Boolean;
      const PointsX, PointsY: TArray<Double>);
  end;

  TChartModel = class(TInterfacedObject, IChartModel)
  private
    FChartKind: TChartKind;
    FTitle: string;
    FTitleVisible: Boolean;
    FLegendVisible: Boolean;
    FLegendPosition: TChartLegendPosition;
    FStacked: Boolean;
    FHorizontal: Boolean;
    FHasScaleMin: Boolean;
    FScaleMin: Double;
    FHasScaleMax: Boolean;
    FScaleMax: Double;
    FLabels: TArray<string>;
    FDatasets: TArray<IChartDataset>;
    function GetChartKind: TChartKind;
    function GetTitle: string;
    function GetTitleVisible: Boolean;
    function GetLegendVisible: Boolean;
    function GetLegendPosition: TChartLegendPosition;
    function GetStacked: Boolean;
    function GetHorizontal: Boolean;
    function GetHasScaleMin: Boolean;
    function GetScaleMin: Double;
    function GetHasScaleMax: Boolean;
    function GetScaleMax: Double;
    function GetLabelCount: Integer;
    function GetLabel(const Index: Integer): string;
    function GetDatasetCount: Integer;
    function GetDataset(const Index: Integer): IChartDataset;
  end;

  TChartDocumentProcessor = class(TInterfacedObject, IMarkdownDocumentProcessor)
  public
    procedure Process(const Document: IMarkdownDocument);
  end;

  TChartParser = class
  private
    const
      LabelKey = 'label';
      BackgroundColorKey = 'backgroundColor';
      BorderColorKey = 'borderColor';
      DatasetsKey = 'datasets';
      LabelsKey = 'labels';
      OptionsKey = 'options';
      PluginsKey = 'plugins';
      TitleKey = 'title';
      TextKey = 'text';
      DisplayKey = 'display';
      LegendKey = 'legend';
      PositionKey = 'position';
      ScalesKey = 'scales';
      YScaleKey = 'y';
      XScaleKey = 'x';
      MinKey = 'min';
      MaxKey = 'max';
      StackedKey = 'stacked';
      FillKey = 'fill';
      IndexAxisKey = 'indexAxis';
    class function TryParseHexColor(const Text: string; out Color: TLayoutColor): Boolean;
    class function TryParseFunctionalColor(const Text: string; out Color: TLayoutColor): Boolean;
    class procedure ReadTitleOptions(const Plugins: TJSONObject; const Model: TChartModel);
    class procedure ReadLegendOptions(const Plugins: TJSONObject; const Model: TChartModel);
    class procedure ReadScaleOptions(const Options: TJSONObject; const Model: TChartModel);
  public
    class function TryChartKind(const Value: string; out Kind: TChartKind): Boolean;
    class function TryParseColor(const Value: string; out Color: TLayoutColor): Boolean;
    class function ReadColors(const Value: TJSONValue): TArray<TLayoutColor>;
    class function ReadValues(const Value: TJSONArray): TArray<Double>;
    class procedure ReadData(const Value: TJSONArray; out Values, PointsX, PointsY: TArray<Double>);
    class function ReadDataset(const Value: TJSONObject): IChartDataset;
    class procedure ReadOptions(const Options: TJSONObject; const Model: TChartModel);
    class procedure BuildLabels(const Data: TJSONObject; const Model: TChartModel);
    class procedure BuildDatasets(const DatasetsArray: TJSONArray; const Model: TChartModel);
    class function TryBuildModel(const Literal: string; out Model: IChartModel): Boolean;
  end;

constructor TChartDataset.Create(const Caption: string; const Values: TArray<Double>;
  const BackgroundColors, BorderColors: TArray<TLayoutColor>; const Fill: Boolean;
  const PointsX, PointsY: TArray<Double>);
begin
  inherited Create;

  FLabel := Caption;
  FValues := Values;
  FBackgroundColors := BackgroundColors;
  FBorderColors := BorderColors;
  FFill := Fill;
  FPointsX := PointsX;
  FPointsY := PointsY;
end;

function TChartDataset.GetLabel: string;
begin
  Result := FLabel;
end;

function TChartDataset.GetValueCount: Integer;
begin
  Result := Length(FValues);
end;

function TChartDataset.GetValue(const Index: Integer): Double;
begin
  Result := FValues[Index];
end;

function TChartDataset.GetBackgroundColorCount: Integer;
begin
  Result := Length(FBackgroundColors);
end;

function TChartDataset.GetBackgroundColor(const Index: Integer): TLayoutColor;
begin
  Result := FBackgroundColors[Index];
end;

function TChartDataset.GetBorderColorCount: Integer;
begin
  Result := Length(FBorderColors);
end;

function TChartDataset.GetBorderColor(const Index: Integer): TLayoutColor;
begin
  Result := FBorderColors[Index];
end;

function TChartDataset.GetFill: Boolean;
begin
  Result := FFill;
end;

function TChartDataset.GetPointCount: Integer;
begin
  Result := Length(FPointsX);
end;

function TChartDataset.GetPointX(const Index: Integer): Double;
begin
  Result := FPointsX[Index];
end;

function TChartDataset.GetPointY(const Index: Integer): Double;
begin
  Result := FPointsY[Index];
end;

function TChartModel.GetChartKind: TChartKind;
begin
  Result := FChartKind;
end;

function TChartModel.GetTitle: string;
begin
  Result := FTitle;
end;

function TChartModel.GetTitleVisible: Boolean;
begin
  Result := FTitleVisible;
end;

function TChartModel.GetLegendVisible: Boolean;
begin
  Result := FLegendVisible;
end;

function TChartModel.GetLegendPosition: TChartLegendPosition;
begin
  Result := FLegendPosition;
end;

function TChartModel.GetStacked: Boolean;
begin
  Result := FStacked;
end;

function TChartModel.GetHorizontal: Boolean;
begin
  Result := FHorizontal;
end;

function TChartModel.GetHasScaleMin: Boolean;
begin
  Result := FHasScaleMin;
end;

function TChartModel.GetScaleMin: Double;
begin
  Result := FScaleMin;
end;

function TChartModel.GetHasScaleMax: Boolean;
begin
  Result := FHasScaleMax;
end;

function TChartModel.GetScaleMax: Double;
begin
  Result := FScaleMax;
end;

function TChartModel.GetLabelCount: Integer;
begin
  Result := Length(FLabels);
end;

function TChartModel.GetLabel(const Index: Integer): string;
begin
  Result := FLabels[Index];
end;

function TChartModel.GetDatasetCount: Integer;
begin
  Result := Length(FDatasets);
end;

function TChartModel.GetDataset(const Index: Integer): IChartDataset;
begin
  Result := FDatasets[Index];
end;

class function TChartParser.TryParseHexColor(const Text: string; out Color: TLayoutColor): Boolean;
var
  Digits: string;
  Ch: Char;
  Red: Integer;
  Green: Integer;
  Blue: Integer;
  Alpha: Integer;
begin
  Color := 0;

  Digits := Text.Substring(1);

  for Ch in Digits do
  begin
    if not CharInSet(Ch, ['0'..'9', 'a'..'f', 'A'..'F']) then
    begin
      Result := False;
      Exit;
    end;
  end;

  
  
  
  Alpha := 255;

  case Length(Digits) of
    3:
      begin
        Red := StrToInt('$' + Digits.Chars[0] + Digits.Chars[0]);
        Green := StrToInt('$' + Digits.Chars[1] + Digits.Chars[1]);
        Blue := StrToInt('$' + Digits.Chars[2] + Digits.Chars[2]);
      end;
    4:
      begin
        Red := StrToInt('$' + Digits.Chars[0] + Digits.Chars[0]);
        Green := StrToInt('$' + Digits.Chars[1] + Digits.Chars[1]);
        Blue := StrToInt('$' + Digits.Chars[2] + Digits.Chars[2]);
        Alpha := StrToInt('$' + Digits.Chars[3] + Digits.Chars[3]);
      end;
    6:
      begin
        Red := StrToInt('$' + Digits.Substring(0, 2));
        Green := StrToInt('$' + Digits.Substring(2, 2));
        Blue := StrToInt('$' + Digits.Substring(4, 2));
      end;
    8:
      begin
        Red := StrToInt('$' + Digits.Substring(0, 2));
        Green := StrToInt('$' + Digits.Substring(2, 2));
        Blue := StrToInt('$' + Digits.Substring(4, 2));
        Alpha := StrToInt('$' + Digits.Substring(6, 2));
      end;
  else
  begin
    Result := False;
    Exit;
  end;
  end;

  Color := TLayoutColor((Cardinal(Alpha) shl 24) or (Cardinal(Red) shl 16) or (Cardinal(Green) shl 8) or
    Cardinal(Blue));
  Result := True;
end;

class function TChartParser.TryParseFunctionalColor(const Text: string; out Color: TLayoutColor): Boolean;
var
  IsFunctional: Boolean;
  Open: type of (Text.IndexOf('('));
  Close: type of (Text.IndexOf(')'));
  Inner: string;
  Parts: TArray<string>;
  Channels: array[0..2] of Integer;
  Index: Integer;
  Channel: Integer;
  AlphaValue: Integer;
  Opacity: Double;
  FormatSettings: type of (TFormatSettings.Invariant);
begin
  Color := 0;

  IsFunctional := Text.StartsWith('rgb(') or Text.StartsWith('rgba(');
  if not IsFunctional then
  begin
    Result := False;
    Exit;
  end;

  Open := Text.IndexOf('(');
  Close := Text.IndexOf(')');
  if (Open < 0) or (Close <= Open) then
  begin
    Result := False;
    Exit;
  end;

  Inner := Text.Substring(Open + 1, Close - Open - 1);
  Parts := Inner.Split([',']);
  if (Length(Parts) < 3) or (Length(Parts) > 4) then
  begin
    Result := False;
    Exit;
  end;

  
  for Index := 0 to 2 do
  begin
    
    if not TryStrToInt(Trim(Parts[Index]), Channel) then
    begin
      Result := False;
      Exit;
    end;
    Channels[Index] := EnsureRange(Channel, 0, 255);
  end;

  AlphaValue := 255;
  if Length(Parts) = 4 then
  begin
    
    FormatSettings := TFormatSettings.Invariant;
    if not TryStrToFloat(Trim(Parts[3]), Opacity, FormatSettings) then
    begin
      Result := False;
      Exit;
    end;
    AlphaValue := Round(EnsureRange(Opacity, 0, 1) * 255);
  end;

  Color := TLayoutColor((Cardinal(AlphaValue) shl 24) or (Cardinal(Channels[0]) shl 16) or
    (Cardinal(Channels[1]) shl 8) or Cardinal(Channels[2]));
  Result := True;
end;

class procedure TChartParser.ReadTitleOptions(const Plugins: TJSONObject; const Model: TChartModel);
var
  Title: TJSONValue;
  DisplayValue: TJSONValue;
  TextValue: TJSONValue;
begin
  Title := Plugins.GetValue(TitleKey);
  if not (Title is TJSONObject) then
    Exit;

  DisplayValue := TJSONObject(Title).GetValue(DisplayKey);
  if DisplayValue is TJSONBool then
    Model.FTitleVisible := TJSONBool(DisplayValue).AsBoolean;

  TextValue := TJSONObject(Title).GetValue(TextKey);
  if TextValue is TJSONString then
    Model.FTitle := TJSONString(TextValue).Value;
end;

class procedure TChartParser.ReadLegendOptions(const Plugins: TJSONObject; const Model: TChartModel);
var
  Legend: TJSONValue;
  DisplayValue: TJSONValue;
  PositionValue: TJSONValue;
  Position: string;
begin
  Legend := Plugins.GetValue(LegendKey);
  if not (Legend is TJSONObject) then
    Exit;

  DisplayValue := TJSONObject(Legend).GetValue(DisplayKey);
  if DisplayValue is TJSONBool then
    Model.FLegendVisible := TJSONBool(DisplayValue).AsBoolean;

  PositionValue := TJSONObject(Legend).GetValue(PositionKey);
  if PositionValue is TJSONString then
  begin
    Position := LowerCase(Trim(TJSONString(PositionValue).Value));
    if Position = 'left' then
      Model.FLegendPosition := TChartLegendPosition.Left
    else if Position = 'right' then
      Model.FLegendPosition := TChartLegendPosition.Right
    else if Position = 'bottom' then
      Model.FLegendPosition := TChartLegendPosition.Bottom
    else if Position = 'top' then
      Model.FLegendPosition := TChartLegendPosition.Top;
  end;
end;

class procedure TChartParser.ReadScaleOptions(const Options: TJSONObject; const Model: TChartModel);
var
  Scales: TJSONValue;
  YScale: TJSONValue;
  MinValue: TJSONValue;
  MaxValue: TJSONValue;
  StackedValue: TJSONValue;
  XScale: TJSONValue;
begin
  Scales := Options.GetValue(ScalesKey);
  if not (Scales is TJSONObject) then
    Exit;

  YScale := TJSONObject(Scales).GetValue(YScaleKey);
  if YScale is TJSONObject then
  begin
    MinValue := TJSONObject(YScale).GetValue(MinKey);
    if MinValue is TJSONNumber then
    begin
      Model.FHasScaleMin := True;
      Model.FScaleMin := TJSONNumber(MinValue).AsDouble;
    end;

    MaxValue := TJSONObject(YScale).GetValue(MaxKey);
    if MaxValue is TJSONNumber then
    begin
      Model.FHasScaleMax := True;
      Model.FScaleMax := TJSONNumber(MaxValue).AsDouble;
    end;

    StackedValue := TJSONObject(YScale).GetValue(StackedKey);
    if (StackedValue is TJSONBool) and TJSONBool(StackedValue).AsBoolean then
      Model.FStacked := True;
  end;

  XScale := TJSONObject(Scales).GetValue(XScaleKey);
  if XScale is TJSONObject then
  begin
    StackedValue := TJSONObject(XScale).GetValue(StackedKey);
    if (StackedValue is TJSONBool) and TJSONBool(StackedValue).AsBoolean then
      Model.FStacked := True;
  end;
end;

class function TChartParser.TryChartKind(const Value: string; out Kind: TChartKind): Boolean;
var
  Normalized: string;
begin
  Normalized := LowerCase(Trim(Value));

  if Normalized = 'bar' then
    Kind := TChartKind.Bar
  else if Normalized = 'line' then
    Kind := TChartKind.Line
  else if Normalized = 'pie' then
    Kind := TChartKind.Pie
  else if Normalized = 'doughnut' then
    Kind := TChartKind.Doughnut
  else if Normalized = 'radar' then
    Kind := TChartKind.Radar
  else if Normalized = 'scatter' then
    Kind := TChartKind.Scatter
  else
  begin
    Result := False;
    Exit;
  end;

  Result := True;
end;

class function TChartParser.TryParseColor(const Value: string; out Color: TLayoutColor): Boolean;
var
  Text: string;
begin
  Color := 0;
  Text := Trim(Value);
  if Text = '' then
  begin
    Result := False;
    Exit;
  end;

  if Text.StartsWith('#') then
  begin
    Result := TryParseHexColor(Text, Color);
    Exit;
  end;

  Result := TryParseFunctionalColor(Text, Color);
end;

class function TChartParser.ReadColors(const Value: TJSONValue): TArray<TLayoutColor>;
var
  Color: TLayoutColor;
  Items: type of (TJSONArray(Value));
  Colors: TList<TLayoutColor>;
  Index: Integer;
  Entry: TJSONValue;
begin
  Result := nil;

  if Value is TJSONString then
  begin
    
    if TryParseColor(TJSONString(Value).Value, Color) then
      Result := [Color];
    Exit;
  end;

  if Value is TJSONArray then
  begin
    Items := TJSONArray(Value);
    Colors := TList<TLayoutColor>.Create;
    try
      for Index := 0 to Items.Count - 1 do
      begin
        
        Entry := Items.Items[Index];
        if (Entry is TJSONString) and TryParseColor(TJSONString(Entry).Value, Color) then
          Colors.Add(Color)
        else
          Colors.Add(0);
      end;
      Result := Colors.ToArray;
    finally
      Colors.Free;
    end;
  end;
end;

class function TChartParser.ReadValues(const Value: TJSONArray): TArray<Double>;
var
  Index: Integer;
  Entry: TJSONValue;
begin
  SetLength(Result, Value.Count);

  for Index := 0 to Value.Count - 1 do
  begin
    Entry := Value.Items[Index];
    if Entry is TJSONNumber then
      Result[Index] := TJSONNumber(Entry).AsDouble
    else
      Result[Index] := 0;
  end;
end;

class procedure TChartParser.ReadData(const Value: TJSONArray; out Values, PointsX, PointsY: TArray<Double>);
var
  Numbers: TList<Double>;
  XCoords: TList<Double>;
  YCoords: TList<Double>;
  Index: Integer;
  Entry: TJSONValue;
  X: Double;
  Y: Double;
  XValue: TJSONValue;
  YValue: TJSONValue;
begin
  Numbers := TList<Double>.Create;
  XCoords := TList<Double>.Create;
  YCoords := TList<Double>.Create;
  try
    for Index := 0 to Value.Count - 1 do
    begin
      Entry := Value.Items[Index];
      if Entry is TJSONNumber then
        Numbers.Add(TJSONNumber(Entry).AsDouble)
      else if Entry is TJSONObject then
      begin
        X := 0.0;
        Y := 0.0;
        XValue := TJSONObject(Entry).GetValue(XScaleKey);
        YValue := TJSONObject(Entry).GetValue(YScaleKey);
        if XValue is TJSONNumber then
          X := TJSONNumber(XValue).AsDouble;
        if YValue is TJSONNumber then
          Y := TJSONNumber(YValue).AsDouble;
        XCoords.Add(X);
        YCoords.Add(Y);
      end
      else
        Numbers.Add(0);
    end;

    Values := Numbers.ToArray;
    PointsX := XCoords.ToArray;
    PointsY := YCoords.ToArray;
  finally
    Numbers.Free;
    XCoords.Free;
    YCoords.Free;
  end;
end;

class function TChartParser.ReadDataset(const Value: TJSONObject): IChartDataset;
var
  Caption: string;
  LabelValue: TJSONValue;
  Values: TArray<Double>;
  PointsX: TArray<Double>;
  PointsY: TArray<Double>;
  DataValue: TJSONValue;
  BackgroundColors: TArray<TLayoutColor>;
  BackgroundValue: TJSONValue;
  BorderColors: TArray<TLayoutColor>;
  BorderValue: TJSONValue;
  Fill: Boolean;
  FillValue: TJSONValue;
begin
  Caption := '';
  LabelValue := Value.GetValue(LabelKey);
  if LabelValue is TJSONString then
    Caption := TJSONString(LabelValue).Value;

  Values := nil;
  PointsX := nil;
  PointsY := nil;
  DataValue := Value.GetValue(TChartExtension.ChartDataKey);
  if DataValue is TJSONArray then
    ReadData(TJSONArray(DataValue), Values, PointsX, PointsY);

  BackgroundColors := nil;
  BackgroundValue := Value.GetValue(BackgroundColorKey);
  if BackgroundValue <> nil then
    BackgroundColors := ReadColors(BackgroundValue);

  BorderColors := nil;
  BorderValue := Value.GetValue(BorderColorKey);
  if BorderValue <> nil then
    BorderColors := ReadColors(BorderValue);

  Fill := False;
  FillValue := Value.GetValue(FillKey);
  if FillValue is TJSONBool then
    Fill := TJSONBool(FillValue).AsBoolean;

  Result := TChartDataset.Create(Caption, Values, BackgroundColors, BorderColors, Fill, PointsX, PointsY);
end;

class procedure TChartParser.ReadOptions(const Options: TJSONObject; const Model: TChartModel);
var
  Plugins: TJSONValue;
  IndexAxisValue: TJSONValue;
begin
  Plugins := Options.GetValue(PluginsKey);
  if Plugins is TJSONObject then
  begin
    ReadTitleOptions(TJSONObject(Plugins), Model);
    ReadLegendOptions(TJSONObject(Plugins), Model);
  end;

  IndexAxisValue := Options.GetValue(IndexAxisKey);
  if (IndexAxisValue is TJSONString) and (LowerCase(Trim(TJSONString(IndexAxisValue).Value)) = YScaleKey) then
    Model.FHorizontal := True;

  ReadScaleOptions(Options, Model);
end;

class procedure TChartParser.BuildLabels(const Data: TJSONObject; const Model: TChartModel);
var
  LabelsValue: TJSONValue;
  LabelsArray: type of (TJSONArray(LabelsValue));
  Index: Integer;
  Entry: TJSONValue;
begin
  LabelsValue := Data.GetValue(LabelsKey);
  if not (LabelsValue is TJSONArray) then
    Exit;

  LabelsArray := TJSONArray(LabelsValue);
  SetLength(Model.FLabels, LabelsArray.Count);
  for Index := 0 to LabelsArray.Count - 1 do
  begin
    Entry := LabelsArray.Items[Index];
    if Entry is TJSONString then
      Model.FLabels[Index] := TJSONString(Entry).Value
    else
      Model.FLabels[Index] := Entry.Value;
  end;
end;

class procedure TChartParser.BuildDatasets(const DatasetsArray: TJSONArray; const Model: TChartModel);
var
  Index: Integer;
  Entry: TJSONValue;
begin
  SetLength(Model.FDatasets, DatasetsArray.Count);
  for Index := 0 to DatasetsArray.Count - 1 do
  begin
    Entry := DatasetsArray.Items[Index];
    if Entry is TJSONObject then
      Model.FDatasets[Index] := ReadDataset(TJSONObject(Entry))
    else
      Model.FDatasets[Index] := TChartDataset.Create('', nil, nil, nil, False, nil, nil);
  end;
end;

class function TChartParser.TryBuildModel(const Literal: string; out Model: IChartModel): Boolean;
var
  Root: TJSONValue;
  Wrapper: type of (TJSONObject(Root));
  WrapperType: TJSONValue;
  ConfigValue: TJSONValue;
  Config: type of (TJSONObject(ConfigValue));
  KindValue: TJSONValue;
  Kind: TChartKind;
  DataValue: TJSONValue;
  Data: type of (TJSONObject(DataValue));
  DatasetsValue: TJSONValue;
  DatasetsArray: type of (TJSONArray(DatasetsValue));
  Instance: TChartModel;
  OptionsValue: TJSONValue;
begin
  Model := nil;

  Root := TJSONObject.ParseJSONValue(Literal);

  if not (Root is TJSONObject) then
  begin
    Root.Free;
    Result := False;
    Exit;
  end;

  try
    Wrapper := TJSONObject(Root);

    WrapperType := Wrapper.GetValue(TChartExtension.ChartTypeKey);
    if not (WrapperType is TJSONString) or (TJSONString(WrapperType).Value <> TChartExtension.ChartTypeValue) then
    begin
      Result := False;
      Exit;
    end;

    ConfigValue := Wrapper.GetValue(TChartExtension.ChartDataKey);
    if not (ConfigValue is TJSONObject) then
    begin
      Result := False;
      Exit;
    end;
    Config := TJSONObject(ConfigValue);

    KindValue := Config.GetValue(TChartExtension.ChartTypeKey);
    if not (KindValue is TJSONString) then
    begin
      Result := False;
      Exit;
    end;

    
    if not TryChartKind(TJSONString(KindValue).Value, Kind) then
    begin
      Result := False;
      Exit;
    end;

    DataValue := Config.GetValue(TChartExtension.ChartDataKey);
    if not (DataValue is TJSONObject) then
    begin
      Result := False;
      Exit;
    end;
    Data := TJSONObject(DataValue);

    DatasetsValue := Data.GetValue(DatasetsKey);
    if not (DatasetsValue is TJSONArray) then
    begin
      Result := False;
      Exit;
    end;
    DatasetsArray := TJSONArray(DatasetsValue);
    if DatasetsArray.Count = 0 then
    begin
      Result := False;
      Exit;
    end;

    Instance := TChartModel.Create;
    Model := Instance;

    Instance.FChartKind := Kind;
    Instance.FLegendVisible := True;
    Instance.FLegendPosition := TChartLegendPosition.Top;

    BuildLabels(Data, Instance);
    BuildDatasets(DatasetsArray, Instance);

    OptionsValue := Config.GetValue(OptionsKey);
    if OptionsValue is TJSONObject then
      ReadOptions(TJSONObject(OptionsValue), Instance);

    Result := True;
  finally
    Root.Free;
  end;
end;

procedure TChartDocumentProcessor.Process(const Document: IMarkdownDocument);
begin
  TChartExtension.Process(Document);
end;

procedure TChartExtension.Setup(const Pipeline: IMarkdownPipelineBuilder);
begin
  Pipeline.RegisterDocumentProcessor(CreateDocumentProcessor, ChartProcessorPriority);
end;

class function TChartExtension.CreateDocumentProcessor: IMarkdownDocumentProcessor;
begin
  Result := TChartDocumentProcessor.Create;
end;

class function TChartExtension.IsChartCodeBlock(const Node: IMarkdownNode): Boolean;
var
  CachedModel: IChartModel;
  Code: IMarkdownCodeBlock;
  Model: IChartModel;
begin
  
  if TryGetModel(Node, CachedModel) then
  begin
    Result := True;
    Exit;
  end;

  
  if not Supports(Node, IMarkdownCodeBlock, Code) or not Code.IsFenced then
  begin
    Result := False;
    Exit;
  end;

  
  Result := TryParse(Code, Model);
end;

class function TChartExtension.TryParse(const Code: IMarkdownCodeBlock; out Model: IChartModel): Boolean;
begin
  Model := nil;
  if Code = nil then
  begin
    Result := False;
    Exit;
  end;

  Result := TChartParser.TryBuildModel(Code.Literal, Model);
end;

class function TChartExtension.TryGetModel(const Node: IMarkdownNode; out Model: IChartModel): Boolean;
var
  Data: IInterface;
begin
  Model := nil;
  if Node = nil then
  begin
    Result := False;
    Exit;
  end;

  
  Result := Node.TryGetExtensionData(ChartModelExtensionKey, Data) and Supports(Data, IChartModel, Model);
end;

class procedure TChartExtension.Process(const Document: IMarkdownDocument);
var
  Pending: TStack<IMarkdownNode>;
  Index: Integer;
  Node: IMarkdownNode;
  Code: IMarkdownCodeBlock;
  Model: IChartModel;
begin
  if Document = nil then
    Exit;

  Pending := TStack<IMarkdownNode>.Create;
  try
    for Index := Document.ChildCount - 1 downto 0 do
    begin
      Pending.Push(Document.Children[Index]);
    end;

    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;

      
      if Supports(Node, IMarkdownCodeBlock, Code) and Code.IsFenced then
      begin
        
        if TryParse(Code, Model) then
          Node.SetExtensionData(ChartModelExtensionKey, Model);
      end;

      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node.Children[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

end.
