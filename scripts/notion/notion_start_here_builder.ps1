param(
    [string]$ParentPageId = "37fe8e29-9eae-8030-a619-f456bc2274cc",
    [string]$PrototypePageId = "37fe8e29-9eae-8159-bd12-d8bcbf34ec0c",
    [string]$HomePageId = "",
    [string]$CommandCenterPageId = "",
    [string]$MobileHomePageId = "",
    [string]$StatePath = ".sol_start_here_state.json",
    [string]$SectionStatePath = ".sol_home_sections_state.json",
    [string]$TodosDatabaseId = "37fe8e29-9eae-815a-9bb1-ef0e273ff652",
    [string]$RecipesDatabaseId = "37fe8e29-9eae-8192-b4d0-c842a8d6e5a9",
    [string]$MealPlanDatabaseId = "37fe8e29-9eae-816e-ae08-e2ecf42453d3",
    [string]$EventsTripsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$ShoppingListDatabaseId = "37fe8e29-9eae-819e-a1e8-e4a33b5121a2",
    [string]$RecipeSuggestionsDatabaseId = "38ce8e29-9eae-81bc-89f9-c81ec968797d",
    [string]$ChoresDatabaseId = "37fe8e29-9eae-81de-a1bd-db293503adfa",
    [string]$PeopleDatabaseId = "37fe8e29-9eae-819c-98be-f20d83340774",
    [string]$BlocksVersion = "2022-06-28",
    [string]$ViewsVersion = "2026-03-11",
    [switch]$CreateIfMissing,
    [switch]$ArchiveExistingChildren,
    [switch]$ArchiveLegacyPages,
    [switch]$DryRun,
    [switch]$VerboseDryRun
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
    $clean = ($Value -replace "[^0-9a-fA-F]", "").ToLowerInvariant()
    if ($clean.Length -ne 32) { throw "Notion ID must contain 32 hex characters. Received '$Value'." }
    return "{0}-{1}-{2}-{3}-{4}" -f $clean.Substring(0, 8), $clean.Substring(8, 4), $clean.Substring(12, 4), $clean.Substring(16, 4), $clean.Substring(20, 12)
}

