{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/utf8.h, source/platform/ttext.cpp, include/tvision/ttext.h
  See COPYRIGHT.magiblot. }
unit TvUtf8;

{$mode objfpc}

interface

{ Indices into a text are zero-based, as in the C++ (the character at Index is Text[Index + 1]).
  The text is a sequence of bytes; the characters are UTF-8 sequences. }

type
  TUtf8Bytes = array[0..3] of Byte;
  TUtf16Pair = array[0..1] of Word;

  TTextMetrics = record
    Width: Cardinal;
    CharacterCount: Cardinal;
    GraphemeCount: Cardinal; { Number of non-combining characters. }
  end;

  TText = class
  public
    { Returns the width of Text. }
    class function Width(const Text: string): SizeInt; static;

    { Returns the width, the character count and the grapheme count of Text. }
    class function Measure(const Text: string): TTextMetrics; static;

    { Returns the length in bytes of the first character in Text. }
    class function Next(const Text: string): SizeInt; overload; static;

    { Increases Index by the length in bytes of the character starting at position Index of Text.
      The variant with AWidth increases AWidth by the width of the character.
      Returns whether Index was increased at all. }
    class function Next(const Text: string; var Index: SizeInt): Boolean; overload; static;
    class function Next(const Text: string; var Index, AWidth: SizeInt): Boolean; overload; static;
    class function Next(const Text: array of Cardinal; var Index, AWidth: SizeInt): Boolean; overload; static;

    { Returns the length in bytes of the character in Text right before position Index. }
    class function Prev(const Text: string; Index: SizeInt): SizeInt; static;

    { Returns the length in bytes of a leading substring of Text which is Count columns wide.
      If Text is less than Count columns wide, returns the length of Text.
      Negative values of Count are treated as 0.
      The variants with ALength and AWidth return the length and the width of the substring.
      When column Count is in the middle of a double-width character in Text, IncludeIncomplete
      determines whether the double-width character is included in the result. }
    class function Scroll(const Text: string; Count: Integer; IncludeIncomplete: Boolean): SizeInt; overload; static;
    class procedure Scroll(const Text: string; Count: Integer; IncludeIncomplete: Boolean;
      var ALength, AWidth: SizeInt); overload; static;
    class procedure Scroll(const Text: array of Cardinal; Count: Integer; IncludeIncomplete: Boolean;
      var ALength, AWidth: SizeInt); overload; static;
  end;

{ Returns the number of continuation bytes that follow FirstByte, 0 when it does not start a sequence. }
function Utf8BytesLeft(FirstByte: Byte): Cardinal;

{ Pre: S is a valid UTF-8 sequence of one to four bytes. }
function Utf8To32(const S: string): Cardinal;

{ Writes the UTF-8 sequence of U32 into U8 and returns its length. }
function Utf32To8(U32: Cardinal; var U8: TUtf8Bytes): SizeInt;

{ Pre: U16 is a valid UTF-16 sequence. If the character is a single code unit, U16[1] = 0. }
function Utf16To8(const U16: TUtf16Pair; var U8: TUtf8Bytes): SizeInt;

{ Returns the number of code units written into U16, or -1. }
function Utf32To16(U32: Cardinal; var U16: TUtf16Pair): Integer;

{ Returns the width in columns of the code point Cp: -1 for a control character, 0 for a combining or
  other zero-width character, 2 for a double-width character, 1 otherwise. }
function CharWidth(Cp: Cardinal): Integer;

var
  { True: text that is valid UTF-8 is treated as UTF-8. False: the bytes of the text are the bytes of the current
    code page, so one byte is one character and nothing is decoded. }
  Utf8Enabled: Boolean = True;

implementation

{$I tvwidth.inc}

type
  TUtf8Table = array[0..363] of Byte;

