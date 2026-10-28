{ Tests of TvGlyphs. }
program t_glyphs;

{$mode objfpc}
{$H+}
{$modeswitch advancedrecords}

uses
  SysUtils, TvColors, TvCell, TvUtf8, TvCodePages, TvGlyphs;

{$I testlib.inc}

type
  TGlyphRow = record
    Cp: LongWord;
    Name: string;
    Expected: Byte;
  end;

const
  RowCount = 62;
  Rows: array[0..RowCount - 1] of TGlyphRow = (
    (Cp: $2591; Name: 'glShadeLight'; Expected: $B0),
    (Cp: $2592; Name: 'glShadeMedium'; Expected: $B1),
    (Cp: $2593; Name: 'glShadeDark'; Expected: $B2),
    (Cp: $2502; Name: 'glLightV'; Expected: $B3),
    (Cp: $2524; Name: 'glLightVL'; Expected: $B4),
    (Cp: $2561; Name: 'glVertSglLeftDbl'; Expected: $B5),
    (Cp: $2562; Name: 'glVertDblLeftSgl'; Expected: $B6),
    (Cp: $2556; Name: 'glDownDblLeftSgl'; Expected: $B7),
    (Cp: $2555; Name: 'glDownSglLeftDbl'; Expected: $B8),
    (Cp: $2563; Name: 'glDblVL'; Expected: $B9),
    (Cp: $2551; Name: 'glDblV'; Expected: $BA),
    (Cp: $2557; Name: 'glDblDL'; Expected: $BB),
    (Cp: $255D; Name: 'glDblUL'; Expected: $BC),
    (Cp: $255C; Name: 'glUpDblLeftSgl'; Expected: $BD),
    (Cp: $255B; Name: 'glUpSglLeftDbl'; Expected: $BE),
    (Cp: $2510; Name: 'glLightDL'; Expected: $BF),
    (Cp: $2514; Name: 'glLightUR'; Expected: $C0),
    (Cp: $2534; Name: 'glLightUH'; Expected: $C1),
    (Cp: $252C; Name: 'glLightDH'; Expected: $C2),
    (Cp: $251C; Name: 'glLightVR'; Expected: $C3),
    (Cp: $2500; Name: 'glLightH'; Expected: $C4),
    (Cp: $253C; Name: 'glLightVH'; Expected: $C5),
    (Cp: $255E; Name: 'glVertSglRightDbl'; Expected: $C6),
    (Cp: $255F; Name: 'glVertDblRightSgl'; Expected: $C7),
    (Cp: $255A; Name: 'glDblUR'; Expected: $C8),
    (Cp: $2554; Name: 'glDblDR'; Expected: $C9),
    (Cp: $2569; Name: 'glDblUH'; Expected: $CA),
    (Cp: $2566; Name: 'glDblDH'; Expected: $CB),
    (Cp: $2560; Name: 'glDblVR'; Expected: $CC),
    (Cp: $2550; Name: 'glDblH'; Expected: $CD),
    (Cp: $256C; Name: 'glDblVH'; Expected: $CE),
    (Cp: $2567; Name: 'glUpSglHorizDbl'; Expected: $CF),
    (Cp: $2568; Name: 'glUpDblHorizSgl'; Expected: $D0),
    (Cp: $2564; Name: 'glDownSglHorizDbl'; Expected: $D1),
    (Cp: $2565; Name: 'glDownDblHorizSgl'; Expected: $D2),
    (Cp: $2559; Name: 'glUpDblRightSgl'; Expected: $D3),
    (Cp: $2558; Name: 'glUpSglRightDbl'; Expected: $D4),
    (Cp: $2552; Name: 'glDownSglRightDbl'; Expected: $D5),
    (Cp: $2553; Name: 'glDownDblRightSgl'; Expected: $D6),
    (Cp: $256B; Name: 'glVertDblHorizSgl'; Expected: $D7),
    (Cp: $256A; Name: 'glVertSglHorizDbl'; Expected: $D8),
    (Cp: $2518; Name: 'glLightUL'; Expected: $D9),
    (Cp: $250C; Name: 'glLightDR'; Expected: $DA),
    (Cp: $2588; Name: 'glBlockFull'; Expected: $DB),
    (Cp: $2584; Name: 'glBlockLower'; Expected: $DC),
    (Cp: $258C; Name: 'glBlockLeft'; Expected: $DD),
    (Cp: $2590; Name: 'glBlockRight'; Expected: $DE),
    (Cp: $2580; Name: 'glBlockUpper'; Expected: $DF),
    (Cp: $25A0; Name: 'glSquare'; Expected: $FE),
    (Cp: $2219; Name: 'glDot'; Expected: $F9),
    (Cp: $221A; Name: 'glRadical'; Expected: $FB),
    (Cp: $00B7; Name: 'glMidDot'; Expected: $FA),
    (Cp: $25B2; Name: 'glTriUp'; Expected: $1E),
    (Cp: $25BC; Name: 'glTriDown'; Expected: $1F),
    (Cp: $25BA; Name: 'glTriRight'; Expected: $10),
    (Cp: $25C4; Name: 'glTriLeft'; Expected: $11),
    (Cp: $2195; Name: 'glUpDown'; Expected: $12),
    (Cp: $2191; Name: 'glArrowUp'; Expected: $18),
    (Cp: $2193; Name: 'glArrowDown'; Expected: $19),
    (Cp: $2192; Name: 'glArrowRight'; Expected: $1A),
    (Cp: $2190; Name: 'glArrowLeft'; Expected: $1B),
    (Cp: $2261; Name: 'glIdentical'; Expected: $F0)
  );

