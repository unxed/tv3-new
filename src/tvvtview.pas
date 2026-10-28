{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/termview.h, source/tvterm-core/termview.cc, include/tvterm/termwnd.h,
  source/tvterm-core/termwnd.cc, include/tvterm/termframe.h, source/tvterm-core/termframe.cc,
  include/tvterm/consts.h, include/tvterm/termemu.h, include/tvterm/termctrl.h and, from magiblot/tvision,
  include/tvision/views.h, include/tvision/ttypes.h, include/tvision/tv.h, include/tvision/config.h
  See COPYRIGHT.tvterm.

  The view, the window and the frame of a terminal. TerminalView shows the surface of the state of a
  TerminalController, keeps a selection that the mouse and the commands of TVTermConstants change, and sends the keys,
  the mouse, the focus, the size and the offset of the scroll bar to the controller as events. BasicTerminalWindow
  holds the scroll bar and the view, takes its title from the state and grabs the input while it is modal.
  BasicTerminalFrame writes the size of the terminal into the lower edge of the frame while the window is dragged.

  The C++ calls that have a unit of the library are TClipboard::requestText (TClipboard.RequestText of TvClip) and
  message (Message of TvViews). The messages cmTerminalUpdated and cmCheckTerminalUpdates are the commands of the
  TVTermConstants that the view is given. The view and the window keep a copy of the constants, where the C++ keeps a
  reference. A TerminalUpdatedMsg reaches the window as the information pointer of a command event. }
unit TvVtView;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvEvents, TvViews, TvWindow, TvVtCore, TvVtCtrl;

type
  { Shows the state of a TerminalController. Takes ownership of the controller: the destructor shuts it down. The
    scroll bar is not owned. }
  TerminalView = class(TView)
  private
    Consts: TVTermConstants;
    ScrollBar: TScrollBar;
    OwnerBufferChanged: Boolean;
    Selection: SelectionRange;
    PrevSelection: SelectionRange;
    InSelectionMode: Boolean;
    { What ReadMouseState takes from the state. }
    SeenOffset: Integer;
    ClientUsesMouse: Boolean;
    procedure ReadMouseState(St: TerminalState);
    procedure DrawWithState(St: TerminalState);
    procedure HandleMouse(What: Word; Mouse: TMouseEventType);
    procedure UpdateHelpContext;
    procedure UpdateCursor(St: TerminalState);
    procedure UpdateScrollBar(St: TerminalState);
    procedure UpdateDisplay(St: TerminalState);
    function CanReuseOwnerBuffer: Boolean;
    function GetCursorDisplayedPos(St: TerminalState): TPoint;
    procedure StartSelection; overload;
    procedure StartSelection(const Pos: SelectionAnchor); overload;
    procedure ExtendSelection(const Pos: SelectionAnchor);
    procedure CancelSelection;
    procedure CopySelection;
  public
    TermCtrl: TerminalController;
    constructor Create(const Bounds: TRect; ATermCtrl: TerminalController; const AConsts: TVTermConstants;
      AScrollBar: TScrollBar);
    destructor Destroy; override;
    procedure ShutDown; override;
    procedure ChangeBounds(const Bounds: TRect); override;
    procedure SetState(AState: Word; Enable: Boolean); override;
    procedure HandleEvent(var Ev: TEvent); override;
    procedure Draw; override;
  end;

  { A TFrame that shows the dimensions of the terminal while it is dragged. It assumes that the terminal fills the
    inner area of the frame. }
  BasicTerminalFrame = class(TFrame)
  public
    constructor Create(const Bounds: TRect);
    procedure Draw; override;
  end;

  { A window with a scroll bar and a TerminalView. The frame of the window is a BasicTerminalFrame. }
  BasicTerminalWindow = class(TWindow)
  private
    Consts: TVTermConstants;
    FocusedCmds: TCommandSet;
    View: TerminalView;
    TitleCapacity: SizeUInt;
    TermTitle: GrowArray;
    procedure CheckChanges(var Upd: TerminalUpdatedMsg);
    procedure ResizeTitle(ACapacity: SizeUInt);
    function UpdateTitle(Term: TerminalController; St: TerminalState): Boolean;
  protected
    function IsDisconnected: Boolean;
  public
    class function InitFrame(Area: TRect): TFrame; static;
    { Takes ownership of ATermCtrl. }
    constructor Create(const Bounds: TRect; ATermCtrl: TerminalController; const AConsts: TVTermConstants);
    destructor Destroy; override;
    procedure ShutDown; override;
    function GetTitle(RoomLeft: SmallInt): PAnsiChar; override;
    procedure HandleEvent(var Ev: TEvent); override;
    procedure SetState(AState: Word; Enable: Boolean); override;
    function Execute: Word; override;
    class function ViewBounds(const WindowBounds: TRect): TRect; static;
    class function ViewSize(const WindowBounds: TRect): TPoint; static;
  end;

