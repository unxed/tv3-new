{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/validate.h, include/tvision/ttypes.h, include/tvision/tv.h,
  source/tvision/tvalidat.cpp
  See COPYRIGHT.magiblot.

  The validators work on texts only; they are used by the thread of the user interface, and no routine of this unit
  is thread-safe. The members read, write, build and streamableName of the classes, and the constructors with
  StreamableInit, belong to a later unit.

  Parts of the C++ that no unit has yet and no input defines:
    - messageBox(mfError | mfOKButton, ...) shows an error message with printf arguments. ErrorBoxHook stands for
      it: Error of the validators calls it with the message text and the arguments of the C++ call, and does nothing
      while it is nil.
    - TStringCollection is not defined by a unit or by an input. TStringLookupValidator holds and takes a
      TNSCollection of TvObjs whose items are blocks of characters with a terminating zero; that is the part of
      TStringCollection that the validator uses.
    - The texts errorMsg of the classes, and validUnsignedChars and validSignedChars of TRangeValidator, are defined
      in files that are not among the sources of the unit. They are the class variables ErrorMsg, RangeErrorMsg,
      ValidUnsignedChars and ValidSignedChars, which start as empty texts and which the program sets. The texts are
      formats of the printf kind, as the hook receives them.

  A text that the C++ passes as a char pointer is a Pascal string: a parameter that the routine may change (the
  argument s of isValidInput and picture) is a var parameter, and the text ends where the string ends. The member
  pic of TPXPictureValidator is a string that is never nil, because the constructor takes a TStringView. }
unit TvValid;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  ctypes, TvObjs;

type
  { What Transfer of a validator does with the buffer. }
  TVTransfer = (
    vtDataSize = 0,
    vtSetData = 1,
    vtGetData = 2
  );

  { The result of the check of a text against a picture. }
  TPicResult = (
    prComplete = 0,
    prIncomplete = 1,
    prEmpty = 2,
    prError = 3,
    prSyntax = 4,
    prAmbiguous = 5,
    prIncompNoFill = 6
  );

const
  { Status of a validator. }
  vsOk = 0;
  vsSyntax = vsOk + 1;

  { Option flags of a validator: one bit each, and the bits that stay reserved. }
  voFill = 1 shl 0;
  voTransfer = 1 shl 1;
  voReserved = 63 shl 2;

type

  { Shows the error message Format, in which the Args stand for the conversions of the printf kind. }
  TErrorBoxProc = procedure(const Format: string; const Args: array of const);

  PLongValue = ^clong;

var
  { Stands for messageBox(mfError | mfOKButton, Format, Args...); nil does nothing. }
  ErrorBoxHook: TErrorBoxProc = nil;