const
  Utf8Accept = 0;
  Utf8Reject = 12;

  Utf8D: TUtf8Table = (
    { The first part of the table maps bytes to character classes. }
     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
     1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,  9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
     7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
     8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    10,3,3,3,3,3,3,3,3,3,3,3,3,4,3,3, 11,6,6,6,5,8,8,8,8,8,8,8,8,8,8,8,

    { The second part is a transition table that maps a combination of a state of the automaton and a
      character class to a state. }
     0,12,24,36,60,96,84,12,12,12,48,72, 12,12,12,12,12,12,12,12,12,12,12,12,
    12, 0,12,12,12,12,12, 0,12, 0,12,12, 12,24,12,12,12,12,12,24,12,24,12,12,
    12,12,12,12,12,12,12,24,12,12,12,12, 12,24,12,12,12,12,12,12,12,24,12,12,
    12,12,12,12,12,12,12,36,12,36,12,12, 12,36,12,12,12,12,12,36,12,36,12,12,
    12,36,12,12,12,12,12,12,12,12,12,12
  );

type
  TLw = record
    Length, Width: SizeInt;
  end;

  TMbStat = record
    Length, Width: Integer;
  end;

function MaxInt(P, Q: Integer): Integer;
begin
  if P > Q then
    Result := P
  else
    Result := Q;
end;

function MinInt(P, Q: SizeInt): SizeInt;
begin
  if P < Q then
    Result := P
  else
    Result := Q;
end;

function InRanges(const Firsts, Lasts: array of Cardinal; Cp: Cardinal): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Result := False;
  Lo := 0;
  Hi := High(Firsts);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if Cp < Firsts[Mid] then
      Hi := Mid - 1
    else if Cp > Lasts[Mid] then
      Lo := Mid + 1
    else
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function CharWidth(Cp: Cardinal): Integer;
begin
  if (Cp < $20) or ((Cp >= $7F) and (Cp <= $9F)) then
    Result := -1
  else if InRanges(ZeroWidthFirst, ZeroWidthLast, Cp) then
    Result := 0
  else if InRanges(DoubleWidthFirst, DoubleWidthLast, Cp) then
    Result := 2
  else
    Result := 1;
end;

function Utf8BytesLeft(FirstByte: Byte): Cardinal;
begin
  if (FirstByte and $E0) = $C0 then
    Result := 1
  else if (FirstByte and $F0) = $E0 then
    Result := 2
  else if (FirstByte and $F8) = $F0 then
    Result := 3
  else
    Result := 0;
end;

function Utf8To32(const S: string): Cardinal;
begin
  case Length(S) of
    1:
      Result := Byte(S[1]);
    2:
      Result := ((Byte(S[1]) and $1F) shl 6) or (Byte(S[2]) and $3F);
    3:
      Result := ((Byte(S[1]) and $0F) shl 12) or ((Byte(S[2]) and $3F) shl 6) or (Byte(S[3]) and $3F);
    4:
      Result := ((Byte(S[1]) and $0F) shl 18) or ((Byte(S[2]) and $3F) shl 12) or
        ((Byte(S[3]) and $3F) shl 6) or (Byte(S[4]) and $3F);
  else
    Result := 0;
  end;
end;

function Utf32To8(U32: Cardinal; var U8: TUtf8Bytes): SizeInt;
var
  AsInt: Cardinal;
  I: Integer;
begin
  if U32 <= $007F then
  begin
    AsInt := U32;
    Result := 1;
  end
  else if U32 <= $07FF then
  begin
    AsInt :=
      (((U32 shr 6) and $1F) or $C0) or
      (((U32 and $3F) or $80) shl 8);
    Result := 2;
  end
  else if U32 <= $FFFF then
  begin
    AsInt :=
      (((U32 shr 12) and $0F) or $E0) or
      ((((U32 shr 6) and $3F) or $80) shl 8) or
      (((U32 and $3F) or $80) shl 16);
    Result := 3;
  end
  else
  begin
    AsInt :=
      (((U32 shr 18) and $07) or $F0) or
      ((((U32 shr 12) and $3F) or $80) shl 8) or
      ((((U32 shr 6) and $3F) or $80) shl 16) or
      (((U32 and $3F) or $80) shl 24);
    Result := 4;
  end;
  { The first byte of the sequence is the first byte of U8, whatever the byte order. }
  for I := 0 to 3 do
    U8[I] := Byte((AsInt shr (8 * I)) and $FF);
end;

function Utf16To8(const U16: TUtf16Pair; var U8: TUtf8Bytes): SizeInt;
var
  U32: Cardinal;
