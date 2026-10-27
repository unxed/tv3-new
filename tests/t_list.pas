{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/views.h (TListViewer), include/tvision/dialogs.h (TListBox, TListBoxRec),
  include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h, source/tvision/tlstview.cpp,
  source/tvision/tlistbox.cpp, source/tvision/tvtext1.cpp (specialChars)
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it and
  reads its events from a script. The colors of the root are the BIOS attributes $41 and above: the entry k of its
  palette is $40 + k, so the entries 26 to 29 of the palette of a list viewer give the attributes $5A (normal),
  $5B (focused), $5C (selected) and $5D (divider). The hook of the messages delivers a message to its receiver as an
  event, and counts and remembers the messages that a list viewer sends when an item is selected. The text of an
  item of the test list viewer is a prefix and the number of the item. }
program t_list;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  SysUtils, TvGeom, TvKeys, TvEvents, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvViews, TvWindow, TvUtil,
  TvList;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 20;
  { A loop of events that asks for more events than a script holds ends the program after this many calls. }
  CallLimit = 20000;

type
  TFakeDisplay = class(TScreenBackend)
  public
    CaretSize: Word;
    procedure SetCaretSize(ASize: Word); override;
    function GetCaretSize: Word; override;
  end;

  { The root of the views: gives the events of a script, and then no event. }
  TRoot = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    function GetPalette: TPalette; override;
  end;

  { A list viewer with the items 'Prefix0', 'Prefix1' and so on, that remembers how it was asked. }
  TTestList = class(TListViewer)
  public
    Prefix: string;
    HasExtra: Boolean;
    Extra: Integer;
    TextCalls: Integer;
    LastMaxLen: SmallInt;
    SelectCalls: Integer;
    SelectedLast: SmallInt;
    function GetText(ItemIndex, MaxLen: SmallInt): string; override;
    function IsSelected(ItemIndex: SmallInt): Boolean; override;
    procedure SelectItem(ItemIndex: SmallInt); override;
  end;

  { A selectable view that draws nothing. }
  TSel = class(TView)
  public
    procedure Draw; override;
  end;

  { A collection that counts how many of its kind are destroyed. }
  TWatched = class(TCollection)
  public
    destructor Destroy; override;
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  RootPal: TPalette;
  GetCalls: Integer;
  SelectCount: Integer;
  LastSelectInfo: Pointer;
  LastSelectReceiver: TView;
  WatchedDestroyed: Integer;
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

function OnMessage(Receiver: TView; What, Command: Word; InfoPtr: Pointer): Pointer;
var
  Ev: TEvent;
begin
  Result := nil;
  if (What = evBroadcast) and (Command = cmListItemSelected) then
  begin
    Inc(SelectCount);
    LastSelectInfo := InfoPtr;
    LastSelectReceiver := Receiver;
  end;
  if Receiver = nil then
    Exit;
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.What := What;
  Ev.Message.Command := Command;
  Ev.Message.InfoPtr := InfoPtr;
  Receiver.HandleEvent(Ev);
  if Ev.What = evNothing then
    Result := Ev.Message.InfoPtr;
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

