param(
    [int]$DayOfMonth = 1,
    [string]$Time = "20:00"
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "sol_sync_flights_from_gmail.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Apply"
$trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth $DayOfMonth -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName "SoL Monthly Flight Sync" -Action $action -Trigger $trigger -Settings $settings -Description "Checks Gmail for new flight emails and adds trips to Sheet of Life." -Force
Write-Host "Registered monthly flight sync for day $DayOfMonth at $Time."
