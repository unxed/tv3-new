{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (THistoryViewer, THistInit, THistoryWindow, THistory),
  include/tvision/views.h, include/tvision/ttypes.h, include/tvision/tv.h, include/tvision/config.h,
  source/tvision/histlist.cpp, source/tvision/thistory.cpp, source/tvision/thistwin.cpp, source/tvision/thstview.cpp,
  source/tvision/tvtext1.cpp (the icon of THistory), include/tvision/util.h, source/tvision/misc.cpp (strnzcpy)
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it. The
  root reads its events from a script, and from the posted events of the event queue when the script asks for it.
  The colors of the root are the BIOS attributes $41 and above: the entry k of its palette is $40 + k. The messages
  that the views send to their owners reach the views of the root. }
program t_hist;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Classes, SysUtils, TvGeom, TvKeys, TvEvents, TvSys, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvTimer, TvViews,
  TvWindow, TvList, TvInput, TvDialog, TvApp, TvHist;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 20;
  { No wait of these tests lasts longer than this, so that a failure ends the program. }
  Guard = 10000;
  WideCh = #$E6#$97#$A5;

type
  TFakeDisplay = class(TScreenBackend)
  public
    CaretSize: Word;
    procedure SetCaretSize(ASize: Word); override;
    function GetCaretSize: Word; override;
  end;

  { The root of the views: reads a script of events, or the events that are posted to the event queue. }
  TRoot = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    UseQueue: Boolean;
    Deadline: Int64;
    ErrorCount: Integer;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    procedure EventError(var Event: TEvent); override;
    function GetPalette: TPalette; override;
  end;

  { A history view that counts what is asked of it. With MakeWindow it opens the window of THistory, and without it
    no window. }
  TTestHistory = class(THistory)
  public
    MakeWindow: Boolean;
    WindowCalls: Integer;
    LastArea: TRect;
    LastHelp: Word;
    RecordCalls: Integer;
    LastRecorded: string;
    function InitHistoryWindow(const Bounds: TRect): THistoryWindow; override;
    procedure RecordHistory(const Text: string); override;
    function LinkOf: TInputLine;
    function IdOf: Word;
  end;

  { A history window that ends its modal loop at cmOK, and shows its viewer. }
  TTestWindow = class(THistoryWindow)
  public
    procedure HandleEvent(var Event: TEvent); override;
    function ViewerOf: TListViewer;
  end;

  TTestInit = class(THistInit)
  public
    function MakerOf: TCreateListViewerFunc;
  end;

  { A selectable view that refuses to give up the focus. }
  TStubborn = class(TView)
  public
    procedure Draw; override;
    function Valid(Command: Word): Boolean; override;
  end;

  TPoster = class(TThread)
  private
    FKind: Integer;
    FDelay: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AKind, ADelay: Integer);
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  GetCalls: Integer;
  WakeFlag: LongInt;
  RootPal: TPalette;

{ The fake display and the hooks. }

procedure TFakeDisplay.SetCaretSize(ASize: Word);
begin
  CaretSize := ASize;
end;

function TFakeDisplay.GetCaretSize: Word;
begin
  Result := CaretSize;
end;

procedure OnCaret(X, Y: Integer);
begin
end;

procedure OnScreenWrite(X, Y: Integer; Buf: PScreenCell; Count: Integer);
begin
end;

function Now64: Int64;
begin
  Result := Int64(GetTickCount64);
end;

{ Small helpers. }

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function RectIs(const Area: TRect; AX, AY, BX, BY: Integer): Boolean;
begin
  Result := (Area.A.X = AX) and (Area.A.Y = AY) and (Area.B.X = BX) and (Area.B.Y = BY);
end;

