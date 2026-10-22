{ Operations on strings that may hold UTF-8 text, by character, by screen cell and by case, keeping stray bytes. }
unit TvUStr;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvUtf8;

{ --- bytes and columns --- }

{ The byte length of the character that starts at byte index Idx; 0 when Idx is outside the string. }
function U8CharBytes(const S: AnsiString; Idx: Integer): Integer;

{ True when every byte of S is below $80. }
function U8IsAscii(const S: AnsiString): Boolean;

{ The number of characters (columns) of S. }
function U8Len(const S: AnsiString): Integer;

{ The byte index at which the 0-based column Col starts. }
function U8Idx(const S: AnsiString; Col: Integer): Integer;

{ The column of the byte at index Idx. }
function U8Col(const S: AnsiString; Idx: Integer): Integer;

{ The byte index of the start of the character before Idx. }
function U8PrevIdx(const S: AnsiString; Idx: Integer): Integer;

{ --- cutting (columns are 0-based) --- }

{ The Cnt characters from column Col. }
function U8Copy(const S: AnsiString; Col, Cnt: Integer): AnsiString;

{ The character at column Col, or '' outside the string. }
function U8Char(const S: AnsiString; Col: Integer): AnsiString;

{ Removes the Cnt characters from column Col. }
procedure U8Delete(var S: AnsiString; Col, Cnt: Integer); overload;
procedure U8Delete(var S: ShortString; Col, Cnt: Integer); overload;

{ Inserts Sub before column Col. }
procedure U8Insert(const Sub: AnsiString; var S: AnsiString; Col: Integer); overload;
procedure U8Insert(const Sub: AnsiString; var S: ShortString; Col: Integer); overload;

{ The first byte of the character at column Col, or a space outside the string. }
function U8ColChar(const S: AnsiString; Col: Integer): Char;

{ The code point of the character at column Col; the byte value for a stray byte; 0 outside the string. }
function U8CodePoint(const S: AnsiString; Col: Integer): LongWord;

{ The UTF-8 bytes of the code point CP. }
function U8Encode(CP: LongWord): AnsiString;

{ The longest beginning of S of at most MaxBytes bytes that does not end inside a character. }
function U8Prefix(const S: AnsiString; MaxBytes: Integer): AnsiString;

{ Removes the last character. }
procedure U8DeleteLast(var S: AnsiString); overload;
procedure U8DeleteLast(var S: ShortString); overload;

{ --- screen cells --- }

{ The number of screen cells of Cnt columns from column Col. }
function U8Cells(const S: AnsiString; Col, Cnt: Integer): Integer;

{ The number of screen cells of S. }
function U8Cols(const S: AnsiString): Integer;

{ The column drawn at the 0-based screen cell Cell. }
function U8ColAtCell(const S: AnsiString; Cell: Integer): Integer;

{ S followed by the spaces that fill it up to Cells cells. }
function U8Pad(const S: AnsiString; Cells: Integer): AnsiString;

{ The longest beginning of S that takes at most Cells cells. }
function U8Fit(const S: AnsiString; Cells: Integer): AnsiString;

{ --- case --- }

{ The upper-case and the lower-case form of a code point. }
function CpUpper(CP: LongWord): LongWord;
function CpLower(CP: LongWord): LongWord;

{ The string with every character in upper case, in lower case, and with its first character in upper case. }
function U8Upper(const S: AnsiString): AnsiString;
function U8Lower(const S: AnsiString): AnsiString;
function U8CapFirst(const S: AnsiString): AnsiString;

{ True when A and B are the same bytes or have the same lower-case form. }
function U8EqualNoCase(const A, B: AnsiString): Boolean;

implementation

const
  AsciiLimit = $80;
  ContFirst = $80;
  ContLast = $BF;

function IsCont(B: Byte): Boolean;
begin
  Result := (B >= ContFirst) and (B <= ContLast);
end;

{ The length of the valid UTF-8 sequence that starts at byte index Idx (1 for an ASCII byte) and its code point;
  0 when the bytes from Idx on do not begin a valid, complete sequence. Idx lies inside S. }
function SeqAt(const S: AnsiString; Idx: Integer; out CP: LongWord): Integer;
var
  First, Next, LoLim, HiLim: Byte;
  Need, K: Integer;
  Acc: LongWord;
