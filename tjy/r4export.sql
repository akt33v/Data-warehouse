SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 500
SET TRIMSPOOL ON
SET COLSEP ''

SPOOL member_churn_status.csv

PROMPT yr_month,member_type,member_status,order_count,total_revenue
SELECT
    TO_CHAR(d.Full_Date, 'YYYY-MM') || ','
    || m.Member_Type || ','
    || m.Member_Status || ','
    || COUNT(DISTINCT f.Order_ID) || ','
    || SUM(f.Total_Amount)
FROM Fact_Order_Sales f
JOIN dim_member m ON f.Member_Key = m.Member_Key
JOIN Dim_Date   d ON f.Date_Key   = d.Date_Key
GROUP BY
    TO_CHAR(d.Full_Date, 'YYYY-MM'),
    m.Member_Type,
    m.Member_Status
ORDER BY member_status, member_type, 1;

SPOOL OFF
SET COLSEP ' '
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 100
