param(
    [string]$PrototypePageId = "37fe8e29-9eae-8159-bd12-d8bcbf34ec0c",
    [string]$HomePageId = "38ce8e29-9eae-818c-b546-d60ea34d16c5",
    [string]$CommandCenterPageId = "",
    [string]$CommandCenterStatePath = ".sol_command_center_state.json",
    [string]$ComponentStatePath = ".sol_command_components_state.json",
    [string]$ChoreTemplatesDatabaseId = "37fe8e29-9eae-8113-88c0-dda7166e8d3d",
    [string]$ApartmentZonesDatabaseId = "37fe8e29-9eae-814e-8b55-d7fd052bd120",
    [string]$TravelDatabaseId = "380e8e29-9eae-8119-a19e-f9f743f62bff",
    [string]$ChoresDatabaseId = "37fe8e29-9eae-81de-a1bd-db293503adfa",
    [string]$TodosDatabaseId = "37fe8e29-9eae-815a-9bb1-ef0e273ff652",
    [string]$RecipesDatabaseId = "37fe8e29-9eae-8192-b4d0-c842a8d6e5a9",
    [string]$MealPlanDatabaseId = "37fe8e29-9eae-816e-ae08-e2ecf42453d3",
    [string]$EventsTripsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$ShoppingListDatabaseId = "37fe8e29-9eae-819e-a1e8-e4a33b5121a2",
    [string]$IngredientsDatabaseId = "38ce8e29-9eae-8137-80c4-cedbdf6943c7",
    [string]$RecipeIngredientsDatabaseId = "38ce8e29-9eae-8131-ba98-de6b87d9f934",
    [string]$RecipeSuggestionsDatabaseId = "38ce8e29-9eae-81bc-89f9-c81ec968797d",
    [string]$PeopleDatabaseId = "37fe8e29-9eae-819c-98be-f20d83340774",
    [string]$InteractionsDatabaseId = "37fe8e29-9eae-817a-b325-f3a28edcc597",
    [string]$RunningLogDatabaseId = "37fe8e29-9eae-810f-b650-eec94ba5d8e6",
    [string]$LearningLogDatabaseId = "37fe8e29-9eae-816d-a682-e5ecf84db554",
    [string]$WeeklyReviewDatabaseId = "37fe8e29-9eae-8147-a043-fe457f112456",
    [string]$BlocksVersion = "2022-06-28",
    [string]$ViewsVersion = "2026-03-11"
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
    param(
        [string]$Text,
        [switch]$Bold,
        [switch]$Code
    )

    if (-not $Text) { return @() }

    return ,@(@{
        type = "text"
        text = @{ content = $Text }
        annotations = @{
            bold = [bool]$Bold
            italic = $false
            strikethrough = $false
            underline = $false
            code = [bool]$Code
            color = "default"
        }
    })
}

function New-TextBlock {
    param(
        [string]$Type,
        [string]$Text,
        [string]$Color = "default"
    )

    return @{
        object = "block"
        type = $Type
        $Type = @{
            rich_text = (New-RichText -Text $Text)
            color = $Color
        }
    }
}

function New-CalloutBlock {
    param(
        [string]$Label,
        [string]$Text
    )

    return @{
        object = "block"
        type = "callout"
        callout = @{
            rich_text = @(
                @{
                    type = "text"
                    text = @{ content = "$Label  " }
                    annotations = @{
                        bold = $true
                        italic = $false
                        strikethrough = $false
                        underline = $false
                        code = $true
                        color = "default"
                    }
                },
                @{
                    type = "text"
                    text = @{ content = $Text }
                    annotations = @{
                        bold = $false
                        italic = $false
                        strikethrough = $false
                        underline = $false
                        code = $false
                        color = "default"
                    }
                }
            )
            color = "gray_background"
        }
    }
}

function New-DividerBlock {
    return @{ object = "block"; type = "divider"; divider = @{} }
}

function New-LinkToPageBlock {
    param([string]$PageId)

    return @{
        object = "block"
        type = "link_to_page"
        link_to_page = @{
            type = "page_id"
            page_id = (ConvertTo-NotionId -Value $PageId)
        }
    }
}

function New-LinkToDatabaseBlock {
    param([string]$DatabaseId)

    return @{
        object = "block"
        type = "link_to_page"
        link_to_page = @{
            type = "database_id"
            database_id = (ConvertTo-NotionId -Value $DatabaseId)
        }
    }
}

function New-ColumnListBlock {
    param([array]$Columns)

    $columnBlocks = @()
    foreach ($columnChildren in $Columns) {
        $columnBlocks += @{
            object = "block"
            type = "column"
            column = @{
                children = @($columnChildren)
            }
        }
    }

    return @{
        object = "block"
        type = "column_list"
        column_list = @{
            children = $columnBlocks
        }
    }
}

function New-KpiBlock {
    param(
        [string]$Label,
        [string]$Value,
        [string]$Hint = ""
    )

    $text = if ($Hint) { "$Value - $Hint" } else { $Value }
    return New-CalloutBlock -Label $Label -Text $text
}

