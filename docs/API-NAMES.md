# How a C++ name becomes a Pascal name

The names of magiblot/tvision and magiblot/tvterm become Pascal names by these rules.

- Classes keep their names.
- Member functions and free functions take a capital first letter.
- Data members take a capital first letter.
- Constants, enumerators and commands keep their names.
- Constructors are `Create`, destructors are `Destroy`.
- Value types are advanced records with class operators.
- Reference parameters that change are `var`; const references are `const`.
- Units are `Tv<Name>`.

## Added

APIs added beside an existing one by rule P5 of `docs/ASYNC.md` are listed here, one per line, as
"added: <name>".

added: TEventQueue.PostEvent
added: TEventQueue.GetPostedEvent
added: TEventQueue.HasPostedEvents
added: TEventQueue.Backend
added: TEventBackend
added: TEventBackend.GetButtonCount
added: TEventBackend.CursorOn
added: TEventBackend.CursorOff
added: TEventFifo
added: TvObject
added: TvObject.DestroyObject
added: Utf8Enabled
added: TTextCells
added: TTransformAttr
added: TPackedUtf8Func
added: CodePageToPackedUtf8
added: TClipboardBackend
added: TStreamBuf
added: TMemBuf
added: TFileBuf

The last eight are added by the rules of the translation, not by rule P5. A Pascal class cannot be extended in another
unit, so the members of the C++ class TText that write into screen cells are class methods of TTextCells in TvText.
TTransformAttr and TPackedUtf8Func are the procedural types that stand for a function template parameter and for the
code page conversion of a control character, and CodePageToPackedUtf8 is the variable that holds the latter.
TClipboardBackend is the class of the hook for the system clipboard, which THardwareInfo provides in the C++.

TStreamBuf stands for the streambuf of the C++ standard library, which the streams of TvStreams use through the
pointer bp; TMemBuf and TFileBuf are its buffers in memory and on a file (the filebuf). The constants iosGoodBit to
iosEnd of TvStreams stand for the state bits, open modes and seek directions of ios. The stream operators >> and <<
are the members Get and Put of the streams, and the operators void * and ! of pstream are OpVoidPtr and OpNot.

Utf8Enabled is a variable of TvUtf8 that has no counterpart in the C++ API; it switches the text routines between
UTF-8 and the one-byte code page.

TvObject is the class TObject of the C++ and TvObject.DestroyObject is its static function destroy: the names TObject
and Destroy belong to System.TObject and its destructor, and a class of the same name in a unit would hide
System.TObject for every unit that uses it. The members that are private virtual in the C++ (FreeItem, Compare)
are protected, so that a class of another unit can override them.

## Added by the translation of the views

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: CaretPositionHook
added: TCaretPositionProc
added: ScreenWriteHook
added: TScreenWriteProc
added: EventTimeoutMs
added: TForEachFunc
added: TFirstThatFunc
added: TPhaseType
added: TSelectMode
added: PColorAttr

TCaretPositionProc and TScreenWriteProc are the procedural types of the hooks that stand for parts of the C++ that
have no unit yet. CaretPositionHook stands for THardwareInfo::setCaretPosition and ScreenWriteHook for
THardwareInfo::screenWrite. EventTimeoutMs is
TProgram::eventTimeoutMs, which the members of TView read and set. TForEachFunc and TFirstThatFunc are the types of
the function pointers that TGroup.ForEach and TGroup.FirstThat take. TPhaseType and TSelectMode are the enumerations
phaseType and selectMode that are nested in TView, and PColorAttr is the pointer to a TColorAttr that a TPalette
holds. The operators & and | of TCommandSet are the operators * and +, and the operators +=, -=, &= and |= are the
methods AddAssign, SubAssign, AndAssign and OrAssign.

## Differences

State protected by rule P4 of `docs/ASYNC.md` is listed here, one per line, as "difference: thread safety of
<name>".

difference: thread safety of TWakeUpEventSource.Signal
difference: thread safety of TEventQueue.PostEvent
difference: thread safety of TEventQueue.WakeUp
difference: thread safety of TEventBackend.Feed
difference: thread safety of TTimerQueue.SetTimer
difference: thread safety of TTimerQueue.KillTimer
difference: thread safety of TTimerQueue.CollectExpiredTimers
difference: thread safety of TTimerQueue.TimeUntilNextTimeout

## Added by the translation of TvMenus

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: HotKeyStrHook
added: THotKeyStrFunc
added: EqualsIgnoreCaseHook
added: TEqualsIgnoreCaseFunc
added: ApplicationHook
added: TApplicationFunc
added: TMenuAction
added: TMenuItem.Ptr
added: TMenuItem.GetParam
added: TMenuItem.SetParam
added: TMenuItem.GetSubMenu
added: TMenuItem.SetSubMenu
added: TMenuView.DoASelect
added: TMenuBox.CNormal
added: TMenuBox.Color
added: MenuViewPalette
added: StatusLinePalette
added: CStrOf
added: HotKeyStrOf
added: SetCommandEvent
added: PostCommand
added: EqualsIgnoreCase

THotKeyStrFunc, TEqualsIgnoreCaseFunc and TApplicationFunc are the procedural types of the hooks that stand for parts
of the C++ that no unit has yet and no input defines. HotKeyStrHook stands for the function hotKeyStr, which gives the
shortcut of the name of a menu item; EqualsIgnoreCaseHook stands for TText::equalsIgnoreCase; ApplicationHook stands
for TProgram::application and gives the root of the application. While HotKeyStrHook or EqualsIgnoreCaseHook is nil,
FindItem finds no item, and while ApplicationHook is nil, PopupMenu answers 0 and does not take the items. HotKeyStrOf
and EqualsIgnoreCase call the hooks, and CStrOf turns a char pointer that may be null into a string. SetCommandEvent turns an event into a command event for a given command, and PostCommand does so, puts the event through a view and clears it.

The tables frameChars of TMenuBox and hintSeparator of TStatusLine are the class variables TMenuBox.FrameChars and
TStatusLine.HintSeparator, which the unit sets to their values when it starts.

A char pointer of the C++ that can be null (name and param of TMenuItem, text of TStatusItem) is a PAnsiChar, and the
members and arguments that are a TStringView are strings. The union of param and subMenu of TMenuItem is the private
pointer Ptr, which the properties Param and SubMenu read and write through GetParam, SetParam, GetSubMenu and
SetSubMenu. A Pascal string has no null value, so the constructors of TMenuItem always allocate the name, and NewLine,
which has a null name in the C++, releases it. The constructor of TMenuView that takes a parent menu has no default
for it, because a default would make a call of the constructors of TMenuBar ambiguous. The function hint of
TStatusLine returns a string.

The operators + of menu.cpp, which chain menu items, sub menus, status items and status definitions, are global
operators with the same operand types. The enumeration menuAction of tmnuview.cpp is TMenuAction and the function
do_a_select is DoASelect. The static variables cNormal and color of tmenubox.cpp, which frameLine and draw share, are
the private fields CNormal and Color of TMenuBox. The static palettes of TMenuView and TStatusLine are the variables
MenuViewPalette and StatusLinePalette, which are created and released with the unit. The functions of the files that
are not members are NewLine, PopupMenu and, inside the unit, GetRect and AutoPlacePopup.

## Added by the translation of TvApp

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TVoidProc
added: TSetCtrlBrkHandlerProc
added: InitHistoryHook
added: DoneHistoryHook
added: SetCtrlBrkHandlerHook
added: TCreateBackgroundFunc
added: TCreateStatusLineFunc
added: TCreateMenuBarFunc
added: TCreateDeskTopFunc
added: TDeskTop.Setup
added: TProgram.Assemble
added: TProgram.ReadScreenMode
added: TProgram.ReadNextEvent
added: TProgram.OfferToStatusLine
added: TProgram.SelectWindowByAltKey
added: TAppInit.SharedScreen
added: TAppInit.SharedQueue
added: TAppInit.SharedSysErr
added: TAppInit.Shutdown
added: TApplication.Subsystems
added: ApplicationRoot
added: HexDigitValue
added: DecodeHex
added: PaletteOfHex
added: WholeScreen
added: StatusItemWithoutText
added: WaitInShell
added: IsTileable
added: CountForCascade
added: PlaceCascaded
added: CountForTiling
added: PlaceTiled
added: DeliverTimerExpired
added: BackgroundPalette
added: AppPalettes

TVoidProc and TSetCtrlBrkHandlerProc are the procedural types of the hooks that stand for parts of the
C++ that no unit has yet and no input defines. InitHistoryHook and DoneHistoryHook stand for initHistory and doneHistory,
which the constructor and the destructor of TApplication call; SetCtrlBrkHandlerHook stands for
THardwareInfo::setCtrlBrkHandler, which TSystemError.Resume and TSystemError.Suspend call with True and False. While a
hook is nil it does nothing. ValidView asks LowMemory of TvMem whether the memory is low. TvApp gives TProgram.Application to the ApplicationHook of TvMenus when
the unit starts. EventTimeoutMs of TvViews, which is
TProgram::eventTimeoutMs, is set to its value 20 when the unit starts.

