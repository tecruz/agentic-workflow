#!/usr/bin/env bash
set -euo pipefail

# ── Health Report ──────────────────────────────────────────────────────────────
# Scans .agentic/ and prints a plain-text summary of task state, context module
# usage, skill invocation usage, profile distribution, VERSION/protocol_version
# consistency, and recent task changes.  Exit 0 always (informational only).
# Requires: bash 3.2+ (macOS default), standard coreutils, grep, sed, find.
# Deliberately array-free: bash 3.2 treats zero-element arrays as unset under
# `set -u`, so `"${arr[@]}"` on an empty array aborts the script.  Aggregation
# is done with newline-joined strings + sort/uniq/while-read pipelines.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTIC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$AGENTIC_DIR/tasks"

# ── Helpers ────────────────────────────────────────────────────────────────────

trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; echo "$v"; }

# ── 1. Collect task state ──────────────────────────────────────────────────────

total=0
statuses=""      # one Status value per task, trailing-newline separated
profiles=""      # one Profile value per task, trailing-newline separated
modules=""       # "<module-id><TAB><basename>" per selection
skills=""        # "<skill-id><TAB><basename>" per invocation
module_total=0
skill_total=0

for f in "$TASKS_DIR"/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  total=$(( total + 1 ))

  s="$(sed -n 's/^Status:[[:space:]]*\(.*\)$/\1/p' "$f" 2>/dev/null || true)"
  s="$(trim "$s")"
  [ -z "$s" ] && s="unknown"
  statuses="${statuses}${s}"$'\n'

  p="$(sed -n 's/^Profile:[[:space:]]*\(.*\)$/\1/p' "$f" 2>/dev/null || true)"
  p="$(trim "$p")"
  [ -z "$p" ] && p="unknown"
  profiles="${profiles}${p}"$'\n'

  in_section=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ Context\ modules ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      in_section=false
      continue
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+)\ v[0-9]+\ loaded\  ]]; then
      mod_id="$(echo "$line" | sed -E 's/^- ([^ ]+) v[0-9]+ loaded.*/\1/' || true)"
      [ -n "$mod_id" ] || continue
      modules="${modules}${mod_id}"$'\t'"${base}"$'\n'
      module_total=$(( module_total + 1 ))
    fi
  done < "$f"

  in_section=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ Skills ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      in_section=false
      continue
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+)\ v[0-9]+\ invoked\  ]]; then
      sk_id="$(echo "$line" | sed -E 's/^- ([^ ]+) v[0-9]+ invoked.*/\1/' || true)"
      [ -n "$sk_id" ] || continue
      skills="${skills}${sk_id}"$'\t'"${base}"$'\n'
      skill_total=$(( skill_total + 1 ))
    fi
  done < "$f"
done

# ── 2. VERSION and protocol_version consistency ────────────────────────────────

version_file="$AGENTIC_DIR/VERSION"
if [ -f "$version_file" ]; then
  file_version="$(trim "$(cat "$version_file")")"
else
  file_version="(missing)"
fi

