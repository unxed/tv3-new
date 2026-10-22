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

function IsPathSep(C: Char): Boolean;
begin
  Result := False;
end;

function IsPathSep(C: Char; const R: TPathRules): Boolean;
begin
  Result := False;
end;

function EndsWithSep(const S: AnsiString): Boolean;
begin
  Result := False;
end;

function EndsWithSep(const S: AnsiString; const R: TPathRules): Boolean;
begin
  Result := False;
end;

function PathDrive(const S: AnsiString): AnsiString;
begin
  Result := '';
end;

function PathDrive(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := '';
end;

function PathRootLen(const S: AnsiString): Integer;
begin
  Result := 0;
end;

function PathRootLen(const S: AnsiString; const R: TPathRules): Integer;
begin
  Result := 0;
end;

function PathIsRooted(const S: AnsiString): Boolean;
begin
  Result := False;
end;

function PathIsRooted(const S: AnsiString; const R: TPathRules): Boolean;
begin
  Result := False;
end;

function PathIsAbsolute(const S: AnsiString): Boolean;
begin
  Result := False;
end;

function PathIsAbsolute(const S: AnsiString; const R: TPathRules): Boolean;
begin
  Result := False;
end;

function PathIsRoot(const S: AnsiString): Boolean;
begin
  Result := False;
end;

function PathIsRoot(const S: AnsiString; const R: TPathRules): Boolean;
begin
  Result := False;
end;

function PathAddSep(const S: AnsiString): AnsiString;
begin
  Result := S;
end;

function PathAddSep(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := S;
end;

function PathDelSep(const S: AnsiString): AnsiString;
begin
  Result := S;
end;

function PathDelSep(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := S;
end;

function PathJoin(const Dir, Name: AnsiString): AnsiString;
begin
  Result := Name;
end;

function PathJoin(const Dir, Name: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := Name;
end;

procedure PathSplit(const S: AnsiString; out Dir, Name, Ext: AnsiString);
begin
  Dir := '';
  Name := S;
  Ext := '';
end;

procedure PathSplit(const S: AnsiString; out Dir, Name, Ext: AnsiString; const R: TPathRules);
begin
  Dir := '';
  Name := S;
  Ext := '';
end;

function PathDir(const S: AnsiString): AnsiString;
begin
  Result := '';
end;

function PathDir(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := '';
end;

function PathName(const S: AnsiString): AnsiString;
begin
  Result := S;
end;

function PathName(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := S;
end;

function PathExt(const S: AnsiString): AnsiString;
begin
  Result := '';
end;

function PathExt(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := '';
end;

function PathChangeExt(const S, Ext: AnsiString): AnsiString;
begin
  Result := S;
end;

function PathChangeExt(const S, Ext: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := S;
end;

function PathNative(const S: AnsiString): AnsiString;
begin
  Result := S;
end;

function PathNative(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := S;
end;

function PathNormalize(const S: AnsiString): AnsiString;
begin
  Result := S;
end;

function PathNormalize(const S: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := S;
end;

function PathExpand(const S: AnsiString): AnsiString;
begin
  Result := S;
end;

function PathExpandFrom(const S, Base: AnsiString): AnsiString;
begin
  Result := S;
end;

function PathExpandIn(const S, Cur: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := S;
end;

function PathSameName(const A, B: AnsiString): Boolean;
begin
  Result := False;
end;

function PathSameName(const A, B: AnsiString; const R: TPathRules): Boolean;
begin
  Result := False;
end;

function PathCurRoot: AnsiString;
begin
  Result := '';
end;

end.
