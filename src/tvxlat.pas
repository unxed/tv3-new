{ Makes keyboard shortcuts independent of the keyboard layout: a map from the characters of non-Latin
  layouts to the Latin keys at the same physical places, and two routines that change a key event
  with it (Alt or Ctrl plus a letter of another script, and a plain letter looked up among hot keys).
  The map is global and filled on first use; use the unit from the input thread only. }
unit TvXlat;

{$mode objfpc}
{$H+}

interface

uses
  TvEvents;

{ Returns the Latin key character for the key where some layout has CodePoint, or 0.
  Code points below 128 give 0. Does not look at XlatEnabled. }
function XlatLatin(CodePoint: LongWord): LongWord;

{ Adds a layout. Letters lists the characters on the Latin keys in the order of the keys; a bar
  separates the lower-case half from the upper-case half. Added pairs replace older ones. }
procedure XlatAdd(const Letters: AnsiString);

{ Reads layouts from a text file with lines "layout = keys". Returns False when the file cannot
  be opened. }
function XlatLoadFile(const Name: AnsiString): Boolean;

{ Turns Alt or Ctrl plus a letter of another script into the shortcut of the Latin letter. }
function XlatModded(var Event: TEvent): Boolean;

{ Turns a plain letter of another script into its Latin character. }
function XlatPlain(var Event: TEvent): Boolean;

var
  XlatEnabled: Boolean = True;

implementation

end.
