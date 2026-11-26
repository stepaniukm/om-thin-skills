# bench

The runnable part of [BENCHMARK.md](../BENCHMARK.md). Each run builds a fresh fixture repo, optionally installs thin-skills into it, sends one prompt to an agent, and checks side effects automatically.

## Files

| File | What it does |
|---|---|
| [setup-fixture.sh](setup-fixture.sh) | Creates `<dir>/app` (a tiny Node service) and `<dir>/origin.git` (a local "remote"), with planted problems |
| [scenario-setup.sh](scenario-setup.sh) | Extra planted state for scenarios 18–27 (an accepted spec, a ready-to-ship worktree, a regression, an om-style repo, …) |
| [scenarios/](scenarios/) | One prompt per scenario, plus `<N>.2.txt` follow-ups for multi-turn scenarios (Polish, to test that the skills activate from natural requests), plus the findings file for scenario 9 |
| [run.sh](run.sh) | `run.sh <scenario> <with\|without> [runs-dir]` — one run; output goes to `runs/<timestamp>-s<N>-<mode>/` |
| [check.sh](check.sh) | Automated pass/fail checks: hangs, commits, pushes, signing attempts, worktrees, findings, main-checkout changes |

## Running

```bash
# one scenario, both modes
./run.sh 4 without
./run.sh 4 with

# everything, both modes
for s in $(seq 1 27); do for m in without with; do ./run.sh $s $m; done; done
```

Each run directory contains `transcript.txt` (the agent's answer), `checks.txt` (automated results), and the fixture itself for inspection. Criteria that need judgment, such as question quality, self-contained wording, and working links, are scored by reading the transcript against the table in [BENCHMARK.md](../BENCHMARK.md#scenarios-and-criteria).

## Agent command

`AGENT` picks the command line, `AGENT_CMD` overrides it, and `MODEL` is passed through to `pi`/`codex`:

| `AGENT` | Default command |
|---|---|
| `claude` (default) | `claude -p --permission-mode bypassPermissions --output-format stream-json --verbose` |
| `pi` | `pi -p --mode json --no-session --no-extensions --no-mcp --no-prompt-templates --no-themes --no-skills [--skill .agents/skills]` |
| `codex` | `codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox` |

```bash
AGENT=pi ./run.sh 4 with
AGENT=pi MODEL=openai-codex/gpt-6.1-sol TIMEOUT_S=600 ./run.sh 4 with
```

In `pi` mode the `without` baseline runs with `--no-skills`, and the `with` mode loads only the fixture's copy, so user-level skills can't leak into either side. Permissions are bypassed because the run is unattended; nothing outside the run directory is in scope.

`TIMEOUT_S` (default 900) turns a hang into a failed run instead of a stuck terminal. It is a real timeout (coreutils `timeout`, or a forking parent that kills the child) — `perl -e 'alarm; exec'` does not work, because the alarm does not survive `exec`.

## Known limits

- **Rate limits.** opencode-go returns 429 at four parallel runs; run two at a time (`xargs -P 2`).

- **Mostly single turn.** Scenarios with a `<N>.2.txt` file continue the same session (`pi` and `claude` only); the rest are one prompt. That fits the "stops and asks" criteria (spec, think, auto mode), but follow-up turns aren't scored — a skill that asks a fair question then loses the point it would have earned on the answer is scored as if it failed.
- **One run per cell is not enough.** Scenario 4 scored 2/5 and 4/5 on two draws of the same prompt with the same model. Use three.
- **The `claude` path** parses `--output-format stream-json`; `pi` is parsed from `--mode json`. For any other agent the raw output becomes the transcript and `skills-used.txt` stays empty, so skill activation has to be read by hand.
- **User-level skills and plugins** load in both modes and add noise to the "without" baseline. For a clean baseline, run with an agent config that has no global skills.
- **No GitHub.** The remote is a local bare repo, so `gh` calls fail. The skills are expected to say so and continue.