begin
  Result := 0;
  CP := 0;
  First := Ord(S[Idx]);
  if First < AsciiLimit then
  begin
    CP := First;
    Result := 1;
    Exit;
  end;
  LoLim := ContFirst;
  HiLim := ContLast;
  case First of
    $C2..$DF:
      begin
        Need := 1;
        Acc := First and $1F;
      end;
    $E0..$EF:
      begin
        Need := 2;
        Acc := First and $0F;
        if First = $E0 then
          LoLim := $A0
        else if First = $ED then
          HiLim := $9F;
      end;
    $F0..$F4:
      begin
        Need := 3;
        Acc := First and $07;
        if First = $F0 then
          LoLim := $90
        else if First = $F4 then
          HiLim := $8F;
      end;
  else
    Exit;
  end;
  if Length(S) - Idx < Need then
    Exit;
  for K := 1 to Need do
  begin
    Next := Ord(S[Idx + K]);
    if (Next < LoLim) or (Next > HiLim) then
      Exit;
    Acc := (Acc shl 6) or (Next and $3F);
    LoLim := ContFirst;
    HiLim := ContLast;
  end;
  CP := Acc;
  Result := Need + 1;
end;

{ The length and the code point of the character at byte index Idx in the current mode; a stray byte is its own
  code point. Idx lies inside S. }
function CharAt(const S: AnsiString; Idx: Integer; out CP: LongWord): Integer;
begin
  Result := 0;
  if Utf8Enabled then
    Result := SeqAt(S, Idx, CP);
  if Result = 0 then
  begin
    Result := 1;
    CP := Ord(S[Idx]);
  end;
end;

{ True when every character takes one byte and one cell. }
function ByteWise(const S: AnsiString): Boolean;
begin
  Result := (not Utf8Enabled) or U8IsAscii(S);
end;

{ The cells of a character of Len bytes with code point CP. }
function CellsOf(Len: Integer; CP: LongWord): Integer;
begin
  Result := 1;
  if Len > 1 then
  begin
    Result := CharWidth(CP);
    if Result < 0 then
      Result := 1;
  end;
end;

{ The bytes First .. After-1 of the characters of the columns Col .. Col+Cnt-1; False when there are none. }
function Span(const S: AnsiString; Col, Cnt: Integer; out First, After: Integer): Boolean;
var
  Num, Taken: Int64;
  CP: LongWord;
begin
  Result := False;
  First := 1;
  After := 1;
  Num := Cnt;
  if Col < 0 then
  begin
    Num := Num + Col;
    Col := 0;
  end;
  if Num <= 0 then
    Exit;
  First := U8Idx(S, Col);
  if First > Length(S) then
    Exit;
  After := First;
  Taken := 0;
  while (Taken < Num) and (After <= Length(S)) do
  begin
    Inc(After, CharAt(S, After, CP));
    Inc(Taken);
  end;
  Result := True;
end;

{ The length that S has after its last character is removed. }
function LengthWithoutLast(const S: AnsiString): Integer;
begin
  Result := Length(S);
  if Result = 0 then
    Exit;
  if Utf8Enabled then
    while (Result > 1) and IsCont(Ord(S[Result])) do
      Dec(Result);
  Dec(Result);
end;

{ --- bytes and columns --- }

function U8CharBytes(const S: AnsiString; Idx: Integer): Integer;
var
  CP: LongWord;
begin
  if (Idx <= 0) or (Idx > Length(S)) then
    Result := 0
  else
    Result := CharAt(S, Idx, CP);
end;

function U8IsAscii(const S: AnsiString): Boolean;
var
  Run, Total: Integer;
begin
  Total := Length(S);
  Run := 1;
  while (Run <= Total) and (Ord(S[Run]) < AsciiLimit) do
    Inc(Run);
  Result := Run > Total;
end;

function U8Len(const S: AnsiString): Integer;
var
  I, N: Integer;
  CP: LongWord;
begin
  if ByteWise(S) then
  begin
    Result := Length(S);
    Exit;
  end;
  I := 1;
  N := 0;
  while I <= Length(S) do
  begin
    Inc(I, CharAt(S, I, CP));
    Inc(N);
  end;
  Result := N;
end;

function U8Idx(const S: AnsiString; Col: Integer): Integer;
var
  N: Integer;
  CP: LongWord;
