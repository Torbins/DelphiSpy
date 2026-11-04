unit DelphiSpy.FmxInspector;

{ The inspector of FireMonkey targets, the counterpart of DelphiSpy.Inspector.
  It runs inside the target, on the GUI thread of the picked form, and has the
  same exports and requests (get, set, children, forms, pick).

  It links no FMX unit. Initializing a second FireMonkey in the target (its
  platform services, windows and OLE) would be too intrusive for the
  no-packages inspectors, and the package inspectors needn't load fmxNNN.bpl.
  So it reaches the target's FMX objects through their RTTI, and tells their
  classes by name (DelphiSpy.Target.AncestorNamed): public properties (Children,
  Parent, AbsoluteRect), published ones (Visible, Position) and the fields
  of TStyledControl. What it needs of the RTL (TComponent, TBasicAction,
  TStrings) has the layout of the inspector's own.

  - A form is found from its window through the window property that FMX
    gives each form's window ('FIREMONKEY' + process id), forms by
    enumerating the process' windows.
  - Controls have no windows: a point is resolved to the topmost visible
    control whose AbsoluteRect holds it, in the form's coordinates (dp; the
    window's pixels divided by the form's scale). HitTest doesn't matter,
    so labels are found too. Style objects (what a styled control applied,
    TStyledControl.FResourceLink, and below it) and the internal containers
    of controls (TContent, TStyledPresentation) are not picked, but are
    listed as children; reports mark style objects with "style".
  - Every FmxObject child is listed, also animations and effects.
  - The control's members are all its published and public properties
    (DelphiSpy.Members.AllPublicOfControl): FMX has no protected properties
    worth reaching, and the inspector couldn't reach them without FMX.

  The no-packages inspector checks that the target's FMX is the one of its
  Delphi version by the size of TCommonCustomForm (FormInstanceSize), which
  changes between versions; the RTL doesn't. }

interface

uses
  Winapi.Windows;

