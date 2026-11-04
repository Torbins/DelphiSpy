program FmxTestTarget;

{ FireMonkey target app for testing DelphiSpy. build.cmd builds it with runtime
  packages rtl;fmx for Delphi 10.4 and 11, and without packages: plain, with
  ShareMem (SHAREMEM) and with SimpleShareMem (SIMPLESHAREMEM). With
  DELPHISPY_SERVER it links DelphiSpy.FmxServer, for inspecting it over the
  network. }

uses
{$IFDEF SHAREMEM}
  ShareMem,
{$ENDIF}
{$IFDEF SIMPLESHAREMEM}
  SimpleShareMem,
{$ENDIF}
{$IFDEF DELPHISPY_SERVER}
  DelphiSpy.FmxServer,
{$ENDIF}
  System.StartUpCopy,
  FMX.Forms,
  FmxTestMain in 'FmxTestMain.pas' {frmFmxTest},
  FmxTestFrame in 'FmxTestFrame.pas' {fraFmxSample: TFrame};

begin
  Application.Initialize;
  Application.CreateForm(TfrmFmxTest, frmFmxTest);
  Application.Run;
end.
