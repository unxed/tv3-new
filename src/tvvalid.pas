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

end.
