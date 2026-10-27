{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (TSItem, TCluster, TRadioButtons, TCheckBoxes, TMultiCheckBoxes and the
  flags cfOneBit to cfEightBits), include/tvision/ttypes.h (specialChars), source/tvision/tcluster.cpp,
  source/tvision/tradiobu.cpp, source/tvision/tcheckbo.cpp, source/tvision/tmulchkb.cpp,
  source/tvision/tvtext1.cpp (the tables button of TRadioButtons and TCheckBoxes)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit. The classes of dialogs.h that are not named above belong to other units.

  Parts of the C++ that have no unit yet:
    - hotKey() returns the letter that a text marks with tildes; the HotKeyHook of TvDialog stands for it. While it
      is nil no item has a hot key, so an item answers to no letter;
    - TStringCollection has no unit; the strings of a cluster are a TCollection of blocks of characters from NewStr,
      which TCollection releases with FreeMem, and the cluster only inserts at the end, reads and counts them, as the
      C++ does.

  specialChars is the variable SpecialChars of TvDialog. The tables button of TRadioButtons and TCheckBoxes are the
  class variables Button of the two classes; they get their C++ values when the unit starts, in code page 437, and a
  program may change them.

  A text of the C++ that is a char pointer is a string here; the strings of a cluster are blocks of characters with a
  terminating zero, as the C++ keeps them. The record that GetData and SetData of a cluster read and write is
  a Word (a LongWord for TMultiCheckBoxes), as in the C++. }
unit TvCluster;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvObjs, TvViews;

const
  { The flags of a TMultiCheckBoxes: the low byte is the mask of the bits of one item and the high byte is the number
    of bits of an item. }
  cfOneBit = Word($0101);
  cfTwoBits = Word($0203);
  cfFourBits = Word($040F);
  cfEightBits = Word($08FF);

type
  { One string of a list of strings, with the next item of the list. The text is a block of characters that the item
    owns. }
  TSItem = class(TvObject)
  public
    Value: PAnsiChar;
    Next: TSItem;
    constructor Create(const AValue: string; ANext: TSItem);
    destructor Destroy; override;
  end;

  { A group of buttons that are laid out in columns of the height of the view. The palette is: 1 normal text,
    2 selected text, 3 normal shortcut, 4 selected shortcut, 5 disabled text. }
  TCluster = class(TView)
  protected
    Value: Cardinal;
    EnableMask: Cardinal;
    Sel: Integer;
    Strings: TCollection;
  private
    function Column(Item: Integer): Integer;
    function FindSel(Where: TPoint): Integer;
    function Row(Item: Integer): Integer;
    procedure MoveSel(Tries, Target: Integer);
    function StepFrom(Candidate: Integer; Key: Word): Integer;
    procedure Travel(Key: Word; var Event: TEvent);
    procedure TrackMouse(var Event: TEvent);
    function ItemUnderMouse(const Event: TEvent): Integer;
    procedure PressSelectedAndRedraw;
    procedure ShowCursorIfOverSelection(const Event: TEvent);
    function MatchesKey(HotChar: Char; const KeyDown: TKeyDownEvent): Boolean;
    procedure HandleOtherKey(var Event: TEvent);
  public
    { The list AStrings is released: its items are copied into the strings of the cluster. }
    constructor Create(const Bounds: TRect; AStrings: TSItem);
    destructor Destroy; override;
    function DataSize: Word; override;
    procedure DrawBox(const Icon: string; Marker: Char);
    { Draws the buttons. Icon is drawn at the start of each button, and the character of Marker that the value of
      MultiMark of the item selects is drawn in its third cell. }
    procedure DrawMultiBox(const Icon, Marker: string);
    procedure GetData(Rec: Pointer); override;
    function GetHelpCtx: Word; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Mark(Item: Integer): Boolean; virtual;
    function MultiMark(Item: Integer): Byte; virtual;
    procedure Press(Item: Integer); virtual;
    procedure MovedTo(Item: Integer); virtual;
    procedure SetData(Rec: Pointer); override;
    procedure SetState(AState: Word; Enable: Boolean); override;
    procedure SetButtonState(AMask: Cardinal; Enable: Boolean); virtual;
    function ButtonState(Item: Integer): Boolean;
  end;

  { Buttons of which one is chosen. The palette is the one of TCluster. }
  TRadioButtons = class(TCluster)
  public
    class var Button: string;
    constructor Create(const Bounds: TRect; AStrings: TSItem);
    procedure Draw; override;
    function Mark(Item: Integer): Boolean; override;
    procedure MovedTo(Item: Integer); override;
    procedure Press(Item: Integer); override;
    procedure SetData(Rec: Pointer); override;
  end;

  { Buttons that are on or off, each one a bit of the value. The palette is the one of TCluster. }
  TCheckBoxes = class(TCluster)
  public
    class var Button: string;
    constructor Create(const Bounds: TRect; AStrings: TSItem);
    procedure Draw; override;
    function Mark(Item: Integer): Boolean; override;
    procedure Press(Item: Integer); override;
  end;

  { Buttons that have more than two states, each one a field of bits of the value. The palette is the one of
    TCluster. }
  TMultiCheckBoxes = class(TCluster)
  private
    SelRange: Byte;
    Flags: Word;
    States: PAnsiChar;
    function FieldMask(Item: Integer): Cardinal;
    function FieldShift(Item: Integer): Integer;
    function FieldOf(Item: Integer): Cardinal;
  public
    constructor Create(const Bounds: TRect; AStrings: TSItem; ASelRange: Byte; AFlags: Word;
      const AStates: string);
    destructor Destroy; override;
    function DataSize: Word; override;
    procedure Draw; override;
    procedure GetData(Rec: Pointer); override;
    function MultiMark(Item: Integer): Byte; override;
    procedure Press(Item: Integer); override;
    procedure SetData(Rec: Pointer); override;
  end;

