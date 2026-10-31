param([string]$Godot = $env:GODOT4, [switch]$Preview)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Godot) { $Godot = 'D:\Projects\Codex\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $Godot)) { throw 'Pass -Godot with your Godot executable.' }
$env:APPDATA = Join-Path $repo 'work/play-a/appdata'
$env:XIUXIAN_A_OUTPUT_DIR = Join-Path $repo 'outputs/combat-lifecycle'
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:XIUXIAN_A_OUTPUT_DIR | Out-Null
& $Godot --headless --path $repo --editor --import --quit --log-file (Join-Path $repo 'work/play-a/import.log')
if ($LASTEXITCODE -ne 0) { throw 'Project import failed.' }
$arguments = @('--path', $repo, '--scene', 'res://scenes/main.tscn', '--log-file', (Join-Path $repo 'work/play-a/play.log'), '--', '--kernel-ephemeral')
if ($Preview) { $arguments += @('--preview', '--skip-intro') }
& $Godot @arguments
exit $LASTEXITCODE
