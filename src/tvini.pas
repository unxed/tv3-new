{ Reads, edits and writes INI files while keeping every line the program did not change: comments, blank lines, order,
  spacing, quoting and line ends. Lines that are not entries are kept as pseudo-entries of their section. }
unit TvIni;

{$mode objfpc}
{$modeswitch nestedprocvars}
{$H+}
{$R-}
{$Q-}

interface

type
  TIniEntry = class
  private
    FTag: AnsiString;
    FValue: AnsiString;
    FComment: AnsiString;
    FOriginal: AnsiString;
    FHasOriginal: Boolean;
    FIsEntry: Boolean;
    FRaw: Boolean;
    procedure Parse(const ALine: AnsiString; ARaw: Boolean);
  public
    constructor Create(const ALine: AnsiString); overload;
    constructor Create(const ALine: AnsiString; ARaw: Boolean); overload;
    constructor Create(const ATag, AValue, AComment: AnsiString; ARaw: Boolean = False); overload;
    function GetText: AnsiString;
    function GetTag: AnsiString;
    function GetValue: AnsiString;
    function GetComment: AnsiString;
    procedure SetValue(const S: AnsiString);
    procedure SetComment(const S: AnsiString);
    function IsEntry: Boolean;       { False for an empty line or a comment line }
  end;

  TIniSection = class;

  PIniEntry = TIniEntry;
  PIniSection = TIniSection;

  TIniEntryEnumProc = procedure(P: PIniEntry) is nested;
  TIniSectionEnumProc = procedure(P: PIniSection) is nested;

  TIniSection = class
  private
    FName: AnsiString;
    FRaw: Boolean;
    FEntries: array of TIniEntry;
    FCount: Integer;
    procedure Append(AEntry: TIniEntry);
    function IndexOf(const Tag: AnsiString): Integer;
  public
    constructor Create(const AName: AnsiString; ARaw: Boolean = False);
    destructor Destroy; override;
    function GetName: AnsiString;
    function AddEntry(const S: AnsiString): PIniEntry; overload;
    function AddEntry(const Tag, Value, Comment: AnsiString): PIniEntry; overload;
    function SearchEntry(const Tag: AnsiString): PIniEntry;
    procedure DeleteEntry(const Tag: AnsiString);
    procedure ForEachEntry(EnumProc: TIniEntryEnumProc);
    function Count: Integer;
    function Entry(I: Integer): PIniEntry;
  end;

  TIniFile = class
  private
    FFileName: AnsiString;
    FSections: array of TIniSection;
    FSectionCount: Integer;
    FModified: Boolean;
    FHasBom: Boolean;
    FCrLf: Boolean;
    function AddSection(const AName: AnsiString): TIniSection;
    function IndexOf(const Section: AnsiString): Integer;
    procedure ClearSections;
    procedure Parse(const Text: AnsiString);
  public
    MakeNullEntries: Boolean;
    InlineComments: Boolean;
    constructor Create(const AFileName: AnsiString);
    destructor Destroy; override;
    function GetFileName: AnsiString;
    function Read: Boolean;
    function Update: Boolean;
    function IsModified: Boolean;
    procedure LoadFromText(const Text: AnsiString);
    function SaveToText: AnsiString;
    function SearchSection(const Section: AnsiString): PIniSection;
    function SearchEntry(const Section, Tag: AnsiString): PIniEntry;
    procedure ForEachSection(EnumProc: TIniSectionEnumProc);
    procedure ForEachEntry(const Section: AnsiString; EnumProc: TIniEntryEnumProc);
    function GetEntry(const Section, Tag, Default: AnsiString): AnsiString;
    procedure SetEntry(const Section, Tag, Value: AnsiString); overload;
    procedure SetEntry(const Section, Tag, Value, Comment: AnsiString); overload;
    function GetIntEntry(const Section, Tag: AnsiString; Default: LongInt): LongInt;
    procedure SetIntEntry(const Section, Tag: AnsiString; Value: LongInt);
    function GetBoolEntry(const Section, Tag: AnsiString; Default: Boolean): Boolean;
    procedure SetBoolEntry(const Section, Tag: AnsiString; Value: Boolean);
    function EntryExists(const Section, Tag: AnsiString): Boolean;
    procedure DeleteSection(const Section: AnsiString);
    procedure DeleteEntry(const Section, Tag: AnsiString);
    function SectionCount: Integer;
    function SectionAt(I: Integer): PIniSection;
  end;
  PIniFile = TIniFile;

const
  MainSectionName = 'MainSection';
  CommentChar = ';';

{ The text to put after "=" for the value S: S itself, or S in quotes when it would not read back unchanged. }
function IniQuote(const S: AnsiString): AnsiString;

implementation

end.
