param([Parameter(Mandatory)][string]$Installer, [switch]$SkipInstall)
$ErrorActionPreference = 'Stop'
$report = [ordered]@{
    time = (Get-Date).ToUniversalTime().ToString('o')
    checks = [ordered]@{}
    manual = @('Sessão remota autenticada entre dois PCs, direta e via relay',
        'Marca no instalador, bandeja, barra de tarefas, atalhos, tela Sobre e temas claro/escuro',
        'Reinicialização completa do Windows, UAC e atualização sobre instalação ASV anterior',
        'Migração controlada de uma máquina com RustDesk oficial instalado')
}
$serviceName = 'ASV-Suporte-Remoto'
$installedExe = Join-Path $env:ProgramFiles "$serviceName\$serviceName.exe"
$originalRustDesk = Get-Service RustDesk -ErrorAction SilentlyContinue

function Assert-ASV($Condition, [string]$Name) {
    $report.checks[$Name] = [bool]$Condition
    if (-not $Condition) { throw "Falhou: $Name" }
}

function Wait-ASV([scriptblock]$Condition, [int]$Seconds = 60) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Invoke-ASV([string[]]$Arguments) {
    $outFile = Join-Path $env:TEMP ('asv-cli-' + [guid]::NewGuid() + '.txt')
    $errFile = "$outFile.err"
    try {
        $p = Start-Process $installedExe -ArgumentList $Arguments -PassThru -NoNewWindow `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if (-not $p.WaitForExit(30000)) { $p.Kill(); throw 'CLI timeout' }
        if ($p.ExitCode -ne 0) { throw "CLI exit code $($p.ExitCode)" }
        $output = Get-Content $outFile -Raw
        if ($null -eq $output) { return '' }
        return $output.Trim()
    } finally {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    Assert-ASV ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'administrator'
    # Run only in a disposable Windows runner/VM. Installation creates a real remote service.
    if (-not $SkipInstall) {
        $setup = Start-Process (Resolve-Path $Installer) -ArgumentList '--silent-install' -PassThru
    }
    Assert-ASV (Wait-ASV { (Test-Path $installedExe) -and
        ((Get-Service $serviceName -ErrorAction SilentlyContinue).Status -eq 'Running') } 120) 'installation-and-service'
    $svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
    Assert-ASV ($svc.StartMode -eq 'Auto') 'service-automatic-start'
    Assert-ASV ($svc.PathName.Contains($installedExe)) 'service-executable-path'
    $pe = [IO.File]::ReadAllBytes($installedExe)
    $header = [BitConverter]::ToInt32($pe, 60)
    Assert-ASV ([BitConverter]::ToUInt16($pe, $header + 4) -eq 0x8664) 'windows-x64'
    $installDir = Split-Path $installedExe
    Assert-ASV (Test-Path "$installDir\ASV-Suporte-Remoto-source.tar.gz") 'installed-corresponding-source'
    Assert-ASV (Test-Path "$installDir\LICENCE") 'installed-AGPL'
    Assert-ASV ((Get-FileHash "$installDir\data\flutter_assets\assets\icon.png").Hash -eq
        (Get-FileHash 'asv/brand/icon.png').Hash) 'installed-icon-png'
    Assert-ASV ((Get-FileHash "$installDir\data\flutter_assets\assets\icon.ico").Hash -eq
        (Get-FileHash 'asv/brand/icon.ico').Hash) 'installed-icon-ico'
    Assert-ASV ((Get-FileHash "$installDir\data\flutter_assets\assets\logo.png").Hash -eq
        (Get-FileHash 'asv/brand/logo.png').Hash) 'installed-logo'
    $expected = @{
        'custom-rendezvous-server' = 'rustdesk.asv.com.br'
        'key' = 'vZmmsfIrplKLZdZB4FoaD8o39dSPJaV58RY4SW0ipxc='
    }
    foreach ($key in $expected.Keys) {
        Assert-ASV ((Invoke-ASV @('--option', $key)) -eq $expected[$key]) "effective-$key"
    }
    $id = Invoke-ASV @('--get-id')
    Assert-ASV ($id -match '^\d+$') 'assigned-device-id'
    foreach ($key in $expected.Keys) {
        $null = Invoke-ASV @('--option', $key, 'override-attempt.invalid')
    }
    Restart-Service $serviceName
    Assert-ASV (Wait-ASV { (Get-Service $serviceName).Status -eq 'Running' }) 'service-restart'
    Start-Sleep -Seconds 3
    foreach ($key in $expected.Keys) {
        Assert-ASV ((Invoke-ASV @('--option', $key)) -eq $expected[$key]) "persistent-$key"
    }
    Assert-ASV ((Invoke-ASV @('--get-id')) -eq $id) 'persistent-device-id'
    foreach ($port in @(21115, 21116, 21117)) {
        $tcp = [Net.Sockets.TcpClient]::new()
        try {
            $task = $tcp.ConnectAsync('rustdesk.asv.com.br', $port)
            Assert-ASV ($task.Wait(5000) -and $tcp.Connected) "tcp-$port"
        } finally { $tcp.Dispose() }
    }
    $systemConfig = Join-Path $env:WINDIR "ServiceProfiles\LocalService\AppData\Roaming\$serviceName\config\$serviceName.toml"
    $systemConfig2 = Join-Path $env:WINDIR "System32\config\systemprofile\AppData\Roaming\$serviceName\config\$serviceName.toml"
    $userConfig = Join-Path $env:APPDATA "$serviceName\config\$serviceName.toml"
    Assert-ASV (Wait-ASV {
        foreach ($p in @($systemConfig, $systemConfig2, $userConfig)) {
            if ((Test-Path $p) -and ((Get-Content $p -Raw) -match '(?m)^key_confirmed\s*=\s*true')) {
                return $true
            }
        }
        return $false
    } 90) 'rendezvous-registration-confirmed'
    Start-Process $installedExe
    Assert-ASV (Wait-ASV {
        # Interactive installation may already have opened the main window.
        $ui = Get-Process -Name $serviceName -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $installedExe -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
            Select-Object -First 1
        if ($ui) { $report.windowTitle = $ui.MainWindowTitle; return $true }
        return $false
    } 45) 'ui-window-started'
    Assert-ASV ($report.windowTitle -like 'ASV Suporte Remoto*') 'ui-window-brand'
    Add-Type -AssemblyName System.Drawing
    $icon = [Drawing.Icon]::ExtractAssociatedIcon($installedExe)
    $bitmap = $icon.ToBitmap()
    $bitmap.Save((Join-Path (Resolve-Path distribution) 'executable-icon.png'))
    $bitmap.Dispose(); $icon.Dispose()
    if ($originalRustDesk) {
        Assert-ASV ((Get-Service RustDesk).Status -eq $originalRustDesk.Status) 'previous-rustdesk-service-unchanged'
    }
    $report.result = 'automatic-checks-passed-manual-acceptance-pending'
} catch {
    $report.result = 'failed'
    $report.error = $_.Exception.Message
    throw
} finally {
    New-Item distribution -ItemType Directory -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content distribution/validation-windows.json
    # Do not upload TOML files or logs: they can contain device credentials/private keys.
}
