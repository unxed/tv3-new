{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/platform.h, source/platform/platform.cpp,
  include/tvision/internal/unixcon.h, source/platform/unixcon.cpp, include/tvision/internal/sigwinch.h,
  source/platform/sigwinch.cpp, include/tvision/internal/sighandl.h, source/platform/sighandl.cpp,
  include/tvision/internal/errredir.h, source/platform/errredir.cpp, include/tvision/internal/ncurdisp.h,
  source/platform/ncurdisp.cpp, include/tvision/internal/ncursinp.h, source/platform/ncursinp.cpp,
  include/tvision/internal/unixclip.h, source/platform/unixclip.cpp, source/platform/hardware.cpp,
  include/tvision/hardware.h
  See COPYRIGHT.magiblot.

  The tests use a pipe for the input of the console and a pipe for its output, which ConsoleCtl takes through
  UseDescriptors, so that no terminal is needed. The expected bytes and events are worked out by hand from the
  C++ routines and from the sequences of TvAnsi and TvTermIo. The size of the screen of two pipes is 80 by 25.
  The clock of the display buffer moves on by a second at every call, so that no flush is put off. }
program t_unix;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  ctypes, SysUtils, BaseUnix, TvGeom, TvColors, TvCell, TvKeys, TvEvents, TvSys, TvDispBuf, TvScreen, TvClip,
  TvTermOs, TvUnix;

{$I testlib.inc}

const
  Esc = #27;
  { The value of cmScreenChanged. }
  CmScreenChangedValue = 57;

var
  InPipe, OutPipe: TFilDes;
  Con: ConsoleCtl;
  ClockNow: QWord;
  Trace: AnsiString;
  TermCount: Integer;
  GotPaste: AnsiString;
  Inp: NcursesInput;
  Ev: TEvent;

function FakeClock: QWord;
begin
  Inc(ClockNow, 1000000);
  Result := ClockNow;
end;

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

procedure OpenPipes;
begin
  Check(fpPipe(InPipe) = 0, 'input pipe made');
  Check(fpPipe(OutPipe) = 0, 'output pipe made');
  fpFcntl(OutPipe[0], F_SETFL, O_NONBLOCK);
  ConsoleCtl.DestroyInstance;
  Con := ConsoleCtl.GetInstance;
  Con.UseDescriptors(InPipe[0], OutPipe[1]);
end;

procedure ClosePipes;
begin
  ConsoleCtl.DestroyInstance;
  fpClose(InPipe[0]);
  fpClose(InPipe[1]);
  fpClose(OutPipe[0]);
  fpClose(OutPipe[1]);
end;

{ Everything that the console has written since the last call. }
function Drain: AnsiString;
var
  Buf: array[0..4095] of AnsiChar;
  Got: TSsize;
  Part: AnsiString;
begin
  Result := '';
  repeat
    Got := fpRead(OutPipe[0], PAnsiChar(@Buf[0]), SizeOf(Buf));
    if Got > 0 then
    begin
      SetString(Part, PAnsiChar(@Buf[0]), Got);
      Result := Result + Part;
    end;
  until Got <= 0;
end;

procedure Feed(const S: AnsiString);
begin
  fpWrite(InPipe[1], PAnsiChar(S), Length(S));
end;

function Has(const Hay, Needle: AnsiString): Boolean;
begin
  Result := Pos(Needle, Hay) > 0;
end;

{ Signals }

procedure TermProbe(Sig: cint); cdecl;
begin
  Inc(TermCount);
end;

procedure NotifyOne(Enter: Boolean);
begin
  if Enter then
    Trace := Trace + 'E'
  else
    Trace := Trace + 'L';
end;

procedure NotifyTwo(Enter: Boolean);
begin
  Trace := Trace + 'X';
end;

{ The action of SIGTERM that the handler finds and passes the signal on to. }
procedure SetProbe;
var
  Sa: SigActionRec;
