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

end.
