{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (the commands of the file dialogs, TSearchRec, TFileCollection,
  TSortedListBox, TFileList, TDirEntry, TDirCollection, TDirListBox), source/tvision/stddlg.cpp (TSortedListBox),
  source/tvision/tfilecol.cpp, source/tvision/tfillist.cpp, source/tvision/tdircoll.cpp, source/tvision/tdirlist.cpp,
  source/platform/dir.cpp, source/tvision/tvtext1.cpp (the tables of TDirListBox), include/tvision/ttypes.h,
  include/tvision/config.h, include/tvision/tv.h, include/tvision/views.h, include/tvision/util.h,
  source/tvision/misc.cpp, source/tvision/tvtext2.cpp
  See COPYRIGHT.magiblot.

  Test program of the unit TvFiles.

  The views have no screen. A view whose messages a test looks at is in a group that counts the events that it gets
  and remembers the last one. The incremental search of the sorted list box is checked with the keys that the test
  gives to a list of files, and with a list of texts that has the default key; the position of the cursor of the list
  box after each key is the one that the arithmetic of handleEvent gives. The tests that touch files make a directory
  of their own under the directory of temporary files and remove it at the end. The directory of the tests has the
  files a.txt (5 bytes), b.txt, c.dat (3 bytes), the directories sub1 and sub2 and the hidden directory .hdir. }
program t_files;

{$mode objfpc}

uses
  SysUtils, TvGeom, TvKeys, TvEvents, TvObjs, TvViews, TvList, TvUtil, TvFiles;

{$I testlib.inc}

type
  { A collection of files that counts its destruction. }
  TCountedFiles = class(TFileCollection)
  public
    destructor Destroy; override;
  end;

  { A collection of directories that counts its destruction. }
  TCountedDirs = class(TDirCollection)
  public
    destructor Destroy; override;
  end;

  { A collection of files that gives the comparison of its items. }
  TFileProbe = class(TFileCollection)
  public
    function Cmp(First, Second: PSearchRec): Integer;
  end;

  { A file list that gives its key and sets its shift state. }
  TListProbe = class(TFileList)
  public
    procedure SetShift(Value: Byte);
    function Shift: Byte;
    function Key(const Text: string): PSearchRec;
  end;

  { A sorted collection of blocks of characters, in the order of the text without regard to the case. }
  TTextCollection = class(TSortedCollection)
  protected
    function Compare(Key1, Key2: Pointer): Integer; override;
    procedure FreeItem(Item: Pointer); override;
  end;

  { A sorted list box over a TTextCollection: it keeps the key of the base class. }
  TTextBox = class(TSortedListBox)
  public
    function Shift: Byte;
  end;

  { A group that counts the events that it gets, and remembers the last one: the messages of the views that it holds. }
  TProbeGroup = class(TGroup)
  public
    procedure HandleEvent(var Event: TEvent); override;
  end;

var
  MessageCount: Integer;
  FocusedCount: Integer;
  LastReceiver: TView;
  LastWhat: Word;
  LastCommand: Word;
  LastInfo: Pointer;
  FilesDestroyed: Integer;
  DirsDestroyed: Integer;
  DefaultCalls: Integer;
  DefaultBox: TDirListBox;
  DefaultEnable: Boolean;
  TempRoot: string;

destructor TCountedFiles.Destroy;
begin
  Inc(FilesDestroyed);
  inherited Destroy;
end;

destructor TCountedDirs.Destroy;
begin
  Inc(DirsDestroyed);
  inherited Destroy;
end;

function TFileProbe.Cmp(First, Second: PSearchRec): Integer;
begin
  Result := Compare(First, Second);
end;

procedure TListProbe.SetShift(Value: Byte);
begin
  ShiftState := Value;
end;

function TListProbe.Shift: Byte;
begin
  Result := ShiftState;
end;

function TListProbe.Key(const Text: string): PSearchRec;
begin
  Result := PSearchRec(GetKey(Text));
end;

function TTextCollection.Compare(Key1, Key2: Pointer): Integer;
begin
  Result := CompareText(string(PAnsiChar(Key1)), string(PAnsiChar(Key2)));
end;

procedure TTextCollection.FreeItem(Item: Pointer);
begin
  FreeMem(Item);
end;

function TTextBox.Shift: Byte;
begin
  Result := ShiftState;
end;

procedure TProbeGroup.HandleEvent(var Event: TEvent);
begin
  Inc(MessageCount);
  if Event.Message.Command = cmFileFocused then
    Inc(FocusedCount);
  LastReceiver := Self;
  LastWhat := Event.What;
  LastCommand := Event.Message.Command;
  LastInfo := Event.Message.InfoPtr;
  inherited HandleEvent(Event);
end;

procedure OnDefault(Box: TDirListBox; Enable: Boolean);
begin
  Inc(DefaultCalls);
  DefaultBox := Box;
  DefaultEnable := Enable;
end;

function IsDirectoryItem(Item, Arg: Pointer): Boolean;
begin
  Result := (PSearchRec(Item)^.Attr and FA_DIREC) <> 0;
end;

function IsSecondEntry(Item, Arg: Pointer): Boolean;
begin
  Result := string(TDirEntry(Item).Text) = 'two';
end;

function Rc: TRect;
begin
  Result := TRect.Create(0, 0, 30, 8);
end;

function MakeRec(const AName: string; AAttr: Byte; ASize: LongInt): PSearchRec;
begin
  New(Result);
  Result^.Attr := AAttr;
  Result^.Time := 0;
  Result^.Size := ASize;
  Result^.Name := AName;