A Pascal class has one parent, so the classes that the C++ inherits virtually beside TGroup are classes between TGroup
and the class that uses them: TDeskInit between TGroup and TDeskTop, and TProgInit between TGroup and TProgram, as
TWindowInit is for TWindow. They hold the functions that make the parts, which are the types
TCreateBackgroundFunc, TCreateStatusLineFunc, TCreateMenuBarFunc and TCreateDeskTopFunc. TProgram has a constructor
without arguments, which passes initStatusLine, initMenuBar and initDeskTop, and a constructor that takes the three
functions in the place of the initializer TProgInit(...) of a derived class; TApplication has the same two, and
TDeskTop has one that takes the function that makes the background. A nil function makes no part. TAppInit is a class
that a TApplication creates before it constructs its base; its constructor starts the screen, the event queue and the
system error handler once, as the static objects of the C++ constructor are made once, and TAppInit.Shutdown ends them
in the reverse order, which the unit also does when it ends. TApplication holds the TAppInit in the private field
Subsystems. The objects THardwareInfo and TMouse of that constructor have no counterpart: the backends of TvScreen and
TvSys stand for them.

The static data of the classes are class variables: StatusLine, MenuBar, DeskTop, Application, AppPalette and the
text ExitText of TProgram, the protected Pending and the private TimerQueue, and DefaultBkgrnd of TDeskTop. ExitText
and DefaultBkgrnd hold the values of tvtext2.cpp when the unit starts. The flags ctrlBreakHit and saveCtrlBreak of TSystemError are the class
variables CtrlBreakHit and SaveCtrlBreak. TSystemError has the members of the branch of syserr.cpp for the flat memory
model: Create, Destroy, Resume and Suspend. The three palettes of the application are made from the tables cpAppColor,
cpAppBlackWhite and cpAppMonochrome of app.h, which are kept as hexadecimal digits, and the palette of TBackground is
made from cpBackground; AppPalettes and BackgroundPalette hold them and the unit releases them when it ends. The help
contexts hcNew to hcClose and the palette numbers apColor, apBlackWhite and apMonochrome keep their names.

The function iSqr, mostEqualDivisors and dividerLoc of tdesktop.cpp are ISqr, MostEqualDivisors and DividerLoc, and
calcTileRect is CalcTileRect inside the unit. The callbacks doCount, doCascade, doCountTileable and doTile and the
function Tileable are CountForCascade, PlaceCascaded, CountForTiling, PlaceTiled and IsTileable inside the unit, and
handleTimeout and viewHasMouse of tprogram.cpp are DeliverTimerExpired and ViewHasMouse. The variables of tdesktop.cpp
that the callbacks share are variables of the unit that are not visible outside it.

The members of the C++ that are static functions taking a TRect by value (initStatusLine, initMenuBar, initDeskTop,
initBackground) are class functions with the same parameter. The parameter of executeDialog is a TWindow, because
TDialog has no unit yet and the routine uses only the members of TView; insertWindow takes and returns a TWindow. The
status items of initStatusLine that have a null text in the C++ keep a nil Text after the constructor of TStatusItem,
which always allocates a text, has made them. The calls getMouseEvent and getKeyEvent of TEvent are the class
procedures GetMouseEvent and GetKeyEvent of TEventQueue. GetEvent of TProgram reads the posted events of the event
queue before the mouse and the keyboard, and Idle runs only when none of the three gave an event.

## Added by the translation of TvList

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: PListBoxRec
added: ListViewerPalette
added: ListMarkers
added: DividerCode
added: AutosPerStep
added: TListViewer.ShowBarWhenLive
added: TListViewer.DragTarget
added: TListViewer.KeyTarget
added: TListViewer.HandleMouseDown
added: TListViewer.HandleKeyDown
added: TListViewer.HandleBroadcast
added: LowAttr
added: AnyBit

PListBoxRec is the pointer to a TListBoxRec, which GetData and SetData of TListBox take from the untyped pointer of
their argument. The names ListViewerPalette, ListMarkers, DividerCode, AutosPerStep, LowAttr and AnyBit are
inside the unit and are not visible outside it. ListViewerPalette is the palette that the static variable of
getPalette of tlstview.cpp holds, made from cpListViewer when the unit starts and released when it ends. ListMarkers
is the table specialChars of tvtext1.cpp, which TvDialog keeps for its own use. DividerCode is the character '\xB3'
that draw writes between two columns, and AutosPerStep is the local mouseAutosToSkip of handleEvent. LowAttr gives the
attribute that a conversion of the result of getColor to a TColorAttr gives, which is the low one of the pair. AnyBit
tells whether a flag of a mask is set, as the tests with & of the C++ do.

The members of TListViewer that handleEvent of the C++ holds in one body are split in three, one for each kind of
event: HandleMouseDown, HandleKeyDown and HandleBroadcast. DragTarget is the part of the mouse loop that gives the
item for a mouse outside the view, and it keeps the count of the automatic events; KeyTarget is the switch of the
key codes, and it tells whether the key moves the focus. ShowBarWhenLive is the repeated code of setState that shows
a scroll bar while the view is active and visible and hides it otherwise. These five are private.

The function getText has no buffer here: GetText returns the text as a string, and its second parameter is the
largest length of the text, which is the third parameter of the C++. In TListBox the text is the block of characters
of the item up to its terminating zero or up to that length. A nil item gives an empty text. The static member
emptyText of TListViewer is the class variable EmptyText, which holds the text of tvtext2.cpp when the unit starts.
The member list of TListBox is the function
List, and the protected member items is Items. The record TListBoxRec keeps its name, with the members Items and
Selection. The destructor of TListBox does not free its list, as the destructor of the C++ is empty; the list is
freed by NewList when another list is given, by SetData and by the owner of the list.

## Added by the translation of TvValid

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TErrorBoxProc
added: ErrorBoxHook
added: PLongValue
added: TRangeValidator.RangeErrorMsg
added: TPXPictureValidator.RunPicture
added: TPXPictureValidator.PicAt
added: AllCharsIn
added: ScanDecimal

TErrorBoxProc is the procedural type of the hook that stands for a part of the C++ that no unit has yet and no input
defines. ErrorBoxHook stands for the call messageBox(mfError | mfOKButton, ...) that Error of TPXPictureValidator,
TFilterValidator, TRangeValidator and TStringLookupValidator makes; it takes the message text and the arguments of the
call (the picture, or the two limits of the range) and does nothing while it is nil. The constants mfError and
mfOKButton are not passed, because every call of the validators has the same two.

The texts errorMsg of the classes and validUnsignedChars and validSignedChars of TRangeValidator are the class
variables ErrorMsg of TPXPictureValidator, TFilterValidator and TStringLookupValidator, and ValidUnsignedChars and
ValidSignedChars of TRangeValidator, which hold the texts of tvtext2.cpp when the unit starts. The errorMsg of
TRangeValidator is RangeErrorMsg, because a class variable of a derived class does not take the name of one of its
base class. The texts are formats of the Format function, so the conversion %ld of the range message is %d, and the
character \n of the picture message is the character 10. TStringCollection is not defined by a unit
or by an input, so TStringLookupValidator takes and holds a TNSCollection whose items are blocks of characters with a
terminating zero, and its destructor and NewStringList destroy it with TvObject.DestroyObject, as destroy does.

A char pointer of the C++ is a string. The arguments s of isValidInput, transfer and picture, which the routines may
change, are var parameters, and the argument of the constructors that take a TStringView is a const string. The member
pic of TPXPictureValidator is a string that is never nil, and the members validChars and strings are a string and a
collection. The members min and max of TRangeValidator are the fields Min and Max of type LongInt (int32_t). The type
long of transfer and of the conversion %ld is clong of the unit ctypes; ScanDecimal is that conversion: white space, a
sign and digits, with the nearest limit for a number beyond the range, and no result when there is no digit. When
vtGetData finds no number, the buffer gets 0, where the C++ stores a value that was never set. The functions isNumber,
isLetter, isSpecial, numChar, isComplete and isIncomplete are IsNumber, IsLetter, IsSpecial, NumChar, IsComplete and
IsIncomplete and are visible outside the unit; the static function uppercase and the static function stringMatch are
Uppercase and StringMatch inside the unit. The enumerations TVTransfer and TPicResult and the constants vsOk, vsSyntax,
voFill, voTransfer and voReserved keep their names.

The constructor of TPXPictureValidator calls picture, which is virtual; RunPicture holds the body of the function and
the constructor calls it, so a class derived in Pascal does not take part in the check of the constructor, as in the
C++ where a call in a constructor reaches the function of the class that is being made. Picture calls RunPicture.
PicAt gives the character of the picture at a position, and the character with the code 0 after its end, as the
reading of the terminating zero of the C++. AllCharsIn is the test strspn(s, chars) == strlen(s) of the filter
validators.

## Added by the translation of TvInput

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TInputLine.HandleMouseDown
added: TInputLine.HandleKeyDown
added: TInputLine.EnterKeyText
added: TInputLine.HandleCommand
added: TInputLine.EraseSpan
added: TInputLine.ScrollWhileHeld
added: TInputLine.DragSelection
added: InputLinePalette
added: Larger
added: Smaller
added: TextBeforeNul
added: LowAttrOf
added: CharLengthAt

