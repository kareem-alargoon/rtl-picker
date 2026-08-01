# RTL Picker -- desktop companion (Windows)
#
# A hotkey cannot restyle another app's window, so this works two ways.
#
# For text you CAN edit, it wraps the selection in Unicode bidi control
# characters (U+202B ... U+202C). Any app implementing the Unicode bidirectional
# algorithm -- Chromium and therefore every Electron app, Word, Notepad, Slack,
# browsers -- lays that run out right-to-left, and the direction survives copy,
# paste and send.
#
# For text you CANNOT edit -- a chat reply, a transcript, a rendered page --
# there is nothing to paste into, so instead the selection is copied and shown
# in our own reader window, laid out right-to-left. The source app is never
# touched.
#
#   Ctrl+Alt+D        read the selection in an RTL window  (works ANYWHERE)
#   Ctrl+Alt+R        wrap the selected text as RTL        (editable fields)
#   Ctrl+Alt+L        strip direction marks back out       (editable fields)
#   Ctrl+Alt+B        wrap whatever is on the clipboard
#   Ctrl+Alt+Shift+R  native paragraph direction -> RTL    (Word/WordPad/Outlook)
#   Ctrl+Alt+Shift+L  native paragraph direction -> LTR    (Word/WordPad/Outlook)
#
# Any key already owned by another app falls back to an alternative; the tray
# menu and the log always show the key that actually won.
#
# Run with -SelfTest to check the helpers without starting the tray app.

param([switch]$SelfTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class RtlHotkeyWindow : NativeWindow, IDisposable
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int WM_HOTKEY = 0x0312;
    private int maxId = 0;

    public event Action<int> HotkeyPressed;

    public RtlHotkeyWindow()
    {
        CreateHandle(new CreateParams());
    }

    // MOD_ALT 1, MOD_CONTROL 2, MOD_SHIFT 4, MOD_WIN 8, MOD_NOREPEAT 0x4000
    public bool Register(int id, uint modifiers, uint virtualKey)
    {
        if (id > maxId) maxId = id;
        return RegisterHotKey(Handle, id, modifiers | 0x4000, virtualKey);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            Action<int> handler = HotkeyPressed;
            if (handler != null) handler((int)m.WParam);
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        for (int i = 1; i <= maxId; i++) UnregisterHotKey(Handle, i);
        DestroyHandle();
    }
}

public static class RtlKeys
{
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int count);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    private const uint KEYUP = 0x0002;

    public const byte VK_CONTROL = 0x11;
    public const byte VK_SHIFT   = 0x10;
    public const byte VK_LSHIFT  = 0xA0;
    public const byte VK_RSHIFT  = 0xA1;
    public const byte VK_MENU    = 0x12;

    private static void Down(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); }
    private static void Up(byte vk)   { keybd_event(vk, 0, KEYUP, UIntPtr.Zero); }

    /// The hotkey chord is still physically held when we fire; synthesizing a
    /// new chord on top of Ctrl+Alt produces garbage unless we clear it first.
    public static void ReleaseModifiers()
    {
        Up(VK_MENU); Up(VK_CONTROL); Up(VK_SHIFT); Up(VK_LSHIFT); Up(VK_RSHIFT);
        System.Threading.Thread.Sleep(40);
    }

    /// Windows' built-in paragraph direction shortcut. RichEdit only.
    public static void SetParagraphDirection(bool rightToLeft)
    {
        ReleaseModifiers();
        byte shift = rightToLeft ? VK_RSHIFT : VK_LSHIFT;
        Down(VK_CONTROL); Down(shift);
        System.Threading.Thread.Sleep(25);
        Up(shift); Up(VK_CONTROL);
    }

    public static void CtrlKey(byte vk)
    {
        Down(VK_CONTROL); Down(vk);
        System.Threading.Thread.Sleep(25);
        Up(vk); Up(VK_CONTROL);
    }

    /// Used only for the log, so a failed action can be traced to a target.
    public static string DescribeForegroundWindow()
    {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return "(none)";
        System.Text.StringBuilder title = new System.Text.StringBuilder(256);
        System.Text.StringBuilder cls = new System.Text.StringBuilder(256);
        GetWindowText(h, title, title.Capacity);
        GetClassName(h, cls, cls.Capacity);
        uint pid; GetWindowThreadProcessId(h, out pid);
        string name = "?";
        try { name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { }
        return name + " [" + cls.ToString() + "] \"" + title.ToString() + "\"";
    }
}