end;

function CountSeps(const S: string): Integer;
var
  Rest: string;
  SepAt: Integer;
begin
  Rest := S;
  Result := 0;
  SepAt := Pos('/', Rest);
  while SepAt > 0 do
  begin
    Inc(Result);
    Delete(Rest, 1, SepAt);
    SepAt := Pos('/', Rest);
  end;
end;

procedure MakeFile(const Path: string; Bytes: Integer);
var
  Handle: THandle;
  Buffer: array[0..63] of Byte;
begin
  Handle := FileCreate(Path);
  FillChar(Buffer, SizeOf(Buffer), 65);
  if Bytes > 0 then
    FileWrite(Handle, Buffer, Bytes);
  FileClose(Handle);
end;

procedure RemoveTree(const Path: string);
var
  Found: SysUtils.TSearchRec;
  Status: Integer;
begin
  Status := FindFirst(Path + '*', faAnyFile, Found);
  while Status = 0 do
  begin
    if (Found.Name <> '.') and (Found.Name <> '..') then
    begin
      if (Found.Attr and faDirectory) <> 0 then
        RemoveTree(Path + Found.Name + '/')
      else
        DeleteFile(Path + Found.Name);
    end;
    Status := FindNext(Found);
  end;
  FindClose(Found);
  RemoveDir(Path);
end;

procedure MakeTree;
begin
  TempRoot := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tvfiles_' + IntToStr(GetProcessID) + '/';
  RemoveTree(TempRoot);
  ForceDirectories(TempRoot + 'a/b/s1');
  ForceDirectories(TempRoot + 'a/b/s2');
  ForceDirectories(TempRoot + 'a/b/.hid');
  MakeFile(TempRoot + 'a/b/x.txt', 1);
  ForceDirectories(TempRoot + 'rd/sub1');
  ForceDirectories(TempRoot + 'rd/sub2');
  ForceDirectories(TempRoot + 'rd/.hdir');
  MakeFile(TempRoot + 'rd/a.txt', 5);
  MakeFile(TempRoot + 'rd/b.txt', 0);
  MakeFile(TempRoot + 'rd/c.dat', 3);
end;

