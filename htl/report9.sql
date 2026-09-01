/* =============================================================================
   REPORT 9: VOUCHER CAMPAIGN ROI & CONVERSION ANALYSIS
   -----------------------------------------------------------------------------
   Dimensions : Dim_Voucher (Voucher_Type) x Dim_Date (Quarter, Is_Holiday)
   Measures   : Discount Given (RM), Gross Revenue (RM), Orders, ROI Multiple
                (Revenue generated per RM of discount given), Avg Order Value
   Purpose    : Determine which voucher types generate the most net revenue per
                RM of discount subsidised, and whether campaigns are more
                effective run during holidays vs regular weekdays.
   Techniques : ROLLUP (subtotals), PIVOT (Holiday x Voucher Type),
                CTE + LAG (QoQ %), RANK (Window — ROI ranking), Interactive ACCEPT
   Display    : All output renders as ASCII box-bordered tables via
                PRINT_BOXED_TABLE (see box_report_utils.sql — run that script
                once per session/schema before this one).
   ============================================================================= */
cl scr
SET DEFINE ON
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

PROMPT ============================================================================
PROMPT REPORT 9: VOUCHER CAMPAIGN ROI AND CONVERSION ANALYSIS
PROMPT ============================================================================

-- =============================================================================
-- SECTION 1a: VOUCHER TYPE DETAIL BY QUARTER
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH voucher_sales AS (
          SELECT
              TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
              v.Voucher_Type,
              f.Order_ID,
              f.Discount_Amount_Prorated,
              f.Total_Amount
          FROM Fact_Order_Sales f
          JOIN Dim_Voucher v ON f.Voucher_Key = v.Voucher_Key
          JOIN Dim_Date    d ON f.Date_Key    = d.Date_Key
          WHERE v.Voucher_Type IS NOT NULL
      )
      SELECT
          pv_quarter                                                       AS quarter,
          Voucher_Type                                                     AS voucher_type,
          COUNT(DISTINCT Order_ID)                                         AS orders,
          ROUND(SUM(Discount_Amount_Prorated), 2)                          AS discount_rm,
          ROUND(SUM(Total_Amount), 2)                                      AS revenue_rm,
          ROUND(SUM(Total_Amount) / NULLIF(COUNT(DISTINCT Order_ID), 0), 2) AS aov_rm,
          ROUND(SUM(Total_Amount) / NULLIF(SUM(Discount_Amount_Prorated), 0), 2) AS roi_multiple
      FROM voucher_sales
      GROUP BY pv_quarter, Voucher_Type
      ORDER BY pv_quarter, Voucher_Type
    ]',
    'SECTION 1a: Voucher Type Performance by Quarter'
  );
END;
/

-- =============================================================================
-- SECTION 1b: QUARTER & GRAND TOTALS (ROLLUP)
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      SELECT
          CASE WHEN GROUPING(pv_quarter) = 1 THEN 'GRAND TOTAL' ELSE pv_quarter END AS quarter,
          SUM(orders)          AS orders,
          ROUND(SUM(discount_rm), 2) AS discount_rm,
          ROUND(SUM(revenue_rm), 2)  AS revenue_rm
      FROM (
          SELECT
              TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
              COUNT(DISTINCT f.Order_ID) AS orders,
              SUM(f.Discount_Amount_Prorated) AS discount_rm,
              SUM(f.Total_Amount) AS revenue_rm
          FROM Fact_Order_Sales f
          JOIN Dim_Voucher v ON f.Voucher_Key = v.Voucher_Key
          JOIN Dim_Date    d ON f.Date_Key    = d.Date_Key
          WHERE v.Voucher_Type IS NOT NULL
          GROUP BY d.Year_Number, d.Quarter_Number
      )
      GROUP BY ROLLUP(pv_quarter)
      ORDER BY GROUPING(pv_quarter), pv_quarter
    ]',
    'SECTION 1b: Quarter and Grand Totals'
  );
END;
/

-- =============================================================================
-- SECTION 2: HOLIDAY VS REGULAR-DAY VOUCHER REVENUE — PIVOT
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      SELECT *
      FROM (
          SELECT
              v.Voucher_Type,
              CASE WHEN d.Is_Holiday = 'Y' THEN 'HOLIDAY' ELSE 'REGULAR' END AS day_flag,
              f.Total_Amount AS revenue
          FROM Fact_Order_Sales f
          JOIN Dim_Voucher v ON f.Voucher_Key = v.Voucher_Key
          JOIN Dim_Date    d ON f.Date_Key    = d.Date_Key
          WHERE v.Voucher_Type IS NOT NULL
      )
      PIVOT (
          SUM(revenue)
          FOR day_flag IN ('HOLIDAY' AS holiday_rev, 'REGULAR' AS regular_rev)
      )
      ORDER BY Voucher_Type
    ]',
    'SECTION 2: Holiday vs Regular-Day Voucher Revenue'
  );
