{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/dispbuff.h, source/platform/dispbuff.cpp,
  include/tvision/internal/platform.h (the class DisplayAdapter), include/tvision/scrncell.h,
  include/tvision/internal/mutex.h, source/platform/mutex.cpp
  See COPYRIGHT.magiblot.

  DisplayAdapter is the class of platform.h whose virtual members do nothing, or give zero, by default.
  DisplayBuffer keeps the screen cells, the rows of damage, the caret and the cursor, and writes to a
  DisplayAdapter. The cell buffer is a dynamic array; ReloadScreenInfo gives a pointer to its first cell, nil while
  the buffer is empty, and the pointer stays the same while the size of the screen stays the same. The members that
  C++ declares private are private to the unit, and the algorithm of FlushScreen is the class FlushScreenAlgorithm of
  the implementation, which reads them.

  The time points of the C++ steady clock are microseconds of DisplayClock, a function that returns a QWord. The
  members begin and end of the damage range are RangeBegin and RangeEnd, because both are reserved words.

  SignalSafeMutexState stands for the spin lock of mutex.h: a recursive critical section, with the thread that holds
  it, so the nesting of a thread that holds the lock needs no separate check. }
unit TvDispBuf;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  SysUtils, TvGeom, TvColors, TvCell;

type
  PScreenCell = ^TScreenCell;

  { Returns a time in microseconds that never goes back. }
  TDisplayClockFunc = function: QWord;

  { The part of a terminal or window that shows the cells. }
  DisplayAdapter = class
  public
    function ReloadScreenInfo: TPoint; virtual;
    function GetColorCount: Integer; virtual;
    function GetFontSize: TPoint; virtual;
    procedure WriteCell(const Pos: TPoint; const Text: string; const Attr: TColorAttr;
      DoubleWidth: Boolean); virtual;
    procedure SetCaretPosition(const Pos: TPoint); virtual;
    procedure SetCaretSize(Size: Integer); virtual;
    procedure ClearScreen; virtual;
    procedure Flush; virtual;
  end;

  DisplayBuffer = class
  private
    type
      Range = record
        RangeBegin, RangeEnd: Integer;
      end;
    var
      Buffer, FlushBuffer: array of TScreenCell;
      RowDamage: array of Range;
      WideOverlapping: Boolean;
      ScreenTouched: Boolean;
      CaretOrCursorChanged: Boolean;
      CaretPosition: TPoint;
      NewCaretSize: Integer;
      CursorPosition: TPoint;
      CursorVisible: Boolean;
      AttrUnderCursor: TColorAttr;
      MaxFps: Integer;
      FlushDelay: QWord;
      LastFlush: QWord;
      PendingFlush: QWord;
    procedure InitState(AMaxFps: Integer);
    function InBounds(X, Y: Integer): Boolean;
    procedure ResizeBuffer;
    procedure SetDirty(X, Y, Len: Integer);
    procedure DrawCursor;
    procedure UndrawCursor;
    function NeedsFlush: Boolean;
    function TimeToFlush: Boolean;
  public
    Size: TPoint;
    CaretSize: Integer;
    constructor Create(AMaxFps: Integer);
    procedure Reset;
    procedure SetCaretSize(ASize: Integer);
    procedure SetCaretPosition(X, Y: Integer);
    procedure ScreenWrite(X, Y: Integer; Buf: PScreenCell; Len: Integer);
    procedure ClearScreen(Display: DisplayAdapter);
    procedure RedrawScreen(Display: DisplayAdapter);
    procedure FlushScreen(Display: DisplayAdapter);
    function ReloadScreenInfo(Display: DisplayAdapter): PScreenCell;
    procedure SetCursorPosition(X, Y: Integer);
    procedure SetCursorVisibility(Visible: Boolean);
    function TimeUntilPendingFlushMs: Integer;
  end;

  { A lock that the thread which holds it may take again. }
  SignalSafeMutexState = class
  private
    Section: TRTLCriticalSection;
    LockingThread: TThreadID;
    Depth: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function LockedByCurrentThread: Boolean;
    procedure Acquire;
    procedure Release;
  end;

