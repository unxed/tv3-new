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

uses
  SysUtils, Classes, TvClip, TvKeys, TvUtf8, TvTermIo, TvAppDir;

const
  AckText = #27'_far2lok'#7;
  ReplyHead = #27'_far2l';
  EventHead = #27'_f2l';
  VerticalBlockName = 'FAR_VerticalBlock_Unicode';
  AuthedsFileName = 'far2l-clipboard-autheds';
  FirstDynamicFormat = $C000;
  MaxIdentityLength = 256;
  FnvBasis: QWord = $CBF29CE484222325;
  FnvPrime: QWord = $100000001B3;

  { What a server reports on CLIP_OPEN: the data IDs and the chunked set. }
  ServerClipFeatures = FARTTY_FEATCLIP_DATA_ID or FARTTY_FEATCLIP_CHUNKED_SET;

  ClipOk = 1;
  ClipFail = 0;
  ClipClosed = -1;

  ChunkUnit = 256;
  { A paste gesture allows reads for this long, and a read may move that time on this many times. }
  GestureWindowMs = 5000;
  GestureExtendLimit = 3;
  { The answer of a read on a clipboard that is not open. }
  NoStackMark = $FFFFFFFF;
  MaxPercent = 100;
  FKeyCount = 12;

var
  StoredItems: array of TVtClipItem;
  FormatNames: array of AnsiString;

function DefaultClock: Int64;
begin
  Result := Int64(GetTickCount64);
end;

{ Bytes and code points }

function CutAtNul(const Data: AnsiString): AnsiString;
var
  NulAt: SizeInt;
