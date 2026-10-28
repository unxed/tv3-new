{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: source/tvterm-core/vtermemu.cc (the conversion of input events),
  include/tvterm/vtermemu.h
  See COPYRIGHT.tvterm. }
program t_vtkeys;

{$mode objfpc}

uses
  TvKeys, TvEvents, TvVtKeys;

{$I testlib.inc}

{ Expected texts are written as the text after the ESC. }
function Esc(const Rest: AnsiString): AnsiString;
begin
  Result := #27 + Rest;
end;

function Rep(const Piece: AnsiString; Times: Integer): AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Times do
    Result := Result + Piece;
end;

function KeyEv(Code, State: Word; const Txt: AnsiString): TKeyDownEvent;
var
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.KeyCode := Code;
  Result.ControlKeyState := State;
  Result.TextLength := Length(Txt);
  for I := 1 to Length(Txt) do
    Result.Text[I - 1] := Ord(Txt[I]);
end;

function MouseEv(X, Y: Integer; Btn, Whl: Byte; State: Word): TMouseEventType;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Where.X := X;
  Result.Where.Y := Y;
  Result.Buttons := Btn;
  Result.Wheel := Whl;
  Result.ControlKeyState := State;
end;

function ModesOf(Track: TVtMouseTracking; Enc: TVtMouseEncoding): TVtInputModes;
begin
  Result := DefaultInputModes;
  Result.MouseTracking := Track;
  Result.MouseEncoding := Enc;
end;

function AppCursor: TVtInputModes;
begin
  Result := DefaultInputModes;
  Result.CursorKeysApplication := True;
end;

{ A key without text, in the default modes. }
function Plain(Code, State: Word): AnsiString;
begin
  Result := ProcessKey(KeyEv(Code, State, ''), DefaultInputModes);
end;

procedure TestConversions;
var
  M: TVtModifiers;
  B: Integer;
begin
  Check(mouseWheelScrollLines = 3, 'wheel lines');
  Check(ConvKey(kbEnter) = vkEnter, 'conv enter');
  Check(ConvKey(kbTab) = vkTab, 'conv tab');
  Check(ConvKey(kbBack) = vkBackspace, 'conv back');
  Check(ConvKey(kbEsc) = vkEscape, 'conv esc');
  Check(ConvKey(kbUp) = vkUp, 'conv up');
  Check(ConvKey(kbPgDn) = vkPageDown, 'conv pgdn');
  Check(ConvKey(kbDel) = vkDel, 'conv del');
  Check(ConvKey(kbF1) = vkF1, 'conv f1');
  Check(ConvKey(kbF12) = vkF12, 'conv f12');
  Check(ConvKey(kbShiftF1) = vkNone, 'conv shift f1 is no key');
  Check(ConvKey(Ord('A')) = vkNone, 'conv letter');
  Check(ConvMod(0) = [], 'mod none');
  Check(ConvMod(kbLeftShift) = [vmShift], 'mod left shift');
  Check(ConvMod(kbRightShift) = [vmShift], 'mod right shift');
  Check(ConvMod(kbLeftAlt) = [vmAlt], 'mod alt');
  Check(ConvMod(kbCtrlShift) = [vmCtrl], 'mod ctrl');
  Check(ConvMod(kbShift or kbCtrlShift or kbAltShift) = [vmShift, vmAlt, vmCtrl], 'mod all');
  Check(ConvMod(kbNumState or kbCapsState) = [], 'mod locks');

  ConvMouse(MouseEv(0, 0, mbLeftButton, 0, kbShift), M, B);
  Check((B = 1) and (M = [vmShift]), 'button left');
  ConvMouse(MouseEv(0, 0, mbMiddleButton, 0, 0), M, B);
  Check(B = 2, 'button middle');
  ConvMouse(MouseEv(0, 0, mbRightButton, 0, 0), M, B);
  Check(B = 3, 'button right');
  ConvMouse(MouseEv(0, 0, mbLeftButton or mbRightButton, 0, 0), M, B);
  Check(B = 1, 'button left before right');
  ConvMouse(MouseEv(0, 0, 0, mwUp, kbLeftAlt), M, B);
  Check((B = 4) and (M = [vmAlt]), 'button wheel up');
  ConvMouse(MouseEv(0, 0, 0, mwDown, 0), M, B);
  Check(B = 5, 'button wheel down');
  ConvMouse(MouseEv(0, 0, 0, mwLeft, 0), M, B);
  Check(B = 0, 'button wheel left');
  ConvMouse(MouseEv(0, 0, 0, 0, 0), M, B);
  Check(B = 0, 'button none');
