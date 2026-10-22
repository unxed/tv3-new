{ Test program of the unit TvTermOsBase. }
program t_termosbase;

{$mode objfpc}

uses
  TvTermOsBase;

{$I testlib.inc}

var
  HookCalls: Integer = 0;
  LastArg: LongInt = 0;

procedure CountHook;
begin
  Inc(HookCalls);
end;

procedure SetFlagHook;
begin
  OsResizeFlag := 1;
end;

procedure Writer;
begin
  TvTermOsBase.OsResizeFlag := 42;
  TvTermOsBase.OsToldCols := 132;
  TvTermOsBase.OsToldRows := 50;
end;

function ReaderSum: LongInt;
begin
  Result := TvTermOsBase.OsResizeFlag + TvTermOsBase.OsToldCols + TvTermOsBase.OsToldRows;
end;

var
  Hook, Other: TOsHook;
  Hooks: array[0..1] of TOsHook;
  PFlag: PLongInt;
  I: Integer;
  AllSet: Boolean;

begin
  { Initial values }
  Check(OsResizeFlag = 0, 'OsResizeFlag starts at 0');
  Check(OsToldCols = 0, 'OsToldCols starts at 0');
  Check(OsToldRows = 0, 'OsToldRows starts at 0');

  { The hook type }
  Check(SizeOf(TOsHook) = SizeOf(Pointer), 'a hook is a plain procedure pointer');
  Hook := @CountHook;
  Check(Assigned(Hook), 'assigned hook');
  Hook();
  Check(HookCalls = 1, 'call through the variable');
  Hook;
  Check(HookCalls = 2, 'call through the variable without brackets');
  Other := @SetFlagHook;
  Other();
  Check(OsResizeFlag = 1, 'a hook changes the shared variable');
  OsResizeFlag := 0;
  Check(OsResizeFlag = 0, 'the flag is reset by its reader');
  Hooks[0] := @CountHook;
  Hooks[1] := @SetFlagHook;
  for I := 0 to 1 do
    Hooks[I]();
  Check((HookCalls = 3) and (OsResizeFlag = 1), 'hooks in an array');
  OsResizeFlag := 0;
  Hook := nil;
  Check(not Assigned(Hook), 'hook set to nil');
  Check(Pointer(Hook) = nil, 'hook is nil as a pointer');

  { Values of the variables }
  OsResizeFlag := 7;
  Check(OsResizeFlag = 7, 'OsResizeFlag keeps 7');
  OsResizeFlag := High(LongInt);
  Check(OsResizeFlag = 2147483647, 'OsResizeFlag keeps 2147483647');
  OsResizeFlag := -1;
  Check(OsResizeFlag = -1, 'OsResizeFlag keeps -1');
  OsResizeFlag := Low(LongInt);
  Check(OsResizeFlag = -2147483647 - 1, 'OsResizeFlag keeps the lowest value');
  OsResizeFlag := 0;
  Check(OsResizeFlag = 0, 'OsResizeFlag back to 0');

  OsToldCols := 80;
  OsToldRows := 25;
  Check((OsToldCols = 80) and (OsToldRows = 25), 'told size 80x25');
  OsToldCols := 2147483647;
  OsToldRows := 2147483647;
  Check((OsToldCols = 2147483647) and (OsToldRows = 2147483647), 'told size with the highest values');
  OsToldCols := -1;
  OsToldRows := -1;
  Check((OsToldCols = -1) and (OsToldRows = -1), 'told size with -1');
  OsToldCols := 200;
  Check((OsToldCols = 200) and (OsToldRows = -1), 'the two sizes are independent');
  OsToldRows := 60;
  Check((OsToldCols = 200) and (OsToldRows = 60), 'the other size changes alone');
  OsToldCols := 0;
  OsToldRows := 0;
  Check((OsToldCols = 0) and (OsToldRows = 0), 'told size back to 0');

  { The three variables are separate storage }
  PFlag := @OsResizeFlag;
  Check((PFlag <> @OsToldCols) and (PFlag <> @OsToldRows) and (@OsToldCols <> @OsToldRows),
    'the variables have different addresses');
  PFlag^ := 11;
  Check((OsResizeFlag = 11) and (OsToldCols = 0) and (OsToldRows = 0), 'a write through the address');
  OsResizeFlag := 0;
  Check(SizeOf(OsResizeFlag) = 4, 'LongInt size of OsResizeFlag');

  { The qualified names are the same variables }
  Writer;
  Check((OsResizeFlag = 42) and (OsToldCols = 132) and (OsToldRows = 50), 'the writer routine is seen by the plain names');
  OsResizeFlag := 1;
  OsToldCols := 2;
  OsToldRows := 3;
  Check(ReaderSum = 6, 'the reader routine sees the plain names');
  AllSet := True;
  for I := 1 to 100 do
  begin
    TvTermOsBase.OsToldCols := I;
    if OsToldCols <> I then
      AllSet := False;
  end;
  Check(AllSet, 'repeated writes are read back');

  Done;
end.
