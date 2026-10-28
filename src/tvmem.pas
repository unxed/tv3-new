{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/buffers.h (TBufListEntry, TVMemMgr), source/tvision/new.cpp (TBufListEntry,
  TVMemMgr), source/tvision/misc.cpp (lowMemory)
  See COPYRIGHT.magiblot.

  The memory comes from the memory manager of the run-time library (GetMem, FreeMem, ReAllocMem). A request that
  the manager cannot satisfy raises EOutOfMemory there, and the routines of this unit turn it into the nil
  pointer that malloc gives in the C++. The state of the unit is not protected by a lock: it belongs to the
  thread of the user interface.

  The replacement of the global operators new and delete, which the C++ compiles only for one compiler, has no
  counterpart: the allocations of Pascal objects do not go through the list of discardable buffers and do not
  take back the safety pool. The routines that serve them (allocBlock, deleteBlock) are not translated. The
  declared but undefined member initMemMgr is not translated either. }
unit TvMem;

{$mode objfpc}
{$modeswitch advancedrecords}
{$R-}
{$Q-}

interface

uses
  SysUtils;

const
  DEFAULT_SAFETY_POOL_SIZE = 4096;

type
  PBufListEntry = ^TBufListEntry;

  { The header of a discardable buffer. The headers are a doubly linked list, the newest buffer first, and the
    data of the buffer follows its header. Owner is the variable that holds the address of the data. }
  TBufListEntry = record
  private
    Next: PBufListEntry;
    Prev: PBufListEntry;
    Owner: PPointer;
    Sz: PtrUInt;
    class var BufList: PBufListEntry;
  public
    { Puts the header at the start of its own memory, in front of the list. }
    constructor Create(var AOwner: Pointer; ASz: PtrUInt);
    { Takes the header out of the list, clears the owner and gives the memory back. }
    procedure Destroy;
    { Memory for a header and Extra bytes of data, nil when there is none. }
    class function NewBlock(Extra: PtrUInt): Pointer; static;
    class procedure FreeBlock(Block: Pointer); static;
    { Discards the newest buffer. It tells whether there was one. }
    class function FreeHead: Boolean; static;
  end;

  TVMemMgr = class
  private
    class var SafetyPool: Pointer;
    class var SafetyPoolSize: PtrUInt;
    class var Inited: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure ResizeSafetyPool(Sz: PtrUInt = DEFAULT_SAFETY_POOL_SIZE); static;
    { Gives the safety pool back, as ResizeSafetyPool(0) does. }
    class procedure ClearSafetyPool; static;
    class function SafetyPoolExhausted: Integer; static;
    class procedure AllocateDiscardable(var Adr: Pointer; Sz: PtrUInt); static;
    class procedure ReallocateDiscardable(var Adr: Pointer; Sz: PtrUInt); static;
    class procedure FreeDiscardable(Block: Pointer); static;
  end;

var
  { The object whose construction makes the safety pool when the unit starts. }
  MemMgr: TVMemMgr;

{ Tells whether the safety pool has been given back. }
function LowMemory: Boolean;

implementation

{ Memory of the run-time library, with nil in place of the exception when there is not enough. }
function GetBlockOrNil(Size: PtrUInt): Pointer;
begin
  Result := nil;
  try
    Result := GetMem(Size);
  except
    on EOutOfMemory do
      Result := nil;
  end;
end;

{ The block resized, with nil when there is not enough memory; the old block is then still valid. }
function ResizeBlockOrNil(Block: Pointer; Size: PtrUInt): Pointer;
var
  Moved: Pointer;
begin
  Result := nil;
  Moved := Block;
  try
    Result := ReAllocMem(Moved, Size);
  except
    on EOutOfMemory do
      Result := nil;
  end;
end;

{ The header that precedes the data at Block. }
function EntryOf(Block: Pointer): PBufListEntry;
begin
  Result := PBufListEntry(PtrUInt(Block) - SizeOf(TBufListEntry));
end;

{ The data that follows a header. }
function DataOf(Entry: PBufListEntry): Pointer;
begin
  Result := Pointer(PtrUInt(Entry) + SizeOf(TBufListEntry));
end;

{ TBufListEntry }

constructor TBufListEntry.Create(var AOwner: Pointer; ASz: PtrUInt);
begin
  Owner := @AOwner;
  Sz := ASz;
  Next := BufList;
  Prev := nil;
  BufList := @Self;
  if Next <> nil then
    Next^.Prev := @Self;