begin
  Result := 1;
  if Col <= 0 then
    Exit;
  if ByteWise(S) then
  begin
    if Col > Length(S) then
      Col := Length(S);
    Result := Col + 1;
    Exit;
  end;
  N := 0;
  while (N < Col) and (Result <= Length(S)) do
  begin
    Inc(Result, CharAt(S, Result, CP));
    Inc(N);
  end;
end;

function U8Col(const S: AnsiString; Idx: Integer): Integer;
var
  I, N, Len: Integer;
  CP: LongWord;
begin
  Result := 0;
  if Idx <= 1 then
    Exit;
  if ByteWise(S) then
  begin
    Result := Idx - 1;
    Exit;
  end;
  I := 1;
  N := 0;
  while I <= Length(S) do
  begin
    Len := CharAt(S, I, CP);
    if I + Len > Idx then
      Break;
    Inc(I, Len);
    Inc(N);
  end;
  if I > Length(S) then
    Inc(N, Idx - I);
  Result := N;
end;

function U8PrevIdx(const S: AnsiString; Idx: Integer): Integer;
var
  I: Integer;
  CP: LongWord;
begin
  Result := 1;
  if Idx <= 1 then
    Exit;
  if not Utf8Enabled then
  begin
    Result := Idx - 1;
    Exit;
  end;
  I := 1;
  while I < Idx do
  begin
    if I > Length(S) then
    begin
      Result := Idx - 1;
      Exit;
    end;
    Result := I;
    Inc(I, CharAt(S, I, CP));
  end;
end;

{ --- cutting --- }

function U8Copy(const S: AnsiString; Col, Cnt: Integer): AnsiString;
var
  First, After: Integer;
begin
  Result := '';
  if Span(S, Col, Cnt, First, After) then
    Result := Copy(S, First, After - First);
end;

function U8Char(const S: AnsiString; Col: Integer): AnsiString;
begin
  Result := U8Copy(S, Col, 1);
end;

procedure U8Delete(var S: AnsiString; Col, Cnt: Integer);
var
  First, After: Integer;
begin
  if Span(S, Col, Cnt, First, After) then
    Delete(S, First, After - First);
end;

procedure U8Delete(var S: ShortString; Col, Cnt: Integer);
var
  Work: AnsiString;
begin
  Work := S;
  U8Delete(Work, Col, Cnt);
  S := Work;
end;

procedure U8Insert(const Sub: AnsiString; var S: AnsiString; Col: Integer);
begin
  Insert(Sub, S, U8Idx(S, Col));
end;

procedure U8Insert(const Sub: AnsiString; var S: ShortString; Col: Integer);
var
  Work: AnsiString;
begin
  Work := S;
  U8Insert(Sub, Work, Col);
  S := Work;
end;

function U8ColChar(const S: AnsiString; Col: Integer): Char;
var
  Idx: Integer;
begin
  Result := ' ';
  if Col < 0 then
    Exit;
  Idx := U8Idx(S, Col);
  if Idx <= Length(S) then
    Result := S[Idx];
end;

function U8CodePoint(const S: AnsiString; Col: Integer): LongWord;
var
  Idx: Integer;
begin
  Result := 0;
  if Col < 0 then
    Exit;
  Idx := U8Idx(S, Col);
  if Idx <= Length(S) then
    CharAt(S, Idx, Result);
end;

function U8Encode(CP: LongWord): AnsiString;
begin
  if CP <= $7F then
    Result := Chr(Byte(CP))
  else if CP <= $7FF then
  begin
    SetLength(Result, 2);
    Result[1] := Chr(Byte($C0 or ((CP shr 6) and $1F)));
    Result[2] := Chr(Byte($80 or (CP and $3F)));
  end
  else if CP <= $FFFF then
  begin
    SetLength(Result, 3);
    Result[1] := Chr(Byte($E0 or ((CP shr 12) and $0F)));
    Result[2] := Chr(Byte($80 or ((CP shr 6) and $3F)));
    Result[3] := Chr(Byte($80 or (CP and $3F)));
  end
  else
  begin
    SetLength(Result, 4);
    Result[1] := Chr(Byte($F0 or ((CP shr 18) and $07)));
    Result[2] := Chr(Byte($80 or ((CP shr 12) and $3F)));
    Result[3] := Chr(Byte($80 or ((CP shr 6) and $3F)));
    Result[4] := Chr(Byte($80 or (CP and $3F)));
  end;
end;

function U8Prefix(const S: AnsiString; MaxBytes: Integer): AnsiString;
var
  N: Integer;
