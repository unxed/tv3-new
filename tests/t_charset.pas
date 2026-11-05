{ Tests of TvCharset: names and ids, the single-byte tables, conversions both ways, UTF-16, UTF-8 validation and
  decoding, and the guess of a set. }
program t_charset;

{$mode objfpc}
{$H+}

uses
  TvUtf8, TvCharset;

{$I testlib.inc}

const
  ReplacementUtf8 = #$EF#$BF#$BD;

{ A string of the given byte values. }
function Seq(const Values: array of Byte): AnsiString;
var
  Index: Integer;
begin
  SetLength(Result, Length(Values));
  for Index := 0 to High(Values) do
    Result[Index + 1] := AnsiChar(Values[Index]);
end;

{ The UTF-8 text of the given code points. }
function Utf8Of(const Points: array of Cardinal): AnsiString;
var
  Index: Integer;
  Count: Integer;
  Position: Integer;
  Encoded: TUtf8Bytes;
begin
  Result := '';
  for Index := 0 to High(Points) do
  begin
    Count := Utf32To8(Points[Index], Encoded);
    for Position := 0 to Count - 1 do
      Result := Result + AnsiChar(Encoded[Position]);
  end;
end;

function PrivetUtf8: AnsiString;
begin
  Result := Seq([$D0, $9F, $D1, $80, $D0, $B8, $D0, $B2, $D0, $B5, $D1, $82]);
end;

function PrivetCp866: AnsiString;
begin
  Result := Seq([$8F, $E0, $A8, $A2, $A5, $E2]);
end;

function PrivetCp1251: AnsiString;
begin
  Result := Seq([$CF, $F0, $E8, $E2, $E5, $F2]);
end;

function PrivetKoi8: AnsiString;
begin
  Result := Seq([$F0, $D2, $C9, $D7, $C5, $D4]);
end;

function PrivetUtf16BE: AnsiString;
begin
  Result := Seq([$04, $1F, $04, $40, $04, $38, $04, $32, $04, $35, $04, $42]);
end;

{ "Eto primer russkogo teksta" in Cyrillic, as UTF-8. }
function SentenceUtf8: AnsiString;
begin
  Result := Utf8Of([$042D, $0442, $043E, $20, $043F, $0440, $0438, $043C, $0435, $0440, $20,
    $0440, $0443, $0441, $0441, $043A, $043E, $0433, $043E, $20,
    $0442, $0435, $043A, $0441, $0442, $0430]);
end;

function NumText(N: Int64): AnsiString;
begin
  Str(N, Result);
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

{ The code point of the byte B of set Id. }
function CpOf(Id: LongInt; B: Byte): Cardinal;
var
  Cp: Cardinal;
  Len: Integer;
begin
  Utf8DecodeAt(CharsetToUtf8(Id, Seq([B])), 1, Cp, Len);
  Result := Cp;
end;

function IsUndefinedByte(Id: LongInt; B: Byte): Boolean;
begin
  Result := CharsetToUtf8(Id, Seq([B])) = ReplacementUtf8;
end;

function UndefinedCount(Id: LongInt): Integer;
var
  B: Integer;
begin
  Result := 0;
  for B := $80 to $FF do
    if IsUndefinedByte(Id, Byte(B)) then
      Inc(Result);
end;

procedure CheckCp(Id: LongInt; B: Byte; Expected: Cardinal);
begin
  Check(CpOf(Id, B) = Expected, 'table value: set ' + NumText(Id) + ' byte ' + NumText(B));
end;

procedure CheckDecode(const Name: string; const S: AnsiString; Pos: SizeInt; ExpectedOk: Boolean;
  ExpectedCp: Cardinal; ExpectedLen: Integer);
var
  Cp: Cardinal;
  Len: Integer;
  Ok: Boolean;
begin
  Ok := Utf8DecodeAt(S, Pos, Cp, Len);
  Check(Ok = ExpectedOk, 'decode result: ' + Name);
  Check(Cp = ExpectedCp, 'decode code point: ' + Name);
  Check(Len = ExpectedLen, 'decode length: ' + Name);
end;

procedure CheckValid(const Name: string; const S: AnsiString; Expected: Boolean);
begin
  Check(Utf8Valid(S) = Expected, 'valid: ' + Name);
end;

procedure CheckListId(I: Integer; Expected: LongInt);
begin
  Check(CharsetListId(I) = Expected, 'list id at ' + NumText(I));
end;

procedure CheckNoUndefined(Id: LongInt);
begin
  Check(UndefinedCount(Id) = 0, 'no undefined byte: set ' + NumText(Id));
end;

{ The listed bytes, and only them, are undefined in the set. }
procedure CheckUndefinedBytes(Id: LongInt; const Bytes: array of Byte);
var
  Index: Integer;
  AllListed: Boolean;
