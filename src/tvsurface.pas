{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/surface.h, source/tvision/tsurface.cpp, include/tvision/views.h,
  include/tvision/scrncell.h, include/tvision/ttypes.h, include/tvision/tv.h, include/tvision/config.h
  See COPYRIGHT.magiblot.

  A TDrawSurface is a block of Size.X * Size.Y screen cells, row after row. Resize gives every cell the zero value
  and sets Size to its argument, also when a side is not positive; then the surface has no cells. At gives a pointer
  to the cell, because a Pascal function has no reference result: S.At(Y, X)^ reads and writes the cell. There is no
  bounds checking. A memory failure raises the exception of the run-time library.

  A TSurfaceView shows the part of its surface that starts at Delta. The cells that the surface does not cover are
  blanks with the attribute of the palette entry 1; when no part of the surface is in view nothing is written.
  The views are used by the thread of the user interface only. The members read, write, build and streamableName
  are not translated. }
unit TvSurface;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvColors, TvCell, TvDrawBuf, TvViews;

type
  { A two-dimensional buffer of screen cells that can be written freely. }
  TDrawSurface = class
  private
    DataLength: SizeUInt;
    Data: PScreenCell;
  public
    Size: TPoint;
    constructor Create; overload;
    constructor Create(const ASize: TPoint); overload;
    destructor Destroy; override;
    { Sets the size and clears all cells; the old contents are not kept. }
    procedure Resize(const ASize: TPoint);
    procedure Grow(const ADelta: TPoint);
    procedure Clear;
    { The address of the cell in the row Y and the column X. }
    function At(Y, X: Integer): PScreenCell;
  end;

  { Shows the region of a surface between Delta and Delta + Size. The palette has one entry, 1 = the empty area. }
  TSurfaceView = class(TView)
  private
    procedure PutRows(First: PScreenCell; FromY, ToY: Integer);
    procedure ShowSurface(Line: PScreenCell; const Blank: TColorAttr);
  public
    Surface: TDrawSurface;
    Delta: TPoint;
    constructor Create(const Bounds: TRect; ASurface: TDrawSurface = nil);
    procedure Draw; override;
    function GetPalette: TPalette; override;
  end;

implementation

const
  cpSurfaceView: string = #1;

var
  SurfaceViewPalette: TPalette;

{ A value that is at least zero. }
function NotBelowZero(V: Integer): Integer;
begin
  if V < 0 then
    Result := 0
  else
    Result := V;
end;

{ Sets Len cells of Cells to a space with the attribute Attr. }
procedure FillWithSpaces(Cells: PScreenCell; Len: Integer; const Attr: TColorAttr);
var
  Blank: TScreenCell;
  K: Integer;
begin
  Blank := TScreenCell.Create(TScreenCharacter.Create(' '), Attr);
  for K := 0 to Len - 1 do
    Cells[K] := Blank;
end;

{ TDrawSurface }

constructor TDrawSurface.Create;
begin
  inherited Create;
  DataLength := 0;
  Data := nil;
  Size.X := 0;
  Size.Y := 0;
end;

constructor TDrawSurface.Create(const ASize: TPoint);
begin
  inherited Create;
  DataLength := 0;
  Data := nil;
  Resize(ASize);
end;

destructor TDrawSurface.Destroy;
begin
  if Data <> nil then
    FreeMem(Data);
  inherited Destroy;
end;

procedure TDrawSurface.Resize(const ASize: TPoint);
var
  NewLength, Bytes: SizeUInt;
  Raw: Pointer;
begin
  if (ASize.X > 0) and (ASize.Y > 0) then
  begin
    NewLength := SizeUInt(ASize.X) * SizeUInt(ASize.Y);
    Bytes := NewLength * SizeOf(TScreenCell);
    if NewLength <= DataLength then
    begin
      Raw := Data;
      Raw := ReAllocMem(Raw, Bytes);
      Data := PScreenCell(Raw);
    end
    else
    begin
      if Data <> nil then
        FreeMem(Data);
      GetMem(Data, Bytes);
    end;
    DataLength := NewLength;
    FillChar(Data^, Bytes, 0);
  end
  else
  begin
    if Data <> nil then
      FreeMem(Data);
    Data := nil;
    DataLength := 0;
  end;
  Size := ASize;
