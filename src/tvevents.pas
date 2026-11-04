{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (the event structures and codes),
  include/tvision/config.h (the constants), include/tvision/internal/termio.h, source/platform/termio.cpp,
  source/platform/far2l.cpp, include/tvision/internal/win32con.h,
  source/platform/win32con.cpp (the input parts)
  The reader of the Windows console (ReadConsoleInput and the console input records) is not part of this unit.
  See COPYRIGHT.magiblot. }
unit TvEvents;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvKeys, TvUtf8;

const
  { Event codes }
  evMouseDown = $0001;
  evMouseUp = $0002;
  evMouseMove = $0004;
  evMouseAuto = $0008;
  evMouseWheel = $0020;
  evKeyDown = $0010;
  evCommand = $0100;
  evBroadcast = $0200;

  { Event masks }
  evNothing = $0000;
  evMouse = $002F;
  evKeyboard = $0010;
  evMessage = $FF00;

  { Mouse button state masks }
  mbLeftButton = $01;
  mbRightButton = $02;
  mbMiddleButton = $04;

  { Mouse wheel state masks }
  mwUp = $01;
  mwDown = $02;
  mwLeft = $04;
  mwRight = $08;

  { Mouse event flags }
  meMouseMoved = $01;
  meDoubleClick = $02;
  meTripleClick = $04;

  { The size of the text of a key event: the longest UTF-8 sequence. }
  maxCharSize = 4;
  { The number of consecutive text events from which the input is taken as a paste. }
  minPasteEventCount = 3;

  { Flags of the mouse events of the console (dwEventFlags): the values of the document
    tools/audit/facts/windows-console-mouse-event-record-str.md }
  MOUSE_WHEELED = $0004;
  MOUSE_HWHEELED = $0008;

  { Virtual key codes: the names and values of the document
    tools/audit/facts/windows-virtual-key-codes.md }
  VK_BACK = $08;
  VK_TAB = $09;
  VK_RETURN = $0D;
  VK_MENU = $12;
  VK_ESCAPE = $1B;
  VK_SPACE = $20;
  VK_PRIOR = $21;
  VK_NEXT = $22;
  VK_END = $23;
  VK_HOME = $24;
  VK_LEFT = $25;
  VK_UP = $26;
  VK_RIGHT = $27;
  VK_DOWN = $28;
  VK_INSERT = $2D;
  VK_DELETE = $2E;
  VK_NUMPAD0 = $60;
  VK_NUMPAD1 = $61;
  VK_NUMPAD2 = $62;
  VK_NUMPAD3 = $63;
  VK_NUMPAD4 = $64;
  VK_NUMPAD5 = $65;
  VK_NUMPAD6 = $66;
  VK_NUMPAD7 = $67;
  VK_NUMPAD8 = $68;
  VK_NUMPAD9 = $69;
  VK_MULTIPLY = $6A;
  VK_ADD = $6B;
  VK_SEPARATOR = $6C;
  VK_SUBTRACT = $6D;
  VK_DECIMAL = $6E;
  VK_DIVIDE = $6F;
  VK_F1 = $70;
  VK_F2 = $71;
  VK_F3 = $72;
  VK_F4 = $73;
  VK_F5 = $74;
  VK_F6 = $75;
  VK_F7 = $76;
  VK_F8 = $77;
  VK_F9 = $78;
  VK_F10 = $79;
  VK_F11 = $7A;
  VK_F12 = $7B;

type
  TMouseEventType = record
    Where: TPoint;
    EventFlags: Word; { Replacement for doubleClick. }
    ControlKeyState: Word;
    Buttons: Byte;
    Wheel: Byte;
  end;

  { The two bytes of a key code, as they lie in memory on a little-endian machine. }
  TCharScanType = record
    CharCode: Byte;
    ScanCode: Byte;
  end;

  { CharScan and KeyCode share their two bytes. Text is not zero-terminated. }
  TKeyDownEvent = record
    { Returns the first TextLength bytes of Text. }
    function GetText: string;
    function ToKey: TKey;
    case Byte of
      0: (KeyCode: Word;
          ControlKeyState: Word;
          Text: TUtf8Bytes;
          TextLength: Byte);
      1: (CharScan: TCharScanType);
  end;

  { The members after Command share their storage. }
  TMessageEvent = record
    Command: Word;
    case Integer of
      1: (InfoPtr: Pointer);
      2: (InfoLong: Int32);
      3: (InfoWord: UInt16);
      4: (InfoInt: Int16);
      5: (InfoByte: UInt8);
      6: (InfoChar: Char);
  end;

  { Mouse, KeyDown and Message share their storage. }
  TEvent = record
    What: Word;
    case Byte of
      0: (Mouse: TMouseEventType);
      1: (KeyDown: TKeyDownEvent);
      2: (Message: TMessageEvent);
  end;

  TParseResult = (Rejected, Accepted, Ignored);

  { A procedure that receives text: a write to the terminal, or a pasted text. }
  TTextProc = procedure(const Text: string);

  TFar2lState = record
    Enabled: Boolean;
  end;

  TInputState = record
    Buttons: Byte;
    Far2l: TFar2lState;
    HasFullOsc52: Boolean;
    BracketedPaste: Boolean;
    GotDsrResponse: Boolean;
    PutPaste: TTextProc;
  end;
  PInputState = ^TInputState;

  { A source of input bytes; Get returns -1 when there is none. }
  TInputGetter = class
  public
    function Get: Integer; virtual; abstract;
    procedure Unget(Key: Integer); virtual; abstract;
  end;

  { Remembers the keys read, so that they can be ungotten. }
  TGetChBuf = record
  private
    Size: Cardinal;
    Keys: array[0..30] of Integer;
  public
    In_: TInputGetter;
    constructor Create(AIn: TInputGetter);
    function GetUnbuffered: Integer;
    function Get(KeepErr: Boolean = False): Integer;
    function Last(I: SizeInt = 0): Integer;
    procedure Unget;
    procedure Reject;
    { Read a decimal number. The last key read, a non-digit or -1, is left in Last. }
    function GetNum(var Value: Cardinal): Boolean;
    function GetInt(var Value: Integer): Boolean;
    function ReadStr(const Str: string): Boolean;
  end;

const
  CSIMaxLength = 6;

type
  { The data of a CSI escape sequence. For "ESC [ 123 :: 456 ; 789 u": Length is 5, Terminator is 'u',
    GetValue(0) is 123, GetSeparator(0) is ':', GetValue(1) is the default, GetSeparator(1) is ':',
    GetValue(2) is 456, GetSeparator(2) is ';', GetValue(3) is 789. }
  TCSIData = record
    Length: Cardinal;
    Values: array[0..CSIMaxLength - 1] of Cardinal;
    Separators: array[0..CSIMaxLength - 1] of Char;
    Terminator: Char;
    function ReadFrom(var Buf: TGetChBuf): Boolean;
    function GetValue(I: Cardinal; ADefault: Cardinal = 1): Cardinal;
    function GetSeparator(I: Cardinal): Char;
  end;

  TBase64Func = function(const S: string): string;
  TCpFunc = function(const Text: string): Byte;

var
  { Conversions between bytes and Base64 text. They must be set before the far2l and OSC 52 input
    and the clipboard are used; while unset, the input is ignored and the clipboard reports failure. }
  Base64Decode: TBase64Func = nil;
  Base64Encode: TBase64Func = nil;

  { Conversions of the text of a key to its character in the current code page; 0 when it has none.
    While unset, only a single ASCII character converts. }
  CpFromUtf8: TCpFunc = nil;
  CpPrintableFromUtf8: TCpFunc = nil;

  { The sequences that turn the far2l terminal extensions on and off. }
  Far2lEnableSeq: string = '';
  Far2lDisableSeq: string = '';

  { Conversion of the scan codes 0..88 of the Windows console to key codes, without a modifier and
    with Shift, Ctrl and Alt. A zero entry means no conversion. }
  NormalCvt, ShiftCvt, CtrlCvt, AltCvt: array[0..88] of Word;

{ Conversion of the fields of Windows console input events, as the win32 input mode and the far2l extension
  deliver them: the virtual key code, the scan code, the character (a whole code point), the state of the
  control keys, the position, the state of the buttons and the event flags. }

{ Returns False when the key gives no event. }
function GetWin32Key(VirtualKey, ScanCode: Word; UnicodeChar, ControlKeyState: Cardinal; var Ev: TEvent;
  var State: TInputState): Boolean;
procedure GetWin32Mouse(X, Y: SmallInt; ButtonState, ControlKeyState, EventFlags: Cardinal; var Ev: TEvent;
  var State: TInputState);
procedure RegenerateMissingScanCodeFromVirtualKeyCode(VirtualKey: Word; var ScanCode: Word;
  var UnicodeChar: Cardinal; ControlKeyState: Cardinal);

{ Terminal input and its control sequences. The procedures that switch features on and off pass the
  sequence to Writer. }

procedure MouseOn(Writer: TTextProc);
procedure MouseOff(Writer: TTextProc);

{ The sequence of KeyModsOn for a TERM that is set (HasTerm) and has the value Term. }
function KeyModsOnSequence(HasTerm: Boolean; const Term: string): string;
procedure KeyModsOn(Writer: TTextProc);
procedure KeyModsOff(Writer: TTextProc);

procedure NormalizeKey(var KeyDown: TKeyDownEvent);

function SetClipboardText(Writer: TTextProc; const Text: string; var State: TInputState): Boolean;
function RequestClipboardText(Writer: TTextProc; Accept: TTextProc; var State: TInputState): Boolean;

