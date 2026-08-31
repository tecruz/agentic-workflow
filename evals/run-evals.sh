#!/usr/bin/env bash
#
# run-evals.sh — offline deterministic runner for behavioral evaluations.
#
# Evaluates observable behavior recorded in saved fixture artifacts by running
# the REAL production contracts against them:
#
#   - scenario.json          validated against evals/schemas/scenario-v1.schema.json
#   - artifacts/task.md      validated by validate-task --handoff and
#                            validate-context --handoff (the actual gates)
#   - verification-result.json
#                            validated against the managed
#                            verification-result-v1.schema.json, including
#                            summary/checks-array agreement
#   - approvals and evidence parsed ONLY from authoritative sections
#                            (fenced code, HTML comments, and blockquotes are
#                            ignored, mirroring the production validators)
#
# It never inspects hidden reasoning, never calls an external model, and
# requires no network access or API keys.
#
# A scenario's artifacts classify observed_result=PASS when every check passes.
# Scenarios may declare "fixture_expected_result": "FAIL" as a negative
# control: the embedded policy violation must be detected, so observed_result
# must come out FAIL for the harness itself to pass.
#
# Every emitted behavioral_evaluation_result document carries the three-way
# split required by evaluation-result-v1.schema.json:
#   observed_result       classification of the fixture artifacts
#   expected_result       what the scenario demands
#   expectation_matched   whether the harness classified correctly
#   result / exit_code    HARNESS verdict (PASS/0 when the expectation matched)
# Each document is validated against that managed schema before it may be
# emitted; a document that violates its own schema aborts the run.
#
# Exit codes:
#   0  every scenario classified as expected and every document schema-valid
#   1  any mismatch, structural error, unreadable scenario, or invalid document
#
# Usage:
#   bash evals/run-evals.sh [--format text|json] [scenarios-dir]
#
# Requirements: bash, python3 (schema validation, contract invocation, and
# JSON serialization), and the sibling .agentic/scripts validators.

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
  1  at least one mismatch, structural error, or invalid document
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --format)
            if [ $# -lt 2 ]; then echo "ERROR: --format requires a value." >&2; exit 1; fi
            FORMAT="$2"; shift 2 ;;
        --format=*) FORMAT="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
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

TASK_VALIDATOR="$SCRIPT_DIR/../.agentic/scripts/validate-task.sh"
CONTEXT_VALIDATOR="$SCRIPT_DIR/../.agentic/scripts/validate-context.sh"
if [ ! -f "$TASK_VALIDATOR" ] || [ ! -f "$CONTEXT_VALIDATOR" ]; then
    TASK_VALIDATOR="$SCRIPT_DIR/../../.agentic/scripts/validate-task.sh"
    CONTEXT_VALIDATOR="$SCRIPT_DIR/../../.agentic/scripts/validate-context.sh"
fi

# Under git-bash (Windows full-CI leg), $PWD-derived paths are MSYS-style
# (/d/...), which a native python3 cannot resolve. Convert every exported
# path to mixed form (C:/...) when cygpath exists; identity elsewhere.
_to_native() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
    else
        printf '%s' "$1"
    fi
}

export AGENTIC_EVAL_TASK_VALIDATOR="$(_to_native "$TASK_VALIDATOR")"
export AGENTIC_EVAL_CONTEXT_VALIDATOR="$(_to_native "$CONTEXT_VALIDATOR")"
export AGENTIC_EVAL_SCENARIO_SCHEMA="$(_to_native "$SCRIPT_DIR/schemas/scenario-v1.schema.json")"
export AGENTIC_EVAL_RESULT_SCHEMA="$(_to_native "$SCRIPT_DIR/schemas/evaluation-result-v1.schema.json")"
export AGENTIC_EVAL_VERIFICATION_SCHEMA="$(_to_native "$SCRIPT_DIR/../.agentic/schemas/verification-result-v1.schema.json")"
export AGENTIC_EVAL_FORMAT="$FORMAT"
export AGENTIC_EVAL_SCENARIOS_DIR="$(_to_native "$SCENARIOS_DIR")"

