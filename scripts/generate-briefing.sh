#!/bin/bash
# Generate a dashboard briefing using Grok and push to GitHub
# Usage: ./generate-briefing.sh [morning|afternoon]

set -e

PERIOD="${1:-morning}"
WORKSPACE="/Users/clankeredwards/.openclaw/workspace"
DASHBOARD_DIR="$WORKSPACE/dashboard"
DATA_DIR="$DASHBOARD_DIR/data"
ENV_FILE="$WORKSPACE/.env"

# Load env
source "$ENV_FILE"

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$DATA_DIR"

echo "Generating $PERIOD briefing for $DATE..."

# Function to call Grok
grok_search() {
  local query="$1"
  local tool_type="${2:-web_search}"
  
  local tool_json
  if [ "$tool_type" = "x_search" ]; then
    tool_json='{"type":"x_search"}'
  else
    tool_json='{"type":"web_search"}'
  fi
  
  curl -s 'https://api.x.ai/v1/responses' \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $XAI_API_KEY" \
    -d "$(cat <<EOF
{
  "model": "grok-4-1-fast-reasoning",
  "input": [{"role": "user", "content": "$query"}],
  "tools": [$tool_json]
}
EOF
)"
}

# Generate each section
echo "Fetching SEO news..."
SEO_RAW=$(grok_search "Return ONLY a valid JSON array (no markdown, no code fences) of the top 4-5 SEO and content marketing news items from today or this week (mid-February 2026). Each object should have: title (string), summary (2-3 sentences string), url (source link string), source (site name string), tags (array of strings). Focus on Google algorithm updates, AI search changes, content strategy trends, and tool announcements.")

echo "Fetching Publishing news..."
PUB_RAW=$(grok_search "Return ONLY a valid JSON array (no markdown, no code fences) of the top 4-5 book publishing and fiction industry news items from today or this week (mid-February 2026). Each object should have: title (string), summary (2-3 sentences string), url (source link string), source (site name string), tags (array of strings). Focus on crowdfunding campaigns for books, BookTok/Bookstagram trends, author controversies, viral posts about non-woke books or traditional storytelling, and speculative fiction news.")

echo "Fetching Pop Culture news..."
POP_RAW=$(grok_search "Return ONLY a valid JSON array (no markdown, no code fences) of the top 3-4 pop culture and entertainment news items from today or this week (mid-February 2026). Each object should have: title (string), summary (2-3 sentences string), url (source link string), source (site name string), tags (array of strings). Focus on book-to-film/TV adaptations, fantasy and sci-fi media news, and major entertainment stories.")

echo "Fetching Business & AI news..."
BIZ_RAW=$(grok_search "Return ONLY a valid JSON array (no markdown, no code fences) of the top 3-4 business and AI news items relevant to small business owners from today or this week (mid-February 2026). Each object should have: title (string), summary (2-3 sentences string), url (source link string), source (site name string), tags (array of strings). Focus on AI tools for business, small business trends, and major tech developments that impact entrepreneurs. No crypto.")

# Extract content text from each response
extract_content() {
  echo "$1" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('output', []):
    if item.get('type') == 'message':
        for c in item.get('content', []):
            if c.get('type') == 'output_text':
                text = c['text'].strip()
                # Remove markdown code fences if present
                if text.startswith('\`\`\`'):
                    text = text.split('\n', 1)[1] if '\n' in text else text[3:]
                if text.endswith('\`\`\`'):
                    text = text[:-3]
                text = text.strip()
                if text.startswith('json'):
                    text = text[4:].strip()
                print(text)
                sys.exit(0)
print('[]')
"
}

SEO_JSON=$(extract_content "$SEO_RAW")
PUB_JSON=$(extract_content "$PUB_RAW")
POP_JSON=$(extract_content "$POP_RAW")
BIZ_JSON=$(extract_content "$BIZ_RAW")

# Build the full briefing JSON
python3 -c "
import json, sys

seo = json.loads('''$SEO_JSON''') if '''$SEO_JSON'''.strip().startswith('[') else []
pub = json.loads('''$PUB_JSON''') if '''$PUB_JSON'''.strip().startswith('[') else []
pop = json.loads('''$POP_JSON''') if '''$POP_JSON'''.strip().startswith('[') else []
biz = json.loads('''$BIZ_JSON''') if '''$BIZ_JSON'''.strip().startswith('[') else []

items = []
for item in seo:
    item['section'] = 'seo'
    item['period'] = '$PERIOD'
    item['timestamp'] = '$TIMESTAMP'
    items.append(item)
for item in pub:
    item['section'] = 'publishing'
    item['period'] = '$PERIOD'
    item['timestamp'] = '$TIMESTAMP'
    items.append(item)
for item in pop:
    item['section'] = 'popculture'
    item['period'] = '$PERIOD'
    item['timestamp'] = '$TIMESTAMP'
    items.append(item)
for item in biz:
    item['section'] = 'business'
    item['period'] = '$PERIOD'
    item['timestamp'] = '$TIMESTAMP'
    items.append(item)

briefing = {
    'date': '$DATE',
    'period': '$PERIOD',
    'generated': '$TIMESTAMP',
    'items': items
}

print(json.dumps(briefing, indent=2))
" > "$DATA_DIR/briefing-${DATE}-${PERIOD}.json" 2>/dev/null

# Also write as the current briefing
cp "$DATA_DIR/briefing-${DATE}-${PERIOD}.json" "$DATA_DIR/current-briefing.json"

echo "Briefing saved to $DATA_DIR/briefing-${DATE}-${PERIOD}.json"

# Push to GitHub
cd "$DASHBOARD_DIR"
git add -A
git commit -m "Update $PERIOD briefing for $DATE" 2>/dev/null || echo "No changes to commit"
git push origin main 2>/dev/null || echo "Push failed"

echo "Done! Briefing generated and deployed."
