{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/tobjstrm.h, source/tvision/tobjstrm.cpp, source/tvision/strmstat.cpp
  See COPYRIGHT.magiblot.

  The object streams. The stream buffer of the C++ standard library, which the C++ streams use through the pointer
  bp, is the class TStreamBuf here, with the memory buffer TMemBuf and the file buffer TFileBuf (the filebuf). The
  bits of the state and the open modes of ios are the constants ios... below.

  A class of the C++ with several bases is a single inheritance chain here. TStreamable, which a class of the C++
  adds as a second base besides TObject, is the class from which a streamable class descends; it descends from
  TvObject. iopstream descends from ipstream and holds an opstream on the same buffer for the writing members.
  ifpstream, ofpstream and fpstream descend from ipstream, opstream and iopstream and hold an fpbase, which owns
  the file buffer and sets the state of its stream. The private virtual members of TStreamable and the members that
  are friends of pstream, ipstream and opstream are protected or reachable in this unit.

  The type name registration TStreamableClass(name, build) is TStreamableClass.Create(Name, Build); the function
  that builds an object is a BUILDER, a function that returns a new TStreamable. The registry TStreamableTypes
  is a sorted collection keyed by the name.

  The stream operators >> and << are the overloaded members Get and Put (GetLong and PutLong for long), and
  GetObject and PutObject for the operators of a TStreamable reference. The operators void * and ! are OpVoidPtr
  and OpNot. }
unit TvStreams;

{$mode objfpc}
{$R-}
{$Q-}
{$POINTERMATH ON}

interface

uses
  SysUtils, ctypes, TvObjs;

const
  { The bits of the state of a stream. }
  iosGoodBit = 0;
  iosEofBit = 1;
  iosFailBit = 2;
  iosBadBit = 4;

  { The open modes of a file buffer. }
  iosIn = 1;
  iosOut = 2;
  iosAte = 4;
  iosApp = 8;
  iosTrunc = 16;
  iosBinary = 32;

  { The directions of a seek. }
  iosBeg = 0;
  iosCur = 1;
  iosEnd = 2;

type
  P_id_type = Cardinal;

const
  { The result of a search for an object that is not in the table of written objects. }
  P_id_notFound = High(P_id_type);

