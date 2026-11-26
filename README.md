# Using thin-skills

How to work with the skills day to day. For the full rules, configuration, and what was left out of open-mercato, see the [thin-skills reference](thin-skills/README.md).

## Set up a repository (once)

1. Install the skills with the [skills.sh](https://skills.sh) CLI. Run this in your project's root:

   ```bash
   npx skills add stepaniukm/om-thin-skills/thin-skills --skill '*'
   ```

   It asks which agents to install for and whether to install for this project or globally; choose **project**. Keep the `/thin-skills` part: the rest of the repository holds the original open-mercato skills. To skip the questions, name your agents:

   ```bash
   npx skills add stepaniukm/om-thin-skills/thin-skills --skill '*' --agent claude-code pi -y
   ```

   This installs all twelve skills, including the one-off `migrate`. The skills land in `.agents/skills/` (with links from `.claude/skills/` for Claude Code), and their versions in `skills-lock.json`. Commit these files, so that your teammates and new worktrees have the skills too. If you already have a skill called `review` or `ship`, for example, check before installing; it has the same name.

   | Later | Command |
   |---|---|
   | See what's installed | `npx skills list` |
   | Update | `npx skills update -p` |
   | Remove | `npx skills remove think discover ux personas spec debug build review qa ship triage migrate` |

   The CLI sends anonymous usage data; set `DISABLE_TELEMETRY=1` to turn that off.

2. Add a `## Workflow` section to the project's `AGENTS.md` (or `CLAUDE.md`). The minimum:

   ```markdown
   ## Workflow
   - Base branch: main
   - Specs: .ai/specs
   - Install: pnpm install --frozen-lockfile
   - Validation (in order):
     - pnpm lint
     - pnpm typecheck
     - pnpm test
   ```

   Add `Run app:` and `QA login:` if you want browser checks, and `Worktree setup:` if a fresh checkout needs more than an install. [All options](thin-skills/README.md#configuration).

3. Install and sign in to the GitHub CLI (`gh auth login`). `ship` needs it, and so does filing issues; most other skills use it to look things up.

## Coming from the open-mercato skills?

Run `migrate` once, before anything else. It archives what the om-* skills generated (`.ai/` → `.ai-archive/`), converts what is still in use (the config into `## Workflow`, the product brief, unfinished specs), and removes the om skills from the project so the two sets don't compete. It shows the plan first and leaves staged changes for you to review. Finish or close open om PRs before you run it.

## Which skill do I need?

| You have… | Start with |
|---|---|
| An idea, and you're not sure it's worth doing | `think` |
| A new product or a whole area to define | `discover` |
| A flow or screen that's unclear | `ux` |
| A brief or prototype to pressure-test before talking to real users | `personas` |
| A decided feature with open design questions | `spec` |
| A bug with an unknown cause | `debug` |
| A small, clear change (about five steps or fewer), or an accepted spec | `build` |
| An unfinished branch or PR: review comments, conflicts, red CI | `build` |
| A change you want checked | `review` (code), `qa` (does it work in the browser), `ux review` (is it usable) |
| A finished worktree | `ship` |
| Findings piling up in `.ai/findings.md` | `triage` |

**Name the skill when you ask**, for example "use the `build` skill to fix #231" (or `/build #231` where your agent supports slash commands). Agents usually pick the right skill from a plain request, but not always; in our [benchmark](thin-skills/BENCHMARK.md) a run that missed `build` edited the main checkout.

## Everyday recipes

### Fix a bug

```
debug #231            → a diagnosis; nothing in your code changes
build #231            → failing test first, then the fix, staged in a worktree
review <worktree>     → a verdict and findings
ship <worktree>       → commit, push, PR
```

You can start at `build`: without a diagnosis it follows `debug` first.

### Build a feature

```
spec "export orders as JSON"   → answer its questions, then accept the spec
build <spec path>              → carries out the plan step by step
review <worktree>
qa <worktree>                  → only if the change has UI
ship <worktree>
```

### Make a small change

```
build "rename the Export button to Download CSV"
ship <worktree>
```

### Handle review comments, conflicts, or red CI

```
build PR 123          → shows everything left to do, then fixes or declines each item
ship <worktree>       → updates the same PR
```

### Define a product or a larger area

```
discover "self-service export portal"   → a product brief
ux prototype "request an export"        → a clickable prototype
spec "<first item from Now>"            → continue as a feature
```

### Run it unattended

```
build <spec path> --auto
```

It asks everything once, up front: how the run ends (review then ship, review then stop, or ship without review), any extras, and whether your signing key is unlocked. Use *review then ship* unless you have a reason not to; *ship without review* also skips the check against the product brief.

## What to expect

- **Each skill stops and hands back to you.** It ends with `Next: …`; you decide whether to run that. `--auto` is the exception you choose.
- **Work happens in a worktree**, `../<repo>.worktrees/<slug>`, so your main checkout stays as it was. Open the path from the report in your editor.
- **By default `build` commits nothing.** It leaves staged changes: look with `git diff --cached`, then commit yourself or run `ship`.
- **Only a few steps write to GitHub**: `ship`, approved issues from `triage` and `discover`, and `--post` comments you approved.
- **Problems outside the task are logged, not fixed**, in `.ai/findings.md` in the main checkout. The file stays local.
- **Questions come with options and a recommendation.** You can answer briefly, but say which option in words.
- **Merging is yours.** After the merge, clean up from the main checkout: `git worktree remove <path>`.

## Good habits

- Pass the worktree path, spec path, or PR number to the next skill, especially in a new session.
- Run `review` in a fresh session, or let it start a subagent. The context that wrote the code shouldn't judge it.
- If a review or QA check is followed by more edits, run it again: its verdict covers only the version it checked.
- Check the `file:line` references and dates in reports and findings. Models sometimes get them wrong.
- For auth, money, permissions, or migrations, add `review --second-opinion` (needs a `Second opinion:` line in the config).
- If a change adds migrations, give the worktree its own database. A copied `.env` often points at the shared one. `qa` stops if it can't confirm they're separate; tests and setup commands run by `build` have no such guard.
- Don't run an untrusted PR on your own machine. A worktree is not a sandbox.

## When something goes wrong

| Symptom | What to do |
|---|---|
| The agent edits your main checkout or skips the steps | The skill probably didn't load. Stop it, check the changes with `git status`, and ask again with the skill's name |
| "The `## Workflow` section is missing" | Add it (see setup); the skill suggests the text but doesn't write it |
| `NOT RUN` in a review | A validation command couldn't run. Fix the setup; it never counts as a pass |
| "No new failures; known failures remain" | Your base branch is already red. It doesn't block you, but it isn't green |
| `QA: BLOCKED` | The app or browser couldn't start, or couldn't start safely. The report says why |
| Commits are refused because of signing | Unlock your key, or run the commands it prints |
| `CI: unverified` | The CI runs couldn't be read. Check the PR on GitHub before merging |
