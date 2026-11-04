unit VclSpy.NoPkg;

{ Part of the no-packages VCL inspectors only: their exports. They are
  packages that contain the RTL and VCL themselves (no requires clause),
  built with the extension dll. VclSpy.SelfFinalize finalizes them when the
  target's application window is destroyed; the inspector's calls are
  wrapped, so that it isn't finalized while it runs. }

interface

implementation

uses
  Winapi.Windows, VclSpy.Inspector, VclSpy.SelfFinalize;

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
