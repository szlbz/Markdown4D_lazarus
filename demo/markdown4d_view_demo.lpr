program markdown4d_view_demo;
{ A reader only: open a markdown file and scroll it.  Shows the viewer
  without an editor - built-in right-click menu, middle-click autoscroll and
  the find box all come with the control. }
{$mode delphiunicode}{$H+}

uses
  Interfaces, Forms,
  ViewMainForm;

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TViewForm, ViewDemoForm);
  Application.Run;
end.
