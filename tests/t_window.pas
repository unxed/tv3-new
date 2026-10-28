{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/views.h (TFrame, TScrollBar, TScroller, TWindowInit, TWindow), source/tvision/tframe.cpp,
  source/tvision/framelin.cpp, source/tvision/tscrlbar.cpp, source/tvision/tscrolle.cpp, source/tvision/twindow.cpp,
  include/tvision/util.h, source/tvision/misc.cpp
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it. The
  root reads its events from a script, and from the posted events of the event queue when the script asks for it.
  The tables of TFrame and TScrollBar are checked against their values in the C++ and then set here to values that make each cell of the
  screen tell which mask or which character was used: the entry k of the masks of the lines is the character
  number k, and the character of the mask m is the letter number m after the letter A. The root and the windows
  count the messages of the scroll bars that they get. The colors of the root are the BIOS attributes $41 and
  above: the entry k of its palette is $40 + k. }
program t_window;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Classes, SysUtils, TvGeom, TvKeys, TvEvents, TvSys, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvTimer, TvViews,
  TvWindow;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 20;
  { No wait of these tests lasts longer than this, so that a failure ends the program. }
  Guard = 10000;

type
  TFakeDisplay = class(TScreenBackend)
  public
    CaretSize: Word;
    procedure SetCaretSize(ASize: Word); override;
    function GetCaretSize: Word; override;
  end;

  { The root of the views: reads a script of events, or the events that are posted to the event queue. With Requeue,
    an event that is put back is the next one that is read. }
  TRoot = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    UseQueue: Boolean;
    Deadline: Int64;
    Requeue: Boolean;
    Pending: TEvent;
    PutCount: Integer;
    LastPut: TEvent;
    ErrorCount: Integer;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure PutEvent(var Event: TEvent); override;
    procedure EventError(var Event: TEvent); override;
    function GetPalette: TPalette; override;
  end;

  TMyFrame = class(TFrame)
  public
    destructor Destroy; override;
  end;

  { A window that counts its destruction and can refuse to close. }
  TTestWin = class(TWindow)
  public
    RejectClose: Boolean;
    destructor Destroy; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Valid(Command: Word): Boolean; override;
  end;

  { A window with a title of its own. }
  TTitleWin = class(TTestWin)
  public
    Alt: PAnsiChar;
    LastMax: SmallInt;
    function GetTitle(MaxSize: SmallInt): PAnsiChar; override;
  end;

  { A window that ends its modal loop at cmOK and cmCancel. }
  TModalWin = class(TTestWin)
  public
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { A selectable view that draws nothing. }
  TSel = class(TView)
  public
    procedure Draw; override;
  end;

  TTestScroller = class(TScroller)
  public
    DrawCount: Integer;
    procedure Draw; override;
    function HBar: TScrollBar;
    function VBar: TScrollBar;
    function GetLimit: TPoint;
    function GetLock: Byte;
    function GetFlag: Boolean;
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
  GetCalls: Integer;
  WakeFlag: LongInt;
  RootPal: TPalette;
  WinDestroyCount: Integer;
  FrameDestroys: Integer;
  FactoryCalls: Integer;
  FactoryRect: TRect;
  ChangedCount, ClickedCount: Integer;
  LastInfo: Pointer;
  Dummy: Integer;

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
end;

procedure OnScreenWrite(X, Y: Integer; Buf: PScreenCell; Count: Integer);
begin
end;

{ Counts the messages of the scroll bars that an event brings: the changes, and the clicks. }
procedure CountMessage(const Event: TEvent);
begin
  if Event.What <> evBroadcast then
    Exit;
  if Event.Message.Command = cmScrollBarChanged then
  begin
    Inc(ChangedCount);
    LastInfo := Event.Message.InfoPtr;
  end
  else if Event.Message.Command = cmScrollBarClicked then
    Inc(ClickedCount);
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

