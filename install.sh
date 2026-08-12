#!/usr/bin/env bash
# nestjs-dev-workflow 수동 설치 스크립트
# 사용법: curl -fsSL https://raw.githubusercontent.com/hyunjin-stemus/nestjs-dev-workflow/main/install.sh | bash

set -e

REPO_URL="https://github.com/hyunjin-stemus/nestjs-dev-workflow"
CLAUDE_DIR="$HOME/.claude"
PLUGIN_DIR="$CLAUDE_DIR/plugins/cache/nestjs-dev-workflow/nestjs-dev-workflow/1.0.0"
TMP_DIR="$(mktemp -d)"

echo "🔧 nestjs-dev-workflow 설치 시작..."

# 임시 디렉토리에 저장소 클론
echo "📥 저장소 클론 중..."
git clone --depth=1 "$REPO_URL.git" "$TMP_DIR/repo"

# 1. 에이전트 (전역 설치)
echo "🤖 agents 설치 중..."
mkdir -p "$CLAUDE_DIR/agents"
cp "$TMP_DIR/repo/agents/"*.md "$CLAUDE_DIR/agents/"

# 2. 슬래시 커맨드 (전역 설치)
echo "⚡ commands 설치 중..."
mkdir -p "$CLAUDE_DIR/commands/cycle"
cp "$TMP_DIR/repo/commands/cycle/"*.md "$CLAUDE_DIR/commands/cycle/"

# 3. Rules (전역 설치)
echo "📋 rules 설치 중..."
mkdir -p "$CLAUDE_DIR/rules"
cp "$TMP_DIR/repo/rules/"*.md "$CLAUDE_DIR/rules/"

# 4. 전역 CLAUDE.md에 rules import 추가
GLOBAL_CLAUDE="$CLAUDE_DIR/CLAUDE.md"
RULES_BLOCK="@./rules/architecture.md
@./rules/api-design.md
@./rules/database.md
@./rules/security.md
@./rules/testing.md"

if [ ! -f "$GLOBAL_CLAUDE" ]; then
  echo "📝 ~/.claude/CLAUDE.md 생성 중..."
  cat > "$GLOBAL_CLAUDE" << 'EOF'
# Global Claude Code Rules

@./rules/architecture.md
@./rules/api-design.md
@./rules/database.md
@./rules/security.md
@./rules/testing.md
EOF
else
  # 이미 존재하면 중복 없이 추가
  if ! grep -q "rules/architecture.md" "$GLOBAL_CLAUDE"; then
    echo "" >> "$GLOBAL_CLAUDE"
    echo "# nestjs-dev-workflow rules" >> "$GLOBAL_CLAUDE"
    echo "@./rules/architecture.md" >> "$GLOBAL_CLAUDE"
    echo "@./rules/api-design.md" >> "$GLOBAL_CLAUDE"
    echo "@./rules/database.md" >> "$GLOBAL_CLAUDE"
    echo "@./rules/security.md" >> "$GLOBAL_CLAUDE"
    echo "@./rules/testing.md" >> "$GLOBAL_CLAUDE"
    echo "📝 기존 ~/.claude/CLAUDE.md에 rules import 추가됨"
  else
    echo "ℹ️  ~/.claude/CLAUDE.md에 이미 rules import가 있음 (스킵)"
  fi
fi

# 5. claude plugin 명령어 지원 시 플러그인 시스템에도 등록
if claude plugin --help &>/dev/null; then
  echo "🔌 claude plugin 시스템에 등록 중..."
  mkdir -p "$PLUGIN_DIR"
  cp -r "$TMP_DIR/repo/"* "$PLUGIN_DIR/"

  # installed_plugins.json 업데이트
  PLUGINS_JSON="$CLAUDE_DIR/plugins/installed_plugins.json"
  if [ -f "$PLUGINS_JSON" ] && command -v python3 &>/dev/null; then
    python3 - "$PLUGINS_JSON" "$PLUGIN_DIR" << 'PYEOF'
import json, sys, os
from datetime import datetime

path = sys.argv[1]
install_path = sys.argv[2]

with open(path, 'r') as f:
    data = json.load(f)

key = "nestjs-dev-workflow@nestjs-dev-workflow"
data.setdefault("plugins", {})[key] = [{
    "scope": "user",
    "installPath": install_path,
    "version": "1.0.0",
    "installedAt": datetime.utcnow().isoformat() + "Z",
    "lastUpdated": datetime.utcnow().isoformat() + "Z"
}]

with open(path, 'w') as f:
    json.dump(data, f, indent=4)

print("✔ installed_plugins.json 업데이트 완료")
PYEOF
  fi
fi

# 정리
rm -rf "$TMP_DIR"

echo ""
echo "✅ nestjs-dev-workflow 설치 완료!"
echo ""
echo "설치된 항목:"
echo "  • agents: database-reviewer, pr-diff-reviewer, nestjs-backend-architect, db-erd-architect, prd-writer, docker-container-manager"
echo "  • commands: /cycle:task-cycle, /cycle:cycle-finish, /cycle:prd-from-requirement"
echo "  • rules: architecture, api-design, database, security, testing (→ ~/.claude/rules/)"
echo "  • ~/.claude/CLAUDE.md: rules import 추가됨"
echo ""
echo "⚠️  적용하려면 Claude Code를 재시작하세요."
