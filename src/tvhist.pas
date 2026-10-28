{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (THistoryViewer, THistInit, THistoryWindow, THistory),
  include/tvision/views.h, include/tvision/ttypes.h, include/tvision/tv.h, include/tvision/config.h,
  source/tvision/histlist.cpp, source/tvision/thistory.cpp, source/tvision/thistwin.cpp, source/tvision/thstview.cpp,
  source/tvision/tvtext1.cpp (the icon of THistory)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructor with StreamableInit, belong to a later
  unit.

  The history lists are kept in one block of bytes, as histlist.cpp keeps them: a record is the byte id, the byte
  length, the text and a zero, and the records of all lists follow one another in the order in which they were
  added. A record is known by its offset in the block, and the offset -1 stands for the null pointer.

  Parts of the C++ that have no unit yet:
    - strnzcpy, which THistory uses to put the chosen text into the line, is not defined by the sources of this
      unit; StrNZCopyHook stands for it, and while it is nil the line keeps its text.
    - strwidth is the width of TText of TvUtf8, and ctrlToArrow is the function of TvKeys.

  When the unit starts it gives InitHistory and DoneHistory to InitHistoryHook and DoneHistoryHook of TvApp, which
  stand for initHistory and doneHistory in the constructor and the destructor of TApplication. }
unit TvHist;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvViews, TvWindow, TvList, TvInput;

const
  { The palette of THistory: 1 arrow, 2 sides. }
  cpHistory = #22#23;
  { The palette of THistoryViewer: 1 active, 2 inactive, 3 focused, 4 selected, 5 divider. }
  cpHistoryViewer = #6#6#7#6#6;
  { The palette of THistoryWindow: 1 frame passive, 2 frame active, 3 frame icon, 4 scroll bar page area,
    5 scroll bar controls, 6 viewer normal text, 7 viewer selected text. }
  cpHistoryWindow = #19#19#21#24#23#19#20;

type
  { Copies Source into a buffer of BufferSize bytes that ends with a zero, and gives the text that the buffer
    holds. }
  TStrNZCopyFunc = function(const Source: string; BufferSize: Integer): string;

  { The function that makes the list viewer of a history window. }
  TCreateListViewerFunc = function(Area: TRect; Win: TWindow; HistoryId: Word): TListViewer;

  { The list of the entries of one history list. }
  THistoryViewer = class(TListViewer)
  protected
    HistoryId: Word;
  public
    constructor Create(const Bounds: TRect; HorizontalBar, VerticalBar: TScrollBar; AHistoryId: Word); reintroduce;
    function GetPalette: TPalette; override;
    function GetText(ItemIndex, MaxLen: SmallInt): string; override;
    procedure HandleEvent(var Event: TEvent); override;
    function HistoryWidth: Integer;
  end;

  { Holds the function that makes the list viewer of a history window. It is the class between TWindow and
    THistoryWindow. }
  THistInit = class(TWindow)
  protected
    CreateListViewer: TCreateListViewerFunc;
  public
    constructor Create(const Bounds: TRect; ListViewerMaker: TCreateListViewerFunc); reintroduce;
  end;

  { The window that shows a history list. }
  THistoryWindow = class(THistInit)
  protected
    Viewer: TListViewer;
  public
    constructor Create(const Bounds: TRect; AHistoryId: Word); reintroduce;
    function GetPalette: TPalette; override;
    { The text of the focused entry of the viewer, at most 255 bytes long. }
    function GetSelection: string; virtual;
    procedure HandleEvent(var Event: TEvent); override;
    class function InitViewer(Area: TRect; Win: TWindow; AHistoryId: Word): TListViewer; static;
  end;

  { The arrow next to an input line that opens the history list of the line. The palette is: 1 arrow, 2 sides. }
  THistory = class(TView)
  private
    class var Icon: string;
    procedure TakeChoice(Popup: THistoryWindow);
    procedure OpenHistoryList(var Event: TEvent);
  protected
    Link: TInputLine;
    HistoryId: Word;
  public
    constructor Create(const Bounds: TRect; ALink: TInputLine; AHistoryId: Word); reintroduce;
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function InitHistoryWindow(const Bounds: TRect): THistoryWindow; virtual;
    procedure RecordHistory(const Text: string); virtual;
    procedure ShutDown; override;
  end;

