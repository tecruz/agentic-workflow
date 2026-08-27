# Behavioral Evaluations (offline)

Deterministic, offline harness evaluations for the agentic-workflow framework
itself. Scenarios evaluate **observable behavior recorded in saved artifacts**
— final task files, selected context modules, risk profiles, approvals,
verification results — never hidden reasoning or chain-of-thought.

No scenario calls an external model. No API keys are required. The runner is
fully deterministic, so it is safe as a merge gate.

## Layout

    evals/
    ├── schemas/
    │   ├── scenario-v1.schema.json
    │   └── evaluation-result-v1.schema.json
    ├── scenarios/<scenario-id>/
    │   ├── scenario.json            # scenario definition (schema v1)
    │   └── artifacts/               # saved observable artifacts
    │       ├── task.md              # final task contract as produced
    │       └── verification-result.json
    ├── run-evals.sh                 # Bash runner
    ├── run-evals.ps1                # PowerShell runner
    ├── generate-scenarios.ps1       # deterministic fixture generator
    └── README.md

## What the runner checks

For every scenario the runner applies the REAL production contracts to the
fixture artifacts and produces a `behavioral_evaluation_result` document:

| Check id | Observable question |
| --- | --- |
| SCENARIO_SCHEMA_VALID | Does `scenario.json` satisfy `scenario-v1.schema.json`? |
| TASK_ARTIFACT_PRESENT | Was a final task file produced? |
| TASK_CONTRACT_VALID | Does `validate-task --handoff` accept the artifact task? |
| CONTEXT_CONTRACT_VALID | Does `validate-context --handoff` accept the selections? |
| VERIFICATION_SCHEMA_VALID | Is `verification-result.json` a schema-valid PASS document whose summary agrees with its checks array? |
| PROFILE_FLOOR_RESPECTED | Is the declared profile at least the scenario minimum? |
| REQUIRED_MODULES_SELECTED | Were all required specialist modules selected? |
| FORBIDDEN_MODULES_AVOIDED | Were irrelevant modules avoided? |
| APPROVALS_DECLARED | Were the required approvals recorded in authoritative sections? |
| EVIDENCE_PRESENT | Do the required evidence tokens appear in authoritative evidence rows? |
| FORBIDDEN_PATHS_AVOIDED | Were forbidden paths left untouched? |
| FORBIDDEN_ACTIONS_ABSENT | Do forbidden-action tokens appear anywhere in the artifacts? |

Approval and evidence parsing is authoritative-only: fenced code blocks, HTML
comments, and blockquote lines are ignored, mirroring the production
validators. A fixture cannot satisfy an approval or evidence check with
non-authoritative content.

## The result document

Every emitted document carries the three-way classification split required by
`evaluation-result-v1.schema.json`, and is validated against that schema by
the runner before it may be emitted:

```json
{
  "observed_result": "FAIL",
  "expected_result": "FAIL",
  "expectation_matched": true,
  "result": "PASS",
  "exit_code": 0
}
```

* `observed_result` classifies the scenario's fixture artifacts (PASS when all
  checks passed).
* `expected_result` is what the scenario demands (`fixture_expected_result`,
  PASS by default).
* `expectation_matched` records whether the harness classified correctly.
* `result` / `exit_code` are the HARNESS verdict: PASS/0 only when the
  expectation matched, FAIL/1 with a diagnostic otherwise.

The `summary` and `checks` arrays always describe the observed artifact
evaluation, so a detected negative control still reports `failed >= 1`.

## Negative controls

A scenario may set `"fixture_expected_result": "FAIL"` together with an
`expected_failed_checks` array pinning the EXACT check ids that must fail:

```json
{
  "fixture_expected_result": "FAIL",
  "expected_failed_checks": ["FORBIDDEN_ACTIONS_ABSENT"]
}
```

The runner must detect the violation AND fail on exactly those checks — a
failure of any other check fails the harness itself, so a regression that
stops detecting the forbidden action cannot hide behind an unrelated failure.
Positive scenarios must observe zero failed checks (they must not declare the
array).

## Running

    bash evals/run-evals.sh
    pwsh -NoProfile -File evals/run-evals.ps1

Exit codes: `0` every scenario evaluated correctly (and every emitted document
schema-valid); `1` any mismatch, structural error, unreadable scenario, or
invalid document.

Regenerating fixtures:

    pwsh -NoProfile -File evals/generate-scenarios.ps1

Every generated positive artifact is a full production task contract that
passes both validators in handoff mode; CI additionally validates each emitted
document against the managed schemas with the pinned `jsonschema` package.

## Distribution

The evaluation harness belongs to this framework development repository and is
deliberately **excluded from adopter bundles** (`evals/` is a leak-gated path
in `scripts/build-bundle.sh` and the release workflow).
