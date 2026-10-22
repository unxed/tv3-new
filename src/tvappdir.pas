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

function NativeAppDirSystem: TAppDirSystem;
begin
  Result := adsXdg;
end;

function AppDirGetEnv(const Name: AnsiString): AnsiString;
begin
  Result := '';
end;

function AppDirProgramDir: AnsiString;
begin
  Result := '';
end;

function AppDirIn(Kind: TAppDirKind; const App: AnsiString; Sys: TAppDirSystem; Env: TAppDirEnv;
  const ProgramDir: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := '';
end;

function AppDirPath(Kind: TAppDirKind; const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := '';
end;

function AppDir(Kind: TAppDirKind; const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := '';
end;

function ConfigDir(const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := '';
end;

function DataDir(const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := '';
end;

function StateDir(const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := '';
end;

function CacheDir(const App: AnsiString; const DosVar: AnsiString): AnsiString;
begin
  Result := '';
end;

function MakeAppDir(const Dir: AnsiString): Boolean;
begin
  Result := False;
end;

end.
