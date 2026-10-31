param([string]$Godot = $env:GODOT4)
$ErrorActionPreference = 'Stop'
$kernelRepo = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $kernelCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($kernelCommand) { $Godot = $kernelCommand.Source }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    throw 'Set GODOT4 or pass -Godot with a Godot 4.7 executable.'
}
$kernelWork = Join-Path $kernelRepo 'work/kernel'
New-Item -ItemType Directory -Force -Path $kernelWork | Out-Null
$kernelLog = Join-Path $kernelWork 'tests.log'
# Use an in-memory Autoload; file adapter tests only write under work/kernel/.
& $Godot --headless --path $kernelRepo --script res://tests/kernel_test.gd --quit-after 600 --log-file $kernelLog -- --kernel-ephemeral
$kernelExitCode = $LASTEXITCODE
$kernelErrors = @(Select-String -LiteralPath $kernelLog -Pattern 'SCRIPT ERROR:|^ERROR:|FAIL:')
# Report the Windows CA-store warning separately; these checks do not use TLS.
$kernelCertificateError = 'ERROR: Failed to read the root certificate store.'
$kernelFailures = @($kernelErrors | Where-Object { $_.Line.Trim() -ne $kernelCertificateError })
if ($kernelErrors.Count -ne $kernelFailures.Count) {
    Write-Warning 'Godot cannot read the Windows root certificate store. Offline checks continue; HTTPS remains unverified.'
}
if ($kernelExitCode -ne 0 -or $kernelFailures.Count -gt 0) {
    throw "Kernel tests failed. See $kernelLog"
}
if (-not (Select-String -LiteralPath $kernelLog -Pattern 'KERNEL_TEST: .*; 0 failures' -Quiet)) {
    throw 'Kernel tests did not finish.'
}
Write-Output 'Kernel checks passed.'
