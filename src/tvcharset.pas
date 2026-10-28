{ Conversion between UTF-8 and single-byte character sets (DOS and Windows code pages, KOI8, ISO 8859,
  Mac Roman) and UTF-16, names and ids of the sets, UTF-8 validation and a guess of the set of a raw text. }
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
function IsPlainAscii(const S: AnsiString): Boolean;
function CharsetGuess(const Raw: AnsiString; const Candidates: array of LongInt): LongInt;

implementation

uses
  TvUtf8;

{$I tvcsets.inc}

type
  TSetTable = array[0..255] of Word;
  PSetTable = ^TSetTable;

const
  SetCount = 46;
  ReplacementChar = $FFFD;
  GuessLimit = 1048576;

  OemFamilyCount = 19;

  { Weights of the lower-case Russian letters U+0430..U+044F, in percent times 10. }
  RussianWeights: array[0..31] of Byte = (
    80, 16, 45, 17, 30, 85, 9, 16, 74, 12, 35, 40, 32, 67, 110, 28,
    47, 55, 63, 26, 3, 10, 5, 14, 7, 3, 2, 19, 17, 3, 6, 20
  );

type
  TReverseCodes = array[0..127] of Word;
  TReverseBytes = array[0..127] of Byte;

var
  { The ids of the sets in list order: the DOS code pages, the Windows ones, KOI8, ISO 8859, Mac Roman. }
  ListIds: array[0..SetCount - 1] of LongInt;

  { The reverse table of the set last used by CharsetFromUtf8: code points ascending, with their bytes. }
  ReverseId: LongInt = 0;
  ReverseCount: Integer = 0;
  ReverseCodes: TReverseCodes;
  ReverseBytes: TReverseBytes;

{ ---- Tables ---- }

procedure BuildListIds;
var
  Slot, Number: Integer;

  procedure Add(Id: Integer);
  begin
    ListIds[Slot] := Id;
    Inc(Slot);
  end;

begin
  Slot := 0;
  Add(437);
  Add(720);
  Add(737);
  Add(775);
  Add(850);
  Add(852);
  Add(855);
  for Number := 857 to 858 do
    Add(Number);
  for Number := 860 to 866 do
    Add(Number);
  Add(869);
  Add(874);
  Add(1125);
  for Number := 1250 to 1258 do
    Add(Number);
  Add(20866);
  Add(21866);
  for Number := 28591 to 28606 do
    if Number <> 28602 then
      Add(Number);
  Add(10000);
end;

{ True for the DOS code pages named cpN, ibmN and N: the first OemFamilyCount ids of the list except 1125. }
function IsOemFamily(Id: LongInt): Boolean;
var
  Slot: Integer;
begin
  Result := False;
  if Id = 1125 then
    Exit;
  for Slot := 0 to OemFamilyCount - 1 do
    if ListIds[Slot] = Id then
    begin
      Result := True;
      Exit;
    end;
end;

function FindTable(Id: LongInt): PSetTable;
begin
  case Id of
    437: Result := @Set437;
    720: Result := @Set720;
    737: Result := @Set737;
    775: Result := @Set775;
    850: Result := @Set850;
    852: Result := @Set852;
    855: Result := @Set855;
    857: Result := @Set857;
    858: Result := @Set858;
    860: Result := @Set860;
    861: Result := @Set861;
    862: Result := @Set862;
    863: Result := @Set863;
    864: Result := @Set864;
    865: Result := @Set865;
    866: Result := @Set866;
    869: Result := @Set869;
    874: Result := @Set874;
    1125: Result := @Set1125;
    1250: Result := @Set1250;
    1251: Result := @Set1251;
    1252: Result := @Set1252;
    1253: Result := @Set1253;
    1254: Result := @Set1254;
    1255: Result := @Set1255;
    1256: Result := @Set1256;
    1257: Result := @Set1257;
    1258: Result := @Set1258;
    20866: Result := @Set20866;
    21866: Result := @Set21866;
    28591: Result := @Set28591;
    28592: Result := @Set28592;
    28593: Result := @Set28593;
    28594: Result := @Set28594;
    28595: Result := @Set28595;
    28596: Result := @Set28596;
    28597: Result := @Set28597;
    28598: Result := @Set28598;
    28599: Result := @Set28599;
    28600: Result := @Set28600;
    28601: Result := @Set28601;
    28603: Result := @Set28603;
    28604: Result := @Set28604;
    28605: Result := @Set28605;
    28606: Result := @Set28606;
    10000: Result := @Set10000;
  else
    Result := nil;
  end;
