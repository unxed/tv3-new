{ Single-byte OEM code pages: the one current page, the byte -> Unicode map, its reverse, the UTF-8 form of a
  byte and plain ASCII substitutes for characters that a page lacks. }
unit TvCodePages;

{$mode objfpc}
{$H+}
{$POINTERMATH ON}

interface

const
  cpIdCp437 = 437;
  cpIdCp866 = 866;
  cpIdCp1125 = 1125;

{ Makes the page with the given number current. Returns False and changes nothing when the number is unknown. }
function CpSelect(Id: Integer): Boolean;

{ Returns the number of the current page. }
function CpCurrent: Integer;

{ Returns the Unicode value that the current page shows for B; $FFFD for an undefined byte. }
function CpToUnicode(B: Byte): LongWord;

{ Returns the lowest byte of the current page that shows CodePoint, 0 when there is none. }
function CpFromUnicode(CodePoint: LongWord): Byte;

{ Writes the UTF-8 form of CpToUnicode(B) to Buf (room for 4 bytes, no terminator) and returns its length. }
function CpToUtf8(B: Byte; Buf: PByte): Integer;

{ Returns the ASCII byte that stands for CodePoint on a page that lacks it, 0 when there is none. }
function CpFallback(CodePoint: LongWord): Byte;

implementation

end.
