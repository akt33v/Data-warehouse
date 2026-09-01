/* =============================================================================
   REPORT 3: TOP PERFORMING RESTAURANTS & RATING CORRELATION
   Dimensions : Dim_Restaurant (Restaurant_Name, Rating, Category) x Dim_Date (Quarter)
   Measures   : Total Revenue, Order Count, Avg Order Value
   Purpose    : Determine if higher-rated restaurants generate more revenue;
                guide app homepage algorithm to prioritize high-rated, high-revenue partners.
   Techniques : RANK (Window), CTE + LAG (QoQ %), CASE WHEN (Rating Tier),
                PIVOT (Rating Tier Crosstab), NTILE (Performance Quartile)
   ============================================================================= */
cl scr
set define on
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 50
SET LINESIZE 120
SET TRIMSPOOL ON
SET TERMOUT ON

-- =============================================================================
-- SECTION 1: TOP RESTAURANTS BY REVENUE — RANK (Window Function)
-- Ranks restaurants within each category by total revenue
-- =============================================================================
COLUMN category         HEADING 'Category'            FORMAT A25
COLUMN restaurant_name  HEADING 'Restaurant'          FORMAT A25
COLUMN rating           HEADING 'Rating'              FORMAT 9.99
COLUMN order_count      HEADING 'Orders'              FORMAT 999,990
COLUMN total_revenue    HEADING 'Total Revenue (RM)'  FORMAT 999,999,990.00
COLUMN rev_rank         HEADING 'Rank'                FORMAT 990

TTITLE LEFT 'ShopGrab Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'REPORT 3: TOP PERFORMING RESTAURANTS AND RATING CORRELATION' -
       SKIP 1 CENTER 'SECTION 1: Restaurant Revenue Ranking by Category' -
       SKIP 2
BTITLE CENTER '--- End of Section ---'

BREAK ON category SKIP 1

SELECT
    r.Category                                                      AS category,
    r.Restaurant_Name                                               AS restaurant_name,
    r.Rating                                                        AS rating,
    COUNT(DISTINCT f.Order_ID)                                      AS order_count,
    SUM(f.Total_Amount)                                             AS total_revenue,
    RANK() OVER (PARTITION BY r.Category ORDER BY SUM(f.Total_Amount) DESC) AS rev_rank
FROM
    Fact_Order_Sales f
    JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
                         AND r.Current_Flag = 'Y'
GROUP BY
    r.Category,
    r.Restaurant_Name,
    r.Rating
ORDER BY
    category, rev_rank;

CLEAR BREAKS

-- =============================================================================
-- SECTION 2: RATING TIER REVENUE ANALYSIS — CASE WHEN + PIVOT
-- Buckets restaurants into Low/Mid/High tiers, pivots by quarter
-- =============================================================================
COLUMN pv_quarter     HEADING 'Quarter'              FORMAT A10
COLUMN low_rev        HEADING 'Low (0-2.99) RM'     FORMAT 999,999,990.00
COLUMN mid_rev        HEADING 'Mid (3-3.99) RM'     FORMAT 999,999,990.00
COLUMN high_rev       HEADING 'High (4-5) RM'       FORMAT 999,999,990.00

TTITLE LEFT 'ShopGrab Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'SECTION 2: Revenue by Rating Tier per Quarter' -
       SKIP 2
BTITLE CENTER '--- End of Section ---'

SELECT *
FROM (
    SELECT
        TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
        CASE
            WHEN r.Rating < 3   THEN 'LOW'
            WHEN r.Rating < 4   THEN 'MID'
            ELSE                     'HIGH'
        END AS rating_tier,
        f.Total_Amount AS total_amount
    FROM
        Fact_Order_Sales f
        JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
                             AND r.Current_Flag = 'Y'
        JOIN Dim_Date       d ON f.Date_Key       = d.Date_Key
)
PIVOT (
    SUM(total_amount)
    FOR rating_tier IN (
        'LOW'  AS low_rev,
        'MID'  AS mid_rev,
        'HIGH' AS high_rev
    )
)
ORDER BY pv_quarter;

-- =============================================================================
-- SECTION 3: QoQ REVENUE TREND FOR TOP-RATED RESTAURANTS — CTE + LAG
-- Tracks quarterly revenue growth for restaurants rated 4.0+
-- =============================================================================
COLUMN rev_quarter    HEADING 'Quarter'              FORMAT A10
COLUMN quarterly_rev  HEADING 'Quarter Rev (RM)'    FORMAT 999,999,990.00
COLUMN prev_rev       HEADING 'Prev Quarter (RM)'   FORMAT 999,999,990.00
COLUMN pct_change     HEADING 'QoQ Change %'        FORMAT 99,990.00

TTITLE LEFT 'ShopGrab Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'SECTION 3: Top-Rated (4.0+) Restaurant Revenue - QoQ Change' -
       SKIP 2
BTITLE CENTER '--- End of Section ---'

