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

function TStreamBuf.Sync: Integer;
begin
end;

function TStreamBuf.PubSeekOff(Off: Int64; Dir: Integer; Which: Integer): Int64;
begin
end;

function TStreamBuf.PubSync: Integer;
begin
end;

function TStreamBuf.SBumpC: Integer;
begin
end;

function TStreamBuf.SGetN(var Buf; N: SizeInt): SizeInt;
begin
end;

function TStreamBuf.SPutC(C: Byte): Integer;
begin
end;

function TStreamBuf.SPutN(const Buf; N: SizeInt): SizeInt;
begin
end;

destructor TMemBuf.Destroy;
begin
end;

function TMemBuf.Size: SizeInt;
begin
end;

function TMemBuf.Data: PByte;
begin
end;

procedure TMemBuf.Reset;
begin
end;

function TMemBuf.SeekOff(Off: Int64; Dir, Which: Integer): Int64;
begin
end;

function TMemBuf.XSGetN(var Buf; N: SizeInt): SizeInt;
begin
end;

function TMemBuf.XSPutN(const Buf; N: SizeInt): SizeInt;
begin
end;

constructor TFileBuf.Create(ABufSize: Integer);
begin
end;

destructor TFileBuf.Destroy;
begin
end;

function TFileBuf.FlushBuf: Boolean;
begin
end;

function TFileBuf.Is_open: Boolean;
begin
end;

function TFileBuf.Open(const Name: AnsiString; Mode: Integer): Boolean;
begin
end;

function TFileBuf.Close: Boolean;
begin
end;

function TFileBuf.Sync: Integer;
begin
end;

function TFileBuf.SeekOff(Off: Int64; Dir, Which: Integer): Int64;
begin
end;

function TFileBuf.XSGetN(var Buf; N: SizeInt): SizeInt;
begin
end;

function TFileBuf.XSPutN(const Buf; N: SizeInt): SizeInt;
begin
end;

constructor TStreamableClass.Create(N: PChar; B: BUILDER; Unused: Integer);
begin
end;

constructor TStreamableTypes.Create;
begin
end;

procedure TStreamableTypes.RegisterType(D: TStreamableClass);
begin
end;

function TStreamableTypes.Lookup(Name: PChar): TStreamableClass;
begin
end;

function TStreamableTypes.KeyOf(Item: Pointer): Pointer;
begin
end;

function TStreamableTypes.Compare(Key1, Key2: Pointer): Integer;
begin
end;

constructor TPWrittenObjects.Create;
begin
end;

procedure TPWrittenObjects.RemoveAll;
begin
end;

procedure TPWrittenObjects.RegisterObject(Adr: Pointer);
begin
end;

function TPWrittenObjects.Find(Adr: Pointer): P_id_type;
begin
end;

function TPWrittenObjects.KeyOf(Item: Pointer): Pointer;
begin
end;

function TPWrittenObjects.Compare(Key1, Key2: Pointer): Integer;
begin
end;

procedure TPWrittenObjects.FreeItem(Item: Pointer);
begin
end;

constructor TPWObj.Create(Adr: Pointer; Id: P_id_type);
begin
end;

constructor TPReadObjects.Create;
begin
end;

procedure TPReadObjects.RemoveAll;
begin
end;

procedure TPReadObjects.ShutDownKeeping;
begin
end;

procedure TPReadObjects.RegisterObject(Adr: Pointer);
begin
end;

function TPReadObjects.Find(Id: P_id_type): Pointer;
begin
end;

constructor pstream.Create(Sb: TStreamBuf);
begin
end;

destructor pstream.Destroy;
begin
end;

class procedure pstream.InitTypes;
begin
end;

function pstream.Rdstate: Integer;
begin
end;

function pstream.Eof: Integer;
begin
end;

function pstream.&Fail: Integer;
begin
end;

function pstream.Bad: Integer;
begin
end;

function pstream.Good: Boolean;
begin
end;

procedure pstream.Clear(I: Integer);
begin
end;

class procedure pstream.RegisterType(Ts: TStreamableClass);
begin
end;

function pstream.OpVoidPtr: Pointer;
begin
end;

