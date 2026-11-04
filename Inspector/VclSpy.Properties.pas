unit VclSpy.Properties;

{ Converts property values between their text form, as VclSpy shows and
  edits them, and the target's own values. Runs inside the target, like
  VclSpy.Inspector.

  Editable are published properties of simple types (numbers, characters,
  strings, enumerations, sets of up to 32 elements) and the TControl and
  TWinControl properties in ExtraProps. Those are declared public or
  protected, so RTTI doesn't list them unless a class republishes them;
  access classes reach them instead. VclSpy.Members reaches the properties of
  objects and the fields of records that properties return.

  A no-packages inspector that doesn't share the target's memory manager
  (VclSpy.Target.TargetMayKeepOurMemory) must not let the target keep a
  string it allocated: the target would free it with its own memory manager.
  String setters of the target get a copy that looks like a string literal,
  which they copy when they assign it. Strings that the inspector's code
  would store itself (field setters, StyleName, ImeName, AnsiString
  properties) are read-only then. }

interface

uses
  System.SysUtils, System.TypInfo, System.JSON, Vcl.Controls;

type
  // A property that TControl or TWinControl declares public or protected.
  // Ordinal values (Boolean, enumerations, small sets, integers) go through
  // GetOrd/SetOrd, strings through GetStr/SetStr. No setter means read-only.
  // KeepsString: SetStr stores the string in the control (in VCL code of the
  // inspector), instead of handing the control's window a copy.
  TExtraProp = record
    Name, Scope: string;
    Info: PTypeInfo;
    WinControlOnly, KeepsString: Boolean;
    GetOrd: TFunc<TControl, Integer>;
    SetOrd: TProc<TControl, Integer>;
    GetStr: TFunc<TControl, string>;
    SetStr: TProc<TControl, string>;
    function AppliesTo(Ctrl: TControl): Boolean;
    function IsString: Boolean;
    function IsEditable: Boolean;
    function ValueText(Ctrl: TControl): string;
    procedure SetValueText(Ctrl: TControl; const Text: string);
  end;

function OrdToText(Info: PTypeInfo; Value: Int64): string;
function IsDateTimeType(Info: PTypeInfo): Boolean;
// The element type of a set, or nil if it has no type information
function SetElementType(Info: PTypeInfo): PTypeInfo;
// Parse text for a type; raise EConvertError with a message for the user
// when the text doesn't fit it
function TextToOrd(Info: PTypeInfo; const Text: string): Int64;
function TextToFloat(Info: PTypeInfo; const Text: string): Extended;
// Types whose values VclSpy edits as text
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

// ExtraProps that Ctrl has and that its class doesn't publish
function ExtraPropsOf(Ctrl: TControl): TArray<TExtraProp>;

// "integer", "enum", "set", "string"... for VclSpy's editor
function KindName(Info: PTypeInfo): string;
// Names VclSpy offers in its editor: enumeration values, set elements, color
// and cursor names. nil for types without names.
function TypeValuesJson(Info: PTypeInfo): TJSONArray;

implementation

uses
  System.Classes, System.UITypes, System.Variants, Vcl.Graphics, Vcl.Forms, Vcl.Menus, VclSpy.Target;

type
  TControlAccess = class(TControl);
  TWinControlAccess = class(TWinControl);

const
  // Offset of StrRec.refCnt from the first character, on Win32 and Win64
  StrRefCountOffset = -8;

var
  ExtraProps: TArray<TExtraProp>;

{ Text form }

function IsType(Info: PTypeInfo; const Name: string): Boolean;
begin
  Result := SameText(GetTypeName(Info), Name);
end;

function IsDateTimeType(Info: PTypeInfo): Boolean;
begin
  Result := IsType(Info, 'TDateTime') or IsType(Info, 'TDate') or IsType(Info, 'TTime');
end;

