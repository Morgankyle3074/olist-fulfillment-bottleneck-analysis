DROP VIEW IF EXISTS vw_order_metrics;
DROP VIEW IF EXISTS vw_throughput_daily;

CREATE VIEW vw_order_metrics AS
SELECT
  o.order_id,
  o.customer_id,
  o.order_purchase_timestamp::date AS order_date,

  EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp))/3600.0
    AS approval_time_hours,

  EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at))/3600.0
    AS processing_time_hours,

  EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date))/3600.0
    AS last_mile_time_hours,

  EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))/3600.0
    AS total_cycle_time_hours,

  CASE
    WHEN o.order_delivered_customer_date IS NOT NULL
     AND o.order_estimated_delivery_date IS NOT NULL
     AND o.order_delivered_customer_date > o.order_estimated_delivery_date
    THEN 1 ELSE 0
  END AS late_flag

FROM orders o
WHERE o.order_status = 'delivered';

CREATE VIEW vw_throughput_daily AS
SELECT
  order_date,
  COUNT(*) AS delivered_orders,
  AVG(late_flag)::numeric(10,4) AS late_rate,
  AVG(total_cycle_time_hours)::numeric(10,2) AS avg_cycle_hours,
  AVG(processing_time_hours)::numeric(10,2) AS avg_processing_hours
FROM vw_order_metrics
GROUP BY order_date
ORDER BY order_date;