function KeyEv(Code: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Code;
end;

function CmdEv(Cmd: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evCommand;
  Result.Message.Command := Cmd;
end;

function MouseEv(X, Y: Integer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evMouseDown;
  Result.Mouse.Where := Pt(X, Y);
  Result.Mouse.Buttons := mbLeftButton;
end;

function DoubleClickEv(X, Y: Integer): TEvent;
begin
  Result := MouseEv(X, Y);
  Result.Mouse.EventFlags := meDoubleClick;
end;

function BroadcastEv(Cmd: Word; Info: Pointer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evBroadcast;
  Result.Message.Command := Cmd;
  Result.Message.InfoPtr := Info;
end;

function CellText(X, Y: Integer): string;
begin
  Result := ScreenCells[Y * ScrW + X].Character.GetText;
end;

function CharAt(X, Y: Integer): Char;
var
  Text: string;
begin
  Text := CellText(X, Y);
  if Length(Text) > 0 then
    Result := Text[1]
  else
    Result := #0;
end;

function AttrAt(X, Y: Integer): Integer;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute.ToBIOS;
end;

function RowText(Y, X0, N: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to N - 1 do
    Result := Result + CharAt(X0 + I, Y);
end;

procedure ClearScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
end;

{ The number of the entry I of a palette. }
function PalByte(P: TPalette; I: Integer): Integer;
var
  A: TColorAttr;
begin
  A := P.Items[I];
  Result := A.ToBIOS;
end;

{ The text of an entry of a history list, and '<nil>' when there is none. }
function EntryOf(ListId: Byte; Index: Integer): string;
var
  Chars: PAnsiChar;
begin
  Chars := HistoryStr(ListId, Index);
  if Chars = nil then
    Result := '<nil>'
  else
    Result := Chars;
end;

procedure ResetHistory;
begin
  DoneHistory;
  HistorySize := 1024;
  InitHistory;
end;

{ The views of the tests. }

procedure TRoot.AddEvent(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TRoot.GetEvent(var Event: TEvent);
var
  nowMs: Int64;
begin
  Inc(GetCalls);
  if GetCalls > 200000 then
  begin
    WriteLn('FAIL a loop of events does not end');
    Halt(1);
  end;
  FillChar(Event, SizeOf(Event), 0);
  if ScriptPos < Length(Script) then
  begin
    Event := Script[ScriptPos];
    Inc(ScriptPos);
    Exit;
  end;
  if not UseQueue then
    Exit;

  if TEventQueue.GetPostedEvent(Event) then
    Exit;
  FillChar(Event, SizeOf(Event), 0);
  nowMs := Now64;
  if InterlockedExchange(WakeFlag, 0) <> 0 then
    Event := CmdEv(cmOK)
  else if nowMs > Deadline then
    Event := CmdEv(cmCancel)
  else
    TEventQueue.WaitForEvents(Guard);
end;

procedure TRoot.EventError(var Event: TEvent);
begin
  Inc(ErrorCount);
end;

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
end;

function TTestHistory.InitHistoryWindow(const Bounds: TRect): THistoryWindow;
begin
  Inc(WindowCalls);
  LastArea := Bounds;
  Result := nil;
  if not MakeWindow then
    Exit;
  Result := inherited InitHistoryWindow(Bounds);
  LastHelp := Result.HelpCtx;
end;

procedure TTestHistory.RecordHistory(const Text: string);
begin
  Inc(RecordCalls);
  LastRecorded := Text;
  inherited RecordHistory(Text);
end;

function TTestHistory.LinkOf: TInputLine;
begin
  Result := Link;
end;

function TTestHistory.IdOf: Word;
begin
  Result := HistoryId;
end;

procedure TTestWindow.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;
  if Event.Message.Command <> cmOK then
    Exit;
  ClearEvent(Event);
  EndModal(cmOK);
end;

function TTestWindow.ViewerOf: TListViewer;
begin
  Result := Viewer;
end;

function TTestInit.MakerOf: TCreateListViewerFunc;
begin
  Result := CreateListViewer;
end;

procedure TStubborn.Draw;
begin
end;

function TStubborn.Valid(Command: Word): Boolean;
begin
  Result := Command <> cmReleasedFocus;
end;

constructor TPoster.Create(AKind, ADelay: Integer);
begin
  FKind := AKind;
  FDelay := ADelay;
  inherited Create(False);
end;

procedure TPoster.Execute;
var
  Ev: TEvent;
begin
  if FDelay > 0 then
    Sleep(FDelay);
  case FKind of
    0:
      begin
        Ev := CmdEv(cmOK);
        TEventQueue.PostEvent(Ev);
      end;
    1:
      begin
        InterlockedExchange(WakeFlag, 1);
        TEventQueue.WakeUp;
      end;
  end;
end;

function MakeRoot: TRoot;
begin
  ClearScreen;
  Result := TRoot.Create(Rc(0, 0, ScrW, ScrH));
  Result.Options := Result.Options and not ofBuffered;
  Result.Buffer := @ScreenCells[0];
  Result.State := Result.State or sfSelected;
  Result.SetState(sfExposed, True);
end;

procedure FreeRoot(R: TRoot);
begin
  TvObject.DestroyObject(R);
end;

{ A root with an input line at 5, 2 that is 20 cells wide, and the history view next to it, 3 cells wide. }
procedure MakeScene(out Root: TRoot; out Line: TInputLine; out View: TTestHistory; ListId: Word);
begin
  Root := MakeRoot;
  Line := TInputLine.Create(Rc(5, 2, 25, 3), 20);
  Root.Insert(Line);
  View := TTestHistory.Create(Rc(25, 2, 28, 3), Line, ListId);
  Root.Insert(View);
end;

function MakeBar(AX, AY, BX, BY: Integer): TScrollBar;
begin
  Result := TScrollBar.Create(Rc(AX, AY, BX, BY));
end;

{ The functions of histlist.cpp. }

procedure TestHistoryList;
var
  I: Integer;
begin
  InitHistory;
  Check(HistoryCount(1) = 0, 'a new history block has no entries');
  Check(HistoryStr(1, 0) = nil, 'a new history block gives no text');
  Check(HistorySize = 1024, 'the block of the lists has 1024 bytes at first');

  HistoryAdd(1, 'one');
  HistoryAdd(1, 'two');
  HistoryAdd(2, 'other');
  HistoryAdd(1, 'three');
  Check(HistoryCount(1) = 3, 'the list 1 has the three entries that were added to it');
  Check(HistoryCount(2) = 1, 'the list 2 has its own entry');
  Check(HistoryCount(3) = 0, 'a list that was not used is empty');
  Check((EntryOf(1, 0) = 'one') and (EntryOf(1, 1) = 'two') and (EntryOf(1, 2) = 'three'),
    'the entries of a list are in the order in which they were added');
  Check(EntryOf(2, 0) = 'other', 'the entry of the list 2');
  Check(EntryOf(1, 3) = '<nil>', 'an index after the last entry gives no text');

  HistoryAdd(1, '');
  Check(HistoryCount(1) = 3, 'an empty text is not added');

  HistoryAdd(1, 'one');
  Check(HistoryCount(1) = 3, 'a text that is already in the list is not added twice');
  Check((EntryOf(1, 0) = 'two') and (EntryOf(1, 1) = 'three') and (EntryOf(1, 2) = 'one'),
    'a text that is added again moves to the end');
  HistoryAdd(1, 'two');
  Check((EntryOf(1, 0) = 'three') and (EntryOf(1, 1) = 'one') and (EntryOf(1, 2) = 'two'),
    'the first entry moves to the end when it is added again');
  Check((HistoryCount(2) = 1) and (EntryOf(2, 0) = 'other'), 'a move in one list does not touch another list');
  HistoryAdd(2, 'one');
  Check((HistoryCount(2) = 2) and (EntryOf(2, 1) = 'one'), 'the same text can be in two lists');

  ClearHistory;
  Check((HistoryCount(1) = 0) and (HistoryCount(2) = 0), 'ClearHistory empties all lists');
  HistoryAdd(1, 'again');
  Check((HistoryCount(1) = 1) and (EntryOf(1, 0) = 'again'), 'a list that was cleared takes entries');

  DoneHistory;
  HistorySize := 40;
  InitHistory;
  HistoryAdd(1, 'aaaaaaaaaa');
  HistoryAdd(1, 'bbbbbbbbbb');
  Check(HistoryCount(1) = 2, 'two entries of 13 bytes fit in a block of 40 bytes');
  HistoryAdd(1, 'cccccccccc');
  Check((HistoryCount(1) = 2) and (EntryOf(1, 0) = 'bbbbbbbbbb') and (EntryOf(1, 1) = 'cccccccccc'),
    'the empty first record is dropped to make room, so the scan skips the oldest entry');
  HistoryAdd(1, 'dddddddddd');
  Check((HistoryCount(1) = 2) and (EntryOf(1, 0) = 'cccccccccc') and (EntryOf(1, 1) = 'dddddddddd'),
    'the oldest record is dropped when the block is full, and the scan skips the first record');
  HistoryAdd(1, StringOfChar('q', 50));
  Check(HistoryCount(1) = 0, 'a text that is larger than the block is not stored and the entries are dropped');
  ResetHistory;

  HistoryAdd(4, StringOfChar('z', 300));
  Check(Length(EntryOf(4, 0)) = 252, 'a text is cut to 252 bytes');
  HistoryAdd(4, StringOfChar('y', 252));
  Check((HistoryCount(4) = 2) and (Length(EntryOf(4, 1)) = 252), 'a text of 252 bytes is kept whole');
  HistoryAdd(4, StringOfChar('z', 300));
  Check((HistoryCount(4) = 2) and (EntryOf(4, 1)[1] = 'z'), 'the cut text is the one that is found again');

  ResetHistory;
  for I := 1 to 60 do
    HistoryAdd(5, 'entry number ' + IntToStr(I));
  Check(HistoryCount(5) < 60, 'a full block drops the oldest entries');
  Check(EntryOf(5, HistoryCount(5) - 1) = 'entry number 60', 'the newest entry stays');
  ResetHistory;

  Check(Assigned(InitHistoryHook) and Assigned(DoneHistoryHook), 'the unit gives its routines to the hooks of TvApp');
  HistoryAdd(1, 'before');
  DoneHistoryHook();
  Check(HistoryCount(1) = 0, 'DoneHistoryHook releases the lists');
  HistoryAdd(1, 'ignored');
  InitHistoryHook();
  Check(HistoryCount(1) = 0, 'a list that was released is empty after the start');
  HistoryAdd(1, 'hooked');
  Check((HistoryCount(1) = 1) and (EntryOf(1, 0) = 'hooked'), 'InitHistoryHook makes lists that take entries');
  ResetHistory;
end;

{ THistoryViewer. }

procedure TestViewer;
var
  HB, VB, HB2, VB2, HB3, VB3, HB4, VB4: TScrollBar;
  V, V2, V3, V4, V5, V6: THistoryViewer;
  Pal: TPalette;
  Ev: TEvent;
  Leftovers: array[0..13] of TvObject;
  Slot: Integer;
begin
  ResetHistory;
  HistoryAdd(5, 'alpha');
  HistoryAdd(5, 'beta');
  HistoryAdd(5, 'gamma');
  HistoryAdd(6, 'short');
  HistoryAdd(6, 'a long history entry');
  HistoryAdd(7, 'solo');
  HistoryAdd(10, WideCh + 'a');

  HB := MakeBar(0, 5, 10, 6);
  VB := MakeBar(10, 0, 11, 5);
  V := THistoryViewer.Create(Rc(0, 0, 10, 5), HB, VB, 5);
  Check(V.NumCols = 1, 'a history viewer has one column');
  Check(V.Range = 3, 'the range of a viewer is the number of entries of its list');
  Check(V.Focused = 1, 'a list of several entries focuses the second one');
  Check((VB.Value = 1) and (VB.MinVal = 0) and (VB.MaxVal = 2), 'the vertical bar follows the range and the focus');
  Check((VB.PgStep = 4) and (VB.ArStep = 1), 'the steps of the vertical bar');
  Check((HB.PgStep = 10) and (HB.ArStep = 1), 'the steps of the horizontal bar');
  Check((HB.MinVal = 0) and (HB.MaxVal = 0), 'a list narrower than the viewer gives a horizontal range of nothing');
  Check(V.HistoryWidth = 5, 'the width of a list is the width of its widest entry');
  Check((V.HScrollBar = HB) and (V.VScrollBar = VB), 'the viewer keeps its bars');

  Pal := V.GetPalette;
  Check((PalByte(Pal, 0) = 5) and (PalByte(Pal, 1) = 6) and (PalByte(Pal, 2) = 6) and (PalByte(Pal, 3) = 7) and
    (PalByte(Pal, 4) = 6) and (PalByte(Pal, 5) = 6), 'the palette of a history viewer');

  Check(V.GetText(0, 255) = 'alpha', 'the text of the first entry');
  Check(V.GetText(1, 255) = 'beta', 'the text of the second entry');
  Check(V.GetText(2, 255) = 'gamma', 'the text of the third entry');
  Check(V.GetText(2, 3) = 'gam', 'the text is cut to the given length');
  Check(V.GetText(0, 0) = '', 'a length of 0 gives no text');
  Check(V.GetText(3, 255) = '', 'an item after the last gives an empty text');

  HB2 := MakeBar(0, 5, 10, 6);
  VB2 := MakeBar(10, 0, 11, 5);
  V2 := THistoryViewer.Create(Rc(0, 0, 10, 5), HB2, VB2, 6);
  Check(V2.HistoryWidth = 20, 'the width of a list with a long entry');
  Check((HB2.MinVal = 0) and (HB2.MaxVal = 13), 'the horizontal range is the width, less the size, plus 3');
  Check((V2.Range = 2) and (V2.Focused = 1), 'a list of two entries focuses the second one');
  Check(V2.GetPalette = Pal, 'all history viewers share their palette');

  HB3 := MakeBar(0, 5, 10, 6);
  VB3 := MakeBar(10, 0, 11, 5);
  V3 := THistoryViewer.Create(Rc(0, 0, 10, 5), HB3, VB3, 7);
  Check((V3.Range = 1) and (V3.Focused = 0), 'a list of one entry keeps the focus on it');
  Check(VB3.MaxVal = 0, 'the vertical range of one entry');

  HB4 := MakeBar(0, 5, 10, 6);
  VB4 := MakeBar(10, 0, 11, 5);
  V4 := THistoryViewer.Create(Rc(0, 0, 10, 5), HB4, VB4, 8);
  Check((V4.Range = 0) and (V4.Focused = 0), 'a list without entries has an empty viewer');
  Check(V4.HistoryWidth = 0, 'the width of an empty list is 0');

  V5 := THistoryViewer.Create(Rc(0, 0, 10, 5), nil, nil, 10);
  Check(V5.HistoryWidth = 3, 'the width is counted in columns and not in bytes');
  Check((V5.Range = 1) and (V5.HScrollBar = nil), 'a viewer can have no bars');

  V6 := THistoryViewer.Create(Rc(0, 0, 10, 5), nil, nil, 5);
  Check((V6.Range = 3) and (V6.Focused = 1), 'a viewer without bars has its range and focus');

  Ev := KeyEv(kbEnter);
  V.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the Enter key is taken by the viewer');
  Ev := KeyEv(kbEsc);
  V.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the Esc key is taken by the viewer');
  Ev := CmdEv(cmCancel);
  V.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the command cmCancel is taken by the viewer');
  Ev := DoubleClickEv(3, 2);
  V.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a double click is taken by the viewer');
  Ev := CmdEv(cmOK);
  V.HandleEvent(Ev);
  Check(Ev.What = evCommand, 'another command is left to the list viewer');
  Ev := KeyEv(kbDown);
  V.HandleEvent(Ev);
  Check((V.Focused = 2) and (VB.Value = 2), 'the other keys go to the list viewer, which moves the focus');
  Ev := KeyEv(kbUp);
  V.HandleEvent(Ev);
  Check(V.Focused = 1, 'the key Up moves the focus back');

  Leftovers[0] := V;
  Leftovers[1] := V2;
  Leftovers[2] := V3;
  Leftovers[3] := V4;
  Leftovers[4] := V5;
  Leftovers[5] := V6;
  Leftovers[6] := HB;
  Leftovers[7] := VB;
  Leftovers[8] := HB2;
  Leftovers[9] := VB2;
  Leftovers[10] := HB3;
  Leftovers[11] := VB3;
  Leftovers[12] := HB4;
  Leftovers[13] := VB4;
  for Slot := 0 to 13 do
    TvObject.DestroyObject(Leftovers[Slot]);
  ResetHistory;
end;

{ THistInit and THistoryWindow. }

function MakeNothing(Area: TRect; Win: TWindow; ListId: Word): TListViewer;
begin
  Result := nil;
end;

procedure TestWindowParts;
var
  Root: TRoot;
  W: TTestWindow;
  Init: TTestInit;
  V: TListViewer;
  Pal: TPalette;
  Ev: TEvent;
begin
  ResetHistory;
  HistoryAdd(5, 'alpha');
  HistoryAdd(5, 'beta');
  HistoryAdd(5, 'gamma');

  Init := TTestInit.Create(Rc(0, 0, 30, 10), @MakeNothing);
  Check(Assigned(Init.MakerOf), 'THistInit keeps the function that makes the viewer');
  Check((Init.Number = wnNoNumber) and (Init.Frame <> nil), 'THistInit makes a window without a number, with a frame');
  TvObject.DestroyObject(Init);

  Root := MakeRoot;
  W := TTestWindow.Create(Rc(5, 3, 25, 11), 5);
  V := W.ViewerOf;
  Check(V <> nil, 'a history window makes its viewer');
  Check(V is THistoryViewer, 'the viewer of a history window is a history viewer');
  Check(W.Flags = wfClose, 'a history window can only be closed');
  Check(W.Number = wnNoNumber, 'a history window has no number');
  Check(W.Frame <> nil, 'a history window has a frame');
  Check((V.Origin.X = 1) and (V.Origin.Y = 1) and (V.Size.X = 18) and (V.Size.Y = 6),
    'the viewer fills the window inside its frame');
  Check((V.Range = 3) and (V.Focused = 1), 'the viewer shows the list of the given number');
  Check((V.HScrollBar <> nil) and (V.VScrollBar <> nil), 'the viewer has both bars');
  Check((V.HScrollBar.Origin.X = 2) and (V.HScrollBar.Origin.Y = 7) and (V.HScrollBar.Size.X = 16),
    'the horizontal bar is on the bottom row of the frame');
  Check((V.VScrollBar.Origin.X = 19) and (V.VScrollBar.Origin.Y = 1) and (V.VScrollBar.Size.Y = 6),
    'the vertical bar is on the right side of the frame');
  Check(((V.HScrollBar.Options and ofPostProcess) <> 0) and ((V.VScrollBar.Options and ofPostProcess) <> 0),
    'both bars take the keys');
  Check((V.VScrollBar.PgStep = 5) and (V.HScrollBar.PgStep = 18), 'the steps of the bars follow the size of the viewer');
  Check(V.HScrollBar.MaxVal = 0, 'the horizontal bar has no range for a narrow list');
  Check(W.GetSelection = 'beta', 'the selection is the text of the focused entry');

  Pal := W.GetPalette;
  Check((PalByte(Pal, 0) = 7) and (PalByte(Pal, 1) = 19) and (PalByte(Pal, 2) = 19) and (PalByte(Pal, 3) = 21) and
    (PalByte(Pal, 4) = 24) and (PalByte(Pal, 5) = 23) and (PalByte(Pal, 6) = 19) and (PalByte(Pal, 7) = 20),
    'the palette of a history window');

  Root.Insert(W);
  ClearScreen;
  V.DrawView;
  Check((RowText(4, 7, 5) = 'alpha') and (RowText(5, 7, 4) = 'beta') and (RowText(6, 7, 5) = 'gamma'),
    'the rows of the viewer show the entries');
  Check(CharAt(7, 7) = ' ', 'the rows after the last entry are blank');

  Ev := MouseEv(30, 15);
  W.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a click outside the window is taken by it');
  Ev := KeyEv(kbDown);
  W.HandleEvent(Ev);
  Check(V.Focused = 2, 'the keys of the window reach the viewer');
  Ev := KeyEv(kbEnter);
  W.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the Enter key is taken by the viewer of the window');

  FreeRoot(Root);
  ResetHistory;
end;

{ The modal loop of a history window as THistory runs it, and THistory itself. }

procedure TestHistoryView;
var
  Root: TRoot;
  Line: TInputLine;
  H, H2, H3: TTestHistory;
  Pal: TPalette;
  Ev: TEvent;
  Stub: TStubborn;
  Text0, Text1, Text2: string;
begin
  ResetHistory;
  MakeScene(Root, Line, H, 12);
  Check(H.IdOf = 12, 'the view keeps its history number');
  Check(H.LinkOf = Line, 'the view keeps its line');
  Check((H.Options and ofPostProcess) <> 0, 'the view takes the events after the others');
  Check((H.EventMask and evBroadcast) <> 0, 'the view takes broadcasts');
  Check((H.Size.X = 3) and (H.Size.Y = 1), 'the view is 3 cells wide');

  Pal := H.GetPalette;
  Check((PalByte(Pal, 0) = 2) and (PalByte(Pal, 1) = 22) and (PalByte(Pal, 2) = 23), 'the palette of a history view');
  Text0 := CellText(25, 2);
  Text1 := CellText(26, 2);
  Text2 := CellText(27, 2);
  Check((Text0 <> '') and (Text0 <> ' ') and (Text1 <> '') and (Text1 <> ' ') and (Text2 <> '') and (Text2 <> ' '),
    'the three cells of the view show the icon');
  Check((Text0 <> Text1) and (Text1 <> Text2) and (Text0 <> Text2), 'the icon has three different characters');
  Check((AttrAt(25, 2) = $57) and (AttrAt(26, 2) = $56) and (AttrAt(27, 2) = $57),
    'the arrow has the color 1 and the sides the color 2');
  Check(CellText(28, 2) = CellText(30, 10), 'the view draws nothing beyond its size');

  Line.Data := 'hello';
  Ev := BroadcastEv(cmRecordHistory, nil);
  H.HandleEvent(Ev);
  Check((H.RecordCalls = 1) and (H.LastRecorded = 'hello'), 'cmRecordHistory records the text of the line');
  Check((HistoryCount(12) = 1) and (EntryOf(12, 0) = 'hello'), 'the text is in the list of the view');
  Check(Ev.What = evBroadcast, 'a broadcast is not cleared');

  Line.Data := 'x1';
  Ev := BroadcastEv(cmReleasedFocus, Line);
  H.HandleEvent(Ev);
  Check((H.RecordCalls = 2) and (HistoryCount(12) = 2) and (EntryOf(12, 1) = 'x1'),
    'the line that gives up the focus is recorded');

  Line.Data := 'x2';
  Ev := BroadcastEv(cmReleasedFocus, H);
  H.HandleEvent(Ev);
  Ev := BroadcastEv(cmReleasedFocus, nil);
  H.HandleEvent(Ev);
  Ev := BroadcastEv(cmOK, nil);
  H.HandleEvent(Ev);
  Check((H.RecordCalls = 2) and (HistoryCount(12) = 2), 'other views that give up the focus, and other broadcasts, are not recorded');

  H.MakeWindow := False;
  Line.Data := 'typed';
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a click on the view is taken');
  Check(H.WindowCalls = 1, 'a click asks for a history window');
  Check(RectIs(H.LastArea, 4, 1, 26, 9), 'the area of the window is below the line, one cell wider on each side');
  Check((H.RecordCalls = 3) and (EntryOf(12, 2) = 'typed'), 'a click records the text of the line first');

  Line.SetState(sfFocused, False);
  Check((H.RecordCalls = 4) and (H.LastRecorded = 'typed'),
    'a line that gives up the focus tells its history view through its owner');
  Ev := KeyEv(kbDown);
  H.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (H.WindowCalls = 1), 'the key Down does nothing while the line is not focused');
  Line.SetState(sfFocused, True);
  Check((Line.State and sfFocused) <> 0, 'the line is focused');
  Check(H.RecordCalls = 4, 'a line that gets the focus is not recorded');
  Ev := KeyEv(kbDown);
  H.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (H.WindowCalls = 2), 'the key Down opens the list while the line is focused');
  Ev := KeyEv(kbCtrlX);
  H.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (H.WindowCalls = 3), 'the key Ctrl-X is the key Down');
  Ev := KeyEv(kbUp);
  H.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (H.WindowCalls = 3), 'the key Up does not open the list');

  H2 := TTestHistory.Create(Rc(30, 2, 33, 3), Line, 12);
  H2.ShutDown;
  Check(H2.LinkOf = nil, 'ShutDown lets go of the line');
  Ev := BroadcastEv(cmRecordHistory, nil);
  H2.HandleEvent(Ev);
  Check(H2.RecordCalls = 0, 'a view that has let go of its line records nothing');
  TvObject.DestroyObject(H2);

  H3 := TTestHistory.Create(Rc(30, 2, 33, 3), Line, 300);
  H3.RecordHistory('wrap');
  Check((HistoryCount(44) = 1) and (EntryOf(44, 0) = 'wrap'), 'a history number is cut to one byte');
  TvObject.DestroyObject(H3);
  FreeRoot(Root);

  { The modal loop. }
  ResetHistory;
  HistoryAdd(13, 'first');
  HistoryAdd(13, 'second');
  HistoryAdd(13, 'third');

  MakeScene(Root, Line, H, 13);
  H.MakeWindow := True;
  Line.HelpCtx := 77;
  Line.Data := 'typed';
  Root.AddEvent(KeyEv(kbEnter));
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the click is taken after the window has run');
  Check(H.LastHelp = 77, 'the window has the help context of the line');
  Check(RectIs(H.LastArea, 4, 1, 26, 9), 'the window that runs has the area that was computed');
  Check(Line.Data = 'second', 'Enter takes the focused entry into the line');
  Check((Line.SelStart = 0) and (Line.SelEnd = 6), 'the new text of the line is selected');
  Check((HistoryCount(13) = 4) and (EntryOf(13, 3) = 'typed'), 'the typed text was recorded, the chosen one was not');
  Check(Root.ErrorCount = 0, 'no event was left over');
  FreeRoot(Root);

  MakeScene(Root, Line, H, 13);
  H.MakeWindow := True;
  Line.Data := 'typed2';
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEnter));
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check(Line.Data = 'third', 'the key Down and Enter take the next entry');
  FreeRoot(Root);

  MakeScene(Root, Line, H, 13);
  H.MakeWindow := True;
  Line.Data := 'keep1';
  Root.AddEvent(KeyEv(kbEsc));
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check((Line.Data = 'keep1') and (Ev.What = evNothing), 'Esc leaves the line as it is');
  FreeRoot(Root);

  MakeScene(Root, Line, H, 13);
  H.MakeWindow := True;
  Line.Data := 'keep2';
  Root.AddEvent(CmdEv(cmCancel));
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check(Line.Data = 'keep2', 'the command cmCancel leaves the line as it is');
  FreeRoot(Root);

  MakeScene(Root, Line, H, 13);
  H.MakeWindow := True;
  Line.Data := 'keep3';
  Root.AddEvent(MouseEv(35, 15));
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check(Line.Data = 'keep3', 'a click outside the window leaves the line as it is');
  FreeRoot(Root);

  MakeScene(Root, Line, H, 13);
  H.MakeWindow := True;
  Line.Data := 'keep4';
  Root.AddEvent(DoubleClickEv(10, 5));
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check(Line.Data <> 'keep4', 'a double click on an entry takes it into the line');
  FreeRoot(Root);

  { A chosen text that is longer than the line holds is cut to the limit of the line: 19 bytes. }
  HistoryAdd(14, 'a');
  HistoryAdd(14, 'abcdefghijklmnopqrstuvwxyz');
  MakeScene(Root, Line, H, 14);
  H.MakeWindow := True;
  Line.Data := 'typed3';
  Root.AddEvent(KeyEv(kbEnter));
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check(Line.Data = 'abcdefghijklmnopqrs', 'a chosen text that is longer than the line holds is cut to its limit');
  Check((Line.SelStart = 0) and (Line.SelEnd = 19), 'the cut text is selected');
  FreeRoot(Root);

  { A line that does not give up the focus is not asked for its history. }
  MakeScene(Root, Line, H, 13);
  H.MakeWindow := True;
  Stub := TStubborn.Create(Rc(0, 5, 10, 6));
  Stub.Options := Stub.Options or ofSelectable or ofValidate;
  Root.Insert(Stub);
  Stub.Select;
  Line.Data := 'blocked';
  Ev := MouseEv(26, 2);
  H.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the click is taken when the line cannot be focused');
  Check(H.WindowCalls = 0, 'no window is asked for when the line cannot be focused');
  Check(H.RecordCalls = 0, 'nothing is recorded when the line cannot be focused');
  FreeRoot(Root);
  ResetHistory;
