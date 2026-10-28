{ Test program of the unit TvDosNames. }
program t_dosnames;

{$mode objfpc}
{$H+}

uses
  SysUtils, TvCodePages, TvUtf8, TvDosNames;

{$I testlib.inc}

const
  PrivetPage = #$8F#$E0#$A8#$A2#$A5#$E2;
  PrivetUtf8 = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;
  JapaneseUtf8 = #$E6#$97#$A5#$E6#$9C#$AC#$E8#$AA#$9E;
  JapaneseEscapes = '{U+65E5}{U+672C}{U+8A9E}';
  SunUtf8 = #$E6#$97#$A5;
  Stray = #$FF#$FE'a';

procedure SetFlags(Utf8Mode, DosUtf8, Provider: Boolean);
begin
  Utf8Enabled := Utf8Mode;
  NamesUtf8 := DosUtf8;
  NamesProvider := Provider;
end;

var
  Provider: Boolean;
  Mode: Integer;

begin
  Check(CpSelect(866), 'page 866 is selectable');
  Utf8Enabled := False;
  NamesMapped := False;
  NamesProvider := False;

  { Section 5, 1: flag off }
  NamesUtf8 := False;
  Check(DosNameToUtf8(PrivetPage) = PrivetPage, 'off: DosNameToUtf8 keeps the page form');
  Check(DosNameToUtf8(PrivetUtf8) = PrivetUtf8, 'off: DosNameToUtf8 keeps the UTF-8 form');
  Check(DosNameFromUtf8(PrivetPage) = PrivetPage, 'off: DosNameFromUtf8 keeps the page form');
  Check(DosNameFromUtf8(PrivetUtf8) = PrivetUtf8, 'off: DosNameFromUtf8 keeps the UTF-8 form');
  Check(DosNameToUtf8('{U+65E5}') = '{U+65E5}', 'off: an escape is not converted');
  Check(DosNameFromUtf8('a{U+x}') = 'a{U+x}', 'off: a brace is not protected');

  { Section 5, 2: examples of 3.2 }
  NamesUtf8 := True;
  Check(DosNameToUtf8(PrivetPage) = PrivetUtf8, 'to UTF-8: Privet');
  Check(DosNameToUtf8('readme.txt') = 'readme.txt', 'to UTF-8: ASCII name unchanged');
  Check(DosNameToUtf8(PrivetPage + '.txt') = PrivetUtf8 + '.txt', 'to UTF-8: Privet with extension');
  Check(DosNameToUtf8(JapaneseEscapes) = JapaneseUtf8, 'to UTF-8: three escapes');
  Check(DosNameToUtf8(PrivetPage + '{U+65E5}') = PrivetUtf8 + SunUtf8, 'to UTF-8: page text and an escape');
  Check(DosNameToUtf8('a{U+007B}U+x}') = 'a{U+x}', 'to UTF-8: the escaped brace');
  Check(DosNameToUtf8('') = '', 'to UTF-8: empty name');

  { examples of 3.3 }
  Check(DosNameFromUtf8(PrivetUtf8) = PrivetPage, 'from UTF-8: Privet');
  Check(DosNameFromUtf8('readme.txt') = 'readme.txt', 'from UTF-8: ASCII name unchanged');
  Check(DosNameFromUtf8(JapaneseUtf8) = JapaneseEscapes, 'from UTF-8: Japanese gives escapes');
  Check(DosNameFromUtf8(PrivetUtf8 + JapaneseUtf8) = PrivetPage + JapaneseEscapes,
    'from UTF-8: Privet and Japanese');
  Check(DosNameFromUtf8('a{U+x}') = 'a{U+007B}U+x}', 'from UTF-8: a brace before U+ is escaped');
  Check(DosNameFromUtf8(Stray) = Stray, 'from UTF-8: stray bytes are copied');
  Check(DosNameFromUtf8('') = '', 'from UTF-8: empty name');
  Check(DosNameFromUtf8(PrivetUtf8 + '.txt') = PrivetPage + '.txt', 'from UTF-8: Privet with extension');
  Check(DosNameFromUtf8(PrivetUtf8 + #$FF) = PrivetPage + #$FF, 'from UTF-8: a stray byte after text');
  Check(DosNameFromUtf8('{x}') = '{x}', 'from UTF-8: a brace without U+ is copied');

  { round trips }
  Check(DosNameFromUtf8(DosNameToUtf8(PrivetPage)) = PrivetPage, 'round trip: page name');
  Check(DosNameToUtf8(DosNameFromUtf8(PrivetUtf8)) = PrivetUtf8, 'round trip: UTF-8 name');
  Check(DosNameFromUtf8(DosNameToUtf8(PrivetPage + JapaneseEscapes)) = PrivetPage + JapaneseEscapes,
    'round trip: page name with escapes');
  Check(DosNameToUtf8(DosNameFromUtf8(PrivetUtf8 + JapaneseUtf8)) = PrivetUtf8 + JapaneseUtf8,
    'round trip: UTF-8 name with Japanese');
  Check(DosNameFromUtf8(DosNameToUtf8('a{U+007B}U+x}')) = 'a{U+007B}U+x}', 'round trip: escaped brace');

  { Section 5, 3: escape boundaries }
  Check(DosNameToUtf8('{U+0041}') = 'A', 'escape of an ASCII character');
  Check(DosNameToUtf8('{U+004}') = '{U+004}', 'three digits are plain text');
  Check(DosNameToUtf8('{U+1234567}') = '{U+1234567}', 'seven digits are plain text');
  Check(DosNameToUtf8('{U+110000}') = '{U+110000}', 'a value above 10FFFF is plain text');
  Check(DosNameToUtf8('{U+12G4}') = '{U+12G4}', 'a non-hex character is plain text');
  Check(DosNameToUtf8('{U+1234') = '{U+1234', 'no closing brace is plain text');
  Check(DosNameToUtf8('{U+01F600}') = #$F0#$9F#$98#$80, 'six digits');
  Check(DosNameToUtf8('{U+65e5}') = SunUtf8, 'lower-case hexadecimal');
  Check(DosNameToUtf8('{u+0041}') = '{u+0041}', 'lower-case u is not an escape');
  Check(DosNameToUtf8('{U+10FFFF}') = #$F4#$8F#$BF#$BF, 'the largest value is an escape');
  Check(DosNameToUtf8('{U+') = '{U+', 'an opening alone is plain text');

  { Section 5, 4 }
  Check(DosNameFromUtf8(#$F0#$9F#$98#$80) = '{U+1F600}', 'character outside the BMP');
  Check(DosNameFromUtf8('{U+') = '{U+007B}U+', 'opening at the end of the text');
  Check(DosNameFromUtf8('{U') = '{U', 'a brace and U at the end are copied');

  { Section 5, 5: the general pair }
  NamesMapped := False;
  for Mode := 0 to 7 do
  begin
    SetFlags((Mode and 1) <> 0, (Mode and 2) <> 0, (Mode and 4) <> 0);
    Check(NameToDos(PrivetUtf8) = PrivetUtf8,
      'not mapped: NameToDos is the identity, mode ' + IntToStr(Mode));
    Check(NameFromDos(JapaneseEscapes + PrivetPage) = JapaneseEscapes + PrivetPage,
      'not mapped: NameFromDos is the identity, mode ' + IntToStr(Mode));
  end;

  NamesMapped := True;
  for Mode := 0 to 1 do
  begin
    Provider := Mode = 1;
    { UTF-8 mode on, DOS in UTF-8 }
    SetFlags(True, True, Provider);
    Check(NameToDos(PrivetUtf8) = PrivetUtf8, 'UTF-8 both: NameToDos unchanged, provider ' + IntToStr(Mode));
    Check(NameFromDos(PrivetUtf8) = PrivetUtf8, 'UTF-8 both: NameFromDos unchanged, provider ' + IntToStr(Mode));
    Check(NameToDos('a{U+x}') = 'a{U+x}', 'UTF-8 both: braces unchanged, provider ' + IntToStr(Mode));
    { UTF-8 mode off }
    SetFlags(False, True, Provider);
    Check(NameToDos(PrivetPage) = PrivetUtf8, 'page program, UTF-8 DOS: NameToDos, provider ' + IntToStr(Mode));
    Check(NameFromDos(PrivetUtf8) = PrivetPage, 'page program, UTF-8 DOS: NameFromDos, provider ' + IntToStr(Mode));
    SetFlags(False, False, Provider);
    Check(NameToDos(PrivetPage) = PrivetPage, 'page both: NameToDos unchanged, provider ' + IntToStr(Mode));
    Check(NameFromDos(PrivetPage) = PrivetPage, 'page both: NameFromDos unchanged, provider ' + IntToStr(Mode));
  end;

  { UTF-8 program, page DOS, no provider }
  SetFlags(True, False, False);
  Check(NameToDos(PrivetUtf8) = PrivetPage, 'no provider: NameToDos of Privet');
  Check(NameFromDos(PrivetPage) = PrivetUtf8, 'no provider: NameFromDos of Privet');
  Check(NameToDos(JapaneseUtf8) = '___', 'no provider: one underscore per character');
  Check(NameFromDos('{U+65E5}') = '{U+65E5}', 'no provider: an escape is plain text');
  Check(NameToDos('{U+x}') = '{U+x}', 'no provider: a brace is not protected');
  Check(NameToDos(PrivetUtf8 + #$FF + 'a') = PrivetPage + #$FF + 'a', 'no provider: a stray byte is copied');

  { UTF-8 program, page DOS, provider }
  SetFlags(True, False, True);
  Check(NameToDos(JapaneseUtf8) = JapaneseEscapes, 'provider: NameToDos of Japanese');
  Check(NameToDos('a' + JapaneseUtf8 + '.txt') = 'a' + JapaneseEscapes + '.txt', 'provider: Japanese in a name');
  Check(NameFromDos(JapaneseEscapes) = JapaneseUtf8, 'provider: NameFromDos of escapes');
  Check(NameFromDos(PrivetPage + '{U+65E5}') = PrivetUtf8 + SunUtf8, 'provider: page text and an escape');
  Check(NameFromDos(NameToDos(PrivetUtf8 + JapaneseUtf8)) = PrivetUtf8 + JapaneseUtf8, 'provider: round trip');
  Check(NameToDos('{U+x}') = '{U+007B}U+x}', 'provider: NameToDos protects the brace');
  Check(NameFromDos('{U+007B}U+x}') = '{U+x}', 'provider: NameFromDos restores the brace');
  Check(NameFromDos('{U+12}') = '{U+12}', 'provider: fewer than four digits');
  Check(NameFromDos('{U+110000}') = '{U+110000}', 'provider: value above 10FFFF');
  Check(NameToDos(#$F0#$9F#$98#$80) = '{U+1F600}', 'provider: a character outside the BMP');
  Check(NameToDos('') = '', 'provider: empty name to DOS');
  Check(NameFromDos('') = '', 'provider: empty name from DOS');

  { UTF-8 mode off }
  SetFlags(False, True, False);
  Check(NameToDos(PrivetPage) = PrivetUtf8, 'mode off, UTF-8 DOS: NameToDos');
  SetFlags(False, False, False);
  Check(NameToDos(PrivetPage) = PrivetPage, 'mode off, page DOS: NameToDos');
  Check(NameFromDos(PrivetPage) = PrivetPage, 'mode off, page DOS: NameFromDos');

  { Section 5, 6: order }
  NamesUtf8 := True;
  Check(DosNameFromUtf8(JapaneseUtf8 + PrivetUtf8 + SunUtf8) = JapaneseEscapes + PrivetPage + '{U+65E5}',
    'order in DosNameFromUtf8');
  SetFlags(True, False, True);
  Check(NameToDos(JapaneseUtf8 + PrivetUtf8 + SunUtf8) = JapaneseEscapes + PrivetPage + '{U+65E5}',
    'order in NameToDos');
  Check(NameFromDos(JapaneseEscapes + PrivetPage + '{U+65E5}') = JapaneseUtf8 + PrivetUtf8 + SunUtf8,
    'order in NameFromDos');

  Utf8Enabled := False;
  NamesMapped := False;
  NamesUtf8 := False;
  NamesProvider := False;
  Done;
end.
