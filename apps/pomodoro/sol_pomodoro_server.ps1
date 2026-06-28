param(
    [int]$Port = 8765,
    [string]$LearningLogDatabaseId = "37fe8e29-9eae-816d-a682-e5ecf84db554",
    [string]$NotionVersion = "2022-06-28"
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

function New-RichText {
    param([string]$Text)
    return ,@(@{ type = "text"; text = @{ content = $Text } })
}

function TitleValue { param([string]$Value) return @{ title = (New-RichText -Text $Value) } }
function TextValue {
    param([string]$Value)
    if (-not $Value) { return @{ rich_text = @() } }
    return @{ rich_text = (New-RichText -Text $Value) }
}
function SelectValue { param([string]$Value) return @{ select = @{ name = $Value } } }
function NumberValue { param([double]$Value) return @{ number = $Value } }
function DateValue { param([string]$Value) return @{ date = @{ start = $Value } } }

function Get-LearningDatabase {
    $notionToken = Get-EnvValue -Name "NOTION_TOKEN"
    if (-not $notionToken) {
        throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
    }

    $headers = @{
        Authorization = "Bearer $notionToken"
        "Notion-Version" = $NotionVersion
    }

    return Invoke-RestMethod -Method "GET" -Uri "https://api.notion.com/v1/databases/$LearningLogDatabaseId" -Headers $headers
}

function Get-LearningPropertyMap {
    $database = Get-LearningDatabase
    $properties = @{}
    foreach ($property in $database.properties.PSObject.Properties) {
        $properties[$property.Name] = $property.Value
    }
    return $properties
}

function Add-LearningLogEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Topic,
        [Parameter(Mandatory = $true)][double]$Hours,
        [Parameter(Mandatory = $true)][string]$Date,
        [string]$SessionTitle = "",
        [string]$Notes = "",
        [string]$Outcome = "",
        [string]$NextStep = "",
        [string]$Source = "Pomodoro"
    )

    $notionToken = Get-EnvValue -Name "NOTION_TOKEN"
    if (-not $notionToken) {
        throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
    }

    $headers = @{
        Authorization = "Bearer $notionToken"
        "Notion-Version" = $NotionVersion
        "Content-Type" = "application/json"
    }

    $databaseProperties = Get-LearningPropertyMap
    $entryName = if ($SessionTitle) { "$SessionTitle - $Date" } else { "$Topic Pomodoro - $Date" }
    $properties = @{
        Name = TitleValue $entryName
        Date = DateValue $Date
        Topic = SelectValue $Topic
        Hours = NumberValue $Hours
        Notes = TextValue $Notes
    }
    if ($Outcome -and $databaseProperties.ContainsKey("Outcome")) { $properties.Outcome = SelectValue $Outcome }
    if ($NextStep -and $databaseProperties.ContainsKey("Next Step")) { $properties["Next Step"] = TextValue $NextStep }
    if ($Source -and $databaseProperties.ContainsKey("Source")) { $properties.Source = SelectValue $Source }

    $body = @{
        parent = @{ database_id = $LearningLogDatabaseId }
        properties = $properties
    }

    $jsonBody = $body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Method "POST" -Uri "https://api.notion.com/v1/pages" -Headers $headers -Body $jsonBody
}

function Get-LearningCategories {
    $notionToken = Get-EnvValue -Name "NOTION_TOKEN"
    if (-not $notionToken) {
        throw "Missing NOTION_TOKEN. Set it in the process/user environment or in a local .env file."
    }

    $headers = @{
        Authorization = "Bearer $notionToken"
        "Notion-Version" = $NotionVersion
    }

    $database = Invoke-RestMethod -Method "GET" -Uri "https://api.notion.com/v1/databases/$LearningLogDatabaseId" -Headers $headers
    $topicProperty = $database.properties.Topic
    if (-not $topicProperty -or -not $topicProperty.select) {
        throw "Learning Log database does not have a Topic select property."
    }

    return @($topicProperty.select.options | ForEach-Object {
        @{
            name = $_.name
            color = $_.color
        }
    })
}

