-- SHOPGRAB DATA WAREHOUSE ETL
-- STEP 9: INITIAL (FULL) LOAD
-- Requires 06_create_warehouse_tables.sql, _create_staging_schema.sql, and
-- 08_create_staging_views.sql to have been run first.
-- Reads only from the VW_STG_* staging views, never straight from OLTP.
--
-- DATA QUALITY strategy (two layers):
--   Layer 1 (view-level)  : 08_create_staging_views.sql already filters out
--                           structurally invalid rows (NULL PKs, bad email,
--                           out-of-range values, future dates). Only clean
--                           rows reach this script.
--   Layer 2 (load-level)  : Each SCD2 PL/SQL block re-checks business rules
--                           (belt-and-suspenders), skips any row still
--                           failing, and logs it to ETL_REJECTED_ROWS with a
--                           validation_rule code. The outer loop never aborts
--                           on a single bad row -- an inner BEGIN...EXCEPTION
--                           block catches DB-level errors, rolls back only
--                           that row via SAVEPOINT, and logs the error.
--
-- This is the one-time bulk historical load. For ongoing operation use
-- 10_incremental_load.sql instead.

SET DEFINE OFF;
SET SERVEROUTPUT ON;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

-- ============================================================================
-- PART 1: DIM_DATE
-- Generated from 2016-01-01 to 2026-12-31; skips already-loaded dates.
-- ============================================================================
PROMPT ======= Loading DIM_DATE... =======;
INSERT INTO dim_date (
    date_key, full_date, day_number, day_name, month_number, month_name,
    quarter_number, year_number, week_number, is_weekend,
    week_start_date, week_end_date, month_start_date, month_end_date,
    quarter_start_date, quarter_end_date,
    is_end_of_month, is_end_of_quarter, is_end_of_year
)
SELECT
    dim_date_seq.NEXTVAL,
    d.full_date,
    TO_NUMBER(TO_CHAR(d.full_date, 'DD')),
    TO_CHAR(d.full_date, 'FMDay', 'NLS_DATE_LANGUAGE = ENGLISH'),
    TO_NUMBER(TO_CHAR(d.full_date, 'MM')),
    TO_CHAR(d.full_date, 'FMMonth', 'NLS_DATE_LANGUAGE = ENGLISH'),
    TO_NUMBER(TO_CHAR(d.full_date, 'Q')),
    TO_NUMBER(TO_CHAR(d.full_date, 'YYYY')),
    TO_NUMBER(TO_CHAR(d.full_date, 'IW')),
    CASE WHEN MOD(TRUNC(d.full_date) - TRUNC(DATE '2001-01-01'), 7) + 1 IN (6, 7)
         THEN 'Y' ELSE 'N' END,
    TRUNC(d.full_date, 'IW'),
    TRUNC(d.full_date, 'IW') + 6,
    TRUNC(d.full_date, 'MM'),
    LAST_DAY(d.full_date),
    TRUNC(d.full_date, 'Q'),
    ADD_MONTHS(TRUNC(d.full_date, 'Q'), 3) - 1,
    CASE WHEN d.full_date = LAST_DAY(d.full_date) THEN 'Y' ELSE 'N' END,
    CASE WHEN d.full_date = ADD_MONTHS(TRUNC(d.full_date, 'Q'), 3) - 1 THEN 'Y' ELSE 'N' END,
    CASE WHEN TO_CHAR(d.full_date, 'MMDD') = '1231' THEN 'Y' ELSE 'N' END
FROM (
    SELECT DATE '2016-01-01' + LEVEL - 1 AS full_date
    FROM dual
    CONNECT BY LEVEL <= (DATE '2026-12-31' - DATE '2016-01-01' + 1)
) d
WHERE NOT EXISTS (
    SELECT 1 FROM dim_date x WHERE x.full_date = d.full_date
);
COMMIT;

