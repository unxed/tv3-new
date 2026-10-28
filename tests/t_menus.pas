{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/menus.h, include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h,
  include/tvision/views.h, source/tvision/menu.cpp, source/tvision/popupmnu.cpp, source/tvision/tmenubar.cpp,
  source/tvision/tmenubox.cpp, source/tvision/tmenupop.cpp, source/tvision/tmnuview.cpp,
  source/tvision/tstatusl.cpp
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it. The
  root reads its events from a script, or from the posted events of the event queue when the script asks for it,
  and it remembers the events that the views put back into it. The palette of the root has seven entries, so that
  each color of the menu palette gives a distinct attribute: the normal text $22, the disabled text $33, the
  shortcut text $44, the selection $55, the disabled selection $66 and the shortcut selection $77. The hooks for
  the shortcut of a menu item and for the application are test doubles; the comparison of texts is the one of
  TvLocale. }
program t_menus;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Classes, SysUtils, TvGeom, TvKeys, TvEvents, TvSys, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvViews,
  TvMenus;

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

  { The root of the views. }
  TRoot = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    UseQueue: Boolean;
    CancelWhenDry: Boolean;
    Deadline: Int64;
    PutCount: Integer;
    LastPut: TEvent;
    TopLog: string;
    TopOrigin: TPoint;
    TopSize: TPoint;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    procedure PutEvent(var Event: TEvent); override;
    function GetPalette: TPalette; override;
  end;

  { Gives access to the members of a menu view that are protected. }
  TCrack = class(TMenuView)
  public
    property CurrentItem: TMenuItem read Current write Current;
    property ParentView: TMenuView read ParentMenu write ParentMenu;
    property MenuObj: TMenu read Menu write Menu;
    property PutClick: Boolean read PutClickEventOnExit write PutClickEventOnExit;
  end;

  TStatusCrack = class(TStatusLine)
  public
    property ItemList: TStatusItem read Items;
    property DefList: TStatusDef read Defs;
  end;

  TCountBar = class(TMenuBar)
  public
    DrawCount: Integer;
    procedure Draw; override;
  end;

  TCountItem = class(TMenuItem)
  public
    destructor Destroy; override;
  end;

  TCountStatusItem = class(TStatusItem)
  public
    destructor Destroy; override;
  end;

  TCountStatus = class(TStatusLine)
  public
    DrawCount: Integer;
    HintText: string;
    procedure Draw; override;
    function Hint(AHelpCtx: Word): string; override;
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
  RootPal: TPalette;
  GetCalls: Integer;
  WakeFlag: LongInt;
  ItemFreed: Integer;
  StatusItemFreed: Integer;
  CurApp: TGroup;
  { The graph of the menu that most tests use. }
  FileSub, EditSub: TSubMenu;
  NewItem, OpenItem, ExitItem, CutItem, CopyItem, SepItem: TMenuItem;

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

{ The shortcut of a name is the text between the first pair of tildes. }
function TestHotKeyStr(const Name: string): string;
var
  A, B: Integer;
begin
  Result := '';
  A := Pos('~', Name);
  if A = 0 then
    Exit;
  B := Pos('~', Copy(Name, A + 1, Length(Name)));
  if B > 1 then
    Result := Copy(Name, A + 1, B - 1);
end;

function TestApp: TGroup;
begin
  Result := CurApp;
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

function RectIs(const R: TRect; AX, AY, BX, BY: Integer): Boolean;
begin
  Result := (R.A.X = AX) and (R.A.Y = AY) and (R.B.X = BX) and (R.B.Y = BY);
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

