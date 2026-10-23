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

uses
  TvScreen, TvUtf8, TvText, TvKeys;

type
  PWord = ^Word;
  PPoint = ^TPoint;
  PEvent = ^TEvent;

  { Gives the cells and the capacity of a TDrawBuffer. }
  TDrawBufferPeek = class(TDrawBuffer)
  public
    function Cells: PScreenCell;
    function Cap: SizeUInt;
  end;

var
  EmptyPalette: TPalette;

function TDrawBufferPeek.Cells: PScreenCell;
begin
  Result := Data;
end;

function TDrawBufferPeek.Cap: SizeUInt;
begin
  Result := Capacity;
end;

function MinOf(A, B: Integer): Integer;
begin
  Result := A;
  if B < A then
    Result := B;
end;

function MaxOf(A, B: Integer): Integer;
begin
  Result := A;
  if B > A then
    Result := B;
end;

{ Shifts V right by one bit, rounding towards minus infinity. }
function Sar1(V: Integer): Integer;
begin
  if V >= 0 then
    Result := V shr 1
  else
    Result := -((-V + 1) shr 1);
end;

function AttrByte(const A: TColorAttr): Byte;
begin
  Result := A;
end;

{ TCommandSet }

class function TCommandSet.Loc(Cmd: Integer): Cardinal;
begin
  Result := Cardinal(Cmd) div 8;
end;

class function TCommandSet.Mask(Cmd: Integer): Byte;
begin
  Result := Byte(1 shl (Cmd and $07));
end;

class function TCommandSet.Create: TCommandSet;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function TCommandSet.Has(Cmd: Integer): Boolean;
begin
  if Loc(Cmd) < 32 then
    Result := (Cmds[Loc(Cmd)] and Mask(Cmd)) <> 0
  else
    Result := False;
end;

procedure TCommandSet.DisableCmd(Cmd: Integer);
begin
  if Loc(Cmd) < 32 then
    Cmds[Loc(Cmd)] := Cmds[Loc(Cmd)] and not Mask(Cmd);
end;

procedure TCommandSet.EnableCmd(Cmd: Integer);
begin
  if Loc(Cmd) < 32 then
    Cmds[Loc(Cmd)] := Cmds[Loc(Cmd)] or Mask(Cmd);
end;

procedure TCommandSet.EnableCmd(const Tc: TCommandSet);
var
  I: Integer;
begin
  for I := 0 to 31 do
    Cmds[I] := Cmds[I] or Tc.Cmds[I];
end;

procedure TCommandSet.DisableCmd(const Tc: TCommandSet);
var
  I: Integer;
begin
  for I := 0 to 31 do
    Cmds[I] := Cmds[I] and not Tc.Cmds[I];
end;

procedure TCommandSet.AddAssign(Cmd: Integer);
begin
  EnableCmd(Cmd);
end;

procedure TCommandSet.SubAssign(Cmd: Integer);
begin
  DisableCmd(Cmd);
end;

procedure TCommandSet.AddAssign(const Tc: TCommandSet);
begin
  EnableCmd(Tc);
end;

procedure TCommandSet.SubAssign(const Tc: TCommandSet);
begin
  DisableCmd(Tc);
end;

function TCommandSet.IsEmpty: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to 31 do
    if Cmds[I] <> 0 then
      Exit;
  Result := True;
end;

function TCommandSet.AndAssign(const Tc: TCommandSet): TCommandSet;
var
  I: Integer;
begin
  for I := 0 to 31 do
    Cmds[I] := Cmds[I] and Tc.Cmds[I];
  Result := Self;
end;

function TCommandSet.OrAssign(const Tc: TCommandSet): TCommandSet;
var
  I: Integer;
begin
  for I := 0 to 31 do
    Cmds[I] := Cmds[I] or Tc.Cmds[I];
  Result := Self;
end;

class operator TCommandSet.*(const One, Two: TCommandSet): TCommandSet;
begin
  Result := One;
  Result.AndAssign(Two);
end;

class operator TCommandSet.+(const One, Two: TCommandSet): TCommandSet;
begin
  Result := One;
  Result.OrAssign(Two);
end;

class operator TCommandSet.=(const One, Two: TCommandSet): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to 31 do
    if One.Cmds[I] <> Two.Cmds[I] then
      Exit;
  Result := True;
end;

class operator TCommandSet.<>(const One, Two: TCommandSet): Boolean;
begin
  Result := not (One = Two);
end;

{ TPalette }

constructor TPalette.Create(const Colors: string; ALen: Word);
var
  I: Integer;
begin
  inherited Create;
  GetMem(Data, (Integer(ALen) + 1) * SizeOf(TColorAttr));
  Data[0] := TColorAttr.Create(Integer(ALen));
  for I := 0 to Integer(ALen) - 1 do
    if I < Length(Colors) then
      Data[I + 1] := TColorAttr.Create(Ord(Colors[I + 1]))
    else
      Data[I + 1] := TColorAttr.Create(0);
end;

constructor TPalette.Create(const Colors: array of TColorAttr);
var
  I: Integer;
begin
  inherited Create;
  GetMem(Data, (Length(Colors) + 1) * SizeOf(TColorAttr));
  Data[0] := TColorAttr.Create(Length(Colors));
  for I := 0 to High(Colors) do
    Data[I + 1] := Colors[I];
end;

constructor TPalette.Create(Other: TPalette);
begin
  inherited Create;
  Data := nil;
  Assign(Other);
end;

destructor TPalette.Destroy;
begin
  if Data <> nil then
    FreeMem(Data);
  inherited Destroy;
end;

procedure TPalette.Assign(Other: TPalette);
var
  Count: Integer;
  NewData: PColorAttr;
begin
  if Other = Self then
    Exit;
  Count := Integer(AttrByte(Other.Data[0])) + 1;
  GetMem(NewData, Count * SizeOf(TColorAttr));
  Move(Other.Data^, NewData^, Count * SizeOf(TColorAttr));
  if Data <> nil then
    FreeMem(Data);
  Data := NewData;
end;

function TPalette.GetItem(Index: Integer): TColorAttr;
begin
  Result := Data[Index];
end;

procedure TPalette.SetItem(Index: Integer; const Value: TColorAttr);
begin
  Data[Index] := Value;
end;

{ The helpers of TView }

function Range(Val, AMin, AMax: Integer): Integer;
begin
  if AMin > AMax then
    AMin := AMax;
  if Val < AMin then
    Result := AMin
  else if Val > AMax then
    Result := AMax
  else
    Result := Val;
end;

{ Fits Val into the range, keeping track of the remainders in Balance, and applies them back when it is possible.
  This lets views recover their original sizes. }
function BalancedRange(Val, AMin, AMax: Integer; var Balance: Integer): Integer;
var
  Offset: Integer;
begin
  if AMin > AMax then
    AMax := AMin;
  if Val < AMin then
  begin
    Balance := Balance + (Val - AMin);
    Result := AMin;
  end
  else if Val > AMax then
  begin
    Balance := Balance + (Val - AMax);
    Result := AMax;
  end
  else
  begin
    Offset := Range(Val + Balance, AMin, AMax) - Val;
    Balance := Balance - Offset;
    Result := Val + Offset;
  end;
end;

procedure FitToLimits(A: Integer; var B: Integer; AMin, AMax: Integer; var Balance: Integer);
begin
  B := A + BalancedRange(B - A, AMin, AMax, Balance);
end;

procedure GrowCoord(P: TView; S, D: Integer; var I: Integer);
begin
  if (P.GrowMode and gfGrowRel) <> 0 then
  begin
    if S <> D then
      I := (I * S + Sar1(S - D)) div (S - D);
  end
  else
    I := I + D;
end;

function MakePoint(AX, AY: Integer): TPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function InitCommands: TCommandSet;
var
  I: Integer;
begin
  Result := TCommandSet.Create;
  for I := 0 to 255 do
    Result.EnableCmd(I);
  Result.DisableCmd(cmZoom);
  Result.DisableCmd(cmClose);
  Result.DisableCmd(cmResize);
  Result.DisableCmd(cmNext);
  Result.DisableCmd(cmPrev);
end;

{ The text of a key event, appended to Dest when it fits. }
function GetEventText(var Event: TEvent; Dest: PChar; DestSize: SizeInt; var ALength: SizeInt): Boolean;
var
  Text: string;
  DstSize: SizeInt;