var
  { The clock of the buffer; the default counts the milliseconds of the run-time library. }
  DisplayClock: TDisplayClockFunc;

implementation

uses
  TvText;

const
{$IFDEF WINDOWS}
  DefaultFps = 120;
{$ELSE}
  DefaultFps = 60;
{$ENDIF}

function SystemClock: QWord;
begin
  Result := QWord(GetTickCount64) * 1000;
end;

{ DisplayAdapter }

function DisplayAdapter.ReloadScreenInfo: TPoint;
begin
  Result.X := 0;
  Result.Y := 0;
end;

function DisplayAdapter.GetColorCount: Integer;
begin
  Result := 0;
end;

function DisplayAdapter.GetFontSize: TPoint;
begin
  Result.X := 0;
  Result.Y := 0;
end;

procedure DisplayAdapter.WriteCell(const Pos: TPoint; const Text: string; const Attr: TColorAttr;
  DoubleWidth: Boolean);
begin
end;

procedure DisplayAdapter.SetCaretPosition(const Pos: TPoint);
begin
end;

procedure DisplayAdapter.SetCaretSize(Size: Integer);
begin
end;

procedure DisplayAdapter.ClearScreen;
begin
end;

procedure DisplayAdapter.Flush;
begin
end;

{ SignalSafeMutexState }

constructor SignalSafeMutexState.Create;
begin
  inherited Create;
  InitCriticalSection(Section);
  LockingThread := TThreadID(0);
  Depth := 0;
end;

destructor SignalSafeMutexState.Destroy;
begin
  DoneCriticalSection(Section);
  inherited Destroy;
end;

function SignalSafeMutexState.LockedByCurrentThread: Boolean;
begin
  Result := LockingThread = GetCurrentThreadId;
end;

procedure SignalSafeMutexState.Acquire;
begin
  EnterCriticalSection(Section);
  LockingThread := GetCurrentThreadId;
  Inc(Depth);
end;

procedure SignalSafeMutexState.Release;
begin
  Dec(Depth);
  if Depth = 0 then
    LockingThread := TThreadID(0);
  LeaveCriticalSection(Section);
end;

{ The cells of a buffer }

{ The number of cells of a screen; a side that is not positive leaves none. }
function CellCountOf(const Dim: TPoint): Integer;
var
  Columns, Rows: Integer;
begin
  Columns := Dim.X;
  Rows := Dim.Y;
  if Columns < 1 then
    Columns := 0;
  if Rows < 1 then
    Rows := 0;
  Result := Columns * Rows;
end;

function IsTrailCell(const Cell: TScreenCell): Boolean;
begin
  Result := Cell.Character.IsWideCharTrail;
end;

function IsWideCell(const Cell: TScreenCell): Boolean;
begin
  Result := Cell.Character.IsWide;
end;

function NegateAttribute(const Attr: TColorAttr): TColorAttr;
begin
  Result := TColorAttr.Create(Integer(Attr.ToBIOS xor $77));
end;

function PackedUtf8Of(C: Char): Cardinal;
begin
  if Assigned(CodePageToPackedUtf8) then
    Result := CodePageToPackedUtf8(C)
  else
    Result := Byte(C);
end;

{ The algorithm that writes the damaged cells of a buffer to an adapter. }
type
  FlushScreenAlgorithm = class
  private
    Disp: DisplayBuffer;
    Display: DisplayAdapter;
    Size: TPoint;
    X, Y, RowOffs: Integer;
    CellIdx: Integer;
    Damage: DisplayBuffer.Range;
    function CellAt(Col: Integer): TScreenCell;
    procedure GetCell;
    function CellDirty: Boolean;
    function WideCanOverlap: Boolean;
    procedure Run;
    procedure ProcessCell;
    procedure WriteCell; overload;
    procedure WriteSpace;
    procedure WriteCell(const Ch: TScreenCharacter; const Attr: TColorAttr; Wide: Boolean); overload;
    procedure CommitDirty;
    procedure EnsureCharacterIsPrintable(var Cell: TScreenCell);
    procedure HandleWideCharSpill;
    procedure HandleTrail;
  public
    constructor Create(ADisp: DisplayBuffer; ADisplay: DisplayAdapter);
  end;

