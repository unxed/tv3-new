{ TvCharset converts text between UTF-8 and the character sets met in files, the clipboard and the terminal: the
  single-byte sets of DOS and Windows, KOI8, ISO 8859, Mac Roman, and UTF-16 in both byte orders. It names the sets,
  lists them, validates UTF-8 (Utf8DecodeAt is the one decoder of UTF-8 text) and guesses which single-byte set a
  raw text is written in. Every conversion goes through UTF-8. The only state is the reverse table that
  CharsetFromUtf8 keeps for the set it served last, so that routine is not reentrant. }
unit TvCharset;

{$mode objfpc}
{$H+}

interface

const
  csUtf8 = 65001;
  csUtf16LE = 1200;
  csUtf16BE = 1201;
  csCp437 = 437;
  csCp866 = 866;
  csCp1251 = 1251;
  csCp1252 = 1252;
  csKoi8R = 20866;
  csLatin1 = 28591;

function CharsetId(const Name: AnsiString): LongInt;
function CharsetName(Id: LongInt): AnsiString;
function CharsetKnown(Id: LongInt): Boolean;
function CharsetListCount: Integer;
function CharsetListId(I: Integer): LongInt;
function CharsetToUtf8(Id: LongInt; const Raw: AnsiString): AnsiString;
function CharsetFromUtf8(Id: LongInt; const Text: AnsiString; out Lost: Integer): AnsiString;
function Utf8Valid(const S: AnsiString): Boolean;
function Utf8DecodeAt(const S: AnsiString; Pos: SizeInt; out Cp: Cardinal; out Len: Integer): Boolean;
function IsPlainAscii(const S: AnsiString): Boolean;
function CharsetGuess(const Raw: AnsiString; const Candidates: array of LongInt): LongInt;

implementation

end.
