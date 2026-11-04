library VclSpyInspect280;

{ Inspector for targets built with Delphi 11 runtime packages (rtl280/vcl280).
  Build with Delphi 11 and runtime packages rtl;vcl only (see build.cmd). }

{$IF CompilerVersion <> 35}
  {$MESSAGE FATAL 'VclSpyInspect280 must be built with Delphi 11 (rtl280/vcl280).'}
{$IFEND}

uses
  VclSpy.Protocol in '..\Common\VclSpy.Protocol.pas',
  VclSpy.MemoryManager in 'VclSpy.MemoryManager.pas',
  VclSpy.Target in 'VclSpy.Target.pas',
  VclSpy.Properties in 'VclSpy.Properties.pas',
  VclSpy.Inspector in 'VclSpy.Inspector.pas';

exports
  VclSpyInspect,
  VclSpyRequest;

begin
end.
