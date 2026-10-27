{ Reads, edits and writes INI files while keeping every line the program did not change: comments, blank lines, order,
  spacing, quoting and line ends. Lines that are not entries are kept as pseudo-entries of their section. }
unit TvIni;

{$mode objfpc}
{$modeswitch nestedprocvars}
{$H+}
{$R-}
{$Q-}

interface

type
  TIniEntry = class
  private
    FTag: AnsiString;
    FValue: AnsiString;
    FComment: AnsiString;
    FOriginal: AnsiString;
    FHasOriginal: Boolean;
    FIsEntry: Boolean;
    FRaw: Boolean;
    procedure Parse(const ALine: AnsiString; ARaw: Boolean);
  public
    constructor Create(const ALine: AnsiString); overload;
    constructor Create(const ALine: AnsiString; ARaw: Boolean); overload;
    constructor Create(const ATag, AValue, AComment: AnsiString; ARaw: Boolean = False); overload;
    function GetText: AnsiString;
    function GetTag: AnsiString;
    function GetValue: AnsiString;
    function GetComment: AnsiString;
    procedure SetValue(const S: AnsiString);
    procedure SetComment(const S: AnsiString);
    function IsEntry: Boolean;       { False for an empty line or a comment line }
  end;

  TIniSection = class;

  PIniEntry = TIniEntry;
  PIniSection = TIniSection;

  TIniEntryEnumProc = procedure(P: PIniEntry) is nested;
  TIniSectionEnumProc = procedure(P: PIniSection) is nested;

  TIniSection = class
  private
    FName: AnsiString;
    FRaw: Boolean;
    FEntries: array of TIniEntry;
    FCount: Integer;
    procedure Append(AEntry: TIniEntry);
    function IndexOf(const Tag: AnsiString): Integer;
  public
    constructor Create(const AName: AnsiString; ARaw: Boolean = False);
    destructor Destroy; override;
    function GetName: AnsiString;
    function AddEntry(const S: AnsiString): PIniEntry; overload;
    function AddEntry(const Tag, Value, Comment: AnsiString): PIniEntry; overload;
    function SearchEntry(const Tag: AnsiString): PIniEntry;
    procedure DeleteEntry(const Tag: AnsiString);
    procedure ForEachEntry(EnumProc: TIniEntryEnumProc);
    function Count: Integer;
    function Entry(I: Integer): PIniEntry;
  end;

  TIniFile = class
  private
    FFileName: AnsiString;
    FSections: array of TIniSection;
    FSectionCount: Integer;
    FModified: Boolean;
    FHasBom: Boolean;
    FCrLf: Boolean;
    function AddSection(const AName: AnsiString): TIniSection;
    function IndexOf(const Section: AnsiString): Integer;
    procedure ClearSections;
    procedure Parse(const Text: AnsiString);
  public
    MakeNullEntries: Boolean;
    InlineComments: Boolean;
    constructor Create(const AFileName: AnsiString);
    destructor Destroy; override;
    function GetFileName: AnsiString;
    function Read: Boolean;
    function Update: Boolean;
    function IsModified: Boolean;
    procedure LoadFromText(const Text: AnsiString);
    function SaveToText: AnsiString;
    function SearchSection(const Section: AnsiString): PIniSection;
    function SearchEntry(const Section, Tag: AnsiString): PIniEntry;
    procedure ForEachSection(EnumProc: TIniSectionEnumProc);
    procedure ForEachEntry(const Section: AnsiString; EnumProc: TIniEntryEnumProc);
    function GetEntry(const Section, Tag, Default: AnsiString): AnsiString;
    procedure SetEntry(const Section, Tag, Value: AnsiString); overload;
    procedure SetEntry(const Section, Tag, Value, Comment: AnsiString); overload;
    function GetIntEntry(const Section, Tag: AnsiString; Default: LongInt): LongInt;
    procedure SetIntEntry(const Section, Tag: AnsiString; Value: LongInt);
    function GetBoolEntry(const Section, Tag: AnsiString; Default: Boolean): Boolean;
    procedure SetBoolEntry(const Section, Tag: AnsiString; Value: Boolean);
    function EntryExists(const Section, Tag: AnsiString): Boolean;
    procedure DeleteSection(const Section: AnsiString);
    procedure DeleteEntry(const Section, Tag: AnsiString);
    function SectionCount: Integer;
    function SectionAt(I: Integer): PIniSection;
  end;
  PIniFile = TIniFile;