function KeyEv(Code: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Code;
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

function WheelEv(Wheel: Byte): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evMouseWheel;
  Result.Mouse.Wheel := Wheel;
end;

function BroadcastEv(Cmd: Word; Info: Pointer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evBroadcast;
  Result.Message.Command := Cmd;
  Result.Message.InfoPtr := Info;
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

function AttrAt(X, Y: Integer): Integer;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute.ToBIOS;
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

{ The number of the entry I of a palette. }
function PalByte(P: TPalette; I: Integer): Integer;
var
  A: TColorAttr;
begin
  A := P.Items[I];
  Result := A.ToBIOS;
end;

procedure ResetMessages;
begin
  ChangedCount := 0;
  ClickedCount := 0;
  LastInfo := nil;
end;

{ The views of the tests. }

destructor TMyFrame.Destroy;
begin
  Inc(FrameDestroys);
  inherited Destroy;
end;

destructor TTestWin.Destroy;
begin
  Inc(WinDestroyCount);
  inherited Destroy;
end;

procedure TTestWin.HandleEvent(var Event: TEvent);
begin
  CountMessage(Event);
  inherited HandleEvent(Event);
end;

function TTestWin.Valid(Command: Word): Boolean;
begin
  if (Command = cmClose) and RejectClose then
    Result := False
  else
    Result := inherited Valid(Command);
end;

function TTitleWin.GetTitle(MaxSize: SmallInt): PAnsiChar;
begin
  LastMax := MaxSize;
  Result := Alt;
end;

procedure TModalWin.HandleEvent(var Event: TEvent);
var
  Cmd: Word;
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;
  Cmd := Event.Message.Command;
  if (Cmd = cmOK) or (Cmd = cmCancel) then
  begin
    ClearEvent(Event);
    EndModal(Cmd);
  end;
end;

procedure TSel.Draw;
begin
end;

procedure TTestScroller.Draw;
begin
  Inc(DrawCount);
end;

function TTestScroller.HBar: TScrollBar;
begin
  Result := HScrollBar;
end;

function TTestScroller.VBar: TScrollBar;
begin
  Result := VScrollBar;
end;

function TTestScroller.GetLimit: TPoint;
begin
  Result := Limit;
end;

function TTestScroller.GetLock: Byte;
begin
  Result := DrawLock;
end;

function TTestScroller.GetFlag: Boolean;
begin
  Result := DrawFlag;
end;

procedure TRoot.AddEvent(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TRoot.GetEvent(var Event: TEvent);
var
  nowMs: Int64;
  hasPending: Boolean;
begin
  Inc(GetCalls);
  if GetCalls > 200000 then
  begin
    WriteLn('FAIL a loop of events does not end');
    Halt(1);
  end;
  FillChar(Event, SizeOf(Event), 0);

  hasPending := Requeue and (Pending.What <> evNothing);
  if hasPending then
  begin
    Event := Pending;
    FillChar(Pending, SizeOf(Pending), 0);
    Exit;
  end;
  if ScriptPos < Length(Script) then
  begin
    Event := Script[ScriptPos];
    Inc(ScriptPos);
    Exit;
  end;
  if not UseQueue then
    Exit;

  if TEventQueue.GetPostedEvent(Event) then
    Exit;
  FillChar(Event, SizeOf(Event), 0);
  nowMs := Now64;
  if InterlockedExchange(WakeFlag, 0) <> 0 then
    Event := CmdEv(cmOK)
  else if nowMs > Deadline then
    Event := CmdEv(cmCancel)
  else
    TEventQueue.WaitForEvents(Guard);
end;

procedure TRoot.HandleEvent(var Event: TEvent);
begin
  CountMessage(Event);
  inherited HandleEvent(Event);
end;

procedure TRoot.PutEvent(var Event: TEvent);
begin
  Inc(PutCount);
  LastPut := Event;
  if Requeue then
    Pending := Event;
end;

procedure TRoot.EventError(var Event: TEvent);
begin
  Inc(ErrorCount);
end;

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
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

function MakeMyFrame(R: TRect): TFrame;
begin
  Inc(FactoryCalls);
  FactoryRect := R;
  Result := TMyFrame.Create(R);
end;

function MakeNoFrame(R: TRect): TFrame;
begin
  Inc(FactoryCalls);
  Result := nil;
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

{ A root with an active window of 20 by 8 cells at 2, 1, which has the number 1 and the title Title. }
procedure Scene(out Root: TRoot; out W: TTestWin);
begin
  Root := NewRoot;
  W := TTestWin.Create(Rc(2, 1, 22, 9), 'Title', 1);
  Root.Insert(W);
  W.SetState(sfActive, True);
end;

procedure SetCommands(Enable: Boolean);
begin
  if Enable then
  begin
    TView.EnableCommand(cmNext);
    TView.EnableCommand(cmPrev);
    TView.EnableCommand(cmResize);
    TView.EnableCommand(cmClose);
    TView.EnableCommand(cmZoom);
  end
  else
  begin
    TView.DisableCommand(cmNext);
    TView.DisableCommand(cmPrev);
    TView.DisableCommand(cmResize);
    TView.DisableCommand(cmClose);
    TView.DisableCommand(cmZoom);
  end;
end;

{ ---- the tests ---- }

procedure TestConstruction;
var
  W, W2, W3, W4: TTestWin;
  Pal: TPalette;
  I: Integer;
  S: string;
begin
  W := TTestWin.Create(Rc(2, 1, 22, 9), 'Title', 1);
  Check(W.Flags = (wfMove or wfGrow or wfClose or wfZoom), 'a new window can move, grow, close and zoom');
  Check(W.Number = 1, 'the window keeps its number');
  Check(W.Palette = wpBlueWindow, 'a new window has the blue palette');
  Check(StrPas(W.Title) = 'Title', 'the window keeps a copy of its title');
  Check(W.GetTitle(7) = W.Title, 'GetTitle returns the title');
  Check(W.ZoomRect = Rc(2, 1, 22, 9), 'the zoom rectangle is the bounds');
  Check((W.State and sfShadow) <> 0, 'a window has a shadow');
  Check((W.Options and (ofSelectable or ofTopSelect)) = (ofSelectable or ofTopSelect),
    'a window can be selected and comes to the top when it is selected');
  Check(W.GrowMode = (gfGrowAll or gfGrowRel), 'a window grows with its owner in all directions, relatively');
  Check(W.Frame <> nil, 'a window has a frame');
  Check(W.Frame.Owner = W, 'the frame is in the window');
  Check(W.First = TView(W.Frame), 'the frame is the first subview');
  Check(W.Frame.GetBounds = Rc(0, 0, 20, 8), 'the frame covers the extent of the window');
  Check(W.Frame.GrowMode = (gfGrowHiX or gfGrowHiY), 'the frame grows with the lower right corner');
  Check(W.Frame.EventMask = (evMouseDown or evKeyDown or evCommand or evBroadcast or evMouseUp),
    'the frame also takes broadcasts and mouse releases');

  Pal := W.Frame.GetPalette;
  Check(PalByte(Pal, 0) = 5, 'the palette of a frame has five entries');
  Check((PalByte(Pal, 1) = 1) and (PalByte(Pal, 2) = 1) and (PalByte(Pal, 3) = 2) and
    (PalByte(Pal, 4) = 2) and (PalByte(Pal, 5) = 3), 'the entries of the palette of a frame');

  Pal := W.GetPalette;
  Check((PalByte(Pal, 0) = 8) and (PalByte(Pal, 1) = 8) and (PalByte(Pal, 8) = 15),
    'the blue palette maps to entries 8 to 15');
  W.Palette := wpCyanWindow;
  Pal := W.GetPalette;
  Check((PalByte(Pal, 0) = 8) and (PalByte(Pal, 1) = 16) and (PalByte(Pal, 8) = 23),
    'the cyan palette maps to entries 16 to 23');
  W.Palette := wpGrayWindow;
  Pal := W.GetPalette;
  Check((PalByte(Pal, 0) = 8) and (PalByte(Pal, 1) = 24) and (PalByte(Pal, 8) = 31),
    'the gray palette maps to entries 24 to 31');
  Check(W.GetPalette = W.GetPalette, 'the palette of a window is one object');
  Check(cpBlueWindow[1] = #8, 'the first entry of the blue palette');

  W2 := TTestWin.Create(Rc(0, 0, 20, 8), 'x', 2);
  Check(W.Frame.GetPalette = W2.Frame.GetPalette, 'all frames share their palette');
  TvObject.DestroyObject(W2);

  FactoryCalls := 0;
  FrameDestroys := 0;
  W2 := TTestWin.Create(Rc(3, 4, 23, 12), 'x', 2, @MakeMyFrame);
  Check(FactoryCalls = 1, 'the function that makes the frame is called once');
  Check(FactoryRect = Rc(0, 0, 20, 8), 'the function gets the extent of the window');
  Check(W2.Frame is TMyFrame, 'the frame is the one that the function made');
  Check(W2.First = TView(W2.Frame), 'the frame of the function is in the window');
  TvObject.DestroyObject(W2);
  Check(FrameDestroys = 1, 'destroying a window destroys its frame');

  W3 := TTestWin.Create(Rc(0, 0, 20, 8), 'x', 2, nil);
  Check(W3.Frame = nil, 'a window without a function has no frame');
  Check(W3.First = nil, 'a window without a frame has no subviews');
  TvObject.DestroyObject(W3);

  W4 := TTestWin.Create(Rc(0, 0, 20, 8), 'x', 2, @MakeNoFrame);
  Check((FactoryCalls = 2) and (W4.Frame = nil) and (W4.First = nil),
    'a function that makes no frame leaves the window without one');
  TvObject.DestroyObject(W4);

  S := 'abc';
  W2 := TTestWin.Create(Rc(0, 0, 20, 8), S, wnNoNumber);
  S[1] := 'z';
  Check(StrPas(W2.Title) = 'abc', 'the title is a copy');
  Check(W2.Number = wnNoNumber, 'a window can have no number');
  TvObject.DestroyObject(W2);
  W2 := TTestWin.Create(Rc(0, 0, 20, 8), '', 3);
  Check((W2.Title <> nil) and (StrPas(W2.Title) = ''), 'an empty title is an empty string');
  TvObject.DestroyObject(W2);

  I := WinDestroyCount;
  TvObject.DestroyObject(W);
  Check(WinDestroyCount = I + 1, 'a window is destroyed');
end;

procedure TestSizeAndZoom;
var
  Root: TRoot;
  W, W2: TTestWin;
  MinP, MaxP: TPoint;
begin
  Scene(Root, W);
  W.SizeLimits(MinP, MaxP);
  Check(MinP = Pt(16, 6), 'the smallest window is 16 by 6');
  Check(MaxP = Pt(ScrW, ScrH), 'the largest window is its owner');

  W2 := TTestWin.Create(Rc(0, 0, 20, 8), 'x', 2);
  W2.SizeLimits(MinP, MaxP);
  Check((MinP = Pt(16, 6)) and (MaxP.X = MaxLongint) and (MaxP.Y = MaxLongint),
    'a window without an owner has no upper limit');
  TvObject.DestroyObject(W2);

  W.Zoom;
  Check(W.GetBounds = Rc(0, 0, ScrW, ScrH), 'zoom fills the owner');
  Check(W.ZoomRect = Rc(2, 1, 22, 9), 'zoom remembers the bounds');
  Check(W.Frame.Size = Pt(ScrW, ScrH), 'the frame grows with the window');
  Check(RowText(0, 35, 3) = '[v]', 'a zoomed window shows the icon that restores it');
  Check(RowText(0, 17, 5) = 'Title', 'the title is in the middle of the wider frame');
  Check(CharAt(33, 0) = '1', 'the number moves with the right edge');
  W.Zoom;
  Check(W.GetBounds = Rc(2, 1, 22, 9), 'a second zoom restores the bounds');
  Check(W.ZoomRect = Rc(2, 1, 22, 9), 'the zoom rectangle is kept');
  Check(W.Frame.Size = Pt(20, 8), 'the frame shrinks with the window');
  Check(RowText(1, 2, 20) = 'JK[*]K Title 1K[^]KL', 'the icon that zooms is back');
  FreeRoot(Root);
end;

procedure TestFrameDraw;
var
  Root: TRoot;
  W: TTestWin;
  T: TTitleWin;
  Long: string;
begin
  Scene(Root, W);
  Check(RowText(1, 2, 20) = 'JK[*]K Title 1K[^]KL', 'the top row of an active frame');
  Check(RowText(4, 2, 20) = 'M' + StringOfChar('N', 18) + 'O', 'a middle row of an active frame');
  Check(RowText(2, 2, 20) = 'M' + StringOfChar('N', 18) + 'O', 'the first middle row of an active frame');
  Check(RowText(7, 2, 20) = 'M' + StringOfChar('N', 18) + 'O', 'the last middle row of an active frame');
  Check(RowText(8, 2, 20) = '<' + StringOfChar('Q', 17) + '>R', 'the bottom row of an active frame with the grips');
  Check(AttrAt(2, 1) = $49, 'an active frame is drawn with the active color');
  Check(AttrAt(4, 1) = $49, 'the brackets of an icon have the color of the frame');
  Check(AttrAt(5, 1) = $4A, 'the symbol of an icon has the color of the icons');
  Check(AttrAt(9, 1) = $49, 'an active title has the active title color');
  Check(AttrAt(2, 4) = $49, 'the sides of an active frame have the active color');

  W.SetState(sfActive, False);
  Check(RowText(1, 2, 20) = 'ABBBBB Title 1BBBBBC', 'the top row of a passive frame has no icons');
  Check(RowText(4, 2, 20) = 'D' + StringOfChar('E', 18) + 'F', 'a middle row of a passive frame');
  Check(RowText(8, 2, 20) = 'G' + StringOfChar('H', 18) + 'I', 'the bottom row of a passive frame has no grips');
  Check(AttrAt(2, 1) = $48, 'a passive frame is drawn with the passive color');
  Check(AttrAt(9, 1) = $48, 'a passive title has the passive title color');

  W.SetState(sfActive, True);
  W.SetState(sfDragging, True);
  Check(RowText(1, 2, 20) = 'AB[*]B Title 1B[^]BC', 'the top row of a frame that is dragged has the lines of a passive frame');
  Check(AttrAt(2, 1) = $4A, 'a frame that is dragged has the icon color');
  Check(AttrAt(9, 1) = $4A, 'a title that is dragged has the icon color');
  W.SetState(sfDragging, False);
  Check(RowText(1, 2, 20) = 'JK[*]K Title 1K[^]KL', 'the frame is active again after the drag');

  W.Flags := wfMove or wfGrow or wfClose;
  W.Frame.DrawView;
  Check(RowText(1, 2, 20) = 'JK[*]K Title KKKK1KL', 'without the zoom flag there is no zoom icon and the number is nearer the edge');
  W.Flags := wfMove or wfZoom;
  W.Frame.DrawView;
  Check(RowText(1, 2, 20) = 'JKKKKK Title 1K[^]KL', 'without the close flag there is no close icon');
  Check(RowText(8, 2, 20) = 'P' + StringOfChar('Q', 18) + 'R', 'without the grow flag there are no grips');
  FreeRoot(Root);

  Root := NewRoot;
  W := TTestWin.Create(Rc(2, 1, 22, 9), 'Title', wnNoNumber);
  Root.Insert(W);
  W.SetState(sfActive, False);
  Check(RowText(1, 2, 20) = 'ABBBBB Title BBBBBBC', 'a window without a number shows none');
  FreeRoot(Root);

  Root := NewRoot;
  W := TTestWin.Create(Rc(2, 1, 22, 9), 'Title', 10);
  Root.Insert(W);
  W.SetState(sfActive, False);
  Check(RowText(1, 2, 20) = 'ABBBBB Title BBBBBBC', 'a number of two digits is not shown');
  FreeRoot(Root);

  Root := NewRoot;
  Long := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  W := TTestWin.Create(Rc(2, 1, 22, 9), Long, 1);
  Root.Insert(W);
  W.SetState(sfActive, False);
  Check(RowText(1, 2, 20) = 'ABBB ABCDEFGHIJ BBBC', 'a long title is cut to the room there is');
  FreeRoot(Root);

  Root := NewRoot;
  T := TTitleWin.Create(Rc(2, 1, 22, 9), 'x', 1);
  Root.Insert(T);
  T.SetState(sfActive, False);
  Check(T.LastMax = 0, 'the room for the title is told to GetTitle');
  Check(RowText(1, 2, 20) = 'ABBBBB' + 'B' + 'BBBBBB' + '1' + 'BBBBBC', 'a window whose GetTitle gives nil shows no title');
  T.Alt := 'Hi';
  T.Frame.DrawView;
  Check(RowText(1, 2, 20) = 'ABBBBBBB Hi B1BBBBBC', 'a title that GetTitle gives is drawn in the middle');
  FreeRoot(Root);
end;

procedure TestFrameLines;
var
  Root: TRoot;
  W: TTestWin;
  Child: TSel;
begin
  { A framed view above the frame, from 4, 2 to 10, 5. The cells under the view are not drawn. }
  Scene(Root, W);
  W.SetState(sfActive, False);
  Child := TSel.Create(Rc(4, 2, 10, 5));
  Child.Options := Child.Options or ofFramed;
  W.Insert(Child);
  W.Frame.DrawView;
  Check(CharAt(2 + 3, 1 + 1) = 'G', 'the left corner above a framed view');
  Check(CharAt(2 + 4, 1 + 1) = 'O', 'the top edge of a framed view');
  Check(CharAt(2 + 9, 1 + 1) = 'O', 'the top edge of a framed view, to its last cell');
  Check(CharAt(2 + 10, 1 + 1) = 'M', 'the right corner above a framed view');
  Check(CharAt(2 + 3, 1 + 2) = 'F', 'the left side of a framed view');
  Check(CharAt(2 + 10, 1 + 4) = 'F', 'the right side of a framed view');
  Check(CharAt(2 + 3, 1 + 5) = 'H', 'the left corner below a framed view');
  Check(CharAt(2 + 7, 1 + 5) = 'O', 'the bottom edge of a framed view');
  Check(CharAt(2 + 10, 1 + 5) = 'N', 'the right corner below a framed view');
  Check(CharAt(2 + 3, 1 + 6) = 'E', 'a row below the framed view is not changed');
  Check(CharAt(2 + 10, 1 + 6) = 'E', 'a row below the framed view is not changed at its right edge');
  Check(CharAt(2 + 3, 1 + 0) = 'B', 'a row above the row of the top edge is not changed');
  Check(CharAt(2 + 2, 1 + 1) = 'E', 'a cell before the left corner is not changed');
  Check(CharAt(2 + 11, 1 + 1) = 'E', 'a cell after the right corner is not changed');

  Child.Options := Child.Options and not ofFramed;
  W.Frame.DrawView;
  Check((CharAt(2 + 3, 1 + 1) = 'E') and (CharAt(2 + 4, 1 + 1) = 'E'), 'a view that is not framed changes nothing');
  Child.Options := Child.Options or ofFramed;
  Child.Hide;
  W.Frame.DrawView;
  Check((CharAt(2 + 3, 1 + 1) = 'E') and (CharAt(2 + 4, 1 + 1) = 'E'), 'a view that is hidden changes nothing');
  FreeRoot(Root);

  { A framed view at the left edge, from 0, 2 to 4, 4. }
  Scene(Root, W);
  W.SetState(sfActive, False);
  Child := TSel.Create(Rc(0, 2, 4, 4));
  Child.Options := Child.Options or ofFramed;
  W.Insert(Child);
  W.Frame.DrawView;
  Check(CharAt(2 + 0, 1 + 1) = 'H', 'the corner at the left edge of the frame, above');
  Check(CharAt(2 + 1, 1 + 1) = 'O', 'the top edge from the first cell after the frame');
  Check(CharAt(2 + 4, 1 + 1) = 'M', 'the right corner of a view at the left edge');
  Check(CharAt(2 + 4, 1 + 2) = 'F', 'the right side of a view at the left edge');
  Check(CharAt(2 + 0, 1 + 4) = 'D', 'the corner at the left edge of the frame, below');
  Check(CharAt(2 + 4, 1 + 4) = 'N', 'the right corner below a view at the left edge');
  Check(CharAt(2 + 2, 1 + 4) = 'O', 'the bottom edge of a view at the left edge');
  FreeRoot(Root);

  { A framed view that reaches beyond the right edge, from 16, 2 to 22, 4. }
  Scene(Root, W);
  W.SetState(sfActive, False);
  Child := TSel.Create(Rc(16, 2, 22, 4));
  Child.Options := Child.Options or ofFramed;
  W.Insert(Child);
  W.Frame.DrawView;
  Check(CharAt(2 + 15, 1 + 1) = 'G', 'the left corner of a view that reaches beyond the frame');
  Check(CharAt(2 + 16, 1 + 1) = 'O', 'the top edge up to the frame');
  Check(CharAt(2 + 19, 1 + 1) = 'N', 'the right edge of the frame takes the right corner');
  Check(CharAt(2 + 15, 1 + 2) = 'F', 'the left side of a view that reaches beyond the frame');
  Check(CharAt(2 + 15, 1 + 4) = 'H', 'the left corner below a view that reaches beyond the frame');
  Check(CharAt(2 + 19, 1 + 4) = 'N', 'the right edge of the frame takes the lower corner');
  FreeRoot(Root);

  { A framed view of one cell at the edge has no room for a mask. }
  Scene(Root, W);
  W.SetState(sfActive, False);
  Child := TSel.Create(Rc(19, 2, 20, 4));
  Child.Options := Child.Options or ofFramed;
  W.Insert(Child);
  W.Frame.DrawView;
  Check((CharAt(2 + 19, 1 + 4) = 'F') and (CharAt(2 + 18, 1 + 2) = 'E') and (CharAt(2 + 19, 1 + 1) = 'F'),
    'a framed view that is cut off by the frame changes nothing');
  FreeRoot(Root);
end;

procedure TestFrameMouse;
var
  Root: TRoot;
  W: TTestWin;
  Ev: TEvent;
begin
  { The close icon. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 5, 1);
  Root.AddEvent(MouseEv(evMouseUp, 5, 1));
  W.Frame.HandleEvent(Ev);
  Check(Root.PutCount = 1, 'a click on the close icon puts one event');
  Check((Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmClose), 'the event is cmClose');
  Check(Root.LastPut.Message.InfoPtr = Pointer(W), 'cmClose is addressed to the window');
  Check(Ev.What = evNothing, 'the click is handled');
  Check(Root.ScriptPos = 1, 'the frame waits for the release of the button');
  FreeRoot(Root);

  { The button is released outside the icon. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 5, 1);
  Root.AddEvent(MouseEv(evMouseUp, 30, 10));
  W.Frame.HandleEvent(Ev);
  Check(Root.PutCount = 0, 'a release away from the close icon closes nothing');
  Check(Ev.What = evMouseUp, 'the event of the release is left as it is');
  FreeRoot(Root);

  { The zoom icon. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 18, 1);
  W.Frame.HandleEvent(Ev);
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmZoom),
    'a click on the zoom icon puts cmZoom');
  Check(Root.LastPut.Message.InfoPtr = Pointer(W), 'cmZoom is addressed to the window');
  Check(Ev.What = evNothing, 'the click on the zoom icon is handled');
  FreeRoot(Root);

  { A double click on the title bar. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 10, 1);
  Ev.Mouse.EventFlags := meDoubleClick;
  W.Frame.HandleEvent(Ev);
  Check((Root.PutCount = 1) and (Root.LastPut.Message.Command = cmZoom), 'a double click on the top row zooms');
  FreeRoot(Root);

  { The close icon of a frame that is not active. }
  Scene(Root, W);
  W.SetState(sfActive, False);
  Ev := MouseEv(evMouseDown, 5, 1);
  Root.AddEvent(MouseEv(evMouseUp, 5, 1));
  W.Frame.HandleEvent(Ev);
  Check(Root.PutCount = 0, 'a frame that is not active has no close icon');
  Check(W.Origin = Pt(2, 1), 'the drag that started did not move the window');
  Check(not W.GetState(sfDragging), 'the drag ended');
  Check(Ev.What = evNothing, 'the click on a frame that is not active is handled');
  FreeRoot(Root);

  { A drag of the top row moves the window. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 10, 1);
  Root.AddEvent(MouseEv(evMouseMove, 12, 3));
  Root.AddEvent(MouseEv(evMouseUp, 12, 3));
  W.Frame.HandleEvent(Ev);
  Check(W.Origin = Pt(4, 3), 'a drag of the top row moves the window');
  Check(W.Size = Pt(20, 8), 'a move does not change the size');
  Check(Ev.What = evNothing, 'the drag is handled');
  Check(not W.GetState(sfDragging), 'the window is not dragged after the drag');
  FreeRoot(Root);

  { A drag of the lower right corner grows the window. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 21, 8);
  Root.AddEvent(MouseEv(evMouseMove, 25, 12));
  Root.AddEvent(MouseEv(evMouseUp, 25, 12));
  W.Frame.HandleEvent(Ev);
  Check(W.Size = Pt(24, 12), 'a drag of the lower right corner changes the size');
  Check(W.Origin = Pt(2, 1), 'a grow does not move the window');
  Check(Ev.What = evNothing, 'the grow is handled');
  FreeRoot(Root);

  { A drag of the lower left corner grows the window to the left. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 3, 8);
  Root.AddEvent(MouseEv(evMouseMove, 1, 10));
  Root.AddEvent(MouseEv(evMouseUp, 1, 10));
  W.Frame.HandleEvent(Ev);
  Check((W.Origin = Pt(0, 1)) and (W.Size = Pt(22, 10)), 'a drag of the lower left corner grows the window to the left');
  FreeRoot(Root);

  { The middle button drags from inside the frame. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 7, 4);
  Ev.Mouse.Buttons := mbMiddleButton;
  Root.AddEvent(MouseEv(evMouseMove, 10, 6));
  Root.AddEvent(MouseEv(evMouseUp, 10, 6));
  W.Frame.HandleEvent(Ev);
  Check(W.Origin = Pt(5, 3), 'the middle button moves the window from inside');
  Check(Ev.What = evNothing, 'the drag with the middle button is handled');
  FreeRoot(Root);

  { The left button inside the frame does nothing. }
  Scene(Root, W);
  Ev := MouseEv(evMouseDown, 7, 4);
  W.Frame.HandleEvent(Ev);
  Check((Ev.What = evMouseDown) and (W.Origin = Pt(2, 1)) and (Root.PutCount = 0) and (Root.ScriptPos = 0),
    'the left button inside the frame does nothing');
  FreeRoot(Root);

  { A window that cannot move cannot be dragged. }
  Scene(Root, W);
  W.Flags := wfGrow or wfClose or wfZoom;
  Ev := MouseEv(evMouseDown, 10, 1);
  W.Frame.HandleEvent(Ev);
  Check((Ev.What = evMouseDown) and (W.Origin = Pt(2, 1)), 'a window without the move flag is not dragged by the top row');
  FreeRoot(Root);

  { A frame that is not active cannot grow the window. }
  Scene(Root, W);
  W.SetState(sfActive, False);
  Ev := MouseEv(evMouseDown, 21, 8);
  W.Frame.HandleEvent(Ev);
  Check((Ev.What = evMouseDown) and (W.Size = Pt(20, 8)), 'a frame that is not active has no grips');
  FreeRoot(Root);
end;

procedure TestWindowCommands;
var
  Root: TRoot;
  W: TTestWin;
  Ev: TEvent;
  Dummy2: Integer;
begin
  { Close. }
  Root := NewRoot;
  W := TTestWin.Create(Rc(2, 1, 22, 9), 'Title', 1, @MakeMyFrame);
  Root.Insert(W);
  WinDestroyCount := 0;
  FrameDestroys := 0;
  Ev := CmdEv(cmClose);
  W.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'cmClose is handled');
  Check(WinDestroyCount = 1, 'cmClose destroys the window');
  Check(FrameDestroys = 1, 'cmClose destroys the frame');
  Check(Root.First = nil, 'the closed window is no more in its owner');
  FreeRoot(Root);

  Scene(Root, W);
  WinDestroyCount := 0;
  Ev := CmdEv(cmClose);
  Ev.Message.InfoPtr := @Dummy2;
  W.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (WinDestroyCount = 0), 'cmClose for another view is left alone');
  Ev := CmdEv(cmClose);
  Ev.Message.InfoPtr := Pointer(W);
  W.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (WinDestroyCount = 1), 'cmClose for the window closes it');
  FreeRoot(Root);

  Scene(Root, W);
  WinDestroyCount := 0;
  W.Flags := wfMove or wfGrow or wfZoom;
  Ev := CmdEv(cmClose);
  W.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (WinDestroyCount = 0), 'a window without the close flag does not close');
  FreeRoot(Root);

  Scene(Root, W);
  WinDestroyCount := 0;
  W.RejectClose := True;
  Ev := CmdEv(cmClose);
  W.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'cmClose is handled when the window is not valid');
  Check((WinDestroyCount = 0) and (Root.IndexOf(W) = 1), 'a window that is not valid for cmClose stays');
  Check(W.Frame <> nil, 'a window that stays keeps its frame');
  FreeRoot(Root);

  Scene(Root, W);
  W.State := W.State or sfModal;
  Ev := CmdEv(cmClose);
  W.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'cmClose of a modal window is handled');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmCancel),
    'cmClose of a modal window puts cmCancel');
  Check(Root.IndexOf(W) = 1, 'a modal window is not closed by cmClose');
  W.State := W.State and not sfModal;
  FreeRoot(Root);

  { Zoom. }
  Scene(Root, W);
  Ev := CmdEv(cmZoom);
  W.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (W.Size = Pt(ScrW, ScrH)), 'cmZoom zooms the window');
  FreeRoot(Root);

  Scene(Root, W);
  Ev := CmdEv(cmZoom);
  Ev.Message.InfoPtr := @Dummy2;
  W.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (W.Size = Pt(20, 8)), 'cmZoom for another view is left alone');
  W.Flags := wfMove or wfGrow or wfClose;
  Ev := CmdEv(cmZoom);
  W.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (W.Size = Pt(20, 8)), 'a window without the zoom flag does not zoom');
  FreeRoot(Root);

  { Resize by the keys. }
  Scene(Root, W);
  Root.AddEvent(KeyEv(kbRight));
  Root.AddEvent(KeyEv(kbEnter));
  Ev := CmdEv(cmResize);
  W.HandleEvent(Ev);
  Check(W.Origin = Pt(3, 1), 'cmResize moves the window with the keys');
  Check((Ev.What = evNothing) and not W.GetState(sfDragging), 'cmResize is handled and the drag ends');
  FreeRoot(Root);

  Scene(Root, W);
  W.Flags := wfClose or wfZoom;
  Ev := CmdEv(cmResize);
  W.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (Root.ScriptPos = 0), 'a window that can neither move nor grow does not resize');
  FreeRoot(Root);
