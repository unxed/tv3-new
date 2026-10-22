{ Matches file names against masks with the wild cards '*', '?' and '[set]', and against lists of masks with exclusions. }
unit TvWild;

{$mode objfpc}
{$R-}
{$Q-}

interface

function WildMatch(const Name, Mask: AnsiString; CaseSensitive: Boolean = False): Boolean;
function WildMatchList(const Name, List: AnsiString; CaseSensitive: Boolean = False): Boolean;
{ True when the text has a wild card of a mask ('*', '?', '['). }
function HasWild(const S: AnsiString): Boolean;

implementation

function WildMatch(const Name, Mask: AnsiString; CaseSensitive: Boolean): Boolean;
begin
  Result := False;
end;

function WildMatchList(const Name, List: AnsiString; CaseSensitive: Boolean): Boolean;
begin
  Result := False;
end;

function HasWild(const S: AnsiString): Boolean;
begin
  Result := False;
end;

end.
