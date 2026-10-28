{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/pty.h, source/tvterm-core/pty.cc (the branch for systems other than Windows; the
  branch of the Windows pseudo console is not translated), include/tvterm/array.h (not used by these sources),
  and, from magiblot/tvision, include/tvision/tspan.h
  See COPYRIGHT.tvterm.

  The pseudo terminal is made with the function forkpty of the C library, which the unit declares as an external
  function (libutil on Linux and the BSD systems, the C library itself on Darwin); the other C functions that the
  C++ calls in the child process (signal, setenv, getenv, execvp, _exit, strerror, cfsetispeed, cfsetospeed) are
  external declarations of the C library too. The reading, writing, ioctl, kill and waitpid calls are those of
  BaseUnix. The record of the terminal mode and the constants of its flags have the values of the Linux system;
  the unit is built only for Linux.

  A TSpan has no unit in the library, so a span of elements is an open array: TSpan<const EnvironmentVar> is a
  const open array of EnvironmentVar, TSpan<char> is a var open array of Char and TSpan<const char> is a const open
  array of Char. The size of a span is the length of the open array. }
unit TvPty;

{$mode objfpc}
{$R-}
{$Q-}

interface

{$IFNDEF LINUX}
{$FATAL TvPty is built for Linux only}
{$ENDIF}

uses
  ctypes, BaseUnix, TvGeom;

type
  { struct PtyDescriptor of the Unix branch. }
  PtyDescriptor = record
    MasterFd: cint;
    ClientPid: TPid;
  end;

  { struct EnvironmentVar: two blocks of characters with a terminating zero. }
  EnvironmentVar = record
    Name: PAnsiChar;
    Value: PAnsiChar;
  end;

  { void (&onError)(const char *reason) }
  TPtyErrorProc = procedure(Reason: PAnsiChar);

  PtyMaster = class
  private
    D: PtyDescriptor;
  public
    constructor Create(ADescriptor: PtyDescriptor);
    { Reads at least one byte, waiting for it, and then the bytes that are available at once, at most the length
      of Data in all. BytesRead is the number of bytes that were stored. False when a read fails. }
    function ReadFromClient(var Data: array of Char; out BytesRead: SizeUInt): Boolean;
    { Writes all the bytes of Data. False when a write fails. }
    function WriteToClient(const Data: array of Char): Boolean;
    procedure ResizeClient(Size: TPoint);
    { Closes the master side, sends SIGHUP to the client, waits a second, and kills the client if it is still
      there. }
    procedure Disconnect;
  end;

{ Starts the program of the environment variable SHELL on a new pseudo terminal of the given size, after the
  variables of Environment were set in the client. On success ADescriptor is filled and the result is True; when
  the fork fails OnError is called with the reason and the result is False. }
function CreatePty(var ADescriptor: PtyDescriptor; Size: TPoint; const Environment: array of EnvironmentVar;
  OnError: TPtyErrorProc): Boolean;

implementation

uses
  SysUtils;

const
{$IFDEF DARWIN}
  PtyLib = 'c';
{$ELSE}
  PtyLib = 'util';
{$ENDIF}

  { Values of the Linux system. }
  ReqFionread = $541B;
  ReqSetWinSize = $5414;

  FlagIcrnl = $100;
  FlagIxon = $400;
  FlagIutf8 = $4000;
  FlagOpost = 1;
  FlagOnlcr = 4;
  FlagCs8 = $30;
  FlagCread = $80;
  FlagIsig = 1;
  FlagIcanon = 2;
  FlagEcho = 8;
  FlagEchoe = $10;
  FlagEchok = $20;
  FlagEchoctl = $200;
  FlagEchoke = $800;
  FlagIexten = $8000;
  SpeedB38400 = 15;

  CcVintr = 0;
  CcVquit = 1;
  CcVerase = 2;
  CcVkill = 3;
  CcVeof = 4;
  CcVtime = 5;
  CcVmin = 6;
  CcVstart = 8;
  CcVstop = 9;
  CcVsusp = 10;
  CcVeol = 11;
  CcVreprint = 12;
  CcVwerase = 14;
  CcVlnext = 15;
  CcVeol2 = 16;
  CcCount = 32;
  PosixVdisable = 0;

  EintrCode = 4;
  ExitFailureCode = 1;
  DefaultHandler: Pointer = nil;

