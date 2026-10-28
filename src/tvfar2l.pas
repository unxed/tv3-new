{ The client side of the far2l terminal extensions, as the document VTExts.md specifies them: the stack encoding of
  requests, replies and events, the framing in APC strings, the typed requests and answers, the decoder of the
  incoming APC strings, and the detection of a server that speaks the extensions.

  The conversion of the key and mouse records into events of the library is done by TvEvents (Far2lToEvent calls its
  routines), and the clipboard requests that a program needs to paste and to copy text are in TvTermIo, whose Base64
  conversions this unit uses. Writing to the terminal is done through a procedure of object that is given, or through
  the ConsoleCtl of TvTermOs. }
unit TvFar2l;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvEvents, TvTermOs;

const
  { Features: the flags of the request x, and the features that a server reports in the answer of CLIP_OPEN. }
  FARTTY_FEAT_COMPACT_INPUT = $00000001;
  FARTTY_FEAT_TERMINAL_SIZE = 2;
  FARTTY_FEATCLIP_DATA_ID = $01;
  FARTTY_FEATCLIP_CHUNKED_SET = 1 shl 1;

  { Clipboard formats }
  CF_TEXT = 1;
  CF_UNICODETEXT = 13;
  CF_HTML = 15;

  { The control key state of the key and mouse records }
  RIGHT_ALT_PRESSED = $0001;
  LEFT_ALT_PRESSED = $0002;
  RIGHT_CTRL_PRESSED = $0004;
  LEFT_CTRL_PRESSED = $0008;
  SHIFT_PRESSED = $0010;
  NUMLOCK_ON = $0020;
  SCROLLLOCK_ON = $0040;
  CAPSLOCK_ON = $0080;
  ENHANCED_KEY = $0100;
  RIGHT_SHIFT_VSC = 54;

  { The event flags and the buttons of the mouse records }
  MOUSE_MOVED = $0001;
  DOUBLE_CLICK = $0002;
  FROM_LEFT_1ST_BUTTON_PRESSED = $0001;
  RIGHTMOST_BUTTON_PRESSED = $0002;
  FROM_LEFT_2ND_BUTTON_PRESSED = $0004;
  FROM_LEFT_3RD_BUTTON_PRESSED = $0008;
  FROM_LEFT_4TH_BUTTON_PRESSED = $0010;

  { Capabilities of the image requests. JPG is not a bit of its own: it is the two low bits together. }
  WP_IMGCAP_RGBA = $001;
  WP_IMGCAP_PNG = $002;
  WP_IMGCAP_JPG = WP_IMGCAP_RGBA or WP_IMGCAP_PNG;
  WP_IMGCAP_ATTACH = $100;
  WP_IMGCAP_SCROLL = $200;
  WP_IMGCAP_ROTMIR = $800;

  { Flags of IMAGE_SET: the format is a number in the low 16 bits and the attach mode a number in bits 16 to 18. }
  WP_IMG_RGBA = 0;
  WP_IMG_RGB = 1;
  WP_IMG_PNG = 2;
  WP_IMG_JPG = 3;
  WP_IMG_MASK_FMT = $00FFFF;
  WP_IMG_ATTACH_LEFT = 1 shl 16;
  WP_IMG_ATTACH_RIGHT = 2 shl 16;
  WP_IMG_ATTACH_TOP = 3 shl 16;
  WP_IMG_ATTACH_BOTTOM = 4 shl 16;
  WP_IMG_MASK_ATTACH = $070000;
  WP_IMG_SCROLL = $080000;
  WP_IMG_PIXEL_OFFSET = $100000;

  { Flags of IMAGE_TRANSFORM: the rotation is a number in the two low bits. }
  WP_IMGTF_ROTATE0 = 0;
  WP_IMGTF_ROTATE90 = 1;
  WP_IMGTF_ROTATE180 = 2;
  WP_IMGTF_ROTATE270 = 3;
  WP_IMGTF_MASK_ROTATE = $03;
  WP_IMGTF_MIRROR_H = $04;
  WP_IMGTF_MIRROR_V = $08;

  { The size of a piece of a chunked upload, and the number of pieces after which one of them asks for an answer. }
  ClipChunkSize = $4000;
  ClipChunkAckEvery = 16;
  { The number of requests that may wait for an answer at once. }
  MaxRequestsInFlight = 255;
  { The longest body of an APC string that the decoder keeps. }
  DefaultBodyLimit = 16 * 1024 * 1024;

