$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $repoRoot 'runner\install-worker-schedule.ps1'
$runnerPath = Join-Path $repoRoot 'runner\run-next-job.ps1'
$bypassEnrollmentPath = Join-Path $repoRoot 'runner\enroll-vercel-bypass.ps1'

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

function Assert-ThrowsContaining {
    param(
        [Parameter(Mandatory)] [scriptblock] $Action,
        [Parameter(Mandatory)] [string] $Expected,
        [Parameter(Mandatory)] [string] $Because
    )

    try {
        & $Action
    } catch {
        Assert-Contains -Actual $_.Exception.Message -Expected $Expected -Because $Because
        return
    }

    throw $Because
}

Assert-Equal -Actual (Test-Path -LiteralPath $installerPath -PathType Leaf) -Expected $true -Because 'The preview-first schedule installer must exist.'
Assert-Equal -Actual (Test-Path -LiteralPath $runnerPath -PathType Leaf) -Expected $true -Because 'The scheduled action must invoke the queue-aware one-job runner.'
Assert-Equal -Actual (Test-Path -LiteralPath $bypassEnrollmentPath -PathType Leaf) -Expected $true -Because 'Protected previews must have a dedicated secure bypass enrollment path.'

$runnerSource = Get-Content -LiteralPath $runnerPath -Raw
Assert-Contains -Actual $runnerSource -Expected "Import-Module `$modulePath" -Because 'The scheduled entrypoint must load the reviewed Sidequest worker module.'
Assert-Contains -Actual $runnerSource -Expected 'Invoke-SidequestWorkerTurn @parameters' -Because 'The scheduled entrypoint must delegate exactly one turn to the exported worker function.'
Assert-Contains -Actual $runnerSource -Expected "CredentialTarget = `$CredentialTarget" -Because 'The runner must pass the named Windows credential target to the worker.'

Assert-ThrowsContaining -Action {
    & $runnerPath -BaseUri 'http://studio.example.test' | Out-Null
} -Expected 'broker_uri_not_secure' -Because 'The scheduled runner must reject a remote HTTP broker before importing the worker module.'

Assert-ThrowsContaining -Action {
    & $runnerPath -BaseUri 'https://worker:secret@studio.example.test' | Out-Null
} -Expected 'broker_uri_not_secure' -Because 'The scheduled runner must reject embedded URL credentials before importing the worker module.'

Assert-ThrowsContaining -Action {
    & $runnerPath -BaseUri 'https://studio.example.test?token=secret' | Out-Null
} -Expected 'broker_uri_not_secure' -Because 'The scheduled runner must reject query-string credentials before importing the worker module.'

$script:registrationCalled = $false
function Register-ScheduledTask {
    $script:registrationCalled = $true
    throw 'preview_must_not_register'
}

$previewJson = & $installerPath -BaseUri 'https://studio.example.test'
$preview = $previewJson | ConvertFrom-Json
Assert-Equal -Actual $preview.mode -Expected 'preview' -Because 'Schedule installation must be preview-only unless -Apply is explicit.'
Assert-Equal -Actual $script:registrationCalled -Expected $false -Because 'Preview mode must never write to Windows Task Scheduler.'
Assert-Equal -Actual $preview.taskName -Expected 'Sidequest Command Center Worker' -Because 'The installer may target only the reviewed worker task name.'
Assert-Equal -Actual $preview.schedule.timezone -Expected 'America/Chicago' -Because 'The human-facing schedule must remain in the approved Central time zone.'
Assert-Equal -Actual $preview.schedule.windowsTimeZone -Expected 'Central Standard Time' -Because 'Windows Task Scheduler must use the America/Chicago-equivalent zone.'
Assert-Equal -Actual $preview.schedule.start -Expected '07:00' -Because 'The first worker heartbeat must start at 7:00 AM Central.'
Assert-Equal -Actual $preview.schedule.lastStart -Expected '20:00' -Because 'The final worker heartbeat must start at 8:00 PM Central.'
Assert-Equal -Actual $preview.schedule.repetitionBoundary -Expected '20:01' -Because 'The repetition boundary must sit strictly after 8:00 PM and before 8:15 PM so boundary semantics cannot add or remove a run.'
Assert-Equal -Actual $preview.schedule.intervalMinutes -Expected 15 -Because 'The worker must poll at the reviewed fifteen-minute cadence.'
Assert-Equal -Actual $preview.schedule.durationMinutes -Expected 781 -Because 'The repetition duration must include the 8:00 PM slot and stop strictly before 8:15 PM.'
Assert-Equal -Actual ([System.IO.Path]::GetFileName($preview.action.executable)) -Expected 'powershell.exe' -Because 'The native task must use stable inbox Windows PowerShell rather than the temporary Codex runtime.'
Assert-NotContains -Actual $preview.action.executable -Unexpected '\.cache\codex-runtimes\' -Because 'A persistent native task must not depend on a disposable Codex runtime path.'
Assert-Equal -Actual $preview.action.credentialTarget -Expected 'SidequestCommandCenterWorker' -Because 'The scheduled action must resolve only the named Windows credential.'
Assert-Equal -Actual $preview.action.protectionBypassCredentialTarget -Expected 'SidequestCommandCenterVercelBypass' -Because 'The scheduled action must reference the separate Vercel bypass credential by target name only.'
Assert-Contains -Actual $preview.action.arguments -Expected '-BaseUri "https://studio.example.test/"' -Because 'The task action must bind the reviewed HTTPS broker URL.'
Assert-Contains -Actual $preview.action.arguments -Expected '-CredentialTarget "SidequestCommandCenterWorker"' -Because 'The task action must pass only the credential target, never its secret.'
Assert-Contains -Actual $preview.action.arguments -Expected '-ProtectionBypassCredentialTarget "SidequestCommandCenterVercelBypass"' -Because 'The task action must pass only the Vercel bypass credential target, never its secret.'
Assert-NotContains -Actual $preview.action.arguments -Unexpected 'worker_token_' -Because 'No raw worker token may appear in the scheduled task arguments.'
Assert-NotContains -Actual $preview.action.arguments -Unexpected 'OPENAI_API_KEY' -Because 'The scheduled task must not carry usage-based provider credentials.'

