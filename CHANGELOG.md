# Changelog

All notable changes to WEED PLAN.MD are documented here. This project uses semantic versioning for its public releases.

## [Unreleased]

### Added

- A purpose-based classification map with a self-contained drag-and-drop pack for starting a new project.
- Separate entry points for maintenance tests, open-source governance, research records, and GitHub automation.

### Fixed

- Markdown link checks now resolve local links relative to the document that contains them.

## [0.1.0] - 2026-11-07

Initial public release.

### Added

- Project-aware bootstrap that creates a `DRAFT` contract, asks one high-impact question at a time, and waits for user confirmation.
- A contract template for first principles, ordered quality goals, core paths, design intent, protected behavior, and evidence commands.
- Trusted Git baseline capture for test failure signatures, core regression, smoke checks, static checks, and performance values.
- Watchdog gate with contract and baseline integrity checks, explicit `PARTIAL` reporting, and review-suggestion adjudication.
- Minimal fix-attempt accounting, rollback tooling, and an optional opt-in Web Audio UI kit.
- Planning, repair, and UI workflows that remain global while consuming a project-specific contract.
- Isolated regression tests, Markdown link checks, and a no-secret GitHub Actions workflow.
- MIT license, contribution guidance, security policy, and public-release documentation.

### Known boundaries

- Trusted baseline evidence requires a Git repository.
- Shell scripts and regression tests are validated on Unix-like systems; Windows is not yet in the test matrix.
- The workflow reduces regression risk but does not guarantee correctness or replace representative tests and human review.
