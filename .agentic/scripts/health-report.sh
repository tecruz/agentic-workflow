#!/usr/bin/env bash
set -euo pipefail

# ── Health Report ──────────────────────────────────────────────────────────────
# Scans .agentic/ and prints a plain-text summary of task state, context module
# usage, skill invocation usage, profile distribution, VERSION/protocol_version
# consistency, and recent task changes.  Exit 0 always (informational only).
# Requires: bash 3.2+, standard coreutils, grep, sed, find.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTIC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$AGENTIC_DIR/tasks"

# ── Helpers ────────────────────────────────────────────────────────────────────

trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; echo "$v"; }

# POSIX-safe map helpers: parallel _keys/_vals indexed arrays.
# Usage: map_set key val / map_get key / map_has key / map_keys
_map_keys="" _map_vals=""
map_init() { _map_keys="" _map_vals=""; }
map_has() {
  local k="$1" i=0
  for ek in $_map_keys; do
    [ "$ek" = "$k" ] && return 0
    i=$(( i + 1 ))
  done
  return 1
}
map_get() {
  local k="$1" i=0
  for ek in $_map_keys; do
    if [ "$ek" = "$k" ]; then
      local j=0
      for ev in $_map_vals; do
        [ "$j" -eq "$i" ] && { echo "$ev"; return 0; }
        j=$(( j + 1 ))
      done
    fi
    i=$(( i + 1 ))
  done
  echo ""
}
map_set() {
  local k="$1" v="$2" i=0 found=false
  for ek in $_map_keys; do
    if [ "$ek" = "$k" ]; then
      found=true
      break
    fi
    i=$(( i + 1 ))
  done
  if $found; then
    # Replace value at index i
    local j=0 new_vals=""
    for ev in $_map_vals; do
      if [ "$j" -eq "$i" ]; then
        new_vals="${new_vals:+$new_vals }$v"
      else
        new_vals="${new_vals:+$new_vals }$ev"
      fi
      j=$(( j + 1 ))
    done
    _map_vals="$new_vals"
  else
    _map_keys="${_map_keys:+$_map_keys }$k"
    _map_vals="${_map_vals:+$_map_vals }$v"
  fi
}
map_keys() { echo "$_map_keys"; }
map_count() {
  local n=0
  for _ in $_map_keys; do n=$(( n + 1 )); done
  echo "$n"
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

map_init
for tf in "${task_files[@]}"; do
  s="$(sed -n 's/^Status:[[:space:]]*\(.*\)$/\1/p' "$tf" 2>/dev/null || true)"
  s="$(trim "$s")"
  [ -z "$s" ] && s="unknown"
  if map_has "$s"; then
    old="$(map_get "$s")"
    map_set "$s" "$(( old + 1 ))"
  else
    map_set "$s" "1"
  fi
done
_status_keys="$_map_keys" _status_vals="$_map_vals"

# ── 2. Context module usage ───────────────────────────────────────────────────

map_init
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
      if map_has "$mod_id"; then
        old="$(map_get "$mod_id")"
        map_set "$mod_id" "${old}, ${base}"
      else
        map_set "$mod_id" "$base"
      fi
      module_total=$(( module_total + 1 ))
    fi
  done < "$tf"
done
_module_keys="$_map_keys" _module_vals="$_map_vals"

# ── 3. Skill invocation usage ─────────────────────────────────────────────────

map_init
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
      if map_has "$sk_id"; then
        old="$(map_get "$sk_id")"
        map_set "$sk_id" "${old}, ${base}"
      else
        map_set "$sk_id" "$base"
      fi
      skill_total=$(( skill_total + 1 ))
    fi
  done < "$tf"
done
_skill_keys="$_map_keys" _skill_vals="$_map_vals"

# ── 4. Profile distribution ──────────────────────────────────────────────────

map_init
for tf in "${task_files[@]}"; do
  p="$(sed -n 's/^Profile:[[:space:]]*\(.*\)$/\1/p' "$tf" 2>/dev/null || true)"
  p="$(trim "$p")"
  [ -z "$p" ] && p="unknown"
  if map_has "$p"; then
    old="$(map_get "$p")"
    map_set "$p" "$(( old + 1 ))"
  else
    map_set "$p" "1"
  fi
done
_profile_keys="$_map_keys" _profile_vals="$_map_vals"

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

map_init
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
  [ -n "$pv" ] && map_set "$pf" "$pv"
done

# Also check evals/run-evals.sh (dev-repo only; absent in adopter installs).
evals_sh="$AGENTIC_DIR/../evals/run-evals.sh"
if [ -f "$evals_sh" ]; then
  pv="$(extract_proto_version "$evals_sh")"
  [ -n "$pv" ] && map_set "$evals_sh" "$pv"
fi
_proto_keys="$_map_keys" _proto_vals="$_map_vals"

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
_map_keys="$_status_keys" _map_vals="$_status_vals"
for s in $(echo "$_map_keys" | tr ' ' '\n' | sort); do
  echo "    $s: $(map_get "$s")"
done
echo ""

echo "── Context Module Usage ──────────────────────────────────────────────"
echo "  Total selections: $module_total"
_map_keys="$_module_keys" _map_vals="$_module_vals"
if [ "$(map_count)" -gt 0 ]; then
  for mod in $(echo "$_map_keys" | tr ' ' '\n' | sort); do
    echo "    $mod:"
    IFS=',' read -ra task_list <<< "$(map_get "$mod")"
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
_map_keys="$_skill_keys" _map_vals="$_skill_vals"
if [ "$(map_count)" -gt 0 ]; then
  for sk in $(echo "$_map_keys" | tr ' ' '\n' | sort); do
    echo "    $sk:"
    IFS=',' read -ra task_list <<< "$(map_get "$sk")"
    for t in "${task_list[@]}"; do
      echo "      - $(trim "$t")"
    done
  done
else
  echo "    (none)"
fi
echo ""

echo "── Profile Distribution ─────────────────────────────────────────────"
_map_keys="$_profile_keys" _map_vals="$_profile_vals"
for p in $(echo "$_map_keys" | tr ' ' '\n' | sort); do
  echo "    $p: $(map_get "$p")"
done
echo ""

echo "── VERSION Consistency ───────────────────────────────────────────────"
echo "  .agentic/VERSION: $file_version"

all_match=true
_map_keys="$_proto_keys" _map_vals="$_proto_vals"
if [ "$(map_count)" -gt 0 ]; then
  for pf in $(echo "$_map_keys" | tr ' ' '\n' | sort); do
    pv="$(map_get "$pf")"
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
