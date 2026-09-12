#!/usr/bin/env bash
# trigger-eval.sh: does the model reach for the right skill on a prompt it should,
# and leave it alone on one it should not?
#
# Each case runs REPEATS times (default 3), up to MAX_TURNS model turns (default 4)
# on MODEL (default sonnet), MCP off, tools capped to TOOLS (default
# Skill,Read,Glob,Grep). A case passes when at least MIN_PASS runs agree (default
# 2). One run of a non-deterministic model is an anecdote.
#
# Self-check first: the parser is fed a canned FIRE, QUIET, DEAD and EMPTY stream
# before any real call. A call with no successful result event is ERR, never
# "no skill"; ERR never passes, and three in a row abort the run (exit 2).
#
# Usage: trigger-eval.sh [--skills DIR] [--cases FILE]
#   env REPEATS MIN_PASS MAX_TURNS MODEL TOOLS SKILL_HEALTH_STATUS
# Exit: 0 all pass, 1 any case below MIN_PASS, 2 harness error or aborted.
set -uo pipefail
. "$(dirname "$0")/lib.sh"; sh_parse_args "$@"
REPEATS="${REPEATS:-3}"; MIN_PASS="${MIN_PASS:-2}"; MAX_TURNS="${MAX_TURNS:-4}"
MODEL="${MODEL:-sonnet}"; TOOLS="${TOOLS:-Skill,Read,Glob,Grep}"
STATUS="${SKILL_HEALTH_STATUS:-}"
[ -f "$CASES" ] || { echo "no cases file: $CASES (write one; see SKILL.md)"; exit 2; }
command -v claude >/dev/null || { echo "claude not on PATH"; exit 2; }
command -v python >/dev/null || command -v python3 >/dev/null || { echo "python not on PATH"; exit 2; }
PY=$(command -v python || command -v python3)

parse() {  # stdin: stream-json -> "skills|-|ERR<TAB>cost"
  "$PY" -c '
import sys,json
seen=[]; cost=""; ok=False
for line in sys.stdin:
    try: j=json.loads(line)
    except Exception: continue
    if j.get("type")=="result":
        cost=str(j.get("total_cost_usd",""))
        ok = (not j.get("is_error")) and j.get("subtype","success")=="success"
    if j.get("type")!="assistant": continue
    for b in j.get("message",{}).get("content",[]):
        if b.get("type")=="tool_use" and b.get("name")=="Skill":
            seen.append(str(b.get("input",{}).get("skill","?")).split(":")[-1])
if not ok: print("ERR\t"+cost)
else: print((",".join(dict.fromkeys(seen)) if seen else "-")+"\t"+cost)'
}

fire='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"alpha"}}]}}
{"type":"result","total_cost_usd":0.01}'
quiet='{"type":"assistant","message":{"content":[{"type":"text","text":"Reading."},{"type":"tool_use","name":"Read","input":{"file_path":"x"}}]}}
{"type":"result","total_cost_usd":0.02}'
dead='{"type":"assistant","message":{"content":[{"type":"text","text":"x"}]}}
{"type":"result","is_error":true,"subtype":"error_during_execution","total_cost_usd":0}'
sc1=$(printf '%s\n' "$fire" | parse); sc2=$(printf '%s\n' "$quiet" | parse)
sc3=$(printf '%s\n' "$dead" | parse); sc4=$(printf '' | parse)
if [ "$sc1" != $'alpha\t0.01' ] || [ "$sc2" != $'-\t0.02' ] || [ "${sc3%%$'\t'*}" != "ERR" ] || [ "${sc4%%$'\t'*}" != "ERR" ]; then
  echo "SELFCHECK FAIL: parser returned [$sc1] [$sc2] [$sc3] [$sc4]"; exit 2
fi
echo "  selfcheck ok (parser: fire, quiet, dead call, empty stream)"

pass=0; fail=0; total_cost=0; errs=0; consecutive_err=0
while IFS=$'\t' read -r prompt expected; do
  case "$prompt" in ''|'#'*) continue;; esac
  hits=0; gots=""
  # The REPEATS calls for one case run in parallel (they are independent), then
  # are read back in order. 2026-09-12: sequential ran at ~17 min per case.
  RUNDIR=$(mktemp -d)
  for ((i=1;i<=REPEATS;i++)); do
    ( claude -p "$prompt" --model "$MODEL" --max-turns "$MAX_TURNS" --output-format stream-json --verbose --strict-mcp-config --tools "$TOOLS" 2>/dev/null | parse > "$RUNDIR/$i" ) &
  done
  wait
  for ((i=1;i<=REPEATS;i++)); do
    out=$(cat "$RUNDIR/$i" 2>/dev/null)
    got="${out%%$'\t'*}"; cost="${out#*$'\t'}"
    [ -n "$cost" ] && total_cost=$("$PY" -c "print(round($total_cost+$cost,4))")
    if [ "$got" = "ERR" ]; then
      errs=$((errs+1)); consecutive_err=$((consecutive_err+1)); gots="$gots${gots:+ }[ERR]"
      if [ "$consecutive_err" -ge 3 ]; then
        echo "ABORT: 3 dead calls in a row (usage limit, auth or network). $pass passed, $fail failed before the abort; nothing after this is a verdict."
        [ -n "$STATUS" ] && printf '%s trigger-eval: ABORTED after %s cases, 3 dead calls in a row (cost $%s)\n' "$(date '+%Y-%m-%d %H:%M')" "$((pass+fail))" "$total_cost" >> "$STATUS"
        exit 2
      fi
      continue
    fi
    consecutive_err=0
    case "$expected" in
      -)   [ "$got" = "-" ] && ok=1 || ok=0 ;;
      !*)  case ",$got," in *",${expected#!},"*) ok=0;; *) ok=1;; esac ;;
      *)   case ",$got," in *",$expected,"*) ok=1;; *) ok=0;; esac ;;
    esac
    hits=$((hits+ok)); gots="$gots${gots:+ }[$got]"
  done
  rm -rf "$RUNDIR"
  if [ "$hits" -ge "$MIN_PASS" ]; then pass=$((pass+1)); echo "  ok    $hits/$REPEATS $gots :: $prompt"
  else fail=$((fail+1)); echo "  FAIL  $hits/$REPEATS want=$expected $gots :: $prompt"; fi
done < "$CASES"
summary="trigger-eval: $pass passed, $fail failed (cases x$REPEATS, pass at >=$MIN_PASS, model $MODEL; dead calls $errs; cost \$$total_cost)"
echo "$summary"
[ -n "$STATUS" ] && printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "$summary" >> "$STATUS"
[ $fail = 0 ]
