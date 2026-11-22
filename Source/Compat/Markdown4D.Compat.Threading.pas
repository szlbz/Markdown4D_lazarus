unit Markdown4D.Compat.Threading;
{ System.Threading's TTask.Run, and a TThread.Queue that takes an anonymous
  method.  FPC's Queue wants a `procedure of object`, so the closure is held by
  a small object that frees itself once it has run. }

{$mode delphiunicode}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$H+}

interface

uses
  SysUtils, Classes, Markdown4D.Compat.Str;

type
  TTask = class
  public
    class procedure Run(const Body: TProc); static;
  end;

// Runs `Body` on the main thread, like TThread.Queue(nil, ...) does.
procedure M4DQueue(const Body: TProc);

implementation

type
  TM4DTaskThread = class(TThread)
  private
    FBody: TProc;
  protected
    procedure Execute; override;
  public
    constructor Create(const Body: TProc);
  end;

  TM4DQueuedProc = class
  private
    FBody: TProc;
  public
    constructor Create(const Body: TProc);
    procedure Run;
  end;

constructor TM4DTaskThread.Create(const Body: TProc);
begin
  FBody := Body;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TM4DTaskThread.Execute;
begin
  try
    if Assigned(FBody) then
      FBody();
  except
    // a background download must never take the process down
  end;
end;

class procedure TTask.Run(const Body: TProc);
begin
  TM4DTaskThread.Create(Body);
end;

constructor TM4DQueuedProc.Create(const Body: TProc);
begin
  inherited Create;
  FBody := Body;
end;

procedure TM4DQueuedProc.Run;
begin
  try
    if Assigned(FBody) then
      FBody();
  finally
    Free;
  end;
end;

procedure M4DQueue(const Body: TProc);
begin
  TThread.Queue(nil, TM4DQueuedProc.Create(Body).Run);
end;

end.
