{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/validate.h, include/tvision/ttypes.h, include/tvision/tv.h,
  source/tvision/tvalidat.cpp, source/tvision/tvtext2.cpp
  See COPYRIGHT.magiblot.

  The expected values are worked out by hand from the C++ routines. The texts of the unit (the error messages and the
  valid characters of the range validator) are checked as the unit sets them. The hook of the error box records what
  the validators ask it to show. }
program t_valid;

{$mode objfpc}

uses
  ctypes, TvObjs, TvValid;

{$I testlib.inc}

type
  { Accepts a text unless Reject is set, and counts the calls of Error. }
  TProbeValidator = class(TValidator)
  public
    Reject: Boolean;
    ErrorCalls: Integer;
    procedure Error; override;
    function IsValid(const Text: string): Boolean; override;
  end;

  { A lookup that accepts the texts of odd length. }
  TOddLookup = class(TLookupValidator)
  public
    function Lookup(const Text: string): Boolean; override;
  end;

  { A collection of strings that counts the items that it frees. }
  TCountedStrings = class(TNSCollection)
  protected
    procedure FreeItem(Item: Pointer); override;
  end;

var
  BoxCalls: Integer = 0;
  BoxFormat: string = '';
  BoxArgCount: Integer = 0;
  BoxText: string = '';
  BoxFirst: Int64 = 0;
  BoxSecond: Int64 = 0;
  FreedStrings: Integer = 0;

procedure TProbeValidator.Error;
begin
  Inc(ErrorCalls);
end;

function TProbeValidator.IsValid(const Text: string): Boolean;
begin
  Result := not Reject;
end;

function TOddLookup.Lookup(const Text: string): Boolean;
begin
  Result := (Length(Text) mod 2) = 1;
end;

procedure TCountedStrings.FreeItem(Item: Pointer);
begin
  Inc(FreedStrings);
end;

procedure RecordBox(const Format: string; const Args: array of const);
begin
  Inc(BoxCalls);
  BoxFormat := Format;
  BoxArgCount := Length(Args);
  BoxText := '';
  BoxFirst := 0;
  BoxSecond := 0;
  if Length(Args) > 0 then
  begin
    if Args[0].VType = vtString then
      BoxText := Args[0].VString^
    else if Args[0].VType = vtInteger then
      BoxFirst := Args[0].VInteger;
  end;
  if (Length(Args) > 1) and (Args[1].VType = vtInteger) then
    BoxSecond := Args[1].VInteger;
end;

function NewFruit: TCountedStrings;
begin
  Result := TCountedStrings.Create(8, 4);
  Result.Insert(Pointer(PAnsiChar('apple')));
  Result.Insert(Pointer(PAnsiChar('pear')));
  Result.Insert(Pointer(PAnsiChar('fig')));
end;

{ Checks Text against the picture and gives the result; the text may be changed. }
function Match(const PictureText: string; var Text: string; AutoFill: Boolean): TPicResult;
var
  Validator: TPXPictureValidator;
begin
  Validator := TPXPictureValidator.Create(PictureText, False);
  try
    Result := Validator.Picture(Text, AutoFill);
  finally
    Validator.Free;
  end;
end;