end;

procedure TestCursorKeys;
begin
  Check(Plain(kbUp, 0) = Esc('[A'), 'up');
  Check(Plain(kbDown, 0) = Esc('[B'), 'down');
  Check(Plain(kbRight, 0) = Esc('[C'), 'right');
  Check(Plain(kbLeft, 0) = Esc('[D'), 'left');
  Check(Plain(kbHome, 0) = Esc('[H'), 'home');
  Check(Plain(kbEnd, 0) = Esc('[F'), 'end');

  Check(ProcessKey(KeyEv(kbUp, 0, ''), AppCursor) = Esc('OA'), 'app up');
  Check(ProcessKey(KeyEv(kbDown, 0, ''), AppCursor) = Esc('OB'), 'app down');
  Check(ProcessKey(KeyEv(kbRight, 0, ''), AppCursor) = Esc('OC'), 'app right');
  Check(ProcessKey(KeyEv(kbLeft, 0, ''), AppCursor) = Esc('OD'), 'app left');
  Check(ProcessKey(KeyEv(kbHome, 0, ''), AppCursor) = Esc('OH'), 'app home');
  Check(ProcessKey(KeyEv(kbEnd, 0, ''), AppCursor) = Esc('OF'), 'app end');

  Check(Plain(kbCtrlUp, 0) = Esc('[1;5A'), 'ctrl up');
  Check(ProcessKey(KeyEv(kbCtrlUp, 0, ''), AppCursor) = Esc('[1;5A'), 'app ctrl up');
  Check(Plain(kbAltLeft, 0) = Esc('[1;3D'), 'alt left');
  Check(Plain(kbUp, kbShift) = Esc('[1;2A'), 'shift up');
  Check(Plain(kbRight, kbShift or kbCtrlShift) = Esc('[1;6C'), 'shift ctrl right');
  Check(Plain(kbUp, kbShift or kbCtrlShift or kbLeftAlt) = Esc('[1;8A'), 'all up');
  Check(Plain(kbCtrlHome, 0) = Esc('[1;5H'), 'ctrl home');
  Check(Plain(kbAltEnd, 0) = Esc('[1;3F'), 'alt end');
end;

procedure TestEditingKeys;
begin
  Check(Plain(kbIns, 0) = Esc('[2~'), 'ins');
  Check(Plain(kbDel, 0) = Esc('[3~'), 'del');
  Check(Plain(kbPgUp, 0) = Esc('[5~'), 'pgup');
  Check(Plain(kbPgDn, 0) = Esc('[6~'), 'pgdn');
  Check(ProcessKey(KeyEv(kbPgDn, 0, ''), AppCursor) = Esc('[6~'), 'app pgdn');
  Check(Plain(kbShiftIns, 0) = Esc('[2;2~'), 'shift ins');
  Check(Plain(kbShiftDel, 0) = Esc('[3;2~'), 'shift del');
  Check(Plain(kbCtrlPgUp, 0) = Esc('[5;5~'), 'ctrl pgup');
  Check(Plain(kbAltPgDn, 0) = Esc('[6;3~'), 'alt pgdn');
  Check(Plain(kbCtrlIns, 0) = Esc('[2;5~'), 'ctrl ins');
  Check(Plain(kbAltDel, 0) = Esc('[3;3~'), 'alt del');
end;