begin
  Result := False;
  if Event.What = evKeyDown then
  begin
    if Event.KeyDown.TextLength <> 0 then
      Text := Event.KeyDown.GetText
    else if Event.KeyDown.KeyCode = kbEnter then
      Text := #10
    else if Event.KeyDown.KeyCode = kbTab then
      Text := #9
    else
      Text := '';
    if ALength >= DestSize then
      DstSize := 0
    else
      DstSize := DestSize - ALength;
    if (Length(Text) > 0) and (Length(Text) <= DstSize) then
    begin
      Move(Text[1], (Dest + ALength)^, Length(Text));
      ALength := ALength + Length(Text);
      Result := True;
    end;
  end;
end;

{ The state of the walk that decides whether a part of a row of a view is covered by the views in front of it. }
type
  TVExposd = record
    Eax, Ebx, Ecx, Esi: Integer;
    Target: TView;
    function L0(Dest: TView): Boolean;
    function L1(Dest: TView): Boolean;
    function L10(Dest: TView): Boolean;
    function L11(Dest: TView): Boolean;
    function L12(Owner: TGroup): Boolean;
    function L13(Owner: TGroup): Boolean;
    function L20(Dest: TView): Boolean;
    function L21(Next: TView): Boolean;
    function L22(Next: TView): Boolean;
    function L23(Next: TView): Boolean;
  end;

function TVExposd.L0(Dest: TView): Boolean;
begin
  if (Dest.State and sfExposed) = 0 then
  begin
    Result := False;
    Exit;
  end;
  if (0 >= Dest.Size.X) or (0 >= Dest.Size.Y) then
  begin
    Result := False;
    Exit;
  end;
  Result := L1(Dest);
end;

function TVExposd.L1(Dest: TView): Boolean;
var
  I: Integer;
begin
  I := 0;
  repeat
    Eax := I;
    Ebx := 0;
    Ecx := Dest.Size.X;
    if not L11(Dest) then
    begin
      Result := True;
      Exit;
    end;
    Inc(I);
  until I >= Dest.Size.Y;
  Result := False;
end;

function TVExposd.L10(Dest: TView): Boolean;
var
  Owner: TGroup;
begin
  Owner := Dest.Owner;
  if (Owner.Buffer <> nil) or (Owner.LockFlag <> 0) then
  begin
    Result := False;
    Exit;
  end;
  Result := L11(Owner);
end;

function TVExposd.L11(Dest: TView): Boolean;
var
  Owner: TGroup;
begin
  Target := Dest;
  Eax := Eax + Dest.Origin.Y;
  Ebx := Ebx + Dest.Origin.X;
  Ecx := Ecx + Dest.Origin.X;
  Owner := Dest.Owner;
  if Owner = nil then
  begin
    Result := False;
    Exit;
  end;
  if Eax < Owner.Clip.A.Y then
  begin
    Result := True;
    Exit;
  end;
  if Eax >= Owner.Clip.B.Y then
  begin
    Result := True;
    Exit;
  end;
  if Ebx >= Owner.Clip.A.X then
  begin
    Result := L12(Owner);
    Exit;
  end;
  Ebx := Owner.Clip.A.X;
  Result := L12(Owner);
end;

function TVExposd.L12(Owner: TGroup): Boolean;
begin
  if Ecx <= Owner.Clip.B.X then
  begin
    Result := L13(Owner);
    Exit;
  end;
  Ecx := Owner.Clip.B.X;
  Result := L13(Owner);
end;

function TVExposd.L13(Owner: TGroup): Boolean;
begin
  if Ebx >= Ecx then
  begin
    Result := True;
    Exit;
  end;
  Result := L20(Owner.Last);
end;

function TVExposd.L20(Dest: TView): Boolean;
var
  Nxt: TView;
begin
  Nxt := Dest.Next;
  if Nxt = Target then
  begin
    Result := L10(Nxt);
    Exit;
  end;
  Result := L21(Nxt);
end;

function TVExposd.L21(Next: TView): Boolean;
begin
  if (Next.State and sfVisible) = 0 then
  begin
    Result := L20(Next);
    Exit;
  end;
  Esi := Next.Origin.Y;
  if Eax < Esi then
  begin
    Result := L20(Next);
    Exit;
  end;
  Esi := Esi + Next.Size.Y;
  if Eax >= Esi then
  begin
    Result := L20(Next);
    Exit;
  end;
  Esi := Next.Origin.X;
  if Ebx < Esi then
  begin
    Result := L22(Next);
    Exit;
  end;
  Esi := Esi + Next.Size.X;
  if Ebx >= Esi then
  begin
    Result := L20(Next);
    Exit;
  end;
  Ebx := Esi;
  if Ebx < Ecx then
  begin
    Result := L20(Next);
    Exit;
  end;
  Result := True;
end;

function TVExposd.L22(Next: TView): Boolean;
begin
  if Ecx <= Esi then
  begin
    Result := L20(Next);
    Exit;
  end;
  Esi := Esi + Next.Size.X;
  if Ecx > Esi then
  begin
    Result := L23(Next);
    Exit;
  end;
  Ecx := Next.Origin.X;
  Result := L20(Next);
end;

function TVExposd.L23(Next: TView): Boolean;
var
  SaveTarget: TView;
  SaveEsi, SaveEcx, SaveEax: Integer;
  B: Boolean;
begin
  SaveTarget := Target;
  SaveEsi := Esi;
  SaveEcx := Ecx;
  SaveEax := Eax;
  Ecx := Next.Origin.X;
  B := L20(Next);
  Eax := SaveEax;
  Ecx := SaveEcx;
  Ebx := SaveEsi;
  Target := SaveTarget;
  if B then
    Result := L20(Next)
  else
    Result := False;
end;

{ The state of the walk that clips a row of cells against the views in front of the view that writes. }
type
  TVWrite = record
    X, Y, Count, WOffset: SmallInt;
    Buffer: Pointer;
    Target: TView;
    Edx, Esi: Integer;
    BufIsShort: Boolean;
    procedure L0(Dest: TView; AX, AY, ACount: SmallInt; B: Pointer);
    procedure L10(Dest: TView);
    procedure L20(Dest: TView);
    procedure L30(Dest: TView);
    procedure L40(Dest: TView);
    procedure L50(Owner: TGroup);
    procedure CopyCell(Dst, Src: PScreenCell);
    procedure CopyShort2Cell(Dst: PScreenCell; Src: PWord);
    class function ApplyShadow(Attr: TColorAttr): TColorAttr; static;
  end;

class function TVWrite.ApplyShadow(Attr: TColorAttr): TColorAttr;
var
  Style: Word;
  Bg: Byte;
begin
  { The style flag tells whether the shadow has been applied. }
  Style := Attr.GetStyle;
  if (Style and slWindowShadow) = 0 then
  begin
    Bg := Attr.GetBackground.ToBIOS(False);
    if Bg = 0 then
      { The shadow attribute is reversed on black areas. }
      Attr := ShadowAttr.Reversed
    else
      Attr := ShadowAttr;
    Attr.SetStyle(Style or slWindowShadow);
  end;
  Result := Attr;
end;

procedure TVWrite.L0(Dest: TView; AX, AY, ACount: SmallInt; B: Pointer);
begin
  X := AX;
  Y := AY;
  Count := ACount;
  Buffer := B;
  WOffset := X;
  Count := Count + X;
  Edx := 0;
  if (0 <= Y) and (Y < Dest.Size.Y) then
  begin
    if X < 0 then
      X := 0;
    if Count > Dest.Size.X then
      Count := Dest.Size.X;
    if X < Count then
      L10(Dest);
  end;
end;

procedure TVWrite.L10(Dest: TView);
var
  Owner: TGroup;
begin
  Owner := Dest.Owner;
  if ((Dest.State and sfVisible) <> 0) and (Owner <> nil) then
  begin
    Target := Dest;
    Y := Y + Dest.Origin.Y;
    X := X + Dest.Origin.X;
    Count := Count + Dest.Origin.X;
    WOffset := WOffset + Dest.Origin.X;
    if (Owner.Clip.A.Y <= Y) and (Y < Owner.Clip.B.Y) then
    begin
      if X < Owner.Clip.A.X then
        X := Owner.Clip.A.X;
      if Count > Owner.Clip.B.X then
        Count := Owner.Clip.B.X;
      if X < Count then
        L20(Owner.Last);
    end;
  end;
