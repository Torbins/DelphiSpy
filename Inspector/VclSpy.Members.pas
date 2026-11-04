unit VclSpy.Members;

{ The properties of the inspected control as a tree: its own properties, the
  properties of the objects that object properties return (Font.Size,
  Margins.Left), the items of collections, list views and tree views
  (Panels[0].Width, Items[0].Caption), and the fields of the records that
  public properties return (BoundsRect.Left). A member's path names it in
  requests: names joined with ".", collection items as "[index]"
  (JoinPath).

  Object and record properties themselves are read-only; their members are
  read and edited like the control's properties. A record field is written by
  changing it in the record the property returned and passing that record to
  the property's setter, so the fields of a record property without a setter
  are read-only. Objects that are other components (Action, PopupMenu,
  Images) are references, not part of the control: their members are not
  reached. Subcomponents (TLabeledEdit.EditLabel) are.

  Objects show their published and public properties, the control its
  published properties and public record properties (records can't be
  published). Published properties come from RTTI, public ones from extended
  RTTI (System.Rtti), which the RTL and VCL have for public properties and
  for record fields. Public getters that change the object
  (TPicture.Bitmap) are skipped. Running in a no-packages inspector,
  System.Rtti reads the target's type information, which has the
  inspector's layout (VclSpy.Target). }

interface

uses
  System.SysUtils, System.TypInfo, System.Rtti, Vcl.Controls, VclSpy.Properties;

type
  TMemberKind = (mkPublished, mkExtra, mkPublic, mkField, mkItem);

  // The value of a record property, read once. Its fields are changed in Data
  // and written back with the property's setter.
  IRecordValue = interface
    function Data: Pointer;
    // Empty if the record can be written back
    function ReadOnlyReason: string;
    procedure Write;
  end;

  TMember = record
    Name, Scope: string;
    Info: PTypeInfo;
    Kind: TMemberKind;
    Instance: TObject;       // the object of a property; the list of an item
    Prop: PPropInfo;         // mkPublished
    Extra: TExtraProp;       // mkExtra
    RttiProp: TRttiInstanceProperty; // mkPublic
    Rec: IRecordValue;       // mkField: the record the field is part of
    Data: Pointer;           // mkField: the field in Rec.Data
    Index: Integer;          // mkItem
    function IsObject: Boolean;
    function IsRecord: Boolean;
    // The value of an object member, or nil
    function GetObject: TObject;
    // The full value of a member that isn't an object
    function ValueText: string;
    function IsEditable: Boolean;
    // Raises EConvertError with a message for the user when the member can't
    // be edited or the text doesn't fit its type
    procedure SetValueText(const Text: string);
    // The fields of a record member. The record is read once for all of them.
    function Fields: TArray<TMember>;
  end;

// The control's published properties, the ExtraProps its class doesn't
// publish and its public record properties, sorted by name
function ControlMembers(Ctrl: TControl): TArray<TMember>;
// The published and public properties of Obj, sorted by name, then the
// items of a collection, of a list view or of a tree view
function ObjectMembers(Obj: TObject): TArray<TMember>;
// Whether the members of Obj, the value of an object property, are shown:
// not those of other components
function ShowsMembers(Obj: TObject): Boolean;
// The member that Path names; raises EConvertError if there is none
function FindMember(Ctrl: TControl; const Path: string): TMember;
function JoinPath(const Path, Name: string): string;

implementation

uses
  System.Classes, System.Variants, System.Generics.Collections, System.Generics.Defaults, Vcl.Graphics,
  Vcl.ComCtrls, VclSpy.Target;

const
  // Items of a collection, list view or tree view that are shown
  MaxItems = 100;

var
  // Keeps the RTTI objects that members refer to
  Context: TRttiContext;

{ Values in memory: record fields }

function ReadOrd(Info: PTypeInfo; P: Pointer): Int64;
begin
  case GetTypeData(Info)^.OrdType of
    otSByte: Result := PShortInt(P)^;
    otUByte: Result := PByte(P)^;
    otSWord: Result := PSmallInt(P)^;
    otUWord: Result := PWord(P)^;
    otSLong: Result := PInteger(P)^;
  else
    Result := PCardinal(P)^;
  end;
end;

procedure WriteOrd(Info: PTypeInfo; P: Pointer; Value: Int64);
begin
  case GetTypeData(Info)^.OrdType of
    otSByte, otUByte: PByte(P)^ := Byte(Value);
    otSWord, otUWord: PWord(P)^ := Word(Value);
  else
    PCardinal(P)^ := Cardinal(Value);
  end;
end;

function TypeSize(Info: PTypeInfo): Integer;
begin
  Result := Context.GetType(Info).TypeSize;
end;

function ReadFloat(Info: PTypeInfo; P: Pointer): Extended;
begin
  case GetTypeData(Info)^.FloatType of
    ftSingle: Result := PSingle(P)^;
    ftDouble: Result := PDouble(P)^;
    ftExtended: Result := PExtended(P)^;
    ftComp: Result := PComp(P)^;
  else
    Result := PCurrency(P)^;
  end;
end;

procedure WriteFloat(Info: PTypeInfo; P: Pointer; Value: Extended);
begin
  case GetTypeData(Info)^.FloatType of
    ftSingle: PSingle(P)^ := Value;
    ftDouble: PDouble(P)^ := Value;
    ftExtended: PExtended(P)^ := Value;
    ftComp: PComp(P)^ := Value;
  else
    PCurrency(P)^ := Value;
  end;
end;

function MemoryText(Info: PTypeInfo; P: Pointer): string; forward;

// "(Left = 0, Top = 0, ...)"
function RecordText(Info: PTypeInfo; P: Pointer): string;
var
  RecType: TRttiType;
  Field: TRttiField;
begin
  Result := '';
  RecType := Context.GetType(Info);
  if RecType <> nil then
    for Field in RecType.GetFields do
      if Field.FieldType <> nil then
      begin
        if Result <> '' then
          Result := Result + ', ';
        Result := Result + Field.Name + ' = ' + MemoryText(Field.FieldType.Handle, PByte(P) + Field.Offset);
      end;
  Result := '(' + Result + ')';
end;

function MemoryText(Info: PTypeInfo; P: Pointer): string;
var
  SetValue: Cardinal;
  Obj: TObject;
begin
  case Info^.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration:
      Result := OrdToText(Info, ReadOrd(Info, P));
    tkSet:
      if IsEditableType(Info) then
      begin
        SetValue := 0;
        Move(P^, SetValue, TypeSize(Info));
        Result := OrdToText(Info, SetValue);
      end
      else if SetElementType(Info) <> nil then
        Result := SetToString(Info, P, True)
      else
        Result := '(set)';
    tkInt64:
      Result := IntToStr(PInt64(P)^);
    tkFloat:
      if IsDateTimeType(Info) then
        Result := DateTimeToStr(ReadFloat(Info, P))
      else
        Result := FloatToStr(ReadFloat(Info, P));
    tkUString:
      Result := PUnicodeString(P)^;
    tkLString:
      Result := string(PAnsiString(P)^);
    tkWString:
      Result := PWideString(P)^;
    tkString:
      Result := string(PShortString(P)^);
    tkVariant:
      Result := VarToStr(PVariant(P)^);
    tkClass:
      begin
        Obj := TObject(PPointer(P)^);
        if Obj = nil then
          Result := '(nil)'
        else
          Result := '(' + Obj.ClassName + ')';
      end;
    tkInterface:
      if PPointer(P)^ <> nil then
        Result := '(interface)'
      else
        Result := '(nil)';
    tkRecord, tkMRecord:
      Result := RecordText(Info, P);
    tkPointer, tkClassRef, tkProcedure:
      Result := Format('$%p', [PPointer(P)^]);
  else
    Result := '';
  end;
end;

procedure SetMemoryText(Info: PTypeInfo; P: Pointer; const Text: string);
var
  SetValue: Cardinal;
begin
  case Info^.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration:
      WriteOrd(Info, P, TextToOrd(Info, Text));
    tkSet:
      begin
        SetValue := Cardinal(TextToOrd(Info, Text));
        Move(SetValue, P^, TypeSize(Info));
      end;
    tkInt64:
      PInt64(P)^ := TextToOrd(Info, Text);
    tkFloat:
      WriteFloat(Info, P, TextToFloat(Info, Text));
    tkUString:
      PUnicodeString(P)^ := Text;
    tkLString:
      PAnsiString(P)^ := AnsiString(Text);
    tkWString:
      PWideString(P)^ := Text;
    tkString:
      PShortString(P)^ := ShortString(Copy(Text, 1, GetTypeData(Info)^.MaxLength));
  else
    raise EConvertError.CreateFmt('Values of type %s cannot be edited.', [GetTypeName(Info)]);
  end;
end;

{ TRecordValue }

type
  TRecordValue = class(TInterfacedObject, IRecordValue)
  private
    FInstance: TObject;
    FProp: TRttiProperty;
    FValue: TValue;
  public
    constructor Create(Instance: TObject; Prop: TRttiProperty);
    function Data: Pointer;
    function ReadOnlyReason: string;
    procedure Write;
  end;

constructor TRecordValue.Create(Instance: TObject; Prop: TRttiProperty);
begin
  inherited Create;
  FInstance := Instance;
  FProp := Prop;
  FValue := Prop.GetValue(Instance);
end;

function TRecordValue.Data: Pointer;
begin
  Result := FValue.GetReferenceToRawData;
end;

// The target's setter would keep the strings (or other managed values) of
// the record, which the inspector's memory manager allocated
function HasManagedFields(RecType: TRttiType): Boolean;
begin
  Result := (RecType.TypeKind = tkMRecord) or
    ((RecType is TRttiRecordType) and (Length(TRttiRecordType(RecType).ManagedFields) > 0));
end;

function TRecordValue.ReadOnlyReason: string;
begin
  if not FProp.IsWritable then
    Result := Format('%s is read-only.', [FProp.Name])
  else if not TargetMayKeepOurMemory and HasManagedFields(FProp.PropertyType) then
    Result := Format('%s (%s) has managed fields, and the inspector doesn''t share the target''s ' +
      'memory manager.', [FProp.Name, FProp.PropertyType.Name])
  else
    Result := '';
end;

procedure TRecordValue.Write;
begin
  FProp.SetValue(FInstance, FValue);
end;

{ Item lists: collections, and the items of list views and tree views }

function IsItemList(Obj: TObject): Boolean;
begin
  Result := IsKindOf(Obj, TCollection) or IsKindOf(Obj, TListItems) or IsKindOf(Obj, TTreeNodes);
end;

function ItemCount(List: TObject): Integer;
begin
  if IsKindOf(List, TCollection) then
    Result := TCollection(List).Count
  else if IsKindOf(List, TListItems) then
    Result := TListItems(List).Count
  else
    Result := TTreeNodes(List).Count;
end;

// Tree nodes by their absolute index: parents before their children
function ItemAt(List: TObject; Index: Integer): TObject;
begin
  if IsKindOf(List, TCollection) then
    Result := TCollection(List).Items[Index]
  else if IsKindOf(List, TListItems) then
    Result := TListItems(List).Item[Index]
  else
    Result := TTreeNodes(List).Item[Index];
end;

// Public properties whose getters change the object: reading TPicture.Bitmap
// turns a picture of another kind (the PNG of a TImage) into a bitmap
function IsSkipped(Obj: TObject; const Name: string): Boolean;
begin
  Result := IsKindOf(Obj, TPicture) and (SameText(Name, 'Bitmap') or SameText(Name, 'Icon') or
    SameText(Name, 'Metafile') or SameText(Name, 'WICImage'));
end;

{ TMember }

function TMember.IsObject: Boolean;
begin
  Result := Info^.Kind = tkClass;
end;

function TMember.IsRecord: Boolean;
begin
  Result := Info^.Kind in [tkRecord, tkMRecord];
end;

function TMember.GetObject: TObject;
begin
  case Kind of
    mkPublished: Result := GetObjectProp(Instance, Prop);
    mkPublic: Result := RttiProp.GetValue(Instance).AsObject;
    mkField: Result := TObject(PPointer(Data)^);
    mkItem: Result := ItemAt(Instance, Index);
  else
    Result := nil;
  end;
end;

function TMember.ValueText: string;
var
  Value: TValue;
begin
  case Kind of
    mkPublished:
      Result := PublishedText(Instance, Prop);
    mkExtra:
      Result := Extra.ValueText(TControl(Instance));
    mkPublic:
      begin
        Value := RttiProp.GetValue(Instance);
        Result := MemoryText(Info, Value.GetReferenceToRawData);
      end;
    mkField:
      Result := MemoryText(Info, Data);
    mkItem:
      Result := '(' + GetObject.ClassName + ')';
  end;
end;

function TMember.IsEditable: Boolean;
begin
  case Kind of
    mkPublished: Result := IsEditablePublished(Prop);
    mkExtra: Result := Extra.IsEditable;
    mkPublic: Result := RttiProp.IsWritable and IsEditableType(Info) and CanSetString(RttiProp.PropInfo);
    mkField: Result := IsEditableType(Info) and (Rec.ReadOnlyReason = '');
  else
    Result := False;
  end;
end;

procedure TMember.SetValueText(const Text: string);
var
  Reason: string;
  Value: TValue;
  RefCount: PInteger;
begin
  if IsObject then
    raise EConvertError.CreateFmt('%s (%s) is an object: edit its properties instead.', [Name, GetTypeName(Info)]);
  if IsRecord then
    raise EConvertError.CreateFmt('%s (%s) is a record: edit its fields instead.', [Name, GetTypeName(Info)]);
  case Kind of
    mkPublished:
      SetPublishedText(Instance, Prop, Text);
    mkExtra:
      Extra.SetValueText(TControl(Instance), Text);
    mkPublic:
      begin
        if not IsEditableType(Info) then
          raise EConvertError.CreateFmt('%s (%s) cannot be edited in VclSpy.', [Name, GetTypeName(Info)]);
        if not RttiProp.IsWritable then
          raise EConvertError.CreateFmt('%s is read-only.', [Name]);
        if not CanSetString(RttiProp.PropInfo) then
          raise EConvertError.CreateFmt('%s (%s) cannot be edited: the inspector doesn''t share the ' +
            'target''s memory manager.', [Name, GetTypeName(Info)]);
        TValue.Make(nil, Info, Value);
        SetMemoryText(Info, Value.GetReferenceToRawData, Text);
        // RTTI hands this very string to the setter
        if (Info^.Kind = tkUString) and not TargetMayKeepOurMemory then
          RefCount := MakeLiteral(PUnicodeString(Value.GetReferenceToRawData)^)
        else
          RefCount := nil;
        try
          RttiProp.SetValue(Instance, Value);
        finally
          EndLiteral(RefCount);
        end;
      end;
    mkField:
      begin
        if not IsEditableType(Info) then
          raise EConvertError.CreateFmt('%s (%s) cannot be edited in VclSpy.', [Name, GetTypeName(Info)]);
        Reason := Rec.ReadOnlyReason;
        if Reason <> '' then
          raise EConvertError.CreateFmt('%s cannot be edited: %s', [Name, Reason]);
        SetMemoryText(Info, Data, Text);
        Rec.Write;
      end;
  else
    raise EConvertError.CreateFmt('%s (%s) cannot be edited in VclSpy.', [Name, GetTypeName(Info)]);
  end;
end;

function TMember.Fields: TArray<TMember>;
var
  Value: IRecordValue;
  Base: PByte;
  RecType: TRttiType;
  Field: TRttiField;
  M: TMember;
begin
  Result := nil;
  if not IsRecord then
    Exit;
  case Kind of
    mkPublic:
      begin
        Value := TRecordValue.Create(Instance, RttiProp);
        Base := Value.Data;
      end;
    mkField:
      begin
        Value := Rec;
        Base := Data;
      end;
  else
    Exit; // records can't be published
  end;
  RecType := Context.GetType(Info);
  if RecType = nil then
    Exit;
  for Field in RecType.GetFields do
    if Field.FieldType <> nil then
    begin
      M := Default(TMember);
      M.Name := Field.Name;
      M.Scope := 'field';
      M.Info := Field.FieldType.Handle;
      M.Kind := mkField;
      M.Rec := Value;
      M.Data := Base + Field.Offset;
      Result := Result + [M];
    end;
end;

{ Lists }

function IndexOfName(const List: TArray<TMember>; const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(List) do
    if SameText(List[I].Name, Name) then
      Exit(I);
  Result := -1;
end;

procedure AddPublished(var List: TArray<TMember>; Obj: TObject);
var
  Count, I: Integer;
  Props: PPropList;
  Prop: PPropInfo;
  M: TMember;
begin
  if Obj.ClassInfo = nil then
    Exit;
  // Props isn't assigned without properties (TBitmap)
  Count := GetPropList(PTypeInfo(Obj.ClassInfo), Props);
  if Count = 0 then
    Exit;
  try
    for I := 0 to Count - 1 do
    begin
      Prop := Props^[I];
      // Events are reported apart; write-only properties can't be shown
      if (Prop^.GetProc = nil) or (Prop^.PropType^.Kind = tkMethod) then
        Continue;
      M := Default(TMember);
      M.Name := GetPropName(Prop);
      M.Scope := 'published';
      M.Info := Prop^.PropType^;
      M.Kind := mkPublished;
      M.Instance := Obj;
      M.Prop := Prop;
      List := List + [M];
    end;
  finally
    FreeMem(Props);
  end;
end;

// Public record properties; with AllKinds all public properties but events
// and those IsSkipped
procedure AddPublic(var List: TArray<TMember>; Obj: TObject; AllKinds: Boolean);
var
  ObjType: TRttiType;
  Prop: TRttiProperty;
  M: TMember;
begin
  if Obj.ClassInfo = nil then
    Exit;
  ObjType := Context.GetType(Obj.ClassType);
  if ObjType = nil then
    Exit;
  // The class's own properties come first, then those of its ancestors, which
  // it may hide
  for Prop in ObjType.GetProperties do
    if (Prop.Visibility = mvPublic) and Prop.IsReadable and (Prop is TRttiInstanceProperty) and
      (Prop.PropertyType <> nil) and (IndexOfName(List, Prop.Name) < 0) and
      ((Prop.PropertyType.TypeKind in [tkRecord, tkMRecord]) or
      (AllKinds and (Prop.PropertyType.TypeKind <> tkMethod) and not IsSkipped(Obj, Prop.Name))) then
    begin
      M := Default(TMember);
      M.Name := Prop.Name;
      M.Scope := 'public';
      M.Info := Prop.PropertyType.Handle;
      M.Kind := mkPublic;
      M.Instance := Obj;
      M.RttiProp := TRttiInstanceProperty(Prop);
      List := List + [M];
    end;
end;

procedure SortByName(var List: TArray<TMember>);
begin
  TArray.Sort<TMember>(List, TComparer<TMember>.Construct(
    function(const L, R: TMember): Integer
    begin
      Result := CompareText(L.Name, R.Name);
    end));
end;

procedure AddItems(var List: TArray<TMember>; Items: TObject);
var
  I: Integer;
  Item: TObject;
  M: TMember;
begin
  for I := 0 to ItemCount(Items) - 1 do
  begin
    if I = MaxItems then
      Break;
    Item := ItemAt(Items, I);
    if Item.ClassInfo = nil then
      Continue;
    M := Default(TMember);
    M.Name := Format('[%d]', [I]);
    M.Scope := 'item';
    M.Info := PTypeInfo(Item.ClassInfo);
    M.Kind := mkItem;
    M.Instance := Items;
    M.Index := I;
    List := List + [M];
  end;
end;

function ControlMembers(Ctrl: TControl): TArray<TMember>;
var
  Extra: TExtraProp;
  M: TMember;
begin
  Result := nil;
  AddPublished(Result, Ctrl);
  for Extra in ExtraPropsOf(Ctrl) do
  begin
    M := Default(TMember);
    M.Name := Extra.Name;
    M.Scope := Extra.Scope;
    M.Info := Extra.Info;
    M.Kind := mkExtra;
    M.Instance := Ctrl;
    M.Extra := Extra;
    Result := Result + [M];
  end;
  AddPublic(Result, Ctrl, False);
  SortByName(Result);
end;

function ObjectMembers(Obj: TObject): TArray<TMember>;
begin
  Result := nil;
  AddPublished(Result, Obj);
  AddPublic(Result, Obj, True);
  SortByName(Result);
  if IsItemList(Obj) then
    AddItems(Result, Obj);
end;

function ShowsMembers(Obj: TObject): Boolean;
begin
  Result := (Obj <> nil) and
    (not IsKindOf(Obj, TComponent) or (csSubComponent in TComponent(Obj).ComponentStyle));
end;

{ Paths }

function JoinPath(const Path, Name: string): string;
begin
  if Path = '' then
    Result := Name
  else if Name.StartsWith('[') then
    Result := Path + Name
  else
    Result := Path + '.' + Name;
end;

// "Panels[0].Width": Panels, [0], Width
function SplitPath(const Path: string): TArray<string>;
var
  I, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(Path) + 1 do
    if (I > Length(Path)) or (Path[I] = '.') or (Path[I] = '[') then
    begin
      if I > Start then
        Result := Result + [Trim(Copy(Path, Start, I - Start))];
      if (I <= Length(Path)) and (Path[I] = '.') then
        Start := I + 1
      else
        Start := I;
    end;
end;

function FindMember(Ctrl: TControl; const Path: string): TMember;
var
  Names: TArray<string>;
  Members: TArray<TMember>;
  Owner, Walked: string;
  I, Found: Integer;
  Obj: TObject;
begin
  Names := SplitPath(Path);
  if Names = nil then
    raise EConvertError.Create('The request needs "property".');
  Members := ControlMembers(Ctrl);
  Owner := Ctrl.ClassName;
  Walked := '';
  for I := 0 to High(Names) do
  begin
    Found := IndexOfName(Members, Names[I]);
    if Found < 0 then
      raise EConvertError.CreateFmt('%s has no property %s.', [Owner, Names[I]]);
    Result := Members[Found];
    if I = High(Names) then
      Exit;
    Walked := JoinPath(Walked, Result.Name);
    Owner := Walked;
    if Result.IsObject then
    begin
      Obj := Result.GetObject;
      if Obj = nil then
        raise EConvertError.CreateFmt('%s is nil.', [Walked]);
      if not ShowsMembers(Obj) then
        raise EConvertError.CreateFmt('%s refers to another component, %s: %s. VclSpy doesn''t edit it.',
          [Walked, TComponent(Obj).Name, Obj.ClassName]);
      Members := ObjectMembers(Obj);
    end
    else if Result.IsRecord then
      Members := Result.Fields
    else
      Members := nil;
  end;
end;

initialization
  Context := TRttiContext.Create;
finalization
  Context.Free;
end.