exec python3 - <<'PYEOF'
import json
import os
import re
import shutil
import subprocess
import sys

scenarios_dir = os.environ["AGENTIC_EVAL_SCENARIOS_DIR"]
fmt = os.environ["AGENTIC_EVAL_FORMAT"]
task_validator = os.path.abspath(os.environ["AGENTIC_EVAL_TASK_VALIDATOR"])
context_validator = os.path.abspath(os.environ["AGENTIC_EVAL_CONTEXT_VALIDATOR"])
scenario_schema_path = os.path.abspath(os.environ["AGENTIC_EVAL_SCENARIO_SCHEMA"])
result_schema_path = os.path.abspath(os.environ["AGENTIC_EVAL_RESULT_SCHEMA"])
verification_schema_path = os.path.abspath(os.environ["AGENTIC_EVAL_VERIFICATION_SCHEMA"])

# The runner may execute under git-bash (MSYS) or WSL bash on Windows hosts,
# and the `bash` resolved from THIS process's PATH is not guaranteed to be
# the same flavor as the one that started us. Detect the child flavor once
# and convert drive-letter paths into the form THAT bash understands; pin
# the resolved binary so probe and validators share one interpreter.
BASH_BIN = shutil.which("bash") or "bash"
_probe = subprocess.run(
    [BASH_BIN, "-c", "uname -s"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
)
_uname = _probe.stdout.decode("utf-8", errors="replace")
if os.name == "nt":
    CHILD_FLAVOR = "wsl" if "Linux" in _uname else "msys"
else:
    CHILD_FLAVOR = "posix"

_DRIVE_RE = re.compile(r"^([A-Za-z]):/(.*)$")


def bash_path(path):
    """Path form acceptable to the child bash (POSIX hosts: unchanged)."""
    p = path.replace(os.sep, "/") if os.sep != "/" else path
    m = _DRIVE_RE.match(p)
    if not m or CHILD_FLAVOR == "posix":
        return p
    drive, rest = m.group(1).lower(), m.group(2)
    if CHILD_FLAVOR == "wsl":
        return "/mnt/%s/%s" % (drive, rest)
    return "%s:/%s" % (drive, rest)

PROFILE_RANK = {"prototype": 0, "standard": 1, "high-assurance": 2}
CHECK_ORDER = [
    "SCENARIO_SCHEMA_VALID",
    "TASK_ARTIFACT_PRESENT",
    "TASK_CONTRACT_VALID",
    "CONTEXT_CONTRACT_VALID",
    "VERIFICATION_SCHEMA_VALID",
    "PROFILE_FLOOR_RESPECTED",
    "REQUIRED_MODULES_SELECTED",
    "FORBIDDEN_MODULES_AVOIDED",
    "APPROVALS_DECLARED",
    "EVIDENCE_PRESENT",
    "FORBIDDEN_PATHS_AVOIDED",
    "FORBIDDEN_ACTIONS_ABSENT",
]


def fail_fast(message):
    print("ERROR: %s" % message, file=sys.stderr)
    sys.exit(1)


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


# ---------------------------------------------------------------------------
# Minimal offline draft-07 subset interpreter. Supports exactly the keywords
# used by the managed schemas: type, const, enum, pattern, required,
# properties, additionalProperties:false, items, minimum, minItems, maxItems,
# allOf, if/then. Validating against the real schema files (not a hand-mirrored
# subset) keeps the runners honest when the schemas evolve.
# ---------------------------------------------------------------------------

_TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
    "null": type(None),
}


def _type_ok(value, name):
    if name == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if name == "boolean":
        return isinstance(value, bool)
    pytype = _TYPES.get(name)
    if pytype is None:
        return True
    if pytype is str and isinstance(value, bool):
        return False
    return isinstance(value, pytype)