procedure TestConstants;
begin
  Check(FA_RDONLY = faReadOnly, 'FA_RDONLY is the read-only attribute');
  Check(FA_DIREC = faDirectory, 'FA_DIREC is the directory attribute');
  Check(FA_ARCH = faArchive, 'FA_ARCH is the archive attribute');
  Check((cmFileOpen = 1001) and (cmFileReplace = 1002) and (cmFileClear = 1003) and (cmFileInit = 1004) and
    (cmChangeDir = 1005) and (cmRevert = 1006), 'the commands of the file dialogs');
  Check((cmFileFocused = 102) and (cmFileDoubleClicked = 103), 'the messages of a file list');
  Check(MaxNameLength = 255, 'the longest name of a TSearchRec');
  Check(TDirListBox.PathDir = #$C0#$C4#$C2, 'pathDir');
  Check(TDirListBox.FirstDir = #$C0#$C2#$C4, 'firstDir');
  Check(TDirListBox.MiddleDir = ' '#$C3#$C4, 'middleDir');
  Check(TDirListBox.LastDir = ' '#$C0#$C4, 'lastDir');
  Check(TDirListBox.Drives = 'Drives', 'drives');
  Check(TDirListBox.Graphics = #$C0#$C3#$C4, 'graphics');
  Check(TFileList.TooManyFiles = 'Too many files.', 'tooManyFiles is the text of the C++');
end;

procedure TestFunctions;
begin
  Check(GetDisk = 2, 'getdisk is the disk C');
  Check(DriveValid('C'), 'the current disk is valid');
  Check(not DriveValid('A') and not DriveValid('B'), 'the disks A and B are not valid, only the current disk is');
  Check(not DriveValid('D') and not DriveValid('Z'), 'the other disks are not valid');

  Check(IsWild('a*'), 'a name with * is wild');
  Check(IsWild('a?b'), 'a name with ? is wild');
  Check(IsWild('*'), 'the name * is wild');
  Check(not IsWild('abc.txt'), 'a name without wild cards is not wild');
  Check(not IsWild(''), 'an empty name is not wild');

  Check(IsDir(TempRoot + 'a'), 'IsDir of a directory');
  Check(not IsDir(TempRoot + 'a/b/x.txt'), 'IsDir of a file');
  Check(not IsDir(TempRoot + 'zzz'), 'IsDir of a name that does not exist');

  Check(PathValid(TempRoot + 'a/b'), 'PathValid of a directory');
  Check(PathValid(TempRoot + 'a/b/'), 'PathValid of a directory with a separator at the end');
  Check(PathValid('/'), 'PathValid of the root');
  Check(not PathValid(TempRoot + 'a/b/x.txt'), 'PathValid of a file');
  Check(not PathValid(TempRoot + 'zzz/'), 'PathValid of a directory that does not exist');
end;

procedure TestValidFileName;
begin
  Check(ValidFileName('plain.txt'), 'a name with no directory is valid');
  Check(ValidFileName(''), 'the empty name is valid');
  Check(ValidFileName(TempRoot + 'a/b/new.txt'), 'a new name in a directory that exists is valid');
  Check(ValidFileName(TempRoot + 'a/b/x.txt'), 'the name of a file that exists is valid');
  Check(ValidFileName(TempRoot + 'a/b/'), 'a directory with no name is valid');
  Check(not ValidFileName(TempRoot + 'zzz/new.txt'), 'a name in a directory that does not exist is not valid');
  Check(not ValidFileName(TempRoot + 'a/b/x.txt/new.txt'), 'a name in a file that is taken for a directory is not valid');
  Check(ValidFileName('/new.txt'), 'a name in the root is valid');

  Check(not ValidFileName('a<b'), 'the character < is not allowed in a name');
  Check(not ValidFileName('a>b'), 'the character > is not allowed in a name');
  Check(not ValidFileName('a|b'), 'the character | is not allowed in a name');
  Check(not ValidFileName('a"b'), 'the character " is not allowed in a name');
  Check(not ValidFileName('file.t<t'), 'the character < is not allowed in an extension');
  Check(not ValidFileName('file.t|t'), 'the character | is not allowed in an extension');
  Check(not ValidFileName('file.t"t'), 'the character " is not allowed in an extension');
  Check(not ValidFileName(TempRoot + 'a/b/we|rd.txt'), 'a bad character is found after a directory that exists');
  Check(not ValidFileName('no\such\name'), 'a backslash ends the directory, which does not exist');

  Check(ValidFileName('a b;c,d=e+f[g].txt'), 'a space and the characters ; , = + [ ] are allowed');
  Check(ValidFileName('name.tar.gz'), 'a name with two dots is valid');
  Check(ValidFileName('.hidden'), 'a name that begins with a dot is valid');
  Check(ValidFileName('a*b'), 'a wild card is valid');
  Check(ValidFileName('noext.'), 'a name that ends with a dot is valid');
  Check(ValidFileName(TempRoot + 'a/b/..'), 'a path that ends with .. is a directory that exists');
  Check(ValidFileName(TempRoot + 'a/b/.'), 'a path that ends with . is a directory that exists');
  Check(not ValidFileName(TempRoot + 'zzz/q/..'), 'a path that ends with .. and leads to a missing directory is not valid');
end;

procedure TestGetCurDir;
var
  SavedDir, Expected: string;
begin
  SavedDir := GetCurrentDir;
  Check(SetCurrentDir(TempRoot + 'a/b'), 'the directory a/b of the tests exists');
  Expected := IncludeTrailingPathDelimiter(GetCurrentDir);
  Check(GetCurDir = Expected, 'the current directory ends with a separator');
  Check((Length(Expected) > 1) and (Expected[1] = '/') and (Expected[Length(Expected)] = '/'),
    'the current directory begins and ends with a separator');
  Check(GetCurDir(GetDisk) = Expected, 'the current disk gives the current directory');
  Check(GetCurDir(-1) = Expected, 'the value -1 stands for the current disk');
  Check(GetCurDir(26) = Expected, 'a value above Z stands for the current disk');
  Check(GetCurDir(200) = Expected, 'a large value stands for the current disk');
  Check(GetCurDir(0) = '/', 'a disk that is not the current one gives the root');
  Check(GetCurDir(25) = '/', 'the disk Z gives the root');

  Check(SetCurrentDir(TempRoot + 'rd'), 'the directory rd of the tests exists');
  Expected := IncludeTrailingPathDelimiter(GetCurrentDir);
  Check(GetCurDir = Expected, 'the current directory follows the change of directory');
  Check(PathValid(GetCurDir), 'the current directory is valid');

  Check(SetCurrentDir('/'), 'the root exists');
  Check(GetCurDir = '/', 'the root has no separator after the one that it is');
  SetCurrentDir(SavedDir);
  Check(GetCurrentDir = SavedDir, 'the directory is restored');
end;

procedure TestFileCollection;
var
  Items: TFileProbe;
  FileA, FileA2, FileB, Zed, Upper, Prefix, PrefixLong, HighByte, DirC, DirD, Parent, Parent2: PSearchRec;
  Dup: PSearchRec;
  Found: PSearchRec;
begin
  Items := TFileProbe.Create(5, 5);
  FileA := MakeRec('a', 0, 1);
  FileA2 := MakeRec('a', FA_DIREC, 2);
  FileB := MakeRec('b', 0, 1);
  Zed := MakeRec('z', 0, 1);
  Upper := MakeRec('Z', 0, 1);
  Prefix := MakeRec('ab', 0, 1);
  PrefixLong := MakeRec('abc', 0, 1);
  HighByte := MakeRec(#$C3, 0, 1);
  DirC := MakeRec('c', FA_DIREC, 0);
  DirD := MakeRec('d', FA_DIREC, 0);
  Parent := MakeRec('..', FA_DIREC, 0);
  Parent2 := MakeRec('..', 0, 0);

  Check(Items.Cmp(FileA, FileA2) = 0, 'equal names are equal even when the attributes differ');
  Check(Items.Cmp(Parent, Parent2) = 0, 'two entries .. are equal');
  Check(Items.Cmp(FileA, FileB) < 0, 'a is before b');
  Check(Items.Cmp(FileB, FileA) > 0, 'b is after a');
  Check(Items.Cmp(Upper, FileA) < 0, 'Z is before a');
  Check(Items.Cmp(Prefix, PrefixLong) < 0, 'a name that begins another is the smaller');
  Check(Items.Cmp(PrefixLong, Prefix) > 0, 'a name that is begun by another is the larger');
  Check(Items.Cmp(Zed, HighByte) < 0, 'the bytes of a name are compared as unsigned');
  Check(Items.Cmp(HighByte, Zed) > 0, 'the bytes of a name are compared as unsigned, the other way');
  Check(Items.Cmp(Parent, FileA) = 1, '.. is after a file');
  Check(Items.Cmp(FileA, Parent) = -1, 'a file is before ..');
  Check(Items.Cmp(Parent, DirC) = 1, '.. is after a directory');
  Check(Items.Cmp(DirC, Parent) = -1, 'a directory is before ..');
  Check(Items.Cmp(DirC, FileB) = 1, 'a directory is after a file');
  Check(Items.Cmp(FileB, DirC) = -1, 'a file is before a directory');
  Check(Items.Cmp(DirC, DirD) < 0, 'two directories are in the order of the names');
  Check(Items.Cmp(DirD, DirC) > 0, 'two directories are in the order of the names, the other way');

  Dispose(FileA);
  Dispose(FileA2);
  Dispose(FileB);
  Dispose(Zed);
  Dispose(Upper);
  Dispose(Prefix);
  Dispose(PrefixLong);
  Dispose(HighByte);
  Dispose(DirC);
  Dispose(DirD);
  Dispose(Parent);
  Dispose(Parent2);

  Items.Insert(MakeRec('b.txt', 0, 1));
  Items.Insert(MakeRec('a.txt', 0, 2));
  Items.Insert(MakeRec('zdir', FA_DIREC, 0));
  Items.Insert(MakeRec('adir', FA_DIREC, 0));
  Items.Insert(MakeRec('..', FA_DIREC, 0));
  Items.Insert(MakeRec('B.txt', 0, 3));
  Dup := MakeRec('b.txt', FA_DIREC, 9);
  Items.Insert(Dup);
  Check(Items.GetCount = 6, 'an item with the name of another is not inserted');
  Dispose(Dup);

  Check(Items.At(0)^.Name = 'B.txt', 'the first item is B.txt');
  Check(Items.At(1)^.Name = 'a.txt', 'the second item is a.txt');
  Check(Items.At(2)^.Name = 'b.txt', 'the third item is b.txt');
  Check(Items.At(3)^.Name = 'adir', 'the fourth item is adir');
  Check(Items.At(4)^.Name = 'zdir', 'the fifth item is zdir');
  Check(Items.At(5)^.Name = '..', 'the last item is ..');
  Check(Items.At(2)^.Size = 1, 'the item b.txt that was inserted is the one that stays');

  Found := Items.FirstThat(@IsDirectoryItem, nil);
  Check((Found <> nil) and (Found^.Name = 'adir'), 'FirstThat gives the first directory');
  Found := Items.LastThat(@IsDirectoryItem, nil);
  Check((Found <> nil) and (Found^.Name = '..'), 'LastThat gives the last directory');

  TvObject.DestroyObject(Items);
end;

procedure TestDirEntry;
var
  Entry: TDirEntry;
  Empty: TDirEntry;
  First: PAnsiChar;
begin
  Entry := TDirEntry.Create('shown', '/x/y');
  Check(string(Entry.Text) = 'shown', 'the text of an entry');
  Check(string(Entry.Dir) = '/x/y', 'the directory of an entry');
  Check(Entry.Text <> Entry.Dir, 'the text and the directory are two blocks');
  First := Entry.Text;
  First[0] := 'S';
  Check(string(Entry.Text) = 'Shown', 'the text of an entry can be changed in place');
  Entry.Free;

  Empty := TDirEntry.Create('', '');
  Check((Empty.Text^ = #0) and (Empty.Dir^ = #0), 'an entry with empty texts');
  Empty.Free;
end;

procedure TestDirCollection;
var
  Dirs: TCountedDirs;
  Found: TDirEntry;
begin
  DirsDestroyed := 0;
  Dirs := TCountedDirs.Create(2, 2);
  Dirs.Insert(TDirEntry.Create('one', '/1'));
  Dirs.Insert(TDirEntry.Create('two', '/2'));
  Dirs.Insert(TDirEntry.Create('three', '/3'));
  Check(Dirs.GetCount = 3, 'a collection of directories is not sorted and keeps its items');
  Check(string(Dirs.At(0).Text) = 'one', 'the first entry is the first inserted');
  Check(string(Dirs.At(2).Dir) = '/3', 'the third entry is the last inserted');
  Found := Dirs.FirstThat(@IsSecondEntry, nil);
  Check(Found = Dirs.At(1), 'FirstThat gives the entry two');
  Found := Dirs.LastThat(@IsSecondEntry, nil);
  Check(Found = Dirs.At(1), 'LastThat gives the entry two');
  TvObject.DestroyObject(Dirs);
  Check(DirsDestroyed = 1, 'the collection of directories is destroyed');
end;

procedure TestFileListBasics;
var
  List: TListProbe;
  Spare: TFileCollection;
  Probe: LongInt;
  Key1, Key2, Key3: PSearchRec;
begin
  List := TListProbe.Create(Rc, nil);
  Check(List.NumCols = 2, 'a file list has two columns');
  Check(List.Range = 0, 'a new file list has no item');
  Check(List.List = nil, 'a new file list has no list');
  Check(List.DataSize = 0, 'the data of a file list has no size');
  Probe := 77;
  List.GetData(@Probe);
  Check(Probe = 77, 'GetData of a file list changes nothing');
  List.SetData(@Probe);
  Check(Probe = 77, 'SetData of a file list changes nothing');

  Spare := TFileCollection.Create(5, 5);
  Spare.Insert(MakeRec('f', 0, 0));
  List.NewList(Spare);
  Check(List.List = Spare, 'NewList of a sorted list box takes the list');
  Check((List.Range = 1) and (List.Focused = 0), 'NewList sets the range and focuses the first item');

  Check(List.Shift = 0, 'the shift state of a new sorted list box is 0');
  Check((List.Cursor.X = 1) and (List.Cursor.Y = 0), 'the cursor of a sorted list box is at 1, 0');
  Check((List.State and sfCursorVis) <> 0, 'the cursor of a sorted list box is shown');

  Key1 := List.Key('abc');
  Check((Key1^.Attr = 0) and (Key1^.Name = 'abc'), 'the key of a name');
  Key2 := List.Key('.x');
  Check((Key2^.Attr = FA_DIREC) and (Key2^.Name = '.x'), 'the key of a name that begins with a dot is a directory');
  Key3 := List.Key('');
  Check((Key3^.Attr = 0) and (Key3^.Name = ''), 'the key of an empty name');
  Check((Key1 = Key2) and (Key2 = Key3), 'the key is one record');
  List.SetShift(kbLeftShift);
  Key1 := List.Key('abc');
  Check(Key1^.Attr = FA_DIREC, 'the key with the shift key down is a directory');
  List.SetShift(kbRightShift);
  Check(List.Key('abc')^.Attr = FA_DIREC, 'the key with the right shift key down is a directory');
  List.SetShift(0);
  Check(List.Key('abc')^.Attr = 0, 'the key with no shift key is a file');
  Check(Length(List.Key(StringOfChar('n', 300))^.Name) = MaxNameLength, 'a long name of a key is cut');
  TvObject.DestroyObject(List);
end;

{ A key down event of the character Ch, with the control keys State. }
function CharEvent(Ch: Char; State: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Word(Ord(Ch));
  Result.KeyDown.ControlKeyState := State;
end;

{ A broadcast of the command Cmd. }
function BroadcastEvent(Cmd: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evBroadcast;
  Result.Message.Command := Cmd;
end;

{ A key down event of a key code. }
function CodeEvent(Code: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Code;
end;

{ A list of files whose entries are, in order: a.txt, alpha, beta, betamax, gamma, the directory dir1 and the
  parent. }
function MakeSearchList: TFileCollection;
begin
  Result := TFileCollection.Create(10, 5);
  Result.Insert(MakeRec('gamma', 0, 1));
  Result.Insert(MakeRec('beta', 0, 1));
  Result.Insert(MakeRec('a.txt', 0, 1));
  Result.Insert(MakeRec('betamax', 0, 1));
  Result.Insert(MakeRec('alpha', 0, 1));
  Result.Insert(MakeRec('..', FA_DIREC, 0));
  Result.Insert(MakeRec('dir1', FA_DIREC, 0));
end;

procedure TestSearchOfFileList;
var
  List: TListProbe;
  Probe: TProbeGroup;
  Ev: TEvent;
begin
  Probe := TProbeGroup.Create(Rc);
  List := TListProbe.Create(Rc, nil);
  Probe.Insert(List);
  List.NewList(MakeSearchList);
  Check((List.Range = 7) and (List.Focused = 0), 'the search list has seven entries and the first is focused');
  Check(List.List.At(0)^.Name = 'a.txt', 'the entries start with a.txt');
  Check((List.List.At(4)^.Name = 'gamma') and (List.List.At(5)^.Name = 'dir1') and (List.List.At(6)^.Name = '..'),
    'the entries end with gamma, dir1 and the parent');

  Ev := CharEvent('b', 0);
  List.HandleEvent(Ev);
  Check(Ev.What = evNothing, 'a letter that moves the focus is taken');
  Check(List.Focused = 2, 'the letter b focuses beta');
  Check(List.Cursor.X = 2, 'the cursor moves by the length of the text after a change of the focus');
  Ev := CharEvent('e', 0);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 2), 'the letter e keeps beta focused');
  Check(List.Cursor.X = 3, 'the cursor moves by one when the focus stays');
  Ev := CharEvent('t', 0);
  List.HandleEvent(Ev);
  Ev := CharEvent('a', 0);
  List.HandleEvent(Ev);
  Check((List.Focused = 2) and (List.Cursor.X = 5), 'the letters t and a keep beta focused and move the cursor');
  Ev := CharEvent('m', 0);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 3), 'the letter m focuses betamax');
  Check(List.Cursor.X = 10, 'the cursor of a change of the focus moves by the position in the text plus one');

  Ev := CharEvent('z', 0);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 3) and (List.Cursor.X = 10),
    'a letter with no match is taken and changes nothing');
  Ev := CharEvent('#', 0);
  List.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (List.Focused = 3) and (List.Cursor.X = 10),
    'a character that is not a letter and has no match is left in the event');

  Ev := CodeEvent(kbBack);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 2) and (List.Cursor.X = 14),
    'Backspace shortens the text and focuses the first entry that begins with it');
  Ev := CodeEvent(kbBack);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 2) and (List.Cursor.X = 13),
    'Backspace moves the cursor back by one when the focus stays');
  Ev := CodeEvent(kbBack);
  List.HandleEvent(Ev);
  Ev := CodeEvent(kbBack);
  List.HandleEvent(Ev);
  Check((List.Focused = 2) and (List.Cursor.X = 11), 'two more Backspace keys leave the text b');
  Ev := CodeEvent(kbBack);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 0) and (List.Cursor.X = 11),
    'the last Backspace gives the empty text, which focuses the first entry');
  Ev := CodeEvent(kbBack);
  List.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (List.Focused = 0) and (List.Cursor.X = 11),
    'Backspace with no text is left in the event');

  Ev := CharEvent('.', 0);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 0) and (List.Cursor.X = 13),
    'the dot of the text of the focused entry sets the position of the dot');
  Ev := CharEvent('.', 0);
  List.HandleEvent(Ev);
  Check((List.Focused = 0) and (List.Cursor.X = 13) and (Ev.What = evKeyDown),
    'the dot again finds the same position and is left in the event');

  List.FocusItem(1);
  Ev := CharEvent('.', 0);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 1) and (List.Cursor.X = 11),
    'a dot with no dot in the text of the focused entry sets the position -1 and is taken');

  Ev := CharEvent('g', 0);
  List.HandleEvent(Ev);
  Check((List.Focused = 4) and (List.Cursor.X = 12), 'the letter g starts a search that focuses gamma');
  Ev := CodeEvent(kbDown);
  List.HandleEvent(Ev);
  Check(List.Focused = 5, 'the key Down moves the focus to the directory');
  Ev := CharEvent('a', 0);
  List.HandleEvent(Ev);
  Check((List.Focused = 0) and (List.Cursor.X = 13), 'a change of the focus ends the search: the next letter starts a new one');

  Ev := BroadcastEvent(cmReleasedFocus);
  List.HandleEvent(Ev);
  Check(Ev.What = evBroadcast, 'the message of the released focus is not taken');
  Ev := CharEvent('b', 0);
  List.HandleEvent(Ev);
  Check((List.Focused = 2) and (List.Cursor.X = 14), 'the message of the released focus ends the search');

  List.NewList(MakeSearchList);
  Check(List.Focused = 0, 'a new list focuses the first entry');
  Ev := CharEvent('b', 0);
  List.HandleEvent(Ev);
  Check((List.Focused = 2) and (List.Cursor.X = 15), 'a new list ends the search');

  List.NewList(MakeSearchList);
  Ev := CharEvent('d', kbLeftShift);
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Focused = 5), 'the letter d with the shift key down looks for a directory');
  Check(List.Shift = kbLeftShift, 'the first letter of a search takes the shift state of its event');
  Ev := CodeEvent(kbBack);
  Ev.KeyDown.ControlKeyState := kbRightShift;
  List.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (List.Shift = kbRightShift),
    'Backspace to the empty text takes the shift state of its event');
  Ev := CharEvent('d', 0);
  List.HandleEvent(Ev);
  Check((List.Shift = 0) and (List.Focused = 5), 'the shift state of a search without the shift key is 0');

  TvObject.DestroyObject(Probe);

  List := TListProbe.Create(Rc, nil);
  Ev := CharEvent('a', 0);
  List.HandleEvent(Ev);
  Check((Ev.What = evKeyDown) and (List.Focused = 0), 'a letter given to a list box that has no list is left in the event');
  TvObject.DestroyObject(List);
