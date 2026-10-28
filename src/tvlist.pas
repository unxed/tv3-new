{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/views.h (TListViewer), include/tvision/dialogs.h (TListBox, TListBoxRec),
  include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h, include/tvision/util.h,
  source/tvision/tlstview.cpp, source/tvision/tlistbox.cpp, source/tvision/tvtext1.cpp (specialChars),
  source/tvision/misc.cpp (message), source/tvision/tvtext2.cpp (emptyText)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit.

  message() sends a message to a view; it is Message of TvViews.

  The text that a list viewer shows for an item is returned by GetText as a string, in the place of the buffer and
  the length that the C++ takes; MaxLen is the largest length of the text. The items of a TListBox are blocks of
  characters with a terminating zero, as the C++ keeps them.

  The static member emptyText of TListViewer is the class variable EmptyText, which holds the text of the C++ when
  the unit starts. The array specialChars,
  which tvtext1.cpp defines, is kept inside the unit as the table of the markers; the palette of the list viewer is
  made when the unit starts and released when it ends. }
unit TvList;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvObjs, TvViews, TvWindow;

const
  { The palette of a list viewer: 1 active, 2 inactive, 3 focused, 4 selected, 5 divider. }
  cpListViewer = #26#26#27#28#29;

type
  { A view that shows the items of a list in one or more columns and moves a focus over them. The items themselves
    are given by GetText of a class below it. }
  TListViewer = class(TView)
  public
    HScrollBar: TScrollBar;
    VScrollBar: TScrollBar;
    NumCols: SmallInt;
    TopItem: SmallInt;
    Focused: SmallInt;
    Range: SmallInt;
    { The text that is shown in the first row of a list that has no item. }
    class var EmptyText: string;
  private
    procedure ShowBarWhenLive(Bar: TScrollBar);
    function DragTarget(const MousePos: TPoint; const Event: TEvent; var AutoCount: Integer;
      Current: SmallInt): SmallInt;
    function KeyTarget(KeyCode: Word; out Target: SmallInt): Boolean;
    procedure HandleMouseDown(var Event: TEvent);
    procedure HandleKeyDown(var Event: TEvent);
    procedure HandleBroadcast(var Event: TEvent);
  public
    constructor Create(const Bounds: TRect; NumberOfColumns: Word; HorizontalBar, VerticalBar: TScrollBar);
    procedure ChangeBounds(const Bounds: TRect); override;
    procedure Draw; override;
    procedure FocusItem(ItemIndex: SmallInt); virtual;
    function GetPalette: TPalette; override;
    function GetText(ItemIndex, MaxLen: SmallInt): string; virtual;
    function IsSelected(ItemIndex: SmallInt): Boolean; virtual;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SelectItem(ItemIndex: SmallInt); virtual;
    procedure SetRange(NewRange: SmallInt);
    procedure SetState(StateBits: Word; TurnOn: Boolean); override;
    procedure FocusItemNum(ItemIndex: SmallInt); virtual;
    procedure ShutDown; override;
  end;

  { The data record of a TListBox: the list and the number of the focused item. }
  TListBoxRec = record
    Items: TCollection;
    Selection: Word;
  end;
  PListBoxRec = ^TListBoxRec;

  { A list viewer whose items are the blocks of characters of a collection. The collection belongs to the list box
    until another list is given; the destructor does not free it. }
  TListBox = class(TListViewer)
  protected
    Items: TCollection;
  public
    constructor Create(const Bounds: TRect; NumberOfColumns: Word; VerticalBar: TScrollBar); reintroduce;
    destructor Destroy; override;
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    function GetText(ItemIndex, MaxLen: SmallInt): string; override;
    procedure NewList(NewItems: TCollection); virtual;
    procedure SetData(Rec: Pointer); override;
    function List: TCollection;
  end;

implementation

uses
  TvKeys;

const
  { The characters that mark an item, from the table specialChars: for the focused item, for a selected item and
    for any other item, each as the left mark and the right mark. }
  ListMarkers: array[0..5] of Byte = (175, 174, 26, 27, 32, 32);

  { The character of the divider between two columns. }
  DividerCode = 179;

  { The number of automatic mouse events outside the view that move the focus by one step. }
  AutosPerStep = 4;

var
  ListViewerPalette: TPalette;

{ Tells whether any bit of Mask is set in Bits. }
function AnyBit(Bits, Mask: Word): Boolean;
begin
  Result := (Bits and Mask) <> 0;
end;

{ The low attribute of the color of the entry Entry of the palette of a view. }
function LowAttr(Viewer: TView; Entry: Word): TColorAttr;
var
  pair: TAttrPair;
begin
  pair := Viewer.GetColor(Entry);
  Result := pair.Attrs[0];
end;

{ TListViewer }

constructor TListViewer.Create(const Bounds: TRect; NumberOfColumns: Word; HorizontalBar, VerticalBar: TScrollBar);
var
  pageStep, arrowStep: Integer;
begin
  inherited Create(Bounds);
  NumCols := NumberOfColumns;
  TopItem := 0;
  Focused := 0;
  Range := 0;

  Options := Options or ofFirstClick or ofSelectable;
  EventMask := EventMask or evBroadcast;

  if VerticalBar <> nil then
  begin
    if NumCols = 1 then
    begin
      pageStep := Size.Y - 1;
      arrowStep := 1;
    end
    else
    begin
      pageStep := Size.Y * NumCols;
      arrowStep := Size.Y;
    end;
    VerticalBar.SetStep(pageStep, arrowStep);
  end;

  if HorizontalBar <> nil then
    HorizontalBar.SetStep(Size.X div NumCols, 1);

  HScrollBar := HorizontalBar;
  VScrollBar := VerticalBar;
end;

procedure TListViewer.ChangeBounds(const Bounds: TRect);
begin
  inherited ChangeBounds(Bounds);
  if HScrollBar <> nil then
    HScrollBar.SetStep(Size.X div NumCols, HScrollBar.ArStep);
  if VScrollBar <> nil then
    VScrollBar.SetStep(Size.Y, VScrollBar.ArStep);
end;

procedure TListViewer.Draw;
var
  lineBuffer: TDrawBuffer;
  normalColor, selectedColor, focusedColor, cellColor: TColorAttr;
  isLive, cursorShown, hasFocusMark: Boolean;
  columnWidth, cellLeft, textShift, markerIndex: Integer;
  row, column, itemIndex: Integer;
  itemText: string;
begin
  isLive := (State and (sfSelected or sfActive)) = (sfSelected or sfActive);
  if isLive then
  begin
    normalColor := LowAttr(Self, 1);
    focusedColor := LowAttr(Self, 3);
    selectedColor := LowAttr(Self, 4);
  end
  else
  begin
    normalColor := LowAttr(Self, 2);
    selectedColor := LowAttr(Self, 4);
    FillChar(focusedColor, SizeOf(focusedColor), 0);
  end;

  if HScrollBar <> nil then
    textShift := HScrollBar.Value
  else
    textShift := 0;

  cursorShown := False;
  columnWidth := Size.X div NumCols + 1;
  lineBuffer := TDrawBuffer.Create;
  try
    row := 0;
    while row < Size.Y do
    begin
      column := 0;
      while column < NumCols do
      begin
        itemIndex := column * Size.Y + row + TopItem;
        cellLeft := column * columnWidth;
        hasFocusMark := isLive and (Focused = itemIndex) and (Range > 0);
        if hasFocusMark then
        begin
          cellColor := focusedColor;
          SetCursor(cellLeft + 1, row);
          markerIndex := 0;
          cursorShown := True;
        end
        else if (itemIndex < Range) and IsSelected(itemIndex) then
        begin
          cellColor := selectedColor;
          markerIndex := 2;
        end
        else
        begin
          cellColor := normalColor;
          markerIndex := 4;
        end;

        lineBuffer.MoveChar(cellLeft, ' ', cellColor, columnWidth);
        if itemIndex < Range then
        begin
          if textShift < 255 then
          begin
            itemText := GetText(itemIndex, 255);
            lineBuffer.MoveStr(cellLeft + 1, itemText, cellColor, columnWidth, textShift);
          end;
          if ShowMarkers then
          begin
            lineBuffer.PutChar(cellLeft, ListMarkers[markerIndex]);
            lineBuffer.PutChar(cellLeft + columnWidth - 2, ListMarkers[markerIndex + 1]);
          end;
        end
        else if (row = 0) and (column = 0) then
          lineBuffer.MoveStr(cellLeft + 1, EmptyText, LowAttr(Self, 1));

        lineBuffer.MoveChar(cellLeft + columnWidth - 1, Chr(DividerCode), LowAttr(Self, 5), 1);
        Inc(column);
      end;
      WriteLine(0, row, Size.X, 1, lineBuffer);
      Inc(row);
    end;
  finally
    lineBuffer.Free;
  end;

  if not cursorShown then
    SetCursor(-1, -1);
end;

procedure TListViewer.FocusItem(ItemIndex: SmallInt);
var
  pageItems: Integer;
begin
  Focused := ItemIndex;
  if VScrollBar <> nil then
    VScrollBar.SetValue(ItemIndex)
  else
    DrawView;

  if Size.Y <= 0 then
    Exit;
  pageItems := Size.Y * NumCols;
  if ItemIndex < TopItem then
  begin
    if NumCols = 1 then
      TopItem := ItemIndex
    else
      TopItem := ItemIndex - ItemIndex mod Size.Y;
  end
  else if ItemIndex >= TopItem + pageItems then
  begin
    if NumCols = 1 then
      TopItem := ItemIndex - Size.Y + 1
    else
      TopItem := ItemIndex - ItemIndex mod Size.Y - Size.Y * (NumCols - 1);
  end;
