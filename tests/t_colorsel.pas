{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/colorsel.h, source/tvision/colorsel.cpp, source/tvision/tvtext1.cpp (the texts and the
  tables of TColorSelector, TMonoSelector and TColorDialog), include/tvision/views.h, include/tvision/ttypes.h,
  include/tvision/config.h, include/tvision/tv.h
  See COPYRIGHT.magiblot.

  The display is a screen of 80 by 25 cells in memory; the root of the views is a group that writes into it and reads
  its events from a script. The colors of the root are the BIOS attributes 1 to 127. The hook of the messages
  records the messages of the six commands of the unit (command, receiver and information) and, when asked, delivers
  every message to its receiver as an event. The palette of the dialog is 8 entries: $07, $1E, $2F, $70, $4C, $5D,
  $6E and $7F. }
program t_colorsel;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Strings, SysUtils, TvGeom, TvKeys, TvEvents, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvViews, TvWindow, TvUtil,
  TvCluster, TvDialog, TvList, TvColorSel;

{$I testlib.inc}

const
  ScrW = 80;
  ScrH = 25;
  CallLimit = 20000;
  MaxMsgs = 256;

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

  TTestSelector = class(TColorSelector)
  public
    function GetColorValue: Byte;
    procedure SetColorValue(NewValue: Byte);
  end;

  TTestMono = class(TMonoSelector)
  public
    function GetMonoValue: Cardinal;
    procedure SetMonoValue(NewValue: Cardinal);
    function StringCount: Integer;
  end;

  TTestDisplay = class(TColorDisplay)
  public
    function GetColorPtr: PColorAttr;
    function GetTextBlock: PAnsiChar;
  end;

  TTestGroupList = class(TColorGroupList)
  public
    function GroupsHead: TColorGroup;
  end;

  TTestItemList = class(TColorItemList)
  public
    function ItemsHead: TColorItem;
  end;

  TTestDialog = class(TColorDialog)
  public
    function GetGroupIndexValue: Byte;
    function GetGroupList: TColorGroupList;
    function ForSelVisible: Boolean;
    function ForLabelVisible: Boolean;
    function BakSelVisible: Boolean;
    function BakLabelVisible: Boolean;
    function MonoSelVisible: Boolean;
    function MonoLabelVisible: Boolean;
  end;

  TCountItem = class(TColorItem)
  public
    destructor Destroy; override;
  end;

  TCountGroup = class(TColorGroup)
  public
    destructor Destroy; override;
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  RootPal: TPalette;
  GetCalls: Integer;
  MsgCount: Integer;
  MsgCmd: array[0..MaxMsgs - 1] of Word;
  MsgInfo: array[0..MaxMsgs - 1] of PtrUInt;
  MsgTarget: array[0..MaxMsgs - 1] of TView;
  Deliver: Boolean;
  ItemsFreed: Integer;
  GroupsFreed: Integer;

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
  if (What = evBroadcast) and (Command >= cmColorForegroundChanged) and (Command <= cmSaveColorIndex) then
  begin
    if MsgCount < MaxMsgs then
    begin
      MsgCmd[MsgCount] := Command;
      MsgInfo[MsgCount] := PtrUInt(InfoPtr);
      MsgTarget[MsgCount] := Receiver;
    end;
    Inc(MsgCount);
  end;
  if (not Deliver) or (Receiver = nil) then
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

function BroadcastEv(Cmd: Word; Info: PtrUInt): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evBroadcast;
  Result.Message.Command := Cmd;
  Result.Message.InfoPtr := Pointer(Info);
end;

function CellText(X, Y: Integer): string;
begin
  Result := ScreenCells[Y * ScrW + X].Character.GetText;
end;

function CharAt(X, Y: Integer): Char;
var
  S: string;
begin
  S := CellText(X, Y);
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

function PalByte(P: TPalette; I: Integer): Integer;
var
  A: TColorAttr;
begin
  A := P.Items[I];
  Result := A.ToBIOS;
end;

function AttrByte(const A: TColorAttr): Integer;
begin
  Result := A.ToBIOS;
end;

procedure ResetMessages;
begin
  MsgCount := 0;
end;

{ The number of messages that the arrays hold. }
function Recorded: Integer;
begin
  Result := MsgCount;
  if Result > MaxMsgs then
    Result := MaxMsgs;
end;

{ Delivers a broadcast of the command Cmd with the number Info to Target. }
procedure SendTo(Target: TView; Cmd: Word; Info: PtrUInt);
var
  Ev: TEvent;
begin
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.What := evBroadcast;
  Ev.Message.Command := Cmd;
  Ev.Message.InfoPtr := Pointer(Info);
  Target.HandleEvent(Ev);
end;

function HasFlag(Bits, Mask: Word): Boolean;
begin
  Result := (Bits and Mask) = Mask;
end;

{ The views of the tests. }

function TTestSelector.GetColorValue: Byte;
begin
  Result := Color;
end;

procedure TTestSelector.SetColorValue(NewValue: Byte);
begin
  Color := NewValue;
end;

function TTestMono.GetMonoValue: Cardinal;
begin
  Result := Value;
end;

procedure TTestMono.SetMonoValue(NewValue: Cardinal);
begin
  Value := NewValue;
end;

function TTestMono.StringCount: Integer;
begin
  Result := Strings.GetCount;
end;

function TTestDisplay.GetColorPtr: PColorAttr;
begin
  Result := Color;
end;

function TTestDisplay.GetTextBlock: PAnsiChar;
begin
  Result := Text;
end;

function TTestGroupList.GroupsHead: TColorGroup;
begin
  Result := Groups;
end;

