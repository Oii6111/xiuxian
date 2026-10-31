param([string]$Godot = $env:GODOT4, [switch]$Graphical)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Godot) { $Godot = 'D:\Projects\Codex\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
& (Join-Path $PSScriptRoot 'test_combat_lifecycle.ps1') -Godot $Godot -Graphical:$Graphical
$work = Join-Path $repo 'work/pr4-integration'
$env:APPDATA = Join-Path $work 'appdata'
$env:XIUXIAN_PIXEL_CAMPAIGN_SAVE_DIR = Join-Path $work 'pixel-save'
New-Item -ItemType Directory -Force -Path $work, $env:APPDATA, $env:XIUXIAN_PIXEL_CAMPAIGN_SAVE_DIR | Out-Null
foreach ($name in @('pr4_challenge_rules_test', 'pr4_challenge_duel_test', 'pr4_boss_design_test', 'pr4_boss_duel_test', 'pr4_a_migration_test', 'equipment_test', 'family_test', 'action_progression_test', 'corridor_test', 'gameplay_test', 'pixel_campaign_rules_test', 'pixel_battle_test')) {
    $log = Join-Path $work ($name + '.log')
    $testOutput = @(& $Godot --headless --path $repo --script "res://tests/$name.gd" --quit-after 1800 --log-file $log -- --preview --skip-intro --kernel-ephemeral 2>&1)
    $code = $LASTEXITCODE
    $testOutput | Where-Object { "$_" -match 'RESULT|TESTS:|assertions|SCRIPT ERROR|^ERROR:' -and "$_" -notmatch 'PURE_FIGHT_RESULTS' } | ForEach-Object { Write-Output $_ }
    $errors = @($testOutput | Where-Object { "$_" -match 'SCRIPT ERROR|^ERROR:|FAIL:' })
    if ($code -ne 0 -or $errors.Count -gt 0) { throw "$name failed. See $log" }
    if (-not (Test-Path -LiteralPath $log)) { throw "$name did not produce a log." }
    if (-not (Select-String -LiteralPath $log -Pattern 'RESULT: PASS|assertions; 0 failures|TESTS: \d+ passed, 0 failed' -Quiet)) {
        throw "$name did not complete successfully."
    }
}
if ($Graphical) {
    foreach ($name in @('pr4_a_render_test', 'pr4_boss_render_test', 'pr4_challenge_render_test')) {
        $log = Join-Path $work ($name + '.log')
        $renderOutput = @(& $Godot --path $repo --rendering-method gl_compatibility --script "res://tests/$name.gd" --quit-after 3600 --log-file $log -- --preview --skip-intro --kernel-ephemeral 2>&1)
        $renderCode = $LASTEXITCODE
        $renderOutput | Where-Object { "$_" -match 'TEST:|SCRIPT ERROR:|^ERROR:|FAIL:' } | ForEach-Object { Write-Output $_ }
        if ($renderCode -ne 0 -or @($renderOutput | Where-Object { "$_" -match 'SCRIPT ERROR:|^ERROR:|FAIL:' }).Count -gt 0 -or -not (Select-String -LiteralPath $log -Pattern 'TEST: .*; 0 failures' -Quiet)) {
            throw "Graphical verification $name failed. See $log"
        }
    }
}
Write-Output 'PR4 and A integration checks passed.'
