{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (TDisplay, TScreen), source/tvision/tscreen.cpp
  See COPYRIGHT.magiblot.

  Only the branch of both files for the flat memory model is translated; the branch for DOS (the BIOS video
  interrupt, isEGAorVGA, videoInt, the screen buffer at a fixed address) is left out, and so is fixCrtMode for
  Borland compilers, which leaves the mode as it is for every other compiler. TDisplay::updateIntlChars has no
  C++ source among the inputs and is left out.

  Everything that THardwareInfo provides is a hook: the methods of TScreenBackend, which do nothing, answer zero
  and give no screen buffer. The program sets TDisplay.Backend to a backend that talks to a display. The calls to
  TMouse::present and TMouse::setRange go to TEventQueue.Backend of TvSys.

  TScreen::screenWidth and TScreen::screenHeight are the variables ScreenWidth and ScreenHeight of TvDrawBuf,
  which TScreen sets; TScreen has no members of those names. The C++ type ushort is a Word, uchar is a Byte,
  and TScreenCell * is a PScreenCell. The members of TScreen are class members: the constructor takes the
  console, the destructor gives it back. }
unit TvScreen;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvDrawBuf;

type
  { The display hardware, as TDisplay and TScreen use it. The base class has no display: the routines do nothing
    and the numbers they return are zero. }
  TScreenBackend = class
  public
    procedure SetUpConsole; virtual;
    procedure RestoreConsole; virtual;
    function GetCaretSize: Word; virtual;
    procedure SetCaretSize(Size: Word); virtual;
    procedure ClearScreen(W, H: Byte); virtual;
    function GetScreenRows: Word; virtual;
    function GetScreenCols: Word; virtual;
    function GetScreenMode: Word; virtual;
    procedure SetScreenMode(Mode: Word); virtual;
    { Gives a buffer of the cells of the screen; nil when there is none. }
    function AllocateScreenBuffer: PScreenCell; virtual;
    procedure FreeScreenBuffer(Buffer: PScreenCell); virtual;
    procedure FlushScreen; virtual;
  end;

  { The video modes and the routines that ask the display for its state and change it. }
  TDisplay = class
  public
    const
      smBW80 = $0002;
      smCO80 = $0003;
      smMono = $0007;
      smFont8x8 = $0100;
      smColor256 = $0200;
      smColorHigh = $0400;
      smUpdate = $8000;
    { The display. The program sets it before the first TScreen is created. }
    class var Backend: TScreenBackend;
    class procedure ClearScreen(W, H: Byte); overload; static;
    class procedure SetCursorType(CT: Word); static;
    class function GetCursorType: Word; static;
    class function GetRows: Word; static;
    class function GetCols: Word; static;
    class procedure SetCrtMode(Mode: Word); static;
    class function GetCrtMode: Word; static;
  end;

  TScreen = class(TDisplay)
  public
    class var StartupMode: Word;
    class var StartupCursor: Word;
    class var ScreenMode: Word;
    class var HiResScreen: Boolean;
    class var CheckSnow: Boolean;
    class var ScreenBuffer: PScreenCell;
    class var CursorLines: Word;
    class var ClearOnSuspend: Boolean;
    { Takes the console, notes the mode and the cursor of the start, takes the screen buffer and reads the state
      of the screen. }
    constructor Create;
    { Gives the console back. }
    destructor Destroy; override;
    class procedure SetVideoMode(Mode: Word); static;
    class procedure ClearScreen; overload; static;
    class procedure FlushScreen; static;
    class procedure SetCrtData; static;
    class function FixCrtMode(Mode: Word): Word; static;
    class procedure Suspend; static;
    class procedure Resume; static;
  end;

implementation

{ TScreenBackend }

procedure TScreenBackend.SetUpConsole;
begin
end;

procedure TScreenBackend.RestoreConsole;
begin
end;

function TScreenBackend.GetCaretSize: Word;
begin
  Result := 0;
end;

procedure TScreenBackend.SetCaretSize(Size: Word);
begin
end;

procedure TScreenBackend.ClearScreen(W, H: Byte);
begin
end;

function TScreenBackend.GetScreenRows: Word;
begin
  Result := 0;
end;

function TScreenBackend.GetScreenCols: Word;
begin
  Result := 0;
end;

function TScreenBackend.GetScreenMode: Word;
begin
  Result := 0;
end;

procedure TScreenBackend.SetScreenMode(Mode: Word);
begin
end;

function TScreenBackend.AllocateScreenBuffer: PScreenCell;
begin
  Result := nil;
end;

procedure TScreenBackend.FreeScreenBuffer(Buffer: PScreenCell);
begin
end;

procedure TScreenBackend.FlushScreen;
begin
end;

{ TDisplay }

class procedure TDisplay.ClearScreen(W, H: Byte);
begin
end;

class procedure TDisplay.SetCursorType(CT: Word);
begin
end;

class function TDisplay.GetCursorType: Word;
begin
  Result := 0;
end;

class function TDisplay.GetRows: Word;
begin
  Result := 0;
end;

class function TDisplay.GetCols: Word;
begin
  Result := 0;
end;

class procedure TDisplay.SetCrtMode(Mode: Word);
begin
end;

class function TDisplay.GetCrtMode: Word;
begin
  Result := 0;
end;

{ TScreen }

constructor TScreen.Create;
begin
  inherited Create;
end;

destructor TScreen.Destroy;
begin
  inherited Destroy;
end;

class procedure TScreen.SetVideoMode(Mode: Word);
begin
end;

class procedure TScreen.ClearScreen;
begin
end;

class procedure TScreen.FlushScreen;
begin
end;

class procedure TScreen.SetCrtData;
begin
end;

class function TScreen.FixCrtMode(Mode: Word): Word;
begin
  Result := Mode;
end;

class procedure TScreen.Suspend;
begin
end;

class procedure TScreen.Resume;
begin
end;

end.
