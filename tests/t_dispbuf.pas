{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/dispbuff.h, source/platform/dispbuff.cpp,
  include/tvision/internal/platform.h, include/tvision/scrncell.h, include/tvision/internal/mutex.h,
  source/platform/mutex.cpp
  See COPYRIGHT.magiblot.

  The adapter of the tests records every call as a text: W<x>,<y>:<text>:<attribute>[+] for a cell (the plus
  marks a double-width cell), C<x>,<y> for the caret position, S<n> for the caret size, CLR for the screen
  clear and FL for the flush. The attributes are BIOS attributes in two hexadecimal digits. The expected texts
  are worked out by hand from the C++ routines. A cell with the default colors has the BIOS attribute 07. }
program t_dispbuf;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  SysUtils, TvGeom, TvColors, TvCell, TvText, TvDispBuf;

{$I testlib.inc}

const
  { U+4E2D, a double-width character. }
  Zhong = #$E4#$B8#$AD;

type
  TRecAdapter = class(DisplayAdapter)
  public
    Log: string;
    ScreenSize: TPoint;
    function ReloadScreenInfo: TPoint; override;
    procedure WriteCell(const Pos: TPoint; const Text: string; const Attr: TColorAttr;
      DoubleWidth: Boolean); override;
    procedure SetCaretPosition(const Pos: TPoint); override;
    procedure SetCaretSize(Size: Integer); override;
    procedure ClearScreen; override;
    procedure Flush; override;
  end;

var
  ZeroCell: TScreenCell;
  FakeNow: QWord;

function TRecAdapter.ReloadScreenInfo: TPoint;
begin
  Result := ScreenSize;
end;

procedure TRecAdapter.WriteCell(const Pos: TPoint; const Text: string; const Attr: TColorAttr;
  DoubleWidth: Boolean);
begin
  Log := Log + 'W' + IntToStr(Pos.X) + ',' + IntToStr(Pos.Y) + ':' + Text + ':' + IntToHex(Attr.ToBIOS, 2);
  if DoubleWidth then
    Log := Log + '+';
  Log := Log + ';';
end;

procedure TRecAdapter.SetCaretPosition(const Pos: TPoint);
begin
  Log := Log + 'C' + IntToStr(Pos.X) + ',' + IntToStr(Pos.Y) + ';';
end;

procedure TRecAdapter.SetCaretSize(Size: Integer);
begin
  Log := Log + 'S' + IntToStr(Size) + ';';
end;

procedure TRecAdapter.ClearScreen;
begin
  Log := Log + 'CLR;';
end;

procedure TRecAdapter.Flush;
begin
  Log := Log + 'FL;';
end;

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function CellOf(C: Char; Attr: Integer): TScreenCell;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Character.InitWithChar(C);
  Result.Attribute := TColorAttr.Create(Attr);
end;

function WideOf(const Utf8: string; Attr: Integer): TScreenCell;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Character.InitWithMultiByteChar(Utf8, True);
  Result.Attribute := TColorAttr.Create(Attr);
end;

function TrailOf(Attr: Integer): TScreenCell;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Character.InitAsWideCharTrail;
  Result.Attribute := TColorAttr.Create(Attr);
end;

procedure Put(Buf: DisplayBuffer; X, Y: Integer; const Cells: array of TScreenCell);
begin
  Buf.ScreenWrite(X, Y, @Cells[0], Length(Cells));
end;

function CellAtPtr(P: PScreenCell; Idx: Integer): TScreenCell;
begin
  Result := PScreenCell(PtrUInt(P) + PtrUInt(Idx) * SizeOf(TScreenCell))^;
end;

{ Returns what the adapter has recorded and forgets it. }
function Take(Rec: TRecAdapter): string;
begin
  Result := Rec.Log;
  Rec.Log := '';
end;

function FakeClock: QWord;
begin
  Result := FakeNow;
end;