type
  { The base of the validators: accepts every text. }
  TValidator = class(TvObject)
  public
    Status: Word;
    Options: Word;
    constructor Create; reintroduce;
    procedure Error; virtual;
    function IsValidInput(var Text: string; SuppressFill: Boolean): Boolean; virtual;
    function IsValid(const Text: string): Boolean; virtual;
    function Transfer(var Text: string; Buffer: Pointer; Flag: TVTransfer): Word; virtual;
    { Calls Error when Text is not valid. }
    function Validate(const Text: string): Boolean;
  end;

  { Checks a text against a picture: # a digit, ? a letter, & a letter made upper case, ! any character made upper
    case, @ any character, * a repeat, braces a group, brackets an optional group, a comma an alternative, a semicolon
    the next character as it is. Other characters stand for themselves. }
  TPXPictureValidator = class(TValidator)
  public
    class var ErrorMsg: string;
    constructor Create(const PictureText: string; AutoFill: Boolean); reintroduce;
    procedure Error; override;
    function IsValidInput(var Text: string; SuppressFill: Boolean): Boolean; override;
    function IsValid(const Text: string): Boolean; override;
    function Picture(var Input: string; AutoFill: Boolean): TPicResult; virtual;
  protected
    Pic: string;
  private
    Index: Integer;
    Jndex: Integer;
    function PicAt(Position: Integer): Char;
    function RunPicture(var Input: string; AutoFill: Boolean): TPicResult;
    procedure Consume(Ch: Char; var Input: string);
    procedure ToGroupEnd(var Position: Integer; TermCh: Integer);
    function SkipToComma(TermCh: Integer): Boolean;
    function CalcTerm(TermCh: Integer): Integer;
    function Iteration(var Input: string; TermCh: Integer): TPicResult;
    function Group(var Input: string; TermCh: Integer): TPicResult;
    function CheckComplete(Rslt: TPicResult; TermCh: Integer): TPicResult;
    function Scan(var Input: string; TermCh: Integer): TPicResult;
    function Process(var Input: string; TermCh: Integer): TPicResult;
    function SyntaxCheck: Boolean;
  end;

  { Accepts the texts that hold only the characters of ValidChars. }
  TFilterValidator = class(TValidator)
  public
    class var ErrorMsg: string;
    constructor Create(const AllowedChars: string); reintroduce;
    procedure Error; override;
    function IsValidInput(var Text: string; SuppressFill: Boolean): Boolean; override;
    function IsValid(const Text: string): Boolean; override;
  protected
    ValidChars: string;
  end;

  { Accepts the texts that are whole numbers from Min to Max. }
  TRangeValidator = class(TFilterValidator)
  public
    class var RangeErrorMsg: string;
    class var ValidUnsignedChars: string;
    class var ValidSignedChars: string;
    constructor Create(LowBound, HighBound: LongInt); reintroduce;
    procedure Error; override;
    function IsValid(const Text: string): Boolean; override;
    function Transfer(var Text: string; Buffer: Pointer; Flag: TVTransfer): Word; override;
  protected
    Min: LongInt;
    Max: LongInt;
  end;

  { Accepts the texts that Lookup finds. }
  TLookupValidator = class(TValidator)
  public
    constructor Create; reintroduce;
    function IsValid(const Text: string): Boolean; override;
    function Lookup(const Text: string): Boolean; virtual;
  end;

  { Accepts the texts that are items of a collection of strings. }
  TStringLookupValidator = class(TLookupValidator)
  public
    class var ErrorMsg: string;
    constructor Create(AStrings: TNSCollection); reintroduce;
    destructor Destroy; override;
    procedure Error; override;
    function Lookup(const Text: string): Boolean; override;
    { Destroys the present list, and takes AStrings in its place. }
    procedure NewStringList(AStrings: TNSCollection);
  protected
    Strings: TNSCollection;
  end;

function IsNumber(Ch: Char): Boolean;
function IsLetter(Ch: Char): Boolean;
function IsSpecial(Ch: Char; const Special: string): Boolean;
{ The count of the characters equal to Ch in Text. }
function NumChar(Ch: Char; const Text: string): Byte;
function IsComplete(Outcome: TPicResult): Boolean;
function IsIncomplete(Outcome: TPicResult): Boolean;

implementation

function Uppercase(Ch: Char): Char;
begin
  if (Ch >= 'a') and (Ch <= 'z') then
    Result := Chr(Ord(Ch) - (Ord('a') - Ord('A')))
  else
    Result := Ch;
end;

{ True when every character of Text is one of the characters of Allowed. }
function AllCharsIn(const Text, Allowed: string): Boolean;
var
  Position: Integer;
begin
  for Position := 1 to Length(Text) do
    if Pos(Text[Position], Allowed) = 0 then
      Exit(False);
  Result := True;
end;

{ Reads a decimal whole number at the start of Text, after white space and with an optional sign, as the
  conversion %ld does. A number beyond the range of a clong gives the nearest limit. False when there is no digit. }
function ScanDecimal(const Text: string; out Value: clong): Boolean;
var
  Position: Integer;
  Negative: Boolean;
  Magnitude: QWord;
  Limit: QWord;
  Digit: QWord;
  Saturated: Boolean;
  FoundDigit: Boolean;
