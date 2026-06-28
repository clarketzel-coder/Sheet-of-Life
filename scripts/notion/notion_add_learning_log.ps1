param(
    [Parameter(Mandatory = $true)][string]$Topic,
    [Parameter(Mandatory = $true)][double]$Hours,
    [string]$Date = "2026-06-14",
    [string]$Notes = "",
    [string]$Outcome = "",
    [string]$NextStep = "",
    [string]$Source = "Manual",
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

function New-RichText {
    param([string]$Text)
    return ,@(@{ type = "text"; text = @{ content = $Text } })
}

function TitleValue { param([string]$Value) return @{ title = (New-RichText -Text $Value) } }
function TextValue {
    param([string]$Value)
    if (-not $Value) { return @{ rich_text = @() } }
    return @{ rich_text = (New-RichText -Text $Value) }
}
function SelectValue { param([string]$Value) return @{ select = @{ name = $Value } } }
function NumberValue { param([double]$Value) return @{ number = $Value } }
function DateValue { param([string]$Value) return @{ date = @{ start = $Value } } }
function Get-DatabaseProperties {
    param(
        [string]$DatabaseId,
        [hashtable]$Headers
    )

    $database = Invoke-RestMethod -Method "GET" -Uri "https://api.notion.com/v1/databases/$DatabaseId" -Headers $Headers
    $properties = @{}
    foreach ($property in $database.properties.PSObject.Properties) {
        $properties[$property.Name] = $true
    }
    return $properties
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

$databaseProperties = Get-DatabaseProperties -DatabaseId $LearningLogDatabaseId -Headers $headers
$entryName = "$Topic - $Date"
$properties = @{
    Name = TitleValue $entryName
    Date = DateValue $Date
    Topic = SelectValue $Topic
    Hours = NumberValue $Hours
    Notes = TextValue $Notes
}
if ($Outcome -and $databaseProperties.ContainsKey("Outcome")) { $properties.Outcome = SelectValue $Outcome }
if ($NextStep -and $databaseProperties.ContainsKey("Next Step")) { $properties["Next Step"] = TextValue $NextStep }
if ($Source -and $databaseProperties.ContainsKey("Source")) { $properties.Source = SelectValue $Source }

$body = @{
    parent = @{ database_id = $LearningLogDatabaseId }
    properties = $properties
}

$jsonBody = $body | ConvertTo-Json -Depth 30
[void](Invoke-RestMethod -Method "POST" -Uri "https://api.notion.com/v1/pages" -Headers $headers -Body $jsonBody)
Write-Host "Logged $Hours hour(s) for $Topic on $Date."
