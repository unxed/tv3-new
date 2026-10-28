{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/termemu.h, include/tvterm/array.h, include/tvterm/mutex.h, include/tvterm/consts.h
  See COPYRIGHT.tvterm.

  The state, the events and the interface of a terminal emulator.

  A range of rows that has no row is {MaxInt, MinInt}; RowRange.Unset gives it, because a record has no default
  constructor. TerminalSurface descends from TDrawSurface of TvSurface and keeps the members of its base public, so
  the members that the C++ makes visible with using lines (Size, At) are visible, and so are the others. A span of
  elements is a pointer with a length (TEnvironmentVarSpan, TWordSpan) when it is a result and a const open array
  when it is a parameter. The lock of Mutex is a critical section of the run-time library; a program that uses more
  than one thread must use the unit cthreads on Unix. A memory failure raises the exception of the run-time
  library. }
unit TvVtCore;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvEvents, TvSurface, TvPty;

type
  { struct RowRange: valid when Start < RangeEnd. }
  RowRange = record
    Start: Integer;
    RangeEnd: Integer;
    constructor Create(AStart, AEnd: Integer);
    { The range that holds no row. }
    class function Unset: RowRange; static;
    function Size: Integer;
    function Intersect(const Other: RowRange): RowRange;
    class operator <>(const A, B: RowRange): Boolean;
  end;

  PRowRange = ^RowRange;

  { struct SelectionAnchor: a point in absolute coordinates, Y = 0 being the oldest scrollback line. }
  SelectionAnchor = record
    X: Integer;
    Y: Integer;
    constructor Create(AX, AY: Integer); overload;
    constructor Create(const P: TPoint); overload;
    class operator <(const A, B: SelectionAnchor): Boolean;
    class operator >(const A, B: SelectionAnchor): Boolean;
    class operator =(const A, B: SelectionAnchor): Boolean;
    { Three-way comparison: below 0, 0 or above 0 as the anchor comes before, at or after Other. }
    function Compare(const Other: SelectionAnchor): Integer;
    function ToPoint: TPoint;
  end;

  { struct SelectionRange: the selection goes from Start to RangeEnd with the column of RangeEnd excluded; both
    orders of the two anchors are valid and equal anchors make an empty selection. }
  SelectionRange = record
    Start: SelectionAnchor;
    RangeEnd: SelectionAnchor;
    constructor Create(const AStart, AEnd: SelectionAnchor);
    function Empty: Boolean;
    function IntersectRow(Y, Cols: Integer): RowRange;
  end;

  { A TDrawSurface that keeps the range of modified cells of every row. }
  TerminalSurface = class(TDrawSurface)
  private
    DamageByRow: array of RowRange;
  public
    constructor Create; reintroduce;
    { Sets the size when it differs from the present one, and then clears the damage. }
    procedure Resize(const ASize: TPoint); reintroduce;
    { Gives every row of the surface an empty range. }
    procedure ClearDamage;
    { The address of the range of a row, which stands for the reference result of the C++ function. }
    function DamageAtRow(Y: SizeUInt): PRowRange;
    procedure AddDamageAtRow(Y: SizeUInt; ABegin, AEnd: Integer);
  end;

  { A growing array of bytes. }
  GrowArray = class
  private
    Buf: PAnsiChar;
    Used: SizeUInt;
    Cap: SizeUInt;
    procedure Grow(MinCapacity: SizeUInt);
  public
    destructor Destroy; override;
    function Data: PAnsiChar;
    function Size: SizeUInt;
    procedure Push(AData: PAnsiChar; ASize: SizeUInt);
    procedure Clear;
  end;

  { struct TerminalState: what the emulator reports to the controller. }
  TerminalState = class
  public
    Surface: TerminalSurface;
    CursorChanged: Boolean;
    CursorPos: TPoint;
    CursorVisible: Boolean;
    CursorBlink: Boolean;
    TitleChanged: Boolean;
    Title: GrowArray;
    ScrollbackChanged: Boolean;
    { 0 (oldest) to ScrollbackLimit (no scrollback shown) }
    ScrollbackOffset: Integer;
    ScrollbackLimit: Integer;
    ScrollbackEnabled: Boolean;
    MouseEnabled: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

