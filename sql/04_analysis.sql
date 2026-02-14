-- ============================================================
-- OLIST FULFILLMENT ANALYSIS
-- Business Focus: Throughput, Bottlenecks, Service Degradation
-- ============================================================



-- ============================================================
-- SECTION 1: EXECUTIVE KPI SUMMARY
-- Purpose: Establish baseline system performance
-- ============================================================

SELECT
    AVG(approval_time_hours)::numeric(10,2)     AS avg_approval_hrs,
    AVG(processing_time_hours)::numeric(10,2)   AS avg_processing_hrs,
    AVG(last_mile_time_hours)::numeric(10,2)    AS avg_last_mile_hrs,
    AVG(total_cycle_time_hours)::numeric(10,2)  AS avg_total_cycle_hrs
FROM vw_order_metrics;



-- ============================================================
-- SECTION 2: FAILURE DECOMPOSITION
-- Purpose: Compare system behavior for Late vs On-Time Orders
-- ============================================================

SELECT
    late_flag,

    AVG(approval_time_hours)::numeric(10,2)     AS avg_approval_hrs,
    AVG(processing_time_hours)::numeric(10,2)   AS avg_processing_hrs,
    AVG(last_mile_time_hours)::numeric(10,2)    AS avg_last_mile_hrs,
    AVG(total_cycle_time_hours)::numeric(10,2)  AS avg_total_cycle_hrs,

    COUNT(*) AS orders

FROM vw_order_metrics
GROUP BY late_flag
ORDER BY late_flag;



-- ============================================================
-- SECTION 3: THROUGHPUT & CONGESTION MONITORING
-- Purpose: Detect load-driven degradation patterns
-- Technique: Rolling Window Analytics
-- ============================================================

SELECT
    order_date,
    delivered_orders,
    late_rate,
    avg_processing_hours,
    avg_cycle_hours,

    AVG(delivered_orders) OVER (
        ORDER BY order_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS orders_7d_avg,

    AVG(late_rate) OVER (
        ORDER BY order_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS late_7d_avg,

    AVG(avg_cycle_hours) OVER (
        ORDER BY order_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS cycle_7d_avg

FROM vw_throughput_daily
ORDER BY order_date;



-- ============================================================
-- SECTION 4: GEOGRAPHIC PERFORMANCE VARIANCE
-- Purpose: Identify regional fulfillment risk
-- ============================================================

SELECT
    c.customer_state,

    COUNT(*) AS orders,

    AVG(v.late_flag)::numeric(10,4)           AS late_rate,
    AVG(v.last_mile_time_hours)::numeric(10,2) AS avg_last_mile_hrs,
    AVG(v.total_cycle_time_hours)::numeric(10,2) AS avg_cycle_hrs,

    RANK() OVER (
        ORDER BY AVG(v.late_flag) DESC
    ) AS delay_rank

FROM vw_order_metrics v
JOIN customers c
    ON v.customer_id = c.customer_id

GROUP BY c.customer_state
ORDER BY late_rate DESC;



-- ============================================================
-- SECTION 5: REVENUE AT RISK ANALYSIS
-- Purpose: Quantify financial exposure from late deliveries
-- ============================================================

WITH order_value AS (
    SELECT
        oi.order_id,
        SUM(oi.price + oi.freight_value) AS order_gmv
    FROM order_items oi
    GROUP BY oi.order_id
),

late_orders AS (
    SELECT
        v.order_id,
        v.late_flag
    FROM vw_order_metrics v
)

SELECT
    COUNT(*) FILTER (WHERE l.late_flag = 1) AS late_orders,
    COUNT(*) AS total_orders,

    SUM(ov.order_gmv) FILTER (WHERE l.late_flag = 1)::numeric(12,2) AS gmv_late,
    SUM(ov.order_gmv)::numeric(12,2) AS gmv_total,

    (SUM(ov.order_gmv) FILTER (WHERE l.late_flag = 1)
        / NULLIF(SUM(ov.order_gmv),0))::numeric(10,4) AS pct_gmv_late

FROM late_orders l
JOIN order_value ov
    ON l.order_id = ov.order_id;



-- ============================================================
-- SECTION 6: CATEGORY-LEVEL DEGRADATION DRIVERS
-- Purpose: Identify product categories most impacted by delays
-- ============================================================

WITH category_metrics AS (
    SELECT
        p.product_category_name,
        v.late_flag,
        AVG(v.last_mile_time_hours) AS avg_last_mile_hrs,
        COUNT(*) AS orders
    FROM vw_order_metrics v
    JOIN order_items oi ON v.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY p.product_category_name, v.late_flag
),

pivoted AS (
    SELECT
        product_category_name,

        MAX(CASE WHEN late_flag = 0 THEN avg_last_mile_hrs END) AS lastmile_on_time,
        MAX(CASE WHEN late_flag = 1 THEN avg_last_mile_hrs END) AS lastmile_late,

        MAX(CASE WHEN late_flag = 0 THEN orders END) AS orders_on_time,
        MAX(CASE WHEN late_flag = 1 THEN orders END) AS orders_late

    FROM category_metrics
    GROUP BY product_category_name
)

SELECT
    product_category_name,
    orders_on_time,
    orders_late,

    lastmile_on_time::numeric(10,2),
    lastmile_late::numeric(10,2),

    (lastmile_late - lastmile_on_time)::numeric(10,2) AS delay_delta,

    RANK() OVER (
        ORDER BY (lastmile_late - lastmile_on_time) DESC
    ) AS degradation_rank

FROM pivoted
WHERE orders_late IS NOT NULL
ORDER BY degradation_rank
LIMIT 20;


-- ============================================================
-- 07_tableau_exports.sql
-- Creates an enriched view for Tableau + export commands
-- ============================================================

DROP VIEW IF EXISTS vw_order_enrichment;

CREATE VIEW vw_order_enrichment AS
WITH item_agg AS (
  SELECT
    oi.order_id,
    COUNT(*) AS items_per_order,
    COUNT(DISTINCT oi.seller_id) AS sellers_per_order,
    COUNT(DISTINCT oi.product_id) AS products_per_order,
    SUM(oi.price) AS items_value,
    SUM(oi.freight_value) AS freight_value,
    SUM(oi.price + oi.freight_value) AS order_value
  FROM order_items oi
  GROUP BY oi.order_id
)
SELECT
  om.order_id,
  om.customer_id,
  om.order_date,
  om.late_flag,

  om.approval_time_hours,
  om.processing_time_hours,
  om.last_mile_time_hours,
  om.total_cycle_time_hours,

  -- driver metrics (order complexity + $$)
  ia.items_per_order,
  ia.sellers_per_order,
  ia.products_per_order,
  ia.items_value,
  ia.freight_value,
  ia.order_value,
  (ia.freight_value / NULLIF(ia.items_value, 0)) AS freight_ratio,

  -- geo
  c.customer_state,

  -- severity metric (days late / early)
  (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS delivery_delay_days

FROM vw_order_metrics om
JOIN orders o
  ON o.order_id = om.order_id
LEFT JOIN item_agg ia
  ON ia.order_id = om.order_id
LEFT JOIN customers c
  ON c.customer_id = om.customer_id;




