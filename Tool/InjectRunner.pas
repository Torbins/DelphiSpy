unit InjectRunner;

{ Starts the VclSpyInject.exe that matches the target's bitness on a
  background thread, optionally feeds it a request on stdin, and collects
  the JSON it writes to stdout. }

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Types;

type
  TInjectRunner = class(TThread)
  private
    FCommandLine: string;
    FInput: TBytes;
    FOutput: string;
  protected
    procedure Execute; override;
  public
    // OnDone runs on the main thread; read Output there. Input goes to the
    // injector's stdin (for --request -).
    constructor Create(const CommandLine: string; OnDone: TNotifyEvent); overload;
    constructor Create(const CommandLine: string; const Input: TBytes; OnDone: TNotifyEvent); overload;
    property Output: string read FOutput;
  end;

// Checks that VclSpy can inspect the process that owns Wnd and returns the
// full path of the injector to use, or raises with a user-readable reason.
function InjectorFor(Wnd: HWND): string;

function ErrorJson(const Msg: string): string;

implementation

uses
  System.JSON, VclSpy.Protocol;

{$WARN SYMBOL_PLATFORM OFF}

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;
  ProcessTimeout = 15000;

function ErrorJson(const Msg: string): string;
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

function IsTokenElevated(Token: THandle): Boolean;
var
  Elevation: TTokenElevation;
  Len: DWORD;
begin
  Result := GetTokenInformation(Token, TokenElevation, @Elevation, SizeOf(Elevation), Len) and
    (Elevation.TokenIsElevated <> 0);
end;

function IsSelfElevated: Boolean;
var
  Token: THandle;
begin
  Result := False;
  if OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    try
      Result := IsTokenElevated(Token);
    finally
      CloseHandle(Token);
    end;
end;

function InjectorFor(Wnd: HWND): string;
var
  Pid: DWORD;
  Process, Token: THandle;
  SelfWow, TargetWow: BOOL;
  Arch: string;
  Elevated: Boolean;
begin
  GetWindowThreadProcessId(Wnd, Pid);
  Process := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
  if Process = 0 then
    raise Exception.CreateFmt('Cannot open process %d: %s', [Pid, SysErrorMessage(GetLastError)]);
  try
    // VclSpy.exe is 32-bit: on 64-bit Windows it runs under WOW64 itself
    Arch := 'x86';
    if IsWow64Process(GetCurrentProcess, SelfWow) and SelfWow and
      IsWow64Process(Process, TargetWow) and not TargetWow then
      Arch := 'x64';

    if not IsSelfElevated then
    begin
      if OpenProcessToken(Process, TOKEN_QUERY, Token) then
        try
          Elevated := IsTokenElevated(Token);
        finally
          CloseHandle(Token);
        end
      else
        Elevated := GetLastError = ERROR_ACCESS_DENIED;
      if Elevated then
        raise Exception.CreateFmt('Process %d runs elevated. Restart VclSpy as administrator ' +
          'to inspect it.', [Pid]);
    end;
  finally
    CloseHandle(Process);
  end;

  Result := ExtractFilePath(ParamStr(0)) + Arch + '\' + VclSpyInjectExeName;
  if not FileExists(Result) then
    raise Exception.CreateFmt('%s is missing.', [Result]);
end;

{ TInjectRunner }

constructor TInjectRunner.Create(const CommandLine: string; OnDone: TNotifyEvent);
begin
  inherited Create(False);
  FCommandLine := CommandLine;
  FreeOnTerminate := True;
  OnTerminate := OnDone;
end;

constructor TInjectRunner.Create(const CommandLine: string; const Input: TBytes; OnDone: TNotifyEvent);
begin
  FInput := Input; // before the thread starts in the inherited constructor
  Create(CommandLine, OnDone);
end;

procedure TInjectRunner.Execute;
var
  Security: TSecurityAttributes;
  ReadPipe, WritePipe, InputRead, InputWrite: THandle;
  Startup: TStartupInfo;
  Info: TProcessInformation;
  Buffer: array[0..4095] of Byte;
  Count, Written: DWORD;
  Bytes: TBytesStream;
  Cmd: string;
begin
  try
    Security.nLength := SizeOf(Security);
    Security.lpSecurityDescriptor := nil;
    Security.bInheritHandle := True;
    Win32Check(CreatePipe(ReadPipe, WritePipe, @Security, 0));
    InputRead := 0;
    InputWrite := 0;
    Bytes := TBytesStream.Create;
    try
      SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
      Win32Check(CreatePipe(InputRead, InputWrite, @Security, 0));
      SetHandleInformation(InputWrite, HANDLE_FLAG_INHERIT, 0);
      FillChar(Startup, SizeOf(Startup), 0);
      Startup.cb := SizeOf(Startup);
      Startup.dwFlags := STARTF_USESTDHANDLES;
      Startup.hStdInput := InputRead;
      Startup.hStdOutput := WritePipe;
      Startup.hStdError := WritePipe;
      Cmd := FCommandLine;
      UniqueString(Cmd);
      Win32Check(CreateProcess(nil, PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil,
        Startup, Info));
      // Our copies of the child's pipe ends must go, or nobody sees end-of-file
      CloseHandle(WritePipe);
      WritePipe := 0;
      CloseHandle(InputRead);
      InputRead := 0;
      try
        // The injector reads all of stdin before it writes anything
        if FInput <> nil then
          WriteFile(InputWrite, FInput[0], Length(FInput), Written, nil);
        CloseHandle(InputWrite);
        InputWrite := 0;
        while ReadFile(ReadPipe, Buffer, SizeOf(Buffer), Count, nil) and (Count > 0) do
          Bytes.WriteBuffer(Buffer, Count);
        if WaitForSingleObject(Info.hProcess, ProcessTimeout) = WAIT_TIMEOUT then
          TerminateProcess(Info.hProcess, 1);
      finally
        CloseHandle(Info.hThread);
        CloseHandle(Info.hProcess);
      end;
      FOutput := TEncoding.UTF8.GetString(Bytes.Bytes, 0, Bytes.Size);
      if FOutput = '' then
        FOutput := ErrorJson(VclSpyInjectExeName + ' produced no output.');
    finally
      Bytes.Free;
      CloseHandle(ReadPipe);
      if WritePipe <> 0 then
        CloseHandle(WritePipe);
      if InputRead <> 0 then
        CloseHandle(InputRead);
      if InputWrite <> 0 then
        CloseHandle(InputWrite);
    end;
  except
    on E: Exception do
      FOutput := ErrorJson('Running ' + VclSpyInjectExeName + ' failed: ' + E.Message);
  end;
end;

end.
