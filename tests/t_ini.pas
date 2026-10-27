{ Test program of the unit TvIni. }
program t_ini;

{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}

uses
  SysUtils, TvIni;

{$I testlib.inc}

const
  LF = #10;
  CRLF = #13#10;
  Bom = #$EF#$BB#$BF;

  { Cyrillic key "Klyuch" in upper and lower case, UTF-8 }
  KeyUpper = #$D0#$9A#$D0#$9B#$D0#$AE#$D0#$A7;
  KeyLower = #$D0#$BA#$D0#$BB#$D1#$8E#$D1#$87;
  { a UTF-8 value of Cyrillic letters and a symbol }
  Utf8Value = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82#$E2#$82#$AC;

  BaseHead =
    '; a comment line' + LF +
    'Comment=Do NOT delete' + LF +
    LF +
    '[Files]' + LF +
    'OpenExts=''*.pas;*.pp'' ;the masks' + LF;
  BaseTail =
    '; between' + LF +
    'Name="it''s"' + LF +
    '[Other]' + LF +
    'Flag=1' + LF;
  BaseText = BaseHead + 'Count = 5' + LF + BaseTail;
  BaseTextCount6 = BaseHead + 'Count=6' + LF + BaseTail;

function NewBase: TIniFile;
begin
  Result := TIniFile.Create('');
  Result.LoadFromText(BaseText);
end;

procedure TestEntryParse;
var
  E: TIniEntry;
