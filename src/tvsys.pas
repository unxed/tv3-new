{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (TEventQueue), source/tvision/tevent.cpp,
  include/tvision/internal/events.h, source/platform/events.cpp,
  include/tvision/hardware.h (getButtonCount, cursorOn, cursorOff)
  See COPYRIGHT.magiblot.

  The unit is for Unix systems: the wake-up source is a pipe. The wake-up sources of Windows and DOS are not
  part of it. The detection of a paste by a count of consecutive text events is not part of it either, because
  the constant of that count is not in the C++ sources; the paste text (SetPasteText) is. }
unit TvSys;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  ctypes, UnixType, BaseUnix, TvEvents;

type
  { The handle that a thread waits on: a file descriptor. }
  TSysHandle = cint;
  TSysManualEventHandle = TFilDes;

  { A signal that stays set until it is cleared: a pipe. }
  TSysManualEvent = class
  private
    FHandle: TSysManualEventHandle;
  public
    class function CreateHandle(var Handle: TSysManualEventHandle): Boolean; static;
    class function GetWaitableHandle(const Handle: TSysManualEventHandle): TSysHandle; static;
    { Takes over Handle, which Destroy closes. }
    constructor Create(const AHandle: TSysManualEventHandle);
    destructor Destroy; override;
    procedure Signal;
    procedure Clear;
  end;

  { A source of events that the waiter polls through Handle. }
  TEventSource = class
  private
    FHandle: TSysHandle;
  public
    constructor Create(AHandle: TSysHandle);
    function HasPendingEvents: Boolean; virtual;
    function GetEvent(var Ev: TEvent): Boolean; virtual;
    property Handle: TSysHandle read FHandle;
  end;

  { Called when the wake-up is taken; it returns whether Ev holds an event. }
  TWakeUpCallback = function(Args: Pointer; var Ev: TEvent): Boolean;

  TWakeUpEventSource = class(TEventSource)
  private
    FSys: TSysManualEvent;
    FCallback: TWakeUpCallback;
    FCallbackArgs: Pointer;
    FSignaled: LongInt;
    function Clear: Boolean;
  public
    { Pre: if ACallback or ACallbackArgs are set, they outlive Self. }
    constructor Create(const AHandle: TSysManualEventHandle; ACallback: TWakeUpCallback;
      ACallbackArgs: Pointer);
    destructor Destroy; override;
    { Any thread. }
    procedure Signal;
    { The thread that waits only. }
    function GetEvent(var Ev: TEvent): Boolean; override;
  end;

  TPollState = (psNothing, psReady, psDisconnect);

  TPollData = record
    Handles: array of TSysHandle;
    States: array of TPollState;
    procedure Push(H: TSysHandle);
    procedure Erase(I: SizeInt);
    function Size: SizeInt;
  end;

  TEventSourceArray = array of TEventSource;

  TEventWaiter = class
  private
    FSources: TEventSourceArray;
    FPD: TPollData;
    FWakeUp: TWakeUpEventSource;
    FReadyEvent: TEvent;
    FReadyEventPresent: Boolean;
    procedure RemoveSourceAt(I: SizeInt);
    procedure PollSources(TimeoutMs: Integer);
    function HasReadyEvent: Boolean;
    procedure GetReadyEvent(var Ev: TEvent);
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddSource(Src: TEventSource);
    procedure RemoveSource(Src: TEventSource);
    function GetEvent(var Ev: TEvent): Boolean;
    { Returns on a ready event or after Ms milliseconds; a negative Ms waits without limit. }
    procedure WaitForEvents(Ms: Integer);
    { Any thread. }
    procedure InterruptEventWait;
  end;

  { A first-in first-out list of events. }
  TEventFifo = class
  private
    FItems: array of TEvent;
    FHead: SizeInt;
    FCount: SizeInt;
  public
    procedure Push(const Ev: TEvent);
    function Pop(var Ev: TEvent): Boolean;
    procedure Clear;
    property Count: SizeInt read FCount;
  end;

  { The input hardware and the wait for it, as TEventQueue uses them. The base class takes its input from
    Feed and waits on a TEventWaiter; a backend for a real terminal overrides what it needs. }
  TEventBackend = class
  private
    FWaiter: TEventWaiter;
    FLock: TRTLCriticalSection;
    FKeys: TEventFifo;
    FMice: TEventFifo;
    FMouseState: TMouseEventType;
    FWidth: Integer;
    FHeight: Integer;
    procedure Accept(const Ev: TEvent);
    function HasInput: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function MousePresent: Boolean; virtual;
    procedure MouseResume; virtual;
    procedure MouseSuspend; virtual;
    procedure MouseSetRange(MaxX, MaxY: Integer); virtual;
    { THardwareInfo::getButtonCount: the number of buttons of the mouse; 0 in the base class. }
    function GetButtonCount: Cardinal; virtual;
    { THardwareInfo::cursorOn and cursorOff: the base class does nothing. }
    procedure CursorOn; virtual;
    procedure CursorOff; virtual;
    { The state of the mouse now. }
    procedure MouseGetState(var Mouse: TMouseEventType); virtual;
    procedure ClearPendingEvent; virtual;
    { Returns the next change of the mouse state, False when there is none. }
    function GetMouseEvent(var Mouse: TMouseEventType): Boolean; virtual;
    function GetKeyEvent(var Ev: TEvent): Boolean; virtual;
    { Ticks of 1/18.2 s. }
    function GetTickCount: Cardinal; virtual;
    function ScreenWidth: Integer; virtual;
    function ScreenHeight: Integer; virtual;
    procedure WaitForEvents(TimeoutMs: Integer); virtual;
    { Any thread. }
    procedure InterruptEventWait; virtual;
    { Adds a key event (What in evKeyboard) or a mouse event (What in evMouse) to the input and wakes the wait.
      Any thread. }
    procedure Feed(const Ev: TEvent);
    procedure SetScreenSize(AWidth, AHeight: Integer);
    property Waiter: TEventWaiter read FWaiter;
  end;

  TEventQueue = class
  private
    class var LastMouse: TMouseEventType;
    class var CurMouse: TMouseEventType;
    class var DownMouse: TMouseEventType;
    class var DownTicks: Word;
    class var MouseEvents: Boolean;
    class var PendingMouseUp: Boolean;
    class var RepeatDelay: Word;
    class var AutoTicks: Word;
    class var AutoDelay: Word;
    class var PasteText: string;
    class var PasteActive: Boolean;
    class var PasteTextIndex: SizeInt;
    class var ShouldSkipLf: Boolean;
    class function GetMouseState(var Ev: TEvent): Boolean; static;
    class function GetPasteEvent(var Ev: TEvent): Boolean; static;
    class procedure GetKeyOrPasteEvent(var Ev: TEvent); static;
    class function ReadKeyPress(var Ev: TEvent): Boolean; static;
  public
    class var DoubleDelay: Word;
    class var MouseReverse: Boolean;
    { The input hardware. The program sets it before the first queue is created. }
    class var Backend: TEventBackend;
    constructor Create;
    destructor Destroy; override;
    class procedure GetMouseEvent(var Ev: TEvent); static;
    class procedure GetKeyEvent(var Ev: TEvent); static;
    class procedure Suspend; static;
    class procedure Resume; static;
    { Returns on input, on WakeUp, on a posted event, or after TimeoutMs milliseconds. }
    class procedure WaitForEvents(TimeoutMs: Integer); static;
    { Thread-safe: ends the wait of WaitForEvents, the one now running or the next one. }
    class procedure WakeUp; static;
    class procedure SetPasteText(const Text: string); static;
    { Thread-safe: adds Ev to the posted events and wakes the wait. }
    class procedure PostEvent(const Ev: TEvent); static;
    { The thread of the views only: takes the oldest posted event. }
    class function GetPostedEvent(var Ev: TEvent): Boolean; static;
    { Thread-safe. }
    class function HasPostedEvents: Boolean; static;
  end;

