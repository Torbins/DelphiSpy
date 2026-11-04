unit DelphiSpy.Properties;

{ Converts property values between their text form, as DelphiSpy shows and
  edits them, and the target's own values. Runs inside the target, like
  DelphiSpy.Inspector.

  Editable are published properties of simple types (numbers, characters,
  strings, enumerations, sets of up to 32 elements) and the extra properties
  that a framework's unit registers (RegisterExtraProp): DelphiSpy.VclProperties
  adds the TControl and TWinControl properties declared public or protected,
  which RTTI doesn't list unless a class republishes them. DelphiSpy.Members
  reaches the properties of objects and the fields of records that properties
  return.

  This unit knows no framework. The names of integer types, such as TColor's
  clRed, come from the framework's units too (RegisterOrdNames).

  A no-packages inspector that doesn't share the target's memory manager
  (DelphiSpy.Target.TargetMayKeepOurMemory) must not let the target keep a
  string it allocated: the target would free it with its own memory manager.
  String setters of the target get a copy that looks like a string literal,
  which they copy when they assign it. Strings that the inspector's code
  would store itself (field setters, StyleName, ImeName, AnsiString
  properties) are read-only then. }

interface

uses
  System.SysUtils, System.Classes, System.TypInfo, System.JSON;

type
  // A property of the instances of Cls that RTTI doesn't list, because it is
  // declared public or protected (TControl.Caption). Ordinal values
  // (Boolean, enumerations, small sets, integers) go through GetOrd/SetOrd,
  // strings through GetStr/SetStr. No setter means read-only. KeepsString:
  // SetStr stores the string in the object (in framework code of the
  // inspector), instead of handing the object's window a copy.
  TExtraProp = record
    Name, Scope: string;
    Info: PTypeInfo;
    Cls: TClass;
    KeepsString: Boolean;
    GetOrd: TFunc<TObject, Integer>;
    SetOrd: TProc<TObject, Integer>;
    GetStr: TFunc<TObject, string>;
    SetStr: TProc<TObject, string>;
    function AppliesTo(Obj: TObject): Boolean;
    function IsString: Boolean;
    function IsEditable: Boolean;
    function ValueText(Obj: TObject): string;
    procedure SetValueText(Obj: TObject; const Text: string);
  end;

  // Value is the number that Text names (clRed), or that Text is
  TTextToOrdFunc = reference to function(const Text: string; out Value: Integer): Boolean;

  // Names for the values of an integer type (TColor: clRed)
  TOrdNames = record
    ToText: TFunc<Integer, string>;
    FromText: TTextToOrdFunc;
    // The names DelphiSpy's editor offers; may be nil
    GetValues: TProc<TGetStrProc>;
    // The message when FromText fails, with %s for the text
    Error: string;
  end;

function OrdToText(Info: PTypeInfo; Value: Int64): string;
function IsDateTimeType(Info: PTypeInfo): Boolean;
// The element type of a set, or nil if it has no type information
function SetElementType(Info: PTypeInfo): PTypeInfo;
// Parse text for a type; raise EConvertError with a message for the user
// when the text doesn't fit it
function TextToOrd(Info: PTypeInfo; const Text: string): Int64;
function TextToFloat(Info: PTypeInfo; const Text: string): Extended;
// Types whose values DelphiSpy edits as text
function IsEditableType(Info: PTypeInfo): Boolean;

// Whether the target may keep the string that the setter of Prop gets (see
// TargetMayKeepOurMemory); with MakeLiteral if it's a UnicodeString
function CanSetString(Prop: PPropInfo): Boolean;
// Makes S look like a string literal (reference count -1) until EndLiteral,
// so that the target's code copies it when it assigns it. nil for ''.
function MakeLiteral(var S: string): PInteger;
procedure EndLiteral(RefCount: PInteger);

// The full value of a published property; objects only by class name
function PublishedText(Instance: TObject; Prop: PPropInfo): string;
function IsEditablePublished(Prop: PPropInfo): Boolean;
// Sets a published property; raises EConvertError with a message for the
// user when it can't be edited or the text doesn't fit its type
procedure SetPublishedText(Instance: TObject; Prop: PPropInfo; const Text: string);

