---
name: ship
description: "Publish finished work from a build worktree — validation gate, commit, push, one GitHub PR without labels or extra comments; in auto mode, waits for CI and makes at most one fix attempt. Only on explicit request. Triggers: ship it, commit and open a PR, push this worktree, publish the branch, open PR, wypchnij, zrób PR, wyślij to, opublikuj zmiany."
---

# Ship

Turn a finished worktree into one PR. Running this skill is the user's consent to publish.

## Arguments

- `<worktree path>` — defaults to the current directory.
- `--yes` — skip the confirmation (passed by `build --auto`).
- `signing-ok` — the answer `build --auto` recorded about commit signing; when present, don't ask again.
- `--draft` — open the PR as a draft.
- `--watch-ci` — wait for CI after opening the PR. On by default with `--yes`.
- `qa: <verdict>` — the `qa` verdict, if QA ran; one line in the PR body.

## Non-negotiables

1. **Never hang**: git runs with `GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" GIT_EDITOR=true`.
2. **Never ship red.** Only failures verified as pre-existing (the same command also fails on `origin/<base>`) may ship, and they're listed in the PR body.
3. **Signed commits** (`commit.gpgsign` = `true`) with uncommitted changes: commit only if `signing-ok` is yes or the user confirms the key is unlocked. Otherwise print the exact commands and stop.
4. Never use `--no-verify`, `--no-gpg-sign`, `--force`, or history rewrites. One PR per branch.
5. No labels, assignees, reviewers, or extra comments unless asked. Never write to issues.
6. **CI: at most one fix attempt**, never a loop. No reruns to get lucky, no skipping or disabling checks.

## Workflow

1. **Target.** It must be a branch other than `<base>` (from the `## Workflow` section of `AGENTS.md`/`CLAUDE.md`). Show `git status --short` and `git diff --stat origin/<base>`. If there's nothing to commit or push, stop.
2. **Gate.** Run every validation command, in order.
3. **Confirm** (unless `--yes`): show the commit message, PR title, and PR body, and ask "Publish this branch and open the PR as shown?"
4. **Commit** the uncommitted changes as one commit: `git add -A && git commit -m "<type>(<area>): <summary>"`. Keep existing commits. A failing hook is a problem to fix or report.
5. **Push:** `git push -u origin <branch>`. On failure, report it and stop.
6. **PR.** If one already exists (`gh pr list --head <branch>`), the push updated it; report its link. Otherwise run `gh pr create --base <base> --title "<type>(<area>): <summary>" --body-file <file> [--draft]`.
7. **CI** (with `--watch-ci` or `--yes`): see below.
8. **Report:** the PR link, the commits included, the CI result, and `cleanup after merge: git worktree remove <path>`.

## Waiting for CI

1. **Wait** with `gh pr checks <n> --watch --fail-fast`, bounded by `CI wait: <minutes>` from the `## Workflow` section (default 30), using the harness's command timeout or a background run. Checks can take a minute to appear; "no checks reported" right after the push means wait and retry, up to 3 times. Still none → `CI: none configured`.
2. **Green** → report. **Still running** at the time limit → report `CI: pending` with the link and stop.
3. **Red** → read the failing logs (`gh run view <run-id> --log-failed`) and decide:
   - **Caused by this change, with a clear fix** → without `--yes`, propose the fix and stop. With `--yes`, fix it in the worktree, rerun the local gate, commit (`fix(ci): <summary>`; the signing rule applies), push, and wait once more. Red again → stop.
   - **Not caused by this change** (it also fails on `<base>`, or it's infrastructure, a flaky test, or an expired secret) → don't touch it. Report it and add it to `<main>/.ai/findings.md` (`Source: ship <branch>`).
   - **Unclear** → stop and report.

   Example report after stopping:

   > CI: red — **e2e / checkout** fails ([log](https://github.com/acme/app/actions/runs/123456)). Cause: the new required "VAT ID" field has no value in the e2e fixture, so the checkout form can't submit. This change caused it, but the fix belongs in shared fixtures, so I didn't touch it. Proposed fix: add a VAT ID to [checkout.fixture.ts](https://github.com/acme/app/blob/feat/vat-id/e2e/fixtures/checkout.fixture.ts#L14).

   Stopping leaves the PR open and red. The report names the failing check, links its log, and gives the cause in one sentence plus the proposed fix. It never says the PR is ready.

## PR body

Short, for a reader who didn't follow the work, with links that resolve on GitHub:

```markdown
Exported reports now include dates before 1970; they were previously left empty.

- Spec: [2026-11-20-legacy-dates.md](https://github.com/acme/app/blob/fix/legacy-dates/.ai/specs/2026-11-20-legacy-dates.md)
- Fix: [format.ts](https://github.com/acme/app/blob/fix/legacy-dates/src/export/format.ts#L18) no longer drops negative (pre-1970) timestamps.
- Closes #231

Validation: lint ✅ · typecheck ✅ · test ✅
Review: approved — no blockers; one minor naming note left as is.
QA: PASS — export checked in the browser for an account with old orders and one with none.
```

Not: "Implements step 2 of the plan, see Q1."