type
  {$PACKRECORDS C}
  TPtyTermios = record
    IFlag: cuint;
    OFlag: cuint;
    CFlag: cuint;
    LFlag: cuint;
    Line: Byte;
    Cc: array[0..CcCount - 1] of Byte;
    ISpeed: cuint;
    OSpeed: cuint;
  end;

  TPtyWinSize = record
    Row: Word;
    Col: Word;
    XPixel: Word;
    YPixel: Word;
  end;
  {$PACKRECORDS DEFAULT}

function CForkPty(var Master: cint; Name: PAnsiChar; var Mode: TPtyTermios; var Win: TPtyWinSize): cint;
  cdecl; external PtyLib name 'forkpty';
function CSignal(Sig: cint; Handler: Pointer): Pointer; cdecl; external 'c' name 'signal';
function CSetEnv(Name, Value: PAnsiChar; Overwrite: cint): cint; cdecl; external 'c' name 'setenv';
function CGetEnv(Name: PAnsiChar): PAnsiChar; cdecl; external 'c' name 'getenv';
function CExecVp(Prog: PAnsiChar; Args: PPAnsiChar): cint; cdecl; external 'c' name 'execvp';
procedure CExit(Code: cint); cdecl; external 'c' name '_exit';
function CStrError(Code: cint): PAnsiChar; cdecl; external 'c' name 'strerror';
function CSetInputSpeed(var Mode: TPtyTermios; Speed: cuint): cint; cdecl; external 'c' name 'cfsetispeed';
function CSetOutputSpeed(var Mode: TPtyTermios; Speed: cuint): cint; cdecl; external 'c' name 'cfsetospeed';
function CErrnoLocation: PCInt; cdecl; external 'c' name '__errno_location';

function LibcErrno: cint;
begin
  Result := CErrnoLocation^;
end;

function CreateWinsize(Size: TPoint): TPtyWinSize;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Row := Word(Size.Y and $FFFF);
  Result.Col := Word(Size.X and $FFFF);
end;

function CreateTermios: TPtyTermios;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.IFlag := FlagIcrnl or FlagIxon;
  Result.OFlag := FlagOpost or FlagOnlcr;
  Result.CFlag := FlagCs8 or FlagCread;
  Result.LFlag := FlagIsig or FlagIcanon or FlagIexten or FlagEcho or FlagEchoe or FlagEchok;
  Result.IFlag := Result.IFlag or FlagIutf8;
  Result.LFlag := Result.LFlag or FlagEchoctl or FlagEchoke;
  Result.Cc[CcVintr] := 3;
  Result.Cc[CcVquit] := 28;
  Result.Cc[CcVerase] := $7F;
  Result.Cc[CcVkill] := 21;
  Result.Cc[CcVeof] := 4;
  Result.Cc[CcVeol] := PosixVdisable;
  Result.Cc[CcVeol2] := PosixVdisable;
  Result.Cc[CcVstart] := 17;
  Result.Cc[CcVstop] := 19;
  Result.Cc[CcVsusp] := 26;
  Result.Cc[CcVreprint] := 18;
  Result.Cc[CcVwerase] := 23;
  Result.Cc[CcVlnext] := 22;
  Result.Cc[CcVmin] := 1;
  Result.Cc[CcVtime] := 0;
  CSetInputSpeed(Result, SpeedB38400);
  CSetOutputSpeed(Result, SpeedB38400);
end;

{ Writes a block of characters with a terminating zero to the standard error output; the child process uses it
  because it must not allocate memory. }
procedure SayOnStderr(Text: PAnsiChar);
var
  Len: PtrInt;
begin
  if Text = nil then
    Exit;
  Len := 0;
  while Text[Len] <> #0 do
    Inc(Len);
  if Len > 0 then
    fpWrite(2, Text, Len);
end;

procedure RunClient(const Environment: array of EnvironmentVar);
var
  Index: Integer;
  Shell: PAnsiChar;
  Args: array[0..1] of PAnsiChar;
