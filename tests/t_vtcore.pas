{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/termemu.h, include/tvterm/array.h, include/tvterm/mutex.h, include/tvterm/consts.h
  See COPYRIGHT.tvterm.

  The expected values are worked out by hand from the C++. A range of rows that has no row is {MaxInt, MinInt}. The
  selection of the tests goes from {2, 1} to {5, 3} with 10 columns, so row 1 gives [2, 10), row 2 gives [0, 10) and
  row 3 gives [0, 5). The surface of the damage tests is 6 columns by 4 rows. The two threads of the lock test add 1
  to a counter 300 times each, so the counter ends at 600. }
program t_vtcore;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses cthreads, SysUtils, TvGeom, TvEvents, TvPty, TvVtCore;

{$I testlib.inc}

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Anchor(X, Y: Integer): SelectionAnchor;
begin
  Result := SelectionAnchor.Create(X, Y);
end;

function IsRange(const R: RowRange; From, Upto: Integer): Boolean;
begin
  Result := (R.Start = From) and (R.RangeEnd = Upto);
end;

function IsUnset(const R: RowRange): Boolean;
begin
  Result := (R.Start = High(LongInt)) and (R.RangeEnd = Low(LongInt));
end;

function TextOf(G: GrowArray): AnsiString;
begin
  SetString(Result, G.Data, G.Size);
end;

procedure TestRowRange;
var
  R: RowRange;
begin
  R := RowRange.Unset;
  Check(IsUnset(R), 'unset range is MaxInt..MinInt');
  Check(R.Size = 0, 'unset range has size 0');
  Check(RowRange.Create(3, 8).Size = 5, 'size of [3,8)');
  Check(RowRange.Create(8, 3).Size = 0, 'size of a reversed range');
  Check(RowRange.Create(5, 5).Size = 0, 'size of an empty range');
  Check(IsRange(RowRange.Create(2, 10).Intersect(RowRange.Create(5, 20)), 5, 10), 'intersect overlapping');
  R := RowRange.Create(0, 4).Intersect(RowRange.Create(6, 9));
  Check(IsRange(R, 6, 4), 'intersect disjoint keeps max start and min end');
  Check(R.Size = 0, 'disjoint intersection has size 0');
  Check(IsUnset(RowRange.Unset.Intersect(RowRange.Create(1, 5))), 'unset stays unset when intersected');
  Check(RowRange.Create(1, 2) <> RowRange.Create(1, 3), 'ranges differ in end');
  Check(RowRange.Create(0, 2) <> RowRange.Create(1, 2), 'ranges differ in start');
  Check(not (RowRange.Create(1, 2) <> RowRange.Create(1, 2)), 'equal ranges do not differ');
end;

procedure TestAnchors;
var
  P: TPoint;
  A: SelectionAnchor;
begin
  Check(Anchor(3, 1) < Anchor(0, 2), 'smaller row is smaller');
  Check(Anchor(5, 2) < Anchor(6, 2), 'same row, smaller column');
  Check(not (Anchor(6, 2) < Anchor(5, 2)), 'same row, larger column is not smaller');
  Check(not (Anchor(4, 4) < Anchor(4, 4)), 'equal anchors are not smaller');
  Check(not (Anchor(4, 4) > Anchor(4, 4)), 'equal anchors are not larger');
  Check(Anchor(0, 3) > Anchor(9, 2), 'larger row is larger');
  Check(Anchor(7, 5) > Anchor(6, 5), 'same row, larger column is larger');
  Check(Anchor(1, 1) = Anchor(1, 1), 'equal anchors are equal');
  Check(not (Anchor(1, 1) = Anchor(2, 1)), 'different anchors are not equal');
  P := Anchor(7, 9).ToPoint;
  Check((P.X = 7) and (P.Y = 9), 'anchor gives a point');
  Check(Anchor(3, 3).Compare(Anchor(9, 2)) > 0, 'compare: later row');
  Check(Anchor(3, 3).Compare(Anchor(4, 3)) < 0, 'compare: same row, earlier column');
  Check(Anchor(3, 3).Compare(Anchor(3, 3)) = 0, 'compare: equal');
  A := SelectionAnchor.Create(Pt(8, 2));
  Check((A.X = 8) and (A.Y = 2), 'anchor made from a point');
end;

procedure TestSelectionRows;
var
  Sel: SelectionRange;