end;

procedure TestWindowKeysAndBroadcast;
var
  Root: TRoot;
  W, W1, W2: TTestWin;
  B1, B2, B3: TSel;
  C0, C1, C2: TView;
  Ev: TEvent;
begin
  Scene(Root, W);
  B1 := TSel.Create(Rc(1, 1, 3, 2));
  B2 := TSel.Create(Rc(1, 2, 3, 3));
  B3 := TSel.Create(Rc(1, 3, 3, 4));
  B1.Options := B1.Options or ofSelectable;
  B2.Options := B2.Options or ofSelectable;
  B3.Options := B3.Options or ofSelectable;
  W.Insert(B1);
  W.Insert(B2);
  W.Insert(B3);
  C0 := W.Current;
  Check(C0 <> nil, 'a window has a current view');
  Ev := KeyEv(kbTab);
  W.HandleEvent(Ev);
  C1 := W.Current;
  Check((C1 <> C0) and (Ev.What = evNothing), 'Tab selects another view and is handled');
  Ev := KeyEv(kbTab);
  W.HandleEvent(Ev);
  C2 := W.Current;
  Check((C2 <> C1) and (C2 <> C0), 'the second Tab selects a third view');
  Ev := KeyEv(kbTab);
  W.HandleEvent(Ev);
  Check(W.Current = C0, 'the third Tab goes round to the first view');
  Ev := KeyEv(kbShiftTab);
  W.HandleEvent(Ev);
  Check((W.Current = C2) and (Ev.What = evNothing), 'Shift+Tab selects the view before the current one');
  FreeRoot(Root);

  { Selection by the number of the window. }
  Root := NewRoot;
  W1 := TTestWin.Create(Rc(2, 1, 22, 9), 'One', 1);
  W2 := TTestWin.Create(Rc(10, 5, 30, 13), 'Two', 2);
  Root.Insert(W1);
  Root.Insert(W2);
  Check(Root.First = TView(W2), 'the window inserted last is on top');
  Ev := BroadcastEv(cmSelectWindowNum, nil);
  Ev.Message.InfoInt := 1;
  W1.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the window with the number takes the broadcast');
  Check(Root.First = TView(W1), 'the window with the number comes to the top');
  Ev := BroadcastEv(cmSelectWindowNum, nil);
  Ev.Message.InfoInt := 5;
  W2.HandleEvent(Ev);
  Check((Ev.What = evBroadcast) and (Root.First = TView(W1)), 'another number is not taken');
  W2.Options := W2.Options and not ofSelectable;
  Ev := BroadcastEv(cmSelectWindowNum, nil);
  Ev.Message.InfoInt := 2;
  W2.HandleEvent(Ev);
  Check((Ev.What = evBroadcast) and (Root.First = TView(W1)), 'a window that cannot be selected does not take its number');
  FreeRoot(Root);
