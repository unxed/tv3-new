{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (TSItem, TCluster, TRadioButtons, TCheckBoxes, TMultiCheckBoxes and the
  flags cfOneBit to cfEightBits), include/tvision/ttypes.h (specialChars), source/tvision/tcluster.cpp,
  source/tvision/tradiobu.cpp, source/tvision/tcheckbo.cpp, source/tvision/tmulchkb.cpp,
  source/tvision/tvtext1.cpp (the tables button of TRadioButtons and TCheckBoxes)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit. The classes of dialogs.h that are not named above belong to other units.

  Parts of the C++ that have no unit yet:
    - hotKey() returns the letter that a text marks with tildes; the HotKeyHook of TvDialog stands for it. While it
      is nil no item has a hot key, so an item answers to no letter;
    - TStringCollection has no unit; the strings of a cluster are a TCollection of blocks of characters from NewStr,
      which TCollection releases with FreeMem, and the cluster only inserts at the end, reads and counts them, as the
      C++ does.

  specialChars is the variable SpecialChars of TvDialog. The tables button of TRadioButtons and TCheckBoxes are the
  class variables Button of the two classes; they get their C++ values when the unit starts, in code page 437, and a
  program may change them.

  A text of the C++ that is a char pointer is a string here; the strings of a cluster are blocks of characters with a
  terminating zero, as the C++ keeps them. The record that GetData and SetData of a cluster read and write is
  a Word (a LongWord for TMultiCheckBoxes), as in the C++. }
unit TvCluster;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvObjs, TvViews;

const
  { The flags of a TMultiCheckBoxes: the low byte is the mask of the bits of one item and the high byte is the number
    of bits of an item. }
  cfOneBit = Word($0101);
  cfTwoBits = Word($0203);
  cfFourBits = Word($040F);
  cfEightBits = Word($08FF);

type
  { One string of a list of strings, with the next item of the list. The text is a block of characters that the item
    owns. }
  TSItem = class(TvObject)
  public
    Value: PAnsiChar;
    Next: TSItem;
    constructor Create(const AValue: string; ANext: TSItem);
    destructor Destroy; override;
  end;

  { A group of buttons that are laid out in columns of the height of the view. The palette is: 1 normal text,
    2 selected text, 3 normal shortcut, 4 selected shortcut, 5 disabled text. }
  TCluster = class(TView)
  protected
    Value: Cardinal;
    EnableMask: Cardinal;
    Sel: Integer;
    Strings: TCollection;
  private
    function Column(Item: Integer): Integer;
    function FindSel(Where: TPoint): Integer;
    function Row(Item: Integer): Integer;
    procedure MoveSel(Tries, Target: Integer);
    function StepFrom(Candidate: Integer; Key: Word): Integer;
    procedure Travel(Key: Word; var Event: TEvent);
    procedure TrackMouse(var Event: TEvent);
    function ItemUnderMouse(const Event: TEvent): Integer;
    procedure PressSelectedAndRedraw;
    procedure ShowCursorIfOverSelection(const Event: TEvent);
    function MatchesKey(HotChar: Char; const KeyDown: TKeyDownEvent): Boolean;
    procedure HandleOtherKey(var Event: TEvent);
  public
    { The list AStrings is released: its items are copied into the strings of the cluster. }
    constructor Create(const Bounds: TRect; AStrings: TSItem);
    destructor Destroy; override;
    function DataSize: Word; override;
    procedure DrawBox(const Icon: string; Marker: Char);
    { Draws the buttons. Icon is drawn at the start of each button, and the character of Marker that the value of
      MultiMark of the item selects is drawn in its third cell. }
    procedure DrawMultiBox(const Icon, Marker: string);
    procedure GetData(Rec: Pointer); override;
    function GetHelpCtx: Word; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Mark(Item: Integer): Boolean; virtual;
    function MultiMark(Item: Integer): Byte; virtual;
    procedure Press(Item: Integer); virtual;
    procedure MovedTo(Item: Integer); virtual;
    procedure SetData(Rec: Pointer); override;
    procedure SetState(AState: Word; Enable: Boolean); override;
    procedure SetButtonState(AMask: Cardinal; Enable: Boolean); virtual;
    function ButtonState(Item: Integer): Boolean;
  end;

  { Buttons of which one is chosen. The palette is the one of TCluster. }
  TRadioButtons = class(TCluster)
  public
    class var Button: string;
    constructor Create(const Bounds: TRect; AStrings: TSItem);
    procedure Draw; override;
    function Mark(Item: Integer): Boolean; override;
    procedure MovedTo(Item: Integer); override;
    procedure Press(Item: Integer); override;
    procedure SetData(Rec: Pointer); override;
  end;

  { Buttons that are on or off, each one a bit of the value. The palette is the one of TCluster. }
  TCheckBoxes = class(TCluster)
  public
    class var Button: string;
    constructor Create(const Bounds: TRect; AStrings: TSItem);
    procedure Draw; override;
    function Mark(Item: Integer): Boolean; override;
    procedure Press(Item: Integer); override;
  end;

  { Buttons that have more than two states, each one a field of bits of the value. The palette is the one of
    TCluster. }
  TMultiCheckBoxes = class(TCluster)
  private
    SelRange: Byte;
    Flags: Word;
    States: PAnsiChar;
    function FieldMask(Item: Integer): Cardinal;
    function FieldShift(Item: Integer): Integer;
    function FieldOf(Item: Integer): Cardinal;
  public
    constructor Create(const Bounds: TRect; AStrings: TSItem; ASelRange: Byte; AFlags: Word;
      const AStates: string);
    destructor Destroy; override;
    function DataSize: Word; override;
    procedure Draw; override;
    procedure GetData(Rec: Pointer); override;
    function MultiMark(Item: Integer): Byte; override;
    procedure Press(Item: Integer); override;
    procedure SetData(Rec: Pointer); override;
  end;

implementation

end.
