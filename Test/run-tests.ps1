# Starts every TestTarget and FmxTestTarget variant, inspects its controls
# through bin\<arch>\VclSpyInject.exe and checks the JSON replies. The
# variants that link VclSpy.Server (VclSpy.FmxServer) are inspected over the
# network, through bin\VclSpyRemote.exe.
# Run build.cmd first. Usage: powershell -ExecutionPolicy Bypass -File Test\run-tests.ps1
# -Only <pattern> runs the variants whose folder in Test\bin matches it (fmx-*).

param([string]$Only = '*')

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
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr wnd, uint msg, IntPtr w, IntPtr l);

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

    public static void MoveCursor(int[] pt) {
        SetThreadDpiAwarenessContext(new IntPtr(-4));
        SetCursorPos(pt[0], pt[1]);
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

function Start-Target($Dir, $Title, $Exe = 'TestTarget', $Class = 'TfrmTest') {
    $exe = "$Root\Test\bin\$Dir\$Exe.exe"
    $proc = Start-Process $exe -PassThru
    for ($i = 0; $i -lt 50; $i++) {
        $form = [Win]::FindWindow($Class, $Title)
        # The caption is set in OnCreate, before the VCL form's child windows exist
        if (($form -ne [IntPtr]::Zero) -and (($Class -ne 'TfrmTest') -or
            ([Win]::FindChild($form, 'TButton', 'OK') -ne [IntPtr]::Zero))) { return @($proc, $form) }
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
    if ($v.Dir -notlike $Only) { continue }
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
        # Public properties of objects
        Check 'Items.Count (public)' (SubProp $r 'Items.Count').value '2'
        Check 'Items.Count scope' (SubProp $r 'Items.Count').scope 'public'
        Check 'Items.Count editable' (SubProp $r 'Items.Count').editable $false
        $s = SetProp $v.Arch $r 'Items.CommaText' 'A,B,C'
        Check 'set public Items.CommaText' (SubProp $s 'Items.Count').value '3'
        Check 'set public Items.CommaText value' (SubProp $s 'Items.CommaText').value 'A,B,C'

        # Getters that change the object are not read
        $r = Inspect $v.Arch (Child $form 'TPanel' 'ImageHost')
        Check 'image name' $r.control.name 'imgIcon'
        Check 'Picture.Graphic' (SubProp $r 'Picture.Graphic').value '(TIcon)'
        Check 'Picture.Bitmap skipped' ($null -eq (SubProp $r 'Picture.Bitmap')) $true
        Check 'Picture.Icon skipped' ($null -eq (SubProp $r 'Picture.Icon')) $true
        $r = Inspect $v.Arch (Child $form 'TPanel' 'ImageHost')
        Check 'Picture.Graphic still an icon' (SubProp $r 'Picture.Graphic').value '(TIcon)'

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

        # List view and tree view items: their public properties
        $r = Inspect $v.Arch (Child $form 'TListView' $null)
        Check 'list view name' $r.control.name 'lvItems'
        Check 'list view Items' (Prop $r 'Items').value '(TListItems, Count = 2)'
        Check 'list item value' (SubProp $r 'Items[1]').value '(TListItem) Second'
        Check 'list item Caption' (SubProp $r 'Items[1].Caption').value 'Second'
        Check 'list item Caption scope' (SubProp $r 'Items[1].Caption').scope 'public'
        Check 'list item Caption editable' (SubProp $r 'Items[1].Caption').editable $true
        Check 'list item Index editable' (SubProp $r 'Items[1].Index').editable $false
        CheckLike 'list item SubItems' (SubProp $r 'Items[1].SubItems').value '*Count = 1*Two'
        $s = SetProp $v.Arch $r 'Items[1].Caption' 'Changed item'
        Check 'set list item Caption' (SubProp $s 'Items[1].Caption').value 'Changed item'
        $s = SetProp $v.Arch $s 'Items[0].ImageIndex' '3'
        Check 'set list item ImageIndex' (SubProp $s 'Items[0].ImageIndex').value '3'
        $e = SetProp $v.Arch $s 'Items[0].Index' '1'
        CheckLike 'read-only public property error' $e.error '*Index is read-only*'

        $r = Inspect $v.Arch (Child $form 'TTreeView' $null)
        Check 'tree view Items' (Prop $r 'Items').value '(TTreeNodes, Count = 3)'
        Check 'tree node Text' (SubProp $r 'Items[1].Text').value 'Child'
        Check 'tree node Level' (SubProp $r 'Items[1].Level').value '1'
        $s = SetProp $v.Arch $r 'Items[1].Text' 'Changed node'
        Check 'set tree node Text' (SubProp $s 'Items[1].Text').value 'Changed node'

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


# FireMonkey: controls have no windows. Requests go to the form's window;
# objects are found by name through "children", and picked at the center of
# the screenRect a "get" reports.

function FmxRequest($Arch, [IntPtr]$Form, [hashtable]$Body) {
    $out = ($Body | ConvertTo-Json -Compress) | & "$Root\bin\$Arch\VclSpyInject.exe" --hwnd $Form.ToInt64() --request -
    return ($out -join '') | ConvertFrom-Json
}

# The address of the object below $Address that the names lead to
function FmxFind($Arch, [IntPtr]$Form, $Address, [string[]]$Names) {
    foreach ($n in $Names) {
        $c = FmxRequest $Arch $Form @{ op = 'children'; address = $Address }
        $child = $c.children | Where-Object name -eq $n
        if (-not $child) { throw "FMX object $n not found" }
        $Address = $child.address
    }
    return $Address
}

function FmxGet($Arch, [IntPtr]$Form, $FormAddress, [string[]]$Names) {
    return FmxRequest $Arch $Form @{ op = 'get'; address = (FmxFind $Arch $Form $FormAddress $Names) }
}

function RectCenter($Rect) {
    return @([int](($Rect.left + $Rect.right) / 2), [int](($Rect.top + $Rect.bottom) / 2))
}

# Inspects the control at a physical screen point, as the finder would
function InspectAt($Arch, [IntPtr]$Wnd, [int[]]$Pt) {
    $out = & "$Root\bin\$Arch\VclSpyInject.exe" --hwnd $Wnd.ToInt64() --x $Pt[0] --y $Pt[1]
    return ($out -join '') | ConvertFrom-Json
}

function PickCenter($Arch, [IntPtr]$Wnd, $Report) {
    return InspectAt $Arch $Wnd (RectCenter $Report.control.screenRect)
}

function Close-FmxTarget($Proc, [IntPtr]$Form) {
    # WM_CLOSE to the main form
    [void][Win]::PostMessage($Form, 0x10, [IntPtr]::Zero, [IntPtr]::Zero)
    Check 'target closed' $Proc.WaitForExit(8000) $true
    Check 'target exit code' $Proc.ExitCode 0
}

# Inspector: the DLL the hook stub should load; Memory as for the VCL variants
$fmxVariants = @(
    @{ Dir = 'fmx-280-x86'; Arch = 'x86'; Title = 'VclSpy FMX Test 35 x86 packages'; Inspector = 'VclSpyInspectFmx280.dll'; Memory = $null },
    @{ Dir = 'fmx-270-x64'; Arch = 'x64'; Title = 'VclSpy FMX Test 34 x64 packages'; Inspector = 'VclSpyInspectFmx270.dll'; Memory = $null },
    @{ Dir = 'fmx-280-x64-nopkg'; Arch = 'x64'; Title = 'VclSpy FMX Test 35 x64 static'; Inspector = 'VclSpyInspectFmxNoPkg280.dll'; Memory = 'own, guarded' },
    # 280 is tried first and refuses the 270 target
    @{ Dir = 'fmx-270-x86-nopkg'; Arch = 'x86'; Title = 'VclSpy FMX Test 34 x86 static'; Inspector = 'VclSpyInspectFmxNoPkg270.dll'; Memory = 'own, guarded' },
    @{ Dir = 'fmx-280-x86-sharemem'; Arch = 'x86'; Title = 'VclSpy FMX Test 35 x86 static ShareMem'; Inspector = 'VclSpyInspectFmxNoPkg280.dll'; Memory = 'borlndmm.dll' },
    @{ Dir = 'fmx-280-x64-simplesharemem'; Arch = 'x64'; Title = 'VclSpy FMX Test 35 x64 static SimpleShareMem'; Inspector = 'VclSpyInspectFmxNoPkg280.dll'; Memory = 'shared by the target' }
)

foreach ($v in $fmxVariants) {
    if ($v.Dir -notlike $Only) { continue }
    Write-Host "== $($v.Title)"
    $proc, $form = Start-Target $v.Dir $v.Title 'FmxTestTarget' 'FMTfrmFmxTest'
    try {
        $a = $v.Arch
        $f = FmxRequest $a $form @{ op = 'forms' }
        Check 'forms ok' $f.ok $true
        CheckLike 'inspector' $f.inspector "$($v.Inspector)*"
        Check 'framework' $f.process.framework 'FMX'
        if ($v.Memory) { Check 'memory manager' $f.process.memoryManager $v.Memory }
        $fi = $f.forms | Where-Object name -eq 'frmFmxTest'
        Check 'form className' $fi.className 'TfrmFmxTest'
        Check 'form caption' $fi.caption $v.Title
        Check 'form hwnd' $fi.hwnd $form.ToInt64()
        $fa = $fi.address

        $r = FmxRequest $a $form @{ op = 'get'; address = $fa }
        Check 'get form' $r.control.path 'frmFmxTest'
        Check 'form text' $r.control.text $v.Title
        Check 'form window' $r.window.hwnd $form.ToInt64()
        Check 'form style object' (@($r.control.children | Where-Object style).Count) 1
        if ($v.Memory) { Check 'FMX module' $r.process.fmxModule 'FmxTestTarget.exe' }
        else { CheckLike 'FMX package' $r.process.fmxPackage 'fmx2?0.bpl' }

        # Picking: dp to pixels and back
        $ok = FmxGet $a $form $fa 'btnOk'
        Check 'button text' $ok.control.text 'OK'
        Check 'button bounds' "$($ok.control.bounds.left),$($ok.control.bounds.top),$($ok.control.bounds.width),$($ok.control.bounds.height)" '16,16,100,28'
        $sr = $ok.control.screenRect
        $scale = ($sr.right - $sr.left) / 100
        Check 'button height in pixels' ([math]::Abs(($sr.bottom - $sr.top) - 28 * $scale) -le 1) $true
        $lbl = FmxGet $a $form $fa 'lblInfo'
        Check 'label offset in pixels' ([math]::Abs(($lbl.control.screenRect.left - $sr.left) - 116 * $scale) -le 1) $true
        $p = PickCenter $a $form $ok
        Check 'pick ok' $p.ok $true
        Check 'pick button' $p.control.name 'btnOk'
        Check 'pick button address' $p.control.address $ok.control.address
        Check 'pick resolved from' $p.resolvedFrom 'frmFmxTest'
        Check 'button OnClick' ($p.control.events | Where-Object name -eq 'OnClick').handler 'TfrmFmxTest.btnOkClick'
        Check 'button unit' $p.control.unitName 'FMX.StdCtrls'
        Check 'form unit' $p.control.form.unitName 'FmxTestMain'
        Check 'form caption' $p.control.form.caption $v.Title
        $style = @($p.control.children | Where-Object style)
        Check 'button style object' $style.Count 1
        $g = FmxRequest $a $form @{ op = 'get'; address = $style[0].address }
        Check 'get style object' $g.control.style $true
        Check 'style object parents' $g.control.parents[0].name 'btnOk'
        $p = PickCenter $a $form $lbl
        Check 'pick label (HitTest off)' $p.control.name 'lblInfo'
        Check 'label class' $p.control.className 'TLabel'

        $e = FmxGet $a $form $fa 'edtDisabled'
        $p = PickCenter $a $form $e
        Check 'pick disabled edit' $p.control.name 'edtDisabled'
        Check 'disabled edit enabled' $p.control.enabled $false

        # A frame
        $go = FmxGet $a $form $fa 'lytHost', 'fraSample', 'rctGoHost', 'sbtnGo'
        $p = PickCenter $a $form $go
        Check 'speed button name' $p.control.name 'sbtnGo'
        Check 'speed button path' $p.control.path 'frmFmxTest.fraSample.sbtnGo'
        Check 'speed button parent path' $p.control.parentPath 'frmFmxTest.lytHost.fraSample.rctGoHost.sbtnGo'
        Check 'speed button OnClick' ($p.control.events | Where-Object name -eq 'OnClick').handler 'TfraFmxSample.sbtnGoClick'
        Check 'frame owner kind' $p.control.owners[0].kind 'frame'
        Check 'parent children' (($p.control.parents[0].children | ForEach-Object name) -join ',') 'sbtnGo'
        Check 'frame children' (($p.control.parents[1].children | ForEach-Object name) -join ',') 'rctGoHost,edtFrame'
        $c = FmxRequest $a $form @{ op = 'children'; address = $p.control.parents[1].address }
        Check 'children names' (($c.children | ForEach-Object name) -join ',') 'rctGoHost,edtFrame'
        Check 'get parent by address' (FmxRequest $a $form @{ op = 'get'; address = $p.control.parents[2].address }).control.name 'lytHost'
        $x = FmxRequest $a $form @{ op = 'children'; address = '$1' }
        CheckLike 'stale address error' $x.error '*no longer exists*'

        # A list box item, inside the list box's content
        $lst = FmxGet $a $form $fa 'lstItems'
        $lr = $lst.control.screenRect
        $p = InspectAt $a $form @([int](($lr.left + $lr.right) / 2), [int]($lr.top + 8 * $scale))
        Check 'pick list box item' $p.control.className 'TListBoxItem'
        Check 'list box item text' $p.control.text 'First'

        # An action
        $p = PickCenter $a $form (FmxGet $a $form $fa 'btnAction')
        Check 'action button text' $p.control.text 'Save'
        Check 'action name' $p.control.action.name 'actSave'
        Check 'action OnExecute' $p.control.action.onExecute.handler 'TfrmFmxTest.actSaveExecute'

        # Editing
        $r = $ok
        Check 'Text editable' (Prop $r 'Text').editable $true
        Check 'Name editable' (Prop $r 'Name').editable $false
        Check 'AbsoluteRect kind' (Prop $r 'AbsoluteRect').kind 'record'
        Check 'AbsoluteRect scope' (Prop $r 'AbsoluteRect').scope 'public'
        Check 'AbsoluteRect value' (Prop $r 'AbsoluteRect').value ('(Left = 16, Top = 16, Right = 116, Bottom = 44, ' +
            'TopLeft = (X = 16, Y = 16), BottomRight = (X = 116, Y = 44))')
        Check 'AbsoluteRect.Left editable' (SubProp $r 'AbsoluteRect.Left').editable $false
        Check 'ParentedVisible (public)' (Prop $r 'ParentedVisible').value 'True'
        Check 'Canvas skipped' ($null -eq (Prop $r 'Canvas')) $true
        Check 'Data skipped' ($null -eq (Prop $r 'Data')) $true
        Check 'Align values' (@($r.control.types.TAlignLayout) -contains 'Client') $true
        $s = SetProp $a $r 'Text' 'Changed'
        Check 'set Text ok' $s.ok $true
        Check 'set Text old value' $s.changed.oldValue 'OK'
        Check 'set Text new value' $s.changed.newValue 'Changed'
        Check 'set Text text' $s.control.text 'Changed'
        $s = SetProp $a $s 'Position.X' '20'
        Check 'set Position.X' $s.control.bounds.left 20
        $s = SetProp $a $s 'Width' '110.5'
        Check 'set Width' $s.control.bounds.width 110.5
        $s = SetProp $a $s 'BoundsRect.Left' '24'
        Check 'set BoundsRect.Left' $s.control.bounds.left 24
        $s = SetProp $a $s 'Opacity' '0.5'
        Check 'set Opacity' (Prop $s 'Opacity').value '0.5'
        # The button's Font is TextSettings.Font, and reached through other paths too: its
        # members are listed once, below the first
        $s = SetProp $a $s 'TextSettings.Font.Size' '14'
        Check 'set TextSettings.Font.Size' $s.changed.newValue '14'
        CheckLike 'Font' (Prop $s 'Font').value '(TSettingsFont) *, 14'
        $s = SetProp $a $s 'Cursor' 'crHandPoint'
        Check 'set Cursor by name' (Prop $s 'Cursor').value 'crHandPoint'
        $s = SetProp $a $s 'Enabled' 'False'
        Check 'set Enabled' (Prop $s 'Enabled').value 'False'
        $s = SetProp $a $s 'Enabled' 'True'
        $e = SetProp $a $s 'Width' 'abc'
        CheckLike 'bad number error' $e.error '*"abc" is not a number*'
        $e = SetProp $a $s 'Align' 'Middle'
        CheckLike 'bad enum error' $e.error '*Use one of:*Client*'
        $e = SetProp $a $s 'Name' 'btnOther'
        CheckLike 'Name error' $e.error '*cannot be edited*'
        $e = SetProp $a $s 'AbsoluteRect.Left' '1'
        CheckLike 'read-only record error' $e.error '*AbsoluteRect is read-only*'
        $e = SetProp $a $s 'NoSuchProperty' '1'
        CheckLike 'unknown property error' $e.error '*has no property NoSuchProperty*'
        $s = SetProp $a $s 'Text' 'OK'
        Check 'restore Text' $s.control.text 'OK'

        # Colors
        $rc = FmxGet $a $form $fa 'rctColor'
        Check 'Fill' (Prop $rc 'Fill').value '(TBrush) Solid, Yellow'
        Check 'Fill.Color' (SubProp $rc 'Fill.Color').value 'Yellow'
        Check 'color values' (@($rc.control.types.TAlphaColor) -contains 'Red') $true
        $s = SetProp $a $rc 'Fill.Color' 'Red'
        Check 'set color by name' (SubProp $s 'Fill.Color').value 'Red'
        $s = SetProp $a $s 'Fill.Color' 'claBlue'
        Check 'set color by cla name' (SubProp $s 'Fill.Color').value 'Blue'
        $s = SetProp $a $s 'Fill.Color' '#FF112233'
        Check 'set color by number' (SubProp $s 'Fill.Color').value '#FF112233'
        $e = SetProp $a $s 'Fill.Color' 'NoSuchColor'
        CheckLike 'bad color error' $e.error '*is not a color*'

        if ($v.Memory -eq 'shared by the target') {
            # The inspector must finalize itself before the exe frees the memory manager it
            # shares: when the last window closes. A minimized FMX application hides its form,
            # and may be closed so.
            $m = FmxRequest $a $form @{ op = 'set'; address = $fa; property = 'WindowState'; value = 'wsMinimized' }
            Check 'minimize' $m.ok $true
            Start-Sleep -Milliseconds 300
            Check 'request while minimized' (FmxRequest $a $form @{ op = 'get'; address = $fa }).ok $true
        }

        Start-Sleep -Milliseconds 300
        Check 'target exited' $proc.HasExited $false
        Close-FmxTarget $proc $form
    }
    finally {
        if (-not $proc.HasExited) { $proc.Kill() }
    }
}


# Sends requests, one per line, to the VclSpy.Server whose description has
# $Server, and returns the replies
function Remote($Server, $Password, [object[]]$Bodies) {
    $lines = ($Bodies | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join "`n"
    $out = $lines | & "$Root\bin\VclSpyRemote.exe" --server $Server --hosts 127.0.0.1 --password $Password --request -
    return @($out | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

$remoteVariants = @(
    @{ Dir = '280-x86-server'; Title = 'VclSpy Test 35 x86 static server' },
    @{ Dir = '280-x64-server-pkg'; Title = 'VclSpy Test 35 x64 packages server' },
    @{ Dir = '270-x64-server'; Title = 'VclSpy Test 34 x64 static server' }
)

foreach ($v in $remoteVariants) {
    if ($v.Dir -notlike $Only) { continue }
    Write-Host "== $($v.Title) (remote)"
    $password = "pw-$($v.Dir)"
    $env:VCLSPY_PASSWORD = $password
    try { $proc, $form = Start-Target $v.Dir $v.Title }
    finally { Remove-Item Env:VCLSPY_PASSWORD }
    try {
        $server = "PID $($proc.Id),"
        $ok = Child $form 'TButton' 'OK'

        $e = Remote $server 'wrong' @(@{ op = 'forms' })
        CheckLike 'wrong password error' $e[0].error '*refused the password*'

        [Win]::MoveCursor([Win]::Center($ok))
        $pt = [Win]::Center((Child $form 'TPanel' 'LabelHost'))
        $r = Remote $server $password @(
            @{ op = 'forms' },
            @{ op = 'pick' },
            @{ op = 'pick'; x = $pt[0]; y = $pt[1] },
            @{ op = 'pick'; x = -99999; y = -99999 })
        Check 'replies' $r.Count 4
        Check 'forms ok' $r[0].ok $true
        CheckLike 'forms inspector' $r[0].inspector 'VclSpy.Server in TestTarget.exe*'
        Check 'forms pid' $r[0].process.pid $proc.Id
        Check 'forms computer' $r[0].process.computer $env:COMPUTERNAME
        $f = $r[0].forms | Where-Object name -eq 'frmTest'
        Check 'form className' $f.className 'TfrmTest'
        Check 'form caption' $f.caption $v.Title
        Check 'form hwnd' $f.hwnd $form.ToInt64()
        Check 'form childCount' ($f.childCount -gt 0) $true
        Check 'pick at cursor' $r[1].control.path 'frmTest.btnOk'
        Check 'pick graphic control' $r[2].control.className 'TLabel'
        CheckLike 'pick outside' $r[3].error '*no window at -99999, -99999*'

        $btn = $r[1]
        $r = Remote $server $password @(
            @{ op = 'get'; address = $f.address },
            @{ op = 'set'; address = $btn.control.address; hwnd = $btn.window.hwnd; property = 'Caption'; value = 'Remote OK' },
            @{ op = 'set'; address = $btn.control.address; property = 'Font.Size'; value = '13' },
            @{ op = 'children'; address = $f.address },
            @{ op = 'set'; address = $btn.control.address; property = 'Tag'; value = 'x' },
            @{ op = 'get'; address = '$1' })
        Check 'replies' $r.Count 6
        Check 'get form' $r[0].control.name 'frmTest'
        CheckLike 'get form properties' $r[0].control.properties.Count '[1-9]*'
        Check 'set Caption' $r[1].changed.newValue 'Remote OK'
        Check 'set Caption text' $r[1].control.text 'Remote OK'
        Check 'set Font.Size' (SubProp $r[2] 'Font.Size').value '13'
        Check 'children has OK' (@($r[3].children | Where-Object name -eq 'btnOk').Count) 1
        CheckLike 'bad value error' $r[4].error '*Cannot set Tag*'
        CheckLike 'stale address error' $r[5].error '*no longer exists*'

        Start-Sleep -Milliseconds 300
        Check 'target exited' $proc.HasExited $false
        [void]$proc.CloseMainWindow()
        Check 'target closed' $proc.WaitForExit(8000) $true
        Check 'target exit code' $proc.ExitCode 0
    }
    finally {
        if (-not $proc.HasExited) { $proc.Kill() }
    }
}

$remoteFmxVariants = @(
    @{ Dir = 'fmx-280-x86-server'; Title = 'VclSpy FMX Test 35 x86 static server' },
    @{ Dir = 'fmx-270-x64-server-pkg'; Title = 'VclSpy FMX Test 34 x64 packages server' }
)

foreach ($v in $remoteFmxVariants) {
    if ($v.Dir -notlike $Only) { continue }
    Write-Host "== $($v.Title) (remote)"
    $password = "pw-$($v.Dir)"
    $env:VCLSPY_PASSWORD = $password
    try { $proc, $form = Start-Target $v.Dir $v.Title 'FmxTestTarget' 'FMTfrmFmxTest' }
    finally { Remove-Item Env:VCLSPY_PASSWORD }
    try {
        $server = "PID $($proc.Id),"
        # FMX starts the server later than the VCL: wait until it can be found
        for ($i = 0; $i -lt 40; $i++) {
            $list = & "$Root\bin\VclSpyRemote.exe" --list --hosts 127.0.0.1
            if ("$list" -like "*$server*") { break }
            Start-Sleep -Milliseconds 250
        }
        $e = Remote $server 'wrong' @(@{ op = 'forms' })
        CheckLike 'wrong password error' $e[0].error '*refused the password*'
        $r = Remote $server $password @(@{ op = 'forms' })
        Check 'forms ok' $r[0].ok $true
        CheckLike 'forms inspector' $r[0].inspector 'VclSpy.Server in FmxTestTarget.exe*'
        Check 'forms framework' $r[0].process.framework 'FMX'
        Check 'forms computer' $r[0].process.computer $env:COMPUTERNAME
        $f = $r[0].forms | Where-Object name -eq 'frmFmxTest'
        Check 'form caption' $f.caption $v.Title
        Check 'form hwnd' $f.hwnd $form.ToInt64()

        $r = Remote $server $password @(@{ op = 'children'; address = $f.address })
        $ok = $r[0].children | Where-Object name -eq 'btnOk'
        $r = Remote $server $password @(@{ op = 'get'; address = $ok.address })
        $pt = RectCenter $r[0].control.screenRect
        $r = Remote $server $password @(
            @{ op = 'pick'; x = $pt[0]; y = $pt[1] },
            @{ op = 'set'; address = $ok.address; hwnd = $f.hwnd; property = 'Text'; value = 'Remote OK' },
            @{ op = 'set'; address = $ok.address; property = 'TextSettings.Font.Size'; value = '13' },
            @{ op = 'set'; address = $ok.address; property = 'Tag'; value = 'x' },
            @{ op = 'get'; address = '$1' })
        Check 'replies' $r.Count 5
        Check 'pick at point' $r[0].control.path 'frmFmxTest.btnOk'
        Check 'set Text' $r[1].changed.newValue 'Remote OK'
        Check 'set Text text' $r[1].control.text 'Remote OK'
        Check 'set Font.Size' $r[2].changed.newValue '13'
        CheckLike 'bad value error' $r[3].error '*Cannot set Tag*'
        CheckLike 'stale address error' $r[4].error '*no longer exists*'

        Start-Sleep -Milliseconds 300
        Check 'target exited' $proc.HasExited $false
        Close-FmxTarget $proc $form
    }
    finally {
        if (-not $proc.HasExited) { $proc.Kill() }
    }
}

Write-Host ''
if ($script:Failures -eq 0) { Write-Host "All $($script:Checks) checks passed." -ForegroundColor Green; exit 0 }
Write-Host "$($script:Failures) of $($script:Checks) checks failed." -ForegroundColor Red
exit 1
