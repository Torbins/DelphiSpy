unit VclSpy.Inspector;

{ Runs inside the target process, on the GUI thread that owns the picked
  window. The inspector DLLs are linked with the rtl and vcl runtime packages
  only, so the VCL objects seen here are the target's own: FindControl works,
  and Owner, Parent and RTTI can be walked directly. }

interface

uses
  Winapi.Windows;

procedure VclSpyInspect(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;

implementation

uses
  Winapi.Messages, System.SysUtils, System.Classes, System.TypInfo, System.Variants,
  System.JSON, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Menus,
  VclSpy.Protocol;

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
  Result := ExtractFileName(ModulePath(FindClassHInstance(Cls)));
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
  while (C <> nil) and not (C is TApplication) do
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
  if C is TCustomForm then
    Result := 'form'
  else if C is TCustomFrame then
    Result := 'frame'
  else if C is TDataModule then
    Result := 'dataModule'
  else if C is TControl then
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
  else if Obj is TComponent then
    Result := ComponentPath(TComponent(Obj)) + ': ' + Obj.ClassName
  else if Obj is TCollection then
    Result := Format('(%s, Count = %d)', [Obj.ClassName, TCollection(Obj).Count])
  else if Obj is TStrings then
    Result := Format('(%s, Count = %d) %s', [Obj.ClassName, TStrings(Obj).Count,
      Shorten(TStrings(Obj).CommaText)])
  else if Obj is TFont then
    Result := Format('(%s) %s, %d pt, %s', [Obj.ClassName, TFont(Obj).Name, TFont(Obj).Size,
      ColorToString(TFont(Obj).Color)])
  else
    Result := '(' + Obj.ClassName + ')';
end;

function PropValueText(Instance: TObject; Prop: PPropInfo): string;
var
  TypeName: string;
begin
  TypeName := GetTypeName(Prop^.PropType^);
  case Prop^.PropType^.Kind of
    tkInteger:
      if SameText(TypeName, 'TColor') then
        Result := ColorToString(TColor(GetOrdProp(Instance, Prop)))
      else if SameText(TypeName, 'TCursor') then
        Result := CursorToString(TCursor(GetOrdProp(Instance, Prop)))
      else if SameText(TypeName, 'TShortCut') then
        Result := ShortCutToText(TShortCut(GetOrdProp(Instance, Prop)))
      else
        Result := IntToStr(GetOrdProp(Instance, Prop));
    tkChar, tkWChar:
      Result := '#' + IntToStr(GetOrdProp(Instance, Prop));
    tkEnumeration:
      Result := GetEnumProp(Instance, Prop);
    tkSet:
      Result := GetSetProp(Instance, Prop, True);
    tkInt64:
      Result := IntToStr(GetInt64Prop(Instance, Prop));
    tkFloat:
      if SameText(TypeName, 'TDateTime') or SameText(TypeName, 'TDate') or SameText(TypeName, 'TTime') then
        Result := DateTimeToStr(GetFloatProp(Instance, Prop))
      else
        Result := FloatToStr(GetFloatProp(Instance, Prop));
    tkString, tkLString, tkWString, tkUString:
      Result := Shorten(GetStrProp(Instance, Prop));
    tkVariant:
      Result := Shorten(VarToStr(GetVariantProp(Instance, Prop)));
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
      if Obj is TComponent then
        AddStr(Result, 'instance', ComponentPath(TComponent(Obj)) + ': ' + Obj.ClassName)
      else
        AddStr(Result, 'instance', Obj.ClassName);
    end;
  except
    on E: Exception do
      AddStr(Result, 'handler', '<error: ' + E.Message + '>');
  end;
  AddStr(Result, 'address', Format('$%p', [Method.Code]));
  AddStr(Result, 'module', ExtractFileName(ModulePath(FindHInstance(Method.Code))));
end;

{ Sections }

procedure AddProperties(Target: TJSONObject; Instance: TObject);
var
  Count, I: Integer;
  List: PPropList;
  Prop: PPropInfo;
  Props, Events: TJSONArray;
  Item: TJSONObject;
  Method: TMethod;
  Value: string;
begin
  Props := TJSONArray.Create;
  Target.AddPair('properties', Props);
  Events := TJSONArray.Create;
  Target.AddPair('events', Events);

  Count := GetPropList(PTypeInfo(Instance.ClassInfo), tkAny, nil);
  GetMem(List, Count * SizeOf(PPropInfo));
  try
    GetPropList(PTypeInfo(Instance.ClassInfo), tkAny, List, True);
    for I := 0 to Count - 1 do
    begin
      Prop := List^[I];
      if Prop^.GetProc = nil then
        Continue; // write-only
      if Prop^.PropType^.Kind = tkMethod then
      begin
        Method := GetMethodProp(Instance, Prop);
        if Method.Code <> nil then
          Events.AddElement(HandlerJson(GetPropName(Prop), Method));
        Continue;
      end;
      try
        Value := PropValueText(Instance, Prop);
      except
        on E: Exception do
          Value := '<error: ' + E.Message + '>';
      end;
      Item := TJSONObject.Create;
      AddStr(Item, 'name', GetPropName(Prop));
      AddStr(Item, 'type', GetTypeName(Prop^.PropType^));
      AddStr(Item, 'value', Value);
      Props.AddElement(Item);
    end;
  finally
    FreeMem(List);
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
    AddBool(Item, 'visible', C.Visible);
    AddBool(Item, 'enabled', C.Enabled);
    if TWinControl(C).HandleAllocated then
      AddInt(Item, 'hwnd', TWinControl(C).Handle);
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
  if (Ctrl is TWinControl) and TWinControl(Ctrl).HandleAllocated then
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
  AddStr(Result, 'module', ModulePath(FindClassHInstance(Ctrl.ClassType)));
  AddStr(Result, 'path', ComponentPath(Ctrl));
  AddStr(Result, 'parentPath', ParentPath(Ctrl));
  AddStr(Result, 'text', Shorten(TControlAccess(Ctrl).Text));
  AddStr(Result, 'hint', Shorten(Ctrl.Hint));
  AddBool(Result, 'visible', Ctrl.Visible);
  AddBool(Result, 'enabled', Ctrl.Enabled);
  AddInt(Result, 'tag', Ctrl.Tag);
  AddBool(Result, 'isWinControl', Ctrl is TWinControl);
  if (Ctrl is TWinControl) and TWinControl(Ctrl).HandleAllocated then
    AddInt(Result, 'hwnd', TWinControl(Ctrl).Handle);

  Bounds := TJSONObject.Create;
  AddInt(Bounds, 'left', Ctrl.Left);
  AddInt(Bounds, 'top', Ctrl.Top);
  AddInt(Bounds, 'width', Ctrl.Width);
  AddInt(Bounds, 'height', Ctrl.Height);
  Result.AddPair('bounds', Bounds);
  Result.AddPair('screenRect', RectJson(PhysicalScreenRect(Ctrl, Mapping)));

  Form := GetParentForm(Ctrl, True);
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

function BuildReport(Wnd: HWND; const ScreenPt: TPoint): string;
var
  Mapping: TDpiMapping;
  LogicalPt: TPoint;
  W: HWND;
  Found: TWinControl;
  Ctrl, Child: TControl;
  Report, Process: TJSONObject;
begin
  // Linked statically instead of through vclNNN.bpl, this DLL would see its own VCL
  if FindClassHInstance(TControl) = HInstance then
    Exit(ErrorReport('This inspector DLL was built without the rtl;vcl runtime packages.'));

  Mapping.Init(GetAncestor(Wnd, GA_ROOT));
  LogicalPt := Mapping.ToLogical(ScreenPt);

  // Child windows that aren't VCL controls (combo box edits, in-place editors)
  // belong to the nearest VCL parent
  W := Wnd;
  Found := nil;
  while (W <> 0) and (Found = nil) do
  begin
    Found := FindControl(W);
    if Found = nil then
      W := GetParent(W);
  end;
  if Found = nil then
    Exit(ErrorReport(Format('Window $%x is not a VCL control of the shared VCL (%s). It may be a ' +
      'non-VCL window, or belong to a module linked without runtime packages.',
      [NativeUInt(Wnd), ClassModuleName(TControl)])));

  // Graphic controls (TLabel, TSpeedButton, TImage...) have no window of their own
  Ctrl := Found;
  Child := Found.ControlAtPos(Found.ScreenToClient(LogicalPt), True, True, True);
  if Child <> nil then
    Ctrl := Child;

  Report := TJSONObject.Create;
  try
    AddBool(Report, 'ok', True);
    AddStr(Report, 'inspector', Format('%s (Delphi %.1f, %s)', [ExtractFileName(ModulePath(HInstance)),
      CompilerVersion, {$IFDEF WIN64}'Win64'{$ELSE}'Win32'{$ENDIF}]));
    Process := TJSONObject.Create;
    AddInt(Process, 'pid', GetCurrentProcessId);
    AddStr(Process, 'exe', ParamStr(0));
    AddStr(Process, 'vclPackage', ClassModuleName(TControl));
    Report.AddPair('process', Process);
    Report.AddPair('window', WindowJson(Wnd));
    if Ctrl <> Found then
      AddStr(Report, 'resolvedFrom', ComponentPath(Found));
    Report.AddPair('control', ControlJson(Ctrl, Mapping));
    Result := Report.ToJSON;
  finally
    Report.Free;
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
    on E: Exception do
      Json := ErrorReport(E.ClassName + ': ' + E.Message);
  else
    Json := ErrorReport('Unknown exception while inspecting the control.');
  end;
  SendReply(ReplyWnd, Json);
end;

end.