constructor FlushScreenAlgorithm.Create(ADisp: DisplayBuffer; ADisplay: DisplayAdapter);
begin
  inherited Create;
  Disp := ADisp;
  Display := ADisplay;
  Size := ADisp.Size;
  X := 0;
  Y := 0;
  RowOffs := 0;
  CellIdx := 0;
  Damage.RangeBegin := 0;
  Damage.RangeEnd := -1;
end;

function FlushScreenAlgorithm.CellAt(Col: Integer): TScreenCell;
begin
  Result := Disp.Buffer[RowOffs + Col];
end;

procedure FlushScreenAlgorithm.GetCell;
begin
  CellIdx := RowOffs + X;
  EnsureCharacterIsPrintable(Disp.Buffer[CellIdx]);
end;

function FlushScreenAlgorithm.CellDirty: Boolean;
begin
  Result := Disp.Buffer[CellIdx] <> Disp.FlushBuffer[CellIdx];
end;

procedure FlushScreenAlgorithm.CommitDirty;
begin
  Disp.FlushBuffer[CellIdx] := Disp.Buffer[CellIdx];
end;

function FlushScreenAlgorithm.WideCanOverlap: Boolean;
begin
  Result := Disp.WideOverlapping;
end;

procedure FlushScreenAlgorithm.Run;
var
  WideSpillBefore: Boolean;
begin
  Size := Disp.Size;
  RowOffs := 0;
  Y := 0;
  while Y < Size.Y do
  begin
    Damage := Disp.RowDamage[Y];
    if Damage.RangeBegin <= Damage.RangeEnd then
    begin
      X := Damage.RangeBegin;
      { A wide character before the first position may need to be drawn again when overlapping is not allowed. }
      WideSpillBefore := (not WideCanOverlap) and (X > 0) and IsWideCell(CellAt(X - 1));
      while X <= Damage.RangeEnd do
      begin
        GetCell;
        if CellDirty or IsTrailCell(Disp.Buffer[CellIdx]) then
        begin
          if WideSpillBefore then
          begin
            Dec(X);
            GetCell;
            WideSpillBefore := False;
          end;
          CommitDirty;
          ProcessCell;
        end
        else
          WideSpillBefore := (not WideCanOverlap) and IsWideCell(Disp.Buffer[CellIdx]);
        Inc(X);
      end;
      if X < Size.X then
      begin
        GetCell;
        { The start of a wide character may have been overwritten, and the trails after it can spill attributes. }
        if IsTrailCell(Disp.Buffer[CellIdx]) then
          HandleTrail;
      end;
    end;
    Disp.RowDamage[Y].RangeBegin := High(Integer);
    Disp.RowDamage[Y].RangeEnd := Low(Integer);
    Inc(Y);
    Inc(RowOffs, Size.X);
  end;
end;

procedure FlushScreenAlgorithm.ProcessCell;
begin
  if IsWideCell(Disp.Buffer[CellIdx]) then
    HandleWideCharSpill
  else if IsTrailCell(Disp.Buffer[CellIdx]) then
    HandleTrail
  else
    WriteCell;
end;

procedure FlushScreenAlgorithm.WriteCell;
begin
  WriteCell(Disp.Buffer[CellIdx].Character, Disp.Buffer[CellIdx].Attribute,
    Disp.Buffer[CellIdx].Character.IsWide);
end;

procedure FlushScreenAlgorithm.WriteSpace;
var
  Blank: TScreenCharacter;
begin
  Blank.InitWithChar(' ');
  WriteCell(Blank, Disp.Buffer[CellIdx].Attribute, False);
end;

procedure FlushScreenAlgorithm.WriteCell(const Ch: TScreenCharacter; const Attr: TColorAttr; Wide: Boolean);
var
  Where: TPoint;
begin
  Where.X := X;
  Where.Y := Y;
  Display.WriteCell(Where, Ch.GetText, Attr, Wide);
