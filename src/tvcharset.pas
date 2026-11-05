{ TvCharset converts text between UTF-8 and the character sets met in files, the clipboard and the terminal: the
  single-byte sets of DOS and Windows, KOI8, ISO 8859, Mac Roman, and UTF-16 in both byte orders. It names the sets,
  lists them, validates UTF-8 (Utf8DecodeAt is the one decoder of UTF-8 text) and guesses which single-byte set a
  raw text is written in. Every conversion goes through UTF-8. The only state is the reverse table that
  CharsetFromUtf8 keeps for the set it served last, so that routine is not reentrant. }
unit TvCharset;

{$mode objfpc}
{$H+}

interface

const
  csUtf8 = 65001;
  csUtf16LE = 1200;
  csUtf16BE = 1201;
  csCp437 = 437;
  csCp866 = 866;
  csCp1251 = 1251;
  csCp1252 = 1252;
  csKoi8R = 20866;
  csLatin1 = 28591;

function CharsetId(const Name: AnsiString): LongInt;
function CharsetName(Id: LongInt): AnsiString;
function CharsetKnown(Id: LongInt): Boolean;
function CharsetListCount: Integer;
function CharsetListId(I: Integer): LongInt;
function CharsetToUtf8(Id: LongInt; const Raw: AnsiString): AnsiString;
function CharsetFromUtf8(Id: LongInt; const Text: AnsiString; out Lost: Integer): AnsiString;
function Utf8Valid(const S: AnsiString): Boolean;
function Utf8DecodeAt(const S: AnsiString; Pos: SizeInt; out Cp: Cardinal; out Len: Integer): Boolean;
function IsPlainAscii(const S: AnsiString): Boolean;
function CharsetGuess(const Raw: AnsiString; const Candidates: array of LongInt): LongInt;

implementation

uses
  TvUtf8;

type
  TCharTable = array[0..255] of Word;
  PCharTable = ^TCharTable;

  TSetEntry = record
    Id: LongInt;
    Table: PCharTable;
  end;

{ The tables Set437 ... Set10000, indexed by byte value. A value 0 at a byte of $80 or more means undefined. }
{$I tvcsets.inc}

const
  SingleByteSetCount = 46;
  ReplacementCp = $FFFD;
  UndefinedMark = $FFFF;
  GuessWindow = 1048576;
  GuessFallbackId = 1252;
  MaxNameVariants = 4;

  { Frequency of the Russian lower-case letters U+0430..U+044F, percent times ten. }
  LowerLetterWeight: array[0..31] of Byte = (
    80, 16, 45, 17, 30, 85, 9, 16,
    74, 12, 35, 40, 32, 67, 110, 28,
    47, 55, 63, 26, 3, 10, 5, 14,
    7, 3, 2, 19, 17, 3, 6, 20);

var
  CacheSetId: LongInt = 0;
  CacheSize: Integer = 0;
  CacheCodes: array[0..127] of Word;
  CacheBytes: array[0..127] of Byte;

{ ---- the sets ---- }

function MakeEntry(Id: LongInt; Table: Pointer): TSetEntry;
begin
  Result.Id := Id;
  Result.Table := PCharTable(Table);
end;

