{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Defines;

{$SCOPEDENUMS ON}

interface

uses
  SysUtils,
  Markdown4D.Compat.Str,
  character;

const
  // Line endings and whitespace
  LineFeed = #10;
  CarriageReturn = #13;
  Tab = #9;
  Space = ' ';

  // Markdown syntax characters
  Backslash = '\';
  Asterisk = '*';
  Underscore = '_';
  Backtick = '`';
  Tilde = '~';
  OpenBracket = '[';
  CloseBracket = ']';
  OpenParen = '(';
  CloseParen = ')';
  ExclamationMark = '!';
  Dollar = '$';

  // HTML-significant characters
  Ampersand = '&';
  LessThan = '<';
  GreaterThan = '>';

  // CommonMark structural limits
  MaxHeadingLevel = 6;
  MinFenceLength = 3;

  // Autolink and URL prefixes
  HttpSchemePrefix = 'http://';
  HttpsSchemePrefix = 'https://';
  WwwPrefix = 'www.';
  UrlSchemeSeparator = '://';

type
  TMarkdownDialect = (CommonMark, Gfm);

  EMarkdownError = class(Exception);

  EMarkdownNotImplemented = class(EMarkdownError);

implementation

end.
