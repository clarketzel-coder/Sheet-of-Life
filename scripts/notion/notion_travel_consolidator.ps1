param(
    [string]$EventsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$TravelDatabaseId = "380e8e29-9eae-8119-a19e-f9f743f62bff",
    [string]$TripName = "Trip: June 21-25, 2026",
    [string]$TripKey = "trip-2026-06-21-2026-06-25",
    [string]$TripStart = "2026-06-21",
    [string]$TripEnd = "2026-06-25",
    [switch]$Apply,
    [string]$NotionVersion = "2022-06-28"
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

function ConvertTo-NotionId {
    param([string]$Value)
    $hex = ($Value -replace "-", "").ToLowerInvariant()
    if ($hex -notmatch "^[0-9a-f]{32}$") {
        throw "Notion ID must contain 32 hex characters. Received '$Value'."
    }
    return "{0}-{1}-{2}-{3}-{4}" -f $hex.Substring(0, 8), $hex.Substring(8, 4), $hex.Substring(12, 4), $hex.Substring(16, 4), $hex.Substring(20, 12)
}

function New-RichText {
    param([string]$Text)
    if (-not $Text) { return @() }
    return ,@(@{ type = "text"; text = @{ content = $Text } })
}

function TitleValue { param([string]$Value) return @{ title = (New-RichText -Text $Value) } }
function TextValue { param([string]$Value) return @{ rich_text = (New-RichText -Text $Value) } }
function SelectValue { param([string]$Value) return @{ select = @{ name = $Value } } }
function DateValue { param([string]$Value) return @{ date = @{ start = $Value } } }
function DateRangeValue { param([string]$Start, [string]$End) return @{ date = @{ start = $Start; end = $End } } }
function RelationValue { param([string]$PageId) if (-not $PageId) { return @{ relation = @() } } return @{ relation = @(@{ id = $PageId }) } }

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

function New-SelectSchema {
    param([string[]]$Options)
    return @{ select = @{ options = @($Options | ForEach-Object { @{ name = $_; color = "default" } }) } }
}

function Ensure-DatabaseProperties {
    param([string]$DatabaseId, [hashtable]$Properties)
    $database = Invoke-NotionApi -Method "GET" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)"
    $patch = @{}
    foreach ($name in $Properties.Keys) {
        if (-not $database.properties.PSObject.Properties.Name.Contains($name)) {
            $patch[$name] = $Properties[$name]
        }
    }
    if ($patch.Count -eq 0) {
        Write-Host "No schema updates needed for $($database.title[0].plain_text)."
        return
    }
    [void](Invoke-NotionApi -Method "PATCH" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)" -Body @{ properties = $patch })
    Write-Host "Updated $($database.title[0].plain_text): added $($patch.Keys -join ', ')."
}

function Get-PlainText {
    param($RichText)
    if (-not $RichText) { return "" }
    return (($RichText | ForEach-Object { $_.plain_text }) -join "")
}

function Get-PageTitle {
    param($Page)
    foreach ($property in $Page.properties.PSObject.Properties) {
        if ($property.Value.type -eq "title") {
            return Get-PlainText $property.Value.title
        }
    }
    return ""
}

function Find-PageByRichText {
    param([string]$DatabaseId, [string]$PropertyName, [string]$Value)
    $body = @{ page_size = 1; filter = @{ property = $PropertyName; rich_text = @{ equals = $Value } } }
    $result = Invoke-NotionApi -Method "POST" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)/query" -Body $body
    if ($result.results.Count -gt 0) { return $result.results[0] }
    return $null
}

