program FmxTestTarget;

{ FireMonkey target app for testing VclSpy. build.cmd builds it with runtime
  packages rtl;fmx for Delphi 10.4 and 11, and without packages: plain, with
  ShareMem (SHAREMEM) and with SimpleShareMem (SIMPLESHAREMEM). With
  VCLSPY_SERVER it links VclSpy.FmxServer, for inspecting it over the
  network. }

uses
{$IFDEF SHAREMEM}
  ShareMem,
{$ENDIF}
{$IFDEF SIMPLESHAREMEM}
  SimpleShareMem,
{$ENDIF}
{$IFDEF VCLSPY_SERVER}
  VclSpy.FmxServer,
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
