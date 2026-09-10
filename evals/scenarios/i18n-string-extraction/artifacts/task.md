# TASK-EVAL: i18n-string-extraction

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Approval gates

- [x] AG-1: Approved by Localization Lead on 2026-08-24

## Acceptance criteria

- AC-1: All hardcoded user-facing strings are captured in en.json.
- AC-2: Pseudo-localization test passes with no layout overflow.
- AC-3: RTL layout renders correctly for the extracted strings.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | extraction-output: 14 new keys extracted and mapped to en.json | passed |
| AC-2 | pseudo-localization-results: layout stable under pseudo-locales | passed |
| AC-3 | rtl-layout-check: extracted strings render correctly in RTL | passed |

## Context modules

- i18n v1 loaded — hardcoded strings extracted from the settings page

## Skills

- verification-triage v1 invoked — extraction output triaged for missing keys

## Verification

### Baseline

- Settings page hardcodes 14 user-facing strings; pseudo-locales trigger overflow.

### Final

- Settings page zero hardcoded strings; pseudo-locales render cleanly.

## Files changed

- `src/pages/Settings.tsx`
- `src/locales/en.json`

## Remaining risks

- None identified.