implementation

uses
  SysUtils, TvCell, TvColors, TvDrawBuf, TvClip, TvUtil;

type
  PTerminalUpdatedMsg = ^TerminalUpdatedMsg;

{ An event of the given kind with every other member zero. }
function BlankTerminalEvent(Kind: TerminalEventType): TerminalEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := Kind;
end;

{ The cells of the row Y that are copied from the surface: the damaged cells when the buffer of the owner is kept,
  and the whole row otherwise. }
function RangeToCopy(Y, Cols: Integer; Surf: TerminalSurface; ReuseBuffer: Boolean): RowRange;
var
  Hurt: PRowRange;
begin
  if not ReuseBuffer then
  begin
    Result := RowRange.Create(0, Cols);
    Exit;
  end;
  Hurt := Surf.DamageAtRow(Y);
  Result := RowRange.Create(Max(Hurt^.Start, 0), Min(Hurt^.RangeEnd, Cols));
end;

{ Reverses the attribute of the cells of Span. }
procedure DrawSelection(var Cells: array of TScreenCell; const Span: RowRange);
var
  Col: Integer;
begin
  Col := Span.Start;
  while Col < Span.RangeEnd do
  begin
    Cells[Col].Attribute := Cells[Col].Attribute.Reversed;
    Inc(Col);
  end;
end;

{ TerminalView }

constructor TerminalView.Create(const Bounds: TRect; ATermCtrl: TerminalController;
  const AConsts: TVTermConstants; AScrollBar: TScrollBar);
begin
  inherited Create(Bounds);
  Consts := AConsts;
  ScrollBar := AScrollBar;
  TermCtrl := ATermCtrl;
  OwnerBufferChanged := False;
  InSelectionMode := False;
  SeenOffset := 0;
  ClientUsesMouse := False;
  FillChar(Selection, SizeOf(Selection), 0);
  FillChar(PrevSelection, SizeOf(PrevSelection), 0);
  GrowMode := gfGrowHiX or gfGrowHiY;
  Options := Options or ofSelectable or ofFirstClick;
  EventMask := EventMask or evMouseMove or evMouseAuto or evMouseWheel or evBroadcast;
  ShowCursor;
end;

destructor TerminalView.Destroy;
begin
  TermCtrl.ShutDown;
  inherited Destroy;
end;

procedure TerminalView.ShutDown;
begin
  ScrollBar := nil;
  inherited ShutDown;
end;

procedure TerminalView.ChangeBounds(const Bounds: TRect);
var
  TermEv: TerminalEvent;
begin
  SetBounds(Bounds);
  OwnerBufferChanged := True;
  DrawView;

  TermEv := BlankTerminalEvent(TerminalEventType.ViewportResize);
  TermEv.ViewportResize.X := Size.X;
  TermEv.ViewportResize.Y := Size.Y;
  TermCtrl.SendEvent(TermEv);
end;

procedure TerminalView.SetState(AState: Word; Enable: Boolean);
var
  TermEv: TerminalEvent;
begin
  if (AState = sfExposed) and (Enable <> GetState(sfExposed)) then
    OwnerBufferChanged := True;

  inherited SetState(AState, Enable);

  if AState = sfFocused then
  begin
    TermEv := BlankTerminalEvent(TerminalEventType.FocusChange);
    TermEv.FocusChange.FocusEnabled := Enable;
    TermCtrl.SendEvent(TermEv);
  end;
end;

procedure TerminalView.HandleEvent(var Ev: TEvent);
var
  TermEv: TerminalEvent;
