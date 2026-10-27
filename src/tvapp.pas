{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/app.h, include/tvision/views.h, source/tvision/tprogram.cpp,
  source/tvision/tapplica.cpp, source/tvision/tbkgrnd.cpp, source/tvision/tdesktop.cpp, source/tvision/syserr.cpp,
  source/tvision/tevent.cpp
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only. The thread-safe surface of the program is the
  event queue (PostEvent, WakeUp) and the timers; nothing else of this unit may be called from another thread.
  GetEvent of TProgram is the one place where the loops of the views wait: it reaches WaitForEvents of
  TEventQueue, so a posted event or a wake-up reaches the innermost loop, nested modal loops included. After the
  wait the sources are read in this order: the events that were posted, the mouse, the keyboard. A posted event
  is read before the mouse so that a stream of input cannot hold it back. Idle runs only when none of them gave
  an event.

  Only the branch of the files for the flat memory model is translated. Of syserr.cpp that is the constructor,
  the destructor, resume and suspend of TSystemError and its two flags; the members for DOS (sysErr, selectKey,
  the critical error handler, Int11trap, the DPMI set-up) are left out. The members of TEvent that read events
  (getMouseEvent, getKeyEvent) are the class procedures of TEventQueue of TvSys, which TProgram calls.

  Parts of the C++ that have no unit yet, or that no input defines, are reached through hooks, which do nothing
  while they are nil:
    - message() sends a message to a view; MessageHook of TvViews stands for it;
    - lowMemory() is LowMemoryHook; while it is nil, memory is never low;
    - TMouse::hide and TMouse::show are MouseHideHook and MouseShowHook;
    - initHistory and doneHistory are InitHistoryHook and DoneHistoryHook;
    - THardwareInfo::setCtrlBrkHandler is SetCtrlBrkHandlerHook;
    - TProgram::application is given to TvMenus through its ApplicationHook when this unit starts.
  The construction of THardwareInfo and of TMouse in TAppInit has no counterpart: the program sets the backends
  of TvScreen and TvSys instead.

  The text of TProgram::exitText and the character TDeskTop::defaultBkgrnd are defined in files that are not
  among the sources of this unit. They are the variables ExitText and DefaultBkgrnd, which the program sets before
  it creates the application; they start empty and as the character 0.

  A Pascal class has one parent, so a class that the C++ inherits virtually beside TGroup is the class between
  TGroup and the class that uses it: TDeskInit between TGroup and TDeskTop, and TProgInit between TGroup and
  TProgram. They hold the functions that make the parts. TAppInit, which the C++ inherits virtually by
  TApplication, is a class of its own that a TApplication holds and creates before it constructs its base.
  TProgram has a constructor without arguments, which uses the static functions initStatusLine, initMenuBar and
  initDeskTop, and a constructor that takes the three functions; TDeskTop and TApplication do likewise. In the
  constructor of TProgram, initScreen is called as the TProgram version, as in the C++ while a constructor runs.

  The parameter of ExecuteDialog is a TWindow, the nearest ancestor of TDialog that exists; the routine uses only
  members of TView. The status items with no text (null in the C++) keep a nil text. }
unit TvApp;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvSys, TvScreen, TvTimer, TvViews, TvWindow, TvMenus;

const
  { Standard application help contexts }
  hcNew = Word($FF01);
  hcOpen = Word($FF02);
  hcSave = Word($FF03);
  hcSaveAs = Word($FF04);
  hcSaveAll = Word($FF05);
  hcChangeDir = Word($FF06);
  hcDosShell = Word($FF07);
  hcExit = Word($FF08);

  hcUndo = Word($FF10);
  hcCut = Word($FF11);
  hcCopy = Word($FF12);
  hcPaste = Word($FF13);
  hcClear = Word($FF14);

  hcTile = Word($FF20);
  hcCascade = Word($FF21);
  hcCloseAll = Word($FF22);
  hcResize = Word($FF23);
  hcZoom = Word($FF24);
  hcNext = Word($FF25);
  hcPrev = Word($FF26);
  hcClose = Word($FF27);

  { The palettes of the application }
  apColor = 0;
  apBlackWhite = 1;
  apMonochrome = 2;

