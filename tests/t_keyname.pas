{ Test program of the unit TvKeyName. }
program t_keyname;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  SysUtils, TvKeys, TvKeyName;

{$I testlib.inc}

const
  RowCount = 29;

type
  TRow = record
    Name: string;
    Code: Word;
  end;

const
  Rows: array[0..RowCount - 1] of TRow = (
    (Name: 'Esc'; Code: $011B), (Name: 'Backspace'; Code: $0E08), (Name: 'Tab'; Code: $0F09),
    (Name: 'Enter'; Code: $1C0D), (Name: 'Space'; Code: $0020), (Name: 'Home'; Code: $4700),
    (Name: 'Up'; Code: $4800), (Name: 'PageUp'; Code: $4900), (Name: 'Num-'; Code: $4A2D),
    (Name: 'F1'; Code: $3B00), (Name: 'F2'; Code: $3C00), (Name: 'F3'; Code: $3D00),
    (Name: 'F4'; Code: $3E00), (Name: 'F5'; Code: $3F00), (Name: 'F6'; Code: $4000),
    (Name: 'F7'; Code: $4100), (Name: 'F8'; Code: $4200), (Name: 'F9'; Code: $4300),
    (Name: 'F10'; Code: $4400), (Name: 'Left'; Code: $4B00), (Name: 'Right'; Code: $4D00),
    (Name: 'Num+'; Code: $4E2B), (Name: 'End'; Code: $4F00), (Name: 'Down'; Code: $5000),
    (Name: 'PageDown'; Code: $5100), (Name: 'Insert'; Code: $5200), (Name: 'Delete'; Code: $5300),
    (Name: 'F11'; Code: $8500), (Name: 'F12'; Code: $8600)
  );

function Key(ACode: Word; AMods: Word = 0): TKey;
begin
  Result := TKey.Create(ACode, AMods);
end;

procedure Name(const K: TKey; const Expected: string; const What: string);
begin
  Check(KeyToStr(K) = Expected, What + ' writes as "' + Expected + '", got "' + KeyToStr(K) + '"');
end;

{ The text reads as the key of Code and Mods. }
procedure Reads(const S: string; ACode: Word; AMods: Word = 0);
var
  K: TKey;
  Ok: Boolean;
begin
  Ok := StrToKey(S, K);
  Check(Ok, '"' + S + '" is a key');
  Check(K = Key(ACode, AMods), '"' + S + '" is the expected key');
end;

procedure Fails(const S: string);
var
  K: TKey;
begin
  K := Key(kbF5);
  Check(not StrToKey(S, K), '"' + S + '" is no key');
  Check(K.Code = kbNoKey, '"' + S + '" leaves no code');
  Check(K.Mods = 0, '"' + S + '" leaves no modifiers');
end;

procedure TestWriting;
var
  K: TKey;
begin
  Name(Key(kbF5), 'F5', 'F5');
  Name(Key(kbCtrlF5), 'Ctrl+F5', 'kbCtrlF5');
  K.Code := kbF5;
  K.Mods := kbCtrlShift or kbShift;
  Name(K, 'Ctrl+Shift+F5', 'F5 with Ctrl and Shift');
  Name(Key(kbAltEnter), 'Alt+Enter', 'kbAltEnter');
  Name(Key(kbCtrlA), 'Ctrl+A', 'kbCtrlA');
  Name(Key(kbAltQ), 'Alt+Q', 'kbAltQ');
  Name(Key(kbShiftTab), 'Shift+Tab', 'kbShiftTab');
  Name(Key(kbEsc), 'Esc', 'kbEsc');
  Name(Key(kbAlt5), 'Alt+5', 'kbAlt5');
  Name(Key(kbCtrlPgUp), 'Ctrl+PageUp', 'kbCtrlPgUp');
  Name(Key($002B), '+', 'the plus character');
  Name(Key(kbGrayPlus), 'Num+', 'kbGrayPlus');
  Name(Key(kbGrayMinus), 'Num-', 'kbGrayMinus');
  Name(Key(kbNoKey), '', 'kbNoKey');
  K.Code := kbNoKey;
  K.Mods := kbCtrlShift or kbAltShift;
  Name(K, '', 'no key with modifiers');
  Name(Key($FE00), 'Key $FE00', 'code FE00');
  Name(Key($FE00, kbCtrlShift), 'Ctrl+Key $FE00', 'code FE00 with Ctrl');
  K.Code := Ord('a');
  K.Mods := 0;
  Name(K, 'A', 'lower-case a');
  K.Code := $0020;
  Name(K, 'Space', 'the space code');
  K.Code := $0001;
  Name(K, 'Key $0001', 'a control code');
  K.Code := $00FF;
  Name(K, 'Key $00FF', 'a code of the high half');
  K.Code := $007F;
  Name(K, 'Key $007F', 'the delete character');
