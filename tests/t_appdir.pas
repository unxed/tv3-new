{ Test program of the unit TvAppDir. }
program t_appdir;

{$mode objfpc}

uses
  SysUtils, Classes, BaseUnix, TvPath, TvAppDir;

{$I testlib.inc}

type
  TPCharList = array[0..65535] of PChar;
  PPCharList = ^TPCharList;

var
  Fake: TStringList;

procedure CheckStr(const Got, Want, Name: string);
begin
  Check(Got = Want, Name + ' (got "' + Got + '", want "' + Want + '")');
end;

{ Sets the fake environment from name/value pairs. }
procedure SetFake(const Pairs: array of string);
var
  I: Integer;
begin
  Fake.Clear;
  for I := 0 to Length(Pairs) div 2 - 1 do
    Fake.Add(Pairs[2 * I] + '=' + Pairs[2 * I + 1]);
end;

function FakeEnv(const Name: AnsiString): AnsiString;
begin
  Result := Fake.Values[Name];
end;

function Calc(Kind: TAppDirKind; Sys: TAppDirSystem): AnsiString;
begin
  Result := AppDirIn(Kind, 'app', Sys, @FakeEnv, 'C:\PROG', 'APPDIR');
end;

procedure CheckAll(Sys: TAppDirSystem; const WantConfig, WantData, WantState, WantCache, Name: string);
begin
  CheckStr(Calc(adConfig, Sys), WantConfig, Name + ' config');
  CheckStr(Calc(adData, Sys), WantData, Name + ' data');
  CheckStr(Calc(adState, Sys), WantState, Name + ' state');
  CheckStr(Calc(adCache, Sys), WantCache, Name + ' cache');
end;

{ Changes a variable of the process environment by replacing the environment table of the program. }
procedure SetProcEnv(const Name, Value: AnsiString);
var
  Old, Fresh: PPCharList;
  Count, I, Used: Integer;
  Prefix: AnsiString;
begin
  Prefix := Name + '=';
  Old := PPCharList(envp);
  Count := 0;
  while (Old <> nil) and (Old^[Count] <> nil) do
    Inc(Count);
  GetMem(Fresh, (Count + 2) * SizeOf(PChar));
  Used := 0;
  for I := 0 to Count - 1 do
    if StrLComp(Old^[I], PChar(Prefix), Length(Prefix)) <> 0 then
    begin
      Fresh^[Used] := Old^[I];
      Inc(Used);
    end;
  if Value <> '' then
  begin
    Fresh^[Used] := StrNew(PChar(Prefix + Value));
    Inc(Used);
  end;
  Fresh^[Used] := nil;
  envp := PPChar(Fresh);
end;

function ModeOf(const Path: AnsiString): Integer;
var
  St: Stat;
begin
  if fpStat(Path, St) <> 0 then
    Result := -1
  else
    Result := St.st_mode and &777;
end;

procedure MakeFile(const Path: AnsiString);
begin
  FileClose(FileCreate(Path));
end;

var
  Tmp, A, B, F, Home, Xdg, Got: AnsiString;
  Prog: AnsiString;

