# Sheet of Life Notion Build Plan

## Purpose

This project is an experiment to recreate the core ideas of **Sheet of Life** inside Notion: a personal operating system for chores, apartment maintenance, meals, recipes, shopping, relationships, events, running, learning, and weekly review.

The current direction is to use Notion as the structured backend and interface, while preserving the most important parts of Sheet of Life:

- calendar-first planning
- recurring chores and apartment routines
- recipes and meal planning
- shopping support
- flexible personal logs
- database-mapped to-dos
- lightweight weekly review

## Notion Access

Parent page shared for the experiment:

```text
37fe8e299eae80e49aafc13cd44cc181
```

URL:

```text
https://app.notion.com/p/37fe8e299eae80e49aafc13cd44cc181?v=37fe8e299eae8044909b000ce3a3339d
```

The user created a Notion API token and connected it to the relevant workspace/pages.

Do not paste or print the token in chat. Prefer one of these safe local options:

```powershell
[Environment]::SetEnvironmentVariable("NOTION_TOKEN", "secret_xxx", "User")
[Environment]::SetEnvironmentVariable("NOTION_PARENT_PAGE_ID", "37fe8e299eae80e49aafc13cd44cc181", "User")
```

Alternatively, use a local `.env` file that is ignored by git:

```text
NOTION_TOKEN=secret_xxx
NOTION_PARENT_PAGE_ID=37fe8e299eae80e49aafc13cd44cc181
```

## Important Constraint

The built-in Notion connector available in Codex currently appears read/search only. It exposed fetch/search tools, but not create/update tools.

For actual building, use the Notion REST API from a local script:

- `POST https://api.notion.com/v1/pages`
- `POST https://api.notion.com/v1/databases`
- optionally `PATCH https://api.notion.com/v1/databases/{database_id}` for relation properties later

Headers:

```text
Authorization: Bearer <token>
Notion-Version: 2022-06-28
Content-Type: application/json
```

Network access may require shell escalation in Codex.

## Proposed Structure

Create a top-level child page under the shared parent:

```text
Sheet of Life OS - Prototype
```

Then create the following databases under that page.

## Databases

### Chore Templates

Source of truth for recurring chores.

Properties:

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

Actual scheduled chore instances. This is the calendar-friendly database.

Properties:

- `Name` title
- `Date` date
- `Done` checkbox
- `Done Date` date
- `Template` rich text for first pass; relation can be added later
- `Zone` select
- `Cadence` select
- `Estimate Minutes` number
- `Status` select: Scheduled, Moved, Done, Skipped
- `Notes` rich text

### Apartment Zones

Maintains the apartment model.

Properties:

- `Name` title
- `Type` select: Room, Surface, Admin, Storage
- `Weekly Weight` number
- `Notes` rich text

### Recipes

Preserve recipes as much as possible. This is the exception to the “start fresh” approach.

Properties:

- `Name` title
- `Cuisine` multi-select
- `Servings` number
- `Calories` number
- `Protein` number
- `Ingredients` rich text
- `Instructions` rich text
- `Active` checkbox

### Meal Plan

Calendar of planned meals.

Properties:

- `Name` title
- `Date` date
- `Slot` select: Breakfast, Lunch, Dinner, Snack
- `Recipe` rich text for first pass; relation can be added later
- `Type` select: Cook, Leftover, Quick, Eat Out
- `Notes` rich text

### Shopping List

Basic list for groceries and home items.

Properties:

- `Item` title
- `Category` select
- `Quantity` rich text
- `Needed For` rich text
- `Purchased` checkbox

### People

Relationship tracking.

Properties:

- `Name` title
- `Tier` select
- `Birthday` date
- `Cadence Days` number
- `Last Contact` date
- `Notes` rich text

### Interactions

Contact and social log.

Properties:

- `Name` title
- `Date` date
- `People` rich text for first pass; relation can be added later
- `Type` select: Text, Call, Meal, Hangout, Work, Other
- `Notes` rich text

