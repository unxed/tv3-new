{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/help.h, include/tvision/helpbase.h, source/tvision/help.cpp,
  source/tvision/helpbase.cpp, source/tvision/tvtext2.cpp (the texts of THelpWindow and THelpFile)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe.

  A help file holds topics. A topic is a list of paragraphs, each with a block of characters, its size and a
  flag that tells whether its lines are wrapped to the width of the viewer, and a list of cross references. THelpIndex
  maps the number of a context to the position of its topic in the file, THelpFile reads and writes the topics
  through an iopstream, THelpViewer shows a topic in a scroller and THelpWindow is the window around a viewer.

  The streamable members read, write, build and streamableName of THelpTopic and THelpIndex are translated with the
  classes of TvStreams: Read, Write, Build and StreamableName. The constructors that take StreamableInit are left
  out, because an object of a Pascal class starts with all its fields zero and Build calls Create. The objects
  RHelpTopic and RHelpIndex of the C++, which register the two types, are made when the unit starts. The pointer
  operators of the stream classes that helpbase.h defines are Get of ipstream, which reads a pointer into a Pointer,
  and Put of opstream and iopstream, which writes a TStreamable. The type name registered for a class is its class
  variable Name.

  A TParagraph is a class whose text is a block of characters of Size bytes with a terminating zero, released with
  FreeMem; NewStr of TvUtil makes such a block. A TCrossRef is a record and the list of the cross references of a
  topic is a block of records, which a PCrossRef points to. The text of a TStringView that a topic gives for a line is
  an AnsiString that holds a copy of the line. Strwidth of TvUtil, which stands for strwidth, and the text
  routines that TDrawBuffer calls take the string type of the unit that declares them, which holds at most 255 bytes
  when that unit is built in mode objfpc, so a line that is longer is cut when it is measured, wrapped or drawn.

  The texts helpWinTitle of THelpWindow and invalidContext of THelpFile are the class variables HelpWinTitle and
  InvalidContext, which get the values of tvtext2.cpp when the unit starts. The palettes of THelpViewer and of
  THelpWindow are made from cHelpViewer and cHelpWindow when the unit starts and released when it ends. The function
  isBlank, getLineAtOffset and discardTrailingWhitespaces of helpbase.cpp are inside the unit. }
unit TvHelp;

{$mode objfpc}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  TvGeom, TvEvents, TvObjs, TvStreams, TvViews, TvWindow;

const
  magicHeader = LongInt($46484246);

  { The palette of THelpViewer: 1 normal, 2 keyword, 3 selected keyword. }
  cHelpViewer = #6#7#8;
  { The palette of THelpWindow: 1 frame passive, 2 frame active, 3 frame icon, 4 scroll bar page area,
    5 scroll bar controls, 6 viewer normal, 7 viewer keyword, 8 viewer selected keyword. }
  cHelpWindow = #$80#$81#$82#$83#$84#$85#$86#$87;

