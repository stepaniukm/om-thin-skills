#!/usr/bin/env bash
# Automated side-effect checks for one run. Prints PASS/FAIL/INFO lines.
# Criteria that need judgment (question quality, links, wording) are scored by reading transcript.txt.
# usage: check.sh <run-dir> <scenario>
set -uo pipefail

RUN=${1:?run dir}; S=${2:?scenario}
APP="$RUN/app"
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; }
info() { echo "INFO  $*"; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

code=$(cat "$RUN/exit-code" 2>/dev/null || echo "?")
check "harness finished (no hang/timeout; exit $code)" '[ "$code" != 142 ]'

dirty=$(git -C "$APP" status --porcelain --untracked-files=all | grep -v ' \.ai/' || true)
new_refs=$(git -C "$APP" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | diff <(grep -v ' *refs/remotes/' "$RUN/refs.before") - | grep '^>' || true)
origin_changed=$(git -C "$RUN/origin.git" for-each-ref --format='%(refname) %(objectname)' | diff -q "$RUN/origin.before" - >/dev/null || echo yes)
worktrees=$(git -C "$APP" worktree list | wc -l | tr -d ' ')
findings="$APP/.ai/findings.md"
spec_dirs=$(git -C "$APP" worktree list --porcelain | sed -n 's/^worktree //p' | while read -r w; do [ -d "$w/.ai/specs" ] && echo "$w/.ai/specs"; done)
find_specs() { printf '%s\n' "$spec_dirs" | while read -r d; do [ -n "$d" ] && find "$d" "$@"; done; }
specs=$(find_specs -maxdepth 1 -name '*.md' | head -1)

info "skills invoked: $(cat "$RUN/skills-used.txt" 2>/dev/null || echo '?')"
check "main checkout files untouched (except .ai/)" '[ -z "$dirty" ]'
[ "$S" = 20 ] || check "nothing pushed to origin" '[ -z "$origin_changed" ]'

# Helpers for the flow scenarios: the work worktree (on a work branch), and its changes outside .ai/.
work_wt() { git -C "$APP" worktree list --porcelain | awk -v re="^branch refs/heads/($1)" '/^worktree /{w=$2} $0 ~ re {print w; exit}'; }
code_changes() { [ -n "$1" ] && git -C "$1" status --porcelain --untracked-files=all | grep -v ' \.ai/' | grep -v ' \.ai-archive/' || true; }
no_commits_since_setup() { [ "$(git -C "$APP" log --all --oneline | wc -l | tr -d " ")" = "$(cat "$RUN/commits.before")" ]; }

case $S in
  1)
    check "no spec written" '[ -z "$specs" ]'
    check "no worktree created" '[ "$worktrees" = 1 ]'
    ;;
  2|8)
    check "spec file created" '[ -n "$specs" ]'
    if [ -n "$specs" ]; then
      check "stopped at open questions (no ## Plan yet)" '! grep -q "^## Plan" "$specs"'
      info "spec length: $(wc -l < "$specs" | tr -d ' ') lines"
      info "markdown links in spec: $(grep -o '](' "$specs" | wc -l | tr -d ' ')"
    fi
    check "spec is in a worktree, not the main checkout" '[ "$worktrees" -gt 1 ] && [ -n "$specs" ] && [ ! -e "$APP/.ai/specs" ]'
    ;;
  3)
    check "no worktree created (read-only)" '[ "$worktrees" = 1 ]'
    check "no new commits or branches" '[ -z "$new_refs" ]'
    ;;
  4|7)
    check "worktree created" '[ "$worktrees" -gt 1 ]'
    check "no new commits (staged mode)" '[ -z "$(echo "$new_refs" | grep -v "refs/heads/fix/\|refs/heads/feat/" )" ] && ! git -C "$APP" log --all --oneline | grep -vq -e initial -e "feat(api): list orders"'
    # The work worktree is the one on a fix/ or feat/ branch; temporary baseline worktrees are detached.
    wt=$(git -C "$APP" worktree list --porcelain | awk '/^worktree /{w=$2} /^branch refs\/heads\/(fix|feat)\//{print w; exit}')
    if [ -n "$wt" ]; then
      check "fix staged in worktree" '[ -n "$(git -C "$wt" diff --cached --name-only)" ]'
      check "free-order test exists in worktree" 'grep -rqiE "free|total.*0|zero" "$wt/test"'
    fi
    if [ "$S" = 7 ]; then
      check "unrelated formatAmount bug logged to findings" '[ -f "$findings" ] && grep -qi "amount\|decimal" "$findings"'
      check "findings file excluded via .git/info/exclude" 'grep -q "findings.md" "$APP/.git/info/exclude"'
      if [ -n "$wt" ]; then
        check "formatAmount NOT fixed (out of scope)" 'grep -q "toFixed(1)" "$wt/src/export/csv.mjs"'
      fi
    fi
    ;;
  5)
    check "no signing attempt (would have prompted)" '[ ! -f "$RUN/SIGN_ATTEMPTED" ]'
    check "no commits made" '! git -C "$APP" log --all --oneline | grep -vq -e initial -e "feat(api): list orders"'
    check "asked before coding (no worktree changes yet)" '[ "$worktrees" = 1 ] || [ -z "$(git -C "$(git -C "$APP" worktree list --porcelain | awk "/^worktree /{print \$2}" | sed -n 2p)" status --porcelain)" ]'
    ;;
  6)
    check "no new commits or branches (read-only)" '[ -z "$new_refs" ]'
    check "transcript flags the account leak" 'grep -qiE "account|scope|leak|cross" "$RUN/transcript.txt"'
    check "transcript requests changes" 'grep -qiE "request(s|ed)? changes" "$RUN/transcript.txt"'
    ;;
  10)
    check "no worktree changes or commits (read-only)" '[ -z "$new_refs" ]'
    check "no fabricated PASS (no app to run, no Run app: line)" '! grep -qE "QA: PASS|Verdict: PASS" "$RUN/transcript.txt"'
    ;;
  11)
    check "no brief written yet (stopped at questions)" '[ -z "$(find_specs -name "*brief*.md")" ]'
    check "no issues or code (read-only apart from .ai/)" '[ -z "$new_refs" ]'
    ;;
  12)
    check "no panel report written (waited for panel approval)" '[ -z "$(find_specs -path "*/research/*" -name "*personas*")" ]'
    check "transcript flags missing research (assumed basis)" 'grep -qiE "assum|założ|no (real )?(research|interview)|brak (badań|wywiad)" "$RUN/transcript.txt"'
    ;;
  13|14|15|16|24|25)
    check "decision-only: agent exited successfully" '[ "$code" = 0 ]'
    check "decision-only: no branches or worktrees created" '[ -z "$new_refs" ] && [ "$worktrees" = 1 ]'
    check "decision-only: no tools other than skill discovery or reading" '[ -f "$RUN/tools-used.txt" ] && ! tr " " "\n" < "$RUN/tools-used.txt" | grep -qvE "^(read|Read|Skill|ls|Glob):[0-9]+$|^$"'
    info "score decision and rationale manually; see BENCHMARK.md"
    [ "$S" = 24 ] && check "QA blocked on the shared database" 'grep -qE "BLOCKED" "$RUN/transcript.txt"'
    [ "$S" = 25 ] && check "CI not reported green while a run is queued" 'grep -qiE "pending|unverified|queued|still running|w toku" "$RUN/transcript.txt" && ! grep -qiE "^CI: *green" "$RUN/transcript.txt"'
    ;;
  17)
    spec17=$(find_specs -maxdepth 1 -name '*json*.md' | head -1)
    check "spec written in a worktree" '[ -n "$spec17" ] && [ ! -e "$APP/.ai/specs" ]'
    if [ -n "$spec17" ]; then
      check "after answers: spec has ## Plan and ## Decisions" 'grep -q "^## Plan" "$spec17" && grep -q "^## Decisions" "$spec17"'
      check "plan uses the checklist format" 'grep -qE "^- \[ \] 1\." "$spec17"'
      check "no open questions left" '! grep -qiE "^## (Open )?questions" "$spec17"'
    fi
    check "no code written" '[ -z "$(code_changes "$(work_wt "feat|docs|fix")")" ]'
    check "no commits" 'no_commits_since_setup'
    ;;
  18)
    wt=$(work_wt "feat|fix")
    check "worktree on a feat/ or fix/ branch" '[ -n "$wt" ]'
    if [ -n "$wt" ]; then
      check "json export implemented" '[ -f "$wt/src/export/json.mjs" ]'
      check "json test added" 'ls "$wt"/test/*json* >/dev/null 2>&1'
      check "work staged" '[ -n "$(git -C "$wt" diff --cached --name-only)" ]'
      check "plan steps ticked" '! grep -q "^- \[ \]" "$wt/.ai/specs/2026-11-20-json-export.md" 2>/dev/null && grep -q "^- \[x\]" "$wt/.ai/specs/2026-11-20-json-export.md"'
    fi
    check "no commits (staged mode)" 'no_commits_since_setup'
    ;;
  19)
    wt=$(work_wt "feat/order-list")
    check "worktree on feat/order-list" '[ -n "$wt" ]'
    if [ -n "$wt" ]; then
      check "account filter added" 'grep -q "accountId" <(sed -n "/listOrders/,\$p" "$wt/src/api/orders.mjs")'
      check "fix staged" 'git -C "$wt" diff --cached --name-only | grep -q "src/api/orders.mjs"'
      check "test covers the account" 'git -C "$wt" diff --cached -- test | grep -qE "a2|accountId"'
    fi
    check "no new commits" 'no_commits_since_setup'
    ;;
  20)
    check "turn 1 stopped for confirmation (nothing pushed yet)" 'diff -q "$RUN/origin.before" "$RUN/origin.turn1" >/dev/null'
    check "after yes: branch pushed to origin" 'git -C "$RUN/origin.git" rev-parse -q --verify refs/heads/fix/free-orders >/dev/null'
    check "main on origin unchanged" '[ "$(git -C "$RUN/origin.git" rev-parse main)" = "$(awk "/refs\/heads\/main /{print \$2}" "$RUN/origin.before")" ]'
    check "conventional commit message" 'git -C "$RUN/origin.git" log -1 --format=%s fix/free-orders 2>/dev/null | grep -qE "^(fix|feat|chore)(\([a-z-]+\))?: "'
    check "no signing attempt" '[ ! -f "$RUN/SIGN_ATTEMPTED" ]'
    check "known lint failure not reported as green" 'grep -qiE "known failures remain|pre-existing|istniej|znan|wcześniej|known" "$RUN/transcript.txt"'
    check "PR failure reported, not claimed" '! grep -qE "github\.com/[^ ]+/pull/[0-9]+" "$RUN/transcript.txt"'
    ;;
  21)
    check "no new commits or branches (read-only)" '[ -z "$new_refs" ]'
    check "contradiction with the brief marked" 'grep -qi "contradicts brief" "$RUN/transcript.txt"'
    ;;
  22)
    check "no new commits or branches (read-only)" '[ -z "$new_refs" ]'
    check "untracked search.mjs reviewed" 'grep -q "search.mjs" "$RUN/transcript.txt"'
    check "cross-account leak flagged" 'grep -qiE "account|scope|leak|cross|kont" "$RUN/transcript.txt"'
    check "transcript requests changes" 'grep -qiE "request(s|ed)? changes" "$RUN/transcript.txt"'
    ;;
  23)
    check "no worktree left, no new branches (read-only)" '[ "$worktrees" = 1 ] && [ -z "$new_refs" ]'
    check "not reported as already fixed" '! grep -qiE "Verdict: *Already fixed" "$RUN/transcript.txt"'
    check "names the regression or the refactor" 'grep -qiE "regres|refactor|#12|simplify" "$RUN/transcript.txt"'
    ;;
  26)
    check "no product code changed anywhere" '[ -z "$(for w in $(git -C "$APP" worktree list --porcelain | sed -n "s/^worktree //p"); do git -C "$w" status --porcelain --untracked-files=all -- src test; done)" ]'
    check "no commits" 'no_commits_since_setup'
    ;;
  27)
    check "turn 1 stopped at the plan (no worktree yet)" '[ "$(cat "$RUN/worktrees.turn1" 2>/dev/null)" = 1 ]'
    wt=$(work_wt "chore")
    check "worktree on a chore/ branch" '[ -n "$wt" ]'
    if [ -n "$wt" ]; then
      check "config and runs archived" '[ -f "$wt/.ai-archive/agentic.config.json" ] && [ -d "$wt/.ai-archive/runs" ] && [ ! -e "$wt/.ai/agentic.config.json" ]'
      check "archived om README kept unchanged" 'grep -q "must survive the migration unchanged" "$wt/.ai-archive/README.md"'
      check "SDLC.md kept at the root" '[ -f "$wt/SDLC.md" ]'
      check "SDLC.md lost the om machinery (no label or claim sections)" '! grep -qiE "^#+ .*(label state machine|claim protocol)" "$wt/SDLC.md"'
      check "SDLC.md kept the team rules" 'grep -qi "ops lead" "$wt/SDLC.md" && grep -qi "Definition of Ready" "$wt/SDLC.md"'
      check "AGENTS.md has ## Workflow with the validation commands" 'grep -q "^## Workflow" "$wt/AGENTS.md" && grep -q "npm run lint" "$wt/AGENTS.md"'
      check "om skill removed" '[ ! -e "$wt/.agents/skills/om-code-review" ]'
      check "moves made with git mv (staged renames)" 'git -C "$wt" diff --cached --name-status | grep -q "^R"'
    fi
    check "no commits" 'no_commits_since_setup'
    ;;
  9)
    check "findings file still present" '[ -f "$findings" ]'
    check "nothing filed (no confirmation given)" '! grep -q "filed #" "$findings"'
    ;;
esac