type
  TBackground = class;
  TDeskTop = class;

  { A procedure or a function without arguments, for the hooks. }
  TVoidProc = procedure;
  TLowMemoryFunc = function: Boolean;
  { Switches the handler of Ctrl-Break on (Install is True) or off. }
  TSetCtrlBrkHandlerProc = procedure(Install: Boolean);

  { The background of the desktop: the pattern repeated over the whole view. The palette has one entry. }
  TBackground = class(TView)
  public
    Pattern: Char;
    constructor Create(const Bounds: TRect; APattern: Char); reintroduce;
    procedure Draw; override;
    function GetPalette: TPalette; override;
  end;

  TCreateBackgroundFunc = function(R: TRect): TBackground;

  { Holds the function that makes the background of a desktop. }
  TDeskInit = class(TGroup)
  protected
    CreateBackground: TCreateBackgroundFunc;
  public
    constructor Create(const Bounds: TRect; BackgroundMaker: TCreateBackgroundFunc); reintroduce;
  end;

  TDeskTop = class(TDeskInit)
  private
    procedure Setup;
  protected
    TileColumnsFirst: Boolean;
  public
    Background: TBackground;
    { The character of the background that InitBackground uses. }
    class var DefaultBkgrnd: Char;
    constructor Create(const Bounds: TRect); reintroduce; overload;
    { As the first constructor, with BackgroundMaker as the function that makes the background. }
    constructor Create(const Bounds: TRect; BackgroundMaker: TCreateBackgroundFunc); reintroduce; overload;
    procedure Cascade(const R: TRect);
    procedure HandleEvent(var Event: TEvent); override;
    class function InitBackground(R: TRect): TBackground; static;
    procedure Tile(const R: TRect);
    procedure TileError; virtual;
    procedure ShutDown; override;
  end;

  TCreateStatusLineFunc = function(R: TRect): TStatusLine;
  TCreateMenuBarFunc = function(R: TRect): TMenuBar;
  TCreateDeskTopFunc = function(R: TRect): TDeskTop;

  { Holds the functions that make the status line, the menu bar and the desktop of a program. }
  TProgInit = class(TGroup)
  protected
    CreateStatusLine: TCreateStatusLineFunc;
    CreateMenuBar: TCreateMenuBarFunc;
    CreateDeskTop: TCreateDeskTopFunc;
  public
    constructor Create(const Bounds: TRect; StatusLineMaker: TCreateStatusLineFunc;
      MenuBarMaker: TCreateMenuBarFunc; DeskTopMaker: TCreateDeskTopFunc); reintroduce;
  end;

  { The palette of a program is: 1 = TBackground, 2 to 7 = TMenuView and TStatusLine, 8 to 15 = TWindow (blue),
    16 to 23 = TWindow (cyan), 24 to 31 = TWindow (gray), 32 to 63 = TDialog (gray), 64 to 95 = TDialog (blue),
    96 to 127 = TDialog (cyan), 128 to 135 = THelpWindow. }
  TProgram = class(TProgInit)
  private
    class var TimerQueue: TTimerQueue;
    class function EventWaitTimeout: Integer; static;
    procedure ReadScreenMode;
    procedure Assemble;
    procedure ReadNextEvent(var Event: TEvent);
    procedure OfferToStatusLine(var Event: TEvent);
    procedure SelectWindowByAltKey(var Event: TEvent);
  protected
    class var Pending: TEvent;
  public
    class var StatusLine: TStatusLine;
    class var MenuBar: TMenuBar;
    class var DeskTop: TDeskTop;
    class var Application: TProgram;
    class var AppPalette: Integer;
    { The text of the exit item of the status line that InitStatusLine makes. }
    class var ExitText: string;

    constructor Create; reintroduce; overload;
    { As the first constructor, with the given functions in place of initStatusLine, initMenuBar and initDeskTop. }
    constructor Create(StatusLineMaker: TCreateStatusLineFunc; MenuBarMaker: TCreateMenuBarFunc;
      DeskTopMaker: TCreateDeskTopFunc); reintroduce; overload;
    destructor Destroy; override;
    function CanMoveFocus: Boolean; virtual;
    function ExecuteDialog(Dialog: TWindow; Data: Pointer = nil): Word; virtual;
    procedure GetEvent(var Event: TEvent); override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure Idle; virtual;
    procedure InitScreen; virtual;
    procedure OutOfMemory; virtual;
    procedure PutEvent(var Event: TEvent); override;
    procedure Run; virtual;
    function InsertWindow(Win: TWindow): TWindow; virtual;
    procedure SetScreenMode(Mode: Word);
    function ValidView(P: TView): TView;
    procedure ShutDown; override;
    function SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer = -1): TTimerId; override;
    procedure KillTimer(Id: TTimerId); override;
    procedure Suspend; virtual;
    procedure Resume; virtual;
    class function InitStatusLine(R: TRect): TStatusLine; static;
    class function InitMenuBar(R: TRect): TMenuBar; static;
    class function InitDeskTop(R: TRect): TDeskTop; static;
  end;

  { The system error handler. In the flat branch it switches the handler of Ctrl-Break. }
  TSystemError = class
  public
    class var CtrlBreakHit: Boolean;
    class var SaveCtrlBreak: Boolean;
    constructor Create;
    destructor Destroy; override;
    class procedure Resume; static;
    class procedure Suspend; static;
  end;

  { Starts the subsystems that an application needs, once for the whole run: the screen, the event queue and
    the system error handler. }
  TAppInit = class
  private
    class var SharedScreen: TScreen;
    class var SharedQueue: TEventQueue;
    class var SharedSysErr: TSystemError;
  public
    constructor Create;
    { Ends the subsystems, in the reverse order of their start. }
    class procedure Shutdown; static;
  end;

  TApplication = class(TProgram)
  private
    Subsystems: TAppInit;
  protected
    constructor Create; reintroduce; overload;
    constructor Create(StatusLineMaker: TCreateStatusLineFunc; MenuBarMaker: TCreateMenuBarFunc;
      DeskTopMaker: TCreateDeskTopFunc); reintroduce; overload;
  public
    destructor Destroy; override;
    procedure Suspend; override;
    procedure Resume; override;
    procedure Cascade;
    procedure DosShell;
    function GetTileRect: TRect; virtual;
    procedure HandleEvent(var Event: TEvent); override;
    procedure Tile;
    procedure WriteShellMsg; virtual;
  end;