end;

procedure TListViewer.FocusItemNum(ItemIndex: SmallInt);
var
  clampedIndex: SmallInt;
begin
  clampedIndex := ItemIndex;
  if clampedIndex < 0 then
    clampedIndex := 0
  else if (clampedIndex >= Range) and (Range > 0) then
    clampedIndex := Range - 1;

  if Range <> 0 then
    FocusItem(clampedIndex);
end;

function TListViewer.GetPalette: TPalette;
begin
  Result := ListViewerPalette;
end;

function TListViewer.GetText(ItemIndex, MaxLen: SmallInt): string;
begin
  Result := '';
end;

function TListViewer.IsSelected(ItemIndex: SmallInt): Boolean;
begin
  Result := ItemIndex = Focused;
end;

{ The item that a mouse outside the view asks for, or Current while it asks for none. Every AutosPerStep-th
  automatic event moves the focus; AutoCount counts them. }
function TListViewer.DragTarget(const MousePos: TPoint; const Event: TEvent; var AutoCount: Integer;
  Current: SmallInt): SmallInt;
var
  columnStart: Integer;
begin
  Result := Current;
  if Event.What = evMouseAuto then
    Inc(AutoCount);
  if AutoCount <> AutosPerStep then
    Exit;
  AutoCount := 0;

  if NumCols = 1 then
  begin
    if MousePos.Y < 0 then
      Result := Focused - 1
    else if MousePos.Y >= Size.Y then
      Result := Focused + 1;
    Exit;
  end;

  columnStart := Focused - Focused mod Size.Y;
  if MousePos.X < 0 then
    Result := Focused - Size.Y
  else if MousePos.X >= Size.X then
    Result := Focused + Size.Y
  else if MousePos.Y < 0 then
    Result := columnStart
  else if MousePos.Y > Size.Y then
    Result := columnStart + Size.Y - 1;
end;

{ The item that a key moves the focus to; False when the key does not move it. }
function TListViewer.KeyTarget(KeyCode: Word; out Target: SmallInt): Boolean;
var
  pageItems: Integer;
begin
  Result := True;
  Target := 0;
  pageItems := Size.Y * NumCols;
  case CtrlToArrow(KeyCode) of
    kbUp:
      Target := Focused - 1;
    kbDown:
      Target := Focused + 1;
    kbRight:
      begin
        Result := NumCols > 1;
        if Result then
          Target := Focused + Size.Y;
      end;
    kbLeft:
      begin
        Result := NumCols > 1;
        if Result then
          Target := Focused - Size.Y;
      end;
    kbPgDn:
      Target := Focused + pageItems;
    kbPgUp:
      Target := Focused - pageItems;
    kbHome:
      Target := TopItem;
    kbEnd:
      Target := TopItem + pageItems - 1;
    kbCtrlPgDn:
      Target := Range - 1;
    kbCtrlPgUp:
      Target := 0;
  else
    Result := False;
  end;
end;

procedure TListViewer.HandleMouseDown(var Event: TEvent);
var
  localSpot: TPoint;
  slotWidth, outsideTicks: Integer;
  previousItem, targetItem: SmallInt;
  keepTracking: Boolean;
begin
  targetItem := 0;
  slotWidth := Size.X div NumCols + 1;
  previousItem := Focused;
  outsideTicks := 0;
  keepTracking := True;
  while keepTracking do
  begin
    localSpot := MakeLocal(Event.Mouse.Where);
    if not MouseInView(Event.Mouse.Where) then
      targetItem := DragTarget(localSpot, Event, outsideTicks, targetItem)
    else
    begin
      targetItem := TopItem + localSpot.Y;
      Inc(targetItem, Size.Y * (localSpot.X div slotWidth));
    end;

    if targetItem <> previousItem then
    begin
      FocusItemNum(targetItem);
      DrawView;
    end;
    previousItem := targetItem;
    if AnyBit(Event.Mouse.EventFlags, meDoubleClick) then
      keepTracking := False
    else
      keepTracking := MouseEvent(Event, evMouseMove or evMouseAuto);
  end;

  FocusItemNum(targetItem);
  DrawView;
  if AnyBit(Event.Mouse.EventFlags, meDoubleClick) then
    if Range > targetItem then
      SelectItem(targetItem);
  ClearEvent(Event);
end;

procedure TListViewer.HandleKeyDown(var Event: TEvent);
var
  destination: SmallInt;
  spacePressed, canSelect: Boolean;
