param(
    [string]$TargetDate = "2026-06-14",
    [string]$TemplatesDatabaseId = "37fe8e29-9eae-8113-88c0-dda7166e8d3d",
    [string]$ChoresDatabaseId = "37fe8e29-9eae-81de-a1bd-db293503adfa",
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
function NumberValue {
    param($Value)
    if ($null -eq $Value) { return @{ number = $null } }
    return @{ number = [double]$Value }
}
function CheckboxValue { param([bool]$Value) return @{ checkbox = $Value } }
function DateValue { param([string]$Value) return @{ date = @{ start = $Value } } }

function Invoke-NotionApi {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [hashtable]$Body
    )

    $headers = @{
        Authorization = "Bearer $script:NotionToken"
        "Notion-Version" = $NotionVersion
        "Content-Type" = "application/json"
    }

    $uri = "https://api.notion.com/v1$Path"
    if ($Body) {
        $jsonBody = $Body | ConvertTo-Json -Depth 30
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $jsonBody
    }

    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
}

function Invoke-DatabaseQuery {
    param(
        [Parameter(Mandatory = $true)][string]$DatabaseId,
        [hashtable]$Filter
    )

    $results = @()
    $hasMore = $true
    $cursor = $null

    while ($hasMore) {
        $body = @{}
        if ($Filter) { $body.filter = $Filter }
        if ($cursor) { $body.start_cursor = $cursor }

        $response = Invoke-NotionApi -Method "POST" -Path "/databases/$DatabaseId/query" -Body $body
        $results += $response.results
        $hasMore = [bool]$response.has_more
        $cursor = $response.next_cursor
    }

    return $results
}

function Get-TitleText {
    param($Property)
    if (-not $Property -or -not $Property.title) { return "" }
    return (($Property.title | ForEach-Object { $_.plain_text }) -join "")
}

function Get-RichText {
    param($Property)
    if (-not $Property -or -not $Property.rich_text) { return "" }
    return (($Property.rich_text | ForEach-Object { $_.plain_text }) -join "")
}

function Get-SelectName {
    param($Property)
    if (-not $Property -or -not $Property.select) { return "" }
    return $Property.select.name
}

function Get-Number {
    param($Property)
    if (-not $Property) { return $null }
    return $Property.number
}

function Test-TemplateDueOnDate {
    param($Template, [datetime]$Date)

    $props = $Template.properties
    $cadence = Get-SelectName $props.Cadence
    $preferredDay = Get-SelectName $props.'Preferred Day'
    $dayOfMonth = Get-Number $props.'Day of Month'
    $dayName = $Date.ToString("ddd")

    if ($cadence -eq "Daily") {
        return $true
    }

    if ($preferredDay -and $preferredDay -eq $dayName) {
        return $true
    }

    if ($dayOfMonth -and [int]$dayOfMonth -eq $Date.Day) {
        return $true
    }

    return $false
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"

if (-not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$date = [datetime]::ParseExact($TargetDate, "yyyy-MM-dd", $null)
$dayName = $date.ToString("dddd")
Write-Host "Updating Chores due on $TargetDate ($dayName)."

$activeTemplateFilter = @{
    property = "Active"
    checkbox = @{ equals = $true }
}

$existingChoresFilter = @{
    and = @(
        @{
            property = "Date"
            date = @{ equals = $TargetDate }
        },
        @{
            property = "Status"
            select = @{ does_not_equal = "Done" }
        }
    )
}

$templates = Invoke-DatabaseQuery -DatabaseId $TemplatesDatabaseId -Filter $activeTemplateFilter
$existingChores = Invoke-DatabaseQuery -DatabaseId $ChoresDatabaseId -Filter $existingChoresFilter

$existingNames = @{}
foreach ($chore in $existingChores) {
    $name = Get-TitleText $chore.properties.Name
    if ($name) {
        $existingNames[$name.ToLowerInvariant()] = $true
    }
}

$created = @()
$alreadyPresent = @()
$notDue = @()

foreach ($template in $templates) {
    $props = $template.properties
    $name = Get-TitleText $props.Name
    if (-not $name) {
        continue
    }

    if (-not (Test-TemplateDueOnDate -Template $template -Date $date)) {
        $notDue += $name
        continue
    }

    if ($existingNames.ContainsKey($name.ToLowerInvariant())) {
        $alreadyPresent += $name
        continue
    }

    $zone = Get-SelectName $props.Zone
    $cadence = Get-SelectName $props.Cadence
    $estimateMinutes = Get-Number $props.'Estimate Minutes'
    $notes = Get-RichText $props.Notes

    $row = @{
        parent = @{ database_id = $ChoresDatabaseId }
        properties = @{
            Name = TitleValue $name
            Date = DateValue $TargetDate
            Done = CheckboxValue $false
            Template = TextValue $name
            Zone = SelectValue $zone
            Cadence = SelectValue $cadence
            "Estimate Minutes" = NumberValue $estimateMinutes
            Status = SelectValue "Not started"
            Notes = TextValue $notes
        }
    }

    [void](Invoke-NotionApi -Method "POST" -Path "/pages" -Body $row)
    $created += $name
    Write-Host "Created: $name"
}

Write-Host ""
Write-Host "Due today and created: $($created.Count)"
foreach ($name in $created) { Write-Host "  - $name" }

Write-Host "Due today and already present: $($alreadyPresent.Count)"
foreach ($name in $alreadyPresent) { Write-Host "  - $name" }

Write-Host "Not due today: $($notDue.Count)"
Write-Host "Done."
