param([Parameter(Mandatory)][string]$Installer)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, Accessibility
# This Flutter engine exposes controls through MSAA; UIA only sees FLUTTERVIEW.
Add-Type -ReferencedAssemblies ([Accessibility.IAccessible].Assembly.Location) @'
using System;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Accessibility;
public static class InstallerAccessibility {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
    [DllImport("oleacc.dll")]
    static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid,
        [MarshalAs(UnmanagedType.Interface)] out object accessible);
    public static IAccessible Find(IntPtr parent, string name, bool button) {
        var child = FindWindowEx(parent, IntPtr.Zero, "FLUTTERVIEW", null);
        if (child == IntPtr.Zero) return null;
        var iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        object accessible;
        AccessibleObjectFromWindow(child, 0xfffffffc, ref iid, out accessible);
        return FindNode(accessible as IAccessible, name, button);
    }
    static IAccessible FindNode(IAccessible node, string name, bool button) {
        if (node == null) return null;
        string text = "";
        try { text = node.get_accName(0) ?? ""; } catch (COMException) { }
        try { text += " " + node.get_accValue(0); } catch (COMException) { }
        try {
            if (Regex.IsMatch(text.Trim(), name, RegexOptions.IgnoreCase) &&
                (!button || (Convert.ToInt32(node.get_accRole(0)) == 43 &&
                             (Convert.ToInt32(node.get_accState(0)) & 1) == 0))) return node;
            for (int i = 1; i <= node.accChildCount; i++) {
                try {
                    var found = FindNode(node.get_accChild(i) as IAccessible, name, button);
                    if (found != null) return found;
                } catch (COMException) { } // A child can disappear while a dialog opens.
            }
        } catch (COMException) { }
        return null;
    }
}
'@
$report = [ordered]@{ checks = [ordered]@{} }

function Wait-InstallUI([scriptblock]$Condition, [int]$Seconds = 60) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $result = & $Condition
        if ($result) { return $result }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw 'Interactive installer did not reach the expected state.'
}

function Get-InstallWindow {
    $p = Get-Process -Name ASV-Suporte-Remoto -ErrorAction SilentlyContinue |
        Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
    if ($p) {
        return [Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
    }
}

function Find-InstallButton([string]$Name) {
    $window = Get-InstallWindow
    if ($window) {
        return [InstallerAccessibility]::Find([IntPtr]$window.Current.NativeWindowHandle, $Name, $true)
    }
}

function Invoke-InstallButton($Button) {
    $Button.accDoDefaultAction(0)
}

function Save-InstallWindow([string]$Name) {
    $bounds = (Get-InstallWindow).Current.BoundingRectangle
    $bitmap = [Drawing.Bitmap]::new([int]$bounds.Width, [int]$bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bitmap.Size)
    $bitmap.Save((Join-Path (Resolve-Path distribution) $Name))
    $graphics.Dispose(); $bitmap.Dispose()
}

try {
    # A real upstream installation reproduces the reported conflict, only on this disposable runner.
    $stock = Join-Path $env:TEMP 'rustdesk-1.5.0-x86_64.exe'
    Invoke-WebRequest 'https://github.com/rustdesk/rustdesk/releases/download/1.5.0/rustdesk-1.5.0-x86_64.exe' -OutFile $stock
    if ((Get-FileHash $stock -Algorithm SHA256).Hash -ne '8555777215510d83d2d61c9dc984e4fcc838bd7e79f9d18a42585431f5e8bb47') {
        throw 'Upstream fixture checksum mismatch.'
    }
    Start-Process $stock -ArgumentList '--silent-install' | Out-Null
    $null = Wait-InstallUI { (Get-Service RustDesk -ErrorAction SilentlyContinue).Status -eq 'Running' }
    $report.checks['upstream-service-running'] = $true
    Start-Process (Resolve-Path $Installer) | Out-Null
    $installLabel = 'Accept and Install|Aceitar e Instalar'
    $button = Wait-InstallUI { Find-InstallButton $installLabel }
    Write-Host "Invoking Accept and Install with the original service running."
    Invoke-InstallButton $button
    $report.checks['accept-button-invoked'] = $true
    $null = Wait-InstallUI {
        $window = Get-InstallWindow
        if (-not $window) { return $false }
        return [InstallerAccessibility]::Find([IntPtr]$window.Current.NativeWindowHandle,
            'O serviço RustDesk original está ativo', $false)
    }
    $report.checks['conflict-error-visible-after-button-click'] = $true
    if ((Get-Service RustDesk).Status -ne 'Running') { throw 'Original service was unexpectedly changed.' }
    $report.checks['original-service-preserved'] = $true
    Save-InstallWindow 'interactive-install-error.png'
    Invoke-InstallButton (Wait-InstallUI { Find-InstallButton '^OK$' })
    $button = Wait-InstallUI { Find-InstallButton $installLabel }
    $report.checks['install-button-enabled-for-retry'] = $true
    Stop-Service RustDesk
    Get-Process RustDesk -ErrorAction SilentlyContinue | Stop-Process -Force
    Invoke-InstallButton $button
    $null = Wait-InstallUI { (Get-Service ASV-Suporte-Remoto -ErrorAction SilentlyContinue).Status -eq 'Running' } 120
    $report.checks['retry-through-button-installed-ASV-service'] = $true
    $report.result = 'passed'
} catch {
    $report.result = 'failed'
    $report.error = $_.Exception.Message
    Write-Host $_.ScriptStackTrace
    Get-Process | Where-Object { $_.ProcessName -match 'ASV|rustdesk' } |
        Select-Object ProcessName, MainWindowHandle, MainWindowTitle | Format-Table | Out-Host
    $window = Get-InstallWindow
    if ($window) {
        Save-InstallWindow 'interactive-install-failure.png'
    }
    throw
} finally {
    New-Item distribution -ItemType Directory -Force | Out-Null
    $report | ConvertTo-Json -Depth 6 | Set-Content distribution/validation-install-button.json
}
