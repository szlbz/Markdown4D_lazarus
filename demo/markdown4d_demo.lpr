program markdown4d_demo;
{ A live preview: the source of a markdown file on the left, the document on the
  right. }
{$mode delphiunicode}{$H+}

uses
  Interfaces, Forms,
  MainForm;

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, DemoForm);
  Application.Run;
end.
