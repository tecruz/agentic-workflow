#!/usr/bin/env bats

# validate-context.sh — context-module selection validator tests.
# Runs against the fixture task files under tests/fixtures/context-tasks.
# The registry under test is the repository's own managed registry; sandboxed
# registry cases build an isolated copy in a temp directory. Expected
# classifications are deterministic and language-independent:
#   0 = VALID, 1 = INVALID, 2 = BLOCKED.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
VALIDATE="$REPO_ROOT/.agentic/scripts/validate-context.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/context-tasks"
REGISTRY="$REPO_ROOT/.agentic/context"

classify() {  # classify <fixture>
    run bash "$VALIDATE" "$FIXTURES/$1" >/dev/null 2>&1
}

classify_with_registry() {  # classify_with_registry <registry-dir> <fixture>
    AGENTIC_CONTEXT_REGISTRY="$1" run bash "$VALIDATE" "$2" >/dev/null 2>&1
}

@test "VALID (0) for a single known selection" {
    classify context-valid-single.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for multiple distinct selections" {
    classify context-valid-multi.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for the None selected sentinel" {
    classify context-valid-none.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for a bare None selected sentinel" {
    classify context-valid-bare-none.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for an unknown module id" {
    classify context-unknown-module.md
    [ "$status" -eq 1 ]
}

@test "MODULE_UNKNOWN diagnostic names the offending module" {
    run bash -c "bash '$VALIDATE' '$FIXTURES/context-unknown-module.md' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mystery-module'* is not in the managed registry"* ]]
}

@test "INVALID (1) for a duplicate selection" {
    classify context-duplicate-module.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the loaded confirmation token is missing" {
    classify context-missing-loaded-token.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a selection without a rationale" {
    classify context-missing-rationale.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an unrecognized selection version" {
    classify context-version-unsupported.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the task profile sits below the module minimum" {
    classify context-profile-too-low.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the Context modules section is absent" {
    classify context-section-missing.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the section has neither selection nor sentinel" {
    classify context-empty-section.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a completed task with a placeholder rationale" {
    classify context-done-placeholder.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when the sentinel coexists with selections" {
    classify context-sentinel-conflict.md
    [ "$status" -eq 1 ]
}

@test "--handoff rejects a task whose status is not done" {
    run bash "$VALIDATE" --handoff "$FIXTURES/context-valid-bare-none.md" >/dev/null 2>&1
    [ "$status" -eq 1 ]
}

@test "--handoff accepts a completed valid task" {
    run bash "$VALIDATE" --handoff "$FIXTURES/context-valid-single.md" >/dev/null 2>&1
    [ "$status" -eq 0 ]
}

@test "JSON mode emits a schema-shaped document on success" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    out="$(bash "$VALIDATE" --format json "$FIXTURES/context-valid-single.md")"
    echo "$out" | python3 -c '
import json, sys
doc = json.loads(sys.stdin.read())
assert doc["kind"] == "context_validation_result", doc["kind"]
assert doc["result"] == "VALID", doc["result"]
assert doc["exit_code"] == 0, doc["exit_code"]
assert doc["protocol_version"] == "1.5.0", doc["protocol_version"]
assert [m["id"] for m in doc["selected_modules"]] == ["security-review"], doc["selected_modules"]
assert doc["diagnostics"] == [], doc["diagnostics"]
'
}

@test "JSON mode carries the stable diagnostic code on failure" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    run bash "$VALIDATE" --format json "$FIXTURES/context-unknown-module.md"
    [ "$status" -eq 1 ]
    echo "$output" | python3 -c '
import json, sys
doc = json.loads(sys.stdin.read())
assert doc["result"] == "INVALID", doc["result"]
assert doc["exit_code"] == 1, doc["exit_code"]
assert len(doc["diagnostics"]) == 1, doc["diagnostics"]
assert doc["diagnostics"][0]["code"] == "MODULE_UNKNOWN", doc["diagnostics"][0]
'
}

@test "BLOCKED (2) for an unusable registry with a malformed module version" {
    sandbox="$(mktemp -d)"
    mkdir -p "$sandbox/broken-module"
    printf '# Module: broken\n\n## ID\n\nbroken-module\n\n## Version\n\nzero\n' > "$sandbox/broken-module/MODULE.md"
    classify_with_registry "$sandbox" "$FIXTURES/context-valid-single.md"
    code="$status"
    rm -rf "$sandbox"
    [ "$code" -eq 2 ]
}

@test "INVALID (1) against a registry that lacks the selected module" {
    sandbox="$(mktemp -d)"
    mkdir -p "$sandbox/some-other-module"
    printf '# Module: other\n\n## ID\n\nsome-other-module\n\n## Version\n\n1\n' > "$sandbox/some-other-module/MODULE.md"
    classify_with_registry "$sandbox" "$FIXTURES/context-valid-single.md"
    code="$status"
    rm -rf "$sandbox"
    [ "$code" -eq 1 ]
}
