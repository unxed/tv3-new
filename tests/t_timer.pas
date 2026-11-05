{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (TTimerQueue), source/tvision/ttimerqu.cpp,
  include/tvision/hardware.h (getTickCountMs), source/platform/hardware.cpp (getTickCountMs)
  See COPYRIGHT.magiblot. }
program t_timer;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  cthreads,
  Classes, SysUtils, TvSys, TvTimer;

{$I testlib.inc}

const
  { No wait of these tests lasts longer than this, so that a failure ends the program. }
  Guard = 10000;
  { What counts as at once, in milliseconds. }
  Quick = 2000;
  MaxLogged = 16;

type
  { What the callback does besides noting the call. }
  TNoteMode = (nmPlain, nmKillOther, nmSetNow, nmSetLater);

  TLog = record
    Count: Integer;
    Ids: array[0..MaxLogged - 1] of TTimerId;
    Mode: TNoteMode;
    Queue: TTimerQueue;
    Other: TTimerId;
    ThreadId: TThreadID;
  end;
  PLog = ^TLog;

  TWorkKind = (wkSet, wkKill, wkMany);

  { Sets or kills timers of a queue from its own thread, after Delay milliseconds. }
  TWorker = class(TThread)
  private
    FKind: TWorkKind;
    FQueue: TTimerQueue;
    FDelay: Integer;
    FTarget: TTimerId;
  protected
    procedure Execute; override;
  public
    Made: TTimerId;
    constructor Create(AKind: TWorkKind; AQueue: TTimerQueue; ADelay: Integer; ATarget: TTimerId);
  end;

var
  Clock: TTimePoint;
  ClockCalls: Integer;
  DoneCount: LongInt;

function FakeClock: TTimePoint;
begin
  Inc(ClockCalls);
  Result := Clock;
end;

function ZeroClock: TTimePoint;
begin
  Result := 0;
end;

function Now64: Int64;
begin
  Result := Int64(GetTickCount64);
end;

procedure Note(Id: TTimerId; Args: Pointer);
var
  Log: PLog;
begin
  Log := PLog(Args);
  if Log^.Count < MaxLogged then
    Log^.Ids[Log^.Count] := Id;
  Inc(Log^.Count);
  Log^.ThreadId := GetCurrentThreadId;
  case Log^.Mode of
    nmKillOther:
      if Log^.Count = 1 then
        Log^.Queue.KillTimer(Log^.Other);
    nmSetNow:
      if Log^.Count = 1 then
        Log^.Other := Log^.Queue.SetTimer(0);
    nmSetLater:
      if Log^.Count = 1 then
        Log^.Other := Log^.Queue.SetTimer(10);
  end;
end;

procedure ResetLog(var Log: TLog; AMode: TNoteMode; AQueue: TTimerQueue);
begin
  FillChar(Log, SizeOf(Log), 0);
  Log.Mode := AMode;
  Log.Queue := AQueue;
end;

constructor TWorker.Create(AKind: TWorkKind; AQueue: TTimerQueue; ADelay: Integer; ATarget: TTimerId);
begin
  FKind := AKind;
  FQueue := AQueue;
  FDelay := ADelay;
  FTarget := ATarget;
  inherited Create(False);
end;

procedure TWorker.Execute;
var
  I: Integer;
  Id: TTimerId;
begin
  if FDelay > 0 then
    Sleep(FDelay);
  case FKind of
    wkSet:
      Made := FQueue.SetTimer(1);
    wkKill:
      FQueue.KillTimer(FTarget);
    wkMany:
      begin
        for I := 1 to 100 do
        begin
          Id := FQueue.SetTimer(0);
          if I mod 2 = 0 then
            FQueue.KillTimer(Id);
        end;
        InterlockedIncrement(DoneCount);
      end;
  end;
end;

var
  B: TEventBackend;
  EQ: TEventQueue;
  Tm: TTimerQueue;
  Log: TLog;
  Dummy: Integer;
  A1, A2, A3: TTimerId;
  Start: Int64;
  T: TWorker;
  Workers: array[0..3] of TWorker;
  MainThread: TThreadID;
  I: Integer;
  Prev, Cur: LongInt;
  Monotonic: Boolean;