function Invoke-NotionApi {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null,
        [string]$Version = $BlocksVersion
    )

    $parameters = @{
        Method = $Method
        Uri = "https://api.notion.com/v1$Path"
        Headers = @{
            Authorization = "Bearer $script:NotionToken"
            "Notion-Version" = $Version
            "Content-Type" = "application/json"
        }
    }

    if ($null -ne $Body) {
        $parameters["Body"] = ($Body | ConvertTo-Json -Depth 40)
    }

    return Invoke-RestMethod @parameters
}

function Get-TitleFromPage {
    param($Page)

    foreach ($property in $Page.properties.PSObject.Properties) {
        if ($property.Value.type -eq "title" -and $property.Value.title.Count -gt 0) {
            return (($property.Value.title | ForEach-Object { $_.plain_text }) -join "")
        }
    }

    return ""
}

function Find-CurrentCommandCenter {
    $statePath = Join-Path -Path $RepoRoot -ChildPath $CommandCenterStatePath
    if (Test-Path -LiteralPath $statePath) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if ($state.commandCenterPageId) {
                $page = Invoke-NotionApi -Method "GET" -Path "/pages/$(ConvertTo-NotionId -Value $state.commandCenterPageId)"
                if (-not $page.archived) { return $page }
            }
        }
        catch {
            Write-Host "Could not use command-center state file; falling back to search."
        }
    }

    $body = @{
        query = "Sheet of Life Command Center"
        filter = @{ property = "object"; value = "page" }
        page_size = 10
    }
    $results = Invoke-NotionApi -Method "POST" -Path "/search" -Body $body
    $parentId = ConvertTo-NotionId -Value $PrototypePageId

    foreach ($page in $results.results) {
        if ((Get-TitleFromPage -Page $page) -eq "Sheet of Life Command Center" -and $page.parent.type -eq "page_id" -and $page.parent.page_id -eq $parentId -and -not $page.archived) {
            return $page
        }
    }

    return $null
}

function New-CommandCenterPage {
    return Invoke-NotionApi -Method "POST" -Path "/pages" -Body @{
        parent = @{ page_id = (ConvertTo-NotionId -Value $PrototypePageId) }
        properties = @{
            title = @{
                title = @(@{ type = "text"; text = @{ content = "Sheet of Life Command Center" } })
            }
        }
    }
}

