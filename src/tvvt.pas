{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/vtermemu.h, source/tvterm-core/vtermemu.cc
  See COPYRIGHT.tvterm.

  The terminal emulator of a client program: VTermEmulator reads the bytes that the client writes, drives a TVtScreen
  with them and writes the answers to the client through a Writer; the events of the user become the bytes of the
  keys, the mouse, the paste and the focus (TvVtKeys). The C++ gets its parser from a library that is not part of the
  sources, so the parser is a byte-driven state machine here: the bytes are decoded as UTF-8 into code points, and
  the code points drive the states (ground, escape, escape with intermediates, CSI, a CSI that is skipped up to its
  final character, and the strings of OSC, DCS, SOS, PM and APC). The controls of the 8-bit set are the code points
  U+0080 to U+009F. CAN and SUB cancel a sequence, ESC inside a sequence starts a new one, and a string ends at ST
  (the code point U+009C or ESC followed by a backslash), at BEL, or at the ESC of a new sequence.

  The titles of OSC 0, 1 and 2 are kept until UpdateState gives them to the state. The factory gives the variables
  TERM and COLORTERM to the client. }
unit TvVt;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvPty, TvVtCore, TvVtScreen, TvVtKeys;

const
  { The number of parameters of a CSI sequence that are kept; the others are dropped. }
  VtMaxParams = 32;

type
  TVtParseState = (sqGround, sqEscape, sqEscInter, sqCsi, sqCsiSkip, sqString);

  { The character sets that can be designated: US ASCII, DEC special graphics and the UK set. }
  TVtGraphicSet = (gsAscii, gsGraphics, gsUk);
  TVtGraphicSets = array[0..3] of TVtGraphicSet;

  { The modes that SM, RM, DECSET and DECRST can change. }
  TVtModeId = (
    tmNone, tmCursorKeys, tmKeypad, tmColumns, tmReverse, tmOrigin, tmWrap, tmBlink, tmShow,
    tmMouseX10, tmMouseNormal, tmMouseButton, tmMouseAny, tmFocus, tmUtf8Mouse, tmSgrMouse,
    tmAlt47, tmAlt1047, tmSaveCursor, tmAlt1049, tmPaste, tmInsert, tmNewLine
  );

  { What DECSC saves besides the cursor and the pen of the screen. }
  TVtSavedCursor = record
    Origin: Boolean;
    Shift: Integer;
    Sets: TVtGraphicSets;
    Fg, Bg: TVtColor;
    Attrs: TVtAttrs;
  end;

  VTermEmulatorFactory = class(TerminalEmulatorFactory)
  public
    function Make(const Size: TPoint; ClientDataWriter: Writer): TerminalEmulator; override;
    function GetCustomEnvironment: TEnvironmentVarSpan; override;
  end;

  VTermEmulator = class(TerminalEmulator)
  private
    FScreen: TVtScreen;
    FOut: Writer;
    FModes: TVtInputModes;
    FMouse: TVtMouseState;
    FTitle, FRun: AnsiString;
    FTitleChanged: Boolean;
    { the parser }
    FNeed: Integer;
    FAcc, FLeast, FLastGraphic: Cardinal;
    FState: TVtParseState;
    FValues: array[0..Pred(VtMaxParams)] of Integer;
    FSubFlags: packed array[0..Pred(VtMaxParams)] of Boolean;
    FCount: Integer;
    FCurValue: Integer;
    FCurSub: Boolean;
    FSeen: Boolean;
    FPrefix: AnsiChar;
    FInter: AnsiString;
    FKind: AnsiChar;
    FBuffer: AnsiString;
    { the modes and the pen that the client sets }
    FSets: TVtGraphicSets;
    FGl: Integer;
    FOrigin, FInsert, FNewLine, FReverse: Boolean;
    FFg, FBg: TVtColor;
    FAttrs: TVtAttrs;
    FSaved: TVtSavedCursor;

    procedure Reply(const Bytes: AnsiString);
    procedure ResetParser;
    procedure ResetCsi;
    procedure ResetPersonality;
    procedure ResetPenState;
    procedure ResetTabStops;
    procedure HandleMouse(const Ev: TvVtCore.MouseEvent);

    procedure FeedBytes(Data: PAnsiChar; Size: SizeUInt);
    procedure FeedByte(B: Byte);
    procedure StartMulti(Need: Integer; Acc, Least: Cardinal);
    procedure FeedCode(Cp: Cardinal);
    procedure GroundCode(Cp: Cardinal);
    procedure EscapeCode(Cp: Cardinal);
    procedure CsiCode(Cp: Cardinal);
    procedure StringCode(Cp: Cardinal);
    procedure StartEscape;
    procedure CancelSequence;
    procedure HandleC1(Cp: Cardinal);
    procedure BeginString(Kind: AnsiChar);
    procedure EndString;
    procedure RunOsc(const Body: AnsiString);
    procedure RunDcs(const Body: AnsiString);
    function DecrqssAnswer(const Req: AnsiString): AnsiString;

    procedure FlushRun;
    procedure Control(Cp: Cardinal);
    procedure LineFeedMode;
    procedure NextLine;
    procedure Print(Cp: Cardinal);
    procedure PrintMapped(Cp: Cardinal);
    function MapCharset(Cp: Cardinal): Cardinal;
    procedure RepeatGraphic(Num: Integer);

    procedure EscDispatch(const Inter: AnsiString; Term: AnsiChar);
    procedure EscPlain(Term: AnsiChar);
    procedure DesignateSet(Slot: Integer; Term: AnsiChar);
    procedure AlignmentPattern;

    procedure CommitParam;
    procedure NextParam(IsSub: Boolean);
    procedure AddDigit(Digit: Integer);
    function ParamAt(Idx, Fallback: Integer): Integer;
    function Positive(Idx: Integer): Integer;
    function RowTarget(Row: Integer): Integer;

    procedure CsiDispatch(Term: AnsiChar);
    procedure CsiPlain(Term: AnsiChar);
    procedure CsiOther(const Sel: AnsiString);
    procedure CsiPlace(Term: AnsiChar);
    procedure CsiEdit(Term: AnsiChar);
    procedure CsiErase(Term: AnsiChar);
    procedure CursorStep(Which, Num: Integer);
    procedure CursorReport(IsPrivate: Boolean);
    procedure StatusReport;
    procedure PrivateStatus;
    procedure WindowReport;
    procedure TabClear;
    procedure SetMargins;
    procedure CursorStyle;

    procedure ApplySgr;
    procedure ApplySgrCode(Code: Integer);
    procedure ReadExtendedColor(var Idx: Integer; Foreground: Boolean);
    function ColonColor(var Idx: Integer; out Col: TVtColor): Boolean;
    function SemicolonColor(var Idx: Integer; out Col: TVtColor): Boolean;

    procedure CsiModes(Enable, IsPrivate: Boolean);
    procedure AskMode(IsPrivate: Boolean);
    procedure ApplyMode(Id: TVtModeId; Enable: Boolean);
    function FlagOf(Id: TVtModeId): PBoolean;
    function ModeIsSet(Id: TVtModeId): Boolean;
    procedure SetMouseEncoding(Id: TVtModeId; Enable: Boolean);
    procedure SwitchScreen(Enter, WithCursor: Boolean);
    procedure SaveState;
    procedure RestoreState;
    procedure SoftReset;
    procedure FullReset;
  public
    constructor Create(const Size: TPoint; ClientDataWriter: Writer);
    destructor Destroy; override;
    procedure HandleEvent(const Event: TerminalEvent); override;
    procedure UpdateState(State: TerminalState); override;
    { The screen that the emulator drives. }
    function Screen: TVtScreen;
  end;

