{ Tests of TvAscii.

  The display is a screen of 40 by 14 cells in memory; the root of the views is a group that writes into it and reads
  its events from a script. The colors of the root are the BIOS attributes 1 to 127: the entry k of its palette is k,
  so the characters of a table have the attribute 13 and the cell under the cursor has the attribute 14. The window
  is at the origin of the root, so the table starts at the screen cell 1, 1 and the report is on the screen row 10.
  The root and the chart count the focus messages of the unit that they get. }
program t_ascii;

{$mode objfpc}
{$H+}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  SysUtils, TvGeom, TvKeys, TvEvents, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvViews, TvWindow, TvUtf8,
  TvAscii;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 14;
  MaxCalls = 100000;
  { The screen cell of the first cell of the table, and the screen row of the report. }
  TableX = 1;
  TableY = 1;
  ReportRow = 10;

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
    ErrorCount: Integer;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure EventError(var Event: TEvent); override;
    function GetPalette: TPalette; override;
  end;

  { A table that also moves by two rows, with the keys F2 and F3. }
  TTestTable = class(TAsciiTable)
  public
    function KeyAction(var Event: TEvent): TAsciiKey; override;
  end;

  { A chart that makes a TTestTable and notes the commands of picks that reach it. }
  TTestChart = class(TAsciiChart)
  public
    function MakeTable(const Bounds: TRect): TAsciiTable; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { Notes the picks that its method is told about. }
  TPickSink = class
  public
    Count: Integer;
    LastCode: LongInt;
    LastSender: TAsciiTable;
    procedure Picked(Sender: TAsciiTable; Code: LongInt);
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  GetCalls: Integer;
  RootPal: TPalette;
  FocusCount: Integer;
  PickedCommands: Integer;
  LastCommandInfo: PtrInt;
  OrderLog: string;
  Sink: TPickSink;

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

{ Counts the focus broadcasts of the unit that an event brings. }
procedure CountFocus(const Event: TEvent);
begin
  if Event.What <> evBroadcast then
    Exit;
  if Event.Message.Command = Word(AsciiCommandBase + acFocused) then
    Inc(FocusCount);
end;

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

{ A key event that carries the text Str, which is at most four bytes. }
function TextEv(const Str: string; Code: Word): TEvent;
var
  index: Integer;
begin
  Result := KeyEv(Code);
  for index := 1 to Length(Str) do
    Result.KeyDown.Text[index - 1] := Byte(Str[index]);
  Result.KeyDown.TextLength := Length(Str);
end;

{ The key event of a character of the code page: the character code and its text. }
function TypeEv(Ch: Char): TEvent;
begin
  Result := TextEv(Ch, Word(Ord(Ch)));
end;

