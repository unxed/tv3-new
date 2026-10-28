{ Tests of TvFar2l. The byte strings are worked out from VTExts.md; the names of the sections of the document are
  given beside the checks that follow them. }
program t_far2l;

{$mode objfpc}
{$modeswitch advancedrecords}

uses
  ctypes, SysUtils, BaseUnix, TvEvents, TvTermOs, TvFar2l;

{$I testlib.inc}

type
  TAnsiArray = array of AnsiString;

  { Collects what a client reports and writes. }
  TTally = class
    Answers: array of TF2lAnswer;
    Events: array of TF2lEvent;
    Wire: AnsiString;
    procedure Put(const Data: AnsiString);
    procedure GotAnswer(const Answer: TF2lAnswer);
    procedure GotEvent(const Event: TF2lEvent);
  end;

procedure TTally.Put(const Data: AnsiString);
begin
  Wire := Wire + Data;
end;

procedure TTally.GotAnswer(const Answer: TF2lAnswer);
begin
  SetLength(Answers, Length(Answers) + 1);
  Answers[High(Answers)] := Answer;
end;

procedure TTally.GotEvent(const Event: TF2lEvent);
begin
  SetLength(Events, Length(Events) + 1);
  Events[High(Events)] := Event;
end;

{ The bytes that a text of hexadecimal pairs stands for; blanks are skipped. }
function FromHex(const Spec: AnsiString): AnsiString;
const
  Digits: AnsiString = '0123456789ABCDEF';
var
  K, Half, Acc: Integer;
begin
  Result := '';
  Half := 0;
  Acc := 0;
  for K := 1 to Length(Spec) do
    if Spec[K] <> ' ' then
    begin
      Acc := Acc * 16 + Pos(UpCase(Spec[K]), Digits) - 1;
      Inc(Half);
      if Half = 2 then
      begin
        Result := Result + Chr(Acc);
        Acc := 0;
        Half := 0;
      end;
    end;
end;

function BelWire(const Prefix, Payload: AnsiString): AnsiString;
begin
  Result := #27'_' + Prefix + Payload + #7;
end;

{ The bodies of the requests in a text of request strings that end with ST. }
function SplitRequests(const Wire: AnsiString): TAnsiArray;
const
  Head: AnsiString = #27'_far2l:';
var
  At, Stop: SizeInt;
