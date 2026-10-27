{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/msgbox.h, source/tvision/msgbox.cpp
  See COPYRIGHT.magiblot.

  The views are used by the thread of the user interface only; no routine of this unit is thread-safe. The functions
  run a modal loop with TProgram.Application, so the application and its desktop must exist when they are called.

  Parts of the C++ that have no unit yet:
    - TInputLine, which inputBox puts into its dialog. InputLineHook stands for its constructor that takes a
      rectangle and a limit; it returns the view that edits the text. While the hook is nil the dialog has no input
      line: the label has no link and the data of the dialog goes to no view.

  The texts of the class MsgBoxText are defined in a file that is not among the sources of the unit, so they are the
  class variables of MsgBoxText, which start as empty texts and which the program sets. The tables of the buttons and
  of the titles read them when a box is made.

  The buffer of inputBox is a block of characters with a terminating zero, as the C++ keeps it, and it is given to
  the data of the dialog and taken from it as it is. The formatted variants of messageBox and messageBoxRect take a
  format string and an array of const, and format them with VFormatStr of TvUtil. }
unit TvMsgBox;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvGeom, TvViews;

const
  { The class of a message box, which chooses the title of its dialog: a number from 0 to 3. }
  mfWarning = 0 * 1;
  mfError = 0 + 1;
  mfInformation = 4 div 2;
  mfConfirmation = 6 div 2;

  { The buttons of a message box: one bit each, in the high byte of the options. }
  mfYesButton = 256;
  mfNoButton = 2 * mfYesButton;
  mfOKButton = 2 * mfNoButton;
  mfCancelButton = 2 * mfOKButton;

  { The usual sets of buttons. }
  mfOKCancel = mfCancelButton + mfOKButton;
  mfYesNoCancel = mfCancelButton + mfNoButton + mfYesButton;

type
  { The function that makes the input line of an input box in the rectangle Bounds, for a text of at most MaxLen
    characters. }
  TCreateInputLineFunc = function(const Bounds: TRect; MaxLen: Byte): TView;

  { The texts of the buttons and of the titles of the boxes. }
  MsgBoxText = class
  public
    class var YesText: string;
    class var NoText: string;
    class var OkText: string;
    class var CancelText: string;
    class var WarningText: string;
    class var ErrorText: string;
    class var InformationText: string;
    class var ConfirmText: string;
  end;

var
  InputLineHook: TCreateInputLineFunc;

{ Shows a box with the text Msg in the rectangle R and answers the command of the button that ended it. }
function MessageBoxRect(const R: TRect; const Msg: string; AOptions: Word): Word; overload;

{ As the first one, with the text made from Fmt and Args. }
function MessageBoxRect(const R: TRect; AOptions: Word; const Fmt: string;
  const Args: array of const): Word; overload;

{ As MessageBoxRect, in a rectangle that is centred in the desktop and tall enough for the text. }
function MessageBox(const Msg: string; AOptions: Word): Word; overload;

{ As the first one, with the text made from Fmt and Args. }
function MessageBox(AOptions: Cardinal; const Fmt: string; const Args: array of const): Word; overload;

{ Asks for a text in a dialog of the rectangle Bounds. Buffer holds the first text and receives the last one unless
  the answer is cmCancel; the text is at most MaxLen characters long. }
function InputBoxRect(const Bounds: TRect; const Caption, Prompt: string; Buffer: PAnsiChar;
  MaxLen: Byte): Word;

{ As InputBoxRect, in a dialog of 60 by 8 cells that is centred in the desktop. }
function InputBox(const Caption, Prompt: string; Buffer: PAnsiChar; MaxLen: Byte): Word;

implementation

end.
