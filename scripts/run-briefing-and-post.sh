#!/bin/bash
# Run briefing generator and post a short summary to Discord.
# Usage: ./scripts/run-briefing-and-post.sh [morning|afternoon]

set -euo pipefail

PERIOD="${1:-morning}"
DASHBOARD_DIR="/Users/clankeredwards/.openclaw/workspace/rebekah-dashboard"
DATA_DIR="$DASHBOARD_DIR/data"
ENV_FILE="/Users/clankeredwards/.openclaw/.env"
DISCORD_TARGET="channel:1471228309797998805"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

export PERIOD
export DATA_DIR

"$DASHBOARD_DIR/scripts/generate-briefing.sh" "$PERIOD"

msg=$(python3 - <<'PY'
import json
from pathlib import Path
b=json.loads(Path('/Users/clankeredwards/.openclaw/workspace/rebekah-dashboard/data/current-briefing.json').read_text())
items=b.get('items',[])
by={}
for it in items:
  by.setdefault(it.get('section','other'),[]).append(it)

def fmt_section(key, title, n=3):
  arr=by.get(key,[])
  if not arr:
    return f"**{title}:** (no new items)"
  lines=[f"**{title} ({len(arr)}):**"]
  for it in arr[:n]:
    lines.append(f"- {it.get('title')} — {it.get('url')}")
    x=it.get('x_urls') or []
    if x:
      lines.append(f"  X: {x[0]}")
  if len(arr)>n:
    lines.append(f"  …and {len(arr)-n} more")
  return "\n".join(lines)

text = "\n\n".join([
  f"**Rebekah Briefing — {b.get('date')} ({b.get('period')})**\nNew items: **{len(items)}**\nDashboard: https://rebekah-edwards.github.io/rebekah-dashboard/",
  fmt_section('seo','SEO & Content'),
  fmt_section('publishing','Publishing & Books'),
  fmt_section('popculture','Pop Culture'),
  fmt_section('business','Biz & AI'),
])
print(text)
PY
)

openclaw message send --channel discord --target "$DISCORD_TARGET" --message "$msg" || true