def schema_errors(instance, schema, path="$"):
    """Returns a list of human-readable violation descriptions."""
    errors = []
    if not isinstance(schema, dict):
        return errors

    if "type" in schema:
        names = schema["type"]
        if isinstance(names, str):
            names = [names]
        if not any(_type_ok(instance, n) for n in names):
            errors.append("%s: expected type %s" % (path, "/".join(names)))
            return errors

    if "const" in schema and instance != schema["const"]:
        errors.append("%s: must equal %r" % (path, schema["const"]))

    if "enum" in schema and instance not in schema["enum"]:
        errors.append("%s: %r not in enum %r" % (path, instance, schema["enum"]))

    if "pattern" in schema and isinstance(instance, str):
        if not re.search(schema["pattern"], instance):
            errors.append("%s: %r does not match %r" % (path, instance, schema["pattern"]))

    if "minimum" in schema and isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if instance < schema["minimum"]:
            errors.append("%s: %r below minimum %r" % (path, instance, schema["minimum"]))

    if isinstance(instance, list):
        if "minItems" in schema and len(instance) < schema["minItems"]:
            errors.append("%s: fewer than %d items" % (path, schema["minItems"]))
        if "maxItems" in schema and len(instance) > schema["maxItems"]:
            errors.append("%s: more than %d items" % (path, schema["maxItems"]))
        if "items" in schema:
            for i, item in enumerate(instance):
                errors.extend(schema_errors(item, schema["items"], "%s[%d]" % (path, i)))

    if isinstance(instance, dict):
        for prop in schema.get("required", []):
            if prop not in instance:
                errors.append("%s: missing required property %r" % (path, prop))
        props = schema.get("properties", {})
        for key, value in instance.items():
            if key in props:
                errors.extend(schema_errors(value, props[key], "%s.%s" % (path, key)))
            elif schema.get("additionalProperties") is False:
                errors.append("%s: unexpected property %r" % (path, key))

    for sub in schema.get("allOf", []):
        errors.extend(schema_errors(instance, sub, path))

    if "if" in schema:
        if not schema_errors(instance, schema["if"], path):
            if "then" in schema:
                errors.extend(schema_errors(instance, schema["then"], path))

    return errors


def validate_or_fail(instance, schema, schema_name, source):
    errors = schema_errors(instance, schema)
    if errors:
        fail_fast("emitted document violates %s for %s: %s"
                  % (schema_name, source, "; ".join(errors[:5])))


def read_task_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def authoritative_sections(task_text):
    """Authoritative task content grouped by `##` section (lowercased names).

    Mirrors the production validators' content scan — fenced code blocks,
    HTML comments, and blockquote lines are dropped — and additionally scopes
    every line to its section so approvals and evidence can only be satisfied
    by their own authoritative sections, never by prose or unrelated tables.
    """
    sections = {}
    in_fence = False
    in_comment = False
    current = None
    for raw in task_text.splitlines():
        line = raw.rstrip("\r")
        stripped = line.strip()
        if in_fence:
            if line.startswith("```"):
                in_fence = False
            continue
        if line.startswith("```"):
            in_fence = True
            continue
        if in_comment:
            if "-->" in stripped:
                in_comment = False
            continue
        if "<!--" in stripped:
            if "-->" not in stripped:
                in_comment = True
            continue
        if stripped.startswith(">"):
            continue
        if stripped.startswith("##"):
            current = stripped.lstrip("#").strip().lower()
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections.setdefault(current, []).append(line)
    return sections


APPROVAL_SECTION = "approval gates"
EVIDENCE_SECTIONS = ("required evidence", "requirement-to-evidence")
CANONICAL_TABLE_HEADER_RE = re.compile(
    r"^\|\s*(?:ac id|requirement id)\s*\|[^|]*\|\s*result\s*\|\s*$",
    re.IGNORECASE,
)


def canonical_evidence_rows(section_lines):
    """Rows of the first canonical `<ID> | Evidence | Result` table only."""
    rows = []
    collecting = False
    for raw in section_lines:
        s = raw.strip()
        if not collecting:
            if CANONICAL_TABLE_HEADER_RE.match(s):
                collecting = True
            continue
        if not s.startswith("|"):
            break
        cells = [c.strip() for c in s.strip("|").split("|")]
        if all(set(c) <= set("-: ") for c in cells):
            continue
        rows.append(s.lower())
    return rows