implementation

uses
  SysUtils, TvGeom, TvKeys, TvUtf8;

var
  { The events of PostEvent, from any thread, read by the thread of the views. }
  PostLock: TRTLCriticalSection;
  Posted: TEventFifo;
  DefaultBackend: TEventBackend;

function NowMs: Int64;
begin
  Result := Int64(GetTickCount64);
end;

{ TSysManualEvent }

class function TSysManualEvent.CreateHandle(var Handle: TSysManualEventHandle): Boolean;
begin
  Result := FpPipe(Handle) <> -1;
end;

class function TSysManualEvent.GetWaitableHandle(const Handle: TSysManualEventHandle): TSysHandle;
begin
  Result := Handle[0];
end;

destructor TSysManualEvent.Destroy;
begin
  FpClose(FHandle[0]);
  FpClose(FHandle[1]);
  inherited Destroy;
end;

procedure TSysManualEvent.Signal;
var
  C: Byte;
begin
  C := 0;
  while FpWrite(FHandle[1], @C, 1) = 0 do
    ;
end;

procedure TSysManualEvent.Clear;
var
  C: Byte;
begin
  while FpRead(FHandle[0], C, 1) = 0 do
    ;
end;

constructor TSysManualEvent.Create(const AHandle: TSysManualEventHandle);
begin
  inherited Create;
  FHandle := AHandle;
