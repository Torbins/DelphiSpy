program TestTarget;

{ Target app for testing DelphiSpy. build.cmd builds it with runtime packages
  rtl;vcl for Delphi 10.4 and 11, x86 and x64, and without packages: plain,
  with ShareMem (SHAREMEM) and with SimpleShareMem (SIMPLESHAREMEM). With
  DELPHISPY_SERVER it links DelphiSpy.Server, for inspecting it over the network. }

uses
{$IFDEF SHAREMEM}
  ShareMem,
{$ENDIF}
{$IFDEF SIMPLESHAREMEM}
  SimpleShareMem,
{$ENDIF}
{$IFDEF DELPHISPY_SERVER}
  DelphiSpy.Server,
{$ENDIF}
  Vcl.Forms,
  TestMain in 'TestMain.pas' {frmTest},
  TestFrame in 'TestFrame.pas' {fraSample: TFrame};

begin
  Application.Initialize;
  Application.CreateForm(TfrmTest, frmTest);
  Application.Run;
end.
