unit VclSpy.SelfFinalize;

{ Part of the no-packages inspectors only (VclSpy.NoPkg, VclSpy.FmxNoPkg).
  They are packages that contain the RTL themselves (no requires clause),
  built with the extension dll. Unlike a DLL's, the units of a package are
  not initialized and finalized by its DllMain, but by its exports
  Initialize and Finalize. The hook stub calls Initialize after loading the
  inspector; this unit calls Finalize when the target ends, while the
  target's memory manager still works. That matters when the inspector
  shares it (SimpleShareMem): the exe frees all of its memory later, and the
  inspector would touch that memory when it is unloaded at the very end of
  the process. When the process ends otherwise (Halt before any window
  closed, ExitProcess), the inspector is not finalized.

  The target ends:
  - VCL: when its TApplication window gets WM_DESTROY, at the end of
    TApplication.Destroy.
  - Without such a window (FireMonkey destroys none when an exe ends): when
    the last window of the GUI thread closes. Each visible top-level window
    is watched (subclassed). Whenever one of them is shown, hidden, activated
    or destroyed, and whenever the inspector is called, the visible windows
    are looked up first, and those not watched yet are watched too, so the
    window that closes last is watched, whichever it is. Not watched are
    windows without area, minimized ones, and the frameworks' application
    windows (TFMAppClass, TApplication). The target ends when the last
    watched window is destroyed, or when none of them is visible and no
    window of the thread is minimized: a minimized FMX application hides
    its forms and minimizes its application window instead, and may be
    closed so, from the taskbar.
    This is a guess: an application that hides all its windows (to the
    notification area) would seem to end. So the windows are watched only
    when the inspector shares the exe's memory manager (VclSpy.MemoryManager,
    mmShared), the one case that needs it. Otherwise not finalizing is
    harmless: the inspector touches only memory of its own, or of
    borlndmm.dll, when it is unloaded.

  A request that hides the last window itself (Visible = False) must not
  finalize the inspector under its own feet: while the inspector runs
  (EnterCall, LeaveCall), finalizing waits until it returns, and doesn't
  happen if a window is visible again by then.

  After Finalize the inspector stays loaded but must not be called any more;
  VclSpyActive tells the hook stub. The window procedure goes on forwarding
  for windows that were subclassed again since: it uses nothing of the RTL,
  and the list of windows is static. }

interface

uses
  Winapi.Windows;

function VclSpyActive: BOOL; stdcall;
// Tells VclSpy.MemoryManager that it may use the memory manager that the exe
// shares (SimpleShareMem): the inspector finalizes itself before the exe
// frees it
procedure VclSpyFinalizesEarly; stdcall;

// Around each call of the inspector's exports
procedure EnterCall;
procedure LeaveCall;

implementation

uses
  Winapi.Messages, VclSpy.Protocol, VclSpy.MemoryManager;

type
  TWatched = record
    Wnd: HWND;
    OldProc: Pointer;
  end;

  PWindowHandle = ^HWND;

  TClassName = array[0..15] of Char;

const
  MaxWatched = 256;

var
  Finalized, Pending: Boolean;
  Calls: Integer;
  // The target's TApplication window (VCL), or 0: then the visible windows
  // are watched
  AppWnd: HWND;
  AppGone: Boolean;
  // Without it, whether the visible windows are watched
  WatchesWindows: Boolean;
  Watched: array[0..MaxWatched - 1] of TWatched;
  WatchedCount: Integer;

function VclSpyActive: BOOL; stdcall;
begin
  Result := not Finalized;
end;

procedure VclSpyFinalizesEarly; stdcall;
begin
end;

{ Watched windows }

function WatchWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall; forward;

function IndexOfWatched(Wnd: HWND): Integer;
var
  I: Integer;
begin
  for I := 0 to WatchedCount - 1 do
    if Watched[I].Wnd = Wnd then
      Exit(I);
  Result := -1;
end;

procedure Watch(Wnd: HWND);
begin
  if (IndexOfWatched(Wnd) >= 0) or (WatchedCount = MaxWatched) then
    Exit;
  Watched[WatchedCount].Wnd := Wnd;
  Watched[WatchedCount].OldProc := Pointer(GetWindowLongPtr(Wnd, GWLP_WNDPROC));
  Inc(WatchedCount);
  SetWindowLongPtr(Wnd, GWLP_WNDPROC, LONG_PTR(@WatchWndProc));
end;

procedure Remove(Index: Integer);
begin
  Dec(WatchedCount);
  Watched[Index] := Watched[WatchedCount];
end;

// Restores the window procedure, unless the window was subclassed again
// since: then it stays watched, and forwarded to
function Unwatch(Index: Integer): Boolean;
begin
  Result := Pointer(GetWindowLongPtr(Watched[Index].Wnd, GWLP_WNDPROC)) = @WatchWndProc;
  if Result then
  begin
    SetWindowLongPtr(Watched[Index].Wnd, GWLP_WNDPROC, LONG_PTR(Watched[Index].OldProc));
    Remove(Index);
  end;
end;

procedure UnwatchAll;
var
  I: Integer;
begin
  I := 0;
  while I < WatchedCount do
    if not Unwatch(I) then
      Inc(I);
end;

function IsClass(Wnd: HWND; const Name: PChar): Boolean;
var
  Buffer: TClassName;
begin
  Result := (GetClassName(Wnd, Buffer, Length(Buffer)) > 0) and (lstrcmp(Buffer, Name) = 0);