type
  { The stack of the serializer: a byte array, pushed to and popped from its end. Integers are little-endian. A pop
    from a stack that is too short sets Failed, takes nothing and gives 0 or an empty text. }
  TF2lStack = class
  private
    FBytes: AnsiString;
    FFailed: Boolean;
  public
    procedure Load(const Serialized: AnsiString);
    { The array from its bottom to its top. }
    function Serialized: AnsiString;
    function Size: SizeInt;
    procedure PutRaw(const Data: AnsiString);
    procedure PutNumber(Value: QWord; Width: Integer);
    procedure PutSigned(Value: Int64; Width: Integer);
    { The bytes, then their count as four bytes. }
    procedure PutString(const Text: AnsiString);
    function PopRaw(Count: QWord): AnsiString;
    function PopNumber(Width: Integer): QWord;
    function PopSigned(Width: Integer): Int64;
    function PopString: AnsiString;
    property Failed: Boolean read FFailed;
  end;

  { How a string of the client ends: BEL or ST (ESC \). }
  TF2lTerminator = (tmBel, tmSt);

  { The requests of the client. The clipboard and image requests come after the others, in the order of their
    sub-command letters. }
  TF2lRequestKind = (
    rqFeatures, rqQuickEdit, rqMaximize, rqRestore, rqCursorHeight, rqMaxSize, rqNotify, rqFKeyTitles, rqPalette,
    rqClipOpen, rqClipClose, rqClipEmpty, rqClipIsAvail, rqClipChunk, rqClipSetData, rqClipGetData,
    rqClipGetDataId, rqClipRegister,
    rqImageCaps, rqImageSet, rqImageTransform, rqImageDelete);

  { A request with its arguments. Which fields a kind uses:
      rqFeatures: Flags. rqCursorHeight: Value (percent). rqNotify: Name (title), Body (text).
      rqFKeyTitles: TitleCount entries, Titles, TitleMask (bit n set: key n+1 has a title).
      rqClipOpen, rqClipRegister: Name. rqClipIsAvail, rqClipGetData, rqClipGetDataId: Value (format).
      rqClipChunk: Value (the size of the piece divided by 256), Body. rqClipSetData: Value (format), Body.
      rqImageSet: Name, Flags, Edges (left, top, right, bottom), PixelWidth, PixelHeight, Body.
      rqImageTransform: Name, Edges, Transform. rqImageDelete: Name. }
  TF2lRequest = record
    Kind: TF2lRequestKind;
    Flags: QWord;
    Value, PixelWidth, PixelHeight: Cardinal;
    Name, Body: AnsiString;
    Transform, TitleMask: Word;
    TitleCount: Integer;
    Edges: array[0..3] of SmallInt;
    Titles: array[0..11] of AnsiString;
  end;

  { The values of an answer, as far as the kind of the request has them:
      Valid: the stack of the reply could be read. Flag: a success flag or an availability.
      Status: the int8 status of the clipboard requests (1 success, 0 failure, -1 not open).
      Number: a format, or the size of data. Wide: features, a data identifier or capabilities.
      Height, Width: the largest window, or the cell size in pixels. Bits: the color depth.
      Data: the data of CLIP_GETDATA. }
  TF2lAnswer = record
    Kind: TF2lRequestKind;
    Valid, Flag: Boolean;
    Id, Bits: Byte;
    Height, Width: SmallInt;
    Wide: QWord;
    Number: Cardinal;
    Data: AnsiString;
    Status: ShortInt;
  end;

  { One entry of the table of the IDs in flight. }
  TF2lSlot = record
    Busy: Boolean;
    Kind: TF2lRequestKind;
  end;

  TF2lEventKind = (feKey, feMouse, feTerminalSize, feUnknown);

  { An event of the server. For a key event Character, ControlKeyState, ScanCode, VirtualKey and RepeatCount are the
    fields of a key record (ScanCode is 0 and RepeatCount is 1 in a compact event). For a mouse event EventFlags,
    ControlKeyState, ButtonState (decoded from the compact form), MouseX and MouseY are those of a mouse record. }
  TF2lEvent = record
    Kind: TF2lEventKind;
    Code: AnsiChar;
    Compact: Boolean;
    Pressed: Boolean;
    Character: Cardinal;
    ControlKeyState: Cardinal;
    ScanCode, VirtualKey, RepeatCount: Word;
    EventFlags, ButtonState: Cardinal;
    MouseX, MouseY: SmallInt;
    Rows, Columns: Word;
  end;

  TF2lDecodeResult = (drDecoded, drUnknown, drDropped, drMalformed);

  { What the decoder found in the input. A bad reply and a bad event are those that throw out of the parser of the
    reference client (no ID, no event code, a truncated size event); a dropped event is a broken key or mouse event. }
  TF2lItemKind = (ikAck, ikReply, ikEvent, ikBadReply, ikBadEvent, ikDropped, ikUnknownEvent, ikOtherApc);

  TF2lItem = record
    Kind: TF2lItemKind;
    ReplyId: Byte;
    ReplyBody: AnsiString;
    Event: TF2lEvent;
  end;

  TF2lPlainProc = procedure(const Data: AnsiString) of object;

  { Takes the input bytes of the terminal, in pieces of any size, and finds the APC strings of the extension in them.
    The other bytes pass through, in order: to OnPlain when it is set, otherwise into a buffer that TakePlain empties. }
  TF2lDecoder = class
  private
    FPhase: Integer;
    FBody: AnsiString;
    FBodyUsed: SizeInt;
    FOverflow: Boolean;
    FLimit: SizeInt;
    FSkipped: Integer;
    FItems: array of TF2lItem;
    FHead: SizeInt;
    FPlain: AnsiString;
    FPlainUsed: SizeInt;
    FOnPlain: TF2lPlainProc;
    procedure PutPlain(const Data: AnsiString);
    procedure AfterEsc(B: Byte);
    procedure StoreBody(B: Byte);
    procedure DropBody;
    procedure Complete;
    procedure Enqueue(const Itm: TF2lItem);
    procedure ReadReply(const Encoded: AnsiString; var Itm: TF2lItem);
  public
    constructor Create;
    procedure Reset;
    procedure FeedByte(B: Byte);
    procedure Feed(const Data: AnsiString);
    function Next(out Item: TF2lItem): Boolean;
    function Pending: SizeInt;
    function TakePlain: AnsiString;
    property BodyLimit: SizeInt read FLimit write FLimit;
    { The strings that were thrown away: too long, or cut off by another escape sequence. }
    property Skipped: Integer read FSkipped;
    property OnPlain: TF2lPlainProc read FOnPlain write FOnPlain;
  end;

  TF2lSendProc = procedure(const Data: AnsiString) of object;
  TF2lAnswerProc = procedure(const Answer: TF2lAnswer) of object;
  TF2lEventProc = procedure(const Event: TF2lEvent) of object;

  { Writes to the console of TvTermOs. }
  TF2lConsoleSender = class
  private
    FCon: ConsoleCtl;
  public
    constructor Create(ACon: ConsoleCtl);
    procedure Send(const Data: AnsiString);
  end;

  TF2lProbeState = (ppIdle, ppWaiting, ppDone);

  { The client: sends the requests through the given procedure, keeps the IDs that wait for answers, and decodes
    what Feed is given. Answers and events go to OnAnswer and OnEvent. A request is sent whether or not the server was
    found to be there; the caller decides. }
  TFar2lClient = class
  private
    FSlots: array[1..255] of TF2lSlot;
    FWindow, FPlainOut: AnsiString;
    FAcked, FSupported: Boolean;
    FCounter: Byte;
    FServerClip: QWord;
    FPlainUsed: SizeInt;
    FProbe: TF2lProbeState;
    FTerm: TF2lTerminator;
    FDecoder: TF2lDecoder;
    FOwned: TF2lConsoleSender;
    FSend: TF2lSendProc;
    FOnAnswer: TF2lAnswerProc;
    FOnEvent: TF2lEventProc;
    procedure Emit(const Data: AnsiString);
    function TakeId(out Id: Byte): Boolean;
    procedure HandlePlain(const Data: AnsiString);
    procedure HandleItem(const Itm: TF2lItem);
    procedure HandleReply(const Itm: TF2lItem);
    procedure Deliver(const Ans: TF2lAnswer);
    procedure FailAll;
    procedure ForgetAll;
  public
    { The replies whose ID was not waiting. }
    Strays: Integer;
    constructor Create(ASend: TF2lSendProc);
    constructor CreateForConsole(Con: ConsoleCtl);
    destructor Destroy; override;
    { Writes the activation string and the status report that ends the probe. }
    procedure Probe;
    { Writes the activation string alone; the server answers every time. }
    procedure Announce;
    procedure ProbeTimedOut;
    procedure Deactivate;
    procedure SendHostIdentity(const Identity: AnsiString);
    procedure Feed(const Data: AnsiString);
    { The bytes that were not strings of the extension. }
    function TakePlain: AnsiString;
    { Sends a request. With WantReply a free ID is taken and given back, and the request waits for its answer; without
      it the ID is 0. False when no ID is free (nothing is sent). }
    function Submit(const Req: TF2lRequest; WantReply: Boolean; out Id: Byte): Boolean;
    { Sets the data of a format. When the server has reported the chunked upload and the data is longer than one
      piece, the pieces go first, and every ClipChunkAckEvery-th of them asks for an answer. Id is that of the
      CLIP_SETDATA. }
    function PutClipboardData(Format: Cardinal; const Data: AnsiString; out Id: Byte): Boolean;
    function InFlightCount: Integer;
    function IsPending(Id: Byte): Boolean;
    function ProbeState: TF2lProbeState;
    function Acknowledged: Boolean;
    function ServerClipFeatures: QWord;
    function Decoder: TF2lDecoder;
    property Terminator: TF2lTerminator read FTerm write FTerm;
    { The result of the probe: the acknowledgement came before the answer to the status report. }
    property Supported: Boolean read FSupported;
    property OnAnswer: TF2lAnswerProc read FOnAnswer write FOnAnswer;
    property OnEvent: TF2lEventProc read FOnEvent write FOnEvent;
  end;

