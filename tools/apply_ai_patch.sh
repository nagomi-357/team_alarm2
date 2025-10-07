#!/usr/bin/env bash
set -euo pipefail

PROMPT="${1:-"Add a feature to the Flutter app"}"
MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
BASE_PATH="$(git rev-parse --show-toplevel)"

die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null || die "Command not found: $1"; }

need git; need curl; need jq; need flutter; need dart
[[ -n "${OPENAI_API_KEY:-}" ]] || die "OPENAI_API_KEY is not set"

# 保護：未コミット変更があると中止
git -C "$BASE_PATH" diff --quiet || die "Working tree has uncommitted changes."
git -C "$BASE_PATH" diff --cached --quiet || die "Staged changes exist. Commit or reset first."

read -r -d '' SYS <<'EOS'
You are a coding assistant. Output ONLY a valid unified diff (git patch) rooted at the repository top.
No prose, no backticks. Paths relative to repo root. Begin with "diff --git".
EOS

read -r -d '' USER <<EOS
Project: Flutter Android app.

Task:
$PROMPT

Constraints:
- Output ONLY a unified diff starting with "diff --git".
- You may create/modify files under lib/, test/, android/ as needed.
- Keep "dart format" clean and pass "flutter analyze".
EOS

echo "Generating patch from model: $MODEL"
RAW=$(curl -sS https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @- <<JSON
{
  "model": "$MODEL",
  "messages": [
    {"role":"system","content": ${SYS@Q}},
    {"role":"user","content": ${USER@Q}}
  ],
  "temperature": 0
}
JSON
)

PATCH=$(echo "$RAW" | jq -r '.choices[0].message.content // ""')
[[ -n "$PATCH" ]] || die "Empty response from model."

# 余計なコードフェンスを除去
PATCH_CLEAN=$(echo "$PATCH" | sed -E 's/^```(diff|patch)?$//; s/^```$//;')
echo "$PATCH_CLEAN" > "$BASE_PATH/.ai.patch"

head -n 1 "$BASE_PATH/.ai.patch" | grep -q '^diff --git' || {
  echo "Model output (head):"; head -n 40 "$BASE_PATH/.ai.patch"
  die "Response is not a unified diff starting with 'diff --git'."
}

echo "Dry-run apply..."
git -C "$BASE_PATH" apply --check .ai.patch

echo "Applying patch..."
git -C "$BASE_PATH" apply --index .ai.patch

echo "Running format/analyze/test..."
dart format --output=none --set-exit-if-changed "$BASE_PATH" || dart format --fix "$BASE_PATH"

if ! flutter analyze; then
  echo "Analyzer failed. Reverting..."
  git -C "$BASE_PATH" reset --hard && git -C "$BASE_PATH" clean -fd
  die "Analyzer failed. Patch reverted."
fi

if ! flutter test; then
  echo "Tests failed. Reverting..."
  git -C "$BASE_PATH" reset --hard && git -C "$BASE_PATH" clean -fd
  die "Tests failed. Patch reverted."
fi

echo "OK. Staged diff:"
git -C "$BASE_PATH" diff --cached --stat
echo "Next: git commit -m 'feat: apply AI patch' && git push -u origin <branch>"
