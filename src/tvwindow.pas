{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/views.h (TFrame, TScrollBar, TScroller, TWindowInit, TWindow and the palettes of the
  windows), source/tvision/tframe.cpp, source/tvision/framelin.cpp, source/tvision/tscrlbar.cpp,
  source/tvision/tscrolle.cpp, source/tvision/twindow.cpp, source/tvision/tvtext1.cpp (the tables of TFrame and
  TScrollBar), include/tvision/util.h, source/tvision/misc.cpp (message)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit.

  message() sends a message to a view; it is Message of TvViews.

  The tables of TFrame (initFrame, frameChars and the five icons) and of TScrollBar (vChars, hChars) are class
  variables, InitFrame, FrameChars, CloseIcon, ZoomIcon, UnZoomIcon, DragIcon and DragLeftIcon of TFrame and VChars and
  HChars of TScrollBar. They get their values, the ones of tvtext1.cpp, when the unit starts; a program may change
  them, as the C++ changes frameChars. The bytes are those of code page 437.

  A Pascal class has one parent, so TWindowInit, which the C++ inherits virtually beside TGroup, is the class between
  TGroup and TWindow: it holds the function that makes the frame. The constructor of TWindow that has no function
  of this kind makes the frame with TWindow.InitFrame, and the constructor that has one passes it to TWindowInit.
  A pointer to a TFrame function that takes a TRect is a TCreateFrameFunc. The title of a window is a block of
  characters with a terminating zero, as the C++ keeps it; GetTitle returns it and nil stands for no title. }
unit TvWindow;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvViews;

const
  { The palettes of the windows. }
  cpBlueWindow = #8#9#10#11#12#13#14#15;
  cpCyanWindow = #16#17#18#19#20#21#22#23;
  cpGrayWindow = #24#25#26#27#28#29#30#31;

type
  TScrollChars = array[0..4] of AnsiChar;

  { The frame of a window. The palette is: 1 passive frame, 2 passive title, 3 active frame, 4 active title,
    5 icons. }
  TFrame = class(TView)
  private
    procedure FrameLine(LineBuffer: TDrawBuffer; Row, MaskIndex: SmallInt; Tint: TColorAttr);
    procedure DragWindow(var Event: TEvent; DragKind: Byte);
  public
    { The masks of the three cells of each kind of line (initFrame), the characters for the masks (frameChars) and
      the icons, in the notation of a command string with tildes. }
    class var InitFrame: array[0..18] of AnsiChar;
    class var FrameChars: array[0..32] of AnsiChar;
    class var CloseIcon: string;
    class var ZoomIcon: string;
    class var UnZoomIcon: string;
    class var DragIcon: string;
    class var DragLeftIcon: string;

    constructor Create(const Bounds: TRect);
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SetState(StateBits: Word; TurnOn: Boolean); override;
  end;

  { A scroll bar. The palette is: 1 page areas, 2 arrows, 3 indicator. }
  TScrollBar = class(TView)
  private
    function GetPartCode: Integer;
  public
    Value: Integer;
    Chars: TScrollChars;
    MinVal: Integer;
    MaxVal: Integer;
    PgStep: Integer;
    ArStep: Integer;
    { The characters of a vertical bar and of a horizontal bar: the two arrows, the page area, the indicator and
      the page area of a bar that cannot scroll. }
    class var VChars: TScrollChars;
    class var HChars: TScrollChars;

    constructor Create(const Bounds: TRect);
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ScrollDraw; virtual;
    function ScrollStep(PartCode: Integer): Integer; virtual;
    procedure SetParams(NewValue, NewMin, NewMax, NewPageStep, NewArrowStep: Integer);
    procedure SetRange(NewMin, NewMax: Integer);
    procedure SetStep(NewPageStep, NewArrowStep: Integer);
    procedure SetValue(NewValue: Integer);
    procedure DrawPos(Position: Integer);
    function GetPos: Integer;
    function GetSize: Integer;
  end;

  { A view that shows a part of a larger area. The palette is: 1 normal text, 2 selected text. }
  TScroller = class(TView)
  public
    Delta: TPoint;
  protected
    DrawLock: Byte;
    DrawFlag: Boolean;
    HScrollBar: TScrollBar;
    VScrollBar: TScrollBar;
    Limit: TPoint;
  private
    procedure ShowSBar(Bar: TScrollBar);
  public
    constructor Create(const Bounds: TRect; HorizontalBar, VerticalBar: TScrollBar);
    procedure ChangeBounds(const Bounds: TRect); override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ScrollDraw; virtual;
    procedure ScrollTo(Column, Row: Integer);
    procedure SetLimit(Columns, Rows: Integer);
    procedure SetState(StateBits: Word; TurnOn: Boolean); override;
    procedure CheckDraw;
    procedure ShutDown; override;
  end;

  { The function that makes the frame of a window. }
  TCreateFrameFunc = function(Area: TRect): TFrame;

  { Holds the function that makes the frame of a window. }
  TWindowInit = class(TGroup)
  protected
    CreateFrame: TCreateFrameFunc;
  public
    constructor Create(const Bounds: TRect; FrameMaker: TCreateFrameFunc); reintroduce;
  end;

  { A window. The palette is: 1 frame passive, 2 frame active, 3 frame icon, 4 scroll bar page area,
    5 scroll bar controls, 6 scroller normal text, 7 scroller selected text, 8 reserved. }
  TWindow = class(TWindowInit)
  private
    procedure Setup(const WindowTitle: string; WindowNumber: SmallInt);
  public
    Flags: Byte;
    ZoomRect: TRect;
    Number: SmallInt;
    Palette: SmallInt;
    Frame: TFrame;
    Title: PAnsiChar;

    constructor Create(const Bounds: TRect; const WindowTitle: string; WindowNumber: SmallInt); overload;
    { As the first constructor, with FrameMaker as the function that makes the frame. }
    constructor Create(const Bounds: TRect; const WindowTitle: string; WindowNumber: SmallInt;
      FrameMaker: TCreateFrameFunc); overload;
    destructor Destroy; override;
    procedure Close; virtual;
    function GetPalette: TPalette; override;
    function GetTitle(RoomLeft: SmallInt): PAnsiChar; virtual;
    procedure HandleEvent(var Event: TEvent); override;
    class function InitFrame(Area: TRect): TFrame; static;
    procedure SetState(StateBits: Word; TurnOn: Boolean); override;
    procedure SizeLimits(var Smallest, Largest: TPoint); override;
    function StandardScrollBar(ScrollOptions: Word): TScrollBar;
    procedure Zoom; virtual;
    procedure ShutDown; override;
  end;

