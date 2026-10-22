{ Test program of the unit TvWordNav. }
program t_wordnav;

{$mode objfpc}

uses
  SysUtils, TvWordNav;

{$I testlib.inc}

{ The positions visited by repeated moves, from 0 to the right or from the end to the left, as '3,7'. }
function Visited(const S: ShortString; ToRight, Fine: Boolean): string;
var
  P, Goal: Integer;
begin
  Result := '';
  if ToRight then
  begin
    P := 0;
    Goal := Length(S);
  end
  else
  begin
    P := Length(S);
    Goal := 0;
  end;
  { an empty text still gives one move, which stays where it is }
  repeat
    if ToRight then
      P := WordNavRight(S, P, Fine)
    else
      P := WordNavLeft(S, P, Fine);
    Result := Result + IntToStr(P) + ',';
  until P = Goal;
  SetLength(Result, Length(Result) - 1);
end;

procedure Row(const S: ShortString; ToRight, Fine: Boolean; const Expected: string);
var
  Name: string;
begin
  Name := '"' + S + '"';
  if ToRight then
    Name := Name + ' right'
  else
    Name := Name + ' left';
  if Fine then
    Name := Name + ' fine'
  else
    Name := Name + ' coarse';
  Check(Visited(S, ToRight, Fine) = Expected, Name);
end;

var
  I, Pos, Next, Round_: Integer;
  Saved: ShortString;
  Rnd: ShortString;
  Sp: ShortString;
  Bounded, Moving, Reaches: Boolean;
  Alphabet: ShortString;
  Fwd, Back: Integer;

