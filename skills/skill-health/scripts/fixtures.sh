#!/usr/bin/env bash
# fixtures.sh: every skill that ships a script (.py/.sh/.ps1) must ship a
# test-*.sh fixture, and every non-zero exit the script can take (sys.exit(N),
# exit N) must be named in that fixture. A guard branch no fixture exercises is
# a branch that can break without anyone noticing.
# Usage: fixtures.sh [--skills DIR]
# Exit: 0 all covered, 3 coverage gap, 2 cannot run.
set -u
. "$(dirname "$0")/lib.sh"; sh_parse_args "$@"
[ -d "$SKILLS" ] || { echo "no skills dir: $SKILLS"; exit 2; }
missing=0; checked=0
for d in "$SKILLS"/*/; do
  name=$(basename "$d"); case "$name" in _*) continue;; esac
  scripts=$(find "$d" -maxdepth 2 -type f \( -name '*.py' -o -name '*.sh' -o -name '*.ps1' \) ! -name 'test-*' 2>/dev/null)
  [ -z "$scripts" ] && continue
  checked=$((checked+1))
  fixtures=$(find "$d" -maxdepth 2 -type f -name 'test-*.sh' 2>/dev/null)
  if [ -z "$fixtures" ]; then
    echo "  MISSING $name: scripts but no test-*.sh"; missing=$((missing+1)); continue
  fi
  fx=$(cat $fixtures)
  before=$missing
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    codes=$(grep -oE 'sys\.exit\(([0-9]+)\)|(^|[^a-z_])exit ([0-9]+)' "$s" | grep -oE '[0-9]+' | sort -un)
    for c in $codes; do
      [ "$c" = 0 ] && continue
      grep -qE "(^|[^0-9])$c([^0-9]|$)" <<<"$fx" || { echo "  MISSING $name: $(basename "$s") can exit $c, no fixture case names it"; missing=$((missing+1)); }
    done
  done <<<"$scripts"
  [ "$missing" = "$before" ] && echo "  ok    $name"
done
echo "fixtures: $checked skill(s) ship scripts, $missing gap(s)"
[ "$missing" -eq 0 ] && exit 0 || exit 3
