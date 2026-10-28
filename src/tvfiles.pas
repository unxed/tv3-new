{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (the commands of the file dialogs, TSearchRec, TFileCollection,
  TSortedListBox, TFileList, TDirEntry, TDirCollection, TDirListBox), source/tvision/tfilecol.cpp,
  source/tvision/tfillist.cpp, source/tvision/tdircoll.cpp, source/tvision/tdirlist.cpp, source/tvision/tvtext1.cpp
  (the tables of TDirListBox), include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h,
  include/tvision/views.h
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the classes, and the constructors with StreamableInit, belong to a later
  unit.

  Parts of the C++ that have no unit yet, or no source among the files above:
    - message() sends a message to a view; MessageHook of TvViews stands for it and does nothing while it is nil.
    - TSortedListBox: its source file is not among the inputs. The class is declared as the header gives it, with
      the member that the header defines (List) and the constructor, which only calls the one of TListBox. Its
      NewList is SortedListBoxNewListHook and does nothing while that is nil; its handleEvent is not translated, so
      the list box keeps the handling of TListBox; its virtual getKey is abstract here. The protected member
      ShiftState stays 0 until a descendant sets it; the member searchPos is left out, because only handleEvent
      uses it.
    - TChDirDialog and its member chDirButton: the setState of TDirListBox reaches them through
      ChDirButtonDefaultHook, which does nothing while it is nil.
    - The text tooManyFiles is defined in a file that is not among the inputs, so it is the class variable
      TooManyFiles of TFileList, empty until the program sets it.
    - The functions of the compatibility headers dir.h and dos.h (findfirst, findnext, getdisk, fnsplit, fnmerge,
      fexpand) are made with the routines of SysUtils and of TvPath: a search is FindFirst and FindNext of SysUtils
      with the mask faReadOnly, faArchive, faHidden and faSymLink for the files and faDirectory and faSymLink for the
      directories, because the library of the RTL leaves out the hidden entries and the links unless the mask asks
      for them. The disk that getdisk gives is the disk C, which is the only disk that exists.

  Only the target without drives is translated: the entry Drives that newDirectory adds on other targets is left out,
  and the separator of the paths that TDirListBox reads is PathSep of TvPath. The texts of the drives that showDrives
  makes keep the backslash of the C++. The names of the files are at most MaxNameLength characters, because the size
  MAXFILE + MAXEXT - 1 is given by a header that is not among the inputs.

  The collections of TvObjs that a Pascal class holds as TCollection and as TSortedCollection have no common
  descendant, so the sorted list box turns the list of TListBox into a TSortedCollection by a typecast; both are the
  same kind of object of TNSCollection. The routines validFileName and getCurDir of tdircoll.cpp, and fexpand, squeeze
  and getHomeDir of tfillist.cpp, are not translated here: TvPath has the path functions of the library. }
unit TvFiles;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvObjs, TvViews, TvWindow, TvList;

const
  { The commands of the file dialogs. }
  cmFileOpen = 1001;
  cmFileReplace = 1002;
  cmFileClear = 1003;
  cmFileInit = 1004;
  cmChangeDir = 1005;
  cmRevert = 1006;

  { The messages of a file list. }
  cmFileFocused = 102;
  cmFileDoubleClicked = 103;

  { The attributes of a file that TSearchRec holds. }
  FA_RDONLY = $01;
  FA_DIREC = $10;
  FA_ARCH = $20;

  { The longest name that a TSearchRec holds. }
  MaxNameLength = 255;

