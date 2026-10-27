{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/dialogs.h (the button flags, TDialog, TButton, TStaticText, TParamText, TLabel),
  include/tvision/ttypes.h (specialChars), source/tvision/tdialog.cpp, source/tvision/tbutton.cpp,
  source/tvision/tstatict.cpp, source/tvision/tparamte.cpp, source/tvision/tlabel.cpp,
  source/tvision/tvtext1.cpp (specialChars and the tables of TButton)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit. The classes of dialogs.h that are not named above belong to other units.

  Parts of the C++ that have no unit yet:
    - message() sends a message to a view; MessageHook of TvViews stands for it and does nothing while it is nil;
    - hotKey() returns the letter that a label or a button of a text marks with tildes; HotKeyHook stands for it. While
      it is nil no text has a hot key, so a label and a button answer to no letter.

  The text of a view is a block of characters with a terminating zero, as the C++ keeps it, and nil stands for no
  text. A string of this library is a short string, so a text is at most 255 characters long. The text of a
  TParamText is a block of 256 characters, and SetText cuts the formatted text to 255 characters. The format of
  SetText is the one of FormatStr of TvUtil, and its arguments are an array of const.

  The tables shadows and markers of TButton are the class variables Shadows and Markers, and specialChars is the
  variable SpecialChars; they get their C++ values when the unit starts, in code page 437, and a program may change
  them.

  TParamText has no text of the base class: the constructor of TStaticText makes a block for an empty text, and
  TParamText gives it back so that Text is nil, as the C++ constructor that passes no text leaves it. Valid of
  TDialog calls the Valid of the class above it, which is the one of TGroup because TWindow does not change it. }
unit TvDialog;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvColors, TvDrawBuf, TvTimer, TvViews, TvWindow;

const
  { The flags of a TButton. }
  bfNormal = Word($00);
  bfDefault = Word($01);
  bfLeftJust = Word($02);
  bfBroadcast = Word($04);
  bfGrabFocus = Word($08);

  { The command that a button broadcasts before it acts, and the two commands that move the default button. }
  cmRecordHistory = Word(60);
  cmGrabDefault = Word(61);
  cmReleaseDefault = Word(62);

  { The palettes of a dialog: the entries of the palette of its owner that the 32 entries of its own palette
    stand for. }
  cpGrayDialog = #$20#$21#$22#$23#$24#$25#$26#$27#$28#$29#$2A#$2B#$2C#$2D#$2E#$2F +
    #$30#$31#$32#$33#$34#$35#$36#$37#$38#$39#$3A#$3B#$3C#$3D#$3E#$3F;
  cpBlueDialog = #$40#$41#$42#$43#$44#$45#$46#$47#$48#$49#$4A#$4B#$4C#$4D#$4E#$4F +
    #$50#$51#$52#$53#$54#$55#$56#$57#$58#$59#$5A#$5B#$5C#$5D#$5E#$5F;
  cpCyanDialog = #$60#$61#$62#$63#$64#$65#$66#$67#$68#$69#$6A#$6B#$6C#$6D#$6E#$6F +
    #$70#$71#$72#$73#$74#$75#$76#$77#$78#$79#$7A#$7B#$7C#$7D#$7E#$7F;
  cpDialog = cpGrayDialog;

  { The values of TDialog.Palette. }
  dpBlueDialog = 0;
  dpCyanDialog = 1;
  dpGrayDialog = 2;

