# 인수인계 — Chess (Godot) + CPU(Stockfish UCI)

## 한 줄 요약

체스 UI/룰 엔진/자동 테스트 + **Stockfish(UCI) CPU 대전**까지 구현 완료.  
현재 CPU 엔진 통신은 **persistent UCI** 방식으로 동작한다(Stockfish 1회 실행 + 파이프 통신).

## 프로젝트 위치

- **`<chess>`**: Godot `--path`에 넣는 **chess 프로젝트 루트** 디렉터리(`project.godot`가 있는 폴더). 아래 `d:\...` 는 개발 예시일 뿐이다.
- 절대경로 예: `d:\Cursor\Godot\chess`
- 메인: `main.gd`, `main.tscn`
- 규칙 엔진: `scripts/chess_state.gd`
- 기물 SVG 세트: `assets/pieces/cburnett/*.svg` (런타임 래스터라이즈)

## Godot 실행 파일·저장소 레이아웃(검증 스크립트)

- `agent_debug/scripts/run_common_verify.ps1` 기본값:
  - **Godot**: `<저장소 루트>/Godot_v4.6.2-stable_win64_console.exe` (`chess`의 **부모** 폴더 = `chess/../`)
  - **chess 경로**: `<저장소 루트>/chess`
- 다른 위치의 Godot/chess를 쓰려면 스크립트의 `-GodotExe`, `-ChessPath` 인자로 덮어쓴다.

## Stockfish(UCI) 바이너리 경로

- 기본 탐색: `scripts/engine/engine_settings.gd` 의 `EngineSettings.find_default_engine_path()` / `default_engine_candidates()`
  - 우선 `res://engine/stockfish/stockfish.exe` (에디터/개발에서 `ProjectSettings.globalize_path`로 절대경로화)
  - 없으면 실행 파일 옆 `engine/stockfish/stockfish.exe` (보내기/포터블)
- 둘 다 없으면 빈 문자열 → CPU/엔진 스모크는 환경에 따라 스킵·실패할 수 있으니 **바이너리 배치**를 먼저 확인한다.

## 현재 구조(중요)

- Godot ↔ (persistent pipe) ↔ Stockfish(UCI, stdin/stdout)
  - runner: `scripts/engine/uci_persistent_runner.gd`
  - 엔진 컨트롤러: `scripts/engine/uci_engine_controller.gd`

## CPU/설정 UI(현재)

- 상단 바:
  - `CPU: ON/OFF`
  - `플레이어=백/흑` (CPU는 항상 상대편)
  - `ENGINE: CONNECTING/READY/ERROR/-`
  - `설정` 팝업:
    - `Skill (0..20)`, `movetime(ms)`, `MaxDepth`(0이면 depth 제한 없음)
    - `레벨 1~8` (lichess 스타일 프리셋) — 선택 시 위 값들도 동기화
    - (개발용) `엔진 로그 표시` 토글: `info depth/score/pv` 요약 최근 N줄 표시(기본 OFF)

## 보드 방향(Flip)

- 플레이어가 `흑`이면 **흑이 아래**로 보이도록 보드를 180도 뒤집어 표시한다.
- `main.gd`의 `_draw()`는 `_rect_for_square()` 기반으로 그려 flip이 타일/기물까지 일관되게 적용되도록 되어있다.

## 검증·캡처 (명령 전문은 두지 않음)

**Godot CLI, 공통 검증 PowerShell 한 줄, `[Verify]` 키워드, `real_click_e2e` pip/실행**은 전부 **`CHECKLIST.md`** 에만 적어 두었다. 여기서는 반복하지 않는다.

- 캡처 산출물: `agent_debug/artifacts/sessions/<세션ID>/` · 세션 힌트 `agent_debug/artifacts/latest_capture.txt`
- 스크린샷 캡처 시 **`--headless` 사용 금지** (동일 규칙은 `CHECKLIST`에도 있다)
- `run_common_verify.ps1`의 Godot/chess 기본 경로 전제는 위 **「Godot 실행 파일·저장소 레이아웃」** 절 참고

## 다음 에이전트가 할 일(우선순위)

- **NEXT**: `CHECKLIST.md`
- **이 폴더 문서 목차·플레이북 분기**: `README.md`

## 최근 추가/변경(중요) — 편집/Undo/캡처/실클릭 E2E

### Undo(무르기)

- 상단 바에 `무르기` 버튼 + `Ctrl+Z` 추가
- 상태 스냅샷 기반으로 되돌리기 구현(일반/앙파상/프로모션 포함)

### 보드 편집기(Setup Position)

- 상단 바에 `편집` 버튼 추가
- 팝업에서 기물 팔레트로 배치/삭제, 턴/캐슬링/EP/카운터 설정, FEN 복사/불러오기, 적용/취소 지원

### 캡처 스크립트 확장

- `res://agent_debug/scripts/capture_screenshot.gd`
  - `--press=<노드경로>`: 캡처 전 버튼 pressed 이벤트 실행
  - `--uci="..."`: UCI 수순 자동 클릭 후 캡처
  - `--fen="..."`: FEN 세팅 후 캡처

## “실제 클릭” 기반 E2E(유저 클릭 유사) 자동화

목표: Godot이 좌표/캡처를 제공하고, Python(pyautogui)이 OS 레벨 “실제 마우스 클릭”을 수행한 뒤, Godot이 뷰포트 캡처 PNG를 저장한다.

- Godot 드라이버: `res://agent_debug/scripts/ui_remote_driver.gd`
  - TCP 로컬 서버로 `targets`, `capture`, `calib_points`, `mouse_pos`, `set_fen` 제공
  - 팝업(편집 UI) 타겟은 ASCII alias(`btn_clear`, `btn_apply` 등)도 제공
- Python 러너: `chess/agent_debug/python/remote_click_capture.py`
  - 클릭 1번당 PNG 1장(step_XX_*) 저장
  - 테스트 시작 전에 캘리브레이션 수행(affine 보정값 출력)
- 의존성·실행: `CHECKLIST.md`의 **`[Verify]` → `real_click_e2e`** 절

### 좌표·팝업(현재 구현 요약)

- 드라이버 루트 `Window`에서 **`gui_embed_subwindows = true`** 로 서브윈도우를 임베드한다(일반 `main.tscn` 실행과 별개·**이 스크립트로 띄울 때만**).
- 팝업 컨트롤 스크린 좌표: **`popup.is_embedded()`** 이면 `DisplayServer.window_get_position()` + `popup.position` + 버튼 `get_global_rect()` 중심; 아니면 `DisplayServer.window_get_position(popup.get_window_id())` + 중심.
- 한 환경에서 `remote_click_capture.py` 전체 플로우가 통과한 상태이나, **OS/DPI/멀티 모니터**에서는 재검증이 필요하다.

### 남은 권장 액션

- 다른 OS/DPI에서 `real_click_e2e` 재검증.
- 임베드가 적용되지 않는 빌드/플랫폼이면 `is_embedded()`가 `false`인 경로(`window_get_position(popup_id)`)를 실기기에서 점검한다.

