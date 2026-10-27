{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (TSItem, TCluster, TRadioButtons, TCheckBoxes, TMultiCheckBoxes and the
  flags cfOneBit to cfEightBits), include/tvision/ttypes.h (specialChars), source/tvision/tcluster.cpp,
  source/tvision/tradiobu.cpp, source/tvision/tcheckbo.cpp, source/tvision/tmulchkb.cpp,
  source/tvision/tvtext1.cpp (the tables button of TRadioButtons and TCheckBoxes)
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it. The
  root reads its events from a script, which a test fills with the mouse events that follow a press of the button.
  The colors of the root are the BIOS attributes 1 to 127: the entry k of its palette is k, so a cluster whose
  palette is 16, 17, 18, 18, 31 draws with the attributes 16 (normal text), 17 (selected text), 18 (shortcut) and 31
  (disabled text). The hook of the hot keys is a function of the test that returns the upper case letter after the
  first tilde of a text. The characters of specialChars are set to letters while the markers are tested, so that the
  cells can be read as text; the values of the C++ are checked first. A test reads the protected members of a
  cluster through a descendant that only exposes them. }
program t_cluster;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Classes, SysUtils, TvGeom, TvKeys, TvEvents, TvSys, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvViews,
  TvWindow, TvUtil, TvDialog, TvCluster;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 20;

type
  TFakeDisplay = class(TScreenBackend)
  public
    CaretSize: Word;
    procedure SetCaretSize(ASize: Word); override;
    function GetCaretSize: Word; override;
  end;

  TRoot = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    function GetPalette: TPalette; override;
  end;

  { A selectable view that refuses to give up the focus. }
  TBlocker = class(TView)
  public
    procedure Draw; override;
    function Valid(Command: Word): Boolean; override;
  end;

  { Exposes the protected members of a cluster; it is used only to cast a cluster. }
  TPeek = class(TCluster)
  public
    function GetValue: Cardinal;
    function GetSel: Integer;
    function GetMask: Cardinal;
    function GetCount: Integer;
    function GetString(Index: Integer): string;
    procedure PutSel(Index: Integer);
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  GetCalls: Integer;
  RootPal: TPalette;

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

function TestHotKey(const Text: string): Char;
var
  position: Integer;
begin
  Result := #0;
  for position := 1 to Length(Text) - 1 do
    if Text[position] = '~' then
    begin
      Result := UpCase(Text[position + 1]);
      Exit;
    end;
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

{ A key event for the character Ch, whose scan code is Scan. }
function CharKeyEv(Ch: Char; Scan: Byte): TEvent;
begin
  Result := KeyEv(Word(Ord(Ch) or (Scan shl 8)));
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
  cellText: string;
begin
  cellText := ScreenCells[Y * ScrW + X].Character.GetText;
  if Length(cellText) > 0 then
    Result := cellText[1]
  else
    Result := #0;
end;

function AttrAt(X, Y: Integer): Integer;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute.ToBIOS;
end;

function RowText(Y, X0, N: Integer): string;
var
  offset: Integer;
begin
  Result := '';
  for offset := 0 to N - 1 do
    Result := Result + CharAt(X0 + offset, Y);
end;

procedure ClearScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
end;

{ The number of the entry I of a palette. }
function PalByte(P: TPalette; I: Integer): Integer;
var
  entry: TColorAttr;
begin
  entry := P.Items[I];
  Result := entry.ToBIOS;
end;

{ The list of strings that holds Names in their order. }
function ItemList(const Names: array of string): TSItem;
var
  position: Integer;
begin
  Result := nil;
  for position := High(Names) downto Low(Names) do
    Result := TSItem.Create(Names[position], Result);
end;

{ A list of Count strings. }
function CountedList(Count: Integer): TSItem;
var
  position: Integer;
begin
  Result := nil;
  for position := Count downto 1 do
    Result := TSItem.Create('I' + IntToStr(position), Result);
end;

{ The views of the tests. }

procedure TBlocker.Draw;
begin
end;

function TBlocker.Valid(Command: Word): Boolean;
begin
  Result := False;
end;

function TPeek.GetValue: Cardinal;
begin
  Result := Value;
end;

function TPeek.GetSel: Integer;
begin
  Result := Sel;
end;

function TPeek.GetMask: Cardinal;
begin
  Result := EnableMask;
end;

function TPeek.GetCount: Integer;
begin
  Result := Strings.GetCount;
end;

function TPeek.GetString(Index: Integer): string;
begin
  Result := StrPas(PAnsiChar(Strings.At(Index)));
end;

procedure TPeek.PutSel(Index: Integer);
begin
  Sel := Index;
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

{ Gives View the event Ev, and tells whether the view cleared it. }
function SendEvent(View: TView; Ev: TEvent): Boolean;
begin
  View.HandleEvent(Ev);
  Result := Ev.What = evNothing;
end;

function SendKey(View: TView; Code: Word): Boolean;
begin
  Result := SendEvent(View, KeyEv(Code));
end;

procedure Focused(View: TView; Enable: Boolean);
begin
  if Enable then
    View.State := View.State or sfFocused
  else
    View.State := View.State and not sfFocused;
end;

procedure Selected(View: TView; Enable: Boolean);
begin
  if Enable then
    View.State := View.State or sfSelected
  else
    View.State := View.State and not sfSelected;
end;

{ ---- the tests ---- }

procedure TestTables;
begin
  Check((cfOneBit = $0101) and (cfTwoBits = $0203) and (cfFourBits = $040F) and (cfEightBits = $08FF),
    'the flags of the multi state check boxes');
  Check((SpecialChars[0] = 175) and (SpecialChars[1] = 174), 'the characters that mark the selected button');
  Check(TRadioButtons.Button = ' ( ) ', 'the icon of a radio button');
  Check(TCheckBoxes.Button = ' [ ] ', 'the icon of a check box');
