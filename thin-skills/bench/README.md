# bench

The runnable part of [BENCHMARK.md](../BENCHMARK.md). Each run builds a fresh fixture repo, optionally installs thin-skills into it, sends one prompt to an agent, and checks side effects automatically.

## Files

| File | What it does |
|---|---|
| [setup-fixture.sh](setup-fixture.sh) | Creates `<dir>/app` (a tiny Node service) and `<dir>/origin.git` (a local "remote"), with planted problems |
| [scenarios/](scenarios/) | One prompt per scenario (Polish, to test that the skills activate from natural requests), plus the findings file for scenario 9 |
| [run.sh](run.sh) | `run.sh <scenario> <with\|without> [runs-dir]` — one run; output goes to `runs/<timestamp>-s<N>-<mode>/` |
| [check.sh](check.sh) | Automated pass/fail checks: hangs, commits, pushes, signing attempts, worktrees, findings, main-checkout changes |

## Running

```bash
# one scenario, both modes
./run.sh 4 without
./run.sh 4 with

# everything, both modes
for s in 1 2 3 4 5 6 7 8 9 10 11 12; do for m in without with; do ./run.sh $s $m; done; done
```

Each run directory contains `transcript.txt` (the agent's answer), `checks.txt` (automated results), and the fixture itself for inspection. Criteria that need judgment, such as question quality, self-contained wording, and working links, are scored by reading the transcript against the table in [BENCHMARK.md](../BENCHMARK.md#scenarios-and-criteria).

## Agent command

Default: `claude -p --permission-mode bypassPermissions`, run inside the throwaway fixture. Permissions are bypassed because the run is unattended; nothing outside the run directory is in scope. To use another model or harness, set `AGENT_CMD` to any command that takes the prompt as its last argument:

```bash
AGENT_CMD="claude -p --permission-mode bypassPermissions --model claude-sonnet-5-5" ./run.sh 2 with
```

`TIMEOUT_S` (default 900) turns a hang into a failed run instead of a stuck terminal.

## Known limits

- **Single turn.** Each run is one prompt. That fits the "stops and asks" criteria (spec, think, auto mode), but follow-up turns aren't scored.
- **User-level skills and plugins** load in both modes and add noise to the "without" baseline. For a clean baseline, run with an agent config that has no global skills.
- **No GitHub.** The remote is a local bare repo, so `gh` calls fail. The skills are expected to say so and continue.
