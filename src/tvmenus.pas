{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/menus.h, include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h,
  include/tvision/views.h, source/tvision/menu.cpp, source/tvision/popupmnu.cpp, source/tvision/tmenubar.cpp,
  source/tvision/tmenubox.cpp, source/tvision/tmenupop.cpp, source/tvision/tmnuview.cpp,
  source/tvision/tstatusl.cpp, source/tvision/tvtext1.cpp
  See COPYRIGHT.magiblot.

  The views of this unit are used by the thread of the user interface only.

  A text of the C++ that is a char pointer which may be null (the name and the parameter of a menu item, the text
  of a status item) is a PAnsiChar, allocated by NewStr and released with FreeMem; a null name marks a separator.
  The argument of a constructor or of a routine that is a TStringView is a string. The union of param and subMenu
  of TMenuItem is one pointer, which the properties Param and SubMenu read and write. Because a Pascal string has
  no null value, a constructor of TMenuItem always allocates the name, and NewLine, which has a null name, releases
  it. The reference parameters of the C++ that stand for objects are object parameters.

  The operators + that chain menu items, sub menus, status items and status definitions are global operators.

  Streaming members (read, write, build, streamableName, the constructors with StreamableInit) are not part of
  this unit.

  Parts of the C++ that no input defines are reached through hooks, which do nothing while they are nil:
    - hotKeyStr stands for HotKeyStrHook; while it is nil, a menu item has no shortcut character;
    - TText::equalsIgnoreCase stands for EqualsIgnoreCaseHook; while it is nil, two texts are not equal;
    - TProgram::application stands for ApplicationHook; while it is nil, PopupMenu answers 0.
  The tables TMenuBox.FrameChars and TStatusLine.HintSeparator are class variables, set to their values when the
  unit starts. The characters are code page 437 bytes written as numbers. }
unit TvMenus;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvKeys, TvEvents, TvObjs, TvColors, TvDrawBuf, TvViews;

type
  TMenu = class;
  TMenuItem = class;
  TSubMenu = class;
  TMenuView = class;
  TMenuBox = class;
  TStatusItem = class;
  TStatusDef = class;

  TMenuItem = class
  private
    { Holds param (a PAnsiChar) when Command is not 0 and subMenu (a TMenu) when it is 0. }
    Ptr: Pointer;
    function GetParam: PAnsiChar;
    procedure SetParam(Value: PAnsiChar);
    function GetSubMenu: TMenu;
    procedure SetSubMenu(Value: TMenu);
  public
    Next: TMenuItem;
    Name: PAnsiChar;
    Command: Word;
    Disabled: Boolean;
    KeyCode: TKey;
    HelpCtx: Word;
    constructor Create(const AName: string; ACommand: Word; AKey: TKey; AHelpCtx: Word = hcNoContext;
      const P: string = ''; ANext: TMenuItem = nil); overload;
    constructor Create(const AName: string; AKey: TKey; ASubMenu: TMenu; AHelpCtx: Word = hcNoContext;
      ANext: TMenuItem = nil); overload;
    destructor Destroy; override;
    procedure Append(ANext: TMenuItem);
    property Param: PAnsiChar read GetParam write SetParam;
    property SubMenu: TMenu read GetSubMenu write SetSubMenu;
  end;

  TSubMenu = class(TMenuItem)
  public
    constructor Create(const Nm: string; Key: TKey; AHelpCtx: Word = hcNoContext); reintroduce;
  end;

  TMenu = class
  public
    Items: TMenuItem;
    Deflt: TMenuItem;
    constructor Create; overload;
    constructor Create(ItemList: TMenuItem); overload;
    constructor Create(ItemList, TheDefault: TMenuItem); overload;
    destructor Destroy; override;
  end;

  { Palette layout
      1 = Normal text
      2 = Disabled text
      3 = Shortcut text
      4 = Normal selection
      5 = Disabled selection
      6 = Shortcut selection }
  TMenuView = class(TView)
  protected
    ParentMenu: TMenuView;
    Menu: TMenu;
    Current: TMenuItem;
    PutClickEventOnExit: Boolean;
  private
    procedure NextItem;
    procedure PrevItem;
    procedure TrackKey(FindNext: Boolean);
    function MouseInOwner(var E: TEvent): Boolean;
    function MouseInMenus(var E: TEvent): Boolean;
    procedure TrackMouse(var E: TEvent; var MouseActive: Boolean);
    function TopMenu: TMenuView;
    function UpdateMenu(AMenu: TMenu): Boolean;
    procedure DoASelect(var Event: TEvent);
    function FindHotKey(P: TMenuItem; Key: TKey): TMenuItem;
    function FindAltShortcut(const KeyDown: TKeyDownEvent): TMenuItem;
  public
    constructor Create(const Bounds: TRect; AMenu: TMenu; AParent: TMenuView); reintroduce; overload;
    constructor Create(const Bounds: TRect); reintroduce; overload;
    function Execute: Word; override;
    function FindItem(Shortcut: Char): TMenuItem; overload;
    function FindItem(const Shortcut: string): TMenuItem; overload;
    function GetItemRect(Item: TMenuItem): TRect; virtual;
    function GetHelpCtx: Word; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function HotKey(Key: TKey): TMenuItem;
    function NewSubView(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView): TMenuView;
  end;

  TMenuBar = class(TMenuView)
  public
    constructor Create(const Bounds: TRect; AMenu: TMenu); reintroduce; overload;
    constructor Create(const Bounds: TRect; AMenu: TSubMenu); reintroduce; overload;
    destructor Destroy; override;
    procedure Draw; override;
    function GetItemRect(Item: TMenuItem): TRect; override;
  end;

  TMenuBox = class(TMenuView)
  private
    { The attributes that frameLine and draw share: the C++ keeps them in file-level variables. }
    CNormal: TAttrPair;
    Color: TAttrPair;
    procedure FrameLine(B: TDrawBuffer; N: SmallInt);
  public
    { The characters of the frame lines: four groups of five characters for the top line, the bottom line, an
      item line and a separator line. It is set when the unit starts. }
    class var FrameChars: string;
    constructor Create(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView); reintroduce;
    procedure Draw; override;
    function GetItemRect(Item: TMenuItem): TRect; override;
  end;

  TMenuPopup = class(TMenuBox)
  public
    constructor Create(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView = nil); reintroduce;
    destructor Destroy; override;
    function Execute: Word; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  TStatusItem = class
  public
    Next: TStatusItem;
    Text: PAnsiChar;
    KeyCode: TKey;
    Command: Word;
    constructor Create(const AText: string; AKey: TKey; Cmd: Word; ANext: TStatusItem = nil);
    destructor Destroy; override;
  end;

  TStatusDef = class
  public
    Next: TStatusDef;
    Min: Word;
    Max: Word;
    Items: TStatusItem;
    constructor Create(AMin, AMax: Word; SomeItems: TStatusItem = nil; ANext: TStatusDef = nil);
  end;

  { Palette layout
      1 = Normal text
      2 = Disabled text
      3 = Shortcut text
      4 = Normal selection
      5 = Disabled selection
      6 = Shortcut selection }
  TStatusLine = class(TView)
  protected
    Items: TStatusItem;
    Defs: TStatusDef;
  private
    procedure DrawSelect(Selected: TStatusItem);
    procedure FindItems;
    function ItemMouseIsIn(Mouse: TPoint): TStatusItem;
    procedure DisposeItems(Item: TStatusItem);
  public
    { The text between the items and the hint. It is set when the unit starts. }
    class var HintSeparator: string;
    constructor Create(const Bounds: TRect; ADefs: TStatusDef); reintroduce;
    destructor Destroy; override;
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Hint(AHelpCtx: Word): string; virtual;
    procedure Update;
  end;

  { Gives the shortcut of a menu item name (the Name is empty for a separator); the answer is empty when the
    name has no shortcut. }
  THotKeyStrFunc = function(const Name: string): string;
  { Tells whether two texts are equal when the case of letters is ignored. }
  TEqualsIgnoreCaseFunc = function(const A, B: string): Boolean;
  { Gives the root of the application, or nil. }
  TApplicationFunc = function: TGroup;

