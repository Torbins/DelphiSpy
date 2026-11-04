unit VclSpy.RemoteClient;

{ VclSpy's side of VclSpy.Server: finds the applications on the network that
  link it, connects to one, and sends it requests (see VclSpy.Protocol). All
  methods block until they are done, so the VclSpy UI calls them on threads of
  their own. The tethering events don't synchronize with the main thread;
  they signal the waiting method instead. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  System.Tether.Manager, System.Tether.AppProfile;

type
  TRemoteServer = record
    ManagerId: string;
    // "TestTarget.exe, PID 1234, COMPUTER"
    Description: string;
    // "192.168.1.20:2020"
    Address: string;
    function Caption: string;
  end;

  ERemoteError = class(Exception);

  TRemoteClient = class
  private
    FManager: TTetheringManager;
    FProfile: TTetheringAppProfile;
    FLock: TObject;
    FManagersFound, FProfilesFound: TEvent;
    FFound: TArray<TTetheringManagerInfo>;
    FServerProfiles: TArray<TTetheringProfileInfo>;
    FAuthFailed: Boolean;
    FPassword: string;
    FConnected: Boolean;
    FServer: TRemoteServer;
    FServerManager: TTetheringManagerInfo;
    FServerProfile: TTetheringProfileInfo;
    FReplies: TDictionary<string, string>;
    FNextId: Integer;
    FOnDisconnected: TProc;
    procedure EndManagersDiscovery(const Sender: TObject; const ARemoteManagers: TTetheringManagerInfoList);
    procedure EndProfilesDiscovery(const Sender: TObject; const ARemoteProfiles: TTetheringProfileInfoList);
    procedure RequestManagerPassword(const Sender: TObject; const ARemoteIdentifier: string; var Password: string);
    procedure AuthError(const Sender: TObject; const AManagerIdentifier: string);
    procedure ResourceReceived(const Sender: TObject; const AResource: TRemoteResource);
    procedure RemoteManagerShutdown(const Sender: TObject; const AManagerIdentifier: string);
    procedure ProfileDisconnected(const Sender: TObject; const AProfileInfo: TTetheringProfileInfo);
    procedure ServerGone;
    function FindManager(const ManagerId: string; out Info: TTetheringManagerInfo): Boolean;
    function IsPaired(const ManagerId: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    // Targets: host names or IPv4 addresses separated by ";" or ",", an
    // address ending in .0 for its whole /24 network, or '' for every network
    // this computer is on (UDP broadcast).
    function Discover(const Targets: string; Timeout: Cardinal): TArray<TRemoteServer>;
    // A server that the last Discover found. Raises ERemoteError.
    procedure Connect(const Server: TRemoteServer; const Password: string; Timeout: Cardinal);
    procedure Disconnect;
    // A request as for VclSpyRequest; returns the reply, or an
    // {"ok":false,...} error object
    function Request(const Json: string; Timeout: Cardinal): string;
    property Connected: Boolean read FConnected;
    property Server: TRemoteServer read FServer;
    // Called on a tethering thread when the server closes the connection
    property OnDisconnected: TProc read FOnDisconnected write FOnDisconnected;
  end;

function RemoteErrorJson(const Msg: string): string;

implementation

uses
  System.JSON,
  // The network adapter's implementation, as the IDE adds for TTetheringManager
  IPPeerClient, IPPeerServer,
  VclSpy.Protocol;

function RemoteErrorJson(const Msg: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('ok', TJSONBool.Create(False));
    Obj.AddPair('error', Msg);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

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

{ TRemoteServer }

function TRemoteServer.Caption: string;
begin
  Result := Format('%s   (%s)', [Description, Address]);
end;

{ TRemoteClient }

constructor TRemoteClient.Create;
begin
  inherited;
  FLock := TObject.Create;
  FManagersFound := TEvent.Create(nil, True, False, '');
  FProfilesFound := TEvent.Create(nil, True, False, '');
  FReplies := TDictionary<string, string>.Create;
  FManager := TTetheringManager.Create(nil);
  FManager.AllowedAdapters := 'Network';
  FManager.Text := VclSpyClientText;
  FManager.SynchronizeEvents := False;
  FManager.OnEndManagersDiscovery := EndManagersDiscovery;
  FManager.OnEndProfilesDiscovery := EndProfilesDiscovery;
  FManager.OnRequestManagerPassword := RequestManagerPassword;
  FManager.OnAuthErrorFromRemote := AuthError;
  FManager.OnAuthErrorFromLocal := AuthError;
  FManager.OnRemoteManagerShutdown := RemoteManagerShutdown;
  FProfile := TTetheringAppProfile.Create(nil);
  FProfile.Group := VclSpyProfileGroup + '.client';
  FProfile.Text := VclSpyClientText;
  FProfile.SynchronizeEvents := False;
  FProfile.OnResourceReceived := ResourceReceived;
  FProfile.OnDisconnect := ProfileDisconnected;
  // Starts listening: the server connects back to send its replies
  FProfile.Manager := FManager;
end;

destructor TRemoteClient.Destroy;
begin
  Disconnect;
  FProfile.Free;
  FManager.Free;
  FReplies.Free;
  FProfilesFound.Free;
  FManagersFound.Free;
  FLock.Free;
  inherited;
end;

procedure TRemoteClient.EndManagersDiscovery(const Sender: TObject; const ARemoteManagers: TTetheringManagerInfoList);
begin
  TMonitor.Enter(FLock);
  try
    FFound := ARemoteManagers.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;
  FManagersFound.SetEvent;
end;

procedure TRemoteClient.EndProfilesDiscovery(const Sender: TObject; const ARemoteProfiles: TTetheringProfileInfoList);
begin
  TMonitor.Enter(FLock);
  try
    FServerProfiles := ARemoteProfiles.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;
  FProfilesFound.SetEvent;
end;

procedure TRemoteClient.RequestManagerPassword(const Sender: TObject; const ARemoteIdentifier: string;
  var Password: string);
begin
  Password := FPassword;
end;

procedure TRemoteClient.AuthError(const Sender: TObject; const AManagerIdentifier: string);
begin
  FAuthFailed := True;
  FProfilesFound.SetEvent;
end;

procedure TRemoteClient.ResourceReceived(const Sender: TObject; const AResource: TRemoteResource);
var
  Id: string;
begin
  if not AResource.Hint.StartsWith(VclSpyReplyDescription) then
    Exit;
  Id := AResource.Hint.Substring(Length(VclSpyReplyDescription));
  TMonitor.Enter(FReplies);
  try
    FReplies.AddOrSetValue(Id, ResourceText(AResource));
    TMonitor.PulseAll(FReplies);
  finally
    TMonitor.Exit(FReplies);
  end;
end;

procedure TRemoteClient.ServerGone;
begin
  if not FConnected then
    Exit;
  FConnected := False;
  if Assigned(FOnDisconnected) then
    FOnDisconnected;
end;

procedure TRemoteClient.RemoteManagerShutdown(const Sender: TObject; const AManagerIdentifier: string);
begin
  if AManagerIdentifier = FServerManager.ManagerIdentifier then
    ServerGone;
end;

procedure TRemoteClient.ProfileDisconnected(const Sender: TObject; const AProfileInfo: TTetheringProfileInfo);
begin
  if AProfileInfo.ProfileIdentifier = FServerProfile.ProfileIdentifier then
    ServerGone;
end;

function TRemoteClient.Discover(const Targets: string; Timeout: Cardinal): TArray<TRemoteServer>;
var
  Hosts: TArray<string>;
  Info: TTetheringManagerInfo;
  Server: TRemoteServer;
  I: Integer;
begin
  Hosts := Targets.Split([';', ',', ' '], TStringSplitOptions.ExcludeEmpty);
  for I := 0 to High(Hosts) do
    Hosts[I] := Hosts[I].Trim;
  FManagersFound.ResetEvent;
  FManager.DiscoverManagers(Timeout, TTetheringTargetHosts(Hosts));
  // The event comes after the timeout
  if FManagersFound.WaitFor(Timeout + 5000) <> wrSignaled then
    raise ERemoteError.Create('The network discovery did not finish.');
  Result := nil;
  TMonitor.Enter(FLock);
  try
    for Info in FFound do
      if Info.ManagerText.StartsWith(VclSpyServerTextPrefix) then
      begin
        Server.ManagerId := Info.ManagerIdentifier;
        Server.Description := Info.ManagerText.Substring(Length(VclSpyServerTextPrefix));
        // "192.168.1.20$2020"
        Server.Address := Info.ConnectionString.Replace('$', ':');
        Result := Result + [Server];
      end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TRemoteClient.FindManager(const ManagerId: string; out Info: TTetheringManagerInfo): Boolean;
var
  Found: TTetheringManagerInfo;
begin
  TMonitor.Enter(FLock);
  try
    for Found in FFound do
      if Found.ManagerIdentifier = ManagerId then
      begin
        Info := Found;
        Exit(True);
      end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := False;
end;

function TRemoteClient.IsPaired(const ManagerId: string): Boolean;
var
  Info: TTetheringManagerInfo;
begin
  for Info in FManager.PairedManagers do
    if Info.ManagerIdentifier = ManagerId then
      Exit(True);
  Result := False;
end;

procedure TRemoteClient.Connect(const Server: TRemoteServer; const Password: string; Timeout: Cardinal);
var
  Info: TTetheringManagerInfo;
  Profile: TTetheringProfileInfo;
  Found: Boolean;
begin
  Disconnect;
  if not FindManager(Server.ManagerId, Info) then
    raise ERemoteError.CreateFmt('%s is no longer on the list; search again.', [Server.Caption]);
  FPassword := Password;
  FAuthFailed := False;
  FProfilesFound.ResetEvent;
  // Disconnect unpairs it again
  FServerManager := Info;
  try
    // Pairing discovers the server's profiles; a paired manager is asked again
    if IsPaired(Info.ManagerIdentifier) then
      FManager.DiscoverProfiles(Info, Timeout)
    else
      FManager.PairManager(Info, Timeout);
    if FProfilesFound.WaitFor(Timeout + 5000) <> wrSignaled then
      raise ERemoteError.CreateFmt('%s did not answer.', [Server.Caption]);
    if FAuthFailed then
      if Password = '' then
        raise ERemoteError.CreateFmt('%s requires a password.', [Server.Caption])
      else
        raise ERemoteError.CreateFmt('%s refused the password.', [Server.Caption]);

    Found := False;
    TMonitor.Enter(FLock);
    try
      for Profile in FServerProfiles do
        if (Profile.ManagerIdentifier = Info.ManagerIdentifier) and (Profile.ProfileGroup = VclSpyProfileGroup) then
        begin
          FServerProfile := Profile;
          Found := True;
          Break;
        end;
    finally
      TMonitor.Exit(FLock);
    end;
    if not Found then
      raise ERemoteError.CreateFmt('%s has no VclSpy server profile.', [Server.Caption]);
    if not FProfile.Connect(FServerProfile, Timeout) then
      raise ERemoteError.CreateFmt('Cannot connect to %s.', [Server.Caption]);
  except
    Disconnect;
    raise;
  end;
  FServer := Server;
  FConnected := True;
end;

procedure TRemoteClient.Disconnect;
var
  Info: TTetheringManagerInfo;
begin
  Info := FServerManager;
  FServerManager := Default(TTetheringManagerInfo);
  if Info.ManagerIdentifier = '' then
    Exit;
  // The server may be gone already
  try
    if FConnected then
    begin
      FConnected := False;
      FProfile.Disconnect(FServerProfile);
    end;
  except
  end;
  try
    if IsPaired(Info.ManagerIdentifier) then
      FManager.UnPairManager(Info);
  except
  end;
end;

function TRemoteClient.Request(const Json: string; Timeout: Cardinal): string;
var
  Value: TJSONValue;
  Id, Text: string;
  Start: TDateTime;
  Remaining: Int64;
begin
  if not FConnected then
    Exit(RemoteErrorJson('Not connected to a VclSpy server.'));
  Value := TJSONObject.ParseJSONValue(Json);
  try
    if not (Value is TJSONObject) then
      Exit(RemoteErrorJson('The request is not a JSON object.'));
    Id := IntToStr(AtomicIncrement(FNextId));
    TJSONObject(Value).AddPair('id', Id);
    TJSONObject(Value).AddPair('replyTo', FProfile.Identifier);
    Text := Value.ToJSON;
  finally
    Value.Free;
  end;

  try
    if not FProfile.SendLongString(FServerProfile, VclSpyRequestDescription, Text) then
      Exit(RemoteErrorJson(Format('Sending the request to %s failed.', [FServer.Caption])));
  except
    on E: Exception do
      Exit(RemoteErrorJson(Format('Sending the request to %s failed: %s', [FServer.Caption, E.Message])));
  end;

  Start := Now;
  TMonitor.Enter(FReplies);
  try
    while not FReplies.TryGetValue(Id, Result) do
    begin
      Remaining := Int64(Timeout) - Round((Now - Start) * MSecsPerDay);
      if (Remaining <= 0) or not TMonitor.Wait(FReplies, Remaining) then
        // The server connects back to send the reply
        Exit(RemoteErrorJson(Format('%s did not reply within %d ms. It may be busy, hung or gone, or ' +
          'a firewall on this computer blocks it from connecting back to %s.',
          [FServer.Caption, Timeout, ExtractFileName(ParamStr(0))])));
    end;
    FReplies.Remove(Id);
  finally
    TMonitor.Exit(FReplies);
  end;
end;

end.
