{ Tests of TvVtExt. The server is driven through Body, the way the emulator hands over the body of an APC string;
  a host that records its calls stands behind it. The wire strings are the ones that the specification gives. }
program t_vtext;

{$mode objfpc}
{$H+}
{$modeswitch advancedrecords}

uses
  SysUtils, TvEvents, TvKeys, TvFar2l, TvClip, TvTermIo, TvVtExt;

{$I testlib.inc}

const
  EscCh = #27;
  BelCh = #7;
  ClientA = '0123456789abcdef0123456789abcdef';
  ClientB = 'abcdef0123456789abcdef0123456789';
  AckSeq = #27'_far2lok'#7;

type
  { Records what the server asks of its host. }
  TTestHost = class(TVtExtHost)
  public
    Answer: TVtClipAnswer;
    Asked: Integer;
    AskedId: AnsiString;
    CursorGot: Integer;
    MaxKnown: Boolean;
    MaxCols, MaxRows: Integer;
    Depth: Integer;
    NoteCount: Integer;
    NoteTitle, NoteText: AnsiString;
    GotTitles: array of AnsiString;
    TitleCalls: Integer;
    Maximized, Restored, QuickEdits: Integer;
    function Joined: AnsiString;
    function AskClipboard(const ClientId: AnsiString): TVtClipAnswer; override;
    procedure Notify(const Title, Text: AnsiString); override;
    function FKeyTitles(const Titles: array of AnsiString): Boolean; override;
    procedure CursorHeight(Percent: Integer); override;
    function ColorBits: Integer; override;
    function WindowMaxSize(out Cols, Rows: Integer): Boolean; override;
    procedure WindowMaximize(Maximize: Boolean); override;
    procedure QuickEdit; override;
  end;

  { Connects a client of TvFar2l to the server: what the client writes goes to Body, what comes back is kept until
    Pump hands it to the client. }
  TLink = class
  public
    Outbox: AnsiString;
    Answers: array of TF2lAnswer;
    procedure Send(const Data: AnsiString);
    procedure GotAnswer(const Answer: TF2lAnswer);
  end;

var
  TestNow: Int64;
  Reply: TF2lStack;
  Srv: TVtExtServer;
  Host: TTestHost;
  TempDir, AuthPath: AnsiString;
  NoItems: array of TVtClipItem;
  Link: TLink;
  Client: TFar2lClient;
  HookTitleCalls: Integer;
  HookNoteText: AnsiString;

{ TTestHost }

function TTestHost.Joined: AnsiString;
var
  K: Integer;
begin
  Result := '';
  for K := 0 to High(GotTitles) do
    Result := Result + GotTitles[K] + '|';
end;

function TTestHost.AskClipboard(const ClientId: AnsiString): TVtClipAnswer;
begin
  Inc(Asked);
  AskedId := ClientId;
  Result := Answer;
end;

procedure TTestHost.Notify(const Title, Text: AnsiString);
begin
  Inc(NoteCount);
  NoteTitle := Title;
  NoteText := Text;
end;

function TTestHost.FKeyTitles(const Titles: array of AnsiString): Boolean;
var
  K: Integer;
begin
  Inc(TitleCalls);
  SetLength(GotTitles, Length(Titles));
  for K := 0 to High(Titles) do
    GotTitles[K] := Titles[K];
  Result := True;
end;

procedure TTestHost.CursorHeight(Percent: Integer);
begin
  CursorGot := Percent;
end;

function TTestHost.ColorBits: Integer;
begin
  Result := Depth;
end;

function TTestHost.WindowMaxSize(out Cols, Rows: Integer): Boolean;
begin
  Cols := MaxCols;
  Rows := MaxRows;
  Result := MaxKnown;
end;

procedure TTestHost.WindowMaximize(Maximize: Boolean);
begin
  if Maximize then
    Inc(Maximized)
  else
    Inc(Restored);
end;

procedure TTestHost.QuickEdit;
begin
  Inc(QuickEdits);
end;

{ The hooks of the base host }

procedure HookTitles(const Titles: array of AnsiString);
begin
  Inc(HookTitleCalls);
end;

procedure HookNotify(const Title, Text: AnsiString);
begin
  HookNoteText := Title + '/' + Text;
end;

function HookColors: Integer;
begin
  Result := 8;
end;

{ TLink }

function Apc(const Wire: AnsiString): AnsiString; forward;

procedure TLink.Send(const Data: AnsiString);
begin
  Outbox := Outbox + Srv.Body(Apc(Data));
end;

procedure TLink.GotAnswer(const Answer: TF2lAnswer);
begin
  SetLength(Answers, Length(Answers) + 1);
  Answers[High(Answers)] := Answer;
end;

{ Helpers }

function TestClock: Int64;
begin
  Result := TestNow;
end;

{ The body of an APC string: the string without ESC _ and without its terminator, BEL or ESC \. }
function Apc(const Wire: AnsiString): AnsiString;
var
  Last: SizeInt;
