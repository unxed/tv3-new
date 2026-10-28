{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/termctrl.h, source/tvterm-core/termctrl.cc, include/tvterm/termemu.h,
  include/tvterm/pty.h
  See COPYRIGHT.tvterm.

  The controller that joins a pseudo terminal and a terminal emulator. Two threads of the run-time library work on
  the client: the writer loop waits for a wake-up or for the time that the last read of data set, takes the events
  of the view, gives them to the emulator, updates the state under the lock and writes what the emulator answers to
  the client; the reader loop reads the client's output and gives it to the emulator. A program that uses a
  controller must use the unit cthreads on Unix, first in the uses clause of the program.

  The controller is owned by the user until ShutDown, and by the two loops until they end: it frees itself when the
  last of the three lets go. }
unit TvVtCtrl;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvPty, TvVtCore;

type
  TerminalController = class;

  TCharBytes = array of Char;

  { The routine that LockState runs with the state. }
  TStateProc = procedure(State: TerminalState) of object;

  { The queue of events that the view sends to the loops. }
  TQueuedEvents = class
  private
    FSlots: array of TerminalEvent;
    FFirst: SizeInt;
    FCount: SizeInt;
  public
    procedure Push(const Ev: TerminalEvent);
    { False when the queue is empty. }
    function Pop(out Ev: TerminalEvent): Boolean;
  end;

  { Collects the bytes that the emulator wants to send to the client. }
  GrowArrayWriter = class(Writer)
  public
    Buffer: GrowArray;
    constructor Create;
    destructor Destroy; override;
    procedure Write(const Data: array of Char); override;
  end;

  { The data and the work of the threads of a controller. FLock grants exclusive access to the fields of the loop
    and to the emulator. }
  TerminalEventLoop = class
  private
    FCtrl: TerminalController;
    FLock: TRTLCriticalSection;
    FTerminated: LongInt;
    FQueue: TQueuedEvents;
    FQueueLock: TRTLCriticalSection;
    { Points in time in milliseconds; 0 is no time. }
    FCurrentTimeout: QWord;
    FMaxReadTimeout: QWord;
    FWake: PRTLEvent;
    FClientDataWriter: GrowArrayWriter;
    FViewportResized: Boolean;
    FViewportSize: TPoint;
    function IsTerminated: Boolean;
    procedure WaitForWake(Due: QWord);
    procedure ProcessEvents;
    procedure UpdateEmulatorState(var Item: TerminalState);
    procedure UpdateState(var Updated: Boolean);
    procedure UpdateTimeouts;
    procedure TakePending(var Dest: TCharBytes);
    procedure WritePendingData(const OutputBuffer: array of Char; var Updated: Boolean);
    procedure NotifyMainThread;
  public
    constructor Create(ACtrl: TerminalController);
    destructor Destroy; override;
    procedure RunWriterLoop;
    procedure RunReaderLoop;
  end;

  TerminalController = class
  private
    FPty: PtyMaster;
    FState: TerminalState;
    FStateLock: specialize Mutex<TerminalState>;
    FLoop: TerminalEventLoop;
    FEmulator: TerminalEmulator;
    FUpdated: LongInt;
    FDisconnected: LongInt;
    { The holders of the controller: the user and the two loops. }
    FHolders: LongInt;
    constructor Create(const ASize: TPoint; AFactory: TerminalEmulatorFactory; ADescriptor: PtyDescriptor);
      reintroduce;
    procedure LetGo;
  public
    destructor Destroy; override;
    { Gives a new controller. On error calls OnError and gives nil. }
    class function Make(ASize: TPoint; AFactory: TerminalEmulatorFactory;
      OnError: TPtyErrorProc): TerminalController;
    { Takes the ownership of the controller: it is freed when the loops have ended. }
    procedure ShutDown;
    procedure SendEvent(const Event: TerminalEvent);
    { True once for every change of the state since the last call. }
    function StateHasBeenUpdated: Boolean;
    function ClientIsDisconnected: Boolean;
    { Runs Func with the state while a lock is held; a call of LockState inside Func waits for ever on another
      thread and works on the same one, because the lock is recursive. }
    procedure LockState(Func: TStateProc);
  end;

implementation

uses
  Classes, SysUtils, TvSys;

const
  MaxReadTimeMs = 20;
  ReadWaitStepMs = 5;
  ReadBufSize = 4096;

