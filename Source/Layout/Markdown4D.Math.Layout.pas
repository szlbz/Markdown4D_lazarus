{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Math.Layout;

{$SCOPEDENUMS ON}

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  Generics.Collections,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Layout.BlockOverride,
  Markdown4D.Math.Syntax;

type
  TMathLayoutOptions = record
    // Family and size of the formula font. Bold and italic are decided per
    // symbol by the layouter, so the flags on this font are ignored.
    Font: TMarkdownFontStyle;
    TextColor: TLayoutColor;
    // Unknown commands are drawn by name in this colour so the author sees
    // what did not resolve.
    ErrorColor: TLayoutColor;
    // Display style sets fractions and limits at full size with the limits
    // above and below; text style is the compact form for inline formulas.
    IsDisplay: Boolean;
    class function Create(const Font: TMarkdownFontStyle; const TextColor, ErrorColor: TLayoutColor;
      const IsDisplay: Boolean): TMathLayoutOptions; static;
  end;

  // A laid-out formula: its extent around the baseline, and the ability to
  // draw itself at any position. Every measure is in the units of the
  // measurer, which is pixels for the viewers.
  IMathLayout = interface
    ['{7C3D1A58-9E24-4B6F-8A07-2F5B6D9C1E43}']
    function GetWidth: Single;
    function GetAscent: Single;
    function GetDescent: Single;
    procedure Draw(const Canvas: IExtensionCanvas; const Left, Baseline: Single);
    property Width: Single read GetWidth;
    property Ascent: Single read GetAscent;
    property Descent: Single read GetDescent;
  end;

  TMathLayouter = class
  public
    class function Layout(const Source: string; const Options: TMathLayoutOptions;
      const Measurer: ITextMeasurer): IMathLayout;
    class function LayoutNode(const Node: IMathNode; const Options: TMathLayoutOptions;
      const Measurer: ITextMeasurer): IMathLayout;
  end;

implementation

uses
  Math,
  character;

type
  TMathStyle = (Display, Text, Script, ScriptScript);

  TMathBoxKind = (Group, Glyph, Rule, Polygon);

  TMathBox = class;

  TMathPlacement = record
    Box: TMathBox;
    Handle: IMathLayout;
    DX: Single;
    DY: Single;
  end;

  // The box model of the layout: a glyph, a filled rule, a filled polygon,
  // or a group placing other boxes relative to its own origin. The origin of
  // every box is its left edge on the baseline; y grows downward, so the
  // ascent lies above at negative y.
  TMathBox = class(TInterfacedObject, IMathLayout)
  private
    FKind: TMathBoxKind;
    FWidth: Single;
    FAscent: Single;
    FDescent: Single;
    FText: string;
    FFont: TMarkdownFontStyle;
    FColor: TLayoutColor;
    FFontBaseline: Single;
    FRule: TLayoutRectF;
    FPoints: TArray<TLayoutPointF>;
    FChildren: TList<TMathPlacement>;
    FUrl: string;
    procedure DrawGroup(const Canvas: IExtensionCanvas; const Left, Baseline: Single);
    procedure DrawChildren(const Canvas: IExtensionCanvas; const Left, Baseline: Single);
    procedure DrawPolygon(const Canvas: IExtensionCanvas; const Left, Baseline: Single);

  public
    constructor Create(const Kind: TMathBoxKind);
    destructor Destroy; override;
    function GetWidth: Single;
    function GetAscent: Single;
    function GetDescent: Single;
    procedure Draw(const Canvas: IExtensionCanvas; const Left, Baseline: Single);
    procedure Place(const Child: TMathBox; const DX, DY: Single);
    // Grows the group so the placed child fits; the group's extent is never
    // smaller than its parts.
    procedure Enclose(const Child: TMathBox; const DX, DY: Single);
    property Width: Single read FWidth write FWidth;
    property Ascent: Single read FAscent write FAscent;
    property Descent: Single read FDescent write FDescent;
    property Text: string read FText write FText;
    property Font: TMarkdownFontStyle read FFont write FFont;
    property Color: TLayoutColor read FColor write FColor;
    property FontBaseline: Single read FFontBaseline write FFontBaseline;
    property Rule: TLayoutRectF read FRule write FRule;
    property Points: TArray<TLayoutPointF> read FPoints write FPoints;
    // Group: the URL its children link to, empty for none.
    property Url: string read FUrl write FUrl;
  end;

  TGlyphExtent = record
    AscentEm: Single;
    DescentEm: Single;
    class function Create(const AscentEm, DescentEm: Single): TGlyphExtent; static;
  end;

  TMathGlyphMapper = class
  private
    class function MapLetter(const Letter: Char; const UpperBase, LowerBase: Integer): Integer; static;
    class function MapDigit(const Digit: Char; const DigitBase: Integer): Integer; static;
    class function DoubleStruck(const Value: Char): Integer; static;
    class function ScriptLetter(const Value: Char): Integer; static;
    class function Fraktur(const Value: Char): Integer; static;
    class function SansSerif(const Value: Char): Integer; static;
    class function Monospace(const Value: Char): Integer; static;

  public
    // Letters and digits move to the Unicode mathematical alphanumeric block
    // of the variant; everything else stays. Bold and italic are font
    // attributes, so they pass through untouched.
    class function Apply(const Text: string; const Variant: TMathFontVariant): string;
  end;

  TMathBoxBuilder = class
  private
    const
      EmSpace = #$2003;
      MaximumDeviceScale = 4;
      ScriptScale = 0.7;
      ScriptScriptScale = 0.5;
      LargeOperatorScale = 1.4;
      AxisHeightEm = 0.25;
      XHeightEm = 0.45;
      RuleThicknessEm = 0.06;
      SuperscriptShiftUpEm = 0.36;
      SuperscriptBottomMinEm = 0.11;
      SubscriptShiftDownEm = 0.2;
      SubscriptTopMaxEm = 0.36;
      SubSuperscriptGapMinEm = 0.2;
      ScriptSpaceEm = 0.05;
      FractionGapDisplayEm = 0.18;
      FractionGapTextEm = 0.06;
      FractionNumeratorShiftDisplayEm = 0.68;
      FractionNumeratorShiftTextEm = 0.44;
      FractionDenominatorShiftDisplayEm = 0.69;
      FractionDenominatorShiftTextEm = 0.34;
      FractionPaddingEm = 0.1;
      RadicalGapDisplayEm = 0.2;
      RadicalGapTextEm = 0.1;
      RadicalExtraAscenderEm = 0.06;
      RadicalSignWidthEm = 0.55;
      RadicalIndexRaiseEm = 0.55;
      RadicalStrokeEm = 0.05;
      LimitGapEm = 0.12;
      AccentGapEm = 0.05;
      AccentGlyphBottomEm = 0.55;
      AccentGlyphTopEm = 0.75;
      ArrowAccentScale = 0.6;
      ArrowAccentBottomEm = 0.02;
      ArrowAccentTopEm = 0.3;
      OverlineGapEm = 0.12;
      DelimiterWidthEm = 0.45;
      DelimiterStrokeEm = 0.075;
      DelimiterGlyphHeightEm = 1.05;
      NullDelimiterSpaceEm = 0.12;
      MatrixRowGapEm = 0.5;
      MatrixColumnGapEm = 0.9;
      // An array row is at least as tall as LaTeX's strut, with some room
      // above and below, so rules between rows keep clear of the text; its
      // columns have half the matrix gap on either side, where the vertical
      // rules run.
      ArrayStrutAscentEm = 0.84;
      ArrayStrutDescentEm = 0.36;
      ArrayRowPaddingEm = 0.2;
      ArrayColumnPaddingEm = 0.5;
      ArrayDoubleRuleGapEm = 0.12;
      ParenthesisSegments = 12;
      MuPerEm = 18;
      ArrowGlyph = #$2192;
      DoubleBarGlyph = #$2016;
      LeftAngleGlyph = #$27E8;
      RightAngleGlyph = #$27E9;
      LeftFloorGlyph = #$230A;
      RightFloorGlyph = #$230B;
      LeftCeilingGlyph = #$2308;
      RightCeilingGlyph = #$2309;
      IntegralGlyph = #$222B;
      // TeX's inter-atom spacing, in mu, indexed by the class on the left and
      // on the right. The second table marks the entries that vanish in
      // script styles.
      SpacingMu: array[TMathAtomClass, TMathAtomClass] of Integer = (
        (0, 3, 4, 5, 0, 0, 0, 3),
        (3, 3, 0, 5, 0, 0, 0, 3),
        (4, 4, 0, 0, 4, 0, 0, 4),
        (5, 5, 0, 0, 5, 0, 0, 5),
        (0, 0, 0, 0, 0, 0, 0, 0),
        (0, 3, 4, 5, 0, 0, 0, 3),
        (3, 3, 0, 3, 3, 3, 3, 3),
        (3, 3, 4, 5, 3, 0, 3, 3));
      SpacingTextOnly: array[TMathAtomClass, TMathAtomClass] of Boolean = (
        (False, False, True, True, False, False, False, True),
        (False, False, False, True, False, False, False, True),
        (True, True, False, False, True, False, False, True),
        (True, True, False, False, True, False, False, True),
        (False, False, False, False, False, False, False, False),
        (False, False, True, True, False, False, False, True),
        (True, True, False, True, True, True, True, True),
        (True, False, True, True, True, False, True, True));
    var
      FMeasurer: ITextMeasurer;
      FOptions: TMathLayoutOptions;
      FDeviceScale: Single;
    class function DeviceScaleOf(const Font: TMarkdownFontStyle; const Measurer: ITextMeasurer): Single; static;
    function Build(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildColored(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildLinked(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildRow(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildSymbol(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildText(const Node: IMathNode; const Style: TMathStyle): TMathBox;
    function BuildSpace(const Node: IMathNode; const Style: TMathStyle): TMathBox;
    function BuildFraction(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildScript(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildLimits(const Base: TMathBox; const Node: IMathNode; const Style: TMathStyle;
      const Variant: TMathFontVariant): TMathBox;
    function BuildRadical(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildDelimited(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildAccent(const Node: IMathNode; const Style: TMathStyle; const Variant: TMathFontVariant): TMathBox;
    function BuildMatrix(const Node: IMathNode; const Style, CellStyle: TMathStyle;
      const Variant: TMathFontVariant): TMathBox;
    function BuildArray(const Node: IMathNode; const Style, CellStyle: TMathStyle;
      const Variant: TMathFontVariant): TMathBox;
    function VerticalRuleBox(const Top, Bottom, Thickness: Single): TMathBox;
    class function RuleSpan(const Count: Integer; const Thickness, Gap: Single): Single; static;
    class function ColumnInset(const Alignment: TMathColumnAlignment; const ColumnIndex: Integer;
      const Slack: Single): Single; static;
    function WrapWithDelimiters(const Body: TMathBox; const Left, Right: string; const Style: TMathStyle): TMathBox;
    function BuildDelimiter(const Delimiter: string; const RequiredAscent, RequiredDescent: Single;
      const Style: TMathStyle): TMathBox;
    function BuildStretchedDelimiter(const Delimiter: string; const Ascent, Descent: Single;
      const Style: TMathStyle): TMathBox;
    procedure AddParenthesis(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single;
      const OpensLeft: Boolean);
    procedure AddBracket(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single;
      const OpensLeft: Boolean);
    procedure AddBrace(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single; const OpensLeft: Boolean);
    procedure AddBar(const Group: TMathBox; const Ascent, Descent, X, Stroke: Single);
    procedure AddAngle(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single; const OpensLeft: Boolean);
    procedure AddFloorOrCeiling(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single;
      const OpensLeft, TickAtTop: Boolean);
    procedure AddPolyline(const Group: TMathBox; const Points: TArray<TLayoutPointF>; const Stroke: Single);
    function GlyphBox(const Text: string; const Font: TMarkdownFontStyle; const Color: TLayoutColor;
      const Extent: TGlyphExtent): TMathBox;
    function RuleBox(const Width, Thickness: Single): TMathBox;
    function SegmentBox(const StartPoint, EndPoint: TLayoutPointF; const Thickness: Single): TMathBox;
    class function EmptyBox: TMathBox; static;
    function FontFor(const Style: TMathStyle; const Variant: TMathFontVariant): TMarkdownFontStyle;
    function EmSize(const Style: TMathStyle): Single;
    class function SubStyle(const Style: TMathStyle): TMathStyle; static;
    class function FractionStyle(const Style: TMathStyle): TMathStyle; static;
    class function IsScriptStyle(const Style: TMathStyle): Boolean; static;
    class function ResolveVariant(const Own, Context: TMathFontVariant): TMathFontVariant; static;
    class function GlyphExtent(const Text: string): TGlyphExtent; static;
    class function RuleThicknessOf(const Em: Single): Single; static;
    class function CellStyleOf(const Node: IMathNode; const Style: TMathStyle): TMathStyle; static;
    class function CharacterExtent(const First: Char): TGlyphExtent; static;
    class function AtomClassOf(const Node: IMathNode): TMathAtomClass; static;
    class function ResolveAtomClasses(const Node: IMathNode): TArray<TMathAtomClass>; static;
    function SpacingBetween(const Left, Right: TMathAtomClass; const Style: TMathStyle): Single;
    class function IsLargeOperator(const Node: IMathNode): Boolean; static;

  public
    constructor Create(const Options: TMathLayoutOptions; const Measurer: ITextMeasurer);
    function BuildRoot(const Node: IMathNode): TMathBox;
  end;
  TM4DGen1 = TArray<TArray<TMathBox>>;

class function TMathLayoutOptions.Create(const Font: TMarkdownFontStyle; const TextColor, ErrorColor: TLayoutColor;
  const IsDisplay: Boolean): TMathLayoutOptions;
begin
  Result.Font := Font;
  Result.TextColor := TextColor;
  Result.ErrorColor := ErrorColor;
  Result.IsDisplay := IsDisplay;
end;

class function TGlyphExtent.Create(const AscentEm, DescentEm: Single): TGlyphExtent;
begin
  Result.AscentEm := AscentEm;
  Result.DescentEm := DescentEm;
end;

class function TMathLayouter.Layout(const Source: string; const Options: TMathLayoutOptions;
  const Measurer: ITextMeasurer): IMathLayout;
begin
  Result := LayoutNode(TMathParser.Parse(Source), Options, Measurer);
end;

class function TMathLayouter.LayoutNode(const Node: IMathNode; const Options: TMathLayoutOptions;
  const Measurer: ITextMeasurer): IMathLayout;
var
  Builder: TMathBoxBuilder;
begin
  Builder := TMathBoxBuilder.Create(Options, Measurer);
  try
    Result := Builder.BuildRoot(Node);
  finally
    Builder.Free;
  end;
end;

constructor TMathBox.Create(const Kind: TMathBoxKind);
begin
  inherited Create;

  FKind := Kind;
  FChildren := TList<TMathPlacement>.Create;
end;

destructor TMathBox.Destroy;
begin
  FChildren.Free;

  inherited Destroy;
end;

function TMathBox.GetWidth: Single;
begin
  Result := FWidth;
end;

function TMathBox.GetAscent: Single;
begin
  Result := FAscent;
end;

function TMathBox.GetDescent: Single;
begin
  Result := FDescent;
end;

procedure TMathBox.Place(const Child: TMathBox; const DX, DY: Single);
var
  Placement: TMathPlacement;
begin
  
  Placement.Box := Child;
  Placement.Handle := Child;
  Placement.DX := DX;
  Placement.DY := DY;

  FChildren.Add(Placement);
end;

procedure TMathBox.Enclose(const Child: TMathBox; const DX, DY: Single);
begin
  Place(Child, DX, DY);

  FWidth := Max(FWidth, DX + Child.Width);
  FAscent := Max(FAscent, Child.Ascent - DY);
  FDescent := Max(FDescent, Child.Descent + DY);
end;

procedure TMathBox.Draw(const Canvas: IExtensionCanvas; const Left, Baseline: Single);
begin
  case FKind of
    TMathBoxKind.Group:
      DrawGroup(Canvas, Left, Baseline);
    TMathBoxKind.Glyph:
      Canvas.DrawText(TLayoutPointF.Create(Left, Baseline - FFontBaseline), FText, FFont, FColor);
    TMathBoxKind.Rule:
      Canvas.FillRectangle(TLayoutRectF.Create(Left + FRule.Left, Baseline + FRule.Top, Left + FRule.Right,
        Baseline + FRule.Bottom), FColor);
    TMathBoxKind.Polygon:
      DrawPolygon(Canvas, Left, Baseline);
  else
    raise EMathSyntaxError.CreateFmt('Unhandled math box kind: %d', [Ord(FKind)]);
  end;
end;

// A canvas that cannot attribute drawing to a link still draws the linked
// part, as plain content.
procedure TMathBox.DrawGroup(const Canvas: IExtensionCanvas; const Left, Baseline: Single);
var
  LinkCanvas: IExtensionLinkCanvas;
  IsLinked: Boolean;
begin
  
  IsLinked := ((FUrl <> '') and Supports(Canvas, IExtensionLinkCanvas, LinkCanvas));
  if not IsLinked then
  begin
    DrawChildren(Canvas, Left, Baseline);
    Exit;
  end;

  LinkCanvas.BeginLink(FUrl);
  try
    DrawChildren(Canvas, Left, Baseline);
  finally
    LinkCanvas.EndLink;
  end;
end;

procedure TMathBox.DrawChildren(const Canvas: IExtensionCanvas; const Left, Baseline: Single);
var
  Placement: TMathPlacement;
begin
  for Placement in FChildren do
  begin
    Placement.Box.Draw(Canvas, Left + Placement.DX, Baseline + Placement.DY);
  end;
end;

procedure TMathBox.DrawPolygon(const Canvas: IExtensionCanvas; const Left, Baseline: Single);
var
  Moved: TArray<TLayoutPointF>;
  Index: Integer;
begin
  
  SetLength(Moved, System.Length(FPoints));

  for Index := 0 to High(FPoints) do
  begin
    Moved[Index] := TLayoutPointF.Create(Left + FPoints[Index].X, Baseline + FPoints[Index].Y);
  end;

  Canvas.FillPolygon(Moved, FColor);
end;

class function TMathGlyphMapper.Apply(const Text: string; const Variant: TMathFontVariant): string;
var
  NeedsMapping: Boolean;
  Builder: TStringBuilder;
  Value: Char;
  CodePoint: Integer;
begin
  NeedsMapping := (Variant = TMathFontVariant.DoubleStruck) or (Variant = TMathFontVariant.Script) or
    (Variant = TMathFontVariant.Fraktur) or (Variant = TMathFontVariant.SansSerif) or
    (Variant = TMathFontVariant.Monospace);
  if not NeedsMapping then
  begin
    Result := Text;
    Exit;
  end;

  Builder := TStringBuilder.Create;
  try
    for Value in Text do
    begin
      

      case Variant of
        TMathFontVariant.DoubleStruck:
          CodePoint := DoubleStruck(Value);
        TMathFontVariant.Script:
          CodePoint := ScriptLetter(Value);
        TMathFontVariant.Fraktur:
          CodePoint := Fraktur(Value);
        TMathFontVariant.SansSerif:
          CodePoint := SansSerif(Value);
        TMathFontVariant.Monospace:
          CodePoint := Monospace(Value);
      else
        CodePoint := 0;
      end;

      if CodePoint = 0 then
        Builder.Append(Value)
      else
        Builder.Append(Char.ConvertFromUtf32(CodePoint));
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TMathGlyphMapper.MapLetter(const Letter: Char; const UpperBase, LowerBase: Integer): Integer;
begin
  if CharInSet(Letter, ['A'..'Z']) then
  begin
    Result := UpperBase + Ord(Letter) - Ord('A');
    Exit;
  end;

  if CharInSet(Letter, ['a'..'z']) then
  begin
    Result := LowerBase + Ord(Letter) - Ord('a');
    Exit;
  end;

  Result := 0;
end;

class function TMathGlyphMapper.MapDigit(const Digit: Char; const DigitBase: Integer): Integer;
begin
  if CharInSet(Digit, ['0'..'9']) then
  begin
    Result := DigitBase + Ord(Digit) - Ord('0');
    Exit;
  end;

  Result := 0;
end;

class function TMathGlyphMapper.DoubleStruck(const Value: Char): Integer;
begin
  case Value of
    'C': Result := $2102;
    'H': Result := $210D;
    'N': Result := $2115;
    'P': Result := $2119;
    'Q': Result := $211A;
    'R': Result := $211D;
    'Z': Result := $2124;
  else
    Result := MapLetter(Value, $1D538, $1D552);
    if Result = 0 then
      Result := MapDigit(Value, $1D7D8);
  end;
end;

class function TMathGlyphMapper.ScriptLetter(const Value: Char): Integer;
begin
  case Value of
    'B': Result := $212C;
    'E': Result := $2130;
    'F': Result := $2131;
    'H': Result := $210B;
    'I': Result := $2110;
    'L': Result := $2112;
    'M': Result := $2133;
    'R': Result := $211B;
    'e': Result := $212F;
    'g': Result := $210A;
    'o': Result := $2134;
  else
    Result := MapLetter(Value, $1D49C, $1D4B6);
  end;
end;

class function TMathGlyphMapper.Fraktur(const Value: Char): Integer;
begin
  case Value of
    'C': Result := $212D;
    'H': Result := $210C;
    'I': Result := $2111;
    'R': Result := $211C;
    'Z': Result := $2128;
  else
    Result := MapLetter(Value, $1D504, $1D51E);
  end;
end;

class function TMathGlyphMapper.SansSerif(const Value: Char): Integer;
begin
  Result := MapLetter(Value, $1D5A0, $1D5BA);
  if Result = 0 then
    Result := MapDigit(Value, $1D7E2);
end;

class function TMathGlyphMapper.Monospace(const Value: Char): Integer;
begin
  Result := MapLetter(Value, $1D670, $1D68A);
  if Result = 0 then
    Result := MapDigit(Value, $1D7F6);
end;

constructor TMathBoxBuilder.Create(const Options: TMathLayoutOptions; const Measurer: ITextMeasurer);
begin
  inherited Create;

  FOptions := Options;
  FMeasurer := Measurer;
  FDeviceScale := DeviceScaleOf(Options.Font, Measurer);
end;

// The measurer may set text larger than the size it is given, as the VCL
// viewer does on a display scaled to 125 % or more: widths then come back in
// device pixels while the size stays at 96 dpi. An em space is one em wide by
// definition, so its width tells how large an em really is, and every height
// and gap the builder derives from the size is scaled to match the glyphs.
class function TMathBoxBuilder.DeviceScaleOf(const Font: TMarkdownFontStyle; const Measurer: ITextMeasurer): Single;
var
  Ratio: Double;
  IsScaled: Boolean;
begin
  Result := 1;
  if Font.Size <= 0 then
    Exit;

  Ratio := Measurer.MeasureText(EmSpace, Font).Width / Font.Size;
  IsScaled := (Ratio > 1) and (Ratio <= MaximumDeviceScale);
  if IsScaled then
    Result := Ratio;
end;

function TMathBoxBuilder.BuildRoot(const Node: IMathNode): TMathBox;
var
  Style: TMathStyle;
  IsLineColumn: Boolean;
begin
  Style := TMathStyle.Text;
  if FOptions.IsDisplay then
    Style := TMathStyle.Display;

  // A column of lines at the root keeps the display style per line; a matrix
  // inside a formula sets its cells in text style, as TeX does.
  IsLineColumn := (Node.Kind = TMathNodeKind.Matrix) and (Node.LeftDelimiter = '') and
    (Node.RightDelimiter = '');
  if IsLineColumn then
  begin
    Result := BuildMatrix(Node, Style, Style, TMathFontVariant.Italic);
    Exit;
  end;

  Result := Build(Node, Style, TMathFontVariant.Italic);
end;

function TMathBoxBuilder.Build(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
begin
  case Node.Kind of
    TMathNodeKind.Row:
      Result := BuildRow(Node, Style, Variant);
    TMathNodeKind.Symbol:
      Result := BuildSymbol(Node, Style, Variant);
    TMathNodeKind.Text:
      Result := BuildText(Node, Style);
    TMathNodeKind.Space:
      Result := BuildSpace(Node, Style);
    TMathNodeKind.Fraction:
      Result := BuildFraction(Node, Style, Variant);
    TMathNodeKind.Script:
      Result := BuildScript(Node, Style, Variant);
    TMathNodeKind.Radical:
      Result := BuildRadical(Node, Style, Variant);
    TMathNodeKind.Delimited:
      Result := BuildDelimited(Node, Style, Variant);
    TMathNodeKind.Accent:
      Result := BuildAccent(Node, Style, Variant);
    TMathNodeKind.Matrix:
      Result := BuildMatrix(Node, Style, CellStyleOf(Node, Style), Variant);
    TMathNodeKind.Styled:
      Result := Build(Node.Children[0], Style, Node.Variant);
    TMathNodeKind.Colored:
      Result := BuildColored(Node, Style, Variant);
    TMathNodeKind.Linked:
      Result := BuildLinked(Node, Style, Variant);
  else
    raise EMathSyntaxError.CreateFmt('Unhandled math node kind: %d', [Ord(Node.Kind)]);
  end;
end;

// Every box reads the text colour from the options as it is built, so the
// body picks up the colour for as long as it is being built.
function TMathBoxBuilder.BuildColored(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  PreviousColor: TLayoutColor;
begin
  PreviousColor := FOptions.TextColor;
  FOptions.TextColor := Node.Color;
  try
    Result := Build(Node.Children[0], Style, Variant);
  finally
    FOptions.TextColor := PreviousColor;
  end;
end;

function TMathBoxBuilder.BuildLinked(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  Body: type of (Build(Node.Children[0], Style, Variant));
begin
  Body := Build(Node.Children[0], Style, Variant);

  Result := TMathBox.Create(TMathBoxKind.Group);
  Result.Url := Node.Text;
  Result.Enclose(Body, 0, 0);
end;

// Atoms sit side by side with TeX's inter-atom spacing between them. Spaces
// are transparent: they add their width and leave the spacing between the
// atoms around them alone.
function TMathBoxBuilder.BuildRow(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  Classes: TArray<TMathAtomClass>;
  Cursor: Single;
  HasPrevious: Boolean;
  PreviousClass: TMathAtomClass;
  Index: Integer;
  Child: IMathNode;
  Box: type of (Build(Child, Style, Variant));
  IsSpace: Boolean;
begin
  Result := TMathBox.Create(TMathBoxKind.Group);

  Classes := ResolveAtomClasses(Node);
  Cursor := 0;
  HasPrevious := False;
  PreviousClass := TMathAtomClass.Ordinary;

  for Index := 0 to Node.ChildCount - 1 do
  begin
    Child := Node.Children[Index];
    Box := Build(Child, Style, Variant);

    IsSpace := (Child.Kind = TMathNodeKind.Space);
    if IsSpace then
    begin
      Result.Enclose(Box, Cursor, 0);
      Cursor := Cursor + Box.Width;
      Continue;
    end;

    if HasPrevious then
      Cursor := Cursor + SpacingBetween(PreviousClass, Classes[Index], Style);

    Result.Enclose(Box, Cursor, 0);
    Cursor := Cursor + Box.Width;
    PreviousClass := Classes[Index];
    HasPrevious := True;
  end;

  Result.Width := Cursor;
end;

// A binary operator with nothing to bind on one side is an ordinary symbol:
// the minus in "-x" or after an equals sign gets no operator spacing.
class function TMathBoxBuilder.ResolveAtomClasses(const Node: IMathNode): TArray<TMathAtomClass>;
var
  Index: Integer;
  PreviousClass: TMathAtomClass;
  IsSpace: Boolean;
  NextClass: TMathAtomClass;
  Ahead: Integer;
  AheadIsSpace: Boolean;
  LacksLeftOperand: Boolean;
  LacksRightOperand: Boolean;
begin
  SetLength(Result, Node.ChildCount);

  for Index := 0 to Node.ChildCount - 1 do
  begin
    Result[Index] := AtomClassOf(Node.Children[Index]);
  end;

  PreviousClass := TMathAtomClass.Opening;

  for Index := 0 to Node.ChildCount - 1 do
  begin
    IsSpace := (Node.Children[Index].Kind = TMathNodeKind.Space);
    if IsSpace then
      Continue;

    if Result[Index] = TMathAtomClass.Binary then
    begin
      NextClass := TMathAtomClass.Closing;
      for Ahead := Index + 1 to Node.ChildCount - 1 do
      begin
        AheadIsSpace := (Node.Children[Ahead].Kind = TMathNodeKind.Space);
        if not AheadIsSpace then
        begin
          NextClass := Result[Ahead];
          Break;
        end;
      end;

      LacksLeftOperand := (PreviousClass = TMathAtomClass.Binary) or (PreviousClass = TMathAtomClass.Operator) or
        (PreviousClass = TMathAtomClass.Relation) or (PreviousClass = TMathAtomClass.Opening) or
        (PreviousClass = TMathAtomClass.Punctuation);
      LacksRightOperand := (NextClass = TMathAtomClass.Relation) or (NextClass = TMathAtomClass.Closing) or
        (NextClass = TMathAtomClass.Punctuation);
      if LacksLeftOperand or LacksRightOperand then
        Result[Index] := TMathAtomClass.Ordinary;
    end;

    PreviousClass := Result[Index];
  end;
end;

class function TMathBoxBuilder.AtomClassOf(const Node: IMathNode): TMathAtomClass;
var
  IsSingleton: Boolean;
begin
  case Node.Kind of
    TMathNodeKind.Symbol, TMathNodeKind.Script, TMathNodeKind.Fraction, TMathNodeKind.Delimited,
    TMathNodeKind.Matrix:
      Result := Node.AtomClass;
    TMathNodeKind.Row:
      begin
        // A group of one atom keeps that atom's class, so {x} + {y} spaces
        // like x + y; a longer group is an ordinary atom, as in TeX.
        IsSingleton := (Node.ChildCount = 1);
        if IsSingleton then
          Result := AtomClassOf(Node.Children[0])
        else
          Result := TMathAtomClass.Ordinary;
      end;
    TMathNodeKind.Colored, TMathNodeKind.Linked:
      Result := AtomClassOf(Node.Children[0]);
  else
    Result := TMathAtomClass.Ordinary;
  end;
end;

function TMathBoxBuilder.SpacingBetween(const Left, Right: TMathAtomClass; const Style: TMathStyle): Single;
var
  VanishesHere: Boolean;
begin
  VanishesHere := SpacingTextOnly[Left, Right] and IsScriptStyle(Style);
  if VanishesHere then
  begin
    Result := 0;
    Exit;
  end;

  Result := SpacingMu[Left, Right] * EmSize(Style) / MuPerEm;
end;

function TMathBoxBuilder.BuildSymbol(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  Effective: TMathFontVariant;
  Font: TMarkdownFontStyle;
  Text: string;
  Color: TLayoutColor;
  Extent: TGlyphExtent;
  DrawsLarge: Boolean;
  Glyph: TMathBox;
  GlyphCentre: Double;
  Shift: Double;
begin
  Effective := ResolveVariant(Node.Variant, Variant);
  Font := FontFor(Style, Effective);
  Text := TMathGlyphMapper.Apply(Node.Text, Effective);

  Color := FOptions.TextColor;
  if Node.IsError then
    Color := FOptions.ErrorColor;

  Extent := GlyphExtent(Node.Text);

  DrawsLarge := IsLargeOperator(Node) and (Style = TMathStyle.Display);
  if not DrawsLarge then
  begin
    Result := GlyphBox(Text, Font, Color, Extent);
    Exit;
  end;

  // A large operator in display style grows and centres on the math axis,
  // so a sum sits level with the fraction bars around it.
  Font.Size := Font.Size * LargeOperatorScale;
  Extent.AscentEm := Extent.AscentEm * LargeOperatorScale;
  Extent.DescentEm := Extent.DescentEm * LargeOperatorScale;

  Glyph := GlyphBox(Text, Font, Color, Extent);
  GlyphCentre := (Glyph.Ascent - Glyph.Descent) / 2;
  Shift := GlyphCentre - AxisHeightEm * EmSize(Style);

  Result := TMathBox.Create(TMathBoxKind.Group);
  Result.Enclose(Glyph, 0, Shift);
end;

class function TMathBoxBuilder.IsLargeOperator(const Node: IMathNode): Boolean;
begin
  Result := (Node.Kind = TMathNodeKind.Symbol) and Node.IsLarge;
end;

function TMathBoxBuilder.BuildText(const Node: IMathNode; const Style: TMathStyle): TMathBox;
var
  Font: TMarkdownFontStyle;
  Text: string;
  Extent: TGlyphExtent;
begin
  Font := FontFor(Style, Node.Variant);
  Text := TMathGlyphMapper.Apply(Node.Text, Node.Variant);
  Extent := GlyphExtent(Node.Text);

  Result := GlyphBox(Text, Font, FOptions.TextColor, Extent);
end;

function TMathBoxBuilder.BuildSpace(const Node: IMathNode; const Style: TMathStyle): TMathBox;
begin
  Result := EmptyBox;
  Result.Width := Node.SpaceWidth * EmSize(Style);
end;

function TMathBoxBuilder.BuildFraction(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  PartStyle: TMathStyle;
  Numerator: type of (Build(Node.Children[0], PartStyle, Variant));
  Denominator: type of (Build(Node.Children[1], PartStyle, Variant));
  Em: Single;
  Axis: Double;
  IsDisplayStyle: Boolean;
  Thickness: Single;
  Gap: Double;
  NumeratorShift: Double;
  DenominatorShift: Double;
  NumeratorBaseline: Double;
  DenominatorBaseline: Double;
  Padding: Double;
  InnerWidth: Single;
  Bar: TMathBox;
begin
  PartStyle := FractionStyle(Style);
  Numerator := Build(Node.Children[0], PartStyle, Variant);
  Denominator := Build(Node.Children[1], PartStyle, Variant);

  Em := EmSize(Style);
  Axis := AxisHeightEm * Em;
  IsDisplayStyle := (Style = TMathStyle.Display);

  Thickness := RuleThicknessOf(Em);
  Gap := FractionGapTextEm * Em;
  NumeratorShift := FractionNumeratorShiftTextEm * Em;
  DenominatorShift := FractionDenominatorShiftTextEm * Em;
  if IsDisplayStyle then
  begin
    Gap := FractionGapDisplayEm * Em;
    NumeratorShift := FractionNumeratorShiftDisplayEm * Em;
    DenominatorShift := FractionDenominatorShiftDisplayEm * Em;
  end;

  if not Node.HasRule then
  begin
    Gap := Gap + Thickness;
    Thickness := 0;
  end;

  NumeratorBaseline := -Max(NumeratorShift, Axis + Thickness / 2 + Gap + Numerator.Descent);
  DenominatorBaseline := Max(DenominatorShift, -Axis + Thickness / 2 + Gap + Denominator.Ascent);

  Padding := FractionPaddingEm * Em;
  InnerWidth := Max(Numerator.Width, Denominator.Width);

  Result := TMathBox.Create(TMathBoxKind.Group);
  Result.Enclose(Numerator, Padding + (InnerWidth - Numerator.Width) / 2, NumeratorBaseline);
  Result.Enclose(Denominator, Padding + (InnerWidth - Denominator.Width) / 2, DenominatorBaseline);

  if Node.HasRule then
  begin
    Bar := RuleBox(InnerWidth + 2 * Padding, Thickness);
    Result.Enclose(Bar, 0, -Axis);
  end;

  Result.Width := InnerWidth + 2 * Padding;
end;

function TMathBoxBuilder.BuildScript(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  BaseNode: IMathNode;
  Base: type of (Build(BaseNode, Style, Variant));
  PutsLimits: Boolean;
  ScriptStyle: TMathStyle;
  HasSuperscript: Boolean;
  HasSubscript: Boolean;
  Em: Single;
  ScriptLeft: Double;
  ScriptWidth: Single;
  SuperscriptRise: Single;
  Superscript: TMathBox;
  Subscript: type of (Build(Node.Children[2], ScriptStyle, Variant));
  SubscriptDrop: Double;
  SuperscriptBottom: Single;
  SubscriptTop: Double;
  Clearance: Double;
  MinimumClearance: Double;
begin
  BaseNode := Node.Children[0];
  Base := Build(BaseNode, Style, Variant);

  PutsLimits := (Style = TMathStyle.Display) and (BaseNode.Kind = TMathNodeKind.Symbol) and BaseNode.TakesLimits;
  if PutsLimits then
  begin
    Result := BuildLimits(Base, Node, Style, Variant);
    Exit;
  end;

  ScriptStyle := SubStyle(Style);
  HasSuperscript := not Node.Children[1].IsEmpty;
  HasSubscript := not Node.Children[2].IsEmpty;
  Em := EmSize(Style);

  Result := TMathBox.Create(TMathBoxKind.Group);
  Result.Enclose(Base, 0, 0);

  ScriptLeft := Base.Width + ScriptSpaceEm * Em;
  ScriptWidth := 0;

  SuperscriptRise := 0;
  Superscript := nil;
  if HasSuperscript then
  begin
    Superscript := Build(Node.Children[1], ScriptStyle, Variant);
    SuperscriptRise := Max(SuperscriptShiftUpEm * Em, Base.Ascent - XHeightEm * Em);
    SuperscriptRise := Max(SuperscriptRise, Superscript.Descent + SuperscriptBottomMinEm * Em);
    ScriptWidth := Superscript.Width;
  end;

  if HasSubscript then
  begin
    Subscript := Build(Node.Children[2], ScriptStyle, Variant);
    SubscriptDrop := Max(SubscriptShiftDownEm * Em, Base.Descent + XHeightEm * Em / 2);
    SubscriptDrop := Max(SubscriptDrop, Subscript.Ascent - SubscriptTopMaxEm * Em);

    if HasSuperscript then
    begin
      SuperscriptBottom := -SuperscriptRise + Superscript.Descent;
      SubscriptTop := SubscriptDrop - Subscript.Ascent;
      Clearance := SubscriptTop - SuperscriptBottom;
      MinimumClearance := SubSuperscriptGapMinEm * Em;
      if Clearance < MinimumClearance then
        SubscriptDrop := SubscriptDrop + (MinimumClearance - Clearance);
    end;

    Result.Enclose(Subscript, ScriptLeft, SubscriptDrop);
    ScriptWidth := Max(ScriptWidth, Subscript.Width);
  end;

  if HasSuperscript then
    Result.Enclose(Superscript, ScriptLeft, -SuperscriptRise);

  Result.Width := ScriptLeft + ScriptWidth + ScriptSpaceEm * Em;
end;

function TMathBoxBuilder.BuildLimits(const Base: TMathBox; const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  ScriptStyle: TMathStyle;
  Gap: Double;
  HasUpper: Boolean;
  HasLower: Boolean;
  Upper: TMathBox;
  Lower: TMathBox;
  Width: Single;
begin
  ScriptStyle := SubStyle(Style);
  Gap := LimitGapEm * EmSize(Style);
  HasUpper := not Node.Children[1].IsEmpty;
  HasLower := not Node.Children[2].IsEmpty;

  Upper := nil;
  Lower := nil;
  Width := Base.Width;

  if HasUpper then
  begin
    Upper := Build(Node.Children[1], ScriptStyle, Variant);
    Width := Max(Width, Upper.Width);
  end;

  if HasLower then
  begin
    Lower := Build(Node.Children[2], ScriptStyle, Variant);
    Width := Max(Width, Lower.Width);
  end;

  Result := TMathBox.Create(TMathBoxKind.Group);
  Result.Enclose(Base, (Width - Base.Width) / 2, 0);

  if HasUpper then
    Result.Enclose(Upper, (Width - Upper.Width) / 2, -(Base.Ascent + Gap + Upper.Descent));

  if HasLower then
    Result.Enclose(Lower, (Width - Lower.Width) / 2, Base.Descent + Gap + Lower.Ascent);

  Result.Width := Width;
end;

function TMathBoxBuilder.BuildRadical(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  Radicand: type of (Build(Node.Children[0], Style, Variant));
  Em: Single;
  Thickness: Single;
  Gap: Double;
  RuleTop: Double;
  SignBottom: Single;
  SignWidth: Double;
  Stroke: Double;
  IndexBox: TMathBox;
  IndexWidth: Single;
  HasIndex: Boolean;
  TickStart: TLayoutPointF;
  TickEnd: TLayoutPointF;
  StrokeEnd: TLayoutPointF;
  RadicandLeft: Double;
  Rule: TMathBox;
begin
  Radicand := Build(Node.Children[0], Style, Variant);
  Em := EmSize(Style);
  Thickness := RuleThicknessOf(Em);

  Gap := RadicalGapTextEm * Em;
  if Style = TMathStyle.Display then
    Gap := RadicalGapDisplayEm * Em;

  RuleTop := -(Radicand.Ascent + Gap + Thickness);
  SignBottom := Radicand.Descent + Thickness;
  SignWidth := RadicalSignWidthEm * Em;
  Stroke := RadicalStrokeEm * Em;

  Result := TMathBox.Create(TMathBoxKind.Group);

  IndexBox := nil;
  IndexWidth := 0;
  HasIndex := not Node.Children[1].IsEmpty;
  if HasIndex then
  begin
    IndexBox := Build(Node.Children[1], TMathStyle.ScriptScript, Variant);
    IndexWidth := Max(0, IndexBox.Width - SignWidth * 0.4);
  end;

  // The sign is a short tick, a long stroke up to the rule, and the rule
  // over the radicand, all drawn as filled shapes so they scale with the
  // radicand rather than with a glyph the font may not stretch.
  TickStart := TLayoutPointF.Create(IndexWidth, RuleTop * 0.45 + SignBottom * 0.55);
  TickEnd := TLayoutPointF.Create(IndexWidth + SignWidth * 0.35, SignBottom);
  StrokeEnd := TLayoutPointF.Create(IndexWidth + SignWidth, RuleTop + Thickness / 2);
  Result.Enclose(SegmentBox(TickStart, TickEnd, Stroke), 0, 0);
  Result.Enclose(SegmentBox(TickEnd, StrokeEnd, Stroke * 1.3), 0, 0);

  RadicandLeft := IndexWidth + SignWidth;
  Rule := RuleBox(Radicand.Width + Gap, Thickness);
  Result.Enclose(Rule, RadicandLeft, RuleTop);
  Result.Enclose(Radicand, RadicandLeft + Gap / 2, 0);

  if HasIndex then
    Result.Enclose(IndexBox, 0, RuleTop + RadicalIndexRaiseEm * Em - IndexBox.Descent);

  Result.Ascent := Result.Ascent + RadicalExtraAscenderEm * Em;
  Result.Width := RadicandLeft + Gap + Radicand.Width;
end;

function TMathBoxBuilder.BuildDelimited(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  Body: type of (Build(Node.Children[0], Style, Variant));
begin
  Body := Build(Node.Children[0], Style, Variant);

  Result := WrapWithDelimiters(Body, Node.LeftDelimiter, Node.RightDelimiter, Style);
end;

function TMathBoxBuilder.WrapWithDelimiters(const Body: TMathBox; const Left, Right: string;
  const Style: TMathStyle): TMathBox;
var
  LeftBox: TMathBox;
  RightBox: TMathBox;
begin
  LeftBox := BuildDelimiter(Left, Body.Ascent, Body.Descent, Style);
  RightBox := BuildDelimiter(Right, Body.Ascent, Body.Descent, Style);

  Result := TMathBox.Create(TMathBoxKind.Group);
  Result.Enclose(LeftBox, 0, 0);
  Result.Enclose(Body, LeftBox.Width, 0);
  Result.Enclose(RightBox, LeftBox.Width + Body.Width, 0);
  Result.Width := LeftBox.Width + Body.Width + RightBox.Width;
end;

// A delimiter that fits the body at the font's size is a glyph; a taller
// one is drawn as filled shapes centred on the math axis.
function TMathBoxBuilder.BuildDelimiter(const Delimiter: string; const RequiredAscent, RequiredDescent: Single;
  const Style: TMathStyle): TMathBox;
var
  Em: Single;
  Axis: Double;
  HalfHeight: Double;
  NeedsStretching: Boolean;
  Font: TMarkdownFontStyle;
begin
  Em := EmSize(Style);

  if Delimiter = '' then
  begin
    Result := EmptyBox;
    Result.Width := NullDelimiterSpaceEm * Em;
    Exit;
  end;

  Axis := AxisHeightEm * Em;
  HalfHeight := Max(RequiredAscent - Axis, RequiredDescent + Axis);
  NeedsStretching := (2 * HalfHeight > DelimiterGlyphHeightEm * Em);
  if not NeedsStretching then
  begin
    Font := FontFor(Style, TMathFontVariant.Upright);
    Result := GlyphBox(Delimiter, Font, FOptions.TextColor, GlyphExtent(Delimiter));
    Exit;
  end;

  Result := BuildStretchedDelimiter(Delimiter, Axis + HalfHeight, HalfHeight - Axis, Style);
end;

function TMathBoxBuilder.BuildStretchedDelimiter(const Delimiter: string; const Ascent, Descent: Single;
  const Style: TMathStyle): TMathBox;
var
  Em: Single;
  Width: Double;
  Stroke: Double;
  Glyph: Char;
begin
  Em := EmSize(Style);
  Width := DelimiterWidthEm * Em;
  Stroke := DelimiterStrokeEm * Em;

  Result := TMathBox.Create(TMathBoxKind.Group);
  Result.Width := Width;
  Result.Ascent := Ascent;
  Result.Descent := Descent;

  Glyph := Delimiter[1];
  case Glyph of
    '(':
      AddParenthesis(Result, Ascent, Descent, Width, Stroke, True);
    ')':
      AddParenthesis(Result, Ascent, Descent, Width, Stroke, False);
    '[':
      AddBracket(Result, Ascent, Descent, Width, Stroke, True);
    ']':
      AddBracket(Result, Ascent, Descent, Width, Stroke, False);
    '{':
      AddBrace(Result, Ascent, Descent, Width, Stroke, True);
    '}':
      AddBrace(Result, Ascent, Descent, Width, Stroke, False);
    '|':
      AddBar(Result, Ascent, Descent, Width / 2, Stroke);
    DoubleBarGlyph:
      begin
        AddBar(Result, Ascent, Descent, Width * 0.3, Stroke);
        AddBar(Result, Ascent, Descent, Width * 0.7, Stroke);
      end;
    LeftAngleGlyph:
      AddAngle(Result, Ascent, Descent, Width, Stroke, True);
    RightAngleGlyph:
      AddAngle(Result, Ascent, Descent, Width, Stroke, False);
    LeftFloorGlyph:
      AddFloorOrCeiling(Result, Ascent, Descent, Width, Stroke, True, False);
    RightFloorGlyph:
      AddFloorOrCeiling(Result, Ascent, Descent, Width, Stroke, False, False);
    LeftCeilingGlyph:
      AddFloorOrCeiling(Result, Ascent, Descent, Width, Stroke, True, True);
    RightCeilingGlyph:
      AddFloorOrCeiling(Result, Ascent, Descent, Width, Stroke, False, True);
    '/':
      AddPolyline(Result, [TLayoutPointF.Create(Width, -Ascent), TLayoutPointF.Create(0, Descent)], Stroke);
    '\':
      AddPolyline(Result, [TLayoutPointF.Create(0, -Ascent), TLayoutPointF.Create(Width, Descent)], Stroke);
  else
    AddBar(Result, Ascent, Descent, Width / 2, Stroke);
  end;
end;

procedure TMathBoxBuilder.AddParenthesis(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single;
  const OpensLeft: Boolean);
var
  Height: Single;
  Bow: Single;
  Outline: TArray<TLayoutPointF>;
  Index: Integer;
  Fraction: Double;
  Y: Double;
  X: Double;
  InnerX: Double;
  Shape: TMathBox;
begin
  // The bow is a parabola from the top right down to the left edge and back;
  // the polygon runs down the outer curve and back up the inner one.
  Height := Ascent + Descent;
  Bow := Width - Stroke;
  
  SetLength(Outline, 2 * (ParenthesisSegments + 1));

  for Index := 0 to ParenthesisSegments do
  begin
    Fraction := Index / ParenthesisSegments;
    Y := -Ascent + Fraction * Height;
    X := Bow * Sqr(2 * Fraction - 1);
    if not OpensLeft then
      X := Width - X;

    Outline[Index] := TLayoutPointF.Create(X, Y);

    InnerX := X + Stroke;
    if not OpensLeft then
      InnerX := X - Stroke;

    Outline[High(Outline) - Index] := TLayoutPointF.Create(InnerX, Y);
  end;

  Shape := TMathBox.Create(TMathBoxKind.Polygon);
  Shape.Points := Outline;
  Shape.Color := FOptions.TextColor;
  Shape.Width := Width;
  Shape.Ascent := Ascent;
  Shape.Descent := Descent;
  Group.Place(Shape, 0, 0);
end;

procedure TMathBoxBuilder.AddBracket(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single;
  const OpensLeft: Boolean);
var
  BarX: Double;
  TickEnd: Single;
begin
  BarX := Stroke / 2;
  TickEnd := Width;
  if not OpensLeft then
  begin
    BarX := Width - Stroke / 2;
    TickEnd := 0;
  end;

  AddPolyline(Group, [TLayoutPointF.Create(TickEnd, -Ascent + Stroke / 2), TLayoutPointF.Create(BarX, -Ascent + Stroke / 2),
    TLayoutPointF.Create(BarX, Descent - Stroke / 2), TLayoutPointF.Create(TickEnd, Descent - Stroke / 2)], Stroke);
end;

procedure TMathBoxBuilder.AddBrace(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single;
  const OpensLeft: Boolean);
var
  Middle: Double;
  Hook: Double;
  Inner: Double;
  Outer: Single;
  Cusp: Single;
begin
  Middle := (Descent - Ascent) / 2;
  Hook := Width / 2;
  // The hook always bulges to the midpoint between the outer edge and the
  // cusp, whichever side each of those ends up on, so unlike Outer and Cusp
  // it never needs a direction-dependent value.
  Inner := Width / 2;
  Outer := Width;
  Cusp := 0;
  if not OpensLeft then
  begin
    Outer := 0;
    Cusp := Width;
  end;

  AddPolyline(Group, [TLayoutPointF.Create(Outer, -Ascent), TLayoutPointF.Create(Inner, -Ascent + Hook),
    TLayoutPointF.Create(Inner, Middle - Hook), TLayoutPointF.Create(Cusp, Middle),
    TLayoutPointF.Create(Inner, Middle + Hook), TLayoutPointF.Create(Inner, Descent - Hook),
    TLayoutPointF.Create(Outer, Descent)], Stroke);
end;

procedure TMathBoxBuilder.AddBar(const Group: TMathBox; const Ascent, Descent, X, Stroke: Single);
begin
  AddPolyline(Group, [TLayoutPointF.Create(X, -Ascent), TLayoutPointF.Create(X, Descent)], Stroke);
end;

procedure TMathBoxBuilder.AddAngle(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single;
  const OpensLeft: Boolean);
var
  Middle: Double;
  Outer: Single;
  Tip: Single;
begin
  Middle := (Descent - Ascent) / 2;
  Outer := Width;
  Tip := 0;
  if not OpensLeft then
  begin
    Outer := 0;
    Tip := Width;
  end;

  AddPolyline(Group, [TLayoutPointF.Create(Outer, -Ascent), TLayoutPointF.Create(Tip, Middle),
    TLayoutPointF.Create(Outer, Descent)], Stroke);
end;

procedure TMathBoxBuilder.AddFloorOrCeiling(const Group: TMathBox; const Ascent, Descent, Width, Stroke: Single;
  const OpensLeft, TickAtTop: Boolean);
var
  BarX: Double;
  TickEnd: Single;
  TickY: Double;
  FarY: Single;
begin
  BarX := Stroke / 2;
  TickEnd := Width;
  if not OpensLeft then
  begin
    BarX := Width - Stroke / 2;
    TickEnd := 0;
  end;

  TickY := Descent - Stroke / 2;
  FarY := -Ascent;
  if TickAtTop then
  begin
    TickY := -Ascent + Stroke / 2;
    FarY := Descent;
  end;

  AddPolyline(Group, [TLayoutPointF.Create(TickEnd, TickY), TLayoutPointF.Create(BarX, TickY),
    TLayoutPointF.Create(BarX, FarY)], Stroke);
end;

procedure TMathBoxBuilder.AddPolyline(const Group: TMathBox; const Points: TArray<TLayoutPointF>;
  const Stroke: Single);
var
  Index: Integer;
begin
  for Index := 0 to High(Points) - 1 do
  begin
    Group.Place(SegmentBox(Points[Index], Points[Index + 1], Stroke), 0, 0);
  end;
end;

function TMathBoxBuilder.BuildAccent(const Node: IMathNode; const Style: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  Base: type of (Build(Node.Children[0], Style, Variant));
  Em: Single;
  IsOverline: Boolean;
  Thickness: Single;
  Line: TMathBox;
  IsArrow: Boolean;
  Font: TMarkdownFontStyle;
  GlyphBottom: Double;
  GlyphTop: Double;
  Accent: type of (GlyphBox(Node.Text, Font, FOptions.TextColor, TGlyphExtent.Create(0, 0)));
  Lift: Double;
begin
  Base := Build(Node.Children[0], Style, Variant);
  Em := EmSize(Style);

  Result := TMathBox.Create(TMathBoxKind.Group);
  Result.Enclose(Base, 0, 0);

  IsOverline := (Node.Text = '');
  if IsOverline then
  begin
    Thickness := RuleThicknessOf(Em);
    Line := RuleBox(Base.Width, Thickness);
    Result.Enclose(Line, 0, -(Base.Ascent + OverlineGapEm * Em + Thickness));
    Exit;
  end;

  // Accent glyphs sit above the x-height in the font, so an accent over a
  // short letter needs no lift; over a tall one it rises with the letter.
  IsArrow := (Node.Text = ArrowGlyph);
  Font := FontFor(Style, TMathFontVariant.Upright);
  GlyphBottom := AccentGlyphBottomEm * Em;
  GlyphTop := AccentGlyphTopEm * Em;
  if IsArrow then
  begin
    Font.Size := Font.Size * ArrowAccentScale;
    GlyphBottom := ArrowAccentBottomEm * Em;
    GlyphTop := ArrowAccentTopEm * Em;
  end;

  Accent := GlyphBox(Node.Text, Font, FOptions.TextColor, TGlyphExtent.Create(0, 0));
  Lift := Max(Base.Ascent, XHeightEm * Em) + AccentGapEm * Em - GlyphBottom;
  Result.Place(Accent, (Base.Width - Accent.Width) / 2, -Lift);
  Result.Ascent := Max(Result.Ascent, Lift + GlyphTop);
end;

function TMathBoxBuilder.BuildMatrix(const Node: IMathNode; const Style, CellStyle: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  Em: Single;
  RowGap: Double;
  ColumnGap: Double;
  ColumnCount: Integer;
  RowIndex: Integer;
  Cells: TM4DGen1;
  ColumnWidths: TArray<Single>;
  RowAscents: TArray<Single>;
  RowDescents: TArray<Single>;
  Body: TMathBox;
  Row: IMathNode;
  ColumnIndex: Integer;
  Cell: TMathBox;
  TotalHeight: Single;
  Cursor: Double;
  RowBaseline: Double;
  X: Single;
  Inset: Single;
  BodyWidth: Single;
  ColumnWidth: Single;
begin
  if Node.ColumnSpec <> '' then
  begin
    Result := BuildArray(Node, Style, CellStyle, Variant);
    Exit;
  end;

  Em := EmSize(Style);
  RowGap := MatrixRowGapEm * Em;
  ColumnGap := MatrixColumnGapEm * Em;

  ColumnCount := 0;
  for RowIndex := 0 to Node.ChildCount - 1 do
  begin
    ColumnCount := Max(ColumnCount, Node.Children[RowIndex].ChildCount);
  end;

  
  
  
  
  SetLength(Cells, Node.ChildCount);
  SetLength(ColumnWidths, ColumnCount);
  SetLength(RowAscents, Node.ChildCount);
  SetLength(RowDescents, Node.ChildCount);

  Body := TMathBox.Create(TMathBoxKind.Group);

  for RowIndex := 0 to Node.ChildCount - 1 do
  begin
    Row := Node.Children[RowIndex];
    SetLength(Cells[RowIndex], Row.ChildCount);

    for ColumnIndex := 0 to Row.ChildCount - 1 do
    begin
      Cell := Build(Row.Children[ColumnIndex], CellStyle, Variant);
      Cells[RowIndex][ColumnIndex] := Cell;
      ColumnWidths[ColumnIndex] := Max(ColumnWidths[ColumnIndex], Cell.Width);
      RowAscents[RowIndex] := Max(RowAscents[RowIndex], Cell.Ascent);
      RowDescents[RowIndex] := Max(RowDescents[RowIndex], Cell.Descent);
    end;
  end;

  TotalHeight := 0;
  for RowIndex := 0 to Node.ChildCount - 1 do
  begin
    TotalHeight := TotalHeight + RowAscents[RowIndex] + RowDescents[RowIndex];
  end;
  TotalHeight := TotalHeight + RowGap * Max(0, Node.ChildCount - 1);

  Cursor := -AxisHeightEm * Em - TotalHeight / 2;
  for RowIndex := 0 to Node.ChildCount - 1 do
  begin
    RowBaseline := Cursor + RowAscents[RowIndex];
    X := 0;

    for ColumnIndex := 0 to High(Cells[RowIndex]) do
    begin
      Cell := Cells[RowIndex][ColumnIndex];
      Inset := ColumnInset(Node.Alignment, ColumnIndex, ColumnWidths[ColumnIndex] - Cell.Width);

      Body.Enclose(Cell, X + Inset, RowBaseline);
      X := X + ColumnWidths[ColumnIndex] + ColumnGap;
    end;

    Cursor := Cursor + RowAscents[RowIndex] + RowDescents[RowIndex] + RowGap;
  end;

  BodyWidth := 0;
  for ColumnWidth in ColumnWidths do
  begin
    BodyWidth := BodyWidth + ColumnWidth;
  end;
  Body.Width := BodyWidth + ColumnGap * Max(0, ColumnCount - 1);

  Result := WrapWithDelimiters(Body, Node.LeftDelimiter, Node.RightDelimiter, Style);
end;

// An array or a tabular sets its rows on LaTeX's strut, one after the other,
// and draws a \hline at the border above a row and a | of the preamble at the
// border between two columns, across all rows.
function TMathBoxBuilder.BuildArray(const Node: IMathNode; const Style, CellStyle: TMathStyle;
  const Variant: TMathFontVariant): TMathBox;
var
  Em: Single;
  Thickness: Single;
  Padding: Double;
  RowPadding: Double;
  RuleGap: Double;
  Columns: string;
  BorderRules: TArray<Integer>;
  Character: Char;
  RowCount: Integer;
  ColumnCount: Integer;
  RowIndex: Integer;
  Cells: TM4DGen1;
  ColumnWidths: TArray<Single>;
  RowAscents: TArray<Single>;
  RowDescents: TArray<Single>;
  Row: IMathNode;
  ColumnIndex: Integer;
  Cell: TMathBox;
  Borders: TArray<Single>;
  X: Single;
  BorderIndex: Integer;
  TotalWidth: Single;
  TotalHeight: Single;
  Body: TMathBox;
  Top: Double;
  Cursor: Double;
  RulesAbove: Integer;
  RuleIndex: Integer;
  RowBaseline: Double;
  Slack: Single;
  Inset: Double;
  CellLeft: Double;
begin
  Em := EmSize(Style);
  Thickness := RuleThicknessOf(Em);
  Padding := ArrayColumnPaddingEm * Em;
  RowPadding := ArrayRowPaddingEm * Em;
  RuleGap := ArrayDoubleRuleGapEm * Em;

  // The columns of the preamble and the rules at each border, 0 before the
  // first column to System.Length(Columns) after the last.
  Columns := '';
  BorderRules := [0];
  for Character in Node.ColumnSpec do
  begin
    if Character = '|' then
      BorderRules[High(BorderRules)] := BorderRules[High(BorderRules)] + 1
    else
    begin
      Columns := Columns + Character;
      BorderRules := BorderRules + [0];
    end;
  end;

  RowCount := Node.ChildCount;
  ColumnCount := System.Length(Columns);
  for RowIndex := 0 to RowCount - 1 do
    ColumnCount := Max(ColumnCount, Node.Children[RowIndex].ChildCount);
  while System.Length(Columns) < ColumnCount do
  begin
    Columns := Columns + 'c';
    BorderRules := BorderRules + [0];
  end;

  
  
  
  
  SetLength(Cells, RowCount);
  SetLength(ColumnWidths, ColumnCount);
  SetLength(RowAscents, RowCount);
  SetLength(RowDescents, RowCount);

  for RowIndex := 0 to RowCount - 1 do
  begin
    Row := Node.Children[RowIndex];
    SetLength(Cells[RowIndex], Row.ChildCount);
    RowAscents[RowIndex] := ArrayStrutAscentEm * Em;
    RowDescents[RowIndex] := ArrayStrutDescentEm * Em;

    for ColumnIndex := 0 to Row.ChildCount - 1 do
    begin
      Cell := Build(Row.Children[ColumnIndex], CellStyle, Variant);
      Cells[RowIndex][ColumnIndex] := Cell;
      ColumnWidths[ColumnIndex] := Max(ColumnWidths[ColumnIndex], Cell.Width);
      RowAscents[RowIndex] := Max(RowAscents[RowIndex], Cell.Ascent);
      RowDescents[RowIndex] := Max(RowDescents[RowIndex], Cell.Descent);
    end;

    RowAscents[RowIndex] := RowAscents[RowIndex] + RowPadding;
    RowDescents[RowIndex] := RowDescents[RowIndex] + RowPadding;
  end;

  // Where each border runs: rules take their own room, the padding sits
  // between them and the cells.
  
  SetLength(Borders, ColumnCount + 1);
  X := 0;
  for BorderIndex := 0 to ColumnCount do
  begin
    Borders[BorderIndex] := X;
    X := X + RuleSpan(BorderRules[BorderIndex], Thickness, RuleGap);
    if BorderIndex < ColumnCount then
      X := X + Padding + ColumnWidths[BorderIndex] + Padding;
  end;
  TotalWidth := X;

  TotalHeight := 0;
  for RowIndex := 0 to RowCount - 1 do
    TotalHeight := TotalHeight + RuleSpan(Node.Children[RowIndex].RulesAbove, Thickness, RuleGap) +
      RowAscents[RowIndex] + RowDescents[RowIndex];
  TotalHeight := TotalHeight + RuleSpan(Node.RulesBelow, Thickness, RuleGap);

  Body := TMathBox.Create(TMathBoxKind.Group);
  Top := -AxisHeightEm * Em - TotalHeight / 2;
  Cursor := Top;

  for RowIndex := 0 to RowCount - 1 do
  begin
    RulesAbove := Node.Children[RowIndex].RulesAbove;
    for RuleIndex := 0 to RulesAbove - 1 do
      Body.Enclose(RuleBox(TotalWidth, Thickness), 0, Cursor + RuleIndex * (Thickness + RuleGap) + Thickness / 2);
    Cursor := Cursor + RuleSpan(RulesAbove, Thickness, RuleGap);

    RowBaseline := Cursor + RowAscents[RowIndex];
    for ColumnIndex := 0 to High(Cells[RowIndex]) do
    begin
      Cell := Cells[RowIndex][ColumnIndex];
      Slack := ColumnWidths[ColumnIndex] - Cell.Width;

      Inset := Slack / 2;
      if Columns[ColumnIndex + 1] = 'l' then
        Inset := 0
      else if Columns[ColumnIndex + 1] = 'r' then
        Inset := Slack;

      CellLeft := Borders[ColumnIndex] + RuleSpan(BorderRules[ColumnIndex], Thickness, RuleGap) + Padding;
      Body.Enclose(Cell, CellLeft + Inset, RowBaseline);
    end;

    Cursor := Cursor + RowAscents[RowIndex] + RowDescents[RowIndex];
  end;

  for RuleIndex := 0 to Node.RulesBelow - 1 do
    Body.Enclose(RuleBox(TotalWidth, Thickness), 0, Cursor + RuleIndex * (Thickness + RuleGap) + Thickness / 2);

  for BorderIndex := 0 to ColumnCount do
  begin
    for RuleIndex := 0 to BorderRules[BorderIndex] - 1 do
      Body.Enclose(VerticalRuleBox(Top, Top + TotalHeight, Thickness),
        Borders[BorderIndex] + RuleIndex * (Thickness + RuleGap), 0);
  end;

  Body.Width := TotalWidth;
  Result := WrapWithDelimiters(Body, Node.LeftDelimiter, Node.RightDelimiter, Style);
end;

// How much room Count rules side by side take, a gap between each two.
class function TMathBoxBuilder.RuleSpan(const Count: Integer; const Thickness, Gap: Single): Single;
begin
  Result := 0;
  if Count > 0 then
    Result := Count * Thickness + (Count - 1) * Gap;
end;

function TMathBoxBuilder.VerticalRuleBox(const Top, Bottom, Thickness: Single): TMathBox;
begin
  Result := TMathBox.Create(TMathBoxKind.Rule);
  Result.Rule := TLayoutRectF.Create(0, Top, Thickness, Bottom);
  Result.Color := FOptions.TextColor;
  Result.Width := Thickness;
  Result.Ascent := -Top;
  Result.Descent := Bottom;
end;

class function TMathBoxBuilder.ColumnInset(const Alignment: TMathColumnAlignment; const ColumnIndex: Integer;
  const Slack: Single): Single;
var
  IsRightAligned: Boolean;
begin
  case Alignment of
    TMathColumnAlignment.Centre:
      Result := Slack / 2;
    TMathColumnAlignment.Left:
      Result := 0;
    TMathColumnAlignment.Alternate:
      begin
        IsRightAligned := (ColumnIndex mod 2 = 0);
        if IsRightAligned then
          Result := Slack
        else
          Result := 0;
      end;
  else
    raise EMathSyntaxError.CreateFmt('Unhandled column alignment: %d', [Ord(Alignment)]);
  end;
end;

function TMathBoxBuilder.GlyphBox(const Text: string; const Font: TMarkdownFontStyle; const Color: TLayoutColor;
  const Extent: TGlyphExtent): TMathBox;
begin
  Result := TMathBox.Create(TMathBoxKind.Glyph);
  Result.Text := Text;
  Result.Font := Font;
  Result.Color := Color;
  Result.FontBaseline := FMeasurer.Baseline(Font);
  Result.Width := FMeasurer.MeasureText(Text, Font).Width;
  Result.Ascent := Extent.AscentEm * Font.Size * FDeviceScale;
  Result.Descent := Extent.DescentEm * Font.Size * FDeviceScale;
end;

function TMathBoxBuilder.RuleBox(const Width, Thickness: Single): TMathBox;
begin
  Result := TMathBox.Create(TMathBoxKind.Rule);
  Result.Rule := TLayoutRectF.Create(0, -Thickness / 2, Width, Thickness / 2);
  Result.Color := FOptions.TextColor;
  Result.Width := Width;
  Result.Ascent := Thickness / 2;
  Result.Descent := Thickness / 2;
end;

// A line segment as a filled quadrilateral, which is the one shape every
// painter draws. Its extent is the bounding box of the two ends.
function TMathBoxBuilder.SegmentBox(const StartPoint, EndPoint: TLayoutPointF; const Thickness: Single): TMathBox;
var
  DeltaX: Single;
  DeltaY: Single;
  Length: Double;
  NormalX: Double;
  NormalY: Double;
begin
  DeltaX := EndPoint.X - StartPoint.X;
  DeltaY := EndPoint.Y - StartPoint.Y;
  Length := Max(Sqrt(DeltaX * DeltaX + DeltaY * DeltaY), 0.001);
  NormalX := -DeltaY / Length * Thickness / 2;
  NormalY := DeltaX / Length * Thickness / 2;

  Result := TMathBox.Create(TMathBoxKind.Polygon);
  Result.Points := [TLayoutPointF.Create(StartPoint.X + NormalX, StartPoint.Y + NormalY),
    TLayoutPointF.Create(EndPoint.X + NormalX, EndPoint.Y + NormalY),
    TLayoutPointF.Create(EndPoint.X - NormalX, EndPoint.Y - NormalY),
    TLayoutPointF.Create(StartPoint.X - NormalX, StartPoint.Y - NormalY)];
  Result.Color := FOptions.TextColor;
  Result.Width := Max(StartPoint.X, EndPoint.X);
  Result.Ascent := -Min(StartPoint.Y, EndPoint.Y);
  Result.Descent := Max(StartPoint.Y, EndPoint.Y);
end;

class function TMathBoxBuilder.EmptyBox: TMathBox;
begin
  Result := TMathBox.Create(TMathBoxKind.Group);
end;

function TMathBoxBuilder.FontFor(const Style: TMathStyle; const Variant: TMathFontVariant): TMarkdownFontStyle;
var
  IsItalic: Boolean;
  IsBold: Boolean;
begin
  IsItalic := (Variant = TMathFontVariant.Italic) or (Variant = TMathFontVariant.BoldItalic);
  IsBold := (Variant = TMathFontVariant.Bold) or (Variant = TMathFontVariant.BoldItalic);

  // The size of a font stays the one the measurer is given; it scales the
  // glyphs itself.
  Result := TMarkdownFontStyle.Create(FOptions.Font.FamilyName, EmSize(Style) / FDeviceScale, IsBold, IsItalic);
end;

function TMathBoxBuilder.EmSize(const Style: TMathStyle): Single;
begin
  case Style of
    TMathStyle.Display, TMathStyle.Text:
      Result := FOptions.Font.Size * FDeviceScale;
    TMathStyle.Script:
      Result := FOptions.Font.Size * ScriptScale * FDeviceScale;
    TMathStyle.ScriptScript:
      Result := FOptions.Font.Size * ScriptScriptScale * FDeviceScale;
  else
    raise EMathSyntaxError.CreateFmt('Unhandled math style: %d', [Ord(Style)]);
  end;
end;

class function TMathBoxBuilder.SubStyle(const Style: TMathStyle): TMathStyle;
begin
  case Style of
    TMathStyle.Display, TMathStyle.Text:
      Result := TMathStyle.Script;
    TMathStyle.Script, TMathStyle.ScriptScript:
      Result := TMathStyle.ScriptScript;
  else
    raise EMathSyntaxError.CreateFmt('Unhandled math style: %d', [Ord(Style)]);
  end;
end;

class function TMathBoxBuilder.FractionStyle(const Style: TMathStyle): TMathStyle;
begin
  case Style of
    TMathStyle.Display:
      Result := TMathStyle.Text;
    TMathStyle.Text:
      Result := TMathStyle.Script;
    TMathStyle.Script, TMathStyle.ScriptScript:
      Result := TMathStyle.ScriptScript;
  else
    raise EMathSyntaxError.CreateFmt('Unhandled math style: %d', [Ord(Style)]);
  end;
end;

class function TMathBoxBuilder.IsScriptStyle(const Style: TMathStyle): Boolean;
begin
  Result := (Style = TMathStyle.Script) or (Style = TMathStyle.ScriptScript);
end;

// A symbol's own variant is italic for letters and upright for the rest;
// inside \mathbf and the like the surrounding variant takes over.
class function TMathBoxBuilder.ResolveVariant(const Own, Context: TMathFontVariant): TMathFontVariant;
var
  HasContext: Boolean;
  IsPlain: Boolean;
begin
  HasContext := (Context <> TMathFontVariant.Italic);
  IsPlain := (Own = TMathFontVariant.Italic) or (Own = TMathFontVariant.Upright);
  if HasContext and IsPlain then
  begin
    Result := Context;
    Exit;
  end;

  Result := Own;
end;

// Whole pixels, at least one: a rule of 1.2 pixels painted at 10.4 or at
// 10.6 rounds to one pixel or to two, so bars and lines of the same formula
// would look unequally thick.
class function TMathBoxBuilder.RuleThicknessOf(const Em: Single): Single;
begin
  Result := Max(1, Round(RuleThicknessEm * Em));
end;

// TeX sets the cells of a matrix in text style, but the lines of aligned in
// the style around them, display style in a display formula, so a fraction
// in an aligned line keeps its size.
class function TMathBoxBuilder.CellStyleOf(const Node: IMathNode; const Style: TMathStyle): TMathStyle;
begin
  if Node.Alignment = TMathColumnAlignment.Alternate then
    Result := Style
  else
    Result := TMathStyle.Text;
end;

// A run of text reaches as high as its tallest character and as low as its
// deepest, so the p of "Rohprotein" keeps a fraction bar below it clear.
class function TMathBoxBuilder.GlyphExtent(const Text: string): TGlyphExtent;
var
  Character: Char;
  Extent: TGlyphExtent;
begin
  Result := TGlyphExtent.Create(0, 0);

  for Character in Text do
  begin
    if Character.IsWhiteSpace or Character.IsLowSurrogate then
      Continue;

    Extent := CharacterExtent(Character);
    Result.AscentEm := Max(Result.AscentEm, Extent.AscentEm);
    Result.DescentEm := Max(Result.DescentEm, Extent.DescentEm);
  end;
end;

// Heights in em for the glyph classes the font families share closely
// enough: the layouter needs ascent and descent, and the measurer only
// reports a line height. The values follow STIX Two Math.
class function TMathBoxBuilder.CharacterExtent(const First: Char): TGlyphExtent;
var
  Ascends: Boolean;
  Descends: Boolean;
  Both: Boolean;
  IsIntegral: Boolean;
begin
  if First.IsDigit then
  begin
    Result := TGlyphExtent.Create(0.68, 0);
    Exit;
  end;

  if First.IsUpper then
  begin
    Result := TGlyphExtent.Create(0.68, 0);
    Exit;
  end;

  if First.IsLower then
  begin
    Ascends := CharInSet(First, ['b', 'd', 'f', 'h', 'k', 'l', 't', 'i']) or (First = #$03B4) or
      (First = #$03B8) or (First = #$03BB);
    Descends := CharInSet(First, ['g', 'p', 'q', 'y']) or (First = #$03B3) or (First = #$03B7) or
      (First = #$03BC) or (First = #$03C1) or (First = #$03C6) or (First = #$03C7) or (First = #$03C8) or
      (First = #$03C2) or (First = #$03D5);
    Both := CharInSet(First, ['j']) or (First = #$03B2) or (First = #$03B6) or (First = #$03BE);

    if Both then
    begin
      Result := TGlyphExtent.Create(0.70, 0.21);
      Exit;
    end;

    if Ascends then
    begin
      Result := TGlyphExtent.Create(0.70, 0);
      Exit;
    end;

    if Descends then
    begin
      Result := TGlyphExtent.Create(0.46, 0.21);
      Exit;
    end;

    Result := TGlyphExtent.Create(0.46, 0);
    Exit;
  end;

  if CharInSet(First, ['(', ')', '[', ']', '{', '}', '|', '/', '\']) or (First = DoubleBarGlyph) or
    (First = LeftAngleGlyph) or (First = RightAngleGlyph) or (First = LeftFloorGlyph) or
    (First = RightFloorGlyph) or (First = LeftCeilingGlyph) or (First = RightCeilingGlyph) then
  begin
    Result := TGlyphExtent.Create(0.75, 0.25);
    Exit;
  end;

  if CharInSet(First, [',', ';']) then
  begin
    Result := TGlyphExtent.Create(0.15, 0.15);
    Exit;
  end;

  if First = '.' then
  begin
    Result := TGlyphExtent.Create(0.12, 0);
    Exit;
  end;

  IsIntegral := (First >= IntegralGlyph) and (First <= #$222E);
  if IsIntegral then
  begin
    Result := TGlyphExtent.Create(0.85, 0.35);
    Exit;
  end;

  if (First = #$2211) or (First = #$220F) or (First = #$2210) then
  begin
    Result := TGlyphExtent.Create(0.75, 0.25);
    Exit;
  end;

  if First.IsPunctuation or First.IsSymbol then
  begin
    Result := TGlyphExtent.Create(0.55, 0.05);
    Exit;
  end;

  Result := TGlyphExtent.Create(0.68, 0.05);
end;

end.