end;

procedure TestSItem;
var
  head: TSItem;
  text: string;
  single: TSItem;
begin
  head := TSItem.Create('First', TSItem.Create('Second', nil));
  Check(StrPas(head.Value) = 'First', 'an item keeps its text');
  Check((head.Next <> nil) and (StrPas(head.Next.Value) = 'Second'), 'an item keeps the next item');
  Check(head.Next.Next = nil, 'the last item has no next item');
  head.Next.Free;
  head.Free;

  text := 'abc';
  single := TSItem.Create(text, nil);
  text[1] := 'X';
  Check(StrPas(single.Value) = 'abc', 'an item keeps a copy of its text');
  single.Free;
end;

procedure TestConstruction;
var
  Root: TRoot;
  Boxes: TCheckBoxes;
  Empty: TCheckBoxes;
begin
  Root := NewRoot;
  Boxes := TCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['Alpha', 'Beta', 'Gamma']));
  Check(Boxes.Options = (ofSelectable or ofFirstClick or ofPreProcess or ofPostProcess),
    'a cluster is selectable, takes the first click and sees the events before and after');
  Check((TPeek(Boxes).GetValue = 0) and (TPeek(Boxes).GetSel = 0), 'a cluster starts with the value 0 and the item 0');
  Check(TPeek(Boxes).GetMask = $FFFFFFFF, 'every button of a cluster is enabled at the start');
  Check(TPeek(Boxes).GetCount = 3, 'the cluster has a string for each item of the list');
  Check((TPeek(Boxes).GetString(0) = 'Alpha') and (TPeek(Boxes).GetString(1) = 'Beta') and
    (TPeek(Boxes).GetString(2) = 'Gamma'), 'the strings keep the order of the list');
  Check((Boxes.Cursor.X = 2) and (Boxes.Cursor.Y = 0), 'the cursor of a cluster starts in the third cell');
  Check((Boxes.State and sfCursorVis) <> 0, 'the cursor of a cluster is shown');
  Check(Boxes.DataSize = 2, 'the data of a cluster is a Word');
  Check(Boxes.GetBounds = Rc(0, 0, 20, 3), 'the bounds of a cluster');
  Check((PalByte(Boxes.GetPalette, 0) = 5) and (PalByte(Boxes.GetPalette, 1) = 16) and
    (PalByte(Boxes.GetPalette, 2) = 17) and (PalByte(Boxes.GetPalette, 3) = 18) and
    (PalByte(Boxes.GetPalette, 4) = 18) and (PalByte(Boxes.GetPalette, 5) = 31), 'the palette of a cluster');
  Empty := TCheckBoxes.Create(Rc(0, 0, 20, 3), nil);
  Check(TPeek(Empty).GetCount = 0, 'a cluster made from an empty list has no strings');
  Check(Boxes.GetPalette = Empty.GetPalette, 'all clusters share their palette');
  Empty.Free;
  Boxes.Free;
  FreeRoot(Root);
end;

procedure TestEnableMask;
var
  Boxes: TCheckBoxes;
  Wide: TCheckBoxes;
  Edge: TCheckBoxes;
begin
  Boxes := TCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['a', 'b', 'c']));
  Check(Boxes.ButtonState(0) and Boxes.ButtonState(1) and Boxes.ButtonState(2), 'the buttons start enabled');
  Check(Boxes.ButtonState(31), 'the bit 31 of the mask is set at the start');
  Check((not Boxes.ButtonState(32)) and (not Boxes.ButtonState(100)), 'an item from 32 on is never enabled');
  Check(not Boxes.ButtonState(-1), 'a negative item is not enabled');

  Boxes.SetButtonState(2, False);
  Check(TPeek(Boxes).GetMask = $FFFFFFFD, 'a button is disabled by clearing its bit');
  Check((not Boxes.ButtonState(1)) and Boxes.ButtonState(0) and Boxes.ButtonState(2), 'only that button is disabled');
  Check((Boxes.Options and ofSelectable) <> 0, 'the cluster stays selectable while a button is enabled');

  Boxes.SetButtonState(5, False);
  Check((Boxes.Options and ofSelectable) = 0, 'the cluster is not selectable when all its buttons are disabled');
  Boxes.SetButtonState(4, True);
  Check(Boxes.ButtonState(2) and ((Boxes.Options and ofSelectable) <> 0),
    'enabling a button makes the cluster selectable again');
  Boxes.Free;

  Wide := TCheckBoxes.Create(Rc(0, 0, 30, 2), CountedList(32));
  Wide.SetButtonState($FFFFFFFF, False);
  Check((TPeek(Wide).GetMask = 0) and ((Wide.Options and ofSelectable) <> 0),
    'a cluster of 32 strings stays selectable when every button is disabled');
  Wide.Free;

  Edge := TCheckBoxes.Create(Rc(0, 0, 30, 2), CountedList(31));
  Edge.SetButtonState($7FFFFFFF, False);
  Check((TPeek(Edge).GetMask = $80000000) and ((Edge.Options and ofSelectable) = 0),
    'a cluster of 31 strings looks at its 31 bits only');
  Edge.Free;
end;

procedure TestMarkAndPress;
var
  Plain: TPeek;
  Boxes: TCheckBoxes;
  Radio: TRadioButtons;