function Get-OrCreateCommandCenterPage {
    if ($CommandCenterPageId) {
        $pageId = ConvertTo-NotionId -Value $CommandCenterPageId
        try {
            [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$pageId" -Body @{ archived = $false })
            return Invoke-NotionApi -Method "GET" -Path "/pages/$pageId"
        } catch {
            Write-Host "Requested Command Center page was not reachable; falling back to state/search."
        }
    }

    $existing = Find-CurrentCommandCenter
    if ($existing) {
        [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($existing.id)" -Body @{ archived = $false })
        return $existing
    }

    return New-CommandCenterPage
}

function Save-CommandCenterState {
    param([string]$PageId)

    $statePath = Join-Path -Path $RepoRoot -ChildPath $CommandCenterStatePath
    @{
        commandCenterPageId = $PageId
        updatedAt = (Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath
}

function Get-JsonState {
    param([string]$Path)

    $fullPath = Join-Path -Path $RepoRoot -ChildPath $Path
    if (-not (Test-Path -LiteralPath $fullPath)) { return @{} }
    $raw = Get-Content -LiteralPath $fullPath -Raw
    if (-not $raw.Trim()) { return @{} }
    $json = $raw | ConvertFrom-Json
    $state = @{}
    foreach ($property in $json.PSObject.Properties) {
        $state[$property.Name] = $property.Value
    }
    return $state
}

function Save-JsonState {
    param([string]$Path, [hashtable]$State)

    $fullPath = Join-Path -Path $RepoRoot -ChildPath $Path
    $State["updatedAt"] = (Get-Date).ToString("o")
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fullPath
}

function Add-Blocks {
    param([string]$PageId, [array]$Children)

    return Invoke-NotionApi -Method "PATCH" -Path "/blocks/$(ConvertTo-NotionId -Value $PageId)/children" -Body @{ children = $Children }
}

function New-TitleValue {
    param([string]$Text)
    return @{ title = @(@{ type = "text"; text = @{ content = $Text } }) }
}

function New-TextValue {
    param([string]$Text)
    return @{ rich_text = @(@{ type = "text"; text = @{ content = $Text } }) }
}

function New-SelectValue {
    param([string]$Name)
    return @{ select = @{ name = $Name } }
}

function New-CommandComponentDatabase {
    return Invoke-NotionApi -Method "POST" -Path "/databases" -Body @{
        parent = @{ page_id = (ConvertTo-NotionId -Value $PrototypePageId) }
        title = @(@{ type = "text"; text = @{ content = "Command Center Components" } })
        properties = @{
            Name = @{ title = @{} }
            Area = @{ select = @{ options = @(
                @{ name = "Food" },
                @{ name = "Home" },
                @{ name = "Tasks" },
                @{ name = "Shopping" },
                @{ name = "People" },
                @{ name = "Body" },
                @{ name = "Mind" },
                @{ name = "Events" },
                @{ name = "Review" }
            ) } }
            Signal = @{ rich_text = @{} }
            Action = @{ rich_text = @{} }
        }
    }
}

function Get-OrCreateCommandComponentDatabaseId {
    $state = Get-JsonState -Path $ComponentStatePath
    if ($state.ContainsKey("componentDatabaseId") -and $state["componentDatabaseId"]) {
        $dbId = ConvertTo-NotionId -Value ([string]$state["componentDatabaseId"])
        try {
            [void](Invoke-NotionApi -Method "GET" -Path "/databases/$dbId")
            return $dbId
        } catch {
            Write-Host "Component database from state was not reachable; creating a new one."
        }
    }

    $db = New-CommandComponentDatabase
    $state["componentDatabaseId"] = $db.id
    Save-JsonState -Path $ComponentStatePath -State $state
    Write-Host "Created Command Center Components database: $($db.id)"
    return $db.id
}

function Find-ComponentPage {
    param([string]$DatabaseId, [string]$Name)

    $body = @{
        page_size = 10
        filter = @{ property = "Name"; title = @{ equals = $Name } }
    }
    $result = Invoke-NotionApi -Method "POST" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)/query" -Body $body
    return @($result.results | Where-Object { -not $_.archived } | Select-Object -First 1)
}

function Ensure-ComponentPage {
    param(
        [string]$DatabaseId,
        [string]$Name,
        [string]$Area,
        [string]$Signal,
        [string]$Action
    )

    $properties = @{
        Name = New-TitleValue -Text $Name
        Area = New-SelectValue -Name $Area
        Signal = New-TextValue -Text $Signal
        Action = New-TextValue -Text $Action
    }

    $existing = Find-ComponentPage -DatabaseId $DatabaseId -Name $Name
    if ($existing) {
        [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($existing.id)" -Body @{ properties = $properties })
        return $existing.id
    }

    $created = Invoke-NotionApi -Method "POST" -Path "/pages" -Body @{
        parent = @{ database_id = (ConvertTo-NotionId -Value $DatabaseId) }
        properties = $properties
    }
    return $created.id
}

function Get-BlockChildren {
    param([string]$BlockId)

    $children = @()
    $cursor = ""
    do {
        $path = "/blocks/$(ConvertTo-NotionId -Value $BlockId)/children?page_size=100"
        if ($cursor) { $path = "$path&start_cursor=$cursor" }
        $response = Invoke-NotionApi -Method "GET" -Path $path
        $children += @($response.results | Where-Object { -not $_.archived })
        $cursor = ""
        if ($response.has_more) { $cursor = $response.next_cursor }
    } while ($cursor)

    return $children
}

function Clear-PageChildren {
    param([string]$PageId)

    $children = Get-BlockChildren -BlockId $PageId
    foreach ($child in $children) {
        [void](Invoke-NotionApi -Method "PATCH" -Path "/blocks/$($child.id)" -Body @{ archived = $true })
        Write-Host "Archived existing Command Center block: $($child.id)"
    }
}

function Add-LabeledLinkedView {
    param(
        [string]$PageId,
        [string]$Name,
        [string]$DatabaseId,
        [string]$Type = "table",
        $Filter = $null,
        $Sorts = $null
    )

    [void](Add-Blocks -PageId $PageId -Children @((New-TextBlock -Type "heading_3" -Text $Name)))
    Add-LinkedView -PageId $PageId -Name $Name -DatabaseId $DatabaseId -Type $Type -Filter $Filter -Sorts $Sorts
}

function Get-DatabaseCount {
    param(
        [string]$DatabaseId,
        $Filter = $null
    )

    $body = @{ page_size = 100 }
    if ($null -ne $Filter) { $body["filter"] = $Filter }
    $result = Invoke-NotionApi -Method "POST" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)/query" -Body $body

    if ($null -ne $result.total_count) { return [int]$result.total_count }
    if ($result.has_more) { return "$(@($result.results).Count)+" }
    return @($result.results).Count
}

function Get-DataSourceId {
    param([string]$DatabaseId)

    $database = Invoke-NotionApi -Method "GET" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)" -Version $ViewsVersion
    if (-not $database.data_sources -or $database.data_sources.Count -eq 0) {
        throw "Database $DatabaseId did not return a data source ID."
    }

    return $database.data_sources[0].id
}

function Add-LinkedView {
    param(
        [string]$PageId,
        [string]$Name,
        [string]$DatabaseId,
        [string]$Type = "table",
        $Filter = $null,
        $Sorts = $null
    )

    $body = @{
        create_database = @{
            parent = @{
                type = "page_id"
                page_id = (ConvertTo-NotionId -Value $PageId)
            }
        }
        data_source_id = (Get-DataSourceId -DatabaseId $DatabaseId)
        name = $Name
        type = $Type
    }

    if ($null -ne $Filter) { $body["filter"] = $Filter }
    if ($null -ne $Sorts) { $body["sorts"] = $Sorts }

    try {
        [void](Invoke-NotionApi -Method "POST" -Path "/views" -Body $body -Version $ViewsVersion)
        Write-Host "Added linked view: $Name"
    } catch {
        if ($Type -ne "table" -and $Type -ne "calendar") {
            Write-Host "View type '$Type' was not accepted for '$Name'. Retrying as table."
            $body["type"] = "table"
            [void](Invoke-NotionApi -Method "POST" -Path "/views" -Body $body -Version $ViewsVersion)
            Write-Host "Added linked view as table: $Name"
        } else {
            throw
        }
    }
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$page = Get-OrCreateCommandCenterPage
Save-CommandCenterState -PageId $page.id
Write-Host "Updating Sheet of Life Command Center in place: $($page.id)"
Clear-PageChildren -PageId $page.id

$today = (Get-Date).ToString("yyyy-MM-dd")
$weekEnd = (Get-Date).AddDays(7).ToString("yyyy-MM-dd")
$monthStart = (Get-Date -Day 1).ToString("yyyy-MM-dd")
$monthEndDate = (Get-Date -Day 1).AddMonths(1).AddDays(-1)
$monthEnd = $monthEndDate.ToString("yyyy-MM-dd")

$foodTodayFilter = @{ property = "Date"; date = @{ equals = $today } }
$foodUpcomingFilter = @{ property = "Date"; date = @{ on_or_after = $today } }
$readyRecipeFilter = @{
    or = @(
        @{ property = "Status"; select = @{ equals = "Ready" } },
        @{ property = "Status"; select = @{ equals = "Cook Soon" } }
    )
}
$foodDecisionFilter = @{
    and = @(
        @{ property = "Date"; date = @{ on_or_after = $today } },
        @{
            or = @(
                @{ property = "Food Included"; checkbox = @{ equals = $true } },
                @{ property = "Food Plan"; select = @{ equals = "Decide later" } },
                @{ property = "Food Plan"; select = @{ is_empty = $true } }
            )
        }
    )
}
$choreOpenFilter = @{ property = "Done"; checkbox = @{ equals = $false } }
$choreWeekFilter = @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Date"; date = @{ on_or_after = $today } },
        @{ property = "Date"; date = @{ on_or_before = $weekEnd } }
    )
}
$choreDoneWeekFilter = @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $true } },
        @{ property = "Date"; date = @{ on_or_after = $today } },
        @{ property = "Date"; date = @{ on_or_before = $weekEnd } }
    )
}
$choreDoneMonthFilter = @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $true } },
        @{ property = "Date"; date = @{ on_or_after = $monthStart } },
        @{ property = "Date"; date = @{ on_or_before = $monthEnd } }
    )
}
$todoOpenFilter = @{ property = "Done"; checkbox = @{ equals = $false } }
$todoDueFilter = @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{
            or = @(
                @{ property = "Due"; date = @{ on_or_before = $today } },
                @{ property = "Do Date"; date = @{ on_or_before = $today } }
            )
        }
    )
}
$shoppingOpenFilter = @{ property = "Purchased"; checkbox = @{ equals = $false } }
$interactionMonthFilter = @{
    and = @(
        @{ property = "Date"; date = @{ on_or_after = $monthStart } },
        @{ property = "Date"; date = @{ on_or_before = $monthEnd } }
    )
}
$runningMonthFilter = @{
    and = @(
        @{ property = "Date"; date = @{ on_or_after = $monthStart } },
        @{ property = "Date"; date = @{ on_or_before = $monthEnd } }
    )
}
$runningUpcomingFilter = @{ property = "Date"; date = @{ on_or_after = $today } }
$learningMonthFilter = @{
    and = @(
        @{ property = "Date"; date = @{ on_or_after = $monthStart } },
        @{ property = "Date"; date = @{ on_or_before = $monthEnd } }
    )
}
$learningRecentFilter = @{ property = "Date"; date = @{ on_or_before = $today } }
$learningTaskFilter = @{
    and = @(
        @{ property = "Area"; select = @{ equals = "Learning" } },
        @{ property = "Done"; checkbox = @{ equals = $false } }
    )
}
$eventUpcomingFilter = @{ property = "Date"; date = @{ on_or_after = $today } }
$travelUpcomingFilter = @{ property = "Start"; date = @{ on_or_after = $today } }
$weeklyRecentFilter = @{ property = "Week Start"; date = @{ on_or_before = $today } }
$foodTodayCount = Get-DatabaseCount -DatabaseId $MealPlanDatabaseId -Filter $foodTodayFilter
$readyRecipeCount = Get-DatabaseCount -DatabaseId $RecipesDatabaseId -Filter $readyRecipeFilter
$foodDecisionCount = Get-DatabaseCount -DatabaseId $EventsTripsDatabaseId -Filter $foodDecisionFilter
$choreOpenCount = Get-DatabaseCount -DatabaseId $ChoresDatabaseId -Filter $choreOpenFilter
$choreWeekCount = Get-DatabaseCount -DatabaseId $ChoresDatabaseId -Filter $choreWeekFilter
$choreDoneWeekCount = Get-DatabaseCount -DatabaseId $ChoresDatabaseId -Filter $choreDoneWeekFilter
$choreDoneMonthCount = Get-DatabaseCount -DatabaseId $ChoresDatabaseId -Filter $choreDoneMonthFilter
$todoOpenCount = Get-DatabaseCount -DatabaseId $TodosDatabaseId -Filter $todoOpenFilter
$todoDueCount = Get-DatabaseCount -DatabaseId $TodosDatabaseId -Filter $todoDueFilter
$shoppingOpenCount = Get-DatabaseCount -DatabaseId $ShoppingListDatabaseId -Filter $shoppingOpenFilter
$peopleCount = Get-DatabaseCount -DatabaseId $PeopleDatabaseId
$interactionMonthCount = Get-DatabaseCount -DatabaseId $InteractionsDatabaseId -Filter $interactionMonthFilter
$runningMonthCount = Get-DatabaseCount -DatabaseId $RunningLogDatabaseId -Filter $runningMonthFilter
$runningUpcomingCount = Get-DatabaseCount -DatabaseId $RunningLogDatabaseId -Filter $runningUpcomingFilter
$learningMonthCount = Get-DatabaseCount -DatabaseId $LearningLogDatabaseId -Filter $learningMonthFilter
$eventUpcomingCount = Get-DatabaseCount -DatabaseId $EventsTripsDatabaseId -Filter $eventUpcomingFilter
$travelUpcomingCount = Get-DatabaseCount -DatabaseId $TravelDatabaseId -Filter $travelUpcomingFilter
$weeklyRecentCount = Get-DatabaseCount -DatabaseId $WeeklyReviewDatabaseId -Filter $weeklyRecentFilter
$recipeSuggestionCount = Get-DatabaseCount -DatabaseId $RecipeSuggestionsDatabaseId
$componentDatabaseId = Get-OrCreateCommandComponentDatabaseId
$foodComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Food + Calendar" -Area "Food" -Signal "$foodTodayCount today | $readyRecipeCount ready | $foodDecisionCount decide" -Action "Open meal calendar, recipe picks, and food decisions."
$homeComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Home / Chores" -Area "Home" -Signal "$choreOpenCount open | $choreDoneMonthCount completed this month" -Action "Open due chores, home radar, and completion history."
$tasksComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Tasks" -Area "Tasks" -Signal "$todoDueCount due | $todoOpenCount open" -Action "Open due tasks, all open tasks, and task capture."
$shoppingComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Shopping" -Area "Shopping" -Signal "$shoppingOpenCount open items" -Action "Open grocery and supply rows before errands."
$recipeBrainComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Recipe Brain" -Area "Food" -Signal "$readyRecipeCount ready | $recipeSuggestionCount suggestions" -Action "Open recipes, ingredients, recipe links, and suggestion backlog."
$peopleComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "People" -Area "People" -Signal "$peopleCount people | $interactionMonthCount interactions this month" -Action "Open contacts, recent interactions, and relationship notes."
$runningComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Running" -Area "Body" -Signal "$runningUpcomingCount planned | $runningMonthCount this month" -Action "Open run calendar, recent runs, and planned mileage."
$learningComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Learning" -Area "Mind" -Signal "$learningMonthCount sessions this month" -Action "Open learning log, topic history, and capture rows."
$eventsComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Events + Travel" -Area "Events" -Signal "$eventUpcomingCount events | $travelUpcomingCount travel items" -Action "Open events, trips, travel segments, and food decisions."
$reviewComponentPageId = Ensure-ComponentPage -DatabaseId $componentDatabaseId -Name "Weekly Review + Pulse" -Area "Review" -Signal "$weeklyRecentCount reviews | $todoOpenCount open tasks" -Action "Open weekly reviews and cross-area pulse views."

