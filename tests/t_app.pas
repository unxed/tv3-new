{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/app.h, include/tvision/views.h, source/tvision/tprogram.cpp,
  source/tvision/tapplica.cpp, source/tvision/tbkgrnd.cpp, source/tvision/tdesktop.cpp, source/tvision/syserr.cpp,
  source/tvision/tevent.cpp, include/tvision/util.h, source/tvision/misc.cpp, source/tvision/tvtext2.cpp,
  include/tvision/system.h (TMouse), source/tvision/tmouse.cpp (TMouse::hide, TMouse::show)
  See COPYRIGHT.magiblot.

  The display is a screen of 60 by 20 cells in memory that can grow to 70 by 22; the input is a backend that takes
  its events from Feed and from the posted events of the event queue. Both backends write a journal of the calls
  that the tests look at (a short word for each, ended with a semicolon). The application is a TApplication that
  counts its idle calls, can put an event when a time limit passes or when another thread asks for it, and uses a
  desktop that counts the calls of TileError. The application and the desktop record the messages that they get.
  The window numbers, sizes and colors are chosen so that the expected values can be worked
  out from the C++: the screen is 60 by 20, the menu bar is the row 0, the desktop the rows 1 to 18 and the status
  line the row 19. The color palette of the application gives the attribute $71 to the background, $70 to the
  normal text of the status line and the menu bar and $74 to the shortcut text of the status line. }
program t_app;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Classes, SysUtils, TvGeom, TvKeys, TvEvents, TvSys, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvTimer,
  TvViews, TvWindow, TvMenus, TvApp;

{$I testlib.inc}

const
  ScrW = 60;
  ScrH = 20;
  { No wait of these tests lasts longer than this, so that a failure ends the program. }
  Guard = 4000;

type
  TFakeScreen = class(TScreenBackend)
  public
    Cols, Rows, Mode, CaretSize: Word;
    AllocCount, FreeCount: Integer;
    procedure SetUpConsole; override;
    procedure RestoreConsole; override;
    function GetCaretSize: Word; override;
    procedure SetCaretSize(ASize: Word); override;
    function GetScreenRows: Word; override;
    function GetScreenCols: Word; override;
    function GetScreenMode: Word; override;
    procedure SetScreenMode(AMode: Word); override;
    function AllocateScreenBuffer: PScreenCell; override;
    procedure FreeScreenBuffer(ABuffer: PScreenCell); override;
  end;

  TFakeEvents = class(TEventBackend)
  public
    procedure MouseSuspend; override;
    procedure MouseSetRange(MaxX, MaxY: Integer); override;
    procedure CursorOn; override;
    procedure CursorOff; override;
  end;

  { A desktop that counts the calls of TileError and shows the order of tiling. }
  TTestDesk = class(TDeskTop)
  public
    ErrorCount: Integer;
    procedure HandleEvent(var Event: TEvent); override;
    procedure TileError; override;
    procedure SetColumnsFirst(Value: Boolean);
    function GetColumnsFirst: Boolean;
  end;

  TStatusPeek = class(TStatusLine)
  public
    function FirstItem: TStatusItem;
    function FirstDef: TStatusDef;
  end;

  TTestApp = class(TApplication)
  public
    IdleCount: Integer;
    OutOfMemoryCount: Integer;
    { When it is above zero and passes, Idle puts the command DeadlineCmd. }
    Deadline: Int64;
    DeadlineCmd: Word;
    TileRectSet: Boolean;
    TileRectValue: TRect;
    constructor Create; reintroduce;
    procedure HandleEvent(var Event: TEvent); override;
    procedure Idle; override;
    procedure OutOfMemory; override;
    function GetTileRect: TRect; override;
    function PendingWhat: Word;
    function PendingCommand: Word;
  end;

  { An application without a desktop, a status line and a menu bar. }
  TBareApp = class(TApplication)
  public
    constructor Create; reintroduce;
  end;

  { An application that uses the makers of TProgram. }
  TPlainApp = class(TApplication)
  public
    constructor Create; reintroduce;
  end;

  TTestWin = class(TWindow)
  public
    RejectValid: Boolean;
    RefuseFocus: Boolean;
    destructor Destroy; override;
    function Valid(Command: Word): Boolean; override;
  end;

  { A window that ends its modal loop at cmOK and cmCancel. }
  TModalWin = class(TTestWin)
  public
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { A dialog that keeps a long integer as its data. }
  TDataWin = class(TModalWin)
  public
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    procedure SetData(Rec: Pointer); override;
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

  TWinList = array[1..8] of TTestWin;

var
  ScreenCells: array[0..80 * 25 - 1] of TScreenCell;
  CurW: Integer = ScrW;

  { The fake devices, and the backends they replace }
  Fake: TFakeScreen;
  FakeEvents: TFakeEvents;
  SavedScreen: TScreenBackend;
  SavedEvents: TEventBackend;

  { The record of what the hooks saw }
  Journal: string;
  SelMsgCount, CmdSetMsgCount, TimerMsgCount: Integer;
  SelMsgInfo, CmdSetInfo, LastTimerInfo: Pointer;
  SelMsgTo, CmdSetTo, LastTimerTo: TView;

  { Switches and counters of the test classes }
  WakeFlag: LongInt;
  LowMemFlag: Boolean;
  InitialTimeout: Integer;
  WinDestroyCount: Integer;
  DataSetCalls, DataGetCalls: Integer;
  DataReceived: LongInt;
  BgMakerCalls: Integer;
  BgMakerRect: TRect;

{ The journal and the hooks }

procedure Note(const What: string);
begin
  Journal := Journal + What + ';';
end;

procedure TFakeScreen.SetUpConsole;
begin
  Note('S');
end;

procedure TFakeScreen.RestoreConsole;
begin
  Note('R');
end;

function TFakeScreen.GetCaretSize: Word;
begin
  Result := CaretSize;
end;

procedure TFakeScreen.SetCaretSize(ASize: Word);
begin
  CaretSize := ASize;
end;

function TFakeScreen.GetScreenRows: Word;
begin
  Result := Rows;
end;

function TFakeScreen.GetScreenCols: Word;
begin
  Result := Cols;
end;

function TFakeScreen.GetScreenMode: Word;
begin
  Result := Mode;
end;

procedure TFakeScreen.SetScreenMode(AMode: Word);
begin
  Mode := AMode;
end;

function TFakeScreen.AllocateScreenBuffer: PScreenCell;
begin
  Inc(AllocCount);
  Result := @ScreenCells[0];
end;

procedure TFakeScreen.FreeScreenBuffer(ABuffer: PScreenCell);
begin
  Inc(FreeCount);
end;

procedure TFakeEvents.MouseSuspend;
begin
  Note('mouse-off');
end;

procedure TFakeEvents.MouseSetRange(MaxX, MaxY: Integer);
begin
  Note('mouse-on');
end;

procedure TFakeEvents.CursorOn;
begin
  Note('mw');
end;

procedure TFakeEvents.CursorOff;
begin
  Note('mh');
end;

procedure OnCaret(X, Y: Integer);
begin
end;

procedure OnScreenWrite(X, Y: Integer; Buf: PScreenCell; Count: Integer);
begin
end;

procedure OnCtrlBrk(Install: Boolean);
begin
  if Install then
    Note('c1')
  else
    Note('c0');
end;

procedure OnInitHistory;
begin
  Note('hi');
end;

procedure OnDoneHistory;
begin
  Note('hd');
end;

function OnLowMemory: Boolean;
begin
  Result := LowMemFlag;
end;

function Now64: Int64;
begin
  Result := Int64(GetTickCount64);
end;

{ Small helpers }

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
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

function MouseEv(What: Word; X, Y: Integer; Buttons: Byte): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := What;
  Result.Mouse.Where := Pt(X, Y);
  Result.Mouse.Buttons := Buttons;
end;

function CharAt(X, Y: Integer): Char;
var
  S: string;
begin
  S := ScreenCells[Y * CurW + X].Character.GetText;
  if Length(S) > 0 then
    Result := S[1]
  else
    Result := #0;
end;

function AttrAt(X, Y: Integer): Integer;
begin
  Result := ScreenCells[Y * CurW + X].Attribute.ToBIOS;
