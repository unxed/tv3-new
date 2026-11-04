{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h, include/tvision/config.h, include/tvision/internal/termio.h,
  source/platform/termio.cpp, source/platform/far2l.cpp,
  include/tvision/internal/win32con.h, source/platform/win32con.cpp
  See COPYRIGHT.magiblot. }
program t_events;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  SysUtils, TvGeom, TvKeys, TvUtf8, TvEvents;

{$I testlib.inc}

type
  { Gives the bytes of a string; Unget takes the last byte back. }
  TStringGetter = class(TInputGetter)
  public
    Data: string;
    Index: Integer;
    constructor Create(const AData: string);
    function Get: Integer; override;
    procedure Unget(Key: Integer); override;
  end;

constructor TStringGetter.Create(const AData: string);
begin
  inherited Create;
  Data := AData;
  Index := 0;
end;

function TStringGetter.Get: Integer;
begin
  if Index < Length(Data) then
  begin
    Result := Ord(Data[Index + 1]);
    Inc(Index);
  end
  else
    Result := -1;
end;

procedure TStringGetter.Unget(Key: Integer);
begin
  if Index > 0 then
    Dec(Index);
end;

var
  Written: string;
  Pasted: string;
  FakePayload: string;
  LastRest: Integer;

procedure Capture(const Text: string);
begin
  Written := Written + Text;
end;

procedure CapturePaste(const Text: string);
begin
  Pasted := Text;
end;

function FakeDecode(const S: string): string;
begin
  if FakePayload <> '' then
    Result := FakePayload
  else
    Result := 'D(' + S + ')';
end;

function FakeEncode(const S: string): string;
begin
  Result := 'E(' + S + ')';
end;

function HookCp(const Text: string): Byte;
begin
  if Text = #$D1#$91 then
    Result := $F1
  else
    Result := 0;
end;

function NewState: TInputState;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

{ Parses S as the input of a terminal; LastRest is the number of bytes left unread. }
function Parse(const S: string; var Ev: TEvent; var State: TInputState): TParseResult;
var
  G: TStringGetter;
  Buf: TGetChBuf;
begin
  G := TStringGetter.Create(S);
  try
    Buf := TGetChBuf.Create(G);
    FillChar(Ev, SizeOf(Ev), 0);
    Result := ParseEvent(Buf, Ev, State);
    LastRest := Length(S) - G.Index;
  finally
    G.Free;
  end;
end;

{ Checks a key event: the result, the key code, the state of the control keys and the text. }
procedure CheckKey(const S: string; ACode, AMods: Word; const AText: string; const Name: string);
var
  Ev: TEvent;
  State: TInputState;
begin
  State := NewState;
  Check(Parse(S, Ev, State) = Accepted, Name + ': accepted');
  Check(Ev.What = evKeyDown, Name + ': key event');
  Check(Ev.KeyDown.KeyCode = ACode, Name + ': key code');
  Check(Ev.KeyDown.ControlKeyState = AMods, Name + ': modifiers');
  Check(Ev.KeyDown.GetText = AText, Name + ': text');
end;

procedure CheckResult(const S: string; AResult: TParseResult; const Name: string);
var
  Ev: TEvent;
  State: TInputState;
begin
  State := NewState;
  Check(Parse(S, Ev, State) = AResult, Name);
end;

var
  Ev: TEvent;
  State: TInputState;
  G: TStringGetter;
  Buf: TGetChBuf;
  Csi: TCSIData;
  Num: Cardinal;
  Int: Integer;
  S: string;
  I: Integer;
  KVk, KScan: Word;
  KCh, KMods: Cardinal;
  KeyDown: TKeyDownEvent;

{ Sets the fields of a key record, which the next conversion takes. }
procedure SetKey(VK, Scan: Word; Ch, Mods: Cardinal);
begin
  KVk := VK;
  KScan := Scan;
  KCh := Ch;
  KMods := Mods;
end;

function ConvKey: Boolean;
begin
  Result := GetWin32Key(KVk, KScan, KCh, KMods, Ev, State);
end;

