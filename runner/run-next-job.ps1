[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [uri] $BaseUri,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')]
    [string] $CredentialTarget = 'SidequestCommandCenterWorker'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (
    -not $BaseUri.IsAbsoluteUri -or
    $BaseUri.Scheme -ne 'https' -or
    -not [string]::IsNullOrEmpty($BaseUri.UserInfo) -or
    -not [string]::IsNullOrEmpty($BaseUri.Query) -or
    -not [string]::IsNullOrEmpty($BaseUri.Fragment)
) {
    throw [InvalidOperationException]::new('broker_uri_not_secure')
}

$modulePath = Join-Path $PSScriptRoot 'SidequestWorker.psm1'
Import-Module $modulePath -Force -DisableNameChecking

$parameters = @{
    BaseUri = $BaseUri
    CredentialTarget = $CredentialTarget
}
$result = Invoke-SidequestWorkerTurn @parameters
if ($null -ne $result) {
    $result | ConvertTo-Json -Depth 8
}
