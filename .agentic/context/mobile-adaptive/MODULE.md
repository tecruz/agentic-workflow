# Module: mobile-adaptive

## ID

mobile-adaptive

## Version

1

## Minimum risk profile

standard

## Load when

- Responsive breakpoints or layout changes
- Touch target sizing or spacing modifications
- Viewport-dependent behavior changes
- New device form factor support (foldables, tablets, desktop PWA)
- Orientation-dependent behavior changes
- Touch/gesture interaction modifications
- Safe area / notch / display cutout handling
- PWA installability or native-like behavior changes

## Required context

- Responsive design system and breakpoint definitions
- Supported device classes (mobile, tablet, foldable, desktop)
- Touch target minimum size requirements (44x44dp minimum)
- Safe area handling strategy
- PWA manifest and installability criteria
- Device testing matrix and device lab access

## Approval gates

- Responsive layout review across all supported breakpoints
- Touch target size compliance check
- Safe area handling verification for notched devices
- PWA installability audit for manifest/service worker changes

## Required evidence

- Responsive layout screenshots across all breakpoints (320px, 768px, 1024px, 1440px+)
- Touch target size audit results (automated + manual)
- Safe area handling screenshots on notched devices
- PWA installability audit (Lighthouse PWA score)
- Orientation change behavior test results
- Foldable device posture change handling (if applicable)

## Prohibited shortcuts

- Do not use fixed pixel widths for responsive containers
- Do not reduce touch targets below 44x44dp minimum
- Do not ignore safe area insets for edge-to-edge layouts
- Do not assume single orientation for mobile views
- Do not disable responsive behavior for "desktop-only" features without testing