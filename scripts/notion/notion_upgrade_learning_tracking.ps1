param(
    [string]$LearningLogDatabaseId = "37fe8e29-9eae-816d-a682-e5ecf84db554",
    [string]$NotionVersion = "2022-06-28"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Import-DotEnv {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            return
        }

        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) {
            return
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($name -and -not [Environment]::GetEnvironmentVariable($name, "Process")) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

function Get-EnvValue {
    param([string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, "User") }
    if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, "Machine") }
    return $value
}

function New-SelectSchema {
    param([string[]]$Options)

    return @{
        select = @{
            options = @($Options | ForEach-Object { @{ name = $_ } })
        }
    }
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$notionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $notionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$headers = @{
    Authorization = "Bearer $notionToken"
    "Notion-Version" = $NotionVersion
    "Content-Type" = "application/json"
}

$body = @{
    properties = @{
        Outcome = New-SelectSchema -Options @("Read", "Practiced", "Built", "Reviewed", "Debugged", "Watched")
        "Next Step" = @{ rich_text = @{} }
        Source = New-SelectSchema -Options @("Manual", "Pomodoro", "Daily Update", "Import")
    }
}

$jsonBody = $body | ConvertTo-Json -Depth 30
[void](Invoke-RestMethod -Method "PATCH" -Uri "https://api.notion.com/v1/databases/$LearningLogDatabaseId" -Headers $headers -Body $jsonBody)
Write-Host "Upgraded Learning Log with Outcome, Next Step, and Source fields."
