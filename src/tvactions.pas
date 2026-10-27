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

end.
