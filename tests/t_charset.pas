program t_charset;

{$mode objfpc}
{$H+}

uses
  TvUtf8, TvCharset;

{$I testlib.inc}

const
  ReplacementUtf8 = #$EF#$BF#$BD;

function Bytes(const A: array of Byte): AnsiString;
var
  I: Integer;
begin
  SetLength(Result, Length(A));
  for I := 0 to High(A) do
    Result[I + 1] := Chr(A[I]);
end;

{ The UTF-8 text of the given code points. }
function Utf8Of(const Codes: array of Cardinal): AnsiString;
var
  I, K, Count: Integer;
  Buffer: TUtf8Bytes;
begin
  Result := '';
  for I := 0 to High(Codes) do
  begin
    Count := Utf32To8(Codes[I], Buffer);
    for K := 0 to Count - 1 do
      Result := Result + Chr(Buffer[K]);
  end;
end;

function Privet8: AnsiString;
begin
  Result := Utf8Of([$041F, $0440, $0438, $0432, $0435, $0442]);
end;

function Sentence8: AnsiString;
begin
  Result := Utf8Of([$042D, $0442, $043E, 32, $043F, $0440, $0438, $043C, $0435, $0440, 32,
    $0440, $0443, $0441, $0441, $043A, $043E, $0433, $043E, 32, $0442, $0435, $043A, $0441, $0442, $0430]);
end;

function FromUtf8(Id: LongInt; const Text: AnsiString): AnsiString;
var
  Lost: Integer;
begin
  Result := CharsetFromUtf8(Id, Text, Lost);
end;

function LostOf(Id: LongInt; const Text: AnsiString): Integer;
begin
  CharsetFromUtf8(Id, Text, Result);
end;

{ The code point of byte B of set Id, $FFFD when it is undefined. }
function CodeOf(Id: LongInt; B: Byte): Cardinal;
begin
  Result := Utf8To32(CharsetToUtf8(Id, Chr(B)));
end;

procedure Spot(Id: LongInt; B: Byte; Expected: Cardinal);
begin
  Check(CodeOf(Id, B) = Expected, 'spot value: set ' + CharsetName(Id) + ' byte ' + HexStr(B, 2));
end;

function UndefinedCount(Id: LongInt): Integer;
var
  B: Integer;
begin
  Result := 0;
  for B := $80 to $FF do
    if CharsetToUtf8(Id, Chr(B)) = ReplacementUtf8 then
      Inc(Result);
end;

procedure TestIds;
begin
  Check(CharsetId('cp866') = 866, 'id: cp866');
  Check(CharsetId('Windows-1251') = 1251, 'id: Windows-1251');
  Check(CharsetId('KOI8-R') = 20866, 'id: KOI8-R');
  Check(CharsetId('UTF-8') = 65001, 'id: UTF-8');
  Check(CharsetId('utf8') = 65001, 'id: utf8');
  Check(CharsetId('iso-8859-15') = 28605, 'id: iso-8859-15');
  Check(CharsetId('nope') = 0, 'id: unknown name');
  Check(CharsetId('') = 0, 'id: empty name');
  Check(CharsetId(' cp866') = 0, 'id: name is not trimmed');
  Check(CharsetId('utf-16') = 1200, 'id: utf-16 is little endian');
  Check(CharsetId('UTF-16LE') = 1200, 'id: utf-16le');
  Check(CharsetId('utf16le') = 1200, 'id: utf16le');
  Check(CharsetId('utf-16be') = 1201, 'id: utf-16be');
  Check(CharsetId('utf16be') = 1201, 'id: utf16be');
  Check(CharsetId('ascii') = 28591, 'id: ascii is Latin-1');
  Check(CharsetId('US-ASCII') = 28591, 'id: us-ascii is Latin-1');
  Check(CharsetId('ibm437') = 437, 'id: ibm437');
  Check(CharsetId('437') = 437, 'id: 437');
  Check(CharsetId('cp866u') = 1125, 'id: cp866u');
  Check(CharsetId('1125') = 1125, 'id: 1125');
  Check(CharsetId('cp1252') = 1252, 'id: cp1252');
  Check(CharsetId('1258') = 1258, 'id: 1258');
  Check(CharsetId('koi8u') = 21866, 'id: koi8u');
  Check(CharsetId('iso8859-2') = 28592, 'id: iso8859-2');
  Check(CharsetId('iso-8859-16') = 28606, 'id: iso-8859-16');
  Check(CharsetId('iso-8859-12') = 0, 'id: there is no iso-8859-12');
  Check(CharsetId('macintosh') = 10000, 'id: macintosh');
  Check(CharsetId('Mac-Roman') = 10000, 'id: mac-roman');
  Check(CharsetId('macroman') = 10000, 'id: macroman');
