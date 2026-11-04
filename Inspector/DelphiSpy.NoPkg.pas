unit DelphiSpy.NoPkg;

{ Part of the no-packages VCL inspectors only: their exports. They are
  packages that contain the RTL and VCL themselves (no requires clause),
  built with the extension dll. DelphiSpy.SelfFinalize finalizes them when the
  target's application window is destroyed; the inspector's calls are
  wrapped, so that it isn't finalized while it runs. }

interface

implementation

uses
  Winapi.Windows, DelphiSpy.Inspector, DelphiSpy.SelfFinalize;

procedure Inspect(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
begin
  EnterCall;
  try
    DelphiSpyInspect(Wnd, X, Y, ReplyWnd);
  finally
    LeaveCall;
  end;
end;

procedure Request(Wnd: HWND; Json: PAnsiChar; ReplyWnd: HWND); stdcall;
begin
  EnterCall;
  try
    DelphiSpyRequest(Wnd, Json, ReplyWnd);
  finally
    LeaveCall;
  end;
end;

exports
  Inspect name 'DelphiSpyInspect',
  Request name 'DelphiSpyRequest',
  DelphiSpyProbe,
  DelphiSpyActive,
  DelphiSpyFinalizesEarly;

end.
