SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 500
SET TRIMSPOOL ON
SET COLSEP ''

SPOOL customer_value_cube.csv

PROMPT cohort_year,member_type,restaurant_cat,order_count,total_revenue,avg_order_value
SELECT
    EXTRACT(YEAR FROM m.Effective_Date) || ','
    || m.Member_Type || ','
    || '"' || r.Category || '"' || ','
    || COUNT(DISTINCT f.Order_ID) || ','
    || SUM(f.Total_Amount) || ','
    || ROUND(SUM(f.Total_Amount) / COUNT(DISTINCT f.Order_ID), 2)
FROM Fact_Order_Sales f
JOIN dim_member     m ON f.Member_Key     = m.Member_Key
JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
GROUP BY EXTRACT(YEAR FROM m.Effective_Date), m.Member_Type, r.Category
ORDER BY 1;

SPOOL OFF
SET COLSEP ' '
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 100