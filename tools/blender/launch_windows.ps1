param(
    [string]$BlenderPath = 'D:\Projects\Codex\tools\blender\blender-4.5.14-windows-x64\blender.exe',
    [string]$ProfileRoot = 'D:\Projects\Codex\tools\blender\profile'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $BlenderPath)) {throw 'Blender not installed; see docs/BLENDER_PIPELINE.md.'}
$env:BLENDER_USER_CONFIG = Join-Path $ProfileRoot 'config'
$env:BLENDER_USER_SCRIPTS = Join-Path $ProfileRoot 'scripts'
$env:APPDATA = 'D:\Projects\Codex\tools\blender\runtime'
$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$env:TEMP = Join-Path $repoDir 'work\blender-mcp\temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
# Dedicated factory scene: avoids modifying a user's open .blend document.
Start-Process -FilePath $BlenderPath -ArgumentList @('--factory-startup','--python',('"'+(Join-Path $PSScriptRoot 'bootstrap.py')+'"')) -WindowStyle Hidden
Write-Output 'Portable Blender launched. MCP addon auto-starts on 127.0.0.1:9876.'
