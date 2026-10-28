{ Tests of the unit TvCodePages: page selection, the tables, the reverse map, the UTF-8 form of a byte and the
  ASCII fallbacks. }
program t_codepages;

{$mode objfpc}
{$H+}

uses
  SysUtils, TvCodePages;

{$I testlib.inc}

const
  PageLast = 16;

  SpotBytes: array[0..6] of Byte = ($80, $9B, $A0, $A4, $E0, $F0, $FF);

  SpotValues: array[0..16, 0..6] of Word = (
    ($00C7, $00A2, $00E1, $00F1, $03B1, $2261, $00A0),
    ($0391, $03B4, $03B9, $03BD, $03C9, $038F, $00A0),
    ($0106, $00F8, $0100, $017C, $00D3, $00AD, $00A0),
    ($00C7, $00F8, $00E1, $00F1, $00D3, $00AD, $00A0),
    ($00C7, $0164, $00E1, $0104, $00D3, $00AD, $00A0),
    ($0452, $040F, $0430, $0446, $042F, $00AD, $00A0),
    ($00C7, $00F8, $00E1, $00F1, $00D3, $00AD, $00A0),
    ($00C7, $00F8, $00E1, $00F1, $00D3, $00AD, $00A0),
    ($00C7, $00A2, $00E1, $00F1, $03B1, $2261, $00A0),
    ($00C7, $00F8, $00E1, $00C1, $03B1, $2261, $00A0),
    ($05D0, $00A2, $00E1, $00F1, $03B1, $2261, $00A0),
    ($00C7, $00A2, $00A6, $00A8, $03B1, $2261, $00A0),
    ($00B0, $FFFD, $00A0, $00A4, $0640, $FE7D, $FFFD),
    ($00C7, $00F8, $00E1, $00F1, $03B1, $2261, $00A0),
    ($0410, $042B, $0430, $0434, $0440, $0401, $00A0),
    ($FFFD, $03AC, $03CA, $0391, $03B6, $00AD, $00A0),
    ($0410, $042B, $0430, $0434, $0440, $0401, $00A0));

  { Control positions 00h..1Fh, then 7Fh. }
  LowHalf: array[0..32] of Word = (
    $0000, $263A, $263B, $2665, $2666, $2663, $2660, $2022, $25D8, $25CB, $25D9, $2642, $2640, $266A, $266B, $263C,
    $25BA, $25C4, $2195, $203C, $00B6, $00A7, $25AC, $21A8, $2191, $2193, $2192, $2190, $221F, $2194, $25B2, $25BC,
    $2302);

  FullFramePages: array[0..8] of Integer = (437, 737, 860, 861, 862, 863, 865, 866, 1125);
  MixedFramePages: array[0..6] of Integer = (775, 850, 852, 855, 857, 858, 869);

  FrameBytes: array[0..13] of Byte = ($B0, $B1, $B2, $B3, $BF, $C0, $C4, $C9, $CD, $D9, $DA, $DB, $DC, $DF);
  FrameValues: array[0..13] of Word = (
    $2591, $2592, $2593, $2502, $2510, $2514, $2500, $2554, $2550, $2518, $250C, $2588, $2584, $2580);

  { Bytes at which the mixed pages keep the frame characters, as ranges first..last. }
  MixedFrameRanges: array[0..5, 0..1] of Byte = (
    ($B0, $B4), ($B9, $BC), ($BF, $C5), ($C8, $CE), ($D9, $DC), ($DF, $DF));
  { Bytes at which the mixed pages have letters instead. }
  MixedLetterBytes: array[0..16] of Byte = (
    $B5, $B6, $B7, $B8, $BD, $BE, $C6, $C7, $CF, $D0, $D1, $D2, $D3, $D4, $D5, $D6, $DD);

  FrameGlyphs: array[0..10] of Word = ($2500, $2502, $250C, $2510, $2514, $2518, $2550, $2551, $2554, $2557, $2588);

