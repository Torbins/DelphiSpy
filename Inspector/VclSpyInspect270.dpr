library VclSpyInspect270;

{ Inspector for targets built with Delphi 10.4 runtime packages (rtl270/vcl270).
  Build with Delphi 10.4 and runtime packages rtl;vcl only (see build.cmd). }

{$IF CompilerVersion <> 34}
  {$MESSAGE FATAL 'VclSpyInspect270 must be built with Delphi 10.4 (rtl270/vcl270).'}
{$IFEND}

uses
  VclSpy.Protocol in '..\Common\VclSpy.Protocol.pas',
  VclSpy.MemoryManager in 'VclSpy.MemoryManager.pas',
  VclSpy.Target in 'VclSpy.Target.pas',
  VclSpy.Properties in 'VclSpy.Properties.pas',
  VclSpy.Members in 'VclSpy.Members.pas',
  VclSpy.Inspector in 'VclSpy.Inspector.pas';

exports
  VclSpyInspect,
  VclSpyRequest;

begin
end.
