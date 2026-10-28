{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/stddlg.h (the options cdNormal, cdNoLoadDir and cdHelpButton, the commands cmChangeDir
  and cmRevert, TChDirDialog), source/tvision/tchdrdlg.cpp, include/tvision/ttypes.h (EOS),
  source/tvision/tvtext1.cpp (the text of the drives)
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The members
  read, write, build and streamableName of the class, and the constructor with StreamableInit, belong to a later
  unit.

  Parts of the C++ that have no unit yet:
    - getCurDir, which getCurrentDir of tchdrdlg.cpp calls, is defined in a file that is not among the sources of
      this unit; GetCurDirHook stands for it, and while it is nil the current directory is empty.
    - strnzcpy, which puts a path into the line, is StrNZCopyHook of TvHist; while it is nil the line keeps its text.
    - The functions of the compatibility headers (fexpand, chdir) are made with TvPath and SysUtils, as TvFiles makes
      them. setdisk is left out, because the target has no drives: the path that changeDir of tchdrdlg.cpp gets
      never has a drive letter before a colon that selects a disk.

  The texts of the dialog (changeDirTitle, dirNameText, dirTreeText, okText, chdirText, revertText, helpText,
  drivesText and invalidText) are defined in a file that is not among the sources of this unit, so they are the class
  variables ChangeDirTitle, DirNameText, DirTreeText, OkText, ChdirText, RevertText, HelpText, DrivesText and
  InvalidText of TChDirDialog, empty until the program sets them. DrivesText must hold the same text as Drives of
  TDirListBox for the entry of the drives to be recognised.

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
  { Stands for getCurDir: the current directory, as the C++ function writes it with the two characters of a drive
    before the path. }
  TGetCurDirFunc = function: string;

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

var
  { Stands for getCurDir; nil gives an empty directory. }
  GetCurDirHook: TGetCurDirFunc;

{ Makes the button of the dialog that owns Box the default button, or stops it from being so. This is what
  ChDirButtonDefaultHook of TvFiles is given when the unit starts. }
procedure MakeChDirButtonDefault(Box: TDirListBox; Enable: Boolean);

implementation

end.
