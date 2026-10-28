{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (TFileInputLine, TFileInfoPane, TFileDialog and the option flags fd...),
  source/tvision/tfildlg.cpp, include/tvision/tv.h, include/tvision/views.h, include/tvision/ttypes.h,
  include/tvision/config.h
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit.

  Parts of the C++ that have no unit yet, or no source among the files above:
    - TFileInputLine and TFileInfoPane: the file that implements them is not among the inputs, so only what the
      header declares is translated. The constructor of TFileInputLine only calls the one of TInputLine. The
      handleEvent of TFileInputLine is FileInputLineEventHook, and the draw and the handleEvent of TFileInfoPane are
      FileInfoPaneDrawHook and FileInfoPaneEventHook. The hooks do nothing while they are nil; the event hooks run
      after the member of the base class. The constructor of TFileInfoPane only calls the one of TView, so its
      event mask is the one of TView, a hook that handles broadcasts has to widen it. The tables months, pmText and
      amText and the palette of TFileInfoPane belong to that file and are left out; the palette is the one of TView.
    - The texts of TFileDialog (filesText, openText, okText, replaceText, clearText, cancelText, helpText,
      invalidDriveText and invalidFileText) are defined in a file that is not among the inputs, so they are the
      class variables FilesText to InvalidFileText, empty until the program sets them.
    - The constant MAXPATH, the functions strnzcpy, getCurDir and validFileName and the functions of the
      compatibility headers have no source here. MaxPath stands for MAXPATH. StrNZCopyHook of TvHist stands for
      strnzcpy and is called with MaxPath; GetCurDirHook stands for getCurDir and ValidFileNameHook for
      validFileName. While StrNZCopyHook is nil a text is not copied and its target keeps its text; while
      GetCurDirHook is nil the directory of a file dialog becomes the empty text; while ValidFileNameHook is nil no
      name is a valid file name. fexpand is PathExpandFrom of TvPath, and fnsplit and fnmerge are made with
      PathDrive and PathSplit of TvPath and a joining of the parts.
    - message() sends a message to a view; MessageHook of TvViews stands for it, as it does in TvFiles.
    - The branches of trim that the C++ compiles when __FLAT__ is not defined are left out, because tv.h defines it.

  The text of a path is a string. A file dialog that has no application (TProgram.Application is nil) keeps the
  bounds that its constructor gives it, because the fit to the screen needs the size of the application. }
unit TvFileDlg;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvEvents, TvViews, TvInput, TvDialog, TvFiles;

const
  { The options of a file dialog. }
  fdOKButton = Word($0001);
  fdOpenButton = Word($0002);
  fdReplaceButton = Word($0004);
  fdClearButton = Word($0008);
  fdHelpButton = Word($0010);
  fdNoLoadDir = Word($0100);

  { The size of a block that holds a path: the value of MAXPATH. }
  MaxPath = 260;

type
  TFileInputLine = class;
  TFileInfoPane = class;

  { Does what the handleEvent of TFileInputLine does beyond the one of TInputLine. }
  TFileInputLineEventProc = procedure(Line: TFileInputLine; var Event: TEvent);
  { Draws a TFileInfoPane. }
  TFileInfoPaneDrawProc = procedure(Pane: TFileInfoPane);
  { Does what the handleEvent of TFileInfoPane does beyond the one of TView. }
  TFileInfoPaneEventProc = procedure(Pane: TFileInfoPane; var Event: TEvent);
  { Gives the current directory, as getCurDir does. }
  TCurDirFunc = function: string;
  { Tells whether Name is a valid name for a file, as validFileName does. }
  TValidFileNameFunc = function(const Name: string): Boolean;

  { The input line of a file dialog. }
  TFileInputLine = class(TInputLine)
  public
    constructor Create(const Bounds: TRect; MaxLength: SmallInt); reintroduce;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { The view of a file dialog that shows the file that is focused in the list. The palette is: 1 normal. }
  TFileInfoPane = class(TView)
  public
    { The entry that the pane shows. }
    FileBlock: TSearchRec;
    constructor Create(const Bounds: TRect); reintroduce;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
  end;

  { A dialog that asks for the name of a file. The data of the dialog is a block of characters that holds the name. }
  TFileDialog = class(TDialog)
  private
    procedure ReadDirectory;
    function CheckDirectory(const Path: string): Boolean;
    procedure AddButton(const Caption: string; ButtonCommand, ButtonFlags: Word; var Area: TRect);
    procedure FitToScreen;
    procedure FinishWithFileCommand(var Event: TEvent);
    procedure TurnDoubleClickIntoOK(var Event: TEvent);
  public
    FileName: TFileInputLine;
    FileList: TFileList;
    WildCard: string;
    Directory: string;
    class var FilesText: string;
    class var OpenText: string;
    class var OkText: string;
    class var ReplaceText: string;
    class var ClearText: string;
    class var CancelText: string;
    class var HelpText: string;
    class var InvalidDriveText: string;
    class var InvalidFileText: string;
    constructor Create(const WildCardText, TitleText, InputLabelText: string; DialogOptions: Word;
      HistoryListId: Byte); reintroduce;
    procedure GetData(Rec: Pointer); override;
    { The name that the input line holds, expanded and completed with the wild card. }
    function GetFileName: string;
    procedure HandleEvent(var Event: TEvent); override;
    procedure SetData(Rec: Pointer); override;
    function Valid(Command: Word): Boolean; override;
    procedure ShutDown; override;
    procedure SizeLimits(var Smallest, Largest: TPoint); override;
  end;