type
  { An entry of a directory: its name, its size, its time in the DOS format and its attributes. }
  TSearchRec = record
    Name: string[MaxNameLength];
    Size, Time: LongInt;
    Attr: Byte;
  end;
  PSearchRec = ^TSearchRec;

  { The entries of a directory in the order of the file list: the files, then the directories, then '..'. The items
    are PSearchRec. }
  TFileCollection = class(TSortedCollection)
  protected
    function Compare(Key1, Key2: Pointer): Integer; override;
    procedure FreeItem(Item: Pointer); override;
  public
    function At(Index: ccIndex): PSearchRec; reintroduce;
    function FirstThat(Test: ccTestFunc; Arg: Pointer): PSearchRec; reintroduce;
    function LastThat(Test: ccTestFunc; Arg: Pointer): PSearchRec; reintroduce;
  end;

  TSortedListBox = class;

  { Does what SortedListBoxNewListHook stands for: puts a list into Box. }
  TSortedNewListProc = procedure(Box: TSortedListBox; NewItems: TSortedCollection);

  { A list box whose list is a sorted collection. }
  TSortedListBox = class(TListBox)
  protected
    ShiftState: Byte;
    function GetKey(const S: string): Pointer; virtual; abstract;
  public
    constructor Create(const Bounds: TRect; NumberOfColumns: Word; VerticalBar: TScrollBar); reintroduce;
    procedure NewList(NewItems: TSortedCollection); reintroduce;
    function List: TSortedCollection; reintroduce;
  end;

  { A list of the files of a directory, in two columns. }
  TFileList = class(TSortedListBox)
  public
    { The text of the warning that the list has not room for all the files. }
    class var TooManyFiles: string;
    constructor Create(const Bounds: TRect; AScrollBar: TScrollBar); reintroduce;
    destructor Destroy; override;
    procedure FocusItem(ItemIndex: SmallInt); override;
    procedure SelectItem(ItemIndex: SmallInt); override;
    function GetText(ItemIndex, MaxLen: SmallInt): string; override;
    procedure NewList(NewItems: TFileCollection); reintroduce;
    procedure ReadDirectory(const Dir, WildCard: string); overload;
    procedure ReadDirectory(const WildCard: string); overload;
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    procedure SetData(Rec: Pointer); override;
    function List: TFileCollection; reintroduce;
  protected
    function GetKey(const S: string): Pointer; override;
  end;

  { An entry of the list of directories: the text that is shown and the path that it stands for. Both are blocks of
    characters with a terminating zero. }
  TDirEntry = class
  private
    DisplayText: PAnsiChar;
    Directory: PAnsiChar;
  public
    constructor Create(const ShownText, DirectoryPath: string);
    destructor Destroy; override;
    function Dir: PAnsiChar;
    function Text: PAnsiChar;
  end;

  { A collection of TDirEntry that is not sorted. }
  TDirCollection = class(TCollection)
  protected
    procedure FreeItem(Item: Pointer); override;
  public
    function At(Index: ccIndex): TDirEntry; reintroduce;
    function FirstThat(Test: ccTestFunc; Arg: Pointer): TDirEntry; reintroduce;
    function LastThat(Test: ccTestFunc; Arg: Pointer): TDirEntry; reintroduce;
  end;

  TDirListBox = class;

  { Does what ChDirButtonDefaultHook stands for: makes the button of the dialog that owns Box the default button, or
    stops it from being so. }
  TMakeDefaultProc = procedure(Box: TDirListBox; Enable: Boolean);

  { A list box that shows the path to a directory as a tree, and the subdirectories of the last directory. }
  TDirListBox = class(TListBox)
  private
    Dir: string;
    Cur: Word;
    procedure ShowDrives(Dirs: TDirCollection);
    procedure ShowDirs(Dirs: TDirCollection);
  public
    class var PathDir: string;
    class var FirstDir: string;
    class var MiddleDir: string;
    class var LastDir: string;
    class var Drives: string;
    class var Graphics: string;
    constructor Create(const Bounds: TRect; AScrollBar: TScrollBar); reintroduce;
    destructor Destroy; override;
    function GetText(ItemIndex, MaxLen: SmallInt): string; override;
    function IsSelected(ItemIndex: SmallInt): Boolean; override;
    procedure SelectItem(ItemIndex: SmallInt); override;
    procedure NewDirectory(const Path: string);
    procedure SetState(StateBits: Word; TurnOn: Boolean); override;
    function List: TDirCollection; reintroduce;
  end;