{$SCOPEDENUMS ON}
  TerminalEventType = (
    KeyDown,
    Mouse,
    ClientDataRead,
    ViewportResize,
    FocusChange,
    ScrollBackOffsetChange,
    CopySelection
  );
{$SCOPEDENUMS OFF}

  MouseEvent = record
    What: Word;
    Mouse: TMouseEventType;
  end;

  ClientDataReadEvent = record
    Data: PAnsiChar;
    Size: SizeUInt;
  end;

  ViewportResizeEvent = record
    X: Integer;
    Y: Integer;
  end;

  FocusChangeEvent = record
    FocusEnabled: Boolean;
  end;

  ScrollBackOffsetChangeEvent = record
    Offset: Integer;
  end;

  CopySelectionEvent = record
    Selection: SelectionRange;
  end;

  { The member Type_ tells which of the members that share the storage is valid. }
  TerminalEvent = record
    Type_: TerminalEventType;
    case Byte of
      0: (KeyDown: TKeyDownEvent);
      1: (Mouse: MouseEvent);
      2: (ClientDataRead: ClientDataReadEvent);
      3: (ViewportResize: ViewportResizeEvent);
      4: (FocusChange: FocusChangeEvent);
      5: (ScrollBackOffsetChange: ScrollBackOffsetChangeEvent);
      6: (CopySelection: CopySelectionEvent);
  end;

  TerminalEmulator = class
  public
    { Called when the user interacts with the terminal or the client process sends data. }
    procedure HandleEvent(const Event: TerminalEvent); virtual; abstract;
    { Called shortly after HandleEvent, so that the changes can be reported through the state. }
    procedure UpdateState(State: TerminalState); virtual; abstract;
  end;

  Writer = class
  public
    procedure Write(const Data: array of Char); virtual; abstract;
  end;

  { A pointer to the first of Size environment variables. }
  PEnvironmentVar = ^EnvironmentVar;

  TEnvironmentVarSpan = record
    Data: PEnvironmentVar;
    Size: SizeUInt;
  end;

  TerminalEmulatorFactory = class
  public
    { Gives a new emulator. ClientDataWriter is not owned and outlives the emulator. }
    function Make(const Size: TPoint; ClientDataWriter: Writer): TerminalEmulator; virtual; abstract;
    { The variables that the emulator needs the client process to have; the result lives as long as the factory. }
    function GetCustomEnvironment: TEnvironmentVarSpan; virtual; abstract;
  end;

  { A pointer to the first of Size words. }
  TWordSpan = record
    Data: PWord;
    Size: SizeUInt;
  end;

  { The nine commands and help contexts of a terminal view; the commands of CmGrabInput to CmStartSelection are
    contiguous. }
  TVTermConstants = record
    CmCheckTerminalUpdates: Word;
    CmTerminalUpdated: Word;
    CmCopySelection: Word;
    CmCancelSelection: Word;
    CmGrabInput: Word;
    CmReleaseInput: Word;
    CmStartSelection: Word;
    HcInputGrabbed: Word;
    HcSelecting: Word;
    { The commands that are active while a terminal window is focused. }
    function FocusedCmds: TWordSpan;
  end;

  { The message that carries an updated state; View is the TerminalView of the C++, whose class is not part of
    this unit. }
  TerminalUpdatedMsg = record
    View: TObject;
    State: TerminalState;
  end;

  { The procedure that Mutex.Lock calls with its item. }
  generic TMutexProc<T> = procedure(var Item: T) of object;

  { A value that is used under a lock. }
  generic Mutex<T> = class
  private
    Section: TRTLCriticalSection;
    Item: T;
  public
    constructor Create; overload;
    constructor Create(const AItem: T); overload;
    destructor Destroy; override;
    { Runs Func with the item while the lock is held. }
    procedure Lock(Func: specialize TMutexProc<T>);
  end;

implementation

uses
  Math;

{ RowRange }

constructor RowRange.Create(AStart, AEnd: Integer);
begin
  Start := AStart;
  RangeEnd := AEnd;
end;

class function RowRange.Unset: RowRange;
begin
  Result.Start := High(LongInt);
  Result.RangeEnd := Low(LongInt);
end;

function RowRange.Size: Integer;
begin
  if Start < RangeEnd then
    Result := RangeEnd - Start
  else
    Result := 0;
end;

function RowRange.Intersect(const Other: RowRange): RowRange;
begin
  Result.Start := Max(Start, Other.Start);
  Result.RangeEnd := Min(RangeEnd, Other.RangeEnd);
end;

class operator RowRange.<>(const A, B: RowRange): Boolean;
begin
  Result := (A.Start <> B.Start) or (A.RangeEnd <> B.RangeEnd);
end;

{ SelectionAnchor }

constructor SelectionAnchor.Create(AX, AY: Integer);
begin
  X := AX;
  Y := AY;
end;

constructor SelectionAnchor.Create(const P: TPoint);
begin
  Y := P.Y;
  X := P.X;
end;

function SelectionAnchor.Compare(const Other: SelectionAnchor): Integer;
var
  Gap: Integer;
begin
  Gap := 0;
  if Y <> Other.Y then
    Gap := Y - Other.Y
  else if X <> Other.X then
    Gap := X - Other.X;
  if Gap < 0 then
    Result := -1
  else if Gap > 0 then
    Result := 1
  else
    Result := 0;
end;

function SelectionAnchor.ToPoint: TPoint;
begin
  Result.Y := Y;
  Result.X := X;
end;

class operator SelectionAnchor.<(const A, B: SelectionAnchor): Boolean;
begin
  Result := A.Compare(B) < 0;
