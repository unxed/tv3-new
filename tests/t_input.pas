{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (the limit modes and TInputLine), include/tvision/views.h,
  include/tvision/validate.h (TValidator and TVTransfer), include/tvision/ttypes.h, include/tvision/tv.h,
  include/tvision/config.h, source/tvision/tinputli.cpp, source/tvision/tvtext1.cpp (the two arrows of TInputLine)
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it and
  reads its events from a script. The colors of the root are the BIOS attributes 1 to 127: the entry k of its
  palette is k, so the attribute of a cell is the entry of the palette of the root that the palette of the line
  leads to (19 passive and active text, 20 selected text, 21 arrows). Lines whose behaviour does not depend on an
  owner have none and are driven through HandleEvent directly. The arrows are set to the letters > and <, so that
  the cells can be read as text; their values in the C++ are checked first. The clipboard has a backend that notes
  its calls. }
program t_input;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  SysUtils, TvGeom, TvKeys, TvEvents, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvViews, TvClip, TvValid,
  TvDialog, TvMenus, TvInput;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 20;
  MaxCalls = 100000;
  WideCh = #$E6#$97#$A5;
  AcuteCh = #$C3#$A9;

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
    ErrorCount: Integer;
    procedure AddEvent(const Ev: TEvent);
    procedure GetEvent(var Event: TEvent); override;
    procedure EventError(var Event: TEvent); override;
    function GetPalette: TPalette; override;
  end;

  { A selectable view that draws nothing. }
  TSel = class(TView)
  public
    procedure Draw; override;
  end;

  { A line that shows the members that are protected. }
  TTestInput = class(TInputLine)
  public
    function CallCanScroll(Delta: Integer): Boolean;
    function CallMouseDelta(var Event: TEvent): Integer;
    function CallMousePos(var Event: TEvent): Integer;
    function CallDisplayedPos(Position: Integer): Integer;
    function CallCanUpdate: Boolean;
    function CallCheckValid(NoFill: Boolean): Boolean;
    procedure CallSaveState;
    procedure CallRestoreState;
    function GetAnchor: Integer;
    function GetValidator: TValidator;
    function OldState: string;
  end;

  { A validator whose answers the test sets and whose calls it counts. }
  TTestValidator = class(TValidator)
  public
    InputCalls: Integer;
    ValidCalls: Integer;
    TransferCalls: Integer;
    LastSuppress: Boolean;
    LastFlag: TVTransfer;
    RejectChar: Char;
    UpcaseText: Boolean;
    AppendText: string;
    ValidResult: Boolean;
    SizeAnswer: Word;
    constructor Create; reintroduce;
    destructor Destroy; override;
    procedure ShutDown; override;
    function IsValidInput(var Text: string; SuppressFill: Boolean): Boolean; override;
    function IsValid(const Text: string): Boolean; override;
    function Transfer(var Text: string; Buffer: Pointer; Flag: TVTransfer): Word; override;
  end;

  { A clipboard backend that notes its calls. }
  TNoteBackend = class(TClipboardBackend)
  public
    SetCalls: Integer;
    RequestCalls: Integer;
    LastSet: string;
    function SetText(const Text: string): Boolean; override;
    function RequestText(Accept: TTextProc): Boolean; override;
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  GetCalls: Integer;
  RootPal: TPalette;
  ShutDownCount: Integer;
  DestroyCount: Integer;

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

{ A key event that carries the text Str, which is at most four bytes. }
function TextEv(const Str: string; Code: Word): TEvent;
var
  index: Integer;
begin
  Result := KeyEv(Code);
  for index := 1 to Length(Str) do
    Result.KeyDown.Text[index - 1] := Byte(Str[index]);
  Result.KeyDown.TextLength := Length(Str);
end;

function TypeEv(Ch: Char): TEvent;
begin
  Result := TextEv(Ch, Word(Ord(Ch)));
end;

function ShiftEv(Code: Word): TEvent;
begin
  Result := KeyEv(Code);
  Result.KeyDown.ControlKeyState := kbLeftShift;
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

procedure TSel.Draw;
begin
end;

function TTestInput.CallCanScroll(Delta: Integer): Boolean;
begin
  Result := CanScroll(Delta);
end;

function TTestInput.CallMouseDelta(var Event: TEvent): Integer;
begin
  Result := MouseDelta(Event);
end;

function TTestInput.CallMousePos(var Event: TEvent): Integer;
begin
  Result := MousePos(Event);
end;

function TTestInput.CallDisplayedPos(Position: Integer): Integer;
begin
  Result := DisplayedPos(Position);
end;

function TTestInput.CallCanUpdate: Boolean;
begin
  Result := CanUpdateCommands;
end;

function TTestInput.CallCheckValid(NoFill: Boolean): Boolean;
begin
  Result := CheckValid(NoFill);
end;

procedure TTestInput.CallSaveState;
begin
  SaveState;
end;

procedure TTestInput.CallRestoreState;
begin
  RestoreState;
end;

function TTestInput.GetAnchor: Integer;
begin
  Result := Anchor;
end;

function TTestInput.GetValidator: TValidator;
begin
  Result := Validator;
end;

function TTestInput.OldState: string;
begin
  Result := OldData + '|' + IntToStr(OldCurPos) + '|' + IntToStr(OldFirstPos) + '|' + IntToStr(OldSelStart) +
    '|' + IntToStr(OldSelEnd);
end;

constructor TTestValidator.Create;
begin
  inherited Create;
  ValidResult := True;
  RejectChar := #0;
end;

destructor TTestValidator.Destroy;
begin
  Inc(DestroyCount);
  inherited Destroy;
end;

procedure TTestValidator.ShutDown;
begin
  Inc(ShutDownCount);
  inherited ShutDown;
end;

function TTestValidator.IsValidInput(var Text: string; SuppressFill: Boolean): Boolean;
var
  index: Integer;