var
  { Stands for the newList of TSortedListBox; nil does nothing. }
  SortedListBoxNewListHook: TSortedNewListProc;
  { Stands for chDirButton->makeDefault of the TChDirDialog that owns a TDirListBox; nil does nothing. }
  ChDirButtonDefaultHook: TMakeDefaultProc;

{ Stands for getdisk: the number of the current disk, 0 for A. }
function GetDisk: Integer;

{ Tells whether the disk Drive exists. }
function DriveValid(Drive: Char): Boolean;

{ Tells whether Path names a directory. }
function IsDir(const Path: string): Boolean;

{ Tells whether Path names a directory that exists, or the root. }
function PathValid(const Path: string): Boolean;

{ Tells whether Name has a wild card character, ? or *. }
function IsWild(const Name: string): Boolean;

implementation

uses
  SysUtils, TvEvents, TvKeys, TvUtil, TvPath, TvMsgbox;

const
  { The number of cells that a level of directories is indented by. }
  IndentStep = 2;
  { The disk that stands for the current one: C. }
  CurrentDisk = 2;
  { The time of a directory '..' that cannot be read: the date 1 January 1980 in the DOS format, and no time. }
  DefaultParentTime = $210000;

var
  { The key that GetKey of TFileList gives. }
  SearchKey: TSearchRec;
  { The entry that is sent when a directory has no file. }
  NoFileRecord: TSearchRec;

{ Sends a message through the hook; nothing happens while there is none. }
procedure SendNotice(Receiver: TView; What, Command: Word; Info: Pointer);
begin
  if not Assigned(MessageHook) then
    Exit;
  MessageHook(Receiver, What, Command, Info);
end;

{ Orders two names byte by byte, as strcmp does: a name that begins another one is the smaller. }
function CompareNames(const FirstName, SecondName: ShortString): Integer;
var
  position, sharedLength: Integer;
  firstByte, secondByte: Byte;
begin
  sharedLength := Length(FirstName);
  if Length(SecondName) < sharedLength then
    sharedLength := Length(SecondName);
  for position := 1 to sharedLength do
  begin
    firstByte := Ord(FirstName[position]);
    secondByte := Ord(SecondName[position]);
    if firstByte < secondByte then
    begin
      Result := -1;
      Exit;
    end;
    if firstByte > secondByte then
    begin
      Result := 1;
      Exit;
    end;
  end;
  if Length(FirstName) < Length(SecondName) then
    Result := -1
  else if Length(FirstName) > Length(SecondName) then
    Result := 1
  else
    Result := 0;
end;

{ The place of the first separator at or after StartAt, or 0. }
function FindSeparator(const Text: string; StartAt: Integer): Integer;
var
  position: Integer;
begin
  for position := StartAt to Length(Text) do
    if Text[position] = PathSep then
    begin
      Result := position;
      Exit;
    end;
  Result := 0;
end;

{ The place of the last separator, or 0. }
function FindLastSeparator(const Text: string): Integer;
var
  position: Integer;
begin
  for position := Length(Text) downto 1 do
    if Text[position] = PathSep then
    begin
      Result := position;
      Exit;
    end;
  Result := 0;
end;

{ Tells whether a name is one of '.', '..' or a hidden name: its first character is a dot. }
function BeginsWithDot(const Name: string): Boolean;
begin
  Result := (Name <> '') and (Name[1] = '.');
end;

{ The first place in Text that holds Code, or nil. }
function FindCode(Text: PAnsiChar; Code: Char): PAnsiChar;
begin
  while Text^ <> #0 do
  begin
    if Text^ = Code then
    begin
      Result := Text;
      Exit;
    end;
    Inc(Text);
  end;
  Result := nil;
end;

{ A new entry, or nil when there is no memory for it. }
function NewSearchRecord: PSearchRec;
begin
  Result := nil;
  try
    New(Result);
    FillChar(Result^, SizeOf(TSearchRec), 0);
  except
    on EOutOfMemory do
      Result := nil;
  end;
