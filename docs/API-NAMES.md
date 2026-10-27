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

## Added by the translation of TvWindow

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: TCreateFrameFunc
added: TWindow.Create with CFrame
added: TWindow.Setup

TCreateFrameFunc is the type of the function pointer `TFrame *(*)( TRect )` that TWindowInit holds. A Pascal class has
one parent, so TWindowInit, which the C++ inherits virtually beside TGroup, is the class between TGroup and TWindow;
its constructor takes the bounds of the group and the function. The constructor of TWindow with three parameters
passes TWindow.InitFrame, which is what the C++ constructor does. A class that derives from TWindow and has a frame
of its own calls the constructor of TWindow with CFrame, which stands for the initializer of TWindowInit that the
most derived class gives in the C++. TWindow.Setup is a private routine that holds the body of the constructor of
TWindow, so that both constructors share it.

The tables of TFrame (initFrame, frameChars, closeIcon, zoomIcon, unZoomIcon, dragIcon, dragLeftIcon) and of
TScrollBar (vChars, hChars) are the class variables InitFrame, FrameChars, CloseIcon, ZoomIcon, UnZoomIcon, DragIcon and
DragLeftIcon of TFrame and VChars and HChars of TScrollBar. They get their C++ values, in code page 437, when the unit
starts, and a program may change them. The icons are strings in the notation of a command string, with tildes. The
palettes cpBlueWindow, cpCyanWindow and cpGrayWindow are constants of the unit; cpFrame, cpScrollBar and cpScroller are
private to it. The message() calls of TScrollBar and TWindow go through MessageHook of TvViews. The private members
frameLine and dragWindow of TFrame and getPartCode of TScrollBar are private here as well.

## Added by the translation of TvDialog

The names below have no counterpart in the C++ and are listed one per line, as "added: <name>".

added: THotKeyFunc
added: HotKeyHook
added: TButton.StartAnimation
added: TButton.TrackMouse
added: TButton.HandleKeyDown
added: TButton.HandleBroadcast
added: TButton.FaceRect

THotKeyFunc is the type of a function that takes the text of a label or a button and returns its hot key, and
HotKeyHook stands for the function hotKey, which has no unit yet. While HotKeyHook is nil no text has a hot key
(the result is #0), so a label and a button answer to no letter and to no Alt key. TButton.StartAnimation is a
private routine that holds the two actions that the C++ repeats in the key and the cmDefault branches of
TButton::handleEvent: draw the button pressed down and set the timer of 100 milliseconds when none runs; the caller
then clears the event. TButton.TrackMouse, TButton.HandleKeyDown and TButton.HandleBroadcast are private routines that hold the mouse, key
and broadcast branches of TButton::handleEvent, and TButton.FaceRect is the private function that gives the
click area of the button. The message() calls of TButton go through MessageHook of TvViews.

The tables of tvtext1.cpp that belong to these classes are variables that get their C++ values, in code page 437,
when the unit starts, and a program may change them: shadows and markers of TButton are the class variables Shadows
and Markers, and specialChars is the variable SpecialChars. The macros cpGrayDialog, cpBlueDialog, cpCyanDialog and
cpDialog are constants of the unit, and the palettes of the other classes (cpStaticText, cpLabel, cpButton) are
private to it. The constants cmGrabDefault and cmReleaseDefault, which tbutton.cpp keeps to itself, and the
button flags and cmRecordHistory of dialogs.h are constants of the unit.

The text of a TStaticText is a block of characters with a terminating zero, as in the C++, and getText takes a
pointer to a buffer of 256 characters. The variadic setText of TParamText takes a format string and an array of
const, and its format is the one of FormatStr of TvUtil. A TParamText has no text of the base class, so its Text is
nil. The members of the C++ that are declared and never defined (pressButton and getActiveRect of TButton) are not
translated. TDialog.Valid calls the Valid of the class above it where the C++ calls TGroup::valid.
