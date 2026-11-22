unit Markdown4D.Lcl.Viewer;
{ TMarkdownViewer: a Markdown document rendered on an LCL canvas.

  The document is parsed and laid out by Markdown4D.Viewer.Model, which is
  widgetset independent; this unit is the shell around it - it measures with a
  TCanvas, paints the display list through IPainter, and turns mouse, wheel and
  keyboard into the model's calls.  Zoom is applied by the model, which lays the
  document out again with a scaled theme, so the painter always works at scale
  1 and only shifts the origin to scroll. }

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
  Markdown4D.Layout.DisplayList,
  Markdown4D.Layout.HitTest,
  Markdown4D.Layout.Renderer,
  Markdown4D.Layout.TextSearch,
  Markdown4D.Layout.Zoom,
  Markdown4D.Theme,
  Markdown4D.AutoScroll,
  Markdown4D.Viewer.ContextMenu,
  Markdown4D.Viewer.Model,
  Markdown4D.Viewer.Shared,
  Markdown4D.Viewer.ImageDownloader,
  Markdown4D.Viewer.ImageSettings,
  Markdown4D.Compat.IOUtils,
  Markdown4D.Lcl.AutoScroll,
  Markdown4D.Lcl.Painter,
  Markdown4D.Lcl.Images;

type
  TMarkdownLinkClickEvent = procedure(const Sender: TObject; const Url: string) of object;
  TMarkdownLinkHoverEvent = procedure(const Sender: TObject; const Url: string) of object;
  TMarkdownExtensionErrorEvent = Markdown4D.Viewer.Model.TMarkdownExtensionErrorEvent;

  // Republished from the shared layer so callers keep finding the type here.
  TMarkdownViewerImageSettings = Markdown4D.Viewer.ImageSettings.TMarkdownViewerImageSettings;

  // Vetoes or permits one remote image, starting from Images.AllowRemote.
  TMarkdownRemoteImageEvent = procedure(const Sender: TObject; const Url: string;
    var Allow: Boolean) of object;

  // One heading of the document, in document order - what a table-of-contents
  // panel needs. ScrollOffset is where the view must be scrolled so the
  // heading is at the top; it is -1 while the heading has not been laid out.
  TMarkdownOutlineEntry = record
    Level: Integer;
    Caption: string;
    Anchor: string;
    SourceLine: Integer;
    ScrollOffset: Single;
  end;

  // Lets the application supply a picture itself, for instance from a resource
  // or a cache of its own. Set Handled to True to keep what it put in Picture.
  TMarkdownResolveImageEvent = procedure(const Sender: TObject; const Url: string;
    const Picture: TPicture; var Handled: Boolean) of object;

  TMarkdownViewer = class(TCustomControl, IMarkdownAutoScrollTarget)
  private
    const
      DefaultControlWidth = 320;
      DefaultControlHeight = 220;
      ScrollLinesPerNotch = 3;
      ScrollLineHeight = 20;
      NotchDelta = 120;
      // Appended markdown is laid out at most this often, whatever the rate
      // the lines arrive at (the model holds the same default).
      FlushTimerIntervalMilliseconds = 100;
      SelectionFillColor = TLayoutColor($402F81F7);
      MatchFillColor = TLayoutColor($55E3B341);
      CopyButtonWidth = 52;
      CopyButtonHeight = 20;
      CopyButtonMargin = 6;
      CopyFeedbackMilliseconds = 1200;
      DoubleClickMilliseconds = 500;
      DoubleClickSlack = 4;
    var
      FModel: TMarkdownViewerModel;
      FImages: TMarkdownViewerImageSettings;
      FImageDownloader: TMarkdownImageDownloader;
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
      FDocumentFolder: string;
      FStoredText: string;
      FLoadedImages: TStringList;
      FRequestedImages: TStringList;
      FOnLinkClick: TMarkdownLinkClickEvent;
      FOnLinkHover: TMarkdownLinkHoverEvent;
      FOnResolveImage: TMarkdownResolveImageEvent;
      FOnRemoteImageRequest: TMarkdownRemoteImageEvent;
      FOnScroll: TNotifyEvent;
      FOnZoomChange: TNotifyEvent;
      FOnExtensionError: TMarkdownExtensionErrorEvent;
      FHoveredLinkUrl: string;
      FPressedLinkUrl: string;
      FSelecting: Boolean;
      FLastClickTick: QWord;
      FLastClickPoint: TPoint;
      FClickCount: Integer;
      FCodeHoverActive: Boolean;
      FCodeHoverRect: TLayoutRectF;
      FCodeHoverText: string;
      FCopyButtonRect: TLayoutRectF;
      FCopyFeedback: Boolean;
      FCopyFeedbackTick: QWord;
      FFeedbackTimer: TTimer;
      FFlushTimer: TTimer;
      FAutoScroller: TMarkdownLclAutoScroller;
      FAutoScroll: Boolean;
      FContextMenu: TPopupMenu;
      FCopyAsMarkdown: Boolean;
      FOnAutoScrollChange: TNotifyEvent;
    function EffectiveTheme: TMarkdownTheme;
    procedure RebuildEffectiveTheme;
    procedure HandleScrollBarChange(Sender: TObject);
    procedure HandleFeedbackTimer(Sender: TObject);
    procedure HandleExtensionError(const Sender: TObject; const Extension: string;
      const Error: Exception);
    procedure ApplyViewport;
    procedure UpdateScrollBar;
    function MaxScrollOffset: Single;
    function ContentPointOf(const X, Y: Integer): TLayoutPointF;
    function ThemeBackground: TColor;
    procedure StepZoom(const Percent: Integer);
    procedure SetZoom(const Value: Integer);
    function GetZoom: Integer;
    function GetText: string;
    function GetFlushIntervalMilliseconds: Cardinal;
    procedure SetFlushIntervalMilliseconds(const Value: Cardinal);
    function GetDisplayList: IMarkdownDisplayList;
    function GetLayoutCount: Integer;
    procedure SetText(const Value: string);
    procedure SetTheme(const Value: TMarkdownTheme);
    procedure SetThemePreset(const Value: TMarkdownThemePreset);
    procedure SetContentScale(const Value: Single);
    function GetScrollOffset: Single;
    procedure SetScrollOffset(const Value: Single);
    procedure ResolvePendingImages;
    procedure LoadImage(const Source: string);
    procedure StoreImage(const Source: string; const Graphic: TGraphic);
    function ResolveLoadedImage(const Source: string): TGraphic;
    function IsImageBroken(const Source: string): Boolean;
    procedure NotifyImageFailed(const Source: string);
    procedure HandleImageDataArrived(const Source: string; const Data: TBytes);
    procedure HandleImageDownloadFailed(const Source: string);
    function AllowsRemoteImage(const Url: string): Boolean;
    procedure SetImages(const Value: TMarkdownViewerImageSettings);
    procedure UpdateHoverCursor(const Point: TLayoutPointF);
    procedure UpdateCodeHover(const Point: TLayoutPointF);
    procedure ClearCodeHover;
    procedure DrawCopyButton(const Painter: IPainter);
    procedure CopyToClipboard(const Text: string);
    procedure CopyCodeAt(const Region: TMarkdownCodeBlockRegion);
    function PointOnCopyButton(const Point: TLayoutPointF): Boolean;
    procedure ScrollDocumentBy(const Delta: Single);
    function IsDoubleClick(const X, Y: Integer): Boolean;
    function LinkAt(const Point: TLayoutPointF; out Url: string): Boolean;
    procedure TakeFocus;
    function GetAutoScroll: Boolean;
    procedure SetAutoScroll(const Value: Boolean);
    function GetIsAutoScrolling: Boolean;
    procedure PaintAutoScrollOrigin;
    function CanAutoScroll: Boolean;
    procedure AutoScrollBy(const Delta: Single);
    procedure AutoScrollChanged;
    procedure ShowContextMenu(const X, Y: Integer);
    procedure HandleContextItemClick(Sender: TObject);
    procedure CopySelectionAsMarkdown;
    procedure CopyForShortcut(const Shift: TShiftState);
  protected
    procedure Paint; override;
    // Drives the flush of markdown queued by AppendMarkdown. A test can call
    // it, which is why it is protected rather than private.
    procedure HandleFlushTimer(Sender: TObject);
    // Paints the part of the document the view covers onto any canvas of the
    // control's size. Paint uses it, and so can a test or a thumbnail.
    procedure RenderDocument(const ACanvas: TCanvas);
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadFromFile(const FileName: string);
    // Adds a chunk of markdown to the end of the document - the way a log or
    // a transcript grows. Chunks arriving faster than the model's
    // FlushIntervalMilliseconds (100 ms by default) are laid out together, so
    // appending line by line does not re-layout per line. When the view is at
    // the bottom it follows the growth.
    procedure AppendMarkdown(const Markdown: string);
    procedure LoadFromStream(const Stream: TStream);
    // Brings the heading a link like #getting-started points at to the top of
    // the view. The anchor may be percent-encoded.
    function ScrollToAnchor(const Anchor: string): Boolean;
    // The headings of the document, in document order, for a table-of-contents
    // panel. Entries carry the scroll offset that brings each heading to the
    // top, so scrolling is just `ScrollOffset := Entry.ScrollOffset`.
    function Outline: TArray<TMarkdownOutlineEntry>;
    // Scrolls the given outline entry into view. True when it was laid out.
    function ScrollToOutlineEntry(const Entry: TMarkdownOutlineEntry): Boolean;
    // Selects the first match after the current selection, wraps around at the
    // end, and scrolls it into view. False when the needle does not occur.
    function FindText(const Needle: string): Boolean; overload;
    function FindText(const Needle: string; const Options: TMarkdownFindOptions): Boolean; overload;
    function FindPrevious(const Needle: string): Boolean; overload;
    function FindPrevious(const Needle: string; const Options: TMarkdownFindOptions): Boolean; overload;
    function FindMatchCount(const Needle: string): Integer; overload;
    function FindMatchCount(const Needle: string; const Options: TMarkdownFindOptions): Integer; overload;
    function FindMatchIndex(const Needle: string): Integer; overload;
    function FindMatchIndex(const Needle: string; const Options: TMarkdownFindOptions): Integer; overload;
    procedure HighlightMatches(const Needle: string); overload;
    procedure HighlightMatches(const Needle: string; const Options: TMarkdownFindOptions); overload;
    procedure ClearHighlights;
    function HighlightCount: Integer;
    procedure ClearSelection;
    function SelectAll: Boolean;
    function SelectedText: string;
    function SelectedMarkdown: string;
    // The stretch of source the selection was rendered from, so a companion
    // editor can select the same characters. False when there is no selection,
    // or the runs it covers carry no source of their own.
    function TryGetSelectionSourceSegment(out Segment: TMarkdownSegment): Boolean;
    // The line of source at the top of the view, and the offset that brings a
    // line to the top. Lines count from 0.
    function ScrollOffsetToSourceLine(const Offset: Single): Integer;
    function SourceLineToScrollOffset(const SourceLine: Integer): Single;
    property DisplayList: IMarkdownDisplayList read GetDisplayList;
    property LayoutCount: Integer read GetLayoutCount;
    property IsSelecting: Boolean read FSelecting;
    property IsAutoScrolling: Boolean read GetIsAutoScrolling;
  published
    property Align;
    property Anchors;
    property BorderStyle;
    property BorderWidth;
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
    property OnDblClick;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;

    // The markdown source. Setting it lays the document out again.
    property Text: string read GetText write SetText;
    // How long markdown queued by AppendMarkdown may wait before it is laid
    // out. Zero lays out on the next timer tick; the default is 100 ms.
    property FlushIntervalMilliseconds: Cardinal
      read GetFlushIntervalMilliseconds write SetFlushIntervalMilliseconds;
    // In percent; the whole document grows with it.
    property Zoom: Integer read GetZoom write SetZoom default 100;
    // Where the top of the view is, in pixels of the laid out document.
    property ScrollOffset: Single read GetScrollOffset write SetScrollOffset;
    // the full laid-out height in pixels, viewport not included
    function ContentHeight: Integer;
    // The colours and fonts. The viewer keeps what it is given, and frees only
    // a theme it created itself.
    property Theme: TMarkdownTheme read FTheme write SetTheme;
    property ThemePreset: TMarkdownThemePreset read FThemePreset write SetThemePreset default TMarkdownThemePreset.Light;
    // Multiplies every font and length, for a form that scales itself on a
    // high DPI screen. 1 leaves the theme as it is.
    property ContentScale: Single read FContentScale write SetContentScale;
    // Relative images resolve against this folder.
    property DocumentFolder: string read FDocumentFolder write FDocumentFolder;
    // Remote-image policy: whether http(s) images may be fetched, a size bound,
    // and whether relative paths may leave the document folder.
    property Images: TMarkdownViewerImageSettings read FImages write SetImages;
    property OnLinkClick: TMarkdownLinkClickEvent read FOnLinkClick write FOnLinkClick;
    property OnLinkHover: TMarkdownLinkHoverEvent read FOnLinkHover write FOnLinkHover;
    property OnResolveImage: TMarkdownResolveImageEvent read FOnResolveImage write FOnResolveImage;
    // Vetoes or permits one remote address, starting from Images.AllowRemote.
    property OnRemoteImageRequest: TMarkdownRemoteImageEvent read FOnRemoteImageRequest write FOnRemoteImageRequest;
    property OnScroll: TNotifyEvent read FOnScroll write FOnScroll;
    property OnZoomChange: TNotifyEvent read FOnZoomChange write FOnZoomChange;
    property OnExtensionError: TMarkdownExtensionErrorEvent read FOnExtensionError write FOnExtensionError;
    // A middle click scrolls the document by the distance of the pointer from
    // where it was pressed, until the next click, key or wheel turn.
    property AutoScroll: Boolean read GetAutoScroll write SetAutoScroll default True;
    property OnAutoScrollChange: TNotifyEvent read FOnAutoScrollChange write FOnAutoScrollChange;
    // Offers Copy as Markdown in the menu and on Ctrl+Shift+C. Turn it off for
    // an application that does not show the source to its readers.
    property CopyAsMarkdown: Boolean read FCopyAsMarkdown write FCopyAsMarkdown default True;
  end;

