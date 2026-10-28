{ File-name conversion at the border between a program and a DOS that offers a UTF-8 file-name API. Names are
  translated between UTF-8 and the bytes of the current code page; a character that the page lacks travels as the
  text U+XXXX in braces. The unit makes no DOS calls; another unit sets the flags. }
unit TvDosNames;

{$mode objfpc}
{$H+}

interface

var
  { True when the DOS takes and gives names in UTF-8; DosNameToUtf8 and DosNameFromUtf8 do nothing while it is False. }
  NamesUtf8: Boolean = False;

{ A name of the program (bytes of the page) as the DOS wants it. }
function DosNameToUtf8(const S: string): string;
{ A name from the DOS as the program wants it (bytes of the page). }
function DosNameFromUtf8(const S: string): string;

var
  { The names are mapped by NameToDos and NameFromDos. }
  NamesMapped: Boolean = False;
  { The provider is there (also when the program did not switch the mode on): U+XXXX in braces is the form of a
    character that the page lacks. }
  NamesProvider: Boolean = False;

{ A name of the program as the DOS wants it, and a name of the DOS as the program wants it. }
function NameToDos(const S: string): string;
function NameFromDos(const S: string): string;

implementation

uses
  SysUtils, TvCodePages, TvUtf8;

const
  BraceEscape = '{U+007B}';
  EscapeOpening = '{U+';
  MaxCodePoint = $10FFFF;

{ Returns the UTF-8 bytes of CodePoint. }
function EncodeUtf8(CodePoint: LongWord): string;
var
  Bytes: TUtf8Bytes;
  Count, Index: SizeInt;
begin
  Count := Utf32To8(CodePoint, Bytes);
  SetLength(Result, Count);
  for Index := 0 to Count - 1 do
    Result[Index + 1] := Char(Bytes[Index]);
end;

{ Returns the escape text (brace, U+, hex digits, brace) of CodePoint, upper-case hexadecimal, at least four digits. }
function EscapeText(CodePoint: LongWord): string;
begin
  Result := '{U+' + IntToHex(CodePoint, 4) + '}';
end;

{ Returns the value of the hexadecimal digit Ch, or -1 when Ch is not one. }
function HexDigitValue(Ch: Char): Integer;
begin
  case Ch of
    '0'..'9': Result := Ord(Ch) - Ord('0');
    'A'..'F': Result := Ord(Ch) - Ord('A') + 10;
    'a'..'f': Result := Ord(Ch) - Ord('a') + 10;
  else
    Result := -1;
  end;
end;

{ Tests whether an escape starts at Position (one-based). On success CodePoint is its value and Used its length. }
function ReadEscape(const S: string; Position: SizeInt; out CodePoint: LongWord; out Used: SizeInt): Boolean;
var
  Cursor, DigitCount, Digit: SizeInt;
  Value: QWord;
begin
  Result := False;
  CodePoint := 0;
  Used := 0;
  if Position + 2 > Length(S) then
    Exit;
  if (S[Position] <> '{') or (S[Position + 1] <> 'U') or (S[Position + 2] <> '+') then
    Exit;
  Cursor := Position + 3;
  Value := 0;
  DigitCount := 0;
  while (Cursor <= Length(S)) and (DigitCount < 7) do
  begin
    Digit := HexDigitValue(S[Cursor]);
    if Digit < 0 then
      Break;
    Value := Value * 16 + QWord(Digit);
    Inc(DigitCount);
    Inc(Cursor);
  end;
  if (DigitCount < 4) or (DigitCount > 6) then
    Exit;
  if (Cursor > Length(S)) or (S[Cursor] <> '}') then
    Exit;
  if Value > MaxCodePoint then
    Exit;
  CodePoint := LongWord(Value);
  Used := Cursor - Position + 1;
  Result := True;
end;

{ Decodes the UTF-8 sequence that starts at Position (one-based). Overlong forms, surrogates, values above
  $10FFFF and truncated sequences are invalid. }
function ReadUtf8(const S: string; Position: SizeInt; out CodePoint: LongWord; out Used: SizeInt): Boolean;
var
  Lead: Byte;
  Extra, Index: SizeInt;
  Continuation: Byte;
  Minimum: LongWord;