{ The strings of the framing. }
function ActivationText: AnsiString;
function DeactivationText(Term: TF2lTerminator = tmSt): AnsiString;
function StatusQueryText: AnsiString;
{ The text of the identity of the host, in which each control character is replaced by a space. }
function HostIdentityText(const Identity: AnsiString; Term: TF2lTerminator = tmBel): AnsiString;
{ A request body (the stack bytes) framed as a request string. }
function WrapRequest(const Body: AnsiString; Term: TF2lTerminator = tmSt): AnsiString;
{ The bytes that a payload of Base64 holds up to its first character that is not of the alphabet. }
function Far2lDecodePayload(const Text: AnsiString): AnsiString;
{ A client ID of the clipboard: 32 to 256 characters of 0-9, a-z, - and _. }
function ValidClientId(const Text: AnsiString): Boolean;
{ True when the capabilities say that JPEG is supported: both low bits are set. }
function ImageCapsHasJpeg(Caps: QWord): Boolean;

{ The constructors of the requests. }
function PlainRequest(Kind: TF2lRequestKind): TF2lRequest;
function RequestFeatures(Flags: QWord): TF2lRequest;
function RequestCursorHeight(Percent: Byte): TF2lRequest;
function RequestNotification(const Title, Text: AnsiString): TF2lRequest;
{ The entries of F1 on; the keys of Absent (bit n for the key n+1) are sent as having no title. }
function RequestFKeyTitles(const Titles: array of AnsiString; Absent: Word): TF2lRequest;
function RequestClipOpen(const ClientId: AnsiString): TF2lRequest;
function RequestClipFormat(Kind: TF2lRequestKind; Format: Cardinal): TF2lRequest;
function RequestClipRegister(const FormatName: AnsiString): TF2lRequest;
function RequestClipSetData(Format: Cardinal; const Data: AnsiString): TF2lRequest;
function RequestClipChunk(const Data: AnsiString): TF2lRequest;
function RequestImageSet(const ImageId: AnsiString; Flags: QWord; Left, Top, Right, Bottom: SmallInt;
  Width, Height: Cardinal; const Pixels: AnsiString): TF2lRequest;
function RequestImageTransform(const ImageId: AnsiString; Left, Top, Right, Bottom: SmallInt;
  Transform: Word): TF2lRequest;
function RequestImageDelete(const ImageId: AnsiString): TF2lRequest;

{ The stack bytes of a request: the arguments, the letters of the command and the ID on top. }
function EncodeRequest(const Req: TF2lRequest; Id: Byte): AnsiString;
{ Reads the stack of a reply (without its ID) as the answer to a request of Kind. ClipFeatures are the features that
  the server reported; the data identifiers are read only when it reported FARTTY_FEATCLIP_DATA_ID. The result is
  Ans.Valid. }
function DecodeAnswer(Kind: TF2lRequestKind; Id: Byte; const Body: AnsiString; ClipFeatures: QWord;
  out Ans: TF2lAnswer): Boolean;
{ Reads the stack of an event, which has the event code on top. }
function DecodeEvent(const Body: AnsiString; out Ev: TF2lEvent): TF2lDecodeResult;

{ Turns a key press or a mouse event into an event of the library by the conversions of TvEvents. False for a key
  release, for a terminal size and for an unknown event, and when the key gives no event. }
function Far2lToEvent(const Fe: TF2lEvent; var Ev: TEvent; var State: TInputState): Boolean;

implementation

uses
  TvTermIo;

const
  TopLetters = 'xeMmhwnfp';
  ClipLetters = 'oceaSsgir';
  ImageLetters = 'cstd';
  DsrReply: AnsiString = #27'[0n';
  NoStack = $FFFFFFFF;

  PhaseIdle = 0;
  PhaseEsc = 1;
  PhaseBody = 2;
  PhaseBodyEsc = 3;

{ Growing buffers }

procedure AppendText(var Buf: AnsiString; var Used: SizeInt; const Part: AnsiString);
var
  Need: SizeInt;