procedure TestFunctionKeys;
begin
  Check(Plain(kbF1, 0) = Esc('OP'), 'f1');
  Check(Plain(kbF2, 0) = Esc('OQ'), 'f2');
  Check(Plain(kbF3, 0) = Esc('OR'), 'f3');
  Check(Plain(kbF4, 0) = Esc('OS'), 'f4');
  Check(ProcessKey(KeyEv(kbF1, 0, ''), AppCursor) = Esc('OP'), 'app f1');
  Check(Plain(kbF5, 0) = Esc('[15~'), 'f5');
  Check(Plain(kbF6, 0) = Esc('[17~'), 'f6');
  Check(Plain(kbF7, 0) = Esc('[18~'), 'f7');
  Check(Plain(kbF8, 0) = Esc('[19~'), 'f8');
  Check(Plain(kbF9, 0) = Esc('[20~'), 'f9');
  Check(Plain(kbF10, 0) = Esc('[21~'), 'f10');
  Check(Plain(kbF11, 0) = Esc('[23~'), 'f11');
  Check(Plain(kbF12, 0) = Esc('[24~'), 'f12');

  Check(Plain(kbShiftF1, 0) = Esc('[1;2P'), 'shift f1');
  Check(Plain(kbCtrlF2, 0) = Esc('[1;5Q'), 'ctrl f2');
  Check(Plain(kbAltF3, 0) = Esc('[1;3R'), 'alt f3');
  Check(Plain(kbF4, kbShift or kbLeftAlt) = Esc('[1;4S'), 'shift alt f4');
  Check(Plain(kbShiftF5, 0) = Esc('[15;2~'), 'shift f5');
  Check(Plain(kbF5, kbShift or kbCtrlShift) = Esc('[15;6~'), 'shift ctrl f5');
  Check(Plain(kbAltF10, 0) = Esc('[21;3~'), 'alt f10');
  Check(Plain(kbCtrlF12, 0) = Esc('[24;5~'), 'ctrl f12');
  Check(Plain(kbShiftF11, 0) = Esc('[23;2~'), 'shift f11');
end;