end;

procedure TestWindowState;
var
  Root: TRoot;
  W: TTestWin;
begin
  Scene(Root, W);
  SetCommands(False);
  W.SetState(sfSelected, False);
  Check(not W.GetState(sfActive) and not W.Frame.GetState(sfActive), 'a window that is not selected is not active, nor is its frame');
  Check(not TView.CommandEnabled(cmNext) and not TView.CommandEnabled(cmZoom), 'the commands of the window stay disabled');
  W.SetState(sfSelected, True);
  Check(W.GetState(sfActive) and W.Frame.GetState(sfActive), 'a window that is selected is active, and so is its frame');
  Check(TView.CommandEnabled(cmNext) and TView.CommandEnabled(cmPrev), 'selecting a window enables cmNext and cmPrev');
  Check(TView.CommandEnabled(cmResize) and TView.CommandEnabled(cmClose) and TView.CommandEnabled(cmZoom),
    'selecting a window enables cmResize, cmClose and cmZoom');

  SetCommands(True);
  W.SetState(sfSelected, False);
  Check(not TView.CommandEnabled(cmNext) and not TView.CommandEnabled(cmPrev), 'deselecting a window disables cmNext and cmPrev');
  Check(not TView.CommandEnabled(cmResize) and not TView.CommandEnabled(cmClose) and not TView.CommandEnabled(cmZoom),
    'deselecting a window disables cmResize, cmClose and cmZoom');
  Check(not W.GetState(sfActive) and not W.Frame.GetState(sfActive), 'a window that is deselected is not active');

  W.Flags := wfClose;
  SetCommands(False);
  W.SetState(sfSelected, True);
  Check(TView.CommandEnabled(cmNext) and TView.CommandEnabled(cmPrev) and TView.CommandEnabled(cmClose),
    'a window that can close enables cmClose');
  Check(not TView.CommandEnabled(cmResize) and not TView.CommandEnabled(cmZoom),
    'a window that cannot move, grow or zoom does not enable cmResize or cmZoom');

  W.SetState(sfSelected, False);
  W.Flags := wfGrow;
  SetCommands(False);
  W.SetState(sfSelected, True);
  Check(TView.CommandEnabled(cmResize) and not TView.CommandEnabled(cmClose) and not TView.CommandEnabled(cmZoom),
    'a window that can grow enables cmResize');

  W.SetState(sfSelected, False);
  W.Flags := wfMove or wfZoom;
  SetCommands(False);
  W.SetState(sfSelected, True);
  Check(TView.CommandEnabled(cmResize) and TView.CommandEnabled(cmZoom) and not TView.CommandEnabled(cmClose),
    'a window that can move and zoom enables cmResize and cmZoom');

  W.SetState(sfSelected, False);
  SetCommands(False);
  W.SetState(sfActive, True);
  Check(W.Frame.GetState(sfActive), 'a window that is made active makes its frame active');
  Check(not TView.CommandEnabled(cmNext), 'activating a window does not enable commands');
  SetCommands(True);
  FreeRoot(Root);
