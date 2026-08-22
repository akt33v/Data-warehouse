-- SHOPGRAB DATA WAREHOUSE
-- STEP 5: VERIFY DATA WAREHOUSE ROW COUNTS & INTEGRITY

SET DEFINE OFF;
SET LINESIZE 120;
SET PAGESIZE 50;

PROMPT ============================================================================;
PROMPT ======= DATA WAREHOUSE TABLE ROW COUNTS =======;
PROMPT ============================================================================;

SELECT RPAD(table_name, 25) || ' | ' || LPAD(TO_CHAR(row_count), 10) AS summary
FROM (
    SELECT 'DIM_DATE'              AS table_name, COUNT(*) AS row_count FROM Dim_Date
    UNION ALL SELECT 'DIM_MEMBER',           COUNT(*) FROM Dim_Member
    UNION ALL SELECT 'DIM_RESTAURANT',       COUNT(*) FROM Dim_Restaurant
    UNION ALL SELECT 'DIM_MENU_ITEM',        COUNT(*) FROM Dim_Menu_Item
    UNION ALL SELECT 'DIM_VOUCHER',          COUNT(*) FROM Dim_Voucher
    UNION ALL SELECT 'DIM_DELIVERY_COMPANY', COUNT(*) FROM Dim_Delivery_Company
    UNION ALL SELECT 'DIM_PAYMENT',          COUNT(*) FROM Dim_Payment
    UNION ALL SELECT 'FACT_ORDER_SALES',     COUNT(*) FROM Fact_Order_Sales
)
ORDER BY table_name;

PROMPT;
PROMPT ============================================================================;
PROMPT ======= SCD TYPE 2 CURRENT VS HISTORICAL ROW COUNTS =======;
PROMPT ============================================================================;

SELECT 'DIM_MEMBER' AS dimension,
       SUM(CASE WHEN Current_Flag = 'Y' THEN 1 ELSE 0 END) AS active_rows,
       SUM(CASE WHEN Current_Flag = 'N' THEN 1 ELSE 0 END) AS expired_history_rows,
       COUNT(*) AS total_rows
FROM Dim_Member
UNION ALL
SELECT 'DIM_MENU_ITEM' AS dimension,
       SUM(CASE WHEN Current_Flag = 'Y' THEN 1 ELSE 0 END) AS active_rows,
       SUM(CASE WHEN Current_Flag = 'N' THEN 1 ELSE 0 END) AS expired_history_rows,
       COUNT(*) AS total_rows
FROM Dim_Menu_Item;

PROMPT;
PROMPT ============================================================================;
PROMPT ======= DATA INTEGRITY CHECKS (VIOLATIONS MUST BE 0) =======;
PROMPT ============================================================================;

SELECT 'OLTP order_item vs DW Fact row count mismatch' AS check_name,
       ABS((SELECT COUNT(*) FROM order_item) - (SELECT COUNT(*) FROM Fact_Order_Sales)) AS violations
FROM dual
UNION ALL
SELECT 'Orders with SUM(Fact total) <> OLTP customer_order.total_amount', COUNT(*)
FROM customer_order co
JOIN (
    SELECT Order_ID, SUM(Total_Amount) AS fact_total
    FROM Fact_Order_Sales
    GROUP BY Order_ID
) f ON f.Order_ID = co.Order_ID
WHERE ROUND(f.fact_total, 2) <> co.total_amount
UNION ALL
SELECT 'Fact rows with orphan Date_Key', COUNT(*)
FROM Fact_Order_Sales f
WHERE NOT EXISTS (SELECT 1 FROM Dim_Date d WHERE d.Date_Key = f.Date_Key)
UNION ALL
SELECT 'Fact rows with orphan Member_Key', COUNT(*)
FROM Fact_Order_Sales f
WHERE NOT EXISTS (SELECT 1 FROM Dim_Member m WHERE m.Member_Key = f.Member_Key)
UNION ALL
SELECT 'Fact rows with orphan Restaurant_Key', COUNT(*)
FROM Fact_Order_Sales f
WHERE NOT EXISTS (SELECT 1 FROM Dim_Restaurant r WHERE r.Restaurant_Key = f.Restaurant_Key)
UNION ALL
SELECT 'Fact rows with orphan Item_Key', COUNT(*)
FROM Fact_Order_Sales f
WHERE NOT EXISTS (SELECT 1 FROM Dim_Menu_Item mi WHERE mi.Item_Key = f.Item_Key);

PROMPT;
