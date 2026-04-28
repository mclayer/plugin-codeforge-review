#!/usr/bin/env bash
# codeforge-review SessionStart dependency check
#
# 본 plugin은 codeforge core plugin이 설치되어 있어야 동작.
# core 미설치 시 fail-fast + install 안내. core 설치 OK 시 자체 regen-agents.sh 체인.
#
# 의존 plugin: codeforge@mclayer

set -euo pipefail

CORE_PLUGIN_PATH="${CLAUDE_PLUGIN_DIR:-$HOME/.claude/plugins/cache}/mclayer/codeforge"

if [[ ! -d "$CORE_PLUGIN_PATH" ]]; then
  cat >&2 <<EOF

✗ codeforge-review plugin 의존성 누락

본 plugin은 codeforge core plugin이 설치되어 있어야 동작합니다.

설치 방법:
  /plugins install codeforge@mclayer

또는 ~/.claude/settings.json에서:
  "enabledPlugins": {
    "codeforge@mclayer": true,
    "codeforge-review@mclayer": true
  }

자세한 사항: https://github.com/mclayer/plugin-codeforge-review#dependencies

EOF
  exit 1
fi

# core 설치 OK — 자체 regen-agents.sh 체인 실행
exec "$(dirname "$0")/regen-agents.sh"
