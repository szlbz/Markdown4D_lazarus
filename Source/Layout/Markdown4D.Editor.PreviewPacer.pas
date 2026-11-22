{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Editor.PreviewPacer;

{$SCOPEDENUMS ON}

interface

type
  // How long the editor waits after the last edit before it updates its
  // preview. A preview that updates quickly follows the typing closely; one
  // that takes long, for a large document, waits for a longer pause, so the
  // update does not land between two keystrokes and stall the typing.
  TMarkdownPreviewPacer = record
  public
    const
      ShortestDelayMilliseconds = 60;
      LongestDelayMilliseconds = 1500;
      DelayPerUpdateMillisecond = 4;
    class function DelayAfter(const UpdateMilliseconds: Int64): Integer; static;
  end;

implementation

uses
  Math,
  Markdown4D.Compat.Str,
  character;

class function TMarkdownPreviewPacer.DelayAfter(const UpdateMilliseconds: Int64): Integer;
var
  Scaled: Int64;
begin
  Scaled := UpdateMilliseconds * DelayPerUpdateMillisecond;
  Result := EnsureRange(Scaled, ShortestDelayMilliseconds, LongestDelayMilliseconds);
end;

end.