begin
  inherited HandleEvent(Ev);

  case Ev.What of
    evCommand:
      if Ev.Message.Command = Consts.CmStartSelection then
      begin
        StartSelection;
        HelpCtx := Consts.HcSelecting;
        ClearEvent(Ev);
      end
      else if Ev.Message.Command = Consts.CmCopySelection then
      begin
        CopySelection;
        ClearEvent(Ev);
      end
      else if Ev.Message.Command = Consts.CmCancelSelection then
      begin
        CancelSelection;
        ClearEvent(Ev);
      end
      else if Ev.Message.Command = cmPaste then
      begin
        TClipboard.RequestText;
        ClearEvent(Ev);
      end;

    evBroadcast:
      if (Ev.Message.Command = Consts.CmCheckTerminalUpdates) and TermCtrl.StateHasBeenUpdated then
        DrawView
      else if (Ev.Message.Command = cmScrollBarChanged) and (Ev.Message.InfoPtr = Pointer(ScrollBar)) and
        (ScrollBar <> nil) then
      begin
        { A change of the scroll bar becomes a scroll event of the terminal. }
        TermEv := BlankTerminalEvent(TerminalEventType.ScrollBackOffsetChange);
        TermEv.ScrollBackOffsetChange.Offset := ScrollBar.Value;
        TermCtrl.SendEvent(TermEv);
        ClearEvent(Ev);
      end;

    evKeyDown:
      begin
        TermEv := BlankTerminalEvent(TerminalEventType.KeyDown);
        TermEv.KeyDown := Ev.KeyDown;
        TermCtrl.SendEvent(TermEv);
        ClearEvent(Ev);
      end;

    evMouseDown:
      begin
        { The loop goes on when the mouse is dragged out of the window. }
        repeat
          HandleMouse(Ev.What, Ev.Mouse);
        until not MouseEvent(Ev, evMouse);
        if Ev.What = evMouseUp then
          HandleMouse(Ev.What, Ev.Mouse);
        ClearEvent(Ev);
      end;

    evMouseWheel, evMouseMove, evMouseAuto, evMouseUp:
      begin
        HandleMouse(Ev.What, Ev.Mouse);
        ClearEvent(Ev);
      end;
  end;
end;

{ Reads the part of the state that a mouse event needs. }
procedure TerminalView.ReadMouseState(St: TerminalState);
begin
  SeenOffset := St.ScrollbackOffset;
  ClientUsesMouse := St.MouseEnabled;
end;

procedure TerminalView.HandleMouse(What: Word; Mouse: TMouseEventType);
var
  AbsPos: TPoint;
  TermEv: TerminalEvent;
  LeftHeld: Boolean;
begin
  Mouse.Where := MakeLocal(Mouse.Where);

  TermCtrl.LockState(@ReadMouseState);
  AbsPos := Mouse.Where;
  AbsPos.Y := AbsPos.Y + SeenOffset;
  LeftHeld := (Mouse.Buttons and mbLeftButton) <> 0;

  if (InSelectionMode or not ClientUsesMouse) and (What = evMouseDown) and LeftHeld then
    { Left click: start the selection. }
    StartSelection(SelectionAnchor.Create(AbsPos))
  else if InSelectionMode and (What = evMouseMove) and LeftHeld then
    { Drag: extend the selection. }
    ExtendSelection(SelectionAnchor.Create(AbsPos))
  else if InSelectionMode and (What = evMouseUp) and Selection.Empty then
    { Nothing was selected: stop selecting. }
    CancelSelection
  else
  begin
    { The terminal emulator gets the event. }
    TermEv := BlankTerminalEvent(TerminalEventType.Mouse);
    TermEv.Mouse.What := What;
    TermEv.Mouse.Mouse := Mouse;
    TermCtrl.SendEvent(TermEv);
  end;
end;

procedure TerminalView.Draw;
begin
  UpdateHelpContext;
  TermCtrl.LockState(@DrawWithState);
end;

procedure TerminalView.DrawWithState(St: TerminalState);
var
  Upd: TerminalUpdatedMsg;
begin
  UpdateCursor(St);
  UpdateScrollBar(St);
  UpdateDisplay(St);

  Upd.View := Self;
  Upd.State := St;
  Message(Owner, evCommand, Consts.CmTerminalUpdated, @Upd);
