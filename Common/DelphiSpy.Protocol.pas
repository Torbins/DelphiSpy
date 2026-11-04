unit DelphiSpy.Protocol;

{ Constants shared by the DelphiSpy tool, the injector, the hook stub and the
  inspector DLLs. Uses only Winapi.Windows, because the hook stub is built
  without SysUtils and without runtime packages. }

interface

uses
  Winapi.Windows;

const
  DelphiSpyQueryMessageName = 'DelphiSpy.Query.v1';
  // WParam: reply window. LParam: a handle, valid in the target, to a file
  // mapping that holds the request as null-terminated UTF-8 JSON. The hook
  // stub closes the handle.
  DelphiSpyRequestMessageName = 'DelphiSpy.Request.v1';
  DelphiSpyCopyDataMagic = $31535356; // 'VSS1'
  DelphiSpyReplyTimeout = 5000;

  DelphiSpyHookDllName = 'DelphiSpyHook.dll';
  DelphiSpyHookExport = 'DelphiSpyCallWndProc';
  DelphiSpyInspectDllPrefix = 'DelphiSpyInspect';
  DelphiSpyInspectExport = 'DelphiSpyInspect';
  DelphiSpyRequestExport = 'DelphiSpyRequest';
  // The no-packages inspectors, DelphiSpyInspectNoPkg<suffix>.dll, for targets
  // that link the VCL statically. They are packages that contain the RTL and
  // VCL: Initialize and Finalize (exported by every package) initialize and
  // finalize their units.
  DelphiSpyNoPkgDllPrefix = 'DelphiSpyInspectNoPkg';
  // The FMX inspectors: DelphiSpyInspectFmx<suffix>.dll for targets that load
  // fmx<suffix>.bpl, DelphiSpyInspectFmxNoPkg<suffix>.dll for those that link
  // FireMonkey statically (also packages that contain the RTL)
  DelphiSpyFmxInspectDllPrefix = 'DelphiSpyInspectFmx';
  DelphiSpyFmxNoPkgDllPrefix = 'DelphiSpyInspectFmxNoPkg';
  DelphiSpyProbeExport = 'DelphiSpyProbe';
  DelphiSpyActiveExport = 'DelphiSpyActive';
  DelphiSpyInitializeExport = 'Initialize';
  DelphiSpyFinalizeExport = 'Finalize';
  DelphiSpyInjectExeName = 'DelphiSpyInject.exe';

  // DelphiSpy.Server: App Tethering between DelphiSpy and a target that links the
  // inspector, over the network. The server's TTetheringManager.Text starts
  // with DelphiSpyServerTextPrefix, and its profile is in DelphiSpyProfileGroup.
  // Requests are JSON objects as for DelphiSpyRequest, plus "id" and "replyTo",
  // the client's profile identifier, sent as UTF-8 streams described
  // DelphiSpyRequestDescription. The reply goes back as a stream described
  // DelphiSpyReplyDescription + id.
  DelphiSpyServerTextPrefix = 'DelphiSpy server: ';
  DelphiSpyClientText = 'DelphiSpy client';
  DelphiSpyProfileGroup = 'DelphiSpy.v1';
  DelphiSpyRequestDescription = 'DelphiSpy.Request';
  DelphiSpyReplyDescription = 'DelphiSpy.Reply:';
  DelphiSpyRemoteTimeout = 15000;

  // BPL suffixes of the Delphi versions the hook stub looks for, newest first.
  // An inspector named DelphiSpyInspect<suffix>.dll must exist for each one used,
  // and DelphiSpyInspectNoPkg<suffix>.dll for targets without runtime packages;
  // DelphiSpyInspectFmx<suffix>.dll and DelphiSpyInspectFmxNoPkg<suffix>.dll for
  // FireMonkey targets.
  DelphiSpyPackageSuffixes: array[0..3] of string = ('370', '290', '280', '270');

type
  // Exported by the inspector DLLs. X and Y are physical screen coordinates.
  TDelphiSpyInspectProc = procedure(Wnd: HWND; X, Y: Integer; ReplyWnd: HWND); stdcall;
  // Exported by the inspector DLLs. Request is null-terminated UTF-8 JSON.
  TDelphiSpyRequestProc = procedure(Wnd: HWND; Request: PAnsiChar; ReplyWnd: HWND); stdcall;
  // Exported by the no-packages inspector DLLs: True if the VCL control (or
  // FMX form) of Wnd, or of a parent window, is of the Delphi version the DLL
  // was built with.
  TDelphiSpyProbeProc = function(Wnd: HWND): BOOL; stdcall;
  // Exported by the no-packages inspector DLLs: False once the target's
  // application window is gone and the DLL finalized itself.
  TDelphiSpyActiveProc = function: BOOL; stdcall;
  // Initialize and Finalize of a package
  TDelphiSpyPackageProc = procedure;

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
