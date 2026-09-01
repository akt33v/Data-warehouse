-- =============================================================================
-- REPORT 2 DATA EXPORT
-- Outputs two CSVs for Python visualisation:
--   1. churn_risk_summary.csv  — roll-up by cohort / type / status / risk tier
--   2. churn_risk_members.csv  — member-level RFM detail (all members)
-- Run from SQL*Plus in the tjy/ directory.
-- =============================================================================
SET HEADING OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 0
SET LINESIZE 600
SET TRIMSPOOL ON
SET COLSEP ''

-- ── CSV 1: ROLL-UP SUMMARY ────────────────────────────────────────────────────
SPOOL tjy/churn_risk_summary.csv

PROMPT cohort_year,member_type,member_status,risk_tier,member_count,avg_recency_days,total_orders,total_revenue,revenue_at_risk,avg_churn_score

WITH ref_date AS (
    SELECT NVL(MAX(d.Full_Date), TRUNC(SYSDATE)) AS max_dw_date
    FROM Fact_Order_Sales f
    JOIN Dim_Date d ON f.Date_Key = d.Date_Key
),
member_base AS (
    SELECT
        m.Member_Key, m.Member_Type, m.Member_Status,
        m.Effective_Date AS registration_date,
        EXTRACT(YEAR FROM m.Effective_Date) AS cohort_year
    FROM dim_member m
    WHERE m.Current_Flag = 'Y'
),
member_rfm AS (
    SELECT
        mb.Member_Key, mb.Member_Type, mb.Member_Status,
        mb.registration_date, mb.cohort_year,
        MAX(dd.Full_Date)               AS last_order_date,
        NVL(COUNT(DISTINCT f.Order_ID), 0) AS total_orders,
        NVL(SUM(f.Total_Amount), 0)     AS total_revenue
    FROM member_base mb
    LEFT JOIN Fact_Order_Sales f ON mb.Member_Key = f.Member_Key
    LEFT JOIN Dim_Date dd        ON f.Date_Key    = dd.Date_Key
    GROUP BY mb.Member_Key, mb.Member_Type, mb.Member_Status,
             mb.registration_date, mb.cohort_year
),
member_scored AS (
    SELECT mr.*,
        CASE
            WHEN mr.last_order_date IS NOT NULL THEN (r.max_dw_date - mr.last_order_date)
            ELSE (r.max_dw_date - mr.registration_date)
        END AS recency_days,
        CASE
            WHEN mr.Member_Status = 'DEACTIVATED' THEN 'Churned'
            WHEN mr.Member_Status = 'SUSPENDED'   THEN 'Suspended'
            WHEN mr.last_order_date IS NULL AND (r.max_dw_date - mr.registration_date) <= 30 THEN 'New - No Order'
            WHEN mr.last_order_date IS NULL       THEN 'Critical'
            WHEN (r.max_dw_date - mr.last_order_date) > 180 THEN 'Critical'
            WHEN (r.max_dw_date - mr.last_order_date) > 90  THEN 'High'
            WHEN (r.max_dw_date - mr.last_order_date) > 60  THEN 'Medium'
            WHEN (r.max_dw_date - mr.last_order_date) > 30  THEN 'Low'
            ELSE 'Healthy'
        END AS risk_tier,
        CASE
            WHEN mr.Member_Status = 'DEACTIVATED' THEN 10.0
            WHEN mr.Member_Status = 'SUSPENDED'   THEN 8.5
            WHEN mr.last_order_date IS NULL       THEN 9.0
            ELSE LEAST(10.0, ROUND(1.0 + ((r.max_dw_date - mr.last_order_date) / 30.0) / GREATEST(mr.total_orders, 1), 1))
        END AS churn_score
    FROM member_rfm mr
    CROSS JOIN ref_date r
)
SELECT
    s.cohort_year              || ','
    || s.Member_Type           || ','
    || s.Member_Status         || ','
    || '"' || s.risk_tier || '"'        || ','
    || COUNT(*)                || ','
    || ROUND(AVG(s.recency_days), 1)    || ','
    || SUM(s.total_orders)     || ','
    || ROUND(SUM(s.total_revenue), 2)   || ','
    || ROUND(SUM(
          s.total_revenue * CASE s.risk_tier
              WHEN 'Churned'   THEN 1.00
              WHEN 'Critical'  THEN 1.00
              WHEN 'Suspended' THEN 0.90
              WHEN 'High'      THEN 0.75
              WHEN 'Medium'    THEN 0.45
              WHEN 'Low'       THEN 0.15
              ELSE 0.00
          END), 2)             || ','
    || ROUND(AVG(s.churn_score), 2)