implementation

uses
  Strings, TvKeys, TvUtil, TvDialog;

const
  cpCluster = #$10#$11#$12#$12#$1F;

var
  ClusterPalette: TPalette;

{ The character of Marker at the zero based position Index; #0 outside the string. }
function MarkerAt(const Marker: string; Index: Integer): Char;
begin
  Result := #0;
  if (Index < 0) or (Index >= Length(Marker)) then
    Exit;
  Result := Marker[Index + 1];
end;

{ The hot key of the string at Item, a block of characters; #0 while there is no hook. }
function HotKeyOfItem(Item: Pointer): Char;
begin
  Result := #0;
  if not Assigned(HotKeyHook) then
    Exit;
  Result := HotKeyHook(StrPas(PAnsiChar(Item)));
end;

{ TSItem }

constructor TSItem.Create(const AValue: string; ANext: TSItem);
begin
  inherited Create;
  Value := NewStr(AValue);
  Next := ANext;
end;

destructor TSItem.Destroy;
begin
  if Value <> nil then
    FreeMem(Value);
  inherited Destroy;
end;

{ TCluster }

constructor TCluster.Create(const Bounds: TRect; AStrings: TSItem);
var
  itemCount: Integer;
  node, following: TSItem;
begin
  inherited Create(Bounds);
  Value := 0;
  Sel := 0;
  Options := Options or ofSelectable or ofFirstClick or ofPreProcess or ofPostProcess;

  itemCount := 0;
  node := AStrings;
  while node <> nil do
  begin
    Inc(itemCount);
    node := node.Next;
  end;

  Strings := TCollection.Create(itemCount, 0);
  node := AStrings;
  while node <> nil do
  begin
    following := node.Next;
    Strings.AtInsert(Strings.GetCount, NewStr(node.Value, StrLen(node.Value)));
    node.Free;
    node := following;
  end;

  EnableMask := High(Cardinal);
  SetCursor(2, 0);
  ShowCursor;
end;

destructor TCluster.Destroy;
begin
  TvObject.DestroyObject(Strings);
  Strings := nil;
  inherited Destroy;
end;

function TCluster.DataSize: Word;
begin
  Result := SizeOf(Word);
end;

procedure TCluster.DrawBox(const Icon: string; Marker: Char);
var
  markers: string;
begin
  markers := ' ' + Marker;
  DrawMultiBox(Icon, markers);
end;

procedure TCluster.DrawMultiBox(const Icon, Marker: string);
var
  lineBuffer: TDrawBuffer;
  normalTints, selectedTints, disabledTints, itemTints: TAttrPair;
  itemCount, lastBlock, rowIndex, blockIndex, itemIndex, itemColumn: Integer;
  isSelected, isCurrentItem: Boolean;
  caretColumn, caretRow: Integer;
begin
  itemCount := Strings.GetCount;
  normalTints := GetColor($0301);
  selectedTints := GetColor($0402);
  disabledTints := GetColor($0505);
  lastBlock := (itemCount - 1) div Size.Y + 1;
  isSelected := (State and sfSelected) <> 0;

  lineBuffer := TDrawBuffer.Create;
  try
    for rowIndex := 0 to Size.Y do
    begin
      lineBuffer.MoveChar(0, ' ', normalTints.Attrs[0], Word(Size.X));
      for blockIndex := 0 to lastBlock do
      begin
        itemIndex := blockIndex * Size.Y + rowIndex;
        if itemIndex >= itemCount then
          Continue;
        itemColumn := Column(itemIndex);
        if itemColumn >= Size.X then
          Continue;

        isCurrentItem := itemIndex = Sel;
        if not ButtonState(itemIndex) then
          itemTints := disabledTints
        else if isCurrentItem and isSelected then
          itemTints := selectedTints
        else
          itemTints := normalTints;

        lineBuffer.MoveChar(Word(itemColumn), ' ', itemTints.Attrs[0], Word(Size.X - itemColumn));
        lineBuffer.MoveCStr(Word(itemColumn), Icon, itemTints);
        lineBuffer.PutChar(Word(itemColumn + 2), Ord(MarkerAt(Marker, MultiMark(itemIndex))));
        lineBuffer.MoveCStr(Word(itemColumn + 5), StrPas(PAnsiChar(Strings.At(itemIndex))), itemTints);
        if ShowMarkers and isSelected and isCurrentItem then
        begin
          lineBuffer.PutChar(Word(itemColumn), SpecialChars[0]);
          lineBuffer.PutChar(Word(Column(itemIndex + Size.Y) - 1), SpecialChars[1]);
        end;
      end;
      WriteBuf(0, rowIndex, Size.X, 1, lineBuffer);
    end;
  finally
    lineBuffer.Free;
  end;
  caretColumn := Column(Sel) + 2;
  caretRow := Row(Sel);
  SetCursor(caretColumn, caretRow);
end;

procedure TCluster.GetData(Rec: Pointer);
begin
  PWord(Rec)^ := Word(Value and $FFFF);
  DrawView;
end;

function TCluster.GetHelpCtx: Word;
begin
  if HelpCtx = hcNoContext then
    Result := hcNoContext
  else
    Result := Word(HelpCtx + Sel);
end;

function TCluster.GetPalette: TPalette;
begin
  Result := ClusterPalette;
end;

procedure TCluster.MoveSel(Tries, Target: Integer);
begin
  if Tries > Strings.GetCount then
    Exit;
  Sel := Target;
  MovedTo(Sel);
  DrawView;
end;

{ The item that the arrow key Key reaches from Candidate, before the check whether its button is enabled. }
function TCluster.StepFrom(Candidate: Integer; Key: Word): Integer;
var
  itemCount, columnsNeeded, rowsBelowZero: Integer;
begin
  itemCount := Strings.GetCount;
  case Key of
    kbUp:
      begin
        Dec(Candidate);
        if Candidate < 0 then
          Candidate := itemCount - 1;
      end;
    kbDown:
      begin
        Inc(Candidate);
        if Candidate >= itemCount then
          Candidate := 0;
      end;
    kbRight:
      begin
        Inc(Candidate, Size.Y);
        if Candidate >= itemCount then
          Candidate := 0;
      end;
    kbLeft:
      begin
        if Candidate <= 0 then
          Candidate := itemCount - 1
        else
        begin
          Candidate := Candidate - Size.Y;
          if Candidate < 0 then
          begin
            columnsNeeded := (itemCount + Size.Y - 1) div Size.Y;
            rowsBelowZero := Candidate;
            Candidate := columnsNeeded * Size.Y;
            Candidate := Candidate + rowsBelowZero;
            Candidate := Candidate - 1;
            Candidate := Min(Candidate, itemCount - 1);
          end;
        end;
      end;
  end;
  Result := Candidate;
end;

{ Moves the selection by the arrow key Key to the next enabled button, giving up after one round. }
procedure TCluster.Travel(Key: Word; var Event: TEvent);
var
  attempts, candidate: Integer;
begin
  attempts := 0;
  candidate := Sel;
  repeat
    Inc(attempts);
    candidate := StepFrom(candidate, Key);
  until ButtonState(candidate) or (attempts > Strings.GetCount);
  MoveSel(attempts, candidate);
  ClearEvent(Event);
end;

{ Follows a press of the mouse button: selects the button under it, and presses it when the button is released
  over the selected one. }
procedure TCluster.TrackMouse(var Event: TEvent);
var
  pressedItem: Integer;
  keepGoing: Boolean;
begin
  pressedItem := ItemUnderMouse(Event);
  if (pressedItem >= 0) and ButtonState(pressedItem) then
    Sel := pressedItem;
  DrawView;

  keepGoing := True;
  while keepGoing do
  begin
    ShowCursorIfOverSelection(Event);
    keepGoing := MouseEvent(Event, evMouseMove);
  end;

  ShowCursor;
  if ItemUnderMouse(Event) = Sel then
    PressSelectedAndRedraw;
  ClearEvent(Event);
end;

{ The item at the place where the mouse event happened; -1 when there is none. }
function TCluster.ItemUnderMouse(const Event: TEvent): Integer;
var
  localPlace: TPoint;
begin
  localPlace := MakeLocal(Event.Mouse.Where);
  Result := FindSel(localPlace);
end;

procedure TCluster.PressSelectedAndRedraw;
begin
  Press(Sel);
  DrawView;
end;

{ The cursor is shown while the mouse is over the enabled selected item, and hidden elsewhere. }
procedure TCluster.ShowCursorIfOverSelection(const Event: TEvent);
var
  overSelection: Boolean;
begin
  overSelection := (ItemUnderMouse(Event) = Sel) and ButtonState(Sel);
  if not overSelection then
  begin
    HideCursor;
    Exit;
  end;
  ShowCursor;
end;

{ Tells whether the key event is the Alt key of HotChar, or its letter while the view may take letters. }
function TCluster.MatchesKey(HotChar: Char; const KeyDown: TKeyDownEvent): Boolean;
var
  mayTakeLetters: Boolean;
begin
  Result := False;
  if KeyDown.KeyCode = 0 then
    Exit;
  if GetAltCode(HotChar) = KeyDown.KeyCode then
  begin
    Result := True;
    Exit;
  end;
  if HotChar = #0 then
    Exit;
  mayTakeLetters := (Owner.Phase = phPostProcess) or ((State and sfFocused) <> 0);
  Result := mayTakeLetters and (HotChar = UpCase(Char(KeyDown.CharScan.CharCode)));
end;

{ A key that is not an arrow: the hot key of a button presses it, and the space bar presses the selected one. }
procedure TCluster.HandleOtherKey(var Event: TEvent);
var
  itemIndex: Integer;
  hotChar: Char;
  typedSpace: Boolean;
begin
  for itemIndex := 0 to Strings.GetCount - 1 do
  begin
    hotChar := HotKeyOfItem(Strings.At(itemIndex));
    if not MatchesKey(hotChar, Event.KeyDown) then
      Continue;
    if not ButtonState(itemIndex) then
      Exit;
    if Focus then
    begin
      Sel := itemIndex;
      MovedTo(Sel);
      PressSelectedAndRedraw;
    end;
    ClearEvent(Event);
    Exit;
  end;

  typedSpace := Event.KeyDown.CharScan.CharCode = Ord(' ');
  if not (typedSpace and ((State and sfFocused) <> 0)) then
    Exit;
  PressSelectedAndRedraw;
  ClearEvent(Event);
end;

procedure TCluster.HandleEvent(var Event: TEvent);
var
  arrow: Word;
  canTakeInput, isFocused, isArrow: Boolean;
begin
  inherited HandleEvent(Event);
  canTakeInput := (Options and ofSelectable) <> 0;
  if not canTakeInput then
    Exit;

  if Event.What = evMouseDown then
  begin
    TrackMouse(Event);
    Exit;
  end;
  if Event.What <> evKeyDown then
    Exit;

  arrow := CtrlToArrow(Event.KeyDown.KeyCode);
  isArrow := (arrow = kbUp) or (arrow = kbDown) or (arrow = kbRight) or (arrow = kbLeft);
  if not isArrow then
  begin
    HandleOtherKey(Event);
    Exit;
  end;
  isFocused := (State and sfFocused) <> 0;
  if isFocused then
    Travel(arrow, Event);
end;

procedure TCluster.SetButtonState(AMask: Cardinal; Enable: Boolean);
var
  itemCount: Integer;
  itemsMask, changedBits: Cardinal;
  anyEnabled: Boolean;
begin
  changedBits := AMask;
  if not Enable then
    changedBits := not changedBits;
  if Enable then
    EnableMask := EnableMask or changedBits
  else
    EnableMask := EnableMask and changedBits;

  itemCount := Strings.GetCount;
  if itemCount >= 32 then
    Exit;
  itemsMask := (Cardinal(1) shl itemCount) - 1;
  anyEnabled := (EnableMask and itemsMask) <> 0;
  if anyEnabled then
    Options := Options or ofSelectable
  else
    Options := Options and not Word(ofSelectable);
end;

procedure TCluster.SetData(Rec: Pointer);
begin
  Value := PWord(Rec)^;
  DrawView;
end;

procedure TCluster.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if AState <> sfSelected then
    Exit;
  DrawView;
end;

function TCluster.Mark(Item: Integer): Boolean;
begin
  Result := False;
end;

function TCluster.MultiMark(Item: Integer): Byte;
begin
  if Mark(Item) then
    Result := 1
  else
    Result := 0;
end;

procedure TCluster.MovedTo(Item: Integer);
begin
end;

procedure TCluster.Press(Item: Integer);
begin
end;

{ The column of the first cell of the button Item. A column of buttons is as wide as its longest text, and two
  columns are 6 cells apart beyond that width. }
function TCluster.Column(Item: Integer): Integer;
var
  itemIndex, columnWidth, textLength: Integer;
begin
  if Item < Size.Y then
  begin
    Result := 0;
    Exit;
  end;
  columnWidth := 0;
  Result := -6;
  textLength := 0;
  for itemIndex := 0 to Item do
  begin
    if itemIndex mod Size.Y = 0 then
    begin
      Result := Result + columnWidth + 6;
      columnWidth := 0;
    end;
    if itemIndex < Strings.GetCount then
      textLength := Cstrlen(StrPas(PAnsiChar(Strings.At(itemIndex))));
    if textLength > columnWidth then
      columnWidth := textLength;
  end;
end;

function TCluster.FindSel(Where: TPoint): Integer;
var
  extent: TRect;
  firstOfColumn, found: Integer;
begin
  extent := GetExtent;
  if not extent.Contains(Where) then
  begin
    Result := -1;
    Exit;
  end;
  firstOfColumn := 0;
  while Where.X >= Column(firstOfColumn + Size.Y) do
    Inc(firstOfColumn, Size.Y);
  found := firstOfColumn + Where.Y;
  if found >= Strings.GetCount then
    Result := -1
  else
    Result := found;
end;

function TCluster.Row(Item: Integer): Integer;
begin
  Result := Item mod Size.Y;
end;

function TCluster.ButtonState(Item: Integer): Boolean;
var
  itemBit: Cardinal;
begin
  if (Item < 0) or (Item >= 32) then
  begin
    Result := False;
    Exit;
  end;
  itemBit := Cardinal(1) shl Item;
  Result := (EnableMask and itemBit) <> 0;
end;

{ TRadioButtons }

constructor TRadioButtons.Create(const Bounds: TRect; AStrings: TSItem);
begin
  inherited Create(Bounds, AStrings);
end;

procedure TRadioButtons.Draw;
begin
  DrawMultiBox(Button, ' ' + #7);
end;

function TRadioButtons.Mark(Item: Integer): Boolean;
begin
  Result := Item = Integer(Value);
end;

procedure TRadioButtons.Press(Item: Integer);
begin
  Value := Cardinal(Item);
end;

procedure TRadioButtons.MovedTo(Item: Integer);
begin
  Value := Cardinal(Item);
end;

procedure TRadioButtons.SetData(Rec: Pointer);
begin
  inherited SetData(Rec);
  Sel := Integer(Value);
end;

{ TCheckBoxes }

constructor TCheckBoxes.Create(const Bounds: TRect; AStrings: TSItem);
begin
  inherited Create(Bounds, AStrings);
end;

procedure TCheckBoxes.Draw;
begin
  DrawMultiBox(Button, ' X');
end;

function TCheckBoxes.Mark(Item: Integer): Boolean;
var
  itemBit: Cardinal;
begin
  itemBit := Cardinal(1) shl Item;
  Result := (Value and itemBit) <> 0;
end;

procedure TCheckBoxes.Press(Item: Integer);
var
  itemBit: Cardinal;
begin
  itemBit := Cardinal(1) shl Item;
  Value := Value xor itemBit;
end;

{ TMultiCheckBoxes }

constructor TMultiCheckBoxes.Create(const Bounds: TRect; AStrings: TSItem; ASelRange: Byte; AFlags: Word;
  const AStates: string);
begin
  inherited Create(Bounds, AStrings);
  States := NewStr(AStates);
  Flags := AFlags;
  SelRange := ASelRange;
end;

destructor TMultiCheckBoxes.Destroy;
begin
  if States <> nil then
    FreeMem(States);
  inherited Destroy;
end;

{ The bits of the field of Item in the value, in place. }
function TMultiCheckBoxes.FieldMask(Item: Integer): Cardinal;
var
  fieldBits: Cardinal;
begin
  fieldBits := Flags and $FF;
  Result := fieldBits shl FieldShift(Item);
end;

{ The position of the lowest bit of the field of Item. }
function TMultiCheckBoxes.FieldShift(Item: Integer): Integer;
begin
  Result := (Flags shr 8) * Item;
end;

{ The field of Item, moved down to the lowest bits. }
function TMultiCheckBoxes.FieldOf(Item: Integer): Cardinal;
begin
  Result := (Value and FieldMask(Item)) shr FieldShift(Item);
end;

function TMultiCheckBoxes.DataSize: Word;
begin
  Result := SizeOf(LongWord);
end;

procedure TMultiCheckBoxes.Draw;
begin
  DrawMultiBox(' [ ] ', StrPas(States));
end;

function TMultiCheckBoxes.MultiMark(Item: Integer): Byte;
begin
  Result := Byte(FieldOf(Item) and $FF);
end;

procedure TMultiCheckBoxes.GetData(Rec: Pointer);
begin
  PLongWord(Rec)^ := Value;
  DrawView;
end;

procedure TMultiCheckBoxes.Press(Item: Integer);
var
  nextState: SmallInt;
  keptBits: Cardinal;
  newField: Cardinal;
begin
  nextState := SmallInt(FieldOf(Item));
  Inc(nextState);
  if nextState >= SelRange then
    nextState := 0;

  keptBits := Value and not FieldMask(Item);
  newField := Cardinal(nextState) shl FieldShift(Item);
  Value := keptBits or newField;
end;

procedure TMultiCheckBoxes.SetData(Rec: Pointer);
begin
  Value := PLongWord(Rec)^;
  DrawView;
end;

initialization
  TRadioButtons.Button := ' ( ) ';
  TCheckBoxes.Button := ' [ ] ';
  ClusterPalette := TPalette.Create(cpCluster, Length(cpCluster));

finalization
  ClusterPalette.Free;

end.
