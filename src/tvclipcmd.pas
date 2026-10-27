{ Reads and writes the system clipboard by running helper programs of the operating system (wl-copy, xsel, xclip,
  pbcopy, clip.exe under WSL) and shows desktop notifications through notify-send or osascript. Every routine returns
  False when there is no program or the program failed, so that the caller can go on to another way. The routines
  block the calling thread for at most about 1.5 seconds per call, keep a lazily built table of programs and change
  the SIGPIPE disposition of the process during a write: call them from one thread at a time. On systems that are not
  Unix-like every routine is a stub. }
unit TvClipCmd;

{$mode objfpc}
{$H+}
{$R-}
{$Q-}

interface

{ Puts Text on the clipboard byte for byte; False when no program is available or the program failed. }
function ClipCmdSet(const Text: AnsiString): Boolean;

{ Reads the clipboard into Text; Text is empty when the result is False. }
function ClipCmdGet(out Text: AnsiString): Boolean;

type
  TClipEnvProc = function(const Name: AnsiString): AnsiString;

var
  { When assigned, PATH, DISPLAY and WAYLAND_DISPLAY are read through it instead of the process environment. }
  OnClipEnv: TClipEnvProc = nil;

{ Shows a desktop notification; True when the notification program ended with status 0 within the time limit. }
function NotifyCmd(const Title, Text: AnsiString): Boolean;

{ The full path of the program that ClipCmdSet or ClipCmdGet would run now, or the empty text. }
function ClipCmdSetName: AnsiString;
function ClipCmdGetName: AnsiString;

implementation

{$IFDEF UNIX}

uses
  SysUtils, ctypes, UnixType, BaseUnix, TvPath;

type
  TArgList = array of AnsiString;

  { ekPlain: the text goes through unchanged. ekNulTerminated: one NUL byte follows the text. ekWslScript: the
    program is cmd.exe running the generated script of WslReadScript, and its output is UTF-16LE. }
  TEntryKind = (ekPlain, ekNulTerminated, ekWslScript);

  TClipEntry = record
    Prog: AnsiString;
    Args: TArgList;
    Needs: AnsiString;
    Kind: TEntryKind;
  end;

  TClipTable = record
    Count: Integer;
    Items: array[0..3] of TClipEntry;
  end;

const
  TimeLimitMs = 1500;
  PollSliceMs = 100;
  PollStepMs = 5;
  MaxArgs = 12;
  DefaultSearchPath = '/usr/local/bin:/bin:/usr/bin';
  WslClipExe = '/mnt/c/Windows/System32/clip.exe';
  WslCmdExe = '/mnt/c/Windows/System32/cmd.exe';

var
  WriteTable: TClipTable;
  ReadTable: TClipTable;
  TablesBuilt: Boolean = False;

{ ---- environment and program lookup ---- }

function EnvGet(const Name: AnsiString): AnsiString;
begin
  if Assigned(OnClipEnv) then
    Result := OnClipEnv(Name)
  else
    Result := GetEnvironmentVariable(Name);
end;

function IsExecutableFile(const Path: AnsiString): Boolean;
var
  Info: Stat;
begin
  Result := False;
  if fpStat(Path, Info) <> 0 then
    Exit;
  if not fpS_ISREG(Info.st_mode) then
    Exit;
  Result := fpAccess(Path, X_OK) = 0;
end;

{ The full path of a program, or the empty text. A name that is not rooted is searched in the directories of PATH. }
function FindProgram(const Name: AnsiString): AnsiString;
var
  SearchList, Dir, Candidate: AnsiString;
  ListSep: Char;
  Start, Stop, Len: Integer;