{ The number of the page at a position 0..PageLast of the list of built-in pages. }
function PageNumberAt(Position: Integer): Integer;
begin
  case Position of
    0: Result := 437;
    1: Result := 737;
    2: Result := 775;
    3: Result := 850;
    4: Result := 852;
    5: Result := 855;
    6: Result := 857;
    7: Result := 858;
    8: Result := 860;
    9: Result := 861;
    10: Result := 862;
    11: Result := 863;
    12: Result := 864;
    13: Result := 865;
    14: Result := 866;
    15: Result := 869;
  else
    Result := 1125;
  end;
end;

function Hex(Value: LongWord): string;
begin
  Result := IntToHex(Value, 4);
end;

function PageName(Id: Integer): string;
begin
  Result := 'cp' + IntToStr(Id);
end;

procedure Select(Id: Integer);
begin
  Check(CpSelect(Id), 'CpSelect accepts ' + PageName(Id));
end;

function IsFrameValue(Value: LongWord): Boolean;
begin
  Result := (Value >= $2500) and (Value <= $257F);
end;

procedure TestDefaultAndSelection;
begin
  Check(CpCurrent = 866, 'default page is 866');
  Check(CpToUnicode($80) = $0410, 'default page: byte 80h is U+0410');
  Check(cpIdCp437 = 437, 'constant cpIdCp437');
  Check(cpIdCp866 = 866, 'constant cpIdCp866');
  Check(cpIdCp1125 = 1125, 'constant cpIdCp1125');
  Check(CpSelect(437), 'CpSelect(437) succeeds');
  Check(CpCurrent = 437, 'CpCurrent is 437 after selecting it');
  Check(CpSelect(437), 'selecting the current page again succeeds');
  Check(CpCurrent = 437, 'CpCurrent is still 437 after selecting it again');
  Check(not CpSelect(1), 'CpSelect(1) is refused');
  Check(CpCurrent = 437, 'refused selection leaves 437 current');
  Check(CpToUnicode($80) = $00C7, 'refused selection leaves the table of 437');
  Check(not CpSelect(0), 'CpSelect(0) is refused');
  Check(not CpSelect(720), 'CpSelect(720) is refused');
  Check(not CpSelect(1251), 'CpSelect(1251) is refused');
  Check(not CpSelect(-866), 'CpSelect(-866) is refused');
  Check(CpCurrent = 437, 'CpCurrent is 437 after several refusals');
  Check(CpFromUnicode($00C7) = $80, 'refused selection leaves the reverse map of 437');
  Check(CpSelect(866), 'CpSelect(866) succeeds');
  Check(CpCurrent = 866, 'CpSelect(866) restores page 866');
  Check(CpToUnicode($80) = $0410, 'CpSelect(866) restores the table of 866');
  Check(CpFromUnicode($0410) = $80, 'CpSelect(866) restores the reverse map of 866');
end;

procedure TestAllSelectable;
var
  Index: Integer;
begin
  for Index := 0 to PageLast do
  begin
    Select(PageNumberAt(Index));
    Check(CpCurrent = PageNumberAt(Index), 'CpCurrent after selecting ' + PageName(PageNumberAt(Index)));
  end;
  Select(866);
end;

procedure TestSpotValues;
var
  PageIndex, SpotIndex: Integer;
  Id: Integer;
begin
  for PageIndex := 0 to PageLast do
  begin
    Id := PageNumberAt(PageIndex);
    Select(Id);
    for SpotIndex := 0 to High(SpotBytes) do
      Check(CpToUnicode(SpotBytes[SpotIndex]) = SpotValues[PageIndex, SpotIndex],
        PageName(Id) + ' byte ' + IntToHex(SpotBytes[SpotIndex], 2) + ' is U+' +
        Hex(SpotValues[PageIndex, SpotIndex]));
  end;
  Select(866);
end;

procedure TestLowHalfAndAscii;
var
  PageIndex, Position: Integer;
  Id: Integer;
  LowOk, AsciiOk, ByteOk: Boolean;
  B: Integer;
