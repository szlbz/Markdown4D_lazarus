{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Layout.MeasureCache;

{$SCOPEDENUMS ON}

// Most measurements during a layout repeat the same words in the same fonts,
// and every relayout (resize, new text, arriving images) repeats them again.
// Measuring through the platform is the slow part, so the sizes are kept,
// keyed by everything that decides them, the scale included.

interface

uses
  Generics.Collections,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Compat.Str,
  character;

type
  TMarkdownMeasureCache = class
  private
    type
      TKey = record
        Text: string;
        Font: TMarkdownFontStyle;
        PixelsPerInch: Integer;
      end;
    var
      FCapacity: Integer;
      FSizes: TDictionary<TKey, TLayoutSizeF>;
    class function KeyOf(const Text: string; const Font: TMarkdownFontStyle;
      const PixelsPerInch: Integer): TKey; static;
    class function KeysEqual(const Left, Right: TKey): Boolean; static;
    class function KeyHash(const Key: TKey): Cardinal; static;

  public
    const
      DefaultCapacity = 65536;
    constructor Create(const Capacity: Integer = DefaultCapacity);
    destructor Destroy; override;
    function TryGetSize(const Text: string; const Font: TMarkdownFontStyle; const PixelsPerInch: Integer;
      out Size: TLayoutSizeF): Boolean;
    // A full cache starts over rather than tracking which entries are old: the
    // words of the document in view come back on the next layout.
    procedure Add(const Text: string; const Font: TMarkdownFontStyle; const PixelsPerInch: Integer;
      const Size: TLayoutSizeF);
    function Count: Integer;
  end;

implementation

uses
  Generics.Defaults,
  Markdown4D.Compat.Hash;

class function TMarkdownMeasureCache.KeyOf(const Text: string; const Font: TMarkdownFontStyle;
  const PixelsPerInch: Integer): TKey;
begin
  Result.Text := Text;
  Result.Font := Font;
  Result.PixelsPerInch := PixelsPerInch;
end;

class function TMarkdownMeasureCache.KeysEqual(const Left, Right: TKey): Boolean;
begin
  Result := (Left.Text = Right.Text) and
            Left.Font.SameAs(Right.Font) and
            (Left.PixelsPerInch = Right.PixelsPerInch);
end;

// Each part feeds the next as its initial value, so no arithmetic can overflow
// in a host that compiles with overflow checks.
class function TMarkdownMeasureCache.KeyHash(const Key: TKey): Cardinal;
var
  TextHash: Integer;
  FamilyHash: Integer;
begin
  TextHash := THashBobJenkins.GetHashValue(Key.Text);
  FamilyHash := THashBobJenkins.GetHashValue(Key.Font.FamilyName);

  Result := THashBobJenkins.GetHashValue(FamilyHash, SizeOf(FamilyHash), TextHash);
  Result := THashBobJenkins.GetHashValue(Key.Font.Size, SizeOf(Key.Font.Size), Result);
  Result := THashBobJenkins.GetHashValue(Key.PixelsPerInch, SizeOf(Key.PixelsPerInch), Result);
end;

constructor TMarkdownMeasureCache.Create(const Capacity: Integer);
var
  Comparer: type of (TEqualityComparer<TKey>.Construct(KeysEqual, KeyHash));
begin
  inherited Create;

  FCapacity := Capacity;
  Comparer := TEqualityComparer<TKey>.Construct(KeysEqual, KeyHash);
  FSizes := TDictionary<TKey, TLayoutSizeF>.Create(Comparer);
end;

destructor TMarkdownMeasureCache.Destroy;
begin
  FSizes.Free;

  inherited Destroy;
end;

function TMarkdownMeasureCache.TryGetSize(const Text: string; const Font: TMarkdownFontStyle;
  const PixelsPerInch: Integer; out Size: TLayoutSizeF): Boolean;
var
  Key: type of (KeyOf(Text, Font, PixelsPerInch));
begin
  Key := KeyOf(Text, Font, PixelsPerInch);
  Result := FSizes.TryGetValue(Key, Size);
end;

procedure TMarkdownMeasureCache.Add(const Text: string; const Font: TMarkdownFontStyle; const PixelsPerInch: Integer;
  const Size: TLayoutSizeF);
var
  IsFull: Boolean;
  Key: type of (KeyOf(Text, Font, PixelsPerInch));
begin
  IsFull := (FSizes.Count >= FCapacity);
  if IsFull then
    FSizes.Clear;

  Key := KeyOf(Text, Font, PixelsPerInch);
  FSizes.AddOrSetValue(Key, Size);
end;

function TMarkdownMeasureCache.Count: Integer;
begin
  Result := FSizes.Count;
end;

end.
