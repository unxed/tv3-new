{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (the button flags, TDialog, TButton, TStaticText, TParamText, TLabel),
  include/tvision/ttypes.h (specialChars), source/tvision/tdialog.cpp, source/tvision/tbutton.cpp,
  source/tvision/tstatict.cpp, source/tvision/tparamte.cpp, source/tvision/tlabel.cpp,
  source/tvision/tvtext1.cpp (specialChars and the tables of TButton), include/tvision/util.h,
  source/tvision/misc.cpp
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it. The
  root reads its events from a script, and from the posted events of the event queue when the script asks for it.
  An event that a view puts back is the next one the root reads. The root hands out the timers as the numbers 1,
  2, 3, and counts the timers that are set and killed. The colors of the root are the BIOS attributes 1 to 127:
  the entry k of its palette is k, so the attribute of a cell is the entry of the palette of the root that the
  palettes of the views lead to. The root and the dialog of the modal tests record the events that they get, which
  are the messages that their views send to them. The hook of the
  hot keys is a function of the test that returns the upper case letter after the first tilde of a text. The
  characters of the shadow, of the markers and of specialChars are set to letters, so that the cells can be read
  as text; their values in the C++ are checked first. }
program t_dialog;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Classes, SysUtils, TvGeom, TvKeys, TvEvents, TvSys, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvTimer, TvViews,
  TvWindow, TvUtil, TvDialog;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 20;
  { No wait of these tests lasts longer than this, so that a failure ends the program. }
  Guard = 10000;
  MaxLog = 64;

type
  TFakeDisplay = class(TScreenBackend)
  public
    CaretSize: Word;
    procedure SetCaretSize(ASize: Word); override;
    function GetCaretSize: Word; override;
  end;

  TRoot = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    UseQueue: Boolean;
    Deadline: Int64;
    Requeue: Boolean;
    Pending: TEvent;
    PutCount: Integer;
    LastPut: TEvent;
    ErrorCount: Integer;
    TimerSerial: PtrUInt;
    TimerCount: Integer;
    LastTimeout: Cardinal;
    KillCount: Integer;
    LastKilled: TTimerId;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure PutEvent(var Event: TEvent); override;
    procedure EventError(var Event: TEvent); override;
    function GetPalette: TPalette; override;
    function SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer = -1): TTimerId; override;
    procedure KillTimer(Id: TTimerId); override;
  end;

  { A dialog that records the events that it gets. }
  TLogDialog = class(TDialog)
  public
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { A selectable view that draws nothing. }
  TSel = class(TView)
  public
    procedure Draw; override;
  end;

  { A view that refuses every command that asks whether it is valid. }
  TInvalidView = class(TView)
  public
    function Valid(Command: Word): Boolean; override;
  end;

  TTestStatic = class(TStaticText)
  public
    function RawText: PAnsiChar;
  end;

  TTestParam = class(TParamText)
  public
    function RawText: PAnsiChar;
    function RawStr: PAnsiChar;
  end;

  TTestLabel = class(TLabel)
  public
    function RawText: PAnsiChar;
    function GetLink: TView;
    function GetLight: Boolean;
  end;

  TTestButton = class(TButton)
  public
    function GetCommand: Word;
    function GetFlags: Byte;
    function GetDefault: Boolean;
  end;

  TPoster = class(TThread)
  private
    FKind: Integer;
    FDelay: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AKind, ADelay: Integer);
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  GetCalls: Integer;
  WakeFlag: LongInt;
  RootPal: TPalette;
  LogCount: Integer;
  LogTarget: array[0..MaxLog - 1] of TView;
  LogKind: array[0..MaxLog - 1] of Word;
  LogCode: array[0..MaxLog - 1] of Word;
  LogInfo: array[0..MaxLog - 1] of Pointer;

{ The fake display and the hooks. }

procedure TFakeDisplay.SetCaretSize(ASize: Word);
begin
  CaretSize := ASize;
end;

function TFakeDisplay.GetCaretSize: Word;
begin
  Result := CaretSize;
end;

procedure OnCaret(X, Y: Integer);
begin
end;

procedure OnScreenWrite(X, Y: Integer; Buf: PScreenCell; Count: Integer);
begin
end;

{ Records the event that the view Receiver gets. }
procedure LogEvent(Receiver: TView; const Event: TEvent);
begin
  if LogCount < MaxLog then
  begin
    LogTarget[LogCount] := Receiver;
    LogKind[LogCount] := Event.What;
    LogCode[LogCount] := Event.Message.Command;
    LogInfo[LogCount] := Event.Message.InfoPtr;
  end;
  Inc(LogCount);
end;

function TestHotKey(const Text: string): Char;
var
  position: Integer;
begin
  Result := #0;
  for position := 1 to Length(Text) - 1 do
    if Text[position] = '~' then
    begin
      Result := UpCase(Text[position + 1]);
      Exit;
    end;
end;

function Now64: Int64;
begin
  Result := Int64(GetTickCount64);
end;