implementation

uses
  TvObjs, TvKeys, TvUtil;

const
  cpFrame = #1#1#2#2#3;
  cpScrollBar = #4#5#5;
  cpScroller = #6#7;

  SmallestWindow: TPoint = (X: 16; Y: 6);

  { The values of the tables of TFrame and TScrollBar, as strings of character codes. }
  InitFrameValues = #6#10#12#5#0#5#3#10#9#22#26#28#21#0#21#19#26#25;
  FrameCharsValues = #32#32#32#192#32#179#218#195#32#217#196#193#191#180#194#197 +
    #32#32#32#200#32#186#201#199#32#188#205#207#187#182#209#32;
  VCharsValues = #30#31#177#254#178;
  HCharsValues = #17#16#177#254#178;

var
  FramePalette: TPalette;
  ScrollBarPalette: TPalette;
  ScrollerPalette: TPalette;
  WindowPalettes: array[0..2] of TPalette;

  { The state of the last mouse press on a scroll bar: the position of the mouse in the bar, the position of the
    indicator, the position of the last arrow and the area of the bar, grown by one. }
  PressedAt: TPoint;
  IndicatorAt: Integer;
  LastArrowAt: Integer;
  PressArea: TRect;

{ Tells whether any bit of Mask is set in Bits. }
function AnyBit(Bits, Mask: Word): Boolean;
begin
  Result := (Bits and Mask) <> 0;
end;

{ Halves Amount, rounding towards minus infinity. }
function FloorHalf(Amount: Integer): Integer;
begin
  Result := Amount div 2;
  if (Amount < 0) and Odd(Amount) then
    Dec(Result);
end;

{ Turns Event into a command for Target, puts it back to the owners of Sender and clears it. }
procedure PostCommand(Sender: TView; var Event: TEvent; Command: Word; Info: Pointer);
begin
  Event.Message.Command := Command;
  Event.What := evCommand;
  Event.Message.InfoPtr := Info;
  Sender.PutEvent(Event);
  Sender.ClearEvent(Event);
end;

{ TFrame }

constructor TFrame.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  GrowMode := gfGrowHiX or gfGrowHiY;
  EventMask := EventMask or evMouseUp or evBroadcast;
end;

{ Puts the icons of an active frame into the buffer of its top row. }
procedure PutTopIcons(Frame: TFrame; Holder: TWindow; LineBuffer: TDrawBuffer; const Tints: TAttrPair);
var
  smallest, largest: TPoint;
  zoomedIcon: string;
begin
  if AnyBit(Holder.Flags, wfClose) then
    LineBuffer.MoveCStr(2, TFrame.CloseIcon, Tints);
  if not AnyBit(Holder.Flags, wfZoom) then
    Exit;
  Holder.SizeLimits(smallest, largest);
  if Holder.Size = largest then
    zoomedIcon := TFrame.UnZoomIcon
  else
    zoomedIcon := TFrame.ZoomIcon;
  LineBuffer.MoveCStr(Word(Frame.Size.X - 5), zoomedIcon, Tints);
end;

procedure TFrame.Draw;
var
  frameTints, titleTints: TAttrPair;
  frameCode, titleCode: Word;
  lineKind, row, titleRoom, frameWidth: Integer;
  lineBuffer: TDrawBuffer;
  holder: TWindow;
  titleText: PAnsiChar;
  titleString: string;
  titleWidth, titleStart, numberBack: Integer;
  isActive: Boolean;
