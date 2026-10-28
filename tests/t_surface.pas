{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/surface.h, source/tvision/tsurface.cpp, include/tvision/views.h,
  include/tvision/scrncell.h, include/tvision/ttypes.h, include/tvision/tv.h, include/tvision/config.h
  See COPYRIGHT.magiblot.

  The display is a screen of 40 by 20 cells in memory; the root of the views is a group that writes into it. The
  palette of the root has the entries $1E and $2F, so the empty area of a surface view has the attribute $1E. The
  cells of the test surfaces hold the character with the code 65 + 10 * row + column and the attribute $30 + row. }
program t_surface;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses cthreads, SysUtils, TvSurface, TvViews, TvObjs, TvScreen, TvSys, TvEvents, TvDrawBuf, TvCell, TvColors, TvGeom;

{$I testlib.inc}

const
  ScrW = 5 * 8;
  ScrH = ScrW div 2;
  ViewW = ScrW div 6;
  ViewH = ScrH div 6;
  ViewX = ViewH - 1;
  ViewY = ViewX - 1;

var
  WriteCount: Integer;
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;

procedure OnCaret(X, Y: Integer);
begin
end;

procedure OnScreenWrite(X, Y: Integer; Buf: PScreenCell; Count: Integer);
begin
  Inc(WriteCount);
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

{ The attribute of the empty area: the first entry of the palette of the root. }
function Blank: Integer;
begin
  Result := $1E;
end;

type
  { A display that only remembers the size of the caret. }
  TFakeDisplay = class(TScreenBackend)
  private
    FCaret: Word;
  public
    function GetCaretSize: Word; override;
    procedure SetCaretSize(ASize: Word); override;
    property Caret: Word read FCaret;
  end;

  { The root group: it takes the palette from a class variable and builds itself at the size of the screen. }
  TRoot = class(TGroup)
  public
    class var Pal: TPalette;
    constructor Make;
    function GetPalette: TPalette; override;
  end;

var
  Fake: TFakeDisplay;

procedure TFakeDisplay.SetCaretSize(ASize: Word);
begin
  FCaret := ASize;
end;

function TFakeDisplay.GetCaretSize: Word;
begin
  Result := FCaret;
end;

constructor TRoot.Make;
begin
  inherited Create(Rc(0, 0, ScrW, ScrH));
end;

function TRoot.GetPalette: TPalette;
begin
  Result := Pal;
end;

{ The cell that the test surfaces hold at the row Row and the column Col. }
function PatternCell(Row, Col: Integer): TScreenCell;
begin
  Result := TScreenCell.Create(TScreenCharacter.Create(Chr(65 + 10 * Row + Col)), TColorAttr.Create($30 + Row));
end;

procedure FillPattern(S: TDrawSurface);
var
  Row, Col: Integer;
begin
  for Row := 0 to S.Size.Y - 1 do
    for Col := 0 to S.Size.X - 1 do
      S.At(Row, Col)^ := PatternCell(Row, Col);
end;

function AllZero(S: TDrawSurface): Boolean;
var
  Zero: TScreenCell;
  Row, Col: Integer;
begin
  FillChar(Zero, SizeOf(Zero), 0);
  Result := True;
  for Row := 0 to S.Size.Y - 1 do
    for Col := 0 to S.Size.X - 1 do
      if S.At(Row, Col)^ <> Zero then
        Result := False;
end;

function CharAt(X, Y: Integer): Char;
var
  Txt: string;
begin
  Txt := ScreenCells[Y * ScrW + X].Character.GetText;
  if Length(Txt) > 0 then
    Result := Txt[1]
  else
    Result := #0;
end;

function AttrAt(X, Y: Integer): TColorAttr;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute;
end;

{ The characters of the row Y of the view, as text. }
function ViewRow(Y: Integer): string;
var
  X: Integer;
begin
  Result := '';
  for X := 0 to ViewW - 1 do
    Result := Result + CharAt(ViewX + X, ViewY + Y);
end;

function ViewAttr(X, Y: Integer): TColorAttr;
begin
  Result := AttrAt(ViewX + X, ViewY + Y);
end;

{ Tells whether the screen is zero everywhere except at the cells of the view. }
function OutsideIsClear: Boolean;
var
  X, Y: Integer;
  Inside: Boolean;