end;

procedure TestKeyCodes;
begin
  Check(KeyCodeToStr(kbAltF3) = 'Alt+F3', 'KeyCodeToStr(kbAltF3)');
  Check(KeyCodeToStr(kbCtrlF5) = 'Ctrl+F5', 'KeyCodeToStr(kbCtrlF5)');
  Check(KeyCodeToStr(kbAltEnter) = 'Alt+Enter', 'KeyCodeToStr(kbAltEnter)');
  Check(KeyCodeToStr(kbNoKey) = '', 'KeyCodeToStr(kbNoKey)');
  Check(KeyCodeToStr(kbCtrlA) = 'Ctrl+A', 'KeyCodeToStr(kbCtrlA)');
  Check(KeyCodeToStr(kbF5) = KeyToStr(Key(kbF5)), 'KeyCodeToStr agrees with KeyToStr');
end;

procedure TestReading;
var
  K: TKey;
begin
  Reads('F5', kbF5);
  Reads('ctrl+f5', kbCtrlF5);
  Reads('Ctrl-S', kbCtrlS);
  Reads('Ctrl+S', kbCtrlS);
  Reads('Alt+Shift+F10', kbF10, kbAltShift or kbShift);
  Reads('Ctrl++', $002B, kbCtrlShift);
  Reads('Ctrl--', $002D, kbCtrlShift);
  Reads('Num-', kbGrayMinus);
  Reads('Num+', kbGrayPlus);
  Reads('Del', kbDel);
  Reads('PgDn', kbPgDn);
  Reads('Return', kbEnter);
  Reads('Alt+a', kbAltA);
  Reads('Space', $0020);
  Reads('Key $FE00', $FE00);
  Fails('Hyper+X');
  Fails('');
  Fails('Ctrl+');
  K := Key(kbF5);
  Check(StrToKey('Ctrl+F5', K) and (K.Code = kbF5) and (K.Mods = kbCtrlShift), 'Ctrl+F5 fields');
  Check(StrToKey('Ctrl+Alt+Shift+F5', K), 'three modifiers');
  Check(K.Mods = (kbCtrlShift or kbAltShift or kbShift), 'three modifiers in the mask');
end;

procedure TestTable;
var
  I: Integer;
  Alias: string;
