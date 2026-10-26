$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'runner\SidequestRunner.psm1'
Import-Module $modulePath -Force

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
    param([string] $Actual, [string] $Unexpected, [string] $Because)
    if ($Actual.Contains($Unexpected)) { throw "$Because`nUnexpected: $Unexpected" }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)] [scriptblock] $Action,
        [Parameter(Mandatory)] [string] $Because
    )

    try {
        & $Action
    } catch {
        return
    }

    throw $Because
}

Assert-Equal -Actual (Test-ChatGPTAuthStatus "Logged in using ChatGPT") -Expected $true -Because 'A ChatGPT-authenticated Codex CLI run must be accepted.'

Assert-Equal -Actual (Test-ChatGPTAuthStatus "Logged in using an API key") -Expected $false -Because 'API-key authentication must be rejected so the runner cannot create usage-based charges.'

Assert-Equal -Actual (Test-ChatGPTAuthStatus "Not logged in") -Expected $false -Because 'Unknown or signed-out authentication must fail closed.'

$goodDoctorReport = @{
    checks = @{
        'auth.credentials' = @{
            status = 'ok'
            details = @{
                'stored API key' = 'false'
                'stored ChatGPT tokens' = 'true'
                'stored auth mode' = 'chatgpt'
            }
        }
        'config.load' = @{
            status = 'ok'
            details = @{ 'model provider' = 'openai' }
        }
        'network.provider_reachability' = @{
            status = 'ok'
            details = @{
                'ChatGPT inference URL' = 'https://chatgpt.com/backend-api/codex reachable'
            }
        }
        'network.websocket_reachability' = @{
            status = 'ok'
            details = @{
                endpoint = 'wss://chatgpt.com/backend-api/codex'
                'auth mode' = 'chatgpt'
                'model provider' = 'openai'
                'provider name' = 'OpenAI'
            }
        }
        'sandbox.helpers' = @{
            status = 'ok'
            details = @{ 'approval policy' = 'OnRequest' }
        }
    }
} | ConvertTo-Json -Depth 8

Assert-Equal -Actual (Test-CodexDoctorReport $goodDoctorReport) -Expected $true -Because 'A pinned OpenAI provider using ChatGPT tokens and the ChatGPT endpoint must pass preflight.'

$failedProviderFixture = $goodDoctorReport | ConvertFrom-Json
$failedProviderFixture.checks.'network.provider_reachability'.status = 'fail'
$failedProviderReport = $failedProviderFixture | ConvertTo-Json -Depth 8
Assert-Equal -Actual (Test-CodexDoctorReport $failedProviderReport) -Expected $false -Because 'A required provider connectivity failure must fail closed even when endpoint metadata looks correct.'

$customProviderFixture = $goodDoctorReport | ConvertFrom-Json
$customProviderFixture.checks.'config.load'.details.'model provider' = 'custom-provider'
$customProviderReport = $customProviderFixture | ConvertTo-Json -Depth 8
Assert-Equal -Actual (Test-CodexDoctorReport $customProviderReport) -Expected $false -Because 'A custom effective provider must fail even when ChatGPT credentials are stored.'

$customEndpointFixture = $goodDoctorReport | ConvertFrom-Json
$customEndpointFixture.checks.'network.provider_reachability'.details.'ChatGPT inference URL' = 'https://gateway.example/v1 reachable'
$customEndpointReport = $customEndpointFixture | ConvertTo-Json -Depth 8
Assert-Equal -Actual (Test-CodexDoctorReport $customEndpointReport) -Expected $false -Because 'A custom HTTP inference endpoint must fail even when the websocket endpoint still points at ChatGPT.'

$noApprovalFixture = $goodDoctorReport | ConvertFrom-Json
$noApprovalFixture.checks.'sandbox.helpers'.details.'approval policy' = 'Never'
$noApprovalReport = $noApprovalFixture | ConvertTo-Json -Depth 8
Assert-Equal -Actual (Test-CodexDoctorReport $noApprovalReport) -Expected $false -Because 'An inherited never-approve policy must fail the human-review preflight.'

