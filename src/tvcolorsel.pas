{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/colorsel.h, source/tvision/colorsel.cpp, source/tvision/tvtext1.cpp (the texts and the
  tables of TColorSelector, TMonoSelector and TColorDialog), include/tvision/views.h, include/tvision/ttypes.h,
  include/tvision/config.h, include/tvision/tv.h, include/tvision/util.h, source/tvision/misc.cpp (message)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, the constructors with StreamableInit and the members
  writeItems, writeGroups, readItems and readGroups of TColorGroupList belong to a later unit.

  message() sends a message to a view; it is Message of TvViews.

  The texts and tables of tvtext1.cpp are class variables: Icon of TColorSelector, Button, Normal, Highlight,
  Underline and Inverse of TMonoSelector, and Colors, GroupText, ItemText, ForText, BakText, TextText, ColorText,
  OkText and CancelText of TColorDialog. They get their C++ values when the unit starts, in code page 437, and a
  program may change them.

  The name of an item and of a group is a block of characters with a terminating zero that the object owns, and nil
  stands for no name. The data record of a TColorDialog is a TPalette: DataSize gives the number of entries of the
  palette plus one, as the C++ does, and GetData and SetData take a pointer to a TPalette object. The members of the
  C++ whose storage is not initialised (the field index of TColorGroup) start at 0. }
unit TvColorSel;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvObjs, TvViews, TvWindow, TvCluster, TvDialog, TvList;

const
  { The commands that the selectors, the display and the lists send to each other. }
  cmColorForegroundChanged = Word(71);
  cmColorBackgroundChanged = Word(72);
  cmColorSet = Word(73);
  cmNewColorItem = Word(74);
  cmNewColorIndex = Word(75);
  cmSaveColorIndex = Word(76);