var
  LowMemoryHook: TLowMemoryFunc;
  MouseHideHook: TVoidProc;
  MouseShowHook: TVoidProc;
  InitHistoryHook: TVoidProc;
  DoneHistoryHook: TVoidProc;
  SetCtrlBrkHandlerHook: TSetCtrlBrkHandlerProc;

{ The integer square root that tiling uses: the smaller of two estimates that differ by at most one. }
function ISqr(Value: SmallInt): SmallInt;

{ Splits N into two factors that are as equal as possible. X is the larger factor when FavorY is False, and Y is
  the larger one when it is True. }
procedure MostEqualDivisors(N: SmallInt; var X, Y: SmallInt; FavorY: Boolean);

{ The position Pos of Num equal steps from Lo to Hi, rounded towards zero. }
function DividerLoc(Lo, Hi, Num, Pos: Integer): Integer;

implementation

uses
  {$IFDEF MSWINDOWS}SysUtils,{$ELSE}BaseUnix,{$ENDIF}
  TvObjs, TvColors, TvDrawBuf, TvKeys, TvUtil;

const
  { The three palettes of the application, two hexadecimal digits for each entry. }
  AppColorHexLow =
    '71707874202824171F1A31311E711F' +
    '373F3A13133E213F707F7A1313707F7E' +
    '707F7A131370707F7E202B2F782E7030' +
    '3F3E1F2F1A20723131302F3E31133800';
  AppColorHexHigh =
    '171F1A71711E171F1E202B2F782E1030' +
    '3F3E702F7A20123131302F3E31133800' +
    '373F3A13133E303F3E202B2F782E3070' +
    '7F7E1F2F1A20323171702F7E71137800' +
    '373F3A1313303E1E';

  AppBlackWhiteHexLow =
    '7070787F07070F070F07707007700F' +
    '070F07707007700F707F7F700770070F' +
    '707F7F700770707F7F070F0F780F7807' +
    '0F0F0F700F0770707007700F07070800';
  AppBlackWhiteHexHigh =
    '070F0F077007070F0F70787F087F0870' +
    '7F7F7F0F707007707070077F70077800' +
    '707F7F700770707F7F070F0F780F7807' +
    '0F0F0F700F0770707007700F07070800' +
    '070F077070070F70';

  AppMonochromeHexLow =
    '7007070F707070070F077070077000' +
    '070F0770700770007070700707700700' +
    '70707007077070700F07070F700F7007' +
    '0F0F0770070770070707700F07077000';
  AppMonochromeHexHigh =
    '70707007077070700F07070F700F7007' +
    '0F0F0770070770070707700F07070100' +
    '70707007077070700F07070F700F7007' +
    '0F0F0770070770070707700F07070100' +
    '070F077070070F70';

type
  PRect = ^TRect;
  PEvent = ^TEvent;

var
  BackgroundPalette: TPalette;
  AppPalettes: array[0..2] of TPalette;

  { The state that the callbacks of the desktop share. }
  CascadeCount: SmallInt;
  LastTileable: TView;
  ColumnCount, RowCount, TileableCount, LeftOverCount, TileIndex: SmallInt;

function HexDigitValue(Digit: Char): Integer;
begin
  if (Digit >= '0') and (Digit <= '9') then
    Result := Ord(Digit) - Ord('0')
  else
    Result := Ord(UpCase(Digit)) - Ord('A') + 10;
end;

{ Turns pairs of hexadecimal digits into the characters they stand for. }
function DecodeHex(const Digits: string): string;
var
  Index, UpperNibble, LowerNibble: Integer;
begin
  SetLength(Result, Length(Digits) div 2);
  for Index := 1 to Length(Result) do
  begin
    UpperNibble := HexDigitValue(Digits[Index * 2 - 1]);
    LowerNibble := HexDigitValue(Digits[Index * 2]);
    Result[Index] := Chr(UpperNibble * 16 + LowerNibble);
  end;
end;

{ Makes a palette from two parts of hexadecimal digits; a constant of this unit is too long for one string. }
function PaletteOfHex(const LowPart, HighPart: string): TPalette;
var
  Entries: string;
