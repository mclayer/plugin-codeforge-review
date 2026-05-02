#!/usr/bin/env bash
# CFP-56 ADR-017 — dogfood artifact path enforcement
# Fails (exit 1) if any file matches forbidden paths in plugin repo:
# - docs/superpowers/specs/**
# - docs/superpowers/plans/**
#
# Allowed: ADR/playbook/template/script 본문이 forbidden path 를 "문자열로 언급"하는 것 (결정 5).
#
# Usage: bash scripts/check-dogfood-artifact-paths.sh [path-prefix]
#   path-prefix: optional repo root override (default: pwd). 테스트 fixture 디렉터리에서 사용.
#
# Detection strategy (3 branches):
#   1. CFP56_USE_FIND=1  → force find (test harness / fixture mode 강제)
#   2. NOT in git work tree → find fallback (non-git 컨텍스트 자동)
#   3. Default → git ls-files (tracked file 만 — production CI accurate)

set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

if [[ "${CFP56_USE_FIND:-0}" == "1" ]] || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # find mode (force or auto fallback) — finds tracked + untracked
  violations=$(find docs/superpowers/specs docs/superpowers/plans \
    -type f 2>/dev/null || true)
else
  # git ls-files mode (default, production CI) — tracked file 만
  violations=$(git ls-files \
    -- 'docs/superpowers/specs/**' 'docs/superpowers/plans/**' \
    2>/dev/null || true)
fi

if [[ -z "$violations" ]]; then
  echo "✅ dogfood-artifact-paths: PASS (no forbidden path)"
  exit 0
fi

echo "❌ dogfood-artifact-paths: FAIL — forbidden dogfood artifact path detected"
echo "ADR-017 violation. Move to mclayer/codeforge-internal-docs/<plugin-folder>/{specs,plans}/:"
while IFS= read -r f; do
  echo "  - $f"
done <<< "$violations"
exit 1
