#!/usr/bin/env bash
# Shared resolution for the skill-health scripts. Source it.
#   sh_skills_dir [DIR]  -> prints the skills folder
#   sh_cases_file [FILE] -> prints the cases file (may not exist)
#   sh_skill_md DIR      -> prints the skill's markdown path (SKILL.md or skill.md)
sh_skills_dir() {
  if [ -n "${1:-}" ]; then printf '%s' "$1"
  elif [ -n "${SKILL_HEALTH_SKILLS:-}" ]; then printf '%s' "$SKILL_HEALTH_SKILLS"
  elif [ -d ".claude/skills" ]; then printf '%s' "$PWD/.claude/skills"
  else printf '%s' "$HOME/.claude/skills"; fi
}
sh_cases_file() {
  if [ -n "${1:-}" ]; then printf '%s' "$1"
  elif [ -n "${SKILL_HEALTH_CASES:-}" ]; then printf '%s' "$SKILL_HEALTH_CASES"
  elif [ -f ".claude/skill-health-cases.tsv" ]; then printf '%s' "$PWD/.claude/skill-health-cases.tsv"
  else printf '%s' "$HOME/.claude/skill-health-cases.tsv"; fi
}
sh_skill_md() {
  if [ -f "$1/SKILL.md" ]; then printf '%s' "$1/SKILL.md"
  elif [ -f "$1/skill.md" ]; then printf '%s' "$1/skill.md"
  else return 1; fi
}
# parse "--skills DIR --cases FILE" style args into SKILLS / CASES, leaving the rest in REST
sh_parse_args() {
  SKILLS=""; CASES=""; REST=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --skills) SKILLS="$2"; shift 2 ;;
      --cases)  CASES="$2"; shift 2 ;;
      *) REST+=("$1"); shift ;;
    esac
  done
  SKILLS=$(sh_skills_dir "$SKILLS"); CASES=$(sh_cases_file "$CASES")
}