procedure TestTexts;
begin
  Check(TPXPictureValidator.ErrorMsg = 'Error in picture format.'#10' %s', 'Picture error text');
  Check(TFilterValidator.ErrorMsg = 'Invalid character in input', 'Filter error text');
  Check(TRangeValidator.RangeErrorMsg = 'Value not in the range %d to %d', 'Range error text');
  Check(TStringLookupValidator.ErrorMsg = 'Input is not in list of valid strings', 'Lookup error text');
  Check(TRangeValidator.ValidUnsignedChars = '+0123456789', 'Unsigned characters');
  Check(TRangeValidator.ValidSignedChars = '+-0123456789', 'Signed characters');
end;

procedure TestFreeFunctions;
begin
  Check(IsNumber('0') and IsNumber('9') and IsNumber('5'), 'IsNumber digits');
  Check(not IsNumber('/') and not IsNumber(':') and not IsNumber('a'), 'IsNumber non digits');
  Check(IsLetter('a') and IsLetter('z') and IsLetter('A') and IsLetter('Z'), 'IsLetter letters');
  Check(not IsLetter('@') and not IsLetter('[') and not IsLetter('`') and not IsLetter('{'),
    'IsLetter characters next to the letters');
  Check(not IsLetter('5') and not IsLetter(#$E1), 'IsLetter digit and high character');
  Check(IsSpecial('#', '#?&') and IsSpecial('&', '#?&'), 'IsSpecial finds');
  Check(not IsSpecial('x', '#?&') and not IsSpecial('x', ''), 'IsSpecial does not find');
  Check(NumChar('a', 'banana') = 3, 'NumChar counts the characters');
  Check(NumChar('z', 'banana') = 0, 'NumChar of a missing character');
  Check(NumChar('a', '') = 0, 'NumChar of an empty text');
  Check(IsComplete(prComplete) and IsComplete(prAmbiguous), 'IsComplete true');
  Check(not IsComplete(prIncomplete) and not IsComplete(prEmpty) and not IsComplete(prError) and
    not IsComplete(prIncompNoFill) and not IsComplete(prSyntax), 'IsComplete false');
  Check(IsIncomplete(prIncomplete) and IsIncomplete(prIncompNoFill), 'IsIncomplete true');
  Check(not IsIncomplete(prComplete) and not IsIncomplete(prAmbiguous) and not IsIncomplete(prEmpty) and
    not IsIncomplete(prError), 'IsIncomplete false');
end;

procedure TestBaseValidator;
var
  Plain: TValidator;
  Probe: TProbeValidator;
  Text: string;
  Number: clong;
begin
  Plain := TValidator.Create;
  try
    Text := 'anything';
    Number := 77;
    Check(Plain.Status = vsOk, 'TValidator starts with status 0');
    Check(Plain.Options = 0, 'TValidator starts with no options');
    Check(Plain.IsValid('abc'), 'TValidator.IsValid accepts');
    Check(Plain.IsValidInput(Text, False), 'TValidator.IsValidInput accepts');
    Check(Text = 'anything', 'TValidator.IsValidInput leaves the text');
    Check(Plain.Transfer(Text, @Number, vtGetData) = 0, 'TValidator.Transfer gives 0');
    Check(Number = 77, 'TValidator.Transfer leaves the buffer');
    Check(Plain.Validate('abc'), 'TValidator.Validate accepts');
    Plain.Error;
  finally
    Plain.Free;
  end;

  Probe := TProbeValidator.Create;
  try
    Check(Probe.Validate('x'), 'Validate is True for a valid text');
    Check(Probe.ErrorCalls = 0, 'Validate does not call Error for a valid text');
    Probe.Reject := True;
    Check(not Probe.Validate('x'), 'Validate is False for an invalid text');
    Check(Probe.ErrorCalls = 1, 'Validate calls Error once for an invalid text');
  finally
    Probe.Free;
  end;

  Check((voFill = 1) and (voTransfer = 2) and (voReserved = $FC), 'option flags');
  Check((vsOk = 0) and (vsSyntax = 1), 'status values');
end;

procedure TestFilter;
var
  Filter: TFilterValidator;
  Text: string;
begin
  Filter := TFilterValidator.Create('0123456789');
  try
    Text := '12a';
    Check(Filter.IsValid('123'), 'Filter accepts valid characters');
    Check(not Filter.IsValid('12a'), 'Filter refuses a character outside the set');
    Check(Filter.IsValid(''), 'Filter accepts an empty text');
    Check(not Filter.IsValid(' 1'), 'Filter refuses a space');
    Check(not Filter.IsValidInput(Text, False), 'Filter.IsValidInput refuses');
    Text := '4711';
    Check(Filter.IsValidInput(Text, True), 'Filter.IsValidInput accepts, fill suppressed');
    Check(Filter.IsValidInput(Text, False), 'Filter.IsValidInput accepts');
    Check(Text = '4711', 'Filter.IsValidInput leaves the text');
    Check(Filter.Status = vsOk, 'Filter status');

    BoxCalls := 0;
    ErrorBoxHook := nil;
    Filter.Error;
    Check(BoxCalls = 0, 'Error does nothing while the hook is nil');
    ErrorBoxHook := @RecordBox;
    Filter.Error;
    Check((BoxCalls = 1) and (BoxFormat = 'Invalid character in input') and (BoxArgCount = 0),
      'Filter.Error shows the message without arguments');
    Check(not Filter.Validate('x'), 'Filter.Validate refuses');
    Check(BoxCalls = 2, 'Filter.Validate shows the error');
    Check(Filter.Validate('7'), 'Filter.Validate accepts');
    Check(BoxCalls = 2, 'Filter.Validate of a valid text shows nothing');
    ErrorBoxHook := nil;
  finally
    Filter.Free;
  end;

  Filter := TFilterValidator.Create('');
  try
    Check(Filter.IsValid(''), 'Filter with no characters accepts the empty text');
    Check(not Filter.IsValid('a'), 'Filter with no characters refuses a text');
  finally
    Filter.Free;
  end;
end;

procedure TestRange;
var
  Range: TRangeValidator;
  Text: string;
  Number: clong;
begin
  Range := TRangeValidator.Create(1, 100);
  try
    Check(Range.IsValid('+50'), 'Range accepts a plus sign');
    Check(Range.Status = vsOk, 'Range status');
    Check(Range.Options = 0, 'Range options');
    Check(Range.IsValid('50'), 'Range accepts 50');
    Check(Range.IsValid('1'), 'Range accepts the lower limit');
    Check(Range.IsValid('100'), 'Range accepts the upper limit');
    Check(Range.IsValid('007'), 'Range accepts leading zeros');
    Check(not Range.IsValid('0'), 'Range refuses below the lower limit');
    Check(not Range.IsValid('101'), 'Range refuses above the upper limit');
    Check(not Range.IsValid('-5'), 'Range with a non negative lower limit refuses the sign');
    Check(not Range.IsValid(''), 'Range refuses an empty text');
    Check(not Range.IsValid('5x'), 'Range refuses a character outside the set');
    Check(not Range.IsValid('99999999999999999999999'), 'Range refuses a number beyond the type');
    Text := '12';
    Check(Range.IsValidInput(Text, False), 'Range.IsValidInput accepts the characters of the set');
    Text := '500';
    Check(Range.IsValidInput(Text, False), 'Range.IsValidInput does not check the range');
    Text := '5-';
    Check(not Range.IsValidInput(Text, False), 'Range.IsValidInput refuses a sign here');
  finally
    Range.Free;
  end;

  Range := TRangeValidator.Create(-5, 5);
  try
    Check(Range.IsValid('-3'), 'Signed range accepts -3');
    Check(Range.IsValid('-5') and Range.IsValid('5'), 'Signed range accepts its limits');
    Check(not Range.IsValid('-6') and not Range.IsValid('6'), 'Signed range refuses beyond its limits');
    Check(Range.IsValid('5-3'), 'Signed range reads the number at the start of the text');
    Check(not Range.IsValid('-'), 'Signed range refuses a sign alone');
    Check(not Range.IsValid('--3'), 'Signed range refuses a double sign');
    Check(Range.IsValid('-0'), 'Signed range accepts -0');
  finally
    Range.Free;
  end;

  Range := TRangeValidator.Create(0, 5);
  try
    Check(not Range.IsValid('-0'), 'Unsigned set is chosen for a lower limit of 0');
  finally
    Range.Free;
  end;

  Range := TRangeValidator.Create(-1, 5);
  try
    Check(Range.IsValid('-0'), 'Signed set is chosen for a lower limit below 0');

    BoxCalls := 0;
    ErrorBoxHook := @RecordBox;
    Range.Error;
    Check((BoxCalls = 1) and (BoxFormat = 'Value not in the range %d to %d') and (BoxArgCount = 2),
      'Range.Error shows the message with two arguments');
    Check((BoxFirst = -1) and (BoxSecond = 5), 'Range.Error passes the limits');
    Check(not Range.Validate('9'), 'Range.Validate refuses');
    Check(BoxCalls = 2, 'Range.Validate shows the error');
    ErrorBoxHook := nil;

    Text := '42';
    Number := 5;
    Check(Range.Transfer(Text, @Number, vtGetData) = 0, 'Transfer without voTransfer gives 0');
    Check(Number = 5, 'Transfer without voTransfer leaves the buffer');
    Range.Options := voTransfer;
    Check(Range.Transfer(Text, @Number, vtDataSize) = SizeOf(clong), 'Transfer vtDataSize gives the size of a long');
    Check((Number = 5) and (Text = '42'), 'Transfer vtDataSize changes nothing');
    Check(Range.Transfer(Text, @Number, vtGetData) = SizeOf(clong), 'Transfer vtGetData gives the size of a long');
    Check(Number = 42, 'Transfer vtGetData reads the number');
    Number := -17;
    Check(Range.Transfer(Text, @Number, vtSetData) = SizeOf(clong), 'Transfer vtSetData gives the size of a long');
    Check(Text = '-17', 'Transfer vtSetData writes the number');
    Text := '-8';
    Range.Transfer(Text, @Number, vtGetData);
    Check(Number = -8, 'Transfer vtGetData reads a negative number');
  finally
    Range.Free;
  end;
end;

procedure TestLookup;
var
  Lookup: TLookupValidator;
  Odd: TOddLookup;
begin
  Lookup := TLookupValidator.Create;
  try
    Check(Lookup.Status = vsOk, 'Lookup status');
    Check(Lookup.Lookup('anything'), 'TLookupValidator.Lookup accepts');
    Check(Lookup.IsValid('anything'), 'TLookupValidator.IsValid asks Lookup');
    Check(Lookup.Validate(''), 'TLookupValidator.Validate accepts');
  finally
    Lookup.Free;
  end;

  Odd := TOddLookup.Create;
  try
    Check(Odd.IsValid('abc'), 'IsValid is the result of Lookup, True');
    Check(not Odd.IsValid('ab'), 'IsValid is the result of Lookup, False');
    BoxCalls := 0;
    ErrorBoxHook := @RecordBox;
    Check(not Odd.Validate('ab'), 'Validate of a lookup refuses');
    Check(BoxCalls = 0, 'The base Error shows nothing');
    ErrorBoxHook := nil;
  finally
    Odd.Free;
  end;
end;

procedure TestStringLookup;
var
  Validator: TStringLookupValidator;
begin
  FreedStrings := 0;
  Validator := TStringLookupValidator.Create(NewFruit);
  try
    Check(Validator.IsValid('apple'), 'Lookup finds the first string');
    Check(Validator.IsValid('fig'), 'Lookup finds the last string');
    Check(Validator.IsValid('pear'), 'Lookup finds a string');
    Check(not Validator.IsValid('Apple'), 'Lookup is case sensitive');
    Check(not Validator.IsValid('app'), 'Lookup does not match a prefix');
    Check(not Validator.IsValid('apples'), 'Lookup does not match a longer text');
    Check(not Validator.IsValid(''), 'Lookup does not find the empty text');
    Check(Validator.Lookup('pear'), 'Lookup is the search');

    BoxCalls := 0;
    ErrorBoxHook := @RecordBox;
    Check(not Validator.Validate('plum'), 'Validate refuses a string that is not in the list');
    Check((BoxCalls = 1) and (BoxFormat = 'Input is not in list of valid strings') and (BoxArgCount = 0),
      'Error shows the message without arguments');
    ErrorBoxHook := nil;

    Validator.NewStringList(nil);
    Check(FreedStrings = 3, 'NewStringList destroys the present list and its items');
    Validator.NewStringList(NewFruit);
    Check(FreedStrings = 3, 'NewStringList with no present list destroys nothing');
    Check(Validator.IsValid('fig'), 'The new list is searched');
  finally
    Validator.Free;
  end;
  Check(FreedStrings = 6, 'The destructor destroys the list');

  FreedStrings := 0;
  Validator := TStringLookupValidator.Create(NewFruit);
  try
    Validator.NewStringList(TCountedStrings.Create(4, 4));
    Check(FreedStrings = 3, 'NewStringList destroys the old list when it takes another');
    Check(not Validator.IsValid('fig'), 'The empty list finds nothing');
  finally
    Validator.Free;
  end;
  Check(FreedStrings = 3, 'The destructor destroys an empty list without items');
end;

procedure TestPictureSyntax;
var
  Validator: TPXPictureValidator;
begin
  Validator := TPXPictureValidator.Create('###', False);
  Check(Validator.Status = vsOk, 'A good picture gives status 0');
  Check(Validator.Options = 0, 'No fill option');
  Validator.Free;

  Validator := TPXPictureValidator.Create('###', True);
  Check((Validator.Options and voFill) <> 0, 'Fill option');
  Validator.Free;

  Validator := TPXPictureValidator.Create('[#', False);
  Check(Validator.Status = vsSyntax, 'An open bracket is a syntax error');
  Validator.Free;

  Validator := TPXPictureValidator.Create('#}', False);
  Check(Validator.Status = vsSyntax, 'A closing brace without an opening one is a syntax error');
  Validator.Free;

  Validator := TPXPictureValidator.Create('', False);
  Check(Validator.Status = vsSyntax, 'An empty picture is a syntax error');
  Validator.Free;

  Validator := TPXPictureValidator.Create('#;', False);
  Check(Validator.Status = vsSyntax, 'A picture that ends with a semicolon is a syntax error');
  Validator.Free;

  Validator := TPXPictureValidator.Create(';[#', False);
  Check(Validator.Status = vsOk, 'A bracket after a semicolon is not counted');
  Validator.Free;

  Validator := TPXPictureValidator.Create('[#', False);
  try
    Check(not Validator.IsValid('1'), 'IsValid is False for a picture with a syntax error');
    Check(not Validator.IsValid(''), 'IsValid of the empty text is False for a picture with a syntax error');
    Check(Validator.Validate('1') = False, 'Validate refuses for a picture with a syntax error');
  finally
    Validator.Free;
  end;
end;

procedure TestPictureDigits;
var
  Text: string;
begin
  Text := '123';
  Check(Match('###', Text, False) = prComplete, 'Digits: three digits are complete');
  Text := '12';
  Check(Match('###', Text, False) = prIncomplete, 'Digits: two digits are incomplete');
  Text := '12';
  Check(Match('###', Text, True) = prIncomplete, 'Digits: two digits are incomplete with fill');
  Check(Text = '12', 'Digits: nothing is filled in before a digit');
  Text := '12a';
  Check(Match('###', Text, False) = prError, 'Digits: a letter is an error');
  Text := '1234';
  Check(Match('###', Text, False) = prError, 'Digits: too many digits are an error');
  Text := '';
  Check(Match('###', Text, False) = prEmpty, 'Digits: an empty text is empty');
  Text := '1';
  Check(Match('[#', Text, False) = prSyntax, 'A syntax error gives prSyntax');
  Text := '';
  Check(Match('[#', Text, False) = prSyntax, 'A syntax error is found before an empty text');
end;

procedure TestPictureKinds;
var
  Text: string;
begin
  Text := 'ab';
  Check(Match('&&', Text, False) = prComplete, 'Upper case letters are complete');
  Check(Text = 'AB', 'The & makes letters upper case');
  Text := 'a1';
  Check(Match('&&', Text, False) = prError, 'The & does not take a digit');
  Text := 'ab';
  Check(Match('??', Text, False) = prComplete, 'Letters are complete');
  Check(Text = 'ab', 'The ? keeps the case');
  Text := '1b';
  Check(Match('??', Text, False) = prError, 'The ? does not take a digit');
  Text := 'a1';
  Check(Match('!!', Text, False) = prComplete, 'The ! takes any character');
  Check(Text = 'A1', 'The ! makes upper case');
  Text := '1 ';
  Check(Match('@@', Text, False) = prComplete, 'The @ takes any character');
  Check(Text = '1 ', 'The @ keeps the text');
end;

procedure TestPictureLiterals;
var
  Text: string;
  Validator: TPXPictureValidator;
begin
  Text := '12/34';
  Check(Match('##/##', Text, False) = prComplete, 'A literal is matched');
  Text := '1234';
  Check(Match('##/##', Text, False) = prError, 'A missing literal is an error');
  Text := '12 34';
  Check(Match('##/##', Text, False) = prComplete, 'A space stands for the literal');
  Check(Text = '12/34', 'A space is replaced by the literal');
  Text := '12';
  Check(Match('##/##', Text, False) = prIncomplete, 'Without fill the text stays incomplete');
  Check(Text = '12', 'Without fill the text is not changed');
  Text := '12';
  Check(Match('##/##', Text, True) = prIncomplete, 'With fill the text is still incomplete');
  Check(Text = '12/', 'With fill the literals up to the next item are added');
  Text := '#';
  Check(Match(';#', Text, False) = prComplete, 'A semicolon makes the next character a literal');
  Text := '5';
  Check(Match(';#', Text, False) = prError, 'A literal # does not take a digit');
  Text := 'X';
  Check(Match('x', Text, False) = prComplete, 'A literal is matched without regard to case');
  Check(Text = 'x', 'A matched literal is written as in the picture');

  Validator := TPXPictureValidator.Create('##/##', True);
  try
    Text := '12';
    Check(Validator.IsValidInput(Text, False), 'IsValidInput accepts an incomplete text');
    Check(Text = '12/', 'IsValidInput fills in with the fill option');
    Text := '12';
    Check(Validator.IsValidInput(Text, True), 'IsValidInput accepts an incomplete text, fill suppressed');
    Check(Text = '12', 'IsValidInput does not fill when it is suppressed');
    Text := '1x';
    Check(not Validator.IsValidInput(Text, False), 'IsValidInput refuses an error');
    Text := '12/34';
    Check(Validator.IsValid(Text), 'IsValid accepts a complete text');
    Text := '12/3';
    Check(not Validator.IsValid(Text), 'IsValid refuses an incomplete text');
    Check(Text = '12/3', 'IsValid does not change its text');
    Check(not Validator.IsValid(''), 'IsValid refuses the empty text');
    Check(Validator.Validate('12/34'), 'Validate accepts a complete text');
    BoxCalls := 0;
    ErrorBoxHook := @RecordBox;
    Check(not Validator.Validate('12/'), 'Validate refuses an incomplete text');
    Check((BoxCalls = 1) and (BoxFormat = 'Error in picture format.'#10' %s') and (BoxArgCount = 1),
      'Error shows the message with the picture');
    Check(BoxText = '##/##', 'The argument of the message is the picture');
    ErrorBoxHook := nil;
  finally
    Validator.Free;
  end;
end;

procedure TestPictureOptional;
var
  Text: string;
begin
  Text := '1';
  Check(Match('#[#]', Text, False) = prComplete, 'An optional digit may be missing');
  Text := '12';
  Check(Match('#[#]', Text, False) = prComplete, 'An optional digit may be there');
  Text := '1x';
  Check(Match('#[#]', Text, False) = prError, 'A wrong character after an optional group is an error');
  Text := '123';
  Check(Match('#[#]', Text, False) = prError, 'Too much after an optional group is an error');
end;

procedure TestPictureGroups;
var
  Text: string;
begin
  Text := '12-3';
  Check(Match('{##}-#', Text, False) = prComplete, 'A group and a literal are complete');
  Text := '1';
  Check(Match('{##}-#', Text, False) = prIncomplete, 'A half group is incomplete');
  Text := '12-';
  Check(Match('{##}-#', Text, False) = prIncomplete, 'A missing last item is incomplete');
  Text := 'a';
  Check(Match('{##}-#', Text, False) = prError, 'A wrong first character is an error');
end;

procedure TestPictureAlternatives;
var
  Text: string;
begin
  Text := '5';
  Check(Match('#,?', Text, False) = prComplete, 'The first alternative is taken');
  Text := 'a';
  Check(Match('#,?', Text, False) = prComplete, 'The second alternative is taken');
  Text := '-';
  Check(Match('#,?', Text, False) = prError, 'No alternative takes the character');
  Text := '55';
  Check(Match('#,?', Text, False) = prError, 'An alternative does not take a longer text');
end;

procedure TestPictureRepeat;
var
  Text: string;
begin
  Text := '123';
  Check(Match('*#', Text, False) = prComplete, 'A repeat takes any count: three digits');
  Text := '12a';
  Check(Match('*#', Text, False) = prError, 'A repeat stops at a wrong character');
  Text := '123';
  Check(Match('*3#', Text, False) = prComplete, 'A counted repeat takes its count');
  Text := '12';
  Check(Match('*3#', Text, False) = prIncomplete, 'A counted repeat with too few is incomplete');
  Text := '1234';
  Check(Match('*3#', Text, False) = prError, 'A counted repeat with too many is an error');
  Text := '1a';
  Check(Match('*3#', Text, False) = prError, 'A counted repeat with a wrong character is an error');
end;

procedure TestEnumerations;
begin
  Check(TPicResult(0) = prComplete, 'The first picture result is prComplete');
  Check(TPicResult(6) = prIncompNoFill, 'The last picture result is prIncompNoFill');
  Check(TVTransfer(0) = vtDataSize, 'The first transfer flag is vtDataSize');
  Check(TVTransfer(2) = vtGetData, 'The last transfer flag is vtGetData');
end;

begin
  TestTexts;
  TestFreeFunctions;
  TestBaseValidator;
  TestFilter;
  TestRange;
  TestLookup;
  TestStringLookup;
  TestPictureSyntax;
  TestPictureDigits;
  TestPictureKinds;
  TestPictureLiterals;
  TestPictureOptional;
  TestPictureGroups;
  TestPictureAlternatives;
  TestPictureRepeat;
  TestEnumerations;
  Done;
end.