end;

// Visible, with an area, not minimized, and not an application window
function IsWatchable(Wnd: HWND): Boolean;
var
  R: TRect;
begin
  Result := IsWindowVisible(Wnd) and not IsIconic(Wnd) and GetWindowRect(Wnd, R) and (R.Right > R.Left) and
    (R.Bottom > R.Top) and not IsClass(Wnd, 'TFMAppClass') and not IsClass(Wnd, 'TApplication');
end;

function WatchWindow(Wnd: HWND; Data: LPARAM): BOOL; stdcall;
begin
  if IsWatchable(Wnd) then
    Watch(Wnd);
  Result := True;
end;

// Watches the visible windows of the GUI thread that aren't yet
procedure WatchVisibleWindows;
begin
  EnumThreadWindows(GetCurrentThreadId, @WatchWindow, 0);
end;

function FindMinimized(Wnd: HWND; Found: PBoolean): BOOL; stdcall;
begin
  if IsWindowVisible(Wnd) and IsIconic(Wnd) then
    Found^ := True;
  Result := not Found^;
end;

function AnyMinimized: Boolean;
begin
  Result := False;
  EnumThreadWindows(GetCurrentThreadId, @FindMinimized, LPARAM(@Result));
end;

// Whether the target ends: the last watched window is gone, or none is
// visible and the application isn't minimized. Skip is a window being
// destroyed.
function NoWindowsLeft(Skip: HWND): Boolean;
var
  I: Integer;
  Exists, Visible: Boolean;
begin
  WatchVisibleWindows;
  Exists := False;
  Visible := False;
  for I := 0 to WatchedCount - 1 do
    if (Watched[I].Wnd <> Skip) and IsWindow(Watched[I].Wnd) then
    begin
      Exists := True;
      if IsWindowVisible(Watched[I].Wnd) then
        Visible := True;
    end;
  Result := not Exists or (not Visible and not AnyMinimized);
end;

{ Finalizing }

procedure FinalizeNow;
var
  Finalize: TVclSpyPackageProc;
begin
  Finalized := True;
  Pending := False;
  UnwatchAll;
  @Finalize := GetProcAddress(HInstance, PChar(VclSpyFinalizeExport));
  try
    Finalize;
    if AppWnd <> 0 then
      OutputDebugString('VclSpy: the inspector finalized itself with the application window')
    else
      OutputDebugString('VclSpy: the inspector finalized itself with the last visible window');
  except
    // Not into the target's message dispatch
  end;
end;

// The target ends: unless the inspector runs (it hid the last window itself)
procedure TargetEnds;
begin
  if Calls > 0 then
    Pending := True
  else
    FinalizeNow;
end;

procedure EnterCall;
begin
  Inc(Calls);
  if not Finalized and WatchesWindows then
    WatchVisibleWindows;
end;

procedure LeaveCall;
begin
  Dec(Calls);
  if (Calls = 0) and Pending and not Finalized then
    if AppGone or (WatchesWindows and NoWindowsLeft(0)) then
      FinalizeNow
    else
      Pending := False;
end;

function IsHiding(Msg: UINT; LParam: LPARAM): Boolean;
begin
  Result := (Msg = WM_WINDOWPOSCHANGED) and (PWindowPos(LParam)^.flags and SWP_HIDEWINDOW <> 0);
end;

function WatchWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  I: Integer;
  Skip: HWND;
begin
  I := IndexOfWatched(Wnd);
  if I < 0 then
    Exit(DefWindowProc(Wnd, Msg, WParam, LParam));
  // Windows shown since are watched before this one may close
  if not Finalized and WatchesWindows and ((Msg = WM_WINDOWPOSCHANGED) or (Msg = WM_SHOWWINDOW) or
    (Msg = WM_ACTIVATE) or (Msg = WM_DESTROY)) then
    WatchVisibleWindows;
  Result := CallWindowProc(Watched[I].OldProc, Wnd, Msg, WParam, LParam);

  // The list may have changed meanwhile
  if Msg = WM_NCDESTROY then
  begin
    I := IndexOfWatched(Wnd);
    if I >= 0 then
      Remove(I);
  end;
  if Finalized then
    Exit;
  if AppWnd <> 0 then
  begin
    if (Wnd = AppWnd) and (Msg = WM_DESTROY) then
    begin
      AppGone := True;
      TargetEnds;
    end;
  end
  else if WatchesWindows and ((Msg = WM_DESTROY) or IsHiding(Msg, LParam)) then
  begin
    if Msg = WM_DESTROY then
      Skip := Wnd
    else
      Skip := 0;
    if NoWindowsLeft(Skip) then
      TargetEnds;
  end;
end;

function FindAppWindow(Wnd: HWND; Found: PWindowHandle): BOOL; stdcall;
begin
  Result := not IsClass(Wnd, 'TApplication');
  if not Result then
    Found^ := Wnd;
end;

initialization
  // The target's TApplication window, on the GUI thread that the hook stub
  // runs on. This inspector's own VCL creates none (IsLibrary).
  EnumThreadWindows(GetCurrentThreadId, @FindAppWindow, LPARAM(@AppWnd));
  if AppWnd <> 0 then
    Watch(AppWnd)
  else if MemoryManagerMode = mmShared then
  begin
    WatchesWindows := True;
    WatchVisibleWindows;
  end;
finalization
  // The hook stub finalizes and unloads an inspector of another Delphi version
  Finalized := True;
  UnwatchAll;
end.
