{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/codepage.h, source/platform/codepage.cpp
  See COPYRIGHT.magiblot. }
program t_codepg;

{$mode objfpc}

uses
  SysUtils, TvUtf8, TvText, TvCodePg;

{$I testlib.inc}

function Seq(const A: array of Byte): string;
var
  I: Integer;
begin
  SetLength(Result, Length(A));
  for I := 0 to High(A) do
    Result[I + 1] := Chr(A[I]);
end;

function Same(const B: TUtf8Bytes; const E: array of Byte): Boolean;
var
  I: Integer;
begin
  Result := Length(E) <= 4;
  if not Result then
    Exit;
  for I := 0 to 3 do
    if I < Length(E) then
      Result := Result and (B[I] = E[I])
    else
      Result := Result and (B[I] = 0);
end;

function BytesToString(const B: TUtf8Bytes): string;
var
  Len: Integer;
begin
  Len := 1 + Integer(Utf8BytesLeft(B[0]));
  SetLength(Result, Len);
  Move(B[0], Result[1], Len);
end;

procedure CheckToUtf8(C: Byte; const E: array of Byte; const Name: string);
begin
  Check(Same(CpTranslator.ToUtf8(Byte(C)), E), 'ToUtf8: ' + Name);
end;

procedure CheckFrom(const S: string; E: Byte; const Name: string);
begin
  Check(Byte(CpTranslator.FromUtf8(S)) = E, 'FromUtf8: ' + Name);
end;

procedure CheckPrintable(const S: string; E: Byte; const Name: string);
begin
  Check(Byte(CpTranslator.PrintableFromUtf8(S)) = E, 'PrintableFromUtf8: ' + Name);
end;

procedure TestTable;
begin
  CheckToUtf8($00, [0], 'NUL');
  CheckToUtf8($01, [$E2, $98, $BA], 'smiley');
  CheckToUtf8($10, [$E2, $96, $BA], 'pointer right');
  CheckToUtf8($1E, [$E2, $96, $B2], 'triangle up');
  CheckToUtf8($20, [$20], 'space');
  CheckToUtf8($22, [$22], 'quote');
  CheckToUtf8($41, [$41], 'A');
  CheckToUtf8($5C, [$5C], 'backslash');
  CheckToUtf8($7E, [$7E], 'tilde');
  CheckToUtf8($7F, [$E2, $8C, $82], 'house');
  CheckToUtf8($80, [$C3, $87], 'C cedilla');
  CheckToUtf8($82, [$C3, $A9], 'e acute');
  CheckToUtf8($9E, [$E2, $82, $A7], 'peseta');
  CheckToUtf8($B0, [$E2, $96, $91], 'light shade');
  CheckToUtf8($C4, [$E2, $94, $80], 'horizontal line');
  CheckToUtf8($CD, [$E2, $95, $90], 'double horizontal line');
  CheckToUtf8($DB, [$E2, $96, $88], 'full block');
  CheckToUtf8($E0, [$CE, $B1], 'alpha');
  CheckToUtf8($E1, [$C3, $9F], 'sharp s');
  CheckToUtf8($F8, [$C2, $B0], 'degree');
  CheckToUtf8($FE, [$E2, $96, $A0], 'black square');
  CheckToUtf8($FF, [$C2, $A0], 'no-break space');
end;

