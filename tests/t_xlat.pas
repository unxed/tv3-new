{ Test program of the unit TvXlat. }
program t_xlat;

{$mode objfpc}

uses
  Classes, SysUtils, TvEvents, TvKeys, TvUtf8, TvXlat;

{$I testlib.inc}

const
  LayoutFileName = 't_xlat_layout.tmp';

{ The UTF-8 text of one code point. }
function U(CodePoint: LongWord): AnsiString;
var
  Bytes: TUtf8Bytes;
  Count, Index: SizeInt;
begin
  Count := Utf32To8(CodePoint, Bytes);
  SetLength(Result, Count);
  for Index := 0 to Count - 1 do
    Result[Index + 1] := Chr(Bytes[Index]);
end;

{ A key-down event with the given control key state and the UTF-8 of one code point as its text. }
procedure MakeKey(var Event: TEvent; State: Word; CodePoint: LongWord);
var
  Count: SizeInt;
begin
  FillChar(Event, SizeOf(Event), 0);
  Event.What := evKeyDown;
  Event.KeyDown.ControlKeyState := State;
  Count := Utf32To8(CodePoint, Event.KeyDown.Text);
  Event.KeyDown.TextLength := Byte(Count);
end;

procedure WriteLayoutFile(const Lines: array of AnsiString);
var
  Content: TStringList;
  Index: Integer;
begin
  Content := TStringList.Create;
  try
    for Index := 0 to High(Lines) do
      Content.Add(Lines[Index]);
    Content.SaveToFile(LayoutFileName);
  finally
    Content.Free;
  end;
end;

var
  Event: TEvent;
  BlankTen: AnsiString;

