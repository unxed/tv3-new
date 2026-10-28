{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/termview.h, source/tvterm-core/termview.cc, include/tvterm/termwnd.h,
  source/tvterm-core/termwnd.cc, include/tvterm/termframe.h, source/tvterm-core/termframe.cc,
  include/tvterm/consts.h, include/tvterm/termemu.h, include/tvterm/termctrl.h
  See COPYRIGHT.tvterm.

  A window of 40 by 12 cells at 2, 1 holds a terminal view of 38 by 10 cells over a controller whose client is
  /bin/sh and whose emulator is the one of TvVt. The window is inserted into a group that writes into the cells of a
  stage of 48 by 16 cells, so the cells that the view draws are read back from the stage. The group reads its events
  from a list of events (the mouse events that the view reads in its loop and the keys of the loop of a modal window)
  and, when the list is empty, waits for the wake-up of the controller and gives the broadcast
  cmCheckTerminalUpdates, as the application of a terminal does. The test types commands through the events of the
  group and reads the rows of the view from the stage. The shell is asked for output that does not depend on the
  prompt: the rows are found by their text, and the prompt is the last row, which ends with $ or #. The clipboard
  is a backend that remembers the text it gets. Every wait has a time-out. }
program t_vtview;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

uses
  cthreads, SysUtils, TvGeom, TvEvents, TvKeys, TvColors, TvCell, TvScreen, TvSys, TvClip, TvPty, TvViews,
  TvObjs, TvWindow, TvVtCore, TvVt, TvVtCtrl, TvVtView;

{$I testlib.inc}