begin
  Result := '';
  if PathIsRooted(Name) then
  begin
    if IsExecutableFile(Name) then
      Result := Name;
    Exit;
  end;
  SearchList := EnvGet('PATH');
  if SearchList = '' then
    SearchList := DefaultSearchPath;
  ListSep := NativePathRules.ListSep;
  Len := Length(SearchList);
  Start := 1;
  while Start <= Len + 1 do
  begin
    Stop := Start;
    while (Stop <= Len) and (SearchList[Stop] <> ListSep) do
      Inc(Stop);
    Dir := Copy(SearchList, Start, Stop - Start);
    if Dir = '' then
      Dir := '.';
    Candidate := PathJoin(Dir, Name);
    if IsExecutableFile(Candidate) then
    begin
      Result := Candidate;
      Exit;
    end;
    Start := Stop + 1;
  end;
end;

{ ---- the tables of programs ---- }

procedure AddEntry(var Table: TClipTable; const Prog: AnsiString; const Args: array of AnsiString;
  const Needs: AnsiString; Kind: TEntryKind);
var
  Slot, I: Integer;
begin
  Slot := Table.Count;
  if Slot > High(Table.Items) then
    Exit;
  Table.Items[Slot].Prog := Prog;
  SetLength(Table.Items[Slot].Args, Length(Args));
  for I := 0 to High(Args) do
    Table.Items[Slot].Args[I] := Args[I];
  Table.Items[Slot].Needs := Needs;
  Table.Items[Slot].Kind := Kind;
  Inc(Table.Count);
end;

procedure EnsureTables;
begin
  if TablesBuilt then
    Exit;
  TablesBuilt := True;
  WriteTable.Count := 0;
  ReadTable.Count := 0;
{$IFDEF DARWIN}
  AddEntry(WriteTable, 'pbcopy', [], '', ekPlain);
  AddEntry(ReadTable, 'pbpaste', [], '', ekPlain);
{$ELSE}
  AddEntry(WriteTable, WslClipExe, [], '', ekNulTerminated);
  AddEntry(WriteTable, 'wl-copy', [], 'WAYLAND_DISPLAY', ekPlain);
  AddEntry(WriteTable, 'xsel', ['--input', '--clipboard'], 'DISPLAY', ekPlain);
  AddEntry(WriteTable, 'xclip', ['-in', '-selection', 'clipboard'], 'DISPLAY', ekPlain);
  AddEntry(ReadTable, 'wl-paste', ['--no-newline'], 'WAYLAND_DISPLAY', ekPlain);
  AddEntry(ReadTable, 'xsel', ['--output', '--clipboard'], 'DISPLAY', ekPlain);
  AddEntry(ReadTable, 'xclip', ['-out', '-selection', 'clipboard'], 'DISPLAY', ekPlain);
  AddEntry(ReadTable, WslCmdExe, [], '', ekWslScript);
{$ENDIF}
end;

