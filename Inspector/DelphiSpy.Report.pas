unit DelphiSpy.Report;

{ The parts of a report that don't depend on the framework, shared by the VCL
  inspector (DelphiSpy.Inspector) and the FMX inspector (DelphiSpy.FmxInspector):
  JSON helpers, the properties and events of an object, owners, class
  hierarchy, coordinates and the reply to DelphiSpy. Runs inside the target,
  on its GUI thread. }

interface

uses
  Winapi.Windows, System.Types, System.SysUtils, System.Classes, System.TypInfo, System.JSON,
  DelphiSpy.Members;

type
  // Maps between the target window's logical coordinates and the physical
  // screen coordinates DelphiSpy works in (they differ for DPI-unaware targets).
  TDpiMapping = record
    Logical, Physical: TRect;
    procedure Init(Wnd: HWND);
    function ToLogical(const P: TPoint): TPoint;
    function ToPhysical(const P: TPoint): TPoint;
  end;

procedure AddStr(Obj: TJSONObject; const Name, Value: string);
procedure AddInt(Obj: TJSONObject; const Name: string; Value: Int64);
procedure AddFloat(Obj: TJSONObject; const Name: string; Value: Double);
procedure AddBool(Obj: TJSONObject; const Name: string; Value: Boolean);
function RectJson(const R: TRect): TJSONObject;
function ErrorReport(const Msg: string): string;

function ModulePath(Module: HMODULE): string;
function ClassModuleName(Cls: TClass): string;
function AddressText(Obj: TObject): string;
// "form", "frame", "dataModule", "control" or "component"
function ComponentKind(C: TComponent): string;

// The full value of a member; PropJson shortens it for the report
function MemberText(const Member: TMember): string;
function HandlerJson(const EventName: string; const Method: TMethod): TJSONObject;
// "properties", "events" and "types" of Ctrl
procedure AddProperties(Target: TJSONObject; Ctrl: TObject);
function ClassHierarchyJson(Cls: TClass): TJSONArray;
function OwnersJson(C: TComponent): TJSONArray;
function ComponentJson(C: TComponent): TJSONObject;
function ActionJson(Action: TBasicAction): TJSONObject;
function WindowJson(Wnd: HWND): TJSONObject;

// "inspector" of a report: the DLL, Delphi version, platform...
function InspectorText: string;

// Op "set": sets the member that "property" of Request names to "value".
// Returns an error report, or '' and the "changed" object of the reply.
function SetMember(Ctrl: TObject; Request: TJSONObject; out Changed: TJSONObject): string;

// The deepest window at a physical screen point, disabled ones included
// (WindowFromPoint skips those), as DelphiSpy's finder resolves it. With
// AtCursor, the window at the mouse cursor, whose position Pt returns.
function WindowAtPhysicalPoint(var Pt: TPoint; AtCursor: Boolean): HWND;
// Op "pick": the window to report, at the mouse cursor or at "x" and "y" of
// Request. Returns 0 with an error report in Error.
function PickWindow(Request: TJSONObject; out Pt: TPoint; out Error: string): HWND;

// The request text without the BOM of a request file
function RequestText(const Request: string): string;
procedure SendReply(ReplyWnd: HWND; const Json: string);

var
  // Set by DelphiSpy.Server, which links the inspector into the target; reports
  // name it instead of the inspector DLL
  LinkedInspectorName: string;

implementation

uses
  Winapi.Messages, System.Math, System.Generics.Collections, DelphiSpy.Protocol, DelphiSpy.Properties, DelphiSpy.Target,
  DelphiSpy.MemoryManager;

type
  TSetThreadDpiAwarenessContext = function(Context: THandle): THandle; stdcall;

const
  DpiAwarenessPerMonitorV2 = THandle(-4);
  // Levels of object properties, collection items and record fields below
  // the control's properties
  MaxPropertyDepth = 4;

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

procedure AddFloat(Obj: TJSONObject; const Name: string; Value: Double);
begin
  // Singles as they were set: 12.3, not 12.3000001907349
  Obj.AddPair(Name, TJSONNumber.Create(SimpleRoundTo(Value, -3)));
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

function AddressText(Obj: TObject): string;
begin
  Result := Format('$%p', [Pointer(Obj)]);
end;

// By name: the VCL's and FMX's classes alike
function ComponentKind(C: TComponent): string;
begin
  if IsKindOfName(C, 'TCustomForm') or IsKindOfName(C, 'TCommonCustomForm') then
    Result := 'form'
  else if IsKindOfName(C, 'TCustomFrame') or IsKindOfName(C, 'TFrame') then
    Result := 'frame'
  else if IsKindOf(C, TDataModule) then
    Result := 'dataModule'
  else if IsKindOfName(C, 'TControl') then
    Result := 'control'
  else
    Result := 'component';
