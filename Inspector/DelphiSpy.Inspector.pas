unit DelphiSpy.Inspector;

{ Runs inside the target process, on the GUI thread that owns the picked
  window. The package inspector DLLs are linked with the rtl and vcl runtime
  packages only, so the VCL objects seen here are the target's own: Owner,
  Parent and RTTI can be walked directly. The no-packages inspectors link the
  VCL statically and see the target's objects as foreign ones of the same
  layout; this unit finds them through their windows, and DelphiSpy.Target
  compares their classes by name, so this unit uses IsKindOf instead of "is".

  Requests (DelphiSpyRequest) are JSON objects with "op" and "address", the
  control.address of an earlier report (or of a parent or child listed in
  one). Op "get" re-reads the control; op "set" also takes "property", a
  property's path (Caption, Font.Size, BoundsRect.Left, Panels[0].Width),
  and "value" (text, as reports show values). Both reply with a fresh report
  of the control; "set" adds "changed" with the old and new value.
  DelphiSpy.Members and DelphiSpy.Properties decide what can be edited. Op "children" replies with
  just "address" and "children", the control's direct children.

  Two ops need no address: "forms" replies with "forms", the target's forms
  (parentless windowed controls), and "pick" reports the control at the
  mouse cursor, or at "x" and "y" (physical screen coordinates) if given.
  DelphiSpy uses them for targets it connects to over the network (DelphiSpy.Server),
  whose windows it can't drag the finder onto.

  DelphiSpy.Report builds what doesn't depend on the VCL; DelphiSpy.VclProperties
  registers what DelphiSpy.Properties and DelphiSpy.Members need to know about VCL
  classes. }

interface

uses
  Winapi.Windows;