begin
  Result := True;
  for Y := 0 to ScrH - 1 do
    for X := 0 to ScrW - 1 do
    begin
      Inside := (X >= ViewX) and (X < ViewX + ViewW) and (Y >= ViewY) and (Y < ViewY + ViewH);
      if (not Inside) and (ScreenCells[Y * ScrW + X].Character.GetText <> #0) then
        Result := False;
    end;
end;

function ViewIsClear: Boolean;
begin
  Result := (ViewRow(0) = StringOfChar(#0, ViewW)) and (ViewRow(1) = StringOfChar(#0, ViewW)) and
    (ViewRow(2) = StringOfChar(#0, ViewW));
end;

function NewRoot: TRoot;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
  Result := TRoot.Make;
  Result.Options := Result.Options and not ofBuffered;
  Result.Buffer := @ScreenCells[0];
  Result.State := Result.State or sfSelected;
  Result.SetState(sfExposed, True);
end;

procedure FreeRoot(R: TRoot);
begin
  TvObject.DestroyObject(R);
end;

procedure ClearScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
end;

{ ---- the tests ---- }

procedure TestCreate;
var
  S: TDrawSurface;
begin
  S := TDrawSurface.Create;
  Check((S.Size.X = 0) and (S.Size.Y = 0), 'a surface made with no size is empty');
  S.Clear;
  Check(True, 'Clear of a surface with no cells does nothing');
  S.Free;

  S := TDrawSurface.Create(Pt(3, 2));
  Check((S.Size.X = 3) and (S.Size.Y = 2), 'a surface made with a size has that size');
  Check(AllZero(S), 'the cells of a new surface are zero');
  S.Free;

  S := TDrawSurface.Create(Pt(0, 4));
  Check((S.Size.X = 0) and (S.Size.Y = 4), 'a size with a zero side is kept as it is');
  S.Free;
  S := TDrawSurface.Create(Pt(-2, -3));
  Check((S.Size.X = -2) and (S.Size.Y = -3), 'a negative size is kept as it is');
  S.Free;
end;

procedure TestAt;
var
  S: TDrawSurface;
  Row, Col: Integer;
  Ok: Boolean;
  Step: PtrUInt;
begin
  S := TDrawSurface.Create(Pt(4, 3));
  FillPattern(S);
  Check(S.At(0, 0)^.Character.GetText = 'A', 'At(0, 0)');
  Check(S.At(1, 2)^.Character.GetText = 'M', 'At(1, 2) is the cell of the row 1 and the column 2');
  Check(S.At(2, 3)^.Character.GetText = 'X', 'At(2, 3) is the last cell');
  Check(S.At(1, 2)^.Attribute = $31, 'the attribute of a cell');
  Step := PtrUInt(S.At(1, 0)) - PtrUInt(S.At(0, 0));
  Check(Step = 4 * SizeOf(TScreenCell), 'the rows follow each other, as many cells as the width apart');
  Step := PtrUInt(S.At(0, 3)) - PtrUInt(S.At(0, 0));
  Check(Step = 3 * SizeOf(TScreenCell), 'the columns of a row follow each other');
  Ok := True;
  for Row := 0 to 2 do
    for Col := 0 to 3 do
      if S.At(Row, Col)^ <> PatternCell(Row, Col) then
        Ok := False;
  Check(Ok, 'every cell keeps what was written to it');
  S.At(1, 1)^ := PatternCell(2, 2);
  Check((S.At(1, 1)^ = PatternCell(2, 2)) and (S.At(1, 2)^ = PatternCell(1, 2)) and (S.At(0, 1)^ = PatternCell(0, 1)),
    'writing a cell changes that cell only');
  S.Free;
end;

procedure TestClear;
var
  S: TDrawSurface;
begin
  S := TDrawSurface.Create(Pt(5, 2));
  FillPattern(S);
  Check(not AllZero(S), 'the filled surface is not zero');
  S.Clear;
  Check(AllZero(S), 'Clear makes all cells zero');
  Check((S.Size.X = 5) and (S.Size.Y = 2), 'Clear keeps the size');
  S.Free;
end;

procedure TestResize;
var
  S: TDrawSurface;
begin
  S := TDrawSurface.Create(Pt(4, 3));
  FillPattern(S);
  S.Resize(Pt(4, 3));
  Check((S.Size.X = 4) and (S.Size.Y = 3), 'Resize to the same size keeps the size');
  Check(AllZero(S), 'Resize to the same size clears the cells');

  FillPattern(S);
  S.Resize(Pt(2, 2));
  Check((S.Size.X = 2) and (S.Size.Y = 2), 'Resize to a smaller size');
  Check(AllZero(S), 'Resize to a smaller size clears the cells');

  FillPattern(S);
  S.Resize(Pt(7, 5));
  Check((S.Size.X = 7) and (S.Size.Y = 5), 'Resize to a larger size');
  Check(AllZero(S), 'Resize to a larger size clears the cells');
  S.At(4, 6)^ := PatternCell(1, 1);
  Check(S.At(4, 6)^ = PatternCell(1, 1), 'the last cell of the larger surface can be written');

  S.Resize(Pt(3, 3));
  S.At(2, 2)^ := PatternCell(2, 2);
  S.Resize(Pt(9, 1));
  Check((S.Size.X = 9) and (S.Size.Y = 1) and AllZero(S), 'a size with more cells in a different shape');

  FillPattern(S);
  S.Resize(Pt(0, 3));
  Check((S.Size.X = 0) and (S.Size.Y = 3), 'Resize with a zero width sets the size as it is');
  S.Clear;
  Check(True, 'Clear after a resize to no cells does nothing');
  S.Resize(Pt(3, 2));
  Check((S.Size.X = 3) and (S.Size.Y = 2) and AllZero(S), 'Resize to cells again after none');
  FillPattern(S);
  S.Resize(Pt(2, -1));
  Check((S.Size.X = 2) and (S.Size.Y = -1), 'Resize with a negative height sets the size as it is');
  S.Resize(Pt(2, 2));
  Check(AllZero(S), 'Resize back to cells gives zero cells');
  S.Free;
end;

procedure TestGrow;
var
  S: TDrawSurface;
begin
  S := TDrawSurface.Create(Pt(4, 3));
  FillPattern(S);
  S.Grow(Pt(1, 2));
  Check((S.Size.X = 5) and (S.Size.Y = 5), 'Grow adds the delta to the size');
  Check(AllZero(S), 'Grow clears the cells');
  S.Grow(Pt(-3, -4));
  Check((S.Size.X = 2) and (S.Size.Y = 1), 'Grow with a negative delta makes the surface smaller');
  FillPattern(S);
  S.Grow(Pt(0, 0));
  Check((S.Size.X = 2) and (S.Size.Y = 1) and AllZero(S), 'Grow by nothing clears the cells');
  S.Grow(Pt(-2, 0));
  Check((S.Size.X = 0) and (S.Size.Y = 1), 'Grow to a zero width');
  S.Free;
end;

procedure TestViewBasics;
var
  Root: TRoot;
  V: TSurfaceView;
  S: TDrawSurface;
begin
  Root := NewRoot;
  S := TDrawSurface.Create(Pt(2, 2));
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH));
  Check(V.Surface = nil, 'a surface view has no surface by default');
  Check((V.Delta.X = 0) and (V.Delta.Y = 0), 'the delta of a new surface view is zero');
  Check((V.Size.X = ViewW) and (V.Size.Y = ViewH), 'the size of the view comes from its bounds');
  TvObject.DestroyObject(V);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH), S);
  Check(V.Surface = S, 'the surface of the constructor is the surface of the view');
  Check((V.Delta.X = 0) and (V.Delta.Y = 0), 'the delta is zero with a surface too');
  Check((V.GetPalette.Data[0] = 1) and (V.GetPalette.Data[1] = 1), 'the palette has the one entry 1');
  Root.Insert(V);
  Check(V.MapColor(1) = Blank, 'the entry 1 is the color 1 of the owner');
  Check(V.GetPalette = V.GetPalette, 'the palette is one object');
  FreeRoot(Root);
  S.Free;
end;

procedure TestNoSurface;
var
  Root: TRoot;
  V: TSurfaceView;
  X, Y: Integer;
  Ok: Boolean;
begin
  Root := NewRoot;
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH));
  Root.Insert(V);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = '      ') and (ViewRow(1) = '      ') and (ViewRow(2) = '      '),
    'with no surface the view shows blanks');
  Ok := True;
  for Y := 0 to ViewH - 1 do
    for X := 0 to ViewW - 1 do
      if ViewAttr(X, Y) <> Blank then
        Ok := False;
  Check(Ok, 'the blanks have the attribute of the entry 1');
  Check(OutsideIsClear, 'nothing is written outside the view');
  FreeRoot(Root);