procedure RegisterExtraProp(const Prop: TExtraProp);
// The extra properties of Obj that its class doesn't publish
function ExtraPropsOf(Obj: TObject): TArray<TExtraProp>;

// For the integer type named TypeName (TColor)
procedure RegisterOrdNames(const TypeName: string; const Names: TOrdNames);

// "integer", "enum", "set", "string"... for DelphiSpy's editor
function KindName(Info: PTypeInfo): string;
// Names DelphiSpy offers in its editor: enumeration values, set elements, color
// and cursor names. nil for types without names.
function TypeValuesJson(Info: PTypeInfo): TJSONArray;

implementation

uses
  System.Variants, DelphiSpy.Target;

type
  TOrdNamesEntry = record
    TypeName: string;
    Names: TOrdNames;
  end;

const
  // Offset of StrRec.refCnt from the first character, on Win32 and Win64
  StrRefCountOffset = -8;

var
  ExtraProps: TArray<TExtraProp>;
  OrdNames: TArray<TOrdNamesEntry>;

{ Text form }

function IsType(Info: PTypeInfo; const Name: string): Boolean;
begin
  Result := SameText(GetTypeName(Info), Name);
end;

procedure RegisterOrdNames(const TypeName: string; const Names: TOrdNames);
var
  Entry: TOrdNamesEntry;
begin
  Entry.TypeName := TypeName;
  Entry.Names := Names;
  OrdNames := OrdNames + [Entry];
end;

function FindOrdNames(Info: PTypeInfo; out Names: TOrdNames): Boolean;
var
  Entry: TOrdNamesEntry;
begin
  if Info^.Kind = tkInteger then
    for Entry in OrdNames do
      if IsType(Info, Entry.TypeName) then
      begin
        Names := Entry.Names;
        Exit(True);
      end;
  Result := False;
end;

function IsDateTimeType(Info: PTypeInfo): Boolean;
begin
  Result := IsType(Info, 'TDateTime') or IsType(Info, 'TDate') or IsType(Info, 'TTime');
end;

function OrdToText(Info: PTypeInfo; Value: Int64): string;
var
  Names: TOrdNames;
begin
  case Info^.Kind of
    tkInteger:
      if FindOrdNames(Info, Names) then
        Result := Names.ToText(Integer(Value))
      else if GetTypeData(Info)^.OrdType = otULong then
        Result := UIntToStr(Cardinal(Value))
      else
        Result := IntToStr(Value);
    tkChar, tkWChar:
      Result := '#' + IntToStr(Value);
    tkEnumeration:
      Result := GetEnumName(Info, Integer(Value));
    tkSet:
      Result := SetToString(Info, Integer(Value), True);
  else
    Result := IntToStr(Value);
  end;
end;

function EnumNames(Info: PTypeInfo): string;
var
  Data: PTypeData;
  I: Integer;
begin
  Data := GetTypeData(Info);
  if Data^.MinValue < 0 then // ByteBool, WordBool, LongBool
    Exit('False, True');
  Result := '';
  for I := Data^.MinValue to Data^.MaxValue do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + GetEnumName(Info, I);
  end;
end;

procedure CheckRange(Info: PTypeInfo; Value: Int64);
var
  Data: PTypeData;
  Min, Max: Int64;
begin
  Data := GetTypeData(Info);
  if Info^.Kind = tkInt64 then
  begin
    Min := Data^.MinInt64Value;
    Max := Data^.MaxInt64Value;
  end
  else if (Info^.Kind = tkInteger) and (Data^.OrdType = otULong) then
  begin
    Min := 0;
    Max := Cardinal(Data^.MaxValue);
  end
  else
  begin
    Min := Data^.MinValue;
    Max := Data^.MaxValue;
  end;
  if (Value < Min) or (Value > Max) then
    raise EConvertError.CreateFmt('%d is out of range for %s (%d..%d).',
      [Value, GetTypeName(Info), Min, Max]);
end;