/// A toast that never steals focus -- critical, because taking focus would
/// break the very selection we are about to copy from.
public class RtlToast : Form
{
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            return cp;
        }
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Text.RegularExpressions

# -------------------------------------------------------------------- logging

$logDir = Join-Path $env:LOCALAPPDATA 'RTLPicker'
$logFile = Join-Path $logDir 'rtlpicker.log'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    try {
        $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    } catch { }
}

<#
  Renders a string for the log: length, how many bidi marks it already carries,
  and the first few characters escaped, so non-Latin text survives the log file
  and an unexpected value (a lone newline, a stale clipboard) is obvious.
#>
function Describe-Text {
    param([string]$Text)
    if ($null -eq $Text) { return '<null>' }
    if ($Text.Length -eq 0) { return '<empty>' }
    $marks = 0
    foreach ($c in $Text.ToCharArray()) { if ($BidiChars -contains $c) { $marks++ } }
    $head = $Text.Substring(0, [Math]::Min(36, $Text.Length))
    $esc = -join ($head.ToCharArray() | ForEach-Object {
            $n = [int]$_
            if ($n -lt 32 -or $n -gt 126) { '\u{0:X4}' -f $n } else { [string]$_ }
        })
    return "len=$($Text.Length) marks=$marks head='$esc'"
}

# ---------------------------------------------------------------- bidi marks

$RLE = [char]0x202B  # right-to-left embedding
$PDF = [char]0x202C  # pop directional formatting
$BidiChars = [char[]]@(0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x200E, 0x200F, 0x2066, 0x2067, 0x2068, 0x2069)

$script:WrapPerLine = $true

function Unwrap-Rtl {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Text.ToCharArray()) {
        if ($BidiChars -notcontains $c) { [void]$sb.Append($c) }
    }
    return $sb.ToString()
}

function Wrap-Rtl {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $clean = Unwrap-Rtl $Text
    if (-not $script:WrapPerLine) { return "$RLE$clean$PDF" }

    $parts = [regex]::Split($clean, '(\r\n|\r|\n)')
    $out = New-Object System.Text.StringBuilder
    foreach ($part in $parts) {
        if ($part -eq '' -or $part -match '^(\r\n|\r|\n)$') { [void]$out.Append($part) }
        else { [void]$out.Append("$RLE$part$PDF") }
    }
    return $out.ToString()
}

# ------------------------------------------------------------------ clipboard

function Get-ClipboardText {
    for ($i = 0; $i -lt 8; $i++) {
        try {
            if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                return [System.Windows.Forms.Clipboard]::GetText()
            }
            return $null
        } catch { Start-Sleep -Milliseconds 60 }
    }
    return $null
}

function Set-ClipboardText {
    param([string]$Text)
    for ($i = 0; $i -lt 8; $i++) {
        # The clipboard is a shared, lockable resource -- another app may hold it.
        try { [System.Windows.Forms.Clipboard]::SetText($Text); return $true } catch { Start-Sleep -Milliseconds 60 }
    }
    return $false
}

function Clear-Clipboard {
    for ($i = 0; $i -lt 8; $i++) {
        try { [System.Windows.Forms.Clipboard]::Clear(); return $true } catch { Start-Sleep -Milliseconds 60 }
    }
    return $false
}

<#
  Copy the selection, transform it, paste it back, then restore whatever the
  user had on the clipboard before.
