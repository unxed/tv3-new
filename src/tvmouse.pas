{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (THWMouse, TMouse), source/tvision/tmouse.cpp,
  include/tvision/hardware.h (getButtonCount, cursorOn, cursorOff)
  See COPYRIGHT.magiblot.

  Only the branch of the files for the flat memory model is translated; the code for the mouse interrupt of
  DOS (the calls of interrupt $33, registerHandler, handlerInstalled) is left out.

  The calls of THardwareInfo (getButtonCount, cursorOn, cursorOff) go to TEventQueue.Backend of TvSys, which
  provides them as GetButtonCount, CursorOn and CursorOff. The members of THWMouse that are protected in the
  C++ are protected here and are public in TMouse. }
unit TvMouse;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvEvents;

type
  THWMouse = class
  protected
    class var ButtonCount: Byte;
    constructor Create;
    class procedure Show; static;
    class procedure Hide; static;
    class procedure SetRange(RX, RY: Word); static;
    class procedure GetEvent(var Me: TMouseEventType); static;
    class function Present: Boolean; static;
    class procedure Suspend; static;
    class procedure Resume; static;
    class procedure Inhibit; static;
  private
    class var NoMouse: Boolean;
  public
    destructor Destroy; override;
  end;

  TMouse = class(THWMouse)
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Show; static;
    class procedure Hide; static;
    class procedure SetRange(RX, RY: Word); static;
    class procedure GetEvent(var Me: TMouseEventType); static;
    class function Present: Boolean; static;
    class procedure Suspend; static;
    class procedure Resume; static;
  end;

implementation

uses
  TvSys;

{ THWMouse }

constructor THWMouse.Create;
begin
  inherited Create;
  Resume;
end;

destructor THWMouse.Destroy;
begin
  Suspend;
  inherited Destroy;
end;

class procedure THWMouse.Resume;
begin
  ButtonCount := Byte(TEventQueue.Backend.GetButtonCount);
  Show;
end;

class procedure THWMouse.Suspend;
begin
  Hide;
  ButtonCount := 0;
end;

class procedure THWMouse.Show;
begin
  TEventQueue.Backend.CursorOn;
end;

class procedure THWMouse.Hide;
begin
  TEventQueue.Backend.CursorOff;
end;

{ In the flat branch there is no range to set. }
class procedure THWMouse.SetRange(RX, RY: Word);
begin
end;

class procedure THWMouse.GetEvent(var Me: TMouseEventType);
begin
  Me.Buttons := 0;
  Me.Wheel := 0;
  Me.Where.X := 0;
  Me.Where.Y := 0;
  Me.EventFlags := 0;
end;

class function THWMouse.Present: Boolean;
begin
  Result := ButtonCount <> 0;
end;

class procedure THWMouse.Inhibit;
begin
  NoMouse := True;
end;

{ TMouse }

constructor TMouse.Create;
begin
  inherited Create;
end;

destructor TMouse.Destroy;
begin
  inherited Destroy;
end;

class procedure TMouse.Show;
begin
  THWMouse.Show;
end;

class procedure TMouse.Hide;
begin
  THWMouse.Hide;
end;

class procedure TMouse.SetRange(RX, RY: Word);
begin
  THWMouse.SetRange(RX, RY);
end;

class procedure TMouse.GetEvent(var Me: TMouseEventType);
begin
  THWMouse.GetEvent(Me);
end;

class function TMouse.Present: Boolean;
begin
  Result := THWMouse.Present;
end;

class procedure TMouse.Suspend;
begin
  THWMouse.Suspend;
end;

class procedure TMouse.Resume;
begin
  THWMouse.Resume;
end;

end.