end;

{ TEventSource }

constructor TEventSource.Create(AHandle: TSysHandle);
begin
  inherited Create;
  FHandle := AHandle;
end;

function TEventSource.HasPendingEvents: Boolean;
begin
  Result := False;
end;

function TEventSource.GetEvent(var Ev: TEvent): Boolean;
begin
  Result := False;
end;

{ TWakeUpEventSource }

constructor TWakeUpEventSource.Create(const AHandle: TSysManualEventHandle; ACallback: TWakeUpCallback;
  ACallbackArgs: Pointer);
begin
  inherited Create(TSysManualEvent.GetWaitableHandle(AHandle));
  FSys := TSysManualEvent.Create(AHandle);
  FCallback := ACallback;
  FCallbackArgs := ACallbackArgs;
  FSignaled := 0;
end;

destructor TWakeUpEventSource.Destroy;
begin
  FSys.Free;
  inherited Destroy;
end;

procedure TWakeUpEventSource.Signal;
begin
  if InterlockedExchange(FSignaled, 1) = 0 then
    FSys.Signal;
end;

function TWakeUpEventSource.Clear: Boolean;
begin
  Result := InterlockedCompareExchange(FSignaled, 0, 0) <> 0;
  if Result then
  begin
    FSys.Clear;
    InterlockedExchange(FSignaled, 0);
  end;
end;

function TWakeUpEventSource.GetEvent(var Ev: TEvent): Boolean;
begin
  Result := Clear;
  if Result then
  begin
    if Assigned(FCallback) then
      Result := FCallback(FCallbackArgs, Ev)
    else
      Ev.What := evNothing;
  end;
end;

{ TPollData }

procedure TPollData.Push(H: TSysHandle);
begin
  SetLength(Handles, Length(Handles) + 1);
  Handles[High(Handles)] := H;
  SetLength(States, Length(States) + 1);
  States[High(States)] := psNothing;
end;

procedure TPollData.Erase(I: SizeInt);
begin
  Delete(Handles, I, 1);
  Delete(States, I, 1);
end;

function TPollData.Size: SizeInt;
begin
  Result := Length(Handles);
end;

{ Waits until a handle is ready or Ms milliseconds pass (without limit when Ms is negative) and marks the
  handles that are ready, or have been closed, in PD.States. }
procedure PollHandles(var PD: TPollData; Ms: Integer);
var
  Fds: array of TPollFD;
  I: SizeInt;
  Flags: SmallInt;
begin
  if PD.Size = 0 then
  begin
    FpPoll(nil, 0, Ms);
    Exit;
  end;
  SetLength(Fds, PD.Size);
  for I := 0 to PD.Size - 1 do
  begin
    Fds[I].fd := PD.Handles[I];
    Fds[I].events := POLLIN;
    Fds[I].revents := 0;
  end;
  if FpPoll(@Fds[0], PD.Size, Ms) >= 0 then
    for I := 0 to PD.Size - 1 do
    begin
      Flags := Fds[I].revents;
      if (Flags and POLLIN) <> 0 then
        PD.States[I] := psReady
      else if (Flags and (POLLHUP or POLLERR or POLLNVAL)) <> 0 then
        PD.States[I] := psDisconnect;
    end;
end;

{ TEventWaiter }