end;

procedure FlushScreenAlgorithm.EnsureCharacterIsPrintable(var Cell: TScreenCell);
var
  Text: string;
  First: Byte;
begin
  if Cell.Character.IsWideCharTrail then
    Exit;
  Text := Cell.Character.GetText;
  First := Byte(Text[1]);
  if First = 0 then
    Cell.Character.InitWithChar(' ')
  else if (Length(Text) = 1) and ((First < 32) or (First >= $7F)) then
    { A single byte outside the printable ASCII range is taken from the code page. }
    Cell.Character.InitWithMultiByteChar(PackedUtf8Of(Char(First)));
end;

procedure FlushScreenAlgorithm.HandleWideCharSpill;
var
  Width, Before: Byte;
  Attr: TColorAttr;
  WBegin, WEnd: Integer;
begin
  Width := Ord(Disp.Buffer[CellIdx].Character.IsWide);
  Attr := Disp.Buffer[CellIdx].Attribute;
  if X + Width < Size.X then
    WriteCell
  else
  begin
    { The character would be printed on the next line: spaces take its place. }
    WriteSpace;
    repeat
      Dec(Width);
      if Width = 0 then
        Break;
      Inc(X);
      if X >= Size.X then
        Break;
      GetCell;
      if not IsTrailCell(Disp.Buffer[CellIdx]) then
      begin
        Dec(X);
        Exit;
      end;
      WriteSpace;
    until False;
    Exit;
  end;
  { The character must not spill on the next cells. }
  WBegin := X;
  repeat
    Before := Width;
    Dec(Width);
    if Before = 0 then
      Break;
    Inc(X);
    if X >= Size.X then
      Break;
    GetCell;
    CommitDirty;
    if not IsTrailCell(Disp.Buffer[CellIdx]) then
    begin
      if WideCanOverlap then
        WriteCell
      else
      begin
        WEnd := X;
        X := WBegin;
        repeat
          GetCell;
          WriteSpace;
          Inc(X);
        until X >= WEnd;
        GetCell;
        WriteCell;
      end;
      Exit;
    end;
  until False;
  { A next cell with another attribute is written anyway, so that the attribute does not spill. }
  if X + 1 < Size.X then
  begin
    Inc(X);
    GetCell;
    if Attr <> Disp.Buffer[CellIdx].Attribute then
    begin
      CommitDirty;
      ProcessCell;
    end
    else
      Dec(X);
  end;
end;

procedure FlushScreenAlgorithm.HandleTrail;
var
  Attr: TColorAttr;
begin
  Attr := Disp.Buffer[CellIdx].Attribute;
  if X > 0 then
  begin
    Dec(X);
    GetCell;
    { The cell behind the placeholder holds a wide character. }
    if Disp.Buffer[CellIdx].Character.IsWide then
    begin
      HandleWideCharSpill;
      Exit;
    end;
    Inc(X);
    GetCell;
  end;
  { The successive placeholders are written as spaces. }
  repeat
    CommitDirty;
    WriteSpace;
    Inc(X);
    if X < Size.X then
      GetCell
    else
      Exit;
  until not IsTrailCell(Disp.Buffer[CellIdx]);
  { A normal character follows. It is written when it would not be reached otherwise and its attribute differs. }
  if (X > Damage.RangeEnd) and (Attr <> Disp.Buffer[CellIdx].Attribute) then
    ProcessCell
  else
    Dec(X);
end;

{ DisplayBuffer }

constructor DisplayBuffer.Create(AMaxFps: Integer);
begin
  inherited Create;
{$IFDEF WINDOWS}
  WideOverlapping := False;
{$ELSE}
  WideOverlapping := True;
{$ENDIF}
  InitState(AMaxFps);
end;

