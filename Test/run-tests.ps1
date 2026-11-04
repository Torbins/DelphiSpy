# Starts every TestTarget variant, inspects its controls through
# bin\<arch>\VclSpyInject.exe and checks the JSON replies.
# Run build.cmd first. Usage: powershell -ExecutionPolicy Bypass -File Test\run-tests.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class Win {
    public delegate bool EnumProc(IntPtr wnd, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr wnd, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr wnd, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr wnd, out RECT rect);

    static string ClassOf(IntPtr wnd) { var s = new StringBuilder(256); GetClassName(wnd, s, s.Capacity); return s.ToString(); }
    static string TextOf(IntPtr wnd) { var s = new StringBuilder(256); GetWindowText(wnd, s, s.Capacity); return s.ToString(); }

    public static IntPtr FindChild(IntPtr parent, string cls, string text) {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(parent, (w, d) => {
            if (ClassOf(w) == cls && (text == null || TextOf(w) == text)) { found = w; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    // Physical screen coordinates, the same space VclSpy.exe works in
    public static int[] Center(IntPtr wnd) {
        SetThreadDpiAwarenessContext(new IntPtr(-4));
        RECT r; GetWindowRect(wnd, out r);
        return new int[] { (r.Left + r.Right) / 2, (r.Top + r.Bottom) / 2 };
    }
}
'@

$script:Failures = 0
$script:Checks = 0

function Check($Label, $Actual, $Expected) {
    $script:Checks++
    if ($Actual -eq $Expected) { Write-Host "  ok    $Label = $Actual" }
    else { $script:Failures++; Write-Host "  FAIL  $Label = '$Actual', expected '$Expected'" -ForegroundColor Red }
}

function CheckLike($Label, $Actual, $Pattern) {
    $script:Checks++
    if ("$Actual" -like $Pattern) { Write-Host "  ok    $Label ~ $Pattern" }
    else { $script:Failures++; Write-Host "  FAIL  $Label = '$Actual', expected like '$Pattern'" -ForegroundColor Red }
}

function Inspect($Arch, [IntPtr]$Wnd) {
    $pt = [Win]::Center($Wnd)
    $out = & "$Root\bin\$Arch\VclSpyInject.exe" --hwnd $Wnd.ToInt64() --x $pt[0] --y $pt[1]
    return ($out -join '') | ConvertFrom-Json
}

# Sends a request through stdin, for the control of an earlier report unless
# $Body has another address
function Request($Arch, $Report, [hashtable]$Body) {
    if (-not $Body.ContainsKey('address')) { $Body.address = $Report.control.address }
    $out = ($Body | ConvertTo-Json -Compress) |
        & "$Root\bin\$Arch\VclSpyInject.exe" --hwnd $Report.window.hwnd --request -
    return ($out -join '') | ConvertFrom-Json
}

function SetProp($Arch, $Report, $Name, $Value) {
    return Request $Arch $Report @{ op = 'set'; property = $Name; value = $Value }
}

function Prop($Report, $Name) {
    return $Report.control.properties | Where-Object name -eq $Name
}

# A property at any depth, by path: Font.Size, BoundsRect.Left, Panels[0].Text
function FindPath($Props, $Path) {
    foreach ($p in $Props) {
        if ($p.path -eq $Path) { return $p }
        if ($p.properties) {
            $found = FindPath $p.properties $Path
            if ($found) { return $found }
        }
    }
}

function SubProp($Report, $Path) {
    return FindPath $Report.control.properties $Path
}

function Child([IntPtr]$Parent, $Cls, $Text) {
    # PowerShell would pass $null to a string parameter as ''
    if ($null -eq $Text) { $Text = [NullString]::Value }
    $w = [Win]::FindChild($Parent, $Cls, $Text)
    if ($w -eq [IntPtr]::Zero) { throw "Child window $Cls '$Text' not found" }
    return $w
}

function Start-Target($Dir, $Title) {
    $exe = "$Root\Test\bin\$Dir\TestTarget.exe"
    $proc = Start-Process $exe -PassThru
    for ($i = 0; $i -lt 50; $i++) {
        $form = [Win]::FindWindow('TfrmTest', $Title)
        if ($form -ne [IntPtr]::Zero) { return @($proc, $form) }
        Start-Sleep -Milliseconds 100
    }
    $proc.Kill()
    throw "Window '$Title' of $exe did not appear"
}

# Memory: the memory manager a no-packages inspector should report, $null for packages
$variants = @(
    @{ Dir = '270-x86'; Arch = 'x86'; Title = 'VclSpy Test 34 x86 packages'; Memory = $null },
    @{ Dir = '270-x64'; Arch = 'x64'; Title = 'VclSpy Test 34 x64 packages'; Memory = $null },
    @{ Dir = '280-x86'; Arch = 'x86'; Title = 'VclSpy Test 35 x86 packages'; Memory = $null },
    @{ Dir = '280-x64'; Arch = 'x64'; Title = 'VclSpy Test 35 x64 packages'; Memory = $null },
    # 280 is tried first and refuses the 270 target
    @{ Dir = '270-x86-nopkg'; Arch = 'x86'; Title = 'VclSpy Test 34 x86 static'; Memory = 'own, guarded' },
    @{ Dir = '280-x86-nopkg'; Arch = 'x86'; Title = 'VclSpy Test 35 x86 static'; Memory = 'own, guarded' },
    @{ Dir = '280-x64-nopkg'; Arch = 'x64'; Title = 'VclSpy Test 35 x64 static'; Memory = 'own, guarded' },
    @{ Dir = '280-x86-sharemem'; Arch = 'x86'; Title = 'VclSpy Test 35 x86 static ShareMem'; Memory = 'borlndmm.dll' },
    @{ Dir = '280-x64-sharemem'; Arch = 'x64'; Title = 'VclSpy Test 35 x64 static ShareMem'; Memory = 'borlndmm.dll' },
    @{ Dir = '280-x86-simplesharemem'; Arch = 'x86'; Title = 'VclSpy Test 35 x86 static SimpleShareMem'; Memory = 'shared by the target' }
)

foreach ($v in $variants) {
    Write-Host "== $($v.Title)"
    $proc, $form = Start-Target $v.Dir $v.Title
    try {
        $r = Inspect $v.Arch (Child $form 'TButton' 'OK')
        Check 'ok' $r.ok $true
        if ($v.Memory) {
            CheckLike 'inspector' $r.inspector "VclSpyInspectNoPkg$($v.Dir.Substring(0, 3)).dll*"
            Check 'memory manager' $r.process.memoryManager $v.Memory
            Check 'VCL module' $r.process.vclModule 'TestTarget.exe'
        }
        Check 'button name' $r.control.name 'btnOk'
        Check 'button OnClick' ($r.control.events | Where-Object name -eq 'OnClick').handler 'TfrmTest.btnOkClick'
        Check 'button unit' $r.control.unitName 'Vcl.StdCtrls'
        Check 'form unit' $r.control.form.unitName 'TestMain'

        $r = Inspect $v.Arch (Child $form 'TPanel' 'LabelHost')
        Check 'label name' $r.control.name 'lblInfo'
        Check 'label class' $r.control.className 'TLabel'
        Check 'label resolved from' $r.resolvedFrom 'frmTest.pnlLabelHost'

        $r = Inspect $v.Arch (Child $form 'TEdit' 'Disabled edit')
        Check 'disabled edit name' $r.control.name 'edtDisabled'
        Check 'disabled edit enabled' $r.control.enabled $false

        $r = Inspect $v.Arch (Child $form 'TPanel' 'GoHost')
        Check 'speed button name' $r.control.name 'sbtnGo'
        Check 'speed button path' $r.control.path 'frmTest.fraSample.sbtnGo'
        Check 'speed button parent path' $r.control.parentPath 'frmTest.pnlHost.fraSample.pnlGoHost.sbtnGo'
        Check 'speed button OnClick' ($r.control.events | Where-Object name -eq 'OnClick').handler 'TfraSample.sbtnGoClick'
        Check 'frame owner kind' $r.control.owners[0].kind 'frame'

        # Browsing the parent tree
        Check 'speed button children' @($r.control.children).Count 0
        Check 'parent children' (($r.control.parents[0].children | ForEach-Object name) -join ',') 'sbtnGo'
        Check 'frame children' (($r.control.parents[1].children | ForEach-Object name) -join ',') 'pnlGoHost,edtFrame'
        $c = Request $v.Arch $r @{ op = 'children'; address = $r.control.parents[1].address }
        Check 'children ok' $c.ok $true
        Check 'children address' $c.address $r.control.parents[1].address
        Check 'children names' (($c.children | ForEach-Object name) -join ',') 'pnlGoHost,edtFrame'
        Check 'children childCount' ($c.children | Where-Object name -eq 'pnlGoHost').childCount 1
        $g = Request $v.Arch $r @{ op = 'get'; address = $r.control.parents[2].address }
        Check 'get parent by address' $g.control.name 'pnlHost'
        $e = Request $v.Arch $r @{ op = 'children'; address = '$1' }
        CheckLike 'children stale address error' $e.error '*no longer exists*'

        $combo = Child $form 'TComboBox' $null
        $r = Inspect $v.Arch (Child $combo 'Edit' $null)
        Check 'combo (via inner edit) name' $r.control.name 'cmbChoice'

        $r = Inspect $v.Arch (Child $form 'TButton' 'Save')
        Check 'action button name' $r.control.name 'btnAction'
        Check 'action name' $r.control.action.name 'actSave'
        Check 'action OnExecute' $r.control.action.onExecute.handler 'TfrmTest.actSaveExecute'

        $ok = Child $form 'TButton' 'OK'
        foreach ($i in 1..3) { $r = Inspect $v.Arch $ok }
        Check 'repeated pick name' $r.control.name 'btnOk'

        $other = if ($v.Arch -eq 'x86') { 'x64' } else { 'x86' }
        $r = Inspect $other $ok
        Check 'wrong-bitness injector ok' $r.ok $false
        CheckLike 'wrong-bitness injector error' $r.error "*use $($v.Arch)\VclSpyInject.exe*"

        # Editing
        $r = Inspect $v.Arch $ok
        Check 'Caption scope' (Prop $r 'Caption').scope 'published'
        Check 'Caption editable' (Prop $r 'Caption').editable $true
        Check 'Text scope (TControl, protected)' (Prop $r 'Text').scope 'protected'
        Check 'ClientWidth scope (TControl, public)' (Prop $r 'ClientWidth').scope 'public'
        Check 'Showing editable' (Prop $r 'Showing').editable $false
        Check 'Name editable' (Prop $r 'Name').editable $false
        Check 'Align values' ($r.control.types.TAlign -join ',') 'alNone,alTop,alBottom,alLeft,alRight,alClient,alCustom'

        # Hint is written straight to a field, by the inspector's code
        $hintEditable = $v.Memory -ne 'own, guarded'
        Check 'Hint editable' (Prop $r 'Hint').editable $hintEditable
        if ($hintEditable) {
            $r = SetProp $v.Arch $r 'Hint' 'A hint'
            Check 'set field-written Hint' (Prop $r 'Hint').value 'A hint'
        }
        else {
            $e = SetProp $v.Arch $r 'Hint' 'A hint'
            CheckLike 'field-written Hint error' $e.error '*memory manager*'
        }
        # The target's setter stores the string; the guarded inspector hands it a
        # copy that looks like a literal. Unpublished, the inspector's code stores it.
        $styleEditable = ((Prop $r 'StyleName').scope -eq 'published') -or $hintEditable
        Check 'StyleName editable' (Prop $r 'StyleName').editable $styleEditable
        if ($styleEditable) {
            # Delphi 10.4 recreates the window: go on with the reply's window
            $r = SetProp $v.Arch $r 'StyleName' 'Windows'
            Check 'set StyleName' (Prop $r 'StyleName').value 'Windows'
            $r = SetProp $v.Arch $r 'StyleName' ''
            Check 'clear StyleName' (Prop $r 'StyleName').value ''
        }

        $s = SetProp $v.Arch $r 'Caption' 'Changed'
        Check 'set Caption ok' $s.ok $true
        Check 'set Caption old value' $s.changed.oldValue 'OK'
        Check 'set Caption new value' $s.changed.newValue 'Changed'
        Check 'set Caption text' $s.control.text 'Changed'
        Check 'set Caption window text' ([Win]::FindChild($form, 'TButton', 'Changed').ToInt64() -eq $s.control.hwnd) $true

        $s = SetProp $v.Arch $s 'Text' 'Via Text'
        Check 'set protected Text' ([Win]::FindChild($form, 'TButton', 'Via Text').ToInt64() -eq $s.control.hwnd) $true
        $s = SetProp $v.Arch $s 'ClientWidth' '120'
        Check 'set public ClientWidth' $s.control.bounds.width 120
        $s = SetProp $v.Arch $s 'Width' ' 110 '
        Check 'set Width' $s.control.bounds.width 110
        $s = SetProp $v.Arch $s 'Anchors' '[akLeft,akBottom]'
        Check 'set Anchors' (Prop $s 'Anchors').value '[akLeft,akBottom]'
        $s = SetProp $v.Arch $s 'Enabled' 'false'
        Check 'set Enabled' (Prop $s 'Enabled').value 'False'
        $s = SetProp $v.Arch $s 'Enabled' 'True'
        # A nested type: its name has a dot
        Check 'Style type' (Prop $s 'Style').type 'TCustomButton.TButtonStyle'
        Check 'Style values' ($s.control.types.'TCustomButton.TButtonStyle' -join ',') 'bsPushButton,bsCommandLink,bsSplitButton'
        $s = SetProp $v.Arch $s 'Style' 'bsSplitButton'
        Check 'set nested enum Style' (Prop $s 'Style').value 'bsSplitButton'
        $s = SetProp $v.Arch $s 'Style' 'bsPushButton'

        $e = SetProp $v.Arch $s 'Width' 'abc'
        Check 'bad integer ok' $e.ok $false
        CheckLike 'bad integer error' $e.error '*"abc" is not an integer*'
        $e = SetProp $v.Arch $s 'Align' 'alMiddle'
        CheckLike 'bad enum error' $e.error '*Use one of: alNone, alTop*'
        $e = SetProp $v.Arch $s 'Anchors' '[akLeft,akMiddle]'
        CheckLike 'bad set error' $e.error '*not a TAnchors value*'
        $e = SetProp $v.Arch $s 'Name' 'btnOther'
        CheckLike 'Name error' $e.error '*cannot be edited*'
        $e = SetProp $v.Arch $s 'Showing' 'False'
        CheckLike 'read-only error' $e.error '*read-only*'
        $e = SetProp $v.Arch $s 'NoSuchProperty' '1'
        CheckLike 'unknown property error' $e.error '*has no property NoSuchProperty*'

        $g = Request $v.Arch $s @{ op = 'get' }
        Check 'get ok' $g.ok $true
        Check 'get width' $g.control.bounds.width 110
        $stale = [pscustomobject]@{ window = $s.window; control = [pscustomobject]@{ address = '$1' } }
        $e = Request $v.Arch $stale @{ op = 'get' }
        CheckLike 'stale address error' $e.error '*no longer exists*'

        $s = SetProp $v.Arch $s 'Caption' 'OK'
        Check 'restore Caption' $s.control.text 'OK'

        # Object properties: read-only themselves, their properties are edited
        $font = Prop $s 'Font'
        Check 'Font kind' $font.kind 'class'
        Check 'Font editable' $font.editable $false
        Check 'Font.Size path' ($font.properties | Where-Object name -eq 'Size').path 'Font.Size'
        Check 'Font.Size editable' (SubProp $s 'Font.Size').editable $true
        # Unlike TComponent.Name
        Check 'Font.Name editable' (SubProp $s 'Font.Name').editable $true
        Check 'Font.Style values' ($s.control.types.TFontStyles -join ',') 'fsBold,fsItalic,fsUnderline,fsStrikeOut'
        $s = SetProp $v.Arch $s 'Font.Size' '12'
        Check 'set Font.Size' (SubProp $s 'Font.Size').value '12'
        Check 'set Font.Size changed property' $s.changed.property 'Font.Size'
        Check 'set Font.Size old value' $s.changed.oldValue '9'
        $s = SetProp $v.Arch $s 'Font.Style' '[fsBold]'
        Check 'set Font.Style' (SubProp $s 'Font.Style').value '[fsBold]'
        $s = SetProp $v.Arch $s 'Font.Name' 'Tahoma'
        Check 'set Font.Name' (SubProp $s 'Font.Name').value 'Tahoma'
        $s = SetProp $v.Arch $s 'Margins.Left' '7'
        Check 'set Margins.Left' (SubProp $s 'Margins.Left').value '7'
        $e = SetProp $v.Arch $s 'Font' 'Arial'
        CheckLike 'set object error' $e.error '*is an object*'
        $e = SetProp $v.Arch $s 'Font.NoSuchProperty' '1'
        CheckLike 'nested unknown property error' $e.error '*Font has no property NoSuchProperty*'

        # Record properties are public: read with the getter, fields written
        # back with the setter
        $bounds = Prop $s 'BoundsRect'
        Check 'BoundsRect kind' $bounds.kind 'record'
        Check 'BoundsRect scope' $bounds.scope 'public'
        Check 'BoundsRect editable' $bounds.editable $false
        $b = $s.control.bounds
        $right = $b.left + $b.width
        $bottom = $b.top + $b.height
        Check 'BoundsRect value' $bounds.value ("(Left = $($b.left), Top = $($b.top), Right = $right, Bottom = $bottom, " +
            "TopLeft = (X = $($b.left), Y = $($b.top)), BottomRight = (X = $right, Y = $bottom))")
        Check 'BoundsRect.Left editable' (SubProp $s 'BoundsRect.Left').editable $true
        Check 'BoundsRect.Left scope' (SubProp $s 'BoundsRect.Left').scope 'field'
        Check 'ClientRect.Right editable (no setter)' (SubProp $s 'ClientRect.Right').editable $false
        $s = SetProp $v.Arch $s 'BoundsRect.Left' '20'
        Check 'set BoundsRect.Left' $s.control.bounds.left 20
        Check 'set BoundsRect.Left keeps Right' $s.control.bounds.width ($right - 20)
        $s = SetProp $v.Arch $s 'BoundsRect.TopLeft.X' '16'
        Check 'set nested record field' $s.control.bounds.left 16
        $e = SetProp $v.Arch $s 'ClientRect.Right' '50'
        CheckLike 'read-only record error' $e.error '*ClientRect is read-only*'
        $e = SetProp $v.Arch $s 'BoundsRect' '1'
        CheckLike 'set record error' $e.error '*is a record*'

        # Other components are references: not unfolded
        $r = Inspect $v.Arch (Child $form 'TButton' 'Save')
        Check 'Action not unfolded' ($null -eq (Prop $r 'Action').properties) $true
        $e = SetProp $v.Arch $r 'Action.Caption' 'Other'
        CheckLike 'component reference error' $e.error '*refers to another component, actSave*'

        # Subcomponents are
        $r = Inspect $v.Arch (Child $form 'TLabeledEdit' 'Labeled edit')
        Check 'subcomponent EditLabel.Caption' (SubProp $r 'EditLabel.Caption').value 'Labeled'
        $s = SetProp $v.Arch $r 'EditLabel.Caption' 'Label 2'
        Check 'set EditLabel.Caption' (SubProp $s 'EditLabel.Caption').value 'Label 2'

        # Collection items
        $r = Inspect $v.Arch (Child $form 'TStatusBar' $null)
        Check 'status bar name' $r.control.name 'sbMain'
        Check 'Panels item scope' (SubProp $r 'Panels[1]').scope 'item'
        Check 'Panels item value' (SubProp $r 'Panels[1]').value '(TStatusPanel) Second'
        Check 'Panels[1].Text' (SubProp $r 'Panels[1].Text').value 'Second'
        $s = SetProp $v.Arch $r 'Panels[1].Text' 'Changed panel'
        Check 'set Panels[1].Text' (SubProp $s 'Panels[1].Text').value 'Changed panel'
        $s = SetProp $v.Arch $s 'Panels[0].Width' '150'
        Check 'set Panels[0].Width' (SubProp $s 'Panels[0].Width').value '150'
        $e = SetProp $v.Arch $s 'Panels[5].Width' '1'
        CheckLike 'missing item error' $e.error '*Panels has no property*'

        # A graphic control: requests go to its parent's window
        $r = Inspect $v.Arch (Child $form 'TPanel' 'LabelHost')
        $s = SetProp $v.Arch $r 'Caption' 'Label changed'
        Check 'set label Caption' $s.control.text 'Label changed'
        $s = SetProp $v.Arch $s 'Color' 'clRed'
        Check 'set label Color by name' (Prop $s 'Color').value 'clRed'
        $s = SetProp $v.Arch $s 'Color' '$00112233'
        Check 'set label Color by number' (Prop $s 'Color').value '$00112233'
        $e = SetProp $v.Arch $s 'Color' 'clNoSuchColor'
        CheckLike 'bad color error' $e.error '*is not a color*'

        Start-Sleep -Milliseconds 300
        Check 'target exited' $proc.HasExited $false

        # The inspector stays loaded; the target must still end normally
        [void]$proc.CloseMainWindow()
        Check 'target closed' $proc.WaitForExit(8000) $true
        Check 'target exit code' $proc.ExitCode 0
    }
    finally {
        if (-not $proc.HasExited) { $proc.Kill() }
    }
}

Write-Host ''
if ($script:Failures -eq 0) { Write-Host "All $($script:Checks) checks passed." -ForegroundColor Green; exit 0 }
Write-Host "$($script:Failures) of $($script:Checks) checks failed." -ForegroundColor Red
exit 1