type
  { The function that returns the hot key of a text: the upper case letter after the first tilde, or #0. }
  THotKeyFunc = function(const Text: string): Char;

  { A window that holds controls and ends its modal loop at cmOK, cmCancel, cmYes and cmNo. The palette is the one
    of dialogs.h: 1 frame passive, 2 frame active, 3 frame icon, 4 scroll bar page area, 5 scroll bar controls,
    6 static text, 7 to 9 label, 10 to 15 button, 16 to 18 cluster, 19 to 21 input line, 22 and 23 history,
    24 and 25 history window scroll bar, 26 to 29 list viewer, 30 info pane, 31 cluster disabled, 32 reserved. }
  TDialog = class(TWindow)
  public
    constructor Create(const Bounds: TRect; const ATitle: string); reintroduce;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Valid(Command: Word): Boolean; override;
  end;

  { A text that is drawn over the lines of the view. The text may hold the character 3 at the start of a line, which
    centres the line, and the character 10, which ends a line. The palette is: 1 text. }
  TStaticText = class(TView)
  protected
    Text: PAnsiChar;
  public
    constructor Create(const Bounds: TRect; const AText: string);
    destructor Destroy; override;
    procedure Draw; override;
    function GetPalette: TPalette; override;
    { Copies the text into Dest, which has room for 256 characters; the copy is cut at 255 characters. }
    procedure GetText(Dest: PAnsiChar); virtual;
  end;

  { A static text that is set at run time. The palette is: 1 text. }
  TParamText = class(TStaticText)
  protected
    Str: PAnsiChar;
  public
    constructor Create(const Bounds: TRect); reintroduce;
    destructor Destroy; override;
    procedure GetText(Dest: PAnsiChar); override;
    procedure SetText(const Fmt: string; const Args: array of const); virtual;
    function GetTextLen: Integer; virtual;
  end;

  { A text that moves the focus to another view. The palette is: 1 normal text, 2 selected text, 3 normal shortcut,
    4 selected shortcut. }
  TLabel = class(TStaticText)
  protected
    Link: TView;
    Light: Boolean;
  private
    procedure FocusLink(var Event: TEvent);
  public
    constructor Create(const Bounds: TRect; const AText: string; ALink: TView); reintroduce;
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ShutDown; override;
  end;

  { A push button. The palette is: 1 normal, 2 default, 3 selected, 4 disabled, 5 normal shortcut, 6 default
    shortcut, 7 selected shortcut, 8 shadow. }
  TButton = class(TView)
  private
    AnimationTimer: TTimerId;
    procedure DrawTitle(LineBuffer: TDrawBuffer; TotalWidth, Indent: Integer; const Tints: TAttrPair;
      Down: Boolean);
    procedure StartAnimation;
    function FaceRect: TRect;
    procedure TrackMouse(var Event: TEvent; FaceArea: TRect);
    procedure HandleKeyDown(var Event: TEvent; HotChar: Char);
    procedure HandleBroadcast(var Event: TEvent);
  protected
    Command: Word;
    Flags: Byte;
    AmDefault: Boolean;
  public
    Title: PAnsiChar;
    { The three characters of the shadow (the top right cell, the other cells of the right column, the bottom
      row) and the two characters of the markers. }
    class var Shadows: string;
    class var Markers: string;

    constructor Create(const Bounds: TRect; const ATitle: string; ACommand, AFlags: Word);
    destructor Destroy; override;
    procedure Draw; override;
    procedure DrawState(Down: Boolean);
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure MakeDefault(Enable: Boolean);
    procedure Press; virtual;
    procedure SetState(AState: Word; Enable: Boolean); override;
  end;

var
  { The characters that mark a selected, a default and a normal control: left and right of each pair. }
  SpecialChars: array[0..5] of Byte = (175, 174, 26, 27, 32, 32);
  HotKeyHook: THotKeyFunc;

implementation

uses
  Strings, TvKeys, TvUtf8, TvUtil;

const
  cpStaticText = #6;
  cpLabel = #7#8#9#9;
  cpButton = #10#11#12#13#14#14#14#15;

  AnimationDurationMs = 100;

var
  StaticTextPalette: TPalette;
  LabelPalette: TPalette;
  ButtonPalette: TPalette;
  DialogPalettes: array[0..2] of TPalette;

{ Tells whether any bit of Mask is set in Bits. }
function AnyBit(Bits, Mask: Word): Boolean;
begin
  Result := (Bits and Mask) <> 0;
end;

{ Sends a message through the hook; nothing happens while there is none. }
procedure Notify(Target: TView; Kind, Code: Word; Payload: Pointer);
begin
  if MessageHook = nil then
    Exit;
  MessageHook(Target, Kind, Code, Payload);
end;

{ The hot key of the text at Source; #0 while there is no hook or no text. }
function HotKeyOf(Source: PAnsiChar): Char;
begin
  Result := #0;
  if not Assigned(HotKeyHook) then
    Exit;
  Result := HotKeyHook(StrPas(Source));
end;

{ The character at the zero based position Offset of Content; #0 outside the text. }
function ByteAt(const Content: string; Offset: Integer): Char;
begin
  Result := #0;
  if (Offset < 0) or (Offset >= Length(Content)) then
    Exit;
  Result := Content[Offset + 1];
end;

{ TDialog }

constructor TDialog.Create(const Bounds: TRect; const ATitle: string);
begin
  inherited Create(Bounds, ATitle, wnNoNumber);
  GrowMode := 0;
  Flags := Byte(wfMove or wfClose);
  Palette := dpGrayDialog;
end;

function TDialog.GetPalette: TPalette;
begin
  case Palette of
    dpBlueDialog: Result := DialogPalettes[0];
    dpCyanDialog: Result := DialogPalettes[1];
  else
    Result := DialogPalettes[2];
  end;
end;

{ Turns Event into the event of kind Kind with the command Code and no information, puts it back and clears it. }
procedure ReissueEvent(Dialog: TDialog; var Event: TEvent; Kind, Code: Word);
begin
  Event.What := Kind;
  Event.Message.Command := Code;
  Event.Message.InfoPtr := nil;
  Dialog.PutEvent(Event);
  Dialog.ClearEvent(Event);
end;

procedure TDialog.HandleEvent(var Event: TEvent);
var
  incomingCommand: Word;
  closesDialog: Boolean;
begin
  inherited HandleEvent(Event);
  if Event.What = evKeyDown then
  begin
    if Event.KeyDown.KeyCode = kbEsc then
      ReissueEvent(Self, Event, evCommand, cmCancel)
    else if Event.KeyDown.KeyCode = kbEnter then
      ReissueEvent(Self, Event, evBroadcast, cmDefault);
    Exit;
  end;
  if Event.What <> evCommand then
    Exit;
  incomingCommand := Event.Message.Command;
  closesDialog := False;
  case incomingCommand of
    cmOK, cmCancel, cmYes, cmNo: closesDialog := True;
  end;
  if not (closesDialog and AnyBit(State, sfModal)) then
    Exit;
  EndModal(incomingCommand);
  ClearEvent(Event);
end;

function TDialog.Valid(Command: Word): Boolean;
begin
  if Command = cmCancel then
  begin
    Result := True;
    Exit;
  end;
  Result := inherited Valid(Command);
end;

{ TStaticText }

constructor TStaticText.Create(const Bounds: TRect; const AText: string);
begin
  inherited Create(Bounds);
  Text := NewStr(AText);
  GrowMode := GrowMode or gfFixed;
end;

destructor TStaticText.Destroy;
begin
  if Text <> nil then
    FreeMem(Text);
  inherited Destroy;
end;

{ Lays out the line of Content that starts at Offset into Buffer and moves Offset to the start of the next line.
  A line is as many words as fit in ViewWidth columns; a word that is wider than the view is cut. }
procedure LayoutLine(const Content: string; ViewWidth: Integer; var Offset: Integer; var Centered: Boolean;
  Buffer: TDrawBuffer; Attr: TColorAttr);
var
  contentLength, lineStart, fitEnd, wordStart, lineWidth, column: Integer;
  keepScanning: Boolean;
  lineText: string;
begin
  contentLength := Length(Content);
  if ByteAt(Content, Offset) = #3 then
  begin
    Centered := True;
    Inc(Offset);
  end;
  lineStart := Offset;
  fitEnd := lineStart + TText.Scroll(Copy(Content, lineStart + 1, 255), ViewWidth, False);
  repeat
    wordStart := Offset;
    while (Offset < contentLength) and (ByteAt(Content, Offset) = ' ') do
      Inc(Offset);
    while (Offset < contentLength) and (ByteAt(Content, Offset) <> ' ') and (ByteAt(Content, Offset) <> #10) do
      Inc(Offset, TText.Next(Copy(Content, Offset + 1, 255)));
    keepScanning := (Offset < contentLength) and (Offset < fitEnd) and (ByteAt(Content, Offset) <> #10);
  until not keepScanning;

  if Offset > fitEnd then
  begin
    if wordStart > lineStart then
      Offset := wordStart
    else
      Offset := fitEnd;
  end;

  lineText := Copy(Content, lineStart + 1, Offset - lineStart);
  lineWidth := Strwidth(lineText);
  if Centered then
    column := (ViewWidth - lineWidth) div 2
  else
    column := 0;
  Buffer.MoveStr(Word(column), Copy(Content, lineStart + 1, 255), Attr, Word(lineWidth));

  while (Offset < contentLength) and (ByteAt(Content, Offset) = ' ') do
    Inc(Offset);
  if ByteAt(Content, Offset) = #10 then
  begin
    Centered := False;
    Inc(Offset);
  end;
end;

procedure TStaticText.Draw;
var
  tints: TAttrPair;
  textAttr: TColorAttr;
  lineBuffer: TDrawBuffer;
  copied: array[0..255] of AnsiChar;
  content, wholeText: string;
  offset, row: Integer;
  centered: Boolean;
begin
  tints := GetColor(1);
  textAttr := tints.Attrs[0];
  GetText(@copied[0]);
  content := StrPas(@copied[0]);
  if Text <> nil then
  begin
    wholeText := StrPas(Text);
    if Copy(wholeText, 1, Length(content)) = content then
      content := wholeText;
  end;

  offset := 0;
  row := 0;
  centered := False;
  lineBuffer := TDrawBuffer.Create;
  try
    while row < Size.Y do
    begin
      lineBuffer.MoveChar(0, ' ', textAttr, Word(Size.X));
      if offset < Length(content) then
        LayoutLine(content, Size.X, offset, centered, lineBuffer, textAttr);
      WriteLine(0, row, Size.X, 1, lineBuffer);
      Inc(row);
    end;
  finally
    lineBuffer.Free;
  end;
end;

function TStaticText.GetPalette: TPalette;
begin
  Result := StaticTextPalette;
end;

procedure TStaticText.GetText(Dest: PAnsiChar);
begin
  if Text = nil then
  begin
    Dest^ := #0;
    Exit;
  end;
  StrLCopy(Dest, Text, 255);
  Dest[255] := #0;
end;

{ TParamText }

constructor TParamText.Create(const Bounds: TRect);
begin
  inherited Create(Bounds, '');
  if Text <> nil then
  begin
    FreeMem(Text);
    Text := nil;
  end;
  GetMem(Str, 256);
  Str[0] := #0;
end;

destructor TParamText.Destroy;
begin
  if Str <> nil then
    FreeMem(Str);
  inherited Destroy;
end;

procedure TParamText.GetText(Dest: PAnsiChar);
begin
  if Str = nil then
  begin
    Dest^ := #0;
    Exit;
  end;
  StrCopy(Dest, Str);
end;

function TParamText.GetTextLen: Integer;
begin
  Result := 0;
  if Str = nil then
    Exit;
  Result := StrLen(Str);
end;

procedure TParamText.SetText(const Fmt: string; const Args: array of const);
var
  formatted: string;
  keptLength: Integer;
begin
  formatted := FormatStr(Fmt, Args);
  keptLength := Length(formatted);
  if keptLength > 255 then
    keptLength := 255;
  if keptLength > 0 then
    Move(formatted[1], Str^, keptLength);
  Str[keptLength] := #0;
  DrawView;
end;

{ TLabel }

constructor TLabel.Create(const Bounds: TRect; const AText: string; ALink: TView);
begin
  inherited Create(Bounds, AText);
  Link := ALink;
  Light := False;
  Options := Options or ofPreProcess or ofPostProcess;
  EventMask := EventMask or evBroadcast;
end;

procedure TLabel.ShutDown;
begin
  Link := nil;
  inherited ShutDown;
end;

procedure TLabel.Draw;
var
  tints: TAttrPair;
  lineBuffer: TDrawBuffer;
  markerIndex: Integer;
begin
  if Light then
  begin
    tints := GetColor($0402);
    markerIndex := 0;
  end
  else
  begin
    tints := GetColor($0301);
    markerIndex := 4;
  end;

  lineBuffer := TDrawBuffer.Create;
  try
    lineBuffer.MoveChar(0, ' ', tints.Attrs[0], Word(Size.X));
    if Text <> nil then
      lineBuffer.MoveCStr(1, StrPas(Text), tints);
    if ShowMarkers then
      lineBuffer.PutChar(0, SpecialChars[markerIndex]);
    WriteLine(0, 0, Size.X, 1, lineBuffer);
  finally
    lineBuffer.Free;
  end;
end;

function TLabel.GetPalette: TPalette;
begin
  Result := LabelPalette;
end;

procedure TLabel.FocusLink(var Event: TEvent);
begin
  if (Link <> nil) and AnyBit(Link.Options, ofSelectable) then
    Link.Focus;
  ClearEvent(Event);
end;

procedure TLabel.HandleEvent(var Event: TEvent);
var
  hotChar: Char;
  pressedCode: Word;
  matchesAlt, matchesLetter, isFocusChange: Boolean;
begin
  inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      FocusLink(Event);
    evKeyDown:
      begin
        hotChar := HotKeyOf(Text);
        pressedCode := Event.KeyDown.KeyCode;
        if pressedCode = 0 then
          Exit;
        matchesAlt := GetAltCode(hotChar) = pressedCode;
        matchesLetter := False;
        if (not matchesAlt) and (hotChar <> #0) then
          matchesLetter := (Owner.Phase = phPostProcess) and
            (hotChar = UpCase(Char(Event.KeyDown.CharScan.CharCode)));
        if matchesAlt or matchesLetter then
          FocusLink(Event);
      end;
    evBroadcast:
      begin
        if Link = nil then
          Exit;
        isFocusChange := (Event.Message.Command = cmReceivedFocus) or (Event.Message.Command = cmReleasedFocus);
        if not isFocusChange then
          Exit;
        Light := AnyBit(Link.State, sfFocused);
        DrawView;
      end;
  end;
end;

{ TButton }

constructor TButton.Create(const Bounds: TRect; const ATitle: string; ACommand, AFlags: Word);
const
  ButtonOptions = ofSelectable or ofFirstClick or ofPreProcess or ofPostProcess;
begin
  inherited Create(Bounds);
  AnimationTimer := nil;
  Title := NewStr(ATitle);
  Command := ACommand;
  Flags := Byte(AFlags);
  AmDefault := AnyBit(AFlags, bfDefault);
  Options := Options or ButtonOptions;
  EventMask := EventMask or evBroadcast;
  if CommandEnabled(ACommand) then
    Exit;
  State := State or sfDisabled;
end;

destructor TButton.Destroy;
begin
  if Title <> nil then
    FreeMem(Title);
  KillTimer(AnimationTimer);
  inherited Destroy;
end;

procedure TButton.Draw;
begin
  DrawState(False);
end;

procedure TButton.DrawTitle(LineBuffer: TDrawBuffer; TotalWidth, Indent: Integer; const Tints: TAttrPair;
  Down: Boolean);
var
  titleText: string;
  leftGap, markerIndex: Integer;
begin
  titleText := StrPas(Title);
  if AnyBit(Flags, bfLeftJust) then
    leftGap := 1
  else
  begin
    leftGap := (TotalWidth - Cstrlen(titleText) - 1) div 2;
    if leftGap < 1 then
      leftGap := 1;
  end;
  LineBuffer.MoveCStr(Word(Indent + leftGap), titleText, Tints);

  if (not ShowMarkers) or Down then
    Exit;
  if AnyBit(State, sfSelected) then
    markerIndex := 0
  else if AmDefault then
    markerIndex := 2
  else
    markerIndex := 4;
  LineBuffer.PutChar(0, SpecialChars[markerIndex]);
  LineBuffer.PutChar(Word(TotalWidth), SpecialChars[markerIndex + 1]);
end;

procedure TButton.DrawState(Down: Boolean);
var
  buttonTints, shadowTints: TAttrPair;
  buttonAttr, shadowAttr: TColorAttr;
  lastColumn, titleRow, row, indent: Integer;
  bottomFill: Char;
  lineBuffer: TDrawBuffer;
begin
  if AnyBit(State, sfDisabled) then
    buttonTints := GetColor($0404)
  else
  begin
    buttonTints := GetColor($0501);
    if AnyBit(State, sfActive) then
    begin
      if AnyBit(State, sfSelected) then
        buttonTints := GetColor($0703)
      else if AmDefault then
        buttonTints := GetColor($0602);
    end;
  end;
  shadowTints := GetColor(8);
  buttonAttr := buttonTints.Attrs[0];
  shadowAttr := shadowTints.Attrs[0];

  lastColumn := Size.X - 1;
  titleRow := Size.Y div 2 - 1;
  bottomFill := ' ';
  lineBuffer := TDrawBuffer.Create;
  try
    for row := 0 to Size.Y - 2 do
    begin
      lineBuffer.MoveChar(0, ' ', buttonAttr, Word(Size.X));
      lineBuffer.PutAttribute(0, shadowAttr);
      if Down then
      begin
        lineBuffer.PutAttribute(1, shadowAttr);
        bottomFill := ' ';
        indent := 2;
      end
      else
      begin
        lineBuffer.PutAttribute(Word(lastColumn), shadowAttr);
        if ShowMarkers then
          bottomFill := ' '
        else
        begin
          if row = 0 then
            lineBuffer.PutChar(Word(lastColumn), Ord(Shadows[1]))
          else
            lineBuffer.PutChar(Word(lastColumn), Ord(Shadows[2]));
          bottomFill := Shadows[3];
        end;
        indent := 1;
      end;

      if (row = titleRow) and (Title <> nil) then
        DrawTitle(lineBuffer, lastColumn, indent, buttonTints, Down);

      if ShowMarkers and not Down then
      begin
        lineBuffer.PutChar(1, Ord(Markers[1]));
        lineBuffer.PutChar(Word(lastColumn - 1), Ord(Markers[2]));
      end;
      WriteLine(0, row, Size.X, 1, lineBuffer);
    end;
    lineBuffer.MoveChar(0, ' ', shadowAttr, 2);
    lineBuffer.MoveChar(2, bottomFill, shadowAttr, Word(lastColumn - 1));
    WriteLine(0, Size.Y - 1, Size.X, 1, lineBuffer);
  finally
    lineBuffer.Free;
  end;
end;

function TButton.GetPalette: TPalette;
begin
  Result := ButtonPalette;
end;

{ Draws the button pressed down and, when no animation runs yet, starts the timer that ends it. }
procedure TButton.StartAnimation;
begin
  DrawState(True);
  if AnimationTimer = nil then
    AnimationTimer := SetTimer(AnimationDurationMs);
end;

{ Follows the mouse while a button is held down and presses the button when it is released over the face. }
procedure TButton.TrackMouse(var Event: TEvent; FaceArea: TRect);
var
  position: TPoint;
  shownDown, overFace: Boolean;
begin
  Inc(FaceArea.B.X);
  shownDown := False;
  repeat
    position := MakeLocal(Event.Mouse.Where);
    overFace := FaceArea.Contains(position);
    if overFace <> shownDown then
    begin
      shownDown := overFace;
      DrawState(shownDown);
    end;
  until not MouseEvent(Event, evMouseMove);
  if not shownDown then
    Exit;
  Press;
  DrawState(False);
end;

procedure TButton.HandleKeyDown(var Event: TEvent; HotChar: Char);
var
  pressedCode: Word;
  typedChar: Byte;
  matches: Boolean;
begin
  pressedCode := Event.KeyDown.KeyCode;
  if pressedCode = 0 then
    Exit;
  typedChar := Event.KeyDown.CharScan.CharCode;
  matches := pressedCode = GetAltCode(HotChar);
  if (not matches) and (Owner.Phase = phPostProcess) and (HotChar <> #0) then
    matches := HotChar = UpCase(Char(typedChar));
  if (not matches) and AnyBit(State, sfFocused) then
    matches := typedChar = Ord(' ');
  if not matches then
    Exit;
  StartAnimation;
  ClearEvent(Event);
end;

procedure TButton.HandleBroadcast(var Event: TEvent);
var
  broadcastCommand: Word;
begin
  broadcastCommand := Event.Message.Command;
  if broadcastCommand = cmDefault then
  begin
    if AmDefault and not AnyBit(State, sfDisabled) then
    begin
      StartAnimation;
      ClearEvent(Event);
    end;
  end
  else if (broadcastCommand = cmGrabDefault) or (broadcastCommand = cmReleaseDefault) then
  begin
    if AnyBit(Flags, bfDefault) then
    begin
      AmDefault := broadcastCommand = cmReleaseDefault;
      DrawView;
    end;
  end
  else if broadcastCommand = cmCommandSetChanged then
  begin
    SetState(sfDisabled, not CommandEnabled(Command));
    DrawView;
  end
  else if broadcastCommand = cmTimerExpired then
  begin
    if (AnimationTimer <> nil) and (Event.Message.InfoPtr = AnimationTimer) then
    begin
      AnimationTimer := nil;
      DrawState(False);
      Press;
      ClearEvent(Event);
    end;
  end;
end;

{ The part of the extent that a click presses: one column is left out at each side and the shadow row at the bottom. }
function TButton.FaceRect: TRect;
begin
  Result := GetExtent;
  Result.A.X := Result.A.X + 1;
  Result.B.X := Result.B.X - 1;
  Result.B.Y := Result.B.Y - 1;
end;

procedure TButton.HandleEvent(var Event: TEvent);
var
  hotChar: Char;
  startedOutside: Boolean;
  face: TRect;
begin
  face := FaceRect;
  startedOutside := False;
  if Event.What = evMouseDown then
    startedOutside := not face.Contains(MakeLocal(Event.Mouse.Where));
  if startedOutside then
    ClearEvent(Event);
  if AnyBit(Flags, bfGrabFocus) then
    inherited HandleEvent(Event);

  hotChar := HotKeyOf(Title);
  case Event.What of
    evMouseDown:
      begin
        if not AnyBit(State, sfDisabled) then
          TrackMouse(Event, face);
        ClearEvent(Event);
      end;
    evKeyDown:
      HandleKeyDown(Event, hotChar);
    evBroadcast:
      HandleBroadcast(Event);
  end;
end;

procedure TButton.MakeDefault(Enable: Boolean);
var
  messageCode: Word;
begin
  if AnyBit(Flags, bfDefault) then
    Exit;
  if Enable then
    messageCode := cmGrabDefault
  else
    messageCode := cmReleaseDefault;
  Notify(Owner, evBroadcast, messageCode, Self);
  AmDefault := Enable;
  DrawView;
end;

procedure TButton.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if AnyBit(AState, sfSelected or sfActive) then
    DrawView;
  if AnyBit(AState, sfFocused) then
    MakeDefault(Enable);
end;

procedure TButton.Press;
var
  commandEvent: TEvent;
begin
  Notify(Owner, evBroadcast, cmRecordHistory, nil);
  if AnyBit(Flags, bfBroadcast) then
  begin
    Notify(Owner, evBroadcast, Command, Self);
    Exit;
  end;
  FillChar(commandEvent, SizeOf(commandEvent), 0);
  commandEvent.What := evCommand;
  commandEvent.Message.Command := Command;
  commandEvent.Message.InfoPtr := Self;
  PutEvent(commandEvent);
end;

initialization
  TButton.Shadows := #$DC#$DB#$DF;
  TButton.Markers := '[]';
  StaticTextPalette := TPalette.Create(cpStaticText, Length(cpStaticText));
  LabelPalette := TPalette.Create(cpLabel, Length(cpLabel));
  ButtonPalette := TPalette.Create(cpButton, Length(cpButton));
  DialogPalettes[0] := TPalette.Create(cpBlueDialog, Length(cpBlueDialog));
  DialogPalettes[1] := TPalette.Create(cpCyanDialog, Length(cpCyanDialog));
  DialogPalettes[2] := TPalette.Create(cpGrayDialog, Length(cpGrayDialog));

finalization
  StaticTextPalette.Free;
  LabelPalette.Free;
  ButtonPalette.Free;
  DialogPalettes[0].Free;
  DialogPalettes[1].Free;
  DialogPalettes[2].Free;

end.
