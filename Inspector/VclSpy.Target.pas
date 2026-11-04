unit VclSpy.Target;

{ Finds the target's VCL objects and tells their classes apart, for both kinds
  of inspector DLL.

  The package inspectors (VclSpyInspectNNN.dll) share the target's rtl and vcl
  packages: the target's objects are instances of the inspector's own classes,
  so "is", FindControl and Screen work for them.

  The no-packages inspectors (VclSpyInspectNoPkgNNN.dll) link the VCL
  statically, as the target does. Built by the same Delphi version, the
  target's objects have the layout of the inspector's classes, so their
  fields, RTTI, virtual methods and the VCL's static methods work, but their
  classes are the target's own. So classes are compared by name, controls are
  found through the window property that every VCL module in the process sets
  ('Delphi' + process id), and forms by enumerating the process' windows.
  CheckTarget makes sure that the target's VCL has this inspector's layout. }

interface

uses
  Winapi.Windows, Vcl.Controls, Vcl.Forms;

// True in the no-packages inspectors
function OwnVcl: Boolean;

// Obj is Cls; in the no-packages inspectors also when it inherits from a
// class of the same name
function IsKindOf(Obj: TObject; Cls: TClass): Boolean;
// The class among Obj's ancestors named like Cls (the target's TControl...)
function TargetClass(Obj: TObject; Cls: TClass): TClass;

// False, with a message, when the VCL of Ctrl doesn't have this inspector's
// layout: the target was built with another Delphi version
function CheckTarget(Ctrl: TControl; out Error: string): Boolean;

// The VCL control of Wnd, or nil. Check it with CheckTarget before use.
function FindTargetControl(Wnd: HWND): TWinControl;
// The VCL control of Wnd or of its nearest parent window that has one
function WindowControl(Wnd: HWND): TWinControl;
// The target's forms (in the no-packages inspectors, all parentless windowed
// controls) that pass CheckTarget
function TargetForms: TArray<TWinControl>;
// GetParentForm(Ctrl, True)
function TopParentForm(Ctrl: TControl): TCustomForm;

function ModuleOf(Address: Pointer): HMODULE;

// The current exception's message, also for exceptions that the target's
// code raised: their classes are not the inspector's Exception
function ExceptionMessage: string;
// The same with the exception's class name: "EClass: message"
function ExceptionText: string;

// False when the target must not keep memory that the inspector allocates:
// in a no-packages inspector that doesn't share the target's memory manager
function TargetMayKeepOurMemory: Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.TypInfo, System.Generics.Collections, VclSpy.MemoryManager;

var
  FOwnVcl: Boolean;

function OwnVcl: Boolean;
begin
  Result := FOwnVcl;
end;

function TargetClass(Obj: TObject; Cls: TClass): TClass;
var
  Name: string;
begin
  Result := Obj.ClassType;
  if Obj.InheritsFrom(Cls) then
  begin
    while Result <> Cls do
      Result := Result.ClassParent;
    Exit;
  end;
  Name := Cls.ClassName;
  while (Result <> nil) and not Result.ClassNameIs(Name) do
    Result := Result.ClassParent;
end;

function IsKindOf(Obj: TObject; Cls: TClass): Boolean;
begin
  if Obj = nil then
    Result := False
  else if Obj.InheritsFrom(Cls) then
    Result := True
  else
    Result := FOwnVcl and (TargetClass(Obj, Cls) <> nil);
end;

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

// True if P points to a Delphi object: its class's vmtSelfPtr points back
function LooksLikeObject(P: Pointer): Boolean;
var
  Vmt: PByte;
begin
  try
    Vmt := PPointer(P)^;
    Result := (Vmt <> nil) and (PPointer(Vmt + vmtSelfPtr)^ = Vmt);
  except
    Result := False;
  end;
end;

function FindTargetControl(Wnd: HWND): TWinControl;
var
  Atom: TAtom;
  Pid: DWORD;
  P: Pointer;
begin
  if not FOwnVcl then
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

function TargetForms: TArray<TWinControl>;
var
  List: TList<TWinControl>;
  I: Integer;
begin
  if not FOwnVcl then
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

function TopParentForm(Ctrl: TControl): TCustomForm;
begin
  while Ctrl.Parent <> nil do
    Ctrl := Ctrl.Parent;
  if IsKindOf(Ctrl, TCustomForm) then
    Result := TCustomForm(Ctrl)
  else
    Result := nil;
end;

function ModuleOf(Address: Pointer): HMODULE;
var
  Info: TMemoryBasicInformation;
begin
  if (Address = nil) or (VirtualQuery(Address, Info, SizeOf(Info)) = 0) or (Info.Type_9 <> MEM_IMAGE) then
    Result := 0
  else
    Result := HMODULE(Info.AllocationBase);
end;

function ExceptionMessage: string;
var
  Obj: TObject;
begin
  Obj := ExceptObject;
  if Obj = nil then
    Result := 'unknown exception'
  else if IsKindOf(Obj, Exception) then
    // The target's Exception has the same layout
    Result := Exception(Obj).Message
  else
    Result := Obj.ClassName;
end;

function ExceptionText: string;
var
  Obj: TObject;
begin
  Obj := ExceptObject;
  if (Obj <> nil) and IsKindOf(Obj, Exception) then
    Result := Obj.ClassName + ': ' + ExceptionMessage
  else
    Result := ExceptionMessage;
end;

function TargetMayKeepOurMemory: Boolean;
begin
  Result := MemoryManagerMode <> mmGuarded;
end;

initialization
  FOwnVcl := FindClassHInstance(TControl) = HInstance;
end.
