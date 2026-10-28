{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (the options cdNormal, cdNoLoadDir and cdHelpButton, the commands cmChangeDir
  and cmRevert, TChDirDialog), source/tvision/tchdrdlg.cpp, source/tvision/tdircoll.cpp (the call of getCurDir),
  include/tvision/ttypes.h (EOS),
  source/tvision/tvtext1.cpp (the text of the drives), include/tvision/util.h, source/tvision/misc.cpp (strnzcpy),
  source/tvision/tvtext2.cpp
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the class, and the constructor with StreamableInit, belong to a later
  unit.

  Parts of the C++ that have no unit yet:
    - getCurDir, which getCurrentDir of tchdrdlg.cpp calls, is GetCurDir of TvFiles. It gives the directory without
      the characters of a drive, so the removal of the drive letter that getCurrentDir makes for a Unix target has
      nothing to remove, and CurrentDirText is the call of GetCurDir.
    - The functions of the compatibility headers (fexpand, chdir) are made with TvPath and SysUtils, as TvFiles makes
      them. setdisk is left out, because the target has no drives: the path that changeDir of tchdrdlg.cpp gets
      never has a drive letter before a colon that selects a disk.

  strnzcpy, which puts a path into the line, is Strnzcpy of TvUtil.

  The texts of the dialog (changeDirTitle, dirNameText, dirTreeText, okText, chdirText, revertText, helpText,
  drivesText and invalidText) are the class variables ChangeDirTitle, DirNameText, DirTreeText, OkText, ChdirText,
  RevertText, HelpText, DrivesText and InvalidText of TChDirDialog, which hold the texts of the C++ when the unit
  starts. DrivesText holds the same text as Drives of TDirListBox, for the entry of the drives to be recognised.

  MAXPATH is defined by a header that is not among the sources; MaxPathLength is the value 257, so that the line
  of the dialog holds at most 255 characters, which is the longest text that a string of this library holds.

  The separator that a path of the list of directories gets is PathSep of TvPath, as TDirListBox of TvFiles reads its
  paths with it; the C++ appends a backslash.

  The four views that the C++ keeps in private members are protected members, DirInput, DirList, OkButton and
  ChDirButton, so that a test can read them. When the unit starts it gives MakeChDirButtonDefault to
  ChDirButtonDefaultHook of TvFiles, which stands for chDirButton->makeDefault of TDirListBox::setState. }
unit TvChDir;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvViews, TvWindow, TvDialog, TvInput, TvFiles;

const
  { The options of the constructor. }
  cdNormal = Word($0000);
  cdNoLoadDir = Word($0001);
  cdHelpButton = Word($0002);

  { The size of the buffers of a path in the C++. }
  MaxPathLength = 257;

type
  { A dialog that shows the tree of directories and changes the current directory. }
  TChDirDialog = class(TDialog)
  private
    procedure SetUpDialog;
    procedure ShowPathInInput(const Path: string);
  protected
    DirInput: TInputLine;
    DirList: TDirListBox;
    OkButton: TButton;
    ChDirButton: TButton;
  public
    class var ChangeDirTitle: string;
    class var DirNameText: string;
    class var DirTreeText: string;
    class var OkText: string;
    class var ChdirText: string;
    class var RevertText: string;
    class var HelpText: string;
    class var DrivesText: string;
    class var InvalidText: string;
    constructor Create(DialogOptions, HistoryId: Word); reintroduce;
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SetData(Rec: Pointer); override;
    function Valid(Command: Word): Boolean; override;
    procedure ShutDown; override;
    procedure SizeLimits(var Smallest, Largest: TPoint); override;
  end;

{ Makes the button of the dialog that owns Box the default button, or stops it from being so. This is what
  ChDirButtonDefaultHook of TvFiles is given when the unit starts. }
procedure MakeChDirButtonDefault(Box: TDirListBox; Enable: Boolean);

implementation

uses
  SysUtils, TvHist, TvMsgbox, TvPath, TvUtil;