procedure DelphiSpyInspect(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
procedure DelphiSpyRequest(Wnd: HWND; Request: PAnsiChar; ReplyWnd: HWND); stdcall;
// Exported by the no-packages inspectors only
function DelphiSpyProbe(Wnd: HWND): BOOL; stdcall;

// The reply of DelphiSpyRequest as JSON, for DelphiSpy.Server. Wnd may be 0: the
// control is then looked for in every form.
function RequestReply(Wnd: HWND; const Request: string): string;

implementation

uses
  Winapi.Messages, System.Types, System.SysUtils, System.Classes, System.TypInfo,
  System.JSON, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms,
  DelphiSpy.Protocol, DelphiSpy.Properties, DelphiSpy.Members, DelphiSpy.Target, DelphiSpy.MemoryManager,
  DelphiSpy.Report, DelphiSpy.VclProperties;

type
  TControlAccess = class(TControl);

{ The target's controls }

// The VCL of the no-packages inspectors (OwnRtl) is not the target's: they
// find controls through the window property that every VCL module in the
// process sets ('Delphi' + process id), and forms by enumerating the
// process' windows. CheckTarget makes sure that the target's VCL has this
// inspector's layout.

// False, with a message, when the VCL of Ctrl doesn't have this inspector's
// layout: the target was built with another Delphi version
function CheckTarget(Ctrl: TControl; out Error: string): Boolean;
const
  Classes: array[0..2] of TClass = (TComponent, TControl, TWinControl);
var
  Cls, Target: TClass;
  Size, Props: Integer;
begin
  for Cls in Classes do
  begin
    if (Cls = TWinControl) and not IsKindOf(Ctrl, TWinControl) then
      Break;
    Target := TargetClass(Ctrl, Cls);
    if Target = nil then
    begin
      Error := Format('%s is not a VCL control: it doesn''t inherit from %s.', [Ctrl.ClassName, Cls.ClassName]);
      Exit(False);
    end;
    Size := Target.InstanceSize;
    Props := GetTypeData(Target.ClassInfo)^.PropCount;
    if (Size <> Cls.InstanceSize) or (Props <> GetTypeData(Cls.ClassInfo)^.PropCount) then
    begin
      Error := Format('The target''s VCL doesn''t match the inspector''s (Delphi %.1f): its %s has %d bytes ' +
        'and %d published properties, the inspector''s %d and %d. The target may be built with another ' +
        'Delphi version.', [CompilerVersion, Cls.ClassName, Size, Props, Cls.InstanceSize,
        GetTypeData(Cls.ClassInfo)^.PropCount]);
      Exit(False);
    end;
  end;
  Result := True;
end;

// The VCL control of Wnd, or nil. Check it with CheckTarget before use.
function FindTargetControl(Wnd: HWND): TWinControl;
var
  Atom: TAtom;
  Pid: DWORD;
  P: Pointer;
begin
  if not OwnRtl then
    Exit(FindControl(Wnd));
  Result := nil;
  if (Wnd = 0) or (GetWindowThreadProcessId(Wnd, Pid) = 0) or (Pid <> GetCurrentProcessId) then
    Exit;
  // Vcl.Controls sets this property for every window it creates, in every module
  Atom := GlobalFindAtom(PChar(Format('Delphi%.8X', [GetCurrentProcessId])));
  if Atom = 0 then
    Exit;
  P := Pointer(GetProp(Wnd, MakeIntAtom(Atom)));
  if (P <> nil) and LooksLikeObject(P) and IsKindOf(TObject(P), TWinControl) then
    Result := TWinControl(P);
end;

// The VCL control of Wnd or of its nearest parent window that has one
function WindowControl(Wnd: HWND): TWinControl;
begin
  Result := nil;
  while (Wnd <> 0) and (Result = nil) do
  begin
    Result := FindTargetControl(Wnd);
    if Result = nil then
      Wnd := GetParent(Wnd);
  end;
end;

function CollectForm(Wnd: HWND; List: TList<TWinControl>): BOOL; stdcall;
var
  Ctrl: TWinControl;
  Error: string;
begin
  try
    Ctrl := FindTargetControl(Wnd);
    if (Ctrl <> nil) and CheckTarget(Ctrl, Error) and (Ctrl.Parent = nil) then
      List.Add(Ctrl);
  except
    // Not into EnumWindows
  end;
  Result := True;
end;

// The target's forms (in the no-packages inspectors, all parentless windowed
// controls) that pass CheckTarget
function TargetForms: TArray<TWinControl>;
var
  List: TList<TWinControl>;
  I: Integer;
begin
  if not OwnRtl then
  begin
    SetLength(Result, Screen.CustomFormCount);
    for I := 0 to Screen.CustomFormCount - 1 do
      Result[I] := Screen.CustomForms[I];
    Exit;
  end;
  List := TList<TWinControl>.Create;
  try
    EnumWindows(@CollectForm, LPARAM(List));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// GetParentForm(Ctrl, True)
function TopParentForm(Ctrl: TControl): TCustomForm;
begin
  while Ctrl.Parent <> nil do
    Ctrl := Ctrl.Parent;
  if IsKindOf(Ctrl, TCustomForm) then
    Result := TCustomForm(Ctrl)
  else
    Result := nil;
end;

{ Naming }

function DisplayName(C: TComponent): string;
begin
  if C.Name <> '' then
    Result := C.Name
  else
    Result := '<' + C.ClassName + '>';
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

function ChildCount(C: TControl): Integer;
begin
  if IsKindOf(C, TWinControl) then
    Result := TWinControl(C).ControlCount
  else
    Result := 0;
end;

// Direct children, for DelphiSpy to browse the parent tree; their addresses
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

// Ctrl may be nil (the forms reply)
function ProcessJson(Ctrl: TControl): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddInt(Result, 'pid', GetCurrentProcessId);
  AddStr(Result, 'exe', ParamStr(0));
  if LinkedInspectorName <> '' then
    AddStr(Result, 'computer', GetEnvironmentVariable('COMPUTERNAME'));
  AddStr(Result, 'framework', 'VCL');
  if OwnRtl then
  begin
    // The module that links the target's VCL: the exe, or a DLL with its own VCL
    if Ctrl <> nil then
      AddStr(Result, 'vclModule', ClassModuleName(TargetClass(Ctrl, TControl)));
    AddStr(Result, 'memoryManager', MemoryManagerText);
  end
  else if MemoryManagerMode = mmLinked then
    // Linked into a target without runtime packages
    AddStr(Result, 'vclModule', ClassModuleName(TControl))
  else
    AddStr(Result, 'vclPackage', ClassModuleName(TControl));
end;

// Wnd is reported as "window": a window on the thread that owns Ctrl, for
// DelphiSpy to send requests to
function NewReport(Ctrl: TControl; Wnd: HWND): TJSONObject;
var
  Mapping: TDpiMapping;
begin
  Mapping.Init(GetAncestor(Wnd, GA_ROOT));
  Result := TJSONObject.Create;
  try
    AddBool(Result, 'ok', True);
    AddStr(Result, 'inspector', InspectorText);
    Result.AddPair('process', ProcessJson(Ctrl));
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
    if OwnRtl then
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

// The target's forms, to browse a target that DelphiSpy can't drag the finder onto
function FormsReply: string;
var
  Reply, Item: TJSONObject;
  List: TJSONArray;
  Form: TWinControl;
begin
  Reply := TJSONObject.Create;
  try
    AddBool(Reply, 'ok', True);
    AddStr(Reply, 'inspector', InspectorText);
    Reply.AddPair('process', ProcessJson(nil));
    List := TJSONArray.Create;
    Reply.AddPair('forms', List);
    for Form in TargetForms do
    begin
      Item := TJSONObject.Create;
      AddStr(Item, 'name', Form.Name);
      AddStr(Item, 'className', Form.ClassName);
      AddStr(Item, 'kind', ComponentKind(Form));
      AddStr(Item, 'caption', Shorten(TControlAccess(Form).Text));
      AddStr(Item, 'address', AddressText(Form));
      AddBool(Item, 'visible', Form.Visible);
      AddBool(Item, 'enabled', Form.Enabled);
      if Form.HandleAllocated then
        AddInt(Item, 'hwnd', Form.Handle);
      AddInt(Item, 'childCount', ChildCount(Form));
      List.AddElement(Item);
    end;
    Result := Reply.ToJSON;
  finally
    Reply.Free;
  end;
end;

// Reports the control at the mouse cursor, or at "x" and "y"
function PickReply(Request: TJSONObject): string;
var
  Pt: TPoint;
  Wnd: HWND;
begin
  Wnd := PickWindow(Request, Pt, Result);
  if Wnd <> 0 then
    Result := BuildReport(Wnd, Pt);
end;

function HandleRequest(Wnd: HWND; const RequestJson: string): string;
var
  Value: TJSONValue;
  Request, Report, Changed: TJSONObject;
  Op: string;
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
    if SameText(Op, 'forms') then
      Exit(FormsReply);
    if SameText(Op, 'pick') then
      Exit(PickReply(Request));
    if not SameText(Op, 'get') and not SameText(Op, 'set') and not SameText(Op, 'children') then
      Exit(ErrorReport(Format('Unknown request op "%s"; use "get", "set", "children", "forms" or "pick".', [Op])));
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
      Result := SetMember(Ctrl, Request, Changed);
      if Result <> '' then
        Exit;
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

procedure DelphiSpyInspect(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
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

function RequestReply(Wnd: HWND; const Request: string): string;
begin
  try
    Result := HandleRequest(Wnd, RequestText(Request));
  except
    Result := ErrorReport(ExceptionText);
  end;
end;

procedure DelphiSpyRequest(Wnd: HWND; Request: PAnsiChar; ReplyWnd: HWND); stdcall;
var
  Json: string;
begin
  try
    Json := RequestReply(Wnd, UTF8ToString(Request));
  except
    Json := ErrorReport(ExceptionText);
  end;
  SendReply(ReplyWnd, Json);
end;

function DelphiSpyProbe(Wnd: HWND): BOOL; stdcall;
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