var
  { The size in bytes of the block of the history lists, which InitHistory allocates. }
  HistorySize: Word = 1024;
  StrNZCopyHook: TStrNZCopyFunc = nil;

{ The number of entries of the list ListId. }
function HistoryCount(ListId: Byte): Word;
{ Puts Text at the end of the list ListId, after removing the entries that have the same text. An empty text is not
  added. }
procedure HistoryAdd(ListId: Byte; const Text: string);
{ The text of the entry EntryIndex of the list ListId, or nil when the list has no such entry. The text stays valid
  until the lists are changed. }
function HistoryStr(ListId: Byte; EntryIndex: Integer): PAnsiChar;
procedure ClearHistory;
procedure InitHistory;
procedure DoneHistory;

implementation

uses
  TvObjs, TvKeys, TvDialog, TvUtf8, TvApp;

const
  { The offset that stands for no record. }
  NoRecord = -1;
  { The most bytes of a text that a record keeps; the length of a record is a byte. }
  MaxStoredText = 252;
  { The bytes of a record besides its text: the id, the length and the terminating zero. }
  RecordOverhead = 3;
  { The offset of the text inside a record. }
  TextOffsetInRecord = 2;
  { Bytes after the block, so that the length of a record at its end can be read. }
  BlockSlack = 2;
  { The arrow of THistory between its two sides. }
  ArrowOfHistory = #$DE'~'#$19'~'#$DD;

var
  HistoryBlock: PByte = nil;
  BlockBytes: Integer = 0;
  LastRec: Integer = 0;
  CurId: Byte = 0;
  CurRec: Integer = NoRecord;
  HistoryPalette: TPalette = nil;
  HistoryViewerPalette: TPalette = nil;
  HistoryWindowPalette: TPalette = nil;

{ The records of the block. }

function RecordId(Offset: Integer): Byte;
begin
  Result := HistoryBlock[Offset];
end;

function RecordLength(Offset: Integer): Integer;
begin
  Result := HistoryBlock[Offset + 1];
end;

function RecordChars(Offset: Integer): PAnsiChar;
begin
  Result := PAnsiChar(@HistoryBlock[Offset + TextOffsetInRecord]);
end;

function RecordText(Offset: Integer): string;
begin
  Result := RecordChars(Offset);
end;

function OffsetAfter(Offset: Integer): Integer;
begin
  Result := Offset + RecordLength(Offset);
end;

{ Writes a record with the given id and text at Offset. }
procedure StoreRecord(Offset: Integer; ListId: Byte; const Text: string);
var
  textLength: Integer;
begin
  textLength := Length(Text);
  HistoryBlock[Offset] := ListId;
  HistoryBlock[Offset + 1] := Byte(textLength + RecordOverhead);
  if textLength > 0 then
    Move(Text[1], HistoryBlock[Offset + TextOffsetInRecord], textLength);
  HistoryBlock[Offset + TextOffsetInRecord + textLength] := 0;
end;

{ The scanning of one list. }

procedure StartId(ListId: Byte);
begin
  CurId := ListId;
  CurRec := 0;
end;

procedure AdvanceStringPointer;
begin
  if CurRec = NoRecord then
    Exit;
  CurRec := OffsetAfter(CurRec);
  while (CurRec < LastRec) and (RecordId(CurRec) <> CurId) do
    CurRec := OffsetAfter(CurRec);
  if CurRec >= LastRec then
    CurRec := NoRecord;
end;

procedure DeleteString;
var
  removedLength, followingOffset: Integer;
