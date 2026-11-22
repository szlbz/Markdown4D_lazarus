unit Markdown4D.Compat.UITypes;
{ The slice of Delphi's System.UITypes / System.UIConsts that Markdown4D uses. }

{$mode delphiunicode}

interface

{$SCOPEDENUMS ON}

type
  TFontStyle = (fsBold, fsItalic, fsUnderline, fsStrikeOut);
  TFontStyles = set of TFontStyle;

  TAlphaColor = Cardinal;

  TAlphaColorRec = record
  var
    Blue: Byte;
    Green: Byte;
    Red: Byte;
    Alpha: Byte;
  end;

  TColorEntry = record
    Name: string;
    Value: TAlphaColor;
  end;

  { The callback Delphi's GetAlphaColorValues hands every RTL colour name to. }
  TAlphaColorValueProc = procedure(const Ident: string) of object;

function InRange(const AValue, AMin, AMax: Integer): Boolean; overload;
function InRange(const AValue, AMin, AMax: Single): Boolean; overload;
function IdentToAlphaColor(const Ident: string; out Color: Cardinal): Boolean; overload;
function IdentToAlphaColor(const Ident: string; out Color: Integer): Boolean; overload;
procedure GetAlphaColorValues(const Proc: TAlphaColorValueProc);

const
  { Delphi's System.UITypes also carries the shortcut modifiers and the
    virtual-key codes; these are the values the Windows unit uses. }
  scShift = $2000;
  scCtrl = $4000;
  scAlt = $8000;
  vkBack = $08;
  vkTab = $09;
  vkReturn = $0D;
  vkShift = $10;
  vkControl = $11;
  vkMenu = $12;
  vkPause = $13;
  vkCapital = $14;
  vkEscape = $1B;
  vkSpace = $20;
  vkPrior = $21;
  vkNext = $22;
  vkEnd = $23;
  vkHome = $24;
  vkLeft = $25;
  vkUp = $26;
  vkRight = $27;
  vkDown = $28;
  vkSnapshot = $2C;
  vkInsert = $2D;
  vkDelete = $2E;
  vkMultiply = $6A;
  vkAdd = $6B;
  vkSeparator = $6C;
  vkSubtract = $6D;
  vkDecimal = $6E;
  vkDivide = $6F;
  vk0 = $30;
  vk1 = $31;
  vk2 = $32;
  vk3 = $33;
  vk4 = $34;
  vk5 = $35;
  vk6 = $36;
  vk7 = $37;
  vk8 = $38;
  vk9 = $39;
  vkA = $41;
  vkB = $42;
  vkC = $43;
  vkD = $44;
  vkE = $45;
  vkF = $46;
  vkG = $47;
  vkH = $48;
  vkI = $49;
  vkJ = $4A;
  vkK = $4B;
  vkL = $4C;
  vkM = $4D;
  vkN = $4E;
  vkO = $4F;
  vkP = $50;
  vkQ = $51;
  vkR = $52;
  vkS = $53;
  vkT = $54;
  vkU = $55;
  vkV = $56;
  vkW = $57;
  vkX = $58;
  vkY = $59;
  vkZ = $5A;
  vkF1 = $70;
  vkEqual = $BB;
  vkComma = $BC;
  vkMinus = $BD;
  vkPeriod = $BE;
  vkSemicolon = $BA;
  vkSlash = $BF;
  vkBackQuote = $C0;
  vkLeftBracket = $DB;
  vkBackslash = $DC;
  vkRightBracket = $DD;
  vkQuote = $DE;
  vkNumLock = $90;
  vkScrollLock = $91;
  vkBrowserBack = $A6;
  vkBrowserForward = $A7;
  vkVolumeMute = $AD;
  vkNumpad0 = $60;
  vkNumpad1 = $61;
  vkNumpad2 = $62;
  vkNumpad3 = $63;
  vkNumpad4 = $64;
  vkNumpad5 = $65;
  vkNumpad6 = $66;
  vkNumpad7 = $67;
  vkNumpad8 = $68;
  vkNumpad9 = $69;
  vkF2 = $71;
  vkF3 = $72;
  vkF4 = $73;
  vkF5 = $74;
  vkF6 = $75;
  vkF7 = $76;
  vkF8 = $77;
  vkF9 = $78;
  vkF10 = $79;
  vkF11 = $7A;
  vkF12 = $7B;

  CssColorNames: array[0..147] of TColorEntry = (
    (Name: 'aliceblue'; Value: $FFF0F8FF),
    (Name: 'antiquewhite'; Value: $FFFAEBD7),
    (Name: 'aqua'; Value: $FF00FFFF),
    (Name: 'aquamarine'; Value: $FF7FFFD4),
    (Name: 'azure'; Value: $FFF0FFFF),
    (Name: 'beige'; Value: $FFF5F5DC),
    (Name: 'bisque'; Value: $FFFFE4C4),
    (Name: 'black'; Value: $FF000000),
    (Name: 'blanchedalmond'; Value: $FFFFEBCD),
    (Name: 'blue'; Value: $FF0000FF),
    (Name: 'blueviolet'; Value: $FF8A2BE2),
    (Name: 'brown'; Value: $FFA52A2A),
    (Name: 'burlywood'; Value: $FFDEB887),
    (Name: 'cadetblue'; Value: $FF5F9EA0),
    (Name: 'chartreuse'; Value: $FF7FFF00),
    (Name: 'chocolate'; Value: $FFD2691E),
    (Name: 'coral'; Value: $FFFF7F50),
    (Name: 'cornflowerblue'; Value: $FF6495ED),
    (Name: 'cornsilk'; Value: $FFFFF8DC),
    (Name: 'crimson'; Value: $FFDC143C),
    (Name: 'cyan'; Value: $FF00FFFF),
    (Name: 'darkblue'; Value: $FF00008B),
    (Name: 'darkcyan'; Value: $FF008B8B),
    (Name: 'darkgoldenrod'; Value: $FFB8860B),
    (Name: 'darkgray'; Value: $FFA9A9A9),
    (Name: 'darkgreen'; Value: $FF006400),
    (Name: 'darkgrey'; Value: $FFA9A9A9),
    (Name: 'darkkhaki'; Value: $FFBDB76B),
    (Name: 'darkmagenta'; Value: $FF8B008B),
    (Name: 'darkolivegreen'; Value: $FF556B2F),
    (Name: 'darkorange'; Value: $FFFF8C00),
    (Name: 'darkorchid'; Value: $FF9932CC),
    (Name: 'darkred'; Value: $FF8B0000),
    (Name: 'darksalmon'; Value: $FFE9967A),
    (Name: 'darkseagreen'; Value: $FF8FBC8F),
    (Name: 'darkslateblue'; Value: $FF483D8B),
    (Name: 'darkslategray'; Value: $FF2F4F4F),
    (Name: 'darkslategrey'; Value: $FF2F4F4F),
    (Name: 'darkturquoise'; Value: $FF00CED1),
    (Name: 'darkviolet'; Value: $FF9400D3),
    (Name: 'deeppink'; Value: $FFFF1493),
    (Name: 'deepskyblue'; Value: $FF00BFFF),
    (Name: 'dimgray'; Value: $FF696969),
    (Name: 'dimgrey'; Value: $FF696969),
    (Name: 'dodgerblue'; Value: $FF1E90FF),
    (Name: 'firebrick'; Value: $FFB22222),
    (Name: 'floralwhite'; Value: $FFFFFAF0),
    (Name: 'forestgreen'; Value: $FF228B22),
    (Name: 'fuchsia'; Value: $FFFF00FF),
    (Name: 'gainsboro'; Value: $FFDCDCDC),
    (Name: 'ghostwhite'; Value: $FFF8F8FF),
    (Name: 'gold'; Value: $FFFFD700),
    (Name: 'goldenrod'; Value: $FFDAA520),
    (Name: 'gray'; Value: $FF808080),
    (Name: 'green'; Value: $FF008000),
    (Name: 'greenyellow'; Value: $FFADFF2F),
    (Name: 'grey'; Value: $FF808080),
    (Name: 'honeydew'; Value: $FFF0FFF0),
    (Name: 'hotpink'; Value: $FFFF69B4),
    (Name: 'indianred'; Value: $FFCD5C5C),
    (Name: 'indigo'; Value: $FF4B0082),
    (Name: 'ivory'; Value: $FFFFFFF0),
    (Name: 'khaki'; Value: $FFF0E68C),
    (Name: 'lavender'; Value: $FFE6E6FA),
    (Name: 'lavenderblush'; Value: $FFFFF0F5),
    (Name: 'lawngreen'; Value: $FF7CFC00),
    (Name: 'lemonchiffon'; Value: $FFFFFACD),
    (Name: 'lightblue'; Value: $FFADD8E6),
    (Name: 'lightcoral'; Value: $FFF08080),
    (Name: 'lightcyan'; Value: $FFE0FFFF),
    (Name: 'lightgoldenrodyellow'; Value: $FFFAFAD2),
    (Name: 'lightgray'; Value: $FFD3D3D3),
    (Name: 'lightgreen'; Value: $FF90EE90),
    (Name: 'lightgrey'; Value: $FFD3D3D3),
    (Name: 'lightpink'; Value: $FFFFB6C1),
    (Name: 'lightsalmon'; Value: $FFFFA07A),
    (Name: 'lightseagreen'; Value: $FF20B2AA),
    (Name: 'lightskyblue'; Value: $FF87CEFA),
    (Name: 'lightslategray'; Value: $FF778899),
    (Name: 'lightslategrey'; Value: $FF778899),
    (Name: 'lightsteelblue'; Value: $FFB0C4DE),
    (Name: 'lightyellow'; Value: $FFFFFFE0),
    (Name: 'lime'; Value: $FF00FF00),
    (Name: 'limegreen'; Value: $FF32CD32),
    (Name: 'linen'; Value: $FFFAF0E6),
    (Name: 'magenta'; Value: $FFFF00FF),
    (Name: 'maroon'; Value: $FF800000),
    (Name: 'mediumaquamarine'; Value: $FF66CDAA),
    (Name: 'mediumblue'; Value: $FF0000CD),
    (Name: 'mediumorchid'; Value: $FFBA55D3),
    (Name: 'mediumpurple'; Value: $FF9370DB),
    (Name: 'mediumseagreen'; Value: $FF3CB371),
    (Name: 'mediumslateblue'; Value: $FF7B68EE),
    (Name: 'mediumspringgreen'; Value: $FF00FA9A),
    (Name: 'mediumturquoise'; Value: $FF48D1CC),
    (Name: 'mediumvioletred'; Value: $FFC71585),
    (Name: 'midnightblue'; Value: $FF191970),
    (Name: 'mintcream'; Value: $FFF5FFFA),
    (Name: 'mistyrose'; Value: $FFFFE4E1),
    (Name: 'moccasin'; Value: $FFFFE4B5),
    (Name: 'navajowhite'; Value: $FFFFDEAD),
    (Name: 'navy'; Value: $FF000080),
    (Name: 'oldlace'; Value: $FFFDF5E6),
    (Name: 'olive'; Value: $FF808000),
    (Name: 'olivedrab'; Value: $FF6B8E23),
    (Name: 'orange'; Value: $FFFFA500),
    (Name: 'orangered'; Value: $FFFF4500),
    (Name: 'orchid'; Value: $FFDA70D6),
    (Name: 'palegoldenrod'; Value: $FFEEE8AA),
    (Name: 'palegreen'; Value: $FF98FB98),
    (Name: 'paleturquoise'; Value: $FFAFEEEE),
    (Name: 'palevioletred'; Value: $FFDB7093),
    (Name: 'papayawhip'; Value: $FFFFEFD5),
    (Name: 'peachpuff'; Value: $FFFFDAB9),
    (Name: 'peru'; Value: $FFCD853F),
    (Name: 'pink'; Value: $FFFFC0CB),
    (Name: 'plum'; Value: $FFDDA0DD),
    (Name: 'powderblue'; Value: $FFB0E0E6),
    (Name: 'purple'; Value: $FF800080),
    (Name: 'rebeccapurple'; Value: $FF663399),
    (Name: 'red'; Value: $FFFF0000),
    (Name: 'rosybrown'; Value: $FFBC8F8F),
    (Name: 'royalblue'; Value: $FF4169E1),
    (Name: 'saddlebrown'; Value: $FF8B4513),
    (Name: 'salmon'; Value: $FFFA8072),
    (Name: 'sandybrown'; Value: $FFF4A460),
    (Name: 'seagreen'; Value: $FF2E8B57),
    (Name: 'seashell'; Value: $FFFFF5EE),
    (Name: 'sienna'; Value: $FFA0522D),
    (Name: 'silver'; Value: $FFC0C0C0),
    (Name: 'skyblue'; Value: $FF87CEEB),
    (Name: 'slateblue'; Value: $FF6A5ACD),
    (Name: 'slategray'; Value: $FF708090),
    (Name: 'slategrey'; Value: $FF708090),
    (Name: 'snow'; Value: $FFFFFAFA),
    (Name: 'springgreen'; Value: $FF00FF7F),
    (Name: 'steelblue'; Value: $FF4682B4),
    (Name: 'tan'; Value: $FFD2B48C),
    (Name: 'teal'; Value: $FF008080),
    (Name: 'thistle'; Value: $FFD8BFD8),
    (Name: 'tomato'; Value: $FFFF6347),
    (Name: 'turquoise'; Value: $FF40E0D0),
    (Name: 'violet'; Value: $FFEE82EE),
    (Name: 'wheat'; Value: $FFF5DEB3),
    (Name: 'white'; Value: $FFFFFFFF),
    (Name: 'whitesmoke'; Value: $FFF5F5F5),
    (Name: 'yellow'; Value: $FFFFFF00),
    (Name: 'yellowgreen'; Value: $FF9ACD32)
  );

implementation

uses
  SysUtils, Math;

function InRange(const AValue, AMin, AMax: Integer): Boolean;
begin
  Result := (AValue >= AMin) and (AValue <= AMax);
end;

function InRange(const AValue, AMin, AMax: Single): Boolean;
begin
  Result := (AValue >= AMin) and (AValue <= AMax);
end;

function IdentToAlphaColor(const Ident: string; out Color: Cardinal): Boolean;
var
  Index: Integer;
  Name: string;
begin
  Name := LowerCase(Ident);
  if Name.StartsWith('cla') then
    Delete(Name, 1, 3);
  Result := True;
  for Index := 0 to High(CssColorNames) do
    if CssColorNames[Index].Name = Name then
    begin
      Color := CssColorNames[Index].Value;
      Exit;
    end;
  Color := 0;
  Result := False;
end;

function IdentToAlphaColor(const Ident: string; out Color: Integer): Boolean;
var
  Value: Cardinal;
begin
  Result := IdentToAlphaColor(Ident, Value);
  Color := Integer(Value);
end;

procedure GetAlphaColorValues(const Proc: TAlphaColorValueProc);
var
  Index: Integer;
begin
  for Index := 0 to High(CssColorNames) do
    Proc(CssColorNames[Index].Name);
end;

end.
