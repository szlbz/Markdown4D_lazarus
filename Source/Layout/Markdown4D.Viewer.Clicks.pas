{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Viewer.Clicks;

{$SCOPEDENUMS ON}

interface

type
  // Counts a press as a single, double or triple click. The platform reports
  // the double click, by its own time and distance. No platform reports a
  // third, so a press that follows a double click closely enough is one.
  TMarkdownClickCounter = record
  public
    const
      // Windows' default double-click time and distance, for a platform that
      // does not report its own.
      DefaultIntervalMilliseconds = 500;
      DefaultTolerance = 2.0;
      SingleClick = 1;
      DoubleClick = 2;
      TripleClick = 3;

  private
    FLastCount: Integer;
    FLastTime: Int64;
    FLastX: Single;
    FLastY: Single;
    function FollowsDoubleClick(const TimeMilliseconds: Int64; const X, Y: Single;
      const IntervalMilliseconds: Cardinal; const Tolerance: Single): Boolean;

  public
    function RegisterPress(const TimeMilliseconds: Int64; const X, Y: Single; const IsDoubleClick: Boolean;
      const IntervalMilliseconds: Cardinal; const Tolerance: Single): Integer;
  end;

  TMarkdownClickKind = (None, Click, DoubleClick);

  // Decides on release whether a press was a click in the text for the host.
  // A press on a link, a button or one that ends autoscroll is no click, nor
  // is a press dragged past the threshold into a selection. The double click
  // comes on release too, as in browsers, so its handler can open a modal
  // window while no button is held.
  TMarkdownClickGesture = record
  public
    const
      // Windows' default drag distance, for a platform that does not report
      // its own.
      DefaultDragThreshold = 4.0;

  private
    FInText: Boolean;
    FClickCount: Integer;
    FPressX: Single;
    FPressY: Single;

  public
    procedure PressInText(const X, Y: Single; const ClickCount: Integer);
    procedure PressElsewhere;
    function Release(const X, Y, DragThreshold: Single): TMarkdownClickKind;
  end;

implementation

function TMarkdownClickCounter.RegisterPress(const TimeMilliseconds: Int64; const X, Y: Single;
  const IsDoubleClick: Boolean; const IntervalMilliseconds: Cardinal; const Tolerance: Single): Integer;
begin
  if FollowsDoubleClick(TimeMilliseconds, X, Y, IntervalMilliseconds, Tolerance) then
    Result := TripleClick
  else if IsDoubleClick then
    Result := DoubleClick
  else
    Result := SingleClick;

  FLastCount := Result;
  FLastTime := TimeMilliseconds;
  FLastX := X;
  FLastY := Y;
end;

function TMarkdownClickCounter.FollowsDoubleClick(const TimeMilliseconds: Int64; const X, Y: Single;
  const IntervalMilliseconds: Cardinal; const Tolerance: Single): Boolean;
var
  IsAfterDouble: Boolean;
  IsSoonEnough: Boolean;
  IsCloseEnough: Boolean;
begin
  IsAfterDouble := (FLastCount = DoubleClick);
  IsSoonEnough := (TimeMilliseconds - FLastTime <= IntervalMilliseconds);
  IsCloseEnough := ((Abs(X - FLastX) <= Tolerance) and (Abs(Y - FLastY) <= Tolerance));

  Result := IsAfterDouble and IsSoonEnough and IsCloseEnough;
end;

procedure TMarkdownClickGesture.PressInText(const X, Y: Single; const ClickCount: Integer);
begin
  FInText := True;
  FClickCount := ClickCount;
  FPressX := X;
  FPressY := Y;
end;

procedure TMarkdownClickGesture.PressElsewhere;
begin
  FInText := False;
end;

function TMarkdownClickGesture.Release(const X, Y, DragThreshold: Single): TMarkdownClickKind;
var
  WasInText: Boolean;
  IsDragged: Boolean;
  IsDoubleClick: Boolean;
begin
  Result := TMarkdownClickKind.None;

  WasInText := FInText;
  FInText := False;
  if not WasInText then
    Exit;

  IsDragged := ((Abs(X - FPressX) > DragThreshold) or (Abs(Y - FPressY) > DragThreshold));
  if IsDragged then
    Exit;

  IsDoubleClick := (FClickCount = TMarkdownClickCounter.DoubleClick);
  if IsDoubleClick then
    Result := TMarkdownClickKind.DoubleClick
  else
    Result := TMarkdownClickKind.Click;
end;

end.