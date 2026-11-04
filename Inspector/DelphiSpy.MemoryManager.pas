unit DelphiSpy.MemoryManager;

{ Makes the no-packages inspectors (DelphiSpyInspectNoPkgNNN.dll) use the
  target's memory manager where they can. Such an inspector has its own RTL,
  so strings that the target's code returns to it, and strings it hands to the
  target's code, cross between two memory managers unless they share one.

  This must be the first unit of the package, so that it runs before anything
  is allocated. It uses nothing but System for that reason. In order:

  - borlndmm.dll is loaded (the target uses ShareMem): use its functions, as
    ShareMem would.
  - Another module shares its memory manager (SimpleShareMem, FastMM's
    ShareMM): use that one. The exe frees all of its memory when it ends;
    DelphiSpy.SelfFinalize finalizes the inspector before that. An inspector
    that couldn't would touch that memory when it is unloaded at the very
    end of the process, so it would use the guard instead.
  - Otherwise keep the inspector's own memory manager, but guard it: blocks
    it allocates carry a mark, and blocks without it, the target's, are never
    freed by it (they leak), only copied when reallocated. The target can
    still free blocks of the inspector that it keeps; DelphiSpy.Properties
    avoids handing it any.

  The first two need the inspector's own memory manager unused so far; if it
  isn't, because some unit ran before this one, the guard is used.

  In the package inspectors this unit does nothing: the rtl package already
  gives them the target's memory manager. Nor where DelphiSpy.Server links the
  inspector into the target: it is the target's own memory manager. }

interface

type
  TMemoryManagerMode = (mmPackage, mmLinked, mmBorlndMM, mmShared, mmGuarded);

var
  MemoryManagerMode: TMemoryManagerMode;

function MemoryManagerText: string;

implementation

{$WARN SYMBOL_PLATFORM OFF}

type
  TMemoryBasicInformation = record
    BaseAddress, AllocationBase: Pointer;
    AllocationProtect: Cardinal;
    RegionSize: NativeUInt;
    State, Protect, Type_: Cardinal;
  end;

const
  BorlndMM = 'borlndmm.dll';
  // Exported by the inspectors that finalize themselves while the target's
  // memory manager still works (DelphiSpy.SelfFinalize)
  FinalizesEarlyExport = 'DelphiSpyFinalizesEarly';
  MEM_COMMIT = $1000;
  PAGE_NOACCESS = $01;
  PAGE_GUARD = $100;
  // Keeps the original memory manager's alignment (16 bytes on Win64)
  GuardSize = 16;
  GuardMagic = NativeUInt({$IFDEF WIN64}$5653475541524431{$ELSE}$56534731{$ENDIF});

function GetModuleHandle(lpModuleName: PChar): HMODULE; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleW';
function GetProcAddress(hModule: HMODULE; lpProcName: PAnsiChar): Pointer; stdcall;
  external 'kernel32.dll' name 'GetProcAddress';
function VirtualQuery(lpAddress: Pointer; var lpBuffer: TMemoryBasicInformation;
  dwLength: NativeUInt): NativeUInt; stdcall; external 'kernel32.dll' name 'VirtualQuery';

var
  Original: TMemoryManagerEx;

function MemoryManagerText: string;
begin
  case MemoryManagerMode of
    mmPackage: Result := 'rtl package';
    mmLinked: Result := 'the target''s own';
    mmBorlndMM: Result := BorlndMM;
    mmShared: Result := 'shared by the target';
  else
    Result := 'own, guarded';
  end;
end;

{ borlndmm.dll }

procedure CallBorlndMM(const Name: PAnsiChar);
var
  Proc: procedure;
begin
  Proc := GetProcAddress(GetModuleHandle(BorlndMM), Name);
  if Assigned(Proc) then
    Proc;
end;

// What ShareMem does, with the borlndmm.dll that the target loaded
function UseBorlndMM: Boolean;
var
  MM: HMODULE;
  Shared: TMemoryManagerEx;
begin
  MM := GetModuleHandle(BorlndMM);
  Result := MM <> 0;
  if not Result then
    Exit;
  Shared := Original;
  Shared.GetMem := GetProcAddress(MM, '@Borlndmm@SysGetMem$qqri');
  Shared.FreeMem := GetProcAddress(MM, '@Borlndmm@SysFreeMem$qqrpv');
  Shared.ReallocMem := GetProcAddress(MM, '@Borlndmm@SysReallocMem$qqrpvi');
  Shared.AllocMem := GetProcAddress(MM, '@Borlndmm@SysAllocMem$qqri');
  Shared.RegisterExpectedMemoryLeak := GetProcAddress(MM, '@Borlndmm@SysRegisterExpectedMemoryLeak$qqrpi');
  Shared.UnregisterExpectedMemoryLeak := GetProcAddress(MM, '@Borlndmm@SysUnregisterExpectedMemoryLeak$qqrpi');
  // borlndmm.dll of Delphi 2006 and later has all of them
  Result := Assigned(Shared.GetMem) and Assigned(Shared.FreeMem) and Assigned(Shared.ReallocMem) and
    Assigned(Shared.AllocMem) and Assigned(Shared.RegisterExpectedMemoryLeak) and
    Assigned(Shared.UnregisterExpectedMemoryLeak);
  if Result then
  begin
    CallBorlndMM('@Borlndmm@HeapAddRef$qqrv');
    SetMemoryManager(Shared);
  end;
end;

{ The guard }

function IsGuarded(P: Pointer): Boolean; inline;
begin
  Result := PNativeUInt(PByte(P) - SizeOf(NativeUInt))^ = NativeUInt(P) xor GuardMagic;
end;

function Mark(Block: Pointer): Pointer; inline;
begin
  Result := Block;
  if Result <> nil then
  begin
    Inc(PByte(Result), GuardSize);
    PNativeUInt(PByte(Result) - SizeOf(NativeUInt))^ := NativeUInt(Result) xor GuardMagic;
  end;
end;

// How many bytes from P on can be read without a fault
function ReadableSize(P: Pointer): NativeUInt;
var
  Info: TMemoryBasicInformation;
begin
  if (VirtualQuery(P, Info, SizeOf(Info)) = 0) or (Info.State <> MEM_COMMIT) or
    (Info.Protect and (PAGE_NOACCESS or PAGE_GUARD) <> 0) then
    Exit(0);
  Result := NativeUInt(Info.BaseAddress) + Info.RegionSize - NativeUInt(P);
end;

function GuardGetMem(Size: NativeInt): Pointer;
begin
  Result := Mark(Original.GetMem(Size + GuardSize));
end;

function GuardAllocMem(Size: NativeInt): Pointer;
begin
  Result := Mark(Original.AllocMem(Size + GuardSize));
end;

function GuardFreeMem(P: Pointer): Integer;
begin
  if not IsGuarded(P) then
    Exit(0); // the target's: leaked
  // A second FreeMem of the same pointer finds no mark
  PNativeUInt(PByte(P) - SizeOf(NativeUInt))^ := 0;
  Result := Original.FreeMem(PByte(P) - GuardSize);
end;

function GuardReallocMem(P: Pointer; Size: NativeInt): Pointer;
var
  Count: NativeUInt;
begin
  if IsGuarded(P) then
    Exit(Mark(Original.ReallocMem(PByte(P) - GuardSize, Size + GuardSize)));
  // The target's: its size is unknown, so copy as much as the new size, or
  // as much as can be read. Bytes past its end are as good as uninitialized.
  Result := GuardGetMem(Size);
  if Result <> nil then
  begin
    Count := ReadableSize(P);
    if Count > NativeUInt(Size) then
      Count := Size;
    Move(P^, Result^, Count);
  end;
end;

function GuardRegisterLeak(P: Pointer): Boolean;
begin
  Result := IsGuarded(P) and Original.RegisterExpectedMemoryLeak(PByte(P) - GuardSize);
end;

function GuardUnregisterLeak(P: Pointer): Boolean;
begin
  Result := IsGuarded(P) and Original.UnregisterExpectedMemoryLeak(PByte(P) - GuardSize);
end;

procedure UseGuard;
var
  Guard: TMemoryManagerEx;
begin
  Guard.GetMem := GuardGetMem;
  Guard.FreeMem := GuardFreeMem;
  Guard.ReallocMem := GuardReallocMem;
  Guard.AllocMem := GuardAllocMem;
  Guard.RegisterExpectedMemoryLeak := GuardRegisterLeak;
  Guard.UnregisterExpectedMemoryLeak := GuardUnregisterLeak;
  SetMemoryManager(Guard);
end;

// True if no block was allocated with the inspector's memory manager yet
function NothingAllocated: Boolean;
var
  State: TMemoryManagerState;
  I: Integer;
begin
  GetMemoryManagerState(State);
  Result := (State.AllocatedMediumBlockCount = 0) and (State.AllocatedLargeBlockCount = 0);
  for I := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    if State.SmallBlockTypeStates[I].AllocatedBlockCount <> 0 then
      Result := False;
end;

function FinalizesEarly: Boolean;
begin
  Result := GetProcAddress(HInstance, FinalizesEarlyExport) <> nil;
end;

// With runtime packages, System is in the rtl package, not in this module
function SystemInThisModule: Boolean;
var
  Info: TMemoryBasicInformation;
begin
  Result := (VirtualQuery(@IsMultiThread, Info, SizeOf(Info)) <> 0) and
    (Info.AllocationBase = Pointer(HInstance));
end;

initialization
  if not SystemInThisModule then
    MemoryManagerMode := mmPackage
  else if not ModuleIsPackage then
    // An exe or DLL that links the inspector (DelphiSpy.Server): the target itself
    MemoryManagerMode := mmLinked
  else
  begin
    // A package that contains System is not a library to it, but the VCL must
    // treat it as one (no TApplication window of its own)
    IsLibrary := True;
    GetMemoryManager(Original);
    if NothingAllocated and UseBorlndMM then
      MemoryManagerMode := mmBorlndMM
    else if NothingAllocated and FinalizesEarly and AttemptToUseSharedMemoryManager then
      MemoryManagerMode := mmShared
    else
    begin
      UseGuard;
      MemoryManagerMode := mmGuarded;
    end;
  end;
finalization
  if MemoryManagerMode = mmBorlndMM then
    CallBorlndMM('@Borlndmm@HeapRelease$qqrv');
end.
