#!/usr/bin/env bash
# CFP-50 / ADR-016 / ADR-023 결정 5 — marketplace parity check
# Compares mirrored fields (name, version, description, author) between
# plugin repo .claude-plugin/plugin.json and mclayer/marketplace .claude-plugin/marketplace.json.
#
# Usage: bash scripts/check-marketplace-parity.sh [plugin-json-path] [marketplace-json-path]
#   plugin-json-path: default = .claude-plugin/plugin.json (cwd-relative)
#   marketplace-json-path: optional. If absent, fetches from mclayer/marketplace via gh api.
#
# Test override: env CFP50_MARKETPLACE_PATH=<local-path> forces local marketplace.json (test mode).
#
# Exit codes:
#   0 = PASS (parity OK)
#   1 = FAIL (drift detected)
#   2 = SETUP error (missing file / jq / gh)

set -euo pipefail

PLUGIN_JSON="${1:-.claude-plugin/plugin.json}"
MARKETPLACE_OVERRIDE="${2:-${CFP50_MARKETPLACE_PATH:-}}"

# --- Setup verify ---
command -v jq >/dev/null 2>&1 || { echo "❌ marketplace-parity: jq not installed"; exit 2; }

if [[ ! -f "$PLUGIN_JSON" ]]; then
  echo "❌ marketplace-parity: plugin.json not found at $PLUGIN_JSON"
  exit 2
fi

# --- Marketplace fetch ---
MARKETPLACE_JSON=""
if [[ -n "$MARKETPLACE_OVERRIDE" ]]; then
  if [[ ! -f "$MARKETPLACE_OVERRIDE" ]]; then
    echo "❌ marketplace-parity: marketplace override path not found: $MARKETPLACE_OVERRIDE"
    exit 2
  fi
  MARKETPLACE_JSON="$(cat "$MARKETPLACE_OVERRIDE")"
else
  command -v gh >/dev/null 2>&1 || { echo "❌ marketplace-parity: gh CLI not installed"; exit 2; }
  MARKETPLACE_JSON="$(gh api repos/mclayer/marketplace/contents/.claude-plugin/marketplace.json --jq .content 2>/dev/null | base64 -d 2>/dev/null || echo "")"
  if [[ -z "$MARKETPLACE_JSON" ]]; then
    echo "❌ marketplace-parity: failed to fetch marketplace.json from mclayer/marketplace"
    exit 2
  fi
fi

# --- Extract plugin name ---
PLUGIN_NAME="$(jq -r '.name // empty' "$PLUGIN_JSON")"
if [[ -z "$PLUGIN_NAME" ]]; then
  echo "❌ marketplace-parity: plugin.json has no .name field"
  exit 2
fi

# --- Find entry in marketplace ---
MARKETPLACE_ENTRY="$(echo "$MARKETPLACE_JSON" | jq --arg name "$PLUGIN_NAME" '.plugins[] | select(.name == $name)')"
if [[ -z "$MARKETPLACE_ENTRY" ]]; then
  echo "❌ marketplace-parity: FAIL — plugin '$PLUGIN_NAME' not registered in mclayer/marketplace"
  echo "  Expected entry in marketplace.json plugins[] with name == '$PLUGIN_NAME'"
  exit 1
fi

# --- Compare 4 mirrored fields (ADR-016) ---
DRIFT=0
for field in name version description author; do
  PLUGIN_VAL="$(jq --compact-output ".$field" "$PLUGIN_JSON")"
  MARKET_VAL="$(echo "$MARKETPLACE_ENTRY" | jq --compact-output ".$field")"
  if [[ "$PLUGIN_VAL" != "$MARKET_VAL" ]]; then
    DRIFT=1
    echo "❌ marketplace-parity: DRIFT in field '$field'"
    echo "  plugin.json:      $PLUGIN_VAL"
    echo "  marketplace.json: $MARKET_VAL"
  fi
done

if [[ "$DRIFT" -eq 0 ]]; then
  echo "✅ marketplace-parity: PASS (plugin '$PLUGIN_NAME' parity OK — 4 mirrored fields match)"
  exit 0
else
  echo "❌ marketplace-parity: FAIL — ADR-016 mirrored field drift. Open sibling sync PR to mclayer/marketplace."
  exit 1
fi
