-- SHOPGRAB VISUALIZATION QUERIES
-- Run each SELECT separately in Oracle SQL Developer.
-- Source: FACT_ORDER_SALES joined to warehouse dimensions.

SET LINESIZE 220;
SET PAGESIZE 100;
SET TAB OFF;
SET WRAP OFF;
SET FEEDBACK OFF;
SET HEADING ON;
SET VERIFY OFF;
SET NULL 'N/A';

COLUMN year_number             FORMAT 9999           HEADING 'YEAR';
COLUMN total_sales_rm          FORMAT 999,999,990.00 HEADING 'TOTAL SALES (RM)';
COLUMN total_orders            FORMAT 999,999        HEADING 'TOTAL ORDERS';
COLUMN delivery_company        FORMAT A25            HEADING 'DELIVERY COMPANY';
COLUMN total_delivery_fees_rm  FORMAT 999,999,990.00 HEADING 'TOTAL DELIVERY FEES (RM)';
COLUMN average_delivery_fee_rm FORMAT 999,999,990.00 HEADING 'AVERAGE DELIVERY FEE (RM)';
COLUMN payment_method          FORMAT A15            HEADING 'PAYMENT METHOD';
COLUMN total_transactions      FORMAT 999,999        HEADING 'TOTAL TRANSACTIONS';
COLUMN successful_transactions FORMAT 999,999        HEADING 'SUCCESSFUL TRANSACTIONS';
COLUMN failed_transactions     FORMAT 999,999        HEADING 'FAILED TRANSACTIONS';
COLUMN refunded_transactions   FORMAT 999,999        HEADING 'REFUNDED TRANSACTIONS';
COLUMN voucher_code            FORMAT A20            HEADING 'VOUCHER CODE';
COLUMN voucher_type            FORMAT A15            HEADING 'VOUCHER TYPE';
COLUMN revenue_rm              FORMAT 999,999,990.00 HEADING 'REVENUE (RM)';
COLUMN total_discount_rm       FORMAT 999,999,990.00 HEADING 'TOTAL DISCOUNT (RM)';
COLUMN average_discount_rm     FORMAT 999,999,990.00 HEADING 'AVERAGE DISCOUNT (RM)';
COLUMN overall_total_orders    FORMAT 999,999        HEADING 'OVERALL TOTAL ORDERS';
COLUMN success_rate            FORMAT 990.00         HEADING 'SUCCESS RATE (%)';
COLUMN top_10                  FORMAT 9              HEADING 'TOP 10';
COLUMN bubble_size             FORMAT 999,999        HEADING 'BUBBLE SIZE';

PROMPT ============================================================================;
PROMPT ORDER FULFILMENT AND DELIVERY PERFORMANCE;
PROMPT ============================================================================;
SELECT
    d.year_number AS year_number,
    dc.company_name AS delivery_company,
    COUNT(DISTINCT f.order_id) AS total_orders,
    ROUND(SUM(f.total_amount), 2) AS total_sales_rm,
    ROUND(SUM(f.delivery_fee_prorated), 2) AS total_delivery_fees_rm,
    ROUND(SUM(SUM(f.delivery_fee_prorated)) OVER (PARTITION BY d.year_number) /
        SUM(COUNT(DISTINCT f.order_id)) OVER (PARTITION BY d.year_number), 2)
        AS average_delivery_fee_rm,
    SUM(COUNT(DISTINCT f.order_id)) OVER (PARTITION BY dc.company_name)
        AS overall_total_orders
FROM fact_order_sales f
JOIN dim_date d ON d.date_key = f.date_key
JOIN dim_delivery_company dc ON dc.delivery_company_key = f.delivery_company_key
WHERE dc.company_name <> 'N/A - Pickup Order'
GROUP BY d.year_number, dc.company_name
ORDER BY d.year_number, total_orders DESC;

PROMPT;
PROMPT ============================================================================;
PROMPT PAYMENT METHOD AND TRANSACTION BEHAVIOUR;
PROMPT ============================================================================;
SELECT
    p.payment_method AS payment_method,
    COUNT(DISTINCT f.order_id) AS total_transactions,
    ROUND(SUM(f.total_amount), 2) AS total_sales_rm,
    COUNT(DISTINCT CASE WHEN p.payment_status = 'SUCCESS' THEN f.order_id END)
        AS successful_transactions,
    COUNT(DISTINCT CASE WHEN p.payment_status = 'FAILED' THEN f.order_id END)
        AS failed_transactions,
    COUNT(DISTINCT CASE WHEN p.payment_status = 'REFUNDED' THEN f.order_id END)
        AS refunded_transactions,
    ROUND(COUNT(DISTINCT CASE WHEN p.payment_status = 'SUCCESS' THEN f.order_id END) /
        NULLIF(COUNT(DISTINCT f.order_id), 0) * 100, 2) AS success_rate
FROM fact_order_sales f
JOIN dim_date d ON d.date_key = f.date_key
JOIN dim_payment p ON p.payment_key = f.payment_key
GROUP BY p.payment_method
ORDER BY total_transactions DESC;

PROMPT;
PROMPT ============================================================================;
PROMPT VOUCHER AND PROMOTION EFFECTIVENESS;
PROMPT ============================================================================;
SELECT
    voucher_code AS voucher_code,
    voucher_type AS voucher_type,
    total_orders AS total_orders,
    revenue_rm AS revenue_rm,
    total_discount_rm AS total_discount_rm,
    average_discount_rm AS average_discount_rm,
    top_10 AS top_10,
    bubble_size AS bubble_size
FROM (
    SELECT
        v.voucher_code AS voucher_code,
        v.voucher_type AS voucher_type,
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
)
ORDER BY total_discount_rm DESC;