end;

{ True when byte B of Table has no Unicode value. }
function IsUndefined(const Table: TSetTable; B: Integer): Boolean;
begin
  Result := (B >= $80) and (Table[B] = 0);
end;

{ ---- Names ---- }

function IntText(Value: LongInt): AnsiString;
begin
  Str(Value, Result);
end;

function LowerAscii(const S: AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Result[I] in ['A'..'Z'] then
      Result[I] := Chr(Ord(Result[I]) + 32);
end;

{ The Index-th name of the table set Id (0-based, in the order of the name table), or '' when there is none. }
function SetNameAt(Id: LongInt; Index: Integer): AnsiString;
var
  Digits: AnsiString;
begin
  Result := '';
  Digits := IntText(Id);
  if IsOemFamily(Id) then
  begin
    case Index of
      0: Result := 'cp' + Digits;
      1: Result := 'ibm' + Digits;
      2: Result := Digits;
    end;
    Exit;
  end;
  case Id of
    1125:
      case Index of
        0: Result := 'cp1125';
        1: Result := 'ibm1125';
        2: Result := 'cp866u';
        3: Result := '1125';
      end;
    1250..1258:
      case Index of
        0: Result := 'windows-' + Digits;
        1: Result := 'cp' + Digits;
        2: Result := Digits;
      end;
    20866:
      case Index of
        0: Result := 'koi8-r';
        1: Result := 'koi8r';
      end;
    21866:
      case Index of
        0: Result := 'koi8-u';
        1: Result := 'koi8u';
      end;
    28591..28606:
      case Index of
        0: Result := 'iso-8859-' + IntText(Id - 28590);
        1: Result := 'iso8859-' + IntText(Id - 28590);
      end;
    10000:
      case Index of
        0: Result := 'macintosh';
        1: Result := 'mac-roman';
        2: Result := 'macroman';
      end;
  end;
end;

{ ---- UTF-8 ---- }

{ Decodes the character that starts at byte Pos (1-based) of S. Returns True and the code point when the bytes form
  a valid, complete sequence; Len is the number of bytes used. When they do not, returns False with Len = 1. }
function DecodeAt(const S: AnsiString; Pos: SizeInt; out Cp: Cardinal; out Len: Integer): Boolean;
var
  Lead, Second, Needed, K: Integer;
  Continuation: Byte;
  Value: Cardinal;
  LowBound, HighBound: Byte;
begin
  Result := False;
  Cp := ReplacementChar;
  Len := 1;
  Lead := Byte(S[Pos]);
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
    Needed := 1;
    Value := Lead and $1F;
  end
  else if Lead < $F0 then
  begin
    Needed := 2;
    Value := Lead and $0F;
  end
  else
  begin
    Needed := 3;
    Value := Lead and $07;
  end;
  if Pos + Needed > Length(S) then
    Exit;
  LowBound := $80;
  HighBound := $BF;
  case Lead of
    $E0: LowBound := $A0;
    $ED: HighBound := $9F;
    $F0: LowBound := $90;
    $F4: HighBound := $8F;
  end;
  Second := Byte(S[Pos + 1]);
  if (Second < LowBound) or (Second > HighBound) then
    Exit;
  Value := (Value shl 6) or (Second and $3F);
  for K := 2 to Needed do
  begin
    Continuation := Byte(S[Pos + K]);
    if (Continuation and $C0) <> $80 then
      Exit;
    Value := (Value shl 6) or (Continuation and $3F);
  end;
  Cp := Value;
  Len := Needed + 1;
  Result := True;
end;

{ Appends the UTF-8 form of Cp to Buf at position Used + 1. Buf must have room for 4 more bytes. }
procedure PutUtf8(var Buf: AnsiString; var Used: SizeInt; Cp: Cardinal);
var
  Bytes: TUtf8Bytes;
  Count, K: SizeInt;
begin
  Count := Utf32To8(Cp, Bytes);
  for K := 0 to Count - 1 do
    Buf[Used + 1 + K] := Chr(Bytes[K]);
  Inc(Used, Count);
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
    if not DecodeAt(S, Pos, Cp, Len) then
      Exit;
    Inc(Pos, Len);
  end;
  Result := True;
end;

function IsPlainAscii(const S: AnsiString): Boolean;
var
  I: SizeInt;
begin
  Result := False;
  for I := 1 to Length(S) do
    if Byte(S[I]) >= $80 then
      Exit;
  Result := True;
end;

{ ---- UTF-16 ---- }

function Utf16ToUtf8(const Raw: AnsiString; BigEndian: Boolean): AnsiString;
var
  UnitCount, Index, Used: SizeInt;
  Current, Following: Cardinal;
  Cp: Cardinal;

  function UnitAt(UnitIndex: SizeInt): Cardinal;
  var
    First, Second: Cardinal;
  begin
    First := Byte(Raw[UnitIndex * 2 + 1]);
    Second := Byte(Raw[UnitIndex * 2 + 2]);
    if BigEndian then
      Result := (First shl 8) or Second
    else
      Result := (Second shl 8) or First;
  end;

begin
  UnitCount := Length(Raw) div 2;
  SetLength(Result, UnitCount * 3 + 4);
  Used := 0;
  Index := 0;
  while Index < UnitCount do
  begin
    Current := UnitAt(Index);
    Inc(Index);
    if (Current >= $D800) and (Current <= $DBFF) then
    begin
      Cp := ReplacementChar;
      if Index < UnitCount then
      begin
        Following := UnitAt(Index);
        if (Following >= $DC00) and (Following <= $DFFF) then
        begin
          Cp := $10000 + ((Current - $D800) shl 10) + (Following - $DC00);
          Inc(Index);
        end;
      end;
    end
    else if (Current >= $DC00) and (Current <= $DFFF) then
      Cp := ReplacementChar
    else
      Cp := Current;
    PutUtf8(Result, Used, Cp);
  end;
  SetLength(Result, Used);
end;

function Utf8ToUtf16(const Text: AnsiString; BigEndian: Boolean; out Lost: Integer): AnsiString;
var
  Used, Pos: SizeInt;
  Cp: Cardinal;
  Len: Integer;

  procedure PutUnit(Value: Cardinal);
  var
    HighByte, LowByte: Char;
  begin
    HighByte := Chr(Byte((Value shr 8) and $FF));
    LowByte := Chr(Byte(Value and $FF));
    if BigEndian then
    begin
      Result[Used + 1] := HighByte;
      Result[Used + 2] := LowByte;
    end
    else
    begin
      Result[Used + 1] := LowByte;
      Result[Used + 2] := HighByte;
    end;
    Inc(Used, 2);
  end;

begin
  Lost := 0;
  SetLength(Result, Length(Text) * 2);
  Used := 0;
  Pos := 1;
  while Pos <= Length(Text) do
  begin
    if not DecodeAt(Text, Pos, Cp, Len) then
    begin
      Inc(Lost);
      Cp := ReplacementChar;
    end;
    Inc(Pos, Len);
    if Cp >= $10000 then
    begin
      PutUnit($D800 + ((Cp - $10000) shr 10));
      PutUnit($DC00 + ((Cp - $10000) and $3FF));
    end
    else
      PutUnit(Cp);
  end;
  SetLength(Result, Used);
end;

{ ---- Lookup routines ---- }

function CharsetId(const Name: AnsiString): LongInt;
var
  Lower: AnsiString;
  ListIndex, NameIndex: Integer;
  Candidate: AnsiString;
begin
  Result := 0;
  Lower := LowerAscii(Name);
  if Lower = '' then
    Exit;
  if (Lower = 'utf-8') or (Lower = 'utf8') then
    Result := csUtf8
  else if (Lower = 'utf-16le') or (Lower = 'utf-16') or (Lower = 'utf16le') then
    Result := csUtf16LE
  else if (Lower = 'utf-16be') or (Lower = 'utf16be') then
    Result := csUtf16BE
  else if (Lower = 'ascii') or (Lower = 'us-ascii') then
    Result := csLatin1
  else
    for ListIndex := 0 to SetCount - 1 do
    begin
      NameIndex := 0;
      repeat
        Candidate := SetNameAt(ListIds[ListIndex], NameIndex);
        if Candidate = Lower then
        begin
          Result := ListIds[ListIndex];
          Exit;
        end;
        Inc(NameIndex);
      until Candidate = '';
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
  Result := SetCount;
end;

function CharsetListId(I: Integer): LongInt;
begin
  if (I < 0) or (I >= SetCount) then
    Result := 0
  else
    Result := ListIds[I];
end;

{ ---- Conversions ---- }

function CharsetToUtf8(Id: LongInt; const Raw: AnsiString): AnsiString;
var
  Table: PSetTable;
  I, Used: SizeInt;
  B: Byte;
  Value: Cardinal;
begin
  if Raw = '' then
  begin
    Result := '';
    Exit;
  end;
  case Id of
    csUtf8:
      begin
        Result := Raw;
        Exit;
      end;
    csUtf16LE:
      begin
        Result := Utf16ToUtf8(Raw, False);
        Exit;
      end;
    csUtf16BE:
      begin
        Result := Utf16ToUtf8(Raw, True);
        Exit;
      end;
  end;
  Table := FindTable(Id);
  if (Table = nil) or IsPlainAscii(Raw) then
  begin
    Result := Raw;
    Exit;
  end;
  SetLength(Result, Length(Raw) * 3);
  Used := 0;
  for I := 1 to Length(Raw) do
  begin
    B := Byte(Raw[I]);
    if B < $80 then
    begin
      Inc(Used);
      Result[Used] := Raw[I];
      Continue;
    end;
    if IsUndefined(Table^, B) then
      Value := ReplacementChar
    else
      Value := Table^[B];
    PutUtf8(Result, Used, Value);
  end;
  SetLength(Result, Used);
end;

{ Builds the reverse table of the set Id (which has a table) and makes it the cached one. }
procedure BuildReverse(Id: LongInt; const Table: TSetTable);
var
  B, Slot, Before: Integer;
begin
  ReverseCount := 0;
  for B := $80 to $FF do
  begin
    if IsUndefined(Table, B) then
      Continue;
    { Insertion into the ascending list of code points. }
    Slot := ReverseCount;
    while (Slot > 0) and (ReverseCodes[Slot - 1] > Table[B]) do
    begin
      ReverseCodes[Slot] := ReverseCodes[Slot - 1];
      ReverseBytes[Slot] := ReverseBytes[Slot - 1];
      Dec(Slot);
    end;
    Before := Slot;
    ReverseCodes[Before] := Table[B];
    ReverseBytes[Before] := Byte(B);
    Inc(ReverseCount);
  end;
  ReverseId := Id;
end;

{ Returns the byte of the cached set for Cp, or -1 when the set has none. }
function ReverseLookup(Cp: Cardinal): Integer;
var
  Low, High, Middle: Integer;
begin
  Result := -1;
  if Cp > $FFFF then
    Exit;
  Low := 0;
  High := ReverseCount - 1;
  while Low <= High do
  begin
    Middle := (Low + High) div 2;
    if Cp < ReverseCodes[Middle] then
      High := Middle - 1
    else if Cp > ReverseCodes[Middle] then
      Low := Middle + 1
    else
    begin
      Result := ReverseBytes[Middle];
      Exit;
    end;
  end;
end;

function CharsetFromUtf8(Id: LongInt; const Text: AnsiString; out Lost: Integer): AnsiString;
var
  Table: PSetTable;
  Pos, Used: SizeInt;
  Cp: Cardinal;
  Len: Integer;
  Found: Integer;
  Valid: Boolean;
begin
  Lost := 0;
  case Id of
    csUtf16LE:
      begin
        Result := Utf8ToUtf16(Text, False, Lost);
        Exit;
      end;
    csUtf16BE:
      begin
        Result := Utf8ToUtf16(Text, True, Lost);
        Exit;
      end;
  end;
  Table := FindTable(Id);
  if (Table = nil) or IsPlainAscii(Text) then
  begin
    Result := Text;
    Exit;
  end;
  if ReverseId <> Id then
    BuildReverse(Id, Table^);
  SetLength(Result, Length(Text));
  Used := 0;
  Pos := 1;
  while Pos <= Length(Text) do
  begin
    if Byte(Text[Pos]) < $80 then
    begin
      Inc(Used);
      Result[Used] := Text[Pos];
      Inc(Pos);
      Continue;
    end;
    Valid := DecodeAt(Text, Pos, Cp, Len);
    Inc(Pos, Len);
    if Valid then
      Found := ReverseLookup(Cp)
    else
      Found := -1;
    Inc(Used);
    if Found >= 0 then
      Result[Used] := Chr(Byte(Found))
    else
    begin
      Result[Used] := '?';
      Inc(Lost);
    end;
  end;
  SetLength(Result, Used);
end;

{ ---- Guessing ---- }

{ The frequency of the Russian letter Cp in percent times 10, 0 for any other code point. }
function RussianWeight(Cp: Cardinal): Integer;
begin
  Result := 0;
  if (Cp >= $0430) and (Cp <= $044F) then
    Result := RussianWeights[Cp - $0430]
  else if Cp = $0451 then
    Result := 2
  else if (Cp >= $0410) and (Cp <= $042F) then
    Result := RussianWeights[Cp + $20 - $0430] div 2
  else if Cp = $0401 then
    Result := 1;
end;

{ The contribution of one byte (value Cp in the set, or undefined) to the score of a candidate. }
function ByteScore(Undefined: Boolean; Cp: Cardinal): Integer;
var
  Weight: Integer;
begin
  if Undefined then
    Result := -50
  else if (Cp >= $2500) and (Cp <= $259F) then
    Result := -20
  else if (Cp >= $0080) and (Cp <= $009F) then
    Result := -50
  else
  begin
    Weight := RussianWeight(Cp);
    Result := 10 * Weight;
    if (Weight = 0) and (Cp >= $00C0) and (Cp <= $1FFF) then
      Inc(Result, 3);
  end;
end;

function CharsetGuess(const Raw: AnsiString; const Candidates: array of LongInt): LongInt;
var
  Counts: array[$80..$FF] of Int64;
  Examined, I: SizeInt;
  CandidateIndex, B: Integer;
  Table: PSetTable;
  Score, Best: Int64;
begin
  if Length(Candidates) = 0 then
  begin
    Result := csCp1252;
    Exit;
  end;
  Result := Candidates[0];
  if IsPlainAscii(Raw) then
    Exit;
  Examined := Length(Raw);
  if Examined > GuessLimit then
    Examined := GuessLimit;
  for B := $80 to $FF do
    Counts[B] := 0;
  for I := 1 to Examined do
    if Byte(Raw[I]) >= $80 then
      Inc(Counts[Byte(Raw[I])]);
  Best := -1;
  for CandidateIndex := 0 to High(Candidates) do
  begin
    Table := FindTable(Candidates[CandidateIndex]);
    if Table = nil then
      Continue;
    Score := 0;
    for B := $80 to $FF do
      if Counts[B] > 0 then
        Inc(Score, Counts[B] * ByteScore(IsUndefined(Table^, B), Table^[B]));
    if Score > Best then
    begin
      Best := Score;
      Result := Candidates[CandidateIndex];
    end;
  end;
end;

initialization
  BuildListIds;

end.
