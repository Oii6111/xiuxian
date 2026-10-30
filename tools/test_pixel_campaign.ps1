param([string]$Godot = $env:GODOT4, [switch]$Graphical)
$ErrorActionPreference = 'Stop'
$pixelRepo = Split-Path -Parent $PSScriptRoot
if (-not $Godot) { $Godot = 'D:\Projects\Codex\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $Godot)) { throw 'Set GODOT4 or pass -Godot with a Godot 4.7.2 executable.' }
$pixelWork = Join-Path $pixelRepo 'work\pixel-campaign'
New-Item -ItemType Directory -Force -Path $pixelWork | Out-Null
$env:APPDATA = Join-Path $pixelRepo 'work\appdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
$env:XIUXIAN_PIXEL_CAMPAIGN_SAVE_DIR = Join-Path $pixelWork 'isolated-profile'
& $Godot --headless --path $pixelRepo --editor --import --quit --log-file (Join-Path $pixelWork 'import.log')
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
foreach ($pixelSuite in @('gameplay_test', 'pixel_campaign_rules_test', 'pixel_battle_test')) {
    $pixelLog = Join-Path $pixelWork ($pixelSuite + '.log')
    & $Godot --headless --path $pixelRepo --script "res://tests/$pixelSuite.gd" --log-file $pixelLog -- --preview --skip-intro
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $pixelLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) { throw "Failed: $pixelSuite (see $pixelLog)" }
}
if ($Graphical) {
    $pixelLog = Join-Path $pixelWork 'input-playtest.log'
    & $Godot --path $pixelRepo --rendering-method gl_compatibility --script res://tests/pixel_world_input_test.gd --log-file $pixelLog -- --preview --skip-intro
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $pixelLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) { throw "Rendered input playtest failed (see $pixelLog)" }
}
Write-Output 'Pixel campaign checks passed.'