end;

{ Takes the attributes, the time, the size and the name of an entry that the RTL found. }
procedure CopyFoundEntry(Target: PSearchRec; const Found: SysUtils.TSearchRec);
begin
  Target^.Attr := Byte(Found.Attr and $FF);
  Target^.Time := Found.Time;
  Target^.Size := LongInt(Found.Size);
  Target^.Name := Found.Name;
end;

{ Functions }

function GetDisk: Integer;
begin
  Result := CurrentDisk;
end;

function DriveValid(Drive: Char): Boolean;
begin
  Result := (Ord(Drive) - Ord('A')) = GetDisk;
end;

function IsDir(const Path: string): Boolean;
var
  found: SysUtils.TSearchRec;
  status: Integer;
  isFound, hasDirectoryBit: Boolean;
begin
  status := FindFirst(Path, faDirectory or faSymLink, found);
  isFound := status = 0;
  hasDirectoryBit := (found.Attr and faDirectory) <> 0;
  Result := isFound and hasDirectoryBit;
  FindClose(found);
end;

function PathValid(const Path: string): Boolean;
var
  expanded: string;
  isRootOnly: Boolean;
begin
  expanded := PathExpand(Path);
  isRootOnly := (Length(expanded) = 1) and IsPathSep(expanded[1]);
  if isRootOnly then
  begin
    Result := True;
    Exit;
  end;
  if EndsWithSep(expanded) then
    SetLength(expanded, Length(expanded) - 1);
  Result := IsDir(expanded);
end;

function IsWild(const Name: string): Boolean;
const
  WildCharacters = ['?', '*'];
var
  nextPosition: Integer;
  currentChar: Char;
begin
  nextPosition := 1;
  while nextPosition <= Length(Name) do
  begin
    currentChar := Name[nextPosition];
    if currentChar in WildCharacters then
      Exit(True);
    Inc(nextPosition);
  end;
  Result := False;
end;

{ TFileCollection }

function TFileCollection.Compare(Key1, Key2: Pointer): Integer;
var
  firstRec, secondRec: PSearchRec;
  firstIsDir, secondIsDir: Boolean;
begin
  firstRec := PSearchRec(Key1);
  secondRec := PSearchRec(Key2);

  if CompareNames(firstRec^.Name, secondRec^.Name) = 0 then
  begin
    Result := 0;
    Exit;
  end;
  if firstRec^.Name = '..' then
  begin
    Result := 1;
    Exit;
  end;
  if secondRec^.Name = '..' then
  begin
    Result := -1;
    Exit;
  end;

  firstIsDir := (firstRec^.Attr and FA_DIREC) <> 0;
  secondIsDir := (secondRec^.Attr and FA_DIREC) <> 0;
  if firstIsDir and not secondIsDir then
  begin
    Result := 1;
    Exit;
  end;
  if secondIsDir and not firstIsDir then
  begin
    Result := -1;
    Exit;
  end;

  Result := CompareNames(firstRec^.Name, secondRec^.Name);
end;

procedure TFileCollection.FreeItem(Item: Pointer);
begin
  Dispose(PSearchRec(Item));
end;

function TFileCollection.At(Index: ccIndex): PSearchRec;
begin
  Result := PSearchRec(inherited At(Index));
end;

function TFileCollection.FirstThat(Test: ccTestFunc; Arg: Pointer): PSearchRec;
begin
  Result := PSearchRec(inherited FirstThat(Test, Arg));
end;

function TFileCollection.LastThat(Test: ccTestFunc; Arg: Pointer): PSearchRec;
begin
  Result := PSearchRec(inherited LastThat(Test, Arg));
end;

{ TSortedListBox }

constructor TSortedListBox.Create(const Bounds: TRect; NumberOfColumns: Word; VerticalBar: TScrollBar);
begin
  inherited Create(Bounds, NumberOfColumns, VerticalBar);
end;

procedure TSortedListBox.NewList(NewItems: TSortedCollection);
begin
  if not Assigned(SortedListBoxNewListHook) then
    Exit;
  SortedListBoxNewListHook(Self, NewItems);