function TextToOrd(Info: PTypeInfo; const Text: string): Int64;
var
  S: string;
  Ident: Integer;
  Names: TOrdNames;
begin
  S := Trim(Text);
  case Info^.Kind of
    tkInteger, tkInt64:
      begin
        if FindOrdNames(Info, Names) then
        begin
          if not Names.FromText(S, Ident) then
            raise EConvertError.CreateFmt(Names.Error, [Text]);
          if GetTypeData(Info)^.OrdType = otULong then
            Result := Cardinal(Ident) // TAlphaColor
          else
            Result := Ident;
        end
        else if not TryStrToInt64(S, Result) then
          raise EConvertError.CreateFmt('"%s" is not an integer.', [Text]);
        CheckRange(Info, Result);
      end;
    tkChar, tkWChar:
      begin
        if Length(Text) = 1 then
          Result := Ord(Text[1])
        else if (Length(S) < 2) or (S[1] <> '#') or not TryStrToInt64(Copy(S, 2, MaxInt), Result) then
          raise EConvertError.CreateFmt('"%s" is not a character. Type one character, or #code.', [Text]);
        CheckRange(Info, Result);
      end;
    tkEnumeration:
      begin
        Result := GetEnumValue(Info, S);
        // GetEnumValue finds names of the base type, also outside a subrange
        if (GetTypeData(Info)^.MinValue >= 0) and
          ((Result < GetTypeData(Info)^.MinValue) or (Result > GetTypeData(Info)^.MaxValue)) then
          raise EConvertError.CreateFmt('"%s" is not a %s value. Use one of: %s.',
            [Text, GetTypeName(Info), EnumNames(Info)]);
      end;
    tkSet:
      try
        Result := StringToSet(Info, S);
      except
        on E: EPropertyConvertError do
          raise EConvertError.CreateFmt('"%s" is not a %s value (%s). Use a list of: %s.',
            [Text, GetTypeName(Info), E.Message, EnumNames(GetTypeData(Info)^.CompType^)]);
      end;
  else
    raise EConvertError.CreateFmt('Values of type %s cannot be edited.', [GetTypeName(Info)]);
  end;
end;

function TextToFloat(Info: PTypeInfo; const Text: string): Extended;
var
  S: string;
  D: TDateTime;
begin
  S := Trim(Text);
  if IsDateTimeType(Info) then
  begin
    if not TryStrToDateTime(S, D) then
      raise EConvertError.CreateFmt('"%s" is not a date/time. Use the format shown, e.g. %s.',
        [Text, DateTimeToStr(Now)]);
    Result := D;
  end
  // The value shown uses the target's decimal separator; accept "." as well
  else if not TryStrToFloat(S, Result) and not TryStrToFloat(S, Result, TFormatSettings.Invariant) then
    raise EConvertError.CreateFmt('"%s" is not a number.', [Text]);
end;

function SetElementType(Info: PTypeInfo): PTypeInfo;
var
  Comp: PPTypeInfo;
begin
  Comp := GetTypeData(Info)^.CompType;
  if Comp = nil then
    Result := nil
  else
    Result := Comp^;
end;

{ Published properties }

function IsEditableType(Info: PTypeInfo): Boolean;
var
  Comp: PTypeInfo;
begin
  case Info^.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration, tkInt64, tkFloat,
    tkString, tkLString, tkWString, tkUString:
      Result := True;
    tkSet:
      begin
        // GetOrdProp/SetOrdProp hold sets of up to 32 elements
        Comp := SetElementType(Info);
        Result := (Comp <> nil) and (Comp^.Kind = tkEnumeration) and (GetTypeData(Comp)^.MinValue >= 0) and
          (GetTypeData(Comp)^.MaxValue < 32);
      end;
  else
    Result := False;
  end;
end;

// TComponent.Name: writable, but renaming breaks FindComponent lookups and the
// paths DelphiSpy shows. Other properties named so (Font.Name) are editable.
function IsComponentName(Prop: PPropInfo): Boolean;
begin
  Result := SameText(GetPropName(Prop), 'Name') and IsType(Prop^.PropType^, 'TComponentName');
