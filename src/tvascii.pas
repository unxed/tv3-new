{ A table-of-characters window for the view library.

  TAsciiTable shows 256 codes in 8 rows of 32 cells with a movable cursor. In code page mode the codes are the bytes
  0..255 and every cell holds one raw byte, which the screen layer shows through the code page. In Unicode mode the
  table shows one block of 256 code points, Block * 256 .. Block * 256 + 255. The user moves the cursor with keys or
  the mouse and picks a code with Enter, a double click or by typing the character; a pick calls OnPick and sends the
  command AsciiCommandBase + acPicked to the owner. TAsciiReport shows the code under the cursor of a table, and
  TAsciiChart is a window that holds a table and a report.

  The text of a cell comes from the hook CharText of the table, which a program may replace. The keys that move the
  cursor are chosen by the virtual method KeyAction and the typed character by TypedCode, so that a subclass can
  change them. Messages are sent with Message of TvViews.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The views of
  this unit are not streamable: the views of TvViews have no stream members that they could extend. }
unit TvAscii;

{$mode objfpc}
{$H+}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvColors, TvEvents, TvKeys, TvDrawBuf, TvObjs, TvViews, TvWindow;

const
  AsciiCols = 32;
  AsciiRows = 8;
  AsciiCells = AsciiCols * AsciiRows;          { 256 }
  AsciiMaxBlock = $10FFFF div AsciiCells;      { 4351 = $10FF }

  { offsets from AsciiCommandBase }
  acFocused = 0;
  acPicked = 1;

type
  TAsciiTable = class;

  TAsciiCharText = function(Code: LongInt): AnsiString;
  TAsciiPickEvent = procedure(Sender: TAsciiTable; Code: LongInt) of object;

  TAsciiKey = (akNone, akLeft, akRight, akUp, akDown, akRowStart, akRowEnd, akColTop, akColBottom, akFirst, akLast,
    akUp2, akDown2, akLeft5, akRight5, akPrevBlock, akNextBlock, akPick);

  { The table of codes. The palette is: 1 the characters, 2 the cell under the cursor. }
  TAsciiTable = class(TView)
    Unicode: Boolean;
    Block: LongInt;
    TypePicks: Boolean;
    MarkCursor: Boolean;
    CharText: TAsciiCharText;
    OnPick: TAsciiPickEvent;
    constructor Create(const Bounds: TRect);
  private
    procedure MoveCursorTo(CellX, CellY: Integer);
    procedure ChangeBlock(Delta: Integer);
    procedure FollowPointer(Where: TPoint);
    procedure HandleMouseDown(var Event: TEvent);
    procedure HandleKeyDown(var Event: TEvent);
  public
    function GetPalette: TPalette; override;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    function KeyAction(var Event: TEvent): TAsciiKey; virtual;
    function TypedCode(var Event: TEvent): LongInt; virtual;
    function Code: LongInt;
    procedure SetCode(ACode: LongInt);
    function CellText(ACode: LongInt): AnsiString;
    procedure Pick; virtual;
    procedure Focused; virtual;
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    procedure SetData(Rec: Pointer); override;
  end;

  { The line that shows the code of a table. The palette is: 1 the text, 2 the character. }
  TAsciiReport = class(TView)
    Code: LongInt;
    Unicode: Boolean;
    CharStr: AnsiString;
    constructor Create(const Bounds: TRect);
  public
    function GetPalette: TPalette; override;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ReportParts(out Prefix, Rest: AnsiString); virtual;
    procedure ShowCode(Table: TAsciiTable);
  end;

  { A window with a table and a report. }
  TAsciiChart = class(TWindow)
    Table: TAsciiTable;
    Report: TAsciiReport;
    constructor Create(const ATitle: ShortString = 'ASCII Table'; AUnicode: Boolean = False); reintroduce;
  public
    function MakeTable(const Bounds: TRect): TAsciiTable; virtual;
    function MakeReport(const Bounds: TRect): TAsciiReport; virtual;
  end;

function AsciiCodePageText(Code: LongInt): AnsiString;
function AsciiUnicodeText(Code: LongInt): AnsiString;

var
  AsciiCommandBase: Word = 910;
  AsciiPalette: ShortString = #6#7;
  AsciiCharText: TAsciiCharText = nil;

implementation

uses
  SysUtils, TvUtf8;

var
  { The palette that was made from AsciiPalette, and the text that it was made from. }
  PaletteObject: TPalette = nil;
  PaletteSource: ShortString = '';