end;

function TSortedListBox.List: TSortedCollection;
begin
  Result := TSortedCollection(inherited List);
end;

{ TFileList }

constructor TFileList.Create(const Bounds: TRect; AScrollBar: TScrollBar);
begin
  inherited Create(Bounds, 2, AScrollBar);
end;

destructor TFileList.Destroy;
begin
  if List <> nil then
    TvObject.DestroyObject(List);
  inherited Destroy;
end;

procedure TFileList.FocusItem(ItemIndex: SmallInt);
begin
  inherited FocusItem(ItemIndex);
  SendNotice(Owner, evBroadcast, cmFileFocused, List.At(ItemIndex));
end;

procedure TFileList.SelectItem(ItemIndex: SmallInt);
begin
  SendNotice(Owner, evBroadcast, cmFileDoubleClicked, List.At(ItemIndex));
end;

function TFileList.DataSize: Word;
begin
  Result := 0;
end;

procedure TFileList.GetData(Rec: Pointer);
begin
end;

procedure TFileList.SetData(Rec: Pointer);
begin
end;

function TFileList.GetKey(const S: string): Pointer;
var
  shiftHeld: Boolean;
begin
  shiftHeld := (ShiftState and kbShift) <> 0;
  if shiftHeld or BeginsWithDot(S) then
    SearchKey.Attr := FA_DIREC
  else
    SearchKey.Attr := 0;
  SearchKey.Name := S;
  Result := @SearchKey;
end;

function TFileList.GetText(ItemIndex, MaxLen: SmallInt): string;
var
  entry: PSearchRec;
begin
  entry := List.At(ItemIndex);
  Result := Copy(entry^.Name, 1, MaxLen);
  if (entry^.Attr and FA_DIREC) <> 0 then
    Result := Result + '\';
end;

procedure TFileList.NewList(NewItems: TFileCollection);
begin
  inherited NewList(NewItems);
end;

function TFileList.List: TFileCollection;
begin
  Result := TFileCollection(inherited List);
end;

procedure TFileList.ReadDirectory(const Dir, WildCard: string);
begin
  ReadDirectory(Dir + WildCard);
end;

procedure TFileList.ReadDirectory(const WildCard: string);
const
  FileMask = faReadOnly or faArchive or faHidden or faSymLink;
  DirectoryMask = faDirectory or faSymLink;
var
  entries: TFileCollection;
  found: SysUtils.TSearchRec;
  status: Integer;
  record_: PSearchRec;
  allocationFailed: Boolean;
  expandedPath, directoryPart, namePart, extensionPart: AnsiString;
  parentPath: string;
  isFile, isSubdirectory, hasEntries: Boolean;
begin
  entries := TFileCollection.Create(5, 5);
  allocationFailed := False;

  status := FindFirst(WildCard, FileMask, found);
  while (not allocationFailed) and (status = 0) do
  begin
    isFile := (found.Attr and faDirectory) = 0;
    if isFile then
    begin
      record_ := NewSearchRecord;
      allocationFailed := record_ = nil;
      if record_ <> nil then
      begin
        CopyFoundEntry(record_, found);
        entries.Insert(record_);
      end;
    end;
    status := FindNext(found);
  end;
  FindClose(found);

  expandedPath := PathExpand(WildCard);
  PathSplit(expandedPath, directoryPart, namePart, extensionPart);
  parentPath := directoryPart + '..';

  status := FindFirst(directoryPart + PathAllFiles, DirectoryMask, found);
  while (not allocationFailed) and (status = 0) do
  begin
    isSubdirectory := ((found.Attr and faDirectory) <> 0) and not BeginsWithDot(found.Name);
    if isSubdirectory then
    begin
      record_ := NewSearchRecord;
      allocationFailed := record_ = nil;
      if record_ <> nil then
      begin
        CopyFoundEntry(record_, found);
        entries.Insert(record_);
      end;
    end;
    status := FindNext(found);
  end;
  FindClose(found);

  if Length(directoryPart) > 1 then
  begin
    record_ := NewSearchRecord;
    allocationFailed := record_ = nil;
    if record_ <> nil then
    begin
      status := FindFirst(parentPath, faDirectory, found);
      if status = 0 then
      begin
        found.Name := '..';
        CopyFoundEntry(record_, found);
      end
      else
      begin
        record_^.Name := '..';
        record_^.Size := 0;
        record_^.Time := DefaultParentTime;
        record_^.Attr := FA_DIREC;
      end;
      FindClose(found);
      entries.Insert(record_);
    end;
  end;

  if allocationFailed then
    MessageBox(TooManyFiles, mfOKButton or mfWarning);
  NewList(entries);

  hasEntries := (List <> nil) and (List.GetCount > 0);
  if hasEntries then
    SendNotice(Owner, evBroadcast, cmFileFocused, List.At(0))
  else
    SendNotice(Owner, evBroadcast, cmFileFocused, @NoFileRecord);
