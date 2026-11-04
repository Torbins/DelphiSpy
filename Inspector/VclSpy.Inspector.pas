unit VclSpy.Inspector;

{ Runs inside the target process, on the GUI thread that owns the picked
  window. The package inspector DLLs are linked with the rtl and vcl runtime
  packages only, so the VCL objects seen here are the target's own: Owner,
  Parent and RTTI can be walked directly. The no-packages inspectors link the
  VCL statically and see the target's objects as foreign ones of the same
  layout; VclSpy.Target finds them and compares their classes by name, so
  this unit uses IsKindOf instead of "is".

  Requests (VclSpyRequest) are JSON objects with "op" and "address", the
  control.address of an earlier report (or of a parent or child listed in
  one). Op "get" re-reads the control; op "set" also takes "property" and
  "value" (text, as reports show values). Both reply with a fresh report of
  the control; "set" adds "changed" with the old and new value.
  VclSpy.Properties decides what can be edited. Op "children" replies with
  just "address" and "children", the control's direct children. }

interface

uses
  Winapi.Windows;

procedure VclSpyInspect(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
procedure VclSpyRequest(Wnd: HWND; Request: PAnsiChar; ReplyWnd: HWND); stdcall;
// Exported by the no-packages inspectors only
function VclSpyProbe(Wnd: HWND): BOOL; stdcall;

implementation

uses
  Winapi.Messages, System.Types, System.SysUtils, System.Classes, System.TypInfo, System.Variants,
  System.JSON, System.Generics.Collections, System.Generics.Defaults,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  VclSpy.Protocol, VclSpy.Properties, VclSpy.Target, VclSpy.MemoryManager;

type
  TControlAccess = class(TControl);

  TSetThreadDpiAwarenessContext = function(Context: THandle): THandle; stdcall;

  // Maps between the target window's logical coordinates and the physical
  // screen coordinates VclSpy works in (they differ for DPI-unaware targets).
  TDpiMapping = record
    Logical, Physical: TRect;
    procedure Init(Wnd: HWND);
    function ToLogical(const P: TPoint): TPoint;
    function ToPhysical(const P: TPoint): TPoint;
  end;

const
  DpiAwarenessPerMonitorV2 = THandle(-4);
  MaxValueLength = 300;

procedure TDpiMapping.Init(Wnd: HWND);
var
  SetContext: TSetThreadDpiAwarenessContext;
  Old: THandle;
begin
  GetWindowRect(Wnd, Logical);
  Physical := Logical;
  @SetContext := GetProcAddress(GetModuleHandle(user32), 'SetThreadDpiAwarenessContext');
  if not Assigned(SetContext) then
    Exit;
  Old := SetContext(DpiAwarenessPerMonitorV2);
  if Old <> 0 then
    try
      GetWindowRect(Wnd, Physical);
    finally
      SetContext(Old);
    end;
end;

function TDpiMapping.ToLogical(const P: TPoint): TPoint;
begin
  if (Physical.Width = 0) or (Physical.Height = 0) then
    Exit(P);
  Result.X := Logical.Left + MulDiv(P.X - Physical.Left, Logical.Width, Physical.Width);
  Result.Y := Logical.Top + MulDiv(P.Y - Physical.Top, Logical.Height, Physical.Height);
end;

function TDpiMapping.ToPhysical(const P: TPoint): TPoint;
begin
  if (Logical.Width = 0) or (Logical.Height = 0) then
    Exit(P);
  Result.X := Physical.Left + MulDiv(P.X - Logical.Left, Physical.Width, Logical.Width);
  Result.Y := Physical.Top + MulDiv(P.Y - Logical.Top, Physical.Height, Logical.Height);
end;

{ JSON helpers }

procedure AddStr(Obj: TJSONObject; const Name, Value: string);
begin
  Obj.AddPair(Name, TJSONString.Create(Value));
end;

procedure AddInt(Obj: TJSONObject; const Name: string; Value: Int64);
begin
  Obj.AddPair(Name, TJSONNumber.Create(Value));
end;

procedure AddBool(Obj: TJSONObject; const Name: string; Value: Boolean);
begin
  Obj.AddPair(Name, TJSONBool.Create(Value));
end;

function RectJson(const R: TRect): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddInt(Result, 'left', R.Left);
  AddInt(Result, 'top', R.Top);
  AddInt(Result, 'right', R.Right);
  AddInt(Result, 'bottom', R.Bottom);
end;

function ErrorReport(const Msg: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    AddBool(Obj, 'ok', False);
    AddStr(Obj, 'error', Msg);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

{ Naming }

function ModulePath(Module: HMODULE): string;
begin
  if Module = 0 then
    Result := ''
  else
    Result := GetModuleName(Module);
end;

function ClassModuleName(Cls: TClass): string;
begin
  Result := ExtractFileName(ModulePath(ModuleOf(Cls)));
end;

function DisplayName(C: TComponent): string;
begin
  if C.Name <> '' then
    Result := C.Name
  else
    Result := '<' + C.ClassName + '>';
end;

// Owner chain as written in code: Form.Frame.Component
function ComponentPath(C: TComponent): string;
begin
  Result := DisplayName(C);
  C := C.Owner;
  while (C <> nil) and not IsKindOf(C, TApplication) do
  begin
    Result := DisplayName(C) + '.' + Result;
    C := C.Owner;
  end;
end;

// Visual nesting: Form.Panel.Frame.Panel.Control
function ParentPath(C: TControl): string;
begin
  Result := DisplayName(C);
  while C.Parent <> nil do
  begin
    C := C.Parent;
    Result := DisplayName(C) + '.' + Result;
  end;
end;

function ComponentKind(C: TComponent): string;
begin
  if IsKindOf(C, TCustomForm) then
    Result := 'form'
  else if IsKindOf(C, TCustomFrame) then
    Result := 'frame'
  else if IsKindOf(C, TDataModule) then
    Result := 'dataModule'
  else if IsKindOf(C, TControl) then
    Result := 'control'
  else
    Result := 'component';
end;

function Shorten(const S: string): string;
begin
  if Length(S) > MaxValueLength then
    Result := Copy(S, 1, MaxValueLength) + '...'
  else
    Result := S;
end;

{ Property values }

function ObjectSummary(Obj: TObject): string;
begin
  if Obj = nil then
    Result := '(nil)'
  else if IsKindOf(Obj, TComponent) then
    Result := ComponentPath(TComponent(Obj)) + ': ' + Obj.ClassName
  else if IsKindOf(Obj, TCollection) then
    Result := Format('(%s, Count = %d)', [Obj.ClassName, TCollection(Obj).Count])
  else if IsKindOf(Obj, TStrings) then
    Result := Format('(%s, Count = %d) %s', [Obj.ClassName, TStrings(Obj).Count,
      Shorten(TStrings(Obj).CommaText)])
  else if IsKindOf(Obj, TFont) then
    Result := Format('(%s) %s, %d pt, %s', [Obj.ClassName, TFont(Obj).Name, TFont(Obj).Size,
      ColorToString(TFont(Obj).Color)])
  else
    Result := '(' + Obj.ClassName + ')';
end;

// The full value; PropJson shortens it for the report
function PropValueText(Instance: TObject; Prop: PPropInfo): string;
var
  Info: PTypeInfo;
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
      Result := ObjectSummary(GetObjectProp(Instance, Prop));
    tkInterface:
      if GetInterfaceProp(Instance, Prop) <> nil then
        Result := '(interface)'
      else
        Result := '(nil)';
  else
    Result := '';
  end;
end;

// Full value of a published or extra property
function PropertyText(Ctrl: TControl; const Name: string): string;
var
  Prop: PPropInfo;
  Extra: TExtraProp;
begin
  Prop := GetPropInfo(Ctrl, Name);
  if (Prop <> nil) and (Prop^.GetProc <> nil) then
    Result := PropValueText(Ctrl, Prop)
  else if FindExtraProp(Ctrl, Name, Extra) then
    Result := Extra.ValueText(Ctrl)
  else
    raise EConvertError.CreateFmt('%s has no property %s.', [Ctrl.ClassName, Name]);
end;

{ Event handlers }

function HandlerJson(const EventName: string; const Method: TMethod): TJSONObject;
var
  Obj: TObject;
  Declaring: TClass;
  Name: string;
begin
  Result := TJSONObject.Create;
  AddStr(Result, 'name', EventName);
  try
    if Method.Data = nil then
      AddStr(Result, 'handler', '(code without an object)')
    else
    begin
      Obj := TObject(Method.Data);
      Name := Obj.MethodName(Method.Code);
      if Name = '' then
      begin
        AddStr(Result, 'handler', Obj.ClassName + '.? (not a published method)');
        AddStr(Result, 'unitName', Obj.UnitName);
      end
      else
      begin
        // The class that introduces the handler, e.g. a base form of an inherited form
        Declaring := Obj.ClassType;
        while (Declaring.ClassParent <> nil) and (Declaring.ClassParent.MethodAddress(Name) = Method.Code) do
          Declaring := Declaring.ClassParent;
        AddStr(Result, 'handler', Declaring.ClassName + '.' + Name);
        AddStr(Result, 'unitName', Declaring.UnitName);
      end;
      if IsKindOf(Obj, TComponent) then
        AddStr(Result, 'instance', ComponentPath(TComponent(Obj)) + ': ' + Obj.ClassName)
      else
        AddStr(Result, 'instance', Obj.ClassName);
    end;
  except
    AddStr(Result, 'handler', '<error: ' + ExceptionMessage + '>');
  end;
  AddStr(Result, 'address', Format('$%p', [Method.Code]));
  AddStr(Result, 'module', ExtractFileName(ModulePath(ModuleOf(Method.Code))));
end;

{ Sections }

function PropJson(const Name: string; Info: PTypeInfo; const Value, Scope: string;
  Editable: Boolean; Types: TJSONObject): TJSONObject;
var
  Values: TJSONArray;
  TypeName: string;
begin
  TypeName := GetTypeName(Info);
  Result := TJSONObject.Create;
  AddStr(Result, 'name', Name);
  AddStr(Result, 'type', TypeName);
  AddStr(Result, 'kind', KindName(Info));
  AddStr(Result, 'value', Shorten(Value));
  if Length(Value) > MaxValueLength then
    AddBool(Result, 'truncated', True);
  AddStr(Result, 'scope', Scope);
  AddBool(Result, 'editable', Editable);
  // Names for VclSpy's editor, once per type
  if Editable and (Types.GetValue(TypeName) = nil) then
  begin
    Values := TypeValuesJson(Info);
    if Values <> nil then
      Types.AddPair(TypeName, Values);
  end;
end;

// Published properties, and the TControl/TWinControl properties the class
// doesn't publish, sorted by name. "types" lists the names that editable
// enumeration, set, color and cursor types accept.
procedure AddProperties(Target: TJSONObject; Ctrl: TControl);
var
  Count, I: Integer;
  List: PPropList;
  Prop: PPropInfo;
  Props, Events: TJSONArray;
  Types: TJSONObject;
  Items: TList<TJSONObject>;
  Item: TJSONObject;
  Extra: TExtraProp;
  Method: TMethod;
  Value: string;
begin
  Props := TJSONArray.Create;
  Target.AddPair('properties', Props);
  Events := TJSONArray.Create;
  Target.AddPair('events', Events);
  Types := TJSONObject.Create;
  Target.AddPair('types', Types);

  Items := TList<TJSONObject>.Create;
  try
    Count := GetPropList(PTypeInfo(Ctrl.ClassInfo), tkAny, nil);
    GetMem(List, Count * SizeOf(PPropInfo));
    try
      GetPropList(PTypeInfo(Ctrl.ClassInfo), tkAny, List, True);
      for I := 0 to Count - 1 do
      begin
        Prop := List^[I];
        if Prop^.GetProc = nil then
          Continue; // write-only
        if Prop^.PropType^.Kind = tkMethod then
        begin
          Method := GetMethodProp(Ctrl, Prop);
          if Method.Code <> nil then
            Events.AddElement(HandlerJson(GetPropName(Prop), Method));
          Continue;
        end;
        try
          Value := PropValueText(Ctrl, Prop);
        except
          Value := '<error: ' + ExceptionMessage + '>';
        end;
        Items.Add(PropJson(GetPropName(Prop), Prop^.PropType^, Value, 'published',
          IsEditablePublished(Prop), Types));
      end;
    finally
      FreeMem(List);
    end;

    for Extra in ExtraPropsOf(Ctrl) do
    begin
      try
        Value := Extra.ValueText(Ctrl);
      except
        Value := '<error: ' + ExceptionMessage + '>';
      end;
      Items.Add(PropJson(Extra.Name, Extra.Info, Value, Extra.Scope, Extra.IsEditable, Types));
    end;

    Items.Sort(TComparer<TJSONObject>.Construct(
      function(const L, R: TJSONObject): Integer
      begin
        Result := CompareText(L.GetValue<string>('name'), R.GetValue<string>('name'));
      end));
    for Item in Items do
      Props.AddElement(Item);
  finally
    Items.Free;
  end;
end;

function ClassHierarchyJson(Cls: TClass): TJSONArray;
var
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  while Cls <> nil do
  begin
    Item := TJSONObject.Create;
    AddStr(Item, 'className', Cls.ClassName);
    AddStr(Item, 'unitName', Cls.UnitName);
    AddStr(Item, 'module', ClassModuleName(Cls));
    Result.AddElement(Item);
    Cls := Cls.ClassParent;
  end;
end;

function OwnersJson(C: TComponent): TJSONArray;
var
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  C := C.Owner;
  while C <> nil do
  begin
    Item := TJSONObject.Create;
    AddStr(Item, 'name', C.Name);
    AddStr(Item, 'className', C.ClassName);
    AddStr(Item, 'unitName', C.UnitName);
    AddStr(Item, 'kind', ComponentKind(C));
    Result.AddElement(Item);
    C := C.Owner;
  end;
end;

function AddressText(C: TControl): string;
begin
  Result := Format('$%p', [Pointer(C)]);
end;

function ChildCount(C: TControl): Integer;
begin
  if IsKindOf(C, TWinControl) then
    Result := TWinControl(C).ControlCount
  else
    Result := 0;
end;

// Direct children, for VclSpy to browse the parent tree; their addresses
// work in requests
function ChildrenJson(C: TControl): TJSONArray;
var
  Child: TControl;
  Item: TJSONObject;
  I: Integer;
begin
  Result := TJSONArray.Create;
  for I := 0 to ChildCount(C) - 1 do
  begin
    Child := TWinControl(C).Controls[I];
    Item := TJSONObject.Create;
    AddStr(Item, 'name', Child.Name);
    AddStr(Item, 'className', Child.ClassName);
    AddStr(Item, 'address', AddressText(Child));
    AddBool(Item, 'visible', Child.Visible);
    AddBool(Item, 'enabled', Child.Enabled);
    AddInt(Item, 'childCount', ChildCount(Child));
    Result.AddElement(Item);
  end;
end;

function ParentsJson(C: TControl): TJSONArray;
var
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  C := C.Parent;
  while C <> nil do
  begin
    Item := TJSONObject.Create;
    AddStr(Item, 'name', C.Name);
    AddStr(Item, 'className', C.ClassName);
    AddStr(Item, 'kind', ComponentKind(C));
    AddStr(Item, 'address', AddressText(C));
    AddBool(Item, 'visible', C.Visible);
    AddBool(Item, 'enabled', C.Enabled);
    if TWinControl(C).HandleAllocated then
      AddInt(Item, 'hwnd', TWinControl(C).Handle);
    Item.AddPair('children', ChildrenJson(C));
    Result.AddElement(Item);
    C := C.Parent;
  end;
end;

function ComponentJson(C: TComponent): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddStr(Result, 'name', C.Name);
  AddStr(Result, 'className', C.ClassName);
  AddStr(Result, 'unitName', C.UnitName);
  AddStr(Result, 'path', ComponentPath(C));
end;

function ActionJson(Action: TBasicAction): TJSONObject;
var
  OnExecute: TNotifyEvent;
begin
  Result := ComponentJson(Action);
  OnExecute := Action.OnExecute;
  if Assigned(OnExecute) then
    Result.AddPair('onExecute', HandlerJson('OnExecute', TMethod(OnExecute)));
end;

function PhysicalScreenRect(Ctrl: TControl; const Mapping: TDpiMapping): TRect;
var
  R: TRect;
begin
  if IsKindOf(Ctrl, TWinControl) and TWinControl(Ctrl).HandleAllocated then
    GetWindowRect(TWinControl(Ctrl).Handle, R)
  else if Ctrl.Parent <> nil then
  begin
    R.TopLeft := Ctrl.Parent.ClientToScreen(Ctrl.BoundsRect.TopLeft);
    R.BottomRight := Ctrl.Parent.ClientToScreen(Ctrl.BoundsRect.BottomRight);
  end
  else
    Exit(Rect(0, 0, 0, 0));
  Result.TopLeft := Mapping.ToPhysical(R.TopLeft);
  Result.BottomRight := Mapping.ToPhysical(R.BottomRight);
end;

function ControlJson(Ctrl: TControl; const Mapping: TDpiMapping): TJSONObject;
var
  Form: TCustomForm;
  FormObj, Bounds: TJSONObject;
  Action: TBasicAction;
begin
  Result := TJSONObject.Create;
  AddStr(Result, 'name', Ctrl.Name);
  AddStr(Result, 'className', Ctrl.ClassName);
  AddStr(Result, 'unitName', Ctrl.UnitName);
  AddStr(Result, 'module', ModulePath(ModuleOf(Ctrl.ClassType)));
  // Identifies the control in requests
  AddStr(Result, 'address', AddressText(Ctrl));
  AddStr(Result, 'path', ComponentPath(Ctrl));
  AddStr(Result, 'parentPath', ParentPath(Ctrl));
  AddStr(Result, 'text', Shorten(TControlAccess(Ctrl).Text));
  AddStr(Result, 'hint', Shorten(Ctrl.Hint));
  AddBool(Result, 'visible', Ctrl.Visible);
  AddBool(Result, 'enabled', Ctrl.Enabled);
  AddInt(Result, 'tag', Ctrl.Tag);
  AddBool(Result, 'isWinControl', IsKindOf(Ctrl, TWinControl));
  if IsKindOf(Ctrl, TWinControl) and TWinControl(Ctrl).HandleAllocated then
    AddInt(Result, 'hwnd', TWinControl(Ctrl).Handle);

  Bounds := TJSONObject.Create;
  AddInt(Bounds, 'left', Ctrl.Left);
  AddInt(Bounds, 'top', Ctrl.Top);
  AddInt(Bounds, 'width', Ctrl.Width);
  AddInt(Bounds, 'height', Ctrl.Height);
  Result.AddPair('bounds', Bounds);
  Result.AddPair('screenRect', RectJson(PhysicalScreenRect(Ctrl, Mapping)));

  Form := TopParentForm(Ctrl);
  if Form <> nil then
  begin
    FormObj := ComponentJson(Form);
    AddStr(FormObj, 'caption', Form.Caption);
    AddStr(FormObj, 'module', ClassModuleName(Form.ClassType));
    Result.AddPair('form', FormObj);
  end;

  Action := TControlAccess(Ctrl).Action;
  if Action <> nil then
    Result.AddPair('action', ActionJson(Action));

  Result.AddPair('owners', OwnersJson(Ctrl));
  Result.AddPair('parents', ParentsJson(Ctrl));
  Result.AddPair('children', ChildrenJson(Ctrl));
  Result.AddPair('classHierarchy', ClassHierarchyJson(Ctrl.ClassType));
  AddProperties(Result, Ctrl);
end;

function WindowJson(Wnd: HWND): TJSONObject;
var
  Buffer: array[0..255] of Char;
  ClassName: string;
begin
  Result := TJSONObject.Create;
  AddInt(Result, 'hwnd', Wnd);
  SetString(ClassName, Buffer, GetClassName(Wnd, Buffer, Length(Buffer)));
  AddStr(Result, 'className', ClassName);
  AddStr(Result, 'style', Format('$%.8x', [GetWindowLong(Wnd, GWL_STYLE)]));
  AddStr(Result, 'exStyle', Format('$%.8x', [GetWindowLong(Wnd, GWL_EXSTYLE)]));
end;

// Wnd is reported as "window": a window on the thread that owns Ctrl, for
// VclSpy to send requests to
function NewReport(Ctrl: TControl; Wnd: HWND): TJSONObject;
var
  Mapping: TDpiMapping;
  Process: TJSONObject;
begin
  Mapping.Init(GetAncestor(Wnd, GA_ROOT));
  Result := TJSONObject.Create;
  try
    AddBool(Result, 'ok', True);
    if OwnVcl then
      AddStr(Result, 'inspector', Format('%s (Delphi %.1f, %s, no packages, memory manager: %s)',
        [ExtractFileName(ModulePath(HInstance)), CompilerVersion, {$IFDEF WIN64}'Win64'{$ELSE}'Win32'{$ENDIF},
        MemoryManagerText]))
    else
      AddStr(Result, 'inspector', Format('%s (Delphi %.1f, %s)', [ExtractFileName(ModulePath(HInstance)),
        CompilerVersion, {$IFDEF WIN64}'Win64'{$ELSE}'Win32'{$ENDIF}]));
    Process := TJSONObject.Create;
    AddInt(Process, 'pid', GetCurrentProcessId);
    AddStr(Process, 'exe', ParamStr(0));
    if OwnVcl then
    begin
      // The module that links the target's VCL: the exe, or a DLL with its own VCL
      AddStr(Process, 'vclModule', ClassModuleName(TargetClass(Ctrl, TControl)));
      AddStr(Process, 'memoryManager', MemoryManagerText);
    end
    else
      AddStr(Process, 'vclPackage', ClassModuleName(TControl));
    Result.AddPair('process', Process);
    Result.AddPair('window', WindowJson(Wnd));
    Result.AddPair('control', ControlJson(Ctrl, Mapping));
  except
    Result.Free;
    raise;
  end;
end;

function BuildReport(Wnd: HWND; const ScreenPt: TPoint): string;
var
  Mapping: TDpiMapping;
  LogicalPt: TPoint;
  Found: TWinControl;
  Ctrl, Child: TControl;
  Report: TJSONObject;
begin
  Mapping.Init(GetAncestor(Wnd, GA_ROOT));
  LogicalPt := Mapping.ToLogical(ScreenPt);

  // Child windows that aren't VCL controls (combo box edits, in-place editors)
  // belong to the nearest VCL parent
  Found := WindowControl(Wnd);
  if Found = nil then
    if OwnVcl then
      Exit(ErrorReport(Format('Window $%x is not a VCL control.', [NativeUInt(Wnd)])))
    else
      Exit(ErrorReport(Format('Window $%x is not a VCL control of the shared VCL (%s). It may be a ' +
        'non-VCL window, or belong to a module linked without runtime packages.',
        [NativeUInt(Wnd), ClassModuleName(TControl)])));
  if not CheckTarget(Found, Result) then
    Exit(ErrorReport(Result));

  // Graphic controls (TLabel, TSpeedButton, TImage...) have no window of their own
  Ctrl := Found;
  Child := Found.ControlAtPos(Found.ScreenToClient(LogicalPt), True, True, True);
  if Child <> nil then
    Ctrl := Child;

  Report := NewReport(Ctrl, Wnd);
  try
    if Ctrl <> Found then
      AddStr(Report, 'resolvedFrom', ComponentPath(Found));
    Result := Report.ToJSON;
  finally
    Report.Free;
  end;
end;

{ Requests }

// Finds the control at Address among the live controls, so that an address
// from an old report is never dereferenced. Searches the window tree of Root
// (the control of the window the request was sent to) first, then every form.
function FindLiveControl(Address: Pointer; Root: TControl): TControl;

  function Search(Root: TControl): TControl;
  var
    I: Integer;
  begin
    if Pointer(Root) = Address then
      Exit(Root);
    if IsKindOf(Root, TWinControl) then
      for I := 0 to TWinControl(Root).ControlCount - 1 do
      begin
        Result := Search(TWinControl(Root).Controls[I]);
        if Result <> nil then
          Exit;
      end;
    Result := nil;
  end;

var
  Form: TWinControl;
begin
  if Root <> nil then
  begin
    while Root.Parent <> nil do
      Root := Root.Parent;
    Result := Search(Root);
    if Result <> nil then
      Exit;
  end;
  for Form in TargetForms do
  begin
    Result := Search(Form);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

// The control's own window, or its nearest windowed parent's. Setting some
// properties recreates windows, so the window the request came to may be gone.
function ControlWindow(Ctrl: TControl; Fallback: HWND): HWND;
begin
  while Ctrl <> nil do
  begin
    if IsKindOf(Ctrl, TWinControl) and TWinControl(Ctrl).HandleAllocated then
      Exit(TWinControl(Ctrl).Handle);
    Ctrl := Ctrl.Parent;
  end;
  Result := Fallback;
end;

function HandleRequest(Wnd: HWND; const RequestJson: string): string;
var
  Value: TJSONValue;
  Request, Report, Changed: TJSONObject;
  Op, Name, Text, OldText: string;
  Address: UInt64;
  Root: TWinControl;
  Ctrl: TControl;
begin
  Root := WindowControl(Wnd);
  if (Root <> nil) and not CheckTarget(Root, Result) then
    Exit(ErrorReport(Result));

  Value := TJSONObject.ParseJSONValue(RequestJson);
  Changed := nil;
  try
    if not (Value is TJSONObject) then
      Exit(ErrorReport('The request is not a JSON object.'));
    Request := TJSONObject(Value);
    Op := Request.GetValue<string>('op', '');
    if not SameText(Op, 'get') and not SameText(Op, 'set') and not SameText(Op, 'children') then
      Exit(ErrorReport(Format('Unknown request op "%s"; use "get", "set" or "children".', [Op])));
    if not TryStrToUInt64(Request.GetValue<string>('address', ''), Address) then
      Exit(ErrorReport('The request needs "address", the control.address of a report.'));

    Ctrl := FindLiveControl(Pointer(NativeUInt(Address)), Root);
    if Ctrl = nil then
      Exit(ErrorReport('The control no longer exists (it may have been destroyed). Pick it again.'));

    if SameText(Op, 'children') then
    begin
      Report := TJSONObject.Create;
      try
        AddBool(Report, 'ok', True);
        AddStr(Report, 'address', AddressText(Ctrl));
        Report.AddPair('children', ChildrenJson(Ctrl));
        Result := Report.ToJSON;
      finally
        Report.Free;
      end;
      Exit;
    end;

    if SameText(Op, 'set') then
    begin
      Name := Request.GetValue<string>('property', '');
      if not Request.TryGetValue<string>('value', Text) then
        Exit(ErrorReport('The request needs "value".'));
      try
        OldText := PropertyText(Ctrl, Name);
        SetPropertyText(Ctrl, Name, Text);
      except
        // Also exceptions of the target's setter, which aren't the inspector's Exception
        Exit(ErrorReport(Format('Cannot set %s: %s', [Name, ExceptionMessage])));
      end;
      Changed := TJSONObject.Create;
      AddStr(Changed, 'property', Name);
      AddStr(Changed, 'oldValue', Shorten(OldText));
      AddStr(Changed, 'newValue', Shorten(PropertyText(Ctrl, Name)));
    end;

    Report := NewReport(Ctrl, ControlWindow(Ctrl, Wnd));
    try
      if Changed <> nil then
      begin
        Report.AddPair('changed', Changed);
        Changed := nil;
      end;
      Result := Report.ToJSON;
    finally
      Report.Free;
    end;
  finally
    Changed.Free;
    Value.Free;
  end;
end;

procedure SendReply(ReplyWnd: HWND; const Json: string);
var
  Bytes: TBytes;
  Data: TCopyDataStruct;
  Res: DWORD_PTR;
begin
  Bytes := TEncoding.UTF8.GetBytes(Json);
  Data.dwData := VclSpyCopyDataMagic;
  Data.cbData := Length(Bytes);
  Data.lpData := Pointer(Bytes);
  SendMessageTimeout(ReplyWnd, WM_COPYDATA, 0, LPARAM(@Data), SMTO_ABORTIFHUNG,
    VclSpyReplyTimeout, @Res);
end;

procedure VclSpyInspect(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
var
  Json: string;
begin
  try
    Json := BuildReport(Wnd, Point(X, Y));
  except
    Json := ErrorReport(ExceptionText);
  end;
  SendReply(ReplyWnd, Json);
end;

procedure VclSpyRequest(Wnd: HWND; Request: PAnsiChar; ReplyWnd: HWND); stdcall;
var
  Json, Text: string;
begin
  try
    Text := UTF8ToString(Request);
    if (Text <> '') and (Text[1] = #$FEFF) then
      Delete(Text, 1, 1); // BOM of a request file
    Json := HandleRequest(Wnd, Text);
  except
    Json := ErrorReport(ExceptionText);
  end;
  SendReply(ReplyWnd, Json);
end;

function VclSpyProbe(Wnd: HWND): BOOL; stdcall;
var
  Ctrl: TWinControl;
  Error: string;
begin
  try
    Ctrl := WindowControl(Wnd);
    Result := (Ctrl <> nil) and CheckTarget(Ctrl, Error);
  except
    Result := False;
  end;
end;

end.
