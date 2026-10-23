{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/views.h (the constants, TCommandSet, TPalette, TView, TGroup),
  include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h, include/tvision/tstrview.h,
  include/tvision/tspan.h, source/tvision/tview.cpp, source/tvision/tgroup.cpp, source/tvision/tcmdset.cpp,
  source/tvision/tvwrite.cpp, source/tvision/tvexposd.cpp, source/tvision/tvcursor.cpp, source/tvision/tgrmv.cpp
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe, and the
  global variables below belong to that thread. A modal loop (ExecView, Execute) reads its events through GetEvent
  of the owners, up to the root of the views, and so reaches the wait for events of that root.

  Only the branch of the files for the flat memory model is translated. The classes of views.h that are not part
  of this unit are TFrame, TScrollBar, TScroller, TListViewer and TWindow with TWindowInit. The members read,
  write, build and streamableName of TView and TGroup, and the constructors with StreamableInit, belong to a later
  unit.

  A class that has no unit yet is reached through a hook:
    - message() sends a message to a view; MessageHook stands for it and does nothing while it is nil;
    - THardwareInfo::setCaretPosition and THardwareInfo::screenWrite are CaretPositionHook and ScreenWriteHook,
      and the size of the caret is set through TDisplay.Backend;
    - TProgram::eventTimeoutMs is EventTimeoutMs;
    - the buffers of TVMemMgr are blocks of the heap;
    - strwidth is the width of TText of TvUtf8.

  The members of TView that are private in the C++ (moveGrow, change, writeView, resizeBalance) are private here.
  The nested enumerations phaseType and selectMode are TPhaseType and TSelectMode, and a TPalette is a class
  because the C++ returns it by reference. The operators of TCommandSet are: += and -= are AddAssign and SubAssign,
  &= and |= are AndAssign and OrAssign, & is * and | is +. The table of masks is a shift. A function pointer of
  the C++ that is passed to forEach and firstThat is a TForEachFunc or a TFirstThatFunc. The buffer of a text is
  a pointer with a size. A buffer of ushort is a Pointer, a buffer of TScreenCell is a PScreenCell. At and IndexOf
  count from 1 at the first subview, and 0 stands for no subview. }
unit TvViews;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvEvents, TvObjs, TvColors, TvCell, TvDrawBuf, TvTimer;

