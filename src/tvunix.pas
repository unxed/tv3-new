{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/platform.h, source/platform/platform.cpp,
  include/tvision/internal/unixcon.h, source/platform/unixcon.cpp, include/tvision/internal/sigwinch.h,
  source/platform/sigwinch.cpp, include/tvision/internal/sighandl.h, source/platform/sighandl.cpp,
  include/tvision/internal/errredir.h, source/platform/errredir.cpp, include/tvision/internal/ncurdisp.h,
  source/platform/ncurdisp.cpp, include/tvision/internal/ncursinp.h, source/platform/ncursinp.cpp,
  include/tvision/internal/unixclip.h, source/platform/unixclip.cpp, source/platform/hardware.cpp,
  include/tvision/hardware.h
  See COPYRIGHT.magiblot.

  The backends of the library for a terminal of a Unix system: TUnixEventBackend (TvSys), TUnixScreenBackend
  (TvScreen) and TUnixClipboardBackend (TvClip), over the class Platform, which holds what the C++ class Platform
  holds: the waiter of events, the display buffer and the console adapter that is in use.

  No curses library is used. NcursesDisplay is the display adapter that writes the ANSI sequences of TvAnsi to the
  descriptor of ConsoleCtl and switches to the alternate screen and back, and NcursesInput reads the descriptor
  and gives the bytes to TermIO.ParseEvent. What the curses library decodes in the C++ (the keys of the terminal
  database) is decoded by TermIO, and by TryLegacyKey for the sequences ESC O letter without a number. The number
  of colors of a terminal is taken from the environment: COLORTERM with truecolor or 24bit, and TERM with direct,
  256color or 16color, give the direct, 256 and 16 color levels; an unset TERM or dumb gives no colors and any
  other TERM gives 8 colors. The keyboard of the terminal is not put in application mode, so the cursor keys come
  as CSI sequences, which TermIO decodes. The terminal mode (raw, no echo, no translation of CR) is set with the
  termios of the descriptor of the input and is restored when the input adapter ends.

  Left out: LinuxConsoleAdapter, LinuxConsoleInput and GpmInput (the values of linux/keyboard.h that
  linuxcon.cpp reads are not among the inputs), Platform::initLocale, Platform::initCharOps and the width
  functions of platfchr.cpp (TvUtf8 has its own width table), and the parts of the C++ that exist only for
  Windows. Without a terminal on the descriptors the screen has the size 80 by 25 where ConsoleCtl gives 0 by 0.

  The text of the clipboard routines of TvClip and of TTextProc is a string of at most 255 bytes, so a longer text
  of the system clipboard is cut at the interface. }
unit TvUnix;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  ctypes, UnixType, BaseUnix, TvGeom, TvColors, TvDispBuf, TvDrawBuf, TvEvents, TvSys, TvScreen, TvClip,
  TvTermOs, TvAnsi;

const
  { The number of events that the backend reads at once (THardwareInfo::eventQSize). }
  eventQSize = 24;
  { The number of signals that SignalHandler takes over. }
  HandledSignalCount = 10;

type
  { The keys of one character that NcursesInput reads: at most four bytes of UTF-8. }
  TNcursesKeys = array[0..3] of Integer;

  { A source of events that reads a terminal. }
  InputAdapter = class(TEventSource)
  end;

  { The display, the sources of events and the clipboard of one console. The base class is the dummy console: it
    has no sources and no clipboard. }
  ConsoleAdapter = class
  public
    Display: DisplayAdapter;
    Sources: array of TEventSource;
    constructor Create(ADisplay: DisplayAdapter; const ASources: array of TEventSource);
    function IsAlive: Boolean; virtual;
    function SetClipboardText(const Text: AnsiString): Boolean; virtual;
    function RequestClipboardText(Accept: TTextProc): Boolean; virtual;
  end;

  { Points the standard error output at a pipe while the console is in use and writes what the pipe holds to the
    terminal when the redirector ends. }
  StderrRedirector = class
  private
    TtyFd: cint;
    BufFd: array[0..1] of cint;
    function Redirect: Boolean;
    procedure CloseAll;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  { The source of events that SIGWINCH signals; it gives the command cmScreenChanged. }
  SigwinchHandler = class(TWakeUpEventSource)
  private
    OldSa: SigActionRec;
    class var Instance: SigwinchHandler;
    constructor Create(const AHandle: TSysManualEventHandle; const AOldSa: SigActionRec);
  public
    { The static function create: nil when a handler exists already or the signal cannot be taken. }
    class function Make: SigwinchHandler; static;
    destructor Destroy; override;
  end;

  SignalHandlerCallback = procedure(Enter: Boolean);

  { Calls the callback with True when a signal of the list comes and with False when the program goes on after
    it, and passes the signal on to the action that was in place before. }
  SignalHandler = class
  private
    class var Callback: SignalHandlerCallback;
  public
    class function HandledSignal(Index: Integer): cint; static;
    class procedure Enable(ACallback: SignalHandlerCallback); static;
    class procedure Disable; static;
  end;

  { The input of ncurses: the bytes of the descriptor, with a time-out for the next byte and a place for the bytes
    that are given back. }
  NcursesInputGetter = class(TInputGetter)
  private
    FFd: cint;
    FStack: array[0..255] of Integer;
    FStackCount: Integer;
    FChunk: array[0..4095] of Byte;
    FChunkPos: Integer;
    FChunkLen: Integer;
    function WaitReadable: Boolean;
  public
    { The time that Get waits for a byte, in milliseconds. }
    TimeoutMs: Integer;
    constructor Create(AFd: cint);
    { The next byte, or -1 when none comes within TimeoutMs. }
    function Get: Integer; override;
    procedure Unget(Key: Integer); override;
    { The number of bytes that were read or given back and have not been taken. }
    function PendingCount: SizeInt;
  end;

  NcursesDisplay = class(DisplayAdapter)
  private
    Con: ConsoleCtl;
    AnsiScreenWriter: TAnsiScreenWriter;
    TermCap: TTermCap;
    procedure Send(const Text: AnsiString);
  public
    { Switches to the alternate screen and clears it. }
    constructor Create(ACon: ConsoleCtl);
    destructor Destroy; override;
    function ReloadScreenInfo: TPoint; override;
    function GetColorCount: Integer; override;
    function GetFontSize: TPoint; override;
    procedure WriteCell(const Pos: TPoint; const Text: string; const Attr: TColorAttr;
      DoubleWidth: Boolean); override;
    procedure SetCaretPosition(const Pos: TPoint); override;
    procedure SetCaretSize(Size: Integer); override;
    procedure ClearScreen; override;
    procedure Flush; override;
  end;

  NcursesInput = class(InputAdapter)
  private
    Con: ConsoleCtl;
    State: PInputState;
    MouseEnabled: Boolean;
    In_: NcursesInputGetter;
    SavedMode: array[0..127] of Byte;
    HaveSavedMode: Boolean;
    procedure EnterRawMode;
    procedure LeaveRawMode;
    function GetChNb: Integer;
    function TryLegacyKey(var Ev: TEvent): Boolean;
    procedure DetectAlt(var Keys: TNcursesKeys; var Alt: Boolean);
    procedure ParsePrintableChar(var Ev: TEvent; var Keys: TNcursesKeys; var NumKeys: Integer);
    procedure ReadUtf8Char(var Keys: TNcursesKeys; var NumKeys: Integer);
  public
    { Puts the terminal in raw mode and turns on the key modes and the mouse. The display is not used. }
    constructor Create(ACon: ConsoleCtl; ADisplay: NcursesDisplay; AState: PInputState; AMouse: Boolean);
    destructor Destroy; override;
    function GetEvent(var Ev: TEvent): Boolean; override;
    function HasPendingEvents: Boolean; override;
  end;

  { The system clipboard through the programs of the system. }
  UnixClipboard = class
  public
    { While False, the clipboard routines run no program and give False. }
    class var Enabled: Boolean;
    class function SetClipboardText(const Text: AnsiString): Boolean; static;
    class function RequestClipboardText(Accept: TTextProc): Boolean; static;
    { Whether a file that can be run is found by the name: along PATH, or at the path when it begins with a slash. }
    class function ExecutableExists(const Name: AnsiString): Boolean; static;
    { Runs the program with the extra variables Env (name, value, name, value...) and reads what it writes, for
      at most TimeoutMs between two reads. False when it could not run, or failed and gave nothing. }
    class function ReadSubprocess(const Argv: array of AnsiString; const Env: array of AnsiString;
      TimeoutMs: Integer; out Data: AnsiString): Boolean; static;
    { Runs the program and writes Text to its input. True when the program ends with the status 0 and took all
      the text. }
    class function WriteSubprocess(const Argv: array of AnsiString; const Text: AnsiString;
      TimeoutMs: Integer): Boolean; static;
  end;

  UnixConsoleAdapter = class(ConsoleAdapter)
  private
    ErrRedir: StderrRedirector;
    Con: ConsoleCtl;
    DisplayBuf: DisplayBuffer;
    InputState: PInputState;
    Sigwinch: SigwinchHandler;
    Input: InputAdapter;
  public
    constructor Create(ADisplay: DisplayAdapter; AInput: InputAdapter; ACon: ConsoleCtl; ADisplayBuf: DisplayBuffer;
      AInputState: PInputState; ASigwinch: SigwinchHandler);
    { The static function create. The adapter takes over AInputState, ADisplay and AInput. }
    class function Make(ACon: ConsoleCtl; ADisplayBuf: DisplayBuffer; AInputState: PInputState;
      ADisplay: DisplayAdapter; AInput: InputAdapter): UnixConsoleAdapter; static;
    destructor Destroy; override;
    function SetClipboardText(const Text: AnsiString): Boolean; override;
    function RequestClipboardText(Accept: TTextProc): Boolean; override;
  end;

  { The singleton that THardwareInfo calls. }
  Platform = class
  private
    Waiter: TEventWaiter;
    DisplayBuf: DisplayBuffer;
    DummyDisplay: DisplayAdapter;
    DummyConsole: ConsoleAdapter;
    Console: ConsoleAdapter;
    Lock: SignalSafeMutexState;
    class var Instance: Platform;
    constructor Create;
    procedure SetUpConsole(var C: ConsoleAdapter); overload;
    procedure RestoreConsole(var C: ConsoleAdapter); overload;
    procedure CheckConsole;
    function CreateConsole: ConsoleAdapter;
    class procedure SignalCallback(Enter: Boolean); static;
  public
    destructor Destroy; override;
    class function GetInstance: Platform; static;
    { Gives the console back and frees the instance, which the C++ never does. }
    class procedure DestroyInstance; static;
    procedure SetUpConsole; overload;
    procedure RestoreConsole; overload;
    function IsSetUp: Boolean;
    function GetEvent(var Ev: TEvent): Boolean;
    procedure WaitForEvents(Ms: Integer);
    procedure InterruptEventWait;
    function GetCaretSize: Integer;
    function IsCaretVisible: Boolean;
    procedure ClearScreen;
    function GetScreenRows: Integer;
    function GetScreenCols: Integer;
    procedure SetCaretPosition(X, Y: Integer);
    function GetScreenMode: Word;
    procedure SetCaretSize(Size: Integer);
    procedure ScreenWrite(X, Y: Integer; Buf: TvDispBuf.PScreenCell; Len: Integer);
    procedure FlushScreen;
    function ReloadScreenInfo: TvDispBuf.PScreenCell;
    procedure FreeScreenBuffer;
    function SetClipboardText(const Text: AnsiString): Boolean;
    function RequestClipboardText(Accept: TTextProc): Boolean;
  end;

  { The input of the terminal as TEventQueue uses it: the members of THardwareInfo for events. }
  TUnixEventBackend = class(TEventBackend)
  private
    EventQ: array[0..eventQSize - 1] of TEvent;
    EventCount: Integer;
    InsertState: Boolean;
    LastMouse: TMouseEventType;
    function GetPendingEvent(var Ev: TEvent; Mouse: Boolean): Boolean;
    procedure ReadEvents;
  public
    constructor Create;
    function GetButtonCount: Cardinal; override;
    procedure MouseGetState(var Mouse: TMouseEventType); override;
    procedure ClearPendingEvent; override;
    function GetMouseEvent(var Mouse: TMouseEventType): Boolean; override;
    function GetKeyEvent(var Ev: TEvent): Boolean; override;
    function ScreenWidth: Integer; override;
    function ScreenHeight: Integer; override;
    procedure WaitForEvents(TimeoutMs: Integer); override;
    procedure InterruptEventWait; override;
  end;

  { The screen as TScreen uses it: the members of THardwareInfo for the screen. }
  TUnixScreenBackend = class(TScreenBackend)
  public
    procedure SetUpConsole; override;
    procedure RestoreConsole; override;
    function GetCaretSize: Word; override;
    procedure SetCaretSize(Size: Word); override;
    procedure ClearScreen(W, H: Byte); override;
    function GetScreenRows: Word; override;
    function GetScreenCols: Word; override;
    function GetScreenMode: Word; override;
    function AllocateScreenBuffer: TvDrawBuf.PScreenCell; override;
    procedure FreeScreenBuffer(Buffer: TvDrawBuf.PScreenCell); override;
    procedure FlushScreen; override;
  end;

  TUnixClipboardBackend = class(TClipboardBackend)
  public
    function SetText(const Text: string): Boolean; override;
    function RequestText(Accept: TTextProc): Boolean; override;
  end;

