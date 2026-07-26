param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\\..\\..")).Path,
  [string]$GodotExe = "",
  [string]$ChessPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
  $GodotExe = Join-Path $RepoRoot "Godot_v4.6.2-stable_win64_console.exe"
}
if ([string]::IsNullOrWhiteSpace($ChessPath)) {
  $ChessPath = Join-Path $RepoRoot "chess"
}

if (-not (Test-Path -LiteralPath $GodotExe)) {
  throw "Godot exe not found: $GodotExe"
}
if (-not (Test-Path -LiteralPath $ChessPath)) {
  throw "Chess path not found: $ChessPath"
}

function Run-Step([string]$Name, [scriptblock]$Cmd) {
  Write-Host ""
  Write-Host "== $Name ==" -ForegroundColor Cyan
  & $Cmd
  if ($LASTEXITCODE -ne 0) {
    throw "Step failed ($Name). exit_code=$LASTEXITCODE"
  }
}

Run-Step "begin_capture_session" { & $GodotExe --path $ChessPath -s "res://agent_debug/scripts/begin_capture_session.gd" }
Run-Step "capture_screenshot"    { & $GodotExe --path $ChessPath -s "res://agent_debug/scripts/capture_screenshot.gd" }
Run-Step "run_chess_tests"       { & $GodotExe --headless --path $ChessPath -s "res://agent_debug/scripts/run_chess_tests.gd" }
Run-Step "run_ui_chess_tests"    { & $GodotExe --headless --path $ChessPath -s "res://agent_debug/scripts/run_ui_chess_tests.gd" }
Run-Step "stockfish_smoke"       { & $GodotExe --headless --path $ChessPath -s "res://agent_debug/scripts/run_stockfish_bestmove_smoke_test.gd" }

Write-Host ""
Write-Host "All common verification steps passed." -ForegroundColor Green

