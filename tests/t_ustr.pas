{ Test program of the unit TvUStr. }
program t_ustr;

{$mode objfpc}

uses
  SysUtils, TvUtf8, TvUStr;

{$I testlib.inc}

const
  { six Cyrillic letters of two bytes each }
  Privet = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;
  { two wide characters of three bytes each }
  Japan = #$E6#$97#$A5#$E6#$9C#$AC;
  Acute = #$C3#$A9;
  Comb = #$CC#$81;
  Smile = #$F0#$9F#$98#$80;

procedure CheckS(const Got, Want: AnsiString; const Name: string);
begin
  Check(Got = Want, Name);
end;

procedure CheckI(Got, Want: Int64; const Name: string);
begin
  Check(Got = Want, Name + ' (got ' + IntToStr(Got) + ', want ' + IntToStr(Want) + ')');
end;

procedure ChkUp(CP, Want: LongWord);
begin
  Check(CpUpper(CP) = Want, 'upper of $' + IntToHex(CP, 4) + ' is $' + IntToHex(Want, 4));
end;

procedure ChkLo(CP, Want: LongWord);
begin
  Check(CpLower(CP) = Want, 'lower of $' + IntToHex(CP, 4) + ' is $' + IntToHex(Want, 4));
end;

{ Both mappings leave CP alone. }
procedure Fixed(CP: LongWord);
begin
  ChkUp(CP, CP);
  ChkLo(CP, CP);
end;

procedure TestIndices;
var
  T: AnsiString;