#>
function Transform-Selection {
    param([scriptblock]$Transform, [string]$Label)

    $target = [RtlKeys]::DescribeForegroundWindow()
    Write-Log "action '$Label' -> $target"

    [RtlKeys]::ReleaseModifiers()
    $original = Get-ClipboardText

    [void](Clear-Clipboard)
    [RtlKeys]::CtrlKey(0x43)   # Ctrl+C

    # Electron can take a while to service the copy; poll for up to a second.
    $selected = $null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 50
        $selected = Get-ClipboardText
        if (-not [string]::IsNullOrEmpty($selected)) { break }
    }
    Write-Log "  copied: $(Describe-Text $selected)"

    if ([string]::IsNullOrEmpty($selected)) {
        if ($original) { [void](Set-ClipboardText $original) }
        Write-Log '  -> nothing captured; the app did not answer Ctrl+C'
        Show-Toast 'Nothing selected' 'Select the text first, then press the shortcut.'
        return
    }

    if ([string]::IsNullOrWhiteSpace($selected)) {
        if ($original) { [void](Set-ClipboardText $original) }
        Write-Log '  -> selection is whitespace only'
        Show-Toast 'Nothing to change' 'The selection has no text in it.'
        return
    }

    $result = & $Transform $selected
    Write-Log "  result: $(Describe-Text $result)"

    # Ordinal, NOT -ceq. PowerShell's -ceq is case-sensitive but still culture
    # sensitive, and bidi controls carry zero collation weight -- so a linguistic
    # comparison reports wrapped and unwrapped text as equal and silently
    # discards the whole transform.
    if ([string]::Equals($result, $selected, [System.StringComparison]::Ordinal)) {
        if ($original) { [void](Set-ClipboardText $original) }
        Write-Log '  -> unchanged; text was already in that state'
        Show-Toast 'Already in that state' 'Ctrl+Alt+L removes the marks first.'
        return
    }

    if (-not (Set-ClipboardText $result)) {
        Write-Log '  -> clipboard write failed'
        Show-Toast 'Clipboard busy' 'Another app is holding the clipboard. Try again.'
        return
    }

    [RtlKeys]::CtrlKey(0x56)   # Ctrl+V
    Start-Sleep -Milliseconds 300

    # If the target was read-only the paste is silently dropped, and the only
    # honest thing we can do is say the marked-up text is on the clipboard.
    if ($original) { [void](Set-ClipboardText $original) }
    Write-Log "  -> pasted $($selected.Length) chars into $target"
    Show-Toast $Label "$($selected.Length) characters. Nothing changed? The box may be read-only."
}

function Convert-Clipboard {
    param([scriptblock]$Transform, [string]$Label)
    $text = Get-ClipboardText
    if ([string]::IsNullOrEmpty($text)) {
        Show-Toast 'Clipboard is empty' 'Copy some text first.'
        return
    }
    if (Set-ClipboardText (& $Transform $text)) {
        Write-Log "clipboard converted: $Label"
        Show-Toast $Label 'Paste it anywhere.'
    }
}

function Set-ParagraphDirection {
    param([bool]$RightToLeft, [string]$Label)
    $target = [RtlKeys]::DescribeForegroundWindow()
    Write-Log "native direction ($Label) -> $target"
    [RtlKeys]::SetParagraphDirection($RightToLeft)
    Show-Toast $Label 'Only works in Word, WordPad and Outlook.'
}

# --------------------------------------------------------------------- toast

$toast = New-Object RtlToast
$toast.FormBorderStyle = 'None'
$toast.ShowInTaskbar = $false
$toast.TopMost = $true
$toast.StartPosition = 'Manual'
$toast.BackColor = [System.Drawing.Color]::FromArgb(20, 22, 26)
$toast.Size = New-Object System.Drawing.Size(340, 74)

$toastTitle = New-Object System.Windows.Forms.Label
$toastTitle.ForeColor = [System.Drawing.Color]::White
$toastTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$toastTitle.Location = New-Object System.Drawing.Point(14, 12)
$toastTitle.Size = New-Object System.Drawing.Size(312, 20)
$toast.Controls.Add($toastTitle)

$toastBody = New-Object System.Windows.Forms.Label
$toastBody.ForeColor = [System.Drawing.Color]::FromArgb(154, 163, 174)
$toastBody.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$toastBody.Location = New-Object System.Drawing.Point(14, 36)
$toastBody.Size = New-Object System.Drawing.Size(312, 30)
$toast.Controls.Add($toastBody)

$toastTimer = New-Object System.Windows.Forms.Timer
$toastTimer.Interval = 1600
$toastTimer.add_Tick({ $toastTimer.Stop(); $toast.Hide() })

<#
  Balloon tips get swallowed by Focus Assist and notification settings, which
  is exactly how this tool ends up looking broken. Draw our own instead.