begin
  Entries := DecodeHex(LowPart) + DecodeHex(HighPart);
  Result := TPalette.Create(Entries, Length(Entries));
end;

function PassMessage(Receiver: TView; What, Command: Word; InfoPtr: Pointer): Pointer;
begin
  if Assigned(MessageHook) then
    Result := MessageHook(Receiver, What, Command, InfoPtr)
  else
    Result := nil;
end;

function MemoryIsLow: Boolean;
begin
  if Assigned(LowMemoryHook) then
    Result := LowMemoryHook()
  else
    Result := False;
end;

function ApplicationRoot: TGroup;
begin
  Result := TProgram.Application;
end;

{ TBackground }

constructor TBackground.Create(const Bounds: TRect; APattern: Char);
begin
  inherited Create(Bounds);
  Pattern := APattern;
  GrowMode := Byte(gfGrowHiX or gfGrowHiY);
end;

procedure TBackground.Draw;
var
  Row: TDrawBuffer;
  Paint: TAttrPair;
begin
  Row := TDrawBuffer.Create;
  try
    Paint := GetColor($01);
    Row.MoveChar(0, Pattern, Paint.Attrs[0], Word(Size.X));
    WriteLine(0, 0, Size.X, Size.Y, Row);
  finally
    Row.Free;
  end;
end;

function TBackground.GetPalette: TPalette;
begin
  Result := BackgroundPalette;
end;

{ TDeskInit }

constructor TDeskInit.Create(const Bounds: TRect; BackgroundMaker: TCreateBackgroundFunc);
begin
  inherited Create(Bounds);
  CreateBackground := BackgroundMaker;
end;

{ The routines of the tiling }

function IsTileable(P: TView): Boolean;
var
  HasOption, IsShown: Boolean;
begin
  HasOption := (P.Options and ofTileable) <> 0;
  IsShown := (P.State and sfVisible) <> 0;
  Result := HasOption and IsShown;
end;

procedure CountForCascade(P: TView; Args: Pointer);
begin
  if not IsTileable(P) then
    Exit;
  Inc(CascadeCount);
  LastTileable := P;
end;

procedure PlaceCascaded(P: TView; Args: Pointer);
var
  Target: TRect;
begin
  if (not IsTileable(P)) or (CascadeCount < 0) then
    Exit;
  Target := PRect(Args)^;
  Inc(Target.A.X, CascadeCount);
  Inc(Target.A.Y, CascadeCount);
  P.Locate(Target);
  Dec(CascadeCount);
end;

procedure CountForTiling(P: TView; Args: Pointer);
begin
  if IsTileable(P) then
    Inc(TileableCount);
end;

function ISqr(Value: SmallInt): SmallInt;
var
  Estimate, Quotient: SmallInt;
begin
  Estimate := 2;
  Quotient := SmallInt(Value div Estimate);
  while Abs(Estimate - Quotient) > 1 do
  begin
    Estimate := SmallInt((Estimate + Quotient) div 2);
    Quotient := SmallInt(Value div Estimate);
  end;
  if Estimate < Quotient then
    Result := Estimate
  else
    Result := Quotient;
end;

procedure MostEqualDivisors(N: SmallInt; var X, Y: SmallInt; FavorY: Boolean);
var
  Factor, Partner: SmallInt;
begin
  Factor := ISqr(N);
  if (N mod Factor <> 0) and (N mod (Factor + 1) = 0) then
    Inc(Factor);
  Partner := SmallInt(N div Factor);
  if Factor < Partner then
    Factor := Partner;

  if FavorY then
  begin
    X := SmallInt(N div Factor);
    Y := Factor;
  end
  else
  begin
    Y := SmallInt(N div Factor);
    X := Factor;
  end;
end;

function DividerLoc(Lo, Hi, Num, Pos: Integer): Integer;
var
  Scaled: Int64;
begin
  Scaled := Int64(Hi - Lo) * Pos;
  Result := Integer(Scaled div Num + Lo);
end;

function CalcTileRect(Position: SmallInt; const Area: TRect): TRect;
var
  Column, Row, FirstShortSlot: SmallInt;
  FullColumns: SmallInt;
  InShortPart: Boolean;
  Rows: Integer;
begin
  FullColumns := ColumnCount - LeftOverCount;
  FirstShortSlot := FullColumns * RowCount;
  InShortPart := Position >= FirstShortSlot;
  if InShortPart then
  begin
    Column := SmallInt((Position - FirstShortSlot) div (RowCount + 1) + FullColumns);
    Row := SmallInt((Position - FirstShortSlot) mod (RowCount + 1));
    Rows := RowCount + 1;
  end
  else
  begin
    Column := SmallInt(Position div RowCount);
    Row := SmallInt(Position mod RowCount);
    Rows := RowCount;
  end;
  Result.A.X := DividerLoc(Area.A.X, Area.B.X, ColumnCount, Column);
  Result.B.X := DividerLoc(Area.A.X, Area.B.X, ColumnCount, Column + 1);
  Result.A.Y := DividerLoc(Area.A.Y, Area.B.Y, Rows, Row);
  Result.B.Y := DividerLoc(Area.A.Y, Area.B.Y, Rows, Row + 1);