begin
  if Length(Part) = 0 then
    Exit;
  Need := Used + Length(Part);
  if Need > Length(Buf) then
    SetLength(Buf, Need + Need div 2 + 64);
  Move(Part[1], Buf[Used + 1], Length(Part));
  Used := Need;
end;

{ TF2lStack }

procedure TF2lStack.Load(const Serialized: AnsiString);
begin
  FBytes := Serialized;
  FFailed := False;
end;

function TF2lStack.Serialized: AnsiString;
begin
  Result := FBytes;
end;

function TF2lStack.Size: SizeInt;
begin
  Result := Length(FBytes);
end;

procedure TF2lStack.PutRaw(const Data: AnsiString);
begin
  FBytes := FBytes + Data;
end;

procedure TF2lStack.PutNumber(Value: QWord; Width: Integer);
var
  K: Integer;
  Piece: AnsiString;
begin
  SetLength(Piece, Width);
  for K := 1 to Width do
  begin
    Piece[K] := Chr(Byte(Value and $FF));
    Value := Value shr 8;
  end;
  FBytes := FBytes + Piece;
end;

procedure TF2lStack.PutSigned(Value: Int64; Width: Integer);
begin
  PutNumber(QWord(Value), Width);
end;

procedure TF2lStack.PutString(const Text: AnsiString);
begin
  PutRaw(Text);
  PutNumber(Length(Text), 4);
end;

function TF2lStack.PopRaw(Count: QWord): AnsiString;
var
  Total: SizeInt;
begin
  Total := Length(FBytes);
  if Count > QWord(Total) then
  begin
    FFailed := True;
    Result := '';
    Exit;
  end;
  Result := Copy(FBytes, Total - SizeInt(Count) + 1, SizeInt(Count));
  SetLength(FBytes, Total - SizeInt(Count));
end;

function TF2lStack.PopNumber(Width: Integer): QWord;
var
  Total, K: SizeInt;
begin
  Result := 0;
  Total := Length(FBytes);
  if Total < Width then
  begin
    FFailed := True;
    Exit;
  end;
  for K := Width - 1 downto 0 do
    Result := (Result shl 8) or QWord(Ord(FBytes[Total - Width + 1 + K]));
  SetLength(FBytes, Total - Width);
end;

function TF2lStack.PopSigned(Width: Integer): Int64;
var
  Raw: QWord;
begin
  Raw := PopNumber(Width);
  Result := Int64(Raw);
  if (Width < 8) and (Raw >= (QWord(1) shl (8 * Width - 1))) then
    Result := Result - (Int64(1) shl (8 * Width));
end;

function TF2lStack.PopString: AnsiString;
var
  Count: QWord;
begin
  Count := PopNumber(4);
  if FFailed then
  begin
    Result := '';
    Exit;
  end;
  Result := PopRaw(Count);
end;

{ The framing }

function ActivationText: AnsiString;
begin
  Result := #27'_far2l1' + #27'\';
end;

function TerminatorText(Term: TF2lTerminator): AnsiString;
begin
  if Term = tmBel then
    Result := #7
  else
    Result := #27'\';
end;

function DeactivationText(Term: TF2lTerminator): AnsiString;
begin
  Result := #27'_far2l0' + TerminatorText(Term);
end;

function StatusQueryText: AnsiString;
begin
  Result := #27'[5n';
end;

function HostIdentityText(const Identity: AnsiString; Term: TF2lTerminator): AnsiString;
var
  K: SizeInt;
  Clean: AnsiString;
