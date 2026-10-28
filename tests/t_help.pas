{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/help.h, include/tvision/helpbase.h, source/tvision/help.cpp,
  source/tvision/helpbase.cpp, source/tvision/tvtext2.cpp (the texts of THelpWindow and THelpFile)
  See COPYRIGHT.magiblot.

  The help files of these tests live in memory buffers. The display is a screen of 80 by 25 cells in memory and the
  root of the views, the stage, is a group that writes into it and reads its events from a script; an event that a
  view puts back is appended to the script. The entries from 128 on of the palette of the stage are the BIOS
  attributes $41 and above, so the three colors of a help viewer are $46, $47 and $48 on the stage; the other entries
  are $07. The values that the tests expect were worked out by hand from the C++: the sample topic has the text
  "Top line", "go BETA now" and "and GAMMA", each line with a line feed, and two cross references. }
program t_help;

{$mode objfpc}
{$POINTERMATH ON}
{$modeswitch advancedrecords}

uses
  cthreads, TvObjs, TvStreams, TvUtil, TvGeom, TvColors, TvCell, TvDrawBuf, TvScreen, TvKeys, TvEvents, TvSys,
  TvViews, TvWindow, TvHelp;

const
  ScrW = 80;
  ScrH = 25;

const
  AttrBase = $46;
  AttrNormal = AttrBase;
  AttrKeyword = AttrBase + 1;
  AttrSelected = AttrBase + 2;

const
  SampleText = 'Top line'#10'go BETA now'#10'and GAMMA'#10;
  InvalidLine = ' No help available in this context.';
  WideCh = #$E6#$97#$A5;

{$I testlib.inc}

type
  TStage = class(TGroup)
  public
    Script: array of TEvent;
    ScriptPos: Integer;
    Calls: Integer;
    PutCount: Integer;
    LastPut: TEvent;
    Unhandled: Integer;
    procedure AddEvent(const Ev: TEvent);
    procedure Rewind;
    procedure GetEvent(var Event: TEvent); override;
    procedure PutEvent(var Event: TEvent); override;
    procedure EventError(var Event: TEvent); override;
    function GetPalette: TPalette; override;
  end;

  { A help viewer that shows its limit. }
  TProbe = class(THelpViewer)
  public
    function LimitOf: TPoint;
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  StagePal: TPalette;
  HandlerCalls: Integer;

{ The hooks of the display. }

procedure OnCaret(X, Y: Integer);
begin
end;

procedure OnScreenWrite(X, Y: Integer; Buf: PScreenCell; Count: Integer);
begin
end;

{ Small helpers. }

