# 커밋 루프 워크플로우 설치 가이드

> Claude Code에게: "이 디렉토리의 SETUP.md대로 설치해줘. 유저 레벨 파일은 복사하고, settings.json/config.toml은 덮어쓰지 말고 키만 병합해줘. repo git hook은 내가 지정하는 repo에만 적용해줘."

역할 분담:
- **개인 워크플로우**(권한 모드, 리뷰 서브에이전트, 커밋 루프 규칙) → **유저 레벨**. 모든 repo·worktree에 자동 적용, 재세팅 불필요.
- **빌드/테스트 게이트** → **repo 레벨** git pre-commit hook. repo마다 빌드 커맨드가 다르므로 여기 둔다. 커밋 주체와 무관하게 동작.

> 📁 이 패키지의 파일은 **루트에 평평하게** 있다: `commit-loop.md`, `code-reviewer.md`, `CLAUDE.snippet.md`, `settings.snippet.json`, `AGENTS.md`, `config.snippet.toml`, `pre-commit`. 아래 명령은 이 디렉토리에서 실행한다.

커밋 게이트는 **확인(confirm) 방식**이다 — `git commit`을 권한으로 막지 않고, 커밋 전 반드시 내 확인을 받는다(확인만 받았으면 누가 커밋하든 무방). `git push`/`rm -rf`는 하드 deny.

---

## 1. Claude Code (유저 레벨)

| 소스 | 목적지 | 방식 |
|---|---|---|
| `commit-loop.md` | `~/.claude/commands/commit-loop.md` | 복사 (명시 호출 `/commit-loop`) |
| `code-reviewer.md` | `~/.claude/agents/code-reviewer.md` | 복사 |
| `CLAUDE.snippet.md` | `~/.claude/CLAUDE.md` | **추가/병합** (자동 적용 — 권장) |
| `settings.snippet.json` | `~/.claude/settings.json` | **병합** (덮어쓰기 X) |

```bash
mkdir -p ~/.claude/commands ~/.claude/agents
cp commit-loop.md   ~/.claude/commands/commit-loop.md
cp code-reviewer.md ~/.claude/agents/code-reviewer.md
```

**자동 적용(권장):** 대부분의 코드 작업에 루프를 자동 적용하려면 규칙을 유저 글로벌 `~/.claude/CLAUDE.md`에 넣는다(매 세션 자동 로드). 사소한 한두 줄 수정·질문은 규칙의 예외로 빠진다.
```bash
touch ~/.claude/CLAUDE.md
# 이미 들어있지 않으면 기존 내용 뒤에 덧붙임 (중복 방지)
grep -q '커밋 루프 (코드 변경 기본 규칙)' ~/.claude/CLAUDE.md \
  || { printf '\n\n' >> ~/.claude/CLAUDE.md && cat CLAUDE.snippet.md >> ~/.claude/CLAUDE.md; }
```
> 수동만 원하면 이 단계를 건너뛰고 매번 `/commit-loop <작업>`으로 명시 호출한다. (Codex는 아래 AGENTS.md로 항상 자동.)

**settings.json — 기존 내용 보존하고 키만 병합.** ⚠️ `jq -s '.[0]*.[1]'`는 allow/deny 배열을 **교체**한다(기존 MCP allow 등이 날아감). 기존 allow가 있으면 아래처럼 **합집합**으로 병합한다:
```bash
# 기존 파일 없으면 그냥 복사
[ -f ~/.claude/settings.json ] || cp settings.snippet.json ~/.claude/settings.json
# 있으면 백업 후 union 병합 (defaultMode 세팅 + allow/deny 합집합, 그 외 키는 그대로 보존)
[ -f ~/.claude/settings.json ] && cp ~/.claude/settings.json ~/.claude/settings.json.bak \
  && jq --slurpfile snip settings.snippet.json '
       ($snip[0].permissions) as $sp
       | .permissions.defaultMode = $sp.defaultMode
       | .permissions.allow = ((.permissions.allow // []) + (($sp.allow // []) - (.permissions.allow // [])))
       | .permissions.deny  = ((.permissions.deny  // []) + (($sp.deny  // []) - (.permissions.deny  // [])))
     ' ~/.claude/settings.json > /tmp/cc.json \
  && jq empty /tmp/cc.json && mv /tmp/cc.json ~/.claude/settings.json
```

핵심 키:
- `defaultMode: "acceptEdits"` — 워크스페이스 파일 편집은 프롬프트 없이. 루프의 게이트는 권한 프롬프트가 아니라 **대화상의 확인 단계**다.
- `deny: Bash(git push:*)`, `Bash(rm -rf:*)` — 외부/위험 동작은 하드 차단. **`git commit`은 deny하지 않는다**(확인 게이트로 통제 — 승인 없이 스스로 커밋하지 않는 규칙은 commit-loop/CLAUDE 규칙이 담당).
- `allow: Bash(./gradlew:*)` 등 — 신뢰 명령은 프롬프트 없이.

