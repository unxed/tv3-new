{ Translated from magiblot/tvision @ b4831e2
  C++ sources: include/tvision/tvobjs.h, include/tvision/objects.h (TCollection, TSortedCollection),
  source/tvision/tobject.cpp, source/tvision/tcollect.cpp, source/tvision/tsortcol.cpp,
  source/tvision/nmcollct.cpp, source/tvision/nmscoll.cpp
  See COPYRIGHT.magiblot. }
program t_objs;

{$mode objfpc}

uses
  SysUtils, TvObjs;

{$I testlib.inc}

type
  PIntBox = ^PtrInt;

  ECollError = class(Exception);

  { Reports an error by an exception, so that the calling routine does not go on. Counts the items it frees. }
  TTestColl = class(TNSCollection)
  public
    ErrCode: ccIndex;
    ErrInfo: ccIndex;
    procedure Error(Code, Info: ccIndex); override;
    procedure Keep;
  protected
    procedure FreeItem(Item: Pointer); override;
  end;

  { Gives access to the fields of any collection. }
  TAccess = class(TNSCollection);

  { Items are integers in pointers; the key is the item itself. }
  TIntSorted = class(TNSSortedCollection)
  protected
    function Compare(Key1, Key2: Pointer): Integer; override;
    procedure FreeItem(Item: Pointer); override;
  end;

  { Items are 100 * key + tag in pointers. }
  TKeyed = class(TNSSortedCollection)
  protected
    function Compare(Key1, Key2: Pointer): Integer; override;
  public
    function KeyOf(Item: Pointer): Pointer; override;
  end;

  TIntSortedColl = class(TSortedCollection)
  protected
    function Compare(Key1, Key2: Pointer): Integer; override;
  end;

  { Counts the calls of ShutDown. }
  TWatched = class(TvObject)
  public
    procedure ShutDown; override;
  end;

var
  FreedTotal: Integer = 0;
  LastFreed: Pointer = nil;
  ShutDowns: Integer = 0;
  Trace: array[0..31] of PtrInt;
  TraceLen: Integer = 0;

function P(N: PtrInt): Pointer;
begin
  Result := Pointer(N);
end;

function V(Item: Pointer): PtrInt;
begin
  Result := PtrInt(Item);
end;

function Cmp(A, B: PtrInt): Integer;
begin
  if A < B then
    Result := -1
  else if A > B then
    Result := 1
  else
    Result := 0;
end;

procedure TTestColl.Error(Code, Info: ccIndex);
begin
  ErrCode := Code;
  ErrInfo := Info;
  raise ECollError.Create('collection error');
end;

procedure TTestColl.Keep;
begin
  TAccess(Self).ShouldDelete := False;
end;

procedure TTestColl.FreeItem(Item: Pointer);
begin
  Inc(FreedTotal);
  LastFreed := Item;
end;

function TIntSorted.Compare(Key1, Key2: Pointer): Integer;
begin
  Result := Cmp(V(Key1), V(Key2));
end;

procedure TIntSorted.FreeItem(Item: Pointer);
begin
  Inc(FreedTotal);
  LastFreed := Item;
end;

function TKeyed.Compare(Key1, Key2: Pointer): Integer;
begin
  Result := Cmp(V(Key1), V(Key2));
end;

function TKeyed.KeyOf(Item: Pointer): Pointer;
begin
  Result := P(V(Item) div 100);
end;

function TIntSortedColl.Compare(Key1, Key2: Pointer): Integer;
begin
  Result := Cmp(V(Key1), V(Key2));
end;

procedure TWatched.ShutDown;
begin
  Inc(ShutDowns);
  inherited ShutDown;
end;

function IsEven(Item, Arg: Pointer): Boolean;
begin
  Result := (V(Item) mod 2) = 0;
end;

function IsAbove(Item, Arg: Pointer): Boolean;
begin
  Result := V(Item) > V(Arg);
end;

procedure Note(Item, Arg: Pointer);
begin
  Trace[TraceLen] := V(Item);
  Inc(TraceLen);
end;

procedure AddUp(Item, Arg: Pointer);
begin
  Inc(PIntBox(Arg)^, V(Item));
end;

{ True when the items of C are Want, in order, and nothing more. }
function Holds(C: TNSCollection; const Want: array of PtrInt): Boolean;
var
  I: Integer;
begin
  Result := C.GetCount = Length(Want);
  if Result then
    for I := 0 to High(Want) do
      if V(C.At(I)) <> Want[I] then
        Result := False;
end;

