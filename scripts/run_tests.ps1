param([string]$GodotPath = $env:GODOT4)
$ErrorActionPreference = 'Stop'
$repoDir = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $candidate = Get-Command godot -ErrorAction SilentlyContinue
    if ($candidate) { $GodotPath = $candidate.Source }
}
if (-not $GodotPath) { $GodotPath = 'D:\Projects\Codex\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Specify -GodotPath or set GODOT4 to a Godot 4 executable.' }
$logDir = Join-Path $repoDir 'work\twenty-boss'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
# Keep editor settings and tool-generated data inside the D-drive project.
$priorAppData = $env:APPDATA
$env:APPDATA = Join-Path $logDir 'appdata'
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
try {
    & $GodotPath --headless --path $repoDir --editor --import --quit --log-file (Join-Path $logDir 'import.log')
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    & $GodotPath --headless --path $repoDir --script res://tests/campaign_test.gd --log-file (Join-Path $logDir 'campaign-tests.log') -- --campaign-test
    if ($LASTEXITCODE -ne 0) { throw 'Campaign tests failed.' }
    & $GodotPath --headless --path $repoDir --script res://tests/gameplay_test.gd --log-file (Join-Path $logDir 'legacy-tests.log') -- --preview --skip-intro
    if ($LASTEXITCODE -ne 0) { throw 'Legacy regression tests failed.' }

    & $GodotPath --headless --path $repoDir --script res://tests/blender_assets_test.gd --log-file (Join-Path $logDir 'blender-assets-tests.log')
    if ($LASTEXITCODE -ne 0) { throw 'Blender asset integration tests failed.' }
} finally {
    $env:APPDATA = $priorAppData
}