end;

procedure ClearScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
end;

function PalByte(P: TPalette; I: Integer): Integer;
var
  A: TColorAttr;
begin
  A := P.Items[I];
  Result := A.ToBIOS;
end;

function BoundsAre(V: TView; AX, AY, BX, BY: Integer): Boolean;
var
  B: TRect;
begin
  B := V.GetBounds;
  Result := (B.A.X = AX) and (B.A.Y = AY) and (B.B.X = BX) and (B.B.Y = BY);
end;

procedure DrainPosted;
var
  Ev: TEvent;
begin
  while TEventQueue.GetPostedEvent(Ev) do
    ;
end;

procedure ResetMessages;
begin
  SelMsgCount := 0;
  SelMsgInfo := nil;
  SelMsgTo := nil;
  CmdSetTo := nil;
  CmdSetInfo := nil;
  TimerMsgCount := 0;
  LastTimerInfo := nil;
  LastTimerTo := nil;
  CmdSetMsgCount := 0;
end;

{ The classes of the tests }

procedure TTestDesk.HandleEvent(var Event: TEvent);
begin
  if Event.What = evBroadcast then
    case Event.Message.Command of
      cmSelectWindowNum:
        begin
          SelMsgCount := SelMsgCount + 1;
          SelMsgTo := Self;
          SelMsgInfo := Event.Message.InfoPtr;
        end;
    end;
  inherited HandleEvent(Event);
end;

procedure TTestDesk.TileError;
begin
  Inc(ErrorCount);
end;

procedure TTestDesk.SetColumnsFirst(Value: Boolean);
begin
  TileColumnsFirst := Value;
end;

function TTestDesk.GetColumnsFirst: Boolean;
begin
  Result := TileColumnsFirst;
end;

function TStatusPeek.FirstItem: TStatusItem;
begin
  Result := Items;
end;

function TStatusPeek.FirstDef: TStatusDef;
begin
  Result := Defs;
end;

function MakeTestDesk(R: TRect): TDeskTop;
begin
  Result := TTestDesk.Create(Rc(R.A.X, R.A.Y + 1, R.B.X, R.B.Y - 1));
end;

function MakeStarBackground(R: TRect): TBackground;
begin
  Inc(BgMakerCalls);
  BgMakerRect := R;
  Result := TBackground.Create(R, '*');
end;

constructor TTestApp.Create;
begin
  inherited Create(@TProgram.InitStatusLine, @TProgram.InitMenuBar, @MakeTestDesk);
  DeadlineCmd := cmCancel;
end;

procedure TTestApp.HandleEvent(var Event: TEvent);
begin
  if Event.What = evBroadcast then
  begin
    if Event.Message.Command = cmTimerExpired then
    begin
      Inc(TimerMsgCount);
      LastTimerInfo := Event.Message.InfoPtr;
      LastTimerTo := Self;
    end
    else if Event.Message.Command = cmCommandSetChanged then
    begin
      Inc(CmdSetMsgCount);
      CmdSetTo := Self;
      CmdSetInfo := Event.Message.InfoPtr;
    end;
  end;
  inherited HandleEvent(Event);
end;

procedure TTestApp.Idle;
var
  Ev: TEvent;
begin
  inherited Idle;
  Inc(IdleCount);
  if InterlockedExchange(WakeFlag, 0) <> 0 then
  begin
    Ev := CmdEv(cmOK);
    PutEvent(Ev);
  end
  else if (Deadline > 0) and (Now64 > Deadline) then
  begin
    Ev := CmdEv(DeadlineCmd);
    PutEvent(Ev);
  end;
end;

procedure TTestApp.OutOfMemory;
begin
  Inc(OutOfMemoryCount);
end;

function TTestApp.GetTileRect: TRect;
begin
  if TileRectSet then
    Result := TileRectValue
  else
    Result := inherited GetTileRect;
end;

function TTestApp.PendingWhat: Word;
begin
  Result := Pending.What;
end;

function TTestApp.PendingCommand: Word;
begin
  Result := Pending.Message.Command;
end;

constructor TBareApp.Create;
begin
  inherited Create(nil, nil, nil);
end;

constructor TPlainApp.Create;
begin
  inherited Create;
end;

destructor TTestWin.Destroy;
begin
  Inc(WinDestroyCount);
  inherited Destroy;
end;

function TTestWin.Valid(Command: Word): Boolean;
begin
  if (Command = cmValid) and RejectValid then
    Result := False
  else if (Command = cmReleasedFocus) and RefuseFocus then
    Result := False
  else
    Result := inherited Valid(Command);
end;

procedure TModalWin.HandleEvent(var Event: TEvent);
var
  Cmd: Word;
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;
  Cmd := Event.Message.Command;
  if (Cmd = cmOK) or (Cmd = cmCancel) then
  begin
    ClearEvent(Event);
    EndModal(Cmd);
  end;
end;

function TDataWin.DataSize: Word;
begin
  Result := SizeOf(LongInt);
end;

procedure TDataWin.GetData(Rec: Pointer);
begin
  Inc(DataGetCalls);
  PLongInt(Rec)^ := 77;
end;

procedure TDataWin.SetData(Rec: Pointer);
begin
  Inc(DataSetCalls);
  DataReceived := PLongInt(Rec)^;
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
        TEventQueue.WakeUp;
      end;
    1:
      begin
        InterlockedExchange(WakeFlag, 1);
        TEventQueue.WakeUp;
      end;
    2:
      begin
        Ev := CmdEv(cmQuit);
        TEventQueue.PostEvent(Ev);
      end;
  end;
end;

function NewApp: TTestApp;
begin
  DrainPosted;
  ClearScreen;
  ResetMessages;
  TView.CommandSetChanged := False;
  EventTimeoutMs := 20;
  Result := TTestApp.Create;
end;

procedure FreeApp(App: TTestApp);
begin
  TvObject.DestroyObject(App);
end;

function NextEvent(App: TTestApp): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  App.GetEvent(Result);
end;

{ Adds Count windows, which are tileable, to the desktop of App; the last one added is the first subview. }
procedure AddWindows(App: TTestApp; Count: Integer; var Wins: TWinList);
var
  K: Integer;
begin
  for K := 1 to Count do
  begin
    Wins[K] := TTestWin.Create(Rc(5, 3, 25, 12), 'Win', K);
    Wins[K].Options := Wins[K].Options or ofTileable;
    App.DeskTop.Insert(Wins[K]);
  end;
end;

{ The tests }

procedure TestSystemError;
var
  Sys: TSystemError;
begin
  Check((not TSystemError.CtrlBreakHit) and (not TSystemError.SaveCtrlBreak), 'the two flags of the system error handler start False');
  SetCtrlBrkHandlerHook := @OnCtrlBrk;
  Journal := '';
  Sys := TSystemError.Create;
  Check(Journal = 'c1;', 'creating the system error handler switches the Ctrl-Break handler on');
  Journal := '';
  TSystemError.Suspend;
  Check(Journal = 'c0;', 'suspend switches the Ctrl-Break handler off');
  Journal := '';
  TSystemError.Resume;
  Check(Journal = 'c1;', 'resume switches the Ctrl-Break handler on');
  Journal := '';
  Sys.Free;
  Check(Journal = 'c0;', 'destroying the system error handler switches the Ctrl-Break handler off');
  SetCtrlBrkHandlerHook := nil;
  Journal := '';
  TSystemError.Resume;
  TSystemError.Suspend;
  Check(Journal = '', 'resume and suspend do nothing while the hook is nil');
  SetCtrlBrkHandlerHook := @OnCtrlBrk;
end;