begin
  Plain := TPeek(TCluster.Create(Rc(0, 0, 20, 3), ItemList(['a', 'b', 'c'])));
  Check(not Plain.Mark(0), 'a plain cluster marks nothing');
  Check(Plain.MultiMark(0) = 0, 'the multi mark of a plain cluster is 0');
  Plain.Press(1);
  Plain.MovedTo(1);
  Check((Plain.GetValue = 0) and (Plain.GetSel = 0), 'a plain cluster does not react to a press or a move');
  Plain.Free;

  Boxes := TCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['a', 'b', 'c']));
  Boxes.Press(0);
  Check(TPeek(Boxes).GetValue = 1, 'pressing the check box 0 sets bit 0');
  Boxes.Press(2);
  Check(TPeek(Boxes).GetValue = 5, 'pressing the check box 2 sets bit 2');
  Check(Boxes.Mark(0) and Boxes.Mark(2) and (not Boxes.Mark(1)), 'a check box is marked when its bit is set');
  Check((Boxes.MultiMark(2) = 1) and (Boxes.MultiMark(1) = 0), 'the multi mark of a check box is 1 or 0');
  Boxes.Press(0);
  Check(TPeek(Boxes).GetValue = 4, 'pressing a marked check box clears its bit');
  Boxes.Press(31);
  Check(TPeek(Boxes).GetValue = $80000004, 'the check box 31 is the highest bit');
  Check(Boxes.Mark(31), 'the check box 31 is marked');
  Boxes.Free;

  Radio := TRadioButtons.Create(Rc(0, 0, 20, 3), ItemList(['a', 'b', 'c']));
  Check(Radio.Mark(0) and (not Radio.Mark(1)), 'the radio button of the value is marked');
  Radio.Press(2);
  Check((TPeek(Radio).GetValue = 2) and Radio.Mark(2) and (not Radio.Mark(0)), 'pressing a radio button chooses it');
  Radio.MovedTo(1);
  Check((TPeek(Radio).GetValue = 1) and Radio.Mark(1), 'moving to a radio button chooses it');
  Check(Radio.MultiMark(1) = 1, 'the multi mark of a marked radio button is 1');
  Check(TPeek(Radio).GetSel = 0, 'pressing and moving do not change the selected item by themselves');
  Radio.Free;
end;

procedure TestMultiState;
var
  Multi: TMultiCheckBoxes;
  Eight: TMultiCheckBoxes;
  One: TMultiCheckBoxes;
  Four: TMultiCheckBoxes;
  Data: LongWord;
begin
  Multi := TMultiCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['a', 'b', 'c']), 3, cfTwoBits, ' -+');
  Check(Multi.DataSize = 4, 'the data of the multi state check boxes is a LongWord');
  Multi.Press(1);
  Check((TPeek(Multi).GetValue = 4) and (Multi.MultiMark(1) = 1), 'the first press sets the field 1 to 1');
  Check((Multi.MultiMark(0) = 0) and (Multi.MultiMark(2) = 0), 'the other fields stay 0');
  Multi.Press(1);
  Check((TPeek(Multi).GetValue = 8) and (Multi.MultiMark(1) = 2), 'the second press sets the field to 2');
  Multi.Press(1);
  Check((TPeek(Multi).GetValue = 0) and (Multi.MultiMark(1) = 0), 'a field that reaches the range returns to 0');
  Multi.Press(2);
  Multi.Press(0);
  Check(TPeek(Multi).GetValue = 17, 'the fields 0 and 2 are 2 bits and 4 bits up');
  Multi.Press(0);
  Check(TPeek(Multi).GetValue = 18, 'a press changes only its own field');
  Data := $FFFFFFFF;
  Multi.SetData(@Data);
  Check((Multi.MultiMark(1) = 3) and (Multi.MultiMark(0) = 3), 'a field may hold a state beyond the range');
  Multi.Press(0);
  Check(TPeek(Multi).GetValue = $FFFFFFFC, 'a state beyond the range returns to 0');
  Multi.Free;

  Eight := TMultiCheckBoxes.Create(Rc(0, 0, 20, 4), ItemList(['a', 'b', 'c', 'd']), 255, cfEightBits, ' xyz');
  Data := $12345678;
  Eight.SetData(@Data);
  Check((Eight.MultiMark(0) = $78) and (Eight.MultiMark(1) = $56) and (Eight.MultiMark(2) = $34) and
    (Eight.MultiMark(3) = $12), 'a field of 8 bits is a byte of the value');
  Eight.Press(3);
  Check(TPeek(Eight).GetValue = $13345678, 'a press of the field 3 changes the top byte');
  Data := $FF345678;
  Eight.SetData(@Data);
  Eight.Press(3);
  Check(TPeek(Eight).GetValue = $00345678, 'a field that reaches the range of 255 returns to 0');
  Eight.Free;

  One := TMultiCheckBoxes.Create(Rc(0, 0, 20, 2), ItemList(['a', 'b']), 2, cfOneBit, ' X');
  One.Press(5);
  Check((TPeek(One).GetValue = 32) and (One.MultiMark(5) = 1), 'a field of 1 bit is one bit of the value');
  One.Press(5);
  Check(TPeek(One).GetValue = 0, 'the field of 1 bit with the range 2 toggles');
  One.Free;

  Four := TMultiCheckBoxes.Create(Rc(0, 0, 20, 2), ItemList(['a', 'b']), 16, cfFourBits, ' 123456789abcdef');
  Data := $F0000000;
  Four.SetData(@Data);
  Check(Four.MultiMark(7) = 15, 'the field 7 of 4 bits is the top nibble');
  Four.Press(7);
  Check(TPeek(Four).GetValue = 0, 'the top nibble returns to 0 at the range 16');
  Four.Free;
end;

procedure TestData;
var
  Root: TRoot;
  Radio: TRadioButtons;
  Boxes: TCheckBoxes;
  Multi: TMultiCheckBoxes;
  Bytes: array[0..7] of Byte;
  Data16: Word;
  Data32: LongWord;
