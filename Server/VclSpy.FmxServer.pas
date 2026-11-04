unit VclSpy.FmxServer;

{ Lets VclSpy inspect this FireMonkey application from another computer of the
  local network. Add the unit to the uses clause of the application's .dpr
  (or of any of its units), with VclSpy's Server, Inspector and Common
  folders on the project's search path. Once the application's main message
  loop runs, an App Tethering server (VclSpy.ServerCore) starts that VclSpy
  finds with its Connect button.
  For VCL applications, use VclSpy.Server instead.

  The unit links VclSpy's FireMonkey inspector (VclSpy.FmxInspector) into the
  application, so nothing is injected: the inspector sees the application's
  own FireMonkey, with or without runtime packages, of any Delphi version it
  compiles with.

  Settings, made before Application.Run:
    VclSpyServerPassword  the password VclSpy must give; also the environment
                          variable VCLSPY_PASSWORD
    VclSpyServerEnabled   False keeps the server from starting; also the
                          environment variable VCLSPY_SERVER=0
  StartVclSpyServer and StopVclSpyServer start and stop it at any time.

  App Tethering uses UDP and TCP ports 2020-2039 (and TCP 2040-2110), which
  the firewall must let through. Anyone who reaches the application and
  knows the password can read and change its controls, and the traffic is
  not encrypted: keep this unit out of release builds (IFDEF DEBUG). }

interface

uses
  VclSpy.ServerCore;

var
  VclSpyServerEnabled: Boolean absolute VclSpy.ServerCore.ServerEnabled;
  VclSpyServerPassword: string absolute VclSpy.ServerCore.ServerPassword;

procedure StartVclSpyServer;
procedure StopVclSpyServer;
function VclSpyServerRunning: Boolean;

implementation

uses
  VclSpy.FmxInspector;

procedure StartVclSpyServer;
begin
  StartServer;
end;

procedure StopVclSpyServer;
begin
  StopServer;
end;

function VclSpyServerRunning: Boolean;
begin
  Result := ServerRunning;
end;

initialization
  InstallServer(RequestReply);
end.
