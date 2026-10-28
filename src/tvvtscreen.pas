{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/vtermemu.h, source/tvterm-core/vtermemu.cc
  See COPYRIGHT.tvterm.

  The screen of a terminal emulator: a grid of cells with a cursor and a pen, the history of the lines that left the
  top of the main screen (Scrollback), and the transfer of both to the TerminalState of TvVtCore. The C++ keeps
  the grid in a library that is not part of the sources; here the grid and the control functions that act on it are
  the class TVtScreen, and a cell is a TVtCell.

  Rows and columns are zero-based. A cell holds up to VtMaxChars code points; the first one is 0 for an erased cell
  and VtWideTrail for the second cell of a wide character. The lead of a wide character has the width 2 and its trail
  the width 0; every other cell has the width 1. Erasing and scrolling give the new cells the background of the pen and
  the default foreground. Text is UTF-8 in AnsiString values. A selection text is returned by CopySelection, which the
  C++ gives to the clipboard. }
unit TvVtScreen;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvColors, TvCell, TvVtCore;

const
  { The number of code points that one cell can hold (VTERM_MAX_CHARS_PER_CELL). }
  VtMaxChars = 6;
  { The first code point of the cell that follows a double-width character; (uint32_t) -1 in the C++. }
  VtWideTrail = $FFFFFFFF;
  { VTermEmulator::mouseWheelScrollLines }
  mouseWheelScrollLines = 3;

type
  TVtColorKind = (vcDefault, vcIndexed, vcRGB);

  TVtColor = record
    Kind: TVtColorKind;
    Idx: Byte;
    Red: Byte;
    Green: Byte;
    Blue: Byte;
  end;

  TVtAttr = (vaBold, vaItalic, vaUnderline, vaBlink, vaReverse, vaStrike, vaConceal);
  TVtAttrs = set of TVtAttr;

  TVtCell = record
    Chars: array[0..VtMaxChars - 1] of Cardinal;
    Width: Integer;
    Fg: TVtColor;
    Bg: TVtColor;
    Attrs: TVtAttrs;
  end;

  TVtCellArray = array of TVtCell;

  { A row of the screen; Continuation tells that it continues the row above it. }
  TVtRow = record
    Cells: TVtCellArray;
    Continuation: Boolean;
  end;

  TVtRowArray = array of TVtRow;

  { A line of the scrollback (Scrollback::Line); Cols is the width that it had when it was pushed. }
  TVtLine = record
    Cells: TVtCellArray;
    Cols: Integer;
    Continuation: Boolean;
  end;

  PVtLine = ^TVtLine;

  { struct Scrollback: the lines that were pushed out of the top of the screen. Offset is 0 (oldest line) to
    NumLines - 1 (newest line), or NumLines when no scrollback is shown. }
  Scrollback = class
  private
    FRing: array of TVtLine;
    FHead: Integer;
    FStored: Integer;
    function SlotOf(AIndex: Integer): Integer;
  public
    Offset: Integer;
    constructor Create;
    { Appends a line, dropping the oldest one when maxSize lines are held; gives False when a line was dropped. }
    function PushLine(ACols: Integer; const ACells: TVtCellArray; AContinuation: Boolean): Boolean;
    { Takes the newest line away; gives False when there is none. }
    function PopLine(out ACells: TVtCellArray; out ACols: Integer; out AContinuation: Boolean): Boolean;
    { ACount < 0: show older lines; ACount > 0: show newer lines. }
    procedure IncrementOffset(ACount: Integer);
    procedure SetOffset(ANewOffset: Integer);
    procedure FollowTerminal;
    function IsFollowingTerminal: Boolean;
    function GetVisibleScrollLines(ATerminalHeight: Integer): Integer;
    function NumLines: Integer;
    { The line AIndex, 0 <= AIndex < NumLines; the address is valid until the next push or pop. }
    function LineAt(AIndex: Integer): PVtLine;
    procedure Clear;
  const
    maxSize = 10000;
  end;

  TVtScreen = class
  private
    { size and the two grids }
    FCols, FRows: Integer;
    FGrid, FStash: TVtRowArray;
    { cursor and margins }
    FCurX, FCurY, FTop, FBottom: Integer;
    FAltActive, FPending: Boolean;
    FTabs: array of Boolean;
    FAutoWrap: Boolean;
    { colors of the pen and of the saved cursor }
    FPenFg, FPenBg, FSavedFg, FSavedBg: TVtColor;
    FPenAttrs: TVtAttrs;
    FSavedAttrs: TVtAttrs;
    FSavedX, FSavedY: Integer;
    FSavedPending: Boolean;
    { what UpdateState reports }
    FHistory: Scrollback;
    FCursorVisible, FCursorBlink: Boolean;
    FDamage: array of RowRange;
    FCursorChanged, FMouseEnabled, FOverflowed: Boolean;
    FShownOffset, FShownLines: Integer;
    function BlankCell: TVtCell;
    function MakeBlankRow: TVtRow;
    function NewGrid: TVtRowArray;
    function RowFromLine(const ACells: TVtCellArray; ACols: Integer; AContinuation: Boolean): TVtRow;
    procedure Damage(ARow, AFrom, ATo: Integer);
    procedure DamageAll;
    procedure ResetTabs;
    procedure ReleasePartner(ARow, AX: Integer);
    procedure ClearSpan(ARow, AFrom, ATo: Integer);
    procedure RepairRow(ARow: Integer);
    procedure PushRowToHistory(ARow: Integer);
    procedure ShiftLines(ATop, ABottom, AAmount: Integer; AUp: Boolean);
    procedure WrapLine;
    procedure AppendMark(ACode: Cardinal);
    procedure AdjustGridRows(var AGrid: TVtRowArray; ANewRows: Integer; var ACursorY: Integer; AUseHistory: Boolean);
    procedure AdjustGridCols(var AGrid: TVtRowArray; ANewCols: Integer);
    procedure UpdateSurface(ASurface: TerminalSurface);
    procedure DrawScrollbackLine(ASurface: TerminalSurface; AY: Integer);
    procedure DrawLine(ASurface: TerminalSurface; AY, ARowIndex, AStart, AEnd: Integer);
    procedure ExtractScrollbackLineText(AY, AStartX, AEndX: Integer; var AText: AnsiString; var APadding: Integer);
    procedure ExtractTerminalLineText(AY, AStartX, AEndX: Integer; var AText: AnsiString; var APadding: Integer);
  public
    constructor Create(ACols, ARows: Integer);
    destructor Destroy; override;

    { The pen: the attributes of the cells that PutChar writes. }
    procedure SetPenColors(const AFg, ABg: TVtColor);
    procedure SetPenAttrs(AAttrs: TVtAttrs);
    procedure ResetPen;

    { Writes a character of the given width (1 or 2) at the cursor. }
    procedure PutChar(ACode: Cardinal; AWidth: Integer);
    { Writes UTF-8 text: the controls 8, 9, 10 and 13 act as Backspace, Tab, LineFeed and CarriageReturn, a character
      without width is added to the cell before the cursor, and the other controls are ignored. }
    procedure PutText(const AText: AnsiString);

    procedure LineFeed;
    procedure ReverseIndex;
    procedure CarriageReturn;
    procedure Backspace;
    procedure Tab(ACount: Integer = 1);
    procedure BackTab(ACount: Integer = 1);
    procedure SetTabStop;
    procedure ClearTabStop;
    procedure ClearAllTabStops;

    { Mode 0: from the cursor to the end, 1: from the start to the cursor, 2: all. In EraseInDisplay the mode 3 clears
      the history and leaves the screen as it is. }
    procedure EraseInLine(AMode: Integer);
    procedure EraseInDisplay(AMode: Integer);
    procedure EraseChars(ACount: Integer);
    procedure InsertChars(ACount: Integer);
    procedure DeleteChars(ACount: Integer);
    procedure InsertLines(ACount: Integer);
    procedure DeleteLines(ACount: Integer);
    procedure ScrollUp(ACount: Integer);
    procedure ScrollDown(ACount: Integer);

    { Sets the scrolling region to the rows ATop to ABottom (both included) and moves the cursor to the origin; a
      region of fewer than two rows is the whole screen. }
    procedure SetScrollRegion(ATop, ABottom: Integer);

    procedure MoveTo(AX, AY: Integer);
    procedure MoveBy(ADX, ADY: Integer);
    procedure SaveCursor;
    procedure RestoreCursor;
    procedure SetCursorVisible(AValue: Boolean);
    procedure SetCursorBlink(AValue: Boolean);
    { Switches between the main screen and the alternate screen, which is blank when it is entered and has no history;
      entering it makes the scrollback follow the terminal. }
    procedure EnableAltScreen(AOn: Boolean);

    { Sets the size, at least 1 x 1. Lines that leave the top of the main screen go to the history, and when the
      screen grows, lines of the history come back at the top. }
    procedure Resize(ANewCols, ANewRows: Integer);

    function GetCell(ARow, ACol: Integer; out ACell: TVtCell): Boolean;
    function LineContinues(ARow: Integer): Boolean;

    { updateState }
    procedure UpdateState(AState: TerminalState);
    { handleScrollbackWheel: AWheel is a wheel value of TvEvents (mwUp, mwDown). }
    procedure HandleScrollbackWheel(AWheel: Byte);
    { copySelection: the text of the selection. }
    function CopySelection(const ASelection: SelectionRange): AnsiString;

    { The cursor column and row, and whether a wrap is pending and whether the cursor blinks. }
    property Cols: Integer read FCols;
    function CursorX: Integer;
    property Rows: Integer read FRows;
    function CursorY: Integer;
    property AutoWrap: Boolean read FAutoWrap write FAutoWrap;
    function WrapPending: Boolean;
    property History: Scrollback read FHistory;
    function CursorBlink: Boolean;
    property MouseEnabled: Boolean read FMouseEnabled write FMouseEnabled;
    function CursorVisible: Boolean;
    property TopMargin: Integer read FTop;
    function AltScreen: Boolean;
    property BottomMargin: Integer read FBottom;
  end;

