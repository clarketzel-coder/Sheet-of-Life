# Sheet of Life

Local scripts and artifacts for the Sheet of Life personal operating system prototype.

## What is here

- `notion_*.ps1` - Notion setup and update helpers for the Sheet of Life workspace.
- `sol_pomodoro_*` - local Pomodoro UI/server and Notion logging helpers.
- `sol_sync_flights_from_gmail.ps1` - Gmail-to-Notion travel sync with one row per flight/reservation segment.
- `*_README.md` and `*_GUIDE.md` - operating notes for each automation area.

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_sync_flights_from_gmail.ps1 -CheckNotion
```

Run the flight sync in dry-run mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_sync_flights_from_gmail.ps1
```