procedure TestTexts;
begin
  Check(TProgram.ExitText = '~Alt-X~ Exit', 'exitText is the text of the C++');
  Check(TDeskTop.DefaultBkgrnd = #$B0, 'defaultBkgrnd is the character of the C++');
end;

procedure TestConstants;
begin
  Check((hcNew = $FF01) and (hcOpen = $FF02) and (hcSave = $FF03) and (hcSaveAs = $FF04) and (hcSaveAll = $FF05) and
    (hcChangeDir = $FF06) and (hcDosShell = $FF07) and (hcExit = $FF08), 'the help contexts of the file commands');
  Check((hcUndo = $FF10) and (hcCut = $FF11) and (hcCopy = $FF12) and (hcPaste = $FF13) and (hcClear = $FF14),
    'the help contexts of the edit commands');
  Check((hcTile = $FF20) and (hcCascade = $FF21) and (hcCloseAll = $FF22) and (hcResize = $FF23) and
    (hcZoom = $FF24) and (hcNext = $FF25) and (hcPrev = $FF26) and (hcClose = $FF27),
    'the help contexts of the window commands');
  Check((apColor = 0) and (apBlackWhite = 1) and (apMonochrome = 2), 'the numbers of the palettes of the application');
  Check(InitialTimeout = 20, 'the time-out of the wait is 20 ms when the unit starts');
  Check(TProgram.AppPalette = apColor, 'the palette of the application is the color palette when the unit starts');
end;

procedure TestTilingMath;
var
  X, Y: SmallInt;
begin
  Check(ISqr(1) = 1, 'ISqr of 1');
  Check(ISqr(2) = 1, 'ISqr of 2');
  Check(ISqr(4) = 2, 'ISqr of 4');
  Check(ISqr(6) = 2, 'ISqr of 6');
  Check(ISqr(8) = 2, 'ISqr of 8 is the smaller of 3 and 2');
  Check(ISqr(9) = 3, 'ISqr of 9');
  Check(ISqr(10) = 3, 'ISqr of 10');
  Check(ISqr(15) = 3, 'ISqr of 15 is the smaller of 4 and 3');
  Check(ISqr(16) = 4, 'ISqr of 16');
  Check(ISqr(24) = 4, 'ISqr of 24');
  Check(ISqr(100) = 10, 'ISqr of 100');

  MostEqualDivisors(1, X, Y, True);
  Check((X = 1) and (Y = 1), 'one tile makes one column and one row');
  MostEqualDivisors(2, X, Y, True);
  Check((X = 1) and (Y = 2), 'two tiles favor Y');
  MostEqualDivisors(2, X, Y, False);
  Check((X = 2) and (Y = 1), 'two tiles, X favored');
  MostEqualDivisors(3, X, Y, True);
  Check((X = 1) and (Y = 3), 'three tiles favor Y');
  MostEqualDivisors(3, X, Y, False);
  Check((X = 3) and (Y = 1), 'three tiles, X favored');
  MostEqualDivisors(4, X, Y, True);
  Check((X = 2) and (Y = 2), 'four tiles make two columns of two');
  MostEqualDivisors(5, X, Y, True);
  Check((X = 2) and (Y = 2), 'five tiles make two columns and two rows, with one left over');
  MostEqualDivisors(6, X, Y, True);
  Check((X = 2) and (Y = 3), 'six tiles favor Y');
  MostEqualDivisors(6, X, Y, False);
  Check((X = 3) and (Y = 2), 'six tiles, X favored');
  MostEqualDivisors(7, X, Y, True);
  Check((X = 2) and (Y = 3), 'seven tiles use the larger factor 3');
  MostEqualDivisors(9, X, Y, False);
  Check((X = 3) and (Y = 3), 'nine tiles make three by three');
  MostEqualDivisors(12, X, Y, True);
  Check((X = 3) and (Y = 4), 'twelve tiles favor Y');

  Check(DividerLoc(0, 60, 2, 1) = 30, 'half of 60');
  Check(DividerLoc(0, 60, 2, 2) = 60, 'the whole of 60');
  Check(DividerLoc(0, 60, 2, 0) = 0, 'the start of the span');
  Check(DividerLoc(0, 18, 3, 2) = 12, 'two thirds of 18');
  Check(DividerLoc(10, 70, 4, 3) = 55, 'three quarters from 10 to 70');
  Check(DividerLoc(5, 18, 4, 1) = 8, 'a quarter of 13 is 3 and the start is added');
  Check(DividerLoc(0, 10, 3, 1) = 3, 'a third of 10 rounds down');
  Check(DividerLoc(0, -10, 3, 1) = -3, 'a third of -10 rounds towards zero');
  Check(DividerLoc(3, 3, 5, 2) = 3, 'an empty span');
end;

procedure TestBackground;
var
  B: TBackground;
begin
  B := TBackground.Create(Rc(2, 2, 12, 5), '#');
  Check(B.Pattern = '#', 'the pattern of a background');
  Check(B.GrowMode = (gfGrowHiX or gfGrowHiY), 'a background grows with the high corner');
  Check(BoundsAre(B, 2, 2, 12, 5), 'the bounds of a background');
  Check((PalByte(B.GetPalette, 0) = 1) and (PalByte(B.GetPalette, 1) = 1), 'the palette of a background has one entry, 1');
  B.Free;
end;

procedure TestDeskTopParts;
var
  D: TTestDesk;
  Bg: TBackground;
begin
  TDeskTop.DefaultBkgrnd := '.';
  Bg := TDeskTop.InitBackground(Rc(0, 0, 10, 3));
  Check(Bg.Pattern = '.', 'InitBackground uses the default character');
  Check(BoundsAre(Bg, 0, 0, 10, 3), 'InitBackground uses the given bounds');
  Bg.Free;

  D := TTestDesk.Create(Rc(0, 0, 20, 10));
  Check(D.GrowMode = (gfGrowHiX or gfGrowHiY), 'a desktop grows with the high corner');
  Check(not D.GetColumnsFirst, 'a desktop tiles rows first at the start');
  Check((D.Background <> nil) and (D.Background.Pattern = '.'), 'a desktop makes its background with InitBackground');
  Check(BoundsAre(D.Background, 0, 0, 20, 10), 'the background fills the extent of the desktop');
  Check((D.IndexOf(D.Background) = 1) and (D.Owner = nil), 'the background is the only subview');
  D.ShutDown;
  Check(D.Background = nil, 'ShutDown of a desktop clears the background');
  D.Free;

  BgMakerCalls := 0;
  D := TTestDesk.Create(Rc(0, 0, 20, 10), @MakeStarBackground);
  Check(BgMakerCalls = 1, 'a desktop calls the function that makes the background once');
  Check(BoundsAre(D.Background, 0, 0, 20, 10) and (D.Background.Pattern = '*'), 'the function receives the extent of the desktop');
  Check((BgMakerRect.A.X = 0) and (BgMakerRect.A.Y = 0) and (BgMakerRect.B.X = 20) and (BgMakerRect.B.Y = 10),
    'the rectangle that the maker received is the extent');
  TvObject.DestroyObject(D);

  D := TTestDesk.Create(Rc(0, 0, 20, 10), nil);
  Check((D.Background = nil) and (D.First = nil), 'a desktop with no function has no background and no subview');
  TvObject.DestroyObject(D);
end;

procedure TestProgramParts;
var
  D: TDeskTop;
  M: TMenuBar;
  S: TStatusLine;
begin
  D := TProgram.InitDeskTop(Rc(0, 0, 60, 20));
  Check(BoundsAre(D, 0, 1, 60, 19), 'InitDeskTop takes a row off the top and one off the bottom');
  Check((D.Background <> nil) and BoundsAre(D.Background, 0, 0, 60, 18), 'InitDeskTop makes a desktop with a background');
  TvObject.DestroyObject(D);
  M := TProgram.InitMenuBar(Rc(0, 0, 60, 20));
  Check(BoundsAre(M, 0, 0, 60, 1), 'InitMenuBar makes a bar of one row at the top');
  M.Free;
  S := TProgram.InitStatusLine(Rc(0, 0, 60, 20));
  Check(BoundsAre(S, 0, 19, 60, 20), 'InitStatusLine makes a line of one row at the bottom');
  S.Free;
end;

procedure TestConstruction;
var
  App: TTestApp;
  Peek: TStatusPeek;
  Item: TStatusItem;
  Def: TStatusDef;
  P: TPalette;
begin
  Journal := '';
  App := NewApp;
  Check(Journal = 'S;mouse-on;c1;', 'the first application starts the screen, the event queue and the system error handler in this order');
  Check(TProgram.Application = App, 'Application is the application');
  Check((TProgram.DeskTop <> nil) and (TProgram.StatusLine <> nil) and (TProgram.MenuBar <> nil),
    'the desktop, the status line and the menu bar exist');
  Check(BoundsAre(App, 0, 0, ScrW, ScrH), 'the application covers the screen');
  Check(App.State = $A61, 'the state of the application is visible, selected, focused, modal and exposed');
  Check(App.Options = 0, 'the options of the application are empty');
  Check(App.Buffer = @ScreenCells[0], 'the buffer of the application is the screen buffer');
  Check(BoundsAre(TProgram.DeskTop, 0, 1, ScrW, ScrH - 1), 'the bounds of the desktop');
  Check(BoundsAre(TProgram.StatusLine, 0, ScrH - 1, ScrW, ScrH), 'the bounds of the status line');
  Check(BoundsAre(TProgram.MenuBar, 0, 0, ScrW, 1), 'the bounds of the menu bar');
  Check((App.IndexOf(TProgram.MenuBar) = 1) and (App.IndexOf(TProgram.StatusLine) = 2) and
    (App.IndexOf(TProgram.DeskTop) = 3), 'the desktop is inserted first, then the status line, then the menu bar');
  Check((ShadowSize.X = 2) and (ShadowSize.Y = 1) and (not TView.ShowMarkers) and (TProgram.AppPalette = apColor),
    'a color screen gives a shadow of 2 by 1, no markers and the color palette');
  Check(TProgram.DeskTop.GrowMode = $0C, 'the desktop grows with the high corner');

  Check((TProgram.DeskTop.Background <> nil) and (TProgram.DeskTop.Background.Pattern = '.'),
    'the desktop of the application has the background with the default character');
  Check(BoundsAre(TProgram.DeskTop.Background, 0, 0, ScrW, ScrH - 2), 'the background fills the desktop');

  Peek := TStatusPeek(TProgram.StatusLine);
  Def := Peek.FirstDef;
  Check((Def <> nil) and (Def.Min = 0) and (Def.Max = $FFFF) and (Def.Next = nil), 'one status definition for all help contexts');
  Item := Peek.FirstItem;
  Check(Item = Def.Items, 'the status line shows the items of its definition');
  Check((Item.Text <> nil) and (StrPas(Item.Text) = '~Q~uit') and (Item.Command = cmQuit) and
    (Item.KeyCode = TKey.Create(kbAltX)), 'the first status item is the exit item, Alt-X');
  Item := Item.Next;
  Check((Item <> nil) and (Item.Text = nil) and (Item.Command = cmMenu) and (Item.KeyCode = TKey.Create(kbF10)),
    'the second status item has no text, F10, cmMenu');
  Item := Item.Next;
  Check((Item <> nil) and (Item.Text = nil) and (Item.Command = cmClose) and (Item.KeyCode = TKey.Create(kbAltF3)),
    'the third status item has no text, Alt-F3, cmClose');
  Item := Item.Next;
  Check((Item <> nil) and (Item.Text = nil) and (Item.Command = cmZoom) and (Item.KeyCode = TKey.Create(kbF5)),
    'the fourth status item has no text, F5, cmZoom');
  Item := Item.Next;
  Check((Item <> nil) and (Item.Text = nil) and (Item.Command = cmResize) and (Item.KeyCode = TKey.Create(kbCtrlF5)),
    'the fifth status item has no text, Ctrl-F5, cmResize');
  Check((Item <> nil) and (Item.Next = nil), 'the status line has five items');

  App.Redraw;
  Check((CharAt(0, 1) = '.') and (CharAt(ScrW - 1, ScrH - 2) = '.'), 'the background pattern is drawn on the desktop');
  Check(AttrAt(0, 1) = $71, 'the background has the first color of the application palette');
  Check((CharAt(1, ScrH - 1) = 'Q') and (CharAt(2, ScrH - 1) = 'u') and (CharAt(4, ScrH - 1) = 't'), 'the exit item is drawn on the status line');
  Check((AttrAt(1, ScrH - 1) = $74) and (AttrAt(2, ScrH - 1) = $70), 'the exit item has the shortcut color and the normal color');
  Check((CharAt(0, 0) = ' ') and (AttrAt(0, 0) = $70), 'the menu bar is drawn in the normal color');

  P := App.GetPalette;
  Check((PalByte(P, 0) = 135) and (PalByte(P, 1) = $71) and (PalByte(P, 2) = $70) and (PalByte(P, 4) = $74),
    'the first entries of the color palette');
  Check((PalByte(P, 14) = $71) and (PalByte(P, 16) = $37) and (PalByte(P, 22) = $21) and (PalByte(P, 31) = $7E),
    'entries 14 to 31 of the color palette');
  Check((PalByte(P, 128) = $37) and (PalByte(P, 133) = $30) and (PalByte(P, 135) = $1E), 'the last entries of the color palette');

  FreeApp(App);
  Check((TProgram.Application = nil) and (TProgram.DeskTop = nil) and (TProgram.StatusLine = nil) and
    (TProgram.MenuBar = nil), 'ShutDown clears Application, the desktop, the status line and the menu bar');

  Journal := '';
  App := NewApp;
  Check(Journal = '', 'a second application does not start the subsystems again');
  Check(TProgram.Application = App, 'the second application is the application');
  FreeApp(App);
end;

procedure TestPlainAndBare;
var
  Plain: TPlainApp;
  Bare: TBareApp;
begin
  ClearScreen;
  Plain := TPlainApp.Create;
  Check((TProgram.DeskTop <> nil) and (TProgram.StatusLine <> nil) and (TProgram.MenuBar <> nil),
    'a TApplication with no arguments makes the three parts');
  Check(TProgram.DeskTop.ClassType = TDeskTop, 'the default function makes a TDeskTop');
  Check(TProgram.StatusLine.ClassType = TStatusLine, 'the default function makes a TStatusLine');
  Check(TProgram.MenuBar.ClassType = TMenuBar, 'the default function makes a TMenuBar');
  TvObject.DestroyObject(Plain);

  Bare := TBareApp.Create;
  Check((TProgram.Application = Bare) and (TProgram.DeskTop = nil) and (TProgram.StatusLine = nil) and
    (TProgram.MenuBar = nil), 'nil functions make no parts');
  Check(Bare.First = nil, 'an application with no parts has no subview');
  Check(BoundsAre(Bare, 0, 0, ScrW, ScrH), 'an application with no parts still covers the screen');
  TvObject.DestroyObject(Bare);
  Check(TProgram.Application = nil, 'the destroyed application is no longer the application');
end;

procedure TestScreenModes;
var
  App: TTestApp;
  P: TPalette;
  Ev: TEvent;
  AllocBefore, FreeBefore: Integer;
begin
  App := NewApp;
  Journal := '';
  App.SetScreenMode(TDisplay.smBW80);
  Check(Journal = 'mh;mouse-on;mw;', 'SetScreenMode hides the mouse cursor, sets the mode and shows the mouse cursor');
  Check((TProgram.AppPalette = apBlackWhite) and (ShadowSize.X = 2) and (ShadowSize.Y = 1) and (not TView.ShowMarkers),
    'a black and white screen has the black and white palette and a shadow of 2 by 1');
  P := App.GetPalette;
  Check((PalByte(P, 0) = 135) and (PalByte(P, 3) = $78) and (PalByte(P, 4) = $7F) and (PalByte(P, 135) = $70) and
    (PalByte(P, 128) = $07), 'entries of the black and white palette');

  App.SetScreenMode(TDisplay.smMono);
  Check((TProgram.AppPalette = apMonochrome) and (ShadowSize.X = 0) and (ShadowSize.Y = 0) and TView.ShowMarkers,
    'a monochrome screen has the monochrome palette, no shadow and markers');
  P := App.GetPalette;
  Check((PalByte(P, 0) = 135) and (PalByte(P, 2) = $07) and (PalByte(P, 4) = $0F) and (PalByte(P, 15) = $00) and
    (PalByte(P, 129) = $0F), 'entries of the monochrome palette');

  App.SetScreenMode(TDisplay.smCO80 or TDisplay.smFont8x8);
  Check((TProgram.AppPalette = apColor) and (ShadowSize.X = 1) and (ShadowSize.Y = 1) and (not TView.ShowMarkers),
    'a color screen with the 8 by 8 font has a shadow 1 wide');

  App.SetScreenMode(TDisplay.smCO80);
  Check((TProgram.AppPalette = apColor) and (ShadowSize.X = 2), 'the color mode restores the shadow of 2 columns');
  P := App.GetPalette;
  Check((PalByte(P, 4) = $74) and (PalByte(P, 135) = $1E), 'the color palette is back');
  Check(AttrAt(0, 1) = $71, 'the redraw after a change of mode paints the background');

  Fake.Cols := 70;
  Fake.Rows := 22;
  CurW := 70;
  AllocBefore := Fake.AllocCount;
  FreeBefore := Fake.FreeCount;
  Journal := '';
  Ev := CmdEv(cmScreenChanged);
  App.PutEvent(Ev);
  Ev := NextEvent(App);
  Check(Ev.What = evNothing, 'cmScreenChanged is cleared');
  Check((Fake.AllocCount = AllocBefore + 1) and (Fake.FreeCount = FreeBefore + 1),
    'cmScreenChanged gives back the screen buffer and takes a new one');
  Check(Journal = 'mh;mouse-on;mw;', 'cmScreenChanged goes through SetScreenMode');
  Check((App.Size.X = 70) and (App.Size.Y = 22), 'the application takes the new size of the screen');
  Check(BoundsAre(TProgram.DeskTop, 0, 1, 70, 21), 'the desktop grows with the screen');
  Check(BoundsAre(TProgram.StatusLine, 0, 21, 70, 22), 'the status line moves to the new last row');
  Check(BoundsAre(TProgram.MenuBar, 0, 0, 70, 1), 'the menu bar grows in width');
  Check(BoundsAre(TProgram.DeskTop.Background, 0, 0, 70, 20), 'the background grows with the desktop');
  Check(CharAt(69, 20) = '.', 'the background is redrawn on the larger screen');

  Fake.Cols := ScrW;
  Fake.Rows := ScrH;
  CurW := ScrW;
  App.SetScreenMode(TDisplay.smUpdate);
  Check(BoundsAre(App, 0, 0, ScrW, ScrH) and BoundsAre(TProgram.DeskTop, 0, 1, ScrW, ScrH - 1),
    'the update mode takes the size of the screen back');
  FreeApp(App);
end;

procedure TestEventSources;
var
  App: TTestApp;
  Ev: TEvent;
  Idle0: Integer;
  Fed: TEvent;
begin
  App := NewApp;
  Ev := KeyEv(kbEnter);
  App.PutEvent(Ev);
  Check(App.PendingWhat = evKeyDown, 'PutEvent keeps the event');
  Idle0 := App.IdleCount;
  Ev := NextEvent(App);
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbEnter), 'GetEvent returns the event that was put');
  Check(App.PendingWhat = evNothing, 'the pending event is taken');
  Check(App.IdleCount = Idle0, 'GetEvent does not call Idle when it returns the pending event');

  Ev := CmdEv(cmNew);
  TEventQueue.PostEvent(Ev);
  Fed := KeyEv(kbEnter);
  FakeEvents.Feed(Fed);
  Fed := MouseEv(evMouseMove, 7, 5, 0);
  FakeEvents.Feed(Fed);
  Idle0 := App.IdleCount;
  Ev := NextEvent(App);
  Check((Ev.What = evCommand) and (Ev.Message.Command = cmNew), 'a posted event is read before the mouse and the keyboard');
  Check(App.IdleCount = Idle0, 'a posted event does not call Idle');
  Ev := NextEvent(App);
  Check((Ev.What = evMouseMove) and (Ev.Mouse.Where.X = 7) and (Ev.Mouse.Where.Y = 5), 'the mouse is read before the keyboard');
  Check(App.IdleCount = Idle0, 'a mouse event does not call Idle');
  Ev := NextEvent(App);
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbEnter), 'the keyboard is read last');
  Check(App.IdleCount = Idle0, 'a key event does not call Idle');
  Ev := NextEvent(App);
  Check(Ev.What = evNothing, 'with no input GetEvent returns no event');
  Check(App.IdleCount = Idle0 + 1, 'with no input GetEvent calls Idle once');
  FreeApp(App);
