param(
    [string]$PrototypePageId = "37fe8e29-9eae-8159-bd12-d8bcbf34ec0c",
    [string]$TimerUrl = "http://127.0.0.1:8765/?compact=1",
    [string]$NotionVersion = "2022-06-28",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

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

function New-RichText {
    param(
        [string]$Text,
        [string]$Link = ""
    )

    $textObject = @{ content = $Text }
    if ($Link) {
        $textObject.link = @{ url = $Link }
    }

    return @{
        type = "text"
        text = $textObject
    }
}

function ConvertTo-NotionId {
    param([string]$Value)

    $hex = ($Value -replace "[^0-9a-fA-F]", "").ToLowerInvariant()
    if ($hex.Length -ne 32) {
        throw "Notion ID must contain 32 hex characters. Received '$Value'."
    }
    return "$($hex.Substring(0,8))-$($hex.Substring(8,4))-$($hex.Substring(12,4))-$($hex.Substring(16,4))-$($hex.Substring(20,12))"
}

Import-DotEnv -Path (Join-Path -Path $PSScriptRoot -ChildPath ".env")
$notionToken = Get-EnvValue -Name "NOTION_TOKEN"

if (-not $DryRun -and -not $notionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$normalizedPageId = ConvertTo-NotionId -Value $PrototypePageId

$body = @{
    children = @(
        @{
            object = "block"
            type = "divider"
            divider = @{}
        },
        @{
            object = "block"
            type = "heading_2"
            heading_2 = @{
                rich_text = @((New-RichText -Text "Focus timer"))
                color = "default"
            }
        },
        @{
            object = "block"
            type = "callout"
            callout = @{
                icon = @{ emoji = "⏱️" }
                color = "blue_background"
                rich_text = @(
                    (New-RichText -Text "Open SoL Pomodoro" -Link $TimerUrl),
                    (New-RichText -Text " to start a focus session and log it to the Learning Log. If it does not open, start the local server from this workspace first.")
                )
            }
        },
        @{
            object = "block"
            type = "bookmark"
            bookmark = @{
                url = $TimerUrl
                caption = @((New-RichText -Text "Local SoL Pomodoro timer"))
            }
        }
    )
}

if ($DryRun) {
    $body | ConvertTo-Json -Depth 30
    return
}

$headers = @{
    Authorization = "Bearer $notionToken"
    "Notion-Version" = $NotionVersion
    "Content-Type" = "application/json"
}

$jsonBody = $body | ConvertTo-Json -Depth 30
[void](Invoke-RestMethod -Method "PATCH" -Uri "https://api.notion.com/v1/blocks/$normalizedPageId/children" -Headers $headers -Body $jsonBody)
Write-Host "Added SoL Pomodoro launcher to Notion page $normalizedPageId."
