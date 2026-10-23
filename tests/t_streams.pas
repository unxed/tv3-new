{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/tobjstrm.h, source/tvision/tobjstrm.cpp, source/tvision/strmstat.cpp
  See COPYRIGHT.magiblot. }
program t_streams;

{$mode objfpc}
{$POINTERMATH ON}

uses
  SysUtils, ctypes, TvObjs, TvStreams;

{$I testlib.inc}

type
  { A streamable object with a number and a pointer to another one. }
  TNode = class(TStreamable)
  public
    Value: LongInt;
    Child: TNode;
    constructor Make(AValue: LongInt; AChild: TNode);
  protected
    function StreamableName: PChar; override;
    function Read(S: ipstream): Pointer; override;
    procedure Write(S: opstream); override;
  end;

  { A streamable object with a short number and a string. }
  TLabel = class(TStreamable)
  public
    X: SmallInt;
    Text: AnsiString;
    constructor Make(AX: SmallInt; const AText: AnsiString);
  protected
    function StreamableName: PChar; override;
    function Read(S: ipstream): Pointer; override;
    procedure Write(S: opstream); override;
  end;

  { A type that is never registered. }
  TUnreg = class(TStreamable)
  public
    Reads: Integer;
  protected
    function StreamableName: PChar; override;
    function Read(S: ipstream): Pointer; override;
    procedure Write(S: opstream); override;
  end;

  { Reaches the registry of the types. }
  TAccess = class(pstream)
  public
    class function Lookup(N: PChar): TStreamableClass;
  end;

var
  RegNode, RegLabel, RegSecond: TStreamableClass;

constructor TNode.Make(AValue: LongInt; AChild: TNode);
begin
  inherited Create;
  Value := AValue;
  Child := AChild;
end;

function TNode.StreamableName: PChar;
begin
  Result := 'TNode';
end;

function TNode.Read(S: ipstream): Pointer;
var
  P: Pointer;
begin
  S.Get(Value);
  P := nil;
  S.Get(P);
  Child := TNode(P);
  Result := Self;
end;

procedure TNode.Write(S: opstream);
begin
  S.Put(Value);
  S.Put(TStreamable(Child));
end;

constructor TLabel.Make(AX: SmallInt; const AText: AnsiString);
begin
  inherited Create;
  X := AX;
  Text := AText;
end;

function TLabel.StreamableName: PChar;
begin
  Result := 'TLabel';
end;

function TLabel.Read(S: ipstream): Pointer;
var
  Buf: array[0..63] of AnsiChar;
begin
  S.Get(X);
  if S.ReadString(@Buf[0], SizeOf(Buf)) <> nil then
    Text := AnsiString(PChar(@Buf[0]))
  else
    Text := '?';
  Result := Self;
end;

procedure TLabel.Write(S: opstream);
begin
  S.Put(X);
  S.WriteString(Text);
end;

function TUnreg.StreamableName: PChar;
begin
  Result := 'TUnreg';
end;

function TUnreg.Read(S: ipstream): Pointer;
begin
  Inc(Reads);
  Result := Self;
end;

procedure TUnreg.Write(S: opstream);
begin
end;

class function TAccess.Lookup(N: PChar): TStreamableClass;
begin
  Result := Types.Lookup(N);
end;

function BuildNode: TStreamable;
begin
  Result := TNode.Create;
end;

function BuildLabel: TStreamable;
begin
  Result := TLabel.Create;
end;

{ The byte I of the memory buffer. }
function Bt(M: TMemBuf; I: SizeInt): Byte;
var
  P: PByte;
begin
  P := M.Data;
  Result := P[I];
end;

{ Moves the position of the buffer to the start. }
procedure Rewind(B: TStreamBuf);
begin
  B.PubSeekOff(0, iosBeg);
end;

{ Tells whether reading a pointer from S ends by Abort. }
function GetAborts(S: ipstream): Boolean;
var
  P: Pointer;
begin
  Result := False;
  P := nil;
  try
    S.Get(P);
  except
    on EAbort do
      Result := True;
  end;
end;

function TempName(const Suffix: AnsiString): AnsiString;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tvstreams_' + IntToStr(Random(1000000)) + Suffix;
end;

{ The memory buffer: writing, reading, seeking, growing. }
procedure TestMemBuf;
var
  M: TMemBuf;
  B, C: array[0..9] of Byte;
  Big: array[0..999] of Byte;
  I: Integer;