begin
  AllListed := True;
  for Index := 0 to High(Bytes) do
    if not IsUndefinedByte(Id, Bytes[Index]) then
      AllListed := False;
  Check(AllListed, 'undefined bytes are undefined: set ' + NumText(Id));
  Check(UndefinedCount(Id) = Length(Bytes), 'undefined byte count: set ' + NumText(Id));
end;

procedure CheckUtf16Lost(const Name: string; Id: LongInt; const Text: AnsiString; const Expected: AnsiString;
  ExpectedLost: Integer);
var
  Lost: Integer;
  Encoded: AnsiString;
begin
  Encoded := CharsetFromUtf8(Id, Text, Lost);
  Check(Encoded = Expected, 'utf-16 encode: ' + Name);
  Check(Lost = ExpectedLost, 'utf-16 encode lost: ' + Name);
end;

procedure TestIds;
begin
  Check(CharsetId('cp866') = 866, 'id cp866');
  Check(CharsetId('Windows-1251') = 1251, 'id Windows-1251');
  Check(CharsetId('KOI8-R') = 20866, 'id KOI8-R');
  Check(CharsetId('UTF-8') = 65001, 'id UTF-8');
  Check(CharsetId('iso-8859-15') = 28605, 'id iso-8859-15');
  Check(CharsetId('nope') = 0, 'id unknown name');
  Check(CharsetId('') = 0, 'id empty name');
  Check(CharsetId(' cp866') = 0, 'id name is not trimmed');
  Check(CharsetId('utf8') = 65001, 'id utf8');
  Check(CharsetId('utf-16le') = 1200, 'id utf-16le');
  Check(CharsetId('utf-16') = 1200, 'id utf-16 is little endian');
  Check(CharsetId('UTF16LE') = 1200, 'id utf16le');
  Check(CharsetId('utf-16be') = 1201, 'id utf-16be');
  Check(CharsetId('utf16be') = 1201, 'id utf16be');
  Check(CharsetId('ascii') = 28591, 'id ascii is Latin-1');
  Check(CharsetId('US-ASCII') = 28591, 'id us-ascii is Latin-1');
  Check(CharsetId('ibm866') = 866, 'id ibm866');
  Check(CharsetId('866') = 866, 'id 866');
  Check(CharsetId('cp437') = 437, 'id cp437');
  Check(CharsetId('IBM850') = 850, 'id ibm850');
  Check(CharsetId('cp1125') = 1125, 'id cp1125');
  Check(CharsetId('ibm1125') = 1125, 'id ibm1125');
  Check(CharsetId('cp866u') = 1125, 'id cp866u');
  Check(CharsetId('1125') = 1125, 'id 1125');
  Check(CharsetId('cp1251') = 1251, 'id cp1251');
  Check(CharsetId('1251') = 1251, 'id 1251');
  Check(CharsetId('windows-1252') = 1252, 'id windows-1252');
  Check(CharsetId('koi8r') = 20866, 'id koi8r');
  Check(CharsetId('koi8-u') = 21866, 'id koi8-u');
  Check(CharsetId('koi8u') = 21866, 'id koi8u');
  Check(CharsetId('iso-8859-1') = 28591, 'id iso-8859-1');
  Check(CharsetId('iso8859-1') = 28591, 'id iso8859-1');
  Check(CharsetId('iso-8859-10') = 28600, 'id iso-8859-10');
  Check(CharsetId('ISO8859-16') = 28606, 'id iso8859-16');
  Check(CharsetId('iso-8859-12') = 0, 'id iso-8859-12 does not exist');
  Check(CharsetId('macintosh') = 10000, 'id macintosh');
  Check(CharsetId('mac-roman') = 10000, 'id mac-roman');
  Check(CharsetId('MacRoman') = 10000, 'id macroman');
  Check(CharsetId('cp20866') = 0, 'id cp20866 is not a name');
  Check(CharsetId('ibm1251') = 0, 'id ibm1251 is not a name');
end;

procedure TestNameTable;
const
  Specials: array[0..7] of AnsiString = ('cp866u', 'koi8-r', 'koi8r', 'koi8-u', 'koi8u', 'macintosh', 'mac-roman',
    'macroman');
var
  Index: Integer;
  Id: LongInt;
  Digits: AnsiString;
  IsoDigits: AnsiString;
  Hits: Integer;
begin
  Hits := 0;
  for Index := 0 to CharsetListCount - 1 do
  begin
    Id := CharsetListId(Index);
    Str(Id, Digits);
    Str(Id - 28590, IsoDigits);
    if CharsetId('cp' + Digits) = Id then Inc(Hits);
    if CharsetId('ibm' + Digits) = Id then Inc(Hits);
    if CharsetId(Digits) = Id then Inc(Hits);
    if CharsetId('windows-' + Digits) = Id then Inc(Hits);
    if CharsetId('iso-8859-' + IsoDigits) = Id then Inc(Hits);
    if CharsetId('iso8859-' + IsoDigits) = Id then Inc(Hits);
  end;
  for Index := 0 to High(Specials) do
    if CharsetId(Specials[Index]) > 0 then
      Inc(Hits);
  Check(Hits = 122, 'the name table has 122 names');
