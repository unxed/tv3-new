{ Test program of the unit TvWild. }
program t_wild;

{$mode objfpc}

uses
  SysUtils, TvUtf8, TvWild;

{$I testlib.inc}

const
  { Cyrillic letters as UTF-8 bytes }
  PrivetCap = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;
  PCapital = #$D0#$9F;
  PSmall = #$D0#$BF;

function M(const Name, Mask: AnsiString): Boolean;
begin
  Result := WildMatch(Name, Mask);
end;

function L(const Name, List: AnsiString): Boolean;
begin
  Result := WildMatchList(Name, List);
end;

begin
  Utf8Enabled := True;

  { Examples of WildMatch }
  Check(M('readme.txt', '*.txt'), 'readme.txt vs *.txt');
  Check(not M('readme.txt', '*.pas'), 'readme.txt vs *.pas');
  Check(M('README.TXT', '*.txt'), 'case folded');
  Check(not WildMatch('README.TXT', '*.txt', True), 'case sensitive');
  Check(M('a.b.c', '*.c'), 'star takes dots');
  Check(M('abc', 'a?c'), 'question mark');
  Check(not M('ac', 'a?c'), 'question mark needs a character');
  Check(M('noext', '*.*'), '*.* without a dot');
  Check(M('', '*'), 'empty name vs *');
  Check(M('abc', 'a*b*c'), 'a*b*c on abc');
  Check(M('aXbXc', 'a*b*c'), 'a*b*c on aXbXc');
  Check(not M('abcd', 'a*b*c'), 'a*b*c on abcd');
  Check(M('aaa', 'a*a'), 'a*a on aaa');
  Check(M('b.pas', '[a-c].pas'), 'range hit');
  Check(not M('d.pas', '[a-c].pas'), 'range miss');
  Check(M('d.pas', '[!a-c].pas'), 'negated range');
  Check(M('[x', '[x'), 'unclosed bracket is literal');
  Check(not M('x', '[x'), 'unclosed bracket does not match x');

  { UTF-8 mode }
  Check(M(PrivetCap + '.txt', PSmall + '*.TXT'), 'Cyrillic case folding');
  Check(M(PrivetCap, '??????'), 'six characters');
  Check(not M(PrivetCap, '?????????????'), 'thirteen question marks');
  Check(not M(PrivetCap, '?????'), 'five question marks');
  Check(M(PCapital, PSmall), 'capital vs small');
  Check(not WildMatch(PCapital, PSmall, True), 'capital vs small, case sensitive');
  Check(M(PSmall, '[' + PCapital + ']'), 'Cyrillic set member');
  Check(M(PSmall, '[' + PCapital + '-' + PSmall + ']'), 'Cyrillic range');

  { 1. empty strings }
  Check(M('', ''), 'empty vs empty');
  Check(not M('a', ''), 'a vs empty mask');
  Check(not M('', '?'), 'empty vs ?');
  Check(M('', '***'), 'empty vs stars');
  Check(M('abc', '***'), 'stars take anything');

  { 2. sets }
  Check(M(']', '[]a]'), '] in []a]');
  Check(M('a', '[]a]'), 'a in []a]');
  Check(not M('b', '[]a]'), 'b not in []a]');
  Check(not M(']', '[!]a]'), '] not in [!]a]');
  Check(M('b', '[!]a]'), 'b in [!]a]');
  Check(M('-', '[a-]'), '- in [a-]');
  Check(M('a', '[a-]'), 'a in [a-]');
  Check(not M('b', '[a-]'), 'b not in [a-]');
  Check(not M('m', '[z-a]'), 'reversed range matches nothing');
  Check(not M('z', '[z-a]'), 'reversed range, lo');
  Check(M('b', '[^a]'), 'caret negation');
  Check(not M('a', '[^a]'), 'caret negation, member');
  Check(M('x', '[a-cx-z]'), 'two ranges');
  Check(not M('', '[a]'), 'set needs a character');
  Check(not M('ab', '[a]'), 'set takes one character');
  Check(not M('x', '[a]x'), 'set mismatch has no literal fallback');
  Check(not M('[x', '[a]x'), 'set mismatch on [');
  Check(M('a]', 'a]'), 'lone closing bracket is literal');
  Check(M('-', '[--]'), 'range of one dash');
  Check(M('a', '[]-a]'), 'range from ]');

  { 3. set at the end of the mask }
  Check(M('ab', 'a[b]'), 'set at the end');
  Check(not M('a', 'a[b]'), 'set at the end, name exhausted');
  Check(M('a[', 'a['), 'mask ending with [');
  Check(not M('a', 'a['), 'mask ending with [, name without it');
  Check(M('[', '['), 'lone [');
  Check(M('[]', '[]'), '[] has no closing bracket after the member');
  Check(not M('[', '[]'), '[] needs both characters');
  Check(M('[!', '[!'), '[! is literal');

  { 4. the *.* rule }
  Check(WildMatch('x', '*.*', True), '*.* case sensitive');
  Check(not M('x', 'a*.*'), 'a*.* needs a dot');
  Check(M('a.', 'a*.*'), 'a*.* with a dot');
  Check(M('', '*.*'), 'empty vs *.*');
  Check(not M('x', '*.* '), '*.* with a blank is an ordinary mask');

  { 5. case in sets }
  Check(M('B', '[a-c]'), 'B in [a-c]');
  Check(not WildMatch('B', '[a-c]', True), 'B in [a-c], case sensitive');
  Check(M('b', '[A-C]'), 'b in [A-C]');
  Check(WildMatch('b', '[A-C]', False), 'b in [A-C], explicit');
  Check(not WildMatch('b', '[A-C]', True), 'b in [A-C], case sensitive');

  { 6. backtracking }
  Check(M('aXbXbXc', '*b*c'), 'aXbXbXc vs *b*c');
  Check(M('mississippi', '*iss*ppi'), 'mississippi vs *iss*ppi');
  Check(not M('mississippi', '*iss*ppx'), 'mississippi vs *iss*ppx');
  Check(M('abab', '*ab'), 'abab vs *ab');
  Check(M('aab', 'a*ab'), 'aab vs a*ab');
  Check(not M('ab', 'a*ab'), 'ab vs a*ab');
  Check(M('a/b\c', '*c'), 'star takes separators');

  { 7. UTF-8 mode off }
  Utf8Enabled := False;
  Check(M(PrivetCap, '????????????'), 'twelve bytes');
  Check(not M(PrivetCap, '??????'), 'six question marks fail on bytes');
  Check(M('abc', 'a?c'), 'ASCII without UTF-8');
  Check(M('b', '[a-c]'), 'range without UTF-8');
  Check(M(#$C0, '[' + #$B0 + '-' + #$D0 + ']'), 'byte range');
  Utf8Enabled := True;

  { 3.4 HasWild }
  Check(HasWild('*.pas'), 'HasWild *');
  Check(HasWild('a?'), 'HasWild ?');
  Check(HasWild('a[b'), 'HasWild [');
  Check(not HasWild('plain.txt'), 'HasWild plain');
  Check(not HasWild(']-'), 'HasWild ] and -');
  Check(not HasWild(''), 'HasWild empty');

  { 3.3 lists }
  Check(L('a.pas', '*.pas;*.inc'), 'list ;');
  Check(L('a.inc', '*.pas, *.inc'), 'list with a blank');
  Check(not L('a.txt', '*.pas;*.inc'), 'list miss');
  Check(not L('test.pas', '*.pas|test*'), 'excluded');
  Check(L('main.pas', '*.pas|test*'), 'not excluded');
  Check(L('main.pas', '|test*'), 'exclude only, kept');
  Check(not L('test1', '|test*'), 'exclude only, dropped');
  Check(not L('a', ''), 'empty list');
  Check(not L('', ''), 'empty list, empty name');
  Check(not L('a', '|'), 'bar alone');
  Check(L('anything', '|  '), 'blank exclude text and blank include');
  Check(L('a.inc', '*.pas,*.inc'), 'list ,');
  Check(L('a.inc', '*.pas;*.inc,*.txt'), 'list mixed separators');
  Check(L('a.pas', ';;*.pas;'), 'empty items');
  Check(L('a.pas', '   *.pas   '), 'blanks around an item');
  Check(not L('a.pas', ' ; , '), 'blank items only');
  Check(L('a|b', '*|b'), 'the name is not the exclude mask');
  Check(L('a.pas', '*.pas|x|y'), 'bar in the exclude part is ordinary');
  Check(not L('x|y', '*|x|y'), 'bar in the exclude part matches itself');
  Check(not L('a.pas', '*.pas|*.pas;*.inc'), 'exclude with two masks');
  Check(not L('a.inc', '*.pas;*.inc|*.pas;*.inc'), 'exclude list second mask');
  Check(L('a.pas', '*.pas| '), 'blank exclude text keeps the name');
  Check(L('x', '*.*|a*'), '*.* in a list');
  Check(not L('abc', '*.*|a*'), '*.* include with an exclusion');
  Check(L('README.TXT', '*.txt'), 'list is case insensitive');
  Check(not WildMatchList('README.TXT', '*.txt', True), 'list case sensitive include');
  Check(WildMatchList('test.pas', '*.pas|TEST*', True), 'case sensitive exclude keeps the name');
  Check(not WildMatchList('test.pas', '*.pas|TEST*', False), 'case insensitive exclude fires');
  Check(L(PrivetCap, PSmall + '*'), 'Cyrillic in a list');

  Done;
end.