end;

procedure TestThreads;
var
  Root: TRoot;
  W: TTestWindow;
  T: TPoster;
  Start: Int64;
  R: Word;
begin
  ResetHistory;
  HistoryAdd(5, 'alpha');
  HistoryAdd(5, 'beta');
  Root := MakeRoot;
  Root.UseQueue := True;
  Root.Deadline := Now64 + 25000;
  W := TTestWindow.Create(Rc(5, 3, 25, 13), 5);
  T := TPoster.Create(0, 250);
  Start := Now64;
  R := Root.ExecView(W);
  Check(R = cmOK, 'an event that is posted from a second thread during ExecView is delivered');
  Check(Now64 - Start < Guard - 1000, 'the posted event ended the wait');
  Check(Now64 - Start >= 150, 'the loop waited for the posted event');
  T.WaitFor;
  T.Free;
  Check(Root.ErrorCount = 0, 'the posted event was handled');

  TvObject.DestroyObject(W);
  W := TTestWindow.Create(Rc(5, 3, 25, 13), 5);
  WakeFlag := 0;
  T := TPoster.Create(1, 250);
  Start := Now64;
  R := Root.ExecView(W);
  Check(R = cmOK, 'a wake-up from a second thread during ExecView ends the wait');
  Check(Now64 - Start < Guard - 1000, 'the wake-up ended the wait');
  T.WaitFor;
  T.Free;
  TvObject.DestroyObject(W);

  W := TTestWindow.Create(Rc(5, 3, 25, 13), 5);
  T := TPoster.Create(0, 0);
  T.WaitFor;
  T.Free;
  Start := Now64;
  R := Root.ExecView(W);
  Check((R = cmOK) and (Now64 - Start < Guard - 1000), 'an event that was posted before ExecView is delivered at once');
  TvObject.DestroyObject(W);
  FreeRoot(Root);
  ResetHistory;
end;

var
  EventBackend: TEventBackend;
  Queue: TEventQueue;
  SavedBackend: TScreenBackend;

begin
  RootPal := TPalette.Create(#$41#$42#$43#$44#$45#$46#$47#$48#$49#$4A#$4B#$4C#$4D#$4E#$4F#$50 +
    #$51#$52#$53#$54#$55#$56#$57#$58#$59#$5A#$5B#$5C#$5D#$5E#$5F#$60, 32);
  Check((cpHistory = #22#23) and (cpHistoryViewer = #6#6#7#6#6) and (cpHistoryWindow = #19#19#21#24#23#19#20),
    'the palette strings of the history views');
  Fake := TFakeDisplay.Create;
  SavedBackend := TDisplay.Backend;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;
  EventBackend := TEventBackend.Create;
  TEventQueue.Backend := EventBackend;
  Queue := TEventQueue.Create;

  TestHistoryList;
  TestViewer;
  TestWindowParts;
  TestHistoryView;
  TestThreads;

  DoneHistory;
  Queue.Free;
  TEventQueue.Backend := nil;
  EventBackend.Free;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