begin
  Sel := SelectionRange.Create(Anchor(2, 1), Anchor(5, 3));
  Check(not Sel.Empty, 'selection is not empty');
  Check(IsUnset(Sel.IntersectRow(0, 10)), 'row before the selection');
  Check(IsRange(Sel.IntersectRow(1, 10), 2, 10), 'first row of the selection');
  Check(IsRange(Sel.IntersectRow(2, 10), 0, 10), 'middle row of the selection');
  Check(IsRange(Sel.IntersectRow(3, 10), 0, 5), 'last row of the selection');
  Check(IsUnset(Sel.IntersectRow(4, 10)), 'row after the selection');

  Sel := SelectionRange.Create(Anchor(5, 3), Anchor(2, 1));
  Check(not Sel.Empty, 'reversed selection is not empty');
  Check(IsRange(Sel.IntersectRow(1, 10), 2, 10), 'reversed: first row');
  Check(IsRange(Sel.IntersectRow(2, 10), 0, 10), 'reversed: middle row');
  Check(IsRange(Sel.IntersectRow(3, 10), 0, 5), 'reversed: last row');
  Check(IsUnset(Sel.IntersectRow(0, 10)), 'reversed: row before');

  Sel := SelectionRange.Create(Anchor(6, 2), Anchor(2, 2));
  Check(IsRange(Sel.IntersectRow(2, 10), 2, 6), 'selection inside one row, reversed');
  Check(IsUnset(Sel.IntersectRow(1, 10)), 'one row selection: row above');

  Sel := SelectionRange.Create(Anchor(4, 4), Anchor(4, 4));
  Check(Sel.Empty, 'equal anchors make an empty selection');
  Check(IsUnset(Sel.IntersectRow(4, 10)), 'empty selection selects nothing');

  Sel := SelectionRange.Create(Anchor(-3, 0), Anchor(4, 1));
  Check(IsRange(Sel.IntersectRow(0, 10), 0, 10), 'negative start column is cut to 0');
  Check(IsRange(Sel.IntersectRow(1, 10), 0, 4), 'last row ends at its column');

  Sel := SelectionRange.Create(Anchor(1, 0), Anchor(50, 0));
  Check(IsRange(Sel.IntersectRow(0, 10), 1, 10), 'end column is cut to the column count');
end;

procedure TestDamage;
var
  S: TerminalSurface;
begin
  S := TerminalSurface.Create;
  try
    Check((S.Size.X = 0) and (S.Size.Y = 0), 'new surface has no size');
    S.Resize(Pt(6, 4));
    Check((S.Size.X = 6) and (S.Size.Y = 4), 'resize sets the size');
    Check(S.At(0, 0) <> nil, 'resized surface has cells');
    Check(IsUnset(S.DamageAtRow(0)^) and IsUnset(S.DamageAtRow(3)^), 'new rows are undamaged');

    S.AddDamageAtRow(1, 2, 5);
    Check(IsRange(S.DamageAtRow(1)^, 2, 5), 'first damage of a row');
    S.AddDamageAtRow(1, 4, 9);
    Check(IsRange(S.DamageAtRow(1)^, 2, 9), 'damage extends the end');
    S.AddDamageAtRow(1, 0, 1);
    Check(IsRange(S.DamageAtRow(1)^, 0, 9), 'damage extends the start');
    Check(IsUnset(S.DamageAtRow(0)^) and IsUnset(S.DamageAtRow(3)^), 'other rows stay undamaged');

    S.Resize(Pt(6, 4));
    Check(IsRange(S.DamageAtRow(1)^, 0, 9), 'resize to the same size keeps the damage');

    S.Resize(Pt(6, 5));
    Check(IsUnset(S.DamageAtRow(1)^), 'resize clears the damage');
    Check(IsUnset(S.DamageAtRow(4)^), 'the new row is undamaged');

    S.AddDamageAtRow(4, 3, 3);
    Check(IsRange(S.DamageAtRow(4)^, 3, 3), 'a range of no width is stored');
    S.ClearDamage;
    Check(IsUnset(S.DamageAtRow(4)^), 'ClearDamage empties the ranges');

    S.Resize(Pt(5, -1));
    Check((S.Size.X = 5) and (S.Size.Y = -1), 'a negative height is kept as the size');
    S.Resize(Pt(2, 2));
    Check(IsUnset(S.DamageAtRow(0)^) and IsUnset(S.DamageAtRow(1)^), 'rows after a size that had no rows');
  finally
    S.Free;
  end;
end;

procedure TestGrowArray;
var
  G: GrowArray;
  Block: array[0..2999] of AnsiChar;
