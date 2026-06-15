param(
    [string]$PrototypePageId = "37fe8e29-9eae-8159-bd12-d8bcbf34ec0c",
    [string]$Title = "To-Dos",
    [switch]$SeedStarterTasks,
    [switch]$DryRun,
    [switch]$VerboseDryRun,
    [string]$NotionVersion = "2022-06-28",

    [string]$ChoreTemplatesDatabaseId = "37fe8e29-9eae-8113-88c0-dda7166e8d3d",
    [string]$ChoresDatabaseId = "37fe8e29-9eae-81de-a1bd-db293503adfa",
    [string]$ApartmentZonesDatabaseId = "37fe8e29-9eae-814e-8b55-d7fd052bd120",
    [string]$RecipesDatabaseId = "37fe8e29-9eae-8192-b4d0-c842a8d6e5a9",
    [string]$MealPlanDatabaseId = "37fe8e29-9eae-816e-ae08-e2ecf42453d3",
    [string]$ShoppingListDatabaseId = "37fe8e29-9eae-819e-a1e8-e4a33b5121a2",
    [string]$PeopleDatabaseId = "37fe8e29-9eae-819c-98be-f20d83340774",
    [string]$InteractionsDatabaseId = "37fe8e29-9eae-817a-b325-f3a28edcc597",
    [string]$RunningLogDatabaseId = "37fe8e29-9eae-810f-b650-eec94ba5d8e6",
    [string]$LearningLogDatabaseId = "37fe8e29-9eae-816d-a682-e5ecf84db554",
    [string]$EventsTripsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$WeeklyReviewDatabaseId = "37fe8e29-9eae-8147-a043-fe457f112456"
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
        throw "Notion ID must contain 32 hex characters. Received '$Value'."
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

function New-SelectPropertyValue {
    param([string]$Text)
    if (-not $Text) {
        return @{ select = $null }
    }

    return @{ select = @{ name = $Text } }
}

function New-NumberPropertyValue {
    param($Value)
    if ($null -eq $Value -or $Value -eq "") {
        return @{ number = $null }
    }

    return @{ number = [double]$Value }
}

function New-CheckboxPropertyValue {
    param([bool]$Value)
    return @{ checkbox = $Value }
}

function New-DatePropertyValue {
    param([string]$Date)
    if (-not $Date) {
        return @{ date = $null }
    }

    return @{ date = @{ start = $Date } }
}

function New-PropertySchema {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [string[]]$Options = @(),
        [string]$RelationDatabaseId = ""
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
        "relation" {
            if (-not $RelationDatabaseId) {
                throw "Relation properties require RelationDatabaseId."
            }

            return @{
                relation = @{
                    database_id = (ConvertTo-NotionPageId -Value $RelationDatabaseId)
                    type = "single_property"
                    single_property = @{}
                }
            }
        }
        default { throw "Unsupported property type '$Type'." }
    }
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
            foreach ($titleKey in @("Task", "Name", "Item")) {
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

        if ($Path -eq "/databases") {
            return @{ id = "dry_run_todos_database" }
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

function New-TodoHubDatabase {
    param([string]$ParentPageId)

    $properties = @{
        Task = New-PropertySchema -Type "title"
        Status = New-PropertySchema -Type "select" -Options @("Inbox", "Next", "Scheduled", "Waiting", "Done", "Cancelled")
        Priority = New-PropertySchema -Type "select" -Options @("High", "Medium", "Low")
        Area = New-PropertySchema -Type "select" -Options @("Home", "Meals", "Shopping", "People", "Running", "Learning", "Events", "Review", "Admin")
        Source = New-PropertySchema -Type "select" -Options @("Chores", "Chore Templates", "Apartment Zones", "Recipes", "Meal Plan", "Shopping List", "People", "Interactions", "Running Log", "Learning Log", "Events & Trips", "Weekly Review", "Ad hoc")
        Due = New-PropertySchema -Type "date"
        "Do Date" = New-PropertySchema -Type "date"
        "Effort Minutes" = New-PropertySchema -Type "number"
        Done = New-PropertySchema -Type "checkbox"
        Notes = New-PropertySchema -Type "rich_text"
        Chore = New-PropertySchema -Type "relation" -RelationDatabaseId $ChoresDatabaseId
        "Chore Template" = New-PropertySchema -Type "relation" -RelationDatabaseId $ChoreTemplatesDatabaseId
        Zone = New-PropertySchema -Type "relation" -RelationDatabaseId $ApartmentZonesDatabaseId
        Recipe = New-PropertySchema -Type "relation" -RelationDatabaseId $RecipesDatabaseId
        Meal = New-PropertySchema -Type "relation" -RelationDatabaseId $MealPlanDatabaseId
        "Shopping Item" = New-PropertySchema -Type "relation" -RelationDatabaseId $ShoppingListDatabaseId
        Person = New-PropertySchema -Type "relation" -RelationDatabaseId $PeopleDatabaseId
        Interaction = New-PropertySchema -Type "relation" -RelationDatabaseId $InteractionsDatabaseId
        Run = New-PropertySchema -Type "relation" -RelationDatabaseId $RunningLogDatabaseId
        Learning = New-PropertySchema -Type "relation" -RelationDatabaseId $LearningLogDatabaseId
        Event = New-PropertySchema -Type "relation" -RelationDatabaseId $EventsTripsDatabaseId
        Review = New-PropertySchema -Type "relation" -RelationDatabaseId $WeeklyReviewDatabaseId
    }

    $body = @{
        parent = @{ page_id = $ParentPageId }
        title = New-RichText -Text $Title
        properties = $properties
    }

    return Invoke-NotionApi -Method "POST" -Path "/databases" -Body $body
}

function New-StarterTask {
    param(
        [string]$TodosDatabaseId,
        [string]$Task,
        [string]$Area,
        [string]$Source,
        [string]$Priority = "Medium",
        [int]$EffortMinutes = 15,
        [string]$Notes = ""
    )

    $body = @{
        parent = @{ database_id = $TodosDatabaseId }
        properties = @{
            Task = New-TitlePropertyValue -Text $Task
            Status = New-SelectPropertyValue -Text "Inbox"
            Priority = New-SelectPropertyValue -Text $Priority
            Area = New-SelectPropertyValue -Text $Area
            Source = New-SelectPropertyValue -Text $Source
            Due = New-DatePropertyValue -Date ""
            "Do Date" = New-DatePropertyValue -Date ""
            "Effort Minutes" = New-NumberPropertyValue -Value $EffortMinutes
            Done = New-CheckboxPropertyValue -Value $false
            Notes = New-RichTextPropertyValue -Text $Notes
        }
    }

    [void](Invoke-NotionApi -Method "POST" -Path "/pages" -Body $body)
}

Import-DotEnv -Path (Join-Path -Path $PSScriptRoot -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"

if (-not $DryRun -and -not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$normalizedPrototypePageId = ConvertTo-NotionPageId -Value $PrototypePageId

Write-Host "Creating '$Title' task hub under Sheet of Life prototype page $normalizedPrototypePageId."
if ($DryRun) {
    Write-Host "Dry run enabled. No Notion API calls will be made."
}

$todoDatabase = New-TodoHubDatabase -ParentPageId $normalizedPrototypePageId
$todoDatabaseId = $todoDatabase.id
Write-Host "To-Dos database: $todoDatabaseId"

if ($SeedStarterTasks) {
    $starterTasks = @(
        @{ Task = "Review open chores"; Area = "Home"; Source = "Chores"; Priority = "High"; EffortMinutes = 10; Notes = "Use this to triage overdue, moved, or skipped chore records." },
        @{ Task = "Plan the next meal block"; Area = "Meals"; Source = "Meal Plan"; Priority = "Medium"; EffortMinutes = 20; Notes = "Attach planned meal rows or recipe rows once selected." },
        @{ Task = "Clear shopping blockers"; Area = "Shopping"; Source = "Shopping List"; Priority = "Medium"; EffortMinutes = 15; Notes = "Attach shopping items that need decisions or purchase." },
        @{ Task = "Check relationship follow-ups"; Area = "People"; Source = "People"; Priority = "Medium"; EffortMinutes = 15; Notes = "Attach people or interaction records that need a reply, call, or plan." },
        @{ Task = "Log or schedule the next run"; Area = "Running"; Source = "Running Log"; Priority = "Low"; EffortMinutes = 10; Notes = "Attach the relevant running log row when there is one." },
        @{ Task = "Pick the next learning session"; Area = "Learning"; Source = "Learning Log"; Priority = "Low"; EffortMinutes = 10; Notes = "Attach learning log rows or leave as an ad hoc learning task." },
        @{ Task = "Prep upcoming event or trip"; Area = "Events"; Source = "Events & Trips"; Priority = "Medium"; EffortMinutes = 20; Notes = "Attach the event or trip that needs preparation." },
        @{ Task = "Run weekly review"; Area = "Review"; Source = "Weekly Review"; Priority = "High"; EffortMinutes = 30; Notes = "Attach the weekly review row for the week." }
    )

    foreach ($task in $starterTasks) {
        New-StarterTask `
            -TodosDatabaseId $todoDatabaseId `
            -Task $task.Task `
            -Area $task.Area `
            -Source $task.Source `
            -Priority $task.Priority `
            -EffortMinutes $task.EffortMinutes `
            -Notes $task.Notes
        Write-Host "Seeded starter task: $($task.Task)"
    }
}

Write-Host "Done."
