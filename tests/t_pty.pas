{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/pty.h, source/tvterm-core/pty.cc (the branch for systems other than Windows)
  See COPYRIGHT.tvterm. }
program t_pty;

{$mode objfpc}

uses
  ctypes, BaseUnix, SysUtils, TvGeom, TvPty;

{$I testlib.inc}

const
  AgainCode = 11;
  RlimitNprocCode = 6;
  WaitLimitMs = 8000;

var
  LastReason: AnsiString;
  ErrorCalls: Integer;

procedure NoteError(Reason: PAnsiChar);
begin
  Inc(ErrorCalls);
  LastReason := AnsiString(Reason);
end;

function Pt(AX, AY: Integer): TPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function OneVar(AName, AValue: PAnsiChar): EnvironmentVar;
begin
  Result.Name := AName;
  Result.Value := AValue;
end;

function CountOf(const Needle, Hay: AnsiString): Integer;
var
  From, Found: Integer;
begin
  Result := 0;
  From := 1;
  while From <= Length(Hay) do
  begin
    Found := Pos(Needle, Copy(Hay, From, Length(Hay)));
    if Found = 0 then
      Break;
    Inc(Result);
    From := From + Found + Length(Needle) - 1;
  end;
end;

procedure SetNonBlocking(Fd: cint);
begin
  fpFcntl(Fd, F_SETFL, O_NONBLOCK);
end;

procedure Send(Master: PtyMaster; const Text: AnsiString);
var
  Bytes: array of Char;
begin
  if Length(Text) = 0 then
    Exit;
  SetLength(Bytes, Length(Text));
  Move(Text[1], Bytes[0], Length(Text));
  Check(Master.WriteToClient(Bytes), 'WriteToClient ' + Copy(Text, 1, 12));
end;

{ One attempt to read; Ended is True when the read fails for a reason other than an empty descriptor. }
procedure ReadMore(Master: PtyMaster; var Acc: AnsiString; out Ended: Boolean);
var
  Buf: array[0..255] of Char;
  Got: SizeUInt;
  Index: Integer;
begin
  Ended := False;
  if Master.ReadFromClient(Buf, Got) then
  begin
    if Got = 0 then
      Sleep(10)
    else
      for Index := 0 to Integer(Got) - 1 do
        Acc := Acc + Buf[Index];
  end
  else if fpGetErrno = AgainCode then
    Sleep(10)
  else
    Ended := True;
end;

function WaitFor(Master: PtyMaster; var Acc: AnsiString; const Needle: AnsiString; Times: Integer): Boolean;
var
  Limit: QWord;
  Ended: Boolean;
begin
  Limit := GetTickCount64 + WaitLimitMs;
  while (CountOf(Needle, Acc) < Times) and (GetTickCount64 < Limit) do
  begin
    ReadMore(Master, Acc, Ended);
    if Ended then
      Break;
  end;
  Result := CountOf(Needle, Acc) >= Times;
end;

function WaitForEnd(Master: PtyMaster; var Acc: AnsiString): Boolean;
var
  Limit: QWord;
begin
  Limit := GetTickCount64 + WaitLimitMs;
  Result := False;
  while (not Result) and (GetTickCount64 < Limit) do
    ReadMore(Master, Acc, Result);
end;

var
  Env: array[0..1] of EnvironmentVar;
  Desc, Failed: PtyDescriptor;
  Master: PtyMaster;
  Acc: AnsiString;
  Ok: Boolean;
  OldLimit, NoProcs: TRLimit;
  Probe: array[0..0] of Char;
  Count: SizeUInt;
  Status: TPid;

