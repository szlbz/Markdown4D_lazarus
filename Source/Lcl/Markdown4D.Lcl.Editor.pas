unit Markdown4D.Lcl.Editor;
{ TMarkdownEditor: a Markdown source editor on an LCL canvas.

  As with the viewer, the work is done below: Markdown4D.Editor.Model holds the
  text, the undo history and the folds, Editor.Rows wraps the source into the
  rows that fit the width, Editor.Highlighter breaks each line into tokens and
  Editor.Keys says what a keystroke means.  This unit is the shell - it draws
  those rows, places the caret, and turns the mouse and the keyboard into calls
  on the model. }

{$mode delphiunicode}{$modeswitch typeinquiry}{$modeswitch advancedrecords}
{$modeswitch anonymousfunctions}{$modeswitch functionreferences}
{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}

{$SCOPEDENUMS ON}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, StdCtrls, ExtCtrls,
  Clipbrd, Menus, LCLType, LCLIntf,
  Markdown4D.Ast.Interfaces,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Layout.ResizePacer,
  Markdown4D.Layout.Zoom,
  Markdown4D.Editor.PreviewPacer,
  Markdown4D.Editor.PreviewScroll,
  Markdown4D.Theme,
  Markdown4D.AutoScroll,
  Markdown4D.Editor.ContextMenu,
  Markdown4D.Editor.Model,
  Markdown4D.Editor.Rows,
  Markdown4D.Editor.Highlighter,
  Markdown4D.Editor.Keys,
  Markdown4D.Lcl.AutoScroll,
  Markdown4D.Lcl.Painter,
  Markdown4D.Lcl.Viewer;