Write-Host "Rebuilding Food + Calendar component page: $foodComponentPageId"
Clear-PageChildren -PageId $foodComponentPageId
[void](Add-Blocks -PageId $foodComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Food + Calendar is the working surface for meals, leftovers, recipes, and food-related events."),
    (New-CalloutBlock -Label "VISUAL" -Text "Use the calendar first, then the short rows below it for decisions and data entry."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Food Signal"),
    (New-KpiBlock -Label "TODAY" -Value "$foodTodayCount meal rows" -Hint "food coverage for today"),
    (New-KpiBlock -Label "READY" -Value "$readyRecipeCount recipes" -Hint "ready or marked cook soon"),
    (New-KpiBlock -Label "DECIDE" -Value "$foodDecisionCount events" -Hint "food-related events needing attention")
))

Add-LabeledLinkedView -PageId $foodComponentPageId -Name "Meal Calendar" -DatabaseId $MealPlanDatabaseId -Type "calendar" -Filter $foodUpcomingFilter -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $foodComponentPageId -Name "Food Today" -DatabaseId $MealPlanDatabaseId -Type "list" -Filter $foodTodayFilter -Sorts @(@{ property = "Slot"; direction = "ascending" })
Add-LabeledLinkedView -PageId $foodComponentPageId -Name "Recipe Picks" -DatabaseId $RecipesDatabaseId -Type "gallery" -Filter $readyRecipeFilter
Add-LabeledLinkedView -PageId $foodComponentPageId -Name "Food Events To Decide" -DatabaseId $EventsTripsDatabaseId -Type "list" -Filter $foodDecisionFilter -Sorts @(@{ property = "Date"; direction = "ascending" })