end;

{ Property values }

function MemberText(const Member: TMember): string;
begin
  if Member.IsObject then
    Result := ObjectSummary(Member.GetObject)
  else
    Result := Member.ValueText;
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

{ Properties }

function PropJson(const Name, Path: string; Info: PTypeInfo; const Value, Scope: string;
  Editable: Boolean; Types: TJSONObject): TJSONObject;
var
  Values: TJSONArray;
  TypeName: string;
begin
  TypeName := GetTypeName(Info);
  Result := TJSONObject.Create;
  AddStr(Result, 'name', Name);
  AddStr(Result, 'path', Path);
  AddStr(Result, 'type', TypeName);
  AddStr(Result, 'kind', KindName(Info));
  AddStr(Result, 'value', Shorten(Value));
  if Length(Value) > MaxValueLength then
    AddBool(Result, 'truncated', True);
  AddStr(Result, 'scope', Scope);
  AddBool(Result, 'editable', Editable);
  // Names for DelphiSpy's editor, once per type
  if Editable and (Types.GetValue(TypeName) = nil) then
  begin
    Values := TypeValuesJson(Info);
    if Values <> nil then
      Types.AddPair(TypeName, Values);
  end;
end;

// A property, and below it, in "properties", the members of the object or
// record it returns (DelphiSpy.Members). Expanded holds the objects whose
// members are listed already: each object's are listed once.
function MemberJson(const Member: TMember; const Path: string; Depth: Integer; Types: TJSONObject;
  Expanded: TList<TObject>): TJSONObject;
var
  Value: string;
  Obj: TObject;
  Failed, Editable: Boolean;
  Members: TArray<TMember>;
  Child: TMember;
  List: TJSONArray;
begin
  Obj := nil;
  Failed := False;
  Editable := False;
  try
    if Member.IsObject then
    begin
      Obj := Member.GetObject;
      Value := ObjectSummary(Obj);
    end
    else
      Value := Member.ValueText;
    Editable := Member.IsEditable;
  except
    Value := '<error: ' + ExceptionMessage + '>';
    Failed := True;
  end;
  Result := PropJson(Member.Name, Path, Member.Info, Value, Member.Scope, Editable, Types);
  if Failed or (Depth >= MaxPropertyDepth) then
    Exit;

  Members := nil;
  try
    if (Obj <> nil) and ShowsMembers(Obj) and not Expanded.Contains(Obj) then
    begin
      Expanded.Add(Obj);
      Members := ObjectMembers(Obj);
    end
    else if Member.IsRecord then
      Members := Member.Fields;
  except
    AddStr(Result, 'error', ExceptionMessage);
    Exit;
  end;
  if Members = nil then
    Exit;
  List := TJSONArray.Create;
  Result.AddPair('properties', List);
  for Child in Members do
    List.AddElement(MemberJson(Child, JoinPath(Path, Child.Name), Depth + 1, Types, Expanded));
end;

// The control's members (ControlMembers) sorted by name, each with the
// members of the object or record it returns, and its event handlers.
// "types" lists the names that editable enumeration, set, color and cursor
// types accept.
procedure AddProperties(Target: TJSONObject; Ctrl: TObject);
var
  Count, I: Integer;
  List: PPropList;
  Prop: PPropInfo;
  Props, Events: TJSONArray;
  Types: TJSONObject;
  Member: TMember;
  Method: TMethod;
  Expanded: TList<TObject>;
begin
  Props := TJSONArray.Create;
  Target.AddPair('properties', Props);
  Events := TJSONArray.Create;
  Target.AddPair('events', Events);
  Types := TJSONObject.Create;
  Target.AddPair('types', Types);

  Count := GetPropList(PTypeInfo(Ctrl.ClassInfo), List);
  if Count > 0 then
  try
    for I := 0 to Count - 1 do
    begin
      Prop := List^[I];
      if (Prop^.GetProc <> nil) and (Prop^.PropType^.Kind = tkMethod) then
      begin
        Method := GetMethodProp(Ctrl, Prop);
        if Method.Code <> nil then
          Events.AddElement(HandlerJson(GetPropName(Prop), Method));
      end;
    end;
  finally
    FreeMem(List);
  end;

  Expanded := TList<TObject>.Create;
  try
    Expanded.Add(Ctrl);
    for Member in ControlMembers(Ctrl) do
      Props.AddElement(MemberJson(Member, Member.Name, 0, Types, Expanded));
  finally
    Expanded.Free;
  end;
end;

{ Sections }

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

