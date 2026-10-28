{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/platform.h, source/platform/platfchr.cpp, source/platform/platform.cpp,
  source/platform/ttext.cpp, include/tvision/ttext.h
  See COPYRIGHT.magiblot.

  The character operations that depend on the C locale or on the console, and the case-insensitive comparison of
  texts. CharOps holds them; until the first use its fields are InitCharWidth and InitCharToLower, which set the
  locale of the C library, choose the functions that suit the console, replace the fields and call the chosen
  function. The comparison reads UTF-8 text and takes a byte that does not start a valid UTF-8 sequence as a
  character of the current code page. The branch for Windows is not translated. }
unit TvLocale;

{$mode objfpc}
{$R-}
{$Q-}

interface

type
  { A function that gives the number of columns of a code point, or a negative number when it has no width. }
  TCharWidthFunc = function(Wc: Cardinal): Integer;
  { A function that gives the lower case of a code point. }
  TCharToLowerFunc = function(Wc: Cardinal): Cardinal;

  { Platform::CharOps. }
  TCharOps = record
    Width: TCharWidthFunc;
    ToLower: TCharToLowerFunc;
  end;

var
  { Platform::charOps. }
  CharOps: TCharOps;

{ Sets the locale of the C library from the environment. Only the first call does it. }
procedure InitLocale;

{ Sets the locale, chooses the width function and the lower case function and stores them in CharOps. Only the
  first call does it. }
procedure InitCharOps;

{ The initial values of the fields of CharOps: each makes the choice and calls the function that was chosen. }
function InitCharWidth(Wc: Cardinal): Integer;
function InitCharToLower(Wc: Cardinal): Cardinal;

{ The width that the C library gives. }
function UnixCharWidth(Wc: Cardinal): Integer;

{$IFDEF LINUX}
{ The width on the Linux console: 1, or 2 for the characters that wcwidth of the 2007-05-26 edition by Markus Kuhn
  gives 2. The console has no zero-width characters. }
function LinuxConsoleCharWidth(Wc: Cardinal): Integer;
{$ENDIF}

{ The lower case that the C library gives for the current locale. }
function CharToLower(Wc: Cardinal): Cardinal;

{ TText::equalsIgnoreCase: compares two texts character by character with the lower case of CharOps. A byte
  that does not begin a valid UTF-8 sequence is a character of the code page of TvCodePg. }
function EqualsIgnoreCase(const A, B: string): Boolean;

implementation

uses
  ctypes, TvUtf8, TvCodePg, TvTermOs;

const
{$IFDEF LINUX}
  LcAll = 6;
{$ELSE}
  LcAll = 0;
{$ENDIF}

function LibcSetLocale(Category: cint; Locale: PAnsiChar): PAnsiChar; cdecl; external 'c' name 'setlocale';
function LibcWcWidth(Wc: cint): cint; cdecl; external 'c' name 'wcwidth';
function LibcToWLower(Wc: cuint): cuint; cdecl; external 'c' name 'towlower';

var
  { The empty name that asks setlocale for the locale of the environment. }
  EnvironmentName: AnsiChar = #0;
  LocaleDone: Boolean = False;
  OpsDone: Boolean = False;
  LocaleLock: TRTLCriticalSection;
  OpsLock: TRTLCriticalSection;

procedure InitLocale;
begin
  EnterCriticalSection(LocaleLock);
  try
    if not LocaleDone then
    begin
      LibcSetLocale(LcAll, @EnvironmentName);
      LocaleDone := True;
    end;
  finally
    LeaveCriticalSection(LocaleLock);
  end;
end;

function UnixCharWidth(Wc: Cardinal): Integer;
begin
  Result := Integer(LibcWcWidth(cint(Wc)));
end;

{$IFDEF LINUX}
function InSpan(Value, First, Last: Cardinal): Boolean;
begin
  Result := (Value >= First) and (Value <= Last);
end;

function LinuxConsoleCharWidth(Wc: Cardinal): Integer;
var
  Spans2: Boolean;