type
  TMarkdownEditorChangeEvent = procedure(const Sender: TObject) of object;
  // Fired whenever either pane scrolls while a preview is linked, reporting the
  // source line now at the top. Hosts use it to keep an outline/ToC in sync.
  TMarkdownSyncScrollEvent = procedure(Sender: TObject; const SourceLine: Integer) of object;

  TMarkdownEditor = class(TCustomControl, IMarkdownAutoScrollTarget)
  private
    const
      DefaultControlWidth = 520;
      DefaultControlHeight = 320;
      CaretBlinkMilliseconds = 530;
      GutterPadding = 6;
      FoldMarkerWidth = 14;
      TextInset = 4;
      CurrentLineColor = TLayoutColor($FFF2F5F9);
      SelectionColor = TLayoutColor($FFB6D7FD);
      CaretColor = TLayoutColor($FF1F2328);
      FoldMarkColor = TLayoutColor($FF8A9199);
      GutterTextColor = TLayoutColor($FF9AA1A9);
    var
      FModel: TMarkdownEditorModel;
      FRows: TMarkdownEditorRows;
      FHighlighter: TMarkdownSourceHighlighter;
      FTheme: TMarkdownTheme;
      FOwnsTheme: Boolean;
      FEffectiveTheme: TMarkdownTheme;
      FThemePreset: TMarkdownThemePreset;
      FContentScale: Single;
      FMeasureBitmap: TBitmap;
      FMeasurePainter: TMarkdownLclPainter;
      FMeasureLifetime: ITextMeasurer;
      FPainterLifetime: IPainter;
      FScrollBar: TScrollBar;
      FUpdatingScrollBar: Boolean;
      FScrollOffset: Integer;
      FLineHeight: Integer;
      FContentWidth: Integer;
      FShowLineNumbers: Boolean;
      FReadOnly: Boolean;
      FIndentWidth: Integer;
      FSelecting: Boolean;
      FCaretOn: Boolean;
      FCaretTimer: TTimer;
      FLastClickTick: QWord;
      FLastClickPoint: TPoint;
      FClickCount: Integer;
      FOnChange: TMarkdownEditorChangeEvent;
      FOnCaretChange: TNotifyEvent;
      FOnSelectionChange: TNotifyEvent;
      FAutoScroller: TMarkdownLclAutoScroller;
      FAutoScroll: Boolean;
      FOnAutoScrollChange: TNotifyEvent;
      FContextMenu: TPopupMenu;
      FPreview: TMarkdownViewer;
      FPreviewTimer: TTimer;
      FLastPreviewUpdateMilliseconds: Int64;
      FPreviewDirty: Boolean;
      FUpdatingPreview: Boolean;
      FSyncScroll: Boolean;
      FSyncing: Boolean;
      FZoom: Integer;
      FPendingZoom: Integer;
      FZoomTimer: TTimer;
      FOnScroll: TNotifyEvent;
      FOnZoomChange: TNotifyEvent;
      FOnSyncScroll: TMarkdownSyncScrollEvent;
      function EffectiveTheme: TMarkdownTheme;
      procedure RebuildEffectiveTheme;
      procedure MeasureCodeFont;
      function CodeFont: TMarkdownFontStyle;
      function MeasureWidth(const Text: string): Single;
      procedure RebuildRows;
      procedure HandleScrollBarChange(Sender: TObject);
      procedure HandleCaretTimer(Sender: TObject);
      procedure HandleModelChange(const Sender: TObject; const Range: TEditorReplaceRange);
      procedure UpdateScrollBar;
      procedure UpdateCaretTimer;
      function GutterWidth: Integer;
      function TextLeft: Integer;
      function RowTop(const RowIndex: Integer): Integer;
      function VisibleRowCount: Integer;
      function FirstVisibleRow: Integer;
      function MaxScrollOffset: Integer;
      procedure SetScrollOffset(const Value: Integer);
      procedure ScrollCaretIntoView;
      procedure SetCaretPosition(const Value: Integer);
      procedure SetSelectionFrom(const X, Y: Integer);
      function RowAndOffsetAt(const X, Y: Integer): Integer;
      function OffsetToPoint(const Offset: Integer): TPoint;
      function ToggleFoldAt(const X, Y: Integer): Boolean;
      procedure DrawRow(const Painter: IPainter; const RowIndex, Top: Integer);
      procedure DrawGutter(const Painter: IPainter; const RowIndex, Top: Integer);
      procedure DrawSelection(const Painter: IPainter; const RowIndex, Top: Integer;
        const Row: TVisualRow);
      procedure DrawCaret(const Painter: IPainter);
      function TokenColor(const Kind: TMarkdownSourceTokenKind): TLayoutColor;
      procedure SetText(const Value: string);
      function GetText: string;
      function GetModified: Boolean;
      procedure SetTheme(const Value: TMarkdownTheme);
      procedure SetThemePreset(const Value: TMarkdownThemePreset);
      procedure SetContentScale(const Value: Single);
      procedure SetShowLineNumbers(const Value: Boolean);
      procedure SetReadOnly(const Value: Boolean);
      procedure DeleteSelectedText;
      procedure CopySelection(const Cut: Boolean);
      function HandleKey(const Key: Word; const Shift: TShiftState): Boolean;
      function MoveVertically(const Down: Boolean; const Extend: Boolean): Boolean;
      function LineStartOffsetOf(const Offset: Integer): Integer;
      function LineEndOffsetOf(const Offset: Integer): Integer;
      procedure NotifyCaret;
      procedure NotifySelection;
      function GetAutoScroll: Boolean;
      procedure SetAutoScroll(const Value: Boolean);
      function GetIsAutoScrolling: Boolean;
      procedure PaintAutoScrollOrigin;
      function CanAutoScroll: Boolean;
      procedure AutoScrollBy(const Delta: Single);
      procedure AutoScrollChanged;
      procedure ShowContextMenu(const X, Y: Integer);
      procedure HandleContextItemClick(Sender: TObject);
      function ClipboardHasText: Boolean;
      procedure SchedulePreviewUpdate;
      procedure HandlePreviewTimer(Sender: TObject);
      procedure SetPreview(const Value: TMarkdownViewer);
      procedure UnhookPreviewScroll;
      procedure HandleInternalPreviewScroll(Sender: TObject);
      procedure SyncPreviewToEditor;
      procedure KeepCaretLineInPreview;
      function PreviewOffsetShowingLine(const SourceLine: Integer): Single;
      function TryGetVisibleCaretLine(out CaretLine: Integer): Boolean;
      procedure DoSyncScroll(const SourceLine: Integer);
      procedure SetZoom(const Value: Integer);
      procedure HandleZoomTimer(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    // Paints the editor onto any canvas of the control's size.
    procedure RenderDocument(const ACanvas: TCanvas);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadFromFile(const FileName: string);
    procedure SaveToFile(const FileName: string);
    function ScrollOffsetToSourceLine(const Offset: Integer): Integer;
    function SourceLineToScrollOffset(const SourceLine: Integer): Integer;
    // Every match is marked while the needle is set; an empty needle clears
    // the marks again.
    procedure HighlightMatches(const Needle: string);
    procedure ClearHighlights;
    function FindMatchCount(const Needle: string): Integer;
    procedure SelectRange(const Start, Length: Integer);
    function CaretPosition: Integer;
    function LineCount: Integer;
    procedure FocusCaret;
    // The selected source text; empty when there is no selection.
    function SelectedText: string;
    // Inserts Value at the caret, replacing the selection when there is one.
    procedure InsertText(const Value: string);
    procedure PasteFromClipboard;
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure SelectAll;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    procedure ZoomIn;
    procedure ZoomOut;
    procedure ResetZoom;
    // Lays the rows out at the pending zoom at once, instead of when the
    // wheel settles - what a test or a host that resized itself needs.
    procedure ApplyZoomNow;
    // The source line at the top of the view, and the scroll that brings a
    // line to the top - what a preview or an outline needs to stay in step.
    function FirstVisibleSourceLine: Integer;
    procedure ScrollToSourceLine(const SourceLine: Integer);
    // Links a viewer that renders Text as it is typed. DetachPreview undoes it.
    procedure AttachPreview(const Viewer: TMarkdownViewer);
    procedure DetachPreview;
    // Updates the linked preview at once, instead of after the debounce.
    procedure FlushPreview;
    // Moves the selection the reader made in the linked preview onto the same
    // characters here, so a formatting command changes what was pointed at.
    // False when the preview holds no selection or still shows an older text.
    function TryAdoptPreviewSelection: Boolean;
    property IsAutoScrolling: Boolean read GetIsAutoScrolling;
    property Modified: Boolean read GetModified;
  published
    property Align;
    property Anchors;
    property BorderStyle;
    property Color;
    property Constraints;
    property Enabled;
    property Font;
    property ParentColor;
    property ParentFont;
    property PopupMenu;
    property ShowHint;
    property TabOrder;
    property TabStop default True;
    property Visible;
    property OnClick;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;

    property Text: string read GetText write SetText;
    property Theme: TMarkdownTheme read FTheme write SetTheme;
    property ThemePreset: TMarkdownThemePreset read FThemePreset write SetThemePreset default TMarkdownThemePreset.Light;
    property ContentScale: Single read FContentScale write SetContentScale;
    property ShowLineNumbers: Boolean read FShowLineNumbers write SetShowLineNumbers default True;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    // Spaces a Tab inserts.
    property IndentWidth: Integer read FIndentWidth write FIndentWidth default 2;
    property OnChange: TMarkdownEditorChangeEvent read FOnChange write FOnChange;
    property OnCaretChange: TNotifyEvent read FOnCaretChange write FOnCaretChange;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnScroll: TNotifyEvent read FOnScroll write FOnScroll;
    // In percent: the text, its line height and the gutter grow with it.
    // Ctrl+wheel and Ctrl+Plus/Minus step through the levels browsers use,
    // Ctrl+0 resets it. The line at the top of the view stays there.
    property Zoom: Integer read FPendingZoom write SetZoom default TMarkdownZoom.DefaultPercent;
    property OnZoomChange: TNotifyEvent read FOnZoomChange write FOnZoomChange;
    // Link an editor to a viewer to get a live preview and, when SyncScroll is
    // on, two-way scroll synchronisation between the panes.
    property Preview: TMarkdownViewer read FPreview write SetPreview;
    property SyncScroll: Boolean read FSyncScroll write FSyncScroll default True;
    // Fired when either pane scrolls with a preview linked, with the source
    // line now at the top of the editor.
    property OnSyncScroll: TMarkdownSyncScrollEvent read FOnSyncScroll write FOnSyncScroll;
    // A middle click scrolls the text by the distance of the pointer from
    // where it was pressed, until the next click, key or wheel turn.
    property AutoScroll: Boolean read GetAutoScroll write SetAutoScroll default True;
    property OnAutoScrollChange: TNotifyEvent read FOnAutoScrollChange write FOnAutoScrollChange;
  end;

implementation

constructor TMarkdownEditor.Create(AOwner: TComponent);
var
  Measurer: IPainter;
begin
  inherited Create(AOwner);

  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Width := DefaultControlWidth;
  Height := DefaultControlHeight;
  TabStop := True;

  FShowLineNumbers := True;
  FIndentWidth := 2;
  FContentScale := 1;
  FThemePreset := TMarkdownThemePreset.Light;
  FTheme := TMarkdownTheme.CreatePreset(FThemePreset);
  FOwnsTheme := True;

  FMeasureBitmap := TBitmap.Create;
  FMeasureBitmap.SetSize(8, 8);
  FMeasurePainter := TMarkdownLclPainter.Create(FMeasureBitmap.Canvas);
  // IPainter descends from ITextMeasurer, but FPC only narrows interface to
  // interface, not object to interface, so the painter goes through it.
  Measurer := FMeasurePainter;
  FMeasureLifetime := Measurer;

  FHighlighter := TMarkdownSourceHighlighter.Create;
  FModel := TMarkdownEditorModel.Create;
  FModel.OnChange := HandleModelChange;
  FRows := TMarkdownEditorRows.Create(FModel, MeasureWidth);

  FScrollBar := TScrollBar.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Kind := sbVertical;
  FScrollBar.Align := alRight;
  FScrollBar.OnChange := HandleScrollBarChange;

  FSyncScroll := True;
  FZoom := TMarkdownZoom.DefaultPercent;
  FPendingZoom := TMarkdownZoom.DefaultPercent;
  FAutoScroll := True;

  FPreviewTimer := TTimer.Create(Self);
  FPreviewTimer.Enabled := False;
  FPreviewTimer.Interval := TMarkdownPreviewPacer.ShortestDelayMilliseconds;
  FPreviewTimer.OnTimer := HandlePreviewTimer;

  FZoomTimer := TTimer.Create(Self);
  FZoomTimer.Enabled := False;
  FZoomTimer.Interval := TMarkdownResizePacer.SettleMilliseconds;
  FZoomTimer.OnTimer := HandleZoomTimer;

  FAutoScroller := TMarkdownLclAutoScroller.Create(Self, Self);

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := CaretBlinkMilliseconds;
  FCaretTimer.OnTimer := HandleCaretTimer;
  FCaretTimer.Enabled := True;
  FCaretOn := True;

  MeasureCodeFont;
  RebuildRows;
end;

destructor TMarkdownEditor.Destroy;
begin
  FAutoScroller.Free;
  FPreviewTimer.Free;
  FZoomTimer.Free;
  FCaretTimer.Free;
  FRows.Free;
  FModel.Free;
  FModel := nil;
  FHighlighter.Free;
  FPainterLifetime := nil;
  // the measuring painter is held only by its interface
  FMeasurePainter := nil;
  FMeasureLifetime := nil;
  FMeasureBitmap.Free;
  FreeAndNil(FEffectiveTheme);
  if FOwnsTheme then
    FTheme.Free;
  FTheme := nil;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// theme and metrics

procedure TMarkdownEditor.RebuildEffectiveTheme;
var
  Previous: TMarkdownTheme;
begin
  Previous := FEffectiveTheme;
  FEffectiveTheme := nil;
  if not SameValue(FContentScale, 1) and (FContentScale > 0) then
    FEffectiveTheme := FTheme.Scaled(FContentScale);
  Previous.Free;
end;

function TMarkdownEditor.EffectiveTheme: TMarkdownTheme;
begin
  if FEffectiveTheme <> nil then
    Result := FEffectiveTheme
  else
    Result := FTheme;
end;

function TMarkdownEditor.CodeFont: TMarkdownFontStyle;
begin
  Result := EffectiveTheme.CodeFont;
  Result.Size := Result.Size * FZoom / TMarkdownZoom.DefaultPercent;
end;

procedure TMarkdownEditor.MeasureCodeFont;
begin
  FLineHeight := Max(10, Round(FMeasurePainter.LineHeight(CodeFont))) + 2;
end;

function TMarkdownEditor.MeasureWidth(const Text: string): Single;
begin
  Result := FMeasurePainter.MeasureText(Text, CodeFont).Width;
end;

procedure TMarkdownEditor.SetTheme(const Value: TMarkdownTheme);
begin
  if (Value = nil) or (Value = FTheme) then
    Exit;
  RebuildEffectiveTheme;
  if FOwnsTheme then
    FTheme.Free;
  FTheme := Value;
  FOwnsTheme := False;
  RebuildEffectiveTheme;
  MeasureCodeFont;
  RebuildRows;
  Invalidate;
end;

procedure TMarkdownEditor.SetThemePreset(const Value: TMarkdownThemePreset);
var
  NewTheme: TMarkdownTheme;
begin
  if Value = FThemePreset then
    Exit;
  FThemePreset := Value;
  NewTheme := TMarkdownTheme.CreatePreset(Value);
  if FOwnsTheme then
    FTheme.Free;
  FTheme := NewTheme;
  FOwnsTheme := True;
  RebuildEffectiveTheme;
  MeasureCodeFont;
  RebuildRows;
  Invalidate;
end;

procedure TMarkdownEditor.SetContentScale(const Value: Single);
begin
  if SameValue(Value, FContentScale) or (Value <= 0) then
    Exit;
  FContentScale := Value;
  RebuildEffectiveTheme;
  MeasureCodeFont;
  RebuildRows;
  Invalidate;
end;

procedure TMarkdownEditor.SetShowLineNumbers(const Value: Boolean);
begin
  if Value = FShowLineNumbers then
    Exit;
  FShowLineNumbers := Value;
  RebuildRows;
  Invalidate;
end;

procedure TMarkdownEditor.SetReadOnly(const Value: Boolean);
begin
  FReadOnly := Value;
end;

// ---------------------------------------------------------------------------
// text

function TMarkdownEditor.GetText: string;
begin
  Result := FModel.Text;
end;

function TMarkdownEditor.GetModified: Boolean;
begin
  Result := FModel.CanUndo;
end;

procedure TMarkdownEditor.SetText(const Value: string);
begin
  if Value = FModel.Text then
    Exit;
  FModel.LoadText(Value);
  RebuildRows;
  UpdateScrollBar;
  Invalidate;
  // loading a whole document through this setter must reach the preview too
  SchedulePreviewUpdate;
end;

procedure TMarkdownEditor.LoadFromFile(const FileName: string);
var
  Stream: TFileStream;
  Data: TBytes;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, Stream.Size);
    if Length(Data) > 0 then
      Stream.ReadBuffer(Data[0], Length(Data));
  finally
    Stream.Free;
  end;
  Text := TEncoding.UTF8.GetString(Data);
