{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Text.UrlSafety;

{$SCOPEDENUMS ON}

// Link and image destinations come straight out of the document, so a document
// can carry a destination that executes code the moment a reader clicks it.
// This unit decides which destinations may reach the output, using the same
// rule set as cmark's safe mode: the scripting schemes are dropped, and data:
// survives only for the four image types that cannot carry script.

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character;

type
  TMarkdownUrlSafety = class
  private
    const
      // Long enough for the longest prefix that is compared below.
      MaxProbeLength = 24;
      DangerousSchemes: array[0..2] of string = ('javascript:', 'vbscript:', 'file:');
      DataScheme = 'data:';
      SafeDataPrefixes: array[0..3] of string = ('data:image/png', 'data:image/gif', 'data:image/jpeg',
        'data:image/webp');
      SchemeSeparator = ':';
      // A browser reads //host/path, and also \\host or /\host, as a link to
      // another host over the page's own protocol, which on the web is https.
      ProtocolRelativeScheme = 'https';
      ProtocolRelativePrefixLength = 2;
      PathSeparators: TSysCharSet = ['/', '\'];
      // RFC 3986 scheme characters. Markdown4D.Compat.Url.TURI uses the same set,
      // but only inside DecomposeURI, and TURI.Create raises for a relative URL
      // and for most schemes without //, such as javascript: and data:.
      SchemeLetters: TSysCharSet = ['a'..'z', 'A'..'Z'];
      SchemeCharacters: TSysCharSet = ['a'..'z', 'A'..'Z', '0'..'9', '+', '-', '.'];
      SchemeTerminators: array[0..4] of Char = (':', '/', '\', '?', '#');
      InvalidSchemeMessage = 'Invalid URL scheme name: "%s"';
    class function SchemeProbe(const Url: string): string;
    class function IsListed(const Scheme: string; const AllowedSchemes: TArray<string>): Boolean;
    class function BareScheme(const Scheme: string): string;
    class function EffectiveScheme(const Url: string): string;
    class function SchemePrefix(const Url: string): string;
    class function IsProtocolRelative(const Prefix: string): Boolean;
    class function IsSchemeName(const Candidate: string): Boolean;

  public
    class function IsDangerous(const Url: string): Boolean;
    class function Sanitized(const Url: string): string;
    // Stricter than IsDangerous alone: a list of schemes cannot reopen what the
    // blocklist closes, so a dangerous destination stays out even when listed.
    class function IsAllowed(const Url: string; const AllowedSchemes: TArray<string>): Boolean;
    // Raises for a name that is not a scheme, such as 'https://', so a mistake
    // in a configuration shows at once instead of dropping every link.
    class function NormalizedScheme(const Scheme: string): string;
  end;

implementation

uses
  Markdown4D.Defines;

class function TMarkdownUrlSafety.IsDangerous(const Url: string): Boolean;
var
  Probe: string;
  Scheme: string;
  Prefix: string;
begin
  Probe := SchemeProbe(Url);

  for Scheme in DangerousSchemes do
  begin
    if Probe.StartsWith(Scheme) then
    begin
      Result := True;
      Exit;
    end;
  end;

  if not Probe.StartsWith(DataScheme) then
  begin
    Result := False;
    Exit;
  end;

  for Prefix in SafeDataPrefixes do
  begin
    if Probe.StartsWith(Prefix) then
    begin
      Result := False;
      Exit;
    end;
  end;

  Result := True;
end;

class function TMarkdownUrlSafety.Sanitized(const Url: string): string;
begin
  if IsDangerous(Url) then
  begin
    Result := '';
    Exit;
  end;

  Result := Url;
end;

class function TMarkdownUrlSafety.IsAllowed(const Url: string; const AllowedSchemes: TArray<string>): Boolean;
var
  Scheme: string;
  IsRelative: Boolean;
begin
  Result := False;
  if IsDangerous(Url) then
    Exit;

  Scheme := EffectiveScheme(Url);
  IsRelative := (Scheme.IsEmpty);
  Result := (IsRelative or IsListed(Scheme, AllowedSchemes));
end;

class function TMarkdownUrlSafety.NormalizedScheme(const Scheme: string): string;
var
  IsValid: Boolean;
begin
  Result := BareScheme(Scheme);

  IsValid := (IsSchemeName(Result));
  if not IsValid then
    raise EMarkdownError.CreateFmt(InvalidSchemeMessage, [Scheme]);
end;

// A browser drops tab, line feed and carriage return anywhere in a URL and other
// control characters and spaces at its ends. Dropping all of them everywhere is
// stricter, so a trick with them fails closed: "java&#9;script:x" and
// " JavaScript:x" are both judged as "javascript:". Only the leading characters
// matter, which keeps this cheap for documents with many links.
class function TMarkdownUrlSafety.SchemeProbe(const Url: string): string;
var
  Builder: TStringBuilder;
  Current: Char;
begin
  Builder := TStringBuilder.Create;
  try
    for Current in Url do
    begin
      if Builder.Length >= MaxProbeLength then
        Break;

      if Current > ' ' then
        Builder.Append(Current);
    end;

    Result := Builder.ToString.ToLowerInvariant;
  finally
    Builder.Free;
  end;
end;

// Entries are compared as BareScheme leaves them, so a list filled in directly
// with 'HTTPS' or 'https:' still means https. SameText compares ASCII letters
// without regard to the user's locale.
class function TMarkdownUrlSafety.IsListed(const Scheme: string; const AllowedSchemes: TArray<string>): Boolean;
var
  Entry: string;
  Listed: string;
  IsMatch: type of ((SameText(Listed, Scheme)));
begin
  Result := False;

  for Entry in AllowedSchemes do
  begin
    Listed := BareScheme(Entry);
    IsMatch := (SameText(Listed, Scheme));
    if IsMatch then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

class function TMarkdownUrlSafety.BareScheme(const Scheme: string): string;
var
  Trimmed: string;
  WithoutSeparator: string;
begin
  Trimmed := Scheme.Trim;
  WithoutSeparator := Trimmed.TrimRight([SchemeSeparator]);
  Result := WithoutSeparator.ToLowerInvariant;
end;

// A long made-up scheme must not pass for a relative path, so there is no
// fixed window here: the prefix runs to the first character that cannot be
// part of a scheme. Without a valid scheme before the first path, query or
// fragment character the destination is relative, and the result is empty.
class function TMarkdownUrlSafety.EffectiveScheme(const Url: string): string;
var
  Prefix: string;
  TerminatorIndex: type of (Prefix.IndexOfAny(SchemeTerminators));
  HasTerminator: Boolean;
  EndsAtSeparator: Boolean;
  Candidate: string;
begin
  Result := '';

  Prefix := SchemePrefix(Url);
  if IsProtocolRelative(Prefix) then
  begin
    Result := ProtocolRelativeScheme;
    Exit;
  end;

  TerminatorIndex := Prefix.IndexOfAny(SchemeTerminators);
  HasTerminator := (TerminatorIndex >= 0);
  if not HasTerminator then
    Exit;

  EndsAtSeparator := (Prefix.Chars[TerminatorIndex] = SchemeSeparator);
  if not EndsAtSeparator then
    Exit;

  Candidate := Prefix.Substring(0, TerminatorIndex);
  if IsSchemeName(Candidate) then
    Result := Candidate.ToLowerInvariant;
end;

// The characters that decide the scheme, with spaces and control characters
// left out as SchemeProbe does: everything up to and including the first one
// that cannot be part of a scheme name. A single leading separator does not
// end it, so a protocol-relative start is seen whole.
class function TMarkdownUrlSafety.SchemePrefix(const Url: string): string;
var
  Builder: TStringBuilder;
  Current: Char;
  IsIgnored: Boolean;
  IsFirstCharacter: Boolean;
  IsSchemeCharacter: type of ((CharInSet(Current, SchemeCharacters)));
  IsLeadingSeparator: Boolean;
  EndsPrefix: Boolean;
begin
  Builder := TStringBuilder.Create;
  try
    for Current in Url do
    begin
      IsIgnored := (Current <= ' ');
      if IsIgnored then
        Continue;

      Builder.Append(Current);

      IsFirstCharacter := (Builder.Length = 1);
      IsSchemeCharacter := (CharInSet(Current, SchemeCharacters));
      IsLeadingSeparator := (IsFirstCharacter and CharInSet(Current, PathSeparators));
      EndsPrefix := (not (IsSchemeCharacter or IsLeadingSeparator));
      if EndsPrefix then
        Break;
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TMarkdownUrlSafety.IsProtocolRelative(const Prefix: string): Boolean;
var
  IsLongEnough: Boolean;
  FirstIsSeparator: type of ((CharInSet(Prefix.Chars[0], PathSeparators)));
  SecondIsSeparator: type of ((CharInSet(Prefix.Chars[1], PathSeparators)));
begin
  Result := False;

  IsLongEnough := (Prefix.Length >= ProtocolRelativePrefixLength);
  if not IsLongEnough then
    Exit;

  FirstIsSeparator := (CharInSet(Prefix.Chars[0], PathSeparators));
  SecondIsSeparator := (CharInSet(Prefix.Chars[1], PathSeparators));
  Result := (FirstIsSeparator and SecondIsSeparator);
end;

// RFC 3986: an ASCII letter, then ASCII letters, digits, plus, minus and full stop.
class function TMarkdownUrlSafety.IsSchemeName(const Candidate: string): Boolean;
var
  StartsWithLetter: type of ((CharInSet(Candidate.Chars[0], SchemeLetters)));
  Current: Char;
  IsSchemeCharacter: type of ((CharInSet(Current, SchemeCharacters)));
begin
  Result := False;
  if Candidate.IsEmpty then
    Exit;

  StartsWithLetter := (CharInSet(Candidate.Chars[0], SchemeLetters));
  if not StartsWithLetter then
    Exit;

  for Current in Candidate do
  begin
    IsSchemeCharacter := (CharInSet(Current, SchemeCharacters));
    if not IsSchemeCharacter then
      Exit;
  end;

  Result := True;
end;

end.