var
  HotKeyStrHook: THotKeyStrFunc;
  EqualsIgnoreCaseHook: TEqualsIgnoreCaseFunc;
  ApplicationHook: TApplicationFunc;

{ A separator line for a menu: an item without a name. }
function NewLine: TMenuItem;

{ Spawns and executes a TMenuPopup on the desktop. Where is the reference position in absolute coordinates; the top
  left corner of the popup is placed at (Where.X, Where.Y + 1) when there is room. AMenu is a chain of menu items,
  which the routine takes ownership of: the items are released with the popup. When Receiver is not nil and a
  command is selected, an evCommand event with it is put into Receiver with PutEvent. Returns the selected
  command, or 0. }
function PopupMenu(Where: TPoint; AMenu: TMenuItem; Receiver: TGroup): Word;

{ Each operator appends its second operand to the end of the chain of the first. The first operand is the result. }
operator +(S: TSubMenu; I: TMenuItem): TSubMenu;
operator +(S1, S2: TSubMenu): TSubMenu;
operator +(I1, I2: TMenuItem): TMenuItem;
operator +(S1: TStatusDef; S2: TStatusItem): TStatusDef;
operator +(S1, S2: TStatusDef): TStatusDef;

implementation

uses
  TvUtil;

const
  CpMenuView = #2#3#4#5#6#7;
  CpStatusLine = #2#3#4#5#6#7;

type
  TMenuAction = (doNothing, doSelect, doReturn);

var
  MenuViewPalette: TPalette;
  StatusLinePalette: TPalette;

{ The text of a char pointer that may be null. }
function CStrOf(P: PAnsiChar): string;
begin
  if P = nil then
    Result := ''
  else
    Result := P;
end;

{ Turns Event into a command event for Cmd, without an information pointer. }
procedure SetCommandEvent(var Event: TEvent; Cmd: Word);
begin
  Event.What := evCommand;
  Event.Message.InfoPtr := nil;
  Event.Message.Command := Cmd;
end;

{ Sends a command event for Cmd through View and clears Event. }
procedure PostCommand(View: TView; var Event: TEvent; Cmd: Word);
begin
  SetCommandEvent(Event, Cmd);
  View.PutEvent(Event);
  View.ClearEvent(Event);
end;

function HotKeyStrOf(Name: PAnsiChar): string;
begin
  if Assigned(HotKeyStrHook) then
    Result := HotKeyStrHook(CStrOf(Name))
  else
    Result := '';
end;

function EqualsIgnoreCase(const A, B: string): Boolean;
begin
  if Assigned(EqualsIgnoreCaseHook) then
    Result := EqualsIgnoreCaseHook(A, B)
  else
    Result := False;
end;

{ TMenuItem }

constructor TMenuItem.Create(const AName: string; ACommand: Word; AKey: TKey; AHelpCtx: Word; const P: string;
  ANext: TMenuItem);
begin
  inherited Create;
  Name := NewStr(AName);
  Command := ACommand;
  Disabled := not TView.CommandEnabled(Command);
  KeyCode := AKey;
  HelpCtx := AHelpCtx;
  if P = '' then
    Ptr := nil
  else
    Ptr := NewStr(P);
  Next := ANext;
end;

constructor TMenuItem.Create(const AName: string; AKey: TKey; ASubMenu: TMenu; AHelpCtx: Word; ANext: TMenuItem);
begin
  inherited Create;
  Name := NewStr(AName);
  Command := 0;
  Disabled := not TView.CommandEnabled(Command);
  KeyCode := AKey;
  HelpCtx := AHelpCtx;
  Ptr := ASubMenu;
  Next := ANext;
end;

destructor TMenuItem.Destroy;
begin
  FreeMem(Name);
  if Command = 0 then
    TMenu(Ptr).Free
  else
    FreeMem(Ptr);
  inherited Destroy;
end;