### Running Log

Fitness tracking.

Properties:

- `Name` title
- `Date` date
- `Planned Miles` number
- `Actual Miles` number
- `Pace` rich text
- `Notes` rich text

### Learning Log

Learning and personal development.

Properties:

- `Name` title
- `Date` date
- `Topic` select
- `Hours` number
- `Notes` rich text

### Events & Trips

Calendar context, travel, appointments, and notable events.

Properties:

- `Name` title
- `Date` date
- `End Date` date
- `Category` select
- `Type` select: Event, Trip, Appointment, Birthday
- `Notes` rich text

### Weekly Review

Reflection and maintenance loop.

Properties:

- `Name` title
- `Week Start` date
- `Wins` rich text
- `Missed Chores` rich text
- `Next Week Focus` rich text

### To-Dos

Central action layer for Sheet of Life. This should be preferred over using the calendar as the primary to-do list, because tasks often come from several SoL databases at once.

Properties:

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
- Relation properties to relevant SoL databases:
  - `Chore`
  - `Chore Template`
  - `Zone`
  - `Recipe`
  - `Meal`
  - `Shopping Item`
  - `Person`
  - `Interaction`
  - `Run`
  - `Learning`
  - `Event`
  - `Review`

## Starter Data

Seed these apartment zones:

- Kitchen
- Bathroom
- Bedroom
- Floors
- Living
- Admin

Seed these chore templates:

- Take out trash & recycling
- Kitchen reset & wipe counters
- Clean bathroom
- Change bed sheets
- Vacuum main areas
- Mop floors
- Clean inside fridge
- Microwave & stovetop detail
- Dust baseboards & fans
- Deep clean behind appliances

Suggested routine structure:

- Daily: quick kitchen reset, dishes, trash check, 5-minute clutter reset
- Weekly: bathroom, floors, laundry/sheets, counters, fridge check, trash/recycling
- Monthly: fridge detail, appliance detail, dusting, baseboards, cabinets, deeper bathroom work
- Quarterly: pantry audit, closet reset, behind/under furniture, filter checks if relevant

## Known Notion UI Limitations

The Notion API can create pages, databases, properties, and records. It cannot fully configure every Notion UI view exactly like a human-created Notion calendar/dashboard.

The practical approach:

1. Create clean databases and starter records with the API.
2. Add or tune Notion views manually if needed:
   - Chores calendar by `Date`
   - Meal Plan calendar by `Date`
   - Events & Trips calendar by `Date`
   - To-Dos board grouped by `Status`
   - To-Dos table filtered to `Done` is unchecked
   - To-Dos calendar by `Do Date` or `Due`
   - Chore Templates table grouped by `Zone` or `Cadence`
3. Add relations and rollups in a second pass once the core databases exist.

## Next Build Steps

1. Create a local builder script:

```text
notion_sheet_of_life_builder.ps1
```

2. Script should:

- read `NOTION_TOKEN` from process/user env or `.env`
- read parent page ID from parameter/env/default
- normalize the Notion page ID
- create `Sheet of Life OS - Prototype`
- create all databases listed above
- seed starter apartment zones and chore templates
- avoid printing the token
- fail clearly if token or parent page ID is missing

3. Add `.env` to `.gitignore` if not already ignored.

4. Run a dry run first.

5. Run the builder against Notion API.

6. Verify created structure in Notion.

7. Create the task hub:

```powershell
.\notion_create_todo_hub.ps1 -DryRun -SeedStarterTasks
.\notion_create_todo_hub.ps1 -SeedStarterTasks
```

8. Copy the created To-Dos database ID into `CHATGPT_NOTION_UPDATE_GUIDE.md`.

## Previous Attempts

The read-only Notion connector could not fetch the shared page directly and returned an object-not-found style error. That likely means the connector was scoped differently than the new API token.

The user later confirmed the Notion connection is working, so the next implementation should use the local API-token path rather than the connector.