function TTestItemList.ItemsHead: TColorItem;
begin
  Result := Items;
end;

function TTestDialog.GetGroupIndexValue: Byte;
begin
  Result := GroupIndex;
end;

function TTestDialog.GetGroupList: TColorGroupList;
begin
  Result := Groups;
end;

function TTestDialog.ForSelVisible: Boolean;
begin
  Result := (ForSel.State and sfVisible) <> 0;
end;

function TTestDialog.ForLabelVisible: Boolean;
begin
  Result := (ForLabel.State and sfVisible) <> 0;
end;

function TTestDialog.BakSelVisible: Boolean;
begin
  Result := (BakSel.State and sfVisible) <> 0;
end;

function TTestDialog.BakLabelVisible: Boolean;
begin
  Result := (BakLabel.State and sfVisible) <> 0;
end;

function TTestDialog.MonoSelVisible: Boolean;
begin
  Result := (MonoSel.State and sfVisible) <> 0;
end;

function TTestDialog.MonoLabelVisible: Boolean;
begin
  Result := (MonoLabel.State and sfVisible) <> 0;
end;

destructor TCountItem.Destroy;
begin
  Inc(ItemsFreed);
  inherited Destroy;
end;

destructor TCountGroup.Destroy;
begin
  Inc(GroupsFreed);
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

{ A selector of the kind AKind in a root, at 0, 0 with the size 12 by AHeight. }
function SelectorIn(Root: TRoot; AKind: TColorSel; AHeight: Integer): TTestSelector;
begin
  Result := TTestSelector.Create(Rc(0, 0, 12, AHeight), AKind);
  Root.Insert(Result);
  ResetMessages;
end;

{ Gives the key Code to S, which has the color Start; the color that S has after it. }
function StepFrom(S: TTestSelector; Start: Byte; Code: Word): Byte;
var
  Ev: TEvent;
begin
  S.SetColorValue(Start);
  ResetMessages;
  Ev := KeyEv(Code);
  S.HandleEvent(Ev);
  Result := S.GetColorValue;
end;

{ The groups and the items that the tests of the lists use: Alpha has Red 10, Green 11 and Blue 12, Beta has Cyan 20
  and Pink 21, Gamma has none. }
procedure MakeGroups(out G1, G2, G3: TColorGroup; out A1, A2, A3, B1, B2: TColorItem);
var
  ChainI: TColorItem;
  ChainG: TColorGroup;
begin
  A1 := TCountItem.Create('Red', 10);
  A2 := TCountItem.Create('Green', 11);
  A3 := TCountItem.Create('Blue', 12);
  B1 := TCountItem.Create('Cyan', 20);
  B2 := TCountItem.Create('Pink', 21);
  ChainI := A1 + A2 + A3;
  ChainI := B1 + B2;
  G1 := TCountGroup.Create('Alpha', A1);
  G2 := TCountGroup.Create('Beta', B1);
  G3 := TCountGroup.Create('Gamma');
  ChainG := G1 + G2 + G3;
end;

{ The groups of the dialog: Window has Frame 1, Title 2 and Text 3; Menu has Normal 4, Select 5 and Back 6. }
function MakeDialogGroups: TColorGroup;
var
  W, M: TColorGroup;
  I1, I2, I3, I4, I5, I6: TColorItem;
begin
  I1 := TCountItem.Create('Frame', 1);
  I2 := TCountItem.Create('Title', 2);
  I3 := TCountItem.Create('Text', 3);
  I4 := TCountItem.Create('Normal', 4);
  I5 := TCountItem.Create('Select', 5);
  I6 := TCountItem.Create('Back', 6);
  W := TCountGroup.Create('Window', I1 + I2 + I3);
  M := TCountGroup.Create('Menu', I4 + I5 + I6);
  Result := W + M;
end;