#>
function Show-Toast {
    param([string]$Title, [string]$Body)
    try {
        $toastTitle.Text = $Title
        $toastBody.Text = $Body
        $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $toast.Location = New-Object System.Drawing.Point(
            ($area.Right - $toast.Width - 18), ($area.Bottom - $toast.Height - 18))
        $toast.Show()
        $toast.BringToFront()
        $toastTimer.Stop()
        $toastTimer.Start()
    } catch {
        Write-Log "toast failed: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------- compose box

$script:composeForm = $null

function Show-ComposeWindow {
    if ($script:composeForm -and -not $script:composeForm.IsDisposed) {
        $script:composeForm.Show(); $script:composeForm.Activate(); return
    }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'RTL Picker -- compose'
    $f.Size = New-Object System.Drawing.Size(560, 340)
    $f.StartPosition = 'CenterScreen'
    $f.TopMost = $true

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ScrollBars = 'Vertical'
    $box.Dock = 'Fill'
    $box.RightToLeft = 'Yes'
    $box.Font = New-Object System.Drawing.Font('Segoe UI', 13)
    # Arabic sample spelled out in code points so this file stays pure ASCII.
    $box.Text = [string]::Join('', [char[]]@(0x0627, 0x0643, 0x062A, 0x0628, 0x0020, 0x0647, 0x0646, 0x0627))
    $f.Controls.Add($box)

    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Bottom'
    $bar.Height = 44
    $bar.Padding = New-Object System.Windows.Forms.Padding(6)
    $f.Controls.Add($bar)

    $copyRtl = New-Object System.Windows.Forms.Button
    $copyRtl.Text = 'Copy as RTL'
    $copyRtl.Width = 110
    $copyRtl.add_Click({
            if (Set-ClipboardText (Wrap-Rtl $box.Text)) {
                Show-Toast 'Copied as RTL' 'Paste it into any app.'
            }
        })
    [void]$bar.Controls.Add($copyRtl)

    $copyPlain = New-Object System.Windows.Forms.Button
    $copyPlain.Text = 'Copy plain'
    $copyPlain.Width = 90
    $copyPlain.add_Click({ [void](Set-ClipboardText (Unwrap-Rtl $box.Text)) })
    [void]$bar.Controls.Add($copyPlain)

    $paste = New-Object System.Windows.Forms.Button
    $paste.Text = 'Paste'
    $paste.Width = 70
    $paste.add_Click({ $t = Get-ClipboardText; if ($t) { $box.Text = Unwrap-Rtl $t } })
    [void]$bar.Controls.Add($paste)

    $clear = New-Object System.Windows.Forms.Button
    $clear.Text = 'Clear'
    $clear.Width = 70
    $clear.add_Click({ $box.Clear() })
    [void]$bar.Controls.Add($clear)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Type here, then Copy as RTL.'
    $hint.AutoSize = $true
    $hint.Padding = New-Object System.Windows.Forms.Padding(10, 8, 0, 0)
    $hint.ForeColor = [System.Drawing.Color]::Gray
    [void]$bar.Controls.Add($hint)

    # Keep the instance alive so the sample text and size persist.
    $f.add_FormClosing({ param($s, $e) $e.Cancel = $true; $s.Hide() })

    $script:composeForm = $f
    $f.Show()
}

# ----------------------------------------------------------------- tray icon

function Get-AppIcon {
    $png = Join-Path $PSScriptRoot '..\extension\icons\icon32.png'
    if (Test-Path $png) {
        try {
            $bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $png).Path)
            return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
        } catch { }
    }
    return [System.Drawing.SystemIcons]::Application
}

# ---------------------------------------------------------------- rtl reader

<#
  The answer to read-only text. Claude's replies, a rendered page and a chat
  transcript can't be edited, so instead of trying to change them we copy the
  selection and show it in our own window, laid out right-to-left. Nothing in
  the source app is touched.
#>

# Same ratio test the browser extension uses: count strong characters on both
# sides rather than trusting the first one.
$RtlRange = '[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]'
$LtrRange = '[A-Za-z\u00C0-\u02AF\u0370-\u04FF\u1E00-\u1FFF\u3040-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]'

function Get-TextDirection {
    param([string]$Text, [double]$Threshold = 0.25)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 'ltr' }
    $rtl = ([regex]::Matches($Text, $RtlRange)).Count
    $ltr = ([regex]::Matches($Text, $LtrRange)).Count
    if (($rtl + $ltr) -eq 0) { return 'ltr' }
    if (($rtl / ($rtl + $ltr)) -ge $Threshold) { return 'rtl' } else { return 'ltr' }
}

$script:readerForm = $null
$script:readerBox = $null
$script:readerFade = $null
$script:readerFadeStep = 0.14
$script:readerFontSize = 14.0
$script:readerDir = 'rtl'

