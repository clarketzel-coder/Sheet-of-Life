# Notion Canonical Surfaces

This file defines which Notion pages are daily-use surfaces and which are support infrastructure.

## Primary Surface

### `Sheet of Life Command Center`

This is the intended primary Sheet of Life dashboard surface.

Use it for component-style dashboards inspired by the original HTML tabs:

- visual summary signals
- a few current working rows
- click-throughs to deeper views
- `Deep Dive / Edit Tables` links for hard database editing

Builder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_refine_command_center.ps1
```

Verifier:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_verify_command_center.ps1
```

## Root + Infrastructure

The workspace root is `Sheet of Life`. It should stay short and point to:

- `Sheet of Life Command Center` for daily use
- `Sheet of Life Infrastructure` for source databases and support blocks

The former `Sheet of Life OS - Prototype` page has been renamed to `Sheet of Life Infrastructure` because it owns the live source databases and the current Command Center. Do not archive it unless those children have been intentionally moved or rebuilt elsewhere.

Archived legacy surfaces:

- `00 - Sheet of Life Home`
- `Sheet of Life Mobile Home`
- `Today Desk`
- `Food Planner`
- `Capture Pad`
- `Weekly Reset`

Do not create new dashboard pages unless the user explicitly asks for a separate surface. Prefer refining Command Center components.

## Component Pattern

Each Command Center component should have:

- a summary/signal area
- one or more focused working views
- a `Deep Dive / Edit Tables` area linking to the underlying databases

Current test components:

- `Food + Calendar`
- `Home / Chores`

## Backend Databases

These are source data, not daily destinations:

- To-Dos
- Recipes
- Meal Plan
- Events & Trips
- Shopping List
- People
- Chores
- Travel
- Ingredients
- Recipe Ingredients
- Recipe Suggestions
- Learning Log

Expose them through filtered linked views inside the relevant component when they answer a direct working question. Keep raw database editing behind deep-dive links.

## Learning Tracking Pattern

Learning should not depend on the Pomodoro timer being available. Treat the Learning Log as the source of truth and the timer as one capture path.

Recommended Learning Log fields:

- `Topic`
- `Date`
- `Hours`
- `Outcome`
- `Next Step`
- `Source`
- `Notes`

Use `Source = Pomodoro` for timer sessions, `Source = Manual` for direct command-line captures, and `Source = Daily Update` for end-of-day catch-up entries.

## Legacy Builders

The following scripts are retained for history or support, but should not be treated as the main current user experience:

- `notion_mobile_home_builder.ps1`
- `notion_start_here_builder.ps1`

Running them can recreate competing surfaces. Use `notion_refine_command_center.ps1` for normal dashboard component updates.

## Cleanup

Workspace cleanup is repeatable through:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_cleanup_workspace.ps1
```

The script defaults to dry run. Add `-Execute` to archive known legacy surfaces and the old duplicate `SoL to-do list` database.
