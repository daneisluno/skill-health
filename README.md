# skill-health

A regression suite for a Claude Code skills folder. It answers five questions
the skills themselves cannot:

1. **Does each skill still fire on the prompts it should?** Every case runs three
   times against a fresh `claude -p`; a case passes at two of three. A call that
   dies (usage limit, auth, network) is an error, never a quiet pass, and three in
   a row abort the run.
2. **Which skills have never been shown to fire?** Coverage: model-invocable skills
   with no trigger case.
3. **What do the skills cost before any of them does anything?** Every description
   is in context on every turn. Chars, a token estimate, and the ones over Claude
   Code's 1,536-character truncation or 500-line guidance.
4. **Which skills has the model actually used?** Read from session transcripts,
   not self-report. Never-invoked in N days is the prune list.
5. **Which skill scripts have no test?** Scripts without a `test-*.sh`, and exit
   codes no fixture names.

Questions 2 to 5 are free and run in seconds. Question 1 spends tokens and takes
a few minutes per case; run it weekly.

## Install

```bash
claude plugin install skill-health@<your-marketplace>
```

or clone this repo and add it with `claude --plugin-dir ./skill-health` (unverified
from memory: check `claude plugin --help` for the current flag).

Requires bash, python 3, and the `claude` CLI on PATH. Windows works under Git Bash.

## Use

```bash
# free, all offline checks
bash skills/skill-health/scripts/report.sh

# spends tokens: every case x3
bash skills/skill-health/scripts/trigger-eval.sh --cases .claude/skill-health-cases.tsv
```

Or in a session: `/skill-health report`, `/skill-health triggers`.

Cases are one per line, tab separated: prompt, then `skill-name`, `!skill-name`
or `-`. See `skills/skill-health/scripts/cases.example.tsv`. Write near-miss
negatives; obviously unrelated prompts test nothing.

Exit codes everywhere: 0 clean, 3 coverage gap (a to-do, nothing is broken),
1 real failure, 2 the tool could not run.

## Schedule

Set `SKILL_HEALTH_STATUS=<file>` and each run appends one dated summary line, so
the file is your history. Nightly `report.sh`, weekly `trigger-eval.sh`, by cron
or Task Scheduler.

## Why it exists

Two things happened on the same day building the first version:

- A one-turn, single-run harness reported two skills broken. They were fine; the
  model reads context before it loads a skill, and one run is an anecdote.
- A usage limit hit mid-run. Every later call died, the parser read "no result"
  as "no skill", eight negatives passed vacuously and nineteen positives failed.

- A run reported seven dead calls in forty-two. The raw streams, once kept, showed
  every one had already invoked the right skill and then hit the turn cap; the CLI
  reports that as an error result and the parser threw the skill call away.

All three are now fixtures in `tests/run.sh`, which is the first thing to run
after any change here. The pattern is the same each time: the harness lied in a
direction that looked like a model failure, and only the kept evidence said otherwise.

## Relation to Anthropic's skill-creator

skill-creator tunes one skill's description with generated prompts. skill-health
is the regression suite across the whole folder, on a schedule, with cost and
usage beside the verdict. Use both.

## Licence

MIT.
