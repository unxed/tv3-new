{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (TFileInputLine, TFileInfoPane, TFileDialog and the option flags fd...),
  source/tvision/stddlg.cpp (TFileInputLine, TFileInfoPane), source/tvision/tfildlg.cpp,
  source/tvision/tdircoll.cpp, source/tvision/tfillist.cpp, include/tvision/tv.h, include/tvision/views.h,
  include/tvision/ttypes.h, include/tvision/config.h, include/tvision/util.h, source/tvision/misc.cpp,
  source/tvision/tvtext2.cpp
  See COPYRIGHT.magiblot.

  Test program of the unit TvFileDlg.

  The first part has no application: a file dialog keeps the bounds of its constructor, and the dialog of the test
  records the events that it gets, which are the messages of its views. The second part has an
  application, a TApplication of the test that reads its events from a script of one event: when the modal dialog
  of a message box asks for its first event, the application takes a snapshot of the dialog (its title and its
  text) and answers cmOK. Any later request for an event is a cmCancel, so that a failure ends the dialog and does
  not wait. The size of the application is changed by the test to give the file dialog the sizes of screen that
  its constructor tells apart.

  The lines of the info pane are read from the buffer of the dialog that owns it: the test gives the dialog a buffer
  of cells and exposes it, as the other tests of views do for their root. The tests that touch
  files make a directory of their own under the directory of temporary files and remove it at the end. The
  directory rd of the tests has the files a.txt, b.txt and c.dat, the directories sub1 and sub2 and the hidden
  directory .hdir. }
program t_filedlg;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads, SysUtils, TvGeom, TvObjs, TvPath, TvColors, TvCell, TvEvents, TvTimer, TvSys, TvDrawBuf, TvScreen,
  TvViews, TvWindow, TvInput, TvList, TvDialog, TvHist, TvApp, TvMsgBox, TvFiles, TvFileDlg;

{$I testlib.inc}

type
  TFakeScreen = class(TScreenBackend)
  public
    Cols, Rows, Mode, CaretSize: Word;
    procedure SetUpConsole; override;
    procedure RestoreConsole; override;
    function GetCaretSize: Word; override;
    procedure SetCaretSize(ASize: Word); override;
    function GetScreenRows: Word; override;
    function GetScreenCols: Word; override;
    function GetScreenMode: Word; override;
    procedure SetScreenMode(AMode: Word); override;
    function AllocateScreenBuffer: PScreenCell; override;
    procedure FreeScreenBuffer(ABuffer: PScreenCell); override;
  end;

  TFakeEvents = class(TEventBackend)
  public
    procedure MouseSuspend; override;
    procedure MouseSetRange(MaxX, MaxY: Integer); override;
  end;

  TSnapshot = record
    Taken: Boolean;
    Title: string;
    MessageText: string;
  end;

  TMsgApp = class(TApplication)
  public
    Armed: Boolean;
    Reply: TEvent;
    constructor Create; reintroduce;
    procedure GetEvent(var Event: TEvent); override;
  end;

  { A file dialog that remembers the events that it gets, and the events that it puts back. }
  TProbeDialog = class(TFileDialog)
  public
    PutCount: Integer;
    LastPut: TEvent;
    procedure HandleEvent(var Event: TEvent); override;
    procedure PutEvent(var Event: TEvent); override;
  end;

  TButtonPeek = class(TButton)
  public
    function CommandOf: Word;
    function FlagsOf: Byte;
  end;

  TLabelPeek = class(TLabel)
  public
    function LinkOf: TView;
  end;

  THistoryPeek = class(THistory)
  public
    function LinkOf: TInputLine;
    function IdOf: Word;
  end;

  { A view that is not valid for any command but cmCancel. }
  TInvalidView = class(TView)
  public
    function Valid(Command: Word): Boolean; override;
  end;

const
  { The size of the screen of the second part. }
  ScrH = 20;
  ScrW = 4 * ScrH;
  { The size of a file dialog that has no application. }
  DlgW = 49;
  DlgH = 19;

var
  ScreenCells: array[0..80 * 25 - 1] of TScreenCell;
  Fake: TFakeScreen;
  FakeEvents: TFakeEvents;
  SavedScreen: TScreenBackend;
  SavedEvents: TEventBackend;
  App: TMsgApp;
  Snap: TSnapshot;
  StrayReads: Integer;

  { The directory of the tests and the wild card that points into it. }
  TempRoot, WildText: string;

  { What the probe dialog saw last. }
  LastInfo: Pointer;
  LastReceiver: TView;
  LastCommand, LastWhat: Word;
  MessageCount: Integer;

  { The cells of the buffer of a dialog of 49 by 19 cells, which has no application. }
  DialogCells: array[0..DlgW * DlgH - 1] of TScreenCell;

  Buf: array[0..MaxPath + 31] of AnsiChar;

{ The fake devices }

procedure TFakeScreen.SetUpConsole;
begin
end;

procedure TFakeScreen.RestoreConsole;
begin
end;

function TFakeScreen.GetCaretSize: Word;
begin
  Result := CaretSize;
end;

procedure TFakeScreen.SetCaretSize(ASize: Word);
begin
  CaretSize := ASize;
end;

function TFakeScreen.GetScreenRows: Word;
begin
  Result := Rows;
end;

function TFakeScreen.GetScreenCols: Word;
begin
  Result := Cols;
end;

function TFakeScreen.GetScreenMode: Word;
begin
  Result := Mode;
end;

procedure TFakeScreen.SetScreenMode(AMode: Word);
begin
  Mode := AMode;
end;

function TFakeScreen.AllocateScreenBuffer: PScreenCell;
begin
  Result := @ScreenCells[0];
end;

procedure TFakeScreen.FreeScreenBuffer(ABuffer: PScreenCell);
begin
end;

procedure TFakeEvents.MouseSuspend;
begin
end;

procedure TFakeEvents.MouseSetRange(MaxX, MaxY: Integer);
begin
end;

procedure OnCaret(X, Y: Integer);
begin
end;

procedure OnScreenWrite(X, Y: Integer; Cells: PScreenCell; Count: Integer);
begin
end;

{ The classes of the test }

function TButtonPeek.CommandOf: Word;
begin
  Result := Command;
end;

function TButtonPeek.FlagsOf: Byte;
begin
  Result := Flags;
end;

function TLabelPeek.LinkOf: TView;
begin
  Result := Link;
end;

function THistoryPeek.LinkOf: TInputLine;
begin
  Result := Link;
end;

function THistoryPeek.IdOf: Word;
begin
  Result := HistoryId;
end;

function TInvalidView.Valid(Command: Word): Boolean;
begin
  Result := Command = cmCancel;
end;

procedure TProbeDialog.HandleEvent(var Event: TEvent);
begin
  Inc(MessageCount);
  LastReceiver := Self;
  LastWhat := Event.What;
  LastCommand := Event.Message.Command;
  LastInfo := Event.Message.InfoPtr;
  inherited HandleEvent(Event);
end;

procedure TProbeDialog.PutEvent(var Event: TEvent);
begin
  Inc(PutCount);
  LastPut := Event;
end;

function MakeDesk(R: TRect): TDeskTop;
begin
  Result := TDeskTop.Create(R);