APPROVAL_PATTERN = re.compile(r"^\s*[-*]\s*\[x\]\s*AG-\d+:", re.IGNORECASE)


def approvals_declare(sections, token):
    wanted = re.sub(r"[-_]+", " ", token).lower()
    for line in sections.get(APPROVAL_SECTION, []):
        if APPROVAL_PATTERN.match(line):
            candidate = re.sub(r"[-_]+", " ", line).lower()
            if wanted in candidate:
                return True
    return False


def evidence_contains(sections, token):
    for name in EVIDENCE_SECTIONS:
        for row in canonical_evidence_rows(sections.get(name, [])):
            if token.lower() in row:
                return True
    return False


def path_forbidden(changed_paths, forbidden_paths):
    """Directory-aware match: a change is forbidden when it equals a
    forbidden path, lives inside one, or would overwrite one."""
    for changed in changed_paths:
        norm = changed.replace("\\", "/").lstrip("./")
        for fp in forbidden_paths:
            f = fp.replace("\\", "/").lstrip("./")
            if norm == f or norm.startswith(f.rstrip("/") + "/") or f.startswith(norm.rstrip("/") + "/"):
                return True
    return False


def artifact_files(artifacts_dir):
    found = []
    for root, _dirs, names in os.walk(artifacts_dir):
        for name in names:
            found.append(os.path.join(root, name))
    return sorted(found)


