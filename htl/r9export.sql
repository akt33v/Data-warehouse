-- =============================================================================
-- REPORT 9 DATA EXPORT — VOUCHER CAMPAIGN ROI & CONVERSION ANALYSIS
-- Outputs two CSVs for Python visualisation:
--   1. voucher_quarter_summary.csv — roll-up by voucher type / holiday flag / quarter
--   2. voucher_lifetime_roi.csv    — lifetime ROI ranking by voucher type
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
SPOOL voucher_quarter_summary.csv

PROMPT pv_quarter,voucher_type,day_flag,order_count,discount_given,gross_revenue,roi_multiple

WITH voucher_sales AS (
    SELECT
        TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
        v.Voucher_Type,
        CASE WHEN d.Is_Holiday = 'Y' THEN 'HOLIDAY' ELSE 'REGULAR' END AS day_flag,
        f.Order_ID,
        f.Discount_Amount_Prorated,
        f.Total_Amount
    FROM Fact_Order_Sales f
    JOIN Dim_Voucher v ON f.Voucher_Key = v.Voucher_Key
    JOIN Dim_Date    d ON f.Date_Key    = d.Date_Key
    WHERE v.Voucher_Type IS NOT NULL
)
SELECT
    pv_quarter                  || ','
    || Voucher_Type              || ','
    || day_flag                    || ','
    || COUNT(DISTINCT Order_ID)      || ','
    || ROUND(SUM(Discount_Amount_Prorated), 2) || ','
    || ROUND(SUM(Total_Amount), 2)                || ','
    || ROUND(SUM(Total_Amount) / NULLIF(SUM(Discount_Amount_Prorated), 0), 2)
FROM voucher_sales
GROUP BY pv_quarter, Voucher_Type, day_flag
ORDER BY pv_quarter, Voucher_Type;

SPOOL OFF

-- ── CSV 2: LIFETIME ROI RANKING ───────────────────────────────────────────────
SPOOL voucher_lifetime_roi.csv

PROMPT voucher_type,order_count,discount_given,gross_revenue,roi_multiple,roi_rank

WITH voucher_lifetime AS (
    SELECT
        v.Voucher_Type,
        COUNT(DISTINCT f.Order_ID)      AS order_count,
        SUM(f.Discount_Amount_Prorated) AS discount_given,
        SUM(f.Total_Amount)             AS gross_revenue
    FROM Fact_Order_Sales f
    JOIN Dim_Voucher v ON f.Voucher_Key = v.Voucher_Key
    WHERE v.Voucher_Type IS NOT NULL
    GROUP BY v.Voucher_Type
)
SELECT
    Voucher_Type                                                             || ','
    || order_count                                                             || ','
    || ROUND(discount_given, 2)                                                  || ','
    || ROUND(gross_revenue, 2)                                                     || ','
    || ROUND(gross_revenue / NULLIF(discount_given, 0), 2)                           || ','
    || RANK() OVER (ORDER BY gross_revenue / NULLIF(discount_given, 0) DESC)
FROM voucher_lifetime
ORDER BY gross_revenue / NULLIF(discount_given, 0) DESC;

SPOOL OFF

-- Restore defaults
SET COLSEP ' '
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 100