procedure DisplayBuffer.InitState(AMaxFps: Integer);
begin
  if AMaxFps < 0 then
    MaxFps := DefaultFps
  else
    MaxFps := AMaxFps;
  FlushDelay := 0;
  if MaxFps > 0 then
    FlushDelay := QWord(1000000 div MaxFps);
  SetLength(Buffer, 0);
  SetLength(FlushBuffer, 0);
  SetLength(RowDamage, 0);
  ScreenTouched := True;
  CaretOrCursorChanged := False;
  CaretPosition.X := -1;
  CaretPosition.Y := -1;
  NewCaretSize := 0;
  CursorPosition.X := -1;
  CursorPosition.Y := -1;
  CursorVisible := False;
  FillChar(AttrUnderCursor, SizeOf(AttrUnderCursor), 0);
  LastFlush := 0;
  PendingFlush := 0;
  Size.X := 0;
  Size.Y := 0;
  CaretSize := -1;
end;

procedure DisplayBuffer.Reset;
begin
  InitState(MaxFps);
end;

function DisplayBuffer.InBounds(X, Y: Integer): Boolean;
begin
  Result := (0 <= X) and (X < Size.X) and (0 <= Y) and (Y < Size.Y);
end;

function DisplayBuffer.ReloadScreenInfo(Display: DisplayAdapter): PScreenCell;
begin
  Size := Display.ReloadScreenInfo;
  CaretSize := -1;
  ResizeBuffer;
  if Length(Buffer) > 0 then
    Result := @Buffer[0]
  else
    Result := nil;
end;

procedure DisplayBuffer.ResizeBuffer;
var
  Wanted, Idx: Integer;
begin
  Wanted := CellCountOf(Size);
  { The storage is kept when the size does not change, so a pointer to the cells stays valid. }
  if Wanted <> Length(Buffer) then
    SetLength(Buffer, Wanted);
  if Wanted <> Length(FlushBuffer) then
    SetLength(FlushBuffer, Wanted);
  for Idx := 0 to Wanted - 1 do
  begin
    FillChar(Buffer[Idx], SizeOf(TScreenCell), 0);
    FillChar(FlushBuffer[Idx], SizeOf(TScreenCell), 0);
  end;
  SetLength(RowDamage, Ord(Size.Y > 0) * Size.Y);
  for Idx := Length(RowDamage) - 1 downto 0 do
  begin
    RowDamage[Idx].RangeEnd := Low(Integer);
    RowDamage[Idx].RangeBegin := High(Integer);
  end;
end;

procedure DisplayBuffer.ClearScreen(Display: DisplayAdapter);
begin
  Display.ClearScreen;
  Display.Flush;
  ResizeBuffer;
end;

procedure DisplayBuffer.RedrawScreen(Display: DisplayAdapter);
var
  Row: Integer;
begin
  ScreenTouched := True;
  LastFlush := 0;
  if Length(FlushBuffer) > 0 then
    FillChar(FlushBuffer[0], Length(FlushBuffer) * SizeOf(TScreenCell), 0);
  for Row := 0 to Length(RowDamage) - 1 do
  begin
    RowDamage[Row].RangeBegin := 0;
    RowDamage[Row].RangeEnd := Size.X - 1;
  end;
  FlushScreen(Display);
end;

procedure DisplayBuffer.SetCaretSize(ASize: Integer);
begin
  NewCaretSize := ASize;
end;

procedure DisplayBuffer.SetCaretPosition(X, Y: Integer);
begin
  CaretPosition.X := X;
  CaretPosition.Y := Y;
  CaretOrCursorChanged := True;
end;

procedure DisplayBuffer.ScreenWrite(X, Y: Integer; Buf: PScreenCell; Len: Integer);
var
  Dst: PScreenCell;
begin
  if not (InBounds(X, Y) and (Len > 0)) then
    Exit;
  if Len > Size.X - X then
    Len := Size.X - X;
  Dst := @Buffer[Y * Size.X + X];
  { The buffer is also the screen buffer that views write into, so the source is often the destination itself.
    Move copes with regions that overlap. }
  if Buf <> Dst then
    Move(Buf^, Dst^, Len * SizeOf(TScreenCell));
  SetDirty(X, Y, Len);
  ScreenTouched := True;
end;

procedure DisplayBuffer.SetDirty(X, Y, Len: Integer);
var
  Dam: Range;