end;

procedure TVWrite.L20(Dest: TView);
var
  Next: TView;
begin
  Next := Dest.Next;
  if Next = Target then
    L40(Next)
  else
  begin
    if ((Next.State and sfVisible) <> 0) and (Next.Origin.Y <= Y) then
      repeat
        Esi := Next.Origin.Y + Next.Size.Y;
        if Y < Esi then
        begin
          Esi := Next.Origin.X;
          if X < Esi then
          begin
            if Count > Esi then
              L30(Next)
            else
              Break;
          end;
          Esi := Esi + Next.Size.X;
          if X < Esi then
          begin
            if Count > Esi then
              X := Esi
            else
              Exit;
          end;
          if ((Next.State and sfShadow) <> 0) and (Next.Origin.Y + ShadowSize.Y <= Y) then
            Esi := Esi + ShadowSize.X
          else
            Break;
        end
        else if ((Next.State and sfShadow) <> 0) and (Y < Esi + ShadowSize.Y) then
        begin
          Esi := Next.Origin.X + ShadowSize.X;
          if X < Esi then
          begin
            if Count > Esi then
              L30(Next)
            else
              Break;
          end;
          Esi := Esi + Next.Size.X;
        end
        else
          Break;
        if X < Esi then
        begin
          Inc(Edx);
          if Count > Esi then
          begin
            L30(Next);
            Dec(Edx);
          end;
        end;
      until True;
    L20(Next);
  end;
end;

procedure TVWrite.L30(Dest: TView);
var
  SaveTarget: TView;
  SaveWOffset, SaveEsi, SaveEdx, SaveCount, SaveY: Integer;
begin
  SaveTarget := Target;
  SaveWOffset := WOffset;
  SaveEsi := Esi;
  SaveEdx := Edx;
  SaveCount := Count;
  SaveY := Y;
  Count := Esi;

  L20(Dest);

  Y := SaveY;
  Count := SaveCount;
  Edx := SaveEdx;
  Esi := SaveEsi;
  WOffset := SaveWOffset;
  Target := SaveTarget;
  X := Esi;
end;

procedure TVWrite.L40(Dest: TView);
var
  Owner: TGroup;
begin
  Owner := Dest.Owner;
  if Owner.Buffer <> nil then
    L50(Owner);
  if Owner.LockFlag = 0 then
    L10(Owner);
end;

procedure TVWrite.L50(Owner: TGroup);
var
  Dst: PScreenCell;
begin
  Dst := @Owner.Buffer[Y * Owner.Size.X + X];
  if BufIsShort then
    CopyShort2Cell(Dst, PWord(Buffer) + (X - WOffset))
  else
    CopyCell(Dst, PScreenCell(Buffer) + (X - WOffset));
  if Owner.Buffer = TScreen.ScreenBuffer then
    if Assigned(ScreenWriteHook) then
      ScreenWriteHook(X, Y, Dst, Count - X);
end;

procedure TVWrite.CopyCell(Dst, Src: PScreenCell);
var
  I: Integer;
  C: TScreenCell;
begin
  if Edx = 0 then
    Move(Src^, Dst^, SizeOf(TScreenCell) * (Count - X))
  else
    for I := 0 to Count - X - 1 do
    begin
      C := Src[I];
      C.Attribute := ApplyShadow(C.Attribute);
      Dst[I] := C;
    end;
end;

procedure TVWrite.CopyShort2Cell(Dst: PScreenCell; Src: PWord);
var
  I: Integer;
  C: TScreenCell;
begin
  if Edx = 0 then
    { Expand character/attribute pair }
    for I := 0 to Count - X - 1 do
      Dst[I] := TScreenCell.Create(Src[I])
  else
    { Mix in shadow attribute }
    for I := 0 to Count - X - 1 do
    begin
      C := TScreenCell.Create(Src[I]);
      C.Attribute := ApplyShadow(C.Attribute);
      Dst[I] := C;
    end;
end;

{ The routines of the caret. }

function DecideCaretSize(P: TView): Integer;
begin
  if (P.State and sfCursorIns) <> 0 then
    Result := 100
  else
    Result := TScreen.CursorLines and $FF;
end;

{ Pre: P.Owner is not nil. }
function CaretIsCoveredBySiblings(P: TView; X, Y: Integer): Boolean;
var
  U: TView;
begin
  U := P.Owner.Last.Next;
  while U <> P do
  begin
    if ((U.State and sfVisible) <> 0) and
       ((U.Origin.Y <= Y) and (Y < U.Origin.Y + U.Size.Y)) and
       ((U.Origin.X <= X) and (X < U.Origin.X + U.Size.X)) then
    begin
      Result := True;
      Exit;
    end;
    U := U.Next;
  end;
  Result := False;
end;

function ComputeCaretSize(P: TView; var X, Y: Integer): Integer;
var
  Mask: Word;
  V: TView;
begin
  Mask := sfVisible or sfCursorVis or sfFocused;
  if (P.State and Mask) <> Mask then
  begin
    Result := 0;
    Exit;
  end;

  V := P;
  while (0 <= Y) and (Y < V.Size.Y) and (0 <= X) and (X < V.Size.X) do
  begin
    Y := Y + V.Origin.Y;
    X := X + V.Origin.X;

    if V.Owner = nil then
    begin
      Result := DecideCaretSize(P);
      Exit;
    end;

    if ((V.Owner.State and sfVisible) = 0) or CaretIsCoveredBySiblings(V, X, Y) then
      Break;

    V := V.Owner;
  end;
  Result := 0;
end;

{ The callbacks of TGroup. }

procedure DoCalcChange(P: TView; D: Pointer);
var
  R: TRect;
begin
  FillChar(R, SizeOf(R), 0);
  P.CalcBounds(R, PPoint(D)^);
  P.ChangeBounds(R);
end;

procedure DoAwaken(V: TView; Args: Pointer);
begin
  V.Awaken;
end;

procedure AddSubviewDataSize(P: TView; T: Pointer);
begin
  PWord(T)^ := PWord(T)^ + P.DataSize;
end;

type
  THandleStruct = record
    Event: PEvent;
    Grp: TGroup;
  end;
  PHandleStruct = ^THandleStruct;

  TSetBlock = record
    St: Word;
    En: Boolean;
  end;
  PSetBlock = ^TSetBlock;

procedure DoHandleEvent(P: TView; S: Pointer);
var
  Ptr: PHandleStruct;
begin
  Ptr := PHandleStruct(S);

  if (P = nil) or (((P.State and sfDisabled) <> 0) and
     ((Ptr^.Event^.What and (positionalEvents or focusedEvents)) <> 0)) then
    Exit;

  case Ptr^.Grp.Phase of
    phFocused:
      ;
    phPreProcess:
      if (P.Options and ofPreProcess) = 0 then
        Exit;
    phPostProcess:
      if (P.Options and ofPostProcess) = 0 then
        Exit;
  end;
  if (Ptr^.Event^.What and P.EventMask) <> 0 then
    P.HandleEvent(Ptr^.Event^);
end;

function HasMouse(P: TView; S: Pointer): Boolean;
begin
  Result := P.ContainsMouse(PEvent(S)^);
end;

procedure DoExpose(P: TView; Enable: Pointer);
begin
  if (P.State and sfVisible) <> 0 then
    P.SetState(sfExposed, PBoolean(Enable)^);
end;

procedure DoSetState(P: TView; B: Pointer);
begin
  P.SetState(PSetBlock(B)^.St, PSetBlock(B)^.En);
end;

function IsInvalid(P: TView; Command: Pointer): Boolean;
begin
  Result := not P.Valid(PWord(Command)^);
end;

{ Tests and changes of the bits of a word of flags. }

function AnySet(Flags, Mask: Word): Boolean;
begin
  Result := (Flags and Mask) <> 0;
end;

function AllSet(Flags, Mask: Word): Boolean;
begin
  Result := (Flags and Mask) = Mask;
end;

procedure SetBits(var Flags: Word; Mask: Word);
begin
  Flags := Flags or Mask;
end;

procedure ClearBits(var Flags: Word; Mask: Word);
begin
  Flags := Flags and not Mask;
