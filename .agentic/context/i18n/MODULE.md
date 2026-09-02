# Module: i18n

## ID

i18n

## Version

1

## Minimum risk profile

standard

## Load when

- New user-facing strings added
- Existing user-facing strings modified or removed
- Locale files added, modified, or reorganized
- Date/time/number/currency formatting changes
- Pluralization rules or ICU message format changes
- RTL/LTR layout direction changes
- New locale/language support added
- Translation key structure changes

## Required context

- Internationalization framework in use (i18next, react-intl, FormatJS, etc.)
- Supported locales list and fallback chain
- Translation extraction and build process
- Translation management workflow (Crowdin, Phrase, Lokalise, etc.)
- Pluralization rules for supported languages
- RTL language support status

## Approval gates

- Translation completeness check required before merging string changes
- Pseudo-localization test should pass for new components
- RTL layout review for layout-affecting changes

## Required evidence

- Extraction script output showing new/updated keys captured
- Translation completeness report for all supported locales
- Pseudo-localization test results (no hardcoded strings, layout overflow)
- RTL layout screenshots for layout-affecting changes
- ICU message format validation for plural/gender/select formats

## Prohibited shortcuts

- Do not hardcode user-facing strings in code
- Do not concatenate strings for user display (use ICU message format)
- Do not add new locales without updating the supported locales list
- Do not skip pseudo-localization for new user-facing components
- Do not assume English word order in concatenated strings