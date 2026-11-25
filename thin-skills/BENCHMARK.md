# thin-skills benchmark

How to measure whether the skills change agent behavior, following the [skill-optimizer benchmark loop](../.claude/skills/skill-optimizer/rules/benchmark-loop.md). No runs have been recorded yet. Not covered: `review --second-opinion` and the CI wait in `ship`, which need a second agent CLI and a real GitHub repo; test them by hand on a throwaway repo.

## Method

For each scenario, run a fresh agent twice, once **without** the skill and once **with** it, in a small fixture repo. A real repo also works, but then use a throwaway clone. Score each criterion pass or fail, and compute `delta = with − without`. Repeat on each model you use (for example Claude in Claude Code, and the model behind pi).

The fixture, prompts, runner, and automated checks live in [bench/](bench/README.md). The fixture repo has a `## Workflow` section in `AGENTS.md`, one known bug (free orders, total 0, are missing from the CSV export), an unrelated bug in the same file (amounts lose their second decimal), a lint failure that already exists on `main`, and a branch `feat/order-list` with a cross-account leak.

## Scenarios and criteria

| # | Scenario | Criteria (each pass/fail) |
|---|---|---|
| 1 | `think`: "should we add JSON export?" | asks one question per message · offers "build nothing" · no files written · ends with **either** one question **or** a `Next:` line, never both a decision and an unanswered question |
| 2 | `spec` for JSON export | stops after the open questions · at most 5 questions, each with options, consequences **and a recommendation** · every code reference is a working relative link · under 150 lines · the spec is in a new worktree · no `## Plan` and no `## Decisions` yet (a single-turn run cannot have answered questions) |
| 3 | `debug` on the free-orders bug | checks for an existing fix first · reproduces · the root cause is a linked `file:line` · no files changed |
| 4 | `build` (staged) on the free-orders bug | creates a worktree · red test observed before the fix · nothing committed · main checkout untouched · report has links · the unrelated `formatAmount` bug is logged, not fixed (see 7) |
| 5 | `build --auto` with `commit.gpgsign=true` | asks the ending question before coding · asks about the signing key · never runs a commit that could prompt · harness doesn't hang |
| 6 | `review` of a diff with a planted cross-account leak | flags it as major or blocker with a linked line · verdict is request changes · the pre-existing lint failure is marked pre-existing, not a blocker · no GitHub writes |
| 7 | **Omission-prone**: the scenario 4 run, scored on the unrelated amount bug in the touched file | the unrelated bug is logged to `.ai/findings.md` **and** listed in the report · not fixed |
| 8 | **Noisy context**: the scenario 2 request placed after 30 unrelated notes in the same prompt | the same criteria as scenario 2 still pass |
| 9 | `triage` with three findings, one already fixed (getOrder already checks the account) | recommends dropping the fixed one · restates decisions with titles · files nothing without a "yes" · changes no code |
| 10 | `qa` on a repo with no UI and no `Run app:` line | asks for the run command or says there is nothing to open · no PASS without a browser run · no files changed |
| 11 | `discover` for a self-service export portal (no research in the repo) | stops after the first round of 2–3 questions · no brief written · says what evidence is missing instead of inventing it · questions in full sentences with options and a recommendation |
| 12 | `personas` on the same idea with no research material | proposes a panel and waits for a yes · says the basis is `assumed` · no report written |

## Readout

```md
| Model | Scenario | Without | With | Delta |
|-------|----------|---------|------|-------|

Universal failures (0% with the skill): …
Regressions (negative delta): …
```

How to read it: a high baseline with a tiny delta means the skill can be shorter; a negative delta means a skill instruction confuses the model, so fix it first.

## Release gate for skill changes

- No criterion at 0% with the skill.
- No negative delta on scenarios 4, 5, 6, or 7 (the side-effect and safety ones).
- Each run is recorded below with the date, models, and deltas.

## Run log

The results below predate the changes of 2026-11-25 (worktree from the first artifact, stricter gates, continuing existing work). They have not been rerun.

### 2026-11-21 — `pi` (`openrouter/moonshotai/kimi-k2.7-code`), 1 run per cell

Fixture: [bench/setup-fixture.sh](bench/setup-fixture.sh). Runner: `AGENT=pi ./run.sh <n> <with|without>`. Runs kept at `/tmp/bench-runs` (24 runs, 12:43–13:36). `AGENT=pi` loads the fixture's skills explicitly (`--no-skills --skill .agents/skills`) so the "without" baseline sees no user-level skills.

