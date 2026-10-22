{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/system.h (TClipboard), source/tvision/tclipbrd.cpp
  See COPYRIGHT.magiblot. }
program t_clip;

{$mode objfpc}

uses
  SysUtils, TvGeom, TvKeys, TvEvents, TvSys, TvClip;

{$I testlib.inc}

type
  { A backend that notes its calls and answers as it is told. }
  TNoteBackend = class(TClipboardBackend)
  public
    SetHandled: Boolean;
    RequestHandled: Boolean;
    SetCalls: Integer;
    RequestCalls: Integer;
    LastSet: string;
    Saved: TTextProc;
    function SetText(const Text: string): Boolean; override;
    function RequestText(Accept: TTextProc): Boolean; override;
  end;

function TNoteBackend.SetText(const Text: string): Boolean;
begin
  Inc(SetCalls);
  LastSet := Text;
  Result := SetHandled;
end;

function TNoteBackend.RequestText(Accept: TTextProc): Boolean;
begin
  Inc(RequestCalls);
  Saved := Accept;
  Result := RequestHandled;
end;

{ The text of the paste events that are waiting, and whether every one of them was marked as a paste. }
var
  AllMarked: Boolean;

function Pasted: string;
var
  Ev: TEvent;
  Guard: Integer;
begin
  Result := '';
  AllMarked := True;
  for Guard := 1 to 1000 do
  begin
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.What := $7777;
    TEventQueue.GetKeyEvent(Ev);
    if Ev.What <> evKeyDown then
      Exit;
    if (Ev.KeyDown.ControlKeyState and kbPaste) = 0 then
      AllMarked := False;
    Result := Result + Chr(Ev.KeyDown.Text[0]);
  end;
end;

var
  Original: TClipboardBackend;
  N: TNoteBackend;
  Got: string;

begin
  Original := TClipboard.Backend;
  Check(Original <> nil, 'there is a backend at the start');
  Check(not Original.SetText('x'), 'the default backend cannot set the text');
  Check(not Original.RequestText(nil), 'the default backend cannot request the text');

  { without a system clipboard the text stays here }
  TClipboard.RequestText;
  Check(Pasted = '', 'an empty clipboard pastes nothing');

  TClipboard.SetText('abc');
  TClipboard.RequestText;
  Got := Pasted;
  Check(Got = 'abc', 'the text that was set is pasted');
  Check(AllMarked, 'the keys of the text are paste keys');
  Check(Pasted = '', 'the text is pasted once per request');

  TClipboard.RequestText;
  Check(Pasted = 'abc', 'a second request gives the same text');

  TClipboard.SetText('x');
  TClipboard.SetText('yz');
  TClipboard.RequestText;
  Check(Pasted = 'yz', 'a new text replaces the old one');

  TClipboard.SetText('');
  TClipboard.RequestText;
  Check(Pasted = '', 'an empty text pastes nothing');
  TClipboard.SetText('abc');
  TClipboard.SetText('');
  TClipboard.RequestText;
  Check(Pasted = '', 'an empty text replaces the old one');

  { a text with a line end }
  TClipboard.SetText('a'#13#10'b');
  TClipboard.RequestText;
  Check(Pasted = 'a'#10'b', 'line ends of the text');

  { a backend that cannot: its calls are made and the text stays here }
  N := TNoteBackend.Create;
  TClipboard.Backend := N;
  TClipboard.SetText('one');
  Check(N.SetCalls = 1, 'the backend is asked to set the text');
  Check(N.LastSet = 'one', 'the backend gets the text');
  TClipboard.RequestText;
  Check(N.RequestCalls = 1, 'the backend is asked for the text');
  Check(Assigned(N.Saved), 'the backend gets a procedure for the answer');
  Check(Pasted = 'one', 'the text kept here is pasted when the backend cannot');

  { a backend that sets the text: it is not kept here }
  N.SetHandled := True;
  TClipboard.SetText('two');
  Check(N.SetCalls = 2, 'a second set is passed to the backend');
  Check(N.LastSet = 'two', 'the backend gets the second text');
  TClipboard.Backend := Original;
  TClipboard.RequestText;
  Check(Pasted = 'one', 'a text taken by the backend does not replace the kept one');
  TClipboard.Backend := N;

  { a backend that requests the text: nothing is pasted until it answers }
  N.RequestHandled := True;
  TClipboard.SetText('kept');
  TClipboard.RequestText;
  Check(N.RequestCalls = 2, 'a second request is passed to the backend');
  Check(Pasted = '', 'nothing is pasted before the backend answers');
  N.Saved('sys');
  Check(Pasted = 'sys', 'the answer of the backend is pasted');
  Check(AllMarked, 'the keys of the answer are paste keys');
  N.Saved('');
  Check(Pasted = '', 'an empty answer pastes nothing');

  { the kept text is still there when the backend is gone }
  N.RequestHandled := False;
  N.SetHandled := False;
  TClipboard.Backend := Original;
  TClipboard.RequestText;
  Check(Pasted = 'one', 'the kept text is unchanged by the requests of the backend');

  TClipboard.Backend := Original;
  N.Free;
  Done;
end.
