param(
    [string]$HomePageId = "",
    [string]$StatePath = ".sol_start_here_state.json",
    [string]$SectionStatePath = ".sol_home_sections_state.json",
    [string]$PrototypePageId = "37fe8e29-9eae-8159-bd12-d8bcbf34ec0c",
    [string]$CommandCenterPageId = "",
    [string]$MobileHomePageId = "",
    [string]$RecipesDatabaseId = "37fe8e29-9eae-8192-b4d0-c842a8d6e5a9",
    [string]$MealPlanDatabaseId = "37fe8e29-9eae-816e-ae08-e2ecf42453d3",
    [string]$EventsTripsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$BlocksVersion = "2022-06-28",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }

    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) { continue }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) { continue }

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

function Get-StatePageId {
    param([string]$Path, [string]$Property)
    $fullPath = Join-Path -Path $RepoRoot -ChildPath $Path
    if (-not (Test-Path -LiteralPath $fullPath)) { return "" }
    $state = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    return [string]$state.$Property
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
    if ($null -ne $Body) { $parameters["Body"] = ($Body | ConvertTo-Json -Depth 30) }

    return Invoke-RestMethod @parameters
}

function Get-PlainText {
    param($RichText)
    return (($RichText | ForEach-Object { $_.plain_text }) -join "")
}