implementation

uses
  Markdown4D.Image.Svg,
  Markdown4D.Toc;

constructor TMarkdownViewer.Create(AOwner: TComponent);
var
  Measurer: IPainter;
begin
  inherited Create(AOwner);

  // the whole client area is painted on every frame, so there is nothing to erase
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Width := DefaultControlWidth;
  Height := DefaultControlHeight;
  TabStop := True;

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

  FModel := TMarkdownViewerModel.Create(FTheme, FMeasureLifetime);
  FModel.OnExtensionError := HandleExtensionError;

  FImages := TMarkdownViewerImageSettings.Create;
  FImageDownloader := TMarkdownImageDownloader.Create(HandleImageDataArrived, HandleImageDownloadFailed);
  FImageDownloader.OnAddressAllowed := AllowsRemoteImage;

  FLoadedImages := TStringList.Create;
  FLoadedImages.CaseSensitive := True;
  FLoadedImages.Sorted := True;
  FLoadedImages.OwnsObjects := True;
  FRequestedImages := TStringList.Create;
  FRequestedImages.CaseSensitive := True;
  FRequestedImages.Sorted := True;
  FRequestedImages.Duplicates := dupIgnore;

  FScrollBar := TScrollBar.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Kind := sbVertical;
  FScrollBar.Align := alRight;
  FScrollBar.Visible := False;
  FScrollBar.OnChange := HandleScrollBarChange;

  FFeedbackTimer := TTimer.Create(Self);
  FFeedbackTimer.Enabled := False;
  FFeedbackTimer.Interval := CopyFeedbackMilliseconds;
  FFeedbackTimer.OnTimer := HandleFeedbackTimer;

  FFlushTimer := TTimer.Create(Self);
  FFlushTimer.Enabled := False;
  FFlushTimer.Interval := FlushTimerIntervalMilliseconds;
  FFlushTimer.OnTimer := HandleFlushTimer;

  FAutoScroll := True;
  FCopyAsMarkdown := True;
  FAutoScroller := TMarkdownLclAutoScroller.Create(Self, Self);

  TMarkdownViewerShared.RegisterDefaultHighlighters;
