{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: source/tvterm-core/vtermemu.cc (the conversion of input events),
  include/tvterm/vtermemu.h
  See COPYRIGHT.tvterm. }
unit TvVtKeys;

{$mode objfpc}

interface

uses
  TvKeys, TvEvents, TvUtf8;

const
  { The number of arrow key presses that one step of the mouse wheel gives. }
  mouseWheelScrollLines = 3;

type
  { The keys that a client program can tell apart. The value of a key is the high byte (the scan code) of its
    Turbo Vision key code. }
  TVtKey = (
    vkNone = 0, vkEscape = $01, vkBackspace = $0E, vkTab = $0F, vkEnter = $1C,
    vkF1 = $3B, vkF2, vkF3, vkF4 = $3E, vkF5, vkF6, vkF7 = $41, vkF8, vkF9, vkF10 = $44,
    vkHome = $47, vkUp, vkPageUp, vkLeft = $4B, vkRight = $4D, vkEnd = $4F,
    vkDown, vkPageDown, vkIns, vkDel,
    vkF11 = $85, vkF12
  );

  TVtModifier = (vmShift, vmAlt, vmCtrl);
  TVtModifiers = set of TVtModifier;

  { The mouse protocols (DECSET 9, 1000, 1002 and 1003). }
  TVtMouseTracking = (vtTrackOff, vtTrackX10, vtTrackNormal, vtTrackButton, vtTrackAny);

  { The encodings of the position (none, 1005 and 1006). }
  TVtMouseEncoding = (vtEncDefault, vtEncUtf8, vtEncSgr);

  { The modes that the client program has set and that change the bytes of the input. }
  TVtInputModes = record
    CursorKeysApplication: Boolean;
    KeypadApplication: Boolean;
    MouseTracking: TVtMouseTracking;
    MouseEncoding: TVtMouseEncoding;
    BracketedPaste: Boolean;
    FocusReporting: Boolean;
  end;

  { What the report of the mouse remembers between two events: the last cell and the buttons held. }
  TVtMouseState = record
    Col, Row: Integer;
    Buttons: Byte;
  end;

{ All modes off. }
function DefaultInputModes: TVtInputModes;

{ No position seen, no button held. }
function NewMouseState: TVtMouseState;

function ConvKey(KeyCode: Word): TVtKey;
function ConvMod(ControlKeyState: Word): TVtModifiers;

{ Button is 1 for the left, 2 for the middle and 3 for the right button, 4 for a wheel step up, 5 for a
  wheel step down and 0 for none. }
procedure ConvMouse(const Mouse: TMouseEventType; var Mods: TVtModifiers; var Button: Integer);

{ The bytes of a key and of a character with the modifiers. }
function KeyBytes(Key: TVtKey; Mods: TVtModifiers; const Modes: TVtInputModes): AnsiString;
function UnicharBytes(CodePoint: Cardinal; Mods: TVtModifiers): AnsiString;

function ProcessKey(const KeyDown: TKeyDownEvent; const Modes: TVtInputModes): AnsiString;
function ProcessMouse(What: Word; const Mouse: TMouseEventType; const Modes: TVtInputModes;
  var State: TVtMouseState): AnsiString;
function WheelToArrow(Wheel: Byte; const Modes: TVtInputModes): AnsiString;

{ The text that a paste sends, a character of the numeric keypad, and the report of the focus. }
function ProcessPaste(const Text: AnsiString; const Modes: TVtInputModes): AnsiString;
function ProcessKeypad(Ch: AnsiChar; const Modes: TVtInputModes): AnsiString;
function ProcessFocus(GotFocus: Boolean; const Modes: TVtInputModes): AnsiString;

implementation

uses
  SysUtils;

const
  EscText = #27;

{ Defaults }

function DefaultInputModes: TVtInputModes;
begin
  Result.CursorKeysApplication := False;
  Result.KeypadApplication := False;
  Result.MouseTracking := vtTrackOff;
  Result.MouseEncoding := vtEncDefault;
  Result.BracketedPaste := False;
  Result.FocusReporting := False;
end;