function Set-ReaderDirection {
    param([string]$Direction)
    $script:readerDir = $Direction
    if ($script:readerBox) {
        $script:readerBox.RightToLeft = $(if ($Direction -eq 'rtl') { 'Yes' } else { 'No' })
    }
}

function Set-ReaderFont {
    param([double]$Size)
    $script:readerFontSize = [Math]::Max(9, [Math]::Min(32, $Size))
    if ($script:readerBox) {
        $script:readerBox.Font = New-Object System.Drawing.Font('Segoe UI', $script:readerFontSize)
    }
}

function Hide-Reader {
    if (-not $script:readerForm -or $script:readerForm.IsDisposed) { return }
    $script:readerFadeStep = -[Math]::Abs($script:readerFadeStep)
    $script:readerFade.Start()
}

function New-ReaderForm {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'RTL Reader  --  Esc to close'
    $f.Size = New-Object System.Drawing.Size(760, 520)
    $f.StartPosition = 'CenterScreen'
    $f.TopMost = $true
    $f.KeyPreview = $true
    $f.ShowInTaskbar = $false
    $f.Opacity = 0
    try { $f.Icon = Get-AppIcon } catch { }

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Dock = 'Fill'
    $box.ReadOnly = $true
    $box.BorderStyle = 'None'
    $box.BackColor = [System.Drawing.Color]::White
    $box.Font = New-Object System.Drawing.Font('Segoe UI', $script:readerFontSize)
    $box.ScrollBars = 'Vertical'
    $f.Controls.Add($box)
    $script:readerBox = $box

    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Bottom'
    $bar.Height = 40
    $bar.Padding = New-Object System.Windows.Forms.Padding(6, 5, 6, 5)
    $f.Controls.Add($bar)

    $mkButton = {
        param([string]$Text, [int]$Width, [scriptblock]$OnClick)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Text
        $b.Width = $Width
        $b.Height = 26
        $b.add_Click($OnClick)
        [void]$bar.Controls.Add($b)
        return $b
    }

    [void](& $mkButton 'A-' 36 { Set-ReaderFont ($script:readerFontSize - 2) })
    [void](& $mkButton 'A+' 36 { Set-ReaderFont ($script:readerFontSize + 2) })
    # Escape hatch for the times the ratio test guesses wrong.
    [void](& $mkButton 'RTL / LTR' 80 {
            Set-ReaderDirection $(if ($script:readerDir -eq 'rtl') { 'ltr' } else { 'rtl' })
        })
    [void](& $mkButton 'Copy' 60 {
            if ($script:readerBox.SelectionLength -gt 0) {
                [void](Set-ClipboardText $script:readerBox.SelectedText)
            } else {
                [void](Set-ClipboardText $script:readerBox.Text)
            }
        })
    [void](& $mkButton 'Close' 60 { Hide-Reader })

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Esc closes.  + / - resize.'
    $hint.AutoSize = $true
    $hint.ForeColor = [System.Drawing.Color]::Gray
    $hint.Padding = New-Object System.Windows.Forms.Padding(10, 7, 0, 0)
    [void]$bar.Controls.Add($hint)

    $f.add_KeyDown({
            param($s, $e)
            switch ($e.KeyCode) {
                'Escape' { Hide-Reader; $e.Handled = $true }
                'Oemplus' { Set-ReaderFont ($script:readerFontSize + 2); $e.Handled = $true }
                'Add' { Set-ReaderFont ($script:readerFontSize + 2); $e.Handled = $true }
                'OemMinus' { Set-ReaderFont ($script:readerFontSize - 2); $e.Handled = $true }
                'Subtract' { Set-ReaderFont ($script:readerFontSize - 2); $e.Handled = $true }
            }
        })

    # Keep the instance so position, size and font survive between reads.
    $f.add_FormClosing({ param($s, $e) $e.Cancel = $true; Hide-Reader })

    $fade = New-Object System.Windows.Forms.Timer
    $fade.Interval = 15
    $fade.add_Tick({
            if (-not $script:readerForm -or $script:readerForm.IsDisposed) { $script:readerFade.Stop(); return }
            $o = $script:readerForm.Opacity + $script:readerFadeStep
            if ($script:readerFadeStep -gt 0 -and $o -ge 1) {
                $o = 1; $script:readerFade.Stop()
            } elseif ($script:readerFadeStep -lt 0 -and $o -le 0) {
                $o = 0; $script:readerFade.Stop(); $script:readerForm.Hide()
            }
            $script:readerForm.Opacity = $o
        })
    $script:readerFade = $fade

    return $f
}

