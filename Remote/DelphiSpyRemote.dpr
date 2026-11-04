program DelphiSpyRemote;

{ Command-line client for applications that link DelphiSpy.Server, the network
  counterpart of DelphiSpyInject.exe. Built as Win32.

  Usage: DelphiSpyRemote.exe --list [--hosts <hosts>] [--timeout <ms>]
         DelphiSpyRemote.exe --server <text> --request <file | -> [--hosts <hosts>]
                          [--password <password>] [--timeout <ms>]
  --list prints the servers found as a JSON array. --hosts names the hosts or
  IPv4 addresses to search, separated by ";" or ","; an address ending in .0
  searches its /24 network. Without it, every network of this computer is
  searched by broadcast. --server picks the server whose description or
  address contains <text> (or whose number in the list it is, from 1).
  --request sends each line of a UTF-8 file or of stdin as a request (see
  DelphiSpyRequest in Inspector\DelphiSpy.Inspector.pas, and ops "forms" and
  "pick"), and prints each reply on a line. Exit code 0 means every reply has
  "ok":true. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  DelphiSpy.Protocol in '..\Common\DelphiSpy.Protocol.pas',
  DelphiSpy.RemoteClient in '..\Common\DelphiSpy.RemoteClient.pas';

const
  DiscoveryTimeout = 3000;

function FindArg(const Name: string; out Value: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), '--' + Name) then
    begin
      Value := ParamStr(I + 1);
      Exit(True);
    end;
  Result := False;
end;

function HasFlag(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), '--' + Name) then
      Exit(True);
  Result := False;
end;

function ArgOr(const Name, Default: string): string;
begin
  if not FindArg(Name, Result) then
    Result := Default;
end;

function ReadInput(const Source: string): string;
var
  Input: THandle;
  Buffer: array[0..4095] of Byte;
  Count: DWORD;
  Bytes: TBytes;
begin
  if Source <> '-' then
    Bytes := TFile.ReadAllBytes(Source)
  else
  begin
    // stdin may be a pipe, which has no size to ask for
    Input := GetStdHandle(STD_INPUT_HANDLE);
    while ReadFile(Input, Buffer, SizeOf(Buffer), Count, nil) and (Count > 0) do
    begin
      SetLength(Bytes, Length(Bytes) + Integer(Count));
      Move(Buffer, Bytes[Length(Bytes) - Integer(Count)], Count);
    end;
  end;
  Result := TEncoding.UTF8.GetString(Bytes);
  if Result.StartsWith(#$FEFF) then
    Delete(Result, 1, 1);
end;

procedure WriteLine(const Text: string);
var
  Bytes: TBytes;
  Written: DWORD;
begin
  Bytes := TEncoding.UTF8.GetBytes(Text + sLineBreak);
  WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), Bytes[0], Length(Bytes), Written, nil);
end;

function ServersJson(const Servers: TArray<TRemoteServer>): string;
var
  List: TJSONArray;
  Item: TJSONObject;
  Server: TRemoteServer;
begin
  List := TJSONArray.Create;
  try
    for Server in Servers do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('description', Server.Description);
      Item.AddPair('address', Server.Address);
      List.AddElement(Item);
    end;
    Result := List.ToJSON;
  finally
    List.Free;
  end;
end;

function PickServer(const Servers: TArray<TRemoteServer>; const Text: string): TRemoteServer;
var
  Server: TRemoteServer;
  Index: Integer;
begin
  if TryStrToInt(Text, Index) and (Index >= 1) and (Index <= Length(Servers)) then
    Exit(Servers[Index - 1]);
  for Server in Servers do
    if Server.Description.ToLower.Contains(Text.ToLower) or Server.Address.Contains(Text) then
      Exit(Server);
  raise ERemoteError.CreateFmt('No DelphiSpy server matches "%s". Found: %s', [Text, ServersJson(Servers)]);
end;

var
  Client: TRemoteClient;
  Servers: TArray<TRemoteServer>;
  ServerText, Source, Line, Reply: string;
  Timeout: Cardinal;
  AllOk: Boolean;
begin
  AllOk := False;
  try
    Timeout := StrToIntDef(ArgOr('timeout', ''), DelphiSpyRemoteTimeout);
    if not HasFlag('list') and not (FindArg('server', ServerText) and FindArg('request', Source)) then
      raise EArgumentException.Create('Usage: DelphiSpyRemote.exe --list [--hosts <hosts>] [--timeout <ms>], or ' +
        'DelphiSpyRemote.exe --server <text> --request <file | -> [--hosts <hosts>] [--password <password>] ' +
        '[--timeout <ms>]');
    Client := TRemoteClient.Create;
    try
      Servers := Client.Discover(ArgOr('hosts', ''), DiscoveryTimeout);
      if HasFlag('list') then
      begin
        WriteLine(ServersJson(Servers));
        AllOk := Servers <> nil;
      end
      else
      begin
        Client.Connect(PickServer(Servers, ServerText), ArgOr('password', ''), Timeout);
        AllOk := True;
        for Line in ReadInput(Source).Split([#13, #10], TStringSplitOptions.ExcludeEmpty) do
          if Line.Trim <> '' then
          begin
            Reply := Client.Request(Line, Timeout);
            WriteLine(Reply);
            if not Reply.StartsWith('{"ok":true') then
              AllOk := False;
          end;
      end;
    finally
      Client.Free;
    end;
  except
    on E: Exception do
      WriteLine(RemoteErrorJson(E.Message));
  end;
  if AllOk then
    ExitCode := 0
  else
    ExitCode := 1;
end.
