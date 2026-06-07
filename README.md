# commit-loop

코드 변경을 **커밋 단위로 쪼개고**, 커밋마다 *plan → 구현 → 빌드/테스트 → 리뷰 → 확인 게이트*를 거치는 개인 워크플로우. Claude Code와 Codex 양쪽에 설치된다.

핵심: **승인(확인) 없이는 커밋하지 않는다** — `git commit`을 권한으로 막는 게 아니라, 커밋 전 반드시 확인 게이트를 거친다(확인만 받으면 누가 커밋하든 무방).

## 설치

```bash
./install.sh                 # 유저 레벨 (Claude Code + Codex)
./install.sh --dry-run       # 무엇이 바뀔지 미리보기
./install.sh --repo <path>   # 위 + 해당 repo에 빌드/테스트 pre-commit 훅
```

재실행해도 안전(idempotent)하고, 변경 전 원본을 `*.bak`으로 백업한다. 상세 설치, 그리고 자동 설치 실패·부분 적용(jq 없는 환경, 특이한 TOML 구조 등) 시 단계별 수동 적용은 [SETUP.md](SETUP.md) 1~3절 참고.

## 트리거

| | 자동 | 명시 |
|---|---|---|
| **Claude Code** | `~/.claude/CLAUDE.md` 규칙 (대부분의 코드 작업) | `/commit-loop <작업>` |
| **Codex** | `~/.codex/AGENTS.md` 규칙 (항상) | — |

예외(루프 없이 바로 처리): 단순 질문·조사·설명, 아주 사소한 한두 줄 수정.

## 구성

| 파일 | 역할 |
|---|---|
| `commit-loop.md` | CC `/commit-loop` 커맨드 (명시 호출) |
| `CLAUDE.snippet.md` | CC 자동 적용 규칙 → `~/.claude/CLAUDE.md` |
| `code-reviewer.md` | CC 코드 리뷰 서브에이전트 |
| `settings.snippet.json` | CC 권한 (`acceptEdits`, deny `git push`/`rm -rf`) |
| `AGENTS.md` | Codex 전역 규칙 (자동) |
| `config.snippet.toml` | Codex 설정 (`approval_policy`/`sandbox_mode`/`multi_agent`) |
| `pre-commit` | repo 빌드/테스트 게이트 훅 |
| `install.sh` / `SETUP.md` | 자동 설치 / 상세 가이드 |

## License

MIT License. (`LICENSE` 파일은 원격 저장소 루트에 있음)
