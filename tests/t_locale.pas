{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/platform.h, source/platform/platfchr.cpp, source/platform/platform.cpp,
  source/platform/ttext.cpp, include/tvision/ttext.h
  See COPYRIGHT.magiblot.

  The environment variable LC_ALL is set to C before the first use, so the locale that InitLocale takes is the C
  locale. The comparison of letters outside ASCII depends on how the C library maps them in that locale, so the
  expected value of such a case is worked out from CharOps.ToLower where the library may differ. }
program t_locale;

{$mode objfpc}

uses
  ctypes, TvLocale;

{$I testlib.inc}

function SetEnvC(Name, Value: PAnsiChar; Overwrite: cint): cint; cdecl; external 'c' name 'setenv';

type
  TTextPair = record
    A, B: string;
    Want: Boolean;
  end;

const
  { Pairs of texts for the comparison. #$C3#$A9 is the lower case e with an acute accent and #$C3#$89 the upper case,
    in UTF-8; #$82 and #$90 are the same two letters in code page 437. #$E2#$94#$9C is U+251C, which is #$C3 of
    code page 437. #$E6#$97#$A5 is U+65E5. }
  TextPairs: array[0..24] of TTextPair = (
    (A: ''; B: ''; Want: True),
    (A: ''; B: 'a'; Want: False),
    (A: 'a'; B: ''; Want: False),
    (A: 'abc'; B: 'abc'; Want: True),
    (A: 'Hello'; B: 'hELLO'; Want: True),
    (A: 'abc'; B: 'abd'; Want: False),
    (A: 'abc'; B: 'abcd'; Want: False),
    (A: 'abcd'; B: 'abc'; Want: False),
    (A: 'a-1 Z'; B: 'A-1 z'; Want: True),
    (A: 'a'#0'b'; B: 'A'#0'B'; Want: True),
    (A: 'caf'#$C3#$A9; B: 'CAF'#$C3#$A9; Want: True),
    (A: 'caf'#$C3#$A9; B: 'cafe'; Want: False),
    (A: 'caf'#$82; B: 'caf'#$C3#$A9; Want: True),
    (A: #$90; B: #$C3#$89; Want: True),
    (A: #$82; B: #$82; Want: True),
    (A: 'x'#$80; B: 'X'#$C3#$87; Want: True),
    (A: #$C3; B: #$E2#$94#$9C; Want: True),
    (A: #$C3'A'; B: #$E2#$94#$9C'a'; Want: True),
    (A: #$C3#$A9; B: #$C3; Want: False),
    (A: #$E6#$97#$A5; B: #$E6#$97#$A5; Want: True),
    (A: #$E6#$97#$A5; B: #$E6#$97; Want: False),
    (A: #$E6#$97#$A5#$E6#$9C#$AC; B: #$E6#$97#$A5; Want: False),
    (A: #$F0#$9F#$98#$80; B: #$F0#$9F#$98#$80; Want: True),
    (A: #$F0#$9F#$98#$80; B: #$F0#$9F#$98#$81; Want: False),
    (A: 'A'#$80'B'; B: 'a'#$C3#$87'b'; Want: True)
  );

function WidthCode(const F: TCharWidthFunc): Pointer;
var
  P: Pointer;
begin
  Move(F, P, SizeOf(P));
  Result := P;
end;

function LowerCode(const F: TCharToLowerFunc): Pointer;
var
  P: Pointer;
begin
  Move(F, P, SizeOf(P));
  Result := P;
end;

function Num(N: Integer): string;
begin
  Str(N, Result);
end;

procedure TestInitialState;
begin
  Check(WidthCode(CharOps.Width) = Pointer(@InitCharWidth), 'the width field starts as InitCharWidth');
  Check(LowerCode(CharOps.ToLower) = Pointer(@InitCharToLower), 'the lower case field starts as InitCharToLower');
end;

procedure TestWidth;
var
  Code, Bad: Integer;
  Chosen: Pointer;
begin
  Check(CharOps.Width(Ord('A')) = 1, 'the first call of the width answers for a letter');
  Check(LowerCode(CharOps.ToLower) = Pointer(@CharToLower), 'the first call also set the lower case function');
  Chosen := WidthCode(CharOps.Width);
  Check(Chosen <> Pointer(@InitCharWidth), 'the width field no longer is InitCharWidth');
  Check(Chosen = Pointer(@UnixCharWidth), 'without a Linux console the width is the one of the C library');

  Bad := 0;
  for Code := 32 to 126 do
    if CharOps.Width(Code) <> 1 then
      Inc(Bad);
  Check(Bad = 0, 'the printable characters of ASCII are one column wide');
  Check(CharOps.Width(0) = 0, 'the null character has no width');
  Check(CharOps.Width(7) < 0, 'a control character has a negative width');
  Check(UnixCharWidth(Ord('z')) = 1, 'UnixCharWidth gives the width of a letter');
end;

{$IFDEF LINUX}
procedure CheckSpans(const Pairs: array of Cardinal);
var
  Index, Bad: Integer;
begin
  Bad := 0;
  Index := 0;
  while Index < High(Pairs) do
  begin
    if Cardinal(LinuxConsoleCharWidth(Pairs[Index])) <> Pairs[Index + 1] then
    begin
      WriteLn('width of U+', HexStr(Pairs[Index], 4), ' is not ', Pairs[Index + 1]);
      Inc(Bad);
    end;
    Inc(Index, 2);
  end;
  Check(Bad = 0, 'the console width of the code points on the borders of the double-width spans');
end;

procedure TestConsoleWidth;
begin
  { Each pair is a code point and its width. The console has no zero-width characters, so U+0300 and U+0000 are
    one column wide. }
  CheckSpans([65, 1, 0, 1, $300, 1, $10FF, 1, $1100, 2, $115F, 2, $1160, 1, $2328, 1, $2329, 2, $232A, 2, $232B, 1,
    $2E7F, 1, $2E80, 2, $303E, 2, $303F, 1, $3040, 2, $A4CF, 2, $A4D0, 1, $ABFF, 1, $AC00, 2, $D7A3, 2, $D7A4, 1,
    $F8FF, 1, $F900, 2, $FAFF, 2, $FB00, 1, $FE10, 2, $FE19, 2, $FE1A, 1, $FE2F, 1, $FE30, 2, $FE6F, 2, $FE70, 1,
    $FEFF, 1, $FF00, 2, $FF60, 2, $FF61, 1, $FFDF, 1, $FFE0, 2, $FFE6, 2, $FFE7, 1, $1FFFF, 1, $20000, 2,
    $2FFFD, 2, $2FFFE, 1, $30000, 2, $3FFFD, 2, $3FFFE, 1, $E0000, 1]);
end;
{$ENDIF}

procedure TestToLower;
var
  Code, Bad: Cardinal;
  Expected: Cardinal;
begin
  Bad := 0;
  for Code := 0 to 127 do
  begin
    if (Code >= Ord('A')) and (Code <= Ord('Z')) then
      Expected := Code + 32
    else
      Expected := Code;
    if CharOps.ToLower(Code) <> Expected then
      Inc(Bad);
  end;
  Check(Bad = 0, 'ASCII letters become lower case and the other characters stay');

  Bad := 0;
  for Code := $E0 to $FF do
    if CharOps.ToLower(Code) <> Code then
      Inc(Bad);
  Check(Bad = 0, 'Latin-1 characters that are not upper case stay');

  Bad := 0;
  for Code := $C0 to $DE do
    if Code <> $D7 then
    begin
      Expected := CharOps.ToLower(Code);
      if (Expected <> Code) and (Expected <> Code + 32) then
        Inc(Bad);
    end;
  Check(Bad = 0, 'an upper case Latin-1 letter stays or becomes the letter 32 places above');
  Check(CharOps.ToLower($D7) = $D7, 'the multiplication sign stays');
  Check(CharToLower($41) = $61, 'CharToLower of A is a');
  Check(CharOps.ToLower($1F600) = $1F600, 'a code point outside the basic plane without a case stays');
  Check(CharOps.ToLower(CharOps.ToLower($C9)) = CharOps.ToLower($C9), 'the lower case is its own lower case');
end;

procedure TestEquals;
var
  Index: Integer;
  Pair: TTextPair;
begin
  for Index := Low(TextPairs) to High(TextPairs) do
  begin
    Pair := TextPairs[Index];
    Check(EqualsIgnoreCase(Pair.A, Pair.B) = Pair.Want, 'text pair ' + Num(Index));
    Check(EqualsIgnoreCase(Pair.B, Pair.A) = Pair.Want, 'text pair ' + Num(Index) + ' reversed');
  end;
  Check(EqualsIgnoreCase(#$C3#$89, #$C3#$A9) = (CharOps.ToLower($C9) = CharOps.ToLower($E9)),
    'the two cases of e with an accent are equal when the locale maps one to the other');
  Check(EqualsIgnoreCase(#$90, #$82) = (CharOps.ToLower($C9) = CharOps.ToLower($E9)),
    'the same two letters in the code page');
  Check(EqualsIgnoreCase(#$C3#$89, #$90), 'a letter in UTF-8 equals the same letter in the code page');
end;

begin
  SetEnvC('LC_ALL', 'C', 1);
  TestInitialState;
  TestWidth;
{$IFDEF LINUX}
  TestConsoleWidth;
{$ENDIF}
  TestToLower;
  TestEquals;
  InitLocale;
  InitCharOps;
  Check(EqualsIgnoreCase('Ab', 'aB'), 'the comparison still works after a second initialisation');
  Done;
end.
