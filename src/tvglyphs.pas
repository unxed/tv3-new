{ TvGlyphs gives names to the frame, shade, block, triangle and arrow characters that text-mode screens draw with.
  A glyph is identified by its Unicode code point. The unit converts a glyph to a byte of the IBM PC character set,
  to a string (UTF-8 or a code page byte, by the UTF-8 mode), to a run of repeated glyphs and to a screen cell, and it
  exports Char constants (gc*) with the PC-set byte of the most used glyphs for places where a function call is not
  allowed. TDrawBuffer.MoveGlyph and TDrawBuffer.PutGlyph of TvDrawBuf draw glyphs into a draw buffer by the cell rule
  of SetCellGlyph. }
unit TvGlyphs;

{$mode objfpc}
{$H+}

interface

uses
  TvCell;

const
  { light lines }
  glLightH         = $2500;
  glLightV         = $2502;
  glLightDR        = $250C;
  glLightDL        = $2510;
  glLightUR        = $2514;
  glLightUL        = $2518;
  glLightVR        = $251C;
  glLightVL        = $2524;
  glLightDH        = $252C;
  glLightUH        = $2534;
  glLightVH        = $253C;
  { double lines }
  glDblH           = $2550;
  glDblV           = $2551;
  glDblDR          = $2554;
  glDblDL          = $2557;
  glDblUR          = $255A;
  glDblUL          = $255D;
  glDblVR          = $2560;
  glDblVL          = $2563;
  glDblDH          = $2566;
  glDblUH          = $2569;
  glDblVH          = $256C;
  { a single and a double line meeting }
  glDownSglRightDbl = $2552;
  glDownDblRightSgl = $2553;
  glDownSglLeftDbl  = $2555;
  glDownDblLeftSgl  = $2556;
  glUpSglRightDbl   = $2558;
  glUpDblRightSgl   = $2559;
  glUpSglLeftDbl    = $255B;
  glUpDblLeftSgl    = $255C;
  glVertSglRightDbl = $255E;
  glVertDblRightSgl = $255F;
  glVertSglLeftDbl  = $2561;
  glVertDblLeftSgl  = $2562;
  glDownSglHorizDbl = $2564;
  glDownDblHorizSgl = $2565;
  glUpSglHorizDbl   = $2567;
  glUpDblHorizSgl   = $2568;
  glVertSglHorizDbl = $256A;
  glVertDblHorizSgl = $256B;
  { blocks and shades }
  glShadeLight     = $2591;
  glShadeMedium    = $2592;
  glShadeDark      = $2593;
  glBlockFull      = $2588;
  glBlockLower     = $2584;
  glBlockUpper     = $2580;
  glBlockLeft      = $258C;
  glBlockRight     = $2590;
  glSquare         = $25A0;
  glDot            = $2219;
  glMidDot         = $00B7;
  glTriUp          = $25B2;
  glTriDown        = $25BC;
  glTriRight       = $25BA;
  glTriLeft        = $25C4;
  glUpDown         = $2195;
  glArrowUp        = $2191;
  glArrowDown      = $2193;
  glArrowRight     = $2192;
  glArrowLeft      = $2190;
  glIdentical      = $2261;
  glRadical        = $221A;

const
  { the same glyphs as Char constants, for a typed constant or a case label, where a function call is not allowed (the bytes of the IBM PC set) }
  gcShadeLight  = #$B0;
  gcShadeMedium = #$B1;
  gcShadeDark   = #$B2;
  gcBlockFull   = #$DB;
  gcBlockLower  = #$DC;
  gcBlockUpper  = #$DF;
  gcBlockLeft   = #$DD;
  gcBlockRight  = #$DE;
  gcDot         = #$F9;
  gcMidDot      = #$FA;
  gcRadical     = #$FB;
  gcSquare      = #$FE;
  gcIdentical   = #$F0;
  gcLightH      = #$C4;
  gcLightV      = #$B3;
  gcLightDR     = #$DA;
  gcLightDL     = #$BF;
  gcLightUR     = #$C0;
  gcLightUL     = #$D9;
  gcLightVR     = #$C3;
  gcLightVL     = #$B4;
  gcLightDH     = #$C2;
  gcLightUH     = #$C1;
  gcLightVH     = #$C5;
  gcTriUp       = #$1E;
  gcTriDown     = #$1F;
  gcTriRight    = #$10;
  gcTriLeft     = #$11;

{ Returns the byte of the glyph in the current code page when that page has a non-ASCII byte for it, else the byte of
  the IBM PC character set; 0 when CodePoint is not a glyph of the unit. }
function GlyphByte(CodePoint: LongWord): Byte;

{ Returns Chr(GlyphByte(CodePoint)). }
function GlyphChar(CodePoint: LongWord): Char;

{ Returns the UTF-8 form of the glyph when the UTF-8 mode is on, else the one-character string GlyphChar. }
function GlyphStr(CodePoint: LongWord): ShortString;

{ Returns Count copies of GlyphStr(CodePoint), as many whole copies as fit in 255 bytes. }
function GlyphRun(CodePoint: LongWord; Count: Integer): ShortString;