function pstream.OpNot: Boolean;
begin
end;

function pstream.Rdbuf: TStreamBuf;
begin
end;

constructor pstream.Create;
begin
end;

procedure pstream.Error(E: StreamableError);
begin
end;

procedure pstream.Error(E: StreamableError; T: TStreamable);
begin
end;

procedure pstream.Init(Sb: TStreamBuf);
begin
end;

procedure pstream.Setstate(B: Integer);
begin
end;

constructor ipstream.Create(Sb: TStreamBuf);
begin
end;

destructor ipstream.Destroy;
begin
end;

function ipstream.Tellg: Int64;
begin
end;

function ipstream.Seekg(Pos: Int64): ipstream;
begin
end;

function ipstream.Seekg(Off: Int64; Dir: Integer): ipstream;
begin
end;

function ipstream.ReadByte: Byte;
begin
end;

function ipstream.ReadWord: Word;
begin
end;

procedure ipstream.ReadBytes(var Data; Sz: SizeInt);
begin
end;

function ipstream.ReadString: PChar;
begin
end;

function ipstream.ReadString(Buf: PChar; MaxLen: Cardinal): PChar;
begin
end;

function ipstream.Get(var V: AnsiChar): ipstream;
begin
end;

function ipstream.Get(var V: ShortInt): ipstream;
begin
end;

function ipstream.Get(var V: Byte): ipstream;
begin
end;

function ipstream.Get(var V: SmallInt): ipstream;
begin
end;

function ipstream.Get(var V: Word): ipstream;
begin
end;

function ipstream.Get(var V: LongInt): ipstream;
begin
end;

function ipstream.Get(var V: LongWord): ipstream;
begin
end;

function ipstream.GetLong(var V: CLong): ipstream;
begin
end;

function ipstream.GetULong(var V: CULong): ipstream;
begin
end;

function ipstream.Get(var V: Single): ipstream;
begin
end;

function ipstream.Get(var V: Double): ipstream;
begin
end;

function ipstream.Get(var V: Extended): ipstream;
begin
end;

function ipstream.GetObject(T: TStreamable): ipstream;
begin
end;

function ipstream.Get(var T: Pointer): ipstream;
begin
end;

constructor ipstream.Create;
begin
end;

function ipstream.ReadPrefix: TStreamableClass;
begin
end;

function ipstream.ReadData(C: TStreamableClass; Mem: TStreamable): Pointer;
begin
end;

procedure ipstream.ReadSuffix;
begin
end;

function ipstream.Find(Id: P_id_type): Pointer;
begin
end;

procedure ipstream.RegisterObject(Adr: Pointer);
begin
end;

constructor opstream.Create;
begin
end;

constructor opstream.Create(Sb: TStreamBuf);
begin
end;

destructor opstream.Destroy;
begin
end;

function opstream.Seekp(Pos: Int64): opstream;
begin
end;

function opstream.Seekp(Off: Int64; Dir: Integer): opstream;
begin
end;

function opstream.Tellp: Int64;
begin
end;

function opstream.Flush: opstream;
begin
end;

procedure opstream.WriteByte(Ch: Byte);
begin
end;

procedure opstream.WriteBytes(const Data; Sz: SizeInt);
begin
end;

procedure opstream.WriteWord(Sh: Word);
begin
end;

procedure opstream.WriteString(Str: PChar);
begin
end;

procedure opstream.WriteString(const Str: AnsiString);
begin
end;

function opstream.Put(const V: AnsiChar): opstream;
begin
end;

function opstream.Put(const V: ShortInt): opstream;
begin
end;

function opstream.Put(const V: Byte): opstream;
begin
end;

function opstream.Put(const V: SmallInt): opstream;
begin
end;

function opstream.Put(const V: Word): opstream;
begin
end;

function opstream.Put(const V: LongInt): opstream;
begin
end;

function opstream.Put(const V: LongWord): opstream;
begin
end;

function opstream.PutLong(const V: CLong): opstream;
begin
end;

function opstream.PutULong(const V: CULong): opstream;
begin
end;

function opstream.Put(const V: Single): opstream;
begin
end;