function BroadcastEv(Cmd: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evBroadcast;
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

{ The text of a name, for a message. }
function NameOf(P: PAnsiChar): string;
begin
  if P = nil then
    Result := '<nil>'
  else
    Result := P;
end;

{ The views of the tests. }

procedure TCountBar.Draw;
begin
  Inc(DrawCount);
  inherited Draw;
end;

destructor TCountItem.Destroy;
begin
  Inc(ItemFreed);
  inherited Destroy;
end;

destructor TCountStatusItem.Destroy;
begin
  Inc(StatusItemFreed);
  inherited Destroy;
end;

procedure TCountStatus.Draw;
begin
  Inc(DrawCount);
  inherited Draw;
end;

function TCountStatus.Hint(AHelpCtx: Word): string;
begin
  Result := HintText;
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
  if TheTopView <> nil then
  begin
    TopLog := TopLog + TheTopView.ClassName + ' ';
    TopOrigin := TheTopView.Origin;
    TopSize := TheTopView.Size;
  end;
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

function NewRoot: TRoot;
begin
  ClearScreen;
  Result := TRoot.Create(Rc(0, 0, ScrW, ScrH));
  Result.Options := Result.Options and not ofBuffered;
  Result.Buffer := @ScreenCells[0];
  Result.State := Result.State or sfSelected;
  Result.SetState(sfExposed, True);
  Result.CancelWhenDry := True;
  CurApp := Result;
end;

procedure FreeRoot(R: TRoot);
begin
  CurApp := nil;
  TvObject.DestroyObject(R);
end;

{ Builds the menu File (New, Open, a line, Exit) and Edit (Cut, Copy) and returns the head of the chain. }
function MakeBarMenu: TSubMenu;
begin
  FileSub := TSubMenu.Create('~F~ile', TKey.Create(kbAltF), 11);
  NewItem := TMenuItem.Create('~N~ew', cmNew, TKey.Create(kbF4), 22, 'F4');
  OpenItem := TMenuItem.Create('~O~pen', cmOpen, TKey.Create(kbF3));
  SepItem := NewLine;
  ExitItem := TMenuItem.Create('E~x~it', cmQuit, TKey.Create(kbAltX));
  FileSub := FileSub + NewItem + OpenItem + SepItem + ExitItem;
  EditSub := TSubMenu.Create('~E~dit', TKey.Create(kbNoKey));
  CutItem := TMenuItem.Create('Cu~t~', cmCut, TKey.Create(kbNoKey));
  CopyItem := TMenuItem.Create('~C~opy', cmCopy, TKey.Create(kbNoKey));
  EditSub := EditSub + CutItem + CopyItem;
  Result := FileSub + EditSub;
end;

function NewBar: TCountBar;
begin
  Result := TCountBar.Create(Rc(0, 0, ScrW, 1), MakeBarMenu);
end;

{ ---- the tests ---- }

procedure TestItems;
var
  L, I, S, A, B, C: TMenuItem;
  Sub: TSubMenu;
  M: TMenu;
begin
  L := NewLine;
  Check(L.Name = nil, 'NewLine has no name');
  Check(L.Command = 0, 'NewLine has the command 0');
  Check(L.Next = nil, 'NewLine has no next item');
  Check(L.HelpCtx = hcNoContext, 'NewLine has no help context');
  Check(L.Param = nil, 'NewLine has no parameter');
  Check(not L.Disabled, 'NewLine is enabled while the command 0 is enabled');
  Check(L.KeyCode = TKey.Create(kbNoKey), 'NewLine has no key');
  L.Free;

  I := TMenuItem.Create('Open', cmOpen, TKey.Create(kbF3), 7, 'F3');
  Check(NameOf(I.Name) = 'Open', 'the item keeps its name');
  Check(I.Command = cmOpen, 'the item keeps its command');
  Check(I.KeyCode = TKey.Create(kbF3), 'the item keeps its key');
  Check(I.HelpCtx = 7, 'the item keeps its help context');
  Check(NameOf(I.Param) = 'F3', 'the item keeps its parameter');
  Check(I.Next = nil, 'the item has no next item by default');
  Check(not I.Disabled, 'an item of an enabled command is enabled');
  I.Free;

  TView.DisableCommand(cmCut);
  I := TMenuItem.Create('Cut', cmCut, TKey.Create(kbNoKey));
  Check(I.Disabled, 'an item of a disabled command is disabled');
  TView.EnableCommand(cmCut);
  I.Free;

  I := TMenuItem.Create('A', cmNew, TKey.Create(kbNoKey));
  Check(I.Param = nil, 'an empty parameter is no parameter');
  I.Free;

  A := TMenuItem.Create('A', cmNew, TKey.Create(kbNoKey));
  B := TMenuItem.Create('B', cmOpen, TKey.Create(kbNoKey), 0, '', A);
  Check(B.Next = A, 'the next item is the last argument of the constructor');
  B.Append(nil);
  Check(B.Next = nil, 'Append sets the next item');
  B.Append(A);
  Check(B.Next = A, 'Append sets the next item to the item given');
  B.Append(nil);
  A.Free;
  B.Free;

  S := TMenuItem.Create('Sub', TKey.Create(kbF2), TMenu.Create, 3);
  Check(S.Command = 0, 'an item with a sub menu has the command 0');
  Check(S.SubMenu <> nil, 'an item with a sub menu holds it');
  Check(S.HelpCtx = 3, 'an item with a sub menu keeps its help context');
  Check(S.KeyCode = TKey.Create(kbF2), 'an item with a sub menu keeps its key');
  Check(S.Next = nil, 'an item with a sub menu has no next item by default');
  S.Free;

  Sub := TSubMenu.Create('~S~ub', TKey.Create(kbAltS), 4);
  Check(NameOf(Sub.Name) = '~S~ub', 'a sub menu keeps its name');
  Check(Sub.Command = 0, 'a sub menu has the command 0');
  Check((Sub.SubMenu <> nil) and (Sub.SubMenu.Items = nil) and (Sub.SubMenu.Deflt = nil), 'a sub menu starts empty');
  Check(Sub.HelpCtx = 4, 'a sub menu keeps its help context');
  Check(Sub.KeyCode = TKey.Create(kbAltS), 'a sub menu keeps its key');
  Sub.Free;
  Sub := TSubMenu.Create('x', TKey.Create(kbNoKey));
  Check(Sub.HelpCtx = hcNoContext, 'the help context of a sub menu is none by default');
  Sub.Free;

  M := TMenu.Create;
  Check((M.Items = nil) and (M.Deflt = nil), 'an empty menu has no items and no default');
  M.Free;
  C := TMenuItem.Create('c', cmNew, TKey.Create(kbNoKey));
  A := TMenuItem.Create('a', cmNew, TKey.Create(kbNoKey));
  M := TMenu.Create(C);
  Check((M.Items = C) and (M.Deflt = C), 'a menu of a list has the list as default');
  M.Free;
  C := TMenuItem.Create('c', cmNew, TKey.Create(kbNoKey), 0, '', A);
  M := TMenu.Create(C, A);
  Check((M.Items = C) and (M.Deflt = A), 'a menu of a list and a default has both');
  M.Free;
end;

procedure TestOperators;
var
  S1, S2, S3: TSubMenu;
  I1, I2, I3, I4, R: TMenuItem;
  D1, D2: TStatusDef;
  T1, T2, T3: TStatusItem;
  Sr: TSubMenu;
  Dr: TStatusDef;
  M: TMenu;
begin
  S1 := TSubMenu.Create('one', TKey.Create(kbNoKey));
  I1 := TMenuItem.Create('i1', cmNew, TKey.Create(kbNoKey));
  I2 := TMenuItem.Create('i2', cmNew, TKey.Create(kbNoKey));
  I3 := TMenuItem.Create('i3', cmNew, TKey.Create(kbNoKey));
  Sr := S1 + I1;
  Check(Sr = S1, 'sub menu plus item gives the sub menu');
  Check((S1.SubMenu.Items = I1) and (S1.SubMenu.Deflt = I1), 'the first item of a sub menu is its default');
  S1 := S1 + I2;
  Check((S1.SubMenu.Items = I1) and (I1.Next = I2) and (S1.SubMenu.Deflt = I1), 'the next item is appended');
  S1 := S1 + I3;
  Check((I2.Next = I3) and (I3.Next = nil), 'an item is appended at the end of the list');

  S2 := TSubMenu.Create('two', TKey.Create(kbNoKey));
  S3 := TSubMenu.Create('three', TKey.Create(kbNoKey));
  Sr := S1 + S2;
  Check((Sr = S1) and (S1.Next = S2), 'sub menu plus sub menu chains them');
  Sr := S2 + S3;
  Check((Sr = S2) and (S2.Next = S3) and (S1.Next = S2), 'sub menu plus sub menu appends at the end');
  I4 := TMenuItem.Create('i4', cmNew, TKey.Create(kbNoKey));
  Sr := S1 + I4;
  Check((Sr = S1) and (S3.SubMenu.Items = I4) and (S3.SubMenu.Deflt = I4),
    'an item added to a chain of sub menus goes to the last sub menu');
  Check(I3.Next = nil, 'the first sub menu does not receive that item');
  M := TMenu.Create(S1);
  M.Free;

  I1 := TMenuItem.Create('a', cmNew, TKey.Create(kbNoKey));
  I2 := TMenuItem.Create('b', cmNew, TKey.Create(kbNoKey));
  I3 := TMenuItem.Create('c', cmNew, TKey.Create(kbNoKey));
  R := I1 + I2;
  Check((R = I1) and (I1.Next = I2), 'item plus item chains them');
  R := I1 + I3;
  Check((R = I1) and (I2.Next = I3) and (I1.Next = I2), 'item plus item appends at the end');
  M := TMenu.Create(I1);
  M.Free;

  D1 := TStatusDef.Create(0, 9);
  D2 := TStatusDef.Create(10, 19);
  T1 := TStatusItem.Create('t1', TKey.Create(kbNoKey), cmNew);
  T2 := TStatusItem.Create('t2', TKey.Create(kbNoKey), cmOpen);
  T3 := TStatusItem.Create('t3', TKey.Create(kbNoKey), cmQuit);
  Dr := D1 + T1;
  Check((Dr = D1) and (D1.Items = T1), 'status definition plus item sets the first item');
  Dr := D1 + T2;
  Check((D1.Items = T1) and (T1.Next = T2), 'status definition plus item appends at the end');
  Dr := D1 + D2;
  Check((Dr = D1) and (D1.Next = D2), 'status definition plus status definition chains them');
  Dr := D1 + T3;
  Check((D2.Items = T3) and (T2.Next = nil), 'an item added to a chain of definitions goes to the last one');
  D2.Free;
  D1.Free;
  T1.Free;
  T2.Free;
  T3.Free;
end;

procedure TestDestroy;
var
  C1, C2, C3, C4, C5, R: TMenuItem;
  Sub: TSubMenu;
  M: TMenu;
begin
  ItemFreed := 0;
  C1 := TCountItem.Create('c1', cmNew, TKey.Create(kbNoKey), 0, 'param');
  C2 := TCountItem.Create('c2', cmOpen, TKey.Create(kbNoKey));
  C3 := TCountItem.Create('c3', cmQuit, TKey.Create(kbNoKey));
  C4 := TCountItem.Create('c4', cmCut, TKey.Create(kbNoKey));
  C5 := TCountItem.Create('c5', cmCopy, TKey.Create(kbNoKey));
  Sub := TSubMenu.Create('sub', TKey.Create(kbNoKey));
  Sub := Sub + C4 + C5;
  R := C1 + C2;
  R := C1 + C3;
  R := C1 + Sub;
  M := TMenu.Create(C1);
  M.Free;
  Check(ItemFreed = 5, 'freeing a menu frees its items and the items of its sub menus');
end;

procedure TestBarBasics;
var
  Bar: TCountBar;
  M: TMenu;
  Bar2: TMenuBar;
  Sub: TSubMenu;
begin
  Bar := NewBar;
  Check(Bar.GrowMode = gfGrowHiX, 'a menu bar grows with the high x');
  Check((Bar.Options and ofPreProcess) <> 0, 'a menu bar pre-processes events');
  Check((Bar.EventMask and evBroadcast) <> 0, 'a menu view receives broadcasts');
  Check((Bar.EventMask and evMouseDown) <> 0, 'a menu view keeps the default event mask');
  Check((TCrack(Bar).MenuObj <> nil) and (TCrack(Bar).MenuObj.Items = FileSub), 'the bar holds the menu of its sub menu');
  Check(TCrack(Bar).MenuObj.Deflt = FileSub, 'the menu of a sub menu has the sub menu as default');
  Check(TCrack(Bar).ParentView = nil, 'a menu bar has no parent menu');
  Check(TCrack(Bar).CurrentItem = nil, 'a menu bar has no current item');
  Check(TCrack(Bar).PutClick, 'a menu bar puts the click that closes it');
  Check((Bar.Size.X = ScrW) and (Bar.Size.Y = 1), 'the size of the bar is the size of the bounds');
  TvObject.DestroyObject(Bar);

  Sub := TSubMenu.Create('~S~ub', TKey.Create(kbNoKey));
  M := TMenu.Create(Sub);
  Bar2 := TMenuBar.Create(Rc(0, 0, 10, 1), M);
  Check(TCrack(Bar2).MenuObj = M, 'the bar holds the menu that is given');
  TvObject.DestroyObject(Bar2);
end;

procedure TestBarRect;
var
  Bar: TCountBar;
  I1: TMenuItem;
  Bar2: TMenuBar;
  R: TRect;
begin
  Bar := NewBar;
  R := Bar.GetItemRect(FileSub);
  Check(RectIs(R, 1, 0, 7, 1), 'the rectangle of the first item of a bar');
  R := Bar.GetItemRect(EditSub);
  Check(RectIs(R, 7, 0, 13, 1), 'the rectangle of the second item of a bar');
  TvObject.DestroyObject(Bar);

  FileSub := TSubMenu.Create('~F~ile', TKey.Create(kbNoKey));
  EditSub := TSubMenu.Create('~E~dit', TKey.Create(kbNoKey));
  I1 := FileSub;
  I1 := I1 + NewLine;
  SepItem := FileSub.Next;
  I1 := I1 + EditSub;
  Bar2 := TMenuBar.Create(Rc(0, 0, 20, 1), FileSub);
  R := Bar2.GetItemRect(SepItem);
  Check(RectIs(R, 7, 0, 7, 1), 'the rectangle of a line in a bar is empty');
  R := Bar2.GetItemRect(EditSub);
  Check(RectIs(R, 7, 0, 13, 1), 'an item after a line starts where the line is');
  TvObject.DestroyObject(Bar2);
end;

procedure TestBarDraw;
var
  Root: TRoot;
  Bar: TCountBar;
  Narrow: TMenuBar;
  Sub: TSubMenu;
begin
  Root := NewRoot;
  Bar := NewBar;
  Root.Insert(Bar);
  ClearScreen;
  Bar.DrawView;
  Check(RowText(0, 0, 14) = '  File  Edit  ', 'the bar draws the names without the tildes');
  Check(RowText(0, 14, 26) = StringOfChar(' ', 26), 'the bar fills the rest of the row with spaces');
  Check(AttrAt(0, 0) = $22, 'the space before the first item is normal');
  Check(AttrAt(1, 0) = $22, 'the space before an item is normal');
  Check(AttrAt(2, 0) = $44, 'the shortcut character is drawn with the shortcut color');
  Check(AttrAt(3, 0) = $22, 'the other characters are drawn with the normal color');
  Check(AttrAt(6, 0) = $22, 'the space after an item is normal');
  Check(AttrAt(39, 0) = $22, 'the end of the row is normal');

  TCrack(Bar).CurrentItem := FileSub;
  Bar.DrawView;
  Check(AttrAt(1, 0) = $55, 'the space before the current item is selected');
  Check(AttrAt(2, 0) = $77, 'the shortcut of the current item has the selected shortcut color');
  Check(AttrAt(3, 0) = $55, 'the text of the current item is selected');
  Check(AttrAt(6, 0) = $55, 'the space after the current item is selected');
  Check(AttrAt(7, 0) = $22, 'the next item is not selected');

  EditSub.Disabled := True;
  Bar.DrawView;
  Check((AttrAt(7, 0) = $33) and (AttrAt(8, 0) = $33) and (AttrAt(11, 0) = $33), 'a disabled item has the disabled color');
  TCrack(Bar).CurrentItem := EditSub;
  Bar.DrawView;
  Check((AttrAt(7, 0) = $66) and (AttrAt(8, 0) = $66) and (AttrAt(12, 0) = $66),
    'the current disabled item has the selected disabled color');
  Check(AttrAt(1, 0) = $22, 'an item that is not current is normal again');
  EditSub.Disabled := False;
  TCrack(Bar).CurrentItem := nil;
  TvObject.DestroyObject(Bar);

  Sub := TSubMenu.Create('~F~ile', TKey.Create(kbNoKey));
  Sub := Sub + TMenuItem.Create('x', cmNew, TKey.Create(kbNoKey));
  Sub := Sub + TSubMenu.Create('~E~dit', TKey.Create(kbNoKey));
  ClearScreen;
  Narrow := TMenuBar.Create(Rc(0, 2, 8, 3), Sub);
  Root.Insert(Narrow);
  Narrow.DrawView;
  Check(RowText(2, 0, 8) = '  File  ', 'an item that does not fit in the bar is not drawn');
  Check(CharAt(8, 2) = #0, 'the bar writes only its own width');
  TvObject.DestroyObject(Narrow);
  FreeRoot(Root);
end;

procedure TestBoxGeometry;
var
  A1, A2, A3, A4, A5, Chain: TMenuItem;
  M7: TMenu;
  Box: TMenuBox;
  Bar: TCountBar;
  R: TRect;
begin
  A1 := TMenuItem.Create('~N~ew', cmNew, TKey.Create(kbF4), 0, 'F4');
  A2 := TMenuItem.Create('~O~pen file', cmOpen, TKey.Create(kbF3));
  A3 := NewLine;
  A4 := TMenuItem.Create('~S~ave as', TKey.Create(kbF2), TMenu.Create);
  A5 := TMenuItem.Create('E~x~it', cmQuit, TKey.Create(kbAltX));
  Chain := A1 + A2 + A3 + A4 + A5;
  M7 := TMenu.Create(Chain);

  Box := TMenuBox.Create(Rc(5, 3, 30, 18), M7, nil);
  Check((Box.Origin.X = 5) and (Box.Origin.Y = 3), 'the box is placed at the top left of the bounds when it fits');
  Check((Box.Size.X = 16) and (Box.Size.Y = 7), 'the width of the box is the widest item and its height one row per item plus 2');
  Check((Box.State and sfShadow) <> 0, 'a menu box has a shadow');
  Check((Box.Options and ofPreProcess) <> 0, 'a menu box pre-processes events');
  Check(TCrack(Box).ParentView = nil, 'a box without a parent menu has none');
  Check(TCrack(Box).MenuObj = M7, 'the box holds its menu');
  Check(TCrack(Box).PutClick, 'a menu box puts the click that closes it');
  Check((Box.EventMask and evBroadcast) <> 0, 'a menu box receives broadcasts');
  TvObject.DestroyObject(Box);

  Box := TMenuBox.Create(Rc(5, 3, 10, 6), M7, nil);
  Check((Box.Origin.X = -6) and (Box.Origin.Y = -1), 'the box is moved back from the bottom right corner of the bounds');
  Check((Box.Size.X = 16) and (Box.Size.Y = 7), 'the size of the box does not depend on the bounds');
  R := Box.GetItemRect(A1);
  Check(RectIs(R, 2, 1, 14, 2), 'the rectangle of the first item of a box');
  R := Box.GetItemRect(A2);
  Check(RectIs(R, 2, 2, 14, 3), 'the rectangle of the second item of a box');
  R := Box.GetItemRect(A3);
  Check(RectIs(R, 2, 3, 14, 4), 'the rectangle of a line in a box');
  R := Box.GetItemRect(A5);
  Check(RectIs(R, 2, 5, 14, 6), 'the rectangle of the last item of a box');
  TvObject.DestroyObject(Box);
  M7.Free;

  Box := TMenuBox.Create(Rc(0, 0, 30, 20), nil, nil);
  Check((Box.Size.X = 10) and (Box.Size.Y = 2), 'a box without a menu has the minimal size');
  TvObject.DestroyObject(Box);

  Bar := NewBar;
  Box := TMenuBox.Create(Rc(3, 1, 40, 20), FileSub.SubMenu, Bar);
  Check(TCrack(Box).ParentView = Bar, 'the box holds its parent menu');
  Check((Box.Size.X = 13) and (Box.Size.Y = 6), 'the width counts the parameter of an item');
  TvObject.DestroyObject(Box);
  TvObject.DestroyObject(Bar);
end;

procedure TestBoxDraw;
var
  Root: TRoot;
  Box: TMenuBox;
  D1, D2, D3, D4: TMenuItem;
  M: TMenu;
begin
  Root := NewRoot;
  D1 := TMenuItem.Create('~N~ew', cmNew, TKey.Create(kbF4), 0, 'F4');
  D2 := NewLine;
  D3 := TMenuItem.Create('~S~ub', TKey.Create(kbF2), TMenu.Create);
  D4 := TMenuItem.Create('Close', cmClose, TKey.Create(kbNoKey));
  D4.Disabled := True;
  M := TMenu.Create(D1 + D2 + D3 + D4);
  Box := TMenuBox.Create(Rc(2, 3, 30, 18), M, nil);
  Root.Insert(Box);
  Check((Box.Origin.X = 2) and (Box.Origin.Y = 3) and (Box.Size.X = 13) and (Box.Size.Y = 6), 'the box for the drawing');
  ClearScreen;
  Box.DrawView;
  Check(RowText(3, 2, 13) = 'abcccccccccde', 'the top line of the frame');
  Check(RowText(4, 2, 13) = 'klmNewmmF4mno', 'an item line with a name and a parameter');
  Check(RowText(5, 2, 13) = 'pqrrrrrrrrrst', 'a separator line');
  Check(RowText(6, 2, 9) = 'klmSubmmm', 'an item line with a sub menu');
  Check((CharAt(11, 6) <> 'm') and (CharAt(12, 6) = 'm'), 'the mark of a sub menu is at the fourth column from the right');
  Check(RowText(6, 13, 2) = 'no', 'the right frame characters of a sub menu line');
  Check(RowText(7, 2, 13) = 'klmClosemmmno', 'an item line of a disabled item');
  Check(RowText(8, 2, 13) = 'fghhhhhhhhhij', 'the bottom line of the frame');
  Check((AttrAt(2, 3) = $22) and (AttrAt(8, 3) = $22) and (AttrAt(14, 3) = $22), 'the top line is normal');
  Check(AttrAt(5, 4) = $44, 'the shortcut character of an item is drawn with the shortcut color');
  Check((AttrAt(6, 4) = $22) and (AttrAt(4, 4) = $22), 'an item that is not current is normal');
  Check(AttrAt(10, 4) = $22, 'the parameter of an item that is not current is normal');
  Check((AttrAt(5, 7) = $33) and (AttrAt(4, 7) = $33) and (AttrAt(9, 7) = $33), 'a disabled item has the disabled color');
  Check(AttrAt(2, 7) = $22, 'the frame of a disabled item is normal');

  TCrack(Box).CurrentItem := D1;
  Box.DrawView;
  Check(AttrAt(5, 4) = $77, 'the shortcut of the current item has the selected shortcut color');
  Check((AttrAt(6, 4) = $55) and (AttrAt(4, 4) = $55) and (AttrAt(10, 4) = $55), 'the current item is selected');
  Check((AttrAt(2, 4) = $22) and (AttrAt(3, 4) = $22) and (AttrAt(13, 4) = $22), 'the frame of the current item is normal');
  TCrack(Box).CurrentItem := D4;
  Box.DrawView;
  Check((AttrAt(5, 7) = $66) and (AttrAt(4, 7) = $66), 'the current disabled item has the selected disabled color');
  Check(AttrAt(5, 4) = $44, 'the previous current item is normal again');
  TCrack(Box).CurrentItem := nil;
  TvObject.DestroyObject(Box);
  M.Free;
  FreeRoot(Root);
end;

procedure TestFindAndHotKey;
var
  Bar: TCountBar;
  Box: TMenuBox;
begin
  Bar := NewBar;
  Check(Bar.FindItem('f') = FileSub, 'FindItem ignores the case of the character');
  Check(Bar.FindItem('E') = EditSub, 'FindItem finds an item by its shortcut');
  Check(Bar.FindItem('x') = nil, 'FindItem looks in the menu of the view only');
  Check(Bar.FindItem('') = nil, 'FindItem of an empty text finds nothing');
  Check(Bar.FindItem(string('e')) = EditSub, 'FindItem takes a text');
  Check(Bar.FindItem(#0) = nil, 'FindItem of a zero character finds nothing');
  EditSub.Disabled := True;
  Check(Bar.FindItem('e') = nil, 'FindItem skips a disabled item');
  EditSub.Disabled := False;
  HotKeyStrHook := nil;
  Check(Bar.FindItem('f') = nil, 'FindItem finds nothing while the hook for the shortcut is not set');
  HotKeyStrHook := @TestHotKeyStr;
  Check(Bar.FindItem('F') = FileSub, 'FindItem finds an item by the upper case of its shortcut');
  Check(Bar.FindItem('fe') = nil, 'FindItem compares the whole text, not its first character');

  Check(Bar.HotKey(TKey.Create(kbF4)) = NewItem, 'HotKey looks into sub menus');
  Check(Bar.HotKey(TKey.Create(kbAltX)) = ExitItem, 'HotKey finds an item after a line');
  Check(Bar.HotKey(TKey.Create(kbF1)) = nil, 'HotKey of an unknown key finds nothing');
  Check(Bar.HotKey(TKey.Create(kbNoKey)) = nil, 'HotKey of no key finds nothing');
  Check(Bar.HotKey(TKey.Create(kbAltF)) = nil, 'the key of a sub menu is not a hot key');
  NewItem.Disabled := True;
  Check(Bar.HotKey(TKey.Create(kbF4)) = nil, 'HotKey skips a disabled item');
  NewItem.Disabled := False;

  Box := TMenuBox.Create(Rc(0, 1, 40, 20), FileSub.SubMenu, nil);
  Check(Box.FindItem('o') = OpenItem, 'a box finds an item by its shortcut');
  Check(Box.FindItem('x') = ExitItem, 'a shortcut can be in the middle of the name');
  Check(Box.FindItem('f') = nil, 'a box does not find the items of another menu');
  Check(Box.HotKey(TKey.Create(kbF3)) = OpenItem, 'a box finds a hot key');
  TvObject.DestroyObject(Box);
  TvObject.DestroyObject(Bar);
end;

{ Shortcuts outside ASCII: a name holds one in UTF-8 or as a byte of code page 437, and the text that is looked for
  holds it in either form. #$C3#$BC is the letter u with a diaeresis in UTF-8 and #$81 is that letter in code page
  437; #$C3#$A9 and #$82 are the letter e with an acute accent. }
procedure TestFindExtended;
var
  First, Second, Third, Chain: TMenuItem;
  M: TMenu;
  Box: TMenuBox;
begin
  First := TMenuItem.Create('~'#$C3#$BC'~ber', cmNew, TKey.Create(kbNoKey));
  Second := TMenuItem.Create('~'#$82'~cole', cmOpen, TKey.Create(kbNoKey));
  Third := TMenuItem.Create('~Q~uit', cmQuit, TKey.Create(kbNoKey));
  Chain := First + Second + Third;
  M := TMenu.Create(Chain);
  Box := TMenuBox.Create(Rc(0, 1, 40, 20), M, nil);
  Check(Box.FindItem(#$C3#$BC) = First, 'a UTF-8 shortcut is found by the same text');
  Check(Box.FindItem(#$81) = First, 'a UTF-8 shortcut is found by the byte of the code page');
  Check(Box.FindItem(#$82) = Second, 'a shortcut that is a byte of the code page is found by that byte');
  Check(Box.FindItem(#$C3#$A9) = Second, 'a shortcut that is a byte of the code page is found by its UTF-8 text');
  Check(Box.FindItem('u') = nil, 'a letter with a diaeresis is not the letter without it');
  Check(Box.FindItem('e') = nil, 'a letter with an accent is not the letter without it');
  Check(Box.FindItem('q') = Third, 'the lower case of an upper case shortcut is found');
  Check(Box.FindItem('Q') = Third, 'the upper case shortcut is found');
  TvObject.DestroyObject(Box);
  M.Free;
end;

procedure TestHelpCtx;
var
  Bar: TCountBar;
  Box: TMenuBox;
begin
  Bar := NewBar;
  Bar.HelpCtx := 3;
  Check(Bar.GetHelpCtx = 3, 'a menu view without a current item has its own help context');
  TCrack(Bar).CurrentItem := FileSub;
  Check(Bar.GetHelpCtx = 11, 'the help context is the one of the current item');
  TCrack(Bar).CurrentItem := EditSub;
  Check(Bar.GetHelpCtx = 3, 'an item without a help context gives the own help context');
  Box := TMenuBox.Create(Rc(0, 1, 40, 20), FileSub.SubMenu, Bar);
  TCrack(Bar).CurrentItem := FileSub;
  Check(Box.GetHelpCtx = 11, 'a box without a current item asks its parent menu');
  TCrack(Box).CurrentItem := NewItem;
  Check(Box.GetHelpCtx = 22, 'a box gives the help context of its current item');
  TCrack(Box).CurrentItem := SepItem;
  Check(Box.GetHelpCtx = 11, 'a line is skipped and the parent menu is asked');
  TCrack(Box).CurrentItem := OpenItem;
  Check(Box.GetHelpCtx = 11, 'an item without a help context is skipped');
  TCrack(Box).CurrentItem := nil;
  TCrack(Bar).CurrentItem := nil;
  TvObject.DestroyObject(Box);
  TvObject.DestroyObject(Bar);
end;

procedure TestBarExec;
var
  Root: TRoot;
  Bar: TCountBar;
  R: Word;
begin
  { Esc ends the loop; nothing is put back. }
  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Bar);
  Check(R = 0, 'Esc ends a menu bar with the command 0');
  Check(Root.PutCount = 0, 'Esc on a menu bar is cleared');
  Check(TCrack(Bar).CurrentItem = nil, 'the current item is none after the loop');
  Check(TCrack(Bar).MenuObj.Deflt = FileSub, 'the default item is the current item of the end');
  Check(Root.IndexOf(Bar) = 0, 'the bar is removed from the root after ExecView');
  Check(Root.TopLog = 'TCountBar ', 'the bar is the top view while it executes');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  { Enter opens the default menu; Enter in it selects its default item. }
  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(KeyEv(kbEnter));
  Root.AddEvent(KeyEv(kbEnter));
  R := Root.ExecView(Bar);
  Check(R = cmNew, 'Enter on the bar and in the menu selects the default command');
  Check(Root.PutCount = 0, 'a selection puts no event back');
  Check(Root.TopLog = 'TCountBar TMenuBox ', 'the sub menu is a modal menu box');
  Check((Root.TopOrigin.X = 0) and (Root.TopOrigin.Y = 1), 'the menu box is placed below the item of the bar');
  Check((Root.TopSize.X = 13) and (Root.TopSize.Y = 6), 'the menu box has the size of its items');
  Check(TCrack(Bar).MenuObj.Deflt = FileSub, 'the bar remembers the item that was opened');
  Check(FileSub.SubMenu.Deflt = NewItem, 'the box remembers the item that was selected');
  Check(Root.IndexOf(Bar) = 0, 'the bar is removed after the selection');
  Check(Root.First = nil, 'the menu box is removed and disposed after the selection');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  { Down opens the menu; Esc in the menu is put back for the bar; the second Esc closes the bar. }
  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEsc));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Bar);
  Check(R = 0, 'Esc in a menu of a bar ends with the command 0');
  Check(Root.PutCount = 1, 'Esc in a sub menu of a bar is put back for the bar');
  Check((Root.LastPut.What = evKeyDown) and (Root.LastPut.KeyDown.KeyCode = kbEsc), 'the event that was put back is Esc');
  Check(Root.TopLog = 'TCountBar TMenuBox TCountBar ', 'the bar is the top view again after the menu closes');
  Check(Root.ScriptPos = 3, 'the bar read the Esc event that it was given');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  { A hot key ends the loop with its command. }
  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(KeyEv(kbF4));
  R := Root.ExecView(Bar);
  Check(R = cmNew, 'a hot key selects the command of its item');
  Check(Root.PutCount = 0, 'a hot key is cleared');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  { A hot key of a disabled command is not a selection. }
  Root := NewRoot;
  Bar := NewBar;
  TView.DisableCommand(cmNew);
  Root.AddEvent(KeyEv(kbF4));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Bar);
  TView.EnableCommand(cmNew);
  Check((R = 0) and (Root.ScriptPos = 2), 'a hot key of a disabled command does not end the loop');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  { Alt and the shortcut of an item opens it. }
  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(KeyEv(kbAltF));
  Root.AddEvent(KeyEv(kbEsc));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Bar);
  Check(R = 0, 'Alt and a letter opens the menu of the letter');
  Check(Root.TopLog = 'TCountBar TMenuBox TCountBar ', 'the menu of the letter was opened');
  Check(Root.PutCount = 1, 'Esc in the opened menu is put back');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  { The arrow keys move along the bar. }
  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(KeyEv(kbRight));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Bar);
  Check(TCrack(Bar).MenuObj.Deflt = EditSub, 'Right moves to the next item of the bar');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(KeyEv(kbRight));
  Root.AddEvent(KeyEv(kbRight));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Bar);
  Check(TCrack(Bar).MenuObj.Deflt = FileSub, 'Right after the last item goes to the first');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(KeyEv(kbLeft));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Bar);
  Check(TCrack(Bar).MenuObj.Deflt = EditSub, 'Left before the first item goes to the last');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  { cmMenu is ignored by the top menu; another command ends the loop and is put back. }
  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(CmdEv(cmMenu));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Bar);
  Check((R = 0) and (Root.PutCount = 0) and (Root.ScriptPos = 2), 'cmMenu does not end the top menu');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(CmdEv(cmQuit));
  R := Root.ExecView(Bar);
  Check(R = 0, 'another command ends the menu with the command 0');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmQuit),
    'the command that ended the menu is put back');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  { A click outside the bar closes it and is put back. }
  Root := NewRoot;
  Bar := NewBar;
  Root.AddEvent(MouseEv(evMouseDown, 30, 10));
  R := Root.ExecView(Bar);
  Check(R = 0, 'a click outside ends the bar with the command 0');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evMouseDown), 'the click that closes the bar is put back');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);

  Root := NewRoot;
  Bar := NewBar;
  TCrack(Bar).PutClick := False;
  Root.AddEvent(MouseEv(evMouseDown, 30, 10));
  R := Root.ExecView(Bar);
  Check((R = 0) and (Root.PutCount = 0), 'the click is not put back when the view does not ask for it');
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);
end;

