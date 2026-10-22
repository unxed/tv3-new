{ Operations on strings that may hold UTF-8 text, by character, by screen cell and by case, keeping stray bytes. }
unit TvUStr;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvUtf8;

{ --- bytes and columns --- }

{ The byte length of the character that starts at byte index Idx; 0 when Idx is outside the string. }
function U8CharBytes(const S: AnsiString; Idx: Integer): Integer;

{ True when every byte of S is below $80. }
function U8IsAscii(const S: AnsiString): Boolean;

{ The number of characters (columns) of S. }
function U8Len(const S: AnsiString): Integer;

{ The byte index at which the 0-based column Col starts. }
function U8Idx(const S: AnsiString; Col: Integer): Integer;

{ The column of the byte at index Idx. }
function U8Col(const S: AnsiString; Idx: Integer): Integer;

{ The byte index of the start of the character before Idx. }
function U8PrevIdx(const S: AnsiString; Idx: Integer): Integer;

{ --- cutting (columns are 0-based) --- }

{ The Cnt characters from column Col. }
function U8Copy(const S: AnsiString; Col, Cnt: Integer): AnsiString;

{ The character at column Col, or '' outside the string. }
function U8Char(const S: AnsiString; Col: Integer): AnsiString;

{ Removes the Cnt characters from column Col. }
procedure U8Delete(var S: AnsiString; Col, Cnt: Integer); overload;
procedure U8Delete(var S: ShortString; Col, Cnt: Integer); overload;

{ Inserts Sub before column Col. }
procedure U8Insert(const Sub: AnsiString; var S: AnsiString; Col: Integer); overload;
procedure U8Insert(const Sub: AnsiString; var S: ShortString; Col: Integer); overload;

{ The first byte of the character at column Col, or a space outside the string. }
function U8ColChar(const S: AnsiString; Col: Integer): Char;

{ The code point of the character at column Col; the byte value for a stray byte; 0 outside the string. }
function U8CodePoint(const S: AnsiString; Col: Integer): LongWord;

{ The UTF-8 bytes of the code point CP. }
function U8Encode(CP: LongWord): AnsiString;

{ The longest beginning of S of at most MaxBytes bytes that does not end inside a character. }
function U8Prefix(const S: AnsiString; MaxBytes: Integer): AnsiString;

{ Removes the last character. }
procedure U8DeleteLast(var S: AnsiString); overload;
procedure U8DeleteLast(var S: ShortString); overload;

{ --- screen cells --- }

{ The number of screen cells of Cnt columns from column Col. }
function U8Cells(const S: AnsiString; Col, Cnt: Integer): Integer;

{ The number of screen cells of S. }
function U8Cols(const S: AnsiString): Integer;

{ The column drawn at the 0-based screen cell Cell. }
function U8ColAtCell(const S: AnsiString; Cell: Integer): Integer;

{ S followed by the spaces that fill it up to Cells cells. }
function U8Pad(const S: AnsiString; Cells: Integer): AnsiString;

{ The longest beginning of S that takes at most Cells cells. }
function U8Fit(const S: AnsiString; Cells: Integer): AnsiString;

{ --- case --- }

{ The upper-case and the lower-case form of a code point. }
function CpUpper(CP: LongWord): LongWord;
function CpLower(CP: LongWord): LongWord;

{ The string with every character in upper case, in lower case, and with its first character in upper case. }
function U8Upper(const S: AnsiString): AnsiString;
function U8Lower(const S: AnsiString): AnsiString;
function U8CapFirst(const S: AnsiString): AnsiString;

{ True when A and B are the same bytes or have the same lower-case form. }
function U8EqualNoCase(const A, B: AnsiString): Boolean;

implementation

function U8CharBytes(const S: AnsiString; Idx: Integer): Integer;
begin
  Result := 0;
end;

function U8IsAscii(const S: AnsiString): Boolean;
begin
  Result := False;
end;

function U8Len(const S: AnsiString): Integer;
begin
  Result := 0;
end;

function U8Idx(const S: AnsiString; Col: Integer): Integer;
begin
  Result := 1;
end;

function U8Col(const S: AnsiString; Idx: Integer): Integer;
begin
  Result := 0;
end;

function U8PrevIdx(const S: AnsiString; Idx: Integer): Integer;
begin
  Result := 1;
end;

function U8Copy(const S: AnsiString; Col, Cnt: Integer): AnsiString;
begin
  Result := '';
end;

function U8Char(const S: AnsiString; Col: Integer): AnsiString;
begin
  Result := '';
end;

procedure U8Delete(var S: AnsiString; Col, Cnt: Integer);
begin
end;

procedure U8Delete(var S: ShortString; Col, Cnt: Integer);
begin
end;

procedure U8Insert(const Sub: AnsiString; var S: AnsiString; Col: Integer);
begin
end;

procedure U8Insert(const Sub: AnsiString; var S: ShortString; Col: Integer);
begin
end;

function U8ColChar(const S: AnsiString; Col: Integer): Char;
begin
  Result := ' ';
end;

function U8CodePoint(const S: AnsiString; Col: Integer): LongWord;
begin
  Result := 0;
end;

function U8Encode(CP: LongWord): AnsiString;
begin
  Result := '';
end;

function U8Prefix(const S: AnsiString; MaxBytes: Integer): AnsiString;
begin
  Result := '';
end;

procedure U8DeleteLast(var S: AnsiString);
begin
end;

procedure U8DeleteLast(var S: ShortString);
begin
end;

function U8Cells(const S: AnsiString; Col, Cnt: Integer): Integer;
begin
  Result := 0;
end;

function U8Cols(const S: AnsiString): Integer;
begin
  Result := 0;
end;

function U8ColAtCell(const S: AnsiString; Cell: Integer): Integer;
begin
  Result := 0;
end;

function U8Pad(const S: AnsiString; Cells: Integer): AnsiString;
begin
  Result := '';
end;

function U8Fit(const S: AnsiString; Cells: Integer): AnsiString;
begin
  Result := '';
end;

function CpUpper(CP: LongWord): LongWord;
begin
  Result := CP;
end;

function CpLower(CP: LongWord): LongWord;
begin
  Result := CP;
end;

function U8Upper(const S: AnsiString): AnsiString;
begin
  Result := '';
end;

function U8Lower(const S: AnsiString): AnsiString;
begin
  Result := '';
end;

function U8CapFirst(const S: AnsiString): AnsiString;
begin
  Result := '';
end;

function U8EqualNoCase(const A, B: AnsiString): Boolean;
begin
  Result := False;
end;

end.