function OrdToText(Info: PTypeInfo; Value: Int64): string;
begin
  case Info^.Kind of
    tkInteger:
      if IsType(Info, 'TColor') then
        Result := ColorToString(TColor(Value))
      else if IsType(Info, 'TCursor') then
        Result := CursorToString(TCursor(Value))
      else if IsType(Info, 'TShortCut') then
        Result := ShortCutToText(TShortCut(Value))
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
begin
  S := Trim(Text);
  case Info^.Kind of
    tkInteger, tkInt64:
      begin
        if IsType(Info, 'TColor') then
        begin
          if not IdentToColor(S, Ident) and not TryStrToInt(S, Ident) then
            raise EConvertError.CreateFmt('"%s" is not a color. Use a name such as clRed or ' +
              'clBtnFace, or a number such as $00FF8000 ($00BBGGRR).', [Text]);
          Result := Ident;
        end
        else if IsType(Info, 'TCursor') then
        begin
          if not IdentToCursor(S, Ident) and not TryStrToInt(S, Ident) then
            raise EConvertError.CreateFmt('"%s" is not a cursor. Use a name such as crHandPoint, ' +
              'or a number.', [Text]);
          Result := Ident;
        end
        else if IsType(Info, 'TShortCut') then
        begin
          Result := TextToShortCut(S);
          if (Result = 0) and (S <> '') and not TryStrToInt64(S, Result) then
            raise EConvertError.CreateFmt('"%s" is not a shortcut. Use text such as Ctrl+S, ' +
              'or nothing for none.', [Text]);
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
// paths VclSpy shows. Other properties named so (Font.Name) are editable.
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
    raise EConvertError.CreateFmt('%s (%s) cannot be edited in VclSpy.', [GetPropName(Prop), GetTypeName(Info)]);
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

function TExtraProp.AppliesTo(Ctrl: TControl): Boolean;
begin
  Result := not WinControlOnly or IsKindOf(Ctrl, TWinControl);
end;

function TExtraProp.IsString: Boolean;
begin
  Result := Assigned(GetStr);
end;

function TExtraProp.IsEditable: Boolean;
begin
  Result := (Assigned(SetOrd) or Assigned(SetStr)) and (not KeepsString or TargetMayKeepOurMemory);
end;

function TExtraProp.ValueText(Ctrl: TControl): string;
begin
  if IsString then
    Result := GetStr(Ctrl)
  else
    Result := OrdToText(Info, GetOrd(Ctrl));
end;

procedure TExtraProp.SetValueText(Ctrl: TControl; const Text: string);
begin
  if Assigned(SetStr) and not IsEditable then
    raise EConvertError.CreateFmt('%s cannot be edited: the inspector doesn''t share the target''s ' +
      'memory manager.', [Name]);
  if not IsEditable then
    raise EConvertError.CreateFmt('%s is read-only.', [Name]);
  if IsString then
    SetStr(Ctrl, Text)
  else
    SetOrd(Ctrl, Integer(TextToOrd(Info, Text)));
end;

function ExtraPropsOf(Ctrl: TControl): TArray<TExtraProp>;
var
  P: TExtraProp;
begin
  Result := nil;
  for P in ExtraProps do
    if P.AppliesTo(Ctrl) and (GetPropInfo(Ctrl, P.Name) = nil) then
      Result := Result + [P];
end;

{ The TControl and TWinControl properties }

procedure AddOrd(const Name, Scope: string; Info: PTypeInfo; WinControlOnly: Boolean;
  const GetOrd: TFunc<TControl, Integer>; const SetOrd: TProc<TControl, Integer>);
var
  P: TExtraProp;
begin
  P := Default(TExtraProp);
  P.Name := Name;
  P.Scope := Scope;
  P.Info := Info;
  P.WinControlOnly := WinControlOnly;
  P.GetOrd := GetOrd;
  P.SetOrd := SetOrd;
  ExtraProps := ExtraProps + [P];
end;

procedure AddStr(const Name, Scope: string; Info: PTypeInfo; WinControlOnly, KeepsString: Boolean;
  const GetStr: TFunc<TControl, string>; const SetStr: TProc<TControl, string>);
var
  P: TExtraProp;
begin
  P := Default(TExtraProp);
  P.Name := Name;
  P.Scope := Scope;
  P.Info := Info;
  P.WinControlOnly := WinControlOnly;
  P.KeepsString := KeepsString;
  P.GetStr := GetStr;
  P.SetStr := SetStr;
  ExtraProps := ExtraProps + [P];
end;

function C(Ctrl: TControl): TControlAccess; inline;
begin
  Result := TControlAccess(Ctrl);
end;

function W(Ctrl: TControl): TWinControlAccess; inline;
begin
  Result := TWinControlAccess(Ctrl);
end;