end;

procedure TestStatusLineEvents;
var
  App: TTestApp;
  Ev: TEvent;
begin
  App := NewApp;
  Ev := KeyEv(kbAltX);
  App.PutEvent(Ev);
  Ev := NextEvent(App);
  Check((Ev.What = evCommand) and (Ev.Message.Command = cmQuit) and (Ev.Message.InfoPtr = nil),
    'the status line turns Alt-X into the command cmQuit');

  Ev := KeyEv(kbF5);
  App.PutEvent(Ev);
  Ev := NextEvent(App);
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbF5), 'a key of a disabled command stays a key');

  Ev := KeyEv(kbEnter);
  App.PutEvent(Ev);
  Ev := NextEvent(App);
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbEnter), 'a key that no item has stays a key');

  Ev := MouseEv(evMouseDown, 2, 5, mbLeftButton);
  App.PutEvent(Ev);
  Ev := NextEvent(App);
  Check((Ev.What = evMouseDown) and (Ev.Mouse.Where.Y = 5), 'a click on the desktop is not offered to the status line');

  Ev := MouseEv(evMouseDown, 2, ScrH - 1, mbLeftButton);
  TEventQueue.PostEvent(Ev);
  Ev := MouseEv(evMouseUp, 2, ScrH - 1, mbLeftButton);
  TEventQueue.PostEvent(Ev);
  Ev := NextEvent(App);
  Check(Ev.What = evNothing, 'a click on the status line is handled by it');
  Check((App.PendingWhat = evCommand) and (App.PendingCommand = cmQuit), 'a click on the exit item puts the command cmQuit');
  Ev := NextEvent(App);
  Check((Ev.What = evCommand) and (Ev.Message.Command = cmQuit), 'the next GetEvent returns the command that was put');
  Check(App.PendingWhat = evNothing, 'the command that was put is taken');
  FreeApp(App);
