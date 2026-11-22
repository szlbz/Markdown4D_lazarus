unit ViewMainForm;
{ The viewer-only demo window: a markdown file list and a heading outline on
  the left, the rendered document on the right.  The file list shows every
  .md file of a directory (the program's directory at startup; the Dir button
  picks another).  Clicking a file opens it, clicking an outline entry jumps
  to that heading - both through public APIs of the control
  (Outline / ScrollToOutlineEntry). }

{$mode delphiunicode}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, StdCtrls, ComCtrls, Graphics,
  Dialogs, IniFiles, FileUtil, Math, LCLType,
  {$IFDEF MSWINDOWS}Registry, ShellAPI, Windows,{$ENDIF}
  Markdown4D.Theme,
  Markdown4D.Lcl.Viewer,
  Markdown4D.Extensions.Mermaid.BlockOverride;

type
  TViewForm = class(TForm)
  private
    FViewer: TMarkdownViewer;
    FFiles: TListBox;
    FOutline: TListBox;
    FLeft: TPanel;
    FLeftSplit: TSplitter;
    FSplitter: TSplitter;
    FStatus: TStatusBar;
    FBar: TPanel;
    FEntries: TArray<TMarkdownOutlineEntry>;
    FDirectory: string;
    FFileName: string;
    FDark: Boolean;
    procedure BuildUi;
    procedure SaveConfig;
    procedure LoadConfig;
    procedure LoadFileList(const Directory: string);
    procedure FillOutline;
    procedure OpenFile(const FileName: string);
    procedure HandleFileClick(Sender: TObject);
    procedure HandleOutlineClick(Sender: TObject);
    procedure HandleScroll(Sender: TObject);
    procedure HandleZoomChange(Sender: TObject);
    procedure HandleLinkClick(const Sender: TObject; const Url: string);
    procedure HandleOpen(Sender: TObject);
    procedure HandleAssociateMd(Sender: TObject);
    procedure HandlePickDirectory(Sender: TObject);
    procedure HandleToggleTheme(Sender: TObject);
    procedure HandleZoomIn(Sender: TObject);
    procedure HandleZoomOut(Sender: TObject);
    procedure HandleClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure ApplyTheme;
    procedure UpdateStatus;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
  end;

var
  ViewDemoForm: TViewForm;

implementation

const
  SampleFileName = 'sample.md';
  IndentStep = '    ';
  ConfigFileName = 'markdown4d_view.ini';
  SecWindow = 'Window';
  SecLayout = 'Layout';
  SecState = 'State';

constructor TViewForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Caption := 'Markdown4D Viewer';
  SetBounds(160, 160, 1120, 680);
  // enables ```mermaid fenced blocks (flowchart / sequence / pie)
  TMermaidBlockOverride.RegisterOverride;
  BuildUi;
  LoadConfig;
  ApplyTheme;
  // a file passed on the command line (Explorer double-click) wins over the
  // restored one; a file association launches us as "viewer.exe" "file.md"
  if (ParamCount > 0) and FileExists(ParamStr(1)) then
  begin
    FFileName := ExpandFileName(ParamStr(1));
    FDirectory := ExtractFileDir(FFileName);
  end;
  // the restored directory (or the program's) as the starting folder
  if FDirectory = '' then
    FDirectory := ExtractFilePath(Application.ExeName);
  LoadFileList(FDirectory);
  if (FFileName <> '') and FileExists(FFileName) then
    OpenFile(FFileName)
  else if FileExists(SampleFileName) then
    OpenFile(SampleFileName)
  else if FFiles.Items.Count > 0 then
    OpenFile(IncludeTrailingPathDelimiter(FDirectory) + FFiles.Items[0]);
end;

