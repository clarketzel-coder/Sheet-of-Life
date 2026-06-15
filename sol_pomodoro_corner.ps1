param(
    [int]$Port = 8765,
    [ValidateSet("TopLeft", "TopRight", "BottomLeft", "BottomRight")]
    [string]$Corner = "BottomRight",
    [int]$Width = 380,
    [int]$Height = 640,
    [string]$BrowserPath = ""
)

$ErrorActionPreference = "Stop"

function Test-Server {
    param([int]$Port)

    try {
        $health = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 2
        return [bool]$health.ok
    }
    catch {
        return $false
    }
}

function Start-SoLServer {
    param([int]$Port)

    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "sol_pomodoro_server.ps1"
    $outPath = Join-Path -Path $PSScriptRoot -ChildPath "sol_pomodoro_live.out.log"
    $errPath = Join-Path -Path $PSScriptRoot -ChildPath "sol_pomodoro_live.err.log"
    $command = "cmd.exe /c powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Port $Port > `"$outPath`" 2> `"$errPath`""

    $shell = New-Object -ComObject WScript.Shell
    [void]$shell.Run($command, 0, $false)

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        if (Test-Server -Port $Port) {
            return
        }
    }

    throw "SoL Pomodoro server did not start. Check $errPath."
}

function Get-BrowserPath {
    param([string]$BrowserPath)

    if ($BrowserPath -and (Test-Path -LiteralPath $BrowserPath)) {
        return $BrowserPath
    }

    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:LocalAppData\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    throw "Could not find Microsoft Edge or Google Chrome. Pass -BrowserPath if it is installed somewhere custom."
}

function Get-WindowPosition {
    param(
        [string]$Corner,
        [int]$Width,
        [int]$Height
    )

    Add-Type -AssemblyName System.Windows.Forms
    $workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $margin = 18

    $x = switch ($Corner) {
        "TopLeft" { $workArea.Left + $margin }
        "BottomLeft" { $workArea.Left + $margin }
        default { $workArea.Right - $Width - $margin }
    }

    $y = switch ($Corner) {
        "TopLeft" { $workArea.Top + $margin }
        "TopRight" { $workArea.Top + $margin }
        default { $workArea.Bottom - $Height - $margin }
    }

    return @{ X = [Math]::Max($workArea.Left, $x); Y = [Math]::Max($workArea.Top, $y) }
}

if (-not (Test-Server -Port $Port)) {
    Start-SoLServer -Port $Port
}

$browser = Get-BrowserPath -BrowserPath $BrowserPath
$position = Get-WindowPosition -Corner $Corner -Width $Width -Height $Height
$url = "http://127.0.0.1:$Port/?compact=1"
$args = "--app=$url --window-size=$Width,$Height --window-position=$($position.X),$($position.Y)"

$shell = New-Object -ComObject WScript.Shell
[void]$shell.Run("`"$browser`" $args", 1, $false)

Write-Host "Opened SoL Pomodoro in $Corner corner: $url"
