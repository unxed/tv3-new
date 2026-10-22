{ Converts between a key (TKey) and its text such as 'Ctrl+Shift+F5'. }
unit TvKeyName;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  TvKeys;

{ The name of a key. A key without a name comes as "Key $XXXX"; kbNoKey as an empty text. }
function KeyToStr(const K: TKey): AnsiString;
function KeyCodeToStr(KeyCode: Word): AnsiString;
{ False when the text is no key; K is nothing then. }
function StrToKey(const S: AnsiString; out K: TKey): Boolean;

implementation

function KeyToStr(const K: TKey): AnsiString;
begin
  Result := '';
end;

function KeyCodeToStr(KeyCode: Word): AnsiString;
begin
  Result := '';
end;

function StrToKey(const S: AnsiString; out K: TKey): Boolean;
begin
  K.Code := kbNoKey;
  K.Mods := 0;
  Result := False;
end;

end.