begin
  { Every control position on one page, one check each. }
  Select(437);
  for Position := 0 to 31 do
    Check(CpToUnicode(Position) = LowHalf[Position], 'cp437 control byte ' + IntToHex(Position, 2) + ' is U+' +
      Hex(LowHalf[Position]));
  Check(CpToUnicode($7F) = $2302, 'cp437 byte 7Fh is U+2302');
  Check(CpToUnicode(0) = 0, 'byte 00h is U+0000');
  Check(CpToUnicode(1) = $263A, 'byte 01h is U+263A');
  for PageIndex := 0 to PageLast do
  begin
    Id := PageNumberAt(PageIndex);
    Select(Id);
    LowOk := True;
    for Position := 0 to 31 do
      if CpToUnicode(Position) <> LowHalf[Position] then
        LowOk := False;
    if CpToUnicode($7F) <> LowHalf[32] then
      LowOk := False;
    Check(LowOk, PageName(Id) + ' bytes 00h..1Fh and 7Fh hold the IBM PC symbols');
    AsciiOk := True;
    for B := $20 to $7E do
    begin
      ByteOk := CpToUnicode(B) = LongWord(B);
      if not ByteOk then
        AsciiOk := False;
    end;
    Check(AsciiOk, PageName(Id) + ' bytes 20h..7Eh are ASCII');
    Check(CpToUnicode($7F) = $2302, PageName(Id) + ' byte 7Fh is U+2302');
    Check(CpToUnicode(0) = 0, PageName(Id) + ' byte 00h is U+0000');
  end;
  Check(CpToUnicode(Ord('%')) = $25, 'cp1125 byte 25h is the percent sign');
  Select(864);
  Check(CpToUnicode($25) = $25, 'cp864 byte 25h stays ASCII');
  Select(866);
end;

procedure TestUndefinedBytes;
const
  Undefined857: array[0..2] of Byte = ($D5, $E7, $F2);
  Undefined864: array[0..5] of Byte = ($9B, $9C, $9F, $A6, $A7, $FF);
  Undefined869: array[0..8] of Byte = ($80, $81, $82, $83, $84, $85, $87, $93, $94);
var
  Index, PageIndex, B: Integer;
  Id, UndefinedCount: Integer;
  Expected: Boolean;
begin
  Select(857);
  for Index := 0 to High(Undefined857) do
    Check(CpToUnicode(Undefined857[Index]) = $FFFD, 'cp857 byte ' + IntToHex(Undefined857[Index], 2) + ' is U+FFFD');
  Select(864);
  for Index := 0 to High(Undefined864) do
    Check(CpToUnicode(Undefined864[Index]) = $FFFD, 'cp864 byte ' + IntToHex(Undefined864[Index], 2) + ' is U+FFFD');
  Select(869);
  for Index := 0 to High(Undefined869) do
    Check(CpToUnicode(Undefined869[Index]) = $FFFD, 'cp869 byte ' + IntToHex(Undefined869[Index], 2) + ' is U+FFFD');
  Check(CpToUnicode(0) = 0, 'cp869 byte 00h stays U+0000');
  for PageIndex := 0 to PageLast do
  begin
    Id := PageNumberAt(PageIndex);
    Select(Id);
    UndefinedCount := 0;
    for B := $80 to $FF do
      if CpToUnicode(B) = $FFFD then
        Inc(UndefinedCount);
    case Id of
      857: Expected := UndefinedCount = 3;
      864: Expected := UndefinedCount = 6;
      869: Expected := UndefinedCount = 9;
    else
      Expected := UndefinedCount = 0;
    end;
    Check(Expected, PageName(Id) + ' has the specified number of undefined bytes');
  end;
  Select(866);
end;

procedure TestFrames;
var
  Index, PageIndex, FrameIndex, RangeIndex: Integer;
  Id, B: Integer;
  FullOk, MixedOk, LettersOk, Block: Boolean;