begin
  Root := NewRoot;
  Radio := TRadioButtons.Create(Rc(0, 0, 10, 3), ItemList(['a', 'b', 'c']));
  Root.Insert(Radio);
  Data16 := 2;
  Radio.SetData(@Data16);
  Check((TPeek(Radio).GetValue = 2) and (TPeek(Radio).GetSel = 2), 'SetData of radio buttons sets the value and the selection');
  FillChar(Bytes, SizeOf(Bytes), $FF);
  Radio.GetData(@Bytes[0]);
  Check(PWord(@Bytes[0])^ = 2, 'GetData gives the value as a Word');
  Check((Bytes[2] = $FF) and (Bytes[3] = $FF), 'GetData writes two bytes only');

  Boxes := TCheckBoxes.Create(Rc(10, 0, 20, 3), ItemList(['a', 'b', 'c']));
  Root.Insert(Boxes);
  ClearScreen;
  Data16 := $FFFF;
  Boxes.SetData(@Data16);
  Check(TPeek(Boxes).GetValue = $FFFF, 'SetData of check boxes sets the value');
  Check(TPeek(Boxes).GetSel = 0, 'SetData of check boxes keeps the selection');
  Check(CharAt(11, 0) = '[', 'SetData draws the view');
  Boxes.Press(20);
  Check(TPeek(Boxes).GetValue = $10FFFF, 'the value of a cluster has 32 bits');
  FillChar(Bytes, SizeOf(Bytes), 0);
  ClearScreen;
  Boxes.GetData(@Bytes[0]);
  Check(PWord(@Bytes[0])^ = $FFFF, 'GetData gives the low 16 bits of the value');
  Check(CharAt(11, 0) = '[', 'GetData draws the view');

  Multi := TMultiCheckBoxes.Create(Rc(20, 0, 30, 2), ItemList(['a', 'b']), 3, cfTwoBits, ' -+');
  Root.Insert(Multi);
  Data32 := $12345678;
  Multi.SetData(@Data32);
  Check(TPeek(Multi).GetValue = $12345678, 'SetData of the multi state check boxes sets all 32 bits');
  FillChar(Bytes, SizeOf(Bytes), $FF);
  Multi.GetData(@Bytes[0]);
  Check(PLongWord(@Bytes[0])^ = $12345678, 'GetData of the multi state check boxes gives a LongWord');
  Check(Bytes[4] = $FF, 'GetData of the multi state check boxes writes four bytes only');
  FreeRoot(Root);
end;

procedure TestHelpCtx;
var
  Boxes: TCheckBoxes;
begin
  Boxes := TCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['a', 'b', 'c']));
  TPeek(Boxes).PutSel(2);
  Check(Boxes.GetHelpCtx = hcNoContext, 'no help context stays no help context');
  Boxes.HelpCtx := 100;
  Check(Boxes.GetHelpCtx = 102, 'the help context grows by the selected item');
  TPeek(Boxes).PutSel(0);
  Check(Boxes.GetHelpCtx = 100, 'the help context of the item 0');
  Boxes.Free;
end;

{ Shows a cluster in a new root, unselected, and draws it on a clean screen. }
procedure ShowCluster(out Root: TRoot; Cl: TCluster);
begin
  Root := NewRoot;
  Root.Insert(Cl);
  Selected(Cl, False);
  ClearScreen;
  Cl.DrawView;
end;

procedure TestDrawLayout;
var
  Root: TRoot;
  Boxes: TCheckBoxes;
