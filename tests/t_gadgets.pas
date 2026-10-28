{ Tests of TvGadgets. The display is a screen of 40 by 3 cells in memory; the root of the views is a group that
  writes into it, and the clock of the program is replaced by a fake. }
program t_gadgets;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  SysUtils, TvGeom, TvEvents, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvViews, TvGadgets;

{$I testlib.inc}

const
  ScrW = 40;
  ScrH = 3;

type
  TFakeDisplay = class(TScreenBackend)
  public
    CaretSize: Word;
    procedure SetCaretSize(ASize: Word); override;
    function GetCaretSize: Word; override;
  end;

  { The root of the views: a group with a palette of two entries. }
  TRoot = class(TGroup)
  public
    function GetPalette: TPalette; override;
  end;

  { A clock that counts its calls of Draw. }
  TCountClock = class(TClockView)
  public
    DrawCount: Integer;
    procedure Draw; override;
  end;

  { A heap view that counts its calls of Draw. }
  TCountHeap = class(THeapView)
  public
    DrawCount: Integer;
    procedure Draw; override;
  end;

  { The receiver of the clicks on a clock. }
  TClicker = class
  public
    Count: Integer;
    Last: TClockView;
    procedure Clicked(Sender: TClockView; var Event: TEvent);
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeDisplay;
  RootPal: TPalette;
  FakeTime: TDateTime;
  HeapValue: Int64;
  Clicker: TClicker;

{ The fake display. }

procedure TFakeDisplay.SetCaretSize(ASize: Word);
begin
  CaretSize := ASize;
end;

function TFakeDisplay.GetCaretSize: Word;
begin
  Result := CaretSize;
end;

function TRoot.GetPalette: TPalette;
begin
  Result := RootPal;
end;

procedure TCountClock.Draw;
begin
  Inc(DrawCount);
  inherited Draw;
end;

procedure TCountHeap.Draw;
begin
  Inc(DrawCount);
  inherited Draw;
end;

procedure TClicker.Clicked(Sender: TClockView; var Event: TEvent);
begin
  Inc(Count);
  Last := Sender;
  Sender.ClearEvent(Event);
end;

{ The hooks of the tests. }

function FakeNow: TDateTime;
begin
  Result := FakeTime;
end;

function FakeHeap: Int64;
begin
  Result := HeapValue;
end;

function HourDotMinute(H, M, S: Word; Seconds, Separator, Hour12: Boolean): AnsiString;
begin
  Result := IntToStr(H) + '.';
  if M < 10 then
    Result := Result + '0';
  Result := Result + IntToStr(M);
end;

procedure SetTime(H, M, S, Ms: Word);
begin
  FakeTime := EncodeTime(H, M, S, Ms);
end;

{ Small helpers. }

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function CharAt(X, Y: Integer): Char;
var
  Text: string;
begin
  Text := ScreenCells[Y * ScrW + X].Character.GetText;
  if Length(Text) > 0 then
    Result := Text[1]
  else
    Result := #0;
end;

function AttrAt(X, Y: Integer): TColorAttr;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute;
end;