type
  TProbe = function: Boolean;
  TPollProc = procedure;

  { The factory of the emulator of TvVt, with the shell in the variables of the client. }
  TShellKit = class(VTermEmulatorFactory)
  private
    FVars: array of EnvironmentVar;
  public
    function GetCustomEnvironment: TEnvironmentVarSpan; override;
  end;

  { A clipboard that keeps the last text it was given, and counts the requests for a text. }
  TTape = class(TClipboardBackend)
  public
    Copies: LongInt;
    Asks: LongInt;
    Last: string;
    function SetText(const Text: string): Boolean; override;
    function RequestText(Accept: TTextProc): Boolean; override;
  end;

  { The group at the root. }
  TStageRoot = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    Cutoff: QWord;
    TimedOut: Boolean;
    PutCount: Integer;
    LastPut: TEvent;
    procedure Arm(Ms: Integer);
    procedure Queue(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    procedure PutEvent(var Event: TEvent); override;
  end;

  TWatchedWindow = class(BasicTerminalWindow)
  public
    destructor Destroy; override;
  end;

  { What a look at the state gives. }
  TSnap = class
  public
    Offset, Limit, CurX, CurY: Integer;
    procedure Take(St: TerminalState);
  end;

const
  StageCols = 48;
  StageRows = 16;
  ViewLeft = 3;
  ViewTop = 2;
  ViewCols = 38;
  ViewRows = 10;
  Patience = 9000;

var
  CaretCalls, PtyErrors, WindowsFreed: Integer;
  Root: TStageRoot = nil;
  CopyBase: LongInt = 0;
  Hist: array[0..ViewRows - 1] of AnsiString;
  Win: TWatchedWindow = nil;
  Stage: array[0..StageCols * StageRows - 1] of TScreenCell;
  OnPoll: TPollProc = nil;
  View: TerminalView = nil;
  CaretAt: TPoint;
  Bar: TScrollBar = nil;
  Consts: TVTermConstants;
  Ctl: TerminalController = nil;
  PlainAttr: TColorAttr;
  Kit: TShellKit = nil;
  Tape: TTape = nil;
  Snap: TSnap = nil;

{ The hooks and the small classes. }

procedure OnPtyError(Reason: PAnsiChar);
begin
  Inc(PtyErrors);
end;

procedure NoteCaret(X, Y: Integer);
begin
  CaretAt.X := X;
  CaretAt.Y := Y;
  Inc(CaretCalls);
end;

function TShellKit.GetCustomEnvironment: TEnvironmentVarSpan;
var
  Own: TEnvironmentVarSpan;
  From: PEnvironmentVar;
  N: Integer;
begin
  if Length(FVars) = 0 then
  begin
    Own := inherited GetCustomEnvironment;
    SetLength(FVars, Integer(Own.Size) + 1);
    FVars[0].Name := 'SHELL';
    FVars[0].Value := '/bin/sh';
    From := Own.Data;
    for N := 1 to High(FVars) do
    begin
      FVars[N] := From^;
      Inc(From);
    end;
  end;
  Result.Data := @FVars[0];
  Result.Size := Length(FVars);
end;

function TTape.SetText(const Text: string): Boolean;
begin
  Last := Text;
  InterlockedIncrement(Copies);
  Result := True;
end;

function TTape.RequestText(Accept: TTextProc): Boolean;
begin
  InterlockedIncrement(Asks);
  Result := True;
end;

destructor TWatchedWindow.Destroy;
begin
  Inc(WindowsFreed);
  inherited Destroy;
end;

procedure TSnap.Take(St: TerminalState);
begin
  Offset := St.ScrollbackOffset;
  Limit := St.ScrollbackLimit;
  CurX := St.CursorPos.X;
  CurY := St.CursorPos.Y;
end;

{ Events. }

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function MakeKey(Code: Word; Ch: Char): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Code;
  if Ch <> #0 then
  begin
    Result.KeyDown.Text[0] := Ord(Ch);
    Result.KeyDown.TextLength := 1;
  end;
end;

function MakeCommand(Cmd: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evCommand;
  Result.Message.Command := Cmd;
end;

function MouseAt(What: Word; X, Y: Integer; Held: Byte): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := What;
  Result.Mouse.Where := Pt(X, Y);
  Result.Mouse.Buttons := Held;
end;

{ A mouse event at a column and a row of the view. }
function ViewMouse(What: Word; Col, Row: Integer; Held: Byte): TEvent;
begin
  Result := MouseAt(What, ViewLeft + Col, ViewTop + Row, Held);
end;

procedure TStageRoot.Arm(Ms: Integer);
begin
  SetLength(Script, 0);
  ScriptPos := 0;
  Cutoff := GetTickCount64 + QWord(Ms);
  TimedOut := False;
  PutCount := 0;
end;

procedure TStageRoot.Queue(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TStageRoot.GetEvent(var Event: TEvent);
begin
  FillChar(Event, SizeOf(Event), 0);
  if Assigned(OnPoll) then
    OnPoll;
  if ScriptPos < Length(Script) then
  begin
    Event := Script[ScriptPos];
    Inc(ScriptPos);
    Exit;
  end;
  if GetTickCount64 > Cutoff then
  begin
    { A loop that does not end is ended here. }
    TimedOut := True;
    EndModal(cmCancel);
    Event.What := evMouseUp;
    Exit;
  end;
  TEventQueue.WaitForEvents(20);
  Event.What := evBroadcast;
  Event.Message.Command := Consts.CmCheckTerminalUpdates;
end;

procedure TStageRoot.PutEvent(var Event: TEvent);
begin
  Inc(PutCount);
  LastPut := Event;
end;

{ The stage. }

function StageText(Left, Top, Count: Integer): AnsiString;
var
  K: Integer;
  One: string;
begin
  Result := '';
  for K := 0 to Count - 1 do
  begin
    One := Stage[Top * StageCols + Left + K].Character.GetText;
    if (One = '') or (One = #0) then
      One := ' ';
    Result := Result + One;
  end;
end;

function StageAttr(X, Y: Integer): TColorAttr;
begin
  Result := Stage[Y * StageCols + X].Attribute;
end;

function ViewRow(R: Integer): AnsiString;
begin
  Result := StageText(ViewLeft, ViewTop + R, ViewCols);
end;

function Marked(Col, Row: Integer): Boolean;
begin
  Result := StageAttr(ViewLeft + Col, ViewTop + Row) = PlainAttr.Reversed;
end;

function Plain(Col, Row: Integer): Boolean;
begin
  Result := StageAttr(ViewLeft + Col, ViewTop + Row) = PlainAttr;
end;

{ The first row of the view whose text, without the blanks at its end, is Wanted; -1 when there is none. }
function FindRow(const Wanted: AnsiString): Integer;
var
  R: Integer;
begin
  Result := -1;
  for R := 0 to ViewRows - 1 do
    if TrimRight(ViewRow(R)) = Wanted then
    begin
      Result := R;
      Exit;
    end;
end;

function FindRowHaving(const Piece: AnsiString): Integer;
var
  R: Integer;
begin
  Result := -1;
  for R := 0 to ViewRows - 1 do
    if Pos(Piece, ViewRow(R)) > 0 then
    begin
      Result := R;
      Exit;
    end;
end;

{ The last row that has text, when it ends with the character of a prompt; -1 otherwise. }
function LastPromptRow: Integer;
var
  R: Integer;
  T: AnsiString;
begin
  Result := -1;
  for R := ViewRows - 1 downto 0 do
  begin
    T := TrimRight(ViewRow(R));
    if T <> '' then
    begin
      if T[Length(T)] in ['$', '#'] then
        Result := R;
      Exit;
    end;
  end;
end;

procedure DumpView(const Why: string);
var
  R: Integer;
begin
  WriteLn('  [', Why, '] rows of the view, cursor ', View.Cursor.X, ',', View.Cursor.Y);
  for R := 0 to ViewRows - 1 do
    WriteLn('  ', R:2, '|', ViewRow(R), '|');
end;

{ The controller. }

procedure Pump(Ms: Integer);
begin
  TEventQueue.WaitForEvents(Ms);
  Message(Root, evBroadcast, Consts.CmCheckTerminalUpdates, nil);
end;

function WaitFor(Probe: TProbe; LimitMs: Integer): Boolean;
var
  Stop: QWord;
begin
  Stop := GetTickCount64 + QWord(LimitMs);
  Result := Probe();
  while (not Result) and (GetTickCount64 < Stop) do
  begin
    Pump(25);
    Result := Probe();
  end;
end;

{ Waits for Probe and counts the result; the rows of the view are shown when it fails. }
procedure Await(Probe: TProbe; const Name: string);
var
  Ok: Boolean;
begin
  Ok := WaitFor(Probe, Patience);
  if not Ok then
    DumpView(Name);
  Check(Ok, Name);
end;

{ A few rounds in which nothing is expected to change. }
procedure Settle(Rounds: Integer);
var
  K: Integer;
begin
  for K := 1 to Rounds do
    Pump(30);
end;

procedure TypeText(const Line: AnsiString; WithEnter: Boolean);
var
  K: Integer;
  Ev: TEvent;
begin
  for K := 1 to Length(Line) do
  begin
    Ev := MakeKey(Ord(Line[K]), Line[K]);
    Root.HandleEvent(Ev);
  end;
  if WithEnter then
  begin
    Ev := MakeKey(kbEnter, #0);
    Root.HandleEvent(Ev);
  end;
end;

procedure Look;
begin
  Ctl.LockState(@Snap.Take);
end;

function Title: AnsiString;
var
  P: PAnsiChar;
begin
  P := Win.GetTitle(0);
  if P = nil then
    Result := ''
  else
    Result := StrPas(P);
end;

function FrameRow: AnsiString;
begin
  Result := StageText(2, 1, 40);
end;

{ The probes of the waits. }

function PromptIsUp: Boolean;
begin
  Result := LastPromptRow >= 0;
end;

function EchoIsDone: Boolean;
var
  Q: Integer;
begin
  Q := FindRow('q42');
  Result := (Q >= 0) and (LastPromptRow > Q);
end;

function TitleIsHello: Boolean;
begin
  Result := Title = 'Hello';
end;

function HiIsDone: Boolean;
var
  Q: Integer;
begin
  Q := FindRow('hi');
  Result := (Q >= 0) and (LastPromptRow > Q);
end;

function LoopIsDone: Boolean;
var
  Q: Integer;
begin
  Q := FindRow('L20');
  Result := (Q >= 0) and (LastPromptRow > Q);
end;

{ True when a text has reached the clipboard since CopyBase was set. }
function CopyArrived: Boolean;
begin
  Result := Tape.Copies > CopyBase;
end;

function ShowsFirstLine: Boolean;
begin
  Result := Pos('echo q', ViewRow(0)) > 0;
end;

function ShowsThirdLine: Boolean;
begin
  Result := (Hist[3] <> '') and (ViewRow(0) = Hist[3]);
end;

function ClientIsGone: Boolean;
begin
  Result := Ctl.ClientIsDisconnected;
end;

function ShowsDisconnected: Boolean;
begin
  Result := Pos('(Disconnected)', FrameRow) > 0;
end;

{ The polls of the modal loops. GrabPhase tells what the poll waits for. }

var
  GrabPhase: Integer;
  GrabHelp: Word;
  GrabModal: Boolean;
  GrabFrame: AnsiString;
  GrabTitle: AnsiString;

procedure QueueText(const Line: AnsiString);
var
  K: Integer;
begin
  for K := 1 to Length(Line) do
    Root.Queue(MakeKey(Ord(Line[K]), Line[K]));
  Root.Queue(MakeKey(kbEnter, #0));
end;

procedure PollTyping;
begin
  case GrabPhase of
    0:
      begin
        GrabHelp := Win.HelpCtx;
        GrabModal := (Win.State and sfModal) <> 0;
        GrabFrame := FrameRow;
        GrabTitle := Title;
        QueueText('echo grab');
        GrabPhase := 1;
      end;
    1:
      if FindRow('grab') >= 0 then
      begin
        Root.Queue(MakeCommand(Consts.CmReleaseInput));
        GrabPhase := 2;
      end;
  end;
end;

procedure PollClose;
begin
  if GrabPhase = 0 then
  begin
    Root.Queue(MakeCommand(cmClose));
    GrabPhase := 1;
  end;
end;

procedure PollClickOutside;
begin
  if GrabPhase = 0 then
  begin
    Root.Queue(MouseAt(evMouseDown, 46, 14, mbLeftButton));
    GrabPhase := 1;
  end;
end;

{ ---- the tests ---- }

procedure TestStatics;
var
  Cmds: TWordSpan;
begin
  Check(BasicTerminalWindow.ViewBounds(Rc(2, 1, 42, 13)) = Rc(3, 2, 41, 12),
    'the bounds of the view are the bounds of the window grown by -1');
  Check(BasicTerminalWindow.ViewSize(Rc(2, 1, 42, 13)) = Pt(38, 10), 'the size of the view');
  Check(BasicTerminalWindow.ViewSize(Rc(0, 0, 2, 2)) = Pt(0, 0), 'a window of 2 by 2 has an empty view');
  Cmds := Consts.FocusedCmds;
  Check(Cmds.Size = 3, 'three commands are active while a terminal window is focused');
  Check((Cmds.Data^ = Consts.CmGrabInput) and (Cmds.Data[2] = Consts.CmStartSelection),
    'the focused commands run from cmGrabInput to cmStartSelection');
end;

procedure TestConstruction;
begin
  Check(Win.Frame is BasicTerminalFrame, 'the frame of the window is a BasicTerminalFrame');
  Check((Win.Options and ofTileable) <> 0, 'the window can be tiled');
  Check((Win.State and sfShadow) = 0, 'the window has no shadow');
  Check((Win.EventMask and evBroadcast) <> 0, 'the window takes broadcasts');
  Check(Win.Number = wnNoNumber, 'the window has no number');
  Check(Win.GetBounds = Rc(2, 1, 42, 13), 'the bounds of the window');
  Check(Win.At(1) is TerminalView, 'the view is the top subview of the window');
  Check(Win.At(2) is TScrollBar, 'the scroll bar is below the view');
  Check(Win.At(3) = TView(Win.Frame), 'the frame is the lowest subview');
  Check(View.GetBounds = Rc(1, 1, 39, 11), 'the view fills the inside of the frame');
  Check(Bar.GetBounds = Rc(39, 1, 40, 11), 'the scroll bar lies on the right edge of the frame');
  Check(View.GrowMode = (gfGrowHiX or gfGrowHiY), 'the view grows with the lower right corner');
  Check((View.Options and (ofSelectable or ofFirstClick)) = (ofSelectable or ofFirstClick),
    'the view can be selected and takes the first click');
  Check((View.EventMask and (evMouseMove or evMouseAuto or evMouseWheel or evBroadcast)) =
    (evMouseMove or evMouseAuto or evMouseWheel or evBroadcast), 'the view takes the mouse and broadcasts');
  Check(View.GetState(sfCursorVis), 'the cursor of the view is shown');
  Check(View.TermCtrl = Ctl, 'the view holds the controller');
  Check(Win.GetTitle(0) = nil, 'a connected terminal without a title has no title');
  Check(not TView.CommandEnabled(Consts.CmGrabInput) and not TView.CommandEnabled(Consts.CmReleaseInput) and
    not TView.CommandEnabled(Consts.CmStartSelection) and not TView.CommandEnabled(cmPaste),
    'the commands of a terminal window are not active before the window is');
end;

procedure TestActivation;
begin
  Check(Win.GetState(sfActive), 'the window is active');
  Check(TView.CommandEnabled(Consts.CmGrabInput) and TView.CommandEnabled(Consts.CmReleaseInput) and
    TView.CommandEnabled(Consts.CmStartSelection) and TView.CommandEnabled(cmPaste),
    'an active window enables the focused commands and cmPaste');
  Win.SetState(sfActive, False);
  Check(not TView.CommandEnabled(Consts.CmGrabInput) and not TView.CommandEnabled(cmPaste),
    'a window that is not active disables them');
  Win.SetState(sfActive, True);
  Check(TView.CommandEnabled(Consts.CmStartSelection), 'and enables them again');
  Check(Win.GetState(sfFocused) and View.GetState(sfFocused), 'the window and the view are focused');
end;

procedure TestPrompt;
var
  PR: Integer;
begin
  Await(@PromptIsUp, 'the prompt of the shell is drawn');
  PR := LastPromptRow;
  Check(PR >= 0, 'a prompt row exists');
  if PR < 0 then
    Exit;
  Check((View.Cursor.X = Length(TrimRight(ViewRow(PR))) + 1) and (View.Cursor.Y = PR),
    'the cursor of the view follows the cursor of the terminal');
  Check(CaretCalls > 0, 'the caret was placed');
  Check((CaretAt.X = ViewLeft + View.Cursor.X) and (CaretAt.Y = ViewTop + View.Cursor.Y),
    'the caret is at the cursor of the view');
  Check(View.GetState(sfCursorVis), 'the cursor of the terminal is visible');
end;

procedure TestTyping;
var
  Ev: TEvent;
  RowQ, RowEcho, Col: Integer;
begin
  Ev := MakeKey(Ord('e'), 'e');
  Root.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the view takes a key');
  TypeText('cho q$((6*7))', True);
  Await(@EchoIsDone, 'the output of the command is drawn');

  RowQ := FindRow('q42');
  RowEcho := FindRowHaving('echo q');
  Check((RowEcho >= 0) and (RowQ = RowEcho + 1), 'the echo of the line and its output are in consecutive rows');
  Check(LastPromptRow = RowQ + 1, 'the prompt follows the output');
  if (RowQ < 0) or (RowEcho < 0) then
    Exit;
  Col := Pos('echo q', ViewRow(RowEcho)) - 1;
  Check(Col = Length(TrimRight(ViewRow(RowQ + 1))) + 1, 'the echo of the line starts after a prompt');
  Check(StageText(ViewLeft, ViewTop + RowQ, 3) = 'q42', 'the cells of the output are on the stage');
  Check(StageText(ViewLeft + 3, ViewTop + RowQ, 5) = '     ', 'the cells after the output are blank');
  Check((View.Cursor.Y = RowQ + 1) and (View.Cursor.X = Col), 'the cursor is behind the new prompt');
  Check((CaretAt.X = ViewLeft + Col) and (CaretAt.Y = ViewTop + RowQ + 1), 'the caret is behind the new prompt');
  Check(Plain(0, RowQ) and Plain(1, RowQ), 'the cells of the text have the plain attribute');
end;

procedure TestTitle;
begin
  TypeText('printf ''\033]0;Hello\007''', True);
  Await(@TitleIsHello, 'the title of the client reaches the window');
  Check(Pos('Hello', FrameRow) > 0, 'the frame shows the title');
  Check(Title = 'Hello', 'the title is kept by the window');
  Settle(6);
end;

procedure TestBufferReuse;
var
  Spot: Integer;
begin
  Spot := 9 * 40 + 31;
  Check(Win.Buffer <> nil, 'the window has a buffer');
  Win.Buffer[Spot] := TScreenCell.Create(TScreenCharacter.Create('Z'), TColorAttr.Create($1F));
  TypeText('echo hi', True);
  Await(@HiIsDone, 'a second command is drawn');
  Check(Win.Buffer[Spot].Character.GetText = 'Z',
    'a cell of the buffer of the owner that was not damaged is not copied again');
  Check(FindRow('hi') >= 0, 'the damaged rows are copied');

  View.ChangeBounds(View.GetBounds);
  Check(Win.Buffer[Spot].Character.GetText <> 'Z', 'a change of the bounds copies the whole surface');
  Check(View.GetBounds = Rc(1, 1, 39, 11), 'the bounds are kept');
  Settle(6);
end;

procedure TestSelection;
var
  RowEcho, Col, K, RowQ: Integer;
  Ev: TEvent;
  Base: LongInt;
  Wanted: AnsiString;
begin
  RowEcho := FindRowHaving('echo q');
  RowQ := FindRow('q42');
  Check((RowEcho >= 0) and (RowQ >= 0), 'the first command is still in the view');
  if (RowEcho < 0) or (RowQ < 0) then
    Exit;
  Col := Pos('echo q', ViewRow(RowEcho)) - 1;

  { A drag from left to right marks the cells from the first to the one before the last. }
  Root.Arm(Patience);
  Root.Queue(ViewMouse(evMouseMove, Col + 4, RowEcho, mbLeftButton));
  Root.Queue(ViewMouse(evMouseUp, Col + 4, RowEcho, 0));
  Ev := ViewMouse(evMouseDown, Col, RowEcho, mbLeftButton);
  Root.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the view takes the press');
  Check(Root.ScriptPos = 2, 'the view read the drag and the release');
  Check(Marked(Col, RowEcho) and Marked(Col + 1, RowEcho) and Marked(Col + 2, RowEcho) and
    Marked(Col + 3, RowEcho), 'the selected cells have a reversed attribute');
  Check(Plain(Col + 4, RowEcho) and Plain(Col - 1, RowEcho), 'the cells around the selection are not changed');
  Check((View.HelpCtx = Consts.HcSelecting) and (Win.GetHelpCtx = Consts.HcSelecting),
    'the help context says that a selection exists');

  { The copy goes through the emulator to the clipboard, and the selection ends. }
  CopyBase := Tape.Copies;
  Check(Message(View, evCommand, Consts.CmCopySelection, nil) = Pointer(View), 'the view takes cmCopySelection');
  Check(Plain(Col, RowEcho) and Plain(Col + 3, RowEcho), 'the copy takes the marks away');
  Check(View.HelpCtx = hcNoContext, 'the help context is the one of no selection');
  Check(WaitFor(@CopyArrived, Patience), 'the text reaches the clipboard');
  Check(Tape.Copies = CopyBase + 1, 'the clipboard got one text');
  Check(Tape.Last = 'echo', 'the text is the selected one');

  { A drag from right to left, then cmCancelSelection. }
  Root.Arm(Patience);
  Root.Queue(ViewMouse(evMouseMove, Col, RowEcho, mbLeftButton));
  Root.Queue(ViewMouse(evMouseUp, Col, RowEcho, 0));
  Ev := ViewMouse(evMouseDown, Col + 4, RowEcho, mbLeftButton);
  Root.HandleEvent(Ev);
  Check(Marked(Col, RowEcho) and Marked(Col + 3, RowEcho) and Plain(Col + 4, RowEcho),
    'a selection that goes backwards marks the same cells');
  Check(Message(View, evCommand, Consts.CmCancelSelection, nil) = Pointer(View), 'the view takes cmCancelSelection');
  Check(Plain(Col, RowEcho) and Plain(Col + 3, RowEcho) and (View.HelpCtx = hcNoContext),
    'cancelling takes the marks away');

  { A selection over two rows: the end of the first and the start of the second. }
  CopyBase := Tape.Copies;
  Root.Arm(Patience);
  Root.Queue(ViewMouse(evMouseMove, 1, RowQ + 1, mbLeftButton));
  Root.Queue(ViewMouse(evMouseUp, 1, RowQ + 1, 0));
  Ev := ViewMouse(evMouseDown, 2, RowQ, mbLeftButton);
  Root.HandleEvent(Ev);
  Check(Marked(2, RowQ) and Marked(ViewCols - 1, RowQ) and Plain(1, RowQ), 'the first row is marked from the start');
  Check(Marked(0, RowQ + 1) and Plain(1, RowQ + 1), 'the last row is marked up to the one before the end');
  for K := 0 to ViewCols - 1 do
    if Marked(K, RowEcho) then
      Check(False, 'no cell of the other rows is marked');
  Message(View, evCommand, Consts.CmCopySelection, nil);
  Check(WaitFor(@CopyArrived, Patience) and (Tape.Copies = CopyBase + 1), 'the second text reaches the clipboard');
  Wanted := '2' + #10 + Copy(ViewRow(RowQ + 1), 1, 1);
  Check(Tape.Last = Wanted, 'the text of two rows has a line feed between them');

  { A press that is released where it was made selects nothing. }
  Root.Arm(Patience);
  Root.Queue(ViewMouse(evMouseUp, Col, RowEcho, 0));
  Ev := ViewMouse(evMouseDown, Col, RowEcho, mbLeftButton);
  Root.HandleEvent(Ev);
  Check(Plain(Col, RowEcho) and (View.HelpCtx = hcNoContext), 'a click selects nothing');

  { cmStartSelection sets the help context at once, and copying nothing sends nothing. }
  CopyBase := Tape.Copies;
  Check(Message(View, evCommand, Consts.CmStartSelection, nil) = Pointer(View), 'the view takes cmStartSelection');
  Check(View.HelpCtx = Consts.HcSelecting, 'the help context is that of a selection');
  Message(View, evCommand, Consts.CmCopySelection, nil);
  Settle(8);
  Check(Tape.Copies = CopyBase, 'an empty selection is not copied');
  Check(View.HelpCtx = hcNoContext, 'and the selection mode ends');

  { cmPaste asks the clipboard for its text. }
  Base := Tape.Asks;
  Check(Message(View, evCommand, cmPaste, nil) = Pointer(View), 'the view takes cmPaste');
  Check(Tape.Asks = Base + 1, 'the clipboard was asked for its text');
end;

procedure TestFrame;
var
  Tint: TColorAttr;
begin
  Win.Frame.SetState(sfDragging, True);
  Check(StageText(2 + 4, 1 + 11, 7) = ' 38x10 ', 'a dragged frame shows the size of the terminal');
  Tint := StageAttr(2 + 4, 1 + 11);
  Check(Tint.ToBIOS = $0A, 'the size has the color of the icons of the frame');
  Win.Frame.SetState(sfDragging, False);
  Check(StageText(2 + 5, 1 + 11, 1) <> '3', 'and stops when the dragging ends');
end;

procedure TestGrabbing;
var
  R: Word;
begin
  { cmGrabInput makes the window modal, and the keys go to the client. }
  GrabPhase := 0;
  Root.Arm(Patience);
  OnPoll := @PollTyping;
  Check(Message(Win, evCommand, Consts.CmGrabInput, nil) = Pointer(Win), 'the window takes cmGrabInput');
  OnPoll := nil;
  Check(not Root.TimedOut, 'the modal loop ended by itself');
  Check(GrabHelp = Consts.HcInputGrabbed, 'the help context is that of a grabbed input');
  Check(GrabModal, 'the window is modal');
  Check(Pos('(Input Grab)', GrabFrame) > 0, 'the frame shows the grab');
  Check(GrabTitle = 'Hello (Input Grab)', 'the title has the text of the grab behind it');
  Check(FindRow('grab') >= 0, 'the keys of the loop reached the client');
  Check(((Win.State and sfModal) = 0) and (Win.HelpCtx = hcNoContext), 'cmReleaseInput ends the grab');
  Check(Title = 'Hello', 'the title is the one of the client again');
  Check(Pos('(Input Grab)', FrameRow) = 0, 'the frame does not show the grab any more');

  { cmClose ends the modal loop and is put back for the owner. }
  GrabPhase := 0;
  Root.Arm(Patience);
  OnPoll := @PollClose;
  R := Root.ExecView(Win);
  OnPoll := nil;
  Check((R = 0) and not Root.TimedOut, 'a modal window ends its loop at cmClose');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmClose),
    'cmClose is put back');
  Check(Root.First = TView(Win), 'the window is still there');

  { A press outside of the window ends it and is put back. }
  GrabPhase := 0;
  Root.Arm(Patience);
  OnPoll := @PollClickOutside;
  R := Root.ExecView(Win);
  OnPoll := nil;
  Check((R = 0) and not Root.TimedOut, 'a modal window ends its loop at a press outside');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evMouseDown), 'the press is put back');
end;

procedure TestScrollback;
var
  Ev: TEvent;
  K, Before: Integer;
  Wanted: AnsiString;
begin
  TypeText('for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do echo L$i; done', True);
  Await(@LoopIsDone, 'the output of a loop is drawn');
  Look;
  Check(Snap.Limit >= 15, 'lines have left the top of the screen');
  Check(Snap.Offset = Snap.Limit, 'the terminal follows its end');
  Check((Bar.MinVal = 0) and (Bar.MaxVal = Snap.Limit), 'the range of the scroll bar is the number of lines');
  Check(Bar.Value = Bar.MaxVal, 'the scroll bar is at its end');
  Check((Bar.PgStep = ViewRows) and (Bar.ArStep = 1), 'a page is the height of the view');
  Check(Bar.GetState(sfVisible), 'the scroll bar is shown');
  Check(FindRow('L20') + 1 = LastPromptRow, 'the last line is above the prompt');
  Check(FindRow('L1') < 0, 'the first line has left the view');
  Check(View.Cursor.Y = Snap.CurY, 'the cursor is where the terminal puts it while it follows');

  { The scroll bar moves the terminal to its oldest line. }
  Bar.SetValue(0);
  Await(@ShowsFirstLine, 'the oldest line is drawn');
  Look;
  Check(Snap.Offset = 0, 'the terminal got the offset of the bar');
  Check(Bar.Value = 0, 'the bar keeps it');
  Check(View.Cursor.Y = Snap.CurY + Snap.Limit, 'the cursor is below the rows that are shown');
  for K := 0 to ViewRows - 1 do
    Hist[K] := ViewRow(K);

  { A step of the wheel moves three lines. }
  Ev := MouseAt(evMouseWheel, ViewLeft, ViewTop, 0);
  Ev.Mouse.Wheel := mwDown;
  Root.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the view takes the wheel');
  Await(@ShowsThirdLine, 'the view scrolls by the wheel');
  Check(Bar.Value = 3, 'the bar follows the wheel');
  for K := 0 to 6 do
    if ViewRow(K) <> Hist[K + 3] then
      Check(False, 'the rows move up by three');

  { The rows of a selection are counted from the oldest line. }
  Root.Arm(Patience);
  Root.Queue(ViewMouse(evMouseMove, 12, 0, mbLeftButton));
  Root.Queue(ViewMouse(evMouseUp, 12, 0, 0));
  Ev := ViewMouse(evMouseDown, 7, 0, mbLeftButton);
  Root.HandleEvent(Ev);
  Check(Marked(7, 0) and Marked(11, 0) and Plain(12, 0) and Plain(6, 0), 'the cells of the shown line are marked');
  CopyBase := Tape.Copies;
  Message(View, evCommand, Consts.CmCopySelection, nil);
  Check(WaitFor(@CopyArrived, Patience) and (Tape.Copies = CopyBase + 1),
    'the text of the old line reaches the clipboard');
  Wanted := TrimRight(Copy(Hist[3], 8, 5));
  Check(Tape.Last = Wanted, 'the text is that of the line of the offset');
end;

procedure TestEnd;
var
  R: Word;
  Before: Integer;
begin
  TypeText('exit', True);
  Await(@ClientIsGone, 'the client ends');
  Await(@ShowsDisconnected, 'the title tells that the client ended');
  Check(Title = 'Hello (Disconnected)', 'the title of a closed terminal');

  { The loop of a modal window ends at once when the client has ended. }
  Root.Arm(Patience);
  R := Root.ExecView(Win);
  Check((R = 0) and not Root.TimedOut, 'a modal window ends its loop when the client has ended');

  { cmClose closes the window; its controller is shut down with the view. }
  Before := WindowsFreed;
  Check(Message(Win, evCommand, cmClose, nil) = Pointer(Win), 'the window takes cmClose');
  Check(WindowsFreed = Before + 1, 'the window is destroyed');
  Check(Root.First = nil, 'the root has no window left');
  Win := nil;
  View := nil;
  Bar := nil;
  Ctl := nil;
end;

var
  Saved: TClipboardBackend;

begin
  PtyErrors := 0;
  CaretCalls := 0;
  WindowsFreed := 0;
  OnPoll := nil;
  FillChar(Stage, SizeOf(Stage), 0);
  FillChar(PlainAttr, SizeOf(PlainAttr), 0);

  Consts.CmCheckTerminalUpdates := 240;
  Consts.CmTerminalUpdated := 241;
  Consts.CmCopySelection := 242;
  Consts.CmCancelSelection := 243;
  Consts.CmGrabInput := 244;
  Consts.CmReleaseInput := 245;
  Consts.CmStartSelection := 246;
  Consts.HcInputGrabbed := 7001;
  Consts.HcSelecting := 7002;

  TScreen.CursorLines := 20;
  CaretPositionHook := @NoteCaret;
  Tape := TTape.Create;
  Saved := TClipboard.Backend;
  TClipboard.Backend := Tape;
  Snap := TSnap.Create;
  Kit := TShellKit.Create;

  TestStatics;

  Ctl := TerminalController.Make(Pt(38, 10), Kit, @OnPtyError);
  Check(Ctl <> nil, 'the controller is made');
  Check(PtyErrors = 0, 'the controller reports no error');
  if Ctl = nil then
  begin
    Done;
    Exit;
  end;

  Root := TStageRoot.Create(Rc(0, 0, StageCols, StageRows));
  Root.Options := Root.Options and not ofBuffered;
  Root.Buffer := @Stage[0];
  Root.State := Root.State or sfSelected or sfFocused;
  Root.SetState(sfExposed, True);

  TView.DisableCommand(Consts.CmGrabInput);
  TView.DisableCommand(Consts.CmReleaseInput);
  TView.DisableCommand(Consts.CmStartSelection);
  TView.DisableCommand(cmPaste);

  Win := TWatchedWindow.Create(Rc(2, 1, 42, 13), Ctl, Consts);
  View := TerminalView(Win.At(1));
  Bar := TScrollBar(Win.At(2));
  TestConstruction;

  Root.Insert(Win);
  TestActivation;
  TestPrompt;
  TestTyping;
  TestTitle;
  TestBufferReuse;
  TestSelection;
  TestFrame;
  TestGrabbing;
  TestScrollback;
  TestEnd;

  { The loops of the controller end after the client's last second. }
  Sleep(2600);

  TvObject.DestroyObject(Root);
  CaretPositionHook := nil;
  TClipboard.Backend := Saved;
  Tape.Free;
  Snap.Free;
  Kit.Free;
  Done;
end.