function ParseEvent(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
function ParseEscapeSeq(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
function ParseX10Mouse(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
function ParseSGRMouse(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
function ParseCSIKey(const Csi: TCSIData; var Ev: TEvent; var State: TInputState): TParseResult;
function ParseSS3Key(var Buf: TGetChBuf; var Ev: TEvent): TParseResult;
function ParseKittyKey(const Csi: TCSIData; var Ev: TEvent): TParseResult;
function ParseDCS(var Buf: TGetChBuf; var State: TInputState): TParseResult;
function ParseOSC(var Buf: TGetChBuf; var State: TInputState): TParseResult;
function ParseCPR(const Csi: TCSIData; var State: TInputState): TParseResult;
function ParseWin32InputModeKeyOrEscapeSeq(const Csi: TCSIData; In_: TInputGetter; var Ev: TEvent;
  var State: TInputState): TParseResult;

{ Reads up to BEL or ST, which are not part of the result. The result ends at its first zero byte. }
function ReadUntilBelOrSt(var Buf: TGetChBuf): string;

{ Writes a Device Status Report request and reads input until its response comes or 200 ms pass. }
procedure ConsumeUnprocessedInput(Writer: TTextProc; In_: TInputGetter; var State: TInputState);

{ The far2l terminal extension }

function ParseFar2lInput(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
function ParseFar2lAnswer(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;

implementation

uses
  SysUtils;

const
  XTermModDefault = 1;

  mmAlt = $08;
  mmCtrl = $10;

  { Request IDs of the far2l extension }
  f2lClipGetData = #$A0;

type
  TModdedKeyCodes = array[0..2] of Word;

  TModdedKeyEntry = record
    KeyCode: Word;
    Modded: TModdedKeyCodes;
  end;

  TVirtualKeyEntry = record
    VirtualKey: Byte;
    KeyCode: Word;
  end;

const
  { The key codes with Shift, Ctrl and Alt applied to the key code }
  ModdedKeyCodes: array[0..64] of TModdedKeyEntry = (
    (KeyCode: Ord('A'); Modded: (0, kbCtrlA, kbAltA)),
    (KeyCode: Ord('B'); Modded: (0, kbCtrlB, kbAltB)),
    (KeyCode: Ord('C'); Modded: (0, kbCtrlC, kbAltC)),
    (KeyCode: Ord('D'); Modded: (0, kbCtrlD, kbAltD)),
    (KeyCode: Ord('E'); Modded: (0, kbCtrlE, kbAltE)),
    (KeyCode: Ord('F'); Modded: (0, kbCtrlF, kbAltF)),
    (KeyCode: Ord('G'); Modded: (0, kbCtrlG, kbAltG)),
    (KeyCode: Ord('H'); Modded: (0, kbCtrlH, kbAltH)),
    (KeyCode: Ord('I'); Modded: (0, kbCtrlI, kbAltI)),
    (KeyCode: Ord('J'); Modded: (0, kbCtrlJ, kbAltJ)),
    (KeyCode: Ord('K'); Modded: (0, kbCtrlK, kbAltK)),
    (KeyCode: Ord('L'); Modded: (0, kbCtrlL, kbAltL)),
    (KeyCode: Ord('M'); Modded: (0, kbCtrlM, kbAltM)),
    (KeyCode: Ord('N'); Modded: (0, kbCtrlN, kbAltN)),
    (KeyCode: Ord('O'); Modded: (0, kbCtrlO, kbAltO)),
    (KeyCode: Ord('P'); Modded: (0, kbCtrlP, kbAltP)),
    (KeyCode: Ord('Q'); Modded: (0, kbCtrlQ, kbAltQ)),
    (KeyCode: Ord('R'); Modded: (0, kbCtrlR, kbAltR)),
    (KeyCode: Ord('S'); Modded: (0, kbCtrlS, kbAltS)),
    (KeyCode: Ord('T'); Modded: (0, kbCtrlT, kbAltT)),
    (KeyCode: Ord('U'); Modded: (0, kbCtrlU, kbAltU)),
    (KeyCode: Ord('V'); Modded: (0, kbCtrlV, kbAltV)),
    (KeyCode: Ord('W'); Modded: (0, kbCtrlW, kbAltW)),
    (KeyCode: Ord('X'); Modded: (0, kbCtrlX, kbAltX)),
    (KeyCode: Ord('Y'); Modded: (0, kbCtrlY, kbAltY)),
    (KeyCode: Ord('Z'); Modded: (0, kbCtrlZ, kbAltZ)),
    (KeyCode: Ord('1'); Modded: (0, 0, kbAlt1)),
    (KeyCode: Ord('2'); Modded: (0, 0, kbAlt2)),
    (KeyCode: Ord('3'); Modded: (0, 0, kbAlt3)),
    (KeyCode: Ord('4'); Modded: (0, 0, kbAlt4)),
    (KeyCode: Ord('5'); Modded: (0, 0, kbAlt5)),
    (KeyCode: Ord('6'); Modded: (0, 0, kbAlt6)),
    (KeyCode: Ord('7'); Modded: (0, 0, kbAlt7)),
    (KeyCode: Ord('8'); Modded: (0, 0, kbAlt8)),
    (KeyCode: Ord('9'); Modded: (0, 0, kbAlt9)),
    (KeyCode: Ord('0'); Modded: (0, 0, kbAlt0)),
    (KeyCode: Ord(' '); Modded: (0, 0, kbAltSpace)),
    (KeyCode: Ord('-'); Modded: (0, 0, kbAltMinus)),
    (KeyCode: Ord('='); Modded: (0, 0, kbAltEqual)),
    (KeyCode: kbF1; Modded: (kbShiftF1, kbCtrlF1, kbAltF1)),
    (KeyCode: kbF2; Modded: (kbShiftF2, kbCtrlF2, kbAltF2)),
    (KeyCode: kbF3; Modded: (kbShiftF3, kbCtrlF3, kbAltF3)),
    (KeyCode: kbF4; Modded: (kbShiftF4, kbCtrlF4, kbAltF4)),
    (KeyCode: kbF5; Modded: (kbShiftF5, kbCtrlF5, kbAltF5)),
    (KeyCode: kbF6; Modded: (kbShiftF6, kbCtrlF6, kbAltF6)),
    (KeyCode: kbF7; Modded: (kbShiftF7, kbCtrlF7, kbAltF7)),
    (KeyCode: kbF8; Modded: (kbShiftF8, kbCtrlF8, kbAltF8)),
    (KeyCode: kbF9; Modded: (kbShiftF9, kbCtrlF9, kbAltF9)),
    (KeyCode: kbF10; Modded: (kbShiftF10, kbCtrlF10, kbAltF10)),
    (KeyCode: kbF11; Modded: (kbShiftF11, kbCtrlF11, kbAltF11)),
    (KeyCode: kbF12; Modded: (kbShiftF12, kbCtrlF12, kbAltF12)),
    (KeyCode: kbEsc; Modded: (0, 0, kbAltEsc)),
    (KeyCode: kbBack; Modded: (0, kbCtrlBack, kbAltBack)),
    (KeyCode: kbTab; Modded: (kbShiftTab, kbCtrlTab, kbAltTab)),
    (KeyCode: kbEnter; Modded: (0, kbCtrlEnter, kbAltEnter)),
    (KeyCode: kbHome; Modded: (0, kbCtrlHome, kbAltHome)),
    (KeyCode: kbUp; Modded: (0, kbCtrlUp, kbAltUp)),
    (KeyCode: kbPgUp; Modded: (0, kbCtrlPgUp, kbAltPgUp)),
    (KeyCode: kbLeft; Modded: (0, kbCtrlLeft, kbAltLeft)),
    (KeyCode: kbRight; Modded: (0, kbCtrlRight, kbAltRight)),
    (KeyCode: kbEnd; Modded: (0, kbCtrlEnd, kbAltEnd)),
    (KeyCode: kbDown; Modded: (0, kbCtrlDown, kbAltDown)),
    (KeyCode: kbPgDn; Modded: (0, kbCtrlPgDn, kbAltPgDn)),
    (KeyCode: kbIns; Modded: (kbShiftIns, kbCtrlIns, kbAltIns)),
    (KeyCode: kbDel; Modded: (kbShiftDel, kbCtrlDel, kbAltDel))
  );

  { The key codes that the Windows console reports for its virtual key codes }
  VirtualKeyTable: array[0..78] of TVirtualKeyEntry = (
    (VirtualKey: VK_BACK; KeyCode: kbBack),
    (VirtualKey: VK_TAB; KeyCode: kbTab),
    (VirtualKey: VK_RETURN; KeyCode: kbEnter),
    (VirtualKey: VK_ESCAPE; KeyCode: kbEsc),
    (VirtualKey: Ord('0'); KeyCode: $0B00 or Ord('0')),
    (VirtualKey: Ord('1'); KeyCode: $0200 or Ord('1')),
    (VirtualKey: Ord('2'); KeyCode: $0300 or Ord('2')),
    (VirtualKey: Ord('3'); KeyCode: $0400 or Ord('3')),
    (VirtualKey: Ord('4'); KeyCode: $0500 or Ord('4')),
    (VirtualKey: Ord('5'); KeyCode: $0600 or Ord('5')),
    (VirtualKey: Ord('6'); KeyCode: $0700 or Ord('6')),
    (VirtualKey: Ord('7'); KeyCode: $0800 or Ord('7')),
    (VirtualKey: Ord('8'); KeyCode: $0900 or Ord('8')),
    (VirtualKey: Ord('9'); KeyCode: $0A00 or Ord('9')),
    (VirtualKey: VK_SPACE; KeyCode: $3900 or Ord(' ')),
    (VirtualKey: Ord('A'); KeyCode: $1E00 or Ord('A')),
    (VirtualKey: Ord('B'); KeyCode: $3000 or Ord('B')),
    (VirtualKey: Ord('C'); KeyCode: $2E00 or Ord('C')),
    (VirtualKey: Ord('D'); KeyCode: $2000 or Ord('D')),
    (VirtualKey: Ord('E'); KeyCode: $1200 or Ord('E')),
    (VirtualKey: Ord('F'); KeyCode: $2100 or Ord('F')),
    (VirtualKey: Ord('G'); KeyCode: $2200 or Ord('G')),
    (VirtualKey: Ord('H'); KeyCode: $2300 or Ord('H')),
    (VirtualKey: Ord('I'); KeyCode: $1700 or Ord('I')),
    (VirtualKey: Ord('J'); KeyCode: $2400 or Ord('J')),
    (VirtualKey: Ord('K'); KeyCode: $2500 or Ord('K')),
    (VirtualKey: Ord('L'); KeyCode: $2600 or Ord('L')),
    (VirtualKey: Ord('M'); KeyCode: $3200 or Ord('M')),
    (VirtualKey: Ord('N'); KeyCode: $3100 or Ord('N')),
    (VirtualKey: Ord('O'); KeyCode: $1800 or Ord('O')),
    (VirtualKey: Ord('P'); KeyCode: $1900 or Ord('P')),
    (VirtualKey: Ord('Q'); KeyCode: $1000 or Ord('Q')),
    (VirtualKey: Ord('R'); KeyCode: $1300 or Ord('R')),
    (VirtualKey: Ord('S'); KeyCode: $1F00 or Ord('S')),
    (VirtualKey: Ord('T'); KeyCode: $1400 or Ord('T')),
    (VirtualKey: Ord('U'); KeyCode: $1600 or Ord('U')),
    (VirtualKey: Ord('V'); KeyCode: $2F00 or Ord('V')),
    (VirtualKey: Ord('W'); KeyCode: $1100 or Ord('W')),
    (VirtualKey: Ord('X'); KeyCode: $2D00 or Ord('X')),
    (VirtualKey: Ord('Y'); KeyCode: $1500 or Ord('Y')),
    (VirtualKey: Ord('Z'); KeyCode: $2C00 or Ord('Z')),
    (VirtualKey: VK_PRIOR; KeyCode: kbPgUp),
    (VirtualKey: VK_NEXT; KeyCode: kbPgDn),
    (VirtualKey: VK_END; KeyCode: kbEnd),
    (VirtualKey: VK_HOME; KeyCode: kbHome),
    (VirtualKey: VK_LEFT; KeyCode: kbLeft),
    (VirtualKey: VK_UP; KeyCode: kbUp),
    (VirtualKey: VK_RIGHT; KeyCode: kbRight),
    (VirtualKey: VK_DOWN; KeyCode: kbDown),
    (VirtualKey: VK_INSERT; KeyCode: kbIns),
    (VirtualKey: VK_DELETE; KeyCode: kbDel),
    (VirtualKey: VK_NUMPAD0; KeyCode: $5200 or Ord('0')),
    (VirtualKey: VK_NUMPAD1; KeyCode: $4F00 or Ord('1')),
    (VirtualKey: VK_NUMPAD2; KeyCode: $5000 or Ord('2')),
    (VirtualKey: VK_NUMPAD3; KeyCode: $5100 or Ord('3')),
    (VirtualKey: VK_NUMPAD4; KeyCode: $4B00 or Ord('4')),
    (VirtualKey: VK_NUMPAD5; KeyCode: $4C00 or Ord('5')),
    (VirtualKey: VK_NUMPAD6; KeyCode: $4D00 or Ord('6')),
    (VirtualKey: VK_NUMPAD7; KeyCode: $4700 or Ord('7')),
    (VirtualKey: VK_NUMPAD8; KeyCode: $4800 or Ord('8')),
    (VirtualKey: VK_NUMPAD9; KeyCode: $4900 or Ord('9')),
    (VirtualKey: VK_MULTIPLY; KeyCode: $3700 or Ord('*')),
    (VirtualKey: VK_ADD; KeyCode: $4E00 or Ord('+')),
    (VirtualKey: VK_SEPARATOR; KeyCode: $7E00 or Ord(',')),
    (VirtualKey: VK_SUBTRACT; KeyCode: $4A00 or Ord('-')),
    (VirtualKey: VK_DECIMAL; KeyCode: $5300 or Ord('.')),
    (VirtualKey: VK_DIVIDE; KeyCode: $3500 or Ord('/')),
    (VirtualKey: VK_F1; KeyCode: kbF1),
    (VirtualKey: VK_F2; KeyCode: kbF2),
    (VirtualKey: VK_F3; KeyCode: kbF3),
    (VirtualKey: VK_F4; KeyCode: kbF4),
    (VirtualKey: VK_F5; KeyCode: kbF5),
    (VirtualKey: VK_F6; KeyCode: kbF6),
    (VirtualKey: VK_F7; KeyCode: kbF7),
    (VirtualKey: VK_F8; KeyCode: kbF8),
    (VirtualKey: VK_F9; KeyCode: kbF9),
    (VirtualKey: VK_F10; KeyCode: kbF10),
    (VirtualKey: VK_F11; KeyCode: kbF11),
    (VirtualKey: VK_F12; KeyCode: kbF12)
  );

{ Binary data of the far2l extension: integers are little-endian. }

function ReadLE16(const S: string; Index: SizeInt): Word;
begin
  Result := Word(Ord(S[Index + 1])) or (Word(Ord(S[Index + 2])) shl 8);
end;

function ReadLE32(const S: string; Index: SizeInt): Cardinal;
begin
  Result := Cardinal(ReadLE16(S, Index)) or (Cardinal(ReadLE16(S, Index + 2)) shl 16);
end;

function DecodeBase64Text(const Encoded: string): string;
begin
  if Assigned(Base64Decode) then
    Result := Base64Decode(Encoded)
  else
    Result := '';
end;

function CodePageOf(Func: TCpFunc; const Text: string): Byte;
begin
  if Assigned(Func) then
    Result := Func(Text)
  else if (Length(Text) = 1) and (Ord(Text[1]) < $80) then
    Result := Ord(Text[1])
  else
    Result := 0;
end;

{ TKeyDownEvent }

function TKeyDownEvent.GetText: string;
begin
  SetString(Result, PAnsiChar(@Text[0]), TextLength);
end;

function TKeyDownEvent.ToKey: TKey;
begin
  Result := TKey.Create(KeyCode, ControlKeyState);
end;

function MakeKeyDown(AKeyCode, AControlKeyState: Word): TKeyDownEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.KeyCode := AKeyCode;
  Result.ControlKeyState := AControlKeyState;
end;

{ TGetChBuf }

constructor TGetChBuf.Create(AIn: TInputGetter);
begin
  In_ := AIn;
  Size := 0;
end;

function TGetChBuf.GetUnbuffered: Integer;
begin
  Result := In_.Get;
end;

function TGetChBuf.Get(KeepErr: Boolean): Integer;
var
  K: Integer;
begin
  if Size < Length(Keys) then
  begin
    K := In_.Get;
    if KeepErr or (K <> -1) then
    begin
      Keys[Size] := K;
      Inc(Size);
    end;
    Result := K;
  end
  else
    Result := -1;
end;

function TGetChBuf.Last(I: SizeInt): Integer;
begin
  if I < Size then
    Result := Keys[Size - 1 - I]
  else
    Result := -1;
end;

procedure TGetChBuf.Unget;
var
  K: Integer;
begin
  if Size > 0 then
  begin
    Dec(Size);
    K := Keys[Size];
    if K <> -1 then
      In_.Unget(K);
  end;
end;

procedure TGetChBuf.Reject;
begin
  while Size > 0 do
    Unget;
end;

{ GetNum and GetInt leave the last key read that is not a digit, or -1, in Last, and it can be ungotten. }

function TGetChBuf.GetNum(var Value: Cardinal): Boolean;
var
  Num, Digits: Cardinal;
  K: Integer;
begin
  Num := 0;
  Digits := 0;
  K := Get(True);
  while (K >= Ord('0')) and (K <= Ord('9')) do
  begin
    Num := 10 * Num + Cardinal(K - Ord('0'));
    Inc(Digits);
    K := Get(True);
  end;
  Result := Digits <> 0;
  if Result then
    Value := Num;
end;

function TGetChBuf.GetInt(var Value: Integer): Boolean;
var
  Num, Digits, Sign, K: Integer;
begin
  Num := 0;
  Digits := 0;
  Sign := 1;
  K := Get(True);
  if K = Ord('-') then
  begin
    Sign := -1;
    K := Get(True);
  end;
  while (K >= Ord('0')) and (K <= Ord('9')) do
  begin
    Num := 10 * Num + (K - Ord('0'));
    Inc(Digits);
    K := Get(True);
  end;
  Result := Digits <> 0;
  if Result then
    Value := Sign * Num;
end;

function TGetChBuf.ReadStr(const Str: string): Boolean;
var
  OrigSize: Cardinal;
  I: SizeInt;
begin
  OrigSize := Size;
  I := 0;
  while (I < Length(Str)) and (Get = Ord(Str[I + 1])) do
    Inc(I);
  if I = Length(Str) then
  begin
    Result := True;
    Exit;
  end;
  while OrigSize < Size do
    Unget;
  Result := False;
end;

{ TCSIData }

{ Pre: ESC [ has just been read. }
function TCSIData.ReadFrom(var Buf: TGetChBuf): Boolean;
var
  I: Cardinal;
  K: Integer;
begin
  Result := False;
  for I := 0 to CSIMaxLength - 1 do
  begin
    if not Buf.GetNum(Values[I]) then
      Values[I] := High(Cardinal);
    K := Buf.Last;
    if K = -1 then
      { No more input and the CSI is not complete yet. }
      Exit;
    if (K = Ord(';')) or (K = Ord(':')) then
      Separators[I] := Char(K)
    else
    begin
      Terminator := Char(K);
      Length := I + 1;
      Result := True;
      Exit;
    end;
  end;
  { The CSI may be longer than is supported. }
end;

function TCSIData.GetValue(I: Cardinal; ADefault: Cardinal): Cardinal;
begin
  if (I < Length) and (Values[I] <> High(Cardinal)) then
    Result := Values[I]
  else
    Result := ADefault;
end;

function TCSIData.GetSeparator(I: Cardinal): Char;
begin
  if (Length > 0) and (I < Length - 1) then
    Result := Separators[I]
  else
    Result := #0;
end;

{ Keys of the terminal }

function GetModdedKeyCode(KeyCode, TvMods: Word): Word;
var
  I, LargestMod: Integer;
begin
  { Modifier precedence: Shift < Ctrl < Alt. }
  if (TvMods and kbLeftAlt) <> 0 then
    LargestMod := 2
  else if (TvMods and kbLeftCtrl) <> 0 then
    LargestMod := 1
  else
    LargestMod := 0;
  Result := 0;
  for I := Low(ModdedKeyCodes) to High(ModdedKeyCodes) do
    if ModdedKeyCodes[I].KeyCode = KeyCode then
    begin
      Result := ModdedKeyCodes[I].Modded[LargestMod];
      Exit;
    end;
end;

function KeyWithXTermMods(KeyCode: Word; Mods: Cardinal): TKeyDownEvent;
var
  TvMods: Word;
begin
  Mods := Mods - XTermModDefault;
  TvMods := 0;
  if (Mods and 1) <> 0 then
    TvMods := TvMods or kbShift;
  if (Mods and 2) <> 0 then
    TvMods := TvMods or kbLeftAlt;
  if (Mods and 4) <> 0 then
    TvMods := TvMods or kbLeftCtrl;
  Result := MakeKeyDown(KeyCode, TvMods);
  NormalizeKey(Result);
end;

function IsAlpha(Ascii: Cardinal): Boolean;
begin
  Result := (Ord(' ') <= Ascii) and (Ascii < 127);
end;

function IsAsciiLetter(Ch: Cardinal): Boolean;
begin
  Result := ((Ord('A') <= Ch) and (Ch <= Ord('Z'))) or ((Ord('a') <= Ch) and (Ch <= Ord('z')));
end;

function IsPrivate(Codepoint: Cardinal): Boolean;
begin
  Result := (57344 <= Codepoint) and (Codepoint <= 63743);
end;

function KeyFromCodepoint(Value, Mods: Cardinal; var KeyDown: TKeyDownEvent): Boolean;
var
  KeyCode: Word;
  Codepoint: Cardinal;
  Bytes: TUtf8Bytes;
begin
  KeyCode := 0;
  case Value of
    8: KeyCode := kbBack;
    9: KeyCode := kbTab;
    13: KeyCode := kbEnter;
    27: KeyCode := kbEsc;
    127: KeyCode := kbBack;
    { Functional keys as represented in the keyboard protocol of Kitty. }
    { Keypad. }
    57399: KeyCode := Ord('0');
    57400: KeyCode := Ord('1');
    57401: KeyCode := Ord('2');
    57402: KeyCode := Ord('3');
    57403: KeyCode := Ord('4');
    57404: KeyCode := Ord('5');
    57405: KeyCode := Ord('6');
    57406: KeyCode := Ord('7');
    57407: KeyCode := Ord('8');
    57408: KeyCode := Ord('9');
    57409: KeyCode := Ord('.');
    57410: KeyCode := Ord('/');
    57411: KeyCode := Ord('*');
    57412: KeyCode := Ord('-');
    57413: KeyCode := Ord('+');
    57414: KeyCode := kbEnter;
    57415: KeyCode := Ord('=');
    57416: KeyCode := Ord(',');
    57417: KeyCode := kbLeft;
    57418: KeyCode := kbRight;
    57419: KeyCode := kbUp;
    57420: KeyCode := kbDown;
    57421: KeyCode := kbPgUp;
    57422: KeyCode := kbPgDn;
    57423: KeyCode := kbHome;
    57424: KeyCode := kbEnd;
    57425: KeyCode := kbIns;
    57426: KeyCode := kbDel;
  else
    if IsAlpha(Value) then
      KeyCode := Value;
  end;
  KeyDown := KeyWithXTermMods(KeyCode, Mods);
  if IsAlpha(KeyDown.KeyCode) or
     ((KeyDown.KeyCode = 0) and (Ord(' ') <= Value) and not IsPrivate(Value)) then
  begin
    if KeyDown.KeyCode = 0 then
      Codepoint := Value
    else
      Codepoint := KeyDown.KeyCode;
    KeyDown.TextLength := Utf32To8(Codepoint, Bytes);
    KeyDown.Text := Bytes;
    KeyDown.CharScan.CharCode := CodePageOf(CpPrintableFromUtf8, KeyDown.GetText);
  end;
  Result := (KeyDown.KeyCode <> 0) or (KeyDown.TextLength <> 0);
end;

function KeyFromLetter(Letter, Mods: Cardinal; var KeyDown: TKeyDownEvent): Boolean;
var
  KeyCode: Word;
begin
  KeyCode := 0;
  case Letter of
    Ord('A'): KeyCode := kbUp;
    Ord('B'): KeyCode := kbDown;
    Ord('C'): KeyCode := kbRight;
    Ord('D'): KeyCode := kbLeft;
    Ord('E'): KeyCode := kbNoKey; { Numpad 5, "KP_Begin". }
    Ord('F'): KeyCode := kbEnd;
    Ord('H'): KeyCode := kbHome;
    Ord('P'): KeyCode := kbF1;
    Ord('Q'): KeyCode := kbF2;
    Ord('R'): KeyCode := kbF3;
    Ord('S'): KeyCode := kbF4;
    Ord('Z'): KeyCode := kbTab;
    { Keypad in XTerm (SS3). }
    Ord('j'): KeyCode := Ord('*');
    Ord('k'): KeyCode := Ord('+');
    Ord('m'): KeyCode := Ord('-');
    Ord('M'): KeyCode := kbEnter;
    Ord('n'): KeyCode := kbDel;
    Ord('o'): KeyCode := Ord('/');
    Ord('p'): KeyCode := kbIns;
    Ord('q'): KeyCode := kbEnd;
    Ord('r'): KeyCode := kbDown;
    Ord('s'): KeyCode := kbPgDn;
    Ord('t'): KeyCode := kbLeft;
    Ord('u'): KeyCode := kbNoKey; { Numpad 5, "KP_Begin". }
    Ord('v'): KeyCode := kbRight;
    Ord('w'): KeyCode := kbHome;
    Ord('x'): KeyCode := kbUp;
    Ord('y'): KeyCode := kbPgUp;
  else
    begin
      Result := False;
      Exit;
    end;
  end;
  KeyDown := KeyWithXTermMods(KeyCode, Mods);
  if IsAlpha(KeyDown.KeyCode) then
  begin
    KeyDown.Text[0] := KeyDown.KeyCode;
    KeyDown.TextLength := 1;
  end;
  Result := True;
end;

{ Windows console input }

{ Sets the text of the key from the character, which is a whole code point. }
procedure GetWin32KeyText(UnicodeChar: Cardinal; var Ev: TEvent);
var
  Bytes: TUtf8Bytes;
  Count: SizeInt;
begin
  Ev.KeyDown.TextLength := 0;

  { Non-printable characters are not text. }
  if (Ord(' ') <= UnicodeChar) and (UnicodeChar <> $7F) then
    if (UnicodeChar < $D800) or ((UnicodeChar > $DFFF) and (UnicodeChar < $10FFFF)) then
    begin
      Count := Utf32To8(UnicodeChar, Bytes);
      Ev.KeyDown.Text := Bytes;
      Ev.KeyDown.TextLength := Count;
    end;
end;

function IsStandaloneModifierKey(KeyCode: Word): Boolean;
begin
  Result := (KeyCode = $2A00) or (KeyCode = $1D00) or (KeyCode = $3600) or (KeyCode = $3800) or
    (KeyCode = $3A00) or (KeyCode = $5B00) or (KeyCode = $5C00);
end;

function GetWin32Key(VirtualKey, ScanCode: Word; UnicodeChar, ControlKeyState: Cardinal; var Ev: TEvent;
  var State: TInputState): Boolean;
var
  Index: Byte;
  KeyCode: Word;
begin
  GetWin32KeyText(UnicodeChar, Ev);

  Ev.What := evKeyDown;
  Ev.KeyDown.CharScan.ScanCode := Byte(ScanCode);
  Ev.KeyDown.CharScan.CharCode := Byte(UnicodeChar);
  Ev.KeyDown.ControlKeyState := Word(ControlKeyState and
    (kbShift or kbCtrlShift or kbAltShift or kbScrollState or kbNumState or kbCapsState));

  if Ev.KeyDown.TextLength <> 0 then
  begin
    Ev.KeyDown.CharScan.CharCode := CodePageOf(CpFromUtf8, Ev.KeyDown.GetText);
    if VirtualKey = VK_MENU then
      { This is enabled when pasting certain characters, and it confuses applications. Clear it. }
      Ev.KeyDown.CharScan.ScanCode := 0;
    if (Ev.KeyDown.CharScan.CharCode = 0) or (Ev.KeyDown.KeyCode <= kbCtrlZ) then
      { If the character cannot be represented in the current code page, or if it would accidentally
        trigger a Ctrl+Key combination, the whole key code becomes zero to avoid side effects. }
      Ev.KeyDown.KeyCode := kbNoKey;
  end;

  if IsStandaloneModifierKey(Ev.KeyDown.KeyCode) then
    { Discard standalone Shift, Ctrl, Alt, Caps Lock, Windows keys. }
    Ev.KeyDown.KeyCode := kbNoKey
  else if ((Ev.KeyDown.ControlKeyState and kbLeftCtrl) <> 0) and
          ((Ev.KeyDown.ControlKeyState and kbRightAlt) <> 0) and
          (Ev.KeyDown.TextLength = 0) then
    { Whether the right Alt key is AltGr depends on the keyboard layout, but AltGr certainly adds the
      left Ctrl flag. If both are set and no text is produced, the whole event is discarded, as AltGr
      must not be handled as Ctrl+Alt. }
    Ev.KeyDown.KeyCode := kbNoKey
  else if ((Ev.KeyDown.ControlKeyState and kbCtrlShift) <> 0) and
          ((Ev.KeyDown.ControlKeyState and kbAltShift) <> 0) and
          (Ev.KeyDown.TextLength <> 0) then
    { Ctrl+Alt that produces text is AltGr: the Ctrl and Alt modifiers are dropped. }
    Ev.KeyDown.ControlKeyState := Ev.KeyDown.ControlKeyState and ($FFFF xor (kbCtrlShift or kbAltShift))
  else if ScanCode < 89 then
  begin
    { Convert NT style virtual scan codes to PC BIOS codes. }
    Index := Byte(ScanCode);
    KeyCode := 0;
    if ((Ev.KeyDown.ControlKeyState and kbAltShift) <> 0) and (AltCvt[Index] <> 0) then
      KeyCode := AltCvt[Index]
    else if ((Ev.KeyDown.ControlKeyState and kbCtrlShift) <> 0) and (CtrlCvt[Index] <> 0) then
      KeyCode := CtrlCvt[Index]
    else if ((Ev.KeyDown.ControlKeyState and kbShift) <> 0) and (ShiftCvt[Index] <> 0) then
      KeyCode := ShiftCvt[Index]
    else if ((Ev.KeyDown.ControlKeyState and (kbShift or kbCtrlShift or kbAltShift)) = 0) and
            (NormalCvt[Index] <> 0) then
      KeyCode := NormalCvt[Index];

    if KeyCode <> 0 then
    begin
      Ev.KeyDown.KeyCode := KeyCode;
      if Ev.KeyDown.CharScan.CharCode < Ord(' ') then
        Ev.KeyDown.TextLength := 0
      else if (Ev.KeyDown.CharScan.CharCode < $7F) and (Ev.KeyDown.TextLength = 0) then
      begin
        Ev.KeyDown.Text[0] := Ev.KeyDown.CharScan.CharCode;
        Ev.KeyDown.TextLength := 1;
      end;
    end;
  end;

  Result := (Ev.KeyDown.KeyCode <> kbNoKey) or (Ev.KeyDown.TextLength <> 0);
end;

procedure GetWin32Mouse(X, Y: SmallInt; ButtonState, ControlKeyState, EventFlags: Cardinal; var Ev: TEvent;
  var State: TInputState);
var
  Positive: Boolean;
begin
  Ev.What := evMouse;
  Ev.Mouse.Where.X := X;
  Ev.Mouse.Where.Y := Y;
  State.Buttons := Byte(ButtonState);
  Ev.Mouse.Buttons := State.Buttons;
  Ev.Mouse.EventFlags := Word(EventFlags);
  Ev.Mouse.ControlKeyState := Word(ControlKeyState and
    (kbShift or kbCtrlShift or kbAltShift or kbScrollState or kbNumState or kbCapsState));

  { The rotation sense is the sign of the high word of the button state. }
  Positive := (ButtonState and $80000000) = 0;
  if (EventFlags and MOUSE_WHEELED) <> 0 then
  begin
    if Positive then
      Ev.Mouse.Wheel := mwUp
    else
      Ev.Mouse.Wheel := mwDown;
  end
  else if (EventFlags and MOUSE_HWHEELED) <> 0 then
  begin
    if Positive then
      Ev.Mouse.Wheel := mwRight
    else
      Ev.Mouse.Wheel := mwLeft;
  end
  else
    Ev.Mouse.Wheel := 0;
end;

function KeyCodeOfVirtualKey(VirtualKey: Byte): Word;
var
  I: Integer;
begin
  Result := 0;
  for I := Low(VirtualKeyTable) to High(VirtualKeyTable) do
    if VirtualKeyTable[I].VirtualKey = VirtualKey then
    begin
      Result := VirtualKeyTable[I].KeyCode;
      Exit;
    end;
end;

procedure RegenerateMissingScanCodeFromVirtualKeyCode(VirtualKey: Word; var ScanCode: Word;
  var UnicodeChar: Cardinal; ControlKeyState: Cardinal);
var
  KeyCode: Word;
begin
  KeyCode := KeyCodeOfVirtualKey(Byte(VirtualKey));
  if KeyCode <> 0 then
  begin
    ScanCode := KeyCode shr 8;
    { Overwrite the UnicodeChar unless it is expected to be non-null and it already is. }
    if (UnicodeChar = 0) or ((KeyCode and $FF) = 0) then
      UnicodeChar := KeyCode and $FF;

    { If the Ctrl or Alt modifiers are present, the event is not meant to produce text, so the
      UnicodeChar is cleared. AltGr is not expected to be reported as Ctrl+Alt here. }
    if ((ControlKeyState and (kbCtrlShift or kbAltShift)) <> 0) and
       (Ord(' ') <= UnicodeChar) and ($7F <> UnicodeChar) then
      UnicodeChar := 0;
  end;
end;

{ Control sequences of the terminal }

procedure MouseOn(Writer: TTextProc);
begin
  Writer(
    #27'[?1001s' + { Save old highlight mouse reporting. }
    #27'[?1000h' + { Enable mouse reporting. }
    #27'[?1002h' + { Enable mouse drag reporting. }
    #27'[?1006h'   { Enable SGR extended mouse reporting. }
  );
end;

procedure MouseOff(Writer: TTextProc);
begin
  Writer(
    #27'[?1006l' + { Disable SGR extended mouse reporting. }
    #27'[?1002l' + { Disable mouse drag reporting. }
    #27'[?1000l' + { Disable mouse reporting. }
    #27'[?1001r'   { Restore old highlight mouse reporting. }
  );
end;

function KeyModsOnSequence(HasTerm: Boolean; const Term: string): string;
begin
  Result :=
    #27'[?1036s' + { Save metaSendsEscape (XTerm). }
    #27'[?1036h' + { Enable metaSendsEscape (XTerm). }
    #27'[?2004s' + { Save bracketed paste. }
    #27'[?2004h' + { Enable bracketed paste. }
    #27'[>4;1m' +  { Enable modifyOtherKeys (XTerm). }
    #27'[>5u' +    { Disambiguate escape codes (1) + Report alternate keys (4) (Kitty). }
    #27'[?9001h' + { Enable win32-input-mode (Conpty). }
    Far2lEnableSeq; { Enable far2l terminal extensions. }

  if HasTerm then
  begin
    { Check for full OSC 52 clipboard support. }
    if (Pos('alacritty', Term) > 0) or (Pos('foot', Term) > 0) then
      { Request the clipboard contents to see if they are readable. It is not safe to print this
        blindly, so it is done only for the terminals that are known to work. }
      Result := Result + #27']52;;?'#7
    else
      Result := Result +
        { Check for the 'kitty-query-clipboard_control' capability (XTGETTCAP). }
        #27'P+q6b697474792d71756572792d636c6970626f6172645f636f6e74726f6c'#27'\' +
        { Check for 'allowWindowOps' (XTQALLOWED). }
        #27']60'#27'\';
  end;

  { Some terminals do not recognize the sequences above and will display them on screen. Clear the
    screen to prevent this. }
  Result := Result + #27'[2J';
end;

procedure KeyModsOn(Writer: TTextProc);
var
  I: Integer;
  Entry: string;
  HasTerm: Boolean;
  Term: string;
begin
  HasTerm := False;
  Term := '';
  for I := 1 to GetEnvironmentVariableCount do
  begin
    Entry := GetEnvironmentString(I);
    if Copy(Entry, 1, 5) = 'TERM=' then
    begin
      HasTerm := True;
      Term := Copy(Entry, 6, Length(Entry));
      Break;
    end;
  end;
  Writer(KeyModsOnSequence(HasTerm, Term));
end;

procedure KeyModsOff(Writer: TTextProc);
begin
  Writer(
    Far2lDisableSeq +
    #27'[?9001l' + { Disable win32-input-mode (Conpty). }
    #27'[<u' +     { Restore previous keyboard mode (Kitty). }
    #27'[>4m' +    { Reset modifyOtherKeys (XTerm). }
    #27'[?2004l' + { Disable bracketed paste. }
    #27'[?2004r' + { Restore bracketed paste. }
    #27'[?1036r'   { Restore metaSendsEscape (XTerm). }
  );
end;

procedure NormalizeKey(var KeyDown: TKeyDownEvent);
var
  TKeyValue: TKey;
  NewMods, OrigMods, KeyCode: Word;
begin
  TKeyValue := KeyDown.ToKey;
  NewMods := TKeyValue.Mods and (kbShift or kbLeftCtrl or kbLeftAlt);
  if NewMods <> 0 then
  begin
    KeyCode := GetModdedKeyCode(TKeyValue.Code, NewMods);
    if KeyCode <> 0 then
    begin
      KeyDown.KeyCode := KeyCode;
      if KeyDown.CharScan.CharCode < Ord(' ') then
        KeyDown.TextLength := 0;
    end;
  end;
  { TKey does not distinguish left/right modifiers, so those are preserved when available. }
  OrigMods := KeyDown.ControlKeyState;
  KeyDown.ControlKeyState := (OrigMods or NewMods) and ($FFFF xor (kbCtrlShift or kbAltShift));
  if (OrigMods and kbCtrlShift) <> 0 then
    KeyDown.ControlKeyState := KeyDown.ControlKeyState or (OrigMods and kbCtrlShift)
  else
    KeyDown.ControlKeyState := KeyDown.ControlKeyState or (NewMods and kbCtrlShift);
  if (OrigMods and kbAltShift) <> 0 then
    KeyDown.ControlKeyState := KeyDown.ControlKeyState or (OrigMods and kbAltShift)
  else
    KeyDown.ControlKeyState := KeyDown.ControlKeyState or (NewMods and kbAltShift);
end;

function ParseEvent(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
begin
  if Buf.Get = 27 then
    Result := ParseEscapeSeq(Buf, Ev, State)
  else
    Result := Rejected;
end;

{ Pre: ESC has just been read. }
function ParseEscapeSeq(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
var
  Csi: TCSIData;
begin
  Result := Rejected;
  case Buf.Get of
    Ord('_'):
      begin
        if Buf.ReadStr('f2l') then
        begin
          Result := ParseFar2lInput(Buf, Ev, State);
          Exit;
        end;
        if Buf.ReadStr('far2l') then
        begin
          Result := ParseFar2lAnswer(Buf, Ev, State);
          Exit;
        end;
      end;
    Ord('['):
      case Buf.Get of
        { Mouse events are usually detected by the curses layer of the C++ library. }
        Ord('M'):
          if ParseX10Mouse(Buf, Ev, State) = Accepted then
            Result := Accepted
          else
            Result := Ignored;
        Ord('<'):
          if ParseSGRMouse(Buf, Ev, State) = Accepted then
            Result := Accepted
          else
            Result := Ignored;
      else
        begin
          Buf.Unget;
          Csi := Default(TCSIData);
          if Csi.ReadFrom(Buf) then
            case Csi.Terminator of
              'u': Result := ParseKittyKey(Csi, Ev);
              'R': Result := ParseCPR(Csi, State);
              '_': Result := ParseWin32InputModeKeyOrEscapeSeq(Csi, Buf.In_, Ev, State);
            else
              Result := ParseCSIKey(Csi, Ev, State);
            end;
        end;
      end;
    Ord('O'): Result := ParseSS3Key(Buf, Ev);
    Ord('P'): Result := ParseDCS(Buf, State);
    Ord(']'): Result := ParseOSC(Buf, State);
    27:
      begin
        Result := ParseEscapeSeq(Buf, Ev, State);
        if (Result = Accepted) and (Ev.What = evKeyDown) then
        begin
          Ev.KeyDown.ControlKeyState := Ev.KeyDown.ControlKeyState or kbLeftAlt;
          NormalizeKey(Ev.KeyDown);
        end;
      end;
  end;
end;

{ Pre: ESC [ M has just been read.
  The complete sequence is ESC [ M a b c, where a is the button number plus 32, b is the column
  number (one-based) plus 32, and c is the row number (one-based) plus 32. }
function ParseX10Mouse(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
var
  Butm, Mods, But: Cardinal;
  Coords: array[0..1] of Integer;
  Idx, C: Integer;
begin
  Butm := Cardinal(Buf.Get);
  Mods := Butm and (mmAlt or mmCtrl);
  But := (Butm and (High(Cardinal) xor (mmAlt or mmCtrl))) - 32;
  if 255 - 32 < But then
  begin
    Result := Rejected;
    Exit;
  end;
  for Idx := 0 to 1 do
  begin
    C := Buf.Get;
    if (C < 0) or (255 < C) then
    begin
      Result := Rejected;
      Exit;
    end;
    { In theory, this encoding only supports coordinates in the range [0, 222]. However, some terminal
      emulators keep increasing the counters, causing an overflow. This can be used to support more
      coordinates, but the sequence must not be rejected, as that causes Ctrl+key events to be
      generated. }
    if C > 32 then
      C := C - 32
    else
      C := C + (256 - 32);
    { Make it zero-based. }
    Coords[Idx] := C - 1;
  end;

  Ev.What := evMouse;
  Ev.Mouse := Default(TMouseEventType);
  Ev.Mouse.Where.X := Coords[0];
  Ev.Mouse.Where.Y := Coords[1];
  if (Mods and mmAlt) <> 0 then
    Ev.Mouse.ControlKeyState := Ev.Mouse.ControlKeyState or kbLeftAlt;
  if (Mods and mmCtrl) <> 0 then
    Ev.Mouse.ControlKeyState := Ev.Mouse.ControlKeyState or kbLeftCtrl;
  case But of
    0, 32: State.Buttons := State.Buttons or mbLeftButton; { Press, drag. }
    1, 33: State.Buttons := State.Buttons or mbMiddleButton;
    2, 34: State.Buttons := State.Buttons or mbRightButton;
    3: State.Buttons := 0; { Release. }
    64: Ev.Mouse.Wheel := mwUp;
    65: Ev.Mouse.Wheel := mwDown;
    66: Ev.Mouse.Wheel := mwLeft;
    67: Ev.Mouse.Wheel := mwRight;
  end;
  Ev.Mouse.Buttons := State.Buttons;
  Result := Accepted;
end;

{ Pre: ESC [ < has just been read.
  The complete sequence is ESC [ < a ; b ; c M or ESC [ < a ; b ; c m, where a is the button number,
  b is the column number (one-based) and c is the row number (one-based), all in decimal.
  The sequence ends with M on button press and with m on button release. }
function ParseSGRMouse(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
var
  Butm, Mods, But, Kind: Cardinal;
  Col, Row: Integer;
begin
  Result := Rejected;
  if not Buf.GetNum(Butm) then
    Exit;
  Mods := Butm and (mmAlt or mmCtrl);
  But := Butm and (High(Cardinal) xor (mmAlt or mmCtrl));
  { Some terminals may emit negative coordinates. }
  if not Buf.GetInt(Col) then
    Exit;
  if not Buf.GetInt(Row) then
    Exit;
  { Make the coordinates zero-based. }
  if Row < 1 then
    Row := 1;
  if Col < 1 then
    Col := 1;
  Dec(Row);
  Dec(Col);
  { Finally, the press/release state. }
  Kind := Cardinal(Buf.Last);
  if (Kind <> Ord('M')) and (Kind <> Ord('m')) then
    Exit;

  Ev.What := evMouse;
  Ev.Mouse := Default(TMouseEventType);
  Ev.Mouse.Where.X := Col;
  Ev.Mouse.Where.Y := Row;
  if (Mods and mmAlt) <> 0 then
    Ev.Mouse.ControlKeyState := Ev.Mouse.ControlKeyState or kbLeftAlt;
  if (Mods and mmCtrl) <> 0 then
    Ev.Mouse.ControlKeyState := Ev.Mouse.ControlKeyState or kbLeftCtrl;
  if Kind = Ord('M') then
  begin
    { Press, wheel or drag. }
    case But of
      0, 32: State.Buttons := State.Buttons or mbLeftButton;
      1, 33: State.Buttons := State.Buttons or mbMiddleButton;
      2, 34: State.Buttons := State.Buttons or mbRightButton;
      64: Ev.Mouse.Wheel := mwUp;
      65: Ev.Mouse.Wheel := mwDown;
      66: Ev.Mouse.Wheel := mwLeft;
      67: Ev.Mouse.Wheel := mwRight;
    end;
  end
  else
  begin
    { Release. }
    case But of
      0: State.Buttons := State.Buttons and (High(Byte) xor mbLeftButton);
      1: State.Buttons := State.Buttons and (High(Byte) xor mbMiddleButton);
      2: State.Buttons := State.Buttons and (High(Byte) xor mbRightButton);
    end;
  end;
  Ev.Mouse.Buttons := State.Buttons;
  Result := Accepted;
end;

{ Parses a few sequences that terminals emit although they do not match their terminal database
  entries, for example Shift F1-4 on Konsole and F1-4 on Putty. }
function ParseCSIKey(const Csi: TCSIData; var Ev: TEvent; var State: TInputState): TParseResult;
var
  Terminator, Mods, Key: Cardinal;
  KeyCode: Word;
begin
  Terminator := Ord(Csi.Terminator);
  if (Csi.Length = 1) and (Terminator = Ord('~')) then
  begin
    case Csi.GetValue(0) of
      1: Ev.KeyDown := MakeKeyDown(kbHome, 0);
      2: Ev.KeyDown := MakeKeyDown(kbIns, 0);
      3: Ev.KeyDown := MakeKeyDown(kbDel, 0);
      4: Ev.KeyDown := MakeKeyDown(kbEnd, 0);
      5: Ev.KeyDown := MakeKeyDown(kbPgUp, 0);
      6: Ev.KeyDown := MakeKeyDown(kbPgDn, 0);
      { These numbers can be interpreted in different ways, for example as F1-F12 instead of F1-F10.
        But this fallback is triggered by Putty, which uses F1-F10. }
      11: Ev.KeyDown := MakeKeyDown(kbF1, 0);
      12: Ev.KeyDown := MakeKeyDown(kbF2, 0);
      13: Ev.KeyDown := MakeKeyDown(kbF3, 0);
      14: Ev.KeyDown := MakeKeyDown(kbF4, 0);
      15: Ev.KeyDown := MakeKeyDown(kbF5, 0);
      17: Ev.KeyDown := MakeKeyDown(kbF6, 0);
      18: Ev.KeyDown := MakeKeyDown(kbF7, 0);
      19: Ev.KeyDown := MakeKeyDown(kbF8, 0);
      20: Ev.KeyDown := MakeKeyDown(kbF9, 0);
      21: Ev.KeyDown := MakeKeyDown(kbF10, 0);
      23: Ev.KeyDown := MakeKeyDown(kbShiftF1, kbShift);
      24: Ev.KeyDown := MakeKeyDown(kbShiftF2, kbShift);
      25: Ev.KeyDown := MakeKeyDown(kbShiftF3, kbShift);
      26: Ev.KeyDown := MakeKeyDown(kbShiftF4, kbShift);
      28: Ev.KeyDown := MakeKeyDown(kbShiftF5, kbShift);
      29: Ev.KeyDown := MakeKeyDown(kbShiftF6, kbShift);
      31: Ev.KeyDown := MakeKeyDown(kbShiftF7, kbShift);
      32: Ev.KeyDown := MakeKeyDown(kbShiftF8, kbShift);
      33: Ev.KeyDown := MakeKeyDown(kbShiftF9, kbShift);
      34: Ev.KeyDown := MakeKeyDown(kbShiftF10, kbShift);
      200:
        begin
          State.BracketedPaste := True;
          Result := Ignored;
          Exit;
        end;
      201:
        begin
          State.BracketedPaste := False;
          Result := Ignored;
          Exit;
        end;
    else
      Result := Rejected;
      Exit;
    end;
  end
  else if (Csi.Length = 1) and (Csi.GetValue(0) = 1) then
  begin
    if not KeyFromLetter(Terminator, XTermModDefault, Ev.KeyDown) then
    begin
      Result := Rejected;
      Exit;
    end;
  end
  else if (Csi.Length = 2) and (Csi.GetSeparator(0) = ';') then
  begin
    Mods := Csi.GetValue(1);
    if Csi.GetValue(0) = 1 then
    begin
      if not KeyFromLetter(Terminator, Mods, Ev.KeyDown) then
      begin
        Result := Rejected;
        Exit;
      end;
    end
    else if Terminator = Ord('~') then
    begin
      KeyCode := 0;
      case Csi.GetValue(0) of
        2: KeyCode := kbIns;
        3: KeyCode := kbDel;
        5: KeyCode := kbPgUp;
        6: KeyCode := kbPgDn;
        11: KeyCode := kbF1;
        12: KeyCode := kbF2;
        13: KeyCode := kbF3;
        14: KeyCode := kbF4;
        15: KeyCode := kbF5;
        17: KeyCode := kbF6;
        18: KeyCode := kbF7;
        19: KeyCode := kbF8;
        20: KeyCode := kbF9;
        21: KeyCode := kbF10;
        23: KeyCode := kbF11;
        24: KeyCode := kbF12;
        29: KeyCode := kbNoKey; { Menu key (XTerm). }
      else
        Result := Rejected;
        Exit;
      end;
      Ev.KeyDown := KeyWithXTermMods(KeyCode, Csi.GetValue(1));
    end
    else
    begin
      Result := Rejected;
      Exit;
    end;
  end
  else if (Csi.Length = 3) and (Csi.GetValue(0) = 27) and (Csi.GetSeparator(0) = ';') and
          (Csi.GetSeparator(1) = ';') and (Terminator = Ord('~')) then
  begin
    { The "modifyOtherKeys" mode of XTerm. }
    Key := Csi.GetValue(2);
    Mods := Csi.GetValue(1);
    if not KeyFromCodepoint(Key, Mods, Ev.KeyDown) then
    begin
      Result := Ignored;
      Exit;
    end;
  end
  else
  begin
    Result := Rejected;
    Exit;
  end;
  Ev.What := evKeyDown;
  Result := Accepted;
end;

{ Pre: ESC O has just been read. Konsole, IntelliJ. }
function ParseSS3Key(var Buf: TGetChBuf; var Ev: TEvent): TParseResult;
var
  Mods, Key: Cardinal;
begin
  Result := Rejected;
  if not Buf.GetNum(Mods) then
    Exit;
  Key := Cardinal(Buf.Last);
  if not KeyFromLetter(Key, Mods, Ev.KeyDown) then
    Exit;
  Ev.What := evKeyDown;
  Result := Accepted;
end;

function ParseKittyKey(const Csi: TCSIData; var Ev: TEvent): TParseResult;
var
  KittyKeyCode, KittyShiftedKeyCode, KittyBaseLayoutKey, KittyModifiers, KittyEventType, KittyText: Cardinal;
  Codepoint, I: Cardinal;
  UpperBaseLayoutKey: Word;
begin
  if (Csi.Length < 1) or (Csi.Terminator <> 'u') then
  begin
    Result := Rejected;
    Exit;
  end;

  { Not all the features of the keyboard protocol of Kitty are requested by KeyModsOn, yet they are
    supported here. The events have the form
      unicode-key-code : shifted-key-code : base-layout-key ; modifiers : event-type ; text-as-codepoints u
    where only the unicode-key-code is mandatory. }
  KittyShiftedKeyCode := 0;
  KittyBaseLayoutKey := 0;
  KittyModifiers := 1;
  KittyEventType := 1;
  KittyText := 0;

  I := 0;
  KittyKeyCode := Csi.GetValue(I, 0);
  Inc(I);
  if (I < Csi.Length) and (Csi.GetSeparator(I - 1) = ':') then
  begin
    KittyShiftedKeyCode := Csi.GetValue(I, 0);
    Inc(I);
  end;
  if (I < Csi.Length) and (Csi.GetSeparator(I - 1) = ':') then
  begin
    KittyBaseLayoutKey := Csi.GetValue(I, 0);
    Inc(I);
  end;
  if I < Csi.Length then
  begin
    KittyModifiers := Csi.GetValue(I, 1);
    Inc(I);
  end;
  if (I < Csi.Length) and (Csi.GetSeparator(I - 1) = ':') then
  begin
    KittyEventType := Csi.GetValue(I, 1);
    Inc(I);
  end;
  if I < Csi.Length then
  begin
    { There could be more than one character, but that is not supported: the first one is taken. }
    KittyText := Csi.GetValue(I, 0);
    Inc(I);
  end;

  if KittyEventType <> 1 then
  begin
    { Only Press events are of interest. }
    Result := Ignored;
    Exit;
  end;

  Codepoint := KittyKeyCode;
  if KittyText <> 0 then
    Codepoint := KittyText
  else if KittyShiftedKeyCode <> 0 then
    Codepoint := KittyShiftedKeyCode;

  if not KeyFromCodepoint(Codepoint, KittyModifiers, Ev.KeyDown) then
  begin
    Result := Ignored;
    Exit;
  end;

  { When the unicode-key-code is not an ASCII letter, but the base-layout-key is, and the Ctrl or Alt
    modifiers are present, the key code of the event is set as if it was Ctrl/Alt + A-Z, so that the
    standard keyboard shortcuts can still be triggered with a non-ASCII keyboard layout (for example,
    Ctrl plus the Russian letter at the place of A of the Latin layout matches Ctrl+A). }
  if not IsAsciiLetter(KittyKeyCode) and IsAsciiLetter(KittyBaseLayoutKey) and
     ((Ev.KeyDown.ControlKeyState and (kbCtrlShift or kbAltShift)) <> 0) then
  begin
    { The base-layout-key is always in lowercase. }
    UpperBaseLayoutKey := KittyBaseLayoutKey - Ord('a') + Ord('A');
    Ev.KeyDown.KeyCode := GetModdedKeyCode(UpperBaseLayoutKey, Ev.KeyDown.ControlKeyState);
    { The text of the event is still the original text of the key. }
  end;

  Ev.What := evKeyDown;
  Result := Accepted;
end;

{ Pre: ESC P has just been read. }
function ParseDCS(var Buf: TGetChBuf; var State: TInputState): TParseResult;
var
  S: string;
begin
  S := ReadUntilBelOrSt(Buf);
  { A DCS comes only as a response to the request for the capabilities of Kitty. }
  if Pos('726561642d636c6970626f617264', S) > 0 then { 'read-clipboard' }
    State.HasFullOsc52 := True;
  Result := Ignored;
end;

{ Pre: ESC ] has just been read. }
function ParseOSC(var Buf: TGetChBuf; var State: TInputState): TParseResult;
var
  S, Encoded: string;
  P, I: SizeInt;
begin
  S := ReadUntilBelOrSt(Buf);
  if (Length(S) > 3) and (Copy(S, 1, 3) = '52;') then { OSC 52 }
  begin
    P := 0;
    for I := 4 to Length(S) do
      if S[I] = ';' then
      begin
        P := I;
        Break;
      end;
    if P > 0 then
    begin
      if not State.HasFullOsc52 then
        { This is the response to the initial request. }
        State.HasFullOsc52 := True
      else if Assigned(State.PutPaste) then
      begin
        Encoded := Copy(S, P + 1, Length(S));
        State.PutPaste(DecodeBase64Text(Encoded));
      end;
    end;
  end
  else if (Length(S) > 3) and (Copy(S, 1, 3) = '60;') then { OSC 60 }
    if Pos('allowWindowOps', Copy(S, 4, Length(S))) > 0 then
      State.HasFullOsc52 := True;
  Result := Ignored;
end;

{ Pre: Csi.Terminator = 'R'. This is the Cursor Position Report, the response to the Device Status
  Report request of ConsumeUnprocessedInput. }
function ParseCPR(const Csi: TCSIData; var State: TInputState): TParseResult;
begin
  if (Csi.Length <> 2) or (Csi.GetSeparator(0) <> ';') then
  begin
    Result := Rejected;
    Exit;
  end;

  State.GotDsrResponse := True;
  Result := Ignored;
end;

function ParseWin32InputModeKey(const Csi: TCSIData; var Ev: TEvent; var State: TInputState): TParseResult;
var
  VirtualKey, ScanCode: Word;
  UnicodeChar, ControlKeyState: Cardinal;
  KeyDown: Boolean;
begin
  VirtualKey := Word(Csi.GetValue(0, 0));
  ScanCode := Word(Csi.GetValue(1, 0));
  UnicodeChar := Word(Csi.GetValue(2, 0));
  KeyDown := Word(Csi.GetValue(3, 0)) <> 0;
  ControlKeyState := Word(Csi.GetValue(4, 0));

  RegenerateMissingScanCodeFromVirtualKeyCode(VirtualKey, ScanCode, UnicodeChar, ControlKeyState);

  if KeyDown and GetWin32Key(VirtualKey, ScanCode, UnicodeChar, ControlKeyState, Ev, State) then
  begin
    NormalizeKey(Ev.KeyDown);
    Result := Accepted;
  end
  else
    Result := Ignored;
end;

type
  { A terminal may emit escape sequences wrapped in win32-input-mode events. This getter unwraps them. }
  TWin32InputModeUnwrapper = class(TInputGetter)
  private
    FIn: TInputGetter;
    FState: PInputState;
    UngetSize: Word;
    UngetBuffer: array[0..30] of SmallInt;
  public
    constructor Create(AIn: TInputGetter; AState: PInputState);
    function Get: Integer; override;
    procedure Unget(Key: Integer); override;
  end;

constructor TWin32InputModeUnwrapper.Create(AIn: TInputGetter; AState: PInputState);
begin
  inherited Create;
  FIn := AIn;
  FState := AState;
  UngetSize := 0;
end;

function TWin32InputModeUnwrapper.Get: Integer;
var
  Buf: TGetChBuf;
  Csi: TCSIData;
  Ev: TEvent;
begin
  if UngetSize > 0 then
  begin
    Dec(UngetSize);
    Result := UngetBuffer[UngetSize];
    Exit;
  end;

  Buf := TGetChBuf.Create(FIn);
  Csi := Default(TCSIData);
  FillChar(Ev, SizeOf(Ev), 0);
  { If a win32-input-mode event has no scan code and a single-byte character, just that character is taken. }
  if (Buf.Get = 27) and (Buf.Get = Ord('[')) and Csi.ReadFrom(Buf) and (Csi.Terminator = '_') and
     (ParseWin32InputModeKey(Csi, Ev, FState^) = Accepted) and
     (Ev.KeyDown.CharScan.ScanCode = 0) and (Ev.KeyDown.TextLength = 1) then
  begin
    Result := Ev.KeyDown.Text[0];
    Exit;
  end;
  Buf.Reject;
  Result := -1;
end;

procedure TWin32InputModeUnwrapper.Unget(Key: Integer);
begin
  { The original win32-input-mode event could be reconstructed and ungotten from the wrapped getter,
    but that is not needed. The characters returned by Get only have to be stored for a while. }
  if UngetSize < Length(UngetBuffer) then
  begin
    UngetBuffer[UngetSize] := Key;
    Inc(UngetSize);
  end;
end;

{ Pre: Csi.Terminator = '_'. }
function ParseWin32InputModeKeyOrEscapeSeq(const Csi: TCSIData; In_: TInputGetter; var Ev: TEvent;
  var State: TInputState): TParseResult;
var
  Unwrapper: TWin32InputModeUnwrapper;
  Buf: TGetChBuf;
begin
  Result := ParseWin32InputModeKey(Csi, Ev, State);
  if (Result = Accepted) and (Ev.KeyDown.ToKey = TKey.Create($001B)) then
  begin
    { This is the initiator of an escape sequence wrapped in win32-input-mode events. }
    Unwrapper := TWin32InputModeUnwrapper.Create(In_, @State);
    try
      Buf := TGetChBuf.Create(Unwrapper);
      Result := ParseEscapeSeq(Buf, Ev, State);
      { Rejected is not propagated, because a secondary buffer has been used. }
      if Result <> Accepted then
        Result := Ignored;
    finally
      Unwrapper.Free;
    end;
  end;
end;

function SetOsc52Clipboard(Writer: TTextProc; const Text: string; var State: TInputState): Boolean;
begin
  if Assigned(Base64Encode) then
    Writer(#27']52;;' + Base64Encode(Text) + #7);
  { The result is False without full OSC 52 support, even though the request is always made. This way
    the internal clipboard can still be used. }
  Result := State.HasFullOsc52;
end;

function RequestOsc52Clipboard(Writer: TTextProc; var State: TInputState): Boolean;
begin
  if State.HasFullOsc52 then
  begin
    Writer(#27']52;;?'#7);
    Result := True;
  end
  else
    Result := False;
end;

function SetClipboardText(Writer: TTextProc; const Text: string; var State: TInputState): Boolean;
begin
  Result := SetOsc52Clipboard(Writer, Text, State);
end;

function RequestClipboardText(Writer: TTextProc; Accept: TTextProc; var State: TInputState): Boolean;
begin
  State.PutPaste := Accept;
  Result := RequestOsc52Clipboard(Writer, State);
end;

function ReadUntilBelOrSt(var Buf: TGetChBuf): string;
var
  Prev, C, Zero: Integer;
begin
  Result := '';
  Prev := 0;
  C := Buf.GetUnbuffered;
  while C <> -1 do
  begin
    if C = 7 then { BEL }
      Break;
    if (C = Ord('\')) and (Prev = 27) then { ST }
    begin
      if Length(Result) > 0 then
        SetLength(Result, Length(Result) - 1);
      Break;
    end;
    Result := Result + Chr(C and $FF);
    Prev := C;
    C := Buf.GetUnbuffered;
  end;
  Zero := Pos(#0, Result);
  if Zero > 0 then
    SetLength(Result, Zero - 1);
end;

{ The terminal might have kept sending events while the application is exiting. This is especially
  likely when the application runs remotely across a slow connection and terminal extensions are in
  place which report key release events (far2l and win32-input-mode), or when the application gets
  killed by a signal while the user was dragging the mouse. Therefore a DSR request is written and events
  are read until its response comes. This has to be done after the keyboard and mouse extensions are
  disabled. }
procedure ConsumeUnprocessedInput(Writer: TTextProc; In_: TInputGetter; var State: TInputState);
var
  Ev: TEvent;
  Buf: TGetChBuf;
  Start: QWord;
begin
  Writer(#27'[6n'); { Device Status Report. }

  FillChar(Ev, SizeOf(Ev), 0);
  State.GotDsrResponse := False;
  Start := GetTickCount64;
  repeat
    Buf := TGetChBuf.Create(In_);
    ParseEvent(Buf, Ev, State);
  until State.GotDsrResponse or (GetTickCount64 - Start > 200);
end;

{ The far2l terminal extension }

{ Pre: ESC _ f2l has just been read. }
function ParseFar2lInput(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
const
  K = 32;
var
  S, Out_: string;
  C: Integer;
  VirtualKey, ScanCode: Word;
  UnicodeChar, ControlKeyState: Cardinal;
begin
  S := '';
  C := Buf.GetUnbuffered;
  while (C <> -1) and (C <> 7) do
  begin
    if Length(S) < 4 * K then
      S := S + Chr(C and $FF);
    C := Buf.GetUnbuffered;
  end;
  Out_ := DecodeBase64Text(S);
  if Length(Out_) > 0 then
  begin
    if (Out_[Length(Out_)] = 'K') and (Length(Out_) - 1 = 14) then
    begin
      VirtualKey := ReadLE16(Out_, 2);
      ScanCode := ReadLE16(Out_, 4);
      ControlKeyState := ReadLE32(Out_, 6);
      UnicodeChar := ReadLE32(Out_, 10);

      RegenerateMissingScanCodeFromVirtualKeyCode(VirtualKey, ScanCode, UnicodeChar, ControlKeyState);

      if GetWin32Key(VirtualKey, ScanCode, UnicodeChar, ControlKeyState, Ev, State) then
      begin
        NormalizeKey(Ev.KeyDown);
        Result := Accepted;
        Exit;
      end;
    end
    else if (Out_[Length(Out_)] = 'M') and (Length(Out_) - 1 = 16) then
    begin
      GetWin32Mouse(SmallInt(ReadLE16(Out_, 0)), SmallInt(ReadLE16(Out_, 2)), ReadLE32(Out_, 4),
        ReadLE32(Out_, 8), ReadLE32(Out_, 12), Ev, State);
      Result := Accepted;
      Exit;
    end;
  end;
  Result := Ignored;
end;

{ Pre: ESC _ far2l has just been read. }
function ParseFar2lAnswer(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
var
  Encoded, Decoded, Text: string;
  DataSize: Cardinal;
begin
  Result := Ignored;
  Encoded := ReadUntilBelOrSt(Buf);
  if Encoded = 'ok' then
    State.Far2l.Enabled := True
  else
  begin
    Decoded := DecodeBase64Text(Encoded);
    if (Length(Decoded) >= 5) and (Decoded[Length(Decoded)] = f2lClipGetData) and
       Assigned(State.PutPaste) then
    begin
      DataSize := ReadLE32(Decoded, Length(Decoded) - 5);
      if (DataSize < High(Cardinal) - 5) and (Length(Decoded) >= 5 + DataSize) then
      begin
        Text := Copy(Decoded, Length(Decoded) - 5 - DataSize + 1, DataSize);
        { Discard the null terminator. }
        if (DataSize > 0) and (Text[Length(Text)] = #0) then
          SetLength(Text, Length(Text) - 1);
        State.PutPaste(Text);
      end;
    end;
  end;
end;

end.