function Bytes(const S: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 1 to Length(S) do
    Result := Result + IntToHex(Ord(S[Index]), 2);
end;

procedure TestTable;
var
  Index, Other: Integer;
  Duplicate: Boolean;
begin
  for Index := 0 to RowCount - 1 do
    Check(GlyphByte(Rows[Index].Cp) = Rows[Index].Expected, 'GlyphByte(' + Rows[Index].Name + ') = table byte');
  Duplicate := False;
  for Index := 0 to RowCount - 1 do
    for Other := Index + 1 to RowCount - 1 do
      if Rows[Index].Cp = Rows[Other].Cp then
        Duplicate := True;
  Check(not Duplicate, 'no two rows of the table share a code point');
end;

procedure TestExamples;
begin
  Check(GlyphByte(glLightH) = $C4, 'example glLightH');
  Check(GlyphByte(glLightV) = $B3, 'example glLightV');
  Check(GlyphByte(glDblH) = $CD, 'example glDblH');
  Check(GlyphByte(glDblDR) = $C9, 'example glDblDR');
  Check(GlyphByte(glDblUL) = $BC, 'example glDblUL');
  Check(GlyphByte(glVertDblRightSgl) = $C7, 'example glVertDblRightSgl');
  Check(GlyphByte(glDownSglRightDbl) = $D5, 'example glDownSglRightDbl');
  Check(GlyphByte(glUpDblHorizSgl) = $D0, 'example glUpDblHorizSgl');
  Check(GlyphByte(glVertSglHorizDbl) = $D8, 'example glVertSglHorizDbl');
  Check(GlyphByte(glShadeMedium) = $B1, 'example glShadeMedium');
  Check(GlyphByte(glBlockFull) = $DB, 'example glBlockFull');
  Check(GlyphByte(glSquare) = $FE, 'example glSquare');
  Check(GlyphByte(glDot) = $F9, 'example glDot');
  Check(GlyphByte(glMidDot) = $FA, 'example glMidDot');
  Check(GlyphByte(glRadical) = $FB, 'example glRadical');
  Check(GlyphByte(glTriUp) = $1E, 'example glTriUp');
  Check(GlyphByte(glTriDown) = $1F, 'example glTriDown');
  Check(GlyphByte(glTriRight) = $10, 'example glTriRight');
  Check(GlyphByte(glTriLeft) = $11, 'example glTriLeft');
end;

procedure TestChars;
begin
  Check(GlyphChar(glShadeLight) = gcShadeLight, 'GlyphChar(glShadeLight) = gcShadeLight');
  Check(GlyphChar(glShadeMedium) = gcShadeMedium, 'GlyphChar(glShadeMedium) = gcShadeMedium');
  Check(GlyphChar(glShadeDark) = gcShadeDark, 'GlyphChar(glShadeDark) = gcShadeDark');
  Check(GlyphChar(glBlockFull) = gcBlockFull, 'GlyphChar(glBlockFull) = gcBlockFull');
  Check(GlyphChar(glBlockLower) = gcBlockLower, 'GlyphChar(glBlockLower) = gcBlockLower');
  Check(GlyphChar(glBlockUpper) = gcBlockUpper, 'GlyphChar(glBlockUpper) = gcBlockUpper');
  Check(GlyphChar(glBlockLeft) = gcBlockLeft, 'GlyphChar(glBlockLeft) = gcBlockLeft');
  Check(GlyphChar(glBlockRight) = gcBlockRight, 'GlyphChar(glBlockRight) = gcBlockRight');
  Check(GlyphChar(glDot) = gcDot, 'GlyphChar(glDot) = gcDot');
  Check(GlyphChar(glMidDot) = gcMidDot, 'GlyphChar(glMidDot) = gcMidDot');
  Check(GlyphChar(glRadical) = gcRadical, 'GlyphChar(glRadical) = gcRadical');
  Check(GlyphChar(glSquare) = gcSquare, 'GlyphChar(glSquare) = gcSquare');
  Check(GlyphChar(glIdentical) = gcIdentical, 'GlyphChar(glIdentical) = gcIdentical');
  Check(GlyphChar(glLightH) = gcLightH, 'GlyphChar(glLightH) = gcLightH');
  Check(GlyphChar(glLightV) = gcLightV, 'GlyphChar(glLightV) = gcLightV');
  Check(GlyphChar(glLightDR) = gcLightDR, 'GlyphChar(glLightDR) = gcLightDR');
  Check(GlyphChar(glLightDL) = gcLightDL, 'GlyphChar(glLightDL) = gcLightDL');
  Check(GlyphChar(glLightUR) = gcLightUR, 'GlyphChar(glLightUR) = gcLightUR');
  Check(GlyphChar(glLightUL) = gcLightUL, 'GlyphChar(glLightUL) = gcLightUL');
  Check(GlyphChar(glLightVR) = gcLightVR, 'GlyphChar(glLightVR) = gcLightVR');
  Check(GlyphChar(glLightVL) = gcLightVL, 'GlyphChar(glLightVL) = gcLightVL');
  Check(GlyphChar(glLightDH) = gcLightDH, 'GlyphChar(glLightDH) = gcLightDH');
  Check(GlyphChar(glLightUH) = gcLightUH, 'GlyphChar(glLightUH) = gcLightUH');
  Check(GlyphChar(glLightVH) = gcLightVH, 'GlyphChar(glLightVH) = gcLightVH');
  Check(GlyphChar(glTriUp) = gcTriUp, 'GlyphChar(glTriUp) = gcTriUp');
  Check(GlyphChar(glTriDown) = gcTriDown, 'GlyphChar(glTriDown) = gcTriDown');
  Check(GlyphChar(glTriRight) = gcTriRight, 'GlyphChar(glTriRight) = gcTriRight');
  Check(GlyphChar(glTriLeft) = gcTriLeft, 'GlyphChar(glTriLeft) = gcTriLeft');
  Check(GlyphChar(glLightH) = #$C4, 'GlyphChar(glLightH) is #$C4');
  Check(GlyphChar(glLightH) <> gcShadeLight, 'GlyphChar(glLightH) is not gcShadeLight');
  Check(GlyphChar(Ord('a')) = #0, 'GlyphChar of a non-glyph is #0');
end;

procedure TestNonGlyphs;
begin
  Check(GlyphByte(Ord('a')) = 0, 'GlyphByte of ASCII a is 0');
  Check(GlyphByte($2603) = 0, 'GlyphByte of U+2603 is 0');
end;

procedure TestStrings;
var
  SavedMode: Boolean;
  Big: ShortString;
begin
  SavedMode := Utf8Enabled;

  Utf8Enabled := True;
  Check(GlyphStr(glLightH) = #$E2#$94#$80, 'GlyphStr UTF-8 on gives three bytes');
  Check(GlyphStr(glMidDot) = #$C2#$B7, 'GlyphStr UTF-8 on gives two bytes for U+00B7');
  Check(GlyphRun(glLightH, 3) = #$E2#$94#$80#$E2#$94#$80#$E2#$94#$80, 'GlyphRun UTF-8 on, three copies');
  Check(GlyphRun(glLightH, 0) = '', 'GlyphRun UTF-8 on, Count 0');
  Check(GlyphRun(glLightH, -5) = '', 'GlyphRun UTF-8 on, negative Count');
  Big := GlyphRun(glLightH, 1000);
  Check(Length(Big) <= 255, 'GlyphRun UTF-8 on, large Count stays within 255 bytes');
  Check(Length(Big) = 255, 'GlyphRun UTF-8 on, 85 copies of a three-byte glyph');
  Check(Length(Big) mod 3 = 0, 'GlyphRun UTF-8 on, length is a multiple of the glyph length');
  Big := GlyphRun(glMidDot, 1000);
  Check((Length(Big) <= 255) and (Length(Big) mod 2 = 0), 'GlyphRun UTF-8 on, whole two-byte copies');

  Utf8Enabled := False;
  Check(GlyphStr(glLightH) = #$C4, 'GlyphStr UTF-8 off gives the PC byte');
  Check(GlyphStr(Ord('a')) = #0, 'GlyphStr UTF-8 off gives #0 for ASCII');
  Check(GlyphRun(glLightH, 3) = #$C4#$C4#$C4, 'GlyphRun UTF-8 off, three copies');
  Check(GlyphRun(glLightH, 0) = '', 'GlyphRun UTF-8 off, Count 0');
  Big := GlyphRun(glLightH, 1000);
  Check(Length(Big) = 255, 'GlyphRun UTF-8 off, large Count gives 255 bytes');

  Utf8Enabled := SavedMode;
  Check(Utf8Enabled = SavedMode, 'the UTF-8 mode flag is restored');
end;

procedure TestCells;
var
  Cells: array[0..3] of TScreenCell;
  Before: TColorAttr;
begin
  FillChar(Cells, SizeOf(Cells), 0);
  SetCellGlyph(Cells[0], glDblH);
  SetCellGlyph(Cells[1], glDblH);
  SetCellGlyph(Cells[2], glDblH);
  Check(Bytes(Cells[0].Character.GetText) = 'E29590', 'SetCellGlyph cell 0 holds E2 95 90');
  Check(Bytes(Cells[1].Character.GetText) = 'E29590', 'SetCellGlyph cell 1 holds E2 95 90');
  Check(Bytes(Cells[2].Character.GetText) = 'E29590', 'SetCellGlyph cell 2 holds E2 95 90');
  Check(not Cells[0].Character.IsWide, 'SetCellGlyph makes an ordinary character');
  Check(Cells[3].Character.GetText = #0, 'the fourth cell is untouched');

  SetCellGlyph(Cells[1], glLightH);
  Check(Bytes(Cells[1].Character.GetText) = 'E29480', 'overwriting a cell leaves exactly the new three bytes');
  Check(Bytes(Cells[0].Character.GetText) = 'E29590', 'the neighbour of an overwritten cell is untouched');

  Cells[3] := TScreenCell.Create($1E41);
  Before := Cells[3].Attribute;
  SetCellGlyph(Cells[3], glLightV);
  Check(CompareByte(Before, Cells[3].Attribute, SizeOf(TColorAttr)) = 0, 'SetCellGlyph keeps the attribute');
  Check(Bytes(Cells[3].Character.GetText) = 'E29482', 'SetCellGlyph replaces the text of a cell with text');

  SetCellGlyph(Cells[2], glMidDot);
  Check(Bytes(Cells[2].Character.GetText) = 'C2B7', 'SetCellGlyph with glMidDot gives C2 B7');
end;

begin
  Check(CpSelect(437), 'CpSelect(437) selects a DOS page');
  TestTable;
  TestExamples;
  TestChars;
  TestNonGlyphs;
  TestStrings;
  TestCells;
  Done;
end.