function Show-Reader {
    param([string]$Text)

    if (-not $script:readerForm -or $script:readerForm.IsDisposed) {
        $script:readerForm = New-ReaderForm
    }

    # Strip any embedded control marks; the window's own direction drives layout.
    $clean = Unwrap-Rtl $Text
    $script:readerBox.Text = $clean
    $script:readerBox.Select(0, 0)
    Set-ReaderDirection (Get-TextDirection $clean)

    $script:readerFadeStep = [Math]::Abs($script:readerFadeStep)
    $script:readerForm.Opacity = 0
    $script:readerForm.Show()
    $script:readerForm.Activate()
    $script:readerFade.Start()
}

<#
  Copy whatever is selected and show it in the reader. Unlike the wrap actions
  this never pastes, so the source app is left completely untouched -- which is
  what makes it work on text you cannot edit.
#>
function Read-Selection {
    $target = [RtlKeys]::DescribeForegroundWindow()
    Write-Log "action 'Read selection' -> $target"

    [RtlKeys]::ReleaseModifiers()
    $original = Get-ClipboardText
    [void](Clear-Clipboard)
    [RtlKeys]::CtrlKey(0x43)   # Ctrl+C

    $selected = $null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 50
        $selected = Get-ClipboardText
        if (-not [string]::IsNullOrEmpty($selected)) { break }
    }
    Write-Log "  copied: $(Describe-Text $selected)"

    # Nothing is pasted, so the clipboard goes back immediately.
    if ($original) { [void](Set-ClipboardText $original) }

    if ([string]::IsNullOrWhiteSpace($selected)) {
        Write-Log '  -> nothing captured'
        Show-Toast 'Nothing selected' 'Select some text in the reply first.'
        return
    }

    Write-Log "  -> opened reader with $($selected.Length) chars"
    Show-Reader $selected
}

function Read-Clipboard {
    $text = Get-ClipboardText
    if ([string]::IsNullOrWhiteSpace($text)) {
        Show-Toast 'Clipboard is empty' 'Copy some text first.'
        return
    }
    Show-Reader $text
}

