{ Translated from magiblot/tvterm @ 210eb23
  C++ sources: include/tvterm/vtermemu.h, source/tvterm-core/vtermemu.cc
  See COPYRIGHT.tvterm. }
program t_vtscreen;

{$mode objfpc}

uses
  SysUtils, TvGeom, TvColors, TvCell, TvEvents, TvVtCore, TvVtScreen;

{$I testlib.inc}

{ The text of a row: '.' for an erased cell, '~' for the second cell of a wide character, '#' for a code point
  above 127, otherwise the character. }
function RowText(S: TVtScreen; Y: Integer): AnsiString;
var
  X: Integer;
  C: TVtCell;
begin
  Result := '';
  for X := 0 to S.Cols - 1 do
  begin
    if not S.GetCell(Y, X, C) then
      Continue;
    if C.Chars[0] = 0 then
      Result := Result + '.'
    else if C.Chars[0] = VtWideTrail then
      Result := Result + '~'
    else if C.Chars[0] < 128 then
      Result := Result + Chr(C.Chars[0])
    else
      Result := Result + '#';
  end;
end;

procedure ExpectRows(S: TVtScreen; const Want: array of AnsiString; const Name: AnsiString);
var
  Y: Integer;
  Got: AnsiString;
begin
  Check(S.Rows = Length(Want), Name + ': number of rows');
  for Y := 0 to High(Want) do
  begin
    if Y >= S.Rows then
      Break;
    Got := RowText(S, Y);
    if Got <> Want[Y] then
      WriteLn('  ', Name, ' row ', Y, ': got ', Got, ', want ', Want[Y]);
    Check(Got = Want[Y], Name + ': row ' + IntToStr(Y));
  end;
end;

{ Writes each text at the start of its row and puts the cursor at the origin. }
procedure LoadRows(S: TVtScreen; const Lines: array of AnsiString);
var
  I: Integer;
begin
  for I := 0 to High(Lines) do
  begin
    S.MoveTo(0, I);
    S.PutText(Lines[I]);
  end;
  S.MoveTo(0, 0);
end;

function SurfText(St: TerminalState; Y, X: Integer): AnsiString;
begin
  Result := St.Surface.At(Y, X)^.Character.GetText;
end;