begin
  for PageIndex := 0 to High(FullFramePages) do
  begin
    Id := FullFramePages[PageIndex];
    Select(Id);
    FullOk := True;
    for FrameIndex := 0 to High(FrameBytes) do
      if CpToUnicode(FrameBytes[FrameIndex]) <> FrameValues[FrameIndex] then
        FullOk := False;
    Check(FullOk, PageName(Id) + ' has the frame and shade characters at B0h..DFh');
    FullOk := True;
    for B := $B0 to $DF do
      if not IsFrameValue(CpToUnicode(B)) and not ((CpToUnicode(B) >= $2580) and (CpToUnicode(B) <= $2593)) then
        FullOk := False;
    Check(FullOk, PageName(Id) + ' has the full frame block at B0h..DFh');
  end;
  for PageIndex := 0 to High(MixedFramePages) do
  begin
    Id := MixedFramePages[PageIndex];
    Select(Id);
    MixedOk := True;
    for RangeIndex := 0 to High(MixedFrameRanges) do
      for B := MixedFrameRanges[RangeIndex, 0] to MixedFrameRanges[RangeIndex, 1] do
      begin
        Block := IsFrameValue(CpToUnicode(B)) or ((CpToUnicode(B) >= $2580) and (CpToUnicode(B) <= $2593));
        if not Block then
          MixedOk := False;
      end;
    Check(MixedOk, PageName(Id) + ' keeps frame characters at B0h-B4h, B9h-BCh, BFh-C5h, C8h-CEh, D9h-DCh, DFh');
    LettersOk := True;
    for Index := 0 to High(MixedLetterBytes) do
      if IsFrameValue(CpToUnicode(MixedLetterBytes[Index])) then
        LettersOk := False;
    Check(LettersOk, PageName(Id) + ' has letters instead of mixed lines at B5h-B8h, BDh, BEh, C6h, C7h, CFh-D8h, DDh');
    Check(CpToUnicode($B0) = $2591, PageName(Id) + ' byte B0h is U+2591');
    Check(CpToUnicode($DB) = $2588, PageName(Id) + ' byte DBh is U+2588');
  end;
  Select(864);
  FullOk := True;
  for B := $B0 to $DF do
    if IsFrameValue(CpToUnicode(B)) then
      FullOk := False;
  Check(FullOk, 'cp864 has no frame characters at B0h..DFh');
  Check(CpToUnicode($B0) <> $2591, 'cp864 byte B0h is not a shade');
  Check(CpToUnicode($80) = $00B0, 'cp864 byte 80h is U+00B0');
  Select(866);
end;

procedure TestPageDifferences;
begin
  Select(850);
  Check(CpToUnicode($D5) = $0131, 'cp850 byte D5h is U+0131');
  Select(858);
  Check(CpToUnicode($D5) = $20AC, 'cp858 byte D5h is the euro sign U+20AC');
  Check(CpFromUnicode($20AC) = $D5, 'cp858 U+20AC maps to D5h');
  Check(CpFromUnicode($0131) = 0, 'cp858 has no dotless i');
  Select(866);
  Check(CpToUnicode($F2) = $0404, 'cp866 byte F2h is U+0404');
  Select(1125);
  Check(CpToUnicode($F2) = $0490, 'cp1125 byte F2h is U+0490');
  Check(CpToUnicode($F3) = $0491, 'cp1125 byte F3h is U+0491');
  Check(CpToUnicode($F4) = $0404, 'cp1125 byte F4h is U+0404');
  Check(CpToUnicode($F5) = $0454, 'cp1125 byte F5h is U+0454');
  Check(CpToUnicode($F6) = $0406, 'cp1125 byte F6h is U+0406');
  Check(CpToUnicode($F7) = $0456, 'cp1125 byte F7h is U+0456');
  Check(CpToUnicode($F8) = $0407, 'cp1125 byte F8h is U+0407');
  Check(CpToUnicode($F9) = $0457, 'cp1125 byte F9h is U+0457');
  Select(866);
end;

procedure TestFromUnicode;
var
  PageIndex, B: Integer;
  Id: Integer;
  BackOk: Boolean;