begin
  isActive := AnyBit(State, sfActive);
  if AnyBit(State, sfDragging) then
  begin
    frameCode := $0505;
    titleCode := $0005;
    lineKind := 0;
  end
  else if isActive then
  begin
    frameCode := $0503;
    titleCode := $0004;
    lineKind := 9;
  end
  else
  begin
    frameCode := $0101;
    titleCode := $0002;
    lineKind := 0;
  end;

  frameTints := GetColor(frameCode);
  titleTints := GetColor(titleCode);

  frameWidth := Size.X;
  titleRoom := frameWidth - 10;

  holder := TWindow(Owner);
  if AnyBit(holder.Flags, wfClose or wfZoom) then
    titleRoom := titleRoom - 6;

  lineBuffer := TDrawBuffer.Create;
  try
    FrameLine(lineBuffer, 0, lineKind, frameTints.Attrs[0]);

    if (holder.Number <> wnNoNumber) and (holder.Number < 10) then
    begin
      titleRoom := titleRoom - 4;
      if AnyBit(holder.Flags, wfZoom) then
        numberBack := 7
      else
        numberBack := 3;
      lineBuffer.PutChar(Word(frameWidth - numberBack), Byte((holder.Number + Ord('0')) and $FF));
    end;

    if Owner <> nil then
    begin
      titleText := holder.GetTitle(SmallInt(titleRoom));
      if titleText <> nil then
      begin
        titleString := StrPas(titleText);
        titleWidth := Max(Min(Strwidth(titleString), frameWidth - 10), 0);
        titleStart := FloorHalf(frameWidth - titleWidth);
        lineBuffer.PutChar(Word(titleStart - 1), Ord(' '));
        lineBuffer.MoveStr(Word(titleStart), titleString, titleTints.Attrs[0], Word(titleWidth));
        lineBuffer.PutChar(Word(titleStart + titleWidth), Ord(' '));
      end;
    end;

    if isActive then
      PutTopIcons(Self, holder, lineBuffer, frameTints);

    WriteLine(0, 0, Size.X, 1, lineBuffer);
    row := 1;
    while row <= Size.Y - 2 do
    begin
      FrameLine(lineBuffer, row, lineKind + 3, frameTints.Attrs[0]);
      WriteLine(0, row, Size.X, 1, lineBuffer);
      Inc(row);
    end;

    FrameLine(lineBuffer, Size.Y - 1, lineKind + 6, frameTints.Attrs[0]);
    if isActive and AnyBit(holder.Flags, wfGrow) then
    begin
      lineBuffer.MoveCStr(0, DragLeftIcon, frameTints);
      lineBuffer.MoveCStr(Word(frameWidth - 2), DragIcon, frameTints);
    end;
    WriteLine(0, Size.Y - 1, Size.X, 1, lineBuffer);
  finally
    lineBuffer.Free;
  end;
end;

function TFrame.GetPalette: TPalette;
begin
  Result := FramePalette;
end;

procedure TFrame.DragWindow(var Event: TEvent; DragKind: Byte);
var
  areaLimits: TRect;
  smallest, largest: TPoint;
  combinedMode: Byte;
begin
  areaLimits := Owner.Owner.GetExtent;
  Owner.SizeLimits(smallest, largest);
  combinedMode := Owner.DragMode or DragKind;
  Owner.DragView(Event, combinedMode, areaLimits, smallest, largest);
  ClearEvent(Event);
end;

procedure TFrame.HandleEvent(var Event: TEvent);
var
  mouseLocal: TPoint;
  holder: TWindow;
  isActive, onCloseIcon, onZoomIcon, onGrip, inInterior: Boolean;
begin
  inherited HandleEvent(Event);
  if Event.What <> evMouseDown then
    Exit;

  holder := TWindow(Owner);
  mouseLocal := MakeLocal(Event.Mouse.Where);
  isActive := AnyBit(State, sfActive);

  if mouseLocal.Y <> 0 then
  begin
    onGrip := isActive and (mouseLocal.Y >= Size.Y - 1) and AnyBit(holder.Flags, wfGrow);
    if onGrip then
    begin
      if mouseLocal.X >= Size.X - 2 then
        DragWindow(Event, dmDragGrow)
      else if mouseLocal.X <= 1 then
        DragWindow(Event, dmDragGrowLeft);
      Exit;
    end;
    inInterior := (mouseLocal.X > 0) and (mouseLocal.X < Size.X - 1) and (mouseLocal.Y > 0) and
      (mouseLocal.Y < Size.Y - 1);
    if (Event.Mouse.Buttons = mbMiddleButton) and inInterior and AnyBit(holder.Flags, wfMove) then
      DragWindow(Event, dmDragMove);
    Exit;
  end;

  onCloseIcon := AnyBit(holder.Flags, wfClose) and isActive and (mouseLocal.X >= 2) and (mouseLocal.X <= 4);
  if onCloseIcon then
  begin
    while MouseEvent(Event, evMouse) do
      ;
    mouseLocal := MakeLocal(Event.Mouse.Where);
    if (mouseLocal.Y = 0) and (mouseLocal.X >= 2) and (mouseLocal.X <= 4) then
      PostCommand(Self, Event, cmClose, Owner);
    Exit;
  end;

  onZoomIcon := (mouseLocal.X >= Size.X - 5) and (mouseLocal.X <= Size.X - 3);
  if AnyBit(holder.Flags, wfZoom) and isActive and (onZoomIcon or AnyBit(Event.Mouse.EventFlags, meDoubleClick)) then
  begin
    PostCommand(Self, Event, cmZoom, Owner);
    Exit;
  end;

  if AnyBit(holder.Flags, wfMove) then
    DragWindow(Event, dmDragMove);