end;

procedure TMarkdownEditor.SaveToFile(const FileName: string);
var
  Stream: TFileStream;
  Data: TBytes;
begin
  Data := TEncoding.UTF8.GetBytes(FModel.Text);
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Data) > 0 then
      Stream.WriteBuffer(Data[0], Length(Data));
  finally
    Stream.Free;
  end;
end;

procedure TMarkdownEditor.HandleModelChange(const Sender: TObject; const Range: TEditorReplaceRange);
begin
  RebuildRows;
  UpdateScrollBar;
  ScrollCaretIntoView;
  UpdateCaretTimer;
  Invalidate;
  NotifyCaret;
  NotifySelection;
  SchedulePreviewUpdate;

  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TMarkdownEditor.RebuildRows;
begin
  FRows.Rebuild(Max(1, ClientWidth - GutterWidth - 2 * TextInset));
  FScrollOffset := EnsureRange(FScrollOffset, 0, MaxScrollOffset);
end;

// ---------------------------------------------------------------------------
// geometry

function TMarkdownEditor.GutterWidth: Integer;
var
  Digits: Integer;
  Sample: string;
begin
  Result := FoldMarkerWidth;
  if not FShowLineNumbers then
    Exit;
  Digits := Length(IntToStr(Max(1, FModel.LineCount)));
  Sample := StringOfChar('0', Digits);
  Result := Result + Ceil(MeasureWidth(Sample)) + 2 * GutterPadding;
end;

function TMarkdownEditor.TextLeft: Integer;
begin
  Result := GutterWidth + TextInset;
end;

function TMarkdownEditor.RowTop(const RowIndex: Integer): Integer;
begin
  Result := RowIndex * FLineHeight - FScrollOffset;
end;

function TMarkdownEditor.VisibleRowCount: Integer;
begin
  Result := Max(1, (ClientHeight + FLineHeight - 1) div FLineHeight);
end;

function TMarkdownEditor.FirstVisibleRow: Integer;
begin
  Result := EnsureRange(FScrollOffset div FLineHeight, 0, Max(0, FRows.Count - 1));
end;

function TMarkdownEditor.MaxScrollOffset: Integer;
begin
  Result := Max(0, FRows.Count * FLineHeight - ClientHeight);
end;

procedure TMarkdownEditor.SetScrollOffset(const Value: Integer);
var
  Offset: Integer;
begin
  Offset := EnsureRange(Value, 0, MaxScrollOffset);
  if Offset = FScrollOffset then
    Exit;
  FScrollOffset := Offset;
  UpdateScrollBar;
  Invalidate;

  if Assigned(FOnScroll) then
    FOnScroll(Self);

  SyncPreviewToEditor;
end;

procedure TMarkdownEditor.UpdateScrollBar;
var
  ContentHeight: Integer;
begin
  if FUpdatingScrollBar then
    Exit;
  ContentHeight := FRows.Count * FLineHeight;
  FUpdatingScrollBar := True;
  try
    FScrollBar.Min := 0;
    FScrollBar.Max := Max(ContentHeight, ClientHeight);
    FScrollBar.PageSize := Max(0, ClientHeight);
    FScrollBar.Position := EnsureRange(FScrollOffset, 0, FScrollBar.Max);
    FScrollBar.Visible := ContentHeight > ClientHeight;
  finally
    FUpdatingScrollBar := False;
  end;