end;

procedure TestStandardScrollBar;
var
  Root: TRoot;
  W: TTestWin;
  V, H, V2, H2: TScrollBar;
begin
  Scene(Root, W);
  V := W.StandardScrollBar(sbVertical);
  H := W.StandardScrollBar(sbHorizontal);
  Check(V.GetBounds = Rc(19, 1, 20, 7), 'a vertical scroll bar is on the right side, inside the corners');
  Check(H.GetBounds = Rc(2, 7, 18, 8), 'a horizontal scroll bar is on the bottom, inside the grips');
  Check((V.Owner = W) and (H.Owner = W), 'the scroll bars are in the window');
  Check(W.IndexOf(V) > 0, 'the scroll bar is inserted');
  Check(V.GrowMode = (gfGrowLoX or gfGrowHiX or gfGrowHiY), 'the grow mode of a vertical bar');
  Check(H.GrowMode = (gfGrowLoY or gfGrowHiX or gfGrowHiY), 'the grow mode of a horizontal bar');
  Check((V.Chars[0] = '^') and (V.Chars[4] = '.'), 'a vertical bar has the vertical characters');
  Check((H.Chars[0] = '<') and (H.Chars[4] = ','), 'a horizontal bar has the horizontal characters');
  Check((V.Options and ofPostProcess) = 0, 'a scroll bar does not take the keys by default');
  Check((V.EventMask and evMouseWheel) <> 0, 'a scroll bar takes the wheel of the mouse');
  V2 := W.StandardScrollBar(sbVertical or sbHandleKeyboard);
  H2 := W.StandardScrollBar(sbHandleKeyboard);
  Check(((V2.Options and ofPostProcess) <> 0) and ((H2.Options and ofPostProcess) <> 0),
    'a scroll bar that handles the keyboard is post-processed');
  Check((V2.Size.X = 1) and (H2.Size.Y = 1), 'the options select the direction');
  FreeRoot(Root);
end;

procedure TestScrollBarValues;
var
  B, Hb: TScrollBar;
  Holder: TTestWin;