begin
  Select(866);
  Check(CpFromUnicode($0410) = $80, 'cp866 U+0410 -> 80h');
  Check(CpFromUnicode($0430) = $A0, 'cp866 U+0430 -> A0h');
  Check(CpFromUnicode($0401) = $F0, 'cp866 U+0401 -> F0h');
  Check(CpFromUnicode($2500) = $C4, 'cp866 U+2500 -> C4h');
  Check(CpFromUnicode($263A) = $01, 'cp866 U+263A -> 01h');
  Check(CpFromUnicode($2302) = $7F, 'cp866 U+2302 -> 7Fh');
  Check(CpFromUnicode($0041) = $41, 'cp866 U+0041 -> 41h');
  Check(CpFromUnicode($4E2D) = 0, 'cp866 U+4E2D -> 0');
  Check(CpFromUnicode(0) = 0, 'U+0000 -> 0');
  Check(CpFromUnicode($10410) = 0, 'a code point above FFFFh -> 0');
  Check(CpFromUnicode($10041) = 0, 'U+10041 does not match 41h');
  Check(CpFromUnicode($FFFFFFFF) = 0, 'the largest code point -> 0');
  Check(CpFromUnicode($00C7) = 0, 'cp866 U+00C7 -> 0');
  Select(437);
  Check(CpFromUnicode($00C7) = $80, 'cp437 U+00C7 -> 80h');
  Check(CpFromUnicode($03B1) = $E0, 'cp437 U+03B1 -> E0h');
  Check(CpFromUnicode($0410) = 0, 'cp437 U+0410 -> 0');
  Select(857);
  Check(CpFromUnicode($011F) = $A7, 'cp857 U+011F -> A7h');
  Select(775);
  Check(CpFromUnicode($00B6) = $14, 'cp775 U+00B6 -> 14h');
  Check(CpFromUnicode($00A7) = $15, 'cp775 U+00A7 -> 15h');
  Select(850);
  Check(CpFromUnicode($00B6) = $14, 'cp850 U+00B6 -> 14h');
  Check(CpFromUnicode($00A7) = $15, 'cp850 U+00A7 -> 15h');
  Select(857);
  Check(CpFromUnicode($00B6) = $14, 'cp857 U+00B6 -> 14h');
  Check(CpFromUnicode($00A7) = $15, 'cp857 U+00A7 -> 15h');
  Select(858);
  Check(CpFromUnicode($00B6) = $14, 'cp858 U+00B6 -> 14h');
  Check(CpFromUnicode($00A7) = $15, 'cp858 U+00A7 -> 15h');
  Select(863);
  Check(CpFromUnicode($00B6) = $14, 'cp863 U+00B6 -> 14h, not 86h');
  Check(CpFromUnicode($00A7) = $15, 'cp863 U+00A7 -> 15h, not 8Fh');
  Select(855);
  Check(CpFromUnicode($00A7) = $15, 'cp855 U+00A7 -> 15h, not FDh');
  Select(852);
  Check(CpFromUnicode($00A7) = $15, 'cp852 U+00A7 -> 15h');
  Select(869);
  Check(CpFromUnicode($00A7) = $15, 'cp869 U+00A7 -> 15h');
  for PageIndex := 0 to PageLast do
  begin
    Id := PageNumberAt(PageIndex);
    Select(Id);
    Check(CpFromUnicode($FFFD) = 0, PageName(Id) + ' U+FFFD -> 0');
    BackOk := True;
    for B := $20 to $FF do
    begin
      if B = $7F then
        Continue;
      if CpToUnicode(B) = $FFFD then
        Continue;
      if CpFromUnicode(CpToUnicode(B)) = 0 then
        BackOk := False;
    end;
    Check(BackOk, PageName(Id) + ' every defined byte 20h..FFh except 7Fh maps back to a non-zero byte');
    BackOk := True;
    for B := $20 to $FF do
    begin
      if CpToUnicode(B) = $FFFD then
        Continue;
      if CpFromUnicode(CpToUnicode(B)) > B then
        BackOk := False;
    end;
    Check(BackOk, PageName(Id) + ' the byte found for a value is never above the byte that has it');
    BackOk := True;
    for B := $20 to $FF do
    begin
      if CpToUnicode(B) = $FFFD then
        Continue;
      if CpToUnicode(CpFromUnicode(CpToUnicode(B))) <> CpToUnicode(B) then
        BackOk := False;
    end;
    Check(BackOk, PageName(Id) + ' round trip byte -> value -> byte -> value');
    BackOk := True;
    for B := $20 to $7E do
      if CpFromUnicode(B) <> B then
        BackOk := False;
    Check(BackOk, PageName(Id) + ' ASCII characters map to themselves');
  end;
  Select(857);
  Check(CpFromUnicode($0131) <> 0, 'cp857 U+0131 has a byte');
  Select(864);
  Check(CpFromUnicode($FE7D) = $F0, 'cp864 U+FE7D -> F0h');
  Select(869);
  Check(CpFromUnicode($0391) = $A4, 'cp869 U+0391 -> A4h');
  Select(866);