begin
  Dam := RowDamage[Y];
  if X < Dam.RangeBegin then
    Dam.RangeBegin := X;
  if X + Len - 1 > Dam.RangeEnd then
    Dam.RangeEnd := X + Len - 1;
  RowDamage[Y] := Dam;
end;

function DisplayBuffer.TimeToFlush: Boolean;
var
  Current, Due: QWord;
begin
  Result := True;
  { A flush may not come sooner than the maximum rate allows. }
  if MaxFps <= 0 then
    Exit;
  Current := DisplayClock();
  Due := LastFlush + FlushDelay;
  if Due <= Current then
  begin
    LastFlush := Current;
    PendingFlush := 0;
  end
  else
  begin
    PendingFlush := Due;
    Result := False;
  end;
end;

function DisplayBuffer.TimeUntilPendingFlushMs: Integer;
var
  Current: QWord;
begin
  if PendingFlush = 0 then
  begin
    Result := -1;
    Exit;
  end;
  Current := DisplayClock();
  if PendingFlush < Current then
    Result := 0
  else
    Result := Integer((PendingFlush - Current) div 1000);
end;

procedure DisplayBuffer.SetCursorPosition(X, Y: Integer);
var
  Pos: TPoint;
begin
  Pos.X := X;
  Pos.Y := Y;
  if CursorVisible and (CursorPosition <> Pos) then
    CaretOrCursorChanged := True;
  CursorPosition := Pos;
end;

procedure DisplayBuffer.SetCursorVisibility(Visible: Boolean);
begin
  if CursorVisible <> Visible then
    CaretOrCursorChanged := True;
  CursorVisible := Visible;
end;

procedure DisplayBuffer.DrawCursor;
var
  X, Y, Idx: Integer;
begin
  if not CursorVisible then
    Exit;
  X := CursorPosition.X;
  Y := CursorPosition.Y;
  if not InBounds(X, Y) then
    Exit;
  Idx := Y * Size.X + X;
  { The cursor on the trail of a wide character is drawn on the character itself. }
  if Buffer[Idx].Character.IsWideCharTrail and (X > 0) and Buffer[Idx - 1].Character.IsWide then
  begin
    Dec(Idx);
    Dec(X);
  end;
  AttrUnderCursor := Buffer[Idx].Attribute;
  Buffer[Idx].Attribute := NegateAttribute(Buffer[Idx].Attribute);
  SetDirty(X, Y, 1);
end;

procedure DisplayBuffer.UndrawCursor;
var
  X, Y, Idx: Integer;
begin
  if not CursorVisible then
    Exit;
  X := CursorPosition.X;
  Y := CursorPosition.Y;
  if not InBounds(X, Y) then
    Exit;
  Idx := Y * Size.X + X;
  if Buffer[Idx].Character.IsWideCharTrail and (X > 0) and Buffer[Idx - 1].Character.IsWide then
  begin
    Dec(Idx);
    Dec(X);
  end;
  Buffer[Idx].Attribute := AttrUnderCursor;
  SetDirty(X, Y, 1);
end;

function DisplayBuffer.NeedsFlush: Boolean;
begin
  Result := ScreenTouched or CaretOrCursorChanged or (CaretSize <> NewCaretSize);
end;

procedure DisplayBuffer.FlushScreen(Display: DisplayAdapter);
var
  Algorithm: FlushScreenAlgorithm;
begin
  if not NeedsFlush then
    Exit;
  if not TimeToFlush then
    Exit;
  DrawCursor;
  Algorithm := FlushScreenAlgorithm.Create(Self, Display);
  try
    Algorithm.Run;
  finally
    Algorithm.Free;
  end;
  if CaretPosition.X <> -1 then
    Display.SetCaretPosition(CaretPosition);
  UndrawCursor;
  if CaretSize <> NewCaretSize then
    Display.SetCaretSize(NewCaretSize);
  Display.Flush;
  ScreenTouched := False;
  CaretOrCursorChanged := False;
  CaretSize := NewCaretSize;
end;

initialization
  DisplayClock := @SystemClock;

end.
