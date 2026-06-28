param(
    [switch]$Apply,
    [switch]$CheckNotion,
    [switch]$ReplayImported,
    [switch]$ReviewTravelEmail,
    [int]$LookbackDays = 45,
    [int]$MaxMessages = 50,
    [string]$GmailQuery = "",
    [string]$EventsDatabaseId = "37fe8e29-9eae-8113-9cc4-c88edca64657",
    [string]$TravelDatabaseId = "380e8e29-9eae-8119-a19e-f9f743f62bff",
    [switch]$IncludeNonFlightTravel,
    [switch]$FileProcessedEmail,
    [switch]$FileImportedEmail,
    [string]$ProcessedLabelName = "Travel",
    [switch]$ArchiveProcessedEmail,
    [string]$NotionVersion = "2022-06-28",
    [string]$RedirectUri = "http://127.0.0.1:8788/"
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$currentPath = Resolve-Path -LiteralPath $PSScriptRoot
while ($currentPath) {
    if (Test-Path -LiteralPath (Join-Path -Path $currentPath -ChildPath ".git")) {
        $RepoRoot = $currentPath.Path
        break
    }
    $parentPath = Split-Path -Path $currentPath -Parent
    if (-not $parentPath -or $parentPath -eq $currentPath.Path) {
        break
    }
    $currentPath = Resolve-Path -LiteralPath $parentPath
}

$GmailReadOnlyScope = "https://www.googleapis.com/auth/gmail.readonly"
$GmailModifyScope = "https://www.googleapis.com/auth/gmail.modify"
$TokenPath = Join-Path -Path $RepoRoot -ChildPath ".sol_google_token.json"
$StatePath = Join-Path -Path $RepoRoot -ChildPath ".sol_flight_sync_state.json"

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

    $clientPath = Join-Path -Path $RepoRoot -ChildPath "google_oauth_client.json"
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

function Get-RequiredGmailScope {
    if ($FileProcessedEmail -or $FileImportedEmail -or $ArchiveProcessedEmail) {
        return $GmailModifyScope
    }
    return $GmailReadOnlyScope
}

function Test-TokenHasScope {
    param($SavedToken, [string]$RequiredScope)

    if (-not $SavedToken.scope) {
        return $false
    }
    $scopes = @("$($SavedToken.scope)" -split "\s+")
    if ($scopes -contains $RequiredScope) {
        return $true
    }
    if ($RequiredScope -eq $GmailReadOnlyScope -and ($scopes -contains $GmailModifyScope)) {
        return $true
    }
    return $false
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
    $requiredScope = Get-RequiredGmailScope

    if (Test-Path -LiteralPath $TokenPath) {
        $saved = Get-Content -LiteralPath $TokenPath -Raw | ConvertFrom-Json
        $savedTokenHasScope = Test-TokenHasScope -SavedToken $saved -RequiredScope $requiredScope
        $expiresAt = [DateTimeOffset]::Parse($saved.expires_at)
        if ($saved.access_token -and $savedTokenHasScope -and $expiresAt -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
            return $saved.access_token
        }

        if ($saved.refresh_token -and $savedTokenHasScope) {
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
    $authUrl = "https://accounts.google.com/o/oauth2/v2/auth?client_id=$([uri]::EscapeDataString($client.ClientId))&redirect_uri=$([uri]::EscapeDataString($RedirectUri))&response_type=code&scope=$([uri]::EscapeDataString($requiredScope))&access_type=offline&prompt=consent&state=$state"

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
    try {
        return Invoke-RestMethod -Method "GET" -Uri "https://gmail.googleapis.com/gmail/v1$Path" -Headers $headers
    }
    catch {
        $details = ""
        if ($_.Exception.Response) {
            $stream = $_.Exception.Response.GetResponseStream()
            if ($stream) {
                $reader = [System.IO.StreamReader]::new($stream)
                $details = $reader.ReadToEnd()
                $reader.Close()
            }
        }

        if ($details) {
            throw "Gmail API request failed: $details"
        }
        throw
    }
}

function Invoke-GmailModifyApi {
    param(
        [string]$Path,
        [string]$AccessToken,
        $Body
    )

    $headers = @{ Authorization = "Bearer $AccessToken"; "Content-Type" = "application/json" }
    $jsonBody = $Body | ConvertTo-Json -Depth 10
    try {
        return Invoke-RestMethod -Method "POST" -Uri "https://gmail.googleapis.com/gmail/v1$Path" -Headers $headers -Body $jsonBody
    }
    catch {
        $details = ""
        if ($_.Exception.Response) {
            $stream = $_.Exception.Response.GetResponseStream()
            if ($stream) {
                $reader = [System.IO.StreamReader]::new($stream)
                $details = $reader.ReadToEnd()
                $reader.Close()
            }
        }

        if ($details) {
            throw "Gmail modify request failed: $details"
        }
        throw
    }
}

function Get-GmailLabelId {
    param([string]$LabelName, [string]$AccessToken)

    if (-not $LabelName) {
        return ""
    }

    $labelList = Invoke-GmailApi -AccessToken $AccessToken -Path "/users/me/labels"
    $label = @($labelList.labels) | Where-Object { $_.name -ieq $LabelName } | Select-Object -First 1
    if (-not $label) {
        throw "Gmail label '$LabelName' was not found. Create that label in Gmail first, or pass a different -ProcessedLabelName."
    }
    return $label.id
}

function Set-GmailProcessedMessage {
    param(
        [string]$MessageId,
        [string]$AccessToken,
        [string]$LabelId
    )

    $addLabelIds = @()
    $removeLabelIds = @()
    if ($FileProcessedEmail -and $LabelId) {
        $addLabelIds += $LabelId
    }
    if ($ArchiveProcessedEmail) {
        $removeLabelIds += "INBOX"
    }

    if ($addLabelIds.Count -eq 0 -and $removeLabelIds.Count -eq 0) {
        return
    }

    [void](Invoke-GmailModifyApi -AccessToken $AccessToken -Path "/users/me/messages/$MessageId/modify" -Body @{
        addLabelIds = $addLabelIds
        removeLabelIds = $removeLabelIds
    })
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

function Get-HtmlBody {
    param($Message)

    $parts = Get-MessageParts -Part $Message.payload
    $html = $parts | Where-Object { $_.mimeType -eq "text/html" -and $_.body.data } | Select-Object -First 1
    if ($html) {
        return ConvertFrom-Base64Url -Value $html.body.data
    }
    return ""
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

function Normalize-FlightNumber {
    param([string]$Value)

    if (-not $Value) { return "" }
    $clean = ($Value -replace "\s+", "").ToUpperInvariant()
    if ($clean -match "^([A-Z]{2})(\d{1,4})$") {
        return "$($Matches[1]) $($Matches[2])"
    }
    return $Value.Trim()
}

function Get-FlightKey {
    param($Item)

    $flight = (Normalize-FlightNumber -Value $Item.FlightNumber) -replace "\s+", ""
    $start = "$($Item.Start)"
    if ($start.Length -ge 16) {
        $start = $start.Substring(0, 16)
    }
    return "flight|$flight|$start|$($Item.From)|$($Item.To)".ToLowerInvariant()
}

function Get-TravelKey {
    param($Item)

    $kind = "$($Item.Kind)".ToLowerInvariant()
    $provider = ("$($Item.Provider)" -replace "\s+", "").ToLowerInvariant()
    $confirmation = ("$($Item.ConfirmationCode)" -replace "\s+", "").ToLowerInvariant()
    $start = "$($Item.Start)"
    if ($start.Length -ge 16) {
        $start = $start.Substring(0, 16)
    }

    if ($confirmation) {
        return "$kind|$provider|$confirmation|$start"
    }
    return "$kind|$provider|$start|$($Item.Location)|$($Item.From)|$($Item.To)".ToLowerInvariant()
}

function New-FlightTravelItem {
    param(
        [string]$FlightNumber,
        [string]$Provider,
        [string]$Start,
        [string]$End,
        [string]$From,
        [string]$To,
        [string]$ConfirmationCode,
        [string]$MessageId,
        [string]$Subject,
        [string]$FromEmail,
        [string]$Notes
    )

    $normalizedFlight = Normalize-FlightNumber -Value $FlightNumber
    $destination = if ($To) { Get-AirportCityName -Airport $To } else { "" }
    $name = if ($destination) { "Flight to $destination ($normalizedFlight)" } else { "$normalizedFlight $From -> $To" }

    $item = @{
        Name = $name
        Kind = "Flight"
        Status = "Confirmed"
        Start = $Start
        End = $End
        Provider = $Provider
        ConfirmationCode = $ConfirmationCode
        FlightNumber = $normalizedFlight
        From = $From
        To = $To
        Location = ""
        Address = ""
        SourceMessageId = $MessageId
        SourceSubject = $Subject
        SourceFrom = $FromEmail
        Notes = $Notes
        Structured = $true
    }
    $item["UniqueKey"] = Get-FlightKey -Item $item
    return $item
}

function New-TravelReservationItem {
    param(
        [string]$Kind,
        [string]$Name,
        [string]$Provider,
        [string]$Start,
        [string]$End,
        [string]$ConfirmationCode,
        [string]$Location,
        [string]$Address,
        [string]$FromLocation,
        [string]$ToLocation,
        [string]$MessageId,
        [string]$Subject,
        [string]$FromEmail,
        [string]$Notes,
        [string]$Status = "Confirmed",
        [bool]$Structured = $true
    )

    $item = @{
        Name = $Name
        Kind = $Kind
        Status = $Status
        Start = $Start
        End = $End
        Provider = $Provider
        ConfirmationCode = $ConfirmationCode
        FlightNumber = ""
        From = $FromLocation
        To = $ToLocation
        Location = $Location
        Address = $Address
        SourceMessageId = $MessageId
        SourceSubject = $Subject
        SourceFrom = $FromEmail
        Notes = $Notes
        Structured = $Structured
    }
    $item["UniqueKey"] = Get-TravelKey -Item $item
    return $item
}

function Get-AirportCityName {
    param([string]$Airport)

    $map = @{
        ATL = "Atlanta"
        AUS = "Austin"
        BOS = "Boston"
        CLT = "Charlotte"
        DCA = "Washington"
        DEN = "Denver"
        DFW = "Dallas"
        EWR = "Newark"
        IAD = "Washington"
        IAH = "Houston"
        JFK = "New York"
        LAS = "Las Vegas"
        LAX = "Los Angeles"
        LGA = "New York"
        MCI = "Kansas City"
        MDW = "Chicago"
        MIA = "Miami"
        MSN = "Madison"
        ORD = "Chicago"
        PHX = "Phoenix"
        ROC = "Rochester"
        SEA = "Seattle"
        SFO = "San Francisco"
    }

    if ($Airport -and $map.ContainsKey($Airport.ToUpperInvariant())) {
        return $map[$Airport.ToUpperInvariant()]
    }
    return ""
}

function Get-AirportTimeZoneId {
    param([string]$Airport)

    $map = @{
        ATL = "Eastern Standard Time"
        CLT = "Eastern Standard Time"
        DCA = "Eastern Standard Time"
        EWR = "Eastern Standard Time"
        IAD = "Eastern Standard Time"
        JFK = "Eastern Standard Time"
        LGA = "Eastern Standard Time"
        MIA = "Eastern Standard Time"
        ROC = "Eastern Standard Time"
        BOS = "Eastern Standard Time"
        ORD = "Central Standard Time"
        MDW = "Central Standard Time"
        MSN = "Central Standard Time"
        DFW = "Central Standard Time"
        IAH = "Central Standard Time"
        MCI = "Central Standard Time"
        AUS = "Central Standard Time"
        DEN = "Mountain Standard Time"
        PHX = "US Mountain Standard Time"
        LAX = "Pacific Standard Time"
        SFO = "Pacific Standard Time"
        SEA = "Pacific Standard Time"
        LAS = "Pacific Standard Time"
    }

    if ($Airport -and $map.ContainsKey($Airport.ToUpperInvariant())) {
        return $map[$Airport.ToUpperInvariant()]
    }
    return ""
}

function Convert-DateAndTime {
    param([string]$Date, [string]$Time, [string]$Airport)

    if (-not $Date -or -not $Time) { return "" }
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo("en-US")
    $styles = [System.Globalization.DateTimeStyles]::None
    $value = "$Date $Time"
    $formats = @("MMMM d, yyyy h:mm tt", "dddd, MMMM d, yyyy h:mm tt")
    foreach ($format in $formats) {
        try {
            $localDateTime = [DateTime]::ParseExact($value, $format, $culture, $styles)
            $timeZoneId = Get-AirportTimeZoneId -Airport $Airport
            if ($timeZoneId) {
                $timeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($timeZoneId)
                $offset = $timeZone.GetUtcOffset($localDateTime)
                return ([DateTimeOffset]::new($localDateTime, $offset)).ToString("yyyy-MM-ddTHH:mm:sszzz")
            }
            return $localDateTime.ToString("s")
        }
        catch {}
    }
    return $value
}

function ConvertTo-PlainLines {
    param([string]$Html)

    if (-not $Html) { return @() }
    $plain = [regex]::Replace($Html, "<(br|/p|/tr|/td|/table|/div)[^>]*>", "`n", "IgnoreCase")
    $plain = [regex]::Replace($plain, "<[^>]+>", " ")
    $plain = [System.Net.WebUtility]::HtmlDecode($plain)
    $plain = [regex]::Replace($plain, "[ \t]+", " ")
    return @($plain -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-ConfirmationCodeFromText {
    param([string]$Text)

    if (-not $Text) { return "" }
    if ($Text -match "(?i)\bConfirmation number:\s*([A-Z0-9]{5,8})\b") {
        return $Matches[1].ToUpperInvariant()
    }
    if ($Text -match "(?i)\bRecord locator\b\s*[:#]?\s*([A-Z0-9]{5,8})\b") {
        return $Matches[1].ToUpperInvariant()
    }
    return ""
}

function Get-ObjectPropertyValue {
    param($Object, [string[]]$Names)

    if (-not $Object) { return "" }
    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($property -and $null -ne $property.Value) {
            return $property.Value
        }
    }
    return ""
}

function ConvertTo-AddressText {
    param($Address)

    if (-not $Address) { return "" }
    if ($Address -is [string]) { return $Address }

    $parts = @()
    foreach ($name in @("streetAddress", "addressLocality", "addressRegion", "postalCode", "addressCountry")) {
        $value = Get-ObjectPropertyValue -Object $Address -Names @($name)
        if ($value) { $parts += "$value" }
    }
    return ($parts -join ", ")
}

function ConvertFrom-JsonLdFlights {
    param(
        [string]$Html,
        [string]$MessageId,
        [string]$Subject,
        [string]$From
    )

    $items = @()
    if (-not $Html) { return $items }

    $matches = [regex]::Matches($Html, "(?is)<script[^>]+type=[""']application/ld\+json[""'][^>]*>(.*?)</script>")
    foreach ($match in $matches) {
        $json = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value).Trim()
        if ($json -notmatch "Flight|Reservation") {
            continue
        }

        try {
            $records = @($json | ConvertFrom-Json)
        }
        catch {
            continue
        }

        foreach ($record in $records) {
            $flights = if ($record.reservationFor) { @($record.reservationFor) } else { @($record) }
            foreach ($flight in $flights) {
                if ($flight.'@type' -ne "Flight") {
                    continue
                }

                $items += New-FlightTravelItem `
                    -FlightNumber $flight.flightNumber `
                    -Provider $flight.airline.name `
                    -Start $flight.departureTime `
                    -End $flight.arrivalTime `
                    -From $flight.departureAirport.iataCode `
                    -To $flight.arrivalAirport.iataCode `
                    -ConfirmationCode (Get-ConfirmationCodeFromText -Text $Html) `
                    -MessageId $MessageId `
                    -Subject $Subject `
                    -FromEmail $From `
                    -Notes "Source: Gmail travel sync`nParser: JSON-LD flight reservation`nDeparture: $($flight.departureAirport.name)`nArrival: $($flight.arrivalAirport.name)"
            }
        }
    }
    return $items
}

function ConvertFrom-JsonLdOtherReservations {
    param(
        [string]$Html,
        [string]$MessageId,
        [string]$Subject,
        [string]$From
    )

    $items = @()
    if (-not $Html) { return $items }

    $matches = [regex]::Matches($Html, "(?is)<script[^>]+type=[""']application/ld\+json[""'][^>]*>(.*?)</script>")
    foreach ($match in $matches) {
        $json = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value).Trim()
        if ($json -notmatch "Reservation|Lodging|Hotel|RentalCar|AutoRental") {
            continue
        }

        try {
            $records = @($json | ConvertFrom-Json)
        }
        catch {
            continue
        }

        foreach ($record in $records) {
            $recordType = "$(Get-ObjectPropertyValue -Object $record -Names @('@type'))"
            $reservationFor = Get-ObjectPropertyValue -Object $record -Names @("reservationFor", "underName")
            $reservationForType = "$(Get-ObjectPropertyValue -Object $reservationFor -Names @('@type'))"
            $confirmation = "$(Get-ObjectPropertyValue -Object $record -Names @("reservationNumber", "confirmationNumber", "orderNumber"))"

            if ($recordType -match "LodgingReservation|HotelReservation" -or $reservationForType -match "Hotel|LodgingBusiness|Accommodation") {
                $provider = "$(Get-ObjectPropertyValue -Object $reservationFor -Names @("name"))"
                if (-not $provider) { $provider = "Hotel" }
                $start = "$(Get-ObjectPropertyValue -Object $record -Names @("checkinTime", "checkInTime", "checkinDate", "checkInDate", "startTime"))"
                $end = "$(Get-ObjectPropertyValue -Object $record -Names @("checkoutTime", "checkOutTime", "checkoutDate", "checkOutDate", "endTime"))"
                $address = ConvertTo-AddressText -Address (Get-ObjectPropertyValue -Object $reservationFor -Names @("address"))
                $location = $provider

                $items += New-TravelReservationItem `
                    -Kind "Hotel" `
                    -Name "Hotel stay: $provider" `
                    -Provider $provider `
                    -Start $start `
                    -End $end `
                    -ConfirmationCode $confirmation `
                    -Location $location `
                    -Address $address `
                    -FromLocation "" `
                    -ToLocation "" `
                    -MessageId $MessageId `
                    -Subject $Subject `
                    -FromEmail $From `
                    -Notes "Source: Gmail travel sync`nParser: JSON-LD lodging reservation"
            }
            elseif ($recordType -match "RentalCarReservation" -or $reservationForType -match "RentalCar|Car|AutoRental") {
                $provider = "$(Get-ObjectPropertyValue -Object $reservationFor -Names @("name"))"
                if (-not $provider) { $provider = "Rental car" }
                $pickup = Get-ObjectPropertyValue -Object $record -Names @("pickupLocation", "pickUpLocation")
                $dropoff = Get-ObjectPropertyValue -Object $record -Names @("dropoffLocation", "dropOffLocation")
                $pickupName = "$(Get-ObjectPropertyValue -Object $pickup -Names @("name"))"
                $dropoffName = "$(Get-ObjectPropertyValue -Object $dropoff -Names @("name"))"
                $start = "$(Get-ObjectPropertyValue -Object $record -Names @("pickupTime", "pickUpTime", "startTime"))"
                $end = "$(Get-ObjectPropertyValue -Object $record -Names @("dropoffTime", "dropOffTime", "endTime"))"
                $location = if ($pickupName) { $pickupName } else { $provider }
                $address = ConvertTo-AddressText -Address (Get-ObjectPropertyValue -Object $pickup -Names @("address"))

                $items += New-TravelReservationItem `
                    -Kind "Car" `
                    -Name "Rental car: $provider" `
                    -Provider $provider `
                    -Start $start `
                    -End $end `
                    -ConfirmationCode $confirmation `
                    -Location $location `
                    -Address $address `
                    -FromLocation $pickupName `
                    -ToLocation $dropoffName `
                    -MessageId $MessageId `
                    -Subject $Subject `
                    -FromEmail $From `
                    -Notes "Source: Gmail travel sync`nParser: JSON-LD rental car reservation"
            }
        }
    }

    return $items
}

function ConvertFrom-UnitedHtmlFlights {
    param(
        [string]$Html,
        [string]$MessageId,
        [string]$Subject,
        [string]$From
    )

    $items = @()
    $lines = ConvertTo-PlainLines -Html $Html
    if ($lines.Count -eq 0) { return $items }

    $confirmationCode = Get-ConfirmationCodeFromText -Text ($lines -join "`n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch "^([A-Z]{2})\s?(\d{3,4})\s+operated by\s+(.+)$") {
            continue
        }

        $flightNumber = "$($Matches[1]) $($Matches[2])"
        $provider = $Matches[3].Trim()
        $date = if ($i -gt 0 -and $lines[$i - 1] -match "^[A-Z][a-z]+ \d{1,2}, \d{4}$") { $lines[$i - 1] } else { "" }
        $aircraft = if (($i + 1) -lt $lines.Count) { $lines[$i + 1] } else { "" }
        $departTime = if (($i + 3) -lt $lines.Count) { $lines[$i + 3] } else { "" }
        $arriveTime = if (($i + 4) -lt $lines.Count) { $lines[$i + 4] } else { "" }
        $departAirport = if (($i + 5) -lt $lines.Count) { $lines[$i + 5] } else { "" }
        $duration = if (($i + 6) -lt $lines.Count) { $lines[$i + 6] } else { "" }
        $arriveAirport = if (($i + 7) -lt $lines.Count) { $lines[$i + 7] } else { "" }
        $departCity = if (($i + 8) -lt $lines.Count) { $lines[$i + 8] } else { "" }
        $arriveCity = if (($i + 9) -lt $lines.Count) { $lines[$i + 9] } else { "" }

        if ($departAirport -notmatch "^[A-Z]{3}$" -or $arriveAirport -notmatch "^[A-Z]{3}$") {
            continue
        }

        $start = Convert-DateAndTime -Date $date -Time $departTime -Airport $departAirport
        $end = Convert-DateAndTime -Date $date -Time $arriveTime -Airport $arriveAirport
        if ($start -and $end) {
            try {
                $startOffset = [DateTimeOffset]::Parse($start)
                $endOffset = [DateTimeOffset]::Parse($end)
                if ($endOffset -lt $startOffset) {
                    $end = $endOffset.AddDays(1).ToString("yyyy-MM-ddTHH:mm:sszzz")
                }
            }
            catch {}
        }

        $items += New-FlightTravelItem `
            -FlightNumber $flightNumber `
            -Provider $provider `
            -Start $start `
            -End $end `
            -From $departAirport `
            -To $arriveAirport `
            -ConfirmationCode $confirmationCode `
            -MessageId $MessageId `
            -Subject $Subject `
            -FromEmail $From `
            -Notes "Source: Gmail travel sync`nParser: United itinerary HTML`nAircraft: $aircraft`nDuration: $duration`nDeparture: $departCity`nArrival: $arriveCity"
    }

    return $items
}

function ConvertFrom-TravelEmail {
    param(
        $Message,
        [string]$Subject,
        [string]$From
    )

    $html = Get-HtmlBody -Message $Message
    $items = ConvertFrom-JsonLdFlights -Html $html -MessageId $Message.id -Subject $Subject -From $From
    if ($items.Count -gt 0) {
        return $items
    }

    $items = ConvertFrom-UnitedHtmlFlights -Html $html -MessageId $Message.id -Subject $Subject -From $From
    if ($items.Count -gt 0) {
        return $items
    }

    if ($IncludeNonFlightTravel) {
        $items = ConvertFrom-JsonLdOtherReservations -Html $html -MessageId $Message.id -Subject $Subject -From $From
        if ($items.Count -gt 0) {
            return $items
        }

        $items = ConvertFrom-TravelEmailHeuristic -Message $Message -Subject $Subject -From $From
        if ($items.Count -gt 0) {
            return $items
        }
    }

    $fallback = ConvertFrom-FlightEmailFallback -Message $Message
    return ,@{
        Name = $fallback.Name
        Kind = "Flight"
        Status = "Needs Review"
        Start = $fallback.Start
        End = $fallback.End
        Provider = ""
        ConfirmationCode = ""
        FlightNumber = ""
        From = ""
        To = ""
        Location = ""
        Address = ""
        SourceMessageId = $Message.id
        SourceSubject = $Subject
        SourceFrom = $From
        UniqueKey = "message|$($Message.id)"
        Notes = $fallback.Notes
        Structured = $false
    }
}

function ConvertFrom-TravelEmailHeuristic {
    param($Message, [string]$Subject, [string]$From)

    $body = Get-PlainBody -Message $Message
    $html = Get-HtmlBody -Message $Message
    $text = "$From`n$Subject`n$($Message.snippet)`n$body`n$([System.Net.WebUtility]::HtmlDecode(([regex]::Replace($html, '<[^>]+>', ' '))))"
    $date = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Message.internalDate).LocalDateTime.ToString("yyyy-MM-dd")
    $confirmation = Get-ConfirmationCodeFromText -Text $text

    if ($text -match "(?i)\b(Marriott|Bonvoy|Hilton|Hampton Inn|DoubleTree|Embassy Suites|Homewood Suites|Hyatt|IHG|Holiday Inn|hotel|check[\s-]?in|check[\s-]?out)\b") {
        $provider = if ($text -match "(?i)\b(Marriott|Bonvoy)\b") { "Marriott" } elseif ($text -match "(?i)\b(Hilton|Hampton Inn|DoubleTree|Embassy Suites|Homewood Suites)\b") { "Hilton" } elseif ($text -match "(?i)\b(Hyatt)\b") { "Hyatt" } elseif ($text -match "(?i)\b(IHG|Holiday Inn)\b") { "IHG" } else { "Hotel" }
        return ,(New-TravelReservationItem `
            -Kind "Hotel" `
            -Name "Hotel reservation: $provider" `
            -Provider $provider `
            -Start $date `
            -End "" `
            -ConfirmationCode $confirmation `
            -Location "" `
            -Address "" `
            -FromLocation "" `
            -ToLocation "" `
            -MessageId $Message.id `
            -Subject $Subject `
            -FromEmail $From `
            -Notes "Needs review: hotel-like email found, but no structured lodging reservation was parsed.`nSource: Gmail travel sync`nFrom: $From`nSubject: $Subject`nSnippet: $($Message.snippet)" `
            -Status "Needs Review" `
            -Structured $false)
    }

    if ($text -match "(?i)\b(National|Enterprise|Alamo|Hertz|Avis|Budget|rental car|car rental|pickup|pick-up|return location)\b") {
        $provider = if ($text -match "(?i)\bNational\b") { "National" } elseif ($text -match "(?i)\bEnterprise\b") { "Enterprise" } elseif ($text -match "(?i)\bAlamo\b") { "Alamo" } elseif ($text -match "(?i)\bHertz\b") { "Hertz" } elseif ($text -match "(?i)\bAvis\b") { "Avis" } elseif ($text -match "(?i)\bBudget\b") { "Budget" } else { "Rental car" }
        return ,(New-TravelReservationItem `
            -Kind "Car" `
            -Name "Rental car reservation: $provider" `
            -Provider $provider `
            -Start $date `
            -End "" `
            -ConfirmationCode $confirmation `
            -Location "" `
            -Address "" `
            -FromLocation "" `
            -ToLocation "" `
            -MessageId $Message.id `
            -Subject $Subject `
            -FromEmail $From `
            -Notes "Needs review: rental-car-like email found, but no structured rental car reservation was parsed.`nSource: Gmail travel sync`nFrom: $From`nSubject: $Subject`nSnippet: $($Message.snippet)" `
            -Status "Needs Review" `
            -Structured $false)
    }

    return @()
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

function DateRangeValue {
    param([string]$Start, [string]$End)
    if (-not $Start) { return $null }
    $date = @{ start = $Start }
    if ($End) {
        try {
            $startOffset = [DateTimeOffset]::Parse($Start)
            $endOffset = [DateTimeOffset]::Parse($End)
            $date["end"] = $endOffset.ToOffset($startOffset.Offset).ToString("yyyy-MM-ddTHH:mm:sszzz")
        }
        catch {
            $date["end"] = $End
        }
    }
    return @{ date = $date }
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

function Test-NotionTravelDatabase {
    param([string]$NotionToken)

    $database = Invoke-NotionApi -Method "GET" -Path "/databases/$TravelDatabaseId" -NotionToken $NotionToken
    $requiredProperties = @("Name", "Kind", "Status", "Start", "End", "Calendar Block", "Calendar Category", "Provider", "Confirmation Code", "Flight Number", "From", "To", "Location", "Address", "Source Message ID", "Source Subject", "Unique Key", "Notes")
    $missingProperties = @($requiredProperties | Where-Object { -not $database.properties.PSObject.Properties.Name.Contains($_) })

    if ($missingProperties.Count -gt 0) {
        throw "Travel database is reachable, but missing expected propert$(if ($missingProperties.Count -eq 1) { 'y' } else { 'ies' }): $($missingProperties -join ', ')"
    }

    Write-Host "Notion preflight OK: Travel database is reachable and has the expected reservation fields."
}

function Add-TravelItem {
    param($Item, [string]$NotionToken)

    $properties = @{
        Name = TitleValue $Item.Name
        Kind = SelectValue $Item.Kind
        Status = SelectValue $Item.Status
        Start = DateValue $Item.Start
        "Calendar Category" = SelectValue "Travel"
        Provider = TextValue $Item.Provider
        "Confirmation Code" = TextValue $Item.ConfirmationCode
        "Flight Number" = TextValue $Item.FlightNumber
        From = TextValue $Item.From
        To = TextValue $Item.To
        Location = TextValue $Item.Location
        Address = TextValue $Item.Address
        "Source Message ID" = TextValue $Item.SourceMessageId
        "Source Subject" = TextValue $Item.SourceSubject
        "Unique Key" = TextValue $Item.UniqueKey
        Notes = TextValue $Item.Notes
    }

    if ($Item.End) {
        $properties["End"] = DateRangeValue -Start $Item.Start -End $Item.End
        $properties["Calendar Block"] = DateRangeValue -Start $Item.Start -End $Item.End
    }
    elseif ($Item.Start) {
        $properties["Calendar Block"] = DateValue $Item.Start
    }

    $body = @{
        parent = @{ database_id = $TravelDatabaseId }
        properties = $properties
    }

    return Invoke-NotionApi -Method "POST" -Path "/pages" -NotionToken $NotionToken -Body $body
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")
Add-Type -AssemblyName System.Web

$notionToken = Get-EnvValue -Name "NOTION_TOKEN"
if (($Apply -or $CheckNotion) -and -not $notionToken) {
    throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
}

if ($CheckNotion) {
    Test-NotionTravelDatabase -NotionToken $notionToken
    if (-not $Apply) {
        return
    }
}

$accessToken = Get-GmailAccessToken
$processedLabelId = ""
if ($FileProcessedEmail -or $FileImportedEmail) {
    $processedLabelId = Get-GmailLabelId -AccessToken $accessToken -LabelName $ProcessedLabelName
}
$state = Load-State
$imported = @($state.importedMessageIds)
$importedSegmentKeys = if ($state.PSObject.Properties.Name.Contains("importedSegmentKeys")) { @($state.importedSegmentKeys) } else { @() }

if ($FileImportedEmail) {
    if ($imported.Count -eq 0) {
        Write-Host "No imported Gmail message IDs were found in local travel sync state."
        return
    }

    foreach ($messageId in @($imported | Select-Object -Unique)) {
        Set-GmailProcessedMessage -AccessToken $accessToken -MessageId $messageId -LabelId $processedLabelId
        $actions = @()
        if ($FileProcessedEmail) { $actions += "labeled '$ProcessedLabelName'" }
        if ($ArchiveProcessedEmail) { $actions += "archived from Inbox" }
        Write-Host "Filed imported Gmail message ${messageId}: $($actions -join ', ')"
    }
    return
}
if (-not $GmailQuery) {
    $GmailQuery = "newer_than:${LookbackDays}d {from:delta.com from:united.com from:aa.com from:americanairlines.com from:marriott.com from:hilton.com from:nationalcar.com from:enterprise.com subject:Delta subject:United subject:`"American Airlines`" subject:Marriott subject:Hilton subject:National subject:Enterprise subject:flight subject:itinerary subject:confirmation subject:reservation subject:hotel subject:`"rental car`"}"
}
$query = $GmailQuery
$encodedQuery = [uri]::EscapeDataString($query)
$messageList = Invoke-GmailApi -AccessToken $accessToken -Path "/users/me/messages?q=$encodedQuery&maxResults=$MaxMessages"
$messages = @($messageList.messages)
$candidates = @()
$seenSegmentKeys = @{}

foreach ($item in $messages) {
    if ((-not $ReplayImported) -and ($imported -contains $item.id)) {
        continue
    }

    $message = Invoke-GmailApi -AccessToken $accessToken -Path "/users/me/messages/$($item.id)?format=full"
    $subject = Get-MessageHeader -Message $message -Name "Subject"
    $from = Get-MessageHeader -Message $message -Name "From"
    $travelItems = @(ConvertFrom-TravelEmail -Message $message -Subject $subject -From $from)

    foreach ($travelItem in $travelItems) {
        if ($ReviewTravelEmail) {
            $candidates += $travelItem
            continue
        }

        $key = $travelItem["UniqueKey"]
        if ($key -and (($importedSegmentKeys -contains $key) -or $seenSegmentKeys.ContainsKey($key))) {
            continue
        }

        if ($key) {
            $seenSegmentKeys[$key] = $true
        }
        $candidates += $travelItem
    }
}

if ($candidates.Count -eq 0) {
    Write-Host "No new travel email candidates found."
    return
}

if ($ReviewTravelEmail) {
    Write-Host "Review mode. No Notion writes, Gmail labels, or local state updates will be made."
    $candidates | ForEach-Object {
        [pscustomobject]@{
            Kind = $_["Kind"]
            Status = $_["Status"]
            Name = $_["Name"]
            Provider = $_["Provider"]
            Start = $_["Start"]
            End = $_["End"]
            Confirmation = $_["ConfirmationCode"]
            Location = $_["Location"]
            Address = $_["Address"]
            Structured = $_["Structured"]
            MessageId = $_["SourceMessageId"]
        }
    } | Format-List
    return
}

if (-not $Apply) {
    Write-Host "Dry run. Re-run with -Apply to write to Notion and update local state."
    $candidates | ForEach-Object {
        [pscustomobject]@{
            Name = $_["Name"]
            Kind = $_["Kind"]
            Start = $_["Start"]
            End = $_["End"]
            From = $_["From"]
            To = $_["To"]
            Structured = $_["Structured"]
            MessageId = $_["SourceMessageId"]
        }
    } | Format-Table -AutoSize
    return
}

$writtenMessageIds = @()
$writtenSegmentKeys = @()
foreach ($candidate in $candidates) {
    [void](Add-TravelItem -Item $candidate -NotionToken $notionToken)
    $writtenMessageIds += $candidate.SourceMessageId
    if ($candidate.UniqueKey) {
        $writtenSegmentKeys += $candidate.UniqueKey
    }
    Write-Host "Added: $($candidate.Name)"
}

foreach ($messageId in @($writtenMessageIds | Select-Object -Unique)) {
    Set-GmailProcessedMessage -AccessToken $accessToken -MessageId $messageId -LabelId $processedLabelId
    if ($FileProcessedEmail -or $ArchiveProcessedEmail) {
        $actions = @()
        if ($FileProcessedEmail) { $actions += "labeled '$ProcessedLabelName'" }
        if ($ArchiveProcessedEmail) { $actions += "archived from Inbox" }
        Write-Host "Filed Gmail message ${messageId}: $($actions -join ', ')"
    }
}

$state.importedMessageIds = @($imported + $writtenMessageIds | Select-Object -Unique)
if ($state.PSObject.Properties.Name.Contains("importedSegmentKeys")) {
    $state.importedSegmentKeys = @($importedSegmentKeys + $writtenSegmentKeys | Select-Object -Unique)
}
else {
    $state | Add-Member -MemberType NoteProperty -Name "importedSegmentKeys" -Value @($importedSegmentKeys + $writtenSegmentKeys | Select-Object -Unique)
}
if ($state.PSObject.Properties.Name.Contains("lastRun")) {
    $state.lastRun = (Get-Date).ToString("o")
}
else {
    $state | Add-Member -MemberType NoteProperty -Name "lastRun" -Value (Get-Date).ToString("o")
}
Save-State -State $state
Write-Host "Imported $($candidates.Count) travel reservation row(s)."