const
  MainSectionName = 'MainSection';
  CommentChar = ';';

{ The text to put after "=" for the value S: S itself, or S in quotes when it would not read back unchanged. }
function IniQuote(const S: AnsiString): AnsiString;

implementation

uses
  SysUtils, TvUStr;

const
  ByteOrderMark = #$EF#$BB#$BF;
  ReadChunkSize = 65536;

{ --- IniQuote --- }

function IniQuote(const S: AnsiString): AnsiString;
var
  NeedsQuotes: Boolean;
  Delimiter: Char;
  Index: Integer;
begin
  Result := S;
  if S = '' then
    Exit;

  NeedsQuotes := (S[1] <= ' ') or (S[Length(S)] <= ' ') or (S[1] = '''') or (S[1] = '"');
  if not NeedsQuotes then
    for Index := 1 to Length(S) do
      if (S[Index] = ';') or (S[Index] < ' ') then
      begin
        NeedsQuotes := True;
        Break;
      end;
  if not NeedsQuotes then
    Exit;

  if Pos('''', S) > 0 then
    Delimiter := '"'
  else
    Delimiter := '''';

  Result := Delimiter;
  for Index := 1 to Length(S) do
  begin
    if S[Index] = Delimiter then
      Result := Result + Delimiter;
    Result := Result + S[Index];
  end;
  Result := Result + Delimiter;
end;

{ --- TIniEntry --- }

constructor TIniEntry.Create(const ALine: AnsiString);
begin
  inherited Create;
  Parse(ALine, False);
end;

constructor TIniEntry.Create(const ALine: AnsiString; ARaw: Boolean);
begin
  inherited Create;
  Parse(ALine, ARaw);
end;

constructor TIniEntry.Create(const ATag, AValue, AComment: AnsiString; ARaw: Boolean);
begin
  inherited Create;
  FTag := ATag;
  FValue := AValue;
  FComment := AComment;
  FRaw := ARaw;
  FIsEntry := True;
  FHasOriginal := False;
  FOriginal := '';
end;

procedure TIniEntry.Parse(const ALine: AnsiString; ARaw: Boolean);
var
  EqualsPos, SemicolonPos, Cursor, LineLen: Integer;
  Delimiter: Char;
  Closed: Boolean;
  Rest: AnsiString;
begin
  FTag := '';
  FValue := '';
  FComment := '';
  FRaw := ARaw;
  FOriginal := ALine;
  FHasOriginal := True;
  FIsEntry := False;

  EqualsPos := Pos('=', ALine);
  if EqualsPos = 0 then
    Exit;
  SemicolonPos := Pos(';', ALine);
  if (SemicolonPos > 0) and (SemicolonPos < EqualsPos) then
    Exit;
  FTag := Trim(Copy(ALine, 1, EqualsPos - 1));
  if FTag = '' then
    Exit;

  FIsEntry := True;
  LineLen := Length(ALine);

  if ARaw then
  begin
    Rest := Copy(ALine, EqualsPos + 1, LineLen);
    if (Length(Rest) >= 2) and ((Rest[1] = '''') or (Rest[1] = '"')) and (Rest[Length(Rest)] = Rest[1]) then
      Rest := Copy(Rest, 2, Length(Rest) - 2);
    FValue := Rest;
    Exit;
  end;

  Cursor := EqualsPos + 1;
  while (Cursor <= LineLen) and (ALine[Cursor] <= ' ') do
    Inc(Cursor);

  if (Cursor <= LineLen) and ((ALine[Cursor] = '''') or (ALine[Cursor] = '"')) then
  begin
    Delimiter := ALine[Cursor];
    Inc(Cursor);
    Closed := False;
    while Cursor <= LineLen do
    begin
      if ALine[Cursor] <> Delimiter then
      begin
        FValue := FValue + ALine[Cursor];
        Inc(Cursor);
      end
      else if (Cursor < LineLen) and (ALine[Cursor + 1] = Delimiter) then
      begin
        FValue := FValue + Delimiter;
        Inc(Cursor, 2);
      end
      else
      begin
        Closed := True;
        Inc(Cursor);
        Break;
      end;
    end;
    if not Closed then
      Exit;
    while (Cursor <= LineLen) and (ALine[Cursor] <> ';') do
      Inc(Cursor);
    if Cursor <= LineLen then
      FComment := Copy(ALine, Cursor + 1, LineLen);
    Exit;
  end;

  SemicolonPos := Cursor;
  while (SemicolonPos <= LineLen) and (ALine[SemicolonPos] <> ';') do
    Inc(SemicolonPos);
  FValue := Trim(Copy(ALine, Cursor, SemicolonPos - Cursor));
  if SemicolonPos <= LineLen then
    FComment := Copy(ALine, SemicolonPos + 1, LineLen);
end;

function TIniEntry.GetText: AnsiString;
begin
  if FHasOriginal then
  begin
    Result := FOriginal;
    Exit;
  end;
  if not FIsEntry then
  begin
    Result := '';
    Exit;
  end;
  if FRaw then
  begin
    Result := FTag + '=' + FValue;
    Exit;
  end;
  Result := FTag + '=' + IniQuote(FValue);
  if FComment <> '' then
    Result := Result + ' ' + CommentChar + FComment;
end;

function TIniEntry.GetTag: AnsiString;
begin
  Result := FTag;
end;

function TIniEntry.GetValue: AnsiString;
begin
  Result := FValue;
end;

function TIniEntry.GetComment: AnsiString;
begin
  Result := FComment;
end;

procedure TIniEntry.SetValue(const S: AnsiString);
begin
  if not FIsEntry then
    Exit;
  if FValue = S then
    Exit;
  FValue := S;
  FHasOriginal := False;
  FOriginal := '';
end;

procedure TIniEntry.SetComment(const S: AnsiString);
begin
  if not FIsEntry then
    Exit;
  if FComment = S then
    Exit;
  FComment := S;
  FHasOriginal := False;
  FOriginal := '';
end;

function TIniEntry.IsEntry: Boolean;
begin
  Result := FIsEntry;
end;

{ --- TIniSection --- }

constructor TIniSection.Create(const AName: AnsiString; ARaw: Boolean);
begin
  inherited Create;
  FName := AName;
  FRaw := ARaw;
  FCount := 0;
end;

destructor TIniSection.Destroy;
var
  Index: Integer;
begin
  for Index := 0 to FCount - 1 do
    FEntries[Index].Free;
  FCount := 0;
  inherited Destroy;
end;

procedure TIniSection.Append(AEntry: TIniEntry);
begin
  if FCount >= Length(FEntries) then
    SetLength(FEntries, FCount * 2 + 8);
  FEntries[FCount] := AEntry;
  Inc(FCount);
end;

function TIniSection.IndexOf(const Tag: AnsiString): Integer;
var
  Wanted: AnsiString;
  Index: Integer;
begin
  Result := -1;
  Wanted := U8Lower(Tag);
  for Index := 0 to FCount - 1 do
    if FEntries[Index].IsEntry and (U8Lower(FEntries[Index].GetTag) = Wanted) then
    begin
      Result := Index;
      Exit;
    end;
end;

function TIniSection.GetName: AnsiString;
begin
  Result := FName;
end;

function TIniSection.AddEntry(const S: AnsiString): PIniEntry;
begin
  Result := TIniEntry.Create(S, FRaw);
  Append(Result);
end;

function TIniSection.AddEntry(const Tag, Value, Comment: AnsiString): PIniEntry;
begin
  Result := TIniEntry.Create(Tag, Value, Comment, FRaw);
  Append(Result);
end;

function TIniSection.SearchEntry(const Tag: AnsiString): PIniEntry;
var
  Found: Integer;
begin
  Found := IndexOf(Tag);
  if Found < 0 then
    Result := nil
  else
    Result := FEntries[Found];
end;

procedure TIniSection.DeleteEntry(const Tag: AnsiString);
var
  Found, Index: Integer;
begin
  Found := IndexOf(Tag);
  if Found < 0 then
    Exit;
  FEntries[Found].Free;
  for Index := Found to FCount - 2 do
    FEntries[Index] := FEntries[Index + 1];
  FEntries[FCount - 1] := nil;
  Dec(FCount);
end;

procedure TIniSection.ForEachEntry(EnumProc: TIniEntryEnumProc);
var
  Index: Integer;
begin
  for Index := 0 to FCount - 1 do
    if FEntries[Index].IsEntry then
      EnumProc(FEntries[Index]);
end;

function TIniSection.Count: Integer;
begin
  Result := FCount;
end;

function TIniSection.Entry(I: Integer): PIniEntry;
begin
  Result := FEntries[I];
end;

{ --- TIniFile --- }

constructor TIniFile.Create(const AFileName: AnsiString);
begin
  inherited Create;
  FFileName := AFileName;
  FSectionCount := 0;
  FModified := False;
  FHasBom := False;
  {$IFDEF UNIX}
  FCrLf := False;
  {$ELSE}
  FCrLf := True;
  {$ENDIF}
  MakeNullEntries := False;
  InlineComments := True;
end;

destructor TIniFile.Destroy;
begin
  ClearSections;
  inherited Destroy;
end;

procedure TIniFile.ClearSections;
var
  Index: Integer;
begin
  for Index := 0 to FSectionCount - 1 do
    FSections[Index].Free;
  FSectionCount := 0;
  SetLength(FSections, 0);
end;

function TIniFile.AddSection(const AName: AnsiString): TIniSection;
begin
  Result := TIniSection.Create(AName, not InlineComments);
  if FSectionCount >= Length(FSections) then
    SetLength(FSections, FSectionCount * 2 + 8);
  FSections[FSectionCount] := Result;
  Inc(FSectionCount);
end;

function TIniFile.IndexOf(const Section: AnsiString): Integer;
var
  Wanted: AnsiString;
  Index: Integer;
begin
  Result := -1;
  Wanted := U8Lower(Section);
  for Index := 0 to FSectionCount - 1 do
    if U8Lower(FSections[Index].GetName) = Wanted then
    begin
      Result := Index;
      Exit;
    end;
end;

procedure TIniFile.Parse(const Text: AnsiString);
var
  TextLen, LineStart, LineBreak, LineEnd: Integer;
  Line, Trimmed: AnsiString;
  Terminated, EndsWithCr: Boolean;
  Current: TIniSection;
begin
  Current := nil;
  TextLen := Length(Text);
  LineStart := 1;
  while LineStart <= TextLen do
  begin
    LineBreak := LineStart;
    while (LineBreak <= TextLen) and (Text[LineBreak] <> #10) do
      Inc(LineBreak);
    Terminated := LineBreak <= TextLen;
    LineEnd := LineBreak - 1;
    EndsWithCr := Terminated and (LineEnd >= LineStart) and (Text[LineEnd] = #13);
    if EndsWithCr then
      Dec(LineEnd);
    Line := Copy(Text, LineStart, LineEnd - LineStart + 1);
    if Terminated then
      FCrLf := EndsWithCr;
    LineStart := LineBreak + 1;

    Trimmed := Trim(Line);
    if (Length(Trimmed) >= 2) and (Trimmed[1] = '[') and (Trimmed[Length(Trimmed)] = ']') then
    begin
      Current := AddSection(Trim(Copy(Trimmed, 2, Length(Trimmed) - 2)));
      Continue;
    end;
    if Current = nil then
      Current := AddSection(MainSectionName);
    Current.AddEntry(Line);
  end;
end;

function TIniFile.GetFileName: AnsiString;
begin
  Result := FFileName;
end;

function TIniFile.IsModified: Boolean;
begin
  Result := FModified;
end;

procedure TIniFile.LoadFromText(const Text: AnsiString);
var
  Body: AnsiString;
begin
  ClearSections;
  FModified := False;
  {$IFDEF UNIX}
  FCrLf := False;
  {$ELSE}
  FCrLf := True;
  {$ENDIF}
  FHasBom := Copy(Text, 1, Length(ByteOrderMark)) = ByteOrderMark;
  if FHasBom then
    Body := Copy(Text, Length(ByteOrderMark) + 1, Length(Text))
  else
    Body := Text;
  Parse(Body);
end;

function TIniFile.SaveToText: AnsiString;
var
  LineEnd: AnsiString;
  SectionIndex, EntryIndex: Integer;
  Section: TIniSection;
begin
  if FCrLf then
    LineEnd := #13#10
  else
    LineEnd := #10;
  Result := '';
  if FHasBom then
    Result := ByteOrderMark;
  for SectionIndex := 0 to FSectionCount - 1 do
  begin
    Section := FSections[SectionIndex];
    if (SectionIndex > 0) or (Section.GetName <> MainSectionName) then
      Result := Result + '[' + Section.GetName + ']' + LineEnd;
    for EntryIndex := 0 to Section.Count - 1 do
      Result := Result + Section.Entry(EntryIndex).GetText + LineEnd;
  end;
end;

function TIniFile.Read: Boolean;
var
  Handle: THandle;
  Chunk: array[0..ReadChunkSize - 1] of Byte;
  Got, OldLen: LongInt;
  Data: AnsiString;
begin
  Result := False;
  if FFileName = '' then
    Exit;
  Handle := FileOpen(FFileName, fmOpenRead or fmShareDenyNone);
  if Handle = feInvalidHandle then
  begin
    LoadFromText('');
    Exit;
  end;
  Data := '';
  repeat
    Got := FileRead(Handle, Chunk, ReadChunkSize);
    if Got > 0 then
    begin
      OldLen := Length(Data);
      SetLength(Data, OldLen + Got);
      Move(Chunk, Data[OldLen + 1], Got);
    end;
  until Got <= 0;
  FileClose(Handle);
  LoadFromText(Data);
  Result := True;
end;

function TIniFile.Update: Boolean;
var
  Text, TempName: AnsiString;
  Handle: THandle;
  Written, Offset, Remaining: LongInt;
  WriteOk: Boolean;
begin
  Result := True;
  if (FFileName = '') or not FModified then
    Exit;
  Result := False;

  if CompareText(ExtractFileExt(FFileName), '.tmp') = 0 then
    TempName := ChangeFileExt(FFileName, '.$$$')
  else
    TempName := ChangeFileExt(FFileName, '.tmp');

  Text := SaveToText;
  Handle := FileCreate(TempName);
  if Handle = feInvalidHandle then
    Exit;
  WriteOk := True;
  Offset := 0;
  while WriteOk and (Offset < Length(Text)) do
  begin
    Remaining := Length(Text) - Offset;
    Written := FileWrite(Handle, Text[Offset + 1], Remaining);
    if Written <= 0 then
      WriteOk := False
    else
      Inc(Offset, Written);
  end;
  FileClose(Handle);
  if not WriteOk then
  begin
    DeleteFile(TempName);
    Exit;
  end;

  {$IFNDEF UNIX}
  if FileExists(FFileName) then
    DeleteFile(FFileName);
  {$ENDIF}
  if not RenameFile(TempName, FFileName) then
  begin
    DeleteFile(TempName);
    Exit;
  end;
  FModified := False;
  Result := True;
end;

function TIniFile.SearchSection(const Section: AnsiString): PIniSection;
var
  Found: Integer;
begin
  Found := IndexOf(Section);
  if Found < 0 then
    Result := nil
  else
    Result := FSections[Found];
end;

function TIniFile.SearchEntry(const Section, Tag: AnsiString): PIniEntry;
var
  Found: PIniSection;
begin
  Result := nil;
  Found := SearchSection(Section);
  if Found = nil then
    Exit;
  Result := Found.SearchEntry(Tag);
end;

procedure TIniFile.ForEachSection(EnumProc: TIniSectionEnumProc);
var
  Index: Integer;
begin
  for Index := 0 to FSectionCount - 1 do
    EnumProc(FSections[Index]);
end;

procedure TIniFile.ForEachEntry(const Section: AnsiString; EnumProc: TIniEntryEnumProc);
var
  Found: PIniSection;
begin
  Found := SearchSection(Section);
  if Found = nil then
    Exit;
  Found.ForEachEntry(EnumProc);
end;

function TIniFile.GetEntry(const Section, Tag, Default: AnsiString): AnsiString;
var
  Found: PIniEntry;
begin
  Found := SearchEntry(Section, Tag);
  if Found = nil then
  begin
    Result := Default;
    if MakeNullEntries then
      SetEntry(Section, Tag, Default);
    Exit;
  end;
  Result := Found.GetValue;
end;

procedure TIniFile.SetEntry(const Section, Tag, Value: AnsiString);
var
  Found: PIniEntry;
  KeptComment: AnsiString;
begin
  Found := SearchEntry(Section, Tag);
  if Found = nil then
    KeptComment := ''
  else
    KeptComment := Found.GetComment;
  SetEntry(Section, Tag, Value, KeptComment);
end;

procedure TIniFile.SetEntry(const Section, Tag, Value, Comment: AnsiString);
var
  Target: PIniSection;
  Found: PIniEntry;
  LastSection: TIniSection;
  TextBefore, TextAfter: AnsiString;
begin
  Target := SearchSection(Section);
  Found := nil;
  if Target <> nil then
    Found := Target.SearchEntry(Tag);

  if Found <> nil then
  begin
    TextBefore := Found.GetText;
    Found.SetValue(Value);
    Found.SetComment(Comment);
    TextAfter := Found.GetText;
    if TextBefore <> TextAfter then
      FModified := True;
    Exit;
  end;

  if (Value = '') and not MakeNullEntries then
    Exit;

  if Target = nil then
  begin
    if FSectionCount > 0 then
    begin
      LastSection := FSections[FSectionCount - 1];
      if (LastSection.Count > 0) and (Trim(LastSection.Entry(LastSection.Count - 1).GetText) <> '') then
        LastSection.AddEntry('');
    end;
    Target := AddSection(Section);
  end;
  Target.AddEntry(Tag, Value, Comment);
  FModified := True;
end;

function TIniFile.GetIntEntry(const Section, Tag: AnsiString; Default: LongInt): LongInt;
var
  Text: AnsiString;
  Parsed: Int64;
begin
  Text := GetEntry(Section, Tag, IntToStr(Default));
  Parsed := StrToInt64Def(Trim(Text), Int64(Default));
  if (Parsed < Low(LongInt)) or (Parsed > High(LongInt)) then
    Result := Default
  else
    Result := LongInt(Parsed);
end;

procedure TIniFile.SetIntEntry(const Section, Tag: AnsiString; Value: LongInt);
begin
  SetEntry(Section, Tag, IntToStr(Value));
end;

function TIniFile.GetBoolEntry(const Section, Tag: AnsiString; Default: Boolean): Boolean;
var
  DefaultText, Lowered: AnsiString;
begin
  if Default then
    DefaultText := '1'
  else
    DefaultText := '0';
  Lowered := U8Lower(Trim(GetEntry(Section, Tag, DefaultText)));
  Result := Default;
  if (Lowered = '1') or (Lowered = 'true') or (Lowered = 'yes') or (Lowered = 'on') then
    Result := True
  else if (Lowered = '0') or (Lowered = 'false') or (Lowered = 'no') or (Lowered = 'off') then
    Result := False;
end;

procedure TIniFile.SetBoolEntry(const Section, Tag: AnsiString; Value: Boolean);
begin
  if Value then
    SetEntry(Section, Tag, '1')
  else
    SetEntry(Section, Tag, '0');
end;

function TIniFile.EntryExists(const Section, Tag: AnsiString): Boolean;
begin
  Result := SearchEntry(Section, Tag) <> nil;
end;

procedure TIniFile.DeleteSection(const Section: AnsiString);
var
  Found, Index: Integer;
begin
  Found := IndexOf(Section);
  if Found < 0 then
    Exit;
  FSections[Found].Free;
  for Index := Found to FSectionCount - 2 do
    FSections[Index] := FSections[Index + 1];
  FSections[FSectionCount - 1] := nil;
  Dec(FSectionCount);
  FModified := True;
end;

procedure TIniFile.DeleteEntry(const Section, Tag: AnsiString);
var
  Target: PIniSection;
begin
  Target := SearchSection(Section);
  if Target = nil then
    Exit;
  if Target.SearchEntry(Tag) = nil then
    Exit;
  Target.DeleteEntry(Tag);
  FModified := True;
end;

function TIniFile.SectionCount: Integer;
begin
  Result := FSectionCount;
end;

function TIniFile.SectionAt(I: Integer): PIniSection;
begin
  Result := FSections[I];
end;

end.
