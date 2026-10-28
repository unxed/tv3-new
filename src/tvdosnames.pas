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

end.