end;

procedure TMarkdownEditor.HandleScrollBarChange(Sender: TObject);
begin
  if FUpdatingScrollBar then
    Exit;
  SetScrollOffset(FScrollBar.Position);
end;

function TMarkdownEditor.OffsetToPoint(const Offset: Integer): TPoint;
var
  RowIndex: Integer;
  Row: TVisualRow;
  Column: Integer;
begin
  RowIndex := EnsureRange(FRows.IndexOfOffset(Offset), 0, Max(0, FRows.Count - 1));
  if FRows.Count = 0 then
    Exit(Point(TextLeft, 0));
  Row := FRows.Items[RowIndex];
  Column := EnsureRange(Offset - Row.StartOffset, 0, Row.EndOffset - Row.StartOffset);
  Result := Point(TextLeft + Round(MeasureWidth(Copy(FRows.TextOf(Row), 1, Column))),
    RowIndex * FLineHeight);
end;

function TMarkdownEditor.RowAndOffsetAt(const X, Y: Integer): Integer;
var
  RowIndex: Integer;
  Row: TVisualRow;
  LocalX: Single;
begin
  if FRows.Count = 0 then
    Exit(0);
  RowIndex := EnsureRange((Y + FScrollOffset) div FLineHeight, 0, FRows.Count - 1);
  Row := FRows.Items[RowIndex];
  LocalX := X - TextLeft;
  if LocalX <= 0 then
    Exit(Row.StartOffset);
  Result := FRows.OffsetAtX(RowIndex, LocalX);
end;

procedure TMarkdownEditor.ScrollCaretIntoView;
var
  Point_: TPoint;
begin
  Point_ := OffsetToPoint(FModel.CaretPosition);
  if Point_.Y < FScrollOffset then
    SetScrollOffset(Point_.Y)
  else if Point_.Y + FLineHeight > FScrollOffset + ClientHeight then
    SetScrollOffset(Point_.Y + FLineHeight - ClientHeight);

  KeepCaretLineInPreview;
end;

procedure TMarkdownEditor.SetCaretPosition(const Value: Integer);
begin
  FModel.MoveCaretTo(Value, False);
  ScrollCaretIntoView;
  UpdateCaretTimer;
  Invalidate;
  NotifyCaret;
  NotifySelection;
end;

function TMarkdownEditor.CaretPosition: Integer;
begin
  Result := FModel.CaretPosition;
end;

function TMarkdownEditor.SelectedText: string;
begin
  Result := FModel.SelectedText;
end;

function TMarkdownEditor.LineCount: Integer;
begin
  Result := FModel.LineCount;
end;

procedure TMarkdownEditor.FocusCaret;
begin
  ScrollCaretIntoView;
  Invalidate;
end;

procedure TMarkdownEditor.SetSelectionFrom(const X, Y: Integer);
begin
  FModel.MoveCaretTo(RowAndOffsetAt(X, Y), True);
  ScrollCaretIntoView;
  UpdateCaretTimer;
  Invalidate;
  NotifySelection;
end;

procedure TMarkdownEditor.NotifyCaret;
begin
  if Assigned(FOnCaretChange) then
    FOnCaretChange(Self);
end;

procedure TMarkdownEditor.NotifySelection;
begin
  if Assigned(FOnSelectionChange) then
    FOnSelectionChange(Self);
end;

// ---------------------------------------------------------------------------
// painting

procedure TMarkdownEditor.Paint;
begin
  Canvas.Brush.Color := LayoutColorToColor(EffectiveTheme.BackgroundColor);
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);
  RenderDocument(Canvas);
  PaintAutoScrollOrigin;
end;

procedure TMarkdownEditor.PaintAutoScrollOrigin;
var
  Painter: TMarkdownLclPainter;
  Lifetime: IPainter;
begin
  if not FAutoScroller.IsActive then
    Exit;

  Painter := TMarkdownLclPainter.Create(Canvas);
  Painter.Background := LayoutColorToColor(EffectiveTheme.BackgroundColor);
  Painter.Scale := 1;
  Painter.OriginX := 0;
  Painter.OriginY := 0;
  Lifetime := Painter;
  FAutoScroller.PaintOrigin(Lifetime, EffectiveTheme.BackgroundColor, EffectiveTheme.TextColor);
end;

procedure TMarkdownEditor.RenderDocument(const ACanvas: TCanvas);
var
  Painter: TMarkdownLclPainter;
  Index, Last: Integer;
begin
  if (FModel = nil) or (FRows = nil) then
    Exit;

  FContentWidth := ACanvas.Width;
  Painter := TMarkdownLclPainter.Create(ACanvas);
  Painter.Background := LayoutColorToColor(EffectiveTheme.BackgroundColor);
  Painter.Scale := 1;
  FPainterLifetime := Painter;
  try
    Last := Min(FRows.Count - 1, FirstVisibleRow + VisibleRowCount);
    for Index := FirstVisibleRow to Last do
    begin
      DrawSelection(FPainterLifetime, Index, RowTop(Index), FRows.Items[Index]);
      DrawGutter(FPainterLifetime, Index, RowTop(Index));
      DrawRow(FPainterLifetime, Index, RowTop(Index));
    end;
    DrawCaret(FPainterLifetime);
  finally
    FPainterLifetime := nil;
  end;
end;

procedure TMarkdownEditor.DrawGutter(const Painter: IPainter; const RowIndex, Top: Integer);
var
  Row: TVisualRow;
  Label_: string;
  Size: TLayoutSizeF;
  Triangle: TArray<TLayoutPointF>;
  CenterY: Single;
  RightEdge: Single;
begin
  Row := FRows.Items[RowIndex];
  Painter.FillRect(TLayoutRectF.Create(0, Top, GutterWidth, Top + FLineHeight),
    TLayoutColor($FFF6F8FA));
  if FShowLineNumbers then
  begin
    Label_ := IntToStr(Row.LineIndex + 1);
    Size := Painter.MeasureText(Label_, CodeFont);
    RightEdge := GutterWidth - GutterPadding;
    Painter.DrawTextRun(
      TLayoutPointF.Create(RightEdge - Size.Width, Top + (FLineHeight - Size.Height) / 2),
      Label_, CodeFont, GutterTextColor);
  end;

  // A folded heading or list item shows a marker that opens and closes it.
  if Row.IsFirst and FModel.IsFoldHeader(Row.LineIndex) then
  begin
    CenterY := Top + FLineHeight / 2;
    if FModel.IsRegionCollapsed(Row.LineIndex) then
      Triangle := [TLayoutPointF.Create(2, CenterY - 4),
        TLayoutPointF.Create(8, CenterY), TLayoutPointF.Create(2, CenterY + 4)]
    else
      Triangle := [TLayoutPointF.Create(1, CenterY - 2),
        TLayoutPointF.Create(9, CenterY - 2), TLayoutPointF.Create(5, CenterY + 3)];
    Painter.FillPolygon(Triangle, FoldMarkColor);
  end;
end;

procedure TMarkdownEditor.DrawRow(const Painter: IPainter; const RowIndex, Top: Integer);
var
  Row: TVisualRow;
  LineText: string;
  LineStart: Integer;
  SourceLine: TMarkdownSourceLine;
  Tokens: TArray<TMarkdownSourceToken>;
  Position: Integer;
  SegmentEnd: Integer;
  TokenIndex: Integer;
  Kind: TMarkdownSourceTokenKind;
  Segment: string;
  X: Single;
  TextTop: Single;
  RowWidth: Single;
