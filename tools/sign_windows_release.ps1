[CmdletBinding(DefaultParameterSetName = 'Sign')]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$SdkTools,
    [Parameter(Mandatory, ParameterSetName = 'Sign')]
    [ValidatePattern('^[0-9a-fA-F]{40}$')][string]$CertificateThumbprint,
    [Parameter(Mandatory, ParameterSetName = 'Sign')][uri]$TimestampUrl,
    [Parameter(Mandatory, ParameterSetName = 'Prepare')][switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackageDirectory).Path
$exe = Join-Path $package 'BREAKPOINT.exe'
$pck = Join-Path $package 'BREAKPOINT.pck'
$manifestTool = Join-Path $SdkTools 'mt.exe'
$signTool = Join-Path $SdkTools 'signtool.exe'
if (!(Test-Path -LiteralPath $exe -PathType Leaf) -or !(Test-Path -LiteralPath $pck -PathType Leaf)) {
    throw 'Use the staging directory of a Windows export with a separate BREAKPOINT.pck.'
}
if ($PSCmdlet.ParameterSetName -eq 'Sign') {
    if (!$TimestampUrl.IsAbsoluteUri -or $TimestampUrl.Scheme -ne 'https') {
        throw 'Use the HTTPS timestamp service of the signing provider.'
    }
    if (!(Test-Path -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint")) {
        throw 'The publisher code-signing certificate is missing from the Personal store of the current user.'
    }
}

function Invoke-SdkTool {
    param([string]$Tool, [string[]]$Arguments)
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool exited with code $LASTEXITCODE" }
}

$manifestFile = Join-Path ([IO.Path]::GetTempPath()) ("breakpoint-" + [guid]::NewGuid() + ".manifest")
try {
    $resource = "$exe;#1"
    Invoke-SdkTool $manifestTool @('-nologo', "-inputresource:$resource", "-out:$manifestFile")
    $manifest = [xml](Get-Content -LiteralPath $manifestFile -Raw)
    $level = $manifest.SelectSingleNode("//*[local-name()='requestedExecutionLevel']")
    if ($null -eq $level) {
        if ((Get-AuthenticodeSignature -LiteralPath $exe).Status -ne 'NotSigned') {
            throw 'The elevation manifest must be added before the executable is signed.'
        }
        $namespace = 'urn:schemas-microsoft-com:asm.v3'
        $trust = $manifest.CreateElement('trustInfo', $namespace)
        $security = $manifest.CreateElement('security', $namespace)
        $privileges = $manifest.CreateElement('requestedPrivileges', $namespace)
        $level = $manifest.CreateElement('requestedExecutionLevel', $namespace)
        $level.SetAttribute('level', 'asInvoker')
        $level.SetAttribute('uiAccess', 'false')
        [void]$privileges.AppendChild($level)
        [void]$security.AppendChild($privileges)
        [void]$trust.AppendChild($security)
        [void]$manifest.DocumentElement.AppendChild($trust)
        $manifest.Save($manifestFile)
        Invoke-SdkTool $manifestTool @('-nologo', '-manifest', $manifestFile, "-outputresource:$resource")
        Invoke-SdkTool $manifestTool @('-nologo', "-inputresource:$resource", "-out:$manifestFile")
        $manifest = [xml](Get-Content -LiteralPath $manifestFile -Raw)
        $level = $manifest.SelectSingleNode("//*[local-name()='requestedExecutionLevel']")
    }
    if ($null -eq $level -or $level.GetAttribute('level') -ne 'asInvoker' -or $level.GetAttribute('uiAccess') -ne 'false') {
        throw 'The export does not declare normal user privileges.'
    }
    Write-Output 'BREAKPOINT.exe declares asInvoker with uiAccess disabled.'
} finally {
    if (Test-Path -LiteralPath $manifestFile) { Remove-Item -LiteralPath $manifestFile }
}

if ($PSCmdlet.ParameterSetName -eq 'Sign') {
    $binaries = Get-ChildItem -LiteralPath $package -File |
        Where-Object { $_.Extension -in '.exe', '.dll' }
    foreach ($binary in $binaries) {
        Invoke-SdkTool $signTool @('sign', '/sha1', $CertificateThumbprint, '/fd', 'SHA256',
            '/tr', $TimestampUrl.AbsoluteUri, '/td', 'SHA256', $binary.FullName)
        Invoke-SdkTool $signTool @('verify', '/pa', '/tw', $binary.FullName)
        $signature = Get-AuthenticodeSignature -LiteralPath $binary.FullName
        if ($signature.Status -ne 'Valid' -or !$signature.TimeStamperCertificate -or
            $signature.SignerCertificate.Thumbprint -ne $CertificateThumbprint) {
            throw "Expected publisher signature and trusted timestamp on $($binary.Name)."
        }
    }
}