[void](Add-Blocks -PageId $foodComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $MealPlanDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $RecipesDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $IngredientsDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $RecipeSuggestionsDatabaseId)
))

Write-Host "Rebuilding Home / Chores component page: $homeComponentPageId"
Clear-PageChildren -PageId $homeComponentPageId
[void](Add-Blocks -PageId $homeComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Home / Chores is the working surface for what needs attention now and what has already been handled."),
    (New-CalloutBlock -Label "VISUAL" -Text "The completed-this-month signal sits above the active rows so progress is visible before the task list."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Home Signal"),
    (New-KpiBlock -Label "OPEN" -Value "$choreOpenCount chores" -Hint "not done"),
    (New-KpiBlock -Label "MONTH" -Value "$choreDoneMonthCount completed" -Hint "chores completed this month"),
    (New-KpiBlock -Label "THIS WEEK" -Value "$choreWeekCount chores" -Hint "scheduled in the next 7 days")
))

Add-LabeledLinkedView -PageId $homeComponentPageId -Name "Chores Due Soon" -DatabaseId $ChoresDatabaseId -Type "list" -Filter $choreWeekFilter -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $homeComponentPageId -Name "Open Home Radar" -DatabaseId $ChoresDatabaseId -Type "list" -Filter $choreOpenFilter -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $homeComponentPageId -Name "Completed This Month" -DatabaseId $ChoresDatabaseId -Type "gallery" -Filter $choreDoneMonthFilter -Sorts @(@{ property = "Date"; direction = "descending" })

