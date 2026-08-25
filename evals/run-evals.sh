#!/usr/bin/env bash
#
# run-evals.sh — offline deterministic runner for behavioral evaluations.
#
# Evaluates observable behavior recorded in saved fixture artifacts (final task
# files, context-module selections, risk profiles, approvals, verification
# results). It never inspects hidden reasoning, never calls an external model,
# and requires no network access or API keys.
#
# A scenario classifies PASS when every check passes. Scenarios may declare
# "fixture_expected_result": "FAIL" as a negative control: the embedded policy
# violation must be detected, so the harness fails unless the classification
# is FAIL.
#
# Exit codes:
#   0  every scenario classified as expected
#   1  any mismatch, structural error, or unreadable scenario
#
# Usage:
#   bash evals/run-evals.sh [--format text|json] [scenarios-dir]
#
# Requirements: bash, python3 (scenario parsing + JSON serialization), and the
# sibling `.agentic/scripts/validate-context.sh` validator.

set -uo pipefail

FORMAT="text"
SCENARIOS_DIR=""

usage() {
    cat <<'EOF'
Usage: run-evals.sh [--format text|json] [scenarios-dir]

Runs every offline behavioral evaluation scenario.

Options:
  --format    Output format: text (default) or json (NDJSON, one
              behavioral_evaluation_result document per scenario).
  -h, --help  Show this help.

Exit codes:
  0  all scenarios classified as expected
  1  at least one mismatch or structural error
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --format)
            if [ $# -lt 2 ]; then echo "ERROR: --format requires a value." >&2; exit 1; fi
            FORMAT="$2"; shift 2 ;;
        --format=*) FORMAT="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "$SCENARIOS_DIR" ]; then
                echo "Error: expected a single scenarios directory." >&2
                exit 1
            fi
            SCENARIOS_DIR="$1"; shift ;;
    esac
done

case "$(printf '%s' "$FORMAT" | tr '[:upper:]' '[:lower:]')" in
    text) FORMAT="text" ;;
    json) FORMAT="json" ;;
    *) echo "ERROR: --format must be 'text' or 'json'." >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$SCENARIOS_DIR" ]; then
    SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
fi

command -v python3 >/dev/null 2>&1 || { echo "ERROR: Python 3 is required for run-evals.sh" >&2; exit 1; }

CONTEXT_VALIDATOR="$SCRIPT_DIR/../.agentic/scripts/validate-context.sh"
if [ ! -f "$CONTEXT_VALIDATOR" ]; then
    CONTEXT_VALIDATOR="$SCRIPT_DIR/../../.agentic/scripts/validate-context.sh"
fi

export AGENTIC_EVAL_CONTEXT_VALIDATOR="$CONTEXT_VALIDATOR"
export AGENTIC_EVAL_FORMAT="$FORMAT"
export AGENTIC_EVAL_SCENARIOS_DIR="$SCENARIOS_DIR"

exec python3 - <<'PYEOF'
import json
import os
import re
import subprocess
import sys

scenarios_dir = os.environ["AGENTIC_EVAL_SCENARIOS_DIR"]
fmt = os.environ["AGENTIC_EVAL_FORMAT"]
validator = os.path.abspath(os.environ["AGENTIC_EVAL_CONTEXT_VALIDATOR"])

PROFILE_RANK = {"prototype": 0, "standard": 1, "high-assurance": 2}
CHECK_ORDER = [
    "SCENARIO_SCHEMA_OK",
    "TASK_ARTIFACT_PRESENT",
    "CONTEXT_CONTRACT_VALID",
    "PROFILE_FLOOR_RESPECTED",
    "REQUIRED_MODULES_SELECTED",
    "FORBIDDEN_MODULES_AVOIDED",
    "APPROVALS_DECLARED",
    "EVIDENCE_PRESENT",
    "VERIFICATION_PASSED",
    "FORBIDDEN_PATHS_AVOIDED",
    "FORBIDDEN_ACTIONS_ABSENT",
]


def fail_fast(message):
    print("ERROR: %s" % message, file=sys.stderr)
    sys.exit(1)