begin
  { The bar is in a window without a frame, which gets its messages. }
  Holder := TTestWin.Create(Rc(0, 0, 20, 12), 'x', wnNoNumber, nil);
  B := TScrollBar.Create(Rc(0, 0, 1, 12));
  Holder.Insert(B);
  Check((B.Value = 0) and (B.MinVal = 0) and (B.MaxVal = 0) and (B.PgStep = 1) and (B.ArStep = 1),
    'the values of a new scroll bar');
  Check(B.GetSize = 12, 'the size of a vertical bar is its height');
  Check(B.GetPos = 1, 'the indicator of a bar that cannot scroll is at 1');
  Hb := TScrollBar.Create(Rc(0, 0, 8, 1));
  Check(Hb.GetSize = 8, 'the size of a horizontal bar is its width');
  Hb.Free;
  Hb := TScrollBar.Create(Rc(0, 0, 2, 1));
  Check(Hb.GetSize = 3, 'the size of a bar is at least 3');
  Hb.Free;
  Hb := TScrollBar.Create(Rc(0, 0, 1, 2));
  Check(Hb.GetSize = 3, 'the size of a short vertical bar is at least 3');
  Hb.Free;

  ResetMessages;
  B.SetParams(15, 0, 10, 4, 2);
  Check((B.Value = 10) and (B.MinVal = 0) and (B.MaxVal = 10), 'the value is kept in the range');
  Check((B.PgStep = 4) and (B.ArStep = 2), 'the steps are set');
  Check(ChangedCount = 1, 'a change of the value tells the owner');
  Check(LastInfo = Pointer(B), 'the message tells which bar changed');
  B.SetParams(10, 0, 10, 7, 3);
  Check(ChangedCount = 1, 'nothing is told when only the steps change');
  Check((B.PgStep = 7) and (B.ArStep = 3), 'the steps are set when nothing else changes');
  B.SetParams(-5, 3, 1, 1, 1);
  Check((B.Value = 3) and (B.MinVal = 3) and (B.MaxVal = 3), 'a maximum below the minimum is the minimum');
  Check(ChangedCount = 2, 'a new value tells the owner');
  B.SetRange(0, 20);
  Check((B.Value = 3) and (B.MinVal = 0) and (B.MaxVal = 20) and (ChangedCount = 2),
    'a new range keeps the value and tells nothing');
  B.SetStep(5, 2);
  Check((B.PgStep = 5) and (B.ArStep = 2) and (B.Value = 3), 'SetStep sets the steps');
  B.SetValue(25);
  Check((B.Value = 20) and (ChangedCount = 3), 'SetValue keeps the value in the range');
  B.SetRange(0, 5);
  Check((B.Value = 5) and (ChangedCount = 4), 'a range that excludes the value changes it');

  B.SetParams(5, 0, 10, 4, 2);
  B.SetValue(0);
  Check(B.GetPos = 1, 'the indicator is at 1 for the minimum');
  B.SetValue(3);
  Check(B.GetPos = 4, 'the indicator for 3 of 10 in a bar of 12');
  B.SetValue(5);
  Check(B.GetPos = 6, 'the indicator for 5 of 10 in a bar of 12');
  B.SetValue(10);
  Check(B.GetPos = 10, 'the indicator for the maximum is next to the last arrow');
  B.SetParams(0, -10, 10, 1, 1);
  Check(B.GetPos = 6, 'the indicator for 0 of -10 to 10');
  B.SetValue(-10);
  Check(B.GetPos = 1, 'the indicator for the minimum of a negative range');

  B.PgStep := 7;
  B.ArStep := 3;
  Check((B.ScrollStep(sbLeftArrow) = -3) and (B.ScrollStep(sbRightArrow) = 3), 'the steps of the horizontal arrows');
  Check((B.ScrollStep(sbUpArrow) = -3) and (B.ScrollStep(sbDownArrow) = 3), 'the steps of the vertical arrows');
  Check((B.ScrollStep(sbPageLeft) = -7) and (B.ScrollStep(sbPageRight) = 7), 'the steps of the horizontal pages');
  Check((B.ScrollStep(sbPageUp) = -7) and (B.ScrollStep(sbPageDown) = 7), 'the steps of the vertical pages');
  Check(B.ScrollStep(sbIndicator) = -3, 'the step of the indicator is a small step back');

  ResetMessages;
  B.ScrollDraw;
  Check((ChangedCount = 1) and (LastInfo = Pointer(B)), 'ScrollDraw sends cmScrollBarChanged');
  TvObject.DestroyObject(Holder);
end;

procedure TestScrollBarDraw;
var
  Root: TRoot;
  W: TTestWin;
  V, H: TScrollBar;
begin
  Scene(Root, W);
  V := W.StandardScrollBar(sbVertical);
  H := W.StandardScrollBar(sbHorizontal);
  Check((CharAt(21, 2) = '^') and (CharAt(21, 7) = 'v'), 'the arrows of a vertical bar');
  Check((CharAt(21, 3) = '.') and (CharAt(21, 6) = '.'), 'a bar that cannot scroll is filled with its last character');
  Check((AttrAt(21, 2) = $4C) and (AttrAt(21, 7) = $4C), 'the arrows have the color of the controls');
  Check((AttrAt(21, 3) = $4B) and (AttrAt(21, 6) = $4B), 'the page area has the color of the page area');
  V.SetParams(0, 0, 4, 1, 1);
  Check((CharAt(21, 2) = '^') and (CharAt(21, 3) = '#') and (CharAt(21, 4) = ':') and (CharAt(21, 6) = ':') and
    (CharAt(21, 7) = 'v'), 'the indicator at the top');
  Check(AttrAt(21, 3) = $4C, 'the indicator has the color of the controls');
  Check(AttrAt(21, 4) = $4B, 'the page area has its color');
  V.SetValue(4);
  Check((CharAt(21, 3) = ':') and (CharAt(21, 6) = '#') and (CharAt(21, 7) = 'v'), 'the indicator at the bottom');
  V.SetValue(2);
  Check((CharAt(21, 5) = '#') and (CharAt(21, 6) = ':'), 'the indicator in the middle');

  Check((CharAt(4, 8) = '<') and (CharAt(19, 8) = '>') and (CharAt(5, 8) = ',') and (CharAt(18, 8) = ','),
    'a horizontal bar that cannot scroll');
  H.SetParams(5, 0, 10, 1, 1);
  Check((CharAt(4, 8) = '<') and (CharAt(19, 8) = '>') and (CharAt(11, 8) = ';') and (CharAt(12, 8) = '@') and
    (CharAt(13, 8) = ';') and (CharAt(5, 8) = ';'), 'a horizontal bar with the indicator at 8');
  FreeRoot(Root);
end;

procedure TestScrollBarEvents;
var
  Root: TRoot;
  W: TTestWin;
  V, H: TScrollBar;
  Ev: TEvent;