{ Finds the first available entry of a table: its required variable is set and its program exists. }
function FindEntry(const Table: TClipTable; out Index: Integer; out Path: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := False;
  Index := -1;
  Path := '';
  EnsureTables;
  for I := 0 to Table.Count - 1 do
  begin
    if (Table.Items[I].Needs <> '') and (EnvGet(Table.Items[I].Needs) = '') then
      Continue;
    Path := FindProgram(Table.Items[I].Prog);
    if Path = '' then
      Continue;
    Index := I;
    Result := True;
    Exit;
  end;
end;

{ ---- the script of the WSL reader ---- }

{ The command line that cmd.exe runs to read the Windows clipboard. cmd.exe called from WSL loses double quotes, so
  every quote is the value of the environment variable q, which RunEntry passes along. The one-line Visual Basic
  script goes into the first directory of the list that can be written; the command then exits at once with the
  status of the script host, after deleting the script file. }
function WslReadScript: AnsiString;
const
  Quote = '%q%';
var
  FileName, Target, Dirs, VbLine: AnsiString;
begin
  FileName := IntToHex(Int64(fpGetPid), 1) + '%RANDOM%.vbs';
  Target := Quote + '%~I\' + FileName + Quote;
  Dirs := Quote + '%TMP%' + Quote + ' ' + Quote + '%TEMP%' + Quote + ' ' + Quote + '%USERPROFILE%' + Quote + ' ' +
    Quote + '.' + Quote + ' ' + Quote + '..' + Quote;
  VbLine := 'WScript.StdOut.Write Create' + 'Object(' + Quote + 'htmlfile' + Quote + '^).' +
    'ParentWindow.ClipboardData.GetData(' + Quote + 'Text' + Quote + '^)';
  Result := '(for %I in (' + Dirs + ') do echo ' + VbLine + '>' + Target + ' 2>nul && (cscript //NoLogo //B //U ' +
    Target + ' && (del ' + Target + ' & exit 0) || (del ' + Target + ' & exit 1))) & exit 1';
end;

{ The current environment with WSLENV=q and q=" added; an older WSLENV or q is replaced. }
function WslEnvironment: TArgList;
var
  I, Count: Integer;
  Entry: AnsiString;
begin
  SetLength(Result, 0);
  Count := 0;
  for I := 1 to GetEnvironmentVariableCount do
  begin
    Entry := GetEnvironmentString(I);
    if (Copy(Entry, 1, 7) = 'WSLENV=') or (Copy(Entry, 1, 2) = 'q=') then
      Continue;
    SetLength(Result, Count + 1);
    Result[Count] := Entry;
    Inc(Count);
  end;
  SetLength(Result, Count + 2);
  Result[Count] := 'WSLENV=q';
  Result[Count + 1] := 'q="';
end;

{ ---- UTF-16LE ---- }

{ An odd trailing byte is dropped; surrogate pairs become four-byte sequences. }
function Utf16LeToUtf8(const Raw: AnsiString): AnsiString;
var
  Units: UnicodeString;
  Encoded: UTF8String;
  I, UnitCount: Integer;
  LowByte, HighByte: Integer;
begin
  UnitCount := Length(Raw) div 2;
  SetLength(Units, UnitCount);
  for I := 1 to UnitCount do
  begin
    LowByte := Ord(Raw[2 * I - 1]);
    HighByte := Ord(Raw[2 * I]);
    Units[I] := WideChar(LowByte or (HighByte shl 8));
  end;
  Encoded := UTF8Encode(Units);
  SetLength(Result, Length(Encoded));
  if Length(Encoded) > 0 then
    Move(Encoded[1], Result[1], Length(Encoded));
end;

{ ---- running a program ---- }

function RemainingMs(Deadline: QWord): Int64;
begin
  Result := Int64(Deadline) - Int64(GetTickCount64);
end;

{ Waits for a descriptor for at most one slice of the time left. False when the deadline has passed. }
function WaitReady(Fd: Integer; Events: Integer; Deadline: QWord): Boolean;
var
  Query: TPollFd;
  Left: Int64;
begin
  Result := False;
  Left := RemainingMs(Deadline);
  if Left <= 0 then
    Exit;
  if Left > PollSliceMs then
    Left := PollSliceMs;
  Query.fd := Fd;
  Query.events := Events;
  Query.revents := 0;
  fpPoll(@Query, 1, Integer(Left));
  Result := True;
end;

function SetNonBlocking(Fd: Integer): Boolean;
var
  Flags: Integer;
begin
  Result := False;
  Flags := fpFcntl(Fd, F_GETFL);
  if Flags < 0 then
    Exit;
  Result := fpFcntl(Fd, F_SETFL, Flags or O_NONBLOCK) >= 0;
end;

procedure IgnoreSigPipe(out OldAction: SigActionRec);
var
  IgnoreAction: SigActionRec;
begin
  FillChar(OldAction, SizeOf(OldAction), 0);
  FillChar(IgnoreAction, SizeOf(IgnoreAction), 0);
  IgnoreAction.sa_handler := SigActionHandler(SIG_IGN);
  fpSigAction(SIGPIPE, @IgnoreAction, @OldAction);
end;

procedure RestoreSigPipe(var OldAction: SigActionRec);
begin
  fpSigAction(SIGPIPE, @OldAction, nil);
end;

{ Writes all of Data to a non-blocking descriptor. False on an error or when the deadline passes (TimedOut). }
function WritePipe(Fd: Integer; const Data: AnsiString; Deadline: QWord; out TimedOut: Boolean): Boolean;
var
  Total, Sent: SizeInt;
  Got: PtrInt;
  Err: Integer;
begin
  Result := False;
  TimedOut := False;
  Total := Length(Data);
  Sent := 0;
  while Sent < Total do
  begin
    Got := fpWrite(Fd, PChar(@Data[Sent + 1]), Total - Sent);
    if Got > 0 then
    begin
      Inc(Sent, Got);
      Continue;
    end;
    if Got < 0 then
    begin
      Err := fpGetErrno;
      if Err = ESysEINTR then
        Continue;
      if Err <> ESysEAGAIN then
        Exit;
    end;
    if not WaitReady(Fd, POLLOUT, Deadline) then
    begin
      TimedOut := True;
      Exit;
    end;
  end;
  Result := True;
end;

{ Reads a non-blocking descriptor until end of file, an error or the deadline. Whatever was read is in Output. }
procedure ReadPipe(Fd: Integer; var Output: AnsiString; Deadline: QWord; out TimedOut, ReachedEof: Boolean);
var
  Buffer: array[0..32767] of Char;
  Got: PtrInt;
  OldLength: SizeInt;
  Err: Integer;
begin
  TimedOut := False;
  ReachedEof := False;
  while True do
  begin
    Got := fpRead(Fd, PChar(@Buffer[0]), SizeOf(Buffer));
    if Got > 0 then
    begin
      OldLength := Length(Output);
      SetLength(Output, OldLength + Got);
      Move(Buffer[0], Output[OldLength + 1], Got);
      Continue;
    end;
    if Got = 0 then
    begin
      ReachedEof := True;
      Exit;
    end;
    Err := fpGetErrno;
    if Err = ESysEINTR then
      Continue;
    if Err <> ESysEAGAIN then
      Exit;
    if not WaitReady(Fd, POLLIN, Deadline) then
    begin
      TimedOut := True;
      Exit;
    end;
  end;
end;

procedure KillAndReap(Pid: TPid);
var
  Status: LongInt;
  Got: TPid;
begin
  fpKill(Pid, SIGKILL);
  repeat
    Got := fpWaitPid(Pid, @Status, 0);
  until (Got >= 0) or (fpGetErrno <> ESysEINTR);
end;

{ Waits for the program to end, looking about every PollStepMs. When the deadline passes first, the program is
  killed and reaped and TimedOut is set. True when the program was reaped and Status holds its status. }
function WaitChild(Pid: TPid; Deadline: QWord; out Status: LongInt; out TimedOut: Boolean): Boolean;
var
  Got: TPid;
begin
  Result := False;
  TimedOut := False;
  Status := 0;
  while True do
  begin
    Got := fpWaitPid(Pid, @Status, WNOHANG);
    if Got = Pid then
    begin
      Result := True;
      Exit;
    end;
    if Got < 0 then
    begin
      if fpGetErrno <> ESysEINTR then
        Exit;
      Continue;
    end;
    if RemainingMs(Deadline) <= 0 then
    begin
      TimedOut := True;
      KillAndReap(Pid);
      Exit;
    end;
    Sleep(PollStepMs);
  end;
end;

{ Starts the program with fork and exec. In the child, standard error and the unused one of standard input and
  output are /dev/null, and the other one is the pipe end that belongs to the child. A negative result means that
  the fork failed. Every pointer is prepared before the fork. }
function StartChild(const Path: AnsiString; const Args: array of AnsiString; Writing: Boolean;
  const PipeFds: TFilDes; const EnvList: TArgList): TPid;
var
  ArgPtrs: array[0..MaxArgs + 1] of PChar;
  EnvPtrs: array of PChar;
  NullDevice: PChar;
  ArgCount, I, NullFd: Integer;
  UseEnv: Boolean;
begin
  ArgPtrs[0] := PChar(Path);
  ArgCount := 1;
  for I := 0 to High(Args) do
  begin
    if Args[I] = '' then
      Continue;
    if ArgCount > MaxArgs then
      Break;
    ArgPtrs[ArgCount] := PChar(Args[I]);
    Inc(ArgCount);
  end;
  ArgPtrs[ArgCount] := nil;
  UseEnv := Length(EnvList) > 0;
  if UseEnv then
  begin
    SetLength(EnvPtrs, Length(EnvList) + 1);
    for I := 0 to High(EnvList) do
      EnvPtrs[I] := PChar(EnvList[I]);
    EnvPtrs[Length(EnvList)] := nil;
  end;
  NullDevice := '/dev/null';

  Result := fpFork;
  if Result <> 0 then
    Exit;

  NullFd := fpOpen(NullDevice, O_RDWR);
  if Writing then
  begin
    fpDup2(PipeFds[0], 0);
    fpDup2(NullFd, 1);
  end
  else
  begin
    fpDup2(NullFd, 0);
    fpDup2(PipeFds[1], 1);
  end;
  fpDup2(NullFd, 2);
  fpClose(PipeFds[0]);
  fpClose(PipeFds[1]);
  if NullFd > 2 then
    fpClose(NullFd);
  if UseEnv then
    fpExecve(PChar(Path), @ArgPtrs[0], @EnvPtrs[0])
  else
    fpExecv(PChar(Path), @ArgPtrs[0]);
  fpExit(127);
end;

{ Runs a program as the specification describes in 3.2. Writing: Input goes to its standard input. Otherwise its
  standard output is collected into Output. EnvList, when not empty, is the whole environment of the child. }
function RunProgram(const Path: AnsiString; const Args: array of AnsiString; Writing: Boolean;
  const Input: AnsiString; out Output: AnsiString; const EnvList: TArgList): Boolean;
var
  PipeFds: TFilDes;
  Pid: TPid;
  Deadline: QWord;
  OldAction: SigActionRec;
  Status: LongInt;
  TransferOk, TimedOut, ReachedEof, Reaped, ExitedClean: Boolean;
begin
  Result := False;
  Output := '';
  TimedOut := False;
  ReachedEof := False;
  if fpPipe(PipeFds) <> 0 then
    Exit;
  Pid := StartChild(Path, Args, Writing, PipeFds, EnvList);
  if Pid < 0 then
  begin
    fpClose(PipeFds[0]);
    fpClose(PipeFds[1]);
    Exit;
  end;

  Deadline := GetTickCount64 + TimeLimitMs;
  if Writing then
  begin
    fpClose(PipeFds[0]);
    TransferOk := SetNonBlocking(PipeFds[1]);
    if TransferOk then
    begin
      IgnoreSigPipe(OldAction);
      TransferOk := WritePipe(PipeFds[1], Input, Deadline, TimedOut);
      RestoreSigPipe(OldAction);
    end;
    fpClose(PipeFds[1]);
  end
  else
  begin
    fpClose(PipeFds[1]);
    TransferOk := SetNonBlocking(PipeFds[0]);
    if TransferOk then
      ReadPipe(PipeFds[0], Output, Deadline, TimedOut, ReachedEof);
    fpClose(PipeFds[0]);
  end;

  if TimedOut then
  begin
    KillAndReap(Pid);
    Output := '';
    Exit;
  end;

  Reaped := WaitChild(Pid, Deadline, Status, TimedOut);
  if TimedOut then
  begin
    Output := '';
    Exit;
  end;
  ExitedClean := Reaped and wifexited(Status) and (wexitstatus(Status) = 0);

  if Writing then
    Result := TransferOk and ExitedClean
  else
    Result := (ExitedClean and ReachedEof) or (Length(Output) > 0);
  if not Result then
    Output := '';
end;

function RunEntry(const Entry: TClipEntry; const Path, Input: AnsiString; Writing: Boolean;
  out Output: AnsiString): Boolean;
begin
  if Entry.Kind = ekWslScript then
    Result := RunProgram(Path, ['/D', '/Q', '/C', WslReadScript], Writing, Input, Output, WslEnvironment)
  else
    Result := RunProgram(Path, Entry.Args, Writing, Input, Output, nil);
end;

{ ---- the routines ---- }

function ClipCmdSet(const Text: AnsiString): Boolean;
var
  Index: Integer;
  Path, Data, Ignored: AnsiString;
begin
  if not FindEntry(WriteTable, Index, Path) then
    Exit(False);
  Data := Text;
  if WriteTable.Items[Index].Kind = ekNulTerminated then
    Data := Data + #0;
  Result := RunEntry(WriteTable.Items[Index], Path, Data, True, Ignored);
end;

function ClipCmdGet(out Text: AnsiString): Boolean;
var
  Index: Integer;
  Path, Raw: AnsiString;
begin
  Text := '';
  if not FindEntry(ReadTable, Index, Path) then
    Exit(False);
  Result := RunEntry(ReadTable.Items[Index], Path, '', False, Raw);
  if not Result then
    Exit;
  if ReadTable.Items[Index].Kind = ekWslScript then
    Text := Utf16LeToUtf8(Raw)
  else
    Text := Raw;
end;

function ClipCmdSetName: AnsiString;
var
  Index: Integer;
  Path: AnsiString;
begin
  if FindEntry(WriteTable, Index, Path) then
    Result := Path
  else
    Result := '';
end;

function ClipCmdGetName: AnsiString;
var
  Index: Integer;
  Path: AnsiString;
begin
  if FindEntry(ReadTable, Index, Path) then
    Result := Path
  else
    Result := '';
end;

{ Makes a text safe inside a double-quoted AppleScript string: a backslash and a double quote get a backslash in
  front, and line breaks become spaces. }
function ScriptStr(const S: AnsiString): AnsiString;
var
  Position: Integer;
  Letter: Char;
  Piece: AnsiString;
begin
  Result := '';
  for Position := 1 to Length(S) do
  begin
    Letter := S[Position];
    if (Letter = #10) or (Letter = #13) then
      Piece := ' '
    else if (Letter = Chr(92)) or (Letter = Chr(34)) then
      Piece := Chr(92) + Letter
    else
      Piece := Letter;
    Result := Result + Piece;
  end;
end;

function NotifyCmd(const Title, Text: AnsiString): Boolean;
var
  Head, Body, Path, Ignored: AnsiString;
begin
  Head := Title;
  if Head = '' then
    Head := ' ';
  Body := Text;
  if Body = '' then
    Body := ' ';
{$IFDEF DARWIN}
  Path := FindProgram('osascript');
  if Path = '' then
    Exit(False);
  Result := RunProgram(Path, ['-e', 'display notification "' + ScriptStr(Body) + '" with title "' +
    ScriptStr(Head) + '"'], True, '', Ignored, nil);
{$ELSE}
  if (EnvGet('DISPLAY') = '') and (EnvGet('WAYLAND_DISPLAY') = '') then
    Exit(False);
  Path := FindProgram('notify-send');
  if Path = '' then
    Exit(False);
  Result := RunProgram(Path, ['--', Head, Body], True, '', Ignored, nil);
{$ENDIF}
end;

{$ELSE}

function ClipCmdSet(const Text: AnsiString): Boolean;
begin
  Result := False;
end;

function ClipCmdGet(out Text: AnsiString): Boolean;
begin
  Text := '';
  Result := False;
end;

function NotifyCmd(const Title, Text: AnsiString): Boolean;
begin
  Result := False;
end;

function ClipCmdSetName: AnsiString;
begin
  Result := '';
end;

function ClipCmdGetName: AnsiString;
begin
  Result := '';
end;

{$ENDIF}

end.
