[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $BaseUri,

    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$taskName = 'Sidequest Command Center Worker'
$credentialTarget = 'SidequestCommandCenterWorker'
$protectionBypassCredentialTarget = 'SidequestCommandCenterVercelBypass'
$windowsTimeZone = 'Central Standard Time'
$ianaTimeZone = 'America/Chicago'
$intervalMinutes = 15
# A 20:01 repetition boundary makes the 20:00 start valid while placing the
# next 15-minute slot (20:15) strictly outside the window under either
# inclusive or exclusive boundary handling.
$durationMinutes = 781

function ConvertTo-SidequestScheduleBrokerUri {
    param([Parameter(Mandatory)] [string] $Value)

    try {
        $uri = [uri] $Value
    } catch {
        throw [InvalidOperationException]::new('broker_uri_not_secure')
    }

    if (
        -not $uri.IsAbsoluteUri -or
        $uri.Scheme -ne 'https' -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)
    ) {
        throw [InvalidOperationException]::new('broker_uri_not_secure')
    }

    return [uri] ($uri.AbsoluteUri.TrimEnd('/') + '/')
}

$brokerUri = ConvertTo-SidequestScheduleBrokerUri -Value $BaseUri
$runnerPath = Join-Path $PSScriptRoot 'run-next-job.ps1'
$repoRoot = Split-Path -Parent $PSScriptRoot
$powerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
$taskArguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -BaseUri "{1}" -CredentialTarget "{2}" -ProtectionBypassCredentialTarget "{3}"' -f `
    $runnerPath, $brokerUri.AbsoluteUri, $credentialTarget, $protectionBypassCredentialTarget
$startBoundary = [datetime]::Today.AddHours(7).ToString('yyyy-MM-ddTHH:mm:ss')
$principalSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$escapedPowerShellPath = [System.Security.SecurityElement]::Escape($powerShellPath)
$escapedTaskArguments = [System.Security.SecurityElement]::Escape($taskArguments)
$escapedRepoRoot = [System.Security.SecurityElement]::Escape($repoRoot)
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Checks the guarded Sidequest queue and processes at most one internal Codex job.</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <Repetition>
        <Interval>PT15M</Interval>
        <Duration>PT13H1M</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$principalSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>false</StartWhenAvailable>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$escapedPowerShellPath</Command>
      <Arguments>$escapedTaskArguments</Arguments>
      <WorkingDirectory>$escapedRepoRoot</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

$preview = [ordered]@{
    mode = if ($Apply) { 'applied' } else { 'preview' }
    taskName = $taskName
    schedule = [ordered]@{
        timezone = $ianaTimeZone
        windowsTimeZone = $windowsTimeZone
        start = '07:00'
        lastStart = '20:00'
        repetitionBoundary = '20:01'
        intervalMinutes = $intervalMinutes
        durationMinutes = $durationMinutes
    }
    action = [ordered]@{
        executable = $powerShellPath
        arguments = $taskArguments
        workingDirectory = $repoRoot
        credentialTarget = $credentialTarget
        protectionBypassCredentialTarget = $protectionBypassCredentialTarget
    }
    taskXml = $taskXml
}

if (-not $Apply) {
    $preview | ConvertTo-Json -Depth 6
    return
}

$currentTimeZone = (Get-TimeZone).Id
if ($currentTimeZone -notin @($windowsTimeZone, $ianaTimeZone)) {
    throw [InvalidOperationException]::new('windows_timezone_mismatch')
}

Register-ScheduledTask `
    -TaskName $taskName `
    -Xml $taskXml `
    -Force | Out-Null

$preview | ConvertTo-Json -Depth 6
