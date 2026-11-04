@echo off
rem Builds VclSpy and its test targets with the Delphi command-line compilers.
rem   VclSpyInspect270 and the 270 test targets: Delphi 10.4 (BDS 21.0)
rem   everything else:                           Delphi 11   (BDS 22.0)
rem Set BDS21 / BDS22 to override the install folders.
setlocal EnableExtensions
set "ROOT=%~dp0"
if not defined BDS21 set "BDS21=C:\Program Files (x86)\Embarcadero\Studio\21.0"
if not defined BDS22 set "BDS22=C:\Program Files (x86)\Embarcadero\Studio\22.0"
set "BIN=%ROOT%bin"
set "TESTBIN=%ROOT%Test\bin"
set "PKG=-LUrtl;vcl"

echo === Tool\VclSpyManifest.rc
"%BDS22%\bin\brcc32.exe" -fo"%ROOT%Tool\VclSpyManifest.res" "%ROOT%Tool\VclSpyManifest.rc" >nul || goto :fail

call :dcc "%BDS22%" dcc32 Tool\VclSpy.dpr                   "%BIN%"     tool-x86     ""       || goto :fail
call :dcc "%BDS22%" dcc32 Inject\VclSpyInject.dpr           "%BIN%\x86" inject-x86   ""       || goto :fail
call :dcc "%BDS22%" dcc64 Inject\VclSpyInject.dpr           "%BIN%\x64" inject-x64   ""       || goto :fail
call :dcc "%BDS22%" dcc32 Hook\VclSpyHook.dpr               "%BIN%\x86" hook-x86     ""       || goto :fail
call :dcc "%BDS22%" dcc64 Hook\VclSpyHook.dpr               "%BIN%\x64" hook-x64     ""       || goto :fail
call :dcc "%BDS22%" dcc32 Inspector\VclSpyInspect280.dpr    "%BIN%\x86" inspect280-x86 "%PKG%" || goto :fail
call :dcc "%BDS22%" dcc64 Inspector\VclSpyInspect280.dpr    "%BIN%\x64" inspect280-x64 "%PKG%" || goto :fail
call :dcc "%BDS21%" dcc32 Inspector\VclSpyInspect270.dpr    "%BIN%\x86" inspect270-x86 "%PKG%" || goto :fail
call :dcc "%BDS21%" dcc64 Inspector\VclSpyInspect270.dpr    "%BIN%\x64" inspect270-x64 "%PKG%" || goto :fail

if /i "%~1"=="notests" goto :done
call :dcc "%BDS21%" dcc32 Test\TestTarget.dpr "%TESTBIN%\270-x86"       test-270-x86       "%PKG%" || goto :fail
call :dcc "%BDS21%" dcc64 Test\TestTarget.dpr "%TESTBIN%\270-x64"       test-270-x64       "%PKG%" || goto :fail
call :dcc "%BDS22%" dcc32 Test\TestTarget.dpr "%TESTBIN%\280-x86"       test-280-x86       "%PKG%" || goto :fail
call :dcc "%BDS22%" dcc64 Test\TestTarget.dpr "%TESTBIN%\280-x64"       test-280-x64       "%PKG%" || goto :fail
call :dcc "%BDS22%" dcc32 Test\TestTarget.dpr "%TESTBIN%\280-x86-nopkg" test-280-x86-nopkg ""      || goto :fail

:done
echo.
echo Build succeeded.
exit /b 0

:fail
echo.
echo Build FAILED.
exit /b 1

rem :dcc <bds root> <dcc32|dcc64> <dpr> <exe output dir> <dcu dir name> <extra options>
:dcc
set "DCUDIR=%ROOT%dcu\%~5"
if not exist "%~4" mkdir "%~4"
if not exist "%DCUDIR%" mkdir "%DCUDIR%"
echo === %~3 (%~2, %~nx1)
rem "uses ... in '..\x.pas'" paths are relative to the current folder, so build from the dpr's folder
for %%F in ("%ROOT%%~3") do pushd "%%~dpF"
"%~1\bin\%~2.exe" -B -Q -NSSystem;System.Win;Winapi;Vcl -E"%~4" -NU"%DCUDIR%" %~6 "%~nx3"
set "RC=%errorlevel%"
popd
exit /b %RC%
