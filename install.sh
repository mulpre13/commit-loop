#!/usr/bin/env bash
#
# commit-loop 워크플로우 설치 (유저 레벨: Claude Code + Codex).
# 재실행 안전(idempotent). 변경 전 원본을 <파일>.bak 으로 최초 1회 백업.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
DRY_RUN=0
REPOS=()
TMP_FILES=()

# 실패/종료 시 임시파일 정리 (성공 시 mv로 이미 사라졌으면 rm -f는 무해)
cleanup() { if [ "${#TMP_FILES[@]}" -gt 0 ]; then rm -f "${TMP_FILES[@]}"; fi; }
trap cleanup EXIT

usage() {
  cat <<'EOF'
commit-loop 설치 (유저 레벨: Claude Code + Codex)

사용법: ./install.sh [--repo <path>]... [--dry-run] [-h|--help]
  --repo <path>   해당 repo에 빌드/테스트 pre-commit 훅 설치 (여러 번 지정 가능)
  --dry-run       실제 변경 없이 수행할 작업만 출력
  -h, --help      이 도움말

재실행 안전(idempotent). 변경 전 원본을 <파일>.bak 으로 최초 1회 백업.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --repo)    [ $# -ge 2 ] || { echo "오류: --repo 뒤에 경로가 필요합니다" >&2; exit 2; }
               REPOS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "오류: 알 수 없는 인자 '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

info() { printf '\n• %s\n' "$*"; }
note() { printf '  - %s\n' "$*"; }

# dry-run 인식 실행기 (단순 명령용; 리다이렉션이 필요한 작업은 별도 처리)
run() {
  if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi
}

# 원본을 최초 1회만 .bak 으로 백업 (재실행 시 이미 변경된 내용으로 덮어쓰지 않도록)
backup_once() {
  local f="$1"
  [ -f "$f" ] && [ ! -f "$f.bak" ] || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] 백업: $f → $f.bak"
  else
    cp "$f" "$f.bak"; note "백업 생성: $f.bak"
  fi
}

# 마커가 없을 때만 src 블록을 file 끝에 append
append_block_once() {  # <file> <marker> <src>
  local file="$1" marker="$2" src="$3"
  if [ -f "$file" ] && grep -qF "$marker" "$file"; then
    note "이미 적용됨, 건너뜀: $file"
    return
  fi
  backup_once "$file"
  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] append: $src → $file"
  else
    { printf '\n\n'; cat "$src"; } >> "$file"
    note "append: $src → $file"
  fi
}

