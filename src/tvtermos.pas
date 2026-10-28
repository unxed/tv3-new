{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/conctl.h, source/platform/conctl.cpp (the branch _TV_UNIX; the branch
  _WIN32 is not translated), include/tvision/internal/getenv.h
  See COPYRIGHT.magiblot. }
unit TvTermOs;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  ctypes, BaseUnix, TvGeom;

type
  ConsoleCtl = class
  private
    FFds: array[0..1] of cint;
    FOwnsFiles: Boolean;
    class var FInstance: ConsoleCtl;
    constructor Create;
    function OpenTerminal: Boolean;
    procedure CloseOwned;
  public
    destructor Destroy; override;
    { Creates the global instance if none exists, and returns it. }
    class function GetInstance: ConsoleCtl;
    { Destroys the global instance if it exists. }
    class procedure DestroyInstance;
    procedure Write(Data: PAnsiChar; Bytes: SizeUInt);
    function GetSize: TPoint;
    function GetFontSize: TPoint;
    function FdIn: cint;
    function FdOut: cint;
{$IFDEF LINUX}
    function IsLinuxConsole: Boolean;
{$ENDIF}
    { Replaces the descriptors of the instance; the descriptors that the instance opened itself are closed, and
      the new ones are not closed by the instance. }
    procedure UseDescriptors(AIn, AOut: cint);
  end;

{ getEnv<TStringView>: the value of the variable, or Def when the variable does not exist. }
function GetEnv(const Name: string; const Def: string = ''): string; overload;
{ getEnv<int>: the integer that the variable starts with (strtol with base 0), or Def when it does not exist or
  does not start with a number. }
function GetEnv(const Name: string; Def: LongInt): LongInt; overload;
{ The lookup that getenv makes: False when the variable does not exist. }
function EnvLookup(const Name: string; out Value: string): Boolean;
{ The conversion strtol(S, &end, 0) followed by the test body != end, with the result truncated to int:
  False when S has no number at its start. }
function ParseEnvInt(const S: string; out Value: LongInt): Boolean;

implementation

uses
  SysUtils, termio;

type
  TTermWinSize = record
    WsRow, WsCol, WsXPixel, WsYPixel: Word;
  end;

{$IFDEF LINUX}
const
  { Values of the Linux kernel interface (linux/kd.h and linux/tiocl.h are not among the translated sources). }
  KdFontOpIoctl = $4B72;
  KdFontOpGet = 1;
  TiocLinuxIoctl = $541C;
  TiocLinuxSubcode = 6;

type
  TConsoleFontOp = record
    FontOp, Flags, Width, Height, CharCount: cuint;
    Data: Pointer;
  end;
{$ENDIF}

const
  TtyPath = '/dev/tty';
  { FD_CLOEXEC }
  FdCloseOnExec = 1;
  IntMaxValue = 2147483647;

function MaxInt(P, Q: LongInt): LongInt;
begin
  if P > Q then
    Result := P
  else
    Result := Q;
end;

function MinInt(P, Q: LongInt): LongInt;
begin
  if P < Q then
    Result := P
  else
    Result := Q;
end;

function EnvLookup(const Name: string; out Value: string): Boolean;
var
  Index, EqPos: Integer;
  Entry: string;
begin
  Result := False;
  Value := '';
  for Index := 1 to GetEnvironmentVariableCount do
  begin
    Entry := GetEnvironmentString(Index);
    EqPos := Pos('=', Entry);
    if (EqPos > 1) and (Copy(Entry, 1, EqPos - 1) = Name) then
    begin
      Value := Copy(Entry, EqPos + 1, Length(Entry));
      Result := True;
      Exit;
    end;
  end;
end;

function DigitOf(C: Char): Integer;
const
  Symbols = '0123456789abcdefghijklmnopqrstuvwxyz';
var
  Found: Integer;
begin
  Found := Pos(LowerCase(C), Symbols);
  Result := Found - 1;
end;

function ParseEnvInt(const S: string; out Value: LongInt): Boolean;
var
  Cur, Last, Base, Digit, FirstDigit: Integer;
  Negative: Boolean;
  Limit, Acc: QWord;
  Signed: Int64;
