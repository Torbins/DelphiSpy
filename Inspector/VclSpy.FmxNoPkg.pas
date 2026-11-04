unit VclSpy.FmxNoPkg;

{ Part of the no-packages FMX inspectors only, the counterpart of VclSpy.NoPkg.
  They are packages that contain the RTL themselves (no requires clause),
  built with the extension dll; the hook stub calls their Initialize after
  loading them.

  Unlike the VCL's, FireMonkey's application window is not destroyed while an
  exe ends (only when FMX runs in a DLL), so there is no moment before the
  exe frees its memory at which the inspector could finalize itself. It is
  never finalized, as when a VCL target ends without destroying its
  application window: the process ends with it still loaded. VclSpyActive
  tells the hook stub that it can always be called.

  When it is unloaded at the very end of the process, it unregisters its
  module, which touches the memory of its RTL. So unlike VclSpy.NoPkg it
  doesn't export VclSpyFinalizesEarly: VclSpy.MemoryManager doesn't use a
  memory manager that the exe shares (SimpleShareMem), which the exe frees
  before, but guards its own. }

interface

uses
  Winapi.Windows;

function VclSpyActive: BOOL; stdcall;

implementation

uses
  VclSpy.FmxInspector;

exports
  VclSpyInspect,
  VclSpyRequest,
  VclSpyProbe,
  VclSpyActive;

function VclSpyActive: BOOL; stdcall;
begin
  Result := True;
end;

end.