end;

procedure TFrame.SetState(StateBits: Word; TurnOn: Boolean);
begin
  inherited SetState(StateBits, TurnOn);
  if AnyBit(StateBits, sfActive or sfDragging) then
    DrawView;
end;

{ Writes the row Row of the frame into LineBuffer. MaskIndex is the index of the first of the three masks of the
  row in InitFrame. }
procedure TFrame.FrameLine(LineBuffer: TDrawBuffer; Row, MaskIndex: SmallInt; Tint: TColorAttr);
var
  cellMasks: array of Byte;
  lastColumn, column, coverFirst, coverEnd, siblingTop, siblingBottom: Integer;
  sibling: TView;
  edgeBits: Word;
  lowBits, highBits: Byte;
begin
  if Size.X <= 0 then
    Exit;

  lastColumn := Size.X - 1;
  SetLength(cellMasks, Size.X);
  cellMasks[0] := Ord(InitFrame[MaskIndex]);
  for column := 1 to lastColumn - 1 do
    cellMasks[column] := Ord(InitFrame[MaskIndex + 1]);
  cellMasks[lastColumn] := Ord(InitFrame[MaskIndex + 2]);

  sibling := Owner.Last.Next;
  while sibling <> TView(Self) do
  begin
    if AnyBit(sibling.Options, ofFramed) and AnyBit(sibling.State, sfVisible) then
    begin
      siblingTop := sibling.Origin.Y;
      siblingBottom := siblingTop + sibling.Size.Y;
      edgeBits := 0;
      if (Row >= siblingTop) and (Row < siblingBottom) then
        edgeBits := 5
      else if Row = siblingTop - 1 then
        edgeBits := (10 shl 8) or 6
      else if Row = siblingBottom then
        edgeBits := (10 shl 8) or 3;

      if edgeBits <> 0 then
      begin
        coverFirst := Max(sibling.Origin.X, 1);
        coverEnd := Min(sibling.Origin.X + sibling.Size.X, lastColumn);
        if coverFirst < coverEnd then
        begin
          lowBits := edgeBits and 255;
          highBits := edgeBits shr 8;
          cellMasks[coverFirst - 1] := cellMasks[coverFirst - 1] or lowBits;
          cellMasks[coverEnd] := cellMasks[coverEnd] or (lowBits xor highBits);
          if lowBits <> 0 then
          begin
            column := coverFirst;
            while column < coverEnd do
            begin
              cellMasks[column] := cellMasks[column] or highBits;
              Inc(column);
            end;
          end;
        end;
      end;
    end;
    sibling := sibling.Next;
  end;

  column := 0;
  while column <= lastColumn do
  begin
    LineBuffer.PutChar(Word(column), Ord(FrameChars[cellMasks[column]]));
    LineBuffer.PutAttribute(Word(column), Tint);
    Inc(column);
  end;
end;

{ TScrollBar }

constructor TScrollBar.Create(const Bounds: TRect);
var
  growBits: Byte;
  charSource: Pointer;
begin
  inherited Create(Bounds);
  MinVal := 0;
  MaxVal := 0;
  Value := MinVal;
  PgStep := 1;
  ArStep := PgStep;
  if Size.X <> 1 then
  begin
    growBits := gfGrowLoY or gfGrowHiX or gfGrowHiY;
    charSource := @HChars;
  end
  else
  begin
    growBits := gfGrowLoX or gfGrowHiX or gfGrowHiY;
    charSource := @VChars;
  end;
  GrowMode := growBits;
  Move(charSource^, Chars, SizeOf(Chars));
  EventMask := EventMask or evMouseWheel;
end;

procedure TScrollBar.Draw;
begin
  DrawPos(GetPos);
end;

procedure TScrollBar.DrawPos(Position: Integer);
var
  lineBuffer: TDrawBuffer;
  lastCell: Integer;
  tints: TAttrPair;
  pageCells: Word;
begin
  lineBuffer := TDrawBuffer.Create;
  try
    lastCell := GetSize - 1;
    pageCells := Word(lastCell - 1);

    tints := GetColor(2);
    lineBuffer.MoveChar(0, Chars[0], tints.Attrs[0], 1);

    tints := GetColor(1);
    if MaxVal = MinVal then
      lineBuffer.MoveChar(1, Chars[4], tints.Attrs[0], pageCells)
    else
    begin
      lineBuffer.MoveChar(1, Chars[2], tints.Attrs[0], pageCells);
      tints := GetColor(3);
      lineBuffer.MoveChar(Word(Position), Chars[3], tints.Attrs[0], 1);
    end;

    tints := GetColor(2);
    lineBuffer.MoveChar(Word(lastCell), Chars[1], tints.Attrs[0], 1);
    WriteBuf(0, 0, Size.X, Size.Y, lineBuffer);
  finally
    lineBuffer.Free;
  end;
end;

function TScrollBar.GetPalette: TPalette;
begin
  Result := ScrollBarPalette;
end;

function TScrollBar.GetPos: Integer;
var
  span: Integer;
  numerator: Int64;
