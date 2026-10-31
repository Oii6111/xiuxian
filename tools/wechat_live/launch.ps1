$ErrorActionPreference = 'Stop'
$wechatDemoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$wechatPython = (Get-Command python -ErrorAction Stop).Source
$wechatGodotCandidates = @($env:GODOT_BIN, (Join-Path $wechatDemoRoot 'work\runtime\Godot_v4.7.2-stable_win64.exe'), 'F:\Godot_v4.7.2-stable_win64.exe')
$wechatGodot = $wechatGodotCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $wechatGodot) {
    throw '找不到 Godot 4.7.2。请把引擎放到 work\runtime，或设置 GODOT_BIN 后重试。'
}
Push-Location -LiteralPath $wechatDemoRoot
try {
    $wechatPlaytestProject = Join-Path $wechatDemoRoot 'work\playtest-project'
    if (-not (Test-Path -LiteralPath (Join-Path $wechatPlaytestProject 'project.godot'))) { $wechatPlaytestProject = $wechatDemoRoot }
    & $wechatPython '-B' (Join-Path $PSScriptRoot 'run.py') '--godot' $wechatGodot '--project' $wechatPlaytestProject
    if ($LASTEXITCODE -ne 0) { throw '现场服务未正常结束，请检查终端提示及 work\wechat-live\gateway.log。' }
} finally {
    Pop-Location
}
