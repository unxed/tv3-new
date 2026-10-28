{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/termio.h, source/platform/termio.cpp, include/tvision/internal/far2l.h,
  source/platform/far2l.cpp, include/tvision/internal/base64.h, source/platform/base64.cpp,
  include/tvision/internal/constmap.h, include/tvision/internal/constarr.h, include/tvision/internal/codepage.h,
  include/tvision/internal/utf8.h, include/tvision/internal/win32con.h
  See COPYRIGHT.magiblot. }
program t_termio;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  ctypes, SysUtils, BaseUnix, TvKeys, TvEvents, TvTermOs, TvTermIo;

{$I testlib.inc}

const
  Esc = #27;

  { The start of the sequence of KeyModsOn, up to the check of the clipboard. }
  KeyModsHead = #27'[?1036s'#27'[?1036h'#27'[?2004s'#27'[?2004h'#27'[>4;1m'#27'[>5u'#27'[?9001h'#27'_far2l1'#27'\';
  KeyModsQuery = #27'P+q6b697474792d71756572792d636c6970626f6172645f636f6e74726f6c'#27'\'#27']60'#27'\';
  KeyModsTail = #27'[2J';

type
  { Input bytes from a text; Get gives -1 at its end. }
  TByteSource = class(TInputGetter)
  private
    FBytes: AnsiString;
    FPos: SizeInt;
  public
    constructor Create(const ABytes: AnsiString);
    function Get: Integer; override;
    procedure Unget(Key: Integer); override;
  end;

constructor TByteSource.Create(const ABytes: AnsiString);
begin
  inherited Create;
  FBytes := ABytes;
  FPos := 0;
end;

function TByteSource.Get: Integer;
begin
  if FPos < Length(FBytes) then
  begin
    Result := Ord(FBytes[FPos + 1]);
    Inc(FPos);
  end
  else
    Result := -1;
end;

procedure TByteSource.Unget(Key: Integer);
begin
  if (Key >= 0) and (FPos > 0) then
    Dec(FPos);
end;

var
  St: TInputState;
  Ev: TEvent;
  Fds: TFilDes;
  Con: ConsoleCtl;
  LastPaste: AnsiString = '';
  PasteCalls: Integer = 0;

procedure CollectPaste(const Text: string);
begin
  LastPaste := Text;
  Inc(PasteCalls);
end;

procedure ClearState;
begin
  FillChar(St, SizeOf(St), 0);
end;

function ParseBytes(const Bytes: AnsiString): TParseResult;
var
  Src: TByteSource;
  Buf: TGetChBuf;
begin
  Src := TByteSource.Create(Bytes);
  try
    Buf := TGetChBuf.Create(Src);
    FillChar(Ev, SizeOf(Ev), 0);
    Result := TTermIO.ParseEvent(Buf, Ev, St);
  finally
    Src.Free;
  end;
end;

{ A key that the bytes must give: the key code and the control key state. }
procedure ExpectKey(const Bytes: AnsiString; Code: Word; const Name: string);
begin
  ClearState;
  Check(ParseBytes(Bytes) = Accepted, Name + ': accepted');
  Check(Ev.What = evKeyDown, Name + ': key event');
  Check(Ev.KeyDown.KeyCode = Code, Name + ': key code');
end;

function Le16(Value: Cardinal): AnsiString;
begin
  Result := Chr(Value and $FF) + Chr((Value shr 8) and $FF);
end;

function Le32(Value: Cardinal): AnsiString;
begin
  Result := Le16(Value) + Le16(Value shr 16);
end;

{ The pipe that stands for the terminal. Reads do not wait. }
procedure OpenPipe;
begin
  Check(fpPipe(Fds) = 0, 'pipe made');
  fpFcntl(Fds[0], F_SETFL, O_NONBLOCK);
  Con := ConsoleCtl.GetInstance;
  Con.UseDescriptors(Fds[0], Fds[1]);
end;

procedure ClosePipe;
begin
  fpClose(Fds[0]);
  fpClose(Fds[1]);
  ConsoleCtl.DestroyInstance;
  Con := nil;
end;

function DrainPipe: AnsiString;
var
  Chunk: array[0..4095] of AnsiChar;
  Got: TSsize;
  Part: AnsiString;
begin
  Result := '';
  repeat
    Got := fpRead(Fds[0], PAnsiChar(@Chunk[0]), SizeOf(Chunk));
    if Got > 0 then
    begin
      SetString(Part, PAnsiChar(@Chunk[0]), Got);
      Result := Result + Part;
    end;
  until Got <= 0;
end;

{ Takes the bytes of the far2l request that starts at At in Text, and moves At after it. }
function NextRequest(const Text: AnsiString; var At: SizeInt; out Payload: AnsiString): Boolean;
const
  Head = #27'_far2l:';