begin
  Result := 1;
  span := MaxVal - MinVal;
  if span = 0 then
    Exit;
  numerator := Int64(Value - MinVal) * (GetSize - 3) + FloorHalf(span);
  Result := Integer(numerator div span) + 1;
end;

function TScrollBar.GetSize: Integer;
var
  extent: Integer;
begin
  extent := Size.X;
  if Size.X = 1 then
    extent := Size.Y;
  Result := Max(3, extent);
end;

{ Tells which part of the bar the mouse is on, from the state of the last press; -1 when it is off the bar. }
function TScrollBar.GetPartCode: Integer;
var
  mark: Integer;
  isVertical: Boolean;
begin
  Result := -1;
  if not PressArea.Contains(PressedAt) then
    Exit;

  isVertical := Size.X = 1;
  if isVertical then
    mark := PressedAt.Y
  else
    mark := PressedAt.X;

  if mark = IndicatorAt then
  begin
    Result := sbIndicator;
    Exit;
  end;

  if mark < 1 then
    Result := sbLeftArrow
  else if mark < IndicatorAt then
    Result := sbPageLeft
  else if mark < LastArrowAt then
    Result := sbPageRight
  else
    Result := sbRightArrow;

  if isVertical then
    Result := Result + 4;
end;

{ The mouse wheel on a scroll bar. }
procedure BarWheel(Bar: TScrollBar; var Event: TEvent);
var
  stepSize: Integer;
  isVertical: Boolean;
begin
  stepSize := 0;
  isVertical := Bar.Size.X = 1;
  if AnyBit(Bar.State, sfVisible) then
    case Event.Mouse.Wheel of
      mwUp:
        if isVertical then
          stepSize := -Bar.ArStep;
      mwDown:
        if isVertical then
          stepSize := Bar.ArStep;
      mwLeft:
        if not isVertical then
          stepSize := -Bar.ArStep;
      mwRight:
        if not isVertical then
          stepSize := Bar.ArStep;
    end;
  if stepSize = 0 then
    Exit;
  Message(Bar.Owner, evBroadcast, cmScrollBarClicked, Bar);
  Bar.SetValue(Bar.Value + 3 * stepSize);
  Bar.ClearEvent(Event);
end;

{ A press of the mouse button on a scroll bar. }
procedure BarPress(Bar: TScrollBar; var Event: TEvent);
var
  pressedPart, pointerAt, travel: Integer;
  scaled: Int64;
begin
  Message(Bar.Owner, evBroadcast, cmScrollBarClicked, Bar);
  PressedAt := Bar.MakeLocal(Event.Mouse.Where);
  PressArea := Bar.GetExtent;
  PressArea.Grow(1, 1);
  IndicatorAt := Bar.GetPos;
  LastArrowAt := Bar.GetSize - 1;
  pressedPart := Bar.GetPartCode;

  case pressedPart of
    sbLeftArrow, sbRightArrow, sbUpArrow, sbDownArrow:
      while True do
      begin
        PressedAt := Bar.MakeLocal(Event.Mouse.Where);
        if Bar.GetPartCode = pressedPart then
          Bar.SetValue(Bar.Value + Bar.ScrollStep(pressedPart));
        if not Bar.MouseEvent(Event, evMouseAuto) then
          Break;
      end;
  else
    while True do
    begin
      PressedAt := Bar.MakeLocal(Event.Mouse.Where);
      if Bar.Size.X = 1 then
        pointerAt := PressedAt.Y
      else
        pointerAt := PressedAt.X;
      pointerAt := Min(Max(pointerAt, 1), LastArrowAt - 1);
      IndicatorAt := pointerAt;
      travel := LastArrowAt - 2;
      if travel > 0 then
      begin
        scaled := Int64(IndicatorAt - 1) * (Bar.MaxVal - Bar.MinVal) + (travel div 2);
        Bar.SetValue(Integer(scaled div travel) + Bar.MinVal);
      end;
      Bar.DrawPos(IndicatorAt);
      if not Bar.MouseEvent(Event, evMouseMove) then
        Break;
    end;
  end;
  Bar.ClearEvent(Event);
end;

{ Tells which part of the bar a key stands for, or the value that it goes to. Returns False when the bar ignores
  the key. }
function BarKey(Bar: TScrollBar; KeyCode: Word; out Part: Integer; out Target: Integer): Boolean;
var
  arrowKey: Word;
begin
  Part := sbIndicator;
  Target := 0;
  Result := True;
  arrowKey := CtrlToArrow(KeyCode);
  if Bar.Size.Y = 1 then
    case arrowKey of
      kbLeft:
        Part := sbLeftArrow;
      kbRight:
        Part := sbRightArrow;
      kbCtrlLeft:
        Part := sbPageLeft;
      kbCtrlRight:
        Part := sbPageRight;
      kbCtrlUp:
        Part := sbPageUp;
      kbCtrlDown:
        Part := sbPageDown;
      kbHome:
        Target := Bar.MinVal;
      kbEnd:
        Target := Bar.MaxVal;
    else
      Result := False;
    end
  else
    case arrowKey of
      kbUp:
        Part := sbUpArrow;
      kbDown:
        Part := sbDownArrow;
      kbPgUp:
        Part := sbPageUp;
      kbPgDn:
        Part := sbPageDown;
      kbCtrlPgUp:
        Target := Bar.MinVal;
      kbCtrlPgDn:
        Target := Bar.MaxVal;
    else
      Result := False;
    end;
