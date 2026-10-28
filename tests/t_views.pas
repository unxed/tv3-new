{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/views.h, include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h,
  include/tvision/tstrview.h, include/tvision/tspan.h, source/tvision/tview.cpp, source/tvision/tgroup.cpp,
  source/tvision/tcmdset.cpp, source/tvision/tvwrite.cpp, source/tvision/tvexposd.cpp, source/tvision/tvcursor.cpp,
  source/tvision/tgrmv.cpp, source/tvision/misc.cpp, include/tvision/util.h
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it, and
  the display of the carets is a fake that remembers the last caret. The root reads its events from a script, and
  from the posted events of the event queue when the script asks for it. The root also records the broadcasts of
  focus that its subviews send to it. }
program t_views;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Classes, SysUtils, TvGeom, TvKeys, TvEvents, TvSys, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvTimer, TvViews;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 20;
  { No wait of these tests lasts longer than this, so that a failure ends the program. }
  Guard = 10000;
  { The key code of the letter a. }
  KeyA = Ord('a');

type
  PString = ^string;

  TFakeDisplay = class(TScreenBackend)
  public
    CaretSize: Word;
    procedure SetCaretSize(ASize: Word); override;
    function GetCaretSize: Word; override;
  end;

  { Draws its character on all its cells and writes what it sees to EvLog. }
  TBox = class(TView)
  public
    Ch: Char;
    Tag: string;
    Pal: TPalette;
    DrawCount: Integer;
    HandleCount: Integer;
    AwakenCount: Integer;
    ClearIt: Boolean;
    RejectCmd: Word;
    constructor Create(const R: TRect; const ATag: string; AChar: Char);
    destructor Destroy; override;
    procedure Draw; override;
    procedure Awaken; override;
    function GetPalette: TPalette; override;
    function Valid(Command: Word): Boolean; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { Draws nothing. }
  TQuiet = class(TView)
  public
    procedure Draw; override;
  end;

  TLimited = class(TBox)
  public
    procedure SizeLimits(var Min, Max: TPoint); override;
  end;

  TDataBox = class(TBox)
  public
    Value: LongInt;
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    procedure SetData(Rec: Pointer); override;
  end;

  TPalGroup = class(TGroup)
  public
    function GetPalette: TPalette; override;
  end;

  { The root of the views: reads a script of events, or the events that are posted to the event queue. }
  TRoot = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    UseQueue: Boolean;
    CancelWhenDry: Boolean;
    Deadline: Int64;
    ErrorCount: Integer;
    PutCount: Integer;
    LastPut: TEvent;
    SeenTimeout: Integer;
    TimerAnswer: Pointer;
    KilledId: Pointer;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure PutEvent(var Event: TEvent); override;
    procedure EventError(var Event: TEvent); override;
    function GetPalette: TPalette; override;
    function SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer): TTimerId; override;
    procedure KillTimer(Id: TTimerId); override;
  end;

  { Records the event that it gets, and clears it while ClearIt is set. }
  TRecorder = class(TView)
  public
    Calls: Integer;
    SeenWhat: Word;
    SeenCommand: Word;
    SeenInfo: Pointer;
    ClearIt: Boolean;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { A view that ends its modal loop at a command. }
  TDlg = class(TGroup)
  public
    VetoOnce: Boolean;
    SawTop: Boolean;
    SawModal: Boolean;
    SawOptions: Word;
    Nested: TDlg;
    NestedResult: Word;
    Child: TView;
    ValidCalls: Integer;
    procedure HandleEvent(var Event: TEvent); override;
    function Valid(Command: Word): Boolean; override;
  end;

  TPoster = class(TThread)
  private
    FKind: Integer;
    FDelay: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AKind, ADelay: Integer);
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  CaretMoves, CaretX, CaretY: Integer;
  ScreenWrites: Integer;
  MsgLog: string;
  EvLog: string;
  DestroyCount: Integer;
  WakeFlag: LongInt;
  RootPal, BoxPal, GroupPal: TPalette;
  GetCalls: Integer;

{ The fake display and the hooks. }

procedure TFakeDisplay.SetCaretSize(ASize: Word);
begin
  CaretSize := ASize;
end;

function TFakeDisplay.GetCaretSize: Word;
begin
  Result := CaretSize;
end;

procedure OnCaret(X, Y: Integer);
begin
  CaretX := X;
  CaretY := Y;
  Inc(CaretMoves);
end;

procedure OnScreenWrite(X, Y: Integer; Buf: PScreenCell; Count: Integer);
begin
  Inc(ScreenWrites);
end;

function Now64: Int64;
begin
  Result := Int64(GetTickCount64);
end;

{ Small helpers. }

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function KeyEv(Code: Word; Shift: Word = 0): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Code;
  Result.KeyDown.ControlKeyState := Shift;
end;

function TextKeyEv(C: Char): TEvent;
begin
  Result := KeyEv(Ord(C));
  Result.KeyDown.Text[0] := Ord(C);
  Result.KeyDown.TextLength := 1;
end;

