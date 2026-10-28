{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (TEventQueue), source/tvision/tevent.cpp,
  include/tvision/internal/events.h, source/platform/events.cpp,
  include/tvision/hardware.h (getButtonCount, cursorOn, cursorOff)
  See COPYRIGHT.magiblot. }
program t_evqueue;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  SysUtils, TvGeom, TvKeys, TvEvents, TvSys;

{$I testlib.inc}

function MouseEv(AX, AY: Integer; AButtons, AWheel: Byte): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evMouseMove;
  Result.Mouse.Where.X := AX;
  Result.Mouse.Where.Y := AY;
  Result.Mouse.Buttons := AButtons;
  Result.Mouse.Wheel := AWheel;
end;

function CommandEv(ACommand: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evCommand;
  Result.Message.Command := ACommand;
end;

{ A key that is not a text: the key code only. }
function KeyEv(ACode: Word): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := ACode;
end;

{ A key with the text Ch. }
function TextEv(Ch: Char): TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := evKeyDown;
  Result.KeyDown.KeyCode := Ord(Ch);
  Result.KeyDown.Text[0] := Ord(Ch);
  Result.KeyDown.TextLength := 1;
end;

function NextKey: TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := $7777;
  TEventQueue.GetKeyEvent(Result);
end;

function NextMouse: TEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.What := $7777;
  TEventQueue.GetMouseEvent(Result);
end;

function Elapsed(Since: Int64): Int64;
begin
  Result := Int64(GetTickCount64) - Since;
end;

var
  B: TEventBackend;
  Q: TEventQueue;
  Ev: TEvent;
  Start: Int64;
  I: Integer;
  Ok: Boolean;
  Pasted: string;

begin
  B := TEventBackend.Create;
  TEventQueue.Backend := B;
  TEventQueue.DoubleDelay := 100;
  Q := TEventQueue.Create;

  { the mouse calls of the hardware: no buttons, and the cursor calls do nothing }
  Check(B.GetButtonCount = 0, 'the base backend has no mouse buttons');
  B.CursorOn;
  B.CursorOff;
  Check(NextMouse.What = evNothing, 'the cursor calls of the base backend change no input');

  { keys come out in the order they went in }
  B.Feed(KeyEv(kbF1));
  B.Feed(KeyEv(kbF2));
  B.Feed(KeyEv(kbEsc));
  Ev := NextKey;
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbF1), 'first key is F1');
  Check((Ev.KeyDown.ControlKeyState and kbPaste) = 0, 'F1 is not a paste');
  Ev := NextKey;
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbF2), 'second key is F2');
  Ev := NextKey;
  Check((Ev.What = evKeyDown) and (Ev.KeyDown.KeyCode = kbEsc), 'third key is Esc');
  Ev := NextKey;
  Check(Ev.What = evNothing, 'no key left');

  { text keys are plain keys, in order, without the paste mark }
  for I := 0 to 3 do
    B.Feed(TextEv(Chr(Ord('w') + I)));
  Pasted := '';
  Ok := True;
  for I := 0 to 3 do
  begin
    Ev := NextKey;
    Ok := Ok and (Ev.What = evKeyDown) and ((Ev.KeyDown.ControlKeyState and kbPaste) = 0) and
      (Ev.KeyDown.TextLength = 1);
    Pasted := Pasted + Chr(Ev.KeyDown.Text[0]);
  end;
  Check(Ok, 'text keys carry no paste mark');
  Check(Pasted = 'wxyz', 'text keys keep their order');
  Check(NextKey.What = evNothing, 'text keys used up');


  { a text for the paste: CR and CRLF become LF }
  TEventQueue.SetPasteText('a'#13#10'b'#13'c');
  Pasted := '';
  repeat
    Ev := NextKey;
    if Ev.What = evKeyDown then
    begin
      Check((Ev.KeyDown.ControlKeyState and kbPaste) <> 0, 'a pasted key is marked');
      Pasted := Pasted + Chr(Ev.KeyDown.Text[0]);
    end;
  until Ev.What = evNothing;
  Check(Pasted = 'a'#10'b'#10'c', 'line ends of a pasted text');

  { the wait: nothing to find. The first wait ends at once on the wake-up that Feed left. }
  TEventQueue.WaitForEvents(0);
  Start := Int64(GetTickCount64);
  TEventQueue.WaitForEvents(120);
  Check((Elapsed(Start) >= 100) and (Elapsed(Start) < 3000), 'a wait without input lasts about the time-out');
  Start := Int64(GetTickCount64);
  TEventQueue.WaitForEvents(0);
  Check(Elapsed(Start) < 1000, 'a wait of zero returns at once');

  { the wait: input is there }
  B.Feed(KeyEv(kbF1));
  Start := Int64(GetTickCount64);
  TEventQueue.WaitForEvents(5000);
  Check(Elapsed(Start) < 2000, 'a wait with input returns at once');
  Check(NextKey.KeyDown.KeyCode = kbF1, 'the key is still there after the wait');

  { the wait: a paste text is there }
  TEventQueue.SetPasteText('');
  Start := Int64(GetTickCount64);
  TEventQueue.WaitForEvents(5000);
  Check(Elapsed(Start) < 2000, 'a wait with a paste text, even empty, returns at once');
  Check(NextKey.What = evNothing, 'an empty paste text gives no key');

  { mouse events }
  Check(NextMouse.What = evNothing, 'no mouse event yet');
  B.Feed(MouseEv(3, 4, 0, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseMove) and (Ev.Mouse.Where.X = 3) and (Ev.Mouse.Where.Y = 4), 'move');
  Check((Ev.Mouse.EventFlags and meMouseMoved) <> 0, 'move flag');
  B.Feed(MouseEv(3, 4, mbLeftButton, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseDown) and (Ev.Mouse.Buttons = mbLeftButton), 'down');
  Check(Ev.Mouse.EventFlags = 0, 'first down is no double click');
  B.Feed(MouseEv(3, 4, 0, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseUp) and (Ev.Mouse.Buttons = mbLeftButton), 'up keeps the buttons that were released');
  B.Feed(MouseEv(3, 4, mbLeftButton, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseDown) and ((Ev.Mouse.EventFlags and meDoubleClick) <> 0), 'double click');
  B.Feed(MouseEv(3, 4, 0, 0));
  Ev := NextMouse;
  Check(Ev.What = evMouseUp, 'up after the double click');
  B.Feed(MouseEv(3, 4, mbLeftButton, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseDown) and ((Ev.Mouse.EventFlags and meTripleClick) <> 0) and
    ((Ev.Mouse.EventFlags and meDoubleClick) = 0), 'triple click');
  B.Feed(MouseEv(7, 6, mbLeftButton, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseMove) and (Ev.Mouse.Where.X = 7) and (Ev.Mouse.Buttons = mbLeftButton), 'drag');
  B.Feed(MouseEv(9, 9, 0, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseMove) and (Ev.Mouse.Where.X = 9) and (Ev.Mouse.Where.Y = 9) and
    (Ev.Mouse.Buttons = mbLeftButton), 'release elsewhere moves first');
  Ev := NextMouse;
  Check((Ev.What = evMouseUp) and (Ev.Mouse.Where.X = 9) and (Ev.Mouse.Buttons = mbLeftButton),
    'then the pending up comes without new input');
  Check(NextMouse.What = evNothing, 'no mouse event left');
  B.Feed(MouseEv(9, 9, 0, mwUp));
  Ev := NextMouse;
  Check((Ev.What = evMouseWheel) and (Ev.Mouse.Wheel = mwUp), 'wheel');
  TEventQueue.MouseReverse := True;
  B.Feed(MouseEv(9, 9, mbLeftButton, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseDown) and (Ev.Mouse.Buttons = mbRightButton), 'reversed buttons');
  B.Feed(MouseEv(9, 9, 0, 0));
  Ev := NextMouse;
  Check((Ev.What = evMouseUp) and (Ev.Mouse.Buttons = mbRightButton), 'reversed up');
  TEventQueue.MouseReverse := False;
  Check(NextMouse.What = evNothing, 'mouse queue empty at the end');

  { posted events come out in the order they were posted }
  Check(not TEventQueue.HasPostedEvents, 'nothing is posted at first');
  Check(not TEventQueue.GetPostedEvent(Ev), 'no posted event to take');
  TEventQueue.PostEvent(CommandEv(1));
  TEventQueue.PostEvent(CommandEv(2));
  TEventQueue.PostEvent(CommandEv(3));
  Check(TEventQueue.HasPostedEvents, 'posted events are there');
  Start := Int64(GetTickCount64);
  TEventQueue.WaitForEvents(5000);
  Check(Elapsed(Start) < 2000, 'a wait with posted events returns at once');
  Ok := TEventQueue.GetPostedEvent(Ev) and (Ev.What = evCommand) and (Ev.Message.Command = 1);
  Check(Ok, 'first posted event');
  Ok := TEventQueue.GetPostedEvent(Ev) and (Ev.What = evCommand) and (Ev.Message.Command = 2);
  Check(Ok, 'second posted event');
  TEventQueue.PostEvent(CommandEv(4));
  Ok := TEventQueue.GetPostedEvent(Ev) and (Ev.Message.Command = 3);
  Check(Ok, 'third posted event');
  Ok := TEventQueue.GetPostedEvent(Ev) and (Ev.Message.Command = 4);
  Check(Ok, 'an event posted later comes last');
  Check(not TEventQueue.HasPostedEvents, 'posted events used up');
  for I := 1 to 40 do
    TEventQueue.PostEvent(CommandEv(I));
  Ok := True;
  for I := 1 to 40 do
    Ok := Ok and TEventQueue.GetPostedEvent(Ev) and (Ev.Message.Command = I);
  Check(Ok, 'many posted events keep their order');

  Q.Free;
  TEventQueue.Backend := nil;
  B.Free;
  Done;
end.