WITH top_rated_qtr AS (
    SELECT
        TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS rev_quarter,
        SUM(f.Total_Amount)                                          AS quarterly_rev
    FROM
        Fact_Order_Sales f
        JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
                             AND r.Current_Flag = 'Y'
        JOIN Dim_Date       d ON f.Date_Key       = d.Date_Key
    WHERE
        r.Rating >= 4.0
    GROUP BY
        d.Year_Number,
        d.Quarter_Number
)
SELECT
    rev_quarter,
    quarterly_rev,
    LAG(quarterly_rev) OVER (ORDER BY rev_quarter) AS prev_rev,
    ROUND(
        (quarterly_rev - LAG(quarterly_rev) OVER (ORDER BY rev_quarter))
        / LAG(quarterly_rev) OVER (ORDER BY rev_quarter) * 100,
        1
    )                                               AS pct_change
FROM top_rated_qtr
ORDER BY rev_quarter;

-- =============================================================================
-- SECTION 4: RESTAURANT PERFORMANCE QUARTILES — NTILE + CTE
-- Segments all restaurants into performance tiers by lifetime revenue
-- =============================================================================
COLUMN restaurant_name  HEADING 'Restaurant'          FORMAT A35
COLUMN category         HEADING 'Category'            FORMAT A25
COLUMN rating           HEADING 'Rating'              FORMAT 9.99
COLUMN total_revenue    HEADING 'Lifetime Rev (RM)'   FORMAT 999,999,990.00
COLUMN perf_quartile    HEADING 'Perf Quartile'       FORMAT 9

TTITLE LEFT 'ShopGrab Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'SECTION 4: Restaurant Performance Segmentation' -
       SKIP 1 CENTER 'Quartile 1 = Top Performers' -
       SKIP 2
BTITLE CENTER '--- End of Section ---'

BREAK ON REPORT ON perf_quartile SKIP 1
COMPUTE AVG LABEL 'Quartile Avg' OF total_revenue rating ON perf_quartile
COMPUTE AVG LABEL 'Overall Avg'  OF total_revenue rating ON REPORT

WITH rest_lifetime AS (
    SELECT
        r.Restaurant_Name,
        r.Category,
        r.Rating,
        SUM(f.Total_Amount) AS total_revenue
    FROM
        Fact_Order_Sales f
        JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
                             AND r.Current_Flag = 'Y'
    GROUP BY
        r.Restaurant_Name,
        r.Category,
        r.Rating
)
SELECT
    restaurant_name,
    category,
    rating,
    total_revenue,
    NTILE(4) OVER (ORDER BY total_revenue DESC) AS perf_quartile
FROM rest_lifetime
ORDER BY perf_quartile, total_revenue DESC;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF

PROMPT
PROMPT ========================================================================
ACCEPT user_category CHAR DEFAULT 'Chinese Cuisine' PROMPT 'Enter Restaurant Category for Drill Down (Press Enter for Chinese Cuisine): '

SET TERMOUT OFF
COLUMN cat_filter NEW_VALUE cat_filter NOPRINT
SELECT '%' || UPPER(TRIM('&user_category')) || '%' AS cat_filter FROM DUAL;
SET TERMOUT ON 

COLUMN restaurant_name  HEADING 'Restaurant'          FORMAT A35
COLUMN rating           HEADING 'Rating'              FORMAT 9.99
COLUMN rev_quarter      HEADING 'Quarter'             FORMAT A10
COLUMN order_count      HEADING 'Orders'              FORMAT 999,990
COLUMN total_revenue    HEADING 'Revenue (RM)'        FORMAT 999,999,990.00

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'SECTION 5: DRILL DOWN - CATEGORY: &user_category' -
       SKIP 2
BTITLE CENTER '--- End of Report ---'

BREAK ON REPORT ON restaurant_name SKIP 1
COMPUTE SUM LABEL 'Restaurant Total' OF order_count total_revenue ON restaurant_name
COMPUTE SUM LABEL 'Grand Total'      OF order_count total_revenue ON REPORT

-- Section 5: NO Current_Flag filter — f.Restaurant_Key already points to the
-- dim_restaurant version that was active when the order was placed (SCD2).
-- This gives the rating that was in effect during that specific quarter.
SELECT
    r.Restaurant_Name                                               AS restaurant_name,
    r.Rating                                                        AS rating,
    TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number)     AS rev_quarter,
    COUNT(DISTINCT f.Order_ID)                                      AS order_count,
    SUM(f.Total_Amount)                                             AS total_revenue
FROM
    Fact_Order_Sales f
    JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
    JOIN Dim_Date       d ON f.Date_Key       = d.Date_Key
WHERE
    UPPER(r.Category) LIKE '&cat_filter'
GROUP BY
    r.Restaurant_Name,
    r.Rating,
    d.Year_Number,
    d.Quarter_Number
ORDER BY
    restaurant_name, rev_quarter;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF
SET FEEDBACK ON
SET VERIFY ON
