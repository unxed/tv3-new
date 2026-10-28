{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/textview.h, source/tvision/textview.cpp, source/tvision/ttprvlns.cpp,
  include/tvision/views.h (TScroller),
  include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h
  See COPYRIGHT.magiblot.

  TTextDevice is a scroller that takes text, and TTerminal keeps the text in a circular buffer and draws its end.
  The class TTextDevice of the C++ has the bases TScroller and streambuf. A Pascal class has one parent, so
  TTextDevice descends from TScroller and holds a stream buffer of the class TTextDeviceBuf (a TStreamBuf of
  TvStreams) that passes every write to Xsputn; StreamBuf gives that buffer. The stream otstream is an opstream on
  the buffer of a TTerminal. The text is written to it with the members of opstream that write bytes (Put of an
  AnsiChar and WriteBytes), which stand for the operator << of the C++ for characters and blocks.

  The value EOF of the C++ is -1. A char pointer is a PAnsiChar. The members read, write, build and streamableName
  are not translated. The static function findLfBackwards of ttprvlns.cpp is FindLfBackwards inside the unit. }
unit TvTextView;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvColors, TvCell, TvDrawBuf, TvViews, TvWindow, TvStreams;

type
  TTextDevice = class;

  { The stream buffer of a text device: it hands the bytes that are written to it to the device. }
  TTextDeviceBuf = class(TStreamBuf)
  private
    FDevice: TTextDevice;
  protected
    function SeekOff(Off: Int64; Dir, Which: Integer): Int64; override;
    function XSGetN(var Buf; N: SizeInt): SizeInt; override;
    function XSPutN(const Buf; N: SizeInt): SizeInt; override;
  public
    constructor Create(ADevice: TTextDevice);
  end;

  { A scroller that takes text. }
  TTextDevice = class(TScroller)
  private
    FStream: TTextDeviceBuf;
  protected
    { Takes Count bytes at S; the default is Do_sputn. }
    function Xsputn(S: PAnsiChar; Count: SizeInt): SizeInt; virtual;
  public
    constructor Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar);
    destructor Destroy; override;
    { Takes Count bytes at S and returns how many it took. }
    function Do_sputn(S: PAnsiChar; Count: Integer): Integer; virtual; abstract;
    { Takes the byte C unless it is -1 (EOF); returns 1. }
    function Overflow(C: Integer = -1): Integer; virtual;
    { The stream buffer of the device, which the streams of TvStreams use. }
    function StreamBuf: TStreamBuf;
  end;

  { The bytes of a part of a line that Draw hands to the draw buffer at once. }
  TLineChunk = array[0..255] of AnsiChar;

  { A text device that keeps the last part of the text in a circular buffer. The palette is the one of TScroller. }
  TTerminal = class(TTextDevice)
  private
    function CopyLine(StartPos, StopPos: Word; var Chunk: TLineChunk): Integer;
    function TrimChunk(var Chunk: TLineChunk; Len: Integer): Integer;
  protected
    BufSize: Word;
    Buffer: PAnsiChar;
    QueFront, QueBack: Word;
    procedure BufDec(var Val: Word);
  public
    constructor Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar; ABufSize: Word);
    destructor Destroy; override;
    function Do_sputn(S: PAnsiChar; Count: Integer): Integer; override;
    procedure BufInc(var Val: Word);
    function CanInsert(Amount: Word): Boolean;
    procedure Draw; override;
    function NextLine(Pos: Word): Word;
    function PrevLines(Pos, Lines: Word): Word;
    function QueEmpty: Boolean;
  end;

  { An output stream on a TTerminal. }
  otstream = class(opstream)
  public
    constructor Create(ATerminal: TTerminal); overload;
  end;

implementation

uses
  TvUtf8;

const
  { A UTF-8 encoded character is up to 4 bytes long (maxCharSize of config.h). }
  MaxCharSize = 4;

  { The largest size of the buffer of a terminal. }
  LargestBuffer = 32000;

function LeastOf(A, B: Integer): Integer;
begin
  if B < A then
    Result := B
  else
    Result := A;
end;

function GreatestOf(A, B: Integer): Integer;
begin
  if B > A then
    Result := B
  else
    Result := A;
end;

{ TTextDeviceBuf }

