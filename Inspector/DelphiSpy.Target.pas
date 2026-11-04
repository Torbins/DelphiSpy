unit DelphiSpy.Target;

{ Tells the target's objects apart, for every kind of inspector DLL.

  The package inspectors (DelphiSpyInspectNNN.dll for the VCL, and
  DelphiSpyInspectFmxNNN.dll for FireMonkey) share the target's rtl package:
  the target's objects are instances of the inspector's own RTL classes, so
  "is" works for TComponent, TCollection, TStrings... The VCL inspectors share
  the vcl package too.

  The no-packages inspectors (DelphiSpyInspectNoPkgNNN.dll and
  DelphiSpyInspectFmxNoPkgNNN.dll) link the RTL (and the VCL) statically, as the
  target does. Built by the same Delphi version, the target's objects have the
  layout of the inspector's classes, so their fields, RTTI, virtual methods
  and static methods work, but their classes are the target's own. So classes
  are compared by name (IsKindOf).

  The FMX inspectors don't link FireMonkey at all: they reach the target's FMX
  objects through RTTI, and their classes by name (AncestorNamed).

  DelphiSpy.Server links the inspector into the target itself, which then works
  like a package inspector: the RTL it sees is its own. }

interface

uses
  Winapi.Windows;

// True in the no-packages inspectors: they have an RTL of their own
function OwnRtl: Boolean;

// Obj is Cls; in the no-packages inspectors also when it inherits from a
// class of the same name
function IsKindOf(Obj: TObject; Cls: TClass): Boolean;
// The class among Obj's ancestors named like Cls (the target's TComponent...)
function TargetClass(Obj: TObject; Cls: TClass): TClass;
// The class among Obj's ancestors named Name, or nil: for classes of a
// framework that the inspector doesn't link
function AncestorNamed(Obj: TObject; const Name: string): TClass;
function IsKindOfName(Obj: TObject; const Name: string): Boolean;

// False, with a message, when the target's RTL doesn't have this inspector's
// layout: Obj's TComponent has another size or other published properties
function CheckRtl(Obj: TObject; out Error: string): Boolean;

// True if P points to a Delphi object: its class's vmtSelfPtr points back
function LooksLikeObject(P: Pointer): Boolean;

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
  System.SysUtils, System.Classes, System.TypInfo, DelphiSpy.MemoryManager;

var
  FOwnRtl: Boolean;

function OwnRtl: Boolean;
begin
  Result := FOwnRtl;
end;

function AncestorNamed(Obj: TObject; const Name: string): TClass;
begin
  if Obj = nil then
    Exit(nil);
  Result := Obj.ClassType;
  while (Result <> nil) and not Result.ClassNameIs(Name) do
    Result := Result.ClassParent;
end;

function IsKindOfName(Obj: TObject; const Name: string): Boolean;
begin
  Result := AncestorNamed(Obj, Name) <> nil;
end;

function TargetClass(Obj: TObject; Cls: TClass): TClass;
begin
  Result := Obj.ClassType;
  if Obj.InheritsFrom(Cls) then
  begin
    while Result <> Cls do
      Result := Result.ClassParent;
    Exit;
  end;
  Result := AncestorNamed(Obj, Cls.ClassName);
end;

function IsKindOf(Obj: TObject; Cls: TClass): Boolean;
begin
  if Obj = nil then
    Result := False
  else if Obj.InheritsFrom(Cls) then
    Result := True
  else
    Result := FOwnRtl and (TargetClass(Obj, Cls) <> nil);
end;

function CheckRtl(Obj: TObject; out Error: string): Boolean;
var
  Target: TClass;
  Size, Props: Integer;
begin
  Target := TargetClass(Obj, TComponent);
  if Target = nil then
  begin
    Error := Format('%s is not a component: it doesn''t inherit from TComponent.', [Obj.ClassName]);
    Exit(False);
  end;
  if not FOwnRtl and (Target <> TComponent) then
  begin
    Error := Format('%s belongs to a module with an RTL of its own (%s), not to the shared rtl package.',
      [Obj.ClassName, ExtractFileName(GetModuleName(ModuleOf(Target)))]);
    Exit(False);
  end;
  Size := Target.InstanceSize;
  Props := GetTypeData(Target.ClassInfo)^.PropCount;
  if (Size <> TComponent.InstanceSize) or (Props <> GetTypeData(TComponent.ClassInfo)^.PropCount) then
  begin
    Error := Format('The target''s RTL doesn''t match the inspector''s (Delphi %.1f): its TComponent has %d ' +
      'bytes and %d published properties, the inspector''s %d and %d. The target may be built with another ' +
      'Delphi version.', [CompilerVersion, Size, Props, TComponent.InstanceSize,
      GetTypeData(TComponent.ClassInfo)^.PropCount]);
    Exit(False);
  end;
  Result := True;
end;

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
  // A package that links the RTL: not the target's module, nor its packages
  FOwnRtl := ModuleIsPackage and (FindClassHInstance(TComponent) = HInstance);
end.