end;

procedure TestIdleAndTimers;
var
  App: TTestApp;
  Id, Gone: TTimerId;
begin
  App := NewApp;
  TView.DisableCommand(cmNew);
  Check(TView.CommandSetChanged, 'disabling a command sets the changed flag');
  App.Idle;
  Check((CmdSetMsgCount = 1) and (CmdSetTo = App) and (CmdSetInfo = nil), 'Idle broadcasts cmCommandSetChanged to the application');
  Check(not TView.CommandSetChanged, 'Idle clears the changed flag');
  TView.EnableCommand(cmNew);
  TView.CommandSetChanged := False;
  App.Idle;
  Check(CmdSetMsgCount = 1, 'Idle sends nothing when the command set did not change');

  Id := App.SetTimer(20, -1);
  Sleep(80);
  App.Idle;
  Check(TimerMsgCount = 1, 'an expired timer is broadcast as cmTimerExpired');
  Check((LastTimerInfo = Id) and (LastTimerTo = App), 'the message of a timer carries its id and goes to the application');
  App.Idle;
  Check(TimerMsgCount = 1, 'a timer of one shot expires once');

  Gone := App.SetTimer(30, -1);
  App.KillTimer(Gone);
  Sleep(80);
  App.Idle;
  Check(TimerMsgCount = 1, 'a timer that was killed does not expire');
  FreeApp(App);
end;

procedure TestWaitTimeouts;
var
  App: TTestApp;
  Ev: TEvent;
  Start, Elapsed: Int64;
  Id, GuardId: TTimerId;
begin
  App := NewApp;
  EventTimeoutMs := 60;
  Ev := NextEvent(App);
  Start := Now64;
  Ev := NextEvent(App);
  Elapsed := Now64 - Start;
  Check((Ev.What = evNothing) and (Elapsed >= 40) and (Elapsed < Guard), 'with no timer the wait lasts as long as the time-out');

  EventTimeoutMs := 3000;
  ResetMessages;
  Id := App.SetTimer(50, -1);
  Ev := NextEvent(App);
  Start := Now64;
  while (TimerMsgCount = 0) and (Now64 - Start < 1500) do
    Ev := NextEvent(App);
  Elapsed := Now64 - Start;
  Check((TimerMsgCount = 1) and (Elapsed < 1500), 'a timer that is due before the time-out ends the wait');

  EventTimeoutMs := -1;
  ResetMessages;
  Id := App.SetTimer(50, -1);
  GuardId := App.SetTimer(1500, -1);
  Ev := NextEvent(App);
  Start := Now64;
  while (TimerMsgCount = 0) and (Now64 - Start < 1200) do
    Ev := NextEvent(App);
  Elapsed := Now64 - Start;
  Check((TimerMsgCount = 1) and (Elapsed < 1200), 'with a negative time-out the wait ends at the next timer');
  App.KillTimer(GuardId);
  EventTimeoutMs := 20;
  FreeApp(App);