# Collect protocol_version from every emitter that embeds it (Bash + PowerShell
# twins, coordinator, and the eval runner). Portable BRE sed — no GNU grep -P,
# which BSD grep on macOS does not support.  No pipes to head: under pipefail a
# short-read SIGPIPE would abort the script on BSD/macOS pipelines.
extract_proto_version() {  # extract_proto_version <file> → version or empty
    local f="$1" v
    v="$(sed -n 's/.*"protocol_version"[[:space:]]*:[[:space:]]*"\([0-9][^"]*\)".*/\1/p' "$f" 2>/dev/null || true)"
    v="${v%%$'\n'*}"
    if [ -z "$v" ]; then
        v="$(sed -n 's/.*protocol_version[[:space:]]*=[[:space:]]*"\([0-9][^"]*\)".*/\1/p' "$f" 2>/dev/null || true)"
        v="${v%%$'\n'*}"
    fi
    if [ -z "$v" ]; then
        v="$(sed -n 's/.*PROTOCOL_VERSION="\([0-9][^"]*\)".*/\1/p' "$f" 2>/dev/null || true)"
        v="${v%%$'\n'*}"
    fi
    if [ -z "$v" ]; then
        v="$(sed -n 's/.*ProtocolVersion[[:space:]]*=[[:space:]]*"\([0-9][^"]*\)".*/\1/p' "$f" 2>/dev/null || true)"
        v="${v%%$'\n'*}"
    fi
    printf '%s' "$v"
}

proto_files=(
  "$AGENTIC_DIR/scripts/verify.sh"
  "$AGENTIC_DIR/scripts/verify.ps1"
  "$AGENTIC_DIR/scripts/validate-task.sh"
  "$AGENTIC_DIR/scripts/validate-task.ps1"
  "$AGENTIC_DIR/scripts/validate-context.sh"
  "$AGENTIC_DIR/scripts/validate-context.ps1"
  "$AGENTIC_DIR/scripts/validate-skills.sh"
  "$AGENTIC_DIR/scripts/validate-skills.ps1"
  "$AGENTIC_DIR/orchestration/coordinator.sh"
  "$AGENTIC_DIR/orchestration/coordinator.ps1"
)

proto_entries=""
for pf in "${proto_files[@]}"; do
  pv="$(extract_proto_version "$pf")"
  [ -n "$pv" ] && proto_entries="${proto_entries}${pf}"$'\t'"${pv}"$'\n'
done

# Also check evals/run-evals.sh (dev-repo only; absent in adopter installs).
evals_sh="$AGENTIC_DIR/../evals/run-evals.sh"
if [ -f "$evals_sh" ]; then
  pv="$(extract_proto_version "$evals_sh")"
  [ -n "$pv" ] && proto_entries="${proto_entries}${evals_sh}"$'\t'"${pv}"$'\n'
fi

# ── 3. Recent changes (last 5 modified task files) ─────────────────────────────

recent_list=""
if command -v git &>/dev/null && git -C "$AGENTIC_DIR/.." rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  recent_list="$(git -C "$AGENTIC_DIR/.." log -5 --format='%ai|%s' -- "$TASKS_DIR"/*.md 2>/dev/null || true)"
fi

# ── Output ────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════════════════"
echo "  Agentic Workflow Health Report"
echo "  $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

echo "── Tasks ─────────────────────────────────────────────────────────────"
echo "  Total: $total"
printf '%s' "$statuses" | sort | uniq -c | while read -r cnt s; do
  echo "    $s: $cnt"
done
echo ""

echo "── Context Module Usage ──────────────────────────────────────────────"
echo "  Total selections: $module_total"
if [ -n "$modules" ]; then
  prev=""
  printf '%s' "$modules" | sort | while IFS=$'\t' read -r mid tsk; do
    if [ "$mid" != "$prev" ]; then
      echo "    $mid:"
      prev="$mid"
    fi
    echo "      - $tsk"
  done
else
  echo "    (none)"
fi
echo ""

echo "── Skill Invocation Usage ────────────────────────────────────────────"
echo "  Total invocations: $skill_total"
if [ -n "$skills" ]; then
  prev=""
  printf '%s' "$skills" | sort | while IFS=$'\t' read -r sk_id tsk; do
    if [ "$sk_id" != "$prev" ]; then
      echo "    $sk_id:"
      prev="$sk_id"
    fi
    echo "      - $tsk"
  done
else
  echo "    (none)"
fi
echo ""

echo "── Profile Distribution ─────────────────────────────────────────────"
printf '%s' "$profiles" | sort | uniq -c | while read -r cnt p; do
  echo "    $p: $cnt"
done
echo ""

echo "── VERSION Consistency ───────────────────────────────────────────────"
echo "  .agentic/VERSION: $file_version"

all_match=true
if [ -n "$proto_entries" ]; then
  proto_report="$(printf '%s' "$proto_entries" | while IFS=$'\t' read -r pf pv; do
    short="$(basename "$pf")"
    if [ "$pv" = "$file_version" ]; then
      echo "    $short: $pv  ✓"
    else
      echo "    $short: $pv  ✗ (expected $file_version)"
    fi
  done)"
  printf '%s\n' "$proto_report"
  if printf '%s' "$proto_report" | grep -q '✗'; then
    all_match=false
  fi
else
  echo "    (no protocol_version found in scripts)"
fi

if $all_match; then
  echo "  Status: CONSISTENT"
else
  echo "  Status: MISMATCH — protocol_version does not match VERSION"
fi
echo ""

echo "── Recent Task Changes (last 5 git-modified) ────────────────────────"
if [ -n "$recent_list" ]; then
  echo "$recent_list" | while IFS='|' read -r date msg; do
    echo "    $date  $msg"
  done
else
  echo "    (no git history or not in a repo)"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════════"
echo "  Report complete. All checks informational — exit 0."
echo "═══════════════════════════════════════════════════════════════════════"

exit 0