if ($SelfTest) {
    $sample = "Hello world`n" + ([string]::Join('', [char[]]@(0x0645, 0x0631, 0x062D, 0x0628, 0x0627)))
    $wrapped = Wrap-Rtl $sample
    # Every string comparison here is ordinal on purpose: -eq / -ceq are
    # culture sensitive and treat bidi controls as weightless, which would make
    # these checks pass no matter what the transforms did.
    $ord = { param($a, $b) [string]::Equals($a, $b, [System.StringComparison]::Ordinal) }

    $results = [ordered]@{
        'native helpers compiled' = ([RtlKeys] -ne $null -and [RtlHotkeyWindow] -ne $null -and [RtlToast] -ne $null)
        'wrap adds bidi marks'    = ($wrapped.Length -gt $sample.Length)
        'wrap is per line'        = (([regex]::Matches($wrapped, [string][char]0x202B)).Count -eq 2)
        'unwrap round-trips'      = (& $ord (Unwrap-Rtl $wrapped) $sample)
        'double wrap is stable'   = (& $ord (Wrap-Rtl $wrapped) $wrapped)
        # The regression that shipped: a wrapped string must not compare equal
        # to its source, or Transform-Selection discards its own output.
        'wrapped differs (ordinal)' = (-not (& $ord $wrapped $sample))
        'culture compare is unsafe' = ($wrapped -ceq $sample)
        'foreground window read'  = (-not [string]::IsNullOrEmpty([RtlKeys]::DescribeForegroundWindow()))
        'detects arabic as rtl'   = ((Get-TextDirection $sample) -eq 'rtl')
        'detects english as ltr'  = ((Get-TextDirection 'plain english sentence here') -eq 'ltr')
        'ignores stray rtl word'  = ((Get-TextDirection ('The city of ' + [string]::Join('', [char[]]@(0x0627, 0x0644, 0x0642, 0x0627, 0x0647, 0x0631, 0x0629)) + ' has many people in it')) -eq 'ltr')
        'app icon loads'          = ((Get-AppIcon) -ne $null)
        'log is writable'         = $(Write-Log 'self test'; Test-Path $logFile)
    }
    $failed = 0
    foreach ($k in $results.Keys) {
        if ($results[$k]) { Write-Host "  ok    $k" } else { Write-Host "  FAIL  $k"; $failed++ }
    }
    Write-Host $(if ($failed) { "$failed check(s) failed" } else { 'all checks passed' })
    exit $failed
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = Get-AppIcon
$notify.Text = 'RTL Picker'
$notify.Visible = $true

# -------------------------------------------------------------------- actions

# MOD_CONTROL (2) | MOD_ALT (1) = 3, plus MOD_SHIFT (4) = 7. Deliberately not
# Alt+Shift, which belongs to the browser extension.
$actions = @(
    # First because it is the one that works on text you cannot edit.
    [pscustomobject]@{ Id = 6; Name = 'Read selection in RTL'; Keys = 'Ctrl+Alt+D'; Mods = 3; Vk = 0x44
        Fallbacks = @(@{ Keys = 'Ctrl+Alt+Q'; Vk = 0x51 }, @{ Keys = 'Ctrl+Alt+Y'; Vk = 0x59 })
        Run = { Read-Selection } }
    [pscustomobject]@{ Id = 1; Name = 'Wrap selection as RTL'; Keys = 'Ctrl+Alt+R'; Mods = 3; Vk = 0x52
        Fallbacks = @(@{ Keys = 'Ctrl+Alt+G'; Vk = 0x47 })
        Run = { Transform-Selection { param($t) Wrap-Rtl $t } 'Wrapped as RTL' } }
    [pscustomobject]@{ Id = 2; Name = 'Remove direction marks'; Keys = 'Ctrl+Alt+L'; Mods = 3; Vk = 0x4C
        Fallbacks = @(@{ Keys = 'Ctrl+Alt+K'; Vk = 0x4B })
        Run = { Transform-Selection { param($t) Unwrap-Rtl $t } 'Marks removed' } }
    [pscustomobject]@{ Id = 3; Name = 'Wrap clipboard as RTL'; Keys = 'Ctrl+Alt+B'; Mods = 3; Vk = 0x42
        Fallbacks = @(@{ Keys = 'Ctrl+Alt+Z'; Vk = 0x5A })
        Run = { Convert-Clipboard { param($t) Wrap-Rtl $t } 'Clipboard wrapped as RTL' } }
    [pscustomobject]@{ Id = 4; Name = 'Paragraph -> RTL (Word only)'; Keys = 'Ctrl+Alt+Shift+R'; Mods = 7; Vk = 0x52
        Fallbacks = @()
        Run = { Set-ParagraphDirection $true 'Paragraph set to RTL' } }
    [pscustomobject]@{ Id = 5; Name = 'Paragraph -> LTR (Word only)'; Keys = 'Ctrl+Alt+Shift+L'; Mods = 7; Vk = 0x4C
        Fallbacks = @()
        Run = { Set-ParagraphDirection $false 'Paragraph set to LTR' } }
)

$byId = @{}
foreach ($a in $actions) { $byId[$a.Id] = $a }

<#
  Global hotkeys are first-come-first-served across the whole machine, so any
  fixed choice will collide on somebody's setup. Fall back to an alternative
  rather than losing the action, and report which key actually won.
#>
$hotkeys = New-Object RtlHotkeyWindow
$failed = @()
$rebound = @()
foreach ($a in $actions) {
    $ok = $hotkeys.Register([int]$a.Id, [uint32]$a.Mods, [uint32]$a.Vk)
    if (-not $ok) {
        Write-Log "$($a.Keys) is taken by another app; trying fallbacks"
        foreach ($fb in $a.Fallbacks) {
            if ($hotkeys.Register([int]$a.Id, [uint32]$a.Mods, [uint32]$fb.Vk)) {
                $rebound += "$($a.Name): $($fb.Keys)"
                $a.Keys = $fb.Keys
                $ok = $true
                break
            }
        }
    }
    if ($ok) {
        Write-Log "registered $($a.Keys) -> $($a.Name)"
    } else {
        $failed += $a.Keys
        Write-Log "FAILED to register $($a.Name) -- all candidate keys are taken"
    }
}

$hotkeys.add_HotkeyPressed({
        param($id)
        try {
            $action = $byId[[int]$id]
            if ($action) { & $action.Run }
        } catch {
            Write-Log "error: $($_.Exception.Message)"
            Show-Toast 'RTL Picker error' $_.Exception.Message
        }
    })

# ------------------------------------------------------------------ tray menu

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$readClip = New-Object System.Windows.Forms.ToolStripMenuItem 'Read clipboard in RTL'
$readClip.Font = New-Object System.Drawing.Font($menu.Font, [System.Drawing.FontStyle]::Bold)
$readClip.add_Click({ Read-Clipboard })
[void]$menu.Items.Add($readClip)

$compose = New-Object System.Windows.Forms.ToolStripMenuItem 'Compose in RTL...'
$compose.add_Click({ Show-ComposeWindow })
[void]$menu.Items.Add($compose)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

foreach ($a in $actions) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $a.Name
    $item.ShortcutKeyDisplayString = $a.Keys
    $item.Tag = $a
    # Read the action off the sender rather than $a -- the loop variable would
    # otherwise be shared by every handler.
    $item.add_Click({ param($s, $e) & $s.Tag.Run })
    [void]$menu.Items.Add($item)
}

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$perLine = New-Object System.Windows.Forms.ToolStripMenuItem 'Wrap each line separately'
$perLine.CheckOnClick = $true
$perLine.Checked = $script:WrapPerLine
$perLine.ToolTipText = 'On: every line becomes its own RTL run. Off: one run for the whole selection.'
$perLine.add_Click({ $script:WrapPerLine = $perLine.Checked })
[void]$menu.Items.Add($perLine)