function Pt(X, Y: Integer): TPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function KeyEv(Code: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Code;
end;

function CmdEv(Cmd: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evCommand;
  Result.Message.Command := Cmd;
end;

function ClickEv(X, Y: Integer): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evMouseDown;
  Result.Mouse.Where := Pt(X, Y);
  Result.Mouse.Buttons := mbLeftButton;
end;

function ByteAt(M: TMemBuf; I: Integer): Integer;
var
  P: PByte;
begin
  P := M.Data;
  Result := P[I];
end;

function LongAt(M: TMemBuf; I: Integer): LongInt;
var
  P: PByte;
begin
  P := M.Data;
  Move(P[I], Result, SizeOf(LongInt));
end;

function EntryOf(P: TPalette; I: Integer): Integer;
var
  A: TColorAttr;
begin
  A := P.Items[I];
  Result := A.ToBIOS;
end;

function CellChar(X, Y: Integer): Char;
var
  Cell: string;
begin
  Cell := ScreenCells[Y * ScrW + X].Character.GetText;
  if Length(Cell) > 0 then
    Result := Cell[1]
  else
    Result := #0;
end;

function RowText(Y, X0, N: Integer): string;
var
  K: Integer;
begin
  Result := '';
  for K := 0 to N - 1 do
    Result := Result + CellChar(X0 + K, Y);
end;

function AttrAt(X, Y: Integer): Integer;
begin
  Result := ScreenCells[Y * ScrW + X].Attribute.ToBIOS;
end;

procedure WipeScreen;
begin
  FillChar(ScreenCells, SizeOf(ScreenCells), 0);
end;

{ The stage. }

procedure TStage.AddEvent(const Ev: TEvent);
begin
  SetLength(Script, Length(Script) + 1);
  Script[High(Script)] := Ev;
end;

procedure TStage.Rewind;
begin
  SetLength(Script, 0);
  ScriptPos := 0;
  Calls := 0;
  PutCount := 0;
  Unhandled := 0;
end;

procedure TStage.GetEvent(var Event: TEvent);
begin
  Inc(Calls);
  if Calls > 5000 then
  begin
    WriteLn('FAIL a loop of events does not end');
    Halt(1);
  end;
  FillChar(Event, SizeOf(Event), 0);
  if ScriptPos < Length(Script) then
  begin
    Event := Script[ScriptPos];
    Inc(ScriptPos);
  end;
end;

procedure TStage.PutEvent(var Event: TEvent);
begin
  Inc(PutCount);
  LastPut := Event;
  AddEvent(Event);
end;

procedure TStage.EventError(var Event: TEvent);
begin
  Inc(Unhandled);
end;

function TStage.GetPalette: TPalette;
begin
  Result := StagePal;
end;

function TProbe.LimitOf: TPoint;
begin
  Result := Limit;
end;

function MakeStagePalette: TPalette;
var
  Codes: string;
  K: Integer;
begin
  SetLength(Codes, 135);
  for K := 1 to 135 do
    if K < 128 then
      Codes[K] := #7
    else
      Codes[K] := Chr($41 + K - 128);
  Result := TPalette.Create(Codes, 135);
end;

function MakeStage: TStage;
begin
  WipeScreen;
  Result := TStage.Create(Rc(0, 0, ScrW, ScrH));
  Result.Options := Result.Options and not ofBuffered;
  Result.Buffer := @ScreenCells[0];
  Result.State := Result.State or sfSelected;
  Result.SetState(sfExposed, True);
end;

{ Topics and files. }

function NewPara(const Txt: string; DoWrap: Boolean): TParagraph;
begin
  Result := TParagraph.Create;
  Result.Size := Word(Length(Txt));
  Result.Text := NewStr(Txt);
  Result.Wrap := DoWrap;
end;

function NewTopic(const Txt: string; DoWrap: Boolean): THelpTopic;
begin
  Result := THelpTopic.Create;
  Result.AddParagraph(NewPara(Txt, DoWrap));
end;

procedure AddRef(T: THelpTopic; RefNo, AtOffset: LongInt; Len: Byte);
var
  Item: TCrossRef;
begin
  Item.Ref := RefNo;
  Item.Offset := AtOffset;
  Item.Length := Len;
  T.AddCrossRef(Item);
end;

{ Tells whether the cross reference I of T is at the column X of the line Y, covers Len columns and leads to RefNo. }
function RefIs(T: THelpTopic; I, X, Y: Integer; Len: Byte; RefNo: LongInt): Boolean;
var
  Loc: TPoint;
  Got: Byte;
  Target: LongInt;
begin
  Loc := Pt(-1, -1);
  Got := 255;
  Target := -1;
  T.GetCrossRef(I, Loc, Got, Target);
  Result := (Loc.X = X) and (Loc.Y = Y) and (Got = Len) and (Target = RefNo);
end;

{ The text of twenty lines "L01" to "L20". }
function LongText: string;
var
  K: Integer;
begin
  Result := '';
  for K := 1 to 20 do
    Result := Result + 'L' + Chr(Ord('0') + K div 10) + Chr(Ord('0') + K mod 10) + #10;
end;

{ Writes the topics 1 to 5 of the sample file into Mem. }
procedure BuildSample(Mem: TMemBuf);
var
  HF: THelpFile;
  T: THelpTopic;
begin
  HF := THelpFile.Create(iopstream.Create(Mem));

  T := NewTopic(SampleText, False);
  AddRef(T, 2, 13, 4);
  AddRef(T, 3, 26, 5);
  HF.RecordPositionInIndex(1);
  HF.PutTopic(T);
  T.Free;

  T := NewTopic('Beta text'#10, False);
  HF.RecordPositionInIndex(2);
  HF.PutTopic(T);
  T.Free;

  T := NewTopic('Gamma text'#10, False);
  HF.RecordPositionInIndex(3);
  HF.PutTopic(T);
  T.Free;

  T := NewTopic(LongText, False);
  AddRef(T, 2, 1, 3);
  AddRef(T, 1, 69, 3);
  HF.RecordPositionInIndex(4);
  HF.PutTopic(T);
  T.Free;

  T := NewTopic('alpha beta gamma', True);
  HF.RecordPositionInIndex(5);
  HF.PutTopic(T);
  T.Free;

  HF.Free;
end;

function OpenSample(Mem: TMemBuf): THelpFile;
begin
  Result := THelpFile.Create(iopstream.Create(Mem));
end;

{ The constants and the registrations. }

procedure TestConstants;
begin
  Check(magicHeader = $46484246, 'the magic number of a help file');
  Check(cHelpViewer = #6#7#8, 'the palette string of the viewer');
  Check((Length(cHelpWindow) = 8) and (cHelpWindow[1] = #$80) and (cHelpWindow[8] = #$87),
    'the palette string of the window');
  Check(AnsiString(THelpTopic.Name) = 'THelpTopic', 'the type name of a topic');
  Check(AnsiString(THelpIndex.Name) = 'THelpIndex', 'the type name of an index');
  Check(Pointer(CrossRefHandler) = Pointer(@NotAssigned), 'the handler of the cross references starts as NotAssigned');
end;

{ THelpIndex. }

procedure TestIndex;
var
  Idx, Back: THelpIndex;
  Mem: TMemBuf;
  Wr: opstream;
  Rd: ipstream;
  Loaded: Pointer;
begin
  Idx := THelpIndex.Create;
  Check((Idx.Size = 0) and (Idx.Index = nil), 'a new index is empty');
  Check(Idx.Position(0) = -1, 'an empty index has no position');
  Idx.Add(0, 100);
  Check(Idx.Size = 10, 'the first entry makes room for ten');
  Check(Idx.Position(0) = 100, 'the entry that was added');
  Check((Idx.Position(1) = -1) and (Idx.Position(9) = -1), 'the other entries of the room are -1');
  Check(Idx.Position(10) = -1, 'a number after the room gives -1');
  Check(Idx.Position(-1) = -1, 'a negative number gives -1');
  Idx.Add(25, 7);
  Check(Idx.Size = 30, 'the room grows to the next multiple of ten that holds the number');
  Check((Idx.Position(0) = 100) and (Idx.Position(25) = 7), 'the old entry stays and the new one is set');
  Check((Idx.Position(10) = -1) and (Idx.Position(26) = -1) and (Idx.Position(29) = -1), 'the new room is -1');
  Idx.Add(5, 55);
  Check((Idx.Size = 30) and (Idx.Position(5) = 55), 'an entry inside the room does not grow it');
  Idx.Add(29, 1);
  Check((Idx.Size = 30) and (Idx.Position(29) = 1), 'the last entry of the room');
  Idx.Add(30, 2);
  Check((Idx.Size = 40) and (Idx.Position(30) = 2) and (Idx.Position(29) = 1), 'a number equal to the size grows the room');
  Idx.Add(-3, 9);
  Check(Idx.Size = 40, 'a negative number is not added');
  Idx.Free;

  { The stream form: the size, then the entries. }
  Idx := THelpIndex.Create;
  Idx.Add(0, 100);
  Idx.Add(3, 4000);
  Mem := TMemBuf.Create;
  Wr := opstream.Create(Mem);
  Wr.Put(Idx);
  Check(Mem.Size = 56, 'an index of ten entries is 56 bytes with its type name');
  Check((ByteAt(Mem, 0) = 2) and (ByteAt(Mem, 1) = Ord('[')) and (ByteAt(Mem, 2) = 10), 'the prefix of the object');
  Check((ByteAt(Mem, 13) = 10) and (ByteAt(Mem, 14) = 0), 'the size is a word');
  Check((LongAt(Mem, 15) = 100) and (LongAt(Mem, 19) = -1) and (LongAt(Mem, 27) = 4000), 'the entries are longs');
  Check(ByteAt(Mem, 55) = Ord(']'), 'the suffix of the object');
  Rd := ipstream.Create(Mem);
  Rd.Seekg(0);
  Loaded := nil;
  Rd.Get(Loaded);
  Back := THelpIndex(Loaded);
  Check(Back <> nil, 'an index is read back');
  Check((Back.Size = 10) and (Back.Position(0) = 100) and (Back.Position(1) = -1) and (Back.Position(3) = 4000),
    'the entries that are read back');
  Back.Free;
  Rd.Free;
  Wr.Free;
  Idx.Free;
  Mem.Free;

  { An empty index has no block of entries. }
  Idx := THelpIndex.Create;
  Mem := TMemBuf.Create;
  Wr := opstream.Create(Mem);
  Wr.Put(Idx);
  Check(Mem.Size = 16, 'an empty index is 16 bytes with its type name');
  Rd := ipstream.Create(Mem);
  Rd.Seekg(0);
  Loaded := nil;
  Rd.Get(Loaded);
  Back := THelpIndex(Loaded);
  Check((Back <> nil) and (Back.Size = 0) and (Back.Index = nil), 'an empty index is read back empty');
  Back.Free;
  Rd.Free;
  Wr.Free;
  Idx.Free;
  Mem.Free;
end;

{ The lines of a topic. }

procedure TestTopicLines;
var
  T: THelpTopic;
  P2: TParagraph;
begin
  T := NewTopic('alpha beta gamma', True);
  Check(T.NumLines = 1, 'a wrapped paragraph is one line while the width is 0');
  Check(T.GetLine(1) = 'alpha beta gamma', 'its line is the whole text');
  Check(T.LongestLineWidth = 16, 'the width of that line');
  T.SetWidth(11);
  Check(T.NumLines = 2, 'the width 11 breaks the text into two lines');
  Check(T.GetLine(1) = 'alpha beta', 'the first line ends before the space');
  Check(T.GetLine(2) = 'gamma', 'the second line');
  Check(T.GetLine(3) = '', 'a line after the last is empty');
  Check(T.LongestLineWidth = 10, 'the longest line at the width 11');
  T.SetWidth(6);
  Check(T.NumLines = 3, 'the width 6 breaks the text into three lines');
  Check((T.GetLine(1) = 'alpha') and (T.GetLine(2) = 'beta') and (T.GetLine(3) = 'gamma'), 'the lines at the width 6');
  Check(T.LongestLineWidth = 5, 'the longest line at the width 6');
  T.Free;

  T := NewTopic('abcdefghij kl', True);
  T.SetWidth(4);
  Check(T.NumLines = 4, 'a word that is longer than the width is cut at the width');
  Check((T.GetLine(1) = 'abcd') and (T.GetLine(2) = 'efgh') and (T.GetLine(3) = 'ij') and (T.GetLine(4) = 'kl'),
    'the pieces of the long word and the words after it');
  T.Free;

  T := NewTopic('abcd efgh', True);
  T.SetWidth(4);
  Check(T.NumLines = 2, 'a word that fills the width is a line of its own');
  Check((T.GetLine(1) = 'abcd') and (T.GetLine(2) = 'efgh'), 'the two words');
  T.Free;

  T := NewTopic('one'#10'two'#10, False);
  Check(T.NumLines = 2, 'a line feed ends a line');
  Check((T.GetLine(1) = 'one') and (T.GetLine(2) = 'two'), 'the lines do not hold the line feed');
  T.Free;

  T := NewTopic('abc   '#10'def', False);
  Check(T.NumLines = 2, 'a paragraph that does not end with a line feed');
  Check((T.GetLine(1) = 'abc') and (T.GetLine(2) = 'def'), 'white space at the end of a line is dropped');
  T.Free;

  T := NewTopic(#10' x', False);
  Check(T.NumLines = 2, 'a line feed at the start gives an empty line');
  Check((T.GetLine(1) = '') and (T.GetLine(2) = ' x'), 'white space at the start of a line is kept');
  T.Free;

  T := NewTopic('one', False);
  P2 := NewPara('two', False);
  T.AddParagraph(P2);
  T.AddParagraph(NewPara('three', True));
  Check(T.NumLines = 3, 'every paragraph gives its lines');
  Check((T.GetLine(2) = 'two') and (T.GetLine(3) = 'three'), 'the lines of the later paragraphs');
  Check((T.Paragraphs.Next = P2) and (P2.Next.Next = nil), 'a paragraph is added at the end of the list');
  T.Free;

  T := NewTopic('a', False);
  T.AddParagraph(NewPara('', False));
  T.AddParagraph(NewPara('b', False));
  Check(T.NumLines = 2, 'an empty paragraph gives no line');
  Check(T.GetLine(2) = 'b', 'the line after an empty paragraph');
  T.Free;

  T := NewTopic('l1'#10'l2'#10'l3'#10'l4'#10, False);
  Check(T.GetLine(3) = 'l3', 'the third line');
  Check(T.GetLine(4) = 'l4', 'the fourth line, after the third');
  Check(T.GetLine(2) = 'l2', 'an earlier line starts again');
  Check(T.GetLine(2) = 'l2', 'the same line twice');
  Check(T.GetLine(4) = 'l4', 'a later line goes on from the line before');
  Check(T.GetLine(1) = 'l1', 'the first line');
  T.Free;

  T := NewTopic(WideCh + 'ab', False);
  Check(T.LongestLineWidth = 4, 'the width of a line counts columns and not bytes');
  T.Free;

  T := THelpTopic.Create;
  Check((T.NumLines = 0) and (T.GetLine(1) = '') and (T.LongestLineWidth = 0), 'a topic without paragraphs has no lines');
  T.Free;
end;

{ The cross references of a topic. }

procedure TestTopicRefs;
var
  T: THelpTopic;
  Loc: TPoint;
  Got: Byte;
  Target: LongInt;
begin
  T := NewTopic('see TOPIC now', False);
  T.AddParagraph(NewPara('next LINK here', False));
  AddRef(T, 7, 5, 5);
  AddRef(T, 9, 19, 4);
  Check(RefIs(T, 0, 4, 1, 5, 7), 'a reference in the first paragraph');
  Check(RefIs(T, 1, 5, 2, 4, 9), 'a reference in the second paragraph counts the size of the first');
  T.Free;

  T := NewTopic('alpha beta gamma', True);
  T.SetWidth(11);
  AddRef(T, 1, 7, 4);
  AddRef(T, 2, 12, 5);
  Check(RefIs(T, 0, 6, 1, 4, 1), 'a reference on the first line of a wrapped paragraph');
  Check(RefIs(T, 1, 0, 2, 5, 2), 'a reference at the start of the second line of a wrapped paragraph');
  T.Free;

  T := NewTopic(WideCh + 'ab', False);
  AddRef(T, 3, 4, 2);
  Check(RefIs(T, 0, 2, 1, 2, 3), 'the column and the length of a reference are in columns, its offset in bytes');
  T.Free;

  T := NewTopic('abc', False);
  AddRef(T, 4, 99, 3);
  Loc := Pt(-1, -1);
  Got := 255;
  Target := -1;
  T.GetCrossRef(0, Loc, Got, Target);
  Check((Loc.X = 0) and (Loc.Y = 0) and (Got = 0) and (Target = 4), 'an offset beyond the text gives the origin and no length');
  T.Free;

  T := NewTopic('abc', False);
  AddRef(T, 5, 2, 9);
  Check(RefIs(T, 0, 1, 1, 2, 5), 'a length beyond the paragraph is cut at its end');
  T.Free;
end;

{ Changes of the list of cross references. }

procedure TestTopicEdit;
var
  T: THelpTopic;
  Item: TCrossRef;
begin
  T := NewTopic('abc', False);
  Check((T.GetNumCrossRefs = 0) and (T.CrossRefs = nil), 'a new topic has no cross references');
  AddRef(T, 1, 1, 1);
  AddRef(T, 2, 2, 1);
  AddRef(T, 3, 3, 1);
  Check(T.GetNumCrossRefs = 3, 'three cross references were added');
  Check((T.CrossRefs[0].Ref = 1) and (T.CrossRefs[1].Ref = 2) and (T.CrossRefs[2].Ref = 3), 'they stay in order');
  Item.Ref := 20;
  Item.Offset := 2;
  Item.Length := 1;
  T.SetCrossRef(1, Item);
  Check((T.CrossRefs[1].Ref = 20) and (T.CrossRefs[0].Ref = 1) and (T.CrossRefs[2].Ref = 3), 'SetCrossRef replaces one');
  Item.Ref := 99;
  T.SetCrossRef(3, Item);
  T.SetCrossRef(-1, Item);
  Check((T.NumRefs = 3) and (T.CrossRefs[0].Ref = 1) and (T.CrossRefs[2].Ref = 3),
    'a number outside the list changes nothing');
  T.SetNumCrossRefs(5);
  Check((T.NumRefs = 5) and (T.CrossRefs[0].Ref = 1) and (T.CrossRefs[1].Ref = 20) and (T.CrossRefs[2].Ref = 3),
    'a longer list keeps the entries');
  T.SetNumCrossRefs(2);
  Check((T.NumRefs = 2) and (T.CrossRefs[0].Ref = 1) and (T.CrossRefs[1].Ref = 20), 'a shorter list keeps the first entries');
  T.SetNumCrossRefs(2);
  Check((T.NumRefs = 2) and (T.CrossRefs[1].Ref = 20), 'the same count changes nothing');
  T.SetNumCrossRefs(0);
  Check((T.NumRefs = 0) and (T.CrossRefs = nil), 'a list of no entries has no block');
  T.Free;
end;

{ The stream form of a topic. }

procedure CountingHandler(S: opstream; Value: LongInt);
begin
  Inc(HandlerCalls);
  S.WriteByte(Byte(Value));
end;

procedure TestTopicStream;
var
  Mem: TMemBuf;
  Wr: opstream;
  Rd: ipstream;
  T, Back: THelpTopic;
  Loaded: Pointer;
begin
  T := NewTopic('hi', True);
  AddRef(T, 3, 1, 2);
  Mem := TMemBuf.Create;
  Wr := opstream.Create(Mem);
  Wr.Put(T);
  Check(Mem.Size = 39, 'a topic of one paragraph and one reference is 39 bytes');
  Check((ByteAt(Mem, 0) = 2) and (ByteAt(Mem, 1) = Ord('[')) and (ByteAt(Mem, 2) = 10), 'the prefix of the object');
  Check((ByteAt(Mem, 3) = Ord('T')) and (ByteAt(Mem, 12) = Ord('c')), 'the type name');
  Check(LongAt(Mem, 13) = 1, 'the number of paragraphs');
  Check((ByteAt(Mem, 17) = 2) and (ByteAt(Mem, 18) = 0), 'the size of the paragraph is a word');
  Check(LongAt(Mem, 19) = 1, 'the flag that tells the paragraph is wrapped');
  Check((ByteAt(Mem, 23) = Ord('h')) and (ByteAt(Mem, 24) = Ord('i')), 'the text of the paragraph');
  Check(LongAt(Mem, 25) = 1, 'the number of references');
  Check((LongAt(Mem, 29) = 3) and (LongAt(Mem, 33) = 1) and (ByteAt(Mem, 37) = 2), 'the number, the offset and the length of the reference');
  Check(ByteAt(Mem, 38) = Ord(']'), 'the suffix of the object');

  Rd := ipstream.Create(Mem);
  Rd.Seekg(0);
  Loaded := nil;
  Rd.Get(Loaded);
  Back := THelpTopic(Loaded);
  Check(Back <> nil, 'a topic is read back');
  Check((Back.Paragraphs <> nil) and (Back.Paragraphs.Size = 2) and Back.Paragraphs.Wrap and (Back.Paragraphs.Next = nil),
    'the paragraph that is read back');
  Check(AnsiString(Back.Paragraphs.Text) = 'hi', 'the text of the paragraph that is read back');
  Check((Back.NumRefs = 1) and (Back.CrossRefs[0].Ref = 3) and (Back.CrossRefs[0].Offset = 1) and
    (Back.CrossRefs[0].Length = 2), 'the reference that is read back');
  Check(Back.GetLine(1) = 'hi', 'the line of the topic that is read back');
  Back.Free;
  Rd.Free;
  Wr.Free;
  T.Free;
  Mem.Free;

  { Three paragraphs, one of them empty. }
  T := NewTopic('one', False);
  T.AddParagraph(NewPara('two', True));
  T.AddParagraph(NewPara('', False));
  Mem := TMemBuf.Create;
  Wr := opstream.Create(Mem);
  Wr.Put(T);
  Rd := ipstream.Create(Mem);
  Rd.Seekg(0);
  Loaded := nil;
  Rd.Get(Loaded);
  Back := THelpTopic(Loaded);
  Check((Back.Paragraphs.Size = 3) and not Back.Paragraphs.Wrap, 'the first of three paragraphs');
  Check((Back.Paragraphs.Next.Size = 3) and Back.Paragraphs.Next.Wrap, 'the second of three paragraphs');
  Check((Back.Paragraphs.Next.Next.Size = 0) and (Back.Paragraphs.Next.Next.Next = nil), 'the third of three paragraphs');
  Check(Back.NumLines = 2, 'the lines of the topic that is read back');
  Back.Free;
  Rd.Free;
  Wr.Free;
  T.Free;
  Mem.Free;

  { A topic without paragraphs and references. }
  T := THelpTopic.Create;
  Mem := TMemBuf.Create;
  Wr := opstream.Create(Mem);
  Wr.Put(T);
  Check(Mem.Size = 22, 'an empty topic is 22 bytes');
  Rd := ipstream.Create(Mem);
  Rd.Seekg(0);
  Loaded := nil;
  Rd.Get(Loaded);
  Back := THelpTopic(Loaded);
  Check((Back <> nil) and (Back.Paragraphs = nil) and (Back.NumRefs = 0) and (Back.CrossRefs = nil), 'an empty topic is read back empty');
  Back.Free;
  Rd.Free;
  Wr.Free;
  T.Free;
  Mem.Free;

  { A handler that writes the number of a reference as one byte. }
  T := NewTopic('hi', True);
  AddRef(T, 3, 1, 2);
  HandlerCalls := 0;
  CrossRefHandler := @CountingHandler;
  Mem := TMemBuf.Create;
  Wr := opstream.Create(Mem);
  Wr.Put(T);
  CrossRefHandler := @NotAssigned;
  Check(HandlerCalls = 1, 'the handler is called once for each reference');
  Check(Mem.Size = 36, 'the handler writes one byte in place of four');
  Check((ByteAt(Mem, 29) = 3) and (LongAt(Mem, 30) = 1) and (ByteAt(Mem, 34) = 2) and (ByteAt(Mem, 35) = Ord(']')),
    'the offset and the length follow the byte of the handler');
  Check(Pointer(CrossRefHandler) = Pointer(@NotAssigned), 'the default handler is back');
  Wr.Free;
  T.Free;
  Mem.Free;
end;

{ THelpFile. }

procedure TestFile;
var
  Mem: TMemBuf;
  Strm: iopstream;
  HF: THelpFile;
  A, B, C, Got, Other: THelpTopic;
begin
  Mem := TMemBuf.Create;
  Strm := iopstream.Create(Mem);
  HF := THelpFile.Create(Strm);
  Check(HF.Modified, 'a file on an empty stream is new');
  Check(HF.IndexPos = 12, 'a new file puts the first topic after its 12 bytes of header');
  Check((HF.Index <> nil) and (HF.Index.Size = 0), 'a new file has an empty index');
  Check(HF.Stream = Strm, 'the file keeps its stream');
  A := NewTopic('first topic', False);
  B := NewTopic('second', False);
  HF.RecordPositionInIndex(1);
  HF.PutTopic(A);
  Check(HF.IndexPos = 51, 'the position after the first topic');
  Check(Mem.Size = 51, 'the stream holds the header and the first topic');
  HF.RecordPositionInIndex(2);
  HF.PutTopic(B);
  Check(HF.IndexPos = 85, 'the position after the second topic');
  Check((HF.Index.Position(1) = 12) and (HF.Index.Position(2) = 51) and (HF.Index.Position(3) = -1),
    'the positions of the topics in the index');
  A.Free;
  B.Free;
  HF.Free;
  Check(Mem.Size = 141, 'the file ends with its index');
  Check((ByteAt(Mem, 0) = $46) and (ByteAt(Mem, 1) = $42) and (ByteAt(Mem, 2) = $48) and (ByteAt(Mem, 3) = $46),
    'the header starts with the magic number');
  Check(LongAt(Mem, 4) = 133, 'the header holds the size less 8');
  Check(LongAt(Mem, 8) = 85, 'the header holds the position of the index');
  Check((ByteAt(Mem, 12) = 2) and (ByteAt(Mem, 51) = 2) and (ByteAt(Mem, 85) = 2), 'the topics and the index are objects');

  Strm := iopstream.Create(Mem);
  HF := THelpFile.Create(Strm);
  Check(not HF.Modified, 'a file that was read is not modified');
  Check(HF.IndexPos = 85, 'the position of the index is read');
  Check((HF.Index.Size = 10) and (HF.Index.Position(1) = 12) and (HF.Index.Position(2) = 51) and
    (HF.Index.Position(3) = -1), 'the index is read');
  Got := HF.GetTopic(1);
  Check((Got.NumLines = 1) and (Got.GetLine(1) = 'first topic'), 'the first topic is read');
  Other := HF.GetTopic(1);
  Check(Other <> Got, 'a topic is read again into a new object');
  Other.Free;
  Got.Free;
  Got := HF.GetTopic(2);
  Check((Got.NumLines = 1) and (Got.GetLine(1) = 'second'), 'the second topic is read');
  Got.Free;
  Got := HF.GetTopic(3);
  Check((Got.NumLines = 2) and (Got.GetLine(1) = '') and (Got.GetLine(2) = InvalidLine),
    'a context that has no topic gives the invalid topic');
  Check(Got.NumRefs = 0, 'the invalid topic has no references');
  Got.Free;
  Got := HF.GetTopic(0);
  Check(Got.GetLine(2) = InvalidLine, 'the context 0 has no topic');
  Got.Free;
  Got := HF.InvalidTopic;
  Check((Got.Paragraphs <> nil) and not Got.Paragraphs.Wrap and (Got.Paragraphs.Next = nil), 'the invalid topic is one paragraph that is not wrapped');
  Check(Got.Paragraphs.Size = Length(#10 + InvalidLine), 'its size is the length of the text');
  Got.Free;
  Check(not HF.Modified, 'reading topics does not modify the file');
  HF.Free;
  Check(Mem.Size = 141, 'a file that was not modified writes nothing');

  { Recording a position changes the index and writes it again. }
  Strm := iopstream.Create(Mem);
  HF := THelpFile.Create(Strm);
  HF.RecordPositionInIndex(5);
  Check(HF.Modified, 'recording a position modifies the file');
  HF.Free;
  Strm := iopstream.Create(Mem);
  HF := THelpFile.Create(Strm);
  Check((HF.Index.Position(5) = 85) and (HF.Index.Position(1) = 12), 'the recorded position and the old ones are in the index');
  HF.Free;

  { A topic that is added to a file that was read goes where the index was. }
  Strm := iopstream.Create(Mem);
  HF := THelpFile.Create(Strm);
  C := NewTopic('third', False);
  HF.RecordPositionInIndex(6);
  HF.PutTopic(C);
  Check(HF.IndexPos = 118, 'the new topic starts at the old index and ends at 118');
  C.Free;
  HF.Free;
  Check(Mem.Size = 174, 'the index is written after the new topic');
  Check((LongAt(Mem, 4) = 166) and (LongAt(Mem, 8) = 118), 'the header follows the new index position');
  Strm := iopstream.Create(Mem);
  HF := THelpFile.Create(Strm);
  Got := HF.GetTopic(6);
  Check(Got.GetLine(1) = 'third', 'the new topic is read');
  Got.Free;
  Got := HF.GetTopic(2);
  Check(Got.GetLine(1) = 'second', 'an old topic is still read');
  Got.Free;
  HF.Free;
  Mem.Free;
end;

procedure TestFileHeader;
var
  Mem: TMemBuf;
  HF: THelpFile;
  Junk: string;
  Magic: LongInt;
begin
  Junk := 'abc';
  Mem := TMemBuf.Create;
  Mem.SPutN(Junk[1], Length(Junk));
  HF := THelpFile.Create(iopstream.Create(Mem));
  Check(HF.Modified and (HF.IndexPos = 12) and (HF.Index <> nil) and (HF.Index.Size = 0),
    'a stream of three bytes is a new file');
  HF.Free;
  Check(Mem.Size = 28, 'a new file gets its header and its empty index');
  Check((LongAt(Mem, 0) = magicHeader) and (LongAt(Mem, 4) = 20) and (LongAt(Mem, 8) = 12), 'the header of the new file');
  HF := THelpFile.Create(iopstream.Create(Mem));
  Check(not HF.Modified and (HF.IndexPos = 12) and (HF.Index.Size = 0), 'the new file is read back');
  HF.Free;
  Mem.Free;

  Magic := magicHeader;
  Mem := TMemBuf.Create;
  Mem.SPutN(Magic, SizeOf(Magic));
  Mem.SPutN(Junk[1], 2);
  HF := THelpFile.Create(iopstream.Create(Mem));
  Check(HF.Modified and (HF.IndexPos = 12), 'the magic number with fewer than 12 bytes is a new file');
  HF.Free;
  Check(Mem.Size = 28, 'the file is made new');
  Mem.Free;

  Junk := StringOfChar('x', 20);
  Mem := TMemBuf.Create;
  Mem.SPutN(Junk[1], Length(Junk));
  HF := THelpFile.Create(iopstream.Create(Mem));
  Check(HF.Modified and (HF.IndexPos = 12), 'a wrong magic number is a new file');
  HF.Free;
  Check((Mem.Size = 28) and (LongAt(Mem, 0) = magicHeader), 'the file is made new over the old bytes');
  Mem.Free;
end;

{ THelpViewer without an owner. }

function MakeProbe(Mem: TMemBuf; Context: Word; out HB, VB: TScrollBar; W, H: Integer): TProbe;
begin
  HB := TScrollBar.Create(Rc(0, H, W, H + 1));
  VB := TScrollBar.Create(Rc(W, 0, W + 1, H));
  Result := TProbe.Create(Rc(0, 0, W, H), HB, VB, OpenSample(Mem), Context);
  Result.State := Result.State or sfSelected;
end;

procedure FreeProbe(V: TProbe; HB, VB: TScrollBar);
begin
  TvObject.DestroyObject(V);
  TvObject.DestroyObject(HB);
  TvObject.DestroyObject(VB);
end;

procedure TestViewer;
var
  Mem: TMemBuf;
  HB, VB, HB2, VB2, HB3, VB3: TScrollBar;
  V, V2, V3: TProbe;
  Ev: TEvent;
  Pal: TPalette;
  Lim: TPoint;
begin
  Mem := TMemBuf.Create;
  BuildSample(Mem);

  V := MakeProbe(Mem, 1, HB, VB, 8, 2);
  Check((V.Topic <> nil) and (V.HFile <> nil), 'the viewer holds the file and the topic');
  Check(V.Selected = 1, 'the first reference is selected');
  Check((V.Options and ofSelectable) <> 0, 'the viewer can be selected');
  Check(V.GrowMode = Byte(gfGrowHiX or gfGrowHiY), 'the viewer grows with the bottom right corner');
  Lim := V.LimitOf;
  Check((Lim.X = 11) and (Lim.Y = 3), 'the limit is the longest line and the number of lines');
  Check((HB.MaxVal = 3) and (VB.MaxVal = 1) and (HB.PgStep = 7) and (VB.PgStep = 1), 'the bars follow the limit');
  Pal := V.GetPalette;
  Check((EntryOf(Pal, 0) = 3) and (EntryOf(Pal, 1) = 6) and (EntryOf(Pal, 2) = 7) and (EntryOf(Pal, 3) = 8),
    'the palette of the viewer');
  Check(V.GetPalette = Pal, 'the palette is shared');

  Ev := KeyEv(kbTab);
  V.HandleEvent(Ev);
  Check((V.Selected = 2) and (Ev.What = evNothing), 'Tab selects the next reference and takes the key');
  Check((VB.Value = 1) and (HB.Value = 0), 'the reference below the view scrolls the vertical bar');
  Ev := KeyEv(kbTab);
  V.HandleEvent(Ev);
  Check(V.Selected = 1, 'Tab after the last reference selects the first');
  Ev := KeyEv(kbShiftTab);
  V.HandleEvent(Ev);
  Check((V.Selected = 2) and (Ev.What = evNothing), 'Shift-Tab before the first reference selects the last');
  Ev := KeyEv(kbShiftTab);
  V.HandleEvent(Ev);
  Check(V.Selected = 1, 'Shift-Tab selects the one before');

  Ev := KeyEv(kbF1);
  V.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (V.Selected = 1), 'another key is left alone');
  Ev := KeyEv(kbEsc);
  V.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'Esc is taken, and put back as a command that nobody receives');
  Ev := CmdEv(cmClose);
  V.HandleEvent(Ev);
  Check(Ev.What = evCommand, 'a close command is left alone while the viewer has no owner');
  Ev := CmdEv(cmOK);
  V.HandleEvent(Ev);
  Check(Ev.What = evCommand, 'another command is left alone');

  Ev := KeyEv(kbEnter);
  V.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'Enter is taken');
  Check(V.Topic.GetLine(1) = 'Beta text', 'Enter follows the selected reference');
  Check((V.Selected = 1) and (V.Topic.GetNumCrossRefs = 0), 'the new topic starts with the selection at 1');
  Lim := V.LimitOf;
  Check((Lim.X = 9) and (Lim.Y = 1), 'the limit follows the new topic');
  Check((VB.Value = 0) and (HB.Value = 0), 'the new topic is shown from the top');
  Ev := KeyEv(kbEnter);
  V.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (V.Topic.GetLine(1) = 'Beta text'), 'Enter without a reference changes nothing');
  Ev := KeyEv(kbShiftTab);
  V.HandleEvent(Ev);
  Check(V.Selected = 0, 'Shift-Tab without references selects 0');
  Ev := KeyEv(kbTab);
  V.HandleEvent(Ev);
  Check(V.Selected = 1, 'Tab without references selects 1');
  FreeProbe(V, HB, VB);

  { The mouse. }
  V := MakeProbe(Mem, 1, HB, VB, 8, 2);
  Ev := ClickEv(0, 0);
  V.HandleEvent(Ev);
  Check((Ev.What = evMouseDown) and (V.Topic.GetNumCrossRefs = 2), 'a click that is not on a reference is left alone');
  Ev := ClickEv(7, 1);
  V.HandleEvent(Ev);
  Check((Ev.What = evMouseDown) and (V.Topic.GetNumCrossRefs = 2), 'a click right after a reference is not on it');
  Ev := ClickEv(2, 1);
  V.HandleEvent(Ev);
  Check((Ev.What = evMouseDown) and (V.Topic.GetNumCrossRefs = 2), 'a click right before a reference is not on it');
  Ev := ClickEv(4, 1);
  V.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a click on a reference is taken');
  Check(V.Topic.GetLine(1) = 'Beta text', 'a click on the first reference follows it');
  Check(V.Selected = 1, 'the new topic has the selection at 1');
  FreeProbe(V, HB, VB);

  V := MakeProbe(Mem, 1, HB, VB, 8, 2);
  Ev := ClickEv(6, 2);
  V.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (V.Topic.GetLine(1) = 'Gamma text'), 'a click on the second reference follows it');
  FreeProbe(V, HB, VB);

  { A context that has no topic. }
  V := MakeProbe(Mem, 99, HB, VB, 8, 2);
  Check((V.Topic.NumLines = 2) and (V.Topic.GetLine(2) = InvalidLine), 'the viewer shows the invalid topic');
  Lim := V.LimitOf;
  Check((Lim.X = Length(InvalidLine)) and (Lim.Y = 2), 'the limit of the invalid topic');
  FreeProbe(V, HB, VB);

  { A new size gives a new wrapping. }
  V2 := MakeProbe(Mem, 5, HB2, VB2, 11, 3);
  Lim := V2.LimitOf;
  Check((Lim.X = 10) and (Lim.Y = 2), 'a wrapped topic at the width 11');
  V2.ChangeBounds(Rc(0, 0, 6, 3));
  Lim := V2.LimitOf;
  Check((V2.Size.X = 6) and (Lim.X = 5) and (Lim.Y = 3), 'the same topic at the width 6');
  Check((HB2.MaxVal = 0) and (VB2.MaxVal = 0), 'the bars follow the new limit');
  V3 := MakeProbe(Mem, 5, HB3, VB3, 11, 3);
  Check(V3.Topic.NumLines = 2, 'a second viewer of the same file');
  FreeProbe(V3, HB3, VB3);
  FreeProbe(V2, HB2, VB2);

  Mem.Free;
end;

{ THelpWindow with the viewer inside. }

function IsHelpViewer(P: TView; Args: Pointer): Boolean;
begin
  Result := P is THelpViewer;
end;

type
  TBarCount = record
    Total: Integer;
    Keyed: Integer;
  end;
  PBarCount = ^TBarCount;

{ Counts the scroll bars among the views of a group, and those of them that take the keys. }
procedure CountBar(P: TView; Args: Pointer);
begin
  if not (P is TScrollBar) then
    Exit;
  Inc(PBarCount(Args)^.Total);
  if (P.Options and ofPostProcess) <> 0 then
    Inc(PBarCount(Args)^.Keyed);
end;

procedure TestWindow;
var
  Mem: TMemBuf;
  Stage: TStage;
  Win: THelpWindow;
  Vw: THelpViewer;
  Ev: TEvent;
  Pal: TPalette;
  Verdict: Word;
  Bars: TBarCount;
begin
  Mem := TMemBuf.Create;
  BuildSample(Mem);
  Stage := MakeStage;
  Win := THelpWindow.Create(OpenSample(Mem), 4);
  Check(AnsiString(Win.Title) = 'Help', 'the title of the window');
  Check((Win.Number = 0) and (Win.Frame <> nil), 'the window has no number and has a frame');
  Check((Win.Flags and wfClose) <> 0, 'the window can be closed');
  Check((Win.Size.X = 50) and (Win.Size.Y = 18), 'the window is 50 by 18');
  Check((Win.Options and ofCentered) = ofCentered, 'the window is centered');
  Pal := Win.GetPalette;
  Check((EntryOf(Pal, 0) = 8) and (EntryOf(Pal, 1) = $80) and (EntryOf(Pal, 5) = $84) and (EntryOf(Pal, 8) = $87),
    'the palette of the window');
  Check(Win.GetPalette = Pal, 'the palette is shared');
  Vw := THelpViewer(Win.FirstThat(@IsHelpViewer, nil));
  Check(Vw <> nil, 'the window holds a help viewer');
  Check((Vw.Origin.X = 2) and (Vw.Origin.Y = 1) and (Vw.Size.X = 46) and (Vw.Size.Y = 16), 'the viewer fills the window inside the frame');
  Bars.Total := 0;
  Bars.Keyed := 0;
  Win.ForEach(@CountBar, @Bars);
  Check(Bars.Total = 2, 'the window holds the two bars of the viewer');
  Check(Bars.Keyed = 2, 'the bars take the keys');
  Check((Vw.HFile <> nil) and (Vw.Topic <> nil) and (Vw.Selected = 1), 'the viewer shows the topic of the context');

  Stage.Insert(Win);
  Check((Win.Origin.X = 15) and (Win.Origin.Y = 3), 'the window is centered in the stage');
  WipeScreen;
  Vw.DrawView;
  Check((RowText(4, 17, 3) = 'L01') and (RowText(5, 17, 3) = 'L02'), 'the viewer shows the lines of the topic');
  Check(AttrAt(17, 4) = AttrSelected, 'the selected reference has the third color');
  Check((AttrAt(19, 4) = AttrSelected) and (AttrAt(20, 4) = AttrNormal), 'the reference covers its columns');
  Check(AttrAt(17, 5) = AttrNormal, 'the text has the first color');
  Check(AttrAt(40, 8) = AttrNormal, 'the blank part of a row has the first color');

  Ev := KeyEv(kbTab);
  Vw.HandleEvent(Ev);
  Check((Vw.Selected = 2) and (Ev.What = evNothing), 'Tab selects the second reference');
  Check(Vw.Delta.Y = 2, 'the second reference is on the line 18, so the view scrolls by 2');
  Check((RowText(4, 17, 3) = 'L03') and (RowText(18, 17, 3) = 'L17') and (RowText(19, 17, 3) = 'L18'),
    'the rows after the scroll');
  Check((AttrAt(17, 19) = AttrSelected) and (AttrAt(17, 18) = AttrNormal), 'the second reference is selected');
  Ev := KeyEv(kbShiftTab);
  Vw.HandleEvent(Ev);
  Check((Vw.Selected = 1) and (Vw.Delta.Y = 0), 'Shift-Tab goes back to the first reference and scrolls back');
  Check((RowText(4, 17, 3) = 'L01') and (AttrAt(17, 4) = AttrSelected), 'the first rows again');

  Ev := KeyEv(kbTab);
  Vw.HandleEvent(Ev);
  Ev := KeyEv(kbTab);
  Vw.HandleEvent(Ev);
  Check((Vw.Selected = 1) and (AttrAt(17, 4) = AttrSelected), 'two Tab keys return to the first reference');

  Ev := KeyEv(kbEnter);
  Vw.HandleEvent(Ev);
  Check(Vw.Topic.GetLine(1) = 'Beta text', 'Enter shows the topic of the reference');
  Check((RowText(4, 17, 9) = 'Beta text') and (CellChar(17, 5) = ' ') and (AttrAt(17, 5) = AttrNormal),
    'the new topic is drawn and the old rows are blank');

  Stage.Rewind;
  Ev := KeyEv(kbEsc);
  Vw.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'Esc is taken');
  Check((Stage.PutCount = 1) and (Stage.LastPut.What = evCommand) and (Stage.LastPut.Message.Command = cmClose),
    'Esc is put back as the command cmClose through the owners');
  Ev := CmdEv(cmClose);
  Vw.HandleEvent(Ev);
  Check(Ev.What = evCommand, 'cmClose is left alone while the window is not modal');
  TvObject.DestroyObject(Stage);
  Mem.Free;

  { The modal loop ends at Esc. }
  Mem := TMemBuf.Create;
  BuildSample(Mem);
  Stage := MakeStage;
  Win := THelpWindow.Create(OpenSample(Mem), 1);
  Stage.Rewind;
  Stage.AddEvent(KeyEv(kbEsc));
  Verdict := Stage.ExecView(Win);
  Check(Verdict = cmClose, 'Esc ends the modal loop of the window with cmClose');
  Check(Stage.Unhandled = 0, 'every event of the loop was handled');
  TvObject.DestroyObject(Win);
  TvObject.DestroyObject(Stage);
  Mem.Free;

  { The command cmClose ends it too. }
  Mem := TMemBuf.Create;
  BuildSample(Mem);
  Stage := MakeStage;
  Win := THelpWindow.Create(OpenSample(Mem), 1);
  Stage.Rewind;
  Stage.AddEvent(CmdEv(cmClose));
  Verdict := Stage.ExecView(Win);
  Check(Verdict = cmClose, 'the command cmClose ends the modal loop with cmClose');
  TvObject.DestroyObject(Win);
  TvObject.DestroyObject(Stage);
  Mem.Free;
end;

var
  QueueBackend: TEventBackend;
  Queue: TEventQueue;

begin
  StagePal := MakeStagePalette;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;
  TScreen.ScreenBuffer := @ScreenCells[0];
  TScreen.CursorLines := 20;
  QueueBackend := TEventBackend.Create;
  TEventQueue.Backend := QueueBackend;
  Queue := TEventQueue.Create;

  TestConstants;
  TestIndex;
  TestTopicLines;
  TestTopicRefs;
  TestTopicEdit;
  TestTopicStream;
  TestFile;
  TestFileHeader;
  TestViewer;
  TestWindow;

  Queue.Free;
  TEventQueue.Backend := nil;
  QueueBackend.Free;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TScreen.ScreenBuffer := nil;
  StagePal.Free;
  Done;
end.
