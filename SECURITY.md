# Security Policy

We take security issues seriously. Please report vulnerabilities responsibly and avoid opening public issues for security reports.

## Supported versions

Security fixes are provided for the latest released version.

If no releases are published yet, security fixes are provided for the `main` branch, and users should pin to a known-good commit SHA.

## Scope

In scope:
- git-hex tool implementations under `tools/` and supporting libraries under `lib/`
- launcher scripts (`git-hex.sh`, `git-hex-env.sh`)
- plugin bundle metadata under `.claude-plugin/`
- release artifacts published in this repository (when present)

Out of scope:
- vulnerabilities in user repositories or infrastructure
- third-party dependencies and tools (e.g., `git`, `bash`, `jq/gojq`), except where git-hex interacts with them in a vulnerable way
  (please still report issues if you believe git-hex is using them unsafely)

## Reporting

- Prefer a private report via GitHub Security Advisories on this repository.
- If you cannot use advisories, contact the maintainer via the email listed on the GitHub profile.

Please include:
- A description of the issue and potential impact.
- Steps to reproduce or a proof of concept, if available.
- Any suggested fixes or mitigations.

## Response expectations

- Acknowledge within **3 business days**.
- Provide a status update within **7 business days** (or sooner when possible).
- Coordinate on a fix and disclosure timeline before public disclosure.

We will acknowledge receipt, investigate, and work with you on remediation before public disclosure.