The members of TInputLine that handleEvent of the C++ holds in one body are split in four, one for each kind of
event and one for the text of a key: HandleMouseDown is the case of evMouseDown, HandleKeyDown is the case of
evKeyDown, and it tells whether the key is for the line (the `return` of the C++ that leaves handleEvent before the
commands are updated is its answer False), EnterKeyText is the default branch of the switch of the key codes, and
HandleCommand is the case of evCommand. All four are private. Three more private members hold repeated or long
pieces: EraseSpan is the sequence of the keys Backspace, Ctrl-Backspace and Ctrl-Delete (select a span when nothing is
selected, delete the selection, check the text), and ScrollWhileHeld and DragSelection are the two loops of
HandleMouseDown. InputLinePalette is the palette that the static
variable of getPalette holds, made from cpInputLine when the unit starts and released when it ends. Larger and Smaller
are max and min, TextBeforeNul is the reading of a block of characters up to its terminating zero, LowAttrOf gives the
low attribute of the pair that getColor returns, and CharLengthAt is TText::next of the text that starts at a
position. These five are inside the unit and are not visible outside it.

The functions hotKey and hotKeyStr are defined in the file of TInputLine, so they are the functions HotKey and
HotKeyStr of the unit, visible outside it. When the unit starts it gives them to HotKeyHook of TvDialog and to
HotKeyStrHook of TvMenus, which stand for them in those units; a program that does not use TvInput leaves the hooks
as they are. The static functions prevWord and nextWord are PrevWord and NextWord inside the unit, and the constant
CONTROL_Y, the table padKeys (a set of scan codes, PadKeys) and the palette cpInputLine keep their names.

The text of a line is a string: the member data is the field Data, and oldData is OldData. The members maxLen,
maxWidth, maxChars, curPos, firstPos, selStart and selEnd are public fields as in the C++, and validator, anchor,
oldCurPos, oldFirstPos, oldSelStart and oldSelEnd are the protected fields Validator, Anchor, OldCurPos, OldFirstPos,
OldSelStart and OldSelEnd. The private member functions of the class are protected, so that a class of another unit
can read the state of a line; setCmdState keeps its name and takes a command, so it hides SetCmdState of TView, which
takes a set of commands. The arrows rightArrow and leftArrow of tvtext1.cpp are the class variables RightArrow and
LeftArrow, which start as the characters 16 and 17 and which a program may change. The limit modes ilMaxBytes,
ilMaxWidth and ilMaxChars keep their names.

Data never holds a zero character that ends it early: a text that comes from a validator, from SetData or from a key
event ends at its first zero character, as a block of characters does. GetData copies DataSize bytes, the text, its
terminating zero and then zeros, where the C++ copies the bytes that follow the zero in the block. SetData and
CheckValid cut a text that is longer than MaxLen, where the C++ would write beyond its block. The size DataSize is a
Word, as ushort is, so it wraps for a limit above 65534 bytes in the same way. The argument rec of GetData and SetData
is a Pointer to a record of at least DataSize bytes. The text of a key event has at most four bytes, which is
maxCharSize of config.h.

## Added by the translation of TvHist

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TCreateListViewerFunc
added: THistory.OpenHistoryList
added: THistory.TakeChoice
added: Rc4
added: RecordId
added: RecordLength
added: RecordChars
added: RecordText
added: OffsetAfter
added: StoreRecord
added: TextOfChars
added: NoRecord
added: MaxStoredText
added: RecordOverhead
added: TextOffsetInRecord
added: BlockSlack
added: ArrowOfHistory
added: HistoryBlock
added: BlockBytes
added: HistoryPalette
added: HistoryViewerPalette
added: HistoryWindowPalette

THistory calls strnzcpy, which is Strnzcpy of TvUtil, to put the chosen text into the line with the limit
maxLen + 1. The function strwidth is the width of TText of TvUtf8, and ctrlToArrow is the function of TvKeys.

The record HistRec of histlist.cpp is not a type: the lists are one block of bytes, and a record is known by its
offset in the block, where the offset NoRecord (-1) stands for the null pointer. RecordId, RecordLength and
RecordChars read the id, the length byte and the text of the record at an offset, RecordText gives the text as a
string, OffsetAfter is the function next, and StoreRecord is the constructor of HistRec. The block is HistoryBlock
with the size BlockBytes that InitHistory took from HistorySize; it has BlockSlack bytes more, so that the length
byte at the end of the last record can be read. The static variables curId, curRec and lastRec are the variables
CurId, CurRec and LastRec of the unit, and startId, advanceStringPointer, deleteString and insertString are StartId,
AdvanceStringPointer, DeleteString and InsertString; none of these is visible outside the unit. The text of a
record is at most MaxStoredText bytes, because the length of a record is a byte, so HistoryAdd cuts a longer text;
a text that is larger than the whole block is not stored, and the older entries are dropped. The functions
HistoryAdd, HistoryCount, HistoryStr, ClearHistory, InitHistory and DoneHistory do nothing, and give 0 and nil, while
there is no block. HistoryStr gives a PAnsiChar, nil when the list has no such entry, also for an index after the
last entry; the text stays valid until the lists are changed. The variable historySize is HistorySize.

The type THistInit, which the C++ inherits virtually beside TWindow, is the class between TWindow and
THistoryWindow, as TWindowInit is between TGroup and TWindow. Its constructor takes the bounds of the window, because
the constructor of TWindow needs them, and the function that makes the list viewer; TCreateListViewerFunc is the type
of that function, and the function THistoryWindow.InitViewer is a class function without Self. The member viewer of
THistoryWindow is the protected field Viewer, and the function getSelection, which has a buffer in the C++, is
GetSelection and returns the text, like GetText of TvList. The constructor of THistory takes the palette strings
cpHistory, cpHistoryViewer and cpHistoryWindow, which keep their names, and the palettes made from them,
HistoryPalette, HistoryViewerPalette and HistoryWindowPalette, are made when the unit starts and released when it
ends. The static member icon of THistory is the private class variable Icon, which the unit sets to ArrowOfHistory.
The part of handleEvent of THistory that opens the list is the private member OpenHistoryList, and the copy of the
chosen text into the line is the private member TakeChoice; Rc4 makes a TRect from four numbers inside the unit. As in
the C++, a scan of a list skips the record at the start of the block, which is the empty record of ClearHistory, so
when that record has been dropped to make room the oldest entry is not seen. A THistory that has
let go of its line in ShutDown ignores its events after the handling of its base class. When the unit starts it gives
InitHistory and DoneHistory to InitHistoryHook and DoneHistoryHook of TvApp.

## Added by the translation of TvFiles

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: PSearchRec
added: MaxNameLength
added: TMakeDefaultProc
added: ChDirButtonDefaultHook
added: GetDisk
added: CompareNames
added: FindSeparator
added: FindLastSeparator
added: BeginsWithDot
added: FindCode
added: NewSearchRecord
added: CopyFoundEntry
added: SearchKey
added: NoFileRecord
added: CurrentDisk
added: IndentStep
added: DefaultParentTime
added: CharOrZero
added: IsAlphaCode
added: HasAnyOf
added: SplitFileName
added: IllegalNameChars
added: SearchTextLength

PSearchRec is the pointer type that stands for TSearchRec *. The entries of a directory are records that the
collections keep as pointers; the names of the entries are at most MaxNameLength characters, because the size
MAXFILE + MAXEXT - 1 comes from a header that is not among the translated sources. TSearchRec is the record of the
unit, not the one of SysUtils, which the unit names as SysUtils.TSearchRec when it searches a directory. The typed
members of the collections (at, firstThat and lastThat) return the typed pointer; the other members keep the pointer
of TvObjs, because a member that takes a different type of pointer cannot override a virtual member of the base. The
sorted collection of files and the collection of directories are not related by a base, so the sorted list box turns
the list of its base TListBox into a TSortedCollection by a typecast.

TSortedListBox is translated from stddlg.cpp: its member searchPos is the private field SearchPos, its virtual getKey is
GetKey, which gives a pointer to the characters of its argument, and the static function equal is Equal. The text
that handleEvent keeps in the buffer curString is a string that holds the characters up to the terminating zero.
CharOrZero is the reading of a character of a string, with the zero character after its end, IsAlphaCode is isalpha
for the ASCII letters, and SearchTextLength is the size 255 that handleEvent gives to getText. ChDirButtonDefaultHook,
with the type TMakeDefaultProc, stands for the call chDirButton->makeDefault of the dialog TChDirDialog that owns a
TDirListBox, and it does nothing while it is nil. The text tooManyFiles is the class variable TooManyFiles of
TFileList, which holds the text of tvtext2.cpp when the unit starts, and the warning is shown with MessageBox of TvMsgbox when the allocation
of an entry fails (EOutOfMemory is caught, as the C++ tests a null pointer).

