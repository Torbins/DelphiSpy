library VclSpyHook;

{ Hook stub that SetWindowsHookEx loads into the target process. It is built
  without runtime packages and without SysUtils, so it can load into any
  process. On a VclSpy query or request it loads the inspector DLL that
  matches the target's VCL package version and calls it on the target's GUI
  thread. A target without a VCL package gets a no-packages inspector, the
  one built with the target's Delphi version. FireMonkey forms get the FMX
  inspectors instead, picked the same way by the fmxNNN.bpl loaded. }

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

function HexStr(Value: Cardinal): string;
const
  Hex: array[0..15] of Char = '0123456789ABCDEF';
var
  I: Integer;
begin
  SetLength(Result, 8);
  for I := 8 downto 1 do
  begin
    Result[I] := Hex[Value and $F];
    Value := Value shr 4;
  end;
end;

function ModulePath(Module: HMODULE): string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  SetString(Result, Buffer, GetModuleFileName(Module, Buffer, Length(Buffer)));
end;

function ModuleDir: string;
var
  I: Integer;
begin
  Result := ModulePath(HInstance);
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

// True if Wnd or a parent window belongs to a VCL control of any module:
// Vcl.Controls gives each window it creates the property 'Delphi' + process id
function IsVclWindow(Wnd: HWND): Boolean;
var
  Name: string;
begin
  Name := 'Delphi' + HexStr(GetCurrentProcessId);
  while Wnd <> 0 do
  begin
    if GetProp(Wnd, PChar(Name)) <> 0 then
      Exit(True);
    Wnd := GetParent(Wnd);
  end;
  Result := False;
end;

// True if Wnd or a parent window is a FireMonkey form: FMX gives the window
// of each form the property 'FIREMONKEY' + process id
function IsFmxWindow(Wnd: HWND): Boolean;
var
  Name: string;
begin
  Name := 'FIREMONKEY' + HexStr(GetCurrentProcessId);
  while Wnd <> 0 do
  begin
    if GetProp(Wnd, PChar(Name)) <> 0 then
      Exit(True);
    Wnd := GetParent(Wnd);
  end;
  Result := False;
end;

// Calls Initialize or Finalize of a no-packages inspector, a package
procedure CallPackageProc(Lib: HMODULE; const Name: string);
var
  Proc: TVclSpyPackageProc;
begin
  @Proc := GetProcAddress(Lib, PChar(Name));
  if Assigned(Proc) then
    Proc;
end;

// For a target without the framework's package: loads the no-packages
// inspector (Prefix: VclSpyInspectNoPkg or VclSpyInspectFmxNoPkg) of the
// target's Delphi version. That is the one an earlier pick loaded, or else
// the first, newest version first, whose probe accepts the control of Wnd.
// Returns 0 after sending an error.
function LoadNoPkgInspector(Wnd, ReplyWnd: HWND; const Prefix, Framework: string): HMODULE;
var
  I: Integer;
  Name, Path, Tried: string;
  Probe: TVclSpyProbeProc;
  Active: TVclSpyActiveProc;
  Err: DWORD;
begin
  for I := Low(VclSpyPackageSuffixes) to High(VclSpyPackageSuffixes) do
  begin
    Result := GetModuleHandle(PChar(Prefix + VclSpyPackageSuffixes[I] + '.dll'));
    if Result <> 0 then
    begin
      @Active := GetProcAddress(Result, PChar(VclSpyActiveExport));
      if Assigned(Active) and Active then
        Exit;
      SendError(ReplyWnd, 'The target is closing: its application window is gone, and the inspector ' +
        'finalized itself.');
      Exit(0);
    end;
  end;

  Tried := '';
  for I := Low(VclSpyPackageSuffixes) to High(VclSpyPackageSuffixes) do
  begin
    Name := Prefix + VclSpyPackageSuffixes[I] + '.dll';
    Path := ModuleDir + Name;
    if GetFileAttributes(PChar(Path)) = INVALID_FILE_ATTRIBUTES then
      Continue;
    Result := LoadLibrary(PChar(Path));
    if Result = 0 then
    begin
      Err := GetLastError;
      Tried := Tried + ', ' + Name + ' (cannot load it, error ' + IntToStr(Err) + ')';
      Continue;
    end;
    // Loading a package doesn't initialize its units
    CallPackageProc(Result, VclSpyInitializeExport);
    @Probe := GetProcAddress(Result, PChar(VclSpyProbeExport));
    // Stays loaded, like the package inspectors
    if Assigned(Probe) and Probe(Wnd) then
      Exit;
    // Another Delphi version. With its own RTL and VCL, it unloads cleanly.
    CallPackageProc(Result, VclSpyFinalizeExport);
    FreeLibrary(Result);
    Tried := Tried + ', ' + Name;
  end;

  if Tried = '' then
    SendError(ReplyWnd, 'The target is not built with Delphi runtime packages, and there is no ' +
      Prefix + 'NNN.dll in ' + ModuleDir + '.')
  else
    SendError(ReplyWnd, 'The target is not built with Delphi runtime packages, and no no-packages ' +
      'inspector matches its ' + Framework + ' (tried ' + Copy(Tried, 3, MaxInt) + '). It may be built ' +
      'with a Delphi version VclSpy does not support.');
  Result := 0;
end;

// Loads the inspector DLL that matches the target's VCL or FMX package
// version, or a no-packages inspector, and returns the address of one of its
// exports, or nil after sending an error.
function InspectorProc(Wnd, ReplyWnd: HWND; const ExportName: string): Pointer;
var
  Package, Prefix, NoPkgPrefix, Framework, Suffix, Path: string;
  Lib: HMODULE;
  Err: DWORD;
begin
  Result := nil;
  if IsFmxWindow(Wnd) then
  begin
    Package := 'fmx';
    Prefix := VclSpyFmxInspectDllPrefix;
    NoPkgPrefix := VclSpyFmxNoPkgDllPrefix;
    Framework := 'FireMonkey';
  end
  else
  begin
    Package := 'vcl';
    Prefix := VclSpyInspectDllPrefix;
    NoPkgPrefix := VclSpyNoPkgDllPrefix;
    Framework := 'VCL';
  end;
  Suffix := FindLoadedPackage(Package);
  if Suffix = '' then
  begin
    if (Package = 'vcl') and not IsVclWindow(Wnd) then
    begin
      SendError(ReplyWnd, 'The window is not a VCL control nor a FireMonkey form: the target loads no ' +
        'vclNNN.bpl, and the window has no property of a statically linked VCL or FireMonkey.');
      Exit;
    end;
    Lib := LoadNoPkgInspector(Wnd, ReplyWnd, NoPkgPrefix, Framework);
    if Lib = 0 then
      Exit;
    Path := ModulePath(Lib);
  end
  else
  begin
    Path := ModuleDir + Prefix + Suffix + '.dll';
    if GetFileAttributes(PChar(Path)) = INVALID_FILE_ATTRIBUTES then
    begin
      SendError(ReplyWnd, 'The target uses ' + Package + Suffix + '.bpl, but ' + Path + ' does not exist.');
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
  @Inspect := InspectorProc(Wnd, ReplyWnd, VclSpyInspectExport);
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
      @Request := InspectorProc(Wnd, ReplyWnd, VclSpyRequestExport);
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