type
  { A block of text of a topic. Next is the following paragraph, Wrap tells whether the lines are wrapped, Size is
    the number of bytes of Text. }
  TParagraph = class
  public
    Next: TParagraph;
    Wrap: Boolean;
    Size: Word;
    Text: PAnsiChar;
  end;

  { A reference from a place in the text of a topic to another topic. Offset counts the bytes of all the paragraphs
    before the reference, from 1, and Length is the number of bytes that the reference covers. }
  TCrossRef = record
    Ref: LongInt;
    Offset: LongInt;
    Length: Byte;
  end;
  PCrossRef = ^TCrossRef;

  { Writes the number of a reference into a stream, in place of the four bytes that the default writes. }
  TCrossRefHandler = procedure(S: opstream; Value: LongInt);

  THelpTopic = class(TStreamable)
  public
    Paragraphs: TParagraph;
    NumRefs: LongInt;
    CrossRefs: PCrossRef;
    class var Name: PChar;
    constructor Create;
    destructor Destroy; override;
    procedure AddCrossRef(ARef: TCrossRef);
    procedure AddParagraph(P: TParagraph);
    procedure GetCrossRef(I: LongInt; var Loc: TPoint; var ALength: Byte; var ARef: LongInt);
    function GetLine(ALine: LongInt): AnsiString;
    function GetNumCrossRefs: LongInt;
    function LongestLineWidth: LongInt;
    function NumLines: LongInt;
    procedure SetCrossRef(I: LongInt; const ARef: TCrossRef);
    procedure SetNumCrossRefs(I: LongInt);
    procedure SetWidth(AWidth: LongInt);
    class function Build: TStreamable; static;
  private
    Width: LongInt;
    LastOffset: LongInt;
    LastLine: LongInt;
    LastParagraph: TParagraph;
    function WrapText(Text: PAnsiChar; TextSize: LongInt; var Offset: LongInt; DoWrap: Boolean): AnsiString;
    procedure ReadParagraphs(S: ipstream);
    procedure ReadCrossRefs(S: ipstream);
    procedure WriteParagraphs(S: opstream);
    procedure WriteCrossRefs(S: opstream);
    procedure DisposeParagraphs;
  protected
    function StreamableName: PChar; override;
    function Read(S: ipstream): Pointer; override;
    procedure Write(S: opstream); override;
  end;

  { Maps the number of a context to a position in a help file; -1 stands for a context that has none. }
  THelpIndex = class(TStreamable)
  public
    Size: Word;
    Index: PLongInt;
    class var Name: PChar;
    constructor Create;
    destructor Destroy; override;
    function Position(I: LongInt): LongInt;
    procedure Add(I: LongInt; Val: LongInt);
    class function Build: TStreamable; static;
  protected
    function StreamableName: PChar; override;
    function Read(S: ipstream): Pointer; override;
    procedure Write(S: opstream); override;
  end;

  { A help file on a stream. The file owns the stream and the index and releases them with itself. }
  THelpFile = class(TvObject)
  public
    Stream: iopstream;
    Modified: Boolean;
    Index: THelpIndex;
    IndexPos: LongInt;
  private
    class var InvalidContext: string;
    class procedure EnsureStreamSize(AStream: iopstream; DesiredSize: LongInt); static;
  public
    constructor Create(S: iopstream);
    destructor Destroy; override;
    function GetTopic(I: LongInt): THelpTopic;
    function InvalidTopic: THelpTopic;
    procedure RecordPositionInIndex(I: LongInt);
    procedure PutTopic(ATopic: THelpTopic);
  end;

  { Shows a topic of a help file. The viewer owns the file and the topic that it shows. Selected counts the cross
    references of the topic from 1. The palette is: 1 normal, 2 keyword, 3 selected keyword. }
  THelpViewer = class(TScroller)
  public
    HFile: THelpFile;
    Topic: THelpTopic;
    Selected: LongInt;
    constructor Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar; AHelpFile: THelpFile;
      Context: Word); reintroduce;
    destructor Destroy; override;
    procedure ChangeBounds(const Bounds: TRect); override;
    procedure Draw; override;
    function GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure MakeSelectVisible(ASelected: LongInt; var KeyPoint: TPoint; var KeyLength: Byte; var KeyRef: LongInt);
    procedure SwitchToTopic(KeyRef: LongInt);
  private
    procedure RefreshLimit;
  end;

  { The window of a help viewer. The palette is: 1 frame passive, 2 frame active, 3 frame icon, 4 scroll bar page
    area, 5 scroll bar controls, 6 viewer normal, 7 viewer keyword, 8 viewer selected keyword. }
  THelpWindow = class(TWindow)
  private
    class var HelpWinTitle: string;
  public
    constructor Create(AHelpFile: THelpFile; Context: Word); reintroduce;
    function GetPalette: TPalette; override;
  end;

var
  CrossRefHandler: TCrossRefHandler;

{ The default of CrossRefHandler: writes nothing. While it is the handler, a topic writes the number of each
  reference as four bytes. }
procedure NotAssigned(S: opstream; Value: LongInt);

implementation

uses
  TvColors, TvDrawBuf, TvKeys, TvUtf8, TvUtil;

const
  { INT_MAX of limits.h. }
  IntMax = High(LongInt);

var
  RHelpTopic: TStreamableClass;
  RHelpIndex: TStreamableClass;
  HelpViewerPalette: TPalette;
  HelpWindowPalette: TPalette;

procedure NotAssigned(S: opstream; Value: LongInt);
begin
end;