function TMenuItem.GetParam: PAnsiChar;
begin
  Result := PAnsiChar(Ptr);
end;

procedure TMenuItem.SetParam(Value: PAnsiChar);
begin
  Ptr := Value;
end;

function TMenuItem.GetSubMenu: TMenu;
begin
  Result := TMenu(Ptr);
end;

procedure TMenuItem.SetSubMenu(Value: TMenu);
begin
  Ptr := Value;
end;

procedure TMenuItem.Append(ANext: TMenuItem);
begin
  Next := ANext;
end;

function NewLine: TMenuItem;
begin
  Result := TMenuItem.Create('', 0, TKey.Create(0), hcNoContext, '', nil);
  FreeMem(Result.Name);
  Result.Name := nil;
end;

{ TSubMenu }

constructor TSubMenu.Create(const Nm: string; Key: TKey; AHelpCtx: Word);
begin
  inherited Create(Nm, Key, TMenu.Create, AHelpCtx);
end;

{ TMenu }

constructor TMenu.Create;
begin
  inherited Create;
  Items := nil;
  Deflt := nil;
end;

constructor TMenu.Create(ItemList: TMenuItem);
begin
  inherited Create;
  Items := ItemList;
  Deflt := ItemList;
end;

constructor TMenu.Create(ItemList, TheDefault: TMenuItem);
begin
  inherited Create;
  Items := ItemList;
  Deflt := TheDefault;
end;

destructor TMenu.Destroy;
var
  Temp: TMenuItem;
begin
  while Items <> nil do
  begin
    Temp := Items;
    Items := Items.Next;
    Temp.Free;
  end;
  inherited Destroy;
end;

{ The operators that chain items }

operator +(S: TSubMenu; I: TMenuItem): TSubMenu;
var
  Sub: TSubMenu;
  Cur: TMenuItem;
begin
  Sub := S;
  while Sub.Next <> nil do
    Sub := TSubMenu(Sub.Next);

  if Sub.SubMenu.Items = nil then
  begin
    Sub.SubMenu.Items := I;
    Sub.SubMenu.Deflt := I;
  end
  else
  begin
    Cur := Sub.SubMenu.Items;
    while Cur.Next <> nil do
      Cur := Cur.Next;
    Cur.Next := I;
  end;
  Result := S;
end;

operator +(S1, S2: TSubMenu): TSubMenu;
var
  Cur: TMenuItem;
begin
  Cur := S1;
  while Cur.Next <> nil do
    Cur := Cur.Next;
  Cur.Next := S2;
  Result := S1;
end;

operator +(I1, I2: TMenuItem): TMenuItem;
var
  Cur: TMenuItem;
begin
  Cur := I1;
  while Cur.Next <> nil do
    Cur := Cur.Next;
  Cur.Next := I2;
  Result := I1;
end;

operator +(S1: TStatusDef; S2: TStatusItem): TStatusDef;
var
  Def: TStatusDef;
  Cur: TStatusItem;
begin
  Def := S1;
  while Def.Next <> nil do
    Def := Def.Next;
  if Def.Items = nil then
    Def.Items := S2
  else
  begin
    Cur := Def.Items;
    while Cur.Next <> nil do
      Cur := Cur.Next;
    Cur.Next := S2;
  end;
  Result := S1;
end;

operator +(S1, S2: TStatusDef): TStatusDef;
var
  Cur: TStatusDef;
begin
  Cur := S1;
  while Cur.Next <> nil do
    Cur := Cur.Next;
  Cur.Next := S2;
  Result := S1;
end;

{ TMenuView }

constructor TMenuView.Create(const Bounds: TRect; AMenu: TMenu; AParent: TMenuView);
begin
  inherited Create(Bounds);
  ParentMenu := AParent;
  Menu := AMenu;
  Current := nil;
  PutClickEventOnExit := True;
  EventMask := EventMask or evBroadcast;
end;

constructor TMenuView.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  ParentMenu := nil;
  Menu := nil;
  Current := nil;
  PutClickEventOnExit := True;
  EventMask := EventMask or evBroadcast;
end;

procedure TMenuView.TrackMouse(var E: TEvent; var MouseActive: Boolean);
var
  PointerSpot: TPoint;
  EntryBox: TRect;
  Walker, Hit: TMenuItem;
begin
  PointerSpot := MakeLocal(E.Mouse.Where);
  Hit := nil;
  Walker := Menu.Items;
  while (Hit = nil) and (Walker <> nil) do
  begin
    EntryBox := GetItemRect(Walker);
    if EntryBox.Contains(PointerSpot) then
      Hit := Walker
    else
      Walker := Walker.Next;
  end;
  Current := Hit;
  MouseActive := MouseActive or (Hit <> nil);
end;

procedure TMenuView.NextItem;
begin
  if Current.Next <> nil then
    Current := Current.Next
  else
    Current := Menu.Items;
end;

procedure TMenuView.PrevItem;
var
  Stop: TMenuItem;
begin
  Stop := nil;
  if Current <> Menu.Items then
    Stop := Current;
  NextItem;
  while Current.Next <> Stop do
    NextItem;
end;

procedure TMenuView.TrackKey(FindNext: Boolean);

  procedure Step;
  begin
    if FindNext then
      NextItem
    else
      PrevItem;
  end;

begin
  if Current = nil then
  begin
    Current := Menu.Items;
    if not FindNext then
      PrevItem;
    if Current.Name <> nil then
      Exit;
  end;
  Step;
  while Current.Name = nil do
    Step;
end;

function TMenuView.MouseInOwner(var E: TEvent): Boolean;
var
  Local: TPoint;
  Box: TRect;
begin
  Result := False;
  if ParentMenu <> nil then
  begin
    Local := ParentMenu.MakeLocal(E.Mouse.Where);
    Box := ParentMenu.GetItemRect(ParentMenu.Current);
    Result := Box.Contains(Local);
  end;
end;

function TMenuView.MouseInMenus(var E: TEvent): Boolean;
var
  Walker: TMenuView;