begin
  FillChar(Sa, SizeOf(Sa), 0);
  PPointer(@Sa)^ := @TermProbe;
  Sa.sa_flags := SA_RESTART;
  fpSigAction(SIGTERM, @Sa, nil);
end;

procedure ClearProbe;
var
  Sa: SigActionRec;
begin
  FillChar(Sa, SizeOf(Sa), 0);
  fpSigAction(SIGTERM, @Sa, nil);
end;

procedure TestSignalHandler;
begin
  Check(HandledSignalCount = 10, 'ten signals are handled');
  Check(SignalHandler.HandledSignal(0) = SIGINT, 'the first signal is SIGINT');
  Check(SignalHandler.HandledSignal(1) = SIGQUIT, 'the second signal is SIGQUIT');
  Check(SignalHandler.HandledSignal(8) = SIGTERM, 'the ninth signal is SIGTERM');
  Check(SignalHandler.HandledSignal(9) = SIGTSTP, 'the last signal is SIGTSTP');
  Trace := '';
  TermCount := 0;
  SetProbe;
  SignalHandler.Enable(@NotifyOne);
  { A second call changes nothing while the first one is in force. }
  SignalHandler.Enable(@NotifyTwo);
  fpKill(fpGetPid, SIGTERM);
  Check(Trace = 'EL', 'the callback is called on entry and on leaving');
  Check(TermCount = 1, 'the previous action runs between the two calls');
  fpKill(fpGetPid, SIGTERM);
  Check(Trace = 'ELEL', 'the handler works a second time');
  Check(TermCount = 2, 'the previous action runs a second time');
  SignalHandler.Disable;
  fpKill(fpGetPid, SIGTERM);
  Check(Trace = 'ELEL', 'no callback after Disable');
  Check(TermCount = 3, 'the previous action is back after Disable');
  SignalHandler.Disable;
  fpKill(fpGetPid, SIGTERM);
  Check(TermCount = 4, 'a second Disable changes nothing');
  ClearProbe;
end;

procedure TestSigwinch;
var
  H: SigwinchHandler;
  E: TEvent;
begin
  H := SigwinchHandler.Make;
  Check(H <> nil, 'handler made');
  Check(SigwinchHandler.Make = nil, 'one handler at a time');
  FillChar(E, SizeOf(E), 0);
  Check(not H.GetEvent(E), 'no event before the signal');
  fpKill(fpGetPid, SIGWINCH);
  Check(H.GetEvent(E), 'event after the signal');
  Check((E.What = evCommand) and (E.Message.Command = CmScreenChangedValue), 'the event is cmScreenChanged');
  Check(not H.GetEvent(E), 'the event comes once');
  fpKill(fpGetPid, SIGWINCH);
  fpKill(fpGetPid, SIGWINCH);
  Check(H.GetEvent(E), 'event after two signals');
  Check(not H.GetEvent(E), 'two signals give one event');
  H.Free;
  H := SigwinchHandler.Make;
  Check(H <> nil, 'handler made again after the first one ended');
  H.Free;
end;

procedure TestStderrRedirector;
var
  Before, After: Stat;
  R: StderrRedirector;
begin
  Check(fpFStat(2, Before) = 0, 'standard error is open');
  R := StderrRedirector.Create;
  R.Free;
  Check(fpFStat(2, After) = 0, 'standard error is open after the redirector');
  Check((Before.st_dev = After.st_dev) and (Before.st_ino = After.st_ino),
    'standard error is the same file after the redirector');
end;

{ The base console adapter and the platform without a console }

procedure TestDummy;
var
  C: ConsoleAdapter;
  P: Platform;
  Started: QWord;
