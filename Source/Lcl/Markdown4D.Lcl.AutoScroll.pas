unit Markdown4D.Lcl.AutoScroll;
{ Middle-click autoscroll for an LCL control, over the framework-neutral
  TMarkdownAutoScroll. It holds the mouse, steps the scrolling on a timer from
  wherever the pointer is, and shows a pan cursor for the direction.

  The VCL build paints its own pan cursors from user32 and re-shows the window
  cursor by hand; the LCL one runs on several widgetsets, so it sets the
  control's Cursor instead - crSizeNS everywhere, the real pan cursors on
  Windows - and puts it back when autoscroll ends. }

{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}

{$SCOPEDENUMS ON}

interface

uses
  Classes, Types, Controls, ExtCtrls,
  Markdown4D.Layout.Interfaces,
  Markdown4D.AutoScroll,
  Markdown4D.AutoScroll.Icon,
  Markdown4D.AutoScroll.Cursors;

type
  TMarkdownLclAutoScroller = class
  private const
    TickMilliseconds = 16;
  private var
    FControl: TControl;
    FTarget: IMarkdownAutoScrollTarget;
    FAutoScroll: TMarkdownAutoScroll;
    FTimer: TTimer;
    FEnabled: Boolean;
    FStoppedByRightClick: Boolean;
    procedure HandleTimer(Sender: TObject);
    procedure SetEnabled(const Value: Boolean);
    function TryStart(const X, Y: Integer): Boolean;
    function PointerInControl: TPoint;
    function Scale: Single;
    procedure ShowCursor(const PointerY: Integer);
    procedure RestoreCursor;
  public
    constructor Create(const Control: TControl; const Target: IMarkdownAutoScrollTarget);
    destructor Destroy; override;
    function IsActive: Boolean;
    // A press while autoscrolling only ends it; a middle press starts it.
    // True when the press is taken.
    function TryHandlePress(const Button: TMouseButton; const X, Y: Integer): Boolean;
    // True once after a right click ended autoscroll, so that click opens no
    // context menu either.
    function TakeSuppressedMenu: Boolean;
    procedure HandleMove(const X, Y: Integer);
    procedure HandleMiddleUp;
    procedure Stop;
    procedure PaintOrigin(const Painter: IPainter;
      const BackgroundColor, TextColor: TLayoutColor);
    property Enabled: Boolean read FEnabled write SetEnabled;
  end;

implementation

uses
  SysUtils, LCLType,
  Markdown4D.Compat.UITypes;

constructor TMarkdownLclAutoScroller.Create(const Control: TControl;
  const Target: IMarkdownAutoScrollTarget);
begin
  inherited Create;

  FControl := Control;
  FTarget := Target;
  FEnabled := True;

  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TickMilliseconds;
  FTimer.OnTimer := HandleTimer;
end;

destructor TMarkdownLclAutoScroller.Destroy;
begin
  FTimer.Free;

  inherited Destroy;
end;

function TMarkdownLclAutoScroller.IsActive: Boolean;
begin
  Result := FAutoScroll.IsActive;
end;

procedure TMarkdownLclAutoScroller.SetEnabled(const Value: Boolean);
begin
  FEnabled := Value;
  if not Value then
    Stop;
end;

function TMarkdownLclAutoScroller.TryHandlePress(const Button: TMouseButton;
  const X, Y: Integer): Boolean;
var
  Focusable: TWinControl;
begin
  if IsActive then
  begin
    FStoppedByRightClick := (Button = TMouseButton.mbRight);
    Stop;
    Result := True;
    Exit;
  end;

  Result := (Button = TMouseButton.mbMiddle) and FEnabled;
  if not Result then
    Exit;

  if FControl is TWinControl then
  begin
    Focusable := TWinControl(FControl);
    if Focusable.CanFocus then
      Focusable.SetFocus;
  end;

  TryStart(X, Y);
end;

function TMarkdownLclAutoScroller.TakeSuppressedMenu: Boolean;
begin
  Result := FStoppedByRightClick;
  FStoppedByRightClick := False;
end;

function TMarkdownLclAutoScroller.TryStart(const X, Y: Integer): Boolean;
begin
  Result := FEnabled and (FTarget <> nil) and FTarget.CanAutoScroll;
  if not Result then
    Exit;

  FAutoScroll.Start(X, Y, Scale, GetTickCount64);
  SetCaptureControl(FControl);
  FTimer.Enabled := True;

  ShowCursor(Y);
  FTarget.AutoScrollChanged;
end;

procedure TMarkdownLclAutoScroller.HandleMove(const X, Y: Integer);
begin
  if not IsActive then
    Exit;

  FAutoScroll.PointerMoved(X, Y);
  ShowCursor(Y);
end;

procedure TMarkdownLclAutoScroller.HandleMiddleUp;
var
  Stopped: Boolean;
begin
  if not IsActive then
    Exit;

  Stopped := FAutoScroll.Release;
  if Stopped then
    Stop;
end;

procedure TMarkdownLclAutoScroller.Stop;
var
  WasActive: Boolean;
begin
  WasActive := IsActive;

  FAutoScroll.Stop;
  FTimer.Enabled := False;
  if not WasActive then
    Exit;

  if GetCaptureControl = FControl then
    SetCaptureControl(nil);
  RestoreCursor;
  if FTarget <> nil then
    FTarget.AutoScrollChanged;
end;

procedure TMarkdownLclAutoScroller.RestoreCursor;
begin
  // The control reads its Cursor on every mouse move again, so the widgetset
  // under the pointer - link hand, text beam - takes over by itself.
  if FControl.Cursor = crSizeNS then
    FControl.Cursor := crDefault;
end;

procedure TMarkdownLclAutoScroller.PaintOrigin(const Painter: IPainter;
  const BackgroundColor, TextColor: TLayoutColor);
var
  Origin: TLayoutPointF;
begin
  if not IsActive then
    Exit;

  Origin := TLayoutPointF.Create(FAutoScroll.OriginX, FAutoScroll.OriginY);
  TMarkdownAutoScrollIcon.Paint(Painter, Origin, Scale, BackgroundColor, TextColor);
end;

procedure TMarkdownLclAutoScroller.HandleTimer(Sender: TObject);
var
  AtPointer: TPoint;
  Delta: Single;
begin
  if not IsActive then
  begin
    FTimer.Enabled := False;
    Exit;
  end;

  AtPointer := PointerInControl;
  ShowCursor(AtPointer.Y);

  Delta := FAutoScroll.Step(GetTickCount64, AtPointer.Y);
  if Delta <> 0 then
    FTarget.AutoScrollBy(Delta);
end;

function TMarkdownLclAutoScroller.PointerInControl: TPoint;
begin
  Result := FControl.ScreenToClient(Mouse.CursorPos);
end;

// The VCL build scales the speed by the monitor's DPI; the LCL keeps that
// factor private to TControl, so the speed is given in plain pixels. The
// record clamps the scale from below at 1 either way.
function TMarkdownLclAutoScroller.Scale: Single;
begin
  Result := 1;
end;

procedure TMarkdownLclAutoScroller.ShowCursor(const PointerY: Integer);
var
  Direction: TMarkdownAutoScrollDirection;
begin
  Direction := FAutoScroll.Direction(PointerY);
  // Windows has the pan cursors the browsers show; the other widgetsets get
  // the plain up-down arrow through the control's own cursor.
  if not TMarkdownAutoScrollCursors.TryApply(Direction) then
    FControl.Cursor := crSizeNS;
end;

end.
