unit VclSpy.FmxNoPkg;

{ Part of the no-packages FMX inspectors only: their exports, the
  counterpart of VclSpy.NoPkg. They are packages that contain the RTL
  themselves (no requires clause), built with the extension dll.

  FireMonkey destroys no window of its own when an exe ends (only in a DLL),
  so VclSpy.SelfFinalize finalizes them when the last visible window of the
  target is hidden or destroyed. The inspector's calls are wrapped, so that
  it isn't finalized while it runs. }

interface

implementation

uses
  Winapi.Windows, VclSpy.FmxInspector, VclSpy.SelfFinalize;

procedure Inspect(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
begin
  EnterCall;
  try
    VclSpyInspect(Wnd, X, Y, ReplyWnd);
  finally
    LeaveCall;
  end;
end;

procedure Request(Wnd: HWND; Json: PAnsiChar; ReplyWnd: HWND); stdcall;
begin
  EnterCall;
  try
    VclSpyRequest(Wnd, Json, ReplyWnd);
  finally
    LeaveCall;
  end;
end;

exports
  Inspect name 'VclSpyInspect',
  Request name 'VclSpyRequest',
  VclSpyProbe,
  VclSpyActive,
  VclSpyFinalizesEarly;

end.