-- ============================================================================
-- PART 2: DIM_MEMBER (SCD Type 2), source: VW_STG_MEMBER
--
-- Validation (belt-and-suspenders over the view's WHERE filters):
--   - member_id, full_name, email, member_type, member_status must be non-NULL
--   - member_status must be ACTIVE / INACTIVE / SUSPENDED
-- Rejected rows logged to ETL_REJECTED_ROWS; loop continues on error.
-- NVL() used in change detection to handle NULL transitions correctly.
-- ============================================================================
PROMPT ======= Loading DIM_MEMBER (SCD2)... =======;
EXEC sp_sync_dim_member;


-- ============================================================================
-- PART 3: DIM_RESTAURANT, source: VW_STG_RESTAURANT
-- SCD Type 2 load via stored procedure (same proc used by incremental runs).
-- ============================================================================
PROMPT ======= Loading DIM_RESTAURANT (SCD2)... =======;
EXEC sp_sync_dim_restaurant;


PROMPT ======= Loading DIM_MENU_ITEM (SCD2)... =======;
EXEC sp_sync_dim_menu_item;


-- ============================================================================
-- PART 5: DIM_VOUCHER, source: VW_STG_VOUCHER
-- MERGE + sentinel row (voucher_key = -1 for orders with no voucher).
-- USING clause guards: non-NULL voucher_id + non-negative amounts.
-- ============================================================================
PROMPT ======= Loading DIM_VOUCHER... =======;
MERGE INTO dim_voucher tgt
USING (
    SELECT * FROM vw_stg_voucher
    WHERE voucher_id              IS NOT NULL
      AND voucher_code            IS NOT NULL
      AND NVL(discount_amount, 0) >= 0
      AND NVL(minimum_order, 0)   >= 0
) src
ON (tgt.voucher_id = src.voucher_id)
WHEN MATCHED THEN UPDATE SET
    tgt.voucher_code    = src.voucher_code,
    tgt.voucher_type    = src.voucher_type,
    tgt.discount_amount = src.discount_amount,
    tgt.minimum_order   = src.minimum_order
WHEN NOT MATCHED THEN INSERT (
    voucher_key, voucher_id, voucher_code, voucher_type, discount_amount, minimum_order
) VALUES (
    dim_voucher_seq.NEXTVAL, src.voucher_id, src.voucher_code, src.voucher_type,
    src.discount_amount, src.minimum_order
);

-- Sentinel row: orders placed without a voucher point here
MERGE INTO dim_voucher tgt
USING (SELECT -1 AS voucher_id FROM dual) src
ON (tgt.voucher_id = src.voucher_id)
WHEN NOT MATCHED THEN INSERT (
    voucher_key, voucher_id, voucher_code, voucher_type, discount_amount, minimum_order
) VALUES (
    -1, -1, 'NO_VOUCHER', 'FIXED', 0, 0
);
COMMIT;

-- ============================================================================
-- PART 6: DIM_DELIVERY_COMPANY, source: VW_STG_DELIVERY_COMPANY
-- MERGE + sentinel row (delivery_company_key = -1 for pickup orders).
-- USING clause guards: non-NULL id/name + non-negative base_fee.
-- ============================================================================
PROMPT ======= Loading DIM_DELIVERY_COMPANY... =======;
MERGE INTO dim_delivery_company tgt
USING (
    SELECT * FROM vw_stg_delivery_company
    WHERE delivery_company_id IS NOT NULL
      AND company_name        IS NOT NULL
      AND NVL(base_fee, 0)   >= 0
) src
ON (tgt.delivery_company_id = src.delivery_company_id)
WHEN MATCHED THEN UPDATE SET
    tgt.company_name   = src.company_name,
    tgt.base_fee       = src.base_fee,
    tgt.service_status = src.service_status
WHEN NOT MATCHED THEN INSERT (
    delivery_company_key, delivery_company_id, company_name, base_fee, service_status
) VALUES (
    dim_del_seq.NEXTVAL, src.delivery_company_id, src.company_name, src.base_fee, src.service_status
);

-- Sentinel row: pickup orders (no delivery record) point here
MERGE INTO dim_delivery_company tgt
USING (SELECT -1 AS delivery_company_id FROM dual) src
ON (tgt.delivery_company_id = src.delivery_company_id)
WHEN NOT MATCHED THEN INSERT (
    delivery_company_key, delivery_company_id, company_name, base_fee, service_status
) VALUES (
    -1, -1, 'N/A - Pickup Order', 0, 'ACTIVE'
);
COMMIT;

-- ============================================================================
-- PART 7: DIM_PAYMENT, source: VW_STG_PAYMENT
-- MERGE. USING clause guards: non-NULL payment_id and payment_method.
-- ============================================================================
PROMPT ======= Loading DIM_PAYMENT... =======;
MERGE INTO dim_payment tgt
USING (
    SELECT * FROM vw_stg_payment
    WHERE payment_id     IS NOT NULL
      AND payment_method IS NOT NULL
) src
ON (tgt.payment_id = src.payment_id)
WHEN MATCHED THEN UPDATE SET
    tgt.payment_method = src.payment_method,
    tgt.payment_status = src.payment_status
WHEN NOT MATCHED THEN INSERT (
    payment_key, payment_id, payment_method, payment_status
) VALUES (
    dim_pay_seq.NEXTVAL, src.payment_id, src.payment_method, src.payment_status
);
COMMIT;

-- ============================================================================
-- PART 8: FACT_ORDER_SALES, source: VW_STG_ORDER_SALES
-- Full DELETE + INSERT -- one-time bulk historical load.
-- USING subquery adds final guards: quantity > 0, non-NULL date, valid date
-- range, non-negative financials.
-- ============================================================================
PROMPT ======= Clearing FACT_ORDER_SALES for full reload... =======;
DELETE FROM fact_order_sales;
COMMIT;

PROMPT ======= Loading FACT_ORDER_SALES... =======;
INSERT INTO fact_order_sales (
    order_id, date_key, member_key, restaurant_key, item_key, voucher_key,
    delivery_company_key, payment_key, quantity, unit_price, subtotal,
    discount_amount_prorated, delivery_fee_prorated, total_amount
)
SELECT
    s.order_id,
    dd.date_key,
    dm.member_key,
    dr.restaurant_key,
    dmi.item_key,
    NVL(dv.voucher_key, -1),
    NVL(ddc.delivery_company_key, -1),
    dp.payment_key,
    s.quantity,
    s.unit_price,
    s.subtotal,
    s.discount_amount_prorated,
    s.delivery_fee_prorated,
    s.total_amount
FROM vw_stg_order_sales s
JOIN dim_date dd
    ON dd.full_date = TRUNC(s.order_datetime)
JOIN dim_member dm
    ON dm.member_id = s.member_id
   AND dm.current_flag = 'Y'
JOIN dim_restaurant dr
    ON dr.restaurant_id = s.restaurant_id
JOIN dim_menu_item dmi
    ON dmi.item_id = s.item_id
   AND dmi.current_flag = 'Y'
LEFT JOIN dim_voucher dv
    ON dv.voucher_id = s.voucher_id
LEFT JOIN dim_delivery_company ddc
    ON ddc.delivery_company_id = s.delivery_company_id
JOIN dim_payment dp
    ON dp.payment_id = s.payment_id
-- Final safety-net guards on the resolved fact rows
WHERE s.quantity           > 0
  AND s.unit_price         >= 0
  AND s.subtotal           >= 0
  AND s.order_datetime     IS NOT NULL
  AND TRUNC(s.order_datetime) BETWEEN DATE '2016-01-01' AND DATE '2026-12-31';

COMMIT;

-- ============================================================================
-- PART 9: LOAD SUMMARY + INTEGRITY CHECKS
-- ============================================================================
PROMPT;
PROMPT ======= INITIAL LOAD COMPLETE =======;
PROMPT Row counts:;

SELECT RPAD(table_name, 25) || ' | ' || LPAD(TO_CHAR(row_count), 8) AS summary
FROM (
    SELECT 'DIM_DATE'             AS table_name, COUNT(*) AS row_count FROM dim_date
    UNION ALL SELECT 'DIM_MEMBER',          COUNT(*) FROM dim_member
    UNION ALL SELECT 'DIM_RESTAURANT',      COUNT(*) FROM dim_restaurant
    UNION ALL SELECT 'DIM_MENU_ITEM',       COUNT(*) FROM dim_menu_item
    UNION ALL SELECT 'DIM_VOUCHER',         COUNT(*) FROM dim_voucher
    UNION ALL SELECT 'DIM_DELIVERY_COMPANY',COUNT(*) FROM dim_delivery_company
    UNION ALL SELECT 'DIM_PAYMENT',         COUNT(*) FROM dim_payment
    UNION ALL SELECT 'FACT_ORDER_SALES',    COUNT(*) FROM fact_order_sales
    ORDER BY 1
);

PROMPT;
PROMPT ======= ETL REJECT SUMMARY =======;
SELECT RPAD(source_name, 15) || ' | rejected: ' || LPAD(TO_CHAR(SUM(rejected_count)), 6)
       || '  valid: ' || LPAD(TO_CHAR(SUM(valid_count)), 6) AS reject_summary
FROM etl_batch_control
WHERE processed_date >= TRUNC(SYSDATE)
GROUP BY source_name
ORDER BY source_name;

PROMPT;
PROMPT ======= INTEGRITY CHECKS (all should be 0) =======;
SELECT 'order_item / fact_order_sales row-count mismatch' AS check_name,
       ABS((SELECT COUNT(*) FROM order_item) - (SELECT COUNT(*) FROM fact_order_sales)) AS violations
FROM dual
UNION ALL
SELECT 'orders where SUM(total_amount) <> customer_order.total_amount', COUNT(*)
FROM customer_order co
JOIN (
    SELECT order_id, SUM(total_amount) AS fact_total FROM fact_order_sales GROUP BY order_id
) f ON f.order_id = co.order_id
WHERE ROUND(f.fact_total, 2) <> co.total_amount;
