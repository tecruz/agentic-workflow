# Module: accessibility

## ID

accessibility

## Version

1

## Minimum risk profile

standard

## Load when

- UI components or user-facing views modified
- Color contrast, typography, or spacing changes
- Interactive element behavior changes (focus, keyboard navigation)
- ARIA attributes or semantic HTML changes
- Screen reader compatibility concerns
- Keyboard shortcut or focus management changes
- New user-facing components or screens added

## Required context

- Accessibility standards target (WCAG 2.1/2.2 AA/AAA)
- Existing accessibility test suite and tools (axe, Lighthouse, etc.)
- Design system accessibility documentation
- Screen reader testing environment
- Keyboard navigation test procedures

## Approval gates

- Accessibility review required for all user-facing changes
- Automated axe/Lighthouse CI gate must pass
- Screen reader testing required for new interactive components

## Required evidence

- Axe-core or Lighthouse accessibility audit results
- Keyboard navigation test results (tab order, focus visibility, focus trapping)
- Screen reader test results (NVDA, JAWS, VoiceOver, TalkBack)
- Color contrast ratio measurements for changed elements
- Focus indicator visibility evidence

## Prohibited shortcuts

- Do not disable accessibility tests to make CI pass
- Do not skip screen reader testing for "minor" UI changes
- Do not use color-only indicators without text alternatives
- Do not remove focus indicators for aesthetic reasons