{ The set number Index in list order; Id = 0 and Table = nil when Index is out of range. }
function EntryAt(Index: Integer): TSetEntry;
begin
  case Index of
    0: Result := MakeEntry(437, @Set437);
    1: Result := MakeEntry(720, @Set720);
    2: Result := MakeEntry(737, @Set737);
    3: Result := MakeEntry(775, @Set775);
    4: Result := MakeEntry(850, @Set850);
    5: Result := MakeEntry(852, @Set852);
    6: Result := MakeEntry(855, @Set855);
    7: Result := MakeEntry(857, @Set857);
    8: Result := MakeEntry(858, @Set858);
    9: Result := MakeEntry(860, @Set860);
    10: Result := MakeEntry(861, @Set861);
    11: Result := MakeEntry(862, @Set862);
    12: Result := MakeEntry(863, @Set863);
    13: Result := MakeEntry(864, @Set864);
    14: Result := MakeEntry(865, @Set865);
    15: Result := MakeEntry(866, @Set866);
    16: Result := MakeEntry(869, @Set869);
    17: Result := MakeEntry(874, @Set874);
    18: Result := MakeEntry(1125, @Set1125);
    19: Result := MakeEntry(1250, @Set1250);
    20: Result := MakeEntry(1251, @Set1251);
    21: Result := MakeEntry(1252, @Set1252);
    22: Result := MakeEntry(1253, @Set1253);
    23: Result := MakeEntry(1254, @Set1254);
    24: Result := MakeEntry(1255, @Set1255);
    25: Result := MakeEntry(1256, @Set1256);
    26: Result := MakeEntry(1257, @Set1257);
    27: Result := MakeEntry(1258, @Set1258);
    28: Result := MakeEntry(20866, @Set20866);
    29: Result := MakeEntry(21866, @Set21866);
    30: Result := MakeEntry(28591, @Set28591);
    31: Result := MakeEntry(28592, @Set28592);
    32: Result := MakeEntry(28593, @Set28593);
    33: Result := MakeEntry(28594, @Set28594);
    34: Result := MakeEntry(28595, @Set28595);
    35: Result := MakeEntry(28596, @Set28596);
    36: Result := MakeEntry(28597, @Set28597);
    37: Result := MakeEntry(28598, @Set28598);
    38: Result := MakeEntry(28599, @Set28599);
    39: Result := MakeEntry(28600, @Set28600);
    40: Result := MakeEntry(28601, @Set28601);
    41: Result := MakeEntry(28603, @Set28603);
    42: Result := MakeEntry(28604, @Set28604);
    43: Result := MakeEntry(28605, @Set28605);
    44: Result := MakeEntry(28606, @Set28606);
    45: Result := MakeEntry(10000, @Set10000);
  else
    Result := MakeEntry(0, nil);
  end;
end;

function FindTable(Id: LongInt): PCharTable;
var
  Index: Integer;
  Entry: TSetEntry;
begin
  Result := nil;
  if Id <= 0 then
    Exit;
  for Index := 0 to SingleByteSetCount - 1 do
  begin
    Entry := EntryAt(Index);
    if Entry.Id = Id then
    begin
      Result := Entry.Table;
      Exit;
    end;
  end;
end;

function IsUndefined(Value: Word): Boolean;
begin
  Result := (Value = 0) or (Value = UndefinedMark);
end;

{ ---- the names ---- }

function LowerAscii(const Text: AnsiString): AnsiString;
var
  Index: SizeInt;
  Code: Integer;
begin
  Result := Text;
  for Index := 1 to Length(Result) do
  begin
    Code := Ord(Result[Index]);
    if (Code >= Ord('A')) and (Code <= Ord('Z')) then
      Result[Index] := AnsiChar(Code + (Ord('a') - Ord('A')));
  end;
end;

{ Name number VariantNo of the set Id, counted from 0; the empty string when the set has fewer names. }
function SetNameAt(Id: LongInt; VariantNo: Integer): AnsiString;
var
  Digits: AnsiString;
  IsoNumber: AnsiString;
begin
  Result := '';
  Str(Id, Digits);
  case Id of
    1125:
      case VariantNo of
        0: Result := 'cp1125';
        1: Result := 'ibm1125';
        2: Result := 'cp866u';
        3: Result := '1125';
      end;
    1250..1258:
      case VariantNo of
        0: Result := 'windows-' + Digits;
        1: Result := 'cp' + Digits;
        2: Result := Digits;
      end;
    20866:
      case VariantNo of
        0: Result := 'koi8-r';
        1: Result := 'koi8r';
      end;
    21866:
      case VariantNo of
        0: Result := 'koi8-u';
        1: Result := 'koi8u';
      end;
    28591..28606:
      begin
        Str(Id - 28590, IsoNumber);
        case VariantNo of
          0: Result := 'iso-8859-' + IsoNumber;
          1: Result := 'iso8859-' + IsoNumber;
        end;
      end;
    10000:
      case VariantNo of
        0: Result := 'macintosh';
        1: Result := 'mac-roman';
        2: Result := 'macroman';
      end;
  else
    case VariantNo of
      0: Result := 'cp' + Digits;
      1: Result := 'ibm' + Digits;
      2: Result := Digits;
    end;
  end;
