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

uses
  SysUtils, TvUtf8, TvUStr;

const
  CpStar = Ord('*');
  CpAny = Ord('?');
  CpOpen = Ord('[');
  CpClose = Ord(']');
  CpDash = Ord('-');
  CpNot1 = Ord('!');
  CpNot2 = Ord('^');

type
  TCodes = array of LongWord;

  TRange = record
    Lo, Hi: LongWord;
  end;

  TItemKind = (ikLiteral, ikAnyOne, ikStar, ikSet);

  TItem = record
    Kind: TItemKind;
    Code: LongWord;
    Negated: Boolean;
    FirstRange, RangeCount: Integer;
  end;

  TPattern = record
    Items: array of TItem;
    Ranges: array of TRange;
  end;

{ The characters of S as code points: UTF-8 sequences in UTF-8 mode, bytes otherwise. }
function Decode(const S: AnsiString): TCodes;
var
  Pos, Len, Cnt: Integer;
begin
  SetLength(Result, Length(S));
  Cnt := 0;
  Pos := 1;
  while Pos <= Length(S) do
  begin
    Len := U8CharBytes(S, Pos);
    if Len <= 1 then
    begin
      Len := 1;
      Result[Cnt] := Ord(S[Pos]);
    end
    else
      Result[Cnt] := U8CodePoint(Copy(S, Pos, Len), 0);
    Inc(Cnt);
    Inc(Pos, Len);
  end;
  SetLength(Result, Cnt);
end;

procedure AddItem(var P: TPattern; AKind: TItemKind; ACode: LongWord);
var
  N: Integer;
begin
  N := Length(P.Items);
  SetLength(P.Items, N + 1);
  P.Items[N].Kind := AKind;
  P.Items[N].Code := ACode;
  P.Items[N].Negated := False;
  P.Items[N].FirstRange := 0;
  P.Items[N].RangeCount := 0;
end;

procedure AddRange(var P: TPattern; ALo, AHi: LongWord);
var
  N: Integer;
begin
  N := Length(P.Ranges);
  SetLength(P.Ranges, N + 1);
  P.Ranges[N].Lo := ALo;
  P.Ranges[N].Hi := AHi;
end;

{ True when a ']' stands in M at an index of From or more. }
function HasCloser(const M: TCodes; From: Integer): Boolean;
var
  K: Integer;
begin
  Result := False;
  for K := From to High(M) do
    if M[K] = CpClose then
    begin
      Result := True;
      Exit;
    end;
end;

{ Reads the set that opens at M[At]; returns the index after its ']', or At when it is no set. }
function ReadSet(const M: TCodes; At: Integer; var P: TPattern): Integer;
var
  Run, Idx: Integer;
  Lo, Hi: LongWord;
  Neg, FirstMember: Boolean;
begin
  Result := At;
  Run := At + 1;
  Neg := (Run <= High(M)) and ((M[Run] = CpNot1) or (M[Run] = CpNot2));
  if Neg then
    Inc(Run);
  if not HasCloser(M, Run + 1) then
    Exit;
  AddItem(P, ikSet, 0);
  Idx := High(P.Items);
  P.Items[Idx].Negated := Neg;
  P.Items[Idx].FirstRange := Length(P.Ranges);
  FirstMember := True;
  while (Run <= High(M)) and (FirstMember or (M[Run] <> CpClose)) do
  begin
    Lo := M[Run];
    Hi := Lo;
    Inc(Run);
    if (Run + 1 <= High(M)) and (M[Run] = CpDash) and (M[Run + 1] <> CpClose) then
    begin
      Hi := M[Run + 1];
      Inc(Run, 2);
    end;
    AddRange(P, Lo, Hi);
    FirstMember := False;
  end;
  P.Items[Idx].RangeCount := Length(P.Ranges) - P.Items[Idx].FirstRange;
  Result := Run + 1;
end;

procedure Compile(const M: TCodes; var P: TPattern);
var
  At, After: Integer;
begin
  SetLength(P.Items, 0);
  SetLength(P.Ranges, 0);
  At := 0;
  while At <= High(M) do
  begin
    case M[At] of
      CpStar:
        begin
          AddItem(P, ikStar, 0);
          Inc(At);
        end;
      CpAny:
        begin
          AddItem(P, ikAnyOne, 0);
          Inc(At);
        end;
      CpOpen:
        begin
          After := ReadSet(M, At, P);
          if After = At then
          begin
            AddItem(P, ikLiteral, CpOpen);
            Inc(At);
          end
          else
            At := After;
        end;
    else
      AddItem(P, ikLiteral, M[At]);
      Inc(At);
    end;
  end;
