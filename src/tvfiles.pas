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

end.