begin
  if U16[1] = 0 then
    U32 := U16[0]
  else
    U32 := ((Cardinal(U16[0]) - $D800) shl 10) or (Cardinal(U16[1]) - $DC00) or $10000;
  Result := Utf32To8(U32, U8);
end;

function Utf32To16(U32: Cardinal; var U16: TUtf16Pair): Integer;
begin
  if (U32 <= $FFFF) and ((U32 < $D800) or ($DFFF < U32)) then
  begin
    U16[0] := Word(U32);
    Result := 1;
  end
  else if U32 < $10FFFF then { Two surrogates. }
  begin
    U16[0] := Word(((U32 - $10000) shr 10) + $D800);
    U16[1] := Word(((U32 - $10000) and $3FF) + $DC00);
    Result := 2;
  end
  else
    Result := -1;
end;

function DecodeUtf8(var State, Codep: Cardinal; B: Byte): Cardinal; overload;
var
  AType: Cardinal;
begin
  AType := Utf8D[B];
  if State <> Utf8Accept then
    Codep := (B and $3F) or (Codep shl 6)
  else
    Codep := ($FF shr AType) and B;
  State := Utf8D[256 + State + AType];
  Result := State;
end;

function DecodeUtf8(var State: Cardinal; B: Byte): Cardinal; overload;
var
  AType: Cardinal;
begin
  AType := Utf8D[B];
  State := Utf8D[256 + State + AType];
  Result := State;
end;

{ The functions below work on the Count bytes of Text that start at the zero-based position Start.
  Pre: Count > 0. }

function MbToWc(var Wc: Cardinal; const Text: string; Start, Count: SizeInt): Integer;
{ Returns n >= 1 if the bytes begin with a UTF-8 multibyte character that is n bytes long, -1 otherwise. }
var
  State, Codep: Cardinal;
  I: SizeInt;
begin
  State := 0;
  Codep := 0;
  for I := 0 to Count - 1 do
    case DecodeUtf8(State, Codep, Byte(Text[Start + I + 1])) of
      Utf8Accept:
        begin
          Wc := Codep;
          Result := I + 1;
          Exit;
        end;
      Utf8Reject:
        begin
          Result := -1;
          Exit;
        end;
    end;
  Result := -1;
end;

function MbLen(const Text: string; Start, Count: SizeInt): Integer;
{ Returns n >= 1 if the bytes begin with a UTF-8 multibyte character that is n bytes long, -1 otherwise. }
var
  State: Cardinal;
  I: SizeInt;
begin
  State := 0;
  for I := 0 to Count - 1 do
    case DecodeUtf8(State, Byte(Text[Start + I + 1])) of
      Utf8Accept:
        begin
          Result := I + 1;
          Exit;
        end;
      Utf8Reject:
        begin
          Result := -1;
          Exit;
        end;
    end;
  Result := -1;
end;

function MbStat(const Text: string; Start, Count: SizeInt): TMbStat;
var
  Wc: Cardinal;
begin
  Wc := 0;
  Result.Length := MbToWc(Wc, Text, Start, Count);
  Result.Width := 1;
  if Result.Length > 1 then
    Result.Width := CharWidth(Wc);
end;

{ The length of the character that starts at Start, 0 at the end of Text. }
function NextLen(const Text: string; Start: SizeInt): SizeInt;
var
  Count: SizeInt;
begin
  Count := Length(Text) - Start;
  if Count > 0 then
    Result := MaxInt(MbLen(Text, Start, Count), 1)
  else
    Result := 0;
end;

function NextImpl(const Text: string; Start: SizeInt): TLw; overload;
var
  Count: SizeInt;
  Mb: TMbStat;
begin
  Count := Length(Text) - Start;
  if Count > 0 then
  begin
    Mb := MbStat(Text, Start, Count);
    if Mb.Length <= 1 then
    begin
      Result.Length := 1;
      Result.Width := 1;
      Exit;
    end;
    Result.Length := Mb.Length;
    if Mb.Width <> 0 then
      Result.Width := MaxInt(Mb.Width, 1)
    else
      Result.Width := 0;
    Exit;
  end;
  Result.Length := 0;
  Result.Width := 0;
end;