end;

{ The value V, raised to Lo when it is below it, and then lowered to Hi when it is above it. }
function Clamp(V, Lo, Hi: Integer): Integer;
begin
  Result := V;
  if Result < Lo then
    Result := Lo;
  if Result > Hi then
    Result := Hi;
end;

{ The view state that ExecView puts back when the modal view ends. }
type
  TExecSave = record
    Options: Word;
    Owner: TGroup;
    Top: TView;
    Current: TView;
    Commands: TCommandSet;
  end;

{ The step of the arrow keys, with or without Ctrl, when a view is dragged with the keyboard. }
function KeyStep(Key: Word; var Step: TPoint): Boolean;
begin
  Result := True;
  case Key of
    kbLeft:
      Step := MakePoint(-1, 0);
    kbRight:
      Step := MakePoint(1, 0);
    kbUp:
      Step := MakePoint(0, -1);
    kbDown:
      Step := MakePoint(0, 1);
    kbCtrlLeft:
      Step := MakePoint(-8, 0);
    kbCtrlRight:
      Step := MakePoint(8, 0);
    kbCtrlUp:
      Step := MakePoint(0, -4);
    kbCtrlDown:
      Step := MakePoint(0, 4);
  else
    Result := False;
  end;
end;

{ Moves or resizes V while the mouse moves, until a button is released. Event is the mouse down event. }
procedure DragByMouse(V: TView; var Event: TEvent; Mode: Byte; var Limits: TRect; MinSize, MaxSize: TPoint);
var
  Offset: TPoint;
  Bounds: TRect;
begin
  Bounds := V.GetBounds;
  if AnySet(Mode, dmDragMove) then
    Offset := V.Origin - Event.Mouse.Where
  else if AnySet(Mode, dmDragGrow) then
    Offset := V.Size - Event.Mouse.Where
  else
    Offset := MakePoint(V.Origin.X, V.Origin.Y + V.Size.Y) - Event.Mouse.Where;
  while True do
  begin
    Event.Mouse.Where := Event.Mouse.Where + Offset;
    if AnySet(Mode, dmDragMove) then
      V.MoveGrow(Event.Mouse.Where, V.Size, Limits, MinSize, MaxSize, Mode)
    else if AnySet(Mode, dmDragGrow) then
      V.MoveGrow(V.Origin, Event.Mouse.Where, Limits, MinSize, MaxSize, Mode)
    else
    begin
      Bounds.A.X := Clamp(Event.Mouse.Where.X, Bounds.B.X - MaxSize.X, Bounds.B.X - MinSize.X);
      Bounds.B.Y := Event.Mouse.Where.Y;
      V.MoveGrow(Bounds.A, Bounds.B - Bounds.A, Limits, MinSize, MaxSize, Mode);
    end;
    if not V.MouseEvent(Event, evMouseMove) then
      Break;
  end;
end;

{ Moves or resizes V with the keys, until Enter ends it or Esc puts V back where it was. }
procedure DragByKeys(V: TView; var Event: TEvent; Mode: Byte; var Limits: TRect; MinSize, MaxSize: TPoint);
var
  Saved: TRect;
  NewOrigin, NewSize, Step: TPoint;
  Key: Word;
begin
  Saved := V.GetBounds;
  repeat
    NewOrigin := V.Origin;
    NewSize := V.Size;
    V.KeyEvent(Event);
    Key := Event.KeyDown.KeyCode;
    if KeyStep(Key and $FF00, Step) then
      V.Change(Mode, Step, NewOrigin, NewSize, Event.KeyDown.ControlKeyState)
    else
      case Key and $FF00 of
        kbHome:
          NewOrigin.X := Limits.A.X;
        kbEnd:
          NewOrigin.X := Limits.B.X - NewSize.X;
        kbPgUp:
          NewOrigin.Y := Limits.A.Y;
        kbPgDn:
          NewOrigin.Y := Limits.B.Y - NewSize.Y;
      end;
    V.MoveGrow(NewOrigin, NewSize, Limits, MinSize, MaxSize, Mode);
  until (Key = kbEsc) or (Key = kbEnter);
  if Key = kbEsc then
    V.Locate(Saved);
end;

{ Makes P the modal view of G: P cannot be selected, is modal, and becomes the current view for the time it executes. }
procedure EnterModal(G: TGroup; P: TView);
begin
  P.Options := P.Options and not ofSelectable;
  P.SetState(sfModal, True);
  G.SetCurrent(P, enterSelect);
end;

{ TView }

constructor TView.Create(const Bounds: TRect);
begin
  inherited Create;
  Next := nil;
  Owner := nil;
  Options := 0;
  GrowMode := 0;
  State := sfVisible;
  EventMask := evMouseDown or evKeyDown or evCommand;
  DragMode := dmLimitLoY;
  HelpCtx := hcNoContext;
  SetBounds(Bounds);
  Cursor := MakePoint(0, 0);
  ResizeBalance := MakePoint(0, 0);
end;

destructor TView.Destroy;
begin
  inherited Destroy;
end;

procedure TView.Awaken;
begin
end;

procedure TView.BlockCursor;
begin
  SetState(sfCursorIns, True);
end;

procedure TView.CalcBounds(var Bounds: TRect; Delta: TPoint);
var
  Lo, Hi: TPoint;
begin
  Bounds := GetBounds;

  if AnySet(GrowMode, gfGrowLoX) then
    GrowCoord(Self, SmallInt(Owner.Size.X), SmallInt(Delta.X), Bounds.A.X);
  if AnySet(GrowMode, gfGrowHiX) then
    GrowCoord(Self, SmallInt(Owner.Size.X), SmallInt(Delta.X), Bounds.B.X);
  if AnySet(GrowMode, gfGrowLoY) then
    GrowCoord(Self, SmallInt(Owner.Size.Y), SmallInt(Delta.Y), Bounds.A.Y);
  if AnySet(GrowMode, gfGrowHiY) then
    GrowCoord(Self, SmallInt(Owner.Size.Y), SmallInt(Delta.Y), Bounds.B.Y);

  SizeLimits(Lo, Hi);
  FitToLimits(Bounds.A.X, Bounds.B.X, Lo.X, Hi.X, ResizeBalance.X);
  FitToLimits(Bounds.A.Y, Bounds.B.Y, Lo.Y, Hi.Y, ResizeBalance.Y);
end;

procedure TView.ChangeBounds(const Bounds: TRect);
begin
  SetBounds(Bounds);
  DrawView;
end;

procedure TView.ClearEvent(var Event: TEvent);
begin
  Event.What := evNothing;
  Event.Message.InfoPtr := Self;
end;

class function TView.CommandEnabled(Command: Word): Boolean;
begin
  Result := (Command > 255) or CurCommandSet.Has(Command);
end;

function TView.DataSize: Word;
begin
  Result := 0;
end;

class procedure TView.DisableCommands(const Commands: TCommandSet);
var
  Common: TCommandSet;
begin
  Common := CurCommandSet * Commands;
  CommandSetChanged := CommandSetChanged or not Common.IsEmpty;
  CurCommandSet.DisableCmd(Commands);
end;

class procedure TView.DisableCommand(Command: Word);
begin
  CommandSetChanged := CommandSetChanged or CurCommandSet.Has(Command);
  CurCommandSet.DisableCmd(Command);
end;

procedure TView.MoveGrow(P, S: TPoint; var Limits: TRect; MinSize, MaxSize: TPoint; Mode: Byte);
var
  R: TRect;
begin
  S.X := Clamp(S.X, MinSize.X, MaxSize.X);
  S.Y := Clamp(S.Y, MinSize.Y, MaxSize.Y);
  P.X := Clamp(P.X, Limits.A.X - S.X + 1, Limits.B.X - 1);
  P.Y := Clamp(P.Y, Limits.A.Y - S.Y + 1, Limits.B.Y - 1);

  if AnySet(Mode, dmLimitLoX) then
    P.X := MaxOf(P.X, Limits.A.X);
  if AnySet(Mode, dmLimitLoY) then
    P.Y := MaxOf(P.Y, Limits.A.Y);
  if AnySet(Mode, dmLimitHiX) then
    P.X := MinOf(P.X, Limits.B.X - S.X);
  if AnySet(Mode, dmLimitHiY) then
    P.Y := MinOf(P.Y, Limits.B.Y - S.Y);
  R := TRect.Create(P, P + S);
  Locate(R);
