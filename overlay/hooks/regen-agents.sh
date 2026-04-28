#!/usr/bin/env bash
# codeforge-review plugin agent regen
#
# codeforge core의 overlay/hooks/regen-agents.sh 패턴 복제.
# 자기 plugin root의 agents/ 만 iterate (sibling discovery 불필요).
# core merge.py 재사용 (consumer가 codeforge core 설치 의무 — session-start-deps-check.sh 보장).

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_MERGE_PY="${CLAUDE_PLUGIN_DIR:-$HOME/.claude/plugins/cache}/mclayer/codeforge/overlay/hooks/merge.py"
CONSUMER_AGENTS_DIR=".claude/agents"

if [[ ! -f "$CORE_MERGE_PY" ]]; then
  echo "⚠ codeforge core merge.py 미발견 — codeforge-review 단독 사용 불가" >&2
  echo "  expected at: $CORE_MERGE_PY" >&2
  exit 1
fi

mkdir -p "$CONSUMER_AGENTS_DIR"

for core_agent in "$PLUGIN_ROOT/agents/"*.md; do
  basename=$(basename "$core_agent")
  overlay_agent=".claude/_overlay/agents/$basename"
  output="$CONSUMER_AGENTS_DIR/$basename"

  if [[ -f "$overlay_agent" ]]; then
    python3 "$CORE_MERGE_PY" "$core_agent" "$overlay_agent" > "$output"
  else
    python3 "$CORE_MERGE_PY" "$core_agent" > "$output"
  fi
done

echo "✓ codeforge-review: $(ls "$PLUGIN_ROOT/agents/"*.md | wc -l) agents regenerated"