function New-RichText {
    param([string]$Text, [switch]$Bold, [switch]$Code)
    if (-not $Text) { return @() }
    return @(@{
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

function New-TitlePropertyValue {
    param([string]$Text)
    return @{ title = @(@{ type = "text"; text = @{ content = $Text } }) }
}

function New-TextBlock {
    param([string]$Type, [string]$Text, [string]$Color = "default")
    return @{
        object = "block"
        type = $Type
        $Type = @{
            rich_text = @((New-RichText -Text $Text))
            color = $Color
        }
    }
}

function New-CalloutBlock {
    param([string]$Label, [string]$Text)
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

function New-ColumnListBlock {
    param([array]$Columns)
    return @{
        object = "block"
        type = "column_list"
        column_list = @{
            children = @(
                $Columns | ForEach-Object {
                    @{
                        object = "block"
                        type = "column"
                        column = @{
                            children = $_
                        }
                    }
                }
            )
        }
    }
}

function New-DividerBlock {
    return @{ object = "block"; type = "divider"; divider = @{} }
}

function New-PropertySchema {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [string[]]$Options = @(),
        [string]$RelationDatabaseId = ""
    )

    switch ($Type) {
        "rich_text" { return @{ rich_text = @{} } }
        "checkbox" { return @{ checkbox = @{} } }
        "select" { return @{ select = @{ options = @($Options | ForEach-Object { @{ name = $_ } }) } } }
        "url" { return @{ url = @{} } }
        "relation" {
            if (-not $RelationDatabaseId) { throw "Relation properties require RelationDatabaseId." }
            return @{ relation = @{ database_id = (ConvertTo-NotionId -Value $RelationDatabaseId); type = "single_property"; single_property = @{} } }
        }
        default { throw "Unsupported property type '$Type'." }
    }
}

function Invoke-NotionApi {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null,
        [string]$Version = $BlocksVersion
    )

    if ($DryRun) {
        $label = ""
        if ($Body -and $Body.properties -and $Body.properties.title -and $Body.properties.title.title.Count -gt 0) {
            $label = " - $($Body.properties.title.title[0].text.content)"
        } elseif ($Body -and $Body.name) {
            $label = " - $($Body.name)"
        }
        Write-Host "DRY RUN $Method $Path$label"
        if ($VerboseDryRun -and $Body) { Write-Host ($Body | ConvertTo-Json -Depth 60) }
        return @{ id = "$([guid]::NewGuid().ToString("N"))"; results = @(); has_more = $false; data_sources = @(@{ id = "$([guid]::NewGuid().ToString("N"))" }) }
    }

    $parameters = @{
        Method = $Method
        Uri = "https://api.notion.com/v1$Path"
        Headers = @{
            Authorization = "Bearer $script:NotionToken"
            "Notion-Version" = $Version
            "Content-Type" = "application/json"
        }
    }
    if ($null -ne $Body) { $parameters["Body"] = ($Body | ConvertTo-Json -Depth 60) }

    try {
        return Invoke-RestMethod @parameters
    } catch {
        $details = $_.Exception.Message
        if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseText = $reader.ReadToEnd()
            if ($responseText) { $details = "$details`n$responseText" }
        }
        throw "Notion API request failed: $Method $Path`n$details"
    }
}

function Get-StatePageId {
    param([string]$Path, [string]$Property)
    $fullPath = Join-Path -Path $RepoRoot -ChildPath $Path
    if (-not (Test-Path -LiteralPath $fullPath)) { return "" }
    $state = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    return [string]$state.$Property
}

function Save-State {
    param([string]$PageId)
    $stateFile = Join-Path -Path $RepoRoot -ChildPath $StatePath
    @{
        startHerePageId = $PageId
        updatedAt = (Get-Date).ToString("o")
        unifiedHome = $true
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile
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

function Get-OrCreateSectionPage {
    param(
        [string]$Key,
        [string]$Title,
        [string]$ParentPageId,
        [hashtable]$State
    )

    if ($State.ContainsKey($Key) -and $State[$Key]) {
        return (ConvertTo-NotionId -Value ([string]$State[$Key]))
    }

    $page = Invoke-NotionApi -Method "POST" -Path "/pages" -Body @{
        parent = @{ page_id = (ConvertTo-NotionId -Value $ParentPageId) }
        properties = @{ title = (New-TitlePropertyValue -Text $Title) }
    }
    $State[$Key] = $page.id
    Write-Host "Created Home work area: $Title ($($page.id))"
    return $page.id
}

function Get-BlockChildren {
    param([string]$BlockId)
    $children = @()
    $cursor = ""
    do {
        $path = "/blocks/$(ConvertTo-NotionId -Value $BlockId)/children?page_size=100"
        if ($cursor) { $path = "$path&start_cursor=$cursor" }
        $response = Invoke-NotionApi -Method "GET" -Path $path
        $children += @($response.results)
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
        Write-Host "Archived existing Home block: $($child.id)"
    }
}

function Add-Blocks {
    param([string]$PageId, [array]$Children)
    [void](Invoke-NotionApi -Method "PATCH" -Path "/blocks/$(ConvertTo-NotionId -Value $PageId)/children" -Body @{ children = $Children })
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

function Add-LabeledLinkedView {
    param(
        [string]$PageId,
        [string]$Name,
        [string]$DatabaseId,
        [string]$Type = "table",
        $Filter = $null,
        $Sorts = $null
    )

    Add-Blocks -PageId $PageId -Children @((New-TextBlock -Type "heading_3" -Text $Name))
    Add-LinkedView -PageId $PageId -Name $Name -DatabaseId $DatabaseId -Type $Type -Filter $Filter -Sorts $Sorts
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $DryRun -and -not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

if (-not $HomePageId) {
    $HomePageId = Get-StatePageId -Path $StatePath -Property "startHerePageId"
}
if (-not $CommandCenterPageId) {
    $CommandCenterPageId = Get-StatePageId -Path ".sol_command_center_state.json" -Property "commandCenterPageId"
}
if (-not $MobileHomePageId) {
    $MobileHomePageId = Get-StatePageId -Path ".sol_mobile_home_state.json" -Property "mobileHomePageId"
}

if (-not $HomePageId -and -not $CreateIfMissing) {
    throw "Missing HomePageId. Pass -HomePageId, restore $StatePath, or run with -CreateIfMissing."
}

if ($HomePageId) {
    $homePageId = ConvertTo-NotionId -Value $HomePageId
    Write-Host "Updating existing Sheet of Life Home: $homePageId"
} else {
    $page = Invoke-NotionApi -Method "POST" -Path "/pages" -Body @{
        parent = @{ page_id = (ConvertTo-NotionId -Value $ParentPageId) }
        properties = @{ title = (New-TitlePropertyValue -Text "00 - Sheet of Life Home") }
    }
    $homePageId = $page.id
    Write-Host "Created Sheet of Life Home: $homePageId"
}
if (-not $DryRun) { Save-State -PageId $homePageId }

$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "Upgrading database properties used by the unified Home workflow."
[void](Invoke-NotionApi -Method "PATCH" -Path "/databases/$(ConvertTo-NotionId -Value $RecipesDatabaseId)" -Body @{
    properties = @{
        Status = New-PropertySchema -Type "select" -Options @("To Process", "Ready", "Cook Soon", "Archived")
        "Source URL" = New-PropertySchema -Type "url"
        "Raw Recipe Notes" = New-PropertySchema -Type "rich_text"
    }
})
[void](Invoke-NotionApi -Method "PATCH" -Path "/databases/$(ConvertTo-NotionId -Value $EventsTripsDatabaseId)" -Body @{
    properties = @{
        "Food Included" = New-PropertySchema -Type "checkbox"
        "Food Plan" = New-PropertySchema -Type "select" -Options @("Food provided", "Eat out", "Bring food", "Snack only", "No food", "Decide later")
        "Meal Slot" = New-PropertySchema -Type "select" -Options @("Breakfast", "Lunch", "Dinner", "Snack")
        "Food Notes" = New-PropertySchema -Type "rich_text"
    }
})
[void](Invoke-NotionApi -Method "PATCH" -Path "/databases/$(ConvertTo-NotionId -Value $MealPlanDatabaseId)" -Body @{
    properties = @{
        "Recipe Link" = New-PropertySchema -Type "relation" -RelationDatabaseId $RecipesDatabaseId
    }
})

$sectionState = Get-JsonState -Path $SectionStatePath
$sectionParentPageId = ConvertTo-NotionId -Value $PrototypePageId
$todayDeskPageId = Get-OrCreateSectionPage -Key "todayDeskPageId" -Title "Today Desk" -ParentPageId $sectionParentPageId -State $sectionState
$foodPlannerPageId = Get-OrCreateSectionPage -Key "foodPlannerPageId" -Title "Food Planner" -ParentPageId $sectionParentPageId -State $sectionState
$capturePadPageId = Get-OrCreateSectionPage -Key "capturePadPageId" -Title "Capture Pad" -ParentPageId $sectionParentPageId -State $sectionState
$weeklyResetPageId = Get-OrCreateSectionPage -Key "weeklyResetPageId" -Title "Weekly Reset" -ParentPageId $sectionParentPageId -State $sectionState
if (-not $DryRun) { Save-JsonState -Path $SectionStatePath -State $sectionState }

if ($ArchiveExistingChildren) {
    Write-Host "Archiving existing visible Home content before rebuilding."
    Clear-PageChildren -PageId $homePageId
    foreach ($sectionPageId in @($todayDeskPageId, $foodPlannerPageId, $capturePadPageId, $weeklyResetPageId)) {
        Clear-PageChildren -PageId $sectionPageId
    }
}

Add-Blocks -PageId $homePageId -Children @(
    (New-TextBlock -Type "quote" -Text "Open here, do the day, capture the loose thing, then leave."),
    (New-TextBlock -Type "heading_2" -Text "Start Here"),
    (New-CalloutBlock -Label "NOW" -Text "Daily actions stay on this page. Planning and maintenance are nearby, but they do not get equal weight.")
)

Add-LabeledLinkedView -PageId $homePageId -Name "Do Today" -DatabaseId $TodosDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Status"; select = @{ does_not_equal = "Done" } },
        @{ property = "Status"; select = @{ does_not_equal = "Cancelled" } },
        @{
            or = @(
                @{ property = "Do Date"; date = @{ on_or_before = $today } },
                @{ property = "Due"; date = @{ on_or_before = $today } }
            )
        }
    )
} -Sorts @(@{ property = "Do Date"; direction = "ascending" }, @{ property = "Due"; direction = "ascending" })

Add-LabeledLinkedView -PageId $homePageId -Name "Food Today" -DatabaseId $MealPlanDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Date"; date = @{ equals = $today } }
    )
} -Sorts @(@{ property = "Slot"; direction = "ascending" })

Add-LabeledLinkedView -PageId $homePageId -Name "Home Due" -DatabaseId $ChoresDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Date"; date = @{ on_or_before = $today } }
    )
} -Sorts @(@{ property = "Date"; direction = "ascending" })