begin
  removedLength := RecordLength(CurRec);
  followingOffset := CurRec + removedLength;
  Move(HistoryBlock[followingOffset], HistoryBlock[CurRec], LastRec - followingOffset);
  LastRec := LastRec - removedLength;
end;

procedure InsertString(ListId: Byte; const Text: string);
var
  neededBytes, firstLength, freeBytes: Integer;
begin
  neededBytes := Length(Text) + RecordOverhead;
  freeBytes := BlockBytes - LastRec;
  while neededBytes > freeBytes do
  begin
    if LastRec = 0 then
      Exit;
    firstLength := RecordLength(0);
    Move(HistoryBlock[firstLength], HistoryBlock[0], LastRec - firstLength);
    LastRec := LastRec - firstLength;
    freeBytes := BlockBytes - LastRec;
  end;
  StoreRecord(LastRec, ListId, Text);
  LastRec := OffsetAfter(LastRec);
end;

function HistoryCount(ListId: Byte): Word;
var
  entries: Integer;
begin
  Result := 0;
  if HistoryBlock = nil then
    Exit;
  StartId(ListId);
  entries := 0;
  AdvanceStringPointer;
  while CurRec <> NoRecord do
  begin
    Inc(entries);
    AdvanceStringPointer;
  end;
  Result := Word(entries);
end;

procedure HistoryAdd(ListId: Byte; const Text: string);
var
  storedText: string;
begin
  if Text = '' then
    Exit;
  if HistoryBlock = nil then
    Exit;
  storedText := Text;
  if Length(storedText) > MaxStoredText then
    SetLength(storedText, MaxStoredText);
  StartId(ListId);
  AdvanceStringPointer;
  while CurRec <> NoRecord do
  begin
    if storedText = RecordText(CurRec) then
      DeleteString;
    AdvanceStringPointer;
  end;
  InsertString(ListId, storedText);
end;

function HistoryStr(ListId: Byte; EntryIndex: Integer): PAnsiChar;
var
  stepsLeft: Integer;
begin
  Result := nil;
  if HistoryBlock = nil then
    Exit;
  StartId(ListId);
  stepsLeft := EntryIndex + 1;
  while stepsLeft > 0 do
  begin
    AdvanceStringPointer;
    Dec(stepsLeft);
  end;
  if CurRec = NoRecord then
    Exit;
  Result := RecordChars(CurRec);
end;

procedure ClearHistory;
begin
  if HistoryBlock = nil then
    Exit;
  StoreRecord(0, 0, '');
  LastRec := OffsetAfter(0);
end;

procedure InitHistory;
begin
  BlockBytes := HistorySize;
  HistoryBlock := AllocMem(BlockBytes + BlockSlack);
  ClearHistory;
end;

procedure DoneHistory;
begin
  if HistoryBlock <> nil then
    FreeMem(HistoryBlock);
  HistoryBlock := nil;
  BlockBytes := 0;
  LastRec := 0;
  CurRec := NoRecord;
end;

{ Gives the text of a block of characters, and an empty text for nil. }
function TextOfChars(Chars: PAnsiChar): string;
begin
  if Chars = nil then
    Result := ''
  else
    Result := Chars;
end;

{ THistoryViewer }

constructor THistoryViewer.Create(const Bounds: TRect; HorizontalBar, VerticalBar: TScrollBar; AHistoryId: Word);
var
  widestEntry: Integer;
begin
  inherited Create(Bounds, 1, HorizontalBar, VerticalBar);
  HistoryId := AHistoryId;
  SetRange(SmallInt(HistoryCount(Byte(AHistoryId))));
  if Range > 1 then
    FocusItem(1);
  if HScrollBar = nil then
    Exit;
  widestEntry := HistoryWidth;
  HScrollBar.SetRange(0, widestEntry - Size.X + 3);
end;

function THistoryViewer.GetPalette: TPalette;
begin
  Result := HistoryViewerPalette;
end;

