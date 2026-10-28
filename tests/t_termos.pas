{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/conctl.h, source/platform/conctl.cpp (the branch _TV_UNIX; the branch
  _WIN32 is not translated), include/tvision/internal/getenv.h
  See COPYRIGHT.magiblot. }
program t_termos;

{$mode objfpc}

uses
  BaseUnix, TvGeom, TvTermOs;

{$I testlib.inc}

const
  NoSuchVar = 'TVISION_TEST_VARIABLE_THAT_IS_NOT_SET';

function IntOf(const S: string; Expected: LongInt): Boolean;
var
  V: LongInt;
begin
  Result := ParseEnvInt(S, V) and (V = Expected);
end;

function NoInt(const S: string): Boolean;
var
  V: LongInt;
begin
  Result := not ParseEnvInt(S, V);
end;

procedure TestInstance;
var
  A, B, C: ConsoleCtl;
begin
  A := ConsoleCtl.GetInstance;
  B := ConsoleCtl.GetInstance;
  Check(A <> nil, 'instance exists');
  Check(A = B, 'instance is shared');
  Check(A.FdIn >= 0, 'input descriptor is valid');
  Check(A.FdOut >= 0, 'output descriptor is valid');
  A.UseDescriptors(77, 78);
  Check((A.FdIn = 77) and (A.FdOut = 78), 'descriptors replaced');
  ConsoleCtl.DestroyInstance;
  C := ConsoleCtl.GetInstance;
  Check(C <> nil, 'instance made again');
  Check(C.FdIn <> 77, 'new instance has its own descriptors');
  ConsoleCtl.DestroyInstance;
  ConsoleCtl.DestroyInstance;
  Check(ConsoleCtl.GetInstance <> nil, 'instance after a double destroy');
  ConsoleCtl.DestroyInstance;
end;

procedure TestEnv;
var
  S: string;
begin
  Check(GetEnv(NoSuchVar, 'dflt') = 'dflt', 'string default');
  Check(GetEnv(NoSuchVar) = '', 'string without default');
  Check(GetEnv(NoSuchVar, 123) = 123, 'integer default');
  Check(GetEnv(NoSuchVar, -5) = -5, 'negative integer default');
  Check(not EnvLookup(NoSuchVar, S), 'lookup of a missing variable');
  Check(not EnvLookup('', S), 'lookup of an empty name');
  Check(IntOf('42', 42), 'decimal');
  Check(IntOf('  42', 42), 'leading white space');
  Check(IntOf(#9#10'7', 7), 'tab and newline');
  Check(IntOf('-5', -5), 'minus');
  Check(IntOf('+9', 9), 'plus');
  Check(IntOf('12abc', 12), 'trailing text');
  Check(IntOf('0x1F', 31), 'hexadecimal');
  Check(IntOf('0Xff', 255), 'upper case x');
  Check(IntOf('010', 8), 'octal');
  Check(IntOf('0', 0), 'zero');
  Check(IntOf('0x', 0), 'x without digits');
  Check(IntOf('0xg', 0), 'x with a bad digit');
  Check(IntOf('089', 0), 'octal stops at 8');
  Check(IntOf('-0x10', -16), 'negative hexadecimal');
  Check(IntOf('4294967296', 0), 'wraps to int');
  Check(IntOf('2147483648', -2147483647 - 1), 'int overflow wraps');
  Check(IntOf('99999999999999999999999', -1), 'saturates to the long maximum');
  Check(NoInt(''), 'empty text');
  Check(NoInt('abc'), 'letters');
  Check(NoInt('   '), 'white space only');
  Check(NoInt('-'), 'sign only');
  Check(NoInt('+x'), 'sign and letter');
  Check(NoInt('x10'), 'x first');
end;

procedure TestWrite;
var
  Fds: TFilDes;
  Buf: array[0..4095] of AnsiChar;
  Big: array[0..3999] of AnsiChar;
  Got: TSsize;
  I: Integer;
  Same: Boolean;
  Con: ConsoleCtl;
begin
  Check(fpPipe(Fds) = 0, 'pipe made');
  Con := ConsoleCtl.GetInstance;
  Con.UseDescriptors(Fds[0], Fds[1]);
  Check((Con.FdIn = Fds[0]) and (Con.FdOut = Fds[1]), 'pipe descriptors in use');
  Con.Write(PAnsiChar('hello'), 5);
  Got := fpRead(Fds[0], PAnsiChar(@Buf[0]), SizeOf(Buf));
  Check(Got = 5, 'five bytes written');
  Check((Got = 5) and (Buf[0] = 'h') and (Buf[4] = 'o'), 'bytes arrive');
  Con.Write(PAnsiChar('abc'), 2);
  Got := fpRead(Fds[0], PAnsiChar(@Buf[0]), SizeOf(Buf));
  Check((Got = 2) and (Buf[0] = 'a') and (Buf[1] = 'b'), 'only the given count is written');
  for I := 0 to High(Big) do
    Big[I] := AnsiChar(Chr(32 + I mod 90));
  Con.Write(PAnsiChar(@Big[0]), SizeOf(Big));
  Got := fpRead(Fds[0], PAnsiChar(@Buf[0]), SizeOf(Buf));
  Check(Got = SizeOf(Big), 'long write completes');
  Same := Got = SizeOf(Big);
  for I := 0 to High(Big) do
    if Same and (Buf[I] <> Big[I]) then
      Same := False;
  Check(Same, 'long write keeps the bytes');
  Con.Write(PAnsiChar('x'), 0);
  fpClose(Fds[1]);
  Got := fpRead(Fds[0], PAnsiChar(@Buf[0]), SizeOf(Buf));
  Check(Got = 0, 'zero bytes write nothing');
  Con.UseDescriptors(Fds[0], 999);
  Con.Write(PAnsiChar('lost'), 4);
  Check(True, 'write to a bad descriptor ends');
  fpClose(Fds[0]);
  ConsoleCtl.DestroyInstance;
end;

procedure TestSizeFallback;
var
  Fds: TFilDes;
  Con: ConsoleCtl;
  P: TPoint;
begin
  Check(fpPipe(Fds) = 0, 'pipe for the size made');
  Con := ConsoleCtl.GetInstance;
  Con.UseDescriptors(Fds[0], Fds[1]);
  P := Con.GetSize;
  Check((P.X = 0) and (P.Y = 0), 'size of pipes is 0, 0');
  P := Con.GetFontSize;
  Check((P.X = 0) and (P.Y = 0), 'font size of pipes is 0, 0');
{$IFDEF LINUX}
  Check(not Con.IsLinuxConsole, 'pipes are not a Linux console');
{$ENDIF}
  Con.UseDescriptors(-1, -1);
  P := Con.GetSize;
  Check((P.X = 0) and (P.Y = 0), 'size of bad descriptors is 0, 0');
  P := Con.GetFontSize;
  Check((P.X = 0) and (P.Y = 0), 'font size of bad descriptors is 0, 0');
{$IFDEF LINUX}
  Check(not Con.IsLinuxConsole, 'bad descriptors are not a Linux console');
{$ENDIF}
  fpClose(Fds[0]);
  fpClose(Fds[1]);
  ConsoleCtl.DestroyInstance;
end;

begin
  TestInstance;
  TestEnv;
  TestWrite;
  TestSizeFallback;
  Done;
end.