END;
/

-- =============================================================================
-- SECTION 3: QoQ REVENUE TREND BY VOUCHER TYPE — CTE + LAG
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH voucher_qtr AS (
          SELECT
              TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS rev_quarter,
              v.Voucher_Type,
              SUM(f.Total_Amount) AS quarterly_rev
          FROM Fact_Order_Sales f
          JOIN Dim_Voucher v ON f.Voucher_Key = v.Voucher_Key
          JOIN Dim_Date    d ON f.Date_Key    = d.Date_Key
          WHERE v.Voucher_Type IS NOT NULL
          GROUP BY d.Year_Number, d.Quarter_Number, v.Voucher_Type
      )
      SELECT
          rev_quarter                                                                    AS quarter,
          Voucher_Type                                                                    AS voucher_type,
          ROUND(quarterly_rev, 2)                                                         AS quarter_rev_rm,
          ROUND(LAG(quarterly_rev) OVER (PARTITION BY Voucher_Type ORDER BY rev_quarter), 2) AS prev_qtr_rev_rm,
          ROUND(
              (quarterly_rev - LAG(quarterly_rev) OVER (PARTITION BY Voucher_Type ORDER BY rev_quarter))
              / NULLIF(LAG(quarterly_rev) OVER (PARTITION BY Voucher_Type ORDER BY rev_quarter), 0) * 100,
              1
          ) AS qoq_change_pct
      FROM voucher_qtr
      ORDER BY rev_quarter, voucher_type
    ]',
    'SECTION 3: Voucher-Driven Revenue Trend - QoQ Change'
  );
END;
/

-- =============================================================================
-- SECTION 4: VOUCHER ROI RANKING (LIFETIME) — RANK (Window)
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH voucher_lifetime AS (
          SELECT
              v.Voucher_Type,
              COUNT(DISTINCT f.Order_ID)         AS order_count,
              SUM(f.Discount_Amount_Prorated)    AS discount_given,
              SUM(f.Total_Amount)                AS gross_revenue
          FROM Fact_Order_Sales f
          JOIN Dim_Voucher v ON f.Voucher_Key = v.Voucher_Key
          WHERE v.Voucher_Type IS NOT NULL
          GROUP BY v.Voucher_Type
      )
      SELECT
          Voucher_Type                                                             AS voucher_type,
          order_count                                                              AS orders,
          ROUND(discount_given, 2)                                                 AS discount_rm,
          ROUND(gross_revenue, 2)                                                  AS revenue_rm,
          ROUND(gross_revenue / NULLIF(discount_given, 0), 2)                      AS roi_multiple,
          RANK() OVER (ORDER BY gross_revenue / NULLIF(discount_given, 0) DESC)    AS roi_rank
      FROM voucher_lifetime
      ORDER BY roi_rank
    ]',
    'SECTION 4: Voucher Type ROI Ranking (Lifetime)'
  );
END;
/

-- =============================================================================
-- SECTION 5: INTERACTIVE DRILL-DOWN BY VOUCHER TYPE (ACCEPT)
-- =============================================================================
PROMPT
PROMPT ========================================================================
ACCEPT p_voucher_type CHAR DEFAULT 'PERCENT' PROMPT 'Enter Voucher Type for Drill Down (PERCENT/FIXED/FREE_DELIVERY) [PERCENT]: '

BEGIN
  print_boxed_table(
    q'[
      SELECT
          v.Voucher_Code                                                    AS voucher_code,
          TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number)       AS quarter,
          COUNT(DISTINCT f.Order_ID)                                        AS orders,
          ROUND(SUM(f.Discount_Amount_Prorated), 2)                        AS discount_rm,
          ROUND(SUM(f.Total_Amount), 2)                                     AS revenue_rm
      FROM Fact_Order_Sales f
      JOIN Dim_Voucher v ON f.Voucher_Key = v.Voucher_Key
      JOIN Dim_Date    d ON f.Date_Key    = d.Date_Key
      WHERE v.Voucher_Type = UPPER(TRIM('&p_voucher_type'))
      GROUP BY v.Voucher_Code, d.Year_Number, d.Quarter_Number
      ORDER BY voucher_code, quarter
    ]',
    'SECTION 5: DRILL DOWN - VOUCHER TYPE: &p_voucher_type'
  );
END;
/

SET FEEDBACK ON
SET VERIFY ON