begin
  Result := False;
  Value := 0;
  Cur := 1;
  Last := Length(S);
  while (Cur <= Last) and (S[Cur] in [' ', #9..#13]) do
    Inc(Cur);
  Negative := False;
  if (Cur <= Last) and (S[Cur] in ['+', '-']) then
  begin
    Negative := S[Cur] = '-';
    Inc(Cur);
  end;
  Base := 10;
  if (Cur <= Last) and (S[Cur] = '0') then
  begin
    Base := 8;
    if (Cur + 2 <= Last) and (S[Cur + 1] in ['x', 'X']) then
    begin
      Digit := DigitOf(S[Cur + 2]);
      if (Digit >= 0) and (Digit < 16) then
      begin
        Base := 16;
        Inc(Cur, 2);
      end;
    end;
  end;
  if Negative then
    Limit := QWord(9223372036854775808)
  else
    Limit := QWord(9223372036854775807);
  FirstDigit := Cur;
  Acc := 0;
  while Cur <= Last do
  begin
    Digit := DigitOf(S[Cur]);
    if (Digit < 0) or (Digit >= Base) then
      Break;
    if Acc > (Limit - QWord(Digit)) div QWord(Base) then
      Acc := Limit
    else
      Acc := Acc * QWord(Base) + QWord(Digit);
    Inc(Cur);
  end;
  if Cur = FirstDigit then
    Exit;
  if not Negative then
    Signed := Int64(Acc)
  else if Acc = Limit then
    Signed := Low(Int64)
  else
    Signed := -Int64(Acc);
  Value := LongInt(Cardinal(Signed and $FFFFFFFF));
  Result := True;
end;

function GetEnv(const Name: string; const Def: string): string;
begin
  if not EnvLookup(Name, Result) then
    Result := Def;
end;

function GetEnv(const Name: string; Def: LongInt): LongInt;
var
  Text: string;
begin
  Result := Def;
  if EnvLookup(Name, Text) then
    if not ParseEnvInt(Text, Result) then
      Result := Def;
end;

{ ConsoleCtl }

constructor ConsoleCtl.Create;
var
  Opened: Boolean;
begin
  inherited Create;
  FFds[0] := -1;
  FFds[1] := -1;
  FOwnsFiles := False;
  Opened := False;
  if GetEnv('TVISION_USE_STDIO', '') = '' then
    Opened := OpenTerminal;
  if not Opened then
  begin
    FFds[0] := 0;
    FFds[1] := 1;
  end;
end;

function ConsoleCtl.OpenTerminal: Boolean;
var
  ReadFd, WriteFd: cint;
begin
  Result := False;
  ReadFd := fpOpen(TtyPath, O_RDONLY);
  if ReadFd < 0 then
    Exit;
  WriteFd := fpOpen(TtyPath, O_WRONLY);
  if WriteFd < 0 then
  begin
    fpClose(ReadFd);
    Exit;
  end;
  FFds[0] := ReadFd;
  FFds[1] := WriteFd;
  FOwnsFiles := True;
  { Subprocesses must not inherit these file descriptors. }
  fpFcntl(ReadFd, F_SETFD, FdCloseOnExec);
  fpFcntl(WriteFd, F_SETFD, FdCloseOnExec);
  Result := True;
end;

procedure ConsoleCtl.CloseOwned;
var
  Index: Integer;
begin
  if FOwnsFiles then
    for Index := 0 to 1 do
      fpClose(FFds[Index]);
  FOwnsFiles := False;
end;

destructor ConsoleCtl.Destroy;
begin
  CloseOwned;
  inherited Destroy;
end;

class function ConsoleCtl.GetInstance: ConsoleCtl;
begin
  if FInstance = nil then
    FInstance := ConsoleCtl.Create;
  Result := FInstance;
end;

class procedure ConsoleCtl.DestroyInstance;
var
  Old: ConsoleCtl;
begin
  Old := FInstance;
  FInstance := nil;
  Old.Free;
end;

procedure ConsoleCtl.UseDescriptors(AIn, AOut: cint);
begin
  CloseOwned;
  FFds[0] := AIn;
  FFds[1] := AOut;
end;

function ConsoleCtl.FdIn: cint;
begin
  Result := FFds[0];
end;

function ConsoleCtl.FdOut: cint;
begin
  Result := FFds[1];
end;

procedure ConsoleCtl.Write(Data: PAnsiChar; Bytes: SizeUInt);
var
  Done: SizeUInt;
  Count: TSsize;
begin
  Done := 0;
  while Done < Bytes do
  begin
    Count := fpWrite(FFds[1], Data + Done, Bytes - Done);
    if Count < 0 then
      Break;
    Inc(Done, SizeUInt(Count));
  end;
end;

function ConsoleCtl.GetSize: TPoint;
var
  Index: Integer;
  Win: TTermWinSize;
  EnvCols, EnvRows: LongInt;
begin
  for Index := 0 to 1 do
    if fpIOCtl(FFds[Index], TIOCGWINSZ, @Win) <> -1 then
    begin
      EnvCols := GetEnv('COLUMNS', IntMaxValue);
      EnvRows := GetEnv('LINES', IntMaxValue);
      Result.X := MinInt(MaxInt(Win.WsCol, 0), MaxInt(EnvCols, 0));
      Result.Y := MinInt(MaxInt(Win.WsRow, 0), MaxInt(EnvRows, 0));
      Exit;
    end;
  Result.X := 0;
  Result.Y := 0;
end;

function ConsoleCtl.GetFontSize: TPoint;
var
  Index: Integer;
  Win: TTermWinSize;
{$IFDEF LINUX}
  Font: TConsoleFontOp;
{$ENDIF}
begin
{$IFDEF LINUX}
  FillChar(Font, SizeOf(Font), 0);
  Font.FontOp := KdFontOpGet;
  Font.Width := 32;
  Font.Height := 32;
  for Index := 0 to 1 do
    if fpIOCtl(FFds[Index], KdFontOpIoctl, @Font) <> -1 then
    begin
      Result.X := MaxInt(LongInt(Font.Width), 0);
      Result.Y := MaxInt(LongInt(Font.Height), 0);
      Exit;
    end;
{$ENDIF}
  for Index := 0 to 1 do
    if fpIOCtl(FFds[Index], TIOCGWINSZ, @Win) <> -1 then
    begin
      Result.X := Win.WsXPixel div MaxInt(Win.WsCol, 1);
      Result.Y := Win.WsYPixel div MaxInt(Win.WsRow, 1);
      Exit;
    end;
  Result.X := 0;
  Result.Y := 0;
end;

{$IFDEF LINUX}
function ConsoleCtl.IsLinuxConsole: Boolean;
var
  Index: Integer;
  Subcode: ShortInt;
begin
  { The request that reads the modifier keys of the console succeeds only on a console descriptor. }
  Result := False;
  for Index := 0 to 1 do
  begin
    Subcode := TiocLinuxSubcode;
    if fpIOCtl(FFds[Index], TiocLinuxIoctl, @Subcode) <> -1 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;
{$ENDIF}

end.