end;

procedure TScrollBar.HandleEvent(var Event: TEvent);
var
  keyPart, keyTarget: Integer;
begin
  inherited HandleEvent(Event);
  case Event.What of
    evMouseWheel:
      BarWheel(Self, Event);
    evMouseDown:
      BarPress(Self, Event);
    evKeyDown:
      begin
        if not AnyBit(State, sfVisible) then
          Exit;
        if not BarKey(Self, Event.KeyDown.KeyCode, keyPart, keyTarget) then
          Exit;
        Message(Owner, evBroadcast, cmScrollBarClicked, Self);
        if keyPart <> sbIndicator then
          keyTarget := Value + ScrollStep(keyPart);
        SetValue(keyTarget);
        ClearEvent(Event);
      end;
  end;
end;

procedure TScrollBar.ScrollDraw;
begin
  Message(Owner, evBroadcast, cmScrollBarChanged, Self);
end;

function TScrollBar.ScrollStep(PartCode: Integer): Integer;
var
  magnitude: Integer;
begin
  if AnyBit(PartCode, 2) then
    magnitude := PgStep
  else
    magnitude := ArStep;
  if AnyBit(PartCode, 1) then
    Result := magnitude
  else
    Result := -magnitude;
end;

procedure TScrollBar.SetParams(NewValue, NewMin, NewMax, NewPageStep, NewArrowStep: Integer);
var
  oldValue, clampedValue, clampedMax: Integer;
  somethingChanged: Boolean;
begin
  clampedMax := Max(NewMax, NewMin);
  clampedValue := Min(clampedMax, Max(NewMin, NewValue));
  oldValue := Value;
  somethingChanged := (oldValue <> clampedValue) or (MinVal <> NewMin) or (MaxVal <> clampedMax);
  if somethingChanged then
  begin
    Value := clampedValue;
    MinVal := NewMin;
    MaxVal := clampedMax;
    DrawView;
    if oldValue <> clampedValue then
      ScrollDraw;
  end;
  PgStep := NewPageStep;
  ArStep := NewArrowStep;
end;

procedure TScrollBar.SetRange(NewMin, NewMax: Integer);
begin
  SetParams(Value, NewMin, NewMax, PgStep, ArStep);
end;

procedure TScrollBar.SetStep(NewPageStep, NewArrowStep: Integer);
begin
  SetParams(Value, MinVal, MaxVal, NewPageStep, NewArrowStep);
end;

procedure TScrollBar.SetValue(NewValue: Integer);
begin
  SetParams(NewValue, MinVal, MaxVal, PgStep, ArStep);
end;

{ TScroller }

constructor TScroller.Create(const Bounds: TRect; HorizontalBar, VerticalBar: TScrollBar);
begin
  inherited Create(Bounds);
  DrawLock := 0;
  DrawFlag := False;
  HScrollBar := HorizontalBar;
  VScrollBar := VerticalBar;
  FillChar(Delta, SizeOf(Delta), 0);
  FillChar(Limit, SizeOf(Limit), 0);
  Options := Options or ofSelectable;
  EventMask := EventMask or evBroadcast;
end;

procedure TScroller.ShutDown;
begin
  VScrollBar := nil;
  HScrollBar := nil;
  inherited ShutDown;
end;

procedure TScroller.ChangeBounds(const Bounds: TRect);
begin
  SetBounds(Bounds);
  DrawLock := DrawLock + 1;
  SetLimit(Limit.X, Limit.Y);
  DrawLock := DrawLock - 1;
  DrawFlag := False;
  DrawView;
end;

procedure TScroller.CheckDraw;
begin
  if (DrawLock <> 0) or not DrawFlag then
    Exit;
  DrawFlag := False;
  DrawView;
end;

function TScroller.GetPalette: TPalette;
begin
  Result := ScrollerPalette;
end;

procedure TScroller.HandleEvent(var Event: TEvent);
var
  sender: Pointer;
  isChange: Boolean;
begin
  inherited HandleEvent(Event);
  isChange := (Event.What = evBroadcast) and (Event.Message.Command = cmScrollBarChanged);
  if not isChange then
    Exit;
  sender := Event.Message.InfoPtr;
  if sender = Pointer(HScrollBar) then
    ScrollDraw
  else if sender = Pointer(VScrollBar) then
    ScrollDraw;
end;

procedure TScroller.ScrollDraw;
var
  newDelta: TPoint;
begin
  newDelta.X := 0;
  newDelta.Y := 0;
  if HScrollBar <> nil then
    newDelta.X := HScrollBar.Value;
  if VScrollBar <> nil then
    newDelta.Y := VScrollBar.Value;

  if (newDelta.X = Delta.X) and (newDelta.Y = Delta.Y) then
    Exit;
  SetCursor(Cursor.X + Delta.X - newDelta.X, Cursor.Y + Delta.Y - newDelta.Y);
  Delta := newDelta;
  if DrawLock = 0 then
    DrawView
  else
    DrawFlag := True;
