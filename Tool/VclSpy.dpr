program VclSpy;

{ Drag the finder onto a control of a Delphi VCL app built with runtime
  packages; VclSpy injects an inspector into that process and shows the
  control's name, class, owner/parent paths, properties and event handlers.
  Built as Win32 with Delphi 11, without runtime packages (see build.cmd). }

uses
  Vcl.Forms,
  VclSpy.Protocol in '..\Common\VclSpy.Protocol.pas',
  Finder in 'Finder.pas',
  InjectRunner in 'InjectRunner.pas',
  MainForm in 'MainForm.pas' {frmMain};

// Common controls v6 and Per-Monitor V2 DPI awareness; built by build.cmd
{$R VclSpyManifest.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'VclSpy';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
