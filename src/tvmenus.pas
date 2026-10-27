{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/menus.h, include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h,
  include/tvision/views.h, source/tvision/menu.cpp, source/tvision/popupmnu.cpp, source/tvision/tmenubar.cpp,
  source/tvision/tmenubox.cpp, source/tvision/tmenupop.cpp, source/tvision/tmnuview.cpp,
  source/tvision/tstatusl.cpp, source/tvision/tvtext1.cpp
  See COPYRIGHT.magiblot.

  The views of this unit are used by the thread of the user interface only.

  A text of the C++ that is a char pointer which may be null (the name and the parameter of a menu item, the text
  of a status item) is a PAnsiChar, allocated by NewStr and released with FreeMem; a null name marks a separator.
  The argument of a constructor or of a routine that is a TStringView is a string. The union of param and subMenu
  of TMenuItem is one pointer, which the properties Param and SubMenu read and write. Because a Pascal string has
  no null value, a constructor of TMenuItem always allocates the name, and NewLine, which has a null name, releases
  it. The reference parameters of the C++ that stand for objects are object parameters.

  The operators + that chain menu items, sub menus, status items and status definitions are global operators.

  Streaming members (read, write, build, streamableName, the constructors with StreamableInit) are not part of
  this unit.

  Parts of the C++ that no input defines are reached through hooks, which do nothing while they are nil:
    - hotKeyStr stands for HotKeyStrHook; while it is nil, a menu item has no shortcut character;
    - TText::equalsIgnoreCase stands for EqualsIgnoreCaseHook; while it is nil, two texts are not equal;
    - TProgram::application stands for ApplicationHook; while it is nil, PopupMenu answers 0.
  The tables TMenuBox.FrameChars and TStatusLine.HintSeparator are class variables, set to their values when the
  unit starts. The characters are code page 437 bytes written as numbers. }
unit TvMenus;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvKeys, TvEvents, TvObjs, TvColors, TvDrawBuf, TvViews;

