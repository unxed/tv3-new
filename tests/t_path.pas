{ Test program of the unit TvPath. }
program t_path;

{$mode objfpc}

uses
  SysUtils, TvPath;

{$I testlib.inc}

var
  U, D: TPathRules;

procedure CheckStr(const Got, Want, Name: string);
begin
  Check(Got = Want, Name + ' (got "' + Got + '", want "' + Want + '")');
end;

procedure CheckSplit(const S, WantDir, WantName, WantExt: string; const R: TPathRules; const Name: string);
var
  Dir, Nm, Ex: AnsiString;
begin
  PathSplit(S, Dir, Nm, Ex, R);
  CheckStr(Dir, WantDir, Name + ' dir');
  CheckStr(Nm, WantName, Name + ' name');
  CheckStr(Ex, WantExt, Name + ' ext');
  CheckStr(Dir + Nm + Ex, S, Name + ' concatenation');
  CheckStr(PathDir(S, R), WantDir, Name + ' PathDir');
  CheckStr(PathName(S, R), WantName + WantExt, Name + ' PathName');
  CheckStr(PathExt(S, R), WantExt, Name + ' PathExt');
end;

procedure CheckNorm(const S, Want: string; const R: TPathRules; const Name: string);
begin
  CheckStr(PathNormalize(S, R), Want, Name);
  CheckStr(PathNormalize(PathNormalize(S, R), R), Want, Name + ' idempotent');
end;

var
  Cwd: AnsiString;

