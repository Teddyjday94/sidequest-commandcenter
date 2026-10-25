Set-StrictMode -Version Latest

class SidequestBrokerException : System.Exception {
    [int] $StatusCode
    [string] $Code

    SidequestBrokerException([int] $statusCode, [string] $code) : base("Sidequest broker request failed ($statusCode): $code.") {
        $this.StatusCode = $statusCode
        $this.Code = $code
    }
}

$script:DefaultCredentialTarget = 'SidequestCommandCenterWorker'

function Initialize-SidequestCredentialInterop {
    if ('Sidequest.NativeCredentialManager' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Sidequest {
    public static class NativeCredentialManager {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct Credential {
            public UInt32 Flags;
            public UInt32 Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public UInt32 CredentialBlobSize;
            public IntPtr CredentialBlob;
            public UInt32 Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("Advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CredWrite(ref Credential credential, UInt32 flags);

        [DllImport("Advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CredRead(string target, UInt32 type, UInt32 flags, out IntPtr credentialPtr);

        [DllImport("Advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
        public static extern void CredFree(IntPtr credentialPtr);
    }
}
'@
}

function ConvertFrom-SidequestSecureString {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [securestring] $SecureString)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Set-SidequestWorkerCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscredential] $Credential,
        [string] $TargetName = $script:DefaultCredentialTarget
    )

    Initialize-SidequestCredentialInterop
    $plainText = ConvertFrom-SidequestSecureString $Credential.Password
    $bytes = [Text.Encoding]::Unicode.GetBytes($plainText)
    $blob = [Runtime.InteropServices.Marshal]::AllocCoTaskMem($bytes.Length)
    try {
        [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $blob, $bytes.Length)
        $native = [Sidequest.NativeCredentialManager+Credential]::new()
        $native.Type = 1
        $native.TargetName = $TargetName
        $native.CredentialBlobSize = $bytes.Length
        $native.CredentialBlob = $blob
        $native.Persist = 2
        $native.UserName = $Credential.UserName
        if (-not [Sidequest.NativeCredentialManager]::CredWrite([ref] $native, 0)) {
            throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
    } finally {
        for ($index = 0; $index -lt $bytes.Length; $index++) { $bytes[$index] = 0 }
        for ($offset = 0; $offset -lt $bytes.Length; $offset++) {
            [Runtime.InteropServices.Marshal]::WriteByte($blob, $offset, 0)
        }
        [Runtime.InteropServices.Marshal]::FreeCoTaskMem($blob)
        $plainText = $null
    }
}

function Get-SidequestWorkerCredential {
    [CmdletBinding()]
    param([string] $TargetName = $script:DefaultCredentialTarget)

    Initialize-SidequestCredentialInterop
    $credentialPointer = [IntPtr]::Zero
    if (-not [Sidequest.NativeCredentialManager]::CredRead($TargetName, 1, 0, [ref] $credentialPointer)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }

    try {
        $native = [Runtime.InteropServices.Marshal]::PtrToStructure(
            $credentialPointer,
            [type] [Sidequest.NativeCredentialManager+Credential]
        )
        $bytes = [byte[]]::new($native.CredentialBlobSize)
        [Runtime.InteropServices.Marshal]::Copy($native.CredentialBlob, $bytes, 0, $bytes.Length)
        $token = [Text.Encoding]::Unicode.GetString($bytes)
        try {
            $secureToken = ConvertTo-SecureString $token -AsPlainText -Force
            return [pscredential]::new($native.UserName, $secureToken)
        } finally {
            for ($index = 0; $index -lt $bytes.Length; $index++) { $bytes[$index] = 0 }
            $token = $null
        }
    } finally {
        [Sidequest.NativeCredentialManager]::CredFree($credentialPointer)
    }
}

function Invoke-DefaultSidequestTransport {
    param($Method, $Uri, $Headers, $Body)

    $parameters = @{
        Method = $Method
        Uri = $Uri
        Headers = $Headers
        ErrorAction = 'Stop'
        MaximumRedirection = 0
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body
    }
    if ($PSVersionTable.PSVersion.Major -le 5) {
        $parameters.UseBasicParsing = $true
    }

    try {
        $response = Invoke-WebRequest @parameters
        return [pscustomobject]@{ StatusCode = [int] $response.StatusCode; Content = [string] $response.Content }
    } catch {
        $statusCode = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int] $_.Exception.Response.StatusCode
        }
        $content = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { [string] $_.ErrorDetails.Message } else { '' }
        return [pscustomobject]@{ StatusCode = $statusCode; Content = $content }
    }
}

function Invoke-SidequestBrokerRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('GET', 'POST')] [string] $Method,
        [Parameter(Mandatory)] [uri] $Uri,
        [Parameter(Mandatory)] [pscredential] $Credential,
        [AllowNull()] $Body,
        [scriptblock] $Transport = ${function:Invoke-DefaultSidequestTransport}
    )

    $isSecureRemote = $Uri.IsAbsoluteUri -and $Uri.Scheme -eq 'https'
    $isLoopbackDevelopment = $Uri.IsAbsoluteUri -and $Uri.Scheme -eq 'http' -and $Uri.IsLoopback
    if ((-not $isSecureRemote -and -not $isLoopbackDevelopment) -or -not [string]::IsNullOrEmpty($Uri.UserInfo)) {
        throw [InvalidOperationException]::new('broker_uri_not_secure')
    }

    $token = ConvertFrom-SidequestSecureString $Credential.Password
    try {
        $headers = @{ Authorization = "Worker $token"; Accept = 'application/json' }
        $jsonBody = if ($null -eq $Body) { $null } else { $Body | ConvertTo-Json -Compress -Depth 12 }
        $response = & $Transport $Method $Uri.AbsoluteUri.TrimEnd('/') $headers $jsonBody
        $statusCode = [int] $response.StatusCode

        if ($statusCode -eq 204) { return $null }
        if ($statusCode -lt 200 -or $statusCode -ge 300) {
            $code = 'broker_error'
            if (-not [string]::IsNullOrWhiteSpace([string] $response.Content)) {
                try {
                    $parsedError = [string] $response.Content | ConvertFrom-Json
                    if ($parsedError.error -match '^[a-z][a-z0-9_]{0,99}$') { $code = [string] $parsedError.error }
                } catch { }
            }
            throw [SidequestBrokerException]::new($statusCode, $code)
        }

        if ([string]::IsNullOrWhiteSpace([string] $response.Content)) { return $null }
        return [string] $response.Content | ConvertFrom-Json
    } finally {
        $token = $null
    }
}

