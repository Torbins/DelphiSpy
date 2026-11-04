program DelphiSpy;

{ Drag the finder onto a control of a Delphi VCL or FireMonkey app; DelphiSpy
  injects an inspector into that process and shows the control's name,
  class, owner/parent paths, properties and event handlers, and can change
  simple properties of the control. Connect... inspects an application on
  another computer that links DelphiSpy.Server (DelphiSpy.FmxServer).
  Built as Win32 with Delphi 11, without runtime packages (see build.cmd). }

uses
  Vcl.Forms,
  DelphiSpy.Protocol in '..\Common\DelphiSpy.Protocol.pas',
  DelphiSpy.RemoteClient in '..\Common\DelphiSpy.RemoteClient.pas',
  Finder in 'Finder.pas',
  InjectRunner in 'InjectRunner.pas',
  MainForm in 'MainForm.pas' {frmMain},
  PropEditor in 'PropEditor.pas' {frmPropEditor},
  ConnectForm in 'ConnectForm.pas' {frmConnect};

// Common controls v6 and Per-Monitor V2 DPI awareness; built by build.cmd
{$R DelphiSpyManifest.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'DelphiSpy';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