constructor TEventWaiter.Create;
var
  H: TSysManualEventHandle;
begin
  inherited Create;
  FillChar(FReadyEvent, SizeOf(FReadyEvent), 0);
  FReadyEventPresent := False;
  if TSysManualEvent.CreateHandle(H) then
  begin
    FWakeUp := TWakeUpEventSource.Create(H, nil, nil);
    AddSource(FWakeUp);
  end;
end;

destructor TEventWaiter.Destroy;
begin
  FWakeUp.Free;
  inherited Destroy;
end;

procedure TEventWaiter.AddSource(Src: TEventSource);
begin
  SetLength(FSources, Length(FSources) + 1);
  FSources[High(FSources)] := Src;
  FPD.Push(Src.Handle);
end;

procedure TEventWaiter.RemoveSource(Src: TEventSource);
var
  I: SizeInt;
begin
  for I := 0 to High(FSources) do
    if FSources[I] = Src then
    begin
      RemoveSourceAt(I);
      Break;
    end;
end;

procedure TEventWaiter.RemoveSourceAt(I: SizeInt);
begin
  Delete(FSources, I, 1);
  FPD.Erase(I);
end;

procedure TEventWaiter.PollSources(TimeoutMs: Integer);
var
  HasEvents: Boolean;
  I: SizeInt;
begin
  HasEvents := False;
  for I := 0 to FPD.Size - 1 do
    if FSources[I].HasPendingEvents then
    begin
      FPD.States[I] := psReady;
      HasEvents := True;
    end
    else
      FPD.States[I] := psNothing;
  if not HasEvents then
  begin
    PollHandles(FPD, TimeoutMs);
    I := 0;
    while I < FPD.Size do
      if FPD.States[I] = psDisconnect then
        RemoveSourceAt(I)
      else
        Inc(I);
  end;
end;

function TEventWaiter.HasReadyEvent: Boolean;
var
  I: SizeInt;
begin
  if not FReadyEventPresent then
    for I := 0 to FPD.Size - 1 do
      if FPD.States[I] = psReady then
      begin
        FPD.States[I] := psNothing;
        FillChar(FReadyEvent, SizeOf(FReadyEvent), 0);
        if FSources[I].GetEvent(FReadyEvent) then
        begin
          FReadyEventPresent := True;
          Break;
        end;
      end;
  Result := FReadyEventPresent;
end;

procedure TEventWaiter.GetReadyEvent(var Ev: TEvent);
begin
  Ev := FReadyEvent;
  FReadyEventPresent := False;
end;

function TEventWaiter.GetEvent(var Ev: TEvent): Boolean;
begin
  Result := HasReadyEvent;
  if not Result then
  begin
    PollSources(0);
    Result := HasReadyEvent;
  end;
  if Result then
    GetReadyEvent(Ev);
end;

{ The milliseconds from Now to Stop, never negative. }
function PollDelayMs(Now, Stop: Int64): Integer;
begin
  if Stop <= Now then
    Result := 0
  else if Stop - Now > High(Integer) then
    Result := High(Integer)
  else
    Result := Integer(Stop - Now);
end;

procedure TEventWaiter.WaitForEvents(Ms: Integer);
var
  Now, Stop: Int64;
begin
  Now := NowMs;
  if Ms < 0 then
    Stop := High(Int64)
  else
    Stop := Now + Ms;
  while (not HasReadyEvent) and (Now <= Stop) do
  begin
    if Ms < 0 then
      PollSources(-1)
    else
      PollSources(PollDelayMs(Now, Stop));
    Now := NowMs;
  end;
end;

procedure TEventWaiter.InterruptEventWait;
begin
  if FWakeUp <> nil then
    FWakeUp.Signal;
end;

{ TEventFifo }

procedure TEventFifo.Push(const Ev: TEvent);
var
  Grown: array of TEvent;
  I: SizeInt;
begin
  if FCount = Length(FItems) then
  begin
    SetLength(Grown, 2 * Length(FItems) + 8);
    for I := 0 to FCount - 1 do
      Grown[I] := FItems[(FHead + I) mod Length(FItems)];
    FItems := Grown;
    FHead := 0;
  end;
  FItems[(FHead + FCount) mod Length(FItems)] := Ev;
  Inc(FCount);
