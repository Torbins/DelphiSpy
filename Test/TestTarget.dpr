program TestTarget;

{ Target app for testing VclSpy. build.cmd builds it with runtime packages
  rtl;vcl for Delphi 10.4 and 11, x86 and x64, plus one variant without packages. }

uses
  Vcl.Forms,
  TestMain in 'TestMain.pas' {frmTest},
  TestFrame in 'TestFrame.pas' {fraSample: TFrame};

begin
  Application.Initialize;
  Application.CreateForm(TfrmTest, frmTest);
  Application.Run;
end.
