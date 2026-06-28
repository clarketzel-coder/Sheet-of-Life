param(
    [string]$EventsTripsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$TravelDatabaseId = "380e8e29-9eae-8119-a19e-f9f743f62bff",
    [string]$PeopleDatabaseId = "37fe8e29-9eae-819c-98be-f20d83340774",
    [string]$BlocksVersion = "2022-06-28"
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

function Invoke-NotionApi {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null
    )

    $parameters = @{
        Method = $Method
        Uri = "https://api.notion.com/v1$Path"
        Headers = @{
            Authorization = "Bearer $script:NotionToken"
            "Notion-Version" = $BlocksVersion
            "Content-Type" = "application/json"
        }
    }

    if ($null -ne $Body) {
        $parameters["Body"] = ($Body | ConvertTo-Json -Depth 40)
    }

    return Invoke-RestMethod @parameters
}

function Get-PlainText {
    param($RichText)
    return (($RichText | ForEach-Object { $_.plain_text }) -join "")
}

function Get-TitleFromPage {
    param($Page)

    foreach ($property in $Page.properties.PSObject.Properties) {
        if ($property.Value.type -eq "title") {
            return Get-PlainText -RichText $property.Value.title
        }
    }

    return ""
}

function Get-AllDatabasePages {
    param(
        [string]$DatabaseId,
        $Filter = $null
    )

    $pages = @()
    $cursor = ""
    do {
        $body = @{ page_size = 100 }
        if ($Filter) { $body["filter"] = $Filter }
        if ($cursor) { $body["start_cursor"] = $cursor }

        $response = Invoke-NotionApi -Method "POST" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)/query" -Body $body
        $pages += @($response.results)
        $cursor = ""
        if ($response.has_more) { $cursor = $response.next_cursor }
    } while ($cursor)

    return $pages
}

function New-TitleValue {
    param([string]$Text)
    return @{ title = @(@{ type = "text"; text = @{ content = $Text } }) }
}

function New-SelectValue {
    param([string]$Name)
    return @{ select = @{ name = $Name } }
}

function New-DateValue {
    param([string]$Start, [string]$End = "")

    $date = @{ start = $Start }
    if ($End) { $date["end"] = $End }
    return @{ date = $date }
}

function New-RichTextValue {
    param([string]$Text)
    return @{ rich_text = @(@{ type = "text"; text = @{ content = $Text } }) }
}

function Get-SelectOption {
    param(
        $Database,
        [string]$PropertyName,
        [string]$Name
    )

    $property = $Database.properties.$PropertyName
    if (-not $property -or $property.type -ne "select") { return $null }

    return @($property.select.options | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Set-SelectOptions {
    param(
        [string]$DatabaseId,
        [string]$PropertyName,
        [array]$DesiredOptions
    )

    $database = Invoke-NotionApi -Method "GET" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)"
    $property = $database.properties.$PropertyName
    if (-not $property -or $property.type -ne "select") {
        Write-Host "Skipping $PropertyName on $DatabaseId; it is not a select property."
        return
    }

    $merged = @()
    foreach ($option in $property.select.options) {
        $merged += @{ name = $option.name; color = $option.color }
    }

    foreach ($desired in $DesiredOptions) {
        if (-not (Get-SelectOption -Database $database -PropertyName $PropertyName -Name $desired.name)) {
            $merged += @{ name = $desired.name; color = $desired.color }
        }
    }

    [void](Invoke-NotionApi -Method "PATCH" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)" -Body @{
        properties = @{
            $PropertyName = @{
                select = @{
                    options = $merged
                }
            }
        }
    })
    Write-Host "Updated $PropertyName colors/options on database $DatabaseId."
}

function Get-NextBirthday {
    param([string]$BirthdayStart)

    $birthday = [DateTime]::Parse($BirthdayStart)
    $today = (Get-Date).Date
    $year = $today.Year
    $candidate = Get-Date -Year $year -Month $birthday.Month -Day $birthday.Day
    if ($candidate.Date -lt $today) {
        $candidate = Get-Date -Year ($year + 1) -Month $birthday.Month -Day $birthday.Day
    }

    return $candidate.ToString("yyyy-MM-dd")
}