def load_scenario(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def scenario_structurally_valid(doc):
    """Minimal structural validation mirroring scenario-v1.schema.json."""
    if not isinstance(doc, dict):
        return False
    if doc.get("schema_version") != 1:
        return False
    if not isinstance(doc.get("id"), str) or not re.match(r"^[a-z0-9][a-z0-9-]*$", doc["id"]):
        return False
    inp = doc.get("input")
    if not isinstance(inp, dict) or not isinstance(inp.get("task"), str):
        return False
    if not isinstance(inp.get("changed_paths"), list):
        return False
    exp = doc.get("expected")
    if not isinstance(exp, dict):
        return False
    if exp.get("minimum_profile") not in PROFILE_RANK:
        return False
    if not isinstance(exp.get("required_modules"), list):
        return False
    forbidden = doc.get("forbidden", {})
    if not isinstance(forbidden, dict):
        return False
    return True


def read_task_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def parse_task_field(task_text, field):
    match = re.search(r"^%s:\s*(\S+)" % field, task_text, re.MULTILINE | re.IGNORECASE)
    return match.group(1) if match else None


def selected_module_ids(task_path):
    """Runs validate-context in JSON mode and returns (ok, profile, ids)."""
    env = dict(os.environ)
    proc = subprocess.run(
        ["bash", validator, "--format", "json", task_path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        env=env,
    )
    try:
        doc = json.loads(proc.stdout.decode("utf-8", errors="replace"))
    except ValueError:
        return False, None, []
    ok = proc.returncode == 0 and doc.get("result") == "VALID"
    profile = doc.get("profile")
    ids = [m.get("id") for m in doc.get("selected_modules", []) if isinstance(m, dict)]
    return ok, profile, ids


def approvals_declare(task_lines, token):
    pattern = re.compile(r"^\s*[-*]\s*\[x\]\s*AG-\d+:", re.IGNORECASE)
    wanted = re.sub(r"[-_]+", " ", token).lower()
    for line in task_lines:
        if pattern.match(line):
            candidate = re.sub(r"[-_]+", " ", line).lower()
            if wanted in candidate:
                return True
    return False


def evidence_contains(task_lines, token):
    for line in task_lines:
        stripped = line.strip()
        if stripped.startswith("|") and stripped.count("|") >= 4:
            if token.lower() in line.lower():
                return True
    return False


def path_forbidden(changed_paths, forbidden_paths):
    for changed in changed_paths:
        norm = changed.replace("\\", "/").lstrip("./")
        for fp in forbidden_paths:
            f = fp.replace("\\", "/").lstrip("./")
            if norm == f or norm.endswith("/" + f):
                return True
    return False


def artifact_files(artifacts_dir):
    found = []
    for root, _dirs, names in os.walk(artifacts_dir):
        for name in names:
            found.append(os.path.join(root, name))
    return sorted(found)


def evaluate_scenario(scenario_path):
    checks = {}
    details = {}

    def record(cid, passed, detail=""):
        checks[cid] = bool(passed)
        if detail:
            details[cid] = detail

    try:
        scenario = load_scenario(scenario_path)
        schema_ok = scenario_structurally_valid(scenario)
    except (ValueError, OSError) as exc:
        record("SCENARIO_SCHEMA_OK", False, "unreadable or malformed scenario.json: %s" % exc)
        return finalize(None, scenario_path)

    sid = scenario.get("id") if schema_ok else os.path.basename(os.path.dirname(scenario_path))
    if schema_ok:
        record("SCENARIO_SCHEMA_OK", True)

    artifacts_dir = os.path.join(os.path.dirname(scenario_path), "artifacts")
    task_path = os.path.join(artifacts_dir, "task.md")

    expected = scenario.get("expected", {})
    forbidden = scenario.get("forbidden", {}) if schema_ok else {}
    required_modules = expected.get("required_modules", []) if schema_ok else []
    required_gates = expected.get("required_approval_gates", []) if schema_ok else []
    required_evidence = expected.get("required_evidence", []) if schema_ok else []

    if schema_ok and os.path.isfile(task_path) and os.path.getsize(task_path) > 0:
        record("TASK_ARTIFACT_PRESENT", True)
        task_text = read_task_text(task_path)
        task_lines = task_text.splitlines()
        ctx_ok, profile, module_ids = selected_module_ids(task_path)
        record("CONTEXT_CONTRACT_VALID", ctx_ok, "" if ctx_ok else "validate-context rejected the artifact task file")
        min_profile = expected.get("minimum_profile")
        prof_rank = PROFILE_RANK.get(profile, -1)
        need_rank = PROFILE_RANK.get(min_profile, 99)
        record("PROFILE_FLOOR_RESPECTED", prof_rank >= need_rank,
               "task profile '%s' vs minimum '%s'" % (profile, min_profile))
        missing = [m for m in required_modules if m not in module_ids]
        record("REQUIRED_MODULES_SELECTED", not missing,
               "" if not missing else "missing: %s" % ", ".join(missing))
        forbidden_modules = forbidden.get("modules", [])
        used = [m for m in module_ids if m in forbidden_modules]
        record("FORBIDDEN_MODULES_AVOIDED", not used,
               "" if not used else "forbidden modules selected: %s" % ", ".join(used))
        gate_missing = [g for g in required_gates if not approvals_declare(task_lines, g)]
        record("APPROVALS_DECLARED", not gate_missing,
               "" if not gate_missing else "no approval record for: %s" % ", ".join(gate_missing))
        ev_missing = [e for e in required_evidence if not evidence_contains(task_lines, e)]
        record("EVIDENCE_PRESENT", not ev_missing,
               "" if not ev_missing else "evidence table lacks: %s" % ", ".join(ev_missing))

        verification_path = os.path.join(artifacts_dir, "verification-result.json")
        ver_ok = False
        if os.path.isfile(verification_path):
            try:
                with open(verification_path, "r", encoding="utf-8") as fh:
                    vdoc = json.load(fh)
                ver_ok = (
                    vdoc.get("kind") == "verification_result"
                    and vdoc.get("result") == "PASS"
                    and vdoc.get("exit_code") == 0
                )
            except (ValueError, OSError):
                ver_ok = False
        record("VERIFICATION_PASSED", ver_ok,
               "" if ver_ok else "artifact verification-result.json must be a PASS verification_result")

        changed = scenario["input"]["changed_paths"] if schema_ok else []
        bad_paths = path_forbidden(changed, forbidden.get("paths", []))
        record("FORBIDDEN_PATHS_AVOIDED", not bad_paths,
               "" if not bad_paths else "a changed path matches a forbidden path")

        tokens = [t.lower() for t in forbidden.get("actions", [])]
        hit = None
        if tokens:
            for af in artifact_files(artifacts_dir):
                try:
                    with open(af, "r", encoding="utf-8", errors="replace") as fh:
                        content = fh.read().lower()
                except OSError:
                    continue
                for tok in tokens:
                    if tok in content:
                        hit = "%s in %s" % (tok, os.path.basename(af))
                        break
                if hit:
                    break
        record("FORBIDDEN_ACTIONS_ABSENT", hit is None,
               "" if hit is None else "forbidden action observed: %s" % hit)
    else:
        if schema_ok:
            record("TASK_ARTIFACT_PRESENT", False, "artifacts/task.md is missing or empty")

    return finalize(sid, scenario_path, checks, details)


def finalize(sid, scenario_path, checks=None, details=None):
    checks = checks or {}
    details = details or {}
    ordered = []
    for cid in CHECK_ORDER:
        if cid in checks:
            ordered.append({"id": cid, "detail": details.get(cid, ""), "passed": checks[cid]})
    total = len(ordered)
    passed = sum(1 for c in ordered if c["passed"])
    verdict = "PASS" if total > 0 and passed == total else "FAIL"

    raw = None
    if os.path.isfile(scenario_path):
        try:
            raw = load_scenario(scenario_path)
        except (ValueError, OSError):
            raw = None
    expectation = raw.get("fixture_expected_result", "PASS") if isinstance(raw, dict) else "PASS"

    diagnostics = []
    matched = verdict == expectation
    if not matched:
        diagnostics.append({
            "code": "FIXTURE_EXPECTATION_MISMATCH",
            "message": "classification %s does not match fixture_expected_result %s" % (verdict, expectation),
        })

    doc = {
        "schema_version": 1,
        "protocol_version": "1.5.0",
        "kind": "behavioral_evaluation_result",
        "mode": "offline-fixture",
        "result": verdict,
        "exit_code": 0 if matched else 1,
        "scenario_id": sid,
        "fixture_expected_result": expectation,
        "summary": {"total": total, "passed": passed, "failed": total - passed},
        "checks": ordered,
        "diagnostics": diagnostics,
    }
    return doc, matched


if not os.path.isdir(scenarios_dir):
    fail_fast("scenarios directory not found: %s" % scenarios_dir)

scenario_files = []
for name in sorted(os.listdir(scenarios_dir)):
    spath = os.path.join(scenarios_dir, name, "scenario.json")
    if os.path.isfile(spath):
        scenario_files.append(spath)

if not scenario_files:
    fail_fast("no scenario.json found under %s" % scenarios_dir)

run_failures = 0
docs = []
for spath in scenario_files:
    doc, matched = evaluate_scenario(spath)
    docs.append(doc)
    if fmt == "json":
        print(json.dumps(doc, separators=(",", ":")))
    else:
        status = "harness-ok" if matched else "HARNESS-FAIL"
        failed_checks = [c["id"] for c in doc["checks"] if not c["passed"]]
        suffix = (" failed=%s" % ",".join(failed_checks)) if failed_checks else ""
        print("%-28s %-4s expectation=%-4s %s%s" % (
            doc["scenario_id"], doc["result"], doc["fixture_expected_result"], status, suffix))
    if not matched:
        run_failures += 1

total_docs = len(docs)
expected_pass = sum(1 for d in docs if d["fixture_expected_result"] == d["result"])

if fmt != "json":
    print("")
    print("evals: %d/%d scenarios classified as expected" % (expected_pass, total_docs))

sys.exit(0 if run_failures == 0 else 1)
PYEOF