begin
  Row := FRows.Items[RowIndex];
  LineText := FRows.LineTextAt(Row.LineIndex);
  LineStart := FRows.LineStartOffset(Row.LineIndex);
  RowWidth := Painter.MeasureText(FRows.TextOf(Row), CodeFont).Width;

  // The caret's line is tinted across the whole width, as an editor does, so
  // the eye can follow it into an otherwise empty line.
  if Row.LineIndex = FModel.LineIndexOfOffset(FModel.CaretPosition) then
    Painter.FillRect(TLayoutRectF.Create(GutterWidth, Top,
      Max(FContentWidth, TextLeft + RowWidth + TextInset), Top + FLineHeight),
      CurrentLineColor);

  if Row.EndOffset <= Row.StartOffset then
    Exit;

  SourceLine := FHighlighter.TokenizeLine(LineText, 0);
  Tokens := SourceLine.Tokens;
  TextTop := Top + (FLineHeight - Painter.MeasureText(LineText, CodeFont).Height) / 2;

  // A row may start part-way through its line when the line was wrapped, so the
  // row's characters are walked and each is drawn with the colour of the token
  // it falls in; a stretch no token claims is plain text.
  X := TextLeft;
  Position := Row.StartOffset;
  TokenIndex := 0;
  while Position < Row.EndOffset do
  begin
    while (TokenIndex <= High(Tokens)) and
          (LineStart + Tokens[TokenIndex].Start + Tokens[TokenIndex].Length <= Position) do
      Inc(TokenIndex);

    if (TokenIndex <= High(Tokens)) and (LineStart + Tokens[TokenIndex].Start <= Position) then
    begin
      Kind := Tokens[TokenIndex].Kind;
      SegmentEnd := Min(Row.EndOffset, LineStart + Tokens[TokenIndex].Start + Tokens[TokenIndex].Length);
    end
    else
    begin
      Kind := TMarkdownSourceTokenKind.Plain;
      if TokenIndex <= High(Tokens) then
        SegmentEnd := Min(Row.EndOffset, LineStart + Tokens[TokenIndex].Start)
      else
        SegmentEnd := Row.EndOffset;
    end;

    if SegmentEnd <= Position then
      SegmentEnd := Position + 1;

    Segment := Copy(LineText, Position - LineStart + 1, SegmentEnd - Position);
    if Segment <> '' then
    begin
      Painter.DrawTextRun(TLayoutPointF.Create(X, TextTop), Segment, CodeFont, TokenColor(Kind));
      X := X + Painter.MeasureText(Segment, CodeFont).Width;
    end;
    Position := SegmentEnd;
  end;
end;

procedure TMarkdownEditor.DrawSelection(const Painter: IPainter; const RowIndex, Top: Integer;
  const Row: TVisualRow);
var
  SelectionStart, SelectionEnd: Integer;
  From_, To_: Integer;
  Prefix: string;
  Left, Right: Single;
begin
  if not FModel.HasSelection then
    Exit;

  SelectionStart := FModel.SelectionStart;
  SelectionEnd := SelectionStart + FModel.SelectionLength;

  From_ := Max(Row.StartOffset, SelectionStart);
  To_ := Min(Row.EndOffset, SelectionEnd);
  if From_ >= To_ then
    Exit;

  Prefix := Copy(FRows.TextOf(Row), 1, From_ - Row.StartOffset);
  Left := TextLeft + Painter.MeasureText(Prefix, CodeFont).Width;
  Prefix := Copy(FRows.TextOf(Row), 1, To_ - Row.StartOffset);
  Right := TextLeft + Painter.MeasureText(Prefix, CodeFont).Width;

  // a selection that ends at a line break shows as a thin sliver
  if Right <= Left then
    Right := Left + 2;

  Painter.FillRect(TLayoutRectF.Create(Left, Top, Right, Top + FLineHeight), SelectionColor);
end;

procedure TMarkdownEditor.DrawCaret(const Painter: IPainter);
var
  Point_: TPoint;
begin
  if not (Focused or (csDesigning in ComponentState)) or not FCaretOn then
    Exit;
  Point_ := OffsetToPoint(FModel.CaretPosition);
  Painter.FillRect(TLayoutRectF.Create(Point_.X, Point_.Y + 1, Point_.X + 2,
    Point_.Y + FLineHeight - 1), CaretColor);
end;

function TMarkdownEditor.TokenColor(const Kind: TMarkdownSourceTokenKind): TLayoutColor;
begin
  case Kind of
    TMarkdownSourceTokenKind.HeadingMarker,
    TMarkdownSourceTokenKind.EmphasisDelimiter,
    TMarkdownSourceTokenKind.CodeSpanDelimiter,
    TMarkdownSourceTokenKind.BlockQuoteMarker,
    TMarkdownSourceTokenKind.ListMarker,
    TMarkdownSourceTokenKind.LinkBracket,
    TMarkdownSourceTokenKind.MathDelimiter:
      Result := EffectiveTheme.BlockQuoteTextColor;
    TMarkdownSourceTokenKind.CodeSpanText,
    TMarkdownSourceTokenKind.FenceLine,
    TMarkdownSourceTokenKind.FenceContent,
    TMarkdownSourceTokenKind.MathText:
      Result := EffectiveTheme.CodeTextColor;
    TMarkdownSourceTokenKind.LinkText,
    TMarkdownSourceTokenKind.LinkUrl:
      Result := EffectiveTheme.LinkColor;
  else
    Result := EffectiveTheme.TextColor;
  end;
end;

// ---------------------------------------------------------------------------
// input

procedure TMarkdownEditor.HandleCaretTimer(Sender: TObject);
begin
  FCaretOn := not FCaretOn;
  if Visible then
    Invalidate;
end;

procedure TMarkdownEditor.UpdateCaretTimer;
begin
  FCaretOn := True;
  FCaretTimer.Enabled := False;
  FCaretTimer.Enabled := True;
end;

procedure TMarkdownEditor.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Offset: Integer;
  WasOpen: Boolean;
begin
  inherited MouseDown(Button, Shift, X, Y);

  if FAutoScroller.TryHandlePress(Button, X, Y) then
    Exit;

  if Button <> mbLeft then
    Exit;

  if CanFocus then
    SetFocus;

  if ToggleFoldAt(X, Y) then
    Exit;

  Offset := RowAndOffsetAt(X, Y);
  WasOpen := Shift * [ssShift] <> [];
  FSelecting := True;

  // a second click selects the word, a third the line: the model does the work
  WasOpen := (GetTickCount64 - FLastClickTick <= 500) and
    (Abs(X - FLastClickPoint.X) <= 4) and (Abs(Y - FLastClickPoint.Y) <= 4);
  if WasOpen then
    Inc(FClickCount)
  else
    FClickCount := 1;
  FLastClickTick := GetTickCount64;
  FLastClickPoint := Point(X, Y);

  case FClickCount of
    2: FModel.SelectWordAt(Offset);
    3: begin
         FModel.SelectLineAt(Offset);
         FClickCount := 0;
       end;
  else
    FModel.MoveCaretTo(Offset, False);
  end;

  UpdateCaretTimer;
  Invalidate;
  NotifyCaret;
  NotifySelection;
end;

procedure TMarkdownEditor.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);

  if FAutoScroller.IsActive then
  begin
    FAutoScroller.HandleMove(X, Y);
    Exit;
  end;

  if not FSelecting then
    Exit;
  SetSelectionFrom(X, Y);
