{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/textview.h, source/tvision/textview.cpp, source/tvision/ttprvlns.cpp,
  include/tvision/views.h (TScroller),
  include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it. The
  colors of the root are the BIOS attributes $41 and above: the entry k of its palette is $40 + k, so the entry 1
  of the palette of a scroller, which is the entry 6 of the root, gives the attribute $46. A terminal of 10 columns
  and 4 rows is at 0, 0 of the screen, with a vertical scroll bar at column 10 when the test needs one. The text is
  given to it through Do_sputn, Overflow and the stream buffer and the stream of the terminal. }
program t_textview;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  SysUtils, TvGeom, TvEvents, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvViews, TvWindow, TvStreams,
  TvTextView;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 20;
  Blank10 = '          ';

type
  TFakeDisplay = class(TScreenBackend)
  public
    CaretSize: Word;
    procedure SetCaretSize(ASize: Word); override;
    function GetCaretSize: Word; override;
  end;

  { The root of the views. }
  TRoot = class(TGroup)
  public
    function GetPalette: TPalette; override;
  end;

  { A terminal that shows its state. }
  TProbe = class(TTerminal)
  public
    function BufferSize: Word;
    function Front: Word;
    function Back: Word;
    function LimitRows: Integer;
    function LimitCols: Integer;
    function DecOf(V: Word): Word;
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  RootPal: TPalette;

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

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
end;

function TProbe.BufferSize: Word;
begin
  Result := BufSize;
end;

function TProbe.Front: Word;
begin
  Result := QueFront;
end;

function TProbe.Back: Word;
begin
  Result := QueBack;
end;

function TProbe.LimitRows: Integer;
begin
  Result := Limit.Y;
end;

function TProbe.LimitCols: Integer;
begin
  Result := Limit.X;
end;

function TProbe.DecOf(V: Word): Word;
begin
  BufDec(V);
  Result := V;
end;

{ Small helpers. }

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function CharAt(X, Y: Integer): Char;
var
  S: string;
begin
  S := ScreenCells[Y * ScrW + X].Character.GetText;
  if Length(S) > 0 then
    Result := S[1]
  else
    Result := #0;
end;

function AttrAt(X, Y: Integer): Integer;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute.ToBIOS;
end;

