# ChatGPT Notion Update Guide for Sheet of Life

## Purpose

Use this guide when asking ChatGPT, Codex, or another local agent to update the **Sheet of Life** Notion workspace.

The Notion workspace is already set up. Future updates should preserve the current structure unless the user explicitly asks to change it.

The canonical daily surface is **Sheet of Life Command Center**. Do not create another dashboard, mobile home, or start-here page by default. If the user says the system is not usable, improve the Command Center component pages.

## Safety Rules

- Do not ask the user to paste the Notion API token into chat.
- Read `NOTION_TOKEN` from the local environment or from a local `.env` file.
- Keep `.env` ignored by git.
- Never print the token.
- Confirm destructive changes before deleting pages, database rows, properties, or databases.
- Prefer additive changes: create records, add properties, append notes, or update specific fields.
- If a Notion API limitation blocks a request, explain the manual Notion UI step clearly.

## Local Workspace

Project folder:

```text
C:\Users\Clark\OneDrive\Documents\Sheet of Life
```

Relevant files:

```text
NOTION_BUILD_PLAN.md
notion_sheet_of_life_builder.ps1
notion_create_todo_hub.ps1
notion_start_here_builder.ps1
notion_verify_home.ps1
NOTION_CANONICAL_SURFACES.md
HOME_USABILITY_CHECKLIST.md
CHATGPT_NOTION_UPDATE_GUIDE.md
.env
```

`.env` may contain:

```text
NOTION_TOKEN=secret_xxx
NOTION_PARENT_PAGE_ID=37fe8e299eae8030a619f456bc2274cc
```

## Current Notion Pages

Parent page:

```text
37fe8e29-9eae-8030-a619-f456bc2274cc
```

Infrastructure page:

```text
37fe8e29-9eae-8159-bd12-d8bcbf34ec0c
```

Infrastructure page title:

```text
Sheet of Life Infrastructure
```

Canonical Command Center page:

```text
38ce8e29-9eae-81e2-9740-dddb8ee7deb3
```

Canonical Command Center page title:

```text
Sheet of Life Command Center
```

Archived legacy pages:

```text
00 - Sheet of Life Home:   38ce8e29-9eae-818c-b546-d60ea34d16c5
Sheet of Life Mobile Home: 38ce8e29-9eae-81ac-850f-cc07cc7b203d
Today Desk:                38ce8e29-9eae-81ed-914b-da6bd8b8c8ee
Food Planner:              38ce8e29-9eae-814a-b3ae-cdaf56add1cf
Capture Pad:               38ce8e29-9eae-8187-b407-d7df866e5af2
Weekly Reset:              38ce8e29-9eae-813e-abfa-e1706962f932
```

Command Center component pages:

```text
Tasks
Shopping
Recipe Brain
Food + Calendar
Home / Chores
People
Running
Learning
Events + Travel
Weekly Review + Pulse
```

Treat the raw databases as infrastructure. The user should normally start from `Sheet of Life Command Center`, then enter one of its component cards.

## Current Database IDs

```text
Chore Templates: 37fe8e29-9eae-8113-88c0-dda7166e8d3d
Chores:          37fe8e29-9eae-81de-a1bd-db293503adfa
Apartment Zones: 37fe8e29-9eae-814e-8b55-d7fd052bd120
Recipes:         37fe8e29-9eae-8192-b4d0-c842a8d6e5a9
Meal Plan:       37fe8e29-9eae-816e-ae08-e2ecf42453d3
Shopping List:   37fe8e29-9eae-819e-a1e8-e4a33b5121a2
People:          37fe8e29-9eae-819c-98be-f20d83340774
Interactions:    37fe8e29-9eae-817a-b325-f3a28edcc597
Running Log:     37fe8e29-9eae-810f-b650-eec94ba5d8e6
Learning Log:    37fe8e29-9eae-816d-a682-e5ecf84db554
Events & Trips:  37fe8e29-9eae-8113-9cc4-c88edca64657
Weekly Review:   37fe8e29-9eae-8147-a043-fe457f112456
Travel:          380e8e29-9eae-8119-a19e-f9f743f62bff
Ingredients:     38ce8e29-9eae-8137-80c4-cedbdf6943c7
Recipe Ingredients: 38ce8e29-9eae-8131-ba98-de6b87d9f934
Recipe Suggestions: 38ce8e29-9eae-81bc-89f9-c81ec968797d
```