end;

procedure TestSearchOfTexts;
var
  Box: TTextBox;
  Texts: TTextCollection;
  Ev: TEvent;
begin
  Box := TTextBox.Create(Rc, 1, nil);
  Texts := TTextCollection.Create(5, 5);
  Texts.Insert(NewStr('date'));
  Texts.Insert(NewStr('cherry'));
  Texts.Insert(NewStr('apple'));
  Texts.Insert(NewStr('Banana'));
  Box.NewList(Texts);
  Check((Box.Range = 4) and (Box.Focused = 0) and (Box.List = Texts), 'the list of texts has four entries');
  Check(Box.GetText(1, 100) = 'Banana', 'the second entry is Banana');

  Ev := CharEvent('c', 0);
  Box.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Box.Focused = 2) and (Box.Cursor.X = 2),
    'the key of the base class is the text: c focuses cherry');
  Ev := CharEvent('H', 0);
  Box.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Box.Focused = 2) and (Box.Cursor.X = 3),
    'the letters are compared without regard to the case');
  Ev := CharEvent('x', 0);
  Box.HandleEvent(Ev);
  Check((Ev.What = evNothing) and (Box.Focused = 2) and (Box.Cursor.X = 3), 'a letter with no match changes nothing');
  Check(Box.Shift = 0, 'the shift state of the search is 0');

  Texts := TTextCollection.Create(5, 5);
  Texts.Insert(NewStr('apple'));
  Texts.Insert(NewStr('Banana'));
  Box.NewList(Texts);
  Ev := CharEvent('B', 0);
  Box.HandleEvent(Ev);
  Check((Box.Focused = 1) and (Ev.What = evNothing), 'an upper case letter finds Banana');
  TvObject.DestroyObject(Box.List);
  TvObject.DestroyObject(Box);
