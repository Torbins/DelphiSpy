unit VclSpy.Injector;

{ Gets VclSpyHook.dll into the process that owns a window and asks it to
  inspect the control at a screen point. The caller must have the same
  bitness as the target. That is why VclSpyInject.exe ships as x86 and x64. }

interface

uses
  Winapi.Windows;

// Returns the inspector's UTF-8 JSON reply, or an {"ok":false,...} error object.
function InjectAndQuery(Wnd: HWND; X, Y: Integer; Timeout: Cardinal): RawByteString;

function ErrorJson(const Msg: string): RawByteString;

implementation

uses
  Winapi.Messages, System.SysUtils, System.JSON,
  VclSpy.Protocol;

{$WARN SYMBOL_PLATFORM OFF}

const
  ReplyWindowClass = 'VclSpyInjectReply';
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
    if Data^.dwData = VclSpyCopyDataMagic then
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
      Message := 'The target is a 32-bit process; use x86\' + VclSpyInjectExeName + '.'
    else
      Message := 'The target is a 64-bit process; use x64\' + VclSpyInjectExeName + '.';
end;

function InjectAndQuery(Wnd: HWND; X, Y: Integer; Timeout: Cardinal): RawByteString;
var
  Pid, Tid, Err: DWORD;
  HookLib: HMODULE;
  HookProc: Pointer;
  Hook: HHOOK;
  ReplyWnd: HWND;
  Res: DWORD_PTR;
  Path, Msg: string;
begin
  if not IsWindow(Wnd) then
    Exit(ErrorJson(Format('Window $%x does not exist.', [NativeUInt(Wnd)])));
  Tid := GetWindowThreadProcessId(Wnd, Pid);
  if Pid = GetCurrentProcessId then
    Exit(ErrorJson('Cannot inspect a window of the injector itself.'));
  if not IsSameBitness(Pid, Msg) then
    Exit(ErrorJson(Msg));

  Path := ExtractFilePath(ParamStr(0)) + VclSpyHookDllName;
  HookLib := LoadLibrary(PChar(Path));
  if HookLib = 0 then
    Exit(ErrorJson(Format('Cannot load %s: %s', [Path, SysErrorMessage(GetLastError)])));
  try
    HookProc := GetProcAddress(HookLib, VclSpyHookExport);
    if HookProc = nil then
      Exit(ErrorJson(Format('%s does not export %s.', [Path, VclSpyHookExport])));

    ReplyWnd := CreateReplyWindow;
    try
      Hook := SetWindowsHookEx(WH_CALLWNDPROC, HookProc, HookLib, Tid);
      if Hook = 0 then
        Exit(ErrorJson('SetWindowsHookEx failed: ' + SysErrorMessage(GetLastError)));
      try
        Reply := '';
        ReplyReceived := False;
        // The inspector replies with WM_COPYDATA while we wait here; sent
        // messages to this thread are dispatched during SendMessageTimeout.
        if SendMessageTimeout(Wnd, RegisterWindowMessage(VclSpyQueryMessageName),
          WPARAM(ReplyWnd), PackPoint(X, Y), SMTO_NORMAL, Timeout, @Res) = 0 then
        begin
          Err := GetLastError;
          if not ReplyReceived then
            if Err = ERROR_TIMEOUT then
              Exit(ErrorJson(Format('The target did not respond within %d ms (is it busy or hung?).', [Timeout])))
            else if Err = ERROR_ACCESS_DENIED then
              Exit(ErrorJson('Access denied sending to the target. It probably runs elevated; ' +
                'start VclSpy as administrator.'))
            else
              Exit(ErrorJson('Sending the query failed: ' + SysErrorMessage(Err)));
        end;
        if not ReplyReceived then
          Exit(ErrorJson('No reply from the target. It may run elevated (start VclSpy as ' +
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

end.