// What TControl publishes itself (Left, Top, Width, Height, Hint, Cursor...)
// comes from RTTI, like any published property.
procedure RegisterExtraProps;
const
  AnyControl = False;
  WinControl = True;
  // SetText hands the window a copy (WM_SETTEXT); the others store the string
  ByMessage = False;
  Keeps = True;
begin
  // TControl, public
  AddOrd('Visible', 'public', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.Visible) end,
    procedure(X: TControl; V: Integer) begin X.Visible := V <> 0 end);
  AddOrd('Enabled', 'public', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.Enabled) end,
    procedure(X: TControl; V: Integer) begin X.Enabled := V <> 0 end);
  AddOrd('Align', 'public', TypeInfo(TAlign), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.Align) end,
    procedure(X: TControl; V: Integer) begin X.Align := TAlign(V) end);
  AddOrd('Anchors', 'public', TypeInfo(TAnchors), AnyControl,
    function(X: TControl): Integer begin Result := Byte(X.Anchors) end,
    procedure(X: TControl; V: Integer) begin X.Anchors := TAnchors(Byte(V)) end);
  AddOrd('BiDiMode', 'public', TypeInfo(TBiDiMode), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.BiDiMode) end,
    procedure(X: TControl; V: Integer) begin X.BiDiMode := TBiDiMode(V) end);
  AddOrd('ClientWidth', 'public', TypeInfo(Integer), AnyControl,
    function(X: TControl): Integer begin Result := X.ClientWidth end,
    procedure(X: TControl; V: Integer) begin X.ClientWidth := V end);
  AddOrd('ClientHeight', 'public', TypeInfo(Integer), AnyControl,
    function(X: TControl): Integer begin Result := X.ClientHeight end,
    procedure(X: TControl; V: Integer) begin X.ClientHeight := V end);
  AddOrd('ShowHint', 'public', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.ShowHint) end,
    procedure(X: TControl; V: Integer) begin X.ShowHint := V <> 0 end);
  AddOrd('StyleElements', 'public', TypeInfo(TStyleElements), AnyControl,
    function(X: TControl): Integer begin Result := Byte(X.StyleElements) end,
    procedure(X: TControl; V: Integer) begin X.StyleElements := TStyleElements(Byte(V)) end);
  AddStr('StyleName', 'public', TypeInfo(string), AnyControl, Keeps,
    function(X: TControl): string begin Result := X.StyleName end,
    procedure(X: TControl; V: string) begin X.StyleName := V end);

  // TControl, protected
  AddStr('Caption', 'protected', TypeInfo(TCaption), AnyControl, ByMessage,
    function(X: TControl): string begin Result := C(X).Caption end,
    procedure(X: TControl; V: string) begin C(X).Caption := V end);
  AddStr('Text', 'protected', TypeInfo(TCaption), AnyControl, ByMessage,
    function(X: TControl): string begin Result := C(X).Text end,
    procedure(X: TControl; V: string) begin C(X).Text := V end);
  AddOrd('Color', 'protected', TypeInfo(TColor), AnyControl,
    function(X: TControl): Integer begin Result := C(X).Color end,
    procedure(X: TControl; V: Integer) begin C(X).Color := V end);
  AddOrd('ParentColor', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).ParentColor) end,
    procedure(X: TControl; V: Integer) begin C(X).ParentColor := V <> 0 end);
  AddOrd('ParentFont', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).ParentFont) end,
    procedure(X: TControl; V: Integer) begin C(X).ParentFont := V <> 0 end);
  AddOrd('ParentShowHint', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).ParentShowHint) end,
    procedure(X: TControl; V: Integer) begin C(X).ParentShowHint := V <> 0 end);
  AddOrd('ParentBiDiMode', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).ParentBiDiMode) end,
    procedure(X: TControl; V: Integer) begin C(X).ParentBiDiMode := V <> 0 end);
  AddOrd('AutoSize', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).AutoSize) end,
    procedure(X: TControl; V: Integer) begin C(X).AutoSize := V <> 0 end);
  AddOrd('DragMode', 'protected', TypeInfo(TDragMode), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).DragMode) end,
    procedure(X: TControl; V: Integer) begin C(X).DragMode := TDragMode(V) end);
  AddOrd('DragKind', 'protected', TypeInfo(TDragKind), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).DragKind) end,
    procedure(X: TControl; V: Integer) begin C(X).DragKind := TDragKind(V) end);
  AddOrd('DragCursor', 'protected', TypeInfo(TCursor), AnyControl,
    function(X: TControl): Integer begin Result := C(X).DragCursor end,
    procedure(X: TControl; V: Integer) begin C(X).DragCursor := V end);

  // TWinControl, public
  AddOrd('TabOrder', 'public', TypeInfo(TTabOrder), WinControl,
    function(X: TControl): Integer begin Result := W(X).TabOrder end,
    procedure(X: TControl; V: Integer) begin W(X).TabOrder := V end);
  AddOrd('TabStop', 'public', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).TabStop) end,
    procedure(X: TControl; V: Integer) begin W(X).TabStop := V <> 0 end);
  AddOrd('DoubleBuffered', 'public', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).DoubleBuffered) end,
    procedure(X: TControl; V: Integer) begin W(X).DoubleBuffered := V <> 0 end);
  AddOrd('ParentDoubleBuffered', 'public', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).ParentDoubleBuffered) end,
    procedure(X: TControl; V: Integer) begin W(X).ParentDoubleBuffered := V <> 0 end);
  AddOrd('Showing', 'public', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).Showing) end,
    nil);

  // TWinControl, protected
  AddOrd('BevelEdges', 'protected', TypeInfo(TBevelEdges), WinControl,
    function(X: TControl): Integer begin Result := Byte(W(X).BevelEdges) end,
    procedure(X: TControl; V: Integer) begin W(X).BevelEdges := TBevelEdges(Byte(V)) end);
  AddOrd('BevelInner', 'protected', TypeInfo(TBevelCut), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).BevelInner) end,
    procedure(X: TControl; V: Integer) begin W(X).BevelInner := TBevelCut(V) end);
  AddOrd('BevelOuter', 'protected', TypeInfo(TBevelCut), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).BevelOuter) end,
    procedure(X: TControl; V: Integer) begin W(X).BevelOuter := TBevelCut(V) end);
  AddOrd('BevelKind', 'protected', TypeInfo(TBevelKind), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).BevelKind) end,
    procedure(X: TControl; V: Integer) begin W(X).BevelKind := TBevelKind(V) end);
  AddOrd('BevelWidth', 'protected', TypeInfo(TBevelWidth), WinControl,
    function(X: TControl): Integer begin Result := W(X).BevelWidth end,
    procedure(X: TControl; V: Integer) begin W(X).BevelWidth := V end);
  AddOrd('BorderWidth', 'protected', TypeInfo(TBorderWidth), WinControl,
    function(X: TControl): Integer begin Result := W(X).BorderWidth end,
    procedure(X: TControl; V: Integer) begin W(X).BorderWidth := V end);
  AddOrd('Ctl3D', 'protected', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).Ctl3D) end,
    procedure(X: TControl; V: Integer) begin W(X).Ctl3D := V <> 0 end);
  AddOrd('ParentCtl3D', 'protected', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).ParentCtl3D) end,
    procedure(X: TControl; V: Integer) begin W(X).ParentCtl3D := V <> 0 end);
  AddOrd('ParentBackground', 'protected', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).ParentBackground) end,
    procedure(X: TControl; V: Integer) begin W(X).ParentBackground := V <> 0 end);
  AddOrd('ImeMode', 'protected', TypeInfo(TImeMode), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).ImeMode) end,
    procedure(X: TControl; V: Integer) begin W(X).ImeMode := TImeMode(V) end);
  AddStr('ImeName', 'protected', TypeInfo(TImeName), WinControl, Keeps,
    function(X: TControl): string begin Result := W(X).ImeName end,
    procedure(X: TControl; V: string) begin W(X).ImeName := V end);
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
  // GetColorValues and GetCursorValues call back a method
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
begin
  Result := nil;
  case Info^.Kind of
    tkEnumeration:
      Result := EnumValuesJson(Info);
    tkSet:
      Result := EnumValuesJson(GetTypeData(Info)^.CompType^);
    tkInteger:
      if IsType(Info, 'TColor') or IsType(Info, 'TCursor') then
      begin
        Result := TJSONArray.Create;
        Collector := TValueCollector.Create;
        try
          Collector.Values := Result;
          if IsType(Info, 'TColor') then
            GetColorValues(Collector.Add)
          else
            GetCursorValues(Collector.Add);
        finally
          Collector.Free;
        end;
      end;
  end;
end;

initialization
  RegisterExtraProps;
end.
