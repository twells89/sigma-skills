# frozen_string_literal: true

# SQL data contracts for the store operating report example. Every statement is
# Snowflake SQL against the Cold Provisions sample schema and returns one or
# more rows per STORE_ID, so a single report-level store control can filter all
# of them. Periods resolve from CURRENT_DATE: "cur" is the last completed
# calendar month, "pm" the month before it, and "ly" the same month last year.

# Override to point the example at a copy of the schema.
DB = ENV.fetch('STORE_REPORT_SCHEMA', 'EXAMPLES.COLD_PROVISIONS')

PARAMS = <<~SQL.strip
  p AS (
    SELECT DATEADD(month, -1, DATE_TRUNC('month', CURRENT_DATE())) AS m_start,
           DATE_TRUNC('month', CURRENT_DATE()) AS m_end
  )
SQL

# One row per store: current month, prior month, same month last year, peers.
STORE_CTES = <<~SQL.strip
  #{PARAMS},
  mgr AS (
    SELECT STORE_ID, EMPLOYEE_ID, EMPLOYEE_NAME, EMAIL
    FROM #{DB}.EMPLOYEES
    WHERE ROLE = 'manager'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY STORE_ID, EMPLOYEE_ID ORDER BY HIRE_DATE DESC) = 1
  ),
  o AS (
    SELECT o.STORE_ID,
      CASE WHEN o.ORDER_LOCAL_DATE >= p.m_start THEN 'cur'
           WHEN o.ORDER_LOCAL_DATE >= DATEADD(month, -1, p.m_start) THEN 'pm'
           WHEN o.ORDER_LOCAL_DATE < DATEADD(year, -1, p.m_end) THEN 'ly'
      END AS per,
      o.ORDER_STATUS, o.ORDER_SUBTOTAL_USD, o.ORDER_DISCOUNT_USD, o.TIP_AMOUNT_USD,
      o.REFUND_AMOUNT_USD, o.COUPON_CODE
    FROM #{DB}.ORDERS o CROSS JOIN p
    WHERE o.ORDER_LOCAL_DATE >= DATEADD(year, -1, p.m_start) AND o.ORDER_LOCAL_DATE < p.m_end
  ),
  a AS (
    SELECT STORE_ID,
  #{%w[cur pm ly].map { |q| <<~Q.chomp }.join(",\n")}
      SUM(IFF(per = '#{q}' AND ORDER_STATUS = 'completed', ORDER_SUBTOTAL_USD - ORDER_DISCOUNT_USD, 0)) AS #{q}_net,
      COUNT_IF(per = '#{q}' AND ORDER_STATUS = 'completed') AS #{q}_orders,
      SUM(IFF(per = '#{q}' AND ORDER_STATUS = 'completed', ORDER_DISCOUNT_USD, 0)) AS #{q}_disc,
      SUM(IFF(per = '#{q}' AND ORDER_STATUS = 'completed', ORDER_SUBTOTAL_USD, 0)) AS #{q}_gross,
      SUM(IFF(per = '#{q}' AND ORDER_STATUS = 'refunded', COALESCE(REFUND_AMOUNT_USD, 0), 0)) AS #{q}_refunds,
      COUNT_IF(per = '#{q}' AND ORDER_STATUS = 'refunded') AS #{q}_refund_cnt,
      SUM(IFF(per = '#{q}' AND ORDER_STATUS = 'completed', TIP_AMOUNT_USD, 0)) AS #{q}_tips,
      COUNT_IF(per = '#{q}' AND ORDER_STATUS = 'completed' AND COUPON_CODE IS NOT NULL) AS #{q}_coupons
  Q
    FROM o WHERE per IS NOT NULL
    GROUP BY 1
  ),
  s AS (
    SELECT st.STORE_ID, st.STORE_NAME, st.REGION, INITCAP(st.TIER) AS TIER,
      st.ADDRESS, st.CITY, st.STATE, st.POSTAL_CODE, st.STORE_PHONE, st.STORE_EMAIL,
      m.EMPLOYEE_NAME AS MANAGER_NAME, m.EMAIL AS MANAGER_EMAIL,
  #{%w[cur pm ly].map { |q| <<~Q.chomp }.join(",\n")}
      COALESCE(a.#{q}_net, 0) AS #{q}_net, COALESCE(a.#{q}_orders, 0) AS #{q}_orders,
      a.#{q}_net / NULLIF(a.#{q}_orders, 0) AS #{q}_ticket,
      a.#{q}_disc / NULLIF(a.#{q}_gross, 0) AS #{q}_disc_rate,
      a.#{q}_coupons / NULLIF(a.#{q}_orders, 0) AS #{q}_coupon_rate,
      COALESCE(a.#{q}_tips, 0) AS #{q}_tips, COALESCE(a.#{q}_refunds, 0) AS #{q}_refunds,
      COALESCE(a.#{q}_refund_cnt, 0) AS #{q}_refund_cnt,
      a.#{q}_refund_cnt / NULLIF(a.#{q}_orders + a.#{q}_refund_cnt, 0) AS #{q}_refund_rate
  Q
    FROM #{DB}.STORES st
    LEFT JOIN mgr m ON m.EMPLOYEE_ID = st.STORE_MANAGER_ID AND m.STORE_ID = st.STORE_ID
    LEFT JOIN a ON a.STORE_ID = st.STORE_ID
  )
SQL

METRICS = [
  # key, label, display format, direction (1 = higher is better, -1 = lower is better)
  ['net', 'Net sales', 'usd0', 1],
  ['orders', 'Orders', 'int', 1],
  ['ticket', 'Average ticket', 'usd2', 1],
  ['disc_rate', 'Discount rate', 'pct', -1],
  ['coupon_rate', 'Coupon redemption', 'pct', 1],
  ['tips', 'Tips', 'usd0', 1],
  ['refunds', 'Refunds ($)', 'usd0', -1],
  ['refund_rate', 'Refund rate', 'pct', -1],
].freeze

def fmt_sql(expr, fmt)
  case fmt
  when 'usd0' then "'$' || TRIM(TO_CHAR(#{expr}, '999,999,990'))"
  when 'usd2' then "'$' || TRIM(TO_CHAR(#{expr}, '999,990.00'))"
  when 'int' then "TRIM(TO_CHAR(#{expr}, '999,999,990'))"
  when 'pct' then "TRIM(TO_CHAR(#{expr} * 100, '990.0')) || '%'"
  end
end

SUMMARY_SQL = <<~SQL
  WITH #{STORE_CTES},
  f AS (
    SELECT s.*, p.m_start,
      (SUM(s.cur_net) OVER (PARTITION BY s.REGION) - s.cur_net)
        / NULLIF(COUNT(*) OVER (PARTITION BY s.REGION) - 1, 0) AS peer_net_v,
      (SUM(s.cur_ticket) OVER (PARTITION BY s.REGION) - COALESCE(s.cur_ticket, 0))
        / NULLIF(COUNT(s.cur_ticket) OVER (PARTITION BY s.REGION) - 1, 0) AS peer_ticket_v,
      RANK() OVER (PARTITION BY s.REGION ORDER BY s.cur_net DESC) AS rank_v,
      COUNT(*) OVER (PARTITION BY s.REGION) AS region_n_v
    FROM s CROSS JOIN p
  ),
  -- Optional headline clauses. Each is NULL when its inputs are missing, so the
  -- sentence drops that clause instead of '||' nulling the whole headline.
  h AS (
    SELECT f.*,
      IFF(f.pm_net > 0,
          IFF(f.cur_net >= f.pm_net, ' were up ', ' were down ')
            || #{fmt_sql('ABS(f.cur_net / NULLIF(f.pm_net, 0) - 1)', 'pct')}
            || ' vs ' || TO_CHAR(DATEADD(month, -1, f.m_start), 'MMMM'),
          NULL) AS pm_clause,
      IFF(f.ly_net > 0,
          IFF(f.cur_net >= f.ly_net, 'up ', 'down ')
            || #{fmt_sql('ABS(f.cur_net / NULLIF(f.ly_net, 0) - 1)', 'pct')}
            || ' vs ' || TO_CHAR(DATEADD(year, -1, f.m_start), 'MMMM YYYY'),
          NULL) AS ly_clause,
      '. Average ticket was ' || #{fmt_sql('f.cur_ticket', 'usd2')}
        || COALESCE(IFF(f.cur_ticket >= f.peer_ticket_v, ', above', ', below')
                    || ' the ' || f.REGION || ' peer average of ' || #{fmt_sql('f.peer_ticket_v', 'usd2')}, '')
        AS ticket_clause
    FROM f
  )
  SELECT
    s.STORE_ID AS "store_id",
    s.STORE_NAME AS "store_name",
    s.REGION AS "region",
    s.TIER AS "tier",
    s.ADDRESS || ', ' || s.CITY || ', ' || s.STATE || ' ' || s.POSTAL_CODE AS "address_line",
    s.STORE_PHONE AS "store_phone",
    COALESCE(s.MANAGER_NAME, s.STORE_NAME || ' store team') AS "manager_name",
    COALESCE(s.MANAGER_EMAIL, s.STORE_EMAIL) AS "recipient_email",
    IFF(s.MANAGER_EMAIL IS NULL, 'store inbox', 'store manager') AS "recipient_type",
    TO_CHAR(s.m_start, 'MMMM YYYY') AS "report_month",
    TO_CHAR(DATEADD(month, -1, s.m_start), 'MMMM') AS "pm_label",
    TO_CHAR(DATEADD(year, -1, s.m_start), 'MMMM YYYY') AS "ly_label",
    'Net sales of ' || #{fmt_sql('s.cur_net', 'usd0')}
      || CASE
           WHEN s.pm_clause IS NOT NULL AND s.ly_clause IS NOT NULL THEN s.pm_clause || ' and ' || s.ly_clause
           WHEN s.pm_clause IS NOT NULL THEN s.pm_clause
           WHEN s.ly_clause IS NOT NULL THEN ' were ' || s.ly_clause
           ELSE ''
         END
      || COALESCE(s.ticket_clause || ', and the store ranked #', '. The store ranked #')
      || s.rank_v || ' of ' || s.region_n_v || ' in the region on net sales.' AS "headline",
  #{METRICS.flat_map { |k, *| %w[cur pm ly].map { |q| "  s.#{q}_#{k} AS \"#{q}_#{k}\"" } }.join(",\n")},
    s.cur_refund_cnt AS "cur_refund_cnt",
    s.pm_refund_cnt AS "pm_refund_cnt",
    s.peer_net_v AS "peer_net",
    s.peer_ticket_v AS "peer_ticket",
    s.region_n_v - 1 AS "peer_n",
    s.rank_v AS "region_rank",
    s.region_n_v AS "region_n"
  FROM h s
SQL

SCORECARD_SQL = <<~SQL
  WITH #{STORE_CTES},
  peer AS (
    SELECT s.*,
  #{METRICS.map { |k, *| "    (SUM(s.cur_#{k}) OVER (PARTITION BY s.REGION) - COALESCE(s.cur_#{k}, 0)) / NULLIF(COUNT(s.cur_#{k}) OVER (PARTITION BY s.REGION) - IFF(s.cur_#{k} IS NULL, 0, 1), 0) AS peer_#{k}" }.join(",\n")}
    FROM s
  ),
  u AS (
  #{METRICS.each_with_index.map { |(k, label, fmt, dir), i| <<~Q.chomp }.join("\n    UNION ALL\n")}
      SELECT STORE_ID, #{i + 1} AS sort_order, '#{label}' AS metric, '#{fmt}' AS fmt, #{dir} AS dir,
        cur_#{k} AS cur_v, pm_#{k} AS pm_v, ly_#{k} AS ly_v, peer_#{k} AS peer_v
      FROM peer
  Q
  )
  SELECT
    STORE_ID AS "store_id",
    sort_order AS "sort_order",
    metric AS "metric",
    CASE fmt
  #{%w[usd0 usd2 int pct].map { |f| "    WHEN '#{f}' THEN #{fmt_sql('cur_v', f)}" }.join("\n")}
    END AS "this_month",
    CASE fmt
  #{%w[usd0 usd2 int pct].map { |f| "    WHEN '#{f}' THEN #{fmt_sql('pm_v', f)}" }.join("\n")}
    END AS "prior_month",
    (cur_v - pm_v) / NULLIF(pm_v, 0) AS "vs_prior_month",
    SIGN(cur_v - pm_v) * dir AS "pm_signal",
    CASE fmt
  #{%w[usd0 usd2 int pct].map { |f| "    WHEN '#{f}' THEN #{fmt_sql('ly_v', f)}" }.join("\n")}
    END AS "last_year",
    (cur_v - ly_v) / NULLIF(ly_v, 0) AS "vs_last_year",
    SIGN(cur_v - ly_v) * dir AS "ly_signal",
    SIGN(cur_v - peer_v) * dir AS "peer_signal",
    CASE fmt
  #{%w[usd0 usd2 int pct].map { |f| "    WHEN '#{f}' THEN #{fmt_sql('peer_v', f)}" }.join("\n")}
    END AS "peer_avg"
  FROM u
SQL

CUR_COMPLETED = "o.ORDER_STATUS = 'completed' AND o.ORDER_LOCAL_DATE >= p.m_start AND o.ORDER_LOCAL_DATE < p.m_end"

DAILY_SQL = <<~SQL
  WITH #{PARAMS},
  d AS (
    SELECT o.STORE_ID, TO_DATE(o.ORDER_LOCAL_DATE) AS d,
      SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD) AS net, COUNT(*) AS orders
    FROM #{DB}.ORDERS o CROSS JOIN p
    WHERE o.ORDER_STATUS = 'completed'
      AND ((o.ORDER_LOCAL_DATE >= p.m_start AND o.ORDER_LOCAL_DATE < p.m_end)
        OR (o.ORDER_LOCAL_DATE >= DATEADD(year, -1, p.m_start) AND o.ORDER_LOCAL_DATE < DATEADD(year, -1, p.m_end)))
    GROUP BY 1, 2
  )
  SELECT c.STORE_ID AS "store_id", c.d AS "order_date", DAY(c.d) AS "day_of_month",
    c.net AS "net_sales", c.orders AS "orders", l.net AS "ly_net_sales"
  FROM d c CROSS JOIN p
  LEFT JOIN d l ON l.STORE_ID = c.STORE_ID AND l.d = DATEADD(year, -1, c.d)
  WHERE c.d >= p.m_start
SQL

CHANNEL_SQL = <<~SQL
  WITH #{PARAMS}
  SELECT o.STORE_ID AS "store_id",
    CASE o.CHANNEL WHEN 'pos' THEN 'In-store POS' WHEN 'mobile_app' THEN 'Mobile app'
      WHEN 'kiosk' THEN 'Kiosk' ELSE INITCAP(o.CHANNEL) END AS "channel",
    COUNT(*) AS "orders",
    SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD) AS "net_sales",
    SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD) / COUNT(*) AS "avg_ticket",
    SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD)
      / SUM(SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD)) OVER (PARTITION BY o.STORE_ID) AS "share"
  FROM #{DB}.ORDERS o CROSS JOIN p
  WHERE #{CUR_COMPLETED}
  GROUP BY 1, 2