# TOML 최상위 키를 첫 [table] 헤더 앞(테이블 없으면 EOF)에 삽입 → 항상 top-level 보장.
# (approval_policy = "on-request" 같은 값 속 '['는 줄 선두가 아니라 /^[[:space:]]*\[/ 에 안 걸림)
insert_before_first_table() {  # <file> <line>
  local file="$1" line="$2" tmp; tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  awk -v ins="$line" '
    !done && /^[[:space:]]*\[/ { print ins; done=1 }
    { print }
    END { if (!done) print ins }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

install_claude() {
  info "Claude Code (유저 레벨)"
  run mkdir -p "$CLAUDE_DIR/commands" "$CLAUDE_DIR/agents"
  run cp "$SCRIPT_DIR/commit-loop.md"   "$CLAUDE_DIR/commands/commit-loop.md"
  run cp "$SCRIPT_DIR/code-reviewer.md" "$CLAUDE_DIR/agents/code-reviewer.md"
  note "command(/commit-loop) + code-reviewer 에이전트 복사"

  run touch "$CLAUDE_DIR/CLAUDE.md"
  append_block_once "$CLAUDE_DIR/CLAUDE.md" "커밋 루프 (코드 변경 기본 규칙)" "$SCRIPT_DIR/CLAUDE.snippet.md"

  local settings="$CLAUDE_DIR/settings.json" snippet="$SCRIPT_DIR/settings.snippet.json"
  if [ ! -f "$settings" ]; then
    run cp "$snippet" "$settings"; note "settings.json 신규 생성"
  elif command -v jq >/dev/null 2>&1; then
    backup_once "$settings"
    if [ "$DRY_RUN" -eq 1 ]; then
      note "[dry-run] settings.json union 병합 (defaultMode + allow/deny, 기존 키 보존)"
    else
      local tmp; tmp="$(mktemp)"; TMP_FILES+=("$tmp")
      jq --slurpfile snip "$snippet" '
        ($snip[0].permissions) as $sp
        | .permissions.defaultMode = $sp.defaultMode
        | .permissions.allow = ((.permissions.allow // []) + (($sp.allow // []) - (.permissions.allow // [])))
        | .permissions.deny  = ((.permissions.deny  // []) + (($sp.deny  // []) - (.permissions.deny  // [])))
      ' "$settings" > "$tmp" && jq empty "$tmp" && mv "$tmp" "$settings"
      note "settings.json union 병합"
    fi
  else
    note "⚠ jq 없음 → settings.json은 SETUP.md 보고 수동 병합 필요"
  fi
}

install_codex() {
  info "Codex (유저 레벨)"
  run mkdir -p "$CODEX_DIR"

  local agents="$CODEX_DIR/AGENTS.md"
  if [ -s "$agents" ] && grep -qF "커밋 루프 (전역 작업 규칙)" "$agents"; then
    note "AGENTS.md 이미 적용됨, 건너뜀"
  elif [ -s "$agents" ]; then
    backup_once "$agents"
    if [ "$DRY_RUN" -eq 1 ]; then
      note "[dry-run] AGENTS.md 앞에 prepend"
    else
      local tmp; tmp="$(mktemp)"; TMP_FILES+=("$tmp")
      cat "$SCRIPT_DIR/AGENTS.md" "$agents" > "$tmp" && mv "$tmp" "$agents"
      note "AGENTS.md prepend"
    fi
  else
    run cp "$SCRIPT_DIR/AGENTS.md" "$agents"; note "AGENTS.md 신규 생성"
  fi

  local config="$CODEX_DIR/config.toml"
  if [ ! -f "$config" ]; then
    run cp "$SCRIPT_DIR/config.snippet.toml" "$config"; note "config.toml 신규 생성"
    return
  fi
  backup_once "$config"
  # 최상위 키 (없을 때만, 첫 [table] 앞에 삽입)
  if ! grep -qE '^[[:space:]]*approval_policy[[:space:]]*=' "$config"; then
    if [ "$DRY_RUN" -eq 1 ]; then note "[dry-run] approval_policy 삽입"
    else insert_before_first_table "$config" 'approval_policy = "on-request"'; note "approval_policy 삽입"; fi
  fi
  if ! grep -qE '^[[:space:]]*sandbox_mode[[:space:]]*=' "$config"; then
    if [ "$DRY_RUN" -eq 1 ]; then note "[dry-run] sandbox_mode 삽입"
    else insert_before_first_table "$config" 'sandbox_mode = "workspace-write"'; note "sandbox_mode 삽입"; fi
  fi
  # [features].multi_agent (가드는 키 존재만 확인 — 섹션 범위는 미검증)
  if grep -qE '^[[:space:]]*multi_agent[[:space:]]*=' "$config"; then
    note "multi_agent 이미 있음 (위치 미검증 — [features] 아래인지 직접 확인 권장)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] [features].multi_agent 삽입"
  elif grep -qE '^[[:space:]]*\[features\]' "$config"; then
    local tmp; tmp="$(mktemp)"; TMP_FILES+=("$tmp")
    awk '{ print } !done && /^[[:space:]]*\[features\]/ { print "multi_agent = true"; done=1 }' "$config" > "$tmp" && mv "$tmp" "$config"
    note "[features].multi_agent 삽입"
  else
    printf '\n[features]\nmulti_agent = true\n' >> "$config"
    note "[features] 추가 + multi_agent"
  fi
}

install_hooks() {
  [ "${#REPOS[@]}" -gt 0 ] || return 0   # 빈 배열이면 종료 → 아래 "${REPOS[@]}" 확장 안전 보장
  info "repo 빌드/테스트 훅"
  local repo
  for repo in "${REPOS[@]}"; do
    if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      note "⚠ $repo : git repo 아님 → 건너뜀"; continue
    fi
    run mkdir -p "$repo/.githooks"
    run cp "$SCRIPT_DIR/pre-commit" "$repo/.githooks/pre-commit"
    run chmod +x "$repo/.githooks/pre-commit"
    run git -C "$repo" config core.hooksPath .githooks
    note "훅 설치: $repo (core.hooksPath=.githooks)"
  done
}

echo "commit-loop 설치  (소스: $SCRIPT_DIR)"
[ "$DRY_RUN" -eq 1 ] && echo "*** DRY-RUN — 실제 변경 없음 ***"
install_claude
install_codex
install_hooks
echo
echo "✅ 완료. 확인: Claude Code에서 /permissions · /agents · /commit-loop, Codex는 codex config show / status."
[ "${#REPOS[@]}" -eq 0 ] && echo "ℹ repo 빌드/테스트 훅은 작업할 repo에서  ./install.sh --repo <path>  로 따로 설치."
