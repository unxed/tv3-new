{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (the limit modes and TInputLine), include/tvision/views.h,
  include/tvision/validate.h (TValidator and TVTransfer), include/tvision/ttypes.h, include/tvision/tv.h,
  include/tvision/config.h, source/tvision/tinputli.cpp, source/tvision/tvtext1.cpp (the two arrows of TInputLine)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of TInputLine, and the constructor with StreamableInit, belong to a later
  unit.

  The text of the line is a Pascal string, and Data stands for the block of characters with a terminating zero
  that the C++ keeps. The text ends at its first zero character wherever it comes from, as a C string does, and
  the line never holds a text longer than MaxLen bytes: SetData and CheckValid cut a longer text. GetData copies
  DataSize bytes of the text and its terminating zero, and a zero fills what lies beyond them. The block oldData
  is the string OldData.

  The functions hotKey and hotKeyStr are defined in the file of TInputLine, so they are HotKey and HotKeyStr of
  this unit. The unit gives them to the hooks that stand for them, HotKeyHook of TvDialog and HotKeyStrHook of
  TvMenus, when it starts.

  Parts of the C++ that have no unit yet:
    - the clipboard is TClipboard of TvClip;
    - strwidth is the width of TText of TvUtf8.

  The private members of the C++ class are protected here, so that a class of another unit can read the state of a
  line. The arrows rightArrow and leftArrow are the class variables RightArrow and LeftArrow, which get their
  values, the ones of tvtext1.cpp, when the unit starts; a program may change them. The member setCmdState of the
  class takes a command and hides the one of TView, as it does in the C++. }
unit TvInput;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvEvents, TvColors, TvViews, TvValid;

const
  { What the limit of a line counts. }
  ilMaxBytes = Word(0);
  ilMaxWidth = Word(1);
  ilMaxChars = Word(2);

type
  { A line of text that the user edits. The palette is: 1 passive, 2 active, 3 selected, 4 arrows. }
  TInputLine = class(TView)
  protected
    Validator: TValidator;
    Anchor: Integer;
    OldData: string;
    OldCurPos: Integer;
    OldFirstPos: Integer;
    OldSelStart: Integer;
    OldSelEnd: Integer;
    function CanScroll(Delta: Integer): Boolean;
    function MouseDelta(var Event: TEvent): Integer;
    function MousePos(var Event: TEvent): Integer;
    function DisplayedPos(Position: Integer): Integer;
    procedure DeleteSelect;
    procedure DeleteCurrent;
    procedure AdjustSelectBlock;
    procedure SaveState;
    procedure RestoreState;
    function CheckValid(NoAutoFill: Boolean): Boolean;
    function CanUpdateCommands: Boolean;
    procedure SetCmdState(Command: Word; Enable: Boolean);
    procedure UpdateCommands;
  private
    procedure HandleMouseDown(var Event: TEvent);
    procedure ScrollWhileHeld(var Event: TEvent; Step: Integer);
    procedure DragSelection(var Event: TEvent);
    function HandleKeyDown(var Event: TEvent): Boolean;
    function EnterKeyText(var Event: TEvent): Boolean;
    procedure EraseSpan(SpanStart, SpanEnd: Integer);
    procedure HandleCommand(var Event: TEvent);
  public
    { The characters at the right and at the left end of a line that goes on beyond the view. }
    class var LeftArrow, RightArrow: AnsiChar;
    Data: string;
    MaxLen, MaxWidth, MaxChars: Integer;
    CurPos, FirstPos: Integer;
    SelStart, SelEnd: Integer;

    { LimitMode tells what Limit counts: bytes (ilMaxBytes, which leave room for the terminating zero), columns
      (ilMaxWidth) or characters (ilMaxChars). }
    constructor Create(const Bounds: TRect; Limit: Integer; ValidatorToUse: TValidator = nil;
      LimitMode: Word = ilMaxBytes); reintroduce;
    destructor Destroy; override;
    function DataSize: Word; override;
    procedure Draw; override;
    procedure GetData(Rec: Pointer); override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SelectAll(Enable: Boolean; Scroll: Boolean = True);
    procedure SetData(Rec: Pointer); override;
    procedure SetState(StateMask: Word; TurnOn: Boolean); override;
    function Valid(Command: Word): Boolean; override;
    { Destroys the validator that the line has, and takes NewValidator in its place. }
    procedure SetValidator(NewValidator: TValidator);
  end;

{ The upper case letter that follows the first tilde of Text, or #0 when there is none. }
function HotKey(const Text: string): Char;
{ The part of Text between the first tilde and the next one, or the end of Text; empty when there is no tilde. }
function HotKeyStr(const Text: string): string;

implementation

end.