function RowText(Y, X0, N: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to N - 1 do
    Result := Result + CharAt(X0 + I, Y);
end;

procedure ClearScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
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

{ A root with a terminal of 10 by 4 cells at 0, 0, that holds BufSz bytes and has a vertical scroll bar when
  WithBar is set. }
procedure Scene(out Root: TRoot; out VB: TScrollBar; out T: TProbe; BufSz: Word; WithBar: Boolean);
begin
  Root := NewRoot;
  VB := nil;
  if WithBar then
  begin
    VB := TScrollBar.Create(Rc(10, 0, 11, 4));
    Root.Insert(VB);
  end;
  T := TProbe.Create(Rc(0, 0, 10, 4), nil, VB, BufSz);
  Root.Insert(T);
end;

{ Gives the text S to Do_sputn of T. }
function Put(T: TTerminal; const S: AnsiString): Integer;
var
  first: PAnsiChar;
begin
  first := nil;
  if S <> '' then
    first := @S[1];
  Result := T.Do_sputn(first, Length(S));
end;

procedure TestConstruction;
var
  T, T2: TProbe;
begin
  T := TProbe.Create(Rc(0, 0, 10, 4), nil, nil, 40000);
  Check(T.BufferSize = 32000, 'the buffer is at most 32000 bytes');
  Check(T.GrowMode = (gfGrowHiX or gfGrowHiY), 'a terminal grows at the high sides');
  Check((T.LimitRows = 1) and (T.LimitCols = 0), 'the limit of a new terminal is 0 columns and 1 row');
  Check((T.Front = 0) and (T.Back = 0), 'the queue of a new terminal is empty');
  Check(T.QueEmpty, 'QueEmpty of a new terminal');
  Check((T.State and sfCursorVis) <> 0, 'the cursor of a terminal is shown');
  Check((T.Cursor.X = 0) and (T.Cursor.Y = 0), 'the cursor starts at 0, 0');
  Check((T.Options and ofSelectable) <> 0, 'a terminal is selectable as a scroller is');
  T2 := TProbe.Create(Rc(0, 0, 10, 4), nil, nil, 100);
  Check(T2.BufferSize = 100, 'a smaller size is kept');
  TvObject.DestroyObject(T);
  TvObject.DestroyObject(T2);
end;

procedure TestBufStep;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
  V: Word;
begin
  Scene(Root, VB, T, 8, True);
  V := 6;
  T.BufInc(V);
  Check(V = 7, 'BufInc moves on');
  T.BufInc(V);
  Check(V = 0, 'BufInc goes round at the size of the buffer');
  Check(T.DecOf(0) = 7, 'BufDec of 0 goes to the last byte');
  Check(T.DecOf(5) = 4, 'BufDec moves back');
  FreeRoot(Root);
end;

procedure TestCanInsert;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
begin
  Scene(Root, VB, T, 8, True);
  Check(T.CanInsert(7), 'seven bytes fit in an empty buffer of eight');
  Check(not T.CanInsert(8), 'eight bytes do not fit in a buffer of eight');
  Put(T, 'abc');
  Check(T.CanInsert(4), 'four bytes fit after three');
  Check(not T.CanInsert(5), 'five bytes do not fit after three');
  FreeRoot(Root);
end;

procedure TestLines;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
begin
  Scene(Root, VB, T, 32, True);
  Check(Put(T, 'ab'#10'cd'#10'ef') = 8, 'eight bytes are taken');
  Check((T.Front = 8) and (T.Back = 0) and not T.QueEmpty, 'the queue holds the eight bytes');
  Check(T.LimitRows = 3, 'two line ends make three lines');
  Check(T.NextLine(0) = 3, 'NextLine of the first line');
  Check(T.NextLine(3) = 6, 'NextLine of the second line');
  Check(T.NextLine(6) = 8, 'NextLine of the last line stops at the front');
  Check(T.NextLine(8) = 8, 'NextLine at the front stays');
  Check(T.PrevLines(8, 1) = 6, 'PrevLines of one line from the end');
  Check(T.PrevLines(8, 2) = 3, 'PrevLines of two lines from the end');
  Check(T.PrevLines(8, 3) = 0, 'PrevLines of three lines reaches the back');
  Check(T.PrevLines(8, 4) = 0, 'PrevLines does not pass the back');
  Check(T.PrevLines(8, 0) = 8, 'PrevLines of no line stays');
  Check(T.PrevLines(5, 1) = 3, 'PrevLines from a line end');
  Check(T.PrevLines(5, 2) = 0, 'PrevLines of two lines from a line end');
  Check(T.PrevLines(3, 1) = 3, 'PrevLines from the start of a line gives an empty line');
  FreeRoot(Root);
end;

procedure TestNoLineEnds;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
begin
  Scene(Root, VB, T, 64, True);
  Check(Put(T, 'hello') = 5, 'Do_sputn gives the number of bytes taken');
  Check((T.Front = 5) and (T.Back = 0), 'the front moves by the count');
  Check(T.LimitRows = 1, 'text without a line end is one line');
  Check(RowText(0, 0, 10) = 'hello     ', 'the text is on the first row');
  Check(RowText(1, 0, 10) = Blank10, 'the rows below the text are blank');
  Check(RowText(3, 0, 10) = Blank10, 'the last row is blank');
  Check(AttrAt(0, 0) = $46, 'the text has the color 1 of the scroller');
  Check(AttrAt(7, 2) = $46, 'a blank row has the same color');
  Check((T.Cursor.X = 5) and (T.Cursor.Y = 0), 'the cursor is after the text');
  Check(Put(T, ' world') = 6, 'more text is taken');
  Check(RowText(0, 0, 10) = 'hello worl', 'a line is cut at the right side of the view');
  Check(T.Cursor.X = 11, 'the cursor is after the whole line');
  FreeRoot(Root);
end;

procedure TestLineEnds;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
begin
  Scene(Root, VB, T, 256, True);
  Check(Put(T, 'ab'#10'cd') = 5, 'text with a line end is taken');
  Check(T.LimitRows = 2, 'the limit counts the line end');
  Check(RowText(0, 0, 4) = 'ab  ', 'the first line');
  Check(RowText(1, 0, 4) = 'cd  ', 'the second line');
  Check((RowText(2, 0, 10) = Blank10) and (RowText(3, 0, 10) = Blank10), 'the rows after the last line are blank');
  Check((T.Cursor.X = 2) and (T.Cursor.Y = 1), 'the cursor is at the end of the last line');

  Put(T, #10);
  Check(T.LimitRows = 3, 'a line end at the end makes an empty last line');
  Check((T.Cursor.X = 0) and (T.Cursor.Y = 2), 'the cursor is on the empty last line');
  Check(RowText(1, 0, 4) = 'cd  ', 'the lines above stay');

  Put(T, 'ef'#10'gh'#10'ij'#10);
  Check(T.LimitRows = 6, 'six lines');
  Check((VB.MinVal = 0) and (VB.MaxVal = 2), 'the range of the bar is the lines beyond the view');
  Check((VB.Value = 2) and (T.Delta.Y = 2), 'the text is scrolled to its end');
  Check(RowText(0, 0, 10) = 'ef        ', 'the view shows the end: row 0');
  Check(RowText(1, 0, 4) = 'gh  ', 'the view shows the end: row 1');
  Check(RowText(2, 0, 4) = 'ij  ', 'the view shows the end: row 2');
  Check(RowText(3, 0, 10) = Blank10, 'the view shows the end: the empty last line');
  Check((T.Cursor.X = 0) and (T.Cursor.Y = 3), 'the cursor is on the last row');

  T.ScrollTo(0, 0);
  Check(T.Delta.Y = 0, 'ScrollTo moves to the top');
  Check(RowText(0, 0, 4) = 'ab  ', 'the top: row 0');
  Check(RowText(1, 0, 4) = 'cd  ', 'the top: row 1');
  Check(RowText(2, 0, 4) = 'ef  ', 'the top: row 2');
  Check(RowText(3, 0, 4) = 'gh  ', 'the top: row 3');
  Check((T.Cursor.X = -1) and (T.Cursor.Y = -1), 'the cursor is hidden when the last line is not shown');

  T.ScrollTo(0, 1);
  Check((RowText(0, 0, 4) = 'cd  ') and (RowText(3, 0, 4) = 'ij  '), 'one line down');

  T.ScrollTo(0, 50);
  Check((T.Delta.Y = 2) and (VB.Value = 2), 'a row beyond the range is the end of the range');
  Check(RowText(0, 0, 4) = 'ef  ', 'the end again');

  T.ScrollTo(0, 0);
  Put(T, 'k');
  Check(T.LimitRows = 6, 'text without a line end adds no line');
  Check(T.Delta.Y = 2, 'new text scrolls to the end');
  Check(RowText(3, 0, 4) = 'k   ', 'the new text is on the last row');
  Check((T.Cursor.X = 1) and (T.Cursor.Y = 3), 'the cursor follows the new text');
  FreeRoot(Root);
end;

procedure TestScrollLimits;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
begin
  Scene(Root, VB, T, 256, True);
  Put(T, 'l0'#10'l1'#10'l2'#10'l3'#10'l4'#10'l5'#10'l6'#10'l7'#10);
  Check(T.LimitRows = 9, 'nine lines');
  Check((VB.MaxVal = 5) and (VB.Value = 5) and (T.Delta.Y = 5), 'the bar is at the end of its range');
  Check(VB.PgStep = 3, 'the page step is the height less one');
  Check((RowText(0, 0, 2) = 'l5') and (RowText(1, 0, 2) = 'l6') and (RowText(2, 0, 2) = 'l7'), 'the last lines');
  Check(RowText(3, 0, 10) = Blank10, 'the empty last line');

  T.ScrollTo(0, 0);
  Check((RowText(0, 0, 2) = 'l0') and (RowText(1, 0, 2) = 'l1') and (RowText(2, 0, 2) = 'l2') and
    (RowText(3, 0, 2) = 'l3'), 'the first lines');

  T.ScrollTo(0, 100);
  Check((T.Delta.Y = 5) and (RowText(0, 0, 2) = 'l5'), 'a row beyond the range is the end');

  T.ScrollTo(0, -4);
  Check((T.Delta.Y = 0) and (RowText(0, 0, 2) = 'l0'), 'a row before the range is the start');

  T.ScrollTo(0, 3);
  Check((RowText(0, 0, 2) = 'l3') and (RowText(3, 0, 2) = 'l6'), 'a middle position');

  Put(T, 'z');
  Check((VB.Value = 5) and (RowText(3, 0, 4) = 'z   ') and (RowText(0, 0, 2) = 'l5'), 'new text goes to the end');

  VB.SetValue(1);
  Check((T.Delta.Y = 1) and (RowText(0, 0, 2) = 'l1') and (RowText(3, 0, 2) = 'l4'), 'the bar moves the view');
  FreeRoot(Root);
end;

procedure TestWithoutBar;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
begin
  Scene(Root, VB, T, 256, False);
  Check(Put(T, 'a'#10'b'#10'c'#10'd'#10'e'#10) = 10, 'ten bytes');
  Check(T.LimitRows = 6, 'six lines');
  Check(T.Delta.Y = 0, 'a terminal without a bar does not scroll');
  Check((RowText(0, 0, 1) = 'a') and (RowText(1, 0, 1) = 'b') and (RowText(2, 0, 1) = 'c') and
    (RowText(3, 0, 1) = 'd'), 'the first lines stay in view');
  Put(T, 'f');
  Check((T.Delta.Y = 0) and (RowText(3, 0, 1) = 'd'), 'more text does not move the view');
  FreeRoot(Root);
end;

procedure TestWrap;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
begin
  Scene(Root, VB, T, 8, True);
  Put(T, 'ab'#10);
  Check((T.Front = 3) and (T.Back = 0) and (T.LimitRows = 2), 'the first line');
  Put(T, 'cd'#10);
  Check((T.Front = 6) and (T.Back = 0) and (T.LimitRows = 3), 'the second line');
  Check(Put(T, 'ef'#10) = 3, 'the third line is taken');
  Check((T.Front = 1) and (T.Back = 3), 'the front wraps and the oldest line is dropped');
  Check(T.LimitRows = 3, 'the dropped line is not counted');
  Check(not T.QueEmpty, 'the queue is not empty');
  Check((RowText(0, 0, 4) = 'cd  ') and (RowText(1, 0, 4) = 'ef  '), 'the lines across the end of the buffer');
  Check(RowText(2, 0, 10) = Blank10, 'the empty last line');
  Check((T.Cursor.X = 0) and (T.Cursor.Y = 2), 'the cursor is on the empty last line');

  Put(T, 'gh');
  Check((T.Front = 3) and (T.Back = 6) and (T.LimitRows = 2), 'a line is dropped for text without a line end');
  Check(RowText(0, 0, 4) = 'ef  ', 'the line that ends across the end of the buffer');
  Check(RowText(1, 0, 4) = 'gh  ', 'the new text');
  Check((T.Cursor.X = 2) and (T.Cursor.Y = 1), 'the cursor after the new text');
  FreeRoot(Root);
end;

procedure TestLongText;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
  Long: AnsiString;
  Row: string;
  I: Integer;
begin
  Scene(Root, VB, T, 8, True);
  Check(Put(T, '0123456789') = 7, 'text longer than the buffer keeps its last seven bytes');
  Check((T.Front = 7) and (T.Back = 0), 'the queue after the long text');
  Check(RowText(0, 0, 7) = '3456789', 'the last bytes are shown');
  FreeRoot(Root);

  Scene(Root, VB, T, 1000, True);
  Long := '';
  for I := 0 to 299 do
    Long := Long + Chr(48 + I mod 10);
  Check(Put(T, Long) = 300, 'a line longer than a piece of the drawing is taken');
  Row := RowText(0, 0, 10);
  Check(Row = '0123456789', 'a long line is drawn from its start');
  Put(T, #10'xy');
  Check((RowText(0, 0, 10) = '0123456789') and (RowText(1, 0, 2) = 'xy'), 'the line after a long line');
  FreeRoot(Root);

  Scene(Root, VB, T, 64, True);
  Put(T, #$C3#$A9'a');
  Check((CharAt(0, 0) = #$C3) and (CharAt(1, 0) = 'a'), 'a two byte character is one cell');
  FreeRoot(Root);
end;

procedure TestStream;
var
  Root: TRoot;
  VB: TScrollBar;
  T: TProbe;
  S: otstream;
  Txt: string;
begin
  Scene(Root, VB, T, 64, True);
  S := otstream.Create(T);
  Check(S.Rdbuf = T.StreamBuf, 'the stream is on the buffer of the terminal');

  S.Put(AnsiChar('q'));
  Check((T.Front = 1) and (RowText(0, 0, 3) = 'q  '), 'one character through the stream');

  Txt := 'ab'#10'cd';
  S.WriteBytes(Txt[1], Length(Txt));
  Check((T.Front = 6) and (T.LimitRows = 2), 'a block through the stream');
  Check((RowText(0, 0, 3) = 'qab') and (RowText(1, 0, 2) = 'cd'), 'the block is drawn');

  Check(T.Overflow(Ord('x')) = 1, 'Overflow gives 1');
  Check((T.Front = 7) and (RowText(1, 0, 3) = 'cdx'), 'Overflow takes the character');
  Check(T.Overflow(-1) = 1, 'Overflow of EOF gives 1');
  Check(T.Front = 7, 'Overflow of EOF takes nothing');

  Check(T.StreamBuf.SPutN(Txt[1], Length(Txt)) = 5, 'the buffer takes a block');
  Check((T.Front = 12) and (T.LimitRows = 3), 'the block reaches Do_sputn at once');
  Check((RowText(1, 0, 5) = 'cdxab') and (RowText(2, 0, 2) = 'cd'), 'the block is drawn after the text');
  Check(T.StreamBuf.SPutC(Ord('!')) = 33, 'SPutC gives the byte');
  Check(RowText(2, 0, 3) = 'cd!', 'the byte is drawn');
  TvObject.DestroyObject(S);
  FreeRoot(Root);
end;

var
  SavedBackend: TScreenBackend;

begin
  RootPal := TPalette.Create(#$41#$42#$43#$44#$45#$46#$47#$48#$49#$4A#$4B#$4C#$4D#$4E#$4F#$50 +
    #$51#$52#$53#$54#$55#$56#$57#$58#$59#$5A#$5B#$5C#$5D#$5E#$5F#$60, 32);

  Fake := TFakeDisplay.Create;
  SavedBackend := TDisplay.Backend;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;

  TestConstruction;
  TestBufStep;
  TestCanInsert;
  TestLines;
  TestNoLineEnds;
  TestLineEnds;
  TestScrollLimits;
  TestWithoutBar;
  TestWrap;
  TestLongText;
  TestStream;

  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  RootPal.Free;
  Done;
end.
