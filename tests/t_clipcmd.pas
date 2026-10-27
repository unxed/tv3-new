{ Test program of the unit TvClipCmd. On Unix it runs the unit against shell-script fakes of the clipboard programs
  that live in a private directory; elsewhere it checks the stubs. }
program t_clipcmd;

{$mode objfpc}
{$H+}

uses
  SysUtils, Classes,
{$IFDEF UNIX}
  BaseUnix,
{$ENDIF}
  TvClipCmd;

{$I testlib.inc}

{$IFNDEF UNIX}

var
  Text: AnsiString;

begin
  Check(not ClipCmdSet('x'), 'stub: ClipCmdSet is False');
  Text := 'junk';
  Check(not ClipCmdGet(Text), 'stub: ClipCmdGet is False');
  Check(Text = '', 'stub: ClipCmdGet leaves the empty text');
  Check(not NotifyCmd('a', 'b'), 'stub: NotifyCmd is False');
  Check(ClipCmdSetName = '', 'stub: ClipCmdSetName is empty');
  Check(ClipCmdGetName = '', 'stub: ClipCmdGetName is empty');
  Done;
end.

{$ELSE}

const
  WslClipExe = '/mnt/c/Windows/System32/clip.exe';
  WslCmdExe = '/mnt/c/Windows/System32/cmd.exe';

var
  Dir: AnsiString;
  EnvPath, EnvDisplay, EnvWayland: AnsiString;

function FakeEnv(const Name: AnsiString): AnsiString;
begin
  if Name = 'PATH' then
    Result := EnvPath
  else if Name = 'DISPLAY' then
    Result := EnvDisplay
  else if Name = 'WAYLAND_DISPLAY' then
    Result := EnvWayland
  else
    Result := '';
end;

procedure WriteBytes(const FileName, Content: AnsiString);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Content) > 0 then
      Stream.WriteBuffer(Content[1], Length(Content));
  finally
    Stream.Free;
  end;
end;

function ReadBytes(const FileName: AnsiString): AnsiString;
var
  Stream: TFileStream;
begin
  Result := '';
  if not FileExists(FileName) then
    Exit;
  Stream := TFileStream.Create(FileName, fmOpenRead);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[1], Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure MakeScript(const Name, Body: AnsiString; Mode: Integer);
