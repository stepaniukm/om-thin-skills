#!/usr/bin/env bash
# Runs one benchmark scenario once, with or without thin-skills installed in the fixture.
# usage: run.sh <scenario 1-27> <with|without> [runs-dir]
# Multi-turn scenarios: scenarios/<N>.2.txt, <N>.3.txt … are sent as follow-ups in the same session.
# env:   AGENT       claude | pi | codex, picks the default AGENT_CMD (default: claude)
#        AGENT_CMD   command that takes the prompt as its last argument; overrides AGENT
#        MODEL       optional model id passed to pi / codex
#        TIMEOUT_S   seconds before the run counts as hung (default 900)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SKILLS_SRC=$(cd "$HERE/.." && pwd)
S=${1:?scenario 1-27}
MODE=${2:?with|without}
OUT=${3:-$HERE/runs}
AGENT=${AGENT:-claude}
TIMEOUT_S=${TIMEOUT_S:-900}

# Per-agent defaults. Both agents get the same skills (installed below into .agents/skills and
# .claude/skills); the "without" mode must load no user-level skills, or the baseline is noise.
case $AGENT in
  claude)
    AGENT_CMD=${AGENT_CMD:-claude -p --permission-mode bypassPermissions --output-format stream-json --verbose}
    ;;
  pi)
    # --no-skills turns off user-level discovery; the fixture's skills are loaded explicitly.
    PI_SKILLS=""; [ "$MODE" = with ] && PI_SKILLS="--skill .agents/skills"
    PI_MODEL=""; [ -n "${MODEL:-}" ] && PI_MODEL="--model $MODEL"
    AGENT_CMD=${AGENT_CMD:-pi -p --mode json --no-extensions --no-mcp --no-prompt-templates --no-themes --no-skills $PI_MODEL $PI_SKILLS}
    ;;
  codex)
    CODEX_MODEL=""; [ -n "${MODEL:-}" ] && CODEX_MODEL="--model $MODEL"
    AGENT_CMD=${AGENT_CMD:-codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox $CODEX_MODEL}
    ;;
  *)
    echo "AGENT must be claude|pi|codex (or set AGENT_CMD)" >&2; exit 2
    ;;
esac

# Scenario 7 is scored on a scenario 4 run (same prompt, different criterion).
PROMPT_ID=$S; [ "$S" = 7 ] && PROMPT_ID=4
PROMPT_FILE="$HERE/scenarios/$PROMPT_ID.txt"
[ -f "$PROMPT_FILE" ] || { echo "no prompt for scenario $S" >&2; exit 2; }
[ "$MODE" = with ] || [ "$MODE" = without ] || { echo "mode must be with|without" >&2; exit 2; }

mkdir -p "$OUT"
# Each run lives in its own private temp directory, linked from $OUT: an agent that explores ".."
# must not find sibling runs (another run's skills, worktrees, or the check results).
NAME="$(date +%Y%m%d-%H%M%S)-s$S-$MODE"
RUN="$(mktemp -d "${TMPDIR:-/tmp}/thinbench.XXXXXX")/$NAME"
mkdir -p "$RUN" && ln -s "$RUN" "$OUT/$NAME"
APP=$("$HERE/setup-fixture.sh" "$RUN")

# Scenario-specific state.
case $S in
  5)
    # Signing on, with a fake signer that records any attempt instead of prompting.
    cat > "$RUN/fake-gpg.sh" <<EOF
#!/bin/sh
touch "$RUN/SIGN_ATTEMPTED"
exit 1
EOF
    chmod +x "$RUN/fake-gpg.sh"
    git -C "$APP" config commit.gpgsign true
    git -C "$APP" config gpg.program "$RUN/fake-gpg.sh"
    ;;
  9)
    mkdir -p "$APP/.ai"
    cp "$HERE/scenarios/9-findings.md" "$APP/.ai/findings.md"
    echo ".ai/findings.md" >> "$APP/.git/info/exclude"
    ;;
esac

if [ "$MODE" = with ]; then
  for dir in .claude/skills .agents/skills; do
    mkdir -p "$APP/$dir"
    for s in think discover ux personas spec debug build review qa ship triage migrate; do cp -R "$SKILLS_SRC/$s" "$APP/$dir/"; done
    echo "$dir/" >> "$APP/.git/info/exclude"
  done
fi

# Planted state for scenarios 18–27.
. "$HERE/scenario-setup.sh"

# Baseline for side-effect checks.
git -C "$APP" for-each-ref --format='%(refname) %(objectname)' > "$RUN/refs.before"
git -C "$RUN/origin.git" for-each-ref --format='%(refname) %(objectname)' > "$RUN/origin.before"
git -C "$APP" log --all --oneline | wc -l | tr -d ' ' > "$RUN/commits.before"

