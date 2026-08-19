-- ============================================================================
-- SHOPGRAB OLTP DATA VERIFICATION SCRIPT
-- Checks row counts, date ranges, distributions, and constraint integrity
-- for all 16 OLTP source tables (excludes DIM_/FACT_ warehouse tables).
-- ============================================================================

SET LINESIZE 120;
SET PAGESIZE 200;
COLUMN TABLE_NAME FORMAT A35;
COLUMN ROW_COUNT  FORMAT 999,999;
COLUMN METRIC     FORMAT A35;
COLUMN EARLIEST   FORMAT A20;
COLUMN LATEST     FORMAT A20;

PROMPT =====================================================================;
PROMPT 1. ROW COUNTS FOR ALL OLTP TABLES;
PROMPT =====================================================================;

SELECT 'MEMBER_TYPE'              AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM member_type
UNION ALL SELECT 'MEMBER',                       COUNT(*) FROM member
UNION ALL SELECT 'ADDRESS',                      COUNT(*) FROM address
UNION ALL SELECT 'RESTAURANT_CATEGORY',          COUNT(*) FROM restaurant_category
UNION ALL SELECT 'RESTAURANT',                   COUNT(*) FROM restaurant
UNION ALL SELECT 'ITEM_CATEGORY',                COUNT(*) FROM item_category
UNION ALL SELECT 'MENU_ITEM',                    COUNT(*) FROM menu_item
UNION ALL SELECT 'VOUCHER',                      COUNT(*) FROM voucher
UNION ALL SELECT 'DELIVERY_COMPANY',             COUNT(*) FROM delivery_company
UNION ALL SELECT 'GROUP_ORDER',                  COUNT(*) FROM group_order
UNION ALL SELECT 'GROUP_ORDER_PARTICIPANT',      COUNT(*) FROM group_order_participant
UNION ALL SELECT 'CUSTOMER_ORDER',               COUNT(*) FROM customer_order
UNION ALL SELECT 'ORDER_ITEM',                   COUNT(*) FROM order_item
UNION ALL SELECT 'DELIVERY',                     COUNT(*) FROM delivery
UNION ALL SELECT 'PAYMENT',                      COUNT(*) FROM payment
UNION ALL SELECT 'VOUCHER_REDEMPTION',           COUNT(*) FROM voucher_redemption
ORDER BY 1;

PROMPT;
PROMPT =====================================================================;
PROMPT 2. DATE RANGE COVERAGE;
PROMPT =====================================================================;

SELECT 'Member Registration'  AS METRIC,
       TO_CHAR(MIN(registration_date), 'YYYY-MM-DD') AS EARLIEST,
       TO_CHAR(MAX(registration_date), 'YYYY-MM-DD') AS LATEST
FROM member
UNION ALL
SELECT 'Customer Order Dates',
       TO_CHAR(MIN(order_datetime), 'YYYY-MM-DD'),
       TO_CHAR(MAX(order_datetime), 'YYYY-MM-DD')
FROM customer_order
UNION ALL
SELECT 'Group Order Dates',
       TO_CHAR(MIN(created_datetime), 'YYYY-MM-DD'),
       TO_CHAR(MAX(created_datetime), 'YYYY-MM-DD')
FROM group_order
UNION ALL
SELECT 'Delivery Dates',
       TO_CHAR(MIN(delivered_datetime), 'YYYY-MM-DD'),
       TO_CHAR(MAX(delivered_datetime), 'YYYY-MM-DD')
FROM delivery
UNION ALL
SELECT 'Payment Dates',
       TO_CHAR(MIN(payment_datetime), 'YYYY-MM-DD'),
       TO_CHAR(MAX(payment_datetime), 'YYYY-MM-DD')
FROM payment
UNION ALL
SELECT 'Voucher Expiry Range',
       TO_CHAR(MIN(expiry_date), 'YYYY-MM-DD'),
       TO_CHAR(MAX(expiry_date), 'YYYY-MM-DD')
FROM voucher;

PROMPT;
PROMPT =====================================================================;
PROMPT 3. CUSTOMER ORDER DISTRIBUTION BY YEAR;
PROMPT =====================================================================;

COLUMN ORDER_YEAR FORMAT 9999;
COLUMN ORDER_COUNT FORMAT 999,999;

SELECT EXTRACT(YEAR FROM order_datetime) AS ORDER_YEAR,
       COUNT(*)                          AS ORDER_COUNT
FROM customer_order
GROUP BY EXTRACT(YEAR FROM order_datetime)
ORDER BY 1;

PROMPT;
PROMPT =====================================================================;
PROMPT 4. ORDER STATUS BREAKDOWN;
PROMPT =====================================================================;

COLUMN ORDER_STATUS FORMAT A20;
COLUMN CNT FORMAT 999,999;

SELECT order_status AS ORDER_STATUS, COUNT(*) AS CNT
FROM customer_order
GROUP BY order_status
ORDER BY 2 DESC;

PROMPT;
PROMPT =====================================================================;
PROMPT 5. PAYMENT METHOD BREAKDOWN;
PROMPT =====================================================================;

COLUMN PAYMENT_METHOD FORMAT A15;

SELECT payment_method AS PAYMENT_METHOD, COUNT(*) AS CNT
FROM payment
GROUP BY payment_method
ORDER BY 2 DESC;

PROMPT;
PROMPT =====================================================================;
PROMPT 6. ORDER TYPE BREAKDOWN (DELIVERY vs PICKUP);
PROMPT =====================================================================;

COLUMN ORDER_TYPE FORMAT A15;

SELECT order_type AS ORDER_TYPE, COUNT(*) AS CNT
FROM customer_order
GROUP BY order_type
ORDER BY 2 DESC;