begin
  Last := Length(Wire);
  if (Last > 0) and (Wire[Last] = BelCh) then
    Dec(Last)
  else if (Last > 1) and (Wire[Last - 1] = EscCh) and (Wire[Last] = '\') then
    Dec(Last, 2);
  Result := Copy(Wire, 3, Last - 2);
end;

function Num(Value: QWord; Width: Integer): AnsiString;
var
  St: TF2lStack;
begin
  St := TF2lStack.Create;
  try
    St.PutNumber(Value, Width);
    Result := St.Serialized;
  finally
    St.Free;
  end;
end;

{ A string as it lies in a stack: the bytes, then the length. }
function PStr(const S: AnsiString): AnsiString;
begin
  Result := S + Num(Length(S), 4);
end;

{ The bytes of a request: the arguments, the letters of the command and the ID. }
function Req(const Args, Letters: AnsiString; Id: Byte): AnsiString;
begin
  Result := Args + Letters + Chr(Id);
end;

function Ask(const Stack: AnsiString): AnsiString;
begin
  Result := Srv.Body('far2l:' + EncodeBase64(Stack));
end;

function ClipAsk(const Args: AnsiString; Sub: Char; Id: Byte): AnsiString;
begin
  Result := Ask(Req(Args, Sub + 'c', Id));
end;

function IdOnly(Id: Byte): AnsiString;
begin
  Result := EscCh + '_far2l' + EncodeBase64(Chr(Id)) + BelCh;
end;

{ Loads the stack of a reply string into Reply (its ID on top); False when the text is not a reply. }
function LoadReply(const R: AnsiString): Boolean;
begin
  Result := (Length(R) > 8) and (Copy(R, 1, 7) = EscCh + '_far2l') and (R[Length(R)] = BelCh);
  if Result then
    Reply.Load(Far2lDecodePayload(Copy(R, 8, Length(R) - 8)))
  else
    Reply.Load('');
end;

{ Loads the stack of an event string (its code on top). }
function LoadEvent(const R: AnsiString): Boolean;
begin
  Result := (Length(R) > 7) and (Copy(R, 1, 5) = EscCh + '_f2l') and (R[Length(R)] = BelCh);
  if Result then
    Reply.Load(Far2lDecodePayload(Copy(R, 6, Length(R) - 6)))
  else
    Reply.Load('');
end;

function SizeWire(Cols, Rows: Integer): AnsiString;
begin
  Result := EscCh + '_f2l' + EncodeBase64(Num(Cols, 2) + Num(Rows, 2) + 'S') + BelCh;
end;

function Wide(const Ascii: AnsiString): AnsiString;
var
  K: Integer;
begin
  Result := '';
  for K := 1 to Length(Ascii) do
    Result := Result + Ascii[K] + #0#0#0;
end;

{ The three letters of a Cyrillic word, as UTF-32 and as UTF-8, from the code points. }
function CyrillicWide: AnsiString;
begin
  Result := Num($41A, 4) + Num($43E, 4) + Num($43B, 4);
end;

function CyrillicBytes: AnsiString;
var
  K: Integer;
  Point: Cardinal;
begin
  Result := '';
  for K := 0 to 2 do
  begin
    Point := Cardinal(Ord(CyrillicWide[K * 4 + 1])) or (Cardinal(Ord(CyrillicWide[K * 4 + 2])) shl 8);
    Result := Result + Chr($C0 or (Point shr 6)) + Chr($80 or (Point and $3F));
  end;
end;

procedure NewServer(Answer: TVtClipAnswer; Activate: Boolean);
begin
  Srv.Free;
  Host.Free;
  Host := TTestHost.Create;
  Host.Answer := Answer;
  Host.MaxKnown := True;
  Host.MaxCols := 200;
  Host.MaxRows := 50;
  Host.Depth := 24;
  Srv := TVtExtServer.Create(80, 25);
  Srv.Host := Host;
  Srv.Now := @TestClock;
  Srv.AuthedsPath := AuthPath;
  TestNow := 200000;
  if Activate then
    Srv.Body('far2l1');
end;

procedure OpenFor(const Cid: AnsiString; Id: Byte; out Status: Integer);
begin
  Status := 99;
  LoadReply(ClipAsk(PStr(Cid), 'o', Id));
  Reply.PopNumber(1);
  Status := Integer(Reply.PopSigned(1));
end;

function SetData(Format: LongWord; const Data: AnsiString; Id: Byte): AnsiString;
begin
  Result := ClipAsk(Data + Num(Length(Data), 4) + Num(Format, 4), 's', Id);
end;

{ Reads the reply of CLIP_GET_DATA: Size is $FFFFFFFF for a clipboard that is not open. }
procedure ParseGet(const R: AnsiString; out Size: QWord; out Data: AnsiString; out DataId: QWord);
begin
  LoadReply(R);
  Reply.PopNumber(1);
  Size := Reply.PopNumber(4);
  Data := '';
  DataId := 0;
  if Size = $FFFFFFFF then
    Exit;
  Data := Reply.PopRaw(Size);
  DataId := Reply.PopNumber(8);
end;

procedure GetAt(Format: LongWord; Moment: Int64; out Size: QWord; out Data: AnsiString; out DataId: QWord);
begin
  TestNow := Moment;
  ParseGet(ClipAsk(Num(Format, 4), 'g', 3), Size, Data, DataId);
end;

procedure MakeKey(var Ev: TEvent; KeyCode, Mods: Word; const Utf8: AnsiString);
var
  K: Integer;
begin
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.What := evKeyDown;
  Ev.KeyDown.KeyCode := KeyCode;
  Ev.KeyDown.ControlKeyState := Mods;
  Ev.KeyDown.TextLength := Length(Utf8);
  for K := 1 to Length(Utf8) do
    Ev.KeyDown.Text[K - 1] := Ord(Utf8[K]);
end;

procedure Pump;
begin
  Client.Feed(Link.Outbox);
  Link.Outbox := '';
end;

function LastAnswer: TF2lAnswer;
begin
  Result := Link.Answers[High(Link.Answers)];
end;

procedure TestBaseHost;
var
  Plain: TVtExtHost;
  Cols, Rows: Integer;
  NoTitles: array of AnsiString;
begin
  Plain := TVtExtHost.Create;
  try
    SetLength(NoTitles, 0);
    Check(Plain.AskClipboard(ClientA) = vcaRemote, 'the base host answers vcaRemote');
    Check(Plain.ColorBits = 4, 'the base host gives 4 colour bits when TvSys gives none');
    Check(not Plain.FKeyTitles(NoTitles), 'the base host reports False for titles without the hook');
    Check(not Plain.WindowMaxSize(Cols, Rows), 'the base host has no largest window without the hook');
    VtOnSetFKeyTitles := @HookTitles;
    VtOnNotify := @HookNotify;
    VtOnColorBits := @HookColors;
    Check(Plain.FKeyTitles(NoTitles) and (HookTitleCalls = 1), 'the base host forwards titles to the hook');
    Plain.Notify('T', 'X');
    Check(HookNoteText = 'T/X', 'the base host forwards a notification with the same title and text');
    Check(Plain.ColorBits = 8, 'the base host forwards the colour bits');
    VtOnSetFKeyTitles := nil;
    VtOnNotify := nil;
    VtOnColorBits := nil;
  finally
    Plain.Free;
  end;
end;

procedure TestActivation;
var
  Own: TVtExtHost;
begin
  Srv.Free;
  Srv := TVtExtServer.Create(80, 25);
  Check(not Srv.Active, 'the server is not active after Create');
  Check(Srv.CursorPercent = -1, 'CursorPercent is -1 after Create');
  Check(ExtractFileName(Srv.AuthedsPath) = 'far2l-clipboard-autheds', 'AuthedsPath names the file of the clients');
  Check(Assigned(Srv.Now), 'the clock is set after Create');
  Check(Srv.Host <> nil, 'the server has its own host after Create');
  Own := Srv.Host;
  Host.Free;
  Host := TTestHost.Create;
  Srv.Host := Host;
  Check(Srv.Host = Host, 'a host that is given becomes the current host');
  Srv.Host := nil;
  Check(Srv.Host = Own, 'writing nil restores the own host');
  Srv.Host := Host;
  Srv.Now := @TestClock;
  Srv.AuthedsPath := AuthPath;
  Host.MaxKnown := True;
  Host.MaxCols := 200;
  Host.MaxRows := 50;
  Host.Depth := 24;
  Check(Ask(Req('', 'e', 8)) = '', 'a request before far2l1 gets no answer');
  Check(Host.QuickEdits = 0, 'a request before the activation has no effect');
  Check(Srv.Body(Apc(EscCh + '_far2l1' + EscCh + '\')) = AckSeq, 'far2l1 is acknowledged');
  Check(Srv.Active, 'far2l1 makes the server active');
  Check(Srv.Body(Apc(EscCh + '_far2l1' + BelCh)) = AckSeq, 'far2l1 ended with BEL is acknowledged again');
  Check(Srv.Body('far2l_marker') = '', 'far2l_marker gets no answer');
  Check(Srv.Body('far2l:') = '', 'an empty request gets no answer');
  Check(Srv.Body('far2') = '', 'a string shorter than 6 bytes gets no answer');
  Check(Srv.Body('FAR2L1') = '', 'the prefix is case sensitive');
  Check(Srv.Body('far2l:!!!!') = '', 'a payload without a valid character gets no answer');
  Check(Srv.Active, 'ignored strings leave the server active');
end;

procedure TestSimpleRequests;
begin
  Check(Srv.Body(Apc(EscCh + '_far2l:MmgA' + BelCh)) = '', 'the cursor height request has no reply');
  Check(Srv.CursorPercent = 50, 'CursorPercent is 50 after the cursor height request');
  Check(Host.CursorGot = 50, 'the host got the cursor height 50');
  Ask(Req(Num(250, 1), 'h', 0));
  Check((Srv.CursorPercent = 100) and (Host.CursorGot = 100), 'a cursor height above 100 is made 100');
  Ask(Req(Num(0, 1), 'h', 0));
  Check((Srv.CursorPercent = 0) and (Host.CursorGot = 0), 'the cursor height 0 is allowed');
  Ask(Req('', 'h', 0));
  Check(Srv.CursorPercent = 0, 'a cursor height request without its byte sets nothing');
  Check(Srv.Body(Apc(EscCh + '_far2l:dwE=' + BelCh)) = EscCh + '_far2lyAAyAAE=' + BelCh,
    'GET_WINDOW_MAXSIZE with ID 1 gives 200 by 50');
  Host.MaxKnown := False;
  LoadReply(Ask(Req('', 'w', 1)));
  Check((Reply.PopNumber(1) = 1) and (Reply.PopNumber(2) = 25) and (Reply.PopNumber(2) = 80),
    'the current size is used when the host does not know the largest window');
  Host.MaxKnown := True;
  Host.MaxRows := 0;
  LoadReply(Ask(Req('', 'w', 1)));
  Check((Reply.PopNumber(1) = 1) and (Reply.PopNumber(2) = 25) and (Reply.PopNumber(2) = 80),
    'the current size is used when a size of the host is zero');
  Host.MaxRows := 50;
  Check(Srv.Body(Apc(EscCh + '_far2l:T0sCAAAARG9uZQQAAABuAA==' + BelCh)) = '', 'the notification has no reply');
  Check((Host.NoteCount = 1) and (Host.NoteTitle = 'Done') and (Host.NoteText = 'OK'),
    'the host got the title Done and the text OK');
  Check(Ask(Req('', 'n', 7)) = EscCh + '_far2lBw==' + BelCh, 'a notification without arguments gets the ID alone');
  Check(Host.NoteCount = 1, 'a notification without arguments is not shown');
  Check(Ask(Req('', 'Z', 9)) = EscCh + '_far2lCQ==' + BelCh, 'an unknown command gets the ID alone');
  Check(Ask(Req('', 'Z', 0)) = '', 'an unknown command with ID 0 gets nothing');
  Check(Ask(Req('', 'e', 8)) = IdOnly(8), 'quick edit gets the ID alone');
  Check(Host.QuickEdits = 1, 'quick edit reached the host once');
  Ask(Req('', 'M', 0));
  Ask(Req('', 'm', 0));
  Check((Host.Maximized = 1) and (Host.Restored = 1), 'maximize and restore reached the host once each');
  Check(Ask(Req('', 'p', 0)) = '', 'a request with ID 0 gets no answer');
  LoadReply(Ask(Req('', 'p', 10)));
  Check(Reply.PopNumber(1) = 10, 'the palette reply ends with the ID');
  Check(Reply.PopNumber(1) = 24, 'the palette reply has the colour depth first');
  Check(Reply.PopNumber(1) = 0, 'the palette reply has the reserved byte second');
  Check(Reply.Size = 0, 'the palette reply has nothing more');
  Check(Ask(Chr(0)) = '', 'a request of one byte with ID 0 is not answered');
  Check(Ask(Chr(5)) = IdOnly(5), 'a request of one byte gets the ID alone');
end;

procedure TestFKeys;
begin
  Check(Srv.Body(Apc(EscCh + '_far2l:AAAAAAAAAAAAAE1lbnUEAAAAAUhlbHAEAAAAAWYB' + BelCh)) =
    EscCh + '_far2lAQE=' + BelCh, 'the F-key titles request gets success and the ID');
  Check(Host.Joined = 'Help|Menu|' + StringOfChar('|', 10), 'the host got Help, Menu and ten empty titles');
  Check(Length(Host.GotTitles) = 12, 'the host got 12 titles');
  LoadReply(Ask(Req(PStr('F2') + Num(1, 1) + Num(0, 1), 'f', 11)));
  Check((Reply.PopNumber(1) = 11) and (Reply.PopNumber(1) = 1) and (Reply.Size = 0),
    'the titles with only F2 give 1 and the ID');
  Check(Host.Joined = '|F2|' + StringOfChar('|', 10), 'the host got an empty F1, F2 and ten empty titles');
end;

procedure TestImage;
begin
  Check(Ask(Req('', 'ci', 5)) = EscCh + '_far2l' + EncodeBase64(StringOfChar(#0, 12) + #5) + BelCh,
    'IMAGE_CAPS gives twelve zero bytes and the ID');
  Check(Srv.Body(Apc(EscCh + '_far2l:/wAA/wEAAAABAAAA/////wMAAgAAAAAAAAAAAGltZwMAAABzaQY=' + BelCh)) =
    EscCh + '_far2lAAY=' + BelCh, 'IMAGE_SET gives status 0 and the ID');
  Check(Ask(Req('', 'ti', 7)) = EscCh + '_far2lAAc=' + BelCh, 'IMAGE_TRANSFORM gives status 0 and the ID');
end;

procedure TestFeaturesAndSize;
begin
  NewServer(vcaShare, True);
  Check(not Srv.CompactInput, 'compact input is off before the features request');
  Check(Ask(Req(Num(3, 8), 'x', 0)) = EscCh + '_f2lUAAZAFM=' + BelCh,
    'features compact and size give exactly the size event for 80 by 25');
  Check(Srv.CompactInput, 'compact input is on after the features request');
  Check(Srv.Resized(100, 30) = SizeWire(100, 30), 'a resize gives the size event for 100 by 30');
  Check(Srv.Resized(100, 30) = '', 'a resize to the same size gives nothing');
  Check(Srv.Resized(80, 25) = SizeWire(80, 25), 'a resize back gives the size event for 80 by 25');
  NewServer(vcaShare, True);
  Check(Ask(Req(Num(1, 8), 'x', 0)) = '', 'features compact input with ID 0 gets no reply and no size event');
  Check(Srv.Resized(90, 25) = '', 'a resize without the size feature gives no size event');
  Ask(Req('abc', 'x', 0));
  Check(Srv.CompactInput, 'a features request that is too short leaves the features');
  Ask(Req(Num(0, 8), 'x', 0));
  Check(not Srv.CompactInput, 'the features are replaced by the value');
  NewServer(vcaShare, False);
  Check(Srv.Resized(90, 25) = '', 'a resize of a server that is not active gives nothing');
  Srv.Body('far2l1');
  Ask(Req(Num(2, 8), 'x', 0));
  Check(Srv.Resized(90, 25) = '', 'the size stored while not active equals the size now');
  Check(Srv.Resized(91, 25) = SizeWire(91, 25), 'the size event goes out without the compact feature');
end;

procedure TestEvents;
var
  Ev: TEvent;
  Text: AnsiString;
begin
  NewServer(vcaShare, False);
  MakeKey(Ev, $1E61, 0, 'a');
  Check(Srv.KeyEvent(Ev) = '', 'a key event of a server that is not active is empty');
  Check(Srv.MouseEvent(1, 1, 0, 0, False, False, 0) = '', 'a mouse event of a server that is not active is empty');
  Srv.Body('far2l1');
  Ask(Req(Num(1, 8), 'x', 0));
  Check(Srv.KeyEvent(Ev) = EscCh + '_f2lQQAAYQBD' + BelCh, 'the press of a gives the compact key event');
  Ev.What := VtEvKeyUp;
  Text := Srv.KeyEvent(Ev);
  Check(LoadEvent(Text), 'the release of a is an event string');
  Check(Reply.PopNumber(1) = Ord('c'), 'the release of a is a compact release');
  MakeKey(Ev, kbCtrlA, kbLeftCtrl, '');
  Check(LoadEvent(Srv.KeyEvent(Ev)), 'Ctrl+A is an event string');
  Check(Reply.PopNumber(1) = Ord('C'), 'Ctrl+A is a compact press');
  Check(Reply.PopNumber(2) = 1, 'Ctrl+A has the character 1');
  Check((Reply.PopNumber(2) and $0C) <> 0, 'Ctrl+A has a Ctrl bit in its state');
  Check(Reply.PopNumber(1) = $41, 'Ctrl+A has the virtual key $41');
  MakeKey(Ev, $1E61, kbLeftCtrl, 'a');
  LoadEvent(Srv.KeyEvent(Ev));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(2) = 1, 'Ctrl with the text a gives the character 1');
  MakeKey(Ev, $1E61, kbLeftCtrl or kbLeftAlt, 'a');
  LoadEvent(Srv.KeyEvent(Ev));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(2) = Ord('a'), 'Ctrl with Alt leaves the character');
  MakeKey(Ev, $1E61, kbShift, 'A');
  LoadEvent(Srv.KeyEvent(Ev));
  Reply.PopNumber(1);
  Reply.PopNumber(2);
  Check(Reply.PopNumber(2) = SHIFT_PRESSED, 'Shift gives the Shift bit of the state');
  MakeKey(Ev, $1E61, 0, Chr($F0) + Chr($9F) + Chr($98) + Chr($80));
  LoadEvent(Srv.KeyEvent(Ev));
  Check(Reply.PopNumber(1) = Ord('K'), 'a character above $FFFF is sent in the long form');
  Check(Reply.PopNumber(4) = $1F600, 'a character above $FFFF is sent whole');
  Ask(Req(Num(0, 8), 'x', 0));
  MakeKey(Ev, $1E61, 0, 'a');
  LoadEvent(Srv.KeyEvent(Ev));
  Check(Reply.PopNumber(1) = Ord('K'), 'without compact input a press is a long key event');
  Check(Reply.PopNumber(4) = Ord('a'), 'the long key event has the character');
  Check(Reply.PopNumber(4) = 0, 'the long key event has the state');
  Check(Reply.PopNumber(2) = $1E, 'the long key event has the scan code');
  Check(Reply.PopNumber(2) = $41, 'the long key event has the virtual key');
  Check(Reply.PopNumber(2) = 1, 'the long key event has the repeat count 1');
  Ask(Req(Num(1, 8), 'x', 0));
  Check(Srv.MouseEvent(10, 5, mbLeftButton, 0, False, False, 0) = EscCh + '_f2lCgAFAAEAAABt' + BelCh,
    'the left button at 10, 5 gives the compact mouse event');
  Check(Srv.MouseEvent(10, 5, 0, mwDown, False, False, 0) = EscCh + '_f2lCgAFAAAA//8AAAAABAAAAE0=' + BelCh,
    'the wheel down at 10, 5 gives the long mouse event');
  LoadEvent(Srv.MouseEvent(2, 3, 0, mwUp, False, False, 0));
  Check(Reply.PopNumber(1) = Ord('m'), 'the wheel up is a compact mouse event');
  Check(Reply.PopNumber(1) = MOUSE_WHEELED, 'the wheel up has the wheel flag');
  Reply.PopNumber(1);
  Check(Reply.PopNumber(2) = $0100, 'the wheel up has 1 in the high part of the buttons');
  LoadEvent(Srv.MouseEvent(2, 3, 0, mwLeft or mwRight, False, False, 0));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(1) = MOUSE_HWHEELED, 'the horizontal wheel has its flag');
  Reply.PopNumber(1);
  Check(Reply.PopNumber(2) = $0100, 'the right wheel wins over the left wheel');
  LoadEvent(Srv.MouseEvent(2, 3, 0, mwUp or mwRight, False, False, 0));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(1) = MOUSE_WHEELED, 'the vertical wheel hides the horizontal wheel');
  LoadEvent(Srv.MouseEvent(2, 3, mbRightButton or mbMiddleButton, 0, True, True, kbShift));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(1) = (MOUSE_MOVED or DOUBLE_CLICK), 'moved and double give both flags');
  Check(Reply.PopNumber(1) = SHIFT_PRESSED, 'Shift in the mouse key state');
  Check(Reply.PopNumber(2) = (RIGHTMOST_BUTTON_PRESSED or FROM_LEFT_2ND_BUTTON_PRESSED),
    'the right and the middle button are bits 2 and 4');
  LoadEvent(Srv.MouseEvent(2, 3, 0, 0, False, False, kbCtrlShift or kbAltShift));
  Reply.PopNumber(1);
  Reply.PopNumber(1);
  Check(Reply.PopNumber(1) = (LEFT_CTRL_PRESSED or LEFT_ALT_PRESSED), 'Ctrl and Alt give the left bits');
  Ask(Req(Num(0, 8), 'x', 0));
  LoadEvent(Srv.MouseEvent(7, 8, mbLeftButton, 0, False, False, 0));
  Check(Reply.PopNumber(1) = Ord('M'), 'without compact input the mouse event is the long one');
  Check(Reply.PopNumber(4) = 0, 'the long mouse event has the flags');
  Check(Reply.PopNumber(4) = 0, 'the long mouse event has the key state');
  Check(Reply.PopNumber(4) = 1, 'the long mouse event has the buttons');
  Check((Reply.PopNumber(2) = 8) and (Reply.PopNumber(2) = 7), 'the long mouse event has the row and the column');
end;

procedure TestOpen;
var
  Status: Integer;
  Features: QWord;
begin
  NewServer(vcaShare, True);
  Check(Srv.Body(Apc(EscCh + '_far2l:MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWYgAAAAb2MB' + BelCh)) =
    EscCh + '_far2lAwAAAAAAAAABAQ==' + BelCh, 'CLIP_OPEN with vcaShare gives the features 3, status 1 and the ID');
  Check((Host.Asked = 1) and (Host.AskedId = ClientA), 'the host was asked once with exactly the client ID');
  OpenFor(ClientA, 21, Status);
  Check(Status = 0, 'opening again while open gives status 0');
  Check(Host.Asked = 1, 'the host is not asked again while the clipboard is open');
  LoadReply(ClipAsk(PStr(ClientA), 'o', 22));
  Reply.PopNumber(1);
  Reply.PopNumber(1);
  Features := Reply.PopNumber(8);
  Check(Features = 3, 'the features are 3 also on a failed open');
  OpenFor('short', 23, Status);
  Check(Status = 0, 'an open with an ID that is not valid gives status 0');
  Check(Host.Asked = 1, 'an ID that is not valid is not asked');
  Check(ClipAsk(PStr(ClientA), 'o', 0) = '', 'an open with ID 0 gets no reply');
end;

procedure TestClipboardData;
var
  Size, DataId: QWord;
  Data: AnsiString;
  Block: LongWord;
  Item: AnsiString;
begin
  NewServer(vcaShare, True);
  VtClipSetItems(NoItems);
  Check(ClipAsk(Num(VtCfText, 4), 'a', 1) <> '', 'CLIP_ISAVAIL gets a reply on a clipboard that is not open');
  LoadReply(ClipAsk(Num(VtCfText, 4), 'a', 1));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(1) = 0, 'CLIP_ISAVAIL for cfText is 0 on an empty clipboard');
  LoadReply(ClipAsk(Num(VtCfText, 4) , 's', 2));
  Check(Reply.Size = 1, 'a request with too short a stack gets the ID alone');
  Check(Host.Asked = 0, 'nothing was asked yet');
  LoadReply(SetData(VtCfText, 'hello', 2));
  Check(Reply.PopNumber(1) = 2, 'SETDATA on a clipboard that is not open ends with the ID');
  Check(Reply.PopSigned(1) = -1, 'SETDATA on a clipboard that is not open gives status -1');
  Check(Reply.Size = 0, 'SETDATA on a clipboard that is not open gives nothing more');
  Check(VtClipGetText = '', 'SETDATA on a clipboard that is not open stores nothing');
  Check(ClipAsk(PStr(ClientA), 'o', 1) <> '', 'the clipboard is opened');
  LoadReply(SetData(VtCfText, 'hello', 2));
  Check(Reply.PopNumber(1) = 2, 'the SETDATA reply ends with the ID');
  Check(Reply.PopSigned(1) = 1, 'SETDATA of cfText hello gives status 1');
  Check(Reply.PopNumber(8) = VtClipDataId(VtCfText, 'hello'), 'SETDATA gives the data ID of hello');
  Check(Reply.Size = 0, 'SETDATA leaves nothing more in the reply');
  Check(VtClipGetText = 'hello', 'the clipboard text is hello');
  GetAt(VtCfText, 200000, Size, Data, DataId);
  Check((Size = 0) and (DataId = 0) and (Data = '') and (Reply.Size = 0),
    'GETDATA before any gesture gives size 0 and ID 0');
  Srv.PasteGesture;
  GetAt(VtCfText, 200000, Size, Data, DataId);
  Check((Size = 5) and (Data = 'hello'), 'GETDATA after a gesture gives 5 bytes hello');
  Check(DataId = VtClipDataId(VtCfText, 'hello'), 'GETDATA gives the data ID of hello');
  Check(Reply.Size = 0, 'GETDATA leaves nothing more in the reply');
  Check(VtClipDataId(VtCfText, 'hello') <> 0, 'a data ID is never 0');
  Check(VtClipDataId(VtCfText, 'ab' + #0 + 'cd') = VtClipDataId(VtCfText, 'ab'), 'the data ID of text ends at a NUL');
  Check(VtClipDataId(2, 'ab' + #0 + 'cd') <> VtClipDataId(2, 'ab'), 'the data ID of another format counts the NUL');
  LoadReply(ClipAsk(Num(VtCfText, 4), 'a', 1));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(1) = 1, 'CLIP_ISAVAIL for cfText is 1');
  LoadReply(ClipAsk('', 'e', 1));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = 1, 'CLIP_EMPTY gives status 1');
  Check(VtClipGetText = '', 'CLIP_EMPTY empties the text of the clipboard');
  Check(not VtClipHasItem(VtCfText), 'CLIP_EMPTY leaves no text item');
  LoadReply(SetData(VtCfText, 'vert' + #0, 4));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = 1, 'SETDATA of vert and a NUL gives status 1');
  Block := VtVerticalBlockFormat;
  LoadReply(SetData(Block, #0#0#0#0, 4));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = 1, 'SETDATA of the vertical block format gives status 1');
  Check(VtClipGetText = 'vert', 'the text is cut at its NUL');
  Check(VtClipGetItem(Block, Item) and (Item = #0#0#0#0), 'the vertical block item is on the clipboard');
  Srv.PasteGesture;
  GetAt(VtCfUnicodeText, 200000, Size, Data, DataId);
  Check(Size = 16, 'GETDATA of cfUnicodeText gives 16 bytes');
  Check(Data = Wide('vert'), 'GETDATA of cfUnicodeText gives the UTF-32 of vert');
  Check(DataId = VtClipDataId(VtCfUnicodeText, Wide('vert')), 'the data ID of cfUnicodeText is over the UTF-32 bytes');
  LoadReply(SetData(VtCfUnicodeText, Wide('vert'), 5));
  Reply.PopNumber(1);
  Reply.PopSigned(1);
  Check(Reply.PopNumber(8) = DataId, 'the same text has the same data ID when it is set and when it is read');
  LoadReply(SetData(VtCfUnicodeText, CyrillicWide, 6));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = 1, 'SETDATA of cfUnicodeText gives status 1');
  Check(VtClipGetText = CyrillicBytes, 'the Unicode text replaces the text as UTF-8');
  Check(Length(VtClipGetText) = 6, 'the Cyrillic word is 6 bytes of UTF-8');
  Check(VtClipGetItem(Block, Item) and (Item = #0#0#0#0), 'the vertical block item stays');
  Check(VtClipHasItem(VtCfUnicodeText), 'the Unicode text format is available when the text is');
end;

procedure TestChunks;
var
  Status: Integer;
  Block256: AnsiString;
  Size, DataId: QWord;
  Data: AnsiString;
begin
  NewServer(vcaShare, True);
  VtClipSetItems(NoItems);
  Block256 := StringOfChar('x', 256);
  OpenFor(ClientA, 1, Status);
  Check(ClipAsk(Block256 + Num(1, 2), 'S', 0) = '', 'a chunk with ID 0 gets no reply');
  ClipAsk(Num(0, 2), 'S', 0);
  Check(ClipAsk(Block256 + Num(1, 2), 'S', 34) = IdOnly(34), 'a chunk with ID 34 gets the ID alone');
  LoadReply(SetData(VtCfText, 'end', 7));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = 1, 'SETDATA after a chunk gives status 1');
  Check(Reply.PopNumber(8) = VtClipDataId(VtCfText, Block256 + 'end'), 'the data ID is over the chunk and the data');
  Check(VtClipGetText = Block256 + 'end', 'the clipboard has the chunk followed by end');
  ClipAsk(Block256 + Num(1, 2), 'S', 0);
  ClipAsk(Num(0, 2), 'S', 0);
  SetData(VtCfText, 'only', 8);
  Check(VtClipGetText = 'only', 'a chunk of count 0 drops the pending chunks');
  ClipAsk(Block256 + Num(1, 2), 'S', 0);
  OpenFor(ClientA, 9, Status);
  Check(Status = 0, 'an open that is refused because the clipboard is open gives status 0');
  SetData(VtCfText, 'end', 8);
  Check(VtClipGetText = Block256 + 'end', 'a refused open leaves the chunks of the open session');
  Check(ClipAsk(Num(3, 2), 'S', 35) = IdOnly(35), 'a chunk whose count promises too many bytes gets the ID alone');
  Srv.PasteGesture;
  GetAt(VtCfText, 200000, Size, Data, DataId);
  Check(Size = 259, 'the text of 259 bytes is read');
end;

procedure TestClose;
var
  Size, DataId: QWord;
  Data: AnsiString;
begin
  NewServer(vcaShare, True);
  Srv.PasteGesture;
  ClipAsk(PStr(ClientA), 'o', 1);
  SetData(VtCfText, 'hello', 2);
  Check(ClipAsk('', 'c', 0) = '', 'CLIP_CLOSE with ID 0 gets no reply');
  GetAt(VtCfText, 200000, Size, Data, DataId);
  Check(Size = $FFFFFFFF, 'GETDATA after CLIP_CLOSE gives $FFFFFFFF');
  Check(Reply.Size = 0, 'GETDATA after CLIP_CLOSE gives nothing more');
  LoadReply(SetData(VtCfText, 'again', 3));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = -1, 'SETDATA after CLIP_CLOSE gives status -1');
  Check(Reply.Size = 0, 'SETDATA after CLIP_CLOSE gives nothing more');
  LoadReply(ClipAsk('', 'c', 4));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = -1, 'CLIP_CLOSE of a closed clipboard gives status -1');
  ClipAsk(PStr(ClientA), 'o', 1);
  Check(Host.Asked = 1, 'a client shared for the activation is not asked again after a close');
  LoadReply(ClipAsk('', 'c', 5));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = 1, 'CLIP_CLOSE of an open clipboard gives status 1');
  LoadReply(ClipAsk('', 'e', 6));
  Reply.PopNumber(1);
  Check(Reply.PopSigned(1) = -1, 'CLIP_EMPTY of a closed clipboard gives status -1');
  GetAt(VtCfText, 200000, Size, Data, DataId);
  Check(Size = $FFFFFFFF, 'GETDATA of a closed clipboard still gives $FFFFFFFF');
end;

procedure TestGestureWindow;
var
  Size, DataId: QWord;
  Data: AnsiString;
  Status: Integer;
begin
  NewServer(vcaShare, True);
  OpenFor(ClientA, 1, Status);
  SetData(VtCfText, 'hello', 2);
  TestNow := 200000;
  Srv.PasteGesture;
  GetAt(VtCfText, 204000, Size, Data, DataId);
  Check(Size = 5, 'the read at 204000 gives 5 bytes');
  GetAt(VtCfText, 208000, Size, Data, DataId);
  Check(Size = 5, 'the read at 208000 gives 5 bytes');
  GetAt(VtCfText, 212000, Size, Data, DataId);
  Check(Size = 5, 'the read at 212000 gives 5 bytes');
  GetAt(VtCfText, 216000, Size, Data, DataId);
  Check(Size = 5, 'the read at 216000 gives 5 bytes');
  GetAt(VtCfText, 217500, Size, Data, DataId);
  Check(Size = 0, 'the read at 217500 gives size 0');
  TestNow := 217000;
  Srv.PasteGesture;
  GetAt(VtCfText, 222000, Size, Data, DataId);
  Check(Size = 5, 'an age of exactly 5000 is still allowed');
  GetAt(VtCfText, 227001, Size, Data, DataId);
  Check(Size = 0, 'an age above 5000 is refused');
  NewServer(vcaShare, True);
  OpenFor(ClientA, 1, Status);
  SetData(VtCfText, 'hello', 2);
  TestNow := 300000;
  LoadReply(ClipAsk(Num(VtCfText, 4), 'i', 3));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(8) = 0, 'GETDATAID without a gesture gives 0');
  Srv.PasteGesture;
  LoadReply(ClipAsk(Num(VtCfText, 4), 'i', 3));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(8) = VtClipDataId(VtCfText, 'hello'), 'GETDATAID after a gesture gives the data ID of hello');
  TestNow := 304000;
  ClipAsk(Num(VtCfText, 4), 'i', 3);
  TestNow := 308000;
  ClipAsk(Num(VtCfText, 4), 'i', 3);
  LoadReply(ClipAsk(Num(VtCfText, 4), 'i', 3));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(8) = 0, 'GETDATAID never extends the gesture');
  TestNow := 304000;
  Srv.PasteGesture;
  GetAt(2, 308000, Size, Data, DataId);
  Check((Size = 0) and (DataId = 0), 'GETDATA of a format that is not there gives size 0 and ID 0');
  GetAt(VtCfText, 312500, Size, Data, DataId);
  Check(Size = 5, 'a read that failed on its format used an extension of the gesture');
end;

procedure TestRegister;
var
  Number: QWord;
begin
  NewServer(vcaShare, True);
  Check(Ask(Req(PStr('FAR_VerticalBlock_Unicode'), 'rc', 4)) = EscCh + '_far2lAMAAAAQ=' + BelCh,
    'CLIP_REGISTER_FORMAT for the vertical block format gives $C000');
  LoadReply(Ask(Req(PStr('FAR_VerticalBlock_Unicode'), 'rc', 4)));
  Reply.PopNumber(1);
  Number := Reply.PopNumber(4);
  Check(Number = VtVerticalBlockFormat, 'the same name gives the same number');
  LoadReply(Ask(Req(PStr('Other_Format'), 'rc', 4)));
  Reply.PopNumber(1);
  Check(Reply.PopNumber(4) = $C001, 'another name gives the next number');
end;

procedure TestAuthorisation;
var
  Status: Integer;
begin
  { vcaBlock }
  NewServer(vcaBlock, True);
  OpenFor(ClientA, 1, Status);
  Check(Status = 0, 'vcaBlock gives status 0');
  OpenFor(ClientA, 1, Status);
  Check(Status = 0, 'vcaBlock gives status 0 again');
  Check(Host.Asked = 2, 'vcaBlock is not remembered, so the host is asked each time');
  { vcaRemote }
  NewServer(vcaRemote, True);
  OpenFor(ClientA, 1, Status);
  Check(Status = -1, 'vcaRemote gives status -1');
  { vcaAlways }
  NewServer(vcaAlways, True);
  Check(not FileExists(AuthPath), 'the file of the clients does not exist before');
  OpenFor(ClientA, 1, Status);
  Check(Status = 1, 'vcaAlways gives status 1');
  ClipAsk('', 'c', 0);
  Check(FileExists(AuthPath), 'the file AuthedsPath exists after vcaAlways');
  OpenFor(ClientB, 1, Status);
  ClipAsk('', 'c', 0);
  Check(Host.Asked = 2, 'each new client is asked');
  Srv.Body('far2l0');
  Check(not Srv.Active, 'far2l0 makes the server inactive');
  Check(Host.TitleCalls > 0, 'far2l0 calls the titles of the host');
  Check(Length(Host.GotTitles) = 0, 'far2l0 clears the titles of the host');
  Check(Ask(Req('', 'e', 8)) = '', 'a request after far2l0 gets no answer');
  Srv.Body('far2l1');
  Host.Asked := 0;
  Host.Answer := vcaBlock;
  OpenFor(ClientA, 1, Status);
  Check((Status = 1) and (Host.Asked = 0), 'a client saved in the file is let in without a question');
  ClipAsk('', 'c', 0);
  { vcaShare lasts for one activation }
  NewServer(vcaShare, True);
  Srv.AuthedsPath := '';
  OpenFor(ClientB, 1, Status);
  Check(Status = 1, 'vcaShare gives status 1');
  ClipAsk('', 'c', 0);
  Srv.Body('far2l0');
  Srv.Body('far2l1');
  Host.Asked := 0;
  Host.Answer := vcaBlock;
  OpenFor(ClientB, 1, Status);
  Check((Status = 0) and (Host.Asked = 1), 'a client shared for the previous activation is asked again');
end;

procedure TestStop;
var
  Ev: TEvent;
begin
  NewServer(vcaShare, True);
  Ask(Req(Num(3, 8), 'x', 0));
  Ask(Req(Num(50, 1), 'h', 0));
  Srv.Body('far2l#user@host');
  Srv.Body('far2l0');
  Check(Srv.CursorPercent = -1, 'Stop forgets the cursor height');
  Check(not Srv.CompactInput, 'Stop clears the features');
  Check(Srv.Resized(90, 40) = '', 'a size event is not sent after Stop');
  MakeKey(Ev, $1E61, 0, 'a');
  Check(Srv.KeyEvent(Ev) = '', 'a key event is empty after Stop');
  Srv.Body('far2l0');
  Check(Host.TitleCalls = 1, 'Stop does nothing when the server is not active');
  Srv.Body('far2l1');
  Check(Srv.Resized(91, 40) = '', 'the features are zero after a new activation');
end;

procedure TestIdentity;
var
  Status: Integer;
begin
  NewServer(vcaShare, False);
  Srv.Body('far2l#user@host');
  Srv.Body('far2l#other');
  Srv.Body('far2l1');
  OpenFor(ClientA + 'a', 1, Status);
  Check(Status = 1, 'an open with a host identity gives status 1');
  Check(Host.Asked = 1, 'the host was asked once');
  Check(Host.AskedId = 'user@host:' + ClientA + 'a', 'the ID the host got has the identity in front');
  ClipAsk('', 'c', 0);
  Srv.Body('far2l0');
  Srv.Body('far2l1');
  Host.Answer := vcaBlock;
  OpenFor(ClientA, 1, Status);
  Check(Status = 0, 'the file does not let in an ID without its identity');
  Check(Host.AskedId = 'user@host:' + ClientA, 'the identity stays over Stop');
end;

procedure TestClient;
var
  Id: Byte;
  Block: LongWord;
  Item: AnsiString;
begin
  NewServer(vcaShare, False);
  Srv.AuthedsPath := '';
  VtClipSetItems(NoItems);
  Link := TLink.Create;
  Client := TFar2lClient.Create(@Link.Send);
  Client.OnAnswer := @Link.GotAnswer;
  try
    Client.Announce;
    Pump;
    Check(Client.Acknowledged, 'the client sees the activation acknowledged');
    Check(Srv.Active, 'the activation of the client makes the server active');
    Client.Submit(RequestClipRegister('FAR_VerticalBlock_Unicode'), True, Id);
    Pump;
    Block := VtVerticalBlockFormat;
    Check(LastAnswer.Number = Block, 'the client gets the number of the server for the vertical block format');
    Client.Submit(RequestClipOpen(ClientA), True, Id);
    Pump;
    Check(LastAnswer.Valid and (LastAnswer.Status = 1), 'the client opens the clipboard');
    Check(Client.ServerClipFeatures = 3, 'the client learns the features of the server clipboard');
    Client.PutClipboardData(VtCfUnicodeText, CyrillicWide, Id);
    Pump;
    Check(LastAnswer.Status = 1, 'the client sets the Unicode text');
    Client.PutClipboardData(Block, #0#0#0#0, Id);
    Pump;
    Check(LastAnswer.Status = 1, 'the client sets the vertical block item');
    Check(VtClipGetText = CyrillicBytes, 'the text of the client is on the clipboard');
    Check(VtClipGetItem(Block, Item) and (Item = #0#0#0#0), 'the item of the client is on the clipboard');
    Client.Submit(RequestClipFormat(rqClipGetData, VtCfText), True, Id);
    Pump;
    Check(LastAnswer.Number = 0, 'the client gets nothing of cfText before a gesture');
    Srv.PasteGesture;
    Client.Submit(RequestClipFormat(rqClipGetData, VtCfUnicodeText), True, Id);
    Pump;
    Check(LastAnswer.Data = CyrillicWide, 'the client gets the Unicode text after a gesture');
    Client.Submit(RequestClipFormat(rqClipGetData, Block), True, Id);
    Pump;
    Check(LastAnswer.Data = #0#0#0#0, 'the client gets the four zero bytes of the registered format');
    Client.Submit(RequestClipFormat(rqClipIsAvail, VtCfText), True, Id);
    Pump;
    Check(LastAnswer.Flag, 'the client sees the text as available');
    Client.Submit(PlainRequest(rqMaxSize), True, Id);
    Pump;
    Check((LastAnswer.Width = 200) and (LastAnswer.Height = 50), 'the client gets 200 columns by 50 rows');
    Client.Submit(PlainRequest(rqPalette), True, Id);
    Pump;
    Check(LastAnswer.Bits = 24, 'the client gets the colour depth 24');
    Client.Submit(RequestFKeyTitles(['a', 'b'], 0), True, Id);
    Pump;
    Check(LastAnswer.Flag, 'the client sees the titles accepted');
    Check(Host.Joined = 'a|b|' + StringOfChar('|', 10), 'the host got a, b and ten empty titles');
  finally
    Client.Free;
    Link.Free;
  end;
end;

procedure Cleanup;
begin
  DeleteFile(AuthPath);
  RemoveDir(ExtractFileDir(AuthPath));
  RemoveDir(ExtractFileDir(ExtractFileDir(AuthPath)));
end;

begin
  Reply := TF2lStack.Create;
  TempDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'vtext_' + IntToStr(GetProcessID);
  AuthPath := TempDir + PathDelim + 'sub' + PathDelim + 'autheds';
  Cleanup;
  TestBaseHost;
  TestActivation;
  TestSimpleRequests;
  TestFKeys;
  TestImage;
  TestFeaturesAndSize;
  TestEvents;
  TestOpen;
  TestRegister;
  TestClipboardData;
  TestChunks;
  TestClose;
  TestGestureWindow;
  TestAuthorisation;
  TestStop;
  TestIdentity;
  TestClient;
  Cleanup;
  Srv.Free;
  Host.Free;
  Reply.Free;
  Done;
end.
