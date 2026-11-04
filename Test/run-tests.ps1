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

# Sends a get/set request for the control of an earlier report, through stdin
function Request($Arch, $Report, [hashtable]$Body) {
    $Body.address = $Report.control.address
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

$variants = @(
    @{ Dir = '270-x86'; Arch = 'x86'; Title = 'VclSpy Test 34 x86 packages' },
    @{ Dir = '270-x64'; Arch = 'x64'; Title = 'VclSpy Test 34 x64 packages' },
    @{ Dir = '280-x86'; Arch = 'x86'; Title = 'VclSpy Test 35 x86 packages' },
    @{ Dir = '280-x64'; Arch = 'x64'; Title = 'VclSpy Test 35 x64 packages' }
)

foreach ($v in $variants) {
    Write-Host "== $($v.Title)"
    $proc, $form = Start-Target $v.Dir $v.Title
    try {
        $r = Inspect $v.Arch (Child $form 'TButton' 'OK')
        Check 'ok' $r.ok $true
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

        $s = SetProp $v.Arch $r 'Caption' 'Changed'
        Check 'set Caption ok' $s.ok $true
        Check 'set Caption old value' $s.changed.oldValue 'OK'
        Check 'set Caption new value' $s.changed.newValue 'Changed'
        Check 'set Caption text' $s.control.text 'Changed'
        Check 'set Caption window text' ([Win]::FindChild($form, 'TButton', 'Changed') -eq $ok) $true

        $s = SetProp $v.Arch $s 'Text' 'Via Text'
        Check 'set protected Text' ([Win]::FindChild($form, 'TButton', 'Via Text') -eq $ok) $true
        $s = SetProp $v.Arch $s 'ClientWidth' '120'
        Check 'set public ClientWidth' $s.control.bounds.width 120
        $s = SetProp $v.Arch $s 'Width' ' 110 '
        Check 'set Width' $s.control.bounds.width 110
        $s = SetProp $v.Arch $s 'Anchors' '[akLeft,akBottom]'
        Check 'set Anchors' (Prop $s 'Anchors').value '[akLeft,akBottom]'
        $s = SetProp $v.Arch $s 'Enabled' 'false'
        Check 'set Enabled' (Prop $s 'Enabled').value 'False'
        $s = SetProp $v.Arch $s 'Enabled' 'True'

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
    }
    finally {
        if (-not $proc.HasExited) { $proc.Kill() }
    }
}

Write-Host '== VclSpy Test 35 x86 static'
$proc, $form = Start-Target '280-x86-nopkg' 'VclSpy Test 35 x86 static'
try {
    $r = Inspect 'x86' (Child $form 'TButton' 'OK')
    Check 'static target ok' $r.ok $false
    CheckLike 'static target error' $r.error '*not built with Delphi runtime packages*'
}
finally {
    if (-not $proc.HasExited) { $proc.Kill() }
}

Write-Host ''
if ($script:Failures -eq 0) { Write-Host "All $($script:Checks) checks passed." -ForegroundColor Green; exit 0 }
Write-Host "$($script:Failures) of $($script:Checks) checks failed." -ForegroundColor Red
exit 1