end;

destructor TMarkdownViewer.Destroy;
begin
  FAutoScroller.Free;
  FFeedbackTimer.Free;
  FImageDownloader.Free;
  FImages.Free;
  FModel.Free;
  FModel := nil;
  FPainterLifetime := nil;
  // the interface holds the only reference, so dropping it frees the painter
  FMeasurePainter := nil;
  FMeasureLifetime := nil;
  FMeasureBitmap.Free;
  FRequestedImages.Free;
  FLoadedImages.Free;
  FreeAndNil(FEffectiveTheme);
  if FOwnsTheme then
    FTheme.Free;
  FTheme := nil;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// theme

procedure TMarkdownViewer.RebuildEffectiveTheme;
var
  Previous: TMarkdownTheme;
begin
  Previous := FEffectiveTheme;
  FEffectiveTheme := nil;
  if not SameValue(FContentScale, 1) and (FContentScale > 0) then
    FEffectiveTheme := FTheme.Scaled(FContentScale);
  if FModel <> nil then
    FModel.ApplyTheme(EffectiveTheme);
  Previous.Free;
end;

function TMarkdownViewer.EffectiveTheme: TMarkdownTheme;
begin
  if FEffectiveTheme <> nil then
    Result := FEffectiveTheme
  else
    Result := FTheme;
end;

procedure TMarkdownViewer.SetTheme(const Value: TMarkdownTheme);
begin
  if (Value = nil) or (Value = FTheme) then
    Exit;
  RebuildEffectiveTheme;
  if FOwnsTheme then
    FTheme.Free;
  FTheme := Value;
  FOwnsTheme := False;
  RebuildEffectiveTheme;
  UpdateScrollBar;
  Invalidate;
end;

procedure TMarkdownViewer.SetThemePreset(const Value: TMarkdownThemePreset);
var
  NewTheme: TMarkdownTheme;
begin
  if Value = FThemePreset then
    Exit;
  FThemePreset := Value;
  NewTheme := TMarkdownTheme.CreatePreset(Value);
  try
    if FOwnsTheme then
      FTheme.Free;
    FTheme := NewTheme;
    FOwnsTheme := True;
  except
    NewTheme.Free;
    raise;
  end;
  RebuildEffectiveTheme;
  UpdateScrollBar;
  Invalidate;
end;

procedure TMarkdownViewer.SetContentScale(const Value: Single);
begin
  if SameValue(Value, FContentScale) or (Value <= 0) then
    Exit;
  FContentScale := Value;
  RebuildEffectiveTheme;
  UpdateScrollBar;
  Invalidate;
end;

function TMarkdownViewer.ThemeBackground: TColor;
begin
  Result := LayoutColorToColor(EffectiveTheme.BackgroundColor);
end;

// ---------------------------------------------------------------------------
// text

function TMarkdownViewer.GetText: string;
begin
  Result := FModel.FullText;
end;

function TMarkdownViewer.GetFlushIntervalMilliseconds: Cardinal;
begin
  Result := FModel.FlushIntervalMilliseconds;
end;

procedure TMarkdownViewer.SetFlushIntervalMilliseconds(const Value: Cardinal);
begin
  FModel.FlushIntervalMilliseconds := Value;
end;

function TMarkdownViewer.GetDisplayList: IMarkdownDisplayList;
begin
  Result := FModel.DisplayList;
end;