end;

procedure PlaceTiled(P: TView; Args: Pointer);
var
  Slot: TRect;
begin
  if not IsTileable(P) then
    Exit;
  Slot := CalcTileRect(TileIndex, PRect(Args)^);
  P.Locate(Slot);
  Dec(TileIndex);
end;

{ TDeskTop }

procedure TDeskTop.Setup;
begin
  GrowMode := Byte(gfGrowHiX or gfGrowHiY);
  TileColumnsFirst := False;
  if not Assigned(CreateBackground) then
    Exit;
  Background := CreateBackground(GetExtent);
  if Background <> nil then
    Insert(Background);
end;

constructor TDeskTop.Create(const Bounds: TRect);
begin
  inherited Create(Bounds, @TDeskTop.InitBackground);
  Setup;
end;

constructor TDeskTop.Create(const Bounds: TRect; BackgroundMaker: TCreateBackgroundFunc);
begin
  inherited Create(Bounds, BackgroundMaker);
  Setup;
end;

procedure TDeskTop.ShutDown;
begin
  Background := nil;
  inherited ShutDown;
end;

procedure TDeskTop.Cascade(const R: TRect);
var
  Smallest, Largest: TPoint;
  TooNarrow, TooShort: Boolean;
begin
  CascadeCount := 0;
  ForEach(@CountForCascade, nil);
  if CascadeCount <= 0 then
    Exit;

  LastTileable.SizeLimits(Smallest, Largest);
  TooNarrow := Smallest.X > R.B.X - R.A.X - CascadeCount;
  TooShort := Smallest.Y > R.B.Y - R.A.Y - CascadeCount;
  if TooNarrow or TooShort then
  begin
    TileError;
    Exit;
  end;

  Dec(CascadeCount);
  Lock;
  ForEach(@PlaceCascaded, @R);
  Unlock;
end;

procedure TDeskTop.HandleEvent(var Event: TEvent);
var
  WantsNext, WantsPrev: Boolean;
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;
  WantsNext := Event.Message.Command = cmNext;
  WantsPrev := Event.Message.Command = cmPrev;
  if not (WantsNext or WantsPrev) then
    Exit;
  if Valid(cmReleasedFocus) then
  begin
    if WantsNext then
      SelectNext(False)
    else
      Current.PutInFrontOf(Background);
  end;
  ClearEvent(Event);
end;

class function TDeskTop.InitBackground(R: TRect): TBackground;
begin
  Result := TBackground.Create(R, DefaultBkgrnd);
end;

procedure TDeskTop.Tile(const R: TRect);
var
  ColumnTooNarrow, RowTooShort: Boolean;
begin
  TileableCount := 0;
  ForEach(@CountForTiling, nil);
  if TileableCount <= 0 then
    Exit;

  MostEqualDivisors(TileableCount, ColumnCount, RowCount, not TileColumnsFirst);
  ColumnTooNarrow := (R.B.X - R.A.X) div ColumnCount = 0;
  RowTooShort := (R.B.Y - R.A.Y) div RowCount = 0;
  if ColumnTooNarrow or RowTooShort then
  begin
    TileError;
    Exit;
  end;

  LeftOverCount := SmallInt(TileableCount mod ColumnCount);
  TileIndex := SmallInt(TileableCount - 1);
  Lock;
  ForEach(@PlaceTiled, @R);
  Unlock;
end;

procedure TDeskTop.TileError;
begin
end;

{ TProgInit }

constructor TProgInit.Create(const Bounds: TRect; StatusLineMaker: TCreateStatusLineFunc;
  MenuBarMaker: TCreateMenuBarFunc; DeskTopMaker: TCreateDeskTopFunc);
begin
  inherited Create(Bounds);
  CreateStatusLine := StatusLineMaker;
  CreateMenuBar := MenuBarMaker;
  CreateDeskTop := DeskTopMaker;
end;

{ TProgram }

function WholeScreen: TRect;
begin
  Result := TRect.Create(0, 0, ScreenWidth, ScreenHeight);
end;

function ViewHasMouse(P: TView; Args: Pointer): Boolean;
var
  IsShown: Boolean;
begin
  IsShown := (P.State and sfVisible) <> 0;
  Result := IsShown and P.MouseInView(PEvent(Args)^.Mouse.Where);
end;

procedure DeliverTimerExpired(Id: TTimerId; Args: Pointer);
begin
  PassMessage(TProgram(Args), evBroadcast, cmTimerExpired, Id);
end;