[void](Add-Blocks -PageId $homeComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $ChoresDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $ChoreTemplatesDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $ApartmentZonesDatabaseId)
))

Write-Host "Rebuilding Tasks component page: $tasksComponentPageId"
Clear-PageChildren -PageId $tasksComponentPageId
[void](Add-Blocks -PageId $tasksComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Tasks is the working surface for what needs doing, without making every source table feel equally urgent."),
    (New-CalloutBlock -Label "VISUAL" -Text "Due and open counts sit above the rows so the page starts with a decision: what needs attention now?"),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Task Signal"),
    (New-KpiBlock -Label "DUE" -Value "$todoDueCount tasks" -Hint "due or scheduled through today"),
    (New-KpiBlock -Label "OPEN" -Value "$todoOpenCount tasks" -Hint "not done")
))
Add-LabeledLinkedView -PageId $tasksComponentPageId -Name "Due Now" -DatabaseId $TodosDatabaseId -Type "list" -Filter $todoDueFilter -Sorts @(@{ property = "Priority"; direction = "ascending" }, @{ property = "Due"; direction = "ascending" })
Add-LabeledLinkedView -PageId $tasksComponentPageId -Name "Open Tasks" -DatabaseId $TodosDatabaseId -Type "table" -Filter $todoOpenFilter -Sorts @(@{ property = "Due"; direction = "ascending" })
Add-LabeledLinkedView -PageId $tasksComponentPageId -Name "Task Capture" -DatabaseId $TodosDatabaseId -Type "table" -Filter $todoOpenFilter
[void](Add-Blocks -PageId $tasksComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $TodosDatabaseId)
))

Write-Host "Rebuilding Shopping component page: $shoppingComponentPageId"
Clear-PageChildren -PageId $shoppingComponentPageId
[void](Add-Blocks -PageId $shoppingComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Shopping is the working surface for groceries, supplies, and anything that should leave the apartment as a clean errand list."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Shopping Signal"),
    (New-KpiBlock -Label "OPEN" -Value "$shoppingOpenCount items" -Hint "not purchased")
))
Add-LabeledLinkedView -PageId $shoppingComponentPageId -Name "Shopping List" -DatabaseId $ShoppingListDatabaseId -Type "table" -Filter $shoppingOpenFilter
Add-LabeledLinkedView -PageId $shoppingComponentPageId -Name "Errand Mode" -DatabaseId $ShoppingListDatabaseId -Type "list" -Filter $shoppingOpenFilter
[void](Add-Blocks -PageId $shoppingComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $ShoppingListDatabaseId)
))