end;

function CharsetId(const Name: AnsiString): LongInt;
var
  Wanted: AnsiString;
  Index: Integer;
  VariantNo: Integer;
  Entry: TSetEntry;
begin
  Result := 0;
  Wanted := LowerAscii(Name);
  if Wanted = '' then
    Exit;
  if (Wanted = 'utf-8') or (Wanted = 'utf8') then
  begin
    Result := csUtf8;
    Exit;
  end;
  if (Wanted = 'utf-16le') or (Wanted = 'utf-16') or (Wanted = 'utf16le') then
  begin
    Result := csUtf16LE;
    Exit;
  end;
  if (Wanted = 'utf-16be') or (Wanted = 'utf16be') then
  begin
    Result := csUtf16BE;
    Exit;
  end;
  if (Wanted = 'ascii') or (Wanted = 'us-ascii') then
  begin
    Result := csLatin1;
    Exit;
  end;
  for Index := 0 to SingleByteSetCount - 1 do
  begin
    Entry := EntryAt(Index);
    for VariantNo := 0 to MaxNameVariants - 1 do
      if SetNameAt(Entry.Id, VariantNo) = Wanted then
      begin
        Result := Entry.Id;
        Exit;
      end;
  end;
end;

function CharsetName(Id: LongInt): AnsiString;
begin
  case Id of
    csUtf8: Result := 'utf-8';
    csUtf16LE: Result := 'utf-16le';
    csUtf16BE: Result := 'utf-16be';
  else
    if FindTable(Id) = nil then
      Result := ''
    else
      Result := SetNameAt(Id, 0);
  end;
end;

function CharsetKnown(Id: LongInt): Boolean;
begin
  Result := (Id = csUtf8) or (Id = csUtf16LE) or (Id = csUtf16BE) or (FindTable(Id) <> nil);
end;

function CharsetListCount: Integer;
begin
  Result := SingleByteSetCount;
end;

function CharsetListId(I: Integer): LongInt;
begin
  Result := EntryAt(I).Id;
end;

{ ---- UTF-8 ---- }

function Utf8DecodeAt(const S: AnsiString; Pos: SizeInt; out Cp: Cardinal; out Len: Integer): Boolean;
var
  Lead: Cardinal;
  Value: Cardinal;
  Continuations: Integer;
  Step: Integer;
  Follower: Cardinal;
begin
  Result := False;
  Cp := ReplacementCp;
  Len := 0;
  if (Pos < 1) or (Pos > Length(S)) then
    Exit;
  Len := 1;
  Lead := Ord(S[Pos]);
  if Lead < $80 then
  begin
    Cp := Lead;
    Result := True;
    Exit;
  end;
  if (Lead < $C2) or (Lead > $F4) then
    Exit;
  if Lead < $E0 then
  begin
    Continuations := 1;
    Value := Lead and $1F;
  end
  else if Lead < $F0 then
  begin
    Continuations := 2;
    Value := Lead and $0F;
  end
  else
  begin
    Continuations := 3;
    Value := Lead and $07;
  end;
  if Pos + Continuations > Length(S) then
    Exit;
  for Step := 1 to Continuations do
  begin
    Follower := Ord(S[Pos + Step]);
    if (Follower and $C0) <> $80 then
      Exit;
    Value := (Value shl 6) or (Follower and $3F);
  end;
  case Continuations of
    2:
      if (Value < $800) or ((Value >= $D800) and (Value <= $DFFF)) then
        Exit;
    3:
      if (Value < $10000) or (Value > $10FFFF) then
        Exit;
  end;
  Cp := Value;
  Len := Continuations + 1;
  Result := True;