Add-Blocks -PageId $homePageId -Children @(
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Quick Capture"),
    (New-CalloutBlock -Label "INBOX" -Text "Capture tasks here without deciding the whole system. Recipe links and shopping are in Capture Pad.")
)

Add-LabeledLinkedView -PageId $homePageId -Name "Task Inbox" -DatabaseId $TodosDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Status"; select = @{ equals = "Inbox" } }
    )
}

Add-Blocks -PageId $homePageId -Children @(
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Planning Rooms"),
    (New-CalloutBlock -Label "FOOD" -Text "Use this when you are intentionally planning meals, recipes, leftovers, or food events."),
    (New-LinkToPageBlock -PageId $foodPlannerPageId),
    (New-CalloutBlock -Label "CAPTURE" -Text "Use this for recipe links, shopping, and messy inbox cleanup."),
    (New-LinkToPageBlock -PageId $capturePadPageId),
    (New-CalloutBlock -Label "RESET" -Text "Use this for weekly planning, upcoming events, and recipe matches."),
    (New-LinkToPageBlock -PageId $weeklyResetPageId)
)

Add-Blocks -PageId $todayDeskPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Finish, move, or reschedule what is visible here."),
    (New-TextBlock -Type "heading_2" -Text "Today Desk")
)

Add-LabeledLinkedView -PageId $todayDeskPageId -Name "Do Today" -DatabaseId $TodosDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Status"; select = @{ does_not_equal = "Done" } },
        @{ property = "Status"; select = @{ does_not_equal = "Cancelled" } },
        @{
            or = @(
                @{ property = "Do Date"; date = @{ on_or_before = $today } },
                @{ property = "Due"; date = @{ on_or_before = $today } }
            )
        }
    )
} -Sorts @(@{ property = "Do Date"; direction = "ascending" }, @{ property = "Due"; direction = "ascending" })

