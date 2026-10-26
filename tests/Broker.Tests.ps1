$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'runner\SidequestBroker.psm1'
Import-Module $modulePath -Force -DisableNameChecking
$moduleSource = Get-Content -Raw -LiteralPath $modulePath

function Assert-Equal {
    param(
        [Parameter(Mandatory)] $Actual,
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] [string] $Because
    )

    if ($Actual -ne $Expected) {
        throw "$Because`nExpected: $Expected`nActual:   $Actual"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)] [string] $Actual,
        [Parameter(Mandatory)] [string] $Expected,
        [Parameter(Mandatory)] [string] $Because
    )

    if (-not $Actual.Contains($Expected)) {
        throw "$Because`nMissing: $Expected"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory)] [string] $Actual,
        [Parameter(Mandatory)] [string] $Unexpected,
        [Parameter(Mandatory)] [string] $Because
    )

    if ($Actual.Contains($Unexpected)) {
        throw "$Because`nUnexpected: $Unexpected"
    }
}

function Assert-ThrowsBrokerStatus {
    param(
        [Parameter(Mandatory)] [scriptblock] $Action,
        [Parameter(Mandatory)] [int] $StatusCode,
        [Parameter(Mandatory)] [string] $Code
    )

    try {
        & $Action
    } catch {
        Assert-Equal -Actual $_.Exception.StatusCode -Expected $StatusCode -Because 'Broker errors must preserve the safe HTTP status for scheduler decisions.'
        Assert-Equal -Actual $_.Exception.Code -Expected $Code -Because 'Broker errors must expose a stable safe code.'
        return $_.Exception.Message
    }

    throw "Expected a broker exception with status $StatusCode."
}

$rawToken = 'worker_token_abcdefghijklmnopqrstuvwxyz_1234567890'
$secureToken = ConvertTo-SecureString $rawToken -AsPlainText -Force
$credential = [pscredential]::new('worker-one', $secureToken)
$rawProtectionBypass = 'vercel_bypass_abcdefghijklmnopqrstuvwxyz_1234567890'
$secureProtectionBypass = ConvertTo-SecureString $rawProtectionBypass -AsPlainText -Force
$baseUri = 'https://studio.example.test'
$jobId = '21000000-0000-4000-8000-000000000001'
Assert-Contains -Actual $moduleSource -Expected 'MaximumRedirection = 0' -Because 'The default broker transport must not forward the worker authorization header through redirects.'

$brokerModule = Get-Module SidequestBroker
$unicodePayload = ('{{"summary":"Cypress Forge Construction{0}s public listing"}}' -f [char] 0x2019)
$defaultTransportResult = & $brokerModule {
    param($payload)
    function Invoke-WebRequest {
        param($Method, $Uri, $Headers, $ErrorAction, $MaximumRedirection, $ContentType, $Body, $UseBasicParsing)
        if ($Body -isnot [byte[]]) { throw 'default_transport_body_not_bytes' }
        $decoded = [Text.Encoding]::UTF8.GetString($Body)
        if ($decoded -ne $payload) { throw 'default_transport_body_not_utf8' }
        if ($ContentType -ne 'application/json; charset=utf-8') { throw 'default_transport_charset_missing' }
        [pscustomobject]@{ StatusCode = 200; Content = '{}' }
    }
    try {
        Invoke-DefaultSidequestTransport 'POST' 'https://studio.example.test/api/test' @{} $payload
    } finally {
        Remove-Item Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
    }
} $unicodePayload
Assert-Equal -Actual $defaultTransportResult.StatusCode -Expected 200 -Because 'The default transport must preserve non-ASCII result text as explicit UTF-8 bytes.'

$script:insecureTransportCalled = $false
$insecureTransport = {
    param($Method, $Uri, $Headers, $Body)
    $script:insecureTransportCalled = $true
    [pscustomobject]@{ StatusCode = 200; Content = '{}' }
}
try {
    Get-SidequestOffer -BaseUri 'http://attacker.example.test' -Credential $credential -Transport $insecureTransport
    throw 'An insecure remote broker URI must be rejected.'
} catch {
    Assert-Contains -Actual $_.Exception.Message -Expected 'broker_uri_not_secure' -Because 'The broker must reject remote HTTP before reading or sending a credential.'
}
Assert-Equal -Actual $script:insecureTransportCalled -Expected $false -Because 'An insecure broker URI must fail before transport receives the worker token.'

$loopbackTransport = {
    param($Method, $Uri, $Headers, $Body)
    [pscustomobject]@{ StatusCode = 204; Content = '' }
}
$loopbackOffer = Get-SidequestOffer -BaseUri 'http://127.0.0.1:4173' -Credential $credential -Transport $loopbackTransport
Assert-Equal -Actual ($null -eq $loopbackOffer) -Expected $true -Because 'HTTP remains available only for explicit loopback development.'

$emptyTransport = {
    param($Method, $Uri, $Headers, $Body)
    [pscustomobject]@{ StatusCode = 204; Content = '' }
}
$emptyOffer = Get-SidequestOffer -BaseUri $baseUri -Credential $credential -Transport $emptyTransport
Assert-Equal -Actual ($null -eq $emptyOffer) -Expected $true -Because 'An empty queue must return no work without throwing or invoking a model.'

