library VclSpyHook;

{ Hook stub that SetWindowsHookEx loads into the target process. It is built
  without runtime packages and without SysUtils, so it can load into any
  process. On a VclSpy query or request it loads the inspector DLL that
  matches the target's VCL package version and calls it on the target's GUI
  thread. }

uses
  Winapi.Windows,
  Winapi.Messages,
  VclSpy.Protocol in '..\Common\VclSpy.Protocol.pas';

var
  QueryMsg, RequestMsg: UINT;

function IntToStr(Value: Integer): string;
var
  S: ShortString;
begin
  Str(Value, S);
  Result := string(S);
end;

function ModuleDir: string;
var
  Buffer: array[0..MAX_PATH] of Char;
  I: Integer;
begin
  SetString(Result, Buffer, GetModuleFileName(HInstance, Buffer, Length(Buffer)));
  I := Length(Result);
  while (I > 0) and (Result[I] <> '\') do
    Dec(I);
  SetLength(Result, I);
end;

function JsonEscape(const S: string): string;
const
  Hex: array[0..15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #0..#31: Result := Result + '\u00' + Hex[Ord(S[I]) shr 4] + Hex[Ord(S[I]) and $F];
    else
      Result := Result + S[I];
    end;
end;

procedure SendError(ReplyWnd: HWND; const Msg: string);
var
  Json: UTF8String;
  Data: TCopyDataStruct;
  Res: DWORD_PTR;
begin
  Json := UTF8String('{"ok":false,"error":"' + JsonEscape(Msg) + '"}');
  Data.dwData := VclSpyCopyDataMagic;
  Data.cbData := Length(Json);
  Data.lpData := PAnsiChar(Json);
  SendMessageTimeout(ReplyWnd, WM_COPYDATA, 0, LPARAM(@Data), SMTO_ABORTIFHUNG,
    VclSpyReplyTimeout, @Res);
end;

function FindLoadedPackage(const Prefix: string): string;
var
  I: Integer;
begin
  for I := Low(VclSpyPackageSuffixes) to High(VclSpyPackageSuffixes) do
    if GetModuleHandle(PChar(Prefix + VclSpyPackageSuffixes[I] + '.bpl')) <> 0 then
      Exit(VclSpyPackageSuffixes[I]);
  Result := '';
end;

// Loads the inspector DLL that matches the target's VCL package version and
// returns the address of one of its exports, or nil after sending an error.
function InspectorProc(ReplyWnd: HWND; const ExportName: string): Pointer;
var
  Suffix, Path: string;
  Lib: HMODULE;
  Err: DWORD;
begin
  Result := nil;
  Suffix := FindLoadedPackage('vcl');
  if Suffix = '' then
  begin
    Suffix := FindLoadedPackage('rtl');
    if Suffix <> '' then
      SendError(ReplyWnd, 'The target loads rtl' + Suffix + '.bpl but not vcl' + Suffix +
        '.bpl, so it is not a VCL application built with runtime packages.')
    else
      SendError(ReplyWnd, 'The target is not built with Delphi runtime packages ' +
        '(no vclNNN.bpl is loaded in the process).');
    Exit;
  end;

  Path := ModuleDir + VclSpyInspectDllPrefix + Suffix + '.dll';
  if GetFileAttributes(PChar(Path)) = INVALID_FILE_ATTRIBUTES then
  begin
    SendError(ReplyWnd, 'The target uses vcl' + Suffix + '.bpl, but ' + Path + ' does not exist.');
    Exit;
  end;

  // Stays loaded on purpose: unloading a package-based DLL from a live app is risky
  Lib := LoadLibrary(PChar(Path));
  if Lib = 0 then
  begin
    Err := GetLastError;
    SendError(ReplyWnd, 'Cannot load ' + Path + ' into the target (error ' + IntToStr(Err) + ').');
    Exit;
  end;

  Result := GetProcAddress(Lib, PChar(ExportName));
  if Result = nil then
    // An older inspector stays loaded until the target restarts
    SendError(ReplyWnd, Path + ' does not export ' + ExportName + '. If VclSpy was updated ' +
      'while the target was running, restart the target.');
end;

procedure HandleQuery(Wnd, ReplyWnd: HWND; Point: LPARAM);
var
  Inspect: TVclSpyInspectProc;
  X, Y: Integer;
begin
  @Inspect := InspectorProc(ReplyWnd, VclSpyInspectExport);
  if Assigned(Inspect) then
  begin
    UnpackPoint(Point, X, Y);
    Inspect(Wnd, X, Y, ReplyWnd);
  end;
end;

procedure HandleRequest(Wnd, ReplyWnd: HWND; Mapping: THandle);
var
  View: Pointer;
  Request: TVclSpyRequestProc;
begin
  try
    View := MapViewOfFile(Mapping, FILE_MAP_READ, 0, 0, 0);
    if View = nil then
    begin
      SendError(ReplyWnd, 'Cannot read the request (error ' + IntToStr(GetLastError) + ').');
      Exit;
    end;
    try
      @Request := InspectorProc(ReplyWnd, VclSpyRequestExport);
      if Assigned(Request) then
        Request(Wnd, PAnsiChar(View), ReplyWnd);
    finally
      UnmapViewOfFile(View);
    end;
  finally
    CloseHandle(Mapping);
  end;
end;

function CallWndProcHook(Code: Integer; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Msg: PCWPStruct;
begin
  if Code = HC_ACTION then
  begin
    if QueryMsg = 0 then
    begin
      QueryMsg := RegisterWindowMessage(VclSpyQueryMessageName);
      RequestMsg := RegisterWindowMessage(VclSpyRequestMessageName);
    end;
    Msg := PCWPStruct(LParam);
    if (Msg^.wParam <> 0) and ((Msg^.message = QueryMsg) or (Msg^.message = RequestMsg)) then
      try
        if Msg^.message = QueryMsg then
          HandleQuery(Msg^.hwnd, HWND(Msg^.wParam), Msg^.lParam)
        else
          HandleRequest(Msg^.hwnd, HWND(Msg^.wParam), THandle(Msg^.lParam));
      except
        // Never let anything escape into the target's message dispatch
      end;
  end;
  Result := CallNextHookEx(0, Code, WParam, LParam);
end;

exports
  CallWndProcHook name VclSpyHookExport;

begin
end.
