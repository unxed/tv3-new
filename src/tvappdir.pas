{ Tells where a program keeps the files of the user (configuration, data, state, caches) by the convention of a system
  (XDG, macOS, Windows, DOS) and creates the directory. The native system is a Unix one: the Windows and DOS routes of
  the native system and the creation of a directory on another system are left out. }
unit TvAppDir;

{$mode objfpc}
{$R-}
{$Q-}

interface

type
  TAppDirKind = (adConfig, adData, adState, adCache);
  TAppDirSystem = (adsXdg, adsMac, adsWindows, adsDos);
  { The value of an environment variable ('' when it is not set). }
  TAppDirEnv = function(const Name: AnsiString): AnsiString;

function NativeAppDirSystem: TAppDirSystem;
function AppDirGetEnv(const Name: AnsiString): AnsiString;
function AppDirProgramDir: AnsiString;

function AppDirIn(Kind: TAppDirKind; const App: AnsiString; Sys: TAppDirSystem; Env: TAppDirEnv;
  const ProgramDir: AnsiString; const DosVar: AnsiString = ''): AnsiString;
function AppDirPath(Kind: TAppDirKind; const App: AnsiString; const DosVar: AnsiString = ''): AnsiString;
function AppDir(Kind: TAppDirKind; const App: AnsiString; const DosVar: AnsiString = ''): AnsiString;

function ConfigDir(const App: AnsiString; const DosVar: AnsiString = ''): AnsiString;
function DataDir(const App: AnsiString; const DosVar: AnsiString = ''): AnsiString;
function StateDir(const App: AnsiString; const DosVar: AnsiString = ''): AnsiString;
function CacheDir(const App: AnsiString; const DosVar: AnsiString = ''): AnsiString;

function MakeAppDir(const Dir: AnsiString): Boolean;

implementation

uses
  SysUtils, BaseUnix, TvPath;

function NativeAppDirSystem: TAppDirSystem;
begin
{$IFDEF DARWIN}
  Result := adsMac;
{$ELSE}
  Result := adsXdg;
{$ENDIF}
end;

function AppDirGetEnv(const Name: AnsiString): AnsiString;
begin
  Result := GetEnvironmentVariable(Name);
end;

function AppDirProgramDir: AnsiString;
begin
  Result := PathDelSep(PathDir(PathExpand(ParamStr(0))));
end;

function Lookup(Env: TAppDirEnv; const Name: AnsiString): AnsiString;
begin
  if Assigned(Env) then
    Result := Env(Name)
  else
    Result := '';
end;

{ The value of the variable when it is an absolute path by the rules R, otherwise ''. }
function Usable(Env: TAppDirEnv; const Name: AnsiString; const R: TPathRules): AnsiString;
begin
  Result := Lookup(Env, Name);
  if not PathIsAbsolute(Result, R) then
    Result := '';
end;

function XdgBase(Kind: TAppDirKind; Env: TAppDirEnv): AnsiString;
const
  VarNames: array[TAppDirKind] of AnsiString = ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME');
  HomeParts: array[TAppDirKind] of AnsiString = ('.config', '.local/share', '.local/state', '.cache');
var
  Home: AnsiString;
begin
  Result := Usable(Env, VarNames[Kind], UnixPathRules);
  if Result = '' then
  begin
    Home := Usable(Env, 'HOME', UnixPathRules);
    if Home <> '' then
      Result := PathJoin(Home, HomeParts[Kind], UnixPathRules);
  end;
end;

function MacBase(Kind: TAppDirKind; Env: TAppDirEnv): AnsiString;
var
  Home: AnsiString;
begin
  Result := '';
  Home := Usable(Env, 'HOME', UnixPathRules);
  if Home = '' then
    Exit;
  if Kind = adCache then
    Result := PathJoin(Home, 'Library/Caches', UnixPathRules)
  else
    Result := PathJoin(Home, 'Library/Application Support', UnixPathRules);
end;

function WindowsBase(Kind: TAppDirKind; Env: TAppDirEnv): AnsiString;
begin
  Result := '';
  if Kind in [adState, adCache] then
    Result := Usable(Env, 'LOCALAPPDATA', DosPathRules);
  if Result = '' then
    Result := Usable(Env, 'APPDATA', DosPathRules);
end;

function AppDirIn(Kind: TAppDirKind; const App: AnsiString; Sys: TAppDirSystem; Env: TAppDirEnv;
  const ProgramDir: AnsiString; const DosVar: AnsiString): AnsiString;
var
  Base: AnsiString;
begin
  Result := '';
  case Sys of
    adsXdg, adsMac:
      begin
        if Sys = adsXdg then
          Base := XdgBase(Kind, Env)
        else
          Base := MacBase(Kind, Env);
        if Base <> '' then
          Result := PathDelSep(PathJoin(Base, App, UnixPathRules), UnixPathRules);
      end;
    adsWindows:
      begin
        Base := WindowsBase(Kind, Env);
        if Base <> '' then
          Result := PathDelSep(PathJoin(Base, App, DosPathRules), DosPathRules);
      end;
    adsDos:
      begin
        if DosVar <> '' then
          Base := Lookup(Env, DosVar)
        else
          Base := '';
        if Base = '' then
          Base := ProgramDir;
        Result := PathDelSep(Base, DosPathRules);
      end;
  end;
end;

function AppDirPath(Kind: TAppDirKind; const App: AnsiString; const DosVar: AnsiString): AnsiString;
var
  Sys: TAppDirSystem;
  ProgDir: AnsiString;
begin
  Sys := NativeAppDirSystem;
  if Sys = adsDos then
    ProgDir := AppDirProgramDir
  else
    ProgDir := '';
  Result := AppDirIn(Kind, App, Sys, @AppDirGetEnv, ProgDir, DosVar);
end;

function AppDir(Kind: TAppDirKind; const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := AppDirPath(Kind, App, DosVar);
  if (Result <> '') and not MakeAppDir(Result) then
    Result := '';
end;

function ConfigDir(const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := AppDir(adConfig, App, DosVar);
end;

function DataDir(const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := AppDir(adData, App, DosVar);
end;

function StateDir(const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := AppDir(adState, App, DosVar);
end;

function CacheDir(const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := AppDir(adCache, App, DosVar);
end;

function MakeAppDir(const Dir: AnsiString): Boolean;
var
  Parent: AnsiString;
begin
  Result := False;
  if Dir = '' then
    Exit;
  if DirectoryExists(Dir) then
  begin
    Result := True;
    Exit;
  end;
  Parent := PathDelSep(PathDir(PathDelSep(Dir)));
  if (Parent <> '') and (Parent <> Dir) and not PathIsRoot(Parent) and not DirectoryExists(Parent) then
    if not MakeAppDir(Parent) then
      Exit;
  Result := (fpMkdir(Dir, S_IRWXU) = 0) or DirectoryExists(Dir);
end;

end.