The tables of TDirListBox (pathDir, firstDir, middleDir, lastDir, drives and graphics) are the class variables
PathDir, FirstDir, MiddleDir, LastDir, Drives and Graphics, which get the values of tvtext1.cpp, in code page 437,
when the unit starts. The paths that TDirListBox reads and builds use PathSep of TvPath as their separator, the
texts of the drives keep the backslash, and a search of a directory uses PathAllFiles for the mask "*.*". GetDisk
stands for getdisk and gives the disk C. CompareNames is strcmp, FindSeparator and FindLastSeparator are strchr and
strrchr for the separator, BeginsWithDot is the test of the first character of
a name, FindCode is strchr of a character in a block, NewSearchRecord is the operator new of DirSearchRec and
CopyFoundEntry is its member readFf_blk. SearchKey is the static record of getKey, NoFileRecord is the static record
noFile of readDirectory, and CurrentDisk, IndentStep and DefaultParentTime are the values 'C', 2 and 0x210000 that the
C++ writes in its code. The routines validFileName and getCurDir are ValidFileName and GetCurDir. SplitFileName is the
part of fnsplit that validFileName uses, without a drive, IllegalNameChars is the static illegalChars of the branch
for a flat memory model, and HasAnyOf is strpbrk as a test. GetCurDir takes the disk as an integer, with the default
-1, and gives the directory without the characters of a drive, written with PathSep before it and, when it is not the
root, after it; a disk that is not the current one gives the root. The routines fexpand, squeeze and getHomeDir are
not in this unit.

## Added by the translation of TvFileDlg

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: MaxPath
added: InfoPanePalette
added: LowAttrOf
added: TwoDigits
added: TFileInfoPane.FileBlock
added: TFileDialog.AddButton
added: TFileDialog.FitToScreen
added: TFileDialog.FinishWithFileCommand
added: TFileDialog.TurnDoubleClickIntoOK
added: TrimName
added: SplitPath
added: MergePath

MaxPath stands for MAXPATH, which a header outside the translated sources defines; it is the size that strnzcpy is
given for the wild card and for the text of the input line. getCurDir and validFileName are GetCurDir and
ValidFileName of TvFiles. fexpand is PathExpandFrom and PathExpand of TvPath, and fnsplit and fnmerge are
SplitPath and MergePath, made with PathDrive and PathSplit of TvPath: the drive is the drive of the path, the
directory is what PathSplit gives after the drive, and the merge puts the four parts one after the other. The
function trim of tfildlg.cpp is TrimName, because Trim belongs to SysUtils; it is the branch for a flat memory model,
which copies the text up to its first zero character and does not cut white space, because tv.h defines __FLAT__.

TFileInputLine and TFileInfoPane are translated from stddlg.cpp. The member file_block of TFileInfoPane is the public
field FileBlock. The static palette of getPalette is the variable InfoPanePalette, made from cpInfoPane when the unit
starts and released when it ends, LowAttrOf gives the low attribute of the pair that getColor returns, and TwoDigits is
the text of a number with at least two digits that draw builds with itoa and a leading '0'. The draw reads the time of
the entry as the packed time of DOS and writes the hour that it shows back into it, as the C++ does through the
structure ftime. The text that handleEvent of TFileInputLine puts into the line is cut to MaxLen, and the separator
between a directory and the wild card is PathSep.

The texts filesText, openText, okText, replaceText, clearText, cancelText, helpText, invalidDriveText and
invalidFileText of TFileDialog are the public class variables FilesText, OpenText, OkText, ReplaceText, ClearText,
CancelText, HelpText, InvalidDriveText and InvalidFileText, and the texts pmText, amText and months of TFileInfoPane
are the public class variables PmText, AmText and Months (an array from 0 to 12). They hold the texts of tvtext2.cpp
when the unit starts. The members fileName, fileList, wildCard and directory are the
public fields FileName, FileList, WildCard and Directory, and the last two are strings. The function getFileName has no
buffer here: GetFileName returns the name as a string, as GetText of TvList does, and GetData copies it with its
terminating zero into the block that it is given. The parameter of the constructor that is a TStringView is a const
string. A file dialog with no application, which is a TProgram.Application that is nil, keeps the bounds of its
constructor, where the C++ would read the size of the application; FitToScreen is the block of the constructor that
fits the dialog to the screen, and AddButton is the repeated insertion of a button of the row at the right of the list,
which gives the button the grow mode gfGrowLoX or gfGrowHiX and moves the rectangle down by three rows.
HandleEvent is split by the kind of event: FinishWithFileCommand is the case of evCommand that ends the dialog at
cmFileOpen, cmFileReplace and cmFileClear, and TurnDoubleClickIntoOK is the case of evBroadcast that turns
cmFileDoubleClicked into a cmOK command that is put back. Both are private.

## Added by the translation of TvMouse

The members GetButtonCount, CursorOn and CursorOff of TEventBackend in TvSys are the functions getButtonCount, cursorOn
and cursorOff of THardwareInfo, which the mouse calls; the backend of the event queue stands for THardwareInfo, as the
backend of TvScreen does for the screen. In the base class GetButtonCount gives 0 and CursorOn and CursorOff do nothing.
The type of GetButtonCount is Cardinal (DWORD).

THWMouse and TMouse keep their names. The members of THWMouse that are protected in the C++ are protected, the static
members are class procedures and class functions, and the static member buttonCount is the protected class variable
ButtonCount, a Byte (uchar); the static noMouse is the private class variable NoMouse. The constructor of THWMouse is
protected and the destructor is public. Only the branch of the files for the flat memory model is translated, so
handlerInstalled and registerHandler do not exist, SetRange does nothing and GetEvent clears the buttons, the wheel,
the position and the flags and leaves ControlKeyState as it is.

## Added by the translation of TvTermOs

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: ConsoleCtl.FdIn
added: ConsoleCtl.FdOut
added: ConsoleCtl.UseDescriptors
added: EnvLookup
added: ParseEnvInt

Only the branch _TV_UNIX of conctl.cpp is translated. The members in and out are FdIn and FdOut, because in and out are
reserved words. The members fin and fout and the data members files and ownsFiles are not translated: a FILE of the C
library has no counterpart, the descriptors are opened and closed directly, and the flush of fout that write makes
first has nothing to flush. The data member fds is the private field FFds, instance is the private class variable
FInstance, and the constructor and the destructor are Create (private) and Destroy. GetInstance and DestroyInstance are
class functions, and IsLinuxConsole exists on Linux only.

UseDescriptors replaces the descriptors of an instance, closes the ones that the instance opened itself and leaves
the new ones open when the instance ends; it exists so that the routines of the instance can be used on pipes.

The function template getEnv is the two overloaded functions GetEnv: the one with a string default stands for the
instantiation for TStringView and the one with a LongInt default for the specialisation for int. EnvLookup is the
call of getenv, which tells whether the variable exists, and ParseEnvInt is the call of strtol with the base 0 and the
test that digits were read, with the result cut to the low 32 bits as the conversion of long to int does. The record
winsize and the types and constants of the font request are inside the unit and are not visible outside it.

## The functions of misc.cpp

The function message is Message of TvViews. Its parameter infoPtr is a Pointer, as the member InfoPtr of
TMessageEvent in TvEvents is, and so is its result: the Pointer that the receiver leaves in the event when it clears
the event, or nil. The functions strnzcpy and strnzcat are Strnzcpy and Strnzcat of TvUtil. The buffer dst of dstSize
characters is the var parameter Dst, a string whose length stays below DstSize, and the length of the string is what
the two functions return. The function lowMemory is LowMemory of TvMem.

## Added by the translation of TvMem

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: PBufListEntry
added: TBufListEntry.NewBlock
added: TBufListEntry.FreeBlock
added: TVMemMgr.ClearSafetyPool
added: GetBlockOrNil
added: ResizeBlockOrNil
added: EntryOf
added: DataOf
added: ShrinkDiscardable

TBufListEntry is a record whose fields Next, Prev, Owner and Sz are private to the unit, and the data of a buffer
follows the record in the same block of memory. PBufListEntry is the pointer to it, and the member owner, which is a
reference to a pointer, is the PPointer Owner. The static member bufList is the class variable BufList. The operator
new with an extra size is the class function NewBlock, which gives the memory of a header and the extra bytes, and the
operator delete is the class procedure FreeBlock. The operator new without an extra size, which gives a null pointer
so that the class is not made by a plain new, has no counterpart. The constructor and the destructor are Create and
Destroy of the record: Create sets up the header in the memory that NewBlock gave, and Destroy takes the header out
of the list, sets the owner to nil and frees the memory. The function freeHead is private in the C++ and is public
here, because its only user, the function allocBlock, is not translated; it tells whether a buffer was discarded.

The members of TVMemMgr that are static are class procedures and class functions, and the static variables
safetyPool, safetyPoolSize and inited are the private class variables SafetyPool, SafetyPoolSize and Inited. The
argument sz of resizeSafetyPool has the default DEFAULT_SAFETY_POOL_SIZE, which keeps its name. The type size_t is
PtrUInt, the type void *& of the owner and of the first argument of allocateDiscardable and reallocateDiscardable is a
var Pointer, and safetyPoolExhausted gives an Integer, as the C++ does. ClearSafetyPool is the call
ResizeSafetyPool(0). GetBlockOrNil and ResizeBlockOrNil are malloc and realloc on the memory manager of the
run-time library: EOutOfMemory is caught and becomes the nil pointer. EntryOf and DataOf are the two conversions
between the address of the data of a buffer and its header, which the C++ writes with sizeof(TBufListEntry), and
ShrinkDiscardable is the branch of reallocateDiscardable that makes a buffer smaller. These four are inside the unit
and are not visible outside it.

