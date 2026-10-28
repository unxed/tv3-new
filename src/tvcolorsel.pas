{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/colorsel.h, source/tvision/colorsel.cpp, source/tvision/tvtext1.cpp (the texts and the
  tables of TColorSelector, TMonoSelector and TColorDialog), include/tvision/views.h, include/tvision/ttypes.h,
  include/tvision/config.h, include/tvision/tv.h
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, the constructors with StreamableInit and the members
  writeItems, writeGroups, readItems and readGroups of TColorGroupList belong to a later unit.

  Parts of the C++ that have no unit yet:
    - message() sends a message to a view; MessageHook of TvViews stands for it and does nothing while it is nil.

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

end.
