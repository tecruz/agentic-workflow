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

@test "the None selected sentinel rejects unresolved suffixes" {
    # Placeholder suffix on a completed task: BLOCKED (2).
    classify context-none-tbd.md
    [ "$status" -eq 2 ]
    # Separator without any rationale: INVALID (1).
    classify context-none-empty-rationale.md
    [ "$status" -eq 1 ]
    # A substantive narrative suffix remains acceptable.
    classify context-none-narrative-ok.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for an unknown module id" {
    classify context-unknown-module.md
    [ "$status" -eq 1 ]
}

@test "MODULE_UNKNOWN diagnostic names the offending module" {
    classify context-unknown-module.md
    [ "$status" -eq 1 ]
    out="$(bash "$VALIDATE" "$FIXTURES/context-unknown-module.md" 2>&1)" || true
    printf '%s' "$out" | grep -q "'mystery-module' is not in the managed registry"
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
assert doc["protocol_version"] == "1.7.0", doc["protocol_version"]
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
    printf '# Module: other\n\n## ID\n\nsome-other-module\n\n## Version\n\n1\n\n## Minimum risk profile\n\nstandard\n\n## Load when\n\n- trigger line\n\n## Required context\n\n- context line\n\n## Approval gates\n\n- gate line\n\n## Required evidence\n\n- evidence line\n\n## Prohibited shortcuts\n\n- shortcut line\n' > "$sandbox/some-other-module/MODULE.md"
    classify_with_registry "$sandbox" "$FIXTURES/context-valid-single.md"
    code="$status"
    rm -rf "$sandbox"
    [ "$code" -eq 1 ]
}


# --- Authority-scope regressions (review blocker #2) -----------------------

@test "INVALID (1) for a selection hidden inside a fenced code block" {
    classify context-fenced-selection.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a None selected sentinel hidden inside a fence" {
    classify context-fenced-none.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an unclosed fence that swallows the whole section" {
    classify context-unclosed-fence.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an HTML-commented selection" {
    classify context-commented-selection.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a blockquoted selection" {
    classify context-blockquote-selection.md
    [ "$status" -eq 1 ]
}

@test "declarations inside fences are ignored: fenced Profile cannot satisfy a floor" {
    # The fence declares high-assurance; the authoritative file says standard,
    # so selecting security-review must still trip the profile floor.
    out="$(bash "$VALIDATE" "$FIXTURES/context-fenced-profile-status.md" 2>&1)" || true
    printf '%s' "$out" | grep -q "below the 'high-assurance' minimum"
}

# --- Registry identity and metadata validation (review blocker #3) ---------

make_module() {  # make_module <registry> <dirname> <declared-id> <version> <min-profile>
    mkdir -p "$1/$2"
    {
        echo "# Module: $2"
        echo
        echo "## ID"
        echo
        echo "$3"
        echo
        echo "## Version"
        echo
        echo "$4"
        echo
        echo "## Minimum risk profile"
        echo
        if [ -n "$5" ]; then
            echo "$5"
            echo
        fi
        echo "## Load when"
        echo
        echo "- trigger line"
        echo
        echo "## Required context"
        echo
        echo "- context line"
        echo
        echo "## Approval gates"
        echo
        echo "- gate line"
        echo
        echo "## Required evidence"
        echo
        echo "- evidence line"
        echo
        echo "## Prohibited shortcuts"
        echo
        echo "- shortcut line"
    } > "$1/$2/MODULE.md"
}

expect_registry_blocked() {  # expect_registry_blocked <fixture> <setup-fn>
    local fixture="$1" setup="$2"
    sandbox="$(mktemp -d)"
    "$setup" "$sandbox"
    AGENTIC_CONTEXT_REGISTRY="$sandbox" run bash "$VALIDATE" "$FIXTURES/$fixture"
    code="$status"
    out="$output"
    rm -rf "$sandbox"
    [ "$code" -eq 2 ]
    printf '%s' "$out" | grep -q "CONTEXT_REGISTRY_INVALID\|registry is unusable"
}

