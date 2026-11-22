unit Markdown4D.Lcl.Register;
{ Puts the viewer and the editor on the component palette.

  Only a package that is installed calls this; an application that adds the
  source folders to its search path gets the same controls without them
  appearing in the tool palette. }

{$mode delphiunicode}{$H+}

interface

procedure Register;

implementation

uses
  Classes,
  Markdown4D.Lcl.Viewer,
  Markdown4D.Lcl.Editor;

const
  PalettePage = 'Markdown4D';

procedure Register;
begin
  RegisterComponents(PalettePage, [TMarkdownViewer, TMarkdownEditor]);
end;

end.
