# Security Policy

## Supported versions

| Version | Supported |
| :------ | :-------- |
| Latest 1.x patch release | Yes |
| Older 1.x releases | Upgrade required |
| Pre-1.0 | No |

Security fixes are delivered through the latest 1.x patch release. Older 1.x
releases should upgrade to the current version.

## Reporting a vulnerability

Do **not** open a public issue for a security vulnerability. Report it
privately to the maintainers via GitHub's private vulnerability reporting:

- Go to https://github.com/tecruz/agentic-workflow
- **Security → Report a vulnerability**

Please include:

- the affected files and version
- a description of the vulnerability and its impact
- steps to reproduce or a proof of concept

We aim to acknowledge reports within 5 business days and to publish a fix and
advisory once a patch is available.

## Security notes for adopters

- The installers write files into the target project and record SHA-256
  checksums in `.agentic/install-manifest.tsv`; they never execute or evaluate
  target-project content.
- `.agentic/checks.tsv` is project-owned. Only adopt a `checks.tsv` from a
  source you trust — the verifier executes the commands listed in it.
- Do not commit secrets, API keys, or credentials. The protocol's git
  conventions and rules require secret hygiene; treat any secret found in a
  repository as compromised and rotate it.