type
  TMenu = class;
  TMenuItem = class;
  TSubMenu = class;
  TMenuView = class;
  TMenuBox = class;
  TStatusItem = class;
  TStatusDef = class;

  TMenuItem = class
  private
    { Holds param (a PAnsiChar) when Command is not 0 and subMenu (a TMenu) when it is 0. }
    Ptr: Pointer;
    function GetParam: PAnsiChar;
    procedure SetParam(Value: PAnsiChar);
    function GetSubMenu: TMenu;
    procedure SetSubMenu(Value: TMenu);
  public
    Next: TMenuItem;
    Name: PAnsiChar;
    Command: Word;
    Disabled: Boolean;
    KeyCode: TKey;
    HelpCtx: Word;
    constructor Create(const AName: string; ACommand: Word; AKey: TKey; AHelpCtx: Word = hcNoContext;
      const P: string = ''; ANext: TMenuItem = nil); overload;
    constructor Create(const AName: string; AKey: TKey; ASubMenu: TMenu; AHelpCtx: Word = hcNoContext;
      ANext: TMenuItem = nil); overload;
    destructor Destroy; override;
    procedure Append(ANext: TMenuItem);
    property Param: PAnsiChar read GetParam write SetParam;
    property SubMenu: TMenu read GetSubMenu write SetSubMenu;
  end;

  TSubMenu = class(TMenuItem)
  public
    constructor Create(const Nm: string; Key: TKey; AHelpCtx: Word = hcNoContext); reintroduce;
  end;

  TMenu = class
  public
    Items: TMenuItem;
    Deflt: TMenuItem;
    constructor Create; overload;
    constructor Create(ItemList: TMenuItem); overload;
    constructor Create(ItemList, TheDefault: TMenuItem); overload;
    destructor Destroy; override;
  end;

  { Palette layout
      1 = Normal text
      2 = Disabled text
      3 = Shortcut text
      4 = Normal selection
      5 = Disabled selection
      6 = Shortcut selection }
  TMenuView = class(TView)
  protected
    ParentMenu: TMenuView;
    Menu: TMenu;
    Current: TMenuItem;
    PutClickEventOnExit: Boolean;
  private
    procedure NextItem;
    procedure PrevItem;
    procedure TrackKey(FindNext: Boolean);
    function MouseInOwner(var E: TEvent): Boolean;
    function MouseInMenus(var E: TEvent): Boolean;
    procedure TrackMouse(var E: TEvent; var MouseActive: Boolean);
    function TopMenu: TMenuView;
    function UpdateMenu(AMenu: TMenu): Boolean;
    procedure DoASelect(var Event: TEvent);
    function FindHotKey(P: TMenuItem; Key: TKey): TMenuItem;
    function FindAltShortcut(const KeyDown: TKeyDownEvent): TMenuItem;
  public
    constructor Create(const Bounds: TRect; AMenu: TMenu; AParent: TMenuView); reintroduce; overload;
    constructor Create(const Bounds: TRect); reintroduce; overload;
    function Execute: Word; override;
    function FindItem(Shortcut: Char): TMenuItem; overload;
    function FindItem(const Shortcut: string): TMenuItem; overload;
    function GetItemRect(Item: TMenuItem): TRect; virtual;
    function GetHelpCtx: Word; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function HotKey(Key: TKey): TMenuItem;
    function NewSubView(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView): TMenuView;
  end;

  TMenuBar = class(TMenuView)
  public
    constructor Create(const Bounds: TRect; AMenu: TMenu); reintroduce; overload;
    constructor Create(const Bounds: TRect; AMenu: TSubMenu); reintroduce; overload;
    destructor Destroy; override;
    procedure Draw; override;
    function GetItemRect(Item: TMenuItem): TRect; override;
  end;

  TMenuBox = class(TMenuView)
  private
    { The attributes that frameLine and draw share: the C++ keeps them in file-level variables. }
    CNormal: TAttrPair;
    Color: TAttrPair;
    procedure FrameLine(B: TDrawBuffer; N: SmallInt);
  public
    { The characters of the frame lines: four groups of five characters for the top line, the bottom line, an
      item line and a separator line. It is set when the unit starts. }
    class var FrameChars: string;
    constructor Create(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView); reintroduce;
    procedure Draw; override;
    function GetItemRect(Item: TMenuItem): TRect; override;
  end;

  TMenuPopup = class(TMenuBox)
  public
    constructor Create(const Bounds: TRect; AMenu: TMenu; AParentMenu: TMenuView = nil); reintroduce;
    destructor Destroy; override;
    function Execute: Word; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  TStatusItem = class
  public
    Next: TStatusItem;
    Text: PAnsiChar;
    KeyCode: TKey;
    Command: Word;
    constructor Create(const AText: string; AKey: TKey; Cmd: Word; ANext: TStatusItem = nil);
    destructor Destroy; override;
  end;

  TStatusDef = class
  public
    Next: TStatusDef;
    Min: Word;
    Max: Word;
    Items: TStatusItem;
    constructor Create(AMin, AMax: Word; SomeItems: TStatusItem = nil; ANext: TStatusDef = nil);
  end;

  { Palette layout
      1 = Normal text
      2 = Disabled text
      3 = Shortcut text
      4 = Normal selection
      5 = Disabled selection
      6 = Shortcut selection }
  TStatusLine = class(TView)
  protected
    Items: TStatusItem;
    Defs: TStatusDef;
  private
    procedure DrawSelect(Selected: TStatusItem);
    procedure FindItems;
    function ItemMouseIsIn(Mouse: TPoint): TStatusItem;
    procedure DisposeItems(Item: TStatusItem);
  public
    { The text between the items and the hint. It is set when the unit starts. }
    class var HintSeparator: string;
    constructor Create(const Bounds: TRect; ADefs: TStatusDef); reintroduce;
    destructor Destroy; override;
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Hint(AHelpCtx: Word): string; virtual;
    procedure Update;
  end;

  { Gives the shortcut of a menu item name (the Name is empty for a separator); the answer is empty when the
    name has no shortcut. }
  THotKeyStrFunc = function(const Name: string): string;
  { Tells whether two texts are equal when the case of letters is ignored. }
  TEqualsIgnoreCaseFunc = function(const A, B: string): Boolean;
  { Gives the root of the application, or nil. }
  TApplicationFunc = function: TGroup;

var
  HotKeyStrHook: THotKeyStrFunc;
  EqualsIgnoreCaseHook: TEqualsIgnoreCaseFunc;
  ApplicationHook: TApplicationFunc;

{ A separator line for a menu: an item without a name. }
function NewLine: TMenuItem;

{ Spawns and executes a TMenuPopup on the desktop. Where is the reference position in absolute coordinates; the top
  left corner of the popup is placed at (Where.X, Where.Y + 1) when there is room. AMenu is a chain of menu items,
  which the routine takes ownership of: the items are released with the popup. When Receiver is not nil and a
  command is selected, an evCommand event with it is put into Receiver with PutEvent. Returns the selected
  command, or 0. }
function PopupMenu(Where: TPoint; AMenu: TMenuItem; Receiver: TGroup): Word;

{ Each operator appends its second operand to the end of the chain of the first. The first operand is the result. }
operator +(S: TSubMenu; I: TMenuItem): TSubMenu;
operator +(S1, S2: TSubMenu): TSubMenu;
operator +(I1, I2: TMenuItem): TMenuItem;
operator +(S1: TStatusDef; S2: TStatusItem): TStatusDef;
operator +(S1, S2: TStatusDef): TStatusDef;

implementation

end.
