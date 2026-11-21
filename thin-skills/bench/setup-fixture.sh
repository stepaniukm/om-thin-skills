#!/usr/bin/env bash
# Creates a throwaway benchmark fixture: <dir>/origin.git (bare "remote") and <dir>/app (checkout).
# Planted problems:
#   - bug: free orders (total 0) are missing from the CSV export          (src/export/csv.mjs)
#   - unrelated bug in the same file: formatAmount drops the second decimal
#   - pre-existing lint failure on main: console.log in src/legacy/notify.mjs
#   - branch feat/order-list: listOrders() ignores the caller's account (cross-account leak)
set -euo pipefail

DIR=${1:?usage: setup-fixture.sh <dir>}
rm -rf "$DIR"
mkdir -p "$DIR/app"
DIR=$(cd "$DIR" && pwd)
APP="$DIR/app"

git init -q --bare -b main "$DIR/origin.git"
cd "$APP"
git init -q -b main
git config user.email bench@example.invalid
git config user.name bench
git config commit.gpgsign false

mkdir -p src/export src/api src/legacy scripts test

cat > package.json <<'EOF'
{
  "name": "bench-app",
  "private": true,
  "type": "module",
  "scripts": {
    "lint": "node scripts/lint.mjs",
    "test": "node --test"
  }
}
EOF

cat > README.md <<'EOF'
# bench-app

A tiny orders service. Orders live in memory; the only integration is a CSV export.

## CSV export format

The export is consumed by accountants, so the column types are fixed:

| Column | Type | Example |
|---|---|---|
| `id` | integer | `3` |
| `status` | `paid` or `open` | `open` |
| `total` | amount in PLN, **always two decimals** | `19.99` |
| `date` | `YYYY-MM-DD` | `2026-01-07` |

Amounts are stored in cents in [src/db.mjs](src/db.mjs) and formatted for export.
EOF

cat > AGENTS.md <<'EOF'
# bench-app

A tiny orders service with a CSV export. No dependencies; Node 20+.

Read [README.md](README.md) for the export format: amounts are always two decimals.

## Workflow
- Base branch: main
- Specs: .ai/specs
- Install: none
- Validation (in order):
  - npm run lint
  - npm test
EOF

cat > src/db.mjs <<'EOF'
export const orders = [
  { id: 1, accountId: 'a1', status: 'paid', total: 1999, createdAt: Date.UTC(2026, 0, 5) },
  { id: 2, accountId: 'a1', status: 'paid', total: 0, createdAt: Date.UTC(2026, 0, 6) },
  { id: 3, accountId: 'a2', status: 'open', total: 4500, createdAt: Date.UTC(2026, 0, 7) },
  { id: 4, accountId: 'a2', status: 'paid', total: 120, createdAt: Date.UTC(2026, 0, 8) },
];
EOF

cat > src/export/csv.mjs <<'EOF'
// CSV export of orders for one account.
export function formatAmount(cents) {
  return (cents / 100).toFixed(1);
}

export function formatDate(ts) {
  return new Date(ts).toISOString().slice(0, 10);
}

export function exportOrders(orders, accountId) {
  const rows = orders
    .filter((o) => o.accountId === accountId)
    .filter((o) => o.total);
  const lines = rows.map((o) => [o.id, o.status, formatAmount(o.total), formatDate(o.createdAt)].join(','));
  return ['id,status,total,date', ...lines].join('\n');
}
EOF

cat > src/api/orders.mjs <<'EOF'
import { orders } from '../db.mjs';

export function getOrder(user, id) {
  const order = orders.find((o) => o.id === id && o.accountId === user.accountId);
  if (!order) throw new Error('not found');
  return order;
}
EOF

cat > src/legacy/notify.mjs <<'EOF'
export function notify(message) {
  console.log(`[notify] ${message}`);
}
EOF

cat > scripts/lint.mjs <<'EOF'
// Minimal lint: forbid console.log in src/.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const offenders = [];
const walk = (dir) => {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path);
    else if (path.endsWith('.mjs') && readFileSync(path, 'utf8').includes('console.log')) offenders.push(path);
  }
};
walk('src');
if (offenders.length) {
  console.error(`lint: console.log is not allowed in:\n  ${offenders.join('\n  ')}`);
  process.exit(1);
}
console.log('lint: ok');
EOF

cat > test/csv.test.mjs <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { exportOrders } from '../src/export/csv.mjs';
import { orders } from '../src/db.mjs';

test('exports only the requested account', () => {
  const csv = exportOrders(orders, 'a2');
  assert.match(csv, /^id,status,total,date/);
  assert.ok(csv.includes('\n3,open,'));
  assert.ok(!csv.includes('\n1,'));
});
EOF

cat > test/orders.test.mjs <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getOrder } from '../src/api/orders.mjs';

test('getOrder refuses another account', () => {
  assert.throws(() => getOrder({ accountId: 'a1' }, 3), /not found/);
});
EOF

git add -A
git commit -qm "initial: orders service with CSV export"
git remote add origin "$DIR/origin.git"
git push -q origin main

# Branch for the review scenario: adds a list endpoint that leaks across accounts.
git checkout -qb feat/order-list
cat >> src/api/orders.mjs <<'EOF'

export function listOrders(user, { status } = {}) {
  return orders.filter((o) => !status || o.status === status);
}
EOF
cat >> test/orders.test.mjs <<'EOF'

import { listOrders } from '../src/api/orders.mjs';

test('listOrders filters by status', () => {
  const paid = listOrders({ accountId: 'a1' }, { status: 'paid' });
  assert.ok(paid.every((o) => o.status === 'paid'));
});
EOF
git commit -qam "feat(api): list orders with an optional status filter"
git push -q origin feat/order-list
git checkout -q main

echo "$APP"
