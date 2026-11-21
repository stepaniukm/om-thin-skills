# Audit of the SDLC in the open-mercato skills (`.agents/skills/`)

As of 2026-11-21. Source: the 75 `om-*` skills from `open-mercato/skills`.

## 1. Scale

| Metric | Value |
|---|---|
| Skills | 75 (including 8 variant aliases of fix-issue and implement-feature) |
| Files | ~660 (549 of them under `references/`) |
| Markdown text | **~600,000 words** (the `SKILL.md` files alone: ~110,000) |
| Claim protocol (`claim-pr.md`) | **~77,500 words in 27 copies, every copy different** (distinct md5 hashes) |
| `agentic-setup.md` + `rules.md` | 74 copies, ~90% of them divergent versions |
| Code | `harness.mjs` 130 KB, `dashboard.mjs` (merge buddy) 210 KB |
| Tracker descriptors | GitHub, GitLab, Forgejo, Linear, Jira — ~190 KB |
| Config keys (`.ai/agentic.config.json`) | ~70 (about 15 of them only for automerge) |

Takeaway: about **a third of the corpus is duplicated boilerplate** (claims, setup, rules), and the copies have drifted apart.

## 2. The SDLC these skills describe

The canonical flow is written down in the `SDLC.md` template (`om-setup-agent-pipeline/references/sdlc-template.md`):

```
Discovery → Intake → Triage → Claim → Design → Implement → PR → Review loop → QA → Merge → Post-merge
```

| Stage | What happens | Skills |
|---|---|---|
| **Setup (once)** | Detect the toolchain, write `.ai/agentic.config.json`, install a tracker descriptor, generate `SDLC.md`, `AGENTS.md`, `CODE_REVIEW.md`, and `BACKWARD_COMPATIBILITY.md`, create labels | `om-setup-agent-pipeline`, `om-setup-discovery-pipeline`, `om-setup-agent-harness`, `om-ux-setup` |
| **Discovery** | Talk the problem through, weigh alternatives (including building nothing), write a product brief, run synthetic users, make mockups | `om-brainstorm`, `om-discover`, `om-synthetic-users`, `om-mockup-prototype`, `om-app-spec-writing`, `om-gap-analysis` |
| **Intake** | File a tracker issue with SDLC labels and a Definition of Ready; turn a brief into a backlog | `om-prepare-issue`, `om-backlog`, `om-auto-manage-issues`, `om-auto-issue-triage` |
| **Spec** | Skeleton → open questions (a hard stop) → design → implementation plan in phases and steps | `om-spec-writing`, `om-auto-write-spec`, `om-pre-implement-spec`, `om-ux-shape`, `om-ux-design` |
| **Triage** | Is the bug real, still unfixed, and not taken by someone else? | `om-verify-in-repo` |
| **Claim** | An atomic lock: a git ref `refs/om-locks/*`, plus an `in-progress` label, plus a comment | built into ~27 skills |
| **Implement** | Bug: root cause → fix (minimal change plus a regression test). Feature: plan → phases with commits in a worktree | `om-root-cause`, `om-fix`, `om-auto-create-pr(-loop)`, `om-auto-implement-spec`, `om-implement-feature*`, `om-fix-issue*` |
| **PR** | Commit, push, open the PR, apply the full label set, plus a comment explaining the labels | `om-open-pr`, `om-check-and-commit` |
| **Review loop** | Code review with a validation gate, autofix, re-review until approved | `om-code-review`, `om-auto-review-pr`, `om-review-prs`, `om-auto-fix-pr`, `om-auto-continue-pr(-loop)`, `om-pr-autopilot` |
| **QA** | Browser checks and screenshots; `needs-qa` → `qa-approved`, pinned to a commit SHA | `om-auto-qa-pr`, `om-qa-buddy`, `om-prepare-test-env`, `om-integration-tests`, `om-ux-review-pr` |
| **Merge** | A readiness report, squash-merge, an automerge queue with three signals | `om-merge-buddy`, `om-approve-merge-pr`, `om-auto-merge-triage`, `om-auto-merge-buddy` |
| **Post-merge** | Close issues, file follow-ups, write the changelog, security reports, retros | `om-close-fixed-issues`, `om-followup-issue-from-pr`, `om-auto-update-changelog`, `om-auto-sec-report*`, `om-pipeline-retro` |

On top of that there is a meta layer outside the lifecycle: `om-help` (a router, which exists because without it nobody could pick the right skill), `om-harness`, `om-evolve-harness`, `om-judge-agent-session`, `om-share-this-session`, `om-create-skill`, `om-create-agents-md`, `om-ai-context-maintenance`, `om-framework-context`, `om-eject-and-customize`, `om-apply-upgrade-notes`, `om-troubleshooter`, `om-smart-test`, `om-figma-design-with-ds`, `om-auto-audit-dependencies`, and `om-auto-qa-scenarios`.

### Two parallel delivery families

