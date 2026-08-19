-- SHOPGRAB DATA WAREHOUSE ETL
-- STEP 8: STAGING VIEWS
-- Views over the OLTP tables -- no physical staging tables, no duplicated
-- data. Both 09_etl_initial_load.sql and 10_incremental_load.sql read from
-- these views instead of joining the OLTP tables directly, so the lookup
-- joins (member_type, restaurant_category, item_category) and the
-- order-level discount/delivery-fee proration math live in exactly one
-- place instead of being restated in every load script.
--
-- Plain views, not materialized: every SELECT against them reflects the
-- current OLTP state at query time, which is what both the initial load
-- (reads everything) and the incremental load (reads everything, then
-- diffs against what's already in the warehouse) need.
--
-- Must run after 01_create_tables.sql (+ data) and before
-- 09_etl_initial_load.sql / 10_incremental_load.sql. Does not depend on
-- 06_create_warehouse_tables.sql -- these views only touch OLTP tables.

SET DEFINE OFF;

CREATE OR REPLACE VIEW vw_stg_member AS
SELECT
    m.member_id,
    m.full_name,
    m.email,
    mt.type_name AS member_type,
    m.member_status,
    m.registration_date
FROM member m
JOIN member_type mt ON mt.member_type_id = m.member_type_id;

CREATE OR REPLACE VIEW vw_stg_restaurant AS
SELECT
    r.restaurant_id,
    r.restaurant_name,
    rc.category_name AS category,
    r.halal_status,
    r.rating_avg AS rating,
    r.location_area
FROM restaurant r
JOIN restaurant_category rc ON rc.restaurant_category_id = r.restaurant_category_id;

CREATE OR REPLACE VIEW vw_stg_menu_item AS
SELECT
    mi.item_id,
    mi.item_name,
    ic.category_name AS item_category,
    mi.item_type,
    mi.budget_meal_flag AS budget_meal,
    mi.super_deal_flag AS super_deal
FROM menu_item mi
JOIN item_category ic ON ic.item_category_id = mi.item_category_id;

CREATE OR REPLACE VIEW vw_stg_voucher AS
SELECT
    voucher_id,
    voucher_code,
    voucher_type,
    discount_amount,
    min_order_amount AS minimum_order
FROM voucher;

CREATE OR REPLACE VIEW vw_stg_delivery_company AS
SELECT
    delivery_company_id,
    company_name,
    base_fee,
    service_status
FROM delivery_company;

CREATE OR REPLACE VIEW vw_stg_payment AS
SELECT
    payment_id,
    order_id,
    payment_method,
    payment_status
FROM payment;

-- One row per order line item, ready to load straight into FACT_ORDER_SALES
-- once each business key below is resolved to its dimension surrogate key.
-- Order-level discount_amount / delivery_fee are prorated across the
-- order's line items in proportion to each line's subtotal share, with the
-- item carrying the highest order_item_id in each order absorbing the
-- rounding remainder -- so SUM(...) per order reconciles exactly to
-- customer_order's totals instead of drifting from independently-rounded
-- lines. (Same math previously duplicated inline in the load scripts;
-- it now lives here once.)
CREATE OR REPLACE VIEW vw_stg_order_sales AS
WITH item_calc AS (
    SELECT
        oi.order_item_id,
        oi.order_id,
        oi.item_id,
        oi.quantity,
        oi.unit_price,
        oi.subtotal,
        co.order_datetime,
        co.member_id,
        co.restaurant_id,
        co.voucher_id,
        co.discount_amount,
        co.delivery_fee,
        del.delivery_company_id,
        pay.payment_id,
        ROUND(co.discount_amount * oi.subtotal / NULLIF(co.subtotal, 0), 2) AS disc_calc,
        ROUND(co.delivery_fee   * oi.subtotal / NULLIF(co.subtotal, 0), 2) AS fee_calc,
        ROW_NUMBER() OVER (PARTITION BY oi.order_id ORDER BY oi.order_item_id DESC) AS rn_desc
    FROM order_item oi
    JOIN customer_order co ON co.order_id = oi.order_id
    LEFT JOIN delivery del ON del.order_id = co.order_id
    JOIN payment pay ON pay.order_id = co.order_id
),
proration AS (
    SELECT
        ic.*,
        SUM(CASE WHEN rn_desc <> 1 THEN disc_calc ELSE 0 END) OVER (PARTITION BY order_id) AS disc_sum_others,
        SUM(CASE WHEN rn_desc <> 1 THEN fee_calc  ELSE 0 END) OVER (PARTITION BY order_id) AS fee_sum_others
    FROM item_calc ic
)
SELECT
    order_item_id,
    order_id,
    order_datetime,
    member_id,
    restaurant_id,
    item_id,
    voucher_id,
    delivery_company_id,
    payment_id,
    quantity,
    unit_price,
    subtotal,
    CASE WHEN rn_desc = 1 THEN discount_amount - disc_sum_others ELSE disc_calc END AS discount_amount_prorated,
    CASE WHEN rn_desc = 1 THEN delivery_fee   - fee_sum_others  ELSE fee_calc  END AS delivery_fee_prorated,
    subtotal
        + (CASE WHEN rn_desc = 1 THEN delivery_fee   - fee_sum_others  ELSE fee_calc  END)
        - (CASE WHEN rn_desc = 1 THEN discount_amount - disc_sum_others ELSE disc_calc END) AS total_amount
FROM proration;

PROMPT ======= Staging views created (6 dimension views + 1 order-sales view) =======;