function MouseEv(What: Word; X, Y: Integer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := What;
  Result.Mouse.Where := Pt(X, Y);
  Result.Mouse.Buttons := mbLeftButton;
end;

{ The global position of the cell Col, Row of the table. }
function CellX(Col: Integer): Integer;
begin
  Result := TableX + Col;
end;

function CellY(Row: Integer): Integer;
begin
  Result := TableY + Row;
end;

function CellStr(X, Y: Integer): string;
begin
  Result := ScreenCells[Y * ScrW + X].Character.GetText;
end;

function AttrAt(X, Y: Integer): Integer;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute.ToBIOS;
end;

function RowStr(Y, X0, N: Integer): string;
var
  offset: Integer;
begin
  Result := '';
  for offset := 0 to N - 1 do
    Result := Result + CellStr(X0 + offset, Y);
end;

procedure ClearScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
end;

procedure TRoot.AddEvent(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TRoot.GetEvent(var Event: TEvent);
begin
  Inc(GetCalls);
  if GetCalls > MaxCalls then
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

procedure TRoot.HandleEvent(var Event: TEvent);
begin
  CountFocus(Event);
  inherited HandleEvent(Event);
end;

procedure TRoot.EventError(var Event: TEvent);
begin
  Inc(ErrorCount);
end;

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
end;

function TTestTable.KeyAction(var Event: TEvent): TAsciiKey;
begin
  if Event.KeyDown.KeyCode = kbF2 then
    Result := akDown2
  else if Event.KeyDown.KeyCode = kbF3 then
    Result := akUp2
  else
    Result := inherited KeyAction(Event);
end;

function TTestChart.MakeTable(const Bounds: TRect): TAsciiTable;
begin
  Result := TTestTable.Create(Bounds);
end;

procedure TTestChart.HandleEvent(var Event: TEvent);
begin
  CountFocus(Event);
  if (Event.What = evCommand) and (Word(Event.Message.Command - AsciiCommandBase) = acPicked) then
  begin
    Inc(PickedCommands);
    LastCommandInfo := PtrInt(Event.Message.InfoPtr);
    OrderLog := OrderLog + 'C';
  end;
  inherited HandleEvent(Event);
end;

procedure TPickSink.Picked(Sender: TAsciiTable; Code: LongInt);
begin
  Inc(Count);
  LastCode := Code;
  LastSender := Sender;
  OrderLog := OrderLog + 'P';
end;

function HookText(Code: LongInt): AnsiString;
begin
  Result := '#';
end;

function CyrillicHook(Code: LongInt): AnsiString;
begin
  Result := #$D0#$B6;
end;

function EmptyHook(Code: LongInt): AnsiString;
begin
  Result := '';
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

{ A root with an active chart at its origin; the counters are zero. }
procedure Scene(out Root: TRoot; out Chart: TTestChart; Uni: Boolean);
begin
  FocusCount := 0;
  PickedCommands := 0;
  LastCommandInfo := 0;
  OrderLog := '';
  Sink.Count := 0;
  Sink.LastCode := -1;
  Sink.LastSender := nil;
  Root := NewRoot;
  Chart := TTestChart.Create('ASCII Table', Uni);
  Root.Insert(Chart);
  Chart.SetState(sfActive, True);
  Chart.Table.OnPick := @Sink.Picked;
end;

{ Gives the event to the table and tells whether the table cleared it. }
function Press(Table: TAsciiTable; Ev: TEvent): Boolean;
begin
  Table.HandleEvent(Ev);
  Result := Ev.What = evNothing;
end;

function ReportText: string;
begin
  Result := TrimRight(RowStr(ReportRow, TableX, AsciiCols));
end;

procedure TestConstants;
begin
  Check(AsciiCols = 32, 'the table has 32 columns');
  Check(AsciiRows = 8, 'the table has 8 rows');
  Check(AsciiCells = 256, 'the table has 256 cells');
  Check(AsciiMaxBlock = $10FF, 'the last block is $10FF');
  Check(acFocused = 0, 'acFocused is the offset 0');
  Check(acPicked = 1, 'acPicked is the offset 1');
  Check(AsciiCommandBase = 910, 'the command base is 910');
  Check(Length(AsciiPalette) = 2, 'the palette string has two entries');
  Check((Ord(AsciiPalette[1]) = 6) and (Ord(AsciiPalette[2]) = 7), 'the palette string maps to the entries 6 and 7');
  Check(not Assigned(AsciiCharText), 'the default hook is not assigned');
end;

procedure TestHooks;
var
  text: AnsiString;
begin
  Check(AsciiCodePageText(65) = 'A', 'the code page text of 65 is A');
  Check(AsciiCodePageText(321) = 'A', 'the code page text keeps the low byte');
  text := AsciiCodePageText(200);
  Check((Length(text) = 1) and (Byte(text[1]) = 200), 'the code page text of 200 is the byte 200');
  text := AsciiCodePageText(0);
  Check((Length(text) = 1) and (text[1] = #0), 'the code page text of 0 is one zero byte');

  Check(AsciiUnicodeText($E9) = #$C3#$A9, 'the Unicode text of $E9 is C3 A9');
  Check(AsciiUnicodeText($85) = ' ', 'the Unicode text of $85 is a space');
  Check(AsciiUnicodeText($4E00) = ' ', 'the Unicode text of a wide character is a space');
  Check(AsciiUnicodeText(1) = #1, 'the Unicode text of 1 is the control byte');
  Check(AsciiUnicodeText(127) = #127, 'the Unicode text of 127 is the control byte');
  text := AsciiUnicodeText(0);
  Check((Length(text) = 1) and (text[1] = #0), 'the Unicode text of 0 is one zero byte');
  Check(AsciiUnicodeText(65) = 'A', 'the Unicode text of 65 is A');
  Check(AsciiUnicodeText(32) = ' ', 'the Unicode text of 32 is a space');
  Check(AsciiUnicodeText($80) = ' ', 'the Unicode text of $80 is a space');
  Check(AsciiUnicodeText($9F) = ' ', 'the Unicode text of $9F is a space');
  Check(AsciiUnicodeText($A0) <> ' ', 'the Unicode text of $A0 is its encoding');
  Check(AsciiUnicodeText($D800) = ' ', 'the Unicode text of a surrogate is a space');
  Check(AsciiUnicodeText($DFFF) = ' ', 'the Unicode text of the last surrogate is a space');
  Check(AsciiUnicodeText($110000) = ' ', 'the Unicode text above $10FFFF is a space');
  Check(AsciiUnicodeText($300) = ' ', 'the Unicode text of a combining mark is a space');
  Check(AsciiUnicodeText($200B) = ' ', 'the Unicode text of a zero-width character is a space');
  Check(AsciiUnicodeText($436) = #$D0#$B6, 'the Unicode text of $436 is D0 B6');
  Check(AsciiUnicodeText($20AC) = #$E2#$82#$AC, 'the Unicode text of $20AC is E2 82 AC');
end;

procedure TestConstruction;
var
  root: TRoot;
  chart: TTestChart;
  entry: TColorAttr;
begin
  Scene(root, chart, False);
  Check((chart.Size.X = 34) and (chart.Size.Y = 12), 'the chart is 34 by 12');
  Check((chart.Table.Size.X = 32) and (chart.Table.Size.Y = 8), 'the table is 32 by 8');
  Check((chart.Report.Size.X = 32) and (chart.Report.Size.Y = 1), 'the report is 32 by 1');
  Check(chart.Current = TView(chart.Table), 'the table is the current view of the chart');
  Check((chart.Table.State and sfSelected) <> 0, 'the table is selected');
  Check(chart.Report.Origin.Y - 1 = 9, 'the report is on the 10th interior row');
  Check((chart.Table.Origin.X = 1) and (chart.Table.Origin.Y = 1), 'the table is at the corner of the interior');
  Check(chart.Number = wnNoNumber, 'the chart has no number');
  Check((chart.Flags and wfGrow) = 0, 'the chart cannot grow');
  Check((chart.Flags and wfZoom) = 0, 'the chart cannot zoom');
  Check((chart.Flags and wfMove) <> 0, 'the chart can move');
  Check((chart.Flags and wfClose) <> 0, 'the chart can close');
  Check(string(chart.Title) = 'ASCII Table', 'the default title is ASCII Table');
  Check(chart.Table is TTestTable, 'MakeTable of a subclass makes the table');
  Check(chart.Report.ClassType = TAsciiReport, 'MakeReport makes a report');
  Check((chart.Table.Options and ofSelectable) <> 0, 'the table is selectable');
  Check((chart.Table.Options and ofFramed) <> 0, 'the table is framed');
  Check((chart.Report.Options and ofFramed) <> 0, 'the report is framed');
  Check((chart.Table.EventMask and evMouseMove) <> 0, 'the table takes mouse moves');
  Check((chart.Report.EventMask and evBroadcast) <> 0, 'the report takes broadcasts');
  Check(chart.Table.TypePicks, 'typing picks by default');
  Check(chart.Table.MarkCursor, 'the cursor is marked by default');
  Check(not chart.Table.Unicode, 'the default mode is the code page');
  Check(chart.Table.Block = 0, 'the block starts at 0');
  Check((chart.Table.Cursor.X = 0) and (chart.Table.Cursor.Y = 0), 'the cursor starts at the first cell');
  Check((chart.Table.State and sfCursorIns) <> 0, 'the cursor is a block cursor');
  Check((chart.Table.State and sfCursorVis) <> 0, 'the cursor is shown');
  Check(chart.Table.Code = 0, 'the code starts at 0');
  Check(not Assigned(chart.Table.CharText), 'the hook of a table is not assigned by default');
  entry := chart.Table.GetPalette.Items[0];
  Check(entry.ToBIOS = 2, 'the palette of the table has two entries');
  entry := chart.Report.GetPalette.Items[0];
  Check(entry.ToBIOS = 2, 'the palette of the report has two entries');
  FreeRoot(root);

  Scene(root, chart, True);
  Check(chart.Table.Unicode, 'AUnicode sets the mode of the table');
  Check(chart.Report.Unicode, 'the report shows the mode of the table');
  FreeRoot(root);
end;

procedure TestDraw;
var
  root: TRoot;
  chart: TTestChart;
begin
  Scene(root, chart, False);
  Check(RowStr(CellY(1), CellX(0), 10) = ' !"#$%&''()', 'row 1 begins with the codes 32 to 41');
  Check(RowStr(CellY(2), CellX(0), 4) = '@ABC', 'row 2 begins with the codes 64 to 67');
  Check(CellStr(CellX(0), CellY(0)) = ' ', 'the cell of the code 0 shows a space');
  Check(CellStr(CellX(31), CellY(1)) = '?', 'the last cell of row 1 is the code 63');
  Check(CellStr(CellX(1), CellY(0)) = #1, 'the cell of the code 1 holds the byte 1');
  Check(CellStr(CellX(0), CellY(7)) = #224, 'the cell of the code 224 holds the byte 224');
  Check(CellStr(CellX(31), CellY(7)) = #255, 'the cell of the code 255 holds the byte 255');
  Check(AttrAt(CellX(0), CellY(0)) = 14, 'the cell under the cursor has the color 2');
  Check(AttrAt(CellX(1), CellY(0)) = 13, 'the other cells have the color 1');
  Check(AttrAt(CellX(0), CellY(1)) = 13, 'a cell of another row has the color 1');

  Check(ReportText = ' Char:    Dec:   0  Hex: 00', 'the report of the code 0');
  Check(Pos('Dec:   0', ReportText) > 0, 'the report of the code 0 has Dec:   0');
  Check(AttrAt(TableX, ReportRow) = 13, 'the text of the report has the color 1');
  Check(AttrAt(TableX + 7, ReportRow) = 14, 'the character of the report has the color 2');

  chart.Table.SetCode(33);
  Check(ReportText = ' Char: !  Dec:  33  Hex: 21', 'the report of the code 33');
  Check(CellStr(TableX + 7, ReportRow) = '!', 'the character of the report is the code 33');
  Check(AttrAt(CellX(1), CellY(1)) = 14, 'the cell of the code 33 has the color 2 after SetCode');
  Check(AttrAt(CellX(0), CellY(0)) = 13, 'the old cell has the color 1 after SetCode');

  chart.Table.MarkCursor := False;
  chart.Table.DrawView;
  Check(AttrAt(CellX(1), CellY(1)) = 13, 'without MarkCursor no cell has the color 2');
  chart.Table.MarkCursor := True;
  chart.Table.DrawView;

  chart.Table.CharText := @HookText;
  chart.Table.DrawView;
  Check(RowStr(CellY(2), CellX(0), 4) = '####', 'the hook gives the text of the cells');
  chart.Table.CharText := @CyrillicHook;
  chart.Table.DrawView;
  Check(CellStr(CellX(5), CellY(2)) = #$D0#$B6, 'a text of several bytes forms one cell');
  Check(CellStr(CellX(6), CellY(2)) = #$D0#$B6, 'the next cell has its own text');
  chart.Table.CharText := @EmptyHook;
  chart.Table.DrawView;
  Check(CellStr(CellX(5), CellY(2)) = ' ', 'an empty text leaves a space');
  chart.Table.CharText := nil;
  chart.Table.DrawView;
  Check(RowStr(CellY(2), CellX(0), 4) = '@ABC', 'without the hook the code page text is shown');
  FreeRoot(root);
end;

procedure TestKeyAction;
var
  root: TRoot;
  chart: TTestChart;
  table: TAsciiTable;
  ev: TEvent;
begin
  Scene(root, chart, False);
  table := chart.Table;
  ev := KeyEv(kbLeft);
  Check(table.KeyAction(ev) = akLeft, 'Left is akLeft');
  ev := KeyEv(kbRight);
  Check(table.KeyAction(ev) = akRight, 'Right is akRight');
  ev := KeyEv(kbUp);
  Check(table.KeyAction(ev) = akUp, 'Up is akUp');
  ev := KeyEv(kbDown);
  Check(table.KeyAction(ev) = akDown, 'Down is akDown');
  ev := KeyEv(kbHome);
  Check(table.KeyAction(ev) = akRowStart, 'Home is akRowStart');
  ev := KeyEv(kbEnd);
  Check(table.KeyAction(ev) = akRowEnd, 'End is akRowEnd');
  ev := KeyEv(kbPgUp);
  Check(table.KeyAction(ev) = akColTop, 'PgUp is akColTop');
  ev := KeyEv(kbPgDn);
  Check(table.KeyAction(ev) = akColBottom, 'PgDn is akColBottom');
  ev := KeyEv(kbCtrlHome);
  Check(table.KeyAction(ev) = akFirst, 'Ctrl+Home is akFirst');
  ev := KeyEv(kbCtrlEnd);
  Check(table.KeyAction(ev) = akLast, 'Ctrl+End is akLast');
  ev := KeyEv(kbCtrlLeft);
  Check(table.KeyAction(ev) = akLeft5, 'Ctrl+Left is akLeft5');
  ev := KeyEv(kbCtrlRight);
  Check(table.KeyAction(ev) = akRight5, 'Ctrl+Right is akRight5');
  ev := KeyEv(kbCtrlPgUp);
  Check(table.KeyAction(ev) = akPrevBlock, 'Ctrl+PgUp is akPrevBlock');
  ev := KeyEv(kbCtrlPgDn);
  Check(table.KeyAction(ev) = akNextBlock, 'Ctrl+PgDn is akNextBlock');
  ev := KeyEv(kbEnter);
  Check(table.KeyAction(ev) = akPick, 'Enter is akPick');
  ev := KeyEv(kbF1);
  Check(table.KeyAction(ev) = akNone, 'F1 is akNone');
  ev := TypeEv('a');
  Check(table.KeyAction(ev) = akNone, 'a letter is akNone');
  FreeRoot(root);
end;

procedure TestMoves;
var
  root: TRoot;
  chart: TTestChart;
  table: TAsciiTable;
begin
  Scene(root, chart, False);
  table := chart.Table;

  Check(Press(table, KeyEv(kbRight)), 'Right is taken');
  Check(Press(table, KeyEv(kbDown)), 'Down is taken');
  Check(table.Code = 33, 'Right and Down from 0 give 33');
  Check((table.Cursor.X = 1) and (table.Cursor.Y = 1), 'the cursor is at column 1, row 1');
  Check(Press(table, KeyEv(kbEnd)), 'End is taken');
  Check(table.Code = 63, 'End gives 63');
  Check(Press(table, KeyEv(kbHome)), 'Home is taken');
  Check(table.Code = 32, 'Home gives 32');
  Check(Press(table, KeyEv(kbPgDn)), 'PgDn is taken');
  Check(table.Code = 224, 'PgDn gives 224');
  Check(Press(table, KeyEv(kbPgUp)), 'PgUp is taken');
  Check(table.Code = 0, 'PgUp gives 0');
  Check(Press(table, KeyEv(kbCtrlEnd)), 'Ctrl+End is taken');
  Check(table.Code = 255, 'Ctrl+End gives 255');
  Press(table, KeyEv(kbRight));
  Check(table.Code = 255, 'Right at 255 leaves 255');
  Press(table, KeyEv(kbDown));
  Check(table.Code = 255, 'Down at 255 leaves 255');
  Press(table, KeyEv(kbCtrlHome));
  Check(table.Code = 0, 'Ctrl+Home gives 0');
  Press(table, KeyEv(kbLeft));
  Check(table.Code = 0, 'Left at 0 leaves 0');
  Press(table, KeyEv(kbUp));
  Check(table.Code = 0, 'Up at 0 leaves 0');
  Press(table, KeyEv(kbCtrlRight));
  Check(table.Code = 5, 'Ctrl+Right gives 5');
  Press(table, KeyEv(kbCtrlLeft));
  Check(table.Code = 0, 'Ctrl+Left gives 0');
  Press(table, KeyEv(kbCtrlLeft));
  Check(table.Code = 0, 'Ctrl+Left at column 0 stays');
  table.SetCode(28);
  Press(table, KeyEv(kbCtrlRight));
  Check(table.Code = 31, 'Ctrl+Right stops at the last column');
  Press(table, KeyEv(kbUp));
  Press(table, KeyEv(kbLeft));
  Check(table.Code = 30, 'Left moves by one cell');
  Press(table, KeyEv(kbDown));
  Check(table.Code = 62, 'Down moves by one row');
  Press(table, KeyEv(kbUp));
  Check(table.Code = 30, 'Up moves by one row');

  table.SetCode(65);
  Check((table.Cursor.X = 1) and (table.Cursor.Y = 2), 'SetCode puts the cursor at column 1, row 2');
  Check(Press(table, KeyEv(kbCtrlPgDn)), 'Ctrl+PgDn is taken in the code page mode');
  Check((table.Code = 65) and (table.Block = 0), 'Ctrl+PgDn changes nothing in the code page mode');
  Check(Press(table, KeyEv(kbCtrlPgUp)), 'Ctrl+PgUp is taken in the code page mode');
  Check((table.Code = 65) and (table.Block = 0), 'Ctrl+PgUp changes nothing in the code page mode');

  { The announcement of a move. }
  table.SetCode(31);
  FocusCount := 0;
  Press(table, KeyEv(kbRight));
  Check((table.Code = 31) and (FocusCount = 1), 'Right at column 31 stays and announces');
  FocusCount := 0;
  Press(table, KeyEv(kbLeft));
  Check(FocusCount = 1, 'a move announces once');
  FocusCount := 0;
  Press(table, KeyEv(kbCtrlPgDn));
  Check(FocusCount = 0, 'Ctrl+PgDn in the code page mode announces nothing');
  FocusCount := 0;
  table.SetCode(table.Code);
  Check(FocusCount = 1, 'SetCode announces even when nothing moved');

  { The report follows the table through the broadcast. }
  table.SetCode(33);
  Press(table, KeyEv(kbRight));
  Check(chart.Report.Code = 34, 'the report follows a move');
  Check(ReportText = ' Char: "  Dec:  34  Hex: 22', 'the report shows the code 34');

  { A subclass that gives the keys akUp2 and akDown2. }
  table.SetCode(0);
  Check(Press(table, KeyEv(kbF2)), 'a key of a subclass is taken');
  Check(table.Code = 64, 'akDown2 moves two rows down');
  Press(table, KeyEv(kbF2));
  Press(table, KeyEv(kbF2));
  Press(table, KeyEv(kbF2));
  Check(table.Code = 224, 'akDown2 stops at the last row');
  Press(table, KeyEv(kbF3));
  Check(table.Code = 160, 'akUp2 moves two rows up');
  table.SetCode(32);
  Press(table, KeyEv(kbF3));
  Check(table.Code = 0, 'akUp2 stops at the first row');
  FreeRoot(root);
end;

procedure TestPick;
var
  root: TRoot;
  chart: TTestChart;
  table: TAsciiTable;
  ev: TEvent;
  cleared: Boolean;
begin
  Scene(root, chart, False);
  table := chart.Table;

  table.SetCode(65);
  Check(Press(table, KeyEv(kbEnter)), 'Enter is taken');
  Check(Sink.Count = 1, 'Enter calls OnPick once');
  Check(Sink.LastCode = 65, 'OnPick gets the code 65');
  Check(Sink.LastSender = table, 'OnPick gets the table');
  Check(PickedCommands = 1, 'the window gets one command');
  Check(LastCommandInfo = 65, 'the command carries the code 65');
  Check(OrderLog = 'PC', 'OnPick runs before the command is sent');

  table.OnPick := nil;
  Press(table, KeyEv(kbEnter));
  Check((Sink.Count = 1) and (PickedCommands = 2), 'without OnPick the command is still sent');
  table.OnPick := @Sink.Picked;

  Check(Press(table, TypeEv('z')), 'a typed character is taken');
  Check(table.Code = 122, 'typing z puts the cursor at 122');
  Check((table.Cursor.X = 26) and (table.Cursor.Y = 3), 'typing z puts the cursor at column 26, row 3');
  Check((Sink.Count = 2) and (Sink.LastCode = 122), 'typing z picks 122');
  Check(LastCommandInfo = 122, 'typing z sends the command with 122');

  table.TypePicks := False;
  ev := TypeEv('y');
  table.HandleEvent(ev);
  Check(ev.What = evKeyDown, 'without TypePicks the key is not cleared');
  Check((table.Code = 122) and (Sink.Count = 2), 'without TypePicks nothing is picked');
  table.TypePicks := True;

  ev := TextEv(#$D0#$B6, 0);
  table.HandleEvent(ev);
  Check(ev.What = evKeyDown, 'in the code page mode a text without a character code is not cleared');
  Check((table.Code = 122) and (Sink.Count = 2), 'in the code page mode a text without a character code is not picked');
  ev := KeyEv(kbF1);
  table.HandleEvent(ev);
  Check(ev.What = evKeyDown, 'a key without a character is not cleared');
  ev := TextEv(#1, 1);
  table.HandleEvent(ev);
  Check((ev.What = evKeyDown) and (Sink.Count = 2), 'a control character is not picked');

  ev := TypeEv('A');
  Check(table.TypedCode(ev) = 65, 'TypedCode of A is 65');
  ev := TextEv(' ', $3920);
  Check(table.TypedCode(ev) = 32, 'TypedCode of a space is 32');
  ev := TextEv(#31, 31);
  Check(table.TypedCode(ev) = -1, 'TypedCode of the code 31 is -1');
  ev := TextEv(#$D0#$B6, 0);
  Check(table.TypedCode(ev) = -1, 'TypedCode of a text without a character code is -1');
  ev := KeyEv(kbLeft);
  Check(table.TypedCode(ev) = -1, 'TypedCode of a key without a character is -1');

  { Mouse. }
  Sink.Count := 0;
  root.Script := nil;
  root.ScriptPos := 0;
  root.AddEvent(MouseEv(evMouseUp, CellX(3), CellY(1)));
  ev := MouseEv(evMouseDown, CellX(3), CellY(1));
  table.HandleEvent(ev);
  Check(ev.What = evNothing, 'a click is taken');
  Check(table.Code = 35, 'a click moves the cursor to the code 35');
  Check(Sink.Count = 0, 'a single click does not pick');
  Check(root.ScriptPos = 1, 'a click reads the events up to the release');

  root.Script := nil;
  root.ScriptPos := 0;
  root.AddEvent(MouseEv(evMouseMove, CellX(4), CellY(2)));
  root.AddEvent(MouseEv(evMouseMove, CellX(5), CellY(2)));
  root.AddEvent(MouseEv(evMouseUp, CellX(5), CellY(2)));
  ev := MouseEv(evMouseDown, CellX(3), CellY(1));
  table.HandleEvent(ev);
  Check(table.Code = 69, 'a drag moves the cursor with the pointer');
  Check(root.ScriptPos = 3, 'a drag reads the events up to the release');
  Check(Sink.Count = 0, 'a drag does not pick');

  root.Script := nil;
  root.ScriptPos := 0;
  root.AddEvent(MouseEv(evMouseMove, 0, 0));
  root.AddEvent(MouseEv(evMouseUp, 0, 0));
  ev := MouseEv(evMouseDown, CellX(2), CellY(1));
  table.HandleEvent(ev);
  Check(table.Code = 34, 'a pointer outside the view does not move the cursor');

  root.Script := nil;
  root.ScriptPos := 0;
  ev := MouseEv(evMouseDown, CellX(4), CellY(2));
  ev.Mouse.EventFlags := meDoubleClick;
  table.HandleEvent(ev);
  Check(ev.What = evNothing, 'a double click is taken');
  Check(table.Code = 68, 'a double click moves the cursor to 68');
  Check((Sink.Count = 1) and (Sink.LastCode = 68), 'a double click picks 68');
  Check(root.ScriptPos = 0, 'a double click reads no event');

  ev := MouseEv(evMouseDown, 0, 0);
  ev.Mouse.EventFlags := meDoubleClick;
  table.HandleEvent(ev);
  Check(table.Code = 68, 'a double click outside the view does not move the cursor');
  Check((Sink.Count = 2) and (Sink.LastCode = 68), 'a double click outside the view still picks');
  cleared := ev.What = evNothing;
  Check(cleared, 'a double click outside the view is taken');
  FreeRoot(root);
end;

procedure TestData;
var
  root: TRoot;
  chart: TTestChart;
  value: LongInt;
begin
  Scene(root, chart, False);
  Check(chart.Table.DataSize = 4, 'DataSize is 4');
  value := 200;
  chart.Table.SetData(@value);
  Check(chart.Table.Code = 200, 'SetData sets the code 200');
  Check((chart.Table.Cursor.X = 8) and (chart.Table.Cursor.Y = 6), 'SetData puts the cursor at row 6');
  value := 0;
  chart.Table.GetData(@value);
  Check(value = 200, 'GetData gives 200');
  Check(chart.Report.Code = 200, 'SetData reaches the report');

  chart.Table.SetCode(-5);
  Check(chart.Table.Code = 0, 'a negative code becomes 0');
  chart.Table.Block := 7;
  chart.Table.SetCode(300);
  Check(chart.Table.Code = 44, 'in the code page mode SetCode keeps the low byte');
  Check(chart.Table.Block = 7, 'in the code page mode SetCode leaves the block');
  chart.Table.Block := 0;
  FreeRoot(root);
end;

procedure TestCellText;
var
  table: TAsciiTable;
  second: TAsciiTable;
begin
  table := TAsciiTable.Create(Rc(0, 0, 32, 8));
  Check(table.CellText(65) = 'A', 'the cell text of a table is the code page text');
  table.Unicode := True;
  Check(table.CellText($E9) = #$C3#$A9, 'the cell text of a Unicode table is the Unicode text');
  table.CharText := @HookText;
  Check(table.CellText($E9) = '#', 'the hook gives the cell text');
  table.CharText := nil;
  Check(table.CellText($E9) = #$C3#$A9, 'without the hook the mode gives the cell text');
  table.Unicode := False;

  AsciiCharText := @HookText;
  second := TAsciiTable.Create(Rc(0, 0, 32, 8));
  AsciiCharText := nil;
  Check(Assigned(second.CharText), 'a new table takes the global hook');
  Check(second.CellText(1) = '#', 'a new table uses the global hook');
  Check(not Assigned(table.CharText), 'a table made before keeps no hook');
  second.Free;

  { A table without an owner works as well. }
  table.SetCode(65);
  Check(table.Code = 65, 'SetCode works without an owner');
  table.Pick;
  Check(table.Code = 65, 'Pick works without an owner');
  table.Free;
end;

procedure TestReport;
var
  root: TRoot;
  chart: TTestChart;
  prefix, rest: AnsiString;
  ev: TEvent;
begin
  Scene(root, chart, False);
  chart.Report.Code := 33;
  chart.Report.ReportParts(prefix, rest);
  Check(prefix = ' Char: ', 'the prefix of the report');
  Check(rest = '  Dec:  33  Hex: 21', 'the rest of the report in the code page mode');
  chart.Report.Code := 0;
  chart.Report.ReportParts(prefix, rest);
  Check(rest = '  Dec:   0  Hex: 00', 'the rest of the report for the code 0');
  chart.Report.Code := 255;
  chart.Report.ReportParts(prefix, rest);
  Check(rest = '  Dec: 255  Hex: FF', 'the rest of the report for the code 255');
  chart.Report.Unicode := True;
  chart.Report.Code := 233;
  chart.Report.ReportParts(prefix, rest);
  Check(rest = '  Dec: 233  U+00E9', 'the rest of the report in the Unicode mode');
  chart.Report.Code := $1F600;
  chart.Report.ReportParts(prefix, rest);
  Check(rest = '  Dec: 128512  U+1F600', 'the rest of the report with five hex digits');
  chart.Report.Unicode := False;

  { A broadcast of the table makes the report show it. }
  chart.Table.SetCursor(5, 0);
  FillChar(ev, SizeOf(ev), 0);
  ev.What := evBroadcast;
  ev.Message.Command := Word(AsciiCommandBase + acFocused);
  ev.Message.InfoPtr := chart.Table;
  chart.Report.HandleEvent(ev);
  Check(chart.Report.Code = 5, 'the report takes the code of the table from the broadcast');
  Check(ev.What = evBroadcast, 'the report leaves the broadcast');

  chart.Table.SetCursor(6, 0);
  FillChar(ev, SizeOf(ev), 0);
  ev.What := evBroadcast;
  ev.Message.Command := Word(AsciiCommandBase + acPicked);
  ev.Message.InfoPtr := chart.Table;
  chart.Report.HandleEvent(ev);
  Check(chart.Report.Code = 5, 'the report ignores another command');

  chart.Table.SetCursor(7, 0);
  chart.Report.ShowCode(chart.Table);
  Check(chart.Report.Code = 7, 'ShowCode copies the code');
  Check(chart.Report.CharStr = #7, 'ShowCode copies the text of the cell');
  Check(not chart.Report.Unicode, 'ShowCode copies the mode');
  FreeRoot(root);
end;

procedure TestUnicode;
var
  root: TRoot;
  chart: TTestChart;
  table: TAsciiTable;
  ev: TEvent;
begin
  Scene(root, chart, True);
  table := chart.Table;
  table.SetCode($E9);
  Check(CellStr(CellX(0), CellY(7)) = #$C3#$A0, 'row 7 begins with U+00E0');
  Check(CellStr(CellX(9), CellY(7)) = #$C3#$A9, 'the tenth cell of row 7 is U+00E9');
  Check(ReportText = ' Char: ' + #$C3#$A9 + '  Dec: 233  U+00E9', 'the report of U+00E9');
  Check(AttrAt(CellX(9), CellY(7)) = 14, 'the cell of U+00E9 has the color 2');
  Check(CellStr(CellX(5), CellY(4)) = ' ', 'a cell of the C1 range shows a space');

  FocusCount := 0;
  Check(Press(table, KeyEv(kbCtrlPgDn)), 'Ctrl+PgDn is taken in the Unicode mode');
  Check(table.Block = 1, 'Ctrl+PgDn goes to block 1');
  Check(table.Code = $1E9, 'the code is $1E9 in block 1');
  Check(CellStr(CellX(0), CellY(0)) = #$C4#$80, 'the first cell of block 1 is U+0100');
  Check(FocusCount = 1, 'a change of the block announces');
  Check(chart.Report.Code = $1E9, 'the report follows the block');

  Press(table, KeyEv(kbCtrlPgUp));
  Check(table.Block = 0, 'Ctrl+PgUp goes back to block 0');
  FocusCount := 0;
  Check(Press(table, KeyEv(kbCtrlPgUp)), 'Ctrl+PgUp at block 0 is taken');
  Check(table.Block = 0, 'Ctrl+PgUp twice stops at block 0');
  Check(FocusCount = 0, 'a refused change of the block announces nothing');

  table.SetCode($10FFFF);
  Check(table.Block = AsciiMaxBlock, 'SetCode of $10FFFF gives the last block');
  Check(table.Code = $10FFFF, 'the code of the last cell is $10FFFF');
  Check((table.Cursor.X = 31) and (table.Cursor.Y = 7), 'the last code is the last cell');
  Press(table, KeyEv(kbCtrlPgDn));
  Check(table.Block = AsciiMaxBlock, 'Ctrl+PgDn stops at the last block');
  table.SetCode($10FFFF + 100);
  Check(table.Code = $10FFFF, 'SetCode clamps a code above $10FFFF');
  table.SetCode(-1);
  Check((table.Code = 0) and (table.Block = 0), 'SetCode of a negative code gives 0');

  Check(Press(table, TextEv(#$D0#$B6, 0)), 'a typed character of the Unicode mode is taken');
  Check(table.Block = 4, 'typing U+0436 goes to block 4');
  Check(table.Code = $436, 'typing U+0436 gives the code $436');
  Check((Sink.Count = 1) and (Sink.LastCode = $436), 'typing U+0436 picks it');
  Check(LastCommandInfo = $436, 'typing U+0436 sends the command with the code');

  ev := TextEv(#$D0#$B6, 0);
  Check(table.TypedCode(ev) = $436, 'TypedCode of a text is its code point');
  ev := TextEv('z', Ord('z'));
  Check(table.TypedCode(ev) = 122, 'TypedCode of an ASCII text is its code');
  ev := TextEv(#127, 127);
  Check(table.TypedCode(ev) = 127, 'TypedCode admits the code 127');
  ev := TextEv(#$C2#$85, 0);
  Check(table.TypedCode(ev) = $85, 'TypedCode admits the code $85');
  ev := TextEv(#31, 31);
  Check(table.TypedCode(ev) = -1, 'TypedCode refuses a control character');
  ev := TextEv(#$D0, 0);
  Check(table.TypedCode(ev) = -1, 'TypedCode refuses a cut sequence');
  ev := TextEv(#$80, 0);
  Check(table.TypedCode(ev) = -1, 'TypedCode refuses a continuation byte');
  ev := TextEv(#$C0#$80, 0);
  Check(table.TypedCode(ev) = -1, 'TypedCode refuses an overlong sequence');
  ev := TextEv(#$D0#$41, 0);
  Check(table.TypedCode(ev) = -1, 'TypedCode refuses a bad continuation byte');
  ev := KeyEv(kbLeft);
  Check(table.TypedCode(ev) = -1, 'TypedCode of a key without a character is -1');
  ev := TextEv(#$F4#$90#$80#$80, 0);
  Check(table.TypedCode(ev) = -1, 'TypedCode refuses a code point above $10FFFF');

  Sink.Count := 0;
  table.TypePicks := False;
  ev := TextEv(#$D0#$B6, 0);
  table.HandleEvent(ev);
  Check((ev.What = evKeyDown) and (Sink.Count = 0), 'without TypePicks nothing is picked in the Unicode mode');
  table.TypePicks := True;
  ev := TextEv(#1, 1);
  table.HandleEvent(ev);
  Check((ev.What = evKeyDown) and (Sink.Count = 0), 'a control character is not picked in the Unicode mode');
  FreeRoot(root);
end;

var
  K: Integer;
  PaletteText: string;
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
  Sink := TPickSink.Create;

  TestConstants;
  TestHooks;
  TestConstruction;
  TestDraw;
  TestKeyAction;
  TestMoves;
  TestPick;
  TestData;
  TestCellText;
  TestReport;
  TestUnicode;

  Sink.Free;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