procedure TViewForm.SaveConfig;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ExtractFilePath(Application.ExeName) + ConfigFileName);
  try
    Ini.WriteInteger(SecWindow, 'Left', Left);
    Ini.WriteInteger(SecWindow, 'Top', Top);
    Ini.WriteInteger(SecWindow, 'Width', Width);
    Ini.WriteInteger(SecWindow, 'Height', Height);
    // the splitters read back from the aligned control sizes
    Ini.WriteInteger(SecLayout, 'LeftColumnWidth', FLeft.Width);
    Ini.WriteInteger(SecLayout, 'FilesPanelHeight', FFiles.Height);
    Ini.WriteString(SecState, 'Directory', FDirectory);
    Ini.WriteString(SecState, 'LastFile', FFileName);
    Ini.WriteInteger(SecState, 'Zoom', FViewer.Zoom);
    Ini.WriteBool(SecState, 'Dark', FDark);
  finally
    Ini.Free;
  end;
end;

procedure TViewForm.LoadConfig;
var
  Ini: TIniFile;
  NewLeft, NewTop, NewWidth, NewHeight: Integer;
  Work: TRect;
begin
  Ini := TIniFile.Create(ExtractFilePath(Application.ExeName) + ConfigFileName);
  try
    // the window bounds, clamped to the current work area
    NewLeft := Ini.ReadInteger(SecWindow, 'Left', Left);
    NewTop := Ini.ReadInteger(SecWindow, 'Top', Top);
    NewWidth := Ini.ReadInteger(SecWindow, 'Width', Width);
    NewHeight := Ini.ReadInteger(SecWindow, 'Height', Height);
    Work := Screen.WorkAreaRect;
    NewWidth := EnsureRange(NewWidth, 400, Work.Width);
    NewHeight := EnsureRange(NewHeight, 300, Work.Height);
    NewLeft := EnsureRange(NewLeft, Work.Left,
      Work.Left + Work.Width - NewWidth);
    NewTop := EnsureRange(NewTop, Work.Top,
      Work.Top + Work.Height - NewHeight);
    SetBounds(NewLeft, NewTop, NewWidth, NewHeight);

    // left column width and the files/outline split
    FLeft.Width := EnsureRange(Ini.ReadInteger(SecLayout, 'LeftColumnWidth',
      FLeft.Width), 120, 600);
    FFiles.Height := EnsureRange(Ini.ReadInteger(SecLayout, 'FilesPanelHeight',
      FFiles.Height), 60, ClientHeight - 80);

    FDirectory := Ini.ReadString(SecState, 'Directory', '');
    FFileName := Ini.ReadString(SecState, 'LastFile', '');
    FDark := Ini.ReadBool(SecState, 'Dark', False);
    FViewer.Zoom := EnsureRange(Ini.ReadInteger(SecState, 'Zoom',
      FViewer.Zoom), 50, 300);
  finally
    Ini.Free;
  end;
end;

procedure TViewForm.BuildUi;
var
  Button: TButton;
  NextLeft: Integer;