register_mismatched_id()      { make_module "$1" good-name other-name 1 high-assurance; }
register_duplicate_id()       { make_module "$1" module-a dup-id 1 standard; make_module "$1" module-b dup-id 1 standard; }
register_path_id()            { make_module "$1" evil '../other-module' 1 standard; }
register_missing_id()         { make_module "$1" no-id '' 1 standard; }
register_no_min_profile()     { make_module "$1" no-min some-id 1 ''; }
register_unknown_min_profile(){ make_module "$1" odd-min some-id 1 critical; }
register_duplicate_heading()  {
    make_module "$1" dup-head some-id 1 standard
    printf '\n## Version\n\n2\n' >> "$1/dup-head/MODULE.md"
}
register_empty_doc_section()  {
    make_module "$1" empty-docs some-id 1 standard
    # No `sed -i`: BSD sed requires an argument to -i while GNU does not.
    grep -v '^- trigger line$' "$1/empty-docs/MODULE.md" > "$1/empty-docs/MODULE.md.tmp"
    mv "$1/empty-docs/MODULE.md.tmp" "$1/empty-docs/MODULE.md"
}
register_valid_minimal()      { make_module "$1" some-other-module some-other-module 1 standard; }

@test "BLOCKED (2): declared ID differing from its directory name" {
    expect_registry_blocked context-valid-single.md register_mismatched_id
}
@test "BLOCKED (2): the same declared ID in two directories" {
    expect_registry_blocked context-valid-single.md register_duplicate_id
}
@test "BLOCKED (2): an ID containing a path component" {
    expect_registry_blocked context-valid-single.md register_path_id
}
@test "BLOCKED (2): a module without any ID" {
    expect_registry_blocked context-valid-single.md register_missing_id
}
@test "BLOCKED (2): a missing Minimum risk profile" {
    expect_registry_blocked context-valid-single.md register_no_min_profile
}
@test "BLOCKED (2): an unrecognized Minimum risk profile" {
    expect_registry_blocked context-valid-single.md register_unknown_min_profile
}
@test "BLOCKED (2): a duplicated Version heading" {
    expect_registry_blocked context-valid-single.md register_duplicate_heading
}
@test "BLOCKED (2): a documentation section without content" {
    expect_registry_blocked context-valid-single.md register_empty_doc_section
}

@test "a registry that lacks the selected module is INVALID (1), not blocked" {
    sandbox="$(mktemp -d)"
    register_valid_minimal "$sandbox"
    AGENTIC_CONTEXT_REGISTRY="$sandbox" run bash "$VALIDATE" "$FIXTURES/context-valid-single.md"
    code="$status"
    rm -rf "$sandbox"
    [ "$code" -eq 1 ]
}

@test "a path-like ID never resolves outside the sandbox registry" {
    sandbox="$(mktemp -d)"
    register_path_id "$sandbox"
    mkdir -p "$sandbox/other-module"
    echo pwned > "$sandbox/other-module/MODULE.md"
    AGENTIC_CONTEXT_REGISTRY="$sandbox" run bash "$VALIDATE" "$FIXTURES/context-valid-single.md"
    code="$status"
    out="$output"
    rm -rf "$sandbox"
    [ "$code" -eq 2 ]
    printf '%s' "$out" | grep -q "CONTEXT_REGISTRY_INVALID\|registry is unusable"
}

# --- Path redaction in JSON output (review blocker #7) ---------------------

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

@test "composite handoff gate accepts a fully valid completed task (Bash)" {
    run bash "$REPO_ROOT/.agentic/scripts/validate-handoff.sh" "$FIXTURES/context-full-contract-ha.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"handoff gate satisfied"* ]]
}

@test "composite handoff gate reports BLOCKED when either leg blocks (Bash)" {
    # Task validator: BLOCKED(2) on planned status under --handoff;
    # context validator: INVALID(1) on bare sentinel? No: bare sentinel is
    # valid, so this fixture isolates the task leg's BLOCKED.
    run bash "$REPO_ROOT/.agentic/scripts/validate-handoff.sh" "$FIXTURES/context-valid-bare-none.md"
    [ "$status" -eq 2 ]
}

