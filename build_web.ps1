param(
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Template,
    [Parameter(Mandatory)][string]$Wasm,
    [Parameter(Mandatory)][string]$Stage,
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$site = Join-Path $PSScriptRoot 'web'
$Stage = [IO.Path]::GetFullPath($Stage)
$Godot = (Resolve-Path -LiteralPath $Godot).ProviderPath
$Template = (Resolve-Path -LiteralPath $Template).ProviderPath.Replace('\','/')
$Wasm = (Resolve-Path -LiteralPath $Wasm).ProviderPath

& $Python (Join-Path $PSScriptRoot 'tools/stage_release.py') web $Stage
if ($LASTEXITCODE -ne 0) { throw 'Staging failed.' }
Copy-Item -LiteralPath $Wasm -Destination (Join-Path $Stage 'bin/voxcore.wasm')
# The Windows editor loads the host library when importing the Web project.
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'game/bin/voxcore.dll') -Destination (Join-Path $Stage 'bin/voxcore.dll')
}
$preset = Join-Path $Stage 'export_presets.cfg'
$config = Get-Content -LiteralPath $preset -Raw
$pattern = '(?s)(\[preset\.1\.options\].*?custom_template/release=)""'
if ($config -notmatch $pattern) { throw 'Web export preset missing.' }
$config = [regex]::Replace($config, $pattern, [Text.RegularExpressions.MatchEvaluator] {
    param($match) $match.Groups[1].Value + '"' + $Template + '"'
})
Set-Content -LiteralPath $preset -Value $config -Encoding utf8

$output = Join-Path $site 'game-build'
New-Item -Path $output -ItemType Directory -Force | Out-Null
& $Godot --headless --path $Stage --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
& $Godot --headless --path $Stage --export-release Web (Join-Path $output 'index.html')
if ($LASTEXITCODE -ne 0) { throw 'Godot Web export failed.' }
Get-ChildItem -LiteralPath $output -File | Select-Object Name, Length
