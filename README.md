# Godot NNUE × Prompt Chess

**Prompt로 오프닝·스타일을 지시하고 대국하는 Godot 체스** — 수는 **Stockfish NNUE**가 검증·후보 생성하고, **Cursor AI**가 프롬프트에 맞게 고르거나 코칭합니다.

Repo: [buc89l2nb41/GodotNnuePromptChess](https://github.com/buc89l2nb41/GodotNnuePromptChess)

---

## 실행 방법 (Quick Start)

### 1) 필수 준비

| 항목 | 설명 |
|------|------|
| **Godot 4.6+** | [Godot 다운로드](https://godotengine.org/download) (에디터 또는 console 빌드) |
| **Stockfish** | [공식 다운로드](https://stockfishchess.org/download/) → `engine/stockfish/stockfish.exe` 에 배치 (Windows) |
| **Python 3.10+** | Prompt AI 상대 / 코칭용 (CPU만 둘 거면 생략 가능) |

> Stockfish 바이너리와 `.env`(API 키)는 **커밋하지 마세요.**

### 2) 저장소 클론

```bash
git clone https://github.com/buc89l2nb41/GodotNnuePromptChess.git
cd GodotNnuePromptChess
```

### 3) Stockfish 배치

1. [stockfishchess.org/download](https://stockfishchess.org/download/) 에서 OS에 맞는 빌드 받기  
2. 실행 파일을 아래 경로에 두기  

```text
GodotNnuePromptChess/engine/stockfish/stockfish.exe   # Windows
# Linux/macOS 예: engine/stockfish/stockfish
```

폴더가 없으면 `engine/stockfish/` 를 만든 뒤 넣으면 됩니다.

### 4) (선택) Prompt AI — 사이드카 1회 설치

채팅으로 오프닝을 지시하거나 PGN 코칭을 쓰려면:

```powershell
cd ai_sidecar
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
```

`.env` 를 열어 **Cursor API 키**를 넣습니다.

- 키 발급: [Cursor Dashboard → Integrations](https://cursor.com/dashboard/integrations)
- 형식 예: `CURSOR_API_KEY=cursor_xxxxxxxx` (placeholder 조각이 남지 않게 한 줄로)

```env
CURSOR_API_KEY=cursor_xxxxxxxx
AI_SIDECAR_MOCK=0
CURSOR_AI_MODEL=composer-2.5
```

키 없이 UI만 확인할 때: `AI_SIDECAR_MOCK=1`

### 5) Godot에서 실행

1. Godot → **Import** → 이 프로젝트의 `project.godot` 선택  
2. **F5 (Play)**  
3. 상단 **상대** 버튼으로 모드 선택  
   - `OFF` — 혼자 / 편집  
   - `CPU` — Stockfish NNUE만  
   - `AI` — Prompt AI (사이드카 자동 기동) + NNUE 후보  

**상대: AI** 를 고르면 Godot이 `ai_sidecar`를 자동으로 켭니다. 보통 수동 `uvicorn`은 필요 없습니다.

에디터 없이 console로 실행하는 예:

```text
Godot_v4.x_win64_console.exe --path "C:\path\to\GodotNnuePromptChess"
```

### 6) 첫 대국 체크리스트

1. Stockfish 경로가 맞는지 확인 → **상대: CPU** 로 한 수 두기  
2. AI를 쓰려면 `.env` 키 설정 후 **상대: AI**  
3. 채팅에 예: `Sicilian Najdorf로 상대해줘` → 오프닝 북 로드  
4. FEN/PGN 칸에 기보 붙여넣기 → **보드에 적용** 또는 **코칭**

---

## 이 프로젝트가 하는 일

| 모드 | 누가 두나 | 특징 |
|------|-----------|------|
| **CPU** | Stockfish (NNUE) | Skill / movetime / depth로 난이도 |
| **AI (Prompt)** | Cursor AI가 MultiPV 후보 중 선택 | 채팅으로 오프닝·스타일·질문; 불법 수는 엔진 폴백으로 차단 |
| **코칭** | Cursor AI 해설 | PGN/FEN 붙여넣기 후 **코칭** — 보드는 최종 포지션으로 맞춤 |

핵심 원칙: **LLM이 임의로 둔 수는 보드에 바로 올리지 않습니다.**  
Stockfish 후보(또는 오프닝 북 UCI)만 적용하고, Godot `ChessState.make_move`가 최종 게이트입니다.

```text
플레이어 / 채팅(Prompt)
        │
        ▼
   Godot (보드 · 규칙)
        │
        ├── CPU:  Stockfish bestmove
        │
        └── AI:   Stockfish MultiPV 후보
                    → ai_sidecar (Cursor SDK)
                    → 선택·코칭 JSON
                    → 합법 수만 적용
```

---

## 주요 기능

### 체스 UI (Godot 4)

- SVG 기물, 클릭 이동, 승급 팝업  
- 새 게임 / 무르기 / 보드 편집 / 플레이어 색  

### Stockfish NNUE (CPU · AI 공통 엔진)

- UCI 직접 연동 (CPU 대전은 Python 불필요)  
- **Skill Level (0–20)** / **movetime(ms)** / **Max depth**  
- Lichess 스타일 **레벨 1–8** 프리셋  
- AI 모드에서는 **MultiPV**로 후보 수 수집  

### Prompt AI 상대 (`ai_sidecar`)

- 채팅 **전송**으로 오프닝·스타일·“왜 그 수야?” 질문  
- 수는 채팅에 자동 해설하지 않음 (물을 때만 답변)  
- 오프닝명은 **표준 영어** (검색·학습용)  
- Skill에 따라 후보를 **가중 선택** (항상 1위만 고집하지 않음)  
- Windows에서 Cursor SDK 브리지 호환 패치 포함  

### FEN / PGN

- 오른쪽 패널에 붙여넣기  
- **보드에 적용** — 포지션/기보를 보드에 반영 (변화수 `()` 스킵, 줄바꿈 있는 chess.com PGN 지원)  
- **코칭** — 보드 반영 + AI 해설 요청  

---

## 설정 (게임 내)

상단 **설정**:

- Skill (0..20)  
- movetime (ms)  
- MaxDepth (`0` = 제한 없음)  
- 레벨 1~8 프리셋  

값은 `user://settings.cfg`에 저장됩니다.

---

## 폴더 구조 (요약)

```text
GodotNnuePromptChess/
├── main.gd / main.tscn     # 메인 UI · 대국 루프
├── scripts/
│   ├── chess_state.gd      # 규칙 · FEN
│   ├── pgn_fen.gd          # FEN/PGN 로더
│   ├── engine/             # Stockfish UCI
│   └── ai/                 # 사이드카 HTTP · 프로세스
├── ai_sidecar/
│   ├── server.py           # FastAPI + Cursor SDK
│   ├── openings.py         # 북/Skill 헬퍼
│   ├── .env.example
│   └── requirements.txt
├── engine/stockfish/       # stockfish.exe (직접 배치, 미포함 권장)
└── agent_debug/            # 헤드리스·스모크 테스트
```

---

## AI 사이드카 수동 실행 (선택)

자동 기동이 안 될 때만:

```powershell
cd ai_sidecar
.\.venv\Scripts\Activate.ps1
uvicorn server:app --host 127.0.0.1 --port 8765
```

헬스 체크: `http://127.0.0.1:8765/health`

| Method | Path | 용도 |
|--------|------|------|
| GET | `/health` | 상태 |
| POST | `/session` | 세션 |
| POST | `/move` | 후보 중 수 선택 |
| POST | `/chat` | 대화 · 오프닝 · 코칭 |

자세한 내용은 [`ai_sidecar/README.md`](ai_sidecar/README.md) 참고.

---

## 테스트 (선택)

Godot console 경로를 `GODOT`에 두고:

```text
# 규칙/FEN
%GODOT% --headless --path "." -s "res://agent_debug/scripts/run_chess_tests.gd"

# PGN/FEN 로더
%GODOT% --headless --path "." -s "res://agent_debug/scripts/run_pgn_fen_test.gd"

# Stockfish 스모크
%GODOT% --headless --path "." -s "res://agent_debug/scripts/run_stockfish_bestmove_smoke_test.gd"
```

---

## 보안 · 라이선스 주의

- **`ai_sidecar/.env` 절대 커밋 금지** (API 키)  
- Stockfish는 [GPL](https://stockfishchess.org/) — 바이너리 재배포 시 라이선스 고지 필요. 이 레포는 **바이너리 미포함**을 권장합니다.  
- Cursor API 사용량·약관은 Cursor 정책을 따릅니다.

---

## 트러블슈팅

| 증상 | 확인 |
|------|------|
| CPU가 안 둠 | `engine/stockfish/stockfish.exe` 경로 · 설정에서 Skill/movetime |
| AI: 사이드카 연결 실패 | `ai_sidecar/.venv` + `pip install` · 포트 8765 · **상대: AI** 재선택 |
| 오프닝 조회 실패 / mock | `.env`의 `CURSOR_API_KEY`가 placeholder가 아닌지 |
| PGN 적용 오류 | chess.com 전체 PGN 붙여넣기 · 변화수 `()`는 본선만 적용됨 |
| Windows `os.get_blocking` | 최신 `ai_sidecar`(win_os_patch)인지 · Godot이 사이드카를 재시작했는지 |

---

## 로드맵에 가까운 사용 예

- 채팅: `Queen's Gambit Accepted로 상대해줘`  
- 채팅: `왜 그 수야?`  
- PGN 붙여넣기 → **코칭**  
- **상대: CPU** 로 NNUE만 연습, **AI** 로 프롬프트 대국