end;

procedure TView.Change(Mode: Byte; Delta: TPoint; var P, S: TPoint; CtrlState: Word);
begin
  if AnySet(CtrlState, kbShift) then
  begin
    if AnySet(Mode, dmDragGrow) then
      S := S + Delta;
  end
  else if AnySet(Mode, dmDragMove) then
    P := P + Delta;
end;

procedure TView.DragView(var Event: TEvent; Mode: Byte; var Limits: TRect; MinSize, MaxSize: TPoint);
begin
  SetState(sfDragging, True);
  if Event.What = evMouseDown then
    DragByMouse(Self, Event, Mode, Limits, MinSize, MaxSize)
  else
    DragByKeys(Self, Event, Mode, Limits, MinSize, MaxSize);
  SetState(sfDragging, False);
end;

procedure TView.Draw;
var
  B: TDrawBuffer;
  Pair: TAttrPair;
begin
  B := TDrawBuffer.Create;
  try
    Pair := GetColor(1);
    B.MoveChar(0, ' ', Pair.Attrs[0], Word(Size.X));
    WriteLine(0, 0, Size.X, Size.Y, B);
  finally
    B.Free;
  end;
end;

procedure TView.DrawCursor;
begin
  if AnySet(State, sfFocused) then
    ResetCursor;
end;

procedure TView.DrawHide(LastView: TView);
begin
  DrawCursor;
  DrawUnderView(AnySet(State, sfShadow), LastView);
end;

procedure TView.DrawShow(LastView: TView);
begin
  DrawView;
  if AnySet(State, sfShadow) then
    DrawUnderView(True, LastView);
end;

procedure TView.DrawUnderRect(var R: TRect; LastView: TView);
begin
  Owner.Clip.Intersect(R);
  Owner.DrawSubViews(NextView, LastView);
  Owner.Clip := Owner.GetExtent;
end;

procedure TView.DrawUnderView(DoShadow: Boolean; LastView: TView);
var
  Area: TRect;
begin
  Area := GetBounds;
  if DoShadow then
    Area.B := Area.B + ShadowSize;
  if AnySet(Options, ofFramed) then
    Area.Grow(1, 1);
  DrawUnderRect(Area, LastView);
end;

procedure TView.DrawView;
begin
  if not Exposed then
    Exit;
  Draw;
  DrawCursor;
end;

class procedure TView.EnableCommands(const Commands: TCommandSet);
begin
  CommandSetChanged := CommandSetChanged or ((CurCommandSet * Commands) <> Commands);
  CurCommandSet.EnableCmd(Commands);
end;

class procedure TView.EnableCommand(Command: Word);
begin
  CommandSetChanged := CommandSetChanged or not CurCommandSet.Has(Command);
  CurCommandSet.EnableCmd(Command);
end;

procedure TView.EndModal(Command: Word);
var
  Top: TView;
begin
  Top := TopView;
  if Top <> nil then
    Top.EndModal(Command);
end;

function TView.EventAvail: Boolean;
var
  Event: TEvent;
  Found: Boolean;
begin
  FillChar(Event, SizeOf(Event), 0);
  GetEvent(Event);
  Found := Event.What <> evNothing;
  if Found then
    PutEvent(Event);
  Result := Found;
end;

function TView.GetBounds: TRect;
begin
  Result := TRect.Create(Origin, Origin + Size);
end;

function TView.Execute: Word;
begin
  Result := cmCancel;
end;

function TView.Focus: Boolean;
begin
  Result := True;
  if AnySet(State, sfSelected or sfModal) or (Owner = nil) then
    Exit;
  Result := Owner.Focus;
  if not Result then
    Exit;
  if (Owner.Current <> nil) and AnySet(Owner.Current.Options, ofValidate) and
     not Owner.Current.Valid(cmReleasedFocus) then
  begin
    Result := False;
    Exit;
  end;
  Select;
end;

function TView.GetClipRect: TRect;
var
  ClipR: TRect;
begin
  ClipR := GetBounds;
  if Owner <> nil then
    ClipR.Intersect(Owner.Clip);
  ClipR.Move(-Origin.X, -Origin.Y);
  Result := ClipR;
end;

function TView.GetColor(Color: Word): TAttrPair;
begin
  Result := TAttrPair.Create(0);

  if (Color and $FF00) <> 0 then
    Result := TAttrPair.ShiftedLeft(MapColor(Color shr 8), 8);

  Result.OrAssign(MapColor(Color and $FF));
end;

class procedure TView.GetCommands(var Commands: TCommandSet);
begin
  Commands := CurCommandSet;
end;

procedure TView.GetData(Rec: Pointer);
begin
end;

procedure TView.GetEvent(var Event: TEvent);
begin
  if Owner <> nil then
    Owner.GetEvent(Event);
end;

procedure TView.GetEvent(var Event: TEvent; TimeoutMs: Integer);
var
  SaveTimeout: Integer;
begin
  SaveTimeout := EventTimeoutMs;
  EventTimeoutMs := TimeoutMs;

  GetEvent(Event);

  EventTimeoutMs := SaveTimeout;
end;

function TView.GetExtent: TRect;
begin
  Result := TRect.Create(0, 0, Size.X, Size.Y);
end;

function TView.GetHelpCtx: Word;
begin
  Result := HelpCtx;
  if AnySet(State, sfDragging) then
    Result := hcDragging;
end;

function TView.GetPalette: TPalette;
begin
  Result := EmptyPalette;
end;

function TView.GetState(AState: Word): Boolean;
begin
  Result := AllSet(State, AState);
end;

procedure TView.GrowTo(X, Y: SmallInt);
var
  Area: TRect;
begin
  Area := GetBounds;
  Area.B.X := Area.A.X + X;
  Area.B.Y := Area.A.Y + Y;
  Locate(Area);
end;

procedure TView.HandleEvent(var Event: TEvent);
begin
  if Event.What <> evMouseDown then
    Exit;
  if AnySet(State, sfSelected or sfDisabled) or not AnySet(Options, ofSelectable) then
    Exit;
  if (not Focus) or not AnySet(Options, ofFirstClick) then
    ClearEvent(Event);
end;

procedure TView.Hide;
begin
  if AnySet(State, sfVisible) then
    SetState(sfVisible, False);
end;

procedure TView.HideCursor;
begin
  SetState(sfCursorVis, False);
end;

procedure TView.KeyEvent(var Event: TEvent);
begin
  repeat
    GetEvent(Event);
  until Event.What = evKeyDown;
end;

procedure TView.KillTimer(Id: TTimerId);
begin
  if Owner <> nil then
    Owner.KillTimer(Id);
end;

procedure TView.Locate(var Bounds: TRect);
var
  Lo, Hi: TPoint;
  Want: TPoint;
  Old: TRect;
begin
  SizeLimits(Lo, Hi);
  Want := Bounds.B - Bounds.A;
  Want.X := Range(Want.X, Lo.X, Hi.X);
  Want.Y := Range(Want.Y, Lo.Y, Hi.Y);
  Bounds.B := Bounds.A + Want;
  Old := GetBounds;
  if Bounds = Old then
    Exit;
  ChangeBounds(Bounds);
  if (Owner = nil) or not AnySet(State, sfVisible) then
    Exit;
  if AnySet(State, sfShadow) then
  begin
    Old.Union(Bounds);
    Old.B := Old.B + ShadowSize;
  end;
  DrawUnderRect(Old, nil);
end;

procedure TView.MakeFirst;
begin
  PutInFrontOf(Owner.First);
end;

function TView.MakeGlobal(Source: TPoint): TPoint;
var
  Walk: TView;
begin
  Result := Source + Origin;
  Walk := Owner;
  while Walk <> nil do
  begin
    Result := Result + Walk.Origin;
    Walk := Walk.Owner;
  end;
end;

function TView.MakeLocal(Source: TPoint): TPoint;
var
  Walk: TView;
begin
  Result := Source - Origin;
  Walk := Owner;
  while Walk <> nil do
  begin
    Result := Result - Walk.Origin;
    Walk := Walk.Owner;
  end;
end;

