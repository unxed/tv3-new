{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/internal/termio.h, source/platform/termio.cpp, include/tvision/internal/far2l.h,
  source/platform/far2l.cpp, include/tvision/internal/base64.h, source/platform/base64.cpp,
  include/tvision/internal/constmap.h, include/tvision/internal/constarr.h, include/tvision/internal/codepage.h,
  include/tvision/internal/utf8.h, include/tvision/internal/win32con.h
  See COPYRIGHT.magiblot.

  The parsers of terminal input, the key tables and the Windows console conversions are in TvEvents; the class
  TTermIO passes its parsing calls to them. This unit holds the Base64 conversions, the clipboard requests of the
  far2l extension and of OSC 52, and the mode switching calls that write to a ConsoleCtl.

  The initialization of this unit sets these variables of TvEvents: Base64Decode and Base64Encode to the conversions
  of this unit, CpFromUtf8 and CpPrintableFromUtf8 to the conversions of CpTranslator of TvCodePg, and
  Far2lEnableSeq and Far2lDisableSeq to the sequences that turn the far2l extension on and off. }
unit TvTermIo;

{$mode objfpc}
{$R-}
{$Q-}

interface

uses
  TvEvents, TvTermOs;

type
  { The namespace TermIO. Reading and writing are done through the ConsoleCtl and the input getter that are given. }
  TTermIO = class
  public
    class procedure MouseOn(Con: ConsoleCtl); static;
    class procedure MouseOff(Con: ConsoleCtl); static;
    class procedure KeyModsOn(Con: ConsoleCtl); static;
    class procedure KeyModsOff(Con: ConsoleCtl); static;

    class procedure NormalizeKey(var KeyDown: TKeyDownEvent); static;

    { False when neither the far2l extension nor OSC 52 can hold the text. }
    class function SetClipboardText(Con: ConsoleCtl; const Text: AnsiString;
      var State: TInputState): Boolean; static;
    { Remembers Accept as the receiver of the answer. False when no request could be made. }
    class function RequestClipboardText(Con: ConsoleCtl; Accept: TTextProc;
      var State: TInputState): Boolean; static;

    class function ParseEvent(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult; static;
    class function ParseEscapeSeq(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult; static;
    class function ParseX10Mouse(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult; static;
    class function ParseSGRMouse(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult; static;
    class function ParseCSIKey(const Csi: TCSIData; var Ev: TEvent; var State: TInputState): TParseResult; static;
    class function ParseSS3Key(var Buf: TGetChBuf; var Ev: TEvent): TParseResult; static;
    class function ParseKittyKey(const Csi: TCSIData; var Ev: TEvent): TParseResult; static;
    class function ParseDCS(var Buf: TGetChBuf; var State: TInputState): TParseResult; static;
    class function ParseOSC(var Buf: TGetChBuf; var State: TInputState): TParseResult; static;
    class function ParseCPR(const Csi: TCSIData; var State: TInputState): TParseResult; static;
    class function ParseWin32InputModeKeyOrEscapeSeq(const Csi: TCSIData; In_: TInputGetter; var Ev: TEvent;
      var State: TInputState): TParseResult; static;

    { The text before BEL or ST, which are not part of it. }
    class function ReadUntilBelOrSt(var Buf: TGetChBuf): string; static;
    class procedure ConsumeUnprocessedInput(Con: ConsoleCtl; In_: TInputGetter; var State: TInputState); static;
  end;

{ The standard alphabet; the decoder takes the URL alphabet too. }
function EncodeBase64(const Input: AnsiString): AnsiString;
function DecodeBase64(const Input: AnsiString): AnsiString;

{ The clipboard of the far2l extension. Both give False and write nothing while the extension is not enabled in State. }
function SetFar2lClipboard(Con: ConsoleCtl; const Text: AnsiString; var State: TInputState): Boolean;
function RequestFar2lClipboard(Con: ConsoleCtl; var State: TInputState): Boolean;

implementation

uses
  SysUtils, BaseUnix, UnixType, TvCodePg;

const
  { Request IDs of the far2l extension }
  f2lNoAnswer = #0;
  f2lClipGetData = #$A0;

  { The clipboard format of plain text of the Windows API. }
  CF_TEXT = 1;

  Base64Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

type
  { A routine of TvEvents that writes through a procedure. }
  TWriterCall = procedure(Writer: TTextProc);

var
  { The identification of this client for the far2l extension: the time at start as 32 decimal digits. }
  f2lClientId: AnsiString;

threadvar
  { The console that BridgeToConsole writes to while a call of TTermIO runs. }
  BridgeCon: ConsoleCtl;

{ Base64 }

function ByteAt(const S: AnsiString; Index: SizeInt): Cardinal;
begin
  Result := Ord(S[Index + 1]);
end;

procedure PutSextet(var S: AnsiString; Index: SizeInt; Value: Cardinal);
begin
  S[Index + 1] := Base64Alphabet[(Value and $3F) + 1];
end;

procedure StoreByte(var S: AnsiString; Index: SizeInt; Value: Cardinal);
begin
  S[Index + 1] := Chr(Value and $FF);
end;

{ The value of a Base64 character; 128 for a character that is not one. }
function SextetOf(Ch: AnsiChar): Cardinal;
begin
  case Ch of
    'A'..'Z': Result := Ord(Ch) - Ord('A');
    'a'..'z': Result := Ord(Ch) - Ord('a') + 26;
    '0'..'9': Result := Ord(Ch) - Ord('0') + 52;
    '+', '-': Result := 62;
    '/', '_': Result := 63;
  else
    Result := 128;
  end;
end;

function EncodeBase64(const Input: AnsiString): AnsiString;
var
  Total, Rest, Whole, Src, Dst: SizeInt;
  Group: Cardinal;
begin
  Total := Length(Input);
  Rest := Total mod 3;
  Whole := Total - Rest;
  SetLength(Result, (Total * 4) div 3 + 4);
  Src := 0;
  Dst := 0;
  while Src < Whole do
  begin
    Group := (ByteAt(Input, Src) shl 16) or (ByteAt(Input, Src + 1) shl 8) or ByteAt(Input, Src + 2);
    PutSextet(Result, Dst, Group shr 18);
    PutSextet(Result, Dst + 1, Group shr 12);
    PutSextet(Result, Dst + 2, Group shr 6);
    PutSextet(Result, Dst + 3, Group);
    Inc(Src, 3);
    Inc(Dst, 4);
  end;
  if Rest = 1 then
  begin
    Group := ByteAt(Input, Total - 1);
    PutSextet(Result, Dst, Group shr 2);
    PutSextet(Result, Dst + 1, Group shl 4);
    Result[Dst + 3] := '=';
    Result[Dst + 4] := '=';
    Inc(Dst, 4);
  end
  else if Rest = 2 then
  begin
    Group := (ByteAt(Input, Total - 2) shl 8) or ByteAt(Input, Total - 1);
    PutSextet(Result, Dst, Group shr 10);
    PutSextet(Result, Dst + 1, Group shr 4);
    PutSextet(Result, Dst + 2, Group shl 2);
    Result[Dst + 4] := '=';
    Inc(Dst, 4);
  end;
  SetLength(Result, Dst);
end;

function DecodeBase64(const Input: AnsiString): AnsiString;
var
  Total, Plain, Src, Dst: SizeInt;
  Padded: Boolean;
  Group: Cardinal;
begin
  Total := Length(Input);
  Padded := (Total > 0) and (((Total mod 4) <> 0) or (Input[Total] = '='));
  Plain := ((Total + 3) div 4 - Ord(Padded)) * 4;
  SetLength(Result, (Total * 3) div 4 + 3);
  Src := 0;
  Dst := 0;
  while Src < Plain do
  begin
    Group := (SextetOf(Input[Src + 1]) shl 18) or (SextetOf(Input[Src + 2]) shl 12) or
      (SextetOf(Input[Src + 3]) shl 6) or SextetOf(Input[Src + 4]);
    StoreByte(Result, Dst, Group shr 16);
    StoreByte(Result, Dst + 1, Group shr 8);
    StoreByte(Result, Dst + 2, Group);
    Inc(Src, 4);
    Inc(Dst, 3);
  end;
  if Padded and (Plain + 1 < Total) then
  begin
    Group := (SextetOf(Input[Plain + 1]) shl 18) or (SextetOf(Input[Plain + 2]) shl 12);
    StoreByte(Result, Dst, Group shr 16);
    Inc(Dst);
    if (Plain + 2 < Total) and (Input[Plain + 3] <> '=') then
    begin
      Group := Group or (SextetOf(Input[Plain + 3]) shl 6);
      StoreByte(Result, Dst, Group shr 8);
      Inc(Dst);
    end;
  end;
  SetLength(Result, Dst);
end;

{ The conversions that TvEvents calls through its variables. }

function Base64EncodeText(const Text: string): string;
begin
  Result := EncodeBase64(Text);
end;

function Base64DecodeText(const Text: string): string;
begin
  Result := DecodeBase64(Text);
end;

function CodePageCharOf(const Text: string): Byte;
begin
  Result := Ord(CpTranslator.FromUtf8(Text));
end;

function PrintableCodePageCharOf(const Text: string): Byte;
begin
  Result := Ord(CpTranslator.PrintableFromUtf8(Text));
end;

{ Writing to a console }

procedure SendText(Con: ConsoleCtl; const Text: AnsiString);
begin
  if (Con <> nil) and (Length(Text) > 0) then
    Con.Write(PAnsiChar(Text), Length(Text));
end;

procedure BridgeToConsole(const Text: string);
begin
  SendText(BridgeCon, Text);
end;

procedure RunWithConsole(Con: ConsoleCtl; Call: TWriterCall);
var
  Saved: ConsoleCtl;
begin
  Saved := BridgeCon;
  BridgeCon := Con;
  try
    Call(@BridgeToConsole);
  finally
    BridgeCon := Saved;
  end;
end;

{ The far2l extension }

{ An integer of a request: four bytes, the lowest first. }
function LittleEndian32(Value: Cardinal): AnsiString;
begin
  SetLength(Result, 4);
  StoreByte(Result, 0, Value);
  StoreByte(Result, 1, Value shr 8);
  StoreByte(Result, 2, Value shr 16);
  StoreByte(Result, 3, Value shr 24);
end;

{ The sequence that carries the bytes of one request. }
function FrameFar2lRequest(const Args: AnsiString): AnsiString;
begin
  Result := #27'_far2l:' + EncodeBase64(Args) + #27'\';
end;

function MakeClientId: AnsiString;
var
  Stamp: TTime;
begin
  Stamp := 0;
  Stamp := fpTime(Stamp);
  Result := IntToStr(Int64(Stamp));
  while Length(Result) < 32 do
    Result := '0' + Result;
end;

{ CLIP_OPEN }
function Far2lOpenRequest: AnsiString;
begin
  Result := FrameFar2lRequest(f2lClientId + LittleEndian32(Length(f2lClientId)) + 'oc' + f2lNoAnswer);
end;

{ CLIP_CLOSE }
function Far2lCloseRequest: AnsiString;
begin
  Result := FrameFar2lRequest('cc' + f2lNoAnswer);
end;

function SetFar2lClipboard(Con: ConsoleCtl; const Text: AnsiString; var State: TInputState): Boolean;
var
  Body, Output: AnsiString;
begin
  Result := State.Far2l.Enabled;
  if not Result then
    Exit;
  Body := Text;
  if Int64(Length(Body)) > Int64(High(Cardinal)) - 1 then
    SetLength(Body, High(Cardinal) - 1);
  Output := Far2lOpenRequest;
  { CLIP_SETDATA }
  Output := Output + FrameFar2lRequest(Body + #0 + LittleEndian32(Length(Body) + 1) +
    LittleEndian32(CF_TEXT) + 'sc' + f2lNoAnswer);
  Output := Output + Far2lCloseRequest;
  SendText(Con, Output);
end;

function RequestFar2lClipboard(Con: ConsoleCtl; var State: TInputState): Boolean;
var
  Output: AnsiString;
begin
  Result := State.Far2l.Enabled;
  if not Result then
    Exit;
  Output := Far2lOpenRequest;
  { CLIP_GETDATA }
  Output := Output + FrameFar2lRequest(LittleEndian32(CF_TEXT) + 'gc' + f2lClipGetData);
  Output := Output + Far2lCloseRequest;
  SendText(Con, Output);
end;

{ OSC 52 }

function SetOsc52Clipboard(Con: ConsoleCtl; const Text: AnsiString; var State: TInputState): Boolean;
begin
  SendText(Con, #27']52;;' + EncodeBase64(Text) + #7);
  { False without full OSC 52 support, even though the request is always made. This way the internal clipboard
    can still be used. }
  Result := State.HasFullOsc52;
end;

function RequestOsc52Clipboard(Con: ConsoleCtl; var State: TInputState): Boolean;
begin
  Result := State.HasFullOsc52;
  if Result then
    SendText(Con, #27']52;;?'#7);
end;

{ TTermIO }

class procedure TTermIO.MouseOn(Con: ConsoleCtl);
begin
  RunWithConsole(Con, @TvEvents.MouseOn);
end;

class procedure TTermIO.MouseOff(Con: ConsoleCtl);
begin
  RunWithConsole(Con, @TvEvents.MouseOff);
end;

class procedure TTermIO.KeyModsOn(Con: ConsoleCtl);
begin
  RunWithConsole(Con, @TvEvents.KeyModsOn);
end;

class procedure TTermIO.KeyModsOff(Con: ConsoleCtl);
begin
  RunWithConsole(Con, @TvEvents.KeyModsOff);
end;

class procedure TTermIO.NormalizeKey(var KeyDown: TKeyDownEvent);
begin
  TvEvents.NormalizeKey(KeyDown);
end;

class function TTermIO.SetClipboardText(Con: ConsoleCtl; const Text: AnsiString;
  var State: TInputState): Boolean;
begin
  Result := SetFar2lClipboard(Con, Text, State) or SetOsc52Clipboard(Con, Text, State);
end;

class function TTermIO.RequestClipboardText(Con: ConsoleCtl; Accept: TTextProc;
  var State: TInputState): Boolean;
begin
  State.PutPaste := Accept;
  Result := RequestFar2lClipboard(Con, State) or RequestOsc52Clipboard(Con, State);
end;

class function TTermIO.ParseEvent(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseEvent(Buf, Ev, State);
end;

class function TTermIO.ParseEscapeSeq(var Buf: TGetChBuf; var Ev: TEvent;
  var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseEscapeSeq(Buf, Ev, State);
end;

class function TTermIO.ParseX10Mouse(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseX10Mouse(Buf, Ev, State);
end;

class function TTermIO.ParseSGRMouse(var Buf: TGetChBuf; var Ev: TEvent; var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseSGRMouse(Buf, Ev, State);
end;

class function TTermIO.ParseCSIKey(const Csi: TCSIData; var Ev: TEvent; var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseCSIKey(Csi, Ev, State);
end;

class function TTermIO.ParseSS3Key(var Buf: TGetChBuf; var Ev: TEvent): TParseResult;
begin
  Result := TvEvents.ParseSS3Key(Buf, Ev);
end;

class function TTermIO.ParseKittyKey(const Csi: TCSIData; var Ev: TEvent): TParseResult;
begin
  Result := TvEvents.ParseKittyKey(Csi, Ev);
end;

class function TTermIO.ParseDCS(var Buf: TGetChBuf; var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseDCS(Buf, State);
end;

class function TTermIO.ParseOSC(var Buf: TGetChBuf; var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseOSC(Buf, State);
end;

class function TTermIO.ParseCPR(const Csi: TCSIData; var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseCPR(Csi, State);
end;

class function TTermIO.ParseWin32InputModeKeyOrEscapeSeq(const Csi: TCSIData; In_: TInputGetter;
  var Ev: TEvent; var State: TInputState): TParseResult;
begin
  Result := TvEvents.ParseWin32InputModeKeyOrEscapeSeq(Csi, In_, Ev, State);
end;

class function TTermIO.ReadUntilBelOrSt(var Buf: TGetChBuf): string;
begin
  Result := TvEvents.ReadUntilBelOrSt(Buf);
end;

class procedure TTermIO.ConsumeUnprocessedInput(Con: ConsoleCtl; In_: TInputGetter; var State: TInputState);
var
  Saved: ConsoleCtl;
begin
  Saved := BridgeCon;
  BridgeCon := Con;
  try
    TvEvents.ConsumeUnprocessedInput(@BridgeToConsole, In_, State);
  finally
    BridgeCon := Saved;
  end;
end;

initialization
  f2lClientId := MakeClientId;
  Base64Decode := @Base64DecodeText;
  Base64Encode := @Base64EncodeText;
  CpFromUtf8 := @CodePageCharOf;
  CpPrintableFromUtf8 := @PrintableCodePageCharOf;
  Far2lEnableSeq := #27'_far2l1'#27'\';
  Far2lDisableSeq := #27'_far2l0'#27'\';

end.