type
  { One color of a group: its name and the index of its entry in the palette. }
  TColorItem = class(TvObject)
  public
    Name: PAnsiChar;
    Index: Byte;
    Next: TColorItem;
    constructor Create(const AName: string; AIndex: Byte; ANext: TColorItem = nil);
    destructor Destroy; override;
  end;

  { A named list of items, with the position of the item that is chosen in it. }
  TColorGroup = class(TvObject)
  public
    Name: PAnsiChar;
    Index: Byte;
    Items: TColorItem;
    Next: TColorGroup;
    constructor Create(const AName: string; AItems: TColorItem = nil; ANext: TColorGroup = nil);
    destructor Destroy; override;
  end;

  { Remembers which group was chosen last and which item was chosen in each group. A block that is made for N groups
    holds N + 2 bytes: the two counters and N positions. }
  TColorIndex = record
    GroupIndex, ColorSize: Byte;
    ColorIndex: array[Byte] of Byte;
  end;
  PColorIndex = ^TColorIndex;

  { Which half of an attribute a TColorSelector sets. }
  TColorSel = (csBackground, csForeground);

  { A grid of the 16 colors (8 for the background) that is chosen with the mouse or the arrow keys. }
  TColorSelector = class(TView)
  protected
    Color: Byte;
    SelType: TColorSel;
  private
    procedure ColorChanged;
    procedure TrackMouse(var Event: TEvent; OldColor: Byte);
    function StepByKey(KeyCode: Word; MaxColor: Integer): Boolean;
  public
    { The character that fills a swatch. }
    class var Icon: Char;
    constructor Create(const Bounds: TRect; ASelType: TColorSel);
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { Four buttons that choose one of the attributes normal, highlight, underline and inverse. }
  TMonoSelector = class(TCluster)
  public
    class var Button: string;
    class var Normal: string;
    class var Highlight: string;
    class var Underline: string;
    class var Inverse: string;
    constructor Create(const Bounds: TRect); reintroduce;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Mark(Item: Integer): Boolean; override;
    procedure NewColor;
    procedure Press(Item: Integer); override;
    procedure MovedTo(Item: Integer); override;
  end;

  { A text that is drawn over the whole view in the color that Color points at. }
  TColorDisplay = class(TView)
  protected
    Color: PColorAttr;
    Text: PAnsiChar;
  public
    constructor Create(const Bounds: TRect; const AText: string);
    destructor Destroy; override;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SetColor(AColor: PColorAttr); virtual;
  end;

  { A list of the names of the groups. The list owns the groups and frees them with their items. }
  TColorGroupList = class(TListViewer)
  protected
    Groups: TColorGroup;
  public
    constructor Create(const Bounds: TRect; AScrollBar: TScrollBar; AGroups: TColorGroup); reintroduce;
    destructor Destroy; override;
    procedure FocusItem(ItemIndex: SmallInt); override;
    function GetText(ItemIndex, MaxLen: SmallInt): string; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SetGroupIndex(GroupNum, ItemNum: Byte);
    function GetGroup(GroupNum: Byte): TColorGroup;
    function GetGroupIndex(GroupNum: Byte): Byte;
    function GetNumGroups: Byte;
  end;

  { A list of the names of the items of the chosen group. The items belong to their group. }
  TColorItemList = class(TListViewer)
  protected
    Items: TColorItem;
  public
    constructor Create(const Bounds: TRect; AScrollBar: TScrollBar; AItems: TColorItem); reintroduce;
    procedure FocusItem(ItemIndex: SmallInt); override;
    function GetText(ItemIndex, MaxLen: SmallInt): string; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { The dialog that sets the entries of a palette. }
  TColorDialog = class(TDialog)
  public
    Pal: TPalette;
  protected
    Display: TColorDisplay;
    Groups: TColorGroupList;
    ForLabel: TLabel;
    ForSel: TColorSelector;
    BakLabel: TLabel;
    BakSel: TColorSelector;
    MonoLabel: TLabel;
    MonoSel: TMonoSelector;
    GroupIndex: Byte;
  private
    procedure ApplyData(Rec: Pointer);
  public
    class var Colors: string;
    class var GroupText: string;
    class var ItemText: string;
    class var ForText: string;
    class var BakText: string;
    class var TextText: string;
    class var ColorText: string;
    class var OkText: string;
    class var CancelText: string;
    { The palette APalette is copied; AGroups is released with the dialog. }
    constructor Create(APalette: TPalette; AGroups: TColorGroup); reintroduce;
    destructor Destroy; override;
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SetData(Rec: Pointer); override;
    procedure GetIndexes(var ColIdx: PColorIndex);
    procedure SetIndexes(var ColIdx: PColorIndex);
  end;

{ Chains an item to the last item of a chain, a group to the last group, and an item to the last item of the last
  group; the first operand is the result. }
operator +(First, Second: TColorItem): TColorItem;
operator +(Group: TColorGroup; Item: TColorItem): TColorGroup;
operator +(First, Second: TColorGroup): TColorGroup;

implementation

uses
  TvUtil, Strings, TvKeys;

const
  { Number of swatches in one row of the grid. }
  GridColumns = 2 * 2;

  { The attribute values of the buttons of a TMonoSelector, one character each, in the order of the buttons. }
  MonoColorChars = #$07#$0F#$01#$70#$09;

var
  { The attribute value of each button of a TMonoSelector; the unit fills it from MonoColorChars when it starts. }
  MonoColors: array[0..4] of Byte;
  TableIndex: Integer;

  { The block of indexes that TColorDialog keeps between two dialogs. }
  ColorIndexes: PColorIndex;

{ The attribute of the BIOS value Bios. }
function AttrOfBios(Bios: Integer): TColorAttr;
var
  made: TColorAttr;
begin
  made := TColorAttr.Create(Bios);
  Result := made;
end;

{ The BIOS value of an attribute. }
function BiosOfAttr(const Attr: TColorAttr): Byte;
var
  converted: Byte;
begin
  converted := Attr.ToBIOS;
  Result := converted;
end;

{ The attribute value that the button Item of a TMonoSelector stands for. }
function ButtonValue(Item: Integer): Cardinal;
begin
  Result := MonoColors[Item];
end;

{ The block of characters Source as a string; nil gives an empty string. }
function TextOfBlock(Source: PAnsiChar): string;
begin
  if Source <> nil then
    Result := StrPas(Source)
  else
    Result := '';
