# Chess (Godot) — NEXT 체크리스트(미완료만)

이 문서는 **앞으로 할 일(NEXT)** 와 **검증·`[Rule]` / `[Verify]` 정의**를 모은다.

- **유지되는 섹션**(삭제하지 않음): `공통 검증(작업 후 필수)`, `동작 검증 루프 (Rule: code-loop)`, **`시각 검증 루프 (Rule: ui-visual)`**, `표기 규칙` 및 그 아래 `[Verify]` 목록. **`## 현재 남은 NEXT`** 의 체크박스만 완료 시 이 문서에서 삭제한다.
- **항목 작성 규칙**: 각 NEXT(체크박스) 옆에 반드시 **`[Rule: ...]`**, **`[Verify: ...]`** 를 붙인다.

## 공통 검증(작업 후 필수)

```text
powershell -NoProfile -ExecutionPolicy Bypass -File "chess/agent_debug/scripts/run_common_verify.ps1"
```

---

## 동작 검증 루프 (Rule: code-loop)

`[Rule: code-loop]`가 붙은 작업을 할 때, 아래 사이클을 **목표가 만족될 때까지** 반복한다.

### 적용 범위

**기능·로직·입력·턴·CPU·엔진·테스트** 등 “동작”에 영향이 있는 변경 전부. (NEXT에 `[Rule: code-loop]`가 붙은 항목과 같다.)

### 필수 참조 (경로는 `chess/` 루트 기준)

- 이 문서의 **공통 검증** 절, **표기 규칙**의 **`[Verify]`** 목록
- (UI 변경이 포함되면) `../../../_agent_tools/UI_VISUAL_GATE_AGENT.md`
- 시각 캡처·헤드리스 주의: 아래 **시각 검증 루프 (Rule: ui-visual)** 절

### 매 사이클

1. **동작 구현** — 변경 범위를 최소화하고, 한 사이클에 한 가지 목표만 처리한다.
2. **체크리스트 확인** — 이번 변경에 해당하는 NEXT(또는 해당 섹션)의 **완료 조건·주의사항**을 확인한다.
3. **동작 실행(재현)** — 최소 재현 시나리오로 실제 동작을 확인한다.
4. **검증 실행** — 위 **공통 검증** 및 필요 시 **`[Verify]`**에 적힌 스크립트를 실행한다. UI에 영향이 있으면 스크린샷(헤드리스 금지): 아래 **시각 검증 루프 (Rule: ui-visual)** 절 및 `[Verify]`의 `begin_capture_session` / `capture_screenshot` 절차.
5. **체크리스트 갱신** — 목표·완료 조건에 **만족할 수준이면** 해당 NEXT를 완료 처리한다(이 프로젝트 규칙: 완료 항목은 이 문서에서 **삭제**).
6. **불만족 시** — 실패 원인을 완료 조건·요구사항에 맞춰 좁히고 1로 돌아간다.

### 끝맺음

- 변경이 누적되기 전에, 사이클을 **작은 단위로 자주** 완료하는 것을 우선한다.
- 작업이 끝난 시점에도 관련 NEXT·완료 조건을 다시 한번 대조한다.

---

## 시각 검증 루프 (Rule: ui-visual)

`[Rule: ui-visual]`이 붙었거나, **화면/레이아웃/색/폰트** 등 눈으로 확인해야 하는 수정을 할 때는 아래 사이클을 **원하는 결과가 나올 때까지** 반복한다. (게이트·PASS/FAIL 산출물 형식은 `../../../_agent_tools/UI_VISUAL_GATE_AGENT.md`.)

### 적용 시점

- `main.gd`의 `_draw`, 색상·여백·글리프 보정
- `main.tscn`의 버튼·라벨·팝업 스타일
- 해상도·보드 크기·클릭 영역 등 **시각적 결과**가 바뀌는 모든 변경

순수 로직만 바꾸고 픽셀 결과가 동일하면 이 루프는 생략 가능하다.

### 루프 (반복 종료 조건: 스크린샷이 목표에 부합)

1. **수정** — 코드/씬을 변경한다.
2. **캡처** — 프로젝트 루트에서 Godot으로 스크립트 실행:
   ```text
   <Godot_console.exe> --path "<chess 프로젝트 절대경로>" -s "res://agent_debug/scripts/begin_capture_session.gd"
   <Godot_console.exe> --path "<chess 프로젝트 절대경로>" -s "res://agent_debug/scripts/capture_screenshot.gd"
   ```
   - 산출물: 실행마다 **새 PNG 파일**이 세션 폴더 `agent_debug/artifacts/sessions/<세션ID>/`에 생성됨(파일명에 타임스탬프 포함).
   - 콘솔 출력: `capture: saved <abs path>` 형태로 저장 경로가 출력되므로, **그 경로의 PNG를 즉시 확인**한다.
   - 세션 위치: `agent_debug/artifacts/latest_capture.txt`에 세션 폴더명이 기록된다.
   - 세션 내 확인: 해당 세션 폴더(`agent_debug/artifacts/sessions/<세션ID>/`) 안의 PNG들을 확인한다.