function DefaultColor: TVtColor;
function IndexedColor(AIdx: Byte): TVtColor;
function RgbColor(ARed, AGreen, ABlue: Byte): TVtColor;
{ The cell that stands for an erased cell in the default colors: no character and the width 1. }
function DefaultCell: TVtCell;

implementation

uses
  Math, TvEvents, TvUtf8, TvText;

type
  TCellRow = array of TScreenCell;

{ Colors and cells }

function DefaultColor: TVtColor;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := vcDefault;
end;

function IndexedColor(AIdx: Byte): TVtColor;
begin
  Result := DefaultColor;
  Result.Kind := vcIndexed;
  Result.Idx := AIdx;
end;

function RgbColor(ARed, AGreen, ABlue: Byte): TVtColor;
begin
  Result := DefaultColor;
  Result.Kind := vcRGB;
  Result.Red := ARed;
  Result.Green := AGreen;
  Result.Blue := ABlue;
end;

function DefaultCell: TVtCell;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Width := 1;
  Result.Fg := DefaultColor;
  Result.Bg := DefaultColor;
end;

function IsWideTrail(const ACell: TVtCell): Boolean;
begin
  Result := ACell.Chars[0] = VtWideTrail;
end;

function IsWideLead(const ACell: TVtCell): Boolean;
begin
  Result := (ACell.Width = 2) and (ACell.Chars[0] <> VtWideTrail);
end;

function RowIsBlank(const ARow: TVtRow): Boolean;
var
  K: Integer;
begin
  Result := False;
  for K := 0 to High(ARow.Cells) do
    if ARow.Cells[K].Chars[0] <> 0 then
      Exit;
  Result := True;
end;

{ Conversion of cells to screen cells (convAttr, convCell) }

function ToTColor(const AColor: TVtColor): TColor;
begin
  case AColor.Kind of
    vcIndexed:
      Result := TColor.Create(TColorXTerm.Create(AColor.Idx));
    vcRGB:
      Result := TColor.Create(TColorRGB.Create(AColor.Red, AColor.Green, AColor.Blue));
  else
    FillChar(Result, SizeOf(Result), 0);
  end;
end;

function ConvAttr(const ACell: TVtCell): TColorAttr;
const
  StyleOf: array[TVtAttr] of Word = (slBold, slItalic, slUnderline, slBlink, slReverse, slStrike, 0);
var
  Style: Word;
  Flag: TVtAttr;
