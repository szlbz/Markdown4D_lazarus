{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Image.Svg.Native;

{$SCOPEDENUMS ON}

// Draws an SVG with the parser, the flattener and the polygon rasterizer of
// this project, so a plain drawing needs no graphics library underneath it.
//
// What it covers: the shape elements, groups, transforms, the viewBox, solid
// fills, gradients, strokes with miter and round joins, opacity, both fill
// rules, clip paths, and text through the glyph seam. What it does not:
// patterns, filters, masks, embedded images and <use>. A document reaching for
// one of those is refused whole rather than drawn wrong, because half a
// drawing is worse than none.

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character,
  Markdown4D.Image.Svg;

// Takes this engine into the viewer's SVG hook.
procedure RegisterNativeSvgRasterizer;

// Draws with this engine alone, reporting False for anything it will not draw
// rather than passing it on. For a host that wants no fallback, and for tests
// that need to know which engine answered.
function TryRasterizeSvgNatively(const Svg: TBytes; const MaxWidth, MaxHeight: Single;
  out Raster: TMarkdownSvgRaster): Boolean;

implementation

uses
  StrUtils,
  Math,
  Markdown4D.Compat.NetEncoding,
  Generics.Collections,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Image.Rasterizer,
  Markdown4D.Image.Filters,
  Markdown4D.Image.Decoder,
  Markdown4D.Image.Glyphs,
  Markdown4D.Image.Svg.Xml,
  Markdown4D.Image.Svg.Path,
  // The Windows font engine, which answers where it can. Everywhere else the
  // FMX layer registers its own, because a cross-platform application is
  // already there.
  Markdown4D.Image.Glyphs.Gdi;

const
  // What a document without a font size of its own is drawn at.
  DefaultFontSize = 16.0;

  // The attribute names read more than once, so a typo cannot make one spelling
  // silently disagree with another.
  IdAttribute = 'id';
  WidthAttribute = 'width';
  HeightAttribute = 'height';
  LeftAttribute = 'x';
  TopAttribute = 'y';
  RadiusAttribute = 'r';
  RadiusXAttribute = 'rx';
  RadiusYAttribute = 'ry';
  CentreXAttribute = 'cx';
  CentreYAttribute = 'cy';
  X1Attribute = 'x1';
  Y1Attribute = 'y1';
  X2Attribute = 'x2';
  Y2Attribute = 'y2';
  PointsAttribute = 'points';
  StyleAttribute = 'style';
  MaskAttribute = 'mask';
  HrefAttribute = 'href';
  XlinkHrefAttribute = 'xlink:href';
  FilterAttribute = 'filter';
  InputAttribute = 'in';
  ZeroLength = '0';

  // The element names read more than once.
  FilterElement = 'filter';
  StyleElement = 'style';
  MaskElement = 'mask';
  SvgElement = 'svg';
  LineElement = 'line';
  PolylineElement = 'polyline';
  LinearGradientElement = 'lineargradient';

  // The presentation values compared more than once, spelled exactly as the
  // SVG specification writes them.
  NoneValue = 'none';
  CurrentColorValue = 'currentcolor';
  RoundValue = 'round';
  ObjectBoundingBoxValue = 'objectBoundingBox';
  UserSpaceOnUseValue = 'userSpaceOnUse';

type
  // Reads the values an SVG writes into its attributes: lengths, fractions,
  // colours, references and the style attribute that can carry any of them.
  TSvgValue = class
  public
    class function TryParseLength(const Text: string; out Value: Single): Boolean; static;
    class function TryParseFraction(const Text: string; out Value: Single): Boolean; static;
    class function TryParseColor(const Text: string; out Color: TLayoutColor): Boolean; static;
    class function TryParseReference(const Text: string; out Reference: string): Boolean; static;
    class function FirstFamilyName(const Families: string): string; static;
    class function StyleValue(const Style, Name: string): string; static;
    class function PresentationValue(const Element: TSvgXmlElement; const Name: string): string; static;
    class function WithOpacity(const Color: TLayoutColor; const Opacity: Single): TLayoutColor; static;
  end;

  TSvgMatrix = record
    A, B, C, D, E, F: Single;
    class function Identity: TSvgMatrix; static;
    class function Translation(const X, Y: Single): TSvgMatrix; static;
    class function Scaling(const X, Y: Single): TSvgMatrix; static;
    class function Rotation(const Degrees: Single): TSvgMatrix; static;
    class function SkewX(const Degrees: Single): TSvgMatrix; static;
    class function SkewY(const Degrees: Single): TSvgMatrix; static;
    function Multiply(const Other: TSvgMatrix): TSvgMatrix;
    function Apply(const Point: TLayoutPointF): TLayoutPointF;
    function AverageScale: Single;
    class function Parse(const Text: string): TSvgMatrix; static;
  end;

  TSvgGradient = record
    Kind: TMarkdownPaintKind;
    // The four numbers of a linear gradient, or the centre and radius of a
    // radial one, in the units the definition asked for.
    First: TLayoutPointF;
    Second: TLayoutPointF;
    Radius: Single;
    OnBoundingBox: Boolean;
    Stops: TArray<TMarkdownGradientStop>;
  end;

  TSvgFilterKind = (Blur, Offset, Flood, Composite, Merge);

  TSvgFilterStep = record
    Kind: TSvgFilterKind;
    Input: string;
    SecondInput: string;
    ResultName: string;
    DeviationX: Single;
    DeviationY: Single;
    DeltaX: Single;
    DeltaY: Single;
    Color: TLayoutColor;
    Operation: string;
    MergeInputs: TArray<string>;
  end;

  TSvgFilter = TArray<TSvgFilterStep>;

  TSvgStyle = record
    FillColor: TLayoutColor;
    FillPaintId: string;
    HasFill: Boolean;
    StrokeColor: TLayoutColor;
    StrokePaintId: string;
    HasStroke: Boolean;
    StrokeWidth: Single;
    FillRule: TMarkdownFillRule;
    Opacity: Single;
    FillOpacity: Single;
    StrokeOpacity: Single;
    RoundCaps: Boolean;
    RoundJoins: Boolean;
    FontFamily: string;
    FontSize: Single;
    Bold: Boolean;
    Italic: Boolean;
    Anchor: string;
    class function Initial: TSvgStyle; static;
    class function Read(const Element: TSvgXmlElement; const Parent: TSvgStyle): TSvgStyle; static;
  end;

  TSvgFrame = record
    Matrix: TSvgMatrix;
    Style: TSvgStyle;
    Mask: TMarkdownClipMask;
    Depth: Integer;
  end;

  ESvgUnsupported = class(Exception);

  TM4DGen2 = TArray<TArray<TLayoutPointF>>;
  TM4DGen1 = TDictionary<string, TArray<TSvgSubPath>>;
  TNativeSvgRenderer = class
  private
    const
      DefaultViewportSize = 300.0;
      MinimumStrokeWidth = 0.1;
      // A reference pointing back at what already contains it would go on for
      // ever, so the nesting is bounded.
      MaxFragmentDepth = 8;
      RadiansPerDegree = Pi / 180;
      OpaqueAlpha = $FF000000;
      SkippedElements: array[0..6] of string = ('defs', 'clippath', MaskElement, 'marker', FilterElement,
        StyleElement, 'pattern');
      UnsupportedElements: array[0..0] of string = ('foreignobject');
    var
      FRaster: TMarkdownPixelRaster;
      FGradients: TDictionary<string, TSvgGradient>;
      FClipPaths: TM4DGen1;
      FFilters: TDictionary<string, TSvgFilter>;
      // The markup of every element carrying an id, so a reference to it can be
      // drawn again wherever it is pointed at.
      FDefinitions: TDictionary<string, string>;
      FFragmentDepth: Integer;
      // Layers a filtered element is drawn into, and the filter waiting to be
      // applied to each of them when it closes.
      FLayers: TArray<TMarkdownPixelRaster>;
      FPendingFilters: TArray<TSvgFilter>;
      FLayerDepths: TArray<Integer>;
      FStack: TArray<TSvgFrame>;
      FDepth: Integer;
      FSkipUntilDepth: Integer;
      FSkipping: Boolean;
    function Frame: TSvgFrame;
    procedure Push(const Element: TSvgXmlElement);
    procedure Pop;
    procedure DrawElement(const Element: TSvgXmlElement);
    procedure DrawText(const Element: TSvgXmlElement);
    procedure DrawImage(const Element: TSvgXmlElement);
    class function TryDecodeDataUri(const Reference: string; out Data: TBytes): Boolean; static;
    procedure DrawSubPaths(const SubPaths: TArray<TSvgSubPath>; const Style: TSvgStyle; const Matrix: TSvgMatrix);
    procedure FillSubPaths(const SubPaths: TArray<TSvgSubPath>; const Style: TSvgStyle; const Matrix: TSvgMatrix);
    procedure StrokeSubPaths(const SubPaths: TArray<TSvgSubPath>; const Style: TSvgStyle; const Matrix: TSvgMatrix);
    class function Transformed(const Points: TArray<TLayoutPointF>; const Matrix: TSvgMatrix): TArray<TLayoutPointF>; static;
    class function RectanglePath(const Left, Top, Width, Height, RadiusX, RadiusY: Single): TArray<TSvgSubPath>; static;
    class function EllipsePath(const CentreX, CentreY, RadiusX, RadiusY: Single): TArray<TSvgSubPath>; static;
    class function PointsPath(const Data: string; const Closed: Boolean): TArray<TSvgSubPath>; static;
    class function SubPathsFor(const Element: TSvgXmlElement): TArray<TSvgSubPath>; static;
    class function BoundsOf(const Contours: TM4DGen2): TLayoutRectF; static;
    procedure CollectDefinitions(const Svg: string);
    function PaintFor(const PaintId: string; const Color: TLayoutColor; const Opacity: Single;
      const Contours: TM4DGen2; const Matrix: TSvgMatrix): TMarkdownPaint;
    function ClipMaskFor(const Reference: string; const Matrix: TSvgMatrix;
      const Parent: TMarkdownClipMask): TMarkdownClipMask;
    procedure DrawFragment(const Svg: string);
    procedure DrawUse(const Element: TSvgXmlElement);
    function MaskFor(const Reference: string; const Parent: TMarkdownClipMask): TMarkdownClipMask;
    function TryTilePaint(const Reference: string; const Contours: TM4DGen2;
      const Matrix: TSvgMatrix; out Paint: TMarkdownPaint): Boolean;
    procedure CollectMarkup(const Svg: string);
    class function InnerMarkup(const Markup: string): string; static;
    procedure BeginLayer(const Filter: TSvgFilter);
    procedure EndLayer;
    function ApplyFilter(const Filter: TSvgFilter; const Source: TMarkdownPixelRaster): TMarkdownPixelRaster;
    class function SourceAlphaOf(const Source: TMarkdownPixelRaster): TMarkdownPixelRaster; static;

  public
    constructor Create;
    destructor Destroy; override;
    function Render(const Svg: string; const MaxWidth, MaxHeight: Single): TMarkdownSvgRaster;
  end;

class function TSvgMatrix.Identity: TSvgMatrix;
begin
  Result.A := 1;
  Result.B := 0;
  Result.C := 0;
  Result.D := 1;
  Result.E := 0;
  Result.F := 0;
end;

class function TSvgMatrix.Translation(const X, Y: Single): TSvgMatrix;
begin
  Result := Identity;
  Result.E := X;
  Result.F := Y;
end;

class function TSvgMatrix.Scaling(const X, Y: Single): TSvgMatrix;
begin
  Result := Identity;
  Result.A := X;
  Result.D := Y;
end;

class function TSvgMatrix.Rotation(const Degrees: Single): TSvgMatrix;
var
  Angle: Double;
begin
  Angle := Degrees * Pi / 180;

  Result := Identity;
  Result.A := Cos(Angle);
  Result.B := Sin(Angle);
  Result.C := -Sin(Angle);
  Result.D := Cos(Angle);
end;

class function TSvgMatrix.SkewX(const Degrees: Single): TSvgMatrix;
begin
  Result := Identity;
  Result.C := Tan(Degrees * Pi / 180);
end;

class function TSvgMatrix.SkewY(const Degrees: Single): TSvgMatrix;
begin
  Result := Identity;
  Result.B := Tan(Degrees * Pi / 180);
end;

// Self first, then Other: a point goes through this matrix and then through
// the one handed in, which is how a shape reaches its group and its group
// reaches the page.
function TSvgMatrix.Multiply(const Other: TSvgMatrix): TSvgMatrix;
begin
  Result.A := A * Other.A + B * Other.C;
  Result.B := A * Other.B + B * Other.D;
  Result.C := C * Other.A + D * Other.C;
  Result.D := C * Other.B + D * Other.D;
  Result.E := E * Other.A + F * Other.C + Other.E;
  Result.F := E * Other.B + F * Other.D + Other.F;
end;

function TSvgMatrix.Apply(const Point: TLayoutPointF): TLayoutPointF;
begin
  Result := TLayoutPointF.Create(A * Point.X + C * Point.Y + E, B * Point.X + D * Point.Y + F);
end;

// What a stroke width becomes after the transform. A stroke under an uneven
// scale is an ellipse rather than a circle, which this rounds off to one width.
function TSvgMatrix.AverageScale: Single;
begin
  Result := (Sqrt(A * A + B * B) + Sqrt(C * C + D * D)) / 2;
end;

class function TSvgStyle.Initial: TSvgStyle;
begin
  Result.FillColor := $FF000000;
  Result.FillPaintId := '';
  Result.HasFill := True;
  Result.StrokeColor := $FF000000;
  Result.StrokePaintId := '';
  Result.HasStroke := False;
  Result.StrokeWidth := 1;
  Result.FillRule := TMarkdownFillRule.NonZero;
  Result.Opacity := 1;
  Result.FillOpacity := 1;
  Result.StrokeOpacity := 1;
  Result.RoundCaps := False;
  Result.RoundJoins := False;
  Result.FontFamily := '';
  Result.FontSize := DefaultFontSize;
  Result.Bold := False;
  Result.Italic := False;
  Result.Anchor := '';
end;

class function TSvgValue.TryParseLength(const Text: string; out Value: Single): Boolean;
const
  Suffixes: array[0..6] of string = ('px', 'pt', 'pc', 'mm', 'cm', 'in', '%');
var
  Trimmed: string;
  Suffix: string;
begin
  Trimmed := Text.Trim;
  if Trimmed = '' then
  begin
    Result := False;
    Exit;
  end;

  for Suffix in Suffixes do
  begin
    if Trimmed.EndsWith(Suffix, True) then
    begin
      Trimmed := Copy(Trimmed, 1, Length(Trimmed) - Length(Suffix)).Trim;
      Break;
    end;
  end;

  Result := TryStrToFloat(Trimmed, Value, TFormatSettings.Invariant);
end;

class function TSvgValue.TryParseFraction(const Text: string; out Value: Single): Boolean;
var
  Trimmed: string;
begin
  Value := 0;

  Trimmed := Text.Trim;
  if Trimmed = '' then
  begin
    Result := False;
    Exit;
  end;

  if Trimmed.EndsWith('%') then
  begin
    Result := TryStrToFloat(Copy(Trimmed, 1, Length(Trimmed) - 1).Trim, Value, TFormatSettings.Invariant);
    Value := Value / 100;
    Exit;
  end;

  Result := TryStrToFloat(Trimmed, Value, TFormatSettings.Invariant);
end;

class function TSvgValue.TryParseColor(const Text: string; out Color: TLayoutColor): Boolean;
const
  Named: array[0..15] of record Name: string; Value: Cardinal; end = (
    (Name: 'black'; Value: $FF000000), (Name: 'white'; Value: $FFFFFFFF),
    (Name: 'red'; Value: $FFFF0000), (Name: 'lime'; Value: $FF00FF00),
    (Name: 'blue'; Value: $FF0000FF), (Name: 'yellow'; Value: $FFFFFF00),
    (Name: 'cyan'; Value: $FF00FFFF), (Name: 'aqua'; Value: $FF00FFFF),
    (Name: 'magenta'; Value: $FFFF00FF), (Name: 'fuchsia'; Value: $FFFF00FF),
    (Name: 'silver'; Value: $FFC0C0C0), (Name: 'gray'; Value: $FF808080),
    (Name: 'grey'; Value: $FF808080), (Name: 'maroon'; Value: $FF800000),
    (Name: 'green'; Value: $FF008000), (Name: 'navy'; Value: $FF000080));
var
  Trimmed: type of (Text.Trim.ToLowerInvariant);
  Digits: string;
  Value: Integer;
  Inner: string;
  Reader: TSvgNumberReader;
  Red: Single;
  Green: Single;
  Blue: Single;
  Entry: type of (Named[0]);
begin
  Color := $FF000000;
  Trimmed := Text.Trim.ToLowerInvariant;
  if Trimmed = '' then
  begin
    Result := False;
    Exit;
  end;

  if Trimmed.StartsWith('#') then
  begin
    Digits := Copy(Trimmed, 2, MaxInt);
    Value := 0;

    if Length(Digits) = 3 then
    begin
      if not TryStrToInt('$' + Digits[1] + Digits[1] + Digits[2] + Digits[2] + Digits[3] + Digits[3], Value) then
      begin
        Result := False;
        Exit;
      end;
    end
    else if Length(Digits) = 6 then
    begin
      if not TryStrToInt('$' + Digits, Value) then
      begin
        Result := False;
        Exit;
      end;
    end
    else
    begin
      Result := False;
      Exit;
    end;

    Color := TLayoutColor(Cardinal(Value) or $FF000000);
    Result := True;
    Exit;
  end;

  if Trimmed.StartsWith('rgb(') and Trimmed.EndsWith(')') then
  begin
    Inner := Copy(Trimmed, 5, Length(Trimmed) - 5);
    Reader := TSvgNumberReader.Create(Inner);

    
    
    
    if not (Reader.TryReadNumber(Red) and Reader.TryReadNumber(Green) and Reader.TryReadNumber(Blue)) then
    begin
      Result := False;
      Exit;
    end;

    Color := TLayoutColor($FF000000 or (Cardinal(Round(EnsureRange(Red, 0, 255))) shl 16) or
      (Cardinal(Round(EnsureRange(Green, 0, 255))) shl 8) or Cardinal(Round(EnsureRange(Blue, 0, 255))));
    Result := True;
    Exit;
  end;

  for Entry in Named do
  begin
    if Entry.Name = Trimmed then
    begin
      Color := TLayoutColor(Entry.Value);
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

// "url(#name)" points at a definition elsewhere in the document.
class function TSvgValue.TryParseReference(const Text: string; out Reference: string): Boolean;
var
  Trimmed: string;
  Inner: type of (Copy(Trimmed, 5, Length(Trimmed) - 5).Trim);
begin
  Reference := '';

  Trimmed := Text.Trim;
  if not (Trimmed.StartsWith('url(', True) and Trimmed.EndsWith(')')) then
  begin
    Result := False;
    Exit;
  end;

  Inner := Copy(Trimmed, 5, Length(Trimmed) - 5).Trim;
  if Inner.StartsWith('#') then
    Inner := Copy(Inner, 2, MaxInt);

  Reference := Inner.Trim(['''', '"']);
  Result := Reference <> '';
end;

class function TSvgValue.FirstFamilyName(const Families: string): string;
var
  Family: string;
  Trimmed: string;
begin
  for Family in Families.Split([',']) do
  begin
    Trimmed := Family.Trim.Trim(['''', '"']);
    if Trimmed = '' then
      Continue;

    if SameText(Trimmed, 'sans-serif') then
    begin
      Result := 'Segoe UI';
      Exit;
    end;
    if SameText(Trimmed, 'serif') then
    begin
      Result := 'Times New Roman';
      Exit;
    end;
    if SameText(Trimmed, 'monospace') then
    begin
      Result := 'Consolas';
      Exit;
    end;

    Result := Trimmed;
    Exit;
  end;

  Result := 'Segoe UI';
end;

class function TSvgValue.StyleValue(const Style, Name: string): string;
var
  Part: string;
  Separator: Integer;
begin
  Result := '';
  if Style = '' then
    Exit;

  for Part in Style.Split([';']) do
  begin
    Separator := Pos(':', Part);
    if Separator = 0 then
      Continue;

    if SameText(Copy(Part, 1, Separator - 1).Trim, Name) then
    begin
      Result := Copy(Part, Separator + 1, MaxInt).Trim;
      Exit;
    end;
  end;
end;

// An attribute and its counterpart inside a style attribute say the same thing,
// with the style winning, so both are read through one lookup.
class function TSvgValue.PresentationValue(const Element: TSvgXmlElement; const Name: string): string;
var
  Style: string;
begin
  Style := Element.Attribute(StyleAttribute);

  Result := TSvgValue.StyleValue(Style, Name);
  if Result = '' then
    Result := Element.Attribute(Name);
end;

class function TSvgMatrix.Parse(const Text: string): TSvgMatrix;
var
  Index: Integer;
  Open: type of (Pos('(', Text, Index));
  Close: type of (Pos(')', Text, Open));
  Name: type of (Copy(Text, Index, Open - Index).Trim.Replace(',', '').ToLowerInvariant);
  Reader: TSvgNumberReader;
  Values: TArray<Single>;
  Value: Single;
  Step: TSvgMatrix;
  OffsetY: Double;
  ScaleY: Single;
begin
  Result := TSvgMatrix.Identity;
  if Text.Trim = '' then
    Exit;

  Index := 1;
  while Index <= Length(Text) do
  begin
    Open := Pos('(', Text, Index);
    if Open = 0 then
      Exit;

    Close := Pos(')', Text, Open);
    if Close = 0 then
      Exit;

    Name := Copy(Text, Index, Open - Index).Trim.Replace(',', '').ToLowerInvariant;
    Reader := TSvgNumberReader.Create(Copy(Text, Open + 1, Close - Open - 1));

    Values := nil;
    
    while Reader.TryReadNumber(Value) do
    begin
      Values := Values + [Value];
    end;

    Step := TSvgMatrix.Identity;

    if (Name = 'translate') and (Length(Values) >= 1) then
    begin
      OffsetY := 0.0;
      if Length(Values) >= 2 then
        OffsetY := Values[1];
      Step := TSvgMatrix.Translation(Values[0], OffsetY);
    end
    else if (Name = 'scale') and (Length(Values) >= 1) then
    begin
      ScaleY := Values[0];
      if Length(Values) >= 2 then
        ScaleY := Values[1];
      Step := TSvgMatrix.Scaling(Values[0], ScaleY);
    end
    else if (Name = 'rotate') and (Length(Values) >= 1) then
    begin
      // Rotating about a point means moving that point to the origin first and
      // putting it back afterwards.
      if Length(Values) >= 3 then
        Step := TSvgMatrix.Translation(-Values[1], -Values[2])
          .Multiply(TSvgMatrix.Rotation(Values[0]))
          .Multiply(TSvgMatrix.Translation(Values[1], Values[2]))
      else
        Step := TSvgMatrix.Rotation(Values[0]);
    end
    else if (Name = 'skewx') and (Length(Values) >= 1) then
      Step := TSvgMatrix.SkewX(Values[0])
    else if (Name = 'skewy') and (Length(Values) >= 1) then
      Step := TSvgMatrix.SkewY(Values[0])
    else if (Name = 'matrix') and (Length(Values) >= 6) then
    begin
      Step.A := Values[0];
      Step.B := Values[1];
      Step.C := Values[2];
      Step.D := Values[3];
      Step.E := Values[4];
      Step.F := Values[5];
    end;

    // The list reads outermost first, so each transform runs before the ones
    // already collected to its left.
    Result := Step.Multiply(Result);
    Index := Close + 1;
  end;
end;

class function TSvgStyle.Read(const Element: TSvgXmlElement; const Parent: TSvgStyle): TSvgStyle;
var
  Fill: string;
  Reference: string;
  Stroke: string;
  Value: Single;
  Join: type of (TSvgValue.PresentationValue(Element, 'stroke-linejoin').Trim);
  Family: string;
  Weight: type of (TSvgValue.PresentationValue(Element, 'font-weight').Trim);
  Slant: type of (TSvgValue.PresentationValue(Element, 'font-style').Trim);
  Anchor: type of (TSvgValue.PresentationValue(Element, 'text-anchor').Trim);
begin
  Result := Parent;

  Fill := TSvgValue.PresentationValue(Element, 'fill');
  if Fill <> '' then
  begin
    Reference := '';
    if SameText(Fill.Trim, NoneValue) then
      Result.HasFill := False
    else if TSvgValue.TryParseReference(Fill, Reference) then
    begin
      Result.FillPaintId := Reference;
      Result.HasFill := True;
    end
    else if TSvgValue.TryParseColor(Fill, Result.FillColor) then
    begin
      Result.FillPaintId := '';
      Result.HasFill := True;
    end
    else if not SameText(Fill.Trim, CurrentColorValue) then
      raise ESvgUnsupported.CreateFmt('fill "%s"', [Fill]);
  end;

  Stroke := TSvgValue.PresentationValue(Element, 'stroke');
  if Stroke <> '' then
  begin
    Reference := '';
    if SameText(Stroke.Trim, NoneValue) then
      Result.HasStroke := False
    else if TSvgValue.TryParseReference(Stroke, Reference) then
    begin
      Result.StrokePaintId := Reference;
      Result.HasStroke := True;
    end
    else if TSvgValue.TryParseColor(Stroke, Result.StrokeColor) then
    begin
      Result.StrokePaintId := '';
      Result.HasStroke := True;
    end
    else if not SameText(Stroke.Trim, CurrentColorValue) then
      raise ESvgUnsupported.CreateFmt('stroke "%s"', [Stroke]);
  end;

  
  if TSvgValue.TryParseLength(TSvgValue.PresentationValue(Element, 'stroke-width'), Value) then
    Result.StrokeWidth := Value;

  if TSvgValue.TryParseLength(TSvgValue.PresentationValue(Element, 'opacity'), Value) then
    Result.Opacity := Result.Opacity * EnsureRange(Value, 0, 1);

  if TSvgValue.TryParseLength(TSvgValue.PresentationValue(Element, 'fill-opacity'), Value) then
    Result.FillOpacity := EnsureRange(Value, 0, 1);

  if TSvgValue.TryParseLength(TSvgValue.PresentationValue(Element, 'stroke-opacity'), Value) then
    Result.StrokeOpacity := EnsureRange(Value, 0, 1);

  if SameText(TSvgValue.PresentationValue(Element, 'fill-rule').Trim, 'evenodd') then
    Result.FillRule := TMarkdownFillRule.EvenOdd
  else if SameText(TSvgValue.PresentationValue(Element, 'fill-rule').Trim, 'nonzero') then
    Result.FillRule := TMarkdownFillRule.NonZero;

  Result.RoundCaps := SameText(TSvgValue.PresentationValue(Element, 'stroke-linecap').Trim, RoundValue);

  Join := TSvgValue.PresentationValue(Element, 'stroke-linejoin').Trim;
  if Join <> '' then
    Result.RoundJoins := SameText(Join, RoundValue);

  // Font properties are inherited, and a document that sets them on a group
  // expects the text inside it to pick them up.
  Family := TSvgValue.PresentationValue(Element, 'font-family');
  if Family <> '' then
    Result.FontFamily := Family;

  if TSvgValue.TryParseLength(TSvgValue.PresentationValue(Element, 'font-size'), Value) then
    Result.FontSize := Value;

  Weight := TSvgValue.PresentationValue(Element, 'font-weight').Trim;
  if Weight <> '' then
    Result.Bold := SameText(Weight, 'bold') or SameText(Weight, 'bolder') or (Weight = '700') or
      (Weight = '800') or (Weight = '900');

  Slant := TSvgValue.PresentationValue(Element, 'font-style').Trim;
  if Slant <> '' then
    Result.Italic := SameText(Slant, 'italic') or SameText(Slant, 'oblique');

  Anchor := TSvgValue.PresentationValue(Element, 'text-anchor').Trim;
  if Anchor <> '' then
    Result.Anchor := Anchor;
end;

class function TSvgValue.WithOpacity(const Color: TLayoutColor; const Opacity: Single): TLayoutColor;
var
  Alpha: Int64;
begin
  Alpha := Round((Color shr 24) * EnsureRange(Opacity, 0, 1));

  Result := TLayoutColor((Color and $00FFFFFF) or (Cardinal(Alpha) shl 24));
end;

constructor TNativeSvgRenderer.Create;
begin
  inherited Create;

  FGradients := TDictionary<string, TSvgGradient>.Create;
  FClipPaths := TM4DGen1.Create;
  FFilters := TDictionary<string, TSvgFilter>.Create;
  FDefinitions := TDictionary<string, string>.Create;
end;

destructor TNativeSvgRenderer.Destroy;
begin
  FDefinitions.Free;
  FFilters.Free;
  FClipPaths.Free;
  FGradients.Free;

  inherited Destroy;
end;

function TNativeSvgRenderer.Frame: TSvgFrame;
begin
  Result := FStack[High(FStack)];
end;

// Pushed once so that MaskFor's own Frame lookup already sees this element's
// depth, matrix and clip-path mask while it renders the referenced <mask>
// markup, popped again because Next is a value and the mask MaskFor resolves
// still has to land on it, then pushed for real now that Next carries it.
procedure TNativeSvgRenderer.Push(const Element: TSvgXmlElement);
var
  Next: TSvgFrame;
  Reference: string;
begin
  Next := Frame;
  Next.Depth := FDepth;
  Next.Style := TSvgStyle.Read(Element, Next.Style);
  Next.Matrix := TSvgMatrix.Parse(Element.Attribute('transform')).Multiply(Next.Matrix);

  Reference := '';
  if TSvgValue.TryParseReference(TSvgValue.PresentationValue(Element, 'clip-path'), Reference) then
    Next.Mask := ClipMaskFor(Reference, Next.Matrix, Next.Mask);

  FStack := FStack + [Next];
  try
    if TSvgValue.TryParseReference(TSvgValue.PresentationValue(Element, MaskAttribute), Reference) then
      Next.Mask := MaskFor(Reference, Next.Mask);
  finally
    Pop;
  end;

  FStack := FStack + [Next];
end;

procedure TNativeSvgRenderer.Pop;
begin
  if Length(FStack) > 1 then
    SetLength(FStack, Length(FStack) - 1);
end;

class function TNativeSvgRenderer.Transformed(const Points: TArray<TLayoutPointF>;
  const Matrix: TSvgMatrix): TArray<TLayoutPointF>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Points));

  for Index := 0 to High(Points) do
  begin
    Result[Index] := Matrix.Apply(Points[Index]);
  end;
end;

procedure TNativeSvgRenderer.FillSubPaths(const SubPaths: TArray<TSvgSubPath>; const Style: TSvgStyle;
  const Matrix: TSvgMatrix);
var
  Contours: TM4DGen2;
  SubPath: TSvgSubPath;
  Paint: TMarkdownPaint;
begin
  Contours := nil;

  for SubPath in SubPaths do
  begin
    if Length(SubPath.Points) >= 3 then
      Contours := Contours + [Transformed(SubPath.Points, Matrix)];
  end;

  if Length(Contours) = 0 then
    Exit;

  Paint := PaintFor(Style.FillPaintId, Style.FillColor, Style.Opacity * Style.FillOpacity,
    Contours, Matrix);

  TMarkdownPolygonRasterizer.FillPaintedContoursInto(FRaster, Contours, Paint, Style.FillRule, Frame.Mask);
end;

procedure TNativeSvgRenderer.StrokeSubPaths(const SubPaths: TArray<TSvgSubPath>; const Style: TSvgStyle;
  const Matrix: TSvgMatrix);
var
  HalfWidth: Double;
  Contours: TM4DGen2;
  SubPath: TSvgSubPath;
  Device: TArray<TLayoutPointF>;
  Paint: TMarkdownPaint;
begin
  HalfWidth := Max(MinimumStrokeWidth, Style.StrokeWidth * Matrix.AverageScale) / 2;

  Contours := nil;
  for SubPath in SubPaths do
  begin
    Device := Transformed(SubPath.Points, Matrix);
    Contours := Contours + TMarkdownPolygonRasterizer.StrokeContours(Device, SubPath.IsClosed, HalfWidth,
      Style.RoundJoins, Style.RoundCaps);
  end;

  if Length(Contours) = 0 then
    Exit;

  Paint := PaintFor(Style.StrokePaintId, Style.StrokeColor, Style.Opacity * Style.StrokeOpacity,
    Contours, Matrix);

  TMarkdownPolygonRasterizer.FillPaintedContoursInto(FRaster, Contours, Paint, TMarkdownFillRule.NonZero,
    Frame.Mask);
end;

procedure TNativeSvgRenderer.DrawSubPaths(const SubPaths: TArray<TSvgSubPath>; const Style: TSvgStyle;
  const Matrix: TSvgMatrix);
begin
  if Length(SubPaths) = 0 then
    Exit;

  if Style.HasFill then
    FillSubPaths(SubPaths, Style, Matrix);

  if Style.HasStroke then
    StrokeSubPaths(SubPaths, Style, Matrix);
end;

class function TNativeSvgRenderer.RectanglePath(const Left, Top, Width, Height,
  RadiusX, RadiusY: Single): TArray<TSvgSubPath>;
var
  Rx: Double;
  Ry: Double;
  Data: string;
begin
  if (Width <= 0) or (Height <= 0) then
  begin
    Result := nil;
    Exit;
  end;

  Rx := Min(Max(0, RadiusX), Width / 2);
  Ry := Min(Max(0, RadiusY), Height / 2);

  Data := '';
  if (Rx = 0) or (Ry = 0) then
    Data := Format('M %s %s H %s V %s H %s Z',
      [FloatToStr(Left, TFormatSettings.Invariant), FloatToStr(Top, TFormatSettings.Invariant),
       FloatToStr(Left + Width, TFormatSettings.Invariant), FloatToStr(Top + Height, TFormatSettings.Invariant),
       FloatToStr(Left, TFormatSettings.Invariant)])
  else
    Data := Format('M %s %s H %s A %s %s 0 0 1 %s %s V %s A %s %s 0 0 1 %s %s H %s A %s %s 0 0 1 %s %s V %s ' +
      'A %s %s 0 0 1 %s %s Z',
      [FloatToStr(Left + Rx, TFormatSettings.Invariant), FloatToStr(Top, TFormatSettings.Invariant),
       FloatToStr(Left + Width - Rx, TFormatSettings.Invariant),
       FloatToStr(Rx, TFormatSettings.Invariant), FloatToStr(Ry, TFormatSettings.Invariant),
       FloatToStr(Left + Width, TFormatSettings.Invariant), FloatToStr(Top + Ry, TFormatSettings.Invariant),
       FloatToStr(Top + Height - Ry, TFormatSettings.Invariant),
       FloatToStr(Rx, TFormatSettings.Invariant), FloatToStr(Ry, TFormatSettings.Invariant),
       FloatToStr(Left + Width - Rx, TFormatSettings.Invariant), FloatToStr(Top + Height, TFormatSettings.Invariant),
       FloatToStr(Left + Rx, TFormatSettings.Invariant),
       FloatToStr(Rx, TFormatSettings.Invariant), FloatToStr(Ry, TFormatSettings.Invariant),
       FloatToStr(Left, TFormatSettings.Invariant), FloatToStr(Top + Height - Ry, TFormatSettings.Invariant),
       FloatToStr(Top + Ry, TFormatSettings.Invariant),
       FloatToStr(Rx, TFormatSettings.Invariant), FloatToStr(Ry, TFormatSettings.Invariant),
       FloatToStr(Left + Rx, TFormatSettings.Invariant), FloatToStr(Top, TFormatSettings.Invariant)]);

  Result := TSvgPathParser.Parse(Data);
end;

class function TNativeSvgRenderer.EllipsePath(const CentreX, CentreY, RadiusX, RadiusY: Single): TArray<TSvgSubPath>;
const
  Segments = 72;
var
  Points: TArray<TLayoutPointF>;
  Step: Integer;
  Angle: Double;
  SubPath: TSvgSubPath;
begin
  if (RadiusX <= 0) or (RadiusY <= 0) then
  begin
    Result := nil;
    Exit;
  end;

  
  SetLength(Points, Segments);
  for Step := 0 to Segments - 1 do
  begin
    Angle := 2 * Pi * Step / Segments;
    Points[Step] := TLayoutPointF.Create(CentreX + RadiusX * Cos(Angle), CentreY + RadiusY * Sin(Angle));
  end;

  
  SubPath.Points := Points;
  SubPath.IsClosed := True;

  Result := [SubPath];
end;

class function TNativeSvgRenderer.PointsPath(const Data: string; const Closed: Boolean): TArray<TSvgSubPath>;
var
  Reader: TSvgNumberReader;
  Points: TArray<TLayoutPointF>;
  X: Single;
  SubPath: TSvgSubPath;
begin
  Reader := TSvgNumberReader.Create(Data);

  Points := nil;
  
  while Reader.TryReadNumber(X) do
  begin
    Points := Points + [TLayoutPointF.Create(X, Reader.ReadNumber)];
  end;

  if Length(Points) < 2 then
  begin
    Result := nil;
    Exit;
  end;

  
  SubPath.Points := Points;
  SubPath.IsClosed := Closed;

  Result := [SubPath];
end;

class function TNativeSvgRenderer.SubPathsFor(const Element: TSvgXmlElement): TArray<TSvgSubPath>;
var
  Name: type of (Element.Name.ToLowerInvariant);
  Left: Single;
  Top: Single;
  Width: Single;
  Height: Single;
  RadiusX: Single;
  RadiusY: Single;
  Radius: Single;
  SubPath: TSvgSubPath;
begin
  Result := nil;

  Name := Element.Name.ToLowerInvariant;

  
  
  
  

  if Name = 'path' then
  begin
    Result := TSvgPathParser.Parse(Element.Attribute('d'));
    Exit;
  end;

  if Name = 'rect' then
  begin
    if not TSvgValue.TryParseLength(Element.Attribute(LeftAttribute, ZeroLength), Left) then
      Left := 0;
    if not TSvgValue.TryParseLength(Element.Attribute(TopAttribute, ZeroLength), Top) then
      Top := 0;
    if not (TSvgValue.TryParseLength(Element.Attribute(WidthAttribute), Width) and
      TSvgValue.TryParseLength(Element.Attribute(HeightAttribute), Height)) then
      Exit;

    RadiusX := 0;
    RadiusY := 0;
    TSvgValue.TryParseLength(Element.Attribute(RadiusXAttribute, ZeroLength), RadiusX);
    if not TSvgValue.TryParseLength(Element.Attribute(RadiusYAttribute, ZeroLength), RadiusY) then
      RadiusY := RadiusX;
    if RadiusY = 0 then
      RadiusY := RadiusX;
    if RadiusX = 0 then
      RadiusX := RadiusY;

    Result := RectanglePath(Left, Top, Width, Height, RadiusX, RadiusY);
    Exit;
  end;

  if Name = 'circle' then
  begin
    
    if not TSvgValue.TryParseLength(Element.Attribute(RadiusAttribute), Radius) then
      Exit;
    if not TSvgValue.TryParseLength(Element.Attribute(CentreXAttribute, ZeroLength), Left) then
      Left := 0;
    if not TSvgValue.TryParseLength(Element.Attribute(CentreYAttribute, ZeroLength), Top) then
      Top := 0;

    Result := EllipsePath(Left, Top, Radius, Radius);
    Exit;
  end;

  if Name = 'ellipse' then
  begin
    
    
    if not (TSvgValue.TryParseLength(Element.Attribute(RadiusXAttribute), RadiusX) and
      TSvgValue.TryParseLength(Element.Attribute(RadiusYAttribute), RadiusY)) then
      Exit;
    if not TSvgValue.TryParseLength(Element.Attribute(CentreXAttribute, ZeroLength), Left) then
      Left := 0;
    if not TSvgValue.TryParseLength(Element.Attribute(CentreYAttribute, ZeroLength), Top) then
      Top := 0;

    Result := EllipsePath(Left, Top, RadiusX, RadiusY);
    Exit;
  end;

  if Name = LineElement then
  begin
    if not (TSvgValue.TryParseLength(Element.Attribute(X1Attribute, ZeroLength), Left) and
      TSvgValue.TryParseLength(Element.Attribute(Y1Attribute, ZeroLength), Top) and
      TSvgValue.TryParseLength(Element.Attribute(X2Attribute, ZeroLength), Width) and
      TSvgValue.TryParseLength(Element.Attribute(Y2Attribute, ZeroLength), Height)) then
      Exit;

    
    SubPath.Points := [TLayoutPointF.Create(Left, Top), TLayoutPointF.Create(Width, Height)];
    SubPath.IsClosed := False;

    Result := [SubPath];
    Exit;
  end;

  if Name = PolylineElement then
  begin
    Result := PointsPath(Element.Attribute(PointsAttribute), False);
    Exit;
  end;

  if Name = 'polygon' then
  begin
    Result := PointsPath(Element.Attribute(PointsAttribute), True);
    Exit;
  end;
end;

procedure TNativeSvgRenderer.DrawElement(const Element: TSvgXmlElement);
var
  SubPaths: TArray<TSvgSubPath>;
  Style: TSvgStyle;
  Name: type of (Element.Name.ToLowerInvariant);
begin
  if SameText(Element.Name, 'text') then
  begin
    DrawText(Element);
    Exit;
  end;

  if SameText(Element.Name, 'image') then
  begin
    DrawImage(Element);
    Exit;
  end;

  SubPaths := SubPathsFor(Element);
  if Length(SubPaths) = 0 then
    Exit;

  Style := Frame.Style;

  // A line or an open polyline has no inside to fill, whatever the style says.
  Name := Element.Name.ToLowerInvariant;
  if (Name = LineElement) or (Name = PolylineElement) then
    Style.HasFill := False;

  DrawSubPaths(SubPaths, Style, Frame.Matrix);
end;

// A text element is drawn from its own outlines: the system hands over the
// curves of the letters, and from there it is a fill like any other.
procedure TNativeSvgRenderer.DrawText(const Element: TSvgXmlElement);
var
  Content: string;
  Style: TSvgStyle;
  Family: string;
  Run: TMarkdownGlyphRun;
  Left: Single;
  Baseline: Single;
  Stretch: Single;
  Wanted: Single;
  Width: Single;
  Anchor: string;
  Placement: TSvgMatrix;
  Contours: TM4DGen2;
  Contour: TArray<TLayoutPointF>;
  Paint: TMarkdownPaint;
begin
  Content := Element.Text.Trim;
  if Content = '' then
    Exit;

  Style := Frame.Style;
  Family := TSvgValue.FirstFamilyName(Style.FontFamily);

  
  if not TMarkdownGlyphSupport.TryOutline(Family, Style.FontSize, Style.Bold, Style.Italic, Content, Run) then
    raise ESvgUnsupported.Create('text outlines');

  
  
  if not TSvgValue.TryParseLength(Element.Attribute(LeftAttribute, ZeroLength), Left) then
    Left := 0;
  if not TSvgValue.TryParseLength(Element.Attribute(TopAttribute, ZeroLength), Baseline) then
    Baseline := 0;

  // A run asked to occupy a given width is stretched to it, which is how a
  // badge keeps its text inside its own box whatever font is installed.
  Stretch := 1;
  
  if TSvgValue.TryParseLength(Element.Attribute('textLength'), Wanted) and (Run.Advance > 0) then
    Stretch := Wanted / Run.Advance;

  Width := Run.Advance * Stretch;
  Anchor := Style.Anchor;
  if SameText(Anchor, 'middle') then
    Left := Left - Width / 2
  else if SameText(Anchor, 'end') then
    Left := Left - Width;

  Placement := TSvgMatrix.Scaling(Stretch, 1)
    .Multiply(TSvgMatrix.Translation(Left, Baseline))
    .Multiply(Frame.Matrix);


  Contours := nil;
  for Contour in Run.Contours do
  begin
    Contours := Contours + [Transformed(Contour, Placement)];
  end;

  if Length(Contours) = 0 then
    Exit;

  Paint := PaintFor(Style.FillPaintId, Style.FillColor, Style.Opacity * Style.FillOpacity,
    Contours, Placement);

  TMarkdownPolygonRasterizer.FillPaintedContoursInto(FRaster, Contours, Paint, TMarkdownFillRule.NonZero,
    Frame.Mask);
end;

// An image is carried inside the document as a data URI. Anything else points
// outside it, which is the host's business rather than this engine's.
class function TNativeSvgRenderer.TryDecodeDataUri(const Reference: string; out Data: TBytes): Boolean;
var
  Trimmed: string;
  Separator: Integer;
  Header: string;
begin
  Data := nil;

  Trimmed := Reference.Trim;
  if not Trimmed.StartsWith('data:', True) then
  begin
    Result := False;
    Exit;
  end;

  Separator := Pos(',', Trimmed);
  if Separator = 0 then
  begin
    Result := False;
    Exit;
  end;

  Header := Copy(Trimmed, 1, Separator - 1);
  if not Header.ToLowerInvariant.Contains('base64') then
  begin
    Result := False;
    Exit;
  end;

  try
    Data := M4DBase64Decode(Copy(Trimmed, Separator + 1, MaxInt));
    Result := Length(Data) > 0;
  except
    // The payload comes from the document; malformed base64 is the host's
    // problem to report, not a reason to take the renderer down with it.
    on Exception do
      Result := False;
  end;
end;

// Walks the pixels the image lands on and asks, for each of them, which pixel
// of the image it came from. That way a rotated or scaled image needs no
// special case: the matrix is simply read backwards.
procedure TNativeSvgRenderer.DrawImage(const Element: TSvgXmlElement);
var
  Reference: string;
  Data: TBytes;
  Source: TMarkdownPixelRaster;
  Left: Single;
  Top: Single;
  Width: Single;
  Height: Single;
  Style: TSvgStyle;
  Placement: TSvgMatrix;
  Determinant: Single;
  Backwards: TSvgMatrix;
  Corners: TArray<TLayoutPointF>;
  Bounds: TLayoutRectF;
  FirstColumn: Integer;
  LastColumn: Integer;
  FirstRow: Integer;
  LastRow: Integer;
  Opacity: type of (EnsureRange(Style.Opacity, 0, 1));
  HasMask: Boolean;
  Row: Integer;
  Column: Integer;
  Origin: type of (Backwards.Apply(TLayoutPointF.Create(Column + 0.5, Row + 0.5)));
  SourceColumn: Int64;
  SourceRow: Int64;
  Outside: Boolean;
  From: Int64;
  Weight: type of (Opacity);
  Arriving: Double;
  Onto: Integer;
  Remaining: Double;
  Channel: Integer;
begin
  Reference := Element.Attribute(HrefAttribute);
  if Reference = '' then
    Reference := Element.Attribute(XlinkHrefAttribute);

  
  if not TryDecodeDataUri(Reference, Data) then
    raise ESvgUnsupported.Create('image source');

  
  if not TMarkdownImageDecoding.TryDecode(Data, Source) then
    raise ESvgUnsupported.Create('image format');

  
  
  
  
  if not TSvgValue.TryParseLength(Element.Attribute(LeftAttribute, ZeroLength), Left) then
    Left := 0;
  if not TSvgValue.TryParseLength(Element.Attribute(TopAttribute, ZeroLength), Top) then
    Top := 0;
  if not TSvgValue.TryParseLength(Element.Attribute(WidthAttribute), Width) then
    Width := Source.Width;
  if not TSvgValue.TryParseLength(Element.Attribute(HeightAttribute), Height) then
    Height := Source.Height;

  if (Width <= 0) or (Height <= 0) then
    Exit;

  Style := Frame.Style;
  Placement := TSvgMatrix.Scaling(Width / Source.Width, Height / Source.Height)
    .Multiply(TSvgMatrix.Translation(Left, Top))
    .Multiply(Frame.Matrix);

  Determinant := Placement.A * Placement.D - Placement.B * Placement.C;
  if Abs(Determinant) < 0.000001 then
    Exit;

  Backwards := Default(TSvgMatrix);
  Backwards.A := Placement.D / Determinant;
  Backwards.B := -Placement.B / Determinant;
  Backwards.C := -Placement.C / Determinant;
  Backwards.D := Placement.A / Determinant;
  Backwards.E := (Placement.C * Placement.F - Placement.D * Placement.E) / Determinant;
  Backwards.F := (Placement.B * Placement.E - Placement.A * Placement.F) / Determinant;

  Corners := [Placement.Apply(TLayoutPointF.Create(0, 0)),
    Placement.Apply(TLayoutPointF.Create(Source.Width, 0)),
    Placement.Apply(TLayoutPointF.Create(Source.Width, Source.Height)),
    Placement.Apply(TLayoutPointF.Create(0, Source.Height))];

  Bounds := BoundsOf([Corners]);
  FirstColumn := Max(0, Floor(Bounds.Left));
  LastColumn := Min(FRaster.Width - 1, Ceil(Bounds.Right));
  FirstRow := Max(0, Floor(Bounds.Top));
  LastRow := Min(FRaster.Height - 1, Ceil(Bounds.Bottom));

  Opacity := EnsureRange(Style.Opacity, 0, 1);
  HasMask := (Length(Frame.Mask) = FRaster.Width * FRaster.Height);

  for Row := FirstRow to LastRow do
  begin
    for Column := FirstColumn to LastColumn do
    begin
      Origin := Backwards.Apply(TLayoutPointF.Create(Column + 0.5, Row + 0.5));
      SourceColumn := Trunc(Origin.X);
      SourceRow := Trunc(Origin.Y);

      Outside := ((Origin.X < 0) or (Origin.Y < 0) or (SourceColumn >= Source.Width) or
        (SourceRow >= Source.Height));
      if Outside then
        Continue;

      From := (SourceRow * Source.Width + SourceColumn) * 4;
      Weight := Opacity;
      if HasMask then
        Weight := Weight * Frame.Mask[Row * FRaster.Width + Column] / 255;

      Arriving := Source.Pixels[From + 3] / 255 * Weight;
      if Arriving <= 0 then
        Continue;

      Onto := (Row * FRaster.Width + Column) * 4;
      Remaining := 1 - Arriving;
      for Channel := 0 to 3 do
      begin
        FRaster.Pixels[Onto + Channel] :=
          Round(Source.Pixels[From + Channel] * Weight + FRaster.Pixels[Onto + Channel] * Remaining);
      end;
    end;
  end;
end;

// The box a shape occupies, which is what a gradient in bounding box units is
// measured against.
class function TNativeSvgRenderer.BoundsOf(const Contours: TM4DGen2): TLayoutRectF;
var
  Started: Boolean;
  Contour: TArray<TLayoutPointF>;
  Point: TLayoutPointF;
begin
  Result := TLayoutRectF.Create(0, 0, 0, 0);

  Started := False;
  for Contour in Contours do
  begin
    for Point in Contour do
    begin
      if not Started then
      begin
        Result := TLayoutRectF.Create(Point.X, Point.Y, Point.X, Point.Y);
        Started := True;
        Continue;
      end;

      Result.Left := Min(Result.Left, Point.X);
      Result.Top := Min(Result.Top, Point.Y);
      Result.Right := Max(Result.Right, Point.X);
      Result.Bottom := Max(Result.Bottom, Point.Y);
    end;
  end;
end;

// A pattern is a small drawing repeated over the shape. It is rendered once at
// the size it occupies on the page, and the rasterizer repeats it from there.
function TNativeSvgRenderer.TryTilePaint(const Reference: string;
  const Contours: TM4DGen2; const Matrix: TSvgMatrix; out Paint: TMarkdownPaint): Boolean;
var
  Definition: string;
  Scanner: TSvgXmlScanner;
  Wrapper: TSvgXmlElement;
  Left: Single;
  Top: Single;
  Width: Single;
  Height: Single;
  OnBoundingBox: Boolean;
  Bounds: TLayoutRectF;
  TileWidth: Single;
  TileHeight: Single;
  OriginX: Single;
  OriginY: Single;
  Scale: Single;
  Placed: type of (Matrix.Apply(TLayoutPointF.Create(Left, Top)));
  PixelWidth: Int64;
  PixelHeight: Int64;
  Markup: string;
  Beneath: TMarkdownPixelRaster;
  Tile: TMarkdownPixelRaster;
  Cell: TSvgFrame;
begin
  Paint := Default(TMarkdownPaint);

  Definition := '';
  if not FDefinitions.TryGetValue(Reference, Definition) then
  begin
    Result := False;
    Exit;
  end;

  Scanner := TSvgXmlScanner.Create(Definition);
  
  try
    if not Scanner.ReadElement(Wrapper) then
    begin
      Result := False;
      Exit;
    end;
  finally
    Scanner.Free;
  end;

  if not SameText(Wrapper.Name, 'pattern') then
  begin
    Result := False;
    Exit;
  end;

  Left := 0;
  Top := 0;
  Width := 0;
  Height := 0;
  TSvgValue.TryParseFraction(Wrapper.Attribute(LeftAttribute, ZeroLength), Left);
  TSvgValue.TryParseFraction(Wrapper.Attribute(TopAttribute, ZeroLength), Top);
  if not (TSvgValue.TryParseFraction(Wrapper.Attribute(WidthAttribute), Width) and
    TSvgValue.TryParseFraction(Wrapper.Attribute(HeightAttribute), Height)) then
  begin
    Result := False;
    Exit;
  end;

  OnBoundingBox := not SameText(Wrapper.Attribute('patternUnits', ObjectBoundingBoxValue), UserSpaceOnUseValue);
  Bounds := BoundsOf(Contours);

  
  
  
  

  if OnBoundingBox then
  begin
    TileWidth := Width * (Bounds.Right - Bounds.Left);
    TileHeight := Height * (Bounds.Bottom - Bounds.Top);
    OriginX := Bounds.Left + Left * (Bounds.Right - Bounds.Left);
    OriginY := Bounds.Top + Top * (Bounds.Bottom - Bounds.Top);
  end
  else
  begin
    Scale := Matrix.AverageScale;
    TileWidth := Width * Scale;
    TileHeight := Height * Scale;
    Placed := Matrix.Apply(TLayoutPointF.Create(Left, Top));
    OriginX := Placed.X;
    OriginY := Placed.Y;
  end;

  PixelWidth := Round(TileWidth);
  PixelHeight := Round(TileHeight);
  if (PixelWidth <= 0) or (PixelHeight <= 0) then
  begin
    Result := False;
    Exit;
  end;

  Markup := InnerMarkup(Definition);
  if Markup = '' then
  begin
    Result := False;
    Exit;
  end;

  Beneath := FRaster;
  FRaster := TMarkdownPixelRaster.Create(PixelWidth, PixelHeight);
  
  try
    Cell := Default(TSvgFrame);
    Cell.Style := Frame.Style;
    Cell.Style.FillPaintId := '';
    Cell.Matrix := TSvgMatrix.Scaling(PixelWidth / Width, PixelHeight / Height);
    FStack := FStack + [Cell];
    try
      DrawFragment(Markup);
    finally
      Pop;
    end;
  finally
    Tile := FRaster;
    FRaster := Beneath;
  end;

  Paint := TMarkdownPaint.Tiled(TLayoutPointF.Create(OriginX, OriginY), PixelWidth, PixelHeight, Tile.Pixels);
  Result := True;
end;

function TNativeSvgRenderer.PaintFor(const PaintId: string; const Color: TLayoutColor; const Opacity: Single;
  const Contours: TM4DGen2; const Matrix: TSvgMatrix): TMarkdownPaint;
var
  Tile: TMarkdownPaint;
  Gradient: TSvgGradient;
  Stops: TArray<TMarkdownGradientStop>;
  Index: Integer;
  First: TLayoutPointF;
  Second: TLayoutPointF;
  Radius: Single;
  Bounds: TLayoutRectF;
  Width: Single;
  Height: Single;
begin
  if PaintId <> '' then
  begin
    
    if TryTilePaint(PaintId, Contours, Matrix, Tile) then
    begin
      Result := Tile;
      Exit;
    end;
  end;

  
  if (PaintId = '') or (not FGradients.TryGetValue(PaintId, Gradient)) then
  begin
    Result := TMarkdownPaint.SolidColor(TSvgValue.WithOpacity(Color, Opacity));
    Exit;
  end;

  Stops := Gradient.Stops;
  for Index := 0 to High(Stops) do
  begin
    Stops[Index].Color := TSvgValue.WithOpacity(Stops[Index].Color, Opacity);
  end;

  // In bounding box units the numbers are fractions of the shape itself, so
  // they only become positions once the shape is known.
  First := Gradient.First;
  Second := Gradient.Second;
  Radius := Gradient.Radius;

  if Gradient.OnBoundingBox then
  begin
    Bounds := BoundsOf(Contours);
    Width := Bounds.Right - Bounds.Left;
    Height := Bounds.Bottom - Bounds.Top;

    First := TLayoutPointF.Create(Bounds.Left + First.X * Width, Bounds.Top + First.Y * Height);
    Second := TLayoutPointF.Create(Bounds.Left + Second.X * Width, Bounds.Top + Second.Y * Height);
    Radius := Radius * Max(Width, Height);
  end
  else
  begin
    First := Matrix.Apply(First);
    Second := Matrix.Apply(Second);
    Radius := Radius * Matrix.AverageScale;
  end;

  if Gradient.Kind = TMarkdownPaintKind.RadialGradient then
  begin
    Result := TMarkdownPaint.Radial(First, Radius, Stops);
    Exit;
  end;

  Result := TMarkdownPaint.Linear(First, Second, Stops);
end;

function TNativeSvgRenderer.ClipMaskFor(const Reference: string; const Matrix: TSvgMatrix;
  const Parent: TMarkdownClipMask): TMarkdownClipMask;
var
  SubPaths: TArray<TSvgSubPath>;
  Contours: TM4DGen2;
  SubPath: TSvgSubPath;
  Coverage: TMarkdownClipMask;
  Combined: TMarkdownClipMask;
  Index: Integer;
begin
  Result := Parent;

  
  if not FClipPaths.TryGetValue(Reference, SubPaths) then
    Exit;

  Contours := nil;
  for SubPath in SubPaths do
  begin
    if Length(SubPath.Points) >= 3 then
      Contours := Contours + [Transformed(SubPath.Points, Matrix)];
  end;

  if Length(Contours) = 0 then
    Exit;

  Coverage := TMarkdownPolygonRasterizer.CoverageOf(Contours, FRaster.Width, FRaster.Height,
    TMarkdownFillRule.NonZero);

  if Length(Parent) <> Length(Coverage) then
  begin
    Result := Coverage;
    Exit;
  end;

  // Two clips in force at once hold a shape to what they have in common.
  
  SetLength(Combined, Length(Coverage));
  for Index := 0 to High(Combined) do
  begin
    Combined[Index] := Parent[Index] * Coverage[Index] div 255;
  end;

  Result := Combined;
end;

// Walks a piece of markup and draws it, starting from whatever frame is on the
// stack. The document body is one such piece, and so is anything a reference
// points at.
procedure TNativeSvgRenderer.DrawFragment(const Svg: string);
var
  Scanner: TSvgXmlScanner;
  BaseDepth: Integer;
  Element: TSvgXmlElement;
  Name: type of (Element.Name.ToLowerInvariant);
  ClosesLayer: Boolean;
  Reference: string;
  Filter: TSvgFilter;
  IsFiltered: Boolean;
begin
  if FFragmentDepth >= MaxFragmentDepth then
    raise ESvgUnsupported.Create('nested references');

  Inc(FFragmentDepth);
  Scanner := TSvgXmlScanner.Create(Svg);
  try
    BaseDepth := FDepth;
    
    while Scanner.ReadElement(Element) do
    begin
      Name := Element.Name.ToLowerInvariant;

      if Element.IsClosing then
      begin
        Dec(FDepth);

        // An element that was skipped never pushed a frame, so its closing tag
        // must not pop one either: doing so would unwind the styles of
        // everything around it.
        if FSkipping then
        begin
          if FDepth < FSkipUntilDepth then
            FSkipping := False;
        end
        else
        begin
          ClosesLayer := (Length(FLayerDepths) > 0) and (FDepth < FLayerDepths[High(FLayerDepths)]);
          if ClosesLayer then
            EndLayer;

          Pop;
        end;

        if SameText(Name, SvgElement) or (FDepth < BaseDepth) then
          Break;

        Continue;
      end;

      Inc(FDepth);

      if FSkipping then
      begin
        if Element.IsSelfClosing then
          Dec(FDepth);
        Continue;
      end;

      if MatchStr(Name, SkippedElements) then
      begin
        if Element.IsSelfClosing then
          Dec(FDepth)
        else
        begin
          FSkipping := True;
          FSkipUntilDepth := FDepth;
        end;
        Continue;
      end;

      if Name = 'use' then
      begin
        Push(Element);
        DrawUse(Element);
        if Element.IsSelfClosing then
        begin
          Pop;
          Dec(FDepth);
        end;
        Continue;
      end;

      if MatchStr(Name, UnsupportedElements) then
        raise ESvgUnsupported.Create(Name);

      // A filtered element is drawn on a layer of its own, which the filter is
      // applied to when the element closes.
      Reference := '';
      Filter := nil;
      IsFiltered := TSvgValue.TryParseReference(TSvgValue.PresentationValue(Element, FilterAttribute), Reference) and
        FFilters.TryGetValue(Reference, Filter);
      if IsFiltered then
        BeginLayer(Filter);

      Push(Element);
      DrawElement(Element);

      if Element.IsSelfClosing then
      begin
        if IsFiltered then
          EndLayer;

        Pop;
        Dec(FDepth);
      end;
    end;
  finally
    Scanner.Free;
    Dec(FFragmentDepth);
  end;
end;

// A use element draws what it points at, moved to where it was put.
procedure TNativeSvgRenderer.DrawUse(const Element: TSvgXmlElement);
var
  Reference: string;
  Markup: string;
  Left: Single;
  Top: Single;
  Moved: TSvgFrame;
begin
  Reference := Element.Attribute(HrefAttribute);
  if Reference = '' then
    Reference := Element.Attribute(XlinkHrefAttribute);

  Reference := Reference.Trim;
  if Reference.StartsWith('#') then
    Reference := Copy(Reference, 2, MaxInt);

  Markup := '';
  if (Reference = '') or (not FDefinitions.TryGetValue(Reference, Markup)) then
    Exit;

  
  
  if not TSvgValue.TryParseLength(Element.Attribute(LeftAttribute, ZeroLength), Left) then
    Left := 0;
  if not TSvgValue.TryParseLength(Element.Attribute(TopAttribute, ZeroLength), Top) then
    Top := 0;

  Moved := Frame;
  Moved.Matrix := TSvgMatrix.Translation(Left, Top).Multiply(Moved.Matrix);
  FStack := FStack + [Moved];
  try
    DrawFragment(Markup);
  finally
    Pop;
  end;
end;

// What a definition holds, without the element wrapping it. A mask or a
// pattern is drawn from its contents; the wrapper itself is not a shape and is
// stepped over by the drawing loop.
class function TNativeSvgRenderer.InnerMarkup(const Markup: string): string;
var
  Opening: Integer;
  Closing: Integer;
begin
  Opening := Pos('>', Markup);
  Closing := Markup.LastIndexOf('<') + 1;

  if (Opening = 0) or (Closing <= Opening) then
  begin
    Result := '';
    Exit;
  end;

  Result := Copy(Markup, Opening + 1, Closing - Opening - 1);
end;

// A mask is a drawing of its own: how bright it is at each pixel decides how
// much of what it masks survives there.
function TNativeSvgRenderer.MaskFor(const Reference: string; const Parent: TMarkdownClipMask): TMarkdownClipMask;
var
  Definition: string;
  Markup: string;
  Beneath: TMarkdownPixelRaster;
  Painted: TMarkdownPixelRaster;
  Frameless: TSvgFrame;
  Coverage: TMarkdownClipMask;
  Combined: TMarkdownClipMask;
  Index: Integer;
begin
  Result := Parent;

  Definition := '';
  if not FDefinitions.TryGetValue(Reference, Definition) then
    Exit;

  Markup := InnerMarkup(Definition);
  if Markup = '' then
    Exit;

  Beneath := FRaster;
  FRaster := TMarkdownPixelRaster.Create(Beneath.Width, Beneath.Height);
  
  try
    Frameless := Frame;
    Frameless.Mask := nil;
    FStack := FStack + [Frameless];
    try
      DrawFragment(Markup);
    finally
      Pop;
    end;
  finally
    Painted := FRaster;
    FRaster := Beneath;
  end;

  Coverage := TMarkdownRasterFilters.LuminanceMask(Painted);

  if Length(Parent) <> Length(Coverage) then
  begin
    Result := Coverage;
    Exit;
  end;

  
  SetLength(Combined, Length(Coverage));
  for Index := 0 to High(Combined) do
  begin
    Combined[Index] := Parent[Index] * Coverage[Index] div 255;
  end;

  Result := Combined;
end;

// Every element carrying an id is remembered whole, because a reference to it
// may appear before or after the definition itself.
procedure TNativeSvgRenderer.CollectMarkup(const Svg: string);
var
  Scanner: TSvgXmlScanner;
  Pending: TArray<string>;
  Starts: TArray<Integer>;
  Depths: TArray<Integer>;
  Depth: Integer;
  Element: TSvgXmlElement;
  Identifier: string;
begin
  Scanner := TSvgXmlScanner.Create(Svg);
  try
    Pending := nil;
    Starts := nil;
    Depths := nil;
    Depth := 0;

    
    while Scanner.ReadElement(Element) do
    begin
      if Element.IsClosing then
      begin
        Dec(Depth);

        while (Length(Depths) > 0) and (Depths[High(Depths)] > Depth) do
        begin
          FDefinitions.AddOrSetValue(Pending[High(Pending)],
            Copy(Svg, Starts[High(Starts)], Element.Stop - Starts[High(Starts)]));

          SetLength(Pending, Length(Pending) - 1);
          SetLength(Starts, Length(Starts) - 1);
          SetLength(Depths, Length(Depths) - 1);
        end;

        Continue;
      end;

      Inc(Depth);

      Identifier := Element.Attribute(IdAttribute);
      if Identifier <> '' then
      begin
        if Element.IsSelfClosing then
          FDefinitions.AddOrSetValue(Identifier, Copy(Svg, Element.Start, Element.Stop - Element.Start))
        else
        begin
          Pending := Pending + [Identifier];
          Starts := Starts + [Element.Start];
          Depths := Depths + [Depth];
        end;
      end;

      if Element.IsSelfClosing then
        Dec(Depth);
    end;
  finally
    Scanner.Free;
  end;
end;

// A filtered element is drawn on a layer of its own, so the filter has
// something to work on that holds nothing but that element.
procedure TNativeSvgRenderer.BeginLayer(const Filter: TSvgFilter);
begin
  FLayers := FLayers + [FRaster];
  FPendingFilters := FPendingFilters + [Filter];
  FLayerDepths := FLayerDepths + [FDepth];

  FRaster := TMarkdownPixelRaster.Create(FRaster.Width, FRaster.Height);
end;

procedure TNativeSvgRenderer.EndLayer;
var
  Filtered: TMarkdownPixelRaster;
  Beneath: TMarkdownPixelRaster;
begin
  if Length(FLayers) = 0 then
    Exit;

  Filtered := ApplyFilter(FPendingFilters[High(FPendingFilters)], FRaster);
  Beneath := FLayers[High(FLayers)];

  SetLength(FLayers, Length(FLayers) - 1);
  SetLength(FPendingFilters, Length(FPendingFilters) - 1);
  SetLength(FLayerDepths, Length(FLayerDepths) - 1);

  FRaster := TMarkdownRasterFilters.Over(Filtered, Beneath);
end;

// The shape of the source without its colours, which is what a drop shadow is
// built from.
class function TNativeSvgRenderer.SourceAlphaOf(const Source: TMarkdownPixelRaster): TMarkdownPixelRaster;
var
  Index: Integer;
begin
  Result := TMarkdownPixelRaster.Create(Source.Width, Source.Height);

  for Index := 0 to High(Result.Pixels) div 4 do
  begin
    Result.Pixels[Index * 4 + 3] := Source.Pixels[Index * 4 + 3];
  end;
end;

function TNativeSvgRenderer.ApplyFilter(const Filter: TSvgFilter;
  const Source: TMarkdownPixelRaster): TMarkdownPixelRaster;
var
  Named: TDictionary<string, TMarkdownPixelRaster>;
  Current: TMarkdownPixelRaster;
  Step: TSvgFilterStep;
  Input: TMarkdownPixelRaster;
  Second: TMarkdownPixelRaster;
  Merged: TMarkdownPixelRaster;
  Name: string;
  Layer: TMarkdownPixelRaster;
begin
  Result := Source;
  if Length(Filter) = 0 then
    Exit;

  Named := TDictionary<string, TMarkdownPixelRaster>.Create;
  try
    Named.AddOrSetValue('SourceGraphic', Source);
    Named.AddOrSetValue('SourceAlpha', SourceAlphaOf(Source));

    Current := Source;

    for Step in Filter do
    begin
      Input := Current;
      if (Step.Input <> '') and (not Named.TryGetValue(Step.Input, Input)) then
        Input := Current;

      case Step.Kind of
        TSvgFilterKind.Blur:
          Current := TMarkdownRasterFilters.Blurred(Input, Step.DeviationX, Step.DeviationY);
        TSvgFilterKind.Offset:
          Current := TMarkdownRasterFilters.Offset(Input, Round(Step.DeltaX), Round(Step.DeltaY));
        TSvgFilterKind.Flood:
          Current := TMarkdownRasterFilters.Flooded(Source.Width, Source.Height, Step.Color);
        TSvgFilterKind.Composite:
          begin
            Second := Source;
            if (Step.SecondInput <> '') and (not Named.TryGetValue(Step.SecondInput, Second)) then
              Second := Source;

            if SameText(Step.Operation, 'in') then
              Current := TMarkdownRasterFilters.InsideOf(Input, Second)
            else
              Current := TMarkdownRasterFilters.Over(Input, Second);
          end;
        TSvgFilterKind.Merge:
          begin
            Merged := TMarkdownPixelRaster.Create(Source.Width, Source.Height);
            for Name in Step.MergeInputs do
            begin
              Layer := Source;
              if Named.TryGetValue(Name, Layer) or (Name = '') then
                Merged := TMarkdownRasterFilters.Over(Layer, Merged);
            end;

            Current := Merged;
          end;
      else
        raise ENotSupportedException.CreateFmt('Unhandled filter kind: %d', [Ord(Step.Kind)]);
      end;

      if Step.ResultName <> '' then
        Named.AddOrSetValue(Step.ResultName, Current);
    end;

    Result := Current;
  finally
    Named.Free;
  end;
end;

// Definitions are read first, because a shape may point at a gradient, a clip
// path or a filter written further down the document.
type
  // A definition is spread over an opening element, its children and its
  // closing element, so each collector keeps the state of the one it is
  // reading and answers whether the element belonged to it.
  TSvgGradientCollector = class
  private
    FTarget: TDictionary<string, TSvgGradient>;
    FGradient: TSvgGradient;
    FId: string;
    procedure Start(const Element: TSvgXmlElement; const Name: string);
    procedure AddStop(const Element: TSvgXmlElement);
    procedure Finish;

  public
    constructor Create(const Target: TDictionary<string, TSvgGradient>);
    function TryCollect(const Element: TSvgXmlElement; const Name: string): Boolean;
  end;

  TSvgClipPathCollector = class
  private
    FTarget: TM4DGen1;
    FSubPaths: TArray<TSvgSubPath>;
    FId: string;
    procedure Finish;

  public
    constructor Create(const Target: TM4DGen1);
    function TryCollect(const Element: TSvgXmlElement; const Name: string): Boolean;
    procedure CollectShape(const Element: TSvgXmlElement);
  end;

  TSvgFilterCollector = class
  private
    FTarget: TDictionary<string, TSvgFilter>;
    FFilter: TSvgFilter;
    FId: string;
    FMergeInputs: TArray<string>;
    FInMerge: Boolean;
    function TryCollectClosing(const Name: string): Boolean;
    function ReadStep(const Element: TSvgXmlElement; const Name: string): TSvgFilterStep;
    procedure Finish;

  public
    constructor Create(const Target: TDictionary<string, TSvgFilter>);
    function TryCollect(const Element: TSvgXmlElement; const Name: string): Boolean;
  end;

constructor TSvgGradientCollector.Create(const Target: TDictionary<string, TSvgGradient>);
begin
  inherited Create;

  FTarget := Target;
end;

function TSvgGradientCollector.TryCollect(const Element: TSvgXmlElement; const Name: string): Boolean;
var
  IsGradient: Boolean;
begin
  IsGradient := (Name = LinearGradientElement) or (Name = 'radialgradient');

  if Element.IsClosing then
  begin
    Result := IsGradient;
    if Result then
      Finish;

    Exit;
  end;

  if IsGradient then
  begin
    Start(Element, Name);
    Result := True;
    Exit;
  end;

  Result := (Name = 'stop') and (FId <> '');
  if Result then
    AddStop(Element);
end;

procedure TSvgGradientCollector.Start(const Element: TSvgXmlElement; const Name: string);
var
  Value: Single;
begin
  FGradient := Default(TSvgGradient);
  FId := Element.Attribute(IdAttribute);
  FGradient.OnBoundingBox := not SameText(Element.Attribute('gradientUnits', ObjectBoundingBoxValue),
    UserSpaceOnUseValue);

  
  if Name = LinearGradientElement then
  begin
    FGradient.Kind := TMarkdownPaintKind.LinearGradient;
    FGradient.First := TLayoutPointF.Create(0, 0);
    FGradient.Second := TLayoutPointF.Create(1, 0);
    if TSvgValue.TryParseFraction(Element.Attribute(X1Attribute), Value) then
      FGradient.First.X := Value;
    if TSvgValue.TryParseFraction(Element.Attribute(Y1Attribute), Value) then
      FGradient.First.Y := Value;
    if TSvgValue.TryParseFraction(Element.Attribute(X2Attribute), Value) then
      FGradient.Second.X := Value;
    if TSvgValue.TryParseFraction(Element.Attribute(Y2Attribute), Value) then
      FGradient.Second.Y := Value;

    Exit;
  end;

  FGradient.Kind := TMarkdownPaintKind.RadialGradient;
  FGradient.First := TLayoutPointF.Create(0.5, 0.5);
  FGradient.Radius := 0.5;
  if TSvgValue.TryParseFraction(Element.Attribute(CentreXAttribute), Value) then
    FGradient.First.X := Value;
  if TSvgValue.TryParseFraction(Element.Attribute(CentreYAttribute), Value) then
    FGradient.First.Y := Value;
  if TSvgValue.TryParseFraction(Element.Attribute(RadiusAttribute), Value) then
    FGradient.Radius := Value;
end;

procedure TSvgGradientCollector.AddStop(const Element: TSvgXmlElement);
var
  Stop: TMarkdownGradientStop;
  Value: Single;
  Color: TLayoutColor;
  Alpha: Single;
begin
  Stop := Default(TMarkdownGradientStop);

  
  if TSvgValue.TryParseFraction(TSvgValue.PresentationValue(Element, 'offset'), Value) then
    Stop.Offset := EnsureRange(Value, 0, 1);

  Color := $FF000000;
  TSvgValue.TryParseColor(TSvgValue.PresentationValue(Element, 'stop-color'), Color);

  Alpha := 1;
  if TSvgValue.TryParseLength(TSvgValue.PresentationValue(Element, 'stop-opacity'), Alpha) then
    Color := TSvgValue.WithOpacity(Color, EnsureRange(Alpha, 0, 1));

  Stop.Color := Color;
  FGradient.Stops := FGradient.Stops + [Stop];
end;

procedure TSvgGradientCollector.Finish;
begin
  if (FId <> '') and (Length(FGradient.Stops) > 0) then
    FTarget.AddOrSetValue(FId, FGradient);

  FId := '';
end;

constructor TSvgClipPathCollector.Create(const Target: TM4DGen1);
begin
  inherited Create;

  FTarget := Target;
end;

function TSvgClipPathCollector.TryCollect(const Element: TSvgXmlElement; const Name: string): Boolean;
begin
  Result := Name = 'clippath';
  if not Result then
    Exit;

  if Element.IsClosing then
  begin
    Finish;
    Exit;
  end;

  FId := Element.Attribute(IdAttribute);
  FSubPaths := nil;
end;

// Every shape between the opening and closing element belongs to the path the
// clip is built from, whatever its name.
procedure TSvgClipPathCollector.CollectShape(const Element: TSvgXmlElement);
begin
  if Element.IsClosing or (FId = '') then
    Exit;

  FSubPaths := FSubPaths + TNativeSvgRenderer.SubPathsFor(Element);
end;

procedure TSvgClipPathCollector.Finish;
begin
  if (FId <> '') and (Length(FSubPaths) > 0) then
    FTarget.AddOrSetValue(FId, FSubPaths);

  FId := '';
  FSubPaths := nil;
end;

constructor TSvgFilterCollector.Create(const Target: TDictionary<string, TSvgFilter>);
begin
  inherited Create;

  FTarget := Target;
end;

function TSvgFilterCollector.TryCollect(const Element: TSvgXmlElement; const Name: string): Boolean;
begin
  if Element.IsClosing then
  begin
    Result := TryCollectClosing(Name);
    Exit;
  end;

  if Name = FilterElement then
  begin
    FId := Element.Attribute(IdAttribute);
    FFilter := nil;
    Result := True;
    Exit;
  end;

  if FId = '' then
  begin
    Result := False;
    Exit;
  end;

  if Name = 'femerge' then
  begin
    FInMerge := True;
    FMergeInputs := nil;
    Result := True;
    Exit;
  end;

  if (Name = 'femergenode') and FInMerge then
  begin
    FMergeInputs := FMergeInputs + [Element.Attribute(InputAttribute)];
    Result := True;
    Exit;
  end;

  FFilter := FFilter + [ReadStep(Element, Name)];
  Result := True;
end;

function TSvgFilterCollector.TryCollectClosing(const Name: string): Boolean;
var
  Step: TSvgFilterStep;
begin
  if Name = FilterElement then
  begin
    Finish;
    Result := True;
    Exit;
  end;

  Result := Name = 'femerge';
  if not Result then
    Exit;

  Step := Default(TSvgFilterStep);
  Step.Kind := TSvgFilterKind.Merge;
  Step.MergeInputs := FMergeInputs;

  FFilter := FFilter + [Step];
  FMergeInputs := nil;
  FInMerge := False;
end;

function TSvgFilterCollector.ReadStep(const Element: TSvgXmlElement; const Name: string): TSvgFilterStep;
var
  Value: Single;
  Deviations: TSvgNumberReader;
begin
  Result := Default(TSvgFilterStep);
  Result.Input := Element.Attribute(InputAttribute);
  Result.SecondInput := Element.Attribute('in2');
  Result.ResultName := Element.Attribute('result');

  

  if Name = 'fegaussianblur' then
  begin
    Result.Kind := TSvgFilterKind.Blur;

    Deviations := TSvgNumberReader.Create(Element.Attribute('stdDeviation', '0'));
    Result.DeviationX := Deviations.ReadNumber;
    if Deviations.TryReadNumber(Value) then
      Result.DeviationY := Value
    else
      Result.DeviationY := Result.DeviationX;

    Exit;
  end;

  if Name = 'feoffset' then
  begin
    Result.Kind := TSvgFilterKind.Offset;
    if TSvgValue.TryParseLength(Element.Attribute('dx', '0'), Value) then
      Result.DeltaX := Value;
    if TSvgValue.TryParseLength(Element.Attribute('dy', '0'), Value) then
      Result.DeltaY := Value;

    Exit;
  end;

  if Name = 'feflood' then
  begin
    Result.Kind := TSvgFilterKind.Flood;
    Result.Color := $FF000000;
    TSvgValue.TryParseColor(TSvgValue.PresentationValue(Element, 'flood-color'), Result.Color);
    if TSvgValue.TryParseLength(TSvgValue.PresentationValue(Element, 'flood-opacity'), Value) then
      Result.Color := TSvgValue.WithOpacity(Result.Color, EnsureRange(Value, 0, 1));

    Exit;
  end;

  if Name = 'fecomposite' then
  begin
    Result.Kind := TSvgFilterKind.Composite;
    Result.Operation := Element.Attribute('operator', 'over');

    Exit;
  end;

  // A primitive this engine has no answer for would quietly change the result,
  // so the whole document goes back rather than half a filter.
  raise ESvgUnsupported.Create(Name);
end;

procedure TSvgFilterCollector.Finish;
begin
  if (FId <> '') and (Length(FFilter) > 0) then
    FTarget.AddOrSetValue(FId, FFilter);

  FId := '';
  FFilter := nil;
end;

procedure TNativeSvgRenderer.CollectDefinitions(const Svg: string);
var
  Scanner: TSvgXmlScanner;
  Gradients: TSvgGradientCollector;
  ClipPaths: TSvgClipPathCollector;
  Filters: TSvgFilterCollector;
  Element: TSvgXmlElement;
  Name: type of (Element.Name.ToLowerInvariant);
begin
  Scanner := TSvgXmlScanner.Create(Svg);
  Gradients := TSvgGradientCollector.Create(FGradients);
  ClipPaths := TSvgClipPathCollector.Create(FClipPaths);
  Filters := TSvgFilterCollector.Create(FFilters);
  try
    
    while Scanner.ReadElement(Element) do
    begin
      Name := Element.Name.ToLowerInvariant;

      if Gradients.TryCollect(Element, Name) then
        Continue;

      if ClipPaths.TryCollect(Element, Name) then
        Continue;

      if Filters.TryCollect(Element, Name) then
        Continue;

      ClipPaths.CollectShape(Element);
    end;
  finally
    Filters.Free;
    ClipPaths.Free;
    Gradients.Free;
    Scanner.Free;
  end;
end;


function TNativeSvgRenderer.Render(const Svg: string; const MaxWidth, MaxHeight: Single): TMarkdownSvgRaster;
var
  Scanner: TSvgXmlScanner;
  Root: TSvgXmlElement;
  Found: Boolean;
  ViewWidth: Single;
  ViewHeight: Single;
  ViewLeft: Single;
  ViewTop: Single;
  ViewBox: string;
  Reader: TSvgNumberReader;
  DeclaredWidth: Single;
  DeclaredHeight: Single;
  TargetWidth: Single;
  TargetHeight: Single;
  Scale: Single;
  PixelWidth: Integer;
  PixelHeight: Integer;
  Base: TSvgMatrix;
  Start: TSvgFrame;
begin
  Result := Default(TMarkdownSvgRaster);

  Scanner := TSvgXmlScanner.Create(Svg);
  try
    
    Found := False;
    while Scanner.ReadElement(Root) do
    begin
      if (not Root.IsClosing) and SameText(Root.Name, SvgElement) then
      begin
        Found := True;
        Break;
      end;
    end;

    if not Found then
      raise ESvgUnsupported.Create('no svg element');

    ViewWidth := 0;
    ViewHeight := 0;
    ViewLeft := 0;
    ViewTop := 0;

    ViewBox := Root.Attribute('viewBox');
    if ViewBox <> '' then
    begin
      Reader := TSvgNumberReader.Create(ViewBox);
      ViewLeft := Reader.ReadNumber;
      ViewTop := Reader.ReadNumber;
      ViewWidth := Reader.ReadNumber;
      ViewHeight := Reader.ReadNumber;
    end;

    DeclaredWidth := 0;
    DeclaredHeight := 0;
    TSvgValue.TryParseLength(Root.Attribute(WidthAttribute), DeclaredWidth);
    TSvgValue.TryParseLength(Root.Attribute(HeightAttribute), DeclaredHeight);

    if (ViewWidth <= 0) or (ViewHeight <= 0) then
    begin
      ViewWidth := DeclaredWidth;
      ViewHeight := DeclaredHeight;
    end;

    if (ViewWidth <= 0) or (ViewHeight <= 0) then
      raise ESvgUnsupported.Create('no intrinsic size');

    TargetWidth := DeclaredWidth;
    TargetHeight := DeclaredHeight;
    if (TargetWidth <= 0) or (TargetHeight <= 0) then
    begin
      TargetWidth := ViewWidth;
      TargetHeight := ViewHeight;
    end;

    Scale := 1;
    if (MaxWidth > 0) and (TargetWidth * Scale > MaxWidth) then
      Scale := MaxWidth / TargetWidth;
    if (MaxHeight > 0) and (TargetHeight * Scale > MaxHeight) then
      Scale := MaxHeight / TargetHeight;

    PixelWidth := Max(1, Round(TargetWidth * Scale));
    PixelHeight := Max(1, Round(TargetHeight * Scale));

    FRaster := TMarkdownPixelRaster.Create(PixelWidth, PixelHeight);
    CollectDefinitions(Svg);
    CollectMarkup(Svg);

    // viewBox to device: shift the box to the origin, then scale it onto the
    // pixels asked for.
    Base := TSvgMatrix.Translation(-ViewLeft, -ViewTop)
      .Multiply(TSvgMatrix.Scaling(PixelWidth / ViewWidth, PixelHeight / ViewHeight));

    Start := Default(TSvgFrame);
    Start.Matrix := Base;
    Start.Style := TSvgStyle.Initial;
    FStack := [Start];
    FDepth := 0;

    Push(Root);
    if Root.IsSelfClosing then
      Exit;

    DrawFragment(Copy(Svg, Root.Stop, MaxInt));
    Result.Width := FRaster.Width;
    Result.Height := FRaster.Height;
    Result.Pixels := FRaster.Pixels;
  finally
    Scanner.Free;
  end;
end;

function TryRasterizeSvgNatively(const Svg: TBytes; const MaxWidth, MaxHeight: Single;
  out Raster: TMarkdownSvgRaster): Boolean;
var
  Text: type of (TEncoding.UTF8.GetString(Svg));
  Renderer: TNativeSvgRenderer;
begin
  Raster := Default(TMarkdownSvgRaster);

  try
    Text := TEncoding.UTF8.GetString(Svg);
    Renderer := TNativeSvgRenderer.Create;
    try
      Raster := Renderer.Render(Text, MaxWidth, MaxHeight);
      Result := (Raster.Width > 0) and (Raster.Height > 0);
    finally
      Renderer.Free;
    end;
  except
    // Anything this engine will not draw goes to the fallback whole, rather
    // than reaching the reader as half a drawing.
    on Exception do
      Result := False;
  end;
end;

procedure RegisterNativeSvgRasterizer;
begin
  TMarkdownSvgSupport.RegisterRasterizer(TryRasterizeSvgNatively);
end;

initialization
  RegisterNativeSvgRasterizer;

end.
