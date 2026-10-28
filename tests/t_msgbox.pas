{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/msgbox.h, source/tvision/msgbox.cpp, source/tvision/tvtext2.cpp
  See COPYRIGHT.magiblot.

  The display is a screen of 60 by 20 cells in memory and the application has only a desktop, which fills the
  screen, so the desktop is 60 cells wide and 20 tall. The application is a TApplication that reads its events from
  a script of one event: when the modal dialog of a box asks for its first event, the application takes a snapshot
  of the dialog (its bounds, title, subviews and the kind of the focused one), lets the test change something
  through DuringModal, and then answers the event that the test armed. Any later request for an event is a
  cmCancel, so that a failure ends the dialog and does not wait. The texts of MsgBoxText are checked as the unit
  sets them. The input line is a view of the test that records what the dialog
  gives it and writes a text of the test when the dialog asks for its data. The buttons and labels are read through
  classes that make their protected members public to the test. }
program t_msgbox;

{$mode objfpc}
{$modeswitch advancedrecords}
{$POINTERMATH ON}

uses
  cthreads,
  Strings, TvGeom, TvKeys, TvEvents, TvSys, TvColors, TvCell, TvDrawBuf, TvScreen, TvObjs, TvTimer, TvViews,
  TvWindow, TvDialog, TvApp, TvMsgBox;

{$I testlib.inc}

const
  ScrW = 60;
  ScrH = 20;
  MaxItems = 8;

type
  TFakeScreen = class(TScreenBackend)
  public
    Cols, Rows, Mode, CaretSize: Word;
    procedure SetUpConsole; override;
    procedure RestoreConsole; override;
    function GetCaretSize: Word; override;
    procedure SetCaretSize(ASize: Word); override;
    function GetScreenRows: Word; override;
    function GetScreenCols: Word; override;
    function GetScreenMode: Word; override;
    procedure SetScreenMode(AMode: Word); override;
    function AllocateScreenBuffer: PScreenCell; override;
    procedure FreeScreenBuffer(ABuffer: PScreenCell); override;
  end;

  TFakeEvents = class(TEventBackend)
  public
    procedure MouseSuspend; override;
    procedure MouseSetRange(MaxX, MaxY: Integer); override;
  end;

  { The input line of the test. }
  TFakeInput = class(TView)
  public
    function DataSize: Word; override;
    procedure GetData(Rec: Pointer); override;
    procedure SetData(Rec: Pointer); override;
  end;

  TButtonPeek = class(TButton)
  public
    function CommandOf: Word;
    function FlagsOf: Byte;
  end;

  TLabelPeek = class(TLabel)
  public
    function LinkOf: TView;
  end;

  TItemKind = (ikText, ikLabel, ikButton, ikInput, ikOther);

  TItemInfo = record
    Kind: TItemKind;
    Bounds: TRect;
    Text: string;
    Command: Word;
    Flags: Byte;
    Link: TView;
    Ref: TView;
  end;

  TSnapshot = record
    Taken: Boolean;
    Bounds: TRect;
    Title: string;
    Modal: Boolean;
    Count: Integer;
    Items: array[1..MaxItems] of TItemInfo;
    CurrentKind: TItemKind;
  end;

  TModalProc = procedure;

  TMsgApp = class(TApplication)
  public
    Armed: Boolean;
    Reply: TEvent;
    DuringModal: TModalProc;
    constructor Create; reintroduce;
    procedure GetEvent(var Event: TEvent); override;
  end;

var
  ScreenCells: array[0..80 * 25 - 1] of TScreenCell;
  Fake: TFakeScreen;
  FakeEvents: TFakeEvents;
  SavedScreen: TScreenBackend;
  SavedEvents: TEventBackend;

  App: TMsgApp;
  Snap: TSnapshot;
  StrayReads: Integer;
  BaseViewCount: Integer;

  { What the input line of the test saw and says. }
  FakeContent: string;
  FakeSeenData: string;
  FakeSetCalls, FakeGetCalls: Integer;
  MakerCalls: Integer;
  MakerBounds: TRect;
  MakerLimit: Integer;

  Buf: array[0..79] of AnsiChar;

{ The hooks and the fake devices }

procedure TFakeScreen.SetUpConsole;
begin
end;

procedure TFakeScreen.RestoreConsole;
begin
end;

