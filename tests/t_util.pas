{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/util.h, source/tvision/drivers2.cpp, source/tvision/tvtext2.cpp,
  source/tvision/newstr.cpp, source/tvision/fmtstr.cpp, source/tvision/misc.cpp
  See COPYRIGHT.magiblot. }
program t_util;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  TvKeys, TvEvents, TvUtil;

{$I testlib.inc}

const
  { U+4E2D takes two columns. }
  Wide = #$E4#$B8#$AD;
  { U+0301 combines with the character before it. }
  Acute = #$CC#$81;
  { U+00E9 as typed text. }
  EAcute = #$C3#$A9;
  AltSpaceChar = #$F0;

{ A key event with the given key code and shift state and no text. }
function KeyEvent(Code, State: Word): TKeyDownEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.KeyCode := Code;
  Result.ControlKeyState := State;
end;

{ A key event that also carries a text of up to four bytes. }
function KeyEventText(Code, State: Word; const Txt: string): TKeyDownEvent;
var
  I: Integer;
begin
  Result := KeyEvent(Code, State);
  for I := 1 to Length(Txt) do
    Result.Text[I - 1] := Ord(Txt[I]);
  Result.TextLength := Length(Txt);
end;

procedure TestMinMax;
begin
  Check(Min(3, 5) = 3, 'min of two integers');
  Check(Min(5, 3) = 3, 'min with the order swapped');
  Check(Max(3, 5) = 5, 'max of two integers');
  Check(Max(5, 3) = 5, 'max with the order swapped');
  Check(Min(-1, 1) = -1, 'min of a negative value');
  Check(Max(Int64(1) shl 40, 7) = Int64(1) shl 40, 'max of large values');
  Check(Min(Int64(1) shl 40, 7) = 7, 'min of large values');
  Check(Max(4, 4) = 4, 'max of equal values');
end;

procedure TestAltCodes;
var
  C: Char;
