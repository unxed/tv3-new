{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/util.h, source/tvision/drivers2.cpp (cstrlen, strwidth),
  source/tvision/tvtext2.cpp (getAltChar, getAltCharStr, getAltCode, getCtrlChar, getCtrlCharStr, getCtrlCode),
  source/tvision/newstr.cpp, source/tvision/fmtstr.cpp, source/tvision/misc.cpp (strnzcpy, strnzcat)
  See COPYRIGHT.magiblot.

  The functions of util.h whose bodies are in these files. ctrlToArrow is in TvKeys and message is Message of
  TvViews. The other declarations of util.h have no body among the sources or need a type that has no unit, and
  are not translated.

  A char buffer of dstSize characters, which strnzcpy and strnzcat fill, is a string that is passed as a var
  parameter and whose length stays below DstSize: the terminating zero of the buffer is the end of the string. The
  two functions return the length of the string, as they return the length of the buffer.

  A TStringView is a string. A TStringView that returns a character of a table (getAltCharStr, getCtrlCharStr) is
  a string of one character, and an empty TStringView is an empty string. The C++ char is a Char, uchar is a Byte
  and ushort is a Word. The functions with a name that starts with a lower case letter in the C++ take a capital
  first letter, as in docs/API-NAMES.md (Cstrlen, Strwidth).

  newStr returns a block that was allocated for the characters and the terminating zero; it is released with
  FreeMem. The variadic list of formatStr is an array of const, and its format is a Free Pascal Format string; a
  C++ format specifier that Format does not accept (for example a length modifier such as l) counts as a failure
  of the formatting. }
unit TvUtil;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvEvents;

{ The smaller and the larger of two values. }
function Min(A, B: Integer): Integer; overload;
function Min(A, B: Int64): Int64; overload;
function Max(A, B: Integer): Integer; overload;
function Max(A, B: Int64): Int64; overload;

