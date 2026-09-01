SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 500
SET TRIMSPOOL ON
SET COLSEP ''

SPOOL tjy/restaurant_performance.csv

PROMPT restaurant_name,category,halal_status,rating,location_area,yr_quarter,order_count,total_revenue,avg_order_value
SELECT
    '"' || r.Restaurant_Name || '"' || ','
    || '"' || r.Category || '"' || ','
    || r.Halal_Status || ','
    || r.Rating || ','
    || '"' || r.Location_Area || '"' || ','
    || TO_CHAR(d.Year_Number) || '-Q' || TO_CHAR(d.Quarter_Number) || ','
    || COUNT(DISTINCT f.Order_ID) || ','
    || SUM(f.Total_Amount) || ','
    || ROUND(SUM(f.Total_Amount) / COUNT(DISTINCT f.Order_ID), 2)
FROM Fact_Order_Sales f
JOIN dim_restaurant r ON f.Restaurant_Key = r.Restaurant_Key
JOIN Dim_Date       d ON f.Date_Key       = d.Date_Key
GROUP BY
    r.Restaurant_Name, r.Category, r.Halal_Status, r.Rating,
    r.Location_Area, d.Year_Number, d.Quarter_Number
ORDER BY r.Restaurant_Name, d.Year_Number, d.Quarter_Number;

SPOOL OFF
SET COLSEP ' '
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 100
