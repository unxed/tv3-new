{ Single-byte OEM code pages: the one current page, the byte -> Unicode map, its reverse, the UTF-8 form of a
  byte and plain ASCII substitutes for characters that a page lacks. }
unit TvCodePages;

{$mode objfpc}
{$H+}
{$POINTERMATH ON}

interface

const
  cpIdCp437 = 437;
  cpIdCp866 = 866;
  cpIdCp1125 = 1125;

{ Makes the page with the given number current. Returns False and changes nothing when the number is unknown. }
function CpSelect(Id: Integer): Boolean;

{ Returns the number of the current page. }
function CpCurrent: Integer;

{ Returns the Unicode value that the current page shows for B; $FFFD for an undefined byte. }
function CpToUnicode(B: Byte): LongWord;

{ Returns the lowest byte of the current page that shows CodePoint, 0 when there is none. }
function CpFromUnicode(CodePoint: LongWord): Byte;

{ Writes the UTF-8 form of CpToUnicode(B) to Buf (room for 4 bytes, no terminator) and returns its length. }
function CpToUtf8(B: Byte; Buf: PByte): Integer;

{ Returns the ASCII byte that stands for CodePoint on a page that lacks it, 0 when there is none. }
function CpFallback(CodePoint: LongWord): Byte;

implementation

uses
  TvUtf8;

{$I tvcp.inc}

type
  TPageTable = array[0..255] of Word;
  PPageTable = ^TPageTable;

  TReversePair = record
    Value: Word;
    Code: Byte;
  end;

var
  CurrentId: Integer;
  CurrentTable: PPageTable;
  ReverseMap: array[0..255] of TReversePair;
  ReverseCount: Integer;

{ Returns the table of the page with the given number, nil when the number is not a built-in page. }
function TableOfPage(Id: Integer): PPageTable;
begin
  case Id of
    437: Result := @Cp437;
    737: Result := @Cp737;
    775: Result := @Cp775;
    850: Result := @Cp850;
    852: Result := @Cp852;
    855: Result := @Cp855;
    857: Result := @Cp857;
    858: Result := @Cp858;
    860: Result := @Cp860;
    861: Result := @Cp861;
    862: Result := @Cp862;
    863: Result := @Cp863;
    864: Result := @Cp864;
    865: Result := @Cp865;
    866: Result := @Cp866;
    869: Result := @Cp869;
    1125: Result := @Cp1125;
  else
    Result := nil;
  end;
end;

function IsUndefined(const Table: TPageTable; B: Integer): Boolean;
begin
  Result := (B >= $80) and (Table[B] = 0);
end;

{ Fills ReverseMap with the pairs of all defined bytes, sorted by value and, for equal values, by byte. }
procedure BuildReverseMap;
var
  ByteValue: Integer;
  Position: Integer;
  Pair: TReversePair;
begin
  ReverseCount := 0;
  for ByteValue := 0 to 255 do
  begin
    if IsUndefined(CurrentTable^, ByteValue) then
      Continue;
    Pair.Value := CurrentTable^[ByteValue];
    Pair.Code := Byte(ByteValue);
    { Bytes arrive in ascending order, so inserting after all pairs with a value not above the new one keeps ties
      ordered by byte. }
    Position := ReverseCount;
    while (Position > 0) and (ReverseMap[Position - 1].Value > Pair.Value) do
    begin
      ReverseMap[Position] := ReverseMap[Position - 1];
      Dec(Position);
    end;
    ReverseMap[Position] := Pair;
    Inc(ReverseCount);
  end;
end;

function CpSelect(Id: Integer): Boolean;
var
  Table: PPageTable;
begin
  Table := TableOfPage(Id);
  Result := Table <> nil;
  if not Result then
    Exit;
  CurrentId := Id;
  CurrentTable := Table;
  BuildReverseMap;
end;

function CpCurrent: Integer;
begin
  Result := CurrentId;
end;

function CpToUnicode(B: Byte): LongWord;
var
  Entry: Word;
begin
  Entry := CurrentTable^[B];
  if (B >= $80) and (Entry = 0) then
    Result := $FFFD
  else
    Result := Entry;
end;

function CpFromUnicode(CodePoint: LongWord): Byte;
var
  LowIndex, HighIndex, MiddleIndex: Integer;
begin
  Result := 0;
  if (CodePoint > $FFFF) or (CodePoint = $FFFD) then
    Exit;
  { Find the first pair whose value is not below CodePoint; it carries the lowest byte of that value. }
  LowIndex := 0;
  HighIndex := ReverseCount;
  while LowIndex < HighIndex do
  begin
    MiddleIndex := (LowIndex + HighIndex) div 2;
    if ReverseMap[MiddleIndex].Value < CodePoint then
      LowIndex := MiddleIndex + 1
    else
      HighIndex := MiddleIndex;
  end;
  if (LowIndex < ReverseCount) and (ReverseMap[LowIndex].Value = CodePoint) then
    Result := ReverseMap[LowIndex].Code;
end;

function CpToUtf8(B: Byte; Buf: PByte): Integer;
var
  Value: LongWord;
  Encoded: TUtf8Bytes;
  Index: Integer;
begin
  Value := CpToUnicode(B);
  if Value < $80 then
  begin
    Buf^ := Byte(Value);
    Result := 1;
    Exit;
  end;
  Result := Integer(Utf32To8(Value, Encoded));
  for Index := 0 to Result - 1 do
    Buf[Index] := Encoded[Index];
end;

function CpFallback(CodePoint: LongWord): Byte;
begin
  case CodePoint of
    $2500, $2501, $2504, $2505, $2508, $2509, $254C, $254D, $2574, $2576, $257C, $257E,
    $2580..$2587, $2013, $2014:
      Result := Ord('-');
    $2550:
      Result := Ord('=');
    $2502, $2503, $2506, $2507, $250A, $250B, $254E, $254F, $2551, $2575, $2577, $257D, $257F,
    $2589..$2590:
      Result := Ord('|');
    $2588:
      Result := Ord('#');
    $2591:
      Result := Ord('.');
    $2592:
      Result := Ord(':');
    $2593:
      Result := Ord('%');
    $2190, $25C4:
      Result := Ord('<');
    $2192, $25BA:
      Result := Ord('>');
    $2191, $25B2:
      Result := Ord('^');
    $2193, $25BC:
      Result := Ord('v');
    $2022, $2219, $25CF:
      Result := Ord('*');
    $2018, $2019:
      Result := $27;
    $201C, $201D:
      Result := $22;
    $00A0:
      Result := $20;
  else
    Result := 0;
  end;
  { Every other character of the box-drawing block is drawn as a corner or a junction. }
  if (Result = 0) and (CodePoint >= $2500) and (CodePoint <= $257F) then
    Result := Ord('+');
end;

initialization
  CpSelect(cpIdCp866);
end.
