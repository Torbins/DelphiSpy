library VclSpyInspectFmx280;

{ Inspector for FireMonkey targets built with Delphi 11 runtime packages
  (fmx280.bpl). Build with Delphi 11 and the runtime package rtl only (see
  build.cmd): the inspector reaches the target's FMX objects through RTTI and
  links no FMX unit (VclSpy.FmxInspector). }

{$IF CompilerVersion <> 35}
  {$MESSAGE FATAL 'VclSpyInspectFmx280 must be built with Delphi 11 (rtl280).'}
{$IFEND}

uses
  VclSpy.Protocol in '..\Common\VclSpy.Protocol.pas',
  VclSpy.MemoryManager in 'VclSpy.MemoryManager.pas',
  VclSpy.Target in 'VclSpy.Target.pas',
  VclSpy.Properties in 'VclSpy.Properties.pas',
  VclSpy.Members in 'VclSpy.Members.pas',
  VclSpy.Report in 'VclSpy.Report.pas',
  VclSpy.FmxInspector in 'VclSpy.FmxInspector.pas';

exports
  VclSpyInspect,
  VclSpyRequest;

begin
end.