end;

{ TDirEntry }

constructor TDirEntry.Create(const ShownText, DirectoryPath: string);
begin
  inherited Create;
  DisplayText := NewStr(ShownText);
  Directory := NewStr(DirectoryPath);
end;

destructor TDirEntry.Destroy;
begin
  FreeMem(DisplayText);
  FreeMem(Directory);
  inherited Destroy;
end;

function TDirEntry.Dir: PAnsiChar;
begin
  Result := Directory;
end;

function TDirEntry.Text: PAnsiChar;
begin
  Result := DisplayText;
end;

{ TDirCollection }

procedure TDirCollection.FreeItem(Item: Pointer);
begin
  TDirEntry(Item).Free;
end;

function TDirCollection.At(Index: ccIndex): TDirEntry;
begin
  Result := TDirEntry(inherited At(Index));
end;

function TDirCollection.FirstThat(Test: ccTestFunc; Arg: Pointer): TDirEntry;
begin
  Result := TDirEntry(inherited FirstThat(Test, Arg));
end;

function TDirCollection.LastThat(Test: ccTestFunc; Arg: Pointer): TDirEntry;
begin
  Result := TDirEntry(inherited LastThat(Test, Arg));
end;

{ TDirListBox }

constructor TDirListBox.Create(const Bounds: TRect; AScrollBar: TScrollBar);
begin
  inherited Create(Bounds, 1, AScrollBar);
  Cur := 0;
  Dir := '';
end;

destructor TDirListBox.Destroy;
begin
  if List <> nil then
    TvObject.DestroyObject(List);
  inherited Destroy;
end;

function TDirListBox.GetText(ItemIndex, MaxLen: SmallInt): string;
var
  source: PAnsiChar;
  textLength: Integer;
