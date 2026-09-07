#!/usr/bin/env bash
set -euo pipefail

# Debug: log the first failing command on macOS
_debug_exit() { echo "health-report.sh: ERR at line $1 exit=$2" >&2; }
trap '_debug_exit $LINENO $?' ERR

# ── Health Report ──────────────────────────────────────────────────────────────
# Scans .agentic/ and prints a plain-text summary of task state, context module
# usage, skill invocation usage, profile distribution, VERSION/protocol_version
# consistency, and recent task changes.  Exit 0 always (informational only).
# Requires: bash 4+, standard coreutils, grep, sed, find.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTIC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$AGENTIC_DIR/tasks"

# ── Helpers ────────────────────────────────────────────────────────────────────

trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; echo "$v"; }

# Count non-README .md files in tasks/
task_files=()
for f in "$TASKS_DIR"/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  task_files+=("$f")
done

total=${#task_files[@]}

# ── 1. Task status breakdown ──────────────────────────────────────────────────

declare -A status_count
for tf in "${task_files[@]}"; do
  s="$(sed -n 's/^Status:[[:space:]]*\(.*\)$/\1/p' "$tf" 2>/dev/null || true)"
  s="$(trim "$s")"
  [ -z "$s" ] && s="unknown"
  status_count["$s"]=$(( ${status_count["$s"]:-0} + 1 ))
done

# ── 2. Context module usage ───────────────────────────────────────────────────

declare -A module_tasks          # module-id → comma-separated task basenames
module_total=0

for tf in "${task_files[@]}"; do
  base="$(basename "$tf")"
  in_section=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ Context\ modules ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+)\ v[0-9]+\ loaded\  ]]; then
      mod_id="$(echo "$line" | sed -E 's/^- ([^ ]+) v[0-9]+ loaded.*/\1/' || true)"
      module_tasks["$mod_id"]="${module_tasks["$mod_id"]:+${module_tasks["$mod_id"]}, }${base}"
      module_total=$(( module_total + 1 ))
    fi
  done < "$tf"
done

# ── 3. Skill invocation usage ─────────────────────────────────────────────────

declare -A skill_tasks           # skill-id → comma-separated task basenames
skill_total=0

for tf in "${task_files[@]}"; do
  base="$(basename "$tf")"
  in_section=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ Skills ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+)\ v[0-9]+\ invoked\  ]]; then
      sk_id="$(echo "$line" | sed -E 's/^- ([^ ]+) v[0-9]+ invoked.*/\1/')"
      skill_tasks["$sk_id"]="${skill_tasks["$sk_id"]:+${skill_tasks["$sk_id"]}, }${base}"
      skill_total=$(( skill_total + 1 ))
    fi
  done < "$tf"
done

# ── 4. Profile distribution ──────────────────────────────────────────────────

declare -A profile_count
for tf in "${task_files[@]}"; do
  p="$(sed -n 's/^Profile:[[:space:]]*\(.*\)$/\1/p' "$tf" 2>/dev/null || true)"
  p="$(trim "$p")"
  [ -z "$p" ] && p="unknown"
  profile_count["$p"]=$(( ${profile_count["$p"]:-0} + 1 ))
done

# ── 5. VERSION and protocol_version consistency ───────────────────────────────

version_file="$AGENTIC_DIR/VERSION"
if [ -f "$version_file" ]; then
  file_version="$(trim "$(cat "$version_file")")"
else
  file_version="(missing)"
fi

# Collect protocol_version from every emitter that embeds it (Bash + PowerShell
# twins, coordinator, and the eval runner). Portable BRE sed — no GNU grep -P,
# which BSD grep on macOS does not support.
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

declare -A proto_versions       # file → version string
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

for pf in "${proto_files[@]}"; do
  pv="$(extract_proto_version "$pf")"
  [ -n "$pv" ] && proto_versions["$pf"]="$pv"
done

# Also check evals/run-evals.sh (dev-repo only; absent in adopter installs).
evals_sh="$AGENTIC_DIR/../evals/run-evals.sh"
if [ -f "$evals_sh" ]; then
  pv="$(extract_proto_version "$evals_sh")"
  [ -n "$pv" ] && proto_versions["$evals_sh"]="$pv"
fi

# ── 6. Recent changes (last 5 modified task files) ────────────────────────────

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
for s in $(printf '%s\n' "${!status_count[@]}" | sort); do
  echo "    $s: ${status_count[$s]}"
done
echo ""

echo "── Context Module Usage ──────────────────────────────────────────────"
echo "  Total selections: $module_total"
if [ ${#module_tasks[@]} -gt 0 ]; then
  for mod in $(printf '%s\n' "${!module_tasks[@]}" | sort); do
    echo "    $mod:"
    IFS=',' read -ra task_list <<< "${module_tasks[$mod]}"
    for t in "${task_list[@]}"; do
      echo "      - $(trim "$t")"
    done
  done
else
  echo "    (none)"
fi
echo ""

echo "── Skill Invocation Usage ────────────────────────────────────────────"
echo "  Total invocations: $skill_total"
if [ ${#skill_tasks[@]} -gt 0 ]; then
  for sk in $(printf '%s\n' "${!skill_tasks[@]}" | sort); do
    echo "    $sk:"
    IFS=',' read -ra task_list <<< "${skill_tasks[$sk]}"
    for t in "${task_list[@]}"; do
      echo "      - $(trim "$t")"
    done
  done
else
  echo "    (none)"
fi
echo ""

echo "── Profile Distribution ─────────────────────────────────────────────"
for p in $(printf '%s\n' "${!profile_count[@]}" | sort); do
  echo "    $p: ${profile_count[$p]}"
done
echo ""

echo "── VERSION Consistency ───────────────────────────────────────────────"
echo "  .agentic/VERSION: $file_version"

all_match=true
if [ ${#proto_versions[@]} -gt 0 ]; then
  for pf in $(printf '%s\n' "${!proto_versions[@]}" | sort); do
    pv="${proto_versions[$pf]}"
    short="$(basename "$pf")"
    if [ "$pv" = "$file_version" ]; then
      echo "    $short: $pv  ✓"
    else
      echo "    $short: $pv  ✗ (expected $file_version)"
      all_match=false
    fi
  done
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
