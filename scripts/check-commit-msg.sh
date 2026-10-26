#!/bin/sh
# Checks commit subjects against Conventional Commits 1.0.0-beta.2 and the
# style rules in docs/agent/workflow.md.
#   check-commit-msg.sh <message-file>     used by the commit-msg hook
#   check-commit-msg.sh --range <from> <to> used by `make commits`
set -eu

types='feat|fix|docs|refactor|test|chore|build|ci|style|perf|revert'
pattern="^($types)(\([a-z0-9]+(-[a-z0-9]+)*\))?: [^A-Z .](.*[^. ])?$"
max_length=100

check_subject() {
  subject="$1"
  case "$subject" in
    "Merge "* | "fixup! "* | "squash! "*) return 0 ;;
  esac
  if ! printf '%s' "$subject" | grep -Eq "$pattern"; then
    echo "invalid commit subject: '$subject'" >&2
    echo "expected '<type>[(scope)]: <description>', lowercase start, no trailing period; types: $types" >&2
    return 1
  fi
  if [ "${#subject}" -gt "$max_length" ]; then
    echo "commit subject longer than $max_length characters: '$subject'" >&2
    return 1
  fi
}

if [ "${1:-}" = "--range" ]; then
  status=0
  for sha in $(git rev-list --no-merges "$2..$3"); do
    check_subject "$(git log -1 --format=%s "$sha")" || status=1
  done
  exit "$status"
fi

check_subject "$(grep -v '^#' "$1" | head -n 1)"
