-- SHOPGRAB DATA WAREHOUSE ETL
-- STEP 9: INITIAL (FULL) LOAD
-- Requires 06_create_warehouse_tables.sql and 08_create_staging_views.sql to
-- have been run first. Reads only from the VW_STG_* staging views, never
-- straight from the OLTP tables.
--
-- This is the first, one-time bulk historical load: dimensions are loaded
-- with MERGE / SCD2 (already safe to re-run), and FACT_ORDER_SALES is
-- cleared and reloaded from scratch every run. For ongoing operation after
-- this first load, use 10_incremental_load.sql instead, which loads the
-- same dimensions but only inserts new fact rows rather than reloading
-- everything.

SET DEFINE OFF;
SET SERVEROUTPUT ON;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

-- ============================================================================
-- PART 1: DIM_DATE
-- Not sourced from a staging view -- there is no OLTP "date" table. Generates
-- every calendar date from 2016-01-01 to 2026-12-31, covering the full
-- order_datetime range the OLTP data can produce.
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
-- ============================================================================
PROMPT ======= Loading DIM_MEMBER (SCD2)... =======;
DECLARE
    v_exists  NUMBER;
    v_changed NUMBER;
BEGIN
    FOR r IN (SELECT * FROM vw_stg_member) LOOP
        SELECT COUNT(*) INTO v_exists
        FROM dim_member
        WHERE member_id = r.member_id AND current_flag = 'Y';

        IF v_exists = 0 THEN
            INSERT INTO dim_member (
                member_key, member_id, full_name, email, member_type, member_status,
                effective_date, expiry_date, current_flag
            ) VALUES (
                dim_member_seq.NEXTVAL, r.member_id, r.full_name, r.email,
                r.member_type, r.member_status,
                r.registration_date, DATE '9999-12-31', 'Y'
            );
        ELSE
            SELECT COUNT(*) INTO v_changed
            FROM dim_member
            WHERE member_id = r.member_id AND current_flag = 'Y'
              AND (full_name <> r.full_name
                   OR email <> r.email
                   OR member_type <> r.member_type
                   OR member_status <> r.member_status);

            IF v_changed > 0 THEN
                UPDATE dim_member
                   SET expiry_date = TRUNC(SYSDATE) - 1,
                       current_flag = 'N'
                 WHERE member_id = r.member_id AND current_flag = 'Y';

                INSERT INTO dim_member (
                    member_key, member_id, full_name, email, member_type, member_status,
                    effective_date, expiry_date, current_flag
                ) VALUES (
                    dim_member_seq.NEXTVAL, r.member_id, r.full_name, r.email,
                    r.member_type, r.member_status,
                    TRUNC(SYSDATE), DATE '9999-12-31', 'Y'
                );
            END IF;
        END IF;
    END LOOP;
    COMMIT;
END;
/

-- ============================================================================
-- PART 3: DIM_RESTAURANT (no history columns), source: VW_STG_RESTAURANT
-- ============================================================================
PROMPT ======= Loading DIM_RESTAURANT... =======;
MERGE INTO dim_restaurant tgt
USING vw_stg_restaurant src
ON (tgt.restaurant_id = src.restaurant_id)
WHEN MATCHED THEN UPDATE SET
    tgt.restaurant_name = src.restaurant_name,
    tgt.category = src.category,
    tgt.halal_status = src.halal_status,
    tgt.rating = src.rating,
    tgt.location_area = src.location_area
WHEN NOT MATCHED THEN INSERT (
    restaurant_key, restaurant_id, restaurant_name, category, halal_status, rating, location_area
) VALUES (
    dim_rest_seq.NEXTVAL, src.restaurant_id, src.restaurant_name, src.category,
    src.halal_status, src.rating, src.location_area
);
COMMIT;

-- ============================================================================
-- PART 4: DIM_MENU_ITEM (SCD Type 2), source: VW_STG_MENU_ITEM
-- menu_item has no "date created" column in OLTP, so a brand-new item's
-- Effective_Date uses a fixed epoch (2000-01-01) that predates every order.
-- ============================================================================
PROMPT ======= Loading DIM_MENU_ITEM (SCD2)... =======;
DECLARE
    v_exists  NUMBER;
    v_changed NUMBER;
