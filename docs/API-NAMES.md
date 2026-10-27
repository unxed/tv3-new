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