begin
  Style := 0;
  for Flag := Low(TVtAttr) to High(TVtAttr) do
    if Flag in ACell.Attrs then
      Style := Style or StyleOf[Flag];
  Result := TColorAttr.Create(ToTColor(ACell.Fg), ToTColor(ACell.Bg), Style);
end;

procedure ConvCell(var ACells: array of TScreenCell; AX: Integer; const ACell: TVtCell);
var
  Len, K: Integer;
  Txt: array of Cardinal;
  Drawn: SizeInt;
begin
  if ACell.Chars[0] = VtWideTrail then
  begin
    { The second cell of a wide character that the text routines did not take as wide gets a space. }
    if (AX > 0) and not ACells[AX - 1].Character.IsWide then
    begin
      ACells[AX].Character := TScreenCharacter.Create(' ');
      ACells[AX].Attribute := ACells[AX - 1].Attribute;
    end;
    Exit;
  end;
  Len := 0;
  while (Len < VtMaxChars) and (ACell.Chars[Len] <> 0) do
    Inc(Len);
  if Len = 0 then
  begin
    { An erased cell is a cell of one NUL byte; CharWidth of TvUtf8 gives -1 for the code point 0, so the text
      routines are not asked to draw it. }
    ACells[AX].Character := TScreenCharacter.Create(#0);
    ACells[AX].Attribute := ConvAttr(ACell);
    Exit;
  end;
  SetLength(Txt, Len);
  for K := 0 to High(Txt) do
    Txt[K] := ACell.Chars[K];
  Drawn := TTextCells.DrawStr(ACells, AX, Txt, 0, ConvAttr(ACell));
  if Drawn < 0 then
    Exit;
end;

procedure LoadRow(ASurface: TerminalSurface; AY: Integer; var ABuf: TCellRow);
var
  Wide: Integer;
begin
  Wide := ASurface.Size.X;
  SetLength(ABuf, 0);
  SetLength(ABuf, Max(Wide, 0));
  if Wide > 0 then
    Move(ASurface.At(AY, 0)^, ABuf[0], Wide * SizeOf(TScreenCell));
end;

procedure StoreRow(ASurface: TerminalSurface; AY: Integer; const ABuf: TCellRow);
begin
  if Length(ABuf) > 0 then
    Move(ABuf[0], ASurface.At(AY, 0)^, Length(ABuf) * SizeOf(TScreenCell));
end;

{ The text of one cell (extractCellText). }
procedure ExtractCellText(const ACell: TVtCell; var AText: AnsiString; var APadding: Integer);
var
  Len, K, J, Got: Integer;
  Bytes: TUtf8Bytes;
begin
  if ACell.Chars[0] = 0 then
  begin
    { Erased cells are spaces when text follows them. }
    Inc(APadding);
    Exit;
  end;
  { The gap behind a double-width character has no text. }
  if ACell.Chars[0] = VtWideTrail then
    Exit;
  if APadding > 0 then
    AText := AText + StringOfChar(' ', APadding);
  APadding := 0;
  Len := 0;
  while (Len < VtMaxChars) and (ACell.Chars[Len] <> 0) do
    Inc(Len);
  for K := 0 to Len - 1 do
  begin
    Got := Utf32To8(ACell.Chars[K], Bytes);
    for J := 0 to Got - 1 do
      AText := AText + Chr(Bytes[J]);
  end;
end;

{ Scrollback }

constructor Scrollback.Create;
begin
  inherited Create;
  SetLength(FRing, 0);
  FHead := 0;
  FStored := 0;
  Offset := 0;
end;

function Scrollback.SlotOf(AIndex: Integer): Integer;
begin
  Result := (FHead + AIndex) mod Length(FRing);
end;

function Scrollback.PushLine(ACols: Integer; const ACells: TVtCellArray; AContinuation: Boolean): Boolean;
var
  Following, Overflowed: Boolean;
  Slot, K, Keep, Grown: Integer;
begin
  { This is decided before the number of lines changes. }
  Following := IsFollowingTerminal;
  Overflowed := False;
  if NumLines >= maxSize then
  begin
    Overflowed := True;
    SetLength(FRing[FHead].Cells, 0);
    FHead := (FHead + 1) mod Length(FRing);
    Dec(FStored);
    if not Following then
      Offset := Max(Offset - 1, 0);
  end;
  if FStored >= Length(FRing) then
  begin
    Grown := Max(16, Length(FRing) * 2);
    if Grown > maxSize then
      Grown := maxSize;
    SetLength(FRing, Grown);
  end;
  Slot := SlotOf(FStored);
  Keep := Min(ACols, Length(ACells));
  SetLength(FRing[Slot].Cells, Max(ACols, 0));
  for K := 0 to High(FRing[Slot].Cells) do
    if K < Keep then
      FRing[Slot].Cells[K] := ACells[K]
    else
      FRing[Slot].Cells[K] := DefaultCell;
  FRing[Slot].Cols := ACols;
  FRing[Slot].Continuation := AContinuation;
  Inc(FStored);
  if Following then
    Offset := FStored;
  Result := not Overflowed;
end;

function Scrollback.PopLine(out ACells: TVtCellArray; out ACols: Integer; out AContinuation: Boolean): Boolean;
var
  Following: Boolean;
  Slot: Integer;
begin
  Result := FStored > 0;
  if not Result then
  begin
    ACells := nil;
    ACols := 0;
    AContinuation := False;
    Exit;
  end;
  Following := IsFollowingTerminal;
  Slot := SlotOf(FStored - 1);
  ACells := FRing[Slot].Cells;
  ACols := FRing[Slot].Cols;
  AContinuation := FRing[Slot].Continuation;
  FRing[Slot].Cells := nil;
  Dec(FStored);
  if Following then
    Offset := FStored
  else
    Offset := Min(Offset, FStored);
end;

procedure Scrollback.IncrementOffset(ACount: Integer);
begin
  if ACount < 0 then
    Offset := Max(Offset + ACount, 0)
  else
    Offset := Min(Offset + ACount, NumLines);
end;

procedure Scrollback.SetOffset(ANewOffset: Integer);
begin
  Offset := Min(Max(0, ANewOffset), NumLines);
end;

procedure Scrollback.FollowTerminal;
begin
  Offset := NumLines;
end;

function Scrollback.IsFollowingTerminal: Boolean;
begin
  Result := Offset = NumLines;
end;

function Scrollback.GetVisibleScrollLines(ATerminalHeight: Integer): Integer;
var
  Available: Integer;
begin
  Available := Max(NumLines - Offset, 0);
  Result := Min(Available, ATerminalHeight);
end;

function Scrollback.NumLines: Integer;
begin
  Result := FStored;
end;

function Scrollback.LineAt(AIndex: Integer): PVtLine;
begin
  Result := @FRing[SlotOf(AIndex)];
end;

procedure Scrollback.Clear;
begin
  SetLength(FRing, 0);
  FHead := 0;
  FStored := 0;
  Offset := 0;
end;

{ TVtScreen: construction and helpers }

constructor TVtScreen.Create(ACols, ARows: Integer);
begin
  inherited Create;
  FCols := Max(ACols, 1);
  FRows := Max(ARows, 1);
  FHistory := Scrollback.Create;
  FAltActive := False;
  FAutoWrap := True;
  FPending := False;
  FCurX := 0;
  FCurY := 0;
  FTop := 0;
  FBottom := FRows - 1;
  FPenFg := DefaultColor;
  FPenBg := DefaultColor;
  FPenAttrs := [];
  FSavedX := 0;
  FSavedY := 0;
  FSavedPending := False;
  FSavedFg := DefaultColor;
  FSavedBg := DefaultColor;
  FSavedAttrs := [];
  FCursorVisible := True;
  FCursorBlink := False;
  FCursorChanged := True;
  FMouseEnabled := False;
  FShownOffset := 0;
  FShownLines := 0;
  FOverflowed := False;
  FGrid := NewGrid;
  ResetTabs;
  DamageAll;
end;

destructor TVtScreen.Destroy;
begin
  FHistory.Free;
  inherited Destroy;
end;

function TVtScreen.BlankCell: TVtCell;
begin
  Result := DefaultCell;
  Result.Bg := FPenBg;
end;

function TVtScreen.MakeBlankRow: TVtRow;
var
  Blank: TVtCell;
  K: Integer;
begin
  Blank := BlankCell;
  SetLength(Result.Cells, FCols);
  for K := 0 to FCols - 1 do
    Result.Cells[K] := Blank;
  Result.Continuation := False;
end;

function TVtScreen.NewGrid: TVtRowArray;
var
  K: Integer;
begin
  SetLength(Result, FRows);
  for K := 0 to FRows - 1 do
    Result[K] := MakeBlankRow;
end;

function TVtScreen.RowFromLine(const ACells: TVtCellArray; ACols: Integer; AContinuation: Boolean): TVtRow;
var
  K, Keep: Integer;
begin
  Keep := Min(Min(ACols, Length(ACells)), FCols);
  SetLength(Result.Cells, FCols);
  for K := 0 to FCols - 1 do
    if K < Keep then
      Result.Cells[K] := ACells[K]
    else
      Result.Cells[K] := DefaultCell;
  Result.Continuation := AContinuation;
end;

procedure TVtScreen.Damage(ARow, AFrom, ATo: Integer);
begin
  if (ARow < 0) or (ARow >= Length(FDamage)) or (ATo <= AFrom) then
    Exit;
  FDamage[ARow] := RowRange.Create(Min(AFrom, FDamage[ARow].Start), Max(ATo, FDamage[ARow].RangeEnd));
end;

procedure TVtScreen.DamageAll;
var
  K: Integer;
begin
  SetLength(FDamage, 0);
  SetLength(FDamage, FRows);
  for K := 0 to FRows - 1 do
    FDamage[K] := RowRange.Create(0, FCols);
end;

procedure TVtScreen.ResetTabs;
var
  K: Integer;
begin
  SetLength(FTabs, FCols);
  for K := 0 to FCols - 1 do
    FTabs[K] := (K mod 8) = 0;
end;

{ When a cell that belongs to a wide character is overwritten, the other half of it becomes blank. }
procedure TVtScreen.ReleasePartner(ARow, AX: Integer);
begin
  if IsWideTrail(FGrid[ARow].Cells[AX]) then
  begin
    if AX > 0 then
    begin
      FGrid[ARow].Cells[AX - 1] := BlankCell;
      Damage(ARow, AX - 1, AX);
    end;
  end
  else if IsWideLead(FGrid[ARow].Cells[AX]) and (AX + 1 < FCols) then
  begin
    FGrid[ARow].Cells[AX + 1] := BlankCell;
    Damage(ARow, AX + 1, AX + 2);
  end;
end;

procedure TVtScreen.ClearSpan(ARow, AFrom, ATo: Integer);
var
  K, First, Past: Integer;
begin
  First := Max(AFrom, 0);
  Past := Min(ATo, FCols);
  for K := First to Past - 1 do
  begin
    ReleasePartner(ARow, K);
    FGrid[ARow].Cells[K] := BlankCell;
  end;
  if (First = 0) and (Past = FCols) then
    FGrid[ARow].Continuation := False;
  Damage(ARow, First, Past);
end;

{ Blanks the halves of wide characters that lost their other half in an insertion or deletion. }
procedure TVtScreen.RepairRow(ARow: Integer);
var
  K: Integer;
begin
  for K := 0 to FCols - 1 do
  begin
    if IsWideTrail(FGrid[ARow].Cells[K]) then
    begin
      if (K = 0) or not IsWideLead(FGrid[ARow].Cells[K - 1]) then
        FGrid[ARow].Cells[K] := BlankCell;
    end
    else if IsWideLead(FGrid[ARow].Cells[K]) then
    begin
      if (K = FCols - 1) or not IsWideTrail(FGrid[ARow].Cells[K + 1]) then
        FGrid[ARow].Cells[K] := BlankCell;
    end;
  end;
end;

procedure TVtScreen.PushRowToHistory(ARow: Integer);
begin
  if not FHistory.PushLine(FCols, FGrid[ARow].Cells, FGrid[ARow].Continuation) then
    FOverflowed := True;
end;

{ Moves the rows ATop..ABottom by AAmount rows, up or down, and gives the freed rows blank cells. A move up of a
  region that is the whole main screen pushes the rows that leave it to the history. }
procedure TVtScreen.ShiftLines(ATop, ABottom, AAmount: Integer; AUp: Boolean);
var
  Height, Moved, K: Integer;
begin
  Height := ABottom - ATop + 1;
  if (Height <= 0) or (AAmount <= 0) then
    Exit;
  Moved := Min(AAmount, Height);
  if AUp then
  begin
    if (not FAltActive) and (ATop = 0) and (ABottom = FRows - 1) then
      for K := 0 to Moved - 1 do
        PushRowToHistory(K);
    for K := ATop to ABottom - Moved do
      FGrid[K] := FGrid[K + Moved];
    for K := ABottom - Moved + 1 to ABottom do
      FGrid[K] := MakeBlankRow;
  end
  else
  begin
    for K := ABottom downto ATop + Moved do
      FGrid[K] := FGrid[K - Moved];
    for K := ATop to ATop + Moved - 1 do
      FGrid[K] := MakeBlankRow;
  end;
  for K := ATop to ABottom do
    Damage(K, 0, FCols);
end;

procedure TVtScreen.WrapLine;
begin
  FCurX := 0;
  LineFeed;
  FGrid[FCurY].Continuation := True;
  FCursorChanged := True;
end;

procedure TVtScreen.AppendMark(ACode: Cardinal);
var
  Target, Slot: Integer;
begin
  Target := FCurX;
  if not FPending then
    Dec(Target);
  if Target < 0 then
    Exit;
  if IsWideTrail(FGrid[FCurY].Cells[Target]) and (Target > 0) then
    Dec(Target);
  if FGrid[FCurY].Cells[Target].Chars[0] = 0 then
  begin
    FGrid[FCurY].Cells[Target].Chars[0] := 32;
    FGrid[FCurY].Cells[Target].Width := 1;
  end;
  Slot := 1;
  while (Slot < VtMaxChars) and (FGrid[FCurY].Cells[Target].Chars[Slot] <> 0) do
    Inc(Slot);
  if Slot < VtMaxChars then
    FGrid[FCurY].Cells[Target].Chars[Slot] := ACode;
  Damage(FCurY, Target, Target + Max(1, FGrid[FCurY].Cells[Target].Width));
end;

{ The pen }

procedure TVtScreen.SetPenColors(const AFg, ABg: TVtColor);
begin
  FPenFg := AFg;
  FPenBg := ABg;
end;

procedure TVtScreen.SetPenAttrs(AAttrs: TVtAttrs);
begin
  FPenAttrs := AAttrs;
end;

procedure TVtScreen.ResetPen;
begin
  FPenFg := DefaultColor;
  FPenBg := DefaultColor;
  FPenAttrs := [];
end;

{ Writing }

procedure TVtScreen.PutChar(ACode: Cardinal; AWidth: Integer);
var
  Lead, Trail: TVtCell;
  Wid, K: Integer;
begin
  Wid := Min(Max(AWidth, 1), 2);
  if FCols < 2 then
    Wid := 1;
  if FPending and FAutoWrap then
    WrapLine;
  FPending := False;
  if (Wid = 2) and (FCurX = FCols - 1) then
  begin
    if not FAutoWrap then
      Exit;
    ClearSpan(FCurY, FCurX, FCurX + 1);
    WrapLine;
  end;

  Lead := DefaultCell;
  Lead.Chars[0] := ACode;
  Lead.Width := Wid;
  Lead.Fg := FPenFg;
  Lead.Bg := FPenBg;
  Lead.Attrs := FPenAttrs;
  ReleasePartner(FCurY, FCurX);
  FGrid[FCurY].Cells[FCurX] := Lead;
  if Wid = 2 then
  begin
    Trail := Lead;
    Trail.Chars[0] := VtWideTrail;
    for K := 1 to VtMaxChars - 1 do
      Trail.Chars[K] := 0;
    Trail.Width := 0;
    ReleasePartner(FCurY, FCurX + 1);
    FGrid[FCurY].Cells[FCurX + 1] := Trail;
  end;
  Damage(FCurY, FCurX, FCurX + Wid);

  if FCurX + Wid >= FCols then
  begin
    FCurX := FCols - 1;
    FPending := FAutoWrap;
  end
  else
    Inc(FCurX, Wid);
  FCursorChanged := True;
end;

procedure TVtScreen.PutText(const AText: AnsiString);
var
  Pos, Extra, Wid: Integer;
  Code: Cardinal;
  Lead: Byte;
begin
  Pos := 1;
  while Pos <= Length(AText) do
  begin
    Lead := Byte(AText[Pos]);
    Extra := Utf8BytesLeft(Lead);
    if ((Lead >= $80) and (Extra = 0)) or (Pos + Extra > Length(AText)) then
    begin
      Inc(Pos);
      Continue;
    end;
    Code := Utf8To32(Copy(AText, Pos, Extra + 1));
    Inc(Pos, Extra + 1);
    case Code of
      8: Backspace;
      9: Tab(1);
      10: LineFeed;
      13: CarriageReturn;
    else
      Wid := CharWidth(Code);
      if Wid > 0 then
        PutChar(Code, Wid)
      else if (Wid = 0) and (Code <> 0) then
        AppendMark(Code);
    end;
  end;
end;

{ Cursor movement }

function TVtScreen.CursorX: Integer;
begin
  Result := FCurX;
end;

procedure TVtScreen.MoveTo(AX, AY: Integer);
var
  NewX, NewY: Integer;
begin
  NewX := Min(Max(AX, 0), FCols - 1);
  NewY := Min(Max(AY, 0), FRows - 1);
  if (NewX <> FCurX) or (NewY <> FCurY) then
    FCursorChanged := True;
  FCurX := NewX;
  FCurY := NewY;
  FPending := False;
end;

procedure TVtScreen.MoveBy(ADX, ADY: Integer);
begin
  MoveTo(FCurX + ADX, FCurY + ADY);
end;

procedure TVtScreen.LineFeed;
begin
  FPending := False;
  if FCurY = FBottom then
    ShiftLines(FTop, FBottom, 1, True)
  else if FCurY < FRows - 1 then
  begin
    Inc(FCurY);
    FCursorChanged := True;
  end;
end;

procedure TVtScreen.ReverseIndex;
begin
  FPending := False;
  if FCurY = FTop then
    ShiftLines(FTop, FBottom, 1, False)
  else if FCurY > 0 then
  begin
    Dec(FCurY);
    FCursorChanged := True;
  end;
end;

procedure TVtScreen.CarriageReturn;
begin
  MoveTo(0, FCurY);
end;

procedure TVtScreen.Backspace;
begin
  MoveTo(FCurX - 1, FCurY);
end;

function TVtScreen.CursorY: Integer;
begin
  Result := FCurY;
end;

procedure TVtScreen.Tab(ACount: Integer);
var
  Step, Target: Integer;
begin
  for Step := 1 to ACount do
  begin
    Target := FCurX + 1;
    while (Target < FCols - 1) and not FTabs[Target] do
      Inc(Target);
    FCurX := Min(Target, FCols - 1);
  end;
  FPending := False;
  FCursorChanged := True;
end;

procedure TVtScreen.BackTab(ACount: Integer);
var
  Step, Target: Integer;
begin
  for Step := 1 to ACount do
  begin
    Target := FCurX - 1;
    while (Target > 0) and not FTabs[Target] do
      Dec(Target);
    FCurX := Max(Target, 0);
  end;
  FPending := False;
  FCursorChanged := True;
end;

procedure TVtScreen.SetTabStop;
begin
  FTabs[FCurX] := True;
end;

procedure TVtScreen.ClearTabStop;
begin
  FTabs[FCurX] := False;
end;

procedure TVtScreen.ClearAllTabStops;
var
  K: Integer;
begin
  for K := 0 to High(FTabs) do
    FTabs[K] := False;
end;

{ Erasing, inserting and deleting }

function TVtScreen.WrapPending: Boolean;
begin
  Result := FPending and FAutoWrap;
end;

procedure TVtScreen.EraseInLine(AMode: Integer);
begin
  case AMode of
    0: ClearSpan(FCurY, FCurX, FCols);
    1: ClearSpan(FCurY, 0, FCurX + 1);
    2: ClearSpan(FCurY, 0, FCols);
  end;
end;

procedure TVtScreen.EraseInDisplay(AMode: Integer);
var
  K: Integer;
begin
  case AMode of
    0:
      begin
        ClearSpan(FCurY, FCurX, FCols);
        for K := FCurY + 1 to FRows - 1 do
          ClearSpan(K, 0, FCols);
      end;
    1:
      begin
        for K := 0 to FCurY - 1 do
          ClearSpan(K, 0, FCols);
        ClearSpan(FCurY, 0, FCurX + 1);
      end;
    2:
      for K := 0 to FRows - 1 do
        ClearSpan(K, 0, FCols);
    3:
      FHistory.Clear;
  end;
end;

procedure TVtScreen.EraseChars(ACount: Integer);
begin
  if ACount > 0 then
    ClearSpan(FCurY, FCurX, FCurX + ACount);
end;

procedure TVtScreen.InsertChars(ACount: Integer);
var
  N, K: Integer;
  Blank: TVtCell;
begin
  N := Min(ACount, FCols - FCurX);
  if N <= 0 then
    Exit;
  Blank := BlankCell;
  for K := FCols - 1 downto FCurX + N do
    FGrid[FCurY].Cells[K] := FGrid[FCurY].Cells[K - N];
  for K := FCurX to FCurX + N - 1 do
    FGrid[FCurY].Cells[K] := Blank;
  RepairRow(FCurY);
  Damage(FCurY, FCurX, FCols);
  FPending := False;
end;

procedure TVtScreen.DeleteChars(ACount: Integer);
var
  N, K: Integer;
  Blank: TVtCell;
begin
  N := Min(ACount, FCols - FCurX);
  if N <= 0 then
    Exit;
  Blank := BlankCell;
  for K := FCurX to FCols - 1 - N do
    FGrid[FCurY].Cells[K] := FGrid[FCurY].Cells[K + N];
  for K := FCols - N to FCols - 1 do
    FGrid[FCurY].Cells[K] := Blank;
  RepairRow(FCurY);
  Damage(FCurY, FCurX, FCols);
  FPending := False;
end;

procedure TVtScreen.InsertLines(ACount: Integer);
begin
  if (FCurY < FTop) or (FCurY > FBottom) then
    Exit;
  ShiftLines(FCurY, FBottom, ACount, False);
  MoveTo(0, FCurY);
end;

procedure TVtScreen.DeleteLines(ACount: Integer);
begin
  if (FCurY < FTop) or (FCurY > FBottom) then
    Exit;
  ShiftLines(FCurY, FBottom, ACount, True);
  MoveTo(0, FCurY);
end;

procedure TVtScreen.ScrollUp(ACount: Integer);
begin
  ShiftLines(FTop, FBottom, ACount, True);
end;

procedure TVtScreen.ScrollDown(ACount: Integer);
begin
  ShiftLines(FTop, FBottom, ACount, False);
end;

procedure TVtScreen.SetScrollRegion(ATop, ABottom: Integer);
var
  First, Last: Integer;
begin
  First := Max(ATop, 0);
  Last := Min(ABottom, FRows - 1);
  if First >= Last then
  begin
    First := 0;
    Last := FRows - 1;
  end;
  FTop := First;
  FBottom := Last;
  MoveTo(0, 0);
end;

procedure TVtScreen.SaveCursor;
begin
  FSavedX := FCurX;
  FSavedY := FCurY;
  FSavedPending := FPending;
  FSavedFg := FPenFg;
  FSavedBg := FPenBg;
  FSavedAttrs := FPenAttrs;
end;

procedure TVtScreen.RestoreCursor;
begin
  MoveTo(FSavedX, FSavedY);
  FPending := FSavedPending and (FCurX = FCols - 1);
  FPenFg := FSavedFg;
  FPenBg := FSavedBg;
  FPenAttrs := FSavedAttrs;
end;

function TVtScreen.CursorVisible: Boolean;
begin
  Result := FCursorVisible;
end;

procedure TVtScreen.SetCursorVisible(AValue: Boolean);
begin
  FCursorChanged := True;
  FCursorVisible := AValue;
end;

procedure TVtScreen.SetCursorBlink(AValue: Boolean);
begin
  FCursorChanged := True;
  FCursorBlink := AValue;
end;

function TVtScreen.AltScreen: Boolean;
begin
  Result := FAltActive;
end;

function TVtScreen.CursorBlink: Boolean;
begin
  Result := FCursorBlink;
end;

procedure TVtScreen.EnableAltScreen(AOn: Boolean);
begin
  if AOn = FAltActive then
    Exit;
  if AOn then
  begin
    FStash := FGrid;
    FGrid := NewGrid;
    FAltActive := True;
    FHistory.FollowTerminal;
  end
  else
  begin
    FGrid := FStash;
    FStash := nil;
    FAltActive := False;
  end;
  DamageAll;
end;

{ Resize }

procedure TVtScreen.AdjustGridRows(var AGrid: TVtRowArray; ANewRows: Integer; var ACursorY: Integer;
  AUseHistory: Boolean);
var
  Old, Excess, Extra, Brought, K, LineCols: Integer;
  LineCells: TVtCellArray;
  LineCont: Boolean;
  Popped, Fresh: TVtRowArray;
begin
  Old := Length(AGrid);
  if ANewRows < Old then
  begin
    Excess := Old - ANewRows;
    { Blank rows below the cursor go first. }
    while (Excess > 0) and (Length(AGrid) - 1 > ACursorY) and RowIsBlank(AGrid[Length(AGrid) - 1]) do
    begin
      SetLength(AGrid, Length(AGrid) - 1);
      Dec(Excess);
    end;
    while Excess > 0 do
    begin
      if AUseHistory then
        if not FHistory.PushLine(FCols, AGrid[0].Cells, AGrid[0].Continuation) then
          FOverflowed := True;
      for K := 1 to High(AGrid) do
        AGrid[K - 1] := AGrid[K];
      SetLength(AGrid, Length(AGrid) - 1);
      if ACursorY > 0 then
        Dec(ACursorY);
      Dec(Excess);
    end;
  end
  else if ANewRows > Old then
  begin
    Extra := ANewRows - Old;
    Brought := 0;
    while AUseHistory and (Brought < Extra) and FHistory.PopLine(LineCells, LineCols, LineCont) do
    begin
      SetLength(Popped, Brought + 1);
      Popped[Brought] := RowFromLine(LineCells, LineCols, LineCont);
      Inc(Brought);
    end;
    SetLength(Fresh, ANewRows);
    for K := 0 to Brought - 1 do
      Fresh[K] := Popped[Brought - 1 - K];
    for K := 0 to Old - 1 do
      Fresh[Brought + K] := AGrid[K];
    for K := Brought + Old to ANewRows - 1 do
      Fresh[K] := MakeBlankRow;
    AGrid := Fresh;
    ACursorY := ACursorY + Brought;
  end;
end;

procedure TVtScreen.AdjustGridCols(var AGrid: TVtRowArray; ANewCols: Integer);
var
  R, K, Old: Integer;
begin
  for R := 0 to High(AGrid) do
  begin
    Old := Length(AGrid[R].Cells);
    SetLength(AGrid[R].Cells, ANewCols);
    for K := Old to ANewCols - 1 do
      AGrid[R].Cells[K] := DefaultCell;
    if (ANewCols < Old) and IsWideLead(AGrid[R].Cells[ANewCols - 1]) then
      AGrid[R].Cells[ANewCols - 1] := DefaultCell;
  end;
end;

procedure TVtScreen.Resize(ANewCols, ANewRows: Integer);
var
  WantCols, WantRows, WorkY, SpareY, K, OldCols: Integer;
begin
  WantCols := Max(ANewCols, 1);
  WantRows := Max(ANewRows, 1);
  if (WantCols = FCols) and (WantRows = FRows) then
    Exit;

  WorkY := FCurY;
  AdjustGridRows(FGrid, WantRows, WorkY, not FAltActive);
  FCurY := WorkY;
  if Length(FStash) > 0 then
  begin
    SpareY := 0;
    AdjustGridRows(FStash, WantRows, SpareY, False);
  end;
  FRows := WantRows;

  if WantCols <> FCols then
  begin
    AdjustGridCols(FGrid, WantCols);
    if Length(FStash) > 0 then
      AdjustGridCols(FStash, WantCols);
    OldCols := FCols;
    SetLength(FTabs, WantCols);
    for K := OldCols to WantCols - 1 do
      FTabs[K] := (K mod 8) = 0;
    FCols := WantCols;
  end;

  FCurX := Min(FCurX, FCols - 1);
  FCurY := Min(Max(FCurY, 0), FRows - 1);
  FSavedX := Min(FSavedX, FCols - 1);
  FSavedY := Min(FSavedY, FRows - 1);
  FPending := False;
  FTop := 0;
  FBottom := FRows - 1;
  FCursorChanged := True;
  DamageAll;
end;

{ Reading }

function TVtScreen.GetCell(ARow, ACol: Integer; out ACell: TVtCell): Boolean;
begin
  Result := (ARow >= 0) and (ARow < FRows) and (ACol >= 0) and (ACol < FCols);
  if Result then
    ACell := FGrid[ARow].Cells[ACol]
  else
    ACell := DefaultCell;
end;

function TVtScreen.LineContinues(ARow: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow < FRows) and FGrid[ARow].Continuation;
end;

{ The surface }

procedure TVtScreen.DrawScrollbackLine(ASurface: TerminalSurface; AY: Integer);
var
  Entry: PVtLine;
  Buf: TCellRow;
  Blank: TVtCell;
  X: Integer;
begin
  Entry := FHistory.LineAt(FHistory.Offset + AY);
  LoadRow(ASurface, AY, Buf);
  Blank := DefaultCell;
  for X := 0 to ASurface.Size.X - 1 do
    if X < Entry^.Cols then
      ConvCell(Buf, X, Entry^.Cells[X])
    else
      ConvCell(Buf, X, Blank);
  StoreRow(ASurface, AY, Buf);
  ASurface.AddDamageAtRow(AY, 0, ASurface.Size.X);
end;

{ Pre: the area is within bounds. }
procedure TVtScreen.DrawLine(ASurface: TerminalSurface; AY, ARowIndex, AStart, AEnd: Integer);
var
  Buf: TCellRow;
  Cell: TVtCell;
  X: Integer;
begin
  LoadRow(ASurface, AY, Buf);
  for X := AStart to AEnd - 1 do
    if GetCell(ARowIndex, X, Cell) then
      ConvCell(Buf, X, Cell)
    else
      FillChar(Buf[X], SizeOf(TScreenCell), 0);
  StoreRow(ASurface, AY, Buf);
  ASurface.AddDamageAtRow(AY, AStart, AEnd);
end;

procedure TVtScreen.UpdateSurface(ASurface: TerminalSurface);
var
  Wanted: TPoint;
  Resized, AreaChanged, NeedsRedraw: Boolean;
  Visible, Y, RowIndex, First, Past: Integer;
  Hurt: PRowRange;
begin
  { Make sure the surface has the right size. }
  Wanted.X := FCols;
  Wanted.Y := FRows;
  Resized := ASurface.Size <> Wanted;
  if Resized then
    ASurface.Resize(Wanted);

  { Draw the scrollback if it is visible. }
  Visible := FHistory.GetVisibleScrollLines(FRows);
  AreaChanged := (FHistory.Offset <> FShownOffset) or (Visible <> FShownLines) or
    (FOverflowed and (FHistory.Offset = 0));
  FShownOffset := FHistory.Offset;
  FShownLines := Visible;
  FOverflowed := False;

  { The scrollback content is immutable, but when it or the size change everything is drawn again. }
  NeedsRedraw := AreaChanged or Resized;
  if NeedsRedraw then
    for Y := 0 to Visible - 1 do
      DrawScrollbackLine(ASurface, Y);

  { Draw the display of the terminal. }
  for Y := Visible to FRows - 1 do
  begin
    RowIndex := Y - Visible;
    Hurt := @FDamage[RowIndex];
    if NeedsRedraw then
    begin
      First := 0;
      Past := FCols;
    end
    else
    begin
      First := Max(Hurt^.Start, 0);
      Past := Min(Hurt^.RangeEnd, FCols);
    end;
    if First < Past then
      DrawLine(ASurface, Y, RowIndex, First, Past);
    Hurt^ := RowRange.Unset;
  end;
end;

procedure TVtScreen.UpdateState(AState: TerminalState);
var
  Differs: Boolean;
begin
  UpdateSurface(AState.Surface);

  if FCursorChanged then
  begin
    FCursorChanged := False;
    AState.CursorChanged := True;
    AState.CursorPos.X := FCurX;
    AState.CursorPos.Y := FCurY;
    AState.CursorVisible := FCursorVisible;
    AState.CursorBlink := FCursorBlink;
  end;

  Differs := (FHistory.Offset <> AState.ScrollbackOffset) or
    (FHistory.NumLines <> AState.ScrollbackLimit) or
    ((not FAltActive) <> AState.ScrollbackEnabled);
  if Differs then
  begin
    AState.ScrollbackChanged := True;
    AState.ScrollbackOffset := FHistory.Offset;
    AState.ScrollbackLimit := FHistory.NumLines;
    { The scroll bar is hidden in the alternate screen, so that it is not taken for the content of the client. }
    AState.ScrollbackEnabled := not FAltActive;
  end;

  AState.MouseEnabled := FMouseEnabled;
end;

procedure TVtScreen.HandleScrollbackWheel(AWheel: Byte);
begin
  if AWheel = mwUp then
    FHistory.IncrementOffset(-mouseWheelScrollLines)
  else if AWheel = mwDown then
    FHistory.IncrementOffset(mouseWheelScrollLines);
end;

{ The text of a selection }

{ Pre: 0 <= AY < FHistory.NumLines }
procedure TVtScreen.ExtractScrollbackLineText(AY, AStartX, AEndX: Integer; var AText: AnsiString;
  var APadding: Integer);
var
  Entry: PVtLine;
  Last, X: Integer;
  AddNewline: Boolean;
begin
  Entry := FHistory.LineAt(AY);
  Last := Min(AEndX, Entry^.Cols);

  if (AStartX < Entry^.Cols) and (Last > 0) then
    for X := AStartX to Min(Last, Entry^.Cols) - 1 do
      ExtractCellText(Entry^.Cells[X], AText, APadding);

  if Last = Entry^.Cols then
  begin
    if AY < FHistory.NumLines - 1 then
      AddNewline := not FHistory.LineAt(AY + 1)^.Continuation
    else
      AddNewline := not FGrid[0].Continuation;
    if AddNewline then
    begin
      AText := AText + #10;
      APadding := 0;
    end;
  end;
end;

{ Pre: 0 <= AY < FRows }
procedure TVtScreen.ExtractTerminalLineText(AY, AStartX, AEndX: Integer; var AText: AnsiString;
  var APadding: Integer);
var
  Last, X: Integer;
  Cell: TVtCell;
begin
  Last := Min(AEndX, FCols);

  if (AStartX < FCols) and (Last > 0) then
    for X := AStartX to Last - 1 do
      if GetCell(AY, X, Cell) then
        ExtractCellText(Cell, AText, APadding);

  if (Last = FCols) and (AY < FRows - 1) then
    if not FGrid[AY + 1].Continuation then
    begin
      AText := AText + #10;
      APadding := 0;
    end;
end;

function TVtScreen.CopySelection(const ASelection: SelectionRange): AnsiString;
var
  Low, High: SelectionAnchor;
  MaxY, FirstY, LastY, Y, FromX, ToX, Padding: Integer;
begin
  if ASelection.RangeEnd < ASelection.Start then
  begin
    Low := ASelection.RangeEnd;
    High := ASelection.Start;
  end
  else
  begin
    Low := ASelection.Start;
    High := ASelection.RangeEnd;
  end;

  MaxY := FHistory.NumLines + FRows;
  FirstY := Max(0, Low.Y);
  LastY := Min(High.Y + 1, MaxY);

  Result := '';
  Padding := 0;
  for Y := FirstY to LastY - 1 do
  begin
    if Y = Low.Y then
      FromX := Max(0, Low.X)
    else
      FromX := 0;
    if Y = High.Y then
      ToX := High.X
    else
      ToX := MaxInt;

    if Y < FHistory.NumLines then
      ExtractScrollbackLineText(Y, FromX, ToX, Result, Padding)
    else
      ExtractTerminalLineText(Y - FHistory.NumLines, FromX, ToX, Result, Padding);
  end;
end;

end.
