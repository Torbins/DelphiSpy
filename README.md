# VclSpy

Inspect controls of a running Delphi VCL application that is built **with runtime packages**.
Drag the finder (crosshair) from VclSpy onto a control and release.
VclSpy loads an inspector DLL into the target process. The DLL shares the target's `rtlNNN.bpl`/`vclNNN.bpl`, so it sees the target's real VCL objects.

Shown for the picked control:

- **Name**, class and unit, and the module (exe/bpl) that defines the class
- Owner path (`frmMain.fraHeader.btnSave`), parent path, and the owning form with its unit
- Published properties, and **event handlers**, e.g. `OnClick = TfrmMain.btnSaveClick`. The handler is reported for the class that declares it (a base form, when forms inherit), with its unit.
- Bound action and its `OnExecute` handler, class hierarchy, raw JSON, and a history of picks

Graphic controls (`TLabel`, `TSpeedButton`, `TImage`...) and disabled controls are found too. Delphi 10.4 (270) and 11 (280) targets are supported, both 32- and 64-bit.

## Build

```bat
build.cmd            :: tool, injectors, hook and inspector DLLs, plus test targets
build.cmd notests    :: skip the test targets
```

Requires Delphi 10.4 (BDS 21.0) and Delphi 11 (BDS 22.0). Set `BDS21` / `BDS22` if they are not in the default folders.
Output:

```
bin\VclSpy.exe                       UI (Win32, no packages)
bin\x86\  bin\x64\
    VclSpyInject.exe                 injector (also a CLI, see below)
    VclSpyHook.dll                   hook stub, no packages
    VclSpyInspect270.dll             inspector for rtl270/vcl270 targets (Delphi 10.4)
    VclSpyInspect280.dll             inspector for rtl280/vcl280 targets (Delphi 11)
```

Deploy the whole `bin` folder; VclSpy picks `x86` or `x64` by the target's bitness.

## How it works

1. VclSpy resolves the deepest window under the cursor and checks the target's bitness and elevation. It then runs `bin\<arch>\VclSpyInject.exe --hwnd <h> --x <x> --y <y>`.
2. The injector installs a `WH_CALLWNDPROC` hook with `VclSpyHook.dll` on the target window's thread and sends it a query message. That loads the stub into the target. The stub runs on the target's **GUI thread**, so touching VCL objects is safe there.
3. The stub checks which `vclNNN.bpl` is loaded and loads the matching `VclSpyInspectNNN.dll` from its own folder.
4. The inspector runs `FindControl(hwnd)` (walking to the parent window for non-VCL child windows), then `ControlAtPos` for graphic controls. It collects the data and sends JSON back with `WM_COPYDATA`. The injector prints it to stdout.

The inspector DLL stays loaded in the target after the first pick, because unloading package-based DLLs from a live app is risky. Later picks reuse it.

## CLI / scripting

```bat
bin\x86\VclSpyInject.exe --hwnd 0x1A2B3C --x 800 --y 600    :: JSON to stdout, exit code 0 on success
bin\VclSpy.exe --inspect 1715004 800 600                    :: open the UI and inspect without dragging
```

Coordinates are physical screen pixels. The inspector maps them for DPI-unaware targets.

## Tests

`Test\run-tests.ps1` starts the test targets (10.4/11 × x86/x64, plus one built without packages). It inspects their controls through the CLI and checks the JSON:

```bat
powershell -ExecutionPolicy Bypass -File Test\run-tests.ps1
```

## Limitations

- The target must use the same major Delphi version's `vclNNN.bpl` as an inspector in `bin`. To support another version, add `Inspector\VclSpyInspectNNN.dpr` (a copy with a different `CompilerVersion` check), build it with that Delphi, and add its suffix to `VclSpyPackageSuffixes` in `Common\VclSpy.Protocol.pas` if it is missing.
- Controls in modules linked **without** runtime packages (an exe or DLL with static VCL) are not visible to the shared VCL; VclSpy reports this.
- Elevated targets need VclSpy to run as administrator.
- Reading properties calls their getters inside the target. That is normally harmless, but it can create window handles that didn't exist yet.
