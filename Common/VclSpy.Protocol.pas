unit VclSpy.Protocol;

{ Constants shared by the VclSpy tool, the injector, the hook stub and the
  inspector DLLs. Uses only Winapi.Windows, because the hook stub is built
  without SysUtils and without runtime packages. }

interface

uses
  Winapi.Windows;

const
  VclSpyQueryMessageName = 'VclSpy.Query.v1';
  // WParam: reply window. LParam: a handle, valid in the target, to a file
  // mapping that holds the request as null-terminated UTF-8 JSON. The hook
  // stub closes the handle.
  VclSpyRequestMessageName = 'VclSpy.Request.v1';
  VclSpyCopyDataMagic = $31535356; // 'VSS1'
  VclSpyReplyTimeout = 5000;

  VclSpyHookDllName = 'VclSpyHook.dll';
  VclSpyHookExport = 'VclSpyCallWndProc';
  VclSpyInspectDllPrefix = 'VclSpyInspect';
  VclSpyInspectExport = 'VclSpyInspect';
  VclSpyRequestExport = 'VclSpyRequest';
  // The no-packages inspectors, VclSpyInspectNoPkg<suffix>.dll, for targets
  // that link the VCL statically. They are packages that contain the RTL and
  // VCL: Initialize and Finalize (exported by every package) initialize and
  // finalize their units.
  VclSpyNoPkgDllPrefix = 'VclSpyInspectNoPkg';
  // The FMX inspectors: VclSpyInspectFmx<suffix>.dll for targets that load
  // fmx<suffix>.bpl, VclSpyInspectFmxNoPkg<suffix>.dll for those that link
  // FireMonkey statically (also packages that contain the RTL)
  VclSpyFmxInspectDllPrefix = 'VclSpyInspectFmx';
  VclSpyFmxNoPkgDllPrefix = 'VclSpyInspectFmxNoPkg';
  VclSpyProbeExport = 'VclSpyProbe';
  VclSpyActiveExport = 'VclSpyActive';
  VclSpyInitializeExport = 'Initialize';
  VclSpyFinalizeExport = 'Finalize';
  VclSpyInjectExeName = 'VclSpyInject.exe';

  // VclSpy.Server: App Tethering between VclSpy and a target that links the
  // inspector, over the network. The server's TTetheringManager.Text starts
  // with VclSpyServerTextPrefix, and its profile is in VclSpyProfileGroup.
  // Requests are JSON objects as for VclSpyRequest, plus "id" and "replyTo",
  // the client's profile identifier, sent as UTF-8 streams described
  // VclSpyRequestDescription. The reply goes back as a stream described
  // VclSpyReplyDescription + id.
  VclSpyServerTextPrefix = 'VclSpy server: ';
  VclSpyClientText = 'VclSpy client';
  VclSpyProfileGroup = 'VclSpy.v1';
  VclSpyRequestDescription = 'VclSpy.Request';
  VclSpyReplyDescription = 'VclSpy.Reply:';
  VclSpyRemoteTimeout = 15000;

  // BPL suffixes of the Delphi versions the hook stub looks for, newest first.
  // An inspector named VclSpyInspect<suffix>.dll must exist for each one used,
  // and VclSpyInspectNoPkg<suffix>.dll for targets without runtime packages;
  // VclSpyInspectFmx<suffix>.dll and VclSpyInspectFmxNoPkg<suffix>.dll for
  // FireMonkey targets.
  VclSpyPackageSuffixes: array[0..3] of string = ('370', '290', '280', '270');

type
  // Exported by the inspector DLLs. X and Y are physical screen coordinates.
  TVclSpyInspectProc = procedure(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
  // Exported by the inspector DLLs. Request is null-terminated UTF-8 JSON.
  TVclSpyRequestProc = procedure(Wnd: HWND; Request: PAnsiChar; ReplyWnd: HWND); stdcall;
  // Exported by the no-packages inspector DLLs: True if the VCL control (or
  // FMX form) of Wnd, or of a parent window, is of the Delphi version the DLL
  // was built with.
  TVclSpyProbeProc = function(Wnd: HWND): BOOL; stdcall;
  // Exported by the no-packages inspector DLLs: False once the target's
  // application window is gone and the DLL finalized itself.
  TVclSpyActiveProc = function: BOOL; stdcall;
  // Initialize and Finalize of a package
  TVclSpyPackageProc = procedure;

function PackPoint(X, Y: Integer): LPARAM;
procedure UnpackPoint(Value: LPARAM; out X, Y: Integer);

implementation

function PackPoint(X, Y: Integer): LPARAM;
begin
  Result := LPARAM(Cardinal(Word(SmallInt(X))) or (Cardinal(Word(SmallInt(Y))) shl 16));
end;

procedure UnpackPoint(Value: LPARAM; out X, Y: Integer);
begin
  X := SmallInt(Word(Value and $FFFF));
  Y := SmallInt(Word((Value shr 16) and $FFFF));
end;

end.