end;

procedure TakeSnapshot(Top: TView);
var
  dialog: TGroup;
  position: Integer;
  member: TView;
  textBuffer: array[0..255] of AnsiChar;
begin
  Snap.Taken := False;
  Snap.Title := '';
  Snap.MessageText := '';
  if not (Top is TGroup) then
    Exit;
  dialog := TGroup(Top);
  Snap.Taken := True;
  if (Top is TWindow) and (TWindow(Top).Title <> nil) then
    Snap.Title := string(TWindow(Top).Title);
  position := 1;
  member := dialog.At(SmallInt(position));
  while member <> nil do
  begin
    if (member is TStaticText) and not (member is TLabel) then
    begin
      textBuffer[0] := #0;
      TStaticText(member).GetText(@textBuffer[0]);
      Snap.MessageText := string(PAnsiChar(@textBuffer[0]));
      Exit;
    end;
    Inc(position);
    member := dialog.At(SmallInt(position));
  end;
end;

constructor TMsgApp.Create;
begin
  inherited Create(nil, nil, @MakeDesk);
end;

procedure TMsgApp.GetEvent(var Event: TEvent);
begin
  if Armed then
  begin
    Armed := False;
    TakeSnapshot(Current);
    Event := Reply;
    Exit;
  end;
  if Pending.What <> evNothing then
  begin
    inherited GetEvent(Event);
    Exit;
  end;
  Inc(StrayReads);
  FillChar(Event, SizeOf(Event), 0);
  Event.What := evCommand;
  Event.Message.Command := cmCancel;
end;

{ Small helpers }

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function RectIs(const R: TRect; AX, AY, BX, BY: Integer): Boolean;
begin
  Result := (R.A.X = AX) and (R.A.Y = AY) and (R.B.X = BX) and (R.B.Y = BY);
end;

{ The number of the entry I of a palette. }
function PalByte(P: TPalette; I: Integer): Integer;
var
  A: TColorAttr;
begin
  A := P.Items[I];
  Result := A.ToBIOS;
end;

procedure DrainPosted;
var
  Ev: TEvent;
begin
  while TEventQueue.GetPostedEvent(Ev) do
    ;
end;

procedure ArmCommand(Command: Word);
begin
  FillChar(App.Reply, SizeOf(App.Reply), 0);
  App.Reply.What := evCommand;
  App.Reply.Message.Command := Command;
  App.Armed := True;
  Snap.Taken := False;
  Snap.Title := '';
  Snap.MessageText := '';
end;

