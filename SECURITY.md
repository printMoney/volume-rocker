# Security Policy

## Supported versions

Only the latest release receives security fixes.

## Reporting a vulnerability

Please **do not** open a public issue. Instead, report it privately through
[GitHub Security Advisories](https://github.com/printMoney/volume-rocker/security/advisories/new).

Include what you found, how to reproduce it, and the impact you expect. You'll get a reply within a week, and we'll coordinate a fix and disclosure with you.

## Scope

Volume Rocker processes audio locally and only connects to the internet to check for updates (via Sparkle, using EdDSA-signed updates over HTTPS). Of particular interest:

- anything that could make the app record, store or transmit audio,
- update-mechanism weaknesses,
- privilege escalation via the app.