procedure DelphiSpyInspect(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
procedure DelphiSpyRequest(Wnd: HWND; Request: PAnsiChar; ReplyWnd: HWND); stdcall;
// Exported by the no-packages inspectors only
function DelphiSpyProbe(Wnd: HWND): BOOL; stdcall;

// The reply of DelphiSpyRequest as JSON, for DelphiSpy.FmxServer. Wnd may be 0:
// the object is then looked for in every form.
function RequestReply(Wnd: HWND; const Request: string): string;

implementation

uses
  System.Types, System.SysUtils, System.Classes, System.TypInfo, System.Rtti, System.UITypes,
  System.UIConsts, System.JSON, System.Generics.Collections,
  DelphiSpy.Properties, DelphiSpy.Members, DelphiSpy.Target, DelphiSpy.MemoryManager, DelphiSpy.Report;

// TCommonCustomForm.InstanceSize of the FMX of this Delphi version. For
// other versions (when DelphiSpy.FmxServer links the inspector) it isn't checked.
{$IF CompilerVersion = 34}
  {$DEFINE FORM_SIZE_KNOWN}
const
  FormInstanceSize = {$IFDEF WIN64}1176{$ELSE}692{$ENDIF};
{$ELSEIF CompilerVersion = 35}
  {$DEFINE FORM_SIZE_KNOWN}
const
  FormInstanceSize = {$IFDEF WIN64}1200{$ELSE}708{$ENDIF};
{$IFEND}

type
  TFormWindow = record
    Wnd: HWND;
    Form: TObject;
  end;

var
  // Keeps the RTTI objects
  Context: TRttiContext;

{ RTTI }

// The value of Obj's published or public property Name; empty if it has none
function PropValue(Obj: TObject; const Name: string): TValue;
var
  ObjType: TRttiType;
  Prop: TRttiProperty;
begin
  Result := TValue.Empty;
  if (Obj = nil) or (Obj.ClassInfo = nil) then
    Exit;
  ObjType := Context.GetType(Obj.ClassType);
  if ObjType = nil then
    Exit;
  Prop := ObjType.GetProperty(Name);
  if (Prop <> nil) and Prop.IsReadable and (Prop.PropertyType <> nil) then
    Result := Prop.GetValue(Obj);
end;

function PropObject(Obj: TObject; const Name: string): TObject;
var
  Value: TValue;
begin
  Value := PropValue(Obj, Name);
  if Value.IsObject then
    Result := Value.AsObject
  else
    Result := nil;
end;

function PropBool(Obj: TObject; const Name: string; Default: Boolean): Boolean;
var
  Value: TValue;
begin
  Value := PropValue(Obj, Name);
  if Value.IsEmpty or (Value.Kind <> tkEnumeration) then
    Result := Default
  else
    Result := Value.AsOrdinal <> 0;
end;

function PropFloat(Obj: TObject; const Name: string): Double;
var
  Value: TValue;
begin
  Value := PropValue(Obj, Name);
  case Value.Kind of
    tkFloat: Result := Value.AsExtended;
    tkInteger, tkInt64: Result := Value.AsOrdinal;
  else
    Result := 0;
  end;
end;

function PropString(Obj: TObject; const Name: string; out Text: string): Boolean;
var
  Value: TValue;
begin
  Value := PropValue(Obj, Name);
  Result := Value.Kind in [tkString, tkLString, tkWString, tkUString];
  if Result then
    Text := Value.AsString;
end;

// A published property's value as the property list shows it
function PublishedValue(Obj: TObject; const Name: string): string;
var
  Prop: PPropInfo;
begin
  Prop := GetPropInfo(Obj, Name);
  if Prop = nil then
    Result := ''
  else
    Result := PublishedText(Obj, Prop);
end;

function PropRect(Obj: TObject; const Name: string; out R: TRectF): Boolean;
var
  Value: TValue;
begin
  Value := PropValue(Obj, Name);
  Result := (Value.Kind = tkRecord) and (Value.DataSize = SizeOf(TRectF));
  if Result then
    Value.ExtractRawData(@R);
end;

{ The target's objects }

function IsFmxObject(Obj: TObject): Boolean;
begin
  Result := IsKindOfName(Obj, 'TFmxObject');
end;

function IsControl(Obj: TObject): Boolean;
begin
  Result := IsKindOfName(Obj, 'TControl');
end;

function IsForm(Obj: TObject): Boolean;
begin
  Result := IsKindOfName(Obj, 'TCommonCustomForm');
end;

function ParentOf(Obj: TObject): TObject;
begin
  Result := PropObject(Obj, 'Parent');
end;

// TFmxObject.Children; nil without children
function ChildrenOf(Obj: TObject): TArray<TObject>;
var
  List: TObject;
  ListType: TRttiType;
  Items: TRttiIndexedProperty;
  Count, I: Integer;
begin
  Result := nil;
  List := PropObject(Obj, 'Children');
  if List = nil then
    Exit;
  Count := PropValue(List, 'Count').AsInteger;
  ListType := Context.GetType(List.ClassType);
  Items := ListType.GetIndexedProperty('Items');
  if Items = nil then
    Exit;
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
    Result[I] := Items.GetValue(List, [I]).AsObject;
end;

function ChildCount(Obj: TObject): Integer;
var
  Value: TValue;
begin
  Value := PropValue(Obj, 'ChildrenCount');
  if Value.IsEmpty then
    Result := 0
  else
    Result := Value.AsInteger;
end;

// The style object that a styled control applied, a child of it
// (TStyledControl.FResourceLink, also TCustomForm's), or nil
function ResourceLink(Obj: TObject): TObject;
var
  ObjType: TRttiType;
  Field: TRttiField;
begin
  Result := nil;
  ObjType := Context.GetType(Obj.ClassType);
  if ObjType = nil then
    Exit;
  Field := ObjType.GetField('FResourceLink');
  if (Field <> nil) and (Field.FieldType <> nil) and (Field.FieldType.TypeKind = tkClass) then
    Result := Field.GetValue(Obj).AsObject;
end;

// Part of the style of a styled control
function IsStyleObject(Obj: TObject): Boolean;
var
  Parent: TObject;
begin
  Parent := ParentOf(Obj);
  while Parent <> nil do
  begin
    if ResourceLink(Parent) = Obj then
      Exit(True);
    Obj := Parent;
    Parent := ParentOf(Obj);
  end;
  Result := False;
end;

// Internal containers of controls: picked as the control they belong to
function IsInternal(Obj: TObject): Boolean;
begin
  Result := IsKindOfName(Obj, 'TContent') or IsKindOfName(Obj, 'TStyledPresentation');
end;

function TopParent(Obj: TObject): TObject;
var
  Parent: TObject;
begin
  Result := Obj;
  Parent := ParentOf(Result);
  while Parent <> nil do
  begin
    Result := Parent;
    Parent := ParentOf(Result);
  end;
end;

function TopForm(Obj: TObject): TObject;
begin
  Result := TopParent(Obj);
  if not IsForm(Result) then
    Result := nil;
end;

function DisplayName(Obj: TObject): string;
var
  Name: string;
begin
  if IsKindOf(Obj, TComponent) and (TComponent(Obj).Name <> '') then
    Result := TComponent(Obj).Name
  else if PropString(Obj, 'StyleName', Name) and (Name <> '') then
    Result := '''' + Name + ''''
  else
    Result := '<' + Obj.ClassName + '>';
end;

// Visual nesting: Form.Layout.Frame.Panel.Control
function ParentPath(Obj: TObject): string;
begin
  Result := DisplayName(Obj);
  Obj := ParentOf(Obj);
  while Obj <> nil do
  begin
    Result := DisplayName(Obj) + '.' + Result;
    Obj := ParentOf(Obj);
  end;
end;

{ Forms and windows }

function FmxWindowProperty: string;
begin
  Result := Format('FIREMONKEY%.8X', [GetCurrentProcessId]);
end;

// The FMX form of Wnd itself, or nil. Check it with CheckTarget before use.
function FindForm(Wnd: HWND): TObject;
var
  Pid: DWORD;
  P: Pointer;
begin
  Result := nil;
  if (Wnd = 0) or (GetWindowThreadProcessId(Wnd, Pid) = 0) or (Pid <> GetCurrentProcessId) then
    Exit;
  P := Pointer(GetProp(Wnd, PChar(FmxWindowProperty)));
  if (P <> nil) and LooksLikeObject(P) and IsForm(TObject(P)) then
    Result := TObject(P);
end;

// The form of Wnd or of its nearest parent window that has one (native
// controls have windows of their own), and that window
function WindowForm(Wnd: HWND; out FormWnd: HWND): TObject;
begin
  Result := nil;
  FormWnd := 0;
  while (Wnd <> 0) and (Result = nil) do
  begin
    Result := FindForm(Wnd);
    if Result = nil then
      Wnd := GetParent(Wnd)
    else
      FormWnd := Wnd;
  end;
end;

function CollectForm(Wnd: HWND; List: TList<TFormWindow>): BOOL; stdcall;
var
  Item: TFormWindow;
begin
  try
    Item.Form := FindForm(Wnd);
    if Item.Form <> nil then
    begin
      Item.Wnd := Wnd;
      List.Add(Item);
    end;
  except
    // Not into EnumWindows
  end;
  Result := True;
end;

// The process' forms: those with top-level windows
function FormWindows: TArray<TFormWindow>;
var
  List: TList<TFormWindow>;
begin
  List := TList<TFormWindow>.Create;
  try
    EnumWindows(@CollectForm, LPARAM(List));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// The window of Form, or Fallback
function FormWindow(Form: TObject; Fallback: HWND): HWND;
var
  Item: TFormWindow;
begin
  if (Fallback <> 0) and (FindForm(Fallback) = Form) then
    Exit(Fallback);
  for Item in FormWindows do
    if Item.Form = Form then
      Exit(Item.Wnd);
  Result := Fallback;
end;

// False, with a message, when the target's RTL or FMX doesn't have this
// inspector's layout: the target was built with another Delphi version
function CheckTarget(Obj: TObject; out Error: string): Boolean;
{$IFDEF FORM_SIZE_KNOWN}
var
  Form: TClass;
{$ENDIF}
begin
  if not CheckRtl(Obj, Error) then
    Exit(False);
  if not IsFmxObject(Obj) then
  begin
    Error := Format('%s is not a FireMonkey object: it doesn''t inherit from TFmxObject.', [Obj.ClassName]);
    Exit(False);
  end;
{$IFDEF FORM_SIZE_KNOWN}
  Form := AncestorNamed(Obj, 'TCommonCustomForm');
  if OwnRtl and (Form <> nil) and (Form.InstanceSize <> FormInstanceSize) then
  begin
    Error := Format('The target''s FireMonkey doesn''t match the inspector''s (Delphi %.1f): its ' +
      'TCommonCustomForm has %d bytes, the inspector''s %d. The target may be built with another Delphi ' +
      'version.', [CompilerVersion, Form.InstanceSize, FormInstanceSize]);
    Exit(False);
  end;
{$ENDIF}
  Result := True;
end;

// Forms that pass CheckTarget
function TargetForms: TArray<TFormWindow>;
var
  Item: TFormWindow;
  Error: string;
begin
  Result := nil;
  for Item in FormWindows do
    if CheckTarget(Item.Form, Error) then
      Result := Result + [Item];
end;

{ Coordinates }

// Pixels per dp of the form's window
function FormScale(Form: TObject; Wnd: HWND): Double;
var
  Handle: TObject;
  Width: Integer;
  R: TRect;
begin
  Result := 0;
  try
    Handle := PropObject(Form, 'Handle');
    if Handle <> nil then
      Result := PropFloat(Handle, 'Scale');
  except
    Result := 0;
  end;
  if Result > 0 then
    Exit;
  Width := Round(PropFloat(Form, 'ClientWidth'));
  if (Width > 0) and GetClientRect(Wnd, R) and (R.Width > 0) then
    Result := R.Width / Width
  else
    Result := 1;
end;

// A point of the form (dp) in logical screen coordinates, and back
function FormToScreen(Wnd: HWND; Scale: Double; const P: TPointF): TPoint;
begin
  Result := Point(Round(P.X * Scale), Round(P.Y * Scale));
  ClientToScreen(Wnd, Result);
end;

function ScreenToForm(Wnd: HWND; Scale: Double; P: TPoint): TPointF;
begin
  ScreenToClient(Wnd, P);
  Result := PointF(P.X / Scale, P.Y / Scale);
end;

function PhysicalScreenRect(Obj, Form: TObject; FormWnd: HWND; const Mapping: TDpiMapping): TRect;
var
  R: TRect;
  F: TRectF;
  Scale: Double;
begin
  if (Obj = Form) and (FormWnd <> 0) then
    GetWindowRect(FormWnd, R)
  else if (Form <> nil) and (FormWnd <> 0) and IsControl(Obj) and PropRect(Obj, 'AbsoluteRect', F) then
  begin
    Scale := FormScale(Form, FormWnd);
    R.TopLeft := FormToScreen(FormWnd, Scale, F.TopLeft);
    R.BottomRight := FormToScreen(FormWnd, Scale, F.BottomRight);
  end
  else
    Exit(Rect(0, 0, 0, 0));
  Result.TopLeft := Mapping.ToPhysical(R.TopLeft);
  Result.BottomRight := Mapping.ToPhysical(R.BottomRight);
end;

// The topmost visible control at P (dp) of the form, in paint order: each
// control is painted before its children, children in order. Style objects
// and internal containers are not picked, though the controls inside the
// latter are; ClipChildren hides children outside their parent.
function ControlAt(Form: TObject; const P: TPointF): TObject;
var
  Found: TObject;

  procedure Visit(Obj: TObject);
  var
    Child, Link: TObject;
    R: TRectF;
    Inside: Boolean;
  begin
    Link := ResourceLink(Obj);
    for Child in ChildrenOf(Obj) do
    begin
      if (Child = Link) or not IsControl(Child) or not PropBool(Child, 'Visible', True) then
        Continue;
      Inside := PropRect(Child, 'AbsoluteRect', R) and R.Contains(P);
      if Inside and not IsInternal(Child) then
        Found := Child;
      if Inside or not PropBool(Child, 'ClipChildren', False) then
        Visit(Child);
    end;
  end;

begin
  Found := Form;
  Visit(Form);
  Result := Found;
end;

{ Sections }

function ChildJson(Child: TObject; IsStyle: Boolean): TJSONObject;
var
  StyleName: string;
begin
  Result := TJSONObject.Create;
  if IsKindOf(Child, TComponent) then
    AddStr(Result, 'name', TComponent(Child).Name);
  if PropString(Child, 'StyleName', StyleName) and (StyleName <> '') then
    AddStr(Result, 'styleName', StyleName);
  AddStr(Result, 'className', Child.ClassName);
  AddStr(Result, 'address', AddressText(Child));
  if IsControl(Child) then
  begin
    AddBool(Result, 'visible', PropBool(Child, 'Visible', True));
    AddBool(Result, 'enabled', PropBool(Child, 'Enabled', True));
  end;
  if IsStyle then
    AddBool(Result, 'style', True);
  AddInt(Result, 'childCount', ChildCount(Child));
end;

// Direct children, for DelphiSpy to browse the parent tree; their addresses
// work in requests. IsStyle: Obj is part of a style, and so are they.
function ChildrenJson(Obj: TObject; IsStyle: Boolean): TJSONArray;
var
  Child, Link: TObject;
begin
  Result := TJSONArray.Create;
  Link := ResourceLink(Obj);
  for Child in ChildrenOf(Obj) do
    Result.AddElement(ChildJson(Child, IsStyle or (Child = Link)));
end;

function ParentsJson(Obj: TObject; FormWnd: HWND): TJSONArray;
var
  Item: TJSONObject;
  Parent: TObject;
begin
  Result := TJSONArray.Create;
  Parent := ParentOf(Obj);
  while Parent <> nil do
  begin
    Item := ChildJson(Parent, IsStyleObject(Parent));
    AddStr(Item, 'kind', ComponentKind(TComponent(Parent)));
    if IsForm(Parent) and (FormWnd <> 0) then
      AddInt(Item, 'hwnd', FormWnd);
    Item.AddPair('children', ChildrenJson(Parent, Item.GetValue<Boolean>('style', False)));
    Result.AddElement(Item);
    Parent := ParentOf(Parent);
  end;
end;

function BoundsJson(Obj: TObject): TJSONObject;
var
  Position: TObject;
begin
  Result := TJSONObject.Create;
  Position := PropObject(Obj, 'Position');
  if Position <> nil then
  begin
    AddFloat(Result, 'left', PropFloat(Position, 'X'));
    AddFloat(Result, 'top', PropFloat(Position, 'Y'));
  end
  else
  begin
    AddFloat(Result, 'left', PropFloat(Obj, 'Left'));
    AddFloat(Result, 'top', PropFloat(Obj, 'Top'));
  end;
  AddFloat(Result, 'width', PropFloat(Obj, 'Width'));
  AddFloat(Result, 'height', PropFloat(Obj, 'Height'));
end;

function ObjectJson(Obj: TObject; FormWnd: HWND; const Mapping: TDpiMapping): TJSONObject;
var
  Form, Action: TObject;
  FormObj: TJSONObject;
  Text: string;
  IsStyle: Boolean;
begin
  Form := TopForm(Obj);
  IsStyle := IsStyleObject(Obj);
  Result := TJSONObject.Create;
  AddStr(Result, 'name', TComponent(Obj).Name);
  if PropString(Obj, 'StyleName', Text) and (Text <> '') then
    AddStr(Result, 'styleName', Text);
  AddStr(Result, 'className', Obj.ClassName);
  AddStr(Result, 'unitName', Obj.UnitName);
  AddStr(Result, 'module', ModulePath(ModuleOf(Obj.ClassType)));
  // Identifies the object in requests
  AddStr(Result, 'address', AddressText(Obj));
  AddStr(Result, 'path', ComponentPath(TComponent(Obj)));
  AddStr(Result, 'parentPath', ParentPath(Obj));
  if PropString(Obj, 'Text', Text) or PropString(Obj, 'Caption', Text) then
    AddStr(Result, 'text', Shorten(Text));
  if PropString(Obj, 'Hint', Text) then
    AddStr(Result, 'hint', Shorten(Text));
  AddBool(Result, 'visible', PropBool(Obj, 'Visible', True));
  AddBool(Result, 'enabled', PropBool(Obj, 'Enabled', True));
  AddInt(Result, 'tag', TComponent(Obj).Tag);
  if IsStyle then
    AddBool(Result, 'style', True);
  AddBool(Result, 'isWinControl', False);
  if (Obj = Form) and (FormWnd <> 0) then
    AddInt(Result, 'hwnd', FormWnd);

  if IsControl(Obj) or IsForm(Obj) then
    Result.AddPair('bounds', BoundsJson(Obj));
  Result.AddPair('screenRect', RectJson(PhysicalScreenRect(Obj, Form, FormWnd, Mapping)));

  if Form <> nil then
  begin
    FormObj := ComponentJson(TComponent(Form));
    if PropString(Form, 'Caption', Text) then
      AddStr(FormObj, 'caption', Text);
    AddStr(FormObj, 'module', ClassModuleName(Form.ClassType));
    Result.AddPair('form', FormObj);
  end;

  if GetPropInfo(Obj, 'Action') <> nil then
  begin
    Action := PropObject(Obj, 'Action');
    if IsKindOf(Action, TBasicAction) then
      Result.AddPair('action', ActionJson(TBasicAction(Action)));
  end;

  Result.AddPair('owners', OwnersJson(TComponent(Obj)));
  Result.AddPair('parents', ParentsJson(Obj, FormWnd));
  Result.AddPair('children', ChildrenJson(Obj, IsStyle));
  Result.AddPair('classHierarchy', ClassHierarchyJson(Obj.ClassType));
  AddProperties(Result, Obj);
end;

// Obj may be nil (the forms reply)
function ProcessJson(Obj: TObject): TJSONObject;
var
  Module: string;
begin
  Result := TJSONObject.Create;
  AddInt(Result, 'pid', GetCurrentProcessId);
  AddStr(Result, 'exe', ParamStr(0));
  if LinkedInspectorName <> '' then
    AddStr(Result, 'computer', GetEnvironmentVariable('COMPUTERNAME'));
  AddStr(Result, 'framework', 'FMX');
  if Obj <> nil then
  begin
    // The module that links the target's FMX: the exe, a DLL, or fmxNNN.bpl
    Module := ClassModuleName(AncestorNamed(Obj, 'TFmxObject'));
    if SameText(ExtractFileExt(Module), '.bpl') then
      AddStr(Result, 'fmxPackage', Module)
    else
      AddStr(Result, 'fmxModule', Module);
  end;
  if OwnRtl then
    AddStr(Result, 'memoryManager', MemoryManagerText);
end;

// FormWnd is reported as "window", for DelphiSpy to send requests to
function NewReport(Obj: TObject; FormWnd: HWND): TJSONObject;
var
  Mapping: TDpiMapping;
begin
  Mapping.Init(GetAncestor(FormWnd, GA_ROOT));
  Result := TJSONObject.Create;
  try
    AddBool(Result, 'ok', True);
    AddStr(Result, 'inspector', InspectorText);
    Result.AddPair('process', ProcessJson(Obj));
    Result.AddPair('window', WindowJson(FormWnd));
    Result.AddPair('control', ObjectJson(Obj, FormWnd, Mapping));
  except
    Result.Free;
    raise;
  end;
end;

function BuildReport(Wnd: HWND; const ScreenPt: TPoint): string;
var
  Mapping: TDpiMapping;
  FormWnd: HWND;
  Form, Obj: TObject;
  Report: TJSONObject;
begin
  Form := WindowForm(Wnd, FormWnd);
  if Form = nil then
    Exit(ErrorReport(Format('Window $%x is not a FireMonkey form, nor a window on one.', [NativeUInt(Wnd)])));
  if not CheckTarget(Form, Result) then
    Exit(ErrorReport(Result));

  Mapping.Init(GetAncestor(FormWnd, GA_ROOT));
  Obj := ControlAt(Form, ScreenToForm(FormWnd, FormScale(Form, FormWnd), Mapping.ToLogical(ScreenPt)));

  Report := NewReport(Obj, FormWnd);
  try
    if Obj <> Form then
      AddStr(Report, 'resolvedFrom', ComponentPath(TComponent(Form)));
    Result := Report.ToJSON;
  finally
    Report.Free;
  end;
end;

{ Requests }

// Finds the object at Address among the live objects of the forms, style
// objects included, so that an address from an old report is never
// dereferenced. Searches Root's form (that of the window the request was
// sent to) first.
function FindLiveObject(Address: Pointer; Root: TObject): TObject;

  function Search(Obj: TObject): TObject;
  var
    Child: TObject;
  begin
    if Pointer(Obj) = Address then
      Exit(Obj);
    for Child in ChildrenOf(Obj) do
    begin
      Result := Search(Child);
      if Result <> nil then
        Exit;
    end;
    Result := nil;
  end;

var
  Item: TFormWindow;
begin
  if Root <> nil then
  begin
    Result := Search(Root);
    if Result <> nil then
      Exit;
  end;
  for Item in TargetForms do
    if Item.Form <> Root then
    begin
      Result := Search(Item.Form);
      if Result <> nil then
        Exit;
    end;
  Result := nil;
end;

// The target's forms, to browse a target that DelphiSpy can't drag the finder onto
function FormsReply: string;
var
  Reply, Item: TJSONObject;
  List: TJSONArray;
  Form: TFormWindow;
  Caption: string;
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
      AddStr(Item, 'name', TComponent(Form.Form).Name);
      AddStr(Item, 'className', Form.Form.ClassName);
      AddStr(Item, 'kind', ComponentKind(TComponent(Form.Form)));
      if PropString(Form.Form, 'Caption', Caption) then
        AddStr(Item, 'caption', Shorten(Caption));
      AddStr(Item, 'address', AddressText(Form.Form));
      AddBool(Item, 'visible', PropBool(Form.Form, 'Visible', True));
      AddBool(Item, 'enabled', IsWindowEnabled(Form.Wnd));
      AddInt(Item, 'hwnd', Form.Wnd);
      AddInt(Item, 'childCount', ChildCount(Form.Form));
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
  FormWnd: HWND;
  Root, Obj, Form: TObject;
begin
  Root := WindowForm(Wnd, FormWnd);
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

    Obj := FindLiveObject(Pointer(NativeUInt(Address)), Root);
    if Obj = nil then
      Exit(ErrorReport('The control no longer exists (it may have been destroyed). Pick it again.'));

    if SameText(Op, 'children') then
    begin
      Report := TJSONObject.Create;
      try
        AddBool(Report, 'ok', True);
        AddStr(Report, 'address', AddressText(Obj));
        Report.AddPair('children', ChildrenJson(Obj, IsStyleObject(Obj)));
        Result := Report.ToJSON;
      finally
        Report.Free;
      end;
      Exit;
    end;

    if SameText(Op, 'set') then
    begin
      Result := SetMember(Obj, Request, Changed);
      if Result <> '' then
        Exit;
    end;

    Form := TopForm(Obj);
    if Form <> nil then
      FormWnd := FormWindow(Form, FormWnd);
    if FormWnd = 0 then
      FormWnd := Wnd;
    Report := NewReport(Obj, FormWnd);
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

{ Exports }

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
  Form: TObject;
  FormWnd: HWND;
  Error: string;
begin
  try
    Form := WindowForm(Wnd, FormWnd);
    Result := (Form <> nil) and CheckTarget(Form, Error);
  except
    Result := False;
  end;
end;

{ What DelphiSpy.Properties and DelphiSpy.Members need to know about FMX }

function AlphaColorFromText(const Text: string; out Value: Integer): Boolean;
var
  S: string;
  Number: Int64;
begin
  S := Text;
  if (S <> '') and (S[1] = '#') then
    S := '$' + Copy(S, 2, MaxInt);
  Result := IdentToAlphaColor('cla' + S, Value) or IdentToAlphaColor(S, Value);
  if not Result and TryStrToInt64(S, Number) and (Number >= Low(Integer)) and (Number <= High(Cardinal)) then
  begin
    Value := Integer(Cardinal(Number));
    Result := True;
  end;
end;

procedure RegisterNames;
var
  Names: TOrdNames;
begin
  Names := Default(TOrdNames);
  Names.ToText := function(V: Integer): string begin Result := AlphaColorToString(TAlphaColor(V)) end;
  Names.FromText := AlphaColorFromText;
  Names.GetValues := procedure(Proc: TGetStrProc) begin GetAlphaColorValues(Proc) end;
  Names.Error := '"%s" is not a color. Use a name such as Red or claRed, or a number such as #FF0080FF ' +
    '(#AARRGGBB).';
  RegisterOrdNames('TAlphaColor', Names);

  Names := Default(TOrdNames);
  Names.ToText := function(V: Integer): string begin Result := CursorToString(TCursor(V)) end;
  Names.FromText :=
    function(const S: string; out V: Integer): Boolean
    begin
      Result := IdentToCursor(S, V) or TryStrToInt(S, V);
    end;
  Names.GetValues := procedure(Proc: TGetStrProc) begin GetCursorValues(Proc) end;
  Names.Error := '"%s" is not a cursor. Use a name such as crHandPoint, or a number.';
  RegisterOrdNames('TCursor', Names);
end;

procedure RegisterObjects;
begin
  AllPublicOfControl := True;
  // Canvas getters may create one (TBitmap); TFmxObject.Data is a TValue;
  // Controls lists the same controls as Children
  RegisterSkippedProperty('*', 'Canvas');
  RegisterSkippedProperty('TFmxObject', 'Data');
  RegisterSkippedProperty('TControl', 'Controls');

  RegisterSummary('TFont',
    function(Obj: TObject): string
    begin
      Result := Format('(%s) %s, %s', [Obj.ClassName, PublishedValue(Obj, 'Family'), PublishedValue(Obj, 'Size')]);
    end);
  RegisterSummary('TBrush',
    function(Obj: TObject): string
    begin
      Result := Format('(%s) %s, %s', [Obj.ClassName, PublishedValue(Obj, 'Kind'), PublishedValue(Obj, 'Color')]);
    end);
  RegisterSummary('TTextSettings',
    function(Obj: TObject): string
    begin
      Result := Format('(%s) %s, %s', [Obj.ClassName, ObjectSummary(PropObject(Obj, 'Font')),
        PublishedValue(Obj, 'FontColor')]);
    end);
  RegisterSummary('TPosition',
    function(Obj: TObject): string
    begin
      Result := Format('(%s) X = %s, Y = %s', [Obj.ClassName, PublishedValue(Obj, 'X'), PublishedValue(Obj, 'Y')]);
    end);
  RegisterSummary('TBounds',
    function(Obj: TObject): string
    begin
      Result := Format('(%s) %s, %s, %s, %s', [Obj.ClassName, PublishedValue(Obj, 'Left'),
        PublishedValue(Obj, 'Top'), PublishedValue(Obj, 'Right'), PublishedValue(Obj, 'Bottom')]);
    end);
  RegisterSummary('TFmxChildrenList',
    function(Obj: TObject): string
    begin
      Result := Format('(%s, Count = %d)', [Obj.ClassName, PropValue(Obj, 'Count').AsInteger]);
    end);
end;

initialization
  Context := TRttiContext.Create;
  RegisterNames;
  RegisterObjects;
finalization
  Context.Free;
end.
