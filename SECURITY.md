# Security Policy

## Supported versions

Security fixes are considered for the latest published release.

| Version | Supported |
| :--- | :--- |
| `v0.1.x` | Yes |
| Earlier public versions | No |

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository, or contact a maintainer through a private channel. Do not post credentials, exploit details, or private project data in a public Issue.

Include the affected file or script, a minimal reproduction, the observed behavior, the expected behavior, and the environment. If the report concerns a workflow script that executes local commands, explain which configuration values are required.

## What is in scope

- A gate that can report `PASS` without its required evidence.
- Tampering with a confirmed contract, trusted baseline, test asset, or failure signature.
- A rollback path that can unexpectedly discard tracked work without a rescue branch.
- Unintended disclosure of local configuration, secrets, or private project paths by a published script.

## What is expected of users

The scripts in this repository execute commands supplied in a local `.agents/workflow.config`. Treat that file as executable configuration: review it, avoid secrets in commands or logs, and test scripts in a disposable copy first. `rollback.sh` can create Git branches and commits, perform a hard reset, clean untracked files, or restore directory snapshots. Use `--dry-run` and keep independent backups.

This project provides workflow rules and evidence checks. It is not a sandbox, an antivirus product, or a guarantee that a configured command is safe.