begin
  Walker := ParentMenu;
  while Walker <> nil do
  begin
    if Walker.MouseInView(E.Mouse.Where) then
      Break;
    Walker := Walker.ParentMenu;
  end;
  Result := Walker <> nil;
end;

function TMenuView.TopMenu: TMenuView;
begin
  Result := Self;
  while Result.ParentMenu <> nil do
    Result := Result.ParentMenu;
end;

function TMenuView.Execute: Word;
var
  OpenAtOnce, FirstPass, MouseActive: Boolean;
  Verdict: TMenuAction;
  LastDrawn, JustClosed: TMenuItem;
  Picked: Word;
  Incoming: TEvent;
  IsBar: Boolean;
  Remembered: TMenuItem;
  WantsOpen, CanOpen: Boolean;

  procedure OnMouseDown;
  var
    InsideSomewhere: Boolean;
  begin
    InsideSomewhere := MouseInView(Incoming.Mouse.Where) or MouseInOwner(Incoming);
    if not InsideSomewhere then
    begin
      { A click outside the bounds closes the menu; the view that recovers the focus gets the event. }
      if PutClickEventOnExit then
        PutEvent(Incoming);
      Verdict := doReturn;
      Exit;
    end;
    TrackMouse(Incoming, MouseActive);
    if IsBar then
      { A menu bar entry opens at once, unless it was just closed by a click on its name. }
      OpenAtOnce := (Current = nil) or (JustClosed <> Current)
    else if (not FirstPass) and MouseInOwner(Incoming) then
      { A sub menu closes on a click in its parent, unless it was just opened. }
      Verdict := doReturn;
  end;

  procedure OnMouseUp;
  var
    OverEntry, LeftTheView: Boolean;
  begin
    TrackMouse(Incoming, MouseActive);
    if MouseInOwner(Incoming) then
    begin
      Current := Menu.Deflt;
      Exit;
    end;
    OverEntry := Current <> nil;
    if OverEntry then
    begin
      if Current.Name = nil then
        Exit;
      if Current = JustClosed then
      begin
        if IsBar then
          Verdict := doReturn
        else
        begin
          Verdict := doNothing;
          JustClosed := nil;
        end;
      end
      else
        Verdict := doSelect;
      Exit;
    end;
    LeftTheView := MouseActive and (not MouseInView(Incoming.Mouse.Where));
    if LeftTheView then
      Verdict := doReturn
    else if not IsBar then
    begin
      { Inside a box, off any entry that can be highlighted: take the default entry or the first. }
      Verdict := doNothing;
      if Menu.Deflt <> nil then
        Current := Menu.Deflt
      else
        Current := Menu.Items;
    end;
  end;

  procedure OnMouseMove;
  var
    OnAnyMenu, DraggedToOther: Boolean;
  begin
    if Incoming.Mouse.Buttons = 0 then
      Exit;
    TrackMouse(Incoming, MouseActive);
    OnAnyMenu := MouseInView(Incoming.Mouse.Where) or MouseInOwner(Incoming);
    DraggedToOther := IsBar and MouseActive and (Current <> JustClosed);
    if (not OnAnyMenu) and MouseInMenus(Incoming) then
      Verdict := doReturn
    else if DraggedToOther then
      OpenAtOnce := True;
  end;

  procedure OnOtherKey;
  var
    Match: TMenuItem;
    Scope: TMenuView;
  begin
    Scope := Self;
    if GetAltCharStr(Incoming.KeyDown) <> '' then
    begin
      Scope := TopMenu;
      Match := Scope.FindAltShortcut(Incoming.KeyDown);
    end
    else
      Match := FindItem(Incoming.KeyDown.GetText);

    if Match = nil then
    begin
      Match := TopMenu.HotKey(Incoming.KeyDown.ToKey);
      if Match = nil then
        Exit;
      if not CommandEnabled(Match.Command) then
        Exit;
      Picked := Match.Command;
      Verdict := doReturn;
      Exit;
    end;

    if Scope = Self then
    begin
      if IsBar then
        OpenAtOnce := True;
      Verdict := doSelect;
      Current := Match;
      Exit;
    end;
    if (ParentMenu <> Scope) or (ParentMenu.Current <> Match) then
      Verdict := doReturn;
  end;

  procedure OnKeyDown;
  var
    Code: Word;
    ParentIsBar: Boolean;
  begin
    Code := Incoming.KeyDown.KeyCode;
    if (Code = kbUp) or (Code = kbDown) then
    begin
      if not IsBar then
        TrackKey(Code = kbDown)
      else if Code = kbDown then
        OpenAtOnce := True;
    end
    else if (Code = kbLeft) or (Code = kbRight) then
    begin
      if IsBar then
        TrackKey(Code = kbRight)
      else if ParentMenu <> nil then
        Verdict := doReturn;
    end
    else if (Code = kbHome) or (Code = kbEnd) then
    begin
      if not IsBar then
      begin
        Current := Menu.Items;
        if Code = kbEnd then
          TrackKey(False);
      end;
    end
    else if Code = kbEnter then
    begin
      if IsBar then
        OpenAtOnce := True;
      Verdict := doSelect;
    end
    else if Code = kbEsc then
    begin
      Verdict := doReturn;
      ParentIsBar := (ParentMenu <> nil) and (ParentMenu.Size.Y = 1);
      if not ParentIsBar then
        ClearEvent(Incoming);
    end
    else
      OnOtherKey;
  end;

  procedure OnCommand;
  begin
    if Incoming.Message.Command <> cmMenu then
    begin
      Verdict := doReturn;
      Exit;
    end;
    OpenAtOnce := False;
    JustClosed := nil;
    if ParentMenu <> nil then
      Verdict := doReturn;
  end;

  procedure OpenSelected;
  var
    EntryBox, Slot: TRect;
    Spawned: TMenuView;
  begin
    if (Incoming.What and (evMouseDown or evMouseMove)) <> 0 then
      PutEvent(Incoming);
    EntryBox := GetItemRect(Current);
    Slot.A.X := EntryBox.A.X + Origin.X;
    Slot.A.Y := EntryBox.B.Y + Origin.Y;
    Slot.B := Owner.Size;
    if IsBar then
      Slot.A.X := Slot.A.X - 1;
    Spawned := TopMenu.NewSubView(Slot, Current.SubMenu, Self);
    Picked := Owner.ExecView(Spawned);
    TvObject.DestroyObject(Spawned);
    JustClosed := Current;
    Menu.Deflt := Current;
  end;

begin
  OpenAtOnce := False;
  FirstPass := True;
  MouseActive := False;
  Picked := 0;
  LastDrawn := nil;
  JustClosed := nil;
  IsBar := Size.Y = 1;
  Current := Menu.Deflt;

  while True do
  begin
    Verdict := doNothing;
    GetEvent(Incoming);
    case Incoming.What of
      evMouseDown: OnMouseDown;
      evMouseUp: OnMouseUp;
      evMouseMove: OnMouseMove;
      evKeyDown: OnKeyDown;
      evCommand: OnCommand;
    end;

    { A sub menu closed by a click on its name opens again only after the mouse moved to another entry. }
    if JustClosed <> Current then
      JustClosed := nil;

    if LastDrawn <> Current then
    begin
      LastDrawn := Current;
      DrawView;
    end;

    WantsOpen := (Verdict = doSelect) or ((Verdict = doNothing) and OpenAtOnce);
    CanOpen := (Current <> nil) and (Current.Name <> nil);
    if WantsOpen and CanOpen then
    begin
      if (Current.Command = 0) and (not Current.Disabled) then
        OpenSelected
      else if Verdict = doSelect then
        Picked := Current.Command;
    end;

    if (Picked <> 0) and CommandEnabled(Picked) then
    begin
      Verdict := doReturn;
      ClearEvent(Incoming);
    end
    else
      Picked := 0;

    FirstPass := False;
    if Verdict = doReturn then
      Break;
  end;

  if Incoming.What <> evNothing then
    if (ParentMenu <> nil) or (Incoming.What = evCommand) then
      PutEvent(Incoming);
  Result := Picked;
  Remembered := Current;
  Current := nil;
  if Remembered <> nil then
  begin
    Menu.Deflt := Remembered;
    DrawView;
  end;
end;

function TMenuView.FindItem(Shortcut: Char): TMenuItem;
var
  S: string;
begin
  S := Shortcut;
  Result := FindItem(S);
end;

function TMenuView.FindItem(const Shortcut: string): TMenuItem;
begin
  Result := Menu.Items;
  while Result <> nil do
  begin
    if (not Result.Disabled) and (HotKeyStrOf(Result.Name) <> '') and
       EqualsIgnoreCase(Shortcut, HotKeyStrOf(Result.Name)) then
      Exit;
    Result := Result.Next;
  end;
end;

function TMenuView.FindAltShortcut(const KeyDown: TKeyDownEvent): TMenuItem;
begin
  if KeyDown.GetText <> '' then
    Result := FindItem(GetAltCharStr(KeyDown))
  else
    Result := nil;
  if Result = nil then
    Result := FindItem(GetAltChar(KeyDown.KeyCode));
end;

function TMenuView.GetItemRect(Item: TMenuItem): TRect;
begin
  Result := TRect.Create(0, 0, 0, 0);
end;

function TMenuView.GetHelpCtx: Word;
var
  Walker: TMenuView;
begin
  Walker := Self;
  while Walker <> nil do
  begin
    if (Walker.Current <> nil) and (Walker.Current.HelpCtx <> hcNoContext) and
       (Walker.Current.Name <> nil) then
      Break;
    Walker := Walker.ParentMenu;
  end;
  if Walker = nil then
    Result := HelpCtx
  else
    Result := Walker.Current.HelpCtx;
end;

function TMenuView.GetPalette: TPalette;
begin
  Result := MenuViewPalette;
end;

function TMenuView.UpdateMenu(AMenu: TMenu): Boolean;
var
  Item: TMenuItem;
  Enabled: Boolean;
begin
  Result := False;
  if AMenu = nil then
    Exit;
  Item := AMenu.Items;
  while Item <> nil do
  begin
    if Item.Name <> nil then
    begin
      if Item.Command = 0 then
      begin
        if UpdateMenu(Item.SubMenu) then
          Result := True;
      end
      else
      begin
        Enabled := CommandEnabled(Item.Command);
        if Item.Disabled = Enabled then
        begin
          Item.Disabled := not Enabled;
          Result := True;
        end;
      end;
    end;
    Item := Item.Next;
  end;
end;

procedure TMenuView.DoASelect(var Event: TEvent);
var
  Outcome: Word;
begin
  PutEvent(Event);
  Outcome := Owner.ExecView(Self);
  Event.Message.Command := Outcome;
  if (Outcome <> 0) and CommandEnabled(Outcome) then
  begin
    SetCommandEvent(Event, Outcome);
    PutEvent(Event);
  end;
  ClearEvent(Event);
end;

procedure TMenuView.HandleEvent(var Event: TEvent);
var
  Found: TMenuItem;
begin
  if Menu = nil then
    Exit;
  case Event.What of
    evMouseDown:
      DoASelect(Event);
    evKeyDown:
      begin
        if FindAltShortcut(Event.KeyDown) <> nil then
        begin
          DoASelect(Event);
          Exit;
        end;
        Found := HotKey(Event.KeyDown.ToKey);
        if Found = nil then
          Exit;
        if not CommandEnabled(Found.Command) then
          Exit;
        PostCommand(Self, Event, Found.Command);
      end;
    evCommand:
      if Event.Message.Command = cmMenu then
        DoASelect(Event);
    evBroadcast:
      if (Event.Message.Command = cmCommandSetChanged) and UpdateMenu(Menu) then
        DrawView;
  end;
end;

