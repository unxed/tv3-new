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

added: MessageHook
added: TMessageFunc
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

TMessageFunc, TCaretPositionProc and TScreenWriteProc are the procedural types of the hooks that stand for parts of
the C++ that have no unit yet. MessageHook stands for the function message, CaretPositionHook for
THardwareInfo::setCaretPosition and ScreenWriteHook for THardwareInfo::screenWrite. EventTimeoutMs is
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
added: TLowMemoryFunc
added: TSetCtrlBrkHandlerProc
added: LowMemoryHook
added: MouseHideHook
added: MouseShowHook
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
added: PassMessage
added: MemoryIsLow
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

TVoidProc, TLowMemoryFunc and TSetCtrlBrkHandlerProc are the procedural types of the hooks that stand for parts of the
C++ that no unit has yet and no input defines. LowMemoryHook stands for the function lowMemory, which validView asks
whether the memory is low; MouseHideHook and MouseShowHook stand for TMouse::hide and TMouse::show, which
setScreenMode calls; InitHistoryHook and DoneHistoryHook stand for initHistory and doneHistory, which the constructor
and the destructor of TApplication call; SetCtrlBrkHandlerHook stands for THardwareInfo::setCtrlBrkHandler, which
TSystemError.Resume and TSystemError.Suspend call with True and False. While a hook is nil it does nothing, and while
LowMemoryHook is nil the memory is never low. MessageHook of TvViews stands for message, as before. TvApp gives
TProgram.Application to the ApplicationHook of TvMenus when the unit starts. EventTimeoutMs of TvViews, which is
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
and DefaultBkgrnd are defined in files that are not among the sources of the unit, so the program sets them; they
start as an empty text and as the character 0. The flags ctrlBreakHit and saveCtrlBreak of TSystemError are the class
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
added: Notify
added: AnyBit

PListBoxRec is the pointer to a TListBoxRec, which GetData and SetData of TListBox take from the untyped pointer of
their argument. The names ListViewerPalette, ListMarkers, DividerCode, AutosPerStep, LowAttr, Notify and AnyBit are
inside the unit and are not visible outside it. ListViewerPalette is the palette that the static variable of
getPalette of tlstview.cpp holds, made from cpListViewer when the unit starts and released when it ends. ListMarkers
is the table specialChars of tvtext1.cpp, which TvDialog keeps for its own use. DividerCode is the character '\xB3'
that draw writes between two columns, and AutosPerStep is the local mouseAutosToSkip of handleEvent. LowAttr gives the
attribute that a conversion of the result of getColor to a TColorAttr gives, which is the low one of the pair. Notify
sends a message through MessageHook, as the function message does in the C++, and does nothing while the hook is nil.
AnyBit tells whether a flag of a mask is set, as the tests with & of the C++ do.

The members of TListViewer that handleEvent of the C++ holds in one body are split in three, one for each kind of
event: HandleMouseDown, HandleKeyDown and HandleBroadcast. DragTarget is the part of the mouse loop that gives the
item for a mouse outside the view, and it keeps the count of the automatic events; KeyTarget is the switch of the
key codes, and it tells whether the key moves the focus. ShowBarWhenLive is the repeated code of setState that shows
a scroll bar while the view is active and visible and hides it otherwise. These five are private.

The function getText has no buffer here: GetText returns the text as a string, and its second parameter is the
largest length of the text, which is the third parameter of the C++. In TListBox the text is the block of characters
of the item up to its terminating zero or up to that length. A nil item gives an empty text. The static member
emptyText of TListViewer is defined in a file that is not among the sources of the unit, so it is the class variable
EmptyText, which starts as an empty text and which the program sets. The member list of TListBox is the function
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

The texts errorMsg of the classes and validUnsignedChars and validSignedChars of TRangeValidator are defined in files
that are not among the sources of the unit, so they are the class variables ErrorMsg of TPXPictureValidator,
TFilterValidator and TStringLookupValidator, and ValidUnsignedChars and ValidSignedChars of TRangeValidator, which
start as empty texts and which the program sets. The errorMsg of TRangeValidator is RangeErrorMsg, because a class
variable of a derived class does not take the name of one of its base class. TStringCollection is not defined by a unit
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

added: TStrNZCopyFunc
added: StrNZCopyHook
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

TStrNZCopyFunc is the procedural type of the hook that stands for a part of the C++ that no unit has yet and no input
defines. StrNZCopyHook stands for the function strnzcpy, which THistory calls to put the chosen text into the line
with the limit maxLen + 1; it takes the text and that limit and gives the text that the buffer holds, and while it is
nil the line keeps its text (the line is still selected and drawn). The function strwidth is the width of TText of
TvUtf8, and ctrlToArrow is the function of TvKeys.

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
added: TSortedNewListProc
added: SortedListBoxNewListHook
added: TMakeDefaultProc
added: ChDirButtonDefaultHook
added: GetDisk
added: SendNotice
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