constructor TProgram.Create;
begin
  inherited Create(WholeScreen, @TProgram.InitStatusLine, @TProgram.InitMenuBar, @TProgram.InitDeskTop);
  Assemble;
end;

constructor TProgram.Create(StatusLineMaker: TCreateStatusLineFunc; MenuBarMaker: TCreateMenuBarFunc;
  DeskTopMaker: TCreateDeskTopFunc);
begin
  inherited Create(WholeScreen, StatusLineMaker, MenuBarMaker, DeskTopMaker);
  Assemble;
end;

procedure TProgram.Assemble;
begin
  Application := Self;
  ReadScreenMode;
  State := sfVisible or sfSelected or sfFocused or sfModal or sfExposed;
  Options := 0;
  Buffer := TScreen.ScreenBuffer;

  if Assigned(CreateDeskTop) then
  begin
    DeskTop := CreateDeskTop(GetExtent);
    if DeskTop <> nil then
      Insert(DeskTop);
  end;

  if Assigned(CreateStatusLine) then
  begin
    StatusLine := CreateStatusLine(GetExtent);
    if StatusLine <> nil then
      Insert(StatusLine);
  end;

  if Assigned(CreateMenuBar) then
  begin
    MenuBar := CreateMenuBar(GetExtent);
    if MenuBar <> nil then
      Insert(MenuBar);
  end;
end;

destructor TProgram.Destroy;
begin
  Application := nil;
  inherited Destroy;
end;

procedure TProgram.ShutDown;
begin
  StatusLine := nil;
  MenuBar := nil;
  DeskTop := nil;
  inherited ShutDown;
end;

function TProgram.CanMoveFocus: Boolean;
begin
  Result := DeskTop.Valid(cmReleasedFocus);
end;

class function TProgram.EventWaitTimeout: Integer;
var
  TimerMs: LongInt;
begin
  TimerMs := TimerQueue.TimeUntilNextTimeout;
  if TimerMs < 0 then
    Exit(EventTimeoutMs);
  if EventTimeoutMs < 0 then
    Exit(TimerMs);
  if EventTimeoutMs < TimerMs then
    Result := EventTimeoutMs
  else
    Result := TimerMs;
end;

function TProgram.ExecuteDialog(Dialog: TWindow; Data: Pointer): Word;
begin
  Result := cmCancel;
  if ValidView(Dialog) = nil then
    Exit;
  if Data <> nil then
    Dialog.SetData(Data);
  Result := DeskTop.ExecView(Dialog);
  if (Result <> cmCancel) and (Data <> nil) then
    Dialog.GetData(Data);
  TvObject.DestroyObject(Dialog);
end;

procedure TProgram.ReadNextEvent(var Event: TEvent);
var
  GotInput: Boolean;
begin
  TEventQueue.WaitForEvents(EventWaitTimeout);
  if TEventQueue.GetPostedEvent(Event) then
    Exit;
  TEventQueue.GetMouseEvent(Event);
  GotInput := Event.What <> evNothing;
  if not GotInput then
  begin
    TEventQueue.GetKeyEvent(Event);
    GotInput := Event.What <> evNothing;
  end;
  if not GotInput then
    Idle;
end;

procedure TProgram.OfferToStatusLine(var Event: TEvent);
var
  IsKey, IsMouseDown, ClickedStatusLine: Boolean;
begin
  if StatusLine = nil then
    Exit;
  IsKey := (Event.What and evKeyDown) <> 0;
  IsMouseDown := (Event.What and evMouseDown) <> 0;
  ClickedStatusLine := False;
  if (not IsKey) and IsMouseDown then
    ClickedStatusLine := FirstThat(@ViewHasMouse, @Event) = StatusLine;
  if IsKey or ClickedStatusLine then
    StatusLine.HandleEvent(Event);
end;

procedure TProgram.GetEvent(var Event: TEvent);
var
  HasPending, ScreenChanged: Boolean;
begin
  HasPending := Pending.What <> evNothing;
  if not HasPending then
    ReadNextEvent(Event)
  else
  begin
    Event := Pending;
    Pending.What := evNothing;
  end;

  OfferToStatusLine(Event);

  ScreenChanged := (Event.What = evCommand) and (Event.Message.Command = cmScreenChanged);
  if not ScreenChanged then
    Exit;
  SetScreenMode(TDisplay.smUpdate);
  ClearEvent(Event);
end;

function TProgram.GetPalette: TPalette;
begin
  Result := AppPalettes[AppPalette];
end;

procedure TProgram.SelectWindowByAltKey(var Event: TEvent);
var
  AltKey: Char;
  WindowNumber: PtrUInt;
  Answer: Pointer;
begin
  AltKey := GetAltChar(Event.KeyDown.KeyCode);
  if (AltKey < '1') or (AltKey > '9') then
    Exit;
  if not CanMoveFocus then
  begin
    ClearEvent(Event);
    Exit;
  end;
  WindowNumber := PtrUInt(Ord(AltKey) - Ord('0'));
  Answer := PassMessage(DeskTop, evBroadcast, cmSelectWindowNum, Pointer(WindowNumber));
  if Answer <> nil then
    ClearEvent(Event);