begin
  Scene(Root, W);
  V := W.StandardScrollBar(sbVertical);
  H := W.StandardScrollBar(sbHorizontal);

  { The wheel. }
  V.SetParams(10, 0, 100, 5, 2);
  H.SetParams(10, 0, 100, 5, 3);
  ResetMessages;
  Ev := WheelEv(mwDown);
  V.HandleEvent(Ev);
  Check((V.Value = 16) and (Ev.What = evNothing), 'the wheel down moves a vertical bar by three small steps');
  Check(ClickedCount = 1, 'the wheel tells the owner that the bar was clicked');
  Ev := WheelEv(mwUp);
  V.HandleEvent(Ev);
  Check(V.Value = 10, 'the wheel up moves a vertical bar back');
  Ev := WheelEv(mwLeft);
  V.HandleEvent(Ev);
  Check((V.Value = 10) and (Ev.What = evMouseWheel), 'a vertical bar ignores the horizontal wheel');
  Ev := WheelEv(mwRight);
  H.HandleEvent(Ev);
  Check((H.Value = 19) and (Ev.What = evNothing), 'the wheel to the right moves a horizontal bar by three small steps');
  Ev := WheelEv(mwLeft);
  H.HandleEvent(Ev);
  Check(H.Value = 10, 'the wheel to the left moves a horizontal bar back');
  Ev := WheelEv(mwDown);
  H.HandleEvent(Ev);
  Check((H.Value = 10) and (Ev.What = evMouseWheel), 'a horizontal bar ignores the vertical wheel');
  V.State := V.State and not sfVisible;
  ResetMessages;
  Ev := WheelEv(mwDown);
  V.HandleEvent(Ev);
  Check((V.Value = 10) and (Ev.What = evMouseWheel) and (ClickedCount = 0), 'a bar that is hidden ignores the wheel');
  V.State := V.State or sfVisible;

  { The keys of a horizontal bar. }
  H.SetParams(5, 0, 10, 4, 2);
  ResetMessages;
  Ev := KeyEv(kbRight);
  H.HandleEvent(Ev);
  Check((H.Value = 7) and (Ev.What = evNothing) and (ClickedCount = 1), 'Right moves a horizontal bar by a small step');
  Ev := KeyEv(kbLeft);
  H.HandleEvent(Ev);
  Check(H.Value = 5, 'Left moves a horizontal bar back by a small step');
  Ev := KeyEv(kbCtrlRight);
  H.HandleEvent(Ev);
  Check(H.Value = 9, 'Ctrl+Right moves a horizontal bar by a page');
  Ev := KeyEv(kbCtrlLeft);
  H.HandleEvent(Ev);
  Check(H.Value = 5, 'Ctrl+Left moves a horizontal bar back by a page');
  Ev := KeyEv(kbHome);
  H.HandleEvent(Ev);
  Check(H.Value = 0, 'Home goes to the minimum');
  Ev := KeyEv(kbCtrlDown);
  H.HandleEvent(Ev);
  Check(H.Value = 4, 'Ctrl+Down moves a horizontal bar by a page');
  Ev := KeyEv(kbCtrlUp);
  H.HandleEvent(Ev);
  Check(H.Value = 0, 'Ctrl+Up moves a horizontal bar back by a page');
  Ev := KeyEv(kbEnd);
  H.HandleEvent(Ev);
  Check(H.Value = 10, 'End goes to the maximum');
  ResetMessages;
  Ev := KeyEv(kbUp);
  H.HandleEvent(Ev);
  Check((H.Value = 10) and (Ev.What = evKeyDown) and (ClickedCount = 0), 'a horizontal bar ignores Up');

  { The keys of a vertical bar. }
  V.SetParams(5, 0, 10, 4, 2);
  ResetMessages;
  Ev := KeyEv(kbDown);
  V.HandleEvent(Ev);
  Check((V.Value = 7) and (Ev.What = evNothing) and (ClickedCount = 1), 'Down moves a vertical bar by a small step');
  Ev := KeyEv(kbUp);
  V.HandleEvent(Ev);
  Check(V.Value = 5, 'Up moves a vertical bar back by a small step');
  Ev := KeyEv(kbPgDn);
  V.HandleEvent(Ev);
  Check(V.Value = 9, 'PgDn moves a vertical bar by a page');
  Ev := KeyEv(kbPgUp);
  V.HandleEvent(Ev);
  Check(V.Value = 5, 'PgUp moves a vertical bar back by a page');
  Ev := KeyEv(kbCtrlPgUp);
  V.HandleEvent(Ev);
  Check(V.Value = 0, 'Ctrl+PgUp goes to the minimum');
  Ev := KeyEv(kbCtrlPgDn);
  V.HandleEvent(Ev);
  Check(V.Value = 10, 'Ctrl+PgDn goes to the maximum');
  ResetMessages;
  Ev := KeyEv(kbLeft);
  V.HandleEvent(Ev);
  Check((V.Value = 10) and (Ev.What = evKeyDown) and (ClickedCount = 0), 'a vertical bar ignores Left');
  V.State := V.State and not sfVisible;
  V.SetValue(5);
  Ev := KeyEv(kbDown);
  V.HandleEvent(Ev);
  Check((V.Value = 5) and (Ev.What = evKeyDown), 'a bar that is hidden ignores the keys');
  V.State := V.State or sfVisible;

  { A click on an arrow, held for one repeat. }
  V.SetParams(0, 0, 10, 4, 2);
  ResetMessages;
  Ev := MouseEv(evMouseDown, 21, 7);
  Root.Script := nil;
  Root.ScriptPos := 0;
  Root.AddEvent(MouseEv(evMouseAuto, 21, 7));
  Root.AddEvent(MouseEv(evMouseUp, 21, 7));
  V.HandleEvent(Ev);
  Check(V.Value = 4, 'a click on the lower arrow moves the bar by a small step for each repeat');
  Check(ChangedCount = 2, 'each step tells the owner');
  Check(ClickedCount = 1, 'a click tells the owner that the bar was clicked');
  Check(Ev.What = evNothing, 'the click is handled');
  Check(Root.ScriptPos = 2, 'the bar waits for the release of the button');

  { A click on the upper arrow does nothing at the minimum. }
  V.SetParams(0, 0, 10, 4, 2);
  ResetMessages;
  Ev := MouseEv(evMouseDown, 21, 2);
  Root.Script := nil;
  Root.ScriptPos := 0;
  Root.AddEvent(MouseEv(evMouseUp, 21, 2));
  V.HandleEvent(Ev);
  Check((V.Value = 0) and (ChangedCount = 0) and (Ev.What = evNothing), 'the upper arrow at the minimum changes nothing');

  { A click in the page area moves the indicator to the mouse, which then follows the mouse. }
  V.SetParams(0, 0, 10, 4, 2);
  ResetMessages;
  Ev := MouseEv(evMouseDown, 21, 4);
  Root.Script := nil;
  Root.ScriptPos := 0;
  Root.AddEvent(MouseEv(evMouseMove, 21, 5));
  Root.AddEvent(MouseEv(evMouseMove, 21, 22));
  Root.AddEvent(MouseEv(evMouseUp, 21, 22));
  V.HandleEvent(Ev);
  Check(V.Value = 10, 'the indicator follows the mouse to the end of the bar');
  Check(ChangedCount = 3, 'the value changed three times: 3, 7 and 10');
  Check(Ev.What = evNothing, 'the drag of the indicator is handled');

  V.SetParams(0, 0, 10, 4, 2);
  ResetMessages;
  Ev := MouseEv(evMouseDown, 21, 4);
  Root.Script := nil;
  Root.ScriptPos := 0;
  Root.AddEvent(MouseEv(evMouseUp, 21, 4));
  V.HandleEvent(Ev);
  Check(V.Value = 3, 'a click in the page area sets the value for the place of the mouse');
  FreeRoot(Root);
end;

procedure TestScroller;
var
  Root: TRoot;
  HB, VB: TScrollBar;
  Sc, Sc0: TTestScroller;
  Pal: TPalette;
  Before: Integer;
  Ev: TEvent;
begin
  Root := NewRoot;
  HB := TScrollBar.Create(Rc(0, 5, 10, 6));
  VB := TScrollBar.Create(Rc(10, 0, 11, 5));
  Sc := TTestScroller.Create(Rc(0, 0, 10, 5), HB, VB);
  Root.Insert(HB);
  Root.Insert(VB);
  Root.Insert(Sc);
  ResetMessages;

  Check(Sc.Delta = Pt(0, 0), 'a new scroller is not scrolled');
  Check(Sc.GetLimit = Pt(0, 0), 'a new scroller has no limit');
  Check((Sc.GetLock = 0) and not Sc.GetFlag, 'a new scroller is not locked');
  Check((Sc.HBar = HB) and (Sc.VBar = VB), 'the scroller keeps its scroll bars');
  Check((Sc.Options and ofSelectable) <> 0, 'a scroller can be selected');
  Check((Sc.EventMask and evBroadcast) <> 0, 'a scroller takes broadcasts');
  Pal := Sc.GetPalette;
  Check((PalByte(Pal, 0) = 2) and (PalByte(Pal, 1) = 6) and (PalByte(Pal, 2) = 7), 'the palette of a scroller');

  Sc.SetLimit(30, 20);
  Check(Sc.GetLimit = Pt(30, 20), 'SetLimit keeps the limit');
  Check((HB.MinVal = 0) and (HB.MaxVal = 20) and (HB.PgStep = 9) and (HB.ArStep = 1),
    'SetLimit sets the range and the page of the horizontal bar');
  Check((VB.MinVal = 0) and (VB.MaxVal = 15) and (VB.PgStep = 4) and (VB.ArStep = 1),
    'SetLimit sets the range and the page of the vertical bar');
  Check((Sc.GetLock = 0) and not Sc.GetFlag, 'SetLimit unlocks the scroller');

  Before := Sc.DrawCount;
  Sc.ScrollTo(7, 3);
  Check((HB.Value = 7) and (VB.Value = 3), 'ScrollTo sets the bars');
  Check(Sc.Delta = Pt(7, 3), 'ScrollTo scrolls the scroller');
  Check(Sc.Cursor = Pt(-7, -3), 'the cursor follows the scroll');
  Check(Sc.DrawCount = Before + 1, 'ScrollTo draws once for both bars');
  Check((Sc.GetLock = 0) and not Sc.GetFlag, 'ScrollTo unlocks the scroller');

  Sc.ScrollTo(100, 100);
  Check((HB.Value = 20) and (VB.Value = 15) and (Sc.Delta = Pt(20, 15)), 'ScrollTo keeps the bars in their range');
  Check(Sc.Cursor = Pt(-20, -15), 'the cursor follows the scroll to the end');

  Before := Sc.DrawCount;
  HB.SetValue(2);
  Check((Sc.Delta = Pt(2, 15)) and (Sc.DrawCount = Before + 1), 'a bar that changes scrolls and draws the scroller at once');

  VB.Value := 1;
  Ev := BroadcastEv(cmScrollBarChanged, @Dummy);
  Sc.HandleEvent(Ev);
  Check(Sc.Delta.Y = 15, 'a change of another view is not taken');
  Ev := BroadcastEv(cmScrollBarClicked, VB);
  Sc.HandleEvent(Ev);
  Check(Sc.Delta.Y = 15, 'a click on the bar is not a change');
  Ev := BroadcastEv(cmScrollBarChanged, VB);
  Sc.HandleEvent(Ev);
  Check(Sc.Delta.Y = 1, 'a change of the vertical bar scrolls the scroller');
  HB.Value := 6;
  Ev := BroadcastEv(cmScrollBarChanged, HB);
  Sc.HandleEvent(Ev);
  Check(Sc.Delta = Pt(6, 1), 'a change of the horizontal bar scrolls the scroller');

  Before := Sc.DrawCount;
  Sc.ChangeBounds(Rc(0, 0, 12, 6));
  Check(Sc.Size = Pt(12, 6), 'ChangeBounds sets the bounds');
  Check((HB.MaxVal = 18) and (HB.PgStep = 11) and (VB.MaxVal = 14) and (VB.PgStep = 5),
    'ChangeBounds sets the bars for the new size');
  Check(Sc.DrawCount = Before + 1, 'ChangeBounds draws once');
  Check((Sc.GetLock = 0) and not Sc.GetFlag, 'ChangeBounds unlocks the scroller');

  { Which bars show. }
  Sc.SetState(sfSelected, False);
  Sc.SetState(sfActive, False);
  Check(((HB.State and sfVisible) = 0) and ((VB.State and sfVisible) = 0), 'the bars of a scroller that is not active are hidden');
  Sc.SetState(sfActive, True);
  Check(((HB.State and sfVisible) = 0) and ((VB.State and sfVisible) = 0),
    'the bars are hidden when the scroller is active and not selected');
  Sc.SetState(sfSelected, True);
  Check(((HB.State and sfVisible) <> 0) and ((VB.State and sfVisible) <> 0),
    'the bars show when the scroller is active and selected');
  HB.Hide;
  Sc.SetState(sfFocused, True);
  Check((HB.State and sfVisible) = 0, 'a change of the focus does not change the bars');
  Sc.SetState(sfActive, False);
  Check(((HB.State and sfVisible) = 0) and ((VB.State and sfVisible) = 0), 'the bars are hidden when the scroller is not active');

  { A scroller without bars. }
  Sc0 := TTestScroller.Create(Rc(0, 6, 10, 10), nil, nil);
  Root.Insert(Sc0);
  Sc0.SetLimit(5, 5);
  Before := Sc0.DrawCount;
  Sc0.ScrollTo(3, 3);
  Check((Sc0.GetLimit = Pt(5, 5)) and (Sc0.Delta = Pt(0, 0)) and (Sc0.DrawCount = Before),
    'a scroller without bars keeps its limit and is not scrolled');
  Sc0.ScrollDraw;
  Check(Sc0.Delta = Pt(0, 0), 'ScrollDraw of a scroller without bars changes nothing');

  { Shut down. }
  Sc.ShutDown;
  Check((Sc.HBar = nil) and (Sc.VBar = nil), 'ShutDown lets go of the bars');
  Check((Sc.Owner = nil) and (Root.IndexOf(Sc) = 0), 'ShutDown takes the scroller out of its owner');
  Sc.Free;
  FreeRoot(Root);
