#!/usr/bin/env bash
# Generates a categorized changelog from git commits between two refs.
# Usage: ./scripts/generate-changelog.sh [from_ref] [to_ref]
#   from_ref: starting ref (exclusive), defaults to previous tag
#   to_ref:   ending ref (inclusive), defaults to HEAD
#
# Categorizes commits by prefix:
#   feat/add/feature → ✨ Features
#   fix/bugfix       → 🐛 Bug Fixes
#   perf/optimize    → ⚡ Performance
#   docs/doc         → 📚 Documentation
#   refactor/clean   → 🔧 Improvements
#   (everything else)→ 📦 Other Changes

set -euo pipefail

TO_REF="${2:-HEAD}"

# Find the previous tag for the starting point
if [[ -n "${1:-}" ]]; then
  FROM_REF="$1"
else
  FROM_REF=$(git describe --tags --abbrev=0 "$TO_REF^" 2>/dev/null || echo "")
fi

# Build the log range
if [[ -n "$FROM_REF" ]]; then
  RANGE="${FROM_REF}..${TO_REF}"
  SINCE_TEXT="since ${FROM_REF}"
else
  RANGE="$TO_REF"
  SINCE_TEXT="(all commits)"
fi

# Collect commits: hash and subject
COMMITS=$(git log --pretty=format:"%H %s" "$RANGE" --no-merges 2>/dev/null || true)

if [[ -z "$COMMITS" ]]; then
  echo "No commits found ${SINCE_TEXT}."
  exit 0
fi

# Categorize
FEATURES=""
FIXES=""
PERF=""
DOCS=""
IMPROVEMENTS=""
OTHER=""

while IFS= read -r line; do
  hash="${line%% *}"
  short_hash="${hash:0:7}"
  subject="${line#* }"

  # Normalize to lowercase for matching
  lower=$(echo "$subject" | tr '[:upper:]' '[:lower:]')
  entry="- ${subject} (\`${short_hash}\`)"

  case "$lower" in
    feat:*|feat\(*|add\ *|add:*|feature:*|feature\ *)
      FEATURES="${FEATURES}${entry}"$'\n' ;;
    fix:*|fix\ *|fix\(*|bugfix:*|bugfix\ *)
      FIXES="${FIXES}${entry}"$'\n' ;;
    perf:*|perf\(*|optimize*|performance*)
      PERF="${PERF}${entry}"$'\n' ;;
    docs:*|docs\(*|doc:*|doc\ *)
      DOCS="${DOCS}${entry}"$'\n' ;;
    refactor:*|refactor\(*|refactor\ *|clean*|improve*|overhaul*|tweak*)
      IMPROVEMENTS="${IMPROVEMENTS}${entry}"$'\n' ;;
    *)
      OTHER="${OTHER}${entry}"$'\n' ;;
  esac
done <<< "$COMMITS"

# Output
output=""

if [[ -n "$FEATURES" ]]; then
  output+="### ✨ Features"$'\n\n'"${FEATURES}"$'\n'
fi
if [[ -n "$FIXES" ]]; then
  output+="### 🐛 Bug Fixes"$'\n\n'"${FIXES}"$'\n'
fi
if [[ -n "$PERF" ]]; then
  output+="### ⚡ Performance"$'\n\n'"${PERF}"$'\n'
fi
if [[ -n "$IMPROVEMENTS" ]]; then
  output+="### 🔧 Improvements"$'\n\n'"${IMPROVEMENTS}"$'\n'
fi
if [[ -n "$DOCS" ]]; then
  output+="### 📚 Documentation"$'\n\n'"${DOCS}"$'\n'
fi
if [[ -n "$OTHER" ]]; then
  output+="### 📦 Other Changes"$'\n\n'"${OTHER}"$'\n'
fi

echo "$output"
