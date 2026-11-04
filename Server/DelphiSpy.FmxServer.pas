unit DelphiSpy.FmxServer;

{ Lets DelphiSpy inspect this FireMonkey application from another computer of the
  local network. Add the unit to the uses clause of the application's .dpr
  (or of any of its units), with DelphiSpy's Server, Inspector and Common
  folders on the project's search path. Once the application's main message
  loop runs, an App Tethering server (DelphiSpy.ServerCore) starts that DelphiSpy
  finds with its Connect button.
  For VCL applications, use DelphiSpy.Server instead.

  The unit links DelphiSpy's FireMonkey inspector (DelphiSpy.FmxInspector) into the
  application, so nothing is injected: the inspector sees the application's
  own FireMonkey, with or without runtime packages, of any Delphi version it
  compiles with.

  Settings, made before Application.Run:
    DelphiSpyServerPassword  the password DelphiSpy must give; also the environment
                          variable DELPHISPY_PASSWORD
    DelphiSpyServerEnabled   False keeps the server from starting; also the
                          environment variable DELPHISPY_SERVER=0
  StartDelphiSpyServer and StopDelphiSpyServer start and stop it at any time.

  App Tethering uses UDP and TCP ports 2020-2039 (and TCP 2040-2110), which
  the firewall must let through. Anyone who reaches the application and
  knows the password can read and change its controls, and the traffic is
  not encrypted: keep this unit out of release builds (IFDEF DEBUG). }

interface

uses
  DelphiSpy.ServerCore;

var
  DelphiSpyServerEnabled: Boolean absolute DelphiSpy.ServerCore.ServerEnabled;
  DelphiSpyServerPassword: string absolute DelphiSpy.ServerCore.ServerPassword;

procedure StartDelphiSpyServer;
procedure StopDelphiSpyServer;
function DelphiSpyServerRunning: Boolean;

implementation

uses
  DelphiSpy.FmxInspector;

procedure StartDelphiSpyServer;
begin
  StartServer;
end;

procedure StopDelphiSpyServer;
begin
  StopServer;
end;

function DelphiSpyServerRunning: Boolean;
begin
  Result := ServerRunning;
end;

initialization
  InstallServer(RequestReply);
end.
