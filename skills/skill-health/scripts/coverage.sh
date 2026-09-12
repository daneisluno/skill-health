#!/usr/bin/env bash
# coverage.sh: which model-invocable skills have no trigger case?
# Skills with disable-model-invocation are excluded (the user invokes those by name).
# Usage: coverage.sh [--skills DIR] [--cases FILE]
# Exit: 0 all covered, 3 coverage gap, 2 cannot run.
set -u
. "$(dirname "$0")/lib.sh"; sh_parse_args "$@"
[ -d "$SKILLS" ] || { echo "no skills dir: $SKILLS"; exit 2; }
covered=$(grep -v '^#' "$CASES" 2>/dev/null | cut -f2 | sed 's/^!//' | grep -v '^-$' | sort -u)
total=0; miss=0; missing=""
for d in "$SKILLS"/*/; do
  n=$(basename "$d"); case "$n" in _*) continue;; esac
  f=$(sh_skill_md "$d") || continue
  grep -qE '^disable-model-invocation:[[:space:]]*true' "$f" && continue
  total=$((total+1))
  grep -qx "$n" <<<"$covered" || { miss=$((miss+1)); missing="$missing $n"; }
done
echo "coverage: $((total-miss))/$total model-invocable skills have a trigger case"
[ "$miss" -gt 0 ] && echo "  no trigger case:$missing"
[ -f "$CASES" ] || echo "  (no cases file at $CASES)"
[ "$miss" -eq 0 ] && exit 0 || exit 3