end;

function TEventFifo.Pop(var Ev: TEvent): Boolean;
begin
  Result := FCount > 0;
  if Result then
  begin
    Ev := FItems[FHead];
    FHead := (FHead + 1) mod Length(FItems);
    Dec(FCount);
  end;
end;

procedure TEventFifo.Clear;
begin
  FHead := 0;
  FCount := 0;
end;

{ TEventBackend }

constructor TEventBackend.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FWaiter := TEventWaiter.Create;
  FKeys := TEventFifo.Create;
  FMice := TEventFifo.Create;
  FillChar(FMouseState, SizeOf(FMouseState), 0);
  FWidth := 80;
  FHeight := 25;
end;

destructor TEventBackend.Destroy;
begin
  FMice.Free;
  FKeys.Free;
  FWaiter.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TEventBackend.Accept(const Ev: TEvent);
begin
  EnterCriticalSection(FLock);
  try
    if (Ev.What and evKeyboard) <> 0 then
      FKeys.Push(Ev)
    else if (Ev.What and evMouse) <> 0 then
      FMice.Push(Ev);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TEventBackend.HasInput: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := (FKeys.Count > 0) or (FMice.Count > 0);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TEventBackend.MousePresent: Boolean;
begin
  Result := True;
end;

procedure TEventBackend.MouseResume;
begin
end;

procedure TEventBackend.MouseSuspend;
begin
end;

procedure TEventBackend.MouseSetRange(MaxX, MaxY: Integer);
begin
end;

function TEventBackend.GetButtonCount: Cardinal;
begin
  Result := 0;
end;

procedure TEventBackend.CursorOn;
begin
end;

procedure TEventBackend.CursorOff;
begin
end;

procedure TEventBackend.MouseGetState(var Mouse: TMouseEventType);
begin
  EnterCriticalSection(FLock);
  try
    Mouse := FMouseState;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TEventBackend.ClearPendingEvent;
begin
  EnterCriticalSection(FLock);
  try
    FMice.Clear;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TEventBackend.GetMouseEvent(var Mouse: TMouseEventType): Boolean;
var
  Ev: TEvent;
begin
  EnterCriticalSection(FLock);
  try
    Result := FMice.Pop(Ev);
    if Result then
    begin
      FMouseState := Ev.Mouse;
      Mouse := Ev.Mouse;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TEventBackend.GetKeyEvent(var Ev: TEvent): Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FKeys.Pop(Ev);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TEventBackend.GetTickCount: Cardinal;
begin
  Result := Cardinal((NowMs * 182) div 10000);
end;

function TEventBackend.ScreenWidth: Integer;
begin
  Result := FWidth;
end;

function TEventBackend.ScreenHeight: Integer;
begin
  Result := FHeight;
end;

procedure TEventBackend.WaitForEvents(TimeoutMs: Integer);
var
  Ev: TEvent;
begin
  if HasInput then
    Exit;
  FWaiter.WaitForEvents(TimeoutMs);
  while FWaiter.GetEvent(Ev) do
    Accept(Ev);
end;

procedure TEventBackend.InterruptEventWait;
begin
  FWaiter.InterruptEventWait;
end;

procedure TEventBackend.Feed(const Ev: TEvent);
begin
  Accept(Ev);
  InterruptEventWait;
end;

procedure TEventBackend.SetScreenSize(AWidth, AHeight: Integer);
begin
  FWidth := AWidth;
  FHeight := AHeight;
end;

{ TEventQueue }

constructor TEventQueue.Create;
begin
  inherited Create;
  Resume;
end;

class procedure TEventQueue.Resume;
begin
  if not Backend.MousePresent then
    Backend.MouseResume;
  if not Backend.MousePresent then
    Exit;
  Backend.MouseGetState(CurMouse);
  LastMouse := CurMouse;
  Backend.ClearPendingEvent;
  MouseEvents := True;
  Backend.MouseSetRange(Backend.ScreenWidth - 1, Backend.ScreenHeight - 1);
end;

class procedure TEventQueue.Suspend;
begin
  Backend.MouseSuspend;
end;

destructor TEventQueue.Destroy;
begin
  Suspend;
  PasteText := '';
  PasteActive := False;
  inherited Destroy;
