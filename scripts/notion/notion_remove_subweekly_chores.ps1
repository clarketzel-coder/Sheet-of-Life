param(
    [string]$TemplatesDatabaseId = "37fe8e29-9eae-8113-88c0-dda7166e8d3d",
    [string]$ChoresDatabaseId = "37fe8e29-9eae-81de-a1bd-db293503adfa",
    [string]$NotionVersion = "2022-06-28",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) { return }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) { return }
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
    if ($null -ne $Body) {
        $parameters["Body"] = ($Body | ConvertTo-Json -Depth 20)
    }
    return Invoke-RestMethod @parameters
}

function Invoke-DatabaseQuery {
    param([string]$DatabaseId, $Filter)
    $results = @()
    $cursor = $null
    do {
        $body = @{ page_size = 100; filter = $Filter }
        if ($cursor) { $body.start_cursor = $cursor }
        $response = Invoke-NotionApi -Method "POST" -Path "/databases/$DatabaseId/query" -Body $body
        $results += $response.results
        $cursor = $response.next_cursor
    } while ($response.has_more)
    return $results
}

function Get-TitleText {
    param($Page)
    foreach ($property in $Page.properties.PSObject.Properties) {
        if ($property.Value.type -eq "title") {
            return (($property.Value.title | ForEach-Object { $_.plain_text }) -join "")
        }
    }
    return ""
}

function Archive-Pages {
    param([array]$Pages, [string]$Label)
    foreach ($page in $Pages) {
        $name = Get-TitleText -Page $page
        if ($Apply) {
            [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($page.id)" -Body @{ archived = $true })
            Write-Host "Archived ${Label}: $name"
        }
        else {
            Write-Host "Would archive ${Label}: $name"
        }
    }
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$dailyFilter = @{ property = "Cadence"; select = @{ equals = "Daily" } }
$dailyTemplates = Invoke-DatabaseQuery -DatabaseId $TemplatesDatabaseId -Filter $dailyFilter
$dailyChores = Invoke-DatabaseQuery -DatabaseId $ChoresDatabaseId -Filter $dailyFilter

Write-Host "Sub-weekly chore cleanup. Apply=$Apply"
Write-Host "Daily templates found: $($dailyTemplates.Count)"
Write-Host "Daily chore instances found: $($dailyChores.Count)"

Archive-Pages -Pages $dailyTemplates -Label "template"
Archive-Pages -Pages $dailyChores -Label "chore"