begin
  Fake := TStringList.Create;
  { XDG }
  SetFake(['HOME', '/home/u']);
  CheckAll(adsXdg, '/home/u/.config/app', '/home/u/.local/share/app', '/home/u/.local/state/app',
    '/home/u/.cache/app', 'XDG home');
  SetFake(['HOME', '/home/u/']);
  CheckAll(adsXdg, '/home/u/.config/app', '/home/u/.local/share/app', '/home/u/.local/state/app',
    '/home/u/.cache/app', 'XDG home with separator');
  SetFake(['XDG_CONFIG_HOME', '/c', 'XDG_DATA_HOME', '/d/', 'XDG_STATE_HOME', '/s', 'XDG_CACHE_HOME', '/k']);
  CheckAll(adsXdg, '/c/app', '/d/app', '/s/app', '/k/app', 'XDG variables');
  SetFake(['XDG_CONFIG_HOME', 'rel/c', 'XDG_STATE_HOME', './s', 'HOME', '/home/u']);
  CheckStr(Calc(adConfig, adsXdg), '/home/u/.config/app', 'XDG relative config variable');
  CheckStr(Calc(adState, adsXdg), '/home/u/.local/state/app', 'XDG relative state variable');
  SetFake([]);
  CheckAll(adsXdg, '', '', '', '', 'XDG empty environment');
  SetFake(['XDG_CACHE_HOME', '/k']);
  CheckStr(Calc(adCache, adsXdg), '/k/app', 'XDG cache variable without HOME');
  CheckStr(Calc(adConfig, adsXdg), '', 'XDG other kind without HOME');
  SetFake(['HOME', 'home']);
  CheckStr(Calc(adConfig, adsXdg), '', 'XDG relative HOME');
  SetFake(['HOME', '/home/u', 'XDG_DATA_HOME', '']);
  CheckStr(Calc(adData, adsXdg), '/home/u/.local/share/app', 'XDG empty variable');
  SetFake(['HOME', '/home/u']);
  CheckStr(AppDirIn(adConfig, '', adsXdg, @FakeEnv, '', ''), '/home/u/.config', 'XDG empty App');

  { macOS }
  SetFake(['HOME', '/Users/u', 'XDG_CONFIG_HOME', '/c']);
  CheckAll(adsMac, '/Users/u/Library/Application Support/app', '/Users/u/Library/Application Support/app',
    '/Users/u/Library/Application Support/app', '/Users/u/Library/Caches/app', 'macOS');
  SetFake([]);
  CheckAll(adsMac, '', '', '', '', 'macOS empty environment');
  SetFake(['XDG_CONFIG_HOME', '/c']);
  CheckStr(Calc(adConfig, adsMac), '', 'macOS without HOME');

  { Windows }
  SetFake(['APPDATA', 'C:\Users\u\AppData\Roaming', 'LOCALAPPDATA', 'C:\Users\u\AppData\Local\']);
  CheckAll(adsWindows, 'C:\Users\u\AppData\Roaming\app', 'C:\Users\u\AppData\Roaming\app',
    'C:\Users\u\AppData\Local\app', 'C:\Users\u\AppData\Local\app', 'Windows');
  SetFake(['APPDATA', 'C:\Users\u\AppData\Roaming', 'LOCALAPPDATA', '']);
  CheckStr(Calc(adCache, adsWindows), 'C:\Users\u\AppData\Roaming\app', 'Windows empty LOCALAPPDATA');
  SetFake(['APPDATA', 'C:\Users\u\AppData\Roaming', 'LOCALAPPDATA', 'Local']);
  CheckStr(Calc(adState, adsWindows), 'C:\Users\u\AppData\Roaming\app', 'Windows relative LOCALAPPDATA');
  SetFake(['APPDATA', '\\srv\home\u']);
  CheckStr(Calc(adConfig, adsWindows), '\\srv\home\u\app', 'Windows UNC');
  SetFake(['LOCALAPPDATA', 'C:\L']);
  CheckStr(Calc(adConfig, adsWindows), '', 'Windows config without APPDATA');
  SetFake([]);
  CheckAll(adsWindows, '', '', '', '', 'Windows empty environment');

  { DOS }
  SetFake([]);
  CheckAll(adsDos, 'C:\PROG', 'C:\PROG', 'C:\PROG', 'C:\PROG', 'DOS variable unset');
  SetFake(['APPDIR', 'D:\CFG\']);
  CheckAll(adsDos, 'D:\CFG', 'D:\CFG', 'D:\CFG', 'D:\CFG', 'DOS variable');
  SetFake(['APPDIR', 'D:\CFG\']);
  CheckStr(AppDirIn(adConfig, 'app', adsDos, @FakeEnv, 'C:\PROG\', ''), 'C:\PROG', 'DOS without variable name');
  CheckStr(AppDirIn(adData, 'app', adsDos, @FakeEnv, '', ''), '', 'DOS nothing known');

  { the native system }
  Check(NativeAppDirSystem = adsXdg, 'native system on Linux');
  CheckStr(AppDirPath(adConfig, 'app'), AppDirIn(adConfig, 'app', NativeAppDirSystem, @AppDirGetEnv, AppDirProgramDir),
    'AppDirPath equals AppDirIn');
  CheckStr(AppDirPath(adCache, 'app'), AppDirIn(adCache, 'app', adsXdg, @AppDirGetEnv, ''), 'AppDirPath cache');
  Prog := AppDirProgramDir;
  Check(Prog <> '', 'program directory is not empty');
  Check(PathIsAbsolute(Prog), 'program directory is absolute');
  Check(PathIsRoot(Prog) or not EndsWithSep(Prog), 'program directory has no trailing separator');

  { MakeAppDir }
  Tmp := PathJoin(PathDelSep(GetTempDir(False)), 't_appdir_' + IntToStr(GetProcessID));
  A := PathJoin(Tmp, 'a');
  B := PathJoin(A, 'b');
  Check(not DirectoryExists(Tmp), 'temporary directory is fresh');
  Check(MakeAppDir(B), 'MakeAppDir two levels');
  Check(DirectoryExists(B), 'two levels exist');
  Check(MakeAppDir(B), 'MakeAppDir again');
  Check(MakeAppDir(B + '/'), 'MakeAppDir with trailing separator');
  Check(ModeOf(B) = &700, 'mode of the last level');
  Check(ModeOf(A) = &700, 'mode of the middle level');
  Check(ModeOf(Tmp) = &700, 'mode of the first level');
  Check(not MakeAppDir(''), 'MakeAppDir empty');
  F := PathJoin(Tmp, 'file');
  MakeFile(F);
  Check(not MakeAppDir(F), 'MakeAppDir on a regular file');
  Check(not MakeAppDir(PathJoin(F, 'sub')), 'MakeAppDir below a regular file');
  Check(not MakeAppDir(PathJoin(PathJoin(F, 'x'), 'y')), 'MakeAppDir two levels below a regular file');

  { AppDir and the wrappers with the environment of the process }
  Home := PathJoin(Tmp, 'home');
  Xdg := PathJoin(Tmp, 'xdg');
  SetProcEnv('HOME', Home);
  SetProcEnv('XDG_CONFIG_HOME', Xdg);
  SetProcEnv('XDG_DATA_HOME', '');
  SetProcEnv('XDG_STATE_HOME', '');
  SetProcEnv('XDG_CACHE_HOME', '');
  CheckStr(AppDirGetEnv('HOME'), Home, 'process HOME');
  Got := ConfigDir('app');
  CheckStr(Got, PathJoin(Xdg, 'app'), 'ConfigDir');
  Check(DirectoryExists(Got), 'ConfigDir creates the directory');
  Check(ModeOf(Got) = &700, 'mode of the configuration directory');
  CheckStr(Got, AppDirPath(adConfig, 'app'), 'ConfigDir equals AppDirPath');
  CheckStr(DataDir('app'), PathJoin(Home, '.local/share/app'), 'DataDir');
  Check(DirectoryExists(PathJoin(Home, '.local/share/app')), 'DataDir creates the directory');
  CheckStr(StateDir('app'), PathJoin(Home, '.local/state/app'), 'StateDir');
  CheckStr(CacheDir('app'), PathJoin(Home, '.cache/app'), 'CacheDir');
  CheckStr(AppDir(adCache, 'other'), PathJoin(Home, '.cache/other'), 'AppDir');
  Check(DirectoryExists(PathJoin(Home, '.cache/other')), 'AppDir creates the directory');
  SetProcEnv('XDG_CONFIG_HOME', PathJoin(F, 'sub'));
  CheckStr(ConfigDir('app'), '', 'ConfigDir below a regular file');
  Check(AppDirPath(adConfig, 'app') <> '', 'AppDirPath does not depend on the creation');
  SetProcEnv('XDG_CONFIG_HOME', '');
  SetProcEnv('HOME', '');
  CheckStr(ConfigDir('app'), '', 'ConfigDir without HOME');

  { remove the test directories }
  fpRmdir(PathJoin(Xdg, 'app'));
  fpRmdir(Xdg);
  fpRmdir(PathJoin(Home, '.local/share/app'));
  fpRmdir(PathJoin(Home, '.local/share'));
  fpRmdir(PathJoin(Home, '.local/state/app'));
  fpRmdir(PathJoin(Home, '.local/state'));
  fpRmdir(PathJoin(Home, '.local'));
  fpRmdir(PathJoin(Home, '.cache/app'));
  fpRmdir(PathJoin(Home, '.cache/other'));
  fpRmdir(PathJoin(Home, '.cache'));
  fpRmdir(Home);
  DeleteFile(F);
  fpRmdir(B);
  fpRmdir(A);
  fpRmdir(Tmp);
  Check(not DirectoryExists(Tmp), 'test directories removed');

  Done;
end.