end;

procedure TestHandleEvent;
var
  App: TTestApp;
  Ev: TEvent;
  W1, W2: TTestWin;
begin
  App := NewApp;
  Ev := CmdEv(cmQuit);
  App.HandleEvent(Ev);
  Check(App.EndState = cmQuit, 'cmQuit ends the modal state of the application');
  Check(Ev.What = evNothing, 'cmQuit is cleared');

  Ev := CmdEv(cmNew);
  App.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (Ev.Message.Command = cmNew), 'a command that nobody handles stays');

  W1 := TTestWin.Create(Rc(2, 2, 30, 10), 'One', 1);
  W2 := TTestWin.Create(Rc(4, 4, 32, 12), 'Two', 2);
  App.DeskTop.Insert(W1);
  App.DeskTop.Insert(W2);
  Check(App.DeskTop.Current = W2, 'the window inserted last is the current one');
  Ev := KeyEv(kbAlt1);
  App.HandleEvent(Ev);
  Check(App.DeskTop.Current = W1, 'Alt-1 selects the window number 1');
  Check(Ev.What = evNothing, 'Alt-1 is cleared when a window answers');
  Check(SelMsgCount = 1, 'the window number is sent as one message');
  Ev := KeyEv(kbAlt2);
  App.HandleEvent(Ev);
  Check(App.DeskTop.Current = W2, 'Alt-2 selects the window number 2');
  Check((SelMsgCount = 2) and (PtrUInt(SelMsgInfo) = 2) and (SelMsgTo = App.DeskTop),
    'the message is a broadcast of cmSelectWindowNum with the number, sent to the desktop');
  Ev := KeyEv(kbAlt9);
  App.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (App.DeskTop.Current = W2), 'Alt-9 stays a key when no window has the number 9');

  W2.Options := W2.Options or ofValidate;
  W2.RefuseFocus := True;
  Ev := KeyEv(kbAlt1);
  App.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'Alt-1 is cleared when the focus cannot move');
  Check(App.DeskTop.Current = W2, 'the focus did not move');
  W2.RefuseFocus := False;
  FreeApp(App);
end;

procedure TestDeskTopEvents;
var
  App: TTestApp;
  Ev: TEvent;
  W1, W2: TTestWin;
  Desk: TDeskTop;
begin
  App := NewApp;
  Desk := App.DeskTop;
  W1 := TTestWin.Create(Rc(2, 2, 30, 10), 'One', 1);
  W2 := TTestWin.Create(Rc(4, 4, 32, 12), 'Two', 2);
  Desk.Insert(W1);
  Desk.Insert(W2);
  Check((Desk.IndexOf(W2) = 1) and (Desk.IndexOf(W1) = 2) and (Desk.IndexOf(Desk.Background) = 3),
    'the last window inserted is the first subview and the background the last');

  Ev := CmdEv(cmNext);
  Desk.HandleEvent(Ev);
  Check(Desk.Current = W1, 'cmNext selects the window behind the current one');
  Check(Ev.What = evNothing, 'cmNext is cleared');
  Check((Desk.IndexOf(W1) = 1) and (Desk.IndexOf(W2) = 2) and (Desk.IndexOf(Desk.Background) = 3),
    'the selected window comes to the front');

  Ev := CmdEv(cmPrev);
  Desk.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'cmPrev is cleared');
  Check((Desk.IndexOf(W2) = 1) and (Desk.IndexOf(W1) = 2) and (Desk.IndexOf(Desk.Background) = 3),
    'cmPrev puts the current window in front of the background');
  Check(Desk.Current = W2, 'the window that is now in front is current');

  W2.Options := W2.Options or ofValidate;
  W2.RefuseFocus := True;
  Ev := CmdEv(cmNext);
  Desk.HandleEvent(Ev);
  Check(Desk.Current = W2, 'cmNext does not move the focus when the current window refuses it');
  Check(Ev.What = evNothing, 'cmNext is cleared when the focus does not move');
  Ev := CmdEv(cmPrev);
  Desk.HandleEvent(Ev);
  Check((Desk.IndexOf(W2) = 1) and (Ev.What = evNothing), 'cmPrev does nothing when the current window refuses the focus');
  W2.RefuseFocus := False;

  Ev := CmdEv(cmNew);
  Desk.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (Ev.Message.Command = cmNew), 'the desktop leaves other commands alone');
  FreeApp(App);
end;

procedure TestCascade;
var
  App: TTestApp;
  Ev: TEvent;
  Wins: TWinList;
  Desk: TTestDesk;
begin
  App := NewApp;
  Desk := TTestDesk(App.DeskTop);
  AddWindows(App, 3, Wins);
  Ev := CmdEv(cmCascade);
  App.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'cmCascade is cleared');
  Check(BoundsAre(Wins[3], 2, 2, 60, 18), 'the first window in the list gets the largest offset');
  Check(BoundsAre(Wins[2], 1, 1, 60, 18), 'the second window is offset by one');
  Check(BoundsAre(Wins[1], 0, 0, 60, 18), 'the last window in the list has no offset');
  Check(Desk.ErrorCount = 0, 'a cascade that fits calls no error');
  Check(Desk.LockFlag = 0, 'the desktop is unlocked after the cascade');
  FreeApp(App);

  App := NewApp;
  Desk := TTestDesk(App.DeskTop);
  AddWindows(App, 3, Wins);
  App.TileRectSet := True;
  App.TileRectValue := Rc(0, 0, 18, 18);
  App.Cascade;
  Check(Desk.ErrorCount = 1, 'a cascade that is too narrow calls TileError');
  Check(BoundsAre(Wins[3], 5, 3, 25, 12) and BoundsAre(Wins[1], 5, 3, 25, 12), 'a cascade that does not fit moves nothing');
  App.TileRectValue := Rc(0, 0, 60, 8);
  App.Cascade;
  Check(Desk.ErrorCount = 2, 'a cascade that is too short calls TileError');
  App.TileRectValue := Rc(0, 0, 40, 10);
  App.Cascade;
  Check(Desk.ErrorCount = 2, 'a cascade into a rectangle that fits calls no error');
  Check(BoundsAre(Wins[3], 2, 2, 40, 10) and BoundsAre(Wins[1], 0, 0, 40, 10), 'the cascade uses the rectangle of GetTileRect');
  FreeApp(App);

  App := NewApp;
  Desk := TTestDesk(App.DeskTop);
  App.Cascade;
  Check(Desk.ErrorCount = 0, 'a cascade of no window calls no error');
  FreeApp(App);
end;

procedure TestTile;
var
  App: TTestApp;
  Ev: TEvent;
  Wins: TWinList;
  Desk: TTestDesk;