If the to-do hub has been created, add its ID here:

```text
To-Dos:          37fe8e29-9eae-815a-9bb1-ef0e273ff652
```

## Notion API Basics

Use the Notion REST API with:

```text
Authorization: Bearer <NOTION_TOKEN>
Notion-Version: 2022-06-28
Content-Type: application/json
```

Common endpoints:

```text
POST  https://api.notion.com/v1/pages
PATCH https://api.notion.com/v1/pages/{page_id}
POST  https://api.notion.com/v1/databases/{database_id}/query
PATCH https://api.notion.com/v1/databases/{database_id}
```

Use `POST /v1/pages` to create database rows by setting:

```json
{
  "parent": { "database_id": "DATABASE_ID" },
  "properties": {}
}
```

## Database Schemas

### Chore Templates

- `Name` title
- `Zone` select
- `Cadence` select: Daily, Weekly, Biweekly, Monthly, Quarterly
- `Preferred Day` select: Sun, Mon, Tue, Wed, Thu, Fri, Sat
- `Day of Month` number
- `Flex Days` number
- `Estimate Minutes` number
- `Active` checkbox
- `Notes` rich text

### Chores

- `Name` title
- `Date` date
- `Done` checkbox
- `Done Date` date
- `Template` rich text
- `Zone` select
- `Cadence` select
- `Estimate Minutes` number
- `Status` select: Not started, Done, Skipped, Missed, Not needed
- `Reminder Policy` select: Chore reminder, No reminder
- `Notes` rich text

### Apartment Zones

- `Name` title
- `Type` select: Room, Surface, Admin, Storage
- `Weekly Weight` number
- `Notes` rich text

### Recipes

- `Name` title
- `Status` select: To Process, Ready, Cook Soon, Archived
- `Cuisine` multi-select
- `Servings` number
- `Calories` number
- `Protein` number
- `Ingredients` rich text
- `Instructions` rich text
- `Source URL` URL
- `Raw Recipe Notes` rich text
- `Active` checkbox

### Meal Plan

- `Name` title
- `Date` date
- `Slot` select: Breakfast, Lunch, Dinner, Snack
- `Recipe` rich text
- `Recipe Link` relation to Recipes
- `Type` select: Cook, Leftover, Quick, Eat Out
- `Notes` rich text

### Shopping List

- `Item` title
- `Category` select
- `Quantity` rich text
- `Needed For` rich text
- `Purchased` checkbox

### People

- `Name` title
- `Tier` select
- `Birthday` date
- `Cadence Days` number
- `Last Contact` date
- `Notes` rich text

### Interactions

- `Name` title
- `Date` date
- `People` rich text
- `Type` select: Text, Call, Meal, Hangout, Work, Other
- `Notes` rich text

### Running Log

- `Name` title
- `Date` date
- `Planned Miles` number
- `Actual Miles` number
- `Pace` rich text
- `Notes` rich text

### Learning Log

- `Name` title
- `Date` date
- `Topic` select
- `Hours` number
- `Notes` rich text

### Events & Trips

- `Name` title
- `Date` date
- `End Date` date
- `Calendar Block` date range for Notion Calendar display
- `Calendar Status` select: Draft, Tentative, Confirmed, Needs Review, Canceled
- `Trip Key` rich text
- `Trip Status` select: Planned, Active, Completed, Canceled
- `Category` select
- `Type` select: Event, Trip, Appointment, Birthday
- `Food Included` checkbox
- `Food Plan` select: Food provided, Eat out, Bring food, Snack only, No food, Decide later
- `Meal Slot` select: Breakfast, Lunch, Dinner, Snack
- `Food Notes` rich text
- `Notes` rich text

### Ingredients

- `Name` title
- `Category` select

### Recipe Ingredients

- `Name` title
- `Recipe` relation to Recipes
- `Ingredient` relation to Ingredients
- `Raw Amount` rich text
- `Required` checkbox

### Recipe Suggestions

- `Suggestion` title
- `Source Recipe` relation to Recipes
- `Suggested Recipe` relation to Recipes
- `Score` number
- `Shared Ingredients` rich text