{ Small helpers. }

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function KeyEv(Code: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Code;
end;

{ A key event for the character Ch, whose scan code is Scan. }
function CharKeyEv(Ch: Char; Scan: Byte): TEvent;
begin
  Result := KeyEv(Word(Ord(Ch) or (Scan shl 8)));
end;

function CmdEv(Cmd: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evCommand;
  Result.Message.Command := Cmd;
end;

function MouseEv(What: Word; X, Y: Integer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := What;
  Result.Mouse.Where := Pt(X, Y);
  Result.Mouse.Buttons := mbLeftButton;
end;

function BroadcastEv(Cmd: Word; Info: Pointer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evBroadcast;
  Result.Message.Command := Cmd;
  Result.Message.InfoPtr := Info;
end;

function CharAt(X, Y: Integer): Char;
var
  cellText: string;
begin
  cellText := ScreenCells[Y * ScrW + X].Character.GetText;
  if Length(cellText) > 0 then
    Result := cellText[1]
  else
    Result := #0;
end;

function AttrAt(X, Y: Integer): Integer;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute.ToBIOS;
end;

function RowText(Y, X0, N: Integer): string;
var
  offset: Integer;
begin
  Result := '';
  for offset := 0 to N - 1 do
    Result := Result + CharAt(X0 + offset, Y);
end;

procedure ClearScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
end;

{ The number of the entry I of a palette. }
function PalByte(P: TPalette; I: Integer): Integer;
var
  entry: TColorAttr;
begin
  entry := P.Items[I];
  Result := entry.ToBIOS;
end;

procedure ResetLog;
begin
  LogCount := 0;
end;

{ Tells whether a message with the command Code was recorded. }
function LogHas(Code: Word): Boolean;
var
  position: Integer;
begin
  Result := False;
  for position := 0 to LogCount - 1 do
    if (position < MaxLog) and (LogCode[position] = Code) then
      Result := True;
end;

{ The views of the tests. }

procedure TSel.Draw;
begin
end;

function TInvalidView.Valid(Command: Word): Boolean;
begin
  Result := False;
end;

function TTestStatic.RawText: PAnsiChar;
begin
  Result := Text;
end;

function TTestParam.RawText: PAnsiChar;
begin
  Result := Text;
end;

function TTestParam.RawStr: PAnsiChar;
begin
  Result := Str;
end;

function TTestLabel.RawText: PAnsiChar;
begin
  Result := Text;
end;

function TTestLabel.GetLink: TView;
begin
  Result := Link;
end;

function TTestLabel.GetLight: Boolean;
begin
  Result := Light;
end;

function TTestButton.GetCommand: Word;
begin
  Result := Command;
end;

function TTestButton.GetFlags: Byte;
begin
  Result := Flags;
end;

function TTestButton.GetDefault: Boolean;
begin
  Result := AmDefault;
end;

procedure TRoot.AddEvent(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TRoot.GetEvent(var Event: TEvent);
var
  nowMs: Int64;
  hasPending: Boolean;
begin
  Inc(GetCalls);
  if GetCalls > 200000 then
  begin
    WriteLn('FAIL a loop of events does not end');
    Halt(1);
  end;
  FillChar(Event, SizeOf(Event), 0);

  hasPending := Requeue and (Pending.What <> evNothing);
  if hasPending then
  begin
    Event := Pending;
    FillChar(Pending, SizeOf(Pending), 0);
    Exit;
  end;
  if ScriptPos < Length(Script) then
  begin
    Event := Script[ScriptPos];
    Inc(ScriptPos);
    Exit;
  end;
  if not UseQueue then
    Exit;

  if TEventQueue.GetPostedEvent(Event) then
    Exit;
  FillChar(Event, SizeOf(Event), 0);
  nowMs := Now64;
  if InterlockedExchange(WakeFlag, 0) <> 0 then
    Event := CmdEv(cmOK)
  else if nowMs > Deadline then
    Event := CmdEv(cmCancel)
  else
    TEventQueue.WaitForEvents(Guard);
end;

procedure TRoot.HandleEvent(var Event: TEvent);
begin
  LogEvent(Self, Event);
  inherited HandleEvent(Event);
end;

procedure TLogDialog.HandleEvent(var Event: TEvent);
begin
  LogEvent(Self, Event);
  inherited HandleEvent(Event);
end;

procedure TRoot.PutEvent(var Event: TEvent);
begin
  Inc(PutCount);
  LastPut := Event;
  if Requeue then
    Pending := Event;
end;

procedure TRoot.EventError(var Event: TEvent);
begin
  Inc(ErrorCount);
end;

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
end;

function TRoot.SetTimer(TimeoutMs: Cardinal; PeriodMs: Integer): TTimerId;
begin
  Inc(TimerSerial);
  Inc(TimerCount);
  LastTimeout := TimeoutMs;
  Result := TTimerId(TimerSerial);
end;

procedure TRoot.KillTimer(Id: TTimerId);
begin
  Inc(KillCount);
  LastKilled := Id;
end;

constructor TPoster.Create(AKind, ADelay: Integer);
begin
  FKind := AKind;
  FDelay := ADelay;
  inherited Create(False);
end;

procedure TPoster.Execute;
var
  Ev: TEvent;
begin
  if FDelay > 0 then
    Sleep(FDelay);
  case FKind of
    0:
      begin
        Ev := CmdEv(cmOK);
        TEventQueue.PostEvent(Ev);
      end;
    1:
      begin
        InterlockedExchange(WakeFlag, 1);
        TEventQueue.WakeUp;
      end;
  end;
end;

function NewRoot: TRoot;
begin
  ClearScreen;
  ResetLog;
  Result := TRoot.Create(Rc(0, 0, ScrW, ScrH));
  Result.Options := Result.Options and not ofBuffered;
  Result.Buffer := @ScreenCells[0];
  Result.State := Result.State or sfSelected;
  Result.SetState(sfExposed, True);
end;

procedure FreeRoot(R: TRoot);
begin
  TvObject.DestroyObject(R);
end;

function NewSel(const Area: TRect): TSel;
begin
  Result := TSel.Create(Area);
  Result.Options := Result.Options or ofSelectable;
end;

{ ---- the tests ---- }

procedure TestTables;
begin
  Check((bfNormal = 0) and (bfDefault = 1) and (bfLeftJust = 2) and (bfBroadcast = 4) and (bfGrabFocus = 8),
    'the flags of a button');
  Check((cmRecordHistory = 60) and (cmGrabDefault = 61) and (cmReleaseDefault = 62),
    'the commands of the buttons');
  Check((dpBlueDialog = 0) and (dpCyanDialog = 1) and (dpGrayDialog = 2), 'the palettes of a dialog');
  Check((SpecialChars[0] = 175) and (SpecialChars[1] = 174) and (SpecialChars[2] = 26) and
    (SpecialChars[3] = 27) and (SpecialChars[4] = 32) and (SpecialChars[5] = 32),
    'the characters that mark the controls');
  Check(TButton.Shadows = #$DC#$DB#$DF, 'the characters of the shadow of a button');
  Check(TButton.Markers = '[]', 'the characters of the markers of a button');
  Check((Length(cpGrayDialog) = 32) and (cpGrayDialog[1] = #$20) and (cpGrayDialog[32] = #$3F),
    'the gray palette of a dialog');
  Check((Length(cpBlueDialog) = 32) and (cpBlueDialog[1] = #$40) and (cpBlueDialog[32] = #$5F),
    'the blue palette of a dialog');
  Check((Length(cpCyanDialog) = 32) and (cpCyanDialog[1] = #$60) and (cpCyanDialog[32] = #$7F),
    'the cyan palette of a dialog');
  Check(cpDialog = cpGrayDialog, 'cpDialog is the gray palette');
end;

procedure TestStaticConstruction;
var
  Root: TRoot;
  Txt, Other: TTestStatic;
  Source: string;
  Copied: array[0..255] of AnsiChar;
begin
  Root := NewRoot;
  Source := 'Hello world';
  Txt := TTestStatic.Create(Rc(0, 0, 10, 3), Source);
  Source[1] := 'J';
  Check(StrPas(Txt.RawText) = 'Hello world', 'the static text keeps a copy of its text');
  Check(Txt.GrowMode = gfFixed, 'a static text does not move with its owner');
  Check(Txt.Options = 0, 'a static text has no options');
  Check(Txt.EventMask = (evMouseDown or evKeyDown or evCommand), 'a static text has the default event mask');
  Check(Txt.GetBounds = Rc(0, 0, 10, 3), 'the bounds of a static text');

  Check((PalByte(Txt.GetPalette, 0) = 1) and (PalByte(Txt.GetPalette, 1) = 6), 'the palette of a static text');
  Other := TTestStatic.Create(Rc(0, 5, 10, 6), 'x');
  Check(Txt.GetPalette = Other.GetPalette, 'all static texts share their palette');
  Other.Free;

  FillChar(Copied, SizeOf(Copied), Ord('X'));
  Txt.GetText(@Copied[0]);
  Check(StrPas(@Copied[0]) = 'Hello world', 'GetText copies the text');
  Check(Copied[11] = #0, 'GetText ends the copy with a zero');

  Other := TTestStatic.Create(Rc(0, 5, 10, 6), '');
  Check((Other.RawText <> nil) and (StrPas(Other.RawText) = ''), 'an empty text is an empty block');
  FillChar(Copied, SizeOf(Copied), Ord('X'));
  Other.GetText(@Copied[0]);
  Check(Copied[0] = #0, 'GetText of an empty text gives an empty string');
  Other.Free;
  Txt.Free;
  FreeRoot(Root);
end;

{ Shows a static text with the text AText in the area Area of a new root and draws it on a clean screen. }
procedure ShowStatic(out Root: TRoot; out Txt: TStaticText; const Area: TRect; const AText: string);
begin
  Root := NewRoot;
  Txt := TStaticText.Create(Area, AText);
  Root.Insert(Txt);
  ClearScreen;
  Txt.DrawView;
end;

procedure TestStaticDraw;
var
  Root: TRoot;
  Txt: TStaticText;
begin
  ShowStatic(Root, Txt, Rc(0, 0, 10, 3), 'Hello world');
  Check(RowText(0, 0, 10) = 'Hello     ', 'the first line holds the words that fit');
  Check(RowText(1, 0, 10) = 'world     ', 'the next word goes to the next line');
  Check(RowText(2, 0, 10) = '          ', 'the lines after the text are blank');
  Check((AttrAt(0, 0) = 6) and (AttrAt(9, 0) = 6) and (AttrAt(0, 2) = 6) and (AttrAt(9, 2) = 6),
    'every cell of a static text has its color');
  Check(CharAt(10, 0) = #0, 'a static text writes nothing beside its area');
  FreeRoot(Root);

  ShowStatic(Root, Txt, Rc(3, 2, 13, 5), 'Hi');
  Check((CharAt(3, 2) = 'H') and (CharAt(4, 2) = 'i') and (CharAt(5, 2) = ' '),
    'a static text is drawn at its position');
  Check((AttrAt(3, 2) = 6) and (AttrAt(12, 4) = 6) and (CharAt(2, 2) = #0) and (CharAt(3, 5) = #0),
    'a static text fills its area only');
  FreeRoot(Root);

  ShowStatic(Root, Txt, Rc(0, 0, 10, 3), #3'Hi');
  Check(RowText(0, 0, 10) = '    Hi    ', 'the character 3 centres the line');
  Check(RowText(1, 0, 10) = '          ', 'the centred text has one line');
  FreeRoot(Root);

  ShowStatic(Root, Txt, Rc(0, 0, 10, 3), 'ab'#10'cd');
  Check(RowText(0, 0, 10) = 'ab        ', 'the character 10 ends the line');
  Check(RowText(1, 0, 10) = 'cd        ', 'the text after the character 10 starts a line');
  FreeRoot(Root);

  ShowStatic(Root, Txt, Rc(0, 0, 10, 3), #3'ab'#10'cd');
  Check(RowText(0, 0, 10) = '    ab    ', 'the first line is centred');
  Check(RowText(1, 0, 10) = 'cd        ', 'the end of the line ends the centring');
  FreeRoot(Root);

  ShowStatic(Root, Txt, Rc(0, 0, 5, 3), 'abcdefghijkl');
  Check(RowText(0, 0, 5) = 'abcde', 'a word that is too wide is cut at the width');
  Check(RowText(1, 0, 5) = 'fghij', 'the rest of a cut word goes on');
  Check(RowText(2, 0, 5) = 'kl   ', 'the end of a cut word');
  FreeRoot(Root);

  ShowStatic(Root, Txt, Rc(0, 0, 7, 3), 'aaa bbb ccc');
  Check(RowText(0, 0, 7) = 'aaa bbb', 'words that fit exactly stay on the line');
  Check(RowText(1, 0, 7) = 'ccc    ', 'the next word goes to the next line when the line is full');
  FreeRoot(Root);

  ShowStatic(Root, Txt, Rc(0, 0, 7, 3), 'aaa bbbb ccc');
  Check(RowText(0, 0, 7) = 'aaa    ', 'a word that does not fit goes to the next line');
  Check(RowText(1, 0, 7) = 'bbbb   ', 'the word is on the second line');
  Check(RowText(2, 0, 7) = 'ccc    ', 'the last word is on the third line');
  FreeRoot(Root);

  ShowStatic(Root, Txt, Rc(0, 0, 10, 3), 'a'#10'b'#10'c'#10'd');
  Check((CharAt(0, 0) = 'a') and (CharAt(0, 1) = 'b') and (CharAt(0, 2) = 'c'), 'one line for each row');
  Check(CharAt(0, 3) = #0, 'the lines that do not fit in the view are not drawn');
  FreeRoot(Root);
end;

procedure TestParamText;
var
  Root: TRoot;
  Txt: TTestParam;
  Copied: array[0..255] of AnsiChar;
  Long: string;
begin
  Root := NewRoot;
  Txt := TTestParam.Create(Rc(0, 0, 10, 1));
  Root.Insert(Txt);
  Check(Txt.GrowMode = gfFixed, 'a parameter text does not move with its owner');
  Check(Txt.RawText = nil, 'a parameter text has no text of the base class');
  Check((Txt.RawStr <> nil) and (StrPas(Txt.RawStr) = ''), 'a parameter text starts empty');
  Check(Txt.GetTextLen = 0, 'the length of an empty parameter text');
  FillChar(Copied, SizeOf(Copied), Ord('X'));
  Txt.GetText(@Copied[0]);
  Check(Copied[0] = #0, 'GetText of an empty parameter text gives an empty string');
  Check((PalByte(Txt.GetPalette, 0) = 1) and (PalByte(Txt.GetPalette, 1) = 6),
    'a parameter text has the palette of a static text');

  ClearScreen;
  Txt.DrawView;
  Check((RowText(0, 0, 10) = '          ') and (AttrAt(4, 0) = 6), 'an empty parameter text is blank');

  ClearScreen;
  Txt.SetText('%d items', [3]);
  Check(StrPas(Txt.RawStr) = '3 items', 'SetText formats its arguments');
  Check(Txt.GetTextLen = 7, 'the length of the text');
  Check(RowText(0, 0, 10) = '3 items   ', 'SetText draws the view');
  FillChar(Copied, SizeOf(Copied), Ord('X'));
  Txt.GetText(@Copied[0]);
  Check(StrPas(@Copied[0]) = '3 items', 'GetText gives the formatted text');

  Txt.SetText('%s-%s', ['ab', 'cd']);
  Check((StrPas(Txt.RawStr) = 'ab-cd') and (Txt.GetTextLen = 5), 'SetText replaces the text');
  Check(RowText(0, 0, 10) = 'ab-cd     ', 'the new text is drawn');

  Txt.SetText('', []);
  Check((StrPas(Txt.RawStr) = '') and (Txt.GetTextLen = 0), 'SetText can empty the text');
  Check(RowText(0, 0, 10) = '          ', 'the empty text is drawn');

  Long := StringOfChar('x', 200);
  Txt.SetText('%s%s', [Long, Long]);
  Check(Txt.GetTextLen = 255, 'the text is cut at 255 characters');
  Check(StrPas(Txt.RawStr) = StringOfChar('x', 255), 'the cut text holds the first characters');
  Txt.SetText('a', []);
  Check(StrPas(Txt.RawStr) = 'a', 'a short text after a long one');
  FreeRoot(Root);
end;

procedure TestLabelConstruction;
var
  Root: TRoot;
  Target: TSel;
  Lbl: TTestLabel;
begin
  Root := NewRoot;
  Target := NewSel(Rc(0, 5, 5, 6));
  Lbl := TTestLabel.Create(Rc(0, 0, 12, 1), '~N~ame', Target);
  Check(Lbl.Options = (ofPreProcess or ofPostProcess), 'a label is processed before and after its owner');
  Check(Lbl.EventMask = (evMouseDown or evKeyDown or evCommand or evBroadcast), 'a label takes broadcasts');
  Check(Lbl.GrowMode = gfFixed, 'a label does not move with its owner');
  Check(Lbl.GetLink = TView(Target), 'a label keeps its link');
  Check(not Lbl.GetLight, 'a label starts without light');
  Check(StrPas(Lbl.RawText) = '~N~ame', 'a label keeps its text');
  Check((PalByte(Lbl.GetPalette, 0) = 4) and (PalByte(Lbl.GetPalette, 1) = 7) and (PalByte(Lbl.GetPalette, 2) = 8) and
    (PalByte(Lbl.GetPalette, 3) = 9) and (PalByte(Lbl.GetPalette, 4) = 9), 'the palette of a label');
  Lbl.Free;
  Target.Free;
  FreeRoot(Root);
end;

procedure TestLabelDraw;
var
  Root: TRoot;
  Target: TSel;
  Lbl: TTestLabel;
  Ev: TEvent;
  SavedChars: array[0..5] of Byte;
  K: Integer;
begin
  Root := NewRoot;
  Target := NewSel(Rc(0, 5, 5, 6));
  Lbl := TTestLabel.Create(Rc(0, 0, 12, 1), '~N~ame', Target);
  Root.Insert(Target);
  Root.Insert(Lbl);

  ClearScreen;
  Lbl.DrawView;
  Check(RowText(0, 0, 12) = ' Name       ', 'a label is drawn one cell from its left edge');
  Check((AttrAt(0, 0) = 7) and (AttrAt(2, 0) = 7) and (AttrAt(11, 0) = 7), 'the normal color of a label');
  Check(AttrAt(1, 0) = 9, 'the shortcut of a label has the normal shortcut color');

  Target.State := Target.State or sfFocused;
  Ev := BroadcastEv(cmReceivedFocus, Target);
  ClearScreen;
  Lbl.HandleEvent(Ev);
  Check(Lbl.GetLight, 'a label lights up when its link receives the focus');
  Check(Ev.What = evBroadcast, 'a label does not take the broadcast');
  Check((AttrAt(0, 0) = 8) and (AttrAt(2, 0) = 8) and (AttrAt(11, 0) = 8), 'the selected color of a label');
  Check((AttrAt(1, 0) = 9) and (RowText(0, 0, 12) = ' Name       '), 'the selected shortcut of a label');

  Target.State := Target.State and not sfFocused;
  Ev := BroadcastEv(cmReleasedFocus, Target);
  ClearScreen;
  Lbl.HandleEvent(Ev);
  Check(not Lbl.GetLight, 'a label goes dark when its link loses the focus');
  Check(AttrAt(2, 0) = 7, 'the label is drawn with the normal color again');

  Target.State := Target.State or sfFocused;
  Ev := BroadcastEv(cmOK, Target);
  Lbl.HandleEvent(Ev);
  Check(not Lbl.GetLight, 'another broadcast does not change the light');
  Target.State := Target.State and not sfFocused;

  for K := 0 to 5 do
    SavedChars[K] := SpecialChars[K];
  for K := 0 to 5 do
    SpecialChars[K] := Ord('A') + K;
  TView.ShowMarkers := True;
  ClearScreen;
  Lbl.DrawView;
  Check(CharAt(0, 0) = 'E', 'a dark label shows the sixth special character');
  Check(AttrAt(0, 0) = 7, 'the marker has the color of the label');
  Target.State := Target.State or sfFocused;
  Ev := BroadcastEv(cmReceivedFocus, Target);
  Lbl.HandleEvent(Ev);
  ClearScreen;
  Lbl.DrawView;
  Check(CharAt(0, 0) = 'A', 'a lit label shows the first special character');
  TView.ShowMarkers := False;
  for K := 0 to 5 do
    SpecialChars[K] := SavedChars[K];
  Target.State := Target.State and not sfFocused;

  FreeRoot(Root);
end;

procedure TestLabelEvents;
var
  Root: TRoot;
  Target, Other, Plain: TSel;
  Lbl, Lbl2, Lbl3: TTestLabel;
  Ev: TEvent;
begin
  Root := NewRoot;
  Other := NewSel(Rc(0, 4, 5, 5));
  Target := NewSel(Rc(0, 5, 5, 6));
  Plain := TSel.Create(Rc(0, 6, 5, 7));
  Lbl := TTestLabel.Create(Rc(0, 0, 12, 1), '~N~ame', Target);
  Lbl3 := TTestLabel.Create(Rc(0, 1, 12, 2), '~P~lain', Plain);
  Root.Insert(Other);
  Root.Insert(Target);
  Root.Insert(Plain);
  Root.Insert(Lbl);
  Root.Insert(Lbl3);

  Root.SetCurrent(Other, normalSelect);
  Check(Root.Current = TView(Other), 'the other view is the current view');
  Ev := MouseEv(evMouseDown, 2, 0);
  Lbl.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a click on a label is taken');
  Check(Root.Current = TView(Target), 'a click on a label focuses its link');

  Root.SetCurrent(Other, normalSelect);
  Ev := MouseEv(evMouseDown, 2, 1);
  Lbl3.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a click on a label of a view that cannot be selected is taken');
  Check(Root.Current = TView(Other), 'a link that cannot be selected does not get the focus');

  Lbl2 := TTestLabel.Create(Rc(0, 2, 12, 3), '~Q~', nil);
  Ev := MouseEv(evMouseDown, 2, 2);
  Lbl2.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a click on a label without a link is taken');
  Ev := BroadcastEv(cmReceivedFocus, Other);
  Lbl2.HandleEvent(Ev);
  Check(not Lbl2.GetLight, 'a label without a link does not light up');
  Lbl2.Free;

  Root.SetCurrent(Other, normalSelect);
  Ev := KeyEv(GetAltCode('N'));
  Lbl.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the Alt key of the hot key is taken');
  Check(Root.Current = TView(Target), 'the Alt key of the hot key focuses the link');

  Root.SetCurrent(Other, normalSelect);
  Ev := CharKeyEv('n', $31);
  Root.Phase := phPostProcess;
  Lbl.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the letter of the hot key is taken after the owner');
  Check(Root.Current = TView(Target), 'the letter of the hot key focuses the link');

  Root.SetCurrent(Other, normalSelect);
  Ev := CharKeyEv('N', $31);
  Lbl.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.Current = TView(Target)), 'the letter is taken in either case');

  Root.SetCurrent(Other, normalSelect);
  Ev := CharKeyEv('x', $2D);
  Lbl.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.Current = TView(Other)), 'another letter is not taken');
  Ev := KeyEv(0);
  Lbl.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.Current = TView(Other)), 'an event with no key code is not taken');

  Root.Phase := phFocused;
  Ev := CharKeyEv('n', $31);
  Lbl.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.Current = TView(Other)),
    'the letter of the hot key is not taken while the owner handles it first');
  Ev := KeyEv(GetAltCode('X'));
  Lbl.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.Current = TView(Other)), 'another Alt key is not taken');

  HotKeyHook := nil;
  Ev := KeyEv(GetAltCode('N'));
  Lbl.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.Current = TView(Other)), 'without a hook for the hot keys no key is taken');
  HotKeyHook := @TestHotKey;

  Lbl3.ShutDown;
  Check(Lbl3.GetLink = nil, 'ShutDown clears the link');
  Check(Lbl3.Owner = nil, 'ShutDown takes the label out of its owner');
  Lbl3.Free;
  FreeRoot(Root);
end;

procedure TestButtonConstruction;
var
  Root: TRoot;
  Btn, Btn2: TTestButton;
  Pal: TPalette;
begin
  Root := NewRoot;
  TView.EnableCommand(100);
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Check(Btn.Options = (ofSelectable or ofFirstClick or ofPreProcess or ofPostProcess),
    'a button can be selected and is processed before and after its owner');
  Check(Btn.EventMask = (evMouseDown or evKeyDown or evCommand or evBroadcast), 'a button takes broadcasts');
  Check(StrPas(Btn.Title) = '~O~K', 'a button keeps its title');
  Check(Btn.GetCommand = cmOK, 'a button keeps its command');
  Check(Btn.GetFlags = 0, 'a button keeps its flags');
  Check(not Btn.GetDefault, 'a normal button is not the default button');
  Check((Btn.State and sfDisabled) = 0, 'a button of an enabled command is enabled');
  Check(Btn.GrowMode = 0, 'a button does not grow');

  Pal := Btn.GetPalette;
  Check((PalByte(Pal, 0) = 8) and (PalByte(Pal, 1) = 10) and (PalByte(Pal, 2) = 11) and (PalByte(Pal, 3) = 12) and
    (PalByte(Pal, 4) = 13) and (PalByte(Pal, 5) = 14) and (PalByte(Pal, 6) = 14) and (PalByte(Pal, 7) = 14) and
    (PalByte(Pal, 8) = 15), 'the palette of a button');

  Btn2 := TTestButton.Create(Rc(0, 0, 10, 2), 'x', 100, bfDefault);
  Check(Btn2.GetDefault and (Btn2.GetFlags = 1), 'a button with the flag is the default button');
  Check(Btn.GetPalette = Btn2.GetPalette, 'all buttons share their palette');
  Btn2.Free;

  Btn2 := TTestButton.Create(Rc(0, 0, 10, 2), 'x', 100, $0105);
  Check((Btn2.GetFlags = 5) and Btn2.GetDefault, 'the flags are kept in a byte and the default flag is read from all bits');
  Btn2.Free;

  TView.DisableCommand(100);
  Btn2 := TTestButton.Create(Rc(0, 0, 10, 2), 'x', 100, bfNormal);
  Check((Btn2.State and sfDisabled) <> 0, 'a button of a disabled command is disabled');
  Btn2.Free;
  TView.EnableCommand(100);
  Btn2 := TTestButton.Create(Rc(0, 0, 10, 2), 'x', 300, bfNormal);
  Check((Btn2.State and sfDisabled) = 0, 'a command above 255 is always enabled');
  Btn2.Free;

  Btn.Free;
  FreeRoot(Root);
end;

procedure TestButtonDraw;
var
  Root: TRoot;
  Btn: TTestButton;
  SavedChars: array[0..5] of Byte;
  K: Integer;
begin
  TButton.Shadows := 'abc';
  TButton.Markers := '<>';
  for K := 0 to 5 do
    SavedChars[K] := SpecialChars[K];
  for K := 0 to 5 do
    SpecialChars[K] := Ord('A') + K;

  Root := NewRoot;
  TView.EnableCommand(101);
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);
  ClearScreen;
  Btn.DrawView;
  Check(RowText(0, 0, 10) = '    OK   a', 'the title row of a button with its shadow');
  Check(RowText(1, 0, 10) = '  cccccccc', 'the bottom row of a button is the shadow');
  Check((AttrAt(1, 0) = 10) and (AttrAt(5, 0) = 10) and (AttrAt(8, 0) = 10), 'the normal color of a button');
  Check(AttrAt(4, 0) = 14, 'the shortcut of a button has the shortcut color');
  Check((AttrAt(0, 0) = 15) and (AttrAt(9, 0) = 15), 'the edges of a button have the shadow color');
  Check((AttrAt(0, 1) = 15) and (AttrAt(2, 1) = 15) and (AttrAt(9, 1) = 15), 'the bottom row has the shadow color');

  TvObject.DestroyObject(Btn);
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfDefault);
  Root.Insert(Btn);
  Btn.SetState(sfSelected, False);
  Btn.SetState(sfActive, True);
  ClearScreen;
  Btn.DrawView;
  Check((AttrAt(1, 0) = 11) and (AttrAt(4, 0) = 14), 'an active default button has the default color');
  Btn.SetState(sfSelected, True);
  ClearScreen;
  Btn.DrawView;
  Check((AttrAt(1, 0) = 12) and (AttrAt(4, 0) = 14), 'an active selected button has the selected color');
  Btn.SetState(sfActive, False);
  ClearScreen;
  Btn.DrawView;
  Check(AttrAt(1, 0) = 10, 'a button that is not active has the normal color');
  TvObject.DestroyObject(Btn);

  TView.DisableCommand(101);
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', 101, bfNormal);
  TView.EnableCommand(101);
  Root.Insert(Btn);
  Btn.SetState(sfActive, True);
  ClearScreen;
  Btn.DrawView;
  Check((AttrAt(1, 0) = 13) and (AttrAt(4, 0) = 13) and (AttrAt(0, 0) = 15), 'a disabled button has the disabled color');
  TvObject.DestroyObject(Btn);

  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);
  ClearScreen;
  Btn.DrawState(True);
  Check(RowText(0, 0, 10) = '     OK   ', 'a pressed button has no shadow and its title is one cell to the right');
  Check(RowText(1, 0, 10) = '          ', 'the bottom row of a pressed button is blank');
  Check((AttrAt(0, 0) = 15) and (AttrAt(1, 0) = 15) and (AttrAt(2, 0) = 10) and (AttrAt(9, 0) = 10),
    'the left edge of a pressed button has the shadow color');
  Check((AttrAt(5, 0) = 14) and (AttrAt(6, 0) = 10) and (AttrAt(5, 1) = 15), 'the colors of a pressed button');
  TvObject.DestroyObject(Btn);

  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfLeftJust);
  Root.Insert(Btn);
  ClearScreen;
  Btn.DrawView;
  Check(RowText(0, 0, 10) = '  OK     a', 'the title of a button with the flag stands at the left');
  TvObject.DestroyObject(Btn);

  Btn := TTestButton.Create(Rc(0, 0, 10, 3), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);
  ClearScreen;
  Btn.DrawView;
  Check(RowText(0, 0, 10) = '    OK   a', 'the title is in the first row of a button of three rows');
  Check(RowText(1, 0, 10) = '         b', 'the other rows of the right column have their own character');
  Check(RowText(2, 0, 10) = '  cccccccc', 'the bottom row of a button of three rows');
  TvObject.DestroyObject(Btn);

  Btn := TTestButton.Create(Rc(0, 0, 10, 4), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);
  ClearScreen;
  Btn.DrawView;
  Check(RowText(0, 0, 10) = '         a', 'the first row of a button of four rows');
  Check(RowText(1, 0, 10) = '    OK   b', 'the title is in the row at half the height less one');
  Check(RowText(2, 0, 10) = '         b', 'the third row of a button of four rows');
  Check(RowText(3, 0, 10) = '  cccccccc', 'the bottom row of a button of four rows');
  TvObject.DestroyObject(Btn);

  TView.ShowMarkers := True;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);
  Btn.SetState(sfSelected, False);
  ClearScreen;
  Btn.DrawView;
  Check(RowText(0, 0, 10) = 'E<  OK  >F', 'a normal button with markers');
  Check(RowText(1, 0, 10) = '          ', 'with markers the shadow is blank');
  Check((AttrAt(0, 0) = 15) and (AttrAt(9, 0) = 15) and (AttrAt(1, 0) = 10), 'the colors of the markers');
  Btn.State := Btn.State or sfSelected;
  ClearScreen;
  Btn.DrawView;
  Check(RowText(0, 0, 10) = 'A<  OK  >B', 'a selected button with markers');
  Btn.DrawState(True);
  Check(RowText(0, 0, 10) = '     OK   ', 'a pressed button has no markers');
  TvObject.DestroyObject(Btn);

  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfDefault);
  Root.Insert(Btn);
  Btn.SetState(sfSelected, False);
  ClearScreen;
  Btn.DrawView;
  Check(RowText(0, 0, 10) = 'C<  OK  >D', 'a default button with markers');
  TvObject.DestroyObject(Btn);
  TView.ShowMarkers := False;

  FreeRoot(Root);
  TButton.Shadows := #$DC#$DB#$DF;
  TButton.Markers := '[]';
  for K := 0 to 5 do
    SpecialChars[K] := SavedChars[K];
end;

procedure TestButtonMouse;
var
  Root: TRoot;
  Btn: TTestButton;
  Other: TSel;
  Ev: TEvent;
begin
  TButton.Shadows := 'abc';
  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);
  ResetLog;

  Root.AddEvent(MouseEv(evMouseMove, 3, 0));
  Root.AddEvent(MouseEv(evMouseUp, 3, 0));
  Ev := MouseEv(evMouseDown, 3, 0);
  Btn.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a click on a button is taken');
  Check(Root.ScriptPos = 2, 'the button follows the mouse until it is released');
  Check(Root.PutCount = 1, 'a click that ends inside the button presses it');
  Check((Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmOK) and
    (Root.LastPut.Message.InfoPtr = Pointer(Btn)), 'the press puts the command of the button, with the button');
  Check((LogCount = 1) and (LogTarget[0] = TView(Root)) and (LogKind[0] = evBroadcast) and
    (LogCode[0] = cmRecordHistory) and (LogInfo[0] = nil), 'the press tells the owner to record the history');
  Check(RowText(0, 0, 10) = '    OK   a', 'the button is drawn up again after the press');

  Root.PutCount := 0;
  ResetLog;
  Root.ScriptPos := 0;
  SetLength(Root.Script, 0);
  Root.AddEvent(MouseEv(evMouseMove, 15, 0));
  Root.AddEvent(MouseEv(evMouseUp, 15, 0));
  Ev := MouseEv(evMouseDown, 3, 0);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.ScriptPos = 2), 'a click that leaves the button is followed to its end');
  Check((Root.PutCount = 0) and (LogCount = 0), 'a click that ends outside the button does not press it');
  Check(RowText(0, 0, 10) = '    OK   a', 'the button is drawn up when the mouse has left it');

  Root.ScriptPos := 0;
  SetLength(Root.Script, 0);
  Root.AddEvent(MouseEv(evMouseUp, 3, 0));
  Ev := MouseEv(evMouseDown, 0, 0);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.ScriptPos = 0) and (Root.PutCount = 0),
    'a click on the left column is taken and does nothing');
  Ev := MouseEv(evMouseDown, 9, 0);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.ScriptPos = 0) and (Root.PutCount = 0),
    'a click on the right column is taken and does nothing');
  Ev := MouseEv(evMouseDown, 3, 1);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.ScriptPos = 0) and (Root.PutCount = 0),
    'a click on the shadow row is taken and does nothing');
  Ev := MouseEv(evMouseDown, 8, 0);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.ScriptPos = 1) and (Root.PutCount = 1),
    'a click on the last column of the face presses the button');

  FreeRoot(Root);

  Root := NewRoot;
  TView.DisableCommand(101);
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', 101, bfNormal);
  TView.EnableCommand(101);
  Root.Insert(Btn);
  Root.AddEvent(MouseEv(evMouseUp, 3, 0));
  Ev := MouseEv(evMouseDown, 3, 0);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.ScriptPos = 0) and (Root.PutCount = 0),
    'a click on a disabled button is taken and does nothing');
  FreeRoot(Root);

  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfBroadcast);
  Root.Insert(Btn);
  ResetLog;
  Root.AddEvent(MouseEv(evMouseUp, 3, 0));
  Ev := MouseEv(evMouseDown, 3, 0);
  Btn.HandleEvent(Ev);
  Check(Root.PutCount = 0, 'a button with the broadcast flag puts no event');
  Check((LogCount = 2) and (LogCode[0] = cmRecordHistory) and (LogInfo[0] = nil), 'the history is recorded first');
  Check((LogTarget[1] = TView(Root)) and (LogKind[1] = evBroadcast) and (LogCode[1] = cmOK) and
    (LogInfo[1] = Pointer(Btn)), 'the command is broadcast to the owner, with the button');
  FreeRoot(Root);

  Root := NewRoot;
  Other := NewSel(Rc(0, 5, 5, 6));
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfGrabFocus);
  Root.Insert(Other);
  Root.Insert(Btn);
  Root.SetCurrent(Other, normalSelect);
  Root.AddEvent(MouseEv(evMouseUp, 3, 0));
  Ev := MouseEv(evMouseDown, 3, 0);
  Btn.HandleEvent(Ev);
  Check(Root.Current = TView(Btn), 'a button with the grab flag takes the focus when it is clicked');
  Check((Ev.What = evNothing) and (Root.PutCount = 1), 'the click still presses the button');
  FreeRoot(Root);
  TButton.Shadows := #$DC#$DB#$DF;
