/* =============================================================================
   REPORT 2: CUSTOMER VALUE CUBE
   Dimensions : Member (Type -> Status) x Registration Cohort Year x Restaurant Category
   Measures   : Order Count, Total Revenue, Average Order Value
   Purpose    : Cohort-based lifetime value analysis for retention / upgrade strategy
   ============================================================================= */
cl scr
set define on
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 80
SET LINESIZE 150
SET TRIMSPOOL ON
SET TERMOUT ON
SET COLSEP '   '
SET SPACE 2

-- Currency / numeric formatting
COLUMN cohort_year        HEADING 'Cohort Year  '        FORMAT 9999
COLUMN member_type        HEADING 'Member Type'          FORMAT A20
COLUMN restaurant_cat     HEADING 'Restaurant Category'  FORMAT A35
COLUMN restaurant_name    HEADING 'Restaurant Name'      FORMAT A45
COLUMN order_count        HEADING 'Order Count'          FORMAT 999,990
COLUMN total_revenue      HEADING 'Total Revenue (RM)'   FORMAT 999,999,990.00
COLUMN avg_order_value    HEADING 'Avg Order Value (RM)' FORMAT 9,999.00

-- Page title / report title
TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'CUSTOMER VALUE CUBE - COHORT LIFETIME VALUE ANALYSIS' -
       SKIP 2

BTITLE CENTER '--- End of Report ---'

-- Subtotal breaks: reset avg/count subtotals at each grouping level
BREAK ON REPORT ON cohort_year SKIP 1 ON member_type SKIP 1
COMPUTE SUM LABEL 'Cohort Total' OF order_count total_revenue ON cohort_year
COMPUTE SUM LABEL 'Member Type Total' OF order_count total_revenue ON member_type
COMPUTE SUM LABEL 'Grand Total' OF order_count total_revenue ON REPORT

-- SPOOL customer_value_cube_report.txt

SELECT
    EXTRACT(YEAR FROM m.Effective_Date)   AS cohort_year,
    m.Member_Type                          AS member_type,
    r.Category                             AS restaurant_cat,
    COUNT(DISTINCT f.Order_ID)             AS order_count,
    SUM(f.Total_Amount)                    AS total_revenue,
    ROUND(SUM(f.Total_Amount) / COUNT(DISTINCT f.Order_ID), 2) AS avg_order_value
FROM
    Fact_Order_Sales f
    JOIN dim_member     m ON f.Member_Key     = m.Member_Key
    JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
GROUP BY
    EXTRACT(YEAR FROM m.Effective_Date),
    m.Member_Type,
    r.Category
ORDER BY
    cohort_year, member_type, restaurant_cat;

clear breaks
clear computes
clear columns
ttitle off
btitle off

-- SPOOL OFF

-- =============================================================================
-- DRILL DOWN REPORT (BY COHORT YEAR & RESTAURANT CATEGORY)
-- =============================================================================
PROMPT
PROMPT ========================================================================
ACCEPT user_year NUMBER DEFAULT 2020 PROMPT 'Enter Cohort Year for Drill Down (e.g., 2016-2025, press Enter for 2020): '
ACCEPT res_category CHAR DEFAULT 'Chinese Cuisine' PROMPT 'Enter Restaurant Category for Drill Down (Press Enter for Chinese Cuisine): '
PROMPT

COLUMN member_type        HEADING 'Member Type'          FORMAT A30
COLUMN restaurant_name    HEADING 'Restaurant Name'      FORMAT A30
COLUMN order_count        HEADING 'Order Count'          FORMAT 999,990
COLUMN total_revenue      HEADING 'Total Revenue (RM)'   FORMAT 999,999,990.00
COLUMN avg_order_value    HEADING 'Avg Order Value (RM)' FORMAT 9,999.00


-- Pre-build the LIKE pattern from the accepted variable
COLUMN user_cat_filter NEW_VALUE user_cat_filter NOPRINT
SELECT '%' || UPPER(TRIM('&res_category')) || '%' AS user_cat_filter FROM DUAL;

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'DRILL DOWN: COHORT YEAR &user_year | CATEGORY: &res_category' -
       SKIP 2

BREAK ON REPORT ON member_type SKIP 1
COMPUTE SUM LABEL 'Member Type Total' OF order_count total_revenue ON member_type
COMPUTE SUM LABEL 'Drill Down Total'  OF order_count total_revenue ON REPORT

SELECT
    m.Member_Type                                              AS member_type,
    r.Restaurant_Name                                          AS restaurant_name,
    COUNT(DISTINCT f.Order_ID)                                 AS order_count,
    SUM(f.Total_Amount)                                        AS total_revenue,
    ROUND(SUM(f.Total_Amount) / COUNT(DISTINCT f.Order_ID), 2) AS avg_order_value
FROM
    Fact_Order_Sales f
    JOIN dim_member     m ON f.Member_Key     = m.Member_Key
    JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
WHERE
    EXTRACT(YEAR FROM m.Effective_Date) = &user_year
    AND UPPER(r.Category) LIKE '&user_cat_filter'
GROUP BY
    m.Member_Type,
    r.Restaurant_Name
ORDER BY
    m.Member_Type, total_revenue DESC;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF

SET FEEDBACK ON
SET VERIFY ON