function TMenuView.FindHotKey(P: TMenuItem; Key: TKey): TMenuItem;
begin
  Result := nil;
  while P <> nil do
  begin
    if P.Name <> nil then
    begin
      if P.Command = 0 then
        Result := FindHotKey(P.SubMenu.Items, Key)
      else if (not P.Disabled) and (P.KeyCode <> TKey.Create(kbNoKey)) and (P.KeyCode = Key) then
        Result := P;
      if Result <> nil then
        Exit;
    end;
    P := P.Next;
  end;
end;

function TMenuView.HotKey(Key: TKey): TMenuItem;
begin
  Result := FindHotKey(Menu.Items, Key);
end;

function TMenuView.NewSubView(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView): TMenuView;
begin
  Result := TMenuBox.Create(Bounds, AMenu, AParentMenu);
end;

{ TMenuBar }

constructor TMenuBar.Create(const Bounds: TRect; AMenu: TMenu);
begin
  inherited Create(Bounds);
  Menu := AMenu;
  GrowMode := Byte(gfGrowHiX);
  Options := Options or ofPreProcess;
end;

constructor TMenuBar.Create(const Bounds: TRect; AMenu: TSubMenu);
begin
  inherited Create(Bounds);
  Menu := TMenu.Create(AMenu);
  GrowMode := Byte(gfGrowHiX);
  Options := Options or ofPreProcess;
end;

destructor TMenuBar.Destroy;
begin
  Menu.Free;
  inherited Destroy;
end;

procedure TMenuBar.Draw;
var
  Row: TDrawBuffer;
  Normal, Selected, NormDis, SelDis, Paint: TAttrPair;
  NextColumn, TextWidth: SmallInt;
  Entry: TMenuItem;

  function PickColor(Candidate: TMenuItem): TAttrPair;
  begin
    Result := Normal;
    if Candidate.Disabled then
    begin
      if Candidate = Current then
        Result := SelDis
      else
        Result := NormDis;
    end
    else if Candidate = Current then
      Result := Selected;
  end;

begin
  Row := TDrawBuffer.Create;
  try
    Normal := GetColor($0301);
    Selected := GetColor($0604);
    NormDis := GetColor($0202);
    SelDis := GetColor($0505);
    Row.MoveChar(0, ' ', Normal.Attrs[0], Word(Size.X));
    Entry := nil;
    if Menu <> nil then
      Entry := Menu.Items;
    NextColumn := 1;
    while Entry <> nil do
    begin
      if Entry.Name <> nil then
      begin
        TextWidth := Cstrlen(CStrOf(Entry.Name));
        if NextColumn + TextWidth < Size.X then
        begin
          Paint := PickColor(Entry);
          Row.MoveChar(Word(NextColumn), ' ', Paint.Attrs[0], 1);
          Row.MoveCStr(Word(NextColumn + 1), CStrOf(Entry.Name), Paint);
          Row.MoveChar(Word(NextColumn + TextWidth + 1), ' ', Paint.Attrs[0], 1);
        end;
        Inc(NextColumn, TextWidth + 2);
      end;
      Entry := Entry.Next;
    end;
    WriteBuf(0, 0, Size.X, 1, Row);
  finally
    Row.Free;
  end;
end;

function TMenuBar.GetItemRect(Item: TMenuItem): TRect;
var
  P: TMenuItem;
begin
  Result := TRect.Create(1, 0, 1, 1);
  P := Menu.Items;
  repeat
    Result.A.X := Result.B.X;
    if P.Name <> nil then
      Inc(Result.B.X, Cstrlen(CStrOf(P.Name)) + 2);
    if P = Item then
      Exit;
    P := P.Next;
  until False;
end;

{ TMenuBox }

function GetRect(const Bounds: TRect; AMenu: TMenu): TRect;
var
  Wd, Ht, Need: SmallInt;
  P: TMenuItem;
begin
  Wd := 10;
  Ht := 2;
  if AMenu <> nil then
    P := AMenu.Items
  else
    P := nil;
  while P <> nil do
  begin
    if P.Name <> nil then
    begin
      Need := Cstrlen(CStrOf(P.Name)) + 6;
      if P.Command = 0 then
        Inc(Need, 3)
      else if P.Param <> nil then
        Inc(Need, Cstrlen(CStrOf(P.Param)) + 2);
      if Need > Wd then
        Wd := Need;
    end;
    Inc(Ht);
    P := P.Next;
  end;

  Result := Bounds;

  if Result.A.X + Wd >= Result.B.X then
    Result.A.X := Result.B.X - Wd
  else
    Result.B.X := Result.A.X + Wd;

  if Result.A.Y + Ht >= Result.B.Y then
    Result.A.Y := Result.B.Y - Ht
  else
    Result.B.Y := Result.A.Y + Ht;
end;

constructor TMenuBox.Create(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView);
begin
  inherited Create(GetRect(Bounds, AMenu), AMenu, AParentMenu);
  State := State or sfShadow;
  Options := Options or ofPreProcess;
end;

procedure TMenuBox.FrameLine(B: TDrawBuffer; N: SmallInt);
begin
  if Length(FrameChars) < N + 5 then
    Exit;
  B.MoveBuf(0, @FrameChars[N + 1], CNormal.Attrs[0], 2);
  B.MoveChar(2, FrameChars[N + 3], Color.Attrs[0], Word(Size.X - 4));
  B.MoveBuf(Word(Size.X - 2), @FrameChars[N + 4], CNormal.Attrs[0], 2);
end;

procedure TMenuBox.Draw;
var
  B: TDrawBuffer;
  Selected, NormDis, SelDis: TAttrPair;
  Row: SmallInt;
  P: TMenuItem;

  function Shade(Item: TMenuItem): TAttrPair;
  begin
    Result := CNormal;
    if Item.Disabled then
    begin
      if Item = Current then
        Result := SelDis
      else
        Result := NormDis;
    end
    else if Item = Current then
      Result := Selected;
  end;