function TView.MapColor(Color: Byte): TColorAttr;
var
  Cur: TView;
  Pal: TPalette;
  Index: Integer;
  Len, Num: Byte;
  Value: TColorAttr;
begin
  Index := Color;
  if Index = 0 then
  begin
    Result := ErrorAttr;
    Exit;
  end;

  Value := TColorAttr.Create(Index);
  Cur := Self;
  while Cur <> nil do
  begin
    Pal := Cur.GetPalette;
    Len := Pal.Data[0];
    if Len > 0 then
    begin
      if Index > Len then
      begin
        Result := ErrorAttr;
        Exit;
      end;
      Value := Pal.Data[Index];
      Num := Value;
      if Cur.Owner <> nil then
      begin
        if Num = 0 then
        begin
          Result := ErrorAttr;
          Exit;
        end;
        Index := Num;
      end;
    end;
    Cur := Cur.Owner;
  end;
  Result := Value;
end;

function TView.MouseEvent(var Event: TEvent; Mask: Word): Boolean;
begin
  repeat
    GetEvent(Event);
  until AnySet(Event.What, Mask or evMouseUp);

  Result := Event.What <> evMouseUp;
end;

function TView.MouseInView(Mouse: TPoint): Boolean;
var
  Extent: TRect;
begin
  Extent := GetExtent;
  Result := Extent.Contains(MakeLocal(Mouse));
end;

procedure TView.MoveTo(X, Y: SmallInt);
var
  Area: TRect;
begin
  Area := GetBounds;
  Area.Move(X - Origin.X, Y - Origin.Y);
  Locate(Area);
end;

function TView.NextView: TView;
begin
  Result := Next;
  if Self = Owner.Last then
    Result := nil;
end;

procedure TView.NormalCursor;
begin
  SetState(sfCursorIns, False);
end;

function TView.Prev: TView;
begin
  Result := Self;
  while Result.Next <> Self do
    Result := Result.Next;
end;

function TView.PrevView: TView;
begin
  Result := nil;
  if Self <> Owner.First then
    Result := Prev;
end;

procedure TView.PutEvent(var Event: TEvent);
begin
  if Owner <> nil then
    Owner.PutEvent(Event);
end;

procedure TView.PutInFrontOf(Target: TView);
var
  Probe, Behind: TView;
begin
  if (Owner = nil) or (Target = Self) or (Target = NextView) then
    Exit;
  if (Target <> nil) and (Target.Owner <> Owner) then
    Exit;
  if not AnySet(State, sfVisible) then
  begin
    Owner.RemoveView(Self);
    Owner.InsertView(Self, Target);
    Exit;
  end;
  Behind := NextView;
  Probe := Target;
  while (Probe <> nil) and (Probe <> Self) do
    Probe := Probe.NextView;
  if Probe = nil then
    Behind := Target;
  ClearBits(State, sfVisible);
  if Behind = Target then
    DrawHide(Behind);
  Owner.RemoveView(Self);
  Owner.InsertView(Self, Target);
  SetBits(State, sfVisible);
  if Behind <> Target then
    DrawShow(Behind);
  if AnySet(Options, ofSelectable) then
    Owner.ResetCurrent;
end;

procedure TView.Select;
begin
  if not AnySet(Options, ofSelectable) or (Owner = nil) then
    Exit;
  if AnySet(Options, ofTopSelect) then
    MakeFirst
  else
    Owner.SetCurrent(Self, normalSelect);
end;

procedure TView.SetBounds(const Bounds: TRect);
begin
  Origin := Bounds.A;
  Size := Bounds.B - Bounds.A;
end;

class procedure TView.SetCmdState(const Commands: TCommandSet; Enable: Boolean);
begin
  if not Enable then
    DisableCommands(Commands)
  else
    EnableCommands(Commands);
end;

class procedure TView.SetCommands(const Commands: TCommandSet);
begin
  if CurCommandSet <> Commands then
  begin
    CommandSetChanged := True;
    CurCommandSet := Commands;
  end;
end;

procedure TView.SetCursor(X, Y: Integer);
begin
  Cursor := MakePoint(X, Y);
  DrawCursor;
end;

procedure TView.SetData(Rec: Pointer);
begin
end;

procedure TView.SetState(AState: Word; Enable: Boolean);
var
  Command: Word;
begin
  if Enable then
    SetBits(State, AState)
  else
    ClearBits(State, AState);

  if Owner = nil then
    Exit;

  if AState = sfVisible then
  begin
    if AnySet(Owner.State, sfExposed) then
      SetState(sfExposed, Enable);
    if not Enable then
      DrawHide(nil)
    else
      DrawShow(nil);
    if AnySet(Options, ofSelectable) then
      Owner.ResetCurrent;
  end
  else if (AState = sfCursorVis) or (AState = sfCursorIns) then
    DrawCursor
  else if AState = sfShadow then
    DrawUnderView(True, nil)
  else if AState = sfFocused then
  begin
    ResetCursor;
    Command := cmReceivedFocus;
    if not Enable then
      Command := cmReleasedFocus;
    if Assigned(MessageHook) then
      MessageHook(Owner, evBroadcast, Command, Self);
  end;
end;

function TView.SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer): TTimerId;
begin
  if Owner <> nil then
    Result := Owner.SetTimer(TimeoutMs, PeriodMs)
  else
    Result := nil;
end;

procedure TView.Show;
begin
  if not AnySet(State, sfVisible) then
    SetState(sfVisible, True);
end;

procedure TView.ShowCursor;
begin
  SetState(sfCursorVis, True);
end;

procedure TView.SizeLimits(var Min, Max: TPoint);
begin
  Min := MakePoint(0, 0);
  if (Owner <> nil) and not AnySet(GrowMode, gfFixed) then
    Max := Owner.Size
  else
    Max := MakePoint(MaxLongint, MaxLongint);
end;

function TView.TextEvent(var Event: TEvent; Dest: PChar; DestSize: SizeInt; var ALength: SizeInt): Boolean;
var
  More: Boolean;
begin
  ALength := 0;

  GetEventText(Event, Dest, DestSize, ALength);
  repeat
    GetEvent(Event, 0);
    More := GetEventText(Event, Dest, DestSize, ALength);
  until not More;

  if Event.What = evNothing then
    ClearEvent(Event)
  else
  begin
    PutEvent(Event);
    ClearEvent(Event);
  end;

  Result := ALength > 0;
end;

function TView.TopView: TView;
begin
  Result := TheTopView;
  if Result <> nil then
    Exit;
  Result := Self;
  while (Result <> nil) and not AnySet(Result.State, sfModal) do
    Result := Result.Owner;
end;

function TView.Valid(Command: Word): Boolean;
begin
  Result := True;
end;

function TView.ContainsMouse(var Event: TEvent): Boolean;
begin
  Result := AnySet(State, sfVisible) and MouseInView(Event.Mouse.Where);
end;

procedure TView.ShutDown;
begin
  Hide;
  if Owner <> nil then
    Owner.Remove(Self);
  inherited ShutDown;
end;

function TView.Exposed: Boolean;
var
  Ex: TVExposd;
begin
  FillChar(Ex, SizeOf(Ex), 0);
  Result := Ex.L0(Self);
end;

procedure TView.ResetCursor;
var
  X, Y, CaretSize: Integer;
begin
  X := Cursor.X;
  Y := Cursor.Y;
  CaretSize := ComputeCaretSize(Self, X, Y);
  if CaretSize <> 0 then
    if Assigned(CaretPositionHook) then
      CaretPositionHook(X, Y);
  TDisplay.Backend.SetCaretSize(Word(CaretSize));
end;

procedure TView.WriteView(X, Y, Count: SmallInt; B: Pointer);
var
  W: TVWrite;
begin
  FillChar(W, SizeOf(W), 0);
  W.BufIsShort := True;
  W.L0(Self, X, Y, Count, B);
end;

procedure TView.WriteView(X, Y, Count: SmallInt; B: PScreenCell);
var
  W: TVWrite;
begin
  FillChar(W, SizeOf(W), 0);
  W.BufIsShort := False;
  W.L0(Self, X, Y, Count, B);
end;

procedure TView.WriteBuf(X, Y, W, H: SmallInt; B: PScreenCell);
begin
  while H > 0 do
  begin
    Dec(H);
    WriteView(X, Y, W, B);
    Inc(Y);
    B := B + W;
  end;