begin
  E := TIniEntry.Create('Key = val ;c');
  Check(E.IsEntry, 'entry: plain line is an entry');
  Check(E.GetTag = 'Key', 'entry: tag is trimmed');
  Check(E.GetValue = 'val', 'entry: unquoted value is trimmed');
  Check(E.GetComment = 'c', 'entry: comment is the text after the semicolon');
  Check(E.GetText = 'Key = val ;c', 'entry: unchanged line gives its original text');
  E.Free;

  E := TIniEntry.Create('Key=v ; c d');
  Check(E.GetComment = ' c d', 'entry: a leading space of the comment is part of it');
  E.Free;

  E := TIniEntry.Create('; a=b');
  Check(not E.IsEntry, 'entry: semicolon before equals sign is not an entry');
  Check((E.GetTag = '') and (E.GetValue = '') and (E.GetComment = ''), 'entry: kept line has empty fields');
  Check(E.GetText = '; a=b', 'entry: kept line keeps its text');
  E.Free;

  E := TIniEntry.Create('x;y=1');
  Check(not E.IsEntry, 'entry: x;y=1 is not an entry');
  E.Free;

  E := TIniEntry.Create('=v');
  Check(not E.IsEntry, 'entry: empty tag is not an entry');
  E.Free;

  E := TIniEntry.Create('   =v');
  Check(not E.IsEntry, 'entry: blank tag is not an entry');
  E.Free;

  E := TIniEntry.Create('just text');
  Check(not E.IsEntry, 'entry: line without equals sign is not an entry');
  E.Free;

  E := TIniEntry.Create('');
  Check(not E.IsEntry, 'entry: empty line is not an entry');
  Check(E.GetText = '', 'entry: empty line text is empty');
  E.Free;

  E := TIniEntry.Create('my tag = 1');
  Check(E.GetTag = 'my tag', 'entry: spaces inside a tag are kept');
  E.Free;

  E := TIniEntry.Create('A=');
  Check(E.IsEntry and (E.GetValue = ''), 'entry: empty value is still an entry');
  E.Free;

  E := TIniEntry.Create('A=1=2');
  Check(E.GetValue = '1=2', 'entry: only the first equals sign splits');
  E.Free;

  E := TIniEntry.Create('A=ab;cd');
  Check((E.GetValue = 'ab') and (E.GetComment = 'cd'), 'entry: a semicolon inside a word ends the value');
  E.Free;

  E := TIniEntry.Create('A=x"y''z');
  Check(E.GetValue = 'x"y''z', 'entry: quotes in the middle of an unquoted value are ordinary');
  E.Free;

  E := TIniEntry.Create('A=''a;b'' ;note');
  Check((E.GetValue = 'a;b') and (E.GetComment = 'note'), 'entry: a semicolon inside quotes is part of the value');
  E.Free;

  E := TIniEntry.Create('A=''it''''s''');
  Check(E.GetValue = 'it''s', 'entry: a doubled delimiter is one delimiter');
  E.Free;

  E := TIniEntry.Create('A="say ""hi"""');
  Check(E.GetValue = 'say "hi"', 'entry: doubled double quotes');
  E.Free;

  E := TIniEntry.Create('A=''q'' junk ;c');
  Check((E.GetValue = 'q') and (E.GetComment = 'c'), 'entry: text after the closing quote is dropped');
  E.Free;

  E := TIniEntry.Create('A=''  pad  ''');
  Check(E.GetValue = '  pad  ', 'entry: a quoted value is not trimmed');
  E.Free;

  E := TIniEntry.Create('A=''abc ;d');
  Check((E.GetValue = 'abc ;d') and (E.GetComment = ''), 'entry: an unterminated quote runs to the end of the line');
  E.Free;

  E := TIniEntry.Create('A=''''');
  Check(E.IsEntry and (E.GetValue = ''), 'entry: empty quotes give an empty value');
  E.Free;

  E := TIniEntry.Create('A=1', False);
  Check(E.GetValue = '1', 'entry: two-argument constructor with False is normal mode');
  E.Free;
end;

procedure TestEntryRaw;
var
  E: TIniEntry;
begin
  E := TIniEntry.Create('Cmd=a -r ; b', True);
  Check(E.GetValue = 'a -r ; b', 'raw: the semicolon is no comment');
  Check(E.GetComment = '', 'raw: the comment stays empty');
  E.Free;

  E := TIniEntry.Create('Q=''x''', True);
  Check(E.GetValue = 'x', 'raw: surrounding quotes are removed');
  E.Free;

  E := TIniEntry.Create('Q="x"', True);
  Check(E.GetValue = 'x', 'raw: surrounding double quotes are removed');
  E.Free;

  E := TIniEntry.Create('Q=''x"', True);
  Check(E.GetValue = '''x"', 'raw: different quote characters are kept');
  E.Free;

  E := TIniEntry.Create('Q=''', True);
  Check(E.GetValue = '''', 'raw: a single quote character is kept');
  E.Free;

  E := TIniEntry.Create('Q=''it''''s''', True);
  Check(E.GetValue = 'it''''s', 'raw: the inside is not unescaped');
  E.Free;

  E := TIniEntry.Create('R= v ', True);
  Check(E.GetValue = ' v ', 'raw: the value is not trimmed');
  E.Free;

  E := TIniEntry.Create('R=1', True);
  E.SetValue('p;q');
  Check(E.GetText = 'R=p;q', 'raw: a changed value is written without quoting');
  E.SetComment('note');
  Check(E.GetText = 'R=p;q', 'raw: the comment is dropped from the text');
  E.Free;
end;

procedure TestEntryFields;
var
  E: TIniEntry;
begin
  E := TIniEntry.Create('Count', '6', '');
  Check(E.IsEntry, 'fields: constructor makes an entry');
  Check(E.GetText = 'Count=6', 'fields: text of tag and value');
  E.Free;

  E := TIniEntry.Create('OpenExts', '*.pas;*.pp', 'the masks');
  Check(E.GetText = 'OpenExts=''*.pas;*.pp'' ;the masks', 'fields: quoted value and comment');
  Check((E.GetTag = 'OpenExts') and (E.GetValue = '*.pas;*.pp') and (E.GetComment = 'the masks'),
    'fields: getters return the fields');
  E.Free;

  E := TIniEntry.Create('Tag', 'a;b', 'c', True);
  Check(E.GetText = 'Tag=a;b', 'fields: raw entry text has no quoting and no comment');
  E.Free;

  E := TIniEntry.Create('Tag', '', '');
  Check(E.GetText = 'Tag=', 'fields: empty value text');
  E.Free;

  E := TIniEntry.Create('Key   =   val  ;c');
  E.SetValue('val');
  Check(E.GetText = 'Key   =   val  ;c', 'set: same value keeps the original text');
  E.SetComment('c');
  Check(E.GetText = 'Key   =   val  ;c', 'set: same comment keeps the original text');
  E.SetValue('new');
  Check(E.GetText = 'Key=new ;c', 'set: a changed value regenerates the text');
  Check(E.GetValue = 'new', 'set: the value is replaced');
  E.SetComment('');
  Check(E.GetText = 'Key=new', 'set: an empty comment is left out');
  E.SetComment('d');
  Check(E.GetText = 'Key=new ;d', 'set: a changed comment is written');
  E.Free;

  E := TIniEntry.Create('Key = ''v'' ;c');
  E.SetComment('other');
  Check(E.GetText = 'Key=v ;other', 'set: a changed comment regenerates the line');
  E.Free;

  E := TIniEntry.Create('; kept');
  E.SetValue('x');
  Check(not E.IsEntry, 'kept line: SetValue does not make an entry');
  Check(E.GetText = '; kept', 'kept line: SetValue leaves the text');
  E.SetComment('y');
  Check(E.GetText = '; kept', 'kept line: SetComment leaves the text');
  Check(E.GetTag = '', 'kept line: the tag stays empty');
  E.Free;
end;

procedure TestQuote;
begin
  Check(IniQuote('abc') = 'abc', 'quote: plain text is unchanged');
  Check(IniQuote('') = '', 'quote: empty text needs no quotes');
  Check(IniQuote('a;b c') = '''a;b c''', 'quote: semicolon gives single quotes');
  Check(IniQuote('x''y;z') = '"x''y;z"', 'quote: single quote inside gives double quotes');
  Check(IniQuote('  pad ') = '''  pad ''', 'quote: padding gives quotes');
  Check(IniQuote('it''s') = 'it''s', 'quote: a quote in the middle needs nothing');
  Check(IniQuote(' a') = ''' a''', 'quote: leading space');
  Check(IniQuote('a ') = '''a ''', 'quote: trailing space');
  Check(IniQuote('''q') = '"''q"', 'quote: leading single quote');
  Check(IniQuote('"q') = '''"q''', 'quote: leading double quote');
  Check(IniQuote('a' + #9 + 'b') = '''a' + #9 + 'b''', 'quote: control byte inside');
  Check(IniQuote(';x''y"z') = '";x''y""z"', 'quote: the delimiter inside is doubled');
  Check(IniQuote('a=b') = 'a=b', 'quote: equals sign needs nothing');
  Check(IniQuote(Utf8Value) = Utf8Value, 'quote: UTF-8 text is unchanged');
end;

procedure TestSection;
var
  S: TIniSection;
  E: PIniEntry;
begin
  S := TIniSection.Create('Sec');
  Check(S.GetName = 'Sec', 'section: name keeps its case');
  Check(S.Count = 0, 'section: starts empty');
  S.AddEntry('A=1');
  S.AddEntry('; c');
  E := S.AddEntry('B', '2', 'x');
  Check(S.Count = 3, 'section: count includes kept lines');
  Check(E.GetText = 'B=2 ;x', 'section: entry made from fields');
  Check(S.Entry(2) = E, 'section: Entry returns the I-th object');
  Check(not S.Entry(1).IsEntry, 'section: a kept line is an object');
  Check(S.SearchEntry('a') <> nil, 'section: search ignores case');
  Check(S.SearchEntry('A').GetValue = '1', 'section: search finds the value');
  Check(S.SearchEntry('; c') = nil, 'section: kept lines are not found');
  Check(S.SearchEntry('zzz') = nil, 'section: missing tag gives nil');
  S.AddEntry('a=dup');
  Check(S.Count = 4, 'section: duplicates are kept');
  Check(S.SearchEntry('A').GetValue = '1', 'section: the first duplicate is found');
  S.DeleteEntry('A');
  Check(S.Count = 3, 'section: delete removes one entry');
  Check(S.SearchEntry('A').GetValue = 'dup', 'section: the second duplicate is found after the first is deleted');
  Check(not S.Entry(0).IsEntry, 'section: later entries move up');
  S.DeleteEntry('zzz');
  Check(S.Count = 3, 'section: delete of a missing tag does nothing');
  S.DeleteEntry('; c');
  Check(S.Count = 3, 'section: delete does not remove kept lines');
  S.Free;

  S := TIniSection.Create('R', True);
  Check(S.AddEntry('V=''x''').GetValue = 'x', 'section: raw mode is given to parsed entries');
  Check(S.AddEntry('W=a;b').GetValue = 'a;b', 'section: raw entry keeps the semicolon');
  S.Free;

  S := TIniSection.Create('N');
  Check(S.AddEntry('W=a;b').GetValue = 'a', 'section: normal mode by default');
  S.AddEntry(KeyUpper + '=1');
  Check(S.SearchEntry(KeyLower) <> nil, 'section: non-ASCII tags are found without regard to case');
  S.Free;
end;

procedure TestRead;
var
  F: TIniFile;
  Main, Files: PIniSection;
begin
  F := NewBase;
  Check(F.SectionCount = 3, 'read: three sections');
  Main := F.SectionAt(0);
  Files := F.SectionAt(1);
  Check(Main.GetName = MainSectionName, 'read: the first section is the main section');
  Check(Files.GetName = 'Files', 'read: the second section is Files');
  Check(F.SectionAt(2).GetName = 'Other', 'read: the third section is Other');
  Check(Main.Count = 3, 'read: main section holds the comment, the entry and the blank line');
  Check(F.GetEntry(MainSectionName, 'Comment', '') = 'Do NOT delete', 'read: the entry before the first header is in the main section');
  Check(F.GetEntry('Files', 'OpenExts', '') = '*.pas;*.pp', 'read: a quoted value keeps its semicolon');
  Check(F.SearchEntry('Files', 'OpenExts').GetComment = 'the masks', 'read: comment after a quoted value');
  Check(F.GetEntry('files', 'COUNT', '') = '5', 'read: section and tag lookup ignore case and spaces around equals');
  Check(F.GetEntry('Files', 'Name', '') = 'it''s', 'read: double quotes around a single quote');
  Check(F.GetEntry('Files', 'Missing', 'dflt') = 'dflt', 'read: missing tag gives the default');
  Check(F.GetEntry('NoSection', 'Missing', 'dflt2') = 'dflt2', 'read: missing section gives the default');
  Check(F.GetIntEntry('Files', 'Count', 0) = 5, 'read: integer value');
  Check(F.GetBoolEntry('Other', 'Flag', False), 'read: boolean value 1');
  Check(F.EntryExists('Other', 'flag'), 'read: EntryExists is case-insensitive');
  Check(not F.EntryExists('Other', 'nothing'), 'read: EntryExists is false for a missing tag');
  Check(not F.EntryExists('Nope', 'Flag'), 'read: EntryExists is false for a missing section');
  Check(F.SearchSection('FILES') = Files, 'read: SearchSection ignores case');
  Check(F.SearchSection('Nope') = nil, 'read: SearchSection gives nil for a missing name');
  Check(F.SearchEntry('Nope', 'x') = nil, 'read: SearchEntry gives nil for a missing section');
  Check(F.SearchEntry('Files', 'x') = nil, 'read: SearchEntry gives nil for a missing tag');
  Check(not F.IsModified, 'read: reading does not set modified');
  Check(F.SaveToText = BaseText, 'read: SaveToText returns the original text');
  F.Free;
end;

procedure TestLoadFormat;
var
  F: TIniFile;
begin
  F := TIniFile.Create('');
  Check(F.InlineComments, 'create: InlineComments starts True');
  Check(not F.MakeNullEntries, 'create: MakeNullEntries starts False');
  Check(F.GetFileName = '', 'create: empty file name is kept');
  Check(F.SectionCount = 0, 'create: no sections');

  F.LoadFromText('');
  Check(F.SectionCount = 0, 'load: empty text gives no sections');
  Check(F.SaveToText = '', 'load: empty text saves as empty text');

  F.LoadFromText('[A]' + LF + 'x=1' + LF);
  Check(F.SectionCount = 1, 'load: text that starts with a header has no main section');
  Check(F.SearchSection(MainSectionName) = nil, 'load: no main section when the text starts with a header');
  Check(F.SaveToText = '[A]' + LF + 'x=1' + LF, 'load: a header-first text saves unchanged');

  F.LoadFromText(LF + '[A]' + LF);
  Check(F.SectionCount = 2, 'load: a blank first line creates the main section');
  Check(F.SectionAt(0).Count = 1, 'load: the blank line is a kept line of the main section');
  Check(F.SaveToText = LF + '[A]' + LF, 'load: the blank first line round-trips');

  F.LoadFromText('[ Spaced ]' + LF + 'x=1' + LF);
  Check(F.SectionAt(0).GetName = 'Spaced', 'load: the section name is trimmed');
  Check(F.SaveToText = '[Spaced]' + LF + 'x=1' + LF, 'load: the header is saved without inner spaces');

  F.LoadFromText('  [Indented]  ' + LF);
  Check(F.SearchSection('Indented') <> nil, 'load: a header is recognised after trimming the line');

  F.LoadFromText('[]' + LF + 'x=1' + LF);
  Check(F.SectionCount = 1, 'load: two brackets make a section');
  Check(F.SectionAt(0).GetName = '', 'load: the name between two brackets is empty');

  F.LoadFromText('[' + LF);
  Check(F.SearchSection('') = nil, 'load: a single bracket is no header');
  Check(F.SectionCount = 1, 'load: a single bracket line is kept in the main section');

  F.LoadFromText('[A] ; note' + LF + 'x=1' + LF);
  Check(F.SectionCount = 1, 'load: a header with a trailing note is a line of the main section');
  Check(F.SearchSection('A') = nil, 'load: a header with a trailing note is not recognised');

  F.LoadFromText('a=1');
  Check(F.SaveToText = 'a=1' + LF, 'load: a missing final line end is added');
  Check(F.GetEntry(MainSectionName, 'a', '') = '1', 'load: a final line without line end is a line');

  F.LoadFromText('a=1' + LF);
  Check(F.SectionAt(0).Count = 1, 'load: a final line end gives no extra line');

  F.LoadFromText(LF);
  Check(F.SectionCount = 1, 'load: a lone line end makes the main section');
  Check(F.SectionAt(0).Count = 1, 'load: a lone line end is one blank line');

  F.LoadFromText('a=1' + #13 + 'b=2' + LF);
  Check(F.SectionAt(0).Count = 1, 'load: a lone CR is not a line end');
  Check(F.SearchEntry(MainSectionName, 'b') = nil, 'load: the text after a lone CR is not a separate entry');

  F.LoadFromText('[A]' + LF + 'x=1' + LF + '[a]' + LF + 'x=2' + LF);
  Check(F.SectionCount = 2, 'load: sections with the same name are kept');
  Check(F.GetEntry('A', 'x', '') = '1', 'load: lookups find the first duplicate section');
  F.SetEntry('A', 'x', '9');
  Check(F.SaveToText = '[A]' + LF + 'x=9' + LF + '[a]' + LF + 'x=2' + LF, 'load: changes act on the first duplicate section');

  F.LoadFromText('x=1' + LF + 'x=2' + LF);
  Check(F.GetEntry(MainSectionName, 'x', '') = '1', 'load: lookups find the first duplicate tag');
  Check(F.SectionAt(0).Count = 2, 'load: duplicate tags are kept');

  F.LoadFromText(BaseText);
  F.SetEntry('Other', 'Flag', '0');
  Check(F.IsModified, 'load: a change sets modified');
  F.LoadFromText(BaseText);
  Check(not F.IsModified, 'load: LoadFromText clears modified');
  F.Free;
end;

procedure TestLineEnds;
var
  F: TIniFile;
begin
  F := TIniFile.Create('');
  F.LoadFromText('a=1' + CRLF + 'b=2' + CRLF);
  Check(F.SectionAt(0).Count = 2, 'crlf: carriage returns are not part of the lines');
  Check(F.GetEntry(MainSectionName, 'b', '') = '2', 'crlf: value without the carriage return');
  Check(F.SaveToText = 'a=1' + CRLF + 'b=2' + CRLF, 'crlf: a CR LF text round-trips');

  F.LoadFromText('[S]' + CRLF + 'a=1' + CRLF + CRLF + 'b=2' + CRLF);
  Check(F.SaveToText = '[S]' + CRLF + 'a=1' + CRLF + CRLF + 'b=2' + CRLF, 'crlf: blank lines round-trip');

  F.LoadFromText('a=1' + CRLF + 'b=2' + LF);
  Check(F.SaveToText = 'a=1' + LF + 'b=2' + LF, 'ends: the last terminated line decides, LF');

  F.LoadFromText('a=1' + LF + 'b=2' + CRLF);
  Check(F.SaveToText = 'a=1' + CRLF + 'b=2' + CRLF, 'ends: the last terminated line decides, CR LF');

  F.LoadFromText('a=1' + LF + 'b=2' + CRLF + 'c=3');
  Check(F.SaveToText = 'a=1' + CRLF + 'b=2' + CRLF + 'c=3' + CRLF, 'ends: an unterminated last line does not change the style');

  F.LoadFromText('a=1' + CRLF + 'b=2' + LF + 'c=3');
  Check(F.SaveToText = 'a=1' + LF + 'b=2' + LF + 'c=3' + LF, 'ends: an unterminated last line does not change the LF style');

  F.LoadFromText('[A]' + CRLF + 'x=1' + CRLF);
  F.SetEntry('A', 'y', '2');
  Check(F.SaveToText = '[A]' + CRLF + 'x=1' + CRLF + 'y=2' + CRLF, 'ends: new lines use the style of the file');
  F.Free;
end;

procedure TestBom;
var
  F: TIniFile;
begin
  F := TIniFile.Create('');
  F.LoadFromText(Bom + '[A]' + LF + 'x=1' + LF);
  Check(F.SectionCount = 1, 'bom: the byte order mark is not text');
  Check(F.SectionAt(0).GetName = 'A', 'bom: a header after the mark is recognised');
  Check(F.SaveToText = Bom + '[A]' + LF + 'x=1' + LF, 'bom: the mark is written back');

  F.LoadFromText(Bom + 'k=v' + LF);
  Check(F.GetEntry(MainSectionName, 'k', '') = 'v', 'bom: the first entry is not spoiled by the mark');

  F.LoadFromText('[A]' + LF);
  Check(F.SaveToText = '[A]' + LF, 'bom: no mark is written when none was read');

  F.LoadFromText(Bom);
  Check(F.SectionCount = 0, 'bom: a text that is only the mark has no sections');
  Check(F.SaveToText = Bom, 'bom: a text that is only the mark saves as the mark');

  F.LoadFromText('x=' + Utf8Value + LF);
  Check(F.GetEntry(MainSectionName, 'x', '') = Utf8Value, 'utf8: the value passes unchanged');
  Check(F.SaveToText = 'x=' + Utf8Value + LF, 'utf8: the text round-trips');
  F.SetEntry(MainSectionName, 'y', Utf8Value);
  Check(F.SaveToText = 'x=' + Utf8Value + LF + 'y=' + Utf8Value + LF, 'utf8: a new UTF-8 value is written unchanged');
  F.Free;
end;

procedure TestCaseFolding;
var
  F: TIniFile;
begin
  F := TIniFile.Create('');
  F.LoadFromText('[' + KeyUpper + ']' + LF + KeyUpper + '=1' + LF);
  Check(F.SearchSection(KeyLower) <> nil, 'case: non-ASCII section names are found without regard to case');
  Check(F.GetEntry(KeyLower, KeyLower, '') = '1', 'case: non-ASCII tags are found without regard to case');
  F.SetEntry(KeyLower, KeyLower, '2');
  Check(F.SaveToText = '[' + KeyUpper + ']' + LF + KeyUpper + '=2' + LF, 'case: the tag keeps the case it had');
  Check(F.SectionCount = 1, 'case: no second section is made for a different case');
  F.Free;
end;

procedure TestSetEntry;
var
  F: TIniFile;
begin
  F := NewBase;
  F.SetEntry('Files', 'Count', '5');
  Check(not F.IsModified, 'set: the same value is not a change');
  F.SetEntry('files', 'count', '5', '');
  Check(not F.IsModified, 'set: the same value and comment are not a change');
  F.SetEntry('Files', 'OpenExts', '*.pas;*.pp');
  Check(not F.IsModified, 'set: the same quoted value is not a change');
  F.SetEntry('Files', 'OpenExts', '*.pas;*.pp', 'the masks');
  Check(not F.IsModified, 'set: the same value and comment of a quoted entry are not a change');
  Check(F.SaveToText = BaseText, 'set: unchanged entries leave the text as it was');

  F.SetIntEntry('Files', 'Count', 6);
  Check(F.IsModified, 'set: a changed integer sets modified');
  Check(F.SaveToText = BaseTextCount6, 'set: only the changed line is generated anew');
  Check(Pos('Count=6' + LF, F.SaveToText) > 0, 'set: the changed line is Count=6');
  Check(Pos('OpenExts=''*.pas;*.pp'' ;the masks' + LF, F.SaveToText) > 0, 'set: the quoted line is unchanged');
  Check(Pos('; between' + LF, F.SaveToText) > 0, 'set: the comment line is unchanged');
  F.Free;

  F := NewBase;
  F.SetEntry('Files', 'OpenExts', 'x');
  Check(F.SearchEntry('Files', 'OpenExts').GetComment = 'the masks', 'set: the three-argument form keeps the comment');
  Check(Pos('OpenExts=x ;the masks' + LF, F.SaveToText) > 0, 'set: the kept comment is written');
  F.SetEntry('Files', 'OpenExts', 'x', '');
  Check(Pos('OpenExts=x' + LF, F.SaveToText) > 0, 'set: an empty comment removes the comment');
  F.SetEntry('Files', 'OpenExts', 'x', 'new');
  Check(Pos('OpenExts=x ;new' + LF, F.SaveToText) > 0, 'set: a new comment is written');
  F.Free;

  F := NewBase;
  F.SetEntry('FILES', 'COUNT', '7');
  Check(Pos('Count=7' + LF, F.SaveToText) > 0, 'set: the tag keeps its case');
  F.Free;

  F := NewBase;
  F.SetEntry('Files', 'OpenExts', '*.pas;*.pp', '');
  Check(F.IsModified, 'set: removing only the comment is a change');
  Check(Pos('OpenExts=''*.pas;*.pp''' + LF, F.SaveToText) > 0, 'set: the value stays quoted without the comment');
  F.Free;

  F := NewBase;
  F.SetEntry('Files', 'Name', 'plain');
  Check(Pos('Name=plain' + LF, F.SaveToText) > 0, 'set: a quoted original is replaced by the plain text');
  F.Free;
end;

procedure TestQuotingRoundTrip;
var
  F, G: TIniFile;
begin
  F := TIniFile.Create('');
  F.LoadFromText('[A]' + LF);
  F.SetEntry('A', 'Path', 'a;b c');
  F.SetEntry('A', 'Q', 'x''y;z');
  F.SetEntry('A', 'Pad', '  pad ');
  Check(Pos('Path=''a;b c''' + LF, F.SaveToText) > 0, 'quote: a semicolon value is saved in single quotes');
  Check(Pos('Q="x''y;z"' + LF, F.SaveToText) > 0, 'quote: a value with a single quote is saved in double quotes');
  Check(Pos('Pad=''  pad ''' + LF, F.SaveToText) > 0, 'quote: a padded value is saved in quotes');

  G := TIniFile.Create('');
  G.LoadFromText(F.SaveToText);
  Check(G.GetEntry('A', 'Path', '') = 'a;b c', 'quote: the semicolon value reads back');
  Check(G.GetEntry('A', 'Q', '') = 'x''y;z', 'quote: the single quote value reads back');
  Check(G.GetEntry('A', 'Pad', '') = '  pad ', 'quote: the padded value reads back');
  Check(G.SaveToText = F.SaveToText, 'quote: the text is stable after a second load');
  G.Free;
  F.Free;
end;

procedure TestNewSection;
var
  F: TIniFile;
begin
  F := NewBase;
  F.SetEntry('New', 'K', 'v');
  Check(F.IsModified, 'new: a new entry sets modified');
  Check(F.SectionCount = 4, 'new: the section is created');
  Check(F.SectionAt(3).GetName = 'New', 'new: the section is at the end with the name as given');
  Check(F.SaveToText = BaseText + LF + '[New]' + LF + 'K=v' + LF, 'new: a blank separator precedes the new section');
  F.SetEntry('Newer', 'K2', 'w');
  Check(F.SaveToText = BaseText + LF + '[New]' + LF + 'K=v' + LF + LF + '[Newer]' + LF + 'K2=w' + LF,
    'new: a separator is added again');
  F.Free;

  F := TIniFile.Create('');
  F.LoadFromText('[A]' + LF + 'x=1' + LF + LF);
  F.SetEntry('B', 'k', 'v');
  Check(F.SaveToText = '[A]' + LF + 'x=1' + LF + LF + '[B]' + LF + 'k=v' + LF, 'new: no separator after a blank line');
  F.Free;

  F := TIniFile.Create('');
  F.LoadFromText('[A]' + LF);
  F.SetEntry('B', 'k', 'v');
  Check(F.SaveToText = '[A]' + LF + '[B]' + LF + 'k=v' + LF, 'new: no separator after an empty section');
  F.Free;

  F := TIniFile.Create('');
  F.LoadFromText('[A]' + LF + 'x=1' + LF + LF + '; c' + LF);
  F.SetEntry('A', 'y', '2');
  Check(F.SaveToText = '[A]' + LF + 'x=1' + LF + LF + '; c' + LF + 'y=2' + LF,
    'new: a new tag goes after the trailing blank and comment lines');
  F.Free;

  F := TIniFile.Create('');
  F.LoadFromText('[A]' + LF + 'x=1' + LF + '[B]' + LF + 'z=1' + LF);
  F.SetEntry('A', 'y', '2');
  Check(F.SaveToText = '[A]' + LF + 'x=1' + LF + 'y=2' + LF + '[B]' + LF + 'z=1' + LF,
    'new: a new tag goes to the end of its own section');
  F.Free;

  F := TIniFile.Create('');
  F.LoadFromText('x=1' + LF);
  F.SetEntry('Other', 'k', 'v');
  Check(F.SaveToText = 'x=1' + LF + LF + '[Other]' + LF + 'k=v' + LF, 'new: a section after the main section');
  F.Free;
end;

procedure TestEmptyValue;
var
  F: TIniFile;
begin
  F := NewBase;
  F.SetEntry('Files', 'Nothing', '');
  Check(not F.IsModified, 'empty: an empty value of a missing tag is not written');
  Check(F.SaveToText = BaseText, 'empty: the text is unchanged');
  F.SetEntry('Brand', 'Nothing', '');
  Check(F.SectionCount = 3, 'empty: not even the section is created');
  Check(not F.IsModified, 'empty: still not modified');

  F.SetEntry('Files', 'Count', '');
  Check(F.IsModified, 'empty: an empty value of an existing tag is written');
  Check(Pos('Count=' + LF, F.SaveToText) > 0, 'empty: the line is Count=');
  F.Free;
end;

procedure TestDelete;
var
  F: TIniFile;
begin
  F := NewBase;
  F.DeleteEntry('Files', 'nothing');
  Check(not F.IsModified, 'delete: a missing tag does not set modified');
  F.DeleteEntry('Nope', 'Count');
  Check(not F.IsModified, 'delete: a missing section does not set modified');
  F.DeleteEntry('Files', 'COUNT');
  Check(F.IsModified, 'delete: a found tag sets modified');
  Check(not F.EntryExists('Files', 'Count'), 'delete: the entry is gone');
  Check(F.SaveToText = BaseHead + BaseTail, 'delete: the other lines are untouched');

  F.LoadFromText(BaseText);
  F.DeleteSection('nope');
  Check(not F.IsModified, 'delete: a missing section does not set modified when deleting a section');
  Check(F.SectionCount = 3, 'delete: a missing section changes nothing');
  F.DeleteSection('FILES');
  Check(F.IsModified, 'delete: deleting a section sets modified');
  Check(F.SectionCount = 2, 'delete: the section is gone');
  Check(F.SearchSection('Files') = nil, 'delete: the section is not found');
  Check(F.SaveToText = '; a comment line' + LF + 'Comment=Do NOT delete' + LF + LF + '[Other]' + LF + 'Flag=1' + LF,
    'delete: the other sections are untouched');
  F.Free;

  F := TIniFile.Create('');
  F.LoadFromText('[A]' + LF + 'x=1' + LF + '[A]' + LF + 'x=2' + LF);
  F.DeleteSection('A');
  Check(F.SaveToText = '[A]' + LF + 'x=2' + LF, 'delete: only the first of two sections is removed');
  F.Free;

  F := TIniFile.Create('');
  F.LoadFromText('[A]' + LF + 'x=1' + LF + 'x=2' + LF);
  F.DeleteEntry('A', 'x');
  Check(F.SaveToText = '[A]' + LF + 'x=2' + LF, 'delete: only the first of two tags is removed');
  F.Free;
end;

procedure TestObjectChanges;
var
  F: TIniFile;
begin
  F := NewBase;
  F.SearchEntry('Files', 'Count').SetValue('8');
  Check(not F.IsModified, 'object: a change through an entry object does not set modified');
  Check(F.GetIntEntry('Files', 'Count', 0) = 8, 'object: the change is visible');
  F.SearchSection('Other').AddEntry('Extra', '1', '');
  Check(not F.IsModified, 'object: AddEntry on a section does not set modified');
  F.SearchSection('Other').DeleteEntry('Flag');
  Check(not F.IsModified, 'object: DeleteEntry on a section does not set modified');
  F.Free;
end;

procedure TestEnumerate;
var
  F: TIniFile;
  Tags: AnsiString;
  Visited: Integer;

  procedure CollectEntry(P: PIniEntry);
  begin
    Tags := Tags + P.GetTag + ',';
    Inc(Visited);
  end;

  procedure CollectSection(P: PIniSection);
  begin
    Tags := Tags + P.GetName + ',';
    Inc(Visited);
  end;

begin
  F := NewBase;

  Tags := '';
  Visited := 0;
  F.ForEachEntry('Files', @CollectEntry);
  Check(Tags = 'OpenExts,Count,Name,', 'each: entries in order, kept lines skipped');
  Check(Visited = 3, 'each: three real entries in Files');

  Tags := '';
  Visited := 0;
  F.ForEachEntry('files', @CollectEntry);
  Check(Visited = 3, 'each: the section name is matched without regard to case');

  Tags := '';
  Visited := 0;
  F.ForEachEntry('Missing', @CollectEntry);
  Check(Visited = 0, 'each: nothing for a missing section');

  Tags := '';
  Visited := 0;
  F.ForEachEntry(MainSectionName, @CollectEntry);
  Check(Tags = 'Comment,', 'each: the main section has one real entry');

  Tags := '';
  Visited := 0;
  F.SearchSection('Other').ForEachEntry(@CollectEntry);
  Check(Tags = 'Flag,', 'each: the enumeration of a section object');

  Tags := '';
  Visited := 0;
  F.ForEachSection(@CollectSection);
  Check(Visited = F.SectionCount, 'each: ForEachSection visits SectionCount sections');
  Check(Tags = 'MainSection,Files,Other,', 'each: sections in order, the main one included');
  F.Free;
end;

procedure TestNullEntries;
var
  F: TIniFile;
begin
  F := NewBase;
  F.MakeNullEntries := True;
  Check(F.GetEntry('Files', 'Fresh', 'dflt') = 'dflt', 'null: the default is returned');
  Check(F.IsModified, 'null: the read of a missing tag marks the file modified');
  Check(F.EntryExists('Files', 'Fresh'), 'null: the tag is added');
  Check(Pos('Fresh=dflt' + LF, F.SaveToText) > 0, 'null: the tag is written with the default');
  F.Free;

  F := NewBase;
  F.MakeNullEntries := True;
  Check(F.GetEntry('Files', 'Blank', '') = '', 'null: an empty default is returned');
  Check(Pos('Blank=' + LF, F.SaveToText) > 0, 'null: an empty default is written as Tag=');
  Check(F.IsModified, 'null: an empty default marks the file modified');
  F.Free;

  F := NewBase;
  F.MakeNullEntries := True;
  Check(F.GetEntry('Brand', 'k', 'v') = 'v', 'null: a missing section gives the default');
  Check(F.SectionCount = 4, 'null: the section is created');
  F.Free;

  F := NewBase;
  F.MakeNullEntries := True;
  Check(F.GetIntEntry('Files', 'Num', 7) = 7, 'null: integer default is returned');
  Check(Pos('Num=7' + LF, F.SaveToText) > 0, 'null: the integer default is written');
  F.Free;

  F := NewBase;
  F.MakeNullEntries := True;
  Check(F.GetBoolEntry('Files', 'On1', True), 'null: boolean default True is returned');
  Check(not F.GetBoolEntry('Files', 'Off1', False), 'null: boolean default False is returned');
  Check(Pos('On1=1' + LF, F.SaveToText) > 0, 'null: the boolean default True is written as 1');
  Check(Pos('Off1=0' + LF, F.SaveToText) > 0, 'null: the boolean default False is written as 0');
  F.Free;

  F := NewBase;
  Check(F.GetEntry('Files', 'Fresh', 'dflt') = 'dflt', 'null: off, the default is returned');
  Check(not F.IsModified, 'null: off, nothing is added');
  Check(F.SaveToText = BaseText, 'null: off, the text is unchanged');
  F.Free;
end;

procedure TestIntBool;
var
  F: TIniFile;
begin
  F := TIniFile.Create('');
  F.LoadFromText(
    'Dec=42' + LF +
    'Neg=-17' + LF +
    'Hex1=$1F' + LF +
    'Hex2=0x10' + LF +
    'Pad=''  12 ''' + LF +
    'Bad=abc' + LF +
    'Empty=' + LF +
    'Big=99999999999' + LF +
    'T1=TRUE' + LF +
    'T2=Yes' + LF +
    'T3=ON' + LF +
    'T4=1' + LF +
    'F1=No' + LF +
    'F2=OFF' + LF +
    'F3=0' + LF +
    'F4=false' + LF +
    'Odd=maybe' + LF +
    'BPad='' yes ''' + LF +
    'BEmpty=' + LF);
  Check(F.GetIntEntry(MainSectionName, 'Dec', 0) = 42, 'int: decimal');
  Check(F.GetIntEntry(MainSectionName, 'Neg', 0) = -17, 'int: negative');
  Check(F.GetIntEntry(MainSectionName, 'Hex1', 0) = 31, 'int: hex with a dollar sign');
  Check(F.GetIntEntry(MainSectionName, 'Hex2', 0) = 16, 'int: hex with 0x');
  Check(F.GetIntEntry(MainSectionName, 'Pad', 0) = 12, 'int: the value is trimmed');
  Check(F.GetIntEntry(MainSectionName, 'Bad', 3) = 3, 'int: not a number gives the default');
  Check(F.GetIntEntry(MainSectionName, 'Empty', 4) = 4, 'int: empty gives the default');
  Check(F.GetIntEntry(MainSectionName, 'Big', 5) = 5, 'int: more than 32 bits gives the default');
  Check(F.GetIntEntry(MainSectionName, 'Nope', 6) = 6, 'int: missing gives the default');
  Check(F.GetIntEntry('Nosec', 'Nope', -6) = -6, 'int: missing section gives the default');

  Check(F.GetBoolEntry(MainSectionName, 'T1', False), 'bool: TRUE');
  Check(F.GetBoolEntry(MainSectionName, 'T2', False), 'bool: Yes');
  Check(F.GetBoolEntry(MainSectionName, 'T3', False), 'bool: ON');
  Check(F.GetBoolEntry(MainSectionName, 'T4', False), 'bool: 1');
  Check(not F.GetBoolEntry(MainSectionName, 'F1', True), 'bool: No');
  Check(not F.GetBoolEntry(MainSectionName, 'F2', True), 'bool: OFF');
  Check(not F.GetBoolEntry(MainSectionName, 'F3', True), 'bool: 0');
  Check(not F.GetBoolEntry(MainSectionName, 'F4', True), 'bool: false');
  Check(F.GetBoolEntry(MainSectionName, 'Odd', True), 'bool: another word gives the default True');
  Check(not F.GetBoolEntry(MainSectionName, 'Odd', False), 'bool: another word gives the default False');
  Check(F.GetBoolEntry(MainSectionName, 'BPad', False), 'bool: the value is trimmed');
  Check(F.GetBoolEntry(MainSectionName, 'BEmpty', True), 'bool: empty gives the default True');
  Check(not F.GetBoolEntry(MainSectionName, 'BEmpty', False), 'bool: empty gives the default False');
  Check(F.GetBoolEntry(MainSectionName, 'Nope', True), 'bool: missing gives the default True');
  Check(not F.GetBoolEntry(MainSectionName, 'Nope', False), 'bool: missing gives the default False');
  Check(not F.IsModified, 'bool: reading does not set modified');

  F.SetBoolEntry(MainSectionName, 'W1', True);
  F.SetBoolEntry(MainSectionName, 'W2', False);
  F.SetIntEntry(MainSectionName, 'W3', -5);
  Check(F.GetEntry(MainSectionName, 'W1', 'x') = '1', 'write: true is written as 1');
  Check(F.GetEntry(MainSectionName, 'W2', 'x') = '0', 'write: false is written as 0');
  Check(F.GetEntry(MainSectionName, 'W3', 'x') = '-5', 'write: integer in decimal');
  Check(F.IsModified, 'write: writing sets modified');
  F.Free;
end;

procedure TestRawMode;
var
  F: TIniFile;
begin
  F := TIniFile.Create('');
  F.InlineComments := False;
  F.LoadFromText('Cmd=a -r ; b' + CRLF + 'Q=''x''' + CRLF);
  Check(F.GetEntry(MainSectionName, 'Cmd', '') = 'a -r ; b', 'rawfile: the value is everything after the equals sign');
  Check(F.GetEntry(MainSectionName, 'Q', '') = 'x', 'rawfile: surrounding quotes are removed');
  F.SetEntry(MainSectionName, 'Q', 'x');
  Check(not F.IsModified, 'rawfile: the same value is not a change');
  F.SetEntry(MainSectionName, 'New', 'p;q');
  Check(F.IsModified, 'rawfile: a new entry sets modified');
  Check(F.SaveToText = 'Cmd=a -r ; b' + CRLF + 'Q=''x''' + CRLF + 'New=p;q' + CRLF,
    'rawfile: a new value is written unquoted and CR LF is kept');
  F.SetEntry(MainSectionName, 'Cmd', 'zz', 'note');
  Check(Pos('Cmd=zz' + CRLF, F.SaveToText) > 0, 'rawfile: no comment is kept');
  F.Free;

  F := TIniFile.Create('');
  F.InlineComments := False;
  F.LoadFromText('[A]' + LF);
  F.SetEntry('B', 'k', 'a b ;c');
  Check(F.SaveToText = '[A]' + LF + '[B]' + LF + 'k=a b ;c' + LF, 'rawfile: a section created later is raw too');
  F.Free;

  F := TIniFile.Create('');
  F.LoadFromText('[A]' + LF + 'k=1 ;c' + LF);
  Check(F.GetEntry('A', 'k', '') = '1', 'rawfile: normal mode is the default');
  F.Free;
end;

procedure TestFiles;
const
  IniName = 't_ini_file.ini';
  TmpOfIni = 't_ini_file.tmp';
  TmpName = 't_ini_ext.tmp';
  TmpOfTmp = 't_ini_ext.$$$';
  NoExt = 't_ini_noext';
  NoExtTmp = 't_ini_noext.tmp';
  EmptyName = 't_ini_empty.ini';
  BadName = 't_ini_no_such_dir/x.ini';
var
  F, G: TIniFile;
  ModeBefore: Integer;
  Handle: THandle;
begin
  DeleteFile(IniName);
  DeleteFile(TmpOfIni);
  DeleteFile(TmpName);
  DeleteFile(TmpOfTmp);
  DeleteFile(NoExt);
  DeleteFile(NoExtTmp);
  DeleteFile(EmptyName);

  F := TIniFile.Create(IniName);
  Check(F.GetFileName = IniName, 'file: the file name is kept');
  Check(not F.Read, 'file: Read of a missing file is False');
  Check(F.SectionCount = 0, 'file: a missing file gives no sections');
  Check(not F.IsModified, 'file: Read does not set modified');

  F.SetEntry('S', 'k', '1');
  Check(F.IsModified, 'file: SetEntry sets modified');
  Check(F.Update, 'file: Update is True');
  Check(not F.IsModified, 'file: Update clears modified');
  Check(FileExists(IniName), 'file: the file exists after Update');
  Check(not FileExists(TmpOfIni), 'file: the temporary file is gone after Update');

  G := TIniFile.Create(IniName);
  ModeBefore := FileMode;
  Check(G.Read, 'file: Read of an existing file is True');
  Check(FileMode = ModeBefore, 'file: Read leaves the global file mode alone');
  Check(G.GetIntEntry('S', 'k', 0) = 1, 'file: the value is read back');
  Check(not G.IsModified, 'file: modified is False after Read');
  G.SetEntry('S', 'k', '2');
  G.SetEntry('S', 'm', 'a;b');
  Check(G.Update, 'file: Update over an existing file is True');
  Check(not G.IsModified, 'file: modified is False after the second Update');
  F.Free;
  F := TIniFile.Create(IniName);
  Check(F.Read, 'file: Read after the second Update');
  Check(F.GetIntEntry('S', 'k', 0) = 2, 'file: the new file replaced the old one');
  Check(F.GetEntry('S', 'm', '') = 'a;b', 'file: a quoted value survives the file');
  F.Free;

  G.SetEntry('S', 'k', '2');
  Check(not G.IsModified, 'file: no change after Update');
  Check(G.Update, 'file: Update without changes is True');
  G.Free;

  F := TIniFile.Create(TmpName);
  F.SetEntry('S', 'k', '3');
  Check(F.Update, 'file: Update of a name ending in .tmp is True');
  Check(FileExists(TmpName), 'file: the .tmp file is written');
  Check(not FileExists(TmpOfTmp), 'file: the temporary name for .tmp is .$$$ and it is gone');
  F.Free;
  F := TIniFile.Create(TmpName);
  Check(F.Read and (F.GetIntEntry('S', 'k', 0) = 3), 'file: the .tmp file reads back');
  F.Free;

  F := TIniFile.Create(NoExt);
  F.SetEntry('S', 'k', '4');
  Check(F.Update, 'file: Update of a name without extension is True');
  Check(FileExists(NoExt), 'file: the file without extension is written');
  Check(not FileExists(NoExtTmp), 'file: the temporary file of a name without extension is gone');
  F.Free;

  Handle := FileCreate(EmptyName);
  FileClose(Handle);
  F := TIniFile.Create(EmptyName);
  Check(F.Read, 'file: Read of an empty file is True');
  Check(F.SectionCount = 0, 'file: an empty file gives no sections');
  F.Free;

  F := TIniFile.Create(BadName);
  F.SetEntry('S', 'k', '5');
  Check(not F.Update, 'file: Update is False when the temporary file cannot be created');
  Check(F.IsModified, 'file: modified stays True after a failed Update');
  F.Free;

  F := TIniFile.Create('');
  Check(not F.Read, 'file: Read with an empty name is False');
  F.SetEntry('S', 'k', '6');
  Check(F.Update, 'file: Update with an empty name is True');
  Check(F.IsModified, 'file: Update with an empty name does nothing');
  Check(F.GetIntEntry('S', 'k', 0) = 6, 'file: a memory-only INI keeps its values');
  Check(not FileExists('.tmp'), 'file: Update with an empty name writes no file');
  F.Free;

  DeleteFile(IniName);
  DeleteFile(TmpOfIni);
  DeleteFile(TmpName);
  DeleteFile(TmpOfTmp);
  DeleteFile(NoExt);
  DeleteFile(NoExtTmp);
  DeleteFile(EmptyName);
end;

begin
  TestEntryParse;
  TestEntryRaw;
  TestEntryFields;
  TestQuote;
  TestSection;
  TestRead;
  TestLoadFormat;
  TestLineEnds;
  TestBom;
  TestCaseFolding;
  TestSetEntry;
  TestQuotingRoundTrip;
  TestNewSection;
  TestEmptyValue;
  TestDelete;
  TestObjectChanges;
  TestEnumerate;
  TestNullEntries;
  TestIntBool;
  TestRawMode;
  TestFiles;
  Done;
end.
