{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (TClipboard), source/tvision/tclipbrd.cpp
  See COPYRIGHT.magiblot.

  The platform clipboard (THardwareInfo::setClipboardText and THardwareInfo::requestClipboardText) is not part
  of the C++ sources of this unit. It is a hook: the methods of TClipboardBackend, which do nothing and report
  failure. The program sets TClipboard.Backend to a backend that talks to a system clipboard. The C++ asks the
  platform clipboard only when __FLAT__ is defined; here the backend is always asked. The length of the stored
  text is the length of the string, so there is no separate member for it. }
unit TvClip;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvEvents;

type
  { The system clipboard, as TClipboard uses it. The base class has no clipboard: both routines report failure,
    so that TClipboard keeps the text itself. }
  TClipboardBackend = class
  public
    { Puts Text on the system clipboard; False when that is not possible. }
    function SetText(const Text: string): Boolean; virtual;
    { Asks for the text of the system clipboard, which is handed to Accept now or later; False when that is not
      possible. }
    function RequestText(Accept: TTextProc): Boolean; virtual;
  end;

  { The clipboard of the program. It has no instances to use; the routines are class routines. }
  TClipboard = class
  private
    class var Instance: TClipboard;
    class var LocalText: string;
    constructor Create;
  public
    { The system clipboard. The program sets it before the first use. }
    class var Backend: TClipboardBackend;
    destructor Destroy; override;
    { Puts Text on the system clipboard through the backend; when the backend cannot, the text is kept here. }
    class procedure SetText(const Text: string); static;
    { Asks the backend for the text of the system clipboard; when it cannot, the text kept here is given to
      TEventQueue.SetPasteText. }
    class procedure RequestText; static;
  end;

implementation

uses
  TvSys;

var
  DefaultBackend: TClipboardBackend;

{ TClipboardBackend }

function TClipboardBackend.SetText(const Text: string): Boolean;
begin
  Result := False;
end;

function TClipboardBackend.RequestText(Accept: TTextProc): Boolean;
begin
  Result := False;
end;

{ TClipboard }

constructor TClipboard.Create;
begin
  inherited Create;
end;

destructor TClipboard.Destroy;
begin
  inherited Destroy;
end;

class procedure TClipboard.SetText(const Text: string);
begin
end;

class procedure TClipboard.RequestText;
begin
end;

initialization
  DefaultBackend := TClipboardBackend.Create;
  TClipboard.Backend := DefaultBackend;
  TClipboard.Instance := TClipboard.Create;

finalization
  TClipboard.Instance.Free;
  TClipboard.Instance := nil;
  DefaultBackend.Free;

end.