begin
  App := NewApp;
  AddWindows(App, 4, Wins);
  Ev := CmdEv(cmTile);
  App.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'cmTile is cleared');
  Check(BoundsAre(Wins[1], 0, 0, 30, 9), 'four windows: the last in the list gets the first place');
  Check(BoundsAre(Wins[2], 0, 9, 30, 18), 'four windows: the second place');
  Check(BoundsAre(Wins[3], 30, 0, 60, 9), 'four windows: the third place');
  Check(BoundsAre(Wins[4], 30, 9, 60, 18), 'four windows: the first in the list gets the last place');
  FreeApp(App);

  App := NewApp;
  AddWindows(App, 3, Wins);
  App.Tile;
  Check(BoundsAre(Wins[1], 0, 0, 60, 6) and BoundsAre(Wins[2], 0, 6, 60, 12) and BoundsAre(Wins[3], 0, 12, 60, 18),
    'three windows make three rows');
  FreeApp(App);

  App := NewApp;
  AddWindows(App, 5, Wins);
  App.Tile;
  Check(BoundsAre(Wins[1], 0, 0, 30, 9) and BoundsAre(Wins[2], 0, 9, 30, 18), 'five windows: the full column on the left');
  Check(BoundsAre(Wins[3], 30, 0, 60, 6) and BoundsAre(Wins[4], 30, 6, 60, 12) and BoundsAre(Wins[5], 30, 12, 60, 18),
    'five windows: the column with one more row on the right');
  FreeApp(App);

  App := NewApp;
  AddWindows(App, 6, Wins);
  App.Tile;
  Check(BoundsAre(Wins[1], 0, 0, 30, 6) and BoundsAre(Wins[3], 0, 12, 30, 18) and BoundsAre(Wins[4], 30, 0, 60, 6) and
    BoundsAre(Wins[6], 30, 12, 60, 18), 'six windows make two columns of three rows');
  FreeApp(App);

  App := NewApp;
  Desk := TTestDesk(App.DeskTop);
  Desk.SetColumnsFirst(True);
  AddWindows(App, 6, Wins);
  App.Tile;
  Check(BoundsAre(Wins[1], 0, 0, 20, 9) and BoundsAre(Wins[2], 0, 9, 20, 18) and BoundsAre(Wins[3], 20, 0, 40, 9) and
    BoundsAre(Wins[6], 40, 9, 60, 18), 'six windows tiled with the columns first make three columns of two rows');
  Check(Desk.ErrorCount = 0, 'tiling that fits calls no error');
  Check(Desk.LockFlag = 0, 'the desktop is unlocked after the tiling');
  FreeApp(App);

  App := NewApp;
  Desk := TTestDesk(App.DeskTop);
  AddWindows(App, 4, Wins);
  App.TileRectSet := True;
  App.TileRectValue := Rc(0, 0, 1, 18);
  App.Tile;
  Check(Desk.ErrorCount = 1, 'tiling into a rectangle that is too narrow calls TileError');
  Check(BoundsAre(Wins[1], 5, 3, 25, 12) and BoundsAre(Wins[4], 5, 3, 25, 12), 'tiling that does not fit moves nothing');
  App.TileRectValue := Rc(0, 0, 60, 1);
  App.Tile;
  Check(Desk.ErrorCount = 2, 'tiling into a rectangle that is too short calls TileError');
  FreeApp(App);

  App := NewApp;
  AddWindows(App, 4, Wins);
  Wins[2].Hide;
  Wins[3].Options := Wins[3].Options and not ofTileable;
  App.Tile;
  Check(BoundsAre(Wins[1], 0, 0, 60, 9) and BoundsAre(Wins[4], 0, 9, 60, 18), 'only the visible tileable windows are tiled');
  Check(BoundsAre(Wins[2], 5, 3, 25, 12) and BoundsAre(Wins[3], 5, 3, 25, 12), 'a hidden window and a window that is not tileable stay');
  FreeApp(App);

  App := NewApp;
  Desk := TTestDesk(App.DeskTop);
  App.Tile;
  Check(Desk.ErrorCount = 0, 'tiling of no window calls no error');
  FreeApp(App);
end;

procedure TestValidView;
var
  App: TTestApp;
  W: TTestWin;
  Before: Integer;
begin
  App := NewApp;
  Check(App.ValidView(nil) = nil, 'ValidView of nil is nil');

  Before := WinDestroyCount;
  W := TTestWin.Create(Rc(2, 2, 30, 10), 'One', 1);
  Check(App.ValidView(W) = W, 'ValidView returns a valid view');
  Check(WinDestroyCount = Before, 'a valid view is not destroyed');
  TvObject.DestroyObject(W);

  Before := WinDestroyCount;
  W := TTestWin.Create(Rc(2, 2, 30, 10), 'One', 1);
  W.RejectValid := True;
  Check(App.ValidView(W) = nil, 'ValidView of a view that is not valid is nil');
  Check(WinDestroyCount = Before + 1, 'a view that is not valid is destroyed');
  Check(App.OutOfMemoryCount = 0, 'a view that is not valid is no out of memory');

  LowMemoryHook := @OnLowMemory;
  LowMemFlag := False;
  Before := WinDestroyCount;
  W := TTestWin.Create(Rc(2, 2, 30, 10), 'One', 1);
  Check(App.ValidView(W) = W, 'ValidView with the memory not low returns the view');
  TvObject.DestroyObject(W);
  LowMemFlag := True;
  Before := WinDestroyCount;
  W := TTestWin.Create(Rc(2, 2, 30, 10), 'One', 1);
  Check(App.ValidView(W) = nil, 'ValidView with low memory is nil');
  Check(WinDestroyCount = Before + 1, 'ValidView with low memory destroys the view');
  Check(App.OutOfMemoryCount = 1, 'ValidView with low memory calls OutOfMemory');
  LowMemFlag := False;
  LowMemoryHook := nil;
  FreeApp(App);
end;

procedure TestInsertWindow;
var
  App: TTestApp;
  W, Current: TTestWin;
  Before: Integer;
begin
  App := NewApp;
  Check(App.InsertWindow(nil) = nil, 'InsertWindow of nil is nil');

  W := TTestWin.Create(Rc(2, 2, 30, 10), 'One', 1);
  Check(App.InsertWindow(W) = W, 'InsertWindow returns the window');
  Check((W.Owner = App.DeskTop) and (App.DeskTop.IndexOf(W) = 1), 'the window is inserted into the desktop');
  Current := W;

  Before := WinDestroyCount;
  W := TTestWin.Create(Rc(3, 3, 31, 11), 'Two', 2);
  W.RejectValid := True;
  Check(App.InsertWindow(W) = nil, 'InsertWindow of a window that is not valid is nil');
  Check(WinDestroyCount = Before + 1, 'a window that is not valid is destroyed');

  Current.Options := Current.Options or ofValidate;
  Current.RefuseFocus := True;
  Check(not App.CanMoveFocus, 'the focus cannot move when the current window refuses it');
  Before := WinDestroyCount;
  W := TTestWin.Create(Rc(3, 3, 31, 11), 'Two', 2);
  Check(App.InsertWindow(W) = nil, 'InsertWindow is nil when the focus cannot move');
  Check(WinDestroyCount = Before + 1, 'the window is destroyed when the focus cannot move');
  Check(App.DeskTop.IndexOf(Current) = 1, 'the desktop is as it was');
  Current.RefuseFocus := False;
  Check(App.CanMoveFocus, 'the focus can move when the current window accepts it');
  FreeApp(App);
end;

procedure TestExecuteDialog;
var
  App: TTestApp;
  D: TDataWin;
  Ev: TEvent;
  Rec: LongInt;
  R: Word;
  Before: Integer;
begin
  App := NewApp;
  Check(App.ExecuteDialog(nil) = cmCancel, 'ExecuteDialog of nil answers cmCancel');

  Rec := 5;
  DataSetCalls := 0;
  DataGetCalls := 0;
  Before := WinDestroyCount;
  D := TDataWin.Create(Rc(5, 3, 25, 12), 'Dialog', 1);
  Ev := CmdEv(cmOK);
  TEventQueue.PostEvent(Ev);
  R := App.ExecuteDialog(D, @Rec);
  Check(R = cmOK, 'ExecuteDialog answers the command that ended the dialog');
  Check((DataSetCalls = 1) and (DataReceived = 5), 'the data is given to the dialog before it runs');
  Check((DataGetCalls = 1) and (Rec = 77), 'the data is taken from the dialog when it ends with another command than cmCancel');
  Check(WinDestroyCount = Before + 1, 'the dialog is destroyed');

  Rec := 5;
  DataSetCalls := 0;
  DataGetCalls := 0;
  D := TDataWin.Create(Rc(5, 3, 25, 12), 'Dialog', 1);
  Ev := CmdEv(cmCancel);
  TEventQueue.PostEvent(Ev);
  R := App.ExecuteDialog(D, @Rec);
  Check(R = cmCancel, 'ExecuteDialog answers cmCancel when the dialog is cancelled');
  Check((DataSetCalls = 1) and (DataGetCalls = 0) and (Rec = 5), 'the data is not taken from a cancelled dialog');

  DataSetCalls := 0;
  DataGetCalls := 0;
  D := TDataWin.Create(Rc(5, 3, 25, 12), 'Dialog', 1);
  Ev := CmdEv(cmOK);
  TEventQueue.PostEvent(Ev);
  R := App.ExecuteDialog(D);
  Check((R = cmOK) and (DataSetCalls = 0) and (DataGetCalls = 0), 'a dialog with no data record neither gets nor gives data');

  Before := WinDestroyCount;
  D := TDataWin.Create(Rc(5, 3, 25, 12), 'Dialog', 1);
  D.RejectValid := True;
  R := App.ExecuteDialog(D, @Rec);
  Check(R = cmCancel, 'ExecuteDialog of a dialog that is not valid answers cmCancel');
  Check(WinDestroyCount = Before + 1, 'a dialog that is not valid is destroyed');
  FreeApp(App);
