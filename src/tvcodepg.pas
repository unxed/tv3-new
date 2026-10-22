{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/codepage.h, source/platform/codepage.cpp
  See COPYRIGHT.magiblot.

  A translation is a table of 256 UTF-8 sequences of up to four bytes, zero-padded, one per code page character.
  The built-in table is the one of code page 437.

  The initialization of this unit sets the variable CodePageToPackedUtf8 of TvText to the conversion of
  CpTranslator. }
unit TvCodePg;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvUtf8;

type
  TCpTranslation = array[0..255] of TUtf8Bytes;
  PCpTranslation = ^TCpTranslation;

  CpTranslator = class
  public
    { Replaces the table used by the conversions with a copy of ATranslation. With nil, restores the table of
      code page 437. }
    class procedure SetTranslation(ATranslation: PCpTranslation); static;

    { Returns the UTF-8 sequence of the code page character C, padded with zero bytes. }
    class function ToUtf8(C: Byte): TUtf8Bytes; static;

    { Returns the UTF-8 sequence of C as a Cardinal, the first byte being the lowest. }
    class function ToPackedUtf8(C: Byte): Cardinal; static;

    { Returns the code page character whose UTF-8 sequence is S, or #0 if there is none. If several characters
      have the same sequence, the one with the lowest value is returned. }
    class function FromUtf8(const S: string): Char; static;

    { As FromUtf8, but returns #0 for the characters below ' '. }
    class function PrintableFromUtf8(const S: string): Char; static;
  end;

implementation

uses
  TvText;

const
  { The code point of every character of code page 437, in the order of the characters. }
  Cp437Points: array[0..255] of Cardinal = (
    $0000, $263A, $263B, $2665, $2666, $2663, $2660, $2022, $25D8, $25CB, $25D9, $2642, $2640, $266A, $266B, $263C,
    $25BA, $25C4, $2195, $203C, $00B6, $00A7, $25AC, $21A8, $2191, $2193, $2192, $2190, $221F, $2194, $25B2, $25BC,
    $0020, $0021, $0022, $0023, $0024, $0025, $0026, $0027, $0028, $0029, $002A, $002B, $002C, $002D, $002E, $002F,
    $0030, $0031, $0032, $0033, $0034, $0035, $0036, $0037, $0038, $0039, $003A, $003B, $003C, $003D, $003E, $003F,
    $0040, $0041, $0042, $0043, $0044, $0045, $0046, $0047, $0048, $0049, $004A, $004B, $004C, $004D, $004E, $004F,
    $0050, $0051, $0052, $0053, $0054, $0055, $0056, $0057, $0058, $0059, $005A, $005B, $005C, $005D, $005E, $005F,
    $0060, $0061, $0062, $0063, $0064, $0065, $0066, $0067, $0068, $0069, $006A, $006B, $006C, $006D, $006E, $006F,
    $0070, $0071, $0072, $0073, $0074, $0075, $0076, $0077, $0078, $0079, $007A, $007B, $007C, $007D, $007E, $2302,
    $00C7, $00FC, $00E9, $00E2, $00E4, $00E0, $00E5, $00E7, $00EA, $00EB, $00E8, $00EF, $00EE, $00EC, $00C4, $00C5,
    $00C9, $00E6, $00C6, $00F4, $00F6, $00F2, $00FB, $00F9, $00FF, $00D6, $00DC, $00A2, $00A3, $00A5, $20A7, $0192,
    $00E1, $00ED, $00F3, $00FA, $00F1, $00D1, $00AA, $00BA, $00BF, $2310, $00AC, $00BD, $00BC, $00A1, $00AB, $00BB,
    $2591, $2592, $2593, $2502, $2524, $2561, $2562, $2556, $2555, $2563, $2551, $2557, $255D, $255C, $255B, $2510,
    $2514, $2534, $252C, $251C, $2500, $253C, $255E, $255F, $255A, $2554, $2569, $2566, $2560, $2550, $256C, $2567,
    $2568, $2564, $2565, $2559, $2558, $2552, $2553, $256B, $256A, $2518, $250C, $2588, $2584, $258C, $2590, $2580,
    $03B1, $00DF, $0393, $03C0, $03A3, $03C3, $00B5, $03C4, $03A6, $0398, $03A9, $03B4, $221E, $03C6, $03B5, $2229,
    $2261, $00B1, $2265, $2264, $2320, $2321, $00F7, $2248, $00B0, $2219, $00B7, $221A, $207F, $00B2, $25A0, $00A0
  );

type
  { An entry of the reverse map: the first Len bytes of a UTF-8 sequence as a Cardinal, the first byte being the
    lowest, and the code page character it stands for. }
  TCpMapEntry = record
    Key: Cardinal;
    Value: Byte;
  end;

  { A translation table with its reverse map. A state is never changed after it is published. }
  TCpState = record
    Table: TCpTranslation;
    Count: Integer;
    Map: array[0..255] of TCpMapEntry; { Sorted by Key. }
  end;
  PCpState = ^TCpState;

var
  { The published state, nil until first use. Secondary threads may still read a state when it is replaced, so a
    replaced state is never freed and the state is never destroyed on exit. }
  State: PCpState = nil;
  StateLock: TRTLCriticalSection;

function PackBytes(const Bytes: TUtf8Bytes; Count: Integer): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    Result := Result or (Cardinal(Bytes[I]) shl (8 * I));
end;

{ The key of the first four bytes of S. }
function StringToKey(const S: string): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
  begin
    if I > 4 then
      Break;
    Result := Result or (Cardinal(Byte(S[I])) shl (8 * (I - 1)));
  end;
end;

{ Returns the index of the first entry of the map whose key is not less than Key. }
function LowerBound(St: PCpState; Key: Cardinal): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := St^.Count;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if St^.Map[Mid].Key < Key then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;
  Result := Lo;
end;

procedure InitUtf8ToCp(St: PCpState);
var
  I, Pos, J: Integer;
  Len: Integer;
  Key: Cardinal;
begin
  St^.Count := 0;
  for I := 0 to 255 do
  begin
    Len := 1 + Integer(Utf8BytesLeft(St^.Table[I][0]));
    Key := PackBytes(St^.Table[I], Len);
    Pos := LowerBound(St, Key);
    { An existing entry is kept, as with the insertion into a map. }
    if (Pos < St^.Count) and (St^.Map[Pos].Key = Key) then
      Continue;
    for J := St^.Count downto Pos + 1 do
      St^.Map[J] := St^.Map[J - 1];
    St^.Map[Pos].Key := Key;
    St^.Map[Pos].Value := Byte(I);
    Inc(St^.Count);
  end;
end;

{ Makes a state from ATranslation, or from code page 437 if it is nil. }
function BuildState(ATranslation: PCpTranslation): PCpState;
var
  I: Integer;
begin
  New(Result);
  if ATranslation <> nil then
    Result^.Table := ATranslation^
  else
    for I := 0 to 255 do
      Utf32To8(Cp437Points[I], Result^.Table[I]);
  InitUtf8ToCp(Result);
end;

{ The map is created on first use, which is safe from other threads, and it is not destroyed. }
function GetState: PCpState;
var
  Built: PCpState;
begin
  Result := State;
  if Result = nil then
  begin
    EnterCriticalSection(StateLock);
    try
      if State = nil then
      begin
        Built := BuildState(nil);
        WriteBarrier;
        State := Built;
      end;
      Result := State;
    finally
      LeaveCriticalSection(StateLock);
    end;
  end;
end;

class procedure CpTranslator.SetTranslation(ATranslation: PCpTranslation);
var
  Built: PCpState;
begin
  Built := BuildState(ATranslation);
  EnterCriticalSection(StateLock);
  try
    WriteBarrier;
    State := Built;
  finally
    LeaveCriticalSection(StateLock);
  end;
end;

class function CpTranslator.ToUtf8(C: Byte): TUtf8Bytes;
begin
  Result := GetState^.Table[C];
end;

class function CpTranslator.ToPackedUtf8(C: Byte): Cardinal;
begin
  Result := PackBytes(GetState^.Table[C], 4);
end;

class function CpTranslator.FromUtf8(const S: string): Char;
var
  St: PCpState;
  Key: Cardinal;
  Pos: Integer;
begin
  St := GetState;
  Key := StringToKey(S);
  Pos := LowerBound(St, Key);
  if (Pos < St^.Count) and (St^.Map[Pos].Key = Key) then
    Result := Char(St^.Map[Pos].Value)
  else
    Result := #0;
end;

class function CpTranslator.PrintableFromUtf8(const S: string): Char;
var
  C: Char;
begin
  C := FromUtf8(S);
  if C < ' ' then
    Result := #0
  else
    Result := C;
end;

function PackedUtf8OfCodePage(C: Char): Cardinal;
begin
  Result := CpTranslator.ToPackedUtf8(Byte(C));
end;

initialization
  InitCriticalSection(StateLock);
  CodePageToPackedUtf8 := @PackedUtf8OfCodePage;

end.
