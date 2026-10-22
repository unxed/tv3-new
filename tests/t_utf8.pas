{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/utf8.h, source/platform/ttext.cpp, include/tvision/ttext.h
  See COPYRIGHT.magiblot. }
program t_utf8;

{$mode objfpc}

uses
  TvUtf8;

{$I testlib.inc}

function Seq(const A: array of Byte): string;
var
  I: Integer;
begin
  SetLength(Result, Length(A));
  for I := 0 to High(A) do
    Result[I + 1] := Chr(A[I]);
end;

procedure CheckNext(const Name: string; const S: string; Expected: SizeInt);
begin
  Check(TText.Next(S) = Expected, 'next length: ' + Name);
end;

procedure CheckWidth(const Name: string; const S: string; Expected: SizeInt);
begin
  Check(TText.Width(S) = Expected, 'width: ' + Name);
end;

procedure CheckEncode(U32: Cardinal; const Expected: array of Byte; const Name: string);
var
  B: TUtf8Bytes;
  N, I: SizeInt;
  Same: Boolean;
begin
  N := Utf32To8(U32, B);
  Check(N = Length(Expected), 'encode length: ' + Name);
  Same := True;
  for I := 0 to 3 do
    if I < Length(Expected) then
    begin
      if B[I] <> Expected[I] then
        Same := False;
    end
    else if B[I] <> 0 then
      Same := False;
  Check(Same, 'encode bytes: ' + Name);
  Check(Utf8To32(Seq(Expected)) = U32, 'decode: ' + Name);
end;

var
  S: string;
  I, W, L, J: SizeInt;
  M: TTextMetrics;
  P: TUtf16Pair;
  B: TUtf8Bytes;
  N: Integer;
  Arr: array of Cardinal;