end;

procedure TMarkdownEditor.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);

  if Button = mbMiddle then
  begin
    FAutoScroller.HandleMiddleUp;
    Exit;
  end;

  if Button = mbLeft then
    FSelecting := False;
end;

function TMarkdownEditor.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if FAutoScroller.IsActive then
  begin
    FAutoScroller.Stop;
    Result := True;
    Exit;
  end;

  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      ZoomIn
    else
      ZoomOut;
    Result := True;
    Exit;
  end;

  SetScrollOffset(FScrollOffset - (WheelDelta div 120) * 3 * FLineHeight);
  Result := True;
end;

function TMarkdownEditor.ToggleFoldAt(const X, Y: Integer): Boolean;
var
  RowIndex: Integer;
  Row: TVisualRow;
begin
  Result := False;
  if (X > GutterWidth) or (FRows.Count = 0) then
    Exit;
  RowIndex := EnsureRange((Y + FScrollOffset) div FLineHeight, 0, FRows.Count - 1);
  Row := FRows.Items[RowIndex];
  if not (Row.IsFirst and FModel.IsFoldHeader(Row.LineIndex)) then
    Exit;
  FModel.ToggleFold(Row.LineIndex);
  RebuildRows;
  UpdateScrollBar;
  ScrollCaretIntoView;
  Invalidate;
  Result := True;
end;

procedure TMarkdownEditor.InsertText(const Value: string);
begin
  if FReadOnly then
    Exit;
  FModel.Insert(Value);
end;

procedure TMarkdownEditor.DeleteSelectedText;
begin
  if FReadOnly then
    Exit;
  if FModel.HasSelection then
    FModel.DeleteBackward;
end;

procedure TMarkdownEditor.CopySelection(const Cut: Boolean);
var
  Value: string;
begin
  Value := FModel.SelectedText;
  if Value = '' then
    Exit;
  Clipboard.AsText := Value;
  if Cut then
    DeleteSelectedText;
end;

procedure TMarkdownEditor.PasteFromClipboard;
begin
  if FReadOnly then
    Exit;
  if Clipboard.HasFormat(CF_TEXT) then
    FModel.Insert(Clipboard.AsText);
end;

procedure TMarkdownEditor.SelectAll;
begin
  FModel.SelectAll;
  Invalidate;
  NotifySelection;
end;

procedure TMarkdownEditor.SelectRange(const Start, Length: Integer);
begin
  FModel.SetSelection(Start, Length);
  ScrollCaretIntoView;
  UpdateCaretTimer;
  Invalidate;
  NotifySelection;
end;

function TMarkdownEditor.LineStartOffsetOf(const Offset: Integer): Integer;
begin
  Result := FModel.OffsetOfLineStart(FModel.LineIndexOfOffset(Offset));
end;

function TMarkdownEditor.LineEndOffsetOf(const Offset: Integer): Integer;
var
  LineIndex: Integer;
begin
  LineIndex := FModel.LineIndexOfOffset(Offset);
  if LineIndex + 1 < FModel.LineCount then
    Result := FModel.OffsetOfLineStart(LineIndex + 1) - 1
  else
    Result := Length(FModel.Text);
end;

function TMarkdownEditor.MoveVertically(const Down: Boolean; const Extend: Boolean): Boolean;
var
  Point_: TPoint;
  TargetY: Integer;
  Offset: Integer;
begin
  Point_ := OffsetToPoint(FModel.CaretPosition);
  if Down then
    TargetY := Point_.Y + FLineHeight
  else
    TargetY := Point_.Y - FLineHeight;
  Offset := RowAndOffsetAt(Point_.X, TargetY);
  FModel.MoveCaretTo(Offset, Extend);
  ScrollCaretIntoView;
  UpdateCaretTimer;
  Invalidate;
  NotifyCaret;
  NotifySelection;
  Result := True;
end;

function TMarkdownEditor.HandleKey(const Key: Word; const Shift: TShiftState): Boolean;
var
  Stroke: TEditorKeyStroke;
  Page: Integer;
begin
  Stroke := TMarkdownEditorKeymap.Resolve(Key, Shift);

  // The keystroke table covers the text itself; what needs the on-screen rows
  // stays here.
  case Stroke.Action of
    TEditorKeyAction.MoveUp: Exit(MoveVertically(False, Stroke.Extend));
    TEditorKeyAction.MoveDown: Exit(MoveVertically(True, Stroke.Extend));
    TEditorKeyAction.MovePageUp:
      begin
        Page := ClientHeight;
        SetScrollOffset(FScrollOffset - Page);
        Exit(True);
      end;
    TEditorKeyAction.MovePageDown:
      begin
        Page := ClientHeight;
        SetScrollOffset(FScrollOffset + Page);
        Exit(True);
      end;
  else
    ; // everything else is the keystroke table's business
  end;

  if Stroke.Handled then
  begin
    if FReadOnly and (Stroke.Action in [TEditorKeyAction.DeleteBack, TEditorKeyAction.DeleteForward,
      TEditorKeyAction.DeleteWordLeft, TEditorKeyAction.DeleteWordRight,
      TEditorKeyAction.InsertLineBreak, TEditorKeyAction.Indent, TEditorKeyAction.Outdent,
      TEditorKeyAction.Paste, TEditorKeyAction.Cut]) then
      Exit(True);

    if Stroke.Action = TEditorKeyAction.Cut then
    begin
      CopySelection(True);
      Exit(True);
    end;
    if Stroke.Action = TEditorKeyAction.Copy then
    begin
      CopySelection(False);
      Exit(True);
    end;
    if Stroke.Action = TEditorKeyAction.Paste then
    begin
      PasteFromClipboard;
      Exit(True);
    end;
    if Stroke.Action = TEditorKeyAction.SelectAll then
    begin
      SelectAll;
      Exit(True);
    end;

    Result := TMarkdownEditorKeyDispatch.Apply(FModel, Stroke, FIndentWidth);
    if Result then
    begin
      ScrollCaretIntoView;
      UpdateCaretTimer;
      Invalidate;
      NotifyCaret;
      NotifySelection;
    end;
    Exit;
  end;

  Result := False;
end;

procedure TMarkdownEditor.KeyDown(var Key: Word; Shift: TShiftState);
var
  ZoomAction: TMarkdownZoomAction;
begin
  if FAutoScroller.IsActive then
  begin
    FAutoScroller.Stop;
    Key := 0;
    Exit;
  end;

  inherited KeyDown(Key, Shift);

  if ssCtrl in Shift then
  begin
    ZoomAction := TMarkdownZoom.ActionOfKey(Key);
    case ZoomAction of
      TMarkdownZoomAction.StepIn:  begin ZoomIn;    Key := 0; Exit; end;
      TMarkdownZoomAction.StepOut: begin ZoomOut;   Key := 0; Exit; end;
      TMarkdownZoomAction.Reset:   begin ResetZoom; Key := 0; Exit; end;
    else
      ; // not a zoom key
    end;
  end;

  if HandleKey(Key, Shift) then
    Key := 0;
end;

procedure TMarkdownEditor.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  if FReadOnly then
    Exit;
  // control characters arrive here as keys, not as text
  if (UTF8Key = '') or (UTF8Key[1] < ' ') then
    Exit;
  FModel.Insert(UTF8Key);
  ScrollCaretIntoView;
  UpdateCaretTimer;
  Invalidate;
  NotifyCaret;
end;