The object memMgr is the variable MemMgr of the unit. It is made when the unit starts and freed when the unit ends,
so the safety pool exists from the start, as the initialization of the C++ object does. The global operators new and
delete of new.cpp, with allocBlock and deleteBlock, are compiled only for one compiler and are not translated; the
member initMemMgr, which is declared and never defined, is not translated.

## Added by the translation of TvHelp

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: PCrossRef
added: IntMax
added: PairLow
added: TextSlice
added: HelpViewerPalette
added: HelpWindowPalette
added: THelpViewer.RefreshLimit

THelpViewer.RefreshLimit is the private call of SetLimit with the longest line and the number of lines of the topic, which the
constructor, ChangeBounds and SwitchToTopic make. The code of HandleEvent and of MakeSelectVisible is split in routines
that are local to them (StepSelection, FollowRef, AskToClose, RefAt, Reveal and the routines for the three kinds of event).

PCrossRef is the pointer type that stands for TCrossRef *; the list of the cross references of a topic is a block of
TCrossRef records that CrossRefs points to, and it is nil while the topic has none. TParagraph is a class with the public
fields Next, Wrap, Size and Text, and TCrossRef is a record with the fields Ref, Offset and Length. The text of a paragraph
is a PAnsiChar block of Size bytes and a terminating zero, which the topic releases with FreeMem. The int32_t of the index
is a LongInt, and the array index of THelpIndex is the PLongInt Index; its size is a Word, as ushort is. IntMax is the
INT_MAX of limits.h, PairLow gives the low attribute of the pair that GetColor returns, which is the conversion of a
TAttrPair to a TColorAttr, and TextSlice gives the bytes of a block of characters from a position as a string. The
palettes that the static variables of the two getPalette functions hold are the variables HelpViewerPalette and
HelpWindowPalette, made from cHelpViewer and cHelpWindow when the unit starts and released when it ends. None of
these six is visible outside the unit except PCrossRef.

The name of THelpTopic and of THelpIndex is the public class variable Name, a PChar that holds the type name when the unit
starts, and the objects RHelpTopic and RHelpIndex are made at that time. The texts helpWinTitle of THelpWindow and
invalidContext of THelpFile are the private class variables HelpWinTitle and InvalidContext, which hold the texts of
tvtext2.cpp when the unit starts. The functions read, write, build and streamableName are Read, Write, Build and
StreamableName; Build is a class function without Self, and the constructors that take StreamableInit are not translated.
The operators >> and << of the helpbase.h for the pointers of the two classes are Get of ipstream, with a Pointer, and Put of
opstream and iopstream. The type TCrossRefHandler takes an opstream and a LongInt, the variable crossRefHandler is
CrossRefHandler, and notAssigned is NotAssigned; the handler counts as unassigned while it holds the address of
NotAssigned.

A TStringView that getLine gives is an AnsiString that holds a copy of the line, the parameter text of wrapText is a PAnsiChar and
its parameter wrap is DoWrap. The functions isBlank, getLineAtOffset and discardTrailingWhitespaces are IsBlank,
GetLineAtOffset and DiscardTrailingWhitespaces inside the unit, and the static ensureStreamSize is the private class
procedure EnsureStreamSize. The reference parameters of GetCrossRef, which it sets, are var parameters. The reference
parameter of SetCrossRef is a non-const reference in the C++ that the function only reads, so here it is a const parameter. The members hFile, topic and
selected of THelpViewer are the public fields HFile, Topic and Selected, and the parameter selected of makeSelectVisible is
ASelected. A THelpTopic that is asked for a cross reference whose offset lies beyond its text gives the point (0, 0), the
length 0 and the number of the reference, and a length that reaches beyond its paragraph is cut at the end of the
paragraph, where the C++ reads beyond the block. A negative number is not an entry of THelpIndex, and SetCrossRef ignores
a number below 0 as it ignores a number beyond the list. The bars of THelpWindow are made one after the other, the horizontal bar first.

## Added by the translation of TvDispBuf

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: PScreenCell
added: TDisplayClockFunc
added: DisplayClock
added: DisplayBuffer.InitState
added: DisplayBuffer.Range.RangeBegin
added: DisplayBuffer.Range.RangeEnd
added: SignalSafeMutexState.Section
added: SignalSafeMutexState.Depth
added: SignalSafeMutexState.Create
added: SignalSafeMutexState.Destroy
added: FlushScreenAlgorithm.Create
added: FlushScreenAlgorithm.CellIdx
added: IsTrailCell
added: IsWideCell
added: NegateAttribute
added: PackedUtf8Of
added: SystemClock
added: CellCountOf

CellCountOf gives the number of cells for a size, the product x*y of resizeBuffer, with zero for a side that is not positive.

The classes DisplayAdapter, DisplayBuffer and SignalSafeMutexState keep their names. PScreenCell is the pointer type that
stands for TScreenCell *; ReloadScreenInfo of DisplayBuffer gives it, nil while the screen has no cells, and ScreenWrite
takes it. TDisplayClockFunc is the type of the clock of the buffer and DisplayClock is the variable that holds it. It
stands for std::chrono::steady_clock::now and gives microseconds in a QWord; the default counts the milliseconds of the
run-time library, and the time points lastFlush and pendingFlush, the duration flushDelay and the zero time point are
QWord values in microseconds. The members begin and end of DisplayBuffer::Range are RangeBegin and RangeEnd, because
both are reserved words. The private members of DisplayBuffer are private to the unit, so the class FlushScreenAlgorithm,
which the C++ declares a friend and which is inside the unit, reads them. InitState is the part of the constructor that
reset calls again with the destructor and the placement new; it sets every member to its first value and keeps the
resolved rate. The pointer cell of FlushScreenAlgorithm is the index CellIdx into the buffer, and its aggregate
initialisation is the constructor Create. IsTrailCell and IsWideCell are isTrail and isWide, NegateAttribute is
negateAttribute, and PackedUtf8Of is the call CpTranslator::toPackedUtf8 through CodePageToPackedUtf8 of TvText. The
function SystemClock is the default of DisplayClock. The member functions that take a DisplayAdapter & take the class
as a plain parameter, and the parameters of DisplayAdapter that are TPoint and TColorAttr are const parameters.

The spin lock of mutex.h is the class SignalSafeMutexState, whose Acquire and Release stand for the static functions
acquire and release; it holds a recursive critical section (Section), the thread that holds it and the nesting depth,
so a thread that holds the lock takes it again as SignalSafeReentrantMutex does, and LockedByCurrentThread is the member
of the same name. A critical section is not safe in a signal handler. The template SignalSafeReentrantMutex, the type
LockGuard and currentThreadId are not translated. The platform member that holds the lock around the calls of the
buffer is not part of this unit.


The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TWriterCall
added: BridgeCon
added: BridgeToConsole
added: RunWithConsole
added: SendText
added: ByteAt
added: PutSextet
added: StoreByte
added: SextetOf
added: Base64Alphabet
added: Base64EncodeText
added: Base64DecodeText
added: CodePageCharOf
added: PrintableCodePageCharOf
added: LittleEndian32
added: FrameFar2lRequest
added: MakeClientId
added: Far2lOpenRequest
added: Far2lCloseRequest

The namespace TermIO is the class TTermIO, whose members are class functions and class procedures. The parameter con of
the members that write is a ConsoleCtl of TvTermOs. The types InputState, GetChBuf, CSIData, InputGetter and
ParseResult are TInputState, TGetChBuf, TCSIData, TInputGetter and TParseResult of TvEvents, which holds the parsers
and the key tables; the members of TTermIO that parse, and normalizeKey, call the routines of TvEvents of the same name.
The function getenv of keyModsOn is the lookup of TvEvents.KeyModsOn. The function readUntilBelOrSt returns a string
where the C++ returns a block of characters that is null on failure, and the text ends at its first zero character. The
function pointer parameter of requestClipboardText is a TTextProc, and the text parameters of setClipboardText and of the
clipboard routines are AnsiString, so that a text is not cut at 255 bytes.

The functions encodeBase64 and decodeBase64 are EncodeBase64 and DecodeBase64, in the forms that take and return a
string; the forms that write into a given block have no counterpart. The decoder gives the value 128 to a character that
is not in the alphabet and uses it in the same sums as the table of the C++ does. The table b64e is Base64Alphabet and
the table b64d is the function SextetOf; ByteAt, PutSextet and StoreByte read and write one byte or one group of six bits
of a text. Base64EncodeText and Base64DecodeText are the conversions that the variables Base64Encode and Base64Decode of
TvEvents hold, and CodePageCharOf and PrintableCodePageCharOf are the ones that CpFromUtf8 and CpPrintableFromUtf8
hold, made with fromUtf8 and printableFromUtf8 of CpTranslator. The initialization of the unit sets these four variables
and Far2lEnableSeq and Far2lDisableSeq of TvEvents.