implementation

uses
  SysUtils, Math, TvEvents, TvClip, TvUtf8;

const
  CsiIntro = #27'[';
  DcsIntro = #27'P';
  StringEnd = #27'\';
  PrimaryAnswer = #27'[?62;22c';
  OscLimit = 4096;
  DcsLimit = 64;

  CustomEnvironment: array[0..1] of EnvironmentVar = (
    (Name: 'TERM'; Value: 'xterm-256color'),
    (Name: 'COLORTERM'; Value: 'truecolor')
  );

  { The numbers of the private modes and the modes that they stand for, in the same order. }
  PrivateNumbers: array[0..19] of Integer = (
    1, 66, 25, 12, 7, 6, 5, 3, 2004, 1004,
    9, 1000, 1002, 1003, 1005, 1006, 47, 1047, 1048, 1049
  );
  PrivateModes: array[0..19] of TVtModeId = (
    tmCursorKeys, tmKeypad, tmShow, tmBlink, tmWrap, tmOrigin, tmReverse, tmColumns, tmPaste, tmFocus,
    tmMouseX10, tmMouseNormal, tmMouseButton, tmMouseAny, tmUtf8Mouse, tmSgrMouse,
    tmAlt47, tmAlt1047, tmSaveCursor, tmAlt1049
  );

  { The parameter of SGR that sets an attribute and the one that clears it. }
  AttrCodes: array[TVtAttr] of Integer = (1, 3, 4, 5, 7, 9, 8);
  AttrOffCodes: array[TVtAttr] of Integer = (22, 23, 24, 25, 27, 29, 28);

  { The code points of DEC special graphics for the characters $5F to $7E, four hexadecimal digits for each. }
  GraphicsHex =
    '00A025C625922409240C240D240A00B0' +
    '00B12424240B25182510250C2514253C' +
    '23BA23BB250023BC23BD251C25242534' +
    '252C25022264226503C0226000A300B7';

{ Routines of the unit }

function Utf8Of(Cp: Cardinal): AnsiString;
var
  Bytes: TUtf8Bytes;
  Len, K: Integer;
begin
  if Cp < $80 then
  begin
    Result := AnsiChar(Cp);
    Exit;
  end;
  Len := Utf32To8(Cp, Bytes);
  SetLength(Result, Len);
  for K := 0 to Len - 1 do
    Result[K + 1] := AnsiChar(Bytes[K]);
end;

function GraphicsCode(Cp: Cardinal): Cardinal;
var
  Start: Integer;
begin
  Start := Integer(Cp - $5F) * 4 + 1;
  Result := Cardinal(StrToInt('$' + Copy(GraphicsHex, Start, 4)));
end;

function LookupMode(IsPrivate: Boolean; Num: Integer): TVtModeId;
var
  K: Integer;
begin
  Result := tmNone;
  if IsPrivate then
  begin
    for K := 0 to High(PrivateNumbers) do
      if PrivateNumbers[K] = Num then
        Result := PrivateModes[K];
  end
  else if Num = 4 then
    Result := tmInsert
  else if Num = 20 then
    Result := tmNewLine;
end;

{ A parameter as the value of a colour component or an index: 0 to 255. }
function Channel(Val: Integer): Byte;
begin
  if Val < 0 then
    Result := 0
  else
    Result := Byte(Min(Val, 255));
end;

{ The part of an SGR report for a colour, with its leading semicolon, or nothing for the default colour. }
function ColorSgr(const Col: TVtColor; Base, Bright, Ext: Integer): AnsiString;
begin
  case Col.Kind of
    vcIndexed:
      if Col.Idx < 8 then
        Result := ';' + IntToStr(Base + Col.Idx)
      else if Col.Idx < 16 then
        Result := ';' + IntToStr(Bright + Col.Idx - 8)
      else
        Result := ';' + IntToStr(Ext) + ';5;' + IntToStr(Col.Idx);
    vcRGB:
      Result := ';' + IntToStr(Ext) + ';2;' + IntToStr(Col.Red) + ';' + IntToStr(Col.Green) + ';' +
        IntToStr(Col.Blue);
  else
    Result := '';
  end;
end;

{ The longest prefix of a text that ends at the boundary of a character and has at most 255 bytes, the size that
  the text of TClipboard can hold. }
function FitClipboard(const Whole: AnsiString): AnsiString;
var
  Cut: Integer;
begin
  if Length(Whole) <= 255 then
  begin
    Result := Whole;
    Exit;
  end;
  Cut := 255;
  while (Cut > 0) and ((Byte(Whole[Cut + 1]) and $C0) = $80) do
    Dec(Cut);
  Result := Copy(Whole, 1, Cut);
end;

{ VTermEmulatorFactory }

function VTermEmulatorFactory.Make(const Size: TPoint; ClientDataWriter: Writer): TerminalEmulator;
begin
  Result := VTermEmulator.Create(Size, ClientDataWriter);
end;

