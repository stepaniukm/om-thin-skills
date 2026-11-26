#!/usr/bin/env bash
# Extra state for scenarios 18–27, on top of setup-fixture.sh. Sourced by run.sh with $S, $RUN, $APP set.
# Every scenario starts on main; branches it needs are pushed to origin so `git fetch` finds them.

g() { git -C "$APP" "$@"; }
commit_main() { g add -A && g commit -qm "$1" && g push -q origin main; }

case $S in
  18)
    # An accepted spec with a two-step plan, committed on main.
    mkdir -p "$APP/.ai/specs"
    cat > "$APP/.ai/specs/2026-11-20-json-export.md" <<'EOF'
# JSON export next to CSV

## TLDR
Integrations want orders as JSON. Today only CSV exists ([csv.mjs](../../src/export/csv.mjs#L10)). Add a JSON export for one account; CSV stays as it is.

## Decisions
- JSON is added next to CSV, not instead of it, because accountants still read the CSV.
- Amounts in JSON are integers in cents, so no rounding happens in the export.

## Acceptance criteria
- When an account is exported to JSON, then every order of that account is in the array, including free orders (total 0).
- When an account is exported to JSON, then no order of another account is in it.

## Plan
- [ ] 1. Add `exportOrdersJson(orders, accountId)` in `src/export/json.mjs` returning a JSON string of `{ id, status, totalCents, date }` — test: `test/json.test.mjs`
- [ ] 2. Cover both acceptance criteria with tests — `npm test`
EOF
    commit_main "docs(specs): accept JSON export spec"
    ;;
  20)
    # A finished worktree with the free-orders fix staged, ready to ship.
    g worktree add -q -b fix/free-orders "$RUN/app.worktrees/free-orders" main
    W="$RUN/app.worktrees/free-orders"
    sed -i.bak '/\.filter((o) => o.total);/d; s/\.filter((o) => o.accountId === accountId)$/.filter((o) => o.accountId === accountId);/' "$W/src/export/csv.mjs" && rm "$W/src/export/csv.mjs.bak"
    cat >> "$W/test/csv.test.mjs" <<'EOF'

test('includes free orders', () => {
  assert.ok(exportOrders(orders, 'a1').includes('\n2,paid,'));
});
EOF
    git -C "$W" add -A
    ;;
  21)
    # A product brief that rules JSON export out, and a branch that adds it anyway.
    mkdir -p "$APP/.ai/specs"
    cat > "$APP/.ai/specs/product-brief.md" <<'EOF'
# bench-app — product brief
Date: 2026-10-01 · Owner: ops lead

## Scope
- **Now:** the CSV export for accountants, correct to the cent.
- **Not doing:** a JSON or API export of orders — accountants only read CSV, and every extra format is a second contract to keep in sync. Decided by the ops lead, 2026-10-01.
EOF
    commit_main "docs: product brief"
    g checkout -qb feat/json-export
    cat > "$APP/src/export/json.mjs" <<'EOF'
export function exportOrdersJson(orders, accountId) {
  return JSON.stringify(orders.filter((o) => o.accountId === accountId));
}
EOF
    cat > "$APP/test/json.test.mjs" <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { exportOrdersJson } from '../src/export/json.mjs';
import { orders } from '../src/db.mjs';

test('exports one account as JSON', () => {
  assert.equal(JSON.parse(exportOrdersJson(orders, 'a2')).length, 2);
});
EOF
    g add -A && g commit -qm "feat(export): JSON export" && g push -q origin feat/json-export
    g checkout -q main
    ;;
  22)
    # A worktree whose staged change imports a new, still untracked module that leaks across accounts.
    g worktree add -q -b feat/order-search "$RUN/app.worktrees/order-search" main
    W="$RUN/app.worktrees/order-search"
    cat >> "$W/src/api/orders.mjs" <<'EOF'

export { searchOrders } from './search.mjs';
EOF
    git -C "$W" add src/api/orders.mjs
    cat > "$W/src/api/search.mjs" <<'EOF'
import { orders } from '../db.mjs';

export function searchOrders(user, text) {
  return orders.filter((o) => String(o.id).includes(text) || o.status.includes(text));
}
EOF
    ;;
  23)
    # The free-orders bug was fixed once, then a refactor brought it back.
    sed -i.bak 's/\.filter((o) => o.total);/.filter((o) => o.total !== undefined);/' "$APP/src/export/csv.mjs" && rm "$APP/src/export/csv.mjs.bak"
    commit_main "fix(export): include free orders in the CSV export (#12)"
    sed -i.bak 's/\.filter((o) => o.total !== undefined);/.filter((o) => o.total);/' "$APP/src/export/csv.mjs" && rm "$APP/src/export/csv.mjs.bak"
    commit_main "refactor(export): simplify the export filters"
    ;;
  27)
    # A repo set up with the om-* skills: config, process doc, run log, an old spec, an installed om skill.
    mkdir -p "$APP/.ai/specs" "$APP/.ai/runs" "$APP/.agents/skills/om-code-review"
    cat > "$APP/.ai/agentic.config.json" <<'EOF'
{ "baseBranch": "main", "tracker": "github", "validation": { "commands": ["npm run lint", "npm test"] },
  "labels": { "enabled": true }, "paths": { "specs": ".ai/specs", "runs": ".ai/runs" } }
EOF
    printf '# .ai — om pipeline memory\n\nOriginal om README; must survive the migration unchanged.\n' > "$APP/.ai/README.md"
    printf '# Run 2026-10-02 — csv export\n\n## Progress\n- [x] 1.1 export — 1a2b3c\n' > "$APP/.ai/runs/2026-10-02-csv-export.md"
    printf '# CSV export\n\nStatus: implemented\n\n## 📋 Implementation Plan\n- [x] Phase 1: export one account\n' > "$APP/.ai/specs/2026-10-01-csv-export.md"
    cat > "$APP/SDLC.md" <<'EOF'
# Software delivery process

## Roles
- The ops lead owns product decisions; any engineer may merge after review.

## Definition of Ready
- The problem, who has it, and how we check the outcome are written down.

## Label state machine
- `review` → `qa` → `merge-queue`; `in-progress` is the claim lock.

## The claim protocol
- Agents claim an issue with `refs/om-locks/*` before work.
EOF
    printf -- '---\nname: om-code-review\ndescription: Review code changes (om).\n---\n# om-code-review\n' > "$APP/.agents/skills/om-code-review/SKILL.md"
    cat > "$APP/AGENTS.md" <<'EOF'
# bench-app

A tiny orders service with a CSV export. No dependencies; Node 20+.

Read [README.md](README.md) for the export format: amounts are always two decimals.

Follow the process in [SDLC.md](SDLC.md). Pipeline config: `.ai/agentic.config.json`. Use `om-code-review` for reviews.
EOF
    g add -f .agents/skills/om-code-review   # run.sh excludes .agents/skills/ in the "with" mode
    commit_main "chore: om pipeline setup"
    ;;
esac
