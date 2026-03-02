#!/bin/bash
# Generate a dashboard briefing (morning/afternoon) and push to GitHub.
# Writes ONLY new (never-seen) items per briefing run.
# Usage: ./scripts/generate-briefing.sh [morning|afternoon]

set -euo pipefail

PERIOD="${1:-morning}"
DASHBOARD_DIR="/Users/clankeredwards/.openclaw/workspace/rebekah-dashboard"
DATA_DIR="$DASHBOARD_DIR/data"
ENV_FILE="/Users/clankeredwards/.openclaw/.env"

# Load env (expects XAI_API_KEY)
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

: "${XAI_API_KEY:?XAI_API_KEY is required (set it in ~/.openclaw/.env)}"

DATE_LOCAL=$(date +%Y-%m-%d)
TIMESTAMP_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$DATA_DIR"

SEEN_FILE="$DATA_DIR/seen.json"
if [ ! -f "$SEEN_FILE" ]; then
  echo '{"seenIds":[]}' > "$SEEN_FILE"
fi

echo "Generating $PERIOD briefing for $DATE_LOCAL…"

xai_responses() {
  local query="$1"
  local payload
  payload=$(python3 - <<PY
import json
query = ${query@Q}
payload = {
  "model": "grok-4-1-fast-reasoning",
  "input": [{"role": "user", "content": query}],
  "tools": [{"type": "web_search"}, {"type": "x_search"}],
}
print(json.dumps(payload))
PY
)

  curl -s 'https://api.x.ai/v1/responses' \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $XAI_API_KEY" \
    -d "$payload"
}

extract_json_array() {
  python3 - <<'PY'
import sys, json
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    print('[]')
    sys.exit(0)

for item in data.get('output', []):
    if item.get('type') != 'message':
        continue
    for c in item.get('content', []):
        if c.get('type') != 'output_text':
            continue
        text = (c.get('text') or '').strip()
        # strip accidental code fences
        if text.startswith('```'):
            text = text.split('\n',1)[1] if '\n' in text else text[3:]
        if text.endswith('```'):
            text = text[:-3]
        text = text.strip()
        if text.lower().startswith('json'):
            text = text[4:].strip()
        if text.startswith('['):
            print(text)
            sys.exit(0)
print('[]')
PY
}

# Prompts: surface stories + lots of links; no repeats handled downstream
SEO_RAW=$(xai_responses "Return ONLY a valid JSON array (no markdown) of 5-7 SEO & content marketing stories from the last 3-7 days. Each object: title, summary (2-3 sentences), url (canonical), source, tags (array), x_urls (array of 0-3 X links). Focus: Google updates, Discover, AEO/GEO evolution, AI search changes, notable SEO tools.")
PUB_RAW=$(xai_responses "Return ONLY a valid JSON array (no markdown) of 5-7 publishing & books stories from the last 3-10 days. Each object: title, summary (2-3 sentences), url (canonical), source, tags (array), x_urls (array of 0-3 X links). Focus: AI controversies in publishing/writing/editing, major contracts, major releases, BookTok/Bookstagram, and stories relevant to non-woke/traditional storytelling messaging (surface, don’t editorialize).")
POP_RAW=$(xai_responses "Return ONLY a valid JSON array (no markdown) of 5-7 pop culture & entertainment stories from the last 3-10 days. Each object: title, summary (2-3 sentences), url (canonical), source, tags (array), x_urls (array of 0-3 X links). Focus: film/TV/books, big cultural moments, and stories that illustrate audience backlash to preachy/woke entertainment (surface, don’t editorialize).")
BIZ_RAW=$(xai_responses "Return ONLY a valid JSON array (no markdown) of 4-6 general business & AI stories from the last 3-10 days. Each object: title, summary (2-3 sentences), url (canonical), source, tags (array), x_urls (array of 0-3 X links). Focus: AI impact on small businesses, new AI tools that actually work, and meaningful platform/product moves.")

SEO_JSON=$(echo "$SEO_RAW" | extract_json_array)
PUB_JSON=$(echo "$PUB_RAW" | extract_json_array)
POP_JSON=$(echo "$POP_RAW" | extract_json_array)
BIZ_JSON=$(echo "$BIZ_RAW" | extract_json_array)

python3 - <<PY
import json, hashlib
from pathlib import Path

data_dir = Path("$DATA_DIR")
period = "$PERIOD"
date_local = "$DATE_LOCAL"
timestamp = "$TIMESTAMP_UTC"

seen_path = data_dir / "seen.json"
seen = json.loads(seen_path.read_text())
seen_ids = set(seen.get('seenIds', []))

sections = [
  ('seo', json.loads('''$SEO_JSON''') if '''$SEO_JSON'''.strip().startswith('[') else []),
  ('publishing', json.loads('''$PUB_JSON''') if '''$PUB_JSON'''.strip().startswith('[') else []),
  ('popculture', json.loads('''$POP_JSON''') if '''$POP_JSON'''.strip().startswith('[') else []),
  ('business', json.loads('''$BIZ_JSON''') if '''$BIZ_JSON'''.strip().startswith('[') else []),
]

items = []
new_ids = []
for section, arr in sections:
  for it in arr:
    title = (it.get('title') or '').strip()
    url = (it.get('url') or '').strip()
    source = (it.get('source') or '').strip()
    if not title or not url:
      continue
    base = f"{title}|{url}|{source}".encode('utf-8')
    _id = hashlib.sha1(base).hexdigest()[:16]
    if _id in seen_ids:
      continue
    it['id'] = _id
    it['section'] = section
    it['period'] = period
    it['timestamp'] = timestamp
    it['tags'] = it.get('tags') or []
    it['x_urls'] = it.get('x_urls') or []
    items.append(it)
    new_ids.append(_id)

briefing = {
  'date': date_local,
  'period': period,
  'generated': timestamp,
  'items': items,
}

out = data_dir / f"briefing-{date_local}-{period}.json"
out.write_text(json.dumps(briefing, indent=2))
(data_dir / "current-briefing.json").write_text(json.dumps(briefing, indent=2))

seen_ids.update(new_ids)
seen_path.write_text(json.dumps({'seenIds': sorted(seen_ids)}, indent=2))

print(f"Wrote {len(items)} new items → {out}")
PY

cd "$DASHBOARD_DIR"
git add data scripts/generate-briefing.sh

git commit -m "Briefing: fix generator + no-repeat seen ledger" 2>/dev/null || true

git push origin main 2>/dev/null || echo "Push failed (check git credentials)"

echo "Done."