function MapChars(C: Char): Cardinal;
begin
  case Ord(C) of
    1: Result := $00BA98E2;
    $B0: Result := $009196E2;
  else
    Result := Ord(C);
  end;
end;

procedure TestAdapterDefaults;
var
  Base: DisplayAdapter;
  Buf: DisplayBuffer;
  P: PScreenCell;
begin
  Base := DisplayAdapter.Create;
  Check(Base.ReloadScreenInfo = Pt(0, 0), 'default reload gives 0,0');
  Check(Base.GetColorCount = 0, 'default color count');
  Check(Base.GetFontSize = Pt(0, 0), 'default font size');
  Base.WriteCell(Pt(1, 1), 'a', TColorAttr.Create($07), False);
  Base.SetCaretPosition(Pt(1, 1));
  Base.SetCaretSize(10);
  Base.ClearScreen;
  Base.Flush;
  Buf := DisplayBuffer.Create(0);
  P := Buf.ReloadScreenInfo(Base);
  Check(Buf.Size = Pt(0, 0), 'size from a default adapter');
  Check(P = nil, 'no cells for an empty screen');
  Buf.FlushScreen(Base);
  Buf.ClearScreen(Base);
  Buf.RedrawScreen(Base);
  Buf.ScreenWrite(0, 0, nil, 1);
  Check(Buf.CaretSize = 0, 'flush with a default adapter');
  Buf.Free;
  Base.Free;
end;

procedure TestMutex;
var
  M: SignalSafeMutexState;
begin
  M := SignalSafeMutexState.Create;
  Check(not M.LockedByCurrentThread, 'mutex is free');
  M.Acquire;
  Check(M.LockedByCurrentThread, 'mutex is held');
  M.Acquire;
  Check(M.LockedByCurrentThread, 'mutex is held twice');
  M.Release;
  Check(M.LockedByCurrentThread, 'mutex is held once');
  M.Release;
  Check(not M.LockedByCurrentThread, 'mutex is free again');
  M.Free;
end;

procedure TestInitialState;
var
  Buf: DisplayBuffer;
  Rec: TRecAdapter;
  P: PScreenCell;
begin
  Buf := DisplayBuffer.Create(0);
  Rec := TRecAdapter.Create;
  Rec.ScreenSize := Pt(10, 3);
  Check(Buf.Size = Pt(0, 0), 'size before reload');
  Check(Buf.CaretSize = -1, 'caret size before reload');
  P := Buf.ReloadScreenInfo(Rec);
  Check(P <> nil, 'cells after reload');
  Check(Buf.Size = Pt(10, 3), 'size after reload');
  Check(Buf.CaretSize = -1, 'caret size after reload');
  Check(CellAtPtr(P, 0) = ZeroCell, 'first cell is zero');
  Check(CellAtPtr(P, 29) = ZeroCell, 'last cell is zero');
  Check(Rec.Log = '', 'reload writes nothing');
  Buf.Free;
  Rec.Free;
end;

{ One buffer through a series of writes and flushes; each step relies on the state of the one before. }
procedure TestScenario;
var
  Buf: DisplayBuffer;
  Rec: TRecAdapter;
  P, Before: PScreenCell;