Assert-Equal -Actual (Test-NoPaidCodexEnvironment @{}) -Expected $true -Because 'An environment without provider keys must pass the billing preflight.'
Assert-Equal -Actual (Test-NoPaidCodexEnvironment @{ CODEX_API_KEY = 'present' }) -Expected $false -Because 'CODEX_API_KEY can override subscription authentication and must be rejected.'
Assert-Equal -Actual (Test-NoPaidCodexEnvironment @{ OPENAI_BASE_URL = 'https://gateway.example' }) -Expected $false -Because 'A custom OpenAI base URL must be rejected by the no-purchase runner.'

$salesSpec = Get-SidequestAgentSpec -Agent 'sales-agent' -RepoRoot $repoRoot
Assert-Equal -Actual $salesSpec.Id -Expected 'sales-agent' -Because 'The runner must resolve the requested agent without silently selecting a different job.'
Assert-Equal -Actual $salesSpec.Schedule -Expected '17 9 * * 1-5' -Because 'The Codex sales schedule must retain the existing 9:17 AM weekday cadence.'

$salesPrompt = New-SidequestAgentPrompt -Spec $salesSpec -RepoRoot $repoRoot
Assert-Contains -Actual $salesPrompt -Expected 'AGENTS.md' -Because 'Every run must load the repository safety rules.'
Assert-Contains -Actual $salesPrompt -Expected 'playbook/PLAYBOOK.md' -Because 'Every run must use the local playbook as its source of operating logic.'
Assert-Contains -Actual $salesPrompt -Expected 'Never send emails, DMs, texts, invoices, or posts.' -Because 'The runner prompt must preserve the human-send-only boundary.'
Assert-Contains -Actual $salesPrompt -Expected 'agents/codex/sales-agent.md' -Because 'The run must load the correct Codex-specific agent instructions.'

Assert-Throws -Action { Get-SidequestAgentSpec -Agent 'made-up-agent' -RepoRoot $repoRoot } -Because 'Unknown agent names must be rejected instead of running an unintended prompt.'

$execArgs = New-CodexExecArguments -Prompt 'Run sales.' -RepoRoot 'C:\sidequest' -SchemaPath 'C:\sidequest\runner\agent-result.schema.json' -OutputPath 'C:\sidequest\.codex-runs\sales.json'
$actualArgs = ConvertTo-Json -Compress -InputObject @($execArgs)
$expectedArgs = '["--ask-for-approval","on-request","exec","--strict-config","-c","model_provider=\"openai\"","--ephemeral","--sandbox","workspace-write","-C","C:\\sidequest","--output-schema","C:\\sidequest\\runner\\agent-result.schema.json","-o","C:\\sidequest\\.codex-runs\\sales.json","Run sales."]'
Assert-Equal -Actual $actualArgs -Expected $expectedArgs -Because 'The runner must pin the built-in OpenAI provider and use a bounded writable sandbox without automatic approval.'

$modelArgs = New-CodexExecArguments -Prompt 'Run content.' -RepoRoot 'C:\sidequest' -SchemaPath 'C:\schema.json' -OutputPath 'C:\result.json' -Model 'gpt-example'
Assert-Contains -Actual (ConvertTo-Json -Compress -InputObject @($modelArgs)) -Expected '"--model","gpt-example"' -Because 'A user-selected Codex model must be forwarded without changing the default when no model is requested.'

