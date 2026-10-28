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

end.