### Travel

Canonical travel database. Use this for both trip envelopes and flight segments. Do not create travel rows in Events & Trips.

- `Name` title
- `Kind` select: Trip, Flight, Hotel, Car, Train, Other
- `Status` select: Confirmed, Needs Review, Canceled
- `Start` date
- `End` date range for Notion Calendar display
- `Calendar Block` date range for Notion Calendar display
- `Calendar Category` select: Travel
- `Parent Trip` relation to Travel
- `Trip Key` rich text
- `Segment Role` select: Trip, Outbound, Return, Connection, Other
- `Provider` rich text
- `Confirmation Code` rich text
- `Flight Number` rich text
- `From` rich text
- `To` rich text
- `Location` rich text
- `Address` rich text
- `Source Message ID` rich text
- `Source Subject` rich text
- `Unique Key` rich text
- `Notes` rich text

### Weekly Review

- `Name` title
- `Week Start` date
- `Wins` rich text
- `Missed Chores` rich text
- `Next Week Focus` rich text

### To-Dos

Central action layer for Sheet of Life. Use this instead of trying to make one calendar do all task behavior.

- `Task` title
- `Status` select: Inbox, Next, Scheduled, Waiting, Done, Cancelled
- `Priority` select: High, Medium, Low
- `Area` select: Home, Meals, Shopping, People, Running, Learning, Events, Review, Admin
- `Source` select: Chores, Chore Templates, Apartment Zones, Recipes, Meal Plan, Shopping List, People, Interactions, Running Log, Learning Log, Events & Trips, Weekly Review, Ad hoc
- `Due` date
- `Do Date` date
- `Effort Minutes` number
- `Done` checkbox
- `Notes` rich text
- `Chore` relation to Chores
- `Chore Template` relation to Chore Templates
- `Zone` relation to Apartment Zones
- `Recipe` relation to Recipes
- `Meal` relation to Meal Plan
- `Shopping Item` relation to Shopping List
- `Person` relation to People
- `Interaction` relation to Interactions
- `Run` relation to Running Log
- `Learning` relation to Learning Log
- `Event` relation to Events & Trips
- `Review` relation to Weekly Review

## Recommended Update Workflow

1. Parse the user's requested change into specific records or schema updates.
2. Identify the target database by name and ID.
3. Query first if the request may update an existing record.
4. For workflow or usability requests, update `Sheet of Life Command Center` or one of its component pages with `notion_refine_command_center.ps1` or targeted Notion API changes instead of making a new dashboard page.
5. Verify the Command Center with `notion_verify_command_center.ps1`.

## Calendar Harmony Rules

- Reminders are allowed for chores only.
- Events, travel, meals, runs, and other life blocks should be categorized and quiet by default.
- Timed calendar items should use a single Notion date property with both `start` and `end`.
- Events & Trips is for non-travel events only. Do not use it for trip envelopes.
- For `Travel`, use `Calendar Block` for Notion Calendar display; `Start` and `End` preserve parsed source timing.
- Travel-agent automation should create flight details only unless the user explicitly enables non-flight travel parsing.
- A multi-day trip should be one `Travel` row with `Kind = Trip`, a stable `Trip Key`, and a `Calendar Block` covering the full trip span.
- Flight rows in `Travel` should link to their parent trip through `Parent Trip`, share the same `Trip Key`, and use `Segment Role` for outbound/return/context.

After applying changes:

- Create or patch only the relevant records.
- Do not duplicate obvious existing records unless the user asks for a new instance.
- Report what changed with record names and target databases.
- For Home or meal-planning changes, run the verifier when possible.

## Useful Property JSON Shapes

Title:

```json
{ "title": [{ "type": "text", "text": { "content": "Text here" } }] }
```

Rich text:

```json
{ "rich_text": [{ "type": "text", "text": { "content": "Text here" } }] }
```

Select:

```json
{ "select": { "name": "Weekly" } }
```

Multi-select:

```json
{ "multi_select": [{ "name": "Mexican" }, { "name": "High Protein" }] }
```

Number:

```json
{ "number": 30 }
```

Checkbox:

```json
{ "checkbox": true }
```

Date:

```json
{ "date": { "start": "2026-06-14" } }
```

Date range:

```json
{ "date": { "start": "2026-06-14", "end": "2026-06-16" } }
```

## Example Requests

Add a chore instance:

```text
Add a Chores record:
Name: Clean bathroom
Date: 2026-06-20
Done: false
Template: Clean bathroom
Zone: Bathroom
Cadence: Weekly
Estimate Minutes: 35
Status: Not started
Notes: Weekly bathroom reset.
```

Add a recipe:

```text
Add a Recipes record:
Name: Turkey taco bowls
Status: Ready
Cuisine: Mexican, Meal prep
Servings: 4
Calories: 520
Protein: 42
Ingredients: ground turkey, rice, beans, salsa, lettuce
Instructions: Cook turkey, season, assemble bowls.
Active: true
```

Recipe workflow:

- Put rough recipe captures in Recipes with `Status = To Process` and preserve source text in `Raw Recipe Notes`.
- When ingredients and instructions are cleaned up, set `Status = Ready`.
- Add linked rows in `Recipe Ingredients` for recommendation-style ingredient overlap.
- Use `Cook Soon` only for recipes the user wants surfaced in the Command Center food and recipe components.

Add a meal plan entry:

```text
Add a Meal Plan record:
Name: Turkey taco bowls dinner
Date: 2026-06-17
Slot: Dinner
Recipe: Turkey taco bowls
Recipe Link: link the Turkey taco bowls recipe row when possible
Type: Cook
Notes: Make enough for leftovers.
```

Meal-planning workflow:

- Use Meal Plan for the actual calendar surface.
- Use `Type = Leftover`, `Quick`, or `Eat Out` when the user is not cooking.
- Link `Recipe Link` when the plan uses a real recipe; leave it empty for leftovers, trivia food, eating out, or loose plans.
- Use Events & Trips food fields for events that include food, then decide whether Meal Plan needs a related meal row.

Add a task mapped to a Sheet of Life area:

```text
Add a To-Dos record:
Task: Text Alex about weekend plans
Status: Next
Priority: Medium
Area: People
Source: People
Due: 2026-06-15
Do Date: 2026-06-15
Effort Minutes: 5
Done: false
Notes: Attach the person record in Notion if available.
```

## Prompt Template for Future ChatGPT

Paste this at the top of a new chat when you want another local agent to update Sheet of Life:

```text
You are helping update my Sheet of Life OS in Notion. Use the local guide at:
C:\Users\Clark\OneDrive\Documents\Sheet of Life\CHATGPT_NOTION_UPDATE_GUIDE.md

Do not ask me to paste the Notion token. Read NOTION_TOKEN from local environment or .env. Use the Notion REST API. Preserve the existing setup unless I explicitly request a schema change. Before destructive changes, ask for confirmation.

The single daily starting surface is Sheet of Life Command Center. Do not create a new dashboard by default; improve the Command Center or one of its component pages.

My requested update:
<write the update here>
```

## Notes for Local Codex Agents

There is an existing builder script:

```text
C:\Users\Clark\OneDrive\Documents\Sheet of Life\notion_sheet_of_life_builder.ps1
```

It creates the initial structure and seed data. Do not rerun it unless the user wants another fresh prototype, because it creates a new set of pages and databases.

The current task-list optimization is handled by:

```text
C:\Users\Clark\OneDrive\Documents\Sheet of Life\notion_create_todo_hub.ps1
```

Run it once to create a central To-Dos database with relations to the existing Sheet of Life databases. Use `-DryRun` first, then run with `-SeedStarterTasks` if starter task rows are desired.

The current daily-use Home surface is handled by:

```text
C:\Users\Clark\OneDrive\Documents\Sheet of Life\notion_start_here_builder.ps1
```

Use this for normal UX/layout changes to the working surface:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_start_here_builder.ps1 -ArchiveExistingChildren
```

Then verify:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_verify_home.ps1
```

For day-to-day updates, write a small targeted script or use direct Notion API calls against the database IDs in this guide. For workflow and usability updates, prefer improving the existing Home launcher or its four work areas. Manual final polish in the Notion UI may still be needed for sidebar order, favoriting, compact density, and hiding low-signal properties.