end;

procedure TestModal;
var
  Root: TRoot;
  W: TModalWin;
  R: Word;
begin
  Root := NewRoot;
  Root.Requeue := True;
  W := TModalWin.Create(Rc(5, 3, 25, 11), 'Modal', wnNoNumber);
  Root.AddEvent(CmdEv(cmClose));
  R := Root.ExecView(W);
  Check(R = cmCancel, 'cmClose of a modal window ends the loop with cmCancel');
  Check(Root.PutCount = 1, 'cmClose put one event');
  Check(not W.GetState(sfModal), 'the window is not modal after the loop');
  TvObject.DestroyObject(W);

  W := TModalWin.Create(Rc(5, 3, 25, 11), 'Modal', wnNoNumber);
  Root.AddEvent(CmdEv(cmOK));
  R := Root.ExecView(W);
  Check(R = cmOK, 'cmOK ends the loop of a modal window');
  TvObject.DestroyObject(W);
  FreeRoot(Root);
end;

procedure TestThreads;
var
  Root: TRoot;
  W: TModalWin;
  T: TPoster;
  Start: Int64;
  R: Word;
begin
  Root := NewRoot;
  Root.UseQueue := True;
  Root.Deadline := Now64 + 25000;
  W := TModalWin.Create(Rc(5, 3, 25, 13), 'Modal', 1);
  T := TPoster.Create(0, 250);
  Start := Now64;
  R := Root.ExecView(W);
  Check(R = cmOK, 'an event that is posted from a second thread during ExecView is delivered');
  Check(Now64 - Start < Guard - 1000, 'the posted event ended the wait');
  Check(Now64 - Start >= 150, 'the loop waited for the posted event');
  T.WaitFor;
  T.Free;
  Check(Root.ErrorCount = 0, 'the posted event was handled');

  TvObject.DestroyObject(W);
  W := TModalWin.Create(Rc(5, 3, 25, 13), 'Modal', 1);
  WakeFlag := 0;
  T := TPoster.Create(1, 250);
  Start := Now64;
  R := Root.ExecView(W);
  Check(R = cmOK, 'a wake-up from a second thread during ExecView ends the wait');
  Check(Now64 - Start < Guard - 1000, 'the wake-up ended the wait');
  T.WaitFor;
  T.Free;
  TvObject.DestroyObject(W);

  W := TModalWin.Create(Rc(5, 3, 25, 13), 'Modal', 1);
  T := TPoster.Create(0, 0);
  T.WaitFor;
  T.Free;
  Start := Now64;
  R := Root.ExecView(W);
  Check((R = cmOK) and (Now64 - Start < Guard - 1000), 'an event that was posted before ExecView is delivered at once');
  TvObject.DestroyObject(W);
  FreeRoot(Root);
end;

var
  EventBackend: TEventBackend;
  Queue: TEventQueue;
  SavedBackend: TScreenBackend;
  K: Integer;
  Chars: string;

begin
  RootPal := TPalette.Create(#$41#$42#$43#$44#$45#$46#$47#$48#$49#$4A#$4B#$4C#$4D#$4E#$4F#$50 +
    #$51#$52#$53#$54#$55#$56#$57#$58#$59#$5A#$5B#$5C#$5D#$5E#$5F#$60, 32);
  Check((Ord(TFrame.InitFrame[0]) = $06) and (Ord(TFrame.InitFrame[1]) = $0A) and (Ord(TFrame.InitFrame[4]) = 0) and
    (Ord(TFrame.InitFrame[9]) = $16) and (Ord(TFrame.InitFrame[17]) = $19) and (Ord(TFrame.InitFrame[18]) = 0),
    'the masks of the lines of a frame');
  Check((Ord(TFrame.FrameChars[3]) = $C0) and (Ord(TFrame.FrameChars[6]) = $DA) and (Ord(TFrame.FrameChars[10]) = $C4) and
    (Ord(TFrame.FrameChars[26]) = $CD) and (Ord(TFrame.FrameChars[30]) = $D1) and (Ord(TFrame.FrameChars[0]) = $20) and
    (Ord(TFrame.FrameChars[32]) = 0), 'the characters of the masks of a frame');
  Check((TFrame.CloseIcon = '[~' + #$FE + '~]') and (TFrame.ZoomIcon = '[~' + #$18 + '~]') and
    (TFrame.UnZoomIcon = '[~' + #$12 + '~]'), 'the icons of a frame');
  Check((TFrame.DragIcon = '~' + #$C4 + #$D9 + '~') and (TFrame.DragLeftIcon = '~' + #$C0 + #$C4 + '~'),
    'the grips of a frame');
  Check((Ord(TScrollBar.VChars[0]) = $1E) and (Ord(TScrollBar.VChars[1]) = $1F) and (Ord(TScrollBar.VChars[3]) = $FE) and
    (Ord(TScrollBar.VChars[4]) = $B2), 'the characters of a vertical scroll bar');
  Check((Ord(TScrollBar.HChars[0]) = $11) and (Ord(TScrollBar.HChars[1]) = $10) and (Ord(TScrollBar.HChars[2]) = $B1),
    'the characters of a horizontal scroll bar');
  for K := 0 to 18 do
    TFrame.InitFrame[K] := Chr(K);
  for K := 0 to 32 do
    TFrame.FrameChars[K] := Chr(Ord('A') + K);
  TFrame.CloseIcon := '[~*~]';
  TFrame.ZoomIcon := '[~^~]';
  TFrame.UnZoomIcon := '[~v~]';
  TFrame.DragIcon := '~>~';
  TFrame.DragLeftIcon := '~<~';
  Chars := '^v:#.';
  for K := 0 to 4 do
    TScrollBar.VChars[K] := Chars[K + 1];
  Chars := '<>;@,';
  for K := 0 to 4 do
    TScrollBar.HChars[K] := Chars[K + 1];

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

  TestConstruction;
  TestSizeAndZoom;
  TestFrameDraw;
  TestFrameLines;
  TestFrameMouse;
  TestWindowCommands;
  TestWindowKeysAndBroadcast;
  TestWindowState;
  TestStandardScrollBar;
  TestScrollBarValues;
  TestScrollBarDraw;
  TestScrollBarEvents;
  TestScroller;
  TestModal;
  TestThreads;

  Queue.Free;
  TEventQueue.Backend := nil;
  EventBackend.Free;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