begin
  B := TEventBackend.Create;
  TEventQueue.Backend := B;
  EQ := TEventQueue.Create;
  MainThread := GetCurrentThreadId;

  Tm := TTimerQueue.Create(@FakeClock);

  { an empty queue }
  ClockCalls := 0;
  ResetLog(Log, nmPlain, Tm);
  Check(Tm.TimeUntilNextTimeout = -1, 'an empty queue has no time-out');
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 0, 'an empty queue collects nothing');
  Check(ClockCalls = 0, 'an empty queue does not read the clock');

  { a one-shot timer }
  Clock := 1000;
  ResetLog(Log, nmPlain, Tm);
  A1 := Tm.SetTimer(100);
  Check(A1 <> nil, 'SetTimer returns an id');
  Check(Tm.TimeUntilNextTimeout = 100, 'time until a new timer');
  Clock := 1060;
  Check(Tm.TimeUntilNextTimeout = 40, 'time until the timer after 60 ms');
  Clock := 1099;
  Check(Tm.TimeUntilNextTimeout = 1, 'time until the timer one ms before');
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 0, 'a timer is not collected before it expires');
  Clock := 1100;
  Check(Tm.TimeUntilNextTimeout = 0, 'time until an expired timer is 0');
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 1) and (Log.Ids[0] = A1), 'an expired timer is collected with its id');
  Check(Tm.TimeUntilNextTimeout = -1, 'a one-shot timer is gone once collected');
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 1, 'a one-shot timer is collected once');

  { a periodic timer }
  Clock := 0;
  ResetLog(Log, nmPlain, Tm);
  A1 := Tm.SetTimer(100, 50);
  Clock := 100;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 1) and (Log.Ids[0] = A1), 'a periodic timer is collected');
  Check(Tm.TimeUntilNextTimeout = 50, 'the next expiry is one period later');
  Clock := 149;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 1, 'a periodic timer waits for its period');
  Clock := 150;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 2, 'a periodic timer is collected again after its period');
  Clock := 400;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 3, 'a periodic timer that missed periods is collected once');
  Check(Tm.TimeUntilNextTimeout = 50, 'the missed periods are skipped');
  Tm.KillTimer(A1);
  Check(Tm.TimeUntilNextTimeout = -1, 'a killed periodic timer is gone');

  { a period of 0 }
  Clock := 0;
  ResetLog(Log, nmPlain, Tm);
  A1 := Tm.SetTimer(10, 0);
  Clock := 10;
  Tm.CollectExpiredTimers(@Note, @Log);
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 2, 'a timer of period 0 is collected by every call');
  Check(Tm.TimeUntilNextTimeout = 0, 'a timer of period 0 stays expired');
  Tm.KillTimer(A1);

  { a periodic timer is collected once per call, even when it is expired again at once }
  Clock := 0;
  ResetLog(Log, nmPlain, Tm);
  A1 := Tm.SetTimer(0, 5);
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 1, 'a periodic timer is collected once in a call');
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 1, 'and is not due again in the same instant');
  Clock := 5;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 2, 'and is collected by the call of the next period');
  Tm.KillTimer(A1);

  { the order of the callbacks is the order in which the timers were set }
  Clock := 0;
  ResetLog(Log, nmPlain, Tm);
  A1 := Tm.SetTimer(30);
  A2 := Tm.SetTimer(10);
  A3 := Tm.SetTimer(20);
  Check(Tm.TimeUntilNextTimeout = 10, 'the time-out is the nearest of all timers');
  Clock := 100;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 3) and (Log.Ids[0] = A1) and (Log.Ids[1] = A2) and (Log.Ids[2] = A3),
    'expired timers are collected in the order they were set');
  Clock := 0;
  ResetLog(Log, nmPlain, Tm);
  A1 := Tm.SetTimer(5, 10);
  A2 := Tm.SetTimer(5);
  Clock := 5;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 2) and (Log.Ids[0] = A1) and (Log.Ids[1] = A2), 'periodic and one-shot timers in order');
  Check(Tm.TimeUntilNextTimeout = 10, 'only the periodic timer is left');
  Tm.KillTimer(A1);

  { killing }
  Clock := 0;
  ResetLog(Log, nmPlain, Tm);
  A1 := Tm.SetTimer(10);
  A2 := Tm.SetTimer(20);
  Tm.KillTimer(A1);
  Check(Tm.TimeUntilNextTimeout = 20, 'a killed timer does not count');
  Clock := 50;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 1) and (Log.Ids[0] = A2), 'a killed timer is not collected');
  Clock := 0;
  A3 := Tm.SetTimer(100);
  Tm.KillTimer(@Dummy);
  Check(Tm.TimeUntilNextTimeout = 100, 'killing an id that is not in the queue changes nothing');
  Tm.KillTimer(A3);
  Check(Tm.TimeUntilNextTimeout = -1, 'the queue is empty after the last kill');

  { the callback changes the list }
  Clock := 0;
  ResetLog(Log, nmKillOther, Tm);
  A1 := Tm.SetTimer(0);
  A2 := Tm.SetTimer(0);
  A3 := Tm.SetTimer(0);
  Log.Other := A2;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 2) and (Log.Ids[0] = A1) and (Log.Ids[1] = A3), 'a timer killed by a callback is skipped');
  Check(Tm.TimeUntilNextTimeout = -1, 'nothing is left');
  ResetLog(Log, nmSetNow, Tm);
  A1 := Tm.SetTimer(0);
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 2) and (Log.Ids[0] = A1) and (Log.Ids[1] = Log.Other),
    'a timer set by a callback that is already expired is collected in the same call');
  ResetLog(Log, nmSetLater, Tm);
  A1 := Tm.SetTimer(0);
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 1, 'a timer set by a callback that is not expired waits');
  Check(Tm.TimeUntilNextTimeout = 10, 'and counts for the time-out');
  Tm.KillTimer(Log.Other);

  { limits of the time-out }
  Clock := 0;
  A1 := Tm.SetTimer($FFFFFFFF);
  Clock := 100;
  Check(Tm.TimeUntilNextTimeout = $7FFFFFFF, 'the time-out is at most the largest 32-bit integer');
  A2 := Tm.SetTimer(1000);
  Check(Tm.TimeUntilNextTimeout = 1000, 'the nearest timer decides');
  Tm.KillTimer(A1);
  Tm.KillTimer(A2);
  Clock := TTimePoint(1) shl 32;
  A1 := Tm.SetTimer(500);
  Clock := Clock + 200;
  Check(Tm.TimeUntilNextTimeout = 300, 'the clock is not limited to 32 bits');
  Tm.KillTimer(A1);
  { the time points are 64 bits wide: the sum of the clock and the time-out does not wrap at 2^32 }
  Clock := $FFFFFFFF;
  A1 := Tm.SetTimer(10);
  Check(Tm.TimeUntilNextTimeout = 10, 'a time point beyond 32 bits is 10 ms away');
  Clock := $FFFFFFFF + 9;
  Check(Tm.TimeUntilNextTimeout = 1, 'one ms before a time point beyond 32 bits');
  ResetLog(Log, nmPlain, Tm);
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 0, 'a timer is not collected before a time point beyond 32 bits');
  Clock := $FFFFFFFF + 10;
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 1) and (Log.Ids[0] = A1), 'a timer is collected at a time point beyond 32 bits');
  { a distance beyond 32 bits is cut to its low 32 bits, as uint32_t(expiresAt - now) is: the clock is set back }
  Clock := 1;
  A1 := Tm.SetTimer($FFFFFFFF);
  Clock := 0;
  Check(Tm.TimeUntilNextTimeout = 0, 'a distance of exactly 2^32 ms is cut to 0');
  Tm.KillTimer(A1);
  Clock := 6;
  A1 := Tm.SetTimer($FFFFFFFF);
  Clock := 0;
  Check(Tm.TimeUntilNextTimeout = 5, 'a distance of 2^32 + 5 ms is cut to 5');
  Tm.KillTimer(A1);
  Tm.Free;

  { the clock of the parameterless constructor: milliseconds of a steady clock }
  Tm := TTimerQueue.Create;
  A1 := Tm.SetTimer(60000);
  Check((Tm.TimeUntilNextTimeout > 59000) and (Tm.TimeUntilNextTimeout <= 60000), 'the default clock counts milliseconds');
  Prev := Tm.TimeUntilNextTimeout;
  Monotonic := True;
  for I := 1 to 5 do
  begin
    Sleep(50);
    Cur := Tm.TimeUntilNextTimeout;
    if (Cur > Prev) or (Prev - Cur < 49) then
      Monotonic := False;
    Prev := Cur;
  end;
  Check(Monotonic, 'the default clock never goes back and advances by the time that passed');
  Tm.KillTimer(A1);
  A1 := Tm.SetTimer(5000);
  Sleep(300);
  Check((Tm.TimeUntilNextTimeout > 0) and (Tm.TimeUntilNextTimeout <= 4701), 'the default clock advanced by about 300 ms');
  Tm.KillTimer(A1);
  ResetLog(Log, nmPlain, Tm);
  A1 := Tm.SetTimer(100);
  Tm.CollectExpiredTimers(@Note, @Log);
  Check(Log.Count = 0, 'a timer of the default clock is not due at once');
  Sleep(250);
  Check(Tm.TimeUntilNextTimeout = 0, 'a timer of the default clock is due after its time-out');
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 1) and (Log.Ids[0] = A1), 'a timer of the default clock is collected after its time-out');
  Tm.Free;

  { a queue that is freed with timers in it }
  Tm := TTimerQueue.Create(@FakeClock);
  Tm.SetTimer(1);
  Tm.SetTimer(2, 3);
  Tm.Free;

  { setting a timer wakes the wait, killing one does too }
  Tm := TTimerQueue.Create;
  TEventQueue.WaitForEvents(0);
  TEventQueue.WaitForEvents(0);
  Start := Now64;
  TEventQueue.WaitForEvents(150);
  Check(Now64 - Start >= 100, 'the wait blocks when nothing woke it');
  A1 := Tm.SetTimer(60000);
  Start := Now64;
  TEventQueue.WaitForEvents(Guard);
  Check(Now64 - Start < Quick, 'SetTimer ends the next wait');
  Start := Now64;
  TEventQueue.WaitForEvents(150);
  Check(Now64 - Start >= 100, 'SetTimer ends only one wait');
  Tm.KillTimer(A1);
  Start := Now64;
  TEventQueue.WaitForEvents(Guard);
  Check(Now64 - Start < Quick, 'KillTimer ends the next wait');
  TEventQueue.WaitForEvents(0);
  Tm.Free;

  { the wake-up does not depend on the clock of the queue }
  Tm := TTimerQueue.Create(@FakeClock);
  Clock := 0;
  TEventQueue.WaitForEvents(0);
  A1 := Tm.SetTimer(5);
  Start := Now64;
  TEventQueue.WaitForEvents(Guard);
  Check(Now64 - Start < Quick, 'SetTimer of a queue with its own clock ends the next wait');
  Tm.KillTimer(A1);
  TEventQueue.WaitForEvents(0);
  Tm.Free;
  Tm := TTimerQueue.Create;

  { a timer set from a second thread ends a blocked wait and fires on this thread }
  ResetLog(Log, nmPlain, Tm);
  T := TWorker.Create(wkSet, Tm, 250, nil);
  Start := Now64;
  TEventQueue.WaitForEvents(Guard);
  Check(Now64 - Start < Guard - 1000, 'a timer set by a second thread ends a blocked wait');
  Check(Now64 - Start >= 150, 'the wait was blocked until the timer was set');
  T.WaitFor;
  Sleep(10);
  Check(Tm.TimeUntilNextTimeout = 0, 'the timer of the second thread is expired');
  Tm.CollectExpiredTimers(@Note, @Log);
  Check((Log.Count = 1) and (Log.Ids[0] = T.Made), 'the timer of the second thread is collected');
  Check(Log.ThreadId = MainThread, 'and its callback runs on the thread that collects');
  T.Free;

  { a timer killed from a second thread ends a blocked wait }
  A1 := Tm.SetTimer(60000);
  TEventQueue.WaitForEvents(0);
  T := TWorker.Create(wkKill, Tm, 250, A1);
  Start := Now64;
  TEventQueue.WaitForEvents(Guard);
  Check(Now64 - Start < Guard - 1000, 'a timer killed by a second thread ends a blocked wait');
  Check(Now64 - Start >= 150, 'the wait was blocked until the timer was killed');
  T.WaitFor;
  T.Free;
  Check(Tm.TimeUntilNextTimeout = -1, 'the timer killed by a second thread is gone');

  { several threads set and kill timers at once }
  Tm.Free;
  Tm := TTimerQueue.Create(@ZeroClock);
  DoneCount := 0;
  for I := 0 to 3 do
    Workers[I] := TWorker.Create(wkMany, Tm, 0, nil);
  Start := Now64;
  while (DoneCount < 4) and (Now64 - Start < Guard) do
    Sleep(5);
  Check(DoneCount = 4, 'four threads set and kill timers within the guard time');
  if DoneCount = 4 then
  begin
    for I := 0 to 3 do
    begin
      Workers[I].WaitFor;
      Workers[I].Free;
    end;
    ResetLog(Log, nmPlain, Tm);
    Tm.CollectExpiredTimers(@Note, @Log);
    Check(Log.Count = 200, 'the timers that were not killed are all collected');
    Check(Tm.TimeUntilNextTimeout = -1, 'and no timer is left');
  end;
  Tm.Free;

  EQ.Free;
  TEventQueue.Backend := nil;
  B.Free;
  Done;
end.