begin
  { Constants }
  Check(evMouseDown = $0001, 'evMouseDown');
  Check(evMouseUp = $0002, 'evMouseUp');
  Check(evMouseMove = $0004, 'evMouseMove');
  Check(evMouseAuto = $0008, 'evMouseAuto');
  Check(evMouseWheel = $0020, 'evMouseWheel');
  Check(evKeyDown = $0010, 'evKeyDown');
  Check(evCommand = $0100, 'evCommand');
  Check(evBroadcast = $0200, 'evBroadcast');
  Check(evNothing = $0000, 'evNothing');
  Check(evMouse = (evMouseDown or evMouseUp or evMouseMove or evMouseAuto or evMouseWheel), 'evMouse');
  Check(evKeyboard = evKeyDown, 'evKeyboard');
  Check(evMessage = (evCommand or evBroadcast or $FC00), 'evMessage');
  Check(mbLeftButton = 1, 'mbLeftButton');
  Check(mbRightButton = 2, 'mbRightButton');
  Check(mbMiddleButton = 4, 'mbMiddleButton');
  Check(mwUp = 1, 'mwUp');
  Check(mwDown = 2, 'mwDown');
  Check(mwLeft = 4, 'mwLeft');
  Check(mwRight = 8, 'mwRight');
  Check(meMouseMoved = 1, 'meMouseMoved');
  Check(meDoubleClick = 2, 'meDoubleClick');
  Check(meTripleClick = 4, 'meTripleClick');
  Check(minPasteEventCount = 3, 'minPasteEventCount');

  { The members of the unions share their storage }
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.KeyDown.KeyCode := $1E41;
  Check(Ev.KeyDown.CharScan.CharCode = $41, 'charCode is the low byte of keyCode');
  Check(Ev.KeyDown.CharScan.ScanCode = $1E, 'scanCode is the high byte of keyCode');
  Ev.KeyDown.CharScan.CharCode := $42;
  Check(Ev.KeyDown.KeyCode = $1E42, 'setting charCode changes keyCode');
  Ev.KeyDown.CharScan.ScanCode := $3B;
  Check(Ev.KeyDown.KeyCode = $3B42, 'setting scanCode changes keyCode');

  FillChar(Ev, SizeOf(Ev), 0);
  Ev.What := evCommand;
  Ev.Message.Command := 7;
  Ev.Message.InfoLong := $12345678;
  Check(Ev.Message.InfoWord = $5678, 'infoWord is the low word of infoLong');
  Check(Ev.Message.InfoByte = $78, 'infoByte is the low byte of infoLong');
  Ev.Message.InfoInt := -2;
  Check(Ev.Message.InfoWord = $FFFE, 'infoInt and infoWord share storage');
  Ev.Message.InfoChar := 'x';
  Check(Ev.Message.InfoByte = Ord('x'), 'infoChar and infoByte share storage');
  Ev.Message.InfoPtr := nil;
  Check(Ev.Message.InfoLong = 0, 'a null infoPtr clears infoLong');
  Check(Ev.Message.Command = 7, 'the command is kept');

  { Text and key of a key event }
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  Check(KeyDown.GetText = '', 'no text');
  KeyDown.Text[0] := Ord('a');
  KeyDown.Text[1] := Ord('b');
  KeyDown.Text[2] := Ord('c');
  KeyDown.TextLength := 2;
  Check(KeyDown.GetText = 'ab', 'the text has TextLength bytes');
  KeyDown.KeyCode := kbF1;
  KeyDown.ControlKeyState := kbShift;
  Check(KeyDown.ToKey = TKey.Create(kbF1, kbShift), 'the key of a key event');

  { GetChBuf }
  G := TStringGetter.Create('ab12x');
  Buf := TGetChBuf.Create(G);
  Check(Buf.Last = -1, 'nothing read yet');
  Check(Buf.Get = Ord('a'), 'Get a');
  Check(Buf.Last = Ord('a'), 'Last is a');
  Check(Buf.Last(1) = -1, 'Last(1) before a second key');
  Check(Buf.Get = Ord('b'), 'Get b');
  Check(Buf.Last(1) = Ord('a'), 'Last(1) is a');
  Buf.Unget;
  Check(G.Index = 1, 'Unget gives the key back');
  Check(Buf.Get = Ord('b'), 'Get b again');
  Check(Buf.GetUnbuffered = Ord('1'), 'GetUnbuffered');
  Check(Buf.Last = Ord('b'), 'GetUnbuffered keeps nothing');
  Buf.Reject;
  Check(G.Index = 1, 'Reject gives back the keys read with Get');
  G.Free;

  G := TStringGetter.Create('123;x');
  Buf := TGetChBuf.Create(G);
  Check(Buf.GetNum(Num), 'GetNum with digits');
  Check(Num = 123, 'GetNum value');
  Check(Buf.Last = Ord(';'), 'GetNum leaves the terminator in Last');
  Buf.Unget;
  Check(G.Get = Ord(';'), 'the terminator can be ungotten');
  G.Free;

  G := TStringGetter.Create('x');
  Buf := TGetChBuf.Create(G);
  Check(not Buf.GetNum(Num), 'GetNum without digits');
  Check(Buf.Last = Ord('x'), 'the key that is not a digit is in Last');
  G.Free;

  G := TStringGetter.Create('');
  Buf := TGetChBuf.Create(G);
  Check(not Buf.GetNum(Num), 'GetNum at the end');
  Check(Buf.Last = -1, 'Last is -1 at the end');
  G.Free;

  G := TStringGetter.Create('-12;');
  Buf := TGetChBuf.Create(G);
  Check(Buf.GetInt(Int), 'GetInt negative');
  Check(Int = -12, 'GetInt value');
  Check(Buf.Last = Ord(';'), 'GetInt leaves the terminator in Last');
  G.Free;

  G := TStringGetter.Create('5');
  Buf := TGetChBuf.Create(G);
  Check(Buf.GetInt(Int) and (Int = 5), 'GetInt up to the end');
  Check(Buf.Last = -1, 'Last is -1 after the digits at the end');
  G.Free;

  G := TStringGetter.Create('-;');
  Buf := TGetChBuf.Create(G);
  Check(not Buf.GetInt(Int), 'GetInt of a sign only');
  G.Free;

  G := TStringGetter.Create('f2lXY');
  Buf := TGetChBuf.Create(G);
  Check(Buf.ReadStr('f2l'), 'ReadStr matches');
  Check(G.Index = 3, 'ReadStr consumes the string');
  Check(Buf.Last = Ord('l'), 'ReadStr leaves the last key');
  G.Free;

  G := TStringGetter.Create('fax');
  Buf := TGetChBuf.Create(G);
  Check(not Buf.ReadStr('f2l'), 'ReadStr does not match');
  Check(G.Index = 0, 'ReadStr gives back what it read');
  Check(not Buf.ReadStr('faxy'), 'ReadStr does not match a longer string');
  Check(G.Index = 0, 'ReadStr gives back what it read at the end');
  Check(Buf.ReadStr('fax'), 'ReadStr matches after a failure');
  G.Free;

  G := TStringGetter.Create(StringOfChar('a', 40));
  Buf := TGetChBuf.Create(G);
  for I := 1 to 31 do
    Buf.Get;
  Check(Buf.Get = -1, 'the buffer holds 31 keys');
  Check(G.Index = 31, 'a full buffer does not read');
  Buf.Reject;
  Check(G.Index = 0, 'Reject gives back all keys');
  G.Free;

  { CSIData }
  G := TStringGetter.Create('123::456;789u');
  Buf := TGetChBuf.Create(G);
  Csi := Default(TCSIData);
  Check(Csi.ReadFrom(Buf), 'CSI is read');
  Check(Csi.Length = 4, 'CSI length');
  Check(Csi.Terminator = 'u', 'CSI terminator');
  Check(Csi.GetValue(0) = 123, 'CSI value 0');
  Check(Csi.GetSeparator(0) = ':', 'CSI separator 0');
  Check(Csi.GetValue(1, 77) = 77, 'CSI missing value gives the default');
  Check(Csi.GetValue(1) = 1, 'CSI default of the default');
  Check(Csi.GetSeparator(1) = ':', 'CSI separator 1');
  Check(Csi.GetValue(2) = 456, 'CSI value 2');
  Check(Csi.GetSeparator(2) = ';', 'CSI separator 2');
  Check(Csi.GetValue(3) = 789, 'CSI value 3');
  Check(Csi.GetSeparator(3) = #0, 'CSI separator after the last value');
  Check(Csi.GetValue(4, 9) = 9, 'CSI value past the end gives the default');
  G.Free;

  G := TStringGetter.Create('A');
  Buf := TGetChBuf.Create(G);
  Csi := Default(TCSIData);
  Check(Csi.ReadFrom(Buf), 'CSI without values');
  Check((Csi.Length = 1) and (Csi.Terminator = 'A'), 'CSI without values: length and terminator');
  Check(Csi.GetValue(0) = 1, 'CSI without values: default');
  G.Free;

  G := TStringGetter.Create('12');
  Buf := TGetChBuf.Create(G);
  Csi := Default(TCSIData);
  Check(not Csi.ReadFrom(Buf), 'CSI that is not complete');
  G.Free;

  G := TStringGetter.Create('1;2;3;4;5;6;7m');
  Buf := TGetChBuf.Create(G);
  Csi := Default(TCSIData);
  Check(not Csi.ReadFrom(Buf), 'CSI that is too long');
  G.Free;

  { ReadUntilBelOrSt }
  G := TStringGetter.Create('abc'#7'def');
  Buf := TGetChBuf.Create(G);
  Check(ReadUntilBelOrSt(Buf) = 'abc', 'up to BEL');
  Check(G.Get = Ord('d'), 'BEL is consumed');
  G.Free;
  G := TStringGetter.Create('ab'#27'\cd');
  Buf := TGetChBuf.Create(G);
  Check(ReadUntilBelOrSt(Buf) = 'ab', 'up to ST');
  Check(G.Get = Ord('c'), 'ST is consumed');
  G.Free;
  G := TStringGetter.Create('ab'#0'cd'#7);
  Buf := TGetChBuf.Create(G);
  Check(ReadUntilBelOrSt(Buf) = 'ab', 'the result ends at a zero byte');
  Check(G.Index = 6, 'the whole input is read');
  G.Free;
  G := TStringGetter.Create('xyz');
  Buf := TGetChBuf.Create(G);
  Check(ReadUntilBelOrSt(Buf) = 'xyz', 'up to the end of the input');
  G.Free;
  G := TStringGetter.Create(#27'\');
  Buf := TGetChBuf.Create(G);
  Check(ReadUntilBelOrSt(Buf) = '', 'ST at the start');
  G.Free;

  { Mouse of X10 }
  State := NewState;
  Check(Parse(#27'[M'#32#43#38, Ev, State) = Accepted, 'X10 press');
  Check(Ev.What = evMouse, 'X10 press: mouse event');
  Check((Ev.Mouse.Where.X = 10) and (Ev.Mouse.Where.Y = 5), 'X10 press: position');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'X10 press: button');
  Check(State.Buttons = mbLeftButton, 'X10 press: state');
  Check(Ev.Mouse.ControlKeyState = 0, 'X10 press: no modifiers');
  Check(LastRest = 0, 'X10 press: all read');
  Check(Parse(#27'[M'#33#43#38, Ev, State) = Accepted, 'X10 middle');
  Check(Ev.Mouse.Buttons = (mbLeftButton or mbMiddleButton), 'X10 middle adds to the state');
  Check(Parse(#27'[M'#34#43#38, Ev, State) = Accepted, 'X10 right');
  Check(Ev.Mouse.Buttons = (mbLeftButton or mbMiddleButton or mbRightButton), 'X10 right adds to the state');
  Check(Parse(#27'[M'#35#43#38, Ev, State) = Accepted, 'X10 release');
  Check((Ev.Mouse.Buttons = 0) and (State.Buttons = 0), 'X10 release clears the buttons');
  Check(Parse(#27'[M'#64#43#38, Ev, State) = Accepted, 'X10 drag');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'X10 drag is the left button');
  State := NewState;
  Check(Parse(#27'[M'#48#43#38, Ev, State) = Accepted, 'X10 with Ctrl');
  Check(Ev.Mouse.ControlKeyState = kbLeftCtrl, 'X10 Ctrl');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'X10 with Ctrl: button');
  Check(Parse(#27'[M'#40#43#38, Ev, State) = Accepted, 'X10 with Alt');
  Check(Ev.Mouse.ControlKeyState = kbLeftAlt, 'X10 Alt');
  State := NewState;
  Check(Parse(#27'[M'#96#43#38, Ev, State) = Accepted, 'X10 wheel up');
  Check(Ev.Mouse.Wheel = mwUp, 'X10 wheel up: wheel');
  Check(Ev.Mouse.Buttons = 0, 'X10 wheel up: no buttons');
  Check(Parse(#27'[M'#97#43#38, Ev, State) = Accepted, 'X10 wheel down');
  Check(Ev.Mouse.Wheel = mwDown, 'X10 wheel down: wheel');
  Check(Parse(#27'[M'#98#43#38, Ev, State) = Accepted, 'X10 wheel left');
  Check(Ev.Mouse.Wheel = mwLeft, 'X10 wheel left: wheel');
  Check(Parse(#27'[M'#99#43#38, Ev, State) = Accepted, 'X10 wheel right');
  Check(Ev.Mouse.Wheel = mwRight, 'X10 wheel right: wheel');
  Check(Parse(#27'[M'#32#1#2, Ev, State) = Accepted, 'X10 wrapped coordinates');
  Check((Ev.Mouse.Where.X = 224) and (Ev.Mouse.Where.Y = 225), 'X10 wrapped coordinates: position');
  Check(Parse(#27'[M'#32#33#33, Ev, State) = Accepted, 'X10 first cell');
  Check((Ev.Mouse.Where.X = 0) and (Ev.Mouse.Where.Y = 0), 'X10 first cell: position');
  CheckResult(#27'[M', Ignored, 'X10 without data is ignored');
  CheckResult(#27'[M'#32#43, Ignored, 'X10 with one coordinate is ignored');
  G := TStringGetter.Create(#0#43#38);
  Buf := TGetChBuf.Create(G);
  State := NewState;
  Check(ParseX10Mouse(Buf, Ev, State) = Rejected, 'X10 with a button below 32 is rejected');
  G.Free;

  { Mouse of SGR }
  State := NewState;
  Check(Parse(#27'[<0;11;6M', Ev, State) = Accepted, 'SGR press');
  Check(Ev.What = evMouse, 'SGR press: mouse event');
  Check((Ev.Mouse.Where.X = 10) and (Ev.Mouse.Where.Y = 5), 'SGR press: position');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'SGR press: button');
  Check(LastRest = 0, 'SGR press: all read');
  Check(Parse(#27'[<2;11;6M', Ev, State) = Accepted, 'SGR right press');
  Check(Ev.Mouse.Buttons = (mbLeftButton or mbRightButton), 'SGR right press adds to the state');
  Check(Parse(#27'[<1;11;6M', Ev, State) = Accepted, 'SGR middle press');
  Check(Ev.Mouse.Buttons = (mbLeftButton or mbRightButton or mbMiddleButton), 'SGR middle press adds to the state');
  Check(Parse(#27'[<0;11;6m', Ev, State) = Accepted, 'SGR release');
  Check(Ev.Mouse.Buttons = (mbRightButton or mbMiddleButton), 'SGR release of the left button');
  Check(Parse(#27'[<2;11;6m', Ev, State) = Accepted, 'SGR release of the right button');
  Check(Ev.Mouse.Buttons = mbMiddleButton, 'SGR release of the right button: state');
  Check(Parse(#27'[<1;11;6m', Ev, State) = Accepted, 'SGR release of the middle button');
  Check(Ev.Mouse.Buttons = 0, 'SGR release of the middle button: state');
  Check(Parse(#27'[<32;3;4M', Ev, State) = Accepted, 'SGR drag');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'SGR drag is the left button');
  Check((Ev.Mouse.Where.X = 2) and (Ev.Mouse.Where.Y = 3), 'SGR drag: position');
  State := NewState;
  Check(Parse(#27'[<64;5;5M', Ev, State) = Accepted, 'SGR wheel up');
  Check((Ev.Mouse.Wheel = mwUp) and (Ev.Mouse.Buttons = 0), 'SGR wheel up: wheel');
  Check(Parse(#27'[<65;5;5M', Ev, State) = Accepted, 'SGR wheel down');
  Check(Ev.Mouse.Wheel = mwDown, 'SGR wheel down: wheel');
  Check(Parse(#27'[<66;5;5M', Ev, State) = Accepted, 'SGR wheel left');
  Check(Ev.Mouse.Wheel = mwLeft, 'SGR wheel left: wheel');
  Check(Parse(#27'[<67;5;5M', Ev, State) = Accepted, 'SGR wheel right');
  Check(Ev.Mouse.Wheel = mwRight, 'SGR wheel right: wheel');
  Check(Parse(#27'[<24;1;1M', Ev, State) = Accepted, 'SGR with Alt and Ctrl');
  Check(Ev.Mouse.ControlKeyState = (kbLeftAlt or kbLeftCtrl), 'SGR Alt and Ctrl');
  Check(Ev.Mouse.Buttons = mbLeftButton, 'SGR with Alt and Ctrl: button');
  State := NewState;
  Check(Parse(#27'[<0;-5;-3M', Ev, State) = Accepted, 'SGR with negative coordinates');
  Check((Ev.Mouse.Where.X = 0) and (Ev.Mouse.Where.Y = 0), 'SGR negative coordinates are clamped');
  Check(Parse(#27'[<0;0;0M', Ev, State) = Accepted, 'SGR with zero coordinates');
  Check((Ev.Mouse.Where.X = 0) and (Ev.Mouse.Where.Y = 0), 'SGR zero coordinates are clamped');
  Check(Parse(#27'[<0;300;200M', Ev, State) = Accepted, 'SGR with large coordinates');
  Check((Ev.Mouse.Where.X = 299) and (Ev.Mouse.Where.Y = 199), 'SGR large coordinates');
  CheckResult(#27'[<0;5M', Ignored, 'SGR without a row is ignored');
  CheckResult(#27'[<0;1;1x', Ignored, 'SGR with another terminator is ignored');
  CheckResult(#27'[<;1;1M', Ignored, 'SGR without a button is ignored');

  { Keys of the CSI }
  CheckKey(#27'[A', kbUp, 0, '', 'Up');
  CheckKey(#27'[B', kbDown, 0, '', 'Down');
  CheckKey(#27'[C', kbRight, 0, '', 'Right');
  CheckKey(#27'[D', kbLeft, 0, '', 'Left');
  CheckKey(#27'[F', kbEnd, 0, '', 'End');
  CheckKey(#27'[H', kbHome, 0, '', 'Home');
  CheckKey(#27'[1;5A', kbCtrlUp, kbLeftCtrl, '', 'Ctrl+Up');
  CheckKey(#27'[1;2A', kbUp, kbShift, '', 'Shift+Up');
  CheckKey(#27'[1;3A', kbAltUp, kbLeftAlt, '', 'Alt+Up');
  CheckKey(#27'[1;5P', kbCtrlF1, kbLeftCtrl, '', 'Ctrl+F1');
  CheckKey(#27'[1;2Z', kbShiftTab, kbShift, '', 'Shift+Tab');
  CheckKey(#27'[1;2k', Ord('+'), kbShift, '+', 'Shift+keypad plus');
  CheckKey(#27'[1~', kbHome, 0, '', 'Home of the tilde form');
  CheckKey(#27'[2~', kbIns, 0, '', 'Insert');
  CheckKey(#27'[3~', kbDel, 0, '', 'Delete');
  CheckKey(#27'[4~', kbEnd, 0, '', 'End of the tilde form');
  CheckKey(#27'[5~', kbPgUp, 0, '', 'PgUp');
  CheckKey(#27'[6~', kbPgDn, 0, '', 'PgDn');
  CheckKey(#27'[11~', kbF1, 0, '', 'F1 of the tilde form');
  CheckKey(#27'[15~', kbF5, 0, '', 'F5');
  CheckKey(#27'[17~', kbF6, 0, '', 'F6');
  CheckKey(#27'[21~', kbF10, 0, '', 'F10');
  CheckKey(#27'[23~', kbShiftF1, kbShift, '', 'Shift+F1 of the tilde form');
  CheckKey(#27'[24~', kbShiftF2, kbShift, '', 'Shift+F2 of the tilde form');
  CheckKey(#27'[34~', kbShiftF10, kbShift, '', 'Shift+F10 of the tilde form');
  CheckKey(#27'[5;5~', kbCtrlPgUp, kbLeftCtrl, '', 'Ctrl+PgUp');
  CheckKey(#27'[15;2~', kbShiftF5, kbShift, '', 'Shift+F5');
  CheckKey(#27'[23;3~', kbAltF11, kbLeftAlt, '', 'Alt+F11');
  CheckKey(#27'[27;5;97~', kbCtrlA, kbLeftCtrl, '', 'modifyOtherKeys Ctrl+a');
  CheckKey(#27'[27;1;97~', Ord('a'), 0, 'a', 'modifyOtherKeys a');
  CheckKey(#27'[27;1;13~', kbEnter, 0, '', 'modifyOtherKeys Enter');
  CheckKey(#27'[27;3;120~', kbAltX, kbLeftAlt, '', 'modifyOtherKeys Alt+x');
  CheckKey(#27'[27;1;1105~', 0, 0, #$D1#$91, 'modifyOtherKeys of a non-ASCII character');
  CheckResult(#27'[27;1;1~', Ignored, 'modifyOtherKeys of a control character is ignored');
  CheckResult(#27'[99~', Rejected, 'unknown tilde key is rejected');
  CheckResult(#27'[9;9;9A', Rejected, 'unknown CSI form is rejected');
  CheckResult(#27'[1;5W', Rejected, 'unknown letter is rejected');
  CheckResult(#27'[5;5W', Rejected, 'unknown final byte is rejected');
  CheckResult(#27'[99;5~', Rejected, 'unknown tilde key with a modifier is rejected');

  State := NewState;
  Check(Parse(#27'[200~', Ev, State) = Ignored, 'start of a paste');
  Check(State.BracketedPaste, 'start of a paste: state');
  Check(Parse(#27'[201~', Ev, State) = Ignored, 'end of a paste');
  Check(not State.BracketedPaste, 'end of a paste: state');

  { Keys of SS3 }
  CheckKey(#27'O5P', kbCtrlF1, kbLeftCtrl, '', 'SS3 Ctrl+F1');
  CheckKey(#27'O2Q', kbShiftF2, kbShift, '', 'SS3 Shift+F2');
  CheckKey(#27'O3S', kbAltF4, kbLeftAlt, '', 'SS3 Alt+F4');
  CheckResult(#27'OP', Rejected, 'SS3 without a modifier is rejected');
  CheckResult(#27'O5W', Rejected, 'SS3 with an unknown letter is rejected');

  { Alt as a prefix }
  CheckKey(#27#27'[A', kbAltUp, kbLeftAlt, '', 'ESC ESC [ A is Alt+Up');
  CheckResult(#27#27'[M', Ignored, 'ESC ESC with a bad mouse is ignored');
  CheckResult(#27'x', Rejected, 'ESC and a letter is rejected');
  CheckResult('x', Rejected, 'a letter is rejected');
  CheckResult('', Rejected, 'no input is rejected');

  { Keys of Kitty }
  CheckKey(#27'[97;5u', kbCtrlA, kbLeftCtrl, '', 'Kitty Ctrl+a');
  CheckKey(#27'[97u', Ord('a'), 0, 'a', 'Kitty a');
  CheckKey(#27'[97;2u', Ord('a'), kbShift, 'a', 'Kitty Shift+a');
  CheckKey(#27'[97;1;65u', Ord('A'), 0, 'A', 'Kitty a with text A');
  CheckKey(#27'[97:65;1u', Ord('A'), 0, 'A', 'Kitty a with shifted key A');
  CheckKey(#27'[13u', kbEnter, 0, '', 'Kitty Enter');
  CheckKey(#27'[27u', kbEsc, 0, '', 'Kitty Esc');
  CheckKey(#27'[127u', kbBack, 0, '', 'Kitty code 127 is Backspace');
  CheckKey(#27'[57417u', kbLeft, 0, '', 'Kitty keypad Left');
  CheckKey(#27'[57399u', Ord('0'), 0, '0', 'Kitty keypad 0');
  CheckKey(#27'[57414;5u', kbCtrlEnter, kbLeftCtrl, '', 'Kitty keypad Enter with Ctrl');
  CheckKey(#27'[1092::97;5u', kbCtrlA, kbLeftCtrl, #$D1#$84, 'Kitty Ctrl+key of another layout');
  CheckResult(#27'[97;5:3u', Ignored, 'Kitty release is ignored');
  CheckResult(#27'[97;5:2u', Ignored, 'Kitty repeat is ignored');
  CheckResult(#27'[1u', Ignored, 'Kitty control character is ignored');
  CheckResult(#27'[57344u', Ignored, 'Kitty private character is ignored');

  { Responses of the terminal }
  State := NewState;
  Check(Parse(#27'[12;40R', Ev, State) = Ignored, 'cursor position report');
  Check(State.GotDsrResponse, 'cursor position report: state');
  State := NewState;
  CheckResult(#27'[12R', Rejected, 'cursor position report of one value is rejected');
  State := NewState;
  Check(Parse(#27'P1+r726561642d636c6970626f617264'#27'\', Ev, State) = Ignored, 'DCS');
  Check(State.HasFullOsc52, 'DCS with read-clipboard');
  State := NewState;
  Check(Parse(#27'P0+r'#27'\', Ev, State) = Ignored, 'DCS without read-clipboard');
  Check(not State.HasFullOsc52, 'DCS without read-clipboard: state');

  Base64Decode := @FakeDecode;
  FakePayload := '';
  State := NewState;
  State.PutPaste := @CapturePaste;
  Pasted := '';
  Check(Parse(#27']52;c;SGVsbG8='#7, Ev, State) = Ignored, 'OSC 52 response');
  Check(State.HasFullOsc52, 'the first OSC 52 response sets the support');
  Check(Pasted = '', 'the first OSC 52 response gives no text');
  Check(Parse(#27']52;c;SGVsbG8='#7, Ev, State) = Ignored, 'OSC 52 clipboard');
  Check(Pasted = 'D(SGVsbG8=)', 'OSC 52 clipboard gives the decoded text');
  Pasted := '';
  Check(Parse(#27']52;c;QUJD'#27'\', Ev, State) = Ignored, 'OSC 52 with ST');
  Check(Pasted = 'D(QUJD)', 'OSC 52 with ST gives the decoded text');
  State := NewState;
  Check(Parse(#27']60;allowWindowOps'#7, Ev, State) = Ignored, 'OSC 60');
  Check(State.HasFullOsc52, 'OSC 60 with allowWindowOps');
  State := NewState;
  Check(Parse(#27']60;other'#7, Ev, State) = Ignored, 'OSC 60 without allowWindowOps');
  Check(not State.HasFullOsc52, 'OSC 60 without allowWindowOps: state');
  Check(Parse(#27']52;'#7, Ev, State) = Ignored, 'OSC 52 without data');
  Check(not State.HasFullOsc52, 'OSC 52 without a second separator');
  Base64Decode := nil;

  { Sequences that switch features }
  Written := '';
  MouseOn(@Capture);
  Check(Written = #27'[?1001s'#27'[?1000h'#27'[?1002h'#27'[?1006h', 'MouseOn');
  Written := '';
  MouseOff(@Capture);
  Check(Written = #27'[?1006l'#27'[?1002l'#27'[?1000l'#27'[?1001r', 'MouseOff');
  Far2lEnableSeq := '<on>';
  Far2lDisableSeq := '<off>';
  S := KeyModsOnSequence(False, '');
  Check(Copy(S, 1, 8) = #27'[?1036s', 'KeyModsOn starts with metaSendsEscape');
  Check(Pos(#27'[>4;1m', S) > 0, 'KeyModsOn enables modifyOtherKeys');
  Check(Pos(#27'[?9001h<on>', S) > 0, 'KeyModsOn enables win32-input-mode and far2l');
  Check(Copy(S, Length(S) - 3, 4) = #27'[2J', 'KeyModsOn clears the screen');
  Check(Pos(#27']60', S) = 0, 'no TERM: no query');
  Check(Pos(#27']52;;?', S) = 0, 'no TERM: no clipboard request');
  S := KeyModsOnSequence(True, 'xterm-256color');
  Check(Pos(#27']60'#27'\', S) > 0, 'other TERM: query of allowWindowOps');
  Check(Pos(#27'P+q6b697474792d71756572792d636c6970626f6172645f636f6e74726f6c'#27'\', S) > 0,
    'other TERM: query of the clipboard control');
  Check(Pos(#27']52;;?', S) = 0, 'other TERM: no clipboard request');
  Check(Copy(S, Length(S) - 3, 4) = #27'[2J', 'other TERM: clears the screen');
  S := KeyModsOnSequence(True, 'alacritty');
  Check(Pos(#27']52;;?'#7, S) > 0, 'alacritty: clipboard request');
  Check(Pos(#27']60', S) = 0, 'alacritty: no query');
  S := KeyModsOnSequence(True, 'foot-extra');
  Check(Pos(#27']52;;?'#7, S) > 0, 'foot: clipboard request');
  S := KeyModsOnSequence(True, '');
  Check(Pos(#27']60'#27'\', S) > 0, 'empty TERM: query');
  Written := '';
  KeyModsOn(@Capture);
  Check(Copy(Written, 1, 8) = #27'[?1036s', 'KeyModsOn writes the sequence');
  Check(Copy(Written, Length(Written) - 3, 4) = #27'[2J', 'KeyModsOn writes the sequence up to the clear');
  Written := '';
  KeyModsOff(@Capture);
  Check(Written = '<off>'#27'[?9001l'#27'[<u'#27'[>4m'#27'[?2004l'#27'[?2004r'#27'[?1036r', 'KeyModsOff');
  Far2lEnableSeq := '';
  Far2lDisableSeq := '';

  { NormalizeKey }
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  KeyDown.KeyCode := kbF1;
  KeyDown.ControlKeyState := kbLeftCtrl;
  NormalizeKey(KeyDown);
  Check(KeyDown.KeyCode = kbCtrlF1, 'Ctrl+F1 is normalized');
  Check(KeyDown.ControlKeyState = kbLeftCtrl, 'Ctrl+F1 keeps its modifiers');
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  KeyDown.KeyCode := Ord('a');
  KeyDown.ControlKeyState := kbLeftAlt;
  KeyDown.Text[0] := Ord('a');
  KeyDown.TextLength := 1;
  NormalizeKey(KeyDown);
  Check(KeyDown.KeyCode = kbAltA, 'Alt+a is normalized');
  Check(KeyDown.TextLength = 0, 'Alt+a has no text');
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  KeyDown.KeyCode := Ord('A');
  KeyDown.ControlKeyState := kbShift;
  KeyDown.Text[0] := Ord('A');
  KeyDown.TextLength := 1;
  NormalizeKey(KeyDown);
  Check(KeyDown.KeyCode = Ord('A'), 'Shift+A is unchanged');
  Check(KeyDown.TextLength = 1, 'Shift+A keeps its text');
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  KeyDown.KeyCode := kbEnter;
  KeyDown.ControlKeyState := kbLeftCtrl or kbLeftAlt;
  NormalizeKey(KeyDown);
  Check(KeyDown.KeyCode = kbAltEnter, 'Ctrl+Alt+Enter takes the larger modifier');
  Check(KeyDown.ControlKeyState = (kbLeftCtrl or kbLeftAlt), 'Ctrl+Alt+Enter keeps both modifiers');
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  KeyDown.KeyCode := kbEnter;
  KeyDown.ControlKeyState := kbScrollState or kbShift;
  NormalizeKey(KeyDown);
  Check(KeyDown.ControlKeyState = (kbScrollState or kbShift), 'other state bits are kept');

  { Keys of the Windows console }
  FillChar(AltCvt, SizeOf(AltCvt), 0);
  FillChar(CtrlCvt, SizeOf(CtrlCvt), 0);
  FillChar(ShiftCvt, SizeOf(ShiftCvt), 0);
  FillChar(NormalCvt, SizeOf(NormalCvt), 0);

  State := NewState;
  SetKey(Ord('A'), 30, Ord('a'), 0);
  Check(ConvKey, 'a letter key');
  Check(Ev.What = evKeyDown, 'a letter key: key event');
  Check(Ev.KeyDown.CharScan.ScanCode = 30, 'a letter key: scan code');
  Check(Ev.KeyDown.CharScan.CharCode = Ord('a'), 'a letter key: char code');
  Check(Ev.KeyDown.GetText = 'a', 'a letter key: text');
  Check(Ev.KeyDown.ControlKeyState = 0, 'a letter key: no modifiers');

  SetKey(VK_F1, $3B, 0, kbShift or kbCapsState or kbInsState or kbPaste);
  Check(ConvKey, 'F1');
  Check(Ev.KeyDown.KeyCode = kbF1, 'F1: key code from the scan code');
  Check(Ev.KeyDown.TextLength = 0, 'F1: no text');
  Check(Ev.KeyDown.ControlKeyState = (kbShift or kbCapsState), 'the state of the control keys is masked');

  SetKey(Ord('A'), 30, 1, kbLeftCtrl);
  Check(ConvKey, 'Ctrl+A');
  Check(Ev.KeyDown.KeyCode = $1E01, 'Ctrl+A: key code');
  Check(Ev.KeyDown.TextLength = 0, 'Ctrl+A: no text');

  SetKey($10, $2A, 0, kbShift);
  Check(not ConvKey, 'a Shift key alone is discarded');
  SetKey($11, $1D, 0, kbLeftCtrl);
  Check(not ConvKey, 'a Ctrl key alone is discarded');
  SetKey($12, $38, 0, kbLeftAlt);
  Check(not ConvKey, 'an Alt key alone is discarded');
  SetKey($14, $3A, 0, kbCapsState);
  Check(not ConvKey, 'Caps Lock is discarded');
  SetKey($5B, $5B, 0, 0);
  Check(not ConvKey, 'the Windows key is discarded');

  SetKey(Ord('E'), 18, 0, kbLeftCtrl or kbRightAlt);
  Check(not ConvKey, 'AltGr without text is discarded');
  SetKey(Ord('E'), 18, Ord('e'), kbLeftCtrl or kbRightAlt);
  Check(ConvKey, 'AltGr with text');
  Check(Ev.KeyDown.GetText = 'e', 'AltGr with text: text');
  Check(Ev.KeyDown.ControlKeyState = 0, 'AltGr with text: Ctrl and Alt are dropped');

  SetKey(Ord('A'), 30, Ord('a'), kbLeftAlt);
  Check(ConvKey, 'Alt and text');
  Check(Ev.KeyDown.GetText = 'a', 'Alt and text: text');
  Check(Ev.KeyDown.ControlKeyState = kbLeftAlt, 'Alt and text: Alt is kept');

  SetKey(VK_MENU, 56, Ord('x'), 0);
  Check(ConvKey, 'a character with the Alt key code');
  Check(Ev.KeyDown.CharScan.ScanCode = 0, 'the scan code of the Alt key code is cleared');
  Check(Ev.KeyDown.KeyCode = Ord('x'), 'the key code of the Alt key code');

  SetKey(0, 0, 0, 0);
  Check(not ConvKey, 'an empty key');

  SetKey(0, 0, $1F600, 0);
  Check(ConvKey, 'a character outside the BMP');
  Check(Ev.KeyDown.GetText = #$F0#$9F#$98#$80, 'a character outside the BMP: text');
  Check(Ev.KeyDown.KeyCode = kbNoKey, 'a character outside the BMP has no key code');
  SetKey(0, 0, $D800, 0);
  ConvKey;
  Check(Ev.KeyDown.TextLength = 0, 'a surrogate has no text');
  SetKey(0, 0, $10FFFF, 0);
  ConvKey;
  Check(Ev.KeyDown.TextLength = 0, 'the last code point has no text');

  CpFromUtf8 := @HookCp;
  SetKey(0, 0, $0451, 0);
  Check(ConvKey, 'a character with a code page');
  Check(Ev.KeyDown.CharScan.CharCode = $F1, 'a character with a code page: char code');
  Check(Ev.KeyDown.GetText = #$D1#$91, 'a character with a code page: text');
  CpFromUtf8 := nil;

  { Conversion of scan codes by the tables }
  NormalCvt[59] := kbF1;
  ShiftCvt[59] := kbShiftF1;
  CtrlCvt[59] := kbCtrlF1;
  AltCvt[59] := kbAltF1;
  SetKey(VK_F1, 59, 0, 0);
  Check(ConvKey and (Ev.KeyDown.KeyCode = kbF1), 'table: normal');
  SetKey(VK_F1, 59, 0, kbShift);
  Check(ConvKey and (Ev.KeyDown.KeyCode = kbShiftF1), 'table: Shift');
  SetKey(VK_F1, 59, 0, kbLeftCtrl);
  Check(ConvKey and (Ev.KeyDown.KeyCode = kbCtrlF1), 'table: Ctrl');
  SetKey(VK_F1, 59, 0, kbLeftAlt);
  Check(ConvKey and (Ev.KeyDown.KeyCode = kbAltF1), 'table: Alt');
  SetKey(VK_F1, 59, 0, kbShift or kbLeftAlt);
  Check(ConvKey and (Ev.KeyDown.KeyCode = kbAltF1), 'table: Alt before Shift');
  SetKey(VK_F1, 59, 0, kbLeftCtrl or kbShift);
  Check(ConvKey and (Ev.KeyDown.KeyCode = kbCtrlF1), 'table: Ctrl before Shift');
  NormalCvt[30] := kbAltA;
  SetKey(Ord('A'), 30, Ord('a'), 0);
  Check(ConvKey, 'table: a key with text');
  Check(Ev.KeyDown.KeyCode = kbAltA, 'table: key code of a key with text');
  Check(Ev.KeyDown.TextLength = 0, 'table: a code below the space clears the text');
  NormalCvt[30] := $1E61;
  SetKey(Ord('A'), 30, Ord('a'), 0);
  Check(ConvKey, 'table: a printable key');
  Check((Ev.KeyDown.KeyCode = $1E61) and (Ev.KeyDown.GetText = 'a'), 'table: a printable key keeps its text');
  NormalCvt[30] := $1E61;
  SetKey(Ord('A'), 30, 0, 0);
  Check(ConvKey, 'table: a printable key without text');
  Check(Ev.KeyDown.GetText = 'a', 'table: text from a char code below 127');
  FillChar(AltCvt, SizeOf(AltCvt), 0);
  FillChar(CtrlCvt, SizeOf(CtrlCvt), 0);
  FillChar(ShiftCvt, SizeOf(ShiftCvt), 0);
  FillChar(NormalCvt, SizeOf(NormalCvt), 0);

  { Mouse of the Windows console }
  State := NewState;
  GetWin32Mouse(10, 5, 1, kbShift or kbCapsState, meDoubleClick, Ev, State);
  Check(Ev.What = evMouse, 'console mouse: mouse event');
  Check((Ev.Mouse.Where.X = 10) and (Ev.Mouse.Where.Y = 5), 'console mouse: position');
  Check(Ev.Mouse.Buttons = 1, 'console mouse: buttons');
  Check(State.Buttons = 1, 'console mouse: state');
  Check(Ev.Mouse.EventFlags = meDoubleClick, 'console mouse: event flags');
  Check(Ev.Mouse.ControlKeyState = (kbShift or kbCapsState), 'console mouse: modifiers');
  Check(Ev.Mouse.Wheel = 0, 'console mouse: no wheel');
  GetWin32Mouse(-1, 2, 0, $FFFF, 0, Ev, State);
  Check(Ev.Mouse.Where.X = -1, 'console mouse: negative position');
  Check(Ev.Mouse.ControlKeyState = (kbShift or kbCtrlShift or kbAltShift or kbScrollState or kbNumState or kbCapsState),
    'console mouse: the state of the control keys is masked');
  Check(State.Buttons = 0, 'console mouse: release');
  GetWin32Mouse(0, 0, $00780000, 0, MOUSE_WHEELED, Ev, State);
  Check(Ev.Mouse.Wheel = mwUp, 'console wheel up');
  GetWin32Mouse(0, 0, $FF880000, 0, MOUSE_WHEELED, Ev, State);
  Check(Ev.Mouse.Wheel = mwDown, 'console wheel down');
  GetWin32Mouse(0, 0, $00780000, 0, MOUSE_HWHEELED, Ev, State);
  Check(Ev.Mouse.Wheel = mwRight, 'console wheel right');
  GetWin32Mouse(0, 0, $FF880000, 0, MOUSE_HWHEELED, Ev, State);
  Check(Ev.Mouse.Wheel = mwLeft, 'console wheel left');
  Check(Ev.Mouse.EventFlags = MOUSE_HWHEELED, 'console wheel: event flags');

  { Scan codes from virtual key codes }
  SetKey(Ord('A'), 0, 0, kbLeftCtrl);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check(KScan = $1E, 'regenerate: scan code of A');
  Check(KCh = 0, 'regenerate: Ctrl clears the character');
  SetKey(Ord('A'), 0, 0, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check(KCh = Ord('A'), 'regenerate: the character of A');
  SetKey(Ord('A'), 0, Ord('a'), 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check(KCh = Ord('a'), 'regenerate: an existing character is kept');
  SetKey(Ord('A'), 0, Ord('a'), kbLeftAlt);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check(KCh = 0, 'regenerate: Alt clears a printable character');
  SetKey(Ord('A'), 0, 1, kbLeftCtrl);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check(KCh = 1, 'regenerate: Ctrl keeps a control character');
  SetKey(VK_F1, 0, 0, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check(KScan = $3B, 'regenerate: scan code of F1');
  Check(KCh = 0, 'regenerate: F1 has no character');
  SetKey(VK_F1, 0, Ord('x'), 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check(KCh = 0, 'regenerate: F1 clears the character');
  SetKey(VK_RETURN, 0, 0, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check((KScan = $1C) and (KCh = 13), 'regenerate: Enter');
  SetKey(VK_RETURN, 0, 10, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check(KCh = 10, 'regenerate: Enter keeps its character');
  SetKey(VK_NUMPAD7, 0, 0, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check((KScan = $47) and (KCh = Ord('7')), 'regenerate: keypad 7');
  SetKey(VK_SPACE, 0, 0, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check((KScan = $39) and (KCh = Ord(' ')), 'regenerate: space');
  SetKey(VK_SEPARATOR, 0, 0, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check((KScan = $7E) and (KCh = Ord(',')), 'regenerate: separator');
  SetKey(Ord('0'), 0, 0, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check((KScan = $0B) and (KCh = Ord('0')), 'regenerate: zero');
  SetKey($E8, 77, 5, 0);
  RegenerateMissingScanCodeFromVirtualKeyCode(KVk, KScan, KCh, KMods);
  Check((KScan = 77) and (KCh = 5), 'regenerate: an unknown key is unchanged');

  { win32-input-mode }
  CheckKey(#27'[65;30;97;1;0;1_', $1E61, 0, 'a', 'win32-input-mode a');
  CheckKey(#27'[112;0;0;1;0;1_', kbF1, 0, '', 'win32-input-mode F1');
  CheckKey(#27'[112;0;0;1;4;1_', kbCtrlF1, kbLeftCtrl, '', 'win32-input-mode Ctrl+F1');
  CheckKey(#27'[38;0;0;1;0;1_', kbUp, 0, '', 'win32-input-mode Up');
  CheckKey(#27'[38;0;0;1;3;1_', kbUp, kbShift, '', 'win32-input-mode Shift+Up');
  CheckResult(#27'[65;30;97;0;0;1_', Ignored, 'win32-input-mode key up is ignored');
  CheckResult(#27'[16;42;0;1;0;1_', Ignored, 'win32-input-mode Shift alone is ignored');

  { Escape sequences in win32-input-mode events }
  State := NewState;
  Check(Parse(#27'[0;0;27;1;0;1_' + #27'[0;0;91;1;0;1_' + #27'[0;0;65;1;0;1_', Ev, State) = Accepted,
    'wrapped Up');
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbUp), 'wrapped Up: key');
  Check(LastRest = 0, 'wrapped Up: all read');
  State := NewState;
  Check(Parse(#27'[0;0;27;1;0;1_' + #27'[0;0;91;1;0;1_' + #27'[0;0;49;1;0;1_' + #27'[0;0;59;1;0;1_' +
    #27'[0;0;53;1;0;1_' + #27'[0;0;65;1;0;1_', Ev, State) = Accepted, 'wrapped Ctrl+Up');
  Check(Ev.KeyDown.KeyCode = kbCtrlUp, 'wrapped Ctrl+Up: key');
  State := NewState;
  Check(Parse(#27'[0;0;27;1;0;1_' + #27'[0;0;120;1;0;1_', Ev, State) = Ignored, 'wrapped unknown sequence');
  Check(Parse(#27'[0;0;27;1;0;1_', Ev, State) = Ignored, 'a lone wrapped initiator');

  { far2l }
  Base64Decode := @FakeDecode;
  Base64Encode := @FakeEncode;
  State := NewState;
  FakePayload := #1#0 + #65#0 + #30#0 + #0#0#0#0 + #97#0#0#0 + 'K';
  Check(Parse(#27'_f2lAAAA'#7, Ev, State) = Accepted, 'far2l key');
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = $1E61) and (Ev.KeyDown.GetText = 'a'), 'far2l key: event');
  Check(LastRest = 0, 'far2l key: all read');
  FakePayload := #1#0 + #112#0 + #0#0 + #4#0#0#0 + #0#0#0#0 + 'K';
  Check(Parse(#27'_f2lAAAA'#7, Ev, State) = Accepted, 'far2l Ctrl+F1');
  Check((Ev.KeyDown.KeyCode = kbCtrlF1) and (Ev.KeyDown.ControlKeyState = kbLeftCtrl), 'far2l Ctrl+F1: event');
  FakePayload := #1#0 + #16#0 + #$2A#0 + #0#0#0#0 + #0#0#0#0 + 'K';
  Check(Parse(#27'_f2lAAAA'#7, Ev, State) = Ignored, 'far2l Shift alone is ignored');
  FakePayload := #10#0 + #5#0 + #1#0#0#0 + #4#0#0#0 + #0#0#0#0 + 'M';
  State := NewState;
  Check(Parse(#27'_f2lAAAA'#7, Ev, State) = Accepted, 'far2l mouse');
  Check(Ev.What = evMouse, 'far2l mouse: mouse event');
  Check((Ev.Mouse.Where.X = 10) and (Ev.Mouse.Where.Y = 5), 'far2l mouse: position');
  Check((Ev.Mouse.Buttons = 1) and (State.Buttons = 1), 'far2l mouse: buttons');
  Check(Ev.Mouse.ControlKeyState = kbLeftCtrl, 'far2l mouse: modifiers');
  FakePayload := #10#0 + #5#0 + #1#0#0#0 + #4#0#0#0 + #4#0#0#0 + 'M';
  Check(Parse(#27'_f2lAAAA'#7, Ev, State) = Accepted, 'far2l mouse wheel');
  Check(Ev.Mouse.EventFlags = MOUSE_WHEELED, 'far2l mouse wheel: event flags');
  Check(Ev.Mouse.Wheel = mwUp, 'far2l mouse wheel: wheel');
  FakePayload := #10#0 + #5#0 + 'M';
  Check(Parse(#27'_f2lAAAA'#7, Ev, State) = Ignored, 'far2l mouse of a wrong length');
  FakePayload := 'abc' + 'Q';
  Check(Parse(#27'_f2lAAAA'#7, Ev, State) = Ignored, 'far2l unknown kind');
  FakePayload := '';
  Check(Parse(#27'_f2l'#7, Ev, State) = Ignored, 'far2l empty');
  Base64Decode := nil;
  Check(Parse(#27'_f2lAAAA'#7, Ev, State) = Ignored, 'far2l without a decoder');
  Base64Decode := @FakeDecode;

  State := NewState;
  Check(Parse(#27'_far2lok'#27'\', Ev, State) = Ignored, 'far2l answer ok');
  Check(State.Far2l.Enabled, 'far2l answer ok: state');
  State := NewState;
  State.PutPaste := @CapturePaste;
  Pasted := '';
  FakePayload := 'hello'#0 + #6#0#0#0 + #$A0;
  Check(Parse(#27'_far2lAAAA'#7, Ev, State) = Ignored, 'far2l clipboard answer');
  Check(Pasted = 'hello', 'far2l clipboard answer: text without the terminator');
  FakePayload := 'junkhello' + #5#0#0#0 + #$A0;
  Pasted := '';
  Check(Parse(#27'_far2lAAAA'#7, Ev, State) = Ignored, 'far2l clipboard answer without a terminator');
  Check(Pasted = 'hello', 'far2l clipboard answer without a terminator: text');
  FakePayload := 'hi' + #200#0#0#0 + #$A0;
  Pasted := '';
  Parse(#27'_far2lAAAA'#7, Ev, State);
  Check(Pasted = '', 'far2l clipboard answer with a size that is too large');
  FakePayload := #0#0#0#0 + #$A0;
  Pasted := 'x';
  Parse(#27'_far2lAAAA'#7, Ev, State);
  Check(Pasted = '', 'far2l clipboard answer of no text');
  FakePayload := 'hello'#0 + #6#0#0#0 + #$A1;
  Pasted := 'x';
  Parse(#27'_far2lAAAA'#7, Ev, State);
  Check(Pasted = 'x', 'far2l answer of another kind');
  State.PutPaste := nil;
  FakePayload := 'hello'#0 + #6#0#0#0 + #$A0;
  Parse(#27'_far2lAAAA'#7, Ev, State);
  Check(Pasted = 'x', 'far2l clipboard answer without a receiver');
  FakePayload := '';

  { Clipboard }
  State := NewState;
  Written := '';
  Check(not SetClipboardText(@Capture, 'hi', State), 'clipboard without support');
  Check(Written = #27']52;;E(hi)'#7, 'clipboard without support: OSC 52 is written');
  State.HasFullOsc52 := True;
  Written := '';
  Check(SetClipboardText(@Capture, 'hi', State), 'clipboard with OSC 52');
  Check(Written = #27']52;;E(hi)'#7, 'clipboard with OSC 52: written');
  State := NewState;
  Written := '';
  Check(not RequestClipboardText(@Capture, @CapturePaste, State), 'clipboard request without support');
  Check(Written = '', 'clipboard request without support: nothing written');
  Pasted := '';
  State.PutPaste('zz');
  Check(Pasted = 'zz', 'clipboard request: the receiver is set');
  State.HasFullOsc52 := True;
  Check(RequestClipboardText(@Capture, @CapturePaste, State), 'clipboard request with OSC 52');
  Check(Written = #27']52;;?'#7, 'clipboard request with OSC 52: written');
  Base64Decode := nil;
  Base64Encode := nil;

  { Input that arrives while the application exits }
  G := TStringGetter.Create(#27'[12;40R');
  State := NewState;
  Written := '';
  ConsumeUnprocessedInput(@Capture, G, State);
  Check(Written = #27'[6n', 'consume: the request is written');
  Check(State.GotDsrResponse, 'consume: the response is read');
  Check(G.Index = 8, 'consume: the input is read up to the response');
  G.Free;
  G := TStringGetter.Create('xy'#27'[1;5A'#27'[3;4R');
  State := NewState;
  Written := '';
  ConsumeUnprocessedInput(@Capture, G, State);
  Check(State.GotDsrResponse, 'consume: the response after other input');
  Check(G.Index = Length(G.Data), 'consume: all the input is read');
  G.Free;
  G := TStringGetter.Create('');
  State := NewState;
  Written := '';
  ConsumeUnprocessedInput(@Capture, G, State);
  Check(not State.GotDsrResponse, 'consume: no response');
  G.Free;

  { The text of a key gets a code page character through the hook }
  CpPrintableFromUtf8 := @HookCp;
  CheckKey(#27'[27;1;1105~', $00F1, 0, #$D1#$91, 'modifyOtherKeys with a code page');
  CpPrintableFromUtf8 := nil;

  Done;
end.
