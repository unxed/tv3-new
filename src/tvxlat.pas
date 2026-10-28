{ Makes keyboard shortcuts independent of the keyboard layout: a map from the characters of non-Latin
  layouts to the Latin keys at the same physical places, and two routines that change a key event
  with it (Alt or Ctrl plus a letter of another script, and a plain letter looked up among hot keys).
  The map is global and filled on first use; use the unit from the input thread only. }
unit TvXlat;

{$mode objfpc}
{$H+}

interface

uses
  TvEvents;

{ Returns the Latin key character for the key where some layout has CodePoint, or 0.
  Code points below 128 give 0. Does not look at XlatEnabled. }
function XlatLatin(CodePoint: LongWord): LongWord;

{ Adds a layout. Letters lists the characters on the Latin keys in the order of the keys; a bar
  separates the lower-case half from the upper-case half. Added pairs replace older ones. }
procedure XlatAdd(const Letters: AnsiString);

{ Reads layouts from a text file with lines "layout = keys". Returns False when the file cannot
  be opened. }
function XlatLoadFile(const Name: AnsiString): Boolean;

{ Turns Alt or Ctrl plus a letter of another script into the shortcut of the Latin letter. }
function XlatModded(var Event: TEvent): Boolean;

{ Turns a plain letter of another script into its Latin character. }
function XlatPlain(var Event: TEvent): Boolean;

var
  XlatEnabled: Boolean = True;

implementation

uses
  SysUtils, TvKeys;

const
  LatinKeyText = 'qwertyuiop[]asdfghjkl;''zxcvbnm,.`\';
  LatinKeyCount = 34;
  MaxLayoutChars = 128;
  MaxEventTextBytes = 4;

type
  TCodeList = array of LongWord;

var
  MapFrom: array of LongWord;
  MapTo: array of LongWord;
  MapCount: Integer = 0;
  BuiltinsLoaded: Boolean = False;
  LaterWins: Boolean = False;