end;

procedure TestFileListDirectory;
var
  List: TListProbe;
  Probe: TProbeGroup;
  Counted: TCountedFiles;
  Index: ccIndex;
  Found: Boolean;
  Parent: PSearchRec;
  Names: string;
  I: Integer;
  Info: PSearchRec;
begin
  Probe := TProbeGroup.Create(Rc);
  List := TListProbe.Create(Rc, nil);
  Probe.Insert(List);
  MessageCount := 0;
  FocusedCount := 0;

  List.ReadDirectory(TempRoot + 'rd/', '*');
  Check((List.List <> nil) and (List.List.GetCount = 6), 'the directory has three files, two directories and ..');
  Check(List.Range = 6, 'the range of the list is the number of entries');
  Names := '';
  for I := 0 to List.List.GetCount - 1 do
    Names := Names + List.List.At(I)^.Name + '|';
  Check(Names = 'a.txt|b.txt|c.dat|sub1|sub2|..|', 'the order of the entries is files, directories, ..');
  Check((List.List.At(0)^.Attr and FA_DIREC) = 0, 'a file is not a directory');
  Check(List.List.At(0)^.Size = 5, 'the size of a.txt');
  Check(List.List.At(2)^.Size = 3, 'the size of c.dat');
  Check(List.List.At(0)^.Time <> 0, 'a file has a time');
  Check((List.List.At(3)^.Attr and FA_DIREC) <> 0, 'a subdirectory is a directory');
  Check((List.List.At(5)^.Attr and FA_DIREC) <> 0, '.. is a directory');
  Check(FocusedCount = 2, 'the first entry is focused by NewList and announced again by ReadDirectory');
  Check((LastWhat = evBroadcast) and (LastCommand = cmFileFocused) and (LastInfo = Pointer(List.List.At(0))),
    'the last message announces the first entry');
  Check(LastReceiver = TView(Probe), 'the message goes to the owner of the list');

  List.FocusItem(2);
  Check((List.Focused = 2) and (LastCommand = cmFileFocused) and (LastInfo = Pointer(List.List.At(2))) and
    (LastWhat = evBroadcast), 'FocusItem announces the entry');
  List.SelectItem(4);
  Check((LastCommand = cmFileDoubleClicked) and (LastInfo = Pointer(List.List.At(4))) and (LastWhat = evBroadcast),
    'SelectItem announces the entry as selected');

  Check(List.GetText(0, 100) = 'a.txt', 'the text of a file');
  Check(List.GetText(0, 3) = 'a.t', 'the text of a file is cut to MaxLen');
  Check(List.GetText(3, 100) = 'sub1\', 'the text of a directory ends with a backslash');
  Check(List.GetText(3, 2) = 'su\', 'the text of a directory is cut before the backslash');
  Check(List.GetText(5, 100) = '..\', 'the text of the parent directory');

  List.SetShift(kbShift);
  Found := List.List.Search(List.Key('sub2'), Index);
  Check(Found and (Index = 4), 'the key of a name with the shift key finds a directory');
  List.SetShift(0);
  Found := List.List.Search(List.Key('b.txt'), Index);
  Check(Found and (Index = 1), 'the key of a name finds a file');
  Found := List.List.Search(List.Key('sub15'), Index);
  Check(not Found and (Index = 3), 'the key of a file name that is not there goes after the files');

  List.ReadDirectory(TempRoot + 'rd/*.txt');
  Check((List.List.GetCount = 5) and (List.List.At(0)^.Name = 'a.txt') and (List.List.At(1)^.Name = 'b.txt') and
    (List.List.At(2)^.Name = 'sub1') and (List.List.At(4)^.Name = '..'),
    'a wild card that is given as one text keeps all the directories');

  MessageCount := 0;
  FocusedCount := 0;
  List.ReadDirectory(TempRoot + 'rd/nothing');
  Check(List.List.GetCount = 3, 'a name without a match leaves the two directories and ..');
  Check(FocusedCount = 2, 'a reading with no file announces the first entry');

  List.ReadDirectory(TempRoot + 'nope/deeper/', '*');
  Check(List.List.GetCount = 1, 'a directory that does not exist has only ..');
  Parent := List.List.At(0);
  Check(Parent^.Name = '..', 'the only entry is ..');
  Check((Parent^.Attr = FA_DIREC) and (Parent^.Size = 0) and (Parent^.Time = $210000),
    'the entry .. that cannot be read has the default values');
  Info := List.List.At(0);
  Check(LastInfo = Pointer(Info), 'the entry .. is announced');

  TvObject.DestroyObject(List);
  TvObject.DestroyObject(Probe);

  FilesDestroyed := 0;
  List := TListProbe.Create(Rc, nil);
  Counted := TCountedFiles.Create(5, 5);
  Counted.Insert(MakeRec('x', 0, 0));
  List.NewList(Counted);
  Check(List.List = Counted, 'the list is the collection that was given');
  Check(List.Range = 1, 'the range of the list is one');
  TvObject.DestroyObject(List);
  Check(FilesDestroyed = 1, 'the destructor of a file list destroys its list');
end;

procedure TestDirListBox;
var
  Box: TDirListBox;
  Probe: TProbeGroup;
  Dirs: TCountedDirs;
  Marker: string;
  Count, Seps, Index, SecondSep: Integer;
  Indent, Name1, Name2: string;
begin
  DirsDestroyed := 0;
  Probe := TProbeGroup.Create(Rc);
  Box := TDirListBox.Create(Rc, nil);
  Probe.Insert(Box);
  MessageCount := 0;
  Check(Box.NumCols = 1, 'a directory list box has one column');
  Check(Box.IsSelected(0), 'the entry 0 is selected in a new list box');
  Check(not Box.IsSelected(1), 'the entry 1 is not selected in a new list box');

  Dirs := TCountedDirs.Create(5, 5);
  Dirs.Insert(TDirEntry.Create('first', '/a'));
  Dirs.Insert(TDirEntry.Create('second', '/a/b'));
  Box.NewList(Dirs);
  Check(Box.GetText(0, 100) = 'first', 'the text of the first entry');
  Check(Box.GetText(1, 3) = 'sec', 'the text of an entry is cut to MaxLen');
  Check(Box.GetText(1, 0) = '', 'the text with the length 0');
  Box.SelectItem(1);
  Check((LastWhat = evCommand) and (LastCommand = cmChangeDir) and (LastInfo = Pointer(Box.List.At(1))) and
    (LastReceiver = TView(Probe)), 'SelectItem sends cmChangeDir with the entry to the owner');
  Check(MessageCount = 1, 'SelectItem sends one message');

  Box.NewDirectory('Drives');
  Check(DirsDestroyed = 1, 'a new directory destroys the old list');
  Check(Box.List.GetCount = 3, 'the disks are A, B and C');
  Check(string(Box.List.At(0).Text) = #$C0#$C2#$C4'A', 'the text of the first disk');
  Check(string(Box.List.At(0).Dir) = 'A:\', 'the directory of the first disk');
  Check(string(Box.List.At(1).Text) = ' '#$C3#$C4'B', 'the text of the middle disk');
  Check(string(Box.List.At(1).Dir) = 'B:\', 'the directory of the middle disk');
  Check(string(Box.List.At(2).Text) = ' '#$C0#$C4'C', 'the text of the last disk');
  Check(string(Box.List.At(2).Dir) = 'C:\', 'the directory of the last disk');
  Check(Box.Focused = 2, 'the current disk is focused');
  Check(Box.IsSelected(2) and not Box.IsSelected(0), 'the current disk is the selected entry');

  Marker := TempRoot + 'a/b/';
  Seps := CountSeps(Marker);
  Box.NewDirectory(Marker);
  Count := Box.List.GetCount;
  Check(Count = Seps + 2, 'the root, the directories up to the current one and two subdirectories');
  Check(Box.Focused = Seps - 1, 'the current directory is focused');
  Check(Box.IsSelected(Seps - 1) and not Box.IsSelected(0), 'the current directory is the selected entry');
  Check(string(Box.List.At(0).Text) = #$C0#$C4#$C2'/', 'the text of the root');
  Check(string(Box.List.At(0).Dir) = '/', 'the directory of the root');
  Check(Copy(string(Box.List.At(1).Text), 1, 5) = '  '#$C0#$C4#$C2, 'the first level is indented by two');
  SecondSep := Pos('/', Copy(Marker, 2, Length(Marker))) + 1;
  Check(string(Box.List.At(1).Dir) = Copy(Marker, 1, SecondSep - 1),
    'the directory of the first level has no separator at the end');
  Indent := StringOfChar(' ', 2 * (Seps - 1));
  Check(string(Box.List.At(Seps - 1).Text) = Indent + #$C0#$C4#$C2'b', 'the text of the current directory');
  Check(string(Box.List.At(Seps - 1).Dir) = TempRoot + 'a/b', 'the directory of the current directory');

  Indent := StringOfChar(' ', 2 * Seps);
  Check(Copy(string(Box.List.At(Seps).Text), 1, 2 * Seps + 3) = Indent + #$C0#$C2#$C4,
    'the first subdirectory has the first mark');
  Check(Copy(string(Box.List.At(Seps + 1).Text), 1, 2 * Seps + 3) = Indent + ' '#$C0#$C4,
    'the last subdirectory has the last mark');
  Name1 := Copy(string(Box.List.At(Seps).Text), 2 * Seps + 4, 100);
  Name2 := Copy(string(Box.List.At(Seps + 1).Text), 2 * Seps + 4, 100);
  Check(((Name1 = 's1') and (Name2 = 's2')) or ((Name1 = 's2') and (Name2 = 's1')),
    'the subdirectories are s1 and s2, and neither the hidden directory nor the file');
  Check(string(Box.List.At(Seps).Dir) = TempRoot + 'a/b/' + Name1, 'the directory of the first subdirectory');
  Check(string(Box.List.At(Seps + 1).Dir) = TempRoot + 'a/b/' + Name2, 'the directory of the last subdirectory');

  Marker := TempRoot + 'a/b/s1/';
  Seps := CountSeps(Marker);
  Box.NewDirectory(Marker);
  Check(Box.List.GetCount = Seps, 'a directory with no subdirectory ends the list');
  Check(Box.Focused = Seps - 1, 'the last directory is focused');
  Index := Seps - 1;
  Check(string(Box.List.At(Index).Text) = StringOfChar(' ', 2 * Index) + #$C0#$C4#$C4's1',
    'the last entry gets the last mark');

  Box.NewDirectory('relative');
  Check(Box.List.GetCount = 0, 'a path without a separator gives an empty list');

  DefaultCalls := 0;
  ChDirButtonDefaultHook := @OnDefault;
  Box.SetState(sfFocused, True);
  Check((DefaultCalls = 1) and (DefaultBox = Box) and DefaultEnable, 'focusing the list box calls the hook');
  Box.SetState(sfFocused, False);
  Check((DefaultCalls = 2) and not DefaultEnable, 'unfocusing the list box calls the hook');
  Box.SetState(sfSelected, True);
  Check(DefaultCalls = 2, 'a change of another state does not call the hook');
  ChDirButtonDefaultHook := nil;
  Box.SetState(sfFocused, True);
  Check(DefaultCalls = 2, 'there is no call while there is no hook');

  TvObject.DestroyObject(Box);
  TvObject.DestroyObject(Probe);

  DirsDestroyed := 0;
  Box := TDirListBox.Create(Rc, nil);
  Dirs := TCountedDirs.Create(5, 5);
  Dirs.Insert(TDirEntry.Create('only', '/o'));
  Box.NewList(Dirs);
  TvObject.DestroyObject(Box);
  Check(DirsDestroyed = 1, 'the destructor of a directory list box destroys its list');
end;

begin
  MakeTree;

  TestConstants;
  TestFunctions;
  TestValidFileName;
  TestGetCurDir;
  TestFileCollection;
  TestDirEntry;
  TestDirCollection;
  TestFileListBasics;
  TestSearchOfFileList;
  TestSearchOfTexts;
  TestFileListDirectory;
  TestDirListBox;

  RemoveTree(TempRoot);
  ChDirButtonDefaultHook := nil;
  Done;
end.
