# Agent 디버깅: 유닛 + UI 테스트 후 로그를 agent_debug/logs/ 에 남김.
param(
    [string]$GodotExe = "d:\Cursor\Godot\Godot_v4.6.2-stable_win64_console.exe",
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = "Stop"
$logDir = Join-Path $PSScriptRoot "logs"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir "run_$stamp.log"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
function Run-Test([string]$ScriptRel) {
    & $GodotExe --headless --path $ProjectDir -s "res://agent_debug/scripts/$ScriptRel" 2>&1 | Tee-Object -FilePath $logFile -Append
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Run-Test "run_chess_tests.gd"
Run-Test "run_ui_chess_tests.gd"
Write-Host "Log: $logFile"