function TFakeScreen.GetCaretSize: Word;
begin
  Result := CaretSize;
end;

procedure TFakeScreen.SetCaretSize(ASize: Word);
begin
  CaretSize := ASize;
end;

function TFakeScreen.GetScreenRows: Word;
begin
  Result := Rows;
end;

function TFakeScreen.GetScreenCols: Word;
begin
  Result := Cols;
end;

function TFakeScreen.GetScreenMode: Word;
begin
  Result := Mode;
end;

procedure TFakeScreen.SetScreenMode(AMode: Word);
begin
  Mode := AMode;
end;

function TFakeScreen.AllocateScreenBuffer: PScreenCell;
begin
  Result := @ScreenCells[0];
end;

procedure TFakeScreen.FreeScreenBuffer(ABuffer: PScreenCell);
begin
end;

procedure TFakeEvents.MouseSuspend;
begin
end;

procedure TFakeEvents.MouseSetRange(MaxX, MaxY: Integer);
begin
end;

procedure OnCaret(X, Y: Integer);
begin
end;

procedure OnScreenWrite(X, Y: Integer; Cells: PScreenCell; Count: Integer);
begin
end;

{ The classes of the test }

function TFakeInput.DataSize: Word;
begin
  Result := Word(MakerLimit + 1);
end;

procedure TFakeInput.GetData(Rec: Pointer);
begin
  Inc(FakeGetCalls);
  StrPCopy(PAnsiChar(Rec), FakeContent);
end;

procedure TFakeInput.SetData(Rec: Pointer);
begin
  Inc(FakeSetCalls);
  FakeSeenData := StrPas(PAnsiChar(Rec));
end;

function TButtonPeek.CommandOf: Word;
begin
  Result := Command;
end;

function TButtonPeek.FlagsOf: Byte;
begin
  Result := Flags;
end;

function TLabelPeek.LinkOf: TView;
begin
  Result := Link;
end;

function MakeFakeInput(const Bounds: TRect; MaxLen: Byte): TView;
begin
  Inc(MakerCalls);
  MakerBounds := Bounds;
  MakerLimit := MaxLen;
  Result := TFakeInput.Create(Bounds);
end;

function MakeDesk(R: TRect): TDeskTop;
begin
  Result := TDeskTop.Create(R);
end;

function KindOf(Item: TView): TItemKind;
begin
  Result := ikOther;
  if Item = nil then
    Exit;
  if Item is TFakeInput then
    Result := ikInput
  else if Item is TLabel then
    Result := ikLabel
  else if Item is TStaticText then
    Result := ikText
  else if Item is TButton then
    Result := ikButton;
end;

function DescribeItem(Item: TView): TItemInfo;
var
  textBuffer: array[0..255] of AnsiChar;
  buttonTitle: PAnsiChar;
begin
  Result.Kind := KindOf(Item);
  Result.Bounds := Item.GetBounds;
  Result.Text := '';
  Result.Command := 0;
  Result.Flags := 0;
  Result.Link := nil;
  Result.Ref := Item;
  case Result.Kind of
    ikText, ikLabel:
      begin
        textBuffer[0] := #0;
        TStaticText(Item).GetText(@textBuffer[0]);
        Result.Text := StrPas(@textBuffer[0]);
        if Result.Kind = ikLabel then
          Result.Link := TLabelPeek(Item).LinkOf;
      end;
    ikButton:
      begin
        Result.Command := TButtonPeek(Item).CommandOf;
        Result.Flags := TButtonPeek(Item).FlagsOf;
        buttonTitle := TButton(Item).Title;
        if buttonTitle <> nil then
          Result.Text := StrPas(buttonTitle);
      end;
  end;
end;

procedure TakeSnapshot(Top: TView);
var
  dialog: TGroup;
  windowTitle: PAnsiChar;
  position, stored: Integer;
  member: TView;
begin
  Snap.Taken := False;
  Snap.Count := 0;
  Snap.Title := '';
  if not (Top is TGroup) then
    Exit;
  dialog := TGroup(Top);
  Snap.Taken := True;
  Snap.Bounds := dialog.GetBounds;
  Snap.Modal := dialog.GetState(sfModal);
  if Top is TWindow then
  begin
    windowTitle := TWindow(Top).Title;
    if windowTitle <> nil then
      Snap.Title := StrPas(windowTitle);
  end;
  Snap.CurrentKind := KindOf(dialog.Current);
  position := 1;
  stored := 0;
  member := dialog.At(SmallInt(position));
  while (member <> nil) and (stored < MaxItems) do
  begin
    if not (member is TFrame) then
    begin
      Inc(stored);
      Snap.Items[stored] := DescribeItem(member);
    end;
    Inc(position);
    member := dialog.At(SmallInt(position));
  end;
  Snap.Count := stored;