begin
  Boxes := TCheckBoxes.Create(Rc(0, 0, 40, 3), ItemList(['ab', 'abcd', 'abc', 'x', 'yy', 'zzzz', 'q']));
  ShowCluster(Root, Boxes);
  Check(RowText(0, 0, 26) = ' [ ] ' + 'ab' + '   ' + ' [ ] ' + 'x' + '    ' + ' [ ] ' + 'q',
    'the first row holds the items 0, 3 and 6, in columns 0, 10 and 20');
  Check(RowText(1, 0, 26) = ' [ ] ' + 'abcd' + ' ' + ' [ ] ' + 'yy' + '   ' + '      ',
    'the second row holds the items 1 and 4');
  Check(RowText(2, 0, 26) = ' [ ] ' + 'abc' + '  ' + ' [ ] ' + 'zzzz' + ' ' + '      ',
    'the third row holds the items 2 and 5');
  Check((CharAt(39, 0) = ' ') and (CharAt(39, 2) = ' '), 'the rest of a row is blank');
  Check(CharAt(0, 3) = #0, 'the row below the view is not written');
  Check((AttrAt(0, 0) = 16) and (AttrAt(5, 0) = 16) and (AttrAt(39, 2) = 16), 'an unselected cluster has the normal color');
  FreeRoot(Root);
end;

procedure TestDrawStates;
var
  Root: TRoot;
  Boxes: TCheckBoxes;
begin
  Boxes := TCheckBoxes.Create(Rc(0, 0, 40, 3), ItemList(['ab', 'abcd', 'abc', 'x', 'yy', 'zzzz', 'q']));
  ShowCluster(Root, Boxes);
  Selected(Boxes, True);
  Boxes.DrawView;
  Check((AttrAt(0, 0) = 17) and (AttrAt(5, 0) = 17) and (AttrAt(9, 0) = 17),
    'the selected item of a selected cluster has the selected color');
  Check((AttrAt(10, 0) = 16) and (AttrAt(39, 0) = 16) and (AttrAt(0, 1) = 16),
    'the other items keep the normal color');

  Selected(Boxes, False);
  Boxes.DrawView;
  Check((AttrAt(0, 0) = 16) and (AttrAt(9, 0) = 16), 'the item of a cluster that is not selected has the normal color');

  Selected(Boxes, True);
  Boxes.SetButtonState(2, False);
  Boxes.DrawView;
  Check((AttrAt(0, 1) = 31) and (AttrAt(5, 1) = 31) and (AttrAt(9, 1) = 31),
    'a disabled item has the disabled color');
  Check((AttrAt(10, 1) = 16) and (AttrAt(0, 0) = 17), 'the items beside a disabled item keep their colors');

  Boxes.SetButtonState(1, False);
  Boxes.DrawView;
  Check(AttrAt(0, 0) = 31, 'a disabled item is not drawn as selected');
  FreeRoot(Root);

  Boxes := TCheckBoxes.Create(Rc(0, 0, 10, 1), ItemList(['~O~ne']));
  ShowCluster(Root, Boxes);
  Check(RowText(0, 0, 8) = ' [ ] One', 'the tildes of a text are not drawn');
  Check((AttrAt(5, 0) = 18) and (AttrAt(6, 0) = 16) and (AttrAt(7, 0) = 16), 'the shortcut has its own color');
  Selected(Boxes, True);
  Boxes.DrawView;
  Check((AttrAt(5, 0) = 18) and (AttrAt(6, 0) = 17) and (AttrAt(0, 0) = 17),
    'the shortcut of a selected item keeps the shortcut color');
  FreeRoot(Root);
end;

procedure TestDrawKinds;
var
  Root: TRoot;
  Radio: TRadioButtons;
  Boxes: TCheckBoxes;
  Multi: TMultiCheckBoxes;
begin
  Radio := TRadioButtons.Create(Rc(0, 0, 12, 2), ItemList(['Red', 'Green']));
  ShowCluster(Root, Radio);
  Check((CharAt(1, 0) = '(') and (CharAt(3, 0) = ')') and (RowText(0, 3, 9) = ') Red    '),
    'a radio button is drawn with the icon of radio buttons');
  Check((CharAt(2, 0) <> ' ') and (CharAt(2, 0) <> #0), 'the radio button of the value has a mark');
  Check((CharAt(2, 1) = ' ') and (RowText(1, 3, 9) = ') Green  '), 'the other radio button has no mark');
  Radio.Press(1);
  Radio.DrawView;
  Check((CharAt(2, 0) = ' ') and (CharAt(2, 1) <> ' ') and (CharAt(2, 1) <> #0),
    'the mark follows the value of the radio buttons');
  FreeRoot(Root);

  Boxes := TCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['One', 'Two', 'Three']));
  ShowCluster(Root, Boxes);
  Boxes.Press(0);
  Boxes.Press(2);
  Boxes.DrawView;
  Check((CharAt(2, 0) = 'X') and (CharAt(2, 1) = ' ') and (CharAt(2, 2) = 'X'), 'a marked check box shows an X');
  Check(RowText(0, 0, 9) = ' [X] One ','the first check box is drawn as marked');
  ClearScreen;
  Boxes.DrawBox(' < > ', '#');
  Check(RowText(0, 0, 9) = ' <#> One ', 'DrawBox draws the marker of a marked item');
  Check(RowText(1, 0, 9) = ' < > Two ', 'DrawBox draws a blank for an unmarked item');
  FreeRoot(Root);

  Multi := TMultiCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['One', 'Two', 'Three']), 3, cfTwoBits, ' -+');
  ShowCluster(Root, Multi);
  Multi.Press(0);
  Multi.Press(1);
  Multi.Press(1);
  Multi.DrawView;
  Check((CharAt(2, 0) = '-') and (CharAt(2, 1) = '+') and (CharAt(2, 2) = ' '),
    'the multi state check boxes draw the character of their state');
  Check((RowText(0, 0, 9) = ' [-] One ') and (RowText(2, 0, 9) = ' [ ] Thre'), 'the icon of the multi state check boxes');
  FreeRoot(Root);
end;

procedure TestMarkersAndCursor;
var
  Root: TRoot;
  Boxes: TCheckBoxes;
begin
  Boxes := TCheckBoxes.Create(Rc(0, 0, 40, 3), ItemList(['ab', 'abcd', 'abc', 'x', 'yy', 'zzzz', 'q']));
  ShowCluster(Root, Boxes);
  Check((Boxes.Cursor.X = 2) and (Boxes.Cursor.Y = 0), 'the cursor is in the third cell of the selected item 0');
  TPeek(Boxes).PutSel(4);
  Boxes.DrawView;
  Check((Boxes.Cursor.X = 12) and (Boxes.Cursor.Y = 1), 'the cursor follows the selected item 4');
  TPeek(Boxes).PutSel(6);
  Boxes.DrawView;
  Check((Boxes.Cursor.X = 22) and (Boxes.Cursor.Y = 0), 'the cursor follows the selected item 6');

  SpecialChars[0] := Ord('<');
  SpecialChars[1] := Ord('>');
  TView.ShowMarkers := False;
  Selected(Boxes, True);
  TPeek(Boxes).PutSel(0);
  ClearScreen;
  Boxes.DrawView;
  Check(RowText(0, 0, 10) = ' [ ] ab   ', 'no marker is drawn while the markers are off');

  TView.ShowMarkers := True;
  ClearScreen;
  Boxes.DrawView;
  Check(RowText(0, 0, 10) = '<[ ] ab  >', 'the markers surround the selected item 0');
  Check(CharAt(10, 0) = ' ', 'the marker does not go into the next column');
  TPeek(Boxes).PutSel(3);
  ClearScreen;
  Boxes.DrawView;
  Check(RowText(0, 10, 10) = '<[ ] x   >', 'the markers surround the selected item 3');
  TPeek(Boxes).PutSel(6);
  ClearScreen;
  Boxes.DrawView;
  Check(RowText(0, 20, 7) = '<[ ] q>', 'the closing marker of the last column is left of the column after it');

  Selected(Boxes, False);
  ClearScreen;
  Boxes.DrawView;
  Check((CharAt(20, 0) = ' ') and (CharAt(26, 0) = ' '), 'a cluster that is not selected has no markers');
  TView.ShowMarkers := False;
  SpecialChars[0] := 175;
  SpecialChars[1] := 174;
  FreeRoot(Root);
