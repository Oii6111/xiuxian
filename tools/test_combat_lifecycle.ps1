param([string]$Godot = $env:GODOT4, [switch]$Graphical)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { $Godot = $command.Source }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    throw 'Set GODOT4 or pass -Godot with a Godot 4.7 executable.'
}
$env:APPDATA = Join-Path $repo 'work/a-test-appdata'
$env:XIUXIAN_A_OUTPUT_DIR = Join-Path $repo 'outputs/combat-lifecycle'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
$work = Join-Path $repo 'work/combat-lifecycle'
New-Item -ItemType Directory -Force -Path $work | Out-Null
# Each suite must print its completion marker with zero failures.
$suites = @(
    'kernel_test|KERNEL_TEST: .*; 0 failures',
    'combat_rules_test|COMBAT_RULES_TEST: .*; 0 failures',
    'combat_module_test|COMBAT_MODULE_TEST: .*; 0 failures',
    'combat_level_test|COMBAT_LEVEL_TEST: .*; 0 failures',
    'combat_boss_level_test|COMBAT_BOSS_LEVEL_TEST: .*; 0 failures',
    'boss_fight_test|BOSS_FIGHT_TEST: .*; 0 failures',
    'boss_minions_test|BOSS_MINIONS_TEST: .*; 0 failures',
    'boss_minion_fight_test|BOSS_MINION_FIGHT_TEST: .*; 0 failures',
    'party_ai_test|PARTY_AI_TEST: .*; 0 failures',
    'boss_party_test|BOSS_PARTY_TEST: .*; 0 failures',
    'combat_party_level_test|COMBAT_PARTY_LEVEL_TEST: .*; 0 failures',
    'lifecycle_rules_test|LIFECYCLE_RULES_TEST: .*; 0 failures',
    'lifecycle_module_test|LIFECYCLE_MODULE_TEST: .*; 0 failures',
    'tribulation_platform_test|TRIBULATION_PLATFORM_TEST: .*; 0 failures',
    'demo_hub_test|DEMO_HUB_TEST: .*; 0 failures',
    'demo_authority_test|DEMO_AUTHORITY_TEST: .*; 0 failures',
    'seclusion_flow_test|SECLUSION_FLOW_TEST: .*; 0 failures',
    'a_acceptance_test|A_ACCEPTANCE_TEST: .*; 0 failures',
    'a_services_test|A_SERVICES_TEST: .*; 0 failures'
)
# A fresh checkout has no import cache; scene-based tests need one import pass.
$importLog = Join-Path $work 'import.log'
& $Godot --headless --path $repo --editor --import --quit --log-file $importLog | Out-Null
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) {
    throw "Import failed. See $importLog"
}
$certificateError = 'ERROR: Failed to read the root certificate store.'
foreach ($entry in $suites) {
    $name, $marker = $entry.Split('|', 2)
    $log = Join-Path $work ($name + '.log')
    $suiteOutput = @(& $Godot --headless --path $repo --script "res://tests/$name.gd" --quit-after 600 --log-file $log -- --kernel-ephemeral 2>&1)
    $exitCode = $LASTEXITCODE
    $suiteOutput | ForEach-Object { Write-Output $_ }
    $shutdownErrors = @($suiteOutput | Where-Object { "$_" -match 'SCRIPT ERROR:|^ERROR:|FAIL:' -and "$_".Trim() -ne $certificateError })
    if ($shutdownErrors.Count -gt 0) { throw "$name reported a process error." }
    if (-not (Test-Path -LiteralPath $log)) { throw "No log written for $name" }
    $errors = @(Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|^ERROR:|FAIL:' | Where-Object { $_.Line.Trim() -ne $certificateError })
    if ($exitCode -ne 0 -or $errors.Count -gt 0) { throw "$name failed. See $log" }
    if (-not (Select-String -LiteralPath $log -Pattern $marker -Quiet)) { throw "$name did not finish." }
    Write-Output "$name passed."
}
if ($Graphical) {
    $renderLog = Join-Path $work 'render.log'
    $renderOutput = @(& $Godot --path $repo --rendering-method gl_compatibility --script res://tests/a_render_test.gd --quit-after 1500 --log-file $renderLog -- --kernel-ephemeral 2>&1)
    $renderExit = $LASTEXITCODE
    $renderOutput | ForEach-Object { Write-Output $_ }
    if (@($renderOutput | Where-Object { "$_" -match 'SCRIPT ERROR:|^ERROR:|FAIL:' }).Count -gt 0) { throw 'Rendered process reported an error.' }
    if ($renderExit -ne 0 -or (Select-String -LiteralPath $renderLog -Pattern 'SCRIPT ERROR:|^ERROR:|FAIL:' -Quiet) -or -not (Select-String -LiteralPath $renderLog -Pattern 'A_RENDER_TEST: .*; 0 failures' -Quiet)) {
        throw "Rendered verification failed. See $renderLog"
    }
}
Write-Output 'Combat and lifecycle checks passed.'