type
  { The source and the sink of bytes under a stream, with one position for reading and writing. }
  TStreamBuf = class(TvObject)
  protected
    { Moves the position by Off from Dir (iosBeg, iosCur, iosEnd); returns the new position or -1. }
    function SeekOff(Off: Int64; Dir, Which: Integer): Int64; virtual; abstract;
    { Writes out what is buffered; returns 0, or -1 when it fails. }
    function Sync: Integer; virtual;
    { Reads up to N bytes into Buf; returns the number of bytes read. }
    function XSGetN(var Buf; N: SizeInt): SizeInt; virtual; abstract;
    { Writes N bytes from Buf; returns the number of bytes written. }
    function XSPutN(const Buf; N: SizeInt): SizeInt; virtual; abstract;
  public
    function PubSeekOff(Off: Int64; Dir: Integer; Which: Integer = iosIn or iosOut): Int64;
    function PubSync: Integer;
    { Reads one byte; returns -1 at the end. }
    function SBumpC: Integer;
    function SGetN(var Buf; N: SizeInt): SizeInt;
    { Writes one byte; returns it, or -1 when it cannot be written. }
    function SPutC(C: Byte): Integer;
    function SPutN(const Buf; N: SizeInt): SizeInt;
  end;

  { A buffer in memory that grows as it is written. }
  TMemBuf = class(TStreamBuf)
  private
    FData: PByte;
    FCap: SizeInt;
    FSize: SizeInt;
    FPos: SizeInt;
  protected
    function SeekOff(Off: Int64; Dir, Which: Integer): Int64; override;
    function XSGetN(var Buf; N: SizeInt): SizeInt; override;
    function XSPutN(const Buf; N: SizeInt): SizeInt; override;
  public
    destructor Destroy; override;
    { The number of bytes held. }
    function Size: SizeInt;
    { The bytes held. }
    function Data: PByte;
    { Drops the bytes and moves the position to 0. }
    procedure Reset;
  end;

  { A buffer on a file. It keeps a block of the file in memory and writes it back when the position leaves
    the block, on a seek from the end, on Sync and on Close. }
  TFileBuf = class(TStreamBuf)
  private
    FHandle: THandle;
    FOpened: Boolean;
    FCanRead: Boolean;
    FCanWrite: Boolean;
    FAppend: Boolean;
    FBuf: PByte;
    FSize: Integer;
    FBufStart: Int64;
    FBufLen: Integer;
    FDirty: Boolean;
    FPos: Int64;
    function FlushBuf: Boolean;
  protected
    function SeekOff(Off: Int64; Dir, Which: Integer): Int64; override;
    function Sync: Integer; override;
    function XSGetN(var Buf; N: SizeInt): SizeInt; override;
    function XSPutN(const Buf; N: SizeInt): SizeInt; override;
  public
    constructor Create(ABufSize: Integer = 4096);
    destructor Destroy; override;
    { Opens the file by Mode, a combination of iosIn, iosOut, iosApp, iosTrunc and iosAte; false when it fails
      or the buffer is open already. }
    function Open(const Name: AnsiString; Mode: Integer): Boolean;
    { Writes out the buffer and closes the file; false when it was not open or the write fails. }
    function Close: Boolean;
    function Is_open: Boolean;
  end;

  ipstream = class;
  opstream = class;

  { The base class of all storable objects. }
  TStreamable = class(TvObject)
  protected
    function StreamableName: PChar; virtual; abstract;
    function Read(S: ipstream): Pointer; virtual; abstract;
    procedure Write(S: opstream); virtual; abstract;
  end;

  { Returns a new object of a streamable class. }
  BUILDER = function: TStreamable;

  { The registration of a streamable type: its name and the function that builds an object of it. The
    constructor enters the type into the registry of the streams. }
  TStreamableClass = class(TvObject)
  private
    Name: PChar;
    Build: BUILDER;
  public
    constructor Create(N: PChar; B: BUILDER; Unused: Integer = 0);
  end;

  { The registry of the types of the application, kept in the order of the names. }
  TStreamableTypes = class(TNSSortedCollection)
  protected
    function Compare(Key1, Key2: Pointer): Integer; override;
  public
    constructor Create; reintroduce;
    procedure RegisterType(D: TStreamableClass);
    { The registration of the type with the name, or nil. }
    function Lookup(Name: PChar): TStreamableClass;
    function KeyOf(Item: Pointer): Pointer; override;
  end;

  { An object that was written, with its number. }
  TPWObj = class
  private
    Address: Pointer;
    Ident: P_id_type;
    constructor Create(Adr: Pointer; Id: P_id_type);
  end;

  { The objects written to a stream, kept in the order of their addresses. }
  TPWrittenObjects = class(TNSSortedCollection)
  private
    CurId: P_id_type;
  protected
    function Compare(Key1, Key2: Pointer): Integer; override;
    procedure FreeItem(Item: Pointer); override;
  public
    constructor Create; reintroduce;
    procedure RemoveAll; reintroduce;
    procedure RegisterObject(Adr: Pointer);
    { The number of the object at Adr, or P_id_notFound. }
    function Find(Adr: Pointer): P_id_type;
    function KeyOf(Item: Pointer): Pointer; override;
  end;

  { The objects read from a stream, in the order in which they were read. }
  TPReadObjects = class(TNSCollection)
  private
    CurId: P_id_type;
  public
    constructor Create; reintroduce;
    procedure RemoveAll; reintroduce;
    { Forgets the objects without freeing them. }
    procedure ShutDownKeeping;
    procedure RegisterObject(Adr: Pointer);
    function Find(Id: P_id_type): Pointer;
  end;

  StreamableError = (peNotRegistered, peInvalidType);
  PointerTypes = (ptNull, ptIndexed, ptObject);

  { The base class of the streams of objects. }
  pstream = class(TvObject)
  protected
    Bp: TStreamBuf;
    State: Integer;
    class var Types: TStreamableTypes;
    constructor Create; overload;
    { Writes the message to the error output and ends by Abort. }
    procedure Error(E: StreamableError); overload;
    procedure Error(E: StreamableError; T: TStreamable); overload;
    procedure Init(Sb: TStreamBuf);
    procedure Setstate(B: Integer);
  public
    constructor Create(Sb: TStreamBuf); overload;
    destructor Destroy; override;
    function Rdstate: Integer;
    function Eof: Integer;
    function &Fail: Integer;
    function Bad: Integer;
    function Good: Boolean;
    procedure Clear(I: Integer = 0);
    function OpVoidPtr: Pointer;
    function OpNot: Boolean;
    function Rdbuf: TStreamBuf;
    class procedure InitTypes;
    class procedure RegisterType(Ts: TStreamableClass);
  end;

  { A stream from which objects are read. }
  ipstream = class(pstream)
  private
    Objs: TPReadObjects;
  protected
    constructor Create; overload;
    function ReadPrefix: TStreamableClass;
    function ReadData(C: TStreamableClass; Mem: TStreamable): Pointer;
    procedure ReadSuffix;
    function Find(Id: P_id_type): Pointer;
    procedure RegisterObject(Adr: Pointer);
  public
    constructor Create(Sb: TStreamBuf); overload;
    destructor Destroy; override;
    function Tellg: Int64;
    function Seekg(Pos: Int64): ipstream; overload;
    function Seekg(Off: Int64; Dir: Integer): ipstream; overload;
    function ReadByte: Byte;
    procedure ReadBytes(var Data; Sz: SizeInt);
    function ReadWord: Word;
    { Reads a string into a new block from GetMem, which the caller frees; nil for the null string. }
    function ReadString: PChar; overload;
    { Reads a string into Buf of MaxLen bytes; nil when it does not fit. }
    function ReadString(Buf: PChar; MaxLen: Cardinal): PChar; overload;
    function Get(var V: AnsiChar): ipstream; overload;
    function Get(var V: ShortInt): ipstream; overload;
    function Get(var V: Byte): ipstream; overload;
    function Get(var V: SmallInt): ipstream; overload;
    function Get(var V: Word): ipstream; overload;
    function Get(var V: LongInt): ipstream; overload;
    function Get(var V: LongWord): ipstream; overload;
    function GetLong(var V: CLong): ipstream;
    function GetULong(var V: CULong): ipstream;
    function Get(var V: Single): ipstream; overload;
    function Get(var V: Double): ipstream; overload;
    function Get(var V: Extended): ipstream; overload;
    { Reads an object into T. }
    function GetObject(T: TStreamable): ipstream;
    { Reads a pointer: nil, an object read before, or a new object. }
    function Get(var T: Pointer): ipstream; overload;
  end;

  { A stream to which objects are written. }
  opstream = class(pstream)
  private
    Objs: TPWrittenObjects;
  protected
    constructor Create; overload;
    procedure WritePrefix(T: TStreamable);
    procedure WriteData(T: TStreamable);
    procedure WriteSuffix(T: TStreamable);
    function Find(Adr: Pointer): P_id_type;
    procedure RegisterObject(Adr: Pointer);
  public
    constructor Create(Sb: TStreamBuf); overload;
    destructor Destroy; override;
    function Tellp: Int64;
    function Seekp(Pos: Int64): opstream; overload;
    function Seekp(Off: Int64; Dir: Integer): opstream; overload;
    function Flush: opstream;
    procedure WriteByte(Ch: Byte);
    procedure WriteBytes(const Data; Sz: SizeInt);
    procedure WriteWord(Sh: Word);
    { Writes a string of up to 254 bytes; nil is the null string. }
    procedure WriteString(Str: PChar); overload;
    procedure WriteString(const Str: AnsiString); overload;
    function Put(const V: AnsiChar): opstream; overload;
    function Put(const V: ShortInt): opstream; overload;
    function Put(const V: Byte): opstream; overload;
    function Put(const V: SmallInt): opstream; overload;
    function Put(const V: Word): opstream; overload;
    function Put(const V: LongInt): opstream; overload;
    function Put(const V: LongWord): opstream; overload;
    function PutLong(const V: CLong): opstream;
    function PutULong(const V: CULong): opstream;
    function Put(const V: Single): opstream; overload;
    function Put(const V: Double): opstream; overload;
    function Put(const V: Extended): opstream; overload;
    { Writes the object T with its type name. }
    function PutObject(T: TStreamable): opstream;
    { Writes a pointer: the null mark, the number of an object written before, or the object. }
    function Put(T: TStreamable): opstream; overload;
  end;

  { A stream for reading and writing objects. }
  iopstream = class(ipstream)
  private
    Writer: opstream;
  protected
    constructor Create; overload;
  public
    constructor Create(Sb: TStreamBuf); overload;
    destructor Destroy; override;
    function Tellp: Int64;
    function Seekp(Pos: Int64): iopstream; overload;
    function Seekp(Off: Int64; Dir: Integer): iopstream; overload;
    function Flush: iopstream;
    procedure WriteByte(Ch: Byte);
    procedure WriteBytes(const Data; Sz: SizeInt);
    procedure WriteWord(Sh: Word);
    procedure WriteString(Str: PChar); overload;
    procedure WriteString(const Str: AnsiString); overload;
    function Put(const V: AnsiChar): iopstream; overload;
    function Put(const V: ShortInt): iopstream; overload;
    function Put(const V: Byte): iopstream; overload;
    function Put(const V: SmallInt): iopstream; overload;
    function Put(const V: Word): iopstream; overload;
    function Put(const V: LongInt): iopstream; overload;
    function Put(const V: LongWord): iopstream; overload;
    function PutLong(const V: CLong): iopstream;
    function PutULong(const V: CULong): iopstream;
    function Put(const V: Single): iopstream; overload;
    function Put(const V: Double): iopstream; overload;
    function Put(const V: Extended): iopstream; overload;
    function PutObject(T: TStreamable): iopstream;
    function Put(T: TStreamable): iopstream; overload;
  end;

  { The base of the streams on files: it owns the file buffer and sets the state of its stream. }
  fpbase = class(TvObject)
  private
    Buf: TFileBuf;
    Owner: pstream;
  public
    constructor Create(AOwner: pstream); overload;
    constructor Create(AOwner: pstream; const Name: AnsiString; OMode: Integer); overload;
    destructor Destroy; override;
    procedure Open(const Name: AnsiString; OMode: Integer);
    procedure Close;
    function Rdbuf: TFileBuf;
  end;

  { A stream for reading objects from a file. }
  ifpstream = class(ipstream)
  private
    Base: fpbase;
  public
    constructor Create; overload;
    constructor Create(const Name: AnsiString; OMode: Integer = iosIn); overload;
    destructor Destroy; override;
    function Rdbuf: TFileBuf; reintroduce;
    procedure Open(const Name: AnsiString; OMode: Integer = iosIn);
    procedure Close;
  end;

  { A stream for writing objects to a file. }
  ofpstream = class(opstream)
  private
    Base: fpbase;
  public
    constructor Create; overload;
    constructor Create(const Name: AnsiString; OMode: Integer = iosOut); overload;
    destructor Destroy; override;
    function Rdbuf: TFileBuf; reintroduce;
    procedure Open(const Name: AnsiString; OMode: Integer = iosOut);
    procedure Close;
  end;

  { A stream for reading and writing objects on a file. }
  fpstream = class(iopstream)
  private
    Base: fpbase;
  public
    constructor Create; overload;
    constructor Create(const Name: AnsiString; OMode: Integer); overload;
    destructor Destroy; override;
    function Rdbuf: TFileBuf; reintroduce;
    procedure Open(const Name: AnsiString; OMode: Integer);
    procedure Close;
  end;

