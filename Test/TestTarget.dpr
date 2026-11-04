program TestTarget;

{ Target app for testing VclSpy. build.cmd builds it with runtime packages
  rtl;vcl for Delphi 10.4 and 11, x86 and x64, and without packages: plain,
  with ShareMem (SHAREMEM) and with SimpleShareMem (SIMPLESHAREMEM). With
  VCLSPY_SERVER it links VclSpy.Server, for inspecting it over the network. }

uses
{$IFDEF SHAREMEM}
  ShareMem,
{$ENDIF}
{$IFDEF SIMPLESHAREMEM}
  SimpleShareMem,
{$ENDIF}
{$IFDEF VCLSPY_SERVER}
  VclSpy.Server,
{$ENDIF}
  Vcl.Forms,
  TestMain in 'TestMain.pas' {frmTest},
  TestFrame in 'TestFrame.pas' {fraSample: TFrame};

begin
  Application.Initialize;
  Application.CreateForm(TfrmTest, frmTest);
  Application.Run;
end.
