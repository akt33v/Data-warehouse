/* =============================================================================
   REPORT 4: MEMBER CHURN & ACTIVATION STATUS ANALYSIS
   Dimensions : Dim_Member (Member_Status, Member_Type) x Dim_Date (Quarter)
   Measures   : Total Revenue, Order Count, Spend Quartiles, QoQ Growth %
   Purpose    : Track revenue lost from suspended/deactivated users,
                detect QoQ active revenue erosion, identify lost VIPs,
                and analyze spending behavior before status change.
   Techniques : PIVOT, CTE, LAG (QoQ %), CASE WHEN bucketing, NTILE, Interactive ACCEPT
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
-- SECTION 1: EXECUTIVE OVERVIEW — PIVOT STATUS BY QUARTER
-- Reshapes long status data into clean quarterly revenue crosstab
-- =============================================================================
COLUMN pv_month        HEADING 'Quarter'              FORMAT A10
COLUMN active_rev      HEADING 'ACTIVE Rev (RM)'      FORMAT 999,999,990.00
COLUMN suspended_rev   HEADING 'SUSPENDED Rev (RM)'   FORMAT 999,999,990.00
COLUMN deact_rev       HEADING 'DEACTIVATED Rev (RM)' FORMAT 999,999,990.00

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'REPORT 4: MEMBER CHURN and ACTIVATION STATUS ANALYSIS' -
       SKIP 1 CENTER 'SECTION 1: Executive Status Overview by Quarter (PIVOT)' -
       SKIP 2
BTITLE CENTER '--- End of Section ---'

SELECT *
FROM (
    SELECT
        TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_month,
        m.Member_Status                  AS member_status,
        f.Total_Amount                   AS total_amount
    FROM
        Fact_Order_Sales f
        JOIN dim_member m ON f.Member_Key = m.Member_Key
        JOIN Dim_Date   d ON f.Date_Key   = d.Date_Key
)
PIVOT (
    SUM(total_amount)
    FOR member_status IN (
        'ACTIVE'      AS active_rev,
        'SUSPENDED'   AS suspended_rev,
        'DEACTIVATED' AS deact_rev
    )
)
ORDER BY pv_month;

-- =============================================================================
-- SECTION 2: CHURN RISK TREND — ACTIVE REVENUE QoQ % CHANGE (CTE + LAG)
-- Detects revenue drop-offs in active base before churn events occur
-- =============================================================================
COLUMN rev_quarter     HEADING 'Quarter'             FORMAT A10
COLUMN quarterly_rev   HEADING 'Quarter Rev (RM)'   FORMAT 999,999,990.00
COLUMN prev_rev        HEADING 'Prev Quarter (RM)'  FORMAT 999,999,990.00
COLUMN pct_change      HEADING 'QoQ Change %'       FORMAT 99,990.00

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'SECTION 2: Active Member Revenue - QoQ % Change (CTE + LAG)' -
       SKIP 2
BTITLE CENTER '--- End of Section ---'

WITH quarterly_active AS (
    SELECT
        TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS rev_quarter,
        SUM(f.Total_Amount)                                          AS quarterly_rev
    FROM
        Fact_Order_Sales f
        JOIN dim_member m ON f.Member_Key = m.Member_Key
        JOIN Dim_Date   d ON f.Date_Key   = d.Date_Key
    WHERE
        m.Member_Status = 'ACTIVE'
    GROUP BY
        d.Year_Number,
        d.Quarter_Number
)
SELECT
    rev_quarter,
    quarterly_rev,
    LAG(quarterly_rev) OVER (ORDER BY rev_quarter)  AS prev_rev,
    ROUND(
        (quarterly_rev - LAG(quarterly_rev) OVER (ORDER BY rev_quarter))
        / LAG(quarterly_rev) OVER (ORDER BY rev_quarter) * 100,
        1
    )                                               AS pct_change
FROM quarterly_active
ORDER BY rev_quarter;

-- =============================================================================
-- SECTION 3: BEHAVIOR DIAGNOSTICS — ORDER SIZE BUCKETING (CASE WHEN)
-- Analyzes whether churned members bought smaller baskets before leaving
-- =============================================================================
COLUMN member_status   HEADING 'Status'              FORMAT A14
COLUMN order_size      HEADING 'Order Size Tier'     FORMAT A15
COLUMN bucket_count    HEADING 'Orders Count'        FORMAT 999,990
COLUMN bucket_revenue  HEADING 'Bucket Revenue (RM)' FORMAT 999,999,990.00

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'SECTION 3: Order Size Bucketing by Member Status (CASE WHEN)' -
       SKIP 2
BTITLE CENTER '--- End of Section ---'

BREAK ON REPORT ON member_status SKIP 1
COMPUTE SUM LABEL 'Status Total' OF bucket_count bucket_revenue ON member_status
COMPUTE SUM LABEL 'Grand Total'  OF bucket_count bucket_revenue ON REPORT

SELECT
    m.Member_Status AS member_status,
    CASE
        WHEN f.Total_Amount < 50          THEN 'Small (<RM50)'
        WHEN f.Total_Amount BETWEEN 50
             AND 150                      THEN 'Medium (RM50-150)'
        ELSE                                   'Large (>RM150)'
    END             AS order_size,
    COUNT(DISTINCT f.Order_ID) AS bucket_count,
    SUM(f.Total_Amount)        AS bucket_revenue
FROM
    Fact_Order_Sales f
    JOIN dim_member m ON f.Member_Key = m.Member_Key
GROUP BY
    m.Member_Status,
    CASE
        WHEN f.Total_Amount < 50          THEN 'Small (<RM50)'
        WHEN f.Total_Amount BETWEEN 50
             AND 150                      THEN 'Medium (RM50-150)'
        ELSE                                   'Large (>RM150)'
    END
ORDER BY
    member_status,
    order_size;

CLEAR BREAKS
CLEAR COMPUTES

-- =============================================================================
-- SECTION 4: HIGH-VALUE LOSS — DEACTIVATED SPEND SEGMENTATION (NTILE)
-- Segments lost members into quartiles: Q1 = high-priority win-back targets
-- =============================================================================
COLUMN member_id       HEADING 'Member ID'           FORMAT 9999999990
COLUMN full_name       HEADING 'Member Name'         FORMAT A30
COLUMN total_spend     HEADING 'Lifetime Spend (RM)' FORMAT 999,999,990.00
COLUMN spend_quartile  HEADING 'Spend Quartile'      FORMAT 9

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'SECTION 4: Deactivated Member Spend Segmentation (NTILE)' -
       SKIP 1 CENTER 'Quartile 1 = Top Spenders Lost (Win-back Priority)' -
       SKIP 2
BTITLE CENTER '--- End of Section ---'

BREAK ON REPORT ON spend_quartile SKIP 1
COMPUTE AVG LABEL 'Quartile Avg' OF total_spend ON spend_quartile
COMPUTE AVG LABEL 'Overall Avg'  OF total_spend ON REPORT

WITH deact_spend AS (
    SELECT
        m.Member_ID,
        m.Full_Name,
        SUM(f.Total_Amount) AS total_spend
    FROM
        Fact_Order_Sales f
        JOIN dim_member m ON f.Member_Key = m.Member_Key
    WHERE
        m.Member_Status = 'DEACTIVATED'
    GROUP BY
        m.Member_ID,
        m.Full_Name
)
SELECT
    member_id,
    full_name,
    total_spend,
    NTILE(4) OVER (ORDER BY total_spend DESC) AS spend_quartile
FROM deact_spend
ORDER BY spend_quartile, total_spend DESC;

CLEAR BREAKS
CLEAR COMPUTES

-- =============================================================================
-- SECTION 5: INTERACTIVE DRILL-DOWN (ACCEPT)
-- Filter specific status to view member type breakdowns over time
-- =============================================================================
PROMPT
PROMPT ========================================================================
ACCEPT user_status CHAR DEFAULT 'ACTIVE' PROMPT 'Enter Member Status for Drill Down (ACTIVE/SUSPENDED/DEACTIVATED, Enter for ACTIVE): '

COLUMN status_filter NEW_VALUE status_filter NOPRINT
SELECT UPPER(TRIM('&user_status')) AS status_filter FROM DUAL;

COLUMN yr_quarter    HEADING 'Quarter'             FORMAT A10
COLUMN member_type   HEADING 'Member Type'         FORMAT A12
COLUMN order_count   HEADING 'Order Count'         FORMAT 999,990
COLUMN total_revenue HEADING 'Total Revenue (RM)'  FORMAT 999,999,990.00

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'SECTION 5: DRILL DOWN - STATUS: &user_status' -
       SKIP 2
BTITLE CENTER '--- End of Report ---'

BREAK ON REPORT ON member_type SKIP 1
COMPUTE SUM LABEL 'Type Total'  OF order_count total_revenue ON member_type
COMPUTE SUM LABEL 'Grand Total' OF order_count total_revenue ON REPORT

SELECT
    TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS yr_quarter,
    m.Member_Type                                                AS member_type,
    COUNT(DISTINCT f.Order_ID)                                   AS order_count,
    SUM(f.Total_Amount)                                          AS total_revenue
FROM
    Fact_Order_Sales f
    JOIN dim_member m ON f.Member_Key = m.Member_Key
    JOIN Dim_Date   d ON f.Date_Key   = d.Date_Key
WHERE
    m.Member_Status = '&status_filter'
GROUP BY
    d.Year_Number,
    d.Quarter_Number,
    m.Member_Type
ORDER BY
    member_type, yr_quarter;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF
SET FEEDBACK ON
SET VERIFY ON
