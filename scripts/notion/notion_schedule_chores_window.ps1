param(
    [string]$StartDate = "",
    [int]$Days = 28,
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

function New-RichText {
    param([string]$Text)
    if (-not $Text) { return @() }
    return ,@(@{ type = "text"; text = @{ content = $Text } })
}

function TitleValue { param([string]$Value) return @{ title = (New-RichText -Text $Value) } }
function TextValue { param([string]$Value) return @{ rich_text = (New-RichText -Text $Value) } }
function SelectValue { param([string]$Value) if (-not $Value) { return @{ select = $null } } return @{ select = @{ name = $Value } } }
function NumberValue { param($Value) if ($null -eq $Value) { return @{ number = $null } } return @{ number = [double]$Value } }
function CheckboxValue { param([bool]$Value) return @{ checkbox = $Value } }
function DateValue { param([string]$Value) return @{ date = @{ start = $Value } } }

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
        $parameters["Body"] = ($Body | ConvertTo-Json -Depth 30)
    }
    return Invoke-RestMethod @parameters
}

function Invoke-DatabaseQuery {
    param([string]$DatabaseId, $Filter = $null)
    $results = @()
    $cursor = $null
    do {
        $body = @{ page_size = 100 }
        if ($Filter) { $body.filter = $Filter }
        if ($cursor) { $body.start_cursor = $cursor }
        $response = Invoke-NotionApi -Method "POST" -Path "/databases/$DatabaseId/query" -Body $body
        $results += $response.results
        $cursor = $response.next_cursor
    } while ($response.has_more)
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

    if ($cadence -eq "Daily") { return $true }
    if ($cadence -eq "Weekly" -and $preferredDay -and $preferredDay -eq $dayName) { return $true }
    if ($cadence -eq "Biweekly" -and $preferredDay -and $preferredDay -eq $dayName) { return $true }
    if ($cadence -eq "Monthly" -and $dayOfMonth -and [int]$dayOfMonth -eq $Date.Day) { return $true }
    if ($cadence -eq "Quarterly" -and $dayOfMonth -and [int]$dayOfMonth -eq $Date.Day -and (($Date.Month - 1) % 3 -eq 0)) { return $true }

    return $false
}

function New-ChoreKey {
    param([string]$Name, [string]$Date)
    return ("$Name|$Date").ToLowerInvariant()
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

if (-not $StartDate) {
    $StartDate = (Get-Date).ToString("yyyy-MM-dd")
}

$start = [datetime]::ParseExact($StartDate, "yyyy-MM-dd", $null)
$end = $start.AddDays($Days - 1)
Write-Host "Planning chores from $($start.ToString('yyyy-MM-dd')) through $($end.ToString('yyyy-MM-dd')). Apply=$Apply"

$templates = Invoke-DatabaseQuery -DatabaseId $TemplatesDatabaseId -Filter @{ property = "Active"; checkbox = @{ equals = $true } }
$chores = Invoke-DatabaseQuery -DatabaseId $ChoresDatabaseId -Filter @{
    and = @(
        @{ property = "Date"; date = @{ on_or_after = $start.ToString("yyyy-MM-dd") } },
        @{ property = "Date"; date = @{ on_or_before = $end.ToString("yyyy-MM-dd") } }
    )
}

$existingKeys = @{}
foreach ($chore in $chores) {
    $name = Get-TitleText $chore.properties.Name
    $date = $chore.properties.Date.date.start
    if ($name -and $date) {
        $existingKeys[(New-ChoreKey -Name $name -Date $date.Substring(0, 10))] = $true
    }
}

$created = @()
$alreadyPresent = 0
$dueCount = 0

for ($offset = 0; $offset -lt $Days; $offset++) {
    $date = $start.AddDays($offset)
    $dateText = $date.ToString("yyyy-MM-dd")

    foreach ($template in $templates) {
        if (-not (Test-TemplateDueOnDate -Template $template -Date $date)) { continue }
        $dueCount++

        $props = $template.properties
        $name = Get-TitleText $props.Name
        if (-not $name) { continue }

        $key = New-ChoreKey -Name $name -Date $dateText
        if ($existingKeys.ContainsKey($key)) {
            $alreadyPresent++
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
                Date = DateValue $dateText
                Done = CheckboxValue $false
                Template = TextValue $name
                Zone = SelectValue $zone
                Cadence = SelectValue $cadence
                "Estimate Minutes" = NumberValue $estimateMinutes
                Status = SelectValue "Not started"
                "Reminder Policy" = SelectValue "Chore reminder"
                Notes = TextValue $notes
            }
        }

        if ($Apply) {
            [void](Invoke-NotionApi -Method "POST" -Path "/pages" -Body $row)
        }
        $created += "$dateText - $name"
        $existingKeys[$key] = $true
    }
}

Write-Host "Due in window: $dueCount"
Write-Host "Already present: $alreadyPresent"
Write-Host "Created: $($created.Count)"
foreach ($item in $created) { Write-Host "  - $item" }