function CommandEvent(Command: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evCommand;
  Result.Message.Command := Command;
end;

function BroadcastEvent(Command: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evBroadcast;
  Result.Message.Command := Command;
end;

procedure FillBuffer(const Content: string);
begin
  FillChar(Buf, SizeOf(Buf), 0);
  if Length(Content) > 0 then
    Move(Content[1], Buf[0], Length(Content));
end;

function BufferText: string;
begin
  Result := string(PAnsiChar(@Buf[0]));
end;

procedure ResetCounters;
begin
  MessageCount := 0;
  LastReceiver := nil;
  LastWhat := 0;
  LastCommand := 0;
  LastInfo := nil;
end;

procedure MakeFile(const Path: string; Bytes: Integer);
var
  handle: THandle;
  block: array[0..63] of Byte;
begin
  handle := FileCreate(Path);
  FillChar(block, SizeOf(block), 65);
  if Bytes > 0 then
    FileWrite(handle, block, Bytes);
  FileClose(handle);
end;

procedure RemoveTree(const Path: string);
var
  found: SysUtils.TSearchRec;
  status: Integer;
begin
  status := FindFirst(Path + '*', faAnyFile, found);
  while status = 0 do
  begin
    if (found.Name <> '.') and (found.Name <> '..') then
    begin
      if (found.Attr and faDirectory) <> 0 then
        RemoveTree(Path + found.Name + '/')
      else
        DeleteFile(Path + found.Name);
    end;
    status := FindNext(found);
  end;
  FindClose(found);
  RemoveDir(Path);
end;

procedure MakeTree;
begin
  TempRoot := PathAddSep(PathNormalize(IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tvfiledlg_' +
    IntToStr(GetProcessID) + '/'));
  RemoveTree(TempRoot);
  ForceDirectories(TempRoot + 'rd/sub1');
  ForceDirectories(TempRoot + 'rd/sub2');
  ForceDirectories(TempRoot + 'rd/.hdir');
  MakeFile(TempRoot + 'rd/a.txt', 5);
  MakeFile(TempRoot + 'rd/b.txt', 0);
  MakeFile(TempRoot + 'rd/c.dat', 3);
  WildText := TempRoot + 'rd/*.txt';
end;

function MakeDialog(const Wild: string; Opts: Word): TProbeDialog;
begin
  Result := TProbeDialog.Create(Wild, 'Open file', '~N~ame', Opts, 7);
end;

function ViewCount(Group: TGroup): Integer;
begin
  Result := 0;
  while Group.At(SmallInt(Result + 1)) <> nil do
    Inc(Result);
end;

{ The Nth subview that is an instance of ViewClass, counted in the order in which the views were inserted. }
function NthOfClass(Group: TGroup; ViewClass: TClass; Nth: Integer): TView;
var
  position, seen: Integer;
  member: TView;
begin
  Result := nil;
  seen := 0;
  for position := ViewCount(Group) downto 1 do
  begin
    member := Group.At(SmallInt(position));
    if member.InheritsFrom(ViewClass) then
    begin
      Inc(seen);
      if seen = Nth then
      begin
        Result := member;
        Exit;
      end;
    end;
  end;
end;

function LabelText(Item: TView): string;
var
  textBuffer: array[0..255] of AnsiChar;
begin
  textBuffer[0] := #0;
  TStaticText(Item).GetText(@textBuffer[0]);
  Result := string(PAnsiChar(@textBuffer[0]));
end;

function ButtonIs(Group: TGroup; Nth: Integer; Command: Word; Flags: Byte; const Caption: string;
  AX, AY, BX, BY: Integer): Boolean;
var
  button: TView;
begin
  Result := False;
  button := NthOfClass(Group, TButton, Nth);
  if button = nil then
    Exit;
  Result := (TButtonPeek(button).CommandOf = Command) and (TButtonPeek(button).FlagsOf = Flags) and
    (string(TButton(button).Title) = Caption) and RectIs(button.GetBounds, AX, AY, BX, BY);
end;

procedure DestroyDialog(Dlg: TProbeDialog);
begin
  TvObject.DestroyObject(Dlg);
end;

{ The tests of the first part: no application }

procedure TestConstants;
begin
  Check(fdOKButton = $0001, 'fdOKButton is 1');
  Check(fdOpenButton = $0002, 'fdOpenButton is 2');
  Check(fdReplaceButton = $0004, 'fdReplaceButton is 4');
  Check(fdClearButton = $0008, 'fdClearButton is 8');
  Check(fdHelpButton = $0010, 'fdHelpButton is $10');
  Check(fdNoLoadDir = $0100, 'fdNoLoadDir is $100');
  Check(MaxPath = 260, 'MaxPath is 260');
  Check(TFileDialog.FilesText = '~F~iles', 'filesText is the text of the C++');
  Check(TFileDialog.OpenText = '~O~pen', 'openText is the text of the C++');
  Check(TFileDialog.OkText = 'O~K~', 'okText is the text of the C++');
  Check(TFileDialog.ReplaceText = '~R~eplace', 'replaceText is the text of the C++');
  Check(TFileDialog.ClearText = '~C~lear', 'clearText is the text of the C++');
  Check(TFileDialog.CancelText = 'Cancel', 'cancelText is the text of the C++');
  Check(TFileDialog.HelpText = '~H~elp', 'helpText is the text of the C++');
  Check(TFileDialog.InvalidDriveText = 'Invalid drive or directory', 'invalidDriveText is the text of the C++');
  Check(TFileDialog.InvalidFileText = 'Invalid file name', 'invalidFileText is the text of the C++');
  Check(TFileInfoPane.PmText = 'p', 'pmText is the text of the C++');
  Check(TFileInfoPane.AmText = 'a', 'amText is the text of the C++');
  Check((TFileInfoPane.Months[0] = '') and (TFileInfoPane.Months[1] = 'Jan') and (TFileInfoPane.Months[2] = 'Feb') and
    (TFileInfoPane.Months[3] = 'Mar') and (TFileInfoPane.Months[4] = 'Apr') and (TFileInfoPane.Months[5] = 'May') and
    (TFileInfoPane.Months[6] = 'Jun'), 'months of the first half year are the texts of the C++');
  Check((TFileInfoPane.Months[7] = 'Jul') and (TFileInfoPane.Months[8] = 'Aug') and (TFileInfoPane.Months[9] = 'Sep') and
    (TFileInfoPane.Months[10] = 'Oct') and (TFileInfoPane.Months[11] = 'Nov') and (TFileInfoPane.Months[12] = 'Dec'),
    'months of the second half year are the texts of the C++');
  Check(TProgram.Application = nil, 'the first part has no application');
end;

{ A search record with the name Name, the attributes Attr, the size Size and the time DosValue. }
function MakeEntry(const Name: string; Attr: Byte; Size, DosValue: LongInt): TvFiles.TSearchRec;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Name := Name;
  Result.Attr := Attr;
  Result.Size := Size;
  Result.Time := DosValue;
end;

{ The time of DOS: the date in the high word and the time of the day in the low word. }
function DosTime(Year, Month, Day, Hour, Minute: Cardinal): LongInt;
var
  value: Cardinal;
begin
  value := ((Year - 1980) shl 25) or (Month shl 21) or (Day shl 16) or (Hour shl 11) or (Minute shl 5);
  Result := LongInt(value);
end;

function InfoEvent(Entry: PSearchRec): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evBroadcast;
  Result.Message.Command := cmFileFocused;
  Result.Message.InfoPtr := Entry;
end;

procedure TestInputLine;
var
  line: TFileInputLine;
  ev: TEvent;
begin
  line := TFileInputLine.Create(Rc(3, 3, 31, 4), 40);
  Check(RectIs(line.GetBounds, 3, 3, 31, 4), 'the input line has the bounds that were given');
  Check(line is TInputLine, 'a TFileInputLine is a TInputLine');
  Check(line.Data = '', 'the text of a new input line is empty');
  Check((line.EventMask and evBroadcast) <> 0, 'an input line of a file dialog takes broadcasts');
  TvObject.DestroyObject(line);
end;

procedure TestInputLineEvents;
var
  dlg: TProbeDialog;
  line, alone: TFileInputLine;
  ev: TEvent;
  fileEntry, dirEntry, longEntry: TvFiles.TSearchRec;
begin
  fileEntry := MakeEntry('one.txt', 0, 1, 0);
  dirEntry := MakeEntry('sub', FA_DIREC, 0, 0);
  longEntry := MakeEntry('abcdefghijkl', 0, 0, 0);
  dlg := MakeDialog('*.txt', fdNoLoadDir);
  line := dlg.FileName;
  line.State := line.State and not sfSelected;
  line.Data := 'typed';
  line.SelStart := 1;
  line.SelEnd := 3;
  line.CurPos := 3;

  ev := InfoEvent(@fileEntry);
  line.HandleEvent(ev);
  Check(line.Data = 'one.txt', 'the name of a focused file goes into a line that is not selected');
  Check((line.SelStart = 0) and (line.SelEnd = 0) and (line.CurPos = 0), 'the text is not selected and the cursor is at its start');
  Check(ev.What = evBroadcast, 'the broadcast of the focused file stays in the event');

  ev := InfoEvent(@dirEntry);
  line.HandleEvent(ev);
  Check(line.Data = 'sub/*.txt', 'a directory gets the separator and the wild card of the dialog');
  dlg.WildCard := '*.dat';
  ev := InfoEvent(@dirEntry);
  line.HandleEvent(ev);
  Check(line.Data = 'sub/*.dat', 'the wild card is the one that the dialog has now');

  line.Data := 'typed';
  line.State := line.State or sfSelected;
  ev := InfoEvent(@fileEntry);
  line.HandleEvent(ev);
  Check(line.Data = 'typed', 'a line that is selected keeps its text');

  line.State := line.State and not sfSelected;
  ev := BroadcastEvent(cmFileDoubleClicked);
  ev.Message.InfoPtr := @fileEntry;
  line.HandleEvent(ev);
  Check(line.Data = 'typed', 'another broadcast leaves the text');
  ev := CommandEvent(cmFileFocused);
  ev.Message.InfoPtr := @fileEntry;
  line.HandleEvent(ev);
  Check(line.Data = 'typed', 'a command of the same number leaves the text');

  DestroyDialog(dlg);

  alone := TFileInputLine.Create(Rc(3, 3, 31, 4), 8);
  ev := InfoEvent(@longEntry);
  alone.HandleEvent(ev);
  Check(alone.Data = 'abcdefg', 'the text is cut to the limit of the line');
  ev := InfoEvent(@dirEntry);
  alone.HandleEvent(ev);
  Check(alone.Data = 'sub/', 'a line with no dialog has no wild card');
  TvObject.DestroyObject(alone);
end;

procedure TestInfoPane;
var
  pane: TFileInfoPane;
  ev: TEvent;
  entry: TvFiles.TSearchRec;
  palette: TPalette;
begin
  pane := TFileInfoPane.Create(Rc(1, 16, 48, 18));
  Check(RectIs(pane.GetBounds, 1, 16, 48, 18), 'the info pane has the bounds that were given');
  Check((pane.EventMask and evBroadcast) <> 0, 'an info pane takes broadcasts');
  palette := pane.GetPalette;
  Check((palette <> nil) and (PalByte(palette, 0) = 1) and (PalByte(palette, 1) = 30),
    'the palette of the info pane has one entry, which is the entry 30 of its owner');
  Check(pane.GetPalette = palette, 'the palette of the info pane is one object');

  entry := MakeEntry('abc', 0, 12, DosTime(2001, 2, 3, 4, 5));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check((pane.FileBlock.Name = 'abc') and (pane.FileBlock.Size = 12) and (pane.FileBlock.Time = entry.Time) and
    (pane.FileBlock.Attr = 0), 'a focused file is copied into the info pane');
  Check(ev.What = evBroadcast, 'the broadcast of the focused file stays in the event');

  entry := MakeEntry('def', FA_DIREC, 0, 0);
  ev := BroadcastEvent(cmFileDoubleClicked);
  ev.Message.InfoPtr := @entry;
  pane.HandleEvent(ev);
  Check(pane.FileBlock.Name = 'abc', 'another broadcast leaves the entry');
  ev := CommandEvent(cmFileFocused);
  ev.Message.InfoPtr := @entry;
  pane.HandleEvent(ev);
  Check(pane.FileBlock.Name = 'abc', 'a command of the same number leaves the entry');
  TvObject.DestroyObject(pane);
end;

{ Gives dlg the buffer DialogCells and exposes it, so that its views write into the cells. }
procedure ExposeDialog(Dlg: TProbeDialog);
begin
  FillChar(DialogCells, SizeOf(DialogCells), 0);
  Dlg.Options := Dlg.Options and not ofBuffered;
  Dlg.Buffer := @DialogCells[0];
  Dlg.SetState(sfExposed, True);
end;

{ The character in the info pane at the column Col of its row Row; the pane is at 1, 16 in the dialog. }
function PaneChar(Row, Col: Integer): Char;
var
  cellText: string;
begin
  cellText := DialogCells[(16 + Row) * DlgW + 1 + Col].Character.GetText;
  if Length(cellText) > 0 then
    Result := cellText[1]
  else
    Result := #0;
end;

{ The text of Count characters in the info pane from the column Col of its row Row. }
function PaneText(Row, Col, Count: Integer): string;
var
  position: Integer;
begin
  Result := '';
  for position := 0 to Count - 1 do
    Result := Result + PaneChar(Row, Col + position);
end;

procedure TestInfoPaneDraw;
var
  dlg: TProbeDialog;
  pane: TFileInfoPane;
  ev: TEvent;
  entry: TvFiles.TSearchRec;
begin
  dlg := MakeDialog('*.txt', fdNoLoadDir);
  dlg.Directory := '/dir/';
  pane := TFileInfoPane(NthOfClass(dlg, TFileInfoPane, 1));
  ExposeDialog(dlg);

  pane.DrawView;
  Check(PaneText(0, 0, 12) = ' /dir/*.txt ', 'the first row shows the expanded directory and wild card');
  Check(PaneText(0, 12, 35) = StringOfChar(' ', 35), 'the rest of the first row is blank');
  Check(PaneText(1, 0, 47) = StringOfChar(' ', 47), 'an empty entry shows a blank second row');

  entry := MakeEntry('a.txt', 0, 12345, DosTime(2024, 3, 7, 14, 5));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check(PaneText(0, 0, 12) = ' /dir/*.txt ', 'the first row is the same after an entry is shown');
  Check(PaneText(1, 0, 7) = ' a.txt ', 'the second row shows the name');
  Check(PaneText(1, 9, 5) = '12345', 'the size is at the column of the width less 38');
  Check(PaneText(1, 25, 3) = 'Mar', 'the month is at the column of the width less 22');
  Check(PaneText(1, 29, 2) = '07', 'a day below ten has a zero before it');
  Check(PaneChar(1, 31) = ',', 'the comma is at the column of the width less 16');
  Check(PaneText(1, 32, 4) = '2024', 'the year is at the column of the width less 15');
  Check(PaneText(1, 38, 2) = '02', 'the hour of 14 is 2 on the clock of 12');
  Check(PaneChar(1, 40) = ':', 'the colon is at the column of the width less 7');
  Check(PaneText(1, 41, 2) = '05', 'a minute below ten has a zero before it');
  Check(PaneChar(1, 43) = 'p', 'the hour 14 is the text of the afternoon');
  Check(((Cardinal(pane.FileBlock.Time) shr 11) and $1F) = 2, 'the draw writes the hour that it shows into the entry');

  pane.DrawView;
  Check((PaneText(1, 38, 2) = '02') and (PaneChar(1, 43) = 'a'),
    'a second draw takes the hour that the first one wrote, which is before noon');

  entry := MakeEntry('b.dat', 0, 0, DosTime(1999, 12, 25, 0, 59));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check((PaneText(1, 25, 3) = 'Dec') and (PaneText(1, 29, 2) = '25') and (PaneText(1, 32, 4) = '1999'),
    'the month 12, the day 25 and the year 1999');
  Check((PaneText(1, 38, 2) = '12') and (PaneChar(1, 43) = 'a') and (PaneText(1, 41, 2) = '59'),
    'the hour 0 is 12 in the morning');
  Check(PaneText(1, 9, 5) = '0    ', 'the size 0 is one digit');

  entry := MakeEntry('c.dat', 0, 7, DosTime(1980, 1, 15, 12, 0));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check((PaneText(1, 25, 3) = 'Jan') and (PaneText(1, 29, 2) = '15') and (PaneText(1, 32, 4) = '1980'),
    'the month 1, the day 15 and the year 1980');
  Check((PaneText(1, 38, 2) = '12') and (PaneChar(1, 43) = 'p') and (PaneText(1, 41, 2) = '00'),
    'the hour 12 is 12 in the afternoon');

  entry := MakeEntry('d.dat', 0, 7, DosTime(2000, 5, 31, 9, 30));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check((PaneText(1, 38, 2) = '09') and (PaneChar(1, 43) = 'a') and (PaneText(1, 25, 3) = 'May'),
    'the hour 9 has a zero before it and is in the morning');

  entry := MakeEntry('e.dat', 0, 7, DosTime(2000, 13, 1, 23, 1));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check((PaneText(1, 25, 3) = '   ') and (PaneText(1, 38, 2) = '11') and (PaneChar(1, 43) = 'p'),
    'a month that has no name shows no name');

  entry := MakeEntry('', 0, 7, DosTime(2000, 5, 31, 9, 30));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check(PaneText(1, 0, 47) = StringOfChar(' ', 47), 'an entry with no name shows a blank second row');

  dlg.Directory := '';
  dlg.WildCard := 'x*';
  pane.DrawView;
  Check(PaneText(0, 1, 2) <> '  ', 'an empty directory still shows a path');

  TFileInfoPane.PmText := 'PM';
  TFileInfoPane.AmText := 'AM';
  entry := MakeEntry('f.dat', 0, 7, DosTime(2000, 5, 31, 15, 30));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check(PaneText(1, 43, 2) = 'PM', 'the text of the afternoon is the class variable PmText');
  entry := MakeEntry('g.dat', 0, 7, DosTime(2000, 5, 31, 5, 30));
  ev := InfoEvent(@entry);
  pane.HandleEvent(ev);
  Check(PaneText(1, 43, 2) = 'AM', 'the text of the morning is the class variable AmText');
  TFileInfoPane.PmText := 'p';
  TFileInfoPane.AmText := 'a';

  DestroyDialog(dlg);
end;

procedure TestConstructionWithoutLoad;
var
  dlg: TProbeDialog;
  lineLabel, filesLabel: TView;
  history: TView;
  bar: TView;
  pane: TView;
begin
  ResetCounters;
  dlg := MakeDialog(WildText, fdOKButton or fdHelpButton or fdNoLoadDir);
  Check(RectIs(dlg.GetBounds, 15, 1, 64, 20), 'a dialog without an application has the bounds of its constructor');
  Check((dlg.Options and ofCentered) = ofCentered, 'the dialog is centred');
  Check((dlg.Flags and wfGrow) <> 0, 'the dialog can grow');
  Check(string(dlg.Title) = 'Open file', 'the title of the dialog');
  Check((dlg.FileName <> nil) and (dlg.FileList <> nil), 'the dialog has an input line and a file list');
  Check(dlg.WildCard = WildText, 'the wild card is the text that was given');
  Check(dlg.FileName.Data = WildText, 'the input line starts with the wild card');
  Check(dlg.Directory = '', 'the directory is empty before a directory is read');
  Check(dlg.FileList.List = nil, 'fdNoLoadDir reads no directory');
  Check(ViewCount(dlg) = 11, 'the dialog has a frame and ten more views');
  Check(dlg.At(1) is TFileInfoPane, 'the info pane was inserted last');
  Check(dlg.At(11) is TFrame, 'the frame was inserted first');

  Check(RectIs(dlg.FileName.GetBounds, 3, 3, 31, 4), 'the bounds of the input line');
  Check(dlg.FileName.GrowMode = gfGrowHiX, 'the input line grows at its right side');

  lineLabel := NthOfClass(dlg, TLabel, 1);
  Check((lineLabel <> nil) and RectIs(lineLabel.GetBounds, 2, 2, 7, 3),
    'the label of the input line is as wide as its text without the tildes plus one');
  Check((LabelText(lineLabel) = '~N~ame') and (TLabelPeek(lineLabel).LinkOf = dlg.FileName), 'the label points to the input line');
  Check(lineLabel.GrowMode = 0, 'the label of the input line does not grow');

  history := NthOfClass(dlg, THistory, 1);
  Check((history <> nil) and RectIs(history.GetBounds, 31, 3, 34, 4), 'the bounds of the history');
  Check((THistoryPeek(history).LinkOf = dlg.FileName) and (THistoryPeek(history).IdOf = 7), 'the history has the line and the id');
  Check(history.GrowMode = (gfGrowLoX or gfGrowHiX), 'the history moves with the right side');

  bar := NthOfClass(dlg, TScrollBar, 1);
  Check((bar <> nil) and RectIs(bar.GetBounds, 3, 14, 34, 15), 'the bounds of the scroll bar');
  Check(RectIs(dlg.FileList.GetBounds, 3, 6, 34, 14), 'the bounds of the file list');
  Check((dlg.FileList.NumCols = 2) and (dlg.FileList.VScrollBar = bar), 'the file list has two columns and the scroll bar');
  Check(dlg.FileList.GrowMode = (gfGrowHiX or gfGrowHiY), 'the file list grows at its right and bottom sides');

  filesLabel := NthOfClass(dlg, TLabel, 2);
  Check((filesLabel <> nil) and RectIs(filesLabel.GetBounds, 2, 5, 8, 6), 'the bounds of the label of the list');
  Check((LabelText(filesLabel) = '~F~iles') and (TLabelPeek(filesLabel).LinkOf = dlg.FileList),
    'the label of the list has the text FilesText and points to the list');
  Check(filesLabel.GrowMode = 0, 'the label of the list does not grow');

  Check(NthOfClass(dlg, TButton, 4) = nil, 'two buttons and the cancel button make three');
  Check(ButtonIs(dlg, 1, cmFileOpen, bfDefault, 'O~K~', 35, 3, 46, 5), 'the OK button is the default button of the first row');
  Check(ButtonIs(dlg, 2, cmCancel, bfNormal, 'Cancel', 35, 6, 46, 8), 'the cancel button is the second');
  Check(ButtonIs(dlg, 3, cmHelp, bfNormal, '~H~elp', 35, 9, 46, 11), 'the help button is the third');
  Check(NthOfClass(dlg, TButton, 1).GrowMode = (gfGrowLoX or gfGrowHiX), 'a button moves with the right side');
  Check(NthOfClass(dlg, TButton, 3).GrowMode = (gfGrowLoX or gfGrowHiX), 'the help button moves with the right side');

  pane := NthOfClass(dlg, TFileInfoPane, 1);
  Check((pane <> nil) and RectIs(pane.GetBounds, 1, 16, 48, 18), 'the bounds of the info pane');
  Check(pane.GrowMode = (gfGrowLoY or gfGrowHiX or gfGrowHiY), 'the info pane grows in every direction but the left');
  DestroyDialog(dlg);
end;

procedure TestButtonRows;
var
  dlg: TProbeDialog;
begin
  dlg := MakeDialog('*', fdOpenButton or fdReplaceButton or fdClearButton or fdNoLoadDir);
  Check(ViewCount(dlg) = 12, 'a dialog with three buttons and cancel has twelve views');
  Check(ButtonIs(dlg, 1, cmFileOpen, bfDefault, '~O~pen', 35, 3, 46, 5), 'the open button is the default button');
  Check(ButtonIs(dlg, 2, cmFileReplace, bfNormal, '~R~eplace', 35, 6, 46, 8), 'the replace button is normal and follows');
  Check(ButtonIs(dlg, 3, cmFileClear, bfNormal, '~C~lear', 35, 9, 46, 11), 'the clear button is normal and follows');
  Check(ButtonIs(dlg, 4, cmCancel, bfNormal, 'Cancel', 35, 12, 46, 14), 'the cancel button is the last');
  Check(NthOfClass(dlg, TButton, 5) = nil, 'there is no help button when it is not asked for');
  Check(LabelText(NthOfClass(dlg, TLabel, 2)) = '~F~iles', 'the label of the list has the text FilesText');
  DestroyDialog(dlg);

  dlg := MakeDialog('*', fdOpenButton or fdOKButton or fdNoLoadDir);
  Check(ButtonIs(dlg, 1, cmFileOpen, bfDefault, '~O~pen', 35, 3, 46, 5), 'with both, the open button is first and the default');
  Check(ButtonIs(dlg, 2, cmFileOpen, bfNormal, 'O~K~', 35, 6, 46, 8), 'with both, the OK button is the second and normal');
  Check(ButtonIs(dlg, 3, cmCancel, bfNormal, 'Cancel', 35, 9, 46, 11), 'the cancel button follows them');
  DestroyDialog(dlg);

  dlg := MakeDialog('*', fdNoLoadDir);
  Check(ViewCount(dlg) = 9, 'a dialog with only cancel has nine views');
  Check(ButtonIs(dlg, 1, cmCancel, bfNormal, 'Cancel', 35, 3, 46, 5), 'the cancel button alone is at the top and is normal');
  DestroyDialog(dlg);

  dlg := MakeDialog('*', fdClearButton or fdHelpButton or fdNoLoadDir);
  Check(ButtonIs(dlg, 1, cmFileClear, bfDefault, '~C~lear', 35, 3, 46, 5), 'the clear button is the default when it is first');
  Check(ButtonIs(dlg, 2, cmCancel, bfNormal, 'Cancel', 35, 6, 46, 8), 'cancel follows the clear button');
  Check(ButtonIs(dlg, 3, cmHelp, bfNormal, '~H~elp', 35, 9, 46, 11), 'help follows cancel');
  DestroyDialog(dlg);
end;

procedure TestLoadingAtConstruction;
var
  dlg: TProbeDialog;
  savedDir: string;
begin
  ResetCounters;
  savedDir := GetCurrentDir;
  Check(SetCurrentDir(TempRoot + 'rd'), 'the directory rd of the tests exists');
  dlg := MakeDialog(WildText, fdOKButton);
  Check(dlg.Directory = IncludeTrailingPathDelimiter(GetCurrentDir),
    'the directory of the dialog is the current directory with a separator at its end');
  Check(dlg.Directory = GetCurDir, 'the directory of the dialog is the one that GetCurDir gives');
  Check((dlg.FileList.List <> nil) and (dlg.FileList.List.GetCount = 5),
    'the list has two files that match, two directories and the parent');
  Check((dlg.FileList.List.At(0)^.Name = 'a.txt') and (dlg.FileList.List.At(1)^.Name = 'b.txt') and
    (dlg.FileList.List.At(4)^.Name = '..'), 'the entries are the files, the directories and the parent');
  Check((LastWhat = evBroadcast) and (LastCommand = cmFileFocused) and (LastInfo = Pointer(dlg.FileList.List.At(0))),
    'the first entry is announced to the dialog');
  Check(LastReceiver = dlg, 'the announcement goes to the dialog, which owns the list');
  DestroyDialog(dlg);

  Check(SetCurrentDir(TempRoot), 'the directory of the tests exists');
  dlg := MakeDialog(WildText, fdOKButton);
  Check(dlg.Directory = IncludeTrailingPathDelimiter(GetCurrentDir), 'the directory follows the current directory');
  Check(dlg.FileList.Range = 5, 'the list is read from the wild card, which has the whole path');
  DestroyDialog(dlg);
  SetCurrentDir(savedDir);
end;

procedure TestGetFileName;
var
  dlg: TProbeDialog;
begin
  dlg := MakeDialog('*.txt', fdNoLoadDir);
  dlg.Directory := TempRoot;

  dlg.FileName.Data := 'b.txt';
  Check(dlg.GetFileName = TempRoot + 'b.txt', 'a relative name is made absolute from the directory');
  dlg.FileName.Data := TempRoot + 'rd/c.dat';
  Check(dlg.GetFileName = TempRoot + 'rd/c.dat', 'an absolute name stays');
  dlg.FileName.Data := '';
  Check(dlg.GetFileName = TempRoot + '*.txt', 'an empty name is the directory and the wild card');
  dlg.FileName.Data := TempRoot + 'rd/';
  Check(dlg.GetFileName = TempRoot + 'rd/*.txt', 'a directory with its separator gets the wild card');
  dlg.FileName.Data := 'sub/x';
  Check(dlg.GetFileName = TempRoot + 'sub/x', 'a name without an extension does not get the wild card');
  dlg.FileName.Data := ' b.txt';
  Check(dlg.GetFileName = TempRoot + ' b.txt', 'the spaces of a name are not trimmed');
  dlg.FileName.Data := 'ab' + #0 + 'cd';
  Check(dlg.GetFileName = TempRoot + 'ab', 'the name ends at a zero character');
  dlg.WildCard := '*';
  dlg.FileName.Data := '';
  Check(dlg.GetFileName = TempRoot + '*', 'the wild card that is the star gives the star');
  dlg.WildCard := '*.txt';
  dlg.Directory := '';
  dlg.FileName.Data := TempRoot + 'rd/a.txt';
  Check(dlg.GetFileName = TempRoot + 'rd/a.txt', 'an absolute name with no directory stays');

  dlg.Directory := TempRoot;
  dlg.FileName.Data := 'b.txt';
  FillChar(Buf, SizeOf(Buf), Ord('Z'));
  dlg.GetData(@Buf[0]);
  Check(BufferText = TempRoot + 'b.txt', 'GetData gives the name of GetFileName');
  Check(Buf[Length(TempRoot + 'b.txt') + 1] = 'Z', 'GetData writes the name and its zero and nothing more');
  DestroyDialog(dlg);
end;

procedure TestEvents;
var
  dlg: TProbeDialog;
  ev: TEvent;
begin
  dlg := MakeDialog('*', fdNoLoadDir);
  dlg.State := dlg.State or sfModal;

  dlg.EndState := 0;
  ev := CommandEvent(cmFileOpen);
  dlg.HandleEvent(ev);
  Check((ev.What = evNothing) and (dlg.EndState = cmFileOpen), 'cmFileOpen ends a modal dialog and is taken');
  dlg.EndState := 0;
  ev := CommandEvent(cmFileReplace);
  dlg.HandleEvent(ev);
  Check((ev.What = evNothing) and (dlg.EndState = cmFileReplace), 'cmFileReplace ends a modal dialog and is taken');
  dlg.EndState := 0;
  ev := CommandEvent(cmFileClear);
  dlg.HandleEvent(ev);
  Check((ev.What = evNothing) and (dlg.EndState = cmFileClear), 'cmFileClear ends a modal dialog and is taken');
  dlg.EndState := 0;
  ev := CommandEvent(cmNew);
  dlg.HandleEvent(ev);
  Check((ev.What = evCommand) and (dlg.EndState = 0), 'another command is left alone');

  dlg.PutCount := 0;
  ev := BroadcastEvent(cmFileDoubleClicked);
  dlg.HandleEvent(ev);
  Check(dlg.PutCount = 1, 'a double click in the list puts an event back');
  Check((dlg.LastPut.What = evCommand) and (dlg.LastPut.Message.Command = cmOK), 'the event that is put back is cmOK');
  Check(ev.What = evNothing, 'the broadcast of the double click is taken');

  dlg.PutCount := 0;
  ev := BroadcastEvent(5000);
  dlg.HandleEvent(ev);
  Check((dlg.PutCount = 0) and (ev.What = evBroadcast), 'another broadcast is left alone');
  FillChar(ev, SizeOf(ev), 0);
  dlg.HandleEvent(ev);
  Check((dlg.PutCount = 0) and (ev.What = evNothing), 'an empty event does nothing');
  DestroyDialog(dlg);
end;

procedure TestSizeLimitsAndShutDown;
var
  dlg: TProbeDialog;
  smallest, largest: TPoint;
begin
  dlg := MakeDialog('*', fdNoLoadDir);
  smallest.X := 0;
  smallest.Y := 0;
  largest.X := 0;
  largest.Y := 0;
  dlg.SizeLimits(smallest, largest);
  Check((smallest.X = 49) and (smallest.Y = 19), 'the smallest size of a file dialog is 49 by 19');
  Check((largest.X >= 49) and (largest.Y >= 19), 'the largest size is the one of the dialog');

  dlg.ShutDown;
  Check((dlg.FileName = nil) and (dlg.FileList = nil), 'ShutDown lets go of the input line and of the list');
  TvObject.DestroyObject(dlg);
end;

{ The tests of the second part: with an application }

procedure TestSetup;
begin
  Check(App <> nil, 'the application exists');
  Check(TProgram.Application = TProgram(App), 'the application is the one of TProgram');
  Check((App.Size.X = ScrW) and (App.Size.Y = ScrH), 'the application fills the screen');
end;

procedure CheckDialogBounds(ScreenColumns, ScreenRows, AX, AY, BX, BY: Integer; const Name: string);
var
  dlg: TProbeDialog;
begin
  App.Size.X := ScreenColumns;
  App.Size.Y := ScreenRows;
  dlg := MakeDialog('*', fdNoLoadDir);
  Check(RectIs(dlg.GetBounds, AX, AY, BX, BY), Name);
  DestroyDialog(dlg);
  App.Size.X := ScrW;
  App.Size.Y := ScrH;
end;

procedure TestFitToScreen;
var
  dlg: TProbeDialog;
  list, pane, okButton: TView;
begin
  CheckDialogBounds(60, 20, 15, 1, 64, 20, 'a small screen leaves the bounds of the constructor');
  CheckDialogBounds(63, 25, 15, 1, 64, 20, 'a screen of 63 by 25 is still small');
  CheckDialogBounds(64, 25, 7, 1, 57, 20, 'a screen of 64 columns takes seven columns off each side');
  CheckDialogBounds(64, 26, 7, 3, 57, 23, 'a screen of 26 rows takes three rows off the top and the bottom');
  CheckDialogBounds(90, 34, 7, 3, 83, 31, 'a screen of 90 by 34 is still of the middle size');
  CheckDialogBounds(91, 35, 0, -4, 79, 25, 'a screen of 91 by 35 grows the dialog by 15 and by 5');
  CheckDialogBounds(80, 20, 7, 1, 73, 20, 'a screen of 80 by 20 gives the dialog 66 columns');
  CheckDialogBounds(100, 40, 0, -4, 79, 25, 'a large screen gives the dialog 79 by 29');

  App.Size.X := 80;
  App.Size.Y := 20;
  dlg := MakeDialog('*', fdOKButton or fdNoLoadDir);
  Check((dlg.Size.X = 66) and (dlg.Size.Y = 19), 'the size of the dialog on a screen of 80 by 20');
  okButton := NthOfClass(dlg, TButton, 1);
  Check(RectIs(okButton.GetBounds, 52, 3, 63, 5), 'the OK button moves by the growth of the width');
  Check(RectIs(NthOfClass(dlg, TButton, 2).GetBounds, 52, 6, 63, 8), 'the cancel button moves as well');
  Check(RectIs(dlg.FileName.GetBounds, 3, 3, 48, 4), 'the input line grows with the width');
  Check(RectIs(NthOfClass(dlg, THistory, 1).GetBounds, 48, 3, 51, 4), 'the history moves with the width');
  Check(RectIs(dlg.FileList.GetBounds, 3, 6, 51, 14), 'the list grows with the width');
  pane := NthOfClass(dlg, TFileInfoPane, 1);
  Check(RectIs(pane.GetBounds, 1, 16, 65, 18), 'the info pane grows with the width');
  DestroyDialog(dlg);

  App.Size.X := 100;
  App.Size.Y := 40;
  dlg := MakeDialog('*', fdOKButton or fdNoLoadDir);
  Check((dlg.Size.X = 79) and (dlg.Size.Y = 29), 'the size of the dialog on a large screen');
  okButton := NthOfClass(dlg, TButton, 1);
  Check(RectIs(okButton.GetBounds, 65, 3, 76, 5), 'the OK button moves by 30 columns');
  list := dlg.FileList;
  Check(RectIs(list.GetBounds, 3, 6, 64, 24), 'the list grows by 30 columns and by 10 rows');
  pane := NthOfClass(dlg, TFileInfoPane, 1);
  Check(RectIs(pane.GetBounds, 1, 26, 78, 28), 'the info pane moves down by 10 rows and grows by 30 columns');
  DestroyDialog(dlg);

  App.Size.X := 70;
  App.Size.Y := 30;
  dlg := MakeDialog('*', fdOKButton or fdNoLoadDir);
  Check(RectIs(dlg.GetBounds, 7, 3, 63, 27), 'the bounds of the dialog on a screen of 70 by 30');
  Check(RectIs(NthOfClass(dlg, TButton, 1).GetBounds, 42, 3, 53, 5), 'the OK button moves by 7 columns');
  Check(RectIs(dlg.FileList.GetBounds, 3, 6, 41, 19), 'the list grows by 7 columns and 5 rows');
  Check(RectIs(NthOfClass(dlg, TFileInfoPane, 1).GetBounds, 1, 21, 55, 23), 'the info pane on a screen of 70 by 30');
  DestroyDialog(dlg);

  App.Size.X := ScrW;
  App.Size.Y := ScrH;
end;

procedure TestValidSimple;
var
  dlg: TProbeDialog;
  bad: TInvalidView;
begin
  dlg := MakeDialog(WildText, fdNoLoadDir);
  dlg.Directory := TempRoot;
  ResetCounters;

  Check(dlg.Valid(cmValid), 'the command 0 is always valid');
  Check(dlg.Valid(cmCancel), 'cmCancel is valid');
  Check(dlg.Valid(cmFileClear), 'cmFileClear is valid');
  Check((MessageCount = 0) and (dlg.FileList.List = nil), 'these commands read no directory');

  bad := TInvalidView.Create(Rc(1, 1, 4, 2));
  dlg.Insert(bad);
  Check(dlg.Valid(cmValid), 'the command 0 is valid even with a view that is not');
  Check(dlg.Valid(cmCancel), 'cmCancel is valid with a view that is not');
  Check(not dlg.Valid(cmFileClear), 'cmFileClear is not valid when a view of the dialog is not');
  Check(not dlg.Valid(cmOK), 'cmOK is not valid when a view of the dialog is not');
  Check((dlg.FileList.List = nil) and (dlg.Directory = TempRoot), 'a view that is not valid stops the check before the name');
  dlg.Remove(bad);
  bad.Free;
  DestroyDialog(dlg);
end;

procedure TestValidWildAndDirectory;
var
  dlg: TProbeDialog;
  directoryBefore: string;
begin
  dlg := MakeDialog(WildText, fdNoLoadDir);
  dlg.Directory := TempRoot;
  ResetCounters;

  dlg.FileName.Select;
  Check(dlg.Current = dlg.FileName, 'the input line is selected');
  dlg.FileName.Data := TempRoot + 'rd/*.dat';
  Check(dlg.FileList.List = nil, 'the list has no entries before the first directory is read');
  Check(not dlg.Valid(cmOK), 'a wild name is never accepted');
  Check(dlg.Directory = TempRoot + 'rd/', 'the directory of the wild name becomes the directory');
  Check(dlg.WildCard = '*.dat', 'the name and the extension become the wild card');
  Check(dlg.FileList.List <> nil, 'the new directory is read');
  Check((dlg.FileList.List.GetCount = 4) and (dlg.FileList.List.At(0)^.Name = 'c.dat'),
    'the list has the file c.dat, two directories and the parent');
  Check(dlg.Current = dlg.FileList, 'the file list is selected after the directory is read');

  dlg.FileName.Select;
  dlg.FileName.Data := TempRoot + 'rd/*.txt';
  Check(not dlg.Valid(cmFileInit), 'a wild name is not accepted at cmFileInit');
  Check((dlg.WildCard = '*.txt') and (dlg.FileList.List.GetCount = 5), 'the directory is read again with the new wild card');
  Check(dlg.Current = dlg.FileName, 'the list is not selected at cmFileInit');

  dlg.FileName.Data := TempRoot + 'rd/sub1';
  Check(not dlg.Valid(cmOK), 'a directory is never accepted');
  Check(dlg.Directory = TempRoot + 'rd/sub1/', 'the directory gets a separator at its end');
  Check(dlg.WildCard = '*.txt', 'the wild card stays when a directory is entered');
  Check((dlg.FileList.List.GetCount = 1) and (dlg.FileList.List.At(0)^.Name = '..'), 'the empty directory has only the parent');
  Check(dlg.Current = dlg.FileList, 'the file list is selected after a directory is entered');

  dlg.FileName.Select;
  dlg.FileName.Data := TempRoot + 'rd/sub2';
  Check(not dlg.Valid(cmFileInit), 'a directory is not accepted at cmFileInit');
  Check(dlg.Directory = TempRoot + 'rd/sub2/', 'the directory is entered at cmFileInit');
  Check(dlg.Current = dlg.FileName, 'the list is not selected at cmFileInit when a directory is entered');

  dlg.FileName.Data := TempRoot + 'rd/a.txt';
  directoryBefore := dlg.Directory;
  Check(dlg.Valid(cmOK), 'the name of a file in a directory that exists is valid');
  Check(dlg.Directory = directoryBefore, 'a valid name changes no directory');
  dlg.FileName.Data := TempRoot + 'rd/new file.txt';
  Check(dlg.Valid(cmOK), 'a new name in a directory that exists is valid');
  dlg.FileName.Data := 'relative.txt';
  dlg.Directory := TempRoot + 'rd/';
  Check(dlg.Valid(cmOK), 'a relative name is expanded from the directory and is valid');
  DestroyDialog(dlg);
end;

procedure TestValidErrors;
var
  dlg: TProbeDialog;
  directoryBefore, wildBefore: string;
begin
  dlg := MakeDialog(WildText, fdNoLoadDir);
  dlg.Directory := TempRoot;
  ResetCounters;

  dlg.FileName.Data := TempRoot + 'rd/bad|name.txt';
  ArmCommand(cmOK);
  Check(not dlg.Valid(cmOK), 'a name with a character that is not allowed is not valid');
  Check(Snap.Taken and (Snap.Title = 'Error'), 'a message box of the class error was shown');
  Check(Snap.MessageText = 'Invalid file name: ''' + TempRoot + 'rd/bad|name.txt' + '''',
    'the box tells the text and the name');

  dlg.FileName.Data := TempRoot + 'nodir/x.txt';
  ArmCommand(cmOK);
  Check(not dlg.Valid(cmOK), 'a name in a directory that does not exist is not valid');
  Check(Snap.Taken and (Snap.MessageText = 'Invalid file name: ''' + TempRoot + 'nodir/x.txt' + ''''),
    'the box tells the name in the missing directory');

  directoryBefore := dlg.Directory;
  wildBefore := dlg.WildCard;
  dlg.FileList.Select;
  Check(dlg.Current = dlg.FileList, 'the list is selected before the directory error');
  dlg.FileName.Data := TempRoot + 'nodir/*.txt';
  ArmCommand(cmOK);
  Check(not dlg.Valid(cmOK), 'a wild name in a directory that does not exist is not valid');
  Check(Snap.Taken and (Snap.Title = 'Error'), 'a message box of the class error was shown for the directory');
  Check(Snap.MessageText = 'Invalid drive or directory: ''' + TempRoot + 'nodir/' + '''',
    'the box tells the text and the directory');
  Check(dlg.Current = dlg.FileName, 'the input line is selected after the directory error');
  Check((dlg.Directory = directoryBefore) and (dlg.WildCard = wildBefore) and (dlg.FileList.List = nil),
    'the directory, the wild card and the list stay');
  DestroyDialog(dlg);
end;

procedure TestSetData;
var
  dlg: TProbeDialog;
begin
  dlg := MakeDialog(WildText, fdNoLoadDir);
  dlg.Directory := TempRoot;
  ResetCounters;

  FillBuffer('');
  dlg.FileList.Select;
  dlg.SetData(@Buf[0]);
  Check(dlg.FileName.Data = '', 'SetData gives the empty text to the input line');
  Check((dlg.FileList.List = nil) and (dlg.Current = dlg.FileList), 'an empty text reads no directory');

  FillBuffer('plain.txt');
  dlg.SetData(@Buf[0]);
  Check(dlg.FileName.Data = 'plain.txt', 'SetData gives the text to the input line');
  Check((dlg.FileList.List = nil) and (dlg.Current = dlg.FileList), 'a text that is not wild reads no directory');

  FillBuffer(TempRoot + 'rd/*.dat');
  dlg.SetData(@Buf[0]);
  Check(dlg.FileName.Data = 'c.dat',
    'the first file of the new directory is shown in the input line while the list is the selected view');
  Check((dlg.Directory = TempRoot + 'rd/') and (dlg.WildCard = '*.dat'), 'a wild text sets the directory and the wild card');
  Check((dlg.FileList.List <> nil) and (dlg.FileList.List.GetCount = 4), 'a wild text reads the directory');
  Check(dlg.Current = dlg.FileName, 'a wild text selects the input line');

  FillBuffer(TempRoot + 'rd/*.txt');
  dlg.SetData(@Buf[0]);
  Check(dlg.FileName.Data = TempRoot + 'rd/*.txt', 'the input line that is selected keeps the wild text');
  Check((dlg.WildCard = '*.txt') and (dlg.FileList.List.GetCount = 5), 'the second wild text reads its directory');
  DestroyDialog(dlg);
end;

procedure TestEnd;
begin
  Check(StrayReads = 0, 'no dialog asked for an event that the test did not arm');
end;

begin
  MakeTree;
  ResetCounters;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;

  TestConstants;
  TestInputLine;
  TestInputLineEvents;
  TestInfoPane;
  TestInfoPaneDraw;
  TestConstructionWithoutLoad;
  TestButtonRows;
  TestLoadingAtConstruction;
  TestGetFileName;
  TestEvents;
  TestSizeLimitsAndShutDown;

  Fake := TFakeScreen.Create;
  Fake.Cols := ScrW;
  Fake.Rows := ScrH;
  Fake.Mode := TDisplay.smCO80;
  SavedScreen := TDisplay.Backend;
  TDisplay.Backend := Fake;
  FakeEvents := TFakeEvents.Create;
  SavedEvents := TEventQueue.Backend;
  TEventQueue.Backend := FakeEvents;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;

  DrainPosted;
  App := TMsgApp.Create;

  TestSetup;
  TestFitToScreen;
  TestValidSimple;
  TestValidWildAndDirectory;
  TestValidErrors;
  TestSetData;
  TestEnd;

  TvObject.DestroyObject(App);
  TAppInit.Shutdown;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TEventQueue.Backend := SavedEvents;
  FakeEvents.Free;
  TDisplay.Backend := SavedScreen;
  Fake.Free;

  RemoveTree(TempRoot);
  Done;
end.