{ THardwareInfo::screenWrite and THardwareInfo::setCaretPosition, for ScreenWriteHook and CaretPositionHook of
  TvViews. }
procedure UnixScreenWrite(X, Y: Integer; Buf: TvDrawBuf.PScreenCell; Count: Integer);
procedure UnixCaretPosition(X, Y: Integer);

implementation

uses
  SysUtils, termio, TvKeys, TvUtf8, TvCodePg, TvTermIo;

const
  { The time that the input waits for the next byte of a key. }
  ReadTimeoutMs = 10;
  { FD_CLOEXEC }
  FdCloseOnExec = 1;
  ClipboardTimeoutMs = 1500;
  ChunkSize = 4096;
  KeyEsc = 27;
  { The size of the screen when the descriptors have none. }
  DefaultColumns = 80;
  DefaultRows = 25;
  { The value of cmScreenChanged of TvViews. }
  ScreenChangedCommand = 57;
  { Numbers of the errors that are tested. }
  ErrInterrupted = 4;
{$IFDEF LINUX}
  ErrWouldBlock = 11;
{$ELSE}
  ErrWouldBlock = 35;
{$ENDIF}
  { The values of SIG_DFL and SIG_IGN. }
  HandlerDefault = 0;
  HandlerIgnore = 1;
  DefaultSearchPath = '/usr/local/bin:/bin:/usr/bin';

type
  PTermiosRec = ^termios;

var
  { THardwareInfo::alwaysFlush: the screen is flushed after every write. }
  AlwaysFlushScreen: Boolean;

function SmallerOf(P, Q: Integer): Integer;
begin
  if P < Q then
    Result := P
  else
    Result := Q;
end;

function LargerOf(P, Q: Integer): Integer;
begin
  if P > Q then
    Result := P
  else
    Result := Q;
end;

{ Writes Size bytes to Fd; it stops at the first failure. }
procedure WriteAll(Fd: cint; Data: PAnsiChar; Size: SizeInt);
var
  Done: SizeInt;
  Got: TSsize;
begin
  Done := 0;
  while Done < Size do
  begin
    Got := fpWrite(Fd, Data + Done, SizeUInt(Size - Done));
    if Got <= 0 then
      Break;
    Inc(Done, Got);
  end;
end;

{ A descriptor is a terminal when its modes can be read. }
function IsTerminal(Fd: cint): Boolean;
var
  Mode: termios;
begin
  Result := TCGetAttr(Fd, Mode) = 0;
end;

{ ConsoleAdapter }

constructor ConsoleAdapter.Create(ADisplay: DisplayAdapter; const ASources: array of TEventSource);
var
  I: Integer;
begin
  inherited Create;
  Display := ADisplay;
  SetLength(Sources, Length(ASources));
  for I := 0 to High(ASources) do
    Sources[I] := ASources[I];
end;

function ConsoleAdapter.IsAlive: Boolean;
begin
  Result := True;
end;

function ConsoleAdapter.SetClipboardText(const Text: AnsiString): Boolean;
begin
  Result := False;
end;

function ConsoleAdapter.RequestClipboardText(Accept: TTextProc): Boolean;
begin
  Result := False;
end;

{ StderrRedirector }

function SameFile(Fd1, Fd2: cint): Boolean;
var
  Info1, Info2: Stat;
begin
  Result := False;
  if fpFStat(Fd1, Info1) <> 0 then
    Exit;
  if fpFStat(Fd2, Info2) <> 0 then
    Exit;
  Result := (Info1.st_dev = Info2.st_dev) and (Info1.st_ino = Info2.st_ino);
end;

{ Moves what the pipe holds, until it is empty, to Dst. }
procedure DumpPipe(Src, Dst: cint);
var
  Flags: cint;
  Chunk: array[0..ChunkSize - 1] of AnsiChar;
  Got: TSsize;
begin
  Flags := fpFcntl(Src, F_GETFL);
  if Flags = -1 then
    Exit;
  if fpFcntl(Src, F_SETFL, Flags or O_NONBLOCK) = -1 then
    Exit;
  repeat
    Got := fpRead(Src, PAnsiChar(@Chunk[0]), SizeOf(Chunk));
    if Got > 0 then
      WriteAll(Dst, PAnsiChar(@Chunk[0]), Got);
  until Got <= 0;
end;

constructor StderrRedirector.Create;
begin
  inherited Create;
  TtyFd := -1;
  BufFd[0] := -1;
  BufFd[1] := -1;
  if not Redirect then
    CloseAll;
end;

{ The steps of the constructor of the C++, in the same order; the first step that fails ends them. }
function StderrRedirector.Redirect: Boolean;
var
  Made: TFilDes;
  Flags: cint;
begin
  Result := False;
  if not IsTerminal(2) then
    Exit;
  TtyFd := fpDup(2);
  if TtyFd = -1 then
    Exit;
  if fpPipe(Made) = -1 then
    Exit;
  BufFd[0] := Made[0];
  BufFd[1] := Made[1];
  if fpDup2(BufFd[1], 2) = -1 then
    Exit;
  Flags := fpFcntl(2, F_GETFL);
  if Flags = -1 then
    Exit;
  if fpFcntl(2, F_SETFL, Flags or O_NONBLOCK) = -1 then
    Exit;
  if fpFcntl(TtyFd, F_SETFD, FdCloseOnExec) = -1 then
    Exit;
  if fpFcntl(BufFd[0], F_SETFD, FdCloseOnExec) = -1 then
    Exit;
  if fpFcntl(BufFd[1], F_SETFD, FdCloseOnExec) = -1 then
    Exit;
  Result := True;
