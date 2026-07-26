agent_debug/ — Agent·CI 디버깅 전용 (게임 본체와 분리)

next_agent/HANDOFF.md — 새 에이전트 인수인계(현재 상태·명령·파일)
next_agent/CHECKLIST.md — NEXT + 공통 검증 + “시각 검증 루프 (Rule: ui-visual)” 등 Rule/Verify 단일 소스
next_agent/README.md — 문서 목차·플레이북 분기(§4)

_agent_tools/ (저장소 루트) — QA·요구사항·기능·폴리시·UI 시각 게이트 등 역할별 플레이북 공통본

scripts/     헤드리스로 돌리는 GDScript
  run_chess_tests.gd       규칙 엔진 테스트
  run_ui_chess_tests.gd    UI 클릭 시뮬레이션 테스트
  capture_screenshot.gd    스크린샷 PNG 저장

artifacts/   산출물 (스크린샷 등). 기본: game_screenshot.png
logs/        Godot 표준 출력 리다이렉트용 (예: run_tests.ps1에서 사용)

예시 (Godot 실행 파일 경로는 본인 환경에 맞게):
  Godot --headless --path <chess폴더> -s res://agent_debug/scripts/run_chess_tests.gd
  Godot --headless --path <chess폴더> -s res://agent_debug/scripts/run_ui_chess_tests.gd
  Godot --path <chess폴더> -s res://agent_debug/scripts/capture_screenshot.gd

로그 저장 예시 (PowerShell):
  Godot ... 2>&1 | Tee-Object -FilePath agent_debug/logs/godot_last_run.log
