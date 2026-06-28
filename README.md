# Sheet of Life

Local scripts and artifacts for the Sheet of Life personal operating system prototype.

## What is here

- `scripts/travel/` - Gmail-to-Notion travel agent and optional Windows scheduled-task helper.
- `scripts/notion/` - Notion setup, cleanup, verification, and maintenance scripts.
- `apps/pomodoro/` - local Pomodoro UI/server and Notion logging helpers.
- `docs/travel/` - travel agent setup and operating notes.
- `docs/pomodoro/` - Pomodoro setup and operating notes.
- `docs/notion/` - Sheet of Life Notion build notes, checklists, and surface maps.

The older standalone HTML prototype is intentionally kept local and ignored by git. This repo is focused on the Notion-backed setup and companion automations.

## Local secrets

Secrets are intentionally kept out of git. Use environment variables or a local `.env` file for values such as:

- `NOTION_TOKEN`
- `NOTION_PARENT_PAGE_ID`
- `GMAIL_CLIENT_ID`
- `GMAIL_CLIENT_SECRET`

The `.gitignore` also excludes Gmail OAuth token/state files and downloaded installers.

## Common commands

Verify the Notion travel database:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -CheckNotion
```

Run the flight sync in dry-run mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1
```

Rebuild the primary Command Center component dashboard:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\notion\notion_refine_command_center.ps1
```

Verify the Command Center component dashboard:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\notion\notion_verify_command_center.ps1
```

## Command Center Component Pattern

`Sheet of Life Command Center` is the primary dashboard surface. It should follow the old HTML prototype's tab idea: each area is a dashboard component, not a raw database dump.

Each component should include:

- visual summary signals
- a few current working rows
- click-through working views
- `Deep Dive / Edit Tables` links for raw database editing

Current test components:

- `Food + Calendar`
- `Home / Chores`

The Notion API does not reliably create all newer UI-only controls such as buttons/forms, so the builder uses KPI callouts, filtered linked database views, and direct database links as the stable component pattern.