end;

{ The text of a name, cut to MaxLen characters. }
function NameText(Source: PAnsiChar; MaxLen: SmallInt): string;
var
  limit: Integer;
begin
  limit := MaxLen;
  if limit < 0 then
    limit := 0;
  Result := Copy(TextOfBlock(Source), 1, limit);
end;

{ The pointer that carries the number Value in a message. }
function PayloadOf(Value: PtrInt): Pointer;
begin
  Result := Pointer(PtrUInt(Value));
end;

{ The group at the position Position of a chain; the first group for a position below 1, nil past the end. }
function GroupAtPosition(First: TColorGroup; Position: Integer): TColorGroup;
var
  remaining: Integer;
begin
  Result := First;
  remaining := Position;
  while (Result <> nil) and (remaining > 0) do
  begin
    Result := Result.Next;
    Dec(remaining);
  end;
end;

{ The item at the position Position of a chain, with the same rule. }
function ItemAtPosition(First: TColorItem; Position: Integer): TColorItem;
var
  remaining: Integer;
begin
  Result := First;
  remaining := Position;
  while (Result <> nil) and (remaining > 0) do
  begin
    Result := Result.Next;
    Dec(remaining);
  end;
end;

function CountItems(First: TColorItem): Integer;
var
  walker: TColorItem;
begin
  Result := 0;
  walker := First;
  while walker <> nil do
  begin
    walker := walker.Next;
    Inc(Result);
  end;
end;

function CountGroups(First: TColorGroup): Integer;
var
  walker: TColorGroup;
begin
  Result := 0;
  walker := First;
  while walker <> nil do
  begin
    walker := walker.Next;
    Inc(Result);
  end;
end;

{ TColorItem }

constructor TColorItem.Create(const AName: string; AIndex: Byte; ANext: TColorItem);
begin
  inherited Create;
  Index := AIndex;
  Next := ANext;
  Name := NewStr(AName);
end;

destructor TColorItem.Destroy;
begin
  if Name <> nil then
    FreeMem(Name);
  inherited Destroy;
end;

{ TColorGroup }

constructor TColorGroup.Create(const AName: string; AItems: TColorItem; ANext: TColorGroup);
begin
  inherited Create;
  Items := AItems;
  Next := ANext;
  Name := NewStr(AName);
end;

destructor TColorGroup.Destroy;
begin
  if Name <> nil then
    FreeMem(Name);
  inherited Destroy;
end;

{ The operators that chain items and groups }

operator +(First, Second: TColorItem): TColorItem;
var
  lastItem: TColorItem;
begin
  lastItem := First;
  while lastItem.Next <> nil do
    lastItem := lastItem.Next;
  lastItem.Next := Second;
  Result := First;
end;

operator +(Group: TColorGroup; Item: TColorItem): TColorGroup;
var
  lastGroup: TColorGroup;
  lastItem: TColorItem;
begin
  lastGroup := Group;
  while lastGroup.Next <> nil do
    lastGroup := lastGroup.Next;

  if lastGroup.Items = nil then
    lastGroup.Items := Item
  else
  begin
    lastItem := lastGroup.Items;
    while lastItem.Next <> nil do
      lastItem := lastItem.Next;
    lastItem.Next := Item;
  end;
  Result := Group;
end;

operator +(First, Second: TColorGroup): TColorGroup;
var
  lastGroup: TColorGroup;
begin
  lastGroup := First;
  while lastGroup.Next <> nil do
    lastGroup := lastGroup.Next;
  lastGroup.Next := Second;
  Result := First;
end;

{ Frees a chain of items. }
procedure FreeItems(First: TColorItem);
var
  current, following: TColorItem;
begin
  current := First;
  while current <> nil do
  begin
    following := current.Next;
    current.Free;
    current := following;
  end;
end;

{ Frees a chain of groups with the items of each. }
procedure FreeGroups(First: TColorGroup);
var
  current, following: TColorGroup;
begin
  current := First;
  while current <> nil do
  begin
    FreeItems(current.Items);
    following := current.Next;
    current.Free;
    current := following;
  end;
