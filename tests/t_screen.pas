{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (TDisplay, TScreen), source/tvision/tscreen.cpp
  See COPYRIGHT.magiblot. }
program t_screen;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  SysUtils, TvCell, TvDrawBuf, TvSys, TvScreen;

{$I testlib.inc}

type
  { A display that notes its calls in Log and keeps a mode, a size and a cursor size. The letters of the log:
    U SetUpConsole, R RestoreConsole, M get the mode, m<mode> set the mode, C get the cursor size,
    c<size> set the cursor size, W get the columns, H get the rows, X<w>x<h> clear, A allocate the buffer,
    D free the buffer, F flush. }
  TFakeDisplay = class(TScreenBackend)
  public
    Log: string;
    Mode: Word;
    Cols: Word;
    Rows: Word;
    Caret: Word;
    Allocated: Integer;
    Freed: Integer;
    LastBuffer: PScreenCell;
    LastFreed: PScreenCell;
    procedure Note(const S: string);
    procedure SetUpConsole; override;
    procedure RestoreConsole; override;
    function GetCaretSize: Word; override;
    procedure SetCaretSize(Size: Word); override;
    procedure ClearScreen(W, H: Byte); override;
    function GetScreenRows: Word; override;
    function GetScreenCols: Word; override;
    function GetScreenMode: Word; override;
    procedure SetScreenMode(Mode: Word); override;
    function AllocateScreenBuffer: PScreenCell; override;
    procedure FreeScreenBuffer(Buffer: PScreenCell); override;
    procedure FlushScreen; override;
  end;

  { A mouse that notes the range it is given. }
  TFakeMouse = class(TEventBackend)
  public
    Present: Boolean;
    RangeCalls: Integer;
    RangeX: Integer;
    RangeY: Integer;
    function MousePresent: Boolean; override;
    procedure MouseSetRange(MaxX, MaxY: Integer); override;
  end;

procedure TFakeDisplay.Note(const S: string);
begin
  if Log <> '' then
    Log := Log + ' ';
  Log := Log + S;
end;

procedure TFakeDisplay.SetUpConsole;
begin
  Note('U');
end;

procedure TFakeDisplay.RestoreConsole;
begin
  Note('R');
end;

function TFakeDisplay.GetCaretSize: Word;
begin
  Note('C');
  Result := Caret;
end;

procedure TFakeDisplay.SetCaretSize(Size: Word);
begin
  Note('c' + IntToStr(Size));
  Caret := Size;
end;

procedure TFakeDisplay.ClearScreen(W, H: Byte);
begin
  Note('X' + IntToStr(W) + 'x' + IntToStr(H));
end;

function TFakeDisplay.GetScreenRows: Word;
begin
  Note('H');
  Result := Rows;
end;

function TFakeDisplay.GetScreenCols: Word;
begin
  Note('W');
  Result := Cols;
end;

function TFakeDisplay.GetScreenMode: Word;
begin
  Note('M');
  Result := Mode;
end;

{ A mode with the 8x8 font has fifty rows. }
procedure TFakeDisplay.SetScreenMode(Mode: Word);
begin
  Note('m' + IntToHex(Mode, 1));
  Self.Mode := Mode;
  if (Mode and TDisplay.smFont8x8) <> 0 then
    Rows := 50
  else
    Rows := 25;
end;

function TFakeDisplay.AllocateScreenBuffer: PScreenCell;
begin
  Note('A');
  Inc(Allocated);
  GetMem(Result, Cols * Rows * SizeOf(TScreenCell));
  FillChar(Result^, Cols * Rows * SizeOf(TScreenCell), 0);
  LastBuffer := Result;
end;

procedure TFakeDisplay.FreeScreenBuffer(Buffer: PScreenCell);
begin
  Note('D');
  Inc(Freed);
  LastFreed := Buffer;
  if Buffer <> nil then
    FreeMem(Buffer);
end;

procedure TFakeDisplay.FlushScreen;
begin
  Note('F');
end;

function TFakeMouse.MousePresent: Boolean;
begin
  Result := Present;
end;

procedure TFakeMouse.MouseSetRange(MaxX, MaxY: Integer);
begin
  Inc(RangeCalls);
  RangeX := MaxX;
  RangeY := MaxY;
end;

var
  Fake: TFakeDisplay;
  Mouse: TFakeMouse;
  SavedMouse: TEventBackend;
  SavedDisplay: TScreenBackend;
  Base: TScreenBackend;
  Scr: TScreen;
  FirstBuffer: PScreenCell;
  Cell: TScreenCell;