function Add-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail
    )

    $script:Checks += [pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $script:NotionToken) {
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
if (-not $HomePageId) {
    throw "Missing HomePageId and could not read $StatePath."
}

$todayDeskPageId = Get-StatePageId -Path $SectionStatePath -Property "todayDeskPageId"
$foodPlannerPageId = Get-StatePageId -Path $SectionStatePath -Property "foodPlannerPageId"
$capturePadPageId = Get-StatePageId -Path $SectionStatePath -Property "capturePadPageId"
$weeklyResetPageId = Get-StatePageId -Path $SectionStatePath -Property "weeklyResetPageId"

$script:Checks = @()
$homePageId = ConvertTo-NotionId -Value $HomePageId

$page = Invoke-NotionApi -Method "GET" -Path "/pages/$homePageId"
$children = Invoke-NotionApi -Method "GET" -Path "/blocks/$homePageId/children?page_size=100"

$titleProperty = $page.properties.PSObject.Properties | Where-Object { $_.Value.type -eq "title" } | Select-Object -First 1
$title = Get-PlainText -RichText $titleProperty.Value.title

$sections = @($children.results | Where-Object { $_.type -eq "heading_2" } | ForEach-Object { Get-PlainText -RichText $_.heading_2.rich_text })
$viewLabels = @($children.results | Where-Object { $_.type -eq "heading_3" } | ForEach-Object { Get-PlainText -RichText $_.heading_3.rich_text })
$linkedViewCount = @($children.results | Where-Object { $_.type -eq "child_database" }).Count
$homeLinkIds = @($children.results | Where-Object { $_.type -eq "link_to_page" } | ForEach-Object { $_.link_to_page.page_id })

$expectedSections = @("Choose a Mode", "How This Works", "Support Links")

Add-Check -Name "Home page reachable" -Passed (-not $page.archived) -Detail "title='$title' id=$homePageId"
Add-Check -Name "Single working page title" -Passed ($title -eq "00 - Sheet of Life Home") -Detail "title='$title'"
Add-Check -Name "Expected sections present" -Passed (@($expectedSections | Where-Object { $sections -notcontains $_ }).Count -eq 0) -Detail (($sections) -join " | ")
Add-Check -Name "Home is a launcher, not a data-entry stack" -Passed ($linkedViewCount -eq 0) -Detail "home_linked_views=$linkedViewCount home_view_labels=$($viewLabels.Count)"

$expectedSupportIds = @($PrototypePageId, $CommandCenterPageId, $MobileHomePageId) | Where-Object { $_ } | ForEach-Object { ConvertTo-NotionId -Value $_ }
$missingSupportIds = @($expectedSupportIds | Where-Object { $homeLinkIds -notcontains $_ })
Add-Check -Name "Legacy pages are subordinate support links" -Passed ($missingSupportIds.Count -eq 0) -Detail "home_links=$($homeLinkIds.Count) missing=$($missingSupportIds -join ', ')"

$workAreas = @(
    @{ Name = "Today Desk"; Id = $todayDeskPageId; Views = @("Do Today", "Food Today", "Home Due") },
    @{ Name = "Food Planner"; Id = $foodPlannerPageId; Views = @("Meal Calendar", "Recipes To Choose From", "Food Events To Decide") },
    @{ Name = "Capture Pad"; Id = $capturePadPageId; Views = @("Task Inbox", "Recipe Inbox", "Shopping Inbox") },
    @{ Name = "Weekly Reset"; Id = $weeklyResetPageId; Views = @("Next Up", "Events Soon", "Recipe Matches") }
)

$expectedWorkAreaIds = @($todayDeskPageId, $foodPlannerPageId, $capturePadPageId, $weeklyResetPageId) | Where-Object { $_ } | ForEach-Object { ConvertTo-NotionId -Value $_ }
$missingWorkAreaLinks = @($expectedWorkAreaIds | Where-Object { $homeLinkIds -notcontains $_ })
Add-Check -Name "Mode chooser links to work areas" -Passed ($missingWorkAreaLinks.Count -eq 0) -Detail "missing=$($missingWorkAreaLinks -join ', ')"

foreach ($area in $workAreas) {
    if (-not $area.Id) {
        Add-Check -Name "$($area.Name) exists" -Passed $false -Detail "Missing from $SectionStatePath"
        continue
    }

    $areaPageId = ConvertTo-NotionId -Value $area.Id
    $areaPage = Invoke-NotionApi -Method "GET" -Path "/pages/$areaPageId"
    $areaChildren = Invoke-NotionApi -Method "GET" -Path "/blocks/$areaPageId/children?page_size=100"
    $areaLabels = @($areaChildren.results | Where-Object { $_.type -eq "heading_3" } | ForEach-Object { Get-PlainText -RichText $_.heading_3.rich_text })
    $areaLinkedViews = @($areaChildren.results | Where-Object { $_.type -eq "child_database" }).Count
    $missingAreaViews = @($area.Views | Where-Object { $areaLabels -notcontains $_ })

    Add-Check -Name "$($area.Name) reachable" -Passed (-not $areaPage.archived) -Detail "id=$areaPageId"
    Add-Check -Name "$($area.Name) has focused views" -Passed ($missingAreaViews.Count -eq 0 -and $areaLinkedViews -eq $area.Views.Count) -Detail "views=$($areaLabels -join ' | ') linked_views=$areaLinkedViews missing=$($missingAreaViews -join ', ')"
}

$readyRecipeBody = @{
    page_size = 100
    filter = @{
        or = @(
            @{ property = "Status"; select = @{ equals = "Ready" } },
            @{ property = "Status"; select = @{ equals = "Cook Soon" } }
        )
    }
}
$readyRecipes = Invoke-NotionApi -Method "POST" -Path "/databases/$(ConvertTo-NotionId -Value $RecipesDatabaseId)/query" -Body $readyRecipeBody
Add-Check -Name "Recipe planning has ready recipes" -Passed ($readyRecipes.results.Count -gt 0) -Detail "ready_or_cooksoon_recipes=$($readyRecipes.results.Count)"

$mealDatabase = Invoke-NotionApi -Method "GET" -Path "/databases/$(ConvertTo-NotionId -Value $MealPlanDatabaseId)"
Add-Check -Name "Meal Plan has recipe relation" -Passed ([bool]$mealDatabase.properties."Recipe Link") -Detail "Recipe Link property present=$([bool]$mealDatabase.properties.'Recipe Link')"

$eventsDatabase = Invoke-NotionApi -Method "GET" -Path "/databases/$(ConvertTo-NotionId -Value $EventsTripsDatabaseId)"
$foodProps = @("Food Included", "Food Plan", "Meal Slot", "Food Notes")
$missingFoodProps = @($foodProps | Where-Object { -not $eventsDatabase.properties.$_ })
Add-Check -Name "Events support food coverage" -Passed ($missingFoodProps.Count -eq 0) -Detail "missing=$($missingFoodProps -join ', ')"

$failed = @($script:Checks | Where-Object { -not $_.Passed })

if (-not $Quiet) {
    foreach ($check in $script:Checks) {
        $status = if ($check.Passed) { "PASS" } else { "FAIL" }
        Write-Host "$status - $($check.Name): $($check.Detail)"
    }
}

if ($failed.Count -gt 0) {
    throw "Unified Home verification failed: $($failed.Count) check(s) failed."
}

if (-not $Quiet) {
    Write-Host "Unified Home verification passed."
}
