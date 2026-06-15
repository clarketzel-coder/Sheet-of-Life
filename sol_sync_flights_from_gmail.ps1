param(
    [switch]$Apply,
    [switch]$CheckNotion,
    [int]$LookbackDays = 45,
    [int]$MaxMessages = 50,
    [string]$GmailQuery = "",
    [string]$EventsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$NotionVersion = "2022-06-28",
    [string]$RedirectUri = "http://127.0.0.1:8788/"
)

$ErrorActionPreference = "Stop"

$GmailScope = "https://www.googleapis.com/auth/gmail.readonly"
$TokenPath = Join-Path -Path $PSScriptRoot -ChildPath ".sol_google_token.json"
$StatePath = Join-Path -Path $PSScriptRoot -ChildPath ".sol_flight_sync_state.json"

function Import-DotEnv {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            return
        }

        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) {
            return
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($name -and -not [Environment]::GetEnvironmentVariable($name, "Process")) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

function Get-EnvValue {
    param([string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, "User") }
    if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, "Machine") }
    return $value
}

function Read-GoogleOAuthClient {
    $clientId = Get-EnvValue -Name "GMAIL_CLIENT_ID"
    $clientSecret = Get-EnvValue -Name "GMAIL_CLIENT_SECRET"

    $clientPath = Join-Path -Path $PSScriptRoot -ChildPath "google_oauth_client.json"
    if ((-not $clientId -or -not $clientSecret) -and (Test-Path -LiteralPath $clientPath)) {
        $client = Get-Content -LiteralPath $clientPath -Raw | ConvertFrom-Json
        $desktop = if ($client.installed) { $client.installed } else { $client.web }
        $clientId = $desktop.client_id
        $clientSecret = $desktop.client_secret
    }

    if (-not $clientId -or -not $clientSecret) {
        throw "Missing Gmail OAuth credentials. Set GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET, or place a Desktop OAuth client file at $clientPath."
    }

    return @{ ClientId = $clientId; ClientSecret = $clientSecret }
}

function ConvertFrom-Base64Url {
    param([string]$Value)

    if (-not $Value) { return "" }
    $padded = $Value.Replace("-", "+").Replace("_", "/")
    switch ($padded.Length % 4) {
        2 { $padded += "==" }
        3 { $padded += "=" }
    }
    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded))
}

function Invoke-GoogleTokenRequest {
    param([hashtable]$Body)

    return Invoke-RestMethod -Method "POST" -Uri "https://oauth2.googleapis.com/token" -Body $Body -ContentType "application/x-www-form-urlencoded"
}

function Receive-LoopbackCode {
    param([string]$ExpectedState)

    $uri = [uri]$RedirectUri
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $uri.Port)
    $listener.Start()
    try {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $buffer = New-Object byte[] 8192
        $read = $stream.Read($buffer, 0, $buffer.Length)
        $request = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
        $firstLine = ($request -split "`r`n")[0]
        $target = ($firstLine -split " ")[1]
        $query = [uri]("http://127.0.0.1$target")
        $params = [System.Web.HttpUtility]::ParseQueryString($query.Query)

        $html = "<html><body><h1>SoL Gmail auth complete</h1><p>You can close this tab.</p></body></html>"
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $headers = "HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n"
        $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
        $stream.Write($headerBytes, 0, $headerBytes.Length)
        $stream.Write($bodyBytes, 0, $bodyBytes.Length)
        $stream.Close()
        $client.Close()

        if ($params["state"] -ne $ExpectedState) {
            throw "OAuth state did not match."
        }
        if ($params["error"]) {
            throw "Google authorization failed: $($params["error"])"
        }
        return $params["code"]
    }
    finally {
        $listener.Stop()
    }
}

