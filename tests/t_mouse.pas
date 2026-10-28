{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (THWMouse, TMouse), source/tvision/tmouse.cpp,
  include/tvision/hardware.h (getButtonCount, cursorOn, cursorOff)
  See COPYRIGHT.magiblot.

  The input backend is a TEventBackend that reports a number of buttons and writes a journal of its cursor
  calls: 'on;' for CursorOn and 'off;' for CursorOff. }
program t_mouse;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  SysUtils, TvGeom, TvEvents, TvSys, TvMouse;

{$I testlib.inc}

type
  TFakeInput = class(TEventBackend)
  public
    Buttons: Cardinal;
    function GetButtonCount: Cardinal; override;
    procedure CursorOn; override;
    procedure CursorOff; override;
  end;

  { A mouse that shows the protected count of buttons. }
  TProbe = class(TMouse)
  public
    function Count: Byte;
  end;

var
  Journal: string;
  Fake: TFakeInput;
  Saved: TEventBackend;
  M: TProbe;
  Me: TMouseEventType;

function TFakeInput.GetButtonCount: Cardinal;
begin
  Result := Buttons;
end;

procedure TFakeInput.CursorOn;
begin
  Journal := Journal + 'on;';
end;

procedure TFakeInput.CursorOff;
begin
  Journal := Journal + 'off;';
end;

function TProbe.Count: Byte;
begin
  Result := ButtonCount;
end;

begin
  Fake := TFakeInput.Create;
  Fake.Buttons := 3;
  Saved := TEventQueue.Backend;
  TEventQueue.Backend := Fake;

  { show and hide are the calls cursorOn and cursorOff, and change no count }
  Check(not TMouse.Present, 'there is no mouse before the first resume');
  Journal := '';
  TMouse.Show;
  Check(Journal = 'on;', 'Show calls cursorOn');
  TMouse.Hide;
  Check(Journal = 'on;off;', 'Hide calls cursorOff');
  Check(not TMouse.Present, 'Show and Hide do not give the mouse a button');

  { the constructor resumes: it reads the buttons and shows the cursor }
  Journal := '';
  M := TProbe.Create;
  Check(Journal = 'on;', 'the constructor reads the buttons and shows the cursor');
  Check(TMouse.Present and (M.Count = 3), 'the count of buttons is the one of the hardware');

  { SetRange has no effect in the flat branch }
  Journal := '';
  TMouse.SetRange(79, 24);
  Check((Journal = '') and (M.Count = 3), 'SetRange does nothing');

  { suspend hides the cursor and clears the count }
  TMouse.Suspend;
  Check(Journal = 'off;', 'Suspend hides the cursor');
  Check((not TMouse.Present) and (M.Count = 0), 'Suspend clears the count of buttons');

  { resume reads the count again, also when it changed }
  Journal := '';
  Fake.Buttons := 2;
  TMouse.Resume;
  Check(Journal = 'on;', 'Resume shows the cursor');
  Check(TMouse.Present and (M.Count = 2), 'Resume reads the count of buttons');

  { the count is an unsigned char: 300 is 44 }
  Fake.Buttons := 300;
  TMouse.Resume;
  Check(M.Count = 44, 'the count of buttons is cut to a byte');
  Fake.Buttons := 256;
  TMouse.Resume;
  Check((M.Count = 0) and (not TMouse.Present), 'a count of 256 is 0, so there is no mouse');

  { the state of the mouse in the flat branch: all zero, and the control key state is left alone }
  FillChar(Me, SizeOf(Me), 0);
  Me.Buttons := 7;
  Me.Wheel := 3;
  Me.Where.X := 9;
  Me.Where.Y := 11;
  Me.EventFlags := 5;
  Me.ControlKeyState := 77;
  TMouse.GetEvent(Me);
  Check((Me.Buttons = 0) and (Me.Wheel = 0) and (Me.Where.X = 0) and (Me.Where.Y = 0) and (Me.EventFlags = 0),
    'GetEvent gives no buttons, no wheel, the origin and no flags');
  Check(Me.ControlKeyState = 77, 'GetEvent leaves the control key state');

  { the destructor suspends }
  Fake.Buttons := 3;
  TMouse.Resume;
  Journal := '';
  M.Free;
  Check(Journal = 'off;', 'the destructor hides the cursor');
  Check(not TMouse.Present, 'the destructor clears the count of buttons');

  TEventQueue.Backend := Saved;
  Fake.Free;
  Done;
end.