end;

procedure TestNames;
var
  Index: Integer;
  Id: LongInt;
  Back: Boolean;
begin
  Check(CharsetName(65001) = 'utf-8', 'name 65001');
  Check(CharsetName(1200) = 'utf-16le', 'name 1200');
  Check(CharsetName(1201) = 'utf-16be', 'name 1201');
  Check(CharsetName(437) = 'cp437', 'name 437');
  Check(CharsetName(866) = 'cp866', 'name 866');
  Check(CharsetName(1125) = 'cp1125', 'name 1125');
  Check(CharsetName(1251) = 'windows-1251', 'name 1251');
  Check(CharsetName(20866) = 'koi8-r', 'name 20866');
  Check(CharsetName(21866) = 'koi8-u', 'name 21866');
  Check(CharsetName(28591) = 'iso-8859-1', 'name 28591');
  Check(CharsetName(28605) = 'iso-8859-15', 'name 28605');
  Check(CharsetName(10000) = 'macintosh', 'name 10000');
  Check(CharsetName(0) = '', 'name of 0 is empty');
  Check(CharsetName(12345) = '', 'name of an unknown id is empty');
  Check(CharsetName(28602) = '', 'name of 28602 is empty');
  Back := True;
  for Index := 0 to CharsetListCount - 1 do
  begin
    Id := CharsetListId(Index);
    if CharsetId(CharsetName(Id)) <> Id then
      Back := False;
  end;
  Check(Back, 'every name converts back to its id');
  Check(CharsetId(CharsetName(65001)) = 65001, 'utf-8 name converts back');
  Check(CharsetId(CharsetName(1200)) = 1200, 'utf-16le name converts back');
  Check(CharsetId(CharsetName(1201)) = 1201, 'utf-16be name converts back');
end;

procedure TestKnownAndList;
var
  Index: Integer;
  AllKnown: Boolean;
begin
  Check(CharsetKnown(65001), 'known 65001');
  Check(CharsetKnown(1200), 'known 1200');
  Check(CharsetKnown(1201), 'known 1201');
  Check(CharsetKnown(866), 'known 866');
  Check(CharsetKnown(1251), 'known 1251');
  Check(CharsetKnown(20866), 'known 20866');
  Check(CharsetKnown(10000), 'known 10000');
  Check(not CharsetKnown(12345), 'unknown 12345');
  Check(not CharsetKnown(0), 'unknown 0');
  Check(not CharsetKnown(28602), 'unknown 28602');
  Check(not CharsetKnown(1), 'unknown 1');
  Check(CharsetListCount > 40, 'list has more than 40 sets');
  Check(CharsetListCount = 46, 'list has 46 sets');
  CheckListId(0, 437);
  CheckListId(1, 720);
  CheckListId(2, 737);
  CheckListId(3, 775);
  CheckListId(4, 850);
  CheckListId(5, 852);
  CheckListId(6, 855);
  CheckListId(7, 857);
  CheckListId(8, 858);
  CheckListId(9, 860);
  CheckListId(10, 861);
  CheckListId(11, 862);
  CheckListId(12, 863);
  CheckListId(13, 864);
  CheckListId(14, 865);
  CheckListId(15, 866);
  CheckListId(16, 869);
  CheckListId(17, 874);
  CheckListId(18, 1125);
  CheckListId(19, 1250);
  CheckListId(20, 1251);
  CheckListId(21, 1252);
  CheckListId(22, 1253);
  CheckListId(23, 1254);
  CheckListId(24, 1255);
  CheckListId(25, 1256);
  CheckListId(26, 1257);
  CheckListId(27, 1258);
  CheckListId(28, 20866);
  CheckListId(29, 21866);
  CheckListId(30, 28591);
  CheckListId(31, 28592);
  CheckListId(32, 28593);
  CheckListId(33, 28594);
  CheckListId(34, 28595);
  CheckListId(35, 28596);
  CheckListId(36, 28597);
  CheckListId(37, 28598);
  CheckListId(38, 28599);
  CheckListId(39, 28600);
  CheckListId(40, 28601);
  CheckListId(41, 28603);
  CheckListId(42, 28604);
  CheckListId(43, 28605);
  CheckListId(44, 28606);
  CheckListId(45, 10000);
  AllKnown := True;
  for Index := 0 to CharsetListCount - 1 do
    if not CharsetKnown(CharsetListId(Index)) then
      AllKnown := False;
  Check(AllKnown, 'every listed set is known');
end;