end;

procedure TestArrowKeys;
var
  Root: TRoot;
  Radio: TRadioButtons;
  Boxes: TCheckBoxes;
  Wide: TCheckBoxes;
  Cleared: Boolean;
begin
  Root := NewRoot;
  Radio := TRadioButtons.Create(Rc(0, 0, 20, 4), ItemList(['One', 'Two', 'Three', 'Four']));
  Root.Insert(Radio);
  Focused(Radio, True);

  Cleared := SendKey(Radio, kbDown);
  Check(Cleared and (TPeek(Radio).GetSel = 1) and (TPeek(Radio).GetValue = 1), 'Down moves to the next radio button');
  SendKey(Radio, kbDown);
  SendKey(Radio, kbDown);
  Check(TPeek(Radio).GetSel = 3, 'Down moves on to the last radio button');
  SendKey(Radio, kbDown);
  Check((TPeek(Radio).GetSel = 0) and (TPeek(Radio).GetValue = 0), 'Down wraps around to the first radio button');
  SendKey(Radio, kbUp);
  Check((TPeek(Radio).GetSel = 3) and (TPeek(Radio).GetValue = 3), 'Up wraps around to the last radio button');
  SendKey(Radio, kbLeft);
  Check(TPeek(Radio).GetSel = 2, 'Left from the last button of one column goes to the one before it');
  SendKey(Radio, kbLeft);
  Check(TPeek(Radio).GetSel = 1, 'Left from the button 2 of one column goes to the button 1');
  SendKey(Radio, kbLeft);
  Check(TPeek(Radio).GetSel = 0, 'Left from the button 1 of one column goes to the button 0');
  Cleared := SendKey(Radio, kbLeft);
  Check(Cleared and (TPeek(Radio).GetSel = 3), 'Left from the first button goes to the last one');
  Cleared := SendKey(Radio, kbRight);
  Check(Cleared and (TPeek(Radio).GetSel = 0), 'Right from the last button of one column wraps to the first one');
  Cleared := SendKey(Radio, kbRight);
  Check(Cleared and (TPeek(Radio).GetSel = 0), 'Right in one column stays on the first button');
  Cleared := SendKey(Radio, kbCtrlX);
  Check(Cleared and (TPeek(Radio).GetSel = 1), 'Ctrl+X acts as Down');
  Cleared := SendKey(Radio, kbCtrlE);
  Check(Cleared and (TPeek(Radio).GetSel = 0), 'Ctrl+E acts as Up');

  Focused(Radio, False);
  Cleared := SendKey(Radio, kbDown);
  Check((not Cleared) and (TPeek(Radio).GetSel = 0), 'an arrow key does nothing while the cluster is not focused');
  Focused(Radio, True);

  Radio.SetButtonState(2, False);
  SendKey(Radio, kbDown);
  Check(TPeek(Radio).GetSel = 2, 'Down skips a disabled button');
  TPeek(Radio).PutSel(0);
  Radio.SetButtonState(8, False);
  SendKey(Radio, kbUp);
  Check(TPeek(Radio).GetSel = 2, 'Up skips a disabled button');
  FreeRoot(Root);

  Root := NewRoot;
  Boxes := TCheckBoxes.Create(Rc(0, 0, 40, 3), ItemList(['ab', 'abcd', 'abc', 'x', 'yy', 'zzzz', 'q']));
  Root.Insert(Boxes);
  Focused(Boxes, True);
  SendKey(Boxes, kbRight);
  Check(TPeek(Boxes).GetSel = 3, 'Right moves one column to the right');
  SendKey(Boxes, kbRight);
  Check(TPeek(Boxes).GetSel = 6, 'Right moves to the last column');
  SendKey(Boxes, kbRight);
  Check(TPeek(Boxes).GetSel = 0, 'Right from the last column wraps to the item 0');
  TPeek(Boxes).PutSel(4);
  SendKey(Boxes, kbRight);
  Check(TPeek(Boxes).GetSel = 0, 'Right past the last item goes to the item 0, not to the same row');
  SendKey(Boxes, kbLeft);
  Check(TPeek(Boxes).GetSel = 6, 'Left from the item 0 goes to the last item');
  SendKey(Boxes, kbLeft);
  Check(TPeek(Boxes).GetSel = 3, 'Left moves one column to the left');
  SendKey(Boxes, kbLeft);
  Check(TPeek(Boxes).GetSel = 0, 'Left from the column 1 reaches the item 0');
  TPeek(Boxes).PutSel(1);
  SendKey(Boxes, kbLeft);
  Check(TPeek(Boxes).GetSel = 6, 'Left from the item 1 wraps to the last row of the last column');
  TPeek(Boxes).PutSel(2);
  SendKey(Boxes, kbLeft);
  Check(TPeek(Boxes).GetSel = 6, 'Left from the item 2 wraps to the last item');
  SendKey(Boxes, kbDown);
  Check(TPeek(Boxes).GetSel = 0, 'Down from the last item goes to the item 0');
  SendKey(Boxes, kbUp);
  Check(TPeek(Boxes).GetSel = 6, 'Up from the item 0 goes to the last item');
  FreeRoot(Root);

  Root := NewRoot;
  Wide := TCheckBoxes.Create(Rc(0, 0, 30, 2), CountedList(32));
  Root.Insert(Wide);
  Focused(Wide, True);
  Wide.SetButtonState($FFFFFFFF, False);
  Cleared := SendKey(Wide, kbDown);
  Check(Cleared and (TPeek(Wide).GetSel = 0), 'with no button enabled the selection stays and the key is used');
  Wide.SetButtonState($100000, True);
  Cleared := SendKey(Wide, kbDown);
  Check(Cleared and (TPeek(Wide).GetSel = 20), 'Down goes to the only enabled button');
  FreeRoot(Root);