end;

procedure StderrRedirector.CloseAll;
begin
  if TtyFd <> -1 then
    fpClose(TtyFd);
  if BufFd[0] <> -1 then
    fpClose(BufFd[0]);
  if BufFd[1] <> -1 then
    fpClose(BufFd[1]);
  TtyFd := -1;
  BufFd[0] := -1;
  BufFd[1] := -1;
end;

destructor StderrRedirector.Destroy;
begin
  { Standard error goes back to the terminal as long as it still is the pipe, and then the pipe is emptied. }
  if SameFile(BufFd[1], 2) then
  begin
    fpDup2(TtyFd, 2);
    DumpPipe(BufFd[0], TtyFd);
  end;
  CloseAll;
  inherited Destroy;
end;

{ Actions of signals }

{ The handler of an action is its first field, whether the action has the form with or without information. }
procedure SetActionHandler(var Action: SigActionRec; Handler: Pointer);
begin
  PPointer(@Action)^ := Handler;
end;

function ActionHandler(const Action: SigActionRec): Pointer;
begin
  Result := PPointer(@Action)^;
end;

{ The action that runs the default handler. }
function DefaultAction: SigActionRec;
begin
  FillChar(Result, SizeOf(Result), 0);
  SetActionHandler(Result, Pointer(PtrUInt(HandlerDefault)));
end;

function IsCustomHandler(Handler: Pointer): Boolean;
begin
  Result := (PtrUInt(Handler) <> HandlerDefault) and (PtrUInt(Handler) <> HandlerIgnore);
end;

{ Two actions are the same when they have the same handler and the same main flags. }
function SameAction(const One, Two: SigActionRec): Boolean;
const
  KnownFlags = SA_SIGINFO or SA_RESTART;
begin
  Result := ((Cardinal(One.sa_flags) and Cardinal(KnownFlags)) = (Cardinal(Two.sa_flags) and Cardinal(KnownFlags))) and
    (ActionHandler(One) = ActionHandler(Two));
end;

{ SignalHandler }

type
  TSignalSlot = record
    Action: SigActionRec;
    Running: LongInt;
  end;

  TSimpleSignalProc = procedure(Signo: cint); cdecl;
  TInfoSignalProc = procedure(Signo: cint; Info, Context: Pointer); cdecl;

const
  HandledSignals: array[0..HandledSignalCount - 1] of cint =
    (SIGINT, SIGQUIT, SIGILL, SIGABRT, SIGBUS, SIGFPE, SIGSEGV, SIGPIPE, SIGTERM, SIGTSTP);

var
  Slots: array[0..HandledSignalCount - 1] of TSignalSlot;

function SlotOf(Signo: cint): Integer;
var
  Slot: Integer;
begin
  Slot := HandledSignalCount;
  repeat
    Dec(Slot);
  until (Slot < 0) or (HandledSignals[Slot] = Signo);
  Result := Slot;
end;

{ The code of the information of a signal: its third integer. }
function SignalCode(Info: Pointer): Integer;
begin
  Result := PLongInt(PtrUInt(Info) + 2 * SizeOf(LongInt))^;
end;

function IsSynchronousSignal(Signo: cint): Boolean;
begin
  Result := (Signo = SIGILL) or (Signo = SIGBUS) or (Signo = SIGFPE) or (Signo = SIGSEGV);
end;

{ Runs the default action of the signal. True means that the handler has to end so that the kernel raises the
  signal again. }
function InvokeDefault(Signo: cint; Info: Pointer): Boolean;
var
  Mask, OldMask: array[0..127] of Byte;
  Bit: Integer;
begin
  Result := False;
  if IsSynchronousSignal(Signo) and (SignalCode(Info) > 0) then
  begin
    Result := True;
    Exit;
  end;
  { A set of signals is a row of bits, the bit Signo - 1 for the signal Signo. }
  FillChar(Mask, SizeOf(Mask), 0);
  FillChar(OldMask, SizeOf(OldMask), 0);
  Bit := Signo - 1;
  Mask[Bit div 8] := Byte(1 shl (Bit mod 8));
  fpSigProcMask(SIG_UNBLOCK, @Mask, @OldMask);
  fpKill(fpGetPid, Signo);
  fpSigProcMask(SIG_SETMASK, @OldMask, nil);
end;

function InvokeHandlerOrDefault(Signo: cint; const Action: SigActionRec; Info, Context: Pointer): Boolean;
var
  Handler: Pointer;
  WithInfo: Boolean;
begin
  Handler := ActionHandler(Action);
  WithInfo := (Cardinal(Action.sa_flags) and Cardinal(SA_SIGINFO)) <> 0;
  if IsCustomHandler(Handler) and WithInfo then
  begin
    TInfoSignalProc(Handler)(Signo, Info, Context);
    Result := False;
  end
  else if IsCustomHandler(Handler) then
  begin
    TSimpleSignalProc(Handler)(Signo);
    Result := False;
  end
  else
    Result := InvokeDefault(Signo, Info);
end;

procedure HandleSignal(Signo: cint; Info, Context: Pointer); cdecl;
var
  Slot: Integer;
  Notify: SignalHandlerCallback;
  NextAction, CurrentAction, Fallback: SigActionRec;
begin
  Slot := SlotOf(Signo);
  if Slot < 0 then
    Exit;
  Notify := SignalHandler.Callback;
  FillChar(CurrentAction, SizeOf(CurrentAction), 0);
  if Assigned(Notify) and (InterlockedExchange(Slots[Slot].Running, 1) = 0) then
  begin
    NextAction := Slots[Slot].Action;
    { This signal could be raised again while the callback runs, so its action is taken out meanwhile. }
    fpSigAction(Signo, nil, @CurrentAction);
    Notify(True);
    fpSigAction(Signo, @NextAction, nil);
    if InvokeHandlerOrDefault(Signo, NextAction, Info, Context) then
      Exit;
    Notify(False);
    fpSigAction(Signo, @CurrentAction, nil);
    InterlockedExchange(Slots[Slot].Running, 0);
  end
  else
  begin
    { The handler runs while it is running already, or without a callback: only the default action is run. }
    Fallback := DefaultAction;
    fpSigAction(Signo, @Fallback, @CurrentAction);
    if InvokeDefault(Signo, Info) then
      Exit;
    fpSigAction(Signo, @CurrentAction, nil);
  end;
end;

{ The action that routes a signal to HandleSignal. }
function HandlerAction: SigActionRec;
begin
  FillChar(Result, SizeOf(Result), 0);
  SetActionHandler(Result, @HandleSignal);
  Result.sa_flags := SA_SIGINFO or SA_RESTART;
end;

class function SignalHandler.HandledSignal(Index: Integer): cint;
begin
  Result := HandledSignals[Index];
end;

class procedure SignalHandler.Enable(ACallback: SignalHandlerCallback);
var
  Ours: SigActionRec;
  I: Integer;
begin
  if Assigned(Callback) then
    Exit;
  Ours := HandlerAction;
  for I := 0 to HandledSignalCount - 1 do
    fpSigAction(HandledSignals[I], @Ours, @Slots[I].Action);
  Callback := ACallback;
end;

class procedure SignalHandler.Disable;
var
  Current: SigActionRec;
  I: Integer;
begin
  if not Assigned(Callback) then
    Exit;
  Callback := nil;
  for I := 0 to HandledSignalCount - 1 do
  begin
    FillChar(Current, SizeOf(Current), 0);
    fpSigAction(HandledSignals[I], nil, @Current);
    { The previous action comes back only when ours is still the one in place. }
    if SameAction(Current, HandlerAction) then
      fpSigAction(HandledSignals[I], @Slots[I].Action, nil);
    Slots[I].Action := DefaultAction;
  end;
end;

{ SigwinchHandler }

function EmitScreenChangedEvent(Args: Pointer; var Ev: TEvent): Boolean;
begin
  Ev.What := evCommand;
  Ev.Message.Command := ScreenChangedCommand;
  Result := True;
end;

procedure SigwinchEntry(Signo: cint); cdecl;
begin
  if SigwinchHandler.Instance <> nil then
    SigwinchHandler.Instance.Signal;
end;

constructor SigwinchHandler.Create(const AHandle: TSysManualEventHandle; const AOldSa: SigActionRec);
begin
  inherited Create(AHandle, @EmitScreenChangedEvent, nil);
  OldSa := AOldSa;
  Instance := Self;
end;

class function SigwinchHandler.Make: SigwinchHandler;
var
  Ours, Previous: SigActionRec;
  Wake: TSysManualEventHandle;
begin
  Result := nil;
  if Instance <> nil then
    Exit;
  Ours := DefaultAction;
  Previous := DefaultAction;
  SetActionHandler(Ours, @SigwinchEntry);
  { Every signal is blocked while the handler runs. }
  FillChar(Ours.sa_mask, SizeOf(Ours.sa_mask), $FF);
  Ours.sa_flags := SA_RESTART;
  if fpSigAction(SIGWINCH, @Ours, @Previous) = -1 then
    Exit;
  if TSysManualEvent.CreateHandle(Wake) then
    Result := SigwinchHandler.Create(Wake, Previous)
  else
    fpSigAction(SIGWINCH, @Previous, nil);
