{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Parser.Interfaces;

interface

type
  IMarkdownIncrementalParser = interface
    ['{35E81D1A-0056-4A57-B97E-F893032B2BE1}']
    procedure Append(const Chunk: string);
    procedure ReplaceRange(const StartIndex, Count: Integer; const Replacement: string);
    function ToHtml: string;
  end;

implementation

end.