begin
  source := List.At(ItemIndex).Text;
  textLength := 0;
  while (textLength < MaxLen) and (source[textLength] <> #0) do
    Inc(textLength);
  SetString(Result, source, textLength);
end;

procedure TDirListBox.SelectItem(ItemIndex: SmallInt);
begin
  SendNotice(Owner, evCommand, cmChangeDir, List.At(ItemIndex));
end;

function TDirListBox.IsSelected(ItemIndex: SmallInt): Boolean;
begin
  Result := ItemIndex = Integer(Cur);
end;

procedure TDirListBox.ShowDrives(Dirs: TDirCollection);
var
  isFirst: Boolean;
  previousRoot, decoration: string;
  letter: Char;
begin
  isFirst := True;
  previousRoot := '0:\';
  for letter := 'A' to 'Z' do
  begin
    if (letter < 'C') or DriveValid(letter) then
    begin
      if previousRoot[1] <> '0' then
      begin
        if isFirst then
        begin
          decoration := FirstDir;
          isFirst := False;
        end
        else
          decoration := MiddleDir;
        Dirs.Insert(TDirEntry.Create(decoration + previousRoot[1], previousRoot));
      end;
      if letter = Chr(GetDisk + Ord('A')) then
        Cur := Dirs.GetCount;
      previousRoot[1] := letter;
    end;
  end;
  if previousRoot[1] <> '0' then
    Dirs.Insert(TDirEntry.Create(LastDir + previousRoot[1], previousRoot));
end;

procedure TDirListBox.ShowDirs(Dirs: TDirCollection);
var
  indentWidth, rootEnd, scanStart, separatorPos, lastSeparator, status: Integer;
  component, listingBase, decoration: string;
  isFirst, isSubdirectory: Boolean;
  found: SysUtils.TSearchRec;
  lastText, markPos: PAnsiChar;
begin
  indentWidth := IndentStep;

  rootEnd := FindSeparator(Dir, 1);
  if rootEnd = 0 then
    Exit;
  Dirs.Insert(TDirEntry.Create(PathDir + Copy(Dir, 1, rootEnd), Copy(Dir, 1, rootEnd)));

  scanStart := rootEnd + 1;
  separatorPos := FindSeparator(Dir, scanStart);
  while separatorPos <> 0 do
  begin
    component := Copy(Dir, scanStart, separatorPos - scanStart);
    Dirs.Insert(TDirEntry.Create(StringOfChar(' ', indentWidth) + PathDir + component,
      Copy(Dir, 1, separatorPos - 1)));
    scanStart := separatorPos + 1;
    Inc(indentWidth, IndentStep);
    separatorPos := FindSeparator(Dir, scanStart);
  end;

  Cur := Dirs.GetCount - 1;

  lastSeparator := FindLastSeparator(Dir);
  listingBase := Copy(Dir, 1, lastSeparator);

  isFirst := True;
  status := FindFirst(listingBase + PathAllFiles, faDirectory or faSymLink, found);
  while status = 0 do
  begin
    isSubdirectory := ((found.Attr and faDirectory) <> 0) and not BeginsWithDot(found.Name);
    if isSubdirectory then
    begin
      if isFirst then
      begin
        decoration := FirstDir;
        isFirst := False;
      end
      else
        decoration := MiddleDir;
      Dirs.Insert(TDirEntry.Create(StringOfChar(' ', indentWidth) + decoration + found.Name,
        listingBase + found.Name));
    end;
    status := FindNext(found);
  end;
  FindClose(found);

  lastText := Dirs.At(Dirs.GetCount - 1).Text;
  markPos := FindCode(lastText, Graphics[1]);
  if markPos = nil then
  begin
    markPos := FindCode(lastText, Graphics[2]);
    if markPos <> nil then
      markPos^ := Graphics[1];
  end
  else
  begin
    markPos[1] := Graphics[3];
    markPos[2] := Graphics[3];
  end;
end;

procedure TDirListBox.NewDirectory(const Path: string);
var
  dirs: TDirCollection;
begin
  Dir := Path;
  dirs := TDirCollection.Create(5, 5);
  if Path = Drives then
    ShowDrives(dirs)
  else
    ShowDirs(dirs);
  NewList(dirs);
  FocusItem(SmallInt(Cur));
end;

procedure TDirListBox.SetState(StateBits: Word; TurnOn: Boolean);
begin
  inherited SetState(StateBits, TurnOn);
  if (StateBits and sfFocused) = 0 then
    Exit;
  if not Assigned(ChDirButtonDefaultHook) then
    Exit;
  ChDirButtonDefaultHook(Self, TurnOn);
end;

function TDirListBox.List: TDirCollection;
begin
  Result := TDirCollection(inherited List);
end;

initialization
  TFileList.TooManyFiles := '';
  TDirListBox.PathDir := #$C0#$C4#$C2;
  TDirListBox.FirstDir := #$C0#$C2#$C4;
  TDirListBox.MiddleDir := ' '#$C3#$C4;
  TDirListBox.LastDir := ' '#$C0#$C4;
  TDirListBox.Drives := 'Drives';
  TDirListBox.Graphics := #$C0#$C3#$C4;

end.