begin
  { The default handlers of the signals of the terminal driver apply. }
  CSignal(SIGINT, DefaultHandler);
  CSignal(SIGQUIT, DefaultHandler);
  CSignal(SIGSTOP, DefaultHandler);
  CSignal(SIGCONT, DefaultHandler);

  for Index := 0 to High(Environment) do
    CSetEnv(Environment[Index].Name, Environment[Index].Value, 1);

  Shell := CGetEnv('SHELL');
  Args[0] := Shell;
  Args[1] := nil;
  CExecVp(Shell, @Args[0]);

  SayOnStderr(#27'[1;31m');
  SayOnStderr('Error: Failed to execute the program specified by the environment variable SHELL (''');
  SayOnStderr(Shell);
  SayOnStderr('''): ');
  SayOnStderr(CStrError(LibcErrno));
  SayOnStderr(#27'[0m');
  CExit(ExitFailureCode);
end;

function CreatePty(var ADescriptor: PtyDescriptor; Size: TPoint; const Environment: array of EnvironmentVar;
  OnError: TPtyErrorProc): Boolean;
var
  Mode: TPtyTermios;
  Win: TPtyWinSize;
  MasterFd: cint;
  ClientPid: cint;
  Failure: AnsiString;
begin
  Mode := CreateTermios;
  Win := CreateWinsize(Size);
  MasterFd := -1;
  ClientPid := CForkPty(MasterFd, nil, Mode, Win);
  if ClientPid = 0 then
    RunClient(Environment)
  else if ClientPid = -1 then
  begin
    Failure := 'forkpty failed: ' + AnsiString(CStrError(LibcErrno));
    OnError(PAnsiChar(Failure));
    Result := False;
    Exit;
  end;
  ADescriptor.MasterFd := MasterFd;
  ADescriptor.ClientPid := ClientPid;
  Result := True;
end;

{ PtyMaster }

constructor PtyMaster.Create(ADescriptor: PtyDescriptor);
begin
  inherited Create;
  D := ADescriptor;
end;

function PtyMaster.ReadFromClient(var Data: array of Char; out BytesRead: SizeUInt): Boolean;
var
  Got: TSsize;
  Available: cint;
  Wanted: SizeInt;
begin
  BytesRead := 0;
  Result := True;
  if Length(Data) <= 1 then
    Exit;
  Got := fpRead(D.MasterFd, PAnsiChar(@Data[0]), 1);
  if Got < 0 then
  begin
    Result := False;
    Exit;
  end;
  if Got = 0 then
    Exit;
  Inc(BytesRead, SizeUInt(Got));
  Available := 0;
  if (fpIOCtl(D.MasterFd, ReqFionread, @Available) <> -1) and (Available > 0) then
  begin
    Wanted := Length(Data) - 1;
    if Available < Wanted then
      Wanted := Available;
    Got := fpRead(D.MasterFd, PAnsiChar(@Data[1]), Wanted);
    if Got < 0 then
    begin
      Result := False;
      Exit;
    end;
    Inc(BytesRead, SizeUInt(Got));
  end;
end;

function PtyMaster.WriteToClient(const Data: array of Char): Boolean;
var
  Done: SizeInt;
  Sent: TSsize;
begin
  Done := 0;
  while Done < Length(Data) do
  begin
    Sent := fpWrite(D.MasterFd, PAnsiChar(@Data[Done]), Length(Data) - Done);
    if Sent < 0 then
    begin
      Result := False;
      Exit;
    end;
    Inc(Done, Sent);
  end;
  Result := True;
end;

procedure PtyMaster.ResizeClient(Size: TPoint);
var
  Win: TPtyWinSize;
begin
  Win := CreateWinsize(Size);
  fpIOCtl(D.MasterFd, ReqSetWinSize, @Win);
end;

procedure PtyMaster.Disconnect;
var
  Reaped: TPid;
begin
  fpClose(D.MasterFd);
  { A hang-up first, and a kill after a while when the client is still there. }
  fpKill(D.ClientPid, SIGHUP);
  Sleep(1000);
  if fpWaitPid(D.ClientPid, nil, WNOHANG) <> D.ClientPid then
  begin
    fpKill(D.ClientPid, SIGKILL);
    repeat
      Reaped := fpWaitPid(D.ClientPid, nil, 0);
    until (Reaped = D.ClientPid) or (fpGetErrno <> EintrCode);
  end;
end;

end.