procedure TestBoxExec;
var
  Root: TRoot;
  Box: TMenuBox;
  A1, A2, A3, A4: TMenuItem;
  M: TMenu;
  R: Word;

  procedure Setup;
  begin
    Root := NewRoot;
    A1 := TMenuItem.Create('~N~ew', cmNew, TKey.Create(kbF4), 0, 'F4');
    A2 := TMenuItem.Create('~O~pen', cmOpen, TKey.Create(kbF3));
    A3 := NewLine;
    A4 := TMenuItem.Create('E~x~it', cmQuit, TKey.Create(kbNoKey));
    M := TMenu.Create(A1 + A2 + A3 + A4);
    Box := TMenuBox.Create(Rc(5, 3, 30, 18), M, nil);
  end;

  procedure TearDown;
  begin
    TvObject.DestroyObject(Box);
    M.Free;
    FreeRoot(Root);
  end;

begin
  Setup;
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEnter));
  R := Root.ExecView(Box);
  Check(R = cmOpen, 'Down and Enter select the second item');
  Check(M.Deflt = A2, 'the box remembers the selected item');
  Check(TCrack(Box).CurrentItem = nil, 'the box has no current item after the loop');
  TearDown;

  Setup;
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEnter));
  R := Root.ExecView(Box);
  Check(R = cmQuit, 'Down skips a line');
  TearDown;

  Setup;
  Root.AddEvent(KeyEv(kbUp));
  Root.AddEvent(KeyEv(kbEnter));
  R := Root.ExecView(Box);
  Check(R = cmQuit, 'Up from the first item goes to the last');
  TearDown;

  Setup;
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbUp));
  Root.AddEvent(KeyEv(kbEnter));
  R := Root.ExecView(Box);
  Check(R = cmOpen, 'Up skips a line');
  TearDown;

  Setup;
  Root.AddEvent(KeyEv(kbEnd));
  Root.AddEvent(KeyEv(kbEnter));
  R := Root.ExecView(Box);
  Check(R = cmQuit, 'End goes to the last item');
  TearDown;

  Setup;
  Root.AddEvent(KeyEv(kbEnd));
  Root.AddEvent(KeyEv(kbHome));
  Root.AddEvent(KeyEv(kbEnter));
  R := Root.ExecView(Box);
  Check(R = cmNew, 'Home goes to the first item');
  TearDown;

  Setup;
  Root.AddEvent(TextKeyEv('o'));
  R := Root.ExecView(Box);
  Check(R = cmOpen, 'a letter selects the item with that shortcut');
  Check(Root.PutCount = 0, 'a letter is cleared');
  TearDown;

  Setup;
  A2.Disabled := True;
  Root.AddEvent(TextKeyEv('o'));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Box);
  Check((R = 0) and (Root.ScriptPos = 2), 'a letter does not select a disabled item');
  TearDown;

  Setup;
  Root.AddEvent(KeyEv(kbF3));
  R := Root.ExecView(Box);
  Check(R = cmOpen, 'a hot key selects its item in a box');
  TearDown;

  Setup;
  TView.DisableCommand(cmOpen);
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEnter));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Box);
  TView.EnableCommand(cmOpen);
  Check((R = 0) and (Root.ScriptPos = 3), 'Enter on an item of a disabled command does not end the loop');
  Check(Root.PutCount = 0, 'Esc in a box without a parent menu is cleared');
  TearDown;

  Setup;
  Root.AddEvent(KeyEv(kbLeft));
  Root.AddEvent(KeyEv(kbRight));
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Box);
  Check((R = 0) and (Root.ScriptPos = 3), 'Left and Right do not end a box without a parent menu');
  TearDown;