function DialogPalette: TPalette;
begin
  Result := TPalette.Create(#$07#$1E#$2F#$70#$4C#$5D#$6E#$7F, 8);
end;

{ The tests. }

procedure TestConstantsAndTexts;
begin
  Check(cmColorForegroundChanged = 71, 'the command cmColorForegroundChanged is 71');
  Check(cmColorBackgroundChanged = 72, 'the command cmColorBackgroundChanged is 72');
  Check(cmColorSet = 73, 'the command cmColorSet is 73');
  Check(cmNewColorItem = 74, 'the command cmNewColorItem is 74');
  Check(cmNewColorIndex = 75, 'the command cmNewColorIndex is 75');
  Check(cmSaveColorIndex = 76, 'the command cmSaveColorIndex is 76');
  Check(Ord(csBackground) = 0, 'csBackground is the first value');
  Check(Ord(csForeground) = 1, 'csForeground is the second value');
  Check(TColorSelector.Icon = #$DB, 'the icon of a color selector is the character $DB');
  Check(TMonoSelector.Button = ' ( ) ', 'the button of a mono selector');
  Check(TMonoSelector.Normal = 'Normal', 'the text Normal');
  Check(TMonoSelector.Highlight = 'Highlight', 'the text Highlight');
  Check(TMonoSelector.Underline = 'Underline', 'the text Underline');
  Check(TMonoSelector.Inverse = 'Inverse', 'the text Inverse');
  Check(TColorDialog.Colors = 'Colors', 'the title of the color dialog');
  Check(TColorDialog.GroupText = '~G~roup', 'the text of the group label');
  Check(TColorDialog.ItemText = '~I~tem', 'the text of the item label');
  Check(TColorDialog.ForText = '~F~oreground', 'the text of the foreground label');
  Check(TColorDialog.BakText = '~B~ackground', 'the text of the background label');
  Check(TColorDialog.TextText = 'Text ', 'the sample text has a trailing blank');
  Check(TColorDialog.ColorText = 'Color', 'the text of the mono label');
  Check(TColorDialog.OkText = 'O~K~', 'the text of the OK button');
  Check(TColorDialog.CancelText = 'Cancel', 'the text of the Cancel button');
end;

procedure TestChains;
var
  I1, I2, I3, I4, J1, J2: TColorItem;
  G1, G2, G3: TColorGroup;
  Joined: TColorItem;
  JoinedGroup: TColorGroup;
begin
  I1 := TColorItem.Create('One', 1);
  Check(StrPas(I1.Name) = 'One', 'an item keeps its name');
  Check(I1.Index = 1, 'an item keeps its index');
  Check(I1.Next = nil, 'an item has no next item by default');
  I2 := TColorItem.Create('Two', 2);
  I3 := TColorItem.Create('Three', 3, nil);
  Joined := I1 + I2;
  Check(Joined = I1, 'the sum of two items is the first');
  Check((I1.Next = I2) and (I2.Next = nil), 'the second item follows the first');
  Joined := I1 + I3;
  Check((I2.Next = I3) and (I1.Next = I2), 'an item is added after the last item of the chain');
  I4 := TColorItem.Create('Four', 4, I1);
  Check(I4.Next = I1, 'the third argument of the constructor is the next item');

  G1 := TColorGroup.Create('Alpha');
  Check(StrPas(G1.Name) = 'Alpha', 'a group keeps its name');
  Check((G1.Items = nil) and (G1.Next = nil), 'a group has no items and no next group by default');
  Check(G1.Index = 0, 'the index of a new group is 0');
  JoinedGroup := G1 + I4;
  Check((G1.Items = I4) and (JoinedGroup = G1), 'an item of a group without items is its first item');
  G2 := TColorGroup.Create('Beta');
  JoinedGroup := G1 + G2;
  Check((JoinedGroup = G1) and (G1.Next = G2), 'the sum of two groups is the first, and the second follows it');
  J1 := TColorItem.Create('Five', 5);
  JoinedGroup := G1 + J1;
  Check((G2.Items = J1) and (JoinedGroup = G1), 'an item is added to the last group of a chain');
  J2 := TColorItem.Create('Six', 6);
  JoinedGroup := G1 + J2;
  Check((J1.Next = J2) and (G2.Items = J1) and (G1.Items = I4), 'an item is added after the last item of the last group');
  G3 := TColorGroup.Create('Gamma', I3, G1);
  Check((G3.Items = I3) and (G3.Next = G1), 'the arguments of the constructor of a group');

  G3.Free;
  G2.Free;
  G1.Free;
  J2.Free;
  J1.Free;
  I4.Free;
  I3.Free;
  I2.Free;
  I1.Free;
end;

procedure TestSelectorCreate;
var
  Root: TRoot;
  Fore, Back: TTestSelector;
begin
  Root := NewRoot;
  Fore := TTestSelector.Create(Rc(2, 3, 14, 7), csForeground);
  Back := TTestSelector.Create(Rc(2, 3, 14, 5), csBackground);
  Check(Fore.GetColorValue = 0, 'the color of a new selector is 0');
  Check(HasFlag(Fore.Options, ofSelectable or ofFirstClick or ofFramed), 'a selector is selectable, takes the first click and is framed');
  Check((Fore.EventMask and evBroadcast) <> 0, 'a selector receives broadcasts');
  Check(Fore.Size = Pt(12, 4), 'the size of a selector comes from the bounds');
  Check(Back.GetColorValue = 0, 'the color of a new background selector is 0');
  Fore.Free;
  Back.Free;
  FreeRoot(Root);
end;

procedure TestSelectorKeys;
var
  Root: TRoot;
  S: TTestSelector;
  Ev: TEvent;
begin
  Root := NewRoot;
  S := SelectorIn(Root, csForeground, 4);

  Check(StepFrom(S, 0, kbRight) = 1, 'right moves to the next color');
  Check((MsgCount = 1) and (MsgCmd[0] = cmColorForegroundChanged) and (MsgInfo[0] = 1),
    'the foreground selector tells the new color to its owner');
  Check(MsgTarget[0] = Root, 'the message goes to the owner');
  Check(StepFrom(S, 15, kbRight) = 0, 'right at the last color wraps to 0');
  Check(StepFrom(S, 0, kbLeft) = 15, 'left at 0 wraps to the last color');
  Check(StepFrom(S, 15, kbLeft) = 14, 'left moves to the previous color');
  Check(StepFrom(S, 5, kbUp) = 1, 'up moves a row up');
  Check(StepFrom(S, 0, kbUp) = 15, 'up at 0 goes to the last color');
  Check(StepFrom(S, 2, kbUp) = 13, 'up in the first row goes to the last row');
  Check(StepFrom(S, 0, kbDown) = 4, 'down moves a row down');
  Check(StepFrom(S, 14, kbDown) = 3, 'down in the last row goes to the first row');
  Check(StepFrom(S, 15, kbDown) = 0, 'down at the last color goes to 0');
  Check(StepFrom(S, 8, kbCtrlS) = 7, 'the Wordstar key control S acts as left');
  Check(StepFrom(S, 8, kbCtrlLeft) = 8, 'control left is not an arrow key for ctrlToArrow');

  Check(StepFrom(S, 6, kbEnter) = 6, 'another key leaves the color');
  Check(MsgCount = 0, 'another key sends no message');
  S.SetColorValue(6);
  Ev := KeyEv(kbEnter);
  S.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'another key is not taken');

  S.SetColorValue(3);
  Ev := KeyEv(kbRight);
  S.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'an arrow key is taken');

  Root.Remove(S);
  S.Free;

  S := SelectorIn(Root, csBackground, 2);
  Check(StepFrom(S, 7, kbRight) = 0, 'right at color 7 of a background selector wraps to 0');
  Check((MsgCount = 1) and (MsgCmd[0] = cmColorBackgroundChanged) and (MsgInfo[0] = 0),
    'the background selector sends the background command');
  Check(StepFrom(S, 0, kbLeft) = 7, 'left at 0 of a background selector goes to 7');
  Check(StepFrom(S, 0, kbUp) = 7, 'up at 0 of a background selector goes to 7');
  Check(StepFrom(S, 2, kbUp) = 5, 'up in the first row of a background selector');
  Check(StepFrom(S, 7, kbDown) = 0, 'down at 7 of a background selector goes to 0');
  Check(StepFrom(S, 5, kbDown) = 2, 'down in the second row of a background selector');
  Check(StepFrom(S, 3, kbDown) = 7, 'down from 3 of a background selector goes to 7');
  Check(StepFrom(S, 0, kbDown) = 4, 'down from 0 of a background selector goes to 4');
  FreeRoot(Root);