end;

procedure TProgram.HandleEvent(var Event: TEvent);
var
  IsQuit: Boolean;
begin
  if Event.What = evKeyDown then
    SelectWindowByAltKey(Event);

  inherited HandleEvent(Event);
  IsQuit := (Event.What = evCommand) and (Event.Message.Command = cmQuit);
  if not IsQuit then
    Exit;
  EndModal(cmQuit);
  ClearEvent(Event);
end;

procedure TProgram.Idle;
begin
  if StatusLine <> nil then
    StatusLine.Update;

  if TView.CommandSetChanged then
  begin
    PassMessage(Self, evBroadcast, cmCommandSetChanged, nil);
    TView.CommandSetChanged := False;
  end;

  TimerQueue.CollectExpiredTimers(@DeliverTimerExpired, Self);
end;

procedure TProgram.ReadScreenMode;
var
  BaseMode: Word;
  SmallFont: Boolean;
begin
  BaseMode := TScreen.ScreenMode and $00FF;
  if BaseMode = TDisplay.smMono then
  begin
    ShadowSize.X := 0;
    ShadowSize.Y := 0;
    TView.ShowMarkers := True;
    AppPalette := apMonochrome;
    Exit;
  end;

  SmallFont := (TScreen.ScreenMode and TDisplay.smFont8x8) <> 0;
  ShadowSize.X := 2 - Ord(SmallFont);
  ShadowSize.Y := 1;
  TView.ShowMarkers := False;
  AppPalette := apColor;
  if BaseMode = TDisplay.smBW80 then
    AppPalette := apBlackWhite;
end;

procedure TProgram.InitScreen;
begin
  ReadScreenMode;
end;

procedure TProgram.OutOfMemory;
begin
end;

procedure TProgram.PutEvent(var Event: TEvent);
begin
  Pending := Event;
end;

procedure TProgram.Run;
begin
  Execute;
end;

function TProgram.InsertWindow(Win: TWindow): TWindow;
begin
  Result := nil;
  if ValidView(Win) = nil then
    Exit;
  if not CanMoveFocus then
  begin
    TvObject.DestroyObject(Win);
    Exit;
  end;
  DeskTop.Insert(Win);
  Result := Win;
end;

procedure TProgram.SetScreenMode(Mode: Word);
var
  Whole: TRect;
begin
  if Assigned(MouseHideHook) then
    MouseHideHook();
  TScreen.SetVideoMode(Mode);
  InitScreen;
  Buffer := TScreen.ScreenBuffer;
  Whole := WholeScreen;
  ChangeBounds(Whole);
  SetState(sfExposed, False);
  SetState(sfExposed, True);
  Redraw;
  if Assigned(MouseShowHook) then
    MouseShowHook();
end;

function TProgram.SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer): TTimerId;
begin
  Result := TimerQueue.SetTimer(TimeoutMs, PeriodMs);
end;

procedure TProgram.KillTimer(Id: TTimerId);
begin
  TimerQueue.KillTimer(Id);
end;

procedure TProgram.Suspend;
begin
end;

procedure TProgram.Resume;
begin
end;

function TProgram.ValidView(P: TView): TView;
begin
  Result := nil;
  if P = nil then
    Exit;
  if MemoryIsLow then
  begin
    TvObject.DestroyObject(P);
    OutOfMemory;
    Exit;
  end;
  if not P.Valid(cmValid) then
  begin
    TvObject.DestroyObject(P);
    Exit;
  end;
  Result := P;
end;

{ A status item whose text is null. }
function StatusItemWithoutText(Key: Word; Command: Word): TStatusItem;
begin
  Result := TStatusItem.Create('', TKey.Create(Key), Command);
  FreeMem(Result.Text);
  Result.Text := nil;
end;

class function TProgram.InitStatusLine(R: TRect): TStatusLine;
var
  Definition: TStatusDef;
begin
  R.A.Y := R.B.Y - 1;
  Definition := TStatusDef.Create(0, $FFFF);
  Definition := Definition + TStatusItem.Create(ExitText, TKey.Create(kbAltX), cmQuit);
  Definition := Definition + StatusItemWithoutText(kbF10, cmMenu);
  Definition := Definition + StatusItemWithoutText(kbAltF3, cmClose);
  Definition := Definition + StatusItemWithoutText(kbF5, cmZoom);
  Definition := Definition + StatusItemWithoutText(kbCtrlF5, cmResize);
  Result := TStatusLine.Create(R, Definition);
end;

class function TProgram.InitMenuBar(R: TRect): TMenuBar;
begin
  R.B.Y := R.A.Y + 1;
  Result := TMenuBar.Create(R, TMenu(nil));
end;