end;

procedure TestButtonKeys;
var
  Root: TRoot;
  Btn: TTestButton;
  Ev: TEvent;
begin
  TButton.Shadows := 'abc';
  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);

  Ev := CharKeyEv(' ', $39);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.TimerCount = 0), 'the space bar does nothing when the button is not focused');

  Btn.State := Btn.State or sfFocused;
  ClearScreen;
  Ev := CharKeyEv(' ', $39);
  Btn.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the space bar is taken when the button is focused');
  Check((Root.TimerCount = 1) and (Root.LastTimeout = 100), 'the press starts a timer of 100 milliseconds');
  Check(RowText(0, 0, 10) = '     OK   ', 'the button is drawn pressed down');
  Ev := CharKeyEv(' ', $39);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.TimerCount = 1), 'a second press does not start a second timer');

  Ev := BroadcastEv(cmTimerExpired, Pointer(99));
  Btn.HandleEvent(Ev);
  Check((Ev.What = evBroadcast) and (Root.PutCount = 0), 'the expiry of another timer is not taken');
  ResetLog;
  Ev := BroadcastEv(cmTimerExpired, Pointer(1));
  Btn.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the expiry of its timer is taken');
  Check(RowText(0, 0, 10) = '    OK   a', 'the button is drawn up when its timer expires');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmOK) and
    (Root.LastPut.Message.InfoPtr = Pointer(Btn)), 'the expiry presses the button');
  Check(LogHas(cmRecordHistory), 'the expiry records the history');
  Ev := BroadcastEv(cmTimerExpired, Pointer(1));
  Btn.HandleEvent(Ev);
  Check((Ev.What = evBroadcast) and (Root.PutCount = 1), 'a timer is used once');

  Ev := CharKeyEv(' ', $39);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.TimerCount = 2), 'a new press starts a new timer');
  Ev := BroadcastEv(cmTimerExpired, Pointer(2));
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.PutCount = 2), 'the new timer presses the button');
  FreeRoot(Root);

  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);
  Ev := KeyEv(GetAltCode('O'));
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.TimerCount = 1), 'the Alt key of the hot key presses the button');
  Ev := KeyEv(GetAltCode('X'));
  Btn.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.TimerCount = 1), 'another Alt key is not taken');

  Ev := CharKeyEv('o', $18);
  Btn.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'the letter is not taken while the owner handles the event first');
  Root.Phase := phPostProcess;
  Ev := CharKeyEv('o', $18);
  Btn.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Root.TimerCount = 1), 'the letter is taken after the owner, while the timer runs');
  Ev := CharKeyEv('O', $18);
  Btn.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the upper case letter is taken as well');
  Ev := CharKeyEv('x', $2D);
  Btn.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'another letter is not taken');
  Ev := KeyEv(0);
  Btn.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'an event with no key code is not taken');
  Root.Phase := phFocused;

  HotKeyHook := nil;
  Ev := KeyEv(GetAltCode('O'));
  Btn.HandleEvent(Ev);
  Check(Ev.What = evKeyDown, 'without a hook for the hot keys the Alt key is not taken');
  Btn.State := Btn.State or sfFocused;
  Ev := CharKeyEv(' ', $39);
  Btn.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'without a hook the space bar still presses a focused button');
  HotKeyHook := @TestHotKey;
  FreeRoot(Root);
  TButton.Shadows := #$DC#$DB#$DF;
