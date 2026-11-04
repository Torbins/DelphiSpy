library VclSpyInspectNoPkg270;

{ Inspector for Delphi 10.4 targets built without runtime packages, the fallback
  when the target loads no vcl270.bpl. Build with Delphi 10.4 and without runtime
  packages (see build.cmd): this DLL has its own VCL, and VclSpy.Target
  reaches the target's controls, which must be of the same Delphi version.
  VclSpy.MemoryManager must stay the first unit. }

{$IF CompilerVersion <> 34}
  {$MESSAGE FATAL 'VclSpyInspectNoPkg270 must be built with Delphi 10.4.'}
{$IFEND}

uses
  VclSpy.MemoryManager in 'VclSpy.MemoryManager.pas',
  VclSpy.Protocol in '..\Common\VclSpy.Protocol.pas',
  VclSpy.Target in 'VclSpy.Target.pas',
  VclSpy.Properties in 'VclSpy.Properties.pas',
  VclSpy.Inspector in 'VclSpy.Inspector.pas';

exports
  VclSpyInspect,
  VclSpyRequest,
  VclSpyProbe;

begin
end.
