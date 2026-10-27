{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/views.h (TListViewer), include/tvision/dialogs.h (TListBox, TListBoxRec),
  include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h, source/tvision/tlstview.cpp,
  source/tvision/tlistbox.cpp, source/tvision/tvtext1.cpp (specialChars)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit.

  Parts of the C++ that have no unit yet:
    - message() sends a message to a view; MessageHook of TvViews stands for it and does nothing while it is nil.

  The text that a list viewer shows for an item is returned by GetText as a string, in the place of the buffer and
  the length that the C++ takes; MaxLen is the largest length of the text. The items of a TListBox are blocks of
  characters with a terminating zero, as the C++ keeps them.

  The static member emptyText of TListViewer is defined in a file that is not among the sources of the unit, so it is
  the class variable EmptyText, which starts as an empty text and which the program sets. The array specialChars,
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

end.