begin
  U := UnixPathRules;
  D := DosPathRules;

  { rules }
  Check((U.Sep = '/') and (U.AltSep = #0) and not U.Drives and U.CaseSensitive, 'Unix rules');
  Check((D.Sep = '\') and (D.AltSep = '/') and D.Drives and not D.CaseSensitive, 'DOS rules');
  CheckStr(U.AllFiles, '*', 'Unix all files');
  CheckStr(D.AllFiles, '*.*', 'DOS all files');
  Check((U.ListSep = ':') and (D.ListSep = ';'), 'list separators');

  { native forms }
  Check(PathSep = '/', 'PathSep');
  Check(not PathHasDrives, 'PathHasDrives');
  Check(PathAllFiles = '*', 'PathAllFiles');
  Check(PathSep = NativePathRules.Sep, 'PathSep equals native Sep');
  Check(PathAllFiles = NativePathRules.AllFiles, 'PathAllFiles equals native AllFiles');
  Check(NativePathRules.Drives = PathHasDrives, 'PathHasDrives equals native Drives');

  { IsPathSep, EndsWithSep }
  Check(IsPathSep('/', U), 'slash is a separator on Unix');
  Check(not IsPathSep('\', U), 'backslash is no separator on Unix');
  Check(IsPathSep('/', D) and IsPathSep('\', D), 'both separators on DOS');
  Check(not IsPathSep('a', D), 'letter is no separator');
  Check(IsPathSep('/') and not IsPathSep('\'), 'native IsPathSep');
  Check(EndsWithSep('a/', U), 'EndsWithSep a/');
  Check(not EndsWithSep('a\', U), 'EndsWithSep a\ on Unix');
  Check(EndsWithSep('a\', D), 'EndsWithSep a\ on DOS');
  Check(not EndsWithSep('', U), 'EndsWithSep empty');
  Check(EndsWithSep('a/') and not EndsWithSep('a'), 'native EndsWithSep');

  { PathDrive }
  CheckStr(PathDrive('C:\x', U), '', 'Unix drive');
  CheckStr(PathDrive('c:\x', D), 'c:', 'letter drive');
  CheckStr(PathDrive('\\srv\share\x', D), '\\srv\share', 'UNC drive');
  CheckStr(PathDrive('\\srv', D), '\\srv', 'UNC server only');
  CheckStr(PathDrive('\\srv\sh', D), '\\srv\sh', 'UNC without tail');
  CheckStr(PathDrive('\\\x', D), '', 'three separators have no drive');
  CheckStr(PathDrive('//srv/sh/x', D), '//srv/sh', 'UNC with slashes');
  CheckStr(PathDrive('a', D), '', 'one character');
  CheckStr(PathDrive('1:x', D), '', 'digit is no drive');
  CheckStr(PathDrive('C:\x'), '', 'native drive');

  { PathRootLen }
  Check(PathRootLen('/a', U) = 1, 'root length /a');
  Check(PathRootLen('a', U) = 0, 'root length a');
  Check(PathRootLen('', U) = 0, 'root length empty');
  Check(PathRootLen('C:\a', D) = 3, 'root length C:\a');
  Check(PathRootLen('C:a', D) = 2, 'root length C:a');
  Check(PathRootLen('\\srv\sh\a', D) = 9, 'root length UNC with tail');
  Check(PathRootLen('\\srv\sh', D) = 8, 'root length UNC');
  Check(PathRootLen('\a', D) = 1, 'root length \a');
  Check(PathRootLen('/a') = 1, 'native root length');

  { PathIsRooted }
  Check(PathIsRooted('/a', U), 'rooted /a');
  Check(not PathIsRooted('a/b', U), 'rooted a/b');
  Check(not PathIsRooted('C:\a', U), 'rooted C:\a on Unix');
  Check(PathIsRooted('\a', D), 'DOS rooted \a');
  Check(PathIsRooted('/a', D), 'DOS rooted /a');
  Check(PathIsRooted('C:\a', D), 'DOS rooted C:\a');
  Check(not PathIsRooted('C:a', D), 'DOS rooted C:a');
  Check(not PathIsRooted('C:', D), 'DOS rooted C:');
  Check(PathIsRooted('\\srv', D), 'DOS rooted UNC server');
  Check(PathIsRooted('/a') and not PathIsRooted('a'), 'native rooted');

  { PathIsAbsolute }
  Check(not PathIsAbsolute('\a', U), 'Unix absolute \a');
  Check(PathIsAbsolute('/a', U), 'Unix absolute /a');
  Check(PathIsAbsolute('C:\a', D), 'DOS absolute C:\a');
  Check(PathIsAbsolute('\\srv\sh\a', D), 'DOS absolute UNC');
  Check(PathIsAbsolute('\\srv\sh', D), 'DOS absolute UNC share');
  Check(not PathIsAbsolute('\a', D), 'DOS absolute \a');
  Check(not PathIsAbsolute('C:a', D), 'DOS absolute C:a');
  Check(not PathIsAbsolute('a', D), 'DOS absolute a');
  Check(PathIsAbsolute('/a') and not PathIsAbsolute('a'), 'native absolute');

  { PathIsRoot }
  Check(PathIsRoot('/', U), 'root /');
  Check(not PathIsRoot('/a', U), 'root /a');
  Check(not PathIsRoot('', U), 'root empty');
  Check(not PathIsRoot('C:\', U), 'root C:\ on Unix');
  Check(not PathIsRoot('//', U), 'root //');
  Check(PathIsRoot('C:\', D), 'DOS root C:\');
  Check(PathIsRoot('\', D), 'DOS root \');
  Check(PathIsRoot('\\srv\sh\', D), 'DOS root UNC');
  Check(not PathIsRoot('C:', D), 'DOS root C:');
  Check(PathIsRoot('/') and not PathIsRoot('/a'), 'native root');

  { PathAddSep }
  CheckStr(PathAddSep('a', U), 'a/', 'add Unix');
  CheckStr(PathAddSep('a', D), 'a\', 'add DOS');
  CheckStr(PathAddSep('/', U), '/', 'add after root');
  CheckStr(PathAddSep('', U), '', 'add to empty');
  CheckStr(PathAddSep('C:', D), 'C:', 'add to bare drive');
  CheckStr(PathAddSep('a\', U), 'a\/', 'add after backslash on Unix');
  CheckStr(PathAddSep('a/', D), 'a/', 'add after slash on DOS');
  CheckStr(PathAddSep('\\srv', D), '\\srv\', 'add to UNC drive');
  CheckStr(PathAddSep('a'), 'a/', 'native add');

  { PathDelSep }
  CheckStr(PathDelSep('/a/', U), '/a', 'del /a/');
  CheckStr(PathDelSep('/', U), '/', 'del /');
  CheckStr(PathDelSep('a//', U), 'a', 'del a//');
  CheckStr(PathDelSep('', U), '', 'del empty');
  CheckStr(PathDelSep('C:\', D), 'C:\', 'del C:\');
  CheckStr(PathDelSep('C:\a\', D), 'C:\a', 'del C:\a\');
  CheckStr(PathDelSep('\', D), '\', 'del DOS \');
  CheckStr(PathDelSep('a/', D), 'a', 'del DOS a/');
  CheckStr(PathDelSep('/a/'), '/a', 'native del');

  { PathJoin }
  CheckStr(PathJoin('/a', 'b', U), '/a/b', 'join /a b');
  CheckStr(PathJoin('/a/', 'b', U), '/a/b', 'join /a/ b');
  CheckStr(PathJoin('/a', '/b', U), '/b', 'join rooted name');
  CheckStr(PathJoin('', 'b', U), 'b', 'join empty dir');
  CheckStr(PathJoin('/a', '', U), '/a', 'join empty name');
  CheckStr(PathJoin('/a', 'C:x', U), '/a/C:x', 'join drive-like name on Unix');
  CheckStr(PathJoin('C:\a', 'b', D), 'C:\a\b', 'join DOS');
  CheckStr(PathJoin('C:', 'b', D), 'C:b', 'join bare drive');
  CheckStr(PathJoin('C:\a', 'D:x', D), 'D:x', 'join name with drive');
  CheckStr(PathJoin('/a', 'b'), '/a/b', 'native join');

  { PathSplit and friends }
  CheckSplit('/a/b/file.name.ext', '/a/b/', 'file.name', '.ext', U, 'split 1');
  CheckSplit('file', '', 'file', '', U, 'split 2');
  CheckSplit('/a/b/', '/a/b/', '', '', U, 'split 3');
  CheckSplit('/a/.profile', '/a/', '.profile', '', U, 'split 4');
  CheckSplit('/a/.x.conf', '/a/', '.x', '.conf', U, 'split 5');
  CheckSplit('..', '', '..', '', U, 'split 6');
  CheckSplit('.', '', '.', '', U, 'split dot');
  CheckSplit('a\b.txt', '', 'a\b', '.txt', U, 'split 7');
  CheckSplit('C:\a\b.txt', '', 'C:\a\b', '.txt', U, 'split 8');
  CheckSplit('a.', '', 'a', '.', U, 'split trailing dot');
  CheckSplit('', '', '', '', U, 'split empty');
  CheckSplit('c:\dir\sub\file.name.ext', 'c:\dir\sub\', 'file.name', '.ext', D, 'split DOS 1');
  CheckSplit('c:file.txt', 'c:', 'file', '.txt', D, 'split DOS 2');
  CheckSplit('c:/a/b.txt', 'c:/a/', 'b', '.txt', D, 'split DOS 3');
  CheckSplit('\\srv\sh\x.c', '\\srv\sh\', 'x', '.c', D, 'split DOS UNC');
  CheckSplit('\\srv\sh', '\\srv\sh', '', '', D, 'split DOS UNC share');
  CheckStr(PathDir('/a/b', U), '/a/', 'dir /a/b');
  CheckStr(PathName('/a/b.c', U), 'b.c', 'name /a/b.c');
  CheckStr(PathExt('/a.d/b', U), '', 'ext /a.d/b');
  CheckStr(PathExt('C:\a.d\b.PAS', D), '.PAS', 'ext keeps case');
  CheckStr(PathChangeExt('/a.d/b.txt', '.bak', U), '/a.d/b.bak', 'change ext 1');
  CheckStr(PathChangeExt('/a.d/b', '.bak', U), '/a.d/b.bak', 'change ext 2');
  CheckStr(PathChangeExt('/a/.profile', '.bak', U), '/a/.profile.bak', 'change ext 3');
  CheckStr(PathChangeExt('a.b\c', '.x', U), 'a.x', 'change ext Unix backslash');
  CheckStr(PathChangeExt('a.b\c', '.x', D), 'a.b\c.x', 'change ext DOS backslash');
  CheckStr(PathChangeExt('C:\a\b.txt', '', D), 'C:\a\b', 'remove ext');
  CheckStr(PathDir('/a/b'), '/a/', 'native dir');
  CheckStr(PathChangeExt('/a/b.txt', '.c'), '/a/b.c', 'native change ext');

  { PathNative }
  CheckStr(PathNative('a/b\c', U), 'a/b\c', 'native conversion Unix');
  CheckStr(PathNative('a/b\c', D), 'a\b\c', 'native conversion DOS');
  CheckStr(PathNative('a/b\c'), 'a/b\c', 'native conversion of the system');

  { PathNormalize }
  CheckNorm('/a//b/./c/../d/', '/a/b/d/', U, 'norm 1');
  CheckNorm('/../a', '/a', U, 'norm 2');
  CheckNorm('../a/..', '..', U, 'norm 3');
  CheckNorm('a/..', '.', U, 'norm 4');
  CheckNorm('/a\b/../c', '/c', U, 'norm 5');
  CheckNorm('a/../', '.', U, 'norm trailing separator');
  CheckNorm('../../a', '../../a', U, 'norm leading parents');
  CheckNorm('/', '/', U, 'norm root');
  CheckNorm('C:/a/../b', 'C:\b', D, 'norm DOS 1');
  CheckNorm('\\srv\sh\a\..\..\b', '\\srv\sh\b', D, 'norm DOS 2');
  CheckNorm('C:\', 'C:\', D, 'norm DOS 3');
  CheckNorm('C:..\x', 'C:..\x', D, 'norm drive relative');
  CheckStr(PathNormalize('', U), '', 'norm empty');
  CheckStr(PathNormalize('', D), '', 'norm empty DOS');
  CheckStr(PathNormalize('/a/./b'), '/a/b', 'norm native');

  { PathExpandIn }
  CheckStr(PathExpandIn('b', '/home/u', U), '/home/u/b', 'expand 1');
  CheckStr(PathExpandIn('../b/', '/home/u', U), '/home/b/', 'expand 2');
  CheckStr(PathExpandIn('/x', '/home/u', U), '/x', 'expand 3');
  CheckStr(PathExpandIn('C:\x', '/home/u', U), '/home/u/C:\x', 'expand 4');
  CheckStr(PathExpandIn('b', '/', U), '/b', 'expand from root');
  CheckStr(PathExpandIn('b', 'C:\a', D), 'C:\a\b', 'expand DOS 1');
  CheckStr(PathExpandIn('\b', 'C:\a', D), 'C:\b', 'expand DOS 2');
  CheckStr(PathExpandIn('c:b', 'C:\a', D), 'C:\a\b', 'expand DOS 3');
  CheckStr(PathExpandIn('D:b', 'C:\a', D), 'D:\b', 'expand DOS 4');
  CheckStr(PathExpandIn('d/e', '\\srv\sh\a', D), '\\srv\sh\a\d\e', 'expand DOS UNC');
  CheckStr(PathExpandIn('D:\b\..\c', 'C:\a', D), 'D:\c', 'expand DOS absolute');

  { PathSameName }
  Check(not PathSameName('A.txt', 'a.txt', U), 'same name Unix');
  Check(PathSameName('A.txt', 'a.txt', D), 'same name DOS');
  Check(PathSameName('a', 'a', U), 'same name equal');
  Check(not PathSameName('a', 'a/', D), 'same name does not normalise');
  Check(not PathSameName('A.txt', 'a.txt'), 'native same name');

  { the current directory }
  Cwd := GetCurrentDir;
  Check(PathIsAbsolute(Cwd), 'current directory is absolute');
  CheckStr(PathExpand('x'), PathJoin(Cwd, 'x'), 'expand x');
  CheckStr(PathExpand('a/../x'), PathJoin(Cwd, 'x'), 'expand a/../x');
  CheckStr(PathExpand('a\b'), PathAddSep(Cwd) + 'a\b', 'expand a\b');
  CheckStr(PathExpand(''), PathAddSep(Cwd), 'expand empty');
  CheckStr(PathExpand('/x'), '/x', 'expand rooted');
  CheckStr(PathExpandFrom('x', 'sub'), PathJoin(PathJoin(Cwd, 'sub'), 'x'), 'expand from sub');
  CheckStr(PathExpandFrom('/x', 'sub'), '/x', 'expand from with rooted name');
  CheckStr(PathExpandFrom('x', ''), PathJoin(Cwd, 'x'), 'expand from empty base');
  Check(PathIsRoot(PathCurRoot), 'current root is a root');
  Check(Copy(Cwd, 1, Length(PathCurRoot)) = PathCurRoot, 'current directory begins with the root');
  CheckStr(PathExpand(PathCurRoot), PathCurRoot, 'expand of the current root');
  Check(Pos(':', PathCurRoot) = 0, 'current root has no colon');
  CheckStr(PathCurRoot, '/', 'current root on Unix');

  Done;
end.
