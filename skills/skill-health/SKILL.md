---
name: skill-health
description: Check whether a Claude Code skills folder is earning its place. Runs the offline report (trigger-case coverage, per-turn context cost of every description, skills never invoked in N days, skill scripts with no fixture) and, on request, the LLM-backed trigger eval (each case three times, pass at two of three, dead calls flagged not scored, cost on the summary line). Use when the user asks whether their skills work, why a skill did not fire, what their skills cost, to prune skills, or says skill health, skill audit, trigger eval.
argument-hint: "[report|triggers|coverage|cost|usage|fixtures] [--skills DIR] [--cases FILE]"
allowed-tools: Bash, Read, Glob, Grep
---

# skill-health

Skills are instructions that only help if the model actually loads them, and each
one costs context on every turn whether it loads or not. This skill measures both
sides. Run the offline report first; it is free. Run the trigger eval when you
need proof the model reaches for a skill, and expect it to spend tokens.

## Commands

All scripts live in `${CLAUDE_SKILL_DIR}/scripts`. Skills folder resolution, in
order: `--skills DIR`, `$SKILL_HEALTH_SKILLS`, `.claude/skills` in the current
directory, `~/.claude/skills`. Cases file: `--cases FILE`, `$SKILL_HEALTH_CASES`,
`.claude/skill-health-cases.tsv`, `~/.claude/skill-health-cases.tsv`.

| Task | Command | Spends tokens |
|---|---|---|
| Everything offline, one report | `bash ${CLAUDE_SKILL_DIR}/scripts/report.sh` | no |
| Trigger-case coverage | `bash ${CLAUDE_SKILL_DIR}/scripts/coverage.sh` | no |
| Context cost per description, oversize SKILL.md files | `python ${CLAUDE_SKILL_DIR}/scripts/context-cost.py` | no |
| Usage from transcripts, never-invoked list | `python ${CLAUDE_SKILL_DIR}/scripts/usage.py --days 90` | no |
| Scripts without a fixture, unnamed exit codes | `bash ${CLAUDE_SKILL_DIR}/scripts/fixtures.sh` | no |
| Trigger eval, all cases x3 | `bash ${CLAUDE_SKILL_DIR}/scripts/trigger-eval.sh` | yes |

Exit codes are the same everywhere: 0 clean, 3 a coverage gap (something is
missing, nothing is broken), 1 a real failure, 2 the tool itself could not run.
Report 3 as a to-do, never as a broken skill.

## Writing trigger cases

One case per line, tab separated: the prompt, then the expectation.

```
Should we charge £49 a month or go contact-us pricing?	pricing-council
Why does this test fail only on the second run?	!pricing-council
Rename fmt_money to format_money across the repo.	-
```

`name` means that skill must fire in at least 2 of 3 runs. `!name` means it
must not. `-` means no skill at all. Write near-miss negatives: a prompt that
shares words with the skill but needs something else is worth ten obviously
unrelated ones. Give the model something it can act on; "tighten this paragraph"
with no paragraph makes it go looking for a file instead of loading the skill.

## Reading the trigger eval

- `ok 3/3 [name] [name] [name]` is a pass. `ok 2/3` passed but is worth a look.
- `FAIL 0/3 [-] [-] [-]` on a positive case usually means the description does
  not contain the words the user actually says. Add them. Anthropic's advice is
  to make descriptions a little pushy: "use this whenever the user says X, Y or Z,
  even if they do not say the skill's name".
- `[ERR]` is a dead call: usage limit, auth, network. It never counts as a pass.
  Three in a row abort the run with exit 2 and an ABORTED status line, because a
  run that continues after that scores every negative as a vacuous pass.
- The summary line carries the cost from the CLI's own accounting. Do not quote
  a cost you did not read from that line.

## Interpreting the offline report

- **Coverage gap**: a model-invocable skill with no trigger case has never been
  shown to fire. Either write a case or ask why it exists.
- **Context cost**: every description is in context on every turn. The total is
  what your skills cost before any of them does anything. Descriptions over the
  combined 1,536-character limit are truncated by Claude Code; SKILL.md over 500
  lines loads in full on every invocation, split it.
- **Never invoked in N days**: read from transcripts, not self-report. A skill
  with no invocations and no trigger case is a candidate for the archive.
- **Fixtures**: a skill that ships a script without a test can be broken without
  anyone noticing. Every non-zero exit the script can take should be named in
  its fixture.

## Scheduling

Run `report.sh` nightly and `trigger-eval.sh` weekly with
`SKILL_HEALTH_STATUS=<file>` set; each run appends one dated summary line there,
so the file is the history. Windows Task Scheduler and cron both work; the
scripts need bash, python 3 and the `claude` CLI on PATH.

## Two lessons this tool exists because of

1. One run of a non-deterministic model is an anecdote. A single-turn, n=1
   harness once reported two skills broken that were fine.
2. A dead call is not a quiet one. A usage limit mid-run once turned 19 cases
   into vacuous verdicts because the parser read "no result" as "no skill".
