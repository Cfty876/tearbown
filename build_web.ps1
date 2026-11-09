param(
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Template,
    [Parameter(Mandatory)][string]$Wasm,
    [Parameter(Mandatory)][string]$Stage
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'game'
$site = Join-Path $PSScriptRoot 'web'
$Stage = [IO.Path]::GetFullPath($Stage)
if ($Stage -eq $source -or $Stage.StartsWith($source + [IO.Path]::DirectorySeparatorChar)) {
    throw 'Use a separate staging directory.'
}
$Godot = (Resolve-Path -LiteralPath $Godot).ProviderPath
$Template = (Resolve-Path -LiteralPath $Template).ProviderPath.Replace('\','/')
$Wasm = (Resolve-Path -LiteralPath $Wasm).ProviderPath
New-Item -ItemType Directory -Path $Stage -Force | Out-Null
Get-ChildItem -LiteralPath $source -Force | Where-Object Name -ne '.godot' |
    Copy-Item -Destination $Stage -Recurse -Force
Copy-Item -LiteralPath $Wasm -Destination (Join-Path $Stage 'bin\voxcore.wasm') -Force
Copy-Item -LiteralPath (Join-Path $site 'shell.html') -Destination (Join-Path $Stage 'ui\web_shell.html') -Force
$preset = Join-Path $Stage 'export_presets.cfg'
$config = Get-Content -LiteralPath $preset -Raw
$section = '[preset.1.options]'
$prefix, $webOptions = $config.Split($section, 2, [StringSplitOptions]::None)
$webOptions = $webOptions.Replace('custom_template/release=""', 'custom_template/release="' + $Template + '"')
Set-Content -LiteralPath $preset -Value ($prefix + $section + $webOptions) -Encoding utf8
$output = Join-Path $site 'public\index.html'
& $Godot --headless --path $Stage --export-release Web $output
if ($LASTEXITCODE -ne 0) { throw "Web export failed ($LASTEXITCODE)" }
Get-ChildItem -LiteralPath (Join-Path $site 'public') -File | Select-Object Name, Length