end;

procedure TestHandleEvent;
var
  Root: TRoot;
  Bar: TCountBar;
  Ev: TEvent;
  Before: Integer;
  Saved: TMenu;
begin
  Root := NewRoot;
  Bar := NewBar;
  Root.Insert(Bar);

  Ev := CmdEv(cmMenu);
  Root.AddEvent(KeyEv(kbEsc));
  Bar.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'cmMenu is handled by the bar');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmMenu),
    'cmMenu is put back before the bar executes');
  Check(Root.ScriptPos = 1, 'the bar executed and read its event');

  Root.PutCount := 0;
  Ev := CmdEv(cmQuit);
  Bar.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (Root.PutCount = 0), 'another command is not handled');

  Root.PutCount := 0;
  Ev := KeyEv(kbAltF);
  Root.AddEvent(KeyEv(kbEsc));
  Bar.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'an Alt key of an item is handled');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evKeyDown) and (Root.LastPut.KeyDown.KeyCode = kbAltF),
    'the Alt key is put back before the bar executes');

  Root.PutCount := 0;
  Ev := KeyEv(kbF4);
  Bar.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a hot key is cleared');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmNew),
    'a hot key becomes the command of its item');
  Check(Root.LastPut.Message.InfoPtr = nil, 'the command of a hot key has no information pointer');

  Root.PutCount := 0;
  TView.DisableCommand(cmNew);
  Ev := KeyEv(kbF4);
  Bar.HandleEvent(Ev);
  TView.EnableCommand(cmNew);
  Check((Ev.What = evKeyDown) and (Root.PutCount = 0), 'a hot key of a disabled command is not handled');

  Root.PutCount := 0;
  NewItem.Disabled := True;
  Ev := KeyEv(kbF4);
  Bar.HandleEvent(Ev);
  NewItem.Disabled := False;
  Check((Ev.What = evKeyDown) and (Root.PutCount = 0), 'a hot key of a disabled item is not handled');

  Root.PutCount := 0;
  Ev := KeyEv(kbF9);
  Bar.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.PutCount = 0), 'a key that matches nothing is not handled');

  Root.PutCount := 0;
  Ev := MouseEv(evMouseDown, 3, 0);
  Root.AddEvent(KeyEv(kbEsc));
  Bar.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a mouse down is handled by the bar');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evMouseDown), 'the mouse down is put back before the bar executes');

  Before := Bar.DrawCount;
  TView.DisableCommand(cmCopy);
  Ev := BroadcastEv(cmCommandSetChanged);
  Bar.HandleEvent(Ev);
  Check(CopyItem.Disabled and not CutItem.Disabled, 'a changed command set disables the items of the sub menus');
  Check(Bar.DrawCount = Before + 1, 'the bar is drawn when an item changed');
  Ev := BroadcastEv(cmCommandSetChanged);
  Bar.HandleEvent(Ev);
  Check(Bar.DrawCount = Before + 1, 'the bar is not drawn when no item changed');
  TView.EnableCommand(cmCopy);
  Ev := BroadcastEv(cmCommandSetChanged);
  Bar.HandleEvent(Ev);
  Check(not CopyItem.Disabled, 'a changed command set enables the items again');
  Check(Bar.DrawCount = Before + 2, 'the bar is drawn when an item is enabled');
  Ev := BroadcastEv(cmReceivedFocus);
  Bar.HandleEvent(Ev);
  Check(Bar.DrawCount = Before + 2, 'another broadcast does nothing');

  Root.PutCount := 0;
  Saved := TCrack(Bar).MenuObj;
  TCrack(Bar).MenuObj := nil;
  Ev := KeyEv(kbF4);
  Bar.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.PutCount = 0), 'a view without a menu handles nothing');
  TCrack(Bar).MenuObj := Saved;
  TvObject.DestroyObject(Bar);
  FreeRoot(Root);