procedure FillFrom(C: TNSCollection; const Want: array of PtrInt);
var
  I: Integer;
begin
  for I := 0 to High(Want) do
    C.Insert(P(Want[I]));
end;

var
  C: TTestColl;
  Plain: TNSCollection;
  S: TIntSorted;
  K: TKeyed;
  Coll: TCollection;
  SC: TIntSortedColl;
  W: TWatched;
  Total: PtrInt;
  Idx: ccIndex;
  Found: Boolean;
  I: Integer;
  Blk: Pointer;
  Caught: Boolean;

begin
  { Creation and growth by Delta }
  C := TTestColl.Create(5, 3);
  Check(C.GetCount = 0, 'a new collection is empty');
  Check(TAccess(C).Limit = 5, 'the limit is the one given');
  Check(TAccess(C).Delta = 3, 'the delta is the one given');
  Check(TAccess(C).ShouldDelete, 'a new collection frees its items');
  C.Free;

  C := TTestColl.Create(1, 2);
  Check(C.Insert(P(10)) = 0, 'the first insert is at 0');
  Check(TAccess(C).Limit = 1, 'one item fit the limit');
  Check(C.Insert(P(20)) = 1, 'the second insert is at 1');
  Check(TAccess(C).Limit = 3, 'a full collection grows by the delta');
  Check(C.Insert(P(30)) = 2, 'the third insert is at 2');
  Check(TAccess(C).Limit = 3, 'no growth while there is room');
  Check(C.Insert(P(40)) = 3, 'the fourth insert is at 3');
  Check(TAccess(C).Limit = 5, 'a second growth by the delta');
  Check(Holds(C, [10, 20, 30, 40]), 'the items are in the order of insertion');
  Check(C.GetCount = 4, 'the count after four inserts');
  C.Free;

  C := TTestColl.Create(0, 4);
  Check(TAccess(C).Limit = 0, 'a limit of 0 holds nothing');
  C.Insert(P(1));
  Check(TAccess(C).Limit = 4, 'the first insert grows an empty collection by the delta');
  C.Free;

  { At, AtPut, AtInsert }
  C := TTestColl.Create(4, 4);
  FillFrom(C, [11, 22, 33]);
  Check(C.At(0) = P(11), 'at 0');
  Check(C.At(2) = P(33), 'at the last index');
  C.AtPut(1, P(99));
  Check(Holds(C, [11, 99, 33]), 'atPut replaces an item');
  Check(C.GetCount = 3, 'atPut keeps the count');
  C.AtInsert(0, P(1));
  Check(Holds(C, [1, 11, 99, 33]), 'atInsert at the front');
  C.AtInsert(2, P(2));
  Check(Holds(C, [1, 11, 2, 99, 33]), 'atInsert in the middle');
  C.AtInsert(5, P(3));
  Check(Holds(C, [1, 11, 2, 99, 33, 3]), 'atInsert at the end');
  Check(TAccess(C).Limit >= 6, 'atInsert grew the collection');

  { Error cases }
  C.ErrCode := 0;
  Caught := False;
  try
    C.At(-1);
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1) and (C.ErrInfo = 0), 'at below 0 is error 1');
  C.ErrCode := 0;
  Caught := False;
  try
    C.At(C.GetCount);
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1), 'at the count is error 1');
  C.ErrCode := 0;
  Caught := False;
  try
    C.AtPut(C.GetCount, P(5));
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1), 'atPut at the count is error 1');
  C.ErrCode := 0;
  Caught := False;
  try
    C.AtInsert(-1, P(5));
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1), 'atInsert below 0 is error 1');
  C.ErrCode := 0;
  Caught := False;
  try
    C.AtRemove(-1);
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1), 'atRemove below 0 is error 1');
  C.ErrCode := 0;
  Caught := False;
  try
    C.AtRemove(C.GetCount);
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1), 'atRemove at the count is error 1');
  C.ErrCode := 0;
  Caught := False;
  try
    C.AtFree(C.GetCount);
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1), 'atFree at the count is error 1');
  Check(Holds(C, [1, 11, 2, 99, 33, 3]), 'the failed calls changed nothing');
  C.Free;

  { AtRemove, Remove, IndexOf }
  C := TTestColl.Create(8, 2);
  FillFrom(C, [5, 6, 7, 8]);
  C.AtRemove(1);
  Check(Holds(C, [5, 7, 8]), 'atRemove closes the gap');
  C.AtRemove(2);
  Check(Holds(C, [5, 7]), 'atRemove of the last item');
  C.AtRemove(0);
  Check(Holds(C, [7]), 'atRemove of the first item');
  Check(FreedTotal = 0, 'atRemove does not free the item');
  C.RemoveAll;
  Check(C.GetCount = 0, 'removeAll empties the collection');
  Check(FreedTotal = 0, 'removeAll does not free the items');
  Check(TAccess(C).Limit = 8, 'removeAll keeps the limit');

  FillFrom(C, [4, 5, 6]);
  Check(C.IndexOf(P(4)) = 0, 'indexOf the first item');
  Check(C.IndexOf(P(6)) = 2, 'indexOf the last item');
  C.Remove(P(5));
  Check(Holds(C, [4, 6]), 'remove takes the item out');
  C.ErrCode := 0;
  Caught := False;
  try
    C.IndexOf(P(77));
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1), 'indexOf of an absent item is error 1');
  C.ErrCode := 0;
  Caught := False;
  try
    C.Remove(P(77));
  except
    on ECollError do Caught := True;
  end;
  Check(Caught and (C.ErrCode = 1), 'remove of an absent item is error 1');
  Check(Holds(C, [4, 6]), 'the failed remove changed nothing');
  C.Free;

  { FirstThat, LastThat, ForEach }
  C := TTestColl.Create(8, 2);
  FillFrom(C, [1, 2, 3, 4, 5, 6, 7]);
  Check(C.FirstThat(@IsEven, nil) = P(2), 'firstThat finds the first even item');
  Check(C.LastThat(@IsEven, nil) = P(6), 'lastThat finds the last even item');
  Check(C.FirstThat(@IsAbove, P(4)) = P(5), 'firstThat passes the argument');
  Check(C.LastThat(@IsAbove, P(4)) = P(7), 'lastThat passes the argument');
  Check(C.FirstThat(@IsAbove, P(7)) = nil, 'firstThat finds nothing: nil');
  Check(C.LastThat(@IsAbove, P(7)) = nil, 'lastThat finds nothing: nil');
  TraceLen := 0;
  C.ForEach(@Note, nil);
  Check(TraceLen = 7, 'forEach visits every item');
  Check((Trace[0] = 1) and (Trace[3] = 4) and (Trace[6] = 7), 'forEach goes from the first to the last');
  Total := 0;
  C.ForEach(@AddUp, @Total);
  Check(Total = 28, 'forEach passes the argument');
  C.Free;

  C := TTestColl.Create(2, 2);
  Check(C.FirstThat(@IsEven, nil) = nil, 'firstThat of an empty collection');
  Check(C.LastThat(@IsEven, nil) = nil, 'lastThat of an empty collection');
  TraceLen := 0;
  C.ForEach(@Note, nil);
  Check(TraceLen = 0, 'forEach of an empty collection');
  C.Free;

  { Pack }
  C := TTestColl.Create(8, 2);
  FillFrom(C, [1, 0, 2, 0, 0, 3]);
  C.Pack;
  Check(V(C.At(0)) = 1, 'pack keeps the first item');
  Check(V(C.At(1)) = 2, 'pack moves the second item up');
  Check(V(C.At(2)) = 3, 'pack moves the third item up');
  Check(C.GetCount = 6, 'pack leaves the count as it was');
  C.Free;

  { SetLimit }
  C := TTestColl.Create(2, 2);
  FillFrom(C, [1, 2]);
  C.SetLimit(10);
  Check(TAccess(C).Limit = 10, 'setLimit raises the limit');
  Check(Holds(C, [1, 2]), 'setLimit keeps the items');
  C.SetLimit(1);
  Check(TAccess(C).Limit = 2, 'setLimit does not go below the count');
  Check(Holds(C, [1, 2]), 'setLimit below the count keeps the items');
  C.SetLimit(-5);
  Check(TAccess(C).Limit = 2, 'a negative limit becomes the count');
  C.RemoveAll;
  C.SetLimit(0);
  Check(TAccess(C).Limit = 0, 'setLimit 0 of an empty collection');
  Check(TAccess(C).Items = nil, 'setLimit 0 releases the storage');
  C.Insert(P(8));
  Check(Holds(C, [8]), 'an emptied collection takes items again');
  C.Free;

  { Freeing items }
  C := TTestColl.Create(8, 2);
  FillFrom(C, [1, 2, 3, 4]);
  FreedTotal := 0;
  C.AtFree(1);
  Check((FreedTotal = 1) and (LastFreed = P(2)), 'atFree frees the item');
  Check(Holds(C, [1, 3, 4]), 'atFree removes the item');
  C.Free(P(4));
  Check((FreedTotal = 2) and (LastFreed = P(4)), 'free frees the item');
  Check(Holds(C, [1, 3]), 'free removes the item');
  C.FreeAll;
  Check(FreedTotal = 4, 'freeAll frees every item');
  Check(C.GetCount = 0, 'freeAll empties the collection');
  C.Free;

  { ShutDown }
  C := TTestColl.Create(8, 2);
  FillFrom(C, [1, 2, 3]);
  FreedTotal := 0;
  C.ShutDown;
  Check(FreedTotal = 3, 'shutDown frees the items');
  Check(C.GetCount = 0, 'shutDown empties the collection');
  Check(TAccess(C).Limit = 0, 'shutDown sets the limit to 0');
  C.Free;

  C := TTestColl.Create(8, 2);
  C.Keep;
  FillFrom(C, [1, 2, 3]);
  FreedTotal := 0;
  C.ShutDown;
  Check(FreedTotal = 0, 'shutDown frees nothing when shouldDelete is off');
  Check(C.GetCount = 0, 'shutDown removes the items when shouldDelete is off');
  Check(TAccess(C).Limit = 0, 'shutDown sets the limit to 0 also then');
  C.Free;

  { The default FreeItem releases memory from GetMem }
  Plain := TNSCollection.Create(4, 4);
  for I := 1 to 3 do
  begin
    GetMem(Blk, 16);
    Plain.Insert(Blk);
  end;
  Plain.AtFree(1);
  Check(Plain.GetCount = 2, 'the default atFree removes the item');
  Plain.FreeAll;
  Check(Plain.GetCount = 0, 'the default freeAll empties the collection');
  GetMem(Blk, 16);
  Plain.Insert(Blk);
  Plain.Free(Blk);
  Check(Plain.GetCount = 0, 'the default free removes the item');
  GetMem(Blk, 16);
  Plain.Insert(Blk);
  Plain.ShutDown;
  Check(Plain.GetCount = 0, 'the default shutDown empties the collection');
  Plain.Free;

  { TvObject }
  TvObject.DestroyObject(nil);
  Check(True, 'destroyObject of nil does nothing');
  W := TWatched.Create;
  ShutDowns := 0;
  TvObject.DestroyObject(W);
  Check(ShutDowns = 1, 'destroyObject calls shutDown once');
  C := TTestColl.Create(4, 4);
  FillFrom(C, [1, 2]);
  FreedTotal := 0;
  TvObject.DestroyObject(C);
  Check(FreedTotal = 2, 'destroyObject of a collection frees its items');

  { TCollection }
  Coll := TCollection.Create(2, 3);
  Check(TAccess(Coll).Limit = 2, 'TCollection takes the limit');
  Check(TAccess(Coll).Delta = 3, 'TCollection takes the delta');
  FillFrom(Coll, [4, 5, 6]);
  Check(Holds(Coll, [4, 5, 6]), 'TCollection inserts');
  Check(TAccess(Coll).Limit = 5, 'TCollection grows by the delta');
  Coll.Free;

  { The sorted collection without duplicates }
  S := TIntSorted.Create(4, 4);
  Check(not S.Duplicates, 'duplicates are off at first');
  Check(S.Insert(P(5)) = 0, 'the first sorted insert');
  Check(S.Insert(P(1)) = 0, 'a smaller item goes to the front');
  Check(S.Insert(P(3)) = 1, 'a middle item goes between');
  Check(S.Insert(P(9)) = 3, 'a larger item goes to the end');
  Check(Holds(S, [1, 3, 5, 9]), 'the items are in order');
  Check(S.Insert(P(3)) = 1, 'a present key gives its index');
  Check(Holds(S, [1, 3, 5, 9]), 'a present key is not inserted again');
  Found := S.Search(P(5), Idx);
  Check(Found and (Idx = 2), 'search finds a key');
  Found := S.Search(P(1), Idx);
  Check(Found and (Idx = 0), 'search finds the first key');
  Found := S.Search(P(9), Idx);
  Check(Found and (Idx = 3), 'search finds the last key');
  Found := S.Search(P(4), Idx);
  Check((not Found) and (Idx = 2), 'search gives the place of an absent key');
  Found := S.Search(P(0), Idx);
  Check((not Found) and (Idx = 0), 'search of a key below all');
  Found := S.Search(P(10), Idx);
  Check((not Found) and (Idx = 4), 'search of a key above all');
  Check(S.IndexOf(P(5)) = 2, 'indexOf finds an item');
  Check(S.IndexOf(P(4)) = ccNotFound, 'indexOf of an absent item is ccNotFound');
  Check(S.IndexOf(P(100)) = ccNotFound, 'indexOf above all is ccNotFound');
  S.Remove(P(3));
  Check(Holds(S, [1, 5, 9]), 'remove by the sorted indexOf');
  FreedTotal := 0;
  S.Free(P(5));
  Check((FreedTotal = 1) and Holds(S, [1, 9]), 'free by the sorted indexOf');
  S.FreeAll;
  Check((FreedTotal = 3) and (S.GetCount = 0), 'freeAll of a sorted collection');
  Found := S.Search(P(7), Idx);
  Check((not Found) and (Idx = 0), 'search in an empty collection');
  Check(S.IndexOf(P(7)) = ccNotFound, 'indexOf in an empty collection');
  S.Free;

  { Many items, to make the search go through several steps }
  S := TIntSorted.Create(0, 8);
  for I := 20 downto 1 do
    S.Insert(P(I * 2));
  Check(S.GetCount = 20, 'twenty items');
  Found := True;
  for I := 0 to 19 do
    if V(S.At(I)) <> (I + 1) * 2 then
      Found := False;
  Check(Found, 'inserted from the largest, they are in order');
  Found := True;
  for I := 1 to 20 do
    if S.IndexOf(P(I * 2)) <> I - 1 then
      Found := False;
  Check(Found, 'indexOf of every item');
  Found := S.Search(P(13), Idx);
  Check((not Found) and (Idx = 6), 'search between two items');
  S.Free;

  { The sorted collection with duplicates }
  S := TIntSorted.Create(4, 4);
  S.Duplicates := True;
  S.Insert(P(3));
  S.Insert(P(1));
  Check(S.Insert(P(3)) = 1, 'a duplicate goes before its equals');
  Check(Holds(S, [1, 3, 3]), 'the duplicate is inserted');
  S.Insert(P(3));
  S.Insert(P(5));
  Check(Holds(S, [1, 3, 3, 3, 5]), 'duplicates stay together');
  Found := S.Search(P(3), Idx);
  Check(Found and (Idx = 1), 'search gives the first of equal keys');
  Check(S.IndexOf(P(3)) = 1, 'indexOf with duplicates');
  S.Free;

  { Keys that differ from the items }
  K := TKeyed.Create(4, 4);
  K.Duplicates := True;
  K.Insert(P(102));
  K.Insert(P(101));
  K.Insert(P(103));
  K.Insert(P(201));
  K.Insert(P(50));
  Check(Holds(K, [50, 103, 101, 102, 201]), 'items are ordered by key, equal keys newest first');
  Check(K.IndexOf(P(50)) = 0, 'indexOf by key');
  Check(K.IndexOf(P(103)) = 1, 'indexOf finds the item among equal keys: first');
  Check(K.IndexOf(P(101)) = 2, 'indexOf finds the item among equal keys: second');
  Check(K.IndexOf(P(102)) = 3, 'indexOf finds the item among equal keys: third');
  Check(K.IndexOf(P(201)) = 4, 'indexOf finds the item after the equal keys');
  Check(K.IndexOf(P(104)) = ccNotFound, 'a key present but another item: ccNotFound');
  Check(K.IndexOf(P(299)) = ccNotFound, 'a key present but another item at the end: ccNotFound');
  Check(K.IndexOf(P(301)) = ccNotFound, 'an absent key: ccNotFound');
  Found := K.Search(P(1), Idx);
  Check(Found and (Idx = 1), 'search takes a key, not an item');
  K.Remove(P(101));
  Check(Holds(K, [50, 103, 102, 201]), 'remove finds the item among equal keys');
  K.Free;

  K := TKeyed.Create(4, 4);
  K.Insert(P(101));
  Check(K.Insert(P(102)) = 0, 'without duplicates an equal key gives its index');
  Check(Holds(K, [101]), 'without duplicates an equal key is not inserted');
  Check(K.IndexOf(P(102)) = 0, 'without duplicates indexOf goes by the key');
  K.Free;

  { TSortedCollection }
  SC := TIntSortedColl.Create(2, 2);
  Check(not SC.Duplicates, 'TSortedCollection has duplicates off');
  FillFrom(SC, [8, 2, 6, 4]);
  Check(Holds(SC, [2, 4, 6, 8]), 'TSortedCollection keeps the order');
  Check(SC.IndexOf(P(6)) = 2, 'TSortedCollection indexOf');
  SC.Insert(P(6));
  Check(SC.GetCount = 4, 'TSortedCollection takes no duplicate');
  SC.Free;

  Done;
end.