const
  { Standard command codes }
  cmValid = Word(0);
  cmQuit = Word(1);
  cmError = Word(2);
  cmMenu = Word(3);
  cmClose = Word(4);
  cmZoom = Word(5);
  cmResize = Word(6);
  cmNext = Word(7);
  cmPrev = Word(8);
  cmHelp = Word(9);

  { TDialog standard commands }
  cmOK = Word(10);
  cmCancel = Word(11);
  cmYes = Word(12);
  cmNo = Word(13);
  cmDefault = Word(14);

  { Standard application commands }
  cmNew = Word(30);
  cmOpen = Word(31);
  cmSave = Word(32);
  cmSaveAs = Word(33);
  cmSaveAll = Word(34);
  cmChDir = Word(35);
  cmDosShell = Word(36);
  cmCloseAll = Word(37);

  { TView state masks }
  sfVisible = Word($001);
  sfCursorVis = Word($002);
  sfCursorIns = Word($004);
  sfShadow = Word($008);
  sfActive = Word($010);
  sfSelected = Word($020);
  sfFocused = Word($040);
  sfDragging = Word($080);
  sfDisabled = Word($100);
  sfModal = Word($200);
  sfDefault = Word($400);
  sfExposed = Word($800);

  { TView option masks }
  ofSelectable = Word($001);
  ofTopSelect = Word($002);
  ofFirstClick = Word($004);
  ofFramed = Word($008);
  ofPreProcess = Word($010);
  ofPostProcess = Word($020);
  ofBuffered = Word($040);
  ofTileable = Word($080);
  ofCenterX = Word($100);
  ofCenterY = Word($200);
  ofCentered = Word($300);
  ofValidate = Word($400);

  { TView grow mode masks }
  gfGrowLoX = Word($01);
  gfGrowLoY = Word($02);
  gfGrowHiX = Word($04);
  gfGrowHiY = Word($08);
  gfGrowAll = Word($0F);
  gfGrowRel = Word($10);
  gfFixed = Word($20);

  { TView drag mode masks }
  dmDragMove = Word($01);
  dmDragGrow = Word($02);
  dmDragGrowLeft = Word($04);
  dmLimitLoX = Word($10);
  dmLimitLoY = Word($20);
  dmLimitHiX = Word($40);
  dmLimitHiY = Word($80);
  dmLimitAll = Word(dmLimitLoX or dmLimitLoY or dmLimitHiX or dmLimitHiY);

  { TView help context codes }
  hcNoContext = Word(0);
  hcDragging = Word(1);

  { TScrollBar part codes }
  sbLeftArrow = Word(0);
  sbRightArrow = Word(1);
  sbPageLeft = Word(2);
  sbPageRight = Word(3);
  sbUpArrow = Word(4);
  sbDownArrow = Word(5);
  sbPageUp = Word(6);
  sbPageDown = Word(7);
  sbIndicator = Word(8);

  { TScrollBar options for TWindow.StandardScrollBar }
  sbHorizontal = Word($000);
  sbVertical = Word($001);
  sbHandleKeyboard = Word($002);

  { TWindow flags masks }
  wfMove = Word($01);
  wfGrow = Word($02);
  wfClose = Word($04);
  wfZoom = Word($08);

  { TView inhibit flags }
  noMenuBar = Word($0001);
  noDeskTop = Word($0002);
  noStatusLine = Word($0004);
  noBackground = Word($0008);
  noFrame = Word($0010);
  noViewer = Word($0020);
  noHistory = Word($0040);

  { TWindow number constants }
  wnNoNumber = Word(0);

  { TWindow palette entries }
  wpBlueWindow = Word(0);
  wpCyanWindow = Word(1);
  wpGrayWindow = Word(2);

  { Application command codes }
  cmCut = Word(20);
  cmCopy = Word(21);
  cmPaste = Word(22);
  cmUndo = Word(23);
  cmClear = Word(24);
  cmTile = Word(25);
  cmCascade = Word(26);
  cmRedo = Word(27);

  { Standard messages }
  cmReceivedFocus = Word(50);
  cmReleasedFocus = Word(51);
  cmCommandSetChanged = Word(52);
  cmTimerExpired = Word(58);

  { TScrollBar messages }
  cmScrollBarChanged = Word(53);
  cmScrollBarClicked = Word(54);

  { TWindow select messages }
  cmSelectWindowNum = Word(55);

  { TListViewer messages }
  cmListItemSelected = Word(56);

  { TProgram messages }
  cmScreenChanged = Word(57);

  { Event masks }
  positionalEvents = Word(evMouse and not evMouseWheel);
  focusedEvents = Word(evKeyboard or evCommand);