end;

procedure TestSuspendResume;
var
  App: TTestApp;
begin
  App := NewApp;
  Journal := '';
  App.Suspend;
  Check(Journal = 'c0;mouse-off;R;', 'suspend stops the system error handler, then the event queue, then the screen');
  Journal := '';
  App.Resume;
  Check(Journal = 'S;mouse-on;c1;', 'resume starts the screen, then the event queue, then the system error handler');
  FreeApp(App);
end;

procedure TestHooksOfHistory;
var
  App: TTestApp;
begin
  InitHistoryHook := @OnInitHistory;
  DoneHistoryHook := @OnDoneHistory;
  Journal := '';
  App := NewApp;
  Check(Journal = 'hi;', 'the constructor of an application calls the hook of initHistory');
  Journal := '';
  FreeApp(App);
  Check(Journal = 'hd;', 'the destructor of an application calls the hook of doneHistory');
  InitHistoryHook := nil;
  DoneHistoryHook := nil;
end;

{ The tests of the threads: an event that another thread posts, or a wake-up, reaches the loop of a modal view. }

procedure PrepareWait(App: TTestApp; TimeoutMs: Integer; out GuardId: TTimerId);
begin
  EventTimeoutMs := TimeoutMs;
  App.Deadline := Now64 + Guard - 300;
  App.DeadlineCmd := cmCancel;
  ResetMessages;
  GuardId := App.SetTimer(Guard, -1);
end;

procedure EndWait(App: TTestApp; GuardId: TTimerId);
begin
  App.Deadline := 0;
  if TimerMsgCount = 0 then
    App.KillTimer(GuardId);
  EventTimeoutMs := 20;
end;

procedure TestThreads;
var
  App: TTestApp;
  W: TModalWin;
  T: TPoster;
  Start, Elapsed: Int64;
  R: Word;
  GuardId: TTimerId;
begin
  App := NewApp;

  W := TModalWin.Create(Rc(5, 3, 25, 13), 'Modal', 1);
  PrepareWait(App, -1, GuardId);
  T := TPoster.Create(0, 250);
  Start := Now64;
  R := App.DeskTop.ExecView(W);
  Elapsed := Now64 - Start;
  T.WaitFor;
  T.Free;
  EndWait(App, GuardId);
  Check(R = cmOK, 'an event that is posted from a second thread during ExecView on the desktop is delivered');
  Check(Elapsed < Guard - 500, 'the posted event ended the wait before the time-out');
  Check(Elapsed >= 150, 'the loop waited for the posted event');
  TvObject.DestroyObject(W);

  W := TModalWin.Create(Rc(5, 3, 25, 13), 'Modal', 1);
  WakeFlag := 0;
  PrepareWait(App, -1, GuardId);
  T := TPoster.Create(1, 250);
  Start := Now64;
  R := App.DeskTop.ExecView(W);
  Elapsed := Now64 - Start;
  T.WaitFor;
  T.Free;
  EndWait(App, GuardId);
  Check(R = cmOK, 'a wake-up from a second thread during ExecView on the desktop ends the wait');
  Check((Elapsed < Guard - 500) and (Elapsed >= 150), 'the wake-up ended the unlimited wait');
  TvObject.DestroyObject(W);

  W := TModalWin.Create(Rc(5, 3, 25, 13), 'Modal', 1);
  PrepareWait(App, 20, GuardId);
  T := TPoster.Create(0, 250);
  Start := Now64;
  R := App.DeskTop.ExecView(W);
  Elapsed := Now64 - Start;
  T.WaitFor;
  T.Free;
  EndWait(App, GuardId);
  Check((R = cmOK) and (Elapsed < Guard - 500) and (Elapsed >= 150),
    'an event that is posted from a second thread is delivered when the wait has a time-out of 20 ms');

  W := TModalWin.Create(Rc(5, 3, 25, 13), 'Modal', 1);
  PrepareWait(App, -1, GuardId);
  T := TPoster.Create(0, 0);
  T.WaitFor;
  T.Free;
  Start := Now64;
  R := App.DeskTop.ExecView(W);
  Elapsed := Now64 - Start;
  EndWait(App, GuardId);
  Check((R = cmOK) and (Elapsed < 1000), 'an event that was posted before ExecView is delivered at once');
  TvObject.DestroyObject(W);

  W := TModalWin.Create(Rc(5, 3, 25, 13), 'Modal', 1);
  PrepareWait(App, -1, GuardId);
  T := TPoster.Create(0, 250);
  Start := Now64;
  R := App.ExecView(W);
  Elapsed := Now64 - Start;
  T.WaitFor;
  T.Free;
  EndWait(App, GuardId);
  Check(R = cmOK, 'an event that is posted from a second thread during ExecView on the application is delivered');
  Check((Elapsed < Guard - 500) and (Elapsed >= 150), 'the loop of ExecView on the application waited for the posted event');
  TvObject.DestroyObject(W);

  PrepareWait(App, -1, GuardId);
  App.DeadlineCmd := cmQuit;
  T := TPoster.Create(2, 250);
  Start := Now64;
  App.Run;
  Elapsed := Now64 - Start;
  T.WaitFor;
  T.Free;
  EndWait(App, GuardId);
  Check(App.EndState = cmQuit, 'Run ends when cmQuit is posted from a second thread');
  Check((Elapsed < Guard - 500) and (Elapsed >= 150), 'the loop of Run waited for the posted event');
  Check(App.IdleCount > 0, 'the loops called Idle');
  FreeApp(App);
end;

procedure TestShutdown;
begin
  Journal := '';
  TAppInit.Shutdown;
  Check(Journal = 'c0;mouse-off;R;', 'the subsystems end in the reverse order of their start');
  Journal := '';
  TAppInit.Shutdown;
  Check(Journal = '', 'ending the subsystems again does nothing');
end;

begin
  InitialTimeout := EventTimeoutMs;
  Fake := TFakeScreen.Create;
  Fake.Cols := ScrW;
  Fake.Rows := ScrH;
  Fake.Mode := TDisplay.smCO80;
  SavedScreen := TDisplay.Backend;
  TDisplay.Backend := Fake;
  FakeEvents := TFakeEvents.Create;
  SavedEvents := TEventQueue.Backend;
  TEventQueue.Backend := FakeEvents;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;
  TestTexts;
  { The checks of the drawing below read a plain character and a short exit text. }
  TDeskTop.DefaultBkgrnd := '.';
  TProgram.ExitText := '~Q~uit';

  TestSystemError;
  TestConstants;
  TestTilingMath;
  TestBackground;
  TestDeskTopParts;
  TestProgramParts;
  TestConstruction;
  TestPlainAndBare;
  TestScreenModes;
  TestEventSources;
  TestStatusLineEvents;
  TestIdleAndTimers;
  TestWaitTimeouts;
  TestHandleEvent;
  TestDeskTopEvents;
  TestCascade;
  TestTile;
  TestValidView;
  TestInsertWindow;
  TestExecuteDialog;
  TestSuspendResume;
  TestHooksOfHistory;
  TestThreads;
  TestShutdown;

  SetCtrlBrkHandlerHook := nil;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TEventQueue.Backend := SavedEvents;
  FakeEvents.Free;
  TDisplay.Backend := SavedScreen;
  Fake.Free;
  Done;
end.
