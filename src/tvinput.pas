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

uses
  TvObjs, TvKeys, TvDrawBuf, TvUtf8, TvClip, TvDialog, TvMenus;

const
  { The code of the key that clears the line. }
  CONTROL_Y = 25;

  { The palette of a line: the entries of the palette of its owner that its four entries stand for. }
  cpInputLine = #$13#$13#$14#$15;

  { The scan codes of Home, Left, Right, End, Ctrl-Left and Ctrl-Right: the keys that extend the selection when
    shift is held. }
  PadKeys = [$73, $74, $47, $4F, $4B, $4D];

var
  InputLinePalette: TPalette = nil;

function Larger(First, Second: Integer): Integer;
begin
  Result := First;
  if Second > First then
    Result := Second;
end;

function Smaller(First, Second: Integer): Integer;
begin
  Result := First;
  if Second < First then
    Result := Second;
end;

{ The part of Source before its first zero character. }
function TextBeforeNul(const Source: string): string;
var
  nulPosition: Integer;
begin
  nulPosition := Pos(#0, Source);
  if nulPosition = 0 then
    Result := Source
  else
    Result := Copy(Source, 1, nulPosition - 1);
end;

{ The low attribute of the entry Entry of the palette of Viewer. }
function LowAttrOf(Viewer: TView; Entry: Word): TColorAttr;
var
  pair: TAttrPair;
begin
  pair := Viewer.GetColor(Entry);
  Result := pair.Attrs[0];
end;

{ The start of the word before the position Position of Text, or 0 when there is none. }
function PrevWord(const Text: string; Position: Integer): Integer;
var
  scan: Integer;
  startsWord: Boolean;
begin
  for scan := Position - 1 downto 1 do
  begin
    startsWord := (Text[scan + 1] <> ' ') and (Text[scan] = ' ');
    if startsWord then
      Exit(scan);
  end;
  Result := 0;
end;

{ The start of the word after the position Position of Text, or the length of Text when there is none. }
function NextWord(const Text: string; Position: Integer): Integer;
var
  scan: Integer;
  endsWord: Boolean;
begin
  for scan := Position to Length(Text) - 2 do
  begin
    endsWord := (Text[scan + 1] = ' ') and (Text[scan + 2] <> ' ');
    if endsWord then
      Exit(scan + 1);
  end;
  Result := Length(Text);
end;

{ The length in bytes of the character of Text that starts at the zero based position Position. }
function CharLengthAt(const Text: string; Position: Integer): Integer;
begin
  Result := Integer(TText.Next(Copy(Text, Position + 1, Length(Text))));
end;

function HotKeyStr(const Text: string): string;
var
  firstTilde, keyStart, closingOffset: Integer;
  rest: string;
begin
  Result := '';
  firstTilde := Pos('~', Text);
  if firstTilde = 0 then
    Exit;
  keyStart := firstTilde + 1;
  rest := Copy(Text, keyStart, Length(Text));
  closingOffset := Pos('~', rest);
  if closingOffset = 0 then
    Result := rest
  else
    Result := Copy(rest, 1, closingOffset - 1);
end;

function HotKey(const Text: string): Char;
var
  marked: string;
begin
  marked := HotKeyStr(Text);
  if marked = '' then
    Exit(#0);
  Result := UpCase(marked[1]);
end;

{ TInputLine }

constructor TInputLine.Create(const Bounds: TRect; Limit: Integer; ValidatorToUse: TValidator;
  LimitMode: Word);
begin
  inherited Create(Bounds);
  if LimitMode = ilMaxBytes then
    MaxLen := Smaller(Larger(Limit - 1, 0), High(LongInt) - 1)
  else
    MaxLen := 255;
  if LimitMode = ilMaxWidth then
    MaxWidth := Limit
  else
    MaxWidth := High(LongInt);
  if LimitMode = ilMaxChars then
    MaxChars := Limit
  else
    MaxChars := High(LongInt);
  CurPos := 0;
  FirstPos := 0;
  SelStart := 0;
  SelEnd := 0;
  Validator := ValidatorToUse;
  Data := '';
  OldData := '';
  State := State or sfCursorVis;
  Options := Options or (ofSelectable or ofFirstClick);
end;

destructor TInputLine.Destroy;
begin
  TvObject.DestroyObject(Validator);
  Validator := nil;
  inherited Destroy;
end;

function TInputLine.CanScroll(Delta: Integer): Boolean;
begin
  if Delta < 0 then
    Result := FirstPos > 0
  else if Delta > 0 then
    Result := (Integer(TText.Width(Data)) - FirstPos + 2) > Size.X
  else
    Result := False;
end;

function TInputLine.DataSize: Word;
var
  transferSize: Word;
begin
  transferSize := 0;
  if Validator <> nil then
    transferSize := Validator.Transfer(Data, nil, vtDataSize);
  if transferSize = 0 then
    transferSize := Word(MaxLen + 1);
  Result := transferSize;
end;

procedure TInputLine.Draw;
var
  lineBuffer: TDrawBuffer;
  textAttr, selectionAttr: TColorAttr;
  selectionLeft, selectionRight, selectionCount, lineHeight: Integer;
begin
  if (State and sfFocused) <> 0 then
    textAttr := LowAttrOf(Self, 2)
  else
    textAttr := LowAttrOf(Self, 1);
  lineBuffer := TDrawBuffer.Create;
  try
    lineBuffer.MoveChar(0, ' ', textAttr, Size.X);
    if Size.X > 1 then
      lineBuffer.MoveStr(1, Data, textAttr, Size.X - 1, FirstPos);
    if CanScroll(1) then
      lineBuffer.MoveChar(Size.X - 1, RightArrow, LowAttrOf(Self, 4), 1);
    if CanScroll(-1) then
      lineBuffer.MoveChar(0, LeftArrow, LowAttrOf(Self, 4), 1);
    if (State and sfSelected) <> 0 then
    begin
      selectionLeft := DisplayedPos(SelStart) - FirstPos;
      selectionRight := DisplayedPos(SelEnd) - FirstPos;
      selectionLeft := Larger(0, selectionLeft);
      selectionRight := Smaller(Size.X - 2, selectionRight);
      selectionCount := selectionRight - selectionLeft;
      if selectionCount > 0 then
      begin
        selectionAttr := LowAttrOf(Self, 3);
        lineBuffer.MoveChar(selectionLeft + 1, #0, selectionAttr, selectionCount);
      end;
    end;
    lineHeight := Size.Y;
    WriteLine(0, 0, Size.X, lineHeight, lineBuffer);
  finally
    lineBuffer.Free;
  end;
  SetCursor(DisplayedPos(CurPos) - FirstPos + 1, 0);
end;

procedure TInputLine.GetData(Rec: Pointer);
var
  recBytes: PByte;
  byteCount, index: Integer;
begin
  if Validator <> nil then
    if Validator.Transfer(Data, Rec, vtGetData) <> 0 then
      Exit;
  byteCount := DataSize;
  recBytes := PByte(Rec);
  for index := 0 to byteCount - 1 do
    if index < Length(Data) then
      recBytes[index] := Byte(Data[index + 1])
    else
      recBytes[index] := 0;
end;

function TInputLine.GetPalette: TPalette;
begin
  Result := InputLinePalette;
end;

function TInputLine.MouseDelta(var Event: TEvent): Integer;
var
  mouse: TPoint;
begin
  mouse := MakeLocal(Event.Mouse.Where);
  if mouse.X <= 0 then
    Result := -1
  else if mouse.X >= Size.X - 1 then
    Result := 1
  else
    Result := 0;
end;

function TInputLine.MousePos(var Event: TEvent): Integer;
var
  mouse: TPoint;
  column: Integer;
begin
  mouse := MakeLocal(Event.Mouse.Where);
  mouse.X := Larger(mouse.X, 1);
  column := mouse.X + FirstPos - 1;
  column := Larger(column, 0);
  Result := Integer(TText.Scroll(Data, column, False));
end;

function TInputLine.DisplayedPos(Position: Integer): Integer;
begin
  Result := Integer(TText.Width(Copy(Data, 1, Position)));
end;

procedure TInputLine.DeleteSelect;
var
  selectedCount, keepFrom: Integer;
begin
  selectedCount := SelEnd - SelStart;
  if selectedCount <= 0 then
    Exit;
  keepFrom := SelStart;
  System.Delete(Data, keepFrom + 1, selectedCount);
  CurPos := keepFrom;
end;

procedure TInputLine.DeleteCurrent;
begin
  if CurPos >= Length(Data) then
    Exit;
  SelStart := CurPos;
  SelEnd := CurPos + CharLengthAt(Data, CurPos);
  DeleteSelect;
end;

procedure TInputLine.AdjustSelectBlock;
begin
  SelStart := Smaller(CurPos, Anchor);
  SelEnd := Larger(CurPos, Anchor);
end;

procedure TInputLine.SaveState;
begin
  if Validator = nil then
    Exit;
  OldSelEnd := SelEnd;
  OldSelStart := SelStart;
  OldFirstPos := FirstPos;
  OldCurPos := CurPos;
  OldData := Data;
end;

procedure TInputLine.RestoreState;
begin
  if Validator = nil then
    Exit;
  SelEnd := OldSelEnd;
  SelStart := OldSelStart;
  FirstPos := OldFirstPos;
  CurPos := OldCurPos;
  Data := OldData;
end;

function TInputLine.CheckValid(NoAutoFill: Boolean): Boolean;
var
  candidate: string;
  oldLength, newLength: Integer;
  cursorAtEnd: Boolean;
begin
  Result := True;
  if Validator = nil then
    Exit;
  candidate := Data;
  oldLength := Length(Data);
  if not Validator.IsValidInput(candidate, NoAutoFill) then
  begin
    RestoreState;
    Result := False;
    Exit;
  end;
  candidate := TextBeforeNul(candidate);
  newLength := Length(candidate);
  if newLength > MaxLen then
  begin
    SetLength(candidate, MaxLen);
    newLength := MaxLen;
  end;
  Data := candidate;
  cursorAtEnd := CurPos >= oldLength;
  if cursorAtEnd and (newLength > oldLength) then
    CurPos := newLength;
end;

{ Puts the text of a key event into the line at the cursor. Returns False when the event holds no text and is
  not the key that clears the line, so that the event is left to others. }
function TInputLine.EnterKeyText(var Event: TEvent): Boolean;
var
  keyText: string;
  keyLength: Integer;
  dataMetrics, keyMetrics: TTextMetrics;
  bytesFit, widthFits, charsFit: Boolean;
begin
  Result := True;
  keyText := Copy(TextBeforeNul(Event.KeyDown.GetText), 1, maxCharSize);
  keyLength := Length(keyText);
  if keyLength > 0 then
  begin
    DeleteSelect;
    if (State and sfCursorIns) <> 0 then
      DeleteCurrent;
    if not CheckValid(True) then
      Exit;
    if keyText[1] in [#9, #10, #13] then
      keyText[1] := ' ';
    dataMetrics := TText.Measure(Data);
    keyMetrics := TText.Measure(keyText);
    bytesFit := Int64(Length(Data)) + keyLength <= Int64(Cardinal(MaxLen));
    widthFits := Int64(dataMetrics.Width) + keyMetrics.Width <= Int64(Cardinal(MaxWidth));
    charsFit := Int64(dataMetrics.GraphemeCount) + keyMetrics.GraphemeCount <= Int64(Cardinal(MaxChars));
    if bytesFit and widthFits and charsFit then
    begin
      if FirstPos > CurPos then
        FirstPos := CurPos;
      System.Insert(keyText, Data, CurPos + 1);
      Inc(CurPos, keyLength);
    end;
    CheckValid(False);
    Exit;
  end;
  if Event.KeyDown.CharScan.CharCode = CONTROL_Y then
  begin
    Data := '';
    CurPos := 0;
    Exit;
  end;
  Result := False;
end;

{ Deletes the selection, or when there is none the text from SpanStart to SpanEnd, and checks the result. }
procedure TInputLine.EraseSpan(SpanStart, SpanEnd: Integer);
begin
  if SelStart = SelEnd then
  begin
    SelEnd := SpanEnd;
    SelStart := SpanStart;
  end;
  DeleteSelect;
  CheckValid(True);
end;

{ Handles a key press of a line that is selected. Returns False when the key is not for the line. }
function TInputLine.HandleKeyDown(var Event: TEvent): Boolean;
var
  extendBlock, isSelectionKey, shiftHeld: Boolean;
  cursorColumn, scrollLimit, textLength, wordTarget: Integer;
begin
  Result := True;
  SaveState;
  Event.KeyDown.KeyCode := CtrlToArrow(Event.KeyDown.KeyCode);
  isSelectionKey := Event.KeyDown.CharScan.ScanCode in PadKeys;
  shiftHeld := (Event.KeyDown.ControlKeyState and kbShift) <> 0;
  extendBlock := isSelectionKey and shiftHeld;
  if extendBlock then
  begin
    Event.KeyDown.CharScan.CharCode := 0;
    if CurPos = SelEnd then
      Anchor := SelStart
    else if SelStart = SelEnd then
      Anchor := CurPos
    else
      Anchor := SelEnd;
  end;

  case Event.KeyDown.KeyCode of
    kbLeft:
      Dec(CurPos, Integer(TText.Prev(Data, CurPos)));
    kbRight:
      Inc(CurPos, CharLengthAt(Data, CurPos));
    kbEnd:
      begin
        textLength := Length(Data);
        CurPos := textLength;
      end;
    kbHome:
      CurPos := 0;
    kbCtrlRight:
      begin
        wordTarget := NextWord(Data, CurPos);
        CurPos := wordTarget;
      end;
    kbCtrlLeft:
      begin
        wordTarget := PrevWord(Data, CurPos);
        CurPos := wordTarget;
      end;
    kbBack:
      EraseSpan(CurPos - Integer(TText.Prev(Data, CurPos)), CurPos);
    kbCtrlBack, kbAltBack:
      EraseSpan(PrevWord(Data, CurPos), CurPos);
    kbDel:
      begin
        if SelStart <> SelEnd then
          DeleteSelect
        else
          DeleteCurrent;
        CheckValid(True);
      end;
    kbCtrlDel:
      EraseSpan(CurPos, NextWord(Data, CurPos));
    kbIns:
      SetState(sfCursorIns, (State and sfCursorIns) = 0);
  else
    if not EnterKeyText(Event) then
      Exit(False);
  end;

  if extendBlock then
    AdjustSelectBlock
  else
  begin
    SelStart := 0;
    SelEnd := 0;
  end;
  cursorColumn := DisplayedPos(CurPos);
  if FirstPos > cursorColumn then
    FirstPos := cursorColumn;
  scrollLimit := cursorColumn - Size.X + 2;
  if FirstPos < scrollLimit then
    FirstPos := scrollLimit;
  DrawView;
  ClearEvent(Event);
end;

{ Handles a press of the mouse button over a line that is selected: a click on an end scrolls, a double click
  selects everything, and a drag selects a block. }
procedure TInputLine.HandleMouseDown(var Event: TEvent);
var
  firstStep: Integer;
  doubleClicked: Boolean;
begin
  firstStep := MouseDelta(Event);
  doubleClicked := (Event.Mouse.EventFlags and meDoubleClick) <> 0;
  if CanScroll(firstStep) then
    ScrollWhileHeld(Event, firstStep)
  else if doubleClicked then
    SelectAll(True)
  else
    DragSelection(Event);
  ClearEvent(Event);
end;

{ Scrolls by Step for the press and for each automatic event that follows, while the button is held. }
procedure TInputLine.ScrollWhileHeld(var Event: TEvent; Step: Integer);
var
  buttonHeld: Boolean;
begin
  buttonHeld := True;
  while buttonHeld do
  begin
    if CanScroll(Step) then
    begin
      FirstPos := FirstPos + Step;
      DrawView;
    end;
    buttonHeld := MouseEvent(Event, evMouseAuto);
  end;
end;

{ Selects from the point of the press to the pointer while the button is held, scrolling at the ends. }
procedure TInputLine.DragSelection(var Event: TEvent);
var
  step: Integer;
  buttonHeld: Boolean;
begin
  Anchor := MousePos(Event);
  buttonHeld := True;
  while buttonHeld do
  begin
    if Event.What = evMouseAuto then
    begin
      step := MouseDelta(Event);
      if CanScroll(step) then
        FirstPos := FirstPos + step;
    end;
    CurPos := MousePos(Event);
    AdjustSelectBlock;
    DrawView;
    buttonHeld := MouseEvent(Event, evMouseMove or evMouseAuto);
  end;
end;

{ Handles the commands that move text between the line and the clipboard. }
procedure TInputLine.HandleCommand(var Event: TEvent);
var
  command: Word;
  selectedText: string;
begin
  command := Event.Message.Command;
  if command = cmPaste then
  begin
    TClipboard.RequestText;
    ClearEvent(Event);
    Exit;
  end;
  if (command <> cmCut) and (command <> cmCopy) then
    Exit;
  selectedText := Copy(Data, SelStart + 1, SelEnd - SelStart);
  TClipboard.SetText(selectedText);
  if command = cmCut then
  begin
    SaveState;
    DeleteSelect;
    CheckValid(True);
    SelStart := 0;
    SelEnd := 0;
    DrawView;
  end;
  ClearEvent(Event);
end;

procedure TInputLine.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (State and sfSelected) = 0 then
    Exit;
  case Event.What of
    evMouseDown:
      HandleMouseDown(Event);
    evKeyDown:
      if not HandleKeyDown(Event) then
        Exit;
    evCommand:
      HandleCommand(Event);
  end;
  if CanUpdateCommands then
    UpdateCommands;
end;

procedure TInputLine.SelectAll(Enable: Boolean; Scroll: Boolean);
var
  endOfSelection, cursorColumn: Integer;
begin
  endOfSelection := 0;
  if Enable then
    endOfSelection := Length(Data);
  SelStart := 0;
  SelEnd := endOfSelection;
  CurPos := endOfSelection;
  if Scroll then
  begin
    cursorColumn := DisplayedPos(CurPos);
    FirstPos := Larger(0, cursorColumn - Size.X + 2);
  end;
  DrawView;
  if CanUpdateCommands then
    UpdateCommands;
end;

procedure TInputLine.SetData(Rec: Pointer);
var
  validatorTookIt: Boolean;
  recBytes: PByte;
  copyLimit, copied, terminatorIndex: Integer;
  received: string;
begin
  validatorTookIt := False;
  if Validator <> nil then
    validatorTookIt := Validator.Transfer(Data, Rec, vtSetData) <> 0;
  if not validatorTookIt then
  begin
    copyLimit := Larger(DataSize - 1, 0);
    recBytes := PByte(Rec);
    SetLength(received, copyLimit);
    copied := 0;
    while (copied < copyLimit) and (recBytes[copied] <> 0) do
    begin
      received[copied + 1] := Chr(recBytes[copied]);
      Inc(copied);
    end;
    SetLength(received, copied);
    terminatorIndex := DataSize - 1;
    if Length(received) > terminatorIndex then
      SetLength(received, Larger(terminatorIndex, 0));
    if Length(received) > MaxLen then
      SetLength(received, MaxLen);
    Data := received;
  end;
  SelectAll(True);
end;

procedure TInputLine.SetState(StateMask: Word; TurnOn: Boolean);
var
  updateBefore, updateAfter, selectsText: Boolean;
begin
  updateBefore := CanUpdateCommands;
  inherited SetState(StateMask, TurnOn);
  updateAfter := CanUpdateCommands;
  selectsText := (StateMask = sfSelected) or ((StateMask = sfActive) and ((State and sfSelected) <> 0));
  if selectsText then
    SelectAll(TurnOn, False);
  if updateBefore <> updateAfter then
    UpdateCommands;
end;

procedure TInputLine.SetValidator(NewValidator: TValidator);
begin
  if Validator <> nil then
    TvObject.DestroyObject(Validator);
  Validator := NewValidator;
end;

function TInputLine.CanUpdateCommands: Boolean;
const
  ActiveAndSelected = sfActive or sfSelected;
begin
  Result := (State and ActiveAndSelected) = ActiveAndSelected;
end;

procedure TInputLine.SetCmdState(Command: Word; Enable: Boolean);
var
  commandSet: TCommandSet;
begin
  commandSet := TCommandSet.Create;
  commandSet.AddAssign(Command);
  if Enable and CanUpdateCommands then
    EnableCommands(commandSet)
  else
    DisableCommands(commandSet);
end;

procedure TInputLine.UpdateCommands;
var
  hasSelection: Boolean;
begin
  hasSelection := SelEnd > SelStart;
  SetCmdState(cmCut, hasSelection);
  SetCmdState(cmCopy, SelEnd > SelStart);
  SetCmdState(cmPaste, True);
end;

function TInputLine.Valid(Command: Word): Boolean;
begin
  Result := True;
  if Validator = nil then
    Exit;
  if Command = cmValid then
    Exit(Validator.Status = vsOk);
  if Command = cmCancel then
    Exit;
  if not Validator.Validate(Data) then
  begin
    Select;
    Result := False;
  end;
end;

initialization
  TInputLine.RightArrow := #$10;
  TInputLine.LeftArrow := #$11;
  InputLinePalette := TPalette.Create(cpInputLine, Length(cpInputLine));
  TvDialog.HotKeyHook := @HotKey;
  TvMenus.HotKeyStrHook := @HotKeyStr;

finalization
  InputLinePalette.Free;

end.
