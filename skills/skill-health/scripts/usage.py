"""usage.py: which skills were actually invoked, from the transcripts, not from memory.

Scans Claude Code session transcripts (~/.claude/projects/*/*.jsonl by default)
for Skill tool calls and /slash invocations in the last N days, then lists every
skill on disk with its count and last use, and the ones never invoked.
Usage: usage.py [--skills DIR] [--projects DIR] [--days 90]
Exit: 0 every skill invoked at least once, 3 some never invoked, 2 cannot run.
"""

import argparse, collections, datetime as dt, glob, json, os, re, sys


def skills_dir(arg):
    if arg:
        return arg
    if os.environ.get("SKILL_HEALTH_SKILLS"):
        return os.environ["SKILL_HEALTH_SKILLS"]
    if os.path.isdir(".claude/skills"):
        return os.path.abspath(".claude/skills")
    return os.path.expanduser("~/.claude/skills")


CMD = re.compile(r"<command-name>/?([A-Za-z0-9:_-]+)</command-name>")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills")
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--days", type=int, default=90)
    a = ap.parse_args()
    root = skills_dir(a.skills)
    if not os.path.isdir(root):
        print(f"no skills dir: {root}")
        return 2
    if not os.path.isdir(a.projects):
        print(f"no transcripts dir: {a.projects}")
        return 2
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=a.days)
    uses, last = collections.Counter(), {}
    for path in glob.glob(os.path.join(a.projects, "*", "*.jsonl")):
        try:
            lines = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with lines:
            for line in lines:
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts = r.get("timestamp")
                if not ts or r.get("isSidechain"):
                    continue
                try:
                    when = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except ValueError:
                    continue
                if when < cutoff:
                    continue
                msg = r.get("message") or {}
                content = msg.get("content")
                hits = []
                if msg.get("role") == "assistant" and isinstance(content, list):
                    for b in content:
                        if (
                            isinstance(b, dict)
                            and b.get("type") == "tool_use"
                            and (b.get("name") or "").lower() == "skill"
                        ):
                            hits.append(
                                str((b.get("input") or {}).get("skill", "")).split(":")[
                                    -1
                                ]
                            )
                elif msg.get("role") == "user":
                    text = content if isinstance(content, str) else json.dumps(content)
                    hits += [c.split(":")[-1] for c in CMD.findall(text)]
                for h in hits:
                    if h:
                        uses[h] += 1
                        last[h] = max(last.get(h, when), when)
    on_disk = sorted(
        n
        for n in os.listdir(root)
        if os.path.isdir(os.path.join(root, n)) and not n.startswith("_")
    )
    print(f"{'skill':32} {'uses':>5}  last used")
    for n in sorted(on_disk, key=lambda k: (-uses[k], k)):
        print(f"{n:32} {uses[n]:5}  {last[n].date() if n in last else '-'}")
    never = [n for n in on_disk if uses[n] == 0]
    print(
        f"\nusage: {len(on_disk) - len(never)}/{len(on_disk)} skills invoked in {a.days} days; never invoked ({len(never)}): {', '.join(never) or 'none'}"
    )
    return 3 if never else 0


if __name__ == "__main__":
    sys.exit(main())