type
  { Adapts a TStateProc to the procedure that the lock of TvVtCore takes. }
  TStateRunner = class
  private
    FFunc: TStateProc;
  public
    constructor Create(AFunc: TStateProc);
    procedure Call(var Item: TerminalState);
  end;

  TLoopRole = (lrWriter, lrReader);

  TLoopThread = class(TThread)
  private
    FLoop: TerminalEventLoop;
    FRole: TLoopRole;
  protected
    procedure Execute; override;
  public
    constructor Create(ALoop: TerminalEventLoop; ARole: TLoopRole); reintroduce;
  end;

{ The clock of the loops: milliseconds, never 0. }
function NowTicks: QWord;
begin
  Result := GetTickCount64 + 1;
end;

{ TQueuedEvents }

procedure TQueuedEvents.Push(const Ev: TerminalEvent);
var
  Wider: array of TerminalEvent;
  Room, K: SizeInt;
begin
  Room := Length(FSlots);
  if FCount = Room then
  begin
    SetLength(Wider, Room * 2 + 8);
    for K := 0 to FCount - 1 do
      Wider[K] := FSlots[(FFirst + K) mod Room];
    FSlots := Wider;
    FFirst := 0;
    Room := Length(FSlots);
  end;
  FSlots[(FFirst + FCount) mod Room] := Ev;
  Inc(FCount);
end;

function TQueuedEvents.Pop(out Ev: TerminalEvent): Boolean;
begin
  Result := FCount > 0;
  if not Result then
    Exit;
  Ev := FSlots[FFirst];
  FFirst := (FFirst + 1) mod Length(FSlots);
  Dec(FCount);
end;

{ GrowArrayWriter }

constructor GrowArrayWriter.Create;
begin
  inherited Create;
  Buffer := GrowArray.Create;
end;

destructor GrowArrayWriter.Destroy;
begin
  Buffer.Free;
  inherited Destroy;
end;

procedure GrowArrayWriter.Write(const Data: array of Char);
begin
  if Length(Data) > 0 then
    Buffer.Push(PAnsiChar(@Data[0]), Length(Data));
end;

{ TStateRunner }

constructor TStateRunner.Create(AFunc: TStateProc);
begin
  inherited Create;
  FFunc := AFunc;
end;

procedure TStateRunner.Call(var Item: TerminalState);
begin
  FFunc(Item);
end;

{ TLoopThread }

constructor TLoopThread.Create(ALoop: TerminalEventLoop; ARole: TLoopRole);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FLoop := ALoop;
  FRole := ARole;
end;

procedure TLoopThread.Execute;
var
  Owner: TerminalController;
begin
  Owner := FLoop.FCtrl;
  try
    if FRole = lrWriter then
      FLoop.RunWriterLoop
    else
      FLoop.RunReaderLoop;
  finally
    { May free the controller and with it the loop. }
    Owner.LetGo;
  end;
end;

{ TerminalEventLoop }

constructor TerminalEventLoop.Create(ACtrl: TerminalController);
begin
  inherited Create;
  FCtrl := ACtrl;
  InitCriticalSection(FLock);
  InitCriticalSection(FQueueLock);
  FQueue := TQueuedEvents.Create;
  FWake := RTLEventCreate;
  FClientDataWriter := GrowArrayWriter.Create;
  FTerminated := 0;
  FCurrentTimeout := 0;
  FMaxReadTimeout := 0;
  FViewportResized := False;
  FViewportSize.X := 0;
  FViewportSize.Y := 0;
end;

destructor TerminalEventLoop.Destroy;
begin
  FClientDataWriter.Free;
  RTLEventDestroy(FWake);
  FQueue.Free;
  DoneCriticalSection(FQueueLock);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TerminalEventLoop.IsTerminated: Boolean;
begin
  Result := InterlockedCompareExchange(FTerminated, 0, 0) <> 0;
end;

{ Waits for a wake-up, or until the time Due when it is not 0. A wake-up that came before the wait is not lost. }
procedure TerminalEventLoop.WaitForWake(Due: QWord);
var
  Instant, Span: QWord;
begin
  if Due = 0 then
    RTLEventWaitFor(FWake)
  else
  begin
    Instant := NowTicks;
    if Due > Instant then
      Span := Due - Instant
    else
      Span := 0;
    RTLEventWaitFor(FWake, LongInt(Span));
  end;
  RTLEventResetEvent(FWake);
end;

{ Pre: FLock is held. }
procedure TerminalEventLoop.ProcessEvents;
var
  Ev: TerminalEvent;
  Found: Boolean;
