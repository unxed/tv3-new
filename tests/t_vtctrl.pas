{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/termctrl.h, source/tvterm-core/termctrl.cc
  See COPYRIGHT.tvterm. }
program t_vtctrl;

{$mode objfpc}
{$R-}
{$Q-}

uses
  cthreads, SysUtils, TvGeom, TvKeys, TvSys, TvPty, TvVtCore, TvVt, TvVtCtrl;

{$I testlib.inc}

const
  PatienceMs = 9000;
  ShellPath = '/bin/sh';

var
  FailedReason: AnsiString;
  FailedCalls: Integer;

procedure RememberFailure(Reason: PAnsiChar);
begin
  Inc(FailedCalls);
  FailedReason := AnsiString(Reason);
end;

{ The factory of the emulator of TvVt, with the shell added to the variables that the client gets. }
type
  TShellFactory = class(TerminalEmulatorFactory)
  private
    FEmulators: VTermEmulatorFactory;
    FVars: array of EnvironmentVar;
  public
    constructor Create;
    destructor Destroy; override;
    function Make(const Size: TPoint; ClientDataWriter: Writer): TerminalEmulator; override;
    function GetCustomEnvironment: TEnvironmentVarSpan; override;
  end;

constructor TShellFactory.Create;
var
  Inner: TEnvironmentVarSpan;
  From: PEnvironmentVar;
  N: Integer;
begin
  inherited Create;
  FEmulators := VTermEmulatorFactory.Create;
  Inner := FEmulators.GetCustomEnvironment;
  SetLength(FVars, 1 + Integer(Inner.Size));
  FVars[0].Name := 'SHELL';
  FVars[0].Value := ShellPath;
  From := Inner.Data;
  for N := 1 to High(FVars) do
  begin
    FVars[N] := From^;
    Inc(From);
  end;
end;

destructor TShellFactory.Destroy;
begin
  FEmulators.Free;
  inherited Destroy;
end;

function TShellFactory.Make(const Size: TPoint; ClientDataWriter: Writer): TerminalEmulator;
begin
  Result := FEmulators.Make(Size, ClientDataWriter);
end;

function TShellFactory.GetCustomEnvironment: TEnvironmentVarSpan;
begin
  Result.Data := @FVars[0];
  Result.Size := Length(FVars);
end;

{ A copy of the text of the surface of the state, row by row, with the blanks at the end of a row cut. }
type
  TScreenShot = class
  public
    Rows: array of AnsiString;
    Wide, Tall: Integer;
    CurX, CurY, Back, BackLimit: Integer;
    procedure Take(State: TerminalState);
    function HasRow(const Wanted: AnsiString): Boolean;
  end;

procedure TScreenShot.Take(State: TerminalState);
var
  Y, X: Integer;
  Line, Piece: AnsiString;
