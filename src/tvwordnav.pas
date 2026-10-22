{ Word boundaries for Ctrl+Left and Ctrl+Right in a single-line input field. }
unit TvWordNav;

{$mode objfpc}
{$R-}
{$Q-}

interface

const
  wnSpace = 0;
  wnDivider = 1;
  wnWord = 2;

var
  { Ctrl+Left and Ctrl+Right in input fields follow these rules; False: the classic jump over blanks only }
  UxWordNav: Boolean = True;
  { the word dividers (a space and a tab are not among them) }
  WordDividers: ShortString = '~!%^&*()+|{}:"<>?`-=\[];'',./';

function WordClassOf(Ch: Char): Integer;

{ The position after Ctrl+Right (Fine = False) or Ctrl+Shift+Right in an input field (Fine = True), starting at Pos; it moves at least one byte. }
function WordNavRight(const S: ShortString; Pos: Integer; Fine: Boolean = False): Integer;

{ The same to the left. }
function WordNavLeft(const S: ShortString; Pos: Integer; Fine: Boolean = False): Integer;

implementation

const
  TabCode = 9;
  SpaceCode = 32;
  HighBit = 128;

function WordClassOf(Ch: Char): Integer;
var
  Code: Integer;
begin
  Code := Ord(Ch);
  if (Code = SpaceCode) or (Code = TabCode) then
    Result := wnSpace
  else if (Code < HighBit) and (Pos(Ch, WordDividers) > 0) then
    Result := wnDivider
  else
    Result := wnWord;
end;

{ Classes of the bytes at Q and Q+1 (1-based); the callers keep 1 <= Q and Q < Length(S). }
procedure ClassesAround(const S: ShortString; Q: Integer; out Prev, Curr: Integer);
begin
  Prev := WordClassOf(S[Q]);
  Curr := WordClassOf(S[Q + 1]);
end;

function WordNavRight(const S: ShortString; Pos: Integer; Fine: Boolean): Integer;
var
  Len, Prev, Curr: Integer;
  Stop: Boolean;
begin
  Len := Length(S);
  if Pos >= Len then
  begin
    Result := Len;
    Exit;
  end;
  if Pos < 0 then
    Pos := 0; { below 0 is not supported; treated as 0 }
  Result := Pos + 1;
  while Result < Len do
  begin
    ClassesAround(S, Result, Prev, Curr);
    if Fine then
      Stop := not ((Prev = wnWord) and (Curr = wnWord)) and (Curr <> wnSpace)
    else
      Stop := ((Prev = wnSpace) and (Curr <> wnSpace)) or ((Prev = wnWord) and (Curr = wnDivider));
    if Stop then
      Exit;
    Inc(Result);
  end;
  Result := Len;
end;

function WordNavLeft(const S: ShortString; Pos: Integer; Fine: Boolean): Integer;
var
  Len, Prev, Curr: Integer;
  Stop: Boolean;
begin
  Len := Length(S);
  if Pos <= 0 then
  begin
    Result := 0;
    Exit;
  end;
  if Pos > Len then
    Pos := Len; { beyond the end is not supported; treated as the end }
  Result := Pos - 1;
  while Result > 0 do
  begin
    ClassesAround(S, Result, Prev, Curr);
    if Fine then
      Stop := not ((Prev = wnWord) and (Curr = wnWord)) and (Curr <> wnSpace) and
        not ((Prev = wnWord) and (Curr = wnDivider))
    else
      Stop := ((Prev = wnSpace) and (Curr <> wnSpace)) or ((Prev = wnDivider) and (Curr = wnWord));
    if Stop then
      Exit;
    Dec(Result);
  end;
  Result := 0;
end;

end.
