{ Test program of the unit TvActions. }
program t_actions;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  cthreads,
  Classes, SysUtils, TvKeys, TvEvents, TvViews, TvMenus, TvActions;

{$I testlib.inc}

const
  CmSaveAction = 200;
  CmOpenAction = 201;
  CmFindAction = 202;

function KeyEvent(KeyCode: Word; ControlState: Word = 0): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := KeyCode;
  Result.KeyDown.ControlKeyState := ControlState;
end;

procedure DeclareThree;
begin
  ClearActions;
  RegisterAction('file.save', '~S~ave', CmSaveAction, kbF2, 5);
  RegisterAction('file.open', '~O~pen', CmOpenAction, kbF3);
  RegisterAction('edit.find', '~F~ind', CmFindAction);
end;

procedure TestRegistry;
var
  Rec: TAction;
  Index: Integer;
begin
  ClearActions;
  Check(ActionCount = 0, 'the registry is empty after ClearActions');
  Check(FindAction('file.save') = -1, 'an empty registry finds no name');
  Check(ActionKeyConflicts = '', 'an empty registry has no conflicts');

  Index := RegisterAction('file.save', '~S~ave', CmSaveAction, kbF2, 5);
  Check(Index = 0, 'the first action has index 0');
  Index := RegisterAction('file.open', '~O~pen', CmOpenAction, kbF3);
  Check(Index = 1, 'the second action has index 1');
  Index := RegisterAction('edit.find', '~F~ind', CmFindAction);
  Check(Index = 2, 'the third action has index 2');
  Check(ActionCount = 3, 'three actions are counted');

  Check(FindAction('FILE.SAVE') = 0, 'FindAction ignores case');
  Check(FindAction('File.Open') = 1, 'FindAction ignores case for the second action');
  Check(FindAction('no.such') = -1, 'an unknown name gives -1');
  Check(FindActionByCommand(CmOpenAction) = 1, 'FindActionByCommand finds the command');
  Check(FindActionByCommand(9999) = -1, 'an unknown command gives -1');

  Rec := ActionAt(0);
  Check(Rec.Name = 'file.save', 'the name of action 0');
  Check(Rec.Caption = '~S~ave', 'the caption of action 0');
  Check(Rec.Command = CmSaveAction, 'the command of action 0');
  Check(Rec.Key = kbF2, 'the key of action 0');
  Check(Rec.DefaultKey = kbF2, 'the default key of action 0');
  Check(Rec.HelpCtx = 5, 'the help context of action 0');
  Rec := ActionAt(2);
  Check(Rec.Key = kbNoKey, 'an action declared without key has kbNoKey');
  Check(Rec.HelpCtx = hcNoContext, 'an action declared without help context has hcNoContext');

  Check(ActionKeyText(0) = 'F2', 'the key text of F2');
  Check(ActionKeyText(2) = '', 'the key text of kbNoKey is empty');
  Check(ActionKeyText(0) <> ActionKeyText(1), 'two keys have two texts');
end;

procedure TestMenuAndStatus;
var
  Item, Unknown: TMenuItem;
  Status, NoStatus: TStatusItem;
  Root: TMenu;
  StatusAnswer: Boolean;
begin
  DeclareThree;
  Unknown := NewActionItem('no.such', nil);
  Check(Unknown = nil, 'an unknown name makes no menu item and returns Next');
  Item := NewActionItem('file.save', Unknown);
  Check(Item <> nil, 'a menu item is made for a known name');
  Check(Item.Command = CmSaveAction, 'the menu item has the command');
  Check(Item.KeyCode = TKey.Create(kbF2), 'the menu item has the current key');
  Check(Item.Next = nil, 'the menu item is linked before Next');
  Check(Item.HelpCtx = 5, 'the menu item has the help context');
  Check(AnsiString(Item.Param) = 'F2', 'the menu item shows the key text');
  Check(AnsiString(Item.Name) = '~S~ave', 'the menu item has the caption');
  Root := TMenu.Create(Item);
  Root.Free;

  Item := NewActionItem('file.open', nil);
  Unknown := NewActionItem('no.such', Item);
  Check(Unknown = Item, 'an unknown name returns Next unchanged');
  Item := NewActionItem('edit.find', Unknown);
  Check(Item.Next <> nil, 'a menu item is linked before a non-empty Next');
  Check(Item.Next.Command = CmOpenAction, 'the linked item is the next item');
  Check(Item.KeyCode = TKey.Create(kbNoKey), 'an action without key gives an item without key');
  Root := TMenu.Create(Item);
  Root.Free;

  BindActionKey('file.save', kbF5);
  Item := NewActionItem('file.save', nil);
  Check(Item.KeyCode = TKey.Create(kbF5), 'the menu item takes the key now in force');
  Check(AnsiString(Item.Param) = 'F5', 'the menu item shows the key now in force');
  Root := TMenu.Create(Item);
  Root.Free;

  NoStatus := NewActionStatusKey('x', 'no.such', nil);
  Check(NoStatus = nil, 'an unknown name makes no status item');
  Status := NewActionStatusKey('~F2~ Save', 'file.open', nil);
  StatusAnswer := (Status <> nil) and (Status.Command = CmOpenAction) and
    (Status.KeyCode = TKey.Create(kbF3)) and (Status.Next = nil);
  Check(StatusAnswer, 'the status item has the key and the command of the action');
  Check(AnsiString(Status.Text) = '~F2~ Save', 'the status item has the text of the caller');
  NoStatus := NewActionStatusKey('y', 'no.such', Status);
  Check(NoStatus = Status, 'an unknown name returns ANext unchanged');
  Status.Free;