end;

procedure TerminalView.UpdateHelpContext;
begin
  { The help context of a selection is shown while something is selected, or when it was set by a command. }
  if InSelectionMode and ((not Selection.Empty) or (HelpCtx = Consts.HcSelecting)) then
    HelpCtx := Consts.HcSelecting
  else
    HelpCtx := hcNoContext;
end;

procedure TerminalView.UpdateCursor(St: TerminalState);
var
  Where: TPoint;
begin
  if St.CursorChanged then
  begin
    St.CursorChanged := False;
    SetState(sfCursorVis, St.CursorVisible);
    SetState(sfCursorIns, St.CursorBlink);

    Where := GetCursorDisplayedPos(St);
    SetCursor(Where.X, Where.Y);
  end;
end;

procedure TerminalView.UpdateScrollBar(St: TerminalState);
var
  Where: TPoint;
begin
  if St.ScrollbackChanged and (ScrollBar <> nil) then
  begin
    St.ScrollbackChanged := False;

    if St.ScrollbackEnabled then
    begin
      ScrollBar.SetParams(St.ScrollbackOffset, 0, St.ScrollbackLimit, Size.Y, 1);
      ScrollBar.Show;

      Where := GetCursorDisplayedPos(St);
      SetCursor(Where.X, Where.Y);
    end
    else
      ScrollBar.Hide;
  end;
end;

procedure TerminalView.UpdateDisplay(St: TerminalState);
var
  Surf: TerminalSurface;
  ReuseBuffer: Boolean;
  Area: TPoint;
  LineBuf: array of TScreenCell;
  Row, AbsRow: Integer;
  Dirty, SelHere, PrevHere: RowRange;
begin
  Surf := St.Surface;
  ReuseBuffer := CanReuseOwnerBuffer;

  Area.X := Min(Size.X, Surf.Size.X);
  Area.Y := Min(Size.Y, Surf.Size.Y);

  SetLength(LineBuf, Max(Area.X, 0));
  if Length(LineBuf) > 0 then
    FillChar(LineBuf[0], Length(LineBuf) * SizeOf(TScreenCell), 0);

  for Row := 0 to Area.Y - 1 do
  begin
    Dirty := RangeToCopy(Row, Area.X, Surf, ReuseBuffer);

    { 0 <= AbsRow < (offset of the scrollback + rows shown) }
    AbsRow := Row + St.ScrollbackOffset;
    SelHere := Selection.IntersectRow(AbsRow, Area.X);
    PrevHere := PrevSelection.IntersectRow(AbsRow, Area.X);

    { A row whose selection changed is copied where the selection was and where it is. }
    if SelHere <> PrevHere then
    begin
      Dirty.Start := Min(Min(Dirty.Start, SelHere.Start), PrevHere.Start);
      Dirty.RangeEnd := Max(Max(Dirty.RangeEnd, SelHere.RangeEnd), PrevHere.RangeEnd);
    end;
    { A selection that begins or ends outside the view must not take a cell that the view does not have. }
    if Dirty.Start < 0 then
      Dirty.Start := 0;
    if Dirty.RangeEnd > Area.X then
      Dirty.RangeEnd := Area.X;

    if Dirty.Size > 0 then
    begin
      Move(Surf.At(Row, Dirty.Start)^, LineBuf[Dirty.Start], SizeOf(TScreenCell) * Dirty.Size);
      DrawSelection(LineBuf, Dirty.Intersect(SelHere));
      WriteLine(SmallInt(Dirty.Start), SmallInt(Row), SmallInt(Dirty.Size), 1,
        PScreenCell(@LineBuf[Dirty.Start]));
    end;
  end;

  Surf.ClearDamage;
  PrevSelection := Selection;
end;

function TerminalView.CanReuseOwnerBuffer: Boolean;
begin
  if OwnerBufferChanged then
  begin
    OwnerBufferChanged := False;
    Result := False;
    Exit;
  end;
  Result := (Owner <> nil) and (Owner.Buffer <> nil);
end;

function TerminalView.GetCursorDisplayedPos(St: TerminalState): TPoint;
begin
  Result := St.CursorPos;
  if St.ScrollbackEnabled then
    Result.Y := Result.Y + (St.ScrollbackLimit - St.ScrollbackOffset);