@test "composite handoff gate reports INVALID for an unknown module (Bash)" {
    run bash "$REPO_ROOT/.agentic/scripts/validate-handoff.sh" "$FIXTURES/context-unknown-module.md"
    [ "$status" -eq 1 ]
}

# --- Profile contract: standalone VALID requires exactly one profile -------

@test "INVALID (1): selections require exactly one recognized risk profile" {
    for fx in context-profile-missing context-profile-unknown context-profile-duplicate context-profile-invalid-with-ha-module context-profile-invalid-none-selected; do
        run bash "$VALIDATE" "$FIXTURES/$fx.md"
        [ "$status" -eq 1 ]
        printf '%s' "$output" | grep -qi "risk profile"
    done
}

@test "JSON mode never reports VALID with a null profile" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    out="$(bash "$VALIDATE" --format json "$FIXTURES/context-profile-unknown.md" 2>/dev/null)" || true
    printf '%s' "$out" | python3 -c '
import json, sys
doc = json.loads(sys.stdin.read())
assert doc["result"] == "INVALID", doc
assert doc["profile"] is None, doc
assert doc["diagnostics"][0]["code"] == "CONTEXT_PROFILE_INVALID", doc
'
}

# --- Successful-leg JSON serialization must be checked (review blocker #6) --

@test "JSON mode emits exactly one document on success" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    out="$(bash "$VALIDATE" --format json "$FIXTURES/context-valid-single.md" 2>/dev/null)" || {
        echo "validator failed unexpectedly: $out" >&2
        return 1
    }
    count="$(printf '%s\n' "$out" | grep -c '"result": *"VALID"')"
    [ "$count" -eq 1 ]
    printf '%s' "$out" | python3 -c '
import json, sys
doc = json.loads(sys.stdin.read())
assert doc["result"] == "VALID", doc
assert doc["exit_code"] == 0, doc
'
}

@test "a failing python3 serialization fails the run instead of faking success" {
    stub="$(mktemp -d)"
    printf '#!/bin/sh\nexit 3\n' > "$stub/python3"
    chmod +x "$stub/python3"
    code=0
    out="$(PATH="$stub:$PATH" bash "$VALIDATE" --format json "$FIXTURES/context-valid-single.md" 2>&1)" || code=$?
    rm -rf "$stub"
    [ "$code" -eq 1 ]
    printf '%s' "$out" | grep -q "failed to serialize JSON result"
    if printf '%s' "$out" | grep -q '"result": *"VALID"'; then
        echo "VALID emitted despite serialization failure: $out" >&2
        return 1
    fi
}

@test "an unwritable JSON destination fails the run instead of faking success" {
    if [ ! -w /dev/full ]; then
        skip "/dev/full not available (POSIX CI only)"
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    run bash -c "bash '$VALIDATE' --format json '$FIXTURES/context-valid-single.md' >/dev/full"
    [ "$status" -ne 0 ]
}

# --- Golden expected outcomes for new context fixtures (review blockers #1, #2, #3) ---

@test "VALID (0) for uppercase profile STANDARD (context-profile-uppercase-standard.md)" {
    classify context-profile-uppercase-standard.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for canonical em-dash separator (context-selection-canonical-emdash.md)" {
    classify context-selection-canonical-emdash.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for canonical hyphen separator (context-selection-canonical-hyphen.md)" {
    classify context-selection-canonical-hyphen.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for colon separator (context-selection-colon-separator.md)" {
    classify context-selection-colon-separator.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for missing separator (context-selection-missing-separator.md)" {
    classify context-selection-missing-separator.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for uppercase LOADED token (context-selection-uppercase-loaded.md)" {
    classify context-selection-uppercase-loaded.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for 'None selectedness' malformed sentinel (context-sentinel-selectedness.md)" {
    classify context-sentinel-selectedness.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for 'None selected-but-not-really' malformed sentinel (context-sentinel-hyphen-nospace.md)" {
    classify context-sentinel-hyphen-nospace.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a 'None selected because ...' sentinel with no separator (context-sentinel-because.md)" {
    classify context-sentinel-because.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a double-space sentinel separator (context-sentinel-double-space.md)" {
    classify context-sentinel-double-space.md
    [ "$status" -eq 0 ]
}