end;

procedure TestFullCover;
var
  Root: TRoot;
  V: TSurfaceView;
  S: TDrawSurface;
begin
  Root := NewRoot;
  S := TDrawSurface.Create(Pt(6, 3));
  FillPattern(S);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH), S);
  Root.Insert(V);

  ClearScreen;
  WriteCount := 0;
  V.DrawView;
  Check((ViewRow(0) = 'ABCDEF') and (ViewRow(1) = 'KLMNOP') and (ViewRow(2) = 'UVWXYZ'),
    'a surface of the size of the view is shown as it is');
  Check((ViewAttr(0, 0) = $30) and (ViewAttr(5, 0) = $30) and (ViewAttr(3, 1) = $31) and (ViewAttr(5, 2) = $32),
    'the attributes of the cells are shown');
  Check(OutsideIsClear, 'nothing is written outside the view');
  Check(WriteCount > 0, 'the cells are written to the screen of the stage');

  S.At(1, 3)^ := PatternCell(0, 7);
  ClearScreen;
  V.DrawView;
  Check(ViewRow(1) = 'KLMHOP', 'a change of the surface shows in the next draw');

  FreeRoot(Root);
  S.Free;
end;

procedure TestLargerSurface;
var
  Root: TRoot;
  V: TSurfaceView;
  S: TDrawSurface;
