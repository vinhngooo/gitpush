# GitHub Push Tool Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, task by task.

**Goal:** Deliver the approved folder + GitHub URL + Run Windows application.
**Architecture:** A reusable PowerShell Git core, a file-based worker, and a Windows Forms front end. A separate process performs Git operations while the UI polls progress.
**Tech Stack:** Windows PowerShell 5.1, Windows Forms, Git for Windows / Credential Manager.
**Spec:** ../specs/2026-10-25-github-push-design.md

## Global Constraints
- Vietnamese GUI; no dependency installation; no force push or automatic history rewrite.
- Preserve current branch, gitignore rules, and credentials in the Git credential store.
- Validate before staging; changing origin requires a dialog.
- No production repository push during development.

## Review Focus
- Quoted, Unicode, spaced paths and command injection attempts must not execute shell text.
- Picking a nested folder must not stage a parent repository.
- Divergent history, deleted files, no-change runs and existing commits must retain correct semantics.
- Tracked secrets, extra push destinations and active merge/rebase must stop before staging/pushing.
- GUI must remain responsive, retain settings and report worker failure.

### Task 1: Git engine
Files: Core.ps1, tests/Run-Tests.ps1.
Produces: ConvertTo-GitHubRepository, Invoke-GitCommand, Get-RepositoryState, Invoke-ProjectPush.
- [x] Write behavioral tests with real disposable local repositories and explicit refusal cases.
- [x] Run tests: observed failure because core was absent.
- [x] Implement safe process argument handling, validation, initialization, ignore protection, commit and push flow.
- [x] Run Windows PowerShell tests: initial 14 cases passed; supplemental regression tests added for final verification.

### Task 2: Worker + UI
Files: Worker.ps1, App.ps1, Mo-GitHub-Push.cmd.
Consumes: core interfaces; worker request/result JSON and UTF-8 progress log.
- [x] Implement responsive GUI, persisted settings, folder picker, login and author dialog, origin confirmation and process worker.
- [x] Add real worker-process integration test and form rendering smoke test.
- [x] Run worker test and GUI smoke capture: passed, inspected rendered image.

### Task 3: Deliver
Files: README.md, tests artifacts outside release, portable ZIP.
- [x] Fresh reviewer checks sources against spec; fixed destination rewrites and HTTPS normalization. Added bounded output drain and independent log-read recovery; shipped .gitignore excludes runtime state.
- [x] Run complete tests and smoke render under Windows PowerShell 5.1: 17/17 Git tests, worker process error contract, GUI rendering and source parser checks passed.
- [x] Package release, verify archive contents, create workspace shortcut and open application for delivery.

## Execution record
- Standalone new folder; parent directory is not a Git repository. No existing project files or branch are modified. Worktree/commit helpers do not apply to this non-repository deliverable.
- User approved implementation; continue inline without another approval round.
- Ruling: conservatively reject matching Git URL rewrite rules, including equivalent transports, to keep the entered HTTPS destination authoritative. Users with deliberate rewrites must adjust them before using this tool.
- Review: no external push/login performed. Read-only preflight establishes repository access; GitHub enforces write permission at push. Existing branch creation and trusted hooks/signing remain standard Git behavior. Secret detection is limited to documented filename patterns.
- Debugging evidence: separate stdout from stderr because sandbox Git ignore warnings otherwise contaminated parsed results. An inherited repository environment and URL rewrites were reproduced in failing tests before their fixes. Output-drain timeout was reproduced with a background Git alias child.
- Review findings resolved; no deferred issues. Source/runtime files preserved in the standalone folder; no Git merge or PR is applicable.