begin
  Check(GetAltCode('Q') = kbAltQ, 'alt code of Q');
  Check(GetAltCode('A') = kbAltA, 'alt code of A');
  Check(GetAltCode('Z') = kbAltZ, 'alt code of Z');
  Check(GetAltCode('M') = kbAltM, 'alt code of M');
  Check(GetAltCode('a') = kbAltA, 'alt code of a lower case letter');
  Check(GetAltCode('x') = kbAltX, 'alt code of x');
  Check(GetAltCode('1') = $7800, 'alt code of 1');
  Check(GetAltCode('9') = $8000, 'alt code of 9');
  Check(GetAltCode('0') = $8100, 'alt code of 0');
  Check(GetAltCode('-') = $8200, 'alt code of minus');
  Check(GetAltCode('=') = $8300, 'alt code of equals');
  Check(GetAltCode(AltSpaceChar) = kbAltSpace, 'alt code of the space-bar character');
  Check(GetAltCode(#0) = 0, 'alt code of a zero');
  Check(GetAltCode('!') = 0, 'alt code of a character without key');
  Check(GetAltCode(' ') = 0, 'alt code of a plain space');
  Check(GetAltCode(#$80) = 0, 'alt code of a high character');

  for C := 'A' to 'Z' do
  begin
    Check(GetAltChar(GetAltCode(C)) = C, 'alt round trip of ' + C);
    Check(GetAltCode(Chr(Ord(C) or $20)) = GetAltCode(C), 'alt code ignores the case of ' + C);
  end;
  for C := '0' to '9' do
    Check(GetAltChar(GetAltCode(C)) = C, 'alt round trip of ' + C);
  Check(GetAltChar(GetAltCode('-')) = '-', 'alt round trip of minus');
  Check(GetAltChar(GetAltCode('=')) = '=', 'alt round trip of equals');
  Check(GetAltChar(GetAltCode(AltSpaceChar)) = AltSpaceChar, 'alt round trip of the space-bar character');
end;

procedure TestAltChars;
begin
  Check(GetAltChar(kbAltQ) = 'Q', 'alt char of kbAltQ');
  Check(GetAltChar(kbAltP) = 'P', 'alt char of kbAltP');
  Check(GetAltChar(kbAltL) = 'L', 'alt char of kbAltL');
  Check(GetAltChar(kbAltX) = 'X', 'alt char of kbAltX');
  Check(GetAltChar(kbAltSpace) = AltSpaceChar, 'alt char of kbAltSpace');
  Check(GetAltChar($7800) = '1', 'alt char of the first digit');
  Check(GetAltChar($8300) = '=', 'alt char of the last key');
  Check(GetAltChar(0) = #0, 'alt char of zero');
  Check(GetAltChar($1A00) = #0, 'alt char in the gap after P');
  Check(GetAltChar($1D00) = #0, 'alt char in the gap before A');
  Check(GetAltChar($2B00) = #0, 'alt char in the gap before Z');
  Check(GetAltChar($0F00) = #0, 'alt char below the letters');
  Check(GetAltChar($3300) = #0, 'alt char above the letters');
  Check(GetAltChar($7700) = #0, 'alt char below the digits');
  Check(GetAltChar($8400) = #0, 'alt char above the digits');
  Check(GetAltChar($1E41) = #0, 'alt char of a key code with a character');
  Check(GetAltChar(kbEnter) = #0, 'alt char of enter');
end;

procedure TestAltCharStr;
begin
  Check(GetAltCharStr(KeyEvent(kbAltF, 0)) = 'F', 'alt string of a scan code');
  Check(GetAltCharStr(KeyEvent(kbAltF, kbAltShift)) = 'F', 'alt string of a scan code with the alt state');
  Check(GetAltCharStr(KeyEvent(kbAltSpace, 0)) = AltSpaceChar, 'alt string of the space bar');
  Check(GetAltCharStr(KeyEvent(0, 0)) = '', 'alt string of an empty event');
  Check(GetAltCharStr(KeyEvent($1E41, 0)) = '', 'alt string of an event with a character');
  Check(GetAltCharStr(KeyEventText(0, kbLeftAlt, EAcute)) = EAcute, 'alt string takes the text');
  Check(GetAltCharStr(KeyEventText(kbAltF, kbAltShift, 'z')) = 'z', 'the text wins over the scan code');
  Check(GetAltCharStr(KeyEventText(kbAltF, kbAltShift or kbCtrlShift, 'z')) = 'z', 'alt with ctrl takes the text');
  Check(GetAltCharStr(KeyEventText(kbAltF, 0, 'z')) = 'F', 'the text without alt is ignored');
  Check(GetAltCharStr(KeyEventText(kbAltF, kbCtrlShift, 'z')) = 'F', 'the text with ctrl only is ignored');
  Check(GetAltCharStr(KeyEventText($0041, kbAltShift, Wide)) = Wide, 'alt string takes a three byte text');
  Check(GetAltCharStr(KeyEventText(0, kbAltShift, '')) = '', 'alt with an empty text');
end;

procedure TestCtrlCodes;
var
  C: Char;
  Code: Word;
begin
  Check(GetCtrlCode(Ord('A')) = (kbAltA or 1), 'ctrl code of A');
  Check(GetCtrlCode(Ord('a')) = (kbAltA or 1), 'ctrl code of a');
  Check(GetCtrlCode(Ord('Z')) = (kbAltZ or 26), 'ctrl code of Z');
  Check(GetCtrlCode(Ord('z')) = (kbAltZ or 26), 'ctrl code of z');
  Check(GetCtrlCode(Ord('M')) = (kbAltM or 13), 'ctrl code of M');
  Check(GetCtrlCode(0) = $FFC0, 'ctrl code of zero');
  Check(GetCtrlCode(Ord('1')) = $FFF1, 'ctrl code of a digit');
  Check(GetCtrlCode(Ord('[')) = 27, 'ctrl code of a bracket');

  for C := 'A' to 'Z' do
  begin
    Code := GetCtrlCode(Ord(C));
    Check((Code and $FF) = Ord(C) - Ord('A') + 1, 'ctrl low byte of ' + C);
    Check((Code and $FF00) = GetAltCode(C), 'ctrl high byte of ' + C);
    Check(GetCtrlChar(Code) = C, 'ctrl round trip of ' + C);
    Check(GetCtrlCode(Ord(C) or $20) = Code, 'ctrl code ignores the case of ' + C);
  end;
end;

procedure TestCtrlChars;
begin
  Check(GetCtrlChar(kbCtrlA) = 'A', 'ctrl char of kbCtrlA');
  Check(GetCtrlChar(kbCtrlS) = 'S', 'ctrl char of kbCtrlS');
  Check(GetCtrlChar(kbCtrlZ) = 'Z', 'ctrl char of kbCtrlZ');
  Check(GetCtrlChar(kbEnter) = 'M', 'ctrl char of enter');
  Check(GetCtrlChar(kbTab) = 'I', 'ctrl char of tab');
  Check(GetCtrlChar(kbBack) = 'H', 'ctrl char of backspace');
  Check(GetCtrlChar(0) = #0, 'ctrl char of zero');
  Check(GetCtrlChar($001B) = #0, 'ctrl char above Z');
  Check(GetCtrlChar($0041) = #0, 'ctrl char of a letter');
  Check(GetCtrlChar(kbAltA) = #0, 'ctrl char of an alt code');
  Check(GetCtrlChar($FF01) = 'A', 'the scan code does not matter');
end;

procedure TestCtrlCharStr;
begin
  Check(GetCtrlCharStr(KeyEvent(kbCtrlB, 0)) = 'B', 'ctrl string of a control character');
  Check(GetCtrlCharStr(KeyEvent(kbCtrlB, kbCtrlShift)) = 'B', 'ctrl string with the ctrl state');
  Check(GetCtrlCharStr(KeyEvent(0, kbCtrlShift)) = '', 'ctrl string of an empty event');
  Check(GetCtrlCharStr(KeyEvent($001B, 0)) = '', 'ctrl string above Z');
  Check(GetCtrlCharStr(KeyEventText(kbCtrlB, kbCtrlShift, 'q')) = 'q', 'ctrl string takes the text');
  Check(GetCtrlCharStr(KeyEventText(kbCtrlB, kbLeftCtrl, EAcute)) = EAcute, 'ctrl string takes a two byte text');
  Check(GetCtrlCharStr(KeyEventText(kbCtrlB, 0, 'q')) = 'B', 'the text without ctrl is ignored');
  Check(GetCtrlCharStr(KeyEventText(kbCtrlB, kbCtrlShift or kbAltShift, 'q')) = 'B', 'the text with alt is ignored');
  Check(GetCtrlCharStr(KeyEventText(kbCtrlB, kbAltShift, 'q')) = 'B', 'the text with alt only is ignored');
  Check(GetCtrlCharStr(KeyEventText($0041, kbCtrlShift or kbAltShift, 'q')) = '', 'alt and ctrl with a letter');
  Check(GetCtrlCharStr(KeyEventText(0, kbCtrlShift, '')) = '', 'ctrl with an empty text');
end;

procedure TestCstrlen;
begin
  Check(Cstrlen('') = 0, 'length of an empty string');
  Check(Cstrlen('File') = 4, 'length of a plain string');
  Check(Cstrlen('~F~ile') = 4, 'length with a hot key');
  Check(Cstrlen('~F~ile ~a~s') = 7, 'length with two hot keys');
  Check(Cstrlen('~') = 0, 'length of one tilde');
  Check(Cstrlen('~~') = 0, 'length of two tildes');
  Check(Cstrlen('~abc') = 3, 'length with an unclosed tilde');
  Check(Cstrlen('a~b~c') = 3, 'length with a tilde pair inside');
  Check(Cstrlen('~Alt-X~ Exit') = 10, 'length of a status line text');
  Check(Cstrlen('~F~' + Wide) = 3, 'length with a wide character');
  Check(Cstrlen(Wide + '~x~' + Wide) = 5, 'length with wide characters around a hot key');
  Check(Cstrlen('e' + Acute) = 1, 'length with a combining character');
  Check(Cstrlen('~e~' + Acute) = 1, 'length of a hot key with a combining character');
  Check(Cstrlen(Wide + Wide) = 4, 'length of two wide characters');
end;

procedure TestStrwidth;
begin
  Check(Strwidth('') = 0, 'width of an empty string');
  Check(Strwidth('abc') = 3, 'width of a plain string');
  Check(Strwidth(Wide) = 2, 'width of a wide character');
  Check(Strwidth('a' + Wide + 'b') = 4, 'width of a mixed string');
  Check(Strwidth('~a~') = 3, 'width counts the tildes');
  Check(Strwidth('e' + Acute) = 1, 'width of a combining character');
  Check(Strwidth(Wide + Wide + Wide) = 6, 'width of three wide characters');
end;

procedure TestNewStr;
var
  P: PAnsiChar;
  Src: string;
begin
  P := NewStr('abc');
  Check(P <> nil, 'a string gives a block');
  Check((P[0] = 'a') and (P[1] = 'b') and (P[2] = 'c') and (P[3] = #0), 'the block holds the string and a zero');
  FreeMem(P);

  P := NewStr('');
  Check(P <> nil, 'an empty string gives a block');
  Check(P[0] = #0, 'the block of an empty string is a zero');
  FreeMem(P);

  Src := 'abcdef';
  P := NewStr(PAnsiChar(@Src[1]), 4);
  Check((P[0] = 'a') and (P[3] = 'd') and (P[4] = #0), 'a pointer and a size give a copy of that size');
  Check(P <> PAnsiChar(@Src[1]), 'the copy is a new block');
  Src := 'xyz';
  Check(P[0] = 'a', 'the copy does not follow the source');
  FreeMem(P);

  P := NewStr(nil, 0);
  Check(P = nil, 'a nil pointer gives nil');
  P := NewStr(nil, 5);
  Check(P = nil, 'a nil pointer with a size gives nil');

  Src := 'a'#0'b';
  P := NewStr(PAnsiChar(@Src[1]), Length(Src));
  Check((P[0] = 'a') and (P[1] = #0) and (P[2] = 'b') and (P[3] = #0), 'a zero inside is copied');
  FreeMem(P);

  P := NewStr(PAnsiChar(@Src[1]), 0);
  Check((P <> nil) and (P[0] = #0), 'a size of zero gives a block with a zero');
  FreeMem(P);
end;

procedure TestFormatStr;
begin
  Check(FormatStr('no specifiers', []) = 'no specifiers', 'format without specifiers');
  Check(FormatStr('%d items', [5]) = '5 items', 'format with a number');
  Check(FormatStr('%s-%s', ['a', 'b']) = 'a-b', 'format with two strings');
  Check(FormatStr('[%5d]', [42]) = '[   42]', 'format with a width');
  Check(FormatStr('%d%%', [50]) = '50%', 'format with a percent sign');
  Check(FormatStr('', []) = '', 'format of an empty string');
  Check(FormatStr('%s', ['Error in picture format.']) = 'Error in picture format.', 'format with a message');
  Check(FormatStr('%d', []) = '%d', 'a failed format gives the format');
  Check(FormatStr('%s %s', ['one']) = '%s %s', 'too few arguments give the format');
  Check(VFormatStr('%d of %d', [1, 2]) = '1 of 2', 'vformat with numbers');
  Check(VFormatStr('%s', ['x']) = 'x', 'vformat with a string');
  Check(VFormatStr('%d', []) = '%d', 'a failed vformat gives the format');
end;

procedure TestStrnzcpy;
var
  Dst: string;
  N: SizeInt;
begin
  Dst := 'old';
  N := Strnzcpy(Dst, 'abc', 10);
  Check((N = 3) and (Dst = 'abc'), 'a text that fits is copied whole');
  N := Strnzcpy(Dst, 'abcdef', 4);
  Check((N = 3) and (Dst = 'abc'), 'a text is cut to the size less one');
  N := Strnzcpy(Dst, 'abc', 3);
  Check((N = 2) and (Dst = 'ab'), 'a text of the size of the buffer loses its last character');
  N := Strnzcpy(Dst, 'abcd', 5);
  Check((N = 4) and (Dst = 'abcd'), 'a text of the size less one is copied whole');
  N := Strnzcpy(Dst, 'abc', 1);
  Check((N = 0) and (Dst = ''), 'a buffer of one character holds the empty text');
  Dst := 'keep';
  N := Strnzcpy(Dst, 'abc', 0);
  Check((N = 0) and (Dst = 'keep'), 'a buffer of no character is not changed');
  Dst := 'x';
  N := Strnzcpy(Dst, '', 5);
  Check((N = 0) and (Dst = ''), 'the empty text replaces the old text');
  Dst := 'longer text';
  N := Strnzcpy(Dst, 'ab', 20);
  Check((N = 2) and (Dst = 'ab'), 'the old text is replaced, not overwritten in part');
  N := Strnzcpy(Dst, 'a'#0'b', 10);
  Check((N = 3) and (Dst = 'a'#0'b'), 'a zero inside the text is copied');
end;

procedure TestStrnzcat;
var
  Dst: string;
  N: SizeInt;
begin
  Dst := 'ab';
  N := Strnzcat(Dst, 'cd', 10);
  Check((N = 4) and (Dst = 'abcd'), 'a text that fits is appended whole');
  Dst := 'ab';
  N := Strnzcat(Dst, 'cdef', 5);
  Check((N = 4) and (Dst = 'abcd'), 'the appended text is cut to the room that is left');
  Dst := 'abcd';
  N := Strnzcat(Dst, 'ef', 5);
  Check((N = 4) and (Dst = 'abcd'), 'nothing is appended to a full buffer');
  Dst := '';
  N := Strnzcat(Dst, 'xyz', 3);
  Check((N = 2) and (Dst = 'xy'), 'a text is appended to the empty text up to the size less one');
  Dst := 'ab';
  N := Strnzcat(Dst, 'cd', 0);
  Check((N = 0) and (Dst = 'ab'), 'a buffer of no character is not changed');
  Dst := 'ab';
  N := Strnzcat(Dst, '', 10);
  Check((N = 2) and (Dst = 'ab'), 'the empty text appends nothing');
  Dst := 'ab'#0'cd';
  N := Strnzcat(Dst, 'X', 10);
  Check((N = 3) and (Dst = 'abX'), 'the text is appended at the first zero character');
  Dst := 'abcdef';
  N := Strnzcat(Dst, 'X', 4);
  Check((N = 3) and (Dst = 'abc'), 'a text that is longer than the buffer holds is cut and nothing is appended');
  Dst := '';
  N := Strnzcpy(Dst, 'abc', 10);
  N := Strnzcat(Dst, 'def', 10);
  Check((N = 6) and (Dst = 'abcdef'), 'Strnzcat goes on after Strnzcpy');
  N := Strnzcat(Dst, 'ghijkl', 10);
  Check((N = 9) and (Dst = 'abcdefghi'), 'the last append stops at the size less one');
end;

begin
  TestMinMax;
  TestAltCodes;
  TestAltChars;
  TestAltCharStr;
  TestCtrlCodes;
  TestCtrlChars;
  TestCtrlCharStr;
  TestCstrlen;
  TestStrwidth;
  TestNewStr;
  TestFormatStr;
  TestStrnzcpy;
  TestStrnzcat;
  Done;
end.