function Read-HttpRequest {
    param([System.IO.Stream]$Stream)

    $buffer = New-Object byte[] 65536
    $memory = New-Object System.IO.MemoryStream
    $headerEnd = -1

    while ($headerEnd -lt 0) {
        $read = $Stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { break }
        $memory.Write($buffer, 0, $read)
        $raw = $memory.ToArray()
        for ($i = 0; $i -le ($raw.Length - 4); $i++) {
            if ($raw[$i] -eq 13 -and $raw[$i + 1] -eq 10 -and $raw[$i + 2] -eq 13 -and $raw[$i + 3] -eq 10) {
                $headerEnd = $i
                break
            }
        }
    }

    $allBytes = $memory.ToArray()
    if ($headerEnd -lt 0) {
        throw "Invalid HTTP request."
    }

    $headerText = [System.Text.Encoding]::ASCII.GetString($allBytes, 0, $headerEnd)
    $headerLines = $headerText -split "`r`n"
    $requestLine = $headerLines[0] -split " "
    $headers = @{}

    foreach ($line in $headerLines[1..($headerLines.Count - 1)]) {
        if (-not $line) { continue }
        $parts = $line -split ":", 2
        if ($parts.Count -eq 2) {
            $headers[$parts[0].Trim().ToLowerInvariant()] = $parts[1].Trim()
        }
    }

    $contentLength = 0
    if ($headers.ContainsKey("content-length")) {
        $contentLength = [int]$headers["content-length"]
    }

    $bodyStart = $headerEnd + 4
    $bodyBytes = New-Object byte[] $contentLength
    $alreadyRead = [Math]::Max(0, $allBytes.Length - $bodyStart)
    if ($alreadyRead -gt 0) {
        [Array]::Copy($allBytes, $bodyStart, $bodyBytes, 0, [Math]::Min($alreadyRead, $contentLength))
    }

    $offset = [Math]::Min($alreadyRead, $contentLength)
    while ($offset -lt $contentLength) {
        $read = $Stream.Read($bodyBytes, $offset, $contentLength - $offset)
        if ($read -le 0) { break }
        $offset += $read
    }

    return @{
        Method = $requestLine[0]
        Path = ([uri]("http://127.0.0.1" + $requestLine[1])).AbsolutePath
        Body = [System.Text.Encoding]::UTF8.GetString($bodyBytes, 0, $contentLength)
    }
}

function Write-HttpResponse {
    param(
        [System.IO.Stream]$Stream,
        [int]$StatusCode,
        [string]$ContentType,
        [byte[]]$Body
    )

    $reason = switch ($StatusCode) {
        200 { "OK" }
        404 { "Not Found" }
        default { "Internal Server Error" }
    }

    $header = "HTTP/1.1 $StatusCode $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($Body, 0, $Body.Length)
}

function Write-JsonResponse {
    param(
        [System.IO.Stream]$Stream,
        [int]$StatusCode,
        [object]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 20
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Write-HttpResponse -Stream $Stream -StatusCode $StatusCode -ContentType "application/json; charset=utf-8" -Body $bytes
}

Import-DotEnv -Path (Join-Path -Path $RepoRoot -ChildPath ".env")

$htmlPath = Join-Path -Path $PSScriptRoot -ChildPath "sol_pomodoro.html"
if (-not (Test-Path -LiteralPath $htmlPath)) {
    throw "Missing UI file: $htmlPath"
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$prefix = "http://127.0.0.1:$Port/"
$listener.Start()

Write-Host "SoL Pomodoro is running at $prefix"
Write-Host "Press Ctrl+C to stop."

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()

        try {
            $request = Read-HttpRequest -Stream $stream

            if ($request.Method -eq "GET" -and ($request.Path -eq "/" -or $request.Path -eq "/index.html")) {
                $bytes = [System.IO.File]::ReadAllBytes($htmlPath)
                Write-HttpResponse -Stream $stream -StatusCode 200 -ContentType "text/html; charset=utf-8" -Body $bytes
            }
            elseif ($request.Method -eq "GET" -and $request.Path -eq "/api/health") {
                $hasToken = [bool](Get-EnvValue -Name "NOTION_TOKEN")
                Write-JsonResponse -Stream $stream -StatusCode 200 -Body @{
                    ok = $true
                    notionTokenConfigured = $hasToken
                    learningLogDatabaseId = $LearningLogDatabaseId
                }
            }
            elseif ($request.Method -eq "GET" -and $request.Path -eq "/api/categories") {
                $categories = Get-LearningCategories
                Write-JsonResponse -Stream $stream -StatusCode 200 -Body @{
                    ok = $true
                    categories = $categories
                }
            }
            elseif ($request.Method -eq "POST" -and $request.Path -eq "/api/stop") {
                Write-JsonResponse -Stream $stream -StatusCode 200 -Body @{ ok = $true; stopped = $true }
                break
            }
            elseif ($request.Method -eq "POST" -and $request.Path -eq "/api/log") {
                $payload = if ($request.Body) { $request.Body | ConvertFrom-Json } else { @{} }
                $topic = [string]$payload.topic
                $sessionTitle = [string]$payload.sessionTitle
                $notes = [string]$payload.notes
                $outcome = [string]$payload.outcome
                $nextStep = [string]$payload.nextStep
                $date = [string]$payload.date
                $durationSeconds = [double]$payload.durationSeconds

                if (-not $topic) { throw "Topic is required." }
                if (-not $date) { $date = (Get-Date).ToString("yyyy-MM-dd") }
                if ($durationSeconds -le 0) { throw "Duration must be greater than zero." }

                $hours = [Math]::Round(($durationSeconds / 3600), 3)
                $result = Add-LearningLogEntry -Topic $topic -Hours $hours -Date $date -SessionTitle $sessionTitle -Notes $notes -Outcome $outcome -NextStep $nextStep -Source "Pomodoro"

                Write-JsonResponse -Stream $stream -StatusCode 200 -Body @{
                    ok = $true
                    pageId = $result.id
                    topic = $topic
                    hours = $hours
                    date = $date
                }
            }
            else {
                Write-JsonResponse -Stream $stream -StatusCode 404 -Body @{ ok = $false; error = "Not found." }
            }
        }
        catch {
            Write-JsonResponse -Stream $stream -StatusCode 500 -Body @{ ok = $false; error = $_.Exception.Message }
        }
        finally {
            $stream.Close()
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
