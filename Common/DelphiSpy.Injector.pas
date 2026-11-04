unit DelphiSpy.Injector;

{ Gets DelphiSpyHook.dll into the process that owns a window and asks it to
  inspect the control at a screen point, or to carry out a JSON request
  (read or change a property). The caller must have the same bitness as the
  target. That is why DelphiSpyInject.exe ships as x86 and x64. }

interface

uses
  Winapi.Windows;

// Returns the inspector's UTF-8 JSON reply, or an {"ok":false,...} error object.
function InjectAndQuery(Wnd: HWND; X, Y: Integer; Timeout: Cardinal): RawByteString;

// Sends a UTF-8 JSON request to the inspector on the thread that owns Wnd and
// returns its UTF-8 JSON reply, or an {"ok":false,...} error object.
function InjectAndRequest(Wnd: HWND; const Request: RawByteString; Timeout: Cardinal): RawByteString;

function ErrorJson(const Msg: string): RawByteString;

implementation

uses
  Winapi.Messages, System.SysUtils, System.JSON,
  DelphiSpy.Protocol;

{$WARN SYMBOL_PLATFORM OFF}

const
  ReplyWindowClass = 'DelphiSpyInjectReply';
  MSGFLT_ALLOW = 1;
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

type
  TChangeWindowMessageFilterEx = function(Wnd: HWND; Msg: UINT; Action: DWORD;
    ChangeFilterStruct: Pointer): BOOL; stdcall;

var
  Reply: RawByteString;
  ReplyReceived: Boolean;

function ErrorJson(const Msg: string): RawByteString;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('ok', TJSONBool.Create(False));
    Obj.AddPair('error', TJSONString.Create(Msg));
    Result := UTF8Encode(Obj.ToJSON);
  finally
    Obj.Free;
  end;
end;

function ReplyWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Data: PCopyDataStruct;
begin
  if Msg = WM_COPYDATA then
  begin
    Data := PCopyDataStruct(LParam);
    if Data^.dwData = DelphiSpyCopyDataMagic then
    begin
      SetString(Reply, PAnsiChar(Data^.lpData), Data^.cbData);
      ReplyReceived := True;
      Exit(1);
    end;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

function CreateReplyWindow: HWND;
var
  WndClass: TWndClass;
  AllowMessage: TChangeWindowMessageFilterEx;
begin
  FillChar(WndClass, SizeOf(WndClass), 0);
  WndClass.lpfnWndProc := @ReplyWndProc;
  WndClass.hInstance := HInstance;
  WndClass.lpszClassName := ReplyWindowClass;
  Winapi.Windows.RegisterClass(WndClass);
  Result := CreateWindowEx(0, ReplyWindowClass, nil, 0, 0, 0, 0, 0, HWND_MESSAGE, 0, HInstance, nil);
  Win32Check(Result <> 0);
  // Lets a target with lower integrity than us send the reply
  @AllowMessage := GetProcAddress(GetModuleHandle(user32), 'ChangeWindowMessageFilterEx');
  if Assigned(AllowMessage) then
    AllowMessage(Result, WM_COPYDATA, MSGFLT_ALLOW, nil);
end;

function IsSameBitness(Pid: DWORD; out Message: string): Boolean;
var
  Process: THandle;
  SelfWow, TargetWow: BOOL;
begin
  Result := True;
  Process := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
  if Process = 0 then
    Exit; // can't tell; let the hook attempt report the real problem
  try
    if IsWow64Process(GetCurrentProcess, SelfWow) and IsWow64Process(Process, TargetWow) then
      Result := SelfWow = TargetWow;
  finally
    CloseHandle(Process);
  end;
  if not Result then
    if TargetWow then
      Message := 'The target is a 32-bit process; use x86\' + DelphiSpyInjectExeName + '.'
    else
      Message := 'The target is a 64-bit process; use x64\' + DelphiSpyInjectExeName + '.';
end;

// Checks that Wnd belongs to another process of our bitness
function CheckTarget(Wnd: HWND; out Pid, Tid: DWORD): string;
begin
  Result := '';
  if not IsWindow(Wnd) then
    Exit(Format('Window $%x does not exist.', [NativeUInt(Wnd)]));
  Tid := GetWindowThreadProcessId(Wnd, Pid);
  if Pid = GetCurrentProcessId then
    Exit('Cannot inspect a window of the injector itself.');
  IsSameBitness(Pid, Result);
end;

type
  // Called once the reply window exists, right before the message is sent
  TMakeLParam = reference to function(ReplyWnd: HWND; out Value: LPARAM; out Error: string): Boolean;

// Hooks the thread that owns Wnd and sends it Msg with the reply window in
// WParam. The inspector answers with WM_COPYDATA while we wait.
function Exchange(Wnd: HWND; Tid: DWORD; Msg: UINT; const MakeLParam: TMakeLParam;
  Timeout: Cardinal): RawByteString;
var
  Err: DWORD;
  HookLib: HMODULE;
  HookProc: Pointer;
  Hook: HHOOK;
  ReplyWnd: HWND;
  Res: DWORD_PTR;
  Value: LPARAM;
  Path, Error: string;