function opstream.Put(const V: Double): opstream;
begin
end;

function opstream.Put(const V: Extended): opstream;
begin
end;

function opstream.PutObject(T: TStreamable): opstream;
begin
end;

function opstream.Put(T: TStreamable): opstream;
begin
end;

procedure opstream.WritePrefix(T: TStreamable);
begin
end;

procedure opstream.WriteData(T: TStreamable);
begin
end;

procedure opstream.WriteSuffix(T: TStreamable);
begin
end;

function opstream.Find(Adr: Pointer): P_id_type;
begin
end;

procedure opstream.RegisterObject(Adr: Pointer);
begin
end;

constructor iopstream.Create(Sb: TStreamBuf);
begin
end;

destructor iopstream.Destroy;
begin
end;

constructor iopstream.Create;
begin
end;

function iopstream.Tellp: Int64;
begin
end;

function iopstream.Seekp(Pos: Int64): iopstream;
begin
end;

function iopstream.Seekp(Off: Int64; Dir: Integer): iopstream;
begin
end;

function iopstream.Flush: iopstream;
begin
end;

procedure iopstream.WriteByte(Ch: Byte);
begin
end;

procedure iopstream.WriteBytes(const Data; Sz: SizeInt);
begin
end;

procedure iopstream.WriteWord(Sh: Word);
begin
end;

procedure iopstream.WriteString(Str: PChar);
begin
end;

procedure iopstream.WriteString(const Str: AnsiString);
begin
end;

function iopstream.Put(const V: AnsiChar): iopstream;
begin
end;

function iopstream.Put(const V: ShortInt): iopstream;
begin
end;

function iopstream.Put(const V: Byte): iopstream;
begin
end;

function iopstream.Put(const V: SmallInt): iopstream;
begin
end;

function iopstream.Put(const V: Word): iopstream;
begin
end;

function iopstream.Put(const V: LongInt): iopstream;
begin
end;

function iopstream.Put(const V: LongWord): iopstream;
begin
end;

function iopstream.PutLong(const V: CLong): iopstream;
begin
end;

function iopstream.PutULong(const V: CULong): iopstream;
begin
end;

function iopstream.Put(const V: Single): iopstream;
begin
end;

function iopstream.Put(const V: Double): iopstream;
begin
end;

function iopstream.Put(const V: Extended): iopstream;
begin
end;

function iopstream.PutObject(T: TStreamable): iopstream;
begin
end;

function iopstream.Put(T: TStreamable): iopstream;
begin
end;

constructor fpbase.Create(AOwner: pstream);
begin
end;

constructor fpbase.Create(AOwner: pstream; const Name: AnsiString; OMode: Integer);
begin
end;

destructor fpbase.Destroy;
begin
end;

procedure fpbase.Open(const Name: AnsiString; OMode: Integer);
begin
end;

procedure fpbase.Close;
begin
end;

function fpbase.Rdbuf: TFileBuf;
begin
end;

constructor ifpstream.Create;
begin
end;

constructor ifpstream.Create(const Name: AnsiString; OMode: Integer);
begin
end;

destructor ifpstream.Destroy;
begin
end;

function ifpstream.Rdbuf: TFileBuf;
begin
end;

procedure ifpstream.Open(const Name: AnsiString; OMode: Integer);
begin
end;

procedure ifpstream.Close;
begin
end;

constructor ofpstream.Create;
begin
end;

constructor ofpstream.Create(const Name: AnsiString; OMode: Integer);
begin
end;

destructor ofpstream.Destroy;
begin
end;

function ofpstream.Rdbuf: TFileBuf;
begin
end;

procedure ofpstream.Open(const Name: AnsiString; OMode: Integer);
begin
end;

procedure ofpstream.Close;
begin
end;

constructor fpstream.Create;
begin
end;

constructor fpstream.Create(const Name: AnsiString; OMode: Integer);
begin
end;

destructor fpstream.Destroy;
begin
end;

function fpstream.Rdbuf: TFileBuf;
begin
end;

procedure fpstream.Open(const Name: AnsiString; OMode: Integer);
begin
end;

procedure fpstream.Close;
begin
end;

end.
