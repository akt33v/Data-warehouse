-- =============================================================================
-- REPORT 7 DATA EXPORT — MENU ITEM CATEGORY PERFORMANCE (BUDGET VS PREMIUM)
-- Outputs two CSVs for Python visualisation:
--   1. menu_tier_summary.csv — roll-up by category / meal tier / item type / quarter
--   2. menu_item_detail.csv  — item-level lifetime detail with ranking
-- Run from SQL*Plus in the reports/ directory.
-- =============================================================================
SET HEADING OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 0
SET LINESIZE 600
SET TRIMSPOOL ON
SET COLSEP ''

-- ── CSV 1: TIER SUMMARY BY QUARTER ────────────────────────────────────────────
SPOOL menu_tier_summary.csv

PROMPT pv_quarter,item_category,meal_tier,deal_flag,item_type,qty_sold,revenue,avg_unit_price

WITH item_sales AS (
    SELECT
        TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
        mi.Item_Category,
        CASE WHEN mi.Budget_Meal = 'Y' THEN 'BUDGET'  ELSE 'PREMIUM' END AS meal_tier,
        CASE WHEN mi.Super_Deal  = 'Y' THEN 'ON DEAL'  ELSE 'REGULAR' END AS deal_flag,
        mi.Item_Type,
        f.Quantity,
        f.Subtotal
    FROM Fact_Order_Sales f
    JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
    JOIN Dim_Date       d ON f.Date_Key = d.Date_Key
)
SELECT
    pv_quarter                 || ','
    || Item_Category           || ','
    || meal_tier                || ','
    || deal_flag                 || ','
    || Item_Type                  || ','
    || SUM(Quantity)                || ','
    || ROUND(SUM(Subtotal), 2)         || ','
    || ROUND(SUM(Subtotal) / NULLIF(SUM(Quantity), 0), 2)
FROM item_sales
GROUP BY pv_quarter, Item_Category, meal_tier, deal_flag, Item_Type
ORDER BY pv_quarter, Item_Category, meal_tier;

SPOOL OFF

-- ── CSV 2: ITEM-LEVEL LIFETIME DETAIL ─────────────────────────────────────────
SPOOL menu_item_detail.csv

PROMPT item_name,item_category,meal_tier,deal_flag,item_type,qty_sold,revenue,avg_unit_price,cat_rank,price_quartile

WITH item_lifetime AS (
    SELECT
        mi.Item_Name,
        mi.Item_Category,
        CASE WHEN mi.Budget_Meal = 'Y' THEN 'BUDGET'  ELSE 'PREMIUM' END AS meal_tier,
        CASE WHEN mi.Super_Deal  = 'Y' THEN 'ON DEAL'  ELSE 'REGULAR' END AS deal_flag,
        mi.Item_Type,
        SUM(f.Quantity) AS qty_sold,
        SUM(f.Subtotal) AS revenue,
        ROUND(SUM(f.Subtotal) / NULLIF(SUM(f.Quantity), 0), 2) AS avg_unit_price
    FROM Fact_Order_Sales f
    JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
    GROUP BY mi.Item_Name, mi.Item_Category, mi.Budget_Meal, mi.Super_Deal, mi.Item_Type
)
SELECT
    '"' || Item_Name || '"'    || ','
    || Item_Category            || ','
    || meal_tier                  || ','
    || deal_flag                    || ','
    || Item_Type                      || ','
    || qty_sold                         || ','
    || revenue                            || ','
    || avg_unit_price                       || ','
    || RANK()  OVER (PARTITION BY Item_Category ORDER BY revenue DESC)         || ','
    || NTILE(4) OVER (PARTITION BY Item_Category ORDER BY avg_unit_price DESC)
FROM item_lifetime
ORDER BY Item_Category, revenue DESC;

SPOOL OFF

-- Restore defaults
SET COLSEP ' '
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 100