end;

procedure TestHotKeys;
var
  Root: TRoot;
  Radio: TRadioButtons;
  Blocker: TBlocker;
  Cleared: Boolean;
begin
  Root := NewRoot;
  Radio := TRadioButtons.Create(Rc(0, 0, 20, 4), ItemList(['~O~ne', '~T~wo', 'Th~r~ee', '~F~our']));
  Root.Insert(Radio);
  Selected(Radio, True);

  Cleared := SendKey(Radio, kbAltT);
  Check(Cleared and (TPeek(Radio).GetSel = 1) and (TPeek(Radio).GetValue = 1),
    'the Alt key of a hot key presses its button');
  Cleared := SendEvent(Radio, CharKeyEv('r', $13));
  Check((not Cleared) and (TPeek(Radio).GetSel = 1), 'a letter is ignored while the cluster is not focused');
  Root.Phase := phPostProcess;
  Cleared := SendEvent(Radio, CharKeyEv('r', $13));
  Check(Cleared and (TPeek(Radio).GetSel = 2) and (TPeek(Radio).GetValue = 2),
    'a letter presses its button in the post process phase');
  Cleared := SendEvent(Radio, CharKeyEv('F', $21));
  Check(Cleared and (TPeek(Radio).GetSel = 3), 'an upper case letter presses its button');
  Cleared := SendEvent(Radio, CharKeyEv('z', $2C));
  Check((not Cleared) and (TPeek(Radio).GetSel = 3), 'a letter that is no hot key is left alone');
  Root.Phase := phFocused;
  Focused(Radio, True);
  Cleared := SendEvent(Radio, CharKeyEv('o', $18));
  Check(Cleared and (TPeek(Radio).GetSel = 0) and (TPeek(Radio).GetValue = 0),
    'a letter presses its button while the cluster is focused');

  Radio.SetButtonState(2, False);
  Cleared := SendKey(Radio, kbAltT);
  Check((not Cleared) and (TPeek(Radio).GetSel = 0), 'the hot key of a disabled button does nothing and is not used');
  Cleared := SendEvent(Radio, CharKeyEv('t', $14));
  Check((not Cleared) and (TPeek(Radio).GetSel = 0), 'the letter of a disabled button does nothing');
  Radio.SetButtonState(2, True);

  HotKeyHook := nil;
  Cleared := SendKey(Radio, kbAltF);
  Check((not Cleared) and (TPeek(Radio).GetSel = 0), 'without the hook no item has a hot key');
  HotKeyHook := @TestHotKey;

  Cleared := SendKey(Radio, 0);
  Check(not Cleared, 'a key event with no code is left alone');
  FreeRoot(Root);

  Root := NewRoot;
  Blocker := TBlocker.Create(Rc(0, 5, 5, 6));
  Blocker.Options := Blocker.Options or ofSelectable or ofValidate;
  Root.Insert(Blocker);
  Radio := TRadioButtons.Create(Rc(0, 0, 20, 4), ItemList(['~O~ne', '~T~wo', 'Th~r~ee', '~F~our']));
  Root.Insert(Radio);
  Root.SetCurrent(Blocker, normalSelect);
  Cleared := SendKey(Radio, kbAltT);
  Check(Cleared and (TPeek(Radio).GetSel = 0) and (TPeek(Radio).GetValue = 0),
    'a hot key does not press a button when the cluster cannot take the focus, and the key is used');
  FreeRoot(Root);
end;

procedure TestSpace;
var
  Root: TRoot;
  Boxes: TCheckBoxes;
  Cleared: Boolean;
begin
  Root := NewRoot;
  Boxes := TCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['One', 'Two', 'Three']));
  Root.Insert(Boxes);
  Focused(Boxes, True);
  TPeek(Boxes).PutSel(1);
  Cleared := SendEvent(Boxes, CharKeyEv(' ', $39));
  Check(Cleared and (TPeek(Boxes).GetValue = 2), 'the space bar presses the selected button');
  Cleared := SendEvent(Boxes, CharKeyEv(' ', $39));
  Check(Cleared and (TPeek(Boxes).GetValue = 0), 'the space bar presses it again');
  Focused(Boxes, False);
  Cleared := SendEvent(Boxes, CharKeyEv(' ', $39));
  Check((not Cleared) and (TPeek(Boxes).GetValue = 0), 'the space bar does nothing while the cluster is not focused');
  FreeRoot(Root);
end;

{ A cluster of seven items, three rows high, in a new root. }
procedure SevenBoxes(out Root: TRoot; out Boxes: TCheckBoxes);
begin
  Root := NewRoot;
  Boxes := TCheckBoxes.Create(Rc(0, 0, 40, 3), ItemList(['ab', 'abcd', 'abc', 'x', 'yy', 'zzzz', 'q']));
  Root.Insert(Boxes);
end;

procedure TestMouse;
var
  Root: TRoot;
  Boxes: TCheckBoxes;
  Cleared: Boolean;
