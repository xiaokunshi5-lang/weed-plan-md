# WEED PLAN.MD Agent Instructions

This repository publishes reusable Markdown workflows and their supporting scripts.

- Keep the three global workflows project-agnostic. Put a consuming project's first principle, quality ordering, and protected behavior in that project's `.agents/PROJECT_CONTRACT.md`.
- Treat existing designs as intentional until evidence shows otherwise. A suggestion from a reviewer, watchdog, or linter is a hypothesis, not a command.
- Preserve the evidence semantics: a missing or unverified check yields `PARTIAL`, never `PASS`.
- Run `bash -n scripts/*.sh`, `node --input-type=module --check < scripts/ui_tactile_kit.js`, `bash tests/check_markdown_links.sh`, and `bash tests/test_project_aware_workflow.sh` before proposing a release.
- Do not commit local `.agents/` state, generated baselines, snapshots, credentials, or private project files.
- Update `CHANGELOG.md` for user-visible changes and keep links in README valid.

For task execution inside a consuming project, read that project's confirmed contract before changing code.
