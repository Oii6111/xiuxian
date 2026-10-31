param([string]$Godot = $env:GODOT4)
$ErrorActionPreference = 'Stop'
$backendRepo = Split-Path -Parent $PSScriptRoot
Push-Location (Join-Path $backendRepo 'server')
try {
    & npm.cmd run check
    if ($LASTEXITCODE -ne 0) { throw 'Backend build or tests failed.' }
    & npm.cmd run demo
    if ($LASTEXITCODE -ne 0) { throw 'Local integration demo failed.' }
    if (-not $Godot) { throw 'Set GODOT4 or pass -Godot to complete Godot verification.' }
    & npm.cmd run test:godot -- $Godot
    if ($LASTEXITCODE -ne 0) { throw 'Godot HTTP/WebSocket integration failed.' }
} finally { Pop-Location }
& (Join-Path $PSScriptRoot 'test_kernel.ps1') -Godot $Godot
Write-Output 'C backend and kernel integration checks passed.'