[xml] $previewTaskXml = $preview.taskXml
$taskNamespace = [System.Xml.XmlNamespaceManager]::new($previewTaskXml.NameTable)
$taskNamespace.AddNamespace('task', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
Assert-Equal -Actual $previewTaskXml.DocumentElement.LocalName -Expected 'Task' -Because 'Preview must include a well-formed native Task Scheduler definition.'
Assert-Equal -Actual $previewTaskXml.SelectSingleNode('//task:Actions/task:Exec/task:Command', $taskNamespace).InnerText -Expected $preview.action.executable -Because 'The XML command must match the reviewed native PowerShell action.'
Assert-Equal -Actual $previewTaskXml.SelectSingleNode('//task:Actions/task:Exec/task:Arguments', $taskNamespace).InnerText -Expected $preview.action.arguments -Because 'The XML arguments must match the secret-free preview action.'
Assert-Equal -Actual $previewTaskXml.SelectSingleNode('//task:Settings/task:StartWhenAvailable', $taskNamespace).InnerText -Expected 'false' -Because 'A missed task must not run later outside the approved operating window.'

Remove-Item Function:\Register-ScheduledTask -ErrorAction SilentlyContinue

Assert-ThrowsContaining -Action {
    & $installerPath -BaseUri 'http://studio.example.test' | Out-Null
} -Expected 'broker_uri_not_secure' -Because 'A remote HTTP broker URL must be rejected before schedule construction.'

Assert-ThrowsContaining -Action {
    & $installerPath -BaseUri 'https://worker:secret@studio.example.test' | Out-Null
} -Expected 'broker_uri_not_secure' -Because 'Embedded URL credentials must be rejected before schedule construction.'

Assert-ThrowsContaining -Action {
    & $installerPath -BaseUri 'https://studio.example.test?token=secret' | Out-Null
} -Expected 'broker_uri_not_secure' -Because 'Query strings must be rejected so the persistent task arguments cannot capture a secret.'

$global:SidequestScheduleRegistration = $null
function Get-TimeZone { [pscustomobject]@{ Id = 'Central Standard Time' } }
function Register-ScheduledTask {
    param($TaskName, $Xml, [switch] $Force)
    $global:SidequestScheduleRegistration = [pscustomobject]@{
        TaskName = $TaskName
        Xml = $Xml
        Force = $Force.IsPresent
    }
    [pscustomobject]@{ TaskName = $TaskName; State = 'Ready' }
}

$appliedJson = & $installerPath -BaseUri 'https://studio.example.test' -Apply
$applied = $appliedJson | ConvertFrom-Json
Assert-Equal -Actual $applied.mode -Expected 'applied' -Because 'Explicit -Apply must report a completed task registration.'
Assert-Equal -Actual $global:SidequestScheduleRegistration.TaskName -Expected 'Sidequest Command Center Worker' -Because 'Apply must register only the fixed reviewed task name.'
Assert-Equal -Actual $global:SidequestScheduleRegistration.Force -Expected $true -Because 'Apply must update the exact worker task idempotently rather than create duplicates.'
Assert-Contains -Actual $global:SidequestScheduleRegistration.Xml -Expected '<Interval>PT15M</Interval>' -Because 'The registered calendar trigger must repeat every fifteen minutes.'
Assert-Contains -Actual $global:SidequestScheduleRegistration.Xml -Expected '<Duration>PT13H1M</Duration>' -Because 'The trigger boundary must fall at 8:01 PM, strictly between the required final run and the next interval.'
Assert-Contains -Actual $global:SidequestScheduleRegistration.Xml -Expected 'T07:00:00</StartBoundary>' -Because 'The registered daily trigger must begin at 7:00 AM local time.'
Assert-Contains -Actual $global:SidequestScheduleRegistration.Xml -Expected '<DaysInterval>1</DaysInterval>' -Because 'The reviewed worker window must repeat daily.'
Assert-Contains -Actual $global:SidequestScheduleRegistration.Xml -Expected '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>' -Because 'Task Scheduler must not start an overlapping worker when an earlier turn is still running.'
Assert-Contains -Actual $global:SidequestScheduleRegistration.Xml -Expected '<LogonType>InteractiveToken</LogonType>' -Because 'The task must run only in the signed-in Windows session that owns the Codex login and worker credential.'
Assert-NotContains -Actual $global:SidequestScheduleRegistration.Xml -Unexpected 'worker_token_' -Because 'The registered task must never store the raw worker credential.'
Assert-NotContains -Actual $global:SidequestScheduleRegistration.Xml -Unexpected 'OPENAI_API_KEY' -Because 'The registered task must never store usage-based provider credentials.'

foreach ($name in @('Get-TimeZone', 'Register-ScheduledTask')) {
    Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
}
Remove-Variable SidequestScheduleRegistration -Scope Global -ErrorAction SilentlyContinue

function Get-TimeZone { [pscustomobject]@{ Id = 'UTC' } }
Assert-ThrowsContaining -Action {
    & $installerPath -BaseUri 'https://studio.example.test' -Apply | Out-Null
} -Expected 'windows_timezone_mismatch' -Because 'Apply must fail closed when the PC is not set to the America/Chicago-equivalent Windows zone.'
Remove-Item Function:\Get-TimeZone -ErrorAction SilentlyContinue

Write-Host 'Schedule tests passed.'
