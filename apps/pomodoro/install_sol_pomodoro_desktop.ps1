param(
    [ValidateSet("TopLeft", "TopRight", "BottomLeft", "BottomRight")]
    [string]$Corner = "BottomRight",
    [int]$Port = 8765,
    [switch]$Startup
)

$ErrorActionPreference = "Stop"

$launcherPath = Join-Path -Path $PSScriptRoot -ChildPath "sol_pomodoro_corner.ps1"
if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Missing launcher file: $launcherPath"
}

$shell = New-Object -ComObject WScript.Shell
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path -Path $desktopPath -ChildPath "SoL Pomodoro.lnk"

$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`" -Port $Port -Corner $Corner"
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = "shell32.dll,264"
$shortcut.Description = "Open the Sheet of Life Pomodoro timer and auto-log focus sessions to Notion."
$shortcut.Save()

Write-Host "Created desktop shortcut: $shortcutPath"

if ($Startup) {
    $startupPath = [Environment]::GetFolderPath("Startup")
    $startupShortcutPath = Join-Path -Path $startupPath -ChildPath "SoL Pomodoro.lnk"
    $startupShortcut = $shell.CreateShortcut($startupShortcutPath)
    $startupShortcut.TargetPath = "powershell.exe"
    $startupShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`" -Port $Port -Corner $Corner"
    $startupShortcut.WorkingDirectory = $PSScriptRoot
    $startupShortcut.IconLocation = "shell32.dll,264"
    $startupShortcut.Description = "Open the Sheet of Life Pomodoro timer at Windows sign-in."
    $startupShortcut.Save()
    Write-Host "Created startup shortcut: $startupShortcutPath"
}