SQL

PAYMENT_SQL = <<~SQL
  WITH #{PARAMS}
  SELECT o.STORE_ID AS "store_id",
    CASE o.PAYMENT_METHOD WHEN 'mobile_wallet' THEN 'Mobile wallet' WHEN 'gift_card' THEN 'Gift card'
      ELSE INITCAP(o.PAYMENT_METHOD) END AS "payment_method",
    COUNT(*) AS "orders",
    SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD) AS "net_sales"
  FROM #{DB}.ORDERS o CROSS JOIN p
  WHERE #{CUR_COMPLETED}
  GROUP BY 1, 2
SQL

HOURLY_SQL = <<~SQL
  WITH #{PARAMS}
  SELECT o.STORE_ID AS "store_id",
    LPAD(o.ORDER_LOCAL_HOUR::STRING, 2, '0') || ':00' AS "hour_label",
    COUNT(*) AS "orders",
    SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD) AS "net_sales"
  FROM #{DB}.ORDERS o CROSS JOIN p
  WHERE #{CUR_COMPLETED}
  GROUP BY 1, 2
SQL

DOW_SQL = <<~SQL
  WITH #{PARAMS}
  SELECT o.STORE_ID AS "store_id",
    DAYOFWEEKISO(o.ORDER_LOCAL_DATE) AS "dow_num",
    DAYNAME(o.ORDER_LOCAL_DATE) AS "day_of_week",
    COUNT(*) AS "orders",
    SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD) AS "net_sales",
    SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD) / COUNT(DISTINCT TO_DATE(o.ORDER_LOCAL_DATE)) AS "avg_daily_sales",
    SUM(o.ORDER_SUBTOTAL_USD - o.ORDER_DISCOUNT_USD) / COUNT(*) AS "avg_ticket"
  FROM #{DB}.ORDERS o CROSS JOIN p
  WHERE #{CUR_COMPLETED}
  GROUP BY 1, 2, 3
SQL

EXCEPTIONS_SQL = <<~SQL
  WITH #{PARAMS}
  SELECT o.STORE_ID AS "store_id",
    COALESCE(o.VOID_REASON, 'Unspecified') AS "reason",
    COUNT(*) AS "refunded_orders",
    SUM(COALESCE(o.REFUND_AMOUNT_USD, 0)) AS "refund_usd"
  FROM #{DB}.ORDERS o CROSS JOIN p
  WHERE o.ORDER_STATUS = 'refunded' AND o.ORDER_LOCAL_DATE >= p.m_start AND o.ORDER_LOCAL_DATE < p.m_end
  GROUP BY 1, 2
SQL

STORE_LIST_SQL = <<~SQL
  SELECT STORE_ID AS "store_id", STORE_ID || ' · ' || STORE_NAME AS "store_label"
  FROM #{DB}.STORES
SQL

