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

uses
  SysUtils;

type
  TNamedKey = record
    Name: string;
    Code: Word;
  end;

const
  NameCount = 29;
  AliasCount = 11;

  { the writing table, also the first reading table }
  KeyNames: array[0..NameCount - 1] of TNamedKey = (
    (Name: 'Esc'; Code: $011B),
    (Name: 'Backspace'; Code: $0E08),
    (Name: 'Tab'; Code: $0F09),
    (Name: 'Enter'; Code: $1C0D),
    (Name: 'Space'; Code: $0020),
    (Name: 'Home'; Code: $4700),
    (Name: 'Up'; Code: $4800),
    (Name: 'PageUp'; Code: $4900),
    (Name: 'Num-'; Code: $4A2D),
    (Name: 'F1'; Code: $3B00),
    (Name: 'F2'; Code: $3C00),
    (Name: 'F3'; Code: $3D00),
    (Name: 'F4'; Code: $3E00),
    (Name: 'F5'; Code: $3F00),
    (Name: 'F6'; Code: $4000),
    (Name: 'F7'; Code: $4100),
    (Name: 'F8'; Code: $4200),
    (Name: 'F9'; Code: $4300),
    (Name: 'F10'; Code: $4400),
    (Name: 'Left'; Code: $4B00),
    (Name: 'Right'; Code: $4D00),
    (Name: 'Num+'; Code: $4E2B),
    (Name: 'End'; Code: $4F00),
    (Name: 'Down'; Code: $5000),
    (Name: 'PageDown'; Code: $5100),
    (Name: 'Insert'; Code: $5200),
    (Name: 'Delete'; Code: $5300),
    (Name: 'F11'; Code: $8500),
    (Name: 'F12'; Code: $8600)
  );

  { names that are only read }
  KeyAliases: array[0..AliasCount - 1] of TNamedKey = (
    (Name: 'Escape'; Code: kbEsc),
    (Name: 'Return'; Code: kbEnter),
    (Name: 'BkSp'; Code: kbBack),
    (Name: 'Ins'; Code: kbIns),
    (Name: 'Del'; Code: kbDel),
    (Name: 'PgUp'; Code: kbPgUp),
    (Name: 'PgDn'; Code: kbPgDn),
    (Name: 'Plus'; Code: kbGrayPlus),
    (Name: 'Minus'; Code: kbGrayMinus),
    (Name: 'Spacebar'; Code: $0020),
    (Name: 'PrtSc'; Code: kbCtrlPrtSc)
  );

  HexPrefix = 'KEY $';

function IsPrintable(Code: Word): Boolean;
begin
  Result := (Code > $20) and (Code < $7F);
end;

function KeyToStr(const K: TKey): AnsiString;
var
  I: Integer;
begin
  Result := '';
  if K.Code = kbNoKey then
    Exit;
  if (K.Mods and kbCtrlShift) <> 0 then
    Result := Result + 'Ctrl+';
  if (K.Mods and kbAltShift) <> 0 then
    Result := Result + 'Alt+';
  if (K.Mods and kbShift) <> 0 then
    Result := Result + 'Shift+';
  for I := 0 to NameCount - 1 do
    if KeyNames[I].Code = K.Code then
    begin
      Result := Result + KeyNames[I].Name;
      Exit;
    end;
  if IsPrintable(K.Code) then
    Result := Result + UpCase(Chr(K.Code))
  else
    Result := Result + 'Key $' + IntToHex(K.Code, 4);
end;

function KeyCodeToStr(KeyCode: Word): AnsiString;
begin
  Result := KeyToStr(TKey.Create(KeyCode));
end;

{ The code of a name of the tables, compared without regard to case; 0 when there is none. }
function CodeOfName(const Text: AnsiString): Word;
var
  I: Integer;
  Wanted: AnsiString;
begin
  Wanted := UpperCase(Text);
  for I := 0 to NameCount - 1 do
    if UpperCase(KeyNames[I].Name) = Wanted then
    begin
      Result := KeyNames[I].Code;
      Exit;
    end;
  for I := 0 to AliasCount - 1 do
    if UpperCase(KeyAliases[I].Name) = Wanted then
    begin
      Result := KeyAliases[I].Code;
      Exit;
    end;
  Result := 0;
end;

{ The mask of a modifier name, 0 when the text is none. }
function MaskOfName(const Text: AnsiString): Word;
var
  Wanted: AnsiString;
begin
  Wanted := UpperCase(Text);
  if (Wanted = 'CTRL') or (Wanted = 'CONTROL') then
    Result := kbCtrlShift
  else if Wanted = 'ALT' then
    Result := kbAltShift
  else if Wanted = 'SHIFT' then
    Result := kbShift
  else
    Result := 0;
end;

{ The position of the separator that ends the next prefix of Text, 0 when the text has none. }
function SeparatorAt(const Text: AnsiString): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 2 to Length(Text) do
    if (Text[I] = '+') or (Text[I] = '-') then
    begin
      if I < Length(Text) then
        Result := I;
      Exit;
    end;
end;

{ The value of the hexadecimal digits of Text (1 to 4 of them); -1 when the text is anything else. }
function HexValue(const Text: AnsiString): Integer;
var
  I, Digit: Integer;
begin
  Result := -1;
  if (Length(Text) < 1) or (Length(Text) > 4) then
    Exit;
  Result := 0;
  for I := 1 to Length(Text) do
  begin
    case Text[I] of
      '0'..'9': Digit := Ord(Text[I]) - Ord('0');
      'A'..'F': Digit := Ord(Text[I]) - Ord('A') + 10;
      'a'..'f': Digit := Ord(Text[I]) - Ord('a') + 10;
    else
      begin
        Result := -1;
        Exit;
      end;
    end;
    Result := Result * 16 + Digit;
  end;
end;

{ The code of a key text without modifiers; 0 when it is no key. }
function CodeOfText(const Text: AnsiString): Word;
var
  Value: Integer;
begin
  Result := CodeOfName(Text);
  if Result <> 0 then
    Exit;
  if Length(Text) = 1 then
  begin
    if IsPrintable(Ord(Text[1])) then
      Result := Ord(UpCase(Text[1]));
    Exit;
  end;
  if (Length(Text) > Length(HexPrefix)) and (UpperCase(Copy(Text, 1, Length(HexPrefix))) = HexPrefix) then
  begin
    Value := HexValue(Copy(Text, Length(HexPrefix) + 1, MaxInt));
    if Value > 0 then
      Result := Value;
  end;
end;

function StrToKey(const S: AnsiString; out K: TKey): Boolean;
var
  Rest: AnsiString;
  Mods, Mask: Word;
  Code: Word;
  At: Integer;
begin
  Result := False;
  Rest := Trim(S);
  Mods := 0;
  repeat
    At := SeparatorAt(Rest);
    if At = 0 then
      Break;
    Mask := MaskOfName(Trim(Copy(Rest, 1, At - 1)));
    if Mask = 0 then
      Break;
    Mods := Mods or Mask;
    Rest := Trim(Copy(Rest, At + 1, MaxInt));
  until False;
  if Rest <> '' then
  begin
    Code := CodeOfText(Rest);
    if Code <> 0 then
    begin
      K := TKey.Create(Code, Mods);
      Result := True;
    end;
  end;
  if not Result then
  begin
    K.Code := kbNoKey;
    K.Mods := 0;
  end;
end;

end.
