library DelphiSpyInspect270;

{ Inspector for targets built with Delphi 10.4 runtime packages (rtl270/vcl270).
  Build with Delphi 10.4 and runtime packages rtl;vcl only (see build.cmd). }

{$IF CompilerVersion <> 34}
  {$MESSAGE FATAL 'DelphiSpyInspect270 must be built with Delphi 10.4 (rtl270/vcl270).'}
{$IFEND}

uses
  DelphiSpy.Protocol in '..\Common\DelphiSpy.Protocol.pas',
  DelphiSpy.MemoryManager in 'DelphiSpy.MemoryManager.pas',
  DelphiSpy.Target in 'DelphiSpy.Target.pas',
  DelphiSpy.Properties in 'DelphiSpy.Properties.pas',
  DelphiSpy.Members in 'DelphiSpy.Members.pas',
  DelphiSpy.Report in 'DelphiSpy.Report.pas',
  DelphiSpy.VclProperties in 'DelphiSpy.VclProperties.pas',
  DelphiSpy.Inspector in 'DelphiSpy.Inspector.pas';

exports
  DelphiSpyInspect,
  DelphiSpyRequest;

begin
end.