{ Puts the UTF-8 form of the glyph into Cell as an ordinary character; the attribute of Cell is not changed. }
procedure SetCellGlyph(var Cell: TScreenCell; CodePoint: LongWord);

implementation

uses
  TvUtf8, TvCodePages;

const
  MaxUnicode = $10FFFF;
  MaxShortLength = 255;

{ The position of the glyph in the IBM PC character set; 0 for a code point that is not a glyph. }
function TableByte(CodePoint: LongWord): Byte;
begin
  case CodePoint of
    $2591: Result := $B0;
    $2592: Result := $B1;
    $2593: Result := $B2;
    $2502: Result := $B3;
    $2524: Result := $B4;
    $2561: Result := $B5;
    $2562: Result := $B6;
    $2556: Result := $B7;
    $2555: Result := $B8;
    $2563: Result := $B9;
    $2551: Result := $BA;
    $2557: Result := $BB;
    $255D: Result := $BC;
    $255C: Result := $BD;
    $255B: Result := $BE;
    $2510: Result := $BF;
    $2514: Result := $C0;
    $2534: Result := $C1;
    $252C: Result := $C2;
    $251C: Result := $C3;
    $2500: Result := $C4;
    $253C: Result := $C5;
    $255E: Result := $C6;
    $255F: Result := $C7;
    $255A: Result := $C8;
    $2554: Result := $C9;
    $2569: Result := $CA;
    $2566: Result := $CB;
    $2560: Result := $CC;
    $2550: Result := $CD;
    $256C: Result := $CE;
    $2567: Result := $CF;
    $2568: Result := $D0;
    $2564: Result := $D1;
    $2565: Result := $D2;
    $2559: Result := $D3;
    $2558: Result := $D4;
    $2552: Result := $D5;
    $2553: Result := $D6;
    $256B: Result := $D7;
    $256A: Result := $D8;
    $2518: Result := $D9;
    $250C: Result := $DA;
    $2588: Result := $DB;
    $2584: Result := $DC;
    $258C: Result := $DD;
    $2590: Result := $DE;
    $2580: Result := $DF;
    $25A0: Result := $FE;
    $2219: Result := $F9;
    $221A: Result := $FB;
    $00B7: Result := $FA;
    $25B2: Result := $1E;
    $25BC: Result := $1F;
    $25BA: Result := $10;
    $25C4: Result := $11;
    $2195: Result := $12;
    $2191: Result := $18;
    $2193: Result := $19;
    $2192: Result := $1A;
    $2190: Result := $1B;
    $2261: Result := $F0;
  else
    Result := 0;
  end;
end;

function GlyphByte(CodePoint: LongWord): Byte;
var
  PageByte: Byte;
  IsAsciiRange: Boolean;
begin
  PageByte := CpFromUnicode(CodePoint);
  IsAsciiRange := (PageByte >= $20) and (PageByte < $7F);
  if (PageByte <> 0) and (not IsAsciiRange) and (CodePoint > $7F) then
  begin
    Result := PageByte;
    Exit;
  end;
  Result := TableByte(CodePoint);
end;

function GlyphChar(CodePoint: LongWord): Char;
begin
  Result := Chr(GlyphByte(CodePoint));
end;

{ Writes the UTF-8 form of CodePoint into Encoded and returns its length; 0 when the value cannot be encoded. }
function EncodeCodePoint(CodePoint: LongWord; var Encoded: TUtf8Bytes): Integer;
begin
  if CodePoint > MaxUnicode then
  begin
    Result := 0;
    Exit;
  end;
  Result := Utf32To8(CodePoint, Encoded);
end;

function Utf8Text(CodePoint: LongWord): string;
var
  Encoded: TUtf8Bytes;
  EncodedLength: Integer;
  Index: Integer;
begin
  Result := '';
  EncodedLength := EncodeCodePoint(CodePoint, Encoded);
  if EncodedLength <= 0 then
    Exit;
  SetLength(Result, EncodedLength);
  for Index := 0 to EncodedLength - 1 do
    Result[Index + 1] := Chr(Encoded[Index]);
end;

function GlyphStr(CodePoint: LongWord): ShortString;
begin
  if Utf8Enabled then
    Result := ShortString(Utf8Text(CodePoint))
  else
  begin
    SetLength(Result, 1);
    Result[1] := GlyphChar(CodePoint);
  end;
end;

function GlyphRun(CodePoint: LongWord; Count: Integer): ShortString;
var
  Piece: ShortString;
  CopyIndex: Integer;
begin
  Result := '';
  if Count <= 0 then
    Exit;
  Piece := GlyphStr(CodePoint);
  if Length(Piece) = 0 then
    Exit;
  for CopyIndex := 1 to Count do
  begin
    if Length(Result) + Length(Piece) > MaxShortLength then
      Break;
    Result := Result + Piece;
  end;
end;

procedure SetCellGlyph(var Cell: TScreenCell; CodePoint: LongWord);
begin
  Cell.Character.InitWithMultiByteChar(Utf8Text(CodePoint), False);
end;

end.