end;

function Utf8Valid(const S: AnsiString): Boolean;
var
  Pos: SizeInt;
  Cp: Cardinal;
  Len: Integer;
begin
  Result := False;
  Pos := 1;
  while Pos <= Length(S) do
  begin
    if not Utf8DecodeAt(S, Pos, Cp, Len) then
      Exit;
    Inc(Pos, Len);
  end;
  Result := True;
end;

function IsPlainAscii(const S: AnsiString): Boolean;
var
  Index: SizeInt;
begin
  Result := False;
  for Index := 1 to Length(S) do
    if Ord(S[Index]) >= $80 then
      Exit;
  Result := True;
end;

{ Writes the UTF-8 of Cp into Dest after the first Used bytes; Dest must be long enough. }
procedure AppendUtf8(var Dest: AnsiString; var Used: SizeInt; Cp: Cardinal);
var
  Encoded: TUtf8Bytes;
  Count: SizeInt;
  Index: SizeInt;
begin
  Count := Utf32To8(Cp, Encoded);
  for Index := 0 to Count - 1 do
    Dest[Used + 1 + Index] := AnsiChar(Encoded[Index]);
  Inc(Used, Count);
end;

{ ---- UTF-16 ---- }

function ReadUnit(const Raw: AnsiString; UnitNo: SizeInt; BigEndian: Boolean): Word;
var
  First: Integer;
  Second: Integer;
begin
  First := Ord(Raw[UnitNo * 2 + 1]);
  Second := Ord(Raw[UnitNo * 2 + 2]);
  if BigEndian then
    Result := Word((First shl 8) or Second)
  else
    Result := Word((Second shl 8) or First);
end;

procedure AppendUnit(var Dest: AnsiString; var Used: SizeInt; Value: Word; BigEndian: Boolean);
var
  HighByte: AnsiChar;
  LowByte: AnsiChar;
begin
  HighByte := AnsiChar(Value shr 8);
  LowByte := AnsiChar(Value and $FF);
  if BigEndian then
  begin
    Dest[Used + 1] := HighByte;
    Dest[Used + 2] := LowByte;
  end
  else
  begin
    Dest[Used + 1] := LowByte;
    Dest[Used + 2] := HighByte;
  end;
  Inc(Used, 2);
end;

function Utf16ToUtf8(const Raw: AnsiString; BigEndian: Boolean): AnsiString;
var
  UnitCount: SizeInt;
  UnitNo: SizeInt;
  Used: SizeInt;
  Current: Word;
  Following: Word;
  Cp: Cardinal;
  Built: AnsiString;
begin
  UnitCount := Length(Raw) div 2;
  SetLength(Built, UnitCount * 3);
  Used := 0;
  UnitNo := 0;
  while UnitNo < UnitCount do
  begin
    Current := ReadUnit(Raw, UnitNo, BigEndian);
    Inc(UnitNo);
    if (Current >= $D800) and (Current <= $DBFF) then
    begin
      Cp := ReplacementCp;
      if UnitNo < UnitCount then
      begin
        Following := ReadUnit(Raw, UnitNo, BigEndian);
        if (Following >= $DC00) and (Following <= $DFFF) then
        begin
          Cp := $10000 + ((Cardinal(Current) - $D800) shl 10) + (Cardinal(Following) - $DC00);
          Inc(UnitNo);
        end;
      end;
    end
    else if (Current >= $DC00) and (Current <= $DFFF) then
      Cp := ReplacementCp
    else
      Cp := Current;
    AppendUtf8(Built, Used, Cp);
  end;
  SetLength(Built, Used);
  Result := Built;
end;

function Utf8ToUtf16(const Text: AnsiString; BigEndian: Boolean; out Lost: Integer): AnsiString;
var
  Pos: SizeInt;
  Used: SizeInt;
  Cp: Cardinal;
  Len: Integer;
  Offset: Cardinal;
  Built: AnsiString;