{ The palette for the text that AsciiPalette holds now. }
function CurrentPalette: TPalette;
begin
  if (PaletteObject = nil) or (PaletteSource <> AsciiPalette) then
  begin
    PaletteObject.Free;
    PaletteSource := AsciiPalette;
    PaletteObject := TPalette.Create(string(PaletteSource), Length(PaletteSource));
  end;
  Result := PaletteObject;
end;

const
  { Keys without Ctrl and the action of the key at the same position of PlainActions. }
  PlainKeys: array[0..7] of Word = (kbUp, kbDown, kbLeft, kbRight, kbPgUp, kbPgDn, kbHome, kbEnd);
  PlainActions: array[0..7] of TAsciiKey = (akUp, akDown, akLeft, akRight, akColTop, akColBottom, akRowStart,
    akRowEnd);
  { Keys with Ctrl and their actions. }
  CtrlKeys: array[0..5] of Word = (kbCtrlHome, kbCtrlEnd, kbCtrlPgUp, kbCtrlPgDn, kbCtrlLeft, kbCtrlRight);
  CtrlActions: array[0..5] of TAsciiKey = (akFirst, akLast, akPrevBlock, akNextBlock, akLeft5, akRight5);

{ The action that goes with KeyCode in the two parallel arrays, or akNone when KeyCode is not in Keys. }
function LookUpKey(KeyCode: Word; const Keys: array of Word; const Actions: array of TAsciiKey): TAsciiKey;
var
  position: Integer;
begin
  position := High(Keys);
  while (position >= 0) and (Keys[position] <> KeyCode) do
    Dec(position);
  if position < 0 then
    Exit(akNone);
  Result := Actions[position];
end;

{ The low attribute of the entry Entry of the palette of Viewer. }
function AttrOfEntry(Viewer: TView; Entry: Word): TColorAttr;
var
  pair: TAttrPair;
begin
  pair := Viewer.GetColor(Entry);
  Result := pair.Attrs[0];
end;

{ Sends a message to Target with Message of TvViews; nothing happens when Target is nil. }
procedure SendMessage(Target: TView; Kind, Command: Word; Info: Pointer);
begin
  Message(Target, Kind, Command, Info);
end;

{ The text that stands for a code in the table or in the report when no hook is assigned. }
function DefaultText(Code: LongInt; Unicode: Boolean): AnsiString;
begin
  if Unicode then
    Result := AsciiUnicodeText(Code)
  else
    Result := AsciiCodePageText(Code);
end;

function ByteText(Value: Byte): AnsiString;
begin
  SetLength(Result, 1);
  Result[1] := AnsiChar(Value);
end;

function AsciiCodePageText(Code: LongInt): AnsiString;
begin
  Result := ByteText(Byte(Code and $FF));
end;

function AsciiUnicodeText(Code: LongInt): AnsiString;
var
  encoded: TUtf8Bytes;
  encodedLength: SizeInt;
  index: Integer;
begin
  if (Code < 32) or (Code = 127) then
    Exit(ByteText(Byte(Code and $FF)));
  if (Code >= $80) and (Code <= $9F) then
    Exit(' ');
  if (Code >= $D800) and (Code <= $DFFF) then
    Exit(' ');
  if Code > $10FFFF then
    Exit(' ');
  if CharWidth(Cardinal(Code)) <> 1 then
    Exit(' ');
  encodedLength := Utf32To8(Cardinal(Code), encoded);
  SetLength(Result, encodedLength);
  for index := 0 to encodedLength - 1 do
    Result[index + 1] := AnsiChar(encoded[index]);
end;

{ The first character of Text as a code point, or -1 when Text does not start with a valid UTF-8 sequence. }
function FirstCodePoint(const Text: AnsiString): LongInt;
var
  firstByte: Byte;
  sequenceLength: Integer;
  index: Integer;
  sequence: AnsiString;
  codePoint: Cardinal;
  encoded: TUtf8Bytes;
begin
  Result := -1;
  if Length(Text) = 0 then
    Exit;
  firstByte := Byte(Text[1]);
  if firstByte < $80 then
    Exit(firstByte);
  sequenceLength := Integer(Utf8BytesLeft(firstByte)) + 1;
  if (sequenceLength < 2) or (sequenceLength > Length(Text)) then
    Exit;
  for index := 2 to sequenceLength do
    if (Byte(Text[index]) and $C0) <> $80 then
      Exit;
  sequence := Copy(Text, 1, sequenceLength);
  codePoint := Utf8To32(sequence);
  if codePoint > $10FFFF then
    Exit;
  if Utf32To8(codePoint, encoded) <> sequenceLength then
    Exit;
  Result := LongInt(codePoint);