begin
  SevenBoxes(Root, Boxes);
  Root.AddEvent(MouseEv(evMouseUp, 12, 1));
  Cleared := SendEvent(Boxes, MouseEv(evMouseDown, 12, 1));
  Check(Cleared and (TPeek(Boxes).GetSel = 4) and (TPeek(Boxes).GetValue = 16),
    'a click selects a button and presses it');
  Check((Boxes.State and sfCursorVis) <> 0, 'the cursor is shown after a click');
  FreeRoot(Root);

  SevenBoxes(Root, Boxes);
  Root.AddEvent(MouseEv(evMouseUp, 30, 2));
  Cleared := SendEvent(Boxes, MouseEv(evMouseDown, 12, 1));
  Check(Cleared and (TPeek(Boxes).GetSel = 4) and (TPeek(Boxes).GetValue = 0),
    'a button is selected but not pressed when the mouse is released away from it');
  FreeRoot(Root);

  SevenBoxes(Root, Boxes);
  Boxes.SetButtonState(16, False);
  Root.AddEvent(MouseEv(evMouseUp, 12, 1));
  Cleared := SendEvent(Boxes, MouseEv(evMouseDown, 12, 1));
  Check(Cleared and (TPeek(Boxes).GetSel = 0) and (TPeek(Boxes).GetValue = 0),
    'a disabled button is not selected by a click, and is not pressed');
  FreeRoot(Root);

  SevenBoxes(Root, Boxes);
  Root.AddEvent(MouseEv(evMouseMove, 12, 1));
  Root.AddEvent(MouseEv(evMouseMove, 1, 0));
  Root.AddEvent(MouseEv(evMouseUp, 1, 0));
  Cleared := SendEvent(Boxes, MouseEv(evMouseDown, 1, 0));
  Check(Cleared and (TPeek(Boxes).GetSel = 0) and (TPeek(Boxes).GetValue = 1),
    'a button is pressed when the mouse comes back to it before it is released');
  Check(Root.ScriptPos = 3, 'the loop reads the moves and the release');
  FreeRoot(Root);

  SevenBoxes(Root, Boxes);
  Root.AddEvent(MouseEv(evMouseUp, 39, 2));
  Cleared := SendEvent(Boxes, MouseEv(evMouseDown, 39, 2));
  Check(Cleared and (TPeek(Boxes).GetSel = 0) and (TPeek(Boxes).GetValue = 0), 'a click beside the items does nothing');
  FreeRoot(Root);

  SevenBoxes(Root, Boxes);
  Root.AddEvent(MouseEv(evMouseUp, 22, 0));
  Cleared := SendEvent(Boxes, MouseEv(evMouseDown, 22, 0));
  Check(Cleared and (TPeek(Boxes).GetSel = 6) and (TPeek(Boxes).GetValue = 64), 'a click on the last column');
  FreeRoot(Root);
end;

procedure TestSetState;
var
  Root: TRoot;
  Boxes: TCheckBoxes;
begin
  Boxes := TCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['One', 'Two', 'Three']));
  Root := NewRoot;
  Root.Insert(Boxes);
  Selected(Boxes, False);
  ClearScreen;
  Boxes.SetState(sfFocused, True);
  Check(CharAt(1, 0) = #0, 'a change of the focus does not draw the cluster');
  Check((Boxes.State and sfFocused) <> 0, 'the state is set');
  Boxes.SetState(sfSelected, True);
  Check(CharAt(1, 0) = '[', 'a change of the selection draws the cluster');
  Check((Boxes.State and sfSelected) <> 0, 'the selected state is set');
  FreeRoot(Root);
end;

procedure TestNotSelectable;
var
  Root: TRoot;
  Boxes: TCheckBoxes;
  Cleared: Boolean;
begin
  Root := NewRoot;
  Boxes := TCheckBoxes.Create(Rc(0, 0, 20, 3), ItemList(['One', 'Two', 'Three']));
  Root.Insert(Boxes);
  Focused(Boxes, True);
  Boxes.SetButtonState(7, False);
  Cleared := SendKey(Boxes, kbDown);
  Check((not Cleared) and (TPeek(Boxes).GetSel = 0), 'a cluster that is not selectable does not handle keys');
  Boxes.SetButtonState(1, True);
  Cleared := SendKey(Boxes, kbDown);
  Check(Cleared and (TPeek(Boxes).GetSel = 0), 'with one enabled button the selection returns to it');
  FreeRoot(Root);
end;

procedure BuildAndDrop;
var
  Radio: TRadioButtons;
  Multi: TMultiCheckBoxes;
begin
  Radio := TRadioButtons.Create(Rc(0, 0, 10, 3), ItemList(['One', 'Two', 'Three']));
  Radio.Free;
  Multi := TMultiCheckBoxes.Create(Rc(0, 0, 10, 3), ItemList(['One', 'Two']), 3, cfTwoBits, ' -+');
  Multi.Free;
end;

procedure TestRelease;
var
  Before, After: PtrUInt;
begin
  BuildAndDrop;
  Before := GetFPCHeapStatus.CurrHeapUsed;
  BuildAndDrop;
  After := GetFPCHeapStatus.CurrHeapUsed;
  Check(After = Before, 'a cluster releases its strings, its list and its states');
end;

var
  PaletteText: string;
  K: Integer;
  SavedBackend: TScreenBackend;

begin
  PaletteText := '';
  for K := 1 to 127 do
    PaletteText := PaletteText + Chr(K);
  RootPal := TPalette.Create(PaletteText, 127);

  Fake := TFakeDisplay.Create;
  SavedBackend := TDisplay.Backend;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;
  HotKeyHook := @TestHotKey;

  TestTables;
  TestSItem;
  TestConstruction;
  TestEnableMask;
  TestMarkAndPress;
  TestMultiState;
  TestData;
  TestHelpCtx;
  TestDrawLayout;
  TestDrawStates;
  TestDrawKinds;
  TestMarkersAndCursor;
  TestArrowKeys;
  TestHotKeys;
  TestSpace;
  TestMouse;
  TestSetState;
  TestNotSelectable;
  TestRelease;

  HotKeyHook := nil;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