The functions setFar2lClipboard and requestFar2lClipboard are SetFar2lClipboard and RequestFar2lClipboard, and the
functions setOsc52Clipboard and requestOsc52Clipboard are inside the unit. The template concat and the function
pushFar2lRequest are LittleEndian32 and FrameFar2lRequest, with the sequences of the three requests built by the
functions Far2lOpenRequest and Far2lCloseRequest and inside the two clipboard routines. The text f2lClientId is
the variable of the unit that MakeClientId fills with the time as 32 decimal digits when the unit starts. The constant
CF_TEXT is the value 1 of the clipboard format of plain text. The routines of TvEvents write through a procedure that
takes a string; BridgeToConsole is that procedure, BridgeCon is the thread variable that holds the ConsoleCtl it writes to
while a member of TTermIO runs, and RunWithConsole sets it and calls a routine of TvEvents with BridgeToConsole as the
writer. SendText writes a text with the member Write of ConsoleCtl.

## Added by the translation of TvUnix

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TNcursesKeys
added: TUnixEventBackend
added: TUnixScreenBackend
added: TUnixClipboardBackend
added: UnixScreenWrite
added: UnixCaretPosition
added: Platform.DestroyInstance
added: Platform.IsSetUp
added: SigwinchHandler.Make
added: SignalHandler.HandledSignal
added: UnixConsoleAdapter.Make
added: UnixClipboard.Enabled
added: UnixClipboard.ExecutableExists
added: UnixClipboard.ReadSubprocess
added: UnixClipboard.WriteSubprocess
added: NcursesInputGetter.TimeoutMs
added: NcursesInputGetter.WaitReadable
added: NcursesInput.EnterRawMode
added: NcursesInput.LeaveRawMode
added: NcursesInput.TryLegacyKey
added: NcursesDisplay.Send
added: StderrRedirector.Redirect
added: StderrRedirector.CloseAll
added: SmallerOf
added: LargerOf
added: WriteAll
added: IsTerminal
added: SetActionHandler
added: ActionHandler
added: SlotOf
added: SignalCode
added: IsSynchronousSignal
added: DetectTermCap
added: ControlKeyEvent
added: IsLetterCode
added: MakeCommand
added: CopyCommandCount
added: CopyCommandAt
added: PasteCommandCount
added: PasteCommandAt
added: IsExecutableFile
added: AppendText
added: BuildEnvironment
added: WritePipe
added: TArgList
added: TPtrList
added: TPrepareKind
added: TClipCommand
added: TProcessInfo
added: TSignalSlot
added: TSimpleSignalProc
added: TInfoSignalProc
added: PTermiosRec
added: DefaultColumns
added: DefaultRows
added: ScreenChangedCommand
added: ErrInterrupted
added: ErrWouldBlock
added: HandlerDefault
added: HandlerIgnore
added: DefaultSearchPath
added: ChunkSize
added: FdCloseOnExec

TUnixEventBackend, TUnixScreenBackend and TUnixClipboardBackend are the descendants of TEventBackend, TScreenBackend and
TClipboardBackend that stand for THardwareInfo on a terminal of a Unix system; all three call the singleton Platform.
UnixScreenWrite and UnixCaretPosition stand for THardwareInfo::screenWrite and THardwareInfo::setCaretPosition, and are
the values for ScreenWriteHook and CaretPositionHook of TvViews. The member eventQ of THardwareInfo, with eventCount and
the enumerator eventQSize, is EventQ, EventCount and eventQSize of TUnixEventBackend; getPendingEvent and readEvents are
GetPendingEvent and ReadEvents, and the static insertState is InsertState, which starts as True. THardwareInfo::getMouseEvent
and getKeyEvent are GetMouseEvent and GetKeyEvent, and THardwareInfo::clearPendingEvent does nothing, as it does in the C++
for the platform of a Unix system.

The classes InputAdapter, ConsoleAdapter, StderrRedirector, SigwinchHandler, SignalHandler, NcursesDisplay, NcursesInputGetter,
NcursesInput, UnixClipboard, UnixConsoleAdapter and Platform keep their names. NcursesDisplay and NcursesInput work on the
descriptors of ConsoleCtl with the sequences of TvAnsi, TvTermIo and TvEvents, and use no curses library. The members display
and sources of ConsoleAdapter are the public fields Display and Sources, an array of TEventSource. The text parameters of
setClipboardText of ConsoleAdapter, UnixConsoleAdapter, UnixClipboard and Platform are AnsiString, and the parameter of
requestClipboardText is a TTextProc. The static functions create of SigwinchHandler and of UnixConsoleAdapter are Make, because
Create is the constructor; the constructor of NcursesDisplay is the static function create with its private constructor
joined, and the constructor of NcursesInput does not use its display. The static member handledSignals of SignalHandler is the
function HandledSignal, which gives the signal at an index below the constant HandledSignalCount, and SignalHandlerCallback is the
procedure type of the callback. The data member pendingCount of NcursesInputGetter is the function PendingCount, which counts the
bytes that were given back with Unget and the bytes that were read from the descriptor and not taken. The input getter waits
for TimeoutMs milliseconds for a byte, the time that wtimeout sets in the C++, and NcursesInput.GetChNb sets it to 0 for one
read. The private members that Platform has for the console (setUpConsole, restoreConsole, checkConsole, createConsole and
signalCallback) keep their names, and the two forms of setUpConsole and of restoreConsole are overloaded. The platform is
a singleton that the C++ never frees; DestroyInstance gives the console back and frees it, and IsSetUp tells whether a console
other than the dummy one is in use. The members of Platform that the C++ declares for a Windows console (sizeChanged) and the
character operations (charOps, initLocale, initCharOps, initCharWidth and initCharToLower) are not translated.

The macros of the signal handling are not used: the actions of the signals are SigActionRec of BaseUnix, the handler of an action is
its first field, and a set of signals is a row of bits. The functions makeDefaultAction, makeHandlerAction, the comparison of two
actions, isCustomHandler, invokeHandlerOrDefault and invokeDefault of sighandl.cpp are DefaultAction, HandlerAction, SameAction,
IsCustomHandler, InvokeHandlerOrDefault and InvokeDefault inside the unit, and handleSignal is HandleSignal; the flags that SameAction
compares are SA_SIGINFO and SA_RESTART. The information of a signal is a Pointer, and SignalCode reads the code of it. The signal is
raised again with fpKill on the process. The members of SignalHandler::HandlerInfo are the record TSignalSlot, the array Slots holds
one for each signal of the list, and SlotOf gives its index. The handler of SIGWINCH is SigwinchEntry and the callback that gives
the command cmScreenChanged is EmitScreenChangedEvent; ScreenChangedCommand is the value of cmScreenChanged of TvViews.

The functions isSameFile, writeFile and dumpPipe of errredir.cpp are SameFile, WriteAll and DumpPipe. The pipe is emptied by reading it
without blocking until nothing is left, where the C++ reads the number of bytes that FIONREAD gives. IsTerminal stands for isatty.
Redirect holds the chain of calls of the constructor of StderrRedirector, with the same order, and CloseAll closes the descriptors
that are open.

The tables copyCommands and pasteCommands of unixclip.cpp are the functions CopyCommandAt and PasteCommandAt with CopyCommandCount and
PasteCommandCount; the type Command is TClipCommand, the function pointer prepare is the enumeration TPrepareKind, and the argument
vectors are dynamic arrays (TArgList), with the pointers that exec takes in TPtrList. The functions wslCopyPrepare and wslPastePrepare
are the cases pkWslCopy and pkWslPaste, with Utf16LeToUtf8 for the second; WslPasteScript is the text wslPasteCmd, which gets the
process number at the place of the placeholder when it is made. commandIsAvailable is CommandIsAvailable, executable_exists is
FindExecutable (which gives the path) and ExecutableExists, run_subprocess is RunSubprocess with TProcessInfo, close_subprocess is
CloseSubprocess, read_pipe and write_pipe are ReadPipe and WritePipe, and read_subprocess and write_subprocess are the class
functions ReadSubprocess and WriteSubprocess. The program is searched along PATH by FindExecutable and started with fpExecVE, with the
environment of the process and the variables of the command, which BuildEnvironment makes before the fork; AppendText adds a text to
a TArgList. The file that executable_exists finds is a regular file with the permission of others to execute it, as IsExecutableFile
tests. Enabled is a class variable that switches the programs off, which has no counterpart.

The keys of ncursinp.cpp that a control character gives (fromNonPrintableAscii) are made by ControlKeyEvent, and TryLegacyKey decodes
ESC O and a letter, a key of the application keypad that ncurses decodes with its terminal database. The number of colors that
TermCap::getDisplayCapabilities gives is DetectTermCap, which reads TERM and COLORTERM. EnterRawMode and LeaveRawMode stand for the
terminal mode that raw, noecho and nonl set and that endwin restores; PTermiosRec is the pointer to the record of the saved mode.
SmallerOf and LargerOf are min and max.