end;

{ TAsciiTable }

constructor TAsciiTable.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  Options := Options or ofSelectable;
  EventMask := EventMask or evMouseMove;
  TypePicks := True;
  MarkCursor := True;
  CharText := AsciiCharText;
  Unicode := False;
  Block := 0;
  BlockCursor;
  ShowCursor;
end;

function TAsciiTable.GetPalette: TPalette;
begin
  Result := CurrentPalette;
end;

procedure TAsciiTable.Draw;
var
  rowBuffer: TDrawBuffer;
  normalAttr, cursorAttr, cellAttr: TColorAttr;
  rowIndex, columnIndex, cellCode: Integer;
  cellString: AnsiString;
begin
  normalAttr := AttrOfEntry(Self, 1);
  cursorAttr := AttrOfEntry(Self, 2);
  rowBuffer := TDrawBuffer.Create;
  try
    for rowIndex := 0 to Size.Y - 1 do
    begin
      rowBuffer.MoveChar(0, ' ', normalAttr, Size.X);
      if rowIndex < AsciiRows then
        for columnIndex := 0 to AsciiCols - 1 do
        begin
          if columnIndex >= Size.X then
            Break;
          cellAttr := normalAttr;
          if MarkCursor and (columnIndex = Cursor.X) and (rowIndex = Cursor.Y) then
            cellAttr := cursorAttr;
          cellCode := rowIndex * AsciiCols + columnIndex;
          if Unicode then
            cellCode := cellCode + Block * AsciiCells;
          cellString := CellText(cellCode);
          if Length(cellString) = 1 then
          begin
            if cellString[1] = #0 then
              rowBuffer.MoveChar(columnIndex, ' ', cellAttr, 1)
            else
              rowBuffer.MoveChar(columnIndex, cellString[1], cellAttr, 1);
            Continue;
          end;
          rowBuffer.MoveChar(columnIndex, ' ', cellAttr, 1);
          if Length(cellString) > 0 then
            rowBuffer.MoveStr(columnIndex, cellString, cellAttr, 1);
        end;
      WriteLine(0, SmallInt(rowIndex), SmallInt(Size.X), 1, rowBuffer);
    end;
  finally
    rowBuffer.Free;
  end;
end;

function TAsciiTable.KeyAction(var Event: TEvent): TAsciiKey;
var
  pressed: Word;
begin
  pressed := Event.KeyDown.KeyCode;
  Result := LookUpKey(pressed, PlainKeys, PlainActions);
  if Result <> akNone then
    Exit;
  Result := LookUpKey(pressed, CtrlKeys, CtrlActions);
  if Result = akNone then
    if pressed = kbEnter then
      Result := akPick;
end;

function TAsciiTable.TypedCode(var Event: TEvent): LongInt;
var
  codePoint: LongInt;
begin
  Result := -1;
  if Unicode then
  begin
    if Event.KeyDown.TextLength = 0 then
      Exit;
    codePoint := FirstCodePoint(Event.KeyDown.GetText);
    if codePoint >= 32 then
      Result := codePoint;
    Exit;
  end;
  if Event.KeyDown.CharScan.CharCode >= 32 then
    Result := Event.KeyDown.CharScan.CharCode;
end;

function TAsciiTable.Code: LongInt;
begin
  Result := Block * AsciiCells + Cursor.Y * AsciiCols + Cursor.X;
  if not Unicode then
    Result := Result and $FF;
end;

procedure TAsciiTable.SetCode(ACode: LongInt);
var
  cellIndex: LongInt;
begin
  if ACode < 0 then
    ACode := 0;
  if Unicode then
  begin
    if ACode > $10FFFF then
      ACode := $10FFFF;
    Block := ACode div AsciiCells;
  end
  else
    ACode := ACode and $FF;
  cellIndex := ACode mod AsciiCells;
  SetCursor(cellIndex mod AsciiCols, cellIndex div AsciiCols);
  DrawView;
  Focused;
end;

function TAsciiTable.CellText(ACode: LongInt): AnsiString;
begin
  if Assigned(CharText) then
    Result := CharText(ACode)
  else
    Result := DefaultText(ACode, Unicode);
end;

procedure TAsciiTable.Pick;
var
  pickedCode: LongInt;
begin
  pickedCode := Code;
  if Assigned(OnPick) then
    OnPick(Self, pickedCode);
  if Owner <> nil then
    SendMessage(Owner, evCommand, Word(AsciiCommandBase + acPicked), Pointer(PtrInt(pickedCode)));