end;

{ TColorSelector }

constructor TColorSelector.Create(const Bounds: TRect; ASelType: TColorSel);
begin
  inherited Create(Bounds);
  SelType := ASelType;
  Color := 0;
  EventMask := EventMask or evBroadcast;
  Options := Options or (ofSelectable or ofFirstClick or ofFramed);
end;

procedure TColorSelector.Draw;
var
  lineBuffer: TDrawBuffer;
  rowIndex, columnIndex, swatch, cellStart: Integer;
  grayAttr: TColorAttr;
begin
  grayAttr := AttrOfBios($70);
  lineBuffer := TDrawBuffer.Create;
  try
    lineBuffer.MoveChar(0, ' ', grayAttr, Word(Size.X));
    for rowIndex := 0 to Size.Y do
    begin
      if rowIndex < 4 then
        for columnIndex := 0 to 3 do
        begin
          swatch := rowIndex * 4 + columnIndex;
          cellStart := columnIndex * 3;
          lineBuffer.MoveChar(Word(cellStart), Icon, AttrOfBios(swatch), 3);
          if swatch = Color then
          begin
            lineBuffer.PutChar(Word(cellStart + 1), 8);
            if swatch = 0 then
              lineBuffer.PutAttribute(Word(cellStart + 1), grayAttr);
          end;
        end;
      WriteLine(0, rowIndex, Size.X, 1, lineBuffer);
    end;
  finally
    lineBuffer.Free;
  end;
end;

procedure TColorSelector.ColorChanged;
var
  command: Word;
begin
  if SelType = csForeground then
    command := cmColorForegroundChanged
  else
    command := cmColorBackgroundChanged;
  Message(Owner, evBroadcast, command, PayloadOf(Color));
end;

{ The loop of the mouse: the color under the mouse is chosen while the mouse is in the view and OldColor
  while it is outside. }
procedure TColorSelector.TrackMouse(var Event: TEvent; OldColor: Byte);
var
  position: TPoint;
  swatchRow, swatchColumn: Integer;
  keepGoing: Boolean;
begin
  keepGoing := True;
  while keepGoing do
  begin
    Color := OldColor;
    if MouseInView(Event.Mouse.Where) then
    begin
      position := MakeLocal(Event.Mouse.Where);
      swatchRow := position.Y;
      swatchColumn := position.X div 3;
      Color := Byte(swatchRow * GridColumns + swatchColumn);
    end;
    ColorChanged;
    DrawView;
    keepGoing := MouseEvent(Event, evMouseMove);
  end;
end;

{ Tells whether Event is the broadcast that gives a whole attribute to the selectors. }
function IsColorSetEvent(const Event: TEvent): Boolean;
begin
  Result := False;
  if Event.What <> evBroadcast then
    Exit;
  Result := Event.Message.Command = cmColorSet;
end;

{ Moves the choice for an arrow key; tells whether the key is one of the four arrows. }
function TColorSelector.StepByKey(KeyCode: Word; MaxColor: Integer): Boolean;
var
  start, landing, colorCount, rowShift: Integer;
begin
  Result := True;
  start := Color;
  colorCount := MaxColor + 1;
  rowShift := MaxColor - GridColumns;
  landing := start;
  case CtrlToArrow(KeyCode) of
    kbLeft:
      landing := (start + MaxColor) mod colorCount;
    kbRight:
      landing := (start + 1) mod colorCount;
    kbUp:
      if start = 0 then
        landing := MaxColor
      else if start >= GridColumns then
        landing := start - GridColumns
      else
        landing := start + rowShift;
    kbDown:
      if start = MaxColor then
        landing := 0
      else if start <= rowShift then
        landing := start + GridColumns
      else
        landing := start - rowShift;
  else
    Result := False;
  end;
  if Result then
    Color := Byte(landing);
end;

procedure TColorSelector.HandleEvent(var Event: TEvent);
var
  startColor, attrByte: Byte;
  limit: Integer;
  changedByUser: Boolean;
begin
  inherited HandleEvent(Event);

  startColor := Color;
  limit := 15;
  if SelType = csBackground then
    limit := 7;

  if IsColorSetEvent(Event) then
  begin
    attrByte := Event.Message.InfoByte;
    case SelType of
      csBackground: Color := attrByte shr 4;
      csForeground: Color := attrByte and $0F;
    end;
    DrawView;
    Exit;
  end;

  changedByUser := False;
  case Event.What of
    evMouseDown:
      begin
        TrackMouse(Event, startColor);
        changedByUser := True;
      end;
    evKeyDown:
      changedByUser := StepByKey(Event.KeyDown.KeyCode, limit);
  end;
  if not changedByUser then
    Exit;

  DrawView;
  ColorChanged;
  ClearEvent(Event);
end;

{ TMonoSelector }

constructor TMonoSelector.Create(const Bounds: TRect);
var
  names: array[0..3] of string;
  position: Integer;
  head: TSItem;
begin
  names[0] := Normal;
  names[1] := Highlight;
  names[2] := Underline;
  names[3] := Inverse;
  head := nil;
  position := 4;
  while position > 0 do
  begin
    Dec(position);
    head := TSItem.Create(names[position], head);
  end;
  inherited Create(Bounds, head);
  EventMask := EventMask or evBroadcast;
end;

procedure TMonoSelector.Draw;
var
  markerChar: Char;
begin
  markerChar := Chr(7);
  DrawBox(Button, markerChar);
end;

procedure TMonoSelector.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if IsColorSetEvent(Event) then
  begin
    Value := Cardinal(Event.Message.InfoByte);
    DrawView;
  end;
end;

function TMonoSelector.Mark(Item: Integer): Boolean;
begin
  Result := Value = ButtonValue(Item);
end;

procedure TMonoSelector.NewColor;
const
  Commands: array[0..1] of Word = (cmColorForegroundChanged, cmColorBackgroundChanged);
var
  half: Integer;
  nibble: PtrInt;
begin
  for half := 0 to 1 do
  begin
    nibble := PtrInt((Value shr (half * 4)) and $0F);
    Message(Owner, evBroadcast, Commands[half], PayloadOf(nibble));
  end;
end;

procedure TMonoSelector.Press(Item: Integer);
begin
  Value := ButtonValue(Item);
  NewColor;
end;

procedure TMonoSelector.MovedTo(Item: Integer);
begin
  Value := ButtonValue(Item);
  NewColor;
end;

{ TColorDisplay }

constructor TColorDisplay.Create(const Bounds: TRect; const AText: string);
begin
  inherited Create(Bounds);
  EventMask := EventMask or evBroadcast;
  Color := nil;
  Text := NewStr(AText);
end;

destructor TColorDisplay.Destroy;
var
  block: PAnsiChar;
begin
  block := Text;
  Text := nil;
  if block <> nil then
    FreeMem(block);
  inherited Destroy;
end;

procedure TColorDisplay.Draw;
var
  shownAttr: TColorAttr;
  lineBuffer: TDrawBuffer;
  content: string;
  textWidth, repeatCount, copyIndex: Integer;
begin
  shownAttr := Color^;
  if shownAttr = 0 then
    shownAttr := ErrorAttr;

  content := TextOfBlock(Text);
  textWidth := Strwidth(content);
  repeatCount := Size.X div textWidth;
  lineBuffer := TDrawBuffer.Create;
  try
    for copyIndex := 0 to repeatCount do
      lineBuffer.MoveStr(Word(copyIndex * textWidth), content, shownAttr);
    WriteLine(0, 0, Size.X, Size.Y, lineBuffer);
  finally
    lineBuffer.Free;
  end;
end;

procedure TColorDisplay.HandleEvent(var Event: TEvent);
var
  currentBios, updatedBios: Integer;