end;

procedure TestButtonBroadcasts;
var
  Root: TRoot;
  Btn, Plain, Off: TTestButton;
  Ev: TEvent;
begin
  TButton.Shadows := 'abc';
  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfDefault);
  Plain := TTestButton.Create(Rc(0, 3, 10, 5), '~C~ancel', cmCancel, bfNormal);
  TView.DisableCommand(101);
  Off := TTestButton.Create(Rc(0, 6, 10, 8), '~X~', 101, bfDefault);
  TView.EnableCommand(101);
  Root.Insert(Btn);
  Root.Insert(Plain);
  Root.Insert(Off);

  ClearScreen;
  Ev := BroadcastEv(cmDefault, nil);
  Plain.HandleEvent(Ev);
  Check((Ev.What = evBroadcast) and (Root.TimerCount = 0), 'a button that is not the default ignores cmDefault');
  Off.HandleEvent(Ev);
  Check((Ev.What = evBroadcast) and (Root.TimerCount = 0), 'a disabled default button ignores cmDefault');
  Btn.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the default button takes cmDefault');
  Check((Root.TimerCount = 1) and (Root.LastTimeout = 100), 'the default button starts its timer');
  Check(RowText(0, 0, 10) = '     OK   ', 'the default button is drawn pressed down');

  Ev := BroadcastEv(cmGrabDefault, nil);
  Btn.HandleEvent(Ev);
  Check(not Btn.GetDefault, 'a button with the flag stops being the default button when another one grabs it');
  Check(Ev.What = evBroadcast, 'the broadcast goes on');
  Ev := BroadcastEv(cmReleaseDefault, nil);
  Btn.HandleEvent(Ev);
  Check(Btn.GetDefault and (Ev.What = evBroadcast), 'a button with the flag becomes the default button again');

  Ev := BroadcastEv(cmReleaseDefault, nil);
  Plain.HandleEvent(Ev);
  Check(not Plain.GetDefault, 'a button without the flag ignores the release');
  Ev := BroadcastEv(cmGrabDefault, nil);
  Plain.HandleEvent(Ev);
  Check(not Plain.GetDefault, 'a button without the flag ignores the grab');

  TView.DisableCommand(101);
  Ev := BroadcastEv(cmCommandSetChanged, nil);
  Off.HandleEvent(Ev);
  Check(((Off.State and sfDisabled) <> 0) and (Ev.What = evBroadcast), 'the button stays disabled');
  Plain.HandleEvent(Ev);
  Check((Plain.State and sfDisabled) = 0, 'a button of an enabled command stays enabled');
  TView.EnableCommand(101);
  Ev := BroadcastEv(cmCommandSetChanged, nil);
  Off.HandleEvent(Ev);
  Check((Off.State and sfDisabled) = 0, 'a button is enabled when its command is enabled');
  TView.DisableCommand(101);
  Ev := BroadcastEv(cmCommandSetChanged, nil);
  Off.HandleEvent(Ev);
  Check((Off.State and sfDisabled) <> 0, 'a button is disabled when its command is disabled');
  TView.EnableCommand(101);

  Ev := BroadcastEv(cmTimerExpired, nil);
  Plain.HandleEvent(Ev);
  Check((Ev.What = evBroadcast) and (Root.PutCount = 0), 'a button without a timer ignores an expiry with no timer');
  Ev := BroadcastEv(cmOK, Plain);
  Plain.HandleEvent(Ev);
  Check(Ev.What = evBroadcast, 'a button ignores the other broadcasts');
  FreeRoot(Root);
  TButton.Shadows := #$DC#$DB#$DF;