end;

procedure TAsciiTable.Focused;
begin
  if Owner <> nil then
    SendMessage(Owner, evBroadcast, Word(AsciiCommandBase + acFocused), Self);
end;

function TAsciiTable.DataSize: Word;
begin
  Result := SizeOf(LongInt);
end;

procedure TAsciiTable.GetData(Rec: Pointer);
begin
  PLongInt(Rec)^ := Code;
end;

procedure TAsciiTable.SetData(Rec: Pointer);
begin
  SetCode(PLongInt(Rec)^);
end;

{ Moves the cursor to a cell inside the table, announces the cell and redraws when the cursor moved. }
procedure TAsciiTable.MoveCursorTo(CellX, CellY: Integer);
var
  newX, newY: Integer;
begin
  newX := CellX;
  if newX < 0 then
    newX := 0;
  if newX > AsciiCols - 1 then
    newX := AsciiCols - 1;
  newY := CellY;
  if newY < 0 then
    newY := 0;
  if newY > AsciiRows - 1 then
    newY := AsciiRows - 1;
  if (newX <> Cursor.X) or (newY <> Cursor.Y) then
  begin
    SetCursor(newX, newY);
    if MarkCursor then
      DrawView;
  end;
  Focused;
end;

{ Shows another block of the Unicode table; nothing happens in code page mode or outside the blocks. }
procedure TAsciiTable.ChangeBlock(Delta: Integer);
var
  newBlock: LongInt;
begin
  if not Unicode then
    Exit;
  newBlock := Block + Delta;
  if (newBlock < 0) or (newBlock > AsciiMaxBlock) then
    Exit;
  Block := newBlock;
  DrawView;
  Focused;
end;

procedure TAsciiTable.HandleMouseDown(var Event: TEvent);
var
  isDouble: Boolean;
  buttonHeld: Boolean;
begin
  isDouble := (Event.Mouse.EventFlags and meDoubleClick) <> 0;
  if isDouble then
  begin
    FollowPointer(Event.Mouse.Where);
    Pick;
    ClearEvent(Event);
    Exit;
  end;
  buttonHeld := True;
  while buttonHeld do
  begin
    FollowPointer(Event.Mouse.Where);
    buttonHeld := MouseEvent(Event, evMouseMove);
  end;
  ClearEvent(Event);
end;

{ Moves the cursor to the cell under the global point Where, when the point is inside the table. }
procedure TAsciiTable.FollowPointer(Where: TPoint);
var
  cellPoint: TPoint;
begin
  if not MouseInView(Where) then
    Exit;
  cellPoint := MakeLocal(Where);
  MoveCursorTo(cellPoint.X, cellPoint.Y);
end;

procedure TAsciiTable.HandleKeyDown(var Event: TEvent);
var
  action: TAsciiKey;
  typed: LongInt;
begin
  action := KeyAction(Event);
  case action of
    akNone:
      begin
        if not TypePicks then
          Exit;
        typed := TypedCode(Event);
        if typed < 0 then
          Exit;
        if Unicode and (typed > $10FFFF) then
          Exit;
        if (not Unicode) and (typed > 255) then
          Exit;
        SetCode(typed);
        Pick;
      end;
    akLeft: MoveCursorTo(Cursor.X - 1, Cursor.Y);
    akRight: MoveCursorTo(Cursor.X + 1, Cursor.Y);
    akUp: MoveCursorTo(Cursor.X, Cursor.Y - 1);
    akDown: MoveCursorTo(Cursor.X, Cursor.Y + 1);
    akRowStart: MoveCursorTo(0, Cursor.Y);
    akRowEnd: MoveCursorTo(AsciiCols - 1, Cursor.Y);
    akColTop: MoveCursorTo(Cursor.X, 0);
    akColBottom: MoveCursorTo(Cursor.X, AsciiRows - 1);
    akFirst: MoveCursorTo(0, 0);
    akLast: MoveCursorTo(AsciiCols - 1, AsciiRows - 1);
    akUp2: MoveCursorTo(Cursor.X, Cursor.Y - 2);
    akDown2: MoveCursorTo(Cursor.X, Cursor.Y + 2);
    akLeft5: MoveCursorTo(Cursor.X - 5, Cursor.Y);
    akRight5: MoveCursorTo(Cursor.X + 5, Cursor.Y);
    akPrevBlock: ChangeBlock(-1);
    akNextBlock: ChangeBlock(1);
    akPick: Pick;
  end;
  ClearEvent(Event);
end;