end;

// Whether the target may keep the string a setter of Prop gets. In a
// no-packages inspector with its own memory manager, only if the target's
// setter assigns it, and copies it (SetLiteralStrProp). ShortString and
// WideString values are not on either memory manager's heap.
function CanSetString(Prop: PPropInfo): Boolean;
begin
  case Prop^.PropType^^.Kind of
    tkLString:
      Result := TargetMayKeepOurMemory;
    tkUString:
      Result := TargetMayKeepOurMemory or
        ((NativeUInt(Prop^.SetProc) and PROPSLOT_MASK) <> PROPSLOT_FIELD);
  else
    Result := True;
  end;
end;

function IsEditablePublished(Prop: PPropInfo): Boolean;
begin
  Result := (Prop^.SetProc <> nil) and IsEditableType(Prop^.PropType^) and
    not IsComponentName(Prop) and CanSetString(Prop);
end;

// Assigning a string whose reference count is -1, like a string literal's,
// makes a copy, with the target's memory manager when the target's code
// assigns it
function MakeLiteral(var S: string): PInteger;
begin
  if S = '' then
    Exit(nil);
  UniqueString(S);
  Result := PInteger(PByte(Pointer(S)) + StrRefCountOffset);
  Result^ := -1;
end;

procedure EndLiteral(RefCount: PInteger);
begin
  if RefCount <> nil then
    RefCount^ := 1;
end;

// Calls the setter with a copy of Text that looks like a string literal
procedure SetLiteralStrProp(Instance: TObject; Prop: PPropInfo; const Text: string);
var
  S: string;
  RefCount: PInteger;
begin
  S := Text;
  RefCount := MakeLiteral(S);
  try
    SetStrProp(Instance, Prop, S);
  finally
    EndLiteral(RefCount);
  end;
end;

function PublishedText(Instance: TObject; Prop: PPropInfo): string;
var
  Info: PTypeInfo;
  Obj: TObject;
begin
  Info := Prop^.PropType^;
  case Info^.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration, tkSet:
      Result := OrdToText(Info, GetOrdProp(Instance, Prop));
    tkInt64:
      Result := IntToStr(GetInt64Prop(Instance, Prop));
    tkFloat:
      if IsDateTimeType(Info) then
        Result := DateTimeToStr(GetFloatProp(Instance, Prop))
      else
        Result := FloatToStr(GetFloatProp(Instance, Prop));
    tkString, tkLString, tkWString, tkUString:
      Result := GetStrProp(Instance, Prop);
    tkVariant:
      Result := VarToStr(GetVariantProp(Instance, Prop));
    tkClass:
      begin
        Obj := GetObjectProp(Instance, Prop);
        if Obj = nil then
          Result := '(nil)'
        else
          Result := '(' + Obj.ClassName + ')';
      end;
    tkInterface:
      if GetInterfaceProp(Instance, Prop) <> nil then
        Result := '(interface)'
      else
        Result := '(nil)';
  else
    Result := '';
  end;
end;

procedure SetPublishedText(Instance: TObject; Prop: PPropInfo; const Text: string);
var
  Info: PTypeInfo;
begin
  Info := Prop^.PropType^;
  if (Prop^.SetProc <> nil) and IsEditableType(Info) and not CanSetString(Prop) then
    raise EConvertError.CreateFmt('%s (%s) cannot be edited: the inspector doesn''t share the ' +
      'target''s memory manager.', [GetPropName(Prop), GetTypeName(Info)]);
  if not IsEditablePublished(Prop) then
    raise EConvertError.CreateFmt('%s (%s) cannot be edited in DelphiSpy.', [GetPropName(Prop), GetTypeName(Info)]);
  case Info^.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration, tkSet:
      SetOrdProp(Instance, Prop, NativeInt(TextToOrd(Info, Text)));
    tkInt64:
      SetInt64Prop(Instance, Prop, TextToOrd(Info, Text));
    tkFloat:
      SetFloatProp(Instance, Prop, TextToFloat(Info, Text));
    tkUString:
      if TargetMayKeepOurMemory then
        SetStrProp(Instance, Prop, Text)
      else
        SetLiteralStrProp(Instance, Prop, Text);
    tkString, tkLString, tkWString:
      SetStrProp(Instance, Prop, Text);
  else
    raise EConvertError.CreateFmt('Values of type %s cannot be edited.', [GetTypeName(Info)]);
  end;
