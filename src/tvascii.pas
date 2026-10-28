{ A table-of-characters window for the view library.

  TAsciiTable shows 256 codes in 8 rows of 32 cells with a movable cursor. In code page mode the codes are the bytes
  0..255 and every cell holds one raw byte, which the screen layer shows through the code page. In Unicode mode the
  table shows one block of 256 code points, Block * 256 .. Block * 256 + 255. The user moves the cursor with keys or
  the mouse and picks a code with Enter, a double click or by typing the character; a pick calls OnPick and sends the
  command AsciiCommandBase + acPicked to the owner. TAsciiReport shows the code under the cursor of a table, and
  TAsciiChart is a window that holds a table and a report.

  The text of a cell comes from the hook CharText of the table, which a program may replace. The keys that move the
  cursor are chosen by the virtual method KeyAction and the typed character by TypedCode, so that a subclass can
  change them. Messages are sent through MessageHook of TvViews and are lost while it is nil.

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

end.
