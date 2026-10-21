# Security Policy

## Supported versions

Only the latest release on `main` receives fixes.

## Data handled by the app

LiftNote stores all workout data **locally on the device** (Application Support, file protection *until first user authentication*). It has no server, account system, analytics or third-party SDKs. Speech recognition uses Apple's `Speech` framework and prefers on-device recognition when the device supports it. Backups are plain JSON files that the user explicitly exports.

## Reporting a vulnerability

Please **do not** open a public issue. Use [GitHub private vulnerability reporting](https://github.com/richardB520/liftnote_1/security/advisories/new) with steps to reproduce. You can expect an acknowledgement within 7 days.