begin
  Result := False;
  CodePoint := 0;
  Used := 1;
  Lead := Byte(S[Position]);
  if Lead < $C2 then
    Exit;
  if Lead < $E0 then
  begin
    Extra := 1;
    CodePoint := Lead and $1F;
    Minimum := $80;
  end
  else if Lead < $F0 then
  begin
    Extra := 2;
    CodePoint := Lead and $0F;
    Minimum := $800;
  end
  else if Lead < $F5 then
  begin
    Extra := 3;
    CodePoint := Lead and $07;
    Minimum := $10000;
  end
  else
    Exit;
  if Position + Extra > Length(S) then
    Exit;
  for Index := 1 to Extra do
  begin
    Continuation := Byte(S[Position + Index]);
    if (Continuation and $C0) <> $80 then
      Exit;
    CodePoint := (CodePoint shl 6) or (Continuation and $3F);
  end;
  if (CodePoint < Minimum) or (CodePoint > MaxCodePoint) then
    Exit;
  if (CodePoint >= $D800) and (CodePoint <= $DFFF) then
    Exit;
  Used := Extra + 1;
  Result := True;
end;

{ True when the text brace-U-plus starts at Position (one-based). }
function StartsEscapeOpening(const S: string; Position: SizeInt): Boolean;
begin
  Result := (Position + 2 <= Length(S)) and (S[Position] = '{') and (S[Position + 1] = 'U')
    and (S[Position + 2] = '+');
end;

function DosNameToUtf8(const S: string): string;
var
  Position, Used: SizeInt;
  CodePoint: LongWord;
  Current: Byte;
begin
  if not NamesUtf8 then
  begin
    Result := S;
    Exit;
  end;
  Result := '';
  Position := 1;
  while Position <= Length(S) do
  begin
    if ReadEscape(S, Position, CodePoint, Used) then
    begin
      Result := Result + EncodeUtf8(CodePoint);
      Inc(Position, Used);
      Continue;
    end;
    Current := Byte(S[Position]);
    if Current < $80 then
      Result := Result + Char(Current)
    else
      Result := Result + EncodeUtf8(CpToUnicode(Current));
    Inc(Position);
  end;
end;

function DosNameFromUtf8(const S: string): string;
var
  Position, Used: SizeInt;
  CodePoint: LongWord;
  PageByte: Byte;
begin
  if not NamesUtf8 then
  begin
    Result := S;
    Exit;
  end;
  Result := '';
  Position := 1;
  while Position <= Length(S) do
  begin
    if Byte(S[Position]) < $80 then
    begin
      if StartsEscapeOpening(S, Position) then
        Result := Result + BraceEscape
      else
        Result := Result + S[Position];
      Inc(Position);
      Continue;
    end;
    if not ReadUtf8(S, Position, CodePoint, Used) then
    begin
      Result := Result + S[Position];
      Inc(Position);
      Continue;
    end;
    PageByte := CpFromUnicode(CodePoint);
    if PageByte <> 0 then
      Result := Result + Char(PageByte)
    else
      Result := Result + EscapeText(CodePoint);
    Inc(Position, Used);
  end;
end;

{ UTF-8 program, DOS with a code page. }
function Utf8ToPage(const S: string): string;
var
  Position, Used: SizeInt;
  CodePoint: LongWord;
  PageByte: Byte;
begin
  Result := '';
  Position := 1;
  while Position <= Length(S) do
  begin
    if Byte(S[Position]) < $80 then
    begin
      if NamesProvider and StartsEscapeOpening(S, Position) then
        Result := Result + BraceEscape
      else
        Result := Result + S[Position];
      Inc(Position);
      Continue;
    end;
    if not ReadUtf8(S, Position, CodePoint, Used) then
    begin
      Result := Result + S[Position];
      Inc(Position);
      Continue;
    end;
    PageByte := CpFromUnicode(CodePoint);
    if PageByte <> 0 then
      Result := Result + Char(PageByte)
    else if NamesProvider then
      Result := Result + EscapeText(CodePoint)
    else
      Result := Result + '_';
    Inc(Position, Used);
  end;
end;

{ UTF-8 program, DOS with a code page. }
function PageToUtf8(const S: string): string;
var
  Position, Used: SizeInt;
  CodePoint: LongWord;
  Current: Byte;
begin
  Result := '';
  Position := 1;
  while Position <= Length(S) do
  begin
    if NamesProvider and ReadEscape(S, Position, CodePoint, Used) then
    begin
      Result := Result + EncodeUtf8(CodePoint);
      Inc(Position, Used);
      Continue;
    end;
    Current := Byte(S[Position]);
    if Current < $80 then
      Result := Result + Char(Current)
    else
      Result := Result + EncodeUtf8(CpToUnicode(Current));
    Inc(Position);
  end;
end;

function NameToDos(const S: string): string;
begin
  Result := S;
  if not NamesMapped then
    Exit;
  if not Utf8Enabled then
    Result := DosNameToUtf8(S)
  else if not NamesUtf8 then
    Result := Utf8ToPage(S);
end;

function NameFromDos(const S: string): string;
begin
  Result := S;
  if not NamesMapped then
    Exit;
  if not Utf8Enabled then
    Result := DosNameFromUtf8(S)
  else if not NamesUtf8 then
    Result := PageToUtf8(S);
end;

end.