end;

{ TExtraProp }

function TExtraProp.AppliesTo(Obj: TObject): Boolean;
begin
  Result := IsKindOf(Obj, Cls);
end;

function TExtraProp.IsString: Boolean;
begin
  Result := Assigned(GetStr);
end;

function TExtraProp.IsEditable: Boolean;
begin
  Result := (Assigned(SetOrd) or Assigned(SetStr)) and (not KeepsString or TargetMayKeepOurMemory);
end;

function TExtraProp.ValueText(Obj: TObject): string;
begin
  if IsString then
    Result := GetStr(Obj)
  else
    Result := OrdToText(Info, GetOrd(Obj));
end;

procedure TExtraProp.SetValueText(Obj: TObject; const Text: string);
begin
  if Assigned(SetStr) and not IsEditable then
    raise EConvertError.CreateFmt('%s cannot be edited: the inspector doesn''t share the target''s ' +
      'memory manager.', [Name]);
  if not IsEditable then
    raise EConvertError.CreateFmt('%s is read-only.', [Name]);
  if IsString then
    SetStr(Obj, Text)
  else
    SetOrd(Obj, Integer(TextToOrd(Info, Text)));
end;

procedure RegisterExtraProp(const Prop: TExtraProp);
begin
  ExtraProps := ExtraProps + [Prop];
end;

function ExtraPropsOf(Obj: TObject): TArray<TExtraProp>;
var
  P: TExtraProp;
begin
  Result := nil;
  for P in ExtraProps do
    if P.AppliesTo(Obj) and (GetPropInfo(Obj, P.Name) = nil) then
      Result := Result + [P];
end;

{ Editor support }

function KindName(Info: PTypeInfo): string;
begin
  case Info^.Kind of
    tkInteger, tkInt64: Result := 'integer';
    tkChar, tkWChar: Result := 'char';
    tkEnumeration: Result := 'enum';
    tkSet: Result := 'set';
    tkFloat: Result := 'float';
    tkString, tkLString, tkWString, tkUString: Result := 'string';
    tkVariant: Result := 'variant';
    tkClass: Result := 'class';
    tkRecord, tkMRecord: Result := 'record';
    tkInterface: Result := 'interface';
  else
    Result := 'other';
  end;
end;

type
  // TOrdNames.GetValues calls back a method
  TValueCollector = class
    Values: TJSONArray;
    procedure Add(const S: string);
  end;

procedure TValueCollector.Add(const S: string);
begin
  Values.Add(S);
end;

function EnumValuesJson(Info: PTypeInfo): TJSONArray;
var
  Data: PTypeData;
  I: Integer;
begin
  Result := TJSONArray.Create;
  Data := GetTypeData(Info);
  if Data^.MinValue < 0 then // ByteBool, WordBool, LongBool
  begin
    Result.Add('False');
    Result.Add('True');
    Exit;
  end;
  for I := Data^.MinValue to Data^.MaxValue do
    Result.Add(GetEnumName(Info, I));
end;

function TypeValuesJson(Info: PTypeInfo): TJSONArray;
var
  Collector: TValueCollector;
  Names: TOrdNames;
begin
  Result := nil;
  case Info^.Kind of
    tkEnumeration:
      Result := EnumValuesJson(Info);
    tkSet:
      Result := EnumValuesJson(GetTypeData(Info)^.CompType^);
    tkInteger:
      if FindOrdNames(Info, Names) and Assigned(Names.GetValues) then
      begin
        Result := TJSONArray.Create;
        Collector := TValueCollector.Create;
        try
          Collector.Values := Result;
          Names.GetValues(Collector.Add);
        finally
          Collector.Free;
        end;
      end;
  end;
end;

end.