function CmdEv(Cmd: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evCommand;
  Result.Message.Command := Cmd;
end;

function MouseEv(What: Word; X, Y: Integer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := What;
  Result.Mouse.Where := Pt(X, Y);
  Result.Mouse.Buttons := mbLeftButton;
end;

function CharAt(X, Y: Integer): Char;
var
  S: string;
begin
  S := ScreenCells[Y * ScrW + X].Character.GetText;
  if Length(S) > 0 then
    Result := S[1]
  else
    Result := #0;
end;

function AttrAt(X, Y: Integer): TColorAttr;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute;
end;

function IsShadowed(X, Y: Integer): Boolean;
var
  A: TColorAttr;
begin
  A := AttrAt(X, Y);
  Result := (A.GetStyle and slWindowShadow) <> 0;
end;

function RowText(Y, X0, N: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to N - 1 do
    Result := Result + CharAt(X0 + I, Y);
end;

procedure ClearScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
end;

function ScreenIsClear: Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to ScrW * ScrH - 1 do
    if ScreenCells[I].Character.GetText <> #0 then
      Result := False;
end;

{ The views of the tests. }

constructor TBox.Create(const R: TRect; const ATag: string; AChar: Char);
begin
  inherited Create(R);
  Tag := ATag;
  Ch := AChar;
  Pal := BoxPal;
  RejectCmd := $FFFF;
end;

destructor TBox.Destroy;
begin
  Inc(DestroyCount);
  inherited Destroy;
end;

procedure TBox.Draw;
var
  Y: Integer;
begin
  Inc(DrawCount);
  for Y := 0 to Size.Y - 1 do
    WriteChar(0, Y, Ch, 1, Size.X);
end;

procedure TBox.Awaken;
begin
  Inc(AwakenCount);
end;

function TBox.GetPalette: TPalette;
begin
  Result := Pal;
end;

function TBox.Valid(Command: Word): Boolean;
begin
  Result := Command <> RejectCmd;
end;

procedure TBox.HandleEvent(var Event: TEvent);
var
  Letter: Char;
begin
  Inc(HandleCount);
  case Owner.Phase of
    phFocused:
      Letter := 'F';
    phPreProcess:
      Letter := 'P';
  else
    Letter := 'Q';
  end;
  EvLog := EvLog + Tag + ':' + Letter + ' ';
  if ClearIt then
    ClearEvent(Event)
  else
    inherited HandleEvent(Event);
end;

procedure TQuiet.Draw;
begin
end;

procedure TLimited.SizeLimits(var Min, Max: TPoint);
begin
  inherited SizeLimits(Min, Max);
  if Max.X > 8 then
    Max.X := 8;
end;

function TDataBox.DataSize: Word;
begin
  Result := SizeOf(LongInt);
end;

procedure TDataBox.GetData(Rec: Pointer);
begin
  PLongInt(Rec)^ := Value;
end;

procedure TDataBox.SetData(Rec: Pointer);
begin
  Value := PLongInt(Rec)^;
end;

function TPalGroup.GetPalette: TPalette;
begin
  Result := GroupPal;
end;

procedure TRecorder.HandleEvent(var Event: TEvent);
begin
  Inc(Calls);
  SeenWhat := Event.What;
  SeenCommand := Event.Message.Command;
  SeenInfo := Event.Message.InfoPtr;
  if ClearIt then
    ClearEvent(Event);
end;

procedure TRoot.HandleEvent(var Event: TEvent);
var
  Mark: string;
  Command: Word;
begin
  Command := Event.Message.Command;
  if (Event.What = evBroadcast) and ((Command = cmReceivedFocus) or (Command = cmReleasedFocus)) and
     (Event.Message.InfoPtr <> nil) and (TObject(Event.Message.InfoPtr) is TBox) then
  begin
    if Command = cmReceivedFocus then
      Mark := '=in '
    else
      Mark := '=out ';
    MsgLog := MsgLog + TBox(Event.Message.InfoPtr).Tag + Mark;
  end;
  inherited HandleEvent(Event);
end;

procedure TRoot.AddEvent(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TRoot.GetEvent(var Event: TEvent);
begin
  Inc(GetCalls);
  if GetCalls > 200000 then
  begin
    WriteLn('FAIL a loop of events does not end');
    Halt(1);
  end;
  SeenTimeout := EventTimeoutMs;
  FillChar(Event, SizeOf(Event), 0);
  if ScriptPos <= High(Script) then
  begin
    Event := Script[ScriptPos];
    Inc(ScriptPos);
  end
  else if CancelWhenDry then
    Event := CmdEv(cmCancel)
  else if UseQueue then
  begin
    if TEventQueue.GetPostedEvent(Event) then
      Exit;
    FillChar(Event, SizeOf(Event), 0);
    if InterlockedExchange(WakeFlag, 0) <> 0 then
      Event := CmdEv(cmOK)
    else if Now64 > Deadline then
      Event := CmdEv(cmCancel)
    else
      TEventQueue.WaitForEvents(Guard);
  end;
end;

procedure TRoot.PutEvent(var Event: TEvent);
begin
  Inc(PutCount);
  LastPut := Event;
end;

procedure TRoot.EventError(var Event: TEvent);
begin
  Inc(ErrorCount);
end;

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
end;

function TRoot.SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer): TTimerId;
begin
  Result := TimerAnswer;
end;

procedure TRoot.KillTimer(Id: TTimerId);
begin
  KilledId := Id;
end;

procedure TDlg.HandleEvent(var Event: TEvent);
var
  Cmd: Word;
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;
  Cmd := Event.Message.Command;
  if (Cmd = cmOK) or (Cmd = cmCancel) or (Cmd = cmYes) then
  begin
    SawModal := GetState(sfModal);
    SawTop := TheTopView = Self;
    SawOptions := Options;
    ClearEvent(Event);
    EndModal(Cmd);
  end
  else if Cmd = cmNew then
  begin
    ClearEvent(Event);
    NestedResult := Owner.ExecView(Nested);
  end
  else if Cmd = cmClose then
  begin
    ClearEvent(Event);
    Child.EndModal(cmYes);
  end
  else if Cmd = cmCut then
  begin
    ClearEvent(Event);
    TView.DisableCommand(cmCopy);
  end;
end;

function TDlg.Valid(Command: Word): Boolean;
begin
  Inc(ValidCalls);
  if (Command = cmOK) and VetoOnce then
  begin
    VetoOnce := False;
    Result := False;
  end
  else
    Result := inherited Valid(Command);
end;

constructor TPoster.Create(AKind, ADelay: Integer);
begin
  FKind := AKind;
  FDelay := ADelay;
  inherited Create(False);
end;

procedure TPoster.Execute;
var
  Ev: TEvent;
begin
  if FDelay > 0 then
    Sleep(FDelay);
  case FKind of
    0:
      begin
        Ev := CmdEv(cmOK);
        TEventQueue.PostEvent(Ev);
      end;
    1:
      begin
        InterlockedExchange(WakeFlag, 1);
        TEventQueue.WakeUp;
      end;
  end;
end;

function NewRoot: TRoot;
begin
  ClearScreen;
  Result := TRoot.Create(Rc(0, 0, ScrW, ScrH));
  Result.Options := Result.Options and not ofBuffered;
  Result.Buffer := @ScreenCells[0];
  Result.State := Result.State or sfSelected;
  Result.SetState(sfExposed, True);
end;

procedure FreeRoot(R: TRoot);
begin
  TvObject.DestroyObject(R);
end;

{ ---- the tests ---- }

procedure TestConstants;
begin
  Check(sfVisible = $0001, 'sfVisible');
  Check(sfCursorVis = $0002, 'sfCursorVis');
  Check(sfCursorIns = $0004, 'sfCursorIns');
  Check(sfShadow = $0008, 'sfShadow');
  Check(sfActive = $0010, 'sfActive');
  Check(sfSelected = $0020, 'sfSelected');
  Check(sfFocused = $0040, 'sfFocused');
  Check(sfDragging = $0080, 'sfDragging');
  Check(sfDisabled = $0100, 'sfDisabled');
  Check(sfModal = $0200, 'sfModal');
  Check(sfDefault = $0400, 'sfDefault');
  Check(sfExposed = $0800, 'sfExposed');
  Check(ofSelectable = $0001, 'ofSelectable');
  Check(ofTopSelect = $0002, 'ofTopSelect');
  Check(ofFirstClick = $0004, 'ofFirstClick');
  Check(ofFramed = $0008, 'ofFramed');
  Check(ofPreProcess = $0010, 'ofPreProcess');
  Check(ofPostProcess = $0020, 'ofPostProcess');
  Check(ofBuffered = $0040, 'ofBuffered');
  Check(ofTileable = $0080, 'ofTileable');
  Check(ofCentered = (ofCenterX or ofCenterY), 'ofCentered is both centers');
  Check(ofCentered = $0300, 'ofCentered');
  Check(ofValidate = $0400, 'ofValidate');
  Check(gfGrowAll = (gfGrowLoX or gfGrowLoY or gfGrowHiX or gfGrowHiY), 'gfGrowAll');
  Check(gfGrowRel = $10, 'gfGrowRel');
  Check(gfFixed = $20, 'gfFixed');
  Check(dmLimitAll = $F0, 'dmLimitAll');
  Check(dmDragGrowLeft = $04, 'dmDragGrowLeft');
  Check(hcDragging = 1, 'hcDragging');
  Check(cmQuit = 1, 'cmQuit');
  Check(cmClose = 4, 'cmClose');
  Check(cmOK = 10, 'cmOK');
  Check(cmCancel = 11, 'cmCancel');
  Check(cmCloseAll = 37, 'cmCloseAll');
  Check(cmCut = 20, 'cmCut');
  Check(cmRedo = 27, 'cmRedo');
  Check(cmReceivedFocus = 50, 'cmReceivedFocus');
  Check(cmReleasedFocus = 51, 'cmReleasedFocus');
  Check(cmCommandSetChanged = 52, 'cmCommandSetChanged');
  Check(cmScreenChanged = 57, 'cmScreenChanged');
  Check(cmTimerExpired = 58, 'cmTimerExpired');
  Check(sbIndicator = 8, 'sbIndicator');
  Check(sbHandleKeyboard = 2, 'sbHandleKeyboard');
  Check(wfZoom = 8, 'wfZoom');
  Check(noHistory = $40, 'noHistory');
  Check(wpGrayWindow = 2, 'wpGrayWindow');
  Check(positionalEvents = $000F, 'positionalEvents leave out the wheel');
  Check(focusedEvents = $0110, 'focusedEvents');
end;

procedure TestCommandSet;
var
  S, T, U, V: TCommandSet;
  I, J: Integer;
  Ok: Boolean;
begin
  S := TCommandSet.Create;
  Check(S.IsEmpty, 'a new command set is empty');
  Check(not S.Has(0), 'a new command set has no command 0');
  S.EnableCmd(5);
  Check(S.Has(5), 'an enabled command is in the set');
  Check(not S.Has(4) and not S.Has(6), 'the neighbours of an enabled command are not');
  Check(not S.IsEmpty, 'a set with a command is not empty');
  S.DisableCmd(5);
  Check(not S.Has(5), 'a disabled command is not in the set');
  Check(S.IsEmpty, 'the set is empty again');

  Ok := True;
  for I := 0 to 255 do
  begin
    S := TCommandSet.Create;
    S.EnableCmd(I);
    for J := 0 to 255 do
      if S.Has(J) <> (J = I) then
        Ok := False;
  end;
  Check(Ok, 'every command from 0 to 255 has a bit of its own');

  S := TCommandSet.Create;
  S.EnableCmd(256);
  S.EnableCmd(-1);
  S.EnableCmd(1000);
  Check(S.IsEmpty, 'commands outside 0 to 255 are not added');
  Check(not S.Has(256) and not S.Has(-1) and not S.Has(1000), 'commands outside 0 to 255 are not in the set');

  T := TCommandSet.Create;
  T.EnableCmd(1);
  T.EnableCmd(2);
  T.EnableCmd(3);
  U := TCommandSet.Create;
  U.EnableCmd(3);
  U.EnableCmd(4);
  V := T * U;
  Check(V.Has(3) and not V.Has(1) and not V.Has(2) and not V.Has(4), 'the intersection');
  V := T + U;
  Check(V.Has(1) and V.Has(2) and V.Has(3) and V.Has(4) and not V.Has(5), 'the union');
  Check(T.Has(1) and not T.Has(4), 'the operands of the union and the intersection are kept');

  V := T;
  V.AndAssign(U);
  Check(V.Has(3) and not V.Has(1), 'AndAssign');
  V := T;
  V.OrAssign(U);
  Check(V.Has(4) and V.Has(1), 'OrAssign');
  V := T;
  V.DisableCmd(U);
  Check(V.Has(1) and V.Has(2) and not V.Has(3), 'DisableCmd of a set');
  V := T;
  V.EnableCmd(U);
  Check(V.Has(4) and V.Has(3), 'EnableCmd of a set');
  V := T;
  V.AddAssign(9);
  Check(V.Has(9), 'AddAssign of a command');
  V.SubAssign(9);
  Check(not V.Has(9), 'SubAssign of a command');
  V.AddAssign(U);
  Check(V.Has(4), 'AddAssign of a set');
  V.SubAssign(U);
  Check(not V.Has(4) and not V.Has(3), 'SubAssign of a set');

  V := T;
  Check(V = T, 'a copy is equal');
  V.EnableCmd(200);
  Check(V <> T, 'a set with one more command is not equal');
  Check(not (V = T), 'equality is false for different sets');
  Check(TCommandSet.Create = TCommandSet.Create, 'two empty sets are equal');
end;

procedure TestViewCommands;
var
  Saved, Mod1, Pair: TCommandSet;
begin
  TView.GetCommands(Saved);
  Check(TView.CommandEnabled(cmQuit), 'cmQuit is enabled at the start');
  Check(TView.CommandEnabled(cmOK), 'cmOK is enabled at the start');
  Check(not TView.CommandEnabled(cmZoom), 'cmZoom is disabled at the start');
  Check(not TView.CommandEnabled(cmClose), 'cmClose is disabled at the start');
  Check(not TView.CommandEnabled(cmResize), 'cmResize is disabled at the start');
  Check(not TView.CommandEnabled(cmNext), 'cmNext is disabled at the start');
  Check(not TView.CommandEnabled(cmPrev), 'cmPrev is disabled at the start');
  Check(TView.CommandEnabled(300), 'a command above 255 is always enabled');
  Check(TView.CommandEnabled(cmTimerExpired), 'cmTimerExpired is enabled');

  TView.CommandSetChanged := False;
  TView.DisableCommand(cmOK);
  Check(not TView.CommandEnabled(cmOK), 'a disabled command is disabled');
  Check(TView.CommandSetChanged, 'disabling an enabled command is a change');
  TView.CommandSetChanged := False;
  TView.DisableCommand(cmOK);
  Check(not TView.CommandSetChanged, 'disabling a disabled command is no change');
  TView.EnableCommand(cmOK);
  Check(TView.CommandEnabled(cmOK), 'an enabled command is enabled');
  Check(TView.CommandSetChanged, 'enabling a disabled command is a change');
  TView.CommandSetChanged := False;
  TView.EnableCommand(cmOK);
  Check(not TView.CommandSetChanged, 'enabling an enabled command is no change');

  Pair := TCommandSet.Create;
  Pair.EnableCmd(cmZoom);
  Pair.EnableCmd(cmClose);
  TView.SetCmdState(Pair, True);
  Check(TView.CommandEnabled(cmZoom) and TView.CommandEnabled(cmClose), 'SetCmdState enables');
  Check(TView.CommandSetChanged, 'enabling a set of disabled commands is a change');
  TView.CommandSetChanged := False;
  TView.EnableCommands(Pair);
  Check(not TView.CommandSetChanged, 'enabling a set that is enabled is no change');
  TView.SetCmdState(Pair, False);
  Check(not TView.CommandEnabled(cmZoom) and not TView.CommandEnabled(cmClose), 'SetCmdState disables');
  Check(TView.CommandSetChanged, 'disabling a set of enabled commands is a change');
  TView.CommandSetChanged := False;
  TView.DisableCommands(Pair);
  Check(not TView.CommandSetChanged, 'disabling a set that is disabled is no change');

  TView.GetCommands(Mod1);
  Check(Mod1 = Saved, 'the commands are back to the start');
  Mod1.EnableCmd(cmZoom);
  TView.SetCommands(Mod1);
  Check(TView.CommandEnabled(cmZoom), 'SetCommands changes the commands');
  Check(TView.CommandSetChanged, 'SetCommands to another set is a change');
  TView.CommandSetChanged := False;
  TView.SetCommands(Mod1);
  Check(not TView.CommandSetChanged, 'SetCommands to the same set is no change');
  TView.SetCommands(Saved);
  TView.CommandSetChanged := False;
end;

procedure TestBounds;
var
  V: TView;
  Root: TRoot;
  G: TGroup;
  Q: TQuiet;
  Ev: TEvent;
begin
  V := TView.Create(Rc(2, 3, 12, 8));
  Check(V.Origin = Pt(2, 3), 'origin');
  Check(V.Size = Pt(10, 5), 'size');
  Check(V.GetBounds = Rc(2, 3, 12, 8), 'GetBounds');
  Check(V.GetExtent = Rc(0, 0, 10, 5), 'GetExtent');
  Check(V.State = sfVisible, 'a new view is visible and nothing else');
  Check(V.Options = 0, 'a new view has no options');
  Check(V.EventMask = (evMouseDown or evKeyDown or evCommand), 'the event mask of a new view');
  Check(V.GrowMode = 0, 'a new view has no grow mode');
  Check(V.DragMode = dmLimitLoY, 'the drag mode of a new view');
  Check(V.HelpCtx = hcNoContext, 'a new view has no help context');
  Check(V.Cursor = Pt(0, 0), 'the cursor of a new view');
  Check((V.Owner = nil) and (V.Next = nil), 'a new view has no owner and no next view');
  V.SetBounds(Rc(1, 1, 4, 4));
  Check((V.Origin = Pt(1, 1)) and (V.Size = Pt(3, 3)), 'SetBounds');
  V.MoveTo(5, 6);
  Check((V.Origin = Pt(5, 6)) and (V.Size = Pt(3, 3)), 'MoveTo keeps the size');
  V.GrowTo(4, 2);
  Check((V.Origin = Pt(5, 6)) and (V.Size = Pt(4, 2)), 'GrowTo keeps the origin');
  V.GrowTo(-5, -5);
  Check(V.Size = Pt(0, 0), 'a size cannot go below the minimum');
  V.Free;

  Root := NewRoot;
  G := TGroup.Create(Rc(5, 3, 25, 13));
  Root.Insert(G);
  Q := TQuiet.Create(Rc(2, 1, 6, 3));
  G.Insert(Q);
  Check(Q.MakeGlobal(Pt(1, 1)) = Pt(8, 5), 'MakeGlobal adds the origins of all owners');
  Check(Q.MakeLocal(Pt(8, 5)) = Pt(1, 1), 'MakeLocal subtracts the origins of all owners');
  Check(Q.MouseInView(Pt(7, 4)), 'a mouse at the first cell is in the view');
  Check(Q.MouseInView(Pt(10, 5)), 'a mouse at the last cell is in the view');
  Check(not Q.MouseInView(Pt(11, 4)), 'a mouse to the right of the view is not in it');
  Check(not Q.MouseInView(Pt(7, 6)), 'a mouse below the view is not in it');
  Check(not Q.MouseInView(Pt(6, 4)), 'a mouse to the left of the view is not in it');
  Ev := MouseEv(evMouseDown, 7, 4);
  Check(Q.ContainsMouse(Ev), 'ContainsMouse of a visible view');
  Q.Hide;
  Check(not Q.ContainsMouse(Ev), 'ContainsMouse of a hidden view');
  Q.Show;
  Q.GrowTo(100, 100);
  Check(Q.Size = Pt(20, 10), 'a view cannot grow beyond its owner');
  Q.MoveTo(3, 4);
  Check(Q.Origin = Pt(3, 4), 'MoveTo in a group');
  Check(Q.GetClipRect = Rc(0, 0, 17, 6), 'GetClipRect is the part of the view inside the clip of its owner');
  FreeRoot(Root);
end;

procedure TestStateAndHide;
var
  Root: TRoot;
  BG, Box: TBox;
begin
  Root := NewRoot;
  BG := TBox.Create(Rc(0, 0, ScrW, ScrH), 'bg', '.');
  Root.Insert(BG);
  Check((CharAt(0, 0) = '.') and (CharAt(ScrW - 1, ScrH - 1) = '.'), 'the background is drawn when it is inserted');
  Box := TBox.Create(Rc(4, 2, 9, 5), 'box', 'B');
  Root.Insert(Box);
  Check((CharAt(4, 2) = 'B') and (CharAt(8, 4) = 'B'), 'a view is drawn when it is inserted');
  Check((CharAt(9, 4) = '.') and (CharAt(3, 2) = '.') and (CharAt(4, 5) = '.'), 'a view does not draw outside itself');
  Check(Box.GetState(sfExposed), 'an inserted view is exposed');
  Box.Hide;
  Check(not Box.GetState(sfVisible), 'a hidden view is not visible');
  Check(not Box.GetState(sfExposed), 'a hidden view is not exposed');
  Check(CharAt(4, 2) = '.', 'a hidden view shows what is behind it');
  Box.Hide;
  Check(not Box.GetState(sfVisible), 'hiding twice is the same');
  Box.Show;
  Check(Box.GetState(sfVisible) and Box.GetState(sfExposed), 'a shown view is visible and exposed');
  Check(CharAt(4, 2) = 'B', 'a shown view is drawn');
  Box.SetState(sfDisabled, True);
  Check(Box.GetState(sfDisabled), 'the disabled state is set');
  Check(Box.GetState(sfDisabled or sfVisible), 'GetState of two states that are set');
  Check(not Box.GetState(sfDisabled or sfFocused), 'GetState of two states of which one is not set');
  Box.SetState(sfDisabled, False);
  Check(not Box.GetState(sfDisabled), 'the disabled state is cleared');
  Box.SetState(sfActive, True);
  Check(Box.GetState(sfActive), 'the active state is set');
  Box.SetState(sfActive, False);
  FreeRoot(Root);
end;

procedure TestHierarchy;
var
  Root, Root2: TRoot;
  A, B, C, D, E, X: TQuiet;
begin
  Root := NewRoot;
  A := TQuiet.Create(Rc(0, 0, 3, 3));
  B := TQuiet.Create(Rc(0, 0, 3, 3));
  C := TQuiet.Create(Rc(0, 0, 3, 3));
  Check(Root.First = nil, 'a new group has no first view');
  Check(Root.Last = nil, 'a new group has no last view');
  Root.Insert(A);
  Check((Root.First = A) and (Root.Last = A) and (A.Next = A), 'one view is first, last and its own next');
  Root.Insert(B);
  Root.Insert(C);
  Check(Root.First = C, 'the view inserted last is the first');
  Check(Root.Last = A, 'the view inserted first is the last');
  Check((C.Next = B) and (B.Next = A) and (A.Next = C), 'the views form a ring');
  Check((C.NextView = B) and (B.NextView = A) and (A.NextView = nil), 'NextView walks from the first to the last');
  Check((A.PrevView = B) and (B.PrevView = C) and (C.PrevView = nil), 'PrevView walks from the last to the first');
  Check((B.Prev = C) and (C.Prev = A) and (A.Prev = B), 'Prev is the previous view of the ring');
  Check(A.Owner = Root, 'the owner of an inserted view');
  Check((Root.IndexOf(C) = 1) and (Root.IndexOf(B) = 2) and (Root.IndexOf(A) = 3), 'IndexOf counts from the first view');
  Check(Root.IndexOf(nil) = 0, 'IndexOf nil is 0');
  Check(Root.IndexOf(Root) = 0, 'IndexOf a view that is not a subview is 0');
  Check((Root.At(1) = C) and (Root.At(2) = B) and (Root.At(3) = A), 'At counts from the first view');
  Check((Root.At(0) = nil) and (Root.At(4) = nil) and (Root.At(-1) = nil), 'At outside the views is nil');

  B.MakeFirst;
  Check(Root.First = B, 'MakeFirst puts a view first');
  Check((B.Next = C) and (C.Next = A) and (A.Next = B) and (Root.Last = A), 'the ring after MakeFirst');
  C.PutInFrontOf(nil);
  Check(Root.Last = C, 'PutInFrontOf nil puts a view last');
  Check((Root.First = B) and (B.Next = A) and (A.Next = C) and (C.Next = B), 'the ring after PutInFrontOf nil');
  C.PutInFrontOf(A);
  Check((B.Next = C) and (C.Next = A) and (Root.Last = A), 'PutInFrontOf puts a view before another');
  A.PutInFrontOf(A);
  Check((B.Next = C) and (C.Next = A), 'PutInFrontOf itself changes nothing');
  X := TQuiet.Create(Rc(0, 0, 3, 3));
  A.PutInFrontOf(X);
  Check((B.Next = C) and (C.Next = A), 'PutInFrontOf a view that is not in the group changes nothing');
  X.Free;

  Root.Remove(C);
  Check((C.Owner = nil) and (C.Next = nil), 'a removed view has no owner and no next view');
  Check((Root.IndexOf(C) = 0) and (Root.First = B) and (B.Next = A) and (A.Next = B), 'the ring after Remove');
  Check(C.GetState(sfVisible), 'a removed view that was visible is visible');
  Root.Remove(nil);
  Root.RemoveView(C);
  Check((Root.First = B) and (Root.Last = A), 'RemoveView of a view that is not in the group changes nothing');
  Root.Remove(A);
  Check((Root.First = B) and (Root.Last = B) and (B.Next = B), 'removing the last view');
  Root.Remove(B);
  Check((Root.First = nil) and (Root.Last = nil), 'removing the only view empties the group');

  Root.Insert(A);
  Root.Insert(B);
  Root.Insert(C);
  Root.Insert(A);
  Check(Root.IndexOf(C) = 1, 'inserting a view that has an owner changes nothing');
  D := TQuiet.Create(Rc(0, 0, 3, 3));
  Root.InsertBefore(D, A);
  Check((D.Owner = Root) and (D.Next = A) and (B.Next = D) and (Root.Last = A), 'InsertBefore puts a view before another');
  Root.InsertBefore(D, nil);
  Check(Root.IndexOf(D) = 3, 'InsertBefore of a view that has an owner changes nothing');
  Root2 := NewRoot;
  X := TQuiet.Create(Rc(0, 0, 3, 3));
  Root2.Insert(X);
  E := TQuiet.Create(Rc(0, 0, 3, 3));
  Root.InsertBefore(E, X);
  Check(E.Owner = nil, 'InsertBefore a view of another group inserts nothing');
  E.Options := ofCenterX or ofCenterY;
  E.SetBounds(Rc(0, 0, 4, 3));
  Root.Insert(E);
  Check(E.Origin = Pt((ScrW - 4) div 2, (ScrH - 3) div 2), 'ofCenterX and ofCenterY center a view in its owner');
  E.Options := 0;
  FreeRoot(Root2);
  FreeRoot(Root);
end;

procedure CollectTags(P: TView; Args: Pointer);
begin
  PString(Args)^ := PString(Args)^ + TBox(P).Tag;
end;

function IsTag(P: TView; Args: Pointer): Boolean;
begin
  Result := TBox(P).Tag = PString(Args)^;
end;

procedure RemoveFrom(P: TView; Args: Pointer);
begin
  TGroup(Args).Remove(P);
end;

procedure TestIteration;
var
  Root: TRoot;
  A, B, C: TBox;
  S: string;
begin
  Root := NewRoot;
  A := TBox.Create(Rc(0, 0, 2, 2), 'a', 'a');
  B := TBox.Create(Rc(0, 0, 2, 2), 'b', 'b');
  C := TBox.Create(Rc(0, 0, 2, 2), 'c', 'c');
  S := 'x';
  Root.ForEach(@CollectTags, @S);
  Check(S = 'x', 'ForEach of an empty group calls nothing');
  Check(Root.FirstThat(@IsTag, @S) = nil, 'FirstThat of an empty group is nil');
  Root.Insert(A);
  Root.Insert(B);
  Root.Insert(C);
  S := '';
  Root.ForEach(@CollectTags, @S);
  Check(S = 'cba', 'ForEach goes from the first view to the last');
  S := 'b';
  Check(Root.FirstThat(@IsTag, @S) = B, 'FirstThat finds the view');
  S := 'z';
  Check(Root.FirstThat(@IsTag, @S) = nil, 'FirstThat is nil when no view fits');
  Root.ForEach(@RemoveFrom, Root);
  Check((Root.First = nil) and (Root.Last = nil), 'ForEach lets the called routine remove the view');
  Check(Root.DataSize = 0, 'the data size of an empty group is 0');
  A.Free;
  B.Free;
  C.Free;
  FreeRoot(Root);
end;

procedure TestFocus;
var
  Root, Root2: TRoot;
  BG: TQuiet;
  S1, S2, S3: TBox;
begin
  Root := NewRoot;
  MsgLog := '';
  BG := TQuiet.Create(Rc(0, 0, ScrW, ScrH));
  S1 := TBox.Create(Rc(0, 0, 4, 2), 'S1', '1');
  S2 := TBox.Create(Rc(5, 0, 9, 2), 'S2', '2');
  S3 := TBox.Create(Rc(10, 0, 14, 2), 'S3', '3');
  S1.Options := ofSelectable;
  S2.Options := ofSelectable;
  S3.Options := ofSelectable;
  Root.Insert(BG);
  Check(Root.Current = nil, 'a view that cannot be selected does not become current');
  Root.Insert(S1);
  Check(Root.Current = S1, 'the first selectable view becomes current');
  Check(S1.GetState(sfSelected), 'the current view is selected');
  Root.Insert(S2);
  Check(Root.Current = S2, 'a view that is inserted becomes current');
  Check(not S1.GetState(sfSelected) and S2.GetState(sfSelected), 'only the current view is selected');
  Root.Insert(S3);
  Check(Root.Current = S3, 'the view inserted last is current');
  Check(not S3.GetState(sfFocused), 'a view of a group that is not focused is not focused');
  Check(MsgLog = '', 'no message of focus is sent while the group is not focused');

  Root.SetState(sfFocused, True);
  Check(S3.GetState(sfFocused), 'the current view of a group that gets the focus is focused');
  Check(MsgLog = 'S3=in ', 'a view that is focused broadcasts cmReceivedFocus');
  MsgLog := '';
  Root.SelectNext(True);
  Check(Root.Current = S2, 'SelectNext goes to the next view');
  Check(MsgLog = 'S3=out S2=in ', 'the focus is released before it is received');
  Check(S2.GetState(sfFocused) and S2.GetState(sfSelected) and not S3.GetState(sfFocused), 'the states after SelectNext');
  Root.SelectNext(False);
  Check(Root.Current = S3, 'SelectNext backwards goes to the previous view');
  S1.Select;
  Check(Root.Current = S1, 'Select makes a view current');
  Root.SelectNext(True);
  Check(Root.Current = S3, 'SelectNext skips views that cannot be selected and wraps around');
  S2.SetState(sfDisabled, True);
  Root.SelectNext(True);
  Check(Root.Current = S1, 'SelectNext skips disabled views');
  S2.SetState(sfDisabled, False);
  S2.Hide;
  Check(Root.Current = S3, 'hiding a view selects the first view that can be selected');
  Root.SelectNext(False);
  Check(Root.Current = S1, 'SelectNext skips hidden views');
  S2.Show;
  Check(Root.Current = S3, 'showing a view selects the first view that can be selected');
  Check(Root.FocusNext(True), 'FocusNext is true when the next view takes the focus');
  Check(Root.Current = S2, 'FocusNext moves the focus');
  Check(S2.Focus, 'Focus of the current view is true');

  S1.Options := S1.Options or ofValidate;
  S1.RejectCmd := cmReleasedFocus;
  S1.Select;
  Check(Root.Current = S1, 'a view with ofValidate becomes current');
  Check(not S3.Focus, 'Focus is false when the current view does not release the focus');
  Check(Root.Current = S1, 'the current view stays when it does not release the focus');
  Check(not Root.Valid(cmReleasedFocus), 'the group asks the current view whether it releases the focus');
  Check(Root.Valid(cmOK), 'the group is valid when all views are');
  S3.RejectCmd := cmOK;
  Check(not Root.Valid(cmOK), 'the group is not valid when a view is not');
  S3.RejectCmd := $FFFF;
  S1.RejectCmd := $FFFF;
  Check(Root.Valid(cmReleasedFocus), 'the group releases the focus when the current view does');
  S1.Options := S1.Options and not ofValidate;
  S1.Select;

  Check(Root.GetHelpCtx = hcNoContext, 'no help context');
  S1.HelpCtx := 7;
  Check(Root.GetHelpCtx = 7, 'the help context of a group is the one of the current view');
  S1.SetState(sfDragging, True);
  Check(S1.GetHelpCtx = hcDragging, 'the help context of a view that is dragged');
  Check(Root.GetHelpCtx = hcDragging, 'the help context of a group is the one of a dragged current view');
  S1.SetState(sfDragging, False);
  S1.HelpCtx := hcNoContext;
  Root.HelpCtx := 9;
  Check(Root.GetHelpCtx = 9, 'a group with a current view that has none has its own help context');

  Root.SetState(sfActive, True);
  Check(S1.GetState(sfActive) and S2.GetState(sfActive) and S3.GetState(sfActive), 'sfActive goes to the subviews');
  Root.SetState(sfActive, False);
  Check(not S1.GetState(sfActive) and not S3.GetState(sfActive), 'sfActive is cleared in the subviews');
  Root.SetState(sfDragging, True);
  Check(S2.GetState(sfDragging), 'sfDragging goes to the subviews');
  Root.SetState(sfDragging, False);
  Root.SetState(sfFocused, False);
  Check(not S1.GetState(sfFocused), 'losing the focus goes to the current view');

  Root2 := NewRoot;
  BG := TQuiet.Create(Rc(0, 0, ScrW, ScrH));
  S1 := TBox.Create(Rc(0, 0, 4, 2), 'T1', '1');
  S1.Options := ofSelectable;
  Root2.Insert(BG);
  Root2.Insert(S1);
  Root2.SelectNext(True);
  Check(Root2.Current = S1, 'SelectNext with a single selectable view changes nothing');
  Check(Root2.FocusNext(True), 'FocusNext with a single selectable view is true');
  FreeRoot(Root2);
  FreeRoot(Root);
end;

procedure TestMessage;
var
  Root: TRoot;
  R: TRecorder;
  Box: TBox;
  Answer: Pointer;
  Marker: Integer;
begin
  Check(Message(nil, evBroadcast, cmOK, Pointer(@Marker)) = nil, 'a message to no view gets no answer');

  R := TRecorder.Create(Rc(0, 0, 1, 1));
  Answer := Message(R, evBroadcast, cmReceivedFocus, Pointer(@Marker));
  Check(R.Calls = 1, 'the receiver handles the message once');
  Check((R.SeenWhat = evBroadcast) and (R.SeenCommand = cmReceivedFocus) and (R.SeenInfo = Pointer(@Marker)),
    'the receiver gets the kind, the command and the information of the message');
  Check(Answer = nil, 'a message that the receiver leaves as it is gets no answer');

  Answer := Message(R, evBroadcast, cmOK, nil);
  Check((R.Calls = 2) and (R.SeenInfo = nil) and (Answer = nil), 'a message with no information');

  R.ClearIt := True;
  Answer := Message(R, evCommand, cmOK, Pointer(@Marker));
  Check((R.Calls = 3) and (R.SeenWhat = evCommand) and (R.SeenCommand = cmOK), 'a command is sent as it is');
  Check(Answer = Pointer(R), 'a message that the receiver clears is answered with the view that cleared it');
  R.Free;

  Root := NewRoot;
  Box := TBox.Create(Rc(0, 0, 2, 2), 'm', 'm');
  Box.EventMask := evBroadcast;
  Root.Insert(Box);
  EvLog := '';
  Answer := Message(Root, evBroadcast, cmOK, nil);
  Check(EvLog = 'm:F ', 'a message to a group goes to the subviews that take it');
  Check(Answer = nil, 'a message that no subview clears gets no answer');
  Box.ClearIt := True;
  EvLog := '';
  Answer := Message(Root, evBroadcast, cmOK, nil);
  Check((EvLog = 'm:F ') and (Answer = Pointer(Box)), 'a subview that clears the message answers with itself');
  Box.EventMask := evMouseDown;
  EvLog := '';
  Answer := Message(Root, evBroadcast, cmOK, nil);
  Check((EvLog = '') and (Answer = nil), 'a subview that does not take broadcasts is not asked');
  FreeRoot(Root);
end;

procedure TestLock;
var
  Root: TRoot;
  G, G2, G3, G4: TGroup;
  Box, Box3: TBox;
  Before: Integer;
begin
  Root := NewRoot;
  G := TGroup.Create(Rc(2, 2, 10, 6));
  Box := TBox.Create(Rc(0, 0, 3, 1), 'x', 'x');
  G.Insert(Box);
  Root.Insert(G);
  Check(G.Buffer <> nil, 'a group that is exposed has a buffer');
  Check(CharAt(2, 2) = 'x', 'a group draws its subviews');
  Check(G.LockFlag = 0, 'a group is not locked');
  G.Lock;
  G.Lock;
  Check(G.LockFlag = 2, 'Lock counts');
  Box.Ch := 'y';
  Box.DrawView;
  Check(CharAt(2, 2) = 'x', 'the screen is not changed while the group is locked');
  Check(G.Buffer^.Character.GetText = 'y', 'the buffer of the group is changed while it is locked');
  G.Unlock;
  Check(G.LockFlag = 1, 'Unlock counts');
  Check(CharAt(2, 2) = 'x', 'the screen is not changed while the group is still locked');
  G.Unlock;
  Check(G.LockFlag = 0, 'the group is unlocked');
  Check(CharAt(2, 2) = 'y', 'the screen is changed when the group is unlocked');
  G.Unlock;
  Check(G.LockFlag = 0, 'Unlock of a group that is not locked changes nothing');
  Before := Box.DrawCount;
  G.Redraw;
  Check(Box.DrawCount = Before + 1, 'Redraw draws the subviews');

  G.Hide;
  Check(G.Buffer = nil, 'a group that is hidden gives its buffer back');
  Check(not Box.GetState(sfExposed), 'the subviews of a group that is hidden are not exposed');
  Before := Box.DrawCount;
  G.Show;
  Check(G.Buffer <> nil, 'a group that is shown has a buffer');
  Check(Box.GetState(sfExposed) and (Box.DrawCount > Before), 'the subviews of a group that is shown are drawn');

  G2 := TGroup.Create(Rc(0, 0, 4, 4));
  G2.Options := G2.Options and not ofBuffered;
  G2.Lock;
  Check(G2.LockFlag = 0, 'Lock of a group with no buffer and no lock changes nothing');
  G2.LockFlag := 1;
  G2.Lock;
  Check(G2.LockFlag = 2, 'Lock of a group that is locked counts');
  G2.LockFlag := 0;
  G2.Free;

  G3 := TGroup.Create(Rc(12, 8, 20, 12));
  G3.Options := G3.Options and not ofBuffered;
  Box3 := TBox.Create(Rc(0, 0, 2, 1), 'z', 'z');
  G3.Insert(Box3);
  Root.Insert(G3);
  Check(G3.Buffer = nil, 'a group that is not buffered has no buffer');
  Check((CharAt(12, 8) = 'z') and (CharAt(13, 8) = 'z'), 'a group that is not buffered draws through its owner');

  G4 := TGroup.Create(Rc(0, 0, 8, 4));
  G4.GetBuffer;
  Check(G4.Buffer = nil, 'a group that is not exposed gets no buffer');
  G4.State := G4.State or sfExposed;
  G4.GetBuffer;
  Check(G4.Buffer <> nil, 'a group that is exposed gets a buffer');
  G4.ChangeBounds(Rc(0, 0, 10, 5));
  Check(G4.Size = Pt(10, 5), 'ChangeBounds of a group');
  Check(G4.Clip = Rc(0, 0, 10, 5), 'the clip of a group is its extent after ChangeBounds');
  Check(G4.Buffer <> nil, 'a group keeps a buffer when it changes its size');
  G4.FreeBuffer;
  Check(G4.Buffer = nil, 'FreeBuffer gives the buffer back');
  G4.Free;
  FreeRoot(Root);
end;

procedure TestClipping;
var
  Root: TRoot;
  V: TQuiet;
  Buf4: array[0..3] of Word;
  Buf5: array[0..4] of Word;
  Buf3: array[0..2] of Word;
  Cells: array[0..2] of TScreenCell;
  DB: TDrawBuffer;
  I: Integer;
  S: string;
begin
  Root := NewRoot;
  V := TQuiet.Create(Rc(3, 2, 9, 5));
  Root.Insert(V);
  ClearScreen;
  ScreenWrites := 0;

  Buf4[0] := $1F41;
  Buf4[1] := $1F42;
  Buf4[2] := $1F43;
  Buf4[3] := $1F44;
  V.WriteBuf(1, 0, 4, 1, Pointer(@Buf4[0]));
  Check(RowText(2, 4, 4) = 'ABCD', 'WriteBuf puts the cells at the origin of the view');
  Check(AttrAt(4, 2) = $1F, 'WriteBuf puts the attribute');
  Check((CharAt(3, 2) = #0) and (CharAt(8, 2) = #0), 'WriteBuf writes nothing outside the cells');
  Check(ScreenWrites > 0, 'a write that reaches the screen buffer is written to the display');

  ClearScreen;
  for I := 0 to 4 do
    Buf5[I] := $1F61 + I;
  V.WriteBuf(-2, 1, 5, 1, Pointer(@Buf5[0]));
  Check(RowText(3, 3, 3) = 'cde', 'a write that starts left of the view starts at its left edge');
  Check(CharAt(2, 3) = #0, 'nothing is written left of the view');

  ClearScreen;
  V.WriteBuf(4, 0, 5, 1, Pointer(@Buf5[0]));
  Check(RowText(2, 7, 2) = 'ab', 'a write that ends right of the view ends at its right edge');
  Check(CharAt(9, 2) = #0, 'nothing is written right of the view');

  ClearScreen;
  ScreenWrites := 0;
  V.WriteBuf(0, -1, 3, 1, Pointer(@Buf5[0]));
  V.WriteBuf(0, 3, 3, 1, Pointer(@Buf5[0]));
  V.WriteBuf(0, 0, 0, 1, Pointer(@Buf5[0]));
  V.WriteBuf(0, 0, 3, 0, Pointer(@Buf5[0]));
  Check(ScreenIsClear and (ScreenWrites = 0), 'rows outside the view and empty writes write nothing');

  ClearScreen;
  V.WriteLine(0, 2, 3, 2, Pointer(@Buf5[0]));
  Check(RowText(4, 3, 3) = 'abc', 'WriteLine writes the row where it fits');
  Check(RowText(5, 3, 3) = #0#0#0, 'WriteLine writes nothing below the view');

  ClearScreen;
  Buf4[0] := $1F31;
  Buf4[1] := $1F32;
  Buf4[2] := $1F33;
  Buf4[3] := $1F34;
  V.WriteBuf(0, 0, 2, 2, Pointer(@Buf4[0]));
  Check((RowText(2, 3, 2) = '12') and (RowText(3, 3, 2) = '34'), 'WriteBuf goes on with the next row of the buffer');

  ClearScreen;
  Buf3[0] := $1F78;
  Buf3[1] := $1F79;
  Buf3[2] := $1F7A;
  V.WriteLine(0, 0, 3, 3, Pointer(@Buf3[0]));
  Check((RowText(2, 3, 3) = 'xyz') and (RowText(3, 3, 3) = 'xyz') and (RowText(4, 3, 3) = 'xyz'),
    'WriteLine writes the same row again');

  ClearScreen;
  for I := 0 to 2 do
    Cells[I] := TScreenCell.Create(Word($1E50 + I));
  V.WriteBuf(0, 0, 3, 1, PScreenCell(@Cells[0]));
  Check(RowText(2, 3, 3) = 'PQR', 'WriteBuf of cells');
  Check(AttrAt(3, 2) = $1E, 'WriteBuf of cells keeps the attributes');
  ClearScreen;
  V.WriteLine(1, 4, 2, 1, PScreenCell(@Cells[0]));
  Check(ScreenIsClear, 'a row outside the view is not written');

  ClearScreen;
  V.WriteChar(1, 1, '#', 1, 3);
  Check(RowText(3, 4, 3) = '###', 'WriteChar');
  Check(AttrAt(4, 3) = $1E, 'WriteChar maps the color through the palettes');
  V.WriteChar(0, 0, 'z', 1, 100);
  Check((RowText(2, 3, 6) = 'zzzzzz') and (CharAt(9, 2) = #0), 'WriteChar is cut to the width of the view');
  ScreenWrites := 0;
  V.WriteChar(0, 0, 'q', 1, 0);
  V.WriteChar(0, 0, 'q', 1, -3);
  Check(ScreenWrites = 0, 'WriteChar with no cells writes nothing');

  ClearScreen;
  V.WriteStr(0, 0, 'hello', 2);
  Check(RowText(2, 3, 5) = 'hello', 'WriteStr');
  Check(AttrAt(3, 2) = $2F, 'WriteStr maps the color');
  ClearScreen;
  V.WriteStr(0, 1, 'abcdefghij', 1);
  Check((RowText(3, 3, 6) = 'abcdef') and (CharAt(9, 3) = #0), 'WriteStr is cut to the width of the view');
  ClearScreen;
  S := 'a' + #$E4#$B8#$AD + 'b';
  V.WriteStr(0, 0, S, 1);
  Check((CharAt(3, 2) = 'a') and (CharAt(6, 2) = 'b'), 'WriteStr puts the characters of a text with a wide character');
  Check(ScreenCells[2 * ScrW + 4].Character.IsWide and ScreenCells[2 * ScrW + 5].Character.IsWideCharTrail,
    'a wide character takes two cells');
  V.WriteStr(0, 0, '', 1);

  ClearScreen;
  DB := TDrawBuffer.Create;
  DB.MoveStr(0, 'xyz', TColorAttr.Create($2A));
  V.WriteBuf(0, 0, 3, 1, DB);
  Check(RowText(2, 3, 3) = 'xyz', 'WriteBuf of a draw buffer');
  Check(AttrAt(3, 2) = $2A, 'WriteBuf of a draw buffer keeps the attributes');
  V.WriteLine(0, 1, 3, 2, DB);
  Check((RowText(3, 3, 3) = 'xyz') and (RowText(4, 3, 3) = 'xyz'), 'WriteLine of a draw buffer');
  DB.Free;

  ClearScreen;
  ScreenWrites := 0;
  V.Hide;
  V.WriteStr(0, 0, 'hidden', 1);
  V.WriteBuf(0, 0, 4, 1, Pointer(@Buf4[0]));
  Check(ScreenIsClear and (ScreenWrites = 0), 'a view that is hidden writes nothing');
  V.Show;
  FreeRoot(Root);

  Root := NewRoot;
  FreeRoot(Root);

  Root := NewRoot;
  Root.Insert(TView.Create(Rc(0, 0, 3, 2)));
  Check((CharAt(0, 0) = ' ') and (CharAt(2, 1) = ' ') and (CharAt(3, 0) = #0), 'the Draw of TView fills the view');
  Check((AttrAt(0, 0) = $1E) and (AttrAt(2, 1) = $1E), 'the Draw of TView uses color 1');
  FreeRoot(Root);
end;

procedure TestOverlap;
var
  Root: TRoot;
  A, B, C: TBox;
begin
  Root := NewRoot;
  A := TBox.Create(Rc(1, 1, 9, 5), 'a', 'a');
  C := TBox.Create(Rc(5, 3, 7, 4), 'c', 'c');
  B := TBox.Create(Rc(4, 2, 10, 5), 'b', 'b');
  Root.Insert(A);
  Root.Insert(C);
  Root.Insert(B);
  Check((CharAt(1, 1) = 'a') and (CharAt(8, 1) = 'a') and (CharAt(3, 2) = 'a'), 'the view behind shows where it is not covered');
  Check((CharAt(4, 2) = 'b') and (CharAt(9, 4) = 'b') and (CharAt(5, 3) = 'b'), 'the view in front covers the ones behind');
  Check(CharAt(9, 1) = #0, 'nothing is drawn where there is no view');
  A.DrawView;
  Check((CharAt(4, 2) = 'b') and (CharAt(5, 3) = 'b') and (CharAt(9, 4) = 'b'), 'a view behind does not draw over one in front');
  Check((CharAt(3, 3) = 'a') and (CharAt(3, 4) = 'a'), 'a view behind draws where it is not covered');
  Check(A.Exposed, 'a view that is partly covered is exposed');
  Check(B.Exposed, 'a view in front is exposed');
  Check(not C.Exposed, 'a view that is covered is not exposed');
  C.DrawView;
  Check(CharAt(5, 3) = 'b', 'a covered view draws nothing');
  B.Hide;
  Check(C.Exposed, 'a view is exposed when the view that covered it is hidden');
  Check((CharAt(5, 3) = 'c') and (CharAt(4, 2) = 'a'), 'hiding a view shows the views behind it');
  B.Show;
  Check((CharAt(5, 3) = 'b') and not C.Exposed, 'showing a view covers the views behind it');
  C.MakeFirst;
  Check((CharAt(5, 3) = 'c') and (CharAt(4, 3) = 'b'), 'MakeFirst brings a view to the front');
  C.PutInFrontOf(nil);
  Check(CharAt(5, 3) = 'b', 'PutInFrontOf nil sends a view to the back');
  Check(not C.Exposed, 'a view at the back that is covered is not exposed');

  B.MoveTo(12, 6);
  Check((CharAt(5, 3) = 'a') and (CharAt(4, 2) = 'a') and (CharAt(12, 6) = 'b'), 'moving a view redraws what it uncovers');
  Check(not C.Exposed, 'a view that is covered by another view is not exposed');
  FreeRoot(Root);
end;

procedure TestShadow;
var
  Root: TRoot;
  A, B: TBox;
  A2: TColorAttr;
begin
  Root := NewRoot;
  A := TBox.Create(Rc(1, 1, 9, 5), 'a', 'a');
  B := TBox.Create(Rc(3, 1, 7, 3), 'b', 'b');
  Root.Insert(A);
  Root.Insert(B);
  B.SetState(sfShadow, True);
  Check(B.GetState(sfShadow), 'the shadow state is set');
  Check(CharAt(7, 2) = 'a', 'the view behind a shadow is drawn');
  Check(IsShadowed(7, 2) and IsShadowed(8, 2), 'the right shadow starts one row below the top');
  Check(not IsShadowed(7, 1) and not IsShadowed(8, 1), 'the right shadow does not cover the first row');
  Check(IsShadowed(5, 3) and IsShadowed(8, 3), 'the shadow below the view');
  Check(not IsShadowed(4, 3) and not IsShadowed(1, 3), 'the shadow below starts two columns right of the view');
  Check(not IsShadowed(5, 4) and not IsShadowed(8, 4), 'the shadow is one row high');
  A2 := AttrAt(7, 2);
  Check(A2.ToBIOS = $08, 'the shadow has the attribute of the shadow');
  Check(not IsShadowed(5, 2) and (CharAt(5, 2) = 'b'), 'the view itself has no shadow');
  B.SetState(sfShadow, False);
  FreeRoot(Root);
end;

procedure TestCursor;
var
  Root: TRoot;
  G: TGroup;
  V, W, V2: TQuiet;
begin
  Root := NewRoot;
  V := TQuiet.Create(Rc(3, 2, 9, 5));
  Root.Insert(V);
  CaretMoves := 0;
  Fake.CaretSize := 99;
  V.SetState(sfFocused, True);
  Check(Fake.CaretSize = 0, 'a focused view with no visible cursor has no caret');
  Check(CaretMoves = 0, 'the caret is not moved when there is none');
  V.ShowCursor;
  Check(V.GetState(sfCursorVis), 'ShowCursor');
  Check(Fake.CaretSize = 20, 'the caret of a visible cursor has the size of the screen cursor');
  Check((CaretX = 3) and (CaretY = 2) and (CaretMoves = 1), 'the caret is at the cursor in global coordinates');
  V.SetCursor(2, 1);
  Check((CaretX = 5) and (CaretY = 3), 'SetCursor moves the caret');
  Check(V.Cursor = Pt(2, 1), 'SetCursor sets the cursor');
  V.BlockCursor;
  Check(Fake.CaretSize = 100, 'a block cursor has the size 100');
  V.NormalCursor;
  Check(Fake.CaretSize = 20, 'NormalCursor gives the normal size back');
  V.HideCursor;
  Check(Fake.CaretSize = 0, 'HideCursor removes the caret');
  V.ShowCursor;
  V.SetCursor(10, 0);
  Check(Fake.CaretSize = 0, 'a cursor outside the view has no caret');
  V.SetCursor(0, 0);
  Check(Fake.CaretSize = 20, 'a cursor inside the view has a caret');

  W := TQuiet.Create(Rc(3, 2, 5, 4));
  Root.Insert(W);
  V.DrawCursor;
  Check(Fake.CaretSize = 0, 'a cursor under another view has no caret');
  W.Hide;
  V.DrawCursor;
  Check(Fake.CaretSize = 20, 'a cursor that is no more under another view has a caret');
  V.SetState(sfFocused, False);
  Check(Fake.CaretSize = 0, 'a view that is not focused has no caret');
  V.SetState(sfFocused, True);
  Check(Fake.CaretSize = 20, 'a view that is focused has a caret');

  CaretMoves := 0;
  Root.Current := V;
  Root.ResetCursor;
  Check(CaretMoves = 1, 'the cursor of a group is the one of its current view');
  Root.Current := nil;
  Root.ResetCursor;
  Check(CaretMoves = 1, 'a group with no current view moves no caret');

  G := TGroup.Create(Rc(10, 5, 30, 15));
  Root.Insert(G);
  V2 := TQuiet.Create(Rc(1, 1, 8, 4));
  G.Insert(V2);
  V2.SetState(sfFocused, True);
  V2.ShowCursor;
  V2.SetCursor(2, 0);
  Check((CaretX = 13) and (CaretY = 6) and (Fake.CaretSize = 20), 'the caret of a view in a group');
  G.State := G.State and not sfVisible;
  V2.DrawCursor;
  Check(Fake.CaretSize = 0, 'a view in a group that is not visible has no caret');
  G.State := G.State or sfVisible;
  V2.DrawCursor;
  Check(Fake.CaretSize = 20, 'a view in a group that is visible has a caret');
  FreeRoot(Root);
end;

procedure TestPalette;
var
  Root: TRoot;
  G: TPalGroup;
  Box, Box2: TBox;
  Plain: TQuiet;
  Pair: TAttrPair;
  P1, P2, P3: TPalette;
  Zero: TPalette;
begin
  Root := NewRoot;
  Box := TBox.Create(Rc(0, 0, 4, 2), 'p', 'p');
  Root.Insert(Box);
  Check(Box.MapColor(1) = $2F, 'MapColor goes through the palette of the view and the root');
  Check(Box.MapColor(2) = $3A, 'MapColor of color 2');
  Check(Box.MapColor(3) = $1E, 'MapColor of color 3');
  Check(Box.MapColor(0) = $CF, 'MapColor of color 0 is the error attribute');
  Check(Box.MapColor(4) = $CF, 'MapColor of a color above the palette is the error attribute');
  Pair := Box.GetColor($0302);
  Check((Pair.Attrs[0] = $3A) and (Pair.Attrs[1] = $1E), 'GetColor of two colors');
  Pair := Box.GetColor(1);
  Check(Pair.Attrs[0] = $2F, 'GetColor of one color');
  Plain := TQuiet.Create(Rc(5, 0, 7, 1));
  Root.Insert(Plain);
  Check(Plain.MapColor(2) = $2F, 'a view with no palette maps colors through its owners');
  Check(Plain.GetPalette.Data <> nil, 'the palette of a view with no palette is empty, not missing');

  G := TPalGroup.Create(Rc(10, 5, 30, 15));
  Root.Insert(G);
  Box2 := TBox.Create(Rc(0, 0, 4, 2), 'q', 'q');
  G.Insert(Box2);
  Check(Box2.MapColor(1) = $1E, 'MapColor goes through the palettes of the view, of its group and of the root');
  Check(Box2.MapColor(2) = $CF, 'a color that is above the palette of the group is the error attribute');
  Check(Box2.MapColor(3) = $4B, 'MapColor of color 3 through the group');
  Zero := TPalette.Create(#0#1, 2);
  Box2.Pal := Zero;
  Check(Box2.MapColor(1) = $CF, 'an entry 0 is the error attribute');
  Check(Box2.MapColor(2) = $4B, 'an entry that is not 0 is mapped');
  Box2.Pal := BoxPal;
  Plain := TQuiet.Create(Rc(0, 5, 2, 6));
  G.Insert(Plain);
  Check(Plain.MapColor(1) = $4B, 'a view with no palette in a group with a palette');

  P1 := TPalette.Create(#10#20#30, 3);
  Check((P1[0] = 3) and (P1[1] = 10) and (P1[2] = 20) and (P1[3] = 30), 'a palette from a text');
  P2 := TPalette.Create(P1);
  Check(P2.Data <> P1.Data, 'a copy of a palette has its own entries');
  Check((P2[0] = 3) and (P2[2] = 20), 'a copy of a palette has the same entries');
  P2[2] := TColorAttr.Create(99);
  Check(P2[2] = 99, 'an entry is set');
  Check(P1[2] = 20, 'the original keeps its entries');
  P1.Assign(P2);
  Check(P1[2] = 99, 'Assign copies the entries');
  P3 := TPalette.Create([TColorAttr.Create(5), TColorAttr.Create(6)]);
  Check((P3[0] = 2) and (P3[1] = 5) and (P3[2] = 6), 'a palette from attributes');
  P1.Free;
  P2.Free;
  P3.Free;
  Zero.Free;
  Check(TView.ErrorAttr = $CF, 'the error attribute');
  Check(ShadowAttr = $08, 'the shadow attribute');
  Check(ShadowSize = Pt(2, 1), 'the size of the shadow');
  FreeRoot(Root);
end;

procedure TestGrow;
var
  Root: TRoot;
  G: TGroup;
  A, B, C, D, E, F: TBox;
  L: TLimited;
  NewB: TRect;
begin
  Root := NewRoot;
  G := TGroup.Create(Rc(0, 0, 20, 10));
  Root.Insert(G);
  A := TBox.Create(Rc(2, 2, 10, 5), 'a', 'a');
  A.GrowMode := gfGrowHiX;
  B := TBox.Create(Rc(2, 6, 10, 8), 'b', 'b');
  B.GrowMode := gfGrowHiY;
  C := TBox.Create(Rc(3, 1, 7, 2), 'c', 'c');
  C.GrowMode := gfGrowLoX or gfGrowHiX;
  D := TBox.Create(Rc(1, 1, 5, 3), 'd', 'd');
  D.GrowMode := gfGrowAll;
  E := TBox.Create(Rc(0, 0, 10, 1), 'e', 'e');
  E.GrowMode := gfGrowRel or gfGrowHiX;
  F := TBox.Create(Rc(3, 9, 6, 10), 'f', 'f');
  L := TLimited.Create(Rc(2, 3, 6, 4), 'l', 'l');
  L.GrowMode := gfGrowHiX;
  G.Insert(A);
  G.Insert(B);
  G.Insert(C);
  G.Insert(D);
  G.Insert(E);
  G.Insert(F);
  G.Insert(L);

  NewB := Rc(0, 0, 26, 14);
  G.Locate(NewB);
  Check(G.Size = Pt(26, 14), 'the group grows');
  Check(A.GetBounds = Rc(2, 2, 16, 5), 'gfGrowHiX moves the right edge');
  Check(B.GetBounds = Rc(2, 6, 10, 12), 'gfGrowHiY moves the bottom edge');
  Check(C.GetBounds = Rc(9, 1, 13, 2), 'gfGrowLoX and gfGrowHiX move the view');
  Check(D.GetBounds = Rc(7, 5, 11, 7), 'gfGrowAll moves the view in both directions');
  Check(E.GetBounds = Rc(0, 0, 13, 1), 'gfGrowRel grows in proportion');
  Check(F.GetBounds = Rc(3, 9, 6, 10), 'a view with no grow mode stays');
  Check(L.GetBounds = Rc(2, 3, 10, 4), 'a view is kept inside its size limits');

  NewB := Rc(0, 0, 20, 10);
  G.Locate(NewB);
  Check(A.GetBounds = Rc(2, 2, 10, 5), 'a view shrinks back (gfGrowHiX)');
  Check(B.GetBounds = Rc(2, 6, 10, 8), 'a view shrinks back (gfGrowHiY)');
  Check(C.GetBounds = Rc(3, 1, 7, 2), 'a view moves back');
  Check(D.GetBounds = Rc(1, 1, 5, 3), 'a view moves back in both directions');
  Check(E.GetBounds = Rc(0, 0, 10, 1), 'a view shrinks back in proportion');
  Check(F.GetBounds = Rc(3, 9, 6, 10), 'a view with no grow mode stays when the group shrinks');
  Check(L.GetBounds = Rc(2, 3, 6, 4), 'a view that was kept inside its limits gets its size back');

  NewB := Rc(2, 2, 22, 12);
  G.Locate(NewB);
  Check(G.Origin = Pt(2, 2), 'a group that moves');
  Check(A.GetBounds = Rc(2, 2, 10, 5), 'the views of a group that moves keep their bounds');
  FreeRoot(Root);
end;

procedure TestDrag;
var
  Root: TRoot;
  V: TQuiet;
  Ev: TEvent;
  Limits: TRect;
begin
  Root := NewRoot;
  V := TQuiet.Create(Rc(10, 5, 16, 8));
  Root.Insert(V);
  Limits := Rc(0, 0, ScrW, ScrH);

  Root.AddEvent(KeyEv(kbRight));
  Root.AddEvent(KeyEv(kbRight));
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEnter));
  Ev := KeyEv(kbRight);
  V.DragView(Ev, dmDragMove or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Origin = Pt(12, 6), 'dragging with the arrow keys moves the view');
  Check(V.Size = Pt(6, 3), 'dragging with the arrow keys keeps the size');
  Check(not V.GetState(sfDragging), 'a view is not dragged after the drag');

  Root.AddEvent(KeyEv(kbLeft));
  Root.AddEvent(KeyEv(kbLeft));
  Root.AddEvent(KeyEv(kbEsc));
  V.DragView(Ev, dmDragMove or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Origin = Pt(12, 6), 'Esc puts the view back');

  Root.AddEvent(KeyEv(kbCtrlRight));
  Root.AddEvent(KeyEv(kbCtrlDown));
  Root.AddEvent(KeyEv(kbEnter));
  V.DragView(Ev, dmDragMove or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Origin = Pt(20, 10), 'Ctrl moves the view by 8 columns and 4 rows');

  Root.AddEvent(KeyEv(kbHome));
  Root.AddEvent(KeyEv(kbEnter));
  V.DragView(Ev, dmDragMove or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Origin.X = 0, 'Home moves the view to the left limit');
  Root.AddEvent(KeyEv(kbEnd));
  Root.AddEvent(KeyEv(kbEnter));
  V.DragView(Ev, dmDragMove or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Origin.X = ScrW - 6, 'End moves the view to the right limit');
  Root.AddEvent(KeyEv(kbPgUp));
  Root.AddEvent(KeyEv(kbEnter));
  V.DragView(Ev, dmDragMove or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Origin.Y = 0, 'PgUp moves the view to the top limit');
  Root.AddEvent(KeyEv(kbPgDn));
  Root.AddEvent(KeyEv(kbEnter));
  V.DragView(Ev, dmDragMove or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Origin.Y = ScrH - 3, 'PgDn moves the view to the bottom limit');

  V.MoveTo(10, 5);
  Root.AddEvent(KeyEv(kbRight, kbLeftShift));
  Root.AddEvent(KeyEv(kbDown, kbLeftShift));
  Root.AddEvent(KeyEv(kbEnter));
  V.DragView(Ev, dmDragMove or dmDragGrow or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Size = Pt(7, 4), 'Shift and the arrow keys change the size');
  Check(V.Origin = Pt(10, 5), 'Shift and the arrow keys keep the origin');
  V.GrowTo(6, 3);

  V.MoveTo(3, 2);
  Root.AddEvent(MouseEv(evMouseMove, 10, 6));
  Root.AddEvent(MouseEv(evMouseUp, 10, 6));
  Ev := MouseEv(evMouseDown, 5, 3);
  V.DragView(Ev, dmDragMove or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Origin = Pt(8, 5), 'dragging with the mouse moves the view by the distance of the mouse');
  Check(V.Size = Pt(6, 3), 'dragging with the mouse keeps the size');

  V.MoveTo(3, 2);
  Root.AddEvent(MouseEv(evMouseMove, 12, 8));
  Root.AddEvent(MouseEv(evMouseUp, 12, 8));
  Ev := MouseEv(evMouseDown, 8, 4);
  V.DragView(Ev, dmDragGrow or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.Size = Pt(10, 7), 'dragging the corner with the mouse changes the size');
  Check(V.Origin = Pt(3, 2), 'dragging the corner with the mouse keeps the origin');

  V.SetBounds(Rc(10, 5, 16, 8));
  Root.AddEvent(MouseEv(evMouseMove, 6, 10));
  Root.AddEvent(MouseEv(evMouseUp, 6, 10));
  Ev := MouseEv(evMouseDown, 10, 8);
  V.DragView(Ev, dmDragGrowLeft or dmLimitAll, Limits, Pt(1, 1), Pt(ScrW, ScrH));
  Check(V.GetBounds = Rc(6, 5, 16, 10), 'dragging the left corner changes the left edge and the height');
  FreeRoot(Root);
end;

procedure TestEvents;
var
  Root: TRoot;
  BG: TView;
  W1, W2, Pre, Cur, Post, None, Inner: TBox;
  G: TGroup;
  Ev: TEvent;
begin
  Root := NewRoot;
  BG := TBox.Create(Rc(0, 0, ScrW, ScrH), 'bg', '.');
  Root.Insert(BG);
  W1 := TBox.Create(Rc(2, 2, 12, 7), 'w1', '1');
  W2 := TBox.Create(Rc(6, 4, 16, 9), 'w2', '2');
  W1.Options := ofSelectable;
  W2.Options := ofSelectable;
  Root.Insert(W1);
  Root.Insert(W2);

  EvLog := '';
  Ev := MouseEv(evMouseDown, 8, 5);
  Root.HandleEvent(Ev);
  Check(EvLog = 'w2:F ', 'a mouse event goes to the front view under the mouse');
  Check(Ev.What = evMouseDown, 'a view that is current does not take the mouse event');

  EvLog := '';
  Ev := MouseEv(evMouseDown, 3, 3);
  Root.HandleEvent(Ev);
  Check(EvLog = 'w1:F ', 'a mouse event goes to the only view under the mouse');
  Check(Ev.What = evNothing, 'a click on a view that is not current takes the event');
  Check(Root.Current = W1, 'a click on a view that is selectable makes it current');

  EvLog := '';
  Ev := MouseEv(evMouseDown, 30, 15);
  Root.HandleEvent(Ev);
  Check(EvLog = 'bg:F ', 'a mouse event outside the windows goes to the background');
  Check(Root.Current = W1, 'a click on a view that is not selectable keeps the current view');

  EvLog := '';
  Ev := MouseEv(evMouseUp, 3, 3);
  Root.HandleEvent(Ev);
  Check(EvLog = '', 'a view gets only the events of its event mask');

  W1.SetState(sfDisabled, True);
  EvLog := '';
  Ev := MouseEv(evMouseDown, 3, 3);
  Root.HandleEvent(Ev);
  Check(EvLog = '', 'a disabled view gets no mouse event, and the views behind it get none');
  W1.SetState(sfDisabled, False);
  W1.Hide;
  Ev := MouseEv(evMouseDown, 3, 3);
  Root.HandleEvent(Ev);
  Check(EvLog = 'bg:F ', 'a hidden view gets no mouse event');
  W1.Show;
  Ev.What := evNothing;
  EvLog := '';
  Root.HandleEvent(Ev);
  Check(EvLog = '', 'an empty event goes nowhere');
  FreeRoot(Root);

  Root := NewRoot;
  BG := TQuiet.Create(Rc(0, 0, ScrW, ScrH));
  None := TBox.Create(Rc(0, 0, 2, 2), 'none', 'n');
  Post := TBox.Create(Rc(0, 0, 2, 2), 'post', 'p');
  Pre := TBox.Create(Rc(0, 0, 2, 2), 'pre', 'r');
  Cur := TBox.Create(Rc(0, 0, 2, 2), 'cur', 'c');
  Post.Options := ofPostProcess;
  Pre.Options := ofPreProcess;
  Cur.Options := ofSelectable;
  Root.Insert(BG);
  Root.Insert(None);
  Root.Insert(Post);
  Root.Insert(Pre);
  Root.Insert(Cur);
  Check(Root.Current = Cur, 'the only selectable view is current');

  EvLog := '';
  Ev := KeyEv(KeyA);
  Root.HandleEvent(Ev);
  Check(EvLog = 'pre:P cur:F post:Q ', 'a key goes to the preprocess views, to the current view and to the postprocess views');
  EvLog := '';
  Ev := CmdEv(cmOK);
  Root.HandleEvent(Ev);
  Check(EvLog = 'pre:P cur:F post:Q ', 'a command goes the same way');

  Pre.ClearIt := True;
  EvLog := '';
  Ev := KeyEv(KeyA);
  Root.HandleEvent(Ev);
  Check(EvLog = 'pre:P ', 'a view that clears the event stops it');
  Check(Ev.What = evNothing, 'the cleared event is empty');
  Pre.ClearIt := False;

  Cur.SetState(sfDisabled, True);
  EvLog := '';
  Ev := KeyEv(KeyA);
  Root.HandleEvent(Ev);
  Check(EvLog = 'pre:P post:Q ', 'a disabled current view gets no key');
  Cur.SetState(sfDisabled, False);

  Cur.EventMask := $FFFF;
  Pre.EventMask := $FFFF;
  Post.EventMask := $FFFF;
  None.EventMask := $FFFF;
  EvLog := '';
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.What := evBroadcast;
  Root.HandleEvent(Ev);
  Check(EvLog = 'cur:F pre:F post:F none:F ', 'a broadcast goes to all views from the first to the last');
  FreeRoot(Root);

  Root := NewRoot;
  BG := TQuiet.Create(Rc(0, 0, ScrW, ScrH));
  G := TGroup.Create(Rc(0, 0, 10, 10));
  Inner := TBox.Create(Rc(0, 0, 3, 3), 'inner', 'i');
  Inner.Options := ofSelectable;
  G.Insert(Inner);
  Root.Insert(BG);
  Root.Insert(G);
  Check(Root.Current = G, 'a group that is inserted becomes current');
  EvLog := '';
  Ev := KeyEv(KeyA);
  Root.HandleEvent(Ev);
  Check(EvLog = 'inner:F ', 'a key goes to the current view of the current group');
  FreeRoot(Root);
end;

procedure TestViewEvents;
var
  Root: TRoot;
  V, Plain: TQuiet;
  Ev: TEvent;
  Buf: array[0..9] of Char;
  Len: SizeInt;
  S: string;
  Free1: TQuiet;
begin
  Root := NewRoot;
  V := TQuiet.Create(Rc(0, 0, 4, 2));
  Root.Insert(V);
  Ev := KeyEv(KeyA);
  V.ClearEvent(Ev);
  Check((Ev.What = evNothing) and (Ev.Message.InfoPtr = Pointer(V)), 'ClearEvent');

  EventTimeoutMs := 77;
  V.GetEvent(Ev, 123);
  Check(Root.SeenTimeout = 123, 'GetEvent with a time-out sets the time-out of the program while it reads');
  Check(EventTimeoutMs = 77, 'GetEvent with a time-out puts the time-out back');

  Root.AddEvent(MouseEv(evMouseMove, 1, 1));
  Root.AddEvent(KeyEv(kbF1));
  V.KeyEvent(Ev);
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbF1), 'KeyEvent skips events that are not keys');

  Root.PutCount := 0;
  Root.AddEvent(KeyEv(kbF2));
  Check(V.EventAvail, 'EventAvail is true when there is an event');
  Check((Root.PutCount = 1) and (Root.LastPut.KeyDown.KeyCode = kbF2), 'EventAvail puts the event back');
  Check(not V.EventAvail, 'EventAvail is false when there is no event');
  Check(Root.PutCount = 1, 'EventAvail puts nothing back when there is no event');

  Root.PutCount := 0;
  Root.AddEvent(TextKeyEv('a'));
  Root.AddEvent(TextKeyEv('b'));
  Root.AddEvent(KeyEv(kbEnter));
  Root.AddEvent(MouseEv(evMouseDown, 0, 0));
  Ev := TextKeyEv('x');
  Check(V.TextEvent(Ev, @Buf[0], 10, Len), 'TextEvent returns true when it got text');
  SetString(S, PChar(@Buf[0]), Len);
  Check(S = 'xab'#10, 'TextEvent collects the text of the events and an Enter as a line feed');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evMouseDown), 'TextEvent puts back the event that is not text');
  Check(Ev.What = evNothing, 'TextEvent leaves an empty event');

  Root.PutCount := 0;
  Root.AddEvent(TextKeyEv('a'));
  Root.AddEvent(TextKeyEv('b'));
  Ev := TextKeyEv('x');
  Check(V.TextEvent(Ev, @Buf[0], 2, Len), 'TextEvent with a small buffer returns true');
  SetString(S, PChar(@Buf[0]), Len);
  Check(S = 'xa', 'TextEvent stops when the text does not fit');
  Check((Root.PutCount = 1) and (Root.LastPut.KeyDown.Text[0] = Ord('b')), 'TextEvent puts back the text that does not fit');

  Root.PutCount := 0;
  Root.AddEvent(KeyEv(kbTab));
  Ev := MouseEv(evMouseDown, 0, 0);
  Check(V.TextEvent(Ev, @Buf[0], 10, Len), 'TextEvent takes a Tab from the next events');
  SetString(S, PChar(@Buf[0]), Len);
  Check(S = #9, 'a Tab is a tab character');
  Check(Root.PutCount = 0, 'a start event that is not text is not put back');

  Ev := KeyEv(kbF5);
  Check(not V.TextEvent(Ev, @Buf[0], 10, Len), 'TextEvent returns false when there is no text');
  Check(Len = 0, 'the length of no text is 0');

  Root.TimerAnswer := Pointer(1234);
  Check(V.SetTimer(100) = Pointer(1234), 'SetTimer asks the owners');
  V.KillTimer(Pointer(77));
  Check(Root.KilledId = Pointer(77), 'KillTimer asks the owners');
  Plain := TQuiet.Create(Rc(0, 0, 1, 1));
  Check(Plain.SetTimer(100) = nil, 'a view with no owner has no timer');
  Plain.KillTimer(Pointer(5));
  Plain.Free;

  Root.UseQueue := False;
  Free1 := TQuiet.Create(Rc(0, 0, 1, 1));
  Check(Free1.TopView = nil, 'the top view of a view that is not modal and has no modal owner is nil');
  Free1.Free;
  Check(V.TopView = nil, 'the top view of a view in a group that is not modal is nil');
  Root.State := Root.State or sfModal;
  Check(V.TopView = Root, 'the top view is the nearest owner that is modal');
  Root.State := Root.State and not sfModal;
  FreeRoot(Root);
end;

procedure TestData;
var
  Root: TRoot;
  G: TGroup;
  D1, D2: TDataBox;
  Plain: TBox;
  Rec, Out2: array[0..1] of LongInt;
  Awake: TBox;
begin
  Root := NewRoot;
  G := TGroup.Create(Rc(0, 0, 10, 10));
  D1 := TDataBox.Create(Rc(0, 0, 2, 1), 'd1', 'a');
  D2 := TDataBox.Create(Rc(0, 1, 2, 2), 'd2', 'b');
  Plain := TBox.Create(Rc(0, 2, 2, 3), 'pl', 'c');
  G.Insert(D1);
  G.Insert(Plain);
  G.Insert(D2);
  Root.Insert(G);
  Check(D1.DataSize = 4, 'the data size of a view with data');
  Check(Plain.DataSize = 0, 'the data size of a view is 0');
  Check(G.DataSize = 8, 'the data size of a group is the sum of its subviews');
  Rec[0] := 11;
  Rec[1] := 22;
  G.SetData(@Rec[0]);
  Check((D1.Value = 11) and (D2.Value = 22), 'SetData gives the record to the subviews in the order of insertion');
  D1.Value := 5;
  D2.Value := 6;
  G.GetData(@Out2[0]);
  Check((Out2[0] = 5) and (Out2[1] = 6), 'GetData collects the record in the order of insertion');

  Awake := TBox.Create(Rc(0, 0, 1, 1), 'aw', 'w');
  G.Insert(Awake);
  Root.Awaken;
  Check((Awake.AwakenCount = 1) and (Plain.AwakenCount = 1) and (D2.AwakenCount = 1), 'Awaken goes to the subviews of subgroups');
  FreeRoot(Root);
end;

procedure TestShutDown;
var
  Root: TRoot;
  G: TGroup;
  I: Integer;
begin
  Root := NewRoot;
  G := TGroup.Create(Rc(0, 0, 10, 10));
  for I := 1 to 3 do
    G.Insert(TBox.Create(Rc(0, I, 2, I + 1), 'x', 'x'));
  Root.Insert(G);
  Check(Root.IndexOf(G) = 1, 'the group is in its owner');
  DestroyCount := 0;
  TvObject.DestroyObject(G);
  Check(DestroyCount = 3, 'destroying a group destroys its subviews');
  Check(Root.First = nil, 'a destroyed group is removed from its owner');
  FreeRoot(Root);
end;

procedure TestExec;
var
  Root: TRoot;
  BG: TQuiet;
  D, D2, D3: TDlg;
  Chd: TBox;
  R: Word;
  Plain: TQuiet;
begin
  Root := NewRoot;
  Root.CancelWhenDry := True;
  BG := TQuiet.Create(Rc(0, 0, ScrW, ScrH));
  Root.Insert(BG);

  Check(Root.ExecView(nil) = cmCancel, 'ExecView of nil ends with cmCancel');

  D := TDlg.Create(Rc(5, 3, 25, 13));
  Root.AddEvent(KeyEv(KeyA));
  Root.AddEvent(CmdEv(cmOK));
  R := Root.ExecView(D);
  Check(R = cmOK, 'ExecView returns the command that ended the loop');
  Check(D.SawTop and D.SawModal, 'the view is the top view and is modal while it executes');
  Check((D.SawOptions and ofSelectable) = 0, 'the view cannot be selected while it executes');
  Check((D.Options and ofSelectable) <> 0, 'the options are back after ExecView');
  Check(TheTopView = nil, 'the top view is back after ExecView');
  Check(not D.GetState(sfModal), 'the view is not modal after ExecView');
  Check((D.Owner = nil) and (Root.IndexOf(D) = 0), 'a view that had no owner is removed after ExecView');
  Check(Root.ErrorCount = 1, 'an event that nobody handles goes to EventError');
  Check(Root.Current = nil, 'the current view is back after ExecView');

  D.VetoOnce := True;
  D.ValidCalls := 0;
  Root.AddEvent(CmdEv(cmOK));
  Root.AddEvent(CmdEv(cmCancel));
  R := Root.ExecView(D);
  Check(R = cmCancel, 'the loop goes on when the view is not valid');
  Check(D.ValidCalls = 2, 'the view is asked whether it is valid each time the loop would end');

  D2 := TDlg.Create(Rc(6, 4, 20, 10));
  D.Nested := D2;
  Root.AddEvent(CmdEv(cmNew));
  Root.AddEvent(CmdEv(cmYes));
  Root.AddEvent(CmdEv(cmCancel));
  R := Root.ExecView(D);
  Check(D.NestedResult = cmYes, 'a nested ExecView returns its own command');
  Check(R = cmCancel, 'the outer loop goes on after the nested one');
  Check(D2.SawTop, 'the nested view is the top view');
  Check(TheTopView = nil, 'the top view is back after nested ExecView calls');

  Chd := TBox.Create(Rc(0, 0, 2, 2), 'chd', 'k');
  D.Insert(Chd);
  D.Child := Chd;
  Root.AddEvent(CmdEv(cmClose));
  R := Root.ExecView(D);
  Check(R = cmYes, 'EndModal of a subview ends the loop of the top view');
  Check(Chd.TopView = nil, 'the top view is nil after the loop');

  Root.AddEvent(CmdEv(cmCut));
  Root.AddEvent(CmdEv(cmOK));
  TView.CommandSetChanged := False;
  Check(TView.CommandEnabled(cmCopy), 'cmCopy is enabled before');
  R := Root.ExecView(D);
  Check(TView.CommandEnabled(cmCopy), 'the commands are back after ExecView');
  Check(TView.CommandSetChanged, 'a change of the commands in ExecView is a change');
  TView.CommandSetChanged := False;

  D3 := TDlg.Create(Rc(2, 2, 12, 8));
  Root.Insert(D3);
  Root.AddEvent(CmdEv(cmOK));
  R := Root.ExecView(D3);
  Check(R = cmOK, 'ExecView of a view that has an owner');
  Check(D3.Owner = Root, 'a view that had an owner keeps it');
  Check(Root.IndexOf(D3) = 1, 'a view that had an owner stays in it');

  Plain := TQuiet.Create(Rc(0, 0, 2, 2));
  R := Root.ExecView(Plain);
  Check(R = cmCancel, 'ExecView of a view that does not execute ends with cmCancel');
  Check((Plain.Owner = nil) and not Plain.GetState(sfModal), 'the view is not in the group and not modal after ExecView');
  Plain.Free;
  TvObject.DestroyObject(D2);
  FreeRoot(Root);
end;

procedure TestThreads;
var
  Root: TRoot;
  D: TDlg;
  T: TPoster;
  Start: Int64;
  R: Word;
begin
  Root := NewRoot;
  Root.UseQueue := True;
  Root.Deadline := Now64 + 25000;
  D := TDlg.Create(Rc(5, 3, 25, 13));
  T := TPoster.Create(0, 250);
  Start := Now64;
  R := Root.ExecView(D);
  Check(R = cmOK, 'an event that is posted from a second thread during ExecView is delivered');
  Check(Now64 - Start < Guard - 1000, 'the posted event ended the wait');
  Check(Now64 - Start >= 150, 'the loop waited for the posted event');
  T.WaitFor;
  T.Free;
  Check(Root.ErrorCount = 0, 'the posted event was handled');

  TvObject.DestroyObject(D);
  D := TDlg.Create(Rc(5, 3, 25, 13));
  WakeFlag := 0;
  T := TPoster.Create(1, 250);
  Start := Now64;
  R := Root.ExecView(D);
  Check(R = cmOK, 'a wake-up from a second thread during ExecView ends the wait');
  Check(Now64 - Start < Guard - 1000, 'the wake-up ended the wait');
  T.WaitFor;
  T.Free;
  TvObject.DestroyObject(D);

  D := TDlg.Create(Rc(5, 3, 25, 13));
  T := TPoster.Create(0, 0);
  T.WaitFor;
  T.Free;
  Start := Now64;
  R := Root.ExecView(D);
  Check((R = cmOK) and (Now64 - Start < Guard - 1000), 'an event that was posted before ExecView is delivered at once');
  TvObject.DestroyObject(D);
  FreeRoot(Root);
end;

var
  EventBackend: TEventBackend;
  Queue: TEventQueue;
  SavedBackend: TScreenBackend;

begin
  RootPal := TPalette.Create([TColorAttr.Create($1E), TColorAttr.Create($2F), TColorAttr.Create($3A),
    TColorAttr.Create($4B)]);
  BoxPal := TPalette.Create(#2#3#1, 3);
  GroupPal := TPalette.Create(#4#1, 2);
  Fake := TFakeDisplay.Create;
  SavedBackend := TDisplay.Backend;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;
  EventBackend := TEventBackend.Create;
  TEventQueue.Backend := EventBackend;
  Queue := TEventQueue.Create;

  TestConstants;
  TestCommandSet;
  TestViewCommands;
  TestBounds;
  TestStateAndHide;
  TestHierarchy;
  TestIteration;
  TestFocus;
  TestMessage;
  TestLock;
  TestClipping;
  TestOverlap;
  TestShadow;
  TestCursor;
  TestPalette;
  TestGrow;
  TestDrag;
  TestEvents;
  TestViewEvents;
  TestData;
  TestShutDown;
  TestExec;
  TestThreads;

  Queue.Free;
  TEventQueue.Backend := nil;
  EventBackend.Free;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  Done;
end.