function Get-SidequestOffer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [uri] $BaseUri,
        [pscredential] $Credential = (Get-SidequestWorkerCredential),
        [scriptblock] $Transport = ${function:Invoke-DefaultSidequestTransport}
    )

    Invoke-SidequestBrokerRequest -Method GET -Uri ([uri]::new($BaseUri, '/api/worker-offer')) -Credential $Credential -Body $null -Transport $Transport
}

function Claim-SidequestJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [uri] $BaseUri,
        [Parameter(Mandatory)] [guid] $JobId,
        [pscredential] $Credential = (Get-SidequestWorkerCredential),
        [scriptblock] $Transport = ${function:Invoke-DefaultSidequestTransport}
    )

    Invoke-SidequestBrokerRequest -Method POST -Uri ([uri]::new($BaseUri, '/api/worker-claim')) -Credential $Credential -Body @{ jobId = $JobId.ToString() } -Transport $Transport
}

function Send-SidequestHeartbeat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [uri] $BaseUri,
        [Parameter(Mandatory)] [guid] $JobId,
        [pscredential] $Credential = (Get-SidequestWorkerCredential),
        [scriptblock] $Transport = ${function:Invoke-DefaultSidequestTransport}
    )

    Invoke-SidequestBrokerRequest -Method POST -Uri ([uri]::new($BaseUri, '/api/worker-heartbeat')) -Credential $Credential -Body @{ jobId = $JobId.ToString() } -Transport $Transport
}

function Submit-SidequestResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [uri] $BaseUri,
        [Parameter(Mandatory)] [guid] $JobId,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Result,
        [pscredential] $Credential = (Get-SidequestWorkerCredential),
        [scriptblock] $Transport = ${function:Invoke-DefaultSidequestTransport}
    )

    Invoke-SidequestBrokerRequest -Method POST -Uri ([uri]::new($BaseUri, '/api/worker-result')) -Credential $Credential -Body @{ jobId = $JobId.ToString(); result = $Result } -Transport $Transport
}

function Fail-SidequestJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [uri] $BaseUri,
        [Parameter(Mandatory)] [guid] $JobId,
        [Parameter(Mandatory)] [ValidatePattern('^[a-z][a-z0-9_]{0,99}$')] [string] $Code,
        [Parameter(Mandatory)] [ValidateLength(1, 1000)] [string] $Summary,
        [Parameter(Mandatory)] [bool] $Retryable,
        [pscredential] $Credential = (Get-SidequestWorkerCredential),
        [scriptblock] $Transport = ${function:Invoke-DefaultSidequestTransport}
    )

    Invoke-SidequestBrokerRequest -Method POST -Uri ([uri]::new($BaseUri, '/api/worker-fail')) -Credential $Credential -Body @{
        jobId = $JobId.ToString()
        code = $Code
        summary = $Summary
        retryable = $Retryable
    } -Transport $Transport
}

Export-ModuleMember -Function Get-SidequestWorkerCredential, Set-SidequestWorkerCredential, Get-SidequestOffer, Claim-SidequestJob, Send-SidequestHeartbeat, Submit-SidequestResult, Fail-SidequestJob

