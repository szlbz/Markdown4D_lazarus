{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Layout.Pointer;

{$SCOPEDENUMS ON}

interface

type
  TMarkdownPointer = record
    // Whether the primary mouse button is down right now, also when another
    // control (a splitter, a window edge) holds the mouse. Only Windows answers;
    // elsewhere this is False and a caller falls back to waiting for the pointer
    // to rest.
    class function IsPrimaryButtonDown: Boolean; static;
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Windows,
  Markdown4D.Compat.Str,
  character;
{$ENDIF}

class function TMarkdownPointer.IsPrimaryButtonDown: Boolean;
var
  PrimaryButton: Integer;
  ButtonsSwapped: Boolean;
begin
{$IFDEF MSWINDOWS}
  PrimaryButton := VK_LBUTTON;
  ButtonsSwapped := (GetSystemMetrics(SM_SWAPBUTTON) <> 0);
  if ButtonsSwapped then
    PrimaryButton := VK_RBUTTON;

  Result := (GetAsyncKeyState(PrimaryButton) < 0);
{$ELSE}
  Result := False;
{$ENDIF}
end;

end.