end;

procedure TScroller.ScrollTo(Column, Row: Integer);
begin
  Inc(DrawLock);
  if HScrollBar <> nil then
    HScrollBar.SetValue(Column);
  if VScrollBar <> nil then
    VScrollBar.SetValue(Row);
  Dec(DrawLock);
  CheckDraw;
end;

procedure TScroller.SetLimit(Columns, Rows: Integer);
begin
  Limit.X := Columns;
  Limit.Y := Rows;
  Inc(DrawLock);
  if HScrollBar <> nil then
    HScrollBar.SetParams(HScrollBar.Value, 0, Columns - Size.X, Size.X - 1, HScrollBar.ArStep);
  if VScrollBar <> nil then
    VScrollBar.SetParams(VScrollBar.Value, 0, Rows - Size.Y, Size.Y - 1, VScrollBar.ArStep);
  Dec(DrawLock);
  CheckDraw;
end;

procedure TScroller.ShowSBar(Bar: TScrollBar);
begin
  if Bar = nil then
    Exit;
  if GetState(sfActive or sfSelected) then
    Bar.Show
  else
    Bar.Hide;
end;

procedure TScroller.SetState(StateBits: Word; TurnOn: Boolean);
begin
  inherited SetState(StateBits, TurnOn);
  if not AnyBit(StateBits, sfActive or sfSelected) then
    Exit;
  ShowSBar(HScrollBar);
  ShowSBar(VScrollBar);
end;

{ TWindowInit }

constructor TWindowInit.Create(const Bounds: TRect; FrameMaker: TCreateFrameFunc);
begin
  inherited Create(Bounds);
  CreateFrame := FrameMaker;
end;

{ TWindow }

constructor TWindow.Create(const Bounds: TRect; const WindowTitle: string; WindowNumber: SmallInt);
begin
  inherited Create(Bounds, @TWindow.InitFrame);
  Setup(WindowTitle, WindowNumber);
end;

constructor TWindow.Create(const Bounds: TRect; const WindowTitle: string; WindowNumber: SmallInt;
  FrameMaker: TCreateFrameFunc);
begin
  inherited Create(Bounds, FrameMaker);
  Setup(WindowTitle, WindowNumber);
end;

{ The body of the constructor: the fields, the state and the frame. }
procedure TWindow.Setup(const WindowTitle: string; WindowNumber: SmallInt);
begin
  Flags := wfMove + wfGrow + wfClose + wfZoom;
  ZoomRect := GetBounds;
  Number := WindowNumber;
  Palette := wpBlueWindow;
  Frame := nil;
  Title := NewStr(WindowTitle);

  GrowMode := gfGrowAll or gfGrowRel;
  Options := Options or ofSelectable or ofTopSelect;
  State := State or sfShadow;

  if not Assigned(CreateFrame) then
    Exit;
  Frame := CreateFrame(GetExtent);
  if Frame <> nil then
    Insert(Frame);
end;

destructor TWindow.Destroy;
begin
  if Title <> nil then
    FreeMem(Title);
  inherited Destroy;
end;

procedure TWindow.Close;
begin
  if not Valid(cmClose) then
    Exit;
  { The frame is not used after it is destroyed with the window. }
  Frame := nil;
  TvObject.DestroyObject(Self);
end;

procedure TWindow.ShutDown;
begin
  Frame := nil;
  inherited ShutDown;
end;

function TWindow.GetPalette: TPalette;
begin
  Result := WindowPalettes[Palette];
end;

function TWindow.GetTitle(RoomLeft: SmallInt): PAnsiChar;
begin
  Result := Title;
end;

{ A command that reaches a window. }
procedure WindowCommand(Win: TWindow; var Event: TEvent);
var
  dragLimits: TRect;
  smallest, largest: TPoint;
  moveOrGrow: Word;
  forMe: Boolean;
  target: Pointer;
begin
  target := Event.Message.InfoPtr;
  forMe := True;
  if target <> nil then
    forMe := target = Pointer(Win);
  case Event.Message.Command of
    cmResize:
      begin
        moveOrGrow := Win.Flags and (wfMove or wfGrow);
        if moveOrGrow = 0 then
          Exit;
        dragLimits := Win.Owner.GetExtent;
        Win.SizeLimits(smallest, largest);
        Win.DragView(Event, Byte(Win.DragMode or moveOrGrow), dragLimits, smallest, largest);
        Win.ClearEvent(Event);
      end;
    cmClose:
      begin
        if not (AnyBit(Win.Flags, wfClose) and forMe) then
          Exit;
        Win.ClearEvent(Event);
        if not AnyBit(Win.State, sfModal) then
        begin
          Win.Close;
          Exit;
        end;
        PostCommand(Win, Event, cmCancel, Event.Message.InfoPtr);
      end;
    cmZoom:
      begin
        if not (AnyBit(Win.Flags, wfZoom) and forMe) then
          Exit;
        Win.Zoom;
        Win.ClearEvent(Event);
      end;
  end;
end;

procedure TWindow.HandleEvent(var Event: TEvent);
var
  eventKind: Word;
  goBackwards: Boolean;