## Added by the translation of TvPty

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TPtyErrorProc
added: TPtyTermios
added: TPtyWinSize
added: RunClient
added: SayOnStderr
added: LibcErrno

The unit is the Unix branch of pty.h and pty.cc of magiblot/tvterm; the branch of the Windows pseudo console is not
translated. PtyDescriptor and EnvironmentVar keep their names and are records, with the fields MasterFd and ClientPid
and the fields Name and Value (blocks of characters with a terminating zero, PAnsiChar). PtyMaster keeps its name; its
member d is the private field D, and its constructor is Create. The functions createPty, readFromClient, writeToClient,
resizeClient and disconnect are CreatePty, ReadFromClient, WriteToClient, ResizeClient and Disconnect. The first
parameter of CreatePty is ADescriptor.

A TSpan has no unit, so a span is an open array: TSpan<const EnvironmentVar> is a const array of EnvironmentVar,
TSpan<char> is a var array of Char and TSpan<const char> is a const array of Char, and the size of the span is the
length of the array. The parameter bytesRead of readFromClient is an out parameter of type SizeUInt (size_t). The
reference to a function void (&)(const char *) is TPtyErrorProc, a procedure type with a PAnsiChar. The functions
createTermios and createWinsize are CreateTermios and CreateWinsize inside the unit; TPtyTermios and TPtyWinSize are the
records struct termios and struct winsize with the layout and the flag values of the Linux system, so the unit is built
for Linux only. forkpty, signal, setenv, getenv, execvp, _exit, strerror, cfsetispeed, cfsetospeed and __errno_location are
external functions of the C library (forkpty of libutil, except on Darwin), declared inside the unit, and LibcErrno reads
the errno of the C library. The part of createPty that runs in the child process is RunClient, and SayOnStderr writes a
block of characters to the descriptor 2, as fprintf to stderr does, without allocating memory. The message of the failed
program is written with SayOnStderr from its parts, with the same text, and the message of the failed fork is built as a
string before it is passed to the callback.

## Added by the translation of TvVtCore

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: RowRange.RangeEnd
added: RowRange.Unset
added: PRowRange
added: SelectionRange.RangeEnd
added: SelectionRange.Create
added: SelectionAnchor.ToPoint
added: SelectionAnchor.Compare
added: GrowArray.Buf
added: GrowArray.Used
added: GrowArray.Cap
added: TerminalEvent.Type_
added: TerminalEmulatorFactory.Make
added: TEnvironmentVarSpan
added: PEnvironmentVar
added: TWordSpan
added: TMutexProc
added: Mutex.Section
added: Mutex.Item

The namespace tvterm is not a prefix. The members end of RowRange and SelectionRange and type of TerminalEvent are
reserved words, so they are RangeEnd and Type_. A record has no default constructor: the default constructor of
RowRange, which gives the range {INT_MAX, INT_MIN}, is the class function Unset, and the constructors of the
other records take their values. The aggregate initialisation of SelectionRange is its constructor Create. The operator
TPoint of SelectionAnchor is the function ToPoint, and the constructor from a TPoint is the constructor Create that
takes a TPoint. Compare is the three-way comparison on which the operators <, > and = of SelectionAnchor rest. TerminalSurface descends publicly from TDrawSurface, so its base members are all public,
where the C++ makes only size and at visible. The functions damageAtRow give no reference: DamageAtRow gives a PRowRange,
and the const overload has no counterpart. Its parameter and the one of AddDamageAtRow are SizeUInt (size_t), and the
parameters begin and end of AddDamageAtRow are ABegin and AEnd. Resize of TerminalSurface hides Resize of TDrawSurface,
which is not virtual, as it does in the C++. The member damageByRow is the private field DamageByRow.

TerminalState is a class, because its members are a TerminalSurface and a GrowArray, which are objects: its
constructor makes them and its destructor frees them. GrowArray is a class whose struct p is the three private fields Buf,
Used and Cap; the member functions data and size are Data and Size, and the move constructor and the operator = are not
translated. A failure of the memory manager raises the exception of the run-time library, where the C++ calls abort.
The enumeration TerminalEventType is declared with scoped enumerators, which are written TerminalEventType.KeyDown and so
on. The union of TerminalEvent is the variant part of the record, which is selected by the member Type_. The
member data of ClientDataReadEvent is a PAnsiChar and its size is SizeUInt.

TSpan has no unit. A span that is a parameter is a const open array (Writer.Write); a span that is a result is a record
with a pointer to the first element and a count, which are TEnvironmentVarSpan for TSpan<const EnvironmentVar> and TWordSpan for
TSpan<const ushort>, with PEnvironmentVar the pointer to an EnvironmentVar. The function create of TerminalEmulatorFactory
is Make, because Create is the constructor, and its reference parameters are a const TPoint and a Writer, and its result
is a TerminalEmulator. The members of TVTermConstants have the prefix of their names in capitals (CmGrabInput, HcSelecting),
FocusedCmds is the span from CmGrabInput to CmStartSelection, and the record keeps the nine fields contiguous.
The member view of TerminalUpdatedMsg is a TObject, because the class TerminalView is not part of this unit and a class
that is only forward declared has no counterpart in Pascal; a user casts it to the class.

Mutex<T> is the generic class Mutex, specialised as specialize Mutex<LongInt>. Its constructor takes the initial value
of the item, or none, in the place of the arguments that the C++ passes on. The std::mutex m is the critical section
Section of the run-time library, which is recursive, and the item is Item. The member lock takes a procedure of object,
the generic type TMutexProc, which receives the item as a var parameter; its result is not returned, because a Pascal
generic method has no deduced result type, so a procedure that wants to give a value stores it in a field.

## Added by the translation of TvTextView

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TTextDeviceBuf
added: TTextDevice.StreamBuf
added: TLineChunk
added: TTerminal.CopyLine
added: TTerminal.TrimChunk
added: MaxCharSize
added: LargestBuffer
added: LeastOf
added: GreatestOf
added: FindLfBackwards

The class TTextDevice has the bases TScroller and streambuf in the C++. A Pascal class has one parent, so TTextDevice
descends from TScroller and holds a stream buffer, the class TTextDeviceBuf of TvStreams, whose writes go to Xsputn;
StreamBuf gives it, and the stream otstream is an opstream on it. The text is written to an otstream with the members of
opstream that write bytes: Put of an AnsiChar and WriteBytes stand for the operator << of the C++ for characters and
blocks of characters. The functions do_sputn, overflow and xsputn are Do_sputn, Overflow and Xsputn; the default of the
parameter of overflow is -1, the value of EOF, and a char pointer is a PAnsiChar. Do_sputn is abstract, Xsputn is
protected and calls Do_sputn, and the stream buffer calls Xsputn for every block that is written to it.

The members bufSize, buffer, queFront, queBack and bufDec of TTerminal are protected and are BufSize, Buffer, QueFront,
QueBack and BufDec. The static function findLfBackwards of ttprvlns.cpp is FindLfBackwards inside the unit. CopyLine is the part of draw that copies the bytes of a line, which
may cross the end of the buffer, into a TLineChunk, the array s of 256 characters, and TrimChunk is the static function
discardPossiblyTruncatedCharsAtEnd; MaxCharSize is maxCharSize of config.h and LargestBuffer is the limit 32000 of the
constructor. LeastOf and GreatestOf are min and max inside the unit. These five are not visible outside the unit
except TLineChunk, which is the type of the parameters of the two private members. The members read, write, build and
streamableName are not translated. A negative count of Do_sputn is taken as 0.

## Added by the translation of TvSurface

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TSurfaceView.PutRows
added: TSurfaceView.ShowSurface
added: SurfaceViewPalette
added: NotBelowZero

TDrawSurface and TSurfaceView keep their names. The members dataLength and data of TDrawSurface are the private fields
DataLength and Data, and size, surface and delta are the public fields Size, Surface and Delta. The constructors are
the two overloads of Create. The functions at have no reference result in Pascal, so At gives a PScreenCell, the
address of the cell, and S.At(Y, X)^ stands for the reference; the const overload has no counterpart. The surface that
a TSurfaceView holds is a TDrawSurface, and the default of the constructor argument is nil. A memory failure of Resize
raises the exception of the run-time library, where the C++ calls abort.

The part of draw that writes rows straight from the surface is PutRows, and the part that draws a surface is
ShowSurface; both are private. The static function fillWithSpaces is FillWithSpaces inside the unit. NotBelowZero is
max(v, 0). The palette of the static variable of getPalette is SurfaceViewPalette, made from cpSurfaceView when the
unit starts and released when it ends; cpSurfaceView keeps its name and is inside the unit. The members read, write,
build and streamableName are not translated.

## Added by the translation of TvVtKeys

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TVtKey
added: TVtModifier
added: TVtModifiers
added: TVtMouseTracking
added: TVtMouseEncoding
added: TVtInputModes
added: TVtMouseState
added: DefaultInputModes
added: NewMouseState
added: KeyBytes
added: UnicharBytes
added: ProcessPaste
added: ProcessKeypad
added: ProcessFocus
added: FunctionIndex
added: ModifierParam
added: CursorFinal
added: PfFinal
added: TildeNumber
added: LetterSequence
added: TildeSequence
added: ControlCharKey
added: ControlOf
added: Utf8Text
added: ModifierBits
added: HeldButton
added: AppendNumber
added: MouseReport
added: MouseMoved
added: MouseButton
added: KeypadLetter

