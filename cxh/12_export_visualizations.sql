SET TERMOUT OFF;
SET FEEDBACK OFF;
SET VERIFY OFF;
SET HEADING OFF;
SET PAGESIZE 0;
SET LINESIZE 32767;
SET TRIMSPOOL ON;
SET MARKUP CSV OFF;

SPOOL 'C:\Users\JAYDEN\Desktop\warehouse2\order_fulfilment_delivery_performance.csv' REPLACE;
SELECT 'YEAR,DELIVERY_COMPANY,TOTAL_ORDERS,TOTAL_SALES_RM,TOTAL_DELIVERY_FEES_RM,AVERAGE_DELIVERY_FEE_RM,OVERALL_TOTAL_ORDERS' FROM dual;
SELECT
    TO_CHAR(d.year_number) || ',' ||
    '"' || REPLACE(dc.company_name, '"', '""') || '",' ||
    TO_CHAR(COUNT(DISTINCT f.order_id)) || ',' ||
    TO_CHAR(ROUND(SUM(f.total_amount), 2), 'FM999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''') || ',' ||
    TO_CHAR(ROUND(SUM(f.delivery_fee_prorated), 2), 'FM999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''') || ',' ||
    TO_CHAR(ROUND(SUM(SUM(f.delivery_fee_prorated)) OVER (PARTITION BY d.year_number) /
        SUM(COUNT(DISTINCT f.order_id)) OVER (PARTITION BY d.year_number), 2),
        'FM999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''') || ',' ||
    TO_CHAR(SUM(COUNT(DISTINCT f.order_id)) OVER (PARTITION BY dc.company_name))
FROM fact_order_sales f
JOIN dim_date d ON d.date_key = f.date_key
JOIN dim_delivery_company dc ON dc.delivery_company_key = f.delivery_company_key
WHERE dc.company_name <> 'N/A - Pickup Order'
GROUP BY d.year_number, dc.company_name
ORDER BY d.year_number, COUNT(DISTINCT f.order_id) DESC;
SPOOL OFF;

SPOOL 'C:\Users\JAYDEN\Desktop\warehouse2\payment_method_order_behaviour.csv' REPLACE;
SELECT 'PAYMENT_METHOD,TOTAL_ORDERS,TOTAL_SALES_RM,SUCCESSFUL_ORDERS,FAILED_ORDERS,REFUNDED_ORDERS,SUCCESS_RATE' FROM dual;
SELECT
    '"' || REPLACE(p.payment_method, '"', '""') || '",' ||
    TO_CHAR(COUNT(DISTINCT f.order_id)) || ',' ||
    TO_CHAR(ROUND(SUM(f.total_amount), 2), 'FM999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''') || ',' ||
    TO_CHAR(COUNT(DISTINCT CASE WHEN p.payment_status = 'SUCCESS' THEN f.order_id END)) || ',' ||
    TO_CHAR(COUNT(DISTINCT CASE WHEN p.payment_status = 'FAILED' THEN f.order_id END)) || ',' ||
    TO_CHAR(COUNT(DISTINCT CASE WHEN p.payment_status = 'REFUNDED' THEN f.order_id END)) || ',' ||
    TO_CHAR(ROUND(
        COUNT(DISTINCT CASE WHEN p.payment_status = 'SUCCESS' THEN f.order_id END) /
        NULLIF(COUNT(DISTINCT f.order_id), 0) * 100, 2),
        'FM990.00', 'NLS_NUMERIC_CHARACTERS=''.,''')
FROM fact_order_sales f
JOIN dim_payment p ON p.payment_key = f.payment_key
GROUP BY p.payment_method
ORDER BY COUNT(DISTINCT f.order_id) DESC;
SPOOL OFF;

SPOOL 'C:\Users\JAYDEN\Desktop\warehouse2\voucher_promotion_effectiveness.csv' REPLACE;
SELECT 'VOUCHER_CODE,VOUCHER_TYPE,TOTAL_ORDERS,REVENUE_RM,TOTAL_DISCOUNT_RM,AVERAGE_DISCOUNT_RM,TOP_10,BUBBLE_SIZE' FROM dual;
SELECT
    '"' || REPLACE(voucher_code, '"', '""') || '",' ||
    '"' || REPLACE(voucher_type, '"', '""') || '",' ||
    TO_CHAR(total_orders) || ',' ||
    TO_CHAR(revenue_rm, 'FM999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''') || ',' ||
    TO_CHAR(total_discount_rm, 'FM999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''') || ',' ||
    TO_CHAR(average_discount_rm, 'FM999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''') || ',' ||
    TO_CHAR(top_10) || ',' ||
    TO_CHAR(bubble_size)
FROM (
    SELECT
        v.voucher_code,
        v.voucher_type,
        COUNT(DISTINCT f.order_id) AS total_orders,
        ROUND(SUM(f.total_amount), 2) AS revenue_rm,
        ROUND(SUM(f.discount_amount_prorated), 2) AS total_discount_rm,
        ROUND(AVG(f.discount_amount_prorated), 2) AS average_discount_rm,
        CASE WHEN ROW_NUMBER() OVER (ORDER BY SUM(f.discount_amount_prorated) DESC) <= 10
            THEN 1 ELSE 0 END AS top_10,
        GREATEST(COUNT(DISTINCT f.order_id), 1) * 8 AS bubble_size
    FROM fact_order_sales f
    JOIN dim_voucher v ON v.voucher_key = f.voucher_key
    WHERE v.voucher_code <> 'NO_VOUCHER'
    GROUP BY v.voucher_code, v.voucher_type
) voucher_sales
ORDER BY total_discount_rm DESC;
SPOOL OFF;

SET TERMOUT ON;
PROMPT CSV export complete:
PROMPT order_fulfilment_delivery_performance.csv
PROMPT payment_method_order_behaviour.csv
PROMPT voucher_promotion_effectiveness.csv