begin
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Height := 48;
  FBar.BevelOuter := bvNone;

  NextLeft := 8;

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.ShowHint:=True;
  Button.Caption := 'Open';
  Button.Hint:='打开md文档';
  Button.SetBounds(NextLeft, 6, 70, 36);
  Button.OnClick := HandleOpen;
  Inc(NextLeft, 76);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Dir';
  Button.Hint:='打开目录的md文档列表';
  Button.ShowHint:=True;
  Button.SetBounds(NextLeft, 6, 70, 36);
  Button.OnClick := HandlePickDirectory;
  Inc(NextLeft, 76);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'Dark';
  Button.Hint:='切换主题';
  Button.ShowHint:=True;
  Button.SetBounds(NextLeft, 6, 70, 36);
  Button.OnClick := HandleToggleTheme;
  Inc(NextLeft, 76);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'A-';
  Button.Hint:='字体尺寸-1';
  Button.SetBounds(NextLeft, 6, 40, 36);
  Button.ShowHint:=True;
  Button.OnClick := HandleZoomOut;
  Inc(NextLeft, 44);

  Button := TButton.Create(Self);
  Button.Parent := FBar;
  Button.Caption := 'A+';
  Button.SetBounds(NextLeft, 6, 40, 36);
  Button.Hint:='字体尺寸+1';
  Button.ShowHint:=True;
  Button.OnClick := HandleZoomIn;
  Inc(NextLeft, 44);

  //Button := TButton.Create(Self);
  //Button.Parent := FBar;
  //Button.Caption := 'Assoc .md';
  //Button.SetBounds(NextLeft, 6, 100, 36);
  //Button.OnClick := HandleAssociateMd;
  //Inc(NextLeft, 82);

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  FStatus.SimpleText := 'Ready';

  OnClose := HandleClose;

  FViewer := TMarkdownViewer.Create(Self);
  FViewer.Parent := Self;
  FViewer.Align := alClient;
  FViewer.OnLinkClick := HandleLinkClick;
  FViewer.OnScroll := HandleScroll;
  FViewer.OnZoomChange := HandleZoomChange;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alLeft;
  FSplitter.Width := 5;

  // the left column: files on top, outline below
  FLeft := TPanel.Create(Self);
  FLeft.Parent := Self;
  FLeft.Align := alLeft;
  FLeft.Width := 240;
  FLeft.BevelOuter := bvNone;

  FOutline := TListBox.Create(FLeft);
  FOutline.Parent := FLeft;
  FOutline.Align := alClient;
  FOutline.OnClick := HandleOutlineClick;

  FLeftSplit := TSplitter.Create(FLeft);
  FLeftSplit.Parent := FLeft;
  FLeftSplit.Align := alTop;
  FLeftSplit.Height := 5;

  FFiles := TListBox.Create(FLeft);
  FFiles.Parent := FLeft;
  FFiles.Align := alTop;
  FFiles.Height := 200;
  FFiles.OnClick := HandleFileClick;
end;

procedure TViewForm.LoadFileList(const Directory: string);
var
  Files: TStringList;
  I: Integer;
begin
  FDirectory := Directory;
  Files := FindAllFiles(Directory, '*.md;*.markdown', False) as TStringList;
  try
    Files.Sort;
    FFiles.Items.BeginUpdate;
    try
      // display names only; HandleFileClick resolves against FDirectory
      FFiles.Items.Assign(Files);
      for I := 0 to FFiles.Items.Count - 1 do
        FFiles.Items[I] := ExtractFileName(FFiles.Items[I]);
    finally
      FFiles.Items.EndUpdate;
    end;
  finally
    Files.Free;
  end;
end;

procedure TViewForm.HandleFileClick(Sender: TObject);
begin
  if FFiles.ItemIndex < 0 then
    Exit;
  OpenFile(IncludeTrailingPathDelimiter(FDirectory) + FFiles.Items[FFiles.ItemIndex]);
end;

procedure TViewForm.HandleClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  SaveConfig;
end;

procedure TViewForm.ApplyTheme;
begin
  if FDark then
    FViewer.ThemePreset := TMarkdownThemePreset.Dark
  else
    FViewer.ThemePreset := TMarkdownThemePreset.Light;
end;

procedure TViewForm.FillOutline;
var
  Entry: TMarkdownOutlineEntry;
  Indent: string;
  I, L: Integer;
begin
  FEntries := FViewer.Outline;
  FOutline.Items.BeginUpdate;
  try
    FOutline.Items.Clear;
    for I := 0 to Length(FEntries) - 1 do
    begin
      Entry := FEntries[I];
      Indent := '';
      for L := 2 to Entry.Level do
        Indent := Indent + IndentStep;
      // Objects carries the entry's index into FEntries
      FOutline.Items.AddObject(Indent + Entry.Caption, TObject(PtrUInt(I)));
    end;
  finally
    FOutline.Items.EndUpdate;
  end;
end;

procedure TViewForm.OpenFile(const FileName: string);
var
  NameIndex: Integer;
begin
  FViewer.DocumentFolder := ExtractFileDir(ExpandFileName(FileName));
  FViewer.LoadFromFile(FileName);
  FFileName := FileName;
  Caption := 'Markdown4D Viewer - ' + ExtractFileName(FileName);
  FillOutline;
  // keep the file list in step with the open document
  NameIndex := FFiles.Items.IndexOf(ExtractFileName(FileName));
  if NameIndex >= 0 then
    FFiles.ItemIndex := NameIndex;
  UpdateStatus;