constructor TTextDeviceBuf.Create(ADevice: TTextDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

function TTextDeviceBuf.SeekOff(Off: Int64; Dir, Which: Integer): Int64;
begin
  Result := -1;
end;

function TTextDeviceBuf.XSGetN(var Buf; N: SizeInt): SizeInt;
begin
  Result := 0;
end;

function TTextDeviceBuf.XSPutN(const Buf; N: SizeInt): SizeInt;
begin
  Result := FDevice.Xsputn(PAnsiChar(@Buf), N);
end;

{ TTextDevice }

constructor TTextDevice.Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar);
begin
  inherited Create(Bounds, AHScrollBar, AVScrollBar);
  FStream := TTextDeviceBuf.Create(Self);
end;

destructor TTextDevice.Destroy;
begin
  FStream.Free;
  FStream := nil;
  inherited Destroy;
end;

function TTextDevice.Overflow(C: Integer): Integer;
var
  oneByte: AnsiChar;
begin
  if C <> -1 then
  begin
    oneByte := AnsiChar(Byte(C and $FF));
    Do_sputn(@oneByte, 1);
  end;
  Result := 1;
end;

function TTextDevice.Xsputn(S: PAnsiChar; Count: SizeInt): SizeInt;
begin
  Result := Do_sputn(S, Integer(Count));
end;

function TTextDevice.StreamBuf: TStreamBuf;
begin
  Result := FStream;
end;

{ TTerminal }

constructor TTerminal.Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar; ABufSize: Word);
begin
  inherited Create(Bounds, AHScrollBar, AVScrollBar);
  QueFront := 0;
  QueBack := 0;
  BufSize := LeastOf(LargestBuffer, ABufSize);
  GetMem(Buffer, BufSize);
  GrowMode := Byte(gfGrowHiX + gfGrowHiY);
  ShowCursor;
  SetCursor(0, 0);
  SetLimit(0, 1);
end;

destructor TTerminal.Destroy;
begin
  if Buffer <> nil then
    FreeMem(Buffer);
  Buffer := nil;
  inherited Destroy;
end;

procedure TTerminal.BufDec(var Val: Word);
begin
  if Val = 0 then
    Val := Word(Integer(BufSize) - 1)
  else
    Dec(Val);
end;

procedure TTerminal.BufInc(var Val: Word);
begin
  if Integer(Val) + 1 < Integer(BufSize) then
    Val := Word(Integer(Val) + 1)
  else
    Val := 0;
end;

function TTerminal.CanInsert(Amount: Word): Boolean;
var
  limitPos: LongInt;
begin
  if QueFront < QueBack then
    limitPos := LongInt(QueFront) + Amount
  else
    limitPos := LongInt(QueFront) - BufSize + Amount;
  Result := QueBack > limitPos;
end;

{ Copies the bytes from StartPos up to StopPos, which may be behind the end of the buffer, into Chunk, as many as
  Chunk holds; returns their number. }
function TTerminal.CopyLine(StartPos, StopPos: Word; var Chunk: TLineChunk): Integer;
var
  firstLen, secondLen: Integer;
begin
  if StopPos >= StartPos then
  begin
    Result := LeastOf(StopPos - StartPos, SizeOf(Chunk));
    Move(Buffer[StartPos], Chunk[0], Result);
  end
  else
  begin
    firstLen := LeastOf(BufSize - StartPos, SizeOf(Chunk));
    secondLen := LeastOf(StopPos, SizeOf(Chunk) - firstLen);
    Move(Buffer[StartPos], Chunk[0], firstLen);
    Move(Buffer[0], Chunk[firstLen], secondLen);
    Result := firstLen + secondLen;
  end;
end;

{ When Chunk is full, the character at its end may be cut: gives the length that ends at a character boundary. }
function TTerminal.TrimChunk(var Chunk: TLineChunk; Len: Integer): Integer;
var
  tail: AnsiString;
  step: SizeInt;
begin
  Result := Len;
  if Len <> SizeOf(Chunk) then
    Exit;
  Result := 0;
  while Result < SizeOf(Chunk) - (MaxCharSize - 1) do
  begin
    SetString(tail, PAnsiChar(@Chunk[Result]), SizeOf(Chunk) - Result);
    step := TText.Next(tail);
    if step < 1 then
      step := 1;
    Inc(Result, step);
  end;
end;

procedure TTerminal.Draw;
var
  lineBuf: TDrawBuffer;
  chunk: TLineChunk;
  chunkLen: Integer;
  piece: AnsiString;
  attr: TColorAttr;
  colX, rowY, bottomLine: Integer;
  begLine, endLine, linePos: Word;
