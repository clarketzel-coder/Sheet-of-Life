param(
    [switch]$Execute,
    [string]$RootPageId = "37fe8e29-9eae-8030-a619-f456bc2274cc",
    [string]$InfrastructurePageId = "37fe8e29-9eae-8159-bd12-d8bcbf34ec0c",
    [string]$CommandCenterPageId = "38ce8e29-9eae-81e2-9740-dddb8ee7deb3",
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

function ConvertTo-NotionId {
    param([string]$Value)

    $clean = ($Value -replace "[^0-9a-fA-F]", "").ToLowerInvariant()
    if ($clean.Length -ne 32) { throw "Notion ID must contain 32 hex characters. Received '$Value'." }
    return "{0}-{1}-{2}-{3}-{4}" -f $clean.Substring(0, 8), $clean.Substring(8, 4), $clean.Substring(12, 4), $clean.Substring(16, 4), $clean.Substring(20, 12)
}

function New-RichText {
    param([string]$Text)
    return ,@(@{ type = "text"; text = @{ content = $Text } })
}

function Invoke-NotionApi {
    param([string]$Method, [string]$Path, $Body = $null)

    $parameters = @{
        Method = $Method
        Uri = "https://api.notion.com/v1$Path"
        Headers = @{
            Authorization = "Bearer $script:NotionToken"
            "Notion-Version" = $NotionVersion
            "Content-Type" = "application/json"
        }
    }
    if ($null -ne $Body) { $parameters["Body"] = ($Body | ConvertTo-Json -Depth 30) }
    return Invoke-RestMethod @parameters
}

function Get-PageTitlePropertyName {
    param([string]$PageId)

    $page = Invoke-NotionApi -Method "GET" -Path "/pages/$(ConvertTo-NotionId -Value $PageId)"
    foreach ($property in $page.properties.PSObject.Properties) {
        if ($property.Value.type -eq "title") {
            return $property.Name
        }
    }
    throw "No title property found for page $PageId."
}

function Set-PageTitle {
    param([string]$PageId, [string]$Title)

    $titleProperty = Get-PageTitlePropertyName -PageId $PageId
    Invoke-NotionApi -Method "PATCH" -Path "/pages/$(ConvertTo-NotionId -Value $PageId)" -Body @{
        properties = @{
            $titleProperty = @{ title = (New-RichText -Text $Title) }
        }
    } | Out-Null
}

function Archive-Page {
    param([string]$PageId)

    $page = Invoke-NotionApi -Method "GET" -Path "/pages/$(ConvertTo-NotionId -Value $PageId)"
    if ($page.archived) {
        return
    }
    Invoke-NotionApi -Method "PATCH" -Path "/pages/$(ConvertTo-NotionId -Value $PageId)" -Body @{ archived = $true } | Out-Null
}

function Archive-Database {
    param([string]$DatabaseId)

    $database = Invoke-NotionApi -Method "GET" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)"
    if ($database.archived) {
        return
    }
    Invoke-NotionApi -Method "PATCH" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)" -Body @{ archived = $true } | Out-Null
}

function Add-RootCommandCenterLink {
    $commandCenterUrl = "https://www.notion.so/$((ConvertTo-NotionId -Value $CommandCenterPageId) -replace '-', '')"
    $children = @(
        @{
            object = "block"
            type = "divider"
            divider = @{}
        },
        @{
            object = "block"
            type = "heading_2"
            heading_2 = @{ rich_text = (New-RichText -Text "Start Here") }
        },
        @{
            object = "block"
            type = "callout"
            callout = @{
                rich_text = (New-RichText -Text "Use the Command Center as the daily Sheet of Life surface. The infrastructure page holds the source databases.")
            }
        },
        @{
            object = "block"
            type = "paragraph"
            paragraph = @{
                rich_text = ,@{
                    type = "text"
                    text = @{
                        content = "Open Sheet of Life Command Center"
                        link = @{ url = $commandCenterUrl }
                    }
                }
            }
        }
    )

    Invoke-NotionApi -Method "PATCH" -Path "/blocks/$(ConvertTo-NotionId -Value $RootPageId)/children" -Body @{ children = $children } | Out-Null
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$legacyPages = @(
    @{ Title = "00 - Sheet of Life Home"; Id = "38ce8e29-9eae-818c-b546-d60ea34d16c5" },
    @{ Title = "Sheet of Life Mobile Home"; Id = "38ce8e29-9eae-81ac-850f-cc07cc7b203d" },
    @{ Title = "Today Desk"; Id = "38ce8e29-9eae-81ed-914b-da6bd8b8c8ee" },
    @{ Title = "Food Planner"; Id = "38ce8e29-9eae-814a-b3ae-cdaf56add1cf" },
    @{ Title = "Capture Pad"; Id = "38ce8e29-9eae-8187-b407-d7df866e5af2" },
    @{ Title = "Weekly Reset"; Id = "38ce8e29-9eae-813e-abfa-e1706962f932" }
)

$duplicateDatabases = @(
    @{ Title = "SoL to-do list"; Id = "37fe8e29-9eae-8029-8053-e4effeb904e2"; Keep = "To-Dos" }
)

Write-Host "Cleanup plan:"
Write-Host "- Keep Command Center: $CommandCenterPageId"
Write-Host "- Keep backend databases and Command Center Components."
Write-Host "- Rename old prototype parent to 'Sheet of Life Infrastructure'."
foreach ($page in $legacyPages) {
    Write-Host "- Archive legacy page: $($page.Title) [$($page.Id)]"
}
foreach ($database in $duplicateDatabases) {
    Write-Host "- Archive duplicate database: $($database.Title) [$($database.Id)]; keep $($database.Keep)"
}
Write-Host "- Add a Start Here link from root Sheet of Life page to the Command Center."

if (-not $Execute) {
    Write-Host "Dry run only. Re-run with -Execute to apply."
    return
}

Set-PageTitle -PageId $InfrastructurePageId -Title "Sheet of Life Infrastructure"
foreach ($page in $legacyPages) {
    Archive-Page -PageId $page.Id
    Write-Host "Archived page: $($page.Title)"
}
foreach ($database in $duplicateDatabases) {
    Archive-Database -DatabaseId $database.Id
    Write-Host "Archived duplicate database: $($database.Title)"
}
Add-RootCommandCenterLink
Write-Host "Workspace cleanup complete."