FROM member_scored s
GROUP BY s.cohort_year, s.Member_Type, s.Member_Status, s.risk_tier
ORDER BY s.cohort_year,
    DECODE(s.Member_Type, 'VIP', 1, 'NORMAL', 2, 3),
    s.Member_Status,
    DECODE(s.risk_tier,
        'Churned', 1, 'Critical', 2, 'High', 3, 'Suspended', 4, 'Medium', 5,
        'Low', 6, 'New - No Order', 7, 'Healthy', 8, 9);

SPOOL OFF

-- ── CSV 2: MEMBER-LEVEL DETAIL ────────────────────────────────────────────────
SPOOL churn_risk_members.csv

PROMPT member_id,member_type,member_status,cohort_year,registration_date,last_order_date,recency_days,total_orders,total_revenue,avg_order_value,risk_tier,churn_score

WITH ref_date AS (
    SELECT NVL(MAX(d.Full_Date), TRUNC(SYSDATE)) AS max_dw_date
    FROM Fact_Order_Sales f
    JOIN Dim_Date d ON f.Date_Key = d.Date_Key
),
member_base AS (
    SELECT
        m.Member_Key, m.Member_ID, m.Member_Type, m.Member_Status,
        m.Effective_Date AS registration_date,
        EXTRACT(YEAR FROM m.Effective_Date) AS cohort_year
    FROM dim_member m
    WHERE m.Current_Flag = 'Y'
),
member_rfm AS (
    SELECT
        mb.Member_Key, mb.Member_ID, mb.Member_Type, mb.Member_Status,
        mb.registration_date, mb.cohort_year,
        MAX(dd.Full_Date)                  AS last_order_date,
        NVL(COUNT(DISTINCT f.Order_ID), 0) AS total_orders,
        NVL(SUM(f.Total_Amount), 0)        AS total_revenue,
        ROUND(NVL(AVG(f.Total_Amount), 0), 2) AS avg_order_value
    FROM member_base mb
    LEFT JOIN Fact_Order_Sales f ON mb.Member_Key = f.Member_Key
    LEFT JOIN Dim_Date dd        ON f.Date_Key    = dd.Date_Key
    GROUP BY mb.Member_Key, mb.Member_ID, mb.Member_Type, mb.Member_Status,
             mb.registration_date, mb.cohort_year
),
member_scored AS (
    SELECT mr.*,
        CASE
            WHEN mr.last_order_date IS NOT NULL THEN (r.max_dw_date - mr.last_order_date)
            ELSE (r.max_dw_date - mr.registration_date)
        END AS recency_days,
        CASE
            WHEN mr.Member_Status = 'DEACTIVATED' THEN 'Churned'
            WHEN mr.Member_Status = 'SUSPENDED'   THEN 'Suspended'
            WHEN mr.last_order_date IS NULL AND (r.max_dw_date - mr.registration_date) <= 30 THEN 'New - No Order'
            WHEN mr.last_order_date IS NULL       THEN 'Critical'
            WHEN (r.max_dw_date - mr.last_order_date) > 180 THEN 'Critical'
            WHEN (r.max_dw_date - mr.last_order_date) > 90  THEN 'High'
            WHEN (r.max_dw_date - mr.last_order_date) > 60  THEN 'Medium'
            WHEN (r.max_dw_date - mr.last_order_date) > 30  THEN 'Low'
            ELSE 'Healthy'
        END AS risk_tier,
        CASE
            WHEN mr.Member_Status = 'DEACTIVATED' THEN 10.0
            WHEN mr.Member_Status = 'SUSPENDED'   THEN 8.5
            WHEN mr.last_order_date IS NULL       THEN 9.0
            ELSE LEAST(10.0, ROUND(1.0 + ((r.max_dw_date - mr.last_order_date) / 30.0) / GREATEST(mr.total_orders, 1), 1))
        END AS churn_score
    FROM member_rfm mr
    CROSS JOIN ref_date r
)
SELECT
    s.Member_ID            || ','
    || s.Member_Type       || ','
    || s.Member_Status     || ','
    || s.cohort_year       || ','
    || TO_CHAR(s.registration_date, 'YYYY-MM-DD') || ','
    || NVL(TO_CHAR(s.last_order_date, 'YYYY-MM-DD'), 'N/A') || ','
    || s.recency_days      || ','
    || s.total_orders      || ','
    || ROUND(s.total_revenue, 2)    || ','
    || s.avg_order_value   || ','
    || '"' || s.risk_tier || '"'    || ','
    || s.churn_score
FROM member_scored s
ORDER BY
    DECODE(s.risk_tier,
        'Churned', 1, 'Critical', 2, 'High', 3, 'Suspended', 4, 'Medium', 5,
        'Low', 6, 'New - No Order', 7, 'Healthy', 8, 9),
    s.churn_score DESC,
    s.total_revenue DESC;

SPOOL OFF

-- Restore defaults
SET COLSEP ' '
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 100