implementation

const
  { The length byte of the null string. }
  nullStringLen = High(Byte);

{ TStreamBuf }

function TStreamBuf.Sync: Integer;
begin
  Result := 0;
end;

function TStreamBuf.PubSeekOff(Off: Int64; Dir: Integer; Which: Integer): Int64;
begin
  Result := SeekOff(Off, Dir, Which);
end;

function TStreamBuf.PubSync: Integer;
begin
  Result := Sync;
end;

function TStreamBuf.SBumpC: Integer;
var
  B: Byte;
begin
  if SGetN(B, 1) = 1 then
    Result := B
  else
    Result := -1;
end;

function TStreamBuf.SGetN(var Buf; N: SizeInt): SizeInt;
begin
  Result := XSGetN(Buf, N);
end;

function TStreamBuf.SPutC(C: Byte): Integer;
begin
  if SPutN(C, 1) = 1 then
    Result := C
  else
    Result := -1;
end;

function TStreamBuf.SPutN(const Buf; N: SizeInt): SizeInt;
begin
  Result := XSPutN(Buf, N);
end;

{ TMemBuf }

destructor TMemBuf.Destroy;
begin
  if FData <> nil then
    FreeMem(FData);
  inherited Destroy;
end;

function TMemBuf.Size: SizeInt;
begin
  Result := FSize;
end;

function TMemBuf.Data: PByte;
begin
  Result := FData;
