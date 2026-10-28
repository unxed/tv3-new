{ The terminal side of the far2l terminal extensions, for the embedded terminal emulator.

  A program in the terminal announces itself with an APC string that begins with "far2l" and then talks in requests
  and replies carried in further APC strings. TVtExtServer takes the body of such a string and returns the bytes that
  go back to the program: the acknowledgement, the reply of a request that has an ID, and the size event. It also
  builds the key and mouse events for a program that asked for them. What the server cannot do itself goes to a
  TVtExtHost. The clipboard that the server serves is kept by the routines VtClip* of this unit; its text is passed
  on to TClipboard. A client is let in by the user for the activation or for always, and the data of the clipboard
  is read only shortly after a paste gesture of the user. }
unit TvVtExt;

{$mode objfpc}
{$H+}
{$R-}
{$Q-}

interface

uses
  TvEvents, TvFar2l;

const
  { The code of a key event that is a release. Every other kind of key event counts as a press. }
  VtEvKeyUp = $0040;

  { The text formats of the clipboard. Both name the one text slot. }
  VtCfText = 1;
  VtCfUnicodeText = 13;

type
  { The answers of the user to a client that asks for the clipboard. }
  TVtClipAnswer = (vcaBlock, vcaRemote, vcaShare, vcaAlways);

  { The routines that the base host forwards to. A hook that is not set does nothing. }
  TVtNotifyProc = procedure(const Title, Text: AnsiString);
  TVtFKeyTitlesProc = procedure(const Titles: array of AnsiString);
  TVtColorBitsFunc = function: Integer;
  TVtWindowMaxSizeFunc = function(out Cols, Rows: Integer): Boolean;
  TVtWindowMaximizeProc = procedure(Maximize: Boolean);
  TVtQuickEditProc = procedure;

  { One item of the clipboard: a format and its data. }
  TVtClipItem = record
    Format: LongWord;
    Data: AnsiString;
  end;

  { What the server cannot do by itself. The base class forwards to the hooks and refuses the clipboard. }
  TVtExtHost = class
  public
    function AskClipboard(const ClientId: AnsiString): TVtClipAnswer; virtual;
    procedure Notify(const Title, Text: AnsiString); virtual;
    function FKeyTitles(const Titles: array of AnsiString): Boolean; virtual;
    procedure CursorHeight(Percent: Integer); virtual;
    function ColorBits: Integer; virtual;
    function WindowMaxSize(out Cols, Rows: Integer): Boolean; virtual;
    procedure WindowMaximize(Maximize: Boolean); virtual;
    procedure QuickEdit; virtual;
  end;

  { The clock of the paste gestures, in milliseconds. }
  TVtClockFunc = function: Int64;

  TVtExtServer = class
  private
    FHost: TVtExtHost;
    FOwnHost: TVtExtHost;
    FFeatures: QWord;
    FIdentity: AnsiString;
    FCols: Integer;
    FRows: Integer;
    FClipOpen: Boolean;
    FShared: array of AnsiString;
    FChunk: AnsiString;
    FSetItems: array of TVtClipItem;
    FGestureTime: Int64;
    FGestureSeen: Boolean;
    FExtends: Integer;
    FAfter: AnsiString;
    procedure SetHost(AHost: TVtExtHost);
    function CurrentTime: Int64;
    procedure AcceptIdentity(const B: AnsiString);
    function Execute(const Request: AnsiString): AnsiString;
    procedure RunCommand(Cmd: AnsiChar; Args, Values: TF2lStack);
    procedure RunMaxSize(Values: TF2lStack);
    procedure RunNotify(Args: TF2lStack);
    procedure RunFKeys(Args, Values: TF2lStack);
    procedure RunFeatures(Args: TF2lStack);
    procedure RunCursorHeight(Args: TF2lStack);
    procedure RunImage(Args, Values: TF2lStack);
    procedure RunClipboard(Args, Values: TF2lStack);
    procedure ClipOpen(Args, Values: TF2lStack);
    procedure ClipClose(Values: TF2lStack);
    procedure ClipEmpty(Values: TF2lStack);
    procedure ClipIsAvail(Args, Values: TF2lStack);
    procedure ClipSetChunk(Args: TF2lStack);
    procedure ClipSetData(Args, Values: TF2lStack);
    procedure ClipGetData(Args, Values: TF2lStack);
    procedure ClipGetDataId(Args, Values: TF2lStack);
    procedure ClipRegister(Args, Values: TF2lStack);
    function Authorise(const ClientId: AnsiString): ShortInt;
    function IsShared(const FullId: AnsiString): Boolean;
    function IsInAuthedsFile(const FullId: AnsiString): Boolean;
    procedure RememberInAuthedsFile(const FullId: AnsiString);
    procedure CloseClip;
    function ReadAllowed(Extend: Boolean): Boolean;
    function FetchClipData(Format: LongWord; out Data: AnsiString): Boolean;
    procedure PutSetItem(Format: LongWord; const Data: AnsiString);
  public
    { Between far2l1 and far2l0; False after Create. }
    Active: Boolean;
    { The cursor height the program asked for, -1: none. }
    CursorPercent: Integer;
    { The file of the clients let in always. }
    AuthedsPath: AnsiString;
    { The clock of the paste gestures, milliseconds. }
    Now: TVtClockFunc;
    constructor Create(ACols, ARows: Integer);
    destructor Destroy; override;
    function Body(const B: AnsiString): AnsiString;
    function Resized(ACols, ARows: Integer): AnsiString;
    procedure Stop;
    procedure PasteGesture;
    function CompactInput: Boolean;
    function KeyEvent(const Event: TEvent): AnsiString;
    function MouseEvent(X, Y: Integer; Buttons, Wheel: Byte; Moved, Double: Boolean; Mods: Word): AnsiString;
    property Host: TVtExtHost read FHost write SetHost;
  end;

var
  { The routines that the base host calls. }
  VtOnNotify: TVtNotifyProc = nil;
  VtOnSetFKeyTitles: TVtFKeyTitlesProc = nil;
  VtOnColorBits: TVtColorBitsFunc = nil;
  VtOnWindowMaxSize: TVtWindowMaxSizeFunc = nil;
  VtOnWindowMaximize: TVtWindowMaximizeProc = nil;
  VtOnQuickEdit: TVtQuickEditProc = nil;

{ The identifier of clipboard data: FNV-1a over the bytes with the length mixed into the start; never 0. For the
  text format the data ends at its first NUL byte. }
function VtClipDataId(Format: LongWord; const Data: AnsiString): QWord;

{ The clipboard that the server serves. }
function VtClipItem(Format: LongWord; const Data: AnsiString): TVtClipItem;
{ Replaces all items; the text goes to TClipboard. }
procedure VtClipSetItems(const Items: array of TVtClipItem);
{ For the two text formats the data is the UTF-8 text. }
function VtClipGetItem(Format: LongWord; out Data: AnsiString): Boolean;
function VtClipHasItem(Format: LongWord): Boolean;
{ The same name gives the same number; the numbers start at $C000. }
function VtClipRegisterFormat(const FormatName: AnsiString): LongWord;
function VtClipGetText: AnsiString;
{ The number of the format of vertical blocks of text, FAR_VerticalBlock_Unicode. }
function VtVerticalBlockFormat: LongWord;

implementation

end.
