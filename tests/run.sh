#!/usr/bin/env bash
# Fixtures for skill-health's own scripts. Builds a throwaway skills folder and a
# throwaway transcripts folder, then asserts each script fires on the gap it
# should and stays quiet on the skill that is fine. Exit 0 all pass, 1 any fail.
set -u
S="$(cd "$(dirname "$0")/../skills/skill-health/scripts" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok    $1"; else FAIL=$((FAIL+1)); echo "  FAIL  $1: want [$2] got [$3]"; fi; }
mk() { mkdir -p "$T/skills/$1"; printf -- '---\nname: %s\ndescription: %s\n%s\n---\n\n# %s\n%s\n' "$1" "$2" "$3" "$1" "$4" > "$T/skills/$1/SKILL.md"; }

# alpha: healthy. script exits 4, fixture names 4, has a trigger case, was invoked.
mk alpha "Do alpha things. Use when the user says alpha." "" "body"
printf 'import sys\nsys.exit(4)\n' > "$T/skills/alpha/tool.py"; printf 'check 4 $?\n' > "$T/skills/alpha/test-alpha.sh"
# beta: script with no fixture, no trigger case, never invoked.
mk beta "Do beta things." "" "body"; printf 'exit 2\n' > "$T/skills/beta/run.sh"
# gamma: user-invoked only; must be excluded from coverage and cost.
mk gamma "Gamma, typed by the user." "disable-model-invocation: true" "body"
# delta: oversize description and a 600-line body.
long=$(python -c "print('x'*1600)"); mk delta "$long" "" "$(python -c "print('line\n'*600)")"
# cases: alpha only, plus a negative naming beta (a negative does not count as coverage for beta... it does: the name appears)
printf 'do alpha\talpha\nsomething else\t-\n' > "$T/cases.tsv"
# transcripts: one Skill call to alpha today
mkdir -p "$T/projects/p"; printf '{"timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"alpha"}}]}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$T/projects/p/s.jsonl"

out=$(bash "$S/coverage.sh" --skills "$T/skills" --cases "$T/cases.tsv"); rc=$?
check "coverage: exit 3 on a gap" 3 "$rc"
check "coverage: names beta and delta, not gamma or alpha" "yes" "$(grep -q 'no trigger case: beta delta' <<<"$out" && echo yes || echo no)"
printf 'do beta\tbeta\ndo delta\tdelta\n' >> "$T/cases.tsv"
bash "$S/coverage.sh" --skills "$T/skills" --cases "$T/cases.tsv" >/dev/null; check "coverage: exit 0 once covered" 0 "$?"

out=$(bash "$S/fixtures.sh" --skills "$T/skills"); rc=$?
check "fixtures: exit 3 on a gap" 3 "$rc"
check "fixtures: alpha ok, beta missing" "yes" "$(grep -q 'ok    alpha' <<<"$out" && grep -q 'MISSING beta' <<<"$out" && echo yes || echo no)"
printf 'check 2 $?\n' > "$T/skills/beta/test-beta.sh"
bash "$S/fixtures.sh" --skills "$T/skills" >/dev/null; check "fixtures: exit 0 once beta has a fixture naming exit 2" 0 "$?"

out=$(python "$S/context-cost.py" --skills "$T/skills"); rc=$?
check "context-cost: exit 3 with flags" 3 "$rc"
check "context-cost: delta flagged over limit and over 500 lines" "yes" "$(grep 'delta' <<<"$out" | grep -q 'OVER 1536' && grep 'delta' <<<"$out" | grep -q 'split it' && echo yes || echo no)"
check "context-cost: gamma costs 0 chars" "yes" "$(grep '^gamma' <<<"$out" | awk '{print $2}' | grep -qx 0 && echo yes || echo no)"
mk delta "Short now." "" "body"
python "$S/context-cost.py" --skills "$T/skills" >/dev/null; check "context-cost: exit 0 once fixed" 0 "$?"

out=$(python "$S/usage.py" --skills "$T/skills" --projects "$T/projects" --days 30); rc=$?
check "usage: exit 3 when some skill never invoked" 3 "$rc"
check "usage: alpha counted once, beta never" "yes" "$(grep -q '^alpha .* 1 ' <<<"$out" && grep -q 'never invoked (3): beta, delta, gamma' <<<"$out" && echo yes || echo no)"

out=$(bash "$S/report.sh" --skills "$T/skills" --cases "$T/cases.tsv" --days 30); rc=$?
check "report: exit 3 when only gaps remain" 3 "$rc"
check "report: summary line names every check" "yes" "$(grep -q 'report: coverage=ok, context-cost=ok, usage=GAP, fixtures=ok' <<<"$out" && echo yes || echo no)"

if command -v claude >/dev/null; then
  out=$(REPEATS=0 bash "$S/trigger-eval.sh" --cases "$T/cases.tsv" 2>&1 | head -1)
  check "trigger-eval: parser self-check passes (no model calls)" "yes" "$(grep -q 'selfcheck ok' <<<"$out" && echo yes || echo no)"
else
  echo "  skip  trigger-eval self-check (claude not on PATH)"
fi
bash "$S/trigger-eval.sh" --cases "$T/nope.tsv" >/dev/null 2>&1; check "trigger-eval: exit 2 with no cases file" 2 "$?"

echo "skill-health tests: $PASS passed, $FAIL failed"
[ $FAIL = 0 ]