begin
  { createPty with a shell that is told to echo something }
  Env[0] := OneVar('SHELL', '/bin/sh');
  Env[1] := OneVar('TVPTY_MARK', 'seen');
  ErrorCalls := 0;
  Ok := CreatePty(Desc, Pt(80, 24), Env, @NoteError);
  Check(Ok, 'CreatePty succeeds');
  Check(ErrorCalls = 0, 'onError is not called on success');
  Check(Desc.ClientPid > 0, 'client process number');
  Check(Desc.MasterFd >= 0, 'master descriptor');
  Master := PtyMaster.Create(Desc);
  SetNonBlocking(Desc.MasterFd);
  Acc := '';
  Send(Master, 'echo r$((6*7))' + #10);
  Check(WaitFor(Master, Acc, 'r42', 1), 'output of the echo command');
  Acc := '';
  Send(Master, 'echo m-$TVPTY_MARK' + #10);
  Check(WaitFor(Master, Acc, 'm-seen', 1), 'custom environment variable reaches the client');

  { the size of the terminal at the start, and after resizeClient }
  Acc := '';
  Send(Master, 'stty size' + #10);
  Check(WaitFor(Master, Acc, '24 80', 1), 'initial size 24 rows by 80 columns');
  Master.ResizeClient(Pt(100, 30));
  Acc := '';
  Send(Master, 'stty size' + #10);
  Check(WaitFor(Master, Acc, '30 100', 1), 'size after ResizeClient');

  { the client ends by itself }
  Acc := '';
  Send(Master, 'exit' + #10);
  Check(WaitForEnd(Master, Acc), 'read fails after the client has ended');
  Master.Disconnect;
  Status := fpWaitPid(Desc.ClientPid, nil, WNOHANG);
  Check(Status = -1, 'client was reaped by Disconnect');
  Master.Free;

  { input is echoed by the terminal and passed to the client (cat) }
  Env[0] := OneVar('SHELL', '/bin/cat');
  Ok := CreatePty(Desc, Pt(80, 24), Env, @NoteError);
  Check(Ok, 'CreatePty with cat');
  Master := PtyMaster.Create(Desc);
  SetNonBlocking(Desc.MasterFd);
  Acc := '';
  Send(Master, 'pong' + #13);
  Check(WaitFor(Master, Acc, 'pong', 2), 'line is echoed and copied back by cat');
  Check(Pos('pong' + #13#10, Acc) > 0, 'output uses carriage return and line feed');
  { a span of one byte is too short for a read: nothing is stored }
  Count := 99;
  Check(Master.ReadFromClient(Probe, Count), 'ReadFromClient on a one byte span');
  Check(Count = 0, 'no byte is read into a one byte span');
  Send(Master, #4);
  Check(WaitForEnd(Master, Acc), 'cat ends at the end-of-file character');
  Master.Disconnect;
  Check(fpWaitPid(Desc.ClientPid, nil, WNOHANG) = -1, 'cat was reaped');
  Master.Free;

  { a program that does not exist: the client reports it on the terminal }
  Env[0] := OneVar('SHELL', '/nonexistent/tvpty-program');
  ErrorCalls := 0;
  Ok := CreatePty(Desc, Pt(80, 24), Env, @NoteError);
  Check(Ok, 'CreatePty returns for a missing program');
  Check(ErrorCalls = 0, 'the failed exec is not an onError case');
  Master := PtyMaster.Create(Desc);
  SetNonBlocking(Desc.MasterFd);
  Acc := '';
  Check(WaitFor(Master, Acc, 'Failed to execute', 1), 'message of the failed program');
  Check(WaitFor(Master, Acc, '/nonexistent/tvpty-program', 1), 'message names the program');
  Check(WaitFor(Master, Acc, 'No such file or directory', 1), 'message gives the reason');
  Check(WaitForEnd(Master, Acc), 'the client has ended');
  Master.Disconnect;
  Master.Free;

  { onError: forkpty fails when the process limit is reached }
  if fpGetUid = 0 then
    WriteLn('onError check skipped: the process limit does not bind the super user')
  else if fpGetRLimit(RlimitNprocCode, @OldLimit) <> 0 then
    WriteLn('onError check skipped: the limit cannot be read')
  else
  begin
    NoProcs := OldLimit;
    NoProcs.rlim_cur := 0;
    ErrorCalls := 0;
    LastReason := '';
    if fpSetRLimit(RlimitNprocCode, @NoProcs) = 0 then
    begin
      Ok := CreatePty(Failed, Pt(80, 24), Env, @NoteError);
      fpSetRLimit(RlimitNprocCode, @OldLimit);
      if Ok then
      begin
        Master := PtyMaster.Create(Failed);
        Master.Disconnect;
        Master.Free;
        WriteLn('onError check skipped: the fork was not refused');
      end
      else
      begin
        Check(ErrorCalls = 1, 'onError is called once when forkpty fails');
        Check(Pos('forkpty failed: ', LastReason) = 1, 'reason starts with the failed call');
        Check(Length(LastReason) > Length('forkpty failed: '), 'reason has the system message');
      end;
    end
    else
      WriteLn('onError check skipped: the limit cannot be set');
  end;

  Done;
end.