begin
  Inc(InputCalls);
  LastSuppress := SuppressFill;
  Result := False;
  if (RejectChar <> #0) and (Pos(RejectChar, Text) > 0) then
    Exit;
  if UpcaseText then
    for index := 1 to Length(Text) do
      Text[index] := UpCase(Text[index]);
  if (not SuppressFill) and (AppendText <> '') and (Pos(AppendText, Text) = 0) then
    Text := Text + AppendText;
  Result := True;
end;

function TTestValidator.IsValid(const Text: string): Boolean;
begin
  Inc(ValidCalls);
  Result := ValidResult;
end;

function TTestValidator.Transfer(var Text: string; Buffer: Pointer; Flag: TVTransfer): Word;
begin
  Inc(TransferCalls);
  LastFlag := Flag;
  if (SizeAnswer <> 0) and (Flag = vtGetData) then
    PByte(Buffer)^ := 71;
  if (SizeAnswer <> 0) and (Flag = vtSetData) then
    Text := 'from-validator';
  Result := SizeAnswer;
end;

function TNoteBackend.SetText(const Text: string): Boolean;
begin
  Inc(SetCalls);
  LastSet := Text;
  Result := True;
end;

function TNoteBackend.RequestText(Accept: TTextProc): Boolean;
begin
  Inc(RequestCalls);
  Result := True;
end;

procedure TRoot.AddEvent(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TRoot.GetEvent(var Event: TEvent);
begin
  Inc(GetCalls);
  if GetCalls > MaxCalls then
  begin
    WriteLn('FAIL a loop of events does not end');
    Halt(1);
  end;
  FillChar(Event, SizeOf(Event), 0);
  if ScriptPos < Length(Script) then
  begin
    Event := Script[ScriptPos];
    Inc(ScriptPos);
  end;
end;

procedure TRoot.EventError(var Event: TEvent);
begin
  Inc(ErrorCount);
end;

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
end;

function NewRoot: TRoot;
begin
  ClearScreen;
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

{ A line of ten columns without an owner, selected, that holds Text with the cursor at Cur. }
function NewBare(const Text: string; Limit, Cur: Integer): TTestInput;
begin
  Result := TTestInput.Create(Rc(0, 0, 10, 1), Limit);
  Result.Data := Text;
  Result.CurPos := Cur;
  Result.State := Result.State or sfSelected;
end;

{ Gives the event to the line and tells whether the line took it. }
function Consumed(Line: TInputLine; Ev: TEvent): Boolean;
begin
  Line.HandleEvent(Ev);
  Result := Ev.What = evNothing;
end;

procedure TypeText(Line: TInputLine; const Str: string);
var
  index: Integer;
begin
  for index := 1 to Length(Str) do
    Consumed(Line, TypeEv(Str[index]));
end;

{ Sets the selection and the cursor of a line. }
procedure Place(Line: TInputLine; SelFrom, SelTo, Cur: Integer);
begin
  Line.SelStart := SelFrom;
  Line.SelEnd := SelTo;
  Line.CurPos := Cur;
end;

{ ---- the tests ---- }

procedure TestNames;
begin
  Check((ilMaxBytes = 0) and (ilMaxWidth = 1) and (ilMaxChars = 2), 'the limit modes');
  Check((TInputLine.RightArrow = #$10) and (TInputLine.LeftArrow = #$11), 'the arrows of a line');

  Check(HotKeyStr('~O~K') = 'O', 'the text between two tildes is the hot key text');
  Check(HotKeyStr('a~bc~d') = 'bc', 'the hot key text may have several characters');
  Check(HotKeyStr('plain') = '', 'a text without a tilde has no hot key text');
  Check(HotKeyStr('x~yz') = 'yz', 'without a second tilde the hot key text goes to the end');
  Check(HotKeyStr('~~') = '', 'two tildes enclose nothing');
  Check(HotKeyStr('~') = '', 'a single tilde at the end encloses nothing');
  Check(HotKeyStr('') = '', 'an empty text has no hot key text');
  Check(HotKey('~o~k') = 'O', 'the hot key is in upper case');
  Check(HotKey('a~bc~d') = 'B', 'the hot key is the first character of the hot key text');
  Check(HotKey('plain') = #0, 'a text without a tilde has no hot key');
  Check(HotKey('~~') = #0, 'an empty hot key text has no hot key');
  Check(HotKey('~5~') = '5', 'a digit is its own hot key');
  Check(HotKey('~' + #$E9 + '~') = #$E9, 'a byte above 127 is not changed');

  Check(Assigned(TvDialog.HotKeyHook) and (TvDialog.HotKeyHook('~q~') = 'Q'),
    'the hook of the hot keys of TvDialog is HotKey');
  Check(Assigned(TvMenus.HotKeyStrHook) and (TvMenus.HotKeyStrHook('ab~c~d') = 'c'),
    'the hook of the hot key text of TvMenus is HotKeyStr');
end;

procedure TestConstruction;
var
  Line, Other: TTestInput;
  Pal: TPalette;
  Valid: TTestValidator;
begin
  Line := TTestInput.Create(Rc(1, 2, 11, 3), 20);
  Check(Line.MaxLen = 19, 'a limit of bytes leaves room for the terminating zero');
  Check((Line.MaxWidth = High(LongInt)) and (Line.MaxChars = High(LongInt)), 'the other limits are not set');
  Check((Line.CurPos = 0) and (Line.FirstPos = 0) and (Line.SelStart = 0) and (Line.SelEnd = 0),
    'a new line has no cursor shift and no selection');
  Check(Line.Data = '', 'a new line is empty');
  Check((Line.State and sfCursorVis) <> 0, 'a line shows its cursor');
  Check((Line.State and sfVisible) <> 0, 'a line is visible');
  Check(Line.Options = (ofSelectable or ofFirstClick), 'a line can be selected and takes the first click');
  Check(Line.GetBounds = Rc(1, 2, 11, 3), 'the bounds of a line');
  Check(Line.DataSize = 20, 'the size of the data is the room for the text and the zero');
  Check(Line.GetValidator = nil, 'a line has no validator unless it is given one');

  Pal := Line.GetPalette;
  Check((PalByte(Pal, 0) = 4) and (PalByte(Pal, 1) = 19) and (PalByte(Pal, 2) = 19) and (PalByte(Pal, 3) = 20) and
    (PalByte(Pal, 4) = 21), 'the palette of a line');
  Other := TTestInput.Create(Rc(0, 0, 5, 1), 5);
  Check(Other.GetPalette = Pal, 'all lines share their palette');
  Other.Free;
  Line.Free;

  Line := TTestInput.Create(Rc(0, 0, 10, 1), 1);
  Check(Line.MaxLen = 0, 'a limit of one byte leaves no room');
  Line.Free;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 0);
  Check(Line.MaxLen = 0, 'a limit of zero bytes leaves no room');
  Line.Free;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), -3);
  Check(Line.MaxLen = 0, 'a negative limit leaves no room');
  Line.Free;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), High(LongInt));
  Check(Line.MaxLen = High(LongInt) - 1, 'the largest limit of bytes is one below the largest integer');
  Line.Free;

  Line := TTestInput.Create(Rc(0, 0, 10, 1), 8, nil, ilMaxWidth);
  Check((Line.MaxLen = 255) and (Line.MaxWidth = 8) and (Line.MaxChars = High(LongInt)),
    'a limit of columns sets the width only');
  Check(Line.DataSize = 256, 'the data of a line limited by width has room for 255 bytes');
  Line.Free;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 5, nil, ilMaxChars);
  Check((Line.MaxLen = 255) and (Line.MaxWidth = High(LongInt)) and (Line.MaxChars = 5),
    'a limit of characters sets the count only');
  Line.Free;

  Valid := TTestValidator.Create;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Check(Line.GetValidator = Valid, 'the line holds the validator it is given');
  Line.Free;
end;

procedure TestMeasures;
var
  Line: TTestInput;
begin
  Line := NewBare('hello', 40, 0);
  Check((Line.CallDisplayedPos(0) = 0) and (Line.CallDisplayedPos(3) = 3) and (Line.CallDisplayedPos(5) = 5),
    'the displayed position of a text of narrow characters');
  Line.Data := 'a' + WideCh + 'b';
  Check((Line.CallDisplayedPos(1) = 1) and (Line.CallDisplayedPos(4) = 3) and (Line.CallDisplayedPos(5) = 4),
    'a wide character takes two columns');
  Line.Data := 'a' + AcuteCh;
  Check(Line.CallDisplayedPos(3) = 2, 'a two byte character takes one column');

  Line.Data := 'hello';
  Check(not Line.CallCanScroll(1) and not Line.CallCanScroll(-1) and not Line.CallCanScroll(0),
    'a short text cannot scroll');
  Line.Data := 'abcdefgh';
  Check(not Line.CallCanScroll(1), 'a text that fills the view up to its margins cannot scroll');
  Line.Data := 'abcdefghi';
  Check(Line.CallCanScroll(1), 'a text one column too long can scroll to the right');
  Check(not Line.CallCanScroll(0), 'a zero step never scrolls');
  Line.FirstPos := 1;
  Check(not Line.CallCanScroll(1), 'once scrolled the rest fits');
  Check(Line.CallCanScroll(-1), 'a scrolled text can scroll back');
  Line.Free;
end;

procedure TestStateBlock;
var
  Line: TTestInput;
  Valid: TTestValidator;
begin
  Line := NewBare('abc', 20, 2);
  Line.FirstPos := 1;
  Line.SelStart := 1;
  Line.SelEnd := 2;
  Line.CallSaveState;
  Check(Line.OldState = '|0|0|0|0', 'a line without a validator saves nothing');
  Line.Data := 'zzz';
  Line.CallRestoreState;
  Check((Line.Data = 'zzz') and (Line.CurPos = 2), 'a line without a validator restores nothing');
  Check(Line.CallCheckValid(True) and Line.CallCheckValid(False), 'a line without a validator is always valid');
  Check(Line.Data = 'zzz', 'a check without a validator leaves the text');
  Line.Free;

  Valid := TTestValidator.Create;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Line.Data := 'abc';
  Place(Line, 1, 2, 2);
  Line.FirstPos := 1;
  Line.CallSaveState;
  Check(Line.OldState = 'abc|2|1|1|2', 'the state that is saved');
  Line.Data := 'q';
  Place(Line, 0, 0, 0);
  Line.FirstPos := 0;
  Line.CallRestoreState;
  Check((Line.Data = 'abc') and (Line.CurPos = 2) and (Line.FirstPos = 1) and (Line.SelStart = 1) and
    (Line.SelEnd = 2), 'the state that is restored');

  Valid.RejectChar := 'x';
  Line.Data := 'a';
  Line.CurPos := 1;
  Line.CallSaveState;
  Line.Data := 'ax';
  Line.CurPos := 2;
  Check(not Line.CallCheckValid(True), 'a text that the validator refuses is not valid');
  Check((Line.Data = 'a') and (Line.CurPos = 1), 'a refused text is replaced by the saved one');
  Valid.RejectChar := #0;
  Line.Data := 'ok';
  Check(Line.CallCheckValid(False), 'a text that the validator accepts is valid');
  Check((Valid.InputCalls = 2) and not Valid.LastSuppress, 'the validator is asked with the flag it is given');
  Line.Free;
end;

procedure TestDraw;
var
  Root: TRoot;
  Line: TTestInput;
begin
  TInputLine.RightArrow := '>';
  TInputLine.LeftArrow := '<';

  Root := NewRoot;
  Line := TTestInput.Create(Rc(2, 1, 12, 2), 20);
  Root.Insert(Line);
  Line.Data := 'hello';
  Line.State := Line.State or sfSelected;
  Place(Line, 0, 5, 5);
  ClearScreen;
  Line.DrawView;
  Check(RowText(1, 2, 10) = ' hello    ', 'the text starts in the second column of the line');
  Check((AttrAt(2, 1) = 19) and (AttrAt(8, 1) = 19) and (AttrAt(11, 1) = 19), 'the text has the passive color');
  Check((AttrAt(3, 1) = 20) and (AttrAt(7, 1) = 20), 'the selected text has the selection color');
  Check((CharAt(1, 1) = #0) and (CharAt(12, 1) = #0), 'a line writes only inside its area');
  Check((Line.Cursor.X = 6) and (Line.Cursor.Y = 0), 'the cursor is after the text');

  Line.State := Line.State and not sfSelected;
  ClearScreen;
  Line.DrawView;
  Check(RowText(1, 2, 10) = ' hello    ', 'a line that is not selected shows its text');
  Check((AttrAt(3, 1) = 19) and (AttrAt(7, 1) = 19), 'a line that is not selected shows no selection');

  Line.State := Line.State or sfSelected;
  Line.Data := 'abcdefghijklmnop';
  Line.FirstPos := 3;
  Place(Line, 0, 0, 0);
  ClearScreen;
  Line.DrawView;
  Check(RowText(1, 2, 10) = '<defghijk>', 'a scrolled text shows an arrow at each end');
  Check((AttrAt(2, 1) = 21) and (AttrAt(11, 1) = 21) and (AttrAt(3, 1) = 19) and (AttrAt(10, 1) = 19),
    'the arrows have their own color');
  Check(Line.Cursor.X = -2, 'the cursor is left of the view when the cursor position is scrolled out');

  Line.FirstPos := 0;
  Place(Line, 2, 14, 14);
  ClearScreen;
  Line.DrawView;
  Check(RowText(1, 2, 10) = ' abcdefgh>', 'a long text has only the right arrow when it is not scrolled');
  Check((AttrAt(4, 1) = 19) and (AttrAt(5, 1) = 20) and (AttrAt(10, 1) = 20) and (AttrAt(11, 1) = 21),
    'the selection stops before the arrow');
  Check(Line.Cursor.X = 15, 'the cursor column is not limited to the view');

  Line.FirstPos := 4;
  Place(Line, 2, 7, 7);
  ClearScreen;
  Line.DrawView;
  Check(RowText(1, 2, 10) = '<efghijkl>', 'a text that is scrolled by four columns');
  Check((AttrAt(2, 1) = 21) and (AttrAt(3, 1) = 20) and (AttrAt(5, 1) = 20) and (AttrAt(6, 1) = 19),
    'the selection is shifted with the text');
  Check(Line.Cursor.X = 4, 'the cursor is shifted with the text');

  Line.Data := 'a' + WideCh + 'b';
  Line.FirstPos := 0;
  Place(Line, 0, 0, 5);
  Line.DrawView;
  Check(Line.Cursor.X = 5, 'the cursor column counts display columns');
  FreeRoot(Root);

  Root := NewRoot;
  Line := TTestInput.Create(Rc(0, 5, 1, 6), 20);
  Root.Insert(Line);
  Line.Data := 'hello';
  ClearScreen;
  Line.DrawView;
  Check((CharAt(0, 5) = '>') and (AttrAt(0, 5) = 21), 'a line of one column shows only the arrow');
  FreeRoot(Root);

  TInputLine.RightArrow := #$10;
  TInputLine.LeftArrow := #$11;
end;

procedure TestTyping;
var
  Line: TTestInput;
begin
  Line := NewBare('', 20, 0);
  Check(Consumed(Line, TypeEv('a')), 'a typed character is taken');
  Check((Line.Data = 'a') and (Line.CurPos = 1), 'a character is put in at the cursor');
  Check((Line.SelStart = 0) and (Line.SelEnd = 0), 'typing leaves no selection');
  TypeText(Line, 'bc');
  Check((Line.Data = 'abc') and (Line.CurPos = 3), 'more characters follow');
  Check(Consumed(Line, KeyEv(kbLeft)) and (Line.CurPos = 2), 'Left moves the cursor back');
  TypeText(Line, 'X');
  Check((Line.Data = 'abXc') and (Line.CurPos = 3), 'a character goes in before the rest of the text');
  Check(Consumed(Line, KeyEv(kbHome)) and (Line.CurPos = 0), 'Home moves the cursor to the start');
  Check(Consumed(Line, KeyEv(kbEnd)) and (Line.CurPos = 4), 'End moves the cursor to the end');
  Check(Consumed(Line, KeyEv(kbBack)), 'Backspace is taken');
  Check((Line.Data = 'abX') and (Line.CurPos = 3), 'Backspace removes the character before the cursor');
  Consumed(Line, KeyEv(kbHome));
  Check(Consumed(Line, KeyEv(kbDel)) and (Line.Data = 'bX') and (Line.CurPos = 0),
    'Delete removes the character at the cursor');

  Check(Consumed(Line, KeyEv(kbIns)) and ((Line.State and sfCursorIns) <> 0), 'Insert turns overwriting on');
  TypeText(Line, 'Z');
  Check((Line.Data = 'ZX') and (Line.CurPos = 1), 'an overwriting character replaces the one at the cursor');
  Consumed(Line, KeyEv(kbIns));
  Check((Line.State and sfCursorIns) = 0, 'Insert turns overwriting off');
  Line.Free;

  Line := NewBare('abc', 20, 3);
  Check(Consumed(Line, KeyEv(kbRight)) and (Line.CurPos = 3), 'Right stops at the end of the text');
  Check(Consumed(Line, KeyEv(kbDel)) and (Line.Data = 'abc'), 'Delete at the end removes nothing');
  Place(Line, 0, 0, 0);
  Check(Consumed(Line, KeyEv(kbLeft)) and (Line.CurPos = 0), 'Left stops at the start of the text');
  Check(Consumed(Line, KeyEv(kbBack)) and (Line.Data = 'abc'), 'Backspace at the start removes nothing');
  Line.CurPos := 3;
  Check(Consumed(Line, KeyEv(25)) and (Line.Data = '') and (Line.CurPos = 0), 'Ctrl-Y clears the line');
  Line.Free;

  Line := NewBare('abc', 20, 0);
  Line.State := Line.State and not sfSelected;
  Check(not Consumed(Line, TypeEv('x')) and (Line.Data = 'abc'), 'a line that is not selected takes no keys');
  Line.State := Line.State or sfSelected;
  Check(not Consumed(Line, KeyEv(kbF1)), 'a key without text that the line does not know is left to others');
  Check(Line.Data = 'abc', 'a key that is left leaves the text');
  Line.Free;

  Line := NewBare('a' + AcuteCh + 'b', 20, 3);
  Check(Consumed(Line, KeyEv(kbLeft)) and (Line.CurPos = 1), 'Left goes back over a two byte character');
  Check(Consumed(Line, KeyEv(kbRight)) and (Line.CurPos = 3), 'Right goes over a two byte character');
  Check(Consumed(Line, KeyEv(kbBack)) and (Line.Data = 'ab') and (Line.CurPos = 1),
    'Backspace removes a whole two byte character');
  Line.Data := 'a' + AcuteCh + 'b';
  Line.CurPos := 1;
  Check(Consumed(Line, KeyEv(kbDel)) and (Line.Data = 'ab') and (Line.CurPos = 1),
    'Delete removes a whole two byte character');
  Line.Data := 'a';
  Line.CurPos := 1;
  Check(Consumed(Line, TextEv(AcuteCh, $00C3)) and (Line.Data = 'a' + AcuteCh) and (Line.CurPos = 3),
    'a two byte character is put in whole');
  Line.Free;

  Line := NewBare('', 20, 0);
  Consumed(Line, TextEv(#9, kbTab));
  Check(Line.Data = ' ', 'a tab becomes a space');
  Consumed(Line, TextEv(#13, kbEnter));
  Check(Line.Data = '  ', 'a carriage return becomes a space');
  Consumed(Line, TextEv(#10, $000A));
  Check(Line.Data = '   ', 'a line feed becomes a space');
  Line.Data := '';
  Line.CurPos := 0;
  Check(Consumed(Line, TextEv('a' + #0 + 'b', $0061)) and (Line.Data = 'a') and (Line.CurPos = 1),
    'the text of a key ends at its first zero character');
  Line.Free;

  Line := NewBare('hello', 20, 3);
  Check(Consumed(Line, KeyEv(kbCtrlA)) and (Line.CurPos = 0), 'Ctrl-A is Home');
  Check(Consumed(Line, KeyEv(kbCtrlF)) and (Line.CurPos = 5), 'Ctrl-F is End');
  Check(Consumed(Line, KeyEv(kbCtrlS)) and (Line.CurPos = 4), 'Ctrl-S is Left');
  Check(Consumed(Line, KeyEv(kbCtrlD)) and (Line.CurPos = 5), 'Ctrl-D is Right');
  Line.CurPos := 0;
  Check(Consumed(Line, KeyEv(kbCtrlG)) and (Line.Data = 'ello'), 'Ctrl-G is Delete');
  Line.Free;
end;

procedure TestLimits;
var
  Line: TTestInput;
begin
  Line := NewBare('', 4, 0);
  TypeText(Line, 'abcd');
  Check((Line.Data = 'abc') and (Line.CurPos = 3), 'a character beyond the limit of bytes is refused');
  Check(Consumed(Line, TypeEv('e')), 'a refused character is taken all the same');
  Place(Line, 0, 3, 3);
  TypeText(Line, 'x');
  Check((Line.Data = 'x') and (Line.CurPos = 1), 'a selection makes room for a character');
  Line.Free;

  Line := NewBare('abc', 4, 0);
  Line.State := Line.State or sfCursorIns;
  TypeText(Line, 'Z');
  Check((Line.Data = 'Zbc') and (Line.CurPos = 1), 'overwriting fits in a full line');
  Line.Free;

  Line := TTestInput.Create(Rc(0, 0, 10, 1), 2, nil, ilMaxChars);
  Line.State := Line.State or sfSelected;
  TypeText(Line, 'abc');
  Check((Line.Data = 'ab') and (Line.CurPos = 2), 'a character beyond the limit of characters is refused');
  Line.Free;

  Line := TTestInput.Create(Rc(0, 0, 10, 1), 3, nil, ilMaxWidth);
  Line.State := Line.State or sfSelected;
  TypeText(Line, 'a');
  Consumed(Line, TextEv(WideCh, $00E6));
  Check((Line.Data = 'a' + WideCh) and (Line.CurPos = 4), 'a wide character fits when its columns fit');
  TypeText(Line, 'b');
  Check((Line.Data = 'a' + WideCh) and (Line.CurPos = 4), 'a character beyond the limit of columns is refused');
  Line.Free;

  Line := NewBare('', 30, 0);
  TypeText(Line, 'abcdefgh');
  Check(Line.FirstPos = 0, 'the view does not scroll while the cursor is inside it');
  TypeText(Line, 'i');
  Check(Line.FirstPos = 1, 'the view scrolls when the cursor leaves it');
  TypeText(Line, 'jkl');
  Check(Line.FirstPos = 4, 'the view follows the cursor');
  Consumed(Line, KeyEv(kbHome));
  Check(Line.FirstPos = 0, 'Home scrolls back to the start');
  Consumed(Line, KeyEv(kbEnd));
  Check(Line.FirstPos = 4, 'End scrolls to the cursor');
  Line.Free;

  Line := NewBare('abcdefghijklmnopqrst', 40, 0);
  Consumed(Line, KeyEv(kbEnd));
  Check((Line.CurPos = 20) and (Line.FirstPos = 12), 'End on a long text scrolls to the cursor');
  Line.Free;
end;

procedure TestSelectionKeys;
var
  Line: TTestInput;
begin
  Line := NewBare('hello', 20, 0);
  Check(Consumed(Line, ShiftEv(kbRight)), 'Shift-Right is taken');
  Check((Line.CurPos = 1) and (Line.SelStart = 0) and (Line.SelEnd = 1), 'Shift-Right selects the character');
  Consumed(Line, ShiftEv(kbRight));
  Check((Line.CurPos = 2) and (Line.SelStart = 0) and (Line.SelEnd = 2), 'Shift-Right extends the selection');
  Consumed(Line, ShiftEv(kbLeft));
  Check((Line.CurPos = 1) and (Line.SelStart = 0) and (Line.SelEnd = 1), 'Shift-Left shrinks the selection');
  Consumed(Line, ShiftEv(kbLeft));
  Check((Line.CurPos = 0) and (Line.SelStart = 0) and (Line.SelEnd = 0), 'Shift-Left can empty the selection');

  Place(Line, 0, 0, 3);
  Consumed(Line, ShiftEv(kbHome));
  Check((Line.CurPos = 0) and (Line.SelStart = 0) and (Line.SelEnd = 3), 'Shift-Home selects to the start');
  Consumed(Line, ShiftEv(kbEnd));
  Check((Line.CurPos = 5) and (Line.SelStart = 3) and (Line.SelEnd = 5),
    'Shift-End anchors at the far end of the selection');
  Consumed(Line, KeyEv(kbLeft));
  Check((Line.CurPos = 4) and (Line.SelStart = 0) and (Line.SelEnd = 0), 'a key without shift drops the selection');

  Line.Data := 'hello';
  Place(Line, 1, 4, 4);
  TypeText(Line, 'X');
  Check((Line.Data = 'hXo') and (Line.CurPos = 2) and (Line.SelEnd = 0), 'typing replaces the selection');
  Line.Data := 'hello';
  Place(Line, 1, 4, 4);
  Consumed(Line, KeyEv(kbBack));
  Check((Line.Data = 'ho') and (Line.CurPos = 1), 'Backspace removes the selection');
  Line.Data := 'hello';
  Place(Line, 1, 4, 4);
  Consumed(Line, KeyEv(kbDel));
  Check((Line.Data = 'ho') and (Line.CurPos = 1), 'Delete removes the selection');
  Line.Free;

  Line := NewBare('ab cd  ef', 20, 9);
  Consumed(Line, KeyEv(kbCtrlLeft));
  Check(Line.CurPos = 7, 'Ctrl-Left goes to the start of the word');
  Consumed(Line, KeyEv(kbCtrlLeft));
  Check(Line.CurPos = 3, 'Ctrl-Left skips blanks');
  Consumed(Line, KeyEv(kbCtrlLeft));
  Check(Line.CurPos = 0, 'Ctrl-Left goes to the start of the text from the first word');
  Consumed(Line, KeyEv(kbCtrlRight));
  Check(Line.CurPos = 3, 'Ctrl-Right goes to the start of the next word');
  Consumed(Line, KeyEv(kbCtrlRight));
  Check(Line.CurPos = 7, 'Ctrl-Right skips blanks');
  Consumed(Line, KeyEv(kbCtrlRight));
  Check(Line.CurPos = 9, 'Ctrl-Right goes to the end from the last word');
  Consumed(Line, KeyEv(kbCtrlBack));
  Check((Line.Data = 'ab cd  ') and (Line.CurPos = 7), 'Ctrl-Backspace removes the word before the cursor');
  Consumed(Line, KeyEv(kbAltBack));
  Check((Line.Data = 'ab ') and (Line.CurPos = 3), 'Alt-Backspace removes the word before the cursor');
  Line.Data := 'ab cd';
  Line.CurPos := 0;
  Consumed(Line, KeyEv(kbCtrlDel));
  Check((Line.Data = 'cd') and (Line.CurPos = 0), 'Ctrl-Delete removes the word at the cursor');
  Line.Data := 'ab cd';
  Line.CurPos := 3;
  Consumed(Line, KeyEv(kbCtrlDel));
  Check((Line.Data = 'ab ') and (Line.CurPos = 3), 'Ctrl-Delete in the last word removes up to the end');
  Line.Free;
end;

procedure TestSelectAndData;
var
  Line: TTestInput;
  Buf: array[0..31] of Byte;
  Valid: TTestValidator;
  index: Integer;
begin
  Line := TTestInput.Create(Rc(0, 0, 5, 1), 20);
  Line.Data := 'abcdefgh';
  Line.SelectAll(True);
  Check((Line.CurPos = 8) and (Line.SelStart = 0) and (Line.SelEnd = 8), 'SelectAll selects the whole text');
  Check(Line.FirstPos = 5, 'SelectAll scrolls to the cursor');
  Line.SelectAll(False);
  Check((Line.CurPos = 0) and (Line.SelEnd = 0) and (Line.FirstPos = 0), 'SelectAll with False drops the selection');
  Line.FirstPos := 1;
  Line.SelectAll(True, False);
  Check((Line.CurPos = 8) and (Line.SelEnd = 8) and (Line.FirstPos = 1), 'SelectAll can leave the scroll as it is');
  Line.Free;

  Line := TTestInput.Create(Rc(0, 0, 10, 1), 8);
  Line.Data := 'abc';
  for index := 0 to 31 do
    Buf[index] := $55;
  Line.GetData(@Buf[0]);
  Check((Buf[0] = Ord('a')) and (Buf[1] = Ord('b')) and (Buf[2] = Ord('c')), 'GetData copies the text');
  Check((Buf[3] = 0) and (Buf[7] = 0), 'GetData fills the data with zeros after the text');
  Check(Buf[8] = $55, 'GetData does not write beyond the data');

  for index := 0 to 31 do
    Buf[index] := 0;
  Buf[0] := Ord('x');
  Buf[1] := Ord('y');
  Buf[2] := Ord('z');
  Buf[4] := Ord('q');
  Line.SetData(@Buf[0]);
  Check(Line.Data = 'xyz', 'SetData takes the text up to the first zero');
  Check((Line.SelStart = 0) and (Line.SelEnd = 3) and (Line.CurPos = 3), 'SetData selects the text');
  Check(Line.FirstPos = 0, 'a short text is not scrolled');

  for index := 0 to 31 do
    Buf[index] := Ord('A') + index;
  Line.SetData(@Buf[0]);
  Check(Line.Data = 'ABCDEFG', 'SetData takes at most the size of the data less one byte');
  Check(Line.SelEnd = 7, 'the selection covers the text that was taken');
  Line.Free;

  Valid := TTestValidator.Create;
  Valid.SizeAnswer := 4;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Check((Line.DataSize = 4) and (Valid.LastFlag = vtDataSize), 'the validator gives the size of the data');
  Line.Data := 'abc';
  Valid.TransferCalls := 0;
  for index := 0 to 31 do
    Buf[index] := $55;
  Line.GetData(@Buf[0]);
  Check((Buf[0] = 71) and (Buf[1] = $55), 'GetData leaves the record to the validator when it takes it');
  Check((Valid.TransferCalls = 1) and (Valid.LastFlag = vtGetData), 'GetData asks the validator once');
  Valid.TransferCalls := 0;
  Line.SetData(@Buf[0]);
  Check(Line.Data = 'from-validator', 'SetData leaves the text to the validator when it takes it');
  Check((Line.SelEnd = 14) and (Line.CurPos = 14), 'the text from the validator is selected');
  Check((Valid.TransferCalls = 1) and (Valid.LastFlag = vtSetData), 'SetData asks the validator once');

  Valid.SizeAnswer := 0;
  Check(Line.DataSize = 20, 'without an answer of the validator the size is the room for the text');
  Line.Data := 'abc';
  Valid.TransferCalls := 0;
  for index := 0 to 31 do
    Buf[index] := $55;
  Line.GetData(@Buf[0]);
  Check((Buf[0] = Ord('a')) and (Buf[2] = Ord('c')) and (Buf[3] = 0), 'GetData copies when the validator does not take it');
  Check((Valid.TransferCalls = 2) and (Valid.LastFlag = vtDataSize), 'GetData then asks the size of the data');
  for index := 0 to 31 do
    Buf[index] := 0;
  Buf[0] := Ord('x');
  Buf[1] := Ord('y');
  Valid.TransferCalls := 0;
  Line.SetData(@Buf[0]);
  Check(Line.Data = 'xy', 'SetData copies when the validator does not take it');
  Check((Valid.TransferCalls = 3) and (Valid.LastFlag = vtDataSize), 'SetData asks the size of the data twice');
  Line.Free;
end;

procedure TestValidation;
var
  Line: TTestInput;
  Valid: TTestValidator;
  Root: TRoot;
  Other: TSel;
begin
  Valid := TTestValidator.Create;
  Valid.RejectChar := 'x';
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Line.State := Line.State or sfSelected;
  TypeText(Line, 'a');
  Check((Line.Data = 'a') and (Line.CurPos = 1), 'a character that the validator accepts is put in');
  Check((Valid.InputCalls = 2) and not Valid.LastSuppress, 'the text is checked before and after the character');
  Check(Consumed(Line, TypeEv('x')), 'a refused character is taken');
  Check((Line.Data = 'a') and (Line.CurPos = 1) and (Valid.InputCalls = 4), 'a character that is refused is taken out');
  TypeText(Line, 'b');
  Check(Line.Data = 'ab', 'typing goes on after a refused character');
  Line.Free;

  Valid := TTestValidator.Create;
  Valid.RejectChar := 'x';
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Line.State := Line.State or sfSelected;
  Line.Data := 'axb';
  Line.CurPos := 3;
  Consumed(Line, KeyEv(kbBack));
  Check((Line.Data = 'axb') and (Line.CurPos = 3) and (Line.SelEnd = 0), 'a deletion that leaves a refused text is undone');
  Check(Valid.InputCalls = 1, 'a deletion asks the validator once');
  Place(Line, 0, 1, 1);
  Consumed(Line, KeyEv(kbDel));
  Check((Line.Data = 'axb') and (Line.CurPos = 1) and (Line.SelStart = 0) and (Line.SelEnd = 0),
    'a deletion of a selection that is refused is undone');
  Line.Data := 'ab';
  Line.CurPos := 2;
  Consumed(Line, KeyEv(kbBack));
  Check((Line.Data = 'a') and (Line.CurPos = 1), 'a deletion that the validator accepts is kept');
  Line.Free;

  Valid := TTestValidator.Create;
  Valid.UpcaseText := True;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Line.State := Line.State or sfSelected;
  TypeText(Line, 'a');
  Check((Line.Data = 'A') and (Line.CurPos = 1), 'the validator may change the text');
  TypeText(Line, 'b');
  Check((Line.Data = 'AB') and (Line.CurPos = 2), 'the changed text goes on');
  Line.Free;

  Valid := TTestValidator.Create;
  Valid.AppendText := '-';
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Line.State := Line.State or sfSelected;
  TypeText(Line, 'a');
  Check((Line.Data = 'a-') and (Line.CurPos = 2), 'a text that the validator lengthens moves the cursor to the end');
  TypeText(Line, 'b');
  Check((Line.Data = 'a-b') and (Line.CurPos = 3), 'a text that the validator keeps the length of keeps the cursor');
  Line.Free;

  Valid := TTestValidator.Create;
  Valid.AppendText := 'ZZZZ';
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 4, Valid);
  Line.State := Line.State or sfSelected;
  TypeText(Line, 'a');
  Check((Line.Data = 'aZZ') and (Line.CurPos = 3), 'a text from the validator is cut to the limit of bytes');
  Line.Free;

  Valid := TTestValidator.Create;
  Valid.RejectChar := 'x';
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Line.State := Line.State or sfSelected;
  Line.Data := 'abc';
  Check(Line.Valid(cmOK) and Line.Valid(cmClose), 'a line is valid when the validator says so');
  Check(Valid.ValidCalls = 2, 'every command but two asks the validator');
  Valid.ValidResult := False;
  Check(not Line.Valid(cmOK), 'a line is not valid when the validator says so');
  Check(Line.Valid(cmCancel), 'cmCancel is always valid');
  Check(Line.Valid(cmValid), 'cmValid asks the status of the validator');
  Check(Valid.ValidCalls = 3, 'cmCancel and cmValid do not ask the validator');
  Valid.Status := vsSyntax;
  Check(not Line.Valid(cmValid), 'a validator with a bad status makes the line not valid');
  Line.Free;

  Line := NewBare('abc', 20, 0);
  Check(Line.Valid(cmOK) and Line.Valid(cmCancel) and Line.Valid(cmValid), 'a line without a validator is valid');
  Line.Free;

  Root := NewRoot;
  Valid := TTestValidator.Create;
  Valid.ValidResult := False;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Other := TSel.Create(Rc(0, 3, 5, 4));
  Other.Options := Other.Options or ofSelectable;
  Root.Insert(Line);
  Root.Insert(Other);
  Root.SetCurrent(Other, normalSelect);
  Check(Root.Current = Other, 'the other view is the current one');
  Check(not Line.Valid(cmOK), 'the line is not valid');
  Check(Root.Current = Line, 'a line that is not valid selects itself');
  FreeRoot(Root);
end;

procedure TestValidatorOwnership;
var
  Line: TTestInput;
  First, Second, Third: TTestValidator;
  Root: TRoot;
begin
  ShutDownCount := 0;
  DestroyCount := 0;
  First := TTestValidator.Create;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 10, First);
  Line.SetValidator(nil);
  Check((ShutDownCount = 1) and (DestroyCount = 1), 'SetValidator destroys the validator that it replaces');
  Check(Line.GetValidator = nil, 'a line may have no validator');
  Second := TTestValidator.Create;
  Line.SetValidator(Second);
  Check((ShutDownCount = 1) and (DestroyCount = 1) and (Line.GetValidator = Second),
    'giving a validator to a line without one destroys nothing');
  Third := TTestValidator.Create;
  Line.SetValidator(Third);
  Check((ShutDownCount = 2) and (DestroyCount = 2) and (Line.GetValidator = Third), 'the second validator is destroyed');
  TvObject.DestroyObject(Line);
  Check((ShutDownCount = 3) and (DestroyCount = 3), 'destroying a line destroys its validator');

  First := TTestValidator.Create;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 10, First);
  Line.Free;
  Check((ShutDownCount = 4) and (DestroyCount = 4), 'freeing a line destroys its validator');

  Root := NewRoot;
  First := TTestValidator.Create;
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 10, First);
  Root.Insert(Line);
  FreeRoot(Root);
  Check((ShutDownCount = 5) and (DestroyCount = 5), 'destroying the owner destroys the validator of a line');
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 10);
  Line.Free;
  Check(DestroyCount = 5, 'a line without a validator destroys none');
end;

procedure TestStates;
var
  Line: TTestInput;
begin
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20);
  Line.Data := 'hello';
  Line.CurPos := 2;
  Line.SetState(sfSelected, True);
  Check((Line.CurPos = 5) and (Line.SelStart = 0) and (Line.SelEnd = 5), 'a line that is selected selects its text');
  Line.SetState(sfSelected, False);
  Check((Line.CurPos = 0) and (Line.SelStart = 0) and (Line.SelEnd = 0), 'a line that is deselected drops the selection');
  Line.Free;

  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20);
  Line.Data := 'hello';
  Line.CurPos := 2;
  Line.SetState(sfActive, True);
  Check((Line.CurPos = 2) and (Line.SelEnd = 0), 'a line that is active but not selected keeps its cursor');
  Line.SetState(sfFocused, True);
  Check((Line.CurPos = 2) and (Line.SelEnd = 0), 'a line that is focused keeps its cursor');
  Line.SetState(sfSelected, True);
  Place(Line, 0, 0, 1);
  Line.SetState(sfActive, False);
  Check((Line.CurPos = 0) and (Line.SelEnd = 0), 'a line that is selected and becomes inactive drops the selection');
  Place(Line, 0, 0, 1);
  Line.SetState(sfActive, True);
  Check((Line.CurPos = 5) and (Line.SelStart = 0) and (Line.SelEnd = 5),
    'a line that is selected and becomes active selects its text');
  Line.Free;
end;

procedure TestCommands;
var
  Line: TTestInput;
begin
  TView.DisableCommand(cmCut);
  TView.DisableCommand(cmCopy);
  TView.DisableCommand(cmPaste);
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20);
  Line.Data := 'hello';
  Check(not Line.CallCanUpdate, 'a line that is neither active nor selected does not update the commands');
  Line.SetState(sfSelected, True);
  Check(not Line.CallCanUpdate, 'a line that is only selected does not update the commands');
  Check(not TView.CommandEnabled(cmCut) and not TView.CommandEnabled(cmCopy) and not TView.CommandEnabled(cmPaste),
    'a line that is only selected leaves the commands disabled');
  Line.SetState(sfActive, True);
  Check(Line.CallCanUpdate, 'a line that is active and selected updates the commands');
  Check(TView.CommandEnabled(cmCut) and TView.CommandEnabled(cmCopy) and TView.CommandEnabled(cmPaste),
    'a line with a selection enables cut, copy and paste');
  Consumed(Line, KeyEv(kbHome));
  Check(not TView.CommandEnabled(cmCut) and not TView.CommandEnabled(cmCopy) and TView.CommandEnabled(cmPaste),
    'a line without a selection enables only paste');
  Consumed(Line, ShiftEv(kbRight));
  Check(TView.CommandEnabled(cmCut) and TView.CommandEnabled(cmCopy) and TView.CommandEnabled(cmPaste),
    'a selection enables cut and copy again');
  Line.SetState(sfActive, False);
  Check(not TView.CommandEnabled(cmCut) and not TView.CommandEnabled(cmCopy) and not TView.CommandEnabled(cmPaste),
    'a line that becomes inactive disables the three commands');
  Line.Free;
end;

procedure TestClipboard;
var
  Line: TTestInput;
  Note: TNoteBackend;
  Original: TClipboardBackend;
begin
  Original := TClipboard.Backend;
  Note := TNoteBackend.Create;
  TClipboard.Backend := Note;

  Line := NewBare('hello', 20, 3);
  Place(Line, 1, 3, 3);
  Check(Consumed(Line, CmdEv(cmCopy)), 'cmCopy is taken');
  Check((Note.SetCalls = 1) and (Note.LastSet = 'el'), 'cmCopy puts the selected text on the clipboard');
  Check((Line.Data = 'hello') and (Line.SelStart = 1) and (Line.SelEnd = 3), 'cmCopy leaves the line as it is');
  Place(Line, 0, 0, 3);
  Consumed(Line, CmdEv(cmCopy));
  Check((Note.SetCalls = 2) and (Note.LastSet = ''), 'cmCopy without a selection puts an empty text');
  Place(Line, 1, 3, 3);
  Check(Consumed(Line, CmdEv(cmCut)), 'cmCut is taken');
  Check((Note.SetCalls = 3) and (Note.LastSet = 'el'), 'cmCut puts the selected text on the clipboard');
  Check((Line.Data = 'hlo') and (Line.CurPos = 1) and (Line.SelStart = 0) and (Line.SelEnd = 0),
    'cmCut removes the selected text');
  Check(Consumed(Line, CmdEv(cmPaste)) and (Note.RequestCalls = 1), 'cmPaste asks the clipboard for its text');
  Check(not Consumed(Line, CmdEv(cmOK)) and (Note.SetCalls = 3) and (Note.RequestCalls = 1),
    'another command is left to others');
  Line.State := Line.State and not sfSelected;
  Place(Line, 0, 1, 1);
  Check(not Consumed(Line, CmdEv(cmCopy)) and (Note.SetCalls = 3), 'a line that is not selected takes no command');
  Check(not Consumed(Line, CmdEv(cmPaste)) and (Note.RequestCalls = 1), 'nor does it paste');
  Line.Free;

  TClipboard.Backend := Original;
  Note.Free;
end;

procedure TestClipboardWithValidator;
var
  Line: TTestInput;
  Valid: TTestValidator;
  Note: TNoteBackend;
  Original: TClipboardBackend;
begin
  Original := TClipboard.Backend;
  Note := TNoteBackend.Create;
  TClipboard.Backend := Note;

  Valid := TTestValidator.Create;
  Valid.RejectChar := 'x';
  Line := TTestInput.Create(Rc(0, 0, 10, 1), 20, Valid);
  Line.State := Line.State or sfSelected;
  Line.Data := 'axb';
  Place(Line, 2, 3, 3);
  Check(Consumed(Line, CmdEv(cmCut)), 'cmCut is taken');
  Check(Note.LastSet = 'b', 'the text is on the clipboard even when the cut is undone');
  Check((Line.Data = 'axb') and (Line.CurPos = 3) and (Line.SelStart = 0) and (Line.SelEnd = 0),
    'a cut that leaves a refused text is undone');
  Line.Data := 'abc';
  Place(Line, 1, 2, 2);
  Consumed(Line, CmdEv(cmCut));
  Check((Note.LastSet = 'b') and (Line.Data = 'ac') and (Line.CurPos = 1), 'a cut that the validator accepts is kept');
  Line.Free;

  TClipboard.Backend := Original;
  Note.Free;
end;

procedure TestMouse;
var
  Root: TRoot;
  Line: TTestInput;
  Ev: TEvent;

  { A line at the columns 2 to 11 of the row 1 that holds Text, selected, with no selection and no shift. }
  procedure Setup(const Text: string);
  begin
    Root := NewRoot;
    Line := TTestInput.Create(Rc(2, 1, 12, 2), 30);
    Root.Insert(Line);
    Line.Data := Text;
    Line.State := Line.State or sfSelected;
    Place(Line, 0, 0, 0);
    Line.FirstPos := 0;
  end;

begin
  Setup('hello world');
  Ev := MouseEv(evMouseDown, 2, 1);
  Check(Line.CallMouseDelta(Ev) = -1, 'the first column of the line scrolls left');
  Ev := MouseEv(evMouseDown, 1, 1);
  Check(Line.CallMouseDelta(Ev) = -1, 'a point left of the line scrolls left');
  Ev := MouseEv(evMouseDown, 3, 1);
  Check(Line.CallMouseDelta(Ev) = 0, 'the second column does not scroll');
  Ev := MouseEv(evMouseDown, 10, 1);
  Check(Line.CallMouseDelta(Ev) = 0, 'the last column but one does not scroll');
  Ev := MouseEv(evMouseDown, 11, 1);
  Check(Line.CallMouseDelta(Ev) = 1, 'the last column of the line scrolls right');
  Ev := MouseEv(evMouseDown, 30, 1);
  Check(Line.CallMouseDelta(Ev) = 1, 'a point right of the line scrolls right');

  Ev := MouseEv(evMouseDown, 2, 1);
  Check(Line.CallMousePos(Ev) = 0, 'the first column is the start of the text');
  Ev := MouseEv(evMouseDown, 3, 1);
  Check(Line.CallMousePos(Ev) = 0, 'the second column is the start of the text');
  Ev := MouseEv(evMouseDown, 5, 1);
  Check(Line.CallMousePos(Ev) = 2, 'the fourth column is after two characters');
  Ev := MouseEv(evMouseDown, 11, 1);
  Check(Line.CallMousePos(Ev) = 8, 'the last column is after eight characters');
  Line.FirstPos := 3;
  Ev := MouseEv(evMouseDown, 5, 1);
  Check(Line.CallMousePos(Ev) = 5, 'the position counts the columns that are scrolled out');
  Line.FirstPos := 0;
  Line.Data := 'hello';
  Ev := MouseEv(evMouseDown, 11, 1);
  Check(Line.CallMousePos(Ev) = 5, 'a point beyond the text is the end of the text');
  Line.Data := 'a' + WideCh + 'b';
  Ev := MouseEv(evMouseDown, 5, 1);
  Check(Line.CallMousePos(Ev) = 1, 'a point in the middle of a wide character is before it');
  Ev := MouseEv(evMouseDown, 6, 1);
  Check(Line.CallMousePos(Ev) = 4, 'a point after a wide character is after it');
  FreeRoot(Root);

  Setup('hello world');
  Root.AddEvent(MouseEv(evMouseMove, 10, 1));
  Root.AddEvent(MouseEv(evMouseUp, 10, 1));
  Ev := MouseEv(evMouseDown, 5, 1);
  Line.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a drag takes the mouse event');
  Check((Line.GetAnchor = 2) and (Line.CurPos = 7) and (Line.SelStart = 2) and (Line.SelEnd = 7),
    'a drag to the right selects from the anchor to the pointer');
  Check(Root.ScriptPos = 2, 'the drag read the events up to the release');
  FreeRoot(Root);

  Setup('hello world');
  Root.AddEvent(MouseEv(evMouseMove, 5, 1));
  Root.AddEvent(MouseEv(evMouseUp, 5, 1));
  Ev := MouseEv(evMouseDown, 10, 1);
  Line.HandleEvent(Ev);
  Check((Line.GetAnchor = 7) and (Line.CurPos = 2) and (Line.SelStart = 2) and (Line.SelEnd = 7),
    'a drag to the left selects from the pointer to the anchor');
  FreeRoot(Root);

  Setup('hello world');
  Root.AddEvent(MouseEv(evMouseUp, 5, 1));
  Ev := MouseEv(evMouseDown, 5, 1);
  Line.HandleEvent(Ev);
  Check((Line.CurPos = 2) and (Line.SelStart = 2) and (Line.SelEnd = 2), 'a click puts the cursor and selects nothing');
  FreeRoot(Root);

  Setup('hello world foo bar');
  Root.AddEvent(MouseEv(evMouseAuto, 11, 1));
  Root.AddEvent(MouseEv(evMouseUp, 11, 1));
  Ev := MouseEv(evMouseDown, 5, 1);
  Line.HandleEvent(Ev);
  Check(Line.FirstPos = 1, 'an automatic event at the end of the line scrolls the text');
  Check((Line.CurPos = 9) and (Line.SelStart = 2) and (Line.SelEnd = 9), 'the selection follows the scrolled text');
  FreeRoot(Root);

  Setup('hello world foo bar');
  Root.AddEvent(MouseEv(evMouseAuto, 11, 1));
  Root.AddEvent(MouseEv(evMouseAuto, 11, 1));
  Root.AddEvent(MouseEv(evMouseUp, 11, 1));
  Ev := MouseEv(evMouseDown, 11, 1);
  Line.HandleEvent(Ev);
  Check(Line.FirstPos = 3, 'a click on the right end scrolls once and once for each automatic event');
  Check((Ev.What = evNothing) and (Root.ScriptPos = 3), 'the click took the events up to the release');
  Check((Line.SelStart = 0) and (Line.SelEnd = 0), 'scrolling selects nothing');
  FreeRoot(Root);

  Setup('hello world foo bar');
  Line.FirstPos := 3;
  Root.AddEvent(MouseEv(evMouseUp, 2, 1));
  Ev := MouseEv(evMouseDown, 2, 1);
  Line.HandleEvent(Ev);
  Check(Line.FirstPos = 2, 'a click on the left end scrolls back');
  FreeRoot(Root);

  Setup('hello');
  Root.AddEvent(MouseEv(evMouseUp, 11, 1));
  Ev := MouseEv(evMouseDown, 11, 1);
  Line.HandleEvent(Ev);
  Check((Line.FirstPos = 0) and (Line.GetAnchor = 5) and (Line.CurPos = 5),
    'a click on the right end of a text that fits puts the cursor at its end');
  FreeRoot(Root);

  Setup('hello world');
  Ev := MouseEv(evMouseDown, 5, 1);
  Ev.Mouse.EventFlags := meDoubleClick;
  Line.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a double click is taken');
  Check((Line.SelStart = 0) and (Line.SelEnd = 11) and (Line.CurPos = 11), 'a double click selects the whole text');
  Check((Line.FirstPos = 3) and (Root.ScriptPos = 0), 'the double click scrolls to the cursor and reads no event');
  FreeRoot(Root);
end;

var
  K: Integer;
  PaletteText: string;
  SavedBackend: TScreenBackend;

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

  TestNames;
  TestConstruction;
  TestMeasures;
  TestStateBlock;
  TestDraw;
  TestTyping;
  TestLimits;
  TestSelectionKeys;
  TestSelectAndData;
  TestValidation;
  TestValidatorOwnership;
  TestStates;
  TestCommands;
  TestClipboard;
  TestClipboardWithValidator;
  TestMouse;

  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