begin
  repeat
    EnterCriticalSection(FQueueLock);
    try
      Found := FQueue.Pop(Ev);
    finally
      LeaveCriticalSection(FQueueLock);
    end;
    if Found then
    begin
      if Ev.Type_ = TerminalEventType.ViewportResize then
      begin
        { The client is not resized yet; UpdateState does it. }
        FViewportSize.X := Ev.ViewportResize.X;
        FViewportSize.Y := Ev.ViewportResize.Y;
        FViewportResized := True;
      end
      else
        FCtrl.FEmulator.HandleEvent(Ev);
    end;
  until not Found;
end;

procedure TerminalEventLoop.UpdateEmulatorState(var Item: TerminalState);
begin
  FCtrl.FEmulator.UpdateState(Item);
end;

{ Pre: FLock is held. }
procedure TerminalEventLoop.UpdateState(var Updated: Boolean);
var
  Ev: TerminalEvent;
begin
  { The time of a millisecond clock is reached when it is not before the time that was set. }
  if NowTicks >= FCurrentTimeout then
  begin
    Updated := True;
    FCurrentTimeout := 0;
    FMaxReadTimeout := 0;
    FCtrl.FStateLock.Lock(@UpdateEmulatorState);
  end;

  if (FCurrentTimeout = 0) and FViewportResized then
  begin
    { The resize waits for a time-out and for the update of the state, because the client is then probably drawn
      properly. }
    FViewportResized := False;
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.Type_ := TerminalEventType.ViewportResize;
    Ev.ViewportResize.X := FViewportSize.X;
    Ev.ViewportResize.Y := FViewportSize.Y;
    FCtrl.FEmulator.HandleEvent(Ev);
    FCtrl.FPty.ResizeClient(FViewportSize);
  end;
end;

{ Pre: FLock is held. Data is flushed ReadWaitStepMs after the last read, or MaxReadTimeMs after the first. }
procedure TerminalEventLoop.UpdateTimeouts;
var
  Instant, Soon: QWord;
begin
  Instant := NowTicks;
  if FMaxReadTimeout = 0 then
    FMaxReadTimeout := Instant + MaxReadTimeMs;
  Soon := Instant + ReadWaitStepMs;
  if Soon < FMaxReadTimeout then
    FCurrentTimeout := Soon
  else
    FCurrentTimeout := FMaxReadTimeout;
end;

{ Pre: FLock is held. Moves the pending bytes of the writer to Dest. }
procedure TerminalEventLoop.TakePending(var Dest: TCharBytes);
var
  Amount: SizeInt;
begin
  Amount := SizeInt(FClientDataWriter.Buffer.Size);
  SetLength(Dest, Amount);
  if Amount > 0 then
  begin
    Move(FClientDataWriter.Buffer.Data^, Dest[0], Amount);
    FClientDataWriter.Buffer.Clear;
  end;
end;

{ FLock needs not be held. }
procedure TerminalEventLoop.WritePendingData(const OutputBuffer: array of Char; var Updated: Boolean);
begin
  if Length(OutputBuffer) = 0 then
    Exit;
  if (not FCtrl.ClientIsDisconnected) and (not FCtrl.FPty.WriteToClient(OutputBuffer)) then
  begin
    InterlockedExchange(FCtrl.FDisconnected, 1);
    Updated := True;
  end;
end;

procedure TerminalEventLoop.NotifyMainThread;
begin
  InterlockedExchange(FCtrl.FUpdated, 1);
  if TEventQueue.Backend <> nil then
    TEventQueue.WakeUp;
end;

procedure TerminalEventLoop.RunWriterLoop;
var
  Outgoing: TCharBytes;
  Flushed: Boolean;
  Due: QWord;
begin
  SetLength(Outgoing, 0);
  while True do
  begin
    Flushed := False;

    EnterCriticalSection(FLock);
    Due := FCurrentTimeout;
    LeaveCriticalSection(FLock);
    WaitForWake(Due);

    EnterCriticalSection(FLock);
    try
      if IsTerminated then
      begin
        FCtrl.FPty.Disconnect;
        Break;
      end;
      ProcessEvents;
      UpdateState(Flushed);
      TakePending(Outgoing);
    finally
      LeaveCriticalSection(FLock);
    end;

    WritePendingData(Outgoing, Flushed);
    SetLength(Outgoing, 0);

    if Flushed then
      NotifyMainThread;
  end;
end;

procedure TerminalEventLoop.RunReaderLoop;
var
  InputBuffer: array[0..ReadBufSize - 1] of Char;
  Got: SizeUInt;
  ReadOk, Flushed: Boolean;
  Ev: TerminalEvent;