function Ensure-TravelTripEnvelope {
    $existing = Find-PageByRichText -DatabaseId $TravelDatabaseId -PropertyName "Trip Key" -Value $TripKey
    $properties = @{
        Name = TitleValue $TripName
        Kind = SelectValue "Trip"
        Status = SelectValue "Confirmed"
        Start = DateValue $TripStart
        End = DateRangeValue -Start $TripStart -End $TripEnd
        "Calendar Block" = DateRangeValue -Start $TripStart -End $TripEnd
        "Calendar Category" = SelectValue "Travel"
        "Trip Key" = TextValue $TripKey
        "Segment Role" = SelectValue "Other"
        Notes = TextValue "Canonical trip envelope. Flight segment rows share this Trip Key."
    }

    if (-not $Apply) {
        Write-Host "Would ensure Travel trip envelope: $TripName"
        if ($existing) { return $existing.id }
        return $null
    }

    if ($existing) {
        [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($existing.id)" -Body @{ properties = $properties })
        Write-Host "Updated Travel trip envelope: $TripName"
        return $existing.id
    }

    $created = Invoke-NotionApi -Method "POST" -Path "/pages" -Body @{ parent = @{ database_id = (ConvertTo-NotionId -Value $TravelDatabaseId) }; properties = $properties }
    Write-Host "Created Travel trip envelope: $TripName"
    return $created.id
}

function Archive-EventsTripEnvelope {
    $existing = Find-PageByRichText -DatabaseId $EventsDatabaseId -PropertyName "Trip Key" -Value $TripKey
    if (-not $existing) { return }
    if (-not $Apply) {
        Write-Host "Would archive Events & Trips duplicate envelope: $(Get-PageTitle $existing)"
        return
    }
    [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($existing.id)" -Body @{ archived = $true })
    Write-Host "Archived Events & Trips duplicate trip envelope."
}

function New-FlightSegment {
    param(
        [string]$Name,
        [string]$FlightNumber,
        [string]$Provider,
        [string]$From,
        [string]$To,
        [string]$Start,
        [string]$End,
        [string]$UniqueKey,
        [string]$SegmentRole,
        [string]$TripPageId
    )

    $existing = Find-PageByRichText -DatabaseId $TravelDatabaseId -PropertyName "Unique Key" -Value $UniqueKey
    $properties = @{
        Name = TitleValue $Name
        Kind = SelectValue "Flight"
        Status = SelectValue "Confirmed"
        Start = DateValue $Start
        End = DateRangeValue -Start $Start -End $End
        "Calendar Block" = DateRangeValue -Start $Start -End $End
        "Calendar Category" = SelectValue "Travel"
        Provider = TextValue $Provider
        "Flight Number" = TextValue $FlightNumber
        From = TextValue $From
        To = TextValue $To
        "Unique Key" = TextValue $UniqueKey
        "Trip Key" = TextValue $TripKey
        "Segment Role" = SelectValue $SegmentRole
        Notes = TextValue "Consolidated from local travel-agent state. Source state recorded original segment key."
    }

    $properties["Parent Trip"] = RelationValue $TripPageId

    if (-not $Apply) {
        Write-Host "Would upsert flight: $Name $Start -> $End"
        return
    }

    if ($existing) {
        [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($existing.id)" -Body @{ properties = $properties })
        Write-Host "Updated flight: $Name"
    }
    else {
        [void](Invoke-NotionApi -Method "POST" -Path "/pages" -Body @{ parent = @{ database_id = (ConvertTo-NotionId -Value $TravelDatabaseId) }; properties = $properties })
        Write-Host "Created flight: $Name"
    }
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

Ensure-DatabaseProperties -DatabaseId $TravelDatabaseId -Properties @{
    "Trip Key" = @{ rich_text = @{} }
    "Segment Role" = New-SelectSchema -Options @("Trip", "Outbound", "Return", "Connection", "Other")
    "Parent Trip" = @{ relation = @{ database_id = (ConvertTo-NotionId -Value $TravelDatabaseId); type = "single_property"; single_property = @{} } }
}

$tripPageId = Ensure-TravelTripEnvelope
Archive-EventsTripEnvelope

# These four segments are the imported travel-agent records preserved in .sol_flight_sync_state.json.
# The user's return flights were moved from Wednesday 2026-06-24 to Thursday 2026-06-25 at the same local times.
$segments = @(
    @{ Name = "Flight to Chicago (AA 3716)"; FlightNumber = "AA 3716"; Provider = "American Airlines"; From = "MSN"; To = "ORD"; Start = "2026-06-21T14:42-05:00"; End = "2026-06-21T15:54-05:00"; UniqueKey = "flight|aa3716|2026-06-21t14:42|msn|ord"; SegmentRole = "Outbound" },
    @{ Name = "Flight to Rochester (AA 6438)"; FlightNumber = "AA 6438"; Provider = "American Airlines"; From = "ORD"; To = "ROC"; Start = "2026-06-21T16:52-05:00"; End = "2026-06-21T19:49-04:00"; UniqueKey = "flight|aa6438|2026-06-21t16:52|ord|roc"; SegmentRole = "Outbound" },
    @{ Name = "Flight to Chicago (UA 2059)"; FlightNumber = "UA 2059"; Provider = "United Airlines"; From = "ROC"; To = "ORD"; Start = "2026-06-25T17:52-04:00"; End = "2026-06-25T19:00-05:00"; UniqueKey = "flight|ua2059|2026-06-24t17:52|roc|ord"; SegmentRole = "Return" },
    @{ Name = "Flight to Madison (UA 630)"; FlightNumber = "UA 630"; Provider = "United Airlines"; From = "ORD"; To = "MSN"; Start = "2026-06-25T22:00-05:00"; End = "2026-06-25T23:12-05:00"; UniqueKey = "flight|ua1400|2026-06-24t21:53|ord|msn"; SegmentRole = "Return" }
)

foreach ($segment in $segments) {
    New-FlightSegment @segment -TripPageId $tripPageId
}

Write-Host "Travel consolidation complete. Apply=$Apply"
