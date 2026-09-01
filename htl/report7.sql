/* =============================================================================
   REPORT 7: MENU ITEM CATEGORY PERFORMANCE — BUDGET VS PREMIUM
   -----------------------------------------------------------------------------
   Dimensions : Dim_Menu_Item (Item_Category, Budget_Meal, Super_Deal, Item_Type)
                x Dim_Date (Quarter)
   Measures   : Quantity Sold, Revenue (Subtotal), Avg Unit Price, Revenue Share %
   Purpose    : Determine whether budget-tier meals drive volume at the expense
                of margin, and whether the "Super Deal" tag actually lifts net
                revenue or merely cannibalises full-price sales. Guides menu
                engineering decisions made jointly with restaurant partners.
   Techniques : ROLLUP (subtotals), PIVOT (Budget vs Premium by Quarter),
                CTE + LAG (QoQ %), RANK (Window), NTILE (Price Quartile),
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
PROMPT REPORT 7: MENU ITEM CATEGORY PERFORMANCE - BUDGET VS PREMIUM
PROMPT ============================================================================

-- =============================================================================
-- SECTION 1a: REVENUE & QUANTITY DETAIL — CATEGORY x MEAL TIER x ITEM TYPE
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH item_sales AS (
          SELECT
              mi.Item_Category,
              CASE WHEN mi.Budget_Meal = 'Y' THEN 'BUDGET' ELSE 'PREMIUM' END AS meal_tier,
              mi.Item_Type,
              f.Quantity,
              f.Subtotal,
              f.Unit_Price
          FROM Fact_Order_Sales f
          JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
      ),
      cat_totals AS (
          SELECT Item_Category, SUM(Subtotal) AS cat_revenue
          FROM item_sales
          GROUP BY Item_Category
      )
      SELECT
          s.Item_Category                                             AS category,
          s.meal_tier                                                 AS meal_tier,
          s.Item_Type                                                 AS item_type,
          SUM(s.Quantity)                                              AS qty_sold,
          ROUND(SUM(s.Subtotal), 2)                                    AS revenue_rm,
          ROUND(SUM(s.Subtotal) / NULLIF(SUM(s.Quantity), 0), 2)       AS avg_price_rm,
          ROUND(SUM(s.Subtotal) * 100 / NULLIF(ct.cat_revenue, 0), 1)  AS cat_rev_share_pct
      FROM item_sales s
      JOIN cat_totals ct ON s.Item_Category = ct.Item_Category
      GROUP BY s.Item_Category, s.meal_tier, s.Item_Type, ct.cat_revenue
      ORDER BY s.Item_Category, s.meal_tier, s.Item_Type
    ]',
    'SECTION 1a: Revenue and Quantity Detail by Category / Meal Tier / Item Type'
  );
END;
/

-- =============================================================================
-- SECTION 1b: CATEGORY & GRAND TOTALS (ROLLUP)
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      SELECT
          CASE WHEN GROUPING(mi.Item_Category) = 1 THEN 'GRAND TOTAL' ELSE mi.Item_Category END AS category,
          SUM(f.Quantity)            AS qty_sold,
          ROUND(SUM(f.Subtotal), 2)  AS revenue_rm
      FROM Fact_Order_Sales f
      JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
      GROUP BY ROLLUP(mi.Item_Category)
      ORDER BY GROUPING(mi.Item_Category), mi.Item_Category
    ]',
    'SECTION 1b: Category and Grand Totals'
  );
END;
/

-- =============================================================================
-- SECTION 2: BUDGET VS PREMIUM REVENUE TREND BY QUARTER — PIVOT
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      SELECT *
      FROM (
          SELECT
              TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS pv_quarter,
              CASE WHEN mi.Budget_Meal = 'Y' THEN 'BUDGET' ELSE 'PREMIUM' END AS meal_tier,
              f.Subtotal AS revenue
          FROM Fact_Order_Sales f
          JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
          JOIN Dim_Date       d ON f.Date_Key = d.Date_Key
      )
      PIVOT (
          SUM(revenue)
          FOR meal_tier IN ('BUDGET' AS budget_rev, 'PREMIUM' AS premium_rev)
      )
      ORDER BY pv_quarter
    ]',
    'SECTION 2: Budget vs Premium Revenue by Quarter'
  );
END;
/

-- =============================================================================
-- SECTION 3: SUPER DEAL IMPACT — QoQ NET REVENUE TREND (CTE + LAG)
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH deal_qtr AS (
          SELECT
              TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) AS deal_quarter,
              CASE WHEN mi.Super_Deal = 'Y' THEN 'ON DEAL' ELSE 'REGULAR' END AS deal_flag,
              SUM(f.Subtotal) AS quarterly_rev
          FROM Fact_Order_Sales f
          JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
          JOIN Dim_Date       d ON f.Date_Key = d.Date_Key
          GROUP BY d.Year_Number, d.Quarter_Number,
                   CASE WHEN mi.Super_Deal = 'Y' THEN 'ON DEAL' ELSE 'REGULAR' END
      )
      SELECT
          deal_quarter,
          deal_flag,
          ROUND(quarterly_rev, 2) AS quarter_rev_rm,
          ROUND(LAG(quarterly_rev) OVER (PARTITION BY deal_flag ORDER BY deal_quarter), 2) AS prev_qtr_rev_rm,
          ROUND(
              (quarterly_rev - LAG(quarterly_rev) OVER (PARTITION BY deal_flag ORDER BY deal_quarter))
              / NULLIF(LAG(quarterly_rev) OVER (PARTITION BY deal_flag ORDER BY deal_quarter), 0) * 100,
              1
          ) AS qoq_change_pct
      FROM deal_qtr
      ORDER BY deal_quarter, deal_flag
    ]',
    'SECTION 3: Super Deal vs Regular-Priced Item Revenue - QoQ Change'
  );
END;
/

-- =============================================================================
-- SECTION 4a: MENU ITEM RANKING WITHIN CATEGORY — RANK + NTILE
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH item_lifetime AS (
          SELECT
              mi.Item_Category,
              mi.Item_Name,
              CASE WHEN mi.Budget_Meal = 'Y' THEN 'BUDGET' ELSE 'PREMIUM' END AS meal_tier,
              SUM(f.Subtotal) AS revenue,
              ROUND(SUM(f.Subtotal) / NULLIF(SUM(f.Quantity), 0), 2) AS avg_unit_price
          FROM Fact_Order_Sales f
          JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
          GROUP BY mi.Item_Category, mi.Item_Name, mi.Budget_Meal
      )
      SELECT
          Item_Category                                                            AS category,
          Item_Name                                                                AS item_name,
          meal_tier                                                                AS meal_tier,
          ROUND(revenue, 2)                                                        AS revenue_rm,
          RANK()  OVER (PARTITION BY Item_Category ORDER BY revenue DESC)          AS cat_rank,
          NTILE(4) OVER (PARTITION BY Item_Category ORDER BY avg_unit_price DESC)  AS price_quartile
      FROM item_lifetime
      ORDER BY category, cat_rank
    ]',
    'SECTION 4a: Menu Item Ranking Within Category (Price Quartile 1 = Highest Avg Unit Price)'
  );
END;
/

-- =============================================================================
-- SECTION 4b: CATEGORY & OVERALL AVERAGE LIFETIME REVENUE
-- =============================================================================
BEGIN
  print_boxed_table(
    q'[
      WITH item_lifetime AS (
          SELECT mi.Item_Category, mi.Item_Name, SUM(f.Subtotal) AS revenue
          FROM Fact_Order_Sales f
          JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
          GROUP BY mi.Item_Category, mi.Item_Name
      )
      SELECT
          CASE WHEN GROUPING(Item_Category) = 1 THEN 'OVERALL AVG' ELSE Item_Category END AS category,
          ROUND(AVG(revenue), 2) AS avg_item_revenue_rm
      FROM item_lifetime
      GROUP BY ROLLUP(Item_Category)
      ORDER BY GROUPING(Item_Category), Item_Category
    ]',
    'SECTION 4b: Category and Overall Average Item Revenue'
  );
END;
/

-- =============================================================================
-- SECTION 5: INTERACTIVE DRILL-DOWN BY CATEGORY (ACCEPT)
-- =============================================================================
PROMPT
PROMPT ========================================================================
ACCEPT user_category CHAR PROMPT 'Enter Item Category for Drill Down (e.g. Noodles, Hot Coffee, Desserts): '

BEGIN
  print_boxed_table(
    q'[
      SELECT
          mi.Item_Name                                                AS item_name,
          CASE WHEN mi.Budget_Meal = 'Y' THEN 'BUDGET' ELSE 'PREMIUM' END AS meal_tier,
          CASE WHEN mi.Super_Deal  = 'Y' THEN 'ON DEAL' ELSE 'REGULAR' END AS deal_flag,
          SUM(f.Quantity)                                             AS qty_sold,
          ROUND(SUM(f.Subtotal), 2)                                   AS revenue_rm,
          ROUND(SUM(f.Subtotal) / NULLIF(SUM(f.Quantity), 0), 2)      AS avg_price_rm
      FROM Fact_Order_Sales f
      JOIN Dim_Menu_Item mi ON f.Item_Key = mi.Item_Key
      WHERE UPPER(mi.Item_Category) LIKE UPPER('%&user_category%')
      GROUP BY mi.Item_Name, mi.Budget_Meal, mi.Super_Deal
      ORDER BY revenue_rm DESC
    ]',
    'SECTION 5: DRILL DOWN - CATEGORY: &user_category'
  );
END;
/

SET FEEDBACK ON
SET VERIFY ON
