{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Editor.PreviewScroll;

{$SCOPEDENUMS ON}

// Where an editor scrolls the preview beside it. The sums live here,
// framework-neutral, so the VCL and FMX editors share them.

interface

type
  TMarkdownPreviewScroll = record
  public
    // The offset that keeps the editor's top line at the top of the preview,
    // unless the line from LineTop to LineBottom would then drop below its
    // bottom edge. The preview then scrolls on just far enough to show that
    // line, or its top when the line is taller than the view.
    class function OffsetShowingLine(const TopLineOffset, LineTop, LineBottom, ViewHeight: Single): Single; static;
  end;

implementation

uses
  Math,
  Markdown4D.Compat.Str,
  character;

class function TMarkdownPreviewScroll.OffsetShowingLine(const TopLineOffset, LineTop, LineBottom,
  ViewHeight: Single): Single;
var
  IsBelowView: Boolean;
begin
  Result := TopLineOffset;

  IsBelowView := (LineBottom > TopLineOffset + ViewHeight);
  if IsBelowView then
    Result := Min(LineTop, LineBottom - ViewHeight);
end;

end.