begin
  attr := MapColor(1);
  SetCursor(-1, -1);

  endLine := QueFront;
  bottomLine := Delta.Y + Size.Y;
  if bottomLine < Limit.Y then
  begin
    endLine := PrevLines(QueFront, Word(Limit.Y - bottomLine));
    BufDec(endLine);
  end;

  lineBuf := TDrawBuffer.Create;
  try
    if Limit.Y > Size.Y then
      rowY := Size.Y - 1
    else
    begin
      lineBuf.MoveChar(0, ' ', attr, Size.X);
      WriteLine(0, Limit.Y, Size.X, Size.Y - Limit.Y, lineBuf);
      rowY := Limit.Y - 1;
    end;

    while rowY >= 0 do
    begin
      colX := 0;
      begLine := PrevLines(endLine, 1);
      linePos := begLine;
      while linePos <> endLine do
      begin
        chunkLen := CopyLine(linePos, endLine, chunk);
        chunkLen := TrimChunk(chunk, chunkLen);
        if chunkLen <= 0 then
          Break;
        if Integer(linePos) >= Integer(BufSize) - chunkLen then
          linePos := Word(chunkLen - (Integer(BufSize) - Integer(linePos)))
        else
          linePos := Word(Integer(linePos) + chunkLen);

        SetString(piece, PAnsiChar(@chunk[0]), chunkLen);
        colX := colX + lineBuf.MoveStr(colX, piece, attr);
      end;

      lineBuf.MoveChar(colX, ' ', attr, GreatestOf(Size.X - colX, 0));
      WriteBuf(0, rowY, Size.X, 1, lineBuf);
      if endLine = QueFront then
        SetCursor(colX, rowY);
      endLine := begLine;
      BufDec(endLine);
      Dec(rowY);
    end;
  finally
    lineBuf.Free;
  end;
end;

function TTerminal.NextLine(Pos: Word): Word;
begin
  Result := Pos;
  while Result <> QueFront do
  begin
    if Buffer[Result] = #10 then
    begin
      BufInc(Result);
      Break;
    end;
    BufInc(Result);
  end;
end;

{ Looks for a line end among Count bytes going back from Pos; Pos is left at the last byte that was checked.
  Pre: Count >= 1. }
function FindLfBackwards(Text: PAnsiChar; var Pos: Word; Count: Word): Boolean;
begin
  Inc(Pos);
  repeat
    Dec(Pos);
    if Text[Pos] = #10 then
    begin
      Result := True;
      Exit;
    end;
    Dec(Count);
  until Count = 0;
  Result := False;
end;

function TTerminal.PrevLines(Pos, Lines: Word): Word;
var
  span: Word;
begin
  if (Lines > 0) and (Pos <> QueBack) then
  begin
    repeat
      if Pos = QueBack then
      begin
        Result := QueBack;
        Exit;
      end;
      BufDec(Pos);
      if Pos >= QueBack then
        span := Pos - QueBack + 1
      else
        span := Pos + 1;
      if FindLfBackwards(Buffer, Pos, span) then
        Dec(Lines);
    until Lines = 0;
    BufInc(Pos);
  end;
  Result := Pos;
end;

function TTerminal.Do_sputn(S: PAnsiChar; Count: Integer): Integer;
var
  screenLines: Word;
  idx, headLen: Integer;
begin
  screenLines := Limit.Y;
  if Count < 0 then
    Count := 0;

  if Count > Integer(BufSize) - 1 then
  begin
    Inc(S, Count - (Integer(BufSize) - 1));
    Count := Integer(BufSize) - 1;
  end;

  for idx := 0 to Count - 1 do
    if S[idx] = #10 then
      Inc(screenLines);

  while not CanInsert(Word(Count)) do
  begin
    QueBack := NextLine(QueBack);
    if screenLines > 1 then
      Dec(screenLines);
  end;

  if Integer(QueFront) + Count >= Integer(BufSize) then
  begin
    headLen := Integer(BufSize) - Integer(QueFront);
    Move(S[0], Buffer[QueFront], headLen);
    Move(S[headLen], Buffer[0], Count - headLen);
    QueFront := Word(Count - headLen);
  end
  else
  begin
    Move(S[0], Buffer[QueFront], Count);
    QueFront := Word(Integer(QueFront) + Count);
  end;

  { While DrawLock is raised the calls below do not draw the view more than once. }
  Inc(DrawLock);
  SetLimit(Limit.X, screenLines);
  ScrollTo(0, Integer(screenLines) + 1);
  Dec(DrawLock);

  DrawView;
  Result := Count;
end;

function TTerminal.QueEmpty: Boolean;
begin
  Result := QueBack = QueFront;
end;

{ otstream }

constructor otstream.Create(ATerminal: TTerminal);
begin
  inherited Create(ATerminal.StreamBuf);
end;

end.