{ The space characters of the C locale. }
function IsBlank(Ch: AnsiChar): Boolean;
begin
  Result := Ch in [#9..#13, ' '];
end;

{ The Count bytes of Text from the zero-based position Start, as a string; empty when there are none. }
function TextSlice(Text: PAnsiChar; Start, Count: LongInt): AnsiString;
begin
  if (Text = nil) or (Start < 0) or (Count <= 0) then
    Result := ''
  else
    SetString(Result, Text + Start, Count);
end;

{ The attribute that the conversion of a pair to a TColorAttr gives. }
function PairLow(const Pair: TAttrPair): TColorAttr;
begin
  Result := Pair.Attrs[0];
end;

{ The bytes of the text from Offset to the end of its line, with the line feed, or to the end of the text. }
function GetLineAtOffset(Text: PAnsiChar; TextSize, Offset: LongInt): AnsiString;
var
  Stop: LongInt;
begin
  Stop := Offset;
  while (Stop < TextSize) and (Text[Stop] <> #10) do
    Inc(Stop);
  if Stop < TextSize then
    Inc(Stop);
  Result := TextSlice(Text, Offset, Stop - Offset);
end;

function DiscardTrailingWhitespaces(const Str: AnsiString): AnsiString;
var
  NewSize: LongInt;
begin
  NewSize := Length(Str);
  while (NewSize > 0) and IsBlank(Str[NewSize]) do
    Dec(NewSize);
  Result := Copy(Str, 1, NewSize);
end;

{ THelpTopic }

constructor THelpTopic.Create;
begin
  inherited Create;
  Paragraphs := nil;
  NumRefs := 0;
  CrossRefs := nil;
  Width := 0;
  LastOffset := 0;
  LastLine := IntMax;
  LastParagraph := nil;
end;

destructor THelpTopic.Destroy;
begin
  DisposeParagraphs;
  if CrossRefs <> nil then
    FreeMem(CrossRefs);
  inherited Destroy;
end;

procedure THelpTopic.DisposeParagraphs;
var
  Cur, Following: TParagraph;
begin
  Cur := Paragraphs;
  while Cur <> nil do
  begin
    Following := Cur.Next;
    if Cur.Text <> nil then
      FreeMem(Cur.Text);
    Cur.Free;
    Cur := Following;
  end;
  Paragraphs := nil;
end;

function THelpTopic.StreamableName: PChar;
begin
  Result := Name;
end;

class function THelpTopic.Build: TStreamable;
begin
  Result := THelpTopic.Create;
end;

procedure THelpTopic.Write(S: opstream);
begin
  WriteParagraphs(S);
  WriteCrossRefs(S);
end;

function THelpTopic.Read(S: ipstream): Pointer;
begin
  ReadParagraphs(S);
  ReadCrossRefs(S);
  Width := 0;
  LastLine := IntMax;
  Result := Self;
end;

procedure THelpTopic.ReadParagraphs(S: ipstream);
var
  Remaining, WrapFlag: LongInt;
  BlockSize: Word;
  Fresh, Tail: TParagraph;
begin
  S.Get(Remaining);
  Tail := nil;
  while Remaining > 0 do
  begin
    S.Get(BlockSize);
    Fresh := TParagraph.Create;
    GetMem(Fresh.Text, BlockSize + 1);
    Fresh.Size := BlockSize;
    S.Get(WrapFlag);
    Fresh.Wrap := WrapFlag <> 0;
    S.ReadBytes(Fresh.Text^, Fresh.Size);
    Fresh.Text[Fresh.Size] := #0;
    if Tail = nil then
      Paragraphs := Fresh
    else
      Tail.Next := Fresh;
    Tail := Fresh;
    Dec(Remaining);
  end;
  if Tail = nil then
    Paragraphs := nil
  else
    Tail.Next := nil;
end;

procedure THelpTopic.ReadCrossRefs(S: ipstream);
var
  K: LongInt;
  Slot: PCrossRef;
begin
  S.Get(NumRefs);
  if NumRefs > 0 then
    CrossRefs := AllocMem(NumRefs * SizeOf(TCrossRef))
  else
    CrossRefs := nil;
  for K := 0 to NumRefs - 1 do
  begin
    Slot := CrossRefs + K;
    S.Get(Slot^.Ref);
    S.Get(Slot^.Offset);
    S.Get(Slot^.Length);
  end;
end;

procedure THelpTopic.WriteParagraphs(S: opstream);
var
  Total, WrapFlag: LongInt;
  Cur: TParagraph;
begin
  Total := 0;
  Cur := Paragraphs;
  while Cur <> nil do
  begin
    Inc(Total);
    Cur := Cur.Next;
  end;
  S.Put(Total);
  Cur := Paragraphs;
  while Cur <> nil do
  begin
    S.Put(Cur.Size);
    if Cur.Wrap then
      WrapFlag := 1
    else
      WrapFlag := 0;
    S.Put(WrapFlag);
    if Cur.Size > 0 then
      S.WriteBytes(Cur.Text^, Cur.Size);
    Cur := Cur.Next;
  end;
end;

procedure THelpTopic.WriteCrossRefs(S: opstream);
var
  K: LongInt;
  Slot: PCrossRef;
begin
  S.Put(NumRefs);
  if Pointer(CrossRefHandler) = Pointer(@NotAssigned) then
  begin
    for K := 0 to NumRefs - 1 do
    begin
      Slot := CrossRefs + K;
      S.Put(Slot^.Ref);
      S.Put(Slot^.Offset);
      S.Put(Slot^.Length);
    end;
  end
  else
  begin
    for K := 0 to NumRefs - 1 do
    begin
      Slot := CrossRefs + K;
      CrossRefHandler(S, Slot^.Ref);
      S.Put(Slot^.Offset);
      S.Put(Slot^.Length);
    end;
  end;
end;

procedure THelpTopic.AddCrossRef(ARef: TCrossRef);
begin
  ReAllocMem(CrossRefs, (NumRefs + 1) * SizeOf(TCrossRef));
  CrossRefs[NumRefs] := ARef;
  Inc(NumRefs);
end;

procedure THelpTopic.AddParagraph(P: TParagraph);
var
  Walk, Back: TParagraph;
begin
  if Paragraphs = nil then
    Paragraphs := P
  else
  begin
    Walk := Paragraphs;
    Back := Walk;
    while Walk <> nil do
    begin
      Back := Walk;
      Walk := Walk.Next;
    end;
    Back.Next := P;
  end;
  P.Next := nil;
end;

{ Cuts the next line of Text at Offset, which moves to the start of the line that follows. The result is the line
  without its trailing white space. A paragraph that is wrapped is cut at the last space that fits into Width. }
function THelpTopic.WrapText(Text: PAnsiChar; TextSize: LongInt; var Offset: LongInt;
  DoWrap: Boolean): AnsiString;
var
  Line: AnsiString;
  Probe: string;
  WrappedSize, NewSize: LongInt;
begin
  Line := GetLineAtOffset(Text, TextSize, Offset);
  if DoWrap then
  begin
    Probe := Copy(Line, 1, 255);
    WrappedSize := TText.Scroll(Probe, Width, False);
    if (0 < WrappedSize) and (WrappedSize < Length(Line)) then
    begin
      NewSize := WrappedSize;
      { Omit the last word if it was cut off by wrapping. }
      while (NewSize > 0) and not IsBlank(Line[NewSize + 1]) do
        Dec(NewSize);
      { Unless it fills the whole line. }
      if NewSize = 0 then
        NewSize := WrappedSize;
      { If a space follows, keep it so that Offset points past it. }
      if (NewSize < TextSize) and IsBlank(Line[NewSize + 1]) then
        Inc(NewSize);
      Line := Copy(Line, 1, NewSize);
    end;
  end;
  Offset := Offset + Length(Line);
  Result := DiscardTrailingWhitespaces(Line);
end;

procedure THelpTopic.GetCrossRef(I: LongInt; var Loc: TPoint; var ALength: Byte; var ARef: LongInt);
var
  CurOffset, ParaOffset, LineOffset, LineNumber, Wanted, RefOffset, RefLength: LongInt;
  P: TParagraph;
  Slot: PCrossRef;
  Before, Marked: AnsiString;
begin
  ParaOffset := 0;
  CurOffset := 0;
  LineNumber := 0;
  Slot := CrossRefs + I;
  Wanted := Slot^.Offset;
  P := Paragraphs;
  repeat
    if P = nil then
    begin
      { The offset is beyond the text of the topic. }
      Loc.X := 0;
      Loc.Y := 0;
      ALength := 0;
      ARef := Slot^.Ref;
      Exit;
    end;
    LineOffset := CurOffset;
    WrapText(P.Text, P.Size, CurOffset, P.Wrap);
    Inc(LineNumber);
    if Wanted <= ParaOffset + CurOffset then
    begin
      RefOffset := Wanted - (ParaOffset + LineOffset) - 1;
      RefLength := Slot^.Length;
      if LineOffset + RefOffset + RefLength > P.Size then
        RefLength := P.Size - (LineOffset + RefOffset);
      Before := TextSlice(P.Text, LineOffset, RefOffset);
      Marked := TextSlice(P.Text, LineOffset + RefOffset, RefLength);
      Loc.X := Strwidth(Before);
      Loc.Y := LineNumber;
      ALength := Byte(Strwidth(Marked));
      ARef := Slot^.Ref;
      Exit;
    end;
    if CurOffset >= P.Size then
    begin
      ParaOffset := ParaOffset + P.Size;
      P := P.Next;
      CurOffset := 0;
    end;
  until False;
end;

function THelpTopic.GetLine(ALine: LongInt): AnsiString;
var
  Offset, Wanted: LongInt;
  P: TParagraph;
  LineText: AnsiString;
begin
  Result := '';
  { Go on from the line that was found last when it is before the wanted one, else start at the first line. }
  P := Paragraphs;
  Offset := 0;
  Wanted := ALine;
  if LastLine < ALine then
  begin
    P := LastParagraph;
    Offset := LastOffset;
    Wanted := ALine - LastLine;
  end;
  LastLine := ALine;
  while P <> nil do
  begin
    if Offset >= P.Size then
    begin
      P := P.Next;
      Offset := 0;
      Continue;
    end;
    LineText := WrapText(P.Text, P.Size, Offset, P.Wrap);
    Dec(Wanted);
    if Wanted <> 0 then
      Continue;
    LastOffset := Offset;
    LastParagraph := P;
    Result := LineText;
    Exit;
  end;
end;

function THelpTopic.GetNumCrossRefs: LongInt;
begin
  Result := NumRefs;
end;

function THelpTopic.LongestLineWidth: LongInt;
var
  LineCount, K, LineWidth: LongInt;
begin
  Result := 0;
  LineCount := NumLines;
  for K := 1 to LineCount do
  begin
    LineWidth := Strwidth(GetLine(K));
    if LineWidth > Result then
      Result := LineWidth;
  end;
end;

function THelpTopic.NumLines: LongInt;
var
  Offset: LongInt;
  P: TParagraph;
begin
  Result := 0;
  Offset := 0;
  P := Paragraphs;
  while P <> nil do
    if Offset < P.Size then
    begin
      WrapText(P.Text, P.Size, Offset, P.Wrap);
      Inc(Result);
    end
    else
    begin
      P := P.Next;
      Offset := 0;
    end;
end;

procedure THelpTopic.SetCrossRef(I: LongInt; const ARef: TCrossRef);
begin
  if (I >= 0) and (I < NumRefs) then
    CrossRefs[I] := ARef;
end;

procedure THelpTopic.SetNumCrossRefs(I: LongInt);
var
  Fresh: PCrossRef;
  Keep: LongInt;
begin
  if NumRefs = I then
    Exit;
  if I > 0 then
    Fresh := AllocMem(I * SizeOf(TCrossRef))
  else
    Fresh := nil;
  if NumRefs > 0 then
  begin
    Keep := NumRefs;
    if I < Keep then
      Keep := I;
    if Keep > 0 then
      Move(CrossRefs^, Fresh^, Keep * SizeOf(TCrossRef));
    FreeMem(CrossRefs);
  end;
  CrossRefs := Fresh;
  NumRefs := I;
end;

procedure THelpTopic.SetWidth(AWidth: LongInt);
begin
  Width := AWidth;
end;

{ THelpIndex }

constructor THelpIndex.Create;
begin
  inherited Create;
  Size := 0;
  Index := nil;
end;

destructor THelpIndex.Destroy;
begin
  if Index <> nil then
    FreeMem(Index);
  inherited Destroy;
end;

function THelpIndex.StreamableName: PChar;
begin
  Result := Name;
end;

class function THelpIndex.Build: TStreamable;
begin
  Result := THelpIndex.Create;
end;

procedure THelpIndex.Write(S: opstream);
var
  K: LongInt;
begin
  S.Put(Size);
  for K := 0 to LongInt(Size) - 1 do
    S.Put(Index[K]);
end;

function THelpIndex.Read(S: ipstream): Pointer;
var
  K: LongInt;
begin
  S.Get(Size);
  if Size = 0 then
    Index := nil
  else
  begin
    GetMem(Index, Size * SizeOf(LongInt));
    for K := 0 to LongInt(Size) - 1 do
      S.Get(Index[K]);
  end;
  Result := Self;
end;

function THelpIndex.Position(I: LongInt): LongInt;
begin
  if (I >= 0) and (I < Size) then
    Result := Index[I]
  else
    Result := -1;
end;

procedure THelpIndex.Add(I: LongInt; Val: LongInt);
const
  Step = 10;
var
  Fresh: PLongInt;
  NewSize: LongInt;
begin
  if I < 0 then
    Exit;
  if I >= Size then
  begin
    NewSize := (I + Step) div Step * Step;
    GetMem(Fresh, NewSize * SizeOf(LongInt));
    if Index <> nil then
      Move(Index^, Fresh^, Size * SizeOf(LongInt));
    FillChar(Fresh[Size], (NewSize - Size) * SizeOf(LongInt), $FF);
    if Index <> nil then
      FreeMem(Index);
    Index := Fresh;
    Size := Word(NewSize);
  end;
  Index[I] := Val;
end;

{ THelpFile }

constructor THelpFile.Create(S: iopstream);
var
  Magic, StreamSize: LongInt;
  Loaded: Pointer;
begin
  inherited Create;
  Magic := 0;
  S.Seekg(0, iosEnd);
  StreamSize := LongInt(S.Tellg);
  S.Seekg(0);
  if StreamSize > SizeOf(Magic) then
    S.Get(Magic);
  if (Magic = magicHeader) and (StreamSize >= 12) then
  begin
    S.Seekg(8);
    S.Get(IndexPos);
    S.Seekg(IndexPos);
    Loaded := nil;
    S.Get(Loaded);
    Index := THelpIndex(Loaded);
    Modified := False;
  end
  else
  begin
    IndexPos := 12;
    Index := THelpIndex.Create;
    Modified := True;
  end;
  Stream := S;
end;

destructor THelpFile.Destroy;
var
  Magic, Total: LongInt;
begin
  if Modified then
  begin
    EnsureStreamSize(Stream, IndexPos);
    Stream.Seekp(IndexPos);
    Stream.Put(Index);
    Magic := magicHeader;
    Stream.Seekp(0, iosEnd);
    Total := LongInt(Stream.Tellp) - 8;
    Stream.Seekp(0);
    Stream.Put(Magic);
    Stream.Put(Total);
    Stream.Put(IndexPos);
  end;
  Stream.Free;
  Index.Free;
  inherited Destroy;
end;

{ Makes the stream at least DesiredSize bytes long by writing zero bytes at its end. }
class procedure THelpFile.EnsureStreamSize(AStream: iopstream; DesiredSize: LongInt);
var
  CurrentSize, K: LongInt;
begin
  AStream.Seekg(0, iosEnd);
  CurrentSize := LongInt(AStream.Tellg);
  if CurrentSize < DesiredSize then
  begin
    AStream.Seekp(0, iosEnd);
    for K := CurrentSize to DesiredSize - 1 do
      AStream.WriteByte(0);
  end;
end;

function THelpFile.GetTopic(I: LongInt): THelpTopic;
var
  Pos: LongInt;
  Loaded: Pointer;
begin
  Pos := Index.Position(I);
  if Pos > 0 then
  begin
    Stream.Seekg(Pos);
    Loaded := nil;
    Stream.Get(Loaded);
    Result := THelpTopic(Loaded);
  end
  else
    Result := InvalidTopic;
end;

function THelpFile.InvalidTopic: THelpTopic;
var
  Para: TParagraph;
begin
  Result := THelpTopic.Create;
  Para := TParagraph.Create;
  Para.Text := NewStr(InvalidContext);
  Para.Size := Word(Length(InvalidContext));
  Para.Wrap := False;
  Para.Next := nil;
  Result.AddParagraph(Para);
end;

procedure THelpFile.RecordPositionInIndex(I: LongInt);
begin
  Index.Add(I, IndexPos);
  Modified := True;
end;

procedure THelpFile.PutTopic(ATopic: THelpTopic);
begin
  EnsureStreamSize(Stream, IndexPos);
  Stream.Seekp(IndexPos);
  Stream.Put(ATopic);
  IndexPos := LongInt(Stream.Tellp);
  Modified := True;
end;

{ THelpViewer }

constructor THelpViewer.Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar; AHelpFile: THelpFile;
  Context: Word);
begin
  inherited Create(Bounds, AHScrollBar, AVScrollBar);
  HFile := AHelpFile;
  GrowMode := Byte(gfGrowHiY or gfGrowHiX);
  Options := ofSelectable or Options;
  Topic := HFile.GetTopic(Context);
  Selected := 1;
  Topic.SetWidth(Size.X);
  RefreshLimit;
end;

destructor THelpViewer.Destroy;
begin
  HFile.Free;
  Topic.Free;
  inherited Destroy;
end;

procedure THelpViewer.ChangeBounds(const Bounds: TRect);
begin
  inherited ChangeBounds(Bounds);
  Topic.SetWidth(Size.X);
  RefreshLimit;
end;

procedure THelpViewer.Draw;
var
  Cells: TDrawBuffer;
  Row, Col, KeyCount, Covered, FirstCol, KeyRef: LongInt;
  Tints: array[1..3] of TColorAttr;
  Normal, Keyword, SelKeyword, Shade: TColorAttr;
  KeyPoint: TPoint;
  KeyLength: Byte;
  LineText: AnsiString;
begin
  for Col := 1 to 3 do
    Tints[Col] := PairLow(GetColor(Col));
  Normal := Tints[1];
  Keyword := Tints[2];
  SelKeyword := Tints[3];
  FillChar(KeyPoint, SizeOf(KeyPoint), 0);
  KeyCount := 0;
  KeyLength := 0;
  KeyRef := 0;
  Cells := TDrawBuffer.Create;
  try
    Topic.SetWidth(Size.X);
    if Topic.GetNumCrossRefs > 0 then
    begin
      repeat
        Topic.GetCrossRef(KeyCount, KeyPoint, KeyLength, KeyRef);
        Inc(KeyCount);
      until (KeyCount >= Topic.GetNumCrossRefs) or (KeyPoint.Y > Delta.Y);
    end;
    for Row := 1 to Size.Y do
    begin
      Cells.MoveChar(0, ' ', Normal, Word(Size.X));
      LineText := Topic.GetLine(Row + Delta.Y);
      if Strwidth(LineText) > Delta.X then
        Cells.MoveStr(0, LineText, Normal, Word(Size.X), Word(Delta.X))
      else
        Cells.MoveStr(0, '', Normal);
      while Row + Delta.Y = KeyPoint.Y do
      begin
        FirstCol := KeyPoint.X - Delta.X;
        Covered := KeyLength;
        if FirstCol < 0 then
        begin
          Covered := Covered + FirstCol;
          FirstCol := 0;
          KeyPoint.X := Delta.X;
        end;
        Shade := Keyword;
        if KeyCount = Selected then
          Shade := SelKeyword;
        for Col := FirstCol to FirstCol + Covered - 1 do
          Cells.PutAttribute(Word(Col), Shade);
        if KeyCount >= Topic.GetNumCrossRefs then
          KeyPoint.Y := 0
        else
        begin
          Topic.GetCrossRef(KeyCount, KeyPoint, KeyLength, KeyRef);
          Inc(KeyCount);
        end;
      end;
      WriteLine(0, Row - 1, Size.X, 1, Cells);
    end;
  finally
    Cells.Free;
  end;
end;

function THelpViewer.GetPalette: TPalette;
begin
  Result := HelpViewerPalette;
end;

procedure THelpViewer.MakeSelectVisible(ASelected: LongInt; var KeyPoint: TPoint; var KeyLength: Byte;
  var KeyRef: LongInt);
var
  Goal: TPoint;

  { The first visible position along one axis that shows Key: Pad is how far before Key the view must start
    (0 across, 1 down, where the rows count from 1), and Room is the size of the view along the axis. }
  function Reveal(Key, Cur, Room, Pad: LongInt): LongInt;
  begin
    Result := Cur;
    if Key - Pad < Result then
      Result := Key - Pad;
    if Key > Result + Room then
      Result := Key - Room;
  end;

begin
  Topic.GetCrossRef(ASelected, KeyPoint, KeyLength, KeyRef);
  Goal.X := Reveal(KeyPoint.X, Delta.X, Size.X, 0);
  Goal.Y := Reveal(KeyPoint.Y, Delta.Y, Size.Y, 1);
  if Goal <> Delta then
    ScrollTo(Goal.X, Goal.Y);
end;

procedure THelpViewer.SwitchToTopic(KeyRef: LongInt);
begin
  Topic.Free;
  Topic := HFile.GetTopic(KeyRef);
  Topic.SetWidth(Size.X);
  ScrollTo(0, 0);
  RefreshLimit;
  Selected := 1;
  DrawView;
end;

{ Sets the limit of the scroller to the extent of the topic at the present width. }
procedure THelpViewer.RefreshLimit;
var
  Extent: TPoint;
begin
  Extent.X := Topic.LongestLineWidth;
  Extent.Y := Topic.NumLines;
  SetLimit(Extent.X, Extent.Y);
end;

procedure THelpViewer.HandleEvent(var Event: TEvent);
var
  KeyPoint: TPoint;
  KeyLength: Byte;
  KeyRef: LongInt;

  { Moves the selection by one reference, forward or back, with a wrap at the ends, and shows it. }
  procedure StepSelection(GoForward: Boolean);
  var
    Total: LongInt;
  begin
    Total := Topic.GetNumCrossRefs;
    if GoForward then
      Selected := Selected + 1
    else
      Selected := Selected - 1;
    if (GoForward and (Selected > Total)) then
      Selected := 1
    else if (not GoForward) and (Selected = 0) then
      Selected := Total;
    if Total = 0 then
      Exit;
    MakeSelectVisible(Selected - 1, KeyPoint, KeyLength, KeyRef);
  end;

  { Follows the cross reference with the zero-based number Slot. }
  procedure FollowRef(Slot: LongInt);
  begin
    Topic.GetCrossRef(Slot, KeyPoint, KeyLength, KeyRef);
    SwitchToTopic(KeyRef);
  end;

  { Turns the Esc key into the command cmClose and puts it back to the owners. }
  procedure AskToClose;
  begin
    Event.Message.Command := cmClose;
    Event.What := evCommand;
    PutEvent(Event);
  end;

  procedure OnKey;
  begin
    case Event.KeyDown.KeyCode of
      kbTab:
        StepSelection(True);
      kbShiftTab:
        StepSelection(False);
      kbEnter:
        if Selected <= Topic.GetNumCrossRefs then
          FollowRef(Selected - 1);
      kbEsc:
        AskToClose;
    else
      Exit;
    end;
    DrawView;
    ClearEvent(Event);
  end;

  { The number, from 1, of the reference that covers the cell Spot of the topic; 0 when none does. }
  function RefAt(const Spot: TPoint): LongInt;
  var
    Slot: LongInt;
  begin
    for Slot := 1 to Topic.GetNumCrossRefs do
    begin
      Topic.GetCrossRef(Slot - 1, KeyPoint, KeyLength, KeyRef);
      if (KeyPoint.Y = Spot.Y + 1) and (Spot.X >= KeyPoint.X) and (Spot.X < KeyPoint.X + KeyLength) then
      begin
        Result := Slot;
        Exit;
      end;
    end;
    Result := 0;
  end;

  procedure OnMouse;
  var
    Spot: TPoint;
    Hit: LongInt;
  begin
    Spot := MakeLocal(Event.Mouse.Where) + Delta;
    Hit := RefAt(Spot);
    if Hit = 0 then
      Exit;
    Selected := Hit;
    DrawView;
    SwitchToTopic(KeyRef);
    ClearEvent(Event);
  end;

  procedure OnCommand;
  begin
    if (Event.Message.Command <> cmClose) or (Owner = nil) then
      Exit;
    if (Owner.State and sfModal) = 0 then
      Exit;
    ClearEvent(Event);
    EndModal(cmClose);
  end;

begin
  KeyRef := 0;
  KeyLength := 0;
  inherited HandleEvent(Event);
  if Event.What = evKeyDown then
    OnKey
  else if Event.What = evMouseDown then
    OnMouse
  else if Event.What = evCommand then
    OnCommand;
end;

{ THelpWindow }

constructor THelpWindow.Create(AHelpFile: THelpFile; Context: Word);
var
  Area: TRect;
  HBar, VBar: TScrollBar;
begin
  inherited Create(TRect.Create(0, 0, 50, 18), HelpWinTitle, wnNoNumber);
  Options := Options or ofCentered;
  Area := TRect.Create(0, 0, 50, 18);
  Area.Grow(-2, -1);
  HBar := StandardScrollBar(sbHorizontal or sbHandleKeyboard);
  VBar := StandardScrollBar(sbVertical or sbHandleKeyboard);
  Insert(THelpViewer.Create(Area, HBar, VBar, AHelpFile, Context));
end;

function THelpWindow.GetPalette: TPalette;
begin
  Result := HelpWindowPalette;
end;

initialization
  THelpTopic.Name := 'THelpTopic';
  THelpIndex.Name := 'THelpIndex';
  THelpFile.InvalidContext := #10' No help available in this context.';
  THelpWindow.HelpWinTitle := 'Help';
  CrossRefHandler := @NotAssigned;
  HelpViewerPalette := TPalette.Create(cHelpViewer, Length(cHelpViewer));
  HelpWindowPalette := TPalette.Create(cHelpWindow, Length(cHelpWindow));
  RHelpTopic := TStreamableClass.Create(THelpTopic.Name, @THelpTopic.Build);
  RHelpIndex := TStreamableClass.Create(THelpIndex.Name, @THelpIndex.Build);

finalization
  HelpViewerPalette.Free;
  HelpWindowPalette.Free;

end.
