{ Conversion between UTF-8 and single-byte character sets (DOS and Windows code pages, KOI8, ISO 8859,
  Mac Roman) and UTF-16, names and ids of the sets, UTF-8 validation and a guess of the set of a raw text. }
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
function IsPlainAscii(const S: AnsiString): Boolean;
function CharsetGuess(const Raw: AnsiString; const Candidates: array of LongInt): LongInt;

implementation

end.