begin
  WriteBytes(Dir + '/' + Name, '#!/bin/sh' + #10 + Body);
  fpChmod(Dir + '/' + Name, Mode);
end;

{ A fake that stores standard input in StoreFile for the words In and keeps it for the words Out. }
procedure MakeStore(const Name, InWord, OutWord, StoreFile: AnsiString);
begin
  MakeScript(Name,
    'for word in "$@"; do' + #10 +
    '  case "$word" in' + #10 +
    '    ' + InWord + ') cat > "' + StoreFile + '"; exit 0;;' + #10 +
    '    ' + OutWord + ') if [ -f "' + StoreFile + '" ]; then cat "' + StoreFile + '"; fi; exit 0;;' + #10 +
    '  esac' + #10 +
    'done' + #10 +
    'exit 2' + #10, &755);
end;

procedure MakeAllStores;
begin
  MakeStore('xclip', '-in', '-out', Dir + '/.xclip');
  MakeStore('xsel', '--input', '--output', Dir + '/.xsel');
  MakeScript('wl-copy', 'cat > "' + Dir + '/.wl"' + #10, &755);
  MakeScript('wl-paste', 'if [ -f "' + Dir + '/.wl" ]; then cat "' + Dir + '/.wl"; fi' + #10, &755);
end;

procedure RemoveTree;
const
  Names: array[0..8] of string = ('xclip', 'xsel', 'wl-copy', 'wl-paste', 'notify-send', '.xclip', '.xsel',
    '.wl', '.notes');
var
  I: Integer;
begin
  for I := Low(Names) to High(Names) do
    DeleteFile(Dir + '/' + Names[I]);
  RemoveDir(Dir);
end;

function Contains(const Whole, Part: AnsiString): Boolean;
begin
  Result := Pos(Part, Whole) > 0;
end;

function BigText: AnsiString;
const
  Greeting = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;
var
  I: Integer;
  Lines: TStringList;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    for I := 1 to 20000 do
      Lines.Add('line ' + IntToStr(I) + ' ' + Greeting);
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

var
  Got, Want, Big, Cyrillic: AnsiString;
  Ok: Boolean;
  Started, Elapsed: QWord;
  SavedDir: AnsiString;

begin
  OnClipEnv := @FakeEnv;
  if FileExists(WslClipExe) or FileExists(WslCmdExe) then
  begin
    { On WSL the Windows programs take part in the lookup and the fakes are not the only choice. }
    EnvPath := '/nonexistent';
    EnvDisplay := '';
    EnvWayland := '';
    if FileExists(WslClipExe) then
      Check(ClipCmdSetName = WslClipExe, 'WSL: the write program is clip.exe')
    else
      Check(ClipCmdSetName = '', 'WSL: without clip.exe nothing is available for writing');
    Done;
    Exit;
  end;

  Dir := GetTempDir(False);
  Dir := ExcludeTrailingPathDelimiter(Dir) + '/tvclipcmd_' + IntToStr(fpGetPid);
  RemoveDir(Dir);
  if not ForceDirectories(Dir) then
  begin
    WriteLn('cannot create ', Dir);
    Halt(2);
  end;
  EnvPath := Dir;
  Cyrillic := #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82 + #10 + #$D0#$BC#$D0#$B8#$D1#$80;
  MakeAllStores;

  { 1. Nothing to run without a display. }
  EnvDisplay := '';
  EnvWayland := '';
  Check(ClipCmdSetName = '', 'no display: the write name is empty');
  Check(ClipCmdGetName = '', 'no display: the read name is empty');
  Check(not ClipCmdSet('x'), 'no display: ClipCmdSet is False');
  Got := 'junk';
  Check(not ClipCmdGet(Got), 'no display: ClipCmdGet is False');
  Check(Got = '', 'no display: the text of a failed ClipCmdGet is empty');

  { 2. DISPLAY: xsel comes before xclip. }
  EnvDisplay := ':0';
  Check(ClipCmdSetName = Dir + '/xsel', 'DISPLAY: the write name is the full path of xsel');
  Check(ClipCmdGetName = Dir + '/xsel', 'DISPLAY: the read name is the full path of xsel');
  Check(ClipCmdSet(Cyrillic), 'xsel: ClipCmdSet of a two-line Cyrillic text is True');
  Check(ReadBytes(Dir + '/.xsel') = Cyrillic, 'xsel: the file holds exactly the bytes of the text');
  Got := '';
  Check(ClipCmdGet(Got), 'xsel: ClipCmdGet is True');
  Check(Got = Cyrillic, 'xsel: ClipCmdGet returns the bytes that were written');

  { A file that is not executable is not a program. }
  fpChmod(Dir + '/xsel', &644);
  Check(Contains(ClipCmdSetName, '/xclip'), 'a plain file xsel is skipped for writing');
  Check(Contains(ClipCmdGetName, '/xclip'), 'a plain file xsel is skipped for reading');

  { 3. Without xsel: xclip, and a NUL byte goes through. }
  DeleteFile(Dir + '/xsel');
  Check(Contains(ClipCmdSetName, '/xclip'), 'no xsel: the write name contains /xclip');
  Check(Contains(ClipCmdGetName, '/xclip'), 'no xsel: the read name contains /xclip');
  Want := 'abc' + #0 + 'def';
  Check(ClipCmdSet(Want), 'xclip: ClipCmdSet of a text with a NUL is True');
  Check(ReadBytes(Dir + '/.xclip') = Want, 'xclip: the file holds the NUL byte');
  Got := '';
  Check(ClipCmdGet(Got), 'xclip: ClipCmdGet of a text with a NUL is True');
  Check(Got = Want, 'xclip: the text with a NUL is read back whole');

  { 4. WAYLAND_DISPLAY: the wl pair comes first. }
  EnvWayland := 'wayland-0';
  Check(Contains(ClipCmdSetName, '/wl-copy'), 'Wayland: the write name contains /wl-copy');
  Check(Contains(ClipCmdGetName, '/wl-paste'), 'Wayland: the read name contains /wl-paste');
  Check(ClipCmdSet(Cyrillic), 'wl-copy: ClipCmdSet is True');
  Check(ReadBytes(Dir + '/.wl') = Cyrillic, 'wl-copy: the file holds the bytes of the text');
  Got := '';
  Check(ClipCmdGet(Got), 'wl-paste: ClipCmdGet is True');
  Check(Got = Cyrillic, 'wl-paste: ClipCmdGet returns the bytes that were written');

  { 5. A text much larger than the pipe buffer. }
  Big := BigText;
  Check(Length(Big) > 300000, 'the big text is larger than 300000 bytes');
  Check(ClipCmdSet(Big), 'big text: ClipCmdSet is True');
  Check(ReadBytes(Dir + '/.wl') = Big, 'big text: the file is equal');
  Got := '';
  Check(ClipCmdGet(Got), 'big text: ClipCmdGet is True');
  Check(Got = Big, 'big text: the text read back is equal');

  { 6. An empty store reads as True with the empty text; an empty text can be written. }
  EnvWayland := '';
  Check(ClipCmdSet(''), 'empty text: ClipCmdSet is True');
  Check(ReadBytes(Dir + '/.xclip') = '', 'empty text: the file is empty');
  Got := 'junk';
  Check(ClipCmdGet(Got), 'empty store: ClipCmdGet is True');
  Check(Got = '', 'empty store: the text is empty');

  { 7. A failing program, and one that hangs. }
  MakeScript('xclip', 'exit 1' + #10, &755);
  Check(not ClipCmdSet('x'), 'exit 1: ClipCmdSet is False');
  Got := 'junk';
  Check(not ClipCmdGet(Got), 'exit 1: ClipCmdGet is False');
  Check(Got = '', 'exit 1: the text of a failed ClipCmdGet is empty');

  MakeScript('xclip', 'exec sleep 20' + #10, &755);
  Started := GetTickCount64;
  Ok := ClipCmdSet('x');
  Elapsed := GetTickCount64 - Started;
  Check(not Ok, 'sleeping program: ClipCmdSet is False');
  Check(Elapsed < 4000, 'sleeping program: ClipCmdSet returns in under 4 seconds');
  Check(Elapsed >= 1000, 'sleeping program: ClipCmdSet waits for the time limit');
  Got := 'junk';
  Started := GetTickCount64;
  Ok := ClipCmdGet(Got);
  Elapsed := GetTickCount64 - Started;
  Check(not Ok, 'sleeping program: ClipCmdGet is False');
  Check(Elapsed < 4000, 'sleeping program: ClipCmdGet returns in under 4 seconds');
  Check(Got = '', 'sleeping program: the text of a timed out ClipCmdGet is empty');

  { 8. Output of a program that then fails is accepted; a program that ends without output is an empty success. }
  MakeScript('xclip', 'printf partial' + #10 + 'exit 1' + #10, &755);
  Got := '';
  Check(ClipCmdGet(Got), 'output then failure: ClipCmdGet is True');
  Check(Got = 'partial', 'output then failure: the output is kept');
  MakeScript('xclip', 'exit 0' + #10, &755);
  Got := 'junk';
  Check(ClipCmdGet(Got), 'exit 0 without output: ClipCmdGet is True');
  Check(Got = '', 'exit 0 without output: the text is empty');

  { 9. A writer that ends early without reading a large text fails; its status 0 does not help. }
  MakeScript('xclip', 'exit 0' + #10, &755);
  Check(not ClipCmdSet(Big), 'early exit 0: a text larger than the pipe buffer fails');

  { 10. The environment hook: an empty PATH falls back to the default list, which does not hold the fakes. }
  MakeAllStores;
  EnvPath := '';
  EnvDisplay := ':0';
  Check(Pos(Dir, ClipCmdSetName) = 0, 'empty PATH: the fakes are not found');
  Check(Pos(Dir, ClipCmdGetName) = 0, 'empty PATH: the fakes are not found for reading');
  { An empty element of PATH is the current directory. }
  MakeAllStores;
  DeleteFile(Dir + '/xsel');
  SavedDir := GetCurrentDir;
  Check(SetCurrentDir(Dir), 'the test can change to its directory');
  EnvPath := ':/nonexistent';
  Check(Contains(ClipCmdSetName, '/xclip'), 'an empty PATH element is the current directory');
  SetCurrentDir(SavedDir);
  EnvPath := Dir;

  { 11. Notifications. }
  MakeScript('notify-send', 'rm -f "' + Dir + '/.notes"' + #10 +
    'for word in "$@"; do printf ''%s\n'' "$word" >> "' + Dir + '/.notes"; done' + #10 + 'exit 0' + #10, &755);
  EnvDisplay := ':0';
  EnvWayland := '';
  Check(NotifyCmd('Title', 'Body text'), 'NotifyCmd with DISPLAY is True');
  Check(ReadBytes(Dir + '/.notes') = '--' + #10 + 'Title' + #10 + 'Body text' + #10,
    'NotifyCmd passes --, the title and the text');
  Check(NotifyCmd('', ''), 'NotifyCmd with empty texts is True');
  Check(ReadBytes(Dir + '/.notes') = '--' + #10 + ' ' + #10 + ' ' + #10, 'NotifyCmd replaces empty texts by a blank');
  EnvDisplay := '';
  EnvWayland := 'wayland-0';
  DeleteFile(Dir + '/.notes');
  Check(NotifyCmd('t', 'x'), 'NotifyCmd with WAYLAND_DISPLAY is True');
  Check(FileExists(Dir + '/.notes'), 'NotifyCmd with WAYLAND_DISPLAY ran the program');
  EnvWayland := '';
  DeleteFile(Dir + '/.notes');
  Check(not NotifyCmd('t', 'x'), 'NotifyCmd without a display is False');
  Check(not FileExists(Dir + '/.notes'), 'NotifyCmd without a display does not run the program');
  EnvDisplay := ':0';
  MakeScript('notify-send', 'exit 3' + #10, &755);
  Check(not NotifyCmd('t', 'x'), 'NotifyCmd is False when the program ends with status 3');
  DeleteFile(Dir + '/notify-send');
  Check(not NotifyCmd('t', 'x'), 'NotifyCmd is False without the program');

  RemoveTree;
  Done;
end.

{$ENDIF}