end;

constructor TMsgApp.Create;
begin
  inherited Create(nil, nil, @MakeDesk);
end;

procedure TMsgApp.GetEvent(var Event: TEvent);
begin
  if Armed then
  begin
    Armed := False;
    TakeSnapshot(Current);
    if Assigned(DuringModal) then
      DuringModal();
    Event := Reply;
    Exit;
  end;
  if Pending.What <> evNothing then
  begin
    inherited GetEvent(Event);
    Exit;
  end;
  Inc(StrayReads);
  FillChar(Event, SizeOf(Event), 0);
  Event.What := evCommand;
  Event.Message.Command := cmCancel;
end;

{ Small helpers }

function Rc(AX, AY, BX, BY: Integer): TRect;
begin
  Result := TRect.Create(AX, AY, BX, BY);
end;

function RectIs(const R: TRect; AX, AY, BX, BY: Integer): Boolean;
begin
  Result := (R.A.X = AX) and (R.A.Y = AY) and (R.B.X = BX) and (R.B.Y = BY);
end;

procedure DrainPosted;
var
  Ev: TEvent;
begin
  while TEventQueue.GetPostedEvent(Ev) do
    ;
end;

procedure ArmCommand(Command: Word);
begin
  FillChar(App.Reply, SizeOf(App.Reply), 0);
  App.Reply.What := evCommand;
  App.Reply.Message.Command := Command;
  App.Armed := True;
  Snap.Taken := False;
end;

procedure ArmKey(Code: Word);
begin
  FillChar(App.Reply, SizeOf(App.Reply), 0);
  App.Reply.What := evKeyDown;
  App.Reply.KeyDown.KeyCode := Code;
  App.Armed := True;
  Snap.Taken := False;
end;

function AppViewCount: Integer;
begin
  Result := 0;
  while App.At(SmallInt(Result + 1)) <> nil do
    Inc(Result);
end;

{ The position in the snapshot of the first subview of the kind Kind; 0 when there is none. }
function FindKind(Kind: TItemKind): Integer;
var
  position: Integer;
begin
  Result := 0;
  for position := 1 to Snap.Count do
    if Snap.Items[position].Kind = Kind then
    begin
      Result := position;
      Exit;
    end;
end;

function CountKind(Kind: TItemKind): Integer;
var
  position: Integer;
begin
  Result := 0;
  for position := 1 to Snap.Count do
    if Snap.Items[position].Kind = Kind then
      Inc(Result);
end;

{ The position in the snapshot of the button of the command Command; 0 when there is none. }
function FindButton(Command: Word): Integer;
var
  position: Integer;
begin
  Result := 0;
  for position := 1 to Snap.Count do
    if (Snap.Items[position].Kind = ikButton) and (Snap.Items[position].Command = Command) then
    begin
      Result := position;
      Exit;
    end;
end;

function ButtonAt(Command: Word; AX, AY, BX, BY: Integer): Boolean;
var
  position: Integer;
begin
  Result := False;
  position := FindButton(Command);
  if position = 0 then
    Exit;
  Result := RectIs(Snap.Items[position].Bounds, AX, AY, BX, BY);
end;

function ButtonTitle(Command: Word): string;
var
  position: Integer;
begin
  Result := '<none>';
  position := FindButton(Command);
  if position = 0 then
    Exit;
  Result := Snap.Items[position].Text;
end;

function ButtonFlags(Command: Word): Integer;
var
  position: Integer;
begin
  Result := -1;
  position := FindButton(Command);
  if position = 0 then
    Exit;
  Result := Snap.Items[position].Flags;
end;

function TextIs(AX, AY, BX, BY: Integer; const Expected: string): Boolean;
var
  position: Integer;
begin
  Result := False;
  position := FindKind(ikText);
  if position = 0 then
    Exit;
  Result := RectIs(Snap.Items[position].Bounds, AX, AY, BX, BY) and (Snap.Items[position].Text = Expected);
