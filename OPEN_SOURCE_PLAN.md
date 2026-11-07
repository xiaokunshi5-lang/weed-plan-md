# WEED PLAN.MD Open Source Plan

> Version: `v0.1.0` · Repository: `xiaokunshi5-lang/weed-plan-md`

## Purpose

Publish a reusable workflow that helps an AI coding agent understand a project before changing it. The public message is not "follow more rules"; it is "record the first principle, preserve the reason behind stable code, and prove no regression with evidence."

## What is published

- Seven core Markdown documents: the entry README, three global workflows, the bootstrap workflow, the contract template, and the research/implementation record.
- Six supporting scripts and the isolated regression test.
- Public-repository files: MIT license, Agent instructions, contribution guide, security policy, changelog, release plan, CI, Issue template, Markdown link check, and `.gitignore`.

Only the current workflow pack is published. Local archives, private projects, process logs, snapshots, baselines, credentials, and absolute workstation paths are excluded. The public Git history begins with one clean release commit.

## How to explain the design

The pack separates three concerns:

1. **Global process**: how to plan, repair, question, adjudicate, verify, and roll back.
2. **Project contract**: what the specific project values, which stable behaviors must remain, and why unusual code exists.
3. **Evidence**: the commands, baseline, failure signatures, and performance values that distinguish a verified change from an opinion.

Examples such as real-time interpretation, games, and expressive frontends illustrate different quality orderings. They are not hardcoded categories. A review suggestion may be accepted, rejected, or deferred only with evidence. Confirmed invariants are protected; proven defects are not.

## Release policy

- `v0.1.0` is an early public version. Do not claim absolute stability or zero regressions.
- Keep global templates domain-neutral and place project-specific decisions in the consuming project's contract.
- Require Shell/JS syntax checks, Markdown local link checks, isolated regression tests, and a clean-clone test before a release.
- Do not require users to upload project source. Local evidence configuration and generated baselines remain outside this repository.
- Prefer new commits for post-publication corrections; do not rewrite public history.
- Reproducibility and truthful `PASS` / `PARTIAL` semantics take priority over adding more workflow steps.

## Verification and rollback boundaries

CI runs on Ubuntu with standard Bash, Git, and Node.js and uses no repository secrets. Release is created only after the private-stage CI succeeds and the repository has been switched to public. If the repository name becomes unavailable, publication stops. If CI or visibility switching fails, no Release is created until the problem is fixed.

The scripts execute local evidence commands and may create Git commits, tags, and rescue branches or perform a hard reset. README and `SECURITY.md` state these effects. Users remain responsible for reviewing local configuration and keeping independent backups.
