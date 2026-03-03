#!/bin/bash
# Run briefing generator and post a short summary to Discord.
# Usage: ./scripts/run-briefing-and-post.sh [morning|afternoon]

set -euo pipefail

PERIOD="${1:-morning}"
DASHBOARD_DIR="/Users/clankeredwards/.openclaw/workspace/rebekah-dashboard"
DATA_DIR="$DASHBOARD_DIR/data"
ENV_FILE="/Users/clankeredwards/.openclaw/.env"
DISCORD_TARGET="channel:1471228309797998805"
OPENCLAW="/opt/homebrew/bin/openclaw"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# Alert Discord on any unhandled error and exit
_on_error() {
  local exit_code=$?
  local line=$1
  "$OPENCLAW" message send --channel discord --target "$DISCORD_TARGET" \
    --message "⚠️ **Briefing failed** (${PERIOD}) — script error on line ${line} (exit ${exit_code}). Check logs: \`rebekah-dashboard/.logs/briefing-${PERIOD}.err.log\`" 2>/dev/null || true
}
trap '_on_error $LINENO' ERR

export PERIOD
export DATA_DIR

"$DASHBOARD_DIR/scripts/generate-briefing.sh" "$PERIOD"

msg=$(python3 - <<'PY'
import json
from pathlib import Path
import os
b=json.loads(Path('/Users/clankeredwards/.openclaw/workspace/rebekah-dashboard/data/current-briefing.json').read_text())
period=b.get('period','morning')
label="7am" if period=="morning" else "3pm"
print(f"Your {label} briefing is ready! https://rebekah-edwards.github.io/rebekah-dashboard/")
PY
)

"$OPENCLAW" message send --channel discord --target "$DISCORD_TARGET" --message "$msg" || true