end;

procedure TestKeys;
var
  Event: TEvent;
  Other: TEvent;
begin
  DeclareThree;
  Event := KeyEvent(kbF3);
  Check(FindActionByKey(Event) = 1, 'FindActionByKey finds the action of F3');
  Check(ActionKeyToCommand(Event), 'a bound key becomes a command');
  Check(Event.What = evCommand, 'the event is a command event');
  Check(Event.Message.Command = CmOpenAction, 'the command is the one of the action');
  Check(Event.Message.InfoPtr = nil, 'InfoPtr is nil');

  Event := KeyEvent(kbF9);
  Check(FindActionByKey(Event) = -1, 'an unbound key finds no action');
  Check(not ActionKeyToCommand(Event), 'an unbound key is not converted');
  Check(Event.What = evKeyDown, 'an unbound key stays a key event');
  Check(Event.KeyDown.KeyCode = kbF9, 'an unbound key keeps its code');

  FillChar(Other, SizeOf(Other), 0);
  Other.What := evCommand;
  Other.Message.Command := CmOpenAction;
  Check(FindActionByKey(Other) = -1, 'a command event finds no action by key');
  Check(not ActionKeyToCommand(Other), 'a non-key event is not converted');
  Check(Other.What = evCommand, 'a non-key event is untouched');

  Event := KeyEvent(kbNoKey);
  Check(FindActionByKey(Event) = -1, 'kbNoKey matches nothing');

  Check(BindActionKey('file.open', kbF4), 'binding a known name gives True');
  Event := KeyEvent(kbF3);
  Check(FindActionByKey(Event) = -1, 'the old key is free after binding');
  Event := KeyEvent(kbF4);
  Check(ActionKeyToCommand(Event), 'the new key works');
  Check(Event.Message.Command = CmOpenAction, 'the new key gives the command');
  Check(ActionAt(1).DefaultKey = kbF3, 'binding leaves the default key');
  Check(not BindActionKey('no.such', kbF4), 'binding an unknown name gives False');
  Check(BindActionKey('FILE.OPEN', kbF6), 'binding ignores the case of the name');
  Check(ActionAt(1).Key = kbF6, 'the bound key is stored');

  ResetActionKeys;
  Check(ActionAt(1).Key = kbF3, 'ResetActionKeys restores the default key');
  Event := KeyEvent(kbF3);
  Check(ActionKeyToCommand(Event), 'the restored key works');
  Check(Event.Message.Command = CmOpenAction, 'the restored key gives the command');

  Check(BindActionKey('file.open', kbNoKey), 'unbinding gives True');
  Event := KeyEvent(kbF3);
  Check(FindActionByKey(Event) = -1, 'an unbound action frees its key');
  Check(ActionKeyText(1) = '', 'an unbound action has an empty key text');

  DeclareThree;
  Event := KeyEvent(kbCtrlF3);
  Check(FindActionByKey(Event) = -1, 'a modified key is not the plain key');
  Check(BindActionKey('edit.find', kbCtrlF3), 'the key with a modifier is bound');
  Event := KeyEvent(kbF3);
  Check(FindActionByKey(Event) = 1, 'the plain key still finds its action');
end;

procedure TestOrder;
var
  Event: TEvent;
begin
  ClearActions;
  RegisterAction('a.one', 'One', 301, kbF7);
  RegisterAction('a.two', 'Two', 302, kbF7);
  Event := KeyEvent(kbF7);
  Check(FindActionByKey(Event) = 0, 'the first of two actions on one key is found');
  Check(ActionKeyToCommand(Event), 'a key of two actions is converted');
  Check(Event.Message.Command = 301, 'the first action decides the command');
  Check(FindActionByCommand(302) = 1, 'the second command is found');
  RegisterAction('a.three', 'Three', 301, kbF8);
  Check(FindActionByCommand(301) = 0, 'the first of two actions with a command is found');
end;