function TMarkdownViewer.GetLayoutCount: Integer;
begin
  Result := FModel.LayoutCount;
end;

procedure TMarkdownViewer.SetText(const Value: string);
begin
  if Value = FStoredText then
    Exit;
  FStoredText := Value;
  // A new document names new pictures: drop responses from the old one.
  FImageDownloader.CancelPending;
  FRequestedImages.Clear;
  ApplyViewport;
  FModel.Text := Value;
  UpdateScrollBar;
  Invalidate;
end;

procedure TMarkdownViewer.LoadFromStream(const Stream: TStream);
var
  Reader: TStringList;
begin
  Reader := TStringList.Create;
  try
    Reader.LoadFromStream(Stream);
    Text := Reader.Text;
  finally
    Reader.Free;
  end;
end;

procedure TMarkdownViewer.LoadFromFile(const FileName: string);
var
  Stream: TFileStream;
  Data: TBytes;
begin
  FDocumentFolder := ExtractFileDir(ExpandFileName(FileName));
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, Stream.Size);
    if Length(Data) > 0 then
      Stream.ReadBuffer(Data[0], Length(Data));
  finally
    Stream.Free;
  end;
  // the file may be UTF-8 with a byte order mark, which TStringList drops
  Text := TEncoding.UTF8.GetString(Data);
end;

// ---------------------------------------------------------------------------
// viewport and scrolling

procedure TMarkdownViewer.ApplyViewport;
begin
  FModel.SetViewport(Max(1, ClientWidth), Max(1, ClientHeight));
  ResolvePendingImages;
  UpdateScrollBar;
end;

function TMarkdownViewer.ContentHeight: Integer;
begin
  if FModel.DisplayList = nil then
    Exit(0);
  Result := Ceil(FModel.DisplayList.Height);
end;

function TMarkdownViewer.MaxScrollOffset: Single;
begin
  Result := Max(0, ContentHeight - ClientHeight);
end;

procedure TMarkdownViewer.UpdateScrollBar;
var
  Content: Integer;
begin
  if FUpdatingScrollBar then
    Exit;
  if FScrollBar = nil then
    Exit;

  Content := ContentHeight;
  FUpdatingScrollBar := True;
  try
    FScrollBar.Min := 0;
    FScrollBar.Max := Max(Content, ClientHeight);
    FScrollBar.PageSize := Max(0, ClientHeight);
    FScrollBar.Position := EnsureRange(Round(FModel.ScrollOffset), 0, FScrollBar.Max);
    FScrollBar.Visible := Content > ClientHeight;
  finally
    FUpdatingScrollBar := False;
  end;
end;

procedure TMarkdownViewer.HandleScrollBarChange(Sender: TObject);
begin
  if FUpdatingScrollBar then
    Exit;
  SetScrollOffset(FScrollBar.Position);
end;

function TMarkdownViewer.GetScrollOffset: Single;
begin
  Result := FModel.ScrollOffset;
end;

procedure TMarkdownViewer.SetScrollOffset(const Value: Single);
var
  Offset: Single;
begin
  Offset := EnsureRange(Value, 0, MaxScrollOffset);
  if SameValue(Offset, FModel.ScrollOffset) then
    Exit;
  FModel.ScrollOffset := Offset;
  UpdateScrollBar;
  Invalidate;
  if Assigned(FOnScroll) then
    FOnScroll(Self);
end;

procedure TMarkdownViewer.ScrollDocumentBy(const Delta: Single);
begin
  SetScrollOffset(FModel.ScrollOffset + Delta);
end;

function TMarkdownViewer.ScrollOffsetToSourceLine(const Offset: Single): Integer;
begin
  Result := FModel.ScrollOffsetToSourceLine(Offset);
end;

function TMarkdownViewer.SourceLineToScrollOffset(const SourceLine: Integer): Single;
begin
  Result := FModel.SourceLineToScrollOffset(SourceLine);
end;

function TMarkdownViewer.ContentPointOf(const X, Y: Integer): TLayoutPointF;
begin
  Result := TLayoutPointF.Create(X, Y + FModel.ScrollOffset);
end;

procedure TMarkdownViewer.Resize;
begin
  inherited Resize;
  if FModel = nil then
    Exit;
  ApplyViewport;
  Invalidate;
end;

// ---------------------------------------------------------------------------
// zoom

function TMarkdownViewer.GetZoom: Integer;
begin
  Result := FModel.Zoom;
end;

procedure TMarkdownViewer.SetZoom(const Value: Integer);
var
  Clamped: Integer;
begin
  Clamped := TMarkdownZoom.Clamp(Value);
  if Clamped = FModel.Zoom then
    Exit;
  FModel.Zoom := Clamped;
  UpdateScrollBar;
  Invalidate;
  if Assigned(FOnZoomChange) then
    FOnZoomChange(Self);
end;

procedure TMarkdownViewer.StepZoom(const Percent: Integer);
begin
  SetZoom(Percent);
end;

// ---------------------------------------------------------------------------
// painting

procedure TMarkdownViewer.Paint;
begin
  Canvas.Brush.Color := ThemeBackground;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);
  RenderDocument(Canvas);
  PaintAutoScrollOrigin;
end;

procedure TMarkdownViewer.PaintAutoScrollOrigin;
var
  Painter: TMarkdownLclPainter;
  Lifetime: IPainter;
begin
  if not FAutoScroller.IsActive then
    Exit;

  // the mark sits where the pointer pressed, in view coordinates, so this
  // painter does not shift by the scroll offset as RenderDocument's does
  Painter := TMarkdownLclPainter.Create(Canvas);
  Painter.Background := ThemeBackground;
  Painter.Scale := 1;
  Painter.OriginX := 0;
  Painter.OriginY := 0;
  Lifetime := Painter;
  FAutoScroller.PaintOrigin(Lifetime, EffectiveTheme.BackgroundColor, EffectiveTheme.TextColor);
end;

procedure TMarkdownViewer.RenderDocument(const ACanvas: TCanvas);
var
  Painter: TMarkdownLclPainter;
  Viewport: TLayoutRectF;
  Offset: Single;
  Box: TLayoutRectF;