function RowText(Y, X0, N: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to N - 1 do
    Result := Result + CharAt(X0 + I, Y);
end;

function PaletteByte(P: TPalette; Index: Integer): Byte;
begin
  Result := P.Data[Index];
end;

function NewRoot: TRoot;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
  Result := TRoot.Create(Rc(0, 0, ScrW, ScrH));
  Result.Options := Result.Options and not ofBuffered;
  Result.Buffer := @ScreenCells[0];
  Result.State := Result.State or sfSelected;
  Result.SetState(sfExposed, True);
end;

procedure FreeRoot(Root: TRoot);
begin
  TvObject.DestroyObject(Root);
end;

{ ---- the tests ---- }

procedure TestFormat;
begin
  Check(ClockFormatDefault(9, 5, 7, True, True, False) = '09:05:07', 'format 24h with seconds');
  Check(ClockFormatDefault(9, 5, 7, False, True, False) = '09:05', 'format 24h without seconds');
  Check(ClockFormatDefault(9, 5, 7, False, False, False) = '09 05', 'blank separator replaces the colon');
  Check(ClockFormatDefault(9, 5, 7, True, False, False) = '09 05:07', 'the separator before seconds stays a colon');
  Check(ClockFormatDefault(23, 59, 59, True, True, False) = '23:59:59', 'format 24h latest time');
  Check(ClockFormatDefault(0, 5, 0, False, True, True) = '12:05am', 'format 12h midnight is 12 am');
  Check(ClockFormatDefault(13, 5, 0, False, True, True) = ' 1:05pm', 'format 12h hour is padded with a blank');
  Check(ClockFormatDefault(12, 0, 9, True, True, True) = '12:00:09pm', 'format 12h noon with seconds is pm');
  Check(ClockFormatDefault(11, 59, 0, False, True, True) = '11:59am', 'format 12h last minute before noon');
  Check(Length(ClockFormatDefault(1, 2, 3, True, True, True)) = Length(ClockFormatDefault(10, 2, 3, True, True, True)),
    'format 12h has a constant width');
end;

procedure TestClockMain;
var
  Root: TRoot;
  Clock, Second: TCountClock;
  Hit: TEvent;
  Pal: TPalette;
  I: Integer;
  AllBlank: Boolean;
begin
  Root := NewRoot;
  ClockNow := @FakeNow;

  Clock := TCountClock.Create(Rc(30, 0, 40, 1));
  Clock.Margin := 1;
  Root.Insert(Clock);

  Check(Clock.ShowSeconds, 'clock shows seconds by default');
  Check(Clock.AutoSize, 'clock sizes itself by default');
  Check(not Clock.BlinkSeparator, 'clock does not blink by default');
  Check(not Clock.Hour12, 'clock is 24 hour by default');
  Check(not Clock.RightAlign, 'clock is not right aligned by default');
  Check(Clock.TimeStr = '', 'clock text is empty before the first update');
  Check((Clock.EventMask and evMouseDown) <> 0, 'clock takes mouse-down events');

  { Draw before the first Update shows blanks. }
  Clock.DrawView;
  AllBlank := True;
  for I := 30 to 39 do
    if CharAt(I, 0) <> ' ' then
      AllBlank := False;
  Check(AllBlank, 'draw before update shows blanks');
  Clock.DrawCount := 0;

  SetTime(10, 20, 30, 100);
  Clock.Update;
  Check(Clock.TimeStr = ' 10:20:30 ', 'update stores the text with the margin');
  Check(Clock.Size.X = 10, 'width follows the text');
  Check(Clock.Origin.X = 30, 'origin stays when the width is unchanged');
  Check(RowText(0, 30, 10) = ' 10:20:30 ', 'cells show the time');
  Check(Clock.DrawCount = 1, 'first update draws once');
  Check(AttrAt(30, 0) = TColorAttr.Create($2F), 'text attribute is entry 2 of the owner');
  Check(AttrAt(39, 0) = TColorAttr.Create($2F), 'blank attribute is entry 2 of the owner');

  SetTime(10, 20, 30, 900);
  Clock.Update;
  Check(Clock.DrawCount = 1, 'update with the same text does not draw');

  SetTime(10, 20, 31, 0);
  Clock.Update;
  Check(Clock.DrawCount = 2, 'update with a new text draws once');
  Check(RowText(0, 30, 10) = ' 10:20:31 ', 'cells show the next second');
  Check(Clock.MsToNextChange = 1000, 'ms to next change with seconds at a whole second');
  SetTime(10, 20, 31, 250);
  Check(Clock.MsToNextChange = 750, 'ms to next change with seconds inside a second');

  { No seconds, blinking separator. }
  Clock.ShowSeconds := False;
  Clock.BlinkSeparator := True;
  SetTime(10, 20, 31, 100);
  Clock.Update;
  Check(Clock.TimeStr = ' 10:20 ', 'text without seconds');
  Check(Clock.Size.X = 7, 'width shrinks to the shorter text');
  Check(Clock.GetBounds.B.X = 40, 'right edge stays in the right half');
  Check(Clock.Origin.X = 33, 'left edge moves in the right half');
  Check(RowText(0, 33, 7) = ' 10:20 ', 'cells show the short text');
  Check(Clock.MsToNextChange = 400, 'ms to next change when blinking, first half');
  SetTime(10, 20, 31, 600);
  Check(Clock.MsToNextChange = 400, 'ms to next change when blinking, second half');
  Clock.Update;
  Check(Clock.TimeStr = ' 10 20 ', 'separator is blank in the second half of a second');
  Check(Clock.Size.X = 7, 'width is the same with a blank separator');
  Clock.BlinkSeparator := False;
  Check(Clock.MsToNextChange = 28400, 'ms to next change without blinking and seconds');
  Clock.Update;
  Check(Clock.TimeStr = ' 10:20 ', 'separator stays without blinking');

  { A format hook. }
  Clock.FormatHook := @HourDotMinute;
  Clock.Update;
  Check(Clock.TimeStr = ' 10.20 ', 'format hook gives the text');
  Check(Clock.Size.X = 7, 'width follows the text of the hook');
  Check(Clock.GetBounds.B.X = 40, 'right edge stays with the hook');
  Clock.FormatHook := nil;
  Check(Clock.ClockText = ' 10:20 ', 'clock text does not store the result');
  Check(Clock.TimeStr = ' 10.20 ', 'clock text leaves the stored text alone');

  { A negative or zero margin adds nothing. }
  Clock.Margin := 0;
  Check(Clock.ClockText = '10:20', 'zero margin adds nothing');
  Clock.Margin := -3;
  Check(Clock.ClockText = '10:20', 'negative margin adds nothing');
  Clock.Margin := 1;

  { A mouse click. }
  Clock.OnClick := @Clicker.Clicked;
  FillChar(Hit, SizeOf(Hit), 0);
  Hit.What := evMouseDown;
  Clock.HandleEvent(Hit);
  Check(Clicker.Count = 1, 'click callback is called once');
  Check(Clicker.Last = TClockView(Clock), 'click callback gets the clock');
  Check(Hit.What = evNothing, 'click callback clears the event');
  FillChar(Hit, SizeOf(Hit), 0);
  Hit.What := evKeyDown;
  Clock.HandleEvent(Hit);
  Check(Clicker.Count = 1, 'a key event does not call the click callback');
  Check(Hit.What = evKeyDown, 'a key event is left alone');
  Clock.OnClick := nil;
  FillChar(Hit, SizeOf(Hit), 0);
  Hit.What := evMouseDown;
  Clock.HandleEvent(Hit);
  Check(Hit.What = evMouseDown, 'a click without a callback is left alone');

  { Palette. }
  Pal := Clock.GetPalette;
  Check(PaletteByte(Pal, 0) = 1, 'default palette has one entry');
  Check(PaletteByte(Pal, 1) = 2, 'default palette maps entry 1 to entry 2');
  Clock.PaletteStr := '';
  Check(PaletteByte(Clock.GetPalette, 0) = 0, 'empty palette string gives a palette of no entries');
  Clock.PaletteStr := #2;
  Check(PaletteByte(Clock.GetPalette, 0) = 1, 'palette is rebuilt from the string');

  { A second clock in the left half: the left edge stays. }
  Second := TCountClock.Create(Rc(2, 0, 12, 1));
  Second.ShowSeconds := False;
  Root.Insert(Second);
  SetTime(10, 20, 31, 100);
  Second.Update;
  Check(Second.TimeStr = '10:20', 'second clock text');
  Check(Second.Size.X = 5, 'second clock is 5 wide');
  Check(Second.Origin.X = 2, 'left edge stays in the left half');
  Check(RowText(0, 2, 5) = '10:20', 'second clock cells');
  Second.RightAlign := True;
  Second.Update;
  Check(Second.TimeStr = '10:20', 'right align keeps the text');
  Check(Second.GetBounds.B.X = 40, 'right align puts the right edge at the owner width');
  Check(Second.Size.X = 5, 'right align keeps the width');
  Check(Second.Origin.X = 35, 'right align moves the left edge');
  SetTime(10, 21, 0, 0);
  Second.Update;
  Check(Second.TimeStr = '10:21', 'right aligned clock follows the time');
  Check(Second.GetBounds.B.X = 40, 'right edge stays at the owner width');
  Second.ShowSeconds := True;
  Second.Update;
  Check(Second.TimeStr = '10:21:00', 'right aligned clock grows with the text');
  Check(Second.Size.X = 8, 'right aligned clock is 8 wide');
  Check(Second.GetBounds.B.X = 40, 'right aligned clock keeps the right edge when it grows');

  FreeRoot(Root);
  ClockNow := nil;
end;

procedure TestClockOptions;
var
  Root: TRoot;
  Fixed, Narrow, Early: TCountClock;
  Free12: TClockView;
begin
  Root := NewRoot;
  ClockNow := @FakeNow;

  { AutoSize off keeps the width. }
  Fixed := TCountClock.Create(Rc(2, 1, 12, 2));
  Fixed.ShowSeconds := False;
  Fixed.AutoSize := False;
  Root.Insert(Fixed);
  SetTime(10, 20, 31, 100);
  Fixed.Update;
  Check(Fixed.TimeStr = '10:20', 'fixed clock text');
  Check(Fixed.Size.X = 10, 'width is kept when AutoSize is off');
  Check(Fixed.Origin.X = 2, 'origin is kept when AutoSize is off');
  Check(RowText(1, 2, 10) = '10:20     ', 'text is drawn to the left, blanks fill the rest');

  { A text wider than the view is cut at the right edge. }
  Narrow := TCountClock.Create(Rc(10, 2, 14, 3));
  Narrow.AutoSize := False;
  Root.Insert(Narrow);
  Narrow.Update;
  Check(Narrow.TimeStr = '10:20:31', 'narrow clock text');
  Check(RowText(2, 10, 4) = '10:2', 'text is cut at the right edge of the view');
  Check(CharAt(14, 2) <> '2', 'nothing is written past the view');

  { Draw before Update. }
  Early := TCountClock.Create(Rc(20, 1, 30, 2));
  Root.Insert(Early);
  Early.DrawView;
  Check(RowText(1, 20, 10) = '          ', 'draw before update shows ten blanks');
  Check(Early.TimeStr = '', 'draw does not compute the text of a clock');

  { A clock without an owner. }
  Free12 := TClockView.Create(Rc(5, 0, 15, 1));
  Free12.Hour12 := True;
  Free12.ShowSeconds := False;
  SetTime(13, 5, 9, 0);
  Free12.Update;
  Check(Free12.TimeStr = ' 1:05pm', 'twelve hour clock shows pm with a padded hour');
  Check(Free12.Origin.X = 5, 'a clock without an owner keeps its left edge');
  Check(Free12.Size.X = 7, 'a clock without an owner takes the width of the text');
  Check(Free12.MsToNextChange = 51000, 'ms to next change without seconds and blinking');
  SetTime(0, 5, 0, 0);
  Free12.Update;
  Check(Free12.TimeStr = '12:05am', 'twelve hour clock shows 12 am at midnight');
  Check(Free12.Origin.X = 5, 'origin is kept when the text keeps its width');
  Free12.FitWidth(3);
  Check((Free12.Origin.X = 5) and (Free12.Size.X = 3), 'FitWidth without an owner keeps the left edge');
  Free12.RightAlign := True;
  Free12.FitWidth(4);
  Check((Free12.Origin.X = 5) and (Free12.Size.X = 4), 'right align without an owner keeps the left edge');
  TvObject.DestroyObject(Free12);

  FreeRoot(Root);
  ClockNow := nil;
end;

procedure TestClockPalette;
var
  First, Later: TClockView;
  Heap: THeapView;
begin
  GadgetPalette := #3;
  First := TClockView.Create(Rc(0, 0, 5, 1));
  Heap := THeapView.Create(Rc(0, 0, 5, 1));
  GadgetPalette := #2;
  Later := TClockView.Create(Rc(0, 0, 5, 1));
  Check(First.PaletteStr = #3, 'clock copies the global palette when it is created');
  Check(Heap.PaletteStr = #3, 'heap view copies the global palette when it is created');
  Check(Later.PaletteStr = #2, 'a later clock copies the changed global palette');
  Check(PaletteByte(First.GetPalette, 1) = 3, 'palette of a clock is made from its own string');
  Check(PaletteByte(Heap.GetPalette, 1) = 3, 'palette of a heap view is made from its own string');
  Check(GadgetPalette = #2, 'the global palette defaults to one entry that maps to entry 2');
  Heap.PaletteStr := '';
  Check(PaletteByte(Heap.GetPalette, 0) = 0, 'heap view with an empty string has no palette of its own');
  TvObject.DestroyObject(First);
  TvObject.DestroyObject(Heap);
  TvObject.DestroyObject(Later);
end;

procedure TestHeap;
var
  Root: TRoot;
  Heap: TCountHeap;
  Narrow: TCountHeap;
  Probe: TCountHeap;
  Plain, WithKb: THeapView;
  Before: Integer;
begin
  Root := NewRoot;

  Plain := THeapView.Create(Rc(0, 0, 5, 1));
  WithKb := THeapView.CreateKb(Rc(0, 0, 5, 1));
  Check(not Plain.Kb, 'Create makes a heap view in bytes');
  Check(WithKb.Kb, 'CreateKb makes a heap view in kilobytes');
  Check(Plain.PaletteStr = #2, 'heap view palette string is the default');
  Check(Plain.HeapStr = '', 'heap text is empty at the start');
  TvObject.DestroyObject(Plain);
  TvObject.DestroyObject(WithKb);

  Heap := TCountHeap.Create(Rc(30, 2, 40, 3));
  Root.Insert(Heap);
  Heap.ValueHook := @FakeHeap;
  HeapValue := 123456;
  Check(Heap.HeapText = '123456', 'heap text in bytes');
  Heap.Update;
  Check(Heap.HeapStr = '123456', 'update stores the text');
  Check(RowText(2, 30, 10) = '    123456', 'text is right aligned');
  Check(AttrAt(30, 2) = TColorAttr.Create($2F), 'heap view uses entry 2 of the owner');

  Before := Heap.DrawCount;
  Heap.Update;
  Check(Heap.DrawCount = Before, 'update with the same text does not draw');

  Heap.Kb := True;
  Check(Heap.HeapStr = '123456', 'changing Kb does not show before the next update');
  Heap.Update;
  Check(Heap.HeapText = '121K', 'heap text in kilobytes');
  Check(Heap.HeapStr = '121K', 'update stores the text in kilobytes');
  Check(RowText(2, 30, 10) = '      121K', 'kilobyte text is right aligned');
  Check(Heap.DrawCount = Before + 1, 'a new text draws once');

  HeapValue := 1024;
  Check(Heap.HeapText = '1K', 'exact kilobyte is not rounded up');
  HeapValue := 1025;
  Check(Heap.HeapText = '2K', 'kilobytes are rounded up');
  HeapValue := 0;
  Check(Heap.HeapText = '0K', 'zero kilobytes');

  { The default counter. }
  Heap.ValueHook := nil;
  Heap.Kb := False;
  Check(HeapInUse > 0, 'heap in use is positive');
  Check(StrToInt64(Heap.HeapText) > 0, 'heap text without a hook is a positive number');
  Heap.Update;
  Check(StrToInt64(Trim(RowText(2, 30, 10))) > 0, 'cells show a positive number without a hook');

  { A text wider than the view loses its right end. }
  Narrow := TCountHeap.Create(Rc(0, 2, 4, 3));
  Root.Insert(Narrow);
  Narrow.ValueHook := @FakeHeap;
  HeapValue := 123456;
  Narrow.Update;
  Check(RowText(2, 0, 4) = '1234', 'a wide text starts at cell 0 and loses its right end');
  Check(CharAt(4, 2) <> '5', 'nothing is written past a narrow heap view');

  { Draw fills an empty text. }
  Probe := TCountHeap.Create(Rc(20, 2, 30, 3));
  Probe.ValueHook := @FakeHeap;
  HeapValue := 5;
  Root.Insert(Probe);
  Probe.DrawView;
  Check(Probe.HeapStr = '5', 'draw computes the text when it is empty');
  Check(RowText(2, 20, 10) = '         5', 'draw shows the computed text at the right');
  Before := Probe.DrawCount;
  Probe.Update;
  Check(Probe.DrawCount = Before, 'update after draw finds the same text');

  FreeRoot(Root);
end;

begin
  RootPal := TPalette.Create([TColorAttr.Create($1E), TColorAttr.Create($2F)]);
  Fake := TFakeDisplay.Create;
  TDisplay.Backend := Fake;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  Clicker := TClicker.Create;

  TestFormat;
  TestClockMain;
  TestClockOptions;
  TestClockPalette;
  TestHeap;

  Clicker.Free;
  TScreen.ScreenBuffer := nil;
  TDisplay.Backend := nil;
  Fake.Free;
  RootPal.Free;
  Done;
end.