Write-Host "Rebuilding Recipe Brain component page: $recipeBrainComponentPageId"
Clear-PageChildren -PageId $recipeBrainComponentPageId
[void](Add-Blocks -PageId $recipeBrainComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Recipe Brain is the ingredient-aware library: recipes, pantry defaults, recipe ingredients, and overlap suggestions."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Recipe Signal"),
    (New-KpiBlock -Label "READY" -Value "$readyRecipeCount recipes" -Hint "ready or marked cook soon"),
    (New-KpiBlock -Label "MATCHES" -Value "$recipeSuggestionCount suggestions" -Hint "ingredient-overlap ideas")
))
Add-LabeledLinkedView -PageId $recipeBrainComponentPageId -Name "Ready Recipes" -DatabaseId $RecipesDatabaseId -Type "gallery" -Filter $readyRecipeFilter
Add-LabeledLinkedView -PageId $recipeBrainComponentPageId -Name "Recipe Suggestions" -DatabaseId $RecipeSuggestionsDatabaseId -Type "table" -Sorts @(@{ property = "Score"; direction = "descending" })
Add-LabeledLinkedView -PageId $recipeBrainComponentPageId -Name "Ingredient Catalog" -DatabaseId $IngredientsDatabaseId -Type "table"
Add-LabeledLinkedView -PageId $recipeBrainComponentPageId -Name "Recipe Ingredient Links" -DatabaseId $RecipeIngredientsDatabaseId -Type "table"
[void](Add-Blocks -PageId $recipeBrainComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $RecipesDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $IngredientsDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $RecipeIngredientsDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $RecipeSuggestionsDatabaseId)
))

Write-Host "Rebuilding People component page: $peopleComponentPageId"
Clear-PageChildren -PageId $peopleComponentPageId
[void](Add-Blocks -PageId $peopleComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "People is the working surface for relationships: who exists, who you have seen lately, and what happened last time."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "People Signal"),
    (New-KpiBlock -Label "PEOPLE" -Value "$peopleCount contacts" -Hint "in the relationship map"),
    (New-KpiBlock -Label "MONTH" -Value "$interactionMonthCount interactions" -Hint "logged this month")
))
Add-LabeledLinkedView -PageId $peopleComponentPageId -Name "People Directory" -DatabaseId $PeopleDatabaseId -Type "gallery"
Add-LabeledLinkedView -PageId $peopleComponentPageId -Name "Recent Interactions" -DatabaseId $InteractionsDatabaseId -Type "list" -Sorts @(@{ property = "Date"; direction = "descending" })
Add-LabeledLinkedView -PageId $peopleComponentPageId -Name "Birthday Calendar" -DatabaseId $PeopleDatabaseId -Type "calendar"
[void](Add-Blocks -PageId $peopleComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $PeopleDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $InteractionsDatabaseId)
))

Write-Host "Rebuilding Running component page: $runningComponentPageId"
Clear-PageChildren -PageId $runningComponentPageId
[void](Add-Blocks -PageId $runningComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Running is the working surface for planned runs, logged runs, notes, and momentum."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Running Signal"),
    (New-KpiBlock -Label "PLANNED" -Value "$runningUpcomingCount runs" -Hint "today or later"),
    (New-KpiBlock -Label "MONTH" -Value "$runningMonthCount runs" -Hint "logged or planned this month")
))
Add-LabeledLinkedView -PageId $runningComponentPageId -Name "Run Calendar" -DatabaseId $RunningLogDatabaseId -Type "calendar" -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $runningComponentPageId -Name "Planned Runs" -DatabaseId $RunningLogDatabaseId -Type "list" -Filter $runningUpcomingFilter -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $runningComponentPageId -Name "Recent Runs" -DatabaseId $RunningLogDatabaseId -Type "table" -Filter $runningMonthFilter -Sorts @(@{ property = "Date"; direction = "descending" })
[void](Add-Blocks -PageId $runningComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $RunningLogDatabaseId)
))

Write-Host "Rebuilding Learning component page: $learningComponentPageId"
Clear-PageChildren -PageId $learningComponentPageId
[void](Add-Blocks -PageId $learningComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Learning is the working surface for study sessions, topic threads, and notes worth returning to."),
    (New-CalloutBlock -Label "CAPTURE" -Text "The Learning Log is the source of truth. Pomodoro, manual entries, and daily updates are all valid ways to capture the same row shape."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Learning Signal"),
    (New-KpiBlock -Label "MONTH" -Value "$learningMonthCount sessions" -Hint "logged this month")
))
Add-LabeledLinkedView -PageId $learningComponentPageId -Name "Learning Calendar" -DatabaseId $LearningLogDatabaseId -Type "calendar" -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $learningComponentPageId -Name "This Month Learning" -DatabaseId $LearningLogDatabaseId -Type "table" -Filter $learningMonthFilter -Sorts @(@{ property = "Date"; direction = "descending" })
Add-LabeledLinkedView -PageId $learningComponentPageId -Name "Learning Capture" -DatabaseId $LearningLogDatabaseId -Type "table" -Filter $learningRecentFilter -Sorts @(@{ property = "Date"; direction = "descending" })
Add-LabeledLinkedView -PageId $learningComponentPageId -Name "Next Learning Tasks" -DatabaseId $TodosDatabaseId -Type "table" -Filter $learningTaskFilter -Sorts @(@{ property = "Due"; direction = "ascending" })
[void](Add-Blocks -PageId $learningComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $LearningLogDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $TodosDatabaseId)
))