end;

procedure TDrawSurface.Grow(const ADelta: TPoint);
var
  Wanted: TPoint;
begin
  Wanted := Size + ADelta;
  Resize(Wanted);
end;

procedure TDrawSurface.Clear;
begin
  if Data <> nil then
    FillChar(Data^, DataLength * SizeOf(TScreenCell), 0);
end;

function TDrawSurface.At(Y, X: Integer): PScreenCell;
begin
  Result := Data + (Y * Size.X + X);
end;

{ TSurfaceView }

constructor TSurfaceView.Create(const Bounds: TRect; ASurface: TDrawSurface);
begin
  inherited Create(Bounds);
  Surface := ASurface;
  Delta.X := 0;
  Delta.Y := 0;
end;

{ Writes the rows FromY to ToY - 1 of the view, one row of the view width each, taking the cells from First and
  stepping by the width of the surface. }
procedure TSurfaceView.PutRows(First: PScreenCell; FromY, ToY: Integer);
var
  Y: Integer;
begin
  Y := FromY;
  while Y < ToY do
  begin
    WriteBuf(0, Y, Size.X, 1, First + (Y - FromY) * Surface.Size.X);
    Y := Y + 1;
  end;
end;

procedure TSurfaceView.ShowSurface(Line: PScreenCell; const Blank: TColorAttr);
var
  Whole, Covered: TRect;
  First: PScreenCell;
  Y, Span: Integer;
begin
  Whole := TRect.Create(0, 0, Size.X, Size.Y);
  { The part of the extent of the view that the surface covers. }
  Covered := TRect.Create(0, 0, Surface.Size.X, Surface.Size.Y);
  Covered.Move(-Delta.X, -Delta.Y);
  Covered.Intersect(Whole);
  if (Covered.A.X < 0) or (Covered.A.X >= Covered.B.X) then
    Exit;
  if (Covered.A.Y < 0) or (Covered.A.Y >= Covered.B.Y) then
    Exit;
  First := Surface.At(NotBelowZero(Delta.Y), NotBelowZero(Delta.X));
  if Covered = Whole then
    PutRows(First, 0, Size.Y)
  else
  begin
    FillWithSpaces(Line, Size.X, Blank);
    WriteLine(0, 0, Size.X, Covered.A.Y, Line);
    WriteLine(0, Covered.B.Y, Size.X, Size.Y - Covered.B.Y, Line);
    if (Covered.A.X = 0) and (Covered.B.X = Size.X) then
      PutRows(First, Covered.A.Y, Covered.B.Y)
    else
    begin
      Span := Covered.B.X - Covered.A.X;
      for Y := Covered.A.Y to Covered.B.Y - 1 do
      begin
        Move(First^, Line[Covered.A.X], Span * SizeOf(TScreenCell));
        WriteBuf(0, Y, Size.X, 1, Line);
        Inc(First, Surface.Size.X);
      end;
    end;
  end;
end;

procedure TSurfaceView.Draw;
var
  Line: PScreenCell;
  Blank: TColorAttr;
begin
  if not ((Size.X > 0) and (Size.Y > 0)) then
    Exit;
  GetMem(Line, Size.X * SizeOf(TScreenCell));
  try
    Blank := MapColor(1);
    if Surface <> nil then
      ShowSurface(Line, Blank)
    else
    begin
      FillWithSpaces(Line, Size.X, Blank);
      WriteLine(0, 0, Size.X, Size.Y, Line);
    end;
  finally
    FreeMem(Line);
  end;
end;

function TSurfaceView.GetPalette: TPalette;
begin
  Result := SurfaceViewPalette;
end;

initialization
  SurfaceViewPalette := TPalette.Create(cpSurfaceView, Length(cpSurfaceView));

finalization
  SurfaceViewPalette.Free;

end.
