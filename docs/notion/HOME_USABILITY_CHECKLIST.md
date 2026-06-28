# Sheet of Life Home Usability Checklist

`00 - Sheet of Life Home` is the only intended daily working surface. Other pages and databases are support infrastructure.

## Pass Criteria

Use this checklist before considering the Sheet of Life Home complete.

### First-open clarity

- Opening Notion should lead to `00 - Sheet of Life Home`.
- The top of the page should answer: which mode am I in?
- The Home page should link to `Today Desk`, `Food Planner`, `Capture Pad`, and `Weekly Reset`.
- The Home page should not contain linked database views.
- The page should not require opening raw databases for normal daily use.

### Phone use

- On mobile, the first screen should show the page title and the mode chooser.
- A task can be marked done from `Today Desk`.
- A loose task can be added from `Task Inbox`.
- A loose recipe can be added from `Recipe Inbox`.
- A shopping item can be added from `Shopping Inbox`.

### Food planning

- `Meal Calendar` is visible in `Food Planner`.
- A meal can be added with date, slot, and type.
- Meal type supports realistic planning: `Cook`, `Leftover`, `Quick`, and `Eat Out`.
- Existing ready recipes appear in `Recipes To Choose From`.
- Events with food appear separately from meal-plan rows.

### Event food

- A trivia night, dinner, party, or trip meal can be tracked as an event.
- Events can record whether food is included.
- Events can record a food plan and meal slot.
- Food events needing a decision appear in `Food Events To Decide`.

### Scope control

- Do not create a new dashboard page for every new problem.
- Prefer adding or refining a filtered view inside one of the four work areas.
- Keep backend databases such as `Ingredients` and `Recipe Ingredients` out of the main daily flow unless they answer a direct planning question.
- Archive or hide legacy dashboards only after the Home page is verified in real use.

## Automated Check

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_verify_home.ps1
```

This verifies the API-visible structure:

- Home page exists and is not archived.
- Home is a launcher, not a data-entry stack.
- The four work areas exist and contain their focused linked views.
- Recipe planning has ready recipes.
- Meal Plan supports recipe relations.
- Events & Trips supports food coverage.

## Manual Notion Polish

Some parts are intentionally manual because the Notion API does not reliably expose all UI controls:

- Favorite `00 - Sheet of Life Home`.
- Put it above raw databases in the sidebar if possible.
- Favorite the four work areas if they are genuinely used often.
- Hide low-signal properties in linked views.
- Use compact density for daily-use views.
- On mobile, confirm the first 30 seconds of use are understandable.