begin
  { The rows of the table }
  Row('foo.bar', True, False, '3,7');
  Row('foo.bar', False, False, '4,0');
  Row('...///', True, False, '6');
  Row('foo bar baz', True, False, '4,8,11');
  Row('foo bar baz', False, False, '8,4,0');
  Row('a.-/b', True, False, '1,5');
  Row('a.-/b', True, True, '1,2,3,4,5');
  Row('foo bar', True, True, '4,7');
  Row('foo bar', False, True, '4,0');
  Row('a.-/b', False, True, '4,3,2,0');

  { Single calls }
  Check(WordNavRight('abc', 3) = 3, 'right at the end');
  Check(WordNavLeft('abc', 0) = 0, 'left at the start');
  Check(WordNavRight('', 0) = 0, 'right in the empty text');
  Check(WordNavLeft('', 0) = 0, 'left in the empty text');
  Check(WordNavRight('abc', 10) = 3, 'right beyond the end');
  Check(WordNavLeft('abc', -2) = 0, 'left below the start');
  Check(WordNavRight('abc', 3, True) = 3, 'fine right at the end');
  Check(WordNavLeft('abc', 0, True) = 0, 'fine left at the start');
  Check(WordNavRight('abc', 1) = 3, 'right inside the only word');
  Check(WordNavLeft('abc', 2) = 0, 'left inside the only word');

  { Classes }
  Check(WordClassOf(' ') = wnSpace, 'class of a space');
  Check(WordClassOf(#9) = wnSpace, 'class of a tab');
  Check(WordClassOf('.') = wnDivider, 'class of a dot');
  Check(WordClassOf('_') = wnWord, 'class of _');
  Check(WordClassOf('$') = wnWord, 'class of $');
  Check(WordClassOf('#') = wnWord, 'class of #');
  Check(WordClassOf('@') = wnWord, 'class of @');
  Check(WordClassOf('a') = wnWord, 'class of a letter');
  Check(WordClassOf('7') = wnWord, 'class of a digit');
  Check(WordClassOf(#1) = wnWord, 'class of a control character');
  Check(WordClassOf(#$D0) = wnWord, 'class of the byte $D0');
  Check(WordClassOf(#$FF) = wnWord, 'class of the byte $FF');
  Check((wnSpace = 0) and (wnDivider = 1) and (wnWord = 2), 'values of the classes');
  Check(UxWordNav, 'the switch starts True');
  Check(Length(WordDividers) = 28, 'number of default dividers');
  for I := 1 to Length(WordDividers) do
    Check(WordClassOf(WordDividers[I]) = wnDivider, 'default divider ' + WordDividers[I]);

  { Changing the dividers }
  Saved := WordDividers;
  WordDividers := '_';
  Check(WordClassOf('_') = wnDivider, 'underscore as a divider');
  Check(WordClassOf('.') = wnWord, 'dot as a word character');
  Check(WordClassOf(' ') = wnSpace, 'space stays a space');
  Check(WordNavRight('a_b', 0) = 1, 'stop at the new divider');
  WordDividers := Saved;
  Check(WordClassOf('_') = wnWord, 'underscore restored');
  Check(WordClassOf('.') = wnDivider, 'dot restored');
  Check(WordNavRight('a_b', 0) = 3, 'no stop at the restored underscore');

  { Bounds }
  Rnd := 'ab. c-d  e.f/g _h $i';
  for Round_ := 0 to 1 do
  begin
    Bounded := True;
    Moving := True;
    for Pos := 0 to Length(Rnd) do
    begin
      Next := WordNavRight(Rnd, Pos, Round_ = 1);
      if (Next < 0) or (Next > Length(Rnd)) then
        Bounded := False;
      if (Next <= Pos) and (Pos < Length(Rnd)) then
        Moving := False;
      if (Pos >= Length(Rnd)) and (Next <> Length(Rnd)) then
        Moving := False;
      Next := WordNavLeft(Rnd, Pos, Round_ = 1);
      if (Next < 0) or (Next > Length(Rnd)) then
        Bounded := False;
      if (Next >= Pos) and (Pos > 0) then
        Moving := False;
      if (Pos = 0) and (Next <> 0) then
        Moving := False;
    end;
    Check(Bounded, 'results within the text, round ' + IntToStr(Round_));
    Check(Moving, 'every move advances, round ' + IntToStr(Round_));
  end;

  { Termination on generated texts }
  Alphabet := 'ab _.-/'#9#$D0#$A4;
  RandSeed := 12345;
  Reaches := True;
  for Round_ := 1 to 200 do
  begin
    SetLength(Rnd, Random(30));
    for I := 1 to Length(Rnd) do
      Rnd[I] := Alphabet[1 + Random(Length(Alphabet))];
    for I := 0 to 1 do
    begin
      Pos := 0;
      Fwd := 0;
      while (Pos < Length(Rnd)) and (Fwd <= Length(Rnd)) do
      begin
        Pos := WordNavRight(Rnd, Pos, I = 1);
        Inc(Fwd);
      end;
      if Pos <> Length(Rnd) then
        Reaches := False;
      Pos := Length(Rnd);
      Back := 0;
      while (Pos > 0) and (Back <= Length(Rnd)) do
      begin
        Pos := WordNavLeft(Rnd, Pos, I = 1);
        Inc(Back);
      end;
      if Pos <> 0 then
        Reaches := False;
    end;
  end;
  Check(Reaches, 'generated texts are crossed in both directions');

  { Only spaces }
  Sp := '     ';
  Check(WordNavRight(Sp, 0) = 5, 'coarse right over spaces only');
  Check(WordNavRight(Sp, 0, True) = 5, 'fine right over spaces only');
  Check(WordNavLeft(Sp, 5) = 0, 'coarse left over spaces only');

  { Non-ASCII bytes }
  Rnd := #$D0#$A4'x';
  Check(WordNavRight(Rnd, 0) = 3, 'no coarse stop inside a multi-byte character, right');
  Check(WordNavLeft(Rnd, 3) = 0, 'no coarse stop inside a multi-byte character, left');
  Check(WordNavRight(Rnd, 0, True) = 3, 'no fine stop inside a word of high bytes');

  { A tab acts as a blank }
  Check(WordNavRight('a'#9'b', 0) = 2, 'right stops after a tab');
  Check(WordNavLeft('a'#9'b', 3) = 2, 'left to the word after a tab');

  Done;
end.