begin
  C := ConsoleAdapter.Create(nil, []);
  Check(C.IsAlive, 'the base console is alive');
  Check(Length(C.Sources) = 0, 'the base console has no sources');
  Check(not C.SetClipboardText('x'), 'the base console has no clipboard to set');
  Check(not C.RequestClipboardText(nil), 'the base console has no clipboard to ask');
  C.Free;

  Platform.DestroyInstance;
  P := Platform.GetInstance;
  Check(P = Platform.GetInstance, 'the platform is a singleton');
  Check(not P.IsSetUp, 'no console at first');
  Check((P.GetScreenCols = 0) and (P.GetScreenRows = 0), 'no size at first');
  Check(P.GetCaretSize = 1, 'the caret size is at least 1');
  Check(not P.IsCaretVisible, 'no caret before the first flush');
  Check(P.GetScreenMode = TDisplay.smMono, 'the dummy display has no colors');
  Check(not P.SetClipboardText('x'), 'the dummy console cannot set the clipboard');
  Check(not P.RequestClipboardText(nil), 'the dummy console cannot ask the clipboard');
  FillChar(Ev, SizeOf(Ev), 0);
  Check(not P.GetEvent(Ev), 'no event without sources');
  Started := GetTickCount64;
  P.WaitForEvents(60);
  Check(GetTickCount64 - Started >= 40, 'the wait lasts for the time-out');
  P.InterruptEventWait;
  Started := GetTickCount64;
  P.WaitForEvents(3000);
  Check(GetTickCount64 - Started < 1500, 'the wait ends at once after an interruption');
  Platform.DestroyInstance;
end;

{ The reader of the descriptor }

procedure TestInputGetter;
var
  G: NcursesInputGetter;
begin
  OpenPipes;
  G := NcursesInputGetter.Create(InPipe[0]);
  Check(G.TimeoutMs = 10, 'the default time-out is 10 ms');
  Check(G.Get = -1, 'no byte gives -1');
  Feed('ab');
  Check(G.Get = 97, 'the first byte');
  Check(G.PendingCount = 1, 'the second byte is read already');
  Check(G.Get = 98, 'the second byte');
  Check(G.PendingCount = 0, 'nothing is pending');
  G.Unget(65);
  G.Unget(66);
  Check(G.PendingCount = 2, 'two bytes given back');
  Check(G.Get = 66, 'the last byte given back comes first');
  Check(G.Get = 65, 'then the one before');
  G.Unget(-1);
  Check(G.PendingCount = 0, 'minus one is not kept');
  G.TimeoutMs := 0;
  Check(G.Get = -1, 'no wait with the time-out 0');
  G.Free;
  ClosePipes;
end;

{ The display adapter }

procedure TestDisplay;
var
  D: NcursesDisplay;
  Got: AnsiString;
  Size: TPoint;
  Count, AtPos, AtCaret: Integer;
begin
  OpenPipes;
  D := NcursesDisplay.Create(Con);
  Check(Drain = Esc + '[?1049h' + Esc + '[0m' + Esc + '[2J', 'entering the alternate screen');
  Size := D.ReloadScreenInfo;
  Check((Size.X = 80) and (Size.Y = 25), 'two pipes give the size 80 by 25');
  Count := D.GetColorCount;
  Check((Count = 0) or (Count = 8) or (Count = 16) or (Count = 256) or (Count = 16777216),
    'the color count is one of the levels');
  Size := D.GetFontSize;
  Check((Size.X = 0) and (Size.Y = 0), 'two pipes give no font size');
  D.WriteCell(Pt(2, 1), 'A', TColorAttr.Create($07), False);
  D.SetCaretPosition(Pt(4, 3));
  Check(Drain = '', 'cells wait for the flush');
  D.Flush;
  Got := Drain;
  Check(Pos(Esc + '[0m', Got) = 1, 'the reset of the reload comes first');
  AtPos := Pos(Esc + '[2;3H', Got);
  Check(AtPos > 0, 'the cell is put at row 2, column 3');
  Check(Pos('A', Got) > AtPos, 'the text of the cell follows its position');
  AtCaret := Pos(Esc + '[4;5H', Got);
  Check(AtCaret > Pos('A', Got), 'the caret is put at row 4, column 5 after the cell');
  D.Flush;
  Check(Drain = '', 'a second flush writes nothing');
  D.ClearScreen;
  D.Flush;
  Check(Has(Drain, Esc + '[2J'), 'the screen is cleared');
  D.SetCaretSize(0);
  Check(Drain = Esc + '[?25l', 'the caret of the size 0 is hidden');
  D.SetCaretSize(100);
  Check(Drain = Esc + '[?12;25h', 'the caret of the size 100 is very visible');
  D.SetCaretSize(30);
  Check(Drain = Esc + '[?12l' + Esc + '[?25h', 'the other sizes give the normal caret');
  D.Free;
  Check(Drain = Esc + '[0m' + Esc + '[?25h' + Esc + '[?1049l', 'leaving the alternate screen');
  ClosePipes;
