param(
    [string]$PrototypePageId = "37fe8e29-9eae-8159-bd12-d8bcbf34ec0c",
    [string]$StatePath = ".sol_mobile_home_state.json",
    [string]$TodosDatabaseId = "37fe8e29-9eae-815a-9bb1-ef0e273ff652",
    [string]$MealPlanDatabaseId = "37fe8e29-9eae-816e-ae08-e2ecf42453d3",
    [string]$EventsTripsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$ChoresDatabaseId = "37fe8e29-9eae-81de-a1bd-db293503adfa",
    [string]$ShoppingListDatabaseId = "37fe8e29-9eae-819e-a1e8-e4a33b5121a2",
    [string]$BlocksVersion = "2022-06-28",
    [string]$ViewsVersion = "2026-03-11",
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

    return "{0}-{1}-{2}-{3}-{4}" -f `
        $clean.Substring(0, 8), `
        $clean.Substring(8, 4), `
        $clean.Substring(12, 4), `
        $clean.Substring(16, 4), `
        $clean.Substring(20, 12)
}

function New-RichText {
    param(
        [string]$Text,
        [switch]$Bold,
        [switch]$Code
    )

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
    param(
        [string]$Type,
        [string]$Text,
        [string]$Color = "default"
    )

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

function New-PropertySchema {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [string[]]$Options = @()
    )

    switch ($Type) {
        "rich_text" { return @{ rich_text = @{} } }
        "checkbox" { return @{ checkbox = @{} } }
        "select" { return @{ select = @{ options = @($Options | ForEach-Object { @{ name = $_ } }) } } }
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
        if ($VerboseDryRun -and $Body) { Write-Host ($Body | ConvertTo-Json -Depth 50) }
        return @{ id = "$([guid]::NewGuid().ToString("N"))"; results = @(); data_sources = @(@{ id = "$([guid]::NewGuid().ToString("N"))" }) }
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

    if ($null -ne $Body) { $parameters["Body"] = ($Body | ConvertTo-Json -Depth 50) }

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

function Get-TitleFromPage {
    param($Page)

    foreach ($property in $Page.properties.PSObject.Properties) {
        if ($property.Value.type -eq "title" -and $property.Value.title.Count -gt 0) {
            return (($property.Value.title | ForEach-Object { $_.plain_text }) -join "")
        }
    }

    return ""
}

function Find-CurrentMobileHome {
    $stateFile = Join-Path -Path $RepoRoot -ChildPath $StatePath
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if ($state.mobileHomePageId) {
                $page = Invoke-NotionApi -Method "GET" -Path "/pages/$(ConvertTo-NotionId -Value $state.mobileHomePageId)"
                if (-not $page.archived) { return $page }
            }
        } catch {
            Write-Host "Could not use mobile-home state file; falling back to search."
        }
    }

    $results = Invoke-NotionApi -Method "POST" -Path "/search" -Body @{
        query = "Sheet of Life Mobile Home"
        filter = @{ property = "object"; value = "page" }
        page_size = 10
    }
    $parentId = ConvertTo-NotionId -Value $PrototypePageId

    foreach ($page in $results.results) {
        if ((Get-TitleFromPage -Page $page) -eq "Sheet of Life Mobile Home" -and $page.parent.type -eq "page_id" -and $page.parent.page_id -eq $parentId -and -not $page.archived) {
            return $page
        }
    }

    return $null
}

function Save-MobileHomeState {
    param([string]$PageId)

    $stateFile = Join-Path -Path $RepoRoot -ChildPath $StatePath
    @{
        mobileHomePageId = $PageId
        updatedAt = (Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile
}

function New-MobileHomePage {
    return Invoke-NotionApi -Method "POST" -Path "/pages" -Body @{
        parent = @{ page_id = (ConvertTo-NotionId -Value $PrototypePageId) }
        properties = @{ title = (New-TitlePropertyValue -Text "Sheet of Life Mobile Home") }
    }
}

function Add-Blocks {
    param([string]$PageId, [array]$Children)

    return Invoke-NotionApi -Method "PATCH" -Path "/blocks/$(ConvertTo-NotionId -Value $PageId)/children" -Body @{ children = $Children }
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

    [void](Invoke-NotionApi -Method "POST" -Path "/views" -Body $body -Version $ViewsVersion)
    Write-Host "Added linked view: $Name"
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (-not $DryRun -and -not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "Adding realistic food/event fields to Events & Trips."
[void](Invoke-NotionApi -Method "PATCH" -Path "/databases/$(ConvertTo-NotionId -Value $EventsTripsDatabaseId)" -Version $BlocksVersion -Body @{
    properties = @{
        "Food Included" = New-PropertySchema -Type "checkbox"
        "Food Plan" = New-PropertySchema -Type "select" -Options @("Food provided", "Eat out", "Bring food", "Snack only", "No food", "Decide later")
        "Meal Slot" = New-PropertySchema -Type "select" -Options @("Breakfast", "Lunch", "Dinner", "Snack")
        "Food Notes" = New-PropertySchema -Type "rich_text"
    }
})

$oldPage = Find-CurrentMobileHome
if ($oldPage) {
    [void](Invoke-NotionApi -Method "PATCH" -Path "/pages/$($oldPage.id)" -Body @{ archived = $true })
    Write-Host "Archived old Sheet of Life Mobile Home: $($oldPage.id)"
}

$page = New-MobileHomePage
if (-not $DryRun) { Save-MobileHomeState -PageId $page.id }
Write-Host "Created Sheet of Life Mobile Home: $($page.id)"

[void](Add-Blocks -PageId $page.id -Children @(
    (New-TextBlock -Type "quote" -Text "A phone-sized place to use the system: what needs doing, what I am eating, and what already counts."),
    (New-CalloutBlock -Label "REALISM" -Text "Cooking is not the default. Leftovers, quick meals, eating out, and food events all count as coverage."),
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Today"),
    (New-CalloutBlock -Label "USE" -Text "Mark tasks done here. They disappear from this view but stay in the database for history.")
))

Add-LinkedView -PageId $page.id -Name "Today Tasks" -DatabaseId $TodosDatabaseId -Type "table" -Filter @{
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
} -Sorts @(@{ property = "Do Date"; direction = "ascending" }, @{ property = "Priority"; direction = "ascending" })

Add-LinkedView -PageId $page.id -Name "Quick Inbox" -DatabaseId $TodosDatabaseId -Type "table" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Status"; select = @{ equals = "Inbox" } }
    )
}

[void](Add-Blocks -PageId $page.id -Children @(
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Food Today"),
    (New-CalloutBlock -Label "CHECK" -Text "This is the food coverage layer: cooked meals, leftovers, quick meals, eating out, and events with food.")
))

Add-LinkedView -PageId $page.id -Name "Meals Today" -DatabaseId $MealPlanDatabaseId -Type "table" -Filter @{
    property = "Date"
    date = @{ equals = $today }
} -Sorts @(@{ property = "Slot"; direction = "ascending" })

Add-LinkedView -PageId $page.id -Name "Food Events Today" -DatabaseId $EventsTripsDatabaseId -Type "table" -Filter @{
    and = @(
        @{ property = "Date"; date = @{ equals = $today } },
        @{ property = "Food Included"; checkbox = @{ equals = $true } }
    )
} -Sorts @(@{ property = "Date"; direction = "ascending" })

[void](Add-Blocks -PageId $page.id -Children @(
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Food Soon")
))

Add-LinkedView -PageId $page.id -Name "Upcoming Leftovers / Quick / Eat Out" -DatabaseId $MealPlanDatabaseId -Type "table" -Filter @{
    and = @(
        @{ property = "Date"; date = @{ on_or_after = $today } },
        @{
            or = @(
                @{ property = "Type"; select = @{ equals = "Leftover" } },
                @{ property = "Type"; select = @{ equals = "Quick" } },
                @{ property = "Type"; select = @{ equals = "Eat Out" } }
            )
        }
    )
} -Sorts @(@{ property = "Date"; direction = "ascending" }, @{ property = "Slot"; direction = "ascending" })

Add-LinkedView -PageId $page.id -Name "Upcoming Food Events" -DatabaseId $EventsTripsDatabaseId -Type "table" -Filter @{
    and = @(
        @{ property = "Date"; date = @{ on_or_after = $today } },
        @{ property = "Food Included"; checkbox = @{ equals = $true } }
    )
} -Sorts @(@{ property = "Date"; direction = "ascending" })

[void](Add-Blocks -PageId $page.id -Children @(
    (New-DividerBlock),
    (New-TextBlock -Type "heading_2" -Text "Home / Shopping")
))

Add-LinkedView -PageId $page.id -Name "Home Due" -DatabaseId $ChoresDatabaseId -Type "table" -Filter @{
    and = @(
        @{ property = "Done"; checkbox = @{ equals = $false } },
        @{ property = "Date"; date = @{ on_or_before = $today } }
    )
} -Sorts @(@{ property = "Date"; direction = "ascending" })

Add-LinkedView -PageId $page.id -Name "Shopping Open" -DatabaseId $ShoppingListDatabaseId -Type "table" -Filter @{
    property = "Purchased"
    checkbox = @{ equals = $false }
}

[void](Add-Blocks -PageId $page.id -Children @(
    (New-DividerBlock),
    (New-CalloutBlock -Label "PHONE" -Text "Favorite this page in Notion mobile. Keep database views compact and hide properties you do not need while standing in line or walking into trivia.")
))

Write-Host "Mobile Home complete."
