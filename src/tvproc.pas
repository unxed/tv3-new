{ Runs other programs for a terminal program: a command line in the system shell with the terminal handed back to the
  system or left alone, a program with its output captured, and a restart of the running program. Only the Unix
  target is implemented: the branches for Windows and DOS are left out. }
unit TvProc;

{$mode objfpc}
{$R-}
{$Q-}

interface

var
  { Hooks that give the terminal back to the system and take it again. When a hook is not assigned, the terminal
    backend routine (UnixSuspend, UnixResume) is called if it is assigned. }
  OnSuspend: TProcedure = nil;
  OnResume: TProcedure = nil;
  UnixSuspend: TProcedure = nil;
  UnixResume: TProcedure = nil;
  { True while the terminal backend is active. }
  UnixActive: Boolean = False;

function RunShell(const CmdLine: AnsiString; Pause: Boolean = False;
  const PauseText: AnsiString = 'Press Enter to return...'): LongInt;
function RunQuiet(const CmdLine: AnsiString): LongInt;
function RunCapture(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
function RunFirstLine(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
procedure RestartSelf;

implementation

function RunShell(const CmdLine: AnsiString; Pause: Boolean; const PauseText: AnsiString): LongInt;
begin
  Result := -1;
end;

function RunQuiet(const CmdLine: AnsiString): LongInt;
begin
  Result := -1;
end;

function RunCapture(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
begin
  Result := '';
end;

function RunFirstLine(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
begin
  Result := '';
end;

procedure RestartSelf;
begin
end;

end.
