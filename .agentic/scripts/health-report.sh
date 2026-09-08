#!/usr/bin/env bash
set -euo pipefail

# ── Health Report ──────────────────────────────────────────────────────────────
# Scans .agentic/ and prints a plain-text summary of task state, context module
# usage, skill invocation usage, profile distribution, VERSION/protocol_version
# consistency, and recent task changes.  Exit 0 always (informational only).
# Requires: bash 3.2+ (macOS default), standard coreutils, grep, sed, find.
# Uses only indexed arrays (no declare -A, no read -a, no namerefs) so it runs
# on the bash 3.2 that macOS ships.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTIC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$AGENTIC_DIR/tasks"

# ── Helpers ────────────────────────────────────────────────────────────────────

trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; echo "$v"; }

# Parallel key/value pair helpers over the globals _map_keys/_map_vals
# (indexed arrays — every map in this script is small).  Values may contain
# spaces; keys and values are never flattened into a delimited string, so no
# word-splitting hazards under bash 3.2 + set -u.
_map_keys=()
_map_vals=()

# kv_find <key> → index or -1
kv_find() {
    local k="$1" i
    for ((i = 0; i < ${#_map_keys[@]}; i++)); do
        if [ "${_map_keys[$i]}" = "$k" ]; then
            echo "$i"
            return 0
        fi
    done
    echo -1
}

# kv_set <key> <value> — replaces an existing key, otherwise appends
kv_set() {
    local k="$1" v="$2" i
    i="$(kv_find "$k")"
    if [ "$i" -ge 0 ]; then
        _map_vals[$i]="$v"
    else
        _map_keys+=("$k")
        _map_vals+=("$v")
    fi
}

# kv_get <key> → value (empty if absent)
kv_get() {
    local k="$1" i
    i="$(kv_find "$k")"
    if [ "$i" -ge 0 ]; then
        echo "${_map_vals[$i]}"
    fi
}

# kv_bump <key> — integer counter semantics (0 if absent)
kv_bump() {
    local k="$1" i
    i="$(kv_find "$k")"
    if [ "$i" -ge 0 ]; then
        _map_vals[$i]=$(( _map_vals[$i] + 1 ))
    else
        _map_keys+=("$k")
        _map_vals+=(1)
    fi
}

# kv_count → number of stored pairs
kv_count() { echo "${#_map_keys[@]}"; }

# kv_sorted_keys → one key per line, sorted (only for space-free key domains)
kv_sorted_keys() {
    printf '%s\n' "${_map_keys[@]}" | sort
}

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

status_keys=()
status_vals=()
for tf in "${task_files[@]}"; do
  s="$(sed -n 's/^Status:[[:space:]]*\(.*\)$/\1/p' "$tf" 2>/dev/null || true)"
  s="$(trim "$s")"
  [ -z "$s" ] && s="unknown"
  _map_keys=("${status_keys[@]}")
  _map_vals=("${status_vals[@]}")
  kv_bump "$s"
  status_keys=("${_map_keys[@]}")
  status_vals=("${_map_vals[@]}")
done

# ── 2. Context module usage ───────────────────────────────────────────────────

module_keys=()
module_vals=()
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
      _map_keys=("${module_keys[@]}")
      _map_vals=("${module_vals[@]}")
      old="$(kv_get "$mod_id")"
      if [ -n "$old" ]; then
        kv_set "$mod_id" "${old},${base}"
      else
        kv_set "$mod_id" "$base"
      fi
      module_keys=("${_map_keys[@]}")
      module_vals=("${_map_vals[@]}")
      module_total=$(( module_total + 1 ))
    fi
  done < "$tf"
done

# ── 3. Skill invocation usage ─────────────────────────────────────────────────

skill_keys=()
skill_vals=()
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
      sk_id="$(echo "$line" | sed -E 's/^- ([^ ]+) v[0-9]+ invoked.*/\1/' || true)"
      _map_keys=("${skill_keys[@]}")
      _map_vals=("${skill_vals[@]}")
      old="$(kv_get "$sk_id")"
      if [ -n "$old" ]; then
        kv_set "$sk_id" "${old},${base}"
      else
        kv_set "$sk_id" "$base"
      fi
      skill_keys=("${_map_keys[@]}")
      skill_vals=("${_map_vals[@]}")
      skill_total=$(( skill_total + 1 ))
    fi
  done < "$tf"
done

# ── 4. Profile distribution ──────────────────────────────────────────────────

profile_keys=()
profile_vals=()
for tf in "${task_files[@]}"; do
  p="$(sed -n 's/^Profile:[[:space:]]*\(.*\)$/\1/p' "$tf" 2>/dev/null || true)"
  p="$(trim "$p")"
  [ -z "$p" ] && p="unknown"
  _map_keys=("${profile_keys[@]}")
  _map_vals=("${profile_vals[@]}")
  kv_bump "$p"
  profile_keys=("${_map_keys[@]}")
  profile_vals=("${_map_vals[@]}")
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

proto_keys=()
proto_vals=()
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
  if [ -n "$pv" ]; then
    proto_keys+=("$pf")
    proto_vals+=("$pv")
  fi
done

# Also check evals/run-evals.sh (dev-repo only; absent in adopter installs).
evals_sh="$AGENTIC_DIR/../evals/run-evals.sh"
if [ -f "$evals_sh" ]; then
  pv="$(extract_proto_version "$evals_sh")"
  if [ -n "$pv" ]; then
    proto_keys+=("$evals_sh")
    proto_vals+=("$pv")
  fi
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
_map_keys=("${status_keys[@]}")
_map_vals=("${status_vals[@]}")
for s in $(kv_sorted_keys); do
  echo "    $s: $(kv_get "$s")"
done
echo ""

echo "── Context Module Usage ──────────────────────────────────────────────"
echo "  Total selections: $module_total"
_map_keys=("${module_keys[@]}")
_map_vals=("${module_vals[@]}")
if [ "$(kv_count)" -gt 0 ]; then
  for mod in $(kv_sorted_keys); do
    echo "    $mod:"
    mv="$(kv_get "$mod")"
    if [ -n "$mv" ]; then
      echo "$mv" | tr ',' '\n' | while IFS= read -r t; do
        [ -n "$t" ] && echo "      - $(trim "$t")"
      done
    fi
  done
else
  echo "    (none)"
fi
echo ""

echo "── Skill Invocation Usage ────────────────────────────────────────────"
echo "  Total invocations: $skill_total"
_map_keys=("${skill_keys[@]}")
_map_vals=("${skill_vals[@]}")
if [ "$(kv_count)" -gt 0 ]; then
  for sk in $(kv_sorted_keys); do
    echo "    $sk:"
    sv="$(kv_get "$sk")"
    if [ -n "$sv" ]; then
      echo "$sv" | tr ',' '\n' | while IFS= read -r t; do
        [ -n "$t" ] && echo "      - $(trim "$t")"
      done
    fi
  done
else
  echo "    (none)"
fi
echo ""

echo "── Profile Distribution ─────────────────────────────────────────────"
_map_keys=("${profile_keys[@]}")
_map_vals=("${profile_vals[@]}")
for p in $(kv_sorted_keys); do
  echo "    $p: $(kv_get "$p")"
done
echo ""

echo "── VERSION Consistency ───────────────────────────────────────────────"
echo "  .agentic/VERSION: $file_version"

all_match=true
if [ "${#proto_keys[@]}" -gt 0 ]; then
  for ((i = 0; i < ${#proto_keys[@]}; i++)); do
    pv="${proto_vals[$i]}"
    short="$(basename "${proto_keys[$i]}")"
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