end;

procedure ResetFake;
begin
  FakeContent := '';
  FakeSeenData := '';
  FakeSetCalls := 0;
  FakeGetCalls := 0;
  MakerCalls := 0;
  MakerLimit := 0;
  MakerBounds := Rc(0, 0, 0, 0);
end;

procedure TypeEdited;
begin
  FakeContent := 'edited';
end;

procedure FillBuffer(const Content: string);
begin
  FillChar(Buf, SizeOf(Buf), 0);
  StrPCopy(@Buf[0], Content);
end;

function BufferText: string;
begin
  Result := StrPas(@Buf[0]);
end;

{ The tests }

procedure TestConstants;
begin
  Check(mfWarning = $0000, 'mfWarning is 0');
  Check(mfError = $0001, 'mfError is 1');
  Check(mfInformation = $0002, 'mfInformation is 2');
  Check(mfConfirmation = $0003, 'mfConfirmation is 3');
  Check(mfYesButton = $0100, 'mfYesButton is $0100');
  Check(mfNoButton = $0200, 'mfNoButton is $0200');
  Check(mfOKButton = $0400, 'mfOKButton is $0400');
  Check(mfCancelButton = $0800, 'mfCancelButton is $0800');
  Check(mfYesNoCancel = $0B00, 'mfYesNoCancel is yes, no and cancel');
  Check(mfOKCancel = $0C00, 'mfOKCancel is ok and cancel');
  Check(MsgBoxText.YesText = '~Y~es', 'yesText is the text of the C++');
  Check(MsgBoxText.NoText = '~N~o', 'noText is the text of the C++');
  Check(MsgBoxText.OkText = 'O~K~', 'okText is the text of the C++');
  Check(MsgBoxText.CancelText = '~C~ancel', 'cancelText is the text of the C++');
  Check(MsgBoxText.WarningText = 'Warning', 'warningText is the text of the C++');
  Check(MsgBoxText.ErrorText = 'Error', 'errorText is the text of the C++');
  Check(MsgBoxText.InformationText = 'Information', 'informationText is the text of the C++');
  Check(MsgBoxText.ConfirmText = 'Confirm', 'confirmText is the text of the C++');
  Check(not Assigned(InputLineHook), 'InputLineHook starts as nil');
end;

procedure TestSetup;
begin
  Check(App <> nil, 'the application exists');
  Check((TProgram.Application = TProgram(App)) and (TProgram.DeskTop <> nil), 'the application and its desktop exist');
  Check((TProgram.DeskTop.Size.X = ScrW) and (TProgram.DeskTop.Size.Y = ScrH), 'the desktop fills the screen');
  BaseViewCount := AppViewCount;
  Check(BaseViewCount = 1, 'the application holds only its desktop');
end;

procedure TestRectYesNoCancel;
var
  answer: Word;
begin
  ArmCommand(cmNo);
  answer := MessageBoxRect(Rc(0, 0, 40, 9), 'Hello', mfError or mfYesNoCancel);
  Check(answer = cmNo, 'MessageBoxRect answers the command that ended the dialog');
  Check(Snap.Taken, 'the modal loop asked for an event of a dialog');
  Check(RectIs(Snap.Bounds, 0, 0, 40, 9), 'the dialog has the rectangle that was given');
  Check(Snap.Title = 'Error', 'the class mfError gives the title of errors');
  Check(Snap.Modal, 'the dialog is modal while it runs');
  Check(Snap.Count = 4, 'a box with three buttons has the text and three buttons');
  Check(CountKind(ikText) = 1, 'the box has one static text');
  Check(TextIs(3, 2, 38, 6, 'Hello'), 'the text fills the rectangle from (3, 2) to (width - 2, height - 3)');
  Check(CountKind(ikButton) = 3, 'the box has three buttons');
  Check(ButtonAt(cmYes, 3, 6, 13, 8), 'the yes button is the first of the row, centred');
  Check(ButtonAt(cmNo, 15, 6, 25, 8), 'the no button is 12 cells after the yes button');
  Check(ButtonAt(cmCancel, 27, 6, 37, 8), 'the cancel button is 12 cells after the no button');
  Check(FindButton(cmOK) = 0, 'there is no ok button when it is not asked for');
  Check((ButtonTitle(cmYes) = '~Y~es') and (ButtonTitle(cmNo) = '~N~o') and (ButtonTitle(cmCancel) = '~C~ancel'),
    'the buttons have the texts of MsgBoxText');
  Check((ButtonFlags(cmYes) = bfNormal) and (ButtonFlags(cmNo) = bfNormal) and (ButtonFlags(cmCancel) = bfNormal),
    'the buttons of a message box are normal buttons');
  Check(Snap.CurrentKind = ikButton, 'a button has the focus');
  Check(AppViewCount = BaseViewCount, 'the dialog is removed from the application after the loop');