3. **확인** — 방금 캡처에서 생성된 PNG를 연다.
   - 에이전트: 이미지 읽기 도구로 파일을 열어 설명/내용을 검토하거나, 사용자에게 확인을 요청한다.
   - **주의:** 자동 생성된 이미지 설명은 실행마다 달라지거나, 코드와 모순(예: 동일 `rect`인데 “이중 렌더”)을 내는 경우가 있다. **판정은 로직·테스트·사용자 육안**과 교차 검증할 것.
4. **판정**
   - **목표 달성** → 루프 종료. 관련 테스트(`run_chess_tests.gd`, `run_ui_chess_tests.gd`)를 한 번 더 돌리는 것을 권장.
   - **미달** → 원인 가설 → 1로 돌아가 수정 후 다시 2~4.

### 이 프로젝트 고정 경로 (Windows 예시)

| 항목 | 경로 |
|------|------|
| 프로젝트 | `d:\Cursor\Godot\chess` (환경에 맞게 치환) |
| 캡처 스크립트 | `res://agent_debug/scripts/capture_screenshot.gd` |
| 출력 PNG | `agent_debug/artifacts/sessions/<세션ID>/game_screenshot_*.png` (매 실행마다 새 파일) |
| Godot (사용자 환경 예) | `d:\Cursor\Godot\Godot_v4.6.2-stable_win64_console.exe` |

헤드리스는 캡처에 실패할 수 있으므로 **스크린샷 뽑을 때는 `--headless`를 붙이지 않는다.**

### 목표가 모호할 때

- 사용자 요청에 **구체적 기준**을 한 줄이라도 적는다 (예: “흑 말이 8단에서 잘리지 않을 것”, “좌표는 격자 바깥”).
- 반복마다 **무엇을 고쳤는지** 짧게 메모하면 다음 라운드에서 같은 실수를 줄인다.

### 관련 스크립트

- `agent_debug/scripts/capture_screenshot.gd` — 뷰포트 → PNG
- `agent_debug/scripts/begin_capture_session.gd` — 이번 검증의 세션 폴더 생성
- `agent_debug/scripts/run_ui_chess_tests.gd` — 클릭/좌표 자동화 (픽셀 미관은 대체하지 않음)
- `agent_debug/README.txt` — 기타 Agent 명령 예시

### 요약 한 줄

> 화면을 건드렸으면 **캡처 → 이미지 확인 → 안 맞으면 수정 후 재캡처**를 목표 달성까지 반복한다.

---

## 현재 남은 NEXT

---

플레이북(`*_AGENT.md`) 이름과 “언제 쓸지”는 **`README.md` 목차 § 4**만 본다.

## 표기 규칙(각 항목 옆에 명시)

- **[Rule]**: 어떤 검증 루프를 따를지
  - `code-loop`: 위 **동작 검증 루프 (Rule: code-loop)** 절
  - `ui-visual`: 위 **시각 검증 루프 (Rule: ui-visual)** 절 (게이트: `../../../_agent_tools/UI_VISUAL_GATE_AGENT.md`)
- **[Verify]**: 작업 후 실행/확인할 항목(스크린샷/테스트/스모크). 캡처 세부는 위 **시각 검증 루프** 절과 동일하다.
  - `begin_capture_session`: `res://agent_debug/scripts/begin_capture_session.gd` 실행 → `agent_debug/artifacts/latest_capture.txt`에 **세션 폴더명** 기록
    - 확인: `agent_debug/artifacts/sessions/<세션ID>/` 폴더가 생성된다
  - `capture_screenshot`: `res://agent_debug/scripts/capture_screenshot.gd` 실행(필요 시 인자 사용) → **세션 폴더 아래에 PNG 생성**
    - 확인: (1) 콘솔의 `capture: saved ...` 경로 PNG를 즉시 열어 확인, 또는 (2) 세션 폴더에서 새로 생긴 PNG를 확인
    - 예시:
      - 백 아래: `... -s capture_screenshot.gd -- --name=white_bottom --player_side=white`
      - 흑 아래: `... -s capture_screenshot.gd -- --name=black_bottom --player_side=black`
  - `run_chess_tests`: `res://agent_debug/scripts/run_chess_tests.gd`
  - `run_ui_chess_tests`: `res://agent_debug/scripts/run_ui_chess_tests.gd`
  - `run_stockfish_bestmove_smoke_test`: `res://agent_debug/scripts/run_stockfish_bestmove_smoke_test.gd`
  - `run_direct_cpu_game_smoke_test`(선택): `res://agent_debug/scripts/run_direct_cpu_game_smoke_test.gd` (헤드리스)
  - `real_click_e2e`: “실제 클릭” 기반 E2E(유저 클릭과 유사) 검증
    - 구성:
      - Godot(좌표/캡처): `res://agent_debug/scripts/ui_remote_driver.gd`
      - Python(실클릭): `chess/agent_debug/python/remote_click_capture.py`
    - 실행:
      ```text
      python -m pip install -r "chess/agent_debug/python/requirements.txt"
      python "chess/agent_debug/python/remote_click_capture.py"
      ```
