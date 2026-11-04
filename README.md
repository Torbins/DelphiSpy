# VclSpy

Inspect, and change, controls of a running Delphi VCL application that is built **with runtime packages**.
Drag the finder (crosshair) from VclSpy onto a control and release.
VclSpy loads an inspector DLL into the target process. The DLL shares the target's `rtlNNN.bpl`/`vclNNN.bpl`, so it sees the target's real VCL objects.

Shown for the picked control:

- **Name**, class and unit, and the module (exe/bpl) that defines the class
- Owner path (`frmMain.fraHeader.btnSave`), parent path, and the owning form with its unit
- Published properties, the `TControl`/`TWinControl` properties the class doesn't publish (`Caption`, `Color`, `Visible`, `TabOrder`...), and **event handlers**, e.g. `OnClick = TfrmMain.btnSaveClick`. The handler is reported for the class that declares it (a base form, when forms inherit), with its unit.
- Bound action and its `OnExecute` handler, class hierarchy, raw JSON, and a history of picks
- **Parents**: the control tree of the form, unfolded down to the picked control, with all children of each parent on the way. Unfold any control to list its children (read from the target on demand). Select a control to inspect it instead.

Graphic controls (`TLabel`, `TSpeedButton`, `TImage`...) and disabled controls are found too. Delphi 10.4 (270) and 11 (280) targets are supported, both 32- and 64-bit.

## Editing properties

Double-click a property (or select it and press Enter, or **Edit...**) to change it in the target. Gray properties are read-only. **Refresh** (F5) reads the control again.

- **Editable**: published properties of simple types: integers, characters, floats and dates, strings, enumerations (including `Boolean`), and sets. Colors (`clRed`, `$00BBGGRR`), cursors (`crHandPoint`) and shortcuts (`Ctrl+S`) take names.
- Also the properties `TControl` and `TWinControl` declare public or protected, so classes that don't publish them still get them (column *Scope*): `Visible`, `Enabled`, `Align`, `Anchors`, `BiDiMode`, `ClientWidth`, `ClientHeight`, `ShowHint`, `StyleElements`, `StyleName`, `Caption`, `Text`, `Color`, `ParentColor`, `ParentFont`, `ParentShowHint`, `ParentBiDiMode`, `AutoSize`, `DragMode`, `DragKind`, `DragCursor`; for windowed controls also `TabOrder`, `TabStop`, `DoubleBuffered`, `ParentDoubleBuffered`, `Bevel*`, `BorderWidth`, `Ctl3D`, `ParentCtl3D`, `ParentBackground`, `ImeMode`, `ImeName`, and read-only `Showing`. The list is `RegisterExtraProps` in `Inspector\VclSpy.Properties.pas`.
- **Not editable**: object properties (`Font`, `Margins`, `Items`...), events, variants, and `Name`. Renaming at run time breaks `FindComponent` lookups and the paths VclSpy shows.

The editor offers names for enumerations, sets, colors and cursors. If the target refuses a value (not an integer, out of range, an exception from the setter), the editor opens again with the error.

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

Edits and refreshes run `VclSpyInject.exe --hwnd <h> --request -` with a JSON request on stdin. The injector copies it into an unnamed file mapping and duplicates the handle into the target, so it depends on no named object and no access rights. It then sends a request message through the same hook. The inspector finds the control by its address from the report, but only among live controls (the window tree of `<h>`, then every form), so a stale address is never dereferenced. It sets the property on the GUI thread and replies with a fresh report. The reply's `window.hwnd` is the control's current window, because some property changes recreate window handles.

## CLI / scripting

```bat
bin\x86\VclSpyInject.exe --hwnd 0x1A2B3C --x 800 --y 600    :: JSON to stdout, exit code 0 on success
bin\VclSpy.exe --inspect 1715004 800 600                    :: open the UI and inspect without dragging
```

Coordinates are physical screen pixels. The inspector maps them for DPI-unaware targets.

Requests take `control.address` and `window.hwnd` from an earlier report. Values are text, as reports show them:

```bat
echo {"op":"set","address":"$02A41B20","property":"Caption","value":"Save all"} | bin\x86\VclSpyInject.exe --hwnd 1715004 --request -
echo {"op":"get","address":"$02A41B20"} | bin\x86\VclSpyInject.exe --hwnd 1715004 --request -
```

Each entry of `control.parents`, and of the `children` lists in a report, has an `address` that works in requests too. `children` lists the direct children of the control and of each parent, with `childCount`. Op `children` returns just those, for any control:

```bat
echo {"op":"children","address":"$02A41B20"} | bin\x86\VclSpyInject.exe --hwnd 1715004 --request -
```

`--request <file>` reads the request from a UTF-8 file instead. A `set` reply adds `"changed": {"property", "oldValue", "newValue"}`. Each property in a report has `kind`, `scope` and `editable`, and `control.types` lists the names of the editable enumeration, set, color and cursor types.

## Tests

`Test\run-tests.ps1` starts the test targets (10.4/11 × x86/x64, plus one built without packages). It inspects their controls through the CLI, edits some of their properties, and checks the JSON:

```bat
powershell -ExecutionPolicy Bypass -File Test\run-tests.ps1
```

## Limitations

- The target must use the same major Delphi version's `vclNNN.bpl` as an inspector in `bin`. To support another version, add `Inspector\VclSpyInspectNNN.dpr` (a copy with a different `CompilerVersion` check), build it with that Delphi, and add its suffix to `VclSpyPackageSuffixes` in `Common\VclSpy.Protocol.pas` if it is missing.
- Controls in modules linked **without** runtime packages (an exe or DLL with static VCL) are not visible to the shared VCL; VclSpy reports this.
- Elevated targets need VclSpy to run as administrator.
- Reading properties calls their getters inside the target. That is normally harmless, but it can create window handles that didn't exist yet.
- Setting a property runs its setter, and whatever the target's code does then (`OnChange`, `OnResize`...), on the target's GUI thread. If that shows a modal dialog, the request times out after 5 seconds; the change still happens.
- Values longer than 300 characters are cut off in reports. Editing such a value replaces all of it; the editor says so.
