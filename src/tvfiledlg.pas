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

end.