end;

procedure TestPopupView;
var
  Root: TRoot;
  Popup: TMenuPopup;
  A, B: TMenuItem;
  M: TMenu;
  Ev: TEvent;
  R: Word;
begin
  Root := NewRoot;
  A := TMenuItem.Create('~A~lpha', cmNew, TKey.Create(kbF4));
  B := TMenuItem.Create('~B~eta', cmOpen, TKey.Create(kbF3));
  M := TMenu.Create(A + B);
  Popup := TMenuPopup.Create(Rc(5, 5, 30, 15), M, nil);
  Check(not TCrack(Popup).PutClick, 'a popup does not put the click that closes it');
  Check((Popup.State and sfShadow) <> 0, 'a popup has a shadow');
  Check((Popup.Options and ofPreProcess) <> 0, 'a popup pre-processes events');
  Root.Insert(Popup);

  Ev := KeyEv(kbCtrlA);
  Popup.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a control character selects an item');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmNew),
    'the control character becomes the command of the item with that letter');
  Check(Root.LastPut.Message.InfoPtr = nil, 'the command has no information pointer');

  Root.PutCount := 0;
  Ev := KeyEv(kbF3);
  Popup.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.PutCount = 1) and (Root.LastPut.Message.Command = cmOpen),
    'a hot key becomes a command');

  Root.PutCount := 0;
  Ev := KeyEv(kbAltX);
  Popup.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.PutCount = 0), 'an unknown Alt key is cleared');

  Ev := KeyEv(kbF9);
  Popup.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.PutCount = 0), 'a key that matches nothing is left');

  A.Disabled := True;
  Ev := KeyEv(kbCtrlA);
  Popup.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.PutCount = 0), 'a disabled item is not selected');
  A.Disabled := False;

  TView.DisableCommand(cmOpen);
  Ev := KeyEv(kbF3);
  Popup.HandleEvent(Ev);
  TView.EnableCommand(cmOpen);
  Check((Ev.What = evKeyDown) and (Root.PutCount = 0), 'a hot key of a disabled command is left');

  Ev := CmdEv(cmQuit);
  Popup.HandleEvent(Ev);
  Check(Ev.What = evCommand, 'another kind of event is passed to the menu box');
  TvObject.DestroyObject(Popup);
  FreeRoot(Root);

  { Executing: the default item is not highlighted, and a click outside is not put back. }
  Root := NewRoot;
  A := TMenuItem.Create('~A~lpha', cmNew, TKey.Create(kbF4));
  B := TMenuItem.Create('~B~eta', cmOpen, TKey.Create(kbF3));
  M := TMenu.Create(A + B);
  Popup := TMenuPopup.Create(Rc(5, 5, 30, 15), M, nil);
  Root.AddEvent(MouseEv(evMouseDown, 35, 15));
  R := Root.ExecView(Popup);
  Check(R = 0, 'a click outside ends a popup with the command 0');
  Check(Root.PutCount = 0, 'the click outside is not put back by a popup');
  Check(M.Deflt = nil, 'a popup has no default item');
  TvObject.DestroyObject(Popup);
  FreeRoot(Root);

  Root := NewRoot;
  A := TMenuItem.Create('~A~lpha', cmNew, TKey.Create(kbF4));
  B := TMenuItem.Create('~B~eta', cmOpen, TKey.Create(kbF3));
  M := TMenu.Create(A + B);
  Popup := TMenuPopup.Create(Rc(5, 5, 30, 15), M, nil);
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEnter));
  R := Root.ExecView(Popup);
  Check(R = cmOpen, 'the first Down of a popup highlights the first item');
  TvObject.DestroyObject(Popup);
  FreeRoot(Root);
