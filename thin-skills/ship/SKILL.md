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
- `review: <verdict>` — the `review` verdict, if it ran; one line in the PR body. "Request changes" → ask before shipping; with `--yes`, stop.
- `qa-need: <none | qa | by hand, with reasons>` — from `review`, if it ran. Name outstanding checks in the PR body and report. For `by hand`, include 1–3 steps with expected results. If still outstanding, auto opens a draft (an existing PR is left as-is and reported); manual mode shows the checks at confirmation.
- `qa: <verdict>` — the `qa` verdict, if QA ran; one line in the PR body. Anything other than PASS or "no UI to check" → ask before shipping; with `--yes`, stop.

## Non-negotiables

1. **Never hang**: git runs with `GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" GIT_EDITOR=true`.
2. **Never ship red.** Only failures verified as pre-existing (the same failures on `origin/<base>`) may ship. List them in the report and PR body under **No new failures; known failures remain**, never as green. The same failures means the same individual tests, lint errors, or type errors with the same message, compared one by one. Any additional or different failure is caused by this change until proven otherwise; if the output can't be compared (for example the command aborted early), it is not pre-existing. A command that could not run is not a pass.
3. **Signed commits** (`commit.gpgsign` = `true`) and something to commit or merge: do it only if `signing-ok` is yes or the user confirms the key is unlocked. Otherwise print the exact commands and stop.
4. Never use `--no-verify`, `--no-gpg-sign`, `--force`, or history rewrites. One PR per branch.
5. No labels, assignees, reviewers, or extra comments unless asked. Never write to issues.
6. **CI: at most one fix attempt**, never a loop. No reruns to get lucky, no skipping or disabling checks.

## Evidence before each push

Review and QA verdicts apply only to the published content they identify. For a clean tree, record the commit SHA and its Git tree ID; for staged work, use the index tree ID (`git write-tree`) only if it matches the work that was actually checked. Matching tree IDs let a plain commit carry staged evidence forward. Missing identity or a mismatched tree means `STALE / not verified for this version`, never `approve` or `PASS` for this version.

`build --auto` passes the checks chosen at the start and their recorded identities. Check this after merging base, and again before pushing a CI fix. In auto mode, if a review or QA check chosen for this run is missing or stale, rerun it on the final tree or stop without pushing that version. In manual mode, disclose stale evidence before publication, update the proposed PR body, and ask for confirmation if the merge changed what the user confirmed. Never use a local gate pass as a substitute for review or QA.

## Workflow

1. **Target.** It must be a branch other than `<base>` (from the `## Workflow` section of `AGENTS.md`/`CLAUDE.md`). Run `git fetch origin <base>`; if it fails, stop. If the branch has an open PR, use its base; a fork PR → stop. Show `git status --short` and `git diff --stat origin/<base>`. If there's nothing to commit or push, stop. Unexpected files, secrets, `.env` files, or build output → ask which files belong; with `--yes`, stop.
2. **Gate.** Run every validation command, in order. Every time the gate runs, inspect its staged, unstaged and untracked outputs. Include intended regenerated files in the diff and rerun downstream checks on the final content (the full gate if earlier results no longer apply). Stop on unexpected or repeatedly changing outputs; never stage or discard them silently. If a generated change alters the diff that was confirmed, obtain a new confirmation in manual mode; in auto mode, stop on unapproved scope and apply the evidence rule before any push.
3. **Confirm** (unless `--yes`): show the files to commit, the commit message, PR title, and PR body, and whether `origin/<base>` will be merged in, and ask "Publish this branch and open the PR as shown?"
4. **Commit** the uncommitted changes as one commit: `git add -- <the reviewed files> && git commit -m "<type>(<area>): <summary>"`. Keep existing commits. A failing hook is a problem to fix or report.
5. **Update from base.** Fetch again. If `origin/<base>` is not an ancestor of `HEAD`, run `git merge --no-edit origin/<base>` (the signing rule applies). Conflict → `git merge --abort`, report the files, stop with `Next: build <worktree>`. Clean → rerun the whole gate; red → stop. Never rebase.
6. **Push:** `git push -u origin <branch>`. On failure, report it and stop.
7. **PR.** If one already exists (`gh pr list --head <branch>`), the push updated it; report its link. Otherwise run `gh pr create --base <base> --title "<type>(<area>): <summary>" --body-file <file> [--draft]`.
8. **CI** (with `--watch-ci` or `--yes`): see below.
9. **Report:** the PR link, the commits included, the CI result, and `cleanup after merge: git worktree remove <path>`.

## Waiting for CI

1. **Wait** with `gh pr checks <n> --watch --fail-fast`, bounded by `CI wait: <minutes>` from the `## Workflow` section (default 30), using the harness's command timeout or a background run. Checks can take a minute to appear; "no checks reported" right after the push means wait and retry, up to 3 times. Still none → `CI: none configured`.
2. **Completeness.** A short check list is not a green one: a queued run adds no checks until its jobs start. Before reporting green, run `gh run list --commit <pushed SHA> --json name,status,conclusion --limit 100`; a run that isn't `completed` counts as still running, and one that failed or was cancelled counts as red (a newer run of the same workflow replaces it). Wait within the same time limit, then read `gh pr checks <n>` again. If runs can't be read, report `CI: unverified`, not green.
3. **Green** (every check and run finished, none red) → report. **Still running** at the time limit → report `CI: pending` with the link and stop.
4. **Red** → read the failing logs (`gh run view <run-id> --log-failed`) and decide:
   - **Caused by this change, with a clear fix** → without `--yes`, propose the fix and stop. With `--yes`, fix it in the worktree, rerun the local gate, stage by path, commit (`fix(ci): <summary>`; the signing rule applies), apply the evidence rule above, then push and wait once more only if allowed. Red again → stop.
   - **Not caused by this change** (the same failure also appears on `<base>`, or it's infrastructure, a flaky test, or an expired secret) → don't touch it. Report it and add it to `<main>/.ai/findings.md` (`## <date> · <title>`, `Source: ship <branch>`, `Where:`, `What:`, `Why it matters:`, `Status: open`). `<main>` is the parent of `git rev-parse --path-format=absolute --git-common-dir`; add the path to `<main>/.git/info/exclude` if missing.
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
Still to check by hand: print the exported report; printing can't be judged by browser QA.
```

Not: "Implements step 2 of the plan, see Q1."
