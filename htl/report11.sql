/* =============================================================================
   REPORT 11: DELIVERY PARTNER PERFORMANCE & OPERATIONAL RELIANCE
   -----------------------------------------------------------------------------
   Dimensions : Dim_Delivery_Company (Company_Name, service_status)
                x Dim_Date (Quarter, Is_Weekend)
   Measures   : Order Volume, Delivery Fee Revenue (RM), Avg Fee per Order,
                Market Share %, Weekend Reliance %
   Purpose    : Monitor which delivery partners carry the platform's fulfilment
                volume and cost, and surface single-partner concentration risk —
                especially on weekends.
   Techniques : ROLLUP (subtotals), PIVOT (Weekend vs Weekday by Company),
                CTE + LAG (QoQ %), RANK + Market-Share Window Function,
                Interactive ACCEPT drill-down
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
PROMPT REPORT 11: DELIVERY PARTNER PERFORMANCE AND OPERATIONAL RELIANCE
PROMPT ============================================================================

-- =============================================================================
-- SECTION 1a: DELIVERY PARTNER DETAIL BY QUARTER
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH delivery_sales AS (
          SELECT
              TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
              dc.Company_Name,
              f.Order_ID,
              f.Delivery_Fee_Prorated
          FROM Fact_Order_Sales f
          JOIN Dim_Delivery_Company dc ON f.Delivery_Company_Key = dc.Delivery_Company_Key
          JOIN Dim_Date             d  ON f.Date_Key              = d.Date_Key
      ),
      qtr_totals AS (
          SELECT pv_quarter, SUM(Delivery_Fee_Prorated) AS qtr_fee
          FROM delivery_sales
          GROUP BY pv_quarter
      )
      SELECT
          ds.pv_quarter                                                     AS quarter,
          ds.Company_Name                                                   AS company,
          COUNT(DISTINCT ds.Order_ID)                                       AS orders,
          ROUND(SUM(ds.Delivery_Fee_Prorated), 2)                           AS fee_revenue_rm,
          ROUND(SUM(ds.Delivery_Fee_Prorated) / NULLIF(COUNT(DISTINCT ds.Order_ID), 0), 2) AS avg_fee_rm,
          ROUND(SUM(ds.Delivery_Fee_Prorated) * 100 / NULLIF(qt.qtr_fee, 0), 1) AS market_share_pct
      FROM delivery_sales ds
      JOIN qtr_totals qt ON ds.pv_quarter = qt.pv_quarter
      GROUP BY ds.pv_quarter, ds.Company_Name, qt.qtr_fee
      ORDER BY ds.pv_quarter, market_share_pct DESC
    ]',
    'SECTION 1a: Delivery Partner Volume and Fee Revenue by Quarter'
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
          SUM(orders)                AS orders,
          ROUND(SUM(fee_revenue_rm), 2) AS fee_revenue_rm
      FROM (
          SELECT
              TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
              COUNT(DISTINCT f.Order_ID) AS orders,
              SUM(f.Delivery_Fee_Prorated) AS fee_revenue_rm
          FROM Fact_Order_Sales f
          JOIN Dim_Delivery_Company dc ON f.Delivery_Company_Key = dc.Delivery_Company_Key
          JOIN Dim_Date             d  ON f.Date_Key              = d.Date_Key
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
-- SECTION 2: WEEKEND VS WEEKDAY ORDER VOLUME BY COMPANY — PIVOT
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      SELECT *
      FROM (
          SELECT
              dc.Company_Name,
              CASE WHEN d.Is_Weekend = 'Y' THEN 'WEEKEND' ELSE 'WEEKDAY' END AS day_flag,
              f.Order_ID
          FROM Fact_Order_Sales f
          JOIN Dim_Delivery_Company dc ON f.Delivery_Company_Key = dc.Delivery_Company_Key
          JOIN Dim_Date             d  ON f.Date_Key              = d.Date_Key
      )
      PIVOT (
          COUNT(DISTINCT Order_ID)
          FOR day_flag IN ('WEEKEND' AS weekend_orders, 'WEEKDAY' AS weekday_orders)
      )
      ORDER BY Company_Name
    ]',
    'SECTION 2: Weekend vs Weekday Order Volume by Delivery Company'
  );
END;
/

-- =============================================================================
-- SECTION 3: QoQ FEE REVENUE TREND BY DELIVERY COMPANY — CTE + LAG
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH company_qtr AS (
          SELECT
              TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS rev_quarter,
              dc.Company_Name,
              SUM(f.Delivery_Fee_Prorated) AS quarterly_fee
          FROM Fact_Order_Sales f
          JOIN Dim_Delivery_Company dc ON f.Delivery_Company_Key = dc.Delivery_Company_Key
          JOIN Dim_Date             d  ON f.Date_Key              = d.Date_Key
          GROUP BY d.Year_Number, d.Quarter_Number, dc.Company_Name
      )
      SELECT
          rev_quarter                                                                     AS quarter,
          Company_Name                                                                    AS company,
          ROUND(quarterly_fee, 2)                                                         AS quarter_fee_rm,
          ROUND(LAG(quarterly_fee) OVER (PARTITION BY Company_Name ORDER BY rev_quarter), 2) AS prev_qtr_fee_rm,
          ROUND(
              (quarterly_fee - LAG(quarterly_fee) OVER (PARTITION BY Company_Name ORDER BY rev_quarter))
              / NULLIF(LAG(quarterly_fee) OVER (PARTITION BY Company_Name ORDER BY rev_quarter), 0) * 100,
              1
          ) AS qoq_change_pct
      FROM company_qtr
      ORDER BY rev_quarter, company
    ]',
    'SECTION 3: Delivery Fee Revenue Trend by Company - QoQ Change'
  );
END;
/

-- =============================================================================
-- SECTION 4: LIFETIME MARKET SHARE & CONCENTRATION RANKING — RANK (Window)
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH company_lifetime AS (
          SELECT
              dc.Company_Name,
              dc.service_status,
              COUNT(DISTINCT f.Order_ID)      AS order_count,
              SUM(f.Delivery_Fee_Prorated)    AS fee_revenue
          FROM Fact_Order_Sales f
          JOIN Dim_Delivery_Company dc ON f.Delivery_Company_Key = dc.Delivery_Company_Key
          GROUP BY dc.Company_Name, dc.service_status
      )
      SELECT
          Company_Name                                                AS company,
          service_status                                              AS status,
          order_count                                                 AS orders,
          ROUND(fee_revenue, 2)                                       AS fee_revenue_rm,
          ROUND(fee_revenue * 100 / SUM(fee_revenue) OVER (), 1)      AS market_share_pct,
          RANK() OVER (ORDER BY fee_revenue DESC)                     AS share_rank
      FROM company_lifetime
      ORDER BY share_rank
    ]',
    'SECTION 4: Lifetime Delivery Partner Market Share and Concentration'
  );
END;
/

-- =============================================================================
-- SECTION 5: INTERACTIVE DRILL-DOWN BY DELIVERY COMPANY (ACCEPT)
-- =============================================================================
PROMPT
PROMPT ========================================================================
ACCEPT user_company CHAR PROMPT 'Enter Delivery Company Name for Drill Down (see Section 4 above for valid names): '

BEGIN
  print_boxed_table(
    q'[
      SELECT
          TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number)      AS quarter,
          CASE WHEN d.Is_Weekend = 'Y' THEN 'WEEKEND' ELSE 'WEEKDAY' END   AS day_type,
          COUNT(DISTINCT f.Order_ID)                                       AS orders,
          ROUND(SUM(f.Delivery_Fee_Prorated), 2)                          AS fee_revenue_rm,
          ROUND(SUM(f.Delivery_Fee_Prorated) / NULLIF(COUNT(DISTINCT f.Order_ID), 0), 2) AS avg_fee_rm
      FROM Fact_Order_Sales f
      JOIN Dim_Delivery_Company dc ON f.Delivery_Company_Key = dc.Delivery_Company_Key
      JOIN Dim_Date             d  ON f.Date_Key              = d.Date_Key
      WHERE UPPER(dc.Company_Name) LIKE UPPER('%&user_company%')
      GROUP BY d.Year_Number, d.Quarter_Number, d.Is_Weekend
      ORDER BY quarter, day_type
    ]',
    'SECTION 5: DRILL DOWN - DELIVERY COMPANY: &user_company'
  );
END;
/

SET FEEDBACK ON
SET VERIFY ON
