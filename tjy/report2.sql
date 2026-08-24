/* =============================================================================
   REPORT 2: MEMBER CHURN RISK & RETENTION ANALYSIS
   -----------------------------------------------------------------------------
   Dimensions : Registration Cohort Year x Member Type x Member Status x Risk Tier
   Measures   : Member Count, Avg Recency (Days), Total Orders, Total Revenue (RM),
                Avg Order Value (RM), Revenue at Risk (RM), Avg Churn Score
   Purpose    : Proactive retention analysis and customer lifetime value risk assessment
   ============================================================================= */
cl scr
SET DEFINE ON
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 165
SET TRIMSPOOL ON
SET TERMOUT ON
SET COLSEP '   '
SET SPACE 2

-- ============================================================================
-- PART 1: ROLL-UP SUMMARY (Cube by Cohort, Type, Status, Risk Tier)
-- ============================================================================

COLUMN cohort_year_disp   HEADING 'Cohort|Year'          FORMAT A12
COLUMN member_type        HEADING 'Member|Type'          FORMAT A12
COLUMN member_status      HEADING 'Member|Status'        FORMAT A12
COLUMN risk_tier          HEADING 'Risk|Tier'            FORMAT A15
COLUMN member_count       HEADING 'Member|Count'         FORMAT 999,990
COLUMN avg_recency        HEADING 'Avg Recency|(Days)'   FORMAT 999,990.0
COLUMN total_orders       HEADING 'Total|Orders'         FORMAT 999,990
COLUMN total_revenue      HEADING 'Total Revenue|(RM)'   FORMAT 999,999,990.00
COLUMN avg_order_value    HEADING 'Avg Order|Value (RM)' FORMAT 9,999.00
COLUMN revenue_at_risk    HEADING 'Revenue at|Risk (RM)' FORMAT 999,999,990.00
COLUMN avg_churn_score    HEADING 'Avg Churn|Score (1-10)' FORMAT 990.0

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'MEMBER CHURN RISK ANALYSIS - ROLL-UP SUMMARY' -
       SKIP 2

BTITLE CENTER '--- End of Roll-Up Report ---'

BREAK ON REPORT ON cohort_year_disp SKIP 1 ON member_type SKIP 1 ON member_status
COMPUTE SUM LABEL 'Cohort Total' OF member_count total_orders total_revenue revenue_at_risk ON cohort_year_disp
COMPUTE SUM LABEL 'Type Total'   OF member_count total_orders total_revenue revenue_at_risk ON member_type
COMPUTE SUM LABEL 'Grand Total'  OF member_count total_orders total_revenue revenue_at_risk ON REPORT