type
  { A set of the commands 0 to 255. Create gives the empty set; a variable of this type that is not set by Create
    or by an assignment has an undefined value. A command outside 0 to 255 is not in any set, and adding it
    changes nothing. }
  TCommandSet = record
  private
    Cmds: array[0..31] of Byte;
    class function Loc(Cmd: Integer): Cardinal; static;
    class function Mask(Cmd: Integer): Byte; static;
  public
    class function Create: TCommandSet; static;
    function Has(Cmd: Integer): Boolean;
    procedure DisableCmd(Cmd: Integer); overload;
    procedure EnableCmd(Cmd: Integer); overload;
    procedure DisableCmd(const Tc: TCommandSet); overload;
    procedure EnableCmd(const Tc: TCommandSet); overload;
    procedure AddAssign(Cmd: Integer); overload;
    procedure SubAssign(Cmd: Integer); overload;
    procedure AddAssign(const Tc: TCommandSet); overload;
    procedure SubAssign(const Tc: TCommandSet); overload;
    function IsEmpty: Boolean;
    function AndAssign(const Tc: TCommandSet): TCommandSet;
    function OrAssign(const Tc: TCommandSet): TCommandSet;
    { The intersection (the operator & of the C++) and the union (the operator |). }
    class operator *(const One, Two: TCommandSet): TCommandSet;
    class operator +(const One, Two: TCommandSet): TCommandSet;
    class operator =(const One, Two: TCommandSet): Boolean;
    class operator <>(const One, Two: TCommandSet): Boolean;
  end;

  PColorAttr = ^TColorAttr;

  { The colors of a view. For a view, Data[0] is the number of entries and Data[1..] are indices into the palette
    of the owner (a TColorAttr holds only the number). For the topmost palette the entries are the actual color
    attributes. }
  TPalette = class
  private
    function GetItem(Index: Integer): TColorAttr;
    procedure SetItem(Index: Integer; const Value: TColorAttr);
  public
    Data: PColorAttr;
    { The first ALen bytes of Colors are the entries. }
    constructor Create(const Colors: string; ALen: Word); overload;
    constructor Create(const Colors: array of TColorAttr); overload;
    constructor Create(Other: TPalette); overload;
    destructor Destroy; override;
    procedure Assign(Other: TPalette);
    property Items[Index: Integer]: TColorAttr read GetItem write SetItem; default;
  end;

  TView = class;
  TGroup = class;

  TPhaseType = (phFocused, phPreProcess, phPostProcess);
  TSelectMode = (normalSelect, enterSelect, leaveSelect);

  { Called for each subview by ForEach. }
  TForEachFunc = procedure(P: TView; Args: Pointer);
  { Called for subviews by FirstThat until it returns True. }
  TFirstThatFunc = function(P: TView; Args: Pointer): Boolean;

  TView = class(TvObject)
  private
    ResizeBalance: TPoint;
    procedure MoveGrow(P, S: TPoint; var Limits: TRect; MinSize, MaxSize: TPoint; Mode: Byte);
    procedure Change(Mode: Byte; Delta: TPoint; var P, S: TPoint; CtrlState: Word);
    { Writes Count cells of B, starting at the column X of the row Y of the view. }
    procedure WriteView(X, Y, Count: SmallInt; B: Pointer); overload;
    procedure WriteView(X, Y, Count: SmallInt; B: PScreenCell); overload;
  public
    Next: TView;
    Size: TPoint;
    Options: Word;
    EventMask: Word;
    State: Word;
    Origin, Cursor: TPoint;
    GrowMode, DragMode: Byte;
    HelpCtx: Word;
    Owner: TGroup;
    class var CommandSetChanged: Boolean;
    class var CurCommandSet: TCommandSet;
    class var ShowMarkers: Boolean;
    class var ErrorAttr: TColorAttr;

    constructor Create(const Bounds: TRect);
    destructor Destroy; override;
    procedure SizeLimits(var Min, Max: TPoint); virtual;
    function GetBounds: TRect;
    function GetExtent: TRect;
    function GetClipRect: TRect;
    function MouseInView(Mouse: TPoint): Boolean;
    function ContainsMouse(var Event: TEvent): Boolean;
    procedure Locate(var Bounds: TRect);
    procedure DragView(var Event: TEvent; Mode: Byte; var Limits: TRect; MinSize, MaxSize: TPoint); virtual;
    procedure CalcBounds(var Bounds: TRect; Delta: TPoint); virtual;
    procedure ChangeBounds(const Bounds: TRect); virtual;
    procedure GrowTo(X, Y: SmallInt);
    procedure MoveTo(X, Y: SmallInt);
    procedure SetBounds(const Bounds: TRect);
    function GetHelpCtx: Word; virtual;
    function Valid(Command: Word): Boolean; virtual;
    procedure Hide;
    procedure Show;
    procedure Draw; virtual;
    procedure DrawView;
    function Exposed: Boolean;
    function Focus: Boolean;
    procedure HideCursor;
    procedure DrawHide(LastView: TView);
    procedure DrawShow(LastView: TView);
    procedure DrawUnderRect(var R: TRect; LastView: TView);
    procedure DrawUnderView(DoShadow: Boolean; LastView: TView);
    function DataSize: Word; virtual;
    { Rec points at a record of at least DataSize bytes. }
    procedure GetData(Rec: Pointer); virtual;
    procedure SetData(Rec: Pointer); virtual;
    procedure Awaken; virtual;
    procedure BlockCursor;
    procedure NormalCursor;
    procedure ResetCursor; virtual;
    procedure SetCursor(X, Y: Integer);
    procedure ShowCursor;
    procedure DrawCursor;
    procedure ClearEvent(var Event: TEvent);
    function EventAvail: Boolean;
    procedure GetEvent(var Event: TEvent); overload; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure PutEvent(var Event: TEvent); virtual;
    class function CommandEnabled(Command: Word): Boolean; static;
    class procedure DisableCommands(const Commands: TCommandSet); static;
    class procedure EnableCommands(const Commands: TCommandSet); static;
    class procedure DisableCommand(Command: Word); static;
    class procedure EnableCommand(Command: Word); static;
    class procedure GetCommands(var Commands: TCommandSet); static;
    class procedure SetCommands(const Commands: TCommandSet); static;
    class procedure SetCmdState(const Commands: TCommandSet; Enable: Boolean); static;
    procedure EndModal(Command: Word); virtual;
    function Execute: Word; virtual;
    function GetColor(Color: Word): TAttrPair;
    function GetPalette: TPalette; virtual;
    function MapColor(Color: Byte): TColorAttr; virtual;
    function GetState(AState: Word): Boolean;
    procedure Select;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    { As GetEvent, with EventTimeoutMs set to TimeoutMs while the event is read. }
    procedure GetEvent(var Event: TEvent; TimeoutMs: Integer); overload;
    procedure KeyEvent(var Event: TEvent);
    function MouseEvent(var Event: TEvent; Mask: Word): Boolean;
    { Fills Dest, which has room for DestSize bytes, with the text of consecutive events; ALength is the number of
      bytes written. Returns whether any byte was written. Event.What is evNothing on return. }
    function TextEvent(var Event: TEvent; Dest: PChar; DestSize: SizeInt; var ALength: SizeInt): Boolean;
    function SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer = -1): TTimerId; virtual;
    procedure KillTimer(Id: TTimerId); virtual;
    function MakeGlobal(Source: TPoint): TPoint;
    function MakeLocal(Source: TPoint): TPoint;
    function NextView: TView;
    function PrevView: TView;
    function Prev: TView;
    procedure MakeFirst;
    procedure PutInFrontOf(Target: TView);
    function TopView: TView;
    { B is a buffer of W * H pairs of a character and a BIOS attribute (Word), or of W * H cells. }
    procedure WriteBuf(X, Y, W, H: SmallInt; B: Pointer); overload;
    procedure WriteBuf(X, Y, W, H: SmallInt; const B: TDrawBuffer); overload;
    procedure WriteBuf(X, Y, W, H: SmallInt; B: PScreenCell); overload;
    procedure WriteChar(X, Y: SmallInt; C: Char; Color: Byte; Count: SmallInt);
    { Writes the same row H times. }
    procedure WriteLine(X, Y, W, H: SmallInt; const B: TDrawBuffer); overload;
    procedure WriteLine(X, Y, W, H: SmallInt; B: Pointer); overload;
    procedure WriteLine(X, Y, W, H: SmallInt; B: PScreenCell); overload;
    procedure WriteStr(X, Y: SmallInt; const Str: string; Color: Byte);
    procedure ShutDown; override;
  end;

  TGroup = class(TView)
  private
    procedure FocusView(P: TView; Enable: Boolean);
    procedure SelectView(P: TView; Enable: Boolean);
    function FindNext(Forwards: Boolean): TView;
  public
    Current: TView;
    Last: TView;
    Clip: TRect;
    Phase: TPhaseType;
    Buffer: PScreenCell;
    LockFlag: Byte;
    EndState: Word;

    constructor Create(const Bounds: TRect);
    procedure ShutDown; override;
    function ExecView(P: TView): Word;
    function Execute: Word; override;
    procedure Awaken; override;
    procedure InsertView(P, Target: TView);
    procedure Remove(P: TView);
    procedure RemoveView(P: TView);
    procedure ResetCurrent;
    procedure SetCurrent(P: TView; Mode: TSelectMode);
    procedure SelectNext(Forwards: Boolean);
    { Returns the first subview, from the first to the last, for which Func returns True; nil when there is none. }
    function FirstThat(Func: TFirstThatFunc; Args: Pointer): TView;
    function FocusNext(Forwards: Boolean): Boolean;
    { Calls Func for each subview, from the first to the last. }
    procedure ForEach(Func: TForEachFunc; Args: Pointer);
    procedure Insert(P: TView);
    procedure InsertBefore(P, Target: TView);
    { The subview at the position Index, counted from 1 at the first subview; nil for any other Index. }
    function At(Index: SmallInt): TView;
    function FirstMatch(AState, AOptions: Word): TView;
    { The position of P, counted from 1 at the first subview; 0 when P is not a subview. }
    function IndexOf(P: TView): SmallInt;
    function First: TView;
    procedure SetState(AState: Word; Enable: Boolean); override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure DrawSubViews(P, Bottom: TView);
    procedure ChangeBounds(const Bounds: TRect); override;
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    procedure SetData(Rec: Pointer); override;
    procedure Draw; override;
    procedure Redraw;
    procedure Lock;
    procedure Unlock;
    procedure ResetCursor; override;
    procedure EndModal(Command: Word); override;
    procedure EventError(var Event: TEvent); virtual;
    function GetHelpCtx: Word; override;
    function Valid(Command: Word): Boolean; override;
    procedure FreeBuffer;
    procedure GetBuffer;
  end;

  { Sends a message to Receiver; the result is the pointer that the receiver answers with, or nil. }
  TMessageFunc = function(Receiver: TView; What, Command: Word; InfoPtr: Pointer): Pointer;
  { Moves the caret of the display. }
  TCaretPositionProc = procedure(X, Y: Integer);
  { Writes Count cells, which are at X and Y of the screen, to the display. }
  TScreenWriteProc = procedure(X, Y: Integer; Buf: PScreenCell; Count: Integer);