begin
  Wide := State.Surface.Size.X;
  Tall := State.Surface.Size.Y;
  CurX := State.CursorPos.X;
  CurY := State.CursorPos.Y;
  Back := State.ScrollbackOffset;
  BackLimit := State.ScrollbackLimit;
  SetLength(Rows, 0);
  SetLength(Rows, Tall);
  for Y := 0 to Tall - 1 do
  begin
    Line := '';
    for X := 0 to Wide - 1 do
    begin
      Piece := State.Surface.At(Y, X)^.Character.GetText;
      if (Piece = '') or (Piece = #0) then
        Piece := ' ';
      Line := Line + Piece;
    end;
    Rows[Y] := TrimRight(Line);
  end;
end;

function TScreenShot.HasRow(const Wanted: AnsiString): Boolean;
var
  Y: Integer;
begin
  Result := False;
  for Y := 0 to High(Rows) do
    if Rows[Y] = Wanted then
      Exit(True);
end;

function BlankEvent(Kind: TerminalEventType): TerminalEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := Kind;
end;

{ The keys of a command line, then Enter. }
procedure TypeLine(Ctl: TerminalController; const Command: AnsiString);
var
  Pos1: Integer;
  Key: TerminalEvent;
begin
  for Pos1 := 1 to Length(Command) do
  begin
    Key := BlankEvent(TerminalEventType.KeyDown);
    Key.KeyDown.KeyCode := Ord(Command[Pos1]);
    Key.KeyDown.Text[0] := Ord(Command[Pos1]);
    Key.KeyDown.TextLength := 1;
    Ctl.SendEvent(Key);
  end;
  Key := BlankEvent(TerminalEventType.KeyDown);
  Key.KeyDown.KeyCode := kbEnter;
  Ctl.SendEvent(Key);
end;

procedure ResizeTo(Ctl: TerminalController; Cols, Lines: Integer);
var
  Ev: TerminalEvent;
begin
  Ev := BlankEvent(TerminalEventType.ViewportResize);
  Ev.ViewportResize.X := Cols;
  Ev.ViewportResize.Y := Lines;
  Ctl.SendEvent(Ev);
end;

{ Prints what the surface and the flags hold, for the log of a failed wait. }
procedure ShowScreen(Ctl: TerminalController; Shot: TScreenShot; const Title: AnsiString);
var
  Y: Integer;
begin
  Ctl.LockState(@Shot.Take);
  WriteLn('  [', Title, '] surface ', Shot.Wide, 'x', Shot.Tall, ', cursor ', Shot.CurX, ',', Shot.CurY,
    ', scrollback ', Shot.Back, '/', Shot.BackLimit, ', disconnected ', Ctl.ClientIsDisconnected,
    ', update flag ', Ctl.StateHasBeenUpdated);
  for Y := 0 to High(Shot.Rows) do
    WriteLn('  ', Y:2, '|', Shot.Rows[Y], '|');
end;

{ Waits until the state has been updated and then shows the row Wanted (any row when it is empty) on a surface of
  Cols x Lines cells (any size when Cols is 0). Each round waits for the wake-up of the event queue for 50 ms at
  most. }
function AwaitScreen(Ctl: TerminalController; Shot: TScreenShot; const Wanted: AnsiString;
  Cols, Lines: Integer): Boolean;
var
  Deadline: QWord;
begin
  Result := False;
  Deadline := GetTickCount64 + PatienceMs;
  repeat
    if Ctl.StateHasBeenUpdated then
    begin
      Ctl.LockState(@Shot.Take);
      if ((Wanted = '') or Shot.HasRow(Wanted)) and
         ((Cols = 0) or ((Shot.Wide = Cols) and (Shot.Tall = Lines))) then
        Exit(True);
    end;
    TEventQueue.WaitForEvents(50);
  until GetTickCount64 >= Deadline;
  ShowScreen(Ctl, Shot, 'wait for "' + Wanted + '" ' + IntToStr(Cols) + 'x' + IntToStr(Lines));
end;

function AwaitDisconnect(Ctl: TerminalController): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + PatienceMs;
  while (not Ctl.ClientIsDisconnected) and (GetTickCount64 < Deadline) do
    TEventQueue.WaitForEvents(50);
  Result := Ctl.ClientIsDisconnected;
end;

function AwaitUpdateFlag(Ctl: TerminalController): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + PatienceMs;
  Result := Ctl.StateHasBeenUpdated;
  while (not Result) and (GetTickCount64 < Deadline) do
  begin
    TEventQueue.WaitForEvents(20);
    Result := Ctl.StateHasBeenUpdated;
  end;
end;

var
  Factory: TShellFactory;
  Ctl: TerminalController;
  Shot: TScreenShot;
  Origin: TPoint;

begin
  FailedCalls := 0;
  Factory := TShellFactory.Create;
  Shot := TScreenShot.Create;
  Origin.X := 80;
  Origin.Y := 24;

  Ctl := TerminalController.Make(Origin, Factory, @RememberFailure);
  Check(Ctl <> nil, 'Make gives a controller');
  Check(FailedCalls = 0, 'OnError is not called on success');
  if Ctl = nil then
  begin
    Done;
    Exit;
  end;
  Check(not Ctl.ClientIsDisconnected, 'the client is connected at the start');

  { 6*7 is worked out by the shell: the command line has the text of the expression, the output row has 42 }
  TypeLine(Ctl, 'echo q$((6*7))');
  Check(AwaitScreen(Ctl, Shot, '$ q42', 0, 0), 'row "$ q42" (prompt and output) on the surface');
  Check((Shot.Wide = 80) and (Shot.Tall = 24), 'surface of 24 rows by 80 columns');
  Check(not Shot.HasRow('q$((6*7))'), 'the output row is not the command text');
  Check(not Ctl.ClientIsDisconnected, 'the client is still connected after a command');

  { the viewport: the emulator and the client are resized in the update that follows the event, and the surface
    takes the new size in the next update, which the output of the command causes }
  ResizeTo(Ctl, 100, 30);
  TypeLine(Ctl, 'stty size');
  Check(AwaitScreen(Ctl, Shot, '30 100', 100, 30), 'client reports 30 rows by 100 columns');

  { the end of the client }
  TypeLine(Ctl, 'exit');
  Check(AwaitDisconnect(Ctl), 'ClientIsDisconnected after exit');
  Check(AwaitUpdateFlag(Ctl), 'StateHasBeenUpdated after the end of the client');

  { events that arrive after the end of the client are accepted }
  TypeLine(Ctl, 'x');
  Check(Ctl.ClientIsDisconnected, 'the client stays disconnected');

  Ctl.ShutDown;
  { the loops end and the controller frees itself; the writer loop waits a second for the client }
  Sleep(2500);

  Shot.Free;
  Factory.Free;
  Done;
end.