begin
  inherited HandleEvent(Event);
  if Event.What <> evBroadcast then
    Exit;
  case Event.Message.Command of
    cmColorBackgroundChanged:
      begin
        currentBios := BiosOfAttr(Color^);
        updatedBios := (currentBios and $0F) or ((Integer(Event.Message.InfoByte) shl 4) and $F0);
        Color^ := AttrOfBios(updatedBios);
        DrawView;
      end;
    cmColorForegroundChanged:
      begin
        currentBios := BiosOfAttr(Color^);
        updatedBios := (currentBios and $F0) or (Event.Message.InfoByte and $0F);
        Color^ := AttrOfBios(updatedBios);
        DrawView;
      end;
  end;
end;

procedure TColorDisplay.SetColor(AColor: PColorAttr);
var
  currentBios: Byte;
begin
  Color := AColor;
  currentBios := BiosOfAttr(Color^);
  Message(Owner, evBroadcast, cmColorSet, PayloadOf(currentBios));
  DrawView;
end;

{ TColorGroupList }

constructor TColorGroupList.Create(const Bounds: TRect; AScrollBar: TScrollBar; AGroups: TColorGroup);
begin
  inherited Create(Bounds, 1, nil, AScrollBar);
  Groups := AGroups;
  SetRange(CountGroups(AGroups));
end;

destructor TColorGroupList.Destroy;
begin
  FreeGroups(Groups);
  inherited Destroy;
end;

procedure TColorGroupList.FocusItem(ItemIndex: SmallInt);
var
  chosenGroup: TColorGroup;
begin
  inherited FocusItem(ItemIndex);
  chosenGroup := GroupAtPosition(Groups, ItemIndex);
  if chosenGroup = nil then
    Exit;
  Message(Owner, evBroadcast, cmNewColorItem, chosenGroup);
end;

function TColorGroupList.GetText(ItemIndex, MaxLen: SmallInt): string;
var
  chosenGroup: TColorGroup;
begin
  Result := '';
  chosenGroup := GroupAtPosition(Groups, ItemIndex);
  if chosenGroup = nil then
    Exit;
  Result := NameText(chosenGroup.Name, MaxLen);
end;

procedure TColorGroupList.HandleEvent(var Event: TEvent);
var
  asksToSave: Boolean;
  focusedGroup: Byte;
begin
  inherited HandleEvent(Event);
  asksToSave := (Event.What = evBroadcast) and (Event.Message.Command = cmSaveColorIndex);
  if not asksToSave then
    Exit;
  focusedGroup := Byte(Focused);
  SetGroupIndex(focusedGroup, Event.Message.InfoByte);
end;

procedure TColorGroupList.SetGroupIndex(GroupNum, ItemNum: Byte);
var
  targetGroup: TColorGroup;
  position: Byte;
  walker: TColorItem;
begin
  targetGroup := GetGroup(GroupNum);
  if targetGroup = nil then
    Exit;
  position := 0;
  walker := targetGroup.Items;
  if walker <> nil then
    while position < ItemNum do
    begin
      walker := walker.Next;
      if walker = nil then
        Break;
      Inc(position);
    end;
  targetGroup.Index := position;
end;

function TColorGroupList.GetGroupIndex(GroupNum: Byte): Byte;
var
  targetGroup: TColorGroup;
begin
  Result := 0;
  targetGroup := GetGroup(GroupNum);
  if targetGroup <> nil then
    Result := targetGroup.Index;
end;

function TColorGroupList.GetGroup(GroupNum: Byte): TColorGroup;
begin
  Result := GroupAtPosition(Groups, GroupNum);
end;

function TColorGroupList.GetNumGroups: Byte;
var
  walker: TColorGroup;
begin
  Result := 0;
  walker := Groups;
  while walker <> nil do
  begin
    walker := walker.Next;
    Inc(Result);
  end;
end;

{ TColorItemList }

constructor TColorItemList.Create(const Bounds: TRect; AScrollBar: TScrollBar; AItems: TColorItem);
begin
  inherited Create(Bounds, 1, nil, AScrollBar);
  Items := AItems;
  EventMask := EventMask or evBroadcast;
  SetRange(CountItems(AItems));
end;

procedure TColorItemList.FocusItem(ItemIndex: SmallInt);
var
  chosenItem: TColorItem;