end;

procedure TViewForm.HandleOutlineClick(Sender: TObject);
var
  Index: Integer;
begin
  if FOutline.ItemIndex < 0 then
    Exit;
  Index := PtrUInt(FOutline.Items.Objects[FOutline.ItemIndex]);
  if (Index >= 0) and (Index < Length(FEntries)) then
    FViewer.ScrollToOutlineEntry(FEntries[Index]);
  UpdateStatus;
end;

procedure TViewForm.UpdateStatus;
begin
  if FViewer.ContentHeight > 0 then
    FStatus.SimpleText := Format('%s  %d%%  (%d headings)',
      [ExtractFileName(FFileName),
       Round(100 * (FViewer.ScrollOffset + FViewer.ClientHeight) /
        FViewer.ContentHeight), Length(FEntries)])
  else
    FStatus.SimpleText := 'empty';
end;

procedure TViewForm.HandleScroll(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TViewForm.HandleZoomChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TViewForm.HandleLinkClick(const Sender: TObject; const Url: string);
begin
  FStatus.SimpleText := 'link: ' + Url;
end;

procedure TViewForm.HandleOpen(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := 'Markdown|*.md;*.markdown;*.txt|All files|*.*';
    Dialog.InitialDir := FDirectory;
    if Dialog.Execute then
      OpenFile(Dialog.FileName);
  finally
    Dialog.Free;
  end;
end;

procedure TViewForm.HandleAssociateMd(Sender: TObject);
{$IFDEF MSWINDOWS}
const
  ProgId = 'Markdown4D.Viewer.md';
var
  Reg: TRegistry;
  Exe: string;
begin
  Exe := ParamStr(0);
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;

    // .md -> our ProgId (current user only, no elevation needed)
    if Reg.OpenKey('Software\Classes\.md', True) then
    begin
      Reg.WriteString('', ProgId);
      Reg.CloseKey;
    end;

    if Reg.OpenKey('Software\Classes\' + ProgId, True) then
    begin
      Reg.WriteString('', 'Markdown Document');
      Reg.CloseKey;
    end;

    if Reg.OpenKey('Software\Classes\' + ProgId + '\DefaultIcon', True) then
    begin
      Reg.WriteString('', '"' + Exe + '",0');
      Reg.CloseKey;
    end;

    if Reg.OpenKey('Software\Classes\' + ProgId + '\shell\open\command', True) then
    begin
      Reg.WriteString('', '"' + Exe + '" "%1"');
      Reg.CloseKey;
    end;

    // tell Explorer to refresh file associations
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
    FStatus.SimpleText := '.md associated with ' + Exe;
  finally
    Reg.Free;
  end;
end;
{$ELSE}
begin
  FStatus.SimpleText := 'file association is Windows-only';
end;
{$ENDIF}

procedure TViewForm.HandlePickDirectory(Sender: TObject);
var
  Dialog: TSelectDirectoryDialog;
begin
  Dialog := TSelectDirectoryDialog.Create(Self);
  try
    Dialog.InitialDir := FDirectory;
    if Dialog.Execute then
    begin
      LoadFileList(Dialog.FileName);
      if FFiles.Items.Count > 0 then
        OpenFile(IncludeTrailingPathDelimiter(Dialog.FileName) + FFiles.Items[0])
      else
        FStatus.SimpleText := 'no markdown files in ' + Dialog.FileName;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TViewForm.HandleToggleTheme(Sender: TObject);
begin
  FDark := not FDark;
  ApplyTheme;
end;

procedure TViewForm.HandleZoomIn(Sender: TObject);
begin
  FViewer.Zoom := FViewer.Zoom + 10;
end;

procedure TViewForm.HandleZoomOut(Sender: TObject);
begin
  FViewer.Zoom := FViewer.Zoom - 10;
end;

end.