end;

procedure TestSelectorBroadcast;
var
  Root: TRoot;
  S: TTestSelector;
  Ev: TEvent;
begin
  Root := NewRoot;
  S := SelectorIn(Root, csForeground, 4);
  Ev := BroadcastEv(cmColorSet, $4B);
  S.HandleEvent(Ev);
  Check(S.GetColorValue = $0B, 'a foreground selector takes the low half of cmColorSet');
  Check(Ev.What = evBroadcast, 'cmColorSet is not taken');
  Check(MsgCount = 0, 'cmColorSet sends no message');
  Root.Remove(S);
  S.Free;

  S := SelectorIn(Root, csBackground, 4);
  Ev := BroadcastEv(cmColorSet, $4B);
  S.HandleEvent(Ev);
  Check(S.GetColorValue = 4, 'a background selector takes the high half of cmColorSet');

  S.SetColorValue(2);
  Ev := BroadcastEv(cmColorForegroundChanged, 9);
  S.HandleEvent(Ev);
  Check(S.GetColorValue = 2, 'another broadcast leaves the color');
  Check(MsgCount = 0, 'another broadcast sends no message');
  FreeRoot(Root);
end;

procedure TestSelectorMouse;
var
  Root: TRoot;
  S: TTestSelector;
  Ev: TEvent;
begin
  Root := NewRoot;
  S := SelectorIn(Root, csForeground, 4);
  S.SetColorValue(5);
  Root.AddEvent(MouseEv(evMouseMove, 1, 0));
  Root.AddEvent(MouseEv(evMouseUp, 1, 0));
  Ev := MouseEv(evMouseDown, 7, 2);
  S.HandleEvent(Ev);
  Check(S.GetColorValue = 0, 'the color follows the mouse and ends under the last position');
  Check(MsgCount = 3, 'a message for the press, one for the move and one at the end');
  Check((MsgInfo[0] = 10) and (MsgInfo[1] = 0) and (MsgInfo[2] = 0), 'the colors of the three messages');
  Check(Root.ScriptPos = 2, 'the loop reads the events up to the release');
  Check(Ev.What = evNothing, 'a press is taken');

  S.SetColorValue(5);
  ResetMessages;
  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  Root.AddEvent(MouseEv(evMouseMove, 30, 10));
  Root.AddEvent(MouseEv(evMouseUp, 30, 10));
  Ev := MouseEv(evMouseDown, 7, 2);
  S.HandleEvent(Ev);
  Check(S.GetColorValue = 5, 'a mouse outside the view gives back the first color');
  Check((MsgCount = 3) and (MsgInfo[0] = 10) and (MsgInfo[1] = 5) and (MsgInfo[2] = 5),
    'the colors of the messages when the mouse leaves the view');

  S.SetColorValue(1);
  ResetMessages;
  SetLength(Root.Script, 0);
  Root.ScriptPos := 0;
  Root.AddEvent(MouseEv(evMouseUp, 11, 3));
  Ev := MouseEv(evMouseDown, 11, 3);
  S.HandleEvent(Ev);
  Check(S.GetColorValue = 15, 'the cell at the bottom right is color 15');
  Check((MsgCount = 2) and (MsgInfo[0] = 15) and (MsgInfo[1] = 15), 'a click sends the color twice');
  FreeRoot(Root);
end;

procedure TestSelectorDraw;
var
  Root: TRoot;
  S: TTestSelector;
  Icon: string;
begin
  Root := NewRoot;
  S := SelectorIn(Root, csForeground, 6);
  S.SetColorValue(13);
  ClearScreen;
  S.DrawView;
  Icon := CellText(0, 0);
  Check(Icon <> ' ', 'a swatch is drawn with the icon');
  Check((CellText(1, 0) = Icon) and (CellText(2, 0) = Icon), 'a swatch is three cells wide');
  Check((AttrAt(3, 0) = 1) and (AttrAt(4, 0) = 1) and (AttrAt(5, 0) = 1), 'the swatch 1 has the attribute 1');
  Check((AttrAt(9, 0) = 3) and (AttrAt(0, 1) = 4), 'the swatches 3 and 4 have their numbers as attributes');
  Check((AttrAt(9, 3) = 15) and (AttrAt(6, 2) = 10), 'the swatches 15 and 10 have their numbers as attributes');
  Check(AttrAt(0, 0) = $70, 'the swatch 0 keeps the attribute of the blank line');
  Check(CellText(4, 3) <> Icon, 'the chosen swatch has a mark in its middle cell');
  Check((CellText(3, 3) = Icon) and (CellText(5, 3) = Icon), 'the chosen swatch keeps the icon on both sides');
  Check(CellText(4, 2) = Icon, 'the other swatches have no mark');
  Check(CellText(4, 4) = CellText(4, 3), 'the row 4 repeats the buffer of the row 3');
  Check((CellText(4, 5) = CellText(4, 3)) and (AttrAt(0, 5) = 12), 'the row 5 repeats the buffer of the row 3');

  S.SetColorValue(0);
  ClearScreen;
  S.DrawView;
  Check(CellText(1, 0) <> Icon, 'the swatch 0 has a mark when it is chosen');
  Check(AttrAt(1, 0) = $70, 'the mark of the swatch 0 has the attribute $70');
  Check(AttrAt(0, 0) = $70, 'the other cells of the swatch 0 have the attribute $70');
  FreeRoot(Root);
