unit MainForm;
{ The demo window: source on the left, rendered document on the right.  The
  editor drives the preview through AttachPreview, so the two panes scroll in
  step and every keystroke reaches the reader through the built-in pacer - no
  hand-rolled timer is needed any more.  The controls are built in code, so
  the demo is one file to read rather than a form plus a resource. }

{$mode delphiunicode}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, StdCtrls, ComCtrls, Graphics,
  Dialogs, LCLType,
  Markdown4D.Theme,
  Markdown4D.Lcl.Viewer,
  Markdown4D.Lcl.Editor,
  Markdown4D.Extensions.Mermaid.BlockOverride;

type
  TMainForm = class(TForm)
  private
    FEditor: TMarkdownEditor;
    FViewer: TMarkdownViewer;
    FSplitter: TSplitter;
    FStatus: TStatusBar;
    FBar: TPanel;
    FFileName: string;
    FDark: Boolean;
    procedure BuildUi;
    procedure LoadSample;
    procedure OpenFile(const FileName: string);
    procedure HandleEditorChange(const Sender: TObject);
    procedure HandleCaretChange(Sender: TObject);
    procedure HandleEditorScroll(Sender: TObject);
    procedure HandleSyncScroll(Sender: TObject; const SourceLine: Integer);
    procedure HandleZoomChange(Sender: TObject);
    procedure HandleLinkClick(const Sender: TObject; const Url: string);
    procedure HandleOpen(Sender: TObject);
    procedure HandleSave(Sender: TObject);
    procedure HandleToggleTheme(Sender: TObject);
    procedure HandleUndo(Sender: TObject);
    procedure HandleRedo(Sender: TObject);
    procedure HandleEditorZoomIn(Sender: TObject);
    procedure HandleEditorZoomOut(Sender: TObject);
    procedure HandleViewerZoomIn(Sender: TObject);
    procedure HandleViewerZoomOut(Sender: TObject);
    procedure ApplyTheme;
    procedure UpdateStatus;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
  end;

var
  DemoForm: TMainForm;

implementation

const
  SampleFileName = 'sample.md';

constructor TMainForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Caption := 'Markdown4D for Lazarus';
  SetBounds(120, 120, 1100, 720);
  // enables ```mermaid fenced blocks (flowchart / sequence / pie)
  TMermaidBlockOverride.RegisterOverride;
  BuildUi;
  ApplyTheme;
  if FileExists(SampleFileName) then
    OpenFile(SampleFileName)
  else
    LoadSample;
end;

destructor TMainForm.Destroy;
begin
  inherited Destroy;
end;

procedure TMainForm.BuildUi;
var
  Button: TButton;
  NextLeft: Integer;
begin
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Height := 36;
  FBar.BevelOuter := bvNone;

  NextLeft := 8;

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Open';
  Button.SetBounds(NextLeft, 6, 78, 26);
  Button.OnClick := HandleOpen;
  Inc(NextLeft, 84);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Save';
  Button.SetBounds(NextLeft, 6, 78, 26);
  Button.OnClick := HandleSave;
  Inc(NextLeft, 84);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Dark';
  Button.SetBounds(NextLeft, 6, 78, 26);
  Button.OnClick := HandleToggleTheme;
  Inc(NextLeft, 84);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Undo';
  Button.SetBounds(NextLeft, 6, 62, 26);
  Button.OnClick := HandleUndo;
  Inc(NextLeft, 66);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Redo';
  Button.SetBounds(NextLeft, 6, 62, 26);
  Button.OnClick := HandleRedo;
  Inc(NextLeft, 68);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Src A-';
  Button.SetBounds(NextLeft, 6, 62, 26);
  Button.OnClick := HandleEditorZoomOut;
  Inc(NextLeft, 66);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Src A+';
  Button.SetBounds(NextLeft, 6, 62, 26);
  Button.OnClick := HandleEditorZoomIn;
  Inc(NextLeft, 66);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Doc A-';
  Button.SetBounds(NextLeft, 6, 62, 26);
  Button.OnClick := HandleViewerZoomOut;
  Inc(NextLeft, 66);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Doc A+';
  Button.SetBounds(NextLeft, 6, 62, 26);
  Button.OnClick := HandleViewerZoomIn;
  Inc(NextLeft, 66);

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  FStatus.SimpleText := 'Ready';

  FViewer := TMarkdownViewer.Create(Self);
  FViewer.Parent := Self;
  FViewer.Align := alRight;
  FViewer.Width := 560;
  FViewer.OnLinkClick := HandleLinkClick;
  FViewer.OnZoomChange := HandleZoomChange;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alRight;
  FSplitter.Width := 5;

  FEditor := TMarkdownEditor.Create(Self);
  FEditor.Parent := Self;
  FEditor.Align := alClient;
  FEditor.OnChange := HandleEditorChange;
  FEditor.OnCaretChange := HandleCaretChange;
  FEditor.OnScroll := HandleEditorScroll;
  FEditor.OnZoomChange := HandleZoomChange;
  FEditor.OnSyncScroll := HandleSyncScroll;

  // The editor drives the preview: text, two-way scrolling and a pacer that
  // keeps typing smooth.  No hand-rolled timer, no manual copy of the text.
  FEditor.AttachPreview(FViewer);