$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'RTL Picker.lnk'

function Set-RunAtStartup {
    param([bool]$Enabled)
    if ($Enabled) {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($startupLink)
        $lnk.TargetPath = (Get-Command powershell.exe).Source
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$PSCommandPath`""
        $lnk.WorkingDirectory = $PSScriptRoot
        $lnk.Description = 'RTL Picker desktop hotkeys'
        $lnk.Save()
    } elseif (Test-Path $startupLink) {
        Remove-Item $startupLink -Force
    }
}

$startup = New-Object System.Windows.Forms.ToolStripMenuItem 'Start with Windows'
$startup.CheckOnClick = $true
$startup.Checked = (Test-Path $startupLink)
$startup.add_Click({
        try { Set-RunAtStartup $startup.Checked }
        catch {
            Show-Toast 'Could not update startup' $_.Exception.Message
            $startup.Checked = (Test-Path $startupLink)
        }
    })
[void]$menu.Items.Add($startup)

$openLog = $menu.Items.Add('Open log')
$openLog.add_Click({ Start-Process notepad.exe $logFile })

$about = $menu.Items.Add('How it works...')
$about.add_Click({
        $lines = ($actions | ForEach-Object { '{0,-18} {1}' -f $_.Keys, $_.Name }) -join "`n"
        [System.Windows.Forms.MessageBox]::Show(
            ("$lines`n`n" +
                "Wrap / Remove edit the text itself, adding invisible Unicode direction`n" +
                "marks. That works in any app that supports copy and paste, including`n" +
                "Electron apps like Claude, Slack and VS Code, and the direction stays`n" +
                "with the text when you send it.`n`n" +
                "The two 'Word only' shortcuts send Windows' native paragraph-direction`n" +
                "command. Chromium and Electron ignore it, so they do nothing there.`n`n" +
                "No hotkey can right-align another app's interface -- only that app's`n" +
                "own settings can. This fixes the text, not the layout."),
            'RTL Picker', 'OK', 'Information') | Out-Null
    })

$exit = $menu.Items.Add('Exit')
$exit.add_Click({
        $notify.Visible = $false
        [System.Windows.Forms.Application]::Exit() # the finally block cleans up
    })

$notify.ContextMenuStrip = $menu
$notify.add_MouseUp({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $menu.Show([System.Windows.Forms.Cursor]::Position)
        }
    })

Write-Log '--- started ---'
$readerKey = ($actions | Where-Object { $_.Id -eq 6 }).Keys
if ($failed.Count) {
    Show-Toast 'Some shortcuts are taken' "$($failed -join ', ') -- another app owns them."
} elseif ($rebound.Count) {
    Show-Toast 'Shortcut changed' ($rebound -join '; ')
} else {
    Show-Toast 'RTL Picker is running' "Select text, press $readerKey to read it in RTL."
}

try {
    [System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
} finally {
    Write-Log '--- stopped ---'
    $notify.Visible = $false
    $notify.Dispose()
    $hotkeys.Dispose()
}
