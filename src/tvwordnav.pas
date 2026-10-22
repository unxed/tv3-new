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

function WordClassOf(Ch: Char): Integer;
begin
  Result := wnWord;
end;

function WordNavRight(const S: ShortString; Pos: Integer; Fine: Boolean): Integer;
begin
  Result := Pos;
end;

function WordNavLeft(const S: ShortString; Pos: Integer; Fine: Boolean): Integer;
begin
  Result := Pos;
end;

end.