begin
  Root := NewRoot;
  S := TDrawSurface.Create(Pt(8, 5));
  FillPattern(S);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH), S);
  Root.Insert(V);

  V.Delta := Pt(1, 1);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = 'LMNOPQ') and (ViewRow(1) = 'VWXYZ[') and (ViewRow(2) = '`abcde'),
    'a surface larger than the view is shown from the delta');
  Check((ViewAttr(0, 0) = $31) and (ViewAttr(0, 2) = $33), 'the attributes follow the delta');
  Check(OutsideIsClear, 'nothing is written outside the view');

  V.Delta := Pt(0, 0);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = 'ABCDEF') and (ViewRow(2) = 'UVWXYZ'), 'the part at the origin of a larger surface');

  V.Delta := Pt(2, 2);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = 'WXYZ[\') and (ViewRow(2) = 'klmnop'), 'the part at the end of a larger surface');
  FreeRoot(Root);
  S.Free;

  Root := NewRoot;
  S := TDrawSurface.Create(Pt(6, 5));
  FillPattern(S);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH), S);
  Root.Insert(V);
  V.Delta := Pt(0, 2);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = 'UVWXYZ') and (ViewRow(1) = '_`abcd') and (ViewRow(2) = 'ijklmn'),
    'a surface that is as wide as the view and higher is shown from the row of the delta');
  FreeRoot(Root);
  S.Free;
end;

procedure TestSmallerSurface;
var
  Root: TRoot;
  V: TSurfaceView;
  S: TDrawSurface;
  X, Y: Integer;
  Ok: Boolean;
begin
  Root := NewRoot;
  S := TDrawSurface.Create(Pt(3, 2));
  FillPattern(S);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH), S);
  Root.Insert(V);

  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = 'ABC   ') and (ViewRow(1) = 'KLM   ') and (ViewRow(2) = '      '),
    'a smaller surface is shown at the origin and the rest is blank');
  Ok := (ViewAttr(0, 0) = $30) and (ViewAttr(2, 0) = $30) and (ViewAttr(0, 1) = $31) and (ViewAttr(2, 1) = $31);
  Check(Ok, 'the cells of the surface keep their attributes');
  Ok := True;
  for Y := 0 to 2 do
    for X := 0 to 5 do
      if ((Y >= 2) or (X >= 3)) and (ViewAttr(X, Y) <> Blank) then
        Ok := False;
  Check(Ok, 'the blank area has the attribute of the entry 1');
  Check(OutsideIsClear, 'nothing is written outside the view');

  V.Delta := Pt(-2, -1);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = '      ') and (ViewRow(1) = '  ABC ') and (ViewRow(2) = '  KLM '),
    'a negative delta moves the surface inside the view');
  Check((ViewAttr(2, 1) = $30) and (ViewAttr(4, 2) = $31) and (ViewAttr(0, 1) = Blank) and (ViewAttr(5, 1) = Blank)
    and (ViewAttr(3, 0) = Blank), 'the attributes with a negative delta');

  V.Delta := Pt(0, -2);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = '      ') and (ViewRow(1) = '      ') and (ViewRow(2) = 'ABC   '),
    'a negative vertical delta only');

  V.Delta := Pt(5, 0);
  ClearScreen;
  V.DrawView;
  Check(ViewIsClear, 'a surface that is out of the view on the left writes nothing');

  V.Delta := Pt(0, 4);
  ClearScreen;
  V.DrawView;
  Check(ViewIsClear, 'a surface that is above the view writes nothing');

  V.Delta := Pt(-6, 0);
  ClearScreen;
  V.DrawView;
  Check(ViewIsClear, 'a surface that is out of the view on the right writes nothing');

  V.Delta := Pt(0, -3);
  ClearScreen;
  V.DrawView;
  Check(ViewIsClear, 'a surface that is below the view writes nothing');
  FreeRoot(Root);
  S.Free;
