{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (the button flags, TDialog, TButton, TStaticText, TParamText, TLabel),
  include/tvision/ttypes.h (specialChars), source/tvision/tdialog.cpp, source/tvision/tbutton.cpp,
  source/tvision/tstatict.cpp, source/tvision/tparamte.cpp, source/tvision/tlabel.cpp,
  source/tvision/tvtext1.cpp (specialChars and the tables of TButton)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit. The classes of dialogs.h that are not named above belong to other units.

  Parts of the C++ that have no unit yet:
    - message() sends a message to a view; MessageHook of TvViews stands for it and does nothing while it is nil;
    - hotKey() returns the letter that a label or a button of a text marks with tildes; HotKeyHook stands for it. While
      it is nil no text has a hot key, so a label and a button answer to no letter.

  The text of a view is a block of characters with a terminating zero, as the C++ keeps it, and nil stands for no
  text. A string of this library is a short string, so a text is at most 255 characters long. The text of a
  TParamText is a block of 256 characters, and SetText cuts the formatted text to 255 characters. The format of
  SetText is the one of FormatStr of TvUtil, and its arguments are an array of const.

  The tables shadows and markers of TButton are the class variables Shadows and Markers, and specialChars is the
  variable SpecialChars; they get their C++ values when the unit starts, in code page 437, and a program may change
  them.

  TParamText has no text of the base class: the constructor of TStaticText makes a block for an empty text, and
  TParamText gives it back so that Text is nil, as the C++ constructor that passes no text leaves it. Valid of
  TDialog calls the Valid of the class above it, which is the one of TGroup because TWindow does not change it. }
unit TvDialog;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvTimer, TvViews, TvWindow;

const
  { The flags of a TButton. }
  bfNormal = Word($00);
  bfDefault = Word($01);
  bfLeftJust = Word($02);
  bfBroadcast = Word($04);
  bfGrabFocus = Word($08);

  { The command that a button broadcasts before it acts, and the two commands that move the default button. }
  cmRecordHistory = Word(60);
  cmGrabDefault = Word(61);
  cmReleaseDefault = Word(62);

  { The palettes of a dialog: the entries of the palette of its owner that the 32 entries of its own palette
    stand for. }
  cpGrayDialog = #$20#$21#$22#$23#$24#$25#$26#$27#$28#$29#$2A#$2B#$2C#$2D#$2E#$2F +
    #$30#$31#$32#$33#$34#$35#$36#$37#$38#$39#$3A#$3B#$3C#$3D#$3E#$3F;
  cpBlueDialog = #$40#$41#$42#$43#$44#$45#$46#$47#$48#$49#$4A#$4B#$4C#$4D#$4E#$4F +
    #$50#$51#$52#$53#$54#$55#$56#$57#$58#$59#$5A#$5B#$5C#$5D#$5E#$5F;
  cpCyanDialog = #$60#$61#$62#$63#$64#$65#$66#$67#$68#$69#$6A#$6B#$6C#$6D#$6E#$6F +
    #$70#$71#$72#$73#$74#$75#$76#$77#$78#$79#$7A#$7B#$7C#$7D#$7E#$7F;
  cpDialog = cpGrayDialog;

  { The values of TDialog.Palette. }
  dpBlueDialog = 0;
  dpCyanDialog = 1;
  dpGrayDialog = 2;

type
  { The function that returns the hot key of a text: the upper case letter after the first tilde, or #0. }
  THotKeyFunc = function(const Text: string): Char;

  { A window that holds controls and ends its modal loop at cmOK, cmCancel, cmYes and cmNo. The palette is the one
    of dialogs.h: 1 frame passive, 2 frame active, 3 frame icon, 4 scroll bar page area, 5 scroll bar controls,
    6 static text, 7 to 9 label, 10 to 15 button, 16 to 18 cluster, 19 to 21 input line, 22 and 23 history,
    24 and 25 history window scroll bar, 26 to 29 list viewer, 30 info pane, 31 cluster disabled, 32 reserved. }
  TDialog = class(TWindow)
  public
    constructor Create(const Bounds: TRect; const ATitle: string); reintroduce;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Valid(Command: Word): Boolean; override;
  end;

  { A text that is drawn over the lines of the view. The text may hold the character 3 at the start of a line, which
    centres the line, and the character 10, which ends a line. The palette is: 1 text. }
  TStaticText = class(TView)
  protected
    Text: PAnsiChar;
  public
    constructor Create(const Bounds: TRect; const AText: string);
    destructor Destroy; override;
    procedure Draw; override;
    function GetPalette: TPalette; override;
    { Copies the text into Dest, which has room for 256 characters; the copy is cut at 255 characters. }
    procedure GetText(Dest: PAnsiChar); virtual;
  end;

  { A static text that is set at run time. The palette is: 1 text. }
  TParamText = class(TStaticText)
  protected
    Str: PAnsiChar;
  public
    constructor Create(const Bounds: TRect); reintroduce;
    destructor Destroy; override;
    procedure GetText(Dest: PAnsiChar); override;
    procedure SetText(const Fmt: string; const Args: array of const); virtual;
    function GetTextLen: Integer; virtual;
  end;

  { A text that moves the focus to another view. The palette is: 1 normal text, 2 selected text, 3 normal shortcut,
    4 selected shortcut. }
  TLabel = class(TStaticText)
  protected
    Link: TView;
    Light: Boolean;
  private
    procedure FocusLink(var Event: TEvent);
  public
    constructor Create(const Bounds: TRect; const AText: string; ALink: TView); reintroduce;
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ShutDown; override;
  end;

  { A push button. The palette is: 1 normal, 2 default, 3 selected, 4 disabled, 5 normal shortcut, 6 default
    shortcut, 7 selected shortcut, 8 shadow. }
  TButton = class(TView)
  private
    AnimationTimer: TTimerId;
    procedure DrawTitle(LineBuffer: TDrawBuffer; TotalWidth, Indent: Integer; const Tints: TAttrPair;
      Down: Boolean);
    procedure StartAnimation;
    function FaceRect: TRect;
    procedure TrackMouse(var Event: TEvent; FaceArea: TRect);
    procedure HandleKeyDown(var Event: TEvent; HotChar: Char);
    procedure HandleBroadcast(var Event: TEvent);
  protected
    Command: Word;
    Flags: Byte;
    AmDefault: Boolean;
  public
    Title: PAnsiChar;
    { The three characters of the shadow (the top right cell, the other cells of the right column, the bottom
      row) and the two characters of the markers. }
    class var Shadows: string;
    class var Markers: string;

    constructor Create(const Bounds: TRect; const ATitle: string; ACommand, AFlags: Word);
    destructor Destroy; override;
    procedure Draw; override;
    procedure DrawState(Down: Boolean);
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure MakeDefault(Enable: Boolean);
    procedure Press; virtual;
    procedure SetState(AState: Word; Enable: Boolean); override;
  end;

var
  { The characters that mark a selected, a default and a normal control: left and right of each pair. }
  SpecialChars: array[0..5] of Byte = (175, 174, 26, 27, 32, 32);
  HotKeyHook: THotKeyFunc;

implementation

end.