$script:capturedRequest = $null
$claimTransport = {
    param($Method, $Uri, $Headers, $Body)
    $script:capturedRequest = [pscustomobject]@{ Method = $Method; Uri = $Uri; Headers = $Headers; Body = $Body }
    [pscustomobject]@{ StatusCode = 200; Content = '{"id":"21000000-0000-4000-8000-000000000001","status":"running"}' }
}
$claimed = Claim-SidequestJob -BaseUri $baseUri -Credential $credential -JobId $jobId -Transport $claimTransport
Assert-Equal -Actual $claimed.status -Expected 'running' -Because 'A successful claim must return the broker response.'
Assert-Equal -Actual $script:capturedRequest.Method -Expected 'POST' -Because 'Claim must use POST.'
Assert-Equal -Actual $script:capturedRequest.Uri -Expected "$baseUri/api/worker-claim" -Because 'Claim must use the fixed worker endpoint.'
Assert-Equal -Actual $script:capturedRequest.Headers.Authorization -Expected "Worker $rawToken" -Because 'The worker credential must be sent only in the authorization header.'
Assert-Equal -Actual (($script:capturedRequest.Body | ConvertFrom-Json).jobId) -Expected $jobId -Because 'Claim must bind the exact offered job id.'

$script:capturedBypassHeaders = $null
$bypassTransport = {
    param($Method, $Uri, $Headers, $Body)
    $script:capturedBypassHeaders = $Headers
    [pscustomobject]@{ StatusCode = 204; Content = '' }
}
$null = Get-SidequestOffer -BaseUri $baseUri -Credential $credential -ProtectionBypassSecret $secureProtectionBypass -Transport $bypassTransport
Assert-Equal -Actual $script:capturedBypassHeaders.Authorization -Expected "Worker $rawToken" -Because 'Adding Vercel protection bypass must not alter worker authentication.'
Assert-Equal -Actual $script:capturedBypassHeaders['x-vercel-protection-bypass'] -Expected $rawProtectionBypass -Because 'The protected preview must receive its automation bypass only as a request header.'

$script:invalidBypassTransportCalled = $false
$invalidBypassTransport = {
    param($Method, $Uri, $Headers, $Body)
    $script:invalidBypassTransportCalled = $true
    [pscustomobject]@{ StatusCode = 204; Content = '' }
}
try {
    $invalidBypass = ConvertTo-SecureString "bad`r`nheader" -AsPlainText -Force
    Get-SidequestOffer -BaseUri $baseUri -Credential $credential -ProtectionBypassSecret $invalidBypass -Transport $invalidBypassTransport | Out-Null
    throw 'An invalid protection bypass reached transport.'
} catch {
    Assert-Contains -Actual $_.Exception.Message -Expected 'protection_bypass_invalid' -Because 'Protection bypass values must reject header injection before transport.'
}
Assert-Equal -Actual $script:invalidBypassTransportCalled -Expected $false -Because 'An invalid protection bypass must never reach network transport.'

$resultTransport = {
    param($Method, $Uri, $Headers, $Body)
    $parsed = $Body | ConvertFrom-Json
    if ($parsed.result.summary -ne 'done') { throw 'Result payload was not serialized.' }
    [pscustomobject]@{ StatusCode = 200; Content = '{"id":"21000000-0000-4000-8000-000000000001","status":"completed"}' }
}
$completed = Submit-SidequestResult -BaseUri $baseUri -Credential $credential -JobId $jobId -Result @{ summary = 'done' } -Transport $resultTransport
Assert-Equal -Actual $completed.status -Expected 'completed' -Because 'A validated result must be returned as a typed object.'

$failureTransport = {
    param($Method, $Uri, $Headers, $Body)
    $parsed = $Body | ConvertFrom-Json
    if ($parsed.code -ne 'network_timeout' -or -not $parsed.retryable) { throw 'Failure payload was not serialized.' }
    [pscustomobject]@{ StatusCode = 200; Content = '{"id":"21000000-0000-4000-8000-000000000001","status":"queued"}' }
}
$failed = Fail-SidequestJob -BaseUri $baseUri -Credential $credential -JobId $jobId -Code 'network_timeout' -Summary 'Browser timed out' -Retryable $true -Transport $failureTransport
Assert-Equal -Actual $failed.status -Expected 'queued' -Because 'A retryable failure must preserve the broker retry decision.'

foreach ($case in @(
    @{ Status = 401; Code = 'worker_not_authorized' },
    @{ Status = 409; Code = 'worker_lease_conflict' },
    @{ Status = 429; Code = 'rate_limited' },
    @{ Status = 503; Code = 'worker_unavailable' }
)) {
    $errorTransport = {
        param($Method, $Uri, $Headers, $Body)
        [pscustomobject]@{
            StatusCode = $case.Status
            Content = ('{{"error":"{0}","unsafe":"{1}"}}' -f $case.Code, $rawToken)
        }
    }.GetNewClosure()

    $message = Assert-ThrowsBrokerStatus -StatusCode $case.Status -Code $case.Code -Action {
        Send-SidequestHeartbeat -BaseUri $baseUri -Credential $credential -JobId $jobId -Transport $errorTransport
    }
    Assert-NotContains -Actual $message -Unexpected $rawToken -Because 'Broker errors must never echo the raw worker credential.'
    Assert-Contains -Actual $message -Expected $case.Code -Because 'Broker errors must retain a safe actionable code.'
}

Write-Host 'Broker tests passed.'