procedure TestPacked;
begin
  Check(CpTranslator.ToPackedUtf8(0) = 0, 'packed: NUL');
  Check(CpTranslator.ToPackedUtf8($41) = $41, 'packed: A');
  Check(CpTranslator.ToPackedUtf8($80) = $87C3, 'packed: two bytes');
  Check(CpTranslator.ToPackedUtf8($01) = $BA98E2, 'packed: three bytes');
  Check(CodePageToPackedUtf8(#$80) = $87C3, 'hook: two bytes');
  Check(CodePageToPackedUtf8(#$01) = $BA98E2, 'hook: three bytes');
end;

procedure TestReverse;
var
  C: Integer;
  R: Byte;
  S: string;
begin
  CheckFrom('A', $41, 'A');
  CheckFrom(Seq([$C3, $87]), $80, 'C cedilla');
  CheckFrom(Seq([$C3, $A9]), $82, 'e acute');
  CheckFrom(Seq([$CE, $B1]), $E0, 'alpha');
  CheckFrom(Seq([$E2, $98, $BA]), $01, 'smiley');
  CheckFrom(Seq([$E2, $96, $88]), $DB, 'full block');
  CheckFrom(Seq([$E2, $8C, $82]), $7F, 'house');
  CheckFrom(Seq([0]), 0, 'NUL');
  CheckFrom(' ', $20, 'space, the lowest of two characters');
  CheckFrom(Seq([$C2, $A0]), $FF, 'no-break space');
  CheckFrom(Seq([$D0, $96]), 0, 'not in the table');
  CheckFrom(Seq([$E2, $82, $AC]), 0, 'euro sign, not in the table');
  CheckFrom('', 0, 'empty');
  for C := 0 to 255 do
  begin
    S := BytesToString(CpTranslator.ToUtf8(Byte(C)));
    R := Byte(CpTranslator.FromUtf8(S));
    Check(R <= C, 'round trip, lowest character: ' + IntToStr(C));
    Check(BytesToString(CpTranslator.ToUtf8(R)) = S, 'round trip, same sequence: ' + IntToStr(C));
  end;
end;

procedure TestPrintable;
begin
  CheckPrintable('A', $41, 'A');
  CheckPrintable(' ', $20, 'space');
  CheckPrintable(Seq([0]), 0, 'NUL');
  CheckPrintable(Seq([$E2, $98, $BA]), 0, 'smiley, a control character');
  CheckPrintable(Seq([$E2, $96, $B2]), 0, 'triangle up, a control character');
  CheckPrintable(Seq([$E2, $82, $AC]), 0, 'not in the table');
  CheckPrintable(Seq([$E2, $8C, $82]), $7F, 'house');
  CheckPrintable(Seq([$C3, $87]), $80, 'C cedilla');
  CheckPrintable(Seq([$E2, $96, $88]), $DB, 'full block');
end;

procedure TestReplaced;
var
  T: TCpTranslation;
  C: Integer;
begin
  for C := 0 to 255 do
    T[C] := CpTranslator.ToUtf8(Byte(C));
  T[$80][0] := $D0;
  T[$80][1] := $96;
  T[$80][2] := 0;
  T[$80][3] := 0;
  T[$81][0] := $41;
  T[$81][1] := 0;
  T[$81][2] := 0;
  T[$81][3] := 0;
  CpTranslator.SetTranslation(@T);
  CheckToUtf8($80, [$D0, $96], 'replaced: entry');
  CheckToUtf8($41, [$41], 'replaced: unchanged entry');
  CheckToUtf8($81, [$41], 'replaced: second A');
  Check(CpTranslator.ToPackedUtf8($80) = $96D0, 'replaced: packed');
  Check(CodePageToPackedUtf8(#$80) = $96D0, 'replaced: hook');
  CheckFrom(Seq([$D0, $96]), $80, 'replaced: new sequence');
  CheckFrom('A', $41, 'replaced: A, the lowest of two characters');
  CheckFrom(Seq([$C3, $87]), 0, 'replaced: old sequence is gone');
  CheckFrom(Seq([$C3, $BC]), $00, 'replaced: u diaeresis is gone');
  CheckFrom(Seq([$C3, $A9]), $82, 'replaced: other entry');
  { The table is copied. }
  T[$80][0] := $D0;
  T[$80][1] := $97;
  CheckToUtf8($80, [$D0, $96], 'replaced: copy');
  CpTranslator.SetTranslation(nil);
  CheckToUtf8($80, [$C3, $87], 'restored: entry');
  CheckToUtf8($81, [$C3, $BC], 'restored: second entry');
  CheckFrom(Seq([$C3, $87]), $80, 'restored: sequence');
  CheckFrom(Seq([$D0, $96]), 0, 'restored: replaced sequence is gone');
  Check(CodePageToPackedUtf8(#$80) = $87C3, 'restored: hook');
end;

begin
  TestTable;
  TestPacked;
  TestReverse;
  TestPrintable;
  TestReplaced;
  Done;
end.