WITH ref_date AS (
    /* Anchor recency to latest DW order date for consistent cohort analysis */
    SELECT NVL(MAX(d.Full_Date), TRUNC(SYSDATE)) AS max_dw_date
    FROM Fact_Order_Sales f
    JOIN Dim_Date d ON f.Date_Key = d.Date_Key
),
member_base AS (
    SELECT 
        m.Member_Key,
        m.Member_ID,
        m.Full_Name,
        m.Email,
        m.Member_Type,
        m.Member_Status,
        m.Effective_Date AS registration_date,
        EXTRACT(YEAR FROM m.Effective_Date) AS cohort_year
    FROM dim_member m
    WHERE m.Current_Flag = 'Y'
),
member_rfm AS (
    SELECT 
        mb.Member_Key,
        mb.Member_Type,
        mb.Member_Status,
        mb.registration_date,
        mb.cohort_year,
        MAX(dd.Full_Date) AS last_order_date,
        NVL(COUNT(DISTINCT f.Order_ID), 0) AS total_orders,
        NVL(SUM(f.Total_Amount), 0) AS total_revenue
    FROM member_base mb
    LEFT JOIN Fact_Order_Sales f ON mb.Member_Key = f.Member_Key
    LEFT JOIN Dim_Date dd ON f.Date_Key = dd.Date_Key
    GROUP BY 
        mb.Member_Key, mb.Member_Type, mb.Member_Status,
        mb.registration_date, mb.cohort_year
),
member_scored AS (
    SELECT 
        mr.*,
        /* Recency in days relative to latest DW transaction date */
        CASE 
            WHEN mr.last_order_date IS NOT NULL 
                THEN (r.max_dw_date - mr.last_order_date)
            ELSE (r.max_dw_date - mr.registration_date)
        END AS recency_days,
        /* Risk Tier based on status and recency */
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
        /* Churn Risk Score normalized on a 1.0 to 10.0 scale */
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
    TO_CHAR(s.cohort_year) AS cohort_year_disp,
    s.Member_Type AS member_type,
    s.Member_Status AS member_status,
    s.risk_tier,
    COUNT(*) AS member_count,
    ROUND(AVG(s.recency_days), 1) AS avg_recency,
    SUM(s.total_orders) AS total_orders,
    SUM(s.total_revenue) AS total_revenue,
    ROUND(SUM(s.total_revenue) / NULLIF(SUM(s.total_orders), 0), 2) AS avg_order_value,
    /* Revenue at Risk: Probability-weighted expected loss based on risk tier */
    SUM(
        s.total_revenue * CASE s.risk_tier
            WHEN 'Churned'     THEN 1.00
            WHEN 'Critical'    THEN 1.00
            WHEN 'Suspended'   THEN 0.90
            WHEN 'High'        THEN 0.75
            WHEN 'Medium'      THEN 0.45
            WHEN 'Low'         THEN 0.15
            ELSE 0.00
        END
    ) AS revenue_at_risk,
    ROUND(AVG(s.churn_score), 1) AS avg_churn_score
FROM member_scored s
GROUP BY 
    s.cohort_year,
    s.Member_Type,
    s.Member_Status,
    s.risk_tier
ORDER BY 
    s.cohort_year, 
    DECODE(s.Member_Type, 'VIP', 1, 'NORMAL', 2, 3),
    s.Member_Status,
    DECODE(s.risk_tier, 
        'Churned', 1, 'Critical', 2, 'High', 3, 'Suspended', 4, 'Medium', 5, 
        'Low', 6, 'New - No Order', 7, 'Healthy', 8, 9);

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF


SET LINESIZE 200;
-- ============================================================================
-- PART 2: DRILL DOWN - MEMBER-LEVEL CHURN RISK DETAIL
-- ============================================================================
PROMPT
PROMPT ========================================================================
PROMPT  DRILL DOWN: Enter filter criteria (press Enter to accept defaults)
PROMPT ========================================================================
ACCEPT p_risk_tier   CHAR DEFAULT 'ALL' PROMPT 'Risk Tier     (ALL/Critical/High/Medium/Low/Healthy/Suspended/Churned) [ALL]: '
ACCEPT p_member_type CHAR DEFAULT 'ALL' PROMPT 'Member Type   (ALL/VIP/NORMAL) [ALL]: '
ACCEPT p_status      CHAR DEFAULT 'ALL' PROMPT 'Member Status (ALL/ACTIVE/SUSPENDED/DEACTIVATED) [ALL]: '
ACCEPT p_cohort      NUMBER DEFAULT 0   PROMPT 'Cohort Year   (0=ALL, e.g. 2016-2025) [0]: '
ACCEPT p_min_rev     NUMBER DEFAULT 0   PROMPT 'Min Revenue   (RM threshold) [0]: '
PROMPT ========================================================================

/* Normalize inputs for LIKE wildcard matching and clean header display */
COLUMN risk_filter    NEW_VALUE risk_filter    NOPRINT
COLUMN type_filter    NEW_VALUE type_filter    NOPRINT
COLUMN status_filter  NEW_VALUE status_filter  NOPRINT
COLUMN cohort_filter  NEW_VALUE cohort_filter  NOPRINT
COLUMN clean_cohort   NEW_VALUE clean_cohort   NOPRINT
COLUMN clean_min_rev  NEW_VALUE clean_min_rev  NOPRINT

SELECT CASE WHEN UPPER(TRIM('&p_risk_tier'))   = 'ALL' THEN '%' ELSE UPPER(TRIM('&p_risk_tier'))   END AS risk_filter   FROM DUAL;
SELECT CASE WHEN UPPER(TRIM('&p_member_type')) = 'ALL' THEN '%' ELSE UPPER(TRIM('&p_member_type')) END AS type_filter   FROM DUAL;
SELECT CASE WHEN UPPER(TRIM('&p_status'))      = 'ALL' THEN '%' ELSE UPPER(TRIM('&p_status'))      END AS status_filter FROM DUAL;
SELECT CASE WHEN &p_cohort = 0 THEN '%' ELSE TRIM(TO_CHAR(&p_cohort)) END AS cohort_filter FROM DUAL;
SELECT CASE WHEN &p_cohort = 0 THEN 'ALL' ELSE TRIM(TO_CHAR(&p_cohort)) END AS clean_cohort FROM DUAL;
SELECT TRIM(TO_CHAR(&p_min_rev)) AS clean_min_rev FROM DUAL;

COLUMN member_id          HEADING 'Member ID'            FORMAT 9999999990
COLUMN full_name          HEADING 'Full Name'            FORMAT A20
COLUMN email              HEADING 'Email'                FORMAT A26
COLUMN member_type        HEADING 'Type'                 FORMAT A7
COLUMN member_status      HEADING 'Status'               FORMAT A12
COLUMN registration_date  HEADING 'Reg Date'             FORMAT A10
COLUMN last_order_date    HEADING 'Last Order'           FORMAT A10
COLUMN recency_days       HEADING 'Recency|(Days)'       FORMAT 999,990
COLUMN total_orders       HEADING 'Orders'               FORMAT 999,990
COLUMN total_revenue      HEADING 'Total Revenue|(RM)'   FORMAT 999,999,990.00
COLUMN avg_order_value    HEADING 'AOV|(RM)'             FORMAT 9,999.00
COLUMN risk_tier          HEADING 'Risk|Tier'            FORMAT A16
COLUMN churn_score        HEADING 'Churn|Score'          FORMAT 990.0

TTITLE LEFT 'Food Delivery Data Warehouse' RIGHT 'Page:' FORMAT 999 SQL.PNO -
       SKIP 1 CENTER 'DRILL DOWN: MEMBER CHURN RISK DETAIL' -
       SKIP 1 CENTER 'Filters: Tier=&p_risk_tier | Type=&p_member_type | Status=&p_status | Cohort=&clean_cohort | MinRev>=RM&clean_min_rev' -
       SKIP 2

BREAK ON REPORT ON risk_tier SKIP 1
COMPUTE SUM LABEL 'Risk Tier Total' OF total_revenue total_orders ON risk_tier
COMPUTE SUM LABEL 'Grand Total'     OF total_revenue total_orders ON REPORT

WITH ref_date AS (
    SELECT NVL(MAX(d.Full_Date), TRUNC(SYSDATE)) AS max_dw_date
    FROM Fact_Order_Sales f
    JOIN Dim_Date d ON f.Date_Key = d.Date_Key
),
member_base AS (
    SELECT 
        m.Member_Key,
        m.Member_ID,
        m.Full_Name,
        m.Email,
        m.Member_Type,
        m.Member_Status,
        m.Effective_Date AS registration_date,
        EXTRACT(YEAR FROM m.Effective_Date) AS cohort_year
    FROM dim_member m
    WHERE m.Current_Flag = 'Y'
),
member_rfm AS (
    SELECT 
        mb.Member_Key,
        mb.Member_ID,
        mb.Full_Name,
        mb.Email,
        mb.Member_Type,
        mb.Member_Status,
        mb.registration_date,
        mb.cohort_year,
        MAX(dd.Full_Date) AS last_order_date,
        NVL(COUNT(DISTINCT f.Order_ID), 0) AS total_orders,
        NVL(SUM(f.Total_Amount), 0) AS total_revenue,
        ROUND(NVL(AVG(f.Total_Amount), 0), 2) AS avg_order_value
    FROM member_base mb
    LEFT JOIN Fact_Order_Sales f ON mb.Member_Key = f.Member_Key
    LEFT JOIN Dim_Date dd ON f.Date_Key = dd.Date_Key
    GROUP BY 
        mb.Member_Key, mb.Member_ID, mb.Full_Name, mb.Email,
        mb.Member_Type, mb.Member_Status, mb.registration_date, mb.cohort_year
),
member_scored AS (
    SELECT 
        mr.*,
        CASE 
            WHEN mr.last_order_date IS NOT NULL 
                THEN (r.max_dw_date - mr.last_order_date)
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
    s.Member_ID AS member_id,
    SUBSTR(s.Full_Name, 1, 20) AS full_name,
    SUBSTR(s.Email, 1, 26) AS email,
    s.Member_Type AS member_type,
    s.Member_Status AS member_status,
    TO_CHAR(s.registration_date, 'YYYY-MM-DD') AS registration_date,
    TO_CHAR(s.last_order_date, 'YYYY-MM-DD') AS last_order_date,
    s.recency_days,
    s.total_orders,
    s.total_revenue,
    s.avg_order_value,
    s.risk_tier,
    s.churn_score
FROM member_scored s
WHERE UPPER(s.risk_tier) LIKE '&risk_filter'
  AND UPPER(s.Member_Type) LIKE '&type_filter'
  AND UPPER(s.Member_Status) LIKE '&status_filter'
  AND TO_CHAR(s.cohort_year) LIKE '&cohort_filter'
  AND s.total_revenue >= &p_min_rev
ORDER BY 
    DECODE(s.risk_tier, 
        'Churned', 1, 'Critical', 2, 'High', 3, 'Suspended', 4, 'Medium', 5, 
        'Low', 6, 'New - No Order', 7, 'Healthy', 8, 9),
    s.churn_score DESC,
    s.total_revenue DESC;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF

SET FEEDBACK ON
SET VERIFY ON