begin
  NulAt := Pos(#0, Data);
  if NulAt = 0 then
    Result := Data
  else
    Result := Copy(Data, 1, NulAt - 1);
end;

procedure StoreWord32(var Buf: AnsiString; At: SizeInt; Value: Cardinal);
var
  K: Integer;
begin
  for K := 0 to 3 do
    Buf[At + K] := Chr((Value shr (8 * K)) and $FF);
end;

function LoadWord32(const Buf: AnsiString; At: SizeInt): Cardinal;
var
  K: Integer;
begin
  Result := 0;
  for K := 3 downto 0 do
    Result := (Result shl 8) or Cardinal(Ord(Buf[At + K]));
end;

{ UTF-8 text to UTF-32 little-endian, without a terminating zero. A byte that begins no complete sequence stands
  for itself. }
function Utf8ToUtf32Bytes(const Utf8: AnsiString): AnsiString;
var
  At, Take, Used: SizeInt;
  CodePoint: Cardinal;
begin
  SetLength(Result, Length(Utf8) * 4);
  At := 1;
  Used := 0;
  while At <= Length(Utf8) do
  begin
    Take := 1 + SizeInt(Utf8BytesLeft(Byte(Utf8[At])));
    if At + Take - 1 > Length(Utf8) then
      Take := 1;
    CodePoint := Utf8To32(Copy(Utf8, At, Take));
    StoreWord32(Result, Used + 1, CodePoint);
    Inc(Used, 4);
    Inc(At, Take);
  end;
  SetLength(Result, Used);
end;

{ UTF-32 little-endian to UTF-8. The text ends at the first zero character; a trailing part of a character is
  dropped and a value above $10FFFF becomes the replacement character. }
function Utf32BytesToUtf8(const Wide: AnsiString): AnsiString;
var
  At, Used: SizeInt;
  CodePoint: Cardinal;
  Encoded: TUtf8Bytes;
  Count, K: SizeInt;
begin
  SetLength(Result, (Length(Wide) div 4) * 4);
  At := 1;
  Used := 0;
  while At + 3 <= Length(Wide) do
  begin
    CodePoint := LoadWord32(Wide, At);
    Inc(At, 4);
    if CodePoint = 0 then
      Break;
    if CodePoint > $10FFFF then
      CodePoint := $FFFD;
    Count := Utf32To8(CodePoint, Encoded);
    for K := 0 to Count - 1 do
    begin
      Inc(Used);
      Result[Used] := Chr(Encoded[K]);
    end;
  end;
  SetLength(Result, Used);
end;

{ The strings of the wire }

function ReplyText(const StackBytes: AnsiString): AnsiString;
begin
  Result := ReplyHead + EncodeBase64(StackBytes) + #7;
end;

function EventText(const StackBytes: AnsiString): AnsiString;
begin
  Result := EventHead + EncodeBase64(StackBytes) + #7;
end;

function SizeEventText(Cols, Rows: Integer): AnsiString;
var
  Wire: TF2lStack;
begin
  Wire := TF2lStack.Create;
  try
    Wire.PutNumber(Word(Cols), 2);
    Wire.PutNumber(Word(Rows), 2);
    Wire.PutRaw('S');
    Result := EventText(Wire.Serialized);
  finally
    Wire.Free;
  end;
end;

procedure PutStatus(Values: TF2lStack; Status: ShortInt);
begin
  Values.PutNumber(Byte(Status), 1);
end;

{ The key and the mouse events }

{ The code point of the text of a key, or the character of its key code when it has no text. }
function KeyCharOf(const Event: TEvent): Cardinal;
begin
  if Event.KeyDown.TextLength > 0 then
    Result := Utf8To32(Event.KeyDown.GetText)
  else
    Result := Event.KeyDown.CharScan.CharCode;
end;

{ The control key state of an event of the library as the bits of the console records. }
function ConsoleKeyState(Mods: Word; WithLocks: Boolean): Cardinal;
begin
  Result := 0;
  if (Mods and kbShift) <> 0 then
    Result := Result or SHIFT_PRESSED;
  if (Mods and kbCtrlShift) <> 0 then
    Result := Result or LEFT_CTRL_PRESSED;
  if (Mods and kbAltShift) <> 0 then
    Result := Result or LEFT_ALT_PRESSED;
  if not WithLocks then
    Exit;
  if (Mods and kbNumState) <> 0 then
    Result := Result or NUMLOCK_ON;
  if (Mods and kbScrollState) <> 0 then
    Result := Result or SCROLLLOCK_ON;
  if (Mods and kbCapsState) <> 0 then
    Result := Result or CAPSLOCK_ON;
end;

{ The character that Ctrl makes of a character: a letter gives 1 to 26, the characters from @ to _ give 0 to 31. }
function CtrlCharOf(Ch: Cardinal): Cardinal;
begin
  Result := Ch;
  if (Ch >= Ord('a')) and (Ch <= Ord('z')) then
    Result := Ch - Ord('a') + 1
  else if (Ch >= Ord('@')) and (Ch <= Ord('_')) then
    Result := Ch - Ord('@');
end;

{ The index 0 to 11 of the function key that a scan code belongs to (plain, with Shift, Ctrl, Alt), or -1. }
function FKeyIndexOfScan(Scan: Word): Integer;
var
  Group, FirstOfTen, FirstOfPair: Integer;
begin
  Result := -1;
  for Group := 0 to 3 do
  begin
    if Group = 0 then
      FirstOfTen := $3B
    else
      FirstOfTen := $54 + 10 * (Group - 1);
    FirstOfPair := $85 + 2 * Group;
    if (Scan >= FirstOfTen) and (Scan < FirstOfTen + 10) then
    begin
      Result := Scan - FirstOfTen;
      Exit;
    end;
    if (Scan >= FirstOfPair) and (Scan < FirstOfPair + 2) then
    begin
      Result := 10 + Scan - FirstOfPair;
      Exit;
    end;
  end;
end;

{ The virtual key of an Alt combination of a letter or a digit, from the scan code of its key code. }
function AltKeyVirtualKey(Scan: Word): Word;
const
  TopRow = 'QWERTYUIOP';
  MiddleRow = 'ASDFGHJKL';
  BottomRow = 'ZXCVBNM';
begin
  Result := 0;
  if (Scan >= $10) and (Scan <= $19) then
    Result := Ord(TopRow[Scan - $10 + 1])
  else if (Scan >= $1E) and (Scan <= $26) then
    Result := Ord(MiddleRow[Scan - $1E + 1])
  else if (Scan >= $2C) and (Scan <= $32) then
    Result := Ord(BottomRow[Scan - $2C + 1])
  else if (Scan >= $78) and (Scan <= $80) then
    Result := Ord('1') + Scan - $78
  else if Scan = $81 then
    Result := Ord('0');
end;

{ The virtual key of the cursor and editing keys, from their scan codes. }
function NavigationVirtualKey(Scan: Word): Word;
begin
  case Scan of
    $47: Result := VK_HOME;
    $48: Result := VK_UP;
    $49: Result := VK_PRIOR;
    $4B: Result := VK_LEFT;
    $4D: Result := VK_RIGHT;
    $4F: Result := VK_END;
    $50: Result := VK_DOWN;
    $51: Result := VK_NEXT;
    $52: Result := VK_INSERT;
    $53: Result := VK_DELETE;
  else
    Result := 0;
  end;
end;

{ The virtual key of a key, from its character and its key code. 0 when nothing is known. }
function KeyVirtualKeyOf(KeyCode: Word; Ch: Cardinal): Word;
var
  Scan: Word;
  FKey: Integer;
begin
  Scan := KeyCode shr 8;
  Result := 0;
  case Ch of
    8: Result := VK_BACK;
    9: Result := VK_TAB;
    13: Result := VK_RETURN;
    27: Result := VK_ESCAPE;
    Ord(' '): Result := VK_SPACE;
    Ord('0')..Ord('9'): Result := Ch;
    Ord('A')..Ord('Z'): Result := Ch;
    Ord('a')..Ord('z'): Result := Ch - Ord('a') + Ord('A');
    1..7, 10..12, 14..26: Result := Ch - 1 + Ord('A');
  end;
  if Result <> 0 then
    Exit;
  Result := NavigationVirtualKey(Scan);
  if Result <> 0 then
    Exit;
  FKey := FKeyIndexOfScan(Scan);
  if FKey >= 0 then
  begin
    Result := VK_F1 + FKey;
    Exit;
  end;
  case Scan of
    $01: Result := VK_ESCAPE;
    $0E: Result := VK_BACK;
    $0F: Result := VK_TAB;
    $1C: Result := VK_RETURN;
  else
    Result := AltKeyVirtualKey(Scan);
  end;
end;

{ VtClipDataId and the clipboard }

function VtClipDataId(Format: LongWord; const Data: AnsiString): QWord;
var
  Count, K: SizeInt;
  NulAt: SizeInt;
begin
  Count := Length(Data);
  if Format = VtCfText then
  begin
    NulAt := Pos(#0, Data);
    if NulAt > 0 then
      Count := NulAt - 1;
  end;
  Result := FnvBasis xor QWord(Count);
  for K := 1 to Count do
  begin
    Result := Result xor QWord(Byte(Data[K]));
    Result := Result * FnvPrime;
  end;
  if Result = 0 then
    Result := 1;
end;

function VtClipItem(Format: LongWord; const Data: AnsiString): TVtClipItem;
begin
  Result.Format := Format;
  Result.Data := Data;
end;

function SlotFormat(Format: LongWord): LongWord;
begin
  if Format = VtCfUnicodeText then
    Result := VtCfText
  else
    Result := Format;
end;

function FindStoredItem(Format: LongWord): Integer;
var
  K: Integer;
  Wanted: LongWord;
begin
  Wanted := SlotFormat(Format);
  for K := 0 to High(StoredItems) do
    if SlotFormat(StoredItems[K].Format) = Wanted then
    begin
      Result := K;
      Exit;
    end;
  Result := -1;
end;

function VtClipGetItem(Format: LongWord; out Data: AnsiString): Boolean;
var
  Slot: Integer;
begin
  Data := '';
  Slot := FindStoredItem(Format);
  Result := Slot >= 0;
  if Result then
    Data := StoredItems[Slot].Data;
end;

function VtClipHasItem(Format: LongWord): Boolean;
begin
  Result := FindStoredItem(Format) >= 0;
end;

function VtClipGetText: AnsiString;
begin
  VtClipGetItem(VtCfText, Result);
end;

procedure VtClipSetItems(const Items: array of TVtClipItem);
var
  K: Integer;
begin
  SetLength(StoredItems, Length(Items));
  for K := 0 to High(Items) do
    StoredItems[K] := Items[K];
  TClipboard.SetText(VtClipGetText);
end;

function VtClipRegisterFormat(const FormatName: AnsiString): LongWord;
var
  K: Integer;
begin
  for K := 0 to High(FormatNames) do
    if FormatNames[K] = FormatName then
    begin
      Result := FirstDynamicFormat + LongWord(K);
      Exit;
    end;
  SetLength(FormatNames, Length(FormatNames) + 1);
  FormatNames[High(FormatNames)] := FormatName;
  Result := FirstDynamicFormat + LongWord(High(FormatNames));
end;

function VtVerticalBlockFormat: LongWord;
begin
  Result := VtClipRegisterFormat(VerticalBlockName);
end;

{ TVtExtHost }

function TVtExtHost.AskClipboard(const ClientId: AnsiString): TVtClipAnswer;
begin
  Result := vcaRemote;
end;

procedure TVtExtHost.Notify(const Title, Text: AnsiString);
begin
  if Assigned(VtOnNotify) then
    VtOnNotify(Title, Text);
end;

function TVtExtHost.FKeyTitles(const Titles: array of AnsiString): Boolean;
begin
  Result := Assigned(VtOnSetFKeyTitles);
  if Result then
    VtOnSetFKeyTitles(Titles);
end;

procedure TVtExtHost.CursorHeight(Percent: Integer);
begin
end;

function TVtExtHost.ColorBits: Integer;
begin
  Result := 0;
  if Assigned(VtOnColorBits) then
    Result := VtOnColorBits();
  if Result = 0 then
    Result := 4;
end;

function TVtExtHost.WindowMaxSize(out Cols, Rows: Integer): Boolean;
begin
  Cols := 0;
  Rows := 0;
  Result := False;
  if Assigned(VtOnWindowMaxSize) then
    Result := VtOnWindowMaxSize(Cols, Rows);
end;

procedure TVtExtHost.WindowMaximize(Maximize: Boolean);
begin
  if Assigned(VtOnWindowMaximize) then
    VtOnWindowMaximize(Maximize);
end;

procedure TVtExtHost.QuickEdit;
begin
  if Assigned(VtOnQuickEdit) then
    VtOnQuickEdit();
end;

{ TVtExtServer: the state }

constructor TVtExtServer.Create(ACols, ARows: Integer);
var
  ConfigBase: AnsiString;
begin
  inherited Create;
  FOwnHost := TVtExtHost.Create;
  FHost := FOwnHost;
  FCols := ACols;
  FRows := ARows;
  CursorPercent := -1;
  Active := False;
  FFeatures := 0;
  FIdentity := '';
  FGestureSeen := False;
  FGestureTime := 0;
  FExtends := 0;
  ConfigBase := AppDirPath(adConfig, 'far2l');
  if ConfigBase = '' then
    AuthedsPath := ''
  else
    AuthedsPath := ConfigBase + PathDelim + AuthedsFileName;
  Now := @DefaultClock;
end;

destructor TVtExtServer.Destroy;
begin
  FOwnHost.Free;
  inherited Destroy;
end;

procedure TVtExtServer.SetHost(AHost: TVtExtHost);
begin
  if AHost = nil then
    FHost := FOwnHost
  else
    FHost := AHost;
end;

function TVtExtServer.CurrentTime: Int64;
begin
  if Assigned(Now) then
    Result := Now()
  else
    Result := 0;
end;

procedure TVtExtServer.CloseClip;
begin
  FClipOpen := False;
  FChunk := '';
  FSetItems := nil;
  FExtends := 0;
end;

procedure TVtExtServer.Stop;
var
  NoTitles: array of AnsiString;
begin
  if not Active then
    Exit;
  Active := False;
  CloseClip;
  FFeatures := 0;
  FShared := nil;
  CursorPercent := -1;
  SetLength(NoTitles, 0);
  FHost.FKeyTitles(NoTitles);
end;

function TVtExtServer.Resized(ACols, ARows: Integer): AnsiString;
begin
  Result := '';
  if (ACols = FCols) and (ARows = FRows) then
    Exit;
  FCols := ACols;
  FRows := ARows;
  if Active and ((FFeatures and FARTTY_FEAT_TERMINAL_SIZE) <> 0) then
    Result := SizeEventText(FCols, FRows);
end;

procedure TVtExtServer.PasteGesture;
begin
  FGestureSeen := True;
  FGestureTime := CurrentTime;
  FExtends := 0;
end;

function TVtExtServer.CompactInput: Boolean;
begin
  Result := (FFeatures and FARTTY_FEAT_COMPACT_INPUT) <> 0;
end;

{ TVtExtServer: the strings }

procedure TVtExtServer.AcceptIdentity(const B: AnsiString);
var
  K: SizeInt;
begin
  if FIdentity <> '' then
    Exit;
  FIdentity := Copy(B, 7, MaxIdentityLength);
  for K := 1 to Length(FIdentity) do
    if FIdentity[K] < ' ' then
      FIdentity[K] := ' ';
end;

function TVtExtServer.Body(const B: AnsiString): AnsiString;
var
  StackBytes: AnsiString;
begin
  Result := '';
  if (Length(B) < 6) or (Copy(B, 1, 5) <> 'far2l') then
    Exit;
  case B[6] of
    '1':
      begin
        Active := True;
        Result := AckText;
      end;
    '0':
      Stop;
    '#':
      AcceptIdentity(B);
    ':':
      begin
        if (not Active) or (Length(B) <= 6) then
          Exit;
        StackBytes := Far2lDecodePayload(Copy(B, 7, Length(B)));
        if StackBytes = '' then
          Exit;
        Result := Execute(StackBytes);
      end;
  end;
end;

{ TVtExtServer: the requests }

function TVtExtServer.Execute(const Request: AnsiString): AnsiString;
var
  Args, Values: TF2lStack;
  Id: Byte;
  Cmd: AnsiChar;
begin
  FAfter := '';
  Result := '';
  Args := TF2lStack.Create;
  Values := TF2lStack.Create;
  try
    Args.Load(Request);
    Id := Byte(Args.PopNumber(1));
    Cmd := AnsiChar(Byte(Args.PopNumber(1)));
    if not Args.Failed then
      RunCommand(Cmd, Args, Values);
    if Args.Failed then
      Values.Load('');
    if Id <> 0 then
    begin
      Values.PutNumber(Id, 1);
      Result := ReplyText(Values.Serialized);
    end;
    Result := Result + FAfter;
    FAfter := '';
  finally
    Values.Free;
    Args.Free;
  end;
end;

procedure TVtExtServer.RunCommand(Cmd: AnsiChar; Args, Values: TF2lStack);
var
  Depth: Integer;
begin
  case Cmd of
    'x':
      RunFeatures(Args);
    'e':
      FHost.QuickEdit;
    'M':
      FHost.WindowMaximize(True);
    'm':
      FHost.WindowMaximize(False);
    'h':
      RunCursorHeight(Args);
    'w':
      RunMaxSize(Values);
    'n':
      RunNotify(Args);
    'f':
      RunFKeys(Args, Values);
    'p':
      begin
        Depth := FHost.ColorBits;
        Values.PutNumber(0, 1);
        Values.PutNumber(Byte(Depth and $FF), 1);
      end;
    'c':
      RunClipboard(Args, Values);
    'i':
      RunImage(Args, Values);
  end;
end;

procedure TVtExtServer.RunFeatures(Args: TF2lStack);
var
  Wanted: QWord;
begin
  Wanted := Args.PopNumber(8);
  if Args.Failed then
    Exit;
  FFeatures := Wanted;
  if (FFeatures and FARTTY_FEAT_TERMINAL_SIZE) <> 0 then
    FAfter := SizeEventText(FCols, FRows);
end;

procedure TVtExtServer.RunCursorHeight(Args: TF2lStack);
var
  Percent: Integer;
begin
  Percent := Integer(Args.PopNumber(1));
  if Args.Failed then
    Exit;
  if Percent > MaxPercent then
    Percent := MaxPercent;
  CursorPercent := Percent;
  FHost.CursorHeight(Percent);
end;

procedure TVtExtServer.RunMaxSize(Values: TF2lStack);
var
  Cols, Rows: Integer;
begin
  Cols := 0;
  Rows := 0;
  if (not FHost.WindowMaxSize(Cols, Rows)) or (Cols <= 0) or (Rows <= 0) then
  begin
    Cols := FCols;
    Rows := FRows;
  end;
  Values.PutNumber(Word(Cols), 2);
  Values.PutNumber(Word(Rows), 2);
end;

procedure TVtExtServer.RunNotify(Args: TF2lStack);
var
  Title, Message: AnsiString;
begin
  Title := Args.PopString;
  Message := Args.PopString;
  if Args.Failed then
    Exit;
  FHost.Notify(Title, Message);
end;

procedure TVtExtServer.RunFKeys(Args, Values: TF2lStack);
var
  Titles: array[0..FKeyCount - 1] of AnsiString;
  K: Integer;
  HasTitle: QWord;
  Accepted: Boolean;
begin
  for K := 0 to FKeyCount - 1 do
  begin
    Titles[K] := '';
    if Args.Size = 0 then
      Continue;
    HasTitle := Args.PopNumber(1);
    if HasTitle <> 0 then
      Titles[K] := Args.PopString;
  end;
  if Args.Failed then
    Exit;
  Accepted := FHost.FKeyTitles(Titles);
  Values.PutNumber(Ord(Accepted), 1);
end;

procedure TVtExtServer.RunImage(Args, Values: TF2lStack);
var
  Sub: QWord;
begin
  Sub := Args.PopNumber(1);
  if Args.Failed then
    Exit;
  if Sub = Ord('c') then
  begin
    Values.PutNumber(0, 8);
    Values.PutNumber(0, 2);
    Values.PutNumber(0, 2);
  end
  else
    Values.PutNumber(0, 1);
end;

{ TVtExtServer: the clipboard }

procedure TVtExtServer.RunClipboard(Args, Values: TF2lStack);
var
  Sub: AnsiChar;
begin
  Sub := AnsiChar(Byte(Args.PopNumber(1)));
  if Args.Failed then
    Exit;
  case Sub of
    'o':
      ClipOpen(Args, Values);
    'c':
      ClipClose(Values);
    'e':
      ClipEmpty(Values);
    'a':
      ClipIsAvail(Args, Values);
    'S':
      ClipSetChunk(Args);
    's':
      ClipSetData(Args, Values);
    'g':
      ClipGetData(Args, Values);
    'i':
      ClipGetDataId(Args, Values);
    'r':
      ClipRegister(Args, Values);
  end;
end;

function TVtExtServer.IsShared(const FullId: AnsiString): Boolean;
var
  K: Integer;
begin
  Result := True;
  for K := 0 to High(FShared) do
    if FShared[K] = FullId then
      Exit;
  Result := False;
end;

function TVtExtServer.IsInAuthedsFile(const FullId: AnsiString): Boolean;
var
  Lines: TStringList;
  K: Integer;
begin
  Result := False;
  if (AuthedsPath = '') or not FileExists(AuthedsPath) then
    Exit;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AuthedsPath);
    except
      Exit;
    end;
    for K := 0 to Lines.Count - 1 do
      if Trim(Lines[K]) = FullId then
      begin
        Result := True;
        Exit;
      end;
  finally
    Lines.Free;
  end;
end;

procedure TVtExtServer.RememberInAuthedsFile(const FullId: AnsiString);
var
  Lines: TStringList;
  Dir: AnsiString;
begin
  if AuthedsPath = '' then
    Exit;
  Lines := TStringList.Create;
  try
    try
      Dir := ExtractFileDir(AuthedsPath);
      if Dir <> '' then
        ForceDirectories(Dir);
      if FileExists(AuthedsPath) then
        Lines.LoadFromFile(AuthedsPath);
      Lines.Add(FullId);
      Lines.SaveToFile(AuthedsPath);
    except
      { A file that cannot be written only means the client is asked again next time. }
    end;
  finally
    Lines.Free;
  end;
end;

function TVtExtServer.Authorise(const ClientId: AnsiString): ShortInt;
var
  FullId: AnsiString;
  Answer: TVtClipAnswer;
begin
  FullId := ClientId;
  if FIdentity <> '' then
    FullId := FIdentity + ':' + ClientId;
  Result := ClipOk;
  if IsShared(FullId) or IsInAuthedsFile(FullId) then
    Exit;
  Answer := FHost.AskClipboard(FullId);
  case Answer of
    vcaRemote:
      Result := ClipClosed;
    vcaBlock:
      Result := ClipFail;
  else
    begin
      if Answer = vcaAlways then
        RememberInAuthedsFile(FullId);
      SetLength(FShared, Length(FShared) + 1);
      FShared[High(FShared)] := FullId;
      Result := ClipOk;
    end;
  end;
end;

procedure TVtExtServer.ClipOpen(Args, Values: TF2lStack);
var
  ClientId: AnsiString;
  Status: ShortInt;
begin
  ClientId := Args.PopString;
  if Args.Failed then
    Exit;
  { A refused open leaves the chunks of a session that is open alone; without a session there are none. }
  if not FClipOpen then
    FChunk := '';
  Status := ClipFail;
  if ValidClientId(ClientId) and not FClipOpen then
    Status := Authorise(ClientId);
  if Status = ClipOk then
  begin
    FClipOpen := True;
    FSetItems := nil;
  end;
  Values.PutNumber(ServerClipFeatures, 8);
  PutStatus(Values, Status);
end;

procedure TVtExtServer.ClipClose(Values: TF2lStack);
begin
  if FClipOpen then
    PutStatus(Values, ClipOk)
  else
    PutStatus(Values, ClipClosed);
  CloseClip;
end;

procedure TVtExtServer.ClipEmpty(Values: TF2lStack);
begin
  if not FClipOpen then
  begin
    PutStatus(Values, ClipClosed);
    Exit;
  end;
  FSetItems := nil;
  VtClipSetItems(FSetItems);
  PutStatus(Values, ClipOk);
end;

procedure TVtExtServer.ClipIsAvail(Args, Values: TF2lStack);
var
  Format: LongWord;
begin
  Format := LongWord(Args.PopNumber(4));
  if Args.Failed then
    Exit;
  Values.PutNumber(Ord(VtClipHasItem(Format)), 1);
end;

procedure TVtExtServer.ClipSetChunk(Args: TF2lStack);
var
  Count: QWord;
  Piece: AnsiString;
begin
  Count := Args.PopNumber(2);
  Piece := Args.PopRaw(Count * ChunkUnit);
  if Args.Failed or not FClipOpen then
    Exit;
  if Count = 0 then
    FChunk := ''
  else
    FChunk := FChunk + Piece;
end;

{ Puts a text or another item into the list of the items set since the clipboard was opened. }
procedure TVtExtServer.PutSetItem(Format: LongWord; const Data: AnsiString);
var
  K: Integer;
begin
  for K := 0 to High(FSetItems) do
    if FSetItems[K].Format = Format then
    begin
      FSetItems[K].Data := Data;
      Exit;
    end;
  SetLength(FSetItems, Length(FSetItems) + 1);
  FSetItems[High(FSetItems)] := VtClipItem(Format, Data);
end;

procedure TVtExtServer.ClipSetData(Args, Values: TF2lStack);
var
  Format: LongWord;
  Size: QWord;
  Sent, Merged, Stored, IdBytes: AnsiString;
begin
  Format := LongWord(Args.PopNumber(4));
  Size := Args.PopNumber(4);
  Sent := Args.PopRaw(Size);
  if Args.Failed then
    Exit;
  if not FClipOpen then
  begin
    PutStatus(Values, ClipClosed);
    Exit;
  end;
  Merged := FChunk + Sent;
  FChunk := '';
  Stored := Merged;
  IdBytes := Merged;
  if Format = VtCfUnicodeText then
  begin
    Stored := Utf32BytesToUtf8(Merged);
    IdBytes := Utf8ToUtf32Bytes(Stored);
    PutSetItem(VtCfText, Stored);
  end
  else if Format = VtCfText then
  begin
    Stored := CutAtNul(Merged);
    IdBytes := Stored;
    PutSetItem(VtCfText, Stored);
  end
  else
    PutSetItem(Format, Stored);
  VtClipSetItems(FSetItems);
  Values.PutNumber(VtClipDataId(Format, IdBytes), 8);
  PutStatus(Values, ClipOk);
end;

{ True when the age of the last paste gesture allows a read. A read that extends moves the gesture time to now,
  at most GestureExtendLimit times per gesture. }
function TVtExtServer.ReadAllowed(Extend: Boolean): Boolean;
var
  Current: Int64;
begin
  Result := False;
  if not FGestureSeen then
    Exit;
  Current := CurrentTime;
  if Current - FGestureTime > GestureWindowMs then
    Exit;
  Result := True;
  if Extend and (FExtends < GestureExtendLimit) then
  begin
    FGestureTime := Current;
    Inc(FExtends);
  end;
end;

{ The data of a format as the client gets it. The text formats come from the one text slot. }
function TVtExtServer.FetchClipData(Format: LongWord; out Data: AnsiString): Boolean;
var
  Found: AnsiString;
begin
  Data := '';
  if Format = VtCfText then
  begin
    Result := VtClipGetItem(VtCfText, Data) and (Data <> '');
    Exit;
  end;
  if Format = VtCfUnicodeText then
  begin
    Result := VtClipGetItem(VtCfText, Found) and (Found <> '');
    if Result then
      Data := Utf8ToUtf32Bytes(Found);
    Exit;
  end;
  Result := VtClipGetItem(Format, Data);
end;

procedure TVtExtServer.ClipGetData(Args, Values: TF2lStack);
var
  Format: LongWord;
  Data: AnsiString;
  Allowed: Boolean;
begin
  Format := LongWord(Args.PopNumber(4));
  if Args.Failed then
    Exit;
  if not FClipOpen then
  begin
    Values.PutNumber(NoStackMark, 4);
    Exit;
  end;
  Allowed := ReadAllowed(True);
  if Allowed and FetchClipData(Format, Data) then
  begin
    Values.PutNumber(VtClipDataId(Format, Data), 8);
    Values.PutRaw(Data);
    Values.PutNumber(Length(Data), 4);
  end
  else
  begin
    Values.PutNumber(0, 8);
    Values.PutNumber(0, 4);
  end;
end;

procedure TVtExtServer.ClipGetDataId(Args, Values: TF2lStack);
var
  Format: LongWord;
  Data: AnsiString;
  DataId: QWord;
begin
  Format := LongWord(Args.PopNumber(4));
  if Args.Failed then
    Exit;
  DataId := 0;
  if FClipOpen and ReadAllowed(False) and FetchClipData(Format, Data) then
    DataId := VtClipDataId(Format, Data);
  Values.PutNumber(DataId, 8);
end;

procedure TVtExtServer.ClipRegister(Args, Values: TF2lStack);
var
  FormatName: AnsiString;
begin
  FormatName := Args.PopString;
  if Args.Failed then
    Exit;
  Values.PutNumber(VtClipRegisterFormat(FormatName), 4);
end;

{ TVtExtServer: the input events }

function TVtExtServer.KeyEvent(const Event: TEvent): AnsiString;
var
  Wire: TF2lStack;
  Ch, Shown, State: Cardinal;
  VKey: Word;
  Scan: Word;
  Code: AnsiChar;
  Pressed: Boolean;
begin
  Result := '';
  if not Active then
    Exit;
  Ch := KeyCharOf(Event);
  State := ConsoleKeyState(Event.KeyDown.ControlKeyState, True);
  VKey := KeyVirtualKeyOf(Event.KeyDown.KeyCode, Ch);
  Scan := Event.KeyDown.CharScan.ScanCode;
  Shown := Ch;
  if ((State and (LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED)) <> 0) and
    ((State and (LEFT_ALT_PRESSED or RIGHT_ALT_PRESSED)) = 0) then
    Shown := CtrlCharOf(Ch);
  Pressed := Event.What <> VtEvKeyUp;
  Wire := TF2lStack.Create;
  try
    if CompactInput and (Shown < $10000) and (VKey < $100) then
    begin
      if Pressed then
        Code := 'C'
      else
        Code := 'c';
      Wire.PutNumber(VKey, 1);
      Wire.PutNumber(State, 2);
      Wire.PutNumber(Shown, 2);
    end
    else
    begin
      if Pressed then
        Code := 'K'
      else
        Code := 'k';
      Wire.PutNumber(1, 2);
      Wire.PutNumber(VKey, 2);
      Wire.PutNumber(Scan, 2);
      Wire.PutNumber(State, 4);
      Wire.PutNumber(Shown, 4);
    end;
    Wire.PutRaw(Code);
    Result := EventText(Wire.Serialized);
  finally
    Wire.Free;
  end;
end;

function TVtExtServer.MouseEvent(X, Y: Integer; Buttons, Wheel: Byte; Moved, Double: Boolean;
  Mods: Word): AnsiString;
var
  Wire: TF2lStack;
  ButtonState, Flags, KeyState: Cardinal;
begin
  Result := '';
  if not Active then
    Exit;
  ButtonState := 0;
  if (Buttons and mbLeftButton) <> 0 then
    ButtonState := ButtonState or FROM_LEFT_1ST_BUTTON_PRESSED;
  if (Buttons and mbRightButton) <> 0 then
    ButtonState := ButtonState or RIGHTMOST_BUTTON_PRESSED;
  if (Buttons and mbMiddleButton) <> 0 then
    ButtonState := ButtonState or FROM_LEFT_2ND_BUTTON_PRESSED;
  Flags := 0;
  if Moved then
    Flags := Flags or MOUSE_MOVED;
  if Double then
    Flags := Flags or DOUBLE_CLICK;
  if (Wheel and (mwUp or mwDown)) <> 0 then
  begin
    Flags := Flags or MOUSE_WHEELED;
    if (Wheel and mwUp) <> 0 then
      ButtonState := ButtonState or (Cardinal(1) shl 16)
    else
      ButtonState := ButtonState or (Cardinal($FFFF) shl 16);
  end
  else if (Wheel and (mwLeft or mwRight)) <> 0 then
  begin
    Flags := Flags or MOUSE_HWHEELED;
    if (Wheel and mwRight) <> 0 then
      ButtonState := ButtonState or (Cardinal(1) shl 16)
    else
      ButtonState := ButtonState or (Cardinal($FFFF) shl 16);
  end;
  KeyState := ConsoleKeyState(Mods, False);
  Wire := TF2lStack.Create;
  try
    Wire.PutSigned(X, 2);
    Wire.PutSigned(Y, 2);
    if CompactInput and (Flags < $100) and ((ButtonState and $FF00FF00) = 0) then
    begin
      Wire.PutNumber((ButtonState and $FF) or (((ButtonState shr 16) and $FF) shl 8), 2);
      Wire.PutNumber(KeyState, 1);
      Wire.PutNumber(Flags, 1);
      Wire.PutRaw('m');
    end
    else
    begin
      Wire.PutNumber(ButtonState, 4);
      Wire.PutNumber(KeyState, 4);
      Wire.PutNumber(Flags, 4);
      Wire.PutRaw('M');
    end;
    Result := EventText(Wire.Serialized);
  finally
    Wire.Free;
  end;
end;

end.