end;

procedure TBufListEntry.Destroy;
begin
  Owner^ := nil;
  if Prev = nil then
    BufList := Next
  else
    Prev^.Next := Next;
  if Next <> nil then
    Next^.Prev := Prev;
  FreeBlock(@Self);
end;

class function TBufListEntry.NewBlock(Extra: PtrUInt): Pointer;
begin
  Result := GetBlockOrNil(SizeOf(TBufListEntry) + Extra);
end;

class procedure TBufListEntry.FreeBlock(Block: Pointer);
begin
  if Block <> nil then
    FreeMem(Block);
end;

class function TBufListEntry.FreeHead: Boolean;
begin
  Result := BufList <> nil;
  if Result then
    BufList^.Destroy;
end;

{ TVMemMgr }

constructor TVMemMgr.Create;
begin
  inherited Create;
  if Inited = 0 then
    ResizeSafetyPool;
end;

destructor TVMemMgr.Destroy;
begin
  ResizeSafetyPool(0);
  Inited := 0;
  inherited Destroy;
end;

class procedure TVMemMgr.ResizeSafetyPool(Sz: PtrUInt);
begin
  Inited := 1;
  if SafetyPool <> nil then
    FreeMem(SafetyPool);
  SafetyPool := nil;
  if Sz <> 0 then
    SafetyPool := GetBlockOrNil(Sz);
  SafetyPoolSize := Sz;
end;

class procedure TVMemMgr.ClearSafetyPool;
begin
  ResizeSafetyPool(0);
end;

class function TVMemMgr.SafetyPoolExhausted: Integer;
begin
  if (Inited <> 0) and (SafetyPool = nil) then
    Result := 1
  else
    Result := 0;
end;

class procedure TVMemMgr.AllocateDiscardable(var Adr: Pointer; Sz: PtrUInt);
var
  Raw: Pointer;
  Entry: PBufListEntry;
begin
  if SafetyPoolExhausted <> 0 then
  begin
    Adr := nil;
    Exit;
  end;
  Raw := TBufListEntry.NewBlock(Sz);
  if Raw = nil then
  begin
    Adr := nil;
    Exit;
  end;
  Entry := PBufListEntry(Raw);
  Entry^.Create(Adr, Sz);
  Adr := DataOf(Entry);
end;

{ The case of ReallocateDiscardable where the new size is below the old one: the block is cut in place, and
  when the memory manager moves it the neighbours of its header and the head of the list are told. }
procedure ShrinkDiscardable(var Adr: Pointer; Entry: PBufListEntry; Sz: PtrUInt);
var
  Moved: PBufListEntry;
begin
  Moved := PBufListEntry(ResizeBlockOrNil(Entry, SizeOf(TBufListEntry) + Sz));
  if Moved = nil then
  begin
    TVMemMgr.FreeDiscardable(Adr);
    Adr := nil;
    Exit;
  end;
  if Moved^.Prev <> nil then
    Moved^.Prev^.Next := Moved
  else
    TBufListEntry.BufList := Moved;
  if Moved^.Next <> nil then
    Moved^.Next^.Prev := Moved;
  Moved^.Sz := Sz;
  Adr := DataOf(Moved);
end;

class procedure TVMemMgr.ReallocateDiscardable(var Adr: Pointer; Sz: PtrUInt);
var
  Entry: PBufListEntry;
begin
  if Sz = 0 then
  begin
    FreeDiscardable(Adr);
    Adr := nil;
    Exit;
  end;
  if Adr = nil then
  begin
    AllocateDiscardable(Adr, Sz);
    Exit;
  end;
  Entry := EntryOf(Adr);
  if Sz < Entry^.Sz then
    ShrinkDiscardable(Adr, Entry, Sz)
  else if Sz > Entry^.Sz then
  begin
    FreeDiscardable(Adr);
    AllocateDiscardable(Adr, Sz);
  end;
end;

class procedure TVMemMgr.FreeDiscardable(Block: Pointer);
begin
  if Block <> nil then
    EntryOf(Block)^.Destroy;
end;

function LowMemory: Boolean;
begin
  Result := TVMemMgr.SafetyPoolExhausted <> 0;
end;

initialization
  MemMgr := TVMemMgr.Create;

finalization
  MemMgr.Free;
  MemMgr := nil;

end.
