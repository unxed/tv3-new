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

## Added by the translation of TvColorSel

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TColorSel
added: PColorIndex
added: TColorSelector.TrackMouse
added: TColorSelector.StepByKey
added: TColorDialog.ApplyData
added: GridColumns
added: AttrOfBios
added: BiosOfAttr
added: TextOfBlock
added: NameText
added: PayloadOf
added: Notify
added: GroupAtPosition
added: ItemAtPosition
added: CountItems
added: CountGroups
added: ButtonValue
added: IsColorSetEvent
added: MonoColorChars
added: TableIndex

ButtonValue gives the attribute value of a button of the mono selector, which is the element of monoColors. MonoColorChars
holds the five values of monoColors as characters, and the unit copies them into the variable MonoColors when it starts,
using the loop variable TableIndex. IsColorSetEvent tells whether an event is the broadcast cmColorSet, which the
selectors test in handleEvent. These four are inside the unit and are not visible outside it.

TColorSel is the enumeration ColorSel that is nested in TColorSelector, with the values csBackground and csForeground,
and PColorIndex is the pointer to a TColorIndex, which getIndexes and setIndexes take by reference as a var parameter.
TColorIndex is a record with the fields GroupIndex, ColorSize and ColorIndex; a block of it holds only ColorSize bytes
of ColorIndex, as the C++ allocates it. The block that the dialog keeps between two calls is the variable
ColorIndexes of the unit, which is not visible outside it and which the unit releases when it ends. The table
monoColors is MonoColors, and the width of the grid of a color selector, the local constant width of handleEvent, is
GridColumns; both are inside the unit.

The members of TColorSelector that handleEvent holds in one body are split: TrackMouse is the loop of the case
evMouseDown, and StepByKey is the switch of the arrow keys, which tells whether the key is an arrow (the `return` of
the default branch is its answer False). Both are private. ApplyData is the body of TColorDialog.SetData: the
constructor of the C++ calls the setData of its own class, so the constructor calls ApplyData and SetData calls it too,
and a class derived in Pascal does not take part in the call of the constructor. ApplyData is private.

Notify sends a message through MessageHook and does nothing while the hook is nil. PayloadOf turns a number into the
pointer that a message carries, as the cast (void *)(size_t) does. AttrOfBios makes a TColorAttr from a BIOS value, and
BiosOfAttr gives the BIOS value of a TColorAttr, which is the conversion of the C++ to uchar. TextOfBlock reads a block
of characters that may be nil, and NameText does so and cuts the text to the largest length, as strnzcpy does with the
size that is one more. GroupAtPosition and ItemAtPosition are the loops `while( cur && n-- > 0 )` that find the group or
the item at a position, and give the first one for a position below 1 and nil past the end. CountItems and CountGroups
are the loops that count a chain. These helpers and GridColumns are inside the unit and are not visible outside it.

The members name of TColorItem and TColorGroup are blocks of characters with a terminating zero that the object owns,
and the constructors take a string. The field index of TColorGroup, which the constructor of the C++ leaves unset,
starts at 0. The members pal, display, groups, forLabel, forSel, bakLabel, bakSel, monoLabel, monoSel and groupIndex of
TColorDialog are Pal, Display, Groups, ForLabel, ForSel, BakLabel, BakSel, MonoLabel, MonoSel and GroupIndex. The
argument of GetData and SetData is a Pointer to a TPalette object, which the dialog copies with Assign, as the C++
copies with the operator =. The static functions freeItems and freeGroups are FreeItems and FreeGroups inside the
unit, and the operators + that chain items and groups are global operators with the same operand types. The texts and
the table icon of tvtext1.cpp are class variables, which the unit sets to their C++ values when it starts: Icon of
TColorSelector, Button, Normal, Highlight, Underline and Inverse of TMonoSelector, and Colors, GroupText, ItemText,
ForText, BakText, TextText, ColorText, OkText and CancelText of TColorDialog.
