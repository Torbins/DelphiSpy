program VclSpyInject;

{ Command-line injector, built as x86 and x64. VclSpy.exe starts the build
  that matches the target's bitness and reads the JSON reply from stdout.

  Usage: VclSpyInject.exe --hwnd <handle> --x <screenX> --y <screenY> [--timeout <ms>]
  Coordinates are physical screen pixels. Exit code 0 means "ok":true. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  VclSpy.Protocol in '..\Common\VclSpy.Protocol.pas',
  VclSpy.Injector in '..\Common\VclSpy.Injector.pas';

// Looks for "--name value"; values may be negative (multi-monitor coordinates)
function FindArg(const Name: string; out Value: Int64): Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), '--' + Name) then
    begin
      Value := StrToInt64(ParamStr(I + 1));
      Exit(True);
    end;
  Result := False;
end;

function RequiredArg(const Name: string): Int64;
begin
  if not FindArg(Name, Result) then
    raise EArgumentException.CreateFmt('Missing --%s. Usage: %s --hwnd <handle> --x <x> --y <y> [--timeout <ms>]',
      [Name, VclSpyInjectExeName]);
end;

function OptionalArg(const Name: string; Default: Int64): Int64;
begin
  if not FindArg(Name, Result) then
    Result := Default;
end;

var
  Output: RawByteString;
  Written: DWORD;
begin
  try
    Output := InjectAndQuery(HWND(RequiredArg('hwnd')), RequiredArg('x'), RequiredArg('y'),
      OptionalArg('timeout', VclSpyReplyTimeout));
  except
    on E: Exception do
      Output := ErrorJson(E.Message);
  end;
  if Output <> '' then
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), Output[1], Length(Output), Written, nil);
  if Pos(RawByteString('"ok":true'), Output) = 2 then
    ExitCode := 0
  else
    ExitCode := 1;
end.