begin
  Spans2 := False;
  if Wc >= $1100 then
  begin
    Spans2 := (Wc <= $115F) or (Wc = $2329) or (Wc = $232A);
    Spans2 := Spans2 or (InSpan(Wc, $2E80, $A4CF) and (Wc <> $303F));
    Spans2 := Spans2 or InSpan(Wc, $AC00, $D7A3) or InSpan(Wc, $F900, $FAFF);
    Spans2 := Spans2 or InSpan(Wc, $FE10, $FE19) or InSpan(Wc, $FE30, $FE6F);
    Spans2 := Spans2 or InSpan(Wc, $FF00, $FF60) or InSpan(Wc, $FFE0, $FFE6);
    Spans2 := Spans2 or InSpan(Wc, $20000, $2FFFD) or InSpan(Wc, $30000, $3FFFD);
  end;
  if Spans2 then
    Result := 2
  else
    Result := 1;
end;
{$ENDIF}

function CharToLower(Wc: Cardinal): Cardinal;
begin
  { wchar_t of the supported systems has 32 bits, so every code point fits and none is skipped. }
  Result := Cardinal(LibcToWLower(cuint(Wc)));
end;

procedure InitCharOps;
var
  Chosen: TCharOps;
begin
  EnterCriticalSection(OpsLock);
  try
    if not OpsDone then
    begin
      InitLocale;
      FillChar(Chosen, SizeOf(Chosen), 0);
      Chosen.Width := @UnixCharWidth;
{$IFDEF LINUX}
      if ConsoleCtl.GetInstance.IsLinuxConsole then
        Chosen.Width := @LinuxConsoleCharWidth;
{$ENDIF}
      Chosen.ToLower := @CharToLower;
      CharOps := Chosen;
      OpsDone := True;
    end;
  finally
    LeaveCriticalSection(OpsLock);
  end;
end;

function InitCharWidth(Wc: Cardinal): Integer;
begin
  InitCharOps;
  Result := CharOps.Width(Wc);
end;

function InitCharToLower(Wc: Cardinal): Cardinal;
begin
  InitCharOps;
  Result := CharOps.ToLower(Wc);
end;

{ Reads the character that starts at the zero-based position Start of S (Pre: Start < Length(S)). The result is
  the number of bytes it takes. A valid UTF-8 sequence gives its code point. Any other byte is a byte of the code
  page, and the code point is the one of its UTF-8 translation. }
function ReadChar(const S: string; Start: SizeInt; out Wc: Cardinal): SizeInt;
var
  After: SizeInt;
  Lead: Byte;
  Bytes: TUtf8Bytes;
  Sequence: string;
  Index: Integer;
begin
  After := Start;
  TText.Next(S, After);
  Result := After - Start;
  Lead := Byte(S[Start + 1]);
  if (Result > 1) or (Lead < $80) then
  begin
    Wc := Utf8To32(Copy(S, Start + 1, Result));
    Exit;
  end;
  Bytes := CpTranslator.ToUtf8(Lead);
  Sequence := '';
  for Index := 0 to 3 do
  begin
    if Bytes[Index] = 0 then
      Break;
    Sequence := Sequence + Char(Bytes[Index]);
  end;
  Wc := Utf8To32(Sequence);
  Result := 1;
end;

function EqualsIgnoreCase(const A, B: string): Boolean;
var
  AtA, AtB: SizeInt;
  WcA, WcB: Cardinal;
  LenA, LenB: SizeInt;
begin
  AtA := 0;
  AtB := 0;
  while (AtA < Length(A)) and (AtB < Length(B)) do
  begin
    LenA := ReadChar(A, AtA, WcA);
    LenB := ReadChar(B, AtB, WcB);
    if CharOps.ToLower(WcA) <> CharOps.ToLower(WcB) then
      Break;
    Inc(AtA, LenA);
    Inc(AtB, LenB);
  end;
  Result := (AtA >= Length(A)) and (AtB >= Length(B));
end;

initialization
  InitCriticalSection(LocaleLock);
  InitCriticalSection(OpsLock);
  CharOps.Width := @InitCharWidth;
  CharOps.ToLower := @InitCharToLower;

finalization
  DoneCriticalSection(OpsLock);
  DoneCriticalSection(LocaleLock);

end.