begin
  G := GrowArray.Create;
  try
    Check(G.Size = 0, 'new array is empty');
    Check(G.Data = nil, 'new array has no block');
    G.Push('abc', 3);
    Check(G.Size = 3, 'size after the first push');
    G.Push('de', 2);
    Check(G.Size = 5, 'size after the second push');
    Check(TextOf(G) = 'abcde', 'bytes of two pushes');
    FillChar(Block, SizeOf(Block), Ord('x'));
    G.Push(@Block[0], SizeOf(Block));
    Check(G.Size = 3005, 'size after a large push');
    Check(Copy(TextOf(G), 1, 5) = 'abcde', 'old bytes survive growing');
    Check((G.Data[3004] = 'x') and (G.Data[5] = 'x'), 'new bytes are stored');
    G.Push('q', 0);
    Check(G.Size = 3005, 'a push of no bytes keeps the size');
    G.Clear;
    Check(G.Size = 0, 'clear empties the array');
    Check(G.Data <> nil, 'clear keeps the block');
    G.Push('Z', 1);
    Check((G.Size = 1) and (G.Data[0] = 'Z'), 'push after clear starts at the beginning');
  finally
    G.Free;
  end;
end;

procedure TestStateAndConstants;
var
  St: TerminalState;
  K: TVTermConstants;
  Cmds: TWordSpan;
  Msg: TerminalUpdatedMsg;
  Ev: TerminalEvent;
begin
  St := TerminalState.Create;
  try
    Check((St.Surface.Size.X = 0) and (St.Surface.Size.Y = 0), 'state surface starts empty');
    Check(not St.CursorChanged and not St.CursorVisible and not St.CursorBlink, 'cursor flags start false');
    Check((St.CursorPos.X = 0) and (St.CursorPos.Y = 0), 'cursor starts at 0,0');
    Check(not St.TitleChanged and (St.Title.Size = 0), 'title starts empty');
    Check(not St.ScrollbackChanged and (St.ScrollbackOffset = 0) and (St.ScrollbackLimit = 0),
      'scrollback numbers start at 0');
    Check(St.ScrollbackEnabled, 'scrollback starts enabled');
    Check(not St.MouseEnabled, 'mouse starts disabled');

    FillChar(Msg, SizeOf(Msg), 0);
    Msg.State := St;
    St.CursorVisible := True;
    Check(Msg.State.CursorVisible and (Msg.View = nil), 'update message holds the state');
  finally
    St.Free;
  end;

  FillChar(K, SizeOf(K), 0);
  K.CmCopySelection := 3;
  K.CmCancelSelection := 4;
  K.CmGrabInput := 14;
  K.CmReleaseInput := 15;
  K.CmStartSelection := 16;
  K.HcInputGrabbed := 20;
  Cmds := K.FocusedCmds;
  Check(Cmds.Size = 3, 'three focused commands');
  Check((Cmds.Data[0] = 14) and (Cmds.Data[1] = 15) and (Cmds.Data[2] = 16), 'focused commands in order');

  FillChar(Ev, SizeOf(Ev), 0);
  Ev.Type_ := TerminalEventType.CopySelection;
  Ev.CopySelection.Selection := SelectionRange.Create(Anchor(11, 2), Anchor(3, 4));
  Check(Ev.Type_ = TerminalEventType.CopySelection, 'event type is kept');
  Check(Ev.ViewportResize.X = 11, 'event members share their storage');
  Check(IsRange(Ev.CopySelection.Selection.IntersectRow(3, 20), 0, 20), 'selection of an event');
  Ev.Type_ := TerminalEventType.Mouse;
  Ev.Mouse.What := evMouseDown;
  Ev.Mouse.Mouse.Where := Pt(5, 6);
  Check((Ev.Mouse.What = evMouseDown) and (Ev.Mouse.Mouse.Where.Y = 6), 'mouse event');
  Check(Ord(TerminalEventType.CopySelection) = 6, 'seven event types');
end;

type
  TEmulatorStub = class(TerminalEmulator)
  public
    Seen: TerminalEventType;
    Calls: Integer;
    Out_: Writer;
    procedure HandleEvent(const Event: TerminalEvent); override;
    procedure UpdateState(State: TerminalState); override;
  end;

  TWriterStub = class(Writer)
  public
    Got: AnsiString;
    procedure Write(const Data: array of Char); override;
  end;

  TFactoryStub = class(TerminalEmulatorFactory)
  public
    Vars: array[0..0] of EnvironmentVar;
    function Make(const Size: TPoint; ClientDataWriter: Writer): TerminalEmulator; override;
    function GetCustomEnvironment: TEnvironmentVarSpan; override;
  end;

procedure TEmulatorStub.HandleEvent(const Event: TerminalEvent);
begin
  Seen := Event.Type_;
  Inc(Calls);
end;

procedure TEmulatorStub.UpdateState(State: TerminalState);
begin
  State.TitleChanged := True;
  State.Title.Push('t', 1);
end;

procedure TWriterStub.Write(const Data: array of Char);
var
  K: Integer;
begin
  for K := 0 to High(Data) do
    Got := Got + Data[K];
