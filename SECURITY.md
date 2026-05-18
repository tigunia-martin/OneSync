# Security Policy

## Reporting a vulnerability

If you discover a security issue in OneSync, **please do not open a public issue**. Instead, report it privately via GitHub's [security advisory form](../../security/advisories/new). I'll acknowledge within a few working days.

Please include:
- A description of the issue and its potential impact
- Steps to reproduce (or a proof-of-concept if you have one)
- Affected versions
- Any suggested mitigation

## What's in scope

- Anything that lets an unauthenticated party access another user's files via the OneSync client
- Anything that lets a OneSync user escalate to permissions they don't have on the underlying SharePoint / OneDrive
- Anything that exposes credentials (tokens, refresh tokens, tenant IDs from logs) outside the local machine
- Anything that crashes Windows Explorer or causes data loss

## What's out of scope

- Issues in the Dokan driver itself — report those upstream at https://github.com/dokan-dev/dokany
- Issues in Microsoft Graph or MSAL — report to Microsoft via msrc.microsoft.com
- Local privilege escalation that requires the attacker to already be a local administrator
- Denial of service requiring the attacker to have valid credentials and disk-write access

## Disclosure

I'll work with you on a disclosure timeline that balances giving users time to update against publishing the fix. Expect 60–90 days as the default.