begin
  if MaxBytes < 0 then
    MaxBytes := 0;
  if Length(S) <= MaxBytes then
  begin
    Result := S;
    Exit;
  end;
  N := MaxBytes;
  if Utf8Enabled then
    while (N > 0) and IsCont(Ord(S[N + 1])) do
      Dec(N);
  Result := Copy(S, 1, N);
end;

procedure U8DeleteLast(var S: AnsiString);
begin
  SetLength(S, LengthWithoutLast(S));
end;

procedure U8DeleteLast(var S: ShortString);
var
  Work: AnsiString;
begin
  Work := S;
  SetLength(S, LengthWithoutLast(Work));
end;

{ --- screen cells --- }

function U8Cells(const S: AnsiString; Col, Cnt: Integer): Integer;
var
  I, Len, Done: Integer;
  Total: Int64;
  CP: LongWord;
begin
  Result := 0;
  if Cnt <= 0 then
    Exit;
  if ByteWise(S) then
  begin
    Result := Cnt;
    Exit;
  end;
  I := 1;
  if Col > 0 then
    I := U8Idx(S, Col);
  Total := 0;
  Done := 0;
  while (Done < Cnt) and (I <= Length(S)) do
  begin
    Len := CharAt(S, I, CP);
    Total := Total + CellsOf(Len, CP);
    Inc(I, Len);
    Inc(Done);
  end;
  Total := Total + (Cnt - Done);
  Result := Total;
end;

function U8Cols(const S: AnsiString): Integer;
begin
  Result := U8Cells(S, 0, U8Len(S));
end;

function U8ColAtCell(const S: AnsiString; Cell: Integer): Integer;
var
  I, Len, Col: Integer;
  Reached: Int64;
  CP: LongWord;
begin
  Result := 0;
  if Cell <= 0 then
    Exit;
  if ByteWise(S) then
  begin
    Result := Cell;
    Exit;
  end;
  I := 1;
  Col := 0;
  Reached := 0;
  while I <= Length(S) do
  begin
    Len := CharAt(S, I, CP);
    Reached := Reached + CellsOf(Len, CP);
    if Reached > Cell then
    begin
      Result := Col;
      Exit;
    end;
    Inc(I, Len);
    Inc(Col);
  end;
  Result := Col + (Cell - Reached);
end;

function U8Pad(const S: AnsiString; Cells: Integer): AnsiString;
var
  Used: Integer;
begin
  Result := S;
  Used := U8Cols(S);
  if Used < Cells then
    Result := S + StringOfChar(' ', Cells - Used);
end;

function U8Fit(const S: AnsiString; Cells: Integer): AnsiString;
var
  I, Len: Integer;
  Total: Int64;
  CP: LongWord;
begin
  Result := '';
  if Cells <= 0 then
    Exit;
  if ByteWise(S) then
  begin
    Result := Copy(S, 1, Cells);
    Exit;
  end;
  I := 1;
  Total := 0;
  while I <= Length(S) do
  begin
    Len := CharAt(S, I, CP);
    Total := Total + CellsOf(Len, CP);
    if Total > Cells then
      Break;
    Inc(I, Len);
  end;
  Result := Copy(S, 1, I - 1);
end;

{ --- case --- }

type
  TCaseKind = (ckShift, ckTarget, ckPairEven, ckPairOdd);

  { A range of code points and how its members change. ckShift: add Arg. ckTarget: become Arg.
    ckPairEven: the upper letter of a pair is the even code point. ckPairOdd: it is the odd one. }
  TCaseRange = record
    First, Last: LongWord;
    Kind: TCaseKind;
    Arg: Integer;
  end;