The unit is the conversion of the input events in vtermemu.cc. The namespace vtermemu is not a prefix, and the
functions convKey, convMod, convMouse, processKey, processMouse and wheelToArrow are ConvKey, ConvMod, ConvMouse,
ProcessKey, ProcessMouse and WheelToArrow, visible outside the unit. The enumerator mouseWheelScrollLines of
VTermEmulator is the constant mouseWheelScrollLines. The functions of the emulation library that the C++ calls at the
end of these functions (keyboard unichar, keyboard key, mouse move and mouse button) are not part of the sources; they
give bytes here, and the routines of the unit return the bytes as an AnsiString instead of writing them to the client.

TVtKey stands for VTermKey: the keys of the table keys (the values VTERM_KEY_ENTER to VTERM_KEY_FUNCTION(12)) are
vkEnter, vkTab, vkBackspace, vkEscape, vkUp, vkDown, vkLeft, vkRight, vkIns, vkDel, vkHome, vkEnd, vkPageUp, vkPageDown
and vkF1 to vkF12, and VTERM_KEY_NONE is vkNone. TVtModifiers stands for VTermModifier, a set of vmShift, vmAlt and
vmCtrl. The value of each key is the scan code of its Turbo Vision key code, so ConvKey takes the high byte of the code
when the low byte is zero (cursor, editing and function keys) and for kbEnter, kbTab, kbBack and kbEsc, and the table
modifiers is the three tests of ConvMod. FunctionIndex gives the number of a function key. The call
vterm_keyboard_key is KeyBytes and vterm_keyboard_unichar is UnicharBytes. ModifierParam is the second parameter of a
key with modifiers (1 plus 1 for Shift, 2 for Alt and 4 for Control), CursorFinal, PfFinal and TildeNumber give the
final character of the cursor keys, the final character of F1 to F4 and the number before the tilde of the editing
keys and of F5 to F12, LetterSequence and TildeSequence build the two forms of sequence, and ControlCharKey builds the
keys that are one control character. ControlOf is the control character that Control gives to a character.
Utf8Text is the UTF-8 text of a code point.

TVtInputModes is the record of the modes of the client that change the bytes: the cursor keys and keypad application
modes (DECCKM and DECKPAM), the mouse tracking level (TVtMouseTracking: none, 9, 1000, 1002, 1003), the encoding of
the mouse position (TVtMouseEncoding: default, 1005, 1006), bracketed paste (2004) and focus reporting (1004).
DefaultInputModes gives all of them off. TVtMouseState holds what the emulation library keeps between two mouse
calls: the last cell (Col and Row, -1 before the first event) and the buttons that are held (bit 0 for the left, 1 for
the middle and 2 for the right button); NewMouseState gives the first state, and ProcessMouse takes it as a var
parameter. vterm_mouse_move is MouseMoved and vterm_mouse_button is MouseButton; MouseReport builds the report, with
AppendNumber for a number of the old encodings (the value plus 32, one byte up to 223 and two UTF-8 bytes up to 2015;
a report that cannot be encoded is empty), ModifierBits gives 4, 8 and 16 for Shift, Alt and Control, and HeldButton
gives the held button of the lowest number. A release in ProcessMouse, whose event has no button, lets go of the held
button of the lowest number. ProcessPaste is the text of a paste with the brackets of mode 2004 when it is set,
ProcessFocus is the report of focus in and out when mode 1004 is set, and ProcessKeypad is a character of the numeric
keypad, which is the SS3 sequence of the character in application mode; KeypadLetter gives its final character.

## Added by the translation of TvVtScreen

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TVtScreen
added: TVtScreen.SetPenColors
added: TVtScreen.SetPenAttrs
added: TVtScreen.ResetPen
added: TVtScreen.PutChar
added: TVtScreen.PutText
added: TVtScreen.LineFeed
added: TVtScreen.ReverseIndex
added: TVtScreen.CarriageReturn
added: TVtScreen.Backspace
added: TVtScreen.Tab
added: TVtScreen.BackTab
added: TVtScreen.SetTabStop
added: TVtScreen.ClearTabStop
added: TVtScreen.ClearAllTabStops
added: TVtScreen.EraseInLine
added: TVtScreen.EraseInDisplay
added: TVtScreen.EraseChars
added: TVtScreen.InsertChars
added: TVtScreen.DeleteChars
added: TVtScreen.InsertLines
added: TVtScreen.DeleteLines
added: TVtScreen.ScrollUp
added: TVtScreen.ScrollDown
added: TVtScreen.SetScrollRegion
added: TVtScreen.MoveTo
added: TVtScreen.MoveBy
added: TVtScreen.SaveCursor
added: TVtScreen.RestoreCursor
added: TVtScreen.SetCursorVisible
added: TVtScreen.SetCursorBlink
added: TVtScreen.EnableAltScreen
added: TVtScreen.Resize
added: TVtScreen.GetCell
added: TVtScreen.LineContinues
added: TVtScreen.Cols
added: TVtScreen.Rows
added: TVtScreen.CursorX
added: TVtScreen.CursorY
added: TVtScreen.WrapPending
added: TVtScreen.AutoWrap
added: TVtScreen.CursorVisible
added: TVtScreen.CursorBlink
added: TVtScreen.MouseEnabled
added: TVtScreen.AltScreen
added: TVtScreen.TopMargin
added: TVtScreen.BottomMargin
added: TVtScreen.History
added: TVtScreen.BlankCell
added: TVtScreen.MakeBlankRow
added: TVtScreen.NewGrid
added: TVtScreen.RowFromLine
added: TVtScreen.Damage
added: TVtScreen.DamageAll
added: TVtScreen.ResetTabs
added: TVtScreen.ReleasePartner
added: TVtScreen.ClearSpan
added: TVtScreen.RepairRow
added: TVtScreen.PushRowToHistory
added: TVtScreen.ShiftLines
added: TVtScreen.WrapLine
added: TVtScreen.AppendMark
added: TVtScreen.AdjustGridRows
added: TVtScreen.AdjustGridCols
added: Scrollback.PopLine
added: Scrollback.LineAt
added: Scrollback.Clear
added: Scrollback.SlotOf
added: TVtColorKind
added: TVtColor
added: TVtAttr
added: TVtAttrs
added: TVtCell
added: TVtCellArray
added: TVtRow
added: TVtRowArray
added: TVtLine
added: PVtLine
added: VtMaxChars
added: VtWideTrail
added: DefaultColor
added: IndexedColor
added: RgbColor
added: DefaultCell
added: TCellRow
added: ToTColor
added: LoadRow
added: StoreRow
added: IsWideTrail
added: IsWideLead
added: RowIsBlank

The libvterm library that the C++ emulator uses for the grid is not a source, so the class TVtScreen holds the grid, the
cursor and the control functions that a terminal needs, and the cell type TVtCell stands for VTermScreenCell. A cell has
up to VtMaxChars code points (chars), a width, foreground and background colors (TVtColor: default, a palette index or
RGB) and the attributes of the set TVtAttrs. The first code point is 0 for an erased cell and VtWideTrail, the value
(uint32_t) -1, for the second cell of a double-width character. The struct Scrollback is the class Scrollback with the
public field Offset and the constant maxSize; its lines are TVtLine values (Line of the C++, with Cells, Cols and
Continuation) held in a ring, and LineAt gives the address of the line with a given index, which stands for the access
lines[i] of the deque. PopLine takes the newest line away, which Resize uses to bring lines back to a screen that grows,
and Clear empties the history, which EraseInDisplay with the mode 3 uses.

The members updateState, handleScrollbackWheel and copySelection are UpdateState, HandleScrollbackWheel and
CopySelection; updateSurface, drawScrollbackLine, extractScrollbackLineText and extractTerminalLineText are private
members, and drawLine, convCell, convAttr and extractCellText are routines of the unit that are not visible outside it.
The C++ state that updateState compares with (scrollOffset, visibleScrollLines and scrollOverflowed of LocalState) are
the private fields FShownOffset, FShownLines and FOverflowed, the cursor and mouse state are fields of the class, and the
damage of the rows is the private array FDamage of RowRange. The title is not part of this unit. The function
copySelection gives the text as the result, where the C++ passes it to TClipboard::setText. The constant
mouseWheelScrollLines keeps its name and is a constant of the unit. A TPoint of the C++ state, such as the size, is read
through Cols and Rows. The pen, the cursor, the margins, the tab stops and the saved cursor are private fields; the pen
gives the colors and attributes of the cells that PutChar writes, and the cells that erasing and scrolling make have the
background of the pen and the default foreground.

A cell that stands for an erased cell has no code point, and ConvCell gives the screen cell of it the text of one NUL
byte without calling the text routines, because CharWidth of TvUtf8 is -1 for the code point 0. A history line that is
shorter than the surface is completed with such cells, as the C++ completes it with the default cell.
