{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/buffers.h, source/tvision/new.cpp, source/tvision/misc.cpp
  See COPYRIGHT.magiblot.

  The tests work on the list of discardable buffers and on the safety pool. The list is read through FreeHead,
  which discards the newest buffer: a buffer that was discarded has its owner variable set to nil, and the order in
  which the owners become nil is the order of the list, the newest first. Every test leaves the list empty and the
  safety pool in place. }
program t_mem;

{$mode objfpc}
{$POINTERMATH ON}

uses
  TvMem;

{$I testlib.inc}

var
  A, B, C, P, Q: Pointer;

procedure Fill(Block: Pointer; Count: Integer; Value: Byte);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    PByte(Block)[I] := Value;
end;

function IsFilled(Block: Pointer; Count: Integer; Value: Byte): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to Count - 1 do
    if PByte(Block)[I] <> Value then
      Result := False;
end;

{ The bytes 1, 2, 3, ... (Count is at most 255). }
procedure FillRamp(Block: Pointer; Count: Integer);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    PByte(Block)[I] := Byte(I + 1);
end;

function IsRamp(Block: Pointer; Count: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to Count - 1 do
    if PByte(Block)[I] <> Byte(I + 1) then
      Result := False;
end;

procedure DiscardAll;
begin
  while TBufListEntry.FreeHead do
    ;
end;

procedure TestInitialState;
begin
  Check(DEFAULT_SAFETY_POOL_SIZE = 4096, 'the default size of the safety pool');
  Check(MemMgr <> nil, 'the manager object exists when the unit has started');
  Check(TVMemMgr.SafetyPoolExhausted = 0, 'the safety pool is made when the unit starts');
  Check(not LowMemory, 'the memory is not low while the safety pool exists');
  Check(not TBufListEntry.FreeHead, 'the list of discardable buffers is empty when the unit starts');
end;

procedure TestSafetyPool;
begin
  TVMemMgr.ClearSafetyPool;
  Check(TVMemMgr.SafetyPoolExhausted = 1, 'a cleared safety pool is exhausted');
  Check(LowMemory, 'the memory is low when the safety pool is exhausted');

  TVMemMgr.ResizeSafetyPool;
  Check(TVMemMgr.SafetyPoolExhausted = 0, 'the default resize makes the safety pool again');
  Check(not LowMemory, 'the memory is not low again');

  TVMemMgr.ResizeSafetyPool(0);
  Check((TVMemMgr.SafetyPoolExhausted = 1) and LowMemory, 'a resize to size 0 exhausts the safety pool');

  TVMemMgr.ResizeSafetyPool(64);
  Check((TVMemMgr.SafetyPoolExhausted = 0) and (not LowMemory), 'a resize to size 64 makes a safety pool');

  TVMemMgr.ResizeSafetyPool(5000);
  TVMemMgr.ResizeSafetyPool(10);
  Check(TVMemMgr.SafetyPoolExhausted = 0, 'a resize of an existing safety pool keeps it made');

  TVMemMgr.ResizeSafetyPool(0);
  TVMemMgr.ResizeSafetyPool(0);
  Check(TVMemMgr.SafetyPoolExhausted = 1, 'a second clearing keeps the safety pool exhausted');
  TVMemMgr.ResizeSafetyPool;
  Check(TVMemMgr.SafetyPoolExhausted = 0, 'the safety pool is back');
end;

procedure TestAllocate;
begin
  A := nil;
  TVMemMgr.AllocateDiscardable(A, 100);
  Check(A <> nil, 'a discardable buffer is allocated');
  Fill(A, 100, $5A);
  B := nil;
  TVMemMgr.AllocateDiscardable(B, 100);
  Check((B <> nil) and (B <> A), 'a second discardable buffer is another block');
  Fill(B, 100, $A5);
  Check(IsFilled(A, 100, $5A) and IsFilled(B, 100, $A5), 'the data of two buffers do not overlap');

  TVMemMgr.FreeDiscardable(A);
  Check(A = nil, 'freeing a buffer clears its owner');
  Check(B <> nil, 'the other buffer stays');
  TVMemMgr.FreeDiscardable(B);
  Check(B = nil, 'freeing the second buffer clears its owner');
  Check(not TBufListEntry.FreeHead, 'the list is empty after both buffers are freed');

  TVMemMgr.FreeDiscardable(nil);
  Check(not TBufListEntry.FreeHead, 'freeing a nil block does nothing');

  A := nil;
  TVMemMgr.AllocateDiscardable(A, 1);
  Check(A <> nil, 'a buffer of one byte');
  PByte(A)^ := 7;
  Check(PByte(A)^ = 7, 'the byte of the buffer');
  TVMemMgr.FreeDiscardable(A);

  A := nil;
  TVMemMgr.AllocateDiscardable(A, 0);
  Check(A <> nil, 'a buffer of size 0 is allocated, as the header needs memory');
  TVMemMgr.FreeDiscardable(A);
  Check(A = nil, 'the buffer of size 0 is freed');

  TVMemMgr.ClearSafetyPool;
  A := Pointer(1);
  TVMemMgr.AllocateDiscardable(A, 100);
  Check(A = nil, 'no buffer is allocated while the safety pool is exhausted');
  Check(not TBufListEntry.FreeHead, 'nothing was put in the list while the safety pool is exhausted');
  TVMemMgr.ResizeSafetyPool;
end;

procedure TestListOrder;
begin
  A := nil;
  B := nil;
  C := nil;
  TVMemMgr.AllocateDiscardable(A, 10);
  TVMemMgr.AllocateDiscardable(B, 20);
  TVMemMgr.AllocateDiscardable(C, 30);

  Check(TBufListEntry.FreeHead, 'FreeHead discards a buffer when the list has one');
  Check((C = nil) and (B <> nil) and (A <> nil), 'FreeHead discards the newest buffer');
  Check(TBufListEntry.FreeHead and (B = nil) and (A <> nil), 'FreeHead then discards the second newest');
  Check(TBufListEntry.FreeHead and (A = nil), 'FreeHead then discards the oldest');
  Check(not TBufListEntry.FreeHead, 'FreeHead tells that the list is empty');

  TVMemMgr.AllocateDiscardable(A, 10);
  TVMemMgr.AllocateDiscardable(B, 20);
  TVMemMgr.AllocateDiscardable(C, 30);
  TVMemMgr.FreeDiscardable(B);
  Check((B = nil) and (A <> nil) and (C <> nil), 'a buffer in the middle of the list is freed');
  Check(TBufListEntry.FreeHead and (C = nil) and (A <> nil), 'the list goes on with the newest buffer');
  Check(TBufListEntry.FreeHead and (A = nil), 'and then with the oldest');
  Check(not TBufListEntry.FreeHead, 'the list is empty after the middle one was freed');

  TVMemMgr.AllocateDiscardable(A, 10);
  TVMemMgr.AllocateDiscardable(B, 20);
  TVMemMgr.AllocateDiscardable(C, 30);
  TVMemMgr.FreeDiscardable(A);
  Check((A = nil) and (B <> nil) and (C <> nil), 'the oldest buffer of the list is freed');
  Check(TBufListEntry.FreeHead and (C = nil) and (B <> nil), 'the newest buffer is still the head');
  Check(TBufListEntry.FreeHead and (B = nil), 'the list ends with the second buffer');
  Check(not TBufListEntry.FreeHead, 'the list is empty after the oldest one was freed');

  TVMemMgr.AllocateDiscardable(A, 10);
  TVMemMgr.AllocateDiscardable(B, 20);
  TVMemMgr.AllocateDiscardable(C, 30);
  TVMemMgr.FreeDiscardable(C);
  Check((C = nil) and (A <> nil) and (B <> nil), 'the newest buffer is freed by FreeDiscardable');
  Check(TBufListEntry.FreeHead and (B = nil) and (A <> nil), 'the head is then the second buffer');
  DiscardAll;
  Check(A = nil, 'DiscardAll empties the list');
end;

procedure TestReallocate;
var
  X: Pointer;
begin
  { A buffer of nil is allocated. }
  A := nil;
  TVMemMgr.ReallocateDiscardable(A, 24);
  Check(A <> nil, 'reallocating nil allocates a buffer');
  Fill(A, 24, $33);
  Check(IsFilled(A, 24, $33), 'the data of a buffer made by ReallocateDiscardable');
  TVMemMgr.FreeDiscardable(A);
  Check((A = nil) and (not TBufListEntry.FreeHead), 'the buffer made by ReallocateDiscardable is in the list');

  { A size 0 frees the buffer. }
  A := nil;
  TVMemMgr.AllocateDiscardable(A, 24);
  TVMemMgr.ReallocateDiscardable(A, 0);
  Check(A = nil, 'reallocating to size 0 clears the pointer');
  Check(not TBufListEntry.FreeHead, 'reallocating to size 0 takes the buffer out of the list');
  TVMemMgr.ReallocateDiscardable(A, 0);
  Check(A = nil, 'reallocating nil to size 0 gives nil');

  { The same size changes nothing. }
  A := nil;
  TVMemMgr.AllocateDiscardable(A, 32);
  FillRamp(A, 32);
  P := A;
  TVMemMgr.ReallocateDiscardable(A, 32);
  Check(A = P, 'reallocating to the same size keeps the address');
  Check(IsRamp(A, 32), 'reallocating to the same size keeps the data');
  TVMemMgr.FreeDiscardable(A);

  { A smaller size keeps the data. }
  A := nil;
  TVMemMgr.AllocateDiscardable(A, 64);
  FillRamp(A, 64);
  TVMemMgr.ReallocateDiscardable(A, 10);
  Check(A <> nil, 'a smaller buffer is kept');
  Check(IsRamp(A, 10), 'the data of a smaller buffer is the start of the old data');
  TVMemMgr.FreeDiscardable(A);
  Check((A = nil) and (not TBufListEntry.FreeHead), 'a smaller buffer is freed through its owner');

  { A cut buffer stays in the list at its place. }
  A := nil;
  B := nil;
  C := nil;
  TVMemMgr.AllocateDiscardable(A, 64);
  TVMemMgr.AllocateDiscardable(B, 64);
  TVMemMgr.AllocateDiscardable(C, 64);
  FillRamp(A, 64);
  FillRamp(B, 64);
  FillRamp(C, 64);
  TVMemMgr.ReallocateDiscardable(B, 4);
  TVMemMgr.ReallocateDiscardable(C, 4);
  TVMemMgr.ReallocateDiscardable(A, 4);
  Check((A <> nil) and (B <> nil) and (C <> nil), 'the three cut buffers are kept');
  Check(IsRamp(A, 4) and IsRamp(B, 4) and IsRamp(C, 4), 'the three cut buffers keep their data');
  Check(TBufListEntry.FreeHead and (C = nil) and (B <> nil) and (A <> nil), 'the newest cut buffer is still the head');
  Check(TBufListEntry.FreeHead and (B = nil) and (A <> nil), 'the middle cut buffer is still second');
  Check(TBufListEntry.FreeHead and (A = nil), 'the oldest cut buffer is still last');
  Check(not TBufListEntry.FreeHead, 'the list is empty after the cut buffers are discarded');

  { A larger size gives a new buffer, which is the newest. }
  A := nil;
  X := nil;
  TVMemMgr.AllocateDiscardable(A, 8);
  TVMemMgr.AllocateDiscardable(X, 8);
  TVMemMgr.ReallocateDiscardable(A, 100);
  Check(A <> nil, 'a larger buffer is allocated');
  Fill(A, 100, $11);
  Check(IsFilled(A, 100, $11), 'the larger buffer has room for its size');
  Check(TBufListEntry.FreeHead, 'the list has a buffer after the growth');
  Check((A = nil) and (X <> nil), 'the larger buffer is the newest of the list');
  TVMemMgr.FreeDiscardable(X);
  Check((X = nil) and (not TBufListEntry.FreeHead), 'the list is empty after the other buffer is freed');

  { The owner is the variable that was given when the buffer was made. }
  P := nil;
  TVMemMgr.AllocateDiscardable(P, 8);
  Q := P;
  TVMemMgr.ReallocateDiscardable(Q, 100);
  Check(P = nil, 'the growth clears the variable that owns the old buffer');
  Check(Q <> nil, 'the variable that was passed gets the new buffer');
  TVMemMgr.FreeDiscardable(Q);
  Check((Q = nil) and (not TBufListEntry.FreeHead), 'the new buffer is owned by the variable that was passed');
end;

procedure TestReallocateWithoutPool;
begin
  A := nil;
  TVMemMgr.AllocateDiscardable(A, 64);
  TVMemMgr.ClearSafetyPool;

  TVMemMgr.ReallocateDiscardable(A, 8);
  Check(A <> nil, 'a buffer is made smaller while the safety pool is exhausted');

  TVMemMgr.ReallocateDiscardable(A, 100);
  Check(A = nil, 'a buffer cannot grow while the safety pool is exhausted');
  Check(not TBufListEntry.FreeHead, 'the buffer that could not grow is gone from the list');

  A := nil;
  TVMemMgr.ReallocateDiscardable(A, 10);
  Check(A = nil, 'reallocating nil gives nil while the safety pool is exhausted');

  TVMemMgr.ResizeSafetyPool;
  TVMemMgr.ReallocateDiscardable(A, 10);
  Check(A <> nil, 'reallocating nil allocates once the safety pool is back');
  TVMemMgr.FreeDiscardable(A);
end;

procedure TestManagerLifetime;
var
  M, M2: TVMemMgr;
begin
  TVMemMgr.ClearSafetyPool;
  M := TVMemMgr.Create;
  Check(TVMemMgr.SafetyPoolExhausted = 1, 'a manager made after the pool was set up does not make the pool again');
  M.Free;
  Check(TVMemMgr.SafetyPoolExhausted = 0, 'destroying a manager leaves the pool not set up, so it is not exhausted');
  Check(not LowMemory, 'the memory is not low after a manager was destroyed');

  A := nil;
  TVMemMgr.AllocateDiscardable(A, 16);
  Check(A <> nil, 'a buffer is allocated while the pool is not set up');
  TVMemMgr.FreeDiscardable(A);

  M2 := TVMemMgr.Create;
  Check(TVMemMgr.SafetyPoolExhausted = 0, 'a manager made while the pool is not set up makes the pool');
  TVMemMgr.ClearSafetyPool;
  Check(TVMemMgr.SafetyPoolExhausted = 1, 'the pool of that manager can be cleared');
  M2.Free;
  Check(TVMemMgr.SafetyPoolExhausted = 0, 'destroying the manager again leaves the pool not set up');

  TVMemMgr.ResizeSafetyPool;
  Check((TVMemMgr.SafetyPoolExhausted = 0) and (not TBufListEntry.FreeHead), 'the pool is back and the list is empty');
end;

begin
  TestInitialState;
  TestSafetyPool;
  TestAllocate;
  TestListOrder;
  TestReallocate;
  TestReallocateWithoutPool;
  TestManagerLifetime;
  Done;
end.