end;

procedure TestPopupMenu;
var
  Root: TRoot;
  A, B: TMenuItem;
  R: Word;
begin
  { The popup is placed below the reference position. }
  Root := NewRoot;
  ItemFreed := 0;
  A := TCountItem.Create('~A~lpha', cmNew, TKey.Create(kbNoKey));
  B := TCountItem.Create('~B~eta', cmOpen, TKey.Create(kbNoKey));
  A := A + B;
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEnter));
  R := PopupMenu(Pt(10, 5), A, Root);
  Check(R = cmNew, 'PopupMenu returns the selected command');
  Check(Root.TopLog = 'TMenuPopup TMenuPopup ', 'the popup is executed on the application');
  Check((Root.TopOrigin.X = 10) and (Root.TopOrigin.Y = 6), 'the popup is placed one row below the position');
  Check((Root.TopSize.X = 11) and (Root.TopSize.Y = 4), 'the popup has the size of its items');
  Check(ItemFreed = 2, 'the popup takes the items and frees them');
  Check(Root.First = nil, 'the popup is removed from the application');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmNew),
    'the selected command is put into the receiver');
  FreeRoot(Root);

  { Near the bottom right corner the popup is moved back, and it is moved above the position when it covers it. }
  Root := NewRoot;
  A := TCountItem.Create('~A~lpha', cmNew, TKey.Create(kbNoKey));
  B := TCountItem.Create('~B~eta', cmOpen, TKey.Create(kbNoKey));
  A := A + B;
  Root.AddEvent(KeyEv(kbEsc));
  R := PopupMenu(Pt(35, 18), A, Root);
  Check(R = 0, 'PopupMenu returns 0 when nothing is selected');
  Check((Root.TopOrigin.X = 29) and (Root.TopOrigin.Y = 14), 'the popup near the corner is moved above the position');
  Check((Root.TopSize.X = 11) and (Root.TopSize.Y = 4), 'the size of that popup');
  Check(Root.PutCount = 0, 'no event is put when nothing is selected');
  FreeRoot(Root);

  { Without a receiver no event is put. }
  Root := NewRoot;
  A := TCountItem.Create('~A~lpha', cmNew, TKey.Create(kbNoKey));
  Root.AddEvent(KeyEv(kbDown));
  Root.AddEvent(KeyEv(kbEnter));
  R := PopupMenu(Pt(2, 2), A, nil);
  Check((R = cmNew) and (Root.PutCount = 0), 'without a receiver the command is only returned');
  FreeRoot(Root);

  { Without an application nothing happens. }
  Root := NewRoot;
  ItemFreed := 0;
  A := TCountItem.Create('~A~lpha', cmNew, TKey.Create(kbNoKey));
  ApplicationHook := nil;
  R := PopupMenu(Pt(2, 2), A, Root);
  ApplicationHook := @TestApp;
  Check(R = 0, 'PopupMenu answers 0 without an application');
  Check(ItemFreed = 0, 'the items are not freed without an application');
  A.Free;
  FreeRoot(Root);
