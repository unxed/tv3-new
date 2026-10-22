{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/tvobjs.h (TObject, TNSCollection, TNSSortedCollection),
  include/tvision/objects.h (TCollection, TSortedCollection), source/tvision/tobject.cpp,
  source/tvision/tcollect.cpp, source/tvision/tsortcol.cpp, source/tvision/nmcollct.cpp,
  source/tvision/nmscoll.cpp
  See COPYRIGHT.magiblot.

  The class TObject of the C++ is TvObject here, so that it does not hide System.TObject. The classes of the
  C++ with virtual inheritance are single inheritance chains here: TCollection and TNSSortedCollection descend
  from TNSCollection, and TSortedCollection from TNSSortedCollection. The private virtual members FreeItem and
  Compare are protected, so that a class of another unit can override them. The stream members (read, write,
  readItem, writeItem, streamableName, name and the stream constructors) belong to a later unit. }
unit TvObjs;

{$mode objfpc}
{$R-}
{$Q-}

interface

type
  { Index into a collection, and the count of its items. }
  ccIndex = Integer;

const
  { Result of an index search that finds nothing. }
  ccNotFound = -1;
  { The largest limit of a collection. }
  maxCollectionSize = MaxInt div SizeOf(Pointer);

type
  { Tells whether Item meets a condition; Arg is passed on from the caller. }
  ccTestFunc = function(Item, Arg: Pointer): Boolean;
  { Does something with Item; Arg is passed on from the caller. }
  ccAppFunc = procedure(Item, Arg: Pointer);

  TSlotRow = array[0..maxCollectionSize - 1] of Pointer;
  PSlotRow = ^TSlotRow;

  { The base of the objects of the library. }
  TvObject = class(TObject)
  public
    { Calls ShutDown of O, when O is not nil, and then frees O. }
    class procedure DestroyObject(O: TvObject);
    { Called before the object is freed; releases what the object holds besides its own memory. }
    procedure ShutDown; virtual;
  end;

  { A collection of untyped pointers that grows by steps of Delta. }
  TNSCollection = class(TvObject)
  protected
    Items: PSlotRow;
    Count: ccIndex;
    Limit: ccIndex;
    Delta: ccIndex;
    ShouldDelete: Boolean;
    constructor Create; overload;
    { Frees the memory of Item; override it to free items of another kind. }
    procedure FreeItem(Item: Pointer); virtual;
  public
    constructor Create(ALimit, ADelta: ccIndex); overload;
    destructor Destroy; override;
    procedure ShutDown; override;
    function At(Index: ccIndex): Pointer;
    function IndexOf(Item: Pointer): ccIndex; virtual;
    procedure AtFree(Index: ccIndex);
    procedure AtRemove(Index: ccIndex);
    procedure Remove(Item: Pointer);
    procedure RemoveAll;
    procedure Free(Item: Pointer); overload;
    procedure FreeAll;
    procedure AtInsert(Index: ccIndex; Item: Pointer);
    procedure AtPut(Index: ccIndex; Item: Pointer);
    function Insert(Item: Pointer): ccIndex; virtual;
    { Ends the program with the exit code 212 - Code. }
    procedure Error(Code, Info: ccIndex); virtual;
    function FirstThat(Test: ccTestFunc; Arg: Pointer): Pointer;
    function LastThat(Test: ccTestFunc; Arg: Pointer): Pointer;
    procedure ForEach(Action: ccAppFunc; Arg: Pointer);
    procedure Pack;
    procedure SetLimit(ALimit: ccIndex); virtual;
    function GetCount: ccIndex;
  end;

  { A collection kept in the order of Compare of the keys of its items. }
  TNSSortedCollection = class(TNSCollection)
  protected
    constructor Create; overload;
    { Less than zero, zero or more than zero when Key1 is before, equal to or after Key2. }
    function Compare(Key1, Key2: Pointer): Integer; virtual; abstract;
  public
    Duplicates: Boolean;
    constructor Create(ALimit, ADelta: ccIndex); overload;
    function Search(Key: Pointer; var Index: ccIndex): Boolean; virtual;
    function IndexOf(Item: Pointer): ccIndex; override;
    function Insert(Item: Pointer): ccIndex; override;
    function KeyOf(Item: Pointer): Pointer; virtual;
  end;

  TCollection = class(TNSCollection)
  public
    constructor Create(ALimit, ADelta: ccIndex); overload;
  end;

  TSortedCollection = class(TNSSortedCollection)
  public
    constructor Create(ALimit, ADelta: ccIndex); overload;
  end;