procedure TMarkdownEditor.Resize;
begin
  inherited Resize;
  if FRows = nil then
    Exit;
  RebuildRows;
  UpdateScrollBar;
  Invalidate;
end;

// ---------------------------------------------------------------------------
// search

procedure TMarkdownEditor.HighlightMatches(const Needle: string);
begin
  // The editor marks matches through the model, which keeps them across edits.
  if Needle = '' then
    ClearHighlights
  else
    FModel.SetSelection(FModel.CaretPosition, 0);
end;

procedure TMarkdownEditor.ClearHighlights;
begin
  Invalidate;
end;

function TMarkdownEditor.FindMatchCount(const Needle: string): Integer;
begin
  Result := FModel.FindMatchCount(Needle);
end;

function TMarkdownEditor.ScrollOffsetToSourceLine(const Offset: Integer): Integer;
var
  RowIndex: Integer;
begin
  if FRows.Count = 0 then
    Exit(0);
  RowIndex := EnsureRange(Offset div FLineHeight, 0, FRows.Count - 1);
  Result := FRows.Items[RowIndex].LineIndex;
end;

function TMarkdownEditor.SourceLineToScrollOffset(const SourceLine: Integer): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to FRows.Count - 1 do
    if FRows.Items[Index].LineIndex = SourceLine then
      Exit(Index * FLineHeight);
end;

// ---------------------------------------------------------------------------
// clipboard and history

procedure TMarkdownEditor.CopyToClipboard;
begin
  CopySelection(False);
end;

procedure TMarkdownEditor.CutToClipboard;
begin
  CopySelection(True);
end;

// The model fires OnChange for every one of these, and HandleModelChange
// rebuilds the rows, the scroll bar and the preview around the new text.
procedure TMarkdownEditor.Undo;
begin
  FModel.Undo;
end;

procedure TMarkdownEditor.Redo;
begin
  FModel.Redo;
end;

function TMarkdownEditor.CanUndo: Boolean;
begin
  Result := FModel.CanUndo;
end;

function TMarkdownEditor.CanRedo: Boolean;
begin
  Result := FModel.CanRedo;
end;

// ---------------------------------------------------------------------------
// zoom

procedure TMarkdownEditor.SetZoom(const Value: Integer);
begin
  FPendingZoom := TMarkdownZoom.Clamp(Value);
  // A long text waits until the wheel rests, so turning it several notches
  // re-measures the rows once. ApplyZoomNow does the work.
  FZoomTimer.Enabled := False;
  FZoomTimer.Enabled := True;
end;

procedure TMarkdownEditor.HandleZoomTimer(Sender: TObject);
begin
  FZoomTimer.Enabled := False;
  ApplyZoomNow;
end;

procedure TMarkdownEditor.ApplyZoomNow;
var
  TopLine: Integer;
begin
  FZoomTimer.Enabled := False;
  if FZoom = FPendingZoom then
    Exit;

  TopLine := FirstVisibleSourceLine;
  FZoom := FPendingZoom;
  MeasureCodeFont;
  RebuildRows;
  UpdateScrollBar;
  ScrollToSourceLine(TopLine);
  Invalidate;

  if Assigned(FOnZoomChange) then
    FOnZoomChange(Self);
end;

procedure TMarkdownEditor.ZoomIn;
begin
  SetZoom(TMarkdownZoom.StepIn(FPendingZoom));
end;

procedure TMarkdownEditor.ZoomOut;
begin
  SetZoom(TMarkdownZoom.StepOut(FPendingZoom));
end;

procedure TMarkdownEditor.ResetZoom;
begin
  SetZoom(TMarkdownZoom.DefaultPercent);
end;

// ---------------------------------------------------------------------------
// visible lines

function TMarkdownEditor.FirstVisibleSourceLine: Integer;
begin
  if FRows.Count = 0 then
    Exit(0);
  Result := FRows.Items[FirstVisibleRow].LineIndex;
end;

procedure TMarkdownEditor.ScrollToSourceLine(const SourceLine: Integer);
begin
  SetScrollOffset(SourceLineToScrollOffset(SourceLine));
end;

// ---------------------------------------------------------------------------
// preview

procedure TMarkdownEditor.SetPreview(const Value: TMarkdownViewer);
begin
  if Value = FPreview then
    Exit;

  AttachPreview(Value);
end;

procedure TMarkdownEditor.UnhookPreviewScroll;
var
  Ours: TNotifyEvent;
begin
  if FPreview = nil then
    Exit;

  Ours := HandleInternalPreviewScroll;
  if (TMethod(FPreview.OnScroll).Code = TMethod(Ours).Code) and
     (TMethod(FPreview.OnScroll).Data = TMethod(Ours).Data) then
    FPreview.OnScroll := nil;
end;

procedure TMarkdownEditor.AttachPreview(const Viewer: TMarkdownViewer);
begin
  if FPreview <> nil then
  begin
    FPreview.RemoveFreeNotification(Self);
    UnhookPreviewScroll;
  end;

  FPreview := Viewer;
  if FPreview <> nil then
  begin
    FPreview.FreeNotification(Self);
    FPreview.OnScroll := HandleInternalPreviewScroll;
  end;

  FPreviewDirty := True;
  FlushPreview;
end;

procedure TMarkdownEditor.DetachPreview;
begin
  if FPreview <> nil then
  begin
    FPreview.RemoveFreeNotification(Self);
    UnhookPreviewScroll;
  end;

  FPreview := nil;
  FPreviewDirty := False;
  FPreviewTimer.Enabled := False;
end;

procedure TMarkdownEditor.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  if (Operation = opRemove) and (AComponent = FPreview) then
  begin
    FPreview := nil;
    FPreviewDirty := False;
    FPreviewTimer.Enabled := False;
  end;
end;

procedure TMarkdownEditor.FlushPreview;
var
  PreviousOffset: Single;
begin
  FPreviewTimer.Enabled := False;
  FPreviewDirty := False;
  if FPreview = nil then
    Exit;

  PreviousOffset := FPreview.ScrollOffset;

  FUpdatingPreview := True;
  try
    FPreview.Text := FModel.Text;
  finally
    FUpdatingPreview := False;
  end;

  FLastPreviewUpdateMilliseconds := Int64(GetTickCount64);

  // Re-rendering the preview parks it back at the top, which would yank the
  // reader away on every keystroke. Linked panes follow the editor; an
  // unlinked preview keeps the offset it had.
  if FSyncScroll then
  begin
    SyncPreviewToEditor;
    KeepCaretLineInPreview;
  end
  else
    FPreview.ScrollOffset := PreviousOffset;
end;

procedure TMarkdownEditor.SchedulePreviewUpdate;
begin
  if (FPreview = nil) or FUpdatingPreview then
    Exit;

  FPreviewDirty := True;
  FPreviewTimer.Enabled := False;
  // a preview that takes long to lay out waits for a longer pause, so the
  // update does not land between two keystrokes and stall the typing
  FPreviewTimer.Interval := TMarkdownPreviewPacer.DelayAfter(FLastPreviewUpdateMilliseconds);
  FPreviewTimer.Enabled := True;
end;

procedure TMarkdownEditor.HandlePreviewTimer(Sender: TObject);
begin
  if not FPreviewDirty then
  begin
    FPreviewTimer.Enabled := False;
    Exit;
  end;

  // a hidden preview lets the update wait; the timer keeps checking
  if (FPreview <> nil) and not FPreview.Showing then
    Exit;

  FlushPreview;
end;

procedure TMarkdownEditor.HandleInternalPreviewScroll(Sender: TObject);
var
  SourceLine: Integer;