begin
  destination := 0;
  spacePressed := Event.KeyDown.CharScan.CharCode = Ord(' ');
  canSelect := spacePressed and (Focused < Range);
  if canSelect then
  begin
    SelectItem(Focused);
    destination := Focused;
  end
  else
  begin
    if not KeyTarget(Event.KeyDown.KeyCode, destination) then
      Exit;
  end;

  FocusItemNum(destination);
  DrawView;
  ClearEvent(Event);
end;

procedure TListViewer.HandleBroadcast(var Event: TEvent);
var
  sender: Pointer;
  command: Word;
  fromOwnBar: Boolean;
begin
  if not AnyBit(Options, ofSelectable) then
    Exit;
  command := Event.Message.Command;
  sender := Event.Message.InfoPtr;
  fromOwnBar := (sender = Pointer(HScrollBar)) or (sender = Pointer(VScrollBar));

  if (command = cmScrollBarClicked) and fromOwnBar then
    Select
  else if command = cmScrollBarChanged then
  begin
    if sender = Pointer(VScrollBar) then
    begin
      FocusItemNum(VScrollBar.Value);
      DrawView;
    end
    else if sender = Pointer(HScrollBar) then
      DrawView;
  end;
end;

procedure TListViewer.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      HandleMouseDown(Event);
    evKeyDown:
      HandleKeyDown(Event);
    evBroadcast:
      HandleBroadcast(Event);
  end;
end;

procedure TListViewer.SelectItem(ItemIndex: SmallInt);
begin
  Message(Owner, evBroadcast, cmListItemSelected, Self);
end;

procedure TListViewer.SetRange(NewRange: SmallInt);
begin
  Range := NewRange;
  if Focused >= NewRange then
    Focused := 0;
  if VScrollBar <> nil then
    VScrollBar.SetParams(Focused, 0, NewRange - 1, VScrollBar.PgStep, VScrollBar.ArStep)
  else
    DrawView;
end;

{ Shows Bar while the view is active and visible, and hides it otherwise. }
procedure TListViewer.ShowBarWhenLive(Bar: TScrollBar);
begin
  if Bar = nil then
    Exit;
  if GetState(sfActive) and GetState(sfVisible) then
    Bar.Show
  else
    Bar.Hide;
end;

procedure TListViewer.SetState(StateBits: Word; TurnOn: Boolean);
begin
  inherited SetState(StateBits, TurnOn);
  if not AnyBit(StateBits, sfSelected or sfActive or sfVisible) then
    Exit;
  ShowBarWhenLive(HScrollBar);
  ShowBarWhenLive(VScrollBar);
  DrawView;
end;

procedure TListViewer.ShutDown;
begin
  HScrollBar := nil;
  VScrollBar := nil;
  inherited ShutDown;
end;

{ TListBox }

constructor TListBox.Create(const Bounds: TRect; NumberOfColumns: Word; VerticalBar: TScrollBar);
begin
  inherited Create(Bounds, NumberOfColumns, nil, VerticalBar);
  Items := nil;
  SetRange(0);
end;

destructor TListBox.Destroy;
begin
  inherited Destroy;
end;

function TListBox.DataSize: Word;
begin
  Result := SizeOf(TListBoxRec);
end;

procedure TListBox.GetData(Rec: Pointer);
var
  dataRec: PListBoxRec;
begin
  dataRec := PListBoxRec(Rec);
  dataRec^.Items := Items;
  dataRec^.Selection := Word(Focused);
end;

function TListBox.GetText(ItemIndex, MaxLen: SmallInt): string;
var
  source: PAnsiChar;
  textLength: Integer;
begin
  Result := '';
  if Items = nil then
    Exit;
  source := PAnsiChar(Items.At(ItemIndex));
  if source = nil then
    Exit;
  textLength := 0;
  while (textLength < MaxLen) and (source[textLength] <> #0) do
    Inc(textLength);
  SetString(Result, source, textLength);
end;

procedure TListBox.NewList(NewItems: TCollection);
var
  itemCount: Integer;
begin
  TvObject.DestroyObject(Items);
  itemCount := 0;
  if NewItems <> nil then
    itemCount := NewItems.GetCount;
  Items := NewItems;
  SetRange(SmallInt(itemCount));
  if Range <= 0 then
  begin
    DrawView;
    Exit;
  end;
  FocusItem(0);
  DrawView;
end;

procedure TListBox.SetData(Rec: Pointer);
var
  dataRec: PListBoxRec;
begin
  dataRec := PListBoxRec(Rec);
  NewList(dataRec^.Items);
  FocusItem(SmallInt(dataRec^.Selection));
  DrawView;
end;

function TListBox.List: TCollection;
begin
  Result := Items;
end;

initialization
  TListViewer.EmptyText := '<empty>';
  ListViewerPalette := TPalette.Create(cpListViewer, Length(cpListViewer));

finalization
  ListViewerPalette.Free;

end.