begin
  if (FModel = nil) or (FModel.DisplayList = nil) then
    Exit;

  Offset := FModel.ScrollOffset;
  // The painter is reference counted and owns itself: as soon as the interface
  // below lets go, the object goes with it.
  Painter := TMarkdownLclPainter.Create(ACanvas);
  Painter.Background := ThemeBackground;
  Painter.Scale := 1;
  Painter.OriginX := 0;
  Painter.OriginY := -Offset;
  Painter.ImageResolver := ResolveLoadedImage;
  Painter.BrokenImageQuery := IsImageBroken;
  FPainterLifetime := Painter;
  try
    Viewport := TLayoutRectF.Create(0, Offset, ACanvas.Width, Offset + ACanvas.Height);
    FPainterLifetime.FillRect(Viewport, EffectiveTheme.BackgroundColor);

    // The selection and the search marks go under the text rather than over it.
    // An LCL canvas cannot blend, so a highlight drawn last would hide the very
    // letters it is meant to mark; under the text it tints the page instead.
    for Box in FModel.HighlightRectsWithin(Viewport) do
      FPainterLifetime.FillRect(Box, MatchFillColor);

    for Box in FModel.SelectionRects do
      FPainterLifetime.FillRect(Box, SelectionFillColor);

    // the background is already down, so the renderer is asked for none
    TMarkdownDisplayListRenderer.Render(FModel.DisplayList, FPainterLifetime, Viewport, 0);

    if FCodeHoverActive then
      DrawCopyButton(FPainterLifetime);
  finally
    FPainterLifetime := nil;
  end;
end;

procedure TMarkdownViewer.DrawCopyButton(const Painter: IPainter);
var
  Caption: string;
  Font: TMarkdownFontStyle;
  Size: TLayoutSizeF;
  TextPoint: TLayoutPointF;
begin
  Caption := 'Copy';
  if FCopyFeedback then
    Caption := 'Copied';

  Font := EffectiveTheme.BaseFont;
  Font.Size := Font.Size * 0.82;
  Size := Painter.MeasureText(Caption, Font);

  Painter.FillRect(FCopyButtonRect, TLayoutColor($F0FFFFFF));
  Painter.DrawRect(FCopyButtonRect, TLayoutColor($FFBFC5CC), 1);
  TextPoint := TLayoutPointF.Create(
    FCopyButtonRect.Left + (FCopyButtonRect.Width - Size.Width) / 2,
    FCopyButtonRect.Top + (FCopyButtonRect.Height - Size.Height) / 2);
  Painter.DrawTextRun(TextPoint, Caption, Font, TLayoutColor($FF3A3F45));
end;

// ---------------------------------------------------------------------------
// images

procedure TMarkdownViewer.ResolvePendingImages;
var
  Sources: TArray<string>;
  Source: string;
begin
  if FModel.DisplayList = nil then
    Exit;
  Sources := FModel.PendingImageSources;
  for Source in Sources do
  begin
    if FRequestedImages.IndexOf(Source) >= 0 then
      Continue;
    FRequestedImages.Add(Source);
    LoadImage(Source);
  end;
end;

procedure TMarkdownViewer.LoadImage(const Source: string);
var
  Picture: TPicture;
  Handled: Boolean;
  Graphic: TGraphic;
  Bitmap: TBitmap;
  FileName: string;
begin
  Handled := False;
  if Assigned(FOnResolveImage) then
  begin
    Picture := TPicture.Create;
    try
      FOnResolveImage(Self, Source, Picture, Handled);
      if Handled then
      begin
        if (Picture.Graphic <> nil) and not Picture.Graphic.Empty then
        begin
          Bitmap := TBitmap.Create;
          try
            Bitmap.Assign(Picture.Graphic);
          except
            Bitmap.Free;
            raise;
          end;
          // StoreImage takes the bitmap over
          StoreImage(Source, Bitmap);
        end
        else
          NotifyImageFailed(Source);
      end;
    finally
      Picture.Free;
    end;
    if Handled then
      Exit;
  end;

  // Remote addresses go to the background downloader. The callback arrives on
  // the UI thread and stores the picture once it has been decoded.
  if TMarkdownViewerShared.IsHttpUrl(Source) then
  begin
    if not AllowsRemoteImage(Source) then
    begin
      NotifyImageFailed(Source);
      Exit;
    end;
    FImageDownloader.Download(Source, Source, FImages.MaxBytes);
    Exit;
  end;

  // a path relative to the document is the common case; anything else left
  // here is a local file that may or may not exist
  FileName := Source;
  if not TPath.IsPathRooted(FileName) and (FDocumentFolder <> '') then
    FileName := IncludeTrailingPathDelimiter(FDocumentFolder) + FileName;
  if TMarkdownLclPictures.FromFile(FileName, EffectiveTheme.BackgroundColor, Graphic) then
  begin
    if Graphic <> nil then
      StoreImage(Source, Graphic);
    Exit;
  end;

  NotifyImageFailed(Source);
end;

procedure TMarkdownViewer.StoreImage(const Source: string; const Graphic: TGraphic);
begin
  if Graphic = nil then
    Exit;
  FLoadedImages.AddObject(Source, Graphic);
  FModel.NotifyImageArrived(Source, TLayoutSizeF.Create(Graphic.Width, Graphic.Height));
  UpdateScrollBar;
  Invalidate;
end;

function TMarkdownViewer.ResolveLoadedImage(const Source: string): TGraphic;
var
  Index: Integer;
begin
  Result := nil;
  if FLoadedImages.Find(Source, Index) then
    Result := TGraphic(FLoadedImages.Objects[Index]);
end;

function TMarkdownViewer.IsImageBroken(const Source: string): Boolean;
begin
  Result := FModel.ImageSlotState(Source) = TMarkdownImageSlotState.Failed;
end;

procedure TMarkdownViewer.NotifyImageFailed(const Source: string);
begin
  FModel.NotifyImageFailed(Source);
  UpdateScrollBar;
  Invalidate;
end;

// Runs on the UI thread (the downloader queues its results there). Decode the
// bytes the same way a local file is decoded, so SVG and alpha behave alike.
procedure TMarkdownViewer.HandleImageDataArrived(const Source: string; const Data: TBytes);
var
  Index: Integer;
  Graphic: TGraphic;
begin
  if FRequestedImages.Find(Source, Index) then
    FRequestedImages.Delete(Index);

  if not TMarkdownLclPictures.FromBytes(Data, EffectiveTheme.BackgroundColor, Graphic) then
  begin
    NotifyImageFailed(Source);
    Exit;
  end;

  if Graphic = nil then
  begin
    NotifyImageFailed(Source);
    Exit;
  end;

  StoreImage(Source, Graphic);
end;

procedure TMarkdownViewer.HandleImageDownloadFailed(const Source: string);
var
  Index: Integer;
begin
  if FRequestedImages.Find(Source, Index) then
    FRequestedImages.Delete(Index);
  NotifyImageFailed(Source);
end;

// Starts from the setting and lets the application narrow it per address.
function TMarkdownViewer.AllowsRemoteImage(const Url: string): Boolean;
begin
  Result := FImages.AllowRemote;
  if Assigned(FOnRemoteImageRequest) then
    FOnRemoteImageRequest(Self, Url, Result);