end;

procedure TestToUtf8;
var
  Buf: array[0..7] of Byte;
  Count: Integer;
  PageIndex, B: Integer;
  Id: Integer;
  LengthOk, FitsOk: Boolean;
  Value, ExpectedLength: LongWord;
begin
  Select(866);
  FillChar(Buf, SizeOf(Buf), $AA);
  Count := CpToUtf8($80, @Buf[0]);
  Check(Count = 2, 'cp866 byte 80h -> 2 bytes');
  Check((Buf[0] = $D0) and (Buf[1] = $90), 'cp866 byte 80h -> D0 90');
  Check(Buf[2] = $AA, 'no terminator is written after a 2-byte sequence');
  Select(437);
  Count := CpToUtf8($80, @Buf[0]);
  Check(Count = 2, 'cp437 byte 80h -> 2 bytes');
  Check((Buf[0] = $C3) and (Buf[1] = $87), 'cp437 byte 80h -> C3 87');
  FillChar(Buf, SizeOf(Buf), $AA);
  Count := CpToUtf8($01, @Buf[0]);
  Check(Count = 3, 'byte 01h -> 3 bytes');
  Check((Buf[0] = $E2) and (Buf[1] = $98) and (Buf[2] = $BA), 'byte 01h -> E2 98 BA');
  Check(Buf[3] = $AA, 'no terminator is written after a 3-byte sequence');
  Count := CpToUtf8($7F, @Buf[0]);
  Check(Count = 3, 'byte 7Fh -> 3 bytes');
  Check((Buf[0] = $E2) and (Buf[1] = $8C) and (Buf[2] = $82), 'byte 7Fh -> E2 8C 82');
  FillChar(Buf, SizeOf(Buf), $AA);
  Count := CpToUtf8(0, @Buf[0]);
  Check(Count = 1, 'byte 00h -> 1 byte');
  Check(Buf[0] = 0, 'byte 00h -> one zero byte');
  Check(Buf[1] = $AA, 'no terminator is written after the zero byte');
  FillChar(Buf, SizeOf(Buf), $AA);
  Count := CpToUtf8(Ord('A'), @Buf[0]);
  Check(Count = 1, 'byte 41h -> 1 byte');
  Check(Buf[0] = $41, 'byte 41h -> 41');
  Check(Buf[1] = $AA, 'no terminator is written after an ASCII byte');
  Count := CpToUtf8($20, @Buf[0]);
  Check((Count = 1) and (Buf[0] = $20), 'byte 20h -> 20');
  Count := CpToUtf8($7E, @Buf[0]);
  Check((Count = 1) and (Buf[0] = $7E), 'byte 7Eh -> 7E');
  Select(864);
  FillChar(Buf, SizeOf(Buf), $AA);
  Count := CpToUtf8($FF, @Buf[0]);
  Check(Count = 3, 'undefined byte -> 3 bytes');
  Check((Buf[0] = $EF) and (Buf[1] = $BF) and (Buf[2] = $BD), 'undefined byte -> EF BF BD');
  Select(869);
  Count := CpToUtf8($80, @Buf[0]);
  Check((Count = 3) and (Buf[0] = $EF) and (Buf[1] = $BF) and (Buf[2] = $BD), 'cp869 byte 80h -> EF BF BD');
  for PageIndex := 0 to PageLast do
  begin
    Id := PageNumberAt(PageIndex);
    Select(Id);
    LengthOk := True;
    FitsOk := True;
    for B := 0 to 255 do
    begin
      Count := CpToUtf8(B, @Buf[0]);
      Value := CpToUnicode(B);
      if Value < $80 then
        ExpectedLength := 1
      else if Value < $800 then
        ExpectedLength := 2
      else
        ExpectedLength := 3;
      if LongWord(Count) <> ExpectedLength then
        LengthOk := False;
      if (Count < 1) or (Count > 3) then
        FitsOk := False;
    end;
    Check(LengthOk, PageName(Id) + ' CpToUtf8 length follows the value of CpToUnicode');
    Check(FitsOk, PageName(Id) + ' CpToUtf8 never returns 4');
    Count := CpToUtf8($01, @Buf[0]);
    Check((Count = 3) and (Buf[0] = $E2) and (Buf[1] = $98) and (Buf[2] = $BA), PageName(Id) + ' byte 01h -> E2 98 BA');
  end;
  Select(866);
