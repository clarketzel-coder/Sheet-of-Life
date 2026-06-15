# SoL Pomodoro

A local Pomodoro timer that logs completed focus sessions to the Sheet of Life Notion Learning Log.

## Start

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_pomodoro_server.ps1
```

Then open:

```text
http://127.0.0.1:8765/
```

## Corner Window

Open a small app-style window in the bottom-right corner:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_pomodoro_corner.ps1
```

Other corners:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_pomodoro_corner.ps1 -Corner TopRight
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_pomodoro_corner.ps1 -Corner TopLeft
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_pomodoro_corner.ps1 -Corner BottomLeft
```

## Notion Target

The server writes to the existing Learning Log database:

```text
37fe8e29-9eae-816d-a682-e5ecf84db554
```

It uses the current schema:

- `Name`
- `Date`
- `Topic`
- `Hours`
- `Notes`

## Add Notion Launcher

Append an `Open SoL Pomodoro` launcher link to the Sheet of Life prototype page:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\notion_add_pomodoro_launcher.ps1
```

## Token Handling

The browser UI never sees the Notion token. The PowerShell server reads `NOTION_TOKEN` from the process, user, or machine environment, or from a local `.env` file in this folder.

## Behavior

- Focus sessions are logged to Notion when they complete.
- Short and long breaks are not logged.
- `Log Now` records elapsed focus time before the timer completes.
- Settings are saved in browser local storage.
- Categories are loaded from the Learning Log `Topic` select property.
- Type a new category into `New category` and press `Use` or `Enter` to log the current session to it.
- New categories are created in Notion when the first session is logged to that category.
