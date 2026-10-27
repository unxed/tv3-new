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

end.