end;

procedure TestStatusItems;
var
  I: TStatusItem;
  J: TStatusItem;
  D: TStatusDef;
  E: TStatusDef;
begin
  I := TStatusItem.Create('~F1~ Help', TKey.Create(kbF1), cmHelp);
  Check(NameOf(I.Text) = '~F1~ Help', 'a status item keeps its text');
  Check(I.KeyCode = TKey.Create(kbF1), 'a status item keeps its key');
  Check(I.Command = cmHelp, 'a status item keeps its command');
  Check(I.Next = nil, 'a status item has no next item by default');
  J := TStatusItem.Create('x', TKey.Create(kbNoKey), cmNew, I);
  Check(J.Next = I, 'the next status item is the last argument');
  J.Free;
  I.Free;

  E := TStatusDef.Create(3, 8);
  D := TStatusDef.Create(1, 5, nil, E);
  Check((D.Min = 1) and (D.Max = 5), 'a status definition keeps its range');
  Check((D.Items = nil) and (D.Next = E), 'a status definition keeps its items and its next definition');
  Check((E.Next = nil) and (E.Items = nil), 'a status definition has no next definition and no items by default');
  E.Free;
  D.Free;
end;

procedure TestStatusLine;
var
  Root: TRoot;
  Line, Narrow: TCountStatus;
  Plain: TStatusLine;
  D1, D2: TStatusDef;
  SI1, SI2, SI3: TStatusItem;
  V: TView;
  Ev: TEvent;
  Before: Integer;