const
  { The shortest path whose last separator is cut off. }
  ShortestTrimmedPath = 4;

{ Tells whether C is a backslash or a slash. }
function IsSeparatorChar(C: Char): Boolean;
begin
  Result := (C = '\') or (C = '/');
end;

{ Cuts off the separator at the end of Path when the path is longer than three characters. }
function WithoutEndSeparator(const Path: string): string;
var
  pathLength: Integer;
  longEnough, endsWithSeparator: Boolean;
begin
  Result := Path;
  pathLength := Length(Path);
  longEnough := pathLength >= ShortestTrimmedPath;
  if not longEnough then
    Exit;
  endsWithSeparator := IsSeparatorChar(Path[pathLength]);
  if endsWithSeparator then
    SetLength(Result, pathLength - 1);
end;

{ The current directory, which has no characters of a drive. }
function CurrentDirText: string;
begin
  Result := GetCurDir;
end;

{ Makes Path the current directory and tells whether it worked. }
function ChangeDirectory(const Path: string): Boolean;
begin
  Result := SetCurrentDir(Path);
end;

procedure MakeChDirButtonDefault(Box: TDirListBox; Enable: Boolean);
var
  dialog: TChDirDialog;
begin
  if not (Box.Owner is TChDirDialog) then
    Exit;
  dialog := TChDirDialog(Box.Owner);
  if dialog.ChDirButton = nil then
    Exit;
  dialog.ChDirButton.MakeDefault(Enable);
end;

{ TChDirDialog }

constructor TChDirDialog.Create(DialogOptions, HistoryId: Word);
var
  scrollBar: TScrollBar;
  history: THistory;
  revertButton, helpButton: TButton;
  wantsHelp, loadsDirectory: Boolean;
begin
  inherited Create(TRect.Create(16, 2, 64, 20), ChangeDirTitle);
  Options := Options or ofCentered;
  Flags := Flags or Byte(wfGrow);

  DirInput := TInputLine.Create(TRect.Create(3, 3, 42, 4), MaxPathLength - 1);
  DirInput.GrowMode := gfGrowHiX;
  Insert(DirInput);
  Insert(TLabel.Create(TRect.Create(2, 2, 17, 3), DirNameText, DirInput));
  history := THistory.Create(TRect.Create(42, 3, 45, 4), DirInput, HistoryId);
  history.GrowMode := gfGrowLoX or gfGrowHiX;
  Insert(history);

  scrollBar := TScrollBar.Create(TRect.Create(32, 6, 33, 16));
  Insert(scrollBar);
  DirList := TDirListBox.Create(TRect.Create(3, 6, 32, 16), scrollBar);
  DirList.GrowMode := gfGrowHiX or gfGrowHiY;
  Insert(DirList);
  Insert(TLabel.Create(TRect.Create(2, 5, 17, 6), DirTreeText, DirList));

  OkButton := TButton.Create(TRect.Create(35, 6, 45, 8), OkText, cmOK, bfDefault);
  OkButton.GrowMode := gfGrowLoX or gfGrowHiX;
  Insert(OkButton);

  ChDirButton := TButton.Create(TRect.Create(35, 9, 45, 11), ChdirText, cmChangeDir, bfNormal);
  ChDirButton.GrowMode := gfGrowLoX or gfGrowHiX;
  Insert(ChDirButton);

  revertButton := TButton.Create(TRect.Create(35, 12, 45, 14), RevertText, cmRevert, bfNormal);
  revertButton.GrowMode := gfGrowLoX or gfGrowHiX;
  Insert(revertButton);

  wantsHelp := (DialogOptions and cdHelpButton) <> 0;
  if wantsHelp then
  begin
    helpButton := TButton.Create(TRect.Create(35, 15, 45, 17), HelpText, cmHelp, bfNormal);
    helpButton.GrowMode := gfGrowLoX or gfGrowHiX;
    Insert(helpButton);
  end;

  loadsDirectory := (DialogOptions and cdNoLoadDir) = 0;
  if loadsDirectory then
    SetUpDialog;

  SelectNext(False);
end;

function TChDirDialog.DataSize: Word;
begin
  Result := 0;
end;

procedure TChDirDialog.ShutDown;
begin
  DirList := nil;
  DirInput := nil;
  OkButton := nil;
  ChDirButton := nil;
  inherited ShutDown;
end;

procedure TChDirDialog.SizeLimits(var Smallest, Largest: TPoint);
begin
  inherited SizeLimits(Smallest, Largest);
  Smallest.X := 48;
  Smallest.Y := 18;
end;

procedure TChDirDialog.GetData(Rec: Pointer);
begin
end;

procedure TChDirDialog.SetData(Rec: Pointer);
begin
end;

{ Puts Path, without its separator at the end, into the input line and draws the line. }
procedure TChDirDialog.ShowPathInInput(const Path: string);
var
  shownPath: string;
begin
  shownPath := WithoutEndSeparator(Path);
  Strnzcpy(DirInput.Data, shownPath, DirInput.MaxLen + 1);
  DirInput.DrawView;
end;

procedure TChDirDialog.HandleEvent(var Event: TEvent);
var
  targetDir: string;
  entryCount: Integer;
  entry: TDirEntry;
  isDrivesEntry, startsWithSeparator, startsWithDrive, endsWithSeparator: Boolean;
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;

  case Event.Message.Command of
    cmRevert:
      targetDir := CurrentDirText;
    cmChangeDir:
      begin
        if DirList.List = nil then
          Exit;
        entryCount := DirList.List.GetCount;
        if (DirList.Focused < 0) or (DirList.Focused >= entryCount) then
          Exit;
        entry := DirList.List.At(DirList.Focused);
        targetDir := entry.Dir;
        isDrivesEntry := targetDir = DrivesText;
        if not isDrivesEntry then
        begin
          startsWithSeparator := (targetDir <> '') and IsSeparatorChar(targetDir[1]);
          startsWithDrive := (targetDir <> '') and DriveValid(targetDir[1]);
          if not (startsWithSeparator or startsWithDrive) then
            Exit;
          endsWithSeparator := IsSeparatorChar(targetDir[Length(targetDir)]);
          if not endsWithSeparator then
            targetDir := targetDir + PathSep;
        end;
      end;
  else
    Exit;
  end;

  DirList.NewDirectory(targetDir);
  ShowPathInInput(targetDir);
  DirList.Select;
  ClearEvent(Event);
end;

procedure TChDirDialog.SetUpDialog;
var
  startDir: string;
begin
  if DirList = nil then
    Exit;
  startDir := CurrentDirText;
  DirList.NewDirectory(startDir);
  if DirInput = nil then
    Exit;
  ShowPathInInput(startDir);
end;

function TChDirDialog.Valid(Command: Word): Boolean;
var
  typedPath, fullPath: string;
begin
  Result := True;
  if Command <> cmOK then
    Exit;

  typedPath := DirInput.Data;
  fullPath := WithoutEndSeparator(PathExpand(typedPath));

  if ChangeDirectory(fullPath) then
    Exit;
  MessageBox(mfError or mfOKButton, '%s: ''%s''.', [InvalidText, fullPath]);
  Result := False;
end;

initialization
  ChDirButtonDefaultHook := @MakeChDirButtonDefault;
  TChDirDialog.ChangeDirTitle := 'Change Directory';
  TChDirDialog.DirNameText := 'Directory ~n~ame';
  TChDirDialog.DirTreeText := 'Directory ~t~ree';
  TChDirDialog.OkText := 'O~K~';
  TChDirDialog.ChdirText := '~C~hdir';
  TChDirDialog.RevertText := '~R~evert';
  TChDirDialog.HelpText := 'Help';
  TChDirDialog.DrivesText := 'Drives';
  TChDirDialog.InvalidText := 'Invalid directory';

end.