begin
  inherited HandleEvent(Event);
  eventKind := Event.What;
  if eventKind = evCommand then
    WindowCommand(Self, Event)
  else if eventKind = evKeyDown then
  begin
    goBackwards := Event.KeyDown.KeyCode = kbShiftTab;
    if goBackwards or (Event.KeyDown.KeyCode = kbTab) then
    begin
      FocusNext(goBackwards);
      ClearEvent(Event);
    end;
  end
  else if eventKind = evBroadcast then
  begin
    if (Event.Message.Command = cmSelectWindowNum) and (Event.Message.InfoInt = Number) and
       AnyBit(Options, ofSelectable) then
    begin
      Select;
      ClearEvent(Event);
    end;
  end;
end;

class function TWindow.InitFrame(Area: TRect): TFrame;
begin
  Result := TFrame.Create(Area);
end;

{ The commands that a selected window with the flags enables. }
function WindowCommandsOf(WindowFlags: Byte): TCommandSet;
begin
  Result := TCommandSet.Create;
  Result.EnableCmd(cmNext);
  Result.EnableCmd(cmPrev);
  if AnyBit(WindowFlags, wfGrow or wfMove) then
    Result.EnableCmd(cmResize);
  if AnyBit(WindowFlags, wfClose) then
    Result.EnableCmd(cmClose);
  if AnyBit(WindowFlags, wfZoom) then
    Result.EnableCmd(cmZoom);
end;

procedure TWindow.SetState(StateBits: Word; TurnOn: Boolean);
var
  commandsToSet: TCommandSet;
begin
  inherited SetState(StateBits, TurnOn);
  if not AnyBit(StateBits, sfSelected) then
    Exit;

  SetState(sfActive, TurnOn);
  if Frame <> nil then
    Frame.SetState(sfActive, TurnOn);
  commandsToSet := WindowCommandsOf(Flags);
  if TurnOn then
    EnableCommands(commandsToSet)
  else
    DisableCommands(commandsToSet);
end;

function TWindow.StandardScrollBar(ScrollOptions: Word): TScrollBar;
var
  whole, barArea: TRect;
  newBar: TScrollBar;
begin
  whole := GetExtent;
  if AnyBit(ScrollOptions, sbVertical) then
    barArea := TRect.Create(whole.B.X - 1, whole.A.Y + 1, whole.B.X, whole.B.Y - 1)
  else
    barArea := TRect.Create(whole.A.X + 2, whole.B.Y - 1, whole.B.X - 2, whole.B.Y);

  newBar := TScrollBar.Create(barArea);
  Insert(newBar);
  if AnyBit(ScrollOptions, sbHandleKeyboard) then
    newBar.Options := newBar.Options or ofPostProcess;
  Result := newBar;
end;

procedure TWindow.SizeLimits(var Smallest, Largest: TPoint);
begin
  inherited SizeLimits(Smallest, Largest);
  Smallest := SmallestWindow;
end;

procedure TWindow.Zoom;
var
  smallest, largest: TPoint;
  fullArea: TRect;
begin
  SizeLimits(smallest, largest);
  if Size = largest then
  begin
    Locate(ZoomRect);
    Exit;
  end;
  ZoomRect := GetBounds;
  fullArea := TRect.Create(0, 0, largest.X, largest.Y);
  Locate(fullArea);
end;

procedure FillTables;
var
  index: Integer;
begin
  FillChar(TFrame.InitFrame, SizeOf(TFrame.InitFrame), 0);
  for index := 1 to Length(InitFrameValues) do
    TFrame.InitFrame[index - 1] := InitFrameValues[index];
  FillChar(TFrame.FrameChars, SizeOf(TFrame.FrameChars), 0);
  for index := 1 to Length(FrameCharsValues) do
    TFrame.FrameChars[index - 1] := FrameCharsValues[index];
  TFrame.CloseIcon := '[~' + Chr(254) + '~]';
  TFrame.ZoomIcon := '[~' + Chr(24) + '~]';
  TFrame.UnZoomIcon := '[~' + Chr(18) + '~]';
  TFrame.DragIcon := '~' + Chr(196) + Chr(217) + '~';
  TFrame.DragLeftIcon := '~' + Chr(192) + Chr(196) + '~';
  for index := 1 to Length(VCharsValues) do
  begin
    TScrollBar.VChars[index - 1] := VCharsValues[index];
    TScrollBar.HChars[index - 1] := HCharsValues[index];
  end;
end;

initialization
  FillTables;
  FramePalette := TPalette.Create(cpFrame, Length(cpFrame));
  ScrollBarPalette := TPalette.Create(cpScrollBar, Length(cpScrollBar));
  ScrollerPalette := TPalette.Create(cpScroller, Length(cpScroller));
  WindowPalettes[0] := TPalette.Create(cpBlueWindow, Length(cpBlueWindow));
  WindowPalettes[1] := TPalette.Create(cpCyanWindow, Length(cpCyanWindow));
  WindowPalettes[2] := TPalette.Create(cpGrayWindow, Length(cpGrayWindow));

finalization
  FramePalette.Free;
  ScrollBarPalette.Free;
  ScrollerPalette.Free;
  WindowPalettes[0].Free;
  WindowPalettes[1].Free;
  WindowPalettes[2].Free;

end.
