library DelphiSpyInspectFmx280;

{ Inspector for FireMonkey targets built with Delphi 11 runtime packages
  (fmx280.bpl). Build with Delphi 11 and the runtime package rtl only (see
  build.cmd): the inspector reaches the target's FMX objects through RTTI and
  links no FMX unit (DelphiSpy.FmxInspector). }

{$IF CompilerVersion <> 35}
  {$MESSAGE FATAL 'DelphiSpyInspectFmx280 must be built with Delphi 11 (rtl280).'}
{$IFEND}

uses
  DelphiSpy.Protocol in '..\Common\DelphiSpy.Protocol.pas',
  DelphiSpy.MemoryManager in 'DelphiSpy.MemoryManager.pas',
  DelphiSpy.Target in 'DelphiSpy.Target.pas',
  DelphiSpy.Properties in 'DelphiSpy.Properties.pas',
  DelphiSpy.Members in 'DelphiSpy.Members.pas',
  DelphiSpy.Report in 'DelphiSpy.Report.pas',
  DelphiSpy.FmxInspector in 'DelphiSpy.FmxInspector.pas';

exports
  DelphiSpyInspect,
  DelphiSpyRequest;

begin
end.