function Get-GmailAccessToken {
    $client = Read-GoogleOAuthClient

    if (Test-Path -LiteralPath $TokenPath) {
        $saved = Get-Content -LiteralPath $TokenPath -Raw | ConvertFrom-Json
        $expiresAt = [DateTimeOffset]::Parse($saved.expires_at)
        if ($saved.access_token -and $expiresAt -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
            return $saved.access_token
        }

        if ($saved.refresh_token) {
            $refreshed = Invoke-GoogleTokenRequest -Body @{
                client_id = $client.ClientId
                client_secret = $client.ClientSecret
                refresh_token = $saved.refresh_token
                grant_type = "refresh_token"
            }
            $saved.access_token = $refreshed.access_token
            $saved.expires_at = ([DateTimeOffset]::UtcNow.AddSeconds([int]$refreshed.expires_in)).ToString("o")
            $saved | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $TokenPath -Encoding UTF8
            return $saved.access_token
        }
    }

    Add-Type -AssemblyName System.Web
    $state = [guid]::NewGuid().ToString("N")
    $authUrl = "https://accounts.google.com/o/oauth2/v2/auth?client_id=$([uri]::EscapeDataString($client.ClientId))&redirect_uri=$([uri]::EscapeDataString($RedirectUri))&response_type=code&scope=$([uri]::EscapeDataString($GmailScope))&access_type=offline&prompt=consent&state=$state"

    Write-Host "Opening Google authorization page..."
    Start-Process $authUrl
    $code = Receive-LoopbackCode -ExpectedState $state

    $token = Invoke-GoogleTokenRequest -Body @{
        client_id = $client.ClientId
        client_secret = $client.ClientSecret
        code = $code
        grant_type = "authorization_code"
        redirect_uri = $RedirectUri
    }

    $record = @{
        access_token = $token.access_token
        refresh_token = $token.refresh_token
        expires_at = ([DateTimeOffset]::UtcNow.AddSeconds([int]$token.expires_in)).ToString("o")
        scope = $token.scope
        token_type = $token.token_type
    }
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $TokenPath -Encoding UTF8
    return $token.access_token
}

function Invoke-GmailApi {
    param(
        [string]$Path,
        [string]$AccessToken
    )

    $headers = @{ Authorization = "Bearer $AccessToken" }
    return Invoke-RestMethod -Method "GET" -Uri "https://gmail.googleapis.com/gmail/v1$Path" -Headers $headers
}

function Get-MessageHeader {
    param($Message, [string]$Name)

    $header = $Message.payload.headers | Where-Object { $_.name -ieq $Name } | Select-Object -First 1
    if ($header) { return $header.value }
    return ""
}

function Get-MessageParts {
    param($Part)

    $parts = @($Part)
    if ($Part.parts) {
        foreach ($child in $Part.parts) {
            $parts += Get-MessageParts -Part $child
        }
    }
    return $parts
}

function Get-PlainBody {
    param($Message)

    $parts = Get-MessageParts -Part $Message.payload
    $plain = $parts | Where-Object { $_.mimeType -eq "text/plain" -and $_.body.data } | Select-Object -First 1
    if ($plain) {
        return ConvertFrom-Base64Url -Value $plain.body.data
    }
    if ($Message.payload.body.data) {
        return ConvertFrom-Base64Url -Value $Message.payload.body.data
    }
    return $Message.snippet
}

function Get-IcsAttachments {
    param($Message, [string]$AccessToken)

    $attachments = @()
    $parts = Get-MessageParts -Part $Message.payload
    foreach ($part in $parts) {
        if ($part.filename -and $part.filename.ToLowerInvariant().EndsWith(".ics") -and $part.body.attachmentId) {
            $attachment = Invoke-GmailApi -AccessToken $AccessToken -Path "/users/me/messages/$($Message.id)/attachments/$($part.body.attachmentId)"
            $attachments += ConvertFrom-Base64Url -Value $attachment.data
        }
    }
    return $attachments
}

function Get-IcsField {
    param([string[]]$Lines, [string]$Name)

    $line = $Lines | Where-Object { $_ -match "^$Name(;[^:]*)?:" } | Select-Object -First 1
    if (-not $line) { return "" }
    return ($line -split ":", 2)[1].Trim()
}

function Convert-IcsDate {
    param([string]$Value)

    if (-not $Value) { return "" }
    $clean = $Value.Trim()

    if ($clean -match "^\d{8}$") {
        return [DateTime]::ParseExact($clean, "yyyyMMdd", $null).ToString("yyyy-MM-dd")
    }
    if ($clean.EndsWith("Z")) {
        return [DateTimeOffset]::ParseExact($clean, "yyyyMMdd'T'HHmmss'Z'", $null).UtcDateTime.ToString("o")
    }
    if ($clean -match "^\d{8}T\d{6}$") {
        return [DateTime]::ParseExact($clean, "yyyyMMdd'T'HHmmss", $null).ToString("s")
    }
    return $clean
}

