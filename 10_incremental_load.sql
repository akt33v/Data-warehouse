-- SHOPGRAB DATA WAREHOUSE ETL
-- STEP 10: INCREMENTAL (SUBSEQUENT) LOAD
-- Requires 06_create_warehouse_tables.sql, 08_create_staging_views.sql and
-- 09_etl_initial_load.sql to have been run first. Safe to run repeatedly
-- (e.g. on a schedule) against whatever the OLTP tables actually contain --
-- it does not seed, fabricate, or depend on any test data of its own.
--
-- How the diff detection works, per table:
--   - DIM_RESTAURANT / DIM_VOUCHER / DIM_DELIVERY_COMPANY / DIM_PAYMENT:
--     a MERGE against the matching VW_STG_* view. Oracle's MERGE already IS
--     the diff -- WHEN NOT MATCHED catches rows new in OLTP since the last
--     run, WHEN MATCHED catches rows whose tracked columns changed.
--   - DIM_MEMBER / DIM_MENU_ITEM: true SCD Type 2, so "changed" can't just
--     overwrite -- a PL/SQL loop compares each OLTP row to the CURRENT_FLAG
--     = 'Y' dimension row for that business key: no match at all = brand-new
--     business key (insert version 1); a match whose tracked attributes
--     differ = expire the current version and insert a new one; identical
--     attributes = no write. This is the same logic 09 runs on the first
--     load -- it is already diff-aware, so it is reused here unchanged.
--   - FACT_ORDER_SALES: a MERGE against VW_STG_ORDER_SALES keyed on
--     (Order_ID, Item_Key) -- the fact's actual primary key. WHEN NOT
--     MATCHED inserts genuinely new order lines; WHEN MATCHED ... AND
--     (any measure differs) updates a line whose quantity, price, discount,
--     delivery fee, or payment status changed since it was first loaded.
--     This replaces 09's full DELETE + INSERT with a real insert-or-update
--     diff, so previously loaded, unchanged rows are never rewritten.
--
-- Order deletions in OLTP are out of scope -- this schema has no delete
-- path for customer_order, so the fact load only ever inserts or updates.

SET DEFINE OFF;
SET SERVEROUTPUT ON;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

-- ============================================================================
-- PART 1: DIM_MEMBER (SCD Type 2), source: VW_STG_MEMBER
-- ============================================================================
PROMPT ======= Syncing DIM_MEMBER (SCD2)... =======;
DECLARE
    v_exists  NUMBER;
    v_changed NUMBER;
    v_new NUMBER := 0;
    v_upd NUMBER := 0;
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
            v_new := v_new + 1;
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
                v_upd := v_upd + 1;
            END IF;
        END IF;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DIM_MEMBER: ' || v_new || ' new, ' || v_upd || ' changed (new SCD2 version), rest unchanged.');
END;
/

-- ============================================================================
-- PART 2: DIM_RESTAURANT, source: VW_STG_RESTAURANT
-- ============================================================================
PROMPT ======= Syncing DIM_RESTAURANT... =======;
MERGE INTO dim_restaurant tgt
USING vw_stg_restaurant src
ON (tgt.restaurant_id = src.restaurant_id)
WHEN MATCHED THEN UPDATE SET
    tgt.restaurant_name = src.restaurant_name,
    tgt.category = src.category,
    tgt.halal_status = src.halal_status,
    tgt.rating = src.rating,
    tgt.location_area = src.location_area
  WHERE tgt.restaurant_name <> src.restaurant_name
     OR tgt.category <> src.category
     OR tgt.halal_status <> src.halal_status
     OR tgt.rating <> src.rating
     OR NVL(tgt.location_area,'~') <> NVL(src.location_area,'~')
WHEN NOT MATCHED THEN INSERT (
    restaurant_key, restaurant_id, restaurant_name, category, halal_status, rating, location_area
) VALUES (
    dim_rest_seq.NEXTVAL, src.restaurant_id, src.restaurant_name, src.category,
    src.halal_status, src.rating, src.location_area
);
COMMIT;

-- ============================================================================
-- PART 3: DIM_MENU_ITEM (SCD Type 2), source: VW_STG_MENU_ITEM
-- ============================================================================
PROMPT ======= Syncing DIM_MENU_ITEM (SCD2)... =======;
DECLARE
    v_exists  NUMBER;
    v_changed NUMBER;
    v_new NUMBER := 0;
    v_upd NUMBER := 0;
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
            v_new := v_new + 1;
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
                v_upd := v_upd + 1;
            END IF;
        END IF;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DIM_MENU_ITEM: ' || v_new || ' new, ' || v_upd || ' changed (new SCD2 version), rest unchanged.');
END;
/

-- ============================================================================
-- PART 4: DIM_VOUCHER, source: VW_STG_VOUCHER
-- ============================================================================
PROMPT ======= Syncing DIM_VOUCHER... =======;
MERGE INTO dim_voucher tgt
USING vw_stg_voucher src
ON (tgt.voucher_id = src.voucher_id)
WHEN MATCHED THEN UPDATE SET
    tgt.voucher_code = src.voucher_code,
    tgt.voucher_type = src.voucher_type,
    tgt.discount_amount = src.discount_amount,
    tgt.minimum_order = src.minimum_order
  WHERE tgt.voucher_code <> src.voucher_code
     OR tgt.voucher_type <> src.voucher_type
     OR NVL(tgt.discount_amount,-1) <> NVL(src.discount_amount,-1)
     OR NVL(tgt.minimum_order,-1) <> NVL(src.minimum_order,-1)