begin
  B := TDrawBuffer.Create;
  try
    CNormal := GetColor($0301);
    Selected := GetColor($0604);
    NormDis := GetColor($0202);
    SelDis := GetColor($0505);
    Color := CNormal;
    FrameLine(B, 0);
    WriteBuf(0, 0, Size.X, 1, B);
    Row := 1;
    if Menu <> nil then
    begin
      P := Menu.Items;
      while P <> nil do
      begin
        if P.Name = nil then
        begin
          Color := CNormal;
          FrameLine(B, 15);
        end
        else
        begin
          Color := Shade(P);
          FrameLine(B, 10);
          B.MoveCStr(3, CStrOf(P.Name), Color);
          if P.Command = 0 then
            B.PutChar(Word(Size.X - 4), 16)
          else if P.Param <> nil then
            B.MoveCStr(Word(Size.X - 3 - Cstrlen(CStrOf(P.Param))), CStrOf(P.Param), Color);
        end;
        WriteBuf(0, Row, Size.X, 1, B);
        Inc(Row);
        P := P.Next;
      end;
    end;
    Color := CNormal;
    FrameLine(B, 5);
    WriteBuf(0, Row, Size.X, 1, B);
  finally
    B.Free;
  end;
end;

function TMenuBox.GetItemRect(Item: TMenuItem): TRect;
var
  Row: SmallInt;
  P: TMenuItem;
begin
  Row := 1;
  P := Menu.Items;
  repeat
    if P = Item then
      Break;
    Inc(Row);
    P := P.Next;
  until False;
  Result := TRect.Create(2, Row, Size.X - 2, Row + 1);
end;

{ TMenuPopup }

constructor TMenuPopup.Create(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView);
begin
  inherited Create(Bounds, AMenu, AParentMenu);
  PutClickEventOnExit := False;
end;

destructor TMenuPopup.Destroy;
begin
  Menu.Free;
  inherited Destroy;
end;

function TMenuPopup.Execute: Word;
begin
  { The default entry is not highlighted, because it would look ugly. }
  Menu.Deflt := nil;
  Result := inherited Execute;
end;

procedure TMenuPopup.HandleEvent(var Event: TEvent);
var
  Candidate: TMenuItem;
begin
  if Event.What = evKeyDown then
  begin
    Candidate := FindItem(GetCtrlChar(Event.KeyDown.KeyCode));
    if Candidate = nil then
      Candidate := HotKey(TKey.Create(Event.KeyDown.KeyCode));
    if (Candidate <> nil) and CommandEnabled(Candidate.Command) then
      PostCommand(Self, Event, Candidate.Command)
    else if GetAltChar(Event.KeyDown.KeyCode) <> #0 then
      ClearEvent(Event);
  end;
  inherited HandleEvent(Event);
end;

{ PopupMenu }

{ Pre: M was constructed with the bounds (P, P). }
procedure AutoPlacePopup(M: TMenuPopup; P: TPoint);
var
  App: TGroup;
  R: TRect;
  D: TPoint;
begin
  App := ApplicationHook();
  { Initially, the menu is placed above P, so it must be moved. }
  R := M.GetBounds;
  { The popup must not go beyond the bottom right corner of the desktop, for usability. }
  D := App.Size - P;
  R.Move(Min(M.Size.X, D.X), Min(M.Size.Y + 1, D.Y));
  { If the popup then contains P, try to move it to a better place. }
  if R.Contains(P) and (R.B.Y - R.A.Y < P.Y) then
    R.Move(0, -(R.B.Y - P.Y));
  M.SetBounds(R);
end;

function PopupMenu(Where: TPoint; AMenu: TMenuItem; Receiver: TGroup): Word;
var
  Res: Word;
  App: TGroup;
  P: TPoint;
  Bounds: TRect;
  Menu: TMenu;
  MenuPopup: TMenuPopup;
  Event: TEvent;
begin
  Res := 0;
  if Assigned(ApplicationHook) then
    App := ApplicationHook()
  else
    App := nil;
  if App <> nil then
  begin
    P := App.MakeLocal(Where);
    Bounds := TRect.Create(P, P);
    Menu := TMenu.Create(AMenu);
    MenuPopup := TMenuPopup.Create(Bounds, Menu);
    AutoPlacePopup(MenuPopup, P);
    { Execute and dispose the menu. }
    Res := App.ExecView(MenuPopup);
    TvObject.DestroyObject(MenuPopup);
    { Generate an event. }
    if (Res <> 0) and (Receiver <> nil) then
    begin
      FillChar(Event, SizeOf(Event), 0);
      Event.What := evCommand;
      Event.Message.Command := Res;
      Receiver.PutEvent(Event);
    end;
  end;
  Result := Res;
end;

{ TStatusItem }

constructor TStatusItem.Create(const AText: string; AKey: TKey; Cmd: Word; ANext: TStatusItem);
begin
  inherited Create;
  Next := ANext;
  Text := NewStr(AText);
  KeyCode := AKey;
  Command := Cmd;
end;

destructor TStatusItem.Destroy;
begin
  FreeMem(Text);
  inherited Destroy;
end;

{ TStatusDef }

constructor TStatusDef.Create(AMin, AMax: Word; SomeItems: TStatusItem; ANext: TStatusDef);
begin
  inherited Create;
  Next := ANext;
  Min := AMin;
  Max := AMax;
  Items := SomeItems;
end;

{ TStatusLine }

constructor TStatusLine.Create(const Bounds: TRect; ADefs: TStatusDef);
begin
  inherited Create(Bounds);
  Defs := ADefs;
  Options := Options or ofPreProcess;
  EventMask := EventMask or evBroadcast;
  GrowMode := Byte(gfGrowLoY or gfGrowHiX or gfGrowHiY);
  FindItems;
end;

procedure TStatusLine.DisposeItems(Item: TStatusItem);
var
  T: TStatusItem;
begin
  while Item <> nil do
  begin
    T := Item;
    Item := Item.Next;
    T.Free;
  end;
end;

destructor TStatusLine.Destroy;
var
  T: TStatusDef;
begin
  while Defs <> nil do
  begin
    T := Defs;
    Defs := Defs.Next;
    DisposeItems(T.Items);
    T.Free;
  end;
  inherited Destroy;