procedure TestConflicts;
begin
  DeclareThree;
  Check(ActionKeyConflicts = '', 'no conflict at first');
  BindActionKey('edit.find', kbCtrlF3);
  Check(ActionKeyConflicts = '', 'no conflict with another key');
  BindActionKey('edit.find', kbF2);
  Check(ActionKeyConflicts = 'F2: file.save, edit.find' + #10, 'two actions on F2 conflict');

  Check(RegisterAction('edit.find', '~F~ind', CmFindAction, kbF5) = 2, 'redeclaring keeps the index');
  Check(ActionCount = 3, 'redeclaring does not add an action');
  Check(ActionKeyConflicts = '', 'redeclaring resets the key and removes the conflict');

  ClearActions;
  RegisterAction('a', 'A', 1, kbF7);
  RegisterAction('b', 'B', 2, kbF7);
  RegisterAction('c', 'C', 3, kbF7);
  Check(ActionKeyConflicts = 'F7: a, b, c' + #10, 'three actions on one key give one line');

  ClearActions;
  RegisterAction('x1', 'X1', 1, kbF7);
  RegisterAction('y1', 'Y1', 2, kbF8);
  RegisterAction('x2', 'X2', 3, kbF7);
  RegisterAction('y2', 'Y2', 4, kbF8);
  RegisterAction('n1', 'N1', 5);
  RegisterAction('n2', 'N2', 6);
  Check(ActionKeyConflicts = 'F7: x1, x2' + #10 + 'F8: y1, y2' + #10,
    'the lines follow the order of the first action of each key');

  ClearActions;
  RegisterAction('n1', 'N1', 5);
  RegisterAction('n2', 'N2', 6);
  Check(ActionKeyConflicts = '', 'actions without key do not conflict');

  ClearActions;
  RegisterAction('p', 'P', 1, kbCtrlF5);
  RegisterAction('q', 'Q', 2, kbCtrlF5);
  Check(Pos('Ctrl+F5: p, q', ActionKeyConflicts) = 1, 'the conflict line has the key text');
end;

procedure TestReregister;
var
  Rec: TAction;
begin
  DeclareThree;
  BindActionKey('file.open', kbF8);
  Check(ActionAt(1).Key = kbF8, 'the user key is in force');
  Check(RegisterAction('FILE.OPEN', '~O~pen file', 250, kbF3, 9) = 1, 'a redeclared name keeps its index');
  Rec := ActionAt(1);
  Check(Rec.Key = kbF3, 're-registering resets the user key');
  Check(Rec.DefaultKey = kbF3, 're-registering sets the default key');
  Check(Rec.Name = 'FILE.OPEN', 'the stored name is as given the last time');
  Check(Rec.Caption = '~O~pen file', 'the caption is overwritten');
  Check(Rec.Command = 250, 'the command is overwritten');
  Check(Rec.HelpCtx = 9, 'the help context is overwritten');
  Check(ActionCount = 3, 'the count is the same after re-registering');
  Check(FindAction('file.open') = 1, 'the redeclared action is found by any case');
end;

procedure TestSwitcher;
var
  Event: TEvent;
begin
  ClearActions;
  RegisterAction('window.switch', '~S~witch', cmNext, kbCtrlTab);
  RegisterAction('file.open', '~O~pen', CmOpenAction, kbF3);
  Event := KeyEvent(kbCtrlTab);
  Check(FindActionByKey(Event) = 0, 'before UseActionsForSwitcher the key of the action is found');
  Check(ActionKeyToCommand(Event), 'before UseActionsForSwitcher no action is excluded');
  Check(Event.Message.Command = cmNext, 'the switcher action converts like any other');

  UseActionsForSwitcher;
  Event := KeyEvent(kbCtrlTab);
  Check(not ActionKeyToCommand(Event), 'the key of the switcher action is not converted');
  Check(Event.What = evKeyDown, 'the key of the switcher action stays a key event');
  Check(Event.KeyDown.KeyCode = kbCtrlTab, 'the key of the switcher action is unchanged');
  Event := KeyEvent(kbF3);
  Check(ActionKeyToCommand(Event), 'another action is still converted');
  Check(Event.Message.Command = CmOpenAction, 'another action gives its command');

  Check(BindActionKey('window.switch', kbAltF6), 'the switcher action is rebound');
  Event := KeyEvent(kbAltF6);
  Check(not ActionKeyToCommand(Event), 'the new key of the switcher action is not converted');
  Event := KeyEvent(kbCtrlTab);
  Check(not ActionKeyToCommand(Event), 'the old key finds no action');

  UseActionsForSwitcher('WINDOW.SWITCH');
  Event := KeyEvent(kbAltF6);
  Check(not ActionKeyToCommand(Event), 'the switcher name is matched without regard to case');
  Event := KeyEvent(kbF3);
  Check(ActionKeyToCommand(Event), 'other actions are converted after a second choice of the name');

  ClearActions;
  Check(ActionCount = 0, 'ClearActions removes the switcher action too');
end;

begin
  TestRegistry;
  TestMenuAndStatus;
  TestKeys;
  TestOrder;
  TestConflicts;
  TestReregister;
  TestSwitcher;
  ClearActions;
  Check(ActionCount = 0, 'ClearActions gives an empty registry');
  Done;
end.