begin
  M := TMemBuf.Create;
  Check(M.SBumpC = -1, 'membuf: empty buffer reads the end');
  Check(M.Size = 0, 'membuf: empty size');
  for I := 0 to 9 do
    B[I] := I + 1;
  Check(M.SPutN(B, 10) = 10, 'membuf: write ten bytes');
  Check(M.Size = 10, 'membuf: size after write');
  Check(M.PubSeekOff(0, iosCur) = 10, 'membuf: position after write');
  Check(M.PubSeekOff(2, iosBeg) = 2, 'membuf: seek from the start');
  Check(M.SBumpC = 3, 'membuf: byte at 2');
  Check(M.PubSeekOff(-1, iosEnd) = 9, 'membuf: seek from the end');
  Check(M.SBumpC = 10, 'membuf: last byte');
  Check(M.SBumpC = -1, 'membuf: end after the last byte');
  Check(M.PubSeekOff(11, iosBeg) = -1, 'membuf: seek past the end fails');
  Check(M.PubSeekOff(-1, iosBeg) = -1, 'membuf: seek before the start fails');
  Check(M.PubSeekOff(0, 7) = -1, 'membuf: unknown direction fails');
  Check(M.PubSeekOff(0, iosCur) = 10, 'membuf: failed seeks keep the position');
  M.PubSeekOff(5, iosBeg);
  FillChar(C, SizeOf(C), 0);
  Check(M.SGetN(C, 10) = 5, 'membuf: short read');
  Check((C[0] = 6) and (C[4] = 10) and (C[5] = 0), 'membuf: short read bytes');
  M.PubSeekOff(1, iosBeg);
  Check(M.SPutC(99) = 99, 'membuf: write one byte');
  Check(M.Size = 10, 'membuf: overwrite keeps the size');
  M.PubSeekOff(0, iosBeg);
  Check((M.SBumpC = 1) and (M.SBumpC = 99) and (M.SBumpC = 3), 'membuf: overwritten bytes');
  Check(M.PubSync = 0, 'membuf: sync');
  for I := 0 to 999 do
    Big[I] := I mod 251;
  M.PubSeekOff(0, iosEnd);
  Check(M.SPutN(Big, 1000) = 1000, 'membuf: write a thousand bytes');
  Check(M.Size = 1010, 'membuf: grown size');
  M.PubSeekOff(10, iosBeg);
  Check((M.SBumpC = 0) and (M.SBumpC = 1), 'membuf: grown bytes');
  M.PubSeekOff(1009, iosBeg);
  Check(M.SBumpC = 999 mod 251, 'membuf: last grown byte');
  M.Reset;
  Check(M.Size = 0, 'membuf: reset size');
  Check(M.SBumpC = -1, 'membuf: reset reads the end');
  M.Free;
end;

{ Bytes, words, strings and blocks. }
procedure TestPrimitives;
var
  M: TMemBuf;
  Wr: opstream;
  Rd: ipstream;
  Buf: array[0..15] of AnsiChar;
  Blk, Got: array[0..4] of Byte;
  PS: PChar;
  Long300: AnsiString;
  Before: SizeInt;
  I: Integer;