function NewMouseState: TVtMouseState;
begin
  Result.Col := -1;
  Result.Row := -1;
  Result.Buttons := 0;
end;

{ Conversion of the codes of Turbo Vision }

{ The keys of the table are the key codes whose value is the scan code of the key: Enter, Tab, Back and Esc
  have a character in the low byte, and the cursor, editing and function keys have a zero low byte. }
function ConvKey(KeyCode: Word): TVtKey;
var
  Scan: Byte;
begin
  Result := vkNone;
  Scan := KeyCode shr 8;
  if (KeyCode and $FF) = 0 then
  begin
    if Scan in [$3B..$44, $47..$49, $4B, $4D, $4F..$53, $85, $86] then
      Result := TVtKey(Scan);
  end
  else if (KeyCode = kbEnter) or (KeyCode = kbTab) or (KeyCode = kbBack) or (KeyCode = kbEsc) then
    Result := TVtKey(Scan);
end;

function ConvMod(ControlKeyState: Word): TVtModifiers;
begin
  Result := [];
  if (ControlKeyState and kbShift) <> 0 then
    Include(Result, vmShift);
  if (ControlKeyState and kbLeftAlt) <> 0 then
    Include(Result, vmAlt);
  if (ControlKeyState and kbCtrlShift) <> 0 then
    Include(Result, vmCtrl);
end;

procedure ConvMouse(const Mouse: TMouseEventType; var Mods: TVtModifiers; var Button: Integer);
begin
  Mods := ConvMod(Mouse.ControlKeyState);
  if (Mouse.Buttons and mbLeftButton) <> 0 then
    Button := 1
  else if (Mouse.Buttons and mbMiddleButton) <> 0 then
    Button := 2
  else if (Mouse.Buttons and mbRightButton) <> 0 then
    Button := 3
  else if (Mouse.Wheel and mwUp) <> 0 then
    Button := 4
  else if (Mouse.Wheel and mwDown) <> 0 then
    Button := 5
  else
    Button := 0;
end;

{ The bytes of the keys }

{ The second parameter of a key with modifiers: 1 plus Shift 1, Alt 2 and Control 4. }
function ModifierParam(Mods: TVtModifiers): Integer;
var
  Each: TVtModifier;
begin
  Result := 1;
  for Each in Mods do
    Result := Result + (1 shl Ord(Each));
end;

