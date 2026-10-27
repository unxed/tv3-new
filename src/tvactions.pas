{ The action registry. An action is declared once with a name, a menu caption, a command, a key and a help context.
  Menu items, status items, the translation of keys into commands, the rebinding of keys by the user and the search
  for two actions on one key all read the one table that this unit owns, in the order of registration.

  The routines are used by the thread of the user interface only; the table has no lock.

  The action of the window switcher is named by UseActionsForSwitcher. Its key is not turned into a command by
  ActionKeyToCommand, because the switcher of the desktop needs the modifiers that are held with it. }
unit TvActions;

{$mode objfpc}
{$modeswitch advancedrecords}

interface

uses
  TvKeys, TvEvents, TvViews, TvMenus;

type
  TAction = record
    Name: ShortString;
    Caption: ShortString;
    Command: Word;
    Key: Word;
    DefaultKey: Word;
    HelpCtx: Word;
  end;

function RegisterAction(const AName, ACaption: ShortString; ACommand: Word;
  AKey: Word = kbNoKey; AHelpCtx: Word = hcNoContext): Integer;
function ActionCount: Integer;
function ActionAt(Index: Integer): TAction;
function FindAction(const AName: ShortString): Integer;
function FindActionByCommand(ACommand: Word): Integer;
function FindActionByKey(const Event: TEvent): Integer;
function BindActionKey(const AName: ShortString; AKey: Word): Boolean;
procedure ResetActionKeys;
function ActionKeyText(Index: Integer): AnsiString;
function NewActionItem(const AName: ShortString; Next: TMenuItem): TMenuItem;
function NewActionStatusKey(const AText, AName: ShortString; ANext: TStatusItem): TStatusItem;
function ActionKeyToCommand(var Event: TEvent): Boolean;
function ActionKeyConflicts: AnsiString;
procedure ClearActions;
procedure UseActionsForSwitcher(const AName: ShortString = 'window.switch');

implementation

uses
  SysUtils, TvKeyName;

var
  { The table; only the first Used entries are in force. }
  Table: array of TAction;
  Used: Integer = 0;
  { The upper-cased name of the switcher action; empty while none is chosen. }
  SwitcherName: AnsiString = '';

function NameKey(const AName: ShortString): AnsiString;
begin
  Result := UpperCase(AnsiString(AName));
end;

{ True when both codes name the same key; kbNoKey is never the same as anything. }
function SameKey(CodeA, CodeB: Word): Boolean;
begin
  Result := False;
  if (CodeA = kbNoKey) or (CodeB = kbNoKey) then
    Exit;
  Result := TKey.Create(CodeA) = TKey.Create(CodeB);
end;

function IsSwitcherAction(Index: Integer): Boolean;
begin
  Result := (SwitcherName <> '') and (NameKey(Table[Index].Name) = SwitcherName);
end;

{ The answer for the hook of the desktop that asks whether a key-down starts or steps the switcher. The shift of the
  event is taken away before the comparison and tells the direction. }
function SwitcherKeyAnswer(const Event: TEvent; out Backward: Boolean): Boolean;
var
  ActionIndex: Integer;
  ActionKey: Word;
  PlainState: Word;
begin
  Result := False;
  Backward := False;
  if Event.What <> evKeyDown then
    Exit;
  ActionIndex := FindAction(SwitcherName);
  if ActionIndex < 0 then
    Exit;
  ActionKey := Table[ActionIndex].Key;
  if ActionKey = kbNoKey then
    Exit;
  PlainState := Event.KeyDown.ControlKeyState and Word($FFFF xor kbShift);
  if TKey.Create(Event.KeyDown.KeyCode, PlainState) <> TKey.Create(ActionKey) then
    Exit;
  Result := True;
  Backward := (Event.KeyDown.ControlKeyState and kbShift) <> 0;
end;

function RegisterAction(const AName, ACaption: ShortString; ACommand: Word;
  AKey: Word; AHelpCtx: Word): Integer;
var
  Entry: TAction;
begin
  Entry.Name := AName;
  Entry.Caption := ACaption;
  Entry.Command := ACommand;
  Entry.Key := AKey;
  Entry.DefaultKey := AKey;
  Entry.HelpCtx := AHelpCtx;
  Result := FindAction(AName);
  if Result >= 0 then
  begin
    Table[Result] := Entry;
    Exit;
  end;
  if Used = Length(Table) then
    SetLength(Table, Used * 2 + 8);
  Table[Used] := Entry;
  Result := Used;
  Inc(Used);
end;

function ActionCount: Integer;
begin
  Result := Used;
end;

function ActionAt(Index: Integer): TAction;
begin
  Result := Table[Index];
end;

function FindAction(const AName: ShortString): Integer;
var
  Wanted: AnsiString;
  Position: Integer;
begin
  Wanted := NameKey(AName);
  for Position := 0 to Used - 1 do
    if NameKey(Table[Position].Name) = Wanted then
    begin
      Result := Position;
      Exit;
    end;
  Result := -1;
end;

function FindActionByCommand(ACommand: Word): Integer;
var
  Position: Integer;
begin
  for Position := 0 to Used - 1 do
    if Table[Position].Command = ACommand then
    begin
      Result := Position;
      Exit;
    end;
  Result := -1;
end;

function FindActionByKey(const Event: TEvent): Integer;
var
  EventCode: TKey;
  Position: Integer;
begin
  Result := -1;
  if Event.What <> evKeyDown then
    Exit;
  EventCode := Event.KeyDown.ToKey;
  for Position := 0 to Used - 1 do
  begin
    if Table[Position].Key = kbNoKey then
      Continue;
    if TKey.Create(Table[Position].Key) = EventCode then
    begin
      Result := Position;
      Exit;
    end;
  end;
end;

function BindActionKey(const AName: ShortString; AKey: Word): Boolean;
var
  Position: Integer;
begin
  Position := FindAction(AName);
  Result := Position >= 0;
  if Result then
    Table[Position].Key := AKey;
end;

procedure ResetActionKeys;
var
  Position: Integer;
begin
  for Position := 0 to Used - 1 do
    Table[Position].Key := Table[Position].DefaultKey;
end;

function ActionKeyText(Index: Integer): AnsiString;
begin
  Result := KeyCodeToStr(Table[Index].Key);
end;

function NewActionItem(const AName: ShortString; Next: TMenuItem): TMenuItem;
var
  Position: Integer;
  Entry: TAction;
begin
  Result := Next;
  Position := FindAction(AName);
  if Position < 0 then
    Exit;
  Entry := Table[Position];
  Result := TMenuItem.Create(Entry.Caption, Entry.Command, TKey.Create(Entry.Key), Entry.HelpCtx,
    ActionKeyText(Position), Next);
end;

function NewActionStatusKey(const AText, AName: ShortString; ANext: TStatusItem): TStatusItem;
var
  Position: Integer;
  Entry: TAction;
begin
  Result := ANext;
  Position := FindAction(AName);
  if Position < 0 then
    Exit;
  Entry := Table[Position];
  Result := TStatusItem.Create(AText, TKey.Create(Entry.Key), Entry.Command, ANext);
end;

function ActionKeyToCommand(var Event: TEvent): Boolean;
var
  Position: Integer;
  TargetCommand: Word;
begin
  Result := False;
  Position := FindActionByKey(Event);
  if Position < 0 then
    Exit;
  if IsSwitcherAction(Position) then
    Exit;
  TargetCommand := Table[Position].Command;
  Event.What := evCommand;
  Event.Message.Command := TargetCommand;
  Event.Message.InfoPtr := nil;
  Result := True;
end;

function ActionKeyConflicts: AnsiString;
var
  First, Other: Integer;
  AlreadyListed: Boolean;
  Names: AnsiString;
  Members: Integer;
begin
  Result := '';
  for First := 0 to Used - 1 do
  begin
    if Table[First].Key = kbNoKey then
      Continue;
    AlreadyListed := False;
    for Other := 0 to First - 1 do
      if SameKey(Table[Other].Key, Table[First].Key) then
      begin
        AlreadyListed := True;
        Break;
      end;
    if AlreadyListed then
      Continue;
    Names := Table[First].Name;
    Members := 1;
    for Other := First + 1 to Used - 1 do
      if SameKey(Table[Other].Key, Table[First].Key) then
      begin
        Names := Names + ', ' + Table[Other].Name;
        Inc(Members);
      end;
    if Members >= 2 then
      Result := Result + ActionKeyText(First) + ': ' + Names + #10;
  end;
end;

procedure ClearActions;
begin
  SetLength(Table, 0);
  Used := 0;
end;

procedure UseActionsForSwitcher(const AName: ShortString);
begin
  SwitcherName := NameKey(AName);
end;

end.