end;

procedure TView.WriteBuf(X, Y, W, H: SmallInt; B: Pointer);
begin
  while H > 0 do
  begin
    Dec(H);
    WriteView(X, Y, W, B);
    Inc(Y);
    B := PWord(B) + W;
  end;
end;

procedure TView.WriteBuf(X, Y, W, H: SmallInt; const B: TDrawBuffer);
begin
  WriteBuf(X, Y, MinOf(W, SmallInt(TDrawBufferPeek(B).Cap - X)), H, TDrawBufferPeek(B).Cells);
end;

procedure TView.WriteChar(X, Y: SmallInt; C: Char; Color: Byte; Count: SmallInt);
var
  Buf: array of TScreenCell;
begin
  if Count > Size.X then
    Count := Size.X;
  if Count > 0 then
  begin
    SetLength(Buf, Count);
    TTextCells.DrawChar(Buf, C, MapColor(Color));
    WriteView(X, Y, Count, PScreenCell(@Buf[0]));
  end;
end;

procedure TView.WriteLine(X, Y, W, H: SmallInt; B: Pointer);
begin
  while H > 0 do
  begin
    Dec(H);
    WriteView(X, Y, W, B);
    Inc(Y);
  end;
end;

procedure TView.WriteLine(X, Y, W, H: SmallInt; B: PScreenCell);
begin
  while H > 0 do
  begin
    Dec(H);
    WriteView(X, Y, W, B);
    Inc(Y);
  end;
end;

procedure TView.WriteLine(X, Y, W, H: SmallInt; const B: TDrawBuffer);
begin
  WriteLine(X, Y, MinOf(W, SmallInt(TDrawBufferPeek(B).Cap - X)), H, TDrawBufferPeek(B).Cells);
end;

procedure TView.WriteStr(X, Y: SmallInt; const Str: string; Color: Byte);
var
  Count: Integer;
  Buf: array of TScreenCell;
begin
  Count := TText.Width(Str);
  if Count > Size.X then
    Count := Size.X;
  if Count > 0 then
  begin
    SetLength(Buf, Count);
    TTextCells.DrawStr(Buf, Str, MapColor(Color));
    WriteView(X, Y, Count, PScreenCell(@Buf[0]));
  end;
end;

{ TGroup }

constructor TGroup.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  Current := nil;
  Last := nil;
  Phase := phFocused;
  Buffer := nil;
  LockFlag := 0;
  EndState := 0;
  Options := Options or ofSelectable or ofBuffered;
  Clip := GetExtent;
  EventMask := $FFFF;
end;

procedure TGroup.ShutDown;
var
  P, T: TView;
begin
  P := Last;
  if P <> nil then
  begin
    repeat
      P.Hide;
      P := P.Prev;
    until P = Last;

    repeat
      T := P.Prev;
      TvObject.DestroyObject(P);
      P := T;
    until Last = nil;
  end;
  FreeBuffer;
  Current := nil;
  inherited ShutDown;
end;

procedure TGroup.Awaken;
begin
  ForEach(@DoAwaken, nil);
end;

procedure TGroup.ChangeBounds(const Bounds: TRect);
var
  D: TPoint;
begin
  D.X := (Bounds.B.X - Bounds.A.X) - Size.X;
  D.Y := (Bounds.B.Y - Bounds.A.Y) - Size.Y;
  if (D.X = 0) and (D.Y = 0) then
  begin
    SetBounds(Bounds);
    DrawView;
  end
  else
  begin
    SetBounds(Bounds);
    Clip := GetExtent;
    GetBuffer;
    Lock;
    ForEach(@DoCalcChange, @D);
    Unlock;
  end;
end;

function TGroup.DataSize: Word;
var
  T: Word;
begin
  T := 0;
  ForEach(@AddSubviewDataSize, @T);
  Result := T;
end;

procedure TGroup.Remove(P: TView);
var
  WasVisible: Boolean;
begin
  if P = nil then
    Exit;
  WasVisible := AnySet(P.State, sfVisible);
  P.Hide;
  RemoveView(P);
  P.Owner := nil;
  P.Next := nil;
  if WasVisible then
    P.Show;
end;

procedure TGroup.Draw;
var
  Area: TRect;
  Fresh: Boolean;
begin
  Fresh := Buffer = nil;
  if Fresh then
    GetBuffer;
  if Buffer = nil then
  begin
    Area := GetClipRect;
    Clip := Area;
    Redraw;
    Clip := GetExtent;
    Exit;
  end;
  if Fresh then
  begin
    LockFlag := LockFlag + 1;
    Redraw;
    LockFlag := LockFlag - 1;
  end;
  Area := GetExtent;
  WriteBuf(Area.A.X, Area.A.Y, Area.B.X, Area.B.Y, Buffer);
end;

procedure TGroup.DrawSubViews(P, Bottom: TView);
begin
  while P <> Bottom do
  begin
    P.DrawView;
    P := P.NextView;
  end;
end;

procedure TGroup.EndModal(Command: Word);
begin
  if (State and sfModal) <> 0 then
    EndState := Command
  else
    inherited EndModal(Command);
end;

procedure TGroup.EventError(var Event: TEvent);
begin
  if Owner <> nil then
    Owner.EventError(Event);
end;

function TGroup.Execute: Word;
var
  E: TEvent;
begin
  repeat
    EndState := 0;
    while EndState = 0 do
    begin
      FillChar(E, SizeOf(E), 0);
      GetEvent(E);
      HandleEvent(E);
      if E.What = evNothing then
        Continue;
      EventError(E);
    end;
  until Valid(EndState);
  Result := EndState;
end;

function TGroup.ExecView(P: TView): Word;
var
  Saved: TExecSave;
  Owned: Boolean;
begin
  Result := cmCancel;
  if P = nil then
    Exit;

  Saved.Options := P.Options;
  Saved.Owner := P.Owner;
  Saved.Top := TheTopView;
  Saved.Current := Current;
  Owned := P.Owner <> nil;
  GetCommands(Saved.Commands);

  TheTopView := P;
  EnterModal(Self, P);
  if not Owned then
    Insert(P);

  Result := P.Execute;

  if not Owned then
    Remove(P);
  SetCurrent(Saved.Current, leaveSelect);
  P.SetState(sfModal, False);
  P.Options := Saved.Options;
  TheTopView := Saved.Top;
  SetCommands(Saved.Commands);
end;

function TGroup.First: TView;
begin
  Result := nil;
  if Last <> nil then
    Result := Last.Next;
end;

function TGroup.FindNext(Forwards: Boolean): TView;
var
  Cand: TView;
begin
  Result := nil;
  if Current = nil then
    Exit;
  Cand := Current;
  repeat
    if Forwards then
      Cand := Cand.Next
    else
      Cand := Cand.Prev;
  until (Cand = Current) or
        (((Cand.State and (sfVisible or sfDisabled)) = sfVisible) and AnySet(Cand.Options, ofSelectable));
  if Cand <> Current then
    Result := Cand;
end;

function TGroup.FocusNext(Forwards: Boolean): Boolean;
var
  Cand: TView;
begin
  Cand := FindNext(Forwards);
  if Cand = nil then
    Result := True
  else
    Result := Cand.Focus;
end;

function TGroup.FirstMatch(AState, AOptions: Word): TView;
var
  Walk: TView;
begin
  Result := nil;
  if Last = nil then
    Exit;
  Walk := Last;
  repeat
    if AllSet(Walk.State, AState) and AllSet(Walk.Options, AOptions) then
    begin
      Result := Walk;
      Exit;
    end;
    Walk := Walk.Next;
  until Walk = Last;
end;

function TGroup.FirstThat(Func: TFirstThatFunc; Args: Pointer): TView;
var
  Temp: TView;
begin
  Result := nil;
  Temp := Last;
  if Temp = nil then
    Exit;
  repeat
    Temp := Temp.Next;
    if Func(Temp, Args) then
    begin
      Result := Temp;
      Exit;
    end;
  until Temp = Last;
end;

procedure TGroup.ForEach(Func: TForEachFunc; Args: Pointer);
var
  Term, Temp, Nxt: TView;