function ConvertFrom-Ics {
    param(
        [string]$Ics,
        [string]$MessageId,
        [string]$Subject,
        [string]$From
    )

    $unfolded = [regex]::Replace($Ics, "(\r?\n)[ \t]", "")
    $events = @()
    foreach ($match in [regex]::Matches($unfolded, "BEGIN:VEVENT(.*?)END:VEVENT", "Singleline")) {
        $lines = ($match.Groups[1].Value -split "\r?\n") | Where-Object { $_ }
        $summary = Get-IcsField -Lines $lines -Name "SUMMARY"
        $start = Convert-IcsDate -Value (Get-IcsField -Lines $lines -Name "DTSTART")
        $end = Convert-IcsDate -Value (Get-IcsField -Lines $lines -Name "DTEND")
        $location = Get-IcsField -Lines $lines -Name "LOCATION"
        $description = Get-IcsField -Lines $lines -Name "DESCRIPTION"

        if ($summary -and $start) {
            $events += @{
                Name = $summary
                Start = $start
                End = $end
                Notes = "Source: Gmail flight sync`nGmail Message ID: $MessageId`nFrom: $From`nSubject: $Subject`nLocation: $location`n$description"
                Structured = $true
            }
        }
    }
    return $events
}

function ConvertFrom-FlightEmailFallback {
    param($Message)

    $subject = Get-MessageHeader -Message $Message -Name "Subject"
    $from = Get-MessageHeader -Message $Message -Name "From"
    $date = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Message.internalDate).LocalDateTime.ToString("yyyy-MM-dd")
    $body = Get-PlainBody -Message $Message
    $flightMatches = [regex]::Matches("$subject`n$body", "\b(DL|Delta|UA|United|AA|American)\s*#?\s*(\d{1,4})\b", "IgnoreCase")
    $flights = @($flightMatches | ForEach-Object { "$($_.Groups[1].Value) $($_.Groups[2].Value)" } | Select-Object -Unique)
    $name = if ($flights.Count -gt 0) { "Flight email: $($flights -join ', ')" } else { "Flight email: $subject" }

    return @{
        Name = $name
        Start = $date
        End = ""
        Notes = "Needs review: no .ics attachment was found.`nSource: Gmail flight sync`nGmail Message ID: $($Message.id)`nFrom: $from`nSubject: $subject`nSnippet: $($Message.snippet)"
        Structured = $false
    }
}

