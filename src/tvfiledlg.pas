{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (TFileInputLine, TFileInfoPane, TFileDialog and the option flags fd...),
  source/tvision/stddlg.cpp (TFileInputLine, TFileInfoPane), source/tvision/tfildlg.cpp, source/tvision/tdircoll.cpp
  (the calls of validFileName and getCurDir), source/tvision/tfillist.cpp (the call of fexpand),
  include/tvision/tv.h, include/tvision/views.h, include/tvision/ttypes.h, include/tvision/config.h,
  include/tvision/util.h, source/tvision/misc.cpp (strnzcpy), source/tvision/tvtext2.cpp
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit.

  Parts of the C++ that have no unit yet, or no source among the files above:
    - The texts of TFileDialog (filesText, openText, okText, replaceText, clearText, cancelText, helpText,
      invalidDriveText and invalidFileText) are the class variables FilesText to InvalidFileText, and the texts pmText,
      amText and months of TFileInfoPane are the class variables PmText, AmText and Months. They hold the texts of
      the C++ when the unit starts.
    - The constant MAXPATH and the functions of the compatibility headers have no source here. MaxPath stands for
      MAXPATH. getCurDir and validFileName are GetCurDir and ValidFileName of TvFiles. fexpand is PathExpand and
      PathExpandFrom of TvPath, and fnsplit and fnmerge are made with PathDrive and PathSplit of TvPath and a joining
      of the parts.
    - The branches of trim that the C++ compiles when __FLAT__ is not defined are left out, because tv.h defines it.
    - The draw of TFileInfoPane reads the time of the entry as the packed time of DOS, which the structure ftime of
      the header dir.h (not among the inputs) lays over it: the bits 0 to 4 are the seconds divided by two, 5 to 10
      the minutes, 11 to 15 the hours, 16 to 20 the day, 21 to 24 the month and 25 to 31 the year after 1980. As the
      C++ does, it writes the hour that it shows (the hour modulo 12, or 12) back into the time of the entry. A month
      that is not between 1 and 12 shows no name, where the C++ reads beyond the table months. The texts that ltoa and
      itoa make are made with Str.
    - The C++ casts the owner of TFileInputLine and of TFileInfoPane to TFileDialog without a test; here an owner that
      is not a TFileDialog gives the empty text for the wild card and for the directory.
    - The text that handleEvent of TFileInputLine puts in the input line is cut to the limit MaxLen of the line, and
      the separator that it writes between a directory and the wild card is PathSep, as Valid writes it; the C++
      writes a backslash and does not cut.

  strnzcpy is Strnzcpy of TvUtil, and it is called with MaxPath.

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
  { The input line of a file dialog. It shows the name of the file that the list focuses, while it is not selected. }
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
    { The texts of the time of the day (pm and am) and the names of the months, from 1 to 12; the entry 0 is empty. }
    class var PmText: string;
    class var AmText: string;
    class var Months: array[0..12] of string;
    constructor Create(const Bounds: TRect); reintroduce;
    procedure Draw; override;
    function GetPalette: TPalette; override;
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

implementation

uses
  TvColors, TvDrawBuf, TvWindow, TvHist, TvApp, TvMsgBox, TvPath, TvUtil;

const
  { The palette of the info pane: the entry of the palette of its owner that its one entry stands for. }
  cpInfoPane = #$1E;

  { The columns of the info pane, from its right side: the size, the month, the day, the comma, the year, the hour,
    the colon, the minutes and the text of the time of the day. }
  SizeColumn = 38;
  MonthColumn = 22;
  DayColumn = 18;
  CommaColumn = 16;
  YearColumn = 15;
  HourColumn = 9;
  ColonColumn = 7;
  MinuteColumn = 6;
  DayPartColumn = 4;
  { The first year that the time of DOS counts. }
  FirstDosYear = 1980;
  { The number of hours of the clock of the day, and the number of the last month. }
  HoursOnClock = 12;
  LastMonth = 12;
  { The bit of the packed time where each part starts. }
  HourShift = 11;
  MinuteShift = 5;
  DayShift = 16;
  MonthShift = 21;
  YearShift = 25;

var
  InfoPanePalette: TPalette = nil;

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
  EventMask := EventMask or evBroadcast;
end;

procedure TFileInputLine.HandleEvent(var Event: TEvent);
var
  entry: PSearchRec;
  shownText, wildCardText: string;
begin
  inherited HandleEvent(Event);
  if Event.What <> evBroadcast then
    Exit;
  if Event.Message.Command <> cmFileFocused then
    Exit;
  if (State and sfSelected) <> 0 then
    Exit;
  entry := PSearchRec(Event.Message.InfoPtr);
  shownText := TrimName(entry^.Name);
  wildCardText := '';
  if (entry^.Attr and FA_DIREC) <> 0 then
  begin
    if Owner is TFileDialog then
      wildCardText := TFileDialog(Owner).WildCard;
    shownText := Concat(shownText, PathSep, wildCardText);
  end;
  Data := Copy(shownText, 1, MaxLen);
  SelectAll(False);
  DrawView;
end;

{ TFileInfoPane }

constructor TFileInfoPane.Create(const Bounds: TRect);
begin
  inherited Create(Bounds);
  EventMask := EventMask or evBroadcast;
end;

{ The low attribute of the entry Entry of the palette of Viewer. }
function LowAttrOf(Viewer: TView; Entry: Word): TColorAttr;
var
  pair: TAttrPair;
begin
  pair := Viewer.GetColor(Entry);
  Result := pair.Attrs[0];
end;

{ The text of Value with at least two digits, the first of them a zero when Value is below ten. }
function TwoDigits(Value: Integer): string;
var
  digits: string;
begin
  Str(Value, digits);
  if Value >= 10 then
    Result := digits
  else
    Result := '0' + digits;
end;

{ Writes the size and the time of Entry into Buffer, at columns counted from the right side of a row of Width cells.
  The time is the packed time of DOS. The hour that is shown is written back into the time of Entry. }
procedure ShowEntryColumns(Buffer: TDrawBuffer; Width: Integer; Color: TColorAttr; var Entry: TvFiles.TSearchRec);
var
  parts: Cardinal;
  clock, month: Integer;
  sizeText, yearText: string;
  afternoon: Boolean;

  procedure Put(FromRight: Integer; const Text: string);
  begin
    Buffer.MoveStr(Word(Width - FromRight), Text, Color);
  end;

begin
  parts := Cardinal(Entry.Time);
  clock := (parts shr HourShift) and $1F;
  afternoon := clock >= HoursOnClock;
  clock := clock mod HoursOnClock;
  if clock = 0 then
    clock := HoursOnClock;
  Entry.Time := LongInt((parts and not Cardinal($1F shl HourShift)) or (Cardinal(clock) shl HourShift));

  Str(Entry.Size, sizeText);
  Put(SizeColumn, sizeText);
  month := (parts shr MonthShift) and $F;
  if month <= LastMonth then
    Put(MonthColumn, TFileInfoPane.Months[month]);
  Put(DayColumn, TwoDigits((parts shr DayShift) and $1F));
  Buffer.PutChar(Word(Width - CommaColumn), Ord(','));
  Str(Integer((parts shr YearShift) and $7F) + FirstDosYear, yearText);
  Put(YearColumn, yearText);
  Put(HourColumn, TwoDigits(clock));
  Buffer.PutChar(Word(Width - ColonColumn), Ord(':'));
  Put(MinuteColumn, TwoDigits((parts shr MinuteShift) and $3F));
  if afternoon then
    Put(DayPartColumn, TFileInfoPane.PmText)
  else
    Put(DayPartColumn, TFileInfoPane.AmText);
end;

procedure TFileInfoPane.Draw;
var
  lineBuffer: TDrawBuffer;
  color: TColorAttr;
  path, directoryText, wildCardText: string;
  row, restRows: Integer;
begin
  directoryText := '';
  wildCardText := '';
  if Owner is TFileDialog then
  begin
    directoryText := TFileDialog(Owner).Directory;
    wildCardText := TFileDialog(Owner).WildCard;
  end;
  Strnzcpy(path, directoryText, MaxPath);
  Strnzcat(path, wildCardText, MaxPath);
  path := PathExpand(path);
  if Length(path) > MaxPath - 1 then
    SetLength(path, MaxPath - 1);

  color := LowAttrOf(Self, 1);
  lineBuffer := TDrawBuffer.Create;
  try
    restRows := 1;
    for row := 0 to 2 do
    begin
      lineBuffer.MoveChar(0, ' ', color, Size.X);
      case row of
        0:
          lineBuffer.MoveStr(1, path, color);
        1:
          begin
            lineBuffer.MoveStr(1, FileBlock.Name, color);
            if FileBlock.Name <> '' then
              ShowEntryColumns(lineBuffer, Size.X, color, FileBlock);
          end;
      else
        restRows := Size.Y - 2;
      end;
      WriteLine(0, row, Size.X, restRows, lineBuffer);
    end;
  finally
    lineBuffer.Free;
  end;
end;

function TFileInfoPane.GetPalette: TPalette;
begin
  Result := InfoPanePalette;
end;

procedure TFileInfoPane.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What <> evBroadcast then
    Exit;
  if Event.Message.Command <> cmFileFocused then
    Exit;
  FileBlock := PSearchRec(Event.Message.InfoPtr)^;
  DrawView;
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
  Strnzcpy(WildCard, WildCardText, MaxPath);

  FileName := TFileInputLine.Create(TRect.Create(3, 3, InputLineRight, 4), MaxPath);
  Strnzcpy(FileName.Data, WildCard, MaxPath);
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
begin
  Directory := GetCurDir;
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

  if ValidFileName(fullName) then
  begin
    Result := True;
    Exit;
  end;
  MessageBox(mfError or mfOKButton, '%s: ''%s''', [InvalidFileText, fullName]);
end;

initialization
  InfoPanePalette := TPalette.Create(cpInfoPane, Length(cpInfoPane));
  TFileDialog.FilesText := '~F~iles';
  TFileDialog.OpenText := '~O~pen';
  TFileDialog.OkText := 'O~K~';
  TFileDialog.ReplaceText := '~R~eplace';
  TFileDialog.ClearText := '~C~lear';
  TFileDialog.CancelText := 'Cancel';
  TFileDialog.HelpText := '~H~elp';
  TFileDialog.InvalidDriveText := 'Invalid drive or directory';
  TFileDialog.InvalidFileText := 'Invalid file name';
  TFileInfoPane.PmText := 'p';
  TFileInfoPane.AmText := 'a';
  TFileInfoPane.Months[0] := '';
  TFileInfoPane.Months[1] := 'Jan';
  TFileInfoPane.Months[2] := 'Feb';
  TFileInfoPane.Months[3] := 'Mar';
  TFileInfoPane.Months[4] := 'Apr';
  TFileInfoPane.Months[5] := 'May';
  TFileInfoPane.Months[6] := 'Jun';
  TFileInfoPane.Months[7] := 'Jul';
  TFileInfoPane.Months[8] := 'Aug';
  TFileInfoPane.Months[9] := 'Sep';
  TFileInfoPane.Months[10] := 'Oct';
  TFileInfoPane.Months[11] := 'Nov';
  TFileInfoPane.Months[12] := 'Dec';

finalization
  InfoPanePalette.Free;
  InfoPanePalette := nil;

end.
