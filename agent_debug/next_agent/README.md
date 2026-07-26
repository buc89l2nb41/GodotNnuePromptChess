# `next_agent` — 문서 목차 (이 폴더만 읽고 시작)

이 폴더는 **인수인계·할 일**과 이 목차만 둔다.  
**명령줄·`[Verify]`·`[Rule: code-loop]` / `[Rule: ui-visual]` 본문·공통 검증**은 `CHECKLIST.md` 한 곳이 소스이고, **프로젝트 맥락·구조·최근 변경**은 `HANDOFF.md` 한 곳이 소스다.  
**역할별 플레이북**(`QA_AGENT.md` 등)은 저장소 공통 폴더 **`../../../_agent_tools/`** 에만 있으며, **맡은 역할이 있을 때만** 연다.

`../../../_agent_tools/`은 여러 프로젝트가 공유하므로, **명시적인 수정 요청이 없으면 변경하지 않는다.** 공통 개선이 필요하면 이 프로젝트 문서에 “필요 이유/영향 범위”를 적고 별도 작업으로 분리한다.

**`[Rule: code-loop]` / `[Rule: ui-visual]`** 본문은 전부 위에서 말한 **`CHECKLIST.md`** 한 곳이다. 워크스페이스 `.cursor/rules/`에는 규칙 파일을 두지 않는다(예전 `.mdc` 내용은 `CHECKLIST.md`로 통합·삭제).

---

## 1. 문서 계층 (중복을 줄이기 위한 규칙)

| 계층 | 파일 | 들어가는 내용 |
|------|------|----------------|
| 맥락·상태 | `HANDOFF.md` | 한 줄 요약, 경로, 아키텍처, UI 동작 요약, 최근 변경, E2E·엔진 등 **설명** |
| 할 일·검증·`code-loop`·`ui-visual` | `CHECKLIST.md` | 미완료 NEXT, **공통 검증 1줄**, **`[Rule: code-loop]` / `[Rule: ui-visual]` 루프**, `[Verify]`·스크립트·예시 **전부** |
| 절차·플레이북 | `../../../_agent_tools/*.md` | 역할별 루프·산출물 형식. **`code-loop` / `ui-visual` 절차·검증 CLI**는 전부 `CHECKLIST.md`만 본다 |

`HANDOFF`와 `CHECKLIST`에 같은 명령을 두지 않는다.

---

## 2. 목차 (파일별 한 줄)

| 파일 | 한 줄 |
|------|--------|
| `README.md` | 이 목차 (지금 읽는 파일) |
| `HANDOFF.md` | 체스 프로젝트 **현재 상태** 인수인계 |
| `CHECKLIST.md` | **NEXT** + **`[Rule: code-loop]` / `[Rule: ui-visual]` 루프** + 검증·스크립트 **단일 모음** |
| [`QA_AGENT.md`](../../../_agent_tools/QA_AGENT.md) | 런타임 QA → 재현·증거·NEXT 환원 |
| [`REQUIREMENTS_AGENT.md`](../../../_agent_tools/REQUIREMENTS_AGENT.md) | 요구사항을 NEXT 세트로 (예산·게이트) |
| [`FEATURE_AGENT.md`](../../../_agent_tools/FEATURE_AGENT.md) | 기능 추가·확장 구현 루프 |
| [`POLISH_AGENT.md`](../../../_agent_tools/POLISH_AGENT.md) | 최소 변경 UX 폴리시 |
| [`UI_VISUAL_GATE_AGENT.md`](../../../_agent_tools/UI_VISUAL_GATE_AGENT.md) | UI 변경 시 시각 증거 게이트(PASS/FAIL·PNG) |

---

## 3. 읽는 순서 (권장)

1. **`README.md`** (이 목차)
2. **`HANDOFF.md`** — 무엇이 있는지
3. **`CHECKLIST.md`** — 무엇을 할지, 어떻게 검증할지
4. 맡은 역할에 해당하는 **공통 플레이북 파일 하나**(`../../../_agent_tools/`). `[Rule: code-loop]` / `[Rule: ui-visual]`이면 `CHECKLIST.md`의 해당 **동작 검증 루프** / **시각 검증 루프** 절을 연다.

---

## 4. “어떤 플레이북을 쓸지” (짧은 분기)

| 상황 | 플레이북 |
|------|----------|
| 넓게 점검해서 이슈를 NEXT로 | [`QA_AGENT.md`](../../../_agent_tools/QA_AGENT.md) |
| 할 일을 기획 단위로 쪼개기 | [`REQUIREMENTS_AGENT.md`](../../../_agent_tools/REQUIREMENTS_AGENT.md) |
| 새 기능·확장 구현 | [`FEATURE_AGENT.md`](../../../_agent_tools/FEATURE_AGENT.md) |
| 작은 UX·문구·피드백만 | [`POLISH_AGENT.md`](../../../_agent_tools/POLISH_AGENT.md) |
| 픽셀 단위 UI 변경 | [`UI_VISUAL_GATE_AGENT.md`](../../../_agent_tools/UI_VISUAL_GATE_AGENT.md) |

`QA_AGENT` 산출물이 “새 기능이 필요”하면 그 NEXT 항목 본문에 **구현 플레이북 파일명**을 한 줄로 적는다(위 표의 이름; 실제 파일은 `../../../_agent_tools/` 아래).

---

## 5. `[Rule]` 본문 위치 (체스 `chess/` 루트 기준)

| `[Rule]` 값 | 본문 위치 |
|-------------|-----------|
| `code-loop` | `CHECKLIST.md`의 **동작 검증 루프 (Rule: code-loop)** 절 |
| `ui-visual` | `CHECKLIST.md`의 **시각 검증 루프 (Rule: ui-visual)** 절 (+ 게이트: [`UI_VISUAL_GATE_AGENT.md`](../../../_agent_tools/UI_VISUAL_GATE_AGENT.md)) |
