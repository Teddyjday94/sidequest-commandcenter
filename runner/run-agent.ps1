[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('contact-finder', 'sales-agent', 'mockup-builder', 'content-agent')]
    [string] $Agent,

    [string] $Model,

    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot 'SidequestRunner.psm1'
$schemaPath = Join-Path $PSScriptRoot 'agent-result.schema.json'
$runsDirectory = Join-Path $repoRoot '.codex-runs'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputPath = Join-Path $runsDirectory "$timestamp-$Agent.json"

Import-Module $modulePath -Force

$spec = Get-SidequestAgentSpec -Agent $Agent -RepoRoot $repoRoot
$prompt = New-SidequestAgentPrompt -Spec $spec -RepoRoot $repoRoot
$arguments = New-CodexExecArguments -Prompt $prompt -RepoRoot $repoRoot -SchemaPath $schemaPath -OutputPath $outputPath -Model $Model

if ($DryRun) {
    [pscustomobject]@{
        agent = $Agent
        schedule = $spec.Schedule
        timezone = 'America/Chicago'
        billing_guard = 'ChatGPT login required'
        executable = 'codex'
        arguments = $arguments
    } | ConvertTo-Json -Depth 5
    exit 0
}

$providerEnvironment = @{}
foreach ($name in @('CODEX_API_KEY', 'OPENAI_API_KEY', 'OPENAI_BASE_URL')) {
    $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    if ($item) {
        $providerEnvironment[$name] = $item.Value
    }
}

if (-not (Test-NoPaidCodexEnvironment $providerEnvironment)) {
    throw 'Refusing to run because an API-key or custom-provider environment variable is set. Remove CODEX_API_KEY, OPENAI_API_KEY, and OPENAI_BASE_URL for this process.'
}

$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $doctorJson = (& codex doctor --json -c 'model_provider="openai"' -c 'approval_policy="on-request"' 2>$null | Out-String)
} finally {
    $ErrorActionPreference = $previousPreference
}

if (-not (Test-CodexDoctorReport $doctorJson)) {
    throw 'Refusing to run because Codex Doctor did not confirm ChatGPT tokens, the built-in OpenAI provider, and the official ChatGPT endpoint.'
}

try {
    $ErrorActionPreference = 'Continue'
    $pluginList = (& codex plugin list 2>$null | Out-String)
    $pluginExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousPreference
}

if ($pluginExitCode -ne 0) {
    throw "Unable to inspect Codex plugins (exit code $pluginExitCode). No model run was started."
}

$missingPlugins = @(Get-MissingAgentPlugins -RequiredPlugins $spec.required_plugins -PluginListText $pluginList)
if ($missingPlugins.Count -gt 0) {
    throw "Missing required enabled Codex plugins: $($missingPlugins -join ', '). Install and connect them before running $Agent. No model run was started."
}

New-Item -ItemType Directory -Path $runsDirectory -Force | Out-Null

try {
    $ErrorActionPreference = 'Continue'
    & codex @arguments
    $codexExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousPreference
}

if ($codexExitCode -ne 0) {
    throw "Codex exited with code $codexExitCode."
}

if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw 'Codex exited successfully but did not create the required structured result file.'
}

$resultJson = Get-Content -Raw -LiteralPath $outputPath
$disposition = Get-SidequestResultDisposition -Json $resultJson -ExpectedAgent $Agent
Write-Host "$($disposition.Status): $($disposition.Summary)"
Write-Host "Saved structured result to $outputPath"

if ($disposition.ExitCode -ne 0) {
    exit $disposition.ExitCode
}