begin
  Clean := Identity;
  for K := 1 to Length(Clean) do
    if (Clean[K] < ' ') or (Clean[K] = #127) then
      Clean[K] := ' ';
  Result := #27'_far2l#' + Clean + TerminatorText(Term);
end;

function WrapRequest(const Body: AnsiString; Term: TF2lTerminator): AnsiString;
begin
  Result := #27'_far2l:' + EncodeBase64(Body) + TerminatorText(Term);
end;

function InAlphabet(Ch: AnsiChar): Boolean;
begin
  Result := (Ch in ['A'..'Z', 'a'..'z', '0'..'9', '+', '/']);
end;

function Far2lDecodePayload(const Text: AnsiString): AnsiString;
var
  Stop: SizeInt;
begin
  Stop := 0;
  while (Stop < Length(Text)) and InAlphabet(Text[Stop + 1]) do
    Inc(Stop);
  Result := DecodeBase64(Copy(Text, 1, Stop));
end;

function ValidClientId(const Text: AnsiString): Boolean;
var
  K: SizeInt;
begin
  Result := (Length(Text) >= 32) and (Length(Text) <= 256);
  if not Result then
    Exit;
  for K := 1 to Length(Text) do
    if not (Text[K] in ['0'..'9', 'a'..'z', '-', '_']) then
    begin
      Result := False;
      Exit;
    end;
end;

function ImageCapsHasJpeg(Caps: QWord): Boolean;
begin
  Result := (Caps and WP_IMGCAP_JPG) = WP_IMGCAP_JPG;
end;

{ The requests }

function PlainRequest(Kind: TF2lRequestKind): TF2lRequest;
begin
  Result := Default(TF2lRequest);
  Result.Kind := Kind;
end;

function RequestFeatures(Flags: QWord): TF2lRequest;
begin
  Result := PlainRequest(rqFeatures);
  Result.Flags := Flags;
end;

function RequestCursorHeight(Percent: Byte): TF2lRequest;
begin
  Result := PlainRequest(rqCursorHeight);
  Result.Value := Percent;
end;

function RequestNotification(const Title, Text: AnsiString): TF2lRequest;
begin
  Result := PlainRequest(rqNotify);
  Result.Name := Title;
  Result.Body := Text;
end;

function RequestFKeyTitles(const Titles: array of AnsiString; Absent: Word): TF2lRequest;
var
  K, Count: Integer;
begin
  Result := PlainRequest(rqFKeyTitles);
  Count := Length(Titles);
  if Count > 12 then
    Count := 12;
  Result.TitleCount := Count;
  for K := 0 to Count - 1 do
  begin
    Result.Titles[K] := Titles[K];
    if ((Absent shr K) and 1) = 0 then
      Result.TitleMask := Result.TitleMask or Word(1 shl K);
  end;
end;

function RequestClipOpen(const ClientId: AnsiString): TF2lRequest;
begin
  Result := PlainRequest(rqClipOpen);
  Result.Name := ClientId;
end;

function RequestClipFormat(Kind: TF2lRequestKind; Format: Cardinal): TF2lRequest;
begin
  Result := PlainRequest(Kind);
  Result.Value := Format;
end;

function RequestClipRegister(const FormatName: AnsiString): TF2lRequest;
begin
  Result := PlainRequest(rqClipRegister);
  Result.Name := FormatName;
end;

function RequestClipSetData(Format: Cardinal; const Data: AnsiString): TF2lRequest;
begin
  Result := RequestClipFormat(rqClipSetData, Format);
  Result.Body := Data;
end;

function RequestClipChunk(const Data: AnsiString): TF2lRequest;
begin
  Result := PlainRequest(rqClipChunk);
  Result.Value := Cardinal(Length(Data)) shr 8;
  Result.Body := Data;
end;

procedure SetEdges(var Req: TF2lRequest; Left, Top, Right, Bottom: SmallInt);
begin
  Req.Edges[0] := Left;
  Req.Edges[1] := Top;
  Req.Edges[2] := Right;
  Req.Edges[3] := Bottom;
end;

function RequestImageSet(const ImageId: AnsiString; Flags: QWord; Left, Top, Right, Bottom: SmallInt;
  Width, Height: Cardinal; const Pixels: AnsiString): TF2lRequest;
begin
  Result := PlainRequest(rqImageSet);
  Result.Name := ImageId;
  Result.Flags := Flags;
  SetEdges(Result, Left, Top, Right, Bottom);
  Result.PixelWidth := Width;
  Result.PixelHeight := Height;
  Result.Body := Pixels;
end;

function RequestImageTransform(const ImageId: AnsiString; Left, Top, Right, Bottom: SmallInt;
  Transform: Word): TF2lRequest;
begin
  Result := PlainRequest(rqImageTransform);
  Result.Name := ImageId;
  SetEdges(Result, Left, Top, Right, Bottom);
  Result.Transform := Transform;
end;

function RequestImageDelete(const ImageId: AnsiString): TF2lRequest;
begin
  Result := PlainRequest(rqImageDelete);
  Result.Name := ImageId;
end;

{ The letters of the command and of the sub-command of a kind; the sub-command is #0 for a command without one. }
procedure LettersOf(Kind: TF2lRequestKind; out Cmd, Sub: AnsiChar);
var
  N: Integer;
begin
  N := Ord(Kind);
  Sub := #0;
  if N <= Ord(rqPalette) then
    Cmd := TopLetters[N + 1]
  else if N <= Ord(rqClipRegister) then
  begin
    Cmd := 'c';
    Sub := ClipLetters[N - Ord(rqClipOpen) + 1];
  end
  else
  begin
    Cmd := 'i';
    Sub := ImageLetters[N - Ord(rqImageCaps) + 1];
  end;
end;

{ The entries of the titles, F12 first, so that F1 is popped first; the state is above its title. }
procedure PutTitles(St: TF2lStack; const Req: TF2lRequest);
var
  K: Integer;
begin
  for K := Req.TitleCount - 1 downto 0 do
    if ((Req.TitleMask shr K) and 1) <> 0 then
    begin
      St.PutString(Req.Titles[K]);
      St.PutNumber(1, 1);
    end
    else
      St.PutNumber(0, 1);
end;

{ The four edges, bottom first. }
procedure PutEdges(St: TF2lStack; const Req: TF2lRequest);
var
  K: Integer;
begin
  for K := High(Req.Edges) downto Low(Req.Edges) do
    St.PutSigned(Req.Edges[K], 2);
end;

function EncodeRequest(const Req: TF2lRequest; Id: Byte): AnsiString;
var
  St: TF2lStack;
  Cmd, Sub: AnsiChar;
begin
  St := TF2lStack.Create;
  try
    case Req.Kind of
      rqFeatures:
        St.PutNumber(Req.Flags, 8);
      rqCursorHeight:
        St.PutNumber(Req.Value, 1);
      rqNotify:
        begin
          St.PutString(Req.Body);
          St.PutString(Req.Name);
        end;
      rqFKeyTitles:
        PutTitles(St, Req);
      rqClipOpen, rqClipRegister, rqImageDelete:
        St.PutString(Req.Name);
      rqClipIsAvail, rqClipGetData, rqClipGetDataId:
        St.PutNumber(Req.Value, 4);
      rqClipChunk:
        begin
          St.PutRaw(Req.Body);
          St.PutNumber(Req.Value, 2);
        end;
      rqClipSetData:
        begin
          St.PutRaw(Req.Body);
          St.PutNumber(Length(Req.Body), 4);
          St.PutNumber(Req.Value, 4);
        end;
      rqImageSet:
        begin
          St.PutRaw(Req.Body);
          St.PutNumber(Req.PixelHeight, 4);
          St.PutNumber(Req.PixelWidth, 4);
          PutEdges(St, Req);
          St.PutNumber(Req.Flags, 8);
          St.PutString(Req.Name);
        end;
      rqImageTransform:
        begin
          St.PutNumber(Req.Transform, 2);
          PutEdges(St, Req);
          St.PutString(Req.Name);
        end;
    else
      { no arguments }
    end;
    LettersOf(Req.Kind, Cmd, Sub);
    if Sub <> #0 then
      St.PutRaw(Sub);
    St.PutRaw(Cmd);
    St.PutNumber(Id, 1);
    Result := St.Serialized;
  finally
    St.Free;
  end;
end;

{ The answers }

function DecodeAnswer(Kind: TF2lRequestKind; Id: Byte; const Body: AnsiString; ClipFeatures: QWord;
  out Ans: TF2lAnswer): Boolean;
var
  St: TF2lStack;
  WantId: Boolean;
begin
  Ans := Default(TF2lAnswer);
  Ans.Kind := Kind;
  Ans.Id := Id;
  WantId := (ClipFeatures and FARTTY_FEATCLIP_DATA_ID) <> 0;
  St := TF2lStack.Create;
  try
    St.Load(Body);
    case Kind of
      rqMaxSize, rqImageCaps:
        begin
          Ans.Height := SmallInt(St.PopSigned(2));
          Ans.Width := SmallInt(St.PopSigned(2));
          if Kind = rqImageCaps then
            Ans.Wide := St.PopNumber(8);
        end;
      rqFKeyTitles, rqImageSet, rqImageTransform, rqImageDelete:
        Ans.Flag := St.PopNumber(1) <> 0;
      rqPalette:
        begin
          Ans.Bits := Byte(St.PopNumber(1));
          if St.Size > 0 then
            St.PopNumber(1);
        end;
      rqClipOpen:
        begin
          Ans.Status := ShortInt(St.PopSigned(1));
          if (Ans.Status = 1) and (St.Size >= 8) then
            Ans.Wide := St.PopNumber(8);
        end;
      rqClipClose, rqClipEmpty, rqClipIsAvail:
        begin
          Ans.Status := ShortInt(St.PopSigned(1));
          Ans.Flag := Ans.Status <> 0;
        end;
      rqClipSetData:
        begin
          Ans.Status := ShortInt(St.PopSigned(1));
          if (Ans.Status = 1) and WantId and (St.Size >= 8) then
            Ans.Wide := St.PopNumber(8);
        end;
      rqClipGetData:
        begin
          Ans.Number := Cardinal(St.PopNumber(4));
          if Ans.Number = NoStack then
            Ans.Status := -1
          else
          begin
            Ans.Data := St.PopRaw(Ans.Number);
            if WantId and (St.Size >= 8) then
              Ans.Wide := St.PopNumber(8);
          end;
        end;
      rqClipGetDataId:
        Ans.Wide := St.PopNumber(8);
      rqClipRegister:
        Ans.Number := Cardinal(St.PopNumber(4));
    else
      { the reply of these requests holds the ID alone }
    end;
    Ans.Valid := not St.Failed;
  finally
    St.Free;
  end;
  Result := Ans.Valid;
end;

{ The events }

procedure ReadFullKey(St: TF2lStack; var Ev: TF2lEvent);
begin
  Ev.Kind := feKey;
  Ev.Character := Cardinal(St.PopNumber(4));
  Ev.ControlKeyState := Cardinal(St.PopNumber(4));
  Ev.ScanCode := Word(St.PopNumber(2));
  Ev.VirtualKey := Word(St.PopNumber(2));
  Ev.RepeatCount := Word(St.PopNumber(2));
end;

procedure ReadCompactKey(St: TF2lStack; var Ev: TF2lEvent);
begin
  Ev.Kind := feKey;
  Ev.Compact := True;
  Ev.Character := Cardinal(St.PopNumber(2));
  Ev.ControlKeyState := Cardinal(St.PopNumber(2));
  Ev.VirtualKey := Word(St.PopNumber(1));
  Ev.RepeatCount := 1;
end;

procedure ReadMouse(St: TF2lStack; var Ev: TF2lEvent; IsCompact: Boolean);
var
  Squeezed: Cardinal;
begin
  Ev.Kind := feMouse;
  Ev.Compact := IsCompact;
  if IsCompact then
  begin
    Ev.EventFlags := Cardinal(St.PopNumber(1));
    Ev.ControlKeyState := Cardinal(St.PopNumber(1));
    Squeezed := Cardinal(St.PopNumber(2));
    Ev.ButtonState := (Squeezed and $FF) or ((Squeezed and $FF00) shl 8);
  end
  else
  begin
    Ev.EventFlags := Cardinal(St.PopNumber(4));
    Ev.ControlKeyState := Cardinal(St.PopNumber(4));
    Ev.ButtonState := Cardinal(St.PopNumber(4));
  end;
  Ev.MouseY := SmallInt(St.PopSigned(2));
  Ev.MouseX := SmallInt(St.PopSigned(2));
end;

function DecodeEvent(const Body: AnsiString; out Ev: TF2lEvent): TF2lDecodeResult;
var
  St: TF2lStack;
  Code: AnsiChar;
begin
  Ev := Default(TF2lEvent);
  Ev.Kind := feUnknown;
  St := TF2lStack.Create;
  try
    St.Load(Body);
    if St.Size = 0 then
    begin
      Result := drMalformed;
      Exit;
    end;
    Code := AnsiChar(Byte(St.PopNumber(1)));
    Ev.Code := Code;
    Result := drDecoded;
    case Code of
      'K', 'k':
        begin
          ReadFullKey(St, Ev);
          Ev.Pressed := Code = 'K';
        end;
      'C', 'c':
        begin
          ReadCompactKey(St, Ev);
          Ev.Pressed := Code = 'C';
        end;
      'M', 'm':
        ReadMouse(St, Ev, Code = 'm');
      'S':
        begin
          Ev.Kind := feTerminalSize;
          Ev.Rows := Word(St.PopNumber(2));
          Ev.Columns := Word(St.PopNumber(2));
        end;
    else
      Result := drUnknown;
    end;
    if (Result = drDecoded) and St.Failed then
      if Code = 'S' then
        Result := drMalformed
      else
        Result := drDropped;
  finally
    St.Free;
  end;
end;

function Far2lToEvent(const Fe: TF2lEvent; var Ev: TEvent; var State: TInputState): Boolean;
var
  Vk, Scan: Word;
  Ch: Cardinal;
begin
  Result := False;
  FillChar(Ev, SizeOf(Ev), 0);
  case Fe.Kind of
    feKey:
      if Fe.Pressed then
      begin
        Vk := Fe.VirtualKey;
        Scan := Fe.ScanCode;
        Ch := Fe.Character;
        RegenerateMissingScanCodeFromVirtualKeyCode(Vk, Scan, Ch, Fe.ControlKeyState);
        Result := GetWin32Key(Vk, Scan, Ch, Fe.ControlKeyState, Ev, State);
        if Result then
          NormalizeKey(Ev.KeyDown);
      end;
    feMouse:
      begin
        GetWin32Mouse(Fe.MouseX, Fe.MouseY, Fe.ButtonState, Fe.ControlKeyState, Fe.EventFlags, Ev, State);
        Result := True;
      end;
  else
    { nothing to give }
  end;
end;

{ TF2lDecoder }

constructor TF2lDecoder.Create;
begin
  inherited Create;
  FLimit := DefaultBodyLimit;
  Reset;
end;

procedure TF2lDecoder.Reset;
begin
  FPhase := PhaseIdle;
  FBodyUsed := 0;
  FOverflow := False;
  SetLength(FItems, 0);
  FHead := 0;
  FPlainUsed := 0;
  FSkipped := 0;
end;

procedure TF2lDecoder.PutPlain(const Data: AnsiString);
begin
  if Assigned(FOnPlain) then
    FOnPlain(Data)
  else
    AppendText(FPlain, FPlainUsed, Data);
end;

procedure TF2lDecoder.DropBody;
begin
  FBodyUsed := 0;
  FOverflow := False;
end;

procedure TF2lDecoder.StoreBody(B: Byte);
begin
  if FBodyUsed >= FLimit then
    FOverflow := True
  else
    AppendText(FBody, FBodyUsed, Chr(B));
end;

procedure TF2lDecoder.AfterEsc(B: Byte);
begin
  if B = Ord('_') then
  begin
    DropBody;
    FPhase := PhaseBody;
  end
  else if B = 27 then
  begin
    PutPlain(#27);
    FPhase := PhaseEsc;
  end
  else
  begin
    PutPlain(#27 + Chr(B));
    FPhase := PhaseIdle;
  end;
end;

procedure TF2lDecoder.Enqueue(const Itm: TF2lItem);
begin
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := Itm;
end;

procedure TF2lDecoder.ReadReply(const Encoded: AnsiString; var Itm: TF2lItem);
var
  St: TF2lStack;
begin
  St := TF2lStack.Create;
  try
    St.Load(Far2lDecodePayload(Encoded));
    if St.Size = 0 then
      Itm.Kind := ikBadReply
    else
    begin
      Itm.ReplyId := Byte(St.PopNumber(1));
      Itm.ReplyBody := St.Serialized;
      Itm.Kind := ikReply;
    end;
  finally
    St.Free;
  end;
end;

procedure TF2lDecoder.Complete;
var
  Whole, Rest: AnsiString;
  Itm: TF2lItem;
begin
  FPhase := PhaseIdle;
  if FOverflow then
  begin
    Inc(FSkipped);
    DropBody;
    Exit;
  end;
  Whole := Copy(FBody, 1, FBodyUsed);
  DropBody;
  Itm := Default(TF2lItem);
  if Copy(Whole, 1, 3) = 'f2l' then
  begin
    case DecodeEvent(Far2lDecodePayload(Copy(Whole, 4, Length(Whole))), Itm.Event) of
      drDecoded: Itm.Kind := ikEvent;
      drUnknown: Itm.Kind := ikUnknownEvent;
      drDropped: Itm.Kind := ikDropped;
    else
      Itm.Kind := ikBadEvent;
    end;
  end
  else if Copy(Whole, 1, 5) = 'far2l' then
  begin
    Rest := Copy(Whole, 6, Length(Whole));
    if Rest = 'ok' then
      Itm.Kind := ikAck
    else
      ReadReply(Rest, Itm);
  end
  else
    Itm.Kind := ikOtherApc;
  Enqueue(Itm);
end;

procedure TF2lDecoder.FeedByte(B: Byte);
begin
  case FPhase of
    PhaseIdle:
      if B = 27 then
        FPhase := PhaseEsc
      else
        PutPlain(Chr(B));
    PhaseEsc:
      AfterEsc(B);
    PhaseBody:
      if B = 7 then
        Complete
      else if B = 27 then
        FPhase := PhaseBodyEsc
      else
        StoreBody(B);
  else
    if B = Ord('\') then
      Complete
    else
    begin
      Inc(FSkipped);
      DropBody;
      AfterEsc(B);
    end;
  end;
end;

procedure TF2lDecoder.Feed(const Data: AnsiString);
var
  K: SizeInt;
begin
  for K := 1 to Length(Data) do
    FeedByte(Ord(Data[K]));
end;

function TF2lDecoder.Next(out Item: TF2lItem): Boolean;
begin
  Item := Default(TF2lItem);
  Result := FHead < Length(FItems);
  if not Result then
    Exit;
  Item := FItems[FHead];
  Inc(FHead);
  if FHead >= Length(FItems) then
  begin
    SetLength(FItems, 0);
    FHead := 0;
  end;
end;

function TF2lDecoder.Pending: SizeInt;
begin
  Result := Length(FItems) - FHead;
end;

function TF2lDecoder.TakePlain: AnsiString;
begin
  Result := Copy(FPlain, 1, FPlainUsed);
  FPlainUsed := 0;
end;

{ TF2lConsoleSender }

constructor TF2lConsoleSender.Create(ACon: ConsoleCtl);
begin
  inherited Create;
  FCon := ACon;
end;

procedure TF2lConsoleSender.Send(const Data: AnsiString);
begin
  if (FCon <> nil) and (Length(Data) > 0) then
    FCon.Write(PAnsiChar(Data), Length(Data));
end;

{ TFar2lClient }

constructor TFar2lClient.Create(ASend: TF2lSendProc);
begin
  inherited Create;
  FSend := ASend;
  FTerm := tmSt;
  FDecoder := TF2lDecoder.Create;
  FDecoder.OnPlain := @HandlePlain;
end;

constructor TFar2lClient.CreateForConsole(Con: ConsoleCtl);
begin
  FOwned := TF2lConsoleSender.Create(Con);
  Create(@FOwned.Send);
end;

destructor TFar2lClient.Destroy;
begin
  FDecoder.Free;
  FOwned.Free;
  inherited Destroy;
end;

procedure TFar2lClient.Emit(const Data: AnsiString);
begin
  if Assigned(FSend) and (Length(Data) > 0) then
    FSend(Data);
end;

function TFar2lClient.InFlightCount: Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := 1 to MaxRequestsInFlight do
    Inc(Result, Ord(FSlots[K].Busy));
end;

function TFar2lClient.IsPending(Id: Byte): Boolean;
begin
  Result := (Id <> 0) and FSlots[Id].Busy;
end;

function TFar2lClient.ProbeState: TF2lProbeState;
begin
  Result := FProbe;
end;

function TFar2lClient.Acknowledged: Boolean;
begin
  Result := FAcked;
end;

function TFar2lClient.ServerClipFeatures: QWord;
begin
  Result := FServerClip;
end;

function TFar2lClient.Decoder: TF2lDecoder;
begin
  Result := FDecoder;
end;

function TFar2lClient.TakeId(out Id: Byte): Boolean;
var
  Tries: Integer;
begin
  Id := 0;
  Result := False;
  if InFlightCount >= MaxRequestsInFlight then
    Exit;
  for Tries := 1 to 255 do
  begin
    FCounter := Byte((Integer(FCounter) + 1) and $FF);
    if (FCounter <> 0) and not FSlots[FCounter].Busy then
    begin
      Id := FCounter;
      Result := True;
      Exit;
    end;
  end;
end;

procedure TFar2lClient.ForgetAll;
var
  K: Integer;
begin
  for K := 1 to MaxRequestsInFlight do
    FSlots[K].Busy := False;
end;

procedure TFar2lClient.Probe;
begin
  FAcked := False;
  FSupported := False;
  FWindow := '';
  FProbe := ppWaiting;
  Emit(ActivationText + StatusQueryText);
end;

procedure TFar2lClient.Announce;
begin
  Emit(ActivationText);
end;

procedure TFar2lClient.ProbeTimedOut;
begin
  if FProbe = ppWaiting then
  begin
    FProbe := ppDone;
    FSupported := FAcked;
  end;
end;

procedure TFar2lClient.Deactivate;
begin
  Emit(DeactivationText(FTerm));
  FAcked := False;
  FSupported := False;
  FProbe := ppIdle;
  FServerClip := 0;
  ForgetAll;
end;

procedure TFar2lClient.SendHostIdentity(const Identity: AnsiString);
begin
  Emit(HostIdentityText(Identity, FTerm));
end;

procedure TFar2lClient.HandlePlain(const Data: AnsiString);
var
  Joined: AnsiString;
  Start: SizeInt;
begin
  AppendText(FPlainOut, FPlainUsed, Data);
  if FProbe <> ppWaiting then
    Exit;
  Joined := FWindow + Data;
  if Pos(DsrReply, Joined) > 0 then
  begin
    FProbe := ppDone;
    FSupported := FAcked;
    FWindow := '';
  end
  else
  begin
    Start := Length(Joined) - 2;
    if Start < 1 then
      Start := 1;
    FWindow := Copy(Joined, Start, 3);
  end;
end;

function TFar2lClient.TakePlain: AnsiString;
begin
  Result := Copy(FPlainOut, 1, FPlainUsed);
  FPlainUsed := 0;
end;

procedure TFar2lClient.Deliver(const Ans: TF2lAnswer);
begin
  if Assigned(FOnAnswer) then
    FOnAnswer(Ans);
end;

procedure TFar2lClient.FailAll;
var
  K: Integer;
  Ans: TF2lAnswer;
begin
  for K := 1 to MaxRequestsInFlight do
    if FSlots[K].Busy then
    begin
      FSlots[K].Busy := False;
      Ans := Default(TF2lAnswer);
      Ans.Kind := FSlots[K].Kind;
      Ans.Id := Byte(K);
      Deliver(Ans);
    end;
end;

procedure TFar2lClient.HandleReply(const Itm: TF2lItem);
var
  Ans: TF2lAnswer;
begin
  if (Itm.ReplyId = 0) or not FSlots[Itm.ReplyId].Busy then
  begin
    Inc(Strays);
    Exit;
  end;
  FSlots[Itm.ReplyId].Busy := False;
  DecodeAnswer(FSlots[Itm.ReplyId].Kind, Itm.ReplyId, Itm.ReplyBody, FServerClip, Ans);
  if (Ans.Kind = rqClipOpen) and Ans.Valid and (Ans.Status = 1) then
    FServerClip := Ans.Wide;
  Deliver(Ans);
end;

procedure TFar2lClient.HandleItem(const Itm: TF2lItem);
begin
  case Itm.Kind of
    ikAck:
      FAcked := True;
    ikReply:
      HandleReply(Itm);
    ikEvent:
      if Assigned(FOnEvent) then
        FOnEvent(Itm.Event);
    ikBadReply, ikBadEvent:
      FailAll;
  else
    { dropped and unknown strings are ignored }
  end;
end;

procedure TFar2lClient.Feed(const Data: AnsiString);
var
  K: SizeInt;
  Itm: TF2lItem;
begin
  for K := 1 to Length(Data) do
  begin
    FDecoder.FeedByte(Ord(Data[K]));
    while FDecoder.Next(Itm) do
      HandleItem(Itm);
  end;
end;

function TFar2lClient.Submit(const Req: TF2lRequest; WantReply: Boolean; out Id: Byte): Boolean;
begin
  Id := 0;
  if WantReply and not TakeId(Id) then
  begin
    Result := False;
    Exit;
  end;
  Emit(WrapRequest(EncodeRequest(Req, Id), FTerm));
  if Id <> 0 then
  begin
    FSlots[Id].Busy := True;
    FSlots[Id].Kind := Req.Kind;
  end;
  Result := True;
end;

function TFar2lClient.PutClipboardData(Format: Cardinal; const Data: AnsiString; out Id: Byte): Boolean;
var
  At: SizeInt;
  Pieces: Integer;
  Spare: Byte;
begin
  Id := 0;
  Result := False;
  At := 1;
  Pieces := 0;
  if (FServerClip and FARTTY_FEATCLIP_CHUNKED_SET) <> 0 then
    while Length(Data) - At + 1 > ClipChunkSize do
    begin
      Inc(Pieces);
      if not Submit(RequestClipChunk(Copy(Data, At, ClipChunkSize)), (Pieces mod ClipChunkAckEvery) = 0,
        Spare) then
      begin
        { Without room for the next answer the upload is cancelled: a piece of size zero drops the collected ones. }
        Submit(RequestClipChunk(''), False, Spare);
        Exit;
      end;
      Inc(At, ClipChunkSize);
    end;
  Result := Submit(RequestClipSetData(Format, Copy(Data, At, Length(Data))), True, Id);
  if not Result and (Pieces > 0) then
    Submit(RequestClipChunk(''), False, Spare);
end;

end.
