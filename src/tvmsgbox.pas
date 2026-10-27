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

uses
  TvObjs, TvUtil, TvDialog, TvApp;

const
  ClassMask = $0003;
  FirstButtonFlag = $0100;
  KnownButtons = 4;
  ButtonWidth = 10;
  ButtonHeight = 2;
  ButtonGap = 2;
  ButtonCommands: array[0..KnownButtons - 1] of Word = (cmYes, cmNo, cmOK, cmCancel);

  { The size of the rectangle that MessageBox starts from, and the cells around the text that the rectangle keeps
    free. }
  BoxWidth = 40;
  BoxHeight = 9;
  SideMargin = 7;
  RowMargin = 6;

  InputBoxWidth = 60;
  InputBoxHeight = 8;

function ButtonCaption(Slot: Integer): string;
begin
  case Slot of
    0: Result := MsgBoxText.YesText;
    1: Result := MsgBoxText.NoText;
    2: Result := MsgBoxText.OkText;
  else
    Result := MsgBoxText.CancelText;
  end;
end;

function ClassCaption(BoxClass: Integer): string;
begin
  case BoxClass of
    0: Result := MsgBoxText.WarningText;
    1: Result := MsgBoxText.ErrorText;
    2: Result := MsgBoxText.InformationText;
  else
    Result := MsgBoxText.ConfirmText;
  end;
end;

{ Tells whether the button of the slot Slot (0 is Yes, 3 is Cancel) is asked for by Options. }
function WantsButton(Options: Word; Slot: Integer): Boolean;
var
  slotFlag: Integer;
begin
  slotFlag := FirstButtonFlag shl Slot;
  Result := (Options and slotFlag) <> 0;
end;

function MessageBoxRect(const R: TRect; const Msg: string; AOptions: Word): Word;
var
  box: TDialog;
  buttons: array[0..KnownButtons - 1] of TView;
  buttonTotal, slot, rowWidth, nextLeft, shown: Integer;
  textArea, buttonArea: TRect;
begin
  box := TDialog.Create(R, ClassCaption(AOptions and ClassMask));

  textArea := TRect.Create(3, 2, box.Size.X - 2, box.Size.Y - 3);
  box.Insert(TStaticText.Create(textArea, Msg));

  buttonTotal := 0;
  rowWidth := -ButtonGap;
  buttonArea := TRect.Create(0, 0, ButtonWidth, ButtonHeight);
  slot := 0;
  while slot < KnownButtons do
  begin
    if WantsButton(AOptions, slot) then
    begin
      buttons[buttonTotal] := TButton.Create(buttonArea, ButtonCaption(slot), ButtonCommands[slot], bfNormal);
      rowWidth := rowWidth + buttons[buttonTotal].Size.X + ButtonGap;
      Inc(buttonTotal);
    end;
    Inc(slot);
  end;

  nextLeft := (box.Size.X - rowWidth) div 2;
  shown := 0;
  while shown < buttonTotal do
  begin
    box.Insert(buttons[shown]);
    buttons[shown].MoveTo(SmallInt(nextLeft), SmallInt(box.Size.Y - 3));
    nextLeft := nextLeft + buttons[shown].Size.X + ButtonGap;
    Inc(shown);
  end;

  box.SelectNext(False);

  Result := TProgram.Application.ExecView(box);

  TvObject.DestroyObject(box);
end;

function MessageBoxRect(const R: TRect; AOptions: Word; const Fmt: string; const Args: array of const): Word;
var
  formatted: string;
begin
  formatted := VFormatStr(Fmt, Args);
  Result := MessageBoxRect(R, formatted, AOptions);
end;

{ The rectangle of a message box for Text: 40 cells wide, 9 tall or taller when the text needs more rows, centred in
  the desktop. }
function CenteredBoxRect(const Text: string): TRect;
var
  textWidth, freeColumns, capacity, boxRows: Integer;
  deskSize: TPoint;
begin
  freeColumns := BoxWidth - SideMargin;
  capacity := freeColumns * (BoxHeight - RowMargin);
  boxRows := BoxHeight;
  textWidth := Strwidth(Text);
  if textWidth > capacity then
    boxRows := textWidth div freeColumns + RowMargin + 1;

  deskSize := TProgram.DeskTop.Size;
  Result := TRect.Create(0, 0, BoxWidth, boxRows);
  Result.Move((deskSize.X - BoxWidth) div 2, (deskSize.Y - boxRows) div 2);
end;

function MessageBox(const Msg: string; AOptions: Word): Word;
var
  area: TRect;
begin
  area := CenteredBoxRect(Msg);
  Result := MessageBoxRect(area, Msg, AOptions);
end;

function MessageBox(AOptions: Cardinal; const Fmt: string; const Args: array of const): Word;
var
  formatted: string;
  area: TRect;
begin
  formatted := VFormatStr(Fmt, Args);
  area := CenteredBoxRect(formatted);
  Result := MessageBoxRect(area, formatted, Word(AOptions));
end;

function InputBox(const Caption, Prompt: string; Buffer: PAnsiChar; MaxLen: Byte): Word;
var
  area: TRect;
  deskSize: TPoint;
begin
  deskSize := TProgram.DeskTop.Size;
  area := TRect.Create(0, 0, InputBoxWidth, InputBoxHeight);
  area.Move((deskSize.X - InputBoxWidth) div 2, (deskSize.Y - InputBoxHeight) div 2);
  Result := InputBoxRect(area, Caption, Prompt, Buffer, MaxLen);
end;

function InputBoxRect(const Bounds: TRect; const Caption, Prompt: string; Buffer: PAnsiChar;
  MaxLen: Byte): Word;
var
  box: TDialog;
  entry: TView;
  area: TRect;
  promptLength: Integer;
  answer: Word;
begin
  box := TDialog.Create(Bounds, Caption);
  promptLength := Length(Prompt);

  area := TRect.Create(4 + promptLength, 2, box.Size.X - 3, 3);
  entry := nil;
  if Assigned(InputLineHook) then
    entry := InputLineHook(area, MaxLen);
  box.Insert(entry);

  area := TRect.Create(2, 2, 3 + promptLength, 3);
  box.Insert(TLabel.Create(area, Prompt, entry));

  area := TRect.Create(box.Size.X - 24, box.Size.Y - 4, box.Size.X - 14, box.Size.Y - 2);
  box.Insert(TButton.Create(area, MsgBoxText.OkText, cmOK, bfDefault));

  area.Move(12, 0);
  box.Insert(TButton.Create(area, MsgBoxText.CancelText, cmCancel, bfNormal));

  box.SelectNext(False);
  box.SetData(Buffer);
  answer := TProgram.Application.ExecView(box);
  if answer <> cmCancel then
    box.GetData(Buffer);
  TvObject.DestroyObject(box);
  Result := answer;
end;

end.