begin
  M := TMemBuf.Create;
  Wr := opstream.Create(M);
  Rd := ipstream.Create(M);
  Check(Wr.Rdbuf = M, 'primitives: the stream keeps its buffer');
  Wr.WriteByte(7);
  Wr.WriteWord($1234);
  Wr.WriteString(PChar('abc'));
  Wr.WriteString(AnsiString('hello'));
  Wr.WriteString(PChar(nil));
  Wr.WriteString(AnsiString(''));
  Check(M.Size = 15, 'primitives: size');
  Check(Wr.Tellp = 15, 'primitives: Tellp');
  Check((Bt(M, 0) = 7) and (Bt(M, 1) = $34) and (Bt(M, 2) = $12), 'primitives: byte and word, low byte first');
  Check((Bt(M, 3) = 3) and (Bt(M, 4) = Ord('a')) and (Bt(M, 6) = Ord('c')), 'primitives: string with length byte');
  Check((Bt(M, 7) = 5) and (Bt(M, 8) = Ord('h')), 'primitives: second string');
  Check(Bt(M, 13) = 255, 'primitives: the null string is the length 255');
  Check(Bt(M, 14) = 0, 'primitives: the empty string is the length 0');
  Check(Rd.Seekg(0) = Rd, 'primitives: Seekg returns the stream');
  Check(Rd.Tellg = 0, 'primitives: Tellg at the start');
  Check(Rd.ReadByte = 7, 'primitives: ReadByte');
  Check(Rd.ReadWord = $1234, 'primitives: ReadWord');
  PS := Rd.ReadString;
  Check((PS <> nil) and (AnsiString(PS) = 'abc'), 'primitives: ReadString');
  FreeMem(PS);
  Check(Rd.ReadString(@Buf[0], SizeOf(Buf)) = @Buf[0], 'primitives: ReadString into a buffer');
  Check(AnsiString(PChar(@Buf[0])) = 'hello', 'primitives: ReadString into a buffer, text');
  Check(Rd.ReadString = nil, 'primitives: the null string reads as nil');
  PS := Rd.ReadString;
  Check((PS <> nil) and (PS^ = #0), 'primitives: the empty string');
  FreeMem(PS);
  Check(Rd.Tellg = 15, 'primitives: Tellg at the end');
  Check(Rd.ReadByte = 255, 'primitives: ReadByte at the end');
  Check(Rd.ReadWord = 0, 'primitives: ReadWord at the end');

  { A string that does not fit is not read; its bytes stay. }
  Wr.WriteString(PChar('toolongvalue'));
  Rd.Seekg(15);
  Check(Rd.ReadString(@Buf[0], 4) = nil, 'primitives: a string that does not fit');
  Check(Rd.ReadByte = Ord('t'), 'primitives: the text of the string stays');
  Rd.Seekg(15);
  Check(Rd.ReadString(@Buf[0], 13) <> nil, 'primitives: a string that fits exactly');
  Check(AnsiString(PChar(@Buf[0])) = 'toolongvalue', 'primitives: text that fits exactly');

  { A string of more than 254 bytes is cut. }
  Long300 := StringOfChar('x', 300);
  Before := M.Size;
  Wr.WriteString(Long300);
  Check(M.Size - Before = 255, 'primitives: a long string is cut to 254 bytes');
  Check(Bt(M, Before) = 254, 'primitives: length byte of a cut string');
  Rd.Seekg(Before);
  PS := Rd.ReadString;
  Check((PS <> nil) and (Length(AnsiString(PS)) = 254), 'primitives: a cut string reads back');
  FreeMem(PS);

  { Blocks. }
  for I := 0 to 4 do
    Blk[I] := 10 * I;
  Before := M.Size;
  Wr.WriteBytes(Blk, 5);
  Check(M.Size - Before = 5, 'primitives: WriteBytes');
  Rd.Seekg(Before);
  FillChar(Got, SizeOf(Got), 0);
  Rd.ReadBytes(Got, 5);
  Check((Got[0] = 0) and (Got[2] = 20) and (Got[4] = 40), 'primitives: ReadBytes');

  { Seeks from the current position and from the end. }
  Check(Wr.Seekp(2, iosBeg) = Wr, 'primitives: Seekp returns the stream');
  Check(Wr.Tellp = 2, 'primitives: Seekp from the start');
  Wr.Seekp(1, iosCur);
  Check(Wr.Tellp = 3, 'primitives: Seekp from the current position');
  Wr.Seekp(0, iosEnd);
  Check(Wr.Tellp = M.Size, 'primitives: Seekp to the end');
  Check(Wr.Flush = Wr, 'primitives: Flush returns the stream');
  Rd.Seekg(-1, iosEnd);
  Check(Rd.ReadByte = 40, 'primitives: Seekg from the end');
  Rd.Seekg(3, iosBeg);
  Rd.Seekg(2, iosCur);
  Check(Rd.Tellg = 5, 'primitives: Seekg from the current position');

  Rd.Free;
  Wr.Free;
  M.Free;
end;

{ Numbers of every size. }
procedure TestNumbers;
var
  M: TMemBuf;
  Wr: opstream;
  Rd: ipstream;
  C1, C2: AnsiChar;
  S1, S2: ShortInt;
  B1, B2: Byte;
  W1, W2: SmallInt;
  U1, U2: Word;
  L1, L2: LongInt;
  D1, D2: LongWord;
  G1, G2: CLong;
  H1, H2: CULong;
  F1, F2: Single;
  R1, R2: Double;
  E1, E2: Extended;
  Expect: SizeInt;
begin
  M := TMemBuf.Create;
  Wr := opstream.Create(M);
  Rd := ipstream.Create(M);
  C1 := 'Z';
  S1 := -3;
  B1 := 200;
  W1 := -2;
  U1 := 60000;
  L1 := -100000;
  D1 := $DEADBEEF;
  G1 := -123456789;
  H1 := 4000000000;
  F1 := 1.5;
  R1 := -2.75;
  E1 := 1234.5;
  Check(Wr.Put(C1).Put(S1).Put(B1) = Wr, 'numbers: Put returns the stream');
  Wr.Put(W1).Put(U1).Put(L1).Put(D1);
  Wr.PutLong(G1).PutULong(H1);
  Wr.Put(F1).Put(R1).Put(E1);
  Expect := 1 + 1 + 1 + 2 + 2 + 4 + 4 + SizeOf(CLong) + SizeOf(CULong) + 4 + 8 + SizeOf(Extended);
  Check(M.Size = Expect, 'numbers: sizes of the types');
  Check((Bt(M, 0) = Ord('Z')) and (Bt(M, 1) = $FD) and (Bt(M, 2) = 200), 'numbers: one byte values');
  Check((Bt(M, 3) = $FE) and (Bt(M, 4) = $FF), 'numbers: SmallInt, low byte first');
  Rewind(M);
  Check(Rd.Get(C2).Get(S2).Get(B2) = Rd, 'numbers: Get returns the stream');
  Rd.Get(W2).Get(U2).Get(L2).Get(D2);
  Rd.GetLong(G2).GetULong(H2);
  Rd.Get(F2).Get(R2).Get(E2);
  Check(C2 = C1, 'numbers: AnsiChar');
  Check(S2 = S1, 'numbers: ShortInt');
  Check(B2 = B1, 'numbers: Byte');
  Check(W2 = W1, 'numbers: SmallInt');
  Check(U2 = U1, 'numbers: Word');
  Check(L2 = L1, 'numbers: LongInt');
  Check(D2 = D1, 'numbers: LongWord');
  Check(G2 = G1, 'numbers: long');
  Check(H2 = H1, 'numbers: unsigned long');
  Check(F2 = F1, 'numbers: Single');
  Check(R2 = R1, 'numbers: Double');
  Check(E2 = E1, 'numbers: Extended');
  Check(Rd.Tellg = Expect, 'numbers: everything is read');
  Rd.Free;
  Wr.Free;
  M.Free;
end;

{ Objects of registered types: the layout, references, nil and the read back. }
procedure TestObjects;
var
  M: TMemBuf;
  Wr: opstream;
  Rd: ipstream;
  A, B, T: TNode;
  Lab: TLabel;
  P1, P2, P3: Pointer;
  Before: SizeInt;
  Back: TNode;
begin
  M := TMemBuf.Create;
  Wr := opstream.Create(M);
  Rd := ipstream.Create(M);

  { A node without a child: the object mark, the type name, the value, the null mark and the end mark. }
  A := TNode.Make(1, nil);
  Wr.Put(A);
  Check(M.Size = 14, 'objects: layout of a pointer to an object');
  Check((Bt(M, 0) = Ord(ptObject)) and (Bt(M, 1) = Ord('[')) and (Bt(M, 2) = 5), 'objects: prefix');
  Check((Bt(M, 3) = Ord('T')) and (Bt(M, 7) = Ord('e')), 'objects: type name');
  Check(Bt(M, 8) = 1, 'objects: value');
  Check(Bt(M, 12) = Ord(ptNull), 'objects: null child');
  Check(Bt(M, 13) = Ord(']'), 'objects: suffix');

  { The same object again is a reference to the first. }
  Before := M.Size;
  Wr.Put(A);
  Check(M.Size - Before = 3, 'objects: a repeated object is a reference');
  Check((Bt(M, Before) = Ord(ptIndexed)) and (Bt(M, Before + 1) = 0) and (Bt(M, Before + 2) = 0),
    'objects: reference to the first object');

  { A nil pointer. }
  Before := M.Size;
  Wr.Put(TStreamable(nil));
  Check((M.Size - Before = 1) and (Bt(M, Before) = Ord(ptNull)), 'objects: nil is the null mark');

  Rewind(M);
  P1 := nil;
  Rd.Get(P1);
  Check(P1 <> nil, 'objects: an object is read');
  T := TNode(P1);
  Check(T is TNode, 'objects: the type of the read object');
  Check((T.Value = 1) and (T.Child = nil), 'objects: values of the read object');
  P2 := nil;
  Rd.Get(P2);
  Check(P2 = P1, 'objects: a reference reads as the same object');
  P3 := Pointer(1);
  Rd.Get(P3);
  Check(P3 = nil, 'objects: the null mark reads as nil');
  Check(Rd.Tellg = M.Size, 'objects: everything is read');
  T.Free;
  A.Free;

  { A node with a child: the child gets the next number. }
  M.Reset;
  Wr.Free;
  Rd.Free;
  Wr := opstream.Create(M);
  Rd := ipstream.Create(M);
  B := TNode.Make(2, nil);
  A := TNode.Make(1, B);
  Wr.Put(A);
  Check(M.Size = 27, 'objects: layout of an object with a child');
  Wr.Put(B);
  Wr.Put(A);
  Check(M.Size = 33, 'objects: two references');
  Check((Bt(M, 27) = Ord(ptIndexed)) and (Bt(M, 28) = 1), 'objects: the child has the number 1');
  Check((Bt(M, 30) = Ord(ptIndexed)) and (Bt(M, 31) = 0), 'objects: the parent has the number 0');
  Rewind(M);
  P1 := nil;
  Rd.Get(P1);
  T := TNode(P1);
  Check((T.Value = 1) and (T.Child <> nil) and (T.Child.Value = 2), 'objects: a child is read');
  P2 := nil;
  Rd.Get(P2);
  Check(P2 = Pointer(T.Child), 'objects: a reference to the child');
  P3 := nil;
  Rd.Get(P3);
  Check(P3 = P1, 'objects: a reference to the parent');
  T.Child.Free;
  T.Free;
  A.Free;
  B.Free;

  { The reference variant writes the object without a pointer mark and reads into an existing object. }
  M.Reset;
  Wr.Free;
  Rd.Free;
  Wr := opstream.Create(M);
  Rd := ipstream.Create(M);
  A := TNode.Make(77, nil);
  Check(Wr.PutObject(A) = Wr, 'objects: PutObject returns the stream');
  Check((M.Size = 13) and (Bt(M, 0) = Ord('[')), 'objects: layout of an object by reference');
  Wr.PutObject(A);
  Check(M.Size = 26, 'objects: PutObject writes the object each time');
  Rewind(M);
  Back := TNode.Make(0, nil);
  Check(Rd.GetObject(Back) = Rd, 'objects: GetObject returns the stream');
  Check(Back.Value = 77, 'objects: GetObject reads into the object');
  Back.Free;
  A.Free;

  { Objects of different types in a row. }
  M.Reset;
  Wr.Free;
  Rd.Free;
  Wr := opstream.Create(M);
  Rd := ipstream.Create(M);
  A := TNode.Make(5, nil);
  Lab := TLabel.Make(-9, 'caption');
  Wr.Put(Lab).Put(A).Put(Lab);
  Rewind(M);
  P1 := nil;
  P2 := nil;
  P3 := nil;
  Rd.Get(P1).Get(P2).Get(P3);
  Check(TObject(P1) is TLabel, 'objects: first type');
  Check(TObject(P2) is TNode, 'objects: second type');
  Check(P3 = P1, 'objects: a repeated label');
  Check((TLabel(P1).X = -9) and (TLabel(P1).Text = 'caption'), 'objects: label values');
  TLabel(P1).Free;
  TNode(P2).Free;
  Lab.Free;
  A.Free;

  Rd.Free;
  Wr.Free;
  M.Free;
end;

{ The tables of objects and the positions. }
procedure TestSeek;
var
  M: TMemBuf;
  Wr: opstream;
  Rd: ipstream;
  A: TNode;
  P1, P2, P3: Pointer;
  Size: SizeInt;
begin
  M := TMemBuf.Create;
  Wr := opstream.Create(M);
  A := TNode.Make(5, nil);

  { After a seek the written objects are forgotten but the numbers go on. }
  Wr.Put(A);
  Check(Wr.Tellp = 14, 'seek: Tellp after an object');
  Wr.Seekp(0);
  Check(Wr.Tellp = 0, 'seek: Seekp');
  Wr.Put(A);
  Check(M.Size = 14, 'seek: the object is written in full again');
  Wr.Put(A);
  Size := M.Size;
  Check(Size = 17, 'seek: and then by reference');
  Check((Bt(M, Size - 3) = Ord(ptIndexed)) and (Bt(M, Size - 2) = 1) and (Bt(M, Size - 1) = 0),
    'seek: the number goes on after a seek');
  Wr.Free;

  { After a seek the read objects are forgotten and the numbers start again. }
  M.Reset;
  Wr := opstream.Create(M);
  Wr.Put(A);
  Wr.Put(A);
  Check(M.Size = 17, 'seek: an object and a reference');
  Rd := ipstream.Create(M);
  Rewind(M);
  P1 := nil;
  Rd.Get(P1);
  Rd.Seekg(0);
  P2 := nil;
  Rd.Get(P2);
  Check(P2 <> P1, 'seek: the object is read anew after a seek');
  P3 := nil;
  Rd.Get(P3);
  Check(P3 = P2, 'seek: a reference after Seekg refers to the new object');
  TNode(P1).Free;
  TNode(P2).Free;
  A.Free;
  Rd.Free;
  Wr.Free;
  M.Free;
end;

{ A stream for reading and writing on one buffer. }
procedure TestIoStream;
var
  M: TMemBuf;
  Io: iopstream;
  A: TNode;
  P: Pointer;
  L: LongInt;
  N: LongInt;
begin
  M := TMemBuf.Create;
  Io := iopstream.Create(M);
  A := TNode.Make(31, nil);
  L := 123456;
  Io.WriteByte(4);
  Io.Put(L);
  Io.Put(A);
  Io.WriteString(PChar('io'));
  Check(Io.Tellp = M.Size, 'iopstream: Tellp');
  Io.Seekg(0);
  Check(Io.ReadByte = 4, 'iopstream: ReadByte');
  Io.Get(N);
  Check(N = L, 'iopstream: Get');
  P := nil;
  Io.Get(P);
  Check((P <> nil) and (TNode(P).Value = 31), 'iopstream: an object');
  TNode(P).Free;
  Check(Io.ReadByte = 2, 'iopstream: length of the string');
  Io.Seekp(0, iosEnd);
  Check(Io.Flush = Io, 'iopstream: Flush');
  A.Free;
  Io.Free;
  M.Free;
end;

{ Faults: a bad mark, a type that is not registered. }
procedure TestErrors;
var
  M: TMemBuf;
  Wr: opstream;
  Rd: ipstream;
  U: TUnreg;
  Aborted: Boolean;
begin
  M := TMemBuf.Create;
  Wr := opstream.Create(M);
  Rd := ipstream.Create(M);

  Wr.WriteByte(9);
  Rewind(M);
  Check(GetAborts(Rd), 'errors: an invalid pointer mark ends by Abort');

  M.Reset;
  Wr.WriteByte(Ord(ptObject));
  Wr.WriteByte(Ord('['));
  Wr.WriteString(PChar('Nope'));
  Rewind(M);
  Check(GetAborts(Rd), 'errors: a type that is not registered cannot be built');

  M.Reset;
  U := TUnreg.Create;
  Aborted := False;
  try
    Wr.PutObject(U);
  except
    on EAbort do
      Aborted := True;
  end;
  Check(Aborted, 'errors: writing an object of a type that is not registered ends by Abort');
  Check((M.Size > 0) and (Bt(M, 0) = Ord('[')), 'errors: the prefix is written before the check');

  { An existing object can be read although its type is not registered. }
  M.Reset;
  Wr.WriteByte(Ord('['));
  Wr.WriteString(PChar('TUnreg'));
  Wr.WriteByte(Ord(']'));
  Rewind(M);
  Rd.GetObject(U);
  Check(U.Reads = 1, 'errors: an object is read into without the registry');
  Check(Rd.Tellg = M.Size, 'errors: the end mark is read');

  U.Free;
  Rd.Free;
  Wr.Free;
  M.Free;
end;

{ The state bits. }
procedure TestState;
var
  M: TMemBuf;
  Rd: ipstream;
begin
  M := TMemBuf.Create;
  Rd := ipstream.Create(M);
  Check(Rd.Good, 'state: a new stream is good');
  Check(Rd.Rdstate = 0, 'state: Rdstate');
  Check((Rd.Eof = 0) and (Rd.&Fail = 0) and (Rd.Bad = 0), 'state: no bit set');
  Check(Rd.OpVoidPtr = Pointer(Rd), 'state: a good stream converts to itself');
  Check(not Rd.OpNot, 'state: a good stream is not negated');
  Rd.Clear(iosEofBit);
  Check((Rd.Eof <> 0) and (Rd.&Fail = 0) and (not Rd.Good), 'state: end of file is not a failure');
  Rd.Clear(iosFailBit);
  Check((Rd.&Fail <> 0) and (Rd.Bad = 0) and (Rd.Eof = 0), 'state: fail');
  Check(Rd.OpVoidPtr = nil, 'state: a failed stream converts to nil');
  Check(Rd.OpNot, 'state: a failed stream is negated');
  Rd.Clear(iosBadBit);
  Check((Rd.Bad <> 0) and (Rd.&Fail <> 0), 'state: bad is also a failure');
  Rd.Clear;
  Check(Rd.Good, 'state: Clear without a value');
  Rd.Clear($1FF);
  Check(Rd.Rdstate = $FF, 'state: Clear keeps the low byte');
  Rd.Free;
  M.Free;
end;

{ The registry of the types. }
procedure TestRegistry;
var
  Reg: TStreamableTypes;
  Zed, Abc, Mid: TStreamableClass;
begin
  Check(TAccess.Lookup('TNode') = RegNode, 'registry: a registered type is found');
  Check(TAccess.Lookup('TLabel') = RegLabel, 'registry: a second type is found');
  Check(TAccess.Lookup('TUnreg') = nil, 'registry: a type that is not registered');
  Check(TAccess.Lookup('TNod') = nil, 'registry: a prefix of a name is not a name');
  Check(TAccess.Lookup('TNodes') = nil, 'registry: a name with more is not a name');
  Check(TAccess.Lookup('tnode') = nil, 'registry: names are case sensitive');
  Check(TAccess.Lookup('') = nil, 'registry: the empty name');
  Check(RegSecond <> RegNode, 'registry: two registrations are two objects');
  Check(TAccess.Lookup('TNode') <> RegSecond, 'registry: the first registration of a name stays');

  Zed := TStreamableClass.Create('Zed', @BuildNode);
  Abc := TStreamableClass.Create('Abc', @BuildNode);
  Mid := TStreamableClass.Create('Mid', @BuildLabel);
  Check(TAccess.Lookup('Zed') = Zed, 'registry: registration by Create');
  Reg := TStreamableTypes.Create;
  Reg.RegisterType(Zed);
  Reg.RegisterType(Abc);
  Reg.RegisterType(Mid);
  Check(Reg.GetCount = 3, 'registry: three types');
  Check((Reg.At(0) = Pointer(Abc)) and (Reg.At(1) = Pointer(Mid)) and (Reg.At(2) = Pointer(Zed)),
    'registry: kept in the order of the names');
  Reg.RegisterType(Abc);
  Check(Reg.GetCount = 3, 'registry: a name is entered once');
  Check(Reg.Lookup('Mid') = Mid, 'registry: lookup in a registry');
  Check(Reg.Lookup('Mi') = nil, 'registry: lookup of a prefix');
  Reg.Free;
end;

{ The streams on files in the temporary directory. }
procedure TestFileStreams;
var
  Name, Name2: AnsiString;
  Wr: ofpstream;
  Rd: ifpstream;
  Io: fpstream;
  A, B: TNode;
  P: Pointer;
  Size: Int64;
  L, N: LongInt;
begin
  Name := TempName('.dat');
  Name2 := TempName('.rw');

  { Writing, then reading. }
  Wr := ofpstream.Create(Name);
  Check(Wr.Good, 'files: ofpstream opens');
  Check(Wr.Rdbuf.Is_open, 'files: the file is open');
  B := TNode.Make(2, nil);
  A := TNode.Make(1, B);
  Wr.WriteByte(1);
  Wr.Put(A);
  Wr.Put(B);
  Wr.WriteString(PChar('end'));
  Size := Wr.Tellp;
  Check(Size = 1 + 27 + 3 + 4, 'files: position after writing');
  Wr.Free;
  Check(FileExists(Name), 'files: the file exists');

  Rd := ifpstream.Create(Name);
  Check(Rd.Good, 'files: ifpstream opens');
  Check(Rd.Rdbuf.Is_open, 'files: the file is open for reading');
  Check(Rd.ReadByte = 1, 'files: ReadByte');
  P := nil;
  Rd.Get(P);
  Check((P <> nil) and (TNode(P).Value = 1) and (TNode(P).Child.Value = 2), 'files: an object');
  TNode(P).Child.Free;
  TNode(P).Free;
  Check(Rd.Tellg = 28, 'files: Tellg');
  Rd.Seekg(0, iosEnd);
  Check(Rd.Tellg = Size, 'files: the file has the written size');
  Check(Rd.ReadByte = 255, 'files: reading at the end');
  Rd.Seekg(Size - 4);
  P := Rd.ReadString;
  Check((P <> nil) and (AnsiString(PChar(P)) = 'end'), 'files: a string');
  FreeMem(P);

  { Close and open again; open twice. }
  Rd.Close;
  Check(Rd.Good and not Rd.Rdbuf.Is_open, 'files: Close');
  Rd.Open(Name);
  Check(Rd.Good and Rd.Rdbuf.Is_open, 'files: Open after Close');
  Check(Rd.ReadByte = 1, 'files: reading after Open');
  Rd.Open(Name);
  Check(Rd.Rdstate = iosFailBit, 'files: Open of an open stream fails');
  Rd.Free;

  { A file that does not exist. }
  Rd := ifpstream.Create(Name + '.none');
  Check(Rd.Bad <> 0, 'files: a missing file is bad');
  Check(Rd.&Fail <> 0, 'files: a missing file fails');
  Check(not Rd.Rdbuf.Is_open, 'files: a missing file is not open');
  Rd.Close;
  Check(Rd.&Fail <> 0, 'files: Close of a stream that is not open fails');
  Rd.Free;
  Rd := ifpstream.Create;
  Check(Rd.Good and not Rd.Rdbuf.Is_open, 'files: a stream without a file is good');
  Rd.Free;

  { Appending, then writing anew. }
  Wr := ofpstream.Create(Name, iosApp);
  Check(Wr.Good, 'files: append opens');
  Wr.WriteByte(9);
  Wr.Free;
  Rd := ifpstream.Create(Name);
  Rd.Seekg(0, iosEnd);
  Check(Rd.Tellg = Size + 1, 'files: append adds to the end');
  Rd.Seekg(Size);
  Check(Rd.ReadByte = 9, 'files: appended byte');
  Rd.Free;
  Wr := ofpstream.Create(Name);
  Wr.Free;
  Rd := ifpstream.Create(Name);
  Rd.Seekg(0, iosEnd);
  Check(Rd.Tellg = 0, 'files: opening for writing empties the file');
  Rd.Free;
  A.Free;
  B.Free;
  DeleteFile(Name);

  { A stream for both. }
  Io := fpstream.Create(Name2, iosIn or iosOut or iosTrunc);
  Check(Io.Good, 'files: fpstream opens');
  L := 424242;
  Io.Put(L);
  Io.WriteString(PChar('abc'));
  Check(Io.Tellp = 8, 'files: fpstream position after writing');
  Check(Io.Tellg = 8, 'files: the position is shared');
  Io.Seekg(0);
  Io.Get(N);
  Check(N = L, 'files: fpstream reads what it wrote');
  Io.Seekp(1);
  Io.WriteByte(0);
  Io.Seekg(0);
  Io.Get(N);
  Check(N = L - (L and $FF00), 'files: fpstream overwrites in the middle');
  Io.Seekp(0, iosEnd);
  Io.WriteByte(77);
  Io.Flush;
  Io.Seekg(-1, iosEnd);
  Check(Io.ReadByte = 77, 'files: fpstream appends at the end');
  Io.Close;
  Check(Io.Good and not Io.Rdbuf.Is_open, 'files: fpstream closes');
  Io.Free;
  Io := fpstream.Create(Name2 + '.none', iosIn or iosOut);
  Check(Io.Bad <> 0, 'files: fpstream on a missing file is bad');
  Io.Free;
  DeleteFile(Name2);
end;

{ The file buffer with a small block. }
procedure TestFileBuf;
var
  Name: AnsiString;
  B: TFileBuf;
  Data, Got: array[0..99] of Byte;
  I: Integer;
begin
  Name := TempName('.buf');
  B := TFileBuf.Create(3);
  Check(not B.Is_open, 'filebuf: not open at first');
  Check(B.SBumpC = -1, 'filebuf: reading a buffer that is not open');
  Check(B.PubSeekOff(0, iosBeg) = -1, 'filebuf: seek of a buffer that is not open');
  Check(not B.Open(Name + '.none', iosIn), 'filebuf: open of a missing file fails');
  Check(not B.Open(Name, 0), 'filebuf: open without a direction fails');
  Check(B.Open(Name, iosIn or iosOut or iosTrunc), 'filebuf: open');
  Check(B.Is_open, 'filebuf: open now');
  Check(not B.Open(Name, iosIn), 'filebuf: open of an open buffer fails');
  for I := 0 to 15 do
    Data[I] := Ord('A') + I;
  Check(B.SPutN(Data, 16) = 16, 'filebuf: write over several blocks');
  Check(B.PubSeekOff(0, iosCur) = 16, 'filebuf: position after write');
  Check(B.PubSeekOff(2, iosBeg) = 2, 'filebuf: seek');
  Check(B.SPutC(Ord('x')) = Ord('x'), 'filebuf: overwrite one byte');
  Check(B.PubSeekOff(0, iosBeg) = 0, 'filebuf: seek to the start');
  FillChar(Got, SizeOf(Got), 0);
  Check(B.SGetN(Got, 16) = 16, 'filebuf: read over several blocks');
  Check((Got[0] = Ord('A')) and (Got[2] = Ord('x')) and (Got[3] = Ord('D')) and (Got[15] = Ord('P')),
    'filebuf: the bytes as written');
  Check(B.SBumpC = -1, 'filebuf: end of the file');
  Check(B.PubSeekOff(0, iosEnd) = 16, 'filebuf: seek to the end');
  Data[0] := Ord('Q');
  Data[1] := Ord('R');
  Check(B.SPutN(Data, 2) = 2, 'filebuf: write at the end');
  Check(B.PubSeekOff(0, iosEnd) = 18, 'filebuf: the end moved');
  Check(B.PubSeekOff(-3, iosEnd) = 15, 'filebuf: seek back from the end');
  FillChar(Got, SizeOf(Got), 0);
  Check(B.SGetN(Got, 10) = 3, 'filebuf: short read at the end');
  Check((Got[0] = Ord('P')) and (Got[1] = Ord('Q')) and (Got[2] = Ord('R')), 'filebuf: bytes at the end');
  Check(B.PubSeekOff(-20, iosCur) = -1, 'filebuf: seek before the start fails');
  Check(B.PubSync = 0, 'filebuf: sync');
  Check(B.Close, 'filebuf: close');
  Check(not B.Close, 'filebuf: close of a closed buffer');
  Check(not B.Is_open, 'filebuf: closed');

  { Reading only. }
  Check(B.Open(Name, iosIn), 'filebuf: open for reading');
  Check(B.SPutC(Ord('z')) = -1, 'filebuf: a buffer for reading cannot write');
  FillChar(Got, SizeOf(Got), 0);
  Check(B.SGetN(Got, 40) = 18, 'filebuf: the file as written');
  Check((Got[2] = Ord('x')) and (Got[17] = Ord('R')), 'filebuf: the bytes after close');
  Check(B.Close, 'filebuf: close after reading');
  B.Free;

  { Writing only; the end position; a block that crosses the file. }
  B := TFileBuf.Create(7);
  Check(B.Open(Name, iosIn or iosOut or iosAte), 'filebuf: open at the end');
  Check(B.PubSeekOff(0, iosCur) = 18, 'filebuf: ate moves to the end');
  Check(B.Close, 'filebuf: close at the end');
  Check(B.Open(Name, iosOut or iosTrunc), 'filebuf: open for writing');
  Check(B.SBumpC = -1, 'filebuf: a buffer for writing cannot read');
  for I := 0 to 99 do
    Data[I] := I;
  Check(B.SPutN(Data, 100) = 100, 'filebuf: write a hundred bytes');
  Check(B.Close, 'filebuf: close after writing');
  Check(B.Open(Name, iosIn or iosOut), 'filebuf: open for both');
  I := 99;
  while I >= 0 do
  begin
    B.PubSeekOff(I, iosBeg);
    if B.SBumpC <> I then
      Check(False, 'filebuf: byte at ' + IntToStr(I));
    Dec(I, 13);
  end;
  B.PubSeekOff(50, iosBeg);
  for I := 0 to 9 do
    Got[I] := 200 + I;
  Check(B.SPutN(Got, 10) = 10, 'filebuf: overwrite ten bytes in the middle');
  Check(B.PubSeekOff(0, iosCur) = 60, 'filebuf: position after the overwrite');
  Check(B.SBumpC = 60, 'filebuf: the byte after the overwrite');
  Check(B.Close, 'filebuf: close after the overwrite');
  B.Free;
  B := TFileBuf.Create;
  Check(B.Open(Name, iosIn), 'filebuf: open again');
  FillChar(Got, SizeOf(Got), 0);
  Check(B.SGetN(Got, 100) = 100, 'filebuf: read the whole file');
  Check((Got[49] = 49) and (Got[50] = 200) and (Got[59] = 209) and (Got[60] = 60) and (Got[99] = 99),
    'filebuf: the file after the overwrite');
  B.Free;
  DeleteFile(Name);

  { Appending. }
  B := TFileBuf.Create(4);
  Check(B.Open(Name, iosOut or iosApp), 'filebuf: open to append');
  Data[0] := 1;
  B.SPutN(Data, 1);
  Check(B.Close, 'filebuf: close after append');
  Check(B.Open(Name, iosOut or iosApp), 'filebuf: open to append again');
  Data[0] := 2;
  B.SPutN(Data, 1);
  Check(B.Close, 'filebuf: close after the second append');
  B.Free;
  B := TFileBuf.Create;
  B.Open(Name, iosIn);
  Check((B.SBumpC = 1) and (B.SBumpC = 2) and (B.SBumpC = -1), 'filebuf: two appends');
  B.Free;
  DeleteFile(Name);
end;

begin
  Randomize;
  RegNode := TStreamableClass.Create('TNode', @BuildNode);
  RegLabel := TStreamableClass.Create('TLabel', @BuildLabel);
  RegSecond := TStreamableClass.Create('TNode', @BuildLabel);
  TestMemBuf;
  TestPrimitives;
  TestNumbers;
  TestObjects;
  TestSeek;
  TestIoStream;
  TestErrors;
  TestState;
  TestRegistry;
  TestFileStreams;
  TestFileBuf;
  Done;
end.
