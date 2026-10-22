{ Tells how a file path looks on a system (separator, root, drive, joining, splitting, normalising, expanding) with
  rules that are given or native. Only the Unix target is implemented: the branches for DOS, Windows and OS/2 are
  left out. }
unit TvPath;

{$mode objfpc}
{$R-}
{$Q-}

interface

type
  TPathRules = record
    Sep: Char;              { the separator that is written }
    AltSep: Char;           { a second character read as a separator (#0: none) }
    Drives: Boolean;        { "C:" drive prefixes and "\\server\share" roots }
    CaseSensitive: Boolean; { names that differ in case are different files }
    ListSep: Char;          { between the directories of a list such as PATH }
    AllFiles: string[3];    { the mask of every file }
  end;

const
  UnixPathRules: TPathRules = (Sep: '/'; AltSep: #0; Drives: False; CaseSensitive: True; ListSep: ':'; AllFiles: '*');
  DosPathRules: TPathRules = (Sep: '\'; AltSep: '/'; Drives: True; CaseSensitive: False; ListSep: ';'; AllFiles: '*.*');

  { The native constants of a target without drives. }
  PathSep = '/';
  PathHasDrives = False;
  PathAllFiles = '*';

function NativePathRules: TPathRules;

function IsPathSep(C: Char): Boolean; overload;
function IsPathSep(C: Char; const R: TPathRules): Boolean; overload;
function EndsWithSep(const S: AnsiString): Boolean; overload;
function EndsWithSep(const S: AnsiString; const R: TPathRules): Boolean; overload;

function PathDrive(const S: AnsiString): AnsiString; overload;
function PathDrive(const S: AnsiString; const R: TPathRules): AnsiString; overload;
function PathRootLen(const S: AnsiString): Integer; overload;
function PathRootLen(const S: AnsiString; const R: TPathRules): Integer; overload;
function PathIsRooted(const S: AnsiString): Boolean; overload;
function PathIsRooted(const S: AnsiString; const R: TPathRules): Boolean; overload;
function PathIsAbsolute(const S: AnsiString): Boolean; overload;
function PathIsAbsolute(const S: AnsiString; const R: TPathRules): Boolean; overload;
function PathIsRoot(const S: AnsiString): Boolean; overload;
function PathIsRoot(const S: AnsiString; const R: TPathRules): Boolean; overload;

function PathAddSep(const S: AnsiString): AnsiString; overload;
function PathAddSep(const S: AnsiString; const R: TPathRules): AnsiString; overload;
function PathDelSep(const S: AnsiString): AnsiString; overload;
function PathDelSep(const S: AnsiString; const R: TPathRules): AnsiString; overload;
function PathJoin(const Dir, Name: AnsiString): AnsiString; overload;
function PathJoin(const Dir, Name: AnsiString; const R: TPathRules): AnsiString; overload;

procedure PathSplit(const S: AnsiString; out Dir, Name, Ext: AnsiString); overload;
procedure PathSplit(const S: AnsiString; out Dir, Name, Ext: AnsiString; const R: TPathRules); overload;
function PathDir(const S: AnsiString): AnsiString; overload;
function PathDir(const S: AnsiString; const R: TPathRules): AnsiString; overload;
function PathName(const S: AnsiString): AnsiString; overload;
function PathName(const S: AnsiString; const R: TPathRules): AnsiString; overload;
function PathExt(const S: AnsiString): AnsiString; overload;
function PathExt(const S: AnsiString; const R: TPathRules): AnsiString; overload;
function PathChangeExt(const S, Ext: AnsiString): AnsiString; overload;
function PathChangeExt(const S, Ext: AnsiString; const R: TPathRules): AnsiString; overload;

function PathNative(const S: AnsiString): AnsiString; overload;
function PathNative(const S: AnsiString; const R: TPathRules): AnsiString; overload;
function PathNormalize(const S: AnsiString): AnsiString; overload;
function PathNormalize(const S: AnsiString; const R: TPathRules): AnsiString; overload;
function PathExpand(const S: AnsiString): AnsiString;
function PathExpandFrom(const S, Base: AnsiString): AnsiString;
function PathExpandIn(const S, Cur: AnsiString; const R: TPathRules): AnsiString;

function PathSameName(const A, B: AnsiString): Boolean; overload;
function PathSameName(const A, B: AnsiString; const R: TPathRules): Boolean; overload;

function PathCurRoot: AnsiString;

implementation

uses
  SysUtils;

function NativePathRules: TPathRules;
begin
  Result := UnixPathRules;
end;

function IsPathSep(C: Char; const R: TPathRules): Boolean;
begin
  Result := (C = R.Sep) or ((R.AltSep <> #0) and (C = R.AltSep));
end;

function IsPathSep(C: Char): Boolean;
begin
  Result := IsPathSep(C, NativePathRules);
end;

function EndsWithSep(const S: AnsiString; const R: TPathRules): Boolean;
begin
  Result := (S <> '') and IsPathSep(S[Length(S)], R);
end;

function EndsWithSep(const S: AnsiString): Boolean;
begin
  Result := EndsWithSep(S, NativePathRules);
end;

{ The length of the drive part of S: 0, 2 for a letter drive, more for a UNC drive. }
function DriveLen(const S: AnsiString; const R: TPathRules): Integer;
var
  Len, Pos, Seen: Integer;
begin
  Result := 0;
  if not R.Drives then
    Exit;
  Len := Length(S);
  if (Len >= 2) and (S[2] = ':') and (S[1] in ['A'..'Z', 'a'..'z']) then
    Result := 2
  else if (Len >= 3) and IsPathSep(S[1], R) and IsPathSep(S[2], R) and not IsPathSep(S[3], R) then
  begin
    Seen := 0;
    Pos := 3;
    while Pos <= Len do
    begin
      if IsPathSep(S[Pos], R) then
      begin
        Inc(Seen);
        if Seen = 2 then
          Break;
      end;
      Inc(Pos);
    end;
    Result := Pos - 1;
  end;
end;

function PathDrive(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := Copy(S, 1, DriveLen(S, R));
end;

function PathDrive(const S: AnsiString): AnsiString;
begin
  Result := PathDrive(S, NativePathRules);
end;

function PathRootLen(const S: AnsiString; const R: TPathRules): Integer;
begin
  Result := DriveLen(S, R);
  if (Result < Length(S)) and IsPathSep(S[Result + 1], R) then
    Inc(Result);
end;

function PathRootLen(const S: AnsiString): Integer;
begin
  Result := PathRootLen(S, NativePathRules);
end;

function PathIsRooted(const S: AnsiString; const R: TPathRules): Boolean;
var
  Drive: Integer;
begin
  Drive := DriveLen(S, R);
  Result := (Drive > 2) or (PathRootLen(S, R) > Drive);
end;

function PathIsRooted(const S: AnsiString): Boolean;
begin
  Result := PathIsRooted(S, NativePathRules);
end;

function PathIsAbsolute(const S: AnsiString; const R: TPathRules): Boolean;
begin
  Result := PathIsRooted(S, R) and (not R.Drives or (DriveLen(S, R) > 0));
end;

function PathIsAbsolute(const S: AnsiString): Boolean;
begin
  Result := PathIsAbsolute(S, NativePathRules);
end;

function PathIsRoot(const S: AnsiString; const R: TPathRules): Boolean;
begin
  Result := (S <> '') and PathIsRooted(S, R) and (PathRootLen(S, R) = Length(S));
end;

function PathIsRoot(const S: AnsiString): Boolean;
begin
  Result := PathIsRoot(S, NativePathRules);
end;

function PathAddSep(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  if (S = '') or EndsWithSep(S, R) or ((Length(S) = 2) and (DriveLen(S, R) = 2)) then
    Result := S
  else
    Result := S + R.Sep;
end;

function PathAddSep(const S: AnsiString): AnsiString;
begin
  Result := PathAddSep(S, NativePathRules);
end;

function PathDelSep(const S: AnsiString; const R: TPathRules): AnsiString;
var
  Keep, Last: Integer;
begin
  Keep := PathRootLen(S, R);
  Last := Length(S);
  while (Last > Keep) and IsPathSep(S[Last], R) do
    Dec(Last);
  Result := Copy(S, 1, Last);
end;

function PathDelSep(const S: AnsiString): AnsiString;
begin
  Result := PathDelSep(S, NativePathRules);
end;

function PathJoin(const Dir, Name: AnsiString; const R: TPathRules): AnsiString;
begin
  if (Dir = '') or PathIsRooted(Name, R) or (DriveLen(Name, R) > 0) then
    Result := Name
  else if Name = '' then
    Result := Dir
  else
    Result := PathAddSep(Dir, R) + Name;
end;

function PathJoin(const Dir, Name: AnsiString): AnsiString;
begin
  Result := PathJoin(Dir, Name, NativePathRules);
end;

procedure PathSplit(const S: AnsiString; out Dir, Name, Ext: AnsiString; const R: TPathRules);
var
  Drive, DirEnd, Dot, I: Integer;
  FilePart, D, N, E: AnsiString;
begin
  Drive := DriveLen(S, R);
  DirEnd := Drive;
  for I := Length(S) downto Drive + 1 do
    if IsPathSep(S[I], R) then
    begin
      DirEnd := I;
      Break;
    end;
  D := Copy(S, 1, DirEnd);
  FilePart := Copy(S, DirEnd + 1, Length(S));
  N := FilePart;
  E := '';
  if (FilePart <> '.') and (FilePart <> '..') then
  begin
    Dot := 0;
    for I := Length(FilePart) downto 2 do
      if FilePart[I] = '.' then
      begin
        Dot := I;
        Break;
      end;
    if Dot > 0 then
    begin
      N := Copy(FilePart, 1, Dot - 1);
      E := Copy(FilePart, Dot, Length(FilePart));
    end;
  end;
  Dir := D;
  Name := N;
  Ext := E;
end;

procedure PathSplit(const S: AnsiString; out Dir, Name, Ext: AnsiString);
begin
  PathSplit(S, Dir, Name, Ext, NativePathRules);
end;

function PathDir(const S: AnsiString; const R: TPathRules): AnsiString;
var
  N, E: AnsiString;
begin
  PathSplit(S, Result, N, E, R);
end;

function PathDir(const S: AnsiString): AnsiString;
begin
  Result := PathDir(S, NativePathRules);
end;

function PathName(const S: AnsiString; const R: TPathRules): AnsiString;
var
  D, N, E: AnsiString;
begin
  PathSplit(S, D, N, E, R);
  Result := N + E;
end;

function PathName(const S: AnsiString): AnsiString;
begin
  Result := PathName(S, NativePathRules);
end;

function PathExt(const S: AnsiString; const R: TPathRules): AnsiString;
var
  D, N: AnsiString;
begin
  PathSplit(S, D, N, Result, R);
end;

function PathExt(const S: AnsiString): AnsiString;
begin
  Result := PathExt(S, NativePathRules);
end;

function PathChangeExt(const S, Ext: AnsiString; const R: TPathRules): AnsiString;
var
  D, N, E: AnsiString;
begin
  PathSplit(S, D, N, E, R);
  Result := D + N + Ext;
end;

function PathChangeExt(const S, Ext: AnsiString): AnsiString;
begin
  Result := PathChangeExt(S, Ext, NativePathRules);
end;

function PathNative(const S: AnsiString; const R: TPathRules): AnsiString;
var
  I: Integer;
begin
  Result := S;
  if R.AltSep = #0 then
    Exit;
  for I := 1 to Length(Result) do
    if Result[I] = R.AltSep then
      Result[I] := R.Sep;
end;

function PathNative(const S: AnsiString): AnsiString;
begin
  Result := PathNative(S, NativePathRules);
end;

function PathNormalize(const S: AnsiString; const R: TPathRules): AnsiString;
var
  N, Root, Part: AnsiString;
  Kept: array of AnsiString;
  Count, RootLen, I, Start: Integer;
  Rooted: Boolean;
begin
  N := PathNative(S, R);
  if N = '' then
  begin
    Result := '';
    Exit;
  end;
  RootLen := PathRootLen(N, R);
  Root := Copy(N, 1, RootLen);
  Rooted := PathIsRooted(N, R);
  SetLength(Kept, Length(N) + 1);
  Count := 0;
  Start := RootLen + 1;
  for I := RootLen + 1 to Length(N) + 1 do
    if (I > Length(N)) or (N[I] = R.Sep) then
    begin
      Part := Copy(N, Start, I - Start);
      Start := I + 1;
      if (Part = '') or (Part = '.') then
        Continue;
      if Part = '..' then
      begin
        if (Count > 0) and (Kept[Count - 1] <> '..') then
          Dec(Count)
        else if not Rooted then
        begin
          Kept[Count] := Part;
          Inc(Count);
        end;
      end
      else
      begin
        Kept[Count] := Part;
        Inc(Count);
      end;
    end;
  Result := Root;
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + R.Sep;
    Result := Result + Kept[I];
  end;
  if (Root = '') and (Count = 0) then
    Result := '.'
  else if (Length(N) > RootLen) and EndsWithSep(N, R) and (Count > 0) then
    Result := Result + R.Sep;
end;

function PathNormalize(const S: AnsiString): AnsiString;
begin
  Result := PathNormalize(S, NativePathRules);
end;

function PathExpandIn(const S, Cur: AnsiString; const R: TPathRules): AnsiString;
var
  Drive, CurDrive, Rest: AnsiString;
begin
  if PathIsAbsolute(S, R) then
  begin
    Result := PathNormalize(S, R);
    Exit;
  end;
  Drive := PathDrive(S, R);
  CurDrive := PathDrive(Cur, R);
  Rest := Copy(S, Length(Drive) + 1, Length(S));
  if (Drive <> '') and (AnsiCompareText(Drive, CurDrive) <> 0) then
    Result := PathNormalize(Drive + R.Sep + Rest, R)
  else if PathIsRooted(S, R) then
    Result := PathNormalize(CurDrive + Rest, R)
  else
    Result := PathNormalize(PathJoin(Cur, Rest, R), R);
end;

function PathExpand(const S: AnsiString): AnsiString;
var
  Cur: AnsiString;
begin
  Cur := GetCurrentDir;
  if S = '' then
    Result := PathAddSep(Cur, UnixPathRules)
  else
    Result := PathExpandIn(S, Cur, UnixPathRules);
end;

function PathExpandFrom(const S, Base: AnsiString): AnsiString;
begin
  if (Base = '') or PathIsRooted(S) or (PathDrive(S) <> '') then
    Result := PathExpand(S)
  else
    Result := PathExpand(PathJoin(Base, S));
end;

function PathSameName(const A, B: AnsiString; const R: TPathRules): Boolean;
begin
  if R.CaseSensitive then
    Result := A = B
  else
    Result := AnsiCompareText(A, B) = 0;
end;

function PathSameName(const A, B: AnsiString): Boolean;
begin
  Result := PathSameName(A, B, NativePathRules);
end;

function PathCurRoot: AnsiString;
var
  Cur: AnsiString;
begin
  Cur := GetCurrentDir;
  if Cur = '' then
    Result := ''
  else
  begin
    Result := Copy(Cur, 1, PathRootLen(Cur));
    if not PathIsRooted(Result) then
      Result := Result + PathSep;
  end;
end;

end.
