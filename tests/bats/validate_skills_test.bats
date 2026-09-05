#!/usr/bin/env bats

# validate-skills.sh — skill-invocation validator tests (ADR-0014).
# Runs against the fixture task files under tests/fixtures/skill-tasks.
# The registry under test is the repository's own managed registry; sandboxed
# registry cases build an isolated copy in a temp directory. Expected
# classifications are deterministic and language-independent:
#   0 = VALID, 1 = INVALID, 2 = BLOCKED.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
VALIDATE="$REPO_ROOT/.agentic/scripts/validate-skills.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/skill-tasks"

classify() {  # classify <fixture>
    run bash "$VALIDATE" "$FIXTURES/$1" >/dev/null 2>&1
}

classify_with_registry() {  # classify_with_registry <registry-dir> <fixture>
    AGENTIC_SKILLS_REGISTRY="$1" run bash "$VALIDATE" "$2" >/dev/null 2>&1
}

@test "VALID (0) for a single known invocation" {
    classify skill-valid-single.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for multiple distinct invocations" {
    classify skill-valid-multi.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for the None required sentinel" {
    classify skill-valid-none.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for a bare None required sentinel" {
    classify skill-valid-bare-none.md
    [ "$status" -eq 0 ]
}

@test "the None required sentinel rejects unresolved suffixes" {
    # Placeholder suffix on a completed task: BLOCKED (2).
    classify skill-none-tbd.md
    [ "$status" -eq 2 ]
    # Separator without any rationale: INVALID (1).
    classify skill-none-empty-rationale.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an unknown skill id" {
    classify skill-unknown.md
    [ "$status" -eq 1 ]
}

@test "SKILL_UNKNOWN diagnostic names the offending skill" {
    classify skill-unknown.md
    [ "$status" -eq 1 ]
    out="$(bash "$VALIDATE" "$FIXTURES/skill-unknown.md" 2>&1)" || true
    printf '%s' "$out" | grep -q "'mystery-skill' is not in the managed registry"
}

@test "INVALID (1) for a duplicate invocation" {
    classify skill-duplicate.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the invoked confirmation token is missing" {
    classify skill-missing-invoked-token.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an invocation without a rationale" {
    classify skill-missing-rationale.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an unrecognized invocation version" {
    classify skill-version-unsupported.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the task profile sits below the skill minimum" {
    classify skill-profile-too-low.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the Skills section is absent" {
    classify skill-section-missing.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the section has neither invocation nor sentinel" {
    classify skill-empty-section.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a completed task with a placeholder rationale" {
    classify skill-done-placeholder.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when the sentinel coexists with invocations" {
    classify skill-sentinel-conflict.md
    [ "$status" -eq 1 ]
}

@test "--handoff rejects a task whose status is not done" {
    run bash "$VALIDATE" --handoff "$FIXTURES/skill-valid-bare-none.md" >/dev/null 2>&1
    [ "$status" -eq 1 ]
}

@test "--handoff accepts a completed valid task" {
    run bash "$VALIDATE" --handoff "$FIXTURES/skill-valid-single.md" >/dev/null 2>&1
    [ "$status" -eq 0 ]
}

@test "JSON mode emits a schema-shaped document on success" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    out="$(bash "$VALIDATE" --format json "$FIXTURES/skill-valid-single.md")"
    echo "$out" | python3 -c '
import json, sys
doc = json.loads(sys.stdin.read())
assert doc["kind"] == "skill_validation_result", doc["kind"]
assert doc["result"] == "VALID", doc["result"]
assert doc["exit_code"] == 0, doc["exit_code"]
assert doc["protocol_version"] == "1.11.0", doc["protocol_version"]
assert [m["id"] for m in doc["invoked_skills"]] == ["verification-triage"], doc["invoked_skills"]
assert doc["diagnostics"] == [], doc["diagnostics"]
'
}

@test "JSON mode carries the stable diagnostic code on failure" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    run bash "$VALIDATE" --format json "$FIXTURES/skill-unknown.md"
    [ "$status" -eq 1 ]
    echo "$output" | python3 -c '
import json, sys
doc = json.loads(sys.stdin.read())
assert doc["result"] == "INVALID", doc["result"]
assert doc["exit_code"] == 1, doc["exit_code"]
assert len(doc["diagnostics"]) == 1, doc["diagnostics"]
assert doc["diagnostics"][0]["code"] == "SKILL_UNKNOWN", doc["diagnostics"][0]
'
}

@test "BLOCKED (2) for an unusable registry with a malformed skill version" {
    sandbox="$(mktemp -d)"
    mkdir -p "$sandbox/broken-skill"
    printf '# Skill: broken\n\n## ID\n\nbroken-skill\n\n## Version\n\nzero\n' > "$sandbox/broken-skill/SKILL.md"
    classify_with_registry "$sandbox" "$FIXTURES/skill-valid-single.md"
    code="$status"
    rm -rf "$sandbox"
    [ "$code" -eq 2 ]
}

@test "INVALID (1) against a registry that lacks the invoked skill" {
    sandbox="$(mktemp -d)"
    mkdir -p "$sandbox/some-other-skill"
    printf '# Skill: other\n\n## ID\n\nsome-other-skill\n\n## Version\n\n1\n\n## Minimum risk profile\n\nstandard\n\n## Invoked when\n\n- trigger line\n\n## Required context\n\n- context line\n\n## Approval gates\n\n- gate line\n\n## Required evidence\n\n- evidence line\n\n## Prohibited shortcuts\n\n- shortcut line\n' > "$sandbox/some-other-skill/SKILL.md"
    classify_with_registry "$sandbox" "$FIXTURES/skill-valid-single.md"
    code="$status"
    rm -rf "$sandbox"
    [ "$code" -eq 1 ]
}

@test "INVALID (1) for an invocation hidden inside a fenced code block" {
    classify skill-fenced-selection.md
    [ "$status" -eq 1 ]
}

@test "JSON redacts absolute outside-project paths to the basename (Bash)" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    out="$(bash "$VALIDATE" --format json /home/someone/secret/project/TASK-X.md 2>/dev/null)" || true
    printf '%s' "$out" | grep -q '"task_file": *"TASK-X.md"'
    if printf '%s' "$out" | grep -q '/home/someone'; then
        echo "absolute path leaked into JSON: $out" >&2
        return 1
    fi
}
