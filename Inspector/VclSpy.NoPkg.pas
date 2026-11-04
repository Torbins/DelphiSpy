unit VclSpy.NoPkg;

{ Part of the no-packages inspectors only. They are packages that contain the
  RTL and VCL themselves (no requires clause), built with the extension dll.
  Unlike a DLL's, the units of a package are not initialized and finalized by
  its DllMain, but by its exports Initialize and Finalize:

  - The hook stub calls Initialize after loading the inspector.
  - Finalize runs when the target's application window is destroyed, at the
    end of TApplication.Destroy, while the target's memory manager still
    works. That matters when the inspector shares it (SimpleShareMem): the
    exe frees all of its memory later, before a DLL would be finalized.
  - When the process ends otherwise, the inspector is not finalized at all.

  After Finalize the inspector stays loaded but must not be called any more;
  VclSpyActive tells the hook stub. }

interface

uses
  Winapi.Windows;

function VclSpyActive: BOOL; stdcall;
// Tells VclSpy.MemoryManager that it may use the memory manager that the exe
// shares (SimpleShareMem): the inspector finalizes itself before the exe
// frees it
procedure VclSpyFinalizesEarly; stdcall;

implementation

uses
  Winapi.Messages, VclSpy.Protocol, VclSpy.Inspector;

exports
  VclSpyInspect,
  VclSpyRequest,
  VclSpyProbe,
  VclSpyActive,
  VclSpyFinalizesEarly;

var
  Finalized: Boolean;
  AppWnd: HWND;
  OldWndProc: Pointer;

type
  PWindowHandle = ^HWND;

function VclSpyActive: BOOL; stdcall;
begin
  Result := not Finalized;
end;

procedure VclSpyFinalizesEarly; stdcall;
begin
end;

function AppWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Finalize: procedure;
begin
  Result := CallWindowProc(OldWndProc, Wnd, Msg, WParam, LParam);
  if (Msg = WM_DESTROY) and not Finalized then
  begin
    // Unless the window was subclassed again since
    if Pointer(GetWindowLongPtr(Wnd, GWLP_WNDPROC)) = @AppWndProc then
      SetWindowLongPtr(Wnd, GWLP_WNDPROC, LONG_PTR(OldWndProc));
    AppWnd := 0;
    Finalized := True;
    @Finalize := GetProcAddress(HInstance, PChar(VclSpyFinalizeExport));
    try
      Finalize;
      OutputDebugString('VclSpy: the inspector finalized itself with the application window');
    except
      // Not into the target's message dispatch
    end;
  end;
end;

function FindAppWindow(Wnd: HWND; Found: PWindowHandle): BOOL; stdcall;
var
  Name: array[0..15] of Char;
begin
  Result := not ((GetClassName(Wnd, Name, Length(Name)) > 0) and (lstrcmp(Name, 'TApplication') = 0));
  if not Result then
    Found^ := Wnd;
end;

initialization
  // The target's TApplication window, on the GUI thread that the hook stub
  // runs on. This inspector's own VCL creates none (IsLibrary).
  EnumThreadWindows(GetCurrentThreadId, @FindAppWindow, LPARAM(@AppWnd));
  if AppWnd <> 0 then
    OldWndProc := Pointer(SetWindowLongPtr(AppWnd, GWLP_WNDPROC, LONG_PTR(@AppWndProc)));
finalization
  // The hook stub finalizes and unloads an inspector of another Delphi version
  if (AppWnd <> 0) and (Pointer(GetWindowLongPtr(AppWnd, GWLP_WNDPROC)) = @AppWndProc) then
    SetWindowLongPtr(AppWnd, GWLP_WNDPROC, LONG_PTR(OldWndProc));
  Finalized := True;
end.