end;

class procedure TEventQueue.GetMouseEvent(var Ev: TEvent);
var
  Up: TMouseEventType;
  Where: TPoint;
  Buttons: Byte;
begin
  if MouseEvents then
  begin
    if PendingMouseUp then
    begin
      Ev.What := evMouseUp;
      Ev.Mouse := LastMouse;
      LastMouse.Buttons := 0;
      PendingMouseUp := False;
      Exit;
    end;
    if not GetMouseState(Ev) then
      Exit;

    Ev.Mouse.EventFlags := 0;

    if (Ev.Mouse.Buttons = 0) and (LastMouse.Buttons <> 0) then
    begin
      if Ev.Mouse.Where = LastMouse.Where then
      begin
        Ev.What := evMouseUp;
        Buttons := LastMouse.Buttons;
        LastMouse := Ev.Mouse;
        Ev.Mouse.Buttons := Buttons;
      end
      else
      begin
        Ev.What := evMouseMove;
        Up := Ev.Mouse;
        Where := Up.Where;
        Ev.Mouse := LastMouse;
        Ev.Mouse.Where := Where;
        Ev.Mouse.EventFlags := Ev.Mouse.EventFlags or meMouseMoved;
        Up.Buttons := LastMouse.Buttons;
        LastMouse := Up;
        PendingMouseUp := True;
      end;
      Exit;
    end;

    if (Ev.Mouse.Buttons <> 0) and (LastMouse.Buttons = 0) then
    begin
      if (Ev.Mouse.Buttons = DownMouse.Buttons) and (Ev.Mouse.Where = DownMouse.Where) and
         (Integer(Ev.What) - Integer(DownTicks) <= Integer(DoubleDelay)) then
      begin
        if (DownMouse.EventFlags and (meDoubleClick or meTripleClick)) = 0 then
          Ev.Mouse.EventFlags := Ev.Mouse.EventFlags or meDoubleClick
        else if (DownMouse.EventFlags and meDoubleClick) <> 0 then
        begin
          Ev.Mouse.EventFlags := Ev.Mouse.EventFlags and not Word(meDoubleClick);
          Ev.Mouse.EventFlags := Ev.Mouse.EventFlags or meTripleClick;
        end;
      end;

      DownMouse := Ev.Mouse;
      DownTicks := Ev.What;
      AutoTicks := DownTicks;
      AutoDelay := RepeatDelay;
      Ev.What := evMouseDown;
      LastMouse := Ev.Mouse;
      Exit;
    end;

    Ev.Mouse.Buttons := LastMouse.Buttons;

    if Ev.Mouse.Wheel <> 0 then
    begin
      Ev.What := evMouseWheel;
      LastMouse := Ev.Mouse;
      Exit;
    end;

    if Ev.Mouse.Where <> LastMouse.Where then
    begin
      Ev.What := evMouseMove;
      Ev.Mouse.EventFlags := Ev.Mouse.EventFlags or meMouseMoved;
      LastMouse := Ev.Mouse;
      Exit;
    end;

    if (Ev.Mouse.Buttons <> 0) and (Integer(Ev.What) - Integer(AutoTicks) > Integer(AutoDelay)) then
    begin
      AutoTicks := Ev.What;
      AutoDelay := 1;
      Ev.What := evMouseAuto;
      LastMouse := Ev.Mouse;
      Exit;
    end;
  end;

  Ev.What := evNothing;
end;

class function TEventQueue.GetMouseState(var Ev: TEvent): Boolean;
begin
  Ev.What := evNothing;

  if not Backend.GetMouseEvent(CurMouse) then
    Exit(False);

  if MouseReverse and (CurMouse.Buttons <> 0) and (CurMouse.Buttons <> 3) then
    CurMouse.Buttons := CurMouse.Buttons xor 3;

  { The tick count when the event was read is kept in What for now. }
  Ev.What := Word(Backend.GetTickCount);
  Ev.Mouse := CurMouse;
  Result := True;
end;

