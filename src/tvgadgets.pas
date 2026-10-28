{ Two small one-row views that show a value of the system: a clock (TClockView) and the memory in use by the
  program (THeapView). The program calls Update of each view from its idle handler or a timer; a view repaints
  only when its text has changed. Both draw one row of text on a background of blanks, in the colour of
  palette entry 1 of the view. The views are used by the thread of the user interface only. }
unit TvGadgets;

{$mode objfpc}
{$H+}

interface

uses
  SysUtils, TvGeom, TvColors, TvEvents, TvDrawBuf, TvViews;

type
  TClockView = class;

  TClockFormat = function(H, M, S: Word; Seconds, Separator, Hour12: Boolean): AnsiString;
  TClockClick = procedure(Sender: TClockView; var Event: TEvent) of object;
  TClockNowFunc = function: TDateTime;
  THeapValueFunc = function: Int64;

  TClockView = class(TView)
  private
    OwnPalette: TPalette;
    OwnPaletteSource: ShortString;
  public
    ShowSeconds: Boolean;
    BlinkSeparator: Boolean;
    Hour12: Boolean;
    AutoSize: Boolean;
    RightAlign: Boolean;
    Margin: Integer;
    FormatHook: TClockFormat;
    OnClick: TClockClick;
    PaletteStr: ShortString;
    TimeStr: AnsiString;
    constructor Create(const Bounds: TRect);
    destructor Destroy; override;
    function GetPalette: TPalette; override;
    function ClockText: AnsiString; virtual;
    { The program calls it; TView has no such method, so it is introduced here. }
    procedure Update; virtual;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    function MsToNextChange: Integer;
    procedure FitWidth(W: Integer);
  end;

  THeapView = class(TView)
  private
    OwnPalette: TPalette;
    OwnPaletteSource: ShortString;
  public
    Kb: Boolean;
    ValueHook: THeapValueFunc;
    PaletteStr: ShortString;
    HeapStr: AnsiString;
    constructor Create(const Bounds: TRect);
    constructor CreateKb(const Bounds: TRect);
    destructor Destroy; override;
    function GetPalette: TPalette; override;
    function HeapText: AnsiString; virtual;
    procedure Update; virtual;
    procedure Draw; override;
  end;

function ClockFormatDefault(H, M, S: Word; Seconds, Separator, Hour12: Boolean): AnsiString;
function HeapInUse: Int64;

var
  ClockNow: TClockNowFunc = nil;
  GadgetPalette: ShortString = #2;

implementation

uses
  TvUtf8;

{ Shared helpers }

{ Gives the palette that a view builds from Source. It is rebuilt when Source differs from the one it was
  built from; an empty Source gives nil, which stands for the palette of no entries. }
procedure RefreshPalette(const Source: ShortString; var Cache: TPalette; var CacheSource: ShortString);
begin
  if (Cache <> nil) and (CacheSource = Source) then
    Exit;
  Cache.Free;
  Cache := nil;
  CacheSource := Source;
  if Source = '' then
    Exit;
  Cache := TPalette.Create(string(Source), Length(Source));
end;

{ Writes row 0 of View: blanks over the whole width, then Text from the left edge or against the right edge. }
procedure DrawGadgetRow(View: TView; const Text: AnsiString; ToRight: Boolean);
var
  Buffer: TDrawBuffer;
  Pair: TAttrPair;
  Attr: TColorAttr;
  ViewWidth, StartX, Room: Integer;
begin
  ViewWidth := View.Size.X;
  if ViewWidth <= 0 then
    Exit;
  Pair := View.GetColor(1);
  Attr := Pair.Attrs[0];
  Buffer := TDrawBuffer.Create;
  try
    Buffer.MoveChar(0, ' ', Attr, ViewWidth);
    if Text <> '' then
    begin
      StartX := 0;
      if ToRight then
      begin
        StartX := ViewWidth - TText.Width(Text);
        if StartX < 0 then
          StartX := 0;
      end;
      Room := ViewWidth - StartX;
      if Room > 0 then
        Buffer.MoveStr(StartX, Text, Attr, Room);
    end;
    View.WriteLine(0, 0, ViewWidth, 1, Buffer);
  finally
    Buffer.Free;
  end;
end;

function TwoDigits(Value: Word): AnsiString;
begin
  Result := IntToStr(Value);
  if Value < 10 then
    Result := '0' + Result;
end;

function CurrentTime: TDateTime;
begin
  if Assigned(ClockNow) then
    Result := ClockNow()
  else
    Result := Now;
end;

{ Public routines }

function ClockFormatDefault(H, M, S: Word; Seconds, Separator, Hour12: Boolean): AnsiString;
var
  HourText: AnsiString;
  Suffix: AnsiString;
  ShownHour: Word;
begin
  Suffix := '';
  if Hour12 then
  begin
    ShownHour := H mod 12;
    if ShownHour = 0 then
      ShownHour := 12;
    HourText := IntToStr(ShownHour);
    if Length(HourText) < 2 then
      HourText := ' ' + HourText;
    if H < 12 then
      Suffix := 'am'
    else
      Suffix := 'pm';
  end
  else
    HourText := TwoDigits(H);

  Result := HourText;
  if Separator then
    Result := Result + ':'
  else
    Result := Result + ' ';
  Result := Result + TwoDigits(M);
  if Seconds then
    Result := Result + ':' + TwoDigits(S);
  Result := Result + Suffix;