end;

procedure TMemBuf.Reset;
begin
  FSize := 0;
  FPos := 0;
end;

function TMemBuf.SeekOff(Off: Int64; Dir, Which: Integer): Int64;
var
  NewPos: Int64;
begin
  Result := -1;
  case Dir of
    iosBeg: NewPos := Off;
    iosCur: NewPos := FPos + Off;
    iosEnd: NewPos := FSize + Off;
  else
    Exit;
  end;
  if (NewPos < 0) or (NewPos > FSize) then
    Exit;
  FPos := NewPos;
  Result := NewPos;
end;

function TMemBuf.XSGetN(var Buf; N: SizeInt): SizeInt;
begin
  Result := FSize - FPos;
  if Result > N then
    Result := N;
  if Result <= 0 then
  begin
    Result := 0;
    Exit;
  end;
  Move(FData[FPos], Buf, Result);
  Inc(FPos, Result);
end;

function TMemBuf.XSPutN(const Buf; N: SizeInt): SizeInt;
var
  Need: SizeInt;
begin
  Result := 0;
  if N <= 0 then
    Exit;
  Need := FPos + N;
  if Need > FCap then
  begin
    FCap := FCap * 2;
    if FCap < Need then
      FCap := Need;
    if FCap < 64 then
      FCap := 64;
    ReAllocMem(FData, FCap);
  end;
  Move(Buf, FData[FPos], N);
  FPos := Need;
  if FPos > FSize then
    FSize := FPos;
  Result := N;
end;

{ TFileBuf }

constructor TFileBuf.Create(ABufSize: Integer);
begin
  inherited Create;
  if ABufSize < 1 then
    ABufSize := 1;
  FSize := ABufSize;
  GetMem(FBuf, FSize);
end;

destructor TFileBuf.Destroy;
begin
  Close;
  FreeMem(FBuf);
  inherited Destroy;
end;

{ Writes the changed block to the file. }
function TFileBuf.FlushBuf: Boolean;
begin
  Result := True;
  if not FDirty then
    Exit;
  FDirty := False;
  if FileSeek(FHandle, FBufStart, 0) < 0 then
    Result := False
  else if FileWrite(FHandle, FBuf^, FBufLen) <> FBufLen then
    Result := False;
end;

function TFileBuf.Is_open: Boolean;
begin
  Result := FOpened;
end;

function TFileBuf.Open(const Name: AnsiString; Mode: Integer): Boolean;
var
  H: THandle;
begin
  Result := False;
  if FOpened then
    Exit;
  if (Mode and iosOut) <> 0 then
  begin
    if (Mode and iosIn) <> 0 then
    begin
      if (Mode and iosTrunc) <> 0 then
        H := FileCreate(Name)
      else
        H := FileOpen(Name, fmOpenReadWrite);
    end
    else if (Mode and iosApp) <> 0 then
    begin
      H := FileOpen(Name, fmOpenReadWrite);
      if H = THandle(-1) then
        H := FileCreate(Name);
    end
    else
      H := FileCreate(Name);
  end
  else if (Mode and iosIn) <> 0 then
    H := FileOpen(Name, fmOpenRead)
  else
    Exit;
  if H = THandle(-1) then
    Exit;
  FHandle := H;
  FOpened := True;
  FCanRead := (Mode and iosIn) <> 0;
  FCanWrite := (Mode and iosOut) <> 0;
  FAppend := (Mode and iosApp) <> 0;
  FBufStart := 0;
  FBufLen := 0;
  FDirty := False;
  FPos := 0;
  if (Mode and iosAte) <> 0 then
    FPos := FileSeek(FHandle, Int64(0), 2);
  Result := True;
end;

function TFileBuf.Close: Boolean;
begin
  Result := False;
  if not FOpened then
    Exit;
  Result := FlushBuf;
  FileClose(FHandle);
  FOpened := False;
  FBufLen := 0;
end;

function TFileBuf.Sync: Integer;
begin
  if FOpened and not FlushBuf then
    Result := -1
  else
    Result := 0;
end;

function TFileBuf.SeekOff(Off: Int64; Dir, Which: Integer): Int64;
var
  NewPos: Int64;
begin
  Result := -1;
  if not FOpened then
    Exit;
  case Dir of
    iosBeg: NewPos := Off;
    iosCur: NewPos := FPos + Off;
    iosEnd:
      begin
        if not FlushBuf then
          Exit;
        NewPos := FileSeek(FHandle, Int64(0), 2) + Off;
      end;
  else
    Exit;
  end;
  if NewPos < 0 then
    Exit;
  FPos := NewPos;
  Result := NewPos;
end;

function TFileBuf.XSGetN(var Buf; N: SizeInt): SizeInt;
var
  Dst: PByte;
  Got, Take: SizeInt;
begin
  Result := 0;
  if (not FOpened) or (not FCanRead) then
    Exit;
  Dst := @Buf;
  while N > 0 do
  begin
    if (FPos < FBufStart) or (FPos >= FBufStart + FBufLen) then
    begin
      { The position is outside the block: write the block back and read the one that starts here. }
      if not FlushBuf then
        Exit;
      FBufStart := FPos;
      FBufLen := 0;
      if FileSeek(FHandle, FPos, 0) < 0 then
        Exit;
      Got := FileRead(FHandle, FBuf^, FSize);
      if Got <= 0 then
        Exit;
      FBufLen := Got;
    end;
    Take := FBufStart + FBufLen - FPos;
    if Take > N then
      Take := N;
    Move(FBuf[FPos - FBufStart], Dst^, Take);
    Inc(FPos, Take);
    Inc(Dst, Take);
    Dec(N, Take);
    Inc(Result, Take);
  end;
end;