procedure TestControlKeys;
begin
  Check(Plain(kbEnter, 0) = #13, 'enter');
  Check(Plain(kbAltEnter, 0) = Esc(#13), 'alt enter');
  Check(Plain(kbCtrlEnter, 0) = #13, 'ctrl enter');
  Check(Plain(kbTab, 0) = #9, 'tab');
  Check(Plain(kbShiftTab, 0) = Esc('[Z'), 'shift tab');
  Check(Plain(kbAltTab, 0) = Esc(#9), 'alt tab');
  Check(Plain(kbBack, 0) = #127, 'backspace');
  Check(Plain(kbCtrlBack, 0) = #8, 'ctrl backspace');
  Check(Plain(kbAltBack, 0) = Esc(#127), 'alt backspace');
  Check(Plain(kbEsc, 0) = #27, 'escape');
  Check(Plain(kbAltEsc, 0) = Esc(#27), 'alt escape');
end;

procedure TestTextKeys;
begin
  Check(ProcessKey(KeyEv(Ord('a'), 0, 'a'), DefaultInputModes) = 'a', 'text a');
  Check(ProcessKey(KeyEv(Ord('A'), kbShift, 'A'), DefaultInputModes) = 'A', 'text shift A');
  Check(ProcessKey(KeyEv($D0B6, 0, #$D0#$B6), DefaultInputModes) = #$D0#$B6, 'text utf8');
  Check(ProcessKey(KeyEv(0, 0, #$E2#$82#$AC), DefaultInputModes) = #$E2#$82#$AC, 'text euro');
  Check(ProcessKey(KeyEv($0635, 0, ''), DefaultInputModes) = '5', 'digit no text');
  Check(Plain($3920, 0) = ' ', 'space no text');
  Check(Plain(kbAltSpace, 0) = Esc(' '), 'alt space');
  Check(Plain(kbAlt1, 0) = Esc('1'), 'alt 1');
  Check(Plain(kbAltA, kbLeftAlt) = Esc('a'), 'alt a');
  Check(Plain(kbAltA, 0) = Esc('A'), 'alt a without state');
  Check(Plain(kbAltA, kbLeftAlt or kbShift) = Esc('A'), 'alt shift a');
  Check(ProcessKey(KeyEv(Ord('x'), kbLeftAlt, 'x'), DefaultInputModes) = Esc('x'), 'alt text x');
  Check(ProcessKey(KeyEv($D0B6, kbLeftAlt, #$D0#$B6), DefaultInputModes) = Esc(#$D0#$B6), 'alt text utf8');
  Check(ProcessKey(KeyEv(0, kbLeftAlt, #$D0#$B6), DefaultInputModes) = #$D0#$B6, 'text of a zero key code');
  Check(Plain(kbNoKey, 0) = '', 'no key');
  Check(Plain(kbCtrlPrtSc, 0) = '', 'key without bytes');
end;

procedure TestControlLetters;
begin
  Check(Plain(kbCtrlA, 0) = #1, 'ctrl a');
  Check(Plain(kbCtrlA, kbCtrlShift) = #1, 'ctrl a with state');
  Check(Plain(kbCtrlM, 0) = #13, 'ctrl m');
  Check(Plain(kbCtrlZ, 0) = #26, 'ctrl z');
  Check(Plain(kbCtrlA, kbShift) = #1, 'ctrl shift a');
  Check(Plain(kbAltA, kbCtrlShift or kbLeftAlt) = Esc(#1), 'ctrl alt a');
  Check(ProcessKey(KeyEv(Ord('['), kbCtrlShift, '['), DefaultInputModes) = #27, 'ctrl bracket');
  Check(ProcessKey(KeyEv($3920, kbCtrlShift, ' '), DefaultInputModes) = #0, 'ctrl space');
  { With Ctrl alone and a letter, the character code of the event is sent as it is. }
  Check(ProcessKey(KeyEv(Ord('c'), kbCtrlShift, 'c'), DefaultInputModes) = 'c', 'ctrl letter char code');
  Check(ProcessKey(KeyEv($2E03, kbCtrlShift, #3), DefaultInputModes) = #3, 'ctrl letter control code');
  Check(ProcessKey(KeyEv(Ord('7'), kbCtrlShift, '7'), DefaultInputModes) = '7', 'ctrl digit');
end;

procedure TestUnicharAndKeyBytes;
begin
  Check(UnicharBytes(Ord('q'), []) = 'q', 'unichar plain');
  Check(UnicharBytes($20AC, []) = #$E2#$82#$AC, 'unichar euro');
  Check(UnicharBytes(Ord('q'), [vmAlt]) = Esc('q'), 'unichar alt');
  Check(UnicharBytes(Ord('q'), [vmShift]) = 'q', 'unichar shift');
  Check(UnicharBytes(Ord('q'), [vmCtrl]) = #17, 'unichar ctrl');
  Check(UnicharBytes(Ord('Q'), [vmCtrl, vmAlt]) = Esc(#17), 'unichar ctrl alt');
  Check(UnicharBytes(Ord('@'), [vmCtrl]) = #0, 'unichar ctrl at');
  Check(UnicharBytes(Ord('_'), [vmCtrl]) = #31, 'unichar ctrl underscore');
  Check(KeyBytes(vkNone, [], DefaultInputModes) = '', 'key none');
  Check(KeyBytes(vkLeft, [vmShift, vmAlt], DefaultInputModes) = Esc('[1;4D'), 'key shift alt left');
  Check(KeyBytes(vkEnd, [], AppCursor) = Esc('OF'), 'key app end');
end;

procedure TestKeypad;
var
  Md: TVtInputModes;
begin
  Md := DefaultInputModes;
  Check(ProcessKeypad('5', Md) = '5', 'keypad numeric 5');
  Check(ProcessKeypad(#13, Md) = #13, 'keypad numeric enter');
  Md.KeypadApplication := True;
  Check(ProcessKeypad('0', Md) = Esc('Op'), 'keypad 0');
  Check(ProcessKeypad('5', Md) = Esc('Ou'), 'keypad 5');
  Check(ProcessKeypad('9', Md) = Esc('Oy'), 'keypad 9');
  Check(ProcessKeypad('*', Md) = Esc('Oj'), 'keypad multiply');
  Check(ProcessKeypad('+', Md) = Esc('Ok'), 'keypad add');
  Check(ProcessKeypad(',', Md) = Esc('Ol'), 'keypad comma');
  Check(ProcessKeypad('-', Md) = Esc('Om'), 'keypad minus');
  Check(ProcessKeypad('.', Md) = Esc('On'), 'keypad period');
  Check(ProcessKeypad('/', Md) = Esc('Oo'), 'keypad divide');
  Check(ProcessKeypad('=', Md) = Esc('OX'), 'keypad equal');
  Check(ProcessKeypad(#13, Md) = Esc('OM'), 'keypad enter');
  Check(ProcessKeypad(#9, Md) = Esc('OI'), 'keypad tab');
  Check(ProcessKeypad(' ', Md) = Esc('O '), 'keypad space');
  Check(ProcessKeypad('a', Md) = 'a', 'keypad other');
end;

procedure TestWheelArrows;
var
  Md: TVtInputModes;
begin
  Md := DefaultInputModes;
  Check(WheelToArrow(mwUp, Md) = Rep(Esc('[A'), 3), 'wheel up');
  Check(WheelToArrow(mwDown, Md) = Rep(Esc('[B'), 3), 'wheel down');
  Check(WheelToArrow(mwLeft, Md) = Rep(Esc('[D'), 3), 'wheel left');
  Check(WheelToArrow(mwRight, Md) = Rep(Esc('[C'), 3), 'wheel right');
  Check(WheelToArrow(0, Md) = '', 'wheel none');
  Check(WheelToArrow(mwUp or mwDown, Md) = '', 'wheel two bits');
  Check(WheelToArrow(mwDown, AppCursor) = Rep(Esc('OB'), 3), 'wheel down application');
end;

procedure TestMouseOffAndX10;
var
  St: TVtMouseState;
  Md: TVtInputModes;
begin
  Md := ModesOf(vtTrackOff, vtEncDefault);
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(3, 3, mbLeftButton, 0, 0), Md, St) = '', 'off press');
  Check(ProcessMouse(evMouseWheel, MouseEv(3, 3, 0, mwUp, 0), Md, St) = '', 'off wheel');

  Md := ModesOf(vtTrackX10, vtEncDefault);
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(0, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[M') + #32#33#33, 'x10 left press');
  Check(ProcessMouse(evMouseUp, MouseEv(0, 0, 0, 0, 0), Md, St) = '', 'x10 release');
  Check(ProcessMouse(evMouseDown, MouseEv(1, 2, mbRightButton, 0, kbShift), Md, St)
    = Esc('[M') + #34#34#35, 'x10 right press with shift');
  Check(ProcessMouse(evMouseWheel, MouseEv(1, 2, 0, mwUp, 0), Md, St) = '', 'x10 wheel');
  Check(ProcessMouse(evMouseMove, MouseEv(5, 5, 0, 0, 0), Md, St) = '', 'x10 move');
end;

procedure TestMouseNormal;
var
  St: TVtMouseState;
  Md: TVtInputModes;
begin
  Md := ModesOf(vtTrackNormal, vtEncDefault);
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(0, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[M') + #32#33#33, 'normal left press');
  Check(ProcessMouse(evMouseUp, MouseEv(0, 0, 0, 0, 0), Md, St)
    = Esc('[M') + #35#33#33, 'normal release');
  Check(ProcessMouse(evMouseDown, MouseEv(9, 4, mbRightButton, 0, 0), Md, St)
    = Esc('[M') + #34#42#37, 'normal right press');
  Check(ProcessMouse(evMouseUp, MouseEv(9, 4, 0, 0, 0), Md, St)
    = Esc('[M') + #35#42#37, 'normal right release');
  Check(ProcessMouse(evMouseDown, MouseEv(9, 4, mbMiddleButton, 0, 0), Md, St)
    = Esc('[M') + #33#42#37, 'normal middle press');
  Check(ProcessMouse(evMouseUp, MouseEv(9, 4, 0, 0, 0), Md, St)
    = Esc('[M') + #35#42#37, 'normal middle release');
  Check(ProcessMouse(evMouseDown, MouseEv(0, 0, mbLeftButton, 0, kbShift or kbLeftAlt or kbCtrlShift),
    Md, St) = Esc('[M') + #60#33#33, 'normal press with modifiers');
  Check(ProcessMouse(evMouseUp, MouseEv(0, 0, 0, 0, kbCtrlShift), Md, St)
    = Esc('[M') + #51#33#33, 'normal release with ctrl');
  Check(ProcessMouse(evMouseWheel, MouseEv(0, 0, 0, mwUp, 0), Md, St)
    = Esc('[M') + #96#33#33, 'normal wheel up');
  Check(ProcessMouse(evMouseWheel, MouseEv(0, 0, 0, mwDown, 0), Md, St)
    = Esc('[M') + #97#33#33, 'normal wheel down');
  Check(ProcessMouse(evMouseWheel, MouseEv(0, 0, 0, mwLeft, 0), Md, St) = '', 'normal wheel left');
  Check(ProcessMouse(evMouseMove, MouseEv(7, 7, mbLeftButton, 0, 0), Md, St) = '', 'normal move');
  Check(ProcessMouse(evMouseUp, MouseEv(7, 7, 0, 0, 0), Md, St) = '', 'release with nothing held');
end;

procedure TestMouseLimits;
var
  St: TVtMouseState;
  Md: TVtInputModes;
begin
  Md := ModesOf(vtTrackNormal, vtEncDefault);
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(222, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[M') + #32#255#33, 'default encoding at the limit');
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(223, 0, mbLeftButton, 0, 0), Md, St) = '',
    'default encoding beyond the limit');
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(0, 223, mbLeftButton, 0, 0), Md, St) = '',
    'default encoding row beyond the limit');

  Md := ModesOf(vtTrackNormal, vtEncUtf8);
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(94, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[M') + #32#127#33, 'utf8 last single byte');
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(95, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[M') + #32#$C2#$80#33, 'utf8 first pair');
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(100, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[M') + #32#$C2#$85#33, 'utf8 column 100');
  Check(ProcessMouse(evMouseUp, MouseEv(100, 0, 0, 0, 0), Md, St)
    = Esc('[M') + #35#$C2#$85#33, 'utf8 release');
  Check(ProcessMouse(evMouseWheel, MouseEv(100, 40, 0, mwUp, kbCtrlShift), Md, St)
    = Esc('[M') + #112#$C2#$85#73, 'utf8 wheel with ctrl');
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(2014, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[M') + #32#$DF#$BF#33, 'utf8 limit');
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(2015, 0, mbLeftButton, 0, 0), Md, St) = '',
    'utf8 beyond the limit');
end;

procedure TestMouseSgr;
var
  St: TVtMouseState;
  Md: TVtInputModes;
begin
  Md := ModesOf(vtTrackNormal, vtEncSgr);
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(0, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[<0;1;1M'), 'sgr left press');
  Check(ProcessMouse(evMouseUp, MouseEv(0, 0, 0, 0, 0), Md, St) = Esc('[<0;1;1m'), 'sgr left release');
  Check(ProcessMouse(evMouseDown, MouseEv(99, 39, mbRightButton, 0, 0), Md, St)
    = Esc('[<2;100;40M'), 'sgr right press far');
  Check(ProcessMouse(evMouseUp, MouseEv(99, 39, 0, 0, 0), Md, St) = Esc('[<2;100;40m'),
    'sgr right release far');
  Check(ProcessMouse(evMouseDown, MouseEv(0, 0, mbMiddleButton, 0, 0), Md, St)
    = Esc('[<1;1;1M'), 'sgr middle press');
  Check(ProcessMouse(evMouseUp, MouseEv(0, 0, 0, 0, 0), Md, St) = Esc('[<1;1;1m'), 'sgr middle release');
  Check(ProcessMouse(evMouseDown, MouseEv(0, 0, mbLeftButton, 0, kbCtrlShift), Md, St)
    = Esc('[<16;1;1M'), 'sgr press with ctrl');
  Check(ProcessMouse(evMouseUp, MouseEv(0, 0, 0, 0, kbCtrlShift), Md, St)
    = Esc('[<16;1;1m'), 'sgr release with ctrl');
  Check(ProcessMouse(evMouseWheel, MouseEv(0, 0, 0, mwDown, 0), Md, St)
    = Esc('[<65;1;1M'), 'sgr wheel down');
  Check(ProcessMouse(evMouseWheel, MouseEv(4, 2, 0, mwUp, kbLeftAlt), Md, St)
    = Esc('[<72;5;3M'), 'sgr wheel up with alt');
  Check(ProcessMouse(evMouseDown, MouseEv(4000, 3000, mbLeftButton, 0, 0), Md, St)
    = Esc('[<0;4001;3001M'), 'sgr large position');
  Check(ProcessMouse(evMouseUp, MouseEv(4000, 3000, 0, 0, 0), Md, St) = Esc('[<0;4001;3001m'),
    'sgr large release');
end;

procedure TestMouseMotion;
var
  St: TVtMouseState;
  Md: TVtInputModes;
begin
  { Button-event tracking with the SGR encoding }
  Md := ModesOf(vtTrackButton, vtEncSgr);
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(0, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[<0;1;1M'), 'drag: press');
  Check(ProcessMouse(evMouseMove, MouseEv(1, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[<32;2;1M'), 'drag: move');
  Check(ProcessMouse(evMouseMove, MouseEv(1, 0, mbLeftButton, 0, 0), Md, St) = '',
    'drag: same cell');
  Check(ProcessMouse(evMouseAuto, MouseEv(1, 0, mbLeftButton, 0, 0), Md, St) = '',
    'drag: auto event');
  Check(ProcessMouse(evMouseMove, MouseEv(1, 1, mbLeftButton, 0, kbCtrlShift), Md, St)
    = Esc('[<48;2;2M'), 'drag: move with ctrl');
  Check(ProcessMouse(evMouseUp, MouseEv(1, 1, 0, 0, 0), Md, St) = Esc('[<0;2;2m'), 'drag: release');
  Check(ProcessMouse(evMouseMove, MouseEv(2, 1, 0, 0, 0), Md, St) = '', 'drag: move without button');

  { Button-event tracking with the default encoding: the examples of the document }
  Md := ModesOf(vtTrackButton, vtEncDefault);
  St := NewMouseState;
  ProcessMouse(evMouseDown, MouseEv(0, 0, mbLeftButton, 0, 0), Md, St);
  Check(ProcessMouse(evMouseMove, MouseEv(4, 2, mbLeftButton, 0, 0), Md, St)
    = Esc('[M') + '@' + #37#35, 'drag default: button 1');
  ProcessMouse(evMouseUp, MouseEv(4, 2, 0, 0, 0), Md, St);
  ProcessMouse(evMouseDown, MouseEv(4, 2, mbRightButton, 0, 0), Md, St);
  Check(ProcessMouse(evMouseMove, MouseEv(5, 2, mbRightButton, 0, 0), Md, St)
    = Esc('[M') + 'B' + #38#35, 'drag default: button 3');

  { Any-event tracking }
  Md := ModesOf(vtTrackAny, vtEncSgr);
  St := NewMouseState;
  Check(ProcessMouse(evMouseDown, MouseEv(0, 0, mbLeftButton, 0, 0), Md, St)
    = Esc('[<35;1;1M') + Esc('[<0;1;1M'), 'any: first press moves first');
  Check(ProcessMouse(evMouseUp, MouseEv(0, 0, 0, 0, 0), Md, St) = Esc('[<0;1;1m'), 'any: release');
  Check(ProcessMouse(evMouseMove, MouseEv(3, 1, 0, 0, 0), Md, St) = Esc('[<35;4;2M'), 'any: bare move');
  Check(ProcessMouse(evMouseMove, MouseEv(3, 1, 0, 0, 0), Md, St) = '', 'any: same cell');
  Md.MouseEncoding := vtEncDefault;
  Check(ProcessMouse(evMouseMove, MouseEv(4, 1, 0, 0, 0), Md, St)
    = Esc('[M') + #67#37#34, 'any default: bare move');
  Md.MouseEncoding := vtEncUtf8;
  Check(ProcessMouse(evMouseMove, MouseEv(100, 1, 0, 0, kbShift), Md, St)
    = Esc('[M') + #71#$C2#$85#34, 'any utf8: move with shift');

  { Normal tracking does not report motion, but remembers the cell }
  Md := ModesOf(vtTrackNormal, vtEncSgr);
  St := NewMouseState;
  Check(ProcessMouse(evMouseMove, MouseEv(5, 5, 0, 0, 0), Md, St) = '', 'normal: no motion');
  Check((St.Col = 5) and (St.Row = 5), 'normal: cell remembered');
  Check(St.Buttons = 0, 'normal: nothing held');
  ProcessMouse(evMouseDown, MouseEv(5, 5, mbLeftButton, 0, 0), Md, St);
  Check(St.Buttons = 1, 'normal: left held');
  ProcessMouse(evMouseUp, MouseEv(5, 5, 0, 0, 0), Md, St);
  Check(St.Buttons = 0, 'normal: left let go');
end;

procedure TestPasteAndFocus;
var
  Md: TVtInputModes;
begin
  Md := DefaultInputModes;
  Check(ProcessPaste('abc', Md) = 'abc', 'paste plain');
  Check(ProcessFocus(True, Md) = '', 'focus in off');
  Check(ProcessFocus(False, Md) = '', 'focus out off');
  Md.BracketedPaste := True;
  Check(ProcessPaste('abc', Md) = Esc('[200~abc') + Esc('[201~'), 'paste bracketed');
  Check(ProcessPaste('', Md) = Esc('[200~') + Esc('[201~'), 'paste bracketed empty');
  Check(ProcessPaste('a'#13#10'b', Md) = Esc('[200~a'#13#10'b') + Esc('[201~'), 'paste lines');
  Md.FocusReporting := True;
  Check(ProcessFocus(True, Md) = Esc('[I'), 'focus in');
  Check(ProcessFocus(False, Md) = Esc('[O'), 'focus out');
end;

procedure TestDefaults;
var
  Md: TVtInputModes;
  St: TVtMouseState;
begin
  Md := DefaultInputModes;
  Check(not Md.CursorKeysApplication, 'default cursor keys');
  Check(not Md.KeypadApplication, 'default keypad');
  Check(Md.MouseTracking = vtTrackOff, 'default tracking');
  Check(Md.MouseEncoding = vtEncDefault, 'default encoding');
  Check(not Md.BracketedPaste, 'default paste');
  Check(not Md.FocusReporting, 'default focus');
  St := NewMouseState;
  Check((St.Col = -1) and (St.Row = -1) and (St.Buttons = 0), 'new mouse state');
end;

begin
  TestDefaults;
  TestConversions;
  TestCursorKeys;
  TestEditingKeys;
  TestFunctionKeys;
  TestControlKeys;
  TestTextKeys;
  TestControlLetters;
  TestUnicharAndKeyBytes;
  TestKeypad;
  TestWheelArrows;
  TestMouseOffAndX10;
  TestMouseNormal;
  TestMouseLimits;
  TestMouseSgr;
  TestMouseMotion;
  TestPasteAndFocus;
  Done;
end.