Add-LabeledLinkedView -PageId $todayDeskPageId -Name "Food Today" -DatabaseId $MealPlanDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Date"; date = @{ equals = $today } }
    )
} -Sorts @(@{ property = "Slot"; direction = "ascending" })

Add-LabeledLinkedView -PageId $todayDeskPageId -Name "Home Due" -DatabaseId $ChoresDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Date"; date = @{ on_or_before = $today } }
    )
} -Sorts @(@{ property = "Date"; direction = "ascending" })

Add-Blocks -PageId $foodPlannerPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Plan food coverage, not perfect cooking."),
    (New-TextBlock -Type "heading_2" -Text "Food Planner"),
    (New-CalloutBlock -Label "REALISTIC" -Text "Cook, leftovers, quick meals, eating out, and trivia food all count.")
)

Add-LabeledLinkedView -PageId $foodPlannerPageId -Name "Meal Calendar" -DatabaseId $MealPlanDatabaseId -Type "calendar" -Filter @{
    property = "Date"
    date = @{ on_or_after = $today }
} -Sorts @(@{ property = "Date"; direction = "ascending" })

Add-LabeledLinkedView -PageId $foodPlannerPageId -Name "Recipes To Choose From" -DatabaseId $RecipesDatabaseId -Type "gallery" -Filter @{
    or = @(
        @{ property = "Status"; select = @{ equals = "Cook Soon" } },
        @{ property = "Status"; select = @{ equals = "Ready" } }
    )
}