end;

function TFactoryStub.Make(const Size: TPoint; ClientDataWriter: Writer): TerminalEmulator;
var
  Emu: TEmulatorStub;
begin
  Emu := TEmulatorStub.Create;
  Emu.Out_ := ClientDataWriter;
  Emu.Calls := Size.X * 100 + Size.Y;
  Result := Emu;
end;

function TFactoryStub.GetCustomEnvironment: TEnvironmentVarSpan;
begin
  Vars[0].Name := 'COLORTERM';
  Vars[0].Value := 'truecolor';
  Result.Data := @Vars[0];
  Result.Size := 1;
end;

procedure TestInterfaces;
var
  Fac: TFactoryStub;
  Wr: TWriterStub;
  Emu: TerminalEmulator;
  St: TerminalState;
  Ev: TerminalEvent;
  Env: TEnvironmentVarSpan;
begin
  Fac := TFactoryStub.Create;
  Wr := TWriterStub.Create;
  St := TerminalState.Create;
  Emu := Fac.Make(Pt(80, 24), Wr);
  try
    Check(TEmulatorStub(Emu).Calls = 8024, 'factory receives the size');
    Check(TEmulatorStub(Emu).Out_ = Wr, 'factory receives the writer');
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.Type_ := TerminalEventType.FocusChange;
    Ev.FocusChange.FocusEnabled := True;
    Emu.HandleEvent(Ev);
    Check(TEmulatorStub(Emu).Seen = TerminalEventType.FocusChange, 'emulator gets the event');
    Check(TEmulatorStub(Emu).Calls = 8025, 'one more call');
    Emu.UpdateState(St);
    Check(St.TitleChanged and (TextOf(St.Title) = 't'), 'emulator reports through the state');
    TEmulatorStub(Emu).Out_.Write(['h', 'i']);
    Check(Wr.Got = 'hi', 'writer gets the bytes');
    Env := Fac.GetCustomEnvironment;
    Check((Env.Size = 1) and (StrComp(Env.Data^.Name, 'COLORTERM') = 0)
      and (StrComp(Env.Data^.Value, 'truecolor') = 0), 'custom environment');
  finally
    Emu.Free;
    St.Free;
    Wr.Free;
    Fac.Free;
  end;
end;

type
  TCountMutex = specialize Mutex<LongInt>;

  TCounterOps = class
    Peeked: LongInt;
    procedure Bump(var Item: LongInt);
    procedure Peek(var Item: LongInt);
  end;

procedure TCounterOps.Bump(var Item: LongInt);
var
  Before: LongInt;
begin
  Before := Item;
  Sleep(0);
  Item := Before + 1;
end;

procedure TCounterOps.Peek(var Item: LongInt);
begin
  Peeked := Item;
end;

const
  BumpsPerThread = 300;

var
  SharedMutex: TCountMutex;
  SharedOps: TCounterOps;

function ThreadBody(Arg: Pointer): PtrInt;
var
  Round: Integer;
begin
  for Round := 1 to BumpsPerThread do
    SharedMutex.Lock(@SharedOps.Bump);
  Result := 0;
end;

procedure TestMutex;
var
  First, Second: TThreadID;
begin
  SharedOps := TCounterOps.Create;
  SharedMutex := TCountMutex.Create;
  try
    SharedMutex.Lock(@SharedOps.Peek);
    Check(SharedOps.Peeked = 0, 'item of a default mutex is 0');
  finally
    SharedMutex.Free;
  end;

  SharedMutex := TCountMutex.Create(40);
  try
    SharedMutex.Lock(@SharedOps.Peek);
    Check(SharedOps.Peeked = 40, 'item is the initial value');
    SharedMutex.Lock(@SharedOps.Bump);
    SharedMutex.Lock(@SharedOps.Bump);
    SharedMutex.Lock(@SharedOps.Peek);
    Check(SharedOps.Peeked = 42, 'two locked calls change the item twice');
  finally
    SharedMutex.Free;
  end;

  SharedMutex := TCountMutex.Create(0);
  try
    First := BeginThread(@ThreadBody, nil);
    Second := BeginThread(@ThreadBody, nil);
    WaitForThreadTerminate(First, 0);
    WaitForThreadTerminate(Second, 0);
    SharedMutex.Lock(@SharedOps.Peek);
    Check(SharedOps.Peeked = 2 * BumpsPerThread, 'two threads lose no update');
  finally
    SharedMutex.Free;
    SharedOps.Free;
  end;
end;

begin
  TestRowRange;
  TestAnchors;
  TestSelectionRows;
  TestDamage;
  TestGrowArray;
  TestStateAndConstants;
  TestInterfaces;
  TestMutex;
  Done;
end.