var
  { The view that executes now, or nil. }
  TheTopView: TView;
  { How far a shadow reaches to the right and downwards, and its attribute. }
  ShadowSize: TPoint;
  ShadowAttr: TColorAttr;
  { The time-out of the wait for events, in milliseconds. }
  EventTimeoutMs: Integer;
  MessageHook: TMessageFunc;
  CaretPositionHook: TCaretPositionProc;
  ScreenWriteHook: TScreenWriteProc;

implementation

class function TCommandSet.Loc(Cmd: Integer): Cardinal;
begin
end;

class function TCommandSet.Mask(Cmd: Integer): Byte;
begin
end;

class function TCommandSet.Create: TCommandSet;
begin
end;

function TCommandSet.Has(Cmd: Integer): Boolean;
begin
end;

procedure TCommandSet.DisableCmd(Cmd: Integer);
begin
end;

procedure TCommandSet.EnableCmd(Cmd: Integer);
begin
end;

procedure TCommandSet.EnableCmd(const Tc: TCommandSet);
begin
end;

procedure TCommandSet.DisableCmd(const Tc: TCommandSet);
begin
end;

procedure TCommandSet.AddAssign(Cmd: Integer);
begin
end;

procedure TCommandSet.SubAssign(Cmd: Integer);
begin
end;