begin
  while True do
  begin
    Got := 0;
    ReadOk := FCtrl.FPty.ReadFromClient(InputBuffer, Got);

    if (not ReadOk) or (Got = 0) then
    begin
      InterlockedExchange(FCtrl.FDisconnected, 1);
      NotifyMainThread;
      Break;
    end;

    { All the data of the client is read, even after the shut down. }
    if IsTerminated then
      Continue;

    Flushed := False;
    EnterCriticalSection(FLock);
    try
      FillChar(Ev, SizeOf(Ev), 0);
      Ev.Type_ := TerminalEventType.ClientDataRead;
      Ev.ClientDataRead.Data := PAnsiChar(@InputBuffer[0]);
      Ev.ClientDataRead.Size := Got;
      FCtrl.FEmulator.HandleEvent(Ev);

      UpdateTimeouts;

      { The events and the update are also done here, because a lock may be unfair: while the client keeps sending,
        this loop could take the lock several times before the writer loop wakes up. }
      ProcessEvents;
      UpdateState(Flushed);
    finally
      LeaveCriticalSection(FLock);
    end;

    if Flushed then
      NotifyMainThread;
    { The writer loop uses the new time-outs and writes the pending data. }
    RTLEventSetEvent(FWake);
  end;
end;

{ TerminalController }

constructor TerminalController.Create(const ASize: TvGeom.TPoint; AFactory: TerminalEmulatorFactory;
  ADescriptor: PtyDescriptor);
begin
  inherited Create;
  FHolders := 3;
  FUpdated := 0;
  FDisconnected := 0;
  FPty := PtyMaster.Create(ADescriptor);
  FState := TerminalState.Create;
  FStateLock := specialize Mutex<TerminalState>.Create(FState);
  FLoop := TerminalEventLoop.Create(Self);
  FEmulator := AFactory.Make(ASize, FLoop.FClientDataWriter);
end;

destructor TerminalController.Destroy;
begin
  FEmulator.Free;
  FLoop.Free;
  FStateLock.Free;
  FState.Free;
  FPty.Free;
  inherited Destroy;
end;

procedure TerminalController.LetGo;
begin
  if InterlockedDecrement(FHolders) = 0 then
    Free;
end;

class function TerminalController.Make(ASize: TvGeom.TPoint; AFactory: TerminalEmulatorFactory;
  OnError: TPtyErrorProc): TerminalController;
var
  Span: TEnvironmentVarSpan;
  Vars: array of EnvironmentVar;
  Cursor: PEnvironmentVar;
  Desc: PtyDescriptor;
  K: SizeInt;
begin
  Result := nil;
  Span := AFactory.GetCustomEnvironment;
  SetLength(Vars, SizeInt(Span.Size));
  Cursor := Span.Data;
  for K := 0 to High(Vars) do
  begin
    Vars[K] := Cursor^;
    Inc(Cursor);
  end;

  if not CreatePty(Desc, ASize, Vars, OnError) then
    Exit;

  Result := TerminalController.Create(ASize, AFactory, Desc);
  TLoopThread.Create(Result.FLoop, lrWriter).Start;
  TLoopThread.Create(Result.FLoop, lrReader).Start;
end;

procedure TerminalController.ShutDown;
begin
  EnterCriticalSection(FLoop.FLock);
  try
    InterlockedExchange(FLoop.FTerminated, 1);
  finally
    LeaveCriticalSection(FLoop.FLock);
  end;
  RTLEventSetEvent(FLoop.FWake);
  { May free the controller. }
  LetGo;
end;

procedure TerminalController.SendEvent(const Event: TerminalEvent);
begin
  EnterCriticalSection(FLoop.FQueueLock);
  try
    FLoop.FQueue.Push(Event);
  finally
    LeaveCriticalSection(FLoop.FQueueLock);
  end;
  RTLEventSetEvent(FLoop.FWake);
end;

function TerminalController.StateHasBeenUpdated: Boolean;
begin
  Result := InterlockedExchange(FUpdated, 0) = 1;
end;

function TerminalController.ClientIsDisconnected: Boolean;
begin
  Result := InterlockedCompareExchange(FDisconnected, 0, 0) <> 0;
end;

procedure TerminalController.LockState(Func: TStateProc);
var
  Runner: TStateRunner;
begin
  Runner := TStateRunner.Create(Func);
  try
    FStateLock.Lock(@Runner.Call);
  finally
    Runner.Free;
  end;
end;

end.