end;

procedure TMarkdownViewer.SetImages(const Value: TMarkdownViewerImageSettings);
begin
  FImages.Assign(Value);
end;

// ---------------------------------------------------------------------------
// selection, search, clipboard

procedure TMarkdownViewer.ClearSelection;
begin
  FModel.ClearSelection;
  Invalidate;
end;

function TMarkdownViewer.SelectAll: Boolean;
begin
  Result := FModel.SelectAll;
  Invalidate;
end;

function TMarkdownViewer.SelectedText: string;
begin
  Result := FModel.SelectedText;
end;

function TMarkdownViewer.SelectedMarkdown: string;
begin
  Result := FModel.SelectedMarkdown;
end;

procedure TMarkdownViewer.HandleExtensionError(const Sender: TObject; const Extension: string;
  const Error: Exception);
begin
  UpdateScrollBar;
  Invalidate;
  if Assigned(FOnExtensionError) then
    FOnExtensionError(Self, Extension, Error);
end;

function TMarkdownViewer.FindText(const Needle: string): Boolean;
begin
  Result := FindText(Needle, Default(TMarkdownFindOptions));
end;

function TMarkdownViewer.FindText(const Needle: string;
  const Options: TMarkdownFindOptions): Boolean;
var
  Match: TMarkdownFoundRange;
  Target: Single;
begin
  Result := FModel.TrySelectNextMatch(Needle, Options, Match);
  if not Result then
    Exit;
  if FModel.TryGetScrollTarget(Match, Target) then
    SetScrollOffset(Target);
  Invalidate;
end;

function TMarkdownViewer.FindPrevious(const Needle: string): Boolean;
begin
  Result := FindPrevious(Needle, Default(TMarkdownFindOptions));
end;

function TMarkdownViewer.FindPrevious(const Needle: string;
  const Options: TMarkdownFindOptions): Boolean;
var
  Match: TMarkdownFoundRange;
  Target: Single;
begin
  Result := FModel.TrySelectPreviousMatch(Needle, Options, Match);
  if not Result then
    Exit;
  if FModel.TryGetScrollTarget(Match, Target) then
    SetScrollOffset(Target);
  Invalidate;
end;

function TMarkdownViewer.FindMatchCount(const Needle: string): Integer;
begin
  Result := FindMatchCount(Needle, Default(TMarkdownFindOptions));
end;

function TMarkdownViewer.FindMatchCount(const Needle: string;
  const Options: TMarkdownFindOptions): Integer;
begin
  Result := FModel.MatchCount(Needle, Options);
end;

function TMarkdownViewer.FindMatchIndex(const Needle: string): Integer;
begin
  Result := FindMatchIndex(Needle, Default(TMarkdownFindOptions));
end;

function TMarkdownViewer.FindMatchIndex(const Needle: string;
  const Options: TMarkdownFindOptions): Integer;
begin
  Result := FModel.MatchIndex(Needle, Options);
end;

procedure TMarkdownViewer.HighlightMatches(const Needle: string);
begin
  HighlightMatches(Needle, Default(TMarkdownFindOptions));
end;

procedure TMarkdownViewer.HighlightMatches(const Needle: string;
  const Options: TMarkdownFindOptions);
begin
  FModel.HighlightMatches(Needle, Options);
  Invalidate;
end;

procedure TMarkdownViewer.ClearHighlights;
begin
  FModel.ClearHighlights;
  Invalidate;
end;

function TMarkdownViewer.HighlightCount: Integer;
begin
  Result := FModel.HighlightCount;
end;

procedure TMarkdownViewer.CopyToClipboard(const Text: string);
begin
  if Text = '' then
    Exit;
  Clipboard.AsText := Text;
end;

procedure TMarkdownViewer.CopySelectionAsMarkdown;
begin
  CopyToClipboard(FModel.SelectedMarkdown);
end;

// Ctrl+Shift+C copies the markdown, unless the application keeps the source
// to itself; then it copies plain text as Ctrl+C does.
procedure TMarkdownViewer.CopyForShortcut(const Shift: TShiftState);
var
  Text: string;
begin
  if ssShift in Shift then
  begin
    if not FCopyAsMarkdown then
      Text := FModel.SelectedText
    else
      Text := FModel.SelectedMarkdown;
  end
  else
    Text := FModel.SelectedText;
  if Text <> '' then
    CopyToClipboard(Text);
end;

function TMarkdownViewer.TryGetSelectionSourceSegment(
  out Segment: TMarkdownSegment): Boolean;
begin
  Result := FModel.TryGetSelectionSourceSegment(Segment);
end;

procedure TMarkdownViewer.CopyCodeAt(const Region: TMarkdownCodeBlockRegion);
begin
  CopyToClipboard(Region.Text);
  FCopyFeedback := True;
  FCopyFeedbackTick := GetTickCount64;
  FFeedbackTimer.Enabled := False;
  FFeedbackTimer.Enabled := True;
  Invalidate;
end;

procedure TMarkdownViewer.HandleFeedbackTimer(Sender: TObject);
begin
  FFeedbackTimer.Enabled := False;
  if not FCopyFeedback then
    Exit;
  FCopyFeedback := False;
  Invalidate;
end;

procedure TMarkdownViewer.AppendMarkdown(const Markdown: string);
begin
  FModel.AppendMarkdown(Markdown, Int64(GetTickCount64));
  // The timer lays out accumulated chunks at the model's flush interval, so a
  // loop appending one line at a time costs one relayout every 100 ms, not one
  // per line.
  FFlushTimer.Enabled := True;
end;

procedure TMarkdownViewer.HandleFlushTimer(Sender: TObject);
begin
  if FModel.TryFlush(Int64(GetTickCount64)) then
  begin
    if FModel.ShouldAutoFollow then
      ScrollOffset := MaxScrollOffset;
    ResolvePendingImages;
    UpdateScrollBar;
    Invalidate;
  end;
  // Chunks can keep arriving while the timer runs; it stops only once the
  // model has drained everything pending.
  FFlushTimer.Enabled := FModel.IsDirty;
end;

// ---------------------------------------------------------------------------
// hit testing

function TMarkdownViewer.LinkAt(const Point: TLayoutPointF; out Url: string): Boolean;
var
  Link: IMarkdownLink;
begin
  Url := '';
  Result := (FModel.DisplayList <> nil) and
    TMarkdownHitTester.TryFindLink(FModel.DisplayList, Point, Link) and
    (Link <> nil);
  if Result then
    Url := Link.Destination;
end;

