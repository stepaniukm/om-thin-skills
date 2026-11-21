## 2026-11-20 · CSV amounts lose their second decimal
- Source: build export-fix
- Where: [csv.mjs](../src/export/csv.mjs#L3)
- What: formatAmount uses toFixed(1), so 19.99 is exported as 20.0.
- Why it matters: exported totals don't match invoices.
- Status: open

## 2026-11-20 · getOrder returns orders from other accounts
- Source: review
- Where: [orders.mjs](../src/api/orders.mjs#L3)
- What: getOrder looks orders up by id only, without checking the caller's account.
- Why it matters: any user could read another account's order.
- Status: open

## 2026-11-21 · Lint failure in legacy notify helper
- Source: build export-fix
- Where: [notify.mjs](../src/legacy/notify.mjs#L2)
- What: console.log in src/legacy/notify.mjs makes `npm run lint` fail on main.
- Why it matters: every validation run starts red.
- Status: open