procedure TestToUtf8;
begin
  Check(CharsetToUtf8(866, PrivetCp866) = PrivetUtf8, 'cp866 Privet to UTF-8');
  Check(CharsetToUtf8(1251, PrivetCp1251) = PrivetUtf8, 'cp1251 Privet to UTF-8');
  Check(CharsetToUtf8(20866, PrivetKoi8) = PrivetUtf8, 'KOI8-R Privet to UTF-8');
  Check(CharsetToUtf8(28591, Seq([$E9])) = Seq([$C3, $A9]), 'Latin-1 E9 to UTF-8');
  Check(CharsetToUtf8(1252, Seq([$80])) = Seq([$E2, $82, $AC]), 'cp1252 80 is the euro');
  Check(CharsetToUtf8(1251, Seq([$98])) = ReplacementUtf8, 'cp1251 98 is undefined');
  Check(CharsetToUtf8(866, 'abc') = 'abc', 'cp866 ASCII unchanged');
  Check(CharsetToUtf8(866, 'ab' + Seq([$80]) + 'c') = 'ab' + Seq([$D0, $90]) + 'c',
    'ASCII and a high byte mixed');
  Check(CharsetToUtf8(65001, Seq([$FF, $41, $C0])) = Seq([$FF, $41, $C0]), 'UTF-8 id returns the bytes unchanged');
  Check(CharsetToUtf8(12345, Seq([$E9, $41])) = Seq([$E9, $41]), 'unknown id returns the bytes unchanged');
  Check(CharsetToUtf8(866, '') = '', 'empty to UTF-8 in cp866');
  Check(CharsetToUtf8(65001, '') = '', 'empty to UTF-8 in UTF-8');
  Check(CharsetToUtf8(1200, '') = '', 'empty to UTF-8 in UTF-16LE');
  Check(CharsetToUtf8(1201, '') = '', 'empty to UTF-8 in UTF-16BE');
  Check(CharsetToUtf8(12345, '') = '', 'empty to UTF-8 in an unknown set');
end;

procedure TestFromUtf8;
var
  Lost: Integer;
  Mixed: AnsiString;
begin
  Check(FromUtf8(866, PrivetUtf8) = PrivetCp866, 'Privet to cp866');
  Check(LostOf(866, PrivetUtf8) = 0, 'Privet to cp866 loses nothing');
  Check(FromUtf8(1251, PrivetUtf8) = PrivetCp1251, 'Privet to cp1251');
  Check(FromUtf8(20866, PrivetUtf8) = PrivetKoi8, 'Privet to KOI8-R');
  Check(FromUtf8(866, PrivetUtf8) = PrivetCp866, 'Privet to cp866 after another set');
  Check(FromUtf8(28591, PrivetUtf8) = '??????', 'Privet to Latin-1 gives question marks');
  Check(LostOf(28591, PrivetUtf8) = 6, 'Privet to Latin-1 loses 6');
  Check(FromUtf8(28591, Seq([$C3, $A9, $78])) = Seq([$E9, $78]), 'e acute and x to Latin-1');
  Check(LostOf(28591, Seq([$C3, $A9, $78])) = 0, 'e acute and x to Latin-1 loses nothing');
  Check(FromUtf8(1252, Seq([$E2, $82, $AC])) = Seq([$80]), 'euro to cp1252');
  Check(FromUtf8(866, 'abc') = 'abc', 'ASCII to cp866 unchanged');
  Check(FromUtf8(65001, Seq([$FF, $41])) = Seq([$FF, $41]), 'UTF-8 to UTF-8 unchanged');
  Check(LostOf(65001, Seq([$FF, $41])) = 0, 'UTF-8 to UTF-8 loses nothing');
  Check(FromUtf8(12345, PrivetUtf8) = PrivetUtf8, 'unknown id returns the text unchanged');
  Check(LostOf(12345, PrivetUtf8) = 0, 'unknown id loses nothing');
  Lost := 99;
  CharsetFromUtf8(866, 'abc', Lost);
  Check(Lost = 0, 'Lost is set for ASCII text');
  Lost := 99;
  CharsetFromUtf8(866, '', Lost);
  Check(Lost = 0, 'Lost is set for the empty text');
  Check(FromUtf8(866, Seq([$FF, $41])) = '?A', 'an invalid byte gives a question mark');
  Check(LostOf(866, Seq([$FF, $41])) = 1, 'an invalid byte is one lost character');
  Check(FromUtf8(28591, Seq([$E2, $82])) = '??', 'a truncated sequence gives one mark per byte');
  Check(LostOf(28591, Seq([$E2, $82])) = 2, 'a truncated sequence loses two');
  Check(FromUtf8(28591, Seq([$C0, $80])) = '??', 'an overlong sequence gives two marks');
  Check(FromUtf8(28591, ReplacementUtf8) = '?', 'a valid U+FFFD gives a question mark');
  Check(LostOf(28591, ReplacementUtf8) = 1, 'a valid U+FFFD is lost');
  Check(FromUtf8(1252, Seq([$F0, $9F, $98, $80])) = '?', 'a character above U+FFFF gives one question mark');
  Check(LostOf(1252, Seq([$F0, $9F, $98, $80])) = 1, 'a character above U+FFFF is one lost');
  Mixed := 'a' + Seq([$C3, $A9]) + 'b' + Seq([$D0, $9F]) + 'c';
  Check(FromUtf8(28591, Mixed) = 'a' + Seq([$E9]) + 'b?c', 'one byte per input character');
  Check(LostOf(28591, Mixed) = 1, 'one unmappable character in mixed text');
  Check(FromUtf8(866, '') = '', 'empty from UTF-8 to cp866');
  Check(FromUtf8(65001, '') = '', 'empty from UTF-8 to UTF-8');
  Check(FromUtf8(1200, '') = '', 'empty from UTF-8 to UTF-16LE');
  Check(FromUtf8(1201, '') = '', 'empty from UTF-8 to UTF-16BE');
  Check(FromUtf8(12345, '') = '', 'empty from UTF-8 to an unknown set');
  Check(FromUtf8(1251, Seq([$D0, $98])) = Seq([$C8]), 'U+0418 to cp1251');
