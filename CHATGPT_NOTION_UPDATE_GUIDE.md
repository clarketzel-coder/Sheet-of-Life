# ChatGPT Notion Update Guide for Sheet of Life

## Purpose

Use this guide when asking ChatGPT, Codex, or another local agent to update the **Sheet of Life OS - Prototype** in Notion.

The Notion workspace is already set up. Future updates should preserve the current structure unless the user explicitly asks to change it.

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

Prototype page:

```text
37fe8e29-9eae-8159-bd12-d8bcbf34ec0c
```

Prototype page title:

```text
Sheet of Life OS - Prototype
```

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
- `Status` select: Scheduled, Moved, Done, Skipped
- `Notes` rich text

### Apartment Zones

- `Name` title
- `Type` select: Room, Surface, Admin, Storage
- `Weekly Weight` number
- `Notes` rich text

### Recipes

- `Name` title
- `Cuisine` multi-select
- `Servings` number
- `Calories` number
- `Protein` number
- `Ingredients` rich text
- `Instructions` rich text
- `Active` checkbox

### Meal Plan

- `Name` title
- `Date` date
- `Slot` select: Breakfast, Lunch, Dinner, Snack
- `Recipe` rich text
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
- `Category` select
- `Type` select: Event, Trip, Appointment, Birthday
- `Notes` rich text

### Travel

Dedicated travel reservation database. Use this instead of Events & Trips for flights, hotels, rental cars, trains, and other travel segments.

- `Name` title
- `Kind` select: Flight, Hotel, Car, Train, Other
- `Status` select: Confirmed, Needs Review, Canceled
- `Start` date
- `End` date
- `Provider` rich text
- `Confirmation Code` rich text
- `Flight Number` rich text
- `From` rich text
- `To` rich text
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
4. Create or patch only the relevant records.
5. Do not duplicate obvious existing records unless the user asks for a new instance.
6. Report what changed with record names and target databases.

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
Status: Scheduled
Notes: Weekly bathroom reset.
```

Add a recipe:

```text
Add a Recipes record:
Name: Turkey taco bowls
Cuisine: Mexican, Meal prep
Servings: 4
Calories: 520
Protein: 42
Ingredients: ground turkey, rice, beans, salsa, lettuce
Instructions: Cook turkey, season, assemble bowls.
Active: true
```

Add a meal plan entry:

```text
Add a Meal Plan record:
Name: Turkey taco bowls dinner
Date: 2026-06-17
Slot: Dinner
Recipe: Turkey taco bowls
Type: Cook
Notes: Make enough for leftovers.
```

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

For day-to-day updates, write a small targeted script or use direct Notion API calls against the database IDs in this guide.