end;

procedure TerminalView.StartSelection;
begin
  StartSelection(SelectionAnchor.Create(0, 0));
end;

procedure TerminalView.StartSelection(const Pos: SelectionAnchor);
begin
  Selection.Start := Pos;
  Selection.RangeEnd := Pos;
  InSelectionMode := True;
end;

procedure TerminalView.ExtendSelection(const Pos: SelectionAnchor);
begin
  Selection.RangeEnd := Pos;
  DrawView;
end;

procedure TerminalView.CancelSelection;
begin
  FillChar(Selection, SizeOf(Selection), 0);
  InSelectionMode := False;
  DrawView;
end;

procedure TerminalView.CopySelection;
var
  TermEv: TerminalEvent;
begin
  if not Selection.Empty then
  begin
    TermEv := BlankTerminalEvent(TerminalEventType.CopySelection);
    TermEv.CopySelection.Selection := Selection;
    TermCtrl.SendEvent(TermEv);
  end;
  CancelSelection;
end;

{ BasicTerminalFrame }

constructor BasicTerminalFrame.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
end;

procedure BasicTerminalFrame.Draw;
var
  Spot: TRect;
  Painter: TDrawBuffer;
  Caption: string;
  Tint: TColorAttr;
  TintByte: Byte;
  Shown: Word;
begin
  inherited Draw;

  if (State and sfDragging) = 0 then
    Exit;
  Spot := TRect.Create(4, Size.Y - 1, Min(Size.X - 4, 14), Size.Y);
  if (Spot.A.X < Spot.B.X) and (Spot.A.Y < Spot.B.Y) then
  begin
    Caption := ' ' + IntToStr(Max(Size.X - 2, 0)) + 'x' + IntToStr(Max(Size.Y - 2, 0)) + ' ';
    Tint := MapColor(5);
    TintByte := Tint;
    Painter := TDrawBuffer.Create;
    try
      Shown := Painter.MoveStr(0, Caption, TColorAttr.Create(TintByte), Word(Spot.B.X - Spot.A.X));
      WriteLine(SmallInt(Spot.A.X), SmallInt(Spot.A.Y), SmallInt(Shown), SmallInt(Spot.B.Y - Spot.A.Y), Painter);
    finally
      Painter.Free;
    end;
  end;
end;

{ BasicTerminalWindow }

class function BasicTerminalWindow.InitFrame(Area: TRect): TFrame;
begin
  Result := BasicTerminalFrame.Create(Area);
end;

constructor BasicTerminalWindow.Create(const Bounds: TRect; ATermCtrl: TerminalController;
  const AConsts: TVTermConstants);
var
  Area: TRect;
  Bar: TScrollBar;
  Span: TWordSpan;
  Walk: PWord;
  K: Integer;
begin
  inherited Create(Bounds, '', wnNoNumber, @BasicTerminalWindow.InitFrame);
  Consts := AConsts;
  View := nil;
  TitleCapacity := 0;
  TermTitle := GrowArray.Create;

  Options := Options or ofTileable;
  EventMask := EventMask or evBroadcast;
  SetState(sfShadow, False);

  Area := GetExtent;
  Area.Grow(0, -1);
  Area.A.X := Area.B.X - 1;
  Bar := TScrollBar.Create(Area);
  Insert(Bar);

  Area := GetExtent;
  Area.Grow(-1, -1);
  View := TerminalView.Create(Area, ATermCtrl, AConsts, Bar);
  Insert(View);

  FocusedCmds := TCommandSet.Create;
  Span := Consts.FocusedCmds;
  Walk := Span.Data;
  for K := 1 to Integer(Span.Size) do
  begin
    FocusedCmds.AddAssign(Walk^);
    Inc(Walk);
  end;
  FocusedCmds.AddAssign(cmPaste);
end;

destructor BasicTerminalWindow.Destroy;
begin
  TermTitle.Free;
  inherited Destroy;
end;

procedure BasicTerminalWindow.ShutDown;
begin
  View := nil;
  inherited ShutDown;
end;

procedure BasicTerminalWindow.CheckChanges(var Upd: TerminalUpdatedMsg);
begin
  if (Frame <> nil) and UpdateTitle(TerminalView(Upd.View).TermCtrl, Upd.State) then
    Frame.DrawView;