end;

{ The input adapter }

function Key(const Bytes: AnsiString): Boolean;
begin
  Feed(Bytes);
  FillChar(Ev, SizeOf(Ev), 0);
  Result := Inp.GetEvent(Ev);
end;

procedure TestInput;
var
  St: PInputState;
  Got: AnsiString;
begin
  OpenPipes;
  New(St);
  FillChar(St^, SizeOf(St^), 0);
  Inp := NcursesInput.Create(Con, nil, St, True);
  Got := Drain;
  Check(Has(Got, Esc + '[?1006h'), 'the mouse is turned on');
  Check(Has(Got, Esc + '[?2004h'), 'bracketed paste is turned on');
  Check(not Inp.HasPendingEvents, 'nothing is pending at first');
  FillChar(Ev, SizeOf(Ev), 0);
  Check(not Inp.GetEvent(Ev), 'no input gives no event');

  Check(Key('a'), 'a letter is a key');
  Check(Ev.What = evKeyDown, 'the letter is a key down event');
  Check(Ev.KeyDown.KeyCode = $0061, 'the key code of a letter is its character');
  Check((Ev.KeyDown.TextLength = 1) and (Ev.KeyDown.Text[0] = 97), 'the text of a letter');
  Check(Ev.KeyDown.ControlKeyState = 0, 'a letter has no modifier');

  Check(Key(#13) and (Ev.KeyDown.KeyCode = kbEnter) and (Ev.KeyDown.TextLength = 0), 'carriage return is Enter');
  Check(Key(#10) and (Ev.KeyDown.KeyCode = kbEnter), 'line feed is Enter');
  Check(Key(#9) and (Ev.KeyDown.KeyCode = kbTab), 'tab');
  Check(Key(#8) and (Ev.KeyDown.KeyCode = kbBack), 'backspace');
  Check(Key(#127) and (Ev.KeyDown.KeyCode = kbBack), 'delete is Backspace');
  Check(Key(#3) and (Ev.KeyDown.KeyCode = kbCtrlC) and (Ev.KeyDown.ControlKeyState = kbLeftCtrl), 'Ctrl+C');
  Check(Key(#0) and (Ev.KeyDown.KeyCode = Ord('@')) and (Ev.KeyDown.ControlKeyState = kbLeftCtrl) and
    (Ev.KeyDown.TextLength = 1) and (Ev.KeyDown.Text[0] = Ord('@')), 'the null character is Ctrl+@');
  Check(Key(#28) and (Ev.KeyDown.KeyCode = Ord('\')) and (Ev.KeyDown.ControlKeyState = kbLeftCtrl), 'Ctrl+backslash');
  Check(Key(#27) and (Ev.KeyDown.KeyCode = kbEsc), 'escape alone is Esc');

  Check(Key(Esc + 'x'), 'escape and a letter');
  Check(Ev.KeyDown.KeyCode = kbAltX, 'escape and a letter are Alt+letter');
  Check((Ev.KeyDown.ControlKeyState and kbAltShift) <> 0, 'Alt+letter has the Alt state');

  Check(Key(#$C3#$A9), 'a two-byte character');
  Check((Ev.KeyDown.TextLength = 2) and (Ev.KeyDown.Text[0] = $C3) and (Ev.KeyDown.Text[1] = $A9),
    'the text of a two-byte character');
  Check(Ev.KeyDown.KeyCode = $0082, 'the key code is the character of the code page');

  Check(Key(Esc + '[A') and (Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbUp), 'the up arrow');
  Check(Ev.KeyDown.ControlKeyState = 0, 'the up arrow has no modifier');
  Check(Key(Esc + 'OP') and (Ev.KeyDown.KeyCode = kbF1), 'F1 as an SS3 sequence');
  Check(Key(Esc + 'OQ') and (Ev.KeyDown.KeyCode = kbF2), 'F2 as an SS3 sequence');
  Check(Key(Esc + 'OA') and (Ev.KeyDown.KeyCode = kbUp), 'the up arrow as an SS3 sequence');
  Check(Key(Esc + '[1;5A') and (Ev.KeyDown.KeyCode = kbCtrlUp) and
    ((Ev.KeyDown.ControlKeyState and kbCtrlShift) <> 0), 'Ctrl+Up');
  Check(Key(Esc + '[3~') and (Ev.KeyDown.KeyCode = kbDel), 'the delete key');
  Check(Key(Esc + '[5~') and (Ev.KeyDown.KeyCode = kbPgUp), 'the page up key');

  Check(Key(Esc + '[<0;10;5M') and (Ev.What = evMouse), 'a mouse press');
  Check((Ev.Mouse.Where.X = 9) and (Ev.Mouse.Where.Y = 4), 'the position of the mouse is zero-based');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'the left button is down');
  Check(St^.Buttons = mbLeftButton, 'the state keeps the button');
  Check(Key(Esc + '[<0;10;5m') and (Ev.What = evMouse) and (Ev.Mouse.Buttons = 0), 'a mouse release');
  Check(Key(Esc + '[<64;1;1M') and (Ev.Mouse.Wheel = mwUp), 'the wheel up');
  Check(Key(Esc + '[<65;1;1M') and (Ev.Mouse.Wheel = mwDown), 'the wheel down');

  Check(not Key(Esc + '[200~'), 'the start of a paste gives no event');
  Check(St^.BracketedPaste, 'the paste state is on');
  Check(Key('q') and ((Ev.KeyDown.ControlKeyState and kbPaste) <> 0), 'a key of a paste has the paste flag');
  Check(not Key(Esc + '[201~'), 'the end of a paste gives no event');
  Check(not St^.BracketedPaste, 'the paste state is off');
  Check(Key('r') and ((Ev.KeyDown.ControlKeyState and kbPaste) = 0), 'a key after the paste has no flag');

  { Two keys that arrive together. }
  Feed('xy');
  FillChar(Ev, SizeOf(Ev), 0);
  Check(Inp.GetEvent(Ev) and (Ev.KeyDown.Text[0] = Ord('x')), 'the first of two keys');
  Check(Inp.HasPendingEvents, 'the second key is pending');
  FillChar(Ev, SizeOf(Ev), 0);
  Check(Inp.GetEvent(Ev) and (Ev.KeyDown.Text[0] = Ord('y')), 'the second of two keys');
  Check(not Inp.HasPendingEvents, 'nothing is pending after both');

  Drain;
  Inp.Free;
  Got := Drain;
  Check(Has(Got, Esc + '[?1006l'), 'the mouse is turned off');
  Check(Has(Got, Esc + '[?2004l'), 'bracketed paste is turned off');
  Check(Has(Got, Esc + '[6n'), 'the device status is asked for before the end');
  Dispose(St);
  ClosePipes;
end;

{ The clipboard programs }

procedure PasteProbe(const Text: string);
begin
  GotPaste := Text;
end;

procedure TestPrograms;
var
  Data: AnsiString;
  Started: QWord;
begin
  Check(UnixClipboard.Enabled, 'the programs are enabled at the start');
  Check(UnixClipboard.ExecutableExists('/bin/sh'), 'a program by its path');
  Check(not UnixClipboard.ExecutableExists('/no/such/program'), 'a path that does not exist');
  Check(not UnixClipboard.ExecutableExists('no-such-program-of-the-tests'), 'a name that is not on PATH');
  Check(not UnixClipboard.ExecutableExists('/etc'), 'a directory is not a program');
  Check(UnixClipboard.ExecutableExists('sh'), 'a program found along PATH');
  Check(UnixClipboard.ReadSubprocess(['/bin/echo', 'hello'], [], 3000, Data), 'the output of a program is read');
  Check(Data = 'hello'#10, 'the text that the program wrote');
  Check(UnixClipboard.ReadSubprocess(['/bin/sh', '-c', 'printf %s "$TV_TEST_VAR"'], ['TV_TEST_VAR', 'seen'], 3000,
    Data), 'a program with a variable');
  Check(Data = 'seen', 'the variable is set for the program');
  Check(not UnixClipboard.ReadSubprocess(['/bin/sh', '-c', 'exit 3'], [], 3000, Data),
    'a failing program without output');
  Check(Data = '', 'no text from a failing program');
  Check(UnixClipboard.ReadSubprocess(['/bin/sh', '-c', 'printf abc; exit 3'], [], 3000, Data),
    'a failing program with output');
  Check(Data = 'abc', 'the output of the failing program is kept');
  Check(not UnixClipboard.ReadSubprocess(['/no/such/program'], [], 100, Data), 'a program that does not exist');
  Started := GetTickCount64;
  Check(not UnixClipboard.ReadSubprocess(['/bin/sh', '-c', 'sleep 5'], [], 200, Data), 'a program that is too slow');
  Check(GetTickCount64 - Started < 4000, 'a slow program is stopped');
  Check(UnixClipboard.WriteSubprocess(['/bin/cat'], 'some text', 3000), 'a program takes a text');
  Check(UnixClipboard.WriteSubprocess(['/bin/cat'], '', 3000), 'a program takes an empty text');
  Check(not UnixClipboard.WriteSubprocess(['/bin/sh', '-c', 'cat >/dev/null; exit 1'], 'x', 3000),
    'a program that ends with a status other than 0');
  Check(not UnixClipboard.WriteSubprocess(['/no/such/program'], 'x', 100), 'writing to a program that does not exist');
  UnixClipboard.Enabled := False;
  Check(not UnixClipboard.SetClipboardText('x'), 'no set while the programs are disabled');
  Check(not UnixClipboard.RequestClipboardText(@PasteProbe), 'no request while the programs are disabled');
  UnixClipboard.Enabled := True;
end;

{ The three backends on the platform }

procedure TestBackends;
var
  OldEvents: TEventBackend;
  OldScreen: TScreenBackend;
  OldClip: TClipboardBackend;
  OldClock: TDisplayClockFunc;
  Events: TUnixEventBackend;
  Screen: TUnixScreenBackend;
  Clip: TUnixClipboardBackend;
  Cells: array[0..2] of TScreenCell;
  Cells0: Pointer;
  Got: AnsiString;
  E: TEvent;
  M, M2: TMouseEventType;
  Mode: Word;
  Started: QWord;
  I: Integer;
begin
  OldEvents := TEventQueue.Backend;
  OldScreen := TDisplay.Backend;
  OldClip := TClipboard.Backend;
  OldClock := DisplayClock;
  Platform.DestroyInstance;
  DisplayClock := @FakeClock;
  OpenPipes;
  TermCount := 0;
  SetProbe;
  UnixClipboard.Enabled := False;

  Events := TUnixEventBackend.Create;
  Screen := TUnixScreenBackend.Create;
  Clip := TUnixClipboardBackend.Create;
  TEventQueue.Backend := Events;
  TDisplay.Backend := Screen;
  TClipboard.Backend := Clip;

  Check(Events.GetButtonCount = 2, 'the mouse has two buttons');
  Check(not Clip.SetText('x'), 'no console, no system clipboard');
  Check(not Platform.GetInstance.IsSetUp, 'the console is not set up yet');

  { The console }
  Screen.SetUpConsole;
  Check(Platform.GetInstance.IsSetUp, 'the console is set up');
  Got := Drain;
  Check(Has(Got, Esc + '[?1049h'), 'the alternate screen is entered');
  Check(Has(Got, Esc + '[?1006h'), 'the mouse is turned on by the console');
  Check(Pos(Esc + '[?1049h', Got) < Pos(Esc + '[?1006h', Got), 'the display starts before the input');

  { The screen }
  Cells0 := Screen.AllocateScreenBuffer;
  Check(Cells0 <> nil, 'the screen has a buffer');
  Check((Screen.GetScreenCols = 80) and (Screen.GetScreenRows = 25), 'the size of the screen');
  Check((Events.ScreenWidth = 80) and (Events.ScreenHeight = 25), 'the event backend knows the size');
  Mode := Screen.GetScreenMode;
  Check(((Mode and $FF) = TDisplay.smMono) or ((Mode and $FF) = TDisplay.smCO80), 'the mode is mono or color');
  Check((Mode and TDisplay.smFont8x8) = 0, 'no font size, no font flag');
  Check(Screen.GetCaretSize = 1, 'the caret size before the first flush');
  for I := 0 to 2 do
  begin
    FillChar(Cells[I], SizeOf(Cells[I]), 0);
    Cells[I].Character.InitWithChar(Chr(Ord('X') + I));
    Cells[I].Attribute := TColorAttr.Create($07);
  end;
  UnixScreenWrite(1, 0, @Cells[0], 3);
  UnixCaretPosition(3, 2);
  Screen.SetCaretSize(100);
  Check(Drain = '', 'nothing is written before the flush');
  Screen.FlushScreen;
  Got := Drain;
  Check(Has(Got, Esc + '[1;2H'), 'the cells are put at row 1, column 2');
  Check(Has(Got, 'XYZ'), 'the three cells are written together');
  Check(Pos(Esc + '[3;4H', Got) > Pos('XYZ', Got), 'the caret is put after the cells');
  Check(Has(Got, Esc + '[?12;25h'), 'the caret is very visible');
  Check(Screen.GetCaretSize = 100, 'the caret size after the flush');
  Screen.FlushScreen;
  Check(Drain = '', 'a flush without changes writes nothing');
  Screen.ClearScreen(80, 25);
  Check(Has(Drain, Esc + '[2J'), 'the screen is cleared');

  { The events }
  Feed('k');
  Events.WaitForEvents(2000);
  FillChar(E, SizeOf(E), 0);
  Check(Events.GetKeyEvent(E), 'a key is read');
  Check((E.What = evKeyDown) and (E.KeyDown.KeyCode = $006B), 'the key is the letter k');
  Check((E.KeyDown.ControlKeyState and kbInsState) <> 0, 'the insert state is added to the key');
  FillChar(E, SizeOf(E), 0);
  Check(Events.GetKeyEvent(E), 'the resize event is read');
  Check((E.What = evCommand) and (E.Message.Command = CmScreenChangedValue), 'it is cmScreenChanged');
  FillChar(E, SizeOf(E), 0);
  Check(not Events.GetKeyEvent(E), 'no more events');

  Feed(Esc + '[<0;10;5M');
  Events.WaitForEvents(2000);
  FillChar(E, SizeOf(E), 0);
  Check(not Events.GetKeyEvent(E), 'a mouse event is not a key');
  FillChar(M, SizeOf(M), 0);
  Check(Events.GetMouseEvent(M), 'the mouse event is read');
  Check((M.Where.X = 9) and (M.Where.Y = 4) and (M.Buttons = mbLeftButton), 'the position and the button');
  FillChar(M2, SizeOf(M2), 0);
  Events.MouseGetState(M2);
  Check((M2.Where.X = 9) and (M2.Buttons = mbLeftButton), 'the state of the mouse is the last event');
  Check(not Events.GetMouseEvent(M), 'one mouse event');
  Events.ClearPendingEvent;

  Events.InterruptEventWait;
  Started := GetTickCount64;
  Events.WaitForEvents(3000);
  Check(GetTickCount64 - Started < 1500, 'the interruption ends the wait');
  FillChar(E, SizeOf(E), 0);
  Check(not Events.GetKeyEvent(E), 'the interruption is not a key');

  Feed('m');
  TEventQueue.WaitForEvents(2000);
  FillChar(E, SizeOf(E), 0);
  TEventQueue.GetKeyEvent(E);
  Check((E.What = evKeyDown) and (E.KeyDown.Text[0] = Ord('m')), 'a key through the queue');

  { The clipboard through OSC 52 }
  Drain;
  Check(not Clip.SetText('hi'), 'the text is not taken without full OSC 52');
  Got := Drain;
  Check(Has(Got, Esc + ']52;;aGk=' + #7), 'the text goes out as an OSC 52 sequence');
  Feed(Esc + ']52;c;Zm9v' + #7);
  Events.WaitForEvents(2000);
  FillChar(E, SizeOf(E), 0);
  Check(not Events.GetKeyEvent(E), 'the answer of the terminal is not an event');
  Check(Clip.SetText('hi'), 'the text is taken once the terminal answered');
  Check(Has(Drain, Esc + ']52;;aGk=' + #7), 'the sequence is written again');
  GotPaste := '';
  Check(Clip.RequestText(@PasteProbe), 'the request is made');
  Check(Has(Drain, Esc + ']52;;?' + #7), 'the request goes out as an OSC 52 sequence');
  Feed(Esc + ']52;c;aGVsbG8=' + #7);
  Events.WaitForEvents(2000);
  FillChar(E, SizeOf(E), 0);
  Check(not Events.GetKeyEvent(E), 'the text of the clipboard is not an event');
  Check(GotPaste = 'hello', 'the text of the clipboard is given to the procedure');

  { A signal takes the console and gives it back, and the previous action of the signal runs. }
  Drain;
  TermCount := 0;
  fpKill(fpGetPid, SIGTERM);
  Check(TermCount = 1, 'the previous action of the signal ran');
  Got := Drain;
  Check(Has(Got, Esc + '[?1049l'), 'the console was given back');
  Check(Pos(Esc + '[?1049h', Got) > Pos(Esc + '[?1049l', Got), 'and taken again');
  Check(Platform.GetInstance.IsSetUp, 'the console is in use after the signal');
  Feed('n');
  Events.WaitForEvents(2000);
  FillChar(E, SizeOf(E), 0);
  Check(Events.GetKeyEvent(E) and (E.What = evKeyDown) and (E.KeyDown.Text[0] = Ord('n')),
    'keys are read after the console is taken again');
  FillChar(E, SizeOf(E), 0);
  Check(Events.GetKeyEvent(E) and (E.What = evCommand) and (E.Message.Command = CmScreenChangedValue),
    'the new console asks for the size again');

  { The end }
  Drain;
  Screen.RestoreConsole;
  Got := Drain;
  Check(Has(Got, Esc + '[6n'), 'the device status is asked for at the end');
  Check(Has(Got, Esc + '[?1049l'), 'the alternate screen is left');
  Check(not Platform.GetInstance.IsSetUp, 'the console is given back');
  Screen.FreeScreenBuffer(nil);
  Check(Screen.GetScreenCols = 0, 'the screen buffer is freed');

  ClearProbe;
  Platform.DestroyInstance;
  ClosePipes;
  TEventQueue.Backend := OldEvents;
  TDisplay.Backend := OldScreen;
  TClipboard.Backend := OldClip;
  DisplayClock := OldClock;
  UnixClipboard.Enabled := True;
  Clip.Free;
  Screen.Free;
  Events.Free;
end;

begin
  TestSignalHandler;
  TestSigwinch;
  TestStderrRedirector;
  TestDummy;
  TestInputGetter;
  TestDisplay;
  TestInput;
  TestPrograms;
  TestBackends;
  Done;
end.