const
  { The built-in layouts list the characters on the keys q w e r t y u i o p [ ] a s d f g h j k l ; ' z x c v b n m , .
    in that order; 0 stands for a key without a character. }
  RussianKeys: array[0..31] of LongWord = (
    $0439, $0446, $0443, $043A, $0435, $043D, $0433, $0448, $0449, $0437, $0445, $044A,
    $0444, $044B, $0432, $0430, $043F, $0440, $043E, $043B, $0434, $0436, $044D,
    $044F, $0447, $0441, $043C, $0438, $0442, $044C, $0431, $044E);

  UkrainianKeys: array[0..31] of LongWord = (
    $0439, $0446, $0443, $043A, $0435, $043D, $0433, $0448, $0449, $0437, $0445, $0457,
    $0444, $0456, $0432, $0430, $043F, $0440, $043E, $043B, $0434, $0436, $0454,
    $044F, $0447, $0441, $043C, $0438, $0442, $044C, $0431, $044E);

  { Serbian Cyrillic; the last two entries are the keys ` and \. }
  SerbianKeys: array[0..33] of LongWord = (
    $0459, $045A, $0435, $0440, $0442, $0437, $0443, $0438, $043E, $043F, $0448, $0452,
    $0430, $0441, $0434, $0444, $0433, $0445, $0458, $043A, $043B, $0447, $045B,
    $0000, $045F, $0446, $0432, $0431, $043D, $043C, $0000, $0000,
    $0000, $0436);

  BelarusianKeys: array[0..31] of LongWord = (
    $0439, $0446, $0443, $043A, $0435, $043D, $0433, $0448, $045E, $0437, $0445, $0000,
    $0444, $044B, $0432, $0430, $043F, $0440, $043E, $043B, $0434, $0436, $044D,
    $044F, $0447, $0441, $043C, $0456, $0442, $044C, $0431, $044E);

  GreekKeys: array[0..31] of LongWord = (
    $003B, $03C2, $03B5, $03C1, $03C4, $03C5, $03B8, $03B9, $03BF, $03C0, $0000, $0000,
    $03B1, $03C3, $03B4, $03C6, $03B3, $03B7, $03BE, $03BA, $03BB, $0000, $0000,
    $03B6, $03C7, $03C8, $03C9, $03B2, $03BD, $03BC, $0000, $0000);

  HebrewKeys: array[0..31] of LongWord = (
    $002F, $0027, $05E7, $05E8, $05D0, $05D8, $05D5, $05DF, $05DD, $05E4, $0000, $0000,
    $05E9, $05D3, $05D2, $05DB, $05E2, $05D9, $05D7, $05DC, $05DA, $05E3, $0000,
    $05D6, $05E1, $05D1, $05D4, $05E0, $05DE, $05E6, $05EA, $05E5);

{ Text decoding }

{ Decodes the character that starts at the one-based position Start. Returns False when the bytes there do not
  form a valid UTF-8 sequence (overlong forms, surrogates and values above U+10FFFF are invalid). }
function DecodeAt(const Text: AnsiString; Start: SizeInt; out CodePoint: LongWord; out Size: SizeInt): Boolean;
var
  Lead, Follower: Byte;
  ExtraCount, Index: SizeInt;
  Smallest, Value: LongWord;
begin
  Result := False;
  CodePoint := 0;
  Size := 0;
  if (Start < 1) or (Start > Length(Text)) then
    Exit;
  Lead := Byte(Text[Start]);
  if Lead < $80 then
  begin
    CodePoint := Lead;
    Size := 1;
    Result := True;
    Exit;
  end;
  if (Lead >= $C2) and (Lead <= $DF) then
  begin
    ExtraCount := 1;
    Smallest := $80;
    Value := Lead and $1F;
  end
  else if (Lead >= $E0) and (Lead <= $EF) then
  begin
    ExtraCount := 2;
    Smallest := $800;
    Value := Lead and $0F;
  end
  else if (Lead >= $F0) and (Lead <= $F4) then
  begin
    ExtraCount := 3;
    Smallest := $10000;
    Value := Lead and $07;
  end
  else
    Exit;
  if Start + ExtraCount > Length(Text) then
    Exit;
  for Index := 1 to ExtraCount do
  begin
    Follower := Byte(Text[Start + Index]);
    if (Follower and $C0) <> $80 then
      Exit;
    Value := (Value shl 6) or (Follower and $3F);
  end;
  if (Value < Smallest) or (Value > $10FFFF) then
    Exit;
  if (Value >= $D800) and (Value <= $DFFF) then
    Exit;
  CodePoint := Value;
  Size := ExtraCount + 1;
  Result := True;
end;

{ Reads Text as UTF-8 into at most MaxCount code points; a byte that starts no valid sequence is the code point
  of its own value. }
function DecodeCodePoints(const Text: AnsiString; MaxCount: Integer): TCodeList;
var
  Position, Count: SizeInt;
  CodePoint: LongWord;
  Size: SizeInt;
begin
  SetLength(Result, Length(Text));
  Count := 0;
  Position := 1;
  while (Position <= Length(Text)) and (Count < MaxCount) do
  begin
    if not DecodeAt(Text, Position, CodePoint, Size) then
    begin
      CodePoint := Byte(Text[Position]);
      Size := 1;
    end;
    Result[Count] := CodePoint;
    Inc(Count);
    Inc(Position, Size);
  end;
  SetLength(Result, Count);
end;

{ The first character of the text of a key event, when it is a valid character of code point 128 or more. }
function EventCharacter(const Event: TEvent; out CodePoint: LongWord): Boolean;
var
  Text: AnsiString;
  Count, Index: Integer;
  Size: SizeInt;
begin
  Result := False;
  CodePoint := 0;
  Count := Event.KeyDown.TextLength;
  if Count = 0 then
    Exit;
  if Count > MaxEventTextBytes then
    Count := MaxEventTextBytes;
  SetLength(Text, Count);
  for Index := 0 to Count - 1 do
    Text[Index + 1] := Chr(Event.KeyDown.Text[Index]);
  if not DecodeAt(Text, 1, CodePoint, Size) then
    Exit;
  Result := CodePoint >= 128;
end;

{ Key codes }

{ Returns the Alt key code of an upper-case letter: the scan code of its key in the high byte. }
function AltCodeOf(Letter: Char): Word;
const
  TopRow = 'QWERTYUIOP';
  MiddleRow = 'ASDFGHJKL';
  BottomRow = 'ZXCVBNM';
var
  Place: Integer;
  Scan: Word;
begin
  Place := Pos(Letter, TopRow);
  if Place > 0 then
    Scan := $0F + Place
  else
  begin
    Place := Pos(Letter, MiddleRow);
    if Place > 0 then
      Scan := $1D + Place
    else
    begin
      Place := Pos(Letter, BottomRow);
      if Place = 0 then
      begin
        Result := 0;
        Exit;
      end;
      Scan := $2B + Place;
    end;
  end;
  Result := Scan shl 8;
end;

{ Returns the Ctrl key code (Largest = 1) or the Alt key code (Largest = 2) of an upper-case letter, else 0. }
function ModdedKeyCode(Letter: Char; Largest: Integer): Word;
begin
  Result := 0;
  if (Letter < 'A') or (Letter > 'Z') then
    Exit;
  case Largest of
    1: Result := Ord(Letter) - Ord('A') + 1;
    2: Result := AltCodeOf(Letter);
  end;
end;

{ The map }

function FindEntry(From: LongWord): Integer;
var
  Index: Integer;
begin
  for Index := 0 to MapCount - 1 do
    if MapFrom[Index] = From then
    begin
      Result := Index;
      Exit;
    end;
  Result := -1;
end;

procedure PutPair(From, Target: LongWord);
var
  Found: Integer;
begin
  if From <= 32 then
    Exit;
  if From = Target then
    Exit;
  Found := FindEntry(From);
  if Found >= 0 then
  begin
    if LaterWins then
      MapTo[Found] := Target;
    Exit;
  end;
  if MapCount = Length(MapFrom) then
  begin
    SetLength(MapFrom, MapCount * 2 + 64);
    SetLength(MapTo, MapCount * 2 + 64);
  end;
  MapFrom[MapCount] := From;
  MapTo[MapCount] := Target;
  Inc(MapCount);
end;

procedure PutPairs(const Layout, Keys: TCodeList);
var
  Index, Last: Integer;
begin
  Last := Length(Layout);
  if Length(Keys) < Last then
    Last := Length(Keys);
  for Index := 0 to Last - 1 do
    PutPair(Layout[Index], Keys[Index]);
end;

function LowerKeys: TCodeList;
begin
  Result := DecodeCodePoints(LatinKeyText, LatinKeyCount);
end;

function UpperKeys: TCodeList;
var
  Index: Integer;
begin
  Result := LowerKeys;
  for Index := 0 to Length(Result) - 1 do
    if (Result[Index] >= Ord('a')) and (Result[Index] <= Ord('z')) then
      Result[Index] := Result[Index] - 32;
end;

{ The capital letter of a lower-case Cyrillic letter. }
function CyrillicCapital(CodePoint: LongWord): LongWord;
begin
  if (CodePoint >= $0430) and (CodePoint <= $044F) then
    Result := CodePoint - $20
  else if (CodePoint >= $0450) and (CodePoint <= $045F) then
    Result := CodePoint - $50
  else
    Result := CodePoint;
end;

{ Adds a built-in layout given as code points. With WithCapitals the capital letters are paired with the
  upper-case Latin keys as well. }
procedure PutBuiltin(const Codes: array of LongWord; WithCapitals: Boolean);
var
  Lower, Capitals: TCodeList;
  Index: Integer;
begin
  SetLength(Lower, Length(Codes));
  SetLength(Capitals, Length(Codes));
  for Index := 0 to High(Codes) do
  begin
    Lower[Index] := Codes[Index];
    Capitals[Index] := CyrillicCapital(Codes[Index]);
  end;
  PutPairs(Lower, LowerKeys);
  if WithCapitals then
    PutPairs(Capitals, UpperKeys);
end;

procedure EnsureBuiltins;
begin
  if BuiltinsLoaded then
    Exit;
  BuiltinsLoaded := True;
  LaterWins := False;
  PutBuiltin(RussianKeys, False);
  PutBuiltin(UkrainianKeys, False);
  PutBuiltin(RussianKeys, True);
  PutBuiltin(UkrainianKeys, True);
  PutBuiltin(SerbianKeys, True);
  PutBuiltin(BelarusianKeys, True);
  PutBuiltin(GreekKeys, False);
  PutBuiltin(HebrewKeys, False);
  LaterWins := True;
end;

{ Public routines }

function XlatLatin(CodePoint: LongWord): LongWord;
var
  Found: Integer;
  LowerLetter: LongWord;
begin
  Result := 0;
  if CodePoint < 128 then
    Exit;
  EnsureBuiltins;
  Found := FindEntry(CodePoint);
  if Found >= 0 then
  begin
    Result := MapTo[Found];
    Exit;
  end;
  if (CodePoint >= $0410) and (CodePoint <= $042F) then
    LowerLetter := CodePoint + $20
  else if (CodePoint >= $0400) and (CodePoint <= $040F) then
    LowerLetter := CodePoint + $50
  else if (CodePoint >= $0391) and (CodePoint <= $03A9) then
    LowerLetter := CodePoint + $20
  else
    Exit;
  Found := FindEntry(LowerLetter);
  if Found >= 0 then
    Result := MapTo[Found];
end;

procedure XlatAdd(const Letters: AnsiString);
var
  BarPosition: SizeInt;
begin
  EnsureBuiltins;
  BarPosition := Pos('|', Letters);
  if BarPosition = 0 then
  begin
    PutPairs(DecodeCodePoints(Letters, MaxLayoutChars), LowerKeys);
    Exit;
  end;
  PutPairs(DecodeCodePoints(Copy(Letters, 1, BarPosition - 1), MaxLayoutChars), LowerKeys);
  PutPairs(DecodeCodePoints(Copy(Letters, BarPosition + 1, Length(Letters)), MaxLayoutChars), UpperKeys);
end;

function XlatLoadFile(const Name: AnsiString): Boolean;
var
  Source: TextFile;
  Line, Layout, Keys: AnsiString;
  CommentPosition, EqualsPosition: SizeInt;
  SavedFileMode: Byte;
  OpenResult: Integer;
begin
  Result := False;
  SavedFileMode := FileMode;
  FileMode := 0;
  AssignFile(Source, Name);
  {$I-}
  Reset(Source);
  {$I+}
  OpenResult := IOResult;
  FileMode := SavedFileMode;
  if OpenResult <> 0 then
    Exit;
  EnsureBuiltins;
  {$I-}
  while not Eof(Source) do
  begin
    ReadLn(Source, Line);
    if IOResult <> 0 then
      Break;
    CommentPosition := Pos('#', Line);
    if CommentPosition > 0 then
      Line := Copy(Line, 1, CommentPosition - 1);
    EqualsPosition := Pos('=', Line);
    if EqualsPosition <= 1 then
      Continue;
    Layout := Trim(Copy(Line, 1, EqualsPosition - 1));
    Keys := Trim(Copy(Line, EqualsPosition + 1, Length(Line)));
    PutPairs(DecodeCodePoints(Layout, MaxLayoutChars), DecodeCodePoints(Keys, MaxLayoutChars));
  end;
  CloseFile(Source);
  {$I+}
  IOResult;
  Result := True;
end;

function XlatModded(var Event: TEvent): Boolean;
var
  CodePoint, Latin: LongWord;
  State: Word;
  Largest: Integer;
  KeyCode: Word;
begin
  Result := False;
  if not XlatEnabled then
    Exit;
  if Event.What <> evKeyDown then
    Exit;
  State := Event.KeyDown.ControlKeyState;
  if ((State and kbCtrlShift) = 0) and ((State and kbAltShift) = 0) then
    Exit;
  if not EventCharacter(Event, CodePoint) then
    Exit;
  Latin := XlatLatin(CodePoint);
  if (Latin >= Ord('A')) and (Latin <= Ord('Z')) then
    Latin := Latin + 32;
  if (Latin < Ord('a')) or (Latin > Ord('z')) then
    Exit;
  if (State and kbAltShift) <> 0 then
    Largest := 2
  else
    Largest := 1;
  KeyCode := ModdedKeyCode(Chr(Latin - 32), Largest);
  if KeyCode = 0 then
    Exit;
  Event.KeyDown.KeyCode := KeyCode;
  Event.KeyDown.TextLength := 0;
  Result := True;
end;

function XlatPlain(var Event: TEvent): Boolean;
var
  CodePoint, Latin: LongWord;
  PlainState: Word;
  HasCtrl, HasAlt: Boolean;
begin
  Result := False;
  if not XlatEnabled then
    Exit;
  if Event.What <> evKeyDown then
    Exit;
  PlainState := Event.KeyDown.ControlKeyState;
  HasCtrl := (PlainState and kbCtrlShift) <> 0;
  HasAlt := (PlainState and kbAltShift) <> 0;
  if HasCtrl or HasAlt then
    Exit;
  if not EventCharacter(Event, CodePoint) then
    Exit;
  Latin := XlatLatin(CodePoint);
  if Latin = 0 then
    Exit;
  Event.KeyDown.Text[0] := Byte(Latin);
  Event.KeyDown.TextLength := 1;
  Event.KeyDown.CharScan.CharCode := Byte(Latin);
  Result := True;
end;

end.