BEGIN
    FOR r IN (SELECT * FROM vw_stg_menu_item) LOOP
        SELECT COUNT(*) INTO v_exists
        FROM dim_menu_item
        WHERE item_id = r.item_id AND current_flag = 'Y';

        IF v_exists = 0 THEN
            INSERT INTO dim_menu_item (
                item_key, item_id, item_name, item_category, item_type,
                budget_meal, super_deal, effective_date, expiry_date, current_flag
            ) VALUES (
                dim_menu_seq.NEXTVAL, r.item_id, r.item_name, r.item_category, r.item_type,
                r.budget_meal, r.super_deal, DATE '2000-01-01', DATE '9999-12-31', 'Y'
            );
        ELSE
            SELECT COUNT(*) INTO v_changed
            FROM dim_menu_item
            WHERE item_id = r.item_id AND current_flag = 'Y'
              AND (item_name <> r.item_name
                   OR item_category <> r.item_category
                   OR item_type <> r.item_type
                   OR budget_meal <> r.budget_meal
                   OR super_deal <> r.super_deal);

            IF v_changed > 0 THEN
                UPDATE dim_menu_item
                   SET expiry_date = TRUNC(SYSDATE) - 1,
                       current_flag = 'N'
                 WHERE item_id = r.item_id AND current_flag = 'Y';

                INSERT INTO dim_menu_item (
                    item_key, item_id, item_name, item_category, item_type,
                    budget_meal, super_deal, effective_date, expiry_date, current_flag
                ) VALUES (
                    dim_menu_seq.NEXTVAL, r.item_id, r.item_name, r.item_category, r.item_type,
                    r.budget_meal, r.super_deal, TRUNC(SYSDATE), DATE '9999-12-31', 'Y'
                );
            END IF;
        END IF;
    END LOOP;
    COMMIT;
END;
/

-- ============================================================================
-- PART 5: DIM_VOUCHER, source: VW_STG_VOUCHER, + sentinel row
-- Voucher_Key = -1 stands in for orders placed without a voucher, since
-- Fact_Order_Sales.Voucher_Key is NOT NULL.
-- ============================================================================
PROMPT ======= Loading DIM_VOUCHER... =======;
MERGE INTO dim_voucher tgt
USING vw_stg_voucher src
ON (tgt.voucher_id = src.voucher_id)
WHEN MATCHED THEN UPDATE SET
    tgt.voucher_code = src.voucher_code,
    tgt.voucher_type = src.voucher_type,
    tgt.discount_amount = src.discount_amount,
    tgt.minimum_order = src.minimum_order
WHEN NOT MATCHED THEN INSERT (
    voucher_key, voucher_id, voucher_code, voucher_type, discount_amount, minimum_order
) VALUES (
    dim_voucher_seq.NEXTVAL, src.voucher_id, src.voucher_code, src.voucher_type,
    src.discount_amount, src.minimum_order
);

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
-- PART 6: DIM_DELIVERY_COMPANY, source: VW_STG_DELIVERY_COMPANY, + sentinel
-- Delivery_Company_Key = -1 stands in for PICKUP orders (no delivery record).
-- ============================================================================
PROMPT ======= Loading DIM_DELIVERY_COMPANY... =======;
MERGE INTO dim_delivery_company tgt
USING vw_stg_delivery_company src
ON (tgt.delivery_company_id = src.delivery_company_id)
WHEN MATCHED THEN UPDATE SET
    tgt.company_name = src.company_name,
    tgt.base_fee = src.base_fee,
    tgt.service_status = src.service_status
WHEN NOT MATCHED THEN INSERT (
    delivery_company_key, delivery_company_id, company_name, base_fee, service_status
) VALUES (
    dim_del_seq.NEXTVAL, src.delivery_company_id, src.company_name, src.base_fee, src.service_status
);

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
-- Grain = one row per OLTP payment record (payment_id is 1:1 with
-- customer_order.order_id), not a deduplicated method/status combo.
-- ============================================================================
PROMPT ======= Loading DIM_PAYMENT... =======;
MERGE INTO dim_payment tgt
USING vw_stg_payment src
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
-- Full DELETE + INSERT -- this is the one-time bulk historical load.
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
    ON dp.payment_id = s.payment_id;

COMMIT;

-- ============================================================================
-- PART 9: LOAD SUMMARY
-- ============================================================================
PROMPT;
PROMPT ======= INITIAL LOAD COMPLETE =======;
PROMPT Row counts:;

SELECT RPAD(table_name, 25) || ' | ' || LPAD(TO_CHAR(row_count), 8) AS summary
FROM (
    SELECT 'DIM_DATE' AS table_name, COUNT(*) AS row_count FROM dim_date
    UNION ALL SELECT 'DIM_MEMBER', COUNT(*) FROM dim_member
    UNION ALL SELECT 'DIM_RESTAURANT', COUNT(*) FROM dim_restaurant
    UNION ALL SELECT 'DIM_MENU_ITEM', COUNT(*) FROM dim_menu_item
    UNION ALL SELECT 'DIM_VOUCHER', COUNT(*) FROM dim_voucher
    UNION ALL SELECT 'DIM_DELIVERY_COMPANY', COUNT(*) FROM dim_delivery_company
    UNION ALL SELECT 'DIM_PAYMENT', COUNT(*) FROM dim_payment
    UNION ALL SELECT 'FACT_ORDER_SALES', COUNT(*) FROM fact_order_sales
    ORDER BY 1
);

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