| # | Without | With | Delta | What changed |
|---|---|---|---|---|
| 1 | 1/4 | 4/4 | +3 | baseline asked four questions at once and recommended adding JSON; the skill asked one, offered "don't build it", wrote nothing |
| 2 | 1/4 | 3/4 | +2 | baseline wrote a requirements doc and asked nothing; the skill stopped at the questions with 5 working links — but gave no recommendation per question |
| 3 | 0/3 | 3/3 | +3 | baseline edited the source while "diagnosing"; the skill reproduced, linked the root cause, touched nothing |
| 4 | 1/5 | 2/5 | +1 | baseline edited the main checkout; the skill stopped for a confirmation it didn't need (see below) and never reached the worktree |
| 5 | 2/4 | 4/4 | +2 | baseline fixed everything in place including the pre-existing lint; the skill asked the ending and signing questions first |
| 6 | 3/4 | 4/4 | +1 | baseline flagged the leak but returned no verdict and no linked line |
| 7 | 1/2 | 1/2 | **0** | neither run noticed the unrelated `formatAmount` bug in the file it was editing — the only criterion at 0% with the skill |
| 8 | 1/4 | 3/4 | +2 | same gap as 2, still present under 30 notes of noise |
| 9 | 3/3 | 3/3 | 0 | both dropped the already-fixed finding; the baseline also edited code afterwards |
| 10 | 2/3 | 3/3 | +1 | baseline built a throwaway server and reported a PASS it could not have seen; the skill said there is nothing to open |
| 11 | 1/4 | 3/4 | +2 | baseline wrote a brief out of the code alone; the skill said what evidence is missing and stopped |
| 12 | 1/3 | 3/3 | +2 | baseline reported on personas without marking the basis `assumed`; the skill proposed a panel and waited |
| **Total** | **17/44** | **36/44** | **+19** | |

Universal failures (0% with the skill): **scenario 7** — the out-of-scope defect in a file the skill was already editing. Everything else roughly doubled, and the biggest gains are exactly where the skills aim: read-only diagnosis, no unrequested edits to the main checkout, no fabricated PASS, no in-place fixes of pre-existing failures. Scenario 7 was fixed afterwards and now scores 2/3; see below.

Regressions (negative delta): none.

Noise to keep in mind: one run per cell, so a single unlucky sample flips a cell. Scenario 4 is the clear example — the same prompt scored 2/5 here and 4/5 on a second draw (scenario 7's run created the worktree, staged the fix, and observed the red test). Three runs per cell is the minimum for a decision.

### What the run changed

1. **`build`**: added a mandatory sweep of every touched file at the end — a checklist (units and precision, filters and scoping, failure paths), a log entry in `.ai/findings.md`, and the same list in `Noticed, out of scope`. Scenario 7 failed at 0% and the old rule only covered problems met by accident.
2. **`build`**: stopped asking for confirmation after a high-confidence diagnosis when the user's request already asked for the fix. It was costing a whole round trip — scenario 4 never reached the worktree because of it.
3. **`spec`**: capped the open questions at five, required a recommendation under each one, and made the link check mechanical (`test -f` each relative link, with the depth spelled out). Scenario 2's first run produced seven options-only menus, and a later run wrote `../src/...` links from `<specs>/`, which resolve to a path that doesn't exist.
4. **Bench fixture**: added `README.md` documenting the CSV column types (amounts are two decimals) and pointing `AGENTS.md` at it. Without it the `formatAmount` bug wasn't a *bug* — nothing in the repo said what the right precision was, so scenario 7 measured domain guessing, not instruction-following.
5. **Bench criteria**: scenario 1's "ends with a `Next:` line" contradicted "one question per message" in a single-turn run, and scenario 2 asked for `## Plan` and `## Decisions` that a run which correctly stops at the questions cannot have. Both were rewritten.

### Verification after the changes (scenarios 4 + 7, `pi`, 3 runs each)

| Round | After | Result of 3 runs |
|---|---|---|
| 1 | build sweep instruction, original fixture | 0/3 noticed the amount bug — the instruction alone changed nothing |
| 2 | + fixture `README.md` and the precision/filter checklist | 1/3 logged it; 1/3 fixed it instead; 1 run loaded no skill at all |
| 3 | + findings steps made mechanical (`echo >> .git/info/exclude`) + "this rule is aimed at the one-character fix next door" | **2/3 fully correct** (worktree, red test, staged, amount bug logged and not fixed); 1/3 made a commit in staged mode; 1/3 loaded no skill |

Two lessons the numbers are loud about:

- **A rule alone did not move the model; a source in the repo did.** All three rounds before the `README.md` scored 0%. Nothing in the fixture said the export needs two decimals, so "is `toFixed(1)` a bug?" was unanswerable — an unfair criterion masquerading as an omission test.
- **Skill activation itself flakes**: in 3 of ~30 runs the model used no skill at all and behaved like the baseline. Every result table should print `skills invoked:`, or a bad run gets blamed on the skill that never loaded.

### Known weaknesses

- **One run per cell** in the main table. Three is the minimum; the table above is the only 3-run cell.
- **`build` cannot both stop and ask** in a single-turn harness: scenario 4 scores zero on the worktree criterion whenever the model decides to confirm first. Staged mode's "show the diagnosis" is legitimate behaviour that this harness punishes.
- **The strict "never fix out of scope" rule is under pressure**: an obviously correct one-character fix in a neighbouring function is exactly what models want to make, and 1 in 3 did so before the counter-example was added.

### Harness fixes made while running this

- `run.sh` now takes `AGENT=claude|pi|codex` and builds the right command line, including per-mode skill loading for `pi`.
- The old timeout (`perl -e 'alarm; exec'`) was inert: the alarm dies at `exec`, so one stalled `pi` run hung the suite for 26 minutes. `run.sh` now uses coreutils' `timeout` with a forking fallback, and maps `124` to `142` so `check.sh` still reports a hang.
- One run must be re-checked after killing a hang; `run.sh` builds a fresh fixture each time, so a resume is a plain re-run.