function TMarkdownViewer.PointOnCopyButton(const Point: TLayoutPointF): Boolean;
begin
  Result := FCodeHoverActive and FCopyButtonRect.Contains(Point);
end;

procedure TMarkdownViewer.UpdateHoverCursor(const Point: TLayoutPointF);
var
  Url: string;
  Key: Integer;
begin
  if PointOnCopyButton(Point) then
  begin
    Cursor := crHandPoint;
    Exit;
  end;

  if LinkAt(Point, Url) then
  begin
    if Url <> FHoveredLinkUrl then
    begin
      FHoveredLinkUrl := Url;
      if Assigned(FOnLinkHover) then
        FOnLinkHover(Self, Url);
    end;
    Cursor := crHandPoint;
    Exit;
  end;

  if (FModel.DisplayList <> nil) and FModel.TryGetDisclosureAt(Point, Key) then
  begin
    Cursor := crHandPoint;
    Exit;
  end;

  if FHoveredLinkUrl <> '' then
  begin
    FHoveredLinkUrl := '';
    if Assigned(FOnLinkHover) then
      FOnLinkHover(Self, '');
  end;
  Cursor := crDefault;
end;

procedure TMarkdownViewer.UpdateCodeHover(const Point: TLayoutPointF);
var
  Region: TMarkdownCodeBlockRegion;
  Left: Single;
begin
  if (FModel.DisplayList = nil) or not FModel.TryGetCodeBlockAt(Point, Region) then
  begin
    ClearCodeHover;
    Exit;
  end;

  Left := Region.Rect.Right - CopyButtonMargin - CopyButtonWidth;
  FCodeHoverRect := Region.Rect;
  FCodeHoverText := Region.Text;
  FCopyButtonRect := TLayoutRectF.Create(Left, Region.Rect.Top + CopyButtonMargin,
    Left + CopyButtonWidth, Region.Rect.Top + CopyButtonMargin + CopyButtonHeight);
  if not FCodeHoverActive then
  begin
    FCodeHoverActive := True;
    FCopyFeedback := False;
    Invalidate;
  end;
end;

procedure TMarkdownViewer.ClearCodeHover;
begin
  if not FCodeHoverActive then
    Exit;
  FCodeHoverActive := False;
  FCopyFeedback := False;
  FFeedbackTimer.Enabled := False;
  Invalidate;
end;

// ---------------------------------------------------------------------------
// input

function TMarkdownViewer.IsDoubleClick(const X, Y: Integer): Boolean;
var
  Now_: QWord;
  IsNear: Boolean;
begin
  Now_ := GetTickCount64;
  IsNear := (Abs(X - FLastClickPoint.X) <= DoubleClickSlack) and
            (Abs(Y - FLastClickPoint.Y) <= DoubleClickSlack);
  if IsNear and (Now_ - FLastClickTick <= DoubleClickMilliseconds) then
    Inc(FClickCount)
  else
    FClickCount := 1;
  FLastClickTick := Now_;
  FLastClickPoint := Point(X, Y);
  Result := FClickCount > 1;
end;

// A control can only take the focus once the form holding it is on screen;
// asking before that raises rather than doing nothing.
procedure TMarkdownViewer.TakeFocus;
var
  Form: TCustomForm;
begin
  if not CanFocus then
    Exit;
  Form := GetParentForm(Self);
  if (Form <> nil) and not Form.Showing then
    Exit;
  SetFocus;
end;

procedure TMarkdownViewer.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Point: TLayoutPointF;
  Url: string;
  Key: Integer;
  Region: TMarkdownCodeBlockRegion;
begin
  inherited MouseDown(Button, Shift, X, Y);

  if FAutoScroller.TryHandlePress(Button, X, Y) then
    Exit;

  if Button <> mbLeft then
    Exit;
  TakeFocus;

  Point := ContentPointOf(X, Y);
  if PointOnCopyButton(Point) then
  begin
    if FModel.TryGetCodeBlockAt(Point, Region) then
      CopyCodeAt(Region);
    Exit;
  end;

  if FModel.TryGetDisclosureAt(Point, Key) then
  begin
    FModel.ToggleDisclosure(Key);
    UpdateScrollBar;
    Invalidate;
    Exit;
  end;

  if FModel.TryBeginScrollerDrag(Point) then
  begin
    Invalidate;
    Exit;
  end;

  if LinkAt(Point, Url) then
  begin
    FPressedLinkUrl := Url;
    Exit;
  end;

  FPressedLinkUrl := '';
  FSelecting := True;
  if IsDoubleClick(X, Y) then
  begin
    if FClickCount >= 3 then
      FModel.SelectLineAt(Point)
    else
      FModel.SelectWordAt(Point);
  end
  else
    FModel.SetSelectionAnchor(Point);
  Invalidate;
end;

procedure TMarkdownViewer.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Point: TLayoutPointF;
begin
  inherited MouseMove(Shift, X, Y);

  if FAutoScroller.IsActive then
  begin
    FAutoScroller.HandleMove(X, Y);
    Exit;
  end;

  Point := ContentPointOf(X, Y);

  if FModel.IsDraggingScroller then
  begin
    FModel.DragScrollerThumb(Point);
    Invalidate;
    Exit;
  end;

  if FSelecting then
  begin
    FModel.SetSelectionExtent(Point);
    Invalidate;
    // dragging past an edge scrolls, as every text view does
    if Y < 0 then
      ScrollDocumentBy(Y)
    else if Y > ClientHeight then
      ScrollDocumentBy(Y - ClientHeight);
    Exit;
  end;

  UpdateCodeHover(Point);
  UpdateHoverCursor(Point);
end;

procedure TMarkdownViewer.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Point: TLayoutPointF;
  Url: string;
begin
  inherited MouseUp(Button, Shift, X, Y);

  if Button = mbMiddle then
  begin
    FAutoScroller.HandleMiddleUp;
    Exit;
  end;

  if Button <> mbLeft then
    Exit;

  if FModel.IsDraggingScroller then
  begin
    FModel.EndScrollerDrag;
    Invalidate;
    Exit;
  end;

  FSelecting := False;

  if FPressedLinkUrl = '' then
    Exit;

  Url := FPressedLinkUrl;
  FPressedLinkUrl := '';
  Point := ContentPointOf(X, Y);
  if LinkAt(Point, Url) and (Url <> '') then
  begin
    if (Url <> '') and (Url[1] = '#') and ScrollToAnchor(Url) then
      Exit;
    if Assigned(FOnLinkClick) then
      FOnLinkClick(Self, Url);
  end;
end;

function TMarkdownViewer.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Point: TPoint;
  Notches: Single;
