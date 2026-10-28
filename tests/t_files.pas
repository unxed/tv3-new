{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (the commands of the file dialogs, TSearchRec, TFileCollection,
  TSortedListBox, TFileList, TDirEntry, TDirCollection, TDirListBox), source/tvision/tfilecol.cpp,
  source/tvision/tfillist.cpp, source/tvision/tdircoll.cpp, source/tvision/tdirlist.cpp, source/tvision/tvtext1.cpp
  (the tables of TDirListBox), include/tvision/ttypes.h, include/tvision/config.h, include/tvision/tv.h,
  include/tvision/views.h
  See COPYRIGHT.magiblot.

  Test program of the unit TvFiles.

  The views have no owner and no screen: a message that a view sends to its owner goes through the hook of the
  messages, which counts the messages and remembers the last one. The hook of the new list of a sorted list box gives
  the list to the list box of TvList. The tests that touch files make a directory of their own under the directory of
  temporary files and remove it at the end. The directory of the tests has the files a.txt (5 bytes), b.txt, c.dat
  (3 bytes), the directories sub1 and sub2 and the hidden directory .hdir. }
program t_files;

{$mode objfpc}

uses
  SysUtils, TvGeom, TvKeys, TvEvents, TvObjs, TvViews, TvList, TvFiles;

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
    function Key(const Text: string): PSearchRec;
  end;

var
  MessageCount: Integer;
  FocusedCount: Integer;
  LastReceiver: TView;
  LastWhat: Word;
  LastCommand: Word;
  LastInfo: Pointer;
  NewListCalls: Integer;
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

function TListProbe.Key(const Text: string): PSearchRec;
begin
  Result := PSearchRec(GetKey(Text));
end;

function OnMessage(Receiver: TView; What, Command: Word; InfoPtr: Pointer): Pointer;
begin
  Inc(MessageCount);
  if Command = cmFileFocused then
    Inc(FocusedCount);
  LastReceiver := Receiver;
  LastWhat := What;
  LastCommand := Command;
  LastInfo := InfoPtr;
  Result := nil;
end;

procedure OnNewList(Box: TSortedListBox; NewItems: TSortedCollection);
begin
  Inc(NewListCalls);
  TListBox(Box).NewList(TCollection(NewItems));
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
  Check(TFileList.TooManyFiles = '', 'tooManyFiles starts empty');
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

  SortedListBoxNewListHook := nil;
  Spare := TFileCollection.Create(5, 5);
  Spare.Insert(MakeRec('f', 0, 0));
  List.NewList(Spare);
  Check(List.List = nil, 'NewList of a sorted list box does nothing while there is no hook');
  TvObject.DestroyObject(Spare);
  SortedListBoxNewListHook := @OnNewList;

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

procedure TestFileListDirectory;
var
  List: TListProbe;
  Counted: TCountedFiles;
  Index: ccIndex;
  Found: Boolean;
  Parent: PSearchRec;
  Names: string;
  I: Integer;
  Info: PSearchRec;
begin
  List := TListProbe.Create(Rc, nil);
  MessageCount := 0;
  FocusedCount := 0;
  NewListCalls := 0;

  List.ReadDirectory(TempRoot + 'rd/', '*');
  Check(NewListCalls = 1, 'ReadDirectory gives the new list to NewList once');
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
  Check(LastReceiver = nil, 'the message goes to the owner, which is none');

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
  Check(NewListCalls = 2, 'the second reading gives a second list');

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
  Dirs: TCountedDirs;
  Marker: string;
  Count, Seps, Index, SecondSep: Integer;
  Indent, Name1, Name2: string;
begin
  DirsDestroyed := 0;
  MessageCount := 0;
  Box := TDirListBox.Create(Rc, nil);
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
    (LastReceiver = nil), 'SelectItem sends cmChangeDir with the entry to the owner');
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

  DirsDestroyed := 0;
  Box := TDirListBox.Create(Rc, nil);
  Dirs := TCountedDirs.Create(5, 5);
  Dirs.Insert(TDirEntry.Create('only', '/o'));
  Box.NewList(Dirs);
  TvObject.DestroyObject(Box);
  Check(DirsDestroyed = 1, 'the destructor of a directory list box destroys its list');
end;

begin
  MessageHook := @OnMessage;
  SortedListBoxNewListHook := @OnNewList;
  MakeTree;

  TestConstants;
  TestFunctions;
  TestFileCollection;
  TestDirEntry;
  TestDirCollection;
  TestFileListBasics;
  TestFileListDirectory;
  TestDirListBox;

  RemoveTree(TempRoot);
  MessageHook := nil;
  SortedListBoxNewListHook := nil;
  ChDirButtonDefaultHook := nil;
  Done;
end.