WHEN NOT MATCHED THEN INSERT (
    voucher_key, voucher_id, voucher_code, voucher_type, discount_amount, minimum_order
) VALUES (
    dim_voucher_seq.NEXTVAL, src.voucher_id, src.voucher_code, src.voucher_type,
    src.discount_amount, src.minimum_order
);
COMMIT;

-- ============================================================================
-- PART 5: DIM_DELIVERY_COMPANY, source: VW_STG_DELIVERY_COMPANY
-- ============================================================================
PROMPT ======= Syncing DIM_DELIVERY_COMPANY... =======;
MERGE INTO dim_delivery_company tgt
USING vw_stg_delivery_company src
ON (tgt.delivery_company_id = src.delivery_company_id)
WHEN MATCHED THEN UPDATE SET
    tgt.company_name = src.company_name,
    tgt.base_fee = src.base_fee,
    tgt.service_status = src.service_status
  WHERE tgt.company_name <> src.company_name
     OR tgt.base_fee <> src.base_fee
     OR tgt.service_status <> src.service_status
WHEN NOT MATCHED THEN INSERT (
    delivery_company_key, delivery_company_id, company_name, base_fee, service_status
) VALUES (
    dim_del_seq.NEXTVAL, src.delivery_company_id, src.company_name, src.base_fee, src.service_status
);
COMMIT;

-- ============================================================================
-- PART 6: DIM_PAYMENT, source: VW_STG_PAYMENT
-- ============================================================================
PROMPT ======= Syncing DIM_PAYMENT... =======;
MERGE INTO dim_payment tgt
USING vw_stg_payment src
ON (tgt.payment_id = src.payment_id)
WHEN MATCHED THEN UPDATE SET
    tgt.payment_method = src.payment_method,
    tgt.payment_status = src.payment_status
  WHERE tgt.payment_method <> src.payment_method
     OR tgt.payment_status <> src.payment_status
WHEN NOT MATCHED THEN INSERT (
    payment_key, payment_id, payment_method, payment_status
) VALUES (
    dim_pay_seq.NEXTVAL, src.payment_id, src.payment_method, src.payment_status
);
COMMIT;

-- ============================================================================
-- PART 7: FACT_ORDER_SALES, source: VW_STG_ORDER_SALES
-- MERGE keyed on (Order_ID, Item_Key) -- the fact's real primary key.
-- Inserts order lines that don't exist yet; updates ones whose measures
-- changed; leaves everything else untouched.
-- ============================================================================
PROMPT ======= Syncing FACT_ORDER_SALES (insert new / update changed)... =======;
MERGE INTO fact_order_sales tgt
USING (
    SELECT
        s.order_id,
        dmi.item_key,
        dd.date_key,
        dm.member_key,
        dr.restaurant_key,
        NVL(dv.voucher_key, -1)  AS voucher_key,
        NVL(ddc.delivery_company_key, -1) AS delivery_company_key,
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
) src
ON (tgt.order_id = src.order_id AND tgt.item_key = src.item_key)
WHEN MATCHED THEN UPDATE SET
    tgt.date_key = src.date_key,
    tgt.member_key = src.member_key,
    tgt.restaurant_key = src.restaurant_key,
    tgt.voucher_key = src.voucher_key,
    tgt.delivery_company_key = src.delivery_company_key,
    tgt.payment_key = src.payment_key,
    tgt.quantity = src.quantity,
    tgt.unit_price = src.unit_price,
    tgt.subtotal = src.subtotal,
    tgt.discount_amount_prorated = src.discount_amount_prorated,
    tgt.delivery_fee_prorated = src.delivery_fee_prorated,
    tgt.total_amount = src.total_amount
  WHERE tgt.quantity <> src.quantity
     OR tgt.unit_price <> src.unit_price
     OR tgt.subtotal <> src.subtotal
     OR tgt.discount_amount_prorated <> src.discount_amount_prorated
     OR tgt.delivery_fee_prorated <> src.delivery_fee_prorated
     OR tgt.total_amount <> src.total_amount
     OR tgt.payment_key <> src.payment_key
     OR tgt.delivery_company_key <> src.delivery_company_key
     OR tgt.voucher_key <> src.voucher_key
     OR tgt.date_key <> src.date_key
WHEN NOT MATCHED THEN INSERT (
    order_id, date_key, member_key, restaurant_key, item_key, voucher_key,
    delivery_company_key, payment_key, quantity, unit_price, subtotal,
    discount_amount_prorated, delivery_fee_prorated, total_amount
) VALUES (
    src.order_id, src.date_key, src.member_key, src.restaurant_key, src.item_key, src.voucher_key,
    src.delivery_company_key, src.payment_key, src.quantity, src.unit_price, src.subtotal,
    src.discount_amount_prorated, src.delivery_fee_prorated, src.total_amount
);
COMMIT;

-- ============================================================================
-- PART 8: SYNC SUMMARY
-- ============================================================================
PROMPT;
PROMPT ======= INCREMENTAL LOAD COMPLETE =======;
PROMPT Row counts:;

SELECT RPAD(table_name, 25) || ' | ' || LPAD(TO_CHAR(row_count), 8) AS summary
FROM (
    SELECT 'DIM_MEMBER' AS table_name, COUNT(*) AS row_count FROM dim_member
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
