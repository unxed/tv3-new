{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (the options cdNormal, cdNoLoadDir and cdHelpButton, the commands cmChangeDir
  and cmRevert, TChDirDialog), source/tvision/tchdrdlg.cpp, source/tvision/tdircoll.cpp (getCurDir),
  include/tvision/ttypes.h (EOS),
  source/tvision/tvtext1.cpp (the text of the drives), include/tvision/util.h, source/tvision/misc.cpp,
  source/tvision/tvtext2.cpp
  See COPYRIGHT.magiblot.

  Test program of the unit TvChDir.

  The display is a screen of 60 by 20 cells in memory and the application has only a desktop. The application counts
  the expired timers that it gets. A command that a list box sends to its owner reaches the dialog. The tests that
  read the current directory make a tree of directories of their own under the directory of temporary files, change
  to it and remove it at the end; the tests of the commands of the list load a path that does not exist, so that the
  lists of directories hold only the path to it. The texts of the dialog are checked as the unit sets them. The
  application puts the command cmOK from its Idle when a flag is set, which closes a message box, and takes a copy of
  the text and the title of the box that is on top when the loop first asks for an event. The posted event and the
  wake-up of the threads reach the loop of ExecView on the desktop. }
program t_chdir;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads, Classes, SysUtils, Strings,
  TvObjs, TvGeom, TvEvents, TvKeys, TvSys, TvTimer, TvColors, TvCell, TvDrawBuf, TvScreen,
  TvViews, TvWindow, TvDialog, TvInput, TvHist, TvList, TvFiles, TvMsgbox, TvApp, TvChDir;

{$I testlib.inc}

const
  { The screen of the fake display, in cells. }
  ScrH = 20;
  ScrW = 3 * ScrH;
  { A wait that lasts longer than this means a failure, which ends the program. }
  Guard = 4000;
  { A directory that does not exist, which the tests of the commands of the list load. }
  DeepDir = '/nosuchroot/alpha/beta/';

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

  { An application with a desktop that fills the screen. It puts cmOK when WakeFlag is set, or the command
    DeadlineCmd when the deadline has passed, and copies what the box on top shows when the loop first asks for an
    event after Capturing was set. }
  TTestApp = class(TApplication)
  public
    Deadline: Int64;
    DeadlineCmd: Word;
    Capturing: Boolean;
    CapturedText: string;
    CapturedTitle: string;
    constructor Create; reintroduce;
    procedure HandleEvent(var Event: TEvent); override;
    procedure Idle; override;
    procedure GetEvent(var Event: TEvent); override;
  private
    procedure CaptureBox;
  end;

  TButtonPeek = class(TButton)
  public
    function CommandOf: Word;
    function FlagsOf: Byte;
    function IsDefault: Boolean;
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

  { The dialog with its four views made readable. }
  TPeekDialog = class(TChDirDialog)
  public
    function InputOf: TInputLine;
    function ListOf: TDirListBox;
    function OkOf: TButton;
    function ChDirOf: TButton;
  end;

  TPoster = class(TThread)
  private
    FKind: Integer;
    FDelay: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AKind, ADelay: Integer);
  end;

var
  ScreenCells: array[0..ScrW * ScrH - 1] of TScreenCell;
  Fake: TFakeScreen;
  FakeEvents: TFakeEvents;
  SavedScreen: TScreenBackend;
  SavedEvents: TEventBackend;
  App: TTestApp;
  WakeFlag: LongInt;
  TimerMsgCount: Integer;
  { The directory of the tests, with a separator at its end. }
  TempRoot: string;

{ The fake devices and the hooks }

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

function MakeDesk(R: TRect): TDeskTop;
begin
  Result := TDeskTop.Create(R);
end;

function Now64: Int64;
begin
  Result := Int64(GetTickCount64);
end;

