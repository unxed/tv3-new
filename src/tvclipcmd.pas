{ Reads and writes the system clipboard by running helper programs of the operating system (wl-copy, xsel, xclip,
  pbcopy, clip.exe under WSL) and shows desktop notifications through notify-send or osascript. Every routine returns
  False when there is no program or the program failed, so that the caller can go on to another way. The routines
  block the calling thread for at most about 1.5 seconds per call, keep a lazily built table of programs and change
  the SIGPIPE disposition of the process during a write: call them from one thread at a time. On systems that are not
  Unix-like every routine is a stub. }
unit TvClipCmd;

{$mode objfpc}
{$H+}
{$R-}
{$Q-}

interface

{ Puts Text on the clipboard byte for byte; False when no program is available or the program failed. }
function ClipCmdSet(const Text: AnsiString): Boolean;

{ Reads the clipboard into Text; Text is empty when the result is False. }
function ClipCmdGet(out Text: AnsiString): Boolean;

type
  TClipEnvProc = function(const Name: AnsiString): AnsiString;

var
  { When assigned, PATH, DISPLAY and WAYLAND_DISPLAY are read through it instead of the process environment. }
  OnClipEnv: TClipEnvProc = nil;

{ Shows a desktop notification; True when the notification program ended with status 0 within the time limit. }
function NotifyCmd(const Title, Text: AnsiString): Boolean;

{ The full path of the program that ClipCmdSet or ClipCmdGet would run now, or the empty text. }
function ClipCmdSetName: AnsiString;
function ClipCmdGetName: AnsiString;

implementation

end.