begin
  inherited FocusItem(ItemIndex);
  Message(Owner, evBroadcast, cmSaveColorIndex, PayloadOf(ItemIndex));

  chosenItem := ItemAtPosition(Items, ItemIndex);
  if chosenItem = nil then
    Exit;
  Message(Owner, evBroadcast, cmNewColorIndex, PayloadOf(chosenItem.Index));
end;

function TColorItemList.GetText(ItemIndex, MaxLen: SmallInt): string;
var
  chosenItem: TColorItem;
begin
  Result := '';
  chosenItem := ItemAtPosition(Items, ItemIndex);
  if chosenItem = nil then
    Exit;
  Result := NameText(chosenItem.Name, MaxLen);
end;

procedure TColorItemList.HandleEvent(var Event: TEvent);
var
  newGroup: TColorGroup;
begin
  inherited HandleEvent(Event);
  if Event.What <> evBroadcast then
    Exit;
  if Event.Message.Command <> cmNewColorItem then
    Exit;
  newGroup := TColorGroup(Event.Message.InfoPtr);
  Items := newGroup.Items;
  SetRange(CountItems(Items));
  FocusItem(newGroup.Index);
  DrawView;
end;

{ TColorDialog }

constructor TColorDialog.Create(APalette: TPalette; AGroups: TColorGroup);
var
  scrollBar: TScrollBar;
  itemList: TView;
begin
  inherited Create(TRect.Create(0, 0, 61, 18), Colors);
  Options := Options or ofCentered;
  if APalette <> nil then
  begin
    Pal := TPalette.Create('', 0);
    Pal.Assign(APalette);
  end
  else
    Pal := nil;

  scrollBar := TScrollBar.Create(TRect.Create(18, 3, 19, 14));
  Insert(scrollBar);

  Groups := TColorGroupList.Create(TRect.Create(3, 3, 18, 14), scrollBar, AGroups);
  Insert(Groups);
  Insert(TLabel.Create(TRect.Create(2, 2, 8, 3), GroupText, Groups));

  scrollBar := TScrollBar.Create(TRect.Create(41, 3, 42, 14));
  Insert(scrollBar);

  itemList := TColorItemList.Create(TRect.Create(21, 3, 41, 14), scrollBar, AGroups.Items);
  Insert(itemList);
  Insert(TLabel.Create(TRect.Create(20, 2, 25, 3), ItemText, itemList));

  ForSel := TColorSelector.Create(TRect.Create(45, 3, 57, 7), csForeground);
  Insert(ForSel);
  ForLabel := TLabel.Create(TRect.Create(45, 2, 57, 3), ForText, ForSel);
  Insert(ForLabel);

  BakSel := TColorSelector.Create(TRect.Create(45, 9, 57, 11), csBackground);
  Insert(BakSel);
  BakLabel := TLabel.Create(TRect.Create(45, 8, 57, 9), BakText, BakSel);
  Insert(BakLabel);

  Display := TColorDisplay.Create(TRect.Create(44, 12, 58, 14), TextText);
  Insert(Display);

  MonoSel := TMonoSelector.Create(TRect.Create(44, 3, 59, 7));
  MonoSel.Hide;
  Insert(MonoSel);
  MonoLabel := TLabel.Create(TRect.Create(43, 2, 49, 3), ColorText, MonoSel);
  MonoLabel.Hide;
  Insert(MonoLabel);

  Insert(TButton.Create(TRect.Create(36, 15, 46, 17), OkText, cmOK, bfDefault));
  Insert(TButton.Create(TRect.Create(48, 15, 58, 17), CancelText, cmCancel, bfNormal));
  SelectNext(False);

  if Pal <> nil then
    ApplyData(Pal);
end;

destructor TColorDialog.Destroy;
begin
  Pal.Free;
  inherited Destroy;
end;

procedure TColorDialog.HandleEvent(var Event: TEvent);
var
  announcesGroup, announcesEntry: Boolean;
  entryNumber: Byte;
begin
  announcesGroup := (Event.What = evBroadcast) and (Event.Message.Command = cmNewColorItem);
  if announcesGroup then
    GroupIndex := Byte(Groups.Focused);
  inherited HandleEvent(Event);
  announcesEntry := (Event.What = evBroadcast) and (Event.Message.Command = cmNewColorIndex);
  if not announcesEntry then
    Exit;
  entryNumber := Event.Message.InfoByte;
  Display.SetColor(@Pal.Data[entryNumber]);
