# Contributing to WEED PLAN.MD

WEED PLAN.MD is a documentation-first workflow pack. A good change makes it easier for an agent to understand project intent, protects a stable behavior with evidence, or removes ambiguity without adding a fixed domain bias.

## Before proposing a change

1. Read [`README.md`](./README.md) and the workflow document affected by your change.
2. Open or find a GitHub Issue that describes a reproducible failure, a misleading instruction, or a concrete adoption problem.
3. Keep one pull request focused on one behavior. Do not silently rewrite the project's first-principle rules or evidence gates.
4. If you change a script, add or update an isolated assertion in [`tests/test_project_aware_workflow.sh`](./tests/test_project_aware_workflow.sh).
5. If you add a document, link it from README and update the local link checker if needed.
6. If you copy code, CSS, or media from another source, verify its current license and preserve required notices.

## Local verification

```bash
bash -n scripts/*.sh
node --input-type=module --check < scripts/ui_tactile_kit.js
bash tests/check_markdown_links.sh
bash tests/test_project_aware_workflow.sh
```

Tests must create their own temporary fixtures and must not modify a contributor's project files.

## Pull request checklist

- [ ] The proposal explains which project context or evidence problem it solves.
- [ ] Global templates remain domain-neutral.
- [ ] `PASS`, `PARTIAL`, `DRAFT`, `CONFIRMED`, and rollback semantics remain intact.
- [ ] All local checks pass and all changed links resolve.
- [ ] `CHANGELOG.md` is updated for user-visible changes.
- [ ] No credentials, local paths, private project files, or generated baselines are included.

Issues and pull requests are expected to stay civil and specific. Maintainers may ask for a minimal reproduction or defer changes that broaden the project's scope without evidence.