function THistoryViewer.GetText(ItemIndex, MaxLen: SmallInt): string;
var
  entryText: string;
begin
  Result := '';
  entryText := TextOfChars(HistoryStr(Byte(HistoryId), ItemIndex));
  if MaxLen <= 0 then
    Exit;
  Result := Copy(entryText, 1, MaxLen);
end;

procedure THistoryViewer.HandleEvent(var Event: TEvent);
var
  verdict: Word;
  decided: Boolean;
begin
  decided := False;
  verdict := cmCancel;
  case Event.What of
    evMouseDown:
      if (Event.Mouse.EventFlags and meDoubleClick) <> 0 then
      begin
        decided := True;
        verdict := cmOK;
      end;
    evKeyDown:
      if Event.KeyDown.KeyCode = kbEnter then
      begin
        decided := True;
        verdict := cmOK;
      end
      else if Event.KeyDown.KeyCode = kbEsc then
        decided := True;
    evCommand:
      if Event.Message.Command = cmCancel then
        decided := True;
  end;
  if not decided then
  begin
    inherited HandleEvent(Event);
    Exit;
  end;
  EndModal(verdict);
  ClearEvent(Event);
end;

function THistoryViewer.HistoryWidth: Integer;
var
  entryCount, entryIndex, entryWidth: Integer;
begin
  Result := 0;
  entryCount := HistoryCount(Byte(HistoryId));
  for entryIndex := 0 to entryCount - 1 do
  begin
    entryWidth := Integer(TText.Width(TextOfChars(HistoryStr(Byte(HistoryId), entryIndex))));
    if entryWidth > Result then
      Result := entryWidth;
  end;
end;

{ THistInit }

constructor THistInit.Create(const Bounds: TRect; ListViewerMaker: TCreateListViewerFunc);
begin
  inherited Create(Bounds, '', wnNoNumber);
  CreateListViewer := ListViewerMaker;
end;

{ THistoryWindow }

constructor THistoryWindow.Create(const Bounds: TRect; AHistoryId: Word);
begin
  inherited Create(Bounds, @THistoryWindow.InitViewer);
  Flags := Byte(wfClose);
  Viewer := nil;
  if not Assigned(CreateListViewer) then
    Exit;
  Viewer := CreateListViewer(GetExtent, Self, AHistoryId);
  if Viewer <> nil then
    Insert(Viewer);
end;

function THistoryWindow.GetPalette: TPalette;
begin
  Result := HistoryWindowPalette;
end;

function THistoryWindow.GetSelection: string;
begin
  Result := '';
  if Viewer = nil then
    Exit;
  Result := Viewer.GetText(Viewer.Focused, 255);
end;

procedure THistoryWindow.HandleEvent(var Event: TEvent);
var
  clickedOutside: Boolean;
begin
  inherited HandleEvent(Event);
  if Event.What <> evMouseDown then
    Exit;
  clickedOutside := not MouseInView(Event.Mouse.Where);
  if not clickedOutside then
    Exit;
  EndModal(cmCancel);
  ClearEvent(Event);
end;

class function THistoryWindow.InitViewer(Area: TRect; Win: TWindow; AHistoryId: Word): TListViewer;
var
  viewerArea: TRect;
  horizontalBar, verticalBar: TScrollBar;
begin
  viewerArea := Area.Grow(-1, -1);
  horizontalBar := Win.StandardScrollBar(sbHorizontal or sbHandleKeyboard);
  verticalBar := Win.StandardScrollBar(sbVertical or sbHandleKeyboard);
  Result := THistoryViewer.Create(viewerArea, horizontalBar, verticalBar, AHistoryId);
end;

{ THistory }

constructor THistory.Create(const Bounds: TRect; ALink: TInputLine; AHistoryId: Word);
begin
  inherited Create(Bounds);
  Link := ALink;
  HistoryId := AHistoryId;
  Options := Options or ofPostProcess;
  EventMask := EventMask or evBroadcast;