function IsBlankText(const T: AnsiString): Boolean;
begin
  Result := (T = #0) or (T = ' ');
end;

function LineOf(Code: Cardinal): TVtCellArray;
begin
  SetLength(Result, 1);
  Result[0] := DefaultCell;
  Result[0].Chars[0] := Code;
end;

function Selected(S: TVtScreen; X1, Y1, X2, Y2: Integer): AnsiString;
begin
  Result := S.CopySelection(SelectionRange.Create(SelectionAnchor.Create(X1, Y1), SelectionAnchor.Create(X2, Y2)));
end;

{ A 3 x 2 screen whose history holds one line, 'aaa', and whose rows are 'bbb' (the continuation of the line that
  went to the history) and 'ccc'. }
function WrappedScene: TVtScreen;
begin
  Result := TVtScreen.Create(3, 2);
  Result.PutText('aaabbb');
  Result.LineFeed;
  Result.MoveTo(0, 1);
  Result.PutText('ccc');
end;

{ A 3 x 2 screen whose history holds 'aaa' and 'bbb' and whose rows are 'ccc' and blank. }
function PlainScene: TVtScreen;
begin
  Result := TVtScreen.Create(3, 2);
  LoadRows(Result, ['aaa', 'bbb']);
  Result.MoveTo(0, 1);
  Result.LineFeed;
  Result.MoveTo(0, 1);
  Result.PutText('ccc');
  Result.MoveTo(0, 1);
  Result.LineFeed;
end;

procedure TestWrapping;
var
  S: TVtScreen;
begin
  S := TVtScreen.Create(5, 3);
  S.PutText('abcde');
  Check(S.WrapPending and (S.CursorX = 4) and (S.CursorY = 0), 'wrap is pending in the last column');
  S.PutText('f');
  ExpectRows(S, ['abcde', 'f....', '.....'], 'wrap');
  Check((S.CursorX = 1) and (S.CursorY = 1) and not S.WrapPending, 'cursor after the wrap');
  Check(S.LineContinues(1) and not S.LineContinues(0) and not S.LineContinues(2), 'continuation flags');
  S.MoveTo(4, 2);
  S.PutText('z');
  Check(S.WrapPending, 'pending after a character in the last column');
  S.MoveTo(4, 2);
  Check(not S.WrapPending, 'a move clears the pending wrap');
  S.Free;

  S := TVtScreen.Create(3, 1);
  S.AutoWrap := False;
  S.PutText('abcd');
  ExpectRows(S, ['abd'], 'no auto wrap');
  Check(not S.WrapPending, 'no pending wrap without auto wrap');
  S.Free;

  S := TVtScreen.Create(4, 3);
  S.PutText('ab'#10'cd');
  ExpectRows(S, ['ab..', '..cd', '....'], 'line feed keeps the column');
  S.Free;

  S := TVtScreen.Create(4, 3);
  S.PutText('ab'#13#10'cd'#13'X'#8'Y');
  ExpectRows(S, ['ab..', 'Yd..', '....'], 'carriage return and backspace');
  S.Free;
end;

procedure TestScrollOffTop;
var
  S: TVtScreen;
  Entry: PVtLine;
begin
  S := TVtScreen.Create(5, 2);
  S.PutText('abcdefghijk');
  ExpectRows(S, ['fghij', 'k....'], 'scrolled');
  Check(S.History.NumLines = 1, 'one line in the history');
  Check(S.History.IsFollowingTerminal and (S.History.Offset = 1), 'the offset follows the terminal');
  Entry := S.History.LineAt(0);
  Check((Entry^.Cols = 5) and (Entry^.Cells[0].Chars[0] = Ord('a')) and (Entry^.Cells[4].Chars[0] = Ord('e')),
    'the pushed line');
  Check(not Entry^.Continuation, 'the first line is no continuation');
  Check(S.LineContinues(0) and S.LineContinues(1), 'the rows keep their continuation flags');
  S.Free;

  S := TVtScreen.Create(3, 2);
  LoadRows(S, ['aaa', 'bbb']);
  S.DeleteLines(1);
  ExpectRows(S, ['bbb', '...'], 'delete at the top of the whole screen');
  Check(S.History.NumLines = 1, 'deleting the first line of the screen pushes it');
  S.Free;
end;

procedure TestRegions;
var
  S: TVtScreen;
begin
  S := TVtScreen.Create(4, 5);
  LoadRows(S, ['1', '2', '3', '4', '5']);
  S.SetScrollRegion(1, 3);
  Check((S.TopMargin = 1) and (S.BottomMargin = 3) and (S.CursorX = 0) and (S.CursorY = 0), 'region set');
  S.MoveTo(0, 3);
  S.LineFeed;
  ExpectRows(S, ['1...', '3...', '4...', '....', '5...'], 'line feed at the bottom margin');
  Check(S.History.NumLines = 0, 'a region is not pushed');
  S.MoveTo(0, 1);
  S.ReverseIndex;
  ExpectRows(S, ['1...', '....', '3...', '4...', '5...'], 'reverse index at the top margin');
  S.ScrollUp(1);
  ExpectRows(S, ['1...', '3...', '4...', '....', '5...'], 'scroll up');
  S.ScrollDown(2);
  ExpectRows(S, ['1...', '....', '....', '3...', '5...'], 'scroll down by two');
  S.MoveTo(0, 0);
  S.ReverseIndex;
  Check(S.CursorY = 0, 'reverse index above the region only stops at the screen');
  S.MoveTo(0, 4);
  S.LineFeed;
  Check(S.CursorY = 4, 'line feed below the region stops at the last row');
  S.SetScrollRegion(3, 3);
  Check((S.TopMargin = 0) and (S.BottomMargin = 4), 'a region of one row is the whole screen');
  S.SetScrollRegion(0, 2);
  S.MoveTo(0, 2);
  S.LineFeed;
  Check(S.History.NumLines = 0, 'a region that starts at the top but is not the screen is not pushed');
  S.Free;

  S := TVtScreen.Create(3, 4);
  LoadRows(S, ['aaa', 'bbb', 'ccc', 'ddd']);
  S.MoveTo(2, 1);
  S.InsertLines(1);
  ExpectRows(S, ['aaa', '...', 'bbb', 'ccc'], 'insert line');
  Check(S.CursorX = 0, 'insert line moves to the first column');
  S.DeleteLines(2);
  ExpectRows(S, ['aaa', 'ccc', '...', '...'], 'delete lines');
  S.SetScrollRegion(1, 2);
  S.MoveTo(0, 3);
  S.InsertLines(1);
  ExpectRows(S, ['aaa', 'ccc', '...', '...'], 'insert outside the region');
  S.Free;
end;

procedure TestErasing;
var
  S: TVtScreen;
  C: TVtCell;
  Found: Boolean;
begin
  S := TVtScreen.Create(6, 2);
  LoadRows(S, ['abcdef', 'ghijkl']);
  S.MoveTo(2, 0);
  S.EraseInLine(0);
  ExpectRows(S, ['ab....', 'ghijkl'], 'erase to the end of the line');
  LoadRows(S, ['abcdef']);
  S.MoveTo(2, 1);
  S.EraseInLine(1);
  ExpectRows(S, ['abcdef', '...jkl'], 'erase to the start of the line');
  S.MoveTo(0, 0);
  S.EraseInLine(2);
  ExpectRows(S, ['......', '...jkl'], 'erase the line');
  LoadRows(S, ['abcdef']);
  S.MoveTo(1, 0);
  S.EraseChars(2);
  ExpectRows(S, ['a..def', '...jkl'], 'erase characters');
  S.Free;

  S := TVtScreen.Create(3, 3);
  LoadRows(S, ['aaa', 'bbb', 'ccc']);
  S.MoveTo(1, 1);
  S.EraseInDisplay(0);
  ExpectRows(S, ['aaa', 'b..', '...'], 'erase below');
  LoadRows(S, ['aaa', 'bbb', 'ccc']);
  S.MoveTo(1, 1);
  S.EraseInDisplay(1);
  ExpectRows(S, ['...', '..b', 'ccc'], 'erase above');
  S.EraseInDisplay(2);
  ExpectRows(S, ['...', '...', '...'], 'erase all');
  S.Free;

  S := PlainScene;
  S.EraseInDisplay(3);
  Check((S.History.NumLines = 0) and (S.History.Offset = 0), 'erase of the saved lines');
  ExpectRows(S, ['ccc', '...'], 'the screen stays when the saved lines are erased');
  S.Free;

  S := TVtScreen.Create(4, 1);
  S.SetPenColors(DefaultColor, IndexedColor(4));
  S.EraseInLine(2);
  Found := S.GetCell(0, 3, C);
  Check(Found and (C.Chars[0] = 0) and (C.Bg.Kind = vcIndexed) and (C.Bg.Idx = 4) and (C.Fg.Kind = vcDefault),
    'erased cells take the background of the pen');
  Found := S.GetCell(0, 4, C);
  Check(not Found, 'a cell outside the screen');
  S.Free;
end;

procedure TestInsertDeleteTabs;
var
  S: TVtScreen;
begin
  S := TVtScreen.Create(6, 2);
  LoadRows(S, ['abcdef']);
  S.MoveTo(2, 0);
  S.InsertChars(2);
  ExpectRows(S, ['ab..cd', '......'], 'insert characters');
  S.DeleteChars(2);
  ExpectRows(S, ['abcd..', '......'], 'delete characters');
  S.DeleteChars(50);
  ExpectRows(S, ['ab....', '......'], 'delete beyond the line');
  S.Free;

  S := TVtScreen.Create(6, 1);
  S.PutChar($4E2D, 2);
  S.PutText('xyz');
  ExpectRows(S, ['#~xyz.'], 'wide character and text');
  S.MoveTo(1, 0);
  S.InsertChars(1);
  ExpectRows(S, ['...xyz'], 'a wide character cut by an insertion leaves no halves');
  S.Free;

  S := TVtScreen.Create(20, 1);
  S.PutText('a'#9'b');
  ExpectRows(S, ['a' + StringOfChar('.', 7) + 'b' + StringOfChar('.', 11)], 'default tab stops');
  S.MoveTo(3, 0);
  S.SetTabStop;
  S.MoveTo(0, 0);
  S.Tab(1);
  Check(S.CursorX = 3, 'a tab stop that was set');
  S.MoveTo(0, 0);
  S.Tab(2);
  Check(S.CursorX = 8, 'two tabs');
  S.MoveTo(0, 0);
  S.Tab(3);
  Check(S.CursorX = 16, 'three tabs reach the stop at 16');
  S.MoveTo(8, 0);
  S.ClearTabStop;
  S.MoveTo(0, 0);
  S.Tab(3);
  Check(S.CursorX = 19, 'a tab without a stop goes to the last column');
  S.BackTab(1);
  Check(S.CursorX = 16, 'back tab');
  S.BackTab(2);
  Check(S.CursorX = 0, 'back tab to the first column');
  S.ClearAllTabStops;
  S.MoveTo(0, 0);
  S.Tab(1);
  Check(S.CursorX = 19, 'no stops after clearing all');
  S.Free;
end;

procedure TestWideAndMarks;
var
  S: TVtScreen;
  C: TVtCell;
  Found: Boolean;
begin
  S := TVtScreen.Create(4, 2);
  S.PutText('ab');
  S.PutChar($4E2D, 2);
  ExpectRows(S, ['ab#~', '....'], 'a wide character');
  Check(S.WrapPending and (S.CursorX = 3), 'pending after a wide character at the end');
  Found := S.GetCell(0, 2, C);
  Check(Found and (C.Width = 2), 'the lead has width 2');
  Found := S.GetCell(0, 3, C);
  Check(Found and (C.Width = 0), 'the trail has width 0');
  S.Free;

  S := TVtScreen.Create(4, 2);
  S.PutText('abc');
  S.PutChar($4E2D, 2);
  ExpectRows(S, ['abc.', '#~..'], 'a wide character that does not fit wraps');
  Check(S.LineContinues(1), 'the wrap of a wide character is a continuation');
  S.MoveTo(1, 1);
  S.PutText('x');
  ExpectRows(S, ['abc.', '.x..'], 'overwriting the trail blanks the lead');
  S.MoveTo(0, 1);
  S.PutText(#$E4#$B8#$AD);
  ExpectRows(S, ['abc.', '#~..'], 'wide character from UTF-8');
  S.MoveTo(0, 1);
  S.PutText('y');
  ExpectRows(S, ['abc.', 'y...'], 'overwriting the lead blanks the trail');
  S.Free;

  S := TVtScreen.Create(4, 1);
  S.PutText('e'#$CC#$81'f');
  Found := S.GetCell(0, 0, C);
  Check(Found and (C.Chars[0] = Ord('e')) and (C.Chars[1] = $301), 'a combining character joins the cell before');
  Check((S.CursorX = 2) and (RowText(S, 0) = 'ef..'), 'the combining character takes no cell');
  S.Free;
end;

procedure TestAltAndCursor;
var
  S: TVtScreen;
  St: TerminalState;
  C: TVtCell;
  Found: Boolean;
begin
  S := TVtScreen.Create(4, 2);
  LoadRows(S, ['abcd', 'efgh']);
  S.EnableAltScreen(True);
  Check(S.AltScreen, 'alternate screen on');
  ExpectRows(S, ['....', '....'], 'the alternate screen is blank');
  S.PutText('zz');
  S.MoveTo(0, 1);
  S.LineFeed;
  Check(S.History.NumLines = 0, 'the alternate screen has no history');
  ExpectRows(S, ['....', '....'], 'scrolled alternate screen');
  St := TerminalState.Create;
  S.UpdateState(St);
  Check(St.ScrollbackChanged and not St.ScrollbackEnabled, 'the scroll bar is off in the alternate screen');
  St.Free;
  S.EnableAltScreen(False);
  ExpectRows(S, ['abcd', 'efgh'], 'the main screen comes back');
  S.MoveTo(0, 1);
  S.LineFeed;
  Check(S.History.NumLines = 1, 'the main screen has history');
  S.History.SetOffset(0);
  S.EnableAltScreen(True);
  Check(S.History.IsFollowingTerminal, 'entering the alternate screen follows the terminal');
  S.Free;

  S := TVtScreen.Create(5, 3);
  S.MoveTo(2, 1);
  S.SetPenAttrs([vaBold]);
  S.SaveCursor;
  S.MoveTo(0, 0);
  S.ResetPen;
  S.RestoreCursor;
  Check((S.CursorX = 2) and (S.CursorY = 1), 'cursor restored');
  S.PutText('q');
  Found := S.GetCell(1, 2, C);
  Check(Found and (C.Chars[0] = Ord('q')) and (C.Attrs = [vaBold]), 'pen restored');
  S.MoveBy(10, 10);
  Check((S.CursorX = 4) and (S.CursorY = 2), 'relative move stops at the edges');
  S.Free;
end;

procedure TestResize;
var
  S: TVtScreen;
begin
  S := TVtScreen.Create(4, 3);
  LoadRows(S, ['aaaa', 'bbbb', 'cccc']);
  S.MoveTo(3, 2);
  S.Resize(4, 2);
  ExpectRows(S, ['bbbb', 'cccc'], 'shrunk');
  Check((S.History.NumLines = 1) and (S.CursorY = 1), 'the top line went to the history');
  Check(S.History.LineAt(0)^.Cells[0].Chars[0] = Ord('a'), 'the line in the history');
  S.Resize(4, 3);
  ExpectRows(S, ['aaaa', 'bbbb', 'cccc'], 'grown');
  Check((S.History.NumLines = 0) and (S.CursorY = 2), 'the line came back from the history');
  S.Resize(4, 5);
  ExpectRows(S, ['aaaa', 'bbbb', 'cccc', '....', '....'], 'grown with nothing in the history');
  S.Free;

  S := TVtScreen.Create(4, 3);
  LoadRows(S, ['aaaa']);
  S.Resize(4, 1);
  ExpectRows(S, ['aaaa'], 'blank rows below the cursor go first');
  Check(S.History.NumLines = 0, 'nothing was pushed');
  S.Free;

  S := TVtScreen.Create(4, 2);
  LoadRows(S, ['abcd', 'efgh']);
  S.MoveTo(3, 1);
  S.Resize(2, 2);
  ExpectRows(S, ['ab', 'ef'], 'narrower');
  Check(S.CursorX = 1, 'cursor in the new last column');
  S.Resize(6, 2);
  ExpectRows(S, ['ab....', 'ef....'], 'wider');
  Check((S.TopMargin = 0) and (S.BottomMargin = 1), 'margins reset');
  S.Free;

  S := TVtScreen.Create(4, 2);
  LoadRows(S, ['abcd', 'efgh']);
  S.MoveTo(0, 1);
  S.LineFeed;
  S.Resize(2, 2);
  Check(S.History.LineAt(0)^.Cols = 4, 'history lines keep their width');
  S.Resize(0, 0);
  Check((S.Cols = 1) and (S.Rows = 1), 'the size is at least 1 x 1');
  S.Free;

  S := TVtScreen.Create(4, 2);
  S.PutChar($4E2D, 2);
  S.Resize(1, 2);
  Check(RowText(S, 0) = '.', 'a wide character cut by a resize leaves no half');
  S.Free;
end;

procedure TestScrollbackObject;
var
  B, B2: Scrollback;
  I: Integer;
  Fine: Boolean;
  Got: TVtCellArray;
  GotCols: Integer;
  GotCont: Boolean;
begin
  B := Scrollback.Create;
  Fine := B.PopLine(Got, GotCols, GotCont);
  Check(not Fine and (GotCols = 0), 'no line to take');
  for I := 1 to 10 do
    Fine := B.PushLine(1, LineOf(I), I = 4);
  Check(Fine and (B.NumLines = 10) and (B.Offset = 10) and B.IsFollowingTerminal, 'ten lines, following');
  Check(B.LineAt(3)^.Continuation and not B.LineAt(2)^.Continuation, 'continuation of a line');
  B.IncrementOffset(-3);
  Check(B.Offset = 7, 'three lines older');
  B.IncrementOffset(5);
  Check(B.Offset = 10, 'newer is limited by the number of lines');
  B.SetOffset(-4);
  Check(B.Offset = 0, 'offset limited below');
  B.IncrementOffset(-1);
  Check(B.Offset = 0, 'older is limited at 0');
  B.SetOffset(99);
  Check(B.Offset = 10, 'offset limited above');
  B.SetOffset(7);
  Check((B.GetVisibleScrollLines(4) = 3) and (B.GetVisibleScrollLines(2) = 2), 'visible lines with offset 7');
  B.SetOffset(3);
  Check(B.GetVisibleScrollLines(4) = 4, 'visible lines are limited by the height');
  B.FollowTerminal;
  Check(B.GetVisibleScrollLines(4) = 0, 'no visible lines when following');
  B.Free;

  B2 := Scrollback.Create;
  Fine := True;
  for I := 1 to 10000 do
    Fine := B2.PushLine(1, LineOf(I), False) and Fine;
  Check(Fine and (B2.NumLines = B2.maxSize), 'the history holds maxSize lines');
  B2.SetOffset(5);
  Fine := B2.PushLine(1, LineOf(10001), False);
  Check(not Fine and (B2.NumLines = 10000), 'the oldest line is dropped');
  Check((B2.Offset = 4) and (B2.LineAt(0)^.Cells[0].Chars[0] = 2) and (B2.LineAt(9999)^.Cells[0].Chars[0] = 10001),
    'the offset moves with the dropped line');
  B2.SetOffset(0);
  Fine := B2.PushLine(1, LineOf(10002), False);
  Check((B2.Offset = 0) and (B2.LineAt(0)^.Cells[0].Chars[0] = 3), 'the offset stays at 0');
  B2.FollowTerminal;
  Fine := B2.PushLine(1, LineOf(10003), False);
  Check(B2.Offset = 10000, 'a following offset stays at the end');
  Fine := B2.PopLine(Got, GotCols, GotCont);
  Check(Fine and (Got[0].Chars[0] = 10003) and (GotCols = 1) and (B2.NumLines = 9999) and (B2.Offset = 9999),
    'the newest line is taken');
  B2.Clear;
  Check((B2.NumLines = 0) and (B2.Offset = 0), 'cleared');
  B2.Free;
end;

procedure TestSurface;
var
  S: TVtScreen;
  St: TerminalState;
  Q: TScreenCell;
  Attr: TColorAttr;
  Want: TColor;
begin
  S := TVtScreen.Create(4, 2);
  St := TerminalState.Create;
  S.PutText('ab');
  S.UpdateState(St);
  Check((St.Surface.Size.X = 4) and (St.Surface.Size.Y = 2), 'the surface has the size of the screen');
  Check((SurfText(St, 0, 0) = 'a') and (SurfText(St, 0, 1) = 'b') and IsBlankText(SurfText(St, 0, 2)),
    'cells of the first row');
  Check((St.Surface.DamageAtRow(0)^.Start = 0) and (St.Surface.DamageAtRow(0)^.RangeEnd = 4),
    'everything is drawn after a resize of the surface');
  Check(St.CursorChanged and (St.CursorPos.X = 2) and (St.CursorPos.Y = 0), 'cursor position');
  Check(St.CursorVisible and not St.CursorBlink, 'cursor visible, not blinking');
  Check(not St.ScrollbackChanged and (St.ScrollbackLimit = 0) and (St.ScrollbackOffset = 0) and
    St.ScrollbackEnabled, 'no change of the scrollback');

  St.Surface.ClearDamage;
  St.CursorChanged := False;
  Q := TScreenCell.Create(TScreenCharacter.Create('Q'), TColorAttr.Create(7));
  St.Surface.At(0, 0)^ := Q;
  S.MoveTo(0, 1);
  S.PutText('z');
  S.UpdateState(St);
  Check(SurfText(St, 0, 0) = 'Q', 'an undamaged cell is not drawn again');
  Check(SurfText(St, 1, 0) = 'z', 'a damaged cell is drawn');
  Check(St.Surface.DamageAtRow(0)^.Size = 0, 'no damage in the first row');
  Check((St.Surface.DamageAtRow(1)^.Start = 0) and (St.Surface.DamageAtRow(1)^.RangeEnd = 1), 'damage of the second row');
  Check(St.CursorChanged and (St.CursorPos.X = 1) and (St.CursorPos.Y = 1), 'cursor moved');

  St.Surface.ClearDamage;
  St.CursorChanged := False;
  St.Surface.At(0, 1)^ := Q;
  S.UpdateState(St);
  Check((SurfText(St, 0, 1) = 'Q') and not St.CursorChanged and (St.Surface.DamageAtRow(0)^.Size = 0),
    'an update without changes draws nothing');

  S.SetCursorVisible(False);
  S.SetCursorBlink(True);
  S.MouseEnabled := True;
  S.UpdateState(St);
  Check(St.CursorChanged and not St.CursorVisible and St.CursorBlink and St.MouseEnabled, 'cursor flags and mouse');

  S.SetPenColors(IndexedColor(2), RgbColor(10, 20, 30));
  S.SetPenAttrs([vaBold, vaUnderline, vaConceal]);
  S.MoveTo(3, 0);
  S.PutText('x');
  S.UpdateState(St);
  Attr := St.Surface.At(0, 3)^.Attribute;
  Want := TColor.Create(TColorXTerm.Create(2));
  Check(Attr.GetForeground = Want, 'indexed foreground');
  Want := TColor.Create(TColorRGB.Create(10, 20, 30));
  Check(Attr.GetBackground = Want, 'RGB background');
  Check(Attr.GetStyle = (slBold or slUnderline), 'style bits');
  St.Free;
  S.Free;
end;

procedure TestHistoryOnSurface;
var
  S: TVtScreen;
  St: TerminalState;
begin
  S := WrappedScene;
  St := TerminalState.Create;
  S.UpdateState(St);
  Check((SurfText(St, 0, 0) = 'b') and (SurfText(St, 1, 2) = 'c'), 'the screen when following');
  Check(St.ScrollbackChanged and (St.ScrollbackLimit = 1) and (St.ScrollbackOffset = 1), 'limit and offset');

  S.HandleScrollbackWheel(mwUp);
  Check(S.History.Offset = 0, 'the wheel moves up');
  S.UpdateState(St);
  Check((SurfText(St, 0, 0) = 'a') and (SurfText(St, 1, 0) = 'b') and (St.ScrollbackOffset = 0),
    'a history line above the screen');

  S.HandleScrollbackWheel(mwDown);
  Check(S.History.Offset = 1, 'the wheel moves down');
  S.UpdateState(St);
  Check((SurfText(St, 0, 0) = 'b') and (SurfText(St, 1, 0) = 'c'), 'the screen again');
  S.HandleScrollbackWheel(mwLeft);
  Check(S.History.Offset = 1, 'a sideways wheel does nothing');

  S.HandleScrollbackWheel(mwUp);
  S.Resize(5, 2);
  S.UpdateState(St);
  Check(St.Surface.Size.X = 5, 'the surface follows the size');
  Check((SurfText(St, 0, 0) = 'a') and IsBlankText(SurfText(St, 0, 3)) and (SurfText(St, 1, 0) = 'b') and
    IsBlankText(SurfText(St, 1, 4)), 'a narrow history line on a wide surface');
  Check(S.History.LineAt(0)^.Cols = 3, 'the line keeps its width');
  St.Free;
  S.Free;
end;

procedure TestOverflowRedraw;
var
  S: TVtScreen;
  St: TerminalState;
  I: Integer;
  Q: TScreenCell;
begin
  S := TVtScreen.Create(2, 1);
  for I := 1 to 10000 do
    S.LineFeed;
  Check((S.History.NumLines = 10000) and S.History.IsFollowingTerminal, 'the history is full');
  S.History.SetOffset(0);
  St := TerminalState.Create;
  S.UpdateState(St);
  Q := TScreenCell.Create(TScreenCharacter.Create('Q'), TColorAttr.Create(7));
  St.Surface.At(0, 0)^ := Q;
  S.UpdateState(St);
  Check(SurfText(St, 0, 0) = 'Q', 'the shown history is not drawn again when it did not change');
  S.LineFeed;
  S.UpdateState(St);
  Check(IsBlankText(SurfText(St, 0, 0)), 'a dropped line makes the shown history draw again');
  Check((S.History.Offset = 0) and (S.History.NumLines = 10000), 'offset and size after the drop');
  St.Free;
  S.Free;
end;

procedure TestSelection;
var
  S: TVtScreen;
begin
  S := WrappedScene;
  Check(Selected(S, 0, 0, 3, 2) = 'aaabbb'#10'ccc', 'selection over the history and the screen');
  Check(Selected(S, 1, 1, 2, 2) = 'bb'#10'cc', 'selection inside the screen');
  Check(S.CopySelection(SelectionRange.Create(SelectionAnchor.Create(2, 2), SelectionAnchor.Create(1, 1))) =
    'bb'#10'cc', 'the anchors in the other order');
  Check(Selected(S, 2, -5, 1, 100) = 'aaabbb'#10'ccc', 'anchors beyond the lines');
  Check(Selected(S, 1, 0, 3, 0) = 'aa', 'part of a history line');
  Check(Selected(S, 0, 0, 0, 0) = '', 'an empty selection');
  S.Free;

  S := PlainScene;
  Check(Selected(S, 0, 0, 3, 3) = 'aaa'#10'bbb'#10'ccc'#10, 'lines of the history end with a line feed');
  Check(Selected(S, 1, 1, 3, 2) = 'bb'#10'ccc'#10, 'from the middle of a history line');
  S.Free;

  S := TVtScreen.Create(6, 2);
  S.PutText('a');
  S.MoveTo(3, 0);
  S.PutText('b');
  Check(Selected(S, 0, 0, 6, 0) = 'a  b'#10, 'erased cells before text are spaces and those after it are dropped');
  S.Free;

  S := TVtScreen.Create(4, 1);
  S.PutText('a');
  S.PutChar($4E2D, 2);
  Check(Selected(S, 0, 0, 4, 0) = 'a'#$E4#$B8#$AD, 'a wide character is written once');
  S.Free;

  S := TVtScreen.Create(4, 1);
  S.PutText('e'#$CC#$81);
  Check(Selected(S, 0, 0, 4, 0) = 'e'#$CC#$81, 'a cell with a combining character');
  S.Free;
end;

begin
  TestWrapping;
  TestScrollOffTop;
  TestRegions;
  TestErasing;
  TestInsertDeleteTabs;
  TestWideAndMarks;
  TestAltAndCursor;
  TestResize;
  TestScrollbackObject;
  TestSurface;
  TestHistoryOnSurface;
  TestOverflowRedraw;
  TestSelection;
  Done;
end.