function Load-State {
    if (Test-Path -LiteralPath $StatePath) {
        return Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{ importedMessageIds = @() }
}

function Save-State {
    param($State)
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function New-RichText {
    param([string]$Text)
    if (-not $Text) { return @() }

    $chunks = @()
    $maxChunkLength = 2000
    for ($offset = 0; $offset -lt $Text.Length; $offset += $maxChunkLength) {
        $length = [Math]::Min($maxChunkLength, $Text.Length - $offset)
        $chunks += @{ type = "text"; text = @{ content = $Text.Substring($offset, $length) } }
    }
    return ,$chunks
}

function TitleValue { param([string]$Value) return @{ title = (New-RichText -Text $Value) } }
function TextValue { param([string]$Value) return @{ rich_text = (New-RichText -Text $Value) } }
function SelectValue { param([string]$Value) return @{ select = @{ name = $Value } } }
function DateValue {
    param([string]$Value)
    if (-not $Value) { return $null }
    return @{ date = @{ start = $Value } }
}

function Invoke-NotionApi {
    param(
        [string]$Method,
        [string]$Path,
        [string]$NotionToken,
        $Body = $null
    )

    $headers = @{
        Authorization = "Bearer $NotionToken"
        "Notion-Version" = $NotionVersion
        "Content-Type" = "application/json"
    }

    $parameters = @{
        Method = $Method
        Uri = "https://api.notion.com/v1$Path"
        Headers = $headers
    }

    if ($null -ne $Body) {
        $parameters["Body"] = ($Body | ConvertTo-Json -Depth 30)
    }

    return Invoke-RestMethod @parameters
}

function Test-NotionEventsDatabase {
    param([string]$NotionToken)

    $database = Invoke-NotionApi -Method "GET" -Path "/databases/$EventsDatabaseId" -NotionToken $NotionToken
    $requiredProperties = @("Name", "Date", "End Date", "Category", "Type", "Notes")
    $missingProperties = @($requiredProperties | Where-Object { -not $database.properties.PSObject.Properties.Name.Contains($_) })

    if ($missingProperties.Count -gt 0) {
        throw "Events & Trips database is reachable, but missing expected propert$(if ($missingProperties.Count -eq 1) { 'y' } else { 'ies' }): $($missingProperties -join ', ')"
    }

    Write-Host "Notion preflight OK: Events & Trips database is reachable and has the expected travel fields."
}

function Add-EventTrip {
    param($Trip, [string]$NotionToken)

    $properties = @{
        Name = TitleValue $Trip.Name
        Date = DateValue $Trip.Start
        Category = SelectValue "Flight"
        Type = SelectValue "Trip"
        Notes = TextValue $Trip.Notes
    }

    if ($Trip.End) {
        $properties["End Date"] = DateValue $Trip.End
    }

    $body = @{
        parent = @{ database_id = $EventsDatabaseId }
        properties = $properties
    }

    return Invoke-NotionApi -Method "POST" -Path "/pages" -NotionToken $NotionToken -Body $body
}

Import-DotEnv -Path (Join-Path -Path $PSScriptRoot -ChildPath ".env")
Add-Type -AssemblyName System.Web

$notionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (($Apply -or $CheckNotion) -and -not $notionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

if ($CheckNotion) {
    Test-NotionEventsDatabase -NotionToken $notionToken
    if (-not $Apply) {
        return
    }
}

$accessToken = Get-GmailAccessToken
$state = Load-State
$imported = @($state.importedMessageIds)
if (-not $GmailQuery) {
    $GmailQuery = "newer_than:${LookbackDays}d {from:delta.com from:united.com from:aa.com from:americanairlines.com subject:Delta subject:United subject:`"American Airlines`" subject:flight subject:itinerary subject:confirmation}"
}
$query = $GmailQuery
$encodedQuery = [uri]::EscapeDataString($query)
$messageList = Invoke-GmailApi -AccessToken $accessToken -Path "/users/me/messages?q=$encodedQuery&maxResults=$MaxMessages"
$messages = @($messageList.messages)
$candidates = @()

foreach ($item in $messages) {
    if ($imported -contains $item.id) {
        continue
    }

    $message = Invoke-GmailApi -AccessToken $accessToken -Path "/users/me/messages/$($item.id)?format=full"
    $subject = Get-MessageHeader -Message $message -Name "Subject"
    $from = Get-MessageHeader -Message $message -Name "From"
    $icsAttachments = Get-IcsAttachments -Message $message -AccessToken $accessToken
    $trips = @()

    foreach ($ics in $icsAttachments) {
        $trips += ConvertFrom-Ics -Ics $ics -MessageId $message.id -Subject $subject -From $from
    }

    if ($trips.Count -eq 0) {
        $trips += ConvertFrom-FlightEmailFallback -Message $message
    }

    foreach ($trip in $trips) {
        $trip["MessageId"] = $message.id
        $candidates += $trip
    }
}

if ($candidates.Count -eq 0) {
    Write-Host "No new flight email candidates found."
    return
}

if (-not $Apply) {
    Write-Host "Dry run. Re-run with -Apply to write to Notion and update local state."
    $candidates | Select-Object Name, Start, End, Structured, MessageId | Format-Table -AutoSize
    return
}

$writtenMessageIds = @()
foreach ($candidate in $candidates) {
    [void](Add-EventTrip -Trip $candidate -NotionToken $notionToken)
    $writtenMessageIds += $candidate.MessageId
    Write-Host "Added: $($candidate.Name)"
}

$state.importedMessageIds = @($imported + $writtenMessageIds | Select-Object -Unique)
$state.lastRun = (Get-Date).ToString("o")
Save-State -State $state
Write-Host "Imported $($candidates.Count) trip event(s)."