end;

function HeapInUse: Int64;
begin
  Result := Int64(GetFPCHeapStatus.CurrHeapUsed);
end;

{ TClockView }

constructor TClockView.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  ShowSeconds := True;
  AutoSize := True;
  BlinkSeparator := False;
  Hour12 := False;
  RightAlign := False;
  Margin := 0;
  FormatHook := nil;
  OnClick := nil;
  TimeStr := '';
  PaletteStr := GadgetPalette;
  EventMask := EventMask or evMouseDown;
end;

destructor TClockView.Destroy;
begin
  OwnPalette.Free;
  OwnPalette := nil;
  inherited Destroy;
end;

function TClockView.GetPalette: TPalette;
begin
  RefreshPalette(PaletteStr, OwnPalette, OwnPaletteSource);
  if OwnPalette = nil then
    Result := inherited GetPalette
  else
    Result := OwnPalette;
end;

function TClockView.ClockText: AnsiString;
var
  Hour, Minute, Second, Milli: Word;
  Separator: Boolean;
begin
  DecodeTime(CurrentTime, Hour, Minute, Second, Milli);
  Separator := (not BlinkSeparator) or ShowSeconds or (Milli < 500);
  if Assigned(FormatHook) then
    Result := FormatHook(Hour, Minute, Second, ShowSeconds, Separator, Hour12)
  else
    Result := ClockFormatDefault(Hour, Minute, Second, ShowSeconds, Separator, Hour12);
  if Margin > 0 then
    Result := StringOfChar(' ', Margin) + Result + StringOfChar(' ', Margin);
end;

function TClockView.MsToNextChange: Integer;
var
  Hour, Minute, Second, Milli: Word;
begin
  DecodeTime(CurrentTime, Hour, Minute, Second, Milli);
  if BlinkSeparator and not ShowSeconds then
    Result := 500 - (Integer(Milli) mod 500)
  else if ShowSeconds then
    Result := 1000 - Integer(Milli)
  else
    Result := (60 - Integer(Second)) * 1000 - Integer(Milli);
end;

procedure TClockView.FitWidth(W: Integer);
var
  Wanted: TRect;
begin
  Wanted := GetBounds;
  if RightAlign and (Owner <> nil) then
  begin
    Wanted.B.X := Owner.Size.X;
    Wanted.A.X := Wanted.B.X - W;
  end
  else if (Owner <> nil) and (Origin.X + Size.X div 2 > Owner.Size.X div 2) then
    Wanted.A.X := Wanted.B.X - W
  else
    Wanted.B.X := Wanted.A.X + W;

  if (Wanted.A.X = Origin.X) and (Wanted.B.X = Origin.X + Size.X) then
    Exit;

  if Owner <> nil then
    Locate(Wanted)
  else
    SetBounds(Wanted);
end;

procedure TClockView.Update;
var
  NewText: AnsiString;
begin
  NewText := ClockText;
  if NewText = TimeStr then
  begin
    if RightAlign and (Owner <> nil) and (Origin.X + Size.X <> Owner.Size.X) then
      FitWidth(Size.X);
    Exit;
  end;

  TimeStr := NewText;
  if AutoSize then
    FitWidth(TText.Width(NewText))
  else if RightAlign then
    FitWidth(Size.X);
  DrawView;
end;

procedure TClockView.Draw;
begin
  DrawGadgetRow(Self, TimeStr, False);
end;

procedure TClockView.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evMouseDown) and Assigned(OnClick) then
    OnClick(Self, Event);
end;

{ THeapView }

constructor THeapView.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  Kb := False;
  ValueHook := nil;
  HeapStr := '';
  PaletteStr := GadgetPalette;
end;

constructor THeapView.CreateKb(const Bounds: TRect);
begin
  Create(Bounds);
  Kb := True;
end;

destructor THeapView.Destroy;
begin
  OwnPalette.Free;
  OwnPalette := nil;
  inherited Destroy;
end;

function THeapView.GetPalette: TPalette;
begin
  RefreshPalette(PaletteStr, OwnPalette, OwnPaletteSource);
  if OwnPalette = nil then
    Result := inherited GetPalette
  else
    Result := OwnPalette;
end;

function THeapView.HeapText: AnsiString;
var
  Value: Int64;
begin
  if Assigned(ValueHook) then
    Value := ValueHook()
  else
    Value := HeapInUse;
  if Kb then
    Result := IntToStr((Value + 1023) div 1024) + 'K'
  else
    Result := IntToStr(Value);
end;

procedure THeapView.Update;
var
  NewText: AnsiString;
begin
  NewText := HeapText;
  if NewText = HeapStr then
    Exit;
  HeapStr := NewText;
  DrawView;
end;

procedure THeapView.Draw;
begin
  if HeapStr = '' then
    HeapStr := HeapText;
  DrawGadgetRow(Self, HeapStr, True);
end;

end.