$isolatedArgs = New-CodexExecArguments -Prompt 'Run queued research.' -RepoRoot 'C:\sidequest' -SchemaPath 'C:\schema.json' -OutputPath 'C:\result.json' -Model 'gpt-6-luna' -WorkerIsolation -NativeWebSearch
$isolatedArgsJson = ConvertTo-Json -Compress -InputObject @($isolatedArgs)
Assert-Contains -Actual $isolatedArgsJson -Expected '["--search","exec","--ignore-user-config"' -Because 'Queued research jobs must use native search and ignore user project configuration.'
Assert-NotContains -Actual $isolatedArgsJson -Unexpected '"--ask-for-approval"' -Because 'The noninteractive queued process must rely on its no-tool read-only boundary and broker approvals rather than advertise an ineffective interactive prompt.'
foreach ($feature in @('plugins', 'apps', 'computer_use', 'browser_use', 'shell_tool')) {
    Assert-Contains -Actual $isolatedArgsJson -Expected ('"--disable","{0}"' -f $feature) -Because "Queued jobs must disable the $feature feature at the Codex process boundary."
}
Assert-NotContains -Actual $isolatedArgsJson -Unexpected '"--disable","unified_exec"' -Because 'Native search requires the unified execution host while shell_tool remains disabled.'
Assert-Contains -Actual $isolatedArgsJson -Expected '"mcp_servers={}"' -Because 'Queued jobs must clear directly configured MCP servers at the process boundary.'
Assert-Contains -Actual $isolatedArgsJson -Expected '"shell_environment_policy.inherit=\"none\""' -Because 'Queued jobs must not inherit host environment credentials.'
Assert-Contains -Actual $isolatedArgsJson -Expected '"--sandbox","read-only"' -Because 'Queued model turns produce only a broker result envelope and must not write the workspace.'
Assert-Equal -Actual $isolatedArgs[-1] -Expected '-' -Because 'Queued jobs must read their prompt from stdin so Windows PowerShell cannot split trusted multiline input into native arguments.'
Assert-NotContains -Actual $isolatedArgsJson -Unexpected 'Run queued research.' -Because 'Queued prompts must never travel through the Windows native command line.'

$isolatedNoSearchArgs = New-CodexExecArguments -Prompt 'Run queued review.' -RepoRoot 'C:\sidequest' -SchemaPath 'C:\schema.json' -OutputPath 'C:\result.json' -Model 'gpt-6.1-sol' -WorkerIsolation
$isolatedNoSearchArgsJson = ConvertTo-Json -Compress -InputObject @($isolatedNoSearchArgs)
Assert-NotContains -Actual $isolatedNoSearchArgsJson -Unexpected '"--search"' -Because 'Non-research queued roles must not receive native web search.'
Assert-Contains -Actual $isolatedNoSearchArgsJson -Expected '"--disable","unified_exec"' -Because 'Non-search jobs must disable the unified execution host with every other unnecessary tool route.'

$pluginList = @'
browser@openai-bundled      installed, enabled  1.0
supabase@openai-curated     installed, enabled  1.0
gmail@openai-curated        not installed
'@
$missingPlugins = @(Get-MissingAgentPlugins -RequiredPlugins @('supabase', 'gmail', 'browser') -PluginListText $pluginList)
Assert-Equal -Actual ($missingPlugins -join ',') -Expected 'gmail' -Because 'Plugin preflight must fail before model invocation when a required connection package is absent.'

$completedResult = '{"agent":"sales-agent","status":"completed","summary":"done","completed":[],"blocked":[],"next_action":"review"}'
$blockedResult = '{"agent":"sales-agent","status":"blocked","summary":"missing connection","completed":[],"blocked":["Supabase"],"next_action":"connect"}'
Assert-Equal -Actual (Get-SidequestResultDisposition -Json $completedResult -ExpectedAgent 'sales-agent').ExitCode -Expected 0 -Because 'A completed matching agent result must exit successfully.'
Assert-Equal -Actual (Get-SidequestResultDisposition -Json $blockedResult -ExpectedAgent 'sales-agent').ExitCode -Expected 20 -Because 'A fully blocked result must be visible to schedulers as a nonzero exit.'
Assert-Throws -Action { Get-SidequestResultDisposition -Json $completedResult -ExpectedAgent 'content-agent' } -Because 'A result for a different agent must never be accepted.'

$dryRunJson = & (Join-Path $repoRoot 'runner\run-agent.ps1') -Agent 'sales-agent' -DryRun
$dryRun = $dryRunJson | ConvertFrom-Json
Assert-Equal -Actual $dryRun.agent -Expected 'sales-agent' -Because 'Dry-run output must identify the agent that would run.'
Assert-Equal -Actual $dryRun.billing_guard -Expected 'ChatGPT login required' -Because 'The executable runner must advertise the no-API-billing guard.'
Assert-Contains -Actual ($dryRun.arguments | ConvertTo-Json -Compress) -Expected '"workspace-write"' -Because 'Dry-run output must expose the bounded sandbox configuration that will be executed.'

Write-Host 'Runner tests passed.'