function Find-BirthdayEvent {
    param([string]$PersonName)

    $result = Get-AllDatabasePages -DatabaseId $EventsTripsDatabaseId -Filter @{
        and = @(
            @{ property = "Name"; title = @{ equals = "Birthday - $PersonName" } },
            @{ property = "Type"; select = @{ equals = "Birthday" } }
        )
    }
    return @($result | Select-Object -First 1)
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$eventCategories = @(
    @{ name = "Birthday"; color = "purple" },
    @{ name = "Appointment"; color = "blue" },
    @{ name = "Event"; color = "green" },
    @{ name = "Social"; color = "pink" },
    @{ name = "Food"; color = "orange" },
    @{ name = "Travel"; color = "yellow" },
    @{ name = "Flight"; color = "red" },
    @{ name = "Home"; color = "brown" },
    @{ name = "Review"; color = "gray" }
)
$eventTypes = @(
    @{ name = "Event"; color = "green" },
    @{ name = "Trip"; color = "yellow" },
    @{ name = "Appointment"; color = "blue" },
    @{ name = "Birthday"; color = "purple" }
)
$calendarStatuses = @(
    @{ name = "Draft"; color = "gray" },
    @{ name = "Tentative"; color = "yellow" },
    @{ name = "Confirmed"; color = "green" },
    @{ name = "Needs Review"; color = "orange" },
    @{ name = "Canceled"; color = "red" }
)
$travelCategories = @(
    @{ name = "Travel"; color = "yellow" },
    @{ name = "Flight"; color = "red" },
    @{ name = "Lodging"; color = "blue" },
    @{ name = "Transit"; color = "orange" },
    @{ name = "Activity"; color = "green" }
)

Set-SelectOptions -DatabaseId $EventsTripsDatabaseId -PropertyName "Category" -DesiredOptions $eventCategories
Set-SelectOptions -DatabaseId $EventsTripsDatabaseId -PropertyName "Type" -DesiredOptions $eventTypes
Set-SelectOptions -DatabaseId $EventsTripsDatabaseId -PropertyName "Calendar Status" -DesiredOptions $calendarStatuses
Set-SelectOptions -DatabaseId $TravelDatabaseId -PropertyName "Calendar Category" -DesiredOptions $travelCategories

$people = Get-AllDatabasePages -DatabaseId $PeopleDatabaseId -Filter @{ property = "Birthday"; date = @{ is_not_empty = $true } }
$birthdayCount = 0
foreach ($person in $people) {
    $personName = Get-TitleFromPage -Page $person
    if (-not $personName) { continue }

    $birthdayStart = $person.properties.Birthday.date.start
    if (-not $birthdayStart) { continue }

    $nextBirthday = Get-NextBirthday -BirthdayStart $birthdayStart
    $properties = @{
        Name = New-TitleValue -Text "Birthday - $personName"
        Type = New-SelectValue -Name "Birthday"
        Category = New-SelectValue -Name "Birthday"
        Date = New-DateValue -Start $nextBirthday
        "Calendar Block" = New-DateValue -Start $nextBirthday
        "Calendar Status" = New-SelectValue -Name "Confirmed"
        "Food Included" = @{ checkbox = $false }
        "Food Plan" = New-SelectValue -Name "No food"
        Notes = New-RichTextValue -Text "Synced from People birthday for $personName."
    }

    $existing = Find-BirthdayEvent -PersonName $personName
    if ($existing) {
        [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($existing.id)" -Body @{ properties = $properties })
        Write-Host "Updated birthday calendar event: $personName -> $nextBirthday"
    } else {
        [void](Invoke-NotionApi -Method "POST" -Path "/pages" -Body @{
            parent = @{ database_id = (ConvertTo-NotionId -Value $EventsTripsDatabaseId) }
            properties = $properties
        })
        Write-Host "Created birthday calendar event: $personName -> $nextBirthday"
    }
    $birthdayCount++
}

$events = Get-AllDatabasePages -DatabaseId $EventsTripsDatabaseId
$eventUpdatedCount = 0
foreach ($event in $events) {
    $props = @{}
    $type = $event.properties.Type.select.name
    $category = $event.properties.Category.select.name
    $date = $event.properties.Date.date.start
    $calendarBlock = $event.properties."Calendar Block".date.start
    $calendarStatus = $event.properties."Calendar Status".select.name

    if ($date -and -not $calendarBlock) {
        $props["Calendar Block"] = New-DateValue -Start $date -End $event.properties.Date.date.end
    }

    if (-not $calendarStatus) {
        $props["Calendar Status"] = New-SelectValue -Name "Confirmed"
    }

    if (-not $category) {
        $mappedCategory = switch ($type) {
            "Birthday" { "Birthday" }
            "Appointment" { "Appointment" }
            "Trip" { "Travel" }
            default { "Event" }
        }
        $props["Category"] = New-SelectValue -Name $mappedCategory
    }

    if ($props.Count -gt 0) {
        [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($event.id)" -Body @{ properties = $props })
        $eventUpdatedCount++
    }
}

$travel = Get-AllDatabasePages -DatabaseId $TravelDatabaseId
$travelUpdatedCount = 0
foreach ($item in $travel) {
    $props = @{}
    $kind = $item.properties.Kind.select.name
    $start = $item.properties.Start.date.start
    $calendarBlock = $item.properties."Calendar Block".date.start
    $calendarCategory = $item.properties."Calendar Category".select.name

    if ($start -and -not $calendarBlock) {
        $props["Calendar Block"] = New-DateValue -Start $start -End $item.properties.Start.date.end
    }

    if (-not $calendarCategory) {
        $mappedTravelCategory = switch ($kind) {
            "Flight" { "Flight" }
            "Hotel" { "Lodging" }
            "Lodging" { "Lodging" }
            "Transit" { "Transit" }
            "Activity" { "Activity" }
            default { "Travel" }
        }
        $props["Calendar Category"] = New-SelectValue -Name $mappedTravelCategory
    }

    if ($props.Count -gt 0) {
        [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($item.id)" -Body @{ properties = $props })
        $travelUpdatedCount++
    }
}

Write-Host "Calendar readiness complete: $birthdayCount birthday events synced, $eventUpdatedCount event rows normalized, $travelUpdatedCount travel rows normalized."
Write-Host "In Notion Calendar, add/show the Events & Trips database using Calendar Block, and Travel using Calendar Block. App source colors are adjusted inside Notion Calendar."