{ Small helpers }

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function CmdEv(Cmd: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evCommand;
  Result.Message.Command := Cmd;
end;

procedure DrainPosted;
var
  discarded: TEvent;
begin
  while TEventQueue.GetPostedEvent(discarded) do
    ;
end;

{ The view of Box that has exactly the given bounds, or nil. }
function FindByBounds(Box: TGroup; AX, AY, BX, BY: Integer): TView;
var
  position: Integer;
  member: TView;
  area: TRect;
  isThis: Boolean;
begin
  Result := nil;
  position := 1;
  member := Box.At(SmallInt(position));
  while member <> nil do
  begin
    area := member.GetBounds;
    isThis := (area.A.X = AX) and (area.A.Y = AY) and (area.B.X = BX) and (area.B.Y = BY);
    if isThis then
    begin
      Result := member;
      Exit;
    end;
    Inc(position);
    member := Box.At(SmallInt(position));
  end;
end;

function CountViews(Box: TGroup): Integer;
begin
  Result := 0;
  while Box.At(SmallInt(Result + 1)) <> nil do
    Inc(Result);
end;

function StaticTextOf(Item: TStaticText): string;
var
  buffer: array[0..255] of AnsiChar;
begin
  buffer[0] := #0;
  Item.GetText(@buffer[0]);
  Result := StrPas(@buffer[0]);
end;

function EntryDir(Box: TDirListBox; Index: Integer): string;
begin
  Result := Box.List.At(Index).Dir;
end;

{ The number of separators in Text. }
function CountSeps(const Text: string): Integer;
var
  position: Integer;
begin
  Result := 0;
  for position := 1 to Length(Text) do
    if Text[position] = '/' then
      Inc(Result);
end;

{ Path without its last name and the separator before it. }
function ParentOf(const Path: string): string;
var
  position: Integer;
begin
  position := Length(Path);
  while (position > 0) and (Path[position] <> '/') do
    Dec(position);
  Result := Copy(Path, 1, position - 1);
end;

procedure MakeTree;
begin
  TempRoot := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tvchdir_' + IntToStr(GetProcessID) + '/';
  RemoveDir(TempRoot + 'alpha/beta');
  RemoveDir(TempRoot + 'alpha');
  RemoveDir(TempRoot);
  ForceDirectories(TempRoot + 'alpha/beta');
end;

procedure RemoveTree;
begin
  RemoveDir(TempRoot + 'alpha/beta');
  RemoveDir(TempRoot + 'alpha');
  RemoveDir(TempRoot);
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

function TButtonPeek.IsDefault: Boolean;
begin
  Result := AmDefault;
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

function TPeekDialog.InputOf: TInputLine;
begin
  Result := DirInput;
end;

function TPeekDialog.ListOf: TDirListBox;
begin
  Result := DirList;
end;

function TPeekDialog.OkOf: TButton;
begin
  Result := OkButton;
end;

function TPeekDialog.ChDirOf: TButton;
begin
  Result := ChDirButton;
end;

constructor TTestApp.Create;
begin
  inherited Create(nil, nil, @MakeDesk);
  DeadlineCmd := cmCancel;
end;

procedure TTestApp.HandleEvent(var Event: TEvent);
begin
  if Event.What = evBroadcast then
    case Event.Message.Command of
      cmTimerExpired:
        TimerMsgCount := TimerMsgCount + 1;
    end;
  inherited HandleEvent(Event);
end;

procedure TTestApp.Idle;
var
  pushed: TEvent;
begin
  inherited Idle;
  if InterlockedExchange(WakeFlag, 0) <> 0 then
  begin
    pushed := CmdEv(cmOK);
    PutEvent(pushed);
  end
  else if (Deadline > 0) and (Now64 > Deadline) then
  begin
    pushed := CmdEv(DeadlineCmd);
    PutEvent(pushed);
  end;
end;

procedure TTestApp.CaptureBox;
var
  box: TGroup;
  position: Integer;
  member: TView;
begin
  CapturedText := '';
  CapturedTitle := '';
  if not (Current is TGroup) then
    Exit;
  box := TGroup(Current);
  if (box is TWindow) and (TWindow(box).Title <> nil) then
    CapturedTitle := StrPas(TWindow(box).Title);
  position := 1;
  member := box.At(SmallInt(position));
  while member <> nil do
  begin
    if (member is TStaticText) and not (member is TLabel) then
      CapturedText := StaticTextOf(TStaticText(member));
    Inc(position);
    member := box.At(SmallInt(position));
  end;
end;

procedure TTestApp.GetEvent(var Event: TEvent);
begin
  if Capturing then
  begin
    Capturing := False;
    CaptureBox;
  end;
  inherited GetEvent(Event);
end;

constructor TPoster.Create(AKind, ADelay: Integer);
begin
  FKind := AKind;
  FDelay := ADelay;
  inherited Create(False);
end;

procedure TPoster.Execute;
var
  posted: TEvent;
begin
  if FDelay > 0 then
    Sleep(FDelay);
  case FKind of
    0:
      begin
        posted := CmdEv(cmOK);
        TEventQueue.PostEvent(posted);
        TEventQueue.WakeUp;
      end;
    1:
      begin
        InterlockedExchange(WakeFlag, 1);
        TEventQueue.WakeUp;
      end;
  end;
end;

{ The tests }

procedure TestConstants;
begin
  Check(cdNormal = 0, 'cdNormal is 0');
  Check(cdNoLoadDir = 1, 'cdNoLoadDir is 1');
  Check(cdHelpButton = 2, 'cdHelpButton is 2');
  Check(cmChangeDir = 1005, 'cmChangeDir is 1005');
  Check(cmRevert = 1006, 'cmRevert is 1006');
  Check(MaxPathLength = 257, 'the size of a path buffer');
  Check(TChDirDialog.ChangeDirTitle = 'Change Directory', 'changeDirTitle is the text of the C++');
  Check(TChDirDialog.DirNameText = 'Directory ~n~ame', 'dirNameText is the text of the C++');
  Check(TChDirDialog.DirTreeText = 'Directory ~t~ree', 'dirTreeText is the text of the C++');
  Check(TChDirDialog.OkText = 'O~K~', 'okText is the text of the C++');
  Check(TChDirDialog.ChdirText = '~C~hdir', 'chdirText is the text of the C++');
  Check(TChDirDialog.RevertText = '~R~evert', 'revertText is the text of the C++');
  Check(TChDirDialog.HelpText = 'Help', 'helpText is the text of the C++');
  Check(TChDirDialog.DrivesText = 'Drives', 'drivesText is the text of the C++');
  Check(TChDirDialog.InvalidText = 'Invalid directory', 'invalidText is the text of the C++');
  Check(Assigned(ChDirButtonDefaultHook), 'the unit gives the hook of makeDefault to TvFiles');
  Check(TDirListBox.Drives = 'Drives', 'the text of the drives of the list box');
end;

procedure TestLayout;
var
  dlg: TPeekDialog;
  found: TView;
  title: string;
begin
  dlg := TPeekDialog.Create(cdNoLoadDir or cdHelpButton, 7);
  Check((dlg.Size.X = 48) and (dlg.Size.Y = 18), 'the dialog is 48 by 18');
  title := StrPas(dlg.Title);
  Check(title = 'Change Directory', 'the title of the dialog is the text ChangeDirTitle');
  Check((dlg.Options and ofCentered) = ofCentered, 'the dialog is centred');
  Check((dlg.Flags and wfGrow) <> 0, 'the dialog can grow');
  Check((dlg.Flags and wfMove) <> 0, 'the dialog keeps the flag of a dialog that it can move');
  Check(CountViews(dlg) = 11, 'the frame and ten views with the help button');
  Check(dlg.Current <> nil, 'a view has the focus');

  found := FindByBounds(dlg, 3, 3, 42, 4);
  Check((found is TInputLine) and (found = TView(dlg.InputOf)), 'the input line is at 3,3,42,4');
  Check(dlg.InputOf.MaxLen = 255, 'the input line has room for a path less the terminating zero');
  Check(dlg.InputOf.GrowMode = gfGrowHiX, 'the input line grows at the high x');
  Check(dlg.InputOf.Data = '', 'the input line starts empty');

  found := FindByBounds(dlg, 2, 2, 17, 3);
  Check((found is TLabel) and (TLabelPeek(found).LinkOf = TView(dlg.InputOf)) and
    (StaticTextOf(TStaticText(found)) = 'Directory ~n~ame'), 'the first label names the input line');

  found := FindByBounds(dlg, 42, 3, 45, 4);
  Check((found is THistory) and (THistoryPeek(found).LinkOf = dlg.InputOf) and (THistoryPeek(found).IdOf = 7),
    'the history of the input line has the given identifier');
  Check(found.GrowMode = (gfGrowLoX or gfGrowHiX), 'the history grows at both x sides');

  found := FindByBounds(dlg, 32, 6, 33, 16);
  Check(found is TScrollBar, 'the scroll bar is at 32,6,33,16');

  found := FindByBounds(dlg, 3, 6, 32, 16);
  Check((found is TDirListBox) and (found = TView(dlg.ListOf)), 'the list of directories is at 3,6,32,16');
  Check(dlg.ListOf.GrowMode = (gfGrowHiX or gfGrowHiY), 'the list grows at the high sides');
  Check(dlg.ListOf.List = nil, 'cdNoLoadDir leaves the list unloaded');

  found := FindByBounds(dlg, 2, 5, 17, 6);
  Check((found is TLabel) and (TLabelPeek(found).LinkOf = TView(dlg.ListOf)) and
    (StaticTextOf(TStaticText(found)) = 'Directory ~t~ree'), 'the second label names the list');

  found := FindByBounds(dlg, 35, 6, 45, 8);
  Check((found is TButton) and (found = TView(dlg.OkOf)) and (StrPas(TButton(found).Title) = 'O~K~'),
    'the button of OK is at 35,6,45,8');
  Check((TButtonPeek(found).CommandOf = cmOK) and (TButtonPeek(found).FlagsOf = bfDefault) and
    TButtonPeek(found).IsDefault, 'the button of OK is the default button of the command cmOK');
  Check(found.GrowMode = (gfGrowLoX or gfGrowHiX), 'the button of OK grows at both x sides');

  found := FindByBounds(dlg, 35, 9, 45, 11);
  Check((found is TButton) and (found = TView(dlg.ChDirOf)) and (StrPas(TButton(found).Title) = '~C~hdir'),
    'the button of the change is at 35,9,45,11');
  Check((TButtonPeek(found).CommandOf = cmChangeDir) and (TButtonPeek(found).FlagsOf = bfNormal) and
    not TButtonPeek(found).IsDefault, 'the button of the change is a normal button of the command cmChangeDir');
  Check(found.GrowMode = (gfGrowLoX or gfGrowHiX), 'the button of the change grows at both x sides');

  found := FindByBounds(dlg, 35, 12, 45, 14);
  Check((found is TButton) and (StrPas(TButton(found).Title) = '~R~evert') and
    (TButtonPeek(found).CommandOf = cmRevert) and (TButtonPeek(found).FlagsOf = bfNormal),
    'the button of the revert is at 35,12,45,14');
  Check(found.GrowMode = (gfGrowLoX or gfGrowHiX), 'the button of the revert grows at both x sides');

  found := FindByBounds(dlg, 35, 15, 45, 17);
  Check((found is TButton) and (StrPas(TButton(found).Title) = 'Help') and (TButtonPeek(found).CommandOf = cmHelp) and
    (TButtonPeek(found).FlagsOf = bfNormal), 'the help button is at 35,15,45,17');
  Check(found.GrowMode = (gfGrowLoX or gfGrowHiX), 'the help button grows at both x sides');
  TvObject.DestroyObject(dlg);

  dlg := TPeekDialog.Create(cdNoLoadDir, 7);
  Check(CountViews(dlg) = 10, 'without the help button the frame and nine views');
  Check(FindByBounds(dlg, 35, 15, 45, 17) = nil, 'there is no help button without the option');
  TvObject.DestroyObject(dlg);
end;

procedure TestSizeAndData;
var
  dlg: TPeekDialog;
  smallest, largest: TPoint;
  record1: array[0..15] of Byte;
  position: Integer;
  unchanged: Boolean;
begin
  dlg := TPeekDialog.Create(cdNoLoadDir, 1);
  smallest.X := 0;
  smallest.Y := 0;
  largest.X := 0;
  largest.Y := 0;
  dlg.SizeLimits(smallest, largest);
  Check((smallest.X = 48) and (smallest.Y = 18), 'the smallest size of the dialog is 48 by 18');
  Check((largest.X > 0) and (largest.Y > 0), 'the largest size comes from the base class');

  Check(dlg.DataSize = 0, 'the dialog has no data');
  dlg.InputOf.Data := 'kept';
  FillChar(record1, SizeOf(record1), $5A);
  dlg.GetData(@record1[0]);
  unchanged := True;
  for position := 0 to High(record1) do
    if record1[position] <> $5A then
      unchanged := False;
  Check(unchanged, 'GetData writes nothing');
  dlg.SetData(@record1[0]);
  Check(dlg.InputOf.Data = 'kept', 'SetData changes nothing');
  TvObject.DestroyObject(dlg);
end;

procedure TestSetUp;
var
  dlg: TPeekDialog;
  savedDir, here: string;
  seps: Integer;
begin
  savedDir := GetCurrentDir;
  Check(SetCurrentDir(TempRoot + 'alpha/beta'), 'the directory alpha/beta of the tests exists');
  here := GetCurrentDir;
  seps := CountSeps(here + '/');
  dlg := TPeekDialog.Create(cdNormal, 1);
  Check(dlg.InputOf.Data = here, 'the line shows the current directory without its separator');
  Check(dlg.ListOf.List <> nil, 'the list is loaded');
  Check(dlg.ListOf.List.GetCount = seps, 'the list has the root and the directories of the path, and no subdirectory');
  Check((EntryDir(dlg.ListOf, 0) = '/') and (EntryDir(dlg.ListOf, seps - 1) = here) and
    (EntryDir(dlg.ListOf, seps - 2) = ParentOf(here)),
    'the entries of the list are the paths up to the current directory');
  Check(dlg.ListOf.Focused = seps - 1, 'the last directory of the path is focused');
  TvObject.DestroyObject(dlg);

  Check(SetCurrentDir('/'), 'the root exists');
  dlg := TPeekDialog.Create(cdNormal, 1);
  Check(dlg.InputOf.Data = '/', 'the root keeps its separator');
  Check((dlg.ListOf.List <> nil) and (EntryDir(dlg.ListOf, 0) = '/'), 'the first entry of the list is the root');
  TvObject.DestroyObject(dlg);
  SetCurrentDir(savedDir);
end;

procedure TestRevert;
var
  dlg: TPeekDialog;
  ev: TEvent;
  savedDir, here: string;
  seps: Integer;
begin
  savedDir := GetCurrentDir;
  Check(SetCurrentDir(TempRoot + 'alpha'), 'the directory alpha of the tests exists');
  here := GetCurrentDir;
  seps := CountSeps(here + '/');
  dlg := TPeekDialog.Create(cdNoLoadDir, 1);
  dlg.InputOf.Data := 'typed text';
  ev := CmdEv(cmRevert);
  dlg.HandleEvent(ev);
  Check(dlg.InputOf.Data = here, 'the revert puts the current directory into the line');
  Check(ev.What = evNothing, 'the revert clears the event');
  Check(dlg.ListOf.List.GetCount = seps + 1, 'the revert loads the list: the path and the subdirectory beta');
  Check(dlg.Current = TView(dlg.ListOf), 'the revert selects the list');
  Check(dlg.ListOf.Focused = seps - 1, 'the revert focuses the last directory of the path');
  Check(EntryDir(dlg.ListOf, seps) = here + '/beta', 'the subdirectory of the current directory is the last entry');

  dlg.InputOf.Data := 'typed text';
  ev := CmdEv(5000);
  dlg.HandleEvent(ev);
  Check((ev.What = evCommand) and (dlg.InputOf.Data = 'typed text'), 'another command is left alone');

  ev := CmdEv(cmRevert);
  ev.What := evBroadcast;
  dlg.HandleEvent(ev);
  Check((ev.What = evBroadcast) and (dlg.InputOf.Data = 'typed text'), 'a broadcast of the same number is left alone');
  TvObject.DestroyObject(dlg);
  SetCurrentDir(savedDir);
end;

procedure TestChangeDir;
var
  dlg: TPeekDialog;
  ev: TEvent;
  dirs: TDirCollection;
begin
  dlg := TPeekDialog.Create(cdNoLoadDir, 1);
  dlg.ListOf.NewDirectory(DeepDir);

  dlg.ListOf.FocusItem(2);
  ev := CmdEv(cmChangeDir);
  dlg.HandleEvent(ev);
  Check(dlg.InputOf.Data = '/nosuchroot/alpha', 'a change of directory puts the focused path into the line');
  Check(ev.What = evNothing, 'the change clears the event');
  Check(dlg.ListOf.List.GetCount = 3, 'the list shows the path to the focused directory');
  Check(dlg.ListOf.Focused = 2, 'the last directory is focused after the change');
  Check(dlg.Current = TView(dlg.ListOf), 'the change selects the list');

  dlg.ListOf.FocusItem(1);
  ev := CmdEv(cmChangeDir);
  dlg.HandleEvent(ev);
  Check(dlg.InputOf.Data = '/nosuchroot', 'a path at the first level');
  Check(dlg.ListOf.List.GetCount = 2, 'the list holds the root and one directory');

  dlg.ListOf.FocusItem(0);
  dlg.ListOf.SelectItem(0);
  Check(dlg.InputOf.Data = '/', 'a choice in the list reaches the dialog and the root has its one character');

  dlg.ListOf.NewDirectory(DeepDir);
  dlg.ListOf.FocusItem(2);
  dlg.ListOf.SelectItem(2);
  Check(dlg.InputOf.Data = '/nosuchroot/alpha', 'SelectItem of the list changes the directory');

  dirs := TDirCollection.Create(2, 2);
  dirs.Insert(TDirEntry.Create('shown', 'Drives'));
  dlg.ListOf.NewList(dirs);
  dlg.ListOf.FocusItem(0);
  ev := CmdEv(cmChangeDir);
  dlg.HandleEvent(ev);
  Check(dlg.InputOf.Data = 'Drives', 'the entry of the drives is taken as it is');
  Check(ev.What = evNothing, 'the entry of the drives clears the event');
  Check(dlg.ListOf.List.GetCount = 3, 'the list of the drives has the disks A, B and C');

  dirs := TDirCollection.Create(2, 2);
  dirs.Insert(TDirEntry.Create('shown', 'relative'));
  dlg.ListOf.NewList(dirs);
  dlg.ListOf.FocusItem(0);
  dlg.InputOf.Data := 'before';
  ev := CmdEv(cmChangeDir);
  dlg.HandleEvent(ev);
  Check((ev.What = evCommand) and (dlg.InputOf.Data = 'before') and (dlg.ListOf.List.GetCount = 1),
    'a path with no separator and no disk is not taken');

  dirs := TDirCollection.Create(2, 2);
  dirs.Insert(TDirEntry.Create('shown', 'C:'));
  dlg.ListOf.NewList(dirs);
  dlg.ListOf.FocusItem(0);
  ev := CmdEv(cmChangeDir);
  dlg.HandleEvent(ev);
  Check((ev.What = evNothing) and (dlg.InputOf.Data = 'C:/'), 'a disk gets a separator after it');

  dirs := TDirCollection.Create(2, 2);
  dirs.Insert(TDirEntry.Create('shown', '/a'));
  dlg.ListOf.NewList(dirs);
  dlg.ListOf.FocusItem(0);
  ev := CmdEv(cmChangeDir);
  dlg.HandleEvent(ev);
  Check(dlg.InputOf.Data = '/a/', 'a path of three characters keeps its separator');

  dirs := TDirCollection.Create(2, 2);
  dirs.Insert(TDirEntry.Create('shown', '/ab'));
  dlg.ListOf.NewList(dirs);
  dlg.ListOf.FocusItem(0);
  ev := CmdEv(cmChangeDir);
  dlg.HandleEvent(ev);
  Check(dlg.InputOf.Data = '/ab', 'a path of four characters loses its separator');
  TvObject.DestroyObject(dlg);

  dlg := TPeekDialog.Create(cdNoLoadDir, 1);
  dlg.InputOf.Data := 'before';
  ev := CmdEv(cmChangeDir);
  dlg.HandleEvent(ev);
  Check((ev.What = evCommand) and (dlg.InputOf.Data = 'before'), 'a change with no list loaded is not handled');
  TvObject.DestroyObject(dlg);
end;

procedure TestDefaultButton;
var
  dlg: TPeekDialog;
  loneList: TDirListBox;
begin
  dlg := TPeekDialog.Create(cdNoLoadDir, 1);
  Check(TButtonPeek(dlg.OkOf).IsDefault, 'the button of OK starts as the default button');
  dlg.ListOf.SetState(sfFocused, True);
  Check(TButtonPeek(dlg.ChDirOf).IsDefault, 'the focus of the list makes the button of the change the default');
  Check(not TButtonPeek(dlg.OkOf).IsDefault, 'the button of OK gives up the default');
  dlg.ListOf.SetState(sfFocused, False);
  Check(not TButtonPeek(dlg.ChDirOf).IsDefault, 'the loss of the focus ends the default of the button of the change');
  Check(TButtonPeek(dlg.OkOf).IsDefault, 'the button of OK is the default again');
  TvObject.DestroyObject(dlg);

  dlg := TPeekDialog.Create(cdNoLoadDir, 1);
  loneList := TDirListBox.Create(Rc(0, 0, 10, 5), nil);
  MakeChDirButtonDefault(loneList, True);
  Check(not TButtonPeek(dlg.ChDirOf).IsDefault, 'a list that has no dialog leaves the buttons of a dialog alone');
  TvObject.DestroyObject(loneList);
  TvObject.DestroyObject(dlg);
end;

procedure TestShutDown;
var
  dlg: TPeekDialog;
begin
  dlg := TPeekDialog.Create(cdNoLoadDir, 1);
  dlg.ShutDown;
  Check((dlg.InputOf = nil) and (dlg.ListOf = nil) and (dlg.OkOf = nil) and (dlg.ChDirOf = nil),
    'ShutDown forgets the four views');
  dlg.Free;
end;

procedure TestValid;
var
  dlg: TPeekDialog;
  tempDir, savedDir, expectedDir: string;
  answer: Boolean;
begin
  savedDir := GetCurrentDir;
  tempDir := GetTempDir;
  Check(SetCurrentDir(tempDir), 'the directory of temporary files exists');
  expectedDir := GetCurrentDir;
  SetCurrentDir(savedDir);

  dlg := TPeekDialog.Create(cdNoLoadDir, 1);
  dlg.InputOf.Data := '/nosuchroot_chdir_test/sub/';
  Check(dlg.Valid(cmCancel), 'a command other than cmOK is valid');
  Check(GetCurrentDir = savedDir, 'a command other than cmOK does not change the directory');

  dlg.InputOf.Data := tempDir;
  answer := dlg.Valid(cmOK);
  Check(answer, 'an existing directory is valid');
  Check(GetCurrentDir = expectedDir, 'the dialog changed the current directory');
  SetCurrentDir(savedDir);

  dlg.InputOf.Data := tempDir + '/./';
  answer := dlg.Valid(cmOK);
  Check(answer and (GetCurrentDir = expectedDir), 'the path is made full before the change');
  SetCurrentDir(savedDir);

  dlg.InputOf.Data := '/nosuchroot_chdir_test/sub/';
  DrainPosted;
  App.Capturing := True;
  App.Deadline := Now64 + Guard - 300;
  App.DeadlineCmd := cmCancel;
  InterlockedExchange(WakeFlag, 1);
  answer := dlg.Valid(cmOK);
  App.Deadline := 0;
  InterlockedExchange(WakeFlag, 0);
  Check(not answer, 'a directory that does not exist is not valid');
  Check(App.CapturedText = 'Invalid directory: ''/nosuchroot_chdir_test/sub''.', 'the box names the path without its separator');
  Check(App.CapturedTitle = 'Error', 'the box is an error box');
  Check(GetCurrentDir = savedDir, 'a failed change leaves the directory');
  TvObject.DestroyObject(dlg);
end;

{ The tests of the threads: an event that another thread posts, or a wake-up, reaches the loop of a modal dialog. }

procedure PrepareWait(TimeoutMs: Integer; out GuardId: TTimerId);
begin
  EventTimeoutMs := TimeoutMs;
  App.Deadline := Now64 + Guard - 300;
  App.DeadlineCmd := cmCancel;
  TimerMsgCount := 0;
  GuardId := App.SetTimer(Guard, -1);
end;

procedure EndWait(GuardId: TTimerId);
begin
  App.Deadline := 0;
  if TimerMsgCount = 0 then
    App.KillTimer(GuardId);
  EventTimeoutMs := 20;
end;

procedure TestThreads;
var
  dlg: TChDirDialog;
  poster: TPoster;
  guardId: TTimerId;
  start, elapsed: Int64;
  answer: Word;
begin
  DrainPosted;
  dlg := TChDirDialog.Create(cdNoLoadDir, 1);
  PrepareWait(-1, guardId);
  poster := TPoster.Create(0, 250);
  start := Now64;
  answer := App.DeskTop.ExecView(dlg);
  elapsed := Now64 - start;
  poster.WaitFor;
  poster.Free;
  EndWait(guardId);
  Check(answer = cmOK, 'an event that is posted from a second thread during ExecView of the dialog is delivered');
  Check(elapsed < Guard - 500, 'the posted event ended the wait before the time-out');
  Check(elapsed >= 150, 'the loop of the dialog waited for the posted event');
  TvObject.DestroyObject(dlg);

  dlg := TChDirDialog.Create(cdNoLoadDir, 1);
  InterlockedExchange(WakeFlag, 0);
  PrepareWait(-1, guardId);
  poster := TPoster.Create(1, 250);
  start := Now64;
  answer := App.DeskTop.ExecView(dlg);
  elapsed := Now64 - start;
  poster.WaitFor;
  poster.Free;
  EndWait(guardId);
  Check(answer = cmOK, 'a wake-up from a second thread during ExecView of the dialog ends the wait');
  Check((elapsed < Guard - 500) and (elapsed >= 150), 'the wake-up ended the unlimited wait');
  TvObject.DestroyObject(dlg);

  dlg := TChDirDialog.Create(cdNoLoadDir, 1);
  PrepareWait(20, guardId);
  poster := TPoster.Create(0, 250);
  start := Now64;
  answer := App.DeskTop.ExecView(dlg);
  elapsed := Now64 - start;
  poster.WaitFor;
  poster.Free;
  EndWait(guardId);
  Check((answer = cmOK) and (elapsed < Guard - 500) and (elapsed >= 150),
    'a posted event is delivered when the wait has a time-out of 20 ms');
  TvObject.DestroyObject(dlg);

  dlg := TChDirDialog.Create(cdNoLoadDir, 1);
  PrepareWait(-1, guardId);
  poster := TPoster.Create(0, 0);
  poster.WaitFor;
  poster.Free;
  start := Now64;
  answer := App.DeskTop.ExecView(dlg);
  elapsed := Now64 - start;
  EndWait(guardId);
  Check((answer = cmOK) and (elapsed < 1000), 'an event that was posted before ExecView is delivered at once');
  TvObject.DestroyObject(dlg);
end;

begin
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

  TestConstants;
  MakeTree;

  DrainPosted;
  EventTimeoutMs := 20;
  App := TTestApp.Create;

  TestLayout;
  TestSizeAndData;
  TestSetUp;
  TestRevert;
  TestChangeDir;
  TestDefaultButton;
  TestShutDown;
  TestValid;
  TestThreads;

  TvObject.DestroyObject(App);
  TAppInit.Shutdown;
  RemoveTree;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TEventQueue.Backend := SavedEvents;
  FakeEvents.Free;
  TDisplay.Backend := SavedScreen;
  Fake.Free;
  Done;
end.