end;

procedure TMainForm.ApplyTheme;
begin
  if FDark then
  begin
    FEditor.ThemePreset := TMarkdownThemePreset.Dark;
    FViewer.ThemePreset := TMarkdownThemePreset.Dark;
  end
  else
  begin
    FEditor.ThemePreset := TMarkdownThemePreset.Light;
    FViewer.ThemePreset := TMarkdownThemePreset.Light;
  end;
end;

procedure TMainForm.LoadSample;
begin
  FFileName := '';
  FEditor.Text :=
    '# Markdown4D for Lazarus' + #10 + #10 +
    'Type on the left, read on the right - the panes scroll together.' + #10 + #10 +
    '## What this demo shows' + #10 + #10 +
    '- Soft wrapping and syntax colours in the editor' + #10 +
    '- Live preview through `AttachPreview`, two-way scroll sync' + #10 +
    '- A built-in right-click menu on both panes' + #10 +
    '- Middle-click autoscroll pans either pane' + #10 +
    '- Headings and list items fold from the gutter' + #10 + #10 +
    '> Select some text here, then press Ctrl+Shift+C to copy the markdown.' + #10 + #10 +
    '```pascal' + #10 +
    'FEditor.AttachPreview(FViewer);' + #10 +
    '```' + #10;
  Caption := 'Markdown4D for Lazarus - untitled';
  UpdateStatus;
end;

procedure TMainForm.OpenFile(const FileName: string);
begin
  FEditor.LoadFromFile(FileName);
  FViewer.DocumentFolder := ExtractFileDir(ExpandFileName(FileName));
  FFileName := FileName;
  Caption := 'Markdown4D for Lazarus - ' + ExtractFileName(FileName);
  UpdateStatus;
end;

procedure TMainForm.HandleEditorChange(const Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
begin
  FStatus.SimpleText := Format('%d lines', [FEditor.LineCount]);
end;

procedure TMainForm.HandleCaretChange(Sender: TObject);
begin
  FStatus.SimpleText := Format('caret %d, line %d', [FEditor.CaretPosition,
    FEditor.FirstVisibleSourceLine]);
end;

procedure TMainForm.HandleEditorScroll(Sender: TObject);
begin
  // The preview already follows on its own; the status bar just reports it.
end;

procedure TMainForm.HandleSyncScroll(Sender: TObject; const SourceLine: Integer);
begin
  FStatus.SimpleText := Format('top line %d', [SourceLine]);
end;

procedure TMainForm.HandleZoomChange(Sender: TObject);
begin
  FStatus.SimpleText := Format('zoom %d%% / %d%%',
    [FEditor.Zoom, FViewer.Zoom]);
end;

procedure TMainForm.HandleLinkClick(const Sender: TObject; const Url: string);
begin
  FStatus.SimpleText := 'link: ' + Url;
end;

procedure TMainForm.HandleOpen(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := 'Markdown|*.md;*.markdown;*.txt|All files|*.*';
    if Dialog.Execute then
      OpenFile(Dialog.FileName);
  finally
    Dialog.Free;
  end;
end;

procedure TMainForm.HandleSave(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := 'Markdown|*.md';
    Dialog.FileName := FFileName;
    if Dialog.Execute then
    begin
      FEditor.SaveToFile(Dialog.FileName);
      FFileName := Dialog.FileName;
      Caption := 'Markdown4D for Lazarus - ' + ExtractFileName(Dialog.FileName);
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TMainForm.HandleToggleTheme(Sender: TObject);
begin
  FDark := not FDark;
  ApplyTheme;
end;

procedure TMainForm.HandleUndo(Sender: TObject);
begin
  FEditor.Undo;
end;

procedure TMainForm.HandleRedo(Sender: TObject);
begin
  FEditor.Redo;
end;

procedure TMainForm.HandleEditorZoomIn(Sender: TObject);
begin
  FEditor.ZoomIn;
end;

procedure TMainForm.HandleEditorZoomOut(Sender: TObject);
begin
  FEditor.ZoomOut;
end;

procedure TMainForm.HandleViewerZoomIn(Sender: TObject);
begin
  FViewer.Zoom := FViewer.Zoom + 10;
end;

procedure TMainForm.HandleViewerZoomOut(Sender: TObject);
begin
  FViewer.Zoom := FViewer.Zoom - 10;
end;

end.