end;

function BasicTerminalWindow.UpdateTitle(Term: TerminalController; St: TerminalState): Boolean;
begin
  if St.TitleChanged then
  begin
    St.TitleChanged := False;
    { The title of the state moves to the window. }
    TermTitle.Clear;
    TermTitle.Push(St.Title.Data, St.Title.Size);
    St.Title.Clear;
    Result := True;
  end
  else
    { When the client has just ended, the title does not change but it has to be drawn again. }
    Result := Term.ClientIsDisconnected;
end;

procedure BasicTerminalWindow.ResizeTitle(ACapacity: SizeUInt);
begin
  if TitleCapacity < ACapacity then
  begin
    if Title <> nil then
      FreeMem(Title);
    GetMem(Title, ACapacity);
    TitleCapacity := ACapacity;
  end;
end;

function BasicTerminalWindow.IsDisconnected: Boolean;
begin
  Result := (View = nil) or View.TermCtrl.ClientIsDisconnected;
end;

function BasicTerminalWindow.GetTitle(RoomLeft: SmallInt): PAnsiChar;
var
  Tail: AnsiString;
  TextLen, TailLen, Total: SizeUInt;
  Block: PAnsiChar;
begin
  if IsDisconnected then
    Tail := ' (Disconnected)'
  else if HelpCtx = Consts.HcInputGrabbed then
    Tail := ' (Input Grab)'
  else
    Tail := '';

  Result := nil;
  TextLen := TermTitle.Size;
  TailLen := Length(Tail);
  Total := TextLen + TailLen;
  if Total = 0 then
    Exit;

  ResizeTitle(Total + 1);
  Block := Title;
  if TextLen > 0 then
    Move(TermTitle.Data^, Block^, TextLen);
  if TailLen > 0 then
    Move(Tail[1], Block[TextLen], TailLen);
  Block[Total] := #0;
  Result := Block;
end;

procedure BasicTerminalWindow.HandleEvent(var Ev: TEvent);
begin
  case Ev.What of
    evCommand:
      if (Ev.Message.Command = Consts.CmGrabInput) and (HelpCtx <> Consts.HcInputGrabbed) and
        (Owner <> nil) then
      begin
        Owner.ExecView(Self);
        ClearEvent(Ev);
      end
      else if ((Ev.Message.Command = cmClose) or (Ev.Message.Command = Consts.CmReleaseInput)) and
        ((State and sfModal) <> 0) then
      begin
        EndModal(cmCancel);
        if Ev.Message.Command = cmClose then
          PutEvent(Ev);
        ClearEvent(Ev);
      end
      else if (Ev.Message.Command = Consts.CmTerminalUpdated) and (Ev.Message.InfoPtr <> nil) then
        CheckChanges(PTerminalUpdatedMsg(Ev.Message.InfoPtr)^);

    evMouseDown:
      if ((State and sfModal) <> 0) and not MouseInView(Ev.Mouse.Where) then
      begin
        EndModal(cmCancel);
        PutEvent(Ev);
        ClearEvent(Ev);
      end;
  end;

  if IsDisconnected and ((State and sfModal) <> 0) then
    EndModal(cmCancel);
  inherited HandleEvent(Ev);
end;

procedure BasicTerminalWindow.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if AState = sfActive then
    SetCmdState(FocusedCmds, Enable);
end;

function BasicTerminalWindow.Execute: Word;
var
  PrevHelp: Word;
begin
  PrevHelp := HelpCtx;
  HelpCtx := Consts.HcInputGrabbed;
  if Frame <> nil then
    Frame.DrawView;

  inherited Execute;

  HelpCtx := PrevHelp;
  if Frame <> nil then
    Frame.DrawView;
  Result := 0;
end;

class function BasicTerminalWindow.ViewBounds(const WindowBounds: TRect): TRect;
begin
  Result := WindowBounds;
  Result.Grow(-1, -1);
end;

class function BasicTerminalWindow.ViewSize(const WindowBounds: TRect): TPoint;
var
  Inner: TRect;
begin
  Inner := ViewBounds(WindowBounds);
  Result := Inner.B - Inner.A;
end;

end.