begin
  { Utf8Enabled }
  Check(Utf8Enabled, 'utf8 mode is on by default');

  { Utf8BytesLeft }
  Check(Utf8BytesLeft($41) = 0, 'bytes left of ASCII');
  Check(Utf8BytesLeft($80) = 0, 'bytes left of a continuation byte');
  Check(Utf8BytesLeft($C3) = 1, 'bytes left of C3');
  Check(Utf8BytesLeft($DF) = 1, 'bytes left of DF');
  Check(Utf8BytesLeft($E0) = 2, 'bytes left of E0');
  Check(Utf8BytesLeft($EF) = 2, 'bytes left of EF');
  Check(Utf8BytesLeft($F0) = 3, 'bytes left of F0');
  Check(Utf8BytesLeft($F7) = 3, 'bytes left of F7');
  Check(Utf8BytesLeft($F8) = 0, 'bytes left of F8');
  Check(Utf8BytesLeft($FF) = 0, 'bytes left of FF');

  { Utf32To8 and Utf8To32 }
  CheckEncode($41, [$41], 'U+0041');
  CheckEncode($7F, [$7F], 'U+007F');
  CheckEncode($80, [$C2, $80], 'U+0080');
  CheckEncode($E9, [$C3, $A9], 'U+00E9');
  CheckEncode($7FF, [$DF, $BF], 'U+07FF');
  CheckEncode($800, [$E0, $A0, $80], 'U+0800');
  CheckEncode($20AC, [$E2, $82, $AC], 'U+20AC');
  CheckEncode($FFFF, [$EF, $BF, $BF], 'U+FFFF');
  CheckEncode($10000, [$F0, $90, $80, $80], 'U+10000');
  CheckEncode($1F600, [$F0, $9F, $98, $80], 'U+1F600');
  CheckEncode($10FFFF, [$F4, $8F, $BF, $BF], 'U+10FFFF');

  { Utf16To8 and Utf32To16 }
  P[0] := $41;
  P[1] := 0;
  N := Utf16To8(P, B);
  Check((N = 1) and (B[0] = $41), 'utf16 to utf8 of a single unit');
  P[0] := $20AC;
  N := Utf16To8(P, B);
  Check((N = 3) and (B[0] = $E2) and (B[1] = $82) and (B[2] = $AC), 'utf16 to utf8 of a euro sign');
  P[0] := $D83D;
  P[1] := $DE00;
  N := Utf16To8(P, B);
  Check((N = 4) and (B[0] = $F0) and (B[1] = $9F) and (B[2] = $98) and (B[3] = $80), 'utf16 to utf8 of a surrogate pair');
  N := Utf32To16($41, P);
  Check((N = 1) and (P[0] = $41), 'utf32 to utf16 of ASCII');
  N := Utf32To16($FFFF, P);
  Check((N = 1) and (P[0] = $FFFF), 'utf32 to utf16 of U+FFFF');
  N := Utf32To16($10000, P);
  Check((N = 2) and (P[0] = $D800) and (P[1] = $DC00), 'utf32 to utf16 of U+10000');
  N := Utf32To16($1F600, P);
  Check((N = 2) and (P[0] = $D83D) and (P[1] = $DE00), 'utf32 to utf16 of U+1F600');
  N := Utf32To16($10FFFF, P);
  Check(N = -1, 'utf32 to utf16 of U+10FFFF');
  N := Utf32To16($110000, P);
  Check(N = -1, 'utf32 to utf16 beyond Unicode');

  { CharWidth }
  Check(CharWidth($00) = -1, 'char width of NUL');
  Check(CharWidth($0A) = -1, 'char width of a line feed');
  Check(CharWidth($1F) = -1, 'char width of U+001F');
  Check(CharWidth($7F) = -1, 'char width of DEL');
  Check(CharWidth($85) = -1, 'char width of a C1 control');
  Check(CharWidth($9F) = -1, 'char width of U+009F');
  Check(CharWidth($20) = 1, 'char width of a space');
  Check(CharWidth($41) = 1, 'char width of A');
  Check(CharWidth($7E) = 1, 'char width of tilde');
  Check(CharWidth($A0) = 1, 'char width of a no-break space');
  Check(CharWidth($AD) = 1, 'char width of a soft hyphen');
  Check(CharWidth($E9) = 1, 'char width of e acute');
  Check(CharWidth($20AC) = 1, 'char width of the euro sign');
  Check(CharWidth($0301) = 0, 'char width of a combining acute');
  Check(CharWidth($036F) = 0, 'char width of the last combining diacritic');
  Check(CharWidth($0E31) = 0, 'char width of a Thai vowel sign');
  Check(CharWidth($0903) = 1, 'char width of a spacing mark');
  Check(CharWidth($0600) = 0, 'char width of an Arabic format character');
  Check(CharWidth($200B) = 0, 'char width of a zero width space');
  Check(CharWidth($200D) = 0, 'char width of a zero width joiner');
  Check(CharWidth($FE0F) = 0, 'char width of a variation selector');
  Check(CharWidth($1161) = 0, 'char width of a Hangul medial vowel');
  Check(CharWidth($11FF) = 0, 'char width of a Hangul final consonant');
  Check(CharWidth($1100) = 2, 'char width of a Hangul initial consonant');
  Check(CharWidth($3000) = 2, 'char width of an ideographic space');
  Check(CharWidth($4E2D) = 2, 'char width of a CJK ideograph');
  Check(CharWidth($AC00) = 2, 'char width of a Hangul syllable');
  Check(CharWidth($FF21) = 2, 'char width of a fullwidth letter');
  Check(CharWidth($FF61) = 1, 'char width of a halfwidth punctuation mark');
  Check(CharWidth($231A) = 2, 'char width of a watch');
  Check(CharWidth($2764) = 1, 'char width of a heart');
  Check(CharWidth($1F1E6) = 1, 'char width of a regional indicator');
  Check(CharWidth($1F468) = 2, 'char width of a man emoji');
  Check(CharWidth($1F600) = 2, 'char width of a grinning face');
  Check(CharWidth($20000) = 2, 'char width of a CJK extension ideograph');
  Check(CharWidth($E000) = 1, 'char width of a private use character');
  Check(CharWidth($10FFFF) = 1, 'char width of the last code point');

  { Valid sequences }
  CheckNext('empty text', '', 0);
  CheckNext('ASCII', 'A', 1);
  CheckNext('ASCII followed by text', 'Abc', 1);
  CheckNext('control character', #$01, 1);
  CheckNext('NUL', #0, 1);
  CheckNext('two bytes', Seq([$C3, $A9]), 2);
  CheckNext('two bytes followed by text', Seq([$C3, $A9, $78]), 2);
  CheckNext('largest two bytes', Seq([$DF, $BF]), 2);
  CheckNext('smallest three bytes', Seq([$E0, $A0, $80]), 3);
  CheckNext('three bytes', Seq([$E2, $82, $AC]), 3);
  CheckNext('before the surrogates', Seq([$ED, $9F, $BF]), 3);
  CheckNext('after the surrogates', Seq([$EE, $80, $80]), 3);
  CheckNext('largest three bytes', Seq([$EF, $BF, $BF]), 3);
  CheckNext('smallest four bytes', Seq([$F0, $90, $80, $80]), 4);
  CheckNext('four bytes', Seq([$F0, $9F, $98, $80]), 4);
  CheckNext('largest code point', Seq([$F4, $8F, $BF, $BF]), 4);

  { Invalid sequences are taken one byte at a time }
  CheckNext('stray continuation byte', Seq([$80]), 1);
  CheckNext('stray continuation byte BF', Seq([$BF, $41]), 1);
  CheckNext('overlong NUL', Seq([$C0, $80]), 1);
  CheckNext('overlong slash', Seq([$C1, $BF]), 1);
  CheckNext('overlong three bytes', Seq([$E0, $80, $80]), 1);
  CheckNext('overlong three bytes, last case', Seq([$E0, $9F, $BF]), 1);
  CheckNext('overlong four bytes', Seq([$F0, $80, $80, $80]), 1);
  CheckNext('overlong four bytes, last case', Seq([$F0, $8F, $BF, $BF]), 1);
  CheckNext('surrogate D800', Seq([$ED, $A0, $80]), 1);
  CheckNext('surrogate DFFF', Seq([$ED, $BF, $BF]), 1);
  CheckNext('beyond Unicode', Seq([$F4, $90, $80, $80]), 1);
  CheckNext('lead byte F5', Seq([$F5, $80, $80, $80]), 1);
  CheckNext('five byte form', Seq([$F8, $88, $80, $80, $80]), 1);
  CheckNext('byte FE', Seq([$FE]), 1);
  CheckNext('byte FF', Seq([$FF]), 1);
  CheckNext('truncated two bytes', Seq([$C3]), 1);
  CheckNext('truncated three bytes', Seq([$E2, $82]), 1);
  CheckNext('truncated four bytes', Seq([$F0, $9F, $98]), 1);
  CheckNext('two bytes cut by ASCII', Seq([$C3, $41]), 1);
  CheckNext('three bytes cut by ASCII', Seq([$E2, $82, $41]), 1);
  CheckNext('four bytes cut by ASCII', Seq([$F0, $9F, $41]), 1);

  { Next with an index }
  S := 'a' + Seq([$C3, $A9]) + 'b';
  I := 0;
  Check(TText.Next(S, I) and (I = 1), 'next index 1');
  Check(TText.Next(S, I) and (I = 3), 'next index 2');
  Check(TText.Next(S, I) and (I = 4), 'next index 3');
  Check((not TText.Next(S, I)) and (I = 4), 'next index at the end');
  I := 0;
  W := 10;
  Check(TText.Next(S, I, W) and (I = 1) and (W = 11), 'next width 1');
  Check(TText.Next(S, I, W) and (I = 3) and (W = 12), 'next width 2');
  Check(TText.Next(S, I, W) and (I = 4) and (W = 13), 'next width 3');
  Check((not TText.Next(S, I, W)) and (I = 4) and (W = 13), 'next width at the end');
  S := Seq([$61, $CC, $81, $E4, $B8, $AD]);
  I := 0;
  W := 0;
  Check(TText.Next(S, I, W) and (I = 1) and (W = 1), 'next width of a letter');
  Check(TText.Next(S, I, W) and (I = 3) and (W = 1), 'next width of a combining mark');
  Check(TText.Next(S, I, W) and (I = 6) and (W = 3), 'next width of an ideograph');
  I := 0;
  W := 0;
  S := Seq([$80]);
  Check(TText.Next(S, I, W) and (I = 1) and (W = 1), 'next width of an invalid byte');
  S := Seq([$C2, $85]);
  I := 0;
  W := 0;
  Check(TText.Next(S, I, W) and (I = 2) and (W = 1), 'next width of a C1 control');

  { Width }
  CheckWidth('empty text', '', 0);
  CheckWidth('ASCII', 'hello', 5);
  CheckWidth('control characters', #1#2#9, 3);
  CheckWidth('e acute', Seq([$C3, $A9]), 1);
  CheckWidth('letter and combining acute', Seq([$61, $CC, $81]), 1);
  CheckWidth('two combining marks', Seq([$61, $CC, $81, $CC, $82]), 1);
  CheckWidth('combining mark first', Seq([$CC, $81]), 0);
  CheckWidth('soft hyphen', Seq([$C2, $AD]), 1);
  CheckWidth('ideograph', Seq([$E4, $B8, $AD]), 2);
  CheckWidth('two ideographs and a letter', Seq([$E4, $B8, $AD, $E4, $B8, $AD, $61]), 5);
  CheckWidth('Hangul syllable', Seq([$EA, $B0, $80]), 2);
  CheckWidth('fullwidth letter', Seq([$EF, $BC, $A1]), 2);
  CheckWidth('Hangul medial vowel', Seq([$E1, $85, $A1]), 0);
  CheckWidth('zero width joiner', Seq([$E2, $80, $8D]), 0);
  CheckWidth('emoji', Seq([$F0, $9F, $98, $80]), 2);
  CheckWidth('emoji joined by a zero width joiner', Seq([$F0, $9F, $98, $80, $E2, $80, $8D, $F0, $9F, $98, $80]), 4);
  CheckWidth('euro sign', Seq([$E2, $82, $AC]), 1);
  CheckWidth('invalid byte', Seq([$80]), 1);
  CheckWidth('overlong sequence', Seq([$C0, $80]), 2);
  CheckWidth('truncated sequence', Seq([$E2, $82]), 2);
  CheckWidth('truncated sequence cut by ASCII', Seq([$E2, $82, $41]), 3);
  CheckWidth('valid after invalid', Seq([$80, $E4, $B8, $AD]), 3);

  { Measure }
  M := TText.Measure('');
  Check((M.Width = 0) and (M.CharacterCount = 0) and (M.GraphemeCount = 0), 'measure of an empty text');
  M := TText.Measure('abc');
  Check((M.Width = 3) and (M.CharacterCount = 3) and (M.GraphemeCount = 3), 'measure of ASCII');
  M := TText.Measure(Seq([$61, $CC, $81, $E4, $B8, $AD]));
  Check((M.Width = 3) and (M.CharacterCount = 3) and (M.GraphemeCount = 2), 'measure with a combining mark');
  M := TText.Measure(Seq([$80, $E2, $82]));
  Check((M.Width = 3) and (M.CharacterCount = 3) and (M.GraphemeCount = 3), 'measure of invalid bytes');

  { Prev }
  S := 'a' + Seq([$C3, $A9]) + 'b';
  Check(TText.Prev(S, 0) = 0, 'prev at the start');
  Check(TText.Prev(S, 1) = 1, 'prev of a letter at the start');
  Check(TText.Prev(S, 3) = 2, 'prev of a two-byte character');
  Check(TText.Prev(S, 4) = 1, 'prev of a letter at the end');
  S := Seq([$E2, $82, $AC]);
  Check(TText.Prev(S, 3) = 3, 'prev of a three-byte character');
  S := Seq([$F0, $9F, $98, $80]);
  Check(TText.Prev(S, 4) = 4, 'prev of a four-byte character');
  S := 'x' + Seq([$F0, $9F, $98, $80]);
  Check(TText.Prev(S, 5) = 4, 'prev of a four-byte character after a letter');
  Check(TText.Prev(S, 1) = 1, 'prev of the letter before a four-byte character');
  S := Seq([$80, $80]);
  Check(TText.Prev(S, 2) = 1, 'prev of invalid bytes');
  S := Seq([$41, $C3]);
  Check(TText.Prev(S, 2) = 1, 'prev of a truncated sequence');
  S := Seq([$C3, $A9, $A9]);
  Check(TText.Prev(S, 3) = 1, 'prev of a stray continuation byte');
  S := Seq([$E2, $82, $41]);
  Check(TText.Prev(S, 3) = 1, 'prev of a letter after a truncated sequence');
  S := Seq([$61, $CC, $81]);
  Check(TText.Prev(S, 3) = 2, 'prev of a combining mark');

  { Scroll }
  S := 'a' + Seq([$E4, $B8, $AD]) + 'b';
  Check(TText.Scroll(S, 1, True) = 1, 'scroll 1 column');
  Check(TText.Scroll(S, 1, False) = 1, 'scroll 1 column, not including');
  Check(TText.Scroll(S, 2, True) = 4, 'scroll into a double-width character, including it');
  Check(TText.Scroll(S, 2, False) = 1, 'scroll into a double-width character, not including it');
  Check(TText.Scroll(S, 3, False) = 4, 'scroll to the end of a double-width character');
  Check(TText.Scroll(S, 4, False) = 5, 'scroll to the end of the text');
  Check(TText.Scroll(S, 10, False) = 5, 'scroll beyond the text');
  Check(TText.Scroll(S, 0, True) = 0, 'scroll 0 columns');
  Check(TText.Scroll(S, -3, True) = 0, 'scroll a negative number of columns');
  TText.Scroll(S, 2, True, L, W);
  Check((L = 4) and (W = 3), 'scroll length and width, including');
  TText.Scroll(S, 2, False, L, W);
  Check((L = 1) and (W = 1), 'scroll length and width, not including');
  TText.Scroll(S, 10, True, L, W);
  Check((L = 5) and (W = 4), 'scroll length and width beyond the text');
  TText.Scroll(S, -1, True, L, W);
  Check((L = 0) and (W = 0), 'scroll length and width of a negative count');
  TText.Scroll('', 3, True, L, W);
  Check((L = 0) and (W = 0), 'scroll of an empty text');
  S := Seq([$61, $CC, $81, $62]);
  TText.Scroll(S, 1, True, L, W);
  Check((L = 1) and (W = 1), 'scroll stops before a combining mark');
  TText.Scroll(S, 2, True, L, W);
  Check((L = 4) and (W = 2), 'scroll past a combining mark');

  { UTF-32 text }
  SetLength(Arr, 3);
  Arr[0] := $61;
  Arr[1] := $4E2D;
  Arr[2] := $62;
  I := 0;
  W := 0;
  Check(TText.Next(Arr, I, W) and (I = 1) and (W = 1), 'utf32 next 1');
  Check(TText.Next(Arr, I, W) and (I = 2) and (W = 3), 'utf32 next 2');
  Check(TText.Next(Arr, I, W) and (I = 3) and (W = 4), 'utf32 next 3');
  Check((not TText.Next(Arr, I, W)) and (I = 3) and (W = 4), 'utf32 next at the end');
  TText.Scroll(Arr, 2, True, L, W);
  Check((L = 2) and (W = 3), 'utf32 scroll, including');
  TText.Scroll(Arr, 2, False, L, W);
  Check((L = 1) and (W = 1), 'utf32 scroll, not including');
  TText.Scroll(Arr, 9, False, L, W);
  Check((L = 3) and (W = 4), 'utf32 scroll beyond the text');
  TText.Scroll(Arr, 0, False, L, W);
  Check((L = 0) and (W = 0), 'utf32 scroll of 0 columns');
  Arr[0] := $61;
  Arr[1] := $0301;
  Arr[2] := $1F600;
  I := 0;
  W := 0;
  J := 0;
  while TText.Next(Arr, I, W) do
    Inc(J);
  Check((J = 3) and (I = 3) and (W = 3), 'utf32 combining mark and emoji');
  Arr[0] := $01;
  I := 0;
  W := 0;
  TText.Next(Arr, I, W);
  Check((I = 1) and (W = 1), 'utf32 control character');
  SetLength(Arr, 0);
  I := 0;
  W := 0;
  Check((not TText.Next(Arr, I, W)) and (I = 0) and (W = 0), 'utf32 empty text');

  Done;
end.
