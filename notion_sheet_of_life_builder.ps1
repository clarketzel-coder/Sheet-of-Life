param(
    [string]$ParentPageId = "",
    [string]$PrototypeTitle = "Sheet of Life OS - Prototype",
    [switch]$DryRun,
    [switch]$VerboseDryRun,
    [string]$NotionVersion = "2022-06-28"
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

function ConvertTo-NotionPageId {
    param([string]$Value)

    $clean = ($Value -replace "[^0-9a-fA-F]", "").ToLowerInvariant()
    if ($clean.Length -ne 32) {
        throw "Parent page ID must contain 32 hex characters. Received '$Value'."
    }

    return "{0}-{1}-{2}-{3}-{4}" -f `
        $clean.Substring(0, 8), `
        $clean.Substring(8, 4), `
        $clean.Substring(12, 4), `
        $clean.Substring(16, 4), `
        $clean.Substring(20, 12)
}

function New-RichText {
    param([string]$Text)
    return ,@(@{ type = "text"; text = @{ content = $Text } })
}

function New-TitlePropertyValue {
    param([string]$Text)
    return @{ title = (New-RichText -Text $Text) }
}

function New-RichTextPropertyValue {
    param([string]$Text)
    if (-not $Text) {
        return @{ rich_text = @() }
    }

    return @{ rich_text = (New-RichText -Text $Text) }
}

function New-PropertySchema {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [string[]]$Options = @()
    )

    switch ($Type) {
        "title" { return @{ title = @{} } }
        "rich_text" { return @{ rich_text = @{} } }
        "number" { return @{ number = @{ format = "number" } } }
        "checkbox" { return @{ checkbox = @{} } }
        "date" { return @{ date = @{} } }
        "select" {
            return @{
                select = @{
                    options = @($Options | ForEach-Object { @{ name = $_ } })
                }
            }
        }
        "multi_select" {
            return @{
                multi_select = @{
                    options = @($Options | ForEach-Object { @{ name = $_ } })
                }
            }
        }
        default { throw "Unsupported property type '$Type'." }
    }
}

function New-DatabasePropertyMap {
    param([object[]]$Definitions)

    $properties = @{}
    foreach ($definition in $Definitions) {
        $properties[$definition.Name] = New-PropertySchema -Type $definition.Type -Options $definition.Options
    }
    return $properties
}

function Invoke-NotionApi {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [hashtable]$Body
    )

    if ($DryRun) {
        $label = ""
        if ($Body.title -and $Body.title.Count -gt 0) {
            $label = " - $($Body.title[0].text.content)"
        } elseif ($Body.properties) {
            foreach ($titleKey in @("title", "Name", "Item")) {
                if ($Body.properties[$titleKey]) {
                    $titleValue = $Body.properties[$titleKey]
                    if ($titleValue.title -and $titleValue.title.Count -gt 0) {
                        $label = " - $($titleValue.title[0].text.content)"
                    }
                    break
                }
            }
        }

        Write-Host "DRY RUN $Method $Path$label"
        if ($VerboseDryRun -and $Body) {
            $json = $Body | ConvertTo-Json -Depth 30
            Write-Host $json
        }
        return @{ id = "dry_run_$([guid]::NewGuid().ToString("N"))" }
    }

    $headers = @{
        Authorization = "Bearer $script:NotionToken"
        "Notion-Version" = $NotionVersion
        "Content-Type" = "application/json"
    }

    $uri = "https://api.notion.com/v1$Path"
    $jsonBody = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $jsonBody
}

function New-NotionPage {
    param(
        [Parameter(Mandatory = $true)][string]$ParentPageId,
        [Parameter(Mandatory = $true)][string]$Title
    )

    $body = @{
        parent = @{ page_id = $ParentPageId }
        properties = @{
            title = New-TitlePropertyValue -Text $Title
        }
    }

    return Invoke-NotionApi -Method "POST" -Path "/pages" -Body $body
}

function New-NotionDatabase {
    param(
        [Parameter(Mandatory = $true)][string]$ParentPageId,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][object[]]$Properties
    )

    $body = @{
        parent = @{ page_id = $ParentPageId }
        title = New-RichText -Text $Title
        properties = New-DatabasePropertyMap -Definitions $Properties
    }

    return Invoke-NotionApi -Method "POST" -Path "/databases" -Body $body
}

function New-DatabaseRow {
    param(
        [Parameter(Mandatory = $true)][string]$DatabaseId,
        [Parameter(Mandatory = $true)][hashtable]$Properties
    )

    $body = @{
        parent = @{ database_id = $DatabaseId }
        properties = $Properties
    }

    return Invoke-NotionApi -Method "POST" -Path "/pages" -Body $body
}

function TitleValue { param([string]$Value) return New-TitlePropertyValue -Text $Value }
function TextValue { param([string]$Value) return New-RichTextPropertyValue -Text $Value }
function SelectValue { param([string]$Value) return @{ select = @{ name = $Value } } }
function NumberValue { param([double]$Value) return @{ number = $Value } }
function CheckboxValue { param([bool]$Value) return @{ checkbox = $Value } }

$databaseDefinitions = @(
    @{
        Title = "Chore Templates"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Zone"; Type = "select"; Options = @("Kitchen", "Bathroom", "Bedroom", "Floors", "Living", "Admin") },
            @{ Name = "Cadence"; Type = "select"; Options = @("Daily", "Weekly", "Biweekly", "Monthly", "Quarterly") },
            @{ Name = "Preferred Day"; Type = "select"; Options = @("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat") },
            @{ Name = "Day of Month"; Type = "number" },
            @{ Name = "Flex Days"; Type = "number" },
            @{ Name = "Estimate Minutes"; Type = "number" },
            @{ Name = "Active"; Type = "checkbox" },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Chores"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Date"; Type = "date" },
            @{ Name = "Done"; Type = "checkbox" },
            @{ Name = "Done Date"; Type = "date" },
            @{ Name = "Template"; Type = "rich_text" },
            @{ Name = "Zone"; Type = "select"; Options = @("Kitchen", "Bathroom", "Bedroom", "Floors", "Living", "Admin") },
            @{ Name = "Cadence"; Type = "select"; Options = @("Daily", "Weekly", "Biweekly", "Monthly", "Quarterly") },
            @{ Name = "Estimate Minutes"; Type = "number" },
            @{ Name = "Status"; Type = "select"; Options = @("Scheduled", "Moved", "Done", "Skipped") },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Apartment Zones"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Type"; Type = "select"; Options = @("Room", "Surface", "Admin", "Storage") },
            @{ Name = "Weekly Weight"; Type = "number" },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Recipes"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Cuisine"; Type = "multi_select"; Options = @() },
            @{ Name = "Servings"; Type = "number" },
            @{ Name = "Calories"; Type = "number" },
            @{ Name = "Protein"; Type = "number" },
            @{ Name = "Ingredients"; Type = "rich_text" },
            @{ Name = "Instructions"; Type = "rich_text" },
            @{ Name = "Active"; Type = "checkbox" }
        )
    },
    @{
        Title = "Meal Plan"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Date"; Type = "date" },
            @{ Name = "Slot"; Type = "select"; Options = @("Breakfast", "Lunch", "Dinner", "Snack") },
            @{ Name = "Recipe"; Type = "rich_text" },
            @{ Name = "Type"; Type = "select"; Options = @("Cook", "Leftover", "Quick", "Eat Out") },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Shopping List"
        Properties = @(
            @{ Name = "Item"; Type = "title" },
            @{ Name = "Category"; Type = "select"; Options = @() },
            @{ Name = "Quantity"; Type = "rich_text" },
            @{ Name = "Needed For"; Type = "rich_text" },
            @{ Name = "Purchased"; Type = "checkbox" }
        )
    },
    @{
        Title = "People"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Tier"; Type = "select"; Options = @() },
            @{ Name = "Birthday"; Type = "date" },
            @{ Name = "Cadence Days"; Type = "number" },
            @{ Name = "Last Contact"; Type = "date" },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Interactions"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Date"; Type = "date" },
            @{ Name = "People"; Type = "rich_text" },
            @{ Name = "Type"; Type = "select"; Options = @("Text", "Call", "Meal", "Hangout", "Work", "Other") },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Running Log"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Date"; Type = "date" },
            @{ Name = "Planned Miles"; Type = "number" },
            @{ Name = "Actual Miles"; Type = "number" },
            @{ Name = "Pace"; Type = "rich_text" },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Learning Log"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Date"; Type = "date" },
            @{ Name = "Topic"; Type = "select"; Options = @() },
            @{ Name = "Hours"; Type = "number" },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Events & Trips"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Date"; Type = "date" },
            @{ Name = "End Date"; Type = "date" },
            @{ Name = "Category"; Type = "select"; Options = @() },
            @{ Name = "Type"; Type = "select"; Options = @("Event", "Trip", "Appointment", "Birthday") },
            @{ Name = "Notes"; Type = "rich_text" }
        )
    },
    @{
        Title = "Weekly Review"
        Properties = @(
            @{ Name = "Name"; Type = "title" },
            @{ Name = "Week Start"; Type = "date" },
            @{ Name = "Wins"; Type = "rich_text" },
            @{ Name = "Missed Chores"; Type = "rich_text" },
            @{ Name = "Next Week Focus"; Type = "rich_text" }
        )
    }
)

$apartmentZones = @(
    @{ Name = "Kitchen"; Type = "Room"; WeeklyWeight = 3; Notes = "Cooking, counters, sink, fridge, pantry." },
    @{ Name = "Bathroom"; Type = "Room"; WeeklyWeight = 3; Notes = "Sink, toilet, shower, mirror, towels." },
    @{ Name = "Bedroom"; Type = "Room"; WeeklyWeight = 2; Notes = "Sheets, laundry, surfaces, closet." },
    @{ Name = "Floors"; Type = "Surface"; WeeklyWeight = 2; Notes = "Vacuuming, mopping, rugs, thresholds." },
    @{ Name = "Living"; Type = "Room"; WeeklyWeight = 2; Notes = "Shared space, dusting, clutter reset." },
    @{ Name = "Admin"; Type = "Admin"; WeeklyWeight = 1; Notes = "Bills, planning, supplies, maintenance." }
)

$choreTemplates = @(
    @{ Name = "Take out trash & recycling"; Zone = "Admin"; Cadence = "Weekly"; PreferredDay = "Sun"; FlexDays = 1; EstimateMinutes = 10; Notes = "Check bins and reset bags." },
    @{ Name = "Kitchen reset & wipe counters"; Zone = "Kitchen"; Cadence = "Daily"; PreferredDay = "Sun"; FlexDays = 0; EstimateMinutes = 10; Notes = "Counters, sink, dishes, obvious clutter." },
    @{ Name = "Clean bathroom"; Zone = "Bathroom"; Cadence = "Weekly"; PreferredDay = "Sat"; FlexDays = 2; EstimateMinutes = 35; Notes = "Toilet, sink, mirror, shower touch-up." },
    @{ Name = "Change bed sheets"; Zone = "Bedroom"; Cadence = "Weekly"; PreferredDay = "Sun"; FlexDays = 2; EstimateMinutes = 15; Notes = "Swap sheets and start laundry." },
    @{ Name = "Vacuum main areas"; Zone = "Floors"; Cadence = "Weekly"; PreferredDay = "Sun"; FlexDays = 2; EstimateMinutes = 25; Notes = "Bedroom, living, paths, rug edges." },
    @{ Name = "Mop floors"; Zone = "Floors"; Cadence = "Biweekly"; PreferredDay = "Sun"; FlexDays = 3; EstimateMinutes = 25; Notes = "Kitchen, bathroom, and high-traffic hard floor." },
    @{ Name = "Clean inside fridge"; Zone = "Kitchen"; Cadence = "Monthly"; PreferredDay = "Sat"; FlexDays = 7; EstimateMinutes = 30; Notes = "Toss old food and wipe shelves." },
    @{ Name = "Microwave & stovetop detail"; Zone = "Kitchen"; Cadence = "Monthly"; PreferredDay = "Sat"; FlexDays = 7; EstimateMinutes = 25; Notes = "Degrease and clean appliance surfaces." },
    @{ Name = "Dust baseboards & fans"; Zone = "Living"; Cadence = "Monthly"; PreferredDay = "Sat"; FlexDays = 7; EstimateMinutes = 35; Notes = "Rotate through rooms as needed." },
    @{ Name = "Deep clean behind appliances"; Zone = "Kitchen"; Cadence = "Quarterly"; PreferredDay = "Sat"; FlexDays = 14; EstimateMinutes = 60; Notes = "Pull forward safely where possible." }
)

Import-DotEnv -Path (Join-Path -Path $PSScriptRoot -ChildPath ".env")

if (-not $ParentPageId) {
    $ParentPageId = Get-EnvValue -Name "NOTION_PARENT_PAGE_ID"
}

if (-not $ParentPageId) {
    throw "Missing parent page ID. Pass -ParentPageId or set NOTION_PARENT_PAGE_ID."
}

$normalizedParentPageId = ConvertTo-NotionPageId -Value $ParentPageId
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"

if (-not $DryRun -and -not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

Write-Host "Creating Notion prototype under parent page $normalizedParentPageId"
if ($DryRun) {
    Write-Host "Dry run enabled. No Notion API calls will be made."
}

$prototypePage = New-NotionPage -ParentPageId $normalizedParentPageId -Title $PrototypeTitle
$prototypePageId = $prototypePage.id
Write-Host "Prototype page: $PrototypeTitle ($prototypePageId)"

$createdDatabases = @{}
foreach ($definition in $databaseDefinitions) {
    $database = New-NotionDatabase -ParentPageId $prototypePageId -Title $definition.Title -Properties $definition.Properties
    $createdDatabases[$definition.Title] = $database.id
    Write-Host "Database: $($definition.Title) ($($database.id))"
}

foreach ($zone in $apartmentZones) {
    [void](New-DatabaseRow -DatabaseId $createdDatabases["Apartment Zones"] -Properties @{
        Name = TitleValue $zone.Name
        Type = SelectValue $zone.Type
        "Weekly Weight" = NumberValue $zone.WeeklyWeight
        Notes = TextValue $zone.Notes
    })
    Write-Host "Seeded apartment zone: $($zone.Name)"
}

foreach ($template in $choreTemplates) {
    [void](New-DatabaseRow -DatabaseId $createdDatabases["Chore Templates"] -Properties @{
        Name = TitleValue $template.Name
        Zone = SelectValue $template.Zone
        Cadence = SelectValue $template.Cadence
        "Preferred Day" = SelectValue $template.PreferredDay
        "Flex Days" = NumberValue $template.FlexDays
        "Estimate Minutes" = NumberValue $template.EstimateMinutes
        Active = CheckboxValue $true
        Notes = TextValue $template.Notes
    })
    Write-Host "Seeded chore template: $($template.Name)"
}

Write-Host "Done."