end;

procedure TestMono;
var
  Root: TRoot;
  M: TTestMono;
  Ev: TEvent;
begin
  Root := NewRoot;
  M := TTestMono.Create(Rc(0, 0, 15, 4));
  Root.Insert(M);
  ResetMessages;
  Check(M.StringCount = 4, 'a mono selector has four buttons');
  Check((M.EventMask and evBroadcast) <> 0, 'a mono selector receives broadcasts');

  M.SetMonoValue($0F);
  Check(M.Mark(1) and (not M.Mark(0)) and (not M.Mark(2)) and (not M.Mark(3)), 'the button of $0F is Highlight');
  M.SetMonoValue($07);
  Check(M.Mark(0) and (not M.Mark(1)), 'the button of $07 is Normal');
  M.SetMonoValue($01);
  Check(M.Mark(2), 'the button of $01 is Underline');
  M.SetMonoValue($70);
  Check(M.Mark(3), 'the button of $70 is Inverse');

  ResetMessages;
  M.Press(2);
  Check(M.GetMonoValue = $01, 'pressing Underline gives $01');
  Check((MsgCount = 2) and (MsgCmd[0] = cmColorForegroundChanged) and (MsgInfo[0] = 1) and
    (MsgCmd[1] = cmColorBackgroundChanged) and (MsgInfo[1] = 0), 'the foreground is told first and then the background');
  ResetMessages;
  M.Press(3);
  Check((M.GetMonoValue = $70) and (MsgInfo[0] = 0) and (MsgInfo[1] = 7), 'pressing Inverse gives $70: black on gray');
  ResetMessages;
  M.MovedTo(1);
  Check((M.GetMonoValue = $0F) and (MsgInfo[0] = 15) and (MsgInfo[1] = 0), 'moving to Highlight gives $0F');
  ResetMessages;
  M.SetMonoValue($9A);
  M.NewColor;
  Check((MsgCount = 2) and (MsgInfo[0] = $A) and (MsgInfo[1] = 9), 'NewColor splits the value into its two halves');
  Check((MsgTarget[0] = Root) and (MsgTarget[1] = Root), 'NewColor sends to the owner');

  Ev := BroadcastEv(cmColorSet, $70);
  M.HandleEvent(Ev);
  Check(M.GetMonoValue = $70, 'cmColorSet sets the value of a mono selector');
  Check(M.Mark(3), 'the new value is marked');
  ResetMessages;
  Ev := BroadcastEv(cmColorBackgroundChanged, 3);
  M.HandleEvent(Ev);
  Check(M.GetMonoValue = $70, 'another broadcast leaves the value');

  M.SetMonoValue($07);
  ClearScreen;
  M.DrawView;
  Check((RowText(0, 0, 2) = ' (') and (CharAt(3, 0) = ')'), 'the first button is drawn as a round button');
  Check(CharAt(2, 0) <> ' ', 'the button of the value is marked');
  Check((CharAt(2, 1) = ' ') and (CharAt(2, 2) = ' ') and (CharAt(2, 3) = ' '), 'the other buttons are not marked');
  Check(RowText(0, 3, 8) = ') Normal', 'the text of the first button');
  Check(RowText(1, 3, 11) = ') Highlight', 'the text of the second button');
  Check(RowText(2, 3, 11) = ') Underline', 'the text of the third button');
  Check(RowText(3, 3, 9) = ') Inverse', 'the text of the fourth button');
  FreeRoot(Root);
end;

procedure TestDisplay;
var
  Root: TRoot;
  D, D2: TTestDisplay;
  V: TColorAttr;
  Ev: TEvent;
  Saved: TColorAttr;