class function TProgram.InitDeskTop(R: TRect): TDeskTop;
var
  Area: TRect;
begin
  Area := TRect.Create(R.A.X, R.A.Y + 1, R.B.X, R.B.Y - 1);
  Result := TDeskTop.Create(Area);
end;

{ TSystemError }

constructor TSystemError.Create;
begin
  inherited Create;
  Resume;
end;

destructor TSystemError.Destroy;
begin
  Suspend;
  inherited Destroy;
end;

class procedure TSystemError.Resume;
begin
  if Assigned(SetCtrlBrkHandlerHook) then
    SetCtrlBrkHandlerHook(True);
end;

class procedure TSystemError.Suspend;
begin
  if Assigned(SetCtrlBrkHandlerHook) then
    SetCtrlBrkHandlerHook(False);
end;

{ TAppInit }

constructor TAppInit.Create;
begin
  inherited Create;
  if SharedScreen = nil then
    SharedScreen := TScreen.Create;
  if SharedQueue = nil then
    SharedQueue := TEventQueue.Create;
  if SharedSysErr = nil then
    SharedSysErr := TSystemError.Create;
end;

class procedure TAppInit.Shutdown;
begin
  SharedSysErr.Free;
  SharedSysErr := nil;
  SharedQueue.Free;
  SharedQueue := nil;
  SharedScreen.Free;
  SharedScreen := nil;
end;

{ TApplication }

constructor TApplication.Create;
begin
  Subsystems := TAppInit.Create;
  inherited Create(@TApplication.InitStatusLine, @TApplication.InitMenuBar, @TApplication.InitDeskTop);
  if Assigned(InitHistoryHook) then
    InitHistoryHook();
end;

constructor TApplication.Create(StatusLineMaker: TCreateStatusLineFunc; MenuBarMaker: TCreateMenuBarFunc;
  DeskTopMaker: TCreateDeskTopFunc);
begin
  Subsystems := TAppInit.Create;
  inherited Create(StatusLineMaker, MenuBarMaker, DeskTopMaker);
  if Assigned(InitHistoryHook) then
    InitHistoryHook();
end;

destructor TApplication.Destroy;
begin
  if Assigned(DoneHistoryHook) then
    DoneHistoryHook();
  inherited Destroy;
  Subsystems.Free;
end;

procedure TApplication.Suspend;
begin
  TSystemError.Suspend;
  TEventQueue.Suspend;
  TScreen.Suspend;
end;

procedure TApplication.Resume;
begin
  TScreen.Resume;
  TEventQueue.Resume;
  TSystemError.Resume;
end;

procedure TApplication.Cascade;
begin
  if DeskTop <> nil then
    DeskTop.Cascade(GetTileRect);
end;

{ Stops the program until the shell, or the job control of the system, lets it go on. }
procedure WaitInShell;
begin
{$IFDEF MSWINDOWS}
  ExecuteProcess(GetEnvironmentVariable('COMSPEC'), '');
{$ELSE}
  fpKill(fpGetPid, SIGTSTP);
{$ENDIF}
end;

procedure TApplication.DosShell;
begin
  Suspend;
  WriteShellMsg;
  WaitInShell;
  Resume;
  Redraw;
end;

function TApplication.GetTileRect: TRect;
begin
  Result := DeskTop.GetExtent;
end;

procedure TApplication.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;
  case Event.Message.Command of
    cmDosShell:
      DosShell;
    cmCascade:
      Cascade;
    cmTile:
      Tile;
  else
    Exit;
  end;
  ClearEvent(Event);
end;

procedure TApplication.Tile;
begin
  if DeskTop <> nil then
    DeskTop.Tile(GetTileRect);
end;

procedure TApplication.WriteShellMsg;
begin
{$IFDEF MSWINDOWS}
  WriteLn('Type EXIT to return...');
{$ELSE}
  WriteLn('The application has been stopped. You can return by entering ''fg''.');
{$ENDIF}
end;

initialization
  BackgroundPalette := TPalette.Create(#1, 1);
  AppPalettes[apColor] := PaletteOfHex(AppColorHexLow, AppColorHexHigh);
  AppPalettes[apBlackWhite] := PaletteOfHex(AppBlackWhiteHexLow, AppBlackWhiteHexHigh);
  AppPalettes[apMonochrome] := PaletteOfHex(AppMonochromeHexLow, AppMonochromeHexHigh);
  TProgram.TimerQueue := TTimerQueue.Create;
  TProgram.AppPalette := apColor;
  EventTimeoutMs := 20;
  ApplicationHook := @ApplicationRoot;

finalization
  TAppInit.Shutdown;
  ApplicationHook := nil;
  TProgram.TimerQueue.Free;
  TProgram.TimerQueue := nil;
  BackgroundPalette.Free;
  AppPalettes[apColor].Free;
  AppPalettes[apBlackWhite].Free;
  AppPalettes[apMonochrome].Free;

end.