end;

procedure TestButtonState;
var
  Root: TRoot;
  Btn, Fixed: TTestButton;
begin
  TButton.Shadows := 'abc';
  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Fixed := TTestButton.Create(Rc(0, 3, 10, 5), '~C~ancel', cmCancel, bfDefault);
  Root.Insert(Btn);
  Root.Insert(Fixed);
  ResetLog;

  Btn.SetState(sfFocused, True);
  Check(LogCount = 2, 'focusing a button sends two messages');
  Check((LogTarget[0] = TView(Root)) and (LogKind[0] = evBroadcast) and (LogCode[0] = cmReceivedFocus) and
    (LogInfo[0] = Pointer(Btn)), 'the view tells its owner that it received the focus');
  Check((LogTarget[1] = TView(Root)) and (LogKind[1] = evBroadcast) and (LogCode[1] = cmGrabDefault) and
    (LogInfo[1] = Pointer(Btn)), 'a focused button grabs the default');
  Check(Btn.GetDefault, 'a focused button is the default button');
  Btn.SetState(sfFocused, False);
  Check(LogCount = 4, 'losing the focus sends two messages');
  Check((LogCode[2] = cmReleasedFocus) and (LogCode[3] = cmReleaseDefault) and (LogInfo[3] = Pointer(Btn)),
    'a button that loses the focus releases the default');
  Check(not Btn.GetDefault, 'the button is not the default button any more');

  ResetLog;
  Fixed.SetState(sfFocused, True);
  Check((LogCount = 1) and (LogCode[0] = cmReceivedFocus), 'a button with the flag does not grab the default');
  Check(Fixed.GetDefault, 'a button with the flag stays the default button');
  Fixed.SetState(sfFocused, False);
  Check((LogCount = 2) and Fixed.GetDefault, 'a button with the flag does not release the default');

  ResetLog;
  Btn.MakeDefault(True);
  Check((LogCount = 1) and (LogTarget[0] = TView(Root)) and (LogKind[0] = evBroadcast) and
    (LogCode[0] = cmGrabDefault) and (LogInfo[0] = Pointer(Btn)), 'MakeDefault tells the owner');
  Check(Btn.GetDefault, 'MakeDefault with True makes the button the default button');
  Btn.MakeDefault(False);
  Check((LogCount = 2) and (LogCode[1] = cmReleaseDefault) and not Btn.GetDefault,
    'MakeDefault with False releases the default');
  Fixed.MakeDefault(False);
  Check((LogCount = 2) and Fixed.GetDefault, 'MakeDefault does nothing to a button with the flag');

  ClearScreen;
  Btn.SetState(sfSelected, True);
  Check(CharAt(4, 0) = 'O', 'a button is drawn when it is selected');
  ClearScreen;
  Btn.SetState(sfActive, True);
  Check(CharAt(4, 0) = 'O', 'a button is drawn when it becomes active');
  ClearScreen;
  Btn.SetState(sfDisabled, True);
  Check(CharAt(4, 0) = #0, 'a button is not drawn when it is disabled');
  FreeRoot(Root);
  TButton.Shadows := #$DC#$DB#$DF;
end;

procedure TestButtonPressAndDestroy;
var
  Root: TRoot;
  Btn: TTestButton;
  Ev: TEvent;
begin
  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), 'x', 77, bfNormal);
  Root.Insert(Btn);
  ResetLog;
  Btn.Press;
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = 77) and
    (Root.LastPut.Message.InfoPtr = Pointer(Btn)), 'Press puts the command of the button');
  Check((LogCount = 1) and (LogCode[0] = cmRecordHistory) and (LogKind[0] = evBroadcast),
    'Press records the history through the owner');
  FreeRoot(Root);

  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Root.Insert(Btn);
  Btn.State := Btn.State or sfFocused;
  Ev := CharKeyEv(' ', $39);
  Btn.HandleEvent(Ev);
  Check(Root.TimerCount = 1, 'the button has a timer');
  Root.RemoveView(Btn);
  Btn.Free;
  Check((Root.KillCount = 1) and (Root.LastKilled = Pointer(1)), 'a button that is destroyed kills its timer');
  FreeRoot(Root);

  Root := NewRoot;
  Btn := TTestButton.Create(Rc(0, 0, 10, 2), '~O~K', cmOK, bfNormal);
  Btn.Owner := Root;
  Btn.Free;
  Check((Root.KillCount = 1) and (Root.LastKilled = nil), 'a button without a timer asks to kill no timer');
  FreeRoot(Root);