class procedure TEventQueue.GetKeyEvent(var Ev: TEvent);
begin
  GetKeyOrPasteEvent(Ev);

  if ShouldSkipLf then
  begin
    ShouldSkipLf := False;
    { Skip a LF, since a CR was read before. }
    if (Ev.What = evKeyDown) and ((Ev.KeyDown.ControlKeyState and kbPaste) <> 0) and
       (((Ev.KeyDown.TextLength = 0) and (Ev.KeyDown.CharScan.CharCode = 10)) or
        ((Ev.KeyDown.TextLength = 1) and (Ev.KeyDown.Text[0] = 10))) then
      GetKeyOrPasteEvent(Ev);
  end;

  if (Ev.What = evKeyDown) and ((Ev.KeyDown.ControlKeyState and kbPaste) <> 0) then
  begin
    if Ev.KeyDown.TextLength = 0 then
    begin
      Ev.KeyDown.Text[0] := Ev.KeyDown.CharScan.CharCode;
      Ev.KeyDown.TextLength := 1;
    end;
    { Convert CR and CRLF into LF. }
    if Ev.KeyDown.Text[0] = 13 then
    begin
      Ev.KeyDown.Text[0] := 10;
      ShouldSkipLf := True;
    end;
    Ev.KeyDown.KeyCode := 0;
  end;
end;

class procedure TEventQueue.SetPasteText(const Text: string);
begin
  { The paste event is set even when the text is empty, so that WaitForEvents does not block in the
    next call. }
  PasteText := Text;
  PasteActive := True;
  PasteTextIndex := 0;
end;

class function TEventQueue.GetPasteEvent(var Ev: TEvent): Boolean;
var
  Next, Len, I: SizeInt;
begin
  Result := False;
  if PasteActive then
  begin
    Next := PasteTextIndex;
    if TText.Next(PasteText, Next) then
    begin
      Len := Next - PasteTextIndex;
      Ev.What := evKeyDown;
      FillChar(Ev.KeyDown, SizeOf(Ev.KeyDown), 0);
      Ev.KeyDown.ControlKeyState := kbPaste;
      Ev.KeyDown.TextLength := Len;
      for I := 0 to Len - 1 do
        Ev.KeyDown.Text[I] := Byte(PasteText[PasteTextIndex + 1 + I]);
      PasteTextIndex := Next;
      Exit(True);
    end;
    PasteText := '';
    PasteActive := False;
  end;
end;

class procedure TEventQueue.GetKeyOrPasteEvent(var Ev: TEvent);
begin
  if GetPasteEvent(Ev) then
    Exit;
  if not ReadKeyPress(Ev) then
    Ev.What := evNothing;
end;

class function TEventQueue.ReadKeyPress(var Ev: TEvent): Boolean;
begin
  if not Backend.GetKeyEvent(Ev) then
    Ev.What := evNothing;
  Result := Ev.What <> evNothing;
end;

class procedure TEventQueue.WaitForEvents(TimeoutMs: Integer);
begin
  if (not PasteActive) and (not HasPostedEvents) then
    Backend.WaitForEvents(TimeoutMs);
end;

class procedure TEventQueue.WakeUp;
begin
  Backend.InterruptEventWait;
end;

class procedure TEventQueue.PostEvent(const Ev: TEvent);
begin
  EnterCriticalSection(PostLock);
  try
    Posted.Push(Ev);
  finally
    LeaveCriticalSection(PostLock);
  end;
  WakeUp;
end;

class function TEventQueue.GetPostedEvent(var Ev: TEvent): Boolean;
begin
  EnterCriticalSection(PostLock);
  try
    Result := Posted.Pop(Ev);
  finally
    LeaveCriticalSection(PostLock);
  end;
end;

class function TEventQueue.HasPostedEvents: Boolean;
begin
  EnterCriticalSection(PostLock);
  try
    Result := Posted.Count > 0;
  finally
    LeaveCriticalSection(PostLock);
  end;
end;

initialization
  InitCriticalSection(PostLock);
  Posted := TEventFifo.Create;
  DefaultBackend := TEventBackend.Create;
  TEventQueue.Backend := DefaultBackend;
  TEventQueue.DoubleDelay := 8;
  TEventQueue.RepeatDelay := 8;

finalization
  if TEventQueue.Backend = DefaultBackend then
    TEventQueue.Backend := nil;
  DefaultBackend.Free;
  Posted.Free;
  DoneCriticalSection(PostLock);

end.