begin
  Root := NewRoot;
  SI1 := TCountStatusItem.Create('~F1~ Help', TKey.Create(kbF1), cmHelp);
  SI2 := TCountStatusItem.Create('~F10~ Menu', TKey.Create(kbF10), cmMenu);
  SI3 := TCountStatusItem.Create('~Alt-X~ Exit', TKey.Create(kbAltX), cmQuit);
  D1 := TStatusDef.Create(0, 0);
  D2 := TStatusDef.Create(5, 9);
  D1 := D1 + SI1 + SI2 + D2 + SI3;
  Line := TCountStatus.Create(Rc(0, 19, ScrW, 20), D1);
  Check((Line.Options and ofPreProcess) <> 0, 'a status line pre-processes events');
  Check((Line.EventMask and evBroadcast) <> 0, 'a status line receives broadcasts');
  Check(Line.GrowMode = (gfGrowLoY or gfGrowHiX or gfGrowHiY), 'the grow mode of a status line');
  Check(TStatusCrack(Line).DefList = D1, 'the status line holds its definitions');
  Check(TStatusCrack(Line).ItemList = SI1, 'the status line starts with the items of the definition of context 0');
  Root.Insert(Line);

  ClearScreen;
  Line.DrawView;
  Check(RowText(19, 0, 19) = ' F1 Help  F10 Menu ', 'the status line draws the items without the tildes');
  Check(RowText(19, 19, 21) = StringOfChar(' ', 21), 'the rest of the row is spaces when there is no hint');
  Check((AttrAt(0, 19) = $22) and (AttrAt(1, 19) = $44) and (AttrAt(2, 19) = $44), 'the shortcut of an item');
  Check((AttrAt(3, 19) = $22) and (AttrAt(8, 19) = $22) and (AttrAt(30, 19) = $22), 'the other text is normal');
  Check(AttrAt(11, 19) = $44, 'the shortcut of the second item');

  Line.HintText := 'Hello';
  Line.DrawView;
  Check(RowText(19, 0, 26) = ' F1 Help  F10 Menu | Hello', 'the hint follows the separator');
  Check((AttrAt(19, 19) = $22) and (AttrAt(21, 19) = $22) and (AttrAt(25, 19) = $22), 'the hint is normal');
  Line.HintText := '';

  TView.DisableCommand(cmMenu);
  Line.DrawView;
  Check((AttrAt(9, 19) = $33) and (AttrAt(10, 19) = $33) and (AttrAt(18, 19) = $33), 'an item of a disabled command is disabled');
  Check(AttrAt(1, 19) = $44, 'the item of an enabled command is normal');
  TView.EnableCommand(cmMenu);

  { Events }
  Ev := KeyEv(kbF10);
  Line.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (Ev.Message.Command = cmMenu) and (Ev.Message.InfoPtr = nil),
    'the key of an item becomes its command');
  TView.DisableCommand(cmMenu);
  Ev := KeyEv(kbF10);
  Line.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'the key of an item of a disabled command stays a key');
  TView.EnableCommand(cmMenu);
  Ev := KeyEv(kbNoKey);
  Line.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'a key code of no key is ignored');
  Ev := KeyEv(kbAltX);
  Line.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'a key of an item of another definition is ignored');
  Ev := KeyEv(kbF1, kbShift);
  Line.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'a key with another modifier is not the key of the item');

  Before := Line.DrawCount;
  Ev := BroadcastEv(cmCommandSetChanged);
  Line.HandleEvent(Ev);
  Check(Line.DrawCount = Before + 1, 'a changed command set redraws the status line');
  Ev := BroadcastEv(cmReceivedFocus);
  Line.HandleEvent(Ev);
  Check(Line.DrawCount = Before + 1, 'another broadcast does not redraw it');

  { The mouse }
  Root.PutCount := 0;
  Root.AddEvent(MouseEv(evMouseUp, 2, 19));
  Ev := MouseEv(evMouseDown, 2, 19);
  Before := Line.DrawCount;
  Line.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a click on the status line is cleared');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmHelp),
    'a click on an item puts its command');
  Check(Root.LastPut.Message.InfoPtr = nil, 'the command of a click has no information pointer');
  Check(Line.DrawCount = Before + 1, 'the status line is redrawn after a click');

  Root.PutCount := 0;
  Root.AddEvent(MouseEv(evMouseMove, 12, 19));
  Root.AddEvent(MouseEv(evMouseUp, 12, 19));
  Ev := MouseEv(evMouseDown, 2, 19);
  Line.HandleEvent(Ev);
  Check((Root.PutCount = 1) and (Root.LastPut.Message.Command = cmMenu), 'the item under the mouse at the end is chosen');

  Root.PutCount := 0;
  Root.AddEvent(MouseEv(evMouseUp, 30, 19));
  Ev := MouseEv(evMouseDown, 30, 19);
  Line.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.PutCount = 0), 'a click beside the items puts nothing');

  Root.PutCount := 0;
  Root.AddEvent(MouseEv(evMouseUp, 2, 19));
  Ev := MouseEv(evMouseDown, 2, 18);
  Line.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.PutCount = 0), 'a click on another row puts nothing');

  Root.PutCount := 0;
  TView.DisableCommand(cmHelp);
  Root.AddEvent(MouseEv(evMouseUp, 2, 19));
  Ev := MouseEv(evMouseDown, 2, 19);
  Line.HandleEvent(Ev);
  TView.EnableCommand(cmHelp);
  Check((Ev.What = evNothing) and (Root.PutCount = 0), 'a click on an item of a disabled command puts nothing');

  { The help context }
  V := TView.Create(Rc(0, 0, 1, 1));
  V.HelpCtx := 7;
  TheTopView := V;
  Before := Line.DrawCount;
  Line.Update;
  Check(Line.HelpCtx = 7, 'Update takes the help context of the top view');
  Check(TStatusCrack(Line).ItemList = SI3, 'Update takes the items of the definition for the context');
  Check(Line.DrawCount = Before + 1, 'Update draws the status line when the context changed');
  Check(RowText(19, 0, 12) = ' Alt-X Exit ', 'the status line draws the items of the new definition');
  Line.Update;
  Check(Line.DrawCount = Before + 1, 'Update does not draw the status line when the context is the same');
  V.HelpCtx := 20;
  Line.Update;
  Check(TStatusCrack(Line).ItemList = nil, 'a context that no definition has gives no items');
  TheTopView := nil;
  Line.Update;
  Check((Line.HelpCtx = hcNoContext) and (TStatusCrack(Line).ItemList = SI1), 'without a top view the context is none');
  V.Free;

  { A line too narrow for the second item. }
  ClearScreen;
  Narrow := TCountStatus.Create(Rc(0, 18, 10, 19), TStatusDef.Create(0, 0, TStatusItem.Create('~F1~ Help', TKey.Create(kbF1), cmHelp,
    TStatusItem.Create('~F10~ Menu', TKey.Create(kbF10), cmMenu))));
  Root.Insert(Narrow);
  Narrow.DrawView;
  Check(RowText(18, 0, 10) = ' F1 Help  ', 'an item that does not fit in the status line is not drawn');
  Check(CharAt(10, 18) = #0, 'the status line writes only its own width');
  TvObject.DestroyObject(Narrow);

  Plain := TStatusLine.Create(Rc(0, 17, ScrW, 18), TStatusDef.Create(0, 0, TStatusItem.Create('~Q~uit', TKey.Create(kbNoKey), cmQuit)));
  Root.Insert(Plain);
  Plain.DrawView;
  Check(RowText(17, 0, 8) = ' Quit   ', 'a plain status line draws its items and no hint');
  Check(Plain.Hint(5) = '', 'the hint of a status line is empty');
  TvObject.DestroyObject(Plain);

  StatusItemFreed := 0;
  TvObject.DestroyObject(Line);
  Check(StatusItemFreed = 3, 'freeing a status line frees the items of all its definitions');
  FreeRoot(Root);
end;

procedure TestTables;
begin
  Check(TMenuBox.FrameChars = ' '#$DA#$C4#$BF'  '#$C0#$C4#$D9'  '#$B3' '#$B3'  '#$C3#$C4#$B4' ',
    'the frame characters of a menu box have their initial value');
  Check(Length(TMenuBox.FrameChars) = 20, 'the frame characters are four groups of five');
  Check(TStatusLine.HintSeparator = #$B3' ', 'the hint separator has its initial value');
  Check(Length(TStatusLine.HintSeparator) = 2, 'the hint separator is two characters');
  { The drawing tests below use a table of letters, so that each position can be told apart. }
  TMenuBox.FrameChars := 'abcdefghijklmnopqrst';
  TStatusLine.HintSeparator := '| ';
end;

procedure TestThreads;
var
  Root: TRoot;
  Box: TMenuBox;
  M: TMenu;
  T: TPoster;
  Start: Int64;
  R: Word;

  procedure MakeBox;
  begin
    M := TMenu.Create(TMenuItem.Create('~N~ew', cmNew, TKey.Create(kbF4)));
    Box := TMenuBox.Create(Rc(5, 3, 25, 13), M, nil);
  end;

  procedure FreeBox;
  begin
    TvObject.DestroyObject(Box);
    M.Free;
  end;

begin
  Root := NewRoot;
  Root.CancelWhenDry := False;
  Root.UseQueue := True;
  Root.Deadline := Now64 + 25000;
  MakeBox;
  T := TPoster.Create(0, 250);
  Start := Now64;
  R := Root.ExecView(Box);
  Check(R = 0, 'a menu ends with the command 0 when an event is posted from a second thread');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmOK),
    'an event that is posted from a second thread during ExecView is delivered to the menu');
  Check(Now64 - Start < Guard - 1000, 'the posted event ended the wait');
  Check(Now64 - Start >= 150, 'the loop waited for the posted event');
  T.WaitFor;
  T.Free;
  FreeBox;

  MakeBox;
  Root.PutCount := 0;
  WakeFlag := 0;
  T := TPoster.Create(1, 250);
  Start := Now64;
  R := Root.ExecView(Box);
  Check((R = 0) and (Root.PutCount = 1) and (Root.LastPut.Message.Command = cmOK),
    'a wake-up from a second thread during ExecView ends the wait of the menu');
  Check(Now64 - Start < Guard - 1000, 'the wake-up ended the wait');
  T.WaitFor;
  T.Free;
  FreeBox;

  MakeBox;
  Root.PutCount := 0;
  T := TPoster.Create(0, 0);
  T.WaitFor;
  T.Free;
  Start := Now64;
  R := Root.ExecView(Box);
  Check((R = 0) and (Root.PutCount = 1) and (Now64 - Start < Guard - 1000),
    'an event that was posted before ExecView is delivered at once');
  FreeBox;
  FreeRoot(Root);
end;

var
  EventBackend: TEventBackend;
  Queue: TEventQueue;
  SavedBackend: TScreenBackend;

begin
  RootPal := TPalette.Create([TColorAttr.Create($11), TColorAttr.Create($22), TColorAttr.Create($33),
    TColorAttr.Create($44), TColorAttr.Create($55), TColorAttr.Create($66), TColorAttr.Create($77)]);
  Fake := TFakeDisplay.Create;
  SavedBackend := TDisplay.Backend;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;
  HotKeyStrHook := @TestHotKeyStr;
  ApplicationHook := @TestApp;
  EventBackend := TEventBackend.Create;
  TEventQueue.Backend := EventBackend;
  Queue := TEventQueue.Create;

  TestTables;
  TestItems;
  TestOperators;
  TestDestroy;
  TestBarBasics;
  TestBarRect;
  TestBarDraw;
  TestBoxGeometry;
  TestBoxDraw;
  TestFindAndHotKey;
  TestFindExtended;
  TestHelpCtx;
  TestBarExec;
  TestBoxExec;
  TestHandleEvent;
  TestPopupView;
  TestPopupMenu;
  TestStatusItems;
  TestStatusLine;
  TestThreads;

  Queue.Free;
  TEventQueue.Backend := nil;
  EventBackend.Free;
  HotKeyStrHook := nil;
  ApplicationHook := nil;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  Done;
end.