end;

procedure TestDialogConstruction;
var
  Root: TRoot;
  Dlg, Fresh: TDialog;
  Pal: TPalette;
begin
  Root := NewRoot;
  Dlg := TDialog.Create(Rc(2, 1, 32, 12), 'Dlg');
  Check(Dlg.GrowMode = 0, 'a dialog does not grow with its owner');
  Check(Dlg.Flags = (wfMove or wfClose), 'a dialog can move and close');
  Check(Dlg.Palette = dpGrayDialog, 'a dialog has the gray palette');
  Check(Dlg.Number = wnNoNumber, 'a dialog has no number');
  Check(StrPas(Dlg.Title) = 'Dlg', 'a dialog keeps its title');
  Check((Dlg.Frame <> nil) and (Dlg.Frame.Owner = TGroup(Dlg)), 'a dialog has a frame');
  Check((Dlg.State and sfShadow) <> 0, 'a dialog has a shadow');
  Check((Dlg.Options and (ofSelectable or ofTopSelect)) = (ofSelectable or ofTopSelect),
    'a dialog can be selected and comes to the top');
  Check(Dlg.GetBounds = Rc(2, 1, 32, 12), 'the bounds of a dialog');

  Pal := Dlg.GetPalette;
  Check((PalByte(Pal, 0) = 32) and (PalByte(Pal, 1) = $20) and (PalByte(Pal, 6) = $25) and (PalByte(Pal, 32) = $3F),
    'the gray palette maps to the entries 32 to 63');
  Check(Dlg.GetPalette = Pal, 'the palette of a dialog is one object');
  Dlg.Palette := dpBlueDialog;
  Pal := Dlg.GetPalette;
  Check((PalByte(Pal, 0) = 32) and (PalByte(Pal, 1) = $40) and (PalByte(Pal, 32) = $5F),
    'the blue palette maps to the entries 64 to 95');
  Dlg.Palette := dpCyanDialog;
  Pal := Dlg.GetPalette;
  Check((PalByte(Pal, 0) = 32) and (PalByte(Pal, 1) = $60) and (PalByte(Pal, 32) = $7F),
    'the cyan palette maps to the entries 96 to 127');
  Fresh := TDialog.Create(Rc(0, 0, 20, 8), 'x');
  Dlg.Palette := 7;
  Check(Dlg.GetPalette = Fresh.GetPalette, 'another value gives the gray palette');
  Check(PalByte(Dlg.GetPalette, 1) = $20, 'the palette for another value maps to the entries 32 to 63');
  TvObject.DestroyObject(Fresh);
  TvObject.DestroyObject(Dlg);
  FreeRoot(Root);