end;

function Accepts(const P: TPattern; Idx: Integer; Ch: LongWord): Boolean;
var
  K: Integer;
  Found: Boolean;
begin
  case P.Items[Idx].Kind of
    ikLiteral:
      Result := P.Items[Idx].Code = Ch;
    ikAnyOne:
      Result := True;
    ikSet:
      begin
        Found := False;
        for K := P.Items[Idx].FirstRange to P.Items[Idx].FirstRange + P.Items[Idx].RangeCount - 1 do
          if (Ch >= P.Ranges[K].Lo) and (Ch <= P.Ranges[K].Hi) then
          begin
            Found := True;
            Break;
          end;
        Result := Found <> P.Items[Idx].Negated;
      end;
  else
    Result := False;
  end;
end;

function Run(const N: TCodes; const P: TPattern): Boolean;
var
  NamePos, ItemPos, StarItem, StarName: Integer;
begin
  NamePos := 0;
  ItemPos := 0;
  StarItem := -1;
  StarName := 0;
  while NamePos < Length(N) do
  begin
    if (ItemPos < Length(P.Items)) and (P.Items[ItemPos].Kind = ikStar) then
    begin
      StarItem := ItemPos;
      StarName := NamePos;
      Inc(ItemPos);
    end
    else if (ItemPos < Length(P.Items)) and Accepts(P, ItemPos, N[NamePos]) then
    begin
      Inc(ItemPos);
      Inc(NamePos);
    end
    else if StarItem >= 0 then
    begin
      Inc(StarName);
      NamePos := StarName;
      ItemPos := StarItem + 1;
    end
    else
    begin
      Result := False;
      Exit;
    end;
  end;
  while (ItemPos < Length(P.Items)) and (P.Items[ItemPos].Kind = ikStar) do
    Inc(ItemPos);
  Result := ItemPos = Length(P.Items);
end;

{ S itself, or its lower-case form when the case does not matter. }
function Fold(const S: AnsiString; CaseSensitive: Boolean): AnsiString;
begin
  if CaseSensitive then
    Result := S
  else
    Result := U8Lower(S);
end;

function WildMatch(const Name, Mask: AnsiString; CaseSensitive: Boolean): Boolean;
var
  P: TPattern;
begin
  if Mask = '*.*' then
  begin
    Result := True;
    Exit;
  end;
  Compile(Decode(Fold(Mask, CaseSensitive)), P);
  Result := Run(Decode(Fold(Name, CaseSensitive)), P);
end;

{ True when one of the masks of Part, separated by ';' or ',', matches Name. }
function PartMatches(const Name, Part: AnsiString; CaseSensitive: Boolean): Boolean;
var
  From, Pos: Integer;
  Item: AnsiString;
begin
  Result := False;
  From := 1;
  for Pos := 1 to Length(Part) + 1 do
    if (Pos > Length(Part)) or (Part[Pos] = ';') or (Part[Pos] = ',') then
    begin
      Item := Trim(Copy(Part, From, Pos - From));
      From := Pos + 1;
      if (Item <> '') and WildMatch(Name, Item, CaseSensitive) then
      begin
        Result := True;
        Exit;
      end;
    end;
end;

function WildMatchList(const Name, List: AnsiString; CaseSensitive: Boolean): Boolean;
var
  Bar: Integer;
  IncPart, Exc: AnsiString;
begin
  Bar := Pos('|', List);
  if Bar = 0 then
  begin
    IncPart := List;
    Exc := '';
  end
  else
  begin
    IncPart := Copy(List, 1, Bar - 1);
    Exc := Copy(List, Bar + 1, Length(List));
  end;
  if Trim(IncPart) <> '' then
    Result := PartMatches(Name, IncPart, CaseSensitive)
  else
    Result := Exc <> '';
  if (Exc <> '') and PartMatches(Name, Exc, CaseSensitive) then
    Result := False;
end;

function HasWild(const S: AnsiString): Boolean;
var
  K: Integer;
begin
  Result := False;
  for K := 1 to Length(S) do
    if S[K] in ['*', '?', '['] then
    begin
      Result := True;
      Exit;
    end;
end;

end.