def run_task_validator(task_path):
    proc = subprocess.run(
        [BASH_BIN, bash_path(task_validator), "--handoff", bash_path(task_path)],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    detail = ""
    if proc.returncode != 0:
        first = proc.stderr.decode("utf-8", errors="replace").strip().splitlines()
        detail = first[0] if first else "validate-task --handoff rejected the artifact (exit %d)" % proc.returncode
    return proc.returncode == 0, detail


def run_context_validator(task_path):
    proc = subprocess.run(
        [BASH_BIN, bash_path(context_validator), "--handoff", "--format", "json", bash_path(task_path)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    profile = None
    ids = []
    detail = ""
    ok = proc.returncode == 0
    try:
        doc = json.loads(proc.stdout.decode("utf-8", errors="replace"))
        profile = doc.get("profile")
        ids = [m.get("id") for m in doc.get("selected_modules", []) if isinstance(m, dict)]
    except ValueError:
        ok = False
        first = proc.stderr.decode("utf-8", errors="replace").strip().splitlines()
        detail = first[0] if first else "validate-context produced no result document (exit %d)" % proc.returncode
    return ok, profile, ids, detail


SUMMARY_FIELDS = ("checks_defined", "checks_run", "required_run",
                  "passed", "failed", "optional_failed", "blocked",
                  "optional_skipped")


def verification_agrees(vdoc):
    """Summary counts must be derivable from the actual checks array."""
    summary = vdoc.get("summary", {})
    checks = vdoc.get("checks", [])
    executed = [c for c in checks if c.get("status") in ("PASS", "FAIL")]
    derived = {
        "checks_defined": len(checks),
        "checks_run": len(executed),
        "required_run": sum(1 for c in executed if c.get("requirement") == "required"),
        "passed": sum(1 for c in checks if c.get("status") == "PASS"),
        "failed": sum(1 for c in checks if c.get("requirement") == "required" and c.get("status") == "FAIL"),
        "optional_failed": sum(1 for c in checks if c.get("requirement") == "optional" and c.get("status") == "FAIL"),
        "blocked": sum(1 for c in checks if c.get("status") == "BLOCKED"),
        "optional_skipped": sum(1 for c in checks if c.get("status") == "SKIPPED_OPTIONAL"),
    }
    mismatched = [f for f in SUMMARY_FIELDS if summary.get(f) != derived[f]]
    return mismatched


def evaluate_scenario(scenario_path):
    checks = {}
    details = {}

    def record(cid, passed, detail=""):
        checks[cid] = bool(passed)
        if detail:
            details[cid] = detail

    scenario = None
    schema_ok = False
    try:
        scenario = load_json(scenario_path)
    except (ValueError, OSError) as exc:
        record("SCENARIO_SCHEMA_VALID", False, "unreadable or malformed scenario.json: %s" % exc)

    if scenario is not None:
        try:
            sschema = load_json(scenario_schema_path)
        except (ValueError, OSError) as exc:
            record("SCENARIO_SCHEMA_VALID", False, "cannot load scenario schema: %s" % exc)
            schema_ok = False
        else:
            errs = schema_errors(scenario, sschema)
            schema_ok = not errs
            record("SCENARIO_SCHEMA_VALID", schema_ok,
                   "" if schema_ok else "scenario.json violates scenario-v1: %s" % "; ".join(errs[:3]))

    sid = scenario.get("id") if isinstance(scenario, dict) and schema_ok else \
        os.path.basename(os.path.dirname(scenario_path))

    artifacts_dir = os.path.join(os.path.dirname(scenario_path), "artifacts")
    task_path = os.path.join(artifacts_dir, "task.md")

    expected = scenario.get("expected", {}) if isinstance(scenario, dict) else {}
    forbidden = scenario.get("forbidden", {}) if isinstance(scenario, dict) else {}
    required_modules = expected.get("required_modules", []) if schema_ok else []
    required_gates = expected.get("required_approval_gates", []) if schema_ok else []
    required_evidence = expected.get("required_evidence", []) if schema_ok else []

    if schema_ok and os.path.isfile(task_path) and os.path.getsize(task_path) > 0:
        record("TASK_ARTIFACT_PRESENT", True)

        task_ok, task_detail = run_task_validator(task_path)
        record("TASK_CONTRACT_VALID", task_ok, "" if task_ok else task_detail)

        ctx_ok, profile, module_ids, ctx_detail = run_context_validator(task_path)
        record("CONTEXT_CONTRACT_VALID", ctx_ok,
               "" if ctx_ok else (ctx_detail or "validate-context --handoff rejected the artifact task file"))

        min_profile = expected.get("minimum_profile")
        prof_rank = PROFILE_RANK.get(profile, -1)
        need_rank = PROFILE_RANK.get(min_profile, 99)
        record("PROFILE_FLOOR_RESPECTED", prof_rank >= need_rank,
               "task profile '%s' vs minimum '%s'" % (profile, min_profile))

        missing = [m for m in required_modules if m not in module_ids]
        record("REQUIRED_MODULES_SELECTED", not missing,
               "" if not missing else "missing: %s" % ", ".join(missing))

        forbidden_modules = forbidden.get("modules", []) if isinstance(forbidden, dict) else []
        used = [m for m in module_ids if m in forbidden_modules]
        record("FORBIDDEN_MODULES_AVOIDED", not used,
               "" if not used else "forbidden modules selected: %s" % ", ".join(used))

        auth_sections = authoritative_sections(read_task_text(task_path))
        gate_missing = [g for g in required_gates if not approvals_declare(auth_sections, g)]
        record("APPROVALS_DECLARED", not gate_missing,
               "" if not gate_missing else "no approval record for: %s" % ", ".join(gate_missing))

        ev_missing = [e for e in required_evidence if not evidence_contains(auth_sections, e)]
        record("EVIDENCE_PRESENT", not ev_missing,
               "" if not ev_missing else "evidence table lacks: %s" % ", ".join(ev_missing))

        verification_path = os.path.join(artifacts_dir, "verification-result.json")
        ver_ok = False
        ver_detail = "artifact verification-result.json must be a schema-valid PASS verification_result"
        if os.path.isfile(verification_path):
            try:
                vdoc = load_json(verification_path)
                vschema = load_json(verification_schema_path)
                errs = schema_errors(vdoc, vschema)
                mismatched = verification_agrees(vdoc)
                if errs:
                    ver_detail = "violates verification-result-v1: %s" % "; ".join(errs[:3])
                elif mismatched:
                    ver_detail = "summary disagrees with checks array: %s" % ", ".join(mismatched)
                elif vdoc.get("result") != "PASS":
                    ver_detail = "verification result is %r, not PASS" % vdoc.get("result")
                else:
                    ver_ok = True
            except (ValueError, OSError) as exc:
                ver_detail = "unreadable verification-result.json: %s" % exc
        record("VERIFICATION_SCHEMA_VALID", ver_ok, "" if ver_ok else ver_detail)

        changed = scenario["input"]["changed_paths"] if schema_ok else []
        bad_paths = path_forbidden(changed, forbidden.get("paths", []) if isinstance(forbidden, dict) else [])
        record("FORBIDDEN_PATHS_AVOIDED", not bad_paths,
               "" if not bad_paths else "a changed path matches a forbidden path")

        tokens = [t.lower() for t in (forbidden.get("actions", []) if isinstance(forbidden, dict) else [])]
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

    return finalize(sid, scenario_path, scenario, checks, details)


def finalize(sid, scenario_path, scenario, checks=None, details=None):
    checks = checks or {}
    details = details or {}
    ordered = []
    for cid in CHECK_ORDER:
        if cid in checks:
            ordered.append({"id": cid, "detail": details.get(cid, ""), "passed": checks[cid]})
    total = len(ordered)
    passed = sum(1 for c in ordered if c["passed"])
    observed = "PASS" if total > 0 and passed == total else "FAIL"

    expectation = "PASS"
    expected_failures = []
    if isinstance(scenario, dict):
        expectation = scenario.get("fixture_expected_result", "PASS")
        expected_failures = sorted(scenario.get("expected_failed_checks", []))

    # A negative control only proves detection when the EXACT intended check
    # set failed; a failure of any other check must fail the harness itself.
    actual_failures = sorted(cid for cid in checks if not checks[cid])
    matched = observed == expectation and actual_failures == expected_failures
    diagnostics = []
    if observed != expectation:
        diagnostics.append({
            "code": "FIXTURE_EXPECTATION_MISMATCH",
            "message": "observed %s does not match fixture_expected_result %s" % (observed, expectation),
        })
    elif actual_failures != expected_failures:
        diagnostics.append({
            "code": "FIXTURE_EXPECTATION_MISMATCH",
            "message": "failed checks [%s] do not match expected_failed_checks [%s]"
                       % (", ".join(actual_failures), ", ".join(expected_failures)),
        })

    doc = {
        "schema_version": 1,
        "protocol_version": "1.7.0",
        "kind": "behavioral_evaluation_result",
        "mode": "offline-fixture",
        "observed_result": observed,
        "expected_result": expectation,
        "expectation_matched": matched,
        "result": "PASS" if matched else "FAIL",
        "exit_code": 0 if matched else 1,
        "scenario_id": sid,
        "summary": {"total": total, "passed": passed, "failed": total - passed},
        "checks": ordered,
        "diagnostics": diagnostics,
    }
    return doc, matched


if not os.path.isdir(scenarios_dir):
    fail_fast("scenarios directory not found: %s" % scenarios_dir)

try:
    result_schema = load_json(result_schema_path)
except (ValueError, OSError) as exc:
    fail_fast("cannot load evaluation-result schema: %s" % exc)

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
    # Every emitted document must satisfy its own managed schema before the
    # runner may print it or report success (#review blocker 4).
    validate_or_fail(doc, result_schema, "evaluation-result-v1.schema.json", doc.get("scenario_id"))
    docs.append(doc)
    if fmt == "json":
        print(json.dumps(doc, separators=(",", ":")))
    else:
        failed_checks = []
        for c in doc["checks"]:
            if not c["passed"]:
                d = c.get("detail", "").strip()
                failed_checks.append(c["id"] + (("[" + d[:140] + "]") if d else ""))
        suffix = (" failed=%s" % ",".join(failed_checks)) if failed_checks else ""
        print("%-28s observed=%-4s expected=%-4s harness=%-4s%s" % (
            doc["scenario_id"], doc["observed_result"], doc["expected_result"],
            doc["result"], suffix))
    if not matched:
        run_failures += 1

total_docs = len(docs)
expected_ok = sum(1 for d in docs if d["result"] == "PASS")

if fmt != "json":
    print("")
    print("evals: %d/%d scenarios evaluated correctly" % (expected_ok, total_docs))

sys.exit(0 if run_failures == 0 else 1)
PYEOF
