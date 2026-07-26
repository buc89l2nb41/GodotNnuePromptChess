# Chess Cursor AI sidecar

Godot 게임과 Cursor SDK를 잇는 로컬 HTTP 서버입니다.

## 실행

Godot에서 **상대: AI** 를 고르면 `ai_sidecar` uvicorn을 **자동 기동**합니다  
(이미 8765 포트에 서버가 있으면 그대로 사용).

최초 1회 의존성만 설치해 두면 됩니다:

```powershell
cd ai_sidecar
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
# .env 에 CURSOR_API_KEY 입력
```

수동 실행이 필요할 때만:

```powershell
cd ai_sidecar
.\.venv\Scripts\Activate.ps1
uvicorn server:app --host 127.0.0.1 --port 8765
```

키 없이 동작 확인(엔진 1위 + mock 채팅): `.env`에 `AI_SIDECAR_MOCK=1` 이거나:

```powershell
$env:AI_SIDECAR_MOCK = "1"
uvicorn server:app --host 127.0.0.1 --port 8765
```

## 엔드포인트

| Method | Path | 용도 |
|--------|------|------|
| GET | `/health` | 상태 |
| POST | `/session` | 새 agent 세션 |
| POST | `/move` | 후보 중 수 선택 (채팅에 자동 해설 없음) |
| POST | `/chat` | 대화 + 오프닝/스타일 명령 적용 + 직전 수 질문 |
| DELETE | `/session/{id}` | 세션 종료 |

수는 **요청한 오프닝을 Cursor가 조회·회상해 UCI 북으로 저장**한 뒤 따릅니다.  
북이 끝나면 MultiPV 후보를 Skill 가중으로 고릅니다 (항상 1위 고정 아님).  
수는 조용히 두고, 해설은 사용자가 채팅으로 물을 때만 답합니다.

## 수동 체크리스트

1. 사이드카 기동 (`/health` → ok)
2. Godot에서 상대 = AI
3. 한 수 두기 → AI가 두되 채팅에 자동 해설이 없음
4. 채팅: `시실리안 나이도프 둬줘` → 답변 + 북 적용
5. 채팅: `왜 그 수야?` → 직전 수 해설
6. 사이드카 중지 후 AI 턴 → 엔진 폴백 + 오류 한 줄
7. 상대 = CPU → 기존처럼 bestmove만 (회귀)