end;

procedure TestUtf16;
var
  Lost: Integer;
begin
  Check(CharsetToUtf8(1200, Seq([$48, $00, $69, $00])) = 'Hi', 'UTF-16LE Hi to UTF-8');
  Check(CharsetToUtf8(1201, Seq([$00, $48, $00, $69])) = 'Hi', 'UTF-16BE Hi to UTF-8');
  Check(CharsetToUtf8(1200, Seq([$3D, $D8, $00, $DE])) = Seq([$F0, $9F, $98, $80]), 'UTF-16LE surrogate pair');
  Check(CharsetToUtf8(1201, Seq([$D8, $3D, $DE, $00])) = Seq([$F0, $9F, $98, $80]), 'UTF-16BE surrogate pair');
  Check(CharsetToUtf8(1201, PrivetUtf16BE) = PrivetUtf8, 'UTF-16BE Privet to UTF-8');
  Check(CharsetToUtf8(1200, Seq([$3D, $D8, $41, $00])) = ReplacementUtf8 + 'A',
    'high surrogate before a plain unit gives U+FFFD and keeps the unit');
  Check(CharsetToUtf8(1200, Seq([$3D, $D8, $3D, $D8, $00, $DE])) = ReplacementUtf8 + Seq([$F0, $9F, $98, $80]),
    'high surrogate before a pair keeps the pair');
  Check(CharsetToUtf8(1200, Seq([$00, $DC, $41, $00])) = ReplacementUtf8 + 'A', 'lone low surrogate gives U+FFFD');
  Check(CharsetToUtf8(1200, Seq([$41, $00, $3D, $D8])) = 'A' + ReplacementUtf8, 'last high surrogate gives U+FFFD');
  Check(CharsetToUtf8(1200, Seq([$48, $00, $69])) = 'H', 'odd UTF-16LE length drops the last byte');
  Check(CharsetToUtf8(1201, Seq([$00, $48, $00])) = 'H', 'odd UTF-16BE length drops the last byte');
  Check(CharsetToUtf8(1200, Seq([$48])) = '', 'a single byte of UTF-16 gives the empty text');
  Check(CharsetToUtf8(1200, Seq([$FF, $FE, $48, $00])) = Seq([$EF, $BB, $BF]) + 'H',
    'a byte order mark stays an ordinary character');
  Check(CharsetToUtf8(1200, Seq([$AC, $20])) = Seq([$E2, $82, $AC]), 'UTF-16LE euro');
  Check(FromUtf8(1200, 'Hi') = Seq([$48, $00, $69, $00]), 'Hi to UTF-16LE');
  Check(FromUtf8(1201, 'Hi') = Seq([$00, $48, $00, $69]), 'Hi to UTF-16BE');
  Check(FromUtf8(1200, Seq([$F0, $9F, $98, $80])) = Seq([$3D, $D8, $00, $DE]), 'U+1F600 to UTF-16LE');
  Check(FromUtf8(1201, Seq([$F0, $9F, $98, $80])) = Seq([$D8, $3D, $DE, $00]), 'U+1F600 to UTF-16BE');
  Check(FromUtf8(1201, PrivetUtf8) = PrivetUtf16BE, 'Privet to UTF-16BE');
  Check(LostOf(1201, PrivetUtf8) = 0, 'Privet to UTF-16BE loses nothing');
  Check(LostOf(1200, Seq([$F0, $9F, $98, $80])) = 0, 'U+1F600 to UTF-16LE loses nothing');
  CheckUtf16Lost('invalid byte LE', 1200, Seq([$FF]), Seq([$FD, $FF]), 1);
  CheckUtf16Lost('invalid byte BE', 1201, Seq([$41, $FF]), Seq([$00, $41, $FF, $FD]), 1);
  CheckUtf16Lost('two invalid bytes', 1200, Seq([$E2, $82]), Seq([$FD, $FF, $FD, $FF]), 2);
  CheckUtf16Lost('valid U+FFFD', 1200, ReplacementUtf8, Seq([$FD, $FF]), 0);
  Lost := 99;
  CharsetFromUtf8(1200, '', Lost);
  Check(Lost = 0, 'Lost is set for the empty text in UTF-16');
  Check(CharsetToUtf8(1200, FromUtf8(1200, PrivetUtf8)) = PrivetUtf8, 'UTF-16LE round trip');
  Check(CharsetToUtf8(1201, FromUtf8(1201, Seq([$F0, $9F, $98, $80]) + 'x')) = Seq([$F0, $9F, $98, $80]) + 'x',
    'UTF-16BE round trip with a pair');