end;

class operator SelectionAnchor.>(const A, B: SelectionAnchor): Boolean;
begin
  Result := A.Compare(B) > 0;
end;

class operator SelectionAnchor.=(const A, B: SelectionAnchor): Boolean;
begin
  Result := A.Compare(B) = 0;
end;

{ SelectionRange }

constructor SelectionRange.Create(const AStart, AEnd: SelectionAnchor);
begin
  Start := AStart;
  RangeEnd := AEnd;
end;

function SelectionRange.Empty: Boolean;
begin
  Result := Start = RangeEnd;
end;

function SelectionRange.IntersectRow(Y, Cols: Integer): RowRange;
var
  Low, High: SelectionAnchor;
  First, Last: Integer;
begin
  if RangeEnd < Start then
  begin
    Low := RangeEnd;
    High := Start;
  end
  else
  begin
    Low := Start;
    High := RangeEnd;
  end;

  if Empty or (Y < Low.Y) or (Y > High.Y) then
  begin
    Result := RowRange.Unset;
    Exit;
  end;

  if Y = Low.Y then
    First := Max(Low.X, 0)
  else
    First := 0;
  if Y = High.Y then
    Last := Min(High.X, Cols)
  else
    Last := Cols;
  Result := RowRange.Create(First, Last);
end;

{ TerminalSurface }

constructor TerminalSurface.Create;
begin
  inherited Create;
  SetLength(DamageByRow, 0);
end;

procedure TerminalSurface.Resize(const ASize: TPoint);
begin
  if ASize <> Size then
  begin
    inherited Resize(ASize);
    ClearDamage;
  end;
end;

procedure TerminalSurface.ClearDamage;
var
  Row: Integer;
begin
  SetLength(DamageByRow, 0);
  SetLength(DamageByRow, Max(0, Size.Y));
  for Row := 0 to High(DamageByRow) do
    DamageByRow[Row] := RowRange.Unset;
end;

function TerminalSurface.DamageAtRow(Y: SizeUInt): PRowRange;
begin
  Result := @DamageByRow[Y];
end;

procedure TerminalSurface.AddDamageAtRow(Y: SizeUInt; ABegin, AEnd: Integer);
var
  Hurt: PRowRange;
begin
  Hurt := DamageAtRow(Y);
  Hurt^ := RowRange.Create(Min(ABegin, Hurt^.Start), Max(AEnd, Hurt^.RangeEnd));
end;

{ GrowArray }

destructor GrowArray.Destroy;
begin
  if Buf <> nil then
    FreeMem(Buf);
  inherited Destroy;
end;

procedure GrowArray.Grow(MinCapacity: SizeUInt);
var
  Wanted: SizeUInt;
  Raw: Pointer;
begin
  Wanted := MinCapacity;
  if 2 * Cap > Wanted then
    Wanted := 2 * Cap;
  Raw := Buf;
  Raw := ReAllocMem(Raw, Wanted);
  Buf := PAnsiChar(Raw);
  Cap := Wanted;
end;

function GrowArray.Data: PAnsiChar;
begin
  Result := Buf;
end;

function GrowArray.Size: SizeUInt;
begin
  Result := Used;
end;

procedure GrowArray.Push(AData: PAnsiChar; ASize: SizeUInt);
var
  Total: SizeUInt;
begin
  Total := Used + ASize;
  if Total > Cap then
    Grow(Total);
  if ASize > 0 then
    Move(AData^, Buf[Used], ASize);
  Used := Total;
end;

procedure GrowArray.Clear;
begin
  Used := 0;
end;

{ TerminalState }

constructor TerminalState.Create;
begin
  inherited Create;
  Surface := TerminalSurface.Create;
  Title := GrowArray.Create;
  CursorPos.X := 0;
  CursorPos.Y := 0;
  ScrollbackEnabled := True;
end;

destructor TerminalState.Destroy;
begin
  Title.Free;
  Surface.Free;
  inherited Destroy;
end;

{ TVTermConstants }

function TVTermConstants.FocusedCmds: TWordSpan;
var
  Distance: PtrUInt;
begin
  Distance := PtrUInt(@CmStartSelection) - PtrUInt(@CmGrabInput);
  Result.Data := @CmGrabInput;
  Result.Size := Distance div SizeOf(Word) + 1;
end;

{ Mutex }

constructor Mutex.Create;
begin
  inherited Create;
  InitCriticalSection(Section);
end;

constructor Mutex.Create(const AItem: T);
begin
  inherited Create;
  InitCriticalSection(Section);
  Item := AItem;
end;

destructor Mutex.Destroy;
begin
  DoneCriticalSection(Section);
  inherited Destroy;
end;

procedure Mutex.Lock(Func: specialize TMutexProc<T>);
begin
  EnterCriticalSection(Section);
  try
    Func(Item);
  finally
    LeaveCriticalSection(Section);
  end;
end;

end.