var
  FileInputLineEventHook: TFileInputLineEventProc;
  FileInfoPaneDrawHook: TFileInfoPaneDrawProc;
  FileInfoPaneEventHook: TFileInfoPaneEventProc;
  GetCurDirHook: TCurDirFunc;
  ValidFileNameHook: TValidFileNameFunc;

implementation

uses
  TvWindow, TvHist, TvApp, TvMsgBox, TvPath, TvUtil;

const
  { The place of the input line, of its label and of the other views of the dialog. }
  InputLineRight = 31;
  ButtonColumnLeft = 35;
  ButtonColumnRight = 46;
  ButtonRowStep = 3;
  { The size that the dialog is made when the screen is wide or tall, and the margins of the middle sizes. }
  WideScreenColumns = 90;
  MediumScreenColumns = 63;
  TallScreenRows = 34;
  MediumScreenRows = 25;
  SideMargin = 7;
  TopMargin = 3;
  WideGrow = 15;
  TallGrow = 5;
  { The smallest size of the dialog. }
  SmallestWidth = 49;
  SmallestHeight = 19;

{ The text that StrNZCopyHook gives for Source, put in Target; Target keeps its text while there is no hook. }
procedure CopyThrough(var Target: string; const Source: string);
begin
  if not Assigned(StrNZCopyHook) then
    Exit;
  Target := StrNZCopyHook(Source, MaxPath);
end;

{ The text up to its first zero character, as the copy of trim for a target with a flat memory model takes it. }
function TrimName(const Source: string): string;
var
  zeroPosition: Integer;