function VTermEmulatorFactory.GetCustomEnvironment: TEnvironmentVarSpan;
begin
  Result.Data := @CustomEnvironment[0];
  Result.Size := Length(CustomEnvironment);
end;

{ VTermEmulator: construction and the events }

constructor VTermEmulator.Create(const Size: TPoint; ClientDataWriter: Writer);
begin
  inherited Create;
  FOut := ClientDataWriter;
  { The screen needs a size of at least 1. }
  FScreen := TVtScreen.Create(Max(Size.X, 1), Max(Size.Y, 1));
  { The cursor of the screen does not blink until the client asks for it. }
  FScreen.SetCursorBlink(False);
  FMouse := NewMouseState;
  FTitle := '';
  FTitleChanged := False;
  ResetParser;
  ResetPersonality;
end;

destructor VTermEmulator.Destroy;
begin
  FScreen.Free;
  inherited Destroy;
end;

function VTermEmulator.Screen: TVtScreen;
begin
  Result := FScreen;
end;

procedure VTermEmulator.Reply(const Bytes: AnsiString);
var
  Buf: array of Char;
begin
  if (Bytes = '') or (FOut = nil) then
    Exit;
  SetLength(Buf, Length(Bytes));
  Move(Bytes[1], Buf[0], Length(Bytes));
  FOut.Write(Buf);
end;

procedure VTermEmulator.HandleMouse(const Ev: TvVtCore.MouseEvent);
begin
  if FScreen.MouseEnabled then
    Reply(ProcessMouse(Ev.What, Ev.Mouse, FModes, FMouse))
  else if FScreen.AltScreen and (Ev.What = evMouseWheel) then
    Reply(WheelToArrow(Ev.Mouse.Wheel, FModes))
  else if Ev.What = evMouseWheel then
    FScreen.HandleScrollbackWheel(Ev.Mouse.Wheel);
end;

procedure VTermEmulator.HandleEvent(const Event: TerminalEvent);
begin
  case Event.Type_ of
    TerminalEventType.KeyDown:
      begin
        Reply(ProcessKey(Event.KeyDown, FModes));
        FScreen.History.FollowTerminal;
      end;
    TerminalEventType.Mouse:
      HandleMouse(Event.Mouse);
    TerminalEventType.ClientDataRead:
      FeedBytes(Event.ClientDataRead.Data, Event.ClientDataRead.Size);
    TerminalEventType.ViewportResize:
      FScreen.Resize(Event.ViewportResize.X, Event.ViewportResize.Y);
    TerminalEventType.FocusChange:
      Reply(ProcessFocus(Event.FocusChange.FocusEnabled, FModes));
    TerminalEventType.ScrollBackOffsetChange:
      FScreen.History.SetOffset(Event.ScrollBackOffsetChange.Offset);
    TerminalEventType.CopySelection:
      TClipboard.SetText(FitClipboard(FScreen.CopySelection(Event.CopySelection.Selection)));
  end;
end;

procedure VTermEmulator.UpdateState(State: TerminalState);
begin
  FScreen.UpdateState(State);
  if FTitleChanged then
  begin
    FTitleChanged := False;
    State.TitleChanged := True;
    State.Title.Clear;
    if FTitle <> '' then
      State.Title.Push(PAnsiChar(FTitle), Length(FTitle));
    FTitle := '';
  end;
end;

{ Resets }

procedure VTermEmulator.ResetCsi;
begin
  FCount := 0;
  FCurValue := -1;
  FCurSub := False;
  FSeen := False;
  FPrefix := #0;
  FInter := '';
end;

procedure VTermEmulator.ResetParser;
begin
  FState := sqGround;
  FNeed := 0;
  FAcc := 0;
  FLeast := 0;
  FRun := '';
  FKind := #0;
  FBuffer := '';
  ResetCsi;
end;

procedure VTermEmulator.ResetPenState;
begin
  FFg := DefaultColor;
  FBg := DefaultColor;
  FAttrs := [];
end;

procedure VTermEmulator.ResetPersonality;
var
  K: Integer;
begin
  FModes := DefaultInputModes;
  FOrigin := False;
  FInsert := False;
  FNewLine := False;
  FReverse := False;
  for K := 0 to High(FSets) do
    FSets[K] := gsAscii;
  FGl := 0;
  ResetPenState;
  FLastGraphic := 0;
  FSaved.Origin := False;
  FSaved.Shift := 0;
  FSaved.Sets := FSets;
  FSaved.Fg := FFg;
  FSaved.Bg := FBg;
  FSaved.Attrs := FAttrs;
end;

procedure VTermEmulator.ResetTabStops;
var
  Col, KeepX, KeepY: Integer;
begin
  KeepX := FScreen.CursorX;
  KeepY := FScreen.CursorY;
  FScreen.ClearAllTabStops;
  Col := 0;
  while Col < FScreen.Cols do
  begin
    FScreen.MoveTo(Col, 0);
    FScreen.SetTabStop;
    Inc(Col, 8);
  end;
  FScreen.MoveTo(KeepX, KeepY);
end;

{ Decoding of the bytes and the states of the parser }

procedure VTermEmulator.StartMulti(Need: Integer; Acc, Least: Cardinal);
begin
  FNeed := Need;
  FAcc := Acc;
  FLeast := Least;
end;

procedure VTermEmulator.FeedByte(B: Byte);
begin
  if FNeed > 0 then
  begin
    if (B and $C0) = $80 then
    begin
      FAcc := (FAcc shl 6) or (B and $3F);
      Dec(FNeed);
      if FNeed = 0 then
      begin
        if (FAcc < FLeast) or (FAcc > $10FFFF) or ((FAcc >= $D800) and (FAcc <= $DFFF)) then
          FAcc := $FFFD;
        FeedCode(FAcc);
      end;
      Exit;
    end;
    { The sequence is cut short; the byte is read again as the start of something else. }
    FNeed := 0;
    FeedCode($FFFD);
  end;
  if B < $80 then
    FeedCode(B)
  else if (B >= $C2) and (B <= $DF) then
    StartMulti(1, B and $1F, $80)
  else if (B >= $E0) and (B <= $EF) then
    StartMulti(2, B and $0F, $800)
  else if (B >= $F0) and (B <= $F4) then
    StartMulti(3, B and $07, $10000)
  else
    FeedCode($FFFD);
end;

procedure VTermEmulator.FeedBytes(Data: PAnsiChar; Size: SizeUInt);
var
  K: SizeUInt;