end;

procedure TestDialogColors;
var
  Root: TRoot;
  Dlg: TDialog;
  Txt: TStaticText;
begin
  Root := NewRoot;
  Dlg := TDialog.Create(Rc(2, 1, 32, 12), 'Dlg');
  Root.Insert(Dlg);
  Txt := TStaticText.Create(Rc(1, 1, 6, 2), 'Hi');
  Dlg.Insert(Txt);
  ClearScreen;
  Txt.DrawView;
  Check((CharAt(3, 2) = 'H') and (CharAt(4, 2) = 'i'), 'a control is drawn inside its dialog');
  Check(AttrAt(3, 2) = $25, 'the colors of a control lead through the gray palette of a dialog');
  Dlg.Palette := dpBlueDialog;
  ClearScreen;
  Txt.DrawView;
  Check(AttrAt(3, 2) = $45, 'the colors of a control lead through the blue palette of a dialog');
  Dlg.Palette := dpCyanDialog;
  ClearScreen;
  Txt.DrawView;
  Check(AttrAt(3, 2) = $65, 'the colors of a control lead through the cyan palette of a dialog');
  FreeRoot(Root);
end;

procedure TestDialogEvents;
var
  Root: TRoot;
  Dlg: TDialog;
  Ev: TEvent;
  Commands: array[0..3] of Word;
  K: Integer;
  AllEnded: Boolean;
