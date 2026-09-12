#!/usr/bin/env bash
# report.sh: every offline check in one run. Free; no model calls.
# Usage: report.sh [--skills DIR] [--cases FILE] [--days 90]
#   env SKILL_HEALTH_STATUS=<file>: append one dated summary line.
# Exit: 0 clean, 3 any coverage gap, 1 any check failed to run cleanly.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"; sh_parse_args "$@"
DAYS=90; for ((i=0;i<${#REST[@]};i++)); do [ "${REST[$i]}" = "--days" ] && DAYS="${REST[$((i+1))]}"; done
PY=$(command -v python || command -v python3)
worst=0; summary=""
run() {  # $1=label, rest=command
  local label="$1"; shift
  echo "## $label"; "$@"; local rc=$?
  case $rc in 0) v=ok;; 3) v=GAP;; *) v="FAIL($rc)";; esac
  [ $rc -gt $worst ] && [ $rc -ne 3 ] && worst=$rc
  [ $rc -eq 3 ] && [ $worst -eq 0 ] && worst=3
  summary="$summary${summary:+, }$label=$v"; echo
}
echo "skill-health report  $(date '+%Y-%m-%d %H:%M')  skills: $SKILLS"; echo
run coverage bash "$HERE/coverage.sh" --skills "$SKILLS" --cases "$CASES"
run context-cost "$PY" "$HERE/context-cost.py" --skills "$SKILLS"
run usage "$PY" "$HERE/usage.py" --skills "$SKILLS" --days "$DAYS"
run fixtures bash "$HERE/fixtures.sh" --skills "$SKILLS"
line="report: $summary"
echo "$line"
[ -n "${SKILL_HEALTH_STATUS:-}" ] && printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "$line" >> "$SKILL_HEALTH_STATUS"
exit $worst