begin
  Result := nil;
  At := 1;
  while Copy(Wire, At, Length(Head)) = Head do
  begin
    Stop := At + Length(Head);
    while (Stop < Length(Wire)) and not ((Wire[Stop] = #27) and (Wire[Stop + 1] = '\')) do
      Inc(Stop);
    if Stop >= Length(Wire) then
      Break;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Far2lDecodePayload(Copy(Wire, At + Length(Head), Stop - At - Length(Head)));
    At := Stop + 2;
  end;
end;

function DecodeOne(const Wire: AnsiString; out Itm: TF2lItem): Boolean;
var
  Dec: TF2lDecoder;
begin
  Dec := TF2lDecoder.Create;
  try
    Dec.Feed(Wire);
    Result := Dec.Next(Itm);
  finally
    Dec.Free;
  end;
end;

{ The kind of the first item that a decoder finds when the wire is fed in two pieces cut at Cut, and its count. }
function SplitFeed(const Wire: AnsiString; Cut: Integer; out Count: SizeInt): TF2lItemKind;
var
  Dec: TF2lDecoder;
  Itm: TF2lItem;
begin
  Dec := TF2lDecoder.Create;
  try
    Dec.Feed(Copy(Wire, 1, Cut));
    Dec.Feed(Copy(Wire, Cut + 1, Length(Wire)));
    Count := Dec.Pending;
    Result := ikOtherApc;
    if Dec.Next(Itm) then
      Result := Itm.Kind;
  finally
    Dec.Free;
  end;
end;

procedure CheckAllCuts(const Wire: AnsiString; Want: TF2lItemKind; const Name: string);
var
  Cut: Integer;
  Count: SizeInt;
  Bad: Integer;
begin
  Bad := 0;
  for Cut := 0 to Length(Wire) do
    if (SplitFeed(Wire, Cut, Count) <> Want) or (Count <> 1) then
      Inc(Bad);
  Check(Bad = 0, Name + ': the same item at every cut');
end;

{ The stack }

procedure TestStack;
var
  S: TF2lStack;
begin
  S := TF2lStack.Create;
  try
    S.PutNumber($0102, 2);
    S.PutSigned(-2, 2);
    S.PutString('ab');
    Check(S.Serialized = FromHex('02 01 fe ff 61 62 02 00 00 00'), 'stack: bytes of pushes');
    Check(S.Size = 10, 'stack: size');
    Check(S.PopString = 'ab', 'stack: string popped first');
    Check(S.PopSigned(2) = -2, 'stack: negative int16');
    Check(S.PopNumber(2) = $0102, 'stack: little-endian int16');
    Check((S.Size = 0) and not S.Failed, 'stack: empty without a failure');
    Check(S.PopNumber(1) = 0, 'stack: pop of an empty stack gives 0');
    Check(S.Failed, 'stack: failure is noted');

    S.Load(FromHex('01 02'));
    Check(S.PopNumber(4) = 0, 'stack: too short for four bytes');
    Check(S.Failed and (S.Size = 2), 'stack: a failed pop takes nothing');

    S.Load(FromHex('61 05 00 00 00'));
    Check(S.PopString = '', 'stack: string longer than the stack');
    Check(S.Failed, 'stack: that is a failure');

    S.Load(FromHex('88 77 66 55 44 33 22 11'));
    Check(S.PopNumber(8) = QWord($1122334455667788), 'stack: uint64');
    S.Load(FromHex('ff ff ff ff ff ff ff ff'));
    Check(S.PopSigned(8) = -1, 'stack: int64 minus one');
    S.Load(FromHex('ff'));
    Check(S.PopSigned(1) = -1, 'stack: int8 minus one');
    S.Load(FromHex('80 00'));
    Check(S.PopSigned(1) = 0, 'stack: top byte only');
  finally
    S.Free;
  end;
end;

{ 4.2 and 4.3: the framing and the Base64 payload }

procedure TestFraming;
begin
  Check(ActivationText = #27'_far2l1'#27'\', 'activation: ESC _ far2l1 ST');
  Check(DeactivationText = #27'_far2l0'#27'\', 'deactivation: ST by default');
  Check(DeactivationText(tmBel) = #27'_far2l0'#7, 'deactivation: BEL');
  Check(StatusQueryText = #27'[5n', 'status query');
  Check(HostIdentityText('me@host') = #27'_far2l#me@host'#7, 'host identity: BEL');
  Check(HostIdentityText('a'#27'b'#7'c', tmSt) = #27'_far2l#a b c'#27'\', 'host identity: control characters');
  Check(WrapRequest(FromHex('32 68 00'), tmBel) = BelWire('far2l:', 'MmgA'), 'request string with BEL');
  Check(WrapRequest(FromHex('32 68 00')) = #27'_far2l:MmgA'#27'\', 'request string with ST');
  Check(WrapRequest('') = #27'_far2l:'#27'\', 'an empty stack is an empty payload');

  Check(Far2lDecodePayload('MmgA') = FromHex('32 68 00'), 'payload: three bytes');
  Check(Far2lDecodePayload('dwE=') = FromHex('77 01'), 'payload: padding');
  Check(Far2lDecodePayload('dwE') = FromHex('77 01'), 'payload: no padding');
  Check(Far2lDecodePayload('dw') = FromHex('77'), 'payload: one byte');
  Check(Far2lDecodePayload('d') = '', 'payload: one character holds no byte');
  Check(Far2lDecodePayload(':MmgA') = '', 'payload: a colon in front gives an empty stack');
  Check(Far2lDecodePayload('MmgA!AAAA') = FromHex('32 68 00'), 'payload: stops at a foreign character');
  Check(Far2lDecodePayload('MmgA'#7'AAAA') = FromHex('32 68 00'), 'payload: stops at BEL');
  Check(Far2lDecodePayload('dwE=dwE=') = FromHex('77 01'), 'payload: stops at the first padding');
  Check(Far2lDecodePayload('Mm gA') = FromHex('32'), 'payload: no blanks inside');
  Check(Far2lDecodePayload('') = '', 'payload: empty');

  Check(ValidClientId('0123456789abcdef0123456789abcdef'), 'client id: 32 characters');
  Check(not ValidClientId('0123456789abcdef0123456789abcde'), 'client id: 31 characters');
  Check(not ValidClientId('0123456789abcdef0123456789abcdeF'), 'client id: capital letter');
  Check(ValidClientId(StringOfChar('a', 255) + '_'), 'client id: 256 characters');
  Check(not ValidClientId(StringOfChar('a', 257)), 'client id: 257 characters');
  Check(ValidClientId('host-name_0123456789abcdefghijklmn'), 'client id: dash and underscore');
  Check(not ValidClientId('0123456789abcdef0123456789abcde.'), 'client id: a dot');
end;

{ 5 and 7: the encoding of the requests }

const
  SampleCount = 13;

  { The stacks of the requests of section 7, bottom to top. }
  SampleStacks: array[0..SampleCount - 1] of AnsiString = (
    '32 68 00',
    '77 01',
    '4f 4b 02 00 00 00 44 6f 6e 65 04 00 00 00 6e 00',
    '00 00 00 00 00 00 00 00 00 00 4d 65 6e 75 04 00 00 00 01 48 65 6c 70 04 00 00 00 01 66 01',
    '30 31 32 33 34 35 36 37 38 39 61 62 63 64 65 66 30 31 32 33 34 35 36 37 38 39 61 62 63 64 65 66 ' +
      '20 00 00 00 6f 63 01',
    '68 65 6c 6c 6f 05 00 00 00 01 00 00 00 73 63 02',
    '01 00 00 00 67 63 03',
    '63 63 00',
    '46 41 52 5f 56 65 72 74 69 63 61 6c 42 6c 6f 63 6b 5f 55 6e 69 63 6f 64 65 19 00 00 00 72 63 04',
    '63 69 05',
    'ff 00 00 ff 01 00 00 00 01 00 00 00 ff ff ff ff 03 00 02 00 00 00 00 00 00 00 00 00 69 6d 67 03 00 00 00 ' +
      '73 69 06',
    '05 00 ff ff ff ff ff ff ff ff 69 6d 67 03 00 00 00 74 69 07',
    '01 00 00 00 00 00 00 00 78 00');

  { The Base64 text of the same requests as the document gives them. }
  SamplePayloads: array[0..SampleCount - 1] of AnsiString = (
    'MmgA', 'dwE=', 'T0sCAAAARG9uZQQAAABuAA==', 'AAAAAAAAAAAAAE1lbnUEAAAAAUhlbHAEAAAAAWYB',
    'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWYgAAAAb2MB', 'aGVsbG8FAAAAAQAAAHNjAg==', 'AQAAAGdjAw==', 'Y2MA',
    'RkFSX1ZlcnRpY2FsQmxvY2tfVW5pY29kZRkAAAByYwQ=', 'Y2kF',
    '/wAA/wEAAAABAAAA/////wMAAgAAAAAAAAAAAGltZwMAAABzaQY=', 'BQD//////////2ltZwMAAAB0aQc=',
    'AQAAAAAAAAB4AA==');

function SampleRequest(N: Integer; out Id: Byte): TF2lRequest;
var
  Texts: array[0..11] of AnsiString;
begin
  Id := 0;
  case N of
    0: Result := RequestCursorHeight(50);
    1:
      begin
        Result := PlainRequest(rqMaxSize);
        Id := 1;
      end;
    2: Result := RequestNotification('Done', 'OK');
    3:
      begin
        Texts[0] := 'Help';
        Texts[1] := 'Menu';
        Result := RequestFKeyTitles(Texts, $0FFC);
        Id := 1;
      end;
    4:
      begin
        Result := RequestClipOpen('0123456789abcdef0123456789abcdef');
        Id := 1;
      end;
    5:
      begin
        Result := RequestClipSetData(CF_TEXT, 'hello');
        Id := 2;
      end;
    6:
      begin
        Result := RequestClipFormat(rqClipGetData, CF_TEXT);
        Id := 3;
      end;
    7: Result := PlainRequest(rqClipClose);
    8:
      begin
        Result := RequestClipRegister('FAR_VerticalBlock_Unicode');
        Id := 4;
      end;
    9:
      begin
        Result := PlainRequest(rqImageCaps);
        Id := 5;
      end;
    10:
      begin
        Result := RequestImageSet('img', WP_IMG_RGBA, 2, 3, -1, -1, 1, 1, #$FF#0#0#$FF);
        Id := 6;
      end;
    11:
      begin
        Result := RequestImageTransform('img', -1, -1, -1, -1, WP_IMGTF_ROTATE90 or WP_IMGTF_MIRROR_H);
        Id := 7;
      end;
  else
    Result := RequestFeatures(FARTTY_FEAT_COMPACT_INPUT);
  end;
end;

procedure TestRequests;
var
  N: Integer;
  Id: Byte;
  Req: TF2lRequest;
  Body: AnsiString;
begin
  for N := 0 to SampleCount - 1 do
  begin
    Req := SampleRequest(N, Id);
    Body := EncodeRequest(Req, Id);
    Check(Body = FromHex(SampleStacks[N]), 'sample ' + IntToStr(N) + ': stack');
    Check(WrapRequest(Body, tmBel) = BelWire('far2l:', SamplePayloads[N]), 'sample ' + IntToStr(N) + ': string');
  end;
end;

{ The requests that section 7 does not show; the stacks follow the tables of section 5. }
procedure TestMoreRequests;
var
  Req: TF2lRequest;
begin
  Check(EncodeRequest(PlainRequest(rqQuickEdit), 0) = FromHex('65 00'), 'e: ad-hoc quick edit');
  Check(EncodeRequest(PlainRequest(rqMaximize), 0) = FromHex('4d 00'), 'M: maximize');
  Check(EncodeRequest(PlainRequest(rqRestore), 9) = FromHex('6d 09'), 'm: restore with an ID');
  Check(EncodeRequest(PlainRequest(rqPalette), 8) = FromHex('70 08'), 'p: color palette');
  Check(EncodeRequest(RequestFeatures(FARTTY_FEAT_COMPACT_INPUT or FARTTY_FEAT_TERMINAL_SIZE), 0) =
    FromHex('03 00 00 00 00 00 00 00 78 00'), 'x: two features');
  Check(EncodeRequest(PlainRequest(rqClipEmpty), 0) = FromHex('65 63 00'), 'c e: empty');
  Check(EncodeRequest(RequestClipFormat(rqClipIsAvail, CF_UNICODETEXT), 4) = FromHex('0d 00 00 00 61 63 04'),
    'c a: availability of a format');
  Check(EncodeRequest(RequestClipFormat(rqClipGetDataId, CF_HTML), 5) = FromHex('0f 00 00 00 69 63 05'),
    'c i: identifier of a format');
  Check(EncodeRequest(RequestClipSetData($C000, ''), 0) = FromHex('00 00 00 00 00 c0 00 00 73 63 00'),
    'c s: no data');
  Check(EncodeRequest(RequestClipChunk(StringOfChar('z', 512)), 0) =
    StringOfChar('z', 512) + FromHex('02 00 53 63 00'), 'c S: size field is the size divided by 256');
  Check(EncodeRequest(RequestClipChunk(''), 0) = FromHex('00 00 53 63 00'), 'c S: size zero cancels');
  Check(EncodeRequest(RequestImageDelete('a'), 3) = FromHex('61 01 00 00 00 64 69 03'), 'i d: delete');
  Check(EncodeRequest(RequestNotification('', ''), 0) = FromHex('00 00 00 00 00 00 00 00 6e 00'),
    'n: empty strings');
  Check(EncodeRequest(RequestCursorHeight(100), 0) = FromHex('64 68 00'), 'h: height 100');

  Req := RequestImageSet('i', WP_IMG_PNG or WP_IMG_ATTACH_BOTTOM or WP_IMG_SCROLL or WP_IMG_PIXEL_OFFSET, 0, 0,
    5, -2, 3, 1, 'abc');
  Check(EncodeRequest(Req, 1) = 'abc' + FromHex('01 00 00 00 03 00 00 00 fe ff 05 00 00 00 00 00 ' +
    '02 00 1c 00 00 00 00 00 69 01 00 00 00 73 69 01'), 'i s: flags, edges and sizes');

  Check(EncodeRequest(RequestFKeyTitles(['x'], 0), 0) = FromHex('78 01 00 00 00 01 66 00'),
    'f: one entry');
  Check(EncodeRequest(RequestFKeyTitles(['x', 'y'], 1), 0) = FromHex('79 01 00 00 00 01 00 66 00'),
    'f: the first key has no title');
  Check(EncodeRequest(RequestFKeyTitles([], 0), 2) = FromHex('66 02'), 'f: no entries clear all titles');
  Check(EncodeRequest(RequestFKeyTitles(['1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd'], 0), 0) =
    FromHex('63 01 00 00 00 01 62 01 00 00 00 01 61 01 00 00 00 01 39 01 00 00 00 01 38 01 00 00 00 01 ' +
    '37 01 00 00 00 01 36 01 00 00 00 01 35 01 00 00 00 01 34 01 00 00 00 01 33 01 00 00 00 01 ' +
    '32 01 00 00 00 01 31 01 00 00 00 01 66 00'), 'f: thirteen entries are cut to twelve');
end;

{ 5.1 to 5.8: the answers }

procedure TestAnswers;
var
  Ans: TF2lAnswer;
begin
  Check(DecodeAnswer(rqMaxSize, 1, FromHex('c8 00 32 00'), 0, Ans) and (Ans.Height = 50) and (Ans.Width = 200),
    'w: height pops first');
  Check(DecodeAnswer(rqMaxSize, 1, FromHex('c8 00'), 0, Ans) = False, 'w: truncated');
  Check(not Ans.Valid, 'w: truncated is not valid');
  Check(DecodeAnswer(rqMaxSize, 1, '', 0, Ans) = False, 'w: empty reply');
  Check(DecodeAnswer(rqFKeyTitles, 1, FromHex('01'), 0, Ans) and Ans.Flag, 'f: supported');
  Check(DecodeAnswer(rqFKeyTitles, 1, FromHex('00'), 0, Ans) and not Ans.Flag, 'f: not supported');
  Check(not DecodeAnswer(rqFKeyTitles, 1, '', 0, Ans), 'f: empty reply is an error');
  Check(DecodeAnswer(rqPalette, 1, FromHex('00 18'), 0, Ans) and (Ans.Bits = 24), 'p: color bits are on top of the reserved byte');
  Check(DecodeAnswer(rqPalette, 1, FromHex('08'), 0, Ans) and (Ans.Bits = 8), 'p: reserved byte may be missing');
  Check(DecodeAnswer(rqMaximize, 1, '', 0, Ans) and (Ans.Kind = rqMaximize) and (Ans.Id = 1),
    'm: an ID alone is a complete reply');

  Check(DecodeAnswer(rqClipOpen, 1, FromHex('03 00 00 00 00 00 00 00 01'), 0, Ans) and (Ans.Status = 1) and
    (Ans.Wide = 3), 'c o: status and features');
  Check(DecodeAnswer(rqClipOpen, 1, FromHex('00'), 0, Ans) and (Ans.Status = 0) and (Ans.Wide = 0),
    'c o: refused');
  Check(DecodeAnswer(rqClipOpen, 1, FromHex('03 00 00 00 00 00 00 00 ff'), 0, Ans) and (Ans.Status = -1) and
    (Ans.Wide = 0), 'c o: features are read only after status 1');
  Check(DecodeAnswer(rqClipOpen, 1, FromHex('01'), 0, Ans) and (Ans.Wide = 0), 'c o: absent features are 0');
  Check(not DecodeAnswer(rqClipOpen, 1, '', 0, Ans), 'c o: no status');
  Check(DecodeAnswer(rqClipClose, 1, FromHex('ff'), 0, Ans) and (Ans.Status = -1), 'c c: not open');
  Check(DecodeAnswer(rqClipEmpty, 1, FromHex('01'), 0, Ans) and (Ans.Status = 1), 'c e: done');
  Check(DecodeAnswer(rqClipIsAvail, 1, FromHex('01'), 0, Ans) and Ans.Flag, 'c a: available');
  Check(DecodeAnswer(rqClipIsAvail, 1, FromHex('00'), 0, Ans) and not Ans.Flag, 'c a: not available');

  Check(DecodeAnswer(rqClipSetData, 2, FromHex('88 77 66 55 44 33 22 11 01'), FARTTY_FEATCLIP_DATA_ID, Ans) and
    (Ans.Status = 1) and (Ans.Wide = QWord($1122334455667788)), 'c s: data identifier');
  Check(DecodeAnswer(rqClipSetData, 2, FromHex('88 77 66 55 44 33 22 11 01'), 0, Ans) and (Ans.Wide = 0),
    'c s: no identifier without the feature');
  Check(DecodeAnswer(rqClipSetData, 2, FromHex('00'), FARTTY_FEATCLIP_DATA_ID, Ans) and (Ans.Status = 0) and
    (Ans.Wide = 0), 'c s: failure holds no identifier');
  Check(DecodeAnswer(rqClipSetData, 2, FromHex('ff'), 3, Ans) and (Ans.Status = -1), 'c s: not open');

  Check(DecodeAnswer(rqClipGetData, 3, FromHex('88 77 66 55 44 33 22 11 68 65 6c 6c 6f 05 00 00 00'), 3, Ans) and
    (Ans.Number = 5) and (Ans.Data = 'hello') and (Ans.Wide = QWord($1122334455667788)), 'c g: size, data, identifier');
  Check(DecodeAnswer(rqClipGetData, 3, FromHex('68 65 6c 6c 6f 05 00 00 00'), 0, Ans) and (Ans.Data = 'hello') and
    (Ans.Wide = 0), 'c g: without the feature the identifier is not read');
  Check(not DecodeAnswer(rqClipGetData, 3, FromHex('68 65 6c 05 00 00 00'), 0, Ans), 'c g: data shorter than size');
  Check(DecodeAnswer(rqClipGetData, 3, FromHex('01 00 00 00 ff ff ff ff'), 3, Ans) and (Ans.Status = -1) and
    (Ans.Number = $FFFFFFFF) and (Ans.Data = ''), 'c g: clipboard not open');
  Check(DecodeAnswer(rqClipGetData, 3, FromHex('00 00 00 00 00 00 00 00 00 00 00 00'), 3, Ans) and
    (Ans.Number = 0) and (Ans.Data = '') and (Ans.Wide = 0), 'c g: no data');
  Check(DecodeAnswer(rqClipGetDataId, 3, FromHex('88 77 66 55 44 33 22 11'), 3, Ans) and
    (Ans.Wide = QWord($1122334455667788)), 'c i: identifier');
  Check(not DecodeAnswer(rqClipGetDataId, 3, FromHex('88 77 66'), 3, Ans), 'c i: short');
  Check(DecodeAnswer(rqClipRegister, 4, FromHex('00 c0 00 00'), 0, Ans) and (Ans.Number = $C000), 'c r: format');

  Check(DecodeAnswer(rqImageCaps, 5, FromHex('03 0b 00 00 00 00 00 00 08 00 10 00'), 0, Ans) and
    (Ans.Height = 16) and (Ans.Width = 8) and (Ans.Wide = $B03), 'i c: height, width, capabilities');
  Check(not DecodeAnswer(rqImageCaps, 5, FromHex('00'), 0, Ans), 'i c: a single zero byte is an error');
  Check(DecodeAnswer(rqImageSet, 6, FromHex('01'), 0, Ans) and Ans.Flag, 'i s: shown');
  Check(DecodeAnswer(rqImageTransform, 7, FromHex('00'), 0, Ans) and not Ans.Flag, 'i t: not changed');
  Check(DecodeAnswer(rqImageDelete, 8, FromHex('01'), 0, Ans) and Ans.Flag, 'i d: removed');

  Check(ImageCapsHasJpeg($B03), 'jpeg: both low bits');
  Check(not ImageCapsHasJpeg(WP_IMGCAP_RGBA), 'jpeg: not with RGBA alone');
  Check(not ImageCapsHasJpeg(WP_IMGCAP_PNG or WP_IMGCAP_ATTACH), 'jpeg: not with PNG alone');
  Check(WP_IMGCAP_JPG = 3, 'jpeg: the value is 3');
  Check((WP_IMG_ATTACH_TOP and WP_IMG_MASK_ATTACH) = $030000, 'attach mode is a number in bits 16 to 18');
end;

{ 6: the events }

procedure TestEvents;
var
  Ev: TF2lEvent;
begin
  Check(DecodeEvent(FromHex('01 00 41 00 1e 00 00 00 00 00 61 00 00 00 4b'), Ev) = drDecoded, 'K: decoded');
  Check((Ev.Kind = feKey) and Ev.Pressed and not Ev.Compact, 'K: a press in the full form');
  Check((Ev.Character = $61) and (Ev.ControlKeyState = 0) and (Ev.ScanCode = $1E) and (Ev.VirtualKey = $41) and
    (Ev.RepeatCount = 1), 'K: fields');
  Check(DecodeEvent(FromHex('03 00 41 00 1e 00 10 01 00 00 e9 00 00 00 6b'), Ev) = drDecoded, 'k: decoded');
  Check((Ev.Kind = feKey) and not Ev.Pressed and (Ev.RepeatCount = 3) and (Ev.Character = $E9) and
    (Ev.ControlKeyState = $110), 'k: a release with a repeat count and flags');

  Check(DecodeEvent(FromHex('41 00 00 61 00 43'), Ev) = drDecoded, 'C: decoded');
  Check((Ev.Kind = feKey) and Ev.Pressed and Ev.Compact and (Ev.Character = $61) and (Ev.VirtualKey = $41) and
    (Ev.ScanCode = 0) and (Ev.RepeatCount = 1) and (Ev.ControlKeyState = 0), 'C: fields');
  Check(DecodeEvent(FromHex('0d 28 01 3b 04 63'), Ev) = drDecoded, 'c: decoded');
  Check((Ev.Kind = feKey) and not Ev.Pressed and Ev.Compact and (Ev.Character = $043B) and
    (Ev.ControlKeyState = $0128) and (Ev.VirtualKey = $0D), 'c: a release');

  Check(DecodeEvent(FromHex('0a 00 05 00 01 00 00 00 6d'), Ev) = drDecoded, 'm: decoded');
  Check((Ev.Kind = feMouse) and Ev.Compact and (Ev.MouseX = 10) and (Ev.MouseY = 5) and (Ev.ButtonState = 1) and
    (Ev.EventFlags = 0) and (Ev.ControlKeyState = 0), 'm: a left press');
  Check(DecodeEvent(FromHex('03 00 04 00 00 01 00 04 6d'), Ev) = drDecoded, 'm: wheel up decoded');
  Check((Ev.ButtonState = $10000) and (Ev.EventFlags = 4) and (Ev.MouseX = 3) and (Ev.MouseY = 4),
    'm: the compact button state is expanded');
  Check(DecodeEvent(FromHex('ff ff fe ff 05 02 01 02 6d'), Ev) = drDecoded, 'm: negative coordinates decoded');
  Check((Ev.MouseX = -1) and (Ev.MouseY = -2) and (Ev.ButtonState = $020005) and (Ev.ControlKeyState = 1) and
    (Ev.EventFlags = 2), 'm: signed position, buttons of both bytes');
  Check(DecodeEvent(FromHex('0a 00 05 00 00 00 ff ff 00 00 00 00 04 00 00 00 4d'), Ev) = drDecoded, 'M: decoded');
  Check((Ev.Kind = feMouse) and not Ev.Compact and (Ev.ButtonState = $FFFF0000) and (Ev.EventFlags = 4) and
    (Ev.MouseX = 10) and (Ev.MouseY = 5), 'M: wheel down');

  Check(DecodeEvent(FromHex('50 00 19 00 53'), Ev) = drDecoded, 'S: decoded');
  Check((Ev.Kind = feTerminalSize) and (Ev.Rows = 25) and (Ev.Columns = 80), 'S: height pops first');

  Check(DecodeEvent('', Ev) = drMalformed, 'no code is malformed');
  Check(DecodeEvent(FromHex('19 00 53'), Ev) = drMalformed, 'S: truncated is malformed');
  Check(DecodeEvent(FromHex('4b'), Ev) = drDropped, 'K: truncated is dropped');
  Check(DecodeEvent(FromHex('00 00 6d'), Ev) = drDropped, 'm: truncated is dropped');
  Check(DecodeEvent(FromHex('01 00 43'), Ev) = drDropped, 'C: truncated is dropped');
  Check(DecodeEvent(FromHex('00 5a'), Ev) = drUnknown, 'unknown code');
  Check((Ev.Code = 'Z') and (Ev.Kind = feUnknown), 'unknown code is kept');
  Check(DecodeEvent(FromHex('ee ee 19 00 50 00 53'), Ev) = drDecoded, 'S: bytes below are not read');
  Check((Ev.Rows = $50) and (Ev.Columns = $19), 'S: the order of the pops, with an extra byte pair below');
end;

{ 4.2: the decoder of APC strings }

procedure TestDecoder;
var
  Dec: TF2lDecoder;
  Itm: TF2lItem;
begin
  Check(DecodeOne(BelWire('far2l', 'ok'), Itm) and (Itm.Kind = ikAck), 'ack with BEL');
  Check(DecodeOne(#27'_far2lok'#27'\', Itm) and (Itm.Kind = ikAck), 'ack with ST');
  Check(DecodeOne(BelWire('far2l', 'AQ=='), Itm) and (Itm.Kind = ikReply) and (Itm.ReplyId = 1) and
    (Itm.ReplyBody = ''), 'a reply that holds an ID only');
  Check(DecodeOne(BelWire('far2l', 'yAAyAAE='), Itm) and (Itm.Kind = ikReply) and (Itm.ReplyId = 1) and
    (Itm.ReplyBody = FromHex('c8 00 32 00')), 'reply of the window size');
  Check(DecodeOne(#27'_far2lAwsAAAAAAAAIABAABQ=='#27'\', Itm) and (Itm.ReplyId = 5) and
    (Itm.ReplyBody = FromHex('03 0b 00 00 00 00 00 00 08 00 10 00')), 'reply with ST');
  Check(DecodeOne(BelWire('far2l', 'iHdmVUQzIhFoZWxsbwUAAAAD'), Itm) and (Itm.ReplyId = 3) and
    (Itm.ReplyBody = FromHex('88 77 66 55 44 33 22 11 68 65 6c 6c 6f 05 00 00 00')), 'reply of the data');

  Check(DecodeOne(BelWire('f2l', 'AQBBAB4AAAAAAGEAAABL'), Itm) and (Itm.Kind = ikEvent) and
    (Itm.Event.Kind = feKey) and (Itm.Event.Character = $61), 'key event');
  Check(DecodeOne(BelWire('f2l', 'UAAZAFM='), Itm) and (Itm.Event.Kind = feTerminalSize) and
    (Itm.Event.Rows = 25) and (Itm.Event.Columns = 80), 'size event');

  { Malformed strings }
  Check(DecodeOne(BelWire('far2l:', 'MmgA'), Itm) and (Itm.Kind = ikBadReply), 'a colon in a reply gives no stack');
  Check(DecodeOne(BelWire('far2l', ''), Itm) and (Itm.Kind = ikBadReply), 'a reply without a payload');
  Check(DecodeOne(BelWire('f2l:', 'UAAZAFM='), Itm) and (Itm.Kind = ikBadEvent), 'a colon in an event gives no stack');
  Check(DecodeOne(BelWire('f2l', ''), Itm) and (Itm.Kind = ikBadEvent), 'an event without a code');
  Check(DecodeOne(BelWire('f2l', 'GQBT'), Itm) and (Itm.Kind = ikBadEvent), 'a truncated size event');
  Check(DecodeOne(BelWire('f2l', 'Sw=='), Itm) and (Itm.Kind = ikDropped), 'a broken key event');
  Check(DecodeOne(BelWire('f2l', 'Wg=='), Itm) and (Itm.Kind = ikUnknownEvent) and (Itm.Event.Code = 'Z'),
    'an unknown event code');
  Check(DecodeOne(BelWire('Gq=0;', 'AAAA'), Itm) and (Itm.Kind = ikOtherApc), 'another APC string');
  Check(DecodeOne(BelWire('far2', 'ok'), Itm) and (Itm.Kind = ikOtherApc), 'a near miss of the prefix');

  CheckAllCuts(BelWire('f2l', 'AQBBAB4AAAAAAGEAAABL'), ikEvent, 'key event');
  CheckAllCuts(#27'_f2lCgAFAAAA//8AAAAABAAAAE0='#27'\', ikEvent, 'wheel event with ST');
  CheckAllCuts(BelWire('far2l', 'iHdmVUQzIhEBAg=='), ikReply, 'reply');
  CheckAllCuts(#27'_far2lok'#27'\', ikAck, 'ack');
  CheckAllCuts(BelWire('far2l:', 'AQ=='), ikBadReply, 'bad reply');

  Dec := TF2lDecoder.Create;
  try
    { Bytes that are not strings of the extension pass through in order. }
    Dec.Feed('ab'#27'[A'#27'_far2lok'#7'cd');
    Check(Dec.Next(Itm) and (Itm.Kind = ikAck), 'ack between other bytes');
    Check(not Dec.Next(Itm), 'nothing else');
    Check(Dec.TakePlain = 'ab'#27'[Acd', 'the other bytes are kept');
    Check(Dec.TakePlain = '', 'and taken once');

    Dec.Feed('x'#27);
    Check(Dec.TakePlain = 'x', 'an ESC at the end of a piece is held');
    Dec.Feed('[B');
    Check(Dec.TakePlain = #27'[B', 'and goes on with the next piece');
    Dec.Feed(#27#27'_far2lok'#7);
    Check(Dec.TakePlain = #27, 'ESC ESC: the first one is a plain byte');
    Check(Dec.Next(Itm) and (Itm.Kind = ikAck), 'and the second starts a string');

    { A string cut off by another escape sequence }
    Dec.Feed(#27'_f2lAQ'#27'[A');
    Check(Dec.Skipped = 1, 'a cut-off string is counted');
    Check(not Dec.Next(Itm), 'it gives no item');
    Check(Dec.TakePlain = #27'[A', 'and the sequence that cut it is plain');
    Dec.Feed(#27'_f2lAQ'#27'_far2lok'#7);
    Check(Dec.Next(Itm) and (Itm.Kind = ikAck) and (Dec.Skipped = 2), 'a new string may start at the cut');

    { A body that is too long }
    Dec.BodyLimit := 8;
    Dec.Feed(BelWire('f2l', 'AQBBAB4AAAAAAGEAAABL'));
    Check(not Dec.Next(Itm) and (Dec.Skipped = 3), 'a body over the limit is thrown away');
    Check(Dec.TakePlain = '', 'without plain bytes');
    Dec.BodyLimit := 100;
    Dec.Feed(BelWire('f2l', 'AQBBAB4AAAAAAGEAAABL'));
    Check(Dec.Next(Itm) and (Itm.Kind = ikEvent), 'the next body is read');

    { Several strings in one piece come out in order }
    Dec.Feed(BelWire('far2l', 'AQ==') + BelWire('f2l', 'QQAAYQBD') + BelWire('far2l', 'ok'));
    Check(Dec.Pending = 3, 'three items are waiting');
    Check(Dec.Next(Itm) and (Itm.Kind = ikReply), 'first the reply');
    Check(Dec.Next(Itm) and (Itm.Kind = ikEvent) and Itm.Event.Compact, 'then the event');
    Check(Dec.Next(Itm) and (Itm.Kind = ikAck), 'then the ack');
    Check(Dec.Pending = 0, 'none left');

    Dec.Feed(#27'_far2lok');
    Dec.Reset;
    Dec.Feed(#7);
    Check(Dec.TakePlain = #7, 'a reset forgets the half string');
  finally
    Dec.Free;
  end;
end;

{ The events of the library }

procedure TestToEvent;
var
  Fe: TF2lEvent;
  Ev: TEvent;
  St: TInputState;
begin
  FillChar(St, SizeOf(St), 0);
  DecodeEvent(FromHex('01 00 41 00 1e 00 00 00 00 00 61 00 00 00 4b'), Fe);
  Check(Far2lToEvent(Fe, Ev, St) and (Ev.What = evKeyDown) and (Ev.KeyDown.GetText = 'a'), 'full key press');
  DecodeEvent(FromHex('41 00 00 61 00 43'), Fe);
  Check(Far2lToEvent(Fe, Ev, St) and (Ev.What = evKeyDown) and (Ev.KeyDown.GetText = 'a'), 'compact key press');
  DecodeEvent(FromHex('01 00 41 00 1e 00 00 00 00 00 61 00 00 00 6b'), Fe);
  Check(not Far2lToEvent(Fe, Ev, St) and (Ev.What = evNothing), 'a key release gives no event');
  DecodeEvent(FromHex('50 00 19 00 53'), Fe);
  Check(not Far2lToEvent(Fe, Ev, St), 'the terminal size gives no event');
  DecodeEvent(FromHex('00 5a'), Fe);
  Check(not Far2lToEvent(Fe, Ev, St), 'an unknown event gives no event');

  FillChar(St, SizeOf(St), 0);
  DecodeEvent(FromHex('0a 00 05 00 01 00 00 00 6d'), Fe);
  Check(Far2lToEvent(Fe, Ev, St) and (Ev.What = evMouse) and (Ev.Mouse.Buttons = mbLeftButton) and
    (Ev.Mouse.Where.X = 10) and (Ev.Mouse.Where.Y = 5) and (Ev.Mouse.Wheel = 0), 'compact mouse press');
  FillChar(St, SizeOf(St), 0);
  DecodeEvent(FromHex('0a 00 05 00 00 00 ff ff 00 00 00 00 04 00 00 00 4d'), Fe);
  Check(Far2lToEvent(Fe, Ev, St) and (Ev.What = evMouse) and (Ev.Mouse.Wheel = mwDown) and
    (Ev.Mouse.EventFlags = MOUSE_WHEELED) and (Ev.Mouse.Buttons = 0), 'wheel down event');
  FillChar(St, SizeOf(St), 0);
  DecodeEvent(FromHex('03 00 04 00 00 01 00 04 6d'), Fe);
  Check(Far2lToEvent(Fe, Ev, St) and (Ev.Mouse.Wheel = mwUp), 'wheel up event');
end;

{ 4.4, 4.5 and 5.7: the client }

procedure TestProbe;
var
  T: TTally;
  C: TFar2lClient;
  K: Integer;
  Wire: AnsiString;
begin
  T := TTally.Create;
  C := TFar2lClient.Create(@T.Put);
  try
    Check(C.ProbeState = ppIdle, 'probe: idle at the start');
    C.Probe;
    Check(T.Wire = #27'_far2l1'#27'\'#27'[5n', 'probe: activation and status query');
    Check(C.ProbeState = ppWaiting, 'probe: waiting');
    C.Feed(#27'_far2lok'#7#27'[0n');
    Check((C.ProbeState = ppDone) and C.Supported and C.Acknowledged, 'probe: acknowledged before the status');
    Check(C.TakePlain = #27'[0n', 'probe: the status report is left for the input parser');

    C.Probe;
    C.Feed(#27'[0n');
    Check((C.ProbeState = ppDone) and not C.Supported, 'probe: the status report alone means no server');
    C.Feed(#27'_far2lok'#7);
    Check(C.Acknowledged and not C.Supported, 'probe: the ack after the status report comes too late');

    Wire := #27'_far2lok'#27'\'#27'[0n';
    for K := 1 to Length(Wire) do
    begin
      C.Probe;
      C.Feed(Copy(Wire, 1, K));
      C.Feed(Copy(Wire, K + 1, Length(Wire)));
      Check(C.Supported, 'probe: split at ' + IntToStr(K));
    end;

    C.Probe;
    C.Feed(#27'[');
    C.Feed('0');
    C.Feed('n');
    Check((C.ProbeState = ppDone) and not C.Supported, 'probe: the status report in three pieces');

    C.Probe;
    C.Feed(#27'_far2lok'#27'\');
    C.ProbeTimedOut;
    Check((C.ProbeState = ppDone) and C.Supported, 'probe: a timeout with the ack in hand');
    C.Probe;
    C.ProbeTimedOut;
    Check((C.ProbeState = ppDone) and not C.Supported, 'probe: a timeout without it');

    T.Wire := '';
    C.Announce;
    Check(T.Wire = #27'_far2l1'#27'\', 'announce');
    T.Wire := '';
    C.Deactivate;
    Check(T.Wire = #27'_far2l0'#27'\', 'deactivate');
    Check(not C.Acknowledged and not C.Supported and (C.ProbeState = ppIdle), 'deactivate: state is forgotten');
    T.Wire := '';
    C.Terminator := tmBel;
    C.Deactivate;
    C.SendHostIdentity('u@h');
    Check(T.Wire = #27'_far2l0'#7#27'_far2l#u@h'#7, 'BEL as the terminator');
  finally
    C.Free;
    T.Free;
  end;
end;

const
  { The samples whose IDs are 1 to 6 in turn, and the replies that the document gives for them. }
  FlowSamples: array[0..5] of Integer = (4, 5, 6, 8, 9, 10);
  FlowReplies: array[0..5] of AnsiString = (
    'AwAAAAAAAAABAQ==', 'iHdmVUQzIhEBAg==', 'iHdmVUQzIhFoZWxsbwUAAAAD', 'AMAAAAQ=', 'AwsAAAAAAAAIABAABQ==',
    'AQY=');

procedure TestClientReplies;
var
  T: TTally;
  C: TFar2lClient;
  Id, Spare: Byte;
  K, Half: Integer;
  Sent: AnsiString;
begin
  T := TTally.Create;
  C := TFar2lClient.Create(@T.Put);
  C.OnAnswer := @T.GotAnswer;
  try
    for K := 0 to 5 do
    begin
      Check(C.Submit(SampleRequest(FlowSamples[K], Spare), True, Id) and (Id = K + 1),
        'flow: ID of request ' + IntToStr(K));
      Check(C.IsPending(K + 1), 'flow: request ' + IntToStr(K) + ' waits');
    end;
    Sent := T.Wire;
    Check(Copy(Sent, 1, 40) = Copy(WrapRequest(FromHex(SampleStacks[4])), 1, 40), 'flow: the first string sent');
    Check(C.InFlightCount = 6, 'flow: six requests wait');
    Check(not C.IsPending(0) and not C.IsPending(7), 'flow: no others wait');

    for K := 0 to 5 do
    begin
      Half := Length(FlowReplies[K]) div 2;
      C.Feed(#27'_far2l' + Copy(FlowReplies[K], 1, Half));
      C.Feed(Copy(FlowReplies[K], Half + 1, Length(FlowReplies[K])) + #7);
    end;
    Check(Length(T.Answers) = 6, 'flow: six answers');
    Check(C.InFlightCount = 0, 'flow: nothing waits any more');
    Check(T.Wire = Sent, 'flow: replies write nothing');
    if Length(T.Answers) = 6 then
    begin
      for K := 0 to 5 do
        Check(T.Answers[K].Valid and (T.Answers[K].Id = K + 1), 'flow: answer ' + IntToStr(K) + ' is for its ID');
      Check((T.Answers[0].Kind = rqClipOpen) and (T.Answers[0].Status = 1) and (T.Answers[0].Wide = 3),
        'flow: open');
      Check(C.ServerClipFeatures = 3, 'flow: features are kept');
      Check((T.Answers[1].Kind = rqClipSetData) and (T.Answers[1].Wide = QWord($1122334455667788)),
        'flow: set data with the identifier');
      Check((T.Answers[2].Kind = rqClipGetData) and (T.Answers[2].Data = 'hello') and (T.Answers[2].Number = 5) and
        (T.Answers[2].Wide = QWord($1122334455667788)), 'flow: get data');
      Check((T.Answers[3].Kind = rqClipRegister) and (T.Answers[3].Number = $C000), 'flow: register');
      Check((T.Answers[4].Kind = rqImageCaps) and (T.Answers[4].Height = 16) and (T.Answers[4].Width = 8) and
        (T.Answers[4].Wide = $B03), 'flow: caps');
      Check((T.Answers[5].Kind = rqImageSet) and T.Answers[5].Flag, 'flow: image set');
    end;

    { A reply whose ID does not wait, an ID of 0 and a late acknowledgement are not answers. }
    C.Feed(BelWire('far2l', 'AQY='));
    C.Feed(BelWire('far2l', 'AA=='));
    C.Feed(BelWire('far2l', 'ok'));
    Check((C.Strays = 2) and (Length(T.Answers) = 6), 'stray replies are counted and ignored');
  finally
    C.Free;
    T.Free;
  end;

  T := TTally.Create;
  C := TFar2lClient.Create(@T.Put);
  C.OnAnswer := @T.GotAnswer;
  try
    C.Submit(PlainRequest(rqMaxSize), True, Id);
    C.Feed(BelWire('far2l', 'yAAyAAE='));
    Check((Length(T.Answers) = 1) and (T.Answers[0].Kind = rqMaxSize) and (T.Answers[0].Height = 50) and
      (T.Answers[0].Width = 200), 'maximum size answered');
    C.Submit(SampleRequest(3, Spare), True, Id);
    C.Feed(BelWire('far2l', 'AQI='));
    Check((Length(T.Answers) = 2) and (T.Answers[1].Kind = rqFKeyTitles) and T.Answers[1].Flag and (Id = 2),
      'titles of the keys answered, with the next ID');
    C.Submit(PlainRequest(rqMaxSize), True, Id);
    C.Feed(BelWire('far2l', 'AwM='));
    Check((Length(T.Answers) = 3) and (T.Answers[2].Kind = rqMaxSize) and not T.Answers[2].Valid,
      'an answer without its values is not valid');
  finally
    C.Free;
    T.Free;
  end;
end;

procedure TestInFlight;
var
  T: TTally;
  C: TFar2lClient;
  Id: Byte;
  K, Used: Integer;
  Marked: SizeInt;
  AllBad: Boolean;
begin
  T := TTally.Create;
  C := TFar2lClient.Create(@T.Put);
  C.OnAnswer := @T.GotAnswer;
  try
    Used := 0;
    for K := 1 to MaxRequestsInFlight do
      if C.Submit(PlainRequest(rqMaxSize), True, Id) then
        Inc(Used);
    Check(Used = 255, 'in flight: 255 requests are taken');
    Check(C.InFlightCount = 255, 'in flight: and 255 wait');
    Marked := Length(T.Wire);
    Check(not C.Submit(PlainRequest(rqMaxSize), True, Id), 'in flight: the 256th is refused');
    Check((Length(T.Wire) = Marked) and (Id = 0), 'in flight: nothing is sent for it');
    Check(C.Submit(PlainRequest(rqQuickEdit), False, Id) and (Id = 0), 'in flight: a request without a reply goes');
    Check(Length(T.Wire) > Marked, 'in flight: and is written');

    C.Feed(BelWire('far2l', 'AQ=='));
    Check(Length(T.Answers) = 1, 'in flight: one reply frees one ID');
    Check(C.Submit(PlainRequest(rqPalette), True, Id) and (Id = 1), 'in flight: the free ID is found again');

    { An event that cannot be read fails every request that waits. }
    C.Feed(BelWire('f2l', ''));
    AllBad := True;
    for K := 1 to Length(T.Answers) - 1 do
      if T.Answers[K].Valid then
        AllBad := False;
    Check(Length(T.Answers) = 256, 'in flight: all waiting requests got an answer');
    Check(AllBad, 'in flight: and none of them is valid');
    Check(C.InFlightCount = 0, 'in flight: none waits any more');
  finally
    C.Free;
    T.Free;
  end;
end;

procedure TestClientEvents;
var
  T: TTally;
  C: TFar2lClient;
begin
  T := TTally.Create;
  C := TFar2lClient.Create(@T.Put);
  C.OnEvent := @T.GotEvent;
  try
    C.Feed(BelWire('f2l', 'AQBBAB4AAAAAAGEAAABL') + BelWire('f2l', 'Wg==') + BelWire('f2l', 'Sw==') +
      BelWire('f2l', 'CgAFAAEAAABt') + #27'_f2lUAAZAFM='#27'\');
    Check(Length(T.Events) = 3, 'events: the unknown and the broken ones are not reported');
    if Length(T.Events) = 3 then
    begin
      Check((T.Events[0].Kind = feKey) and (T.Events[0].VirtualKey = $41), 'events: key first');
      Check((T.Events[1].Kind = feMouse) and (T.Events[1].MouseX = 10), 'events: then the mouse');
      Check((T.Events[2].Kind = feTerminalSize) and (T.Events[2].Columns = 80), 'events: then the size');
    end;
    Check(C.TakePlain = '', 'events: no other bytes');
  finally
    C.Free;
    T.Free;
  end;
end;

procedure TestClipboardUpload;
var
  T: TTally;
  C: TFar2lClient;
  Id: Byte;
  Bodies: TAnsiArray;
  Data: AnsiString;
  Big: SizeInt;
begin
  T := TTally.Create;
  C := TFar2lClient.Create(@T.Put);
  try
    { Without the feature of chunks all the data goes in one request. }
    Data := StringOfChar('x', 2 * ClipChunkSize + 5);
    Check(C.PutClipboardData(CF_TEXT, Data, Id) and (Id = 1), 'upload: one request without the feature');
    Bodies := SplitRequests(T.Wire);
    Check(Length(Bodies) = 1, 'upload: one string is sent');
    if Length(Bodies) = 1 then
      Check(Bodies[0] = Data + FromHex('05 80 00 00 01 00 00 00 73 63 01'), 'upload: size and format of the data');
  finally
    C.Free;
    T.Free;
  end;

  T := TTally.Create;
  C := TFar2lClient.Create(@T.Put);
  C.OnAnswer := @T.GotAnswer;
  try
    C.Submit(RequestClipOpen('0123456789abcdef0123456789abcdef'), True, Id);
    C.Feed(BelWire('far2l', 'AwAAAAAAAAABAQ=='));
    Check(C.ServerClipFeatures = 3, 'upload: features reported');
    T.Wire := '';
    Data := StringOfChar('x', 2 * ClipChunkSize) + 'abcde';
    Check(C.PutClipboardData(CF_TEXT, Data, Id) and (Id = 2), 'upload: with the pieces');
    Bodies := SplitRequests(T.Wire);
    Check(Length(Bodies) = 3, 'upload: two pieces and the rest');
    if Length(Bodies) = 3 then
    begin
      Check(Bodies[0] = StringOfChar('x', ClipChunkSize) + FromHex('40 00 53 63 00'), 'upload: first piece');
      Check(Bodies[1] = Bodies[0], 'upload: second piece');
      Check(Bodies[2] = 'abcde' + FromHex('05 00 00 00 01 00 00 00 73 63 02'), 'upload: the last request');
    end;
    Check(C.IsPending(2) and (C.InFlightCount = 1), 'upload: only the last request waits');

    { Exactly one piece of data is not cut. }
    T.Wire := '';
    Check(C.PutClipboardData(CF_TEXT, StringOfChar('y', ClipChunkSize), Id), 'upload: data of one piece');
    Check(Length(SplitRequests(T.Wire)) = 1, 'upload: sent in one request');
    T.Wire := '';
    Check(C.PutClipboardData(CF_TEXT, '', Id), 'upload: no data');
    Bodies := SplitRequests(T.Wire);
    Check((Length(Bodies) = 1) and (Length(Bodies[0]) = 11), 'upload: an empty request');

    { The sixteenth piece asks for an answer. }
    T.Wire := '';
    Big := 17 * ClipChunkSize + 1;
    Data := StringOfChar('z', Big);
    Check(C.PutClipboardData(CF_HTML, Data, Id), 'upload: seventeen pieces');
    Bodies := SplitRequests(T.Wire);
    Check(Length(Bodies) = 18, 'upload: seventeen pieces and the rest');
    if Length(Bodies) = 18 then
    begin
      Check(Bodies[14][Length(Bodies[14])] = #0, 'upload: the fifteenth piece has ID 0');
      Check(Bodies[15][Length(Bodies[15])] <> #0, 'upload: the sixteenth has an ID');
      Check(Bodies[16][Length(Bodies[16])] = #0, 'upload: the seventeenth has ID 0');
      Check(Bodies[17] = 'z' + FromHex('01 00 00 00 0f 00 00 00 73 63') + Chr(Id), 'upload: the rest and its ID');
    end;
    Check(C.InFlightCount >= 2, 'upload: the sixteenth piece and the rest wait');
  finally
    C.Free;
    T.Free;
  end;
end;

{ The pipe that stands for the terminal. Reads do not wait. }
procedure TestConsole;
var
  Fds: TFilDes;
  Con: ConsoleCtl;
  C: TFar2lClient;
  Chunk: array[0..1023] of AnsiChar;
  Got: TSsize;
  Part, Seen: AnsiString;
  Spare: Byte;
begin
  Check(fpPipe(Fds) = 0, 'console: pipe made');
  fpFcntl(Fds[0], F_SETFL, O_NONBLOCK);
  Con := ConsoleCtl.GetInstance;
  Con.UseDescriptors(Fds[0], Fds[1]);
  C := TFar2lClient.CreateForConsole(Con);
  try
    C.Probe;
    C.Submit(RequestCursorHeight(50), False, Spare);
  finally
    C.Free;
  end;
  Seen := '';
  repeat
    Got := fpRead(Fds[0], PAnsiChar(@Chunk[0]), SizeOf(Chunk));
    if Got > 0 then
    begin
      SetString(Part, PAnsiChar(@Chunk[0]), Got);
      Seen := Seen + Part;
    end;
  until Got <= 0;
  Check(Seen = #27'_far2l1'#27'\'#27'[5n' + #27'_far2l:MmgA'#27'\', 'console: bytes written through ConsoleCtl');
  fpClose(Fds[0]);
  fpClose(Fds[1]);
  ConsoleCtl.DestroyInstance;
end;

begin
  TestStack;
  TestFraming;
  TestRequests;
  TestMoreRequests;
  TestAnswers;
  TestEvents;
  TestDecoder;
  TestToEvent;
  TestProbe;
  TestClientReplies;
  TestInFlight;
  TestClientEvents;
  TestClipboardUpload;
  TestConsole;
  Done;
end.