procedure TCommandSet.AddAssign(const Tc: TCommandSet);
begin
end;

procedure TCommandSet.SubAssign(const Tc: TCommandSet);
begin
end;

function TCommandSet.IsEmpty: Boolean;
begin
end;

function TCommandSet.AndAssign(const Tc: TCommandSet): TCommandSet;
begin
end;

function TCommandSet.OrAssign(const Tc: TCommandSet): TCommandSet;
begin
end;

class operator TCommandSet.*(const One, Two: TCommandSet): TCommandSet;
begin
end;

class operator TCommandSet.+(const One, Two: TCommandSet): TCommandSet;
begin
end;

class operator TCommandSet.=(const One, Two: TCommandSet): Boolean;
begin
end;

class operator TCommandSet.<>(const One, Two: TCommandSet): Boolean;
begin
end;

constructor TPalette.Create(const Colors: string; ALen: Word);
begin
end;

constructor TPalette.Create(const Colors: array of TColorAttr);
begin
end;

constructor TPalette.Create(Other: TPalette);
begin
end;

destructor TPalette.Destroy;
begin
end;

procedure TPalette.Assign(Other: TPalette);
begin
end;

function TPalette.GetItem(Index: Integer): TColorAttr;
begin
end;

procedure TPalette.SetItem(Index: Integer; const Value: TColorAttr);
begin
end;

constructor TView.Create(const Bounds: TRect);
begin
end;

destructor TView.Destroy;
begin
end;

procedure TView.Awaken;
begin
end;

procedure TView.BlockCursor;
begin
end;

procedure TView.CalcBounds(var Bounds: TRect; Delta: TPoint);
begin
end;

procedure TView.ChangeBounds(const Bounds: TRect);
begin
end;

procedure TView.ClearEvent(var Event: TEvent);
begin
end;

class function TView.CommandEnabled(Command: Word): Boolean;
begin
end;

function TView.DataSize: Word;
begin
end;

