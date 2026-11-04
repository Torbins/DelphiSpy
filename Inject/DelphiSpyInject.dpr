program DelphiSpyInject;

{ Command-line injector, built as x86 and x64. DelphiSpy.exe starts the build
  that matches the target's bitness and reads the JSON reply from stdout.

  Usage: DelphiSpyInject.exe --hwnd <handle> --x <screenX> --y <screenY> [--timeout <ms>]
         DelphiSpyInject.exe --hwnd <handle> --request <file | -> [--timeout <ms>]
  Coordinates are physical screen pixels. --request sends a UTF-8 JSON
  request read from a file or, with "-", from stdin; see DelphiSpyRequest in
  Inspector\DelphiSpy.Inspector.pas. Exit code 0 means "ok":true. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  DelphiSpy.Protocol in '..\Common\DelphiSpy.Protocol.pas',
  DelphiSpy.Injector in '..\Common\DelphiSpy.Injector.pas';

// Looks for "--name value"
function FindStrArg(const Name: string; out Value: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), '--' + Name) then
    begin
      Value := ParamStr(I + 1);
      Exit(True);
    end;
  Result := False;
end;

// Values may be negative (multi-monitor coordinates)
function FindArg(const Name: string; out Value: Int64): Boolean;
var
  S: string;
begin
  Result := FindStrArg(Name, S);
  if Result then
    Value := StrToInt64(S);
end;

function RequiredArg(const Name: string): Int64;
begin
  if not FindArg(Name, Result) then
    raise EArgumentException.CreateFmt('Missing --%s. Usage: %s --hwnd <handle> --x <x> --y <y> ' +
      '[--timeout <ms>], or %0:s --hwnd <handle> --request <file | -> [--timeout <ms>]',
      [Name, DelphiSpyInjectExeName]);
end;

function OptionalArg(const Name: string; Default: Int64): Int64;
begin
  if not FindArg(Name, Result) then
    Result := Default;
end;

function ReadRequest(const Source: string): RawByteString;
var
  Input: THandle;
  Buffer: array[0..4095] of Byte;
  Count: DWORD;
  Bytes: TBytes;
begin
  if Source <> '-' then
    Bytes := TFile.ReadAllBytes(Source)
  else
  begin
    // stdin may be a pipe, which has no size to ask for
    Input := GetStdHandle(STD_INPUT_HANDLE);
    while ReadFile(Input, Buffer, SizeOf(Buffer), Count, nil) and (Count > 0) do
    begin
      SetLength(Bytes, Length(Bytes) + Integer(Count));
      Move(Buffer, Bytes[Length(Bytes) - Integer(Count)], Count);
    end;
  end;
  SetString(Result, PAnsiChar(Bytes), Length(Bytes));
end;

var
  Output: RawByteString;
  Written: DWORD;
  RequestSource: string;
begin
  try
    if FindStrArg('request', RequestSource) then
      Output := InjectAndRequest(HWND(RequiredArg('hwnd')), ReadRequest(RequestSource),
        OptionalArg('timeout', DelphiSpyReplyTimeout))
    else
      Output := InjectAndQuery(HWND(RequiredArg('hwnd')), RequiredArg('x'), RequiredArg('y'),
        OptionalArg('timeout', DelphiSpyReplyTimeout));
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