begin
  Term := Last;
  Temp := Last;
  if Temp = nil then
    Exit;
  Nxt := Temp.Next;
  repeat
    Temp := Nxt;
    { The next view is read before the call, so that Func may remove Temp. }
    Nxt := Temp.Next;
    Func(Temp, Args);
  until Temp = Term;
end;

function TGroup.At(Index: SmallInt): TView;
var
  Temp: TView;
  I: SmallInt;
begin
  Result := nil;
  if (Last = nil) or (Index < 1) then
    Exit;
  Temp := Last;
  for I := 1 to Index do
  begin
    Temp := Temp.Next;
    if (Temp = Last) and (I < Index) then
      Exit;
  end;
  Result := Temp;
end;

function TGroup.IndexOf(P: TView): SmallInt;
var
  Temp: TView;
  I: SmallInt;
begin
  Result := 0;
  if (Last = nil) or (P = nil) then
    Exit;
  Temp := Last;
  I := 0;
  repeat
    Inc(I);
    Temp := Temp.Next;
    if Temp = P then
    begin
      Result := I;
      Exit;
    end;
  until Temp = Last;
end;

procedure TGroup.FreeBuffer;
begin
  if ((Options and ofBuffered) <> 0) and (Buffer <> nil) then
  begin
    FreeMem(Buffer);
    Buffer := nil;
  end;
end;

procedure TGroup.GetBuffer;
var
  Sz: Integer;
begin
  if (State and sfExposed) <> 0 then
    if (Options and ofBuffered) <> 0 then
    begin
      Sz := MaxOf(Size.X * Size.Y * SizeOf(TScreenCell), 0);
      ReallocMem(Pointer(Buffer), Sz);
      { A buffer that is not set may hold control characters, which would be written to the screen. }
      if Buffer <> nil then
        FillChar(Buffer^, Sz, 0);
    end;
end;

procedure TGroup.GetData(Rec: Pointer);
var
  Pos: Word;
  Walk: TView;
begin
  if Last = nil then
    Exit;
  Pos := 0;
  Walk := Last;
  repeat
    Walk.GetData(PByte(Rec) + Pos);
    Inc(Pos, Walk.DataSize);
    Walk := Walk.Prev;
  until Walk = Last;
end;

procedure TGroup.HandleEvent(var Event: TEvent);
var
  Hs: THandleStruct;
begin
  inherited HandleEvent(Event);

  Hs.Event := @Event;
  Hs.Grp := Self;

  if (Event.What and focusedEvents) <> 0 then
  begin
    Phase := phPreProcess;
    ForEach(@DoHandleEvent, @Hs);

    Phase := phFocused;
    DoHandleEvent(Current, @Hs);

    Phase := phPostProcess;
    ForEach(@DoHandleEvent, @Hs);
  end
  else if Event.What <> 0 then
  begin
    Phase := phFocused;
    if (Event.What and positionalEvents) <> 0 then
      DoHandleEvent(FirstThat(@HasMouse, @Event), @Hs)
    else
      ForEach(@DoHandleEvent, @Hs);
  end;
end;

procedure TGroup.Insert(P: TView);
begin
  InsertBefore(P, First);
end;

procedure TGroup.InsertBefore(P, Target: TView);
var
  SaveState: Word;
begin
  if (P <> nil) and (P.Owner = nil) and ((Target = nil) or (Target.Owner = Self)) then
  begin
    if (P.Options and ofCenterX) <> 0 then
      P.Origin.X := (Size.X - P.Size.X) div 2;
    if (P.Options and ofCenterY) <> 0 then
      P.Origin.Y := (Size.Y - P.Size.Y) div 2;
    SaveState := P.State;
    P.Hide;
    InsertView(P, Target);
    if (SaveState and sfVisible) <> 0 then
      P.Show;
    if (SaveState and sfActive) <> 0 then
      P.SetState(sfActive, True);
  end;
end;

procedure TGroup.InsertView(P, Target: TView);
begin
  P.Owner := Self;
  if Target <> nil then
  begin
    Target := Target.Prev;
    P.Next := Target.Next;
    Target.Next := P;
  end
  else
  begin
    if Last = nil then
      P.Next := P
    else
    begin
      P.Next := Last.Next;
      Last.Next := P;
    end;
    Last := P;
  end;
end;

procedure TGroup.Lock;
begin
  if Assigned(Buffer) or (LockFlag > 0) then
    Inc(LockFlag);
end;

procedure TGroup.Redraw;
begin
  DrawSubViews(First, nil);
end;

procedure TGroup.RemoveView(P: TView);
var
  S: TView;
begin
  if Last <> nil then
  begin
    S := Last;
    while S.Next <> P do
    begin
      if S.Next = Last then
        Exit;
      S := S.Next;
    end;
    S.Next := P.Next;
    if P = Last then
    begin
      if P = P.Next then
        Last := nil
      else
        Last := S;
    end;
  end;
end;

procedure TGroup.ResetCurrent;
begin
  SetCurrent(FirstMatch(sfVisible, ofSelectable), normalSelect);
end;

procedure TGroup.ResetCursor;
begin
  if Current <> nil then
    Current.ResetCursor;
end;

procedure TGroup.SelectNext(Forwards: Boolean);
var
  Cand: TView;
begin
  if Current = nil then
    Exit;
  Cand := FindNext(Forwards);
  if Cand <> nil then
    Cand.Select;
end;

procedure TGroup.SelectView(P: TView; Enable: Boolean);
begin
  if P <> nil then
    P.SetState(sfSelected, Enable);
end;

procedure TGroup.FocusView(P: TView; Enable: Boolean);
begin
  if AnySet(State, sfFocused) and (P <> nil) then
    P.SetState(sfFocused, Enable);
end;

procedure TGroup.SetCurrent(P: TView; Mode: TSelectMode);
begin
  if Current = P then
    Exit;
  Lock;
  FocusView(Current, False);
  if (Mode <> enterSelect) and (Current <> nil) then
    Current.SetState(sfSelected, False);
  if (Mode <> leaveSelect) and (P <> nil) then
    P.SetState(sfSelected, True);
  if AnySet(State, sfFocused) and (P <> nil) then
    P.SetState(sfFocused, True);
  Current := P;
  Unlock;
end;

procedure TGroup.SetData(Rec: Pointer);
var
  Pos: Word;
  Walk: TView;
begin
  if Last = nil then
    Exit;
  Pos := 0;
  Walk := Last;
  repeat
    Walk.SetData(PByte(Rec) + Pos);
    Inc(Pos, Walk.DataSize);
    Walk := Walk.Prev;
  until Walk = Last;
end;

procedure TGroup.SetState(AState: Word; Enable: Boolean);
var
  Sb: TSetBlock;
begin
  Sb.St := AState;
  Sb.En := Enable;

  inherited SetState(AState, Enable);

  if (AState and (sfActive or sfDragging)) <> 0 then
  begin
    Lock;
    ForEach(@DoSetState, @Sb);
    Unlock;
  end;

  if (AState and sfFocused) <> 0 then
  begin
    if Current <> nil then
      Current.SetState(sfFocused, Enable);
  end;

  if (AState and sfExposed) <> 0 then
  begin
    ForEach(@DoExpose, @Enable);
    if not Enable then
      FreeBuffer;
  end;
end;

procedure TGroup.Unlock;
begin
  if LockFlag = 0 then
    Exit;
  Dec(LockFlag);
  if LockFlag = 0 then
    DrawView;
end;

function TGroup.Valid(Command: Word): Boolean;
begin
  if Command <> cmReleasedFocus then
  begin
    Result := FirstThat(@IsInvalid, @Command) = nil;
    Exit;
  end;
  Result := True;
  if (Current <> nil) and AnySet(Current.Options, ofValidate) then
    Result := Current.Valid(Command);
end;

function TGroup.GetHelpCtx: Word;
begin
  Result := hcNoContext;
  if Current <> nil then
    Result := Current.GetHelpCtx;
  if Result = hcNoContext then
    Result := inherited GetHelpCtx;
end;

initialization
  EmptyPalette := TPalette.Create('', 0);
  ShadowSize := MakePoint(2, 1);
  ShadowAttr := TColorAttr.Create($08);
  TView.ShowMarkers := False;
  TView.ErrorAttr := TColorAttr.Create($CF);
  TView.CommandSetChanged := False;
  TView.CurCommandSet := InitCommands;

finalization
  EmptyPalette.Free;

end.
