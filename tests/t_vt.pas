{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/vtermemu.h, source/tvterm-core/vtermemu.cc
  See COPYRIGHT.tvterm. }
program t_vt;

{$mode objfpc}
{$R-}
{$Q-}

uses
  TvVt, TvPty, TvClip, SysUtils, TvEvents, TvKeys, TvGeom, TvCell, TvColors, TvVtKeys, TvVtScreen, TvVtCore;

{$I testlib.inc}

function Times(const Piece: AnsiString; N: Integer): AnsiString;
begin
  Result := '';
  while N > 0 do
  begin
    Result := Result + Piece;
    Dec(N);
  end;
end;

{ In the texts of the tables '^' stands for ESC and '~' for CR and LF. }
function Seq(const S: AnsiString): AnsiString;
var
  Rest, Chunk: AnsiString;
begin
  Result := '';
  Rest := S;
  while Rest <> '' do
  begin
    case Rest[1] of
      '^': Chunk := #27;
      '~': Chunk := #13 + #10;
    else
      Chunk := Rest[1];
    end;
    Result := Result + Chunk;
    Delete(Rest, 1, 1);
  end;
end;

function MakePoint(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

{ The text of a row: '.' for a blank or a space, '~' for the second cell of a wide character, '#' for a code point
  above 127, otherwise the character. }
function RowText(S: TVtScreen; Y: Integer): AnsiString;
var
  X: Integer;
  C: TVtCell;
begin
  Result := '';
  for X := 0 to S.Cols - 1 do
  begin
    S.GetCell(Y, X, C);
    if (C.Chars[0] = 0) or (C.Chars[0] = 32) then
      Result := Result + '.'
    else if C.Chars[0] = VtWideTrail then
      Result := Result + '~'
    else if C.Chars[0] < 128 then
      Result := Result + Chr(C.Chars[0])
    else
      Result := Result + '#';
  end;
end;

{ A row of a table, completed with blanks to the width of the screen. }
function PadRow(const Row: AnsiString; Wide: Integer): AnsiString;
begin
  Result := Row;
  while Length(Result) < Wide do
    Result := Result + '.';
end;

{ Want holds the rows of the screen, separated by '|'; the rows that it leaves out are blank. }
procedure ExpectScreen(S: TVtScreen; const Want, Name: AnsiString);
var
  Rest, Row, Got, Exp: AnsiString;
  Y, Bar: Integer;
begin
  Rest := Want;
  for Y := 0 to S.Rows - 1 do
  begin
    Bar := Pos('|', Rest);
    if Bar > 0 then
    begin
      Row := Copy(Rest, 1, Bar - 1);
      Rest := Copy(Rest, Bar + 1, MaxInt);
    end
    else
    begin
      Row := Rest;
      Rest := '';
    end;
    Got := RowText(S, Y);
    Exp := PadRow(Row, S.Cols);
    if Got <> Exp then
      WriteLn('  ', Name, ' row ', Y, ': got ', Got, ', want ', Exp);
    Check(Got = Exp, Name + ': row ' + IntToStr(Y));
  end;
end;

function TitleOf(St: TerminalState): AnsiString;
begin
  SetLength(Result, St.Title.Size);
  if St.Title.Size > 0 then
    Move(St.Title.Data^, Result[1], St.Title.Size);
end;

function SurfText(St: TerminalState; Y, X: Integer): AnsiString;
begin
  Result := St.Surface.At(Y, X)^.Character.GetText;
end;

{ The events of the user and of the client, as the controller would make them. }

function KeyOf(Code, Mods: Word; const Txt: AnsiString): TerminalEvent;
var
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := TerminalEventType.KeyDown;
  Result.KeyDown.KeyCode := Code;
  Result.KeyDown.ControlKeyState := Mods;
  Result.KeyDown.TextLength := Length(Txt);
  for I := 1 to Length(Txt) do
    Result.KeyDown.Text[I - 1] := Ord(Txt[I]);
end;

function MouseOf(What: Word; X, Y: Integer; Btn, Whl: Byte): TerminalEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := TerminalEventType.Mouse;
  Result.Mouse.What := What;
  Result.Mouse.Mouse.Where.X := X;
  Result.Mouse.Mouse.Where.Y := Y;
  Result.Mouse.Mouse.Buttons := Btn;
  Result.Mouse.Mouse.Wheel := Whl;
end;

function FocusOf(Gained: Boolean): TerminalEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := TerminalEventType.FocusChange;
  Result.FocusChange.FocusEnabled := Gained;
end;

function ResizeOf(X, Y: Integer): TerminalEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := TerminalEventType.ViewportResize;
  Result.ViewportResize.X := X;
  Result.ViewportResize.Y := Y;
end;

function OffsetOf(Off: Integer): TerminalEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := TerminalEventType.ScrollBackOffsetChange;
  Result.ScrollBackOffsetChange.Offset := Off;
end;

function CopyOf(X1, Y1, X2, Y2: Integer): TerminalEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := TerminalEventType.CopySelection;
  Result.CopySelection.Selection :=
    SelectionRange.Create(SelectionAnchor.Create(X1, Y1), SelectionAnchor.Create(X2, Y2));
end;

function DataOf(const Bytes: AnsiString): TerminalEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Type_ := TerminalEventType.ClientDataRead;
  Result.ClientDataRead.Data := PAnsiChar(Bytes);
  Result.ClientDataRead.Size := Length(Bytes);
end;

type
  { The writer that keeps what the emulator sends to the client. }
  TapeWriter = class(Writer)
  public
    Log: AnsiString;
    procedure Write(const Data: array of Char); override;
  end;

  { The clipboard backend that keeps the text it is given. }
  TapeClipboard = class(TClipboardBackend)
  public
    Got: string;
    Calls: Integer;
    function SetText(const Text: string): Boolean; override;
  end;

procedure TapeWriter.Write(const Data: array of Char);
var
  I: Integer;
begin
  for I := 0 to High(Data) do
    Log := Log + Data[I];
end;

function TapeClipboard.SetText(const Text: string): Boolean;
begin
  Got := Text;
  Inc(Calls);
  Result := True;
end;

{ An emulator of 12 columns and 4 rows. }
function NewEmu(W: TapeWriter): VTermEmulator;
begin
  Result := VTermEmulator.Create(MakePoint(12, 4), W);
end;

procedure Send(E: VTermEmulator; const Ev: TerminalEvent);
begin
  E.HandleEvent(Ev);
end;

procedure Feed(E: VTermEmulator; const Bytes: AnsiString);
begin
  if Bytes <> '' then
    Send(E, DataOf(Bytes));
end;

{ One event for each byte: every sequence is split at every possible place. }
procedure FeedSplit(E: VTermEmulator; const Bytes: AnsiString);
var
  I: Integer;
begin
  for I := 1 to Length(Bytes) do
    Feed(E, Bytes[I]);
end;

procedure FeedMode(E: VTermEmulator; const Bytes: AnsiString; Split: Boolean);
begin
  if Split then
    FeedSplit(E, Bytes)
  else
    Feed(E, Bytes);
end;

function ModeLabel(Split: Boolean): AnsiString;
begin
  if Split then
    Result := ' (byte by byte)'
  else
    Result := ' (whole)';
end;

{ Tables of (name, input, expected screen): each input is fed whole and then one byte at a time. }
procedure RunScreenCases(const Table: array of AnsiString);
var
  I: Integer;
  Split: Boolean;
  W: TapeWriter;
  E: VTermEmulator;
begin
  I := 0;
  while I + 2 <= High(Table) do
  begin
    for Split := False to True do
    begin
      W := TapeWriter.Create;
      E := NewEmu(W);
      FeedMode(E, Table[I + 1], Split);
      ExpectScreen(E.Screen, Table[I + 2], Table[I] + ModeLabel(Split));
      E.Free;
      W.Free;
    end;
    Inc(I, 3);
  end;
end;

{ Tables of (name, input, expected bytes written to the client). }
procedure RunAnswerCases(const Table: array of AnsiString);
var
  I: Integer;
  Split: Boolean;
  W: TapeWriter;
  E: VTermEmulator;
begin
  I := 0;
  while I + 2 <= High(Table) do
  begin
    for Split := False to True do
    begin
      W := TapeWriter.Create;
      E := NewEmu(W);
      FeedMode(E, Table[I + 1], Split);
      if W.Log <> Table[I + 2] then
        WriteLn('  ', Table[I], ': got ', Length(W.Log), ' bytes, want ', Length(Table[I + 2]));
      Check(W.Log = Table[I + 2], Table[I] + ModeLabel(Split));
      E.Free;
      W.Free;
    end;
    Inc(I, 3);
  end;
end;

function DescribeColor(const C: TVtColor): AnsiString;
begin
  case C.Kind of
    vcIndexed:
      Result := 'i' + IntToStr(C.Idx);
    vcRGB:
      Result := 'r' + IntToStr(C.Red) + '.' + IntToStr(C.Green) + '.' + IntToStr(C.Blue);
  else
    Result := 'd';
  end;
end;

{ foreground | background | letters of the attributes (bold, italic, underline, blink, reverse, strike, conceal) }
function Describe(const C: TVtCell): AnsiString;
var
  A: TVtAttr;
begin
  Result := DescribeColor(C.Fg) + '|' + DescribeColor(C.Bg) + '|';
  for A := Low(TVtAttr) to High(TVtAttr) do
    if A in C.Attrs then
      Result := Result + 'BIUKRSC'[Ord(A) + 1];
end;

{ Tables of (input, description of the first cell); the input ends with the letter that is written. }
procedure RunSgrCases(const Table: array of AnsiString);
var
  I: Integer;
  Split: Boolean;
  W: TapeWriter;
  E: VTermEmulator;
  C: TVtCell;
  Got: AnsiString;
begin
  I := 0;
  while I + 1 <= High(Table) do
  begin
    for Split := False to True do
    begin
      W := TapeWriter.Create;
      E := NewEmu(W);
      FeedMode(E, Table[I], Split);
      E.Screen.GetCell(0, 0, C);
      Got := Describe(C);
      if Got <> Table[I + 1] then
        WriteLn('  sgr ', StringReplace(Table[I], #27, '^', [rfReplaceAll]), ': got ', Got, ', want ', Table[I + 1]);
      Check((C.Chars[0] = Ord('x')) and (Got = Table[I + 1]),
        'sgr ' + StringReplace(Table[I], #27, '^', [rfReplaceAll]) + ModeLabel(Split));
      E.Free;
      W.Free;
    end;
    Inc(I, 2);
  end;
end;

procedure TestCursorAndState;
const
  Tracks: array[0..3] of Integer = (9, 1000, 1002, 1003);
var
  W: TapeWriter;
  E: VTermEmulator;
  St: TerminalState;
  N: Integer;
begin
  W := TapeWriter.Create;
  E := NewEmu(W);
  St := TerminalState.Create;

  Feed(E, 'abc');
  E.UpdateState(St);
  Check(St.CursorChanged and (St.CursorPos.X = 3) and (St.CursorPos.Y = 0), 'state: cursor position');
  Check(St.CursorVisible and not St.CursorBlink, 'state: the cursor starts visible and steady');
  Check((St.Surface.Size.X = 12) and (St.Surface.Size.Y = 4), 'state: surface size');
  Check((SurfText(St, 0, 0) = 'a') and (SurfText(St, 0, 2) = 'c'), 'state: surface text');
  Check(not St.MouseEnabled, 'state: mouse is off at first');
  Check(St.ScrollbackEnabled and (St.ScrollbackLimit = 0), 'state: scrollback on, no lines');

  St.CursorChanged := False;
  E.UpdateState(St);
  Check(not St.CursorChanged, 'state: no cursor report without a change');

  Feed(E, Seq('^[?25l'));
  E.UpdateState(St);
  Check(St.CursorChanged and not St.CursorVisible, 'state: DECTCEM off');
  St.CursorChanged := False;
  Feed(E, Seq('^[?25h'));
  E.UpdateState(St);
  Check(St.CursorChanged and St.CursorVisible, 'state: DECTCEM on');

  Feed(E, Seq('^[?12h'));
  E.UpdateState(St);
  Check(St.CursorBlink, 'state: blink on');
  Feed(E, Seq('^[?12l'));
  E.UpdateState(St);
  Check(not St.CursorBlink, 'state: blink off');
  Feed(E, Seq('^[5 q'));
  E.UpdateState(St);
  Check(St.CursorBlink, 'state: DECSCUSR 5 blinks');
  Feed(E, Seq('^[2 q'));
  E.UpdateState(St);
  Check(not St.CursorBlink, 'state: DECSCUSR 2 is steady');
  Feed(E, Seq('^[0 q'));
  E.UpdateState(St);
  Check(St.CursorBlink, 'state: DECSCUSR 0 blinks');
  Feed(E, Seq('^[7 q'));
  E.UpdateState(St);
  Check(not St.CursorBlink, 'state: DECSCUSR 7 is the initial steady cursor');

  for N := 0 to High(Tracks) do
  begin
    Feed(E, Seq('^[?' + IntToStr(Tracks[N]) + 'h'));
    E.UpdateState(St);
    Check(St.MouseEnabled, 'state: mouse on by ' + IntToStr(Tracks[N]));
    Feed(E, Seq('^[?' + IntToStr(Tracks[N]) + 'l'));
    E.UpdateState(St);
    Check(not St.MouseEnabled, 'state: mouse off by ' + IntToStr(Tracks[N]));
  end;
  Feed(E, Seq('^[?1006h^[?1005h'));
  E.UpdateState(St);
  Check(not St.MouseEnabled, 'state: an encoding alone does not enable the mouse');
  Feed(E, Seq('^[?1000h^[?1002h^[?1002l'));
  E.UpdateState(St);
  Check(not St.MouseEnabled, 'state: the reset of the active mode turns the mouse off');

  { the alternate screen hides the scrollback bar }
  Feed(E, Seq('^[?1049h'));
  E.UpdateState(St);
  Check(not St.ScrollbackEnabled and St.ScrollbackChanged, 'state: scrollback is off in the alternate screen');
  Feed(E, Seq('^[?1049l'));
  E.UpdateState(St);
  Check(St.ScrollbackEnabled, 'state: scrollback is on again');

  St.Free;
  E.Free;
  W.Free;
end;

procedure CheckTitle(const Name, Input, Want: AnsiString; Changed: Boolean);
var
  Split: Boolean;
  W: TapeWriter;
  E: VTermEmulator;
  St: TerminalState;
begin
  for Split := False to True do
  begin
    W := TapeWriter.Create;
    E := NewEmu(W);
    St := TerminalState.Create;
    FeedMode(E, Input, Split);
    E.UpdateState(St);
    Check(St.TitleChanged = Changed, 'title ' + Name + ': changed' + ModeLabel(Split));
    if Changed then
    begin
      Check(TitleOf(St) = Want, 'title ' + Name + ': text' + ModeLabel(Split));
      St.TitleChanged := False;
      E.UpdateState(St);
      Check(not St.TitleChanged, 'title ' + Name + ': reported once' + ModeLabel(Split));
    end;
    St.Free;
    E.Free;
    W.Free;
  end;
end;

procedure TestTitles;
begin
  CheckTitle('osc 0 and BEL', Seq('^]0;hello') + #7, 'hello', True);
  CheckTitle('osc 2 and ST', Seq('^]2;Name^\'), 'Name', True);
  CheckTitle('osc 1', Seq('^]1;icon^\'), 'icon', True);
  CheckTitle('utf-8 text', Seq('^]0;h') + #$C3#$A9 + #7, 'h' + #$C3#$A9, True);
  CheckTitle('8-bit ST', Seq('^]0;x') + #$C2#$9C, 'x', True);
  CheckTitle('8-bit OSC', #$C2#$9D + '0;t' + #$C2#$9C, 't', True);
  CheckTitle('empty', Seq('^]0;') + #7, '', True);
  CheckTitle('the last one wins', Seq('^]0;first^\^]0;second^\'), 'second', True);
  CheckTitle('ended by ESC', Seq('^]2;abc^H'), 'abc', True);
  CheckTitle('text with semicolons', Seq('^]0;a;b;c^\'), 'a;b;c', True);
  CheckTitle('cancelled', Seq('^]0;zzz') + #24 + 'x', '', False);
  CheckTitle('colours', Seq('^]4;1;rgb:ff/00/00') + #7, '', False);
  CheckTitle('colour query', Seq('^]11;?') + #7, '', False);
  CheckTitle('hyperlink', Seq('^]8;;http://example.org^\'), '', False);
  CheckTitle('clipboard', Seq('^]52;c;SGVsbG8=') + #7, '', False);
  CheckTitle('no number', Seq('^]x;abc^\'), '', False);
  CheckTitle('no separator', Seq('^]0abc^\'), '', False);
end;

procedure TestEvents;
var
  W: TapeWriter;
  E: VTermEmulator;
  St: TerminalState;
  Quiet: AnsiString;
begin
  { keys }
  W := TapeWriter.Create;
  E := NewEmu(W);
  Send(E, KeyOf(kbUp, 0, ''));
  Check(W.Log = Seq('^[A'), 'key: up in the normal mode');
  W.Log := '';
  Feed(E, Seq('^[?1h'));
  Send(E, KeyOf(kbUp, 0, ''));
  Check(W.Log = Seq('^OA'), 'key: up in the application mode');
  W.Log := '';
  Send(E, KeyOf(Ord('a'), 0, 'a'));
  Check(W.Log = 'a', 'key: a letter');
  E.Free;
  W.Free;

  { focus }
  W := TapeWriter.Create;
  E := NewEmu(W);
  Send(E, FocusOf(True));
  Send(E, FocusOf(False));
  Check(W.Log = '', 'focus: nothing before mode 1004');
  Feed(E, Seq('^[?1004h'));
  Send(E, FocusOf(True));
  Check(W.Log = Seq('^[I'), 'focus: in');
  Send(E, FocusOf(False));
  Check(W.Log = Seq('^[I^[O'), 'focus: out');
  E.Free;
  W.Free;

  { mouse reports }
  W := TapeWriter.Create;
  E := NewEmu(W);
  Send(E, MouseOf(evMouseDown, 2, 3, mbLeftButton, 0));
  Check(W.Log = '', 'mouse: no report while the mouse is off');
  Feed(E, Seq('^[?1000h^[?1006h'));
  Send(E, MouseOf(evMouseDown, 2, 3, mbLeftButton, 0));
  Check(W.Log = Seq('^[<0;3;4M'), 'mouse: press in the SGR encoding');
  Send(E, MouseOf(evMouseUp, 2, 3, 0, 0));
  Check(W.Log = Seq('^[<0;3;4M^[<0;3;4m'), 'mouse: release in the SGR encoding');
  E.Free;
  W.Free;

  { the wheel }
  W := TapeWriter.Create;
  E := NewEmu(W);
  Feed(E, Seq('^[?1049h'));
  Send(E, MouseOf(evMouseWheel, 0, 0, 0, mwUp));
  Check(W.Log = Seq('^[A^[A^[A'), 'wheel: up on the alternate screen gives three up arrows');
  W.Log := '';
  Send(E, MouseOf(evMouseWheel, 0, 0, 0, mwDown));
  Check(W.Log = Seq('^[B^[B^[B'), 'wheel: down on the alternate screen gives three down arrows');
  W.Log := '';
  Feed(E, Seq('^[?1h'));
  Send(E, MouseOf(evMouseWheel, 0, 0, 0, mwUp));
  Check(W.Log = Seq('^OA^OA^OA'), 'wheel: the arrows follow the cursor key mode');
  W.Log := '';
  Send(E, MouseOf(evMouseDown, 1, 1, mbLeftButton, 0));
  Check(W.Log = '', 'wheel: a press on the alternate screen is not sent');
  W.Log := '';
  Feed(E, Seq('^[?1000h^[?1006h'));
  Send(E, MouseOf(evMouseWheel, 0, 0, 0, mwUp));
  Check(W.Log = Seq('^[<64;1;1M'), 'wheel: a client that asks for the mouse gets the report');
  E.Free;
  W.Free;

  { the scrollback }
  W := TapeWriter.Create;
  E := NewEmu(W);
  St := TerminalState.Create;
  Feed(E, Times(Seq('a~'), 6));
  E.UpdateState(St);
  Check((St.ScrollbackLimit = 3) and (St.ScrollbackOffset = 3) and St.ScrollbackEnabled,
    'scrollback: three lines left the screen and the view follows');
  Send(E, MouseOf(evMouseWheel, 0, 0, 0, mwUp));
  E.UpdateState(St);
  Check((St.ScrollbackOffset = 0) and (W.Log = ''), 'scrollback: the wheel up moves three lines and sends nothing');
  Send(E, MouseOf(evMouseWheel, 0, 0, 0, mwDown));
  E.UpdateState(St);
  Check(St.ScrollbackOffset = 3, 'scrollback: the wheel down moves back');
  Send(E, OffsetOf(1));
  E.UpdateState(St);
  Check(St.ScrollbackOffset = 1, 'scrollback: the offset is set');
  Send(E, OffsetOf(99));
  E.UpdateState(St);
  Check(St.ScrollbackOffset = 3, 'scrollback: the offset stops at the last line');
  Send(E, OffsetOf(1));
  Send(E, KeyOf(Ord('a'), 0, 'a'));
  E.UpdateState(St);
  Check((St.ScrollbackOffset = 3) and (W.Log = 'a'), 'scrollback: a key makes the view follow the terminal');
  St.Free;
  E.Free;
  W.Free;

  { the size of the viewport }
  W := TapeWriter.Create;
  E := NewEmu(W);
  St := TerminalState.Create;
  Feed(E, 'abc');
  Send(E, ResizeOf(6, 2));
  E.UpdateState(St);
  Check((E.Screen.Cols = 6) and (E.Screen.Rows = 2), 'resize: the screen has the new size');
  Check((St.Surface.Size.X = 6) and (St.Surface.Size.Y = 2), 'resize: the surface has the new size');
  Check((SurfText(St, 0, 0) = 'a') and (SurfText(St, 0, 2) = 'c'), 'resize: the text stays');
  Send(E, ResizeOf(0, -5));
  Check((E.Screen.Cols = 1) and (E.Screen.Rows = 1), 'resize: at least one cell');
  St.Free;
  E.Free;
  W.Free;

  { text of the client does not produce answers }
  W := TapeWriter.Create;
  E := NewEmu(W);
  Quiet := 'plain text' + Seq('^[1;31m^[2J^[H') + #7;
  Feed(E, Quiet);
  Check(W.Log = '', 'a client that only writes gets no answer');
  E.Free;
  W.Free;
end;

procedure TestClipboard;
var
  W: TapeWriter;
  E: VTermEmulator;
  Tape: TapeClipboard;
  Saved: TClipboardBackend;
begin
  Saved := TClipboard.Backend;
  Tape := TapeClipboard.Create;
  TClipboard.Backend := Tape;
  W := TapeWriter.Create;
  E := NewEmu(W);
  Feed(E, 'hello');
  Send(E, CopyOf(0, 0, 5, 0));
  Check((Tape.Calls = 1) and (Tape.Got = 'hello'), 'copy: one row');
  Feed(E, Seq('~cd'));
  Send(E, CopyOf(0, 0, 2, 1));
  Check((Tape.Calls = 2) and (Tape.Got = 'hello' + #10 + 'cd'), 'copy: two rows are joined by a line feed');
  Send(E, CopyOf(3, 0, 1, 0));
  Check(Tape.Got = 'el', 'copy: the anchors may be in either order');
  E.Free;
  W.Free;
  TClipboard.Backend := Saved;
  Tape.Free;
end;

procedure TestFactory;
var
  F: VTermEmulatorFactory;
  W: TapeWriter;
  Em: TerminalEmulator;
  Env: TEnvironmentVarSpan;
  First, Second: PEnvironmentVar;
begin
  F := VTermEmulatorFactory.Create;
  W := TapeWriter.Create;
  Em := F.Make(MakePoint(0, 0), W);
  Check(Em is VTermEmulator, 'factory: the emulator class');
  Check((VTermEmulator(Em).Screen.Cols = 1) and (VTermEmulator(Em).Screen.Rows = 1),
    'factory: the size is at least 1 x 1');
  Env := F.GetCustomEnvironment;
  Check(Env.Size = 2, 'factory: two variables');
  First := Env.Data;
  Second := PEnvironmentVar(PtrUInt(Env.Data) + SizeOf(EnvironmentVar));
  Check((AnsiString(First^.Name) = 'TERM') and (AnsiString(First^.Value) = 'xterm-256color'), 'factory: TERM');
  Check((AnsiString(Second^.Name) = 'COLORTERM') and (AnsiString(Second^.Value) = 'truecolor'), 'factory: COLORTERM');
  Em.Free;
  W.Free;
  F.Free;
end;

procedure TestGraphicCells;
var
  W: TapeWriter;
  E: VTermEmulator;
  C: TVtCell;
begin
  W := TapeWriter.Create;
  E := NewEmu(W);
  Feed(E, Seq('^(0lqkx^(B'));
  E.Screen.GetCell(0, 0, C);
  Check(C.Chars[0] = $250C, 'graphics: l is the upper left corner');
  E.Screen.GetCell(0, 1, C);
  Check(C.Chars[0] = $2500, 'graphics: q is the horizontal line');
  E.Screen.GetCell(0, 2, C);
  Check(C.Chars[0] = $2510, 'graphics: k is the upper right corner');
  E.Screen.GetCell(0, 3, C);
  Check(C.Chars[0] = $2502, 'graphics: x is the vertical line');
  Feed(E, Seq('~^(A#'));
  E.Screen.GetCell(1, 0, C);
  Check(C.Chars[0] = $A3, 'UK set: the number sign is the pound sign');
  E.Free;
  W.Free;
end;

begin
  RunScreenCases([
    'text', 'Hi', 'Hi',
    'wrap', 'ABCDEFGHIJKLMN', 'ABCDEFGHIJKL|MN',
    'wrap pending then CR LF', Seq('ABCDEFGHIJKL~x'), 'ABCDEFGHIJKL|x',
    'LF keeps the column', 'ab' + #10 + 'c', 'ab|..c',
    'LNM makes LF a new line', Seq('^[20hab') + #10 + 'c', 'ab|c',
    'BS', 'abc' + #8 + 'X', 'abX',
    'HT', 'a' + #9 + 'b', 'a.......b',
    'CR', 'abc' + #13 + 'X', 'Xbc',
    'VT and FF act as LF', 'a' + #11 + 'b' + #12 + 'c', 'a|.b|..c',
    'NUL BEL and DEL are ignored', 'a' + #0 + #7 + #127 + 'b', 'ab',
    'UTF-8 text', 'a' + #$C3#$A9 + 'b', 'a#b',
    'wide character', #$E4#$B8#$AD + 'x', '#~x',
    'wide character at the last column', 'aaaaaaaaaaa' + #$E4#$B8#$AD, 'aaaaaaaaaaa|#~',
    'combining mark', 'e' + #$CC#$81 + 'x', 'ex',
    'invalid byte', 'a' + #$FF + 'b', 'a#b',
    'cut sequence', #$E4#$B8 + 'x', '#x',
    'stray bytes', #$80 + #$C0 + 'a', '##a',

    'CUB', Seq('abc^[2DX'), 'aXc',
    'CUF', Seq('a^[3Cb'), 'a...b',
    'CUP and CUU', Seq('^[3;4Hx^[2Ay'), '....y||...x',
    'CUD', Seq('a^[2Bb'), 'a||.b',
    'CNL', Seq('abc^[1Ed'), 'abc|d',
    'CNL and CPL', Seq('abc^[2E^[1Fd'), 'abc|d',
    'CHA', Seq('abcdef^[2GX'), 'aXcdef',
    'CUP without parameters', Seq('ab^[HX'), 'Xb',
    'HVP', Seq('^[2;3fY'), '|..Y',
    'HPA', Seq('^[5`a'), '....a',
    'VPA', Seq('^[3db'), '||b',
    'HPR and VPR', Seq('a^[2ab^[1ec'), 'a..b|....c',
    'CUP beyond the screen', Seq('^[99;99HZ'), '|||...........Z',
    'CUF beyond the screen', Seq('^[99CQ'), '...........Q',
    'a parameter that does not fit', Seq('^[99999999999CQ'), '...........Q',
    'REP', Seq('a^[3b'), 'aaaa',
    'ECH', Seq('abcdef^[1G^[2X'), '..cdef',
    'ICH', Seq('abcdef^[1G^[2@'), '..abcdef',
    'DCH', Seq('abcdef^[2G^[2P'), 'adef',

    'EL 0', Seq('abcdef^[3G^[K'), 'ab',
    'EL 1', Seq('abcdef^[3G^[1K'), '...def',
    'EL 2', Seq('abc^[2K'), '',
    'ED 0', Seq('aaa~bbb~ccc^[2;2H^[J'), 'aaa|b',
    'ED 1', Seq('aaa~bbb~ccc^[2;2H^[1J'), '|..b|ccc',
    'ED 2', Seq('abc^[2J'), '',
    'ED 3 keeps the screen', Seq('abc^[3J'), 'abc',
    'IL', Seq('aaa~bbb~ccc^[2;1H^[L'), 'aaa||bbb|ccc',
    'DL', Seq('aaa~bbb~ccc^[2;1H^[M'), 'aaa|ccc',
    'SU', Seq('aaa~bbb~ccc^[S'), 'bbb|ccc',
    'SD', Seq('aaa~bbb~ccc^[T'), '|aaa|bbb|ccc',

    'LF at the bottom of a region', Seq('^[2;3raaa^[2;1Hbbb^[3;1Hccc') + #10 + 'd', 'aaa|ccc|...d',
    'RI at the top of a region', Seq('^[2;3r^[2;1Hq^[2;1H^M'), '||q',
    'origin mode', Seq('^[2;3r^[?6h^[1;1Hx^[?6l^[1;1Hy'), 'y|x',
    'origin mode keeps the cursor in the region', Seq('^[2;3r^[?6h^[9;1Hz'), '||z',
    'IND', Seq('ab^Dc'), 'ab|..c',
    'NEL', Seq('ab^Ec'), 'ab|c',
    'RI at the top of the screen', Seq('a^Mb'), '.b|a',
    'TBC 3', Seq('^[3ga') + #9 + 'b', 'a..........b',
    'HTS', Seq('^[3g^[5G^H^[1G') + #9 + 'x', '....x',
    'CBT', Seq('abcdefghij^[ZX'), 'abcdefghXj',
    'CHT', Seq('^[2Ix'), '...........x',
    'DECSC and DECRC', Seq('ab^7^[3;3HX^8c'), 'abc||..X',
    'SCOSC and SCORC', Seq('ab^[s^[3;3HX^[uc'), 'abc||..X',

    'DECAWM off', Seq('^[?7lABCDEFGHIJKLMN'), 'ABCDEFGHIJKN',
    'DECAWM on again', Seq('^[?7l^[?7hABCDEFGHIJKLMN'), 'ABCDEFGHIJKL|MN',
    'IRM', Seq('abc^[1G^[4hX^[4lY'), 'XYbc',
    'alternate screen content', Seq('abc^[?1049hX'), '...X',
    'alternate screen restore', Seq('abc^[?1049hX^[?1049ld'), 'abcd',
    'mode 47', Seq('abc^[?47hX^[?47ld'), 'abc.d',
    'mode 1047', Seq('abc^[?1047hX^[?1047ld'), 'abc.d',
    'mode 1048', Seq('ab^[?1048h^[3;3HX^[?1048lc'), 'abc||..X',
    'DECALN', Seq('^#8'), 'EEEEEEEEEEEE|EEEEEEEEEEEE|EEEEEEEEEEEE|EEEEEEEEEEEE',
    'RIS', Seq('abc^[1;31m^[?25l^cx'), 'x',
    'DECSTR', Seq('abc^[!px'), 'abcx',

    'DEC graphics', Seq('^(0lqk^(Blqk'), '###lqk',
    'SO and SI', Seq('^)0') + #14 + 'q' + #15 + 'q', '#q',
    'charset saved by DECSC', Seq('^(0^7^(B^8q'), '#',

    'CAN cancels CSI', Seq('a^[2') + #24 + 'b', 'ab',
    'SUB cancels CSI', Seq('a^[3') + #26 + 'b', 'ab',
    'ESC restarts a sequence', Seq('a^[31^[2Cx'), 'a..x',
    'unknown final', Seq('a^[5yb'), 'ab',
    'unknown private mode', Seq('^[?9999ha'), 'a',
    'unknown ESC sequence', Seq('a^qb'), 'ab',
    'too many parameters', Seq('^[' + Times('1;', 40) + '1mx'), 'x',
    'junk after an intermediate', Seq('a^[ 5Cb'), 'ab',
    'a control inside CSI', Seq('ab^[2') + #8 + 'DX', 'Xb',
    'DEC private erase', Seq('abcdef^[3G^[?K'), 'ab',

    'DCS is skipped', Seq('^P1;2|abc^\x'), 'x',
    'DCS ended by BEL', Seq('^Pabc') + #7 + 'x', 'x',
    'APC, PM and SOS are skipped', Seq('^_app^\a') + #27 + '^pm' + Seq('^\b^Xsos^\c'), 'abc',
    'OSC with a colour', Seq('^]4;1;rgb:ff/00/00') + #7 + 'x', 'x',
    'hyperlinks leave the text', Seq('^]8;;http://example.org^\link^]8;;^\'), 'link',
    'OSC 52 is not served', Seq('^]52;c;SGVsbG8=') + #7 + 'x', 'x',

    'C1 CSI', 'ab' + #$C2#$9B + '2DX', 'Xb',
    'C1 IND', 'a' + #$C2#$84 + 'b', 'a|.b',
    'C1 NEL', 'a' + #$C2#$85 + 'b', 'a|b',
    'C1 RI', 'a' + #$C2#$8D + 'b', '.b|a',
    'C1 DCS and ST', #$C2#$90 + 'zz' + #$C2#$9C + 'x', 'x'
  ]);

  RunSgrCases([
    Seq('^[31mx'), 'i1|d|',
    Seq('^[1;32mx'), 'i2|d|B',
    Seq('^[44mx'), 'd|i4|',
    Seq('^[91mx'), 'i9|d|',
    Seq('^[103mx'), 'd|i11|',
    Seq('^[37;47mx'), 'i7|i7|',
    Seq('^[97;107mx'), 'i15|i15|',
    Seq('^[38;5;200mx'), 'i200|d|',
    Seq('^[48;5;17mx'), 'd|i17|',
    Seq('^[38;5;300mx'), 'i255|d|',
    Seq('^[38;2;10;20;30mx'), 'r10.20.30|d|',
    Seq('^[48;2;255;0;128mx'), 'd|r255.0.128|',
    Seq('^[38:5:99mx'), 'i99|d|',
    Seq('^[48:5:3mx'), 'd|i3|',
    Seq('^[38:2::1:2:3mx'), 'r1.2.3|d|',
    Seq('^[38:2:4:5:6mx'), 'r4.5.6|d|',
    Seq('^[48:2::7:8:9mx'), 'd|r7.8.9|',
    Seq('^[38;5;1;1mx'), 'i1|d|B',
    Seq('^[31;1;42mx'), 'i1|i2|B',
    Seq('^[31:1mx'), 'i1|d|',
    Seq('^[3;4;5;7;9;8mx'), 'd|d|IUKRSC',
    Seq('^[1;31;0mx'), 'd|d|',
    Seq('^[1;4m^[22;24mx'), 'd|d|',
    Seq('^[31;39mx'), 'd|d|',
    Seq('^[41;49mx'), 'd|d|',
    Seq('^[4:3mx'), 'd|d|U',
    Seq('^[4m^[4:0mx'), 'd|d|',
    Seq('^[1m^[mx'), 'd|d|',
    Seq('^[38;5mx'), 'd|d|',
    Seq('^[38;2;1;2mx'), 'd|d|',
    Seq('^[7;27mx'), 'd|d|',
    Seq('^[1;5;25mx'), 'd|d|B',
    Seq('^[21mx'), 'd|d|U',
    Seq('^[6mx'), 'd|d|K',
    Seq('^[31m^7^[0m^8x'), 'i1|d|'
  ]);

  RunAnswerCases([
    'DA1', Seq('^[c'), Seq('^[?62;22c'),
    'DA1 with 0', Seq('^[0c'), Seq('^[?62;22c'),
    'DA1 with another number', Seq('^[1c'), '',
    'DECID', Seq('^Z'), Seq('^[?62;22c'),
    'C1 DECID', #$C2#$9A, Seq('^[?62;22c'),
    'DA2', Seq('^[>c'), Seq('^[>1;10;0c'),
    'DA2 with 0', Seq('^[>0c'), Seq('^[>1;10;0c'),
    'DA3', Seq('^[=c'), Seq('^P!|00000000^\'),
    'XTVERSION', Seq('^[>0q'), Seq('^P>|TvVt(0.1)^\'),
    'DSR status', Seq('^[5n'), Seq('^[0n'),
    'DSR position', Seq('abc^[6n'), Seq('^[1;4R'),
    'DSR position after CUP', Seq('^[2;3H^[6n'), Seq('^[2;3R'),
    'DSR position at the end of a row', Seq('ABCDEFGHIJKL^[6n'), Seq('^[1;12R'),
    'DEC DSR position', Seq('abc^[?6n'), Seq('^[?1;4R'),
    'DSR position in the origin mode', Seq('^[2;3r^[?6h^[6n'), Seq('^[1;1R'),
    'DSR printer', Seq('^[?15n'), Seq('^[?10n'),
    'DSR user keys', Seq('^[?25n'), Seq('^[?20n'),
    'DSR keyboard', Seq('^[?26n'), Seq('^[?27;1;0;0n'),
    'DSR unknown', Seq('^[7n'), '',
    'window size', Seq('^[18t'), Seq('^[8;4;12t'),
    'screen size', Seq('^[19t'), Seq('^[9;4;12t'),
    'DECRQM wrap', Seq('^[?7$p'), Seq('^[?7;1$y'),
    'DECRQM wrap off', Seq('^[?7l^[?7$p'), Seq('^[?7;2$y'),
    'DECRQM cursor', Seq('^[?25$p'), Seq('^[?25;1$y'),
    'DECRQM columns', Seq('^[?3$p'), Seq('^[?3;4$y'),
    'DECRQM unknown', Seq('^[?9999$p'), Seq('^[?9999;0$y'),
    'DECRQM origin', Seq('^[?6h^[?6$p'), Seq('^[?6;1$y'),
    'DECRQM paste', Seq('^[?2004h^[?2004$p'), Seq('^[?2004;1$y'),
    'DECRQM alternate screen', Seq('^[?1049$p'), Seq('^[?1049;2$y'),
    'DECRQM alternate screen on', Seq('^[?1049h^[?1049$p'), Seq('^[?1049;1$y'),
    'DECRQM mouse', Seq('^[?1000h^[?1000$p'), Seq('^[?1000;1$y'),
    'DECRQM another mouse mode', Seq('^[?1000h^[?1002$p'), Seq('^[?1002;2$y'),
    'DECRQM SGR mouse', Seq('^[?1006h^[?1006$p'), Seq('^[?1006;1$y'),
    'DECRQM focus', Seq('^[?1004$p'), Seq('^[?1004;2$y'),
    'DECRQM IRM', Seq('^[4$p'), Seq('^[4;2$y'),
    'DECRQM IRM on', Seq('^[4h^[4$p'), Seq('^[4;1$y'),
    'DECRQM LNM', Seq('^[20h^[20$p'), Seq('^[20;1$y'),
    'DECRQM ANSI unknown', Seq('^[99$p'), Seq('^[99;0$y'),
    'DECRQSS SGR', Seq('^[1;31m^P$qm^\'), Seq('^P1$r0;1;31m^\'),
    'DECRQSS margins', Seq('^[2;3r^P$qr^\'), Seq('^P1$r2;3r^\'),
    'DECRQSS unknown', Seq('^P$qz^\'), Seq('^P0$r^\'),
    'no answer to a colour query', Seq('^]11;?') + #7, '',
    'no answer to text', 'hello', ''
  ]);

  TestCursorAndState;
  TestTitles;
  TestEvents;
  TestClipboard;
  TestFactory;
  TestGraphicCells;
  Done;
end.
