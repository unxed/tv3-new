{ Test program of the unit TvProc. }
program t_proc;

{$mode objfpc}

uses
  SysUtils, BaseUnix, TvProc;

{$I testlib.inc}

const
  Lf = #10;
  GuardSeconds = 60;

var
  Suspends: Integer = 0;
  Resumes: Integer = 0;

{ Each test runs under a time-out: the alarm signal ends the program when a call does not return. }
procedure Guard;
begin
  fpAlarm(GuardSeconds);
end;

procedure Unguard;
begin
  fpAlarm(0);
end;

procedure CountSuspend;
begin
  Inc(Suspends);
end;

procedure CountResume;
begin
  Inc(Resumes);
end;

procedure ResetHooks;
begin
  Suspends := 0;
  Resumes := 0;
  OnSuspend := nil;
  OnResume := nil;
  UnixSuspend := nil;
  UnixResume := nil;
  UnixActive := False;
end;

procedure CheckStr(const Got, Want, Name: AnsiString);
begin
  Check(Got = Want, Name + ' (got length ' + IntToStr(Length(Got)) + ')');
end;

function AllBytes(const S: AnsiString; B: Char): Boolean;
begin
  Result := S = StringOfChar(B, Length(S));
end;

procedure TestQuiet;
begin
  Guard;
  ResetHooks;
  Check(RunQuiet('exit 0') = 0, 'quiet exit 0');
  Check(RunQuiet('exit 1') = 1, 'quiet exit 1');
  Check(RunQuiet('exit 7') = 7, 'quiet exit 7');
  Check(RunQuiet('exit 255') = 255, 'quiet exit 255');
  Check(RunQuiet('kill -9 $$') = 137, 'quiet killed by signal 9');
  Check(RunQuiet('kill -15 $$') = 143, 'quiet killed by signal 15');
  Check(RunQuiet('/no/such/command') = 127, 'quiet command not found');
  Check(RunQuiet('echo x | grep -q x') = 0, 'quiet pipe');
  Check(RunQuiet('false') = 1, 'quiet false');
  Check(RunQuiet('test "$$" -gt 0 && exit 4') = 4, 'quiet variable and list');
  Check(RunQuiet('') = 0, 'quiet empty command line');
  OnSuspend := @CountSuspend;
  OnResume := @CountResume;
  Check(RunQuiet('exit 2') = 2, 'quiet with hooks');
  Check((Suspends = 0) and (Resumes = 0), 'quiet does not call the hooks');
  ResetHooks;
  Unguard;
end;

procedure TestCapture;
var
  S: AnsiString;