const
  UpperRanges: array[0..32] of TCaseRange = (
    (First: $61; Last: $7A; Kind: ckShift; Arg: -$20),
    (First: $B5; Last: $B5; Kind: ckTarget; Arg: $39C),
    (First: $E0; Last: $F6; Kind: ckShift; Arg: -$20),
    (First: $F8; Last: $FE; Kind: ckShift; Arg: -$20),
    (First: $FF; Last: $FF; Kind: ckTarget; Arg: $178),
    (First: $100; Last: $12F; Kind: ckPairEven; Arg: 0),
    (First: $131; Last: $131; Kind: ckTarget; Arg: $49),
    (First: $132; Last: $137; Kind: ckPairEven; Arg: 0),
    (First: $139; Last: $148; Kind: ckPairOdd; Arg: 0),
    (First: $14A; Last: $177; Kind: ckPairEven; Arg: 0),
    (First: $17A; Last: $17E; Kind: ckPairOdd; Arg: 0),
    (First: $17F; Last: $17F; Kind: ckTarget; Arg: $53),
    (First: $1CE; Last: $1CE; Kind: ckShift; Arg: -1),
    (First: $1E00; Last: $1E95; Kind: ckPairEven; Arg: 0),
    (First: $1EA0; Last: $1EFF; Kind: ckPairEven; Arg: 0),
    (First: $3AC; Last: $3AC; Kind: ckTarget; Arg: $386),
    (First: $3AD; Last: $3AF; Kind: ckShift; Arg: -$25),
    (First: $3B1; Last: $3C1; Kind: ckShift; Arg: -$20),
    (First: $3C3; Last: $3CB; Kind: ckShift; Arg: -$20),
    (First: $3C2; Last: $3C2; Kind: ckTarget; Arg: $3A3),
    (First: $3CC; Last: $3CC; Kind: ckTarget; Arg: $38C),
    (First: $3CD; Last: $3CE; Kind: ckShift; Arg: -$3F),
    (First: $430; Last: $44F; Kind: ckShift; Arg: -$20),
    (First: $450; Last: $45F; Kind: ckShift; Arg: -$50),
    (First: $460; Last: $481; Kind: ckPairEven; Arg: 0),
    (First: $48A; Last: $4BF; Kind: ckPairEven; Arg: 0),
    (First: $4D0; Last: $52F; Kind: ckPairEven; Arg: 0),
    (First: $4C2; Last: $4CE; Kind: ckPairOdd; Arg: 0),
    (First: $4CF; Last: $4CF; Kind: ckTarget; Arg: $4C0),
    (First: $561; Last: $586; Kind: ckShift; Arg: -$30),
    (First: $2170; Last: $217F; Kind: ckShift; Arg: -$10),
    (First: $24D0; Last: $24E9; Kind: ckShift; Arg: -$1A),
    (First: $FF41; Last: $FF5A; Kind: ckShift; Arg: -$20)
  );

  LowerRanges: array[0..29] of TCaseRange = (
    (First: $41; Last: $5A; Kind: ckShift; Arg: $20),
    (First: $C0; Last: $D6; Kind: ckShift; Arg: $20),
    (First: $D8; Last: $DE; Kind: ckShift; Arg: $20),
    (First: $100; Last: $12F; Kind: ckPairEven; Arg: 0),
    (First: $130; Last: $130; Kind: ckTarget; Arg: $69),
    (First: $132; Last: $137; Kind: ckPairEven; Arg: 0),
    (First: $139; Last: $148; Kind: ckPairOdd; Arg: 0),
    (First: $14A; Last: $177; Kind: ckPairEven; Arg: 0),
    (First: $178; Last: $178; Kind: ckTarget; Arg: $FF),
    (First: $179; Last: $17E; Kind: ckPairOdd; Arg: 0),
    (First: $1CD; Last: $1CD; Kind: ckShift; Arg: 1),
    (First: $1E00; Last: $1E95; Kind: ckPairEven; Arg: 0),
    (First: $1EA0; Last: $1EFF; Kind: ckPairEven; Arg: 0),
    (First: $386; Last: $386; Kind: ckTarget; Arg: $3AC),
    (First: $388; Last: $38A; Kind: ckShift; Arg: $25),
    (First: $38C; Last: $38C; Kind: ckTarget; Arg: $3CC),
    (First: $38E; Last: $38F; Kind: ckShift; Arg: $3F),
    (First: $391; Last: $3A1; Kind: ckShift; Arg: $20),
    (First: $3A3; Last: $3AB; Kind: ckShift; Arg: $20),
    (First: $400; Last: $40F; Kind: ckShift; Arg: $50),
    (First: $410; Last: $42F; Kind: ckShift; Arg: $20),
    (First: $460; Last: $481; Kind: ckPairEven; Arg: 0),
    (First: $48A; Last: $4BF; Kind: ckPairEven; Arg: 0),
    (First: $4D0; Last: $52F; Kind: ckPairEven; Arg: 0),
    (First: $4C0; Last: $4C0; Kind: ckTarget; Arg: $4CF),
    (First: $4C1; Last: $4CD; Kind: ckPairOdd; Arg: 0),
    (First: $531; Last: $556; Kind: ckShift; Arg: $30),
    (First: $2160; Last: $216F; Kind: ckShift; Arg: $10),
    (First: $24B6; Last: $24CF; Kind: ckShift; Arg: $1A),
    (First: $FF21; Last: $FF3A; Kind: ckShift; Arg: $20)
  );