PROMPT;
PROMPT =====================================================================;
PROMPT 7. MEMBER TYPE DISTRIBUTION;
PROMPT =====================================================================;

COLUMN TYPE_NAME FORMAT A10;

SELECT mt.type_name AS TYPE_NAME, COUNT(*) AS CNT
FROM member m
JOIN member_type mt ON m.member_type_id = mt.member_type_id
GROUP BY mt.type_name
ORDER BY 2 DESC;

PROMPT;
PROMPT =====================================================================;
PROMPT 8. GROUP ORDER STATUS BREAKDOWN;
PROMPT =====================================================================;

COLUMN GROUP_STATUS FORMAT A15;

SELECT group_status AS GROUP_STATUS, COUNT(*) AS CNT
FROM group_order
GROUP BY group_status
ORDER BY 2 DESC;

PROMPT;
PROMPT =====================================================================;
PROMPT 9. VOUCHER USAGE SUMMARY;
PROMPT =====================================================================;

COLUMN VOUCHER_TYPE FORMAT A15;
COLUMN TOTAL_VOUCHERS FORMAT 999;
COLUMN TIMES_REDEEMED FORMAT 999,999;

SELECT v.voucher_type                   AS VOUCHER_TYPE,
       COUNT(DISTINCT v.voucher_id)     AS TOTAL_VOUCHERS,
       COUNT(vr.redemption_id)          AS TIMES_REDEEMED
FROM voucher v
LEFT JOIN voucher_redemption vr ON v.voucher_id = vr.voucher_id
GROUP BY v.voucher_type
ORDER BY 1;

PROMPT;
PROMPT =====================================================================;
PROMPT 10. DELIVERY COMPANY WORKLOAD;
PROMPT =====================================================================;

COLUMN COMPANY_NAME FORMAT A25;
COLUMN DELIVERIES FORMAT 999,999;

SELECT dc.company_name AS COMPANY_NAME, COUNT(d.delivery_id) AS DELIVERIES
FROM delivery_company dc
LEFT JOIN delivery d ON dc.delivery_company_id = d.delivery_company_id
GROUP BY dc.company_name
ORDER BY 2 DESC;

PROMPT;
PROMPT =====================================================================;
PROMPT 11. CONSTRAINT / INTEGRITY CHECKS (all should be 0);
PROMPT =====================================================================;

COLUMN CHECK_NAME FORMAT A50;
COLUMN VIOLATIONS FORMAT 999,999;

SELECT 'Orders with wrong total_amount'             AS CHECK_NAME, COUNT(*) AS VIOLATIONS
FROM customer_order
WHERE total_amount <> (subtotal + delivery_fee - discount_amount)
UNION ALL
SELECT 'Delivery orders missing address_id',        COUNT(*)
FROM customer_order
WHERE order_type = 'DELIVERY' AND address_id IS NULL
UNION ALL
SELECT 'Order items with wrong subtotal',           COUNT(*)
FROM order_item
WHERE subtotal <> (quantity * unit_price)
UNION ALL
SELECT 'Payments without matching order',           COUNT(*)
FROM payment p
WHERE NOT EXISTS (SELECT 1 FROM customer_order co WHERE co.order_id = p.order_id)
UNION ALL
SELECT 'Deliveries without matching order',         COUNT(*)
FROM delivery d
WHERE NOT EXISTS (SELECT 1 FROM customer_order co WHERE co.order_id = d.order_id)
UNION ALL
SELECT 'Redemptions without matching order',        COUNT(*)
FROM voucher_redemption vr
WHERE NOT EXISTS (SELECT 1 FROM customer_order co WHERE co.order_id = vr.order_id)
UNION ALL
SELECT 'Group participants not in member table',    COUNT(*)
FROM group_order_participant gp
WHERE NOT EXISTS (SELECT 1 FROM member m WHERE m.member_id = gp.member_id)
UNION ALL
SELECT 'Orders referencing invalid voucher_id',     COUNT(*)
FROM customer_order co
WHERE co.voucher_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM voucher v WHERE v.voucher_id = co.voucher_id)
UNION ALL
SELECT 'Orders referencing invalid address_id',     COUNT(*)
FROM customer_order co
WHERE co.address_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM address a WHERE a.address_id = co.address_id);

PROMPT;
PROMPT =====================================================================;
PROMPT 12. TOP 10 MOST ACTIVE MEMBERS (by order count);
PROMPT =====================================================================;

COLUMN MEMBER_ID FORMAT 9999;
COLUMN FULL_NAME FORMAT A25;
COLUMN ORDERS FORMAT 999,999;

SELECT * FROM (
    SELECT m.member_id AS MEMBER_ID, m.full_name AS FULL_NAME, COUNT(co.order_id) AS ORDERS
    FROM member m
    LEFT JOIN customer_order co ON m.member_id = co.member_id
    GROUP BY m.member_id, m.full_name
    ORDER BY 3 DESC
)
WHERE ROWNUM <= 10;

PROMPT;
PROMPT =====================================================================;
PROMPT 13. TOP 10 MOST ORDERED RESTAURANTS;
PROMPT =====================================================================;

COLUMN RESTAURANT_NAME FORMAT A30;

SELECT * FROM (
    SELECT r.restaurant_name AS RESTAURANT_NAME, COUNT(co.order_id) AS ORDERS
    FROM restaurant r
    LEFT JOIN customer_order co ON r.restaurant_id = co.restaurant_id
    GROUP BY r.restaurant_name
    ORDER BY 2 DESC
)
WHERE ROWNUM <= 10;

PROMPT;
PROMPT ============= VERIFICATION COMPLETE =============;