begin
  if (not FSyncScroll) or FSyncing or (FPreview = nil) then
    Exit;

  FSyncing := True;
  try
    SourceLine := FPreview.ScrollOffsetToSourceLine(FPreview.ScrollOffset);
    ScrollToSourceLine(SourceLine);
    DoSyncScroll(SourceLine);
  finally
    FSyncing := False;
  end;
end;

procedure TMarkdownEditor.SyncPreviewToEditor;
var
  SourceLine: Integer;
begin
  if (not FSyncScroll) or FSyncing or (FPreview = nil) then
    Exit;

  FSyncing := True;
  try
    SourceLine := FirstVisibleSourceLine;
    FPreview.ScrollOffset := FPreview.SourceLineToScrollOffset(SourceLine);
    DoSyncScroll(SourceLine);
  finally
    FSyncing := False;
  end;
end;

// A caret moved by typing, a key or a click takes the preview along when its
// line would otherwise leave it: the preview can need more room than the
// editor for the same lines, as text wraps, images take height or the two
// zoom apart. Scrolling leaves the caret alone and does not come here, so the
// preview then follows the editor's top line only.
procedure TMarkdownEditor.KeepCaretLineInPreview;
var
  CaretLine: Integer;
  Offset: Single;
begin
  if (not FSyncScroll) or FSyncing or (FPreview = nil) then
    Exit;
  if not FPreview.HandleAllocated then
    Exit;

  if not TryGetVisibleCaretLine(CaretLine) then
    Exit;

  Offset := PreviewOffsetShowingLine(CaretLine);
  if SameValue(Offset, FPreview.ScrollOffset) then
    Exit;

  FSyncing := True;
  try
    FPreview.ScrollOffset := Offset;
  finally
    FSyncing := False;
  end;
end;

function TMarkdownEditor.PreviewOffsetShowingLine(const SourceLine: Integer): Single;
var
  TopLineOffset: Single;
  LineTop: Single;
  LineBottom: Single;
begin
  TopLineOffset := FPreview.SourceLineToScrollOffset(FirstVisibleSourceLine);
  LineTop := FPreview.SourceLineToScrollOffset(SourceLine);
  LineBottom := FPreview.SourceLineToScrollOffset(SourceLine + 1);
  Result := TMarkdownPreviewScroll.OffsetShowingLine(TopLineOffset, LineTop,
    LineBottom, FPreview.ClientHeight);
end;

function TMarkdownEditor.TryGetVisibleCaretLine(out CaretLine: Integer): Boolean;
var
  CaretRow: Integer;
  CaretTop: Integer;
begin
  CaretLine := 0;
  Result := False;

  if FRows.Count = 0 then
    Exit;

  CaretRow := EnsureRange(FRows.IndexOfOffset(FModel.CaretPosition), 0, FRows.Count - 1);
  CaretTop := CaretRow * FLineHeight;
  if (CaretTop < FScrollOffset) or
     (CaretTop + FLineHeight > FScrollOffset + ClientHeight) then
    Exit;

  CaretLine := FRows.Items[CaretRow].LineIndex;
  Result := True;
end;

procedure TMarkdownEditor.DoSyncScroll(const SourceLine: Integer);
begin
  if Assigned(FOnSyncScroll) then
    FOnSyncScroll(Self, SourceLine);
end;

function TMarkdownEditor.TryAdoptPreviewSelection: Boolean;
var
  Segment: TMarkdownSegment;
begin
  Result := False;
  if FPreview = nil then
    Exit;

  // the offsets the preview hands out belong to the text it shows; adopting
  // them onto an older document would select the wrong characters
  if FPreview.Text <> FModel.Text then
    Exit;

  if not FPreview.TryGetSelectionSourceSegment(Segment) then
    Exit;

  // source offsets count from 1, the caret from 0
  FModel.SelectTextRange(Segment.StartOffset - 1, Segment.Length);
  if not FModel.HasSelection then
    Exit;

  ScrollCaretIntoView;
  UpdateCaretTimer;
  Invalidate;
  NotifyCaret;
  NotifySelection;

  Result := True;
end;

// ---------------------------------------------------------------------------
// autoscroll and the right-click menu

function TMarkdownEditor.GetAutoScroll: Boolean;
begin
  Result := FAutoScroll;
end;

procedure TMarkdownEditor.SetAutoScroll(const Value: Boolean);
begin
  FAutoScroll := Value;
  if not Value then
    FAutoScroller.Stop;
end;

function TMarkdownEditor.GetIsAutoScrolling: Boolean;
begin
  Result := FAutoScroller.IsActive;
end;

function TMarkdownEditor.CanAutoScroll: Boolean;
begin
  Result := FRows.Count * FLineHeight > ClientHeight;
end;

procedure TMarkdownEditor.AutoScrollBy(const Delta: Single);
begin
  SetScrollOffset(FScrollOffset + Round(Delta));
end;

procedure TMarkdownEditor.AutoScrollChanged;
begin
  if Assigned(FOnAutoScrollChange) then
    FOnAutoScrollChange(Self);
  Invalidate;
end;

procedure TMarkdownEditor.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
begin
  // a right click that ended autoscroll was a stop, not a menu request
  if FAutoScroller.TakeSuppressedMenu then
  begin
    Handled := True;
    Exit;
  end;

  inherited DoContextPopup(MousePos, Handled);

  // a menu assigned by the host wins; the built-in one is the fallback
  if Handled then
    Exit;
  ShowContextMenu(MousePos.X, MousePos.Y);
  Handled := True;
end;

procedure TMarkdownEditor.ShowContextMenu(const X, Y: Integer);
var
  Item: TEditorContextItem;
  Separator: TMenuItem;
  Entry: TMenuItem;
  Origin: TPoint;
const
  MenuSeparatorCaption = '-';
begin
  if FContextMenu = nil then
    FContextMenu := TPopupMenu.Create(Self);

  FContextMenu.Items.Clear;

  for Item in TMarkdownEditorContextMenu.Build(FModel, ClipboardHasText) do
  begin
    if Item.StartsGroup and (FContextMenu.Items.Count > 0) then
    begin
      Separator := TMenuItem.Create(FContextMenu);
      Separator.Caption := MenuSeparatorCaption;
      FContextMenu.Items.Add(Separator);
    end;

    Entry := TMenuItem.Create(FContextMenu);
    Entry.Caption := Item.Caption;
    Entry.Enabled := Item.Enabled;
    Entry.ShortCut := Item.ShortCut;
    Entry.Tag := Ord(Item.Command);
    Entry.OnClick := HandleContextItemClick;
    FContextMenu.Items.Add(Entry);
  end;

  Origin := ClientToScreen(Point(X, Y));
  FContextMenu.PopUp(Origin.X, Origin.Y);
end;

procedure TMarkdownEditor.HandleContextItemClick(Sender: TObject);
var
  Command: TEditorContextCommand;
begin
  Command := TEditorContextCommand((Sender as TMenuItem).Tag);

  if TMarkdownEditorContextMenu.Execute(FModel, Command) then
  begin
    Invalidate;
    Exit;
  end;

  case Command of
    TEditorContextCommand.Cut:   CutToClipboard;
    TEditorContextCommand.Copy:  CopyToClipboard;
    TEditorContextCommand.Paste: PasteFromClipboard;
  end;

  Invalidate;
end;

function TMarkdownEditor.ClipboardHasText: Boolean;
begin
  try
    Result := Clipboard.HasFormat(CF_TEXT);
  except
    Result := False;
  end;
end;

end.