end;

procedure THistory.ShutDown;
begin
  Link := nil;
  inherited ShutDown;
end;

procedure THistory.Draw;
var
  lineBuffer: TDrawBuffer;
begin
  lineBuffer := TDrawBuffer.Create;
  try
    lineBuffer.MoveCStr(0, Icon, GetColor($0102));
    WriteLine(0, 0, Size.X, Size.Y, lineBuffer);
  finally
    lineBuffer.Free;
  end;
end;

function THistory.GetPalette: TPalette;
begin
  Result := HistoryPalette;
end;

function Rc4(LeftX, TopY, RightX, BottomY: Integer): TRect;
begin
  Result := TRect.Create(LeftX, TopY, RightX, BottomY);
end;

procedure THistory.TakeChoice(Popup: THistoryWindow);
var
  chosenText: string;
begin
  chosenText := Popup.GetSelection;
  if Assigned(StrNZCopyHook) then
    Link.Data := StrNZCopyHook(chosenText, Link.MaxLen + 1);
  Link.SelectAll(True);
  Link.DrawView;
end;

procedure THistory.OpenHistoryList(var Event: TEvent);
var
  lineArea, ownerArea, popupArea: TRect;
  popup: THistoryWindow;
  outcome: Word;
begin
  if Link.Focus then
    RecordHistory(Link.Data)
  else
  begin
    ClearEvent(Event);
    Exit;
  end;
  lineArea := Link.GetBounds;
  popupArea := Rc4(lineArea.A.X - 1, lineArea.A.Y - 1, lineArea.B.X + 1, lineArea.B.Y + 7);
  ownerArea := Owner.GetExtent;
  popupArea := popupArea.Intersect(ownerArea);
  popupArea.B.Y := popupArea.B.Y - 1;
  popup := InitHistoryWindow(popupArea);
  if popup <> nil then
  begin
    outcome := Owner.ExecView(popup);
    if outcome = cmOK then
      TakeChoice(popup);
    TvObject.DestroyObject(popup);
  end;
  ClearEvent(Event);
end;

procedure THistory.HandleEvent(var Event: TEvent);
var
  opensList, linkIsReleased: Boolean;
  command: Word;
begin
  inherited HandleEvent(Event);
  if Link = nil then
    Exit;
  opensList := Event.What = evMouseDown;
  if (not opensList) and (Event.What = evKeyDown) then
    opensList := (CtrlToArrow(Event.KeyDown.KeyCode) = kbDown) and ((Link.State and sfFocused) <> 0);
  if opensList then
  begin
    OpenHistoryList(Event);
    Exit;
  end;
  if Event.What <> evBroadcast then
    Exit;
  command := Event.Message.Command;
  linkIsReleased := (command = cmReleasedFocus) and (Event.Message.InfoPtr = Pointer(Link));
  if linkIsReleased or (command = cmRecordHistory) then
    RecordHistory(Link.Data);
end;

function THistory.InitHistoryWindow(const Bounds: TRect): THistoryWindow;
begin
  Result := THistoryWindow.Create(Bounds, HistoryId);
  Result.HelpCtx := Link.HelpCtx;
end;

procedure THistory.RecordHistory(const Text: string);
begin
  HistoryAdd(Byte(HistoryId), Text);
end;

initialization
  THistory.Icon := ArrowOfHistory;
  HistoryPalette := TPalette.Create(cpHistory, Length(cpHistory));
  HistoryViewerPalette := TPalette.Create(cpHistoryViewer, Length(cpHistoryViewer));
  HistoryWindowPalette := TPalette.Create(cpHistoryWindow, Length(cpHistoryWindow));
  TvApp.InitHistoryHook := @InitHistory;
  TvApp.DoneHistoryHook := @DoneHistory;

finalization
  DoneHistory;
  HistoryPalette.Free;
  HistoryViewerPalette.Free;
  HistoryWindowPalette.Free;

end.