end;

procedure TestNames;
var
  I: Integer;
  Id: LongInt;
  AllBack: Boolean;
begin
  Check(CharsetName(1251) = 'windows-1251', 'name: 1251');
  Check(CharsetName(437) = 'cp437', 'name: 437');
  Check(CharsetName(866) = 'cp866', 'name: 866');
  Check(CharsetName(1125) = 'cp1125', 'name: 1125');
  Check(CharsetName(20866) = 'koi8-r', 'name: 20866');
  Check(CharsetName(21866) = 'koi8-u', 'name: 21866');
  Check(CharsetName(28591) = 'iso-8859-1', 'name: 28591');
  Check(CharsetName(28606) = 'iso-8859-16', 'name: 28606');
  Check(CharsetName(10000) = 'macintosh', 'name: 10000');
  Check(CharsetName(65001) = 'utf-8', 'name: 65001');
  Check(CharsetName(1200) = 'utf-16le', 'name: 1200');
  Check(CharsetName(1201) = 'utf-16be', 'name: 1201');
  Check(CharsetName(12345) = '', 'name: unknown id');
  Check(CharsetName(0) = '', 'name: id 0');
  Check(CharsetName(28602) = '', 'name: id 28602 does not exist');
  AllBack := True;
  for I := 0 to CharsetListCount - 1 do
  begin
    Id := CharsetListId(I);
    if CharsetId(CharsetName(Id)) <> Id then
      AllBack := False;
  end;
  Check(AllBack, 'name: every listed name converts back to its id');
  Check((CharsetId(CharsetName(65001)) = 65001) and (CharsetId(CharsetName(1200)) = 1200) and
    (CharsetId(CharsetName(1201)) = 1201), 'name: UTF names convert back');
end;

procedure TestKnownAndList;
var
  I, K: Integer;
  Distinct: Boolean;
  AllKnown: Boolean;
begin
  Check(CharsetKnown(437), 'known: 437');
  Check(CharsetKnown(866), 'known: 866');
  Check(CharsetKnown(1251), 'known: 1251');
  Check(CharsetKnown(20866), 'known: 20866');
  Check(CharsetKnown(10000), 'known: 10000');
  Check(CharsetKnown(65001), 'known: 65001');
  Check(CharsetKnown(1200), 'known: 1200');
  Check(CharsetKnown(1201), 'known: 1201');
  Check(not CharsetKnown(12345), 'known: 12345 is unknown');
  Check(not CharsetKnown(0), 'known: 0 is unknown');
  Check(not CharsetKnown(28602), 'known: 28602 is unknown');
  Check(CharsetListCount > 40, 'list: more than 40 sets');
  Check(CharsetListCount = 46, 'list: 46 sets');
  Check(CharsetListId(0) = 437, 'list: first is 437');
  Check(CharsetListId(15) = 866, 'list: number 15 is 866');
  Check(CharsetListId(18) = 1125, 'list: number 18 is 1125');
  Check(CharsetListId(28) = 20866, 'list: number 28 is 20866');
  Check(CharsetListId(45) = 10000, 'list: last is 10000');
  AllKnown := True;
  Distinct := True;
  for I := 0 to CharsetListCount - 1 do
  begin
    if not CharsetKnown(CharsetListId(I)) then
      AllKnown := False;
    for K := 0 to I - 1 do
      if CharsetListId(K) = CharsetListId(I) then
        Distinct := False;
  end;
  Check(AllKnown, 'list: every listed id is known');
  Check(Distinct, 'list: ids are distinct');
end;