begin
  if FAutoScroller.IsActive then
  begin
    FAutoScroller.Stop;
    Result := True;
    Exit;
  end;

  Notches := WheelDelta / NotchDelta;

  if ssCtrl in Shift then
  begin
    if Notches > 0 then
      SetZoom(TMarkdownZoom.StepIn(GetZoom))
    else
      SetZoom(TMarkdownZoom.StepOut(GetZoom));
    Result := True;
    Exit;
  end;

  if ssShift in Shift then
  begin
    Point := ScreenToClient(MousePos);
    Result := FModel.ScrollSideways(ContentPointOf(Point.X, Point.Y), -Notches * 40);
    if Result then
      Invalidate;
    Exit;
  end;

  ScrollDocumentBy(-Notches * ScrollLinesPerNotch * ScrollLineHeight);
  Result := True;
end;

procedure TMarkdownViewer.KeyDown(var Key: Word; Shift: TShiftState);
var
  Page: Single;
  Action: TMarkdownZoomAction;
  Text: string;
begin
  if FAutoScroller.IsActive then
  begin
    FAutoScroller.Stop;
    Key := 0;
    Exit;
  end;

  inherited KeyDown(Key, Shift);

  Page := Max(1, ClientHeight - ScrollLineHeight);

  if ssCtrl in Shift then
  begin
    Action := TMarkdownZoom.ActionOfKey(Key);
    case Action of
      TMarkdownZoomAction.StepIn: begin SetZoom(TMarkdownZoom.StepIn(GetZoom)); Key := 0; Exit; end;
      TMarkdownZoomAction.StepOut: begin SetZoom(TMarkdownZoom.StepOut(GetZoom)); Key := 0; Exit; end;
      TMarkdownZoomAction.Reset: begin SetZoom(TMarkdownZoom.DefaultPercent); Key := 0; Exit; end;
    else
      ; // not a zoom key
    end;

    case Key of
      Ord('A'):
        begin
          SelectAll;
          Key := 0;
        end;
      Ord('C'):
        begin
          CopyForShortcut(Shift);
          Key := 0;
        end;
    end;
    Exit;
  end;

  case Key of
    VK_UP: ScrollDocumentBy(-ScrollLineHeight);
    VK_DOWN: ScrollDocumentBy(ScrollLineHeight);
    VK_PRIOR: ScrollDocumentBy(-Page);
    VK_NEXT: ScrollDocumentBy(Page);
    VK_HOME: SetScrollOffset(0);
    VK_END: SetScrollOffset(MaxScrollOffset);
  else
    Exit;
  end;
  Key := 0;
end;

// ---------------------------------------------------------------------------
// anchors

function TMarkdownViewer.ScrollToAnchor(const Anchor: string): Boolean;
var
  Offset: Single;
  Name: string;
begin
  Name := Anchor;
  if (Name <> '') and (Name[1] = '#') then
    Delete(Name, 1, 1);
  Result := (Name <> '') and FModel.TryGetAnchorOffset(Name, Offset);
  if Result then
    SetScrollOffset(Offset);
end;

function TMarkdownViewer.Outline: TArray<TMarkdownOutlineEntry>;
var
  Toc: IMarkdownToc;
  I: Integer;
  Offset: Single;

  procedure Collect(const Entry: IMarkdownTocEntry);
  var
    I: Integer;
    Name: string;
    Slot: Integer;
  begin
    Name := Entry.Anchor;
    if (Name <> '') and (Name[1] = '#') then
      Delete(Name, 1, 1);
    Slot := Length(Result);
    SetLength(Result, Slot + 1);
    Result[Slot].Level := Entry.Level;
    Result[Slot].Caption := Entry.Caption;
    Result[Slot].Anchor := Name;
    Result[Slot].SourceLine := Entry.SourceLine;
    // A heading the layout has not reached - one inside an unopened details
    // block, say - keeps -1 so a panel can show it as unresolvable.
    if FModel.TryGetAnchorOffset(Name, Offset) then
      Result[Slot].ScrollOffset := Offset
    else
      Result[Slot].ScrollOffset := -1;
    for I := 0 to Entry.ChildCount - 1 do
      Collect(Entry.Children[I]);
  end;

begin
  Result := nil;
  if FModel.Document = nil then
    Exit;
  Toc := TMarkdownToc.FromDocument(FModel.Document);
  for I := 0 to Toc.EntryCount - 1 do
    Collect(Toc.Entries[I]);
end;

function TMarkdownViewer.ScrollToOutlineEntry(
  const Entry: TMarkdownOutlineEntry): Boolean;
begin
  Result := ScrollToAnchor(Entry.Anchor);
end;

// ---------------------------------------------------------------------------
// autoscroll and the right-click menu

function TMarkdownViewer.GetAutoScroll: Boolean;
begin
  Result := FAutoScroll;
end;

procedure TMarkdownViewer.SetAutoScroll(const Value: Boolean);
begin
  FAutoScroll := Value;
  if not Value then
    FAutoScroller.Stop;
end;

function TMarkdownViewer.GetIsAutoScrolling: Boolean;
begin
  Result := FAutoScroller.IsActive;
end;

function TMarkdownViewer.CanAutoScroll: Boolean;
begin
  Result := ContentHeight > ClientHeight;
end;

procedure TMarkdownViewer.AutoScrollBy(const Delta: Single);
begin
  ScrollDocumentBy(Delta);
end;

procedure TMarkdownViewer.AutoScrollChanged;
begin
  if Assigned(FOnAutoScrollChange) then
    FOnAutoScrollChange(Self);
  Invalidate;
end;

procedure TMarkdownViewer.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
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

procedure TMarkdownViewer.ShowContextMenu(const X, Y: Integer);
var
  Item: TViewerContextItem;
  Separator: TMenuItem;
  Entry: TMenuItem;
  Origin: TPoint;
const
  MenuSeparatorCaption = '-';
begin
  if FContextMenu = nil then
    FContextMenu := TPopupMenu.Create(Self);

  FContextMenu.Items.Clear;

  for Item in TMarkdownViewerContextMenu.Build(FModel, FCopyAsMarkdown) do
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

procedure TMarkdownViewer.HandleContextItemClick(Sender: TObject);
var
  Command: TViewerContextCommand;
begin
  Command := TViewerContextCommand((Sender as TMenuItem).Tag);

  if TMarkdownViewerContextMenu.Execute(FModel, Command) then
  begin
    Invalidate;
    Exit;
  end;

  case Command of
    TViewerContextCommand.Copy           : CopyToClipboard(FModel.SelectedText);
    TViewerContextCommand.CopyAsMarkdown : CopySelectionAsMarkdown;
  end;

  Invalidate;
end;

end.