end;

procedure TestUtf8Checks;
begin
  CheckValid('Privet', PrivetUtf8, True);
  CheckValid('cp866 Privet', PrivetCp866, False);
  CheckValid('plain', 'plain', True);
  CheckValid('empty', '', True);
  CheckValid('C0 80', Seq([$C0, $80]), False);
  CheckValid('C1 BF', Seq([$C1, $BF]), False);
  CheckValid('C2 80', Seq([$C2, $80]), True);
  CheckValid('E0 80 80', Seq([$E0, $80, $80]), False);
  CheckValid('E0 A0 80', Seq([$E0, $A0, $80]), True);
  CheckValid('ED 9F BF', Seq([$ED, $9F, $BF]), True);
  CheckValid('ED A0 80', Seq([$ED, $A0, $80]), False);
  CheckValid('ED BF BF', Seq([$ED, $BF, $BF]), False);
  CheckValid('EE 80 80', Seq([$EE, $80, $80]), True);
  CheckValid('F0 80 80 80', Seq([$F0, $80, $80, $80]), False);
  CheckValid('F0 90 80 80', Seq([$F0, $90, $80, $80]), True);
  CheckValid('F4 8F BF BF', Seq([$F4, $8F, $BF, $BF]), True);
  CheckValid('F4 90 80 80', Seq([$F4, $90, $80, $80]), False);
  CheckValid('F5 80 80 80', Seq([$F5, $80, $80, $80]), False);
  CheckValid('FF', Seq([$FF]), False);
  CheckValid('stray continuation', Seq([$80]), False);
  CheckValid('stray continuation after text', 'ab' + Seq([$BF]), False);
  CheckValid('truncated two bytes', 'a' + Seq([$D0]), False);
  CheckValid('truncated three bytes', Seq([$E2, $82]), False);
  CheckValid('truncated four bytes', Seq([$F0, $9F, $98]), False);
  CheckValid('bad continuation', Seq([$E2, $82, $41]), False);
  CheckValid('valid after valid', Seq([$E2, $82, $AC, $D0, $9F, $41]), True);
  Check(IsPlainAscii(''), 'empty is plain ASCII');
  Check(IsPlainAscii('plain text 123'), 'plain text is plain ASCII');
  Check(IsPlainAscii(#0#127), 'bytes 0 and 127 are plain ASCII');
  Check(not IsPlainAscii(PrivetUtf8), 'Privet is not plain ASCII');
  Check(not IsPlainAscii('abc' + Seq([$80])), 'byte 80 is not plain ASCII');
end;

procedure TestDecodeAt;
begin
  CheckDecode('A', 'A', 1, True, $41, 1);
  CheckDecode('D0 9F', Seq([$D0, $9F]), 1, True, $041F, 2);
  CheckDecode('E2 82 AC', Seq([$E2, $82, $AC]), 1, True, $20AC, 3);
  CheckDecode('F0 9F 98 80', Seq([$F0, $9F, $98, $80]), 1, True, $1F600, 4);
  CheckDecode('C0 80', Seq([$C0, $80]), 1, False, $FFFD, 1);
  CheckDecode('ED A0 80', Seq([$ED, $A0, $80]), 1, False, $FFFD, 1);
  CheckDecode('E2 82 truncated', Seq([$E2, $82]), 1, False, $FFFD, 1);
  CheckDecode('Pos 0', 'abc', 0, False, $FFFD, 0);
  CheckDecode('Pos Length + 1', 'abc', 4, False, $FFFD, 0);
  CheckDecode('Pos negative', 'abc', -3, False, $FFFD, 0);
  CheckDecode('Pos far above', 'abc', 100, False, $FFFD, 0);
  CheckDecode('empty text', '', 1, False, $FFFD, 0);
  CheckDecode('second character', 'x' + Seq([$D0, $9F]), 2, True, $041F, 2);
  CheckDecode('last character', 'xyz', 3, True, $7A, 1);
  CheckDecode('stray continuation', Seq([$80, $41]), 1, False, $FFFD, 1);
  CheckDecode('F4 90 80 80', Seq([$F4, $90, $80, $80]), 1, False, $FFFD, 1);
  CheckDecode('F4 8F BF BF', Seq([$F4, $8F, $BF, $BF]), 1, True, $10FFFF, 4);
  CheckDecode('F5', Seq([$F5, $80, $80, $80]), 1, False, $FFFD, 1);
  CheckDecode('bad continuation', Seq([$E2, $82, $41]), 1, False, $FFFD, 1);
  CheckDecode('E0 A0 80', Seq([$E0, $A0, $80]), 1, True, $0800, 3);
  CheckDecode('C2 80', Seq([$C2, $80]), 1, True, $0080, 2);
  CheckDecode('text ends inside', 'a' + Seq([$F0, $9F]), 2, False, $FFFD, 1);
end;

procedure TestTables;
var
  B: Integer;
  Identity: Boolean;
begin
  CheckCp(437, $80, $00C7);
  CheckCp(437, $9B, $00A2);
  CheckCp(437, $B0, $2591);
  CheckCp(437, $E0, $03B1);
  CheckCp(437, $FF, $00A0);
  CheckCp(850, $9B, $00F8);
  CheckCp(850, $D5, $0131);
  CheckCp(858, $D5, $20AC);
  CheckCp(866, $80, $0410);
  CheckCp(866, $A0, $0430);
  CheckCp(866, $E0, $0440);
  CheckCp(866, $F0, $0401);
  CheckCp(866, $FF, $00A0);
  CheckCp(1125, $F2, $0490);
  CheckCp(1125, $F4, $0404);
  CheckCp(1125, $F6, $0406);
  CheckCp(1125, $F8, $0407);
  CheckCp(1250, $8A, $0160);
  CheckCp(1251, $80, $0402);
  CheckCp(1251, $A8, $0401);
  CheckCp(1251, $C0, $0410);
  CheckCp(1251, $E0, $0430);
  CheckCp(1252, $80, $20AC);
  CheckCp(1252, $9F, $0178);
  CheckCp(1253, $C1, $0391);
  CheckCp(874, $A1, $0E01);
  CheckCp(874, $E0, $0E40);
  CheckCp(20866, $A3, $0451);
  CheckCp(20866, $B3, $0401);
  CheckCp(20866, $C0, $044E);
  CheckCp(20866, $C1, $0430);
  CheckCp(20866, $E1, $0410);
  CheckCp(20866, $F0, $041F);
  CheckCp(21866, $A4, $0454);
  CheckCp(21866, $B4, $0404);
  CheckCp(28592, $A1, $0104);
  CheckCp(28595, $A1, $0401);
  CheckCp(28595, $B0, $0410);
  CheckCp(28595, $D0, $0430);
  CheckCp(28605, $A4, $20AC);
  CheckCp(10000, $80, $00C4);
  CheckCp(10000, $DB, $20AC);
  Identity := True;
  for B := 0 to 255 do
    if CpOf(28591, Byte(B)) <> Cardinal(B) then
      Identity := False;
  Check(Identity, 'Latin-1 is the identity on all 256 values');
  CheckUndefinedBytes(720, [$80, $81, $84, $86, $8D, $8E, $8F, $90]);
  CheckUndefinedBytes(857, [$D5, $E7, $F2]);
  CheckUndefinedBytes(864, [$9B, $9C, $9F, $A6, $A7, $FF]);
  CheckUndefinedBytes(869, [$80, $81, $82, $83, $84, $85, $87, $93, $94]);
  CheckUndefinedBytes(1251, [$98]);
  CheckUndefinedBytes(1252, [$81, $8D, $8F, $90, $9D]);
  CheckUndefinedBytes(28593, [$A5, $AE, $BE, $C3, $D0, $E3, $F0]);
  CheckNoUndefined(437);
  CheckNoUndefined(737);
  CheckNoUndefined(775);
  CheckNoUndefined(850);
  CheckNoUndefined(852);
  CheckNoUndefined(855);
  CheckNoUndefined(858);
  CheckNoUndefined(860);
  CheckNoUndefined(861);
  CheckNoUndefined(862);
  CheckNoUndefined(863);
  CheckNoUndefined(865);
  CheckNoUndefined(866);
  CheckNoUndefined(1125);
  CheckNoUndefined(1256);
  CheckNoUndefined(20866);
  CheckNoUndefined(21866);
  CheckNoUndefined(28591);
  CheckNoUndefined(28592);
  CheckNoUndefined(28594);
  CheckNoUndefined(28595);
  CheckNoUndefined(28599);
  CheckNoUndefined(28600);
  CheckNoUndefined(28603);
  CheckNoUndefined(28604);
  CheckNoUndefined(28605);
  CheckNoUndefined(28606);
  CheckNoUndefined(10000);
end;

procedure TestRoundTrip;
var
  Index: Integer;
  Id: LongInt;
  B: Integer;
  Raw: AnsiString;
  Utf8: AnsiString;
  Back: AnsiString;
  Lost: Integer;
  LowHalfIdentity: Boolean;
begin
  for Index := 0 to CharsetListCount - 1 do
  begin
    Id := CharsetListId(Index);
    Raw := '';
    LowHalfIdentity := True;
    for B := 0 to 255 do
    begin
      if not IsUndefinedByte(Id, Byte(B)) then
        Raw := Raw + AnsiChar(B);
      if (B < $80) and (CpOf(Id, Byte(B)) <> Cardinal(B)) then
        LowHalfIdentity := False;
    end;
    Utf8 := CharsetToUtf8(Id, Raw);
    Back := CharsetFromUtf8(Id, Utf8, Lost);
    Check(Utf8Valid(Utf8), 'converted text is valid UTF-8: set ' + NumText(Id));
    Check((Back = Raw) and (Lost = 0), 'round trip of every defined byte: set ' + NumText(Id));
    Check(LowHalfIdentity, 'the low half is ASCII: set ' + NumText(Id));
  end;
end;

procedure TestGuess;
var
  Sentence: AnsiString;
  Sentence866: AnsiString;
  Sentence1251: AnsiString;
  SentenceKoi8: AnsiString;
  Lost: Integer;
  Long: AnsiString;
begin
  Sentence := SentenceUtf8;
  Sentence866 := CharsetFromUtf8(866, Sentence, Lost);
  Check((Lost = 0) and (Length(Sentence866) = 26), 'the sentence converts to cp866');
  Sentence1251 := CharsetFromUtf8(1251, Sentence, Lost);
  Check((Lost = 0) and (Length(Sentence1251) = 26), 'the sentence converts to cp1251');
  SentenceKoi8 := CharsetFromUtf8(20866, Sentence, Lost);
  Check((Lost = 0) and (Length(SentenceKoi8) = 26), 'the sentence converts to KOI8-R');
  Check(CharsetGuess(Sentence866, [1251, 866, 20866]) = 866, 'guess cp866');
  Check(CharsetGuess(Sentence1251, [866, 1251, 20866]) = 1251, 'guess cp1251');
  Check(CharsetGuess(SentenceKoi8, [866, 1251, 20866]) = 20866, 'guess KOI8-R');
  Check(CharsetGuess(Sentence866, [20866, 1251, 866]) = 866, 'guess cp866 with another candidate order');
  Check(CharsetGuess(Sentence1251, [20866, 866, 1251]) = 1251, 'guess cp1251 with another candidate order');
  Check(CharsetGuess(SentenceKoi8, [1251, 20866, 866]) = 20866, 'guess KOI8-R with another candidate order');
  Check(CharsetGuess('plain text', [1251, 866]) = 1251, 'plain text gives the first candidate');
  Check(CharsetGuess('plain text', [12345]) = 12345, 'plain text gives the first candidate even if unknown');
  Check(CharsetGuess('', [866, 1251]) = 866, 'empty text gives the first candidate');
  Check(CharsetGuess('plain text', []) = 1252, 'no candidates and plain text give 1252');
  Check(CharsetGuess(Sentence866, []) = 1252, 'no candidates give 1252');
  Check(CharsetGuess('', []) = 1252, 'no candidates and empty text give 1252');
  Check(CharsetGuess(Sentence866, [65001, 866]) = 866, 'UTF-8 is skipped as a candidate');
  Check(CharsetGuess(Sentence866, [65001, 1200]) = 65001, 'only non-table candidates give the first one');
  Check(CharsetGuess(Seq([$85, $85]), [12345, 28591]) = 12345, 'a negative score never wins');
  Check(CharsetGuess(Seq([$A0]), [12345, 28591]) = 28591, 'a score of zero wins over the default');
  Check(CharsetGuess(Seq([$A0]), [1252, 28591]) = 1252, 'a tie goes to the earlier candidate');
  Check(CharsetGuess(Seq([$A0]), [28591, 1252]) = 28591, 'a tie goes to the earlier candidate, other order');
  Check(CharsetGuess(Seq([$98]), [1251, 28591]) = 1251, 'undefined and control bytes score negative');
  Check(CharsetGuess(Seq([$B0, $B1, $B2]), [437, 1252]) = 1252, 'box drawing scores negative');
  Check(CharsetGuess(Seq([$E9]), [12345, 28591]) = 28591, 'a letter-like value scores positive');
  Long := StringOfChar('a', 1048576) + Sentence1251;
  Check(CharsetGuess(Long, [866, 1251]) = 866, 'only the first 1048576 bytes are examined');
  Check(CharsetGuess(Long, [12345, 866, 1251]) = 866, 'unknown candidates are skipped in the window case');
end;

procedure TestEmpty;
var
  Lost: Integer;
begin
  Check(Utf8Valid(''), 'empty text is valid UTF-8');
  Check(IsPlainAscii(''), 'empty text is plain ASCII');
  Lost := 7;
  Check(CharsetFromUtf8(1251, '', Lost) = '', 'empty text from UTF-8');
  Check(Lost = 0, 'empty text loses nothing');
  Check(CharsetToUtf8(1251, '') = '', 'empty text to UTF-8');
  Check(CharsetGuess('', [1251]) = 1251, 'empty text guess');
end;

begin
  TestIds;
  TestNameTable;
  TestNames;
  TestKnownAndList;
  TestToUtf8;
  TestFromUtf8;
  TestUtf16;
  TestUtf8Checks;
  TestDecodeAt;
  TestTables;
  TestRoundTrip;
  TestGuess;
  TestEmpty;
  Done;
end.