begin
  Root := NewRoot;
  Dlg := TDialog.Create(Rc(2, 1, 32, 12), 'Dlg');
  Root.Insert(Dlg);

  Ev := KeyEv(kbEsc);
  Dlg.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the Esc key is taken');
  Check((Root.PutCount = 1) and (Root.LastPut.What = evCommand) and (Root.LastPut.Message.Command = cmCancel) and
    (Root.LastPut.Message.InfoPtr = nil), 'the Esc key puts cmCancel');

  Ev := KeyEv(kbEnter);
  Dlg.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'the Enter key is taken');
  Check((Root.PutCount = 2) and (Root.LastPut.What = evBroadcast) and (Root.LastPut.Message.Command = cmDefault) and
    (Root.LastPut.Message.InfoPtr = nil), 'the Enter key puts a broadcast of cmDefault');

  Ev := KeyEv($3B00);
  Dlg.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (Root.PutCount = 2), 'another key is not taken');

  Commands[0] := cmOK;
  Commands[1] := cmCancel;
  Commands[2] := cmYes;
  Commands[3] := cmNo;
  for K := 0 to 3 do
  begin
    Ev := CmdEv(Commands[K]);
    Dlg.HandleEvent(Ev);
  end;
  Check((Ev.What = evCommand) and (Dlg.EndState = 0), 'a dialog that is not modal does not end at a command');

  Dlg.State := Dlg.State or sfModal;
  AllEnded := True;
  for K := 0 to 3 do
  begin
    Dlg.EndState := 0;
    Ev := CmdEv(Commands[K]);
    Dlg.HandleEvent(Ev);
    if (Ev.What <> evNothing) or (Dlg.EndState <> Commands[K]) then
      AllEnded := False;
  end;
  Check(AllEnded, 'a modal dialog ends at cmOK, cmCancel, cmYes and cmNo and takes the command');

  Dlg.EndState := 0;
  Ev := CmdEv(cmNew);
  Dlg.HandleEvent(Ev);
  Check((Ev.What = evCommand) and (Dlg.EndState = 0), 'a modal dialog does not end at another command');
  Dlg.State := Dlg.State and not sfModal;
  FreeRoot(Root);
end;

procedure TestDialogValid;
var
  Dlg: TDialog;
  Bad: TInvalidView;
begin
  Dlg := TDialog.Create(Rc(0, 0, 20, 8), 'x');
  Check(Dlg.Valid(cmOK), 'a dialog with valid controls is valid');
  Bad := TInvalidView.Create(Rc(1, 1, 4, 2));
  Dlg.Insert(Bad);
  Check(Dlg.Valid(cmCancel), 'cmCancel is always valid');
  Check(not Dlg.Valid(cmOK), 'a dialog with a control that is not valid is not valid');
  Check(not Dlg.Valid(cmYes), 'the same holds for another command');
  Dlg.Remove(Bad);
  Check(Dlg.Valid(cmOK), 'a dialog is valid again without the control');
  Bad.Free;
  TvObject.DestroyObject(Dlg);
end;

procedure TestDialogModal;
var
  Root: TRoot;
  Dlg: TDialog;
  Btn: TButton;
  R: Word;
begin
  TButton.Shadows := 'abc';
  Root := NewRoot;
  Root.Requeue := True;
  Dlg := TLogDialog.Create(Rc(5, 3, 30, 10), 'Dlg');
  Btn := TButton.Create(Rc(2, 4, 12, 6), '~O~K', cmOK, bfDefault);
  Dlg.Insert(Btn);
  Root.AddEvent(KeyEv(kbEnter));
  Root.AddEvent(BroadcastEv(cmTimerExpired, Pointer(1)));
  R := Root.ExecView(Dlg);
  Check(R = cmOK, 'Enter presses the default button, which ends the dialog with its command');
  Check((Root.TimerCount = 1) and (Root.LastTimeout = 100), 'the default button animated its press with one timer');
  Check(LogHas(cmRecordHistory), 'the press recorded the history through the dialog');
  Check((Root.ScriptPos = 2) and (Root.ErrorCount = 0), 'every event was taken by a view');
  TvObject.DestroyObject(Dlg);
  FreeRoot(Root);

  Root := NewRoot;
  Root.Requeue := True;
  Dlg := TDialog.Create(Rc(5, 3, 30, 10), 'Dlg');
  Btn := TButton.Create(Rc(2, 4, 12, 6), '~O~K', cmOK, bfDefault);
  Dlg.Insert(Btn);
  Root.AddEvent(KeyEv(kbEsc));
  R := Root.ExecView(Dlg);
  Check(R = cmCancel, 'Esc ends the dialog with cmCancel');
  Check((Root.TimerCount = 0) and (Root.ErrorCount = 0), 'Esc starts no timer and every event was taken');
  TvObject.DestroyObject(Dlg);
  FreeRoot(Root);
  TButton.Shadows := #$DC#$DB#$DF;
end;

procedure TestThreads;
var
  Root: TRoot;
  Dlg: TDialog;
  Poster: TPoster;
  Start: Int64;
  R: Word;
begin
  Root := NewRoot;
  Root.UseQueue := True;
  Root.Deadline := Now64 + 25000;
  Dlg := TDialog.Create(Rc(5, 3, 25, 13), 'Modal');
  Poster := TPoster.Create(0, 250);
  Start := Now64;
  R := Root.ExecView(Dlg);
  Check(R = cmOK, 'an event that is posted from a second thread during ExecView is delivered');
  Check(Now64 - Start < Guard - 1000, 'the posted event ended the wait');
  Check(Now64 - Start >= 150, 'the loop waited for the posted event');
  Poster.WaitFor;
  Poster.Free;
  Check(Root.ErrorCount = 0, 'the posted event was handled');

  TvObject.DestroyObject(Dlg);
  Dlg := TDialog.Create(Rc(5, 3, 25, 13), 'Modal');
  WakeFlag := 0;
  Poster := TPoster.Create(1, 250);
  Start := Now64;
  R := Root.ExecView(Dlg);
  Check(R = cmOK, 'a wake-up from a second thread during ExecView ends the wait');
  Check(Now64 - Start < Guard - 1000, 'the wake-up ended the wait');
  Poster.WaitFor;
  Poster.Free;
  TvObject.DestroyObject(Dlg);

  Dlg := TDialog.Create(Rc(5, 3, 25, 13), 'Modal');
  Poster := TPoster.Create(0, 0);
  Poster.WaitFor;
  Poster.Free;
  Start := Now64;
  R := Root.ExecView(Dlg);
  Check((R = cmOK) and (Now64 - Start < Guard - 1000), 'an event that was posted before ExecView is delivered at once');
  TvObject.DestroyObject(Dlg);
  FreeRoot(Root);
end;

var
  EventBackend: TEventBackend;
  Queue: TEventQueue;
  SavedBackend: TScreenBackend;
  K: Integer;
  PaletteText: string;

begin
  PaletteText := '';
  for K := 1 to 127 do
    PaletteText := PaletteText + Chr(K);
  RootPal := TPalette.Create(PaletteText, 127);

  Fake := TFakeDisplay.Create;
  SavedBackend := TDisplay.Backend;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;
  HotKeyHook := @TestHotKey;
  EventBackend := TEventBackend.Create;
  TEventQueue.Backend := EventBackend;
  Queue := TEventQueue.Create;

  TestTables;
  TestStaticConstruction;
  TestStaticDraw;
  TestParamText;
  TestLabelConstruction;
  TestLabelDraw;
  TestLabelEvents;
  TestButtonConstruction;
  TestButtonDraw;
  TestButtonMouse;
  TestButtonKeys;
  TestButtonBroadcasts;
  TestButtonState;
  TestButtonPressAndDestroy;
  TestDialogConstruction;
  TestDialogColors;
  TestDialogEvents;
  TestDialogValid;
  TestDialogModal;
  TestThreads;

  Queue.Free;
  TEventQueue.Backend := nil;
  EventBackend.Free;
  HotKeyHook := nil;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