{ The code point CP changed by the first range of Rows that holds it; Upper tells which letter of a pair CP is
  mapped to. Returns Found = False when no range holds CP. }
function MapIn(const Rows: array of TCaseRange; CP: LongWord; Upper: Boolean; out Found: Boolean): LongWord;
var
  I: Integer;
  OddCp: Boolean;
begin
  Result := CP;
  Found := False;
  OddCp := Odd(CP);
  for I := 0 to High(Rows) do
    if (CP >= Rows[I].First) and (CP <= Rows[I].Last) then
    begin
      Found := True;
      case Rows[I].Kind of
        ckShift:
          Result := LongWord(Int64(CP) + Rows[I].Arg);
        ckTarget:
          Result := LongWord(Rows[I].Arg);
        ckPairEven:
          if Upper and OddCp then
            Result := CP - 1
          else if (not Upper) and (not OddCp) then
            Result := CP + 1;
        ckPairOdd:
          if Upper and (not OddCp) then
            Result := CP - 1
          else if (not Upper) and OddCp then
            Result := CP + 1;
      end;
      Exit;
    end;
end;

function CpUpper(CP: LongWord): LongWord;
var
  Found: Boolean;
begin
  Result := MapIn(UpperRanges, CP, True, Found);
end;

function CpLower(CP: LongWord): LongWord;
var
  Found: Boolean;
begin
  Result := MapIn(LowerRanges, CP, False, Found);
end;

{ An ASCII letter in the wanted case; any other byte unchanged. }
function AsciiCase(B: Byte; Upper: Boolean): Byte;
begin
  Result := B;
  if Upper then
  begin
    if (B >= Ord('a')) and (B <= Ord('z')) then
      Result := B - $20;
  end
  else if (B >= Ord('A')) and (B <= Ord('Z')) then
    Result := B + $20;
end;

{ Makes room in R for N more bytes after the K used ones. }
procedure Reserve(var R: AnsiString; K, N: Integer);
begin
  if K + N > Length(R) then
    SetLength(R, 2 * (K + N));
end;

function MapString(const S: AnsiString; Upper: Boolean): AnsiString;
var
  I, K, Len, J: Integer;
  CP, NewCp: LongWord;
  Enc: AnsiString;
begin
  SetLength(Result, Length(S));
  if ByteWise(S) then
  begin
    for I := 1 to Length(S) do
      Result[I] := Chr(AsciiCase(Ord(S[I]), Upper));
    Exit;
  end;
  I := 1;
  K := 0;
  while I <= Length(S) do
  begin
    Len := SeqAt(S, I, CP);
    if Len <= 1 then
    begin
      Reserve(Result, K, 1);
      Inc(K);
      Result[K] := Chr(AsciiCase(Ord(S[I]), Upper));
      Inc(I);
      Continue;
    end;
    if Upper then
      NewCp := CpUpper(CP)
    else
      NewCp := CpLower(CP);
    if NewCp = CP then
    begin
      Reserve(Result, K, Len);
      for J := 0 to Len - 1 do
        Result[K + 1 + J] := S[I + J];
      Inc(K, Len);
    end
    else
    begin
      Enc := U8Encode(NewCp);
      Reserve(Result, K, Length(Enc));
      for J := 1 to Length(Enc) do
        Result[K + J] := Enc[J];
      Inc(K, Length(Enc));
    end;
    Inc(I, Len);
  end;
  SetLength(Result, K);
end;

function U8Upper(const S: AnsiString): AnsiString;
begin
  Result := MapString(S, True);
end;

function U8Lower(const S: AnsiString): AnsiString;
begin
  Result := MapString(S, False);
end;

function U8CapFirst(const S: AnsiString): AnsiString;
var
  Len: Integer;
begin
  Result := S;
  if S = '' then
    Exit;
  Len := U8CharBytes(S, 1);
  Result := U8Upper(Copy(S, 1, Len)) + Copy(S, Len + 1, Length(S));
end;

function U8EqualNoCase(const A, B: AnsiString): Boolean;
begin
  Result := (A = B) or (U8Lower(A) = U8Lower(B));
end;

end.
