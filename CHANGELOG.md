# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Open-source project files: MIT license, contributing guide, code of conduct, security policy, issue / PR templates.
- GitHub Actions CI: core tests on Linux and macOS, iOS app build.
- Architecture notes (`docs/ARCHITECTURE.md`) and roadmap.

### Fixed
- `AppStore.defaultFileURL` is now `nonisolated` so it can be used as a default argument.

## [0.1.0] – 2026-10-08

### Added
- Routine-free workout logging: pick muscle groups, exercises are carried over from the last session of each group with last weight × reps shown per set.
- Per-set quality marks (↑ → ↓) kept separate from load / rep changes.
- 147-entry equipment library (Nautilus, PRIME plate-loaded with 1/2/3 horn positions and selectorized, Atlantis, Hammer Strength, free weights, cables) and custom equipment.
- Single-arm / both-arms toggle for back exercises and arm / shoulder cable exercises, with separate rest times.
- Rest timer next to the set, on the Lock Screen and Dynamic Island (Live Activity), with a notification when it ends.
- Chinese voice logging that survives pauses and produces an editable confirmation card.
- Weekly working-set volume for 7 muscle groups against a 10–20 set target, body map, per-set drill-down and 6-week trend.
- Editable history table (sets, date, title, equipment), notebook-style side-by-side comparison, discard workout, local storage and JSON backup / merge.
- 36 unit tests for the core library.