begin
  zeroPosition := Pos(#0, Source);
  if zeroPosition = 0 then
    Result := Source
  else
    Result := Copy(Source, 1, zeroPosition - 1);
end;

{ Cuts a path into the drive, the directory with its last separator, the name and the extension with its dot. }
procedure SplitPath(const FullPath: string; out DrivePart, DirectoryPart, NamePart, ExtensionPart: string);
var
  wholePath, driveOfPath, directoryWithDrive, nameOfPath, extensionOfPath: AnsiString;
begin
  wholePath := FullPath;
  driveOfPath := PathDrive(wholePath);
  PathSplit(wholePath, directoryWithDrive, nameOfPath, extensionOfPath);
  DrivePart := driveOfPath;
  DirectoryPart := Copy(directoryWithDrive, Length(driveOfPath) + 1, Length(directoryWithDrive));
  NamePart := nameOfPath;
  ExtensionPart := extensionOfPath;
end;

{ Puts the four parts of a path together. }
function MergePath(const DrivePart, DirectoryPart, NamePart, ExtensionPart: string): string;
begin
  Result := DrivePart + DirectoryPart + NamePart + ExtensionPart;
end;

{ TFileInputLine }

constructor TFileInputLine.Create(const Bounds: TRect; MaxLength: SmallInt);
begin
  inherited Create(Bounds, MaxLength);
end;

procedure TFileInputLine.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if not Assigned(FileInputLineEventHook) then
    Exit;
  FileInputLineEventHook(Self, Event);
end;

{ TFileInfoPane }

constructor TFileInfoPane.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
end;

procedure TFileInfoPane.Draw;
begin
  if not Assigned(FileInfoPaneDrawHook) then
    Exit;
  FileInfoPaneDrawHook(Self);
end;

procedure TFileInfoPane.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if not Assigned(FileInfoPaneEventHook) then
    Exit;
  FileInfoPaneEventHook(Self, Event);
end;

{ TFileDialog }

procedure TFileDialog.AddButton(const Caption: string; ButtonCommand, ButtonFlags: Word; var Area: TRect);
begin
  Insert(TButton.Create(Area, Caption, ButtonCommand, ButtonFlags));
  First.GrowMode := Byte(gfGrowLoX or gfGrowHiX);
  Area.A.Y := Area.A.Y + ButtonRowStep;
  Area.B.Y := Area.B.Y + ButtonRowStep;
end;

procedure TFileDialog.FitToScreen;
var
  dialogBounds, screenBounds: TRect;
  screenSize: TPoint;
  isWide, isMediumWide, isTall, isMediumTall: Boolean;
begin
  dialogBounds := GetBounds;
  screenSize := TProgram.Application.Size;
  screenBounds := TProgram.Application.GetBounds;

  isWide := screenSize.X > WideScreenColumns;
  isMediumWide := (not isWide) and (screenSize.X > MediumScreenColumns);
  if isWide then
    dialogBounds.Grow(WideGrow, 0)
  else if isMediumWide then
  begin
    screenBounds.Grow(-SideMargin, 0);
    dialogBounds.A.X := screenBounds.A.X;
    dialogBounds.B.X := screenBounds.B.X;
  end;

  isTall := screenSize.Y > TallScreenRows;
  isMediumTall := (not isTall) and (screenSize.Y > MediumScreenRows);
  if isTall then
    dialogBounds.Grow(0, TallGrow)
  else if isMediumTall then
  begin
    screenBounds.Grow(0, -TopMargin);
    dialogBounds.A.Y := screenBounds.A.Y;
    dialogBounds.B.Y := screenBounds.B.Y;
  end;

  Locate(dialogBounds);
end;

constructor TFileDialog.Create(const WildCardText, TitleText, InputLabelText: string; DialogOptions: Word;
  HistoryListId: Byte);
var
  scrollBar: TScrollBar;
  nextFlags: Word;
  buttonArea: TRect;
begin
  inherited Create(TRect.Create(15, 1, 64, 20), TitleText);
  Directory := '';
  Options := Options or ofCentered;
  Flags := Byte(Flags or wfGrow);
  CopyThrough(WildCard, WildCardText);

  FileName := TFileInputLine.Create(TRect.Create(3, 3, InputLineRight, 4), MaxPath);
  CopyThrough(FileName.Data, WildCard);
  Insert(FileName);
  First.GrowMode := Byte(gfGrowHiX);

  Insert(TLabel.Create(TRect.Create(2, 2, 3 + Cstrlen(InputLabelText), 3), InputLabelText, FileName));
  First.GrowMode := 0;
  Insert(THistory.Create(TRect.Create(InputLineRight, 3, 34, 4), FileName, HistoryListId));
  First.GrowMode := Byte(gfGrowLoX or gfGrowHiX);
  scrollBar := TScrollBar.Create(TRect.Create(3, 14, 34, 15));
  Insert(scrollBar);
  FileList := TFileList.Create(TRect.Create(3, 6, 34, 14), scrollBar);
  Insert(FileList);
  First.GrowMode := Byte(gfGrowHiX or gfGrowHiY);
  Insert(TLabel.Create(TRect.Create(2, 5, 8, 6), FilesText, FileList));
  First.GrowMode := 0;

  nextFlags := bfDefault;
  buttonArea := TRect.Create(ButtonColumnLeft, 3, ButtonColumnRight, 5);

  if (DialogOptions and fdOpenButton) <> 0 then
  begin
    AddButton(OpenText, cmFileOpen, nextFlags, buttonArea);
    nextFlags := bfNormal;
  end;
  if (DialogOptions and fdOKButton) <> 0 then
  begin
    AddButton(OkText, cmFileOpen, nextFlags, buttonArea);
    nextFlags := bfNormal;
  end;
  if (DialogOptions and fdReplaceButton) <> 0 then
  begin
    AddButton(ReplaceText, cmFileReplace, nextFlags, buttonArea);
    nextFlags := bfNormal;
  end;
  if (DialogOptions and fdClearButton) <> 0 then
  begin
    AddButton(ClearText, cmFileClear, nextFlags, buttonArea);
    nextFlags := bfNormal;
  end;

  AddButton(CancelText, cmCancel, bfNormal, buttonArea);
  if (DialogOptions and fdHelpButton) <> 0 then
    AddButton(HelpText, cmHelp, bfNormal, buttonArea);

  Insert(TFileInfoPane.Create(TRect.Create(1, 16, 48, 18)));
  First.GrowMode := Byte(gfGrowAll and (not gfGrowLoX) and $FF);
  SelectNext(False);

  if TProgram.Application <> nil then
    FitToScreen;

  if (DialogOptions and fdNoLoadDir) = 0 then
    ReadDirectory;
end;

procedure TFileDialog.ShutDown;
begin
  FileName := nil;
  FileList := nil;
  inherited ShutDown;
end;

procedure TFileDialog.SizeLimits(var Smallest, Largest: TPoint);
begin
  inherited SizeLimits(Smallest, Largest);
  Smallest.X := SmallestWidth;
  Smallest.Y := SmallestHeight;
end;

function TFileDialog.GetFileName: string;
var
  typedName, expandedName: string;
  driveText, directoryText, baseName, extensionText: string;
  wildDrive, wildDirectory, wildBase, wildExtension: string;
  hasNoName: Boolean;
begin
  typedName := TrimName(FileName.Data);
  expandedName := PathExpandFrom(typedName, Directory);
  SplitPath(expandedName, driveText, directoryText, baseName, extensionText);
  hasNoName := (baseName = '') and (extensionText = '');
  if hasNoName then
  begin
    SplitPath(WildCard, wildDrive, wildDirectory, wildBase, wildExtension);
    expandedName := MergePath(driveText, directoryText, wildBase, wildExtension);
  end;
  Result := expandedName;
end;

procedure TFileDialog.FinishWithFileCommand(var Event: TEvent);
var
  chosenCommand: Word;
begin
  chosenCommand := Event.Message.Command;
  case chosenCommand of
    cmFileOpen, cmFileReplace, cmFileClear:
      begin
        EndModal(chosenCommand);
        ClearEvent(Event);
      end;
  end;
end;

procedure TFileDialog.TurnDoubleClickIntoOK(var Event: TEvent);
var
  okEvent: TEvent;
begin
  if Event.Message.Command <> cmFileDoubleClicked then
    Exit;
  okEvent := Event;
  okEvent.What := evCommand;
  okEvent.Message.Command := cmOK;
  Event := okEvent;
  PutEvent(Event);
  ClearEvent(Event);
end;

procedure TFileDialog.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  case Event.What of
    evCommand:
      FinishWithFileCommand(Event);
    evBroadcast:
      TurnDoubleClickIntoOK(Event);
  end;
end;

procedure TFileDialog.ReadDirectory;
var
  currentDirectory: string;
begin
  if Assigned(GetCurDirHook) then
    currentDirectory := GetCurDirHook()
  else
    currentDirectory := '';
  Directory := currentDirectory;
  FileList.ReadDirectory(WildCard);
end;

procedure TFileDialog.SetData(Rec: Pointer);
var
  recordText: string;
begin
  inherited SetData(Rec);
  if PAnsiChar(Rec)^ = #0 then
    Exit;
  recordText := PAnsiChar(Rec);
  if not IsWild(recordText) then
    Exit;
  Valid(cmFileInit);
  FileName.Select;
end;

procedure TFileDialog.GetData(Rec: Pointer);
var
  nameText: string;
  nameLength: Integer;
begin
  nameText := GetFileName;
  nameLength := Length(nameText);
  if nameLength > 0 then
    Move(nameText[1], PAnsiChar(Rec)^, nameLength);
  PAnsiChar(Rec)[nameLength] := #0;
end;

function TFileDialog.CheckDirectory(const Path: string): Boolean;
begin
  if PathValid(Path) then
  begin
    Result := True;
    Exit;
  end;
  MessageBox(mfError or mfOKButton, '%s: ''%s''', [InvalidDriveText, Path]);
  FileName.Select;
  Result := False;
end;

function TFileDialog.Valid(Command: Word): Boolean;
var
  fullName, driveText, directoryText, baseName, extensionText, directoryPath: string;
  isNameValid: Boolean;
begin
  Result := False;
  if Command = cmValid then
  begin
    Result := True;
    Exit;
  end;
  if not inherited Valid(Command) then
    Exit;
  if (Command = cmCancel) or (Command = cmFileClear) then
  begin
    Result := True;
    Exit;
  end;

  fullName := GetFileName;

  if IsWild(fullName) then
  begin
    SplitPath(fullName, driveText, directoryText, baseName, extensionText);
    directoryPath := driveText + directoryText;
    if CheckDirectory(directoryPath) then
    begin
      Directory := directoryPath;
      WildCard := baseName + extensionText;
      if Command <> cmFileInit then
        FileList.Select;
      FileList.ReadDirectory(Directory, WildCard);
    end;
    Exit;
  end;

  if IsDir(fullName) then
  begin
    if CheckDirectory(fullName) then
    begin
      Directory := fullName + PathSep;
      if Command <> cmFileInit then
        FileList.Select;
      FileList.ReadDirectory(Directory, WildCard);
    end;
    Exit;
  end;

  isNameValid := Assigned(ValidFileNameHook) and ValidFileNameHook(fullName);
  if isNameValid then
  begin
    Result := True;
    Exit;
  end;
  MessageBox(mfError or mfOKButton, '%s: ''%s''', [InvalidFileText, fullName]);
end;

end.