begin
  Buf := DisplayBuffer.Create(0);
  Rec := TRecAdapter.Create;
  Rec.ScreenSize := Pt(10, 3);
  P := Buf.ReloadScreenInfo(Rec);

  { A cell, the first flush gives the caret size. }
  Put(Buf, 2, 1, [CellOf('A', $1F)]);
  Check(CellAtPtr(P, 12).Character.GetText = 'A', 'write lands in the buffer');
  Check(CellAtPtr(P, 12).Attribute = $1F, 'write keeps the attribute');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W2,1:A:1F;S0;FL;', 'first flush');
  Check(Buf.CaretSize = 0, 'caret size after the flush');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'a flush with nothing changed');

  { Caret position and size. }
  Buf.SetCaretPosition(4, 1);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'C4,1;FL;', 'caret position');
  Buf.SetCaretSize(30);
  Check(Buf.CaretSize = 0, 'caret size is taken at the flush');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'C4,1;S30;FL;', 'caret size 30');
  Check(Buf.CaretSize = 30, 'caret size 30 is kept');
  Buf.SetCaretSize(0);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'C4,1;S0;FL;', 'caret hidden');
  Check(Buf.CaretSize = 0, 'caret size 0 is kept');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'nothing after the caret change');

  { Attribute changes. }
  Put(Buf, 0, 0, [CellOf('A', $1F), CellOf('B', $1F), CellOf('C', $2E)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:A:1F;W1,0:B:1F;W2,0:C:2E;C4,1;FL;', 'three cells');
  Put(Buf, 0, 0, [CellOf('A', $1F)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'C4,1;FL;', 'an unchanged cell is not written');
  Put(Buf, 0, 0, [CellOf('A', $4F)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:A:4F;C4,1;FL;', 'a changed attribute is written');

  { A wide character and its trail; the next cell has another attribute and is written too. }
  Put(Buf, 3, 2, [WideOf(Zhong, $1F), TrailOf($1F)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W3,2:' + Zhong + ':1F+;W5,2: :07;C4,1;FL;', 'wide character');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'nothing after the wide character');

{$IFNDEF WINDOWS}
  { The trail is overwritten: the cell is written alone. }
  Put(Buf, 4, 2, [CellOf('X', $07)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W4,2:X:07;C4,1;FL;', 'overwritten trail');
{$ENDIF}

  { A wide character in the last column is replaced with a space. }
  Put(Buf, 9, 1, [WideOf(Zhong, $1F)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W9,1: :1F;C4,1;FL;', 'wide character in the last column');

  { A trail with no wide character before it is written as a space, and the next cell is written because its
    attribute differs. }
  Put(Buf, 6, 2, [TrailOf($07)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W6,2: :07;W7,2: :07;C4,1;FL;', 'lone trail');

  { The cursor negates the attribute under it while the flush runs. }
  Buf.SetCursorVisibility(True);
  Buf.SetCursorPosition(2, 1);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W2,1:A:68;C4,1;FL;', 'cursor drawn');
  Check(CellAtPtr(P, 12).Attribute = $1F, 'cursor attribute is restored in the buffer');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'nothing while the cursor stays');
  Buf.SetCursorVisibility(False);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W2,1:A:1F;C4,1;FL;', 'cursor removed');

  { A new size: the cells are zero, the caret size is taken again, the caret position is kept. }
  Rec.ScreenSize := Pt(4, 2);
  P := Buf.ReloadScreenInfo(Rec);
  Check(Buf.Size = Pt(4, 2), 'size after the resize');
  Check(Buf.CaretSize = -1, 'caret size after the resize');
  Check(P <> nil, 'cells after the resize');
  Check(CellAtPtr(P, 0) = ZeroCell, 'first cell after the resize');
  Check(CellAtPtr(P, 7) = ZeroCell, 'last cell after the resize');
  Check(Take(Rec) = '', 'resize writes nothing');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'C4,1;S0;FL;', 'flush after the resize');

  { Writes outside of the screen change nothing. }
  Put(Buf, 9, 1, [CellOf('Q', $07)]);
  Put(Buf, 4, 0, [CellOf('Q', $07)]);
  Put(Buf, 0, 2, [CellOf('Q', $07)]);
  Put(Buf, -1, 0, [CellOf('Q', $07)]);
  Buf.ScreenWrite(0, 0, @ZeroCell, 0);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'writes outside of the screen');

  { A write that is longer than the row is cut. }
  Put(Buf, 2, 0, [CellOf('p', $07), CellOf('q', $07), CellOf('r', $07)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W2,0:p:07;W3,0:q:07;C4,1;FL;', 'write cut at the end of the row');

  { A write from the buffer itself changes nothing in the buffer and still marks the cells. }
  Before := PScreenCell(PtrUInt(P) + 2 * SizeOf(TScreenCell));
  Buf.ScreenWrite(2, 0, Before, 2);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'C4,1;FL;', 'write from the buffer itself');

  { Clearing writes nothing of the cells, keeps the storage and gives zero cells. }
  Buf.ClearScreen(Rec);
  Check(Take(Rec) = 'CLR;FL;', 'clear screen');
  Check(CellAtPtr(P, 2) = ZeroCell, 'cell after the clear');
  Check(CellAtPtr(P, 3) = ZeroCell, 'next cell after the clear');
  Put(Buf, 0, 0, [CellOf('Z', $07)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:Z:07;C4,1;FL;', 'write after the clear');

  Buf.Free;
  Rec.Free;
end;

procedure TestRedraw;
var
  Buf: DisplayBuffer;
  Rec: TRecAdapter;
begin
  Buf := DisplayBuffer.Create(0);
  Rec := TRecAdapter.Create;
  Rec.ScreenSize := Pt(3, 2);
  Buf.ReloadScreenInfo(Rec);
  Put(Buf, 0, 0, [CellOf('a', $1F), CellOf('b', $2E), CellOf('c', $07)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:a:1F;W1,0:b:2E;W2,0:c:07;S0;FL;', 'cells before the redraw');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'no flush before the redraw');
  Buf.RedrawScreen(Rec);
  Check(Take(Rec) = 'W0,0:a:1F;W1,0:b:2E;W2,0:c:07;W0,1: :07;W1,1: :07;W2,1: :07;FL;', 'redraw writes every cell');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'no flush after the redraw');
  Buf.Free;
  Rec.Free;
end;

procedure TestControlCharacters;
var
  Buf: DisplayBuffer;
  Rec: TRecAdapter;
  Saved: TPackedUtf8Func;
begin
  Saved := CodePageToPackedUtf8;
  CodePageToPackedUtf8 := @MapChars;
  Buf := DisplayBuffer.Create(0);
  Rec := TRecAdapter.Create;
  Rec.ScreenSize := Pt(5, 1);
  Buf.ReloadScreenInfo(Rec);
  Put(Buf, 0, 0, [CellOf(#1, $07), CellOf(#$B0, $07), CellOf(#0, $07)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:' + #$E2#$98#$BA + ':07;W1,0:' + #$E2#$96#$91 + ':07;W2,0: :07;S0;FL;',
    'control and extended characters come from the code page');
  Buf.Free;
  Rec.Free;
  CodePageToPackedUtf8 := Saved;
end;

procedure TestWideSpill;
var
  Buf: DisplayBuffer;
  Rec: TRecAdapter;
begin
  { The cell after a wide character has the same attribute: it is not written again. }
  Buf := DisplayBuffer.Create(0);
  Rec := TRecAdapter.Create;
  Rec.ScreenSize := Pt(6, 1);
  Buf.ReloadScreenInfo(Rec);
  Put(Buf, 2, 0, [CellOf('q', $1F)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W2,0:q:1F;S0;FL;', 'cell before the wide character');
  Put(Buf, 0, 0, [WideOf(Zhong, $1F), TrailOf($1F)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:' + Zhong + ':1F+;FL;', 'same attribute after the wide character');
  Buf.Free;

  { The cursor on a trail is drawn on the wide character. }
  Buf := DisplayBuffer.Create(0);
  Buf.ReloadScreenInfo(Rec);
  Put(Buf, 0, 0, [WideOf(Zhong, $1F), TrailOf($1F), CellOf('z', $07)]);
  Buf.SetCursorVisibility(True);
  Buf.SetCursorPosition(1, 0);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:' + Zhong + ':68+;W2,0:z:07;S0;FL;', 'cursor on a trail');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'nothing while the cursor stays on the trail');
  Buf.SetCursorPosition(2, 0);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:' + Zhong + ':1F+;W2,0:z:70;FL;', 'cursor moved off the trail');
  Buf.Free;
  Rec.Free;
end;

procedure TestRate;
var
  Buf: DisplayBuffer;
  Rec: TRecAdapter;
  SavedClock: TDisplayClockFunc;
begin
  SavedClock := DisplayClock;
  DisplayClock := @FakeClock;

  { One flush per second at most. }
  FakeNow := 5000000;
  Buf := DisplayBuffer.Create(1);
  Rec := TRecAdapter.Create;
  Rec.ScreenSize := Pt(2, 1);
  Buf.ReloadScreenInfo(Rec);
  Check(Buf.TimeUntilPendingFlushMs = -1, 'no pending flush at the start');
  Put(Buf, 0, 0, [CellOf('x', $07)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:x:07;S0;FL;', 'first flush of a limited rate');
  Check(Buf.TimeUntilPendingFlushMs = -1, 'no pending flush after a flush');
  Put(Buf, 1, 0, [CellOf('y', $07)]);
  FakeNow := 5300000;
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'a flush that is too early');
  Check(Buf.TimeUntilPendingFlushMs = 700, 'time until the pending flush');
  FakeNow := 5900000;
  Check(Buf.TimeUntilPendingFlushMs = 100, 'time until the pending flush, later');
  FakeNow := 6500000;
  Check(Buf.TimeUntilPendingFlushMs = 0, 'the pending flush is due');
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W1,0:y:07;FL;', 'the pending flush');
  Check(Buf.TimeUntilPendingFlushMs = -1, 'the pending flush is gone');

  { A redraw does not wait. }
  Put(Buf, 0, 0, [CellOf('x', $0A)]);
  FakeNow := 6600000;
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'another flush that is too early');
  Buf.RedrawScreen(Rec);
  Check(Take(Rec) = 'W0,0:x:0A;W1,0:y:07;FL;', 'redraw ignores the rate');
  Check(Buf.TimeUntilPendingFlushMs = -1, 'no pending flush after the redraw');

  { Reset gives the first state and keeps the rate. }
  Buf.Reset;
  Check(Buf.Size = Pt(0, 0), 'size after the reset');
  Check(Buf.CaretSize = -1, 'caret size after the reset');
  Check(Buf.TimeUntilPendingFlushMs = -1, 'no pending flush after the reset');
  FakeNow := 9000000;
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'S0;FL;', 'flush after the reset');
  Buf.SetCaretPosition(2, 2);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'the rate is kept by the reset');
  Check(Buf.TimeUntilPendingFlushMs = 1000, 'time until the pending flush after the reset');
  Buf.Free;

{$IFNDEF WINDOWS}
  { A negative rate is 60 flushes per second: a delay of 16666 microseconds. }
  FakeNow := 100000;
  Buf := DisplayBuffer.Create(-1);
  Rec.ScreenSize := Pt(1, 1);
  Buf.ReloadScreenInfo(Rec);
  Rec.Log := '';
  Put(Buf, 0, 0, [CellOf('m', $07)]);
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = 'W0,0:m:07;S0;FL;', 'first flush at the default rate');
  Put(Buf, 0, 0, [CellOf('n', $07)]);
  FakeNow := 110000;
  Buf.FlushScreen(Rec);
  Check(Take(Rec) = '', 'a flush that is too early at the default rate');
  Check(Buf.TimeUntilPendingFlushMs = 6, 'time until the pending flush at the default rate');
  Buf.Free;
{$ENDIF}

  Rec.Free;
  DisplayClock := SavedClock;
end;

begin
  FillChar(ZeroCell, SizeOf(ZeroCell), 0);
  TestAdapterDefaults;
  TestMutex;
  TestInitialState;
  TestScenario;
  TestRedraw;
  TestControlCharacters;
  TestWideSpill;
  TestRate;
  Done;
end.