end;

destructor SigwinchHandler.Destroy;
begin
  fpSigAction(SIGWINCH, @OldSa, nil);
  Instance := nil;
  inherited Destroy;
end;

{ NcursesInputGetter }

constructor NcursesInputGetter.Create(AFd: cint);
begin
  inherited Create;
  FFd := AFd;
  FStackCount := 0;
  FChunkPos := 0;
  FChunkLen := 0;
  TimeoutMs := ReadTimeoutMs;
end;

function NcursesInputGetter.WaitReadable: Boolean;
var
  Wait: TPollFD;
  Res: cint;
begin
  Wait.fd := FFd;
  Wait.events := POLLIN;
  Wait.revents := 0;
  repeat
    Res := FpPoll(@Wait, 1, TimeoutMs);
  until (Res >= 0) or (fpGetErrno <> ErrInterrupted);
  Result := (Res > 0) and ((Wait.revents and POLLIN) <> 0);
end;

function NcursesInputGetter.Get: Integer;
var
  Got: TSsize;
begin
  if FStackCount > 0 then
  begin
    Dec(FStackCount);
    Result := FStack[FStackCount];
    Exit;
  end;
  if FChunkPos >= FChunkLen then
  begin
    FChunkPos := 0;
    FChunkLen := 0;
    if not WaitReadable then
    begin
      Result := -1;
      Exit;
    end;
    Got := fpRead(FFd, PAnsiChar(@FChunk[0]), SizeOf(FChunk));
    if Got <= 0 then
    begin
      Result := -1;
      Exit;
    end;
    FChunkLen := Integer(Got);
  end;
  Result := FChunk[FChunkPos];
  Inc(FChunkPos);
end;

procedure NcursesInputGetter.Unget(Key: Integer);
begin
  if (Key >= 0) and (FStackCount < Length(FStack)) then
  begin
    FStack[FStackCount] := Key;
    Inc(FStackCount);
  end;
end;

function NcursesInputGetter.PendingCount: SizeInt;
begin
  Result := FStackCount + (FChunkLen - FChunkPos);
end;

{ NcursesDisplay }

{ The colors of the terminal, from the environment. }
function DetectTermCap: TTermCap;
var
  Term, ColorTerm: string;
begin
  Term := LowerCase(GetEnv('TERM', ''));
  ColorTerm := LowerCase(GetEnv('COLORTERM', ''));
  FillChar(Result, SizeOf(Result), 0);
  if (Pos('truecolor', ColorTerm) > 0) or (Pos('24bit', ColorTerm) > 0) or (Pos('direct', Term) > 0) then
    Result.Colors := Direct
  else if Pos('256color', Term) > 0 then
    Result.Colors := Indexed256
  else if Pos('16color', Term) > 0 then
    Result.Colors := Indexed16
  else if (Term = '') or (Term = 'dumb') then
    Result.Colors := NoColor
  else
    Result.Colors := Indexed8;
end;