begin
  K := 0;
  while K < Size do
  begin
    FeedByte(Byte(Data[K]));
    Inc(K);
  end;
  FlushRun;
end;

procedure VTermEmulator.FeedCode(Cp: Cardinal);
begin
  if Cp = 27 then
    StartEscape
  else if (Cp = 24) or (Cp = 26) then
    CancelSequence
  else if (Cp >= $80) and (Cp <= $9F) then
    HandleC1(Cp)
  else
    case FState of
      sqGround:
        GroundCode(Cp);
      sqEscape, sqEscInter:
        EscapeCode(Cp);
      sqCsi, sqCsiSkip:
        CsiCode(Cp);
      sqString:
        StringCode(Cp);
    end;
end;

procedure VTermEmulator.StartEscape;
begin
  if FState = sqString then
    EndString;
  FlushRun;
  FState := sqEscape;
  FInter := '';
end;

procedure VTermEmulator.CancelSequence;
begin
  if FState <> sqGround then
  begin
    FState := sqGround;
    FBuffer := '';
  end;
end;

{ A control of the 8-bit set acts as ESC followed by the character 64 below it. }
procedure VTermEmulator.HandleC1(Cp: Cardinal);
begin
  FlushRun;
  if FState = sqString then
    EndString;
  FState := sqGround;
  FInter := '';
  EscDispatch('', AnsiChar(Cp - $40));
end;

procedure VTermEmulator.GroundCode(Cp: Cardinal);
begin
  if Cp < 32 then
    Control(Cp)
  else if Cp <> 127 then
    Print(Cp);
end;

procedure VTermEmulator.EscapeCode(Cp: Cardinal);
begin
  if Cp < 32 then
    Control(Cp)
  else if Cp = 127 then
    Exit
  else if Cp <= $2F then
  begin
    if Length(FInter) < 4 then
      FInter := FInter + AnsiChar(Cp);
    FState := sqEscInter;
  end
  else if Cp <= $7E then
  begin
    FState := sqGround;
    EscDispatch(FInter, AnsiChar(Cp));
  end
  else
    FState := sqGround;
end;