function TFileBuf.XSPutN(const Buf; N: SizeInt): SizeInt;
var
  Src: PByte;
  Off: Int64;
  Take: SizeInt;
begin
  Result := 0;
  if (not FOpened) or (not FCanWrite) then
    Exit;
  if FAppend then
  begin
    if not FlushBuf then
      Exit;
    FPos := FileSeek(FHandle, Int64(0), 2);
  end;
  Src := @Buf;
  while N > 0 do
  begin
    Off := FPos - FBufStart;
    if (Off < 0) or (Off >= FSize) or (Off > FBufLen) then
    begin
      { The position is outside the block and not next to its end: start a block here. }
      if not FlushBuf then
        Exit;
      FBufStart := FPos;
      FBufLen := 0;
      Off := 0;
    end;
    Take := FSize - Off;
    if Take > N then
      Take := N;
    Move(Src^, FBuf[Off], Take);
    if Off + Take > FBufLen then
      FBufLen := Off + Take;
    FDirty := True;
    Inc(FPos, Take);
    Inc(Src, Take);
    Dec(N, Take);
    Inc(Result, Take);
  end;
end;

{ TStreamableClass }

constructor TStreamableClass.Create(N: PChar; B: BUILDER; Unused: Integer);
begin
  inherited Create;
  Name := N;
  Build := B;
  pstream.InitTypes;
  pstream.RegisterType(Self);
end;

{ TStreamableTypes }

constructor TStreamableTypes.Create;
begin
  inherited Create(5, 5);
end;

procedure TStreamableTypes.RegisterType(D: TStreamableClass);
begin
  Insert(D);
end;

function TStreamableTypes.Lookup(Name: PChar): TStreamableClass;
var
  Loc: ccIndex;
begin
  if Search(Name, Loc) then
    Result := TStreamableClass(At(Loc))
  else
    Result := nil;
end;

function TStreamableTypes.KeyOf(Item: Pointer): Pointer;
begin
  Result := TStreamableClass(Item).Name;
end;

{ Compares the names as strcmp does, byte by byte. }
function TStreamableTypes.Compare(Key1, Key2: Pointer): Integer;
var
  P1, P2: PByte;
begin
  P1 := Key1;
  P2 := Key2;
  while (P1^ <> 0) and (P1^ = P2^) do
  begin
    Inc(P1);
    Inc(P2);
  end;
  Result := Integer(P1^) - Integer(P2^);
end;

{ TPWrittenObjects }

constructor TPWrittenObjects.Create;
begin
  inherited Create(5, 5);
  CurId := 0;
end;

procedure TPWrittenObjects.RemoveAll;
begin
  CurId := 0;
  FreeAll;
end;

procedure TPWrittenObjects.RegisterObject(Adr: Pointer);
var
  O: TPWObj;
  Loc: ccIndex;
begin
  O := TPWObj.Create(Adr, CurId);
  Inc(CurId);
  Loc := Insert(O);
  { An address that is in the table already keeps its first number. }
  if At(Loc) <> Pointer(O) then
    O.Free;
end;

function TPWrittenObjects.Find(Adr: Pointer): P_id_type;
var
  Loc: ccIndex;
begin
  if Search(Adr, Loc) then
    Result := TPWObj(At(Loc)).Ident
  else
    Result := P_id_notFound;
end;

function TPWrittenObjects.KeyOf(Item: Pointer): Pointer;
begin
  Result := TPWObj(Item).Address;
end;

function TPWrittenObjects.Compare(Key1, Key2: Pointer): Integer;
begin
  if Key1 = Key2 then
    Result := 0
  else if PtrUInt(Key1) < PtrUInt(Key2) then
    Result := -1
  else
    Result := 1;
end;

procedure TPWrittenObjects.FreeItem(Item: Pointer);
begin
  TPWObj(Item).Free;
end;

{ TPWObj }

constructor TPWObj.Create(Adr: Pointer; Id: P_id_type);
begin
  inherited Create;
  Address := Adr;
  Ident := Id;
end;

{ TPReadObjects }

constructor TPReadObjects.Create;
begin
  inherited Create(5, 5);
  CurId := 0;
end;

procedure TPReadObjects.RemoveAll;
begin
  CurId := 0;
  inherited RemoveAll;
end;

procedure TPReadObjects.ShutDownKeeping;
begin
  ShouldDelete := False;
  ShutDown;
end;

procedure TPReadObjects.RegisterObject(Adr: Pointer);
var
  Loc: ccIndex;
begin
  Loc := Insert(Adr);
  Assert(Cardinal(Loc) = CurId);
  Inc(CurId);
end;

function TPReadObjects.Find(Id: P_id_type): Pointer;
begin
  Result := At(Id);
end;

{ pstream }

constructor pstream.Create(Sb: TStreamBuf);
begin
  inherited Create;
  Init(Sb);
end;

destructor pstream.Destroy;
begin
  inherited Destroy;
end;

class procedure pstream.InitTypes;
begin
  if Types = nil then
    Types := TStreamableTypes.Create;
end;

function pstream.Rdstate: Integer;
begin
  Result := State;
end;

function pstream.Eof: Integer;
begin
  Result := State and iosEofBit;
end;

function pstream.&Fail: Integer;
begin
  Result := State and (iosFailBit or iosBadBit);
end;

function pstream.Bad: Integer;
begin
  Result := State and iosBadBit;
end;

function pstream.Good: Boolean;
begin
  Result := State = 0;
end;

procedure pstream.Clear(I: Integer);
begin
  State := I and $FF;
end;

class procedure pstream.RegisterType(Ts: TStreamableClass);
begin
  Types.RegisterType(Ts);
end;

function pstream.OpVoidPtr: Pointer;
begin
  if &Fail <> 0 then
    Result := nil
  else
    Result := Pointer(Self);
end;

