# Example: Bursted Store Operating Report

A two-page, US Letter, pixel-perfect report rendered once per store and
delivered to that store's manager. It is built on the Cold Provisions schema in
the Sigma Sample Database (`EXAMPLES.COLD_PROVISIONS`: `ORDERS`, `STORES`,
`EMPLOYEES`), so it runs in any org that has the sample connection.

Live-proven on 2026-10-16: verify, create, seven full-document PUTs, readback,
and populated PDF exports for three stores, with headline values matched
against direct warehouse queries. The schedule bodies are drafted from the
OpenAPI and were not created. See
[`reference/workflows/burst.md`](../../reference/workflows/burst.md).

## What it shows

**Page 1, Summary**
- Branded header with an SVG logo, and per-page footers with "Page X of 2".
- A data-generated "At a glance" sentence.
- Six KPI cards with direction-aware deltas vs. prior month.
- A scorecard comparing this month, prior month, same month last year, and the
  region peer average, with green/red for favorable/unfavorable moves.
- Daily net sales bars against a same-day-last-year line.

**Page 2, Sales detail**
- Channel table with share tint, payment mix, sales by hour of day (scale
  color), day-of-week heat table, refunds by reason, and four order-quality
  KPIs.

**Bursting**
- A single-select `store` control filters all nine custom-SQL sources on a
  hidden data page.
- The recipient is the store manager, falling back to the store inbox when a
  store has no manager.

## Files

| File | Purpose |
|---|---|
| `build.rb` | Composes the report with `ReportSpec::Builder` and writes a create envelope. Never calls the API. |
| `sql.rb` | Snowflake SQL contracts. Periods resolve from `CURRENT_DATE`, so the report always covers the last completed month. |
| `recipients.sql` | Store → recipient query with the manager/inbox fallback. |
| `draft-burst-schedules.rb` | Drafts one schedule body per store, in test mode unless `--live`. Never calls the API. |

## Run it

```bash
cd sigma-reports/examples/store-operating-report
ruby build.rb --folder-id <folder-id> --connection-id <sample-db-connection-id> \
  --output /tmp/store-report.json
ruby ../../scripts/validate-spec.rb --mode create /tmp/store-report.json
jq -c . /tmp/store-report.json > /tmp/store-report.min.json   # see "Compact bodies" in SKILL.md
# then /v2/reports/spec/verify, and POST /v2/reports/spec once the destination is approved
```

Export a sample store, then draft the burst:

```bash
ruby draft-burst-schedules.rb --recipients recipients.csv \
  --test-email you@example.com --output /tmp/burst-schedules.json
```

## Demo prompt

To rebuild this live, for example while recording a demo, give an agent with
this skill installed:

```text
Use the sigma-reports skill to build a pixel-perfect, bursted report in my Sigma
org from the Cold Provisions schema in the Sigma Sample Database
(EXAMPLES.COLD_PROVISIONS: ORDERS, STORES, EMPLOYEES). Follow
examples/store-operating-report and reference/workflows/burst.md.

"Cold Provisions — Monthly Store Operating Report": US Letter portrait, 2 pages,
one copy per store, always for the last completed month.

Page 1: branded header and logo, store/manager details, a data-generated "At a
glance" sentence, 6 KPI cards with direction-aware vs-prior-month deltas, a
scorecard (this month / prior month / same month LY / region peer avg) with
green/red favorable moves, and daily net sales vs same day last year.

Page 2: sales by channel, payment mix, sales by hour, day of week, refunds by
reason, and order-quality KPIs. Footer on each page: "Confidential — prepared
for <store>" and "Page X of 2".

Bursting: a single-select Store control filtering every source. Recipient = the
store manager, falling back to the store inbox.

Put it in my My Documents folder, export PDFs for ST001, ST021 and ST015, show
me each page, and check the headline numbers against a direct warehouse query.
Draft the burst schedules but do NOT create them, and route every test copy to
<your test inbox>.
```

## Data notes

- Net sales = `ORDER_SUBTOTAL_USD - ORDER_DISCOUNT_USD` on completed orders.
  Refunds come from `ORDER_STATUS = 'refunded'` (`REFUND_AMOUNT_USD`,
  `VOID_REASON`).
- `EMPLOYEES.EMPLOYEE_ID` is not unique. Join managers on `ROLE = 'manager'`
  and the same `STORE_ID`. 13 of 57 stores have no manager and use the inbox
  fallback.
- Region peer average = mean of the other stores in the region. Region + tier
  cells can contain a single store, which would compare the store with itself.
- `ORDERS` holds about 8M rows, so every source pre-aggregates to the store
  grain in SQL.