begin
  Lost := 0;
  SetLength(Built, Length(Text) * 2);
  Used := 0;
  Pos := 1;
  while Pos <= Length(Text) do
  begin
    if not Utf8DecodeAt(Text, Pos, Cp, Len) then
      Inc(Lost);
    Inc(Pos, Len);
    if Cp < $10000 then
      AppendUnit(Built, Used, Word(Cp), BigEndian)
    else
    begin
      Offset := Cp - $10000;
      AppendUnit(Built, Used, Word($D800 + (Offset shr 10)), BigEndian);
      AppendUnit(Built, Used, Word($DC00 + (Offset and $3FF)), BigEndian);
    end;
  end;
  SetLength(Built, Used);
  Result := Built;
end;

{ ---- single-byte sets ---- }

function CharsetToUtf8(Id: LongInt; const Raw: AnsiString): AnsiString;
var
  Table: PCharTable;
  Built: AnsiString;
  Used: SizeInt;
  Index: SizeInt;
  ByteValue: Integer;
  Mapped: Word;
begin
  Result := Raw;
  if Raw = '' then
    Exit;
  if Id = csUtf8 then
    Exit;
  if (Id = csUtf16LE) or (Id = csUtf16BE) then
  begin
    Result := Utf16ToUtf8(Raw, Id = csUtf16BE);
    Exit;
  end;
  Table := FindTable(Id);
  if Table = nil then
    Exit;
  if IsPlainAscii(Raw) then
    Exit;
  SetLength(Built, Length(Raw) * 3);
  Used := 0;
  for Index := 1 to Length(Raw) do
  begin
    ByteValue := Ord(Raw[Index]);
    if ByteValue < $80 then
    begin
      Inc(Used);
      Built[Used] := Raw[Index];
      Continue;
    end;
    Mapped := Table^[ByteValue];
    if IsUndefined(Mapped) then
      AppendUtf8(Built, Used, ReplacementCp)
    else
      AppendUtf8(Built, Used, Mapped);
  end;
  SetLength(Built, Used);
  Result := Built;
end;

{ Fills the reverse table of the cache for the set Id: the defined bytes $80..$FF ordered by code point. }
procedure BuildReverse(Id: LongInt; Table: PCharTable);
var
  ByteValue: Integer;
  Code: Word;
  Slot: Integer;
  Count: Integer;
begin
  CacheSetId := 0;
  Count := 0;
  for ByteValue := $80 to $FF do
  begin
    Code := Table^[ByteValue];
    if IsUndefined(Code) then
      Continue;
    Slot := Count;
    while (Slot > 0) and (CacheCodes[Slot - 1] > Code) do
    begin
      CacheCodes[Slot] := CacheCodes[Slot - 1];
      CacheBytes[Slot] := CacheBytes[Slot - 1];
      Dec(Slot);
    end;
    CacheCodes[Slot] := Code;
    CacheBytes[Slot] := Byte(ByteValue);
    Inc(Count);
  end;
  CacheSize := Count;
  CacheSetId := Id;
end;

{ Looks Cp up in the reverse table of the cache. }
function FindInReverse(Cp: Cardinal; out Found: Byte): Boolean;
var
  FirstIndex: Integer;
  LastIndex: Integer;
  MidIndex: Integer;
begin
  Result := False;
  Found := 0;
  if Cp > $FFFF then
    Exit;
  FirstIndex := 0;
  LastIndex := CacheSize - 1;
  while FirstIndex <= LastIndex do
  begin
    MidIndex := (FirstIndex + LastIndex) div 2;
    if CacheCodes[MidIndex] = Cp then
    begin
      Found := CacheBytes[MidIndex];
      Result := True;
      Exit;
    end;
    if CacheCodes[MidIndex] < Cp then
      FirstIndex := MidIndex + 1
    else
      LastIndex := MidIndex - 1;
  end;
end;

function CharsetFromUtf8(Id: LongInt; const Text: AnsiString; out Lost: Integer): AnsiString;
var
  Table: PCharTable;
  Built: AnsiString;
  Used: SizeInt;
  Pos: SizeInt;
  Cp: Cardinal;
  Len: Integer;
  Mapped: Byte;