function MouseEv(What: Word; X, Y: Integer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := What;
  Result.Mouse.Where := Pt(X, Y);
  Result.Mouse.Buttons := mbLeftButton;
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

function Visible(V: TView): Boolean;
begin
  Result := (V.State and sfVisible) <> 0;
end;

procedure ResetMessages;
begin
  SelectCount := 0;
  LastSelectInfo := nil;
  LastSelectReceiver := nil;
end;

{ The views of the tests. }

function TTestList.GetText(ItemIndex, MaxLen: SmallInt): string;
begin
  TextCalls := TextCalls + 1;
  LastMaxLen := MaxLen;
  Result := Copy(Prefix + IntToStr(ItemIndex), 1, MaxLen);
end;

function TTestList.IsSelected(ItemIndex: SmallInt): Boolean;
begin
  Result := (ItemIndex = Focused) or (HasExtra and (ItemIndex = Extra));
end;

procedure TTestList.SelectItem(ItemIndex: SmallInt);
begin
  Inc(SelectCalls);
  SelectedLast := ItemIndex;
  inherited SelectItem(ItemIndex);
end;

procedure TSel.Draw;
begin
end;

destructor TWatched.Destroy;
begin
  Inc(WatchedDestroyed);
  inherited Destroy;
end;

procedure TRoot.AddEvent(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TRoot.GetEvent(var Event: TEvent);
begin
  Inc(GetCalls);
  if GetCalls > CallLimit then
  begin
    WriteLn('FAIL a loop of events does not end');
    Halt(1);
  end;
  FillChar(Event, SizeOf(Event), 0);
  if ScriptPos < Length(Script) then
  begin
    Event := Script[ScriptPos];
    Inc(ScriptPos);
  end;
end;

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
end;

function NewRoot: TRoot;
begin
  ClearScreen;
  GetCalls := 0;
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

{ Makes V selected and active. }
procedure MakeLive(V: TView);
begin
  V.State := V.State or sfSelected;
  V.SetState(sfActive, True);
end;

{ A root with two scroll bars and a list viewer of 10 by 5 cells at 0, 0 that has Count items, that is selected and
  active. }
procedure ListScene(out Root: TRoot; out HB, VB: TScrollBar; out L: TTestList; Count: SmallInt);
begin
  Root := NewRoot;
  HB := TScrollBar.Create(Rc(0, 5, 10, 6));
  VB := TScrollBar.Create(Rc(10, 0, 11, 5));
  L := TTestList.Create(Rc(0, 0, 10, 5), 1, HB, VB);
  L.Prefix := 'Item ';
  Root.Insert(HB);
  Root.Insert(VB);
  Root.Insert(L);
  L.SetRange(Count);
  MakeLive(L);
  ResetMessages;
end;

{ A root with a list viewer of 12 by 4 cells in two columns, without scroll bars, that has Count items. }
procedure ColumnScene(out Root: TRoot; out L: TTestList; Count: SmallInt);
begin
  Root := NewRoot;
  L := TTestList.Create(Rc(0, 0, 12, 4), 2, nil, nil);
  L.Prefix := 'n';
  Root.Insert(L);
  L.SetRange(Count);
  MakeLive(L);
  ResetMessages;
end;

{ Gives the key Code to L; tells whether L took the event. }
function Press(L: TTestList; Code: Word): Boolean;
var
  Ev: TEvent;
begin
  Ev := KeyEv(Code);
  L.HandleEvent(Ev);
  Result := Ev.What = evNothing;
end;

function MakeItems(const Names: array of string): TWatched;
var
  K: Integer;
begin
  Result := TWatched.Create(8, 8);
  for K := 0 to High(Names) do
    Result.Insert(NewStr(Names[K]));
end;

procedure TestPalette;
var
  V: TListViewer;
  Pal: TPalette;
begin
  V := TListViewer.Create(Rc(0, 0, 10, 5), 1, nil, nil);
  Pal := V.GetPalette;
  Check(PalByte(Pal, 0) = 5, 'the palette of a list viewer has five entries');
  Check((PalByte(Pal, 1) = 26) and (PalByte(Pal, 2) = 26), 'the active and the inactive entries are 26');
  Check(PalByte(Pal, 3) = 27, 'the focused entry is 27');
  Check(PalByte(Pal, 4) = 28, 'the selected entry is 28');
  Check(PalByte(Pal, 5) = 29, 'the divider entry is 29');
  Check(V.GetText(3, 255) = '', 'the base list viewer has no text');
  Check(V.IsSelected(0) and not V.IsSelected(1), 'the base list viewer selects the focused item');
  TvObject.DestroyObject(V);
end;

procedure TestConstruction;
var
  HB, VB, HB2, VB2: TScrollBar;
  L, L2: TListViewer;
begin
  HB := TScrollBar.Create(Rc(0, 5, 10, 6));
  VB := TScrollBar.Create(Rc(10, 0, 11, 5));
  L := TListViewer.Create(Rc(0, 0, 10, 5), 1, HB, VB);
  Check((L.NumCols = 1) and (L.TopItem = 0) and (L.Focused = 0) and (L.Range = 0), 'the fields of a new list viewer');
  Check((L.Options and ofFirstClick) <> 0, 'a list viewer takes the first click');
  Check((L.Options and ofSelectable) <> 0, 'a list viewer can be selected');
  Check((L.EventMask and evBroadcast) <> 0, 'a list viewer takes broadcasts');
  Check((L.HScrollBar = HB) and (L.VScrollBar = VB), 'the list viewer keeps its scroll bars');
  Check((VB.PgStep = 4) and (VB.ArStep = 1), 'the steps of the vertical bar of one column');
  Check((HB.PgStep = 10) and (HB.ArStep = 1), 'the steps of the horizontal bar of one column');

  HB2 := TScrollBar.Create(Rc(0, 4, 12, 5));
  VB2 := TScrollBar.Create(Rc(12, 0, 13, 4));
  L2 := TListViewer.Create(Rc(0, 0, 12, 4), 3, HB2, VB2);
  Check((VB2.PgStep = 12) and (VB2.ArStep = 4), 'the steps of the vertical bar of three columns');
  Check((HB2.PgStep = 4) and (HB2.ArStep = 1), 'the steps of the horizontal bar of three columns');

  L.ShutDown;
  Check((L.HScrollBar = nil) and (L.VScrollBar = nil), 'ShutDown lets go of the scroll bars');
  TvObject.DestroyObject(L);
  TvObject.DestroyObject(L2);
  TvObject.DestroyObject(HB);
  TvObject.DestroyObject(VB);
  TvObject.DestroyObject(HB2);
  TvObject.DestroyObject(VB2);
end;

procedure TestSetRange;
var
  Root: TRoot;
  HB, VB: TScrollBar;
  L: TTestList;
  Bare: TListViewer;
begin
  ListScene(Root, HB, VB, L, 20);
  Check(L.Range = 20, 'SetRange keeps the range');
  Check((VB.MinVal = 0) and (VB.MaxVal = 19) and (VB.Value = 0), 'SetRange sets the range of the bar');
  Check((VB.PgStep = 4) and (VB.ArStep = 1), 'SetRange keeps the steps of the bar');

  L.FocusItem(15);
  Check(VB.Value = 15, 'FocusItem moves the bar');
  L.SetRange(10);
  Check((L.Range = 10) and (L.Focused = 0), 'a range that does not hold the focus brings it back to the first item');
  Check((VB.MaxVal = 9) and (VB.Value = 0), 'the bar follows the shorter range');

  L.SetRange(0);
  Check((L.Range = 0) and (L.Focused = 0), 'an empty range');
  Check(VB.MaxVal = 0, 'the bar of an empty range ends at 0');
  FreeRoot(Root);

  Bare := TListViewer.Create(Rc(0, 0, 10, 5), 1, nil, nil);
  Bare.SetRange(3);
  Check(Bare.Range = 3, 'SetRange of a list viewer without a bar');
  TvObject.DestroyObject(Bare);
end;

procedure TestFocus;
var
  Root: TRoot;
  HB, VB: TScrollBar;
  L: TTestList;
begin
  ListScene(Root, HB, VB, L, 20);
  L.FocusItem(7);
  Check((L.Focused = 7) and (L.TopItem = 3) and (VB.Value = 7), 'FocusItem below the page scrolls the page down');
  L.FocusItem(1);
  Check((L.Focused = 1) and (L.TopItem = 1) and (VB.Value = 1), 'FocusItem above the page scrolls the page up');
  L.FocusItem(4);
  Check((L.Focused = 4) and (L.TopItem = 1), 'FocusItem inside the page keeps the page');
  L.FocusItemNum(-5);
  Check((L.Focused = 0) and (L.TopItem = 0) and (VB.Value = 0), 'FocusItemNum cuts a negative item to the first');
  L.FocusItemNum(100);
  Check((L.Focused = 19) and (L.TopItem = 15) and (VB.Value = 19), 'FocusItemNum cuts a large item to the last');
  L.FocusItemNum(8);
  Check(L.Focused = 8, 'FocusItemNum focuses an item inside the range');
  L.SetRange(0);
  L.FocusItemNum(3);
  Check((L.Focused = 0) and (VB.Value = 0), 'FocusItemNum does nothing for an empty range');
  FreeRoot(Root);

  Root := NewRoot;
  L := TTestList.Create(Rc(0, 0, 10, 5), 1, nil, nil);
  Root.Insert(L);
  L.SetRange(20);
  L.FocusItem(7);
  Check((L.Focused = 7) and (L.TopItem = 3), 'FocusItem without a bar scrolls the page down');
  L.FocusItem(2);
  Check((L.Focused = 2) and (L.TopItem = 2), 'FocusItem without a bar scrolls the page up');
  FreeRoot(Root);

  ColumnScene(Root, L, 20);
  L.FocusItem(9);
  Check((L.Focused = 9) and (L.TopItem = 4), 'FocusItem below the page of two columns');
  L.FocusItem(2);
  Check((L.Focused = 2) and (L.TopItem = 0), 'FocusItem above the page of two columns');
  L.FocusItem(7);
  Check((L.Focused = 7) and (L.TopItem = 0), 'FocusItem at the end of the page of two columns');
  L.FocusItem(8);
  Check((L.Focused = 8) and (L.TopItem = 4), 'FocusItem at the first item after the page of two columns');
  L.FocusItem(3);
  Check((L.Focused = 3) and (L.TopItem = 0), 'FocusItem into the first column of an earlier page');
  FreeRoot(Root);
end;

procedure TestDraw;
var
  Root: TRoot;
  HB, VB: TScrollBar;
  L: TTestList;
begin
  ListScene(Root, HB, VB, L, 20);
  ClearScreen;
  L.TextCalls := 0;
  L.DrawView;
  Check(RowText(0, 0, 10) = ' Item 0   ', 'the first row of a list viewer');
  Check(RowText(1, 0, 10) = ' Item 1   ', 'the second row of a list viewer');
  Check(RowText(4, 0, 10) = ' Item 4   ', 'the last row of a list viewer');
  Check(L.TextCalls = 5, 'one text is asked for each row');
  Check(L.LastMaxLen = 255, 'the text is asked for with the length 255');
  Check((AttrAt(1, 0) = $5B) and (AttrAt(9, 0) = $5B), 'the focused row has the focused color');
  Check((AttrAt(1, 1) = $5A) and (AttrAt(0, 4) = $5A), 'the other rows have the normal color');
  Check(L.Cursor = Pt(1, 0), 'the cursor is at the focused item');

  L.HasExtra := True;
  L.Extra := 2;
  ClearScreen;
  L.DrawView;
  Check(AttrAt(1, 2) = $5C, 'a selected item has the selected color');
  Check((AttrAt(1, 0) = $5B) and (AttrAt(1, 1) = $5A), 'the focused row keeps its color beside a selected item');

  TView.ShowMarkers := True;
  ClearScreen;
  L.DrawView;
  Check((CharAt(0, 0) <> ' ') and (CharAt(9, 0) <> ' '), 'the focused row has marks at both ends');
  Check((CharAt(0, 1) = ' ') and (CharAt(9, 1) = ' '), 'a normal row has blank marks');
  Check((CharAt(0, 2) <> ' ') and (CharAt(9, 2) <> ' '), 'a selected row has marks at both ends');
  Check(AttrAt(0, 2) = $5C, 'a mark keeps the color of the row');
  Check(RowText(0, 1, 6) = 'Item 0', 'the marks leave the text');
  TView.ShowMarkers := False;

  ClearScreen;
  L.DrawView;
  Check((CharAt(0, 2) = ' ') and (CharAt(9, 2) = ' '), 'there are no marks while the markers are off');

  L.SetState(sfActive, False);
  ClearScreen;
  L.DrawView;
  Check(AttrAt(1, 0) = $5C, 'the focused row of an inactive list viewer has the selected color');
  Check(AttrAt(1, 1) = $5A, 'the other rows of an inactive list viewer have the normal color');
  Check(L.Cursor = Pt(-1, -1), 'an inactive list viewer has no cursor');
  FreeRoot(Root);

  ListScene(Root, HB, VB, L, 2);
  ClearScreen;
  L.DrawView;
  Check((RowText(0, 0, 10) = ' Item 0   ') and (RowText(1, 0, 10) = ' Item 1   '), 'the rows of a short list');
  Check(RowText(2, 0, 10) = StringOfChar(' ', 10), 'a row after the last item is blank');
  Check(RowText(4, 0, 10) = StringOfChar(' ', 10), 'the last row after the last item is blank');
  Check((AttrAt(5, 2) = $5A) and (AttrAt(5, 4) = $5A), 'a blank row has the normal color');
  FreeRoot(Root);

  ListScene(Root, HB, VB, L, 0);
  TListViewer.EmptyText := '<empty>';
  ClearScreen;
  L.DrawView;
  Check(RowText(0, 0, 10) = ' <empty>  ', 'an empty list shows the empty text in the first row');
  Check(AttrAt(1, 0) = $5A, 'the empty text has the normal color');
  Check(RowText(1, 0, 10) = StringOfChar(' ', 10), 'an empty list is blank below the first row');
  Check(L.Cursor = Pt(-1, -1), 'an empty list has no cursor');
  FreeRoot(Root);

  ListScene(Root, HB, VB, L, 20);
  HB.SetParams(2, 0, 10, HB.PgStep, HB.ArStep);
  ClearScreen;
  L.DrawView;
  Check(RowText(0, 0, 10) = ' em 0     ', 'the text is moved by the value of the horizontal bar');
  Check(RowText(1, 0, 10) = ' em 1     ', 'every row is moved by the value of the horizontal bar');
  FreeRoot(Root);

  ColumnScene(Root, L, 20);
  ClearScreen;
  L.DrawView;
  Check((RowText(0, 0, 6) = ' n0   ') and (RowText(0, 7, 5) = ' n4  '), 'the first row of two columns');
  Check((RowText(3, 0, 6) = ' n3   ') and (RowText(3, 7, 5) = ' n7  '), 'the last row of two columns');
  Check(CharAt(6, 0) <> ' ', 'a divider ends the first column');
  Check(AttrAt(6, 0) = $5D, 'the divider has the divider color');
  Check((AttrAt(1, 0) = $5B) and (AttrAt(8, 0) = $5A), 'the colors of the first row of two columns');
  Check(L.Cursor = Pt(1, 0), 'the cursor of two columns');
  L.FocusItem(5);
  Check(L.Cursor = Pt(8, 1), 'the cursor in the second column');
  Check((AttrAt(8, 1) = $5B) and (AttrAt(1, 0) = $5A), 'the focus moves to the second column');
  L.FocusItem(9);
  ClearScreen;
  L.DrawView;
  Check((RowText(0, 0, 6) = ' n4   ') and (RowText(0, 7, 5) = ' n8  '), 'the page of two columns starts at the top item');
  Check(L.Cursor = Pt(8, 1), 'the cursor follows the page of two columns');
  FreeRoot(Root);
  TListViewer.EmptyText := '';
end;

procedure TestKeys;
var
  Root: TRoot;
  HB, VB: TScrollBar;
  L: TTestList;
  Taken: Boolean;
begin
  ListScene(Root, HB, VB, L, 20);
  Taken := Press(L, kbDown);
  Check(Taken and (L.Focused = 1), 'the down key moves the focus down');
  Press(L, kbUp);
  Check(L.Focused = 0, 'the up key moves the focus up');
  Taken := Press(L, kbUp);
  Check(Taken and (L.Focused = 0), 'the up key at the first item keeps the focus');
  Press(L, kbPgDn);
  Check((L.Focused = 5) and (L.TopItem = 1), 'the page down key moves by a page');
  Press(L, kbPgUp);
  Check((L.Focused = 0) and (L.TopItem = 0), 'the page up key moves back by a page');
  Press(L, kbEnd);
  Check((L.Focused = 4) and (L.TopItem = 0), 'the end key goes to the last item of the page');
  Press(L, kbHome);
  Check(L.Focused = 0, 'the home key goes to the first item of the page');
  Press(L, kbPgDn);
  Press(L, kbEnd);
  Check(L.Focused = 5, 'the end key of a scrolled page');
  Press(L, kbHome);
  Check((L.Focused = 1) and (L.TopItem = 1), 'the home key of a scrolled page');
  Press(L, kbCtrlPgDn);
  Check((L.Focused = 19) and (L.TopItem = 15), 'control page down goes to the last item');
  Press(L, kbCtrlPgUp);
  Check((L.Focused = 0) and (L.TopItem = 0), 'control page up goes to the first item');

  Taken := Press(L, kbRight);
  Check(not Taken and (L.Focused = 0), 'the right key is not taken by a list of one column');
  Taken := Press(L, kbLeft);
  Check(not Taken and (L.Focused = 0), 'the left key is not taken by a list of one column');
  Taken := Press(L, kbF1);
  Check(not Taken, 'a key that the list does not know is not taken');

  Taken := Press(L, kbCtrlX);
  Check(Taken and (L.Focused = 1), 'control X acts as the down key');
  Press(L, kbCtrlE);
  Check(L.Focused = 0, 'control E acts as the up key');

  Taken := Press(L, $0020);
  Check(Taken and (L.SelectCalls = 1) and (L.SelectedLast = 0), 'the space key selects the focused item');
  Check((SelectCount = 1) and (LastSelectInfo = Pointer(L)) and (LastSelectReceiver = Root),
    'selecting an item tells the owner');
  L.FocusItem(3);
  Press(L, $0020);
  Check((L.SelectCalls = 2) and (L.SelectedLast = 3) and (L.Focused = 3), 'the space key selects another item');

  L.SetRange(0);
  Taken := Press(L, $0020);
  Check(not Taken and (L.SelectCalls = 2), 'the space key selects nothing in an empty list');
  FreeRoot(Root);

  ColumnScene(Root, L, 20);
  Press(L, kbRight);
  Check(L.Focused = 4, 'the right key moves to the next column');
  Press(L, kbRight);
  Check((L.Focused = 8) and (L.TopItem = 4), 'the right key scrolls by a column');
  Press(L, kbLeft);
  Check((L.Focused = 4) and (L.TopItem = 4), 'the left key moves to the column before');
  Press(L, kbPgDn);
  Check((L.Focused = 12) and (L.TopItem = 8), 'the page down key moves by all columns');
  Press(L, kbPgUp);
  Check((L.Focused = 4) and (L.TopItem = 4), 'the page up key moves back by all columns');
  Press(L, kbEnd);
  Check((L.Focused = 11) and (L.TopItem = 4), 'the end key goes to the last item of the columns');
  Press(L, kbHome);
  Check(L.Focused = 4, 'the home key goes to the first item of the columns');
  Press(L, kbLeft);
  Check((L.Focused = 0) and (L.TopItem = 0), 'the left key goes back to the first column');
  Press(L, kbLeft);
  Check(L.Focused = 0, 'the left key in the first column keeps the focus');
  FreeRoot(Root);
end;

procedure TestMouse;
var
  Root: TRoot;
  HB, VB: TScrollBar;
  L: TTestList;
  Ev: TEvent;
  K: Integer;
begin
  ListScene(Root, HB, VB, L, 20);
  Root.AddEvent(MouseEv(evMouseUp, 4, 3));
  Ev := MouseEv(evMouseDown, 4, 3);
  L.HandleEvent(Ev);
  Check(L.Focused = 3, 'a click focuses the item under the mouse');
  Check(Ev.What = evNothing, 'a click is taken');
  Check(L.SelectCalls = 0, 'a single click selects nothing');

  Root.ScriptPos := 0;
  SetLength(Root.Script, 0);
  Root.AddEvent(MouseEv(evMouseMove, 3, 4));
  Root.AddEvent(MouseEv(evMouseUp, 3, 4));
  Ev := MouseEv(evMouseDown, 1, 0);
  L.HandleEvent(Ev);
  Check(L.Focused = 4, 'the focus follows the mouse while the button is down');
  Check(Root.ScriptPos = 2, 'the loop reads the events up to the release');

  Root.ScriptPos := 0;
  SetLength(Root.Script, 0);
  Root.AddEvent(MouseEv(evMouseUp, 2, 1));
  Ev := MouseEv(evMouseDown, 2, 1);
  Ev.Mouse.EventFlags := meDoubleClick;
  L.HandleEvent(Ev);
  Check(L.Focused = 1, 'a double click focuses the item');
  Check((L.SelectCalls = 1) and (L.SelectedLast = 1), 'a double click selects the item');
  Check(Root.ScriptPos = 0, 'a double click reads no more events');
  Check(Ev.What = evNothing, 'a double click is taken');

  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  for K := 1 to 4 do
    Root.AddEvent(MouseEv(evMouseAuto, 2, -1));
  Root.AddEvent(MouseEv(evMouseUp, 2, -1));
  Ev := MouseEv(evMouseDown, 2, 2);
  L.HandleEvent(Ev);
  Check(L.Focused = 1, 'four automatic events above the view move the focus up by one');
  Check(Root.ScriptPos = 5, 'the loop reads the automatic events and the release');

  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  for K := 1 to 3 do
    Root.AddEvent(MouseEv(evMouseAuto, 2, 7));
  Root.AddEvent(MouseEv(evMouseUp, 2, 7));
  Ev := MouseEv(evMouseDown, 2, 1);
  L.HandleEvent(Ev);
  Check(L.Focused = 1, 'three automatic events below the view do not move the focus');

  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  for K := 1 to 4 do
    Root.AddEvent(MouseEv(evMouseAuto, 2, 7));
  Root.AddEvent(MouseEv(evMouseUp, 2, 7));
  Ev := MouseEv(evMouseDown, 2, 1);
  L.HandleEvent(Ev);
  Check(L.Focused = 2, 'four automatic events below the view move the focus down by one');
  FreeRoot(Root);

  ListScene(Root, HB, VB, L, 3);
  Root.AddEvent(MouseEv(evMouseUp, 1, 4));
  Ev := MouseEv(evMouseDown, 1, 4);
  L.HandleEvent(Ev);
  Check(L.Focused = 2, 'a click below the last item focuses the last item');
  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  Ev := MouseEv(evMouseDown, 1, 4);
  Ev.Mouse.EventFlags := meDoubleClick;
  L.HandleEvent(Ev);
  Check(L.SelectCalls = 0, 'a double click below the last item selects nothing');
  FreeRoot(Root);

  ColumnScene(Root, L, 20);
  Root.AddEvent(MouseEv(evMouseUp, 8, 2));
  Ev := MouseEv(evMouseDown, 8, 2);
  L.HandleEvent(Ev);
  Check(L.Focused = 6, 'a click in the second column');

  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  for K := 1 to 4 do
    Root.AddEvent(MouseEv(evMouseAuto, -3, 1));
  Root.AddEvent(MouseEv(evMouseUp, -3, 1));
  Ev := MouseEv(evMouseDown, 8, 2);
  L.HandleEvent(Ev);
  Check(L.Focused = 2, 'automatic events to the left move the focus by a column back');

  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  for K := 1 to 4 do
    Root.AddEvent(MouseEv(evMouseAuto, 20, 1));
  Root.AddEvent(MouseEv(evMouseUp, 20, 1));
  Ev := MouseEv(evMouseDown, 2, 0);
  L.HandleEvent(Ev);
  Check(L.Focused = 4, 'automatic events to the right move the focus by a column forward');

  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  Root.AddEvent(MouseEv(evMouseUp, 8, 2));
  Ev := MouseEv(evMouseDown, 8, 2);
  L.HandleEvent(Ev);
  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  for K := 1 to 4 do
    Root.AddEvent(MouseEv(evMouseAuto, 3, -2));
  Root.AddEvent(MouseEv(evMouseUp, 3, -2));
  Ev := MouseEv(evMouseDown, 8, 2);
  L.HandleEvent(Ev);
  Check(L.Focused = 4, 'automatic events above move the focus to the top of the column');

  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  for K := 1 to 4 do
    Root.AddEvent(MouseEv(evMouseAuto, 3, 9));
  Root.AddEvent(MouseEv(evMouseUp, 3, 9));
  Ev := MouseEv(evMouseDown, 8, 2);
  L.HandleEvent(Ev);
  Check(L.Focused = 7, 'automatic events far below move the focus to the bottom of the column');
  FreeRoot(Root);
end;

procedure TestBroadcast;
var
  Root: TRoot;
  HB, VB: TScrollBar;
  L: TTestList;
  S: TSel;
  Ev: TEvent;
begin
  ListScene(Root, HB, VB, L, 20);
  VB.Value := 9;
  Ev := BroadcastEv(cmScrollBarChanged, VB);
  L.HandleEvent(Ev);
  Check((L.Focused = 9) and (L.TopItem = 5), 'a change of the vertical bar focuses the item of its value');
  Check(Ev.What = evBroadcast, 'a change of the bar is not taken');

  HB.Value := 3;
  Ev := BroadcastEv(cmScrollBarChanged, HB);
  L.HandleEvent(Ev);
  Check(L.Focused = 9, 'a change of the horizontal bar keeps the focus');

  VB.Value := 15;
  Ev := BroadcastEv(cmScrollBarChanged, @Dummy);
  L.HandleEvent(Ev);
  Check(L.Focused = 9, 'a change of another view is not taken');

  Ev := BroadcastEv(cmListItemSelected, VB);
  L.HandleEvent(Ev);
  Check(L.Focused = 9, 'another broadcast is not taken');

  S := TSel.Create(Rc(20, 0, 30, 5));
  S.Options := S.Options or ofSelectable;
  Root.Insert(S);
  Root.SetCurrent(S, normalSelect);
  Check(Root.Current = S, 'the other view is the current view');
  Ev := BroadcastEv(cmScrollBarClicked, @Dummy);
  L.HandleEvent(Ev);
  Check(Root.Current = S, 'a click on another view does not select the list viewer');
  Ev := BroadcastEv(cmScrollBarClicked, VB);
  L.HandleEvent(Ev);
  Check(Root.Current = L, 'a click on its vertical bar selects the list viewer');
  Root.SetCurrent(S, normalSelect);
  Ev := BroadcastEv(cmScrollBarClicked, HB);
  L.HandleEvent(Ev);
  Check(Root.Current = L, 'a click on its horizontal bar selects the list viewer');

  L.Options := L.Options and not ofSelectable;
  Root.SetCurrent(S, normalSelect);
  Ev := BroadcastEv(cmScrollBarClicked, VB);
  L.HandleEvent(Ev);
  Check(Root.Current = S, 'a list viewer that cannot be selected takes no broadcast');
  FreeRoot(Root);
end;

procedure TestState;
var
  Root: TRoot;
  HB, VB: TScrollBar;
  L: TTestList;
begin
  ListScene(Root, HB, VB, L, 20);
  Check(Visible(HB) and Visible(VB), 'the bars of an active list viewer are shown');
  L.SetState(sfActive, False);
  Check(not Visible(HB) and not Visible(VB), 'the bars of an inactive list viewer are hidden');
  L.SetState(sfActive, True);
  Check(Visible(HB) and Visible(VB), 'the bars are shown when the list viewer becomes active');
  L.SetState(sfSelected, False);
  Check(Visible(HB) and Visible(VB), 'the bars stay shown while the list viewer is active');

  VB.Hide;
  L.SetState(sfDisabled, True);
  Check(not Visible(VB), 'a state that does not matter leaves the bars as they are');
  L.SetState(sfDisabled, False);

  L.SetState(sfActive, True);
  Check(Visible(VB), 'a state that matters shows the bar again');
  L.Hide;
  Check(not Visible(HB) and not Visible(VB), 'the bars of a hidden list viewer are hidden');
  L.Show;
  Check(Visible(HB) and Visible(VB), 'the bars of a shown active list viewer are shown');
  FreeRoot(Root);
end;

procedure TestChangeBounds;
var
  Root: TRoot;
  HB, VB, HB2, VB2: TScrollBar;
  L: TTestList;
  L2: TListViewer;
begin
  ListScene(Root, HB, VB, L, 20);
  HB.SetStep(HB.PgStep, 3);
  L.ChangeBounds(Rc(0, 0, 20, 8));
  Check(L.Size = Pt(20, 8), 'ChangeBounds sets the size');
  Check((HB.PgStep = 20) and (HB.ArStep = 3), 'ChangeBounds sets the page of the horizontal bar and keeps its arrow');
  Check((VB.PgStep = 8) and (VB.ArStep = 1), 'ChangeBounds sets the page of the vertical bar and keeps its arrow');
  FreeRoot(Root);

  HB2 := TScrollBar.Create(Rc(0, 4, 12, 5));
  VB2 := TScrollBar.Create(Rc(12, 0, 13, 4));
  L2 := TListViewer.Create(Rc(0, 0, 12, 4), 2, HB2, VB2);
  L2.ChangeBounds(Rc(0, 0, 16, 6));
  Check(HB2.PgStep = 8, 'the page of the horizontal bar is the width of a column');
  Check(VB2.PgStep = 6, 'the page of the vertical bar is the height');
  TvObject.DestroyObject(L2);
  TvObject.DestroyObject(HB2);
  TvObject.DestroyObject(VB2);
end;

procedure TestSelectWithoutHook;
var
  V: TListViewer;
  Before: Integer;
  Saved: TMessageFunc;
begin
  V := TListViewer.Create(Rc(0, 0, 10, 5), 1, nil, nil);
  ResetMessages;
  V.SelectItem(3);
  Check((SelectCount = 1) and (LastSelectInfo = Pointer(V)) and (LastSelectReceiver = nil),
    'SelectItem sends the message to the owner, which is none');
  Saved := MessageHook;
  MessageHook := nil;
  Before := SelectCount;
  V.SelectItem(3);
  Check(SelectCount = Before, 'SelectItem does nothing while there is no hook of messages');
  MessageHook := Saved;
  TvObject.DestroyObject(V);
end;

procedure TestListBox;
var
  Root: TRoot;
  VB: TScrollBar;
  LB: TListBox;
  C1, C2, C3, C4: TWatched;
  Rec, Back: TListBoxRec;
begin
  WatchedDestroyed := 0;
  Root := NewRoot;
  VB := TScrollBar.Create(Rc(10, 0, 11, 5));
  LB := TListBox.Create(Rc(0, 0, 10, 5), 1, VB);
  Root.Insert(VB);
  Root.Insert(LB);
  MakeLive(LB);

  Check(LB.List = nil, 'a new list box has no list');
  Check((LB.Range = 0) and (LB.Focused = 0) and (LB.NumCols = 1), 'the fields of a new list box');
  Check((LB.HScrollBar = nil) and (LB.VScrollBar = VB), 'a list box has a vertical bar only');
  Check(LB.GetText(0, 255) = '', 'a list box without a list has no text');
  Check(LB.DataSize = SizeOf(TListBoxRec), 'the size of the data of a list box');
  Check((LB.Options and ofSelectable) <> 0, 'a list box can be selected');

  C1 := MakeItems(['Alpha', 'Beta', 'Gamma']);
  LB.NewList(C1);
  Check(LB.List = C1, 'NewList keeps the list');
  Check((LB.Range = 3) and (LB.Focused = 0), 'NewList sets the range and focuses the first item');
  Check((VB.MinVal = 0) and (VB.MaxVal = 2), 'NewList sets the range of the bar');
  Check((LB.GetText(0, 255) = 'Alpha') and (LB.GetText(1, 255) = 'Beta') and (LB.GetText(2, 255) = 'Gamma'),
    'the text of an item is the string of the list');
  Check(LB.GetText(0, 3) = 'Alp', 'the text is cut to the given length');
  Check(LB.GetText(2, 0) = '', 'a length of 0 gives no text');
  Check(LB.GetText(1, 100) = 'Beta', 'a longer length gives the whole string');

  ClearScreen;
  LB.DrawView;
  Check((RowText(0, 0, 6) = ' Alpha') and (RowText(1, 0, 5) = ' Beta') and (RowText(2, 0, 6) = ' Gamma'),
    'the rows of a list box show the strings');
  Check(RowText(3, 0, 10) = StringOfChar(' ', 10), 'the rows after the last string are blank');
  Check((AttrAt(2, 0) = $5B) and (AttrAt(2, 1) = $5A), 'the focused string of a list box has the focused color');

  LB.FocusItem(2);
  LB.GetData(@Back);
  Check((Back.Items = C1) and (Back.Selection = 2), 'GetData gives the list and the focused item');

  C2 := MakeItems(['One', 'Two']);
  LB.NewList(C2);
  Check(WatchedDestroyed = 1, 'NewList destroys the list that it replaces');
  Check((LB.List = C2) and (LB.Range = 2) and (LB.Focused = 0), 'NewList of a shorter list focuses the first item');

  C3 := MakeItems(['a', 'b', 'c', 'd']);
  Rec.Items := C3;
  Rec.Selection := 3;
  LB.SetData(@Rec);
  Check(WatchedDestroyed = 2, 'SetData destroys the list that it replaces');
  Check((LB.List = C3) and (LB.Range = 4) and (LB.Focused = 3), 'SetData gives the list and focuses the item');
  LB.GetData(@Back);
  Check((Back.Items = C3) and (Back.Selection = 3), 'GetData gives back what SetData took');

  LB.NewList(nil);
  Check(WatchedDestroyed = 3, 'NewList of no list destroys the list');
  Check((LB.List = nil) and (LB.Range = 0) and (LB.Focused = 0), 'NewList of no list empties the list box');
  Check(LB.GetText(0, 255) = '', 'an emptied list box has no text');

  C4 := MakeItems(['last']);
  LB.NewList(C4);
  FreeRoot(Root);
  Check(WatchedDestroyed = 3, 'destroying a list box does not destroy its list');
  TvObject.DestroyObject(C4);
  Check(WatchedDestroyed = 4, 'the list is destroyed by its owner');
end;

var
  SavedBackend: TScreenBackend;

begin
  RootPal := TPalette.Create(#$41#$42#$43#$44#$45#$46#$47#$48#$49#$4A#$4B#$4C#$4D#$4E#$4F#$50 +
    #$51#$52#$53#$54#$55#$56#$57#$58#$59#$5A#$5B#$5C#$5D#$5E#$5F#$60, 32);
  Check(Length(cpListViewer) = 5, 'the palette string of a list viewer has five entries');
  Check((Ord(cpListViewer[1]) = $1A) and (Ord(cpListViewer[2]) = $1A) and (Ord(cpListViewer[3]) = $1B) and
    (Ord(cpListViewer[4]) = $1C) and (Ord(cpListViewer[5]) = $1D), 'the values of the palette of a list viewer');
  Check(TListViewer.EmptyText = '', 'the empty text starts empty');
  Check(not TView.ShowMarkers, 'the markers start off');

  Fake := TFakeDisplay.Create;
  SavedBackend := TDisplay.Backend;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;
  MessageHook := @OnMessage;

  TestPalette;
  TestConstruction;
  TestSetRange;
  TestFocus;
  TestDraw;
  TestKeys;
  TestMouse;
  TestBroadcast;
  TestState;
  TestChangeBounds;
  TestSelectWithoutHook;
  TestListBox;

  MessageHook := nil;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