implementation

class procedure TvObject.DestroyObject(O: TvObject);
begin
  if O <> nil then
    O.ShutDown;
  O.Free;
end;

procedure TvObject.ShutDown;
begin
end;

constructor TNSCollection.Create(ALimit, ADelta: ccIndex);
begin
  { The fields of a new instance are zero: no storage, no items, no limit. }
  inherited Create;
  Delta := ADelta;
  ShouldDelete := True;
  SetLimit(ALimit);
end;

constructor TNSCollection.Create;
begin
  inherited Create;
  ShouldDelete := True;
end;

destructor TNSCollection.Destroy;
begin
  if Items <> nil then
    FreeMem(Items);
  inherited Destroy;
end;

procedure TNSCollection.ShutDown;
begin
  if ShouldDelete then
    FreeAll
  else
    RemoveAll;
  SetLimit(0);
  inherited ShutDown;
end;

function TNSCollection.At(Index: ccIndex): Pointer;
begin
  if (Index < 0) or (Index >= Count) then
    Error(1, 0);
  Result := Items^[Index];
end;

procedure TNSCollection.AtRemove(Index: ccIndex);
var
  J: ccIndex;
begin
  if (Index < 0) or (Index >= Count) then
    Error(1, 0);

  Dec(Count);
  for J := Index to Count - 1 do
    Items^[J] := Items^[J + 1];
end;

procedure TNSCollection.AtFree(Index: ccIndex);
var
  Item: Pointer;
begin
  Item := At(Index);
  AtRemove(Index);
  FreeItem(Item);
end;

procedure TNSCollection.AtInsert(Index: ccIndex; Item: Pointer);
begin
  if Index < 0 then
    Error(1, 0);
  if Count = Limit then
    SetLimit(Count + Delta);

  Move(Items^[Index], Items^[Index + 1], (Count - Index) * SizeOf(Pointer));
  Inc(Count);

  Items^[Index] := Item;
end;

procedure TNSCollection.AtPut(Index: ccIndex; Item: Pointer);
begin
  if Index >= Count then
    Error(1, 0);

  Items^[Index] := Item;
end;

procedure TNSCollection.Remove(Item: Pointer);
begin
  AtRemove(IndexOf(Item));
end;

procedure TNSCollection.RemoveAll;
begin
  Count := 0;
end;

procedure TNSCollection.Error(Code, Info: ccIndex);
begin
  Halt(212 - Code);
end;

function TNSCollection.FirstThat(Test: ccTestFunc; Arg: Pointer): Pointer;
var
  I: ccIndex;
begin
  for I := 0 to Count - 1 do
    if Test(Items^[I], Arg) then
      Exit(Items^[I]);
  Result := nil;
end;

function TNSCollection.LastThat(Test: ccTestFunc; Arg: Pointer): Pointer;
var
  I: ccIndex;
begin
  for I := Count downto 1 do
    if Test(Items^[I - 1], Arg) then
      Exit(Items^[I - 1]);
  Result := nil;
end;

procedure TNSCollection.ForEach(Action: ccAppFunc; Arg: Pointer);
var
  I: ccIndex;
begin
  for I := 0 to Count - 1 do
    Action(Items^[I], Arg);
end;

procedure TNSCollection.Free(Item: Pointer);
begin
  Remove(Item);
  FreeItem(Item);
end;

procedure TNSCollection.FreeAll;
var
  I: ccIndex;