begin
  { The values of XlatLatin }
  Check(XlatLatin($0444) = Ord('a'), 'U+0444 is key a');
  Check(XlatLatin($044B) = Ord('s'), 'U+044B is key s');
  Check(XlatLatin($0419) = Ord('Q'), 'capital U+0419 is Q');
  Check(XlatLatin($0456) = Ord('s'), 'Ukrainian U+0456 is key s');
  Check(XlatLatin($0457) = Ord(']'), 'Ukrainian U+0457 is key ]');
  Check(XlatLatin($03B1) = Ord('a'), 'Greek alpha is key a');
  Check(XlatLatin(Ord('a')) = 0, 'a Latin letter gives 0');
  Check(XlatLatin(0) = 0, 'code point 0 gives 0');
  Check(XlatLatin($4000) = 0, 'an unknown code point gives 0');
  Check(XlatLatin($0439) = Ord('q'), 'Russian U+0439 is key q');
  Check(XlatLatin($044E) = Ord('.'), 'Russian U+044E is key period');
  Check(XlatLatin($0454) = Ord(''''), 'Ukrainian U+0454 is key apostrophe');
  Check(XlatLatin($0407) = Ord(']'), 'capital U+0407 is key ]');
  Check(XlatLatin($0459) = Ord('q'), 'Serbian U+0459 is key q');
  Check(XlatLatin($045A) = Ord('w'), 'Serbian U+045A is key w');
  Check(XlatLatin($03C9) = Ord('v'), 'Greek omega is key v');
  Check(XlatLatin($03C7) = Ord('x'), 'Greek chi is key x');
  Check(XlatLatin($03B6) = Ord('z'), 'Greek zeta is key z');
  Check(XlatLatin($03A3) = Ord('s'), 'Greek capital sigma gives the lower-case s');
  Check(XlatLatin($05E9) = Ord('a'), 'Hebrew shin is key a');
  Check(XlatLatin(Ord(';')) = 0, 'the ASCII semicolon of the Greek layout is inert');

  { Add with ASCII letters }
  XlatAdd('ABC');
  Check(XlatLatin(Ord('A')) = 0, 'XlatAdd of ASCII leaves XlatLatin(A) = 0');

  { XlatModded }
  MakeKey(Event, kbLeftAlt, $044B);
  Check(XlatModded(Event), 'Alt plus U+044B is translated');
  Check(Event.KeyDown.KeyCode = kbAltS, 'Alt plus U+044B becomes kbAltS');
  Check(Event.KeyDown.TextLength = 0, 'a translated shortcut has no text');
  Check(Event.KeyDown.ControlKeyState = kbLeftAlt, 'the control key state stays');

  MakeKey(Event, kbLeftCtrl, $043A);
  Check(XlatModded(Event), 'Ctrl plus U+043A is translated');
  Check(Event.KeyDown.KeyCode = kbCtrlR, 'Ctrl plus U+043A becomes kbCtrlR');

  MakeKey(Event, kbLeftCtrl or kbLeftAlt, $043A);
  Check(XlatModded(Event) and (Event.KeyDown.KeyCode = kbAltR), 'Ctrl and Alt together pick Alt');

  MakeKey(Event, kbLeftAlt or $0010, $0419);
  Check(XlatModded(Event) and (Event.KeyDown.KeyCode = kbAltQ), 'a capital letter is folded to lower case');

  MakeKey(Event, kbLeftAlt, $0457);
  Check(not XlatModded(Event), 'a punctuation key is not translated by XlatModded');
  Check(Event.KeyDown.TextLength = 2, 'a refused event keeps its text');

  MakeKey(Event, kbLeftAlt, Ord('a'));
  Check(not XlatModded(Event), 'a Latin letter with Alt is not translated');

  MakeKey(Event, kbLeftAlt, $4000);
  Check(not XlatModded(Event), 'an unknown character with Alt is not translated');

  MakeKey(Event, kbLeftAlt, $044B);
  Event.KeyDown.TextLength := 0;
  Check(not XlatModded(Event), 'an event with no text is not translated');

  MakeKey(Event, kbLeftAlt, $044B);
  Event.KeyDown.Text[0] := $FF;
  Check(not XlatModded(Event), 'an invalid UTF-8 text is not translated');

  MakeKey(Event, kbLeftAlt, $044B);
  Event.KeyDown.TextLength := 1;
  Check(not XlatModded(Event), 'a truncated UTF-8 character is not translated');

  MakeKey(Event, kbLeftAlt, $044B);
  Event.What := evMouseDown;
  Check(not XlatModded(Event), 'an event that is not a key-down is not translated');

  MakeKey(Event, 0, $043A);
  Check(not XlatModded(Event), 'a plain key is not translated by XlatModded');
  Check(Event.KeyDown.TextLength = 2, 'a plain key keeps its text after XlatModded');

  { XlatPlain }
  MakeKey(Event, 0, $043A);
  Check(XlatPlain(Event), 'a plain U+043A is translated');
  Check(Event.KeyDown.TextLength = 1, 'the translated text has length 1');
  Check(Event.KeyDown.Text[0] = Ord('r'), 'the translated text is r');
  Check(Event.KeyDown.CharScan.CharCode = Ord('r'), 'the translated char code is r');

  MakeKey(Event, kbLeftAlt, $044B);
  Check(not XlatPlain(Event), 'Alt plus U+044B is refused by XlatPlain');

  MakeKey(Event, kbLeftCtrl, $044B);
  Check(not XlatPlain(Event), 'Ctrl plus U+044B is refused by XlatPlain');

  MakeKey(Event, kbLeftAlt, $044B);
  Check(not XlatPlain(Event) and (Event.KeyDown.TextLength = 2), 'a refused XlatPlain leaves the event');

  MakeKey(Event, 0, $0419);
  Check(XlatPlain(Event) and (Event.KeyDown.Text[0] = Ord('Q')), 'a capital of a both-case layout gives upper case');

  MakeKey(Event, 0, $0457);
  Check(XlatPlain(Event) and (Event.KeyDown.Text[0] = Ord(']')), 'a punctuation key gives the punctuation character');

  MakeKey(Event, 0, $0391);
  Check(XlatPlain(Event) and (Event.KeyDown.Text[0] = Ord('a')), 'a Greek capital gives lower case');

  MakeKey(Event, 0, Ord('a'));
  Check(not XlatPlain(Event), 'a Latin letter is refused by XlatPlain');

  MakeKey(Event, 0, $4000);
  Check(not XlatPlain(Event), 'an unknown character is refused by XlatPlain');

  MakeKey(Event, 0, $043A);
  Event.KeyDown.TextLength := 0;
  Check(not XlatPlain(Event), 'an event with no text is refused by XlatPlain');

  MakeKey(Event, 0, $043A);
  Event.What := evMouseDown;
  Check(not XlatPlain(Event), 'an event that is not a key-down is refused by XlatPlain');

  { XlatEnabled }
  XlatEnabled := False;
  MakeKey(Event, kbLeftAlt, $044B);
  Check(not XlatModded(Event), 'XlatModded is False when disabled');
  MakeKey(Event, 0, $043A);
  Check(not XlatPlain(Event), 'XlatPlain is False when disabled');
  Check(XlatLatin($043A) = Ord('r'), 'XlatLatin ignores XlatEnabled');
  XlatEnabled := True;

  { XlatLoadFile }
  Check(not XlatLoadFile('t_xlat_no_such_file.tmp'), 'a missing file gives False');

  WriteLayoutFile([
    '# a comment line',
    U($04D0) + U($04D1) + '=xy # the rest is a comment',
    'a line without an equals sign',
    '=zzz',
    '  ' + U($04D4) + '  =  e  ',
    U($04D2) + '|' + U($04D3) + '=abc']);
  Check(XlatLoadFile(LayoutFileName), 'a layout file is loaded');
  Check(XlatLatin($04D0) = Ord('x'), 'file line pairs the first character');
  Check(XlatLatin($04D1) = Ord('y'), 'file line pairs the second character');
  Check(XlatLatin($04D4) = Ord('e'), 'file line is trimmed on both sides');
  Check(XlatLatin($04D2) = Ord('a'), 'a bar in a file is a layout character');
  Check(XlatLatin($04D3) = Ord('c'), 'the bar takes a position in a file');

  WriteLayoutFile(['nothing usable here', '# only a comment']);
  Check(XlatLoadFile(LayoutFileName), 'a file without usable lines still gives True');
  DeleteFile(LayoutFileName);

  { XlatAdd }
  XlatAdd(U($04E0) + U($04E1));
  Check((XlatLatin($04E0) = Ord('q')) and (XlatLatin($04E1) = Ord('w')), 'XlatAdd pairs by position');
  XlatAdd(U($04E1));
  Check(XlatLatin($04E1) = Ord('q'), 'the last added pair wins');
  XlatAdd(' ' + U($04E2));
  Check((XlatLatin($04E2) = Ord('w')) and (XlatLatin($04E1) = Ord('q')), 'a blank leaves its key without a character');
  XlatAdd(U($04F0) + '|' + U($04F1));
  Check(XlatLatin($04F0) = Ord('q'), 'the part before the bar uses the lower-case keys');
  Check(XlatLatin($04F1) = Ord('Q'), 'the part after the bar uses the upper-case keys');
  BlankTen := '          ';
  XlatAdd(BlankTen + U($04F2) + '|' + BlankTen + U($04F3));
  Check((XlatLatin($04F2) = Ord('[')) and (XlatLatin($04F3) = Ord('[')), 'punctuation keys are not changed by the bar');
  XlatAdd(' ' + U($0444));
  Check(XlatLatin($0444) = Ord('w'), 'an added layout overrides a built-in one');
  XlatAdd(AnsiString(#$FF#$FE));
  Check(XlatLatin($FF) = Ord('q'), 'an invalid byte counts as its own code point');

  Done;
end.