function InspectorText: string;
const
  Platform = {$IFDEF WIN64}'Win64'{$ELSE}'Win32'{$ENDIF};
begin
  if LinkedInspectorName <> '' then
    Result := Format('%s in %s (Delphi %.1f, %s)', [LinkedInspectorName,
      ExtractFileName(ModulePath(HInstance)), CompilerVersion, Platform])
  else if OwnRtl then
    Result := Format('%s (Delphi %.1f, %s, no packages, memory manager: %s)',
      [ExtractFileName(ModulePath(HInstance)), CompilerVersion, Platform, MemoryManagerText])
  else
    Result := Format('%s (Delphi %.1f, %s)', [ExtractFileName(ModulePath(HInstance)),
      CompilerVersion, Platform]);
end;

{ Requests }

function SetMember(Ctrl: TObject; Request: TJSONObject; out Changed: TJSONObject): string;
var
  Name, Text, OldText: string;
  Member: TMember;
begin
  Changed := nil;
  Name := Request.GetValue<string>('property', '');
  if not Request.TryGetValue<string>('value', Text) then
    Exit(ErrorReport('The request needs "value".'));
  try
    Member := FindMember(Ctrl, Name);
    OldText := MemberText(Member);
    Member.SetValueText(Text);
  except
    // Also exceptions of the target's setter, which aren't the inspector's Exception
    Exit(ErrorReport(Format('Cannot set %s: %s', [Name, ExceptionMessage])));
  end;
  Changed := TJSONObject.Create;
  AddStr(Changed, 'property', Name);
  AddStr(Changed, 'oldValue', Shorten(OldText));
  // Again: a record field's member holds the record as it was
  AddStr(Changed, 'newValue', Shorten(MemberText(FindMember(Ctrl, Name))));
  Result := '';
end;

function WindowAtPhysicalPoint(var Pt: TPoint; AtCursor: Boolean): HWND;
var
  SetContext: TSetThreadDpiAwarenessContext;
  Old: THandle;
  Child: HWND;
  ClientPt: TPoint;
begin
  // Physical coordinates, also in a DPI-unaware target
  @SetContext := GetProcAddress(GetModuleHandle(user32), 'SetThreadDpiAwarenessContext');
  Old := 0;
  if Assigned(SetContext) then
    Old := SetContext(DpiAwarenessPerMonitorV2);
  try
    if AtCursor then
      GetCursorPos(Pt);
    Result := WindowFromPoint(Pt);
    if Result = 0 then
      Exit;
    Result := GetAncestor(Result, GA_ROOT);
    repeat
      ClientPt := Pt;
      ScreenToClient(Result, ClientPt);
      Child := ChildWindowFromPointEx(Result, ClientPt, CWP_SKIPINVISIBLE or CWP_SKIPTRANSPARENT);
      if (Child = 0) or (Child = Result) then
        Break;
      Result := Child;
    until False;
  finally
    if Old <> 0 then
      SetContext(Old);
  end;
end;

function PickWindow(Request: TJSONObject; out Pt: TPoint; out Error: string): HWND;
var
  AtCursor: Boolean;
  Pid: DWORD;
  Where: string;
begin
  Error := '';
  AtCursor := not (Request.TryGetValue<Integer>('x', Pt.X) and Request.TryGetValue<Integer>('y', Pt.Y));
  Result := WindowAtPhysicalPoint(Pt, AtCursor);
  if AtCursor then
    Where := Format('the mouse cursor (%d, %d)', [Pt.X, Pt.Y])
  else
    Where := Format('%d, %d', [Pt.X, Pt.Y]);
  if Result = 0 then
    Error := ErrorReport('There is no window at ' + Where + '.')
  else
  begin
    GetWindowThreadProcessId(Result, Pid);
    if Pid <> GetCurrentProcessId then
    begin
      Error := ErrorReport(Format('The window at %s is not one of %s.', [Where, ExtractFileName(ParamStr(0))]));
      Result := 0;
    end;
  end;
end;

function RequestText(const Request: string): string;
begin
  Result := Request;
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1); // BOM of a request file
end;

procedure SendReply(ReplyWnd: HWND; const Json: string);
var
  Bytes: TBytes;
  Data: TCopyDataStruct;
  Res: DWORD_PTR;
begin
  Bytes := TEncoding.UTF8.GetBytes(Json);
  Data.dwData := DelphiSpyCopyDataMagic;
  Data.cbData := Length(Bytes);
  Data.lpData := Pointer(Bytes);
  SendMessageTimeout(ReplyWnd, WM_COPYDATA, 0, LPARAM(@Data), SMTO_ABORTIFHUNG,
    DelphiSpyReplyTimeout, @Res);
end;

end.
