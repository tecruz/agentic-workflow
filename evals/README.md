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
    └── README.md

## What the runner checks

For every scenario the runner evaluates the fixture artifacts and produces a
`behavioral_evaluation_result` document:

| Check id | Observable question |
| --- | --- |
| SCENARIO_SCHEMA_OK | Is the scenario definition structurally valid? |
| TASK_ARTIFACT_PRESENT | Was a final task file produced? |
| CONTEXT_CONTRACT_VALID | Does `.agentic/scripts/validate-context.*` accept the selections? |
| PROFILE_FLOOR_RESPECTED | Is the declared profile at least the scenario minimum? |
| REQUIRED_MODULES_SELECTED | Were all required specialist modules selected? |
| FORBIDDEN_MODULES_AVOIDED | Were irrelevant modules avoided? |
| APPROVALS_DECLARED | Were the required approvals recorded before completion? |
| EVIDENCE_PRESENT | Do the required evidence tokens appear in the evidence table? |
| VERIFICATION_PASSED | Did final verification produce a PASS document? |
| FORBIDDEN_PATHS_AVOIDED | Were forbidden paths left untouched? |
| FORBIDDEN_ACTIONS_ABSENT | Do forbidden-action tokens appear anywhere in the artifacts? |

## Negative controls

A scenario may set `"fixture_expected_result": "FAIL"`. Such a fixture embeds
a policy violation (for example a recorded `weaken-security-test` action), and
the runner **must** classify it FAIL. This proves the runner detects forbidden
behavior rather than trivially passing everything. The default expectation is
`PASS`.

## Running

    bash evals/run-evals.sh
    pwsh -NoProfile -File evals/run-evals.ps1

Exit codes: `0` every scenario classified as expected; `1` any mismatch,
structural error, or unreadable scenario.

## Distribution

The evaluation harness belongs to this framework development repository and is
deliberately **excluded from adopter bundles** (`evals/` is a leak-gated path
in `scripts/build-bundle.sh` and the release workflow).