1. **Publishing (`om-auto-*`).** Autonomous by default; ends with a ready, labeled PR. For a bug (`om-auto-fix-issue`):
   ```
   verify-in-repo → [worktree] → root-cause → fix (claim) → open-pr (commit, push, PR, labels, lock transfer)
     → auto-review-pr --autofix (loop) → auto-qa-pr (UI) → release lock → [optionally automerge]
   ```
   For a feature: `auto-write-spec` (a separate PR holding only the spec) → `auto-implement-spec` → `auto-create-pr` (the plan is committed first and a draft PR opens immediately) → review → QA.
2. **Staged-only (`om-fix-issue`, `om-implement-feature` + `om-harness`).** Never commits or pushes; leaves a staged diff for human review. Has the profiles `standard`, `optimized`, `multi`, `multi-optimized`, and `high-assurance`: worker models, review councils made of several models, packet leases, and hooks that block `git push`.

The staged-only family is the closest to a human-in-the-loop goal, but it carries a heavy multi-model runtime.

## 3. Hidden assumptions

| # | Assumption | Where it lives | Consequence for a small team |
|---|---|---|---|
| A1 | **Many agents and people work on the same repo at the same time** | the claim protocol in 27 skills | Huge overhead (locks as git refs, electing a "winner", `claim-reset`) with little value |
| A2 | **The tracker is the source of truth and the PR is the unit of progress** | almost every skill | You can't work locally without GitHub or GitLab; every step leaves comments |
| A3 | **Autonomy is the default**: "Autonomous run — no user in the loop" | the shared `rules.md`, also loaded by interactive skills (for example `om-check-and-commit`) | The agent makes decisions and "documents" them instead of asking |
| A4 | **The config exists, and if it doesn't, the agent creates it** | `agentic-setup.md` in 26 skills: "missing → run `om-setup-agent-pipeline` (… `--defaults` unattended)" | The first run of an ordinary skill can generate 5+ files and labels in the tracker |
| A5 | **Labels are a state machine** (pipeline, category, meta, priority, risk) | `SDLC.md`, `pr-finalize.md`, `verdict-and-labels.md` | Every PR gets about five labels and a comment justifying each one |
| A6 | **CI is mirrored locally** through `validation.commands` | every implementing skill and review | A good assumption, worth keeping |
| A7 | **Always an isolated worktree, with a fresh dependency install** | create-pr, fix-issue, review-pr | Slow and disk-hungry, but it keeps parallel agents apart |
| A8 | **Process artifacts live in the repo** (`.ai/runs/*.md`, `.ai/specs/briefs`, the plan as the first commit) | auto-create-pr, brainstorm | Repo clutter, which then needs its own skill to archive (`om-ai-context-maintenance`) |
| A9 | **Skills talk to each other through parsed text** (`Next:`, `PR: #n (link: …)`, `— PREVIOUS STEP (x) said —`, `NO_ACTION_NEEDED`, `Status: blocked`) | the marker contract in `rules.md` | An implicit API: changing one skill can silently break a chain |
| A10 | **Open Mercato / web-app specifics** (a UI performance gate, codegen, locale rules, ejecting, product decisions with N/R/D ids, `BACKWARD_COMPATIBILITY.md`) | code-review, check-and-commit, spec-writing | Domain rules presented as universal ones |
| A11 | **Other models are available** (Codex, DeepSeek, Kimi, GLM, MiMo) | om-harness | The `multi` and `optimized` profiles are unusable without setup |
| A12 | **There is a browser and a running app** for QA | auto-qa-pr, prepare-test-env | |
| A13 | **Commits never prompt** | every committing skill | With commit signing on, a passphrase prompt hangs the harness |

## 4. Side effects (things that happen "along the way")

The most surprising ones, ordered by risk:

1. **In its default mode (`prepare-and-merge`), `om-auto-merge-buddy` squash-merges while "bypassing other labels and host merge rules"**: three automation signals replace branch protection.
2. **`om-auto-review-pr` fixes and pushes to a PR on its own when the PR's author is `CURRENT_USER`.** If the agent runs with your `gh` credentials, *every PR you wrote by hand* counts as "the automation's own PR" and gets modified without `--autofix`.
3. **Auto-setup when the config is missing.** Any skill may write `.ai/agentic.config.json`, `SDLC.md`, `AGENTS.md`, `CODE_REVIEW.md`, `BACKWARD_COMPATIBILITY.md`, and a tracker descriptor, and create labels in the repo.
4. **Locks are pushed to the remote as git refs** (`refs/om-locks/*`). The template itself warns that "lock pushes may trigger CI/hooks".
5. **A draft PR opens right after the plan is committed**: work in progress is public before a single line of code exists.
6. **Tracker noise**: a claim comment, a label-rationale comment, a run summary, a CI follow-up comment, a lock-release comment, and manual-QA instructions, on every run.
7. **Autonomous issue filing**: findings during a run become issues, so the issue count grows with entries that often aren't worth tracking.
8. **Fork PRs**: the automation opens a replacement PR in its own repo and closes the original.
9. **Held CI runs get approved** (`approve-pending-runs`) during review.
10. **Hooks** (`block-push-and-pr.sh`, `freeze-tests.sh`) are installed into the repo settings, plus a `.om-freeze-tests` sentinel file.
11. **`om-spec-writing` edits old specs** (the `Superseded by` annotation).
12. **`om-auto-update-changelog` and `om-close-fixed-issues`** close issues and open documentation PRs.