begin
  I := 0;
  while I < Count do
  begin
    FreeItem(At(I));
    Inc(I);
  end;
  Count := 0;
end;

{ The default releases a block of memory from GetMem. It cannot run the destructor of an object, so a collection of
  objects overrides it. }
procedure TNSCollection.FreeItem(Item: Pointer);
begin
  if Item <> nil then
    FreeMem(Item);
end;

function TNSCollection.IndexOf(Item: Pointer): ccIndex;
var
  I: ccIndex;
begin
  for I := 0 to Count - 1 do
    if Item = Items^[I] then
      Exit(I);

  Error(1, 0);
  Result := 0;
end;

function TNSCollection.Insert(Item: Pointer): ccIndex;
begin
  Result := Count;
  AtInsert(Count, Item);
end;

{ Moves the items that are not nil to the front, in their order. Count stays as it was. }
procedure TNSCollection.Pack;
var
  Dst, Src: ccIndex;
begin
  Dst := 0;
  for Src := 0 to Count - 1 do
    if Items^[Src] <> nil then
    begin
      Items^[Dst] := Items^[Src];
      Inc(Dst);
    end;
end;

procedure TNSCollection.SetLimit(ALimit: ccIndex);
var
  Wanted: ccIndex;
begin
  Wanted := ALimit;
  if Wanted > maxCollectionSize then
    Wanted := maxCollectionSize;
  if Wanted < Count then
    Wanted := Count;
  if Wanted <> Limit then
  begin
    if Wanted > 0 then
      ReAllocMem(Items, SizeInt(Wanted) * SizeOf(Pointer))
    else
    begin
      if Items <> nil then
        FreeMem(Items);
      Items := nil;
    end;
    Limit := Wanted;
  end;
end;

function TNSCollection.GetCount: ccIndex;
begin
  Result := Count;
end;

constructor TNSSortedCollection.Create(ALimit, ADelta: ccIndex);
begin
  inherited Create(ALimit, ADelta);
  Duplicates := False;
  Delta := ADelta;
  SetLimit(ALimit);
end;

constructor TNSSortedCollection.Create;
begin
  inherited Create;
  Duplicates := False;
end;

function TNSSortedCollection.IndexOf(Item: Pointer): ccIndex;
var
  First, I: ccIndex;
begin
  Result := ccNotFound;
  if not Search(KeyOf(Item), First) then
    Exit;
  if Duplicates then
  begin
    { Among the items of an equal key, the one that is Item itself. }
    for I := First to Count - 1 do
      if Items^[I] = Item then
        Exit(I);
  end
  else if First < Count then
    Result := First;
end;

function TNSSortedCollection.Insert(Item: Pointer): ccIndex;
var
  I: ccIndex;
begin
  if (not Search(KeyOf(Item), I)) or Duplicates then
    AtInsert(I, Item);
  Result := I;
end;

function TNSSortedCollection.KeyOf(Item: Pointer): Pointer;
begin
  Result := Item;
end;

{ Looks for the first place where a key is not before Key, in the half-open range Lo..Hi. Without duplicates it
  stops at the first item whose key equals Key. }
function TNSSortedCollection.Search(Key: Pointer; var Index: ccIndex): Boolean;
var
  Lo, Hi, Mid, Order: ccIndex;
begin
  Lo := 0;
  Hi := Count;
  Result := False;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi - 1) shr 1;
    Order := Compare(KeyOf(Items^[Mid]), Key);
    if Order < 0 then
      Lo := Mid + 1
    else
    begin
      Hi := Mid;
      if Order = 0 then
      begin
        Result := True;
        if not Duplicates then
          Lo := Mid;
      end;
    end;
  end;
  Index := Lo;
end;

constructor TCollection.Create(ALimit, ADelta: ccIndex);
begin
  inherited Create;
  Delta := ADelta;
  SetLimit(ALimit);
end;

constructor TSortedCollection.Create(ALimit, ADelta: ccIndex);
begin
  inherited Create(ALimit, ADelta);
end;

end.