begin
  Lost := 0;
  Result := Text;
  if Text = '' then
    Exit;
  if Id = csUtf8 then
    Exit;
  if (Id = csUtf16LE) or (Id = csUtf16BE) then
  begin
    Result := Utf8ToUtf16(Text, Id = csUtf16BE, Lost);
    Exit;
  end;
  Table := FindTable(Id);
  if Table = nil then
    Exit;
  if IsPlainAscii(Text) then
    Exit;
  if CacheSetId <> Id then
    BuildReverse(Id, Table);
  SetLength(Built, Length(Text));
  Used := 0;
  Pos := 1;
  while Pos <= Length(Text) do
  begin
    if Ord(Text[Pos]) < $80 then
    begin
      Inc(Used);
      Built[Used] := Text[Pos];
      Inc(Pos);
      Continue;
    end;
    Utf8DecodeAt(Text, Pos, Cp, Len);
    Inc(Pos, Len);
    Inc(Used);
    if FindInReverse(Cp, Mapped) then
      Built[Used] := AnsiChar(Mapped)
    else
    begin
      Built[Used] := '?';
      Inc(Lost);
    end;
  end;
  SetLength(Built, Used);
  Result := Built;
end;

{ ---- guessing ---- }

{ The weight of a Russian letter: its frequency in percent times ten, halved for a capital letter. }
function RussianWeight(Cp: Cardinal): Integer;
begin
  Result := 0;
  if (Cp >= $0430) and (Cp <= $044F) then
    Result := LowerLetterWeight[Cp - $0430]
  else if Cp = $0451 then
    Result := 2
  else if (Cp >= $0410) and (Cp <= $042F) then
    Result := LowerLetterWeight[Cp - $0410] div 2
  else if Cp = $0401 then
    Result := 1;
end;

{ What one byte adds to the score of a set whose table maps it to Mapped. }
function ByteContribution(Mapped: Word): Integer;
var
  Weight: Integer;
begin
  Result := 0;
  if IsUndefined(Mapped) then
  begin
    Result := -50;
    Exit;
  end;
  if (Mapped >= $2500) and (Mapped <= $259F) then
  begin
    Result := -20;
    Exit;
  end;
  if (Mapped >= $0080) and (Mapped <= $009F) then
  begin
    Result := -50;
    Exit;
  end;
  Weight := RussianWeight(Mapped);
  Result := 10 * Weight;
  if (Weight = 0) and (Mapped >= $00C0) and (Mapped <= $1FFF) then
    Result := Result + 3;
end;

function CharsetGuess(const Raw: AnsiString; const Candidates: array of LongInt): LongInt;
var
  Histogram: array[0..127] of Int64;
  Window: SizeInt;
  Position: SizeInt;
  ByteValue: Integer;
  Slot: Integer;
  CandidateNo: Integer;
  Table: PCharTable;
  Score: Int64;
  BestScore: Int64;
begin
  if Length(Candidates) = 0 then
  begin
    Result := GuessFallbackId;
    Exit;
  end;
  Result := Candidates[0];
  if IsPlainAscii(Raw) then
    Exit;
  Window := Length(Raw);
  if Window > GuessWindow then
    Window := GuessWindow;
  FillChar(Histogram, SizeOf(Histogram), 0);
  for Position := 1 to Window do
  begin
    ByteValue := Ord(Raw[Position]);
    if ByteValue >= $80 then
      Inc(Histogram[ByteValue - $80]);
  end;
  BestScore := -1;
  for CandidateNo := 0 to High(Candidates) do
  begin
    Table := FindTable(Candidates[CandidateNo]);
    if Table = nil then
      Continue;
    Score := 0;
    for Slot := 0 to 127 do
      if Histogram[Slot] > 0 then
        Score := Score + Histogram[Slot] * ByteContribution(Table^[Slot + $80]);
    if Score > BestScore then
    begin
      BestScore := Score;
      Result := Candidates[CandidateNo];
    end;
  end;
end;

end.
