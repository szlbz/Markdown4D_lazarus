{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Extensions.Math;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Extensions.Interfaces,
  Markdown4D.Compat.Str,
  character;

type
  // Registers the "$...$" and "$$...$$" syntax plus the ```math fence alias.
  // The math node kind itself, its HTML output and its markdown writer are
  // part of the core; this extension only turns the parsers on. UseGfm
  // includes it, so TMarkdown and the viewers recognise math out of the box.
  TMathExtension = class(TInterfacedObject, IMarkdownExtension)
  public
    procedure Setup(const Pipeline: IMarkdownPipelineBuilder);
  end;

implementation

uses
  Markdown4D.Defines,
  Markdown4D.Parser.Blocks,
  Markdown4D.Parser.Inlines;

procedure TMathExtension.Setup(const Pipeline: IMarkdownPipelineBuilder);
begin
  Pipeline.RegisterBlockParser(TMathBlockStarter.Create, Dollar, TMarkdownPriorities.MathBlockStart);
  Pipeline.RegisterInlineParser(TMathInlineParser.Create, Dollar, TMarkdownPriorities.MathInline);
end;

end.