end;

procedure TestAnswers;
begin
  ArmCommand(cmOK);
  Check(MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfOKButton) = cmOK, 'the answer is cmOK when the dialog ends with cmOK');
  ArmCommand(cmYes);
  Check(MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfOKButton) = cmYes, 'the answer is cmYes when the dialog ends with cmYes');
  ArmCommand(cmCancel);
  Check(MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfOKButton) = cmCancel,
    'the answer is cmCancel when the dialog ends with cmCancel');
  ArmKey(kbEsc);
  Check(MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfOKButton) = cmCancel, 'the key Esc ends a message box with cmCancel');
  Check(StrayReads = 0, 'the answers did not need a request that the test did not arm');
end;

procedure TestTitles;
begin
  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfWarning or mfOKButton);
  Check(Snap.Title = 'Warning', 'the class mfWarning gives the title of warnings');
  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfError or mfOKButton);
  Check(Snap.Title = 'Error', 'the class mfError gives the title of errors with an ok button');
  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfInformation or mfOKButton);
  Check(Snap.Title = 'Information', 'the class mfInformation gives the title of information');
  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfConfirmation or mfOKButton);
  Check(Snap.Title = 'Confirm', 'the class mfConfirmation gives the title of confirmations');
  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'x', $0407);
  Check(Snap.Title = 'Confirm', 'only the two low bits of the options choose the title');
  Check((Snap.Count = 2) and (FindButton(cmOK) <> 0), 'the bit $0004 asks for no button');
end;

procedure TestButtonRows;
begin
  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfOKButton);
  Check(ButtonAt(cmOK, 15, 6, 25, 8), 'one button is centred: (40 - 10) / 2');
  Check(Snap.CurrentKind = ikButton, 'the only button has the focus');

  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfOKCancel);
  Check(ButtonAt(cmOK, 9, 6, 19, 8), 'with two buttons the ok button starts at (40 - 22) / 2');
  Check(ButtonAt(cmCancel, 21, 6, 31, 8), 'with two buttons the cancel button follows after 12 cells');

  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'x', mfYesButton or mfNoButton or mfOKButton or mfCancelButton);
  Check(Snap.Count = 5, 'four buttons and the text');
  Check(ButtonAt(cmYes, -3, 6, 7, 8), 'four buttons are wider than the dialog, so the first starts at -3');
  Check(ButtonAt(cmNo, 9, 6, 19, 8), 'the second of four buttons');
  Check(ButtonAt(cmOK, 21, 6, 31, 8), 'the third of four buttons');
  Check(ButtonAt(cmCancel, 33, 6, 43, 8), 'the fourth of four buttons');

  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 41, 9), 'x', mfOKButton);
  Check(ButtonAt(cmOK, 15, 6, 25, 8), 'the start of a button is cut towards zero: (41 - 10) / 2 is 15');
  Check(TextIs(3, 2, 39, 6, 'x'), 'the text of a dialog 41 cells wide ends at 39');

  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 9), 'only text', mfInformation);
  Check(Snap.Count = 1, 'a box without a button flag holds only its text');
  Check(Snap.Items[1].Kind = ikText, 'the only subview of a box without buttons is the text');
  Check(Snap.Title = 'Information', 'a box without buttons has its title');
end;

procedure TestRectPlacement;
begin
  ArmCommand(cmOK);
  MessageBoxRect(Rc(5, 4, 45, 13), 'placed', mfOKCancel);
  Check(RectIs(Snap.Bounds, 5, 4, 45, 13), 'the dialog is at the rectangle that was given');
  Check(ButtonAt(cmOK, 9, 6, 19, 8), 'the buttons are placed in the coordinates of the dialog');
  Check(TextIs(3, 2, 38, 6, 'placed'), 'the text is placed in the coordinates of the dialog');

  ArmCommand(cmOK);
  MessageBoxRect(Rc(0, 0, 40, 13), 'tall', mfOKButton);
  Check(TextIs(3, 2, 38, 10, 'tall'), 'the text of a tall dialog ends 3 rows above the bottom');
  Check(ButtonAt(cmOK, 15, 10, 25, 12), 'the buttons of a tall dialog are 3 rows above the bottom');