PSearchRec is the pointer type that stands for TSearchRec *. The entries of a directory are records that the
collections keep as pointers; the names of the entries are at most MaxNameLength characters, because the size
MAXFILE + MAXEXT - 1 comes from a header that is not among the translated sources. TSearchRec is the record of the
unit, not the one of SysUtils, which the unit names as SysUtils.TSearchRec when it searches a directory. The typed
members of the collections (at, firstThat and lastThat) return the typed pointer; the other members keep the pointer
of TvObjs, because a member that takes a different type of pointer cannot override a virtual member of the base. The
sorted collection of files and the collection of directories are not related by a base, so the sorted list box turns
the list of its base TListBox into a TSortedCollection by a typecast.

The source file of TSortedListBox is not among the translated sources. SortedListBoxNewListHook stands for its
newList, with the type TSortedNewListProc, and while it is nil the list is not given to the list box. Its handleEvent
is not translated, its virtual getKey is abstract, and its member searchPos is left out. ChDirButtonDefaultHook, with
the type TMakeDefaultProc, stands for the call chDirButton->makeDefault of the dialog TChDirDialog that owns a
TDirListBox, and it does nothing while it is nil. The text tooManyFiles is the class variable TooManyFiles of
TFileList, empty until the program sets it, and the warning is shown with MessageBox of TvMsgbox when the allocation
of an entry fails (EOutOfMemory is caught, as the C++ tests a null pointer).

The tables of TDirListBox (pathDir, firstDir, middleDir, lastDir, drives and graphics) are the class variables
PathDir, FirstDir, MiddleDir, LastDir, Drives and Graphics, which get the values of tvtext1.cpp, in code page 437,
when the unit starts. The paths that TDirListBox reads and builds use PathSep of TvPath as their separator, the
texts of the drives keep the backslash, and a search of a directory uses PathAllFiles for the mask "*.*". GetDisk
stands for getdisk and gives the disk C. SendNotice is the call of MessageHook, CompareNames is strcmp, FindSeparator
and FindLastSeparator are strchr and strrchr for the separator, BeginsWithDot is the test of the first character of
a name, FindCode is strchr of a character in a block, NewSearchRecord is the operator new of DirSearchRec and
CopyFoundEntry is its member readFf_blk. SearchKey is the static record of getKey, NoFileRecord is the static record
noFile of readDirectory, and CurrentDisk, IndentStep and DefaultParentTime are the values 'C', 2 and 0x210000 that the
C++ writes in its code. The routines validFileName, getCurDir, fexpand, squeeze and getHomeDir are not in this unit.

## Added by the translation of TvChDir

added: TGetCurDirFunc
added: GetCurDirHook
added: MaxPathLength
added: MakeChDirButtonDefault

TGetCurDirFunc is the procedural type of the hook that stands for a part of the C++ that no unit has yet and no input
defines. GetCurDirHook stands for the function getCurDir, which getCurrentDir of tchdrdlg.cpp calls; the hook gives
the directory with the two characters of a drive in front, as the C++ function writes it, and the dialog removes those
two characters. While the hook is nil the current directory is empty. The function strnzcpy is StrNZCopyHook of
TvHist, so while that hook is nil the input line of the dialog keeps its text. The functions fexpand and chdir are made
with PathExpand of TvPath and SetCurrentDir of SysUtils, as TvFiles makes the functions of the compatibility headers,
and setdisk is left out because the target has no drives.

MaxPathLength stands for MAXPATH, which a header outside the sources defines; its value 257 gives the input line a
limit of 255 characters, the longest text of a string of this library. MakeChDirButtonDefault is the routine that TvChDir
gives to ChDirButtonDefaultHook of TvFiles when the unit starts: it makes chDirButton of the TChDirDialog that owns the
list box the default button, or stops it from being so, and it does nothing when the list box has no such owner.

The texts changeDirTitle, dirNameText, dirTreeText, okText, chdirText, revertText, helpText, drivesText and invalidText
are not in the sources, so they are the class variables ChangeDirTitle, DirNameText, DirTreeText, OkText, ChdirText,
RevertText, HelpText, DrivesText and InvalidText of TChDirDialog, empty until the program sets them; DrivesText must
equal Drives of TDirListBox. The constants cdNormal, cdNoLoadDir and cdHelpButton keep their names. The members
dirInput, dirList, okButton and chDirButton are the protected members DirInput, DirList, OkButton and ChDirButton. The
separator that a directory gets in the change of directory is PathSep, and a change of directory with no list or with
no focused entry is not handled, where the C++ would use a null pointer.
