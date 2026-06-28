# Sheet of Life Meal Brain

This upgrade preserves the original Sheet of Life recipe engine inside Notion without flattening recipes into notes.

## What was built

- Existing `Recipes` database was upgraded with:
  - `Recipe ID`
  - `Carbs`
  - `Fat`
  - `Source`
- Existing `Meal Plan` database was upgraded with:
  - `Recipe Link` relation to `Recipes`
- New structured databases were created:
  - `Ingredients`: `38ce8e29-9eae-8137-80c4-cedbdf6943c7`
  - `Recipe Ingredients`: `38ce8e29-9eae-8131-ba98-de6b87d9f934`
  - `Recipe Suggestions`: `38ce8e29-9eae-81bc-89f9-c81ec968797d`

## Source of truth

The seed data comes from `sheet_of_life_v0.10.2.html`:

- `R`: recipe records
- `DEFAULT_PANTRY`: pantry items ignored for matching
- `SYN`: ingredient synonym normalization
- `GCATS`: ingredient categories

The builder reads that JavaScript directly with Node so recipe instructions, quantities, units, and matching behavior stay faithful to the original app.

## Seeded data

- 15 structured recipe rows
- 211 recipe-ingredient relation rows
- ingredient dictionary rows generated from normalized recipe ingredients plus pantry defaults
- recipe suggestion rows scored by shared non-pantry ingredients

## Command

Dry run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_meal_brain_builder.ps1 -DryRun -CreateRecipeRows
```

Resume or rebuild against the created support databases:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_meal_brain_builder.ps1 -CreateRecipeRows -IngredientsDatabaseId 38ce8e29-9eae-8137-80c4-cedbdf6943c7 -RecipeIngredientsDatabaseId 38ce8e29-9eae-8131-ba98-de6b87d9f934 -RecipeSuggestionsDatabaseId 38ce8e29-9eae-81bc-89f9-c81ec968797d
```

Do not rerun `-CreateRecipeRows` casually. The current builder seeds rows and does not deduplicate existing Notion pages.
