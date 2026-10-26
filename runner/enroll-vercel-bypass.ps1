[CmdletBinding()]
param(
    [securestring] $Secret,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')]
    [string] $CredentialTarget = 'SidequestCommandCenterVercelBypass'
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'SidequestBroker.psm1'
Import-Module $modulePath -Force -DisableNameChecking

if (-not $Secret) {
    $Secret = Read-Host 'Paste the Vercel automation bypass secret' -AsSecureString
}

try {
    $credential = [pscredential]::new('vercel-automation-bypass', $Secret)
    Set-SidequestWorkerCredential -Credential $credential -TargetName $CredentialTarget
    Write-Host "Stored the Vercel automation bypass in Windows Credential Manager target '$CredentialTarget'."
} finally {
    $credential = $null
    $Secret = $null
}
