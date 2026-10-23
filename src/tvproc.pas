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

uses
  SysUtils, Process, ctypes, UnixType, BaseUnix;

{ The result of a command from its wait status. }
function StatusToResult(Status: cint): LongInt;
begin
  if (Status and $7F) <> 0 then
    Result := 128 + (Status and $7F)
  else
    Result := (Status shr 8) and $FF;
end;

function RunQuiet(const CmdLine: AnsiString): LongInt;
var
  Cmd: AnsiString;
  Argv: array[0..3] of PChar;
  Pid, Got: TPid;
  Status: cint;
begin
  Cmd := CmdLine;
  UniqueString(Cmd);
  Argv[0] := 'sh';
  Argv[1] := '-c';
  Argv[2] := PChar(Cmd);
  Argv[3] := nil;
  Pid := fpFork;
  if Pid < 0 then
    Exit(-1);
  if Pid = 0 then
  begin
    fpExecve('/bin/sh', @Argv[0], envp);
    fpExit(127);
  end;
  Status := 0;
  repeat
    Got := fpWaitPid(Pid, @Status, 0);
  until (Got <> -1) or (fpGetErrno <> ESysEINTR);
  if Got = -1 then
    Result := -1
  else
    Result := StatusToResult(Status);
end;

function RunShell(const CmdLine: AnsiString; Pause: Boolean; const PauseText: AnsiString): LongInt;
begin
  if Assigned(OnSuspend) then
    OnSuspend
  else if Assigned(UnixSuspend) then
    UnixSuspend;
  WriteLn;
  WriteLn('$ ', CmdLine);
  Flush(Output);
  Result := RunQuiet(CmdLine);
  if Pause and (UnixActive or Assigned(OnSuspend)) then
  begin
    WriteLn;
    Write(PauseText);
    Flush(Output);
    ReadLn;
  end;
  if Assigned(OnResume) then
    OnResume
  else if Assigned(UnixResume) then
    UnixResume;
end;

function RunCapture(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
const
  Chunk = 65536;
var
  P: TProcess;
  Buf: AnsiString;
  Len, N, I: LongInt;
begin
  Result := '';
  P := TProcess.Create(nil);
  try
    try
      P.Executable := Exe;
      for I := 0 to High(Args) do
        P.Parameters.Add(Args[I]);
      P.Options := [poUsePipes, poStderrToOutput];
      P.Execute;
      SetLength(Buf, Chunk);
      Len := 0;
      repeat
        if Length(Buf) - Len < Chunk div 4 then
          SetLength(Buf, Length(Buf) * 2);
        N := fpRead(P.Output.Handle, Buf[Len + 1], Length(Buf) - Len);
        if N > 0 then
          Inc(Len, N);
      until (N = 0) or ((N < 0) and (fpGetErrno <> ESysEINTR) and (fpGetErrno <> ESysEAGAIN));
      P.WaitOnExit;
      SetLength(Buf, Len);
      Result := Buf;
    except
      Result := '';
    end;
  finally
    P.Free;
  end;
end;

function RunFirstLine(const Exe: AnsiString; const Args: array of AnsiString): AnsiString;
var
  Text: AnsiString;
  I: LongInt;
begin
  Text := RunCapture(Exe, Args);
  I := 1;
  while (I <= Length(Text)) and (Text[I] <> #10) and (Text[I] <> #13) do
    Inc(I);
  Result := Copy(Text, 1, I - 1);
end;

procedure RestartSelf;
var
  Strs: array of AnsiString;
  Argv: array of PChar;
  I, Count: LongInt;
begin
  Count := ParamCount + 1;
  SetLength(Strs, Count);
  SetLength(Argv, Count + 1);
  for I := 0 to Count - 1 do
  begin
    Strs[I] := ParamStr(I);
    Argv[I] := PChar(Strs[I]);
  end;
  Argv[Count] := nil;
  fpExecve(Strs[0], @Argv[0], envp);
end;

end.