function NextImpl(const Text: array of Cardinal; Start: SizeInt): TLw; overload;
var
  Width: Integer;
begin
  if Length(Text) - Start > 0 then
  begin
    Width := CharWidth(Text[Start]);
    Result.Length := 1;
    if Width <> 0 then
      Result.Width := MaxInt(Width, 1)
    else
      Result.Width := 0;
    Exit;
  end;
  Result.Length := 0;
  Result.Width := 0;
end;

{ TText }

class function TText.Width(const Text: string): SizeInt;
var
  I, W: SizeInt;
begin
  I := 0;
  W := 0;
  while TText.Next(Text, I, W) do
    ;
  Result := W;
end;

class function TText.Measure(const Text: string): TTextMetrics;
var
  I, W: SizeInt;
begin
  FillChar(Result, SizeOf(Result), 0);
  I := 0;
  while True do
  begin
    W := 0;
    if not TText.Next(Text, I, W) then
      Break;
    Inc(Result.Width, Cardinal(W));
    Inc(Result.CharacterCount);
    if W > 0 then
      Inc(Result.GraphemeCount);
  end;
end;

class function TText.Next(const Text: string): SizeInt;
begin
  Result := NextLen(Text, 0);
end;

class function TText.Next(const Text: string; var Index: SizeInt): Boolean;
var
  Len: SizeInt;
begin
  Len := NextLen(Text, Index);
  Inc(Index, Len);
  Result := Len <> 0;
end;

class function TText.Next(const Text: string; var Index, AWidth: SizeInt): Boolean;
var
  R: TLw;
begin
  R := NextImpl(Text, Index);
  Inc(Index, R.Length);
  Inc(AWidth, R.Width);
  Result := R.Length <> 0;
end;

class function TText.Next(const Text: array of Cardinal; var Index, AWidth: SizeInt): Boolean;
var
  R: TLw;
begin
  R := NextImpl(Text, Index);
  Inc(Index, R.Length);
  Inc(AWidth, R.Width);
  Result := R.Length <> 0;
end;

class function TText.Prev(const Text: string; Index: SizeInt): SizeInt;
var
  Lead, I: SizeInt;
  Len: Integer;
begin
  if Index <> 0 then
  begin
    { Try reading backwards character by character, until a valid character is found.
      This tolerates invalid characters. }
    Lead := MinInt(Index, 4);
    for I := 1 to Lead do
    begin
      Len := MbLen(Text, Index - I, I);
      if Len > 0 then
      begin
        if Len = I then
          Result := I
        else
          Result := 1;
        Exit;
      end;
    end;
    Result := 1;
    Exit;
  end;
  Result := 0;
end;

class function TText.Scroll(const Text: string; Count: Integer; IncludeIncomplete: Boolean): SizeInt;
var
  ALength, AWidth: SizeInt;
begin
  ALength := 0;
  AWidth := 0;
  TText.Scroll(Text, Count, IncludeIncomplete, ALength, AWidth);
  Result := ALength;
end;

class procedure TText.Scroll(const Text: string; Count: Integer; IncludeIncomplete: Boolean;
  var ALength, AWidth: SizeInt);
var
  I, W, I2, W2: SizeInt;
begin
  I := 0;
  W := 0;
  if Count > 0 then
    while True do
    begin
      I2 := I;
      W2 := W;
      if (not TText.Next(Text, I, W)) or (W = Count) then
        Break;
      if W > Count then
      begin
        if not IncludeIncomplete then
        begin
          I := I2;
          W := W2;
        end;
        Break;
      end;
    end;
  ALength := I;
  AWidth := W;
end;

class procedure TText.Scroll(const Text: array of Cardinal; Count: Integer; IncludeIncomplete: Boolean;
  var ALength, AWidth: SizeInt);
var
  I, W, I2, W2: SizeInt;
begin
  I := 0;
  W := 0;
  if Count > 0 then
    while True do
    begin
      I2 := I;
      W2 := W;
      if (not TText.Next(Text, I, W)) or (W = Count) then
        Break;
      if W > Count then
      begin
        if not IncludeIncomplete then
        begin
          I := I2;
          W := W2;
        end;
        Break;
      end;
    end;
  ALength := I;
  AWidth := W;
end;

end.