{ The final character of the cursor keys, #0 for any other key. }
function CursorFinal(Key: TVtKey): AnsiChar;
const
  CursorOrder: array[0..5] of TVtKey = (vkUp, vkDown, vkRight, vkLeft, vkHome, vkEnd);
  CursorLetters = 'ABCDHF';
var
  I: Integer;
begin
  Result := #0;
  for I := 0 to High(CursorOrder) do
    if CursorOrder[I] = Key then
      Result := CursorLetters[I + 1];
end;

{ The number n of F1 to F12 as a key, 0 for any other key. }
function FunctionIndex(Key: TVtKey): Integer;
begin
  if (Key >= vkF1) and (Key <= vkF10) then
    Result := Ord(Key) - Ord(vkF1) + 1
  else if (Key = vkF11) or (Key = vkF12) then
    Result := Ord(Key) - Ord(vkF11) + 11
  else
    Result := 0;
end;

{ The final character of F1 to F4, #0 for any other key. }
function PfFinal(Key: TVtKey): AnsiChar;
var
  N: Integer;
begin
  N := FunctionIndex(Key);
  if (N >= 1) and (N <= 4) then
    Result := AnsiChar(Ord('P') + N - 1)
  else
    Result := #0;
end;

{ The number before the tilde of the editing keys and of F5 to F12, 0 for any other key. }
function TildeNumber(Key: TVtKey): Integer;
const
  { The numbers of F1 to F12 }
  FunctionNumbers = #11#12#13#14#15#17#18#19#20#21#23#24;
var
  N: Integer;
begin
  N := FunctionIndex(Key);
  Result := 0;
  if N >= 5 then
    Result := Ord(FunctionNumbers[N])
  else if (Key = vkIns) or (Key = vkDel) then
    Result := Ord(Key) - Ord(vkIns) + 2
  else if Key = vkPageUp then
    Result := 5
  else if Key = vkPageDown then
    Result := 6;
end;

{ A key that ends in a letter: SS3 or CSI before the letter when no modifier is held, CSI 1 ; m before it
  otherwise. }
function LetterSequence(Final: AnsiChar; Mods: TVtModifiers; UseSs3: Boolean): AnsiString;
begin
  if Mods <> [] then
    Result := EscText + '[1;' + IntToStr(ModifierParam(Mods)) + Final
  else if UseSs3 then
    Result := EscText + 'O' + Final
  else
    Result := EscText + '[' + Final;
end;

function TildeSequence(Number: Integer; Mods: TVtModifiers): AnsiString;
begin
  Result := EscText + '[' + IntToStr(Number);
  if Mods <> [] then
    Result := Result + ';' + IntToStr(ModifierParam(Mods));
  Result := Result + '~';
end;

{ The keys that send one control character; Alt puts an ESC before it. }
function ControlCharKey(Key: TVtKey; Mods: TVtModifiers): AnsiString;
var
  Base: AnsiString;
begin
  Result := '';
  case Key of
    vkEnter:
      Base := #13;
    vkTab:
      if vmShift in Mods then
        Base := EscText + '[Z'
      else
        Base := #9;
    vkBackspace:
      if vmCtrl in Mods then
        Base := #8
      else
        Base := #127;
    vkEscape:
      Base := EscText;
  else
    Exit;
  end;
  if vmAlt in Mods then
    Result := EscText + Base
  else
    Result := Base;
end;

function KeyBytes(Key: TVtKey; Mods: TVtModifiers; const Modes: TVtInputModes): AnsiString;
var
  Letter: AnsiChar;
  Number: Integer;
begin
  Letter := CursorFinal(Key);
  if Letter <> #0 then
  begin
    Result := LetterSequence(Letter, Mods, Modes.CursorKeysApplication);
    Exit;
  end;
  Letter := PfFinal(Key);
  if Letter <> #0 then
  begin
    Result := LetterSequence(Letter, Mods, True);
    Exit;
  end;
  Number := TildeNumber(Key);
  if Number <> 0 then
    Result := TildeSequence(Number, Mods)
  else
    Result := ControlCharKey(Key, Mods);
end;

{ The control character that Ctrl gives to a character, False when it gives none. }
function ControlOf(CodePoint: Cardinal; var Code: Byte): Boolean;
begin
  Result := True;
  if CodePoint = Ord(' ') then
    Code := 0
  else if (CodePoint >= Ord('@')) and (CodePoint <= Ord('_')) then
    Code := Byte(CodePoint and $1F)
  else if (CodePoint >= Ord('a')) and (CodePoint <= Ord('z')) then
    Code := Byte(CodePoint and $1F)
  else
    Result := False;
end;

function Utf8Text(CodePoint: Cardinal): AnsiString;
var
  Bytes: TUtf8Bytes;
  Count, I: SizeInt;
begin
  Count := Utf32To8(CodePoint, Bytes);
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
    Result[I + 1] := AnsiChar(Bytes[I]);
end;

function UnicharBytes(CodePoint: Cardinal; Mods: TVtModifiers): AnsiString;
var
  Code: Byte;
begin
  if (vmCtrl in Mods) and ControlOf(CodePoint, Code) then
    Result := AnsiChar(Code)
  else
    Result := Utf8Text(CodePoint);
  if vmAlt in Mods then
    Result := EscText + Result;
end;

function ProcessKey(const KeyDown: TKeyDownEvent; const Modes: TVtInputModes): AnsiString;
var
  Ev: TKeyDownEvent;
  TvKey: TKey;
  VtMods: TVtModifiers;
  Key: TVtKey;
  Letter: Boolean;
begin
  Ev := KeyDown;
  TvKey := Ev.ToKey;
  VtMods := ConvMod(TvKey.Mods);
  Letter := (TvKey.Code >= Ord('A')) and (TvKey.Code <= Ord('Z'));
  if (TvKey.Mods = kbCtrlShift) and Letter then
  begin
    { A control character goes through as it is. }
    Ev.Text[0] := Ev.CharScan.CharCode;
    Ev.TextLength := 1;
    VtMods := [];
  end
  else if (Ev.TextLength = 0) and (TvKey.Code >= Ord(' ')) and (TvKey.Code < $7F) then
  begin
    { The other combinations of a letter and a modifier go as text. }
    Ev.Text[0] := Byte(TvKey.Code);
    Ev.TextLength := 1;
    if Letter and ((Ev.ControlKeyState and (kbShift or kbCtrlShift or kbAltShift)) = kbLeftAlt) then
      Ev.Text[0] := Ev.Text[0] + (Ord('a') - Ord('A'));
  end;

  Result := '';
  if Ev.TextLength <> 0 then
    Result := UnicharBytes(Utf8To32(Ev.GetText), VtMods)
  else
  begin
    Key := ConvKey(TvKey.Code);
    if Key <> vkNone then
      Result := KeyBytes(Key, VtMods, Modes);
  end;
end;

function WheelToArrow(Wheel: Byte; const Modes: TVtInputModes): AnsiString;
var
  Key: TVtKey;
  Step: Integer;
begin
  Result := '';
  Key := vkNone;
  if Wheel = mwUp then
    Key := vkUp
  else if Wheel = mwDown then
    Key := vkDown
  else if Wheel = mwLeft then
    Key := vkLeft
  else if Wheel = mwRight then
    Key := vkRight;
  if Key = vkNone then
    Exit;
  for Step := 1 to mouseWheelScrollLines do
    Result := Result + KeyBytes(Key, [], Modes);
end;

{ The bytes of the mouse }

function ModifierBits(Mods: TVtModifiers): Integer;
begin
  Result := (ModifierParam(Mods) - 1) shl 2;
end;

{ The button with the lowest number among the ones held, 0 when none is held. }
function HeldButton(const State: TVtMouseState): Integer;
var
  N: Integer;
begin
  Result := 0;
  for N := 0 to 2 do
    if (State.Buttons and (1 shl N)) <> 0 then
    begin
      Result := N + 1;
      Exit;
    end;
end;

{ Adds the character of the number N + 32 in the default encoding (one byte, up to 223) or in the UTF-8
  encoding (up to 2015). False when N cannot be encoded. }
function AppendNumber(N: Integer; Enc: TVtMouseEncoding; var Dest: AnsiString): Boolean;
begin
  Result := False;
  if N < 0 then
    Exit;
  if Enc = vtEncUtf8 then
  begin
    if N + 32 > 2047 then
      Exit;
    Dest := Dest + Utf8Text(Cardinal(N + 32));
  end
  else
  begin
    if N + 32 > 255 then
      Exit;
    Dest := Dest + AnsiChar(N + 32);
  end;
  Result := True;
end;

{ Code is the event code without the 32 of the old encodings; the cell is zero-based. A report that the
  encoding cannot hold is empty. }
function MouseReport(Code, Col, Row: Integer; Pressed: Boolean; Enc: TVtMouseEncoding): AnsiString;
var
  Head: AnsiString;
begin
  if Enc = vtEncSgr then
  begin
    Result := EscText + '[<' + IntToStr(Code) + ';' + IntToStr(Col + 1) + ';' + IntToStr(Row + 1);
    if Pressed then
      Result := Result + 'M'
    else
      Result := Result + 'm';
    Exit;
  end;
  Head := EscText + '[M';
  if AppendNumber(Code, Enc, Head) and AppendNumber(Col + 1, Enc, Head) and
     AppendNumber(Row + 1, Enc, Head) then
    Result := Head
  else
    Result := '';
end;

{ The motion to a cell: reported with a button held by the protocols 1002 and 1003, and with none held by
  1003 only. }
function MouseMoved(Row, Col: Integer; Mods: TVtModifiers; const Modes: TVtInputModes;
  var State: TVtMouseState): AnsiString;
var
  Held, Code: Integer;
begin
  Result := '';
  if (Col = State.Col) and (Row = State.Row) then
    Exit;
  State.Col := Col;
  State.Row := Row;
  if not (Modes.MouseTracking in [vtTrackButton, vtTrackAny]) then
    Exit;
  Held := HeldButton(State);
  if Held <> 0 then
    Code := Held - 1 + 32 + ModifierBits(Mods)
  else if Modes.MouseTracking = vtTrackAny then
    Code := 3 + 32 + ModifierBits(Mods)
  else
    Exit;
  Result := MouseReport(Code, Col, Row, True, Modes.MouseEncoding);
end;

{ A button pressed or released, or a step of the wheel (button 4 and 5, which have no release). }
function MouseButton(Button: Integer; Pressed: Boolean; Mods: TVtModifiers; Row, Col: Integer;
  const Modes: TVtInputModes; var State: TVtMouseState): AnsiString;
var
  Code: Integer;
begin
  Result := '';
  if (Button < 1) or (Button > 5) then
    Exit;
  if Button <= 3 then
  begin
    if Pressed then
      State.Buttons := State.Buttons or Byte(1 shl (Button - 1))
    else
      State.Buttons := State.Buttons and Byte(255 xor (1 shl (Button - 1)));
  end
  else if not Pressed then
    Exit;
  if Modes.MouseTracking = vtTrackOff then
    Exit;
  if Button >= 4 then
    Code := 64 + (Button - 4)
  else
    Code := Button - 1;
  if Modes.MouseTracking = vtTrackX10 then
  begin
    { Only the presses of the three buttons, with no modifier. }
    if (not Pressed) or (Button > 3) then
      Exit;
  end
  else
  begin
    if (not Pressed) and (Modes.MouseEncoding <> vtEncSgr) then
      Code := 3;
    Code := Code + ModifierBits(Mods);
  end;
  Result := MouseReport(Code, Col, Row, Pressed, Modes.MouseEncoding);
end;

function ProcessMouse(What: Word; const Mouse: TMouseEventType; const Modes: TVtInputModes;
  var State: TVtMouseState): AnsiString;
var
  Mods: TVtModifiers;
  Button: Integer;
begin
  ConvMouse(Mouse, Mods, Button);
  Result := MouseMoved(Mouse.Where.Y, Mouse.Where.X, Mods, Modes, State);
  if (What and (evMouseDown or evMouseUp or evMouseWheel)) <> 0 then
  begin
    { A release carries no button state, so it lets go of the button that is held. }
    if (What = evMouseUp) and (Button = 0) then
      Button := HeldButton(State);
    Result := Result + MouseButton(Button, What <> evMouseUp, Mods, Mouse.Where.Y, Mouse.Where.X,
      Modes, State);
  end;
end;

{ Paste, keypad and focus }

function ProcessPaste(const Text: AnsiString; const Modes: TVtInputModes): AnsiString;
begin
  if Modes.BracketedPaste then
    Result := EscText + '[200~' + Text + EscText + '[201~'
  else
    Result := Text;
end;

{ The letter after SS3 of a key of the application keypad, #0 for a character that has none. }
function KeypadLetter(Ch: AnsiChar): AnsiChar;
begin
  if (Ch >= '0') and (Ch <= '9') then
    Result := AnsiChar(Ord('p') + Ord(Ch) - Ord('0'))
  else
    case Ch of
      '*': Result := 'j';
      '+': Result := 'k';
      ',': Result := 'l';
      '-': Result := 'm';
      '.': Result := 'n';
      '/': Result := 'o';
      '=': Result := 'X';
      ' ': Result := ' ';
      #9: Result := 'I';
      #13: Result := 'M';
    else
      Result := #0;
    end;
end;

function ProcessKeypad(Ch: AnsiChar; const Modes: TVtInputModes): AnsiString;
var
  Letter: AnsiChar;
begin
  Result := Ch;
  if not Modes.KeypadApplication then
    Exit;
  Letter := KeypadLetter(Ch);
  if Letter <> #0 then
    Result := EscText + 'O' + Letter;
end;

function ProcessFocus(GotFocus: Boolean; const Modes: TVtInputModes): AnsiString;
begin
  Result := '';
  if not Modes.FocusReporting then
    Exit;
  if GotFocus then
    Result := EscText + '[I'
  else
    Result := EscText + '[O';
end;

end.