end;

procedure TStatusLine.Draw;
begin
  DrawSelect(nil);
end;

procedure TStatusLine.DrawSelect(Selected: TStatusItem);
var
  Row: TDrawBuffer;
  Normal, Chosen, NormDis, SelDis, Paint: TAttrPair;
  Entry: TStatusItem;
  NextColumn, TextWidth: Integer;
  HintText: string;

  function Shade(Candidate: TStatusItem): TAttrPair;
  var
    IsSelected: Boolean;
  begin
    IsSelected := Candidate = Selected;
    if not CommandEnabled(Candidate.Command) then
    begin
      if IsSelected then
        Result := SelDis
      else
        Result := NormDis;
    end
    else if IsSelected then
      Result := Chosen
    else
      Result := Normal;
  end;

  procedure DrawItems;
  begin
    Entry := Items;
    while Entry <> nil do
    begin
      if Entry.Text <> nil then
      begin
        TextWidth := Cstrlen(CStrOf(Entry.Text));
        if NextColumn + TextWidth < Size.X then
        begin
          Paint := Shade(Entry);
          Row.MoveChar(Word(NextColumn), ' ', Paint.Attrs[0], 1);
          Row.MoveCStr(Word(NextColumn + 1), CStrOf(Entry.Text), Paint);
          Row.MoveChar(Word(NextColumn + TextWidth + 1), ' ', Paint.Attrs[0], 1);
        end;
        Inc(NextColumn, TextWidth + 2);
      end;
      Entry := Entry.Next;
    end;
  end;

  procedure DrawHint;
  begin
    HintText := '';
    if NextColumn < Size.X - 2 then
      HintText := Hint(HelpCtx);
    if HintText = '' then
      Exit;
    Row.MoveStr(Word(NextColumn), HintSeparator, Normal.Attrs[0]);
    Inc(NextColumn, 2);
    Row.MoveStr(Word(NextColumn), HintText, Normal.Attrs[0], Word(Size.X - NextColumn));
  end;

begin
  Row := TDrawBuffer.Create;
  try
    Normal := GetColor($0301);
    Chosen := GetColor($0604);
    NormDis := GetColor($0202);
    SelDis := GetColor($0505);
    Row.MoveChar(0, ' ', Normal.Attrs[0], Word(Size.X));
    NextColumn := 0;
    DrawItems;
    DrawHint;
    WriteLine(0, 0, Size.X, 1, Row);
  finally
    Row.Free;
  end;
end;

procedure TStatusLine.FindItems;
var
  Def: TStatusDef;
begin
  Items := nil;
  Def := Defs;
  while Def <> nil do
  begin
    if (HelpCtx >= Def.Min) and (HelpCtx <= Def.Max) then
    begin
      Items := Def.Items;
      Break;
    end;
    Def := Def.Next;
  end;
end;

function TStatusLine.GetPalette: TPalette;
begin
  Result := StatusLinePalette;
end;

function TStatusLine.ItemMouseIsIn(Mouse: TPoint): TStatusItem;
var
  First, Past: Integer;
begin
  Result := nil;
  if Mouse.Y <> 0 then
    Exit;
  First := 0;
  Result := Items;
  while Result <> nil do
  begin
    if Result.Text <> nil then
    begin
      Past := First + Cstrlen(CStrOf(Result.Text)) + 2;
      if (Mouse.X >= First) and (Mouse.X < Past) then
        Exit;
      First := Past;
    end;
    Result := Result.Next;
  end;
end;

procedure TStatusLine.HandleEvent(var Event: TEvent);

  procedure OnPress;
  var
    Pressed, Hovered: TStatusItem;
  begin
    Pressed := nil;
    while True do
    begin
      Hovered := ItemMouseIsIn(MakeLocal(Event.Mouse.Where));
      if Pressed <> Hovered then
      begin
        Pressed := Hovered;
        DrawSelect(Pressed);
      end;
      if not MouseEvent(Event, evMouseMove) then
        Break;
    end;

    if (Pressed <> nil) and CommandEnabled(Pressed.Command) then
      PostCommand(Self, Event, Pressed.Command)
    else
      ClearEvent(Event);
    DrawView;
  end;

  procedure OnKey;
  var
    Found: TStatusItem;
  begin
    Found := nil;
    if Event.KeyDown.KeyCode <> kbNoKey then
    begin
      Found := Items;
      while (Found <> nil) and
            not (CommandEnabled(Found.Command) and (Event.KeyDown.ToKey = Found.KeyCode)) do
        Found := Found.Next;
    end;
    if Found <> nil then
      SetCommandEvent(Event, Found.Command);
  end;

  procedure OnBroadcast;
  begin
    if Event.Message.Command <> cmCommandSetChanged then
      Exit;
    DrawView;
  end;

  procedure Dispatch;
  begin
    case Event.What of
      evMouseDown:
        OnPress;
      evKeyDown:
        OnKey;
      evBroadcast:
        OnBroadcast;
    end;
  end;

begin
  inherited HandleEvent(Event);
  Dispatch;
end;

function TStatusLine.Hint(AHelpCtx: Word): string;
begin
  Result := '';
end;

procedure TStatusLine.Update;
var
  Top: TView;
  Wanted: Word;
begin
  Top := TopView;
  Wanted := hcNoContext;
  if Top <> nil then
    Wanted := Top.GetHelpCtx;
  if HelpCtx = Wanted then
    Exit;
  HelpCtx := Wanted;
  FindItems;
  DrawView;
end;

initialization
  TMenuBox.FrameChars := ' '#$DA#$C4#$BF'  '#$C0#$C4#$D9'  '#$B3' '#$B3'  '#$C3#$C4#$B4' ';
  TStatusLine.HintSeparator := #$B3' ';
  MenuViewPalette := TPalette.Create(CpMenuView, Length(CpMenuView));
  StatusLinePalette := TPalette.Create(CpStatusLine, Length(CpStatusLine));

finalization
  MenuViewPalette.Free;
  StatusLinePalette.Free;

end.