class procedure TView.DisableCommands(const Commands: TCommandSet);
begin
end;

class procedure TView.DisableCommand(Command: Word);
begin
end;

procedure TView.MoveGrow(P, S: TPoint; var Limits: TRect; MinSize, MaxSize: TPoint; Mode: Byte);
begin
end;

procedure TView.Change(Mode: Byte; Delta: TPoint; var P, S: TPoint; CtrlState: Word);
begin
end;

procedure TView.DragView(var Event: TEvent; Mode: Byte; var Limits: TRect; MinSize, MaxSize: TPoint);
begin
end;

procedure TView.Draw;
begin
end;

procedure TView.DrawCursor;
begin
end;

procedure TView.DrawHide(LastView: TView);
begin
end;

procedure TView.DrawShow(LastView: TView);
begin
end;

procedure TView.DrawUnderRect(var R: TRect; LastView: TView);
begin
end;

procedure TView.DrawUnderView(DoShadow: Boolean; LastView: TView);
begin
end;

procedure TView.DrawView;
begin
end;

class procedure TView.EnableCommands(const Commands: TCommandSet);
begin
end;

class procedure TView.EnableCommand(Command: Word);
begin
end;

procedure TView.EndModal(Command: Word);
begin
end;

function TView.EventAvail: Boolean;
begin
end;

function TView.GetBounds: TRect;
begin
end;

function TView.Execute: Word;
begin
end;

function TView.Focus: Boolean;
begin
end;

function TView.GetClipRect: TRect;
begin
end;

function TView.GetColor(Color: Word): TAttrPair;
begin
end;

class procedure TView.GetCommands(var Commands: TCommandSet);
begin
end;

procedure TView.GetData(Rec: Pointer);
begin
end;

procedure TView.GetEvent(var Event: TEvent);
begin
end;

procedure TView.GetEvent(var Event: TEvent; TimeoutMs: Integer);
begin
end;

function TView.GetExtent: TRect;
begin
end;

function TView.GetHelpCtx: Word;
begin
end;

function TView.GetPalette: TPalette;
begin
end;

function TView.GetState(AState: Word): Boolean;
begin
end;

procedure TView.GrowTo(X, Y: SmallInt);
begin
end;

procedure TView.HandleEvent(var Event: TEvent);
begin
end;

procedure TView.Hide;
begin
end;

procedure TView.HideCursor;
begin
end;

procedure TView.KeyEvent(var Event: TEvent);
begin
end;

procedure TView.KillTimer(Id: TTimerId);
begin
end;

procedure TView.Locate(var Bounds: TRect);
begin
end;

procedure TView.MakeFirst;
begin
end;

function TView.MakeGlobal(Source: TPoint): TPoint;
begin
end;

function TView.MakeLocal(Source: TPoint): TPoint;
begin
end;

function TView.MapColor(Color: Byte): TColorAttr;
begin
end;

function TView.MouseEvent(var Event: TEvent; Mask: Word): Boolean;
begin
end;

function TView.MouseInView(Mouse: TPoint): Boolean;
begin
end;

procedure TView.MoveTo(X, Y: SmallInt);
begin
end;

function TView.NextView: TView;
begin
end;

procedure TView.NormalCursor;
begin
end;

function TView.Prev: TView;
begin
end;

function TView.PrevView: TView;
begin
end;

procedure TView.PutEvent(var Event: TEvent);
begin
end;

procedure TView.PutInFrontOf(Target: TView);
begin
end;

procedure TView.Select;
begin
end;

procedure TView.SetBounds(const Bounds: TRect);
begin
end;

class procedure TView.SetCmdState(const Commands: TCommandSet; Enable: Boolean);
begin
end;

class procedure TView.SetCommands(const Commands: TCommandSet);
begin
end;

procedure TView.SetCursor(X, Y: Integer);
begin
end;

procedure TView.SetData(Rec: Pointer);
begin
end;

procedure TView.SetState(AState: Word; Enable: Boolean);
begin
end;

function TView.SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer): TTimerId;
begin
end;

procedure TView.Show;
begin
end;

procedure TView.ShowCursor;
begin
end;

procedure TView.SizeLimits(var Min, Max: TPoint);
begin
end;

function TView.TextEvent(var Event: TEvent; Dest: PChar; DestSize: SizeInt; var ALength: SizeInt): Boolean;
begin
end;