## 5. Where the complexity is

| Rank | Hotspot | Why it is expensive | Value for a small team |
|---|---|---|---|
| 1 | **The claim/lock protocol** | 13% of all text; atomic refs, elections through comments, `claim-reset` audits, the issue-to-PR lock transfer, `ci-monitoring` as a "non-claim" | close to zero |
| 2 | **Automerge** | `automerge`, `-now`, `-force`, `-prepare`; three signals plus an alternative CI signal; modes; a risk override; `--skip-pre-existing-ci-errors`; a 210 KB dashboard | close to zero with a human in the loop |
| 3 | **The label state machine and the QA gate** | 25+ labels, mutual exclusions, a `QA head:` pinned to a SHA, the self-QA exception, risk-high gates | low |
| 4 | **The multi-model harness** | 5 profiles, review councils, packet leases, manifests, JSON schemas, a 130 KB runtime | low: a fresh-context review subagent covers the core |
| 5 | **Multiplying variants** | 4× fix-issue, 4× implement-feature, create-pr vs. -loop, continue-pr vs. -loop, 3 review skills, 5 merge / drive-a-PR skills | "solved" by the `om-help` router, which is a symptom |
| 6 | **Duplicated, drifting boilerplate** | 74 copies of setup and rules, 27 of the claim protocol, each slightly different; it's unclear which version applies | negative |
| 7 | **The tracker abstraction** | 5 trackers × ~30 operations, through Markdown descriptors | low when one tracker is used through `gh` |
| 8 | **Dual `--interactive` / `--autonomous` modes in one skill** | the same instructions with inverted rules ("never answer your own questions" vs. "answer them yourself") | confuses the model and makes runs less predictable |
| 9 | **Text contracts between skills** | markers, `PREVIOUS STEP` blocks, stop tokens | needed only for automated chains |
| 10 | **The plan as a repo file, with Progress checkboxes and "mark step complete" commits** | enables resuming, at the cost of history noise | medium: resuming helps on long tasks |
| 11 | **Compressed references in human-facing text** | questions and decisions referred to as "Q2", "D7", "option B" | humans lose track of what a decision was about, especially in interactive question rounds |

## 6. What is worth keeping

- **`om-brainstorm`**: a hard gate of "no artifacts during the conversation", "build nothing" always on the table, a challenger in a fresh context, and one routing decision as the output.
- **`om-spec-writing`**: skeleton first, then **open questions as a hard stop**; the spec describes what is unique, not the framework; a plan in phases and steps, each testable and leaving the app working.
- **`om-verify-in-repo`**: "bias toward stopping" — without evidence that the bug exists, nothing gets touched.
- **`om-root-cause` → `om-fix`**: the brief format (summary, root cause with `file:line`, files to change, approach, risks), no widening of scope, an explicit low-confidence flag.
- **The regression test is observed failing before the fix** (from `om-fix-issue`).
- **`om-code-review`**: the blocker / major / minor / nit scale and a **mechanical verdict**; a validation gate with real command results; "every failure is a finding".
- **Review in a fresh context** (without the implementation transcript).
- **The staged-only handoff**: the agent ends on a staged diff, and publishing is a separate, explicit human decision.
- **The untrusted-content boundary**: issue, PR, and doc content is data, not instructions.
- **Validation commands in one place** instead of guessing.

## 7. The result: `thin-skills/`

Eleven skills built on the principles below. See [thin-skills/README.md](thin-skills/README.md) for the full description.

```
think ──► spec ──────────► build ──► review ──► ship
          debug (bugs) ──────┘
anything out of scope ──► .ai/findings.md ──► triage
```

1. **One skill = one stage, one artifact, one stopping point.** No variants or aliases.
2. **A human approves each transition.** A skill never runs the next one on its own; it suggests it.
3. **No side effects outside the worktree**, except in skills named after the effect (`ship`, `triage`).
4. **No claims, labels, locks, or automerge.**
5. **Configuration is one section in `AGENTS.md`/`CLAUDE.md`** (validation commands, the specs dir); no separate JSON and no auto-setup.
6. **Each skill is self-contained and short** instead of sharing drifting `references/` copies.
7. **Default: staged, uncommitted changes.** An opt-in `--auto` mode commits per step and ends in the way the user chooses at the start of the run. It never hangs on a signing passphrase.
8. **Findings go to a local file**, never straight to the tracker; `triage` files issues only on confirmation.
9. **Human-facing text must stand on its own**: no bare "Q2" or "option B"; every question and decision is written out in full.
10. **Write for the actual reader.** Agent-only artifacts can be as dense as useful. Human-facing documents are short, and every dependency (files, specs, issues, PRs) is a clickable Markdown link. The om specs referenced sources as plain text, which made them hard to read and navigate.
