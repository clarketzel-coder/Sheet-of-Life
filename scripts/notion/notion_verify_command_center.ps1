param(
    [string]$CommandCenterStatePath = ".sol_command_center_state.json",
    [string]$ComponentStatePath = ".sol_command_components_state.json",
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

function Get-PlainText {
    param($RichText)
    return (($RichText | ForEach-Object { $_.plain_text }) -join "")
}

function Invoke-NotionApi {
    param([string]$Method, [string]$Path, $Body = $null)
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

function Get-BlockTree {
    param([array]$Blocks)

    $all = @()
    foreach ($block in $Blocks) {
        $all += $block
        if ($block.has_children) {
            $childBlocks = Get-BlockChildren -BlockId $block.id
            $all += Get-BlockTree -Blocks $childBlocks
        }
    }
    return $all
}

function Get-JsonState {
    param([string]$Path)

    $fullPath = Join-Path -Path $RepoRoot -ChildPath $Path
    if (-not (Test-Path -LiteralPath $fullPath)) { throw "Missing $Path." }
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
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

function Get-BlockLabels {
    param([array]$Blocks, [string]$Type)

    return @($Blocks | Where-Object { $_.type -eq $Type } | ForEach-Object { Get-PlainText -RichText $_.$Type.rich_text })
}

function Get-KpiCount {
    param([array]$Blocks)

    return @($Blocks | Where-Object { $_.type -eq "callout" } | Where-Object {
        $txt = Get-PlainText -RichText $_.callout.rich_text
        $txt -match "^(TODAY|READY|DECIDE|OPEN|THIS WEEK|DONE|MONTH)\s+"
    }).Count
}

function Test-ComponentPage {
    param(
        [string]$DatabaseId,
        [string]$Name,
        [string]$ExpectedSection,
        [array]$ExpectedLabels,
        [int]$MinViews,
        [int]$MinLinks
    )

    $componentPage = Find-ComponentPage -DatabaseId $DatabaseId -Name $Name
    if (-not $componentPage) {
        Add-Check -Name "$Name component exists" -Passed $false -Detail "missing"
        return
    }

    $componentChildren = Get-BlockChildren -BlockId $componentPage.id
    $componentAllBlocks = Get-BlockTree -Blocks $componentChildren
    $componentSections = Get-BlockLabels -Blocks $componentChildren -Type "heading_2"
    $componentLabels = Get-BlockLabels -Blocks $componentChildren -Type "heading_3"
    $componentViewCount = @($componentChildren | Where-Object { $_.type -eq "child_database" }).Count
    $componentLinkCount = @($componentChildren | Where-Object { $_.type -eq "link_to_page" }).Count
    $componentKpiCount = Get-KpiCount -Blocks $componentAllBlocks

    Add-Check -Name "$Name component exists" -Passed ($null -ne $componentPage) -Detail "id=$($componentPage.id)"
    Add-Check -Name "$Name component has working dashboard" -Passed ((@($ExpectedLabels | Where-Object { $componentLabels -notcontains $_ }).Count -eq 0) -and ($componentSections -contains $ExpectedSection) -and $componentViewCount -ge $MinViews -and $componentLinkCount -ge $MinLinks) -Detail "sections=$($componentSections -join ' | '); labels=$($componentLabels -join ' | '); views=$componentViewCount; kpis=$componentKpiCount; links=$componentLinkCount"
}

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $script:Checks += [pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $script:NotionToken) { throw "Missing NOTION_TOKEN." }

$state = Get-JsonState -Path $CommandCenterStatePath
if (-not $state.commandCenterPageId) { throw "Missing commandCenterPageId in $CommandCenterStatePath." }
$componentState = Get-JsonState -Path $ComponentStatePath
if (-not $componentState.componentDatabaseId) { throw "Missing componentDatabaseId in $ComponentStatePath." }

$script:Checks = @()
$pageId = ConvertTo-NotionId -Value $state.commandCenterPageId
$page = Invoke-NotionApi -Method "GET" -Path "/pages/$pageId"
$children = Get-BlockChildren -BlockId $pageId
$allBlocks = Get-BlockTree -Blocks $children
$componentDatabaseId = ConvertTo-NotionId -Value $componentState.componentDatabaseId
$foodPage = Find-ComponentPage -DatabaseId $componentDatabaseId -Name "Food + Calendar"
$homePage = Find-ComponentPage -DatabaseId $componentDatabaseId -Name "Home / Chores"
$foodChildren = if ($foodPage) { Get-BlockChildren -BlockId $foodPage.id } else { @() }
$homeChildren = if ($homePage) { Get-BlockChildren -BlockId $homePage.id } else { @() }
$foodAllBlocks = Get-BlockTree -Blocks $foodChildren
$homeAllBlocks = Get-BlockTree -Blocks $homeChildren

$titleProperty = $page.properties.PSObject.Properties | Where-Object { $_.Value.type -eq "title" } | Select-Object -First 1
$title = Get-PlainText -RichText $titleProperty.Value.title
$sections = Get-BlockLabels -Blocks $children -Type "heading_2"
$labels = Get-BlockLabels -Blocks $children -Type "heading_3"
$linkedViewCount = @($children | Where-Object { $_.type -eq "child_database" }).Count
$topKpiCount = Get-KpiCount -Blocks $allBlocks
$foodLabels = Get-BlockLabels -Blocks $foodChildren -Type "heading_3"
$homeLabels = Get-BlockLabels -Blocks $homeChildren -Type "heading_3"
$foodSections = Get-BlockLabels -Blocks $foodChildren -Type "heading_2"
$homeSections = Get-BlockLabels -Blocks $homeChildren -Type "heading_2"
$foodLinkedViewCount = @($foodChildren | Where-Object { $_.type -eq "child_database" }).Count
$homeLinkedViewCount = @($homeChildren | Where-Object { $_.type -eq "child_database" }).Count
$foodDeepDiveLinkCount = @($foodChildren | Where-Object { $_.type -eq "link_to_page" }).Count
$homeDeepDiveLinkCount = @($homeChildren | Where-Object { $_.type -eq "link_to_page" }).Count
$foodKpiCount = Get-KpiCount -Blocks $foodAllBlocks
$homeKpiCount = Get-KpiCount -Blocks $homeAllBlocks

$expectedTopSections = @("Component Tiles", "Reference")
$blockedTopSections = @("Food + Calendar", "Home / Chores")
$expectedTopLabels = @("Command Center Components")
$expectedFoodLabels = @("Meal Calendar", "Food Today", "Recipe Picks", "Food Events To Decide", "Deep Dive / Edit Tables")
$expectedHomeLabels = @("Chores Due Soon", "Open Home Radar", "Completed This Month", "Deep Dive / Edit Tables")

Add-Check -Name "Command Center reachable" -Passed (-not $page.archived) -Detail "title='$title' id=$pageId"
Add-Check -Name "Command Center title" -Passed ($title -eq "Sheet of Life Command Center") -Detail "title='$title'"
Add-Check -Name "Command Center stays compact" -Passed ((@($expectedTopSections | Where-Object { $sections -notcontains $_ }).Count -eq 0) -and (@($blockedTopSections | Where-Object { $sections -contains $_ }).Count -eq 0)) -Detail ($sections -join " | ")
Add-Check -Name "Command Center has tile view only" -Passed ((@($expectedTopLabels | Where-Object { $labels -notcontains $_ }).Count -eq 0) -and $linkedViewCount -eq 1 -and $topKpiCount -eq 0) -Detail "labels=$($labels -join ' | '); linked_views=$linkedViewCount; top_kpis=$topKpiCount"
Add-Check -Name "Food component page exists" -Passed ($null -ne $foodPage) -Detail "id=$($foodPage.id)"
Add-Check -Name "Food component has working dashboard" -Passed ((@($expectedFoodLabels | Where-Object { $foodLabels -notcontains $_ }).Count -eq 0) -and ($foodSections -contains "Food Signal") -and $foodLinkedViewCount -ge 4 -and $foodKpiCount -ge 3 -and $foodDeepDiveLinkCount -ge 4) -Detail "sections=$($foodSections -join ' | '); labels=$($foodLabels -join ' | '); views=$foodLinkedViewCount; kpis=$foodKpiCount; links=$foodDeepDiveLinkCount"
Add-Check -Name "Home component page exists" -Passed ($null -ne $homePage) -Detail "id=$($homePage.id)"
Add-Check -Name "Home component has working dashboard" -Passed ((@($expectedHomeLabels | Where-Object { $homeLabels -notcontains $_ }).Count -eq 0) -and ($homeSections -contains "Home Signal") -and $homeLinkedViewCount -ge 3 -and $homeKpiCount -ge 3 -and $homeDeepDiveLinkCount -ge 3) -Detail "sections=$($homeSections -join ' | '); labels=$($homeLabels -join ' | '); views=$homeLinkedViewCount; kpis=$homeKpiCount; links=$homeDeepDiveLinkCount"

Test-ComponentPage -DatabaseId $componentDatabaseId -Name "Tasks" -ExpectedSection "Task Signal" -ExpectedLabels @("Due Now", "Open Tasks", "Task Capture", "Deep Dive / Edit Tables") -MinViews 3 -MinLinks 1
Test-ComponentPage -DatabaseId $componentDatabaseId -Name "Shopping" -ExpectedSection "Shopping Signal" -ExpectedLabels @("Shopping List", "Errand Mode", "Deep Dive / Edit Tables") -MinViews 2 -MinLinks 1
Test-ComponentPage -DatabaseId $componentDatabaseId -Name "Recipe Brain" -ExpectedSection "Recipe Signal" -ExpectedLabels @("Ready Recipes", "Recipe Suggestions", "Ingredient Catalog", "Recipe Ingredient Links", "Deep Dive / Edit Tables") -MinViews 4 -MinLinks 4
Test-ComponentPage -DatabaseId $componentDatabaseId -Name "People" -ExpectedSection "People Signal" -ExpectedLabels @("People Directory", "Recent Interactions", "Birthday Calendar", "Deep Dive / Edit Tables") -MinViews 3 -MinLinks 2
Test-ComponentPage -DatabaseId $componentDatabaseId -Name "Running" -ExpectedSection "Running Signal" -ExpectedLabels @("Run Calendar", "Planned Runs", "Recent Runs", "Deep Dive / Edit Tables") -MinViews 3 -MinLinks 1
Test-ComponentPage -DatabaseId $componentDatabaseId -Name "Learning" -ExpectedSection "Learning Signal" -ExpectedLabels @("Learning Calendar", "This Month Learning", "Learning Capture", "Next Learning Tasks", "Deep Dive / Edit Tables") -MinViews 4 -MinLinks 2
Test-ComponentPage -DatabaseId $componentDatabaseId -Name "Events + Travel" -ExpectedSection "Events Signal" -ExpectedLabels @("Event Calendar", "Upcoming Events", "Food Decisions", "Travel Itinerary", "Deep Dive / Edit Tables") -MinViews 4 -MinLinks 2
Test-ComponentPage -DatabaseId $componentDatabaseId -Name "Weekly Review + Pulse" -ExpectedSection "Pulse Signal" -ExpectedLabels @("Weekly Reviews", "Open Task Pulse", "Running This Month", "Learning This Month", "Deep Dive / Edit Tables") -MinViews 4 -MinLinks 4

$failed = @($script:Checks | Where-Object { -not $_.Passed })
if (-not $Quiet) {
    foreach ($check in $script:Checks) {
        $status = if ($check.Passed) { "PASS" } else { "FAIL" }
        Write-Host "$status - $($check.Name): $($check.Detail)"
    }
}

if ($failed.Count -gt 0) {
    throw "Command Center verification failed: $($failed.Count) check(s) failed."
}

if (-not $Quiet) {
    Write-Host "Command Center component verification passed."
}