begin
  Root := NewRoot;
  V := TColorAttr.Create($1E);
  D := TTestDisplay.Create(Rc(0, 0, 10, 2), 'Ab');
  Check(StrPas(D.GetTextBlock) = 'Ab', 'a display keeps its text');
  Check((D.EventMask and evBroadcast) <> 0, 'a display receives broadcasts');
  Check(D.GetColorPtr = nil, 'a display has no color at first');
  D.SetColor(@V);
  Check(D.GetColorPtr = @V, 'SetColor keeps the pointer');
  Root.Insert(D);

  ResetMessages;
  D.SetColor(@V);
  Check((MsgCount = 1) and (MsgCmd[0] = cmColorSet) and (MsgInfo[0] = $1E) and (MsgTarget[0] = Root),
    'SetColor tells the color to the owner');

  ClearScreen;
  D.DrawView;
  Check(RowText(0, 0, 10) = 'AbAbAbAbAb', 'the text is repeated over the width');
  Check(RowText(1, 0, 10) = 'AbAbAbAbAb', 'the same row is written for every row of the view');
  Check((AttrAt(0, 0) = $1E) and (AttrAt(9, 1) = $1E), 'the text has the color');

  D2 := TTestDisplay.Create(Rc(0, 5, 10, 6), 'Text ');
  D2.SetColor(@V);
  Root.Insert(D2);
  ClearScreen;
  D2.DrawView;
  Check(RowText(5, 0, 10) = 'Text Text ', 'a text that does not divide the width is cut');

  Saved := TView.ErrorAttr;
  TView.ErrorAttr := TColorAttr.Create($4F);
  V := TColorAttr.Create(0);
  ClearScreen;
  D.DrawView;
  Check(AttrAt(0, 0) = $4F, 'the color 0 is drawn with the error attribute');
  TView.ErrorAttr := Saved;
  V := TColorAttr.Create($1E);

  ResetMessages;
  Ev := BroadcastEv(cmColorForegroundChanged, $0A);
  D.HandleEvent(Ev);
  Check(AttrByte(V) = $1A, 'a new foreground replaces the low half');
  Ev := BroadcastEv(cmColorBackgroundChanged, 5);
  D.HandleEvent(Ev);
  Check(AttrByte(V) = $5A, 'a new background replaces the high half');
  Ev := BroadcastEv(cmColorBackgroundChanged, $1F);
  D.HandleEvent(Ev);
  Check(AttrByte(V) = $FA, 'a background above 15 is cut to its low four bits');
  Ev := BroadcastEv(cmColorForegroundChanged, $3C);
  D.HandleEvent(Ev);
  Check(AttrByte(V) = $FC, 'a foreground above 15 is cut to its low four bits');
  Check(Ev.What = evBroadcast, 'the change is not taken');
  Ev := BroadcastEv(cmColorSet, $11);
  D.HandleEvent(Ev);
  Check(AttrByte(V) = $FC, 'another broadcast leaves the color');
  Check(MsgCount = 0, 'the display sends no message when it changes');

  Ev := KeyEv(kbRight);
  D.HandleEvent(Ev);
  Check(AttrByte(V) = $FC, 'a key leaves the color');
  FreeRoot(Root);
end;

procedure TestGroupList;
var
  G1, G2, G3: TColorGroup;
  A1, A2, A3, B1, B2: TColorItem;
  SB: TScrollBar;
  L: TTestGroupList;
  Ev: TEvent;
begin
  ItemsFreed := 0;
  GroupsFreed := 0;
  MakeGroups(G1, G2, G3, A1, A2, A3, B1, B2);
  SB := TScrollBar.Create(Rc(15, 0, 16, 5));
  L := TTestGroupList.Create(Rc(0, 0, 15, 5), SB, G1);
  Check(L.GroupsHead = G1, 'the list holds the groups');
  Check(L.Range = 3, 'the range is the number of groups');
  Check(L.NumCols = 1, 'the list has one column');
  Check((SB.MinVal = 0) and (SB.MaxVal = 2), 'the bar has the range of the groups');
  Check(L.GetNumGroups = 3, 'the number of groups');
  Check((L.GetGroup(0) = G1) and (L.GetGroup(1) = G2) and (L.GetGroup(2) = G3), 'the groups by number');
  Check(L.GetGroup(3) = nil, 'a number past the end gives no group');
  Check(L.GetText(0, 255) = 'Alpha', 'the text of the first item is the name of the first group');
  Check(L.GetText(1, 3) = 'Bet', 'the text is cut to the length');
  Check(L.GetText(5, 255) = '', 'an item past the end has no text');
  Check(L.GetText(0, 0) = '', 'a length of 0 gives no text');
  Check(L.GetText(-1, 255) = 'Alpha', 'a negative item gives the first group');
  Check(L.GetGroupIndex(0) = 0, 'the index of a new group is 0');
  Check(L.GetGroupIndex(7) = 0, 'the index of a missing group is 0');

  L.SetGroupIndex(0, 2);
  Check(G1.Index = 2, 'SetGroupIndex sets the position of an item');
  L.SetGroupIndex(0, 9);
  Check(G1.Index = 2, 'a position past the last item gives the last item');
  L.SetGroupIndex(0, 1);
  Check(L.GetGroupIndex(0) = 1, 'GetGroupIndex gives the position');
  L.SetGroupIndex(2, 5);
  Check(G3.Index = 0, 'a group without items has the position 0');
  L.SetGroupIndex(9, 1);
  Check((G1.Index = 1) and (G2.Index = 0), 'a missing group changes nothing');

  ResetMessages;
  L.FocusItem(1);
  Check(L.Focused = 1, 'FocusItem moves the focus');
  Check((MsgCount = 1) and (MsgCmd[0] = cmNewColorItem) and (MsgInfo[0] = PtrUInt(G2)),
    'FocusItem sends the group to the owner');
  ResetMessages;
  L.FocusItem(7);
  Check(MsgCount = 0, 'FocusItem past the end sends no message');
  L.FocusItem(1);

  Ev := BroadcastEv(cmSaveColorIndex, 1);
  L.HandleEvent(Ev);
  Check(G2.Index = 1, 'cmSaveColorIndex sets the position in the focused group');
  Ev := BroadcastEv(cmSaveColorIndex, 7);
  L.HandleEvent(Ev);
  Check(G2.Index = 1, 'cmSaveColorIndex with a position past the end gives the last item');
  Ev := BroadcastEv(cmSaveColorIndex, 0);
  L.HandleEvent(Ev);
  Check((G2.Index = 0) and (G1.Index = 1), 'cmSaveColorIndex changes the focused group only');

  L.Free;
  SB.Free;
  Check(GroupsFreed = 3, 'the list frees its groups');
  Check(ItemsFreed = 5, 'the list frees the items of its groups');
