# SoL Flight Sync

Monthly Gmail-to-SoL flight email sync.

## What It Does

- Reads Gmail with the readonly Gmail API scope.
- Searches recent airline/travel emails from Delta, United, American, and flight-related subjects.
- Prefers `.ics` calendar attachments for structured flight/trip times.
- Falls back to a review-needed trip record when no `.ics` attachment is found.
- Adds records to the existing SoL `Events & Trips` database.
- Deduplicates by Gmail message ID in `.sol_flight_sync_state.json`.

## Local Secrets

The following files are ignored by git:

- `google_oauth_client.json`
- `.sol_google_token.json`
- `.sol_flight_sync_state.json`

## Google Setup

Create a Google Cloud OAuth client for a desktop app, then either:

1. Save the downloaded client JSON as `google_oauth_client.json` in this folder, or
2. Set `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET` in the environment or `.env`.

The script requests only:

```text
https://www.googleapis.com/auth/gmail.readonly
```

## First Run

Verify the Notion connection and target database:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_sync_flights_from_gmail.ps1 -CheckNotion
```

Dry run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_sync_flights_from_gmail.ps1
```

Dry run against a Gmail label:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_sync_flights_from_gmail.ps1 -GmailQuery 'label:Travel/Flights newer_than:90d'
```

Write to Notion:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_sync_flights_from_gmail.ps1 -Apply
```

## Schedule Monthly

Register a Windows scheduled task for the first day of each month at 8 PM:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_register_monthly_flight_sync.ps1
```

Use a different day/time:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sol_register_monthly_flight_sync.ps1 -DayOfMonth 7 -Time "21:30"
```