end;

procedure TestPartialColumns;
var
  Root: TRoot;
  V: TSurfaceView;
  S: TDrawSurface;
begin
  Root := NewRoot;
  S := TDrawSurface.Create(Pt(6, 3));
  FillPattern(S);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH), S);
  Root.Insert(V);
  V.Delta := Pt(2, 0);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = 'CDEF  ') and (ViewRow(1) = 'MNOP  ') and (ViewRow(2) = 'WXYZ  '),
    'the columns from the delta are shown at the left, the rest is blank');
  Check((ViewAttr(3, 2) = $32) and (ViewAttr(4, 2) = Blank) and (ViewAttr(5, 0) = Blank),
    'the attributes of a shifted surface');
  FreeRoot(Root);
  S.Free;

  Root := NewRoot;
  S := TDrawSurface.Create(Pt(8, 2));
  FillPattern(S);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH), S);
  Root.Insert(V);
  V.Delta := Pt(1, 0);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = 'BCDEFG') and (ViewRow(1) = 'LMNOPQ') and (ViewRow(2) = '      '),
    'a surface that is wider and lower than the view is copied row by row');
  Check((ViewAttr(0, 1) = $31) and (ViewAttr(0, 2) = Blank), 'the attributes of the rows of a wider surface');
  FreeRoot(Root);
  S.Free;
end;

procedure TestChangedSurface;
var
  Root: TRoot;
  V: TSurfaceView;
  S: TDrawSurface;
begin
  Root := NewRoot;
  S := TDrawSurface.Create(Pt(6, 3));
  FillPattern(S);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX + ViewW, ViewY + ViewH), S);
  Root.Insert(V);

  S.Resize(Pt(2, 1));
  S.At(0, 0)^ := PatternCell(0, 0);
  S.At(0, 1)^ := PatternCell(0, 1);
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = 'AB    ') and (ViewRow(1) = '      ') and (ViewRow(2) = '      '),
    'a surface that is resized is shown with its new size');

  S.Clear;
  ClearScreen;
  V.DrawView;
  Check((CharAt(ViewX, ViewY) = #0) and (CharAt(ViewX + 1, ViewY) = #0) and (CharAt(ViewX + 2, ViewY) = ' '),
    'a cleared surface shows its zero cells');

  S.Resize(Pt(0, 0));
  ClearScreen;
  V.DrawView;
  Check(ViewIsClear, 'a surface with no cells writes nothing');

  V.Surface := nil;
  ClearScreen;
  V.DrawView;
  Check((ViewRow(0) = '      ') and (ViewAttr(1, 1) = Blank), 'taking the surface away shows blanks');
  FreeRoot(Root);
  S.Free;
end;

procedure TestEmptyView;
var
  Root: TRoot;
  V: TSurfaceView;
  S: TDrawSurface;
begin
  Root := NewRoot;
  S := TDrawSurface.Create(Pt(3, 3));
  FillPattern(S);
  V := TSurfaceView.Create(Rc(ViewX, ViewY, ViewX, ViewY + ViewH), S);
  Root.Insert(V);
  ClearScreen;
  V.Draw;
  Check(OutsideIsClear and ViewIsClear, 'a view with no width writes nothing');
  V.Surface := nil;
  V.Draw;
  Check(OutsideIsClear and ViewIsClear, 'a view with no width and no surface writes nothing');
  FreeRoot(Root);
  S.Free;
end;

var
  SavedBackend: TScreenBackend;

begin
  TRoot.Pal := TPalette.Create([TColorAttr.Create($1E), TColorAttr.Create($2F)]);
  Fake := TFakeDisplay.Create;
  SavedBackend := TDisplay.Backend;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;

  TestCreate;
  TestAt;
  TestClear;
  TestResize;
  TestGrow;
  TestViewBasics;
  TestNoSurface;
  TestFullCover;
  TestLargerSurface;
  TestSmallerSurface;
  TestPartialColumns;
  TestChangedSurface;
  TestEmptyView;

  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := SavedBackend;
  Fake.Free;
  TRoot.Pal.Free;
  Done;
end.