begin
  for I := 0 to RowCount - 1 do
  begin
    Check(KeyCodeToStr(Rows[I].Code) = Rows[I].Name, 'code to name of ' + Rows[I].Name);
    Check(KeyToStr(Key(Rows[I].Code)) = Rows[I].Name, 'key to name of ' + Rows[I].Name);
    Reads(Rows[I].Name, Rows[I].Code);
    Reads(UpperCase(Rows[I].Name), Rows[I].Code);
    Reads(LowerCase(Rows[I].Name), Rows[I].Code);
    Reads(' ' + Rows[I].Name + ' ', Rows[I].Code);
  end;
  Reads('Escape', kbEsc);
  Reads('Return', kbEnter);
  Reads('BkSp', kbBack);
  Reads('Ins', kbIns);
  Reads('Del', kbDel);
  Reads('PgUp', kbPgUp);
  Reads('PgDn', kbPgDn);
  Reads('Plus', kbGrayPlus);
  Reads('Minus', kbGrayMinus);
  Reads('Spacebar', $0020);
  Reads('PrtSc', kbCtrlPrtSc);
  Alias := 'escape';
  Reads(Alias, kbEsc);
  Reads('PGUP', kbPgUp);
  Reads('bksp', kbBack);
  Reads('SPACEBAR', $0020);
  Reads('prtsc', kbCtrlPrtSc);
  { the aliases are never written }
  Check(KeyCodeToStr(kbEsc) = 'Esc', 'Esc is written, not Escape');
  Check(KeyCodeToStr(kbDel) = 'Delete', 'Delete is written, not Del');
  Check(KeyCodeToStr(kbGrayPlus) = 'Num+', 'Num+ is written, not Plus');
  { the keypad keys are not the printable ones }
  Reads('+', $002B);
  Reads('-', $002D);
  Check(Key(kbGrayPlus) <> Key($002B), 'Num+ differs from +');
  Check(Key(kbGrayMinus) <> Key($002D), 'Num- differs from -');
end;

procedure TestModifiers;
var
  M: Word;
  Expected: string;
  K, K2: TKey;
begin
  for M := 0 to 7 do
  begin
    Expected := '';
    K.Code := kbF5;
    K.Mods := 0;
    if (M and 1) <> 0 then
    begin
      Expected := Expected + 'Ctrl+';
      K.Mods := K.Mods or kbCtrlShift;
    end;
    if (M and 2) <> 0 then
    begin
      Expected := Expected + 'Alt+';
      K.Mods := K.Mods or kbAltShift;
    end;
    if (M and 4) <> 0 then
    begin
      Expected := Expected + 'Shift+';
      K.Mods := K.Mods or kbShift;
    end;
    Expected := Expected + 'F5';
    Name(K, Expected, 'F5 with the modifier set ' + IntToStr(M));
    Check(StrToKey(Expected, K2) and (K2 = K), 'F5 with the modifier set ' + IntToStr(M) + ' reads back');
  end;
  Check(StrToKey('Shift+Alt+Ctrl+F5', K) and StrToKey('Ctrl+Alt+Shift+F5', K2) and (K = K2),
    'the order of the modifiers does not matter');
  Check(StrToKey('Ctrl + F5', K) and (K = Key(kbCtrlF5)), 'spaces around the plus');
  Check(StrToKey('  Ctrl  +  Alt  +  F5  ', K) and (K = Key(kbF5, kbCtrlShift or kbAltShift)), 'many spaces');
  Check(StrToKey('control+x', K) and (K = Key(Ord('X'), kbCtrlShift)), 'control+x');
  Check(StrToKey('CONTROL-X', K) and (K = Key(Ord('X'), kbCtrlShift)), 'CONTROL-X');
  Check(StrToKey('Ctrl+Ctrl+F5', K) and (K = Key(kbCtrlF5)), 'a repeated modifier');
  Check(StrToKey('ALT+SHIFT+tab', K) and (K = Key(kbTab, kbAltShift or kbShift)), 'upper-case modifiers');
  Check(StrToKey('Alt+Num-', K) and (K = Key(kbGrayMinus, kbAltShift)), 'Alt+Num-');
  Check(StrToKey('Ctrl+Key $0041', K) and (K = Key($0041, kbCtrlShift)), 'Ctrl+Key $0041');
end;

procedure TestPrintable;
var
  C: Integer;
  K: TKey;
  Up: Char;
  S: string;