begin
  CheckI(U8Len('abc'), 3, 'len abc');
  CheckI(U8Len(Privet), 6, 'len privet');
  CheckI(U8Len('a' + Acute + Smile), 3, 'len with a 4-byte character');
  CheckI(U8Len('a'#$80'b'), 3, 'len with a stray byte');
  CheckI(U8Len('ab'#$D0), 3, 'len with a truncated sequence');
  CheckI(U8Len(''), 0, 'len empty');

  CheckI(U8Idx(Privet, 0), 1, 'idx 0');
  CheckI(U8Idx(Privet, 2), 5, 'idx 2');
  CheckI(U8Idx(Privet, 6), 13, 'idx 6');
  CheckI(U8Idx(Privet, 99), 13, 'idx 99');
  CheckI(U8Idx(Privet, -1), 1, 'idx -1');
  CheckI(U8Idx(Privet, -3), 1, 'idx -3');
  CheckI(U8Idx('', 4), 1, 'idx in an empty string');
  CheckI(U8Idx('', 0), 1, 'idx 0 in an empty string');
  T := 'a' + Acute + Smile;
  CheckI(U8Idx(T, 0), 1, 'idx mixed 0');
  CheckI(U8Idx(T, 1), 2, 'idx mixed 1');
  CheckI(U8Idx(T, 2), 4, 'idx mixed 2');
  CheckI(U8Idx(T, 3), 8, 'idx mixed 3');

  CheckI(U8Col(Privet, 5), 2, 'col 5');
  CheckI(U8Col(Privet, 6), 2, 'col 6 inside a character');
  CheckI(U8Col(Privet, 13), 6, 'col 13');
  CheckI(U8Col(Privet, 15), 8, 'col 15');
  CheckI(U8Col(Privet, 0), 0, 'col 0');
  CheckI(U8Col(Privet, 1), 0, 'col 1');
  CheckI(U8Col(Privet, 2), 0, 'col 2');
  CheckI(U8Col(Privet, 3), 1, 'col 3');
  CheckI(U8Col(Privet, -4), 0, 'col -4');

  CheckI(U8PrevIdx(Privet, 5), 3, 'previdx 5');
  CheckI(U8PrevIdx(Privet, 6), 5, 'previdx 6');
  CheckI(U8PrevIdx(Privet, 13), 11, 'previdx 13');
  CheckI(U8PrevIdx(Privet, 1), 1, 'previdx 1');
  CheckI(U8PrevIdx(Privet, 2), 1, 'previdx 2');
  CheckI(U8PrevIdx(Privet, 20), 19, 'previdx 20');
  CheckI(U8PrevIdx(Privet, 0), 1, 'previdx 0');

  CheckI(U8CharBytes(Privet, 1), 2, 'charbytes 1');
  CheckI(U8CharBytes(Privet, 2), 1, 'charbytes 2');
  CheckI(U8CharBytes(Privet, 13), 0, 'charbytes 13');
  CheckI(U8CharBytes(Privet, 0), 0, 'charbytes 0');
  CheckI(U8CharBytes(Privet, -1), 0, 'charbytes -1');
  CheckI(U8CharBytes('ab'#$D0, 3), 1, 'charbytes truncated');
  CheckI(U8CharBytes('a' + Acute + Smile, 4), 4, 'charbytes of a 4-byte character');
  CheckI(U8CharBytes(Japan, 4), 3, 'charbytes of a 3-byte character');
  CheckI(U8CharBytes('abc', 2), 1, 'charbytes ascii');

  Check(U8IsAscii(''), 'ascii empty');
  Check(U8IsAscii('abc'#0#127), 'ascii abc');
  Check(not U8IsAscii('ab' + Acute), 'not ascii');
  Check(not U8IsAscii(#$80), 'not ascii stray');
end;

procedure TestCutting;
var
  S: AnsiString;
  Sh: ShortString;
  Big: ShortString;
begin
  CheckS(U8Copy(Privet, 1, 3), #$D1#$80#$D0#$B8#$D0#$B2, 'copy 1,3');
  CheckS(U8Copy(Privet, -2, 4), #$D0#$9F#$D1#$80, 'copy -2,4');
  CheckS(U8Copy(Privet, 4, 99), #$D0#$B5#$D1#$82, 'copy 4,99');
  CheckS(U8Copy(Privet, 6, 1), '', 'copy 6,1');
  CheckS(U8Copy(Privet, 0, 0), '', 'copy 0,0');
  CheckS(U8Copy(Privet, 0, -2), '', 'copy 0,-2');
  CheckS(U8Copy(Privet, -5, 3), '', 'copy -5,3');
  CheckS(U8Copy(Privet, 0, 6), Privet, 'copy all');
  CheckS(U8Copy('', 0, 3), '', 'copy of an empty string');
  CheckS(U8Copy('abcdef', 2, 2), 'cd', 'copy ascii');
  CheckS(U8Copy('a'#$80'b', 1, 1), #$80, 'copy a stray byte');

  CheckS(U8Char(Privet, 1), #$D1#$80, 'char 1');
  CheckS(U8Char(Privet, -1), '', 'char -1');
  CheckS(U8Char(Privet, 6), '', 'char 6');
  CheckS(U8Char(Privet, 0), #$D0#$9F, 'char 0');

  S := Privet;
  U8Delete(S, 1, 2);
  CheckS(S, #$D0#$9F#$D0#$B2#$D0#$B5#$D1#$82, 'delete 1,2');
  S := Privet;
  U8Delete(S, -1, 3);
  CheckS(S, #$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82, 'delete -1,3');
  S := Privet;
  U8Delete(S, 2, 0);
  CheckS(S, Privet, 'delete count 0');
  S := Privet;
  U8Delete(S, 6, 2);
  CheckS(S, Privet, 'delete past the end');
  S := Privet;
  U8Delete(S, 4, 99);
  CheckS(S, #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2, 'delete to the end');
  S := '';
  U8Delete(S, 0, 1);
  CheckS(S, '', 'delete in an empty string');
  Sh := Privet;
  U8Delete(Sh, 0, 1);
  CheckS(Sh, #$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82, 'shortstring delete 0,1');
  Sh := Privet;
  U8Delete(Sh, 1, 2);
  CheckS(Sh, #$D0#$9F#$D0#$B2#$D0#$B5#$D1#$82, 'shortstring delete 1,2');
  Sh := Privet;
  U8Delete(Sh, 9, 2);
  CheckS(Sh, Privet, 'shortstring delete past the end');

  S := Privet;
  U8Insert('x', S, 3);
  CheckS(S, #$D0#$9F#$D1#$80#$D0#$B8'x'#$D0#$B2#$D0#$B5#$D1#$82, 'insert at 3');
  S := 'ab';
  U8Insert('x', S, 99);
  CheckS(S, 'abx', 'insert past the end');
  S := '';
  U8Insert('x', S, 5);
  CheckS(S, 'x', 'insert into an empty string');
  S := '';
  U8Insert('x', S, 0);
  CheckS(S, 'x', 'insert into an empty string at 0');
  S := 'ab';
  U8Insert('x', S, -4);
  CheckS(S, 'xab', 'insert at a negative column');
  S := Privet;
  U8Insert('x', S, 6);
  CheckS(S, Privet + 'x', 'insert at the number of columns');
  Sh := Privet;
  U8Insert('x', Sh, 3);
  CheckS(Sh, #$D0#$9F#$D1#$80#$D0#$B8'x'#$D0#$B2#$D0#$B5#$D1#$82, 'shortstring insert at 3');
  Sh := 'ab';
  U8Insert('x', Sh, 99);
  CheckS(Sh, 'abx', 'shortstring insert past the end');
  Big := StringOfChar('a', 250);
  U8Insert(StringOfChar('b', 20), Big, 0);
  Check((Length(Big) = 255) and (Big[20] = 'b') and (Big[21] = 'a') and (Big[255] = 'a'),
    'shortstring insert is cut at 255 bytes');

  CheckI(Ord(U8ColChar(Privet, 1)), $D1, 'colchar 1');
  CheckI(Ord(U8ColChar('ab', 2)), 32, 'colchar past the end');
  CheckI(Ord(U8ColChar('ab', -1)), 32, 'colchar negative');
  CheckI(Ord(U8ColChar('ab', 1)), Ord('b'), 'colchar ascii');
  CheckI(Ord(U8ColChar('', 0)), 32, 'colchar of an empty string');
end;

procedure TestCodePoints;
const
  RoundCases: array[0..6] of LongWord = ($7F, $80, $7FF, $800, $FFFF, $10000, $10FFFF);
var
  I: Integer;
begin
  CheckI(U8CodePoint(Privet, 1), $440, 'codepoint letter');
  CheckI(U8CodePoint('a'#$80, 1), $80, 'codepoint stray byte');
  CheckI(U8CodePoint('a', 5), 0, 'codepoint past the end');
  CheckI(U8CodePoint('a', -1), 0, 'codepoint negative');
  CheckI(U8CodePoint('a', 0), $61, 'codepoint ascii');
  CheckI(U8CodePoint(Japan, 0), $65E5, 'codepoint 3-byte');
  CheckI(U8CodePoint(Japan, 1), $672C, 'codepoint second 3-byte');
  CheckI(U8CodePoint('a' + Smile, 1), $1F600, 'codepoint 4-byte');
  CheckI(U8CodePoint('a'#0'b', 1), 0, 'codepoint of a NUL');

  CheckS(U8Encode($41), 'A', 'encode 41');
  CheckS(U8Encode($439), #$D0#$B9, 'encode 439');
  CheckS(U8Encode($20AC), #$E2#$82#$AC, 'encode 20AC');
  CheckS(U8Encode($1F600), Smile, 'encode 1F600');
  CheckS(U8Encode(0), #0, 'encode 0');
  CheckI(Length(U8Encode(0)), 1, 'encode 0 length');
  CheckS(U8Encode($7F), #$7F, 'encode 7F');
  CheckS(U8Encode($80), #$C2#$80, 'encode 80');
  CheckS(U8Encode($7FF), #$DF#$BF, 'encode 7FF');
  CheckS(U8Encode($800), #$E0#$A0#$80, 'encode 800');
  CheckS(U8Encode($FFFF), #$EF#$BF#$BF, 'encode FFFF');
  CheckS(U8Encode($10000), #$F0#$90#$80#$80, 'encode 10000');
  CheckS(U8Encode($10FFFF), #$F4#$8F#$BF#$BF, 'encode 10FFFF');
  for I := 0 to High(RoundCases) do
  begin
    CheckI(U8CodePoint(U8Encode(RoundCases[I]), 0), RoundCases[I], 'round trip $' + IntToHex(RoundCases[I], 4));
    CheckI(U8Len(U8Encode(RoundCases[I])), 1, 'one column for $' + IntToHex(RoundCases[I], 4));
  end;
end;

procedure TestPrefixAndLast;
var
  S: AnsiString;
  Sh: ShortString;
begin
  CheckS(U8Prefix(Privet, 5), #$D0#$9F#$D1#$80, 'prefix 5');
  CheckS(U8Prefix(Privet, 4), #$D0#$9F#$D1#$80, 'prefix 4');
  CheckS(U8Prefix(Privet, 99), Privet, 'prefix 99');
  CheckS(U8Prefix(Privet, 0), '', 'prefix 0');
  CheckS(U8Prefix(Privet, -1), '', 'prefix -1');
  CheckS(U8Prefix(Privet, 12), Privet, 'prefix the whole length');
  CheckS(U8Prefix('abc', 2), 'ab', 'prefix ascii');
  CheckS(U8Prefix('a'#$80#$80'b', 2), '', 'prefix with stray bytes');
  CheckS(U8Prefix('ab' + Acute, 3), 'ab', 'prefix before a character');
  CheckS(U8Prefix('ab' + Acute, 4), 'ab' + Acute, 'prefix up to a character');
  CheckS(U8Prefix('', 3), '', 'prefix of an empty string');

  S := Privet;
  U8DeleteLast(S);
  CheckS(S, #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5, 'deletelast privet');
  S := 'ab';
  U8DeleteLast(S);
  CheckS(S, 'a', 'deletelast ab');
  S := 'a' + Acute;
  U8DeleteLast(S);
  CheckS(S, 'a', 'deletelast acute');
  S := 'ab'#$D0;
  U8DeleteLast(S);
  CheckS(S, 'ab', 'deletelast truncated');
  S := 'a'#$80;
  U8DeleteLast(S);
  CheckS(S, '', 'deletelast stray');
  S := '';
  U8DeleteLast(S);
  CheckS(S, '', 'deletelast empty');
  S := 'a' + Smile;
  U8DeleteLast(S);
  CheckS(S, 'a', 'deletelast 4-byte');

  Sh := Privet;
  U8DeleteLast(Sh);
  CheckS(Sh, #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5, 'shortstring deletelast privet');
  Sh := 'ab';
  U8DeleteLast(Sh);
  CheckS(Sh, 'a', 'shortstring deletelast ab');
  Sh := 'a' + Acute;
  U8DeleteLast(Sh);
  CheckS(Sh, 'a', 'shortstring deletelast acute');
  Sh := 'a'#$80;
  U8DeleteLast(Sh);
  CheckS(Sh, '', 'shortstring deletelast stray');
  Sh := '';
  U8DeleteLast(Sh);
  CheckS(Sh, '', 'shortstring deletelast empty');
end;

{ Every byte of Bad is its own column and U8Upper keeps the bytes but for ASCII letters. }
procedure CheckInvalid(const Bad: AnsiString; const Name: string);
var
  I: Integer;
begin
  CheckI(U8Len(Bad), Length(Bad), 'invalid len: ' + Name);
  for I := 1 to Length(Bad) do
  begin
    CheckI(U8CharBytes(Bad, I), 1, 'invalid charbytes ' + IntToStr(I) + ': ' + Name);
    CheckI(U8CodePoint(Bad, I - 1), Ord(Bad[I]), 'invalid codepoint ' + IntToStr(I) + ': ' + Name);
    CheckI(U8Idx(Bad, I - 1), I, 'invalid idx ' + IntToStr(I) + ': ' + Name);
  end;
  CheckS(U8Upper(Bad), Bad, 'invalid upper: ' + Name);
  CheckS(U8Lower(Bad), Bad, 'invalid lower: ' + Name);
end;

procedure TestInvalid;
begin
  CheckInvalid(#$C0#$80, 'overlong two bytes');
  CheckInvalid(#$C1#$BF, 'overlong C1');
  CheckInvalid(#$E0#$80#$80, 'overlong three bytes');
  CheckInvalid(#$ED#$A0#$80, 'surrogate');
  CheckInvalid(#$F4#$90#$80#$80, 'above 10FFFF');
  CheckInvalid(#$F5#$80#$80#$80, 'F5 lead');
  CheckInvalid(#$FF#$FE, 'FF FE');
  CheckInvalid(#$80, 'lone continuation byte');
  CheckInvalid(#$E2#$82, 'truncated three bytes');
  CheckInvalid(#$F0#$9F#$98, 'truncated four bytes');
  CheckInvalid(#$D0, 'lone lead byte');
  CheckInvalid(#$E2#$82'1', 'truncated three bytes then ASCII');
  CheckInvalid(#$D0'1', 'lead then ASCII');
  CheckInvalid(#$E0#$9F#$BF, 'E0 with a low second byte');
  CheckInvalid(#$F0#$8F#$BF#$BF, 'F0 with a low second byte');
  CheckS(U8Upper(#$E2#$82'a'), #$E2#$82'A', 'upper after a truncated sequence');
  CheckS(U8Upper('a'#$80'b'), 'A'#$80'B', 'upper around a stray byte');
  CheckS(U8Upper('ab'#$D0), 'AB'#$D0, 'upper before a truncated lead');

  { the edges of the valid sequences }
  CheckI(U8Len(#$C2#$80), 1, 'valid C2 80');
  CheckI(U8Len(#$DF#$BF), 1, 'valid DF BF');
  CheckI(U8Len(#$E0#$A0#$80), 1, 'valid E0 A0 80');
  CheckI(U8Len(#$ED#$9F#$BF), 1, 'valid ED 9F BF');
  CheckI(U8Len(#$EE#$80#$80), 1, 'valid EE 80 80');
  CheckI(U8Len(#$F0#$90#$80#$80), 1, 'valid F0 90 80 80');
  CheckI(U8Len(#$F4#$8F#$BF#$BF), 1, 'valid F4 8F BF BF');
  CheckI(U8CodePoint(#$ED#$9F#$BF, 0), $D7FF, 'codepoint before the surrogates');
  CheckI(U8CodePoint(#$EE#$80#$80, 0), $E000, 'codepoint after the surrogates');
end;

procedure TestCells;
var
  T: AnsiString;
begin
  CheckI(U8Cols(Japan), 4, 'cols japan');
  CheckI(U8Cols('a' + Japan), 5, 'cols a+japan');
  CheckI(U8Cols('a' + Comb), 1, 'cols a+comb');
  CheckI(U8Cols(''), 0, 'cols empty');
  CheckI(U8Cols(Privet), 6, 'cols privet');
  CheckI(U8Cols(#$C2#$85), 1, 'cols of a C1 control');
  CheckI(U8Cols('a'#1#$7F), 3, 'cols of ASCII controls');
  CheckI(U8Cols('a'#$80'b'), 3, 'cols with a stray byte');

  CheckI(U8Cells(Japan, 1, 1), 2, 'cells japan 1,1');
  CheckI(U8Cells('ab', 1, 3), 3, 'cells past the end');
  CheckI(U8Cells('a' + Japan, 0, 2), 3, 'cells a+japan 0,2');
  CheckI(U8Cells('a' + Comb + 'b', 0, 3), 2, 'cells with a combining mark');
  CheckI(U8Cells(Japan, 2, 3), 3, 'cells japan 2,3');
  CheckI(U8Cells(Japan, 0, 0), 0, 'cells count 0');
  CheckI(U8Cells(Japan, 0, -3), 0, 'cells negative count');
  CheckI(U8Cells(Japan, -1, 1), 2, 'cells negative column starts at 0');
  CheckI(U8Cells('abc', 7, 2), 2, 'cells ascii ignores the column');
  CheckI(U8Cells(#$C2#$85, 0, 1), 1, 'cells of a C1 control');

  T := 'a' + Japan + 'b';
  CheckI(U8ColAtCell(T, 2), 1, 'colatcell 2');
  CheckI(U8ColAtCell(T, 4), 2, 'colatcell 4');
  CheckI(U8ColAtCell(T, 1), 1, 'colatcell 1');
  CheckI(U8ColAtCell(T, 3), 2, 'colatcell 3');
  CheckI(U8ColAtCell(T, 5), 3, 'colatcell 5');
  CheckI(U8ColAtCell(T, 6), 4, 'colatcell 6');
  CheckI(U8ColAtCell(T, 9), 7, 'colatcell 9');
  CheckI(U8ColAtCell(T, 0), 0, 'colatcell 0');
  CheckI(U8ColAtCell(T, -3), 0, 'colatcell -3');
  CheckI(U8ColAtCell('ab', 5), 5, 'colatcell ascii past the end');
  CheckI(U8ColAtCell('a' + Comb + 'b', 1), 2, 'colatcell skips a combining mark');
  CheckI(U8ColAtCell('a' + Comb + 'b', 0), 0, 'colatcell on the base character');
  CheckI(U8ColAtCell(Acute, 5), 5, 'colatcell excess rule');
  CheckI(U8ColAtCell('a' + Comb, 1), 2, 'colatcell at the total with a trailing mark');

  CheckS(U8Pad(Japan, 6), Japan + '  ', 'pad japan 6');
  CheckS(U8Pad(Japan, 2), Japan, 'pad japan 2');
  CheckS(U8Pad('ab', 1), 'ab', 'pad ab 1');
  CheckS(U8Pad('', 3), '   ', 'pad empty');
  CheckS(U8Pad('x', 0), 'x', 'pad x 0');
  CheckS(U8Pad('x', -2), 'x', 'pad negative');
  CheckS(U8Pad(Privet, 8), Privet + '  ', 'pad privet');

  CheckS(U8Fit('a' + Japan, 2), 'a', 'fit a+japan 2');
  CheckS(U8Fit('a' + Japan, 3), 'a'#$E6#$97#$A5, 'fit a+japan 3');
  CheckS(U8Fit('a' + Japan, 5), 'a' + Japan, 'fit a+japan 5');
  CheckS(U8Fit(Japan, 1), '', 'fit japan 1');
  CheckS(U8Fit('a' + Comb + 'b', 1), 'a' + Comb, 'fit keeps a combining mark');
  CheckS(U8Fit('abc', 2), 'ab', 'fit abc 2');
  CheckS(U8Fit('abc', 0), '', 'fit abc 0');
  CheckS(U8Fit('abc', -1), '', 'fit abc -1');
  CheckS(U8Fit('abc', 9), 'abc', 'fit abc 9');
  CheckS(U8Fit(Privet, 3), #$D0#$9F#$D1#$80#$D0#$B8, 'fit privet 3');
  CheckS(U8Fit('a' + Japan + 'b', 3), 'a' + #$E6#$97#$A5, 'fit stops at the first column that does not fit');
  CheckS(U8Fit(Japan + 'b', 1), '', 'fit does not skip a wide character');
end;

procedure TestCaseValues;
begin
  ChkUp($3C2, $3A3);
  ChkLo($130, $69);
  ChkUp($45F, $40F);
  ChkUp($E9, $C9);
  ChkUp($FF, $178);
  ChkLo($178, $FF);
  ChkUp($101, $100);
  ChkLo($100, $101);
  ChkUp($148, $147);
  ChkLo($147, $148);
  ChkUp($17E, $17D);
  ChkLo($179, $17A);
  ChkLo($138, $138);
  ChkUp($DF, $DF);
  ChkUp($3CE, $38F);
  ChkLo($38F, $3CE);
  ChkUp($44F, $42F);
  ChkUp($561, $531);
  ChkUp($1E01, $1E00);
  ChkLo($1E9E, $1E9E);
  ChkUp($4CF, $4C0);
  ChkLo($4C0, $4CF);
  ChkUp($4C2, $4C1);
  ChkUp($FF41, $FF21);
  ChkUp($10D0, $10D0);
  ChkUp($B5, $39C);
  ChkLo($39C, $3BC);
  ChkUp($131, $49);
  ChkUp($17F, $53);
  ChkUp($1CE, $1CD);
  ChkLo($1CD, $1CE);

  { boundaries of the upper-case ranges }
  ChkUp($60, $60); ChkUp($61, $41); ChkUp($7A, $5A); ChkUp($7B, $7B);
  ChkUp($B4, $B4); ChkUp($B6, $B6);
  ChkUp($E0, $C0); ChkUp($F6, $D6); ChkUp($F7, $F7); ChkUp($F8, $D8); ChkUp($FE, $DE);
  ChkUp($100, $100); ChkUp($12F, $12E); ChkUp($130, $130); ChkUp($132, $132); ChkUp($133, $132); ChkUp($137, $136);
  ChkUp($138, $138); ChkUp($139, $139); ChkUp($13A, $139); ChkUp($148, $147); ChkUp($149, $149);
  ChkUp($14A, $14A); ChkUp($14B, $14A); ChkUp($177, $176); ChkUp($178, $178); ChkUp($179, $179); ChkUp($17A, $179);
  ChkUp($180, $180); ChkUp($1CD, $1CD);
  ChkUp($1E00, $1E00); ChkUp($1E95, $1E94); ChkUp($1E96, $1E96); ChkUp($1E9E, $1E9E); ChkUp($1E9F, $1E9F);
  ChkUp($1EA0, $1EA0); ChkUp($1EA1, $1EA0); ChkUp($1EFF, $1EFE); ChkUp($1F00, $1F00);
  ChkUp($3AB, $3AB); ChkUp($3AC, $386); ChkUp($3AD, $388); ChkUp($3AF, $38A); ChkUp($3B0, $3B0);
  ChkUp($3B1, $391); ChkUp($3C1, $3A1); ChkUp($3C3, $3A3); ChkUp($3CB, $3AB); ChkUp($3CC, $38C);
  ChkUp($3CD, $38E); ChkUp($3CF, $3CF);
  ChkUp($42F, $42F); ChkUp($430, $410); ChkUp($450, $400); ChkUp($460, $460); ChkUp($461, $460);
  ChkUp($481, $480); ChkUp($482, $482); ChkUp($489, $489); ChkUp($48A, $48A); ChkUp($48B, $48A);
  ChkUp($4BF, $4BE); ChkUp($4C0, $4C0); ChkUp($4C1, $4C1); ChkUp($4CE, $4CD);
  ChkUp($4D0, $4D0); ChkUp($4D1, $4D0); ChkUp($52F, $52E); ChkUp($530, $530);
  ChkUp($560, $560); ChkUp($586, $556); ChkUp($587, $587);
  ChkUp($216F, $216F); ChkUp($2170, $2160); ChkUp($217F, $216F); ChkUp($2180, $2180);
  ChkUp($24CF, $24CF); ChkUp($24D0, $24B6); ChkUp($24E9, $24CF); ChkUp($24EA, $24EA);
  ChkUp($FF40, $FF40); ChkUp($FF5A, $FF3A); ChkUp($FF5B, $FF5B);
  ChkUp($10000, $10000); ChkUp($1D41A, $1D41A); ChkUp($10FFFF, $10FFFF); ChkUp($FFFFFFFF, $FFFFFFFF);

  { boundaries of the lower-case ranges }
  ChkLo($40, $40); ChkLo($41, $61); ChkLo($5A, $7A); ChkLo($5B, $5B);
  ChkLo($BF, $BF); ChkLo($C0, $E0); ChkLo($D6, $F6); ChkLo($D7, $D7); ChkLo($D8, $F8); ChkLo($DE, $FE); ChkLo($DF, $DF);
  ChkLo($100, $101); ChkLo($101, $101); ChkLo($12E, $12F); ChkLo($12F, $12F); ChkLo($131, $131);
  ChkLo($132, $133); ChkLo($136, $137); ChkLo($137, $137); ChkLo($139, $13A); ChkLo($13A, $13A);
  ChkLo($147, $148); ChkLo($148, $148); ChkLo($149, $149); ChkLo($14A, $14B); ChkLo($176, $177); ChkLo($177, $177);
  ChkLo($179, $17A); ChkLo($17A, $17A); ChkLo($17D, $17E); ChkLo($17E, $17E); ChkLo($17F, $17F);
  ChkLo($1CC, $1CC); ChkLo($1CE, $1CE);
  ChkLo($1E00, $1E01); ChkLo($1E94, $1E95); ChkLo($1E95, $1E95); ChkLo($1E96, $1E96); ChkLo($1E9F, $1E9F);
  ChkLo($1EA0, $1EA1); ChkLo($1EFE, $1EFF); ChkLo($1EFF, $1EFF);
  ChkLo($385, $385); ChkLo($386, $3AC); ChkLo($387, $387); ChkLo($388, $3AD); ChkLo($38A, $3AF); ChkLo($38B, $38B);
  ChkLo($38C, $3CC); ChkLo($38D, $38D); ChkLo($38E, $3CD); ChkLo($390, $390);
  ChkLo($391, $3B1); ChkLo($3A1, $3C1); ChkLo($3A2, $3A2); ChkLo($3A3, $3C3); ChkLo($3AB, $3CB); ChkLo($3AC, $3AC);
  ChkLo($3FF, $3FF); ChkLo($400, $450); ChkLo($40F, $45F); ChkLo($410, $430); ChkLo($42F, $44F); ChkLo($430, $430);
  ChkLo($460, $461); ChkLo($480, $481); ChkLo($481, $481); ChkLo($482, $482);
  ChkLo($48A, $48B); ChkLo($4BE, $4BF); ChkLo($4BF, $4BF);
  ChkLo($4C1, $4C2); ChkLo($4CD, $4CE); ChkLo($4CE, $4CE); ChkLo($4CF, $4CF);
  ChkLo($4D0, $4D1); ChkLo($52E, $52F); ChkLo($52F, $52F); ChkLo($530, $530);
  ChkLo($531, $561); ChkLo($556, $586); ChkLo($557, $557);
  ChkLo($215F, $215F); ChkLo($2160, $2170); ChkLo($216F, $217F); ChkLo($2170, $2170);
  ChkLo($24B5, $24B5); ChkLo($24B6, $24D0); ChkLo($24CF, $24E9); ChkLo($24D0, $24D0);
  ChkLo($FF20, $FF20); ChkLo($FF21, $FF41); ChkLo($FF3A, $FF5A); ChkLo($FF3B, $FF3B);
  ChkLo($10000, $10000); ChkLo($10FFFF, $10FFFF); ChkLo($FFFFFFFF, $FFFFFFFF);

  { characters outside the tables }
  Fixed($10D0); Fixed($5D0); Fixed($627); Fixed($4E00); Fixed($1F600); Fixed($1C5); Fixed($1F00);
  Fixed($1CF);
end;

procedure TestCaseConsistency;
var
  C, D: LongWord;
  Violations: Integer;
begin
  Violations := 0;
  for C := $80 to $24FF do
  begin
    D := CpLower(C);
    if (D <> C) and (C <> $130) and (C <> $3A3) and (C <> $1E9E) and (CpUpper(D) <> C) then
    begin
      Inc(Violations);
      WriteLn('lower then upper of $', IntToHex(C, 4));
    end;
    D := CpUpper(C);
    if (D <> C) and (C <> $B5) and (C <> $131) and (C <> $17F) and (C <> $3C2) and (CpLower(D) <> C) then
    begin
      Inc(Violations);
      WriteLn('upper then lower of $', IntToHex(C, 4));
    end;
  end;
  CheckI(Violations, 0, 'case consistency');
end;

procedure TestCaseStrings;
var
  Samples: array[0..4] of AnsiString;
  I: Integer;
begin
  CheckS(U8Upper(Privet), #$D0#$9F#$D0#$A0#$D0#$98#$D0#$92#$D0#$95#$D0#$A2, 'upper privet');
  CheckS(U8Lower(#$D0#$9F#$D0#$A0#$D0#$98), #$D0#$BF#$D1#$80#$D0#$B8, 'lower privet');
  CheckS(U8Upper('abc' + Acute), 'ABC'#$C3#$89, 'upper acute');
  CheckS(U8Upper('a'#$80'b'), 'A'#$80'B', 'upper stray');
  CheckS(U8Upper(Japan), Japan, 'upper japan');
  CheckS(U8Upper(#$C4#$B1), 'I', 'upper dotless i');
  CheckS(U8Lower(#$C4#$B0), 'i', 'lower dotted I');
  CheckS(U8Upper('ab'#$D0), 'AB'#$D0, 'upper truncated');
  CheckS(U8Upper(''), '', 'upper empty');
  CheckS(U8Lower(''), '', 'lower empty');
  CheckS(U8Upper(#$C5#$BF), 'S', 'upper long s');
  CheckS(U8Lower(#$C5#$BF), #$C5#$BF, 'lower long s');
  CheckS(U8Upper('a' + #$C4#$B1 + 'b'), 'AIB', 'upper dotless i inside');
  CheckS(U8Lower('A' + #$C4#$B0 + 'B'), 'aib', 'lower dotted I inside');
  CheckS(U8Lower('ABC ' + Privet), 'abc ' + U8Lower(Privet), 'lower mixed');
  CheckS(U8Upper(#$C3#$9F), #$C3#$9F, 'upper sharp s');
  CheckS(U8Upper('a' + Smile), 'A' + Smile, 'upper emoji');
  CheckS(U8Upper(#$CF#$82), #$CE#$A3, 'upper final sigma');
  CheckI(Length(U8Upper(#$C4#$B1#$C4#$B1)), 2, 'upper shrinks the string');

  CheckS(U8CapFirst(#$D0#$BF#$D1#$80), #$D0#$9F#$D1#$80, 'capfirst pr');
  CheckS(U8CapFirst(Privet), Privet, 'capfirst privet');
  CheckS(U8CapFirst('abc'), 'Abc', 'capfirst abc');
  CheckS(U8CapFirst(#$80'a'), #$80'a', 'capfirst stray');
  CheckS(U8CapFirst(''), '', 'capfirst empty');
  CheckS(U8CapFirst(#$C4#$B1'bc'), 'Ibc', 'capfirst dotless i');
  CheckS(U8CapFirst('aBC'), 'ABC', 'capfirst keeps the rest');

  Check(U8EqualNoCase(Privet, U8Upper(Privet)), 'equal privet and its upper');
  Check(not U8EqualNoCase(Privet, 'privet'), 'not equal to a latin text');
  Check(U8EqualNoCase('', ''), 'equal empty');
  Check(U8EqualNoCase('Abc', 'aBC'), 'equal Abc aBC');
  Check(not U8EqualNoCase('S', #$C5#$BF), 'S and long s differ');
  Check(not U8EqualNoCase(#$CF#$82, #$CE#$A3), 'final sigma and capital sigma differ');
  Check(U8EqualNoCase(#$C4#$B0, 'i'), 'dotted I equals i');
  Check(not U8EqualNoCase('abc', 'abd'), 'different texts');
  Check(not U8EqualNoCase('abc', 'ab'), 'different lengths');

  Samples[0] := Privet;
  Samples[1] := 'abc' + Acute + 'Z';
  Samples[2] := #$D0#$BF#$D1#$80#$D0#$B8 + ' ' + #$D0#$A0#$D0#$98;
  Samples[3] := #$C4#$80#$C4#$81#$C5#$B8;
  Samples[4] := 'x'#$80'Y'#$D0;
  for I := 0 to High(Samples) do
  begin
    CheckS(U8Upper(U8Upper(Samples[I])), U8Upper(Samples[I]), 'upper is idempotent ' + IntToStr(I));
    CheckS(U8Lower(U8Lower(Samples[I])), U8Lower(Samples[I]), 'lower is idempotent ' + IntToStr(I));
    CheckS(U8Lower(U8Upper(U8Lower(Samples[I]))), U8Lower(Samples[I]), 'lower upper lower ' + IntToStr(I));
  end;
end;

procedure TestByteMode;
var
  S: AnsiString;
begin
  Utf8Enabled := False;
  CheckI(U8Len(Privet), 12, 'byte mode len');
  CheckI(U8Cols(Privet), 12, 'byte mode cols');
  CheckI(U8Idx(Privet, 3), 4, 'byte mode idx 3');
  CheckI(U8Idx(Privet, 99), 13, 'byte mode idx 99');
  CheckI(U8Idx(Privet, -2), 1, 'byte mode idx negative');
  CheckI(U8Col(Privet, 15), 14, 'byte mode col 15');
  CheckI(U8Col(Privet, 0), 0, 'byte mode col 0');
  CheckI(U8Col(Privet, 1), 0, 'byte mode col 1');
  CheckI(U8PrevIdx(Privet, 5), 4, 'byte mode previdx');
  CheckI(U8PrevIdx(Privet, 1), 1, 'byte mode previdx 1');
  CheckI(U8CharBytes(Privet, 1), 1, 'byte mode charbytes');
  CheckI(U8CharBytes(Privet, 13), 0, 'byte mode charbytes past the end');
  CheckI(U8CodePoint(Privet, 0), $D0, 'byte mode codepoint');
  CheckI(U8CodePoint(Privet, 11), $82, 'byte mode last codepoint');
  CheckI(U8CodePoint(Privet, 12), 0, 'byte mode codepoint past the end');
  CheckS(U8Upper('abc'), 'ABC', 'byte mode upper ascii');
  CheckS(U8Upper(Privet), Privet, 'byte mode upper keeps high bytes');
  CheckS(U8Lower('ABC' + Privet), 'abc' + Privet, 'byte mode lower');
  CheckS(U8Prefix(Privet, 5), #$D0#$9F#$D1#$80#$D0, 'byte mode prefix');
  CheckS(U8Copy(Privet, 1, 3), #$9F#$D1#$80, 'byte mode copy');
  CheckI(Length(U8Fit(Privet, 3)), 3, 'byte mode fit');
  CheckS(U8Fit(Privet, 3), #$D0#$9F#$D1, 'byte mode fit bytes');
  CheckI(U8Cells(Privet, 0, 5), 5, 'byte mode cells');
  CheckI(U8ColAtCell(Privet, 7), 7, 'byte mode colatcell');
  CheckS(U8CapFirst('abc'), 'Abc', 'byte mode capfirst');
  CheckS(U8CapFirst(#$D0#$BF), #$D0#$BF, 'byte mode capfirst high byte');
  CheckS(U8Pad(Privet, 14), Privet + '  ', 'byte mode pad');
  CheckI(U8Cols(Japan), 6, 'byte mode cols of wide characters');
  CheckS(U8Encode($439), #$D0#$B9, 'byte mode encode');
  CheckI(CpUpper($E9), $C9, 'byte mode cpupper');
  CheckI(CpLower($C9), $E9, 'byte mode cplower');
  Check(U8IsAscii('abc') and not U8IsAscii(Privet), 'byte mode isascii');
  S := Privet;
  U8DeleteLast(S);
  CheckI(Length(S), 11, 'byte mode deletelast');
  Utf8Enabled := True;
end;

begin
  Utf8Enabled := True;
  TestIndices;
  TestCutting;
  TestCodePoints;
  TestPrefixAndLast;
  TestInvalid;
  TestCells;
  TestCaseValues;
  TestCaseConsistency;
  TestCaseStrings;
  TestByteMode;
  Check(Utf8Enabled, 'utf8 mode is restored');
  Done;
end.