constructor NcursesDisplay.Create(ACon: ConsoleCtl);
begin
  inherited Create;
  Con := ACon;
  TermCap := DetectTermCap;
  AnsiScreenWriter := TAnsiScreenWriter.Create(TermCap);
  Send(#27'[?1049h' + #27'[0m' + #27'[2J');
end;

destructor NcursesDisplay.Destroy;
begin
  Send(#27'[0m' + #27'[?25h' + #27'[?1049l');
  AnsiScreenWriter.Free;
  inherited Destroy;
end;

procedure NcursesDisplay.Send(const Text: AnsiString);
begin
  if Length(Text) > 0 then
    Con.Write(PAnsiChar(Text), Length(Text));
end;

function NcursesDisplay.ReloadScreenInfo: TPoint;
begin
  Result := Con.GetSize;
  if (Result.X <= 0) or (Result.Y <= 0) then
  begin
    Result.X := DefaultColumns;
    Result.Y := DefaultRows;
  end;
  AnsiScreenWriter.Reset;
end;

function NcursesDisplay.GetColorCount: Integer;
begin
  case TermCap.Colors of
    Indexed8: Result := 8;
    Indexed16: Result := 16;
    Indexed256: Result := 256;
    Direct: Result := 256 * 256 * 256;
  else
    Result := 0;
  end;
end;

function NcursesDisplay.GetFontSize: TPoint;
begin
  Result := Con.GetFontSize;
end;

procedure NcursesDisplay.ClearScreen;
begin
  AnsiScreenWriter.ClearScreen;
end;

procedure NcursesDisplay.WriteCell(const Pos: TPoint; const Text: string; const Attr: TColorAttr;
  DoubleWidth: Boolean);
begin
  AnsiScreenWriter.WriteCell(Pos, Text, Attr, DoubleWidth);
end;

procedure NcursesDisplay.SetCaretPosition(const Pos: TPoint);
begin
  AnsiScreenWriter.SetCaretPosition(Pos);
end;

{ The caret is hidden for the size 0, very visible for 100 and normal for the sizes between. }
procedure NcursesDisplay.SetCaretSize(Size: Integer);
begin
  if Size <= 0 then
    Send(#27'[?25l')
  else if Size = 100 then
    Send(#27'[?12;25h')
  else
    Send(#27'[?12l' + #27'[?25h');
end;

procedure NcursesDisplay.Flush;
var
  Bytes: AnsiString;
begin
  Bytes := AnsiScreenWriter.Flush;
  Send(Bytes);
end;

{ NcursesInput }

{ The key that a control character gives. }
procedure ControlKeyEvent(K: Integer; var KeyDown: TKeyDownEvent);
var
  Separator: Char;
begin
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  case K of
    0, 28, 29, 30, 31:
      begin
        case K of
          0: Separator := '@';
          28: Separator := '\';
          29: Separator := ']';
          30: Separator := '^';
        else
          Separator := '_';
        end;
        KeyDown.KeyCode := Ord(Separator);
        KeyDown.ControlKeyState := kbLeftCtrl;
        KeyDown.Text[0] := Ord(Separator);
        KeyDown.TextLength := 1;
      end;
    8: KeyDown.KeyCode := kbBack;
    9: KeyDown.KeyCode := kbTab;
    10, 13: KeyDown.KeyCode := kbEnter;
    27: KeyDown.KeyCode := kbEsc;
  else
    begin
      KeyDown.KeyCode := K;
      KeyDown.ControlKeyState := kbLeftCtrl;
    end;
  end;
end;

constructor NcursesInput.Create(ACon: ConsoleCtl; ADisplay: NcursesDisplay; AState: PInputState; AMouse: Boolean);
begin
  inherited Create(ACon.FdIn);
  Con := ACon;
  State := AState;
  MouseEnabled := AMouse;
  In_ := NcursesInputGetter.Create(ACon.FdIn);
  EnterRawMode;
  TTermIO.KeyModsOn(Con);
  if MouseEnabled then
    TTermIO.MouseOn(Con);
end;

destructor NcursesInput.Destroy;
begin
  if MouseEnabled then
    TTermIO.MouseOff(Con);
  TTermIO.KeyModsOff(Con);
  TTermIO.ConsumeUnprocessedInput(Con, In_, State^);
  LeaveRawMode;
  In_.Free;
  inherited Destroy;
end;

{ Raw input without echo and without the translation of CR, as the curses calls raw, noecho and nonl give it. }
procedure NcursesInput.EnterRawMode;
var
  Mode: termios;
begin
  HaveSavedMode := False;
  if TCGetAttr(Con.FdIn, Mode) <> 0 then
    Exit;
  PTermiosRec(@SavedMode)^ := Mode;
  HaveSavedMode := True;
  Mode.c_lflag := Mode.c_lflag and not (ICANON or ISIG or IEXTEN or ECHO);
  Mode.c_iflag := Mode.c_iflag and not (IXON or BRKINT or PARMRK or ICRNL);
  Mode.c_oflag := Mode.c_oflag and not ONLCR;
  Mode.c_cc[VMIN] := 1;
  Mode.c_cc[VTIME] := 0;
  TCSetAttr(Con.FdIn, TCSANOW, Mode);
end;

procedure NcursesInput.LeaveRawMode;
begin
  if HaveSavedMode then
    TCSetAttr(Con.FdIn, TCSADRAIN, PTermiosRec(@SavedMode)^);
  HaveSavedMode := False;
end;

function NcursesInput.HasPendingEvents: Boolean;
begin
  Result := In_.PendingCount > 0;
end;

{ The next byte, without waiting. }
function NcursesInput.GetChNb: Integer;
var
  Saved: Integer;
begin
  Saved := In_.TimeoutMs;
  In_.TimeoutMs := 0;
  Result := In_.Get;
  In_.TimeoutMs := Saved;
end;

function IsLetterCode(Code: Integer): Boolean;
begin
  Result := (Code >= 0) and (Code < 128) and (Chr(Code) in ['A'..'Z', 'a'..'z']);
end;

{ ESC O letter, a key of the application keypad without a number: it is decoded as the CSI sequence of the same
  letter, which ParseCSIKey knows. }
function NcursesInput.TryLegacyKey(var Ev: TEvent): Boolean;
var
  Buf: TGetChBuf;
  Csi: TCSIData;
  C: Integer;
begin
  Result := False;
  Buf := TGetChBuf.Create(In_);
  if (Buf.Get = KeyEsc) and (Buf.Get = Ord('O')) then
  begin
    C := Buf.Get;
    if IsLetterCode(C) then
    begin
      Csi := Default(TCSIData);
      Csi.Length := 1;
      Csi.Values[0] := High(Cardinal);
      Csi.Terminator := Chr(C);
      if TTermIO.ParseCSIKey(Csi, Ev, State^) = Accepted then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
  Buf.Reject;
end;

{ A key that follows ESC at once is the key with Alt. }
procedure NcursesInput.DetectAlt(var Keys: TNcursesKeys; var Alt: Boolean);
var
  K: Integer;
begin
  K := GetChNb;
  if K <> -1 then
  begin
    Keys[0] := K;
    Alt := True;
  end;
end;

{ The bytes after the first one of a UTF-8 character. }
procedure NcursesInput.ReadUtf8Char(var Keys: TNcursesKeys; var NumKeys: Integer);
var
  I: Integer;
begin
  Inc(NumKeys, Integer(Utf8BytesLeft(Byte(Keys[0]))));
  if NumKeys > Length(Keys) then
    NumKeys := Length(Keys);
  for I := 1 to NumKeys - 1 do
  begin
    Keys[I] := In_.Get;
    if Keys[I] = -1 then
    begin
      NumKeys := I;
      Break;
    end;
  end;
end;

procedure NcursesInput.ParsePrintableChar(var Ev: TEvent; var Keys: TNcursesKeys; var NumKeys: Integer);
var
  I: Integer;
begin
  ReadUtf8Char(Keys, NumKeys);
  for I := 0 to NumKeys - 1 do
    Ev.KeyDown.Text[I] := Byte(Keys[I]);
  Ev.KeyDown.TextLength := NumKeys;
  { The character is representable in the code page, with some luck. }
  Ev.KeyDown.CharScan.CharCode := Ord(CpTranslator.FromUtf8(Ev.KeyDown.GetText));
  { Text must not trigger the keys of Ctrl. }
  if Ev.KeyDown.KeyCode <= kbCtrlZ then
    Ev.KeyDown.KeyCode := kbNoKey;
end;

function NcursesInput.GetEvent(var Ev: TEvent): Boolean;
var
  Buf: TGetChBuf;
  K, NumKeys: Integer;
  Keys: TNcursesKeys;
  Alt: Boolean;
begin
  Result := False;
  Buf := TGetChBuf.Create(In_);
  case TTermIO.ParseEvent(Buf, Ev, State^) of
    Rejected:
      Buf.Reject;
    Accepted:
      begin
        Result := True;
        Exit;
      end;
    Ignored:
      Exit;
  end;
  FillChar(Ev.KeyDown, SizeOf(Ev.KeyDown), 0);
  if TryLegacyKey(Ev) then
  begin
    Result := True;
    Exit;
  end;
  K := In_.Get;
  if K = -1 then
    Exit;
  FillChar(Keys, SizeOf(Keys), 0);
  Keys[0] := K;
  NumKeys := 1;
  Ev.What := evKeyDown;
  Alt := False;
  if Keys[0] = KeyEsc then
    DetectAlt(Keys, Alt);
  if Keys[0] < 32 then
    ControlKeyEvent(Keys[0], Ev.KeyDown)
  else if Keys[0] = 127 then
    Ev.KeyDown.KeyCode := kbBack;
  { A character that no table has is text. }
  if Ev.KeyDown.KeyCode = kbNoKey then
    ParsePrintableChar(Ev, Keys, NumKeys);
  if Alt then
  begin
    Ev.KeyDown.ControlKeyState := Ev.KeyDown.ControlKeyState or kbLeftAlt;
    TTermIO.NormalizeKey(Ev.KeyDown);
  end;
  if State^.BracketedPaste then
    Ev.KeyDown.ControlKeyState := Ev.KeyDown.ControlKeyState or kbPaste;
  Result := (Ev.KeyDown.KeyCode <> kbNoKey) or (Ev.KeyDown.TextLength <> 0);
end;

{ UnixClipboard }

type
  TArgList = array of AnsiString;
  TPtrList = array of PAnsiChar;

  TPrepareKind = (pkNone, pkWslCopy, pkWslPaste);

  { A program that copies or pastes: its arguments, the variable that must be set, the variables that it gets
    (name, value, name, value...) and the change of the text. }
  TClipCommand = record
    Argv: TArgList;
    RequiredEnv: AnsiString;
    CustomEnv: TArgList;
    Prepare: TPrepareKind;
  end;

  TProcessInfo = record
    Pid: TPid;
    Fd: cint;
  end;

function MakeCommand(const Argv: array of AnsiString; const Required: AnsiString; const Env: array of AnsiString;
  Prepare: TPrepareKind): TClipCommand;
var
  I: Integer;
begin
  SetLength(Result.Argv, Length(Argv));
  for I := 0 to High(Argv) do
    Result.Argv[I] := Argv[I];
  Result.RequiredEnv := Required;
  SetLength(Result.CustomEnv, Length(Env));
  for I := 0 to High(Env) do
    Result.CustomEnv[I] := Env[I];
  Result.Prepare := Prepare;
end;

{ The script for cmd.exe that prints the clipboard of Windows in UTF-16. }
function WslPasteScript: AnsiString;
var
  Pid: AnsiString;
begin
  Pid := IntToHex(Int64(fpGetPid), 8);
  Result :=
    '(FOR' +
    ' %i IN (%q%%TMP%%q% %q%%TEMP%%q% %q%%USERPROFILE%%q% \. .)' +
    ' DO' +
    ' set SCRIPT_PATH=%q%%~i\' + Pid + '%RANDOM%.vbs%q%' +
    ' && cmd /C' +
    ' echo' +
    ' WScript.StdOut.Write' +
    ' CreateObject(%q%HTMLFile%q%^).ParentWindow.ClipboardData.GetData(%q%Text%q%^)' +
    ' ^> ^%SCRIPT_PATH^%' +
    ' && (' +
    ' cmd /C' +
    ' cscript //NoLogo //B //U ^%SCRIPT_PATH^%' +
    ' ^&^& (del /Q ^%SCRIPT_PATH^% ^& exit ^)' +
    ' ^|^| (del /Q ^%SCRIPT_PATH^% ^& exit 1^)' +
    ' && exit' +
    ' || exit 1' +
    ')' +
    ')' +
    ' & exit 1';
end;

function CopyCommandCount: Integer;
begin
{$IFDEF DARWIN}
  Result := 1;
{$ELSE}
  Result := 4;
{$ENDIF}
end;

function CopyCommandAt(Index: Integer): TClipCommand;
begin
  case Index of
{$IFDEF DARWIN}
    0: Result := MakeCommand(['pbcopy'], '', [], pkNone);
{$ELSE}
    0: Result := MakeCommand(['/mnt/c/Windows/System32/clip.exe'], '', [], pkWslCopy);
    1: Result := MakeCommand(['wl-copy'], 'WAYLAND_DISPLAY', [], pkNone);
    2: Result := MakeCommand(['xsel', '--input', '--clipboard'], 'DISPLAY', [], pkNone);
    3: Result := MakeCommand(['xclip', '-in', '-selection', 'clipboard'], 'DISPLAY', [], pkNone);
{$ENDIF}
  end;
end;

function PasteCommandCount: Integer;
begin
{$IFDEF DARWIN}
  Result := 1;
{$ELSE}
  Result := 4;
{$ENDIF}
end;

function PasteCommandAt(Index: Integer): TClipCommand;
begin
  case Index of
{$IFDEF DARWIN}
    0: Result := MakeCommand(['pbpaste'], '', [], pkNone);
{$ELSE}
    0: Result := MakeCommand(['wl-paste', '--no-newline'], 'WAYLAND_DISPLAY', [], pkNone);
    1: Result := MakeCommand(['xsel', '--output', '--clipboard'], 'DISPLAY', [], pkNone);
    2: Result := MakeCommand(['xclip', '-out', '-selection', 'clipboard'], 'DISPLAY', [], pkNone);
    3: Result := MakeCommand(['/mnt/c/Windows/System32/cmd.exe', '/D', '/Q', '/C', WslPasteScript], '',
         ['WSLENV', 'q', 'q', '"'], pkWslPaste);
{$ENDIF}
  end;
end;

{ A regular file that others may run. }
function IsExecutableFile(const Path: AnsiString): Boolean;
var
  Info: Stat;
  Wanted: Cardinal;
begin
  Result := False;
  if fpStat(PAnsiChar(Path), Info) <> 0 then
    Exit;
  Wanted := Cardinal(S_IFREG or S_IXOTH);
  Result := (Cardinal(Info.st_mode) and Wanted) = Wanted;
end;

{ The path of the file that runs for a name: the name itself when it begins with a slash, else the first match along
  PATH. An empty element of PATH stands for the root directory, as the C++ builds the names. }
function FindExecutable(const Name: AnsiString): AnsiString;
var
  Dirs: AnsiString;
  Start, Stop: SizeInt;
  Candidate: AnsiString;
begin
  Result := '';
  if (Name <> '') and (Name[1] = '/') then
    Dirs := ''
  else
  begin
    Dirs := GetEnvironmentVariable('PATH');
    if Dirs = '' then
      Dirs := DefaultSearchPath;
  end;
  Start := 1;
  repeat
    Stop := Start;
    while (Stop <= Length(Dirs)) and (Dirs[Stop] <> ':') do
      Inc(Stop);
    Candidate := Copy(Dirs, Start, Stop - Start) + '/' + Name;
    if IsExecutableFile(Candidate) then
    begin
      Result := Candidate;
      Exit;
    end;
    if Stop > Length(Dirs) then
      Break;
    Start := Stop + 1;
  until False;
end;

procedure AppendText(var List: TArgList; const Text: AnsiString);
begin
  SetLength(List, Length(List) + 1);
  List[High(List)] := Text;
end;

{ The environment of the program: that of this process, with the variables of Extra (name, value, name, value...)
  set. Store keeps the texts that Ptrs points to. }
procedure BuildEnvironment(const Extra: array of AnsiString; out Store: TArgList; out Ptrs: TPtrList);
var
  I, J, EqPos: Integer;
  Entry, Key: AnsiString;
  Overridden: Boolean;
begin
  SetLength(Store, 0);
  for I := 1 to GetEnvironmentVariableCount do
  begin
    Entry := GetEnvironmentString(I);
    EqPos := Pos('=', Entry);
    Overridden := False;
    if EqPos > 1 then
    begin
      Key := Copy(Entry, 1, EqPos - 1);
      J := 0;
      while J < Length(Extra) do
      begin
        if Extra[J] = Key then
          Overridden := True;
        Inc(J, 2);
      end;
    end;
    if not Overridden then
      AppendText(Store, Entry);
  end;
  J := 0;
  while J + 1 < Length(Extra) do
  begin
    AppendText(Store, Extra[J] + '=' + Extra[J + 1]);
    Inc(J, 2);
  end;
  SetLength(Ptrs, Length(Store) + 1);
  for I := 0 to High(Store) do
    Ptrs[I] := PAnsiChar(Store[I]);
  Ptrs[Length(Store)] := nil;
end;

{ Starts the program with its input or its output on a pipe; Fd is the other end of the pipe. Pid is -1 when
  the program could not start. }
function RunSubprocess(const Argv: array of AnsiString; const Env: array of AnsiString;
  Writing: Boolean): TProcessInfo;
var
  Made: TFilDes;
  Path: AnsiString;
  ArgPtrs, EnvPtrs: TPtrList;
  EnvStore: TArgList;
  I: Integer;
  Child: TPid;
  NewIn, NewOut, Nul: cint;
begin
  Result.Pid := -1;
  Result.Fd := -1;
  if Length(Argv) = 0 then
    Exit;
  Path := FindExecutable(Argv[0]);
  if Path = '' then
    Exit;
  { Everything that the child needs is made before the fork. }
  SetLength(ArgPtrs, Length(Argv) + 1);
  for I := 0 to High(Argv) do
    ArgPtrs[I] := PAnsiChar(Argv[I]);
  ArgPtrs[Length(Argv)] := nil;
  BuildEnvironment(Env, EnvStore, EnvPtrs);
  if fpPipe(Made) = -1 then
    Exit;
  Child := fpFork;
  if Child = 0 then
  begin
    Nul := fpOpen('/dev/null', O_RDWR);
    if Writing then
    begin
      NewIn := Made[0];
      NewOut := Nul;
    end
    else
    begin
      NewIn := Nul;
      NewOut := Made[1];
    end;
    if (Nul <> -1) and (fpDup2(NewIn, 0) <> -1) and (fpDup2(NewOut, 1) <> -1) and (fpDup2(Nul, 2) <> -1) and
       (fpClose(Made[0]) <> -1) and (fpClose(Made[1]) <> -1) and (fpClose(Nul) <> -1) then
      fpExecVE(PAnsiChar(Path), @ArgPtrs[0], @EnvPtrs[0]);
    fpExit(127);
  end;
  if Child > 0 then
  begin
    if Writing then
    begin
      fpClose(Made[0]);
      Result.Fd := Made[1];
    end
    else
    begin
      fpClose(Made[1]);
      Result.Fd := Made[0];
    end;
    Result.Pid := Child;
    Exit;
  end;
  fpClose(Made[0]);
  fpClose(Made[1]);
end;

{ Closes the pipe and waits for the program; True when it ended with the status 0. }
function CloseSubprocess(const Proc: TProcessInfo): Boolean;
var
  Status: cint;
  Waited: TPid;
begin
  fpClose(Proc.Fd);
  Status := 0;
  Waited := fpWaitPid(Proc.Pid, @Status, 0);
  Result := (Waited > 0) and ((Status and $7F) = 0) and (((Status shr 8) and $FF) = 0);
end;

{ Reads the pipe until its end or until nothing comes for TimeoutMs. False when the pipe cannot be read without
  blocking. Incomplete tells that the time ran out. }
function ReadPipe(Fd: cint; TimeoutMs: Integer; out Data: AnsiString; out Incomplete: Boolean): Boolean;
var
  Flags: cint;
  Chunk: array[0..ChunkSize - 1] of Byte;
  Got: TSsize;
  Total, PollResult: Integer;
  Wait: TPollFD;
begin
  Data := '';
  Incomplete := False;
  Result := False;
  Flags := fpFcntl(Fd, F_GETFL);
  if Flags = -1 then
    Exit;
  if fpFcntl(Fd, F_SETFL, Flags or O_NONBLOCK) = -1 then
    Exit;
  Result := True;
  Total := 0;
  PollResult := -1;
  repeat
    repeat
      Got := fpRead(Fd, PAnsiChar(@Chunk[0]), SizeOf(Chunk));
      if Got > 0 then
      begin
        SetLength(Data, Total + Integer(Got));
        Move(Chunk[0], Data[Total + 1], Integer(Got));
        Inc(Total, Integer(Got));
      end;
    until Got <= 0;
    if (Got = 0) or ((Got < 0) and (fpGetErrno <> ErrWouldBlock)) then
      Break;
    Wait.fd := Fd;
    Wait.events := POLLIN;
    Wait.revents := 0;
    PollResult := FpPoll(@Wait, 1, TimeoutMs);
    if (PollResult <= 0) or ((Wait.revents and POLLIN) = 0) then
      Break;
  until False;
  Incomplete := PollResult = 0;
end;

{ Writes the text to the pipe, waiting for TimeoutMs when it is full. Success tells that all the text was
  written. Incomplete tells that the time ran out. }
function WritePipe(Fd: cint; const Text: AnsiString; TimeoutMs: Integer; out Incomplete: Boolean): Boolean;
var
  Flags: cint;
  Written: Integer;
  Got: TSsize;
  PollResult: Integer;
  Wait: TPollFD;
begin
  Incomplete := False;
  Result := False;
  Flags := fpFcntl(Fd, F_GETFL);
  if Flags = -1 then
    Exit;
  if fpFcntl(Fd, F_SETFL, Flags or O_NONBLOCK) = -1 then
    Exit;
  Written := 0;
  PollResult := -1;
  repeat
    repeat
      Got := 0;
      if Written < Length(Text) then
        Got := fpWrite(Fd, PAnsiChar(Text) + Written, SizeUInt(Length(Text) - Written));
      if Got > 0 then
        Inc(Written, Integer(Got));
    until Got <= 0;
    if (Written >= Length(Text)) or (Got = 0) or ((Got < 0) and (fpGetErrno <> ErrWouldBlock)) then
      Break;
    Wait.fd := Fd;
    Wait.events := POLLOUT;
    Wait.revents := 0;
    PollResult := FpPoll(@Wait, 1, TimeoutMs);
    if (PollResult <= 0) or ((Wait.revents and POLLOUT) = 0) then
      Break;
  until False;
  Result := Written = Length(Text);
  Incomplete := PollResult = 0;
end;

{ The UTF-16 text that CScript prints, as UTF-8. A lone surrogate becomes U+FFFD. }
function Utf16LeToUtf8(const Raw: AnsiString): AnsiString;
var
  Units, I: Integer;
  K: SizeInt;
  First, Second: Word;
  Pair: TUtf16Pair;
  Bytes: TUtf8Bytes;
  Count: SizeInt;
begin
  Result := '';
  Units := Length(Raw) div 2;
  I := 0;
  while I < Units do
  begin
    First := Word(Ord(Raw[2 * I + 1])) or (Word(Ord(Raw[2 * I + 2])) shl 8);
    Inc(I);
    Second := 0;
    if I < Units then
      Second := Word(Ord(Raw[2 * I + 1])) or (Word(Ord(Raw[2 * I + 2])) shl 8);
    if (First >= $D800) and (First <= $DBFF) and (Second >= $DC00) and (Second <= $DFFF) then
    begin
      Pair[0] := First;
      Pair[1] := Second;
      Inc(I);
      Count := Utf16To8(Pair, Bytes);
    end
    else if (First >= $D800) and (First <= $DFFF) then
      Count := Utf32To8($FFFD, Bytes)
    else
    begin
      Pair[0] := First;
      Pair[1] := 0;
      Count := Utf16To8(Pair, Bytes);
    end;
    for K := 0 to Count - 1 do
      Result := Result + Chr(Bytes[K]);
  end;
end;

function CommandIsAvailable(const Cmd: TClipCommand): Boolean;
var
  Value: string;
begin
  Result := True;
  if Cmd.RequiredEnv <> '' then
  begin
    Value := GetEnv(Cmd.RequiredEnv, '');
    Result := Value <> '';
  end;
  if Result then
    Result := UnixClipboard.ExecutableExists(Cmd.Argv[0]);
end;

class function UnixClipboard.ExecutableExists(const Name: AnsiString): Boolean;
begin
  Result := FindExecutable(Name) <> '';
end;

class function UnixClipboard.ReadSubprocess(const Argv: array of AnsiString; const Env: array of AnsiString;
  TimeoutMs: Integer; out Data: AnsiString): Boolean;
var
  Proc: TProcessInfo;
  Opened, Incomplete, Exited: Boolean;
begin
  Data := '';
  Result := False;
  Proc := RunSubprocess(Argv, Env, False);
  if Proc.Pid = -1 then
    Exit;
  Opened := ReadPipe(Proc.Fd, TimeoutMs, Data, Incomplete);
  if Incomplete then
    fpKill(Proc.Pid, SIGKILL);
  Exited := CloseSubprocess(Proc);
  Result := Opened and (Exited or (Length(Data) > 0));
  if not Result then
    Data := '';
end;

class function UnixClipboard.WriteSubprocess(const Argv: array of AnsiString; const Text: AnsiString;
  TimeoutMs: Integer): Boolean;
var
  Proc: TProcessInfo;
  Complete, Incomplete, Exited: Boolean;
begin
  Result := False;
  Proc := RunSubprocess(Argv, [], True);
  if Proc.Pid = -1 then
    Exit;
  Complete := WritePipe(Proc.Fd, Text, TimeoutMs, Incomplete);
  if Incomplete then
    fpKill(Proc.Pid, SIGKILL);
  Exited := CloseSubprocess(Proc);
  Result := Exited and Complete;
end;

class function UnixClipboard.SetClipboardText(const Text: AnsiString): Boolean;
var
  I: Integer;
  Cmd: TClipCommand;
  Payload: AnsiString;
begin
  Result := False;
  if not Enabled then
    Exit;
  for I := 0 to CopyCommandCount - 1 do
  begin
    Cmd := CopyCommandAt(I);
    if CommandIsAvailable(Cmd) then
    begin
      Payload := Text;
      { A null character at the end is the way around a defect of clip.exe. }
      if Cmd.Prepare = pkWslCopy then
        Payload := Payload + #0;
      Result := WriteSubprocess(Cmd.Argv, Payload, ClipboardTimeoutMs);
      Exit;
    end;
  end;
end;

class function UnixClipboard.RequestClipboardText(Accept: TTextProc): Boolean;
var
  I: Integer;
  Cmd: TClipCommand;
  Data: AnsiString;
begin
  Result := False;
  if not Enabled then
    Exit;
  for I := 0 to PasteCommandCount - 1 do
  begin
    Cmd := PasteCommandAt(I);
    if CommandIsAvailable(Cmd) then
    begin
      if ReadSubprocess(Cmd.Argv, Cmd.CustomEnv, ClipboardTimeoutMs, Data) then
      begin
        if Cmd.Prepare = pkWslPaste then
          Data := Utf16LeToUtf8(Data);
        Accept(Copy(Data, 1, 255));
        Result := True;
      end;
      Exit;
    end;
  end;
end;

{ UnixConsoleAdapter }

constructor UnixConsoleAdapter.Create(ADisplay: DisplayAdapter; AInput: InputAdapter; ACon: ConsoleCtl;
  ADisplayBuf: DisplayBuffer; AInputState: PInputState; ASigwinch: SigwinchHandler);
begin
  inherited Create(ADisplay, [AInput, ASigwinch]);
  ErrRedir := StderrRedirector.Create;
  Con := ACon;
  DisplayBuf := ADisplayBuf;
  InputState := AInputState;
  Sigwinch := ASigwinch;
  Input := AInput;
  { A change of the size that no signal told about (after SIGTSTP, for example) is not missed. }
  if Sigwinch <> nil then
    Sigwinch.Signal;
end;

class function UnixConsoleAdapter.Make(ACon: ConsoleCtl; ADisplayBuf: DisplayBuffer; AInputState: PInputState;
  ADisplay: DisplayAdapter; AInput: InputAdapter): UnixConsoleAdapter;
var
  Handler: SigwinchHandler;
begin
  Handler := SigwinchHandler.Make;
  Result := UnixConsoleAdapter.Create(ADisplay, AInput, ACon, ADisplayBuf, AInputState, Handler);
end;

destructor UnixConsoleAdapter.Destroy;
begin
  Sigwinch.Free;
  Input.Free;
  Display.Free;
  Dispose(InputState);
  ErrRedir.Free;
  inherited Destroy;
end;

function UnixConsoleAdapter.SetClipboardText(const Text: AnsiString): Boolean;
begin
  if UnixClipboard.SetClipboardText(Text) then
  begin
    Result := True;
    Exit;
  end;
  if TTermIO.SetClipboardText(Con, Text, InputState^) then
  begin
    Result := True;
    Exit;
  end;
  { On failure an OSC sequence was printed that not every terminal can handle: the screen is drawn again in case
    it has been spoiled. }
  DisplayBuf.RedrawScreen(Display);
  Result := False;
end;

function UnixConsoleAdapter.RequestClipboardText(Accept: TTextProc): Boolean;
begin
  if UnixClipboard.RequestClipboardText(Accept) then
  begin
    Result := True;
    Exit;
  end;
  Result := TTermIO.RequestClipboardText(Con, Accept, InputState^);
end;

{ Platform }

constructor Platform.Create;
begin
  inherited Create;
  Waiter := TEventWaiter.Create;
  DisplayBuf := DisplayBuffer.Create(GetEnv('TVISION_MAX_FPS', -1));
  DummyDisplay := DisplayAdapter.Create;
  DummyConsole := ConsoleAdapter.Create(DummyDisplay, []);
  Console := DummyConsole;
  Lock := SignalSafeMutexState.Create;
  AlwaysFlushScreen := GetEnv('TVISION_MAX_FPS', 0) < 0;
end;

destructor Platform.Destroy;
begin
  RestoreConsole;
  DummyConsole.Free;
  DummyDisplay.Free;
  DisplayBuf.Free;
  Waiter.Free;
  Lock.Free;
  inherited Destroy;
end;

class function Platform.GetInstance: Platform;
begin
  if Instance = nil then
    Instance := Platform.Create;
  Result := Instance;
end;

class procedure Platform.DestroyInstance;
var
  Old: Platform;
begin
  Old := Instance;
  Instance := nil;
  Old.Free;
end;

function Platform.CreateConsole: ConsoleAdapter;
var
  Ctl: ConsoleCtl;
  State: PInputState;
  Display: NcursesDisplay;
  Input: NcursesInput;
begin
  Ctl := ConsoleCtl.GetInstance;
  New(State);
  FillChar(State^, SizeOf(State^), 0);
  Display := NcursesDisplay.Create(Ctl);
  Input := NcursesInput.Create(Ctl, Display, State, True);
  Result := UnixConsoleAdapter.Make(Ctl, DisplayBuf, State, Display, Input);
end;

procedure Platform.SetUpConsole(var C: ConsoleAdapter);
var
  I: Integer;
begin
  if C = DummyConsole then
  begin
    C := CreateConsole;
    SignalHandler.Enable(@Platform.SignalCallback);
    for I := 0 to High(C.Sources) do
      if C.Sources[I] <> nil then
        Waiter.AddSource(C.Sources[I]);
  end;
end;

procedure Platform.RestoreConsole(var C: ConsoleAdapter);
var
  I: Integer;
begin
  if C <> DummyConsole then
  begin
    DisplayBuf.FlushScreen(C.Display);
    for I := 0 to High(C.Sources) do
      if C.Sources[I] <> nil then
        Waiter.RemoveSource(C.Sources[I]);
    SignalHandler.Disable;
    C.Free;
    C := DummyConsole;
  end;
end;

procedure Platform.SetUpConsole;
begin
  Lock.Acquire;
  try
    SetUpConsole(Console);
  finally
    Lock.Release;
  end;
end;

procedure Platform.RestoreConsole;
begin
  Lock.Acquire;
  try
    RestoreConsole(Console);
  finally
    Lock.Release;
  end;
end;

function Platform.IsSetUp: Boolean;
begin
  Result := Console <> DummyConsole;
end;

procedure Platform.CheckConsole;
begin
  Lock.Acquire;
  try
    if not Console.IsAlive then
    begin
      { The console likely crashed. }
      RestoreConsole(Console);
      SetUpConsole(Console);
    end;
  finally
    Lock.Release;
  end;
end;

function Platform.GetEvent(var Ev: TEvent): Boolean;
begin
  Result := Waiter.GetEvent(Ev);
end;

procedure Platform.WaitForEvents(Ms: Integer);
var
  WaitTimeout, FlushTimeout: Integer;
begin
  CheckConsole;
  WaitTimeout := Ms;
  { When the display buffer has changes that wait, the wait ends in time to flush them. }
  FlushTimeout := DisplayBuf.TimeUntilPendingFlushMs;
  if Ms < 0 then
    WaitTimeout := FlushTimeout
  else if FlushTimeout >= 0 then
    WaitTimeout := SmallerOf(Ms, FlushTimeout);
  Waiter.WaitForEvents(WaitTimeout);
end;

procedure Platform.InterruptEventWait;
begin
  Waiter.InterruptEventWait;
end;

{ The size of the caret is kept in the range 1 to 100, as TScreen expects. }
function Platform.GetCaretSize: Integer;
begin
  Result := SmallerOf(LargerOf(DisplayBuf.CaretSize, 1), 100);
end;

function Platform.IsCaretVisible: Boolean;
begin
  Result := DisplayBuf.CaretSize > 0;
end;

procedure Platform.ClearScreen;
begin
  Lock.Acquire;
  try
    DisplayBuf.ClearScreen(Console.Display);
  finally
    Lock.Release;
  end;
end;

function Platform.GetScreenRows: Integer;
begin
  Result := DisplayBuf.Size.Y;
end;

function Platform.GetScreenCols: Integer;
begin
  Result := DisplayBuf.Size.X;
end;

procedure Platform.SetCaretPosition(X, Y: Integer);
begin
  DisplayBuf.SetCaretPosition(X, Y);
end;

function Platform.GetScreenMode: Word;
var
  ColorCount: Integer;
  FontSize: TPoint;
begin
  Lock.Acquire;
  try
    ColorCount := Console.Display.GetColorCount;
    FontSize := Console.Display.GetFontSize;
  finally
    Lock.Release;
  end;
  if ColorCount = 0 then
    Result := TDisplay.smMono
  else
    Result := TDisplay.smCO80;
  if ColorCount >= 256 then
    Result := Result or TDisplay.smColor256;
  if ColorCount >= 256 * 256 * 256 then
    Result := Result or TDisplay.smColorHigh;
  if (FontSize.X > 0) and (FontSize.Y > 0) and (FontSize.X >= FontSize.Y) then
    Result := Result or TDisplay.smFont8x8;
end;

procedure Platform.SetCaretSize(Size: Integer);
begin
  DisplayBuf.SetCaretSize(Size);
end;

procedure Platform.ScreenWrite(X, Y: Integer; Buf: TvDispBuf.PScreenCell; Len: Integer);
begin
  DisplayBuf.ScreenWrite(X, Y, Buf, Len);
end;

procedure Platform.FlushScreen;
begin
  Lock.Acquire;
  try
    DisplayBuf.FlushScreen(Console.Display);
  finally
    Lock.Release;
  end;
end;

function Platform.ReloadScreenInfo: TvDispBuf.PScreenCell;
begin
  Lock.Acquire;
  try
    Result := DisplayBuf.ReloadScreenInfo(Console.Display);
  finally
    Lock.Release;
  end;
end;

procedure Platform.FreeScreenBuffer;
begin
  DisplayBuf.Reset;
end;

function Platform.SetClipboardText(const Text: AnsiString): Boolean;
begin
  Lock.Acquire;
  try
    Result := Console.SetClipboardText(Text);
  finally
    Lock.Release;
  end;
end;

function Platform.RequestClipboardText(Accept: TTextProc): Boolean;
begin
  Lock.Acquire;
  try
    Result := Console.RequestClipboardText(Accept);
  finally
    Lock.Release;
  end;
end;

{ Called by the signal handler: the console is given back when a signal comes and taken again when the program
  goes on. }
class procedure Platform.SignalCallback(Enter: Boolean);
begin
  if (Instance <> nil) and (not Instance.Lock.LockedByCurrentThread) then
  begin
    if Enter then
      Instance.RestoreConsole
    else
      Instance.SetUpConsole;
  end;
end;

{ TUnixEventBackend }

constructor TUnixEventBackend.Create;
begin
  inherited Create;
  EventCount := 0;
  InsertState := True;
  FillChar(LastMouse, SizeOf(LastMouse), 0);
end;

{ Turbo Vision only checks whether this is not zero. }
function TUnixEventBackend.GetButtonCount: Cardinal;
begin
  Result := 2;
end;

procedure TUnixEventBackend.MouseGetState(var Mouse: TMouseEventType);
begin
  Mouse := LastMouse;
end;

{ Nothing is dropped from the events that were read. }
procedure TUnixEventBackend.ClearPendingEvent;
begin
end;

function TUnixEventBackend.ScreenWidth: Integer;
begin
  Result := Platform.GetInstance.GetScreenCols;
end;

function TUnixEventBackend.ScreenHeight: Integer;
begin
  Result := Platform.GetInstance.GetScreenRows;
end;

{ Takes the oldest event of the queue that is a mouse event when Mouse is True and another event otherwise. }
function TUnixEventBackend.GetPendingEvent(var Ev: TEvent; Mouse: Boolean): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  for I := 0 to EventCount - 1 do
    if ((EventQ[I].What and evMouse) <> 0) = Mouse then
    begin
      Ev := EventQ[I];
      J := I;
      while J + 1 < EventCount do
      begin
        EventQ[J] := EventQ[J + 1];
        Inc(J);
      end;
      Dec(EventCount);
      Result := True;
      Exit;
    end;
end;

{ No more events are read until the queue is empty. }
procedure TUnixEventBackend.ReadEvents;
var
  Source: Platform;
begin
  if EventCount = 0 then
  begin
    Source := Platform.GetInstance;
    while (EventCount < eventQSize) and Source.GetEvent(EventQ[EventCount]) do
      Inc(EventCount);
  end;
end;

function TUnixEventBackend.GetMouseEvent(var Mouse: TMouseEventType): Boolean;
var
  Ev: TEvent;
begin
  FillChar(Ev, SizeOf(Ev), 0);
  Result := GetPendingEvent(Ev, True);
  if Result then
  begin
    Mouse := Ev.Mouse;
    LastMouse := Ev.Mouse;
  end;
end;

function TUnixEventBackend.GetKeyEvent(var Ev: TEvent): Boolean;
begin
  Result := False;
  ReadEvents;
  if GetPendingEvent(Ev, False) then
  begin
    if (Ev.What and evKeyboard) <> 0 then
    begin
      if Ev.KeyDown.KeyCode = kbIns then
        InsertState := not InsertState;
      if InsertState then
        Ev.KeyDown.ControlKeyState := Ev.KeyDown.ControlKeyState or kbInsState;
    end;
    Result := Ev.What <> evNothing;
  end;
end;

{ The screen is flushed once for every time that all events have been processed, and only when the wait blocks. }
procedure TUnixEventBackend.WaitForEvents(TimeoutMs: Integer);
begin
  if EventCount = 0 then
  begin
    Platform.GetInstance.FlushScreen;
    Platform.GetInstance.WaitForEvents(TimeoutMs);
  end;
end;

procedure TUnixEventBackend.InterruptEventWait;
begin
  Platform.GetInstance.InterruptEventWait;
end;

{ TUnixScreenBackend }

procedure TUnixScreenBackend.SetUpConsole;
begin
  Platform.GetInstance.SetUpConsole;
end;

procedure TUnixScreenBackend.RestoreConsole;
begin
  Platform.GetInstance.RestoreConsole;
end;

function TUnixScreenBackend.GetCaretSize: Word;
begin
  Result := Word(Platform.GetInstance.GetCaretSize);
end;

procedure TUnixScreenBackend.SetCaretSize(Size: Word);
begin
  Platform.GetInstance.SetCaretSize(Size);
end;

procedure TUnixScreenBackend.ClearScreen(W, H: Byte);
begin
  Platform.GetInstance.ClearScreen;
end;

function TUnixScreenBackend.GetScreenRows: Word;
begin
  Result := Word(Platform.GetInstance.GetScreenRows);
end;

function TUnixScreenBackend.GetScreenCols: Word;
begin
  Result := Word(Platform.GetInstance.GetScreenCols);
end;

function TUnixScreenBackend.GetScreenMode: Word;
begin
  Result := Platform.GetInstance.GetScreenMode;
end;

function TUnixScreenBackend.AllocateScreenBuffer: TvDrawBuf.PScreenCell;
begin
  Result := TvDrawBuf.PScreenCell(Platform.GetInstance.ReloadScreenInfo);
end;

procedure TUnixScreenBackend.FreeScreenBuffer(Buffer: TvDrawBuf.PScreenCell);
begin
  Platform.GetInstance.FreeScreenBuffer;
end;

procedure TUnixScreenBackend.FlushScreen;
begin
  Platform.GetInstance.FlushScreen;
end;

{ TUnixClipboardBackend }

function TUnixClipboardBackend.SetText(const Text: string): Boolean;
begin
  Result := Platform.GetInstance.SetClipboardText(Text);
end;

function TUnixClipboardBackend.RequestText(Accept: TTextProc): Boolean;
begin
  Result := Platform.GetInstance.RequestClipboardText(Accept);
end;

{ The hooks of the views }

procedure UnixScreenWrite(X, Y: Integer; Buf: TvDrawBuf.PScreenCell; Count: Integer);
begin
  Platform.GetInstance.ScreenWrite(X, Y, TvDispBuf.PScreenCell(Buf), Count);
  if AlwaysFlushScreen then
    Platform.GetInstance.FlushScreen;
end;

procedure UnixCaretPosition(X, Y: Integer);
begin
  Platform.GetInstance.SetCaretPosition(X, Y);
end;

initialization
  UnixClipboard.Enabled := True;
  AlwaysFlushScreen := False;

end.