begin
  for C := $21 to $7E do
  begin
    Up := UpCase(Chr(C));
    S := Chr(C);
    Check(KeyCodeToStr(Word(C)) = Up, 'writing of character ' + IntToStr(C));
    Check(StrToKey(S, K) and (K = Key(Ord(Up))), 'reading of character ' + IntToStr(C));
    Check(StrToKey('Ctrl+' + Up, K) and (K = Key(Ord(Up), kbCtrlShift)), 'reading of Ctrl and character ' + IntToStr(C));
    Check(StrToKey('Alt+' + S, K) and (K = Key(Ord(Up), kbAltShift)), 'reading of Alt and character ' + IntToStr(C));
  end;
  Check(StrToKey('a', K) and (K.Code = $0041), 'a reads as A');
  Check(StrToKey('+', K) and (K.Code = $002B) and (K.Mods = 0), 'plus alone');
  Check(StrToKey('-', K) and (K.Code = $002D) and (K.Mods = 0), 'minus alone');
  Reads('Alt+-', $002D, kbAltShift);
  Reads('Alt++', $002B, kbAltShift);
  Reads('Shift+Ctrl+-', $002D, kbShift or kbCtrlShift);
  { 0061 is written as A and so does not round trip }
  K.Code := $0061;
  K.Mods := 0;
  Check(StrToKey(KeyToStr(K), K) and (K.Code = $0041), 'lower-case code does not round trip');
end;

procedure TestRejects;
begin
  Fails('Hyper+X');
  Fails('');
  Fails('   ');
  Fails(#9);
  Fails('Ctrl+');
  Fails('Ctrl+Alt');
  Fails('Ctrl+Alt+');
  Fails('Key $');
  Fails('Key $0000');
  Fails('Key $ZZ');
  Fails('Key $12G');
  Fails('Key $-1');
  Fails('Ctrl+Key $0');
  Fails('F13');
  Fails('Foo');
  Fails('Ctrl+Foo');
  Fails('Ctrl+Hyper+F5');
  Fails('+Ctrl');
  Fails('--');
  Fails('Num');
  Fails(#1);
  Fails(#127);
  Fails(#200);
  Fails('Ctrl+' + #1);
  Fails('Ctrl+' + #200);
  Fails('PrintScreenX');
end;

procedure TestHex;
begin
  Reads('Key $FE00', $FE00);
  Reads('key $fe00', $FE00);
  Reads('KEY $00FF', $00FF);
  Reads('Key $1', $0001);
  Reads('Ctrl+Key $FE00', $FE00, kbCtrlShift);
  Check(Key($FE00) = Key($FE00, 0), 'plain key');
end;

procedure TestRoundTrip;
var
  I: Integer;
  M: Word;
  K, K2: TKey;
begin
  for I := 0 to RowCount - 1 do
    for M := 0 to 7 do
    begin
      K := Key(Rows[I].Code, ((M and 1) * kbCtrlShift) or (((M shr 1) and 1) * kbAltShift) or
        (((M shr 2) and 1) * kbShift));
      Check(StrToKey(KeyToStr(K), K2) and (K2 = K), 'round trip of ' + Rows[I].Name + ' with set ' + IntToStr(M));
    end;
  K := Key(kbHome, kbCtrlShift);
  Check(StrToKey(KeyToStr(K), K2) and (K2 = K), 'round trip of Ctrl+Home');
  K := Key(kbIns, kbShift);
  Check(StrToKey(KeyToStr(K), K2) and (K2 = K), 'round trip of Shift+Insert');
  Check(KeyToStr(Key(kbCtrlHome)) = 'Ctrl+Home', 'kbCtrlHome');
  Check(KeyToStr(Key(kbShiftIns)) = 'Shift+Insert', 'kbShiftIns');
  K := Key($FE00, kbAltShift);
  Check(StrToKey(KeyToStr(K), K2) and (K2 = K), 'round trip of Alt+Key $FE00');
  for I := $21 to $7E do
    if not (Chr(I) in ['a'..'z']) then
    begin
      K := Key(I, kbCtrlShift);
      Check(StrToKey(KeyToStr(K), K2) and (K2 = K), 'round trip of character ' + IntToStr(I));
    end;
end;

begin
  TestWriting;
  TestKeyCodes;
  TestReading;
  TestTable;
  TestModifiers;
  TestPrintable;
  TestRejects;
  TestHex;
  TestRoundTrip;
  Done;
end.