end;

procedure TestFallback;
const
  Dashes: array[0..11] of Word = ($2500, $2501, $2504, $2505, $2508, $2509, $254C, $254D, $2574, $2576, $257C, $257E);
  Bars: array[0..12] of Word = ($2502, $2503, $2506, $2507, $250A, $250B, $254E, $254F, $2551, $2575, $2577, $257D, $257F);
  Plus: array[0..7] of Word = ($250C, $2510, $2554, $2557, $253C, $256C, $2552, $2561);
var
  Index: Integer;
  Cp: LongWord;
  Ok: Boolean;
begin
  for Index := 0 to High(Dashes) do
    Check(CpFallback(Dashes[Index]) = Ord('-'), 'fallback U+' + Hex(Dashes[Index]) + ' is -');
  Ok := True;
  for Cp := $2580 to $2587 do
    if CpFallback(Cp) <> Ord('-') then
      Ok := False;
  Check(Ok, 'fallback U+2580..U+2587 is -');
  Check(CpFallback($2013) = Ord('-'), 'fallback U+2013 is -');
  Check(CpFallback($2014) = Ord('-'), 'fallback U+2014 is -');
  Check(CpFallback($2550) = Ord('='), 'fallback U+2550 is =');
  for Index := 0 to High(Bars) do
    Check(CpFallback(Bars[Index]) = Ord('|'), 'fallback U+' + Hex(Bars[Index]) + ' is |');
  Ok := True;
  for Cp := $2589 to $2590 do
    if CpFallback(Cp) <> Ord('|') then
      Ok := False;
  Check(Ok, 'fallback U+2589..U+2590 is |');
  Check(CpFallback($2588) = Ord('#'), 'fallback U+2588 is #');
  Check(CpFallback($2591) = Ord('.'), 'fallback U+2591 is .');
  Check(CpFallback($2592) = Ord(':'), 'fallback U+2592 is :');
  Check(CpFallback($2593) = Ord('%'), 'fallback U+2593 is %');
  Check(CpFallback($2190) = Ord('<'), 'fallback U+2190 is <');
  Check(CpFallback($25C4) = Ord('<'), 'fallback U+25C4 is <');
  Check(CpFallback($2192) = Ord('>'), 'fallback U+2192 is >');
  Check(CpFallback($25BA) = Ord('>'), 'fallback U+25BA is >');
  Check(CpFallback($2191) = Ord('^'), 'fallback U+2191 is ^');
  Check(CpFallback($25B2) = Ord('^'), 'fallback U+25B2 is ^');
  Check(CpFallback($2193) = Ord('v'), 'fallback U+2193 is v');
  Check(CpFallback($25BC) = Ord('v'), 'fallback U+25BC is v');
  Check(CpFallback($2022) = Ord('*'), 'fallback U+2022 is *');
  Check(CpFallback($2219) = Ord('*'), 'fallback U+2219 is *');
  Check(CpFallback($25CF) = Ord('*'), 'fallback U+25CF is *');
  Check(CpFallback($2018) = $27, 'fallback U+2018 is an apostrophe');
  Check(CpFallback($2019) = $27, 'fallback U+2019 is an apostrophe');
  Check(CpFallback($201C) = $22, 'fallback U+201C is a double quote');
  Check(CpFallback($201D) = $22, 'fallback U+201D is a double quote');
  Check(CpFallback($00A0) = $20, 'fallback U+00A0 is a space');
  for Index := 0 to High(Plus) do
    Check(CpFallback(Plus[Index]) = Ord('+'), 'fallback U+' + Hex(Plus[Index]) + ' is +');
  Check(CpFallback($2500) = Ord('-'), 'fallback U+2500 is -');
  Check(CpFallback($2551) = Ord('|'), 'fallback U+2551 is |');
  Check(CpFallback($2554) = Ord('+'), 'fallback U+2554 is +');
  Check(CpFallback($2588) = Ord('#'), 'fallback U+2588 is #');
  Check(CpFallback($2190) = Ord('<'), 'fallback U+2190 is < (example)');
  Check(CpFallback($4E2D) = 0, 'fallback U+4E2D is 0');
  Check(CpFallback($0041) = 0, 'fallback U+0041 is 0');
  Check(CpFallback(0) = 0, 'fallback U+0000 is 0');
  Check(CpFallback($24FF) = 0, 'fallback U+24FF (below the box block) is 0');
  Check(CpFallback($2594) = 0, 'fallback U+2594 is 0');
  Check(CpFallback($FFFD) = 0, 'fallback U+FFFD is 0');
  Check(CpFallback($12500) = 0, 'fallback of a code point above FFFFh is 0');
  Select(437);
  Check(CpFallback($2500) = Ord('-'), 'fallback does not depend on the current page');
  Select(866);