end;

function TColorDialog.DataSize: Word;
begin
  Result := Word(BiosOfAttr(Pal.Data[0]) + 1);
end;

procedure TColorDialog.GetData(Rec: Pointer);
begin
  GetIndexes(ColorIndexes);
  TPalette(Rec).Assign(Pal);
end;

procedure TColorDialog.SetData(Rec: Pointer);
begin
  ApplyData(Rec);
end;

{ The body of SetData, which the constructor calls for the palette that it was given. }
procedure TColorDialog.ApplyData(Rec: Pointer);
var
  paletteEntry: Byte;
begin
  if Pal = nil then
    Pal := TPalette.Create('', 0);
  Pal.Assign(TPalette(Rec));

  SetIndexes(ColorIndexes);
  paletteEntry := Groups.GetGroupIndex(GroupIndex);
  Display.SetColor(@Pal.Data[paletteEntry]);
  Groups.FocusItem(GroupIndex);
  if ShowMarkers then
  begin
    ForLabel.Hide;
    ForSel.Hide;
    BakLabel.Hide;
    BakSel.Hide;
    MonoLabel.Show;
    MonoSel.Show;
  end;
  Groups.Select;
end;

procedure TColorDialog.SetIndexes(var ColIdx: PColorIndex);
var
  groupCount, position: Byte;
  needsNewBlock: Boolean;
begin
  groupCount := Groups.GetNumGroups;
  if (ColIdx <> nil) and (ColIdx^.ColorSize <> groupCount) then
  begin
    FreeMem(ColIdx);
    ColIdx := nil;
  end;
  needsNewBlock := ColIdx = nil;
  if needsNewBlock then
  begin
    GetMem(ColIdx, Integer(groupCount) + 2);
    ColIdx^.GroupIndex := 0;
    FillChar(ColIdx^.ColorIndex, groupCount, 0);
    ColIdx^.ColorSize := groupCount;
  end;
  position := 0;
  while position < groupCount do
  begin
    Groups.SetGroupIndex(position, ColIdx^.ColorIndex[position]);
    Inc(position);
  end;

  GroupIndex := ColIdx^.GroupIndex;
end;

procedure TColorDialog.GetIndexes(var ColIdx: PColorIndex);
var
  groupCount, position: Byte;
begin
  groupCount := Groups.GetNumGroups;
  if ColIdx = nil then
  begin
    GetMem(ColIdx, Integer(groupCount) + 2);
    FillChar(ColIdx^.ColorIndex, groupCount, 0);
    ColIdx^.ColorSize := groupCount;
  end;
  ColIdx^.GroupIndex := GroupIndex;
  position := 0;
  while position < groupCount do
  begin
    ColIdx^.ColorIndex[position] := Groups.GetGroupIndex(position);
    Inc(position);
  end;
end;

initialization
  for TableIndex := 0 to High(MonoColors) do
    MonoColors[TableIndex] := Ord(MonoColorChars[TableIndex + 1]);
  TColorSelector.Icon := #$DB;
  TMonoSelector.Button := ' ( ) ';
  TMonoSelector.Normal := 'Normal';
  TMonoSelector.Highlight := 'Highlight';
  TMonoSelector.Underline := 'Underline';
  TMonoSelector.Inverse := 'Inverse';
  TColorDialog.Colors := 'Colors';
  TColorDialog.GroupText := '~G~roup';
  TColorDialog.ItemText := '~I~tem';
  TColorDialog.ForText := '~F~oreground';
  TColorDialog.BakText := '~B~ackground';
  TColorDialog.TextText := 'Text ';
  TColorDialog.ColorText := 'Color';
  TColorDialog.OkText := 'O~K~';
  TColorDialog.CancelText := 'Cancel';
  ColorIndexes := nil;

finalization
  if ColorIndexes <> nil then
    FreeMem(ColorIndexes);

end.