{ Returns the character of the Alt key code KeyCode: a letter or a digit, or the space-bar character for
  kbAltSpace; #0 when the code has no character. }
function GetAltChar(KeyCode: Word): Char;

{ Returns the text of an Alt+Key event, or the character of its Alt key code; empty when it has none. }
function GetAltCharStr(const KeyDown: TKeyDownEvent): string;

{ Returns the Alt key code of the character C (letters are taken in upper case); 0 when it has none. }
function GetAltCode(C: Char): Word;

{ Returns the letter of the Ctrl key code KeyCode: the control character 1 to 26 as the letter A to Z; #0 when the
  code has none. }
function GetCtrlChar(KeyCode: Word): Char;

{ Returns the text of a Ctrl+Key event (without Alt), or the letter of its control character; empty when it has
  none. }
function GetCtrlCharStr(const KeyDown: TKeyDownEvent): string;

{ Returns the Alt key code of the character Ch combined with the Ctrl code of its letter. }
function GetCtrlCode(Ch: Byte): Word;

{ Returns the displayed length of Text, ignoring the '~' characters. It is used for command strings, which use '~'
  to toggle between display attributes. }
function Cstrlen(const Text: string): Integer;

{ Returns the displayed length of Text. }
function Strwidth(const Text: string): Integer;

{ Returns a copy of the Size bytes at S in a block of Size + 1 bytes, with a terminating zero; nil when S is nil.
  The variant with a string always returns a block. }
function NewStr(S: PAnsiChar; Size: SizeInt): PAnsiChar; overload;
function NewStr(const S: string): PAnsiChar; overload;

{ Returns AFormat with its specifiers replaced by Args. When the formatting fails, returns AFormat. }
function FormatStr(const AFormat: string; const Args: array of const): string;
function VFormatStr(const AFormat: string; const Args: array of const): string;

{ Puts Src into Dst, which stands for a buffer of DstSize characters, where the last character is kept for the
  terminating zero: at most DstSize - 1 characters of Src are copied. Returns the length of Dst. When DstSize is 0
  Dst is not changed and the result is 0. Src and Dst must not be the same string. }
function Strnzcpy(var Dst: string; const Src: string; DstSize: SizeInt): SizeInt;

{ Appends Src to Dst, which stands for a buffer of DstSize characters, where the last character is kept for the
  terminating zero: Dst is never longer than DstSize - 1 characters. The length of Dst is the number of characters
  before its first zero character, or its whole length when it has none, and what follows that zero character is
  dropped. A Dst that is already longer than DstSize - 1 characters is cut to that length, and nothing is appended,
  where the C++ writes beyond the buffer. Returns the length of Dst. When DstSize is 0 Dst is not changed and the
  result is 0. Src and Dst must not be the same string. }
function Strnzcat(var Dst: string; const Src: string; DstSize: SizeInt): SizeInt;

implementation

uses
  SysUtils, TvKeys, TvUtf8;

const
  AltCodes1 = 'QWERTYUIOP'#0#0#0#0'ASDFGHJKL'#0#0#0#0#0'ZXCVBNM';
  AltCodes2 = '1234567890-=';
  { The space-bar character, U+2261 in CP437. }
  AltSpaceChar = #$F0;

  CtrlCodes = #0'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

function Min(A, B: Integer): Integer;
begin
  if A < B then
    Exit(A);
  Result := B;
end;

function Min(A, B: Int64): Int64;
begin
  if A < B then
    Exit(A);
  Result := B;
end;

function Max(A, B: Integer): Integer;
begin
  if A > B then
    Exit(A);
  Result := B;
end;

function Max(A, B: Int64): Int64;
begin
  if A > B then
    Exit(A);
  Result := B;
end;

function GetAltChar(KeyCode: Word): Char;
var
  KeyDown: TKeyDownEvent;
  AltChar: string;
begin
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  KeyDown.KeyCode := KeyCode;
  AltChar := GetAltCharStr(KeyDown);

  if AltChar = '' then
    Result := #0
  else
    Result := AltChar[1];
end;

function GetAltCharStr(const KeyDown: TKeyDownEvent): string;
var
  ScanCode: Word;
  Ch: Char;
begin
  { If the Alt+Key event contains text, return it. }
  if ((KeyDown.ControlKeyState and kbAltShift) <> 0) and (KeyDown.GetText <> '') then
  begin
    Result := KeyDown.GetText;
    Exit;
  end;

  { Otherwise, try mapping the scan code to a character. }
  Result := '';
  if KeyDown.CharScan.CharCode = 0 then
  begin
    ScanCode := KeyDown.CharScan.ScanCode;

    Ch := #0;
    if KeyDown.KeyCode = kbAltSpace then
      Ch := AltSpaceChar { special case to handle alt-Space }
    else if (ScanCode >= $10) and (ScanCode <= $32) then
      Ch := AltCodes1[ScanCode - $10 + 1] { alt-letter }
    else if (ScanCode >= $78) and (ScanCode <= $83) then
      Ch := AltCodes2[ScanCode - $78 + 1]; { alt-number }

    if Ch <> #0 then
      Result := Ch;
  end;
end;

function GetAltCode(C: Char): Word;
var
  I: SizeInt;
begin
  Result := 0;
  if C = #0 then
    Exit;

  C := UpCase(C);

  if C = AltSpaceChar then
  begin
    Result := kbAltSpace; { special case to handle alt-Space }
    Exit;
  end;

  for I := 1 to Length(AltCodes1) do
    if AltCodes1[I] = C then
    begin
      Result := Word((I - 1 + $10) shl 8);
      Exit;
    end;

  for I := 1 to Length(AltCodes2) do
    if AltCodes2[I] = C then
    begin
      Result := Word((I - 1 + $78) shl 8);
      Exit;
    end;
end;

function GetCtrlChar(KeyCode: Word): Char;
var
  KeyDown: TKeyDownEvent;
  CtrlChar: string;
begin
  FillChar(KeyDown, SizeOf(KeyDown), 0);
  KeyDown.KeyCode := KeyCode;
  CtrlChar := GetCtrlCharStr(KeyDown);

  if CtrlChar = '' then
    Result := #0
  else
    Result := CtrlChar[1];
end;

function GetCtrlCharStr(const KeyDown: TKeyDownEvent): string;
var
  CharCode: Byte;
begin
  { If the Ctrl+Key event contains text, return it. The Alt modifier must not be present, since that would be
    considered an Alt+Key press. }
  if ((KeyDown.ControlKeyState and kbAltShift) = 0) and
     ((KeyDown.ControlKeyState and kbCtrlShift) <> 0) and
     (KeyDown.GetText <> '') then
  begin
    Result := KeyDown.GetText;
    Exit;
  end;

  { Otherwise, map control characters into the corresponding ASCII character. }
  Result := '';
  CharCode := KeyDown.CharScan.CharCode;
  if (CharCode > 0) and (CharCode <= Ord('Z') - Ord('A') + 1) then
    Result := CtrlCodes[CharCode + 1];
end;

function GetCtrlCode(Ch: Byte): Word;
var
  Letter: Integer;
begin
  if (Ch >= Ord('a')) and (Ch <= Ord('z')) then
    Letter := Ch and not $20
  else
    Letter := Ch;
  Result := Word(Integer(GetAltCode(Char(Ch))) or (Letter - Ord('A') + 1));
end;

function Cstrlen(const Text: string): Integer;
var
  I, W: SizeInt;
begin
  I := 0;
  W := 0;
  while I < Length(Text) do
  begin
    if Text[I + 1] <> '~' then
      TText.Next(Text, I, W)
    else
      Inc(I);
  end;
  Result := W;
end;

function Strwidth(const Text: string): Integer;
begin
  Result := TText.Width(Text);
end;

function NewStr(S: PAnsiChar; Size: SizeInt): PAnsiChar;
begin
  if S = nil then
  begin
    Result := nil;
    Exit;
  end;
  GetMem(Result, Size + 1);
  Move(S^, Result^, Size);
  Result[Size] := #0;
end;

function NewStr(const S: string): PAnsiChar;
begin
  GetMem(Result, Length(S) + 1);
  if S <> '' then
    Move(S[1], Result^, Length(S));
  Result[Length(S)] := #0;
end;

function FormatStr(const AFormat: string; const Args: array of const): string;
begin
  Result := VFormatStr(AFormat, Args);
end;

function VFormatStr(const AFormat: string; const Args: array of const): string;
begin
  try
    Result := Format(AFormat, Args);
  except
    on EConvertError do
      Result := AFormat;
  end;
end;

function Strnzcpy(var Dst: string; const Src: string; DstSize: SizeInt): SizeInt;
var
  CopyLen: SizeInt;
begin
  Result := 0;
  if DstSize <= 0 then
    Exit;

  CopyLen := Length(Src);
  if CopyLen > DstSize - 1 then
    CopyLen := DstSize - 1;
  Dst := Copy(Src, 1, CopyLen);
  Result := CopyLen;
end;

function Strnzcat(var Dst: string; const Src: string; DstSize: SizeInt): SizeInt;
var
  DstLen, CopyLen, ZeroPos: SizeInt;
begin
  Result := 0;
  if DstSize <= 0 then
    Exit;

  DstLen := Length(Dst);
  ZeroPos := Pos(#0, Dst);
  if ZeroPos > 0 then
    DstLen := ZeroPos - 1;
  if DstLen > DstSize - 1 then
    DstLen := DstSize - 1;

  CopyLen := Length(Src);
  if CopyLen > DstSize - 1 - DstLen then
    CopyLen := DstSize - 1 - DstLen;
  Dst := Copy(Dst, 1, DstLen) + Copy(Src, 1, CopyLen);
  Result := DstLen + CopyLen;
end;

end.