end;

procedure TestFormattedRect;
var
  answer: Word;
begin
  ArmCommand(cmOK);
  answer := MessageBoxRect(Rc(0, 0, 30, 9), mfWarning or mfOKCancel, 'Item %d of %s', [7, 'ten']);
  Check(answer = cmOK, 'the formatted MessageBoxRect answers the command that ended the dialog');
  Check(RectIs(Snap.Bounds, 0, 0, 30, 9), 'the formatted box has the rectangle that was given');
  Check(Snap.Title = 'Warning', 'the formatted box has the title of its class');
  Check(TextIs(3, 2, 28, 6, 'Item 7 of ten'), 'the text of the formatted box is the formatted text');
  Check(ButtonAt(cmOK, 4, 6, 14, 8), 'the ok button of a dialog 30 cells wide starts at (30 - 22) / 2');
  Check(ButtonAt(cmCancel, 16, 6, 26, 8), 'the cancel button of a dialog 30 cells wide');
end;

procedure TestMessageBox;
var
  answer: Word;
  ninetyNine, hundred, twoHundred: string;
begin
  ninetyNine := StringOfChar('a', 99);
  hundred := StringOfChar('b', 100);
  twoHundred := StringOfChar('c', 200);

  ArmCommand(cmOK);
  answer := MessageBox('Short message', mfInformation or mfOKButton);
  Check(answer = cmOK, 'MessageBox answers the command that ended the dialog');
  Check(RectIs(Snap.Bounds, 10, 5, 50, 14), 'a short text gives a box of 40 by 9 centred in the desktop');
  Check(Snap.Title = 'Information', 'MessageBox gives the title of its class');
  Check(TextIs(3, 2, 38, 6, 'Short message'), 'the text of MessageBox');
  Check(ButtonAt(cmOK, 15, 6, 25, 8), 'the button of MessageBox');

  ArmCommand(cmYes);
  answer := MessageBox('Question', mfConfirmation or mfYesNoCancel);
  Check(answer = cmYes, 'MessageBox answers cmYes when the dialog ends with cmYes');

  ArmCommand(cmOK);
  MessageBox(ninetyNine, mfOKButton);
  Check(RectIs(Snap.Bounds, 10, 5, 50, 14), 'a text of 99 columns still fits the box of 9 rows');

  ArmCommand(cmOK);
  MessageBox(hundred, mfOKButton);
  Check(RectIs(Snap.Bounds, 10, 5, 50, 15), 'a text of 100 columns needs 100 / 33 + 6 + 1 = 10 rows');

  ArmCommand(cmOK);
  MessageBox(twoHundred, mfOKButton);
  Check(RectIs(Snap.Bounds, 10, 3, 50, 16), 'a text of 200 columns needs 13 rows and the box is centred with (20 - 13) / 2');
  Check(TextIs(3, 2, 38, 10, twoHundred), 'the text of the tall box ends 3 rows above its bottom');
  Check(ButtonAt(cmOK, 15, 10, 25, 12), 'the button of the tall box is 3 rows above its bottom');
  Check(AppViewCount = BaseViewCount, 'the boxes are removed from the application');
end;

procedure TestFormattedMessageBox;
var
  answer: Word;
  hundred: string;
begin
  hundred := StringOfChar('d', 100);

  ArmCommand(cmOK);
  answer := MessageBox(mfInformation or mfOKButton, 'Copied %d files to %s', [3, 'disk']);
  Check(answer = cmOK, 'the formatted MessageBox answers the command that ended the dialog');
  Check(TextIs(3, 2, 38, 6, 'Copied 3 files to disk'), 'the formatted text is shown');
  Check(RectIs(Snap.Bounds, 10, 5, 50, 14), 'the formatted box is centred in the desktop');
  Check(Snap.Title = 'Information', 'the formatted box has the title of its class');

  ArmCommand(cmOK);
  MessageBox(mfError or mfOKButton, '%s', [hundred]);
  Check(RectIs(Snap.Bounds, 10, 5, 50, 15), 'the height of the formatted box follows the formatted text');
  Check(TextIs(3, 2, 38, 7, hundred), 'the text of the formatted box is the formatted text, not the format');

  ArmCommand(cmNo);
  answer := MessageBox(mfWarning or mfYesNoCancel, 'Delete %d?', [2]);
  Check(answer = cmNo, 'the formatted MessageBox answers cmNo when the dialog ends with cmNo');
  Check(Snap.Count = 4, 'the formatted box has its three buttons');