end;

procedure TestItemList;
var
  G1, G2, G3: TColorGroup;
  A1, A2, A3, B1, B2: TColorItem;
  SB: TScrollBar;
  L: TTestItemList;
  Ev: TEvent;
begin
  MakeGroups(G1, G2, G3, A1, A2, A3, B1, B2);
  SB := TScrollBar.Create(Rc(15, 0, 16, 5));
  L := TTestItemList.Create(Rc(0, 0, 15, 5), SB, A1);
  Check(L.ItemsHead = A1, 'the list holds the items');
  Check(L.Range = 3, 'the range is the number of items');
  Check((L.EventMask and evBroadcast) <> 0, 'the item list receives broadcasts');
  Check((SB.MinVal = 0) and (SB.MaxVal = 2), 'the bar has the range of the items');
  Check((L.GetText(0, 255) = 'Red') and (L.GetText(1, 255) = 'Green'), 'the text of an item is its name');
  Check(L.GetText(2, 3) = 'Blu', 'the text is cut to the length');
  Check(L.GetText(3, 255) = '', 'an item past the end has no text');
  Check(L.GetText(0, 0) = '', 'a length of 0 gives no text');

  ResetMessages;
  L.FocusItem(1);
  Check(L.Focused = 1, 'FocusItem moves the focus');
  Check((MsgCount = 2) and (MsgCmd[0] = cmSaveColorIndex) and (MsgInfo[0] = 1), 'the position is saved first');
  Check((MsgCmd[1] = cmNewColorIndex) and (MsgInfo[1] = 11), 'the index of the item follows');
  ResetMessages;
  L.FocusItem(2);
  Check((MsgInfo[0] = 2) and (MsgInfo[1] = 12), 'the position and the index of the third item');
  ResetMessages;
  L.FocusItem(5);
  Check((MsgCount = 1) and (MsgCmd[0] = cmSaveColorIndex) and (MsgInfo[0] = 5),
    'an item past the end saves its position and has no index');

  G2.Index := 1;
  ResetMessages;
  Ev := BroadcastEv(cmNewColorItem, PtrUInt(G2));
  L.HandleEvent(Ev);
  Check(L.ItemsHead = B1, 'cmNewColorItem takes the items of the group');
  Check(L.Range = 2, 'the range is the number of items of the new group');
  Check(L.Focused = 1, 'the focus goes to the position of the group');
  Check((MsgCount = 2) and (MsgCmd[0] = cmSaveColorIndex) and (MsgInfo[0] = 1) and (MsgCmd[1] = cmNewColorIndex) and
    (MsgInfo[1] = 21), 'the new item is focused through FocusItem');
  Check(L.GetText(0, 255) = 'Cyan', 'the texts are those of the new group');

  ResetMessages;
  Ev := BroadcastEv(cmNewColorItem, PtrUInt(G3));
  L.HandleEvent(Ev);
  Check((L.Range = 0) and (L.ItemsHead = nil), 'a group without items gives an empty list');
  Check((MsgCount = 1) and (MsgCmd[0] = cmSaveColorIndex) and (MsgInfo[0] = 0), 'only the position is saved');

  L.Free;
  SB.Free;
  G1.Free;
  G2.Free;
  G3.Free;
  A1.Free;
  A2.Free;
  A3.Free;
  B1.Free;
  B2.Free;
end;

procedure TestDialog;
var
  Dlg: TTestDialog;
  Source, Copy1, NewPal: TPalette;
  Idx: PColorIndex;
  FirstSet, LastSet, K: Integer;
