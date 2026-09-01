-- =============================================================================
-- REPORT 11 DATA EXPORT — DELIVERY PARTNER PERFORMANCE & OPERATIONAL RELIANCE
-- Outputs two CSVs for Python visualisation:
--   1. delivery_quarter_summary.csv — roll-up by company / weekend flag / quarter
--   2. delivery_lifetime_share.csv  — lifetime market share & concentration ranking
-- Run from SQL*Plus in the reports/ directory.
-- =============================================================================
SET HEADING OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 0
SET LINESIZE 600
SET TRIMSPOOL ON
SET COLSEP ''

-- ── CSV 1: QUARTER SUMMARY ────────────────────────────────────────────────────
SPOOL delivery_quarter_summary.csv

PROMPT pv_quarter,company_name,day_flag,order_count,fee_revenue,avg_fee

WITH delivery_sales AS (
    SELECT
        TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
        dc.Company_Name,
        CASE WHEN d.Is_Weekend = 'Y' THEN 'WEEKEND' ELSE 'WEEKDAY' END AS day_flag,
        f.Order_ID,
        f.Delivery_Fee_Prorated
    FROM Fact_Order_Sales f
    JOIN Dim_Delivery_Company dc ON f.Delivery_Company_Key = dc.Delivery_Company_Key
    JOIN Dim_Date             d  ON f.Date_Key              = d.Date_Key
)
SELECT
    pv_quarter                    || ','
    || Company_Name                 || ','
    || day_flag                       || ','
    || COUNT(DISTINCT Order_ID)         || ','
    || ROUND(SUM(Delivery_Fee_Prorated), 2) || ','
    || ROUND(SUM(Delivery_Fee_Prorated) / NULLIF(COUNT(DISTINCT Order_ID), 0), 2)
FROM delivery_sales
GROUP BY pv_quarter, Company_Name, day_flag
ORDER BY pv_quarter, Company_Name;

SPOOL OFF

-- ── CSV 2: LIFETIME MARKET SHARE & CONCENTRATION ──────────────────────────────
SPOOL delivery_lifetime_share.csv

PROMPT company_name,service_status,order_count,fee_revenue,market_share,share_rank

WITH company_lifetime AS (
    SELECT
        dc.Company_Name,
        dc.service_status,
        COUNT(DISTINCT f.Order_ID)   AS order_count,
        SUM(f.Delivery_Fee_Prorated) AS fee_revenue
    FROM Fact_Order_Sales f
    JOIN Dim_Delivery_Company dc ON f.Delivery_Company_Key = dc.Delivery_Company_Key
    GROUP BY dc.Company_Name, dc.service_status
)
SELECT
    Company_Name                                                    || ','
    || service_status                                                  || ','
    || order_count                                                       || ','
    || ROUND(fee_revenue, 2)                                              || ','
    || ROUND(fee_revenue * 100 / SUM(fee_revenue) OVER (), 1)               || ','
    || RANK() OVER (ORDER BY fee_revenue DESC)
FROM company_lifetime
ORDER BY fee_revenue DESC;

SPOOL OFF

-- Restore defaults
SET COLSEP ' '
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 100
