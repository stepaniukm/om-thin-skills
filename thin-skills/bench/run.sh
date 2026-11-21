#!/usr/bin/env bash
# Runs one benchmark scenario once, with or without thin-skills installed in the fixture.
# usage: run.sh <scenario 1-12> <with|without> [runs-dir]
# env:   AGENT_CMD   command that takes the prompt as its last argument
#                    (default: claude -p --permission-mode bypassPermissions)
#        TIMEOUT_S   seconds before the run counts as hung (default 900)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SKILLS_SRC=$(cd "$HERE/.." && pwd)
S=${1:?scenario 1-12}
MODE=${2:?with|without}
OUT=${3:-$HERE/runs}
AGENT_CMD=${AGENT_CMD:-claude -p --permission-mode bypassPermissions --output-format stream-json --verbose}
TIMEOUT_S=${TIMEOUT_S:-900}

# Scenario 7 is scored on a scenario 4 run (same prompt, different criterion).
PROMPT_ID=$S; [ "$S" = 7 ] && PROMPT_ID=4
PROMPT_FILE="$HERE/scenarios/$PROMPT_ID.txt"
[ -f "$PROMPT_FILE" ] || { echo "no prompt for scenario $S" >&2; exit 2; }
[ "$MODE" = with ] || [ "$MODE" = without ] || { echo "mode must be with|without" >&2; exit 2; }

mkdir -p "$OUT"
RUN="$OUT/$(date +%Y%m%d-%H%M%S)-s$S-$MODE"
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
    for s in think discover ux personas spec debug build review qa ship triage; do cp -R "$SKILLS_SRC/$s" "$APP/$dir/"; done
    echo "$dir/" >> "$APP/.git/info/exclude"
  done
fi

# Baseline for side-effect checks.
git -C "$APP" for-each-ref --format='%(refname) %(objectname)' > "$RUN/refs.before"
git -C "$RUN/origin.git" for-each-ref --format='%(refname) %(objectname)' > "$RUN/origin.before"

echo "run: $RUN"
set +e
(cd "$APP" && perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_S" $AGENT_CMD "$(cat "$PROMPT_FILE")") > "$RUN/raw-output.txt" 2>&1
echo $? > "$RUN/exit-code"
set -e

# Stream-json output (Claude Code) → final answer + which skills were invoked. Other agents: raw output as is.
python3 - "$RUN" <<'PY'
import json, sys, pathlib
run = pathlib.Path(sys.argv[1]); raw = (run / "raw-output.txt").read_text(errors="replace")
result, skills, tools = None, [], {}
for line in raw.splitlines():
    try: e = json.loads(line)
    except ValueError: continue
    if e.get("type") == "assistant":
        for c in e.get("message", {}).get("content", []):
            if c.get("type") == "tool_use":
                tools[c["name"]] = tools.get(c["name"], 0) + 1
                if c["name"] == "Skill": skills.append(c["input"].get("skill", "?"))
    elif e.get("type") == "result":
        result = e.get("result", "")
(run / "transcript.txt").write_text(result if result is not None else raw)
(run / "skills-used.txt").write_text(" ".join(skills) + "\n")
(run / "tools-used.txt").write_text(" ".join(f"{k}:{v}" for k, v in sorted(tools.items())) + "\n")
PY

"$HERE/check.sh" "$RUN" "$S" | tee "$RUN/checks.txt"
