"""context-cost.py: what do your skills cost before any of them does anything?

Every skill description sits in context on every turn (except skills with
disable-model-invocation, which only load when the user types them). This prints
chars and a rough token estimate (chars/4) per skill and in total, and flags:
  - description + when_to_use over 1,536 chars (Claude Code truncates there)
  - no description (Claude falls back to the first line of the body)
  - SKILL.md over 500 lines (loads in full on every invocation; split it)
Usage: context-cost.py [--skills DIR] [--limit 1536] [--max-lines 500]
Exit: 0 clean, 3 something flagged, 2 cannot run.
"""

import argparse, io, os, re, sys


def skills_dir(arg):
    if arg:
        return arg
    if os.environ.get("SKILL_HEALTH_SKILLS"):
        return os.environ["SKILL_HEALTH_SKILLS"]
    if os.path.isdir(".claude/skills"):
        return os.path.abspath(".claude/skills")
    return os.path.expanduser("~/.claude/skills")


def frontmatter(text):
    m = re.match(r"^---\r?\n(.*?)\r?\n---", text, re.S)
    if not m:
        return {}
    fm, cur, out = m.group(1), None, {}
    for line in fm.splitlines():
        k = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if k and not line.startswith((" ", "\t")):
            cur = k.group(1)
            out[cur] = k.group(2).strip()
        elif cur and line.startswith((" ", "\t")):
            out[cur] = (out[cur] + " " + line.strip()).strip()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills")
    ap.add_argument("--limit", type=int, default=1536)
    ap.add_argument("--max-lines", type=int, default=500)
    a = ap.parse_args()
    root = skills_dir(a.skills)
    if not os.path.isdir(root):
        print(f"no skills dir: {root}")
        return 2
    rows, flags, total = [], 0, 0
    for n in sorted(os.listdir(root)):
        d = os.path.join(root, n)
        if n.startswith("_") or not os.path.isdir(d):
            continue
        f = next(
            (
                os.path.join(d, x)
                for x in ("SKILL.md", "skill.md")
                if os.path.isfile(os.path.join(d, x))
            ),
            None,
        )
        if not f:
            continue
        text = io.open(f, encoding="utf-8", errors="replace").read()
        fm = frontmatter(text)
        desc = (fm.get("description", "") + " " + fm.get("when_to_use", "")).strip()
        lines = text.count("\n") + 1
        in_ctx = fm.get("disable-model-invocation", "").lower() != "true"
        chars = len(desc) if in_ctx else 0
        total += chars
        note = []
        if not fm.get("description"):
            note.append("NO DESCRIPTION")
            flags += 1
        if len(desc) > a.limit:
            note.append(f"OVER {a.limit} chars, truncated")
            flags += 1
        if lines > a.max_lines:
            note.append(f"{lines} lines, split it")
            flags += 1
        if not in_ctx:
            note.append("user-invoked only, not in context")
        rows.append((n, chars, lines, "; ".join(note)))
    print(f"{'skill':32} {'desc chars':>10} {'~tokens':>8} {'lines':>6}  notes")
    for n, c, l, note in sorted(rows, key=lambda r: -r[1]):
        print(f"{n:32} {c:10} {c // 4:8} {l:6}  {note}")
    print(
        f"\ncontext-cost: {len(rows)} skills, {total:,} description chars (~{total // 4:,} tokens) on every turn; {flags} flag(s)"
    )
    return 3 if flags else 0


if __name__ == "__main__":
    sys.exit(main())