function pstream.OpNot: Boolean;
begin
  Result := &Fail <> 0;
end;

function pstream.Rdbuf: TStreamBuf;
begin
  Result := Bp;
end;

constructor pstream.Create;
begin
  inherited Create;
end;

procedure pstream.Error(E: StreamableError);
begin
  if E = peInvalidType then
    WriteLn(ErrOutput, 'pstream error: invalid type encountered')
  else if E = peNotRegistered then
    WriteLn(ErrOutput, 'pstream error: type not registered');
  Flush(ErrOutput);
  Abort;
end;

procedure pstream.Error(E: StreamableError; T: TStreamable);
begin
  if E = peNotRegistered then
    WriteLn(ErrOutput, 'pstream error: type ''', T.StreamableName, ''' not registered')
  else
    Error(E);
  Flush(ErrOutput);
  Abort;
end;

procedure pstream.Init(Sb: TStreamBuf);
begin
  State := 0;
  Bp := Sb;
end;

procedure pstream.Setstate(B: Integer);
begin
  State := State or (B and $FF);
end;

{ ipstream }

constructor ipstream.Create(Sb: TStreamBuf);
begin
  inherited Create(Sb);
  Objs := TPReadObjects.Create;
end;

destructor ipstream.Destroy;
begin
  Objs.ShutDownKeeping;
  Objs.Free;
  inherited Destroy;
end;

function ipstream.Tellg: Int64;
begin
  Result := Bp.PubSeekOff(0, iosCur, iosIn);
end;

function ipstream.Seekg(Pos: Int64): ipstream;
begin
  Objs.RemoveAll;
  Bp.PubSeekOff(Pos, iosBeg);
  Result := Self;
end;

function ipstream.Seekg(Off: Int64; Dir: Integer): ipstream;
begin
  Objs.RemoveAll;
  Bp.PubSeekOff(Off, Dir);
  Result := Self;
end;

function ipstream.ReadByte: Byte;
begin
  Result := Byte(Bp.SBumpC);
end;

function ipstream.ReadWord: Word;
var
  Temp: Word;
begin
  Temp := 0;
  Bp.SGetN(Temp, SizeOf(Word));
  Result := Temp;
end;

procedure ipstream.ReadBytes(var Data; Sz: SizeInt);
begin
  Bp.SGetN(Data, Sz);
end;

function ipstream.ReadString: PChar;
var
  Len: Byte;
begin
  Len := ReadByte;
  if Len = nullStringLen then
  begin
    Result := nil;
    Exit;
  end;
  GetMem(Result, Len + 1);
  ReadBytes(Result^, Len);
  Result[Len] := #0;
end;

function ipstream.ReadString(Buf: PChar; MaxLen: Cardinal): PChar;
var
  Len: Byte;
begin
  Assert(Buf <> nil);

  Len := ReadByte;
  if Len >= MaxLen then
  begin
    Result := nil;
    Exit;
  end;
  ReadBytes(Buf^, Len);
  Buf[Len] := #0;
  Result := Buf;
end;

function ipstream.Get(var V: AnsiChar): ipstream;
begin
  V := AnsiChar(ReadByte);
  Result := Self;
end;

function ipstream.Get(var V: ShortInt): ipstream;
begin
  V := ShortInt(ReadByte);
  Result := Self;
end;

function ipstream.Get(var V: Byte): ipstream;
begin
  V := ReadByte;
  Result := Self;
end;

function ipstream.Get(var V: SmallInt): ipstream;
begin
  V := SmallInt(ReadWord);
  Result := Self;
end;

function ipstream.Get(var V: Word): ipstream;
begin
  V := ReadWord;
  Result := Self;
end;

function ipstream.Get(var V: LongInt): ipstream;
begin
  ReadBytes(V, SizeOf(LongInt));
  Result := Self;
end;

function ipstream.Get(var V: LongWord): ipstream;
begin
  ReadBytes(V, SizeOf(LongWord));
  Result := Self;
end;

function ipstream.GetLong(var V: CLong): ipstream;
begin
  ReadBytes(V, SizeOf(V));
  Result := Self;
end;

function ipstream.GetULong(var V: CULong): ipstream;
begin
  ReadBytes(V, SizeOf(V));
  Result := Self;
end;

function ipstream.Get(var V: Single): ipstream;
begin
  ReadBytes(V, SizeOf(V));
  Result := Self;
end;

function ipstream.Get(var V: Double): ipstream;
begin
  ReadBytes(V, SizeOf(V));
  Result := Self;
end;

function ipstream.Get(var V: Extended): ipstream;
begin
  ReadBytes(V, SizeOf(V));
  Result := Self;
end;

function ipstream.GetObject(T: TStreamable): ipstream;
var
  Pc: TStreamableClass;
begin
  Pc := ReadPrefix;
  ReadData(Pc, T);
  ReadSuffix;
  Result := Self;
end;

function ipstream.Get(var T: Pointer): ipstream;
var
  Ch: Byte;
  Index: P_id_type;
  Pc: TStreamableClass;
begin
  Ch := ReadByte;
  case Ch of
    Ord(ptNull):
      T := nil;
    Ord(ptIndexed):
      begin
        Index := ReadWord;
        T := Find(Index);
        Assert(T <> nil);
      end;
    Ord(ptObject):
      begin
        Pc := ReadPrefix;
        T := ReadData(Pc, nil);
        ReadSuffix;
      end;
  else
    Error(peInvalidType);
  end;
  Result := Self;
end;

constructor ipstream.Create;
begin
  inherited Create;
  Objs := TPReadObjects.Create;
end;

function ipstream.ReadPrefix: TStreamableClass;
var
  Ch: Byte;
  Name: array[0..127] of AnsiChar;
begin
  Ch := ReadByte;
  Assert(Ch = Ord('['));

  Name[0] := #0;
  ReadString(@Name[0], SizeOf(Name));
  Result := Types.Lookup(@Name[0]);
end;

function ipstream.ReadData(C: TStreamableClass; Mem: TStreamable): Pointer;
begin
  if Mem = nil then
  begin
    { An object cannot be built from a type that is not registered. }
    if C = nil then
      Error(peNotRegistered);
    Mem := C.Build();
  end;
  RegisterObject(Pointer(Mem));
  Result := Mem.Read(Self);
end;

procedure ipstream.ReadSuffix;
var
  Ch: Byte;
begin
  Ch := ReadByte;
  Assert(Ch = Ord(']'));
end;

function ipstream.Find(Id: P_id_type): Pointer;
begin
  Result := Objs.Find(Id);
end;

procedure ipstream.RegisterObject(Adr: Pointer);
begin
  Objs.RegisterObject(Adr);
end;

{ opstream }

constructor opstream.Create;
begin
  inherited Create;
  Objs := TPWrittenObjects.Create;
end;

constructor opstream.Create(Sb: TStreamBuf);
begin
  inherited Create(Sb);
  Objs := TPWrittenObjects.Create;
end;

destructor opstream.Destroy;
begin
  TvObject.DestroyObject(Objs);
  inherited Destroy;
end;

function opstream.Seekp(Pos: Int64): opstream;
begin
  Objs.FreeAll;
  Bp.PubSeekOff(Pos, iosBeg);
  Result := Self;
end;

function opstream.Seekp(Off: Int64; Dir: Integer): opstream;
begin
  Objs.FreeAll;
  Bp.PubSeekOff(Off, Dir);
  Result := Self;
end;

function opstream.Tellp: Int64;
begin
  Result := Bp.PubSeekOff(0, iosCur, iosOut);
end;

function opstream.Flush: opstream;
begin
  Bp.PubSync;
  Result := Self;
end;

procedure opstream.WriteByte(Ch: Byte);
begin
  Bp.SPutC(Ch);
end;

procedure opstream.WriteBytes(const Data; Sz: SizeInt);
begin
  Bp.SPutN(Data, Sz);
end;

procedure opstream.WriteWord(Sh: Word);
begin
  Bp.SPutN(Sh, SizeOf(Word));
end;

procedure opstream.WriteString(Str: PChar);
begin
  if Str = nil then
  begin
    WriteByte(nullStringLen);
    Exit;
  end;
  WriteString(AnsiString(Str));
end;

procedure opstream.WriteString(const Str: AnsiString);
var
  Len: SizeInt;
begin
  Len := Length(Str);
  if Len > nullStringLen - 1 then
    Len := nullStringLen - 1;
  WriteByte(Byte(Len));
  WriteBytes(PChar(Str)^, Len);
end;

function opstream.Put(const V: AnsiChar): opstream;
begin
  WriteByte(Ord(V));
  Result := Self;
end;

function opstream.Put(const V: ShortInt): opstream;
begin
  WriteByte(Byte(V));
  Result := Self;
end;

function opstream.Put(const V: Byte): opstream;
begin
  WriteByte(V);
  Result := Self;
end;

function opstream.Put(const V: SmallInt): opstream;
begin
  WriteWord(Word(V));
  Result := Self;
end;

function opstream.Put(const V: Word): opstream;
begin
  WriteWord(V);
  Result := Self;
end;

function opstream.Put(const V: LongInt): opstream;
begin
  WriteBytes(V, SizeOf(LongInt));
  Result := Self;
end;

function opstream.Put(const V: LongWord): opstream;
begin
  WriteBytes(V, SizeOf(LongWord));
  Result := Self;
end;

function opstream.PutLong(const V: CLong): opstream;
begin
  WriteBytes(V, SizeOf(V));
  Result := Self;
end;

function opstream.PutULong(const V: CULong): opstream;
begin
  WriteBytes(V, SizeOf(V));
  Result := Self;
end;

function opstream.Put(const V: Single): opstream;
begin
  WriteBytes(V, SizeOf(V));
  Result := Self;
end;

function opstream.Put(const V: Double): opstream;
begin
  WriteBytes(V, SizeOf(V));
  Result := Self;
end;

function opstream.Put(const V: Extended): opstream;
begin
  WriteBytes(V, SizeOf(V));
  Result := Self;
end;

function opstream.PutObject(T: TStreamable): opstream;
begin
  WritePrefix(T);
  WriteData(T);
  WriteSuffix(T);
  Result := Self;
end;

function opstream.Put(T: TStreamable): opstream;
var
  Index: P_id_type;
begin
  if T = nil then
    WriteByte(Ord(ptNull))
  else
  begin
    Index := Find(Pointer(T));
    if Index <> P_id_notFound then
    begin
      WriteByte(Ord(ptIndexed));
      WriteWord(Word(Index));
    end
    else
    begin
      WriteByte(Ord(ptObject));
      PutObject(T);
    end;
  end;
  Result := Self;
end;

procedure opstream.WritePrefix(T: TStreamable);
begin
  WriteByte(Ord('['));
  WriteString(T.StreamableName);
end;

procedure opstream.WriteData(T: TStreamable);
begin
  if Types.Lookup(T.StreamableName) = nil then
    Error(peNotRegistered, T)
  else
  begin
    RegisterObject(Pointer(T));
    T.Write(Self);
  end;
end;

procedure opstream.WriteSuffix(T: TStreamable);
begin
  WriteByte(Ord(']'));
end;

function opstream.Find(Adr: Pointer): P_id_type;
begin
  Result := Objs.Find(Adr);
end;

procedure opstream.RegisterObject(Adr: Pointer);
begin
  Objs.RegisterObject(Adr);
end;

{ iopstream }

constructor iopstream.Create(Sb: TStreamBuf);
begin
  inherited Create(Sb);
  Writer := opstream.Create(Sb);
end;

destructor iopstream.Destroy;
begin
  Writer.Free;
  inherited Destroy;
end;

constructor iopstream.Create;
begin
  inherited Create;
  Writer := opstream.Create;
end;

function iopstream.Tellp: Int64;
begin
  Result := Writer.Tellp;
end;

function iopstream.Seekp(Pos: Int64): iopstream;
begin
  Writer.Seekp(Pos);
  Result := Self;
end;

function iopstream.Seekp(Off: Int64; Dir: Integer): iopstream;
begin
  Writer.Seekp(Off, Dir);
  Result := Self;
end;

function iopstream.Flush: iopstream;
begin
  Writer.Flush;
  Result := Self;
end;

procedure iopstream.WriteByte(Ch: Byte);
begin
  Writer.WriteByte(Ch);
end;

procedure iopstream.WriteBytes(const Data; Sz: SizeInt);
begin
  Writer.WriteBytes(Data, Sz);
end;

procedure iopstream.WriteWord(Sh: Word);
begin
  Writer.WriteWord(Sh);
end;

procedure iopstream.WriteString(Str: PChar);
begin
  Writer.WriteString(Str);
end;

procedure iopstream.WriteString(const Str: AnsiString);
begin
  Writer.WriteString(Str);
end;

function iopstream.Put(const V: AnsiChar): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.Put(const V: ShortInt): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.Put(const V: Byte): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.Put(const V: SmallInt): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.Put(const V: Word): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.Put(const V: LongInt): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.Put(const V: LongWord): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.PutLong(const V: CLong): iopstream;
begin
  Writer.PutLong(V);
  Result := Self;
end;

function iopstream.PutULong(const V: CULong): iopstream;
begin
  Writer.PutULong(V);
  Result := Self;
end;

function iopstream.Put(const V: Single): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.Put(const V: Double): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.Put(const V: Extended): iopstream;
begin
  Writer.Put(V);
  Result := Self;
end;

function iopstream.PutObject(T: TStreamable): iopstream;
begin
  Writer.PutObject(T);
  Result := Self;
end;

function iopstream.Put(T: TStreamable): iopstream;
begin
  Writer.Put(T);
  Result := Self;
end;

{ fpbase }

constructor fpbase.Create(AOwner: pstream);
begin
  inherited Create;
  Owner := AOwner;
  Buf := TFileBuf.Create;
  Owner.Init(Buf);
end;

constructor fpbase.Create(AOwner: pstream; const Name: AnsiString; OMode: Integer);
begin
  inherited Create;
  Owner := AOwner;
  Buf := TFileBuf.Create;
  Owner.Init(Buf);
  Open(Name, OMode);
end;

destructor fpbase.Destroy;
begin
  Buf.Free;
  inherited Destroy;
end;

procedure fpbase.Open(const Name: AnsiString; OMode: Integer);
begin
  if Buf.Is_open then
    Owner.Clear(iosFailBit)
  else if Buf.Open(Name, OMode) then
    Owner.Clear(iosGoodBit)
  else
    Owner.Clear(iosBadBit);
end;

procedure fpbase.Close;
begin
  if Buf.Close then
    Owner.Clear(iosGoodBit)
  else
    Owner.Setstate(iosFailBit);
end;

function fpbase.Rdbuf: TFileBuf;
begin
  Result := Buf;
end;

{ ifpstream }

constructor ifpstream.Create;
begin
  inherited Create;
  Base := fpbase.Create(Self);
end;

constructor ifpstream.Create(const Name: AnsiString; OMode: Integer);
begin
  inherited Create;
  Base := fpbase.Create(Self, Name, OMode or iosIn or iosBinary);
end;

destructor ifpstream.Destroy;
begin
  inherited Destroy;
  Base.Free;
end;

function ifpstream.Rdbuf: TFileBuf;
begin
  Result := Base.Rdbuf;
end;

procedure ifpstream.Open(const Name: AnsiString; OMode: Integer);
begin
  Base.Open(Name, OMode or iosIn or iosBinary);
end;

procedure ifpstream.Close;
begin
  Base.Close;
end;

{ ofpstream }

constructor ofpstream.Create;
begin
  inherited Create;
  Base := fpbase.Create(Self);
end;

constructor ofpstream.Create(const Name: AnsiString; OMode: Integer);
begin
  inherited Create;
  Base := fpbase.Create(Self, Name, OMode or iosOut or iosBinary);
end;

destructor ofpstream.Destroy;
begin
  inherited Destroy;
  Base.Free;
end;

function ofpstream.Rdbuf: TFileBuf;
begin
  Result := Base.Rdbuf;
end;

procedure ofpstream.Open(const Name: AnsiString; OMode: Integer);
begin
  Base.Open(Name, OMode or iosOut or iosBinary);
end;

procedure ofpstream.Close;
begin
  Base.Close;
end;

{ fpstream }

constructor fpstream.Create;
begin
  inherited Create;
  Base := fpbase.Create(Self);
  Writer.Init(Base.Rdbuf);
end;

constructor fpstream.Create(const Name: AnsiString; OMode: Integer);
begin
  inherited Create;
  Base := fpbase.Create(Self);
  Writer.Init(Base.Rdbuf);
  Base.Open(Name, OMode or iosBinary);
end;

destructor fpstream.Destroy;
begin
  inherited Destroy;
  Base.Free;
end;

function fpstream.Rdbuf: TFileBuf;
begin
  Result := Base.Rdbuf;
end;

procedure fpstream.Open(const Name: AnsiString; OMode: Integer);
begin
  Base.Open(Name, OMode or iosBinary);
end;

procedure fpstream.Close;
begin
  Base.Close;
end;

initialization
  pstream.InitTypes;

end.