begin
  Guard;
  CheckStr(RunCapture('/bin/echo', ['hello', 'world']), 'hello world' + Lf, 'capture echo');
  CheckStr(RunCapture('/bin/echo', ['a  b']), 'a  b' + Lf, 'capture argument with spaces');
  CheckStr(RunCapture('/bin/echo', ['$HOME', '*']), '$HOME *' + Lf, 'capture no expansion');
  CheckStr(RunCapture('/bin/sh', ['-c', 'echo out; echo err 1>&2']), 'out' + Lf + 'err' + Lf, 'capture both streams');
  CheckStr(RunCapture('/bin/sh', ['-c', 'echo 1; echo 2 1>&2; echo 3; echo 4 1>&2']),
    '1' + Lf + '2' + Lf + '3' + Lf + '4' + Lf, 'capture order of the streams');
  CheckStr(RunCapture('/no/such/program', []), '', 'capture missing program');
  CheckStr(RunCapture('/bin/sh', ['-c', ':']), '', 'capture no output');
  CheckStr(RunCapture('/bin/true', []), '', 'capture empty arguments');
  CheckStr(RunCapture('/bin/false', []), '', 'capture exit code is not reported');
  CheckStr(RunCapture('/bin/sh', ['-c', 'printf ''a\n\n''']), 'a' + Lf + Lf, 'capture not trimmed');
  CheckStr(RunCapture('/bin/sh', ['-c', 'printf ''a\r\nb''']), 'a'#13#10'b', 'capture keeps carriage return');
  S := RunCapture('/bin/sh', ['-c', 'printf ''\000\377x''']);
  CheckStr(S, #0#255'x', 'capture binary bytes');
  S := RunCapture('/bin/sh', ['-c', 'head -c 300000 /dev/zero']);
  Check(Length(S) = 300000, 'capture large output length ' + IntToStr(Length(S)));
  Check(AllBytes(S, #0), 'capture large output bytes');
  S := RunCapture('/bin/sh', ['-c', 'head -c 200000 /dev/zero 1>&2']);
  Check(Length(S) = 200000, 'capture large error output length ' + IntToStr(Length(S)));
  Check(AllBytes(S, #0), 'capture large error output bytes');
  Unguard;
end;

procedure TestFirstLine;
begin
  Guard;
  CheckStr(RunFirstLine('/bin/sh', ['-c', 'echo one; echo two']), 'one', 'first line');
  CheckStr(RunFirstLine('/bin/sh', ['-c', 'printf ''a\r\nb''']), 'a', 'first line before carriage return');
  CheckStr(RunFirstLine('/bin/sh', ['-c', 'printf ''abc''']), 'abc', 'first line without line break');
  CheckStr(RunFirstLine('/bin/sh', ['-c', ':']), '', 'first line of no output');
  CheckStr(RunFirstLine('/no/such/program', []), '', 'first line of missing program');
  CheckStr(RunFirstLine('/bin/sh', ['-c', 'printf ''\nx''']), '', 'first line after leading line feed');
  CheckStr(RunFirstLine('/bin/echo', ['a b']), 'a b', 'first line keeps spaces');
  Unguard;
end;

{ Replaces the standard input by a pipe that holds Text. }
procedure FeedInput(const Text: AnsiString);
var
  Fds: TFilDes;
begin
  if fpPipe(Fds) <> 0 then
    Exit;
  fpWrite(Fds[1], Text[1], Length(Text));
  fpClose(Fds[1]);
  fpDup2(Fds[0], 0);
  fpClose(Fds[0]);
end;

procedure TestShell;
var
  Line: AnsiString;
begin
  Guard;
  ResetHooks;
  FeedInput('first' + Lf + 'second' + Lf + 'third' + Lf);
  OnSuspend := @CountSuspend;
  OnResume := @CountResume;
  Check(RunShell('exit 3') = 3, 'shell exit 3');
  Check((Suspends = 1) and (Resumes = 1), 'shell calls each hook once');
  Check(RunShell('exit 0', False) = 0, 'shell exit 0');
  Check((Suspends = 2) and (Resumes = 2), 'shell calls each hook once again');
  Check(RunShell('/no/such/command') = 127, 'shell command not found');
  Check((Suspends = 3) and (Resumes = 3), 'shell hooks after a failing command');
  Check(RunShell('kill -9 $$') = 137, 'shell killed by signal');
  Check((Suspends = 4) and (Resumes = 4), 'shell hooks after a signal');
  { no pause was made until now: the first line of the input is still there }
  Check(RunShell('exit 5', True) = 5, 'shell with pause');
  Check((Suspends = 5) and (Resumes = 5), 'shell with pause calls the hooks');
  ReadLn(Line);
  CheckStr(Line, 'second', 'pause consumed one line');
  { neither hook nor active backend: no pause }
  ResetHooks;
  Check(RunShell('exit 6', True) = 6, 'shell with pause and no terminal');
  ReadLn(Line);
  CheckStr(Line, 'third', 'no pause without terminal');
  { the terminal backend routines are used when the hooks are not assigned }
  UnixSuspend := @CountSuspend;
  UnixResume := @CountResume;
  Check(RunShell('exit 9') = 9, 'shell backend exit');
  Check((Suspends = 1) and (Resumes = 1), 'shell calls the backend routines');
  ResetHooks;
  Unguard;
end;

{ The helper copy of the program: the first instance replaces itself by a second one. }
procedure RunHelper(const GuardFile: AnsiString);
var
  H: THandle;
begin
  Guard;
  if FileExists(GuardFile) then
  begin
    DeleteFile(GuardFile);
    WriteLn('second');
    Flush(Output);
    Halt(0);
  end;
  H := FileCreate(GuardFile);
  FileClose(H);
  WriteLn('first');
  Flush(Output);
  RestartSelf;
  WriteLn('not restarted');
  Flush(Output);
  DeleteFile(GuardFile);
  Halt(1);
end;

procedure TestRestart;
var
  GuardFile: AnsiString;
begin
  Guard;
  GuardFile := IncludeTrailingPathDelimiter(GetTempDir) + 't_proc_restart_' + IntToStr(fpGetPid);
  DeleteFile(GuardFile);
  CheckStr(RunCapture(ParamStr(0), ['--restart', GuardFile]), 'first' + Lf + 'second' + Lf, 'restart');
  Check(not FileExists(GuardFile), 'restart removed the guard file');
  DeleteFile(GuardFile);
  Unguard;
end;

begin
  if (ParamCount = 2) and (ParamStr(1) = '--restart') then
    RunHelper(ParamStr(2));
  TestQuiet;
  TestCapture;
  TestFirstLine;
  TestRestart;
  TestShell;
  Done;
end.