end;

procedure TestInputBox;
var
  answer: Word;
  entryPosition, labelPosition: Integer;
begin
  InputLineHook := @MakeFakeInput;

  ResetFake;
  FillBuffer('initial');
  App.DuringModal := @TypeEdited;
  ArmCommand(cmOK);
  answer := InputBox('Rename', 'Name:', @Buf[0], 20);
  App.DuringModal := nil;
  Check(answer = cmOK, 'InputBox answers the command that ended the dialog');
  Check(MakerCalls = 1, 'the input line is made once');
  Check(MakerLimit = 20, 'the input line is made with the limit');
  Check(RectIs(MakerBounds, 9, 2, 57, 3), 'the input line is made at (4 + label length, 2) to (width - 3, 3)');
  Check(RectIs(Snap.Bounds, 0, 6, 60, 14), 'the dialog of InputBox is 60 by 8 and centred in the desktop');
  Check(Snap.Title = 'Rename', 'the dialog has the title that was given');
  Check(Snap.Modal, 'the input dialog is modal while it runs');
  Check(Snap.Count = 4, 'the input dialog has an input line, a label and two buttons');
  entryPosition := FindKind(ikInput);
  labelPosition := FindKind(ikLabel);
  Check((entryPosition <> 0) and RectIs(Snap.Items[entryPosition].Bounds, 9, 2, 57, 3),
    'the input line is in the dialog at its rectangle');
  Check((labelPosition <> 0) and RectIs(Snap.Items[labelPosition].Bounds, 2, 2, 8, 3),
    'the label is at (2, 2) to (3 + label length, 3)');
  Check((labelPosition <> 0) and (Snap.Items[labelPosition].Text = 'Name:'), 'the label has the text that was given');
  Check((labelPosition <> 0) and (entryPosition <> 0) and (Snap.Items[labelPosition].Link <> nil) and
    (Snap.Items[labelPosition].Link = Snap.Items[entryPosition].Ref), 'the label is linked to the input line');
  Check(ButtonAt(cmOK, 36, 4, 46, 6), 'the ok button is at (width - 24, height - 4)');
  Check(ButtonAt(cmCancel, 48, 4, 58, 6), 'the cancel button is 12 cells right of the ok button');
  Check((ButtonTitle(cmOK) = 'O~K~') and (ButtonTitle(cmCancel) = '~C~ancel'), 'the buttons have the texts of MsgBoxText');
  Check(ButtonFlags(cmOK) = bfDefault, 'the ok button is the default button');
  Check(ButtonFlags(cmCancel) = bfNormal, 'the cancel button is a normal button');
  Check(FakeSetCalls = 1, 'the data of the dialog was set once');
  Check(FakeSeenData = 'initial', 'the input line got the text of the buffer');
  Check(FakeGetCalls = 1, 'the data of the dialog was read once after an answer other than cmCancel');
  Check(BufferText = 'edited', 'the buffer holds the text that the input line gave');
  Check(AppViewCount = BaseViewCount, 'the input dialog is removed from the application');

  ResetFake;
  FillBuffer('initial');
  App.DuringModal := @TypeEdited;
  ArmCommand(cmCancel);
  answer := InputBox('Rename', 'Name:', @Buf[0], 20);
  App.DuringModal := nil;
  Check(answer = cmCancel, 'InputBox answers cmCancel when the dialog is cancelled');
  Check(FakeSetCalls = 1, 'the data was set before the loop of a cancelled dialog');
  Check(FakeGetCalls = 0, 'the data of a cancelled dialog is not read');
  Check(BufferText = 'initial', 'the buffer of a cancelled dialog is not changed');

  ResetFake;
  FillBuffer('initial');
  App.DuringModal := @TypeEdited;
  ArmKey(kbEsc);
  answer := InputBox('Rename', 'Name:', @Buf[0], 20);
  App.DuringModal := nil;
  Check(answer = cmCancel, 'the key Esc cancels the input dialog');
  Check((FakeGetCalls = 0) and (BufferText = 'initial'), 'Esc leaves the buffer as it was');

  ResetFake;
  FillBuffer('initial');
  App.DuringModal := @TypeEdited;
  ArmCommand(cmNo);
  answer := InputBox('Rename', 'Name:', @Buf[0], 20);
  App.DuringModal := nil;
  Check(answer = cmNo, 'InputBox answers cmNo when the dialog ends with cmNo');
  Check((FakeGetCalls = 1) and (BufferText = 'edited'), 'every answer but cmCancel reads the data');

  ResetFake;
  FillBuffer('initial');
  FakeContent := 'other';
  ArmCommand(cmOK);
  answer := InputBoxRect(Rc(5, 3, 45, 12), 'T', 'L', @Buf[0], 7);
  Check(answer = cmOK, 'InputBoxRect answers the command that ended the dialog');
  Check(RectIs(Snap.Bounds, 5, 3, 45, 12), 'the dialog of InputBoxRect has the rectangle that was given');
  Check(Snap.Title = 'T', 'the title of InputBoxRect');
  Check(RectIs(MakerBounds, 5, 2, 37, 3), 'the input line of a dialog 40 wide ends at 37');
  Check(MakerLimit = 7, 'the limit of InputBoxRect reaches the input line');
  labelPosition := FindKind(ikLabel);
  Check((labelPosition <> 0) and RectIs(Snap.Items[labelPosition].Bounds, 2, 2, 4, 3) and
    (Snap.Items[labelPosition].Text = 'L'), 'a label of one character is from 2 to 4');
  Check(ButtonAt(cmOK, 16, 5, 26, 7), 'the ok button of a dialog 40 by 9');
  Check(ButtonAt(cmCancel, 28, 5, 38, 7), 'the cancel button of a dialog 40 by 9');
  Check(BufferText = 'other', 'the buffer got the text of the input line');

  InputLineHook := nil;
  ResetFake;
  FillBuffer('initial');
  ArmCommand(cmOK);
  answer := InputBox('Rename', 'Name:', @Buf[0], 20);
  Check(answer = cmOK, 'InputBox without the hook answers the command that ended the dialog');
  Check(MakerCalls = 0, 'no input line is made without the hook');
  Check(Snap.Count = 3, 'the dialog has a label and two buttons without the hook');
  Check(CountKind(ikInput) = 0, 'there is no input line without the hook');
  labelPosition := FindKind(ikLabel);
  Check((labelPosition <> 0) and (Snap.Items[labelPosition].Link = nil), 'the label has no link without the hook');
  Check(BufferText = 'initial', 'the buffer is not changed when no view holds its data');
  Check(AppViewCount = BaseViewCount, 'the dialog without the input line is removed from the application');
