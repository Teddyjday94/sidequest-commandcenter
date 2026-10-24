[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$')]
    [string] $WorkerId,

    [securestring] $Token,

    [string] $CredentialTarget = 'SidequestCommandCenterWorker'
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'SidequestBroker.psm1'
Import-Module $modulePath -Force -DisableNameChecking

if (-not $Token) {
    $Token = Read-Host 'Paste the one-time worker token' -AsSecureString
}

try {
    $credential = [pscredential]::new($WorkerId, $Token)
    Set-SidequestWorkerCredential -Credential $credential -TargetName $CredentialTarget
    Write-Host "Enrolled worker '$WorkerId' in Windows Credential Manager target '$CredentialTarget'."
} finally {
    $credential = $null
    $Token = $null
}
