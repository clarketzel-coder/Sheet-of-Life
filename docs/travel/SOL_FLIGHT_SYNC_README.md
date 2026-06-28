# SoL Travel Sync

Monthly Gmail-to-SoL travel email sync.

## What It Does

- Reads Gmail with the readonly Gmail API scope.
- Searches recent airline/travel emails from airlines, hotels, and rental car providers.
- Parses American Airlines JSON-LD flight reservations and United itinerary HTML flight blocks.
- Defaults to flights only, matching the current travel-agent scope.
- Optional: pass `-IncludeNonFlightTravel` to parse JSON-LD lodging/rental car reservations and hotel/car review candidates.
- Creates one row per concrete flight segment in the SoL `Travel` database.
- Trip envelopes also belong in `Travel` as `Kind = Trip`; `Events & Trips` should not be used for travel.
- Falls back to a review-needed travel record when no segment parser matches.
- Deduplicates by travel segment key and Gmail message ID in `.sol_flight_sync_state.json`.
- Writes `Calendar Block` as a start/end date range so Notion Calendar can display the flight as a real block.

## Local Secrets

The following files are ignored by git:

- `google_oauth_client.json`
- `.sol_google_token.json`
- `.sol_flight_sync_state.json`

## Google Setup

Create a Google Cloud OAuth client for a desktop app, then either:

1. Save the downloaded client JSON as `google_oauth_client.json` in the repo root, or
2. Set `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET` in the environment or `.env`.

The script requests only:

```text
https://www.googleapis.com/auth/gmail.readonly
```

If you use `-FileProcessedEmail` or `-ArchiveProcessedEmail`, the script requests:

```text
https://www.googleapis.com/auth/gmail.modify
```

That broader scope is needed to apply Gmail labels or remove messages from the Inbox.

## First Run

Verify the Notion connection and target Travel database:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -CheckNotion
```

Dry run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1
```

Review recent travel-like emails without writing to Notion or filing Gmail:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -ReviewTravelEmail
```

Dry run against a Gmail label:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -GmailQuery 'label:Travel/Flights newer_than:90d'
```

Write to Notion:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -Apply
```

Include hotel/car candidates too:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -Apply -IncludeNonFlightTravel
```

Write to Notion, then label the source email with an existing Gmail label:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -Apply -FileProcessedEmail -ProcessedLabelName "Travel"
```

Write to Notion, label the source email, and archive it from the Inbox:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -Apply -FileProcessedEmail -ProcessedLabelName "Travel" -ArchiveProcessedEmail
```

File already-imported source emails from local sync state:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_sync_flights_from_gmail.ps1 -FileImportedEmail -FileProcessedEmail -ProcessedLabelName "Travel/Upcoming" -ArchiveProcessedEmail
```

## Schedule Monthly

Register a Windows scheduled task for the first day of each month at 8 PM:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_register_monthly_flight_sync.ps1
```

Use a different day/time:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\travel\sol_register_monthly_flight_sync.ps1 -DayOfMonth 7 -Time "21:30"
```
