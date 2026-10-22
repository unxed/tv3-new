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
end;

procedure TvObject.ShutDown;
begin
end;

constructor TNSCollection.Create;
begin
end;

procedure TNSCollection.FreeItem(Item: Pointer);
begin
end;

constructor TNSCollection.Create(ALimit, ADelta: ccIndex);
begin
end;

destructor TNSCollection.Destroy;
begin
end;

procedure TNSCollection.ShutDown;
begin
end;

function TNSCollection.At(Index: ccIndex): Pointer;
begin
  Result := nil;
end;

function TNSCollection.IndexOf(Item: Pointer): ccIndex;
begin
  Result := 0;
end;

procedure TNSCollection.AtFree(Index: ccIndex);
begin
end;

procedure TNSCollection.AtRemove(Index: ccIndex);
begin
end;

procedure TNSCollection.Remove(Item: Pointer);
begin
end;

procedure TNSCollection.RemoveAll;
begin
end;

procedure TNSCollection.Free(Item: Pointer);
begin
end;

procedure TNSCollection.FreeAll;
begin
end;

procedure TNSCollection.AtInsert(Index: ccIndex; Item: Pointer);
begin
end;

procedure TNSCollection.AtPut(Index: ccIndex; Item: Pointer);
begin
end;

function TNSCollection.Insert(Item: Pointer): ccIndex;
begin
  Result := 0;
end;

procedure TNSCollection.Error(Code, Info: ccIndex);
begin
end;

function TNSCollection.FirstThat(Test: ccTestFunc; Arg: Pointer): Pointer;
begin
  Result := nil;
end;

function TNSCollection.LastThat(Test: ccTestFunc; Arg: Pointer): Pointer;
begin
  Result := nil;
end;

procedure TNSCollection.ForEach(Action: ccAppFunc; Arg: Pointer);
begin
end;

procedure TNSCollection.Pack;
begin
end;

procedure TNSCollection.SetLimit(ALimit: ccIndex);
begin
end;

function TNSCollection.GetCount: ccIndex;
begin
  Result := 0;
end;

constructor TNSSortedCollection.Create;
begin
end;

constructor TNSSortedCollection.Create(ALimit, ADelta: ccIndex);
begin
end;

function TNSSortedCollection.Search(Key: Pointer; var Index: ccIndex): Boolean;
begin
  Index := 0;
  Result := False;
end;

function TNSSortedCollection.IndexOf(Item: Pointer): ccIndex;
begin
  Result := ccNotFound;
end;

function TNSSortedCollection.Insert(Item: Pointer): ccIndex;
begin
  Result := 0;
end;

function TNSSortedCollection.KeyOf(Item: Pointer): Pointer;
begin
  Result := nil;
end;

constructor TCollection.Create(ALimit, ADelta: ccIndex);
begin
end;

constructor TSortedCollection.Create(ALimit, ADelta: ccIndex);
begin
end;

end.