echo "run: $RUN"

# A real timeout: `perl -e 'alarm; exec'` loses the alarm at exec, so a stalled agent hung the
# whole suite. Prefer coreutils' timeout and fall back to a forking parent that can kill the child.
run_with_timeout() {
  local secs=$1 code; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; code=$?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; code=$?
  else
    perl -e '
      my $secs = shift; my $pid = fork;
      if (!$pid) { exec @ARGV; exit 127 }
      $SIG{ALRM} = sub { kill 9, $pid; exit 142 };
      alarm $secs; waitpid $pid, 0;
      my $status = $? >> 8;
      exit($status ? $status : ($? ? 128 + ($? & 127) : 0));
    ' "$secs" "$@"; code=$?
  fi
  [ "$code" = 124 ] && code=142   # GNU timeout's code for "timed out"
  return "$code"
}

# Follow-up turns continue the same session. pi keeps its sessions under the run directory.
case $AGENT in
  pi) AGENT_CMD="$AGENT_CMD --session-dir $RUN/sessions"; CONTINUE="-c" ;;
  claude) CONTINUE="-c" ;;
  *) CONTINUE="" ;;
esac

set +e
(cd "$APP" && run_with_timeout "$TIMEOUT_S" $AGENT_CMD "$(cat "$PROMPT_FILE")") > "$RUN/raw-output.txt" 2>&1
code=$?
turn=2
while [ "$code" = 0 ] && [ -f "$HERE/scenarios/$PROMPT_ID.$turn.txt" ]; do
  [ -n "$CONTINUE" ] || { echo "AGENT=$AGENT can't continue a session; turn $turn skipped" >&2; break; }
  git -C "$RUN/origin.git" for-each-ref --format='%(refname) %(objectname)' > "$RUN/origin.turn$((turn-1))"
  git -C "$APP" worktree list | wc -l | tr -d ' ' > "$RUN/worktrees.turn$((turn-1))"
  (cd "$APP" && run_with_timeout "$TIMEOUT_S" $AGENT_CMD $CONTINUE "$(cat "$HERE/scenarios/$PROMPT_ID.$turn.txt")") >> "$RUN/raw-output.txt" 2>&1
  code=$?
  turn=$((turn+1))
done
echo $((turn-1)) > "$RUN/turns"
echo $code > "$RUN/exit-code"
set -e

# Event stream → final answer + which skills were invoked. Handles Claude Code's stream-json
# and pi's --mode json. Other agents: the raw output is used as the transcript.
python3 - "$RUN" <<'PY'
import json, re, sys, pathlib
run = pathlib.Path(sys.argv[1]); raw = (run / "raw-output.txt").read_text(errors="replace")
turns, skills, tools = [], [], {}
SKILL_PATH = re.compile(r"\.agents/skills/([a-z-]+)/SKILL\.md")

def note_skill_args(args):
    for s in SKILL_PATH.findall(json.dumps(args)):
        if (run / "app" / ".agents" / "skills" / s / "SKILL.md").is_file() and s not in skills:
            skills.append(s)

for line in raw.splitlines():
    try: e = json.loads(line)
    except ValueError: continue
    kind = e.get("type")
    if kind == "assistant":  # Claude Code
        for c in e.get("message", {}).get("content", []):
            if c.get("type") == "tool_use":
                tools[c["name"]] = tools.get(c["name"], 0) + 1
                if c["name"] == "Skill": skills.append(c["input"].get("skill", "?"))
                note_skill_args(c.get("input", {}))
    elif kind == "result" and e.get("result") is not None:  # Claude Code final answer
        turns.append(e["result"])
    elif kind == "agent_end":  # pi
        texts = []
        for m in e.get("messages", []):
            if m.get("role") != "assistant": continue
            for b in (m.get("content") or []):
                if not isinstance(b, dict): continue
                if b.get("type") == "text" and b.get("text"):
                    texts.append(b["text"])
                elif b.get("type") == "toolCall":
                    name = b.get("name", "?")
                    tools[name] = tools.get(name, 0) + 1
                    note_skill_args(b.get("arguments", {}))
        turns.append("\n\n".join(texts))
# One section per turn; each agent_end / result event covers only its own turn.
result = turns[0] if len(turns) == 1 else "\n\n".join(f"--- turn {i} ---\n{t}" for i, t in enumerate(turns, 1))
(run / "transcript.txt").write_text(result if turns else raw)
(run / "skills-used.txt").write_text(" ".join(skills) + "\n")
(run / "tools-used.txt").write_text(" ".join(f"{k}:{v}" for k, v in sorted(tools.items())) + "\n")
PY

"$HERE/check.sh" "$RUN" "$S" | tee "$RUN/checks.txt"
