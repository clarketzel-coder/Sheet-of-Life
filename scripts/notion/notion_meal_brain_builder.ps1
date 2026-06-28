param(
    [string]$PrototypePageId = "37fe8e29-9eae-8159-bd12-d8bcbf34ec0c",
    [string]$RecipesDatabaseId = "37fe8e29-9eae-8192-b4d0-c842a8d6e5a9",
    [string]$MealPlanDatabaseId = "37fe8e29-9eae-816e-ae08-e2ecf42453d3",
    [string]$IngredientsDatabaseId = "",
    [string]$RecipeIngredientsDatabaseId = "",
    [string]$RecipeSuggestionsDatabaseId = "",
    [string]$SourceHtmlPath = ".\sheet_of_life_v0.10.2.html",
    [switch]$CreateRecipeRows,
    [switch]$DryRun,
    [switch]$VerboseDryRun,
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

    if (-not $Text) { return @() }
    return @(@{ type = "text"; text = @{ content = $Text.Substring(0, [Math]::Min(2000, $Text.Length)) } })
}

function New-TitleValue {
    param([string]$Text)
    if (-not $Text) { return @{ title = @() } }
    return @{ title = @(@{ type = "text"; text = @{ content = $Text.Substring(0, [Math]::Min(2000, $Text.Length)) } }) }
}
function New-TextValue {
    param([string]$Text)
    if (-not $Text) { return @{ rich_text = @() } }
    return @{ rich_text = @(@{ type = "text"; text = @{ content = $Text.Substring(0, [Math]::Min(2000, $Text.Length)) } }) }
}
function New-NumberValue {
    param($Value)
    if ($null -eq $Value -or $Value -eq "") { return @{ number = $null } }
    return @{ number = [double]$Value }
}
function New-CheckboxValue { param([bool]$Value) return @{ checkbox = $Value } }
function New-SelectValue {
    param([string]$Text)
    if (-not $Text) { return @{ select = $null } }
    return @{ select = @{ name = $Text } }
}
function New-MultiSelectValue {
    param([string[]]$Names)
    return @{ multi_select = @($Names | Where-Object { $_ } | ForEach-Object { @{ name = $_ } }) }
}
function New-RelationValue {
    param([string[]]$Ids)
    return @{ relation = @($Ids | Where-Object { $_ } | ForEach-Object { @{ id = $_ } }) }
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
        "select" { return @{ select = @{ options = @($Options | ForEach-Object { @{ name = $_ } }) } } }
        "multi_select" { return @{ multi_select = @{ options = @($Options | ForEach-Object { @{ name = $_ } }) } } }
        "relation" {
            if (-not $RelationDatabaseId) { throw "Relation properties require RelationDatabaseId." }
            return @{ relation = @{ database_id = (ConvertTo-NotionId -Value $RelationDatabaseId); type = "single_property"; single_property = @{} } }
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
            foreach ($titleKey in @("Name", "Ingredient", "Suggestion")) {
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
            Write-Host ($Body | ConvertTo-Json -Depth 60)
        }

        return @{ id = "$([guid]::NewGuid().ToString("N"))"; properties = @{} }
    }

    $headers = @{
        Authorization = "Bearer $script:NotionToken"
        "Notion-Version" = $NotionVersion
        "Content-Type" = "application/json"
    }

    $uri = "https://api.notion.com/v1$Path"
    $jsonBody = $Body | ConvertTo-Json -Depth 60
    try {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $jsonBody
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

function New-NotionDatabase {
    param(
        [Parameter(Mandatory = $true)][string]$ParentPageId,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][hashtable]$Properties
    )

    return Invoke-NotionApi -Method "POST" -Path "/databases" -Body @{
        parent = @{ page_id = $ParentPageId }
        title = New-RichText -Text $Title
        properties = $Properties
    }
}

function Update-DatabaseProperties {
    param(
        [Parameter(Mandatory = $true)][string]$DatabaseId,
        [Parameter(Mandatory = $true)][hashtable]$Properties
    )

    return Invoke-NotionApi -Method "PATCH" -Path "/databases/$(ConvertTo-NotionId -Value $DatabaseId)" -Body @{ properties = $Properties }
}

function New-DatabaseRow {
    param(
        [Parameter(Mandatory = $true)][string]$DatabaseId,
        [Parameter(Mandatory = $true)][hashtable]$Properties,
        [object[]]$Children = @()
    )

    $body = @{
        parent = @{ database_id = (ConvertTo-NotionId -Value $DatabaseId) }
        properties = $Properties
    }
    if ($Children.Count -gt 0) { $body.children = $Children }

    return Invoke-NotionApi -Method "POST" -Path "/pages" -Body $body
}

function New-ParagraphBlock { param([string]$Text) return @{ object = "block"; type = "paragraph"; paragraph = @{ rich_text = @((New-RichText -Text $Text)) } } }
function New-HeadingBlock { param([string]$Text) return @{ object = "block"; type = "heading_2"; heading_2 = @{ rich_text = @((New-RichText -Text $Text)) } } }
function New-NumberedBlock { param([string]$Text) return @{ object = "block"; type = "numbered_list_item"; numbered_list_item = @{ rich_text = @((New-RichText -Text $Text)) } } }

function Read-RecipeSource {
    param([string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $nodeScript = @'
const fs = require("fs");
const vm = require("vm");
const path = process.argv[2];
const html = fs.readFileSync(path, "utf8");
function grab(name) {
  const re = new RegExp("const\\s+" + name + "\\s*=\\s*([\\s\\S]*?);\\n");
  const m = html.match(re);
  if (!m) throw new Error("Could not find const " + name);
  return m[1];
}
const context = {};
vm.createContext(context);
for (const name of ["R", "DEFAULT_PANTRY", "SYN", "GCATS"]) {
  vm.runInContext("this." + name + " = " + grab(name), context);
}
process.stdout.write(JSON.stringify({
  recipes: context.R,
  pantry: context.DEFAULT_PANTRY,
  synonyms: context.SYN,
  categories: context.GCATS
}));
'@

    $tempScript = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "sol_recipe_extract_$([guid]::NewGuid().ToString("N")).js"
    try {
        [System.IO.File]::WriteAllText($tempScript, $nodeScript)
        $json = & node $tempScript $resolvedPath
        if ($LASTEXITCODE -ne 0) { throw "Node failed to parse recipe source." }
        return $json | ConvertFrom-Json
    } finally {
        if (Test-Path -LiteralPath $tempScript) {
            Remove-Item -LiteralPath $tempScript -Force
        }
    }
}

function Get-NormalizedName {
    param(
        [string]$Item,
        [hashtable]$Synonyms
    )

    $lower = $Item.ToLowerInvariant()
    $name = ($lower -replace "\b(boneless |skinless |fresh |light |reduced fat |salt reduced |low sodium |dark |extra lean |fat free |shredded |grated |ground |dried |baby |mini |sweet )\b", "").Trim()
    if ($Synonyms.ContainsKey($name)) { return $Synonyms[$name] }
    if ($Synonyms.ContainsKey($lower)) { return $Synonyms[$lower] }
    return $name
}

function Get-IngredientCategory {
    param(
        [string]$Name,
        [object]$Categories
    )

    foreach ($category in $Categories.PSObject.Properties) {
        if (@($category.Value) -contains $Name) { return $category.Name }
    }
    return "Other"
}

function ConvertTo-Hashtable {
    param([object]$Object)

    $hash = @{}
    foreach ($property in $Object.PSObject.Properties) {
        $hash[$property.Name] = [string]$property.Value
    }
    return $hash
}

function Get-NonPantryIngredients {
    param(
        [object]$Recipe,
        [hashtable]$Synonyms,
        [string[]]$Pantry
    )

    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($ingredient in $Recipe.ing) {
        $normalized = Get-NormalizedName -Item $ingredient.i -Synonyms $Synonyms
        if ($Pantry -notcontains $normalized -and $seen.Add($normalized)) {
            $normalized
        }
    }
}

function Get-Suggestions {
    param(
        [object[]]$Recipes,
        [hashtable]$Synonyms,
        [string[]]$Pantry
    )

    $itemsByRecipe = @{}
    foreach ($recipe in $Recipes) {
        $itemsByRecipe[$recipe.id] = @(Get-NonPantryIngredients -Recipe $recipe -Synonyms $Synonyms -Pantry $Pantry)
    }

    $suggestions = @()
    foreach ($source in $Recipes) {
        foreach ($candidate in $Recipes) {
            if ($source.id -eq $candidate.id) { continue }

            $shared = @($itemsByRecipe[$candidate.id] | Where-Object { $itemsByRecipe[$source.id] -contains $_ })
            if ($shared.Count -eq 0) { continue }

            $suggestions += [pscustomobject]@{
                SourceId = $source.id
                CandidateId = $candidate.id
                SourceName = $source.name
                CandidateName = $candidate.name
                Shared = $shared
                Score = $shared.Count
            }
        }
    }

    return $suggestions | Sort-Object SourceId, @{ Expression = "Score"; Descending = $true }, CandidateName
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Import-DotEnv -Path (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath ".env")
$script:NotionToken = Get-EnvValue -Name "NOTION_TOKEN"

if (-not $DryRun -and -not $script:NotionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

$prototypePageId = ConvertTo-NotionId -Value $PrototypePageId
$recipesDatabaseId = ConvertTo-NotionId -Value $RecipesDatabaseId
$mealPlanDatabaseId = ConvertTo-NotionId -Value $MealPlanDatabaseId

$source = Read-RecipeSource -Path $SourceHtmlPath
$recipes = @($source.recipes)
$pantry = @($source.pantry | ForEach-Object { [string]$_ })
$synonyms = ConvertTo-Hashtable -Object $source.synonyms

Write-Host "Loaded $($recipes.Count) recipes from $SourceHtmlPath."
if ($DryRun) { Write-Host "Dry run enabled. No Notion API calls will be made." }

Write-Host "Upgrading existing Recipes database with structured fields."
[void](Update-DatabaseProperties -DatabaseId $recipesDatabaseId -Properties @{
    "Recipe ID" = New-PropertySchema -Type "rich_text"
    "Carbs" = New-PropertySchema -Type "number"
    "Fat" = New-PropertySchema -Type "number"
    "Source" = New-PropertySchema -Type "select" -Options @("Sheet of Life HTML", "Manual", "Imported")
})

Write-Host "Adding a relation-friendly recipe link to the Meal Plan database."
[void](Update-DatabaseProperties -DatabaseId $mealPlanDatabaseId -Properties @{
    "Recipe Link" = New-PropertySchema -Type "relation" -RelationDatabaseId $recipesDatabaseId
})

if ($IngredientsDatabaseId) {
    $ingredientsDbId = ConvertTo-NotionId -Value $IngredientsDatabaseId
    Write-Host "Using existing Ingredients database: $ingredientsDbId"
} else {
    $ingredientsDb = New-NotionDatabase -ParentPageId $prototypePageId -Title "Ingredients" -Properties @{
        Name = New-PropertySchema -Type "title"
        "Normalized Name" = New-PropertySchema -Type "rich_text"
        Category = New-PropertySchema -Type "select" -Options @("Proteins", "Produce", "Dairy", "Grains & Carbs", "Sauces & Pantry", "Other")
        "Pantry Default" = New-PropertySchema -Type "checkbox"
        Aliases = New-PropertySchema -Type "rich_text"
    }
    $ingredientsDbId = $ingredientsDb.id
}
Write-Host "Ingredients database: $ingredientsDbId"

if ($RecipeIngredientsDatabaseId) {
    $recipeIngredientsDbId = ConvertTo-NotionId -Value $RecipeIngredientsDatabaseId
    Write-Host "Using existing Recipe Ingredients database: $recipeIngredientsDbId"
} else {
    $recipeIngredientsDb = New-NotionDatabase -ParentPageId $prototypePageId -Title "Recipe Ingredients" -Properties @{
        Name = New-PropertySchema -Type "title"
        Recipe = New-PropertySchema -Type "relation" -RelationDatabaseId $recipesDatabaseId
        Ingredient = New-PropertySchema -Type "relation" -RelationDatabaseId $ingredientsDbId
        Quantity = New-PropertySchema -Type "number"
        Unit = New-PropertySchema -Type "rich_text"
        "Original Ingredient" = New-PropertySchema -Type "rich_text"
        "Normalized Ingredient" = New-PropertySchema -Type "rich_text"
        "Pantry Item" = New-PropertySchema -Type "checkbox"
        Category = New-PropertySchema -Type "select" -Options @("Proteins", "Produce", "Dairy", "Grains & Carbs", "Sauces & Pantry", "Other")
    }
    $recipeIngredientsDbId = $recipeIngredientsDb.id
}
Write-Host "Recipe Ingredients database: $recipeIngredientsDbId"

if ($RecipeSuggestionsDatabaseId) {
    $recipeSuggestionsDbId = ConvertTo-NotionId -Value $RecipeSuggestionsDatabaseId
    Write-Host "Using existing Recipe Suggestions database: $recipeSuggestionsDbId"
} else {
    $recipeSuggestionsDb = New-NotionDatabase -ParentPageId $prototypePageId -Title "Recipe Suggestions" -Properties @{
        Suggestion = New-PropertySchema -Type "title"
        "Source Recipe" = New-PropertySchema -Type "relation" -RelationDatabaseId $recipesDatabaseId
        "Suggested Recipe" = New-PropertySchema -Type "relation" -RelationDatabaseId $recipesDatabaseId
        Score = New-PropertySchema -Type "number"
        "Shared Ingredients" = New-PropertySchema -Type "rich_text"
    }
    $recipeSuggestionsDbId = $recipeSuggestionsDb.id
}
Write-Host "Recipe Suggestions database: $recipeSuggestionsDbId"

$ingredientPageByName = @{}
$aliasByNormalized = @{}
foreach ($pair in $synonyms.GetEnumerator()) {
    if (-not $aliasByNormalized.ContainsKey($pair.Value)) { $aliasByNormalized[$pair.Value] = @() }
    $aliasByNormalized[$pair.Value] = @($aliasByNormalized[$pair.Value]) + $pair.Key
}

$normalizedNames = New-Object System.Collections.Generic.HashSet[string]
foreach ($recipe in $recipes) {
    foreach ($ingredient in $recipe.ing) {
        [void]$normalizedNames.Add((Get-NormalizedName -Item $ingredient.i -Synonyms $synonyms))
    }
}
foreach ($item in $pantry) {
    [void]$normalizedNames.Add($item)
}

foreach ($name in ($normalizedNames | Sort-Object)) {
    $aliases = ""
    if ($aliasByNormalized.ContainsKey($name)) { $aliases = (@($aliasByNormalized[$name]) | Sort-Object -Unique) -join ", " }
    $category = Get-IngredientCategory -Name $name -Categories $source.categories
    $page = New-DatabaseRow -DatabaseId $ingredientsDbId -Properties @{
        Name = New-TitleValue -Text $name
        "Normalized Name" = New-TextValue -Text $name
        Category = New-SelectValue -Text $category
        "Pantry Default" = New-CheckboxValue -Value ($pantry -contains $name)
        Aliases = New-TextValue -Text $aliases
    }
    $ingredientPageByName[$name] = $page.id
    Write-Host "Seeded ingredient: $name"
}

$recipePageById = @{}
foreach ($recipe in $recipes) {
    $children = @(
        (New-HeadingBlock -Text "Instructions")
    ) + @($recipe.inst | ForEach-Object { New-NumberedBlock -Text ([string]$_) })

    if ($CreateRecipeRows) {
        $page = New-DatabaseRow -DatabaseId $recipesDatabaseId -Properties @{
            Name = New-TitleValue -Text $recipe.name
            "Recipe ID" = New-TextValue -Text $recipe.id
            Cuisine = New-MultiSelectValue -Names @($recipe.cu)
            Servings = New-NumberValue -Value $recipe.srv
            Calories = New-NumberValue -Value $recipe.cal
            Protein = New-NumberValue -Value $recipe.pro
            Carbs = New-NumberValue -Value $recipe.carb
            Fat = New-NumberValue -Value $recipe.fat
            Ingredients = New-TextValue -Text (($recipe.ing | ForEach-Object { "$($_.q) $($_.u) $($_.i)".Trim() }) -join "`n")
            Instructions = New-TextValue -Text (($recipe.inst | ForEach-Object { [string]$_ }) -join "`n")
            Active = New-CheckboxValue -Value $true
            Source = New-SelectValue -Text "Sheet of Life HTML"
        } -Children $children
        $recipePageById[$recipe.id] = $page.id
        Write-Host "Seeded structured recipe: $($recipe.name)"
    } else {
        Write-Host "Skipped recipe row creation for '$($recipe.name)' because -CreateRecipeRows was not passed."
    }
}

if ($CreateRecipeRows) {
    foreach ($recipe in $recipes) {
        foreach ($ingredient in $recipe.ing) {
            $normalized = Get-NormalizedName -Item $ingredient.i -Synonyms $synonyms
            $category = Get-IngredientCategory -Name $normalized -Categories $source.categories
            [void](New-DatabaseRow -DatabaseId $recipeIngredientsDbId -Properties @{
                Name = New-TitleValue -Text "$($recipe.name) - $($ingredient.i)"
                Recipe = New-RelationValue -Ids @($recipePageById[$recipe.id])
                Ingredient = New-RelationValue -Ids @($ingredientPageByName[$normalized])
                Quantity = New-NumberValue -Value $ingredient.q
                Unit = New-TextValue -Text $ingredient.u
                "Original Ingredient" = New-TextValue -Text $ingredient.i
                "Normalized Ingredient" = New-TextValue -Text $normalized
                "Pantry Item" = New-CheckboxValue -Value ($pantry -contains $normalized)
                Category = New-SelectValue -Text $category
            })
            Write-Host "Linked ingredient: $($recipe.name) / $($ingredient.i)"
        }
    }

    $suggestions = @(Get-Suggestions -Recipes $recipes -Synonyms $synonyms -Pantry $pantry)
    foreach ($suggestion in $suggestions) {
        [void](New-DatabaseRow -DatabaseId $recipeSuggestionsDbId -Properties @{
            Suggestion = New-TitleValue -Text "$($suggestion.SourceName) -> $($suggestion.CandidateName)"
            "Source Recipe" = New-RelationValue -Ids @($recipePageById[$suggestion.SourceId])
            "Suggested Recipe" = New-RelationValue -Ids @($recipePageById[$suggestion.CandidateId])
            Score = New-NumberValue -Value $suggestion.Score
            "Shared Ingredients" = New-TextValue -Text ($suggestion.Shared -join ", ")
        })
        Write-Host "Seeded suggestion: $($suggestion.SourceName) -> $($suggestion.CandidateName) ($($suggestion.Score))"
    }
} else {
    Write-Host "Recipe ingredient and suggestion rows require -CreateRecipeRows so relation targets are known."
}

Write-Host "Done."