end;

procedure TestEnd;
begin
  Check(StrayReads = 0, 'no dialog asked for an event that the test did not arm');
end;

begin
  TestConstants;

  Fake := TFakeScreen.Create;
  Fake.Cols := ScrW;
  Fake.Rows := ScrH;
  Fake.Mode := TDisplay.smCO80;
  SavedScreen := TDisplay.Backend;
  TDisplay.Backend := Fake;
  FakeEvents := TFakeEvents.Create;
  SavedEvents := TEventQueue.Backend;
  TEventQueue.Backend := FakeEvents;
  CaretPositionHook := @OnCaret;
  ScreenWriteHook := @OnScreenWrite;

  DrainPosted;
  App := TMsgApp.Create;

  TestSetup;
  TestRectYesNoCancel;
  TestAnswers;
  TestTitles;
  TestButtonRows;
  TestRectPlacement;
  TestFormattedRect;
  TestMessageBox;
  TestFormattedMessageBox;
  TestInputBox;
  TestEnd;

  TvObject.DestroyObject(App);
  TAppInit.Shutdown;
  ScreenWriteHook := nil;
  CaretPositionHook := nil;
  TEventQueue.Backend := SavedEvents;
  FakeEvents.Free;
  TDisplay.Backend := SavedScreen;
  Fake.Free;
  Done;
end.