Write-Host "Rebuilding Events + Travel component page: $eventsComponentPageId"
Clear-PageChildren -PageId $eventsComponentPageId
[void](Add-Blocks -PageId $eventsComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Events + Travel is the working surface for calendar commitments, food-at-event decisions, trips, and itinerary details."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Events Signal"),
    (New-KpiBlock -Label "EVENTS" -Value "$eventUpcomingCount upcoming" -Hint "dated today or later"),
    (New-KpiBlock -Label "TRAVEL" -Value "$travelUpcomingCount items" -Hint "segments starting today or later"),
    (New-KpiBlock -Label "DECIDE" -Value "$foodDecisionCount events" -Hint "food plan needs attention")
))
Add-LabeledLinkedView -PageId $eventsComponentPageId -Name "Event Calendar" -DatabaseId $EventsTripsDatabaseId -Type "calendar" -Filter $eventUpcomingFilter -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $eventsComponentPageId -Name "Upcoming Events" -DatabaseId $EventsTripsDatabaseId -Type "table" -Filter $eventUpcomingFilter -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $eventsComponentPageId -Name "Food Decisions" -DatabaseId $EventsTripsDatabaseId -Type "list" -Filter $foodDecisionFilter -Sorts @(@{ property = "Date"; direction = "ascending" })
Add-LabeledLinkedView -PageId $eventsComponentPageId -Name "Travel Itinerary" -DatabaseId $TravelDatabaseId -Type "table" -Filter $travelUpcomingFilter -Sorts @(@{ property = "Start"; direction = "ascending" })
[void](Add-Blocks -PageId $eventsComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $EventsTripsDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $TravelDatabaseId)
))

Write-Host "Rebuilding Weekly Review + Pulse component page: $reviewComponentPageId"
Clear-PageChildren -PageId $reviewComponentPageId
[void](Add-Blocks -PageId $reviewComponentPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Weekly Review + Pulse is the check-in surface: what worked, what slipped, and what needs attention next."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Pulse Signal"),
    (New-KpiBlock -Label "REVIEWS" -Value "$weeklyRecentCount reviews" -Hint "dated through today"),
    (New-KpiBlock -Label "TASKS" -Value "$todoOpenCount open" -Hint "still not done"),
    (New-KpiBlock -Label "CHORES" -Value "$choreDoneMonthCount completed" -Hint "this month")
))
Add-LabeledLinkedView -PageId $reviewComponentPageId -Name "Weekly Reviews" -DatabaseId $WeeklyReviewDatabaseId -Type "table" -Filter $weeklyRecentFilter -Sorts @(@{ property = "Week Start"; direction = "descending" })
Add-LabeledLinkedView -PageId $reviewComponentPageId -Name "Open Task Pulse" -DatabaseId $TodosDatabaseId -Type "list" -Filter $todoOpenFilter -Sorts @(@{ property = "Due"; direction = "ascending" })
Add-LabeledLinkedView -PageId $reviewComponentPageId -Name "Running This Month" -DatabaseId $RunningLogDatabaseId -Type "table" -Filter $runningMonthFilter -Sorts @(@{ property = "Date"; direction = "descending" })
Add-LabeledLinkedView -PageId $reviewComponentPageId -Name "Learning This Month" -DatabaseId $LearningLogDatabaseId -Type "table" -Filter $learningMonthFilter -Sorts @(@{ property = "Date"; direction = "descending" })
[void](Add-Blocks -PageId $reviewComponentPageId -Children @(
    (New-TextBlock -Type "heading_3" -Text "Deep Dive / Edit Tables"),
    (New-LinkToDatabaseBlock -DatabaseId $WeeklyReviewDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $TodosDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $RunningLogDatabaseId),
    (New-LinkToDatabaseBlock -DatabaseId $LearningLogDatabaseId)
))

[void](Add-Blocks -PageId $page.id -Children @(
    (New-TextBlock -Type "quote" -Text "Sheet of Life Command Center: dashboard components first, hard tables one click deeper."),
    (New-CalloutBlock -Label "PATTERN" -Text "Open a component card to work inside that area: visuals, live rows, and deep editing stay together."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Component Tiles"),
    (New-CalloutBlock -Label "CARDS" -Text "These gallery cards are the tab-style places from the old HTML. The Command Center stays short; the card pages carry the working dashboards.")
))

Add-LabeledLinkedView -PageId $page.id -Name "Command Center Components" -DatabaseId $componentDatabaseId -Type "gallery"

[void](Add-Blocks -PageId $page.id -Children @(
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Reference"),
    (New-CalloutBlock -Label "HOME" -Text "Existing Home remains available as a support page while this component test runs."),
    (New-LinkToPageBlock -PageId $HomePageId),
    (New-CalloutBlock -Label "BUILT" -Text "Components now cover tasks, shopping, recipes, food/calendar, home/chores, people, running, learning, events/travel, and weekly review/pulse.")
))

Write-Host "Refined Command Center complete."