procedure TestToUtf8;
begin
  Check(CharsetToUtf8(866, Bytes([$8F, $E0, $A8, $A2, $A5, $E2])) = Privet8, 'to utf8: cp866 Privet');
  Check(CharsetToUtf8(1251, Bytes([$CF, $F0, $E8, $E2, $E5, $F2])) = Privet8, 'to utf8: cp1251 Privet');
  Check(CharsetToUtf8(20866, Bytes([$F0, $D2, $C9, $D7, $C5, $D4])) = Privet8, 'to utf8: KOI8-R Privet');
  Check(CharsetToUtf8(28591, #$E9) = #$C3#$A9, 'to utf8: Latin-1 E9');
  Check(CharsetToUtf8(1252, #$80) = #$E2#$82#$AC, 'to utf8: cp1252 euro');
  Check(CharsetToUtf8(1251, #$98) = ReplacementUtf8, 'to utf8: cp1251 undefined byte 98');
  Check(CharsetToUtf8(1252, #$81) = ReplacementUtf8, 'to utf8: cp1252 undefined byte 81');
  Check(CharsetToUtf8(866, 'abc') = 'abc', 'to utf8: cp866 ASCII');
  Check(CharsetToUtf8(866, 'a' + #$80 + 'b') = 'a' + #$D0#$90 + 'b', 'to utf8: ASCII mixed with a high byte');
  Check(CharsetToUtf8(866, '') = '', 'to utf8: empty text');
  Check(CharsetToUtf8(65001, #$FF#$FE'x') = #$FF#$FE'x', 'to utf8: UTF-8 is returned unchanged');
  Check(CharsetToUtf8(12345, #$E9'x') = #$E9'x', 'to utf8: unknown id returns the text unchanged');
  Check(CharsetToUtf8(0, #$E9) = #$E9, 'to utf8: id 0 returns the text unchanged');
end;

procedure TestFromUtf8;
var
  Lost: Integer;
  Output: AnsiString;
begin
  Output := CharsetFromUtf8(866, Privet8, Lost);
  Check(Output = Bytes([$8F, $E0, $A8, $A2, $A5, $E2]), 'from utf8: cp866 Privet');
  Check(Lost = 0, 'from utf8: cp866 Privet loses nothing');
  Output := CharsetFromUtf8(1251, Privet8, Lost);
  Check(Output = Bytes([$CF, $F0, $E8, $E2, $E5, $F2]), 'from utf8: cp1251 Privet');
  Check(Lost = 0, 'from utf8: cp1251 Privet loses nothing');
  Output := CharsetFromUtf8(20866, Privet8, Lost);
  Check(Output = Bytes([$F0, $D2, $C9, $D7, $C5, $D4]), 'from utf8: KOI8-R Privet');
  Check(Lost = 0, 'from utf8: KOI8-R Privet loses nothing');
  Output := CharsetFromUtf8(28591, Privet8, Lost);
  Check(Output = '??????', 'from utf8: Cyrillic into Latin-1 gives question marks');
  Check(Lost = 6, 'from utf8: Cyrillic into Latin-1 loses 6');
  Output := CharsetFromUtf8(28591, #$C3#$A9'x', Lost);
  Check(Output = #$E9'x', 'from utf8: e acute and x into Latin-1');
  Check(Lost = 0, 'from utf8: e acute into Latin-1 loses nothing');
  Output := CharsetFromUtf8(1252, #$E2#$82#$AC, Lost);
  Check(Output = #$80, 'from utf8: euro into cp1252');
  Check(Lost = 0, 'from utf8: euro into cp1252 loses nothing');
  Lost := 99;
  Output := CharsetFromUtf8(866, 'abc', Lost);
  Check((Output = 'abc') and (Lost = 0), 'from utf8: ASCII unchanged and Lost set to 0');
  Output := CharsetFromUtf8(65001, Privet8, Lost);
  Check((Output = Privet8) and (Lost = 0), 'from utf8: UTF-8 to UTF-8 unchanged');
  Lost := 99;
  Output := CharsetFromUtf8(65001, #$FF'x', Lost);
  Check((Output = #$FF'x') and (Lost = 0), 'from utf8: UTF-8 to UTF-8 does not validate');
  Lost := 99;
  Output := CharsetFromUtf8(12345, Privet8, Lost);
  Check((Output = Privet8) and (Lost = 0), 'from utf8: unknown id returns the text and Lost = 0');
  Lost := 99;
  Output := CharsetFromUtf8(866, '', Lost);
  Check((Output = '') and (Lost = 0), 'from utf8: empty text');
  Output := CharsetFromUtf8(866, 'a'#$FF'b', Lost);
  Check(Output = 'a?b', 'from utf8: an invalid byte gives one question mark');
  Check(Lost = 1, 'from utf8: an invalid byte counts as one lost character');
  Output := CharsetFromUtf8(866, #$D0, Lost);
  Check((Output = '?') and (Lost = 1), 'from utf8: a truncated sequence is one invalid character');
  Output := CharsetFromUtf8(866, #$80#$80, Lost);
  Check((Output = '??') and (Lost = 2), 'from utf8: stray continuation bytes are one character each');
  Output := CharsetFromUtf8(28591, #$EF#$BF#$BD, Lost);
  Check((Output = '?') and (Lost = 1), 'from utf8: a valid U+FFFD gives a question mark and is counted');
  Output := CharsetFromUtf8(1252, #$F0#$9F#$98#$80, Lost);
  Check((Output = '?') and (Lost = 1), 'from utf8: a code point above U+FFFF is lost');
  Output := CharsetFromUtf8(866, #$C0#$80, Lost);
  Check((Output = '??') and (Lost = 2), 'from utf8: an overlong form is two invalid bytes');
  { The cache holds the last set only: alternate the sets. }
  Check(FromUtf8(866, Privet8) = Bytes([$8F, $E0, $A8, $A2, $A5, $E2]), 'cache: 866 after another set');
  Check(FromUtf8(1251, Privet8) = Bytes([$CF, $F0, $E8, $E2, $E5, $F2]), 'cache: 1251 after 866');
  Check(FromUtf8(866, Privet8) = Bytes([$8F, $E0, $A8, $A2, $A5, $E2]), 'cache: 866 again');
  Check(LostOf(28591, Privet8) = 6, 'cache: Latin-1 after 866');
  Check(FromUtf8(1252, #$E2#$82#$AC) = #$80, 'cache: cp1252 after Latin-1');
end;

procedure TestUtf16;
var
  Lost: Integer;
  Output: AnsiString;
begin
  Check(CharsetToUtf8(1200, Bytes([$48, 0, $69, 0])) = 'Hi', 'utf16: LE decode');
  Check(CharsetToUtf8(1201, Bytes([0, $48, 0, $69])) = 'Hi', 'utf16: BE decode');
  Check(CharsetToUtf8(1200, Bytes([$3D, $D8, $00, $DE])) = #$F0#$9F#$98#$80, 'utf16: LE surrogate pair decode');
  Check(CharsetToUtf8(1201, Bytes([$D8, $3D, $DE, $00])) = #$F0#$9F#$98#$80, 'utf16: BE surrogate pair decode');
  Output := CharsetFromUtf8(1200, #$F0#$9F#$98#$80, Lost);
  Check((Output = Bytes([$3D, $D8, $00, $DE])) and (Lost = 0), 'utf16: LE surrogate pair encode');
  Output := CharsetFromUtf8(1201, #$F0#$9F#$98#$80, Lost);
  Check((Output = Bytes([$D8, $3D, $DE, $00])) and (Lost = 0), 'utf16: BE surrogate pair encode');
  Output := CharsetFromUtf8(1200, 'Hi', Lost);
  Check((Output = Bytes([$48, 0, $69, 0])) and (Lost = 0), 'utf16: LE encode');
  Output := CharsetFromUtf8(1201, 'Hi', Lost);
  Check((Output = Bytes([0, $48, 0, $69])) and (Lost = 0), 'utf16: BE encode');
  Output := CharsetFromUtf8(1201, Privet8, Lost);
  Check(Output = Bytes([$04, $1F, $04, $40, $04, $38, $04, $32, $04, $35, $04, $42]), 'utf16: BE Privet');
  Check(Lost = 0, 'utf16: BE Privet loses nothing');
  Check(CharsetToUtf8(1201, Bytes([$04, $1F, $04, $40, $04, $38, $04, $32, $04, $35, $04, $42])) = Privet8,
    'utf16: BE Privet decode');
  Check(CharsetToUtf8(1200, Bytes([$1F, $04, $40, $04, $38, $04, $32, $04, $35, $04, $42, $04])) = Privet8,
    'utf16: LE Privet decode');
  Check(CharsetToUtf8(1200, Bytes([0, $D8])) = ReplacementUtf8, 'utf16: a high surrogate as the last unit');
  Check(CharsetToUtf8(1200, Bytes([0, $DC])) = ReplacementUtf8, 'utf16: a lone low surrogate');
  Check(CharsetToUtf8(1200, Bytes([0, $D8, $41, 0])) = ReplacementUtf8 + 'A',
    'utf16: the unit after an unmatched high surrogate is kept');
  Check(CharsetToUtf8(1201, Bytes([$D8, 0, $D8, 0, $DC, 0])) = ReplacementUtf8 + #$F0#$90#$80#$80,
    'utf16: a high surrogate followed by a pair');
  Check(CharsetToUtf8(1200, Bytes([$48, 0, $69])) = 'H', 'utf16: an odd trailing byte is dropped');
  Check(CharsetToUtf8(1200, Bytes([$48])) = '', 'utf16: a single byte gives nothing');
  Check(CharsetToUtf8(1200, '') = '', 'utf16: empty LE text');
  Check(CharsetToUtf8(1201, '') = '', 'utf16: empty BE text');
  Check(CharsetToUtf8(1200, Bytes([$FF, $FE])) = #$EF#$BB#$BF, 'utf16: LE U+FEFF is kept as a character');
  Check(CharsetToUtf8(1201, Bytes([$FE, $FF])) = #$EF#$BB#$BF, 'utf16: BE U+FEFF is kept as a character');
  Output := CharsetFromUtf8(1200, '', Lost);
  Check((Output = '') and (Lost = 0), 'utf16: empty text encodes to nothing');
  Output := CharsetFromUtf8(1200, 'a'#$FF'b', Lost);
  Check(Output = Bytes([$61, 0, $FD, $FF, $62, 0]), 'utf16: an invalid byte gives U+FFFD');
  Check(Lost = 1, 'utf16: an invalid byte is counted');
  Output := CharsetFromUtf8(1201, #$ED#$A0#$80, Lost);
  Check((Output = Bytes([$FF, $FD, $FF, $FD, $FF, $FD])) and (Lost = 3), 'utf16: an encoded surrogate is three invalid bytes');
end;

procedure TestValidity;
begin
  Check(Utf8Valid(Privet8), 'valid: Privet in UTF-8');
  Check(not Utf8Valid(Bytes([$8F, $E0, $A8, $A2, $A5, $E2])), 'valid: Privet in cp866 is not valid');
  Check(Utf8Valid('plain'), 'valid: plain');
  Check(not Utf8Valid(#$C0#$80), 'valid: C0 80 is not valid');
  Check(not Utf8Valid(#$C1#$BF), 'valid: C1 never leads');
  Check(Utf8Valid(''), 'valid: empty string');
  Check(Utf8Valid(#$C2#$80), 'valid: U+0080');
  Check(Utf8Valid(#$DF#$BF), 'valid: U+07FF');
  Check(Utf8Valid(#$E0#$A0#$80), 'valid: U+0800');
  Check(not Utf8Valid(#$E0#$80#$80), 'valid: overlong three-byte form');
  Check(Utf8Valid(#$EF#$BF#$BF), 'valid: U+FFFF');
  Check(not Utf8Valid(#$ED#$A0#$80), 'valid: surrogate ED A0 80');
  Check(not Utf8Valid(#$ED#$BF#$BF), 'valid: surrogate ED BF BF');
  Check(Utf8Valid(#$ED#$9F#$BF), 'valid: U+D7FF');
  Check(Utf8Valid(#$EE#$80#$80), 'valid: U+E000');
  Check(Utf8Valid(#$F0#$90#$80#$80), 'valid: U+10000');
  Check(not Utf8Valid(#$F0#$80#$80#$80), 'valid: overlong four-byte form');
  Check(Utf8Valid(#$F4#$8F#$BF#$BF), 'valid: U+10FFFF');
  Check(not Utf8Valid(#$F4#$90#$80#$80), 'valid: above U+10FFFF');
  Check(not Utf8Valid(#$F5#$80#$80#$80), 'valid: F5 is forbidden');
  Check(not Utf8Valid(#$FF), 'valid: FF is forbidden');
  Check(not Utf8Valid(#$80), 'valid: stray continuation byte');
  Check(not Utf8Valid('a'#$80), 'valid: stray continuation byte after ASCII');
  Check(not Utf8Valid(#$E2#$82), 'valid: truncated three-byte sequence');
  Check(not Utf8Valid(#$D0), 'valid: truncated two-byte sequence');
  Check(not Utf8Valid(#$D0'x'), 'valid: a lead followed by ASCII');
  Check(IsPlainAscii(''), 'ascii: empty string');
  Check(IsPlainAscii('plain text 123 ~'), 'ascii: plain text');
  Check(not IsPlainAscii(Privet8), 'ascii: UTF-8 Privet is not plain');
  Check(not IsPlainAscii('abc'#$80), 'ascii: byte 80 is not plain');
  Check(IsPlainAscii(#0#$7F), 'ascii: NUL and DEL are plain');
end;

procedure TestGuess;
var
  Raw: AnsiString;
begin
  Raw := FromUtf8(866, Sentence8);
  Check(CharsetGuess(Raw, [1251, 866, 20866]) = 866, 'guess: cp866 text');
  Raw := FromUtf8(1251, Sentence8);
  Check(CharsetGuess(Raw, [866, 1251, 20866]) = 1251, 'guess: cp1251 text');
  Raw := FromUtf8(20866, Sentence8);
  Check(CharsetGuess(Raw, [866, 1251, 20866]) = 20866, 'guess: KOI8-R text');
  Check(CharsetGuess('plain text', [1251, 866]) = 1251, 'guess: plain ASCII gives the first candidate');
  Check(CharsetGuess(Raw, []) = 1252, 'guess: no candidates gives 1252');
  Check(CharsetGuess('', []) = 1252, 'guess: empty text and no candidates gives 1252');
  Check(CharsetGuess('', [866, 1251]) = 866, 'guess: empty text gives the first candidate');
  Check(CharsetGuess('plain', [12345, 866]) = 12345, 'guess: plain text gives the first candidate even if unknown');
  Check(CharsetGuess(Raw, [12345, 20866]) = 20866, 'guess: an unknown candidate is skipped');
  Check(CharsetGuess(Raw, [12345, 54321]) = 12345, 'guess: no scoring candidate gives the first one');
  Check(CharsetGuess(Raw, [65001, 1200]) = 65001, 'guess: UTF candidates are skipped');
  Check(CharsetGuess(Bytes([$81, $81, $81]), [1252, 28591]) = 1252, 'guess: all scores negative gives the first candidate');
  Check(CharsetGuess(FromUtf8(866, Sentence8), [20866]) = 20866, 'guess: a single candidate');
  Check(CharsetGuess(Bytes([$B3, $B3, $C4]), [437, 1251]) = 1251, 'guess: box drawing scores below letters');
end;

procedure TestSpotValues;
begin
  Spot(437, $80, $00C7);
  Spot(437, $9B, $00A2);
  Spot(437, $B0, $2591);
  Spot(437, $E0, $03B1);
  Spot(437, $FF, $00A0);
  Spot(850, $9B, $00F8);
  Spot(850, $D5, $0131);
  Spot(858, $D5, $20AC);
  Spot(866, $80, $0410);
  Spot(866, $A0, $0430);
  Spot(866, $E0, $0440);
  Spot(866, $F0, $0401);
  Spot(866, $FF, $00A0);
  Spot(1125, $F2, $0490);
  Spot(1125, $F4, $0404);
  Spot(1125, $F6, $0406);
  Spot(1125, $F8, $0407);
  Spot(1250, $8A, $0160);
  Spot(1251, $80, $0402);
  Spot(1251, $A8, $0401);
  Spot(1251, $C0, $0410);
  Spot(1251, $E0, $0430);
  Spot(1251, $98, $FFFD);
  Spot(1252, $80, $20AC);
  Spot(1252, $9F, $0178);
  Spot(1252, $81, $FFFD);
  Spot(1253, $C1, $0391);
  Spot(874, $A1, $0E01);
  Spot(874, $E0, $0E40);
  Spot(20866, $A3, $0451);
  Spot(20866, $B3, $0401);
  Spot(20866, $C0, $044E);
  Spot(20866, $C1, $0430);
  Spot(20866, $E1, $0410);
  Spot(20866, $F0, $041F);
  Spot(21866, $A4, $0454);
  Spot(21866, $B4, $0404);
  Spot(28592, $A1, $0104);
  Spot(28595, $A1, $0401);
  Spot(28595, $B0, $0410);
  Spot(28595, $D0, $0430);
  Spot(28605, $A4, $20AC);
  Spot(10000, $80, $00C4);
  Spot(10000, $DB, $20AC);
end;

procedure TestTables;
var
  B: Integer;
  IdentityLow: Boolean;
  Latin1Identity: Boolean;
  I: Integer;
  Id: LongInt;
begin
  IdentityLow := True;
  for I := 0 to CharsetListCount - 1 do
  begin
    Id := CharsetListId(I);
    for B := 0 to $7F do
      if CodeOf(Id, Byte(B)) <> Cardinal(B) then
        IdentityLow := False;
  end;
  Check(IdentityLow, 'tables: bytes 00..7F are the identity in every set');
  Latin1Identity := True;
  for B := 0 to $FF do
    if CodeOf(28591, Byte(B)) <> Cardinal(B) then
      Latin1Identity := False;
  Check(Latin1Identity, 'tables: Latin-1 is the identity on all 256 values');
  Check(UndefinedCount(437) = 0, 'undefined: cp437 has none');
  Check(UndefinedCount(866) = 0, 'undefined: cp866 has none');
  Check(UndefinedCount(1251) = 1, 'undefined: cp1251 has 1');
  Check(UndefinedCount(1252) = 5, 'undefined: cp1252 has 5');
  Check(UndefinedCount(857) = 3, 'undefined: cp857 has 3');
  Check(UndefinedCount(864) = 6, 'undefined: cp864 has 6');
  Check(UndefinedCount(869) = 9, 'undefined: cp869 has 9');
  Check(UndefinedCount(28593) = 7, 'undefined: ISO-8859-3 has 7');
  Check(UndefinedCount(20866) = 0, 'undefined: KOI8-R has none');
  Check(UndefinedCount(10000) = 0, 'undefined: Mac Roman has none');
  Check(CharsetToUtf8(857, #$D5) = ReplacementUtf8, 'undefined: cp857 D5');
  Check(CharsetToUtf8(864, #$FF) = ReplacementUtf8, 'undefined: cp864 FF');
  Check(CharsetToUtf8(869, #$80) = ReplacementUtf8, 'undefined: cp869 80');
  Check(CharsetToUtf8(28593, #$A5) = ReplacementUtf8, 'undefined: ISO-8859-3 A5');
end;

procedure TestRoundTrip;
var
  I, B, Count: Integer;
  Id: LongInt;
  Defined: AnsiString;
  Lost: Integer;
  Back, Utf8Text: AnsiString;
  AllExact: Boolean;
  AllClean: Boolean;
begin
  AllExact := True;
  AllClean := True;
  for I := 0 to CharsetListCount - 1 do
  begin
    Id := CharsetListId(I);
    Defined := '';
    for B := 0 to $FF do
      if (B < $80) or (CharsetToUtf8(Id, Chr(B)) <> ReplacementUtf8) then
        Defined := Defined + Chr(B);
    Utf8Text := CharsetToUtf8(Id, Defined);
    Back := CharsetFromUtf8(Id, Utf8Text, Lost);
    Count := Length(Defined);
    if (Back <> Defined) or (Length(Back) <> Count) then
      AllExact := False;
    if Lost <> 0 then
      AllClean := False;
    Check((Back = Defined) and (Lost = 0), 'round trip: set ' + CharsetName(Id));
  end;
  Check(AllExact, 'round trip: every set returns its defined bytes');
  Check(AllClean, 'round trip: no set loses a character');
end;

procedure TestEmpty;
var
  Lost: Integer;
  I: Integer;
  AllEmpty: Boolean;
begin
  AllEmpty := True;
  for I := 0 to CharsetListCount - 1 do
  begin
    if CharsetToUtf8(CharsetListId(I), '') <> '' then
      AllEmpty := False;
    Lost := 99;
    if CharsetFromUtf8(CharsetListId(I), '', Lost) <> '' then
      AllEmpty := False;
    if Lost <> 0 then
      AllEmpty := False;
  end;
  Check(AllEmpty, 'empty: every set gives the empty string both ways');
  Check(CharsetToUtf8(65001, '') = '', 'empty: UTF-8 to UTF-8');
  Check(FromUtf8(65001, '') = '', 'empty: UTF-8 from UTF-8');
  Check(CharsetToUtf8(99, '') = '', 'empty: unknown id to UTF-8');
  Check(FromUtf8(99, '') = '', 'empty: unknown id from UTF-8');
  Check(FromUtf8(1201, '') = '', 'empty: UTF-16BE from UTF-8');
end;

begin
  TestIds;
  TestNames;
  TestKnownAndList;
  TestToUtf8;
  TestFromUtf8;
  TestUtf16;
  TestValidity;
  TestGuess;
  TestSpotValues;
  TestTables;
  TestRoundTrip;
  TestEmpty;
  Done;
end.