begin
  { The values before any screen exists. }
  Check(TScreen.StartupMode = $FFFF, 'startup mode before the screen');
  Check(TScreen.StartupCursor = 0, 'startup cursor before the screen');
  Check(TScreen.ScreenMode = 0, 'screen mode before the screen');
  Check(ScreenWidth = 0, 'width before the screen');
  Check(ScreenHeight = 0, 'height before the screen');
  Check(not TScreen.HiResScreen, 'hi-res before the screen');
  Check(TScreen.CheckSnow, 'check snow before the screen');
  Check(TScreen.ScreenBuffer = nil, 'buffer before the screen');
  Check(TScreen.CursorLines = 0, 'cursor lines before the screen');
  Check(TScreen.ClearOnSuspend, 'clear on suspend before the screen');

  { The video modes. }
  Check(TDisplay.smBW80 = $0002, 'smBW80');
  Check(TDisplay.smCO80 = $0003, 'smCO80');
  Check(TDisplay.smMono = $0007, 'smMono');
  Check(TDisplay.smFont8x8 = $0100, 'smFont8x8');
  Check(TDisplay.smColor256 = $0200, 'smColor256');
  Check(TDisplay.smColorHigh = $0400, 'smColorHigh');
  Check(TDisplay.smUpdate = $8000, 'smUpdate');

  { The base backend has no display. }
  SavedDisplay := TDisplay.Backend;
  Check(SavedDisplay <> nil, 'there is a default backend');
  Check(TDisplay.GetCols = 0, 'default columns');
  Check(TDisplay.GetRows = 0, 'default rows');
  Check(TDisplay.GetCrtMode = 0, 'default mode');
  Check(TDisplay.GetCursorType = 0, 'default cursor type');
  TDisplay.SetCursorType(5);
  TDisplay.SetCrtMode(3);
  TDisplay.ClearScreen(1, 1);
  TScreen.FlushScreen;
  Check(TDisplay.GetCrtMode = 0, 'default mode stays');
  Base := TScreenBackend.Create;
  Check(Base.AllocateScreenBuffer = nil, 'default gives no buffer');
  Base.FreeScreenBuffer(nil);
  Base.Free;

  Fake := TFakeDisplay.Create;
  Fake.Mode := TDisplay.smCO80;
  Fake.Cols := 80;
  Fake.Rows := 25;
  Fake.Caret := 25;
  TDisplay.Backend := Fake;
  SavedMouse := TEventQueue.Backend;
  Mouse := TFakeMouse.Create;
  Mouse.Present := True;
  TEventQueue.Backend := Mouse;

  { The calls to the display. }
  Check(TDisplay.GetCols = 80, 'columns');
  Check(TDisplay.GetRows = 25, 'rows');
  Check(TDisplay.GetCrtMode = 3, 'mode');
  Check(TDisplay.GetCursorType = 25, 'cursor type');
  Fake.Log := '';
  TDisplay.SetCursorType($0107);
  Check(Fake.Caret = 7, 'cursor type keeps the low byte');
  TDisplay.SetCursorType($1234);
  Check(Fake.Caret = $34, 'cursor type drops the high byte');
  TDisplay.SetCursorType(0);
  Check(Fake.Caret = 0, 'cursor type zero');
  Check(Fake.Log = 'c7 c52 c0', 'cursor type calls');
  Fake.Log := '';
  TDisplay.ClearScreen(80, 25);
  Check(Fake.Log = 'X80x25', 'display clear');
  Fake.Log := '';
  TDisplay.SetCrtMode(TDisplay.smBW80);
  Check(Fake.Log = 'm2', 'set mode');
  Check(Fake.Mode = 2, 'mode is set');
  Fake.Mode := TDisplay.smCO80;
  Fake.Caret := 25;

  { Creating the screen. }
  Fake.Log := '';
  Scr := TScreen.Create;
  Check(Fake.Log = 'U M C A M W H C c0', 'create calls: ' + Fake.Log);
  Check(TScreen.StartupMode = 3, 'startup mode');
  Check(TScreen.StartupCursor = 25, 'startup cursor');
  Check(TScreen.ScreenMode = 3, 'screen mode');
  Check(ScreenWidth = 80, 'width');
  Check(ScreenHeight = 25, 'height');
  Check(not TScreen.HiResScreen, 'not hi-res at 25 rows');
  Check(TScreen.CursorLines = 25, 'cursor lines are the cursor of the start');
  Check(Fake.Caret = 0, 'cursor is hidden');
  Check(Fake.Allocated = 1, 'one buffer');
  Check(TScreen.ScreenBuffer = Fake.LastBuffer, 'screen buffer');
  Check(TScreen.ScreenBuffer <> nil, 'screen buffer is there');
  FirstBuffer := TScreen.ScreenBuffer;

  { The buffer holds the cells of the screen. }
  Cell := TScreenCell.Create($1F51);
  PScreenCell(FirstBuffer)[24 * 80 + 79] := Cell;
  Check(PScreenCell(TScreen.ScreenBuffer)[24 * 80 + 79] = Cell, 'last cell of the buffer');

  { Clearing and flushing. }
  Fake.Log := '';
  TScreen.ClearScreen;
  Check(Fake.Log = 'X80x25', 'clear screen');
  Fake.Log := '';
  TScreen.FlushScreen;
  Check(Fake.Log = 'F', 'flush screen');

  { The mode is kept. }
  Check(TScreen.FixCrtMode(TDisplay.smCO80) = 3, 'fix mode CO80');
  Check(TScreen.FixCrtMode(TDisplay.smMono) = 7, 'fix mode mono');
  Check(TScreen.FixCrtMode(TDisplay.smCO80 or TDisplay.smFont8x8) = $0103, 'fix mode with the 8x8 font');

  { A new mode with the mouse present. }
  Fake.Log := '';
  TScreen.SetVideoMode(TDisplay.smCO80 or TDisplay.smFont8x8);
  Check(Fake.Log = 'm103 M W H C c0 W H', 'set video mode calls: ' + Fake.Log);
  Check(TScreen.ScreenMode = $0103, 'mode after the change');
  Check(ScreenHeight = 50, 'height after the change');
  Check(TScreen.HiResScreen, 'hi-res at 50 rows');
  Check(TScreen.CursorLines = 0, 'cursor lines are the hidden cursor');
  Check(Mouse.RangeCalls = 1, 'mouse range is set');
  Check((Mouse.RangeX = 79) and (Mouse.RangeY = 49), 'mouse range');
  Check(Fake.Allocated = 1, 'the buffer stays');
  Check(TScreen.ScreenBuffer = FirstBuffer, 'same buffer after the change');

  { The same mode with the mouse absent. }
  Mouse.Present := False;
  Fake.Log := '';
  TScreen.SetVideoMode(TDisplay.smCO80);
  Check(Fake.Log = 'm3 M W H C c0', 'set video mode calls without a mouse: ' + Fake.Log);
  Check(ScreenHeight = 25, 'height back');
  Check(not TScreen.HiResScreen, 'hi-res back');
  Check(Mouse.RangeCalls = 1, 'mouse range is not set without a mouse');
  Mouse.Present := True;

  { An update takes a new buffer and does not change the mode. }
  Fake.Cols := 100;
  Fake.Rows := 40;
  Fake.Log := '';
  TScreen.SetVideoMode(TDisplay.smUpdate);
  Check(Fake.Log = 'D A M W H C c0 W H', 'update calls: ' + Fake.Log);
  Check(Fake.LastFreed = FirstBuffer, 'the old buffer is freed');
  Check(Fake.Allocated = 2, 'a new buffer');
  Check(TScreen.ScreenBuffer = Fake.LastBuffer, 'the new buffer is the screen buffer');
  Check(ScreenWidth = 100, 'width after the update');
  Check(ScreenHeight = 40, 'height after the update');
  Check(TScreen.HiResScreen, 'hi-res after the update');
  Check(Mouse.RangeCalls = 2, 'mouse range after the update');
  Check((Mouse.RangeX = 99) and (Mouse.RangeY = 39), 'mouse range after the update values');
  Fake.Cols := 80;
  Fake.Rows := 25;
  TScreen.SetVideoMode(TDisplay.smUpdate);

  { The width and the height go to the display as bytes. }
  ScreenWidth := 300;
  ScreenHeight := 25;
  Fake.Log := '';
  TScreen.ClearScreen;
  Check(Fake.Log = 'X44x25', 'clear screen with a byte width');
  ScreenWidth := 80;

  { Suspend and resume. }
  TScreen.SetVideoMode(TDisplay.smCO80 or TDisplay.smFont8x8);
  Fake.Log := '';
  TScreen.Suspend;
  Check(Fake.Log = 'm3 X80x50 c25 R', 'suspend calls: ' + Fake.Log);
  Check(Fake.Mode = 3, 'mode of the start is back');
  Check(Fake.Caret = 25, 'cursor of the start is back');
  Fake.Log := '';
  TScreen.Resume;
  Check(Fake.Log = 'U M C m103 M W H C c0', 'resume calls: ' + Fake.Log);
  Check(Fake.Mode = $0103, 'mode of the screen is back');
  Check(TScreen.StartupMode = 3, 'startup mode after the resume');
  Check(TScreen.StartupCursor = 25, 'startup cursor after the resume');
  Check(Fake.Caret = 0, 'cursor is hidden after the resume');

  { Suspend with the same mode and without the clear. }
  TScreen.SetVideoMode(TDisplay.smCO80);
  TScreen.ClearOnSuspend := False;
  Fake.Log := '';
  TScreen.Suspend;
  Check(Fake.Log = 'c25 R', 'suspend without a change and without a clear: ' + Fake.Log);
  TScreen.ClearOnSuspend := True;
  Fake.Log := '';
  TScreen.Resume;
  Check(Fake.Log = 'U M C M W H C c0', 'resume with the same mode: ' + Fake.Log);

  { Destroying the screen gives the console back. }
  Fake.Log := '';
  Scr.Free;
  Check(Fake.Log = 'X80x25 c25 R D', 'destroy calls: ' + Fake.Log);
  Check(Fake.Freed = Fake.Allocated, 'every buffer is freed');
  Check(Fake.LastFreed = Fake.LastBuffer, 'the screen buffer is freed');

  TEventQueue.Backend := SavedMouse;
  Mouse.Free;
  TDisplay.Backend := SavedDisplay;
  Fake.Free;

  { A screen on the base backend has no buffer. }
  Scr := TScreen.Create;
  Check(TScreen.ScreenBuffer = nil, 'no buffer on the base backend');
  Check(ScreenWidth = 0, 'no width on the base backend');
  Check(not TScreen.HiResScreen, 'no hi-res on the base backend');
  Scr.Free;

  Done;
end.