end;

procedure TestGlyphCoverage;
var
  PageIndex, GlyphIndex: Integer;
  Id: Integer;
  Covered, ShadesCovered: Boolean;
  Cp: LongWord;
  ShadeList: array[0..4] of Word;
begin
  ShadeList[0] := $2591;
  ShadeList[1] := $2592;
  ShadeList[2] := $2593;
  ShadeList[3] := $2219;
  ShadeList[4] := $25B2;
  for PageIndex := 0 to PageLast do
  begin
    Id := PageNumberAt(PageIndex);
    Select(Id);
    Covered := True;
    for GlyphIndex := 0 to High(FrameGlyphs) do
    begin
      Cp := FrameGlyphs[GlyphIndex];
      if (CpFromUnicode(Cp) = 0) and (CpFallback(Cp) = 0) then
        Covered := False;
    end;
    Check(Covered, PageName(Id) + ' the 11 frame glyphs each have a byte or a fallback');
    ShadesCovered := True;
    for GlyphIndex := 0 to High(ShadeList) do
    begin
      Cp := ShadeList[GlyphIndex];
      if (CpFromUnicode(Cp) = 0) and (CpFallback(Cp) = 0) then
        ShadesCovered := False;
    end;
    Check(ShadesCovered, PageName(Id) + ' U+2591..U+2593, U+2219 and U+25B2 each have a byte or a fallback');
  end;
  Select(866);
end;

begin
  TestDefaultAndSelection;
  TestAllSelectable;
  TestSpotValues;
  TestLowHalfAndAscii;
  TestUndefinedBytes;
  TestFrames;
  TestPageDifferences;
  TestFromUnicode;
  TestToUtf8;
  TestFallback;
  TestGlyphCoverage;
  Done;
end.