begin
  Deliver := True;
  ItemsFreed := 0;
  GroupsFreed := 0;
  Source := DialogPalette;
  ResetMessages;
  Dlg := TTestDialog.Create(Source, MakeDialogGroups);

  Check(Dlg.Size = Pt(61, 18), 'the dialog is 61 by 18');
  Check(HasFlag(Dlg.Options, ofCentered), 'the dialog is centered');
  Check(StrPas(Dlg.Title) = 'Colors', 'the title of the dialog');
  Check((Dlg.Pal <> nil) and (Dlg.Pal <> Source), 'the dialog holds a copy of the palette');
  Check((PalByte(Dlg.Pal, 0) = 8) and (PalByte(Dlg.Pal, 1) = $07) and (PalByte(Dlg.Pal, 4) = $70) and
    (PalByte(Dlg.Pal, 8) = $7F), 'the copy has the entries of the palette');
  Check(Dlg.DataSize = 9, 'the data size is the number of entries plus one');
  Check(Dlg.GetGroupList.Range = 2, 'the group list shows two groups');
  Check(Dlg.GetGroupList.GetText(1, 255) = 'Menu', 'the second group is Menu');
  Check(Dlg.GetGroupIndexValue = 0, 'the first group is chosen');
  Check(Dlg.GetGroupList.Focused = 0, 'the first group is focused');
  Check(Dlg.ForSelVisible and Dlg.ForLabelVisible and Dlg.BakSelVisible and Dlg.BakLabelVisible,
    'the selectors and their labels are shown');
  Check((not Dlg.MonoSelVisible) and (not Dlg.MonoLabelVisible), 'the mono selector and its label are hidden');

  FirstSet := -1;
  LastSet := -1;
  for K := 0 to Recorded - 1 do
    if MsgCmd[K] = cmColorSet then
    begin
      if FirstSet < 0 then
        FirstSet := K;
      LastSet := K;
    end;
  Check((FirstSet >= 0) and (MsgInfo[FirstSet] = 8), 'the display first shows the entry 0, which holds the count');
  Check((LastSet > FirstSet) and (MsgInfo[LastSet] = $07), 'the display ends on the entry of the first item');

  ResetMessages;
  Dlg.GetGroupList.FocusItem(1);
  Check(Dlg.GetGroupIndexValue = 1, 'a new group is remembered by the dialog');
  LastSet := -1;
  for K := 0 to Recorded - 1 do
    if MsgCmd[K] = cmColorSet then
      LastSet := K;
  Check((LastSet >= 0) and (MsgInfo[LastSet] = $70), 'the display shows the first item of the new group');

  SendTo(Dlg, cmColorForegroundChanged, 3);
  Check(PalByte(Dlg.Pal, 4) = $73, 'a new foreground changes the entry of the item');
  SendTo(Dlg, cmColorBackgroundChanged, 2);
  Check(PalByte(Dlg.Pal, 4) = $23, 'a new background changes the entry of the item');

  ResetMessages;
  SendTo(Dlg, cmNewColorIndex, 2);
  LastSet := -1;
  for K := 0 to Recorded - 1 do
    if MsgCmd[K] = cmColorSet then
      LastSet := K;
  Check((LastSet >= 0) and (MsgInfo[LastSet] = $1E), 'cmNewColorIndex points the display at the entry');
  SendTo(Dlg, cmColorForegroundChanged, 1);
  Check((PalByte(Dlg.Pal, 2) = $11) and (PalByte(Dlg.Pal, 4) = $23), 'only the entry that the display points at changes');

  Copy1 := TPalette.Create('', 0);
  Dlg.GetData(Copy1);
  Check((PalByte(Copy1, 0) = 8) and (PalByte(Copy1, 2) = $11) and (PalByte(Copy1, 4) = $23), 'GetData copies the palette');

  Dlg.GetGroupList.SetGroupIndex(0, 2);
  Idx := nil;
  Dlg.GetIndexes(Idx);
  Check(Idx <> nil, 'GetIndexes makes a block');
  Check((Idx^.ColorSize = 2) and (Idx^.GroupIndex = 1), 'the block has the number of groups and the chosen group');
  Check((Idx^.ColorIndex[0] = 2) and (Idx^.ColorIndex[1] = 0), 'the block has the position of each group');
  Idx^.GroupIndex := 0;
  Idx^.ColorIndex[0] := 1;
  Idx^.ColorIndex[1] := 2;
  Dlg.SetIndexes(Idx);
  Check(Dlg.GetGroupIndexValue = 0, 'SetIndexes sets the chosen group');
  Check((Dlg.GetGroupList.GetGroupIndex(0) = 1) and (Dlg.GetGroupList.GetGroupIndex(1) = 2),
    'SetIndexes sets the position of each group');
  Idx^.ColorSize := 5;
  Idx^.ColorIndex[0] := 1;
  Dlg.SetIndexes(Idx);
  Check((Idx <> nil) and (Idx^.ColorSize = 2) and (Idx^.GroupIndex = 0), 'a block of the wrong size is made again');
  Check((Dlg.GetGroupList.GetGroupIndex(0) = 0) and (Dlg.GetGroupList.GetGroupIndex(1) = 0),
    'the new block holds zeros');
  FreeMem(Idx);

  NewPal := TPalette.Create(#$11#$22#$33#$44#$55#$66#$77#$78, 8);
  TView.ShowMarkers := True;
  Dlg.SetData(NewPal);
  TView.ShowMarkers := False;
  Check((PalByte(Dlg.Pal, 1) = $11) and (PalByte(Dlg.Pal, 8) = $78), 'SetData copies the palette');
  Check((not Dlg.ForSelVisible) and (not Dlg.ForLabelVisible) and (not Dlg.BakSelVisible) and
    (not Dlg.BakLabelVisible), 'with the markers on the selectors and their labels are hidden');
  Check(Dlg.MonoSelVisible and Dlg.MonoLabelVisible, 'with the markers on the mono selector and its label are shown');

  Deliver := False;
  TvObject.DestroyObject(Dlg);
  Check(ItemsFreed = 6, 'the dialog frees the items of its groups');
  Check(GroupsFreed = 2, 'the dialog frees its groups');
  Source.Free;
  Copy1.Free;
  NewPal.Free;
  Deliver := False;
end;

procedure TestDialogWithoutPalette;
var
  Dlg: TTestDialog;
  NewPal: TPalette;
begin
  Deliver := False;
  ResetMessages;
  Dlg := TTestDialog.Create(nil, MakeDialogGroups);
  Check(Dlg.Pal = nil, 'a dialog made without a palette has none');
  Check(MsgCount = 0, 'a dialog made without a palette sends no color message');
  NewPal := DialogPalette;
  Dlg.SetData(NewPal);
  Check((Dlg.Pal <> nil) and (Dlg.Pal <> NewPal), 'SetData makes the palette');
  Check((PalByte(Dlg.Pal, 0) = 8) and (PalByte(Dlg.Pal, 3) = $2F), 'SetData copies the entries');
  Check(Dlg.DataSize = 9, 'the data size follows the new palette');
  TvObject.DestroyObject(Dlg);
  NewPal.Free;
end;

var
  SavedBackend: TScreenBackend;
  PaletteText: string;
  K: Integer;

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
  MessageHook := @OnMessage;

  TestConstantsAndTexts;
  TestChains;
  TestSelectorCreate;
  TestSelectorKeys;
  TestSelectorBroadcast;
  TestSelectorMouse;
  TestSelectorDraw;
  TestMono;
  TestDisplay;
  TestGroupList;
  TestItemList;
  TestDialog;
  TestDialogWithoutPalette;

  MessageHook := nil;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