begin
  Value := 0;
  Position := 1;
  while (Position <= Length(Text)) and (Text[Position] in [' ', #9, #10, #11, #12, #13]) do
    Inc(Position);

  Negative := False;
  if Position <= Length(Text) then
    case Text[Position] of
      '-':
        begin
          Negative := True;
          Inc(Position);
        end;
      '+':
        Inc(Position);
    end;

  if Negative then
    Limit := QWord(High(clong)) + 1
  else
    Limit := QWord(High(clong));

  Magnitude := 0;
  Saturated := False;
  FoundDigit := False;
  while (Position <= Length(Text)) and (Text[Position] in ['0'..'9']) do
  begin
    FoundDigit := True;
    Digit := Ord(Text[Position]) - Ord('0');
    if not Saturated then
    begin
      if Magnitude > (Limit - Digit) div 10 then
      begin
        Saturated := True;
        Magnitude := Limit;
      end
      else
        Magnitude := Magnitude * 10 + Digit;
    end;
    Inc(Position);
  end;

  Result := FoundDigit;
  if not FoundDigit then
    Exit;

  if not Negative then
    Value := clong(Magnitude)
  else if Magnitude = 0 then
    Value := 0
  else
    Value := clong(-Int64(Magnitude - 1) - 1);
end;

function IsNumber(Ch: Char): Boolean;
begin
  Result := (Ch >= '0') and (Ch <= '9');
end;

function IsLetter(Ch: Char): Boolean;
var
  CaseFolded: Byte;
begin
  CaseFolded := Ord(Ch) and $DF;
  Result := (CaseFolded >= Ord('A')) and (CaseFolded <= Ord('Z'));
end;

function IsSpecial(Ch: Char; const Special: string): Boolean;
begin
  Result := Pos(Ch, Special) > 0;
end;

function NumChar(Ch: Char; const Text: string): Byte;
var
  Position: Integer;
begin
  Result := 0;
  for Position := 1 to Length(Text) do
    if Text[Position] = Ch then
      Inc(Result);
end;

function IsComplete(Outcome: TPicResult): Boolean;
begin
  Result := Outcome in [prComplete, prAmbiguous];
end;

function IsIncomplete(Outcome: TPicResult): Boolean;
begin
  Result := Outcome in [prIncomplete, prIncompNoFill];
end;

{ TValidator }

constructor TValidator.Create;
begin
  inherited Create;
  Status := 0;
  Options := 0;
end;

procedure TValidator.Error;
begin
end;

function TValidator.IsValidInput(var Text: string; SuppressFill: Boolean): Boolean;
begin
  Result := True;
end;

function TValidator.IsValid(const Text: string): Boolean;
begin
  Result := True;
end;

function TValidator.Transfer(var Text: string; Buffer: Pointer; Flag: TVTransfer): Word;
begin
  Result := 0;
end;

function TValidator.Validate(const Text: string): Boolean;
begin
  if IsValid(Text) then
    Exit(True);
  Error;
  Result := False;
end;

{ TPXPictureValidator }

constructor TPXPictureValidator.Create(const PictureText: string; AutoFill: Boolean);
var
  EmptyInput: string;
begin
  inherited Create;
  Pic := PictureText;
  if AutoFill then
    Options := Options or voFill;

  EmptyInput := '';
  if RunPicture(EmptyInput, False) <> prEmpty then
    Status := vsSyntax;
end;

procedure TPXPictureValidator.Error;
begin
  if Assigned(ErrorBoxHook) then
    ErrorBoxHook(ErrorMsg, [Pic]);
end;

function TPXPictureValidator.IsValidInput(var Text: string; SuppressFill: Boolean): Boolean;
var
  FillWanted: Boolean;
begin
  FillWanted := ((Options and voFill) <> 0) and not SuppressFill;
  Result := Picture(Text, FillWanted) <> prError;
end;

function TPXPictureValidator.IsValid(const Text: string): Boolean;
var
  WorkText: string;
begin
  WorkText := Text;
  Result := Picture(WorkText, False) = prComplete;
end;

function TPXPictureValidator.PicAt(Position: Integer): Char;
begin
  if (Position >= 0) and (Position < Length(Pic)) then
    Result := Pic[Position + 1]
  else
    Result := #0;
end;

procedure TPXPictureValidator.Consume(Ch: Char; var Input: string);
begin
  Input[Jndex + 1] := Ch;
  Inc(Index);
  Inc(Jndex);
end;

{ Moves Position over one character, or over one group when a group opens there. }
procedure TPXPictureValidator.ToGroupEnd(var Position: Integer; TermCh: Integer);
var
  BracketDepth: Integer;
  BraceDepth: Integer;
begin
  BracketDepth := 0;
  BraceDepth := 0;
  while True do
  begin
    if Position = TermCh then
      Exit;
    case PicAt(Position) of
      '[': Inc(BracketDepth);
      ']': Dec(BracketDepth);
      '{': Inc(BraceDepth);
      '}': Dec(BraceDepth);
      ';': Inc(Position);
    end;
    Inc(Position);
    if (BracketDepth = 0) and (BraceDepth = 0) then
      Exit;
  end;
end;

function TPXPictureValidator.SkipToComma(TermCh: Integer): Boolean;
begin
  while True do
  begin
    ToGroupEnd(Index, TermCh);
    if (Index = TermCh) or (PicAt(Index) = ',') then
      Break;
  end;
  if PicAt(Index) = ',' then
    Inc(Index);
  Result := Index < TermCh;
end;

function TPXPictureValidator.CalcTerm(TermCh: Integer): Integer;
var
  Position: Integer;
begin
  Position := Index;
  ToGroupEnd(Position, TermCh);
  Result := Position;
end;

function TPXPictureValidator.Iteration(var Input: string; TermCh: Integer): TPicResult;
var
  Repetitions: Integer;
  RepeatCount: Integer;
  GroupStart: Integer;
  GroupEnd: Integer;
begin
  Repetitions := 0;
  Result := prError;

  Inc(Index);
  while IsNumber(PicAt(Index)) do
  begin
    Repetitions := Repetitions * 10 + (Ord(PicAt(Index)) - Ord('0'));
    Inc(Index);
  end;

  GroupStart := Index;
  GroupEnd := CalcTerm(TermCh);

  if Repetitions <> 0 then
  begin
    for RepeatCount := 1 to Repetitions do
    begin
      Index := GroupStart;
      Result := Process(Input, GroupEnd);
      if not IsComplete(Result) then
      begin
        if Result = prEmpty then
          Result := prIncomplete;
        Exit;
      end;
    end;
  end
  else
  begin
    repeat
      Index := GroupStart;
      Result := Process(Input, GroupEnd);
    until Result <> prComplete;

    if (Result = prEmpty) or (Result = prError) then
    begin
      Inc(Index);
      Result := prAmbiguous;
    end;
  end;
  Index := GroupEnd;
end;

function TPXPictureValidator.Group(var Input: string; TermCh: Integer): TPicResult;
var
  GroupEnd: Integer;
begin
  GroupEnd := CalcTerm(TermCh);
  Inc(Index);
  Result := Process(Input, GroupEnd - 1);
  if not IsIncomplete(Result) then
    Index := GroupEnd;
end;

function TPXPictureValidator.CheckComplete(Rslt: TPicResult; TermCh: Integer): TPicResult;
var
  Probe: Integer;
  Skipping: Boolean;
begin
  Result := Rslt;
  if not IsIncomplete(Rslt) then
    Exit;

  Probe := Index;
  Skipping := True;
  while Skipping do
    case PicAt(Probe) of
      '[':
        ToGroupEnd(Probe, TermCh);
      '*':
        begin
          if not IsNumber(PicAt(Probe + 1)) then
            Inc(Probe);
          ToGroupEnd(Probe, TermCh);
        end;
    else
      Skipping := False;
    end;

  if Probe = TermCh then
    Result := prAmbiguous;
end;

function TPXPictureValidator.Scan(var Input: string; TermCh: Integer): TPicResult;
var
  Ch: Char;
  Outcome: TPicResult;
begin
  Outcome := prEmpty;

  while (Index <> TermCh) and (PicAt(Index) <> ',') do
  begin
    if Jndex >= Length(Input) then
      Exit(CheckComplete(Outcome, TermCh));

    Ch := Input[Jndex + 1];
    case PicAt(Index) of
      '#':
        begin
          if not IsNumber(Ch) then
            Exit(prError);
          Consume(Ch, Input);
        end;
      '?':
        begin
          if not IsLetter(Ch) then
            Exit(prError);
          Consume(Ch, Input);
        end;
      '&':
        begin
          if not IsLetter(Ch) then
            Exit(prError);
          Consume(Uppercase(Ch), Input);
        end;
      '!':
        Consume(Uppercase(Ch), Input);
      '@':
        Consume(Ch, Input);
      '*':
        begin
          Outcome := Iteration(Input, TermCh);
          if not IsComplete(Outcome) then
            Exit(Outcome);
          if Outcome = prError then
            Outcome := prAmbiguous;
        end;
      '{':
        begin
          Outcome := Group(Input, TermCh);
          if not IsComplete(Outcome) then
            Exit(Outcome);
        end;
      '[':
        begin
          Outcome := Group(Input, TermCh);
          if IsIncomplete(Outcome) then
            Exit(Outcome);
          if Outcome = prError then
            Outcome := prAmbiguous;
        end;
    else
      begin
        if PicAt(Index) = ';' then
          Inc(Index);
        if (Uppercase(PicAt(Index)) <> Uppercase(Ch)) and (Ch <> ' ') then
          Exit(prError);
        Consume(PicAt(Index), Input);
      end;
    end;

    if Outcome = prAmbiguous then
      Outcome := prIncompNoFill
    else
      Outcome := prIncomplete;
  end;

  if Outcome = prIncompNoFill then
    Result := prAmbiguous
  else
    Result := prComplete;
end;

function TPXPictureValidator.Process(var Input: string; TermCh: Integer): TPicResult;
var
  Outcome: TPicResult;
  Reported: TPicResult;
  SawIncomplete: Boolean;
  AltStartIndex: Integer;
  AltStartJndex: Integer;
  IncompleteIndex: Integer;
  IncompleteJndex: Integer;
  Settled: Boolean;
begin
  SawIncomplete := False;
  AltStartIndex := Index;
  AltStartJndex := Jndex;
  IncompleteIndex := 0;
  IncompleteJndex := 0;

  repeat
    Outcome := Scan(Input, TermCh);

    { A complete result counts only when it reaches farther in the input than the earlier incomplete one. }
    if (Outcome = prComplete) and SawIncomplete and (Jndex < IncompleteJndex) then
    begin
      Outcome := prIncomplete;
      Jndex := IncompleteJndex;
    end;

    Settled := (Outcome <> prError) and (Outcome <> prIncomplete);
    if not Settled then
    begin
      Reported := Outcome;

      if (not SawIncomplete) and (Outcome = prIncomplete) then
      begin
        SawIncomplete := True;
        IncompleteIndex := Index;
        IncompleteJndex := Jndex;
      end;
      Index := AltStartIndex;
      Jndex := AltStartJndex;
      if not SkipToComma(TermCh) then
      begin
        if SawIncomplete then
        begin
          Reported := prIncomplete;
          Index := IncompleteIndex;
          Jndex := IncompleteJndex;
        end;
        Exit(Reported);
      end;
      AltStartIndex := Index;
    end;
  until Settled;

  if (Outcome = prComplete) and SawIncomplete then
    Result := prAmbiguous
  else
    Result := Outcome;
end;

function TPXPictureValidator.SyntaxCheck: Boolean;
var
  Position: Integer;
  PicLength: Integer;
  BracketDepth: Integer;
  BraceDepth: Integer;
begin
  PicLength := Length(Pic);
  if PicLength = 0 then
    Exit(False);
  if Pic[PicLength] = ';' then
    Exit(False);

  Position := 0;
  BracketDepth := 0;
  BraceDepth := 0;
  while Position < PicLength do
  begin
    case PicAt(Position) of
      '[': Inc(BracketDepth);
      ']': Dec(BracketDepth);
      '{': Inc(BraceDepth);
      '}': Dec(BraceDepth);
      ';': Inc(Position);
    end;
    Inc(Position);
  end;

  Result := (BracketDepth = 0) and (BraceDepth = 0);
end;

function TPXPictureValidator.RunPicture(var Input: string; AutoFill: Boolean): TPicResult;
var
  Reprocess: Boolean;
  Outcome: TPicResult;
begin
  if not SyntaxCheck then
    Exit(prSyntax);
  if Length(Input) = 0 then
    Exit(prEmpty);

  Jndex := 0;
  Index := 0;

  Outcome := Process(Input, Length(Pic));
  if (Outcome <> prError) and (Jndex < Length(Input)) then
    Outcome := prError;

  if (Outcome = prIncomplete) and AutoFill then
  begin
    Reprocess := False;
    while (Index < Length(Pic)) and not IsSpecial(PicAt(Index), '#?&!@*{}[],') do
    begin
      if PicAt(Index) = ';' then
        Inc(Index);
      Input := Input + PicAt(Index);
      Inc(Index);
      Reprocess := True;
    end;

    Jndex := 0;
    Index := 0;
    if Reprocess then
      Outcome := Process(Input, Length(Pic));
  end;

  case Outcome of
    prAmbiguous: Result := prComplete;
    prIncompNoFill: Result := prIncomplete;
  else
    Result := Outcome;
  end;
end;

function TPXPictureValidator.Picture(var Input: string; AutoFill: Boolean): TPicResult;
begin
  Result := RunPicture(Input, AutoFill);
end;

{ TFilterValidator }

constructor TFilterValidator.Create(const AllowedChars: string);
begin
  inherited Create;
  ValidChars := AllowedChars;
end;

procedure TFilterValidator.Error;
begin
  if Assigned(ErrorBoxHook) then
    ErrorBoxHook(ErrorMsg, []);
end;

function TFilterValidator.IsValidInput(var Text: string; SuppressFill: Boolean): Boolean;
begin
  Result := AllCharsIn(Text, ValidChars);
end;

function TFilterValidator.IsValid(const Text: string): Boolean;
begin
  Result := AllCharsIn(Text, ValidChars);
end;

{ TRangeValidator }

constructor TRangeValidator.Create(LowBound, HighBound: LongInt);
begin
  inherited Create('');
  Min := LowBound;
  Max := HighBound;
  if LowBound >= 0 then
    ValidChars := ValidUnsignedChars
  else
    ValidChars := ValidSignedChars;
end;

procedure TRangeValidator.Error;
begin
  if Assigned(ErrorBoxHook) then
    ErrorBoxHook(RangeErrorMsg, [Min, Max]);
end;

function TRangeValidator.IsValid(const Text: string): Boolean;
var
  Number: clong;
begin
  Result := False;
  if not inherited IsValid(Text) then
    Exit;
  if not ScanDecimal(Text, Number) then
    Exit;
  Result := (Number >= Min) and (Number <= Max);
end;

function TRangeValidator.Transfer(var Text: string; Buffer: Pointer; Flag: TVTransfer): Word;
var
  Number: clong;
begin
  if (Options and voTransfer) = 0 then
    Exit(0);

  case Flag of
    vtDataSize:
      ;
    vtGetData:
      begin
        ScanDecimal(Text, Number);
        PLongValue(Buffer)^ := Number;
      end;
    vtSetData:
      Str(PLongValue(Buffer)^, Text);
  end;
  Result := SizeOf(clong);
end;

{ TLookupValidator }

constructor TLookupValidator.Create;
begin
  inherited Create;
end;

function TLookupValidator.IsValid(const Text: string): Boolean;
begin
  Result := Lookup(Text);
end;

function TLookupValidator.Lookup(const Text: string): Boolean;
begin
  Result := True;
end;

{ TStringLookupValidator }

constructor TStringLookupValidator.Create(AStrings: TNSCollection);
begin
  inherited Create;
  Strings := AStrings;
end;

destructor TStringLookupValidator.Destroy;
begin
  NewStringList(nil);
  inherited Destroy;
end;

procedure TStringLookupValidator.Error;
begin
  if Assigned(ErrorBoxHook) then
    ErrorBoxHook(ErrorMsg, []);
end;

{ Compares two blocks of characters that end with a zero; a nil pointer is an empty text. }
function StringMatch(Item, Wanted: Pointer): Boolean;
var
  ItemChars: PAnsiChar;
  WantedChars: PAnsiChar;
begin
  ItemChars := PAnsiChar(Item);
  WantedChars := PAnsiChar(Wanted);
  if ItemChars = nil then
    Exit((WantedChars = nil) or (WantedChars^ = #0));
  if WantedChars = nil then
    Exit(ItemChars^ = #0);

  while (ItemChars^ = WantedChars^) and (ItemChars^ <> #0) do
  begin
    Inc(ItemChars);
    Inc(WantedChars);
  end;
  Result := ItemChars^ = WantedChars^;
end;

function TStringLookupValidator.Lookup(const Text: string): Boolean;
var
  Wanted: array[0..256] of AnsiChar;
  TextLength: Integer;
  Found: Pointer;
begin
  TextLength := Length(Text);
  if TextLength > 0 then
    Move(Text[1], Wanted[0], TextLength);
  Wanted[TextLength] := #0;
  Found := Strings.FirstThat(@StringMatch, @Wanted[0]);
  Result := Found <> nil;
end;

procedure TStringLookupValidator.NewStringList(AStrings: TNSCollection);
begin
  if Strings <> nil then
    TvObject.DestroyObject(Strings);
  Strings := AStrings;
end;

end.