Add-LabeledLinkedView -PageId $foodPlannerPageId -Name "Food Events To Decide" -DatabaseId $EventsTripsDatabaseId -Type "list" -Filter @{
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
} -Sorts @(@{ property = "Date"; direction = "ascending" })

Add-Blocks -PageId $capturePadPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Capture first. Organize later."),
    (New-TextBlock -Type "heading_2" -Text "Capture Pad"),
    (New-CalloutBlock -Label "FAST" -Text "Use these when you are on your phone or moving fast. Messy is fine here.")
)

Add-LabeledLinkedView -PageId $capturePadPageId -Name "Task Inbox" -DatabaseId $TodosDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Status"; select = @{ equals = "Inbox" } }
    )
}

Add-LabeledLinkedView -PageId $capturePadPageId -Name "Recipe Inbox" -DatabaseId $RecipesDatabaseId -Type "list" -Filter @{
    property = "Status"
    select = @{ equals = "To Process" }
}

Add-LabeledLinkedView -PageId $capturePadPageId -Name "Shopping Inbox" -DatabaseId $ShoppingListDatabaseId -Type "list" -Filter @{
    property = "Purchased"
    checkbox = @{ equals = $false }
}

Add-Blocks -PageId $weeklyResetPageId -Children @(
    (New-TextBlock -Type "quote" -Text "Use this when you are planning, not all day."),
    (New-TextBlock -Type "heading_2" -Text "Weekly Reset")
)

Add-LabeledLinkedView -PageId $weeklyResetPageId -Name "Next Up" -DatabaseId $TodosDatabaseId -Type "list" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Status"; select = @{ does_not_equal = "Done" } },
        @{ property = "Status"; select = @{ does_not_equal = "Cancelled" } }
    )
} -Sorts @(@{ property = "Do Date"; direction = "ascending" }, @{ property = "Due"; direction = "ascending" })

Add-LabeledLinkedView -PageId $weeklyResetPageId -Name "Events Soon" -DatabaseId $EventsTripsDatabaseId -Type "list" -Filter @{
    property = "Date"
    date = @{ on_or_after = $today }
} -Sorts @(@{ property = "Date"; direction = "ascending" })

Add-LabeledLinkedView -PageId $weeklyResetPageId -Name "Recipe Matches" -DatabaseId $RecipeSuggestionsDatabaseId -Type "list" -Sorts @(@{ property = "Score"; direction = "descending" })

Add-Blocks -PageId $weeklyResetPageId -Children @(
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Tiny Instructions"),
    (New-CalloutBlock -Label "ADD RECIPE" -Text "Create it in Recipe Inbox with a name, source URL, and raw notes. Clean it later."),
    (New-CalloutBlock -Label "PLAN MEAL" -Text "Create it on Meal Calendar. Choose Cook, Leftover, Quick, or Eat Out. Link a recipe only when needed."),
    (New-CalloutBlock -Label "EVENT FOOD" -Text "For trivia or dinner plans, use Food Events To Decide and set whether food is covered.")
)

$supportBlocks = @(
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Support Links"),
    (New-CalloutBlock -Label "SUPPORT" -Text "These are reference/legacy surfaces, not places to work from day to day.")
)
if ($CommandCenterPageId) { $supportBlocks += (New-LinkToPageBlock -PageId $CommandCenterPageId) }
if ($MobileHomePageId) { $supportBlocks += (New-LinkToPageBlock -PageId $MobileHomePageId) }
$supportBlocks += (New-LinkToPageBlock -PageId $PrototypePageId)
Add-Blocks -PageId $homePageId -Children $supportBlocks

if ($ArchiveLegacyPages) {
    foreach ($legacyPageId in @($CommandCenterPageId, $MobileHomePageId)) {
        if ($legacyPageId -and (ConvertTo-NotionId -Value $legacyPageId) -ne (ConvertTo-NotionId -Value $homePageId)) {
            [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$(ConvertTo-NotionId -Value $legacyPageId)" -Body @{ archived = $true })
            Write-Host "Archived legacy support page: $legacyPageId"
        }
    }
}

Write-Host "Unified Sheet of Life Home complete."