## 2. Codex (유저 레벨)

| 소스 | 목적지 | 방식 |
|---|---|---|
| `AGENTS.md` | `~/.codex/AGENTS.md` | 복사(없으면) / 맨 위에 **병합** (항상 자동 적용) |
| `config.snippet.toml` | `~/.codex/config.toml` | **병합** (덮어쓰기 X) |

```bash
mkdir -p ~/.codex
# AGENTS.md: 이미 적용됐으면 skip / 비어있지 않으면 앞에 prepend / 아니면 복사 (Codex가 매 세션 자동 로드)
if [ -s ~/.codex/AGENTS.md ] && grep -qF "커밋 루프 (전역 작업 규칙)" ~/.codex/AGENTS.md; then
  : # 이미 적용됨
elif [ -s ~/.codex/AGENTS.md ]; then
  cat AGENTS.md ~/.codex/AGENTS.md > /tmp/a.md && mv /tmp/a.md ~/.codex/AGENTS.md
else
  cp AGENTS.md ~/.codex/AGENTS.md
fi
```
config.toml은 최상위 키 `approval_policy = "on-request"` / `sandbox_mode = "workspace-write"`와 `[features] multi_agent = true`를 기존 파일에 손으로 병합한다(최상위 키는 반드시 첫 `[table]` **위에**, 중복 키 주의). 리뷰는 Codex 내장 `/review`.

> ⚠️ Naver 관리 머신이면 `requirements.toml`로 approval/sandbox가 제약될 수 있다. `on-request` + `workspace-write`는 보통 허용 범위(금지 대상은 `never` / `danger-full-access`). `codex config show` 또는 `/status`로 실제 적용값 확인.

## 3. repo별 빌드/테스트 게이트 (repo마다 1회)

작업할 repo에서만:
```bash
mkdir -p .githooks
cp <이 패키지>/pre-commit .githooks/pre-commit
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks    # 같은 repo의 모든 worktree 공유. 단, 클론/호스트마다 1회 필요(local config).
```
그다음 `.githooks/pre-commit` 안의 `./gradlew build test`를 **이 repo에 맞게 수정**한다(모듈 한정 빌드 등 — 모노레포는 루트 전체 빌드가 느릴 수 있다). 이 파일이 빌드/테스트 명령의 단일 소스이고, CC/Codex의 워크플로우 규칙(빌드/테스트 단계)이 이걸 참조한다.

선택: repo `CLAUDE.md`(또는 `AGENTS.md`)에 빌드 커맨드를 한 줄 적어두면 에이전트가 더 잘 찾는다. 예: `빌드/테스트: ./gradlew :module:build :module:test`

> 💡 `.githooks/pre-commit`를 repo에 커밋해두면 파일은 클론을 따라간다. 하지만 `git config core.hooksPath .githooks`는 클론마다 로컬 설정이므로 호스트마다 한 번 실행해야 한다.

---

## 트리거: 자동 vs 수동

- **CC**: `CLAUDE.snippet.md`를 `~/.claude/CLAUDE.md`에 넣으면 **자동**(대부분의 코드 작업). 안 넣으면 `/commit-loop <작업>`로 **수동** 호출.
- **Codex**: `~/.codex/AGENTS.md`로 **항상 자동**.
- 둘 다 예외: 단순 질문·조사·설명, 아주 사소한 한두 줄 수정은 루프 없이 바로 처리.

## 사용법 (일상)

- 흐름: 분해 승인 → [커밋 plan 승인 → 구현 → 빌드/테스트(자율 수정) → 리뷰 → 확인 게이트] 반복.
- 커밋은 확인 게이트 통과 후. 승인 없이 스스로 커밋하거나 다음 커밋으로 넘어가지 않는다.

## 검증

- CC: `/permissions`로 `acceptEdits` + deny(git push, rm -rf) 확인. `/agents`로 code-reviewer 확인. 자동 적용 시 `~/.claude/CLAUDE.md`에 "커밋 루프" 블록 있는지.
- git hook: repo에서 `git config --get core.hooksPath` → `.githooks` 나오는지. 일부러 테스트 깨뜨리고 커밋 시도 → 차단되는지.
- Codex: `codex config show` 또는 `/status`로 approval_policy / sandbox_mode 확인.

## 나중에 추가할 옵션 (지금은 불필요)

자율(빌드/테스트 자동 실행)이 가끔 빠지면, CC Stop hook으로 "변경 있는데 테스트 green 아니면 턴 종료 차단"을 하드 강제할 수 있다. 단순 질문 오발동을 막으려면 hook 안에 변경 가드를 넣는다:
```bash
git diff --quiet && git diff --cached --quiet && exit 0   # 변경 없으면 통과
```
처음엔 깔지 말고, 실제로 자율이 자주 빼먹을 때만 추가.
