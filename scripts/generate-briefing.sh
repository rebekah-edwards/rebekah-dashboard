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

mkdir -p "$DATA_DIR"

python3 - <<'PY'
import json, subprocess, os, hashlib
from pathlib import Path
from datetime import datetime, timezone

period=os.environ.get('PERIOD','morning')

def now_utc():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

def today_local():
    # ok for our use; launchd is local-time scheduled
    return datetime.now().strftime('%Y-%m-%d')

DATA_DIR=Path(os.environ['DATA_DIR'])
SEEN_FILE=DATA_DIR/'seen.json'
if not SEEN_FILE.exists():
    SEEN_FILE.write_text(json.dumps({'seenIds':[]},indent=2))

seen=json.loads(SEEN_FILE.read_text())
seen_ids=set(seen.get('seenIds',[]))

key=os.environ['XAI_API_KEY']
MODEL='grok-4-1-fast-reasoning'
TOOLS=[{'type':'web_search'},{'type':'x_search'}]

def call(prompt:str):
    payload={'model':MODEL,'input':[{'role':'user','content':prompt}], 'tools': TOOLS}
    r=subprocess.run([
        'curl','-s','https://api.x.ai/v1/responses',
        '-H','Content-Type: application/json',
        '-H',f'Authorization: Bearer {key}',
        '-d',json.dumps(payload)
    ], capture_output=True, text=True, check=True)
    data=json.loads(r.stdout)
    # Surface API-level errors (e.g. credits exhausted, auth failures)
    if 'error' in data or 'code' in data:
        err_msg = data.get('error') or data.get('code','unknown error')
        raise RuntimeError(f"xAI API error: {err_msg}")
    out=''
    for item in data.get('output',[]):
        if item.get('type')=='message':
            for c in item.get('content',[]):
                if c.get('type')=='output_text':
                    out=c.get('text','')
                    break
    out=out.strip()
    if out.startswith('```'):
        out=out.split('\n',1)[1] if '\n' in out else out[3:]
    if out.endswith('```'):
        out=out[:-3]
    out=out.strip()
    if out.lower().startswith('json'):
        out=out[4:].strip()
    arr=json.loads(out) if out.startswith('[') else []
    return arr

prompts={
 'seo':"Return ONLY a valid JSON array (no markdown) of 5-7 SEO & content marketing stories from the last 3-7 days. Each object: title, summary (2-3 sentences), url (canonical), source, tags (array), x_urls (array of 0-3 X links). Focus: what’s trending, Google updates, Discover, AEO/GEO evolution, AI search changes, notable SEO tools.",
 'publishing':"Return ONLY a valid JSON array (no markdown) of 5-7 publishing & books stories from the last 3-10 days. Each object: title, summary (2-3 sentences), url (canonical), source, tags (array), x_urls (array of 0-3 X links). Focus: AI controversies in publishing/writing/editing, major contracts, major releases, BookTok/Bookstagram, and stories relevant to non-woke/traditional storytelling messaging (surface, don’t editorialize).",
 'popculture':"Return ONLY a valid JSON array (no markdown) of 5-7 pop culture & entertainment stories from the last 3-10 days. Each object: title, summary (2-3 sentences), url (canonical), source, tags (array), x_urls (array of 0-3 X links). Focus: major entertainment moments, and stories that illustrate audience backlash to preachy/woke entertainment (surface, don’t editorialize).",
 'business':"Return ONLY a valid JSON array (no markdown) of 4-6 general business & AI stories from the last 3-10 days. Each object: title, summary (2-3 sentences), url (canonical), source, tags (array), x_urls (array of 0-3 X links). Focus: AI impact on small businesses, new AI tools that actually work, and meaningful platform/product moves.",
}

items=[]
new_ids=[]
for section,p in prompts.items():
    arr=call(p)
    for it in arr:
        title=(it.get('title') or '').strip(); url=(it.get('url') or '').strip(); source=(it.get('source') or '').strip()
        if not title or not url:
            continue
        _id=hashlib.sha1(f"{title}|{url}|{source}".encode()).hexdigest()[:16]
        if _id in seen_ids:
            continue
        it.update({
            'id':_id,
            'section':section,
            'period':period,
            'timestamp':now_utc(),
            'tags': it.get('tags') or [],
            'x_urls': it.get('x_urls') or [],
        })
        items.append(it)
        new_ids.append(_id)

briefing={
  'date': today_local(),
  'period': period,
  'generated': now_utc(),
  'items': items,
}

out=DATA_DIR/f"briefing-{briefing['date']}-{period}.json"
out.write_text(json.dumps(briefing,indent=2))
(DATA_DIR/'current-briefing.json').write_text(json.dumps(briefing,indent=2))

seen_ids.update(new_ids)
SEEN_FILE.write_text(json.dumps({'seenIds': sorted(seen_ids)}, indent=2))

print(f"Wrote {len(items)} new items → {out}")
PY