begin
  Path := ExtractFilePath(ParamStr(0)) + DelphiSpyHookDllName;
  HookLib := LoadLibrary(PChar(Path));
  if HookLib = 0 then
    Exit(ErrorJson(Format('Cannot load %s: %s', [Path, SysErrorMessage(GetLastError)])));
  try
    HookProc := GetProcAddress(HookLib, DelphiSpyHookExport);
    if HookProc = nil then
      Exit(ErrorJson(Format('%s does not export %s.', [Path, DelphiSpyHookExport])));

    ReplyWnd := CreateReplyWindow;
    try
      if not MakeLParam(ReplyWnd, Value, Error) then
        Exit(ErrorJson(Error));
      Hook := SetWindowsHookEx(WH_CALLWNDPROC, HookProc, HookLib, Tid);
      if Hook = 0 then
        Exit(ErrorJson('SetWindowsHookEx failed: ' + SysErrorMessage(GetLastError)));
      try
        Reply := '';
        ReplyReceived := False;
        // The inspector replies with WM_COPYDATA while we wait here; sent
        // messages to this thread are dispatched during SendMessageTimeout.
        if SendMessageTimeout(Wnd, Msg, WPARAM(ReplyWnd), Value, SMTO_NORMAL, Timeout, @Res) = 0 then
        begin
          Err := GetLastError;
          if not ReplyReceived then
            if Err = ERROR_TIMEOUT then
              Exit(ErrorJson(Format('The target did not respond within %d ms (is it busy or hung?).', [Timeout])))
            else if Err = ERROR_ACCESS_DENIED then
              Exit(ErrorJson('Access denied sending to the target. It probably runs elevated; ' +
                'start DelphiSpy as administrator.'))
            else
              Exit(ErrorJson('Sending the query failed: ' + SysErrorMessage(Err)));
        end;
        if not ReplyReceived then
          Exit(ErrorJson('No reply from the target. It may run elevated (start DelphiSpy as ' +
            'administrator), or security software may block the hook DLL.'));
        Result := Reply;
      finally
        UnhookWindowsHookEx(Hook);
        // Wakes the target thread so Windows can unload the hook stub
        PostMessage(Wnd, WM_NULL, 0, 0);
      end;
    finally
      DestroyWindow(ReplyWnd);
    end;
  finally
    FreeLibrary(HookLib);
  end;
end;

function InjectAndQuery(Wnd: HWND; X, Y: Integer; Timeout: Cardinal): RawByteString;
var
  Pid, Tid: DWORD;
  Msg: string;
begin
  Msg := CheckTarget(Wnd, Pid, Tid);
  if Msg <> '' then
    Exit(ErrorJson(Msg));
  Result := Exchange(Wnd, Tid, RegisterWindowMessage(DelphiSpyQueryMessageName),
    function(ReplyWnd: HWND; out Value: LPARAM; out Error: string): Boolean
    begin
      Value := PackPoint(X, Y);
      Result := True;
    end, Timeout);
end;

function InjectAndRequest(Wnd: HWND; const Request: RawByteString; Timeout: Cardinal): RawByteString;
var
  Pid, Tid: DWORD;
  Msg: string;
  Mapping, Process: THandle;
  View: Pointer;
begin
  Msg := CheckTarget(Wnd, Pid, Tid);
  if Msg <> '' then
    Exit(ErrorJson(Msg));

  // An unnamed mapping, handed to the target with DuplicateHandle: no named
  // object whose access rights would depend on elevation or integrity level
  Mapping := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, Length(Request) + 1, nil);
  if Mapping = 0 then
    Exit(ErrorJson('CreateFileMapping failed: ' + SysErrorMessage(GetLastError)));
  try
    View := MapViewOfFile(Mapping, FILE_MAP_WRITE, 0, 0, 0);
    if View = nil then
      Exit(ErrorJson('MapViewOfFile failed: ' + SysErrorMessage(GetLastError)));
    try
      // The view is zero-filled, so the request ends with #0
      if Request <> '' then
        Move(Request[1], View^, Length(Request));
    finally
      UnmapViewOfFile(View);
    end;

    Process := OpenProcess(PROCESS_DUP_HANDLE, False, Pid);
    if Process = 0 then
      Exit(ErrorJson(Format('Cannot open process %d: %s', [Pid, SysErrorMessage(GetLastError)])));
    try
      Result := Exchange(Wnd, Tid, RegisterWindowMessage(DelphiSpyRequestMessageName),
        function(ReplyWnd: HWND; out Value: LPARAM; out Error: string): Boolean
        var
          Remote: THandle;
        begin
          // The hook stub closes the duplicate. If the message never gets
          // there, one handle leaks in the target; closing it from here could
          // hit a reused handle value if the stub closed it late.
          Result := DuplicateHandle(GetCurrentProcess, Mapping, Process, @Remote, FILE_MAP_READ, False, 0);
          if Result then
            Value := LPARAM(Remote)
          else
            Error := 'DuplicateHandle failed: ' + SysErrorMessage(GetLastError);
        end, Timeout);
    finally
      CloseHandle(Process);
    end;
  finally
    CloseHandle(Mapping);
  end;
end;

end.