function TView.TopView: TView;
begin
end;

function TView.Valid(Command: Word): Boolean;
begin
end;

function TView.ContainsMouse(var Event: TEvent): Boolean;
begin
end;

procedure TView.ShutDown;
begin
end;

function TView.Exposed: Boolean;
begin
end;

procedure TView.ResetCursor;
begin
end;

procedure TView.WriteView(X, Y, Count: SmallInt; B: Pointer);
begin
end;

procedure TView.WriteView(X, Y, Count: SmallInt; B: PScreenCell);
begin
end;

procedure TView.WriteBuf(X, Y, W, H: SmallInt; B: PScreenCell);
begin
end;

procedure TView.WriteBuf(X, Y, W, H: SmallInt; B: Pointer);
begin
end;

procedure TView.WriteBuf(X, Y, W, H: SmallInt; const B: TDrawBuffer);
begin
end;

procedure TView.WriteChar(X, Y: SmallInt; C: Char; Color: Byte; Count: SmallInt);
begin
end;

procedure TView.WriteLine(X, Y, W, H: SmallInt; B: Pointer);
begin
end;

procedure TView.WriteLine(X, Y, W, H: SmallInt; B: PScreenCell);
begin
end;

procedure TView.WriteLine(X, Y, W, H: SmallInt; const B: TDrawBuffer);
begin
end;

procedure TView.WriteStr(X, Y: SmallInt; const Str: string; Color: Byte);
begin
end;

constructor TGroup.Create(const Bounds: TRect);
begin
end;

procedure TGroup.ShutDown;
begin
end;

procedure TGroup.Awaken;
begin
end;

procedure TGroup.ChangeBounds(const Bounds: TRect);
begin
end;

function TGroup.DataSize: Word;
begin
end;

procedure TGroup.Remove(P: TView);
begin
end;

procedure TGroup.Draw;
begin
end;

procedure TGroup.DrawSubViews(P, Bottom: TView);
begin
end;

procedure TGroup.EndModal(Command: Word);
begin
end;

procedure TGroup.EventError(var Event: TEvent);
begin
end;

function TGroup.Execute: Word;
begin
end;

function TGroup.ExecView(P: TView): Word;
begin
end;

function TGroup.First: TView;
begin
end;

function TGroup.FindNext(Forwards: Boolean): TView;
begin
end;

function TGroup.FocusNext(Forwards: Boolean): Boolean;
begin
end;

function TGroup.FirstMatch(AState, AOptions: Word): TView;
begin
end;

function TGroup.FirstThat(Func: TFirstThatFunc; Args: Pointer): TView;
begin
end;

procedure TGroup.ForEach(Func: TForEachFunc; Args: Pointer);
begin
end;

function TGroup.At(Index: SmallInt): TView;
begin
end;

function TGroup.IndexOf(P: TView): SmallInt;
begin
end;

procedure TGroup.FreeBuffer;
begin
end;

procedure TGroup.GetBuffer;
begin
end;

procedure TGroup.GetData(Rec: Pointer);
begin
end;

procedure TGroup.HandleEvent(var Event: TEvent);
begin
end;

procedure TGroup.Insert(P: TView);
begin
end;

procedure TGroup.InsertBefore(P, Target: TView);
begin
end;

procedure TGroup.InsertView(P, Target: TView);
begin
end;

procedure TGroup.Lock;
begin
end;

procedure TGroup.Redraw;
begin
end;

procedure TGroup.RemoveView(P: TView);
begin
end;

procedure TGroup.ResetCurrent;
begin
end;

procedure TGroup.ResetCursor;
begin
end;

procedure TGroup.SelectNext(Forwards: Boolean);
begin
end;

procedure TGroup.SelectView(P: TView; Enable: Boolean);
begin
end;

procedure TGroup.FocusView(P: TView; Enable: Boolean);
begin
end;

procedure TGroup.SetCurrent(P: TView; Mode: TSelectMode);
begin
end;

procedure TGroup.SetData(Rec: Pointer);
begin
end;

procedure TGroup.SetState(AState: Word; Enable: Boolean);
begin
end;

procedure TGroup.Unlock;
begin
end;

function TGroup.Valid(Command: Word): Boolean;
begin
end;

function TGroup.GetHelpCtx: Word;
begin
end;

end.