procedure TAsciiTable.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What = evMouseDown then
    HandleMouseDown(Event)
  else if Event.What = evKeyDown then
    HandleKeyDown(Event);
end;

{ TAsciiReport }

constructor TAsciiReport.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  EventMask := EventMask or evBroadcast;
  Code := 0;
  Unicode := False;
  CharStr := '';
end;

function TAsciiReport.GetPalette: TPalette;
begin
  Result := CurrentPalette;
end;

procedure TAsciiReport.ReportParts(out Prefix, Rest: AnsiString);
begin
  Prefix := ' Char: ';
  if Unicode then
    Rest := '  Dec: ' + IntToStr(Code) + '  U+' + IntToHex(Code, 4)
  else
    Rest := '  Dec: ' + Format('%3d', [Code]) + '  Hex: ' + IntToHex(Code and $FF, 2);
end;

procedure TAsciiReport.Draw;
var
  rowBuffer: TDrawBuffer;
  textAttr, charAttr: TColorAttr;
  prefixText, restText: AnsiString;
  charColumn, restColumn: Integer;
begin
  textAttr := AttrOfEntry(Self, 1);
  charAttr := AttrOfEntry(Self, 2);
  ReportParts(prefixText, restText);
  rowBuffer := TDrawBuffer.Create;
  try
    rowBuffer.MoveChar(0, ' ', textAttr, Size.X);
    rowBuffer.MoveStr(0, prefixText, textAttr, Size.X);
    charColumn := Length(prefixText);
    if charColumn < Size.X then
    begin
      if Length(CharStr) = 1 then
      begin
        if CharStr[1] = #0 then
          rowBuffer.MoveChar(charColumn, ' ', charAttr, 1)
        else
          rowBuffer.MoveChar(charColumn, CharStr[1], charAttr, 1);
      end
      else if Length(CharStr) > 1 then
        rowBuffer.MoveStr(charColumn, CharStr, charAttr, 1);
      restColumn := charColumn + 1;
      if (restColumn < Size.X) and (Length(restText) > 0) then
        rowBuffer.MoveStr(restColumn, restText, textAttr, Size.X - restColumn);
    end;
    WriteLine(0, 0, SmallInt(Size.X), SmallInt(Size.Y), rowBuffer);
  finally
    rowBuffer.Free;
  end;
end;

procedure TAsciiReport.ShowCode(Table: TAsciiTable);
begin
  Code := Table.Code;
  Unicode := Table.Unicode;
  CharStr := Table.CellText(Code);
  DrawView;
end;

procedure TAsciiReport.HandleEvent(var Event: TEvent);
var
  isFocusedMessage: Boolean;
begin
  inherited HandleEvent(Event);
  if Event.What <> evBroadcast then
    Exit;
  isFocusedMessage := Event.Message.Command = Word(AsciiCommandBase + acFocused);
  if not isFocusedMessage then
    Exit;
  if Event.Message.InfoPtr = nil then
    Exit;
  if not (TObject(Event.Message.InfoPtr) is TAsciiTable) then
    Exit;
  ShowCode(TAsciiTable(Event.Message.InfoPtr));
end;

{ TAsciiChart }

constructor TAsciiChart.Create(const ATitle: ShortString; AUnicode: Boolean);
var
  interior, tableBounds, reportBounds: TRect;
begin
  inherited Create(TRect.Create(0, 0, AsciiCols + 2, AsciiRows + 4), string(ATitle), wnNoNumber);
  Flags := Flags and not Byte(wfGrow or wfZoom);
  interior := GetExtent;
  interior := interior.Grow(-1, -1);
  reportBounds := TRect.Create(interior.A.X, interior.B.Y - 1, interior.B.X, interior.B.Y);
  tableBounds := TRect.Create(interior.A.X, interior.A.Y, interior.B.X, interior.A.Y + AsciiRows);

  Report := MakeReport(reportBounds);
  Report.Options := Report.Options or ofFramed;
  Insert(Report);

  Table := MakeTable(tableBounds);
  Table.Options := Table.Options or ofFramed;
  Table.Unicode := AUnicode;
  Insert(Table);

  Table.Select;
  Report.ShowCode(Table);
end;

function TAsciiChart.MakeTable(const Bounds: TRect): TAsciiTable;
begin
  Result := TAsciiTable.Create(Bounds);
end;

function TAsciiChart.MakeReport(const Bounds: TRect): TAsciiReport;
begin
  Result := TAsciiReport.Create(Bounds);
end;

finalization
  PaletteObject.Free;
  PaletteObject := nil;
end.
