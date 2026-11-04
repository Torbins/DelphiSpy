unit VclSpy.Server;

{ Lets VclSpy inspect this application from another computer of the local
  network. Add the unit to the uses clause of the application's .dpr (or of
  any of its units), with VclSpy's Server, Inspector and Common folders on the
  project's search path. Once the application's main message loop runs, an
  App Tethering server starts that VclSpy finds with its Connect button.

  The unit links VclSpy's inspector into the application, so nothing is
  injected: the inspector sees the application's own VCL, with or without
  runtime packages, of any Delphi version it compiles with.

  Settings, made before Application.Run:
    VclSpyServerPassword  the password VclSpy must give; also the environment
                          variable VCLSPY_PASSWORD
    VclSpyServerEnabled   False keeps the server from starting; also the
                          environment variable VCLSPY_SERVER=0
  StartVclSpyServer and StopVclSpyServer start and stop it at any time.

  App Tethering uses UDP and TCP ports 2020-2039 (and TCP 2040-2110), which
  the firewall must let through. Anyone who reaches the application and
  knows the password can read and change its controls, and the traffic is
  not encrypted: keep this unit out of release builds (IFDEF DEBUG).

  Requests run on the GUI thread, from the main message loop, as requests
  through VclSpy's hook do. Each reply is sent from a thread of its own (the
  server connects back to VclSpy for it), so a client that doesn't take its
  reply holds up no other. }

interface

var
  VclSpyServerEnabled: Boolean = True;
  VclSpyServerPassword: string;

procedure StartVclSpyServer;
procedure StopVclSpyServer;
function VclSpyServerRunning: Boolean;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.JSON,
  System.Tether.Manager, System.Tether.AppProfile,
  // The network adapter's implementation, as the IDE adds for TTetheringManager
  IPPeerClient, IPPeerServer,
  VclSpy.Protocol, VclSpy.Inspector;

type
  TServer = class
  private
    FManager: TTetheringManager;
    FProfile: TTetheringAppProfile;
    procedure ResourceReceived(const Sender: TObject; const AResource: TRemoteResource);
    procedure SendReply(const Client: TTetheringProfileInfo; const Description, Json: string);
    function FindClient(const Id: string; out Profile: TTetheringProfileInfo): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  Server: TServer;
  // Replies being sent. Not a field: the threads may outlive the server.
  Sending: Integer;

function ResourceText(Resource: TRemoteResource): string;
var
  Stream: TStream;
  Bytes: TBytes;
begin
  if Resource.ResType <> TRemoteResourceType.Stream then
    Exit(Resource.Value.AsString);
  Stream := Resource.Value.AsStream;
  Stream.Position := 0;
  SetLength(Bytes, Stream.Size);
  if Bytes <> nil then
    Stream.ReadBuffer(Bytes[0], Length(Bytes));
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function ComputerName: string;
begin
  Result := GetEnvironmentVariable('COMPUTERNAME');
end;

{ TServer }

constructor TServer.Create;
var
  Description: string;
begin
  inherited;
  Description := Format('%s, PID %d, %s', [ExtractFileName(ParamStr(0)), GetCurrentProcessId, ComputerName]);
  FManager := TTetheringManager.Create(nil);
  FManager.AllowedAdapters := 'Network';
  FManager.Text := VclSpyServerTextPrefix + Description;
  FManager.Password := VclSpyServerPassword;
  FProfile := TTetheringAppProfile.Create(nil);
  FProfile.Group := VclSpyProfileGroup;
  FProfile.Text := Description;
  FProfile.OnResourceReceived := ResourceReceived;
  // Starts listening
  FProfile.Manager := FManager;
end;

destructor TServer.Destroy;
var
  I: Integer;
begin
  // A reply that is still being sent uses the profile and the manager. If one
  // doesn't finish, they are left alone (the application is usually ending).
  for I := 1 to 30 do
    if Sending = 0 then
      Break
    else
      Sleep(100);
  if Sending = 0 then
  begin
    FProfile.Free;
    FManager.Free;
  end;
  inherited;
end;

function TServer.FindClient(const Id: string; out Profile: TTetheringProfileInfo): Boolean;
var
  Info: TTetheringProfileInfo;
begin
  for Info in FProfile.GetConnectedProfiles do
    if Info.ProfileIdentifier = Id then
    begin
      Profile := Info;
      Exit(True);
    end;
  for Info in FManager.RemoteProfiles do
    if Info.ProfileIdentifier = Id then
    begin
      Profile := Info;
      Exit(True);
    end;
  Result := False;
end;

// On the GUI thread (SynchronizeEvents)
procedure TServer.ResourceReceived(const Sender: TObject; const AResource: TRemoteResource);
var
  Text, Description: string;
  Value: TJSONValue;
  Client: TTetheringProfileInfo;
  Wnd: HWND;
  Pid: DWORD;
begin
  if AResource.Hint <> VclSpyRequestDescription then
    Exit;
  try
    Text := ResourceText(AResource);
    Value := TJSONObject.ParseJSONValue(Text);
    try
      if not (Value is TJSONObject) then
        Exit;
      if not FindClient(Value.GetValue<string>('replyTo', ''), Client) then
        Exit; // nobody to reply to
      Description := VclSpyReplyDescription + Value.GetValue<string>('id', '');
      // The window.hwnd of an earlier report, where the inspector looks for
      // the control first
      Wnd := HWND(Value.GetValue<Int64>('hwnd', 0));
      if (Wnd <> 0) and ((GetWindowThreadProcessId(Wnd, Pid) = 0) or (Pid <> GetCurrentProcessId)) then
        Wnd := 0;
    finally
      Value.Free;
    end;
    SendReply(Client, Description, RequestReply(Wnd, Text));
  except
    // Never into the tethering thread that synchronized this call
  end;
end;

procedure TServer.SendReply(const Client: TTetheringProfileInfo; const Description, Json: string);
var
  Profile: TTetheringAppProfile;
begin
  // Not Self: the thread may outlive it (see Destroy)
  Profile := FProfile;
  AtomicIncrement(Sending);
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        Profile.SendLongString(Client, Description, Json);
      except
        // The client is gone, or can't be reached; it times out
      end;
      AtomicDecrement(Sending);
    end).Start;
end;

{ Starting }

procedure StartVclSpyServer;
begin
  if Server = nil then
    Server := TServer.Create;
end;

procedure StopVclSpyServer;
begin
  FreeAndNil(Server);
end;

function VclSpyServerRunning: Boolean;
begin
  Result := Server <> nil;
end;

procedure StartWhenEnabled;
begin
  if GetEnvironmentVariable('VCLSPY_SERVER') = '0' then
    VclSpyServerEnabled := False;
  if VclSpyServerPassword = '' then
    VclSpyServerPassword := GetEnvironmentVariable('VCLSPY_PASSWORD');
  if VclSpyServerEnabled then
    try
      StartVclSpyServer;
    except
      on E: Exception do
        OutputDebugString(PChar('VclSpy: the server did not start: ' + E.Message));
    end;
end;

initialization
  LinkedInspectorName := 'VclSpy.Server';
  // Once the main message loop runs: the .dpr can change the settings first
  TThread.ForceQueue(nil, StartWhenEnabled);
finalization
  StopVclSpyServer;
end.
