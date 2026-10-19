param([Parameter(Mandatory)][string]$Installer)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
$report = [ordered]@{ checks = [ordered]@{} }
$buttonCondition = [Windows.Automation.PropertyCondition]::new(
    [Windows.Automation.AutomationElement]::ControlTypeProperty,
    [Windows.Automation.ControlType]::Button)

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
    if ($p) { return [Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle) }
}

function Find-InstallButton([string]$Name) {
    $window = Get-InstallWindow
    if (-not $window) { return }
    foreach ($element in $window.FindAll([Windows.Automation.TreeScope]::Descendants, $buttonCondition)) {
        if ($element.Current.Name -match $Name -and $element.Current.IsEnabled) { return $element }
    }
}

function Invoke-InstallButton($Button) {
    $pattern = $Button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
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
        foreach ($element in $window.FindAll([Windows.Automation.TreeScope]::Descendants,
                [Windows.Automation.Condition]::TrueCondition)) {
            if ($element.Current.Name -like '*O serviço RustDesk original está ativo*') { return $true }
        }
        return $false
    }
    $report.checks['conflict-error-visible-after-button-click'] = $true
    if ((Get-Service RustDesk).Status -ne 'Running') { throw 'Original service was unexpectedly changed.' }
    $report.checks['original-service-preserved'] = $true
    $bounds = (Get-InstallWindow).Current.BoundingRectangle
    $bitmap = [Drawing.Bitmap]::new([int]$bounds.Width, [int]$bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bitmap.Size)
    $bitmap.Save((Join-Path (Resolve-Path distribution) 'interactive-install-error.png'))
    $graphics.Dispose(); $bitmap.Dispose()
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
    throw
} finally {
    New-Item distribution -ItemType Directory -Force | Out-Null
    $report | ConvertTo-Json -Depth 6 | Set-Content distribution/validation-install-button.json
}
