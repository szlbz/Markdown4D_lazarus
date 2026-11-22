{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.DesignSample;

interface

type
  TMarkdownDesignSample = class
  public const
    Markdown =
      '# Markdown4D'#10#10 +
      'Native **CommonMark** and *GFM* rendering in ~~a browser~~ pure Delphi - ' +
      '[GDK Software](https://github.com/GDKsoftware/Markdown4D).'#10#10 +
      '- [x] Tables, task lists and `inline code`'#10 +
      '- [ ] Streaming text via *AppendMarkdown*'#10#10 +
      '| Feature | VCL | FMX |'#10 +
      '| --- | :-: | :-: |'#10 +
      '| Viewer | yes | yes |'#10 +
      '| Editor | yes | yes |'#10#10 +
      '```pascal'#10 +
      'const Html = TMarkdown.ToHtml(''**Hello**'');'#10 +
      '```'#10#10 +
      '> Tip: switch ThemePreset to Dark in the Object Inspector.';
  end;

implementation

end.