var
  First, Stop: SizeInt;
begin
  Result := False;
  Payload := '';
  if Copy(Text, At, Length(Head)) <> Head then
    Exit;
  First := At + Length(Head);
  Stop := First;
  while (Stop < Length(Text)) and not ((Text[Stop] = #27) and (Text[Stop + 1] = '\')) do
    Inc(Stop);
  if Stop >= Length(Text) then
    Exit;
  Payload := DecodeBase64(Copy(Text, First, Stop - First));
  At := Stop + 2;
  Result := True;
end;

function AllDigits(const Text: AnsiString): Boolean;
var
  I: SizeInt;
begin
  Result := Length(Text) > 0;
  for I := 1 to Length(Text) do
    if not (Text[I] in ['0'..'9']) then
      Result := False;
end;

procedure TestBase64;
begin
  Check(EncodeBase64('') = '', 'encode empty');
  Check(EncodeBase64('f') = 'Zg==', 'encode one byte');
  Check(EncodeBase64('fo') = 'Zm8=', 'encode two bytes');
  Check(EncodeBase64('foo') = 'Zm9v', 'encode three bytes');
  Check(EncodeBase64('foob') = 'Zm9vYg==', 'encode four bytes');
  Check(EncodeBase64('fooba') = 'Zm9vYmE=', 'encode five bytes');
  Check(EncodeBase64('foobar') = 'Zm9vYmFy', 'encode six bytes');
  Check(EncodeBase64('hi') = 'aGk=', 'encode hi');
  Check(EncodeBase64(#$FB#$FF) = '+/8=', 'encode the last two characters of the alphabet');
  Check(DecodeBase64('') = '', 'decode empty');
  Check(DecodeBase64('Zg==') = 'f', 'decode one byte');
  Check(DecodeBase64('Zm8=') = 'fo', 'decode two bytes');
  Check(DecodeBase64('Zm9v') = 'foo', 'decode three bytes');
  Check(DecodeBase64('Zm9vYg==') = 'foob', 'decode four bytes');
  Check(DecodeBase64('Zm9vYmE=') = 'fooba', 'decode five bytes');
  Check(DecodeBase64('Zm9vYmFy') = 'foobar', 'decode six bytes');
  Check(DecodeBase64('SGVsbG8=') = 'Hello', 'decode Hello');
  Check(DecodeBase64('Zm8') = 'fo', 'decode without padding');
  Check(DecodeBase64('Zg') = 'f', 'decode one byte without padding');
  Check(DecodeBase64('+/8=') = #$FB#$FF, 'decode the standard alphabet');
  Check(DecodeBase64('-_8=') = #$FB#$FF, 'decode the URL alphabet');
  Check(DecodeBase64('*A==') = #0, 'a character outside the alphabet counts as 128');
  Check(DecodeBase64(EncodeBase64(#0#1#2#255#254)) = #0#1#2#255#254, 'binary round trip');
end;

procedure TestHooks;
begin
  Check(Assigned(Base64Decode) and Assigned(Base64Encode), 'Base64 hooks set');
  Check(Base64Encode('foo') = 'Zm9v', 'encode hook');
  Check(Base64Decode('Zm9v') = 'foo', 'decode hook');
  Check(Assigned(CpFromUtf8) and Assigned(CpPrintableFromUtf8), 'code page hooks set');
  Check(CpFromUtf8('A') = 65, 'code page of A');
  Check(CpFromUtf8(#$C3#$A9) = $82, 'code page of e acute');
  Check(CpFromUtf8(#$E2#$98#$BA) = 1, 'code page of the smiling face');
  Check(CpPrintableFromUtf8(#$E2#$98#$BA) = 0, 'a control position is not printable');
  Check(CpPrintableFromUtf8(#$C3#$A9) = $82, 'printable e acute');
  Check(CpFromUtf8(#$E4#$B8#$AD) = 0, 'a character that is not in the code page');
  Check(Far2lEnableSeq = #27'_far2l1'#27'\', 'far2l enable sequence');
  Check(Far2lDisableSeq = #27'_far2l0'#27'\', 'far2l disable sequence');
end;

procedure TestModes;
var
  Term, Middle: string;
  HasTerm: Boolean;
begin
  OpenPipe;
  TTermIO.MouseOn(Con);
  Check(DrainPipe = #27'[?1001s'#27'[?1000h'#27'[?1002h'#27'[?1006h', 'mouse on');
  TTermIO.MouseOff(Con);
  Check(DrainPipe = #27'[?1006l'#27'[?1002l'#27'[?1000l'#27'[?1001r', 'mouse off');
  TTermIO.KeyModsOff(Con);
  Check(DrainPipe = #27'_far2l0'#27'\'#27'[?9001l'#27'[<u'#27'[>4m'#27'[?2004l'#27'[?2004r'#27'[?1036r',
    'key modes off');
  HasTerm := EnvLookup('TERM', Term);
  if not HasTerm then
    Middle := ''
  else if (Pos('alacritty', Term) > 0) or (Pos('foot', Term) > 0) then
    Middle := #27']52;;?'#7
  else
    Middle := KeyModsQuery;
  TTermIO.KeyModsOn(Con);
  Check(DrainPipe = KeyModsHead + Middle + KeyModsTail, 'key modes on');
  Check(KeyModsOnSequence(False, '') = KeyModsHead + KeyModsTail, 'key modes on without TERM');
  Check(KeyModsOnSequence(True, 'xterm') = KeyModsHead + KeyModsQuery + KeyModsTail, 'key modes on for xterm');
  Check(KeyModsOnSequence(True, 'foot') = KeyModsHead + #27']52;;?'#7 + KeyModsTail, 'key modes on for foot');
  Check(KeyModsOnSequence(True, 'alacritty') = KeyModsHead + #27']52;;?'#7 + KeyModsTail,
    'key modes on for alacritty');
  ClosePipe;
end;

procedure TestNormalize;
var
  KD: TKeyDownEvent;
begin
  FillChar(KD, SizeOf(KD), 0);
  KD.KeyCode := kbRight;
  KD.ControlKeyState := kbLeftCtrl;
  TTermIO.NormalizeKey(KD);
  Check(KD.KeyCode = kbCtrlRight, 'Ctrl+Right');
  Check((KD.ControlKeyState and kbCtrlShift) <> 0, 'Ctrl state kept');
  FillChar(KD, SizeOf(KD), 0);
  KD.KeyCode := kbTab;
  KD.ControlKeyState := kbShift;
  TTermIO.NormalizeKey(KD);
  Check(KD.KeyCode = kbShiftTab, 'Shift+Tab');
  FillChar(KD, SizeOf(KD), 0);
  KD.KeyCode := kbUp;
  TTermIO.NormalizeKey(KD);
  Check(KD.KeyCode = kbUp, 'Up without modifiers');
end;

procedure TestEscapeKeys;
begin
  ClearState;
  Check(ParseBytes('a') = Rejected, 'a plain character is rejected');
  Check(ParseBytes('') = Rejected, 'no input is rejected');
  Check(ParseBytes(Esc) = Rejected, 'a lone ESC is rejected');
  ExpectKey(#27'[A', kbUp, 'CSI A');
  Check(Ev.KeyDown.ControlKeyState = 0, 'CSI A has no modifiers');
  ExpectKey(#27'[B', kbDown, 'CSI B');
  ExpectKey(#27'[H', kbHome, 'CSI H');
  ExpectKey(#27'[1;5C', kbCtrlRight, 'CSI 1;5 C');
  Check((Ev.KeyDown.ControlKeyState and kbCtrlShift) <> 0, 'CSI 1;5 C has Ctrl');
  ExpectKey(#27'[1;3D', kbAltLeft, 'CSI 1;3 D');
  Check((Ev.KeyDown.ControlKeyState and kbAltShift) <> 0, 'CSI 1;3 D has Alt');
  ExpectKey(#27'[1;2P', kbShiftF1, 'CSI 1;2 P');
  Check((Ev.KeyDown.ControlKeyState and kbShift) <> 0, 'CSI 1;2 P has Shift');
  ExpectKey(#27'[1P', kbF1, 'CSI 1 P');
  ExpectKey(#27'[Z', kbTab, 'CSI Z');
  ExpectKey(#27'[1Z', kbTab, 'CSI 1 Z');
  ExpectKey(#27'[1;2Z', kbShiftTab, 'CSI 1;2 Z');
  ExpectKey(#27'[3~', kbDel, 'CSI 3 ~');
  ExpectKey(#27'[2~', kbIns, 'CSI 2 ~');
  ExpectKey(#27'[5~', kbPgUp, 'CSI 5 ~');
  ExpectKey(#27'[15~', kbF5, 'CSI 15 ~');
  ExpectKey(#27'[23~', kbShiftF1, 'CSI 23 ~');
  Check(Ev.KeyDown.ControlKeyState = kbShift, 'CSI 23 ~ has Shift');
  ExpectKey(#27'[34~', kbShiftF10, 'CSI 34 ~');
  ExpectKey(#27'[5;3~', kbAltPgUp, 'CSI 5;3 ~');
  ExpectKey(#27'[15;5~', kbCtrlF5, 'CSI 15;5 ~');
  ExpectKey(#27'[27;5;97~', kbCtrlA, 'modifyOtherKeys Ctrl+A');
  ClearState;
  Check(ParseBytes(#27'[99~') = Rejected, 'unknown CSI ~ number');
  Check(ParseBytes(#27'[1;2;3;4;5;6;7X') = Rejected, 'a CSI longer than supported is rejected');
  ExpectKey(#27#27'[A', kbAltUp, 'ESC ESC CSI A');
  Check((Ev.KeyDown.ControlKeyState and kbAltShift) <> 0, 'ESC ESC CSI A has Alt');
end;

procedure TestSS3;
begin
  ExpectKey(#27'O5P', kbCtrlF1, 'SS3 5 P');
  ExpectKey(#27'O3Q', kbAltF2, 'SS3 3 Q');
  ExpectKey(#27'O2A', kbUp, 'SS3 2 A');
  Check((Ev.KeyDown.ControlKeyState and kbShift) <> 0, 'SS3 2 A has Shift');
  ClearState;
  Check(ParseBytes(#27'OP') = Rejected, 'SS3 without a number is rejected');
  Check(ParseBytes(#27'O1y') = Accepted, 'SS3 keypad letter');
  Check(Ev.KeyDown.KeyCode = kbPgUp, 'SS3 1 y is Page Up');
  Check(ParseBytes(#27'O5!') = Rejected, 'SS3 with an unknown letter is rejected');
end;

procedure TestKitty;
begin
  ClearState;
  Check(ParseBytes(#27'[97u') = Accepted, 'kitty a: accepted');
  Check(Ev.What = evKeyDown, 'kitty a: key event');
  Check(Ev.KeyDown.KeyCode = 97, 'kitty a: key code');
  Check((Ev.KeyDown.TextLength = 1) and (Ev.KeyDown.Text[0] = 97), 'kitty a: text');
  Check(Ev.KeyDown.ControlKeyState = 0, 'kitty a: no modifiers');
  ExpectKey(#27'[97;5u', kbCtrlA, 'kitty Ctrl+a');
  Check(Ev.KeyDown.ControlKeyState = kbLeftCtrl, 'kitty Ctrl+a: state');
  ExpectKey(#27'[13u', kbEnter, 'kitty Enter');
  ExpectKey(#27'[127u', kbBack, 'kitty Backspace');
  ExpectKey(#27'[57417u', kbLeft, 'kitty keypad left');
  ClearState;
  Check(ParseBytes(#27'[97;1:3u') = Ignored, 'kitty release is ignored');
  Check(ParseBytes(#27'[97;1:2u') = Ignored, 'kitty repeat is ignored');
  Check(ParseBytes(#27'[97;1:1u') = Accepted, 'kitty press with an event type is accepted');
  Check(ParseBytes(#27'[97:65;2u') = Accepted, 'kitty shifted: accepted');
  Check(Ev.KeyDown.KeyCode = Ord('A'), 'kitty shifted: key code');
  Check((Ev.KeyDown.TextLength = 1) and (Ev.KeyDown.Text[0] = 65), 'kitty shifted: text');
  Check((Ev.KeyDown.ControlKeyState and kbShift) <> 0, 'kitty shifted: Shift');
  Check(ParseBytes(#27'[1092::97;5u') = Accepted, 'kitty base layout: accepted');
  Check(Ev.KeyDown.KeyCode = kbCtrlA, 'kitty base layout: Ctrl+A');
  Check(Ev.KeyDown.TextLength = 2, 'kitty base layout: the text stays');
  Check(ParseBytes(#27'[233u') = Accepted, 'kitty e acute: accepted');
  Check(Ev.KeyDown.TextLength = 2, 'kitty e acute: two bytes of text');
  Check((Ev.KeyDown.Text[0] = $C3) and (Ev.KeyDown.Text[1] = $A9), 'kitty e acute: text');
  Check(Ev.KeyDown.CharScan.CharCode = $82, 'kitty e acute: code page character');
  Check(ParseBytes(#27'[57344u') = Ignored, 'kitty private use is ignored');
  Check(ParseBytes(#27'[u') = Ignored, 'kitty without a key is ignored');
end;

procedure TestMouse;
begin
  ClearState;
  Check(ParseBytes(#27'[M +&') = Accepted, 'X10 press: accepted');
  Check(Ev.What = evMouse, 'X10 press: mouse event');
  Check((Ev.Mouse.Where.X = 10) and (Ev.Mouse.Where.Y = 5), 'X10 press: position');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'X10 press: left button');
  Check(St.Buttons = mbLeftButton, 'X10 press: state');
  Check(ParseBytes(#27'[M!+&') = Accepted, 'X10 middle press: accepted');
  Check(Ev.Mouse.Buttons = (mbLeftButton or mbMiddleButton), 'X10 buttons add up');
  Check(ParseBytes(#27'[M#+&') = Accepted, 'X10 release: accepted');
  Check(Ev.Mouse.Buttons = 0, 'X10 release clears the buttons');
  Check(ParseBytes(#27'[M"+&') = Accepted, 'X10 right press: accepted');
  Check(Ev.Mouse.Buttons = mbRightButton, 'X10 right button');
  Check(ParseBytes(#27'[M`+&') = Accepted, 'X10 wheel up: accepted');
  Check(Ev.Mouse.Wheel = mwUp, 'X10 wheel up');
  Check(ParseBytes(#27'[Ma+&') = Accepted, 'X10 wheel down: accepted');
  Check(Ev.Mouse.Wheel = mwDown, 'X10 wheel down');
  ClearState;
  Check(ParseBytes(#27'[M0+&') = Accepted, 'X10 Ctrl press: accepted');
  Check(Ev.Mouse.ControlKeyState = kbLeftCtrl, 'X10 Ctrl state');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'X10 Ctrl press: left button');
  ClearState;
  Check(ParseBytes(#27'[M(+&') = Accepted, 'X10 Alt press: accepted');
  Check(Ev.Mouse.ControlKeyState = kbLeftAlt, 'X10 Alt state');
  Check(ParseBytes(#27'[M +'#10) = Accepted, 'X10 overflowed row: accepted');
  Check((Ev.Mouse.Where.X = 10) and (Ev.Mouse.Where.Y = 233), 'X10 overflowed row: position');
  Check(ParseBytes(#27'[M') = Ignored, 'X10 without bytes is ignored');
  Check(ParseBytes(#27'[M +') = Ignored, 'X10 without the row is ignored');

  ClearState;
  Check(ParseBytes(#27'[<0;11;6M') = Accepted, 'SGR press: accepted');
  Check(Ev.What = evMouse, 'SGR press: mouse event');
  Check((Ev.Mouse.Where.X = 10) and (Ev.Mouse.Where.Y = 5), 'SGR press: position');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'SGR press: left button');
  Check(ParseBytes(#27'[<2;1;1M') = Accepted, 'SGR right press: accepted');
  Check(Ev.Mouse.Buttons = (mbLeftButton or mbRightButton), 'SGR buttons add up');
  Check(ParseBytes(#27'[<0;1;1m') = Accepted, 'SGR release: accepted');
  Check(Ev.Mouse.Buttons = mbRightButton, 'SGR release clears one button');
  Check(ParseBytes(#27'[<2;1;1m') = Accepted, 'SGR right release: accepted');
  Check(Ev.Mouse.Buttons = 0, 'SGR release clears the last button');
  Check(ParseBytes(#27'[<65;3;4M') = Accepted, 'SGR wheel: accepted');
  Check(Ev.Mouse.Wheel = mwDown, 'SGR wheel down');
  Check((Ev.Mouse.Where.X = 2) and (Ev.Mouse.Where.Y = 3), 'SGR wheel position');
  Check(ParseBytes(#27'[<66;1;1M') = Accepted, 'SGR wheel left: accepted');
  Check(Ev.Mouse.Wheel = mwLeft, 'SGR wheel left');
  Check(ParseBytes(#27'[<67;1;1M') = Accepted, 'SGR wheel right: accepted');
  Check(Ev.Mouse.Wheel = mwRight, 'SGR wheel right');
  Check(ParseBytes(#27'[<0;-3;0M') = Accepted, 'SGR negative position: accepted');
  Check((Ev.Mouse.Where.X = 0) and (Ev.Mouse.Where.Y = 0), 'SGR negative position is clamped');
  ClearState;
  Check(ParseBytes(#27'[<40;1;1M') = Accepted, 'SGR Alt drag: accepted');
  Check(Ev.Mouse.ControlKeyState = kbLeftAlt, 'SGR Alt state');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'SGR Alt drag: left button');
  Check(ParseBytes(#27'[<48;1;1M') = Accepted, 'SGR Ctrl press: accepted');
  Check(Ev.Mouse.ControlKeyState = kbLeftCtrl, 'SGR Ctrl state');
  Check(ParseBytes(#27'[<x') = Ignored, 'SGR without a number is ignored');
  Check(ParseBytes(#27'[<0;1;1X') = Ignored, 'SGR with a bad terminator is ignored');
  Check(ParseBytes(#27'[<0;1M') = Ignored, 'SGR without the row is ignored');
end;

procedure TestPasteBrackets;
begin
  ClearState;
  Check(ParseBytes(#27'[200~') = Ignored, 'paste start is ignored');
  Check(St.BracketedPaste, 'paste start sets the state');
  Check(ParseBytes(#27'[201~') = Ignored, 'paste end is ignored');
  Check(not St.BracketedPaste, 'paste end clears the state');
end;

procedure TestReplies;
begin
  ClearState;
  Check(ParseBytes(#27'[24;80R') = Ignored, 'CPR is ignored');
  Check(St.GotDsrResponse, 'CPR is noted');
  ClearState;
  Check(ParseBytes(#27'[24R') = Rejected, 'a CPR without a column is rejected');
  Check(not St.GotDsrResponse, 'a bad CPR is not noted');

  ClearState;
  Check(ParseBytes(#27'P0+r'#27'\') = Ignored, 'DCS is ignored');
  Check(not St.HasFullOsc52, 'a DCS without the capability');
  Check(ParseBytes(#27'P1+r726561642d636c6970626f617264'#27'\') = Ignored, 'DCS with the capability is ignored');
  Check(St.HasFullOsc52, 'a DCS with the capability');

  ClearState;
  Check(ParseBytes(#27']60;allowWindowOps=1'#7) = Ignored, 'OSC 60 is ignored');
  Check(St.HasFullOsc52, 'OSC 60 with allowWindowOps');
  ClearState;
  Check(ParseBytes(#27']60;other'#7) = Ignored, 'OSC 60 without allowWindowOps');
  Check(not St.HasFullOsc52, 'OSC 60 without allowWindowOps sets nothing');

  ClearState;
  St.PutPaste := @CollectPaste;
  PasteCalls := 0;
  Check(ParseBytes(#27']52;c;?'#7) = Ignored, 'OSC 52 answer is ignored');
  Check(St.HasFullOsc52, 'the first OSC 52 answer marks the support');
  Check(PasteCalls = 0, 'the first OSC 52 answer is not a paste');
  Check(ParseBytes(#27']52;c;SGVsbG8='#27'\') = Ignored, 'OSC 52 paste is ignored');
  Check(PasteCalls = 1, 'OSC 52 paste is delivered');
  Check(LastPaste = 'Hello', 'OSC 52 paste text');
  Check(ParseBytes(#27']52;c;Zm9v'#7) = Ignored, 'OSC 52 paste with BEL is ignored');
  Check(LastPaste = 'foo', 'OSC 52 paste text with BEL');
  Check(ParseBytes(#27']52;c'#7) = Ignored, 'OSC 52 without a second semicolon is ignored');
  Check(PasteCalls = 2, 'OSC 52 without a second semicolon is not a paste');
  St.PutPaste := nil;
  Check(ParseBytes(#27']52;c;Zm9v'#7) = Ignored, 'OSC 52 paste without a receiver');
  Check(PasteCalls = 2, 'no receiver, no delivery');
end;

procedure TestFar2lInput;
var
  Bytes: AnsiString;
begin
  ClearState;
  Check(ParseBytes(#27'_far2lok'#27'\') = Ignored, 'far2l answer ok is ignored');
  Check(St.Far2l.Enabled, 'far2l answer ok enables the extension');

  ClearState;
  St.PutPaste := @CollectPaste;
  PasteCalls := 0;
  Bytes := 'Hello'#0 + Le32(6) + #$A0;
  Check(ParseBytes(#27'_far2l' + EncodeBase64(Bytes) + #27'\') = Ignored, 'far2l clipboard answer is ignored');
  Check(PasteCalls = 1, 'far2l clipboard answer is delivered');
  Check(LastPaste = 'Hello', 'far2l clipboard text without its terminator');
  Bytes := 'Hello' + Le32(6) + #$A0;
  Check(ParseBytes(#27'_far2l' + EncodeBase64(Bytes) + #7) = Ignored, 'far2l answer with a short text');
  Check(PasteCalls = 1, 'a text shorter than its size is not delivered');
  Bytes := 'Hi' + Le32(2) + #$A1;
  Check(ParseBytes(#27'_far2l' + EncodeBase64(Bytes) + #7) = Ignored, 'far2l answer of another request');
  Check(PasteCalls = 1, 'another request is not delivered');

  ClearState;
  Bytes := Le16(1) + Le16($41) + Le16($1E) + Le32(0) + Le32($61) + 'K';
  Check(ParseBytes(#27'_f2l' + EncodeBase64(Bytes) + #7) = Accepted, 'far2l key: accepted');
  Check(Ev.What = evKeyDown, 'far2l key: key event');
  Check((Ev.KeyDown.TextLength = 1) and (Ev.KeyDown.Text[0] = 97), 'far2l key: text');
  Bytes := Le16(5) + Le16(3) + Le32(1) + Le32(0) + Le32(0) + 'M';
  Check(ParseBytes(#27'_f2l' + EncodeBase64(Bytes) + #7) = Accepted, 'far2l mouse: accepted');
  Check(Ev.What = evMouse, 'far2l mouse: mouse event');
  Check((Ev.Mouse.Where.X = 5) and (Ev.Mouse.Where.Y = 3), 'far2l mouse: position');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'far2l mouse: button');
  Check(ParseBytes(#27'_f2l' + EncodeBase64('short') + #7) = Ignored, 'far2l input of another size is ignored');
  Check(ParseBytes(#27'_f2l' + #7) = Ignored, 'empty far2l input is ignored');
end;

function Wrapped(VirtualKey, ScanCode, Code: Integer; Down: Integer): AnsiString;
begin
  Result := #27'[' + IntToStr(VirtualKey) + ';' + IntToStr(ScanCode) + ';' + IntToStr(Code) + ';' +
    IntToStr(Down) + ';0;1_';
end;

procedure TestWin32Input;
begin
  ClearState;
  Check(ParseBytes(Wrapped(65, 30, 97, 1)) = Accepted, 'win32 key: accepted');
  Check(Ev.What = evKeyDown, 'win32 key: key event');
  Check((Ev.KeyDown.TextLength = 1) and (Ev.KeyDown.Text[0] = 97), 'win32 key: text');
  Check(Ev.KeyDown.CharScan.ScanCode = 30, 'win32 key: scan code');
  Check(ParseBytes(Wrapped(65, 30, 97, 0)) = Ignored, 'win32 key release is ignored');
  Check(ParseBytes(Wrapped(0, 0, 27, 1) + Wrapped(0, 0, 91, 1) + Wrapped(0, 0, 65, 1)) = Accepted,
    'wrapped escape sequence: accepted');
  Check(Ev.What = evKeyDown, 'wrapped escape sequence: key event');
  Check(Ev.KeyDown.KeyCode = kbUp, 'wrapped escape sequence: Up');
  Check(ParseBytes(Wrapped(0, 0, 27, 1) + Wrapped(0, 0, 91, 1) + Wrapped(0, 0, 33, 1)) = Ignored,
    'a wrapped sequence that fails is ignored');
  Check(ParseBytes(Wrapped(0, 0, 27, 1)) = Ignored, 'a wrapped ESC alone is ignored');
end;

procedure TestReadUntil;
var
  Src: TByteSource;
  Buf: TGetChBuf;
begin
  Src := TByteSource.Create('abc'#7'tail');
  try
    Buf := TGetChBuf.Create(Src);
    Check(TTermIO.ReadUntilBelOrSt(Buf) = 'abc', 'read until BEL');
    Check(Src.Get = Ord('t'), 'the input after BEL stays');
  finally
    Src.Free;
  end;
  Src := TByteSource.Create('abc'#27'\xy');
  try
    Buf := TGetChBuf.Create(Src);
    Check(TTermIO.ReadUntilBelOrSt(Buf) = 'abc', 'read until ST');
    Check(Src.Get = Ord('x'), 'the input after ST stays');
  finally
    Src.Free;
  end;
  Src := TByteSource.Create('xyz');
  try
    Buf := TGetChBuf.Create(Src);
    Check(TTermIO.ReadUntilBelOrSt(Buf) = 'xyz', 'read until the end of the input');
  finally
    Src.Free;
  end;
  Src := TByteSource.Create('ab'#0'cd'#7);
  try
    Buf := TGetChBuf.Create(Src);
    Check(TTermIO.ReadUntilBelOrSt(Buf) = 'ab', 'the text ends at its first zero');
  finally
    Src.Free;
  end;
end;

procedure TestFar2lClipboard;
var
  Output, P1, P2, P3: AnsiString;
  At: SizeInt;
  Accepted3: Boolean;
begin
  OpenPipe;
  ClearState;
  Check(not SetFar2lClipboard(Con, 'hi', St), 'far2l set clipboard while disabled');
  Check(DrainPipe = '', 'far2l set clipboard while disabled writes nothing');
  Check(not RequestFar2lClipboard(Con, St), 'far2l request clipboard while disabled');
  Check(DrainPipe = '', 'far2l request clipboard while disabled writes nothing');

  St.Far2l.Enabled := True;
  Check(SetFar2lClipboard(Con, 'hi', St), 'far2l set clipboard');
  Output := DrainPipe;
  At := 1;
  Check(NextRequest(Output, At, P1), 'far2l set: first request');
  Check(NextRequest(Output, At, P2), 'far2l set: second request');
  Accepted3 := NextRequest(Output, At, P3);
  Check(Accepted3, 'far2l set: third request');
  Check(At = Length(Output) + 1, 'far2l set: nothing else');
  Check(Length(P1) = 39, 'far2l open: length');
  Check(AllDigits(Copy(P1, 1, 32)), 'far2l open: the client id is made of digits');
  Check(Copy(P1, 33, 7) = #32#0#0#0'oc'#0, 'far2l open: size, name and no answer');
  Check(P2 = 'hi'#0#3#0#0#0#1#0#0#0'sc'#0, 'far2l set data');
  Check(P3 = 'cc'#0, 'far2l close');

  Check(RequestFar2lClipboard(Con, St), 'far2l request clipboard');
  Output := DrainPipe;
  At := 1;
  Check(NextRequest(Output, At, P1), 'far2l request: first request');
  Check(NextRequest(Output, At, P2), 'far2l request: second request');
  Check(NextRequest(Output, At, P3), 'far2l request: third request');
  Check(At = Length(Output) + 1, 'far2l request: nothing else');
  Check(Copy(P1, 1, 32) <> '', 'far2l request: client id present');
  Check(Length(P1) = 39, 'far2l request open: length');
  Check(P2 = #1#0#0#0'gc'#$A0, 'far2l get data');
  Check(P3 = 'cc'#0, 'far2l request close');

  Check(SetFar2lClipboard(Con, '', St), 'far2l set an empty text');
  Output := DrainPipe;
  At := 1;
  Check(NextRequest(Output, At, P1) and NextRequest(Output, At, P2), 'far2l empty text: requests');
  Check(P2 = #0#1#0#0#0#1#0#0#0'sc'#0, 'far2l empty text data');
  ClosePipe;
end;

procedure TestClipboard;
var
  Output: AnsiString;
begin
  OpenPipe;
  ClearState;
  Check(not TTermIO.SetClipboardText(Con, 'hi', St), 'set clipboard without support');
  Check(DrainPipe = #27']52;;aGk='#7, 'OSC 52 is written even without support');
  St.HasFullOsc52 := True;
  Check(TTermIO.SetClipboardText(Con, 'hi', St), 'set clipboard with OSC 52');
  Check(DrainPipe = #27']52;;aGk='#7, 'OSC 52 text');
  Check(TTermIO.SetClipboardText(Con, '', St), 'set an empty clipboard');
  Check(DrainPipe = #27']52;;'#7, 'OSC 52 empty text');
  St.Far2l.Enabled := True;
  Check(TTermIO.SetClipboardText(Con, 'hi', St), 'set clipboard with far2l');
  Output := DrainPipe;
  Check(Copy(Output, 1, 8) = #27'_far2l:', 'far2l takes the text');
  Check(Pos(#27']52', Output) = 0, 'OSC 52 is not written when far2l took the text');

  ClearState;
  PasteCalls := 0;
  Check(not TTermIO.RequestClipboardText(Con, @CollectPaste, St), 'request clipboard without support');
  Check(DrainPipe = '', 'nothing is written without support');
  Check(Assigned(St.PutPaste), 'the receiver is remembered');
  St.HasFullOsc52 := True;
  Check(TTermIO.RequestClipboardText(Con, @CollectPaste, St), 'request clipboard with OSC 52');
  Check(DrainPipe = #27']52;;?'#7, 'OSC 52 request');
  St.Far2l.Enabled := True;
  Check(TTermIO.RequestClipboardText(Con, @CollectPaste, St), 'request clipboard with far2l');
  Output := DrainPipe;
  Check(Copy(Output, 1, 8) = #27'_far2l:', 'far2l takes the request');
  Check(Pos(#27']52', Output) = 0, 'OSC 52 is not requested when far2l took the request');
  ParseBytes(#27'_far2l' + EncodeBase64('ok'#0 + Le32(3) + #$A0) + #7);
  Check(PasteCalls = 1, 'the remembered receiver gets the answer');
  Check(LastPaste = 'ok', 'the answer text');
  ClosePipe;
end;

procedure TestConsume;
var
  Src: TByteSource;
  Started: QWord;
begin
  OpenPipe;
  ClearState;
  Src := TByteSource.Create('xy'#27'[A'#27'[24;80Rleft');
  try
    TTermIO.ConsumeUnprocessedInput(Con, Src, St);
    Check(St.GotDsrResponse, 'the response to the DSR request is read');
    Check(DrainPipe = #27'[6n', 'the DSR request is written');
    Check(Src.Get = Ord('l'), 'the input after the response stays');
  finally
    Src.Free;
  end;
  ClearState;
  St.GotDsrResponse := True;
  Src := TByteSource.Create('');
  try
    Started := GetTickCount64;
    TTermIO.ConsumeUnprocessedInput(Con, Src, St);
    Check(not St.GotDsrResponse, 'the flag is cleared before the wait');
    Check(GetTickCount64 - Started >= 150, 'the wait lasts about 200 ms');
    Check(DrainPipe = #27'[6n', 'the DSR request is written once');
  finally
    Src.Free;
  end;
  ClosePipe;
end;

begin
  TestBase64;
  TestHooks;
  TestModes;
  TestNormalize;
  TestEscapeKeys;
  TestSS3;
  TestKitty;
  TestMouse;
  TestPasteBrackets;
  TestReplies;
  TestFar2lInput;
  TestWin32Input;
  TestReadUntil;
  TestFar2lClipboard;
  TestClipboard;
  TestConsume;
  Done;
end.
