{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/views.h (TFrame, TScrollBar, TScroller, TWindowInit, TWindow and the palettes of the
  windows), source/tvision/tframe.cpp, source/tvision/framelin.cpp, source/tvision/tscrlbar.cpp,
  source/tvision/tscrolle.cpp, source/tvision/twindow.cpp, source/tvision/tvtext1.cpp (the tables of TFrame and
  TScrollBar)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit.

  Parts of the C++ that have no unit yet:
    - message() sends a message to a view; MessageHook of TvViews stands for it and does nothing while it is nil.

  The tables of TFrame (initFrame, frameChars and the five icons) and of TScrollBar (vChars, hChars) are class
  variables, InitFrame, FrameChars, CloseIcon, ZoomIcon, UnZoomIcon, DragIcon and DragLeftIcon of TFrame and VChars and
  HChars of TScrollBar. They get their values, the ones of tvtext1.cpp, when the unit starts; a program may change
  them, as the C++ changes frameChars. The bytes are those of code page 437.

  A Pascal class has one parent, so TWindowInit, which the C++ inherits virtually beside TGroup, is the class between
  TGroup and TWindow: it holds the function that makes the frame. The constructor of TWindow that has no function
  of this kind makes the frame with TWindow.InitFrame, and the constructor that has one passes it to TWindowInit.
  A pointer to a TFrame function that takes a TRect is a TCreateFrameFunc. The title of a window is a block of
  characters with a terminating zero, as the C++ keeps it; GetTitle returns it and nil stands for no title. }
unit TvWindow;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvViews;

const
  { The palettes of the windows. }
  cpBlueWindow = #8#9#10#11#12#13#14#15;
  cpCyanWindow = #16#17#18#19#20#21#22#23;
  cpGrayWindow = #24#25#26#27#28#29#30#31;

type
  TScrollChars = array[0..4] of AnsiChar;

  { The frame of a window. The palette is: 1 passive frame, 2 passive title, 3 active frame, 4 active title,
    5 icons. }
  TFrame = class(TView)
  private
    procedure FrameLine(LineBuffer: TDrawBuffer; Row, MaskIndex: SmallInt; Tint: TColorAttr);
    procedure DragWindow(var Event: TEvent; DragKind: Byte);
  public
    { The masks of the three cells of each kind of line (initFrame), the characters for the masks (frameChars) and
      the icons, in the notation of a command string with tildes. }
    class var InitFrame: array[0..18] of AnsiChar;
    class var FrameChars: array[0..32] of AnsiChar;
    class var CloseIcon: string;
    class var ZoomIcon: string;
    class var UnZoomIcon: string;
    class var DragIcon: string;
    class var DragLeftIcon: string;

    constructor Create(const Bounds: TRect);
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SetState(StateBits: Word; TurnOn: Boolean); override;
  end;

  { A scroll bar. The palette is: 1 page areas, 2 arrows, 3 indicator. }
  TScrollBar = class(TView)
  private
    function GetPartCode: Integer;
  public
    Value: Integer;
    Chars: TScrollChars;
    MinVal: Integer;
    MaxVal: Integer;
    PgStep: Integer;
    ArStep: Integer;
    { The characters of a vertical bar and of a horizontal bar: the two arrows, the page area, the indicator and
      the page area of a bar that cannot scroll. }
    class var VChars: TScrollChars;
    class var HChars: TScrollChars;

    constructor Create(const Bounds: TRect);
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ScrollDraw; virtual;
    function ScrollStep(PartCode: Integer): Integer; virtual;
    procedure SetParams(NewValue, NewMin, NewMax, NewPageStep, NewArrowStep: Integer);
    procedure SetRange(NewMin, NewMax: Integer);
    procedure SetStep(NewPageStep, NewArrowStep: Integer);
    procedure SetValue(NewValue: Integer);
    procedure DrawPos(Position: Integer);
    function GetPos: Integer;
    function GetSize: Integer;
  end;

  { A view that shows a part of a larger area. The palette is: 1 normal text, 2 selected text. }
  TScroller = class(TView)
  public
    Delta: TPoint;
  protected
    DrawLock: Byte;
    DrawFlag: Boolean;
    HScrollBar: TScrollBar;
    VScrollBar: TScrollBar;
    Limit: TPoint;
  private
    procedure ShowSBar(Bar: TScrollBar);
  public
    constructor Create(const Bounds: TRect; HorizontalBar, VerticalBar: TScrollBar);
    procedure ChangeBounds(const Bounds: TRect); override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ScrollDraw; virtual;
    procedure ScrollTo(Column, Row: Integer);
    procedure SetLimit(Columns, Rows: Integer);
    procedure SetState(StateBits: Word; TurnOn: Boolean); override;
    procedure CheckDraw;
    procedure ShutDown; override;
  end;

  { The function that makes the frame of a window. }
  TCreateFrameFunc = function(Area: TRect): TFrame;

  { Holds the function that makes the frame of a window. }
  TWindowInit = class(TGroup)
  protected
    CreateFrame: TCreateFrameFunc;
  public
    constructor Create(const Bounds: TRect; FrameMaker: TCreateFrameFunc); reintroduce;
  end;

  { A window. The palette is: 1 frame passive, 2 frame active, 3 frame icon, 4 scroll bar page area,
    5 scroll bar controls, 6 scroller normal text, 7 scroller selected text, 8 reserved. }
  TWindow = class(TWindowInit)
  private
    procedure Setup(const WindowTitle: string; WindowNumber: SmallInt);
  public
    Flags: Byte;
    ZoomRect: TRect;
    Number: SmallInt;
    Palette: SmallInt;
    Frame: TFrame;
    Title: PAnsiChar;

    constructor Create(const Bounds: TRect; const WindowTitle: string; WindowNumber: SmallInt); overload;
    { As the first constructor, with FrameMaker as the function that makes the frame. }
    constructor Create(const Bounds: TRect; const WindowTitle: string; WindowNumber: SmallInt;
      FrameMaker: TCreateFrameFunc); overload;
    destructor Destroy; override;
    procedure Close; virtual;
    function GetPalette: TPalette; override;
    function GetTitle(RoomLeft: SmallInt): PAnsiChar; virtual;
    procedure HandleEvent(var Event: TEvent); override;
    class function InitFrame(Area: TRect): TFrame; static;
    procedure SetState(StateBits: Word; TurnOn: Boolean); override;
    procedure SizeLimits(var Smallest, Largest: TPoint); override;
    function StandardScrollBar(ScrollOptions: Word): TScrollBar;
    procedure Zoom; virtual;
    procedure ShutDown; override;
  end;

implementation

end.