procedure VTermEmulator.CsiCode(Cp: Cardinal);
begin
  if Cp < 32 then
    Control(Cp)
  else if Cp = 127 then
    Exit
  else if Cp > 126 then
    FState := sqGround
  else if Cp >= $40 then
  begin
    if FState = sqCsi then
    begin
      FState := sqGround;
      CsiDispatch(AnsiChar(Cp));
    end
    else
      FState := sqGround;
  end
  else if FState = sqCsiSkip then
    Exit
  else if (Cp >= $30) and (Cp <= $39) then
  begin
    if FInter <> '' then
      FState := sqCsiSkip
    else
      AddDigit(Integer(Cp) - $30);
  end
  else if (Cp = $3A) or (Cp = $3B) then
  begin
    if FInter <> '' then
      FState := sqCsiSkip
    else
      NextParam(Cp = $3A);
  end
  else if Cp >= $3C then
  begin
    if FSeen or (FPrefix <> #0) or (FInter <> '') then
      FState := sqCsiSkip
    else
      FPrefix := AnsiChar(Cp);
  end
  else if Length(FInter) < 3 then
    FInter := FInter + AnsiChar(Cp)
  else
    FState := sqCsiSkip;
end;

procedure VTermEmulator.StringCode(Cp: Cardinal);
var
  Limit: Integer;
begin
  if Cp = 7 then
    EndString
  else if (Cp >= 32) and (Cp <> 127) then
  begin
    if FKind = ']' then
      Limit := OscLimit
    else
      Limit := DcsLimit;
    if Length(FBuffer) < Limit then
      FBuffer := FBuffer + Utf8Of(Cp);
  end;
end;

procedure VTermEmulator.BeginString(Kind: AnsiChar);
begin
  FState := sqString;
  FKind := Kind;
  FBuffer := '';
end;

procedure VTermEmulator.EndString;
var
  Done: AnsiChar;
  Body: AnsiString;
begin
  Done := FKind;
  Body := FBuffer;
  FState := sqGround;
  FBuffer := '';
  if Done = ']' then
    RunOsc(Body)
  else if Done = 'P' then
    RunDcs(Body);
end;

{ OSC Ps ; Pt: the numbers 0, 1 and 2 set the title; the other commands are ignored. }
procedure VTermEmulator.RunOsc(const Body: AnsiString);
var
  Semi, Num, K: Integer;
begin
  Semi := Pos(';', Body);
  if Semi < 2 then
    Exit;
  Num := 0;
  for K := 1 to Semi - 1 do
  begin
    if not (Body[K] in ['0'..'9']) then
      Exit;
    Num := Min(Num * 10 + Ord(Body[K]) - Ord('0'), 9999);
  end;
  if Num <= 2 then
  begin
    FTitle := Copy(Body, Semi + 1, MaxInt);
    FTitleChanged := True;
  end;
end;

{ The only device control string that is answered is the request of a setting (DECRQSS). }
procedure VTermEmulator.RunDcs(const Body: AnsiString);
begin
  if Copy(Body, 1, 2) = '$q' then
    Reply(DecrqssAnswer(Copy(Body, 3, MaxInt)));
end;

function VTermEmulator.DecrqssAnswer(const Req: AnsiString): AnsiString;
var
  A: TVtAttr;
  Body: AnsiString;
begin
  if Req = 'm' then
  begin
    Body := '0';
    for A := Low(TVtAttr) to High(TVtAttr) do
      if A in FAttrs then
        Body := Body + ';' + IntToStr(AttrCodes[A]);
    Body := Body + ColorSgr(FFg, 30, 90, 38) + ColorSgr(FBg, 40, 100, 48);
    Result := DcsIntro + '1$r' + Body + 'm' + StringEnd;
  end
  else if Req = 'r' then
    Result := DcsIntro + '1$r' + IntToStr(FScreen.TopMargin + 1) + ';' + IntToStr(FScreen.BottomMargin + 1) +
      'r' + StringEnd
  else
    Result := DcsIntro + '0$r' + StringEnd;
end;

{ Text and the controls of the first set }

procedure VTermEmulator.FlushRun;
var
  Pending: AnsiString;
begin
  if FRun = '' then
    Exit;
  Pending := FRun;
  FRun := '';
  FScreen.PutText(Pending);
end;

procedure VTermEmulator.LineFeedMode;
begin
  FScreen.LineFeed;
  if FNewLine then
    FScreen.CarriageReturn;
end;

procedure VTermEmulator.NextLine;
begin
  FScreen.CarriageReturn;
  FScreen.LineFeed;
end;

procedure VTermEmulator.Control(Cp: Cardinal);
begin
  FlushRun;
  case Cp of
    8:
      FScreen.Backspace;
    9:
      FScreen.Tab(1);
    10, 11, 12:
      LineFeedMode;
    13:
      FScreen.CarriageReturn;
    14:
      FGl := 1;
    15:
      FGl := 0;
  end;
end;

function VTermEmulator.MapCharset(Cp: Cardinal): Cardinal;
begin
  Result := Cp;
  if (Cp < $20) or (Cp > $7E) then
    Exit;
  case FSets[FGl] of
    gsGraphics:
      if Cp >= $5F then
        Result := GraphicsCode(Cp);
    gsUk:
      if Cp = $23 then
        Result := $A3;
  end;
end;

procedure VTermEmulator.Print(Cp: Cardinal);
begin
  PrintMapped(MapCharset(Cp));
end;

procedure VTermEmulator.PrintMapped(Cp: Cardinal);
var
  Wid: Integer;
begin
  FLastGraphic := Cp;
  if FInsert then
  begin
    FlushRun;
    Wid := CharWidth(Cp);
    if Wid > 0 then
      FScreen.InsertChars(Wid);
    FScreen.PutText(Utf8Of(Cp));
  end
  else
    FRun := FRun + Utf8Of(Cp);
end;

procedure VTermEmulator.RepeatGraphic(Num: Integer);
var
  K: Integer;
begin
  if FLastGraphic = 0 then
    Exit;
  for K := 1 to Num do
    PrintMapped(FLastGraphic);
end;

{ ESC sequences }

procedure VTermEmulator.DesignateSet(Slot: Integer; Term: AnsiChar);
begin
  case Term of
    '0':
      FSets[Slot] := gsGraphics;
    'A':
      FSets[Slot] := gsUk;
  else
    FSets[Slot] := gsAscii;
  end;
end;

{ DECALN: the screen is filled with the letter E, with the whole screen as the region. }
procedure VTermEmulator.AlignmentPattern;
var
  Row: Integer;
  Wrapped: Boolean;
begin
  Wrapped := FScreen.AutoWrap;
  FScreen.AutoWrap := False;
  FScreen.SetScrollRegion(0, FScreen.Rows - 1);
  for Row := 0 to FScreen.Rows - 1 do
  begin
    FScreen.MoveTo(0, Row);
    FScreen.PutText(StringOfChar('E', FScreen.Cols));
  end;
  FScreen.AutoWrap := Wrapped;
  FScreen.MoveTo(0, 0);
end;

procedure VTermEmulator.EscPlain(Term: AnsiChar);
begin
  case Term of
    '[':
      begin
        FState := sqCsi;
        ResetCsi;
      end;
    ']', 'P', 'X', '^', '_':
      BeginString(Term);
    'D':
      FScreen.LineFeed;
    'E':
      NextLine;
    'H':
      FScreen.SetTabStop;
    'M':
      FScreen.ReverseIndex;
    '7':
      SaveState;
    '8':
      RestoreState;
    '=':
      FModes.KeypadApplication := True;
    '>':
      FModes.KeypadApplication := False;
    'c':
      FullReset;
    'Z':
      Reply(PrimaryAnswer);
  end;
end;

procedure VTermEmulator.EscDispatch(const Inter: AnsiString; Term: AnsiChar);
var
  Slot: Integer;
begin
  if Inter = '' then
    EscPlain(Term)
  else if Inter = '#' then
  begin
    if Term = '8' then
      AlignmentPattern;
  end
  else if Length(Inter) = 1 then
  begin
    Slot := Pos(Inter[1], '()*+') - 1;
    if Slot < 0 then
    begin
      Slot := Pos(Inter[1], '-./');
      if Slot = 0 then
        Slot := -1;
    end;
    if Slot >= 0 then
      DesignateSet(Slot, Term);
  end;
end;

{ The parameters of CSI }

procedure VTermEmulator.CommitParam;
begin
  if FCount < VtMaxParams then
  begin
    FValues[FCount] := FCurValue;
    FSubFlags[FCount] := FCurSub;
    Inc(FCount);
  end;
  FCurValue := -1;
  FCurSub := False;
end;

procedure VTermEmulator.NextParam(IsSub: Boolean);
begin
  CommitParam;
  FCurSub := IsSub;
  FSeen := True;
end;

procedure VTermEmulator.AddDigit(Digit: Integer);
begin
  FSeen := True;
  if FCurValue < 0 then
    FCurValue := 0;
  FCurValue := Min(FCurValue * 10 + Digit, 99999);
end;

function VTermEmulator.ParamAt(Idx, Fallback: Integer): Integer;
begin
  if (Idx < FCount) and (FValues[Idx] >= 0) then
    Result := FValues[Idx]
  else
    Result := Fallback;
end;

{ A count: a missing parameter and 0 are 1. }
function VTermEmulator.Positive(Idx: Integer): Integer;
begin
  Result := ParamAt(Idx, 1);
  if Result < 1 then
    Result := 1;
end;

{ The row of the screen for a row number of a cursor position: relative to the region in the origin mode. }
function VTermEmulator.RowTarget(Row: Integer): Integer;
begin
  if FOrigin then
    Result := Min(FScreen.TopMargin + Row, FScreen.BottomMargin)
  else
    Result := Row;
end;

{ CSI sequences }

procedure VTermEmulator.CsiDispatch(Term: AnsiChar);
var
  Sel: AnsiString;
begin
  if FSeen then
    CommitParam;
  Sel := FInter + Term;
  if FPrefix <> #0 then
    Sel := FPrefix + Sel;
  if Length(Sel) = 1 then
    CsiPlain(Term)
  else
    CsiOther(Sel);
end;

{ CUU, CUD, CUF, CUB, CNL and CPL (Which is 1 to 6): a move up or down stops at the margin of the region when the
  cursor is inside it. }
procedure VTermEmulator.CursorStep(Which, Num: Integer);
const
  StepX: array[1..6] of Integer = (0, 0, 1, -1, 0, 0);
  StepY: array[1..6] of Integer = (-1, 1, 0, 0, 1, -1);
var
  NewX, NewY: Integer;
begin
  NewX := FScreen.CursorX + StepX[Which] * Num;
  NewY := FScreen.CursorY + StepY[Which] * Num;
  if Which >= 5 then
    NewX := 0;
  if StepY[Which] < 0 then
  begin
    if FScreen.CursorY >= FScreen.TopMargin then
      NewY := Max(NewY, FScreen.TopMargin);
  end
  else if StepY[Which] > 0 then
  begin
    if FScreen.CursorY <= FScreen.BottomMargin then
      NewY := Min(NewY, FScreen.BottomMargin);
  end;
  FScreen.MoveTo(NewX, NewY);
end;

procedure VTermEmulator.CsiPlace(Term: AnsiChar);
begin
  case Term of
    'G', '`':
      FScreen.MoveTo(Positive(0) - 1, FScreen.CursorY);
    'a':
      FScreen.MoveBy(Positive(0), 0);
    'd':
      FScreen.MoveTo(FScreen.CursorX, RowTarget(Positive(0) - 1));
    'e':
      FScreen.MoveBy(0, Positive(0));
  else
    FScreen.MoveTo(Positive(1) - 1, RowTarget(Positive(0) - 1));
  end;
end;

procedure VTermEmulator.CsiEdit(Term: AnsiChar);
var
  Num: Integer;
begin
  Num := Positive(0);
  if Term = '@' then
    FScreen.InsertChars(Num)
  else if Term = 'P' then
    FScreen.DeleteChars(Num)
  else if Term = 'X' then
    FScreen.EraseChars(Num)
  else if (Term = 'L') or (Term = 'M') then
  begin
    if Term = 'L' then
      FScreen.InsertLines(Num)
    else
      FScreen.DeleteLines(Num);
  end
  else if (Term = 'S') or (Term = 'T') or (Term = '^') then
  begin
    { With more than one parameter T starts the mouse highlight, which is not served. }
    if FCount > 1 then
      Exit;
    if Term = 'S' then
      FScreen.ScrollUp(Num)
    else
      FScreen.ScrollDown(Num);
  end
  else if Term = 'I' then
    FScreen.Tab(Num)
  else if Term = 'Z' then
    FScreen.BackTab(Num)
  else
    RepeatGraphic(Num);
end;

procedure VTermEmulator.CsiErase(Term: AnsiChar);
var
  Mode: Integer;
begin
  Mode := ParamAt(0, 0);
  if Term = 'J' then
    FScreen.EraseInDisplay(Mode)
  else
    FScreen.EraseInLine(Mode);
end;

procedure VTermEmulator.TabClear;
begin
  case ParamAt(0, 0) of
    0:
      FScreen.ClearTabStop;
    3:
      FScreen.ClearAllTabStops;
  end;
end;

procedure VTermEmulator.SetMargins;
var
  First, Last: Integer;
begin
  First := Positive(0);
  Last := ParamAt(1, FScreen.Rows);
  if Last < 1 then
    Last := FScreen.Rows;
  FScreen.SetScrollRegion(First - 1, Last - 1);
  FScreen.MoveTo(0, RowTarget(0));
end;

procedure VTermEmulator.CursorStyle;
var
  Style: Integer;
begin
  Style := ParamAt(0, 0);
  if Style = 7 then
    FScreen.SetCursorBlink(False)
  else if (Style >= 0) and (Style <= 6) then
    FScreen.SetCursorBlink((Style = 0) or Odd(Style));
end;

{ The answers }

procedure VTermEmulator.CursorReport(IsPrivate: Boolean);
var
  Row: Integer;
  Pfx: AnsiString;
begin
  Row := FScreen.CursorY;
  if FOrigin then
    Row := Max(Row - FScreen.TopMargin, 0);
  Pfx := '';
  if IsPrivate then
    Pfx := '?';
  Reply(CsiIntro + Pfx + IntToStr(Row + 1) + ';' + IntToStr(FScreen.CursorX + 1) + 'R');
end;

procedure VTermEmulator.StatusReport;
begin
  case ParamAt(0, 0) of
    5:
      Reply(CsiIntro + '0n');
    6:
      CursorReport(False);
  end;
end;

procedure VTermEmulator.PrivateStatus;
begin
  case ParamAt(0, 0) of
    6:
      CursorReport(True);
    15:
      Reply(CsiIntro + '?10n');
    25:
      Reply(CsiIntro + '?20n');
    26:
      Reply(CsiIntro + '?27;1;0;0n');
  end;
end;

{ XTWINOPS 18 and 19: the size of the text area and of the screen in characters. }
procedure VTermEmulator.WindowReport;
var
  Code: Integer;
begin
  Code := ParamAt(0, 0);
  if (Code = 18) or (Code = 19) then
    Reply(CsiIntro + IntToStr(Code - 10) + ';' + IntToStr(FScreen.Rows) + ';' + IntToStr(FScreen.Cols) + 't');
end;

{ SGR }

procedure VTermEmulator.ApplySgrCode(Code: Integer);
var
  A: TVtAttr;
begin
  case Code of
    0:
      ResetPenState;
    30..37:
      FFg := IndexedColor(Code - 30);
    39:
      FFg := DefaultColor;
    40..47:
      FBg := IndexedColor(Code - 40);
    49:
      FBg := DefaultColor;
    90..97:
      FFg := IndexedColor(Code - 82);
    100..107:
      FBg := IndexedColor(Code - 92);
  else
    for A := Low(TVtAttr) to High(TVtAttr) do
    begin
      if Code = AttrCodes[A] then
        Include(FAttrs, A);
      if Code = AttrOffCodes[A] then
        Exclude(FAttrs, A);
    end;
    if Code = 6 then
      Include(FAttrs, vaBlink)
    else if Code = 21 then
      Include(FAttrs, vaUnderline);
  end;
end;

{ 38 and 48 with sub-parameters (a colon before each): 5 and an index, or 2 and the three components with an
  optional colour space before them. Idx is the index of the 38 or 48 and is left at the last parameter used. }
function VTermEmulator.ColonColor(var Idx: Integer; out Col: TVtColor): Boolean;
var
  First, Last, Base: Integer;
begin
  Result := False;
  First := Idx + 1;
  Last := First;
  while (Last + 1 < FCount) and FSubFlags[Last + 1] do
    Inc(Last);
  Idx := Last;
  if (FValues[First] = 5) and (Last - First >= 1) then
  begin
    Col := IndexedColor(Channel(FValues[First + 1]));
    Result := True;
  end
  else if FValues[First] = 2 then
  begin
    if Last - First >= 4 then
      Base := First + 2
    else if Last - First = 3 then
      Base := First + 1
    else
      Exit;
    Col := RgbColor(Channel(FValues[Base]), Channel(FValues[Base + 1]), Channel(FValues[Base + 2]));
    Result := True;
  end;
end;

{ 38 and 48 with parameters that are separated by semicolons: 5;n or 2;r;g;b. }
function VTermEmulator.SemicolonColor(var Idx: Integer; out Col: TVtColor): Boolean;
var
  Sort: Integer;
begin
  Result := False;
  if Idx + 1 >= FCount then
  begin
    Idx := FCount;
    Exit;
  end;
  Sort := FValues[Idx + 1];
  if Sort = 5 then
  begin
    if Idx + 2 < FCount then
    begin
      Col := IndexedColor(Channel(FValues[Idx + 2]));
      Result := True;
    end;
    Inc(Idx, 2);
  end
  else if Sort = 2 then
  begin
    if Idx + 4 < FCount then
    begin
      Col := RgbColor(Channel(FValues[Idx + 2]), Channel(FValues[Idx + 3]), Channel(FValues[Idx + 4]));
      Result := True;
    end;
    Inc(Idx, 4);
  end
  else
    Inc(Idx);
end;

procedure VTermEmulator.ReadExtendedColor(var Idx: Integer; Foreground: Boolean);
var
  Col: TVtColor;
  Got: Boolean;
begin
  if (Idx + 1 < FCount) and FSubFlags[Idx + 1] then
    Got := ColonColor(Idx, Col)
  else
    Got := SemicolonColor(Idx, Col);
  if not Got then
    Exit;
  if Foreground then
    FFg := Col
  else
    FBg := Col;
end;

procedure VTermEmulator.ApplySgr;
var
  Idx, Code: Integer;
begin
  if FCount = 0 then
    ResetPenState;
  Idx := 0;
  while Idx < FCount do
  begin
    Code := Max(FValues[Idx], 0);
    if (Code = 38) or (Code = 48) then
      ReadExtendedColor(Idx, Code = 38)
    else if (Code = 4) and (Idx + 1 < FCount) and FSubFlags[Idx + 1] then
    begin
      { 4:0 is no underline and any other style is an underline. }
      Inc(Idx);
      if Max(FValues[Idx], 0) = 0 then
        Exclude(FAttrs, vaUnderline)
      else
        Include(FAttrs, vaUnderline);
    end
    else
      ApplySgrCode(Code);
    while (Idx + 1 < FCount) and FSubFlags[Idx + 1] do
      Inc(Idx);
    Inc(Idx);
  end;
  FScreen.SetPenColors(FFg, FBg);
  FScreen.SetPenAttrs(FAttrs);
end;

{ Modes }

function VTermEmulator.FlagOf(Id: TVtModeId): PBoolean;
begin
  Result := nil;
  case Id of
    tmCursorKeys:
      Result := @FModes.CursorKeysApplication;
    tmKeypad:
      Result := @FModes.KeypadApplication;
    tmFocus:
      Result := @FModes.FocusReporting;
    tmPaste:
      Result := @FModes.BracketedPaste;
    tmReverse:
      Result := @FReverse;
    tmInsert:
      Result := @FInsert;
    tmNewLine:
      Result := @FNewLine;
  end;
end;

function VTermEmulator.ModeIsSet(Id: TVtModeId): Boolean;
var
  Flag: PBoolean;
begin
  Flag := FlagOf(Id);
  if Flag <> nil then
    Result := Flag^
  else if (Id >= tmMouseX10) and (Id <= tmMouseAny) then
    Result := Ord(FModes.MouseTracking) = Ord(vtTrackX10) + Ord(Id) - Ord(tmMouseX10)
  else if Id = tmUtf8Mouse then
    Result := FModes.MouseEncoding = vtEncUtf8
  else if Id = tmSgrMouse then
    Result := FModes.MouseEncoding = vtEncSgr
  else if Id = tmOrigin then
    Result := FOrigin
  else
    case Id of
      tmWrap:
        Result := FScreen.AutoWrap;
      tmBlink:
        Result := FScreen.CursorBlink;
      tmShow:
        Result := FScreen.CursorVisible;
      tmAlt47, tmAlt1047, tmAlt1049:
        Result := FScreen.AltScreen;
    else
      Result := False;
    end;
end;

procedure VTermEmulator.SetMouseEncoding(Id: TVtModeId; Enable: Boolean);
var
  Wanted: TVtMouseEncoding;
begin
  if Id = tmSgrMouse then
    Wanted := vtEncSgr
  else
    Wanted := vtEncUtf8;
  if Enable then
    FModes.MouseEncoding := Wanted
  else if FModes.MouseEncoding = Wanted then
    FModes.MouseEncoding := vtEncDefault;
end;

procedure VTermEmulator.SaveState;
begin
  FScreen.SaveCursor;
  FSaved.Origin := FOrigin;
  FSaved.Shift := FGl;
  FSaved.Sets := FSets;
  FSaved.Fg := FFg;
  FSaved.Bg := FBg;
  FSaved.Attrs := FAttrs;
end;

procedure VTermEmulator.RestoreState;
begin
  FScreen.RestoreCursor;
  FOrigin := FSaved.Origin;
  FGl := FSaved.Shift;
  FSets := FSaved.Sets;
  FFg := FSaved.Fg;
  FBg := FSaved.Bg;
  FAttrs := FSaved.Attrs;
end;

{ Modes 47 and 1047 switch the screen; 1049 saves the cursor before the switch to the alternate screen and
  restores it after the switch back. }
procedure VTermEmulator.SwitchScreen(Enter, WithCursor: Boolean);
begin
  if Enter then
  begin
    if FScreen.AltScreen then
      Exit;
    if WithCursor then
      SaveState;
    FScreen.EnableAltScreen(True);
  end
  else if FScreen.AltScreen then
  begin
    FScreen.EnableAltScreen(False);
    if WithCursor then
      RestoreState;
  end;
end;

procedure VTermEmulator.ApplyMode(Id: TVtModeId; Enable: Boolean);
var
  Flag: PBoolean;
begin
  Flag := FlagOf(Id);
  if Flag <> nil then
    Flag^ := Enable
  else if (Id >= tmMouseX10) and (Id <= tmMouseAny) then
  begin
    if Enable then
      FModes.MouseTracking := TVtMouseTracking(Ord(vtTrackX10) + Ord(Id) - Ord(tmMouseX10))
    else
      FModes.MouseTracking := vtTrackOff;
    FScreen.MouseEnabled := FModes.MouseTracking <> vtTrackOff;
  end
  else if (Id = tmUtf8Mouse) or (Id = tmSgrMouse) then
    SetMouseEncoding(Id, Enable)
  else
    case Id of
      tmOrigin:
        begin
          FOrigin := Enable;
          FScreen.MoveTo(0, RowTarget(0));
        end;
      tmWrap:
        FScreen.AutoWrap := Enable;
      tmBlink:
        FScreen.SetCursorBlink(Enable);
      tmShow:
        FScreen.SetCursorVisible(Enable);
      tmAlt47, tmAlt1047:
        SwitchScreen(Enable, False);
      tmAlt1049:
        SwitchScreen(Enable, True);
      tmSaveCursor:
        if Enable then
          SaveState
        else
          RestoreState;
    end;
end;

procedure VTermEmulator.CsiModes(Enable, IsPrivate: Boolean);
var
  K: Integer;
  Id: TVtModeId;
begin
  for K := 0 to FCount - 1 do
  begin
    Id := LookupMode(IsPrivate, FValues[K]);
    if Id <> tmNone then
      ApplyMode(Id, Enable);
  end;
end;

{ DECRQM: the reply is CSI [?] mode ; value $ y with 0 for an unknown mode, 1 set, 2 reset and 4 for a mode that
  cannot be set. }
procedure VTermEmulator.AskMode(IsPrivate: Boolean);
var
  Num, Code: Integer;
  Id: TVtModeId;
  Pfx: AnsiString;
begin
  Num := ParamAt(0, 0);
  Id := LookupMode(IsPrivate, Num);
  if Id = tmNone then
    Code := 0
  else if Id = tmColumns then
    Code := 4
  else if ModeIsSet(Id) then
    Code := 1
  else
    Code := 2;
  Pfx := '';
  if IsPrivate then
    Pfx := '?';
  Reply(CsiIntro + Pfx + IntToStr(Num) + ';' + IntToStr(Code) + '$y');
end;

{ Resets }

procedure VTermEmulator.SoftReset;
var
  KeepX, KeepY: Integer;
begin
  KeepX := FScreen.CursorX;
  KeepY := FScreen.CursorY;
  FInsert := False;
  FOrigin := False;
  FModes.CursorKeysApplication := False;
  FModes.KeypadApplication := False;
  FScreen.AutoWrap := True;
  FScreen.SetCursorVisible(True);
  FScreen.ResetPen;
  ResetPenState;
  FSets[0] := gsAscii;
  FSets[1] := gsAscii;
  FSets[2] := gsAscii;
  FSets[3] := gsAscii;
  FGl := 0;
  FScreen.SetScrollRegion(0, FScreen.Rows - 1);
  FScreen.MoveTo(0, 0);
  SaveState;
  FScreen.MoveTo(KeepX, KeepY);
end;

{ RIS: the screen is erased but the history and the title are kept. }
procedure VTermEmulator.FullReset;
begin
  FlushRun;
  if FScreen.AltScreen then
    FScreen.EnableAltScreen(False);
  ResetPersonality;
  FScreen.ResetPen;
  FScreen.AutoWrap := True;
  FScreen.MouseEnabled := False;
  FScreen.SetCursorVisible(True);
  FScreen.SetCursorBlink(False);
  FScreen.EraseInDisplay(2);
  ResetTabStops;
  FScreen.SetScrollRegion(0, FScreen.Rows - 1);
  FScreen.MoveTo(0, 0);
  FScreen.SaveCursor;
end;

{ CSI sequences that have a private marker or an intermediate character. }
procedure VTermEmulator.CsiOther(const Sel: AnsiString);
begin
  if (Sel = '?h') or (Sel = '?l') then
    CsiModes(Sel = '?h', True)
  else if Sel = '?n' then
    PrivateStatus
  else if Sel = '?$p' then
    AskMode(True)
  else if Sel = '$p' then
    AskMode(False)
  else if (Sel = '?J') or (Sel = '?K') then
    CsiErase(Sel[2])
  else if Sel = '?W' then
  begin
    if ParamAt(0, 0) = 5 then
      ResetTabStops;
  end
  else if Sel = '>c' then
  begin
    if ParamAt(0, 0) = 0 then
      Reply(CsiIntro + '>1;10;0c');
  end
  else if Sel = '>q' then
  begin
    if ParamAt(0, 0) = 0 then
      Reply(DcsIntro + '>|TvVt(0.1)' + StringEnd);
  end
  else if Sel = '=c' then
  begin
    if ParamAt(0, 0) = 0 then
      Reply(DcsIntro + '!|00000000' + StringEnd);
  end
  else if Sel = '!p' then
    SoftReset
  else if Sel = ' q' then
    CursorStyle;
end;

procedure VTermEmulator.CsiPlain(Term: AnsiChar);
begin
  if Pos(Term, 'ABCDEF') > 0 then
    CursorStep(Pos(Term, 'ABCDEF'), Positive(0))
  else if Pos(Term, 'G`adeHf') > 0 then
    CsiPlace(Term)
  else if Pos(Term, '@PXLMSTI^Zb') > 0 then
    CsiEdit(Term)
  else if (Term = 'J') or (Term = 'K') then
    CsiErase(Term)
  else
    case Term of
      'c':
        if ParamAt(0, 0) = 0 then
          Reply(PrimaryAnswer);
      'g':
        TabClear;
      'h', 'l':
        CsiModes(Term = 'h', False);
      'm':
        ApplySgr;
      'n':
        StatusReport;
      'r':
        SetMargins;
      's':
        if FCount = 0 then
          SaveState;
      'u':
        if FCount = 0 then
          RestoreState;
      't':
        WindowReport;
    end;
end;

end.
