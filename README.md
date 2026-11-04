# DelphiSpy

Inspect, and change, controls of a running Delphi VCL or FireMonkey (FMX) application that is built **with runtime packages**, or, with some limits, without them (see [Targets without runtime packages](#targets-without-runtime-packages) and [FireMonkey targets](#firemonkey-targets)).
Drag the finder (crosshair) from DelphiSpy onto a control and release.
DelphiSpy loads an inspector DLL into the target process. The DLL shares the target's `rtlNNN.bpl`/`vclNNN.bpl`, so it sees the target's real VCL objects.

Shown for the picked control:

- **Name**, class and unit, and the module (exe/bpl) that defines the class
- Owner path (`frmMain.fraHeader.btnSave`), parent path, and the owning form with its unit
- Published properties, the `TControl`/`TWinControl` properties the class doesn't publish (`Caption`, `Color`, `Visible`, `TabOrder`...), public record properties (`BoundsRect`, `ClientRect`), and **event handlers**, e.g. `OnClick = TfrmMain.btnSaveClick`. The handler is reported for the class that declares it (a base form, when forms inherit), with its unit.
- Bound action and its `OnExecute` handler, class hierarchy, raw JSON, and a history of picks
- **Parents**: the control tree of the form, unfolded down to the picked control, with all children of each parent on the way. Unfold any control to list its children (read from the target on demand). Select a control to inspect it instead.

Graphic controls (`TLabel`, `TSpeedButton`, `TImage`...) and disabled controls are found too. Delphi 10.4 (270) and 11 (280) targets are supported, both 32- and 64-bit. So are the forms of FireMonkey applications, their controls, and the objects of the controls' styles.

Applications on other computers of the network can be inspected too, if they link the unit `DelphiSpy.Server` (`DelphiSpy.FmxServer` for FireMonkey; see [Inspecting over the network](#inspecting-over-the-network)).

## Editing properties

Double-click a property (or select it and press Enter, or **Edit...**) to change it in the target. Gray properties are read-only. **Refresh** (F5) reads the control again.

- **Editable**: published properties of simple types: integers, characters, floats and dates, strings, enumerations (including `Boolean`), and sets. Colors (`clRed`, `$00BBGGRR`), cursors (`crHandPoint`) and shortcuts (`Ctrl+S`) take names.
- Also the properties `TControl` and `TWinControl` declare public or protected, so classes that don't publish them still get them (column *Scope*): `Visible`, `Enabled`, `Align`, `Anchors`, `BiDiMode`, `ClientWidth`, `ClientHeight`, `ShowHint`, `StyleElements`, `StyleName`, `Caption`, `Text`, `Color`, `ParentColor`, `ParentFont`, `ParentShowHint`, `ParentBiDiMode`, `AutoSize`, `DragMode`, `DragKind`, `DragCursor`; for windowed controls also `TabOrder`, `TabStop`, `DoubleBuffered`, `ParentDoubleBuffered`, `Bevel*`, `BorderWidth`, `Ctl3D`, `ParentCtl3D`, `ParentBackground`, `ImeMode`, `ImeName`, and read-only `Showing`. The list is `RegisterExtraProps` in `Inspector\DelphiSpy.VclProperties.pas`.
- **Object and record properties** are read-only themselves, but unfold, like in the Object Inspector, to their members, which are read and edited like the control's properties. Click the plus box, double-click the property, or select it and press Enter or the Right arrow (Left folds it again, or goes to the property a member belongs to). Typing a filter lists the matching properties at any depth by their path (`Font.Size`).
  - Objects (`Font`, `Margins`, `Constraints`, `TLabeledEdit.EditLabel`...) unfold to their published and public properties (scope `public`, e.g. `Items.Count` and `Items.CommaText` of a combo box), and collections (`TStatusBar.Panels`, `TListView.Columns`) to their items, `[0]`, `[1]`... (the first 100). So do the `Items` of list views and tree views (tree nodes in tree order, parents before their children), whose items have public properties only (`Items[0].Caption`, `Items[0].SubItems`, `Items[1].Text`, `Items[1].Level`). Public properties whose getters change the object are left out: reading `TPicture.Bitmap`, `Icon`, `Metafile` or `WICImage` turns a picture of another kind (the PNG of a `TImage`) into one of that kind. Properties that refer to other components (`Action`, `PopupMenu`, `Images`) are not unfolded; inspect those components instead. Each object is unfolded once per report, up to 4 levels deep.
  - Records can't be published, so they come from the public properties of the class (`BoundsRect`, `ClientRect`, `ClientOrigin` of every control). They unfold to their fields, nested records too (`BoundsRect.TopLeft.X`). Editing a field reads the record from the property, changes the field, and passes the record to the property's setter. The fields of a record property without a setter (`ClientRect`) are read-only.
- **Not editable**: events, variants, and `Name`. Renaming at run time breaks `FindComponent` lookups and the paths DelphiSpy shows.

The editor offers names for enumerations, sets, colors and cursors. If the target refuses a value (not an integer, out of range, an exception from the setter), the editor opens again with the error.

## Build

```bat
build.cmd            :: tool, injectors, hook and inspector DLLs, plus test targets
build.cmd notests    :: skip the test targets
```

Requires Delphi 10.4 (BDS 21.0) and Delphi 11 (BDS 22.0). Set `BDS21` / `BDS22` if they are not in the default folders.
Output:

```
bin\DelphiSpy.exe                       UI (Win32, no packages)
bin\DelphiSpyRemote.exe                 CLI client for applications that link DelphiSpy.Server
bin\x86\  bin\x64\
    DelphiSpyInject.exe                 injector (also a CLI, see below)
    DelphiSpyHook.dll                   hook stub, no packages
    DelphiSpyInspect270.dll             inspector for rtl270/vcl270 targets (Delphi 10.4)
    DelphiSpyInspect280.dll             inspector for rtl280/vcl280 targets (Delphi 11)
    DelphiSpyInspectNoPkg270.dll        inspector for Delphi 10.4 targets without runtime packages
    DelphiSpyInspectNoPkg280.dll        inspector for Delphi 11 targets without runtime packages
    DelphiSpyInspectFmx270.dll          inspector for FireMonkey targets with fmx270 (Delphi 10.4)
    DelphiSpyInspectFmx280.dll          inspector for FireMonkey targets with fmx280 (Delphi 11)
    DelphiSpyInspectFmxNoPkg270.dll     inspector for Delphi 10.4 FireMonkey targets without runtime packages
    DelphiSpyInspectFmxNoPkg280.dll     inspector for Delphi 11 FireMonkey targets without runtime packages
```

Deploy the whole `bin` folder; DelphiSpy picks `x86` or `x64` by the target's bitness.

## How it works

1. DelphiSpy resolves the deepest window under the cursor and checks the target's bitness and elevation. It then runs `bin\<arch>\DelphiSpyInject.exe --hwnd <h> --x <x> --y <y>`.
2. The injector installs a `WH_CALLWNDPROC` hook with `DelphiSpyHook.dll` on the target window's thread and sends it a query message. That loads the stub into the target. The stub runs on the target's **GUI thread**, so touching VCL objects is safe there.
3. The stub checks which `vclNNN.bpl` is loaded and loads the matching `DelphiSpyInspectNNN.dll` from its own folder. If none is loaded, it loads a no-packages inspector instead (see below). For a FireMonkey form, it does the same with `fmxNNN.bpl` and the FMX inspectors (see [FireMonkey targets](#firemonkey-targets)).
4. The inspector runs `FindControl(hwnd)` (walking to the parent window for non-VCL child windows), then `ControlAtPos` for graphic controls. It collects the data and sends JSON back with `WM_COPYDATA`. The injector prints it to stdout.

The inspector DLL stays loaded in the target after the first pick, because unloading package-based DLLs from a live app is risky. Later picks reuse it.

Edits and refreshes run `DelphiSpyInject.exe --hwnd <h> --request -` with a JSON request on stdin. The injector copies it into an unnamed file mapping and duplicates the handle into the target, so it depends on no named object and no access rights. It then sends a request message through the same hook. The inspector finds the control by its address from the report, but only among live controls (the window tree of `<h>`, then every form), so a stale address is never dereferenced. It sets the property on the GUI thread and replies with a fresh report. The reply's `window.hwnd` is the control's current window, because some property changes recreate window handles.

## Targets without runtime packages

A target that loads no `vclNNN.bpl` links the VCL statically, so it has its own copy of the RTL and VCL. DelphiSpy then falls back to a no-packages inspector, `DelphiSpyInspectNoPkgNNN.dll`, which has a VCL of its own too. It is a package without a `requires` clause, so it contains the RTL and VCL itself, built with the extension `dll` (`Inspector\DelphiSpyInspectNoPkgNNN.dpk`). As with any package, its DllMain doesn't initialize or finalize its units; its exports `Initialize` and `Finalize` do:

- The stub loads one only if the picked window (or a parent window) has the property that the VCL gives every window it creates (`Delphi` + process ID). It tries the inspectors newest version first. Each checks that the target's `TComponent`, `TControl` and `TWinControl` have its own size and published properties, which means the same Delphi version. An inspector that doesn't match is unloaded again. The one that matches stays loaded.
- The stub calls `Initialize` after loading an inspector (and `Finalize` before unloading one that doesn't match). The inspector subclasses the target's `TApplication` window and calls its own `Finalize` when that window gets `WM_DESTROY`, at the end of `TApplication.Destroy`, while the target's memory manager still works. It then writes `DelphiSpy: the inspector finalized itself with the application window` with `OutputDebugString`. If the process ends otherwise, the inspector is not finalized at all.
- The target's objects are not instances of the inspector's classes, though they have the same layout. So the inspector finds controls through that window property instead of `FindControl`. It compares classes by name instead of `is`, and enumerates the process' windows instead of `Screen.Forms`. Fields, RTTI, virtual methods and the VCL's static methods work on the target's objects.
- **Memory manager.** Strings cross between the target's code and the inspector's in both directions. If the target uses `ShareMem` (`borlndmm.dll` is loaded), the inspector installs `borlndmm.dll`'s functions with `SetMemoryManager` before anything is allocated, so both use the same memory manager. If the target shares its memory manager with `SimpleShareMem` (or FastMM's ShareMM), the inspector uses that one. Otherwise it keeps its own memory manager but guards it. Blocks it allocates are marked. Blocks of the target that it would free are leaked instead, and when it reallocates one, it copies the block. The report's `inspector` and `process.memoryManager` say which: `borlndmm.dll`, `shared by the target` or `own, guarded`.
- With the guarded memory manager, the target must not keep strings that the inspector allocated, because the target would free them with its own memory manager. Setters of string properties get a copy that looks like a string literal, so they copy it when they store it. String properties that are written straight to a field (`Hint`, `property X: string read FX write FX`), AnsiString properties, and the unpublished `StyleName` and `ImeName` are read-only then. With a shared memory manager, they are editable.
- Finalizing with the application window matters most for `SimpleShareMem`: the exe frees all memory of its memory manager when it ends, but DLL would already be finalized before that. `Inspector\DelphiSpy.SelfFinalize.pas` does the same, for the FMX inspectors.

`process.vclModule` names the module that links the VCL the control belongs to (`process.vclPackage` with packages). Edits run some VCL code of the inspector's own VCL copy on the target's control (`TControl.SetText`, `SetAlign`...), so global VCL state (`Screen`, `Application`, styles) seen by that code is the inspector's, not the target's.

## FireMonkey targets

FireMonkey applications are inspected like VCL ones: with and without runtime packages, Delphi 10.4 and 11, 32- and 64-bit, through the CLI, and over the network (with `DelphiSpy.FmxServer`). The hook stub tells a FireMonkey form by the property that FMX gives the window of each form (`FIREMONKEY` + process ID). It loads `DelphiSpyInspectFmxNNN.dll` if the target loads `fmxNNN.bpl`, and otherwise a no-packages inspector, `DelphiSpyInspectFmxNoPkgNNN.dll`: the first, newest version first, that accepts the target. It accepts targets whose `TCommonCustomForm` has the size it has in its own Delphi version (the RTL classes have the same size in 10.4 and 11; FMX's don't).

FMX controls have no windows, so some things work differently:

- **Picking.** The inspector finds the form of the window under the finder (or of its parent window, for native controls), maps the point to the form's coordinates (the window's pixels divided by the form's scale), and takes the topmost visible control whose `AbsoluteRect` holds it, in paint order. A control's `ClipChildren` hides its children outside it. `HitTest` doesn't matter, so labels are found too. Not picked are the objects of a control's style (the style object that a `TStyledControl` applies, its first child, and everything below it) and the internal containers of controls (`TContent`, such as the content of list boxes and scroll boxes, and `TStyledPresentation`): the control they belong to is reported instead, or the control inside the container (a list box item).
- **Parents** lists all child objects: controls, the objects of styles (marked `[style]`, and named by their `StyleName`, e.g. `'text': TText`, when they have no name), animations and effects. Select any of them to inspect it; the objects of a style can be edited too, until the control applies its style again.
- `bounds` are `Position.X`, `Position.Y`, `Width` and `Height`, in dp; `screenRect` comes from `AbsoluteRect`. The report's `window` is the form's window, where requests go; `style` is `true` for the objects of a style.
- **Properties.** The control's published properties and *all* its public ones (`AbsoluteRect`, `ParentedVisible`, `IsFocused`, `BoundsRect`...), since FMX has no protected properties worth reaching. Left out are `Canvas` (getters that may create one), `TFmxObject.Data` (a `TValue`), `TControl.Controls` (the same as `Children`), and `TComponent`'s `ComObject`, `VCLComObject` and `Observers`. Objects, collections and records unfold as for the VCL (`TextSettings.Font.Size`, `Margins.Left`, `Position.X`, `BoundsRect.Left`); an object that two properties return (a button's `Font` and `TextSettings.Font`) is unfolded once, below the first. Colors (`TAlphaColor`) take names (`Red`, `claRed`) or numbers (`#FF112233`, `#AARRGGBB`), cursors names (`crHandPoint`).

The FMX inspectors link no FireMonkey unit: a second FireMonkey in the target would set up platform services, windows and OLE of its own. They reach the target's FMX objects through RTTI instead (`Children`, `Parent`, `AbsoluteRect`, the style field of `TStyledControl`), and tell their classes by name. So the package inspector shares only `rtlNNN.bpl` with the target. The no-packages inspector is a package that contains the RTL, like the VCL one, with the same handling of the memory manager. But FireMonkey destroys no window of its own when an exe ends (only in a DLL), so with a target that shares its memory manager (`SimpleShareMem`), the inspector finalizes itself when the last window of the target closes instead: it watches every visible window (minimized ones and FMX's application window aside), and the target ends when the last of them is destroyed, or when none is visible and the application isn't minimized (a minimized FMX application hides its forms). It then writes `DelphiSpy: the inspector finalized itself with the last visible window` with `OutputDebugString`. That's a guess: if such a target hides all its windows while it goes on running (to the notification area, or `Visible` set to `False` in DelphiSpy), the inspector finalizes itself too early, and DelphiSpy reports that the target is closing until it restarts. With other memory managers the inspector needn't finalize itself, and doesn't watch the windows.

Not available for FireMonkey targets: names of shortcuts (`TShortCut` values are numbers), 3D objects (the `TControl3D` objects of a `TViewport3D` or `TForm3D` are listed, but not picked), and platforms other than Windows.

## Inspecting over the network

DelphiSpy can't drag its finder onto a window on another computer, nor inject anything there. Instead, the application links the unit `Server\DelphiSpy.Server.pas`, which runs an [App Tethering](https://docwiki.embarcadero.com/RADStudio/en/Using_App_Tethering) server inside it:

1. Add `DelphiSpy.Server` to the uses clause of the application's `.dpr` (or of any of its units), and DelphiSpy's `Server`, `Inspector` and `Common` folders to the project's search path. Keep it out of release builds:

   ```pascal
   uses
   {$IFDEF DEBUG}
     DelphiSpy.Server,
   {$ENDIF}
     Vcl.Forms,
   ```

   A FireMonkey application adds `DelphiSpy.FmxServer` instead, with the same folders and settings.

2. Run the application. The server starts once the main message loop runs.
3. In DelphiSpy, click **Connect...**. It lists the applications with `DelphiSpy.Server` on the local network (exe, process ID, computer, address). For a computer in another network, type its name or IP address (several, separated by `;`; an address ending in `.0` searches its /24 network) and click **Search**. Select one and **Connect**.
4. **Forms...** lists the application's forms; pick one to inspect it, then browse its controls on the **Parents** tab. **F6** (or the first item of the Forms menu) inspects the control at the mouse cursor of the remote computer, for whoever sits there, or when you control it over remote desktop. Properties are read and edited as for local targets.

The unit links DelphiSpy's inspector into the application, so nothing is injected: the inspector sees the application's own VCL (or FireMonkey). That works with and without runtime packages, with any memory manager, for 32- and 64-bit, and for any Delphi version the inspector compiles with (10.4 and 11 are tested). DelphiSpy and the application may be built with different Delphi versions.

Settings, made in the `.dpr` before `Application.Run`, or with environment variables of the application:

| Variable | Environment | |
|---|---|---|
| `DelphiSpyServerPassword` | `DELPHISPY_PASSWORD` | Password DelphiSpy must give to connect (pairing password of App Tethering). |
| `DelphiSpyServerEnabled` | `DELPHISPY_SERVER=0` | `False` keeps the server from starting. |

`StartDelphiSpyServer` and `StopDelphiSpyServer` start and stop it at any time.

- **Firewall.** App Tethering uses UDP and TCP ports 2020–2039 for discovery and pairing, and TCP ports 2040–2110 for connections, in both directions: the server connects back to DelphiSpy to send its replies. The firewall on both computers must let the application and `DelphiSpy.exe` (or `DelphiSpyRemote.exe`) through; Windows asks for each the first time it listens. If replies time out while the application responds, check the firewall on DelphiSpy's side.
- **Security.** Anyone who can reach the application and knows the password (if one is set) can read and change its controls' properties. The traffic is not encrypted. Use it on trusted networks and in debug builds only.
- Requests run on the application's GUI thread, from its message loop, like requests through the hook. If the GUI thread is busy, or a setter shows a modal dialog, the request times out after 15 seconds.
- Up to 20 App Tethering applications can run on one computer (one port each in 2020–2039).

Op `forms` lists the forms, and op `pick` reports the control at the mouse cursor, or at `"x"` and `"y"` (physical screen coordinates of the remote computer). Both need no address and work through `DelphiSpyInject.exe` too.

`bin\DelphiSpyRemote.exe` is the CLI counterpart of `DelphiSpyInject.exe` for such applications. `--list` prints the servers found; `--request` sends each line of a file or of stdin as a request, and prints each reply on a line:

```bat
bin\DelphiSpyRemote.exe --list
bin\DelphiSpyRemote.exe --list --hosts testpc;192.168.5.0
echo {"op":"forms"} | bin\DelphiSpyRemote.exe --server TestTarget.exe --password secret --request -
echo {"op":"set","address":"$02A41B20","property":"Caption","value":"Save all"} | bin\DelphiSpyRemote.exe --server "PID 1234," --request -
```

`--server` picks the server whose description (`TestTarget.exe, PID 1234, TESTPC`) or address contains the text, or by its number in the list. The exit code is 0 if every reply has `"ok":true`.

## CLI / scripting

```bat
bin\x86\DelphiSpyInject.exe --hwnd 0x1A2B3C --x 800 --y 600    :: JSON to stdout, exit code 0 on success
bin\DelphiSpy.exe --inspect 1715004 800 600                    :: open the UI and inspect without dragging
```

Coordinates are physical screen pixels. The inspector maps them for DPI-unaware targets.

Requests take `control.address` and `window.hwnd` from an earlier report. Values are text, as reports show them:

```bat
echo {"op":"set","address":"$02A41B20","property":"Caption","value":"Save all"} | bin\x86\DelphiSpyInject.exe --hwnd 1715004 --request -
echo {"op":"get","address":"$02A41B20"} | bin\x86\DelphiSpyInject.exe --hwnd 1715004 --request -
```

Each entry of `control.parents`, and of the `children` lists in a report, has an `address` that works in requests too. `children` lists the direct children of the control and of each parent, with `childCount`. Op `children` returns just those, for any control:

```bat
echo {"op":"children","address":"$02A41B20"} | bin\x86\DelphiSpyInject.exe --hwnd 1715004 --request -
```

`"property"` is a property's path: its name, or for a member of an object or record property the names joined with `.`, and collection items as `[index]`:

```bat
echo {"op":"set","address":"$02A41B20","property":"Font.Size","value":"12"} | bin\x86\DelphiSpyInject.exe --hwnd 1715004 --request -
echo {"op":"set","address":"$02A41B20","property":"BoundsRect.Left","value":"20"} | bin\x86\DelphiSpyInject.exe --hwnd 1715004 --request -
echo {"op":"set","address":"$02A41B20","property":"Panels[0].Text","value":"Ready"} | bin\x86\DelphiSpyInject.exe --hwnd 1715004 --request -
```

`--request <file>` reads the request from a UTF-8 file instead. A `set` reply adds `"changed": {"property", "oldValue", "newValue"}`. Each property in a report has `name`, `path`, `kind` (`class` and `record` for object and record properties), `scope` (`field` for record fields, `item` for collection items) and `editable`. Object and record properties that unfold have their members in `properties`. `control.types` lists the names of the editable enumeration, set, color and cursor types, also those of members.

## Tests

`Test\run-tests.ps1` starts the test targets: 10.4/11 × x86/x64 with packages, and without packages (plain, with `ShareMem` and with `SimpleShareMem`). It inspects their controls through the CLI, edits some of their properties, checks the JSON, and checks that each target still closes normally. Targets that link `DelphiSpy.Server` (11 x86 without packages, 11 x64 with packages, 10.4 x64 without packages) are inspected the same way through `DelphiSpyRemote.exe`, over the loopback address, with a password. So is the FireMonkey target, `Test\FmxTestTarget.dpr`, in the same variants (11 x86 and 10.4 x64 with packages, 11 x64 and 10.4 x86 without, 11 x86 with `ShareMem`, 11 x64 with `SimpleShareMem`, and with `DelphiSpy.FmxServer` 11 x86 without packages and 10.4 x64 with them). Its controls are found by name through `children`, and picked at the center of the `screenRect` that `get` reports. `-Only <pattern>` runs the variants whose folder in `Test\bin` matches (`-Only fmx-*`):

```bat
powershell -ExecutionPolicy Bypass -File Test\run-tests.ps1
```

## Limitations

- The target must use the same major Delphi version's `vclNNN.bpl` as an inspector in `bin`, or, without packages, be built with the same Delphi version as a no-packages inspector. To support another version, add `Inspector\DelphiSpyInspectNNN.dpr` and `Inspector\DelphiSpyInspectNoPkgNNN.dpk` (copies with a different `CompilerVersion` or `VERnnn` check), build them with that Delphi, and add its suffix to `DelphiSpyPackageSuffixes` in `Common\DelphiSpy.Protocol.pas` if it is missing. For FireMonkey, add `DelphiSpyInspectFmxNNN.dpr` and `DelphiSpyInspectFmxNoPkgNNN.dpk` the same way, and the size of that version's `TCommonCustomForm` (Win32 and Win64) to `FormInstanceSize` in `Inspector\DelphiSpy.FmxInspector.pas`.
- In a target with runtime packages, controls of modules that link the VCL statically (a DLL with its own VCL) are not visible to the shared VCL; DelphiSpy reports this.
- Without runtime packages, the inspector works on objects of a VCL copy that isn't its own. It is less robust than a package inspector, especially without `ShareMem`. Don't count on the target being in a good state after a debugging session.
- Elevated targets need DelphiSpy to run as administrator.
- Reading properties calls their getters inside the target, also those of record properties and of the properties of unfolded objects. That is normally harmless, but it can create window handles that didn't exist yet (`ClientRect`), and public getters of unfolded objects can create what they return (a bitmap's `Canvas`, a font's `Handle`).
- Without a shared memory manager (`own, guarded`), the fields of records that hold strings or other managed values are read-only, because the target would keep the inspector's strings.
- Setting a property runs its setter, and whatever the target's code does then (`OnChange`, `OnResize`...), on the target's GUI thread. If that shows a modal dialog, the request times out after 5 seconds; the change still happens.
- Values longer than 300 characters are cut off in reports. Editing such a value replaces all of it; the editor says so.
