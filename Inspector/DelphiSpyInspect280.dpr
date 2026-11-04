library DelphiSpyInspect280;

{ Inspector for targets built with Delphi 11 runtime packages (rtl280/vcl280).
  Build with Delphi 11 and runtime packages rtl;vcl only (see build.cmd). }

{$IF CompilerVersion <> 35}
  {$MESSAGE FATAL 'DelphiSpyInspect280 must be built with Delphi 11 (rtl280/vcl280).'}
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
