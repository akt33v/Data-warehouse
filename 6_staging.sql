-- SHOPGRAB DATA WAREHOUSE ETL
-- STEP 8: STAGING VIEWS
-- Views over the OLTP tables -- no physical staging tables, no duplicated
-- data. Both 09_etl_initial_load.sql and 10_incremental_load.sql read from
-- these views instead of joining the OLTP tables directly, so the lookup
-- joins (member_type, restaurant_category, item_category) and the
-- order-level discount/delivery-fee proration math live in exactly one
-- place instead of being restated in every load script.
--
-- DATA QUALITY applied here (transforms both initial + incremental load):
--   - TRIM()        : remove leading/trailing whitespace from all strings
--   - LOWER()       : normalize email to lowercase
--   - UPPER()       : normalize status/flag fields to uppercase
--   - NVL()         : replace NULL numeric fields with safe defaults
--   - REGEXP_LIKE() : filter rows with invalid email format
--   - WHERE clauses : exclude rows missing critical NOT-NULL fields,
--                     rows with out-of-range values, or structurally invalid
--                     records (zero/negative quantity, future dates, etc.)
--
-- Rows excluded by these WHERE clauses will NOT appear in the load scripts
-- and will not reach the warehouse. The 09_etl_initial_load.sql PL/SQL loops
-- handle per-row logging of any rows that pass the view but fail a business
-- rule check.
--
-- Plain views, not materialized: every SELECT against them reflects the
-- current OLTP state at query time.
--
-- Must run after 01_create_tables.sql (+ data) and before
-- 09_etl_initial_load.sql / 10_incremental_load.sql.

SET DEFINE OFF;

-- ============================================================================
-- VW_STG_MEMBER
-- Excludes rows with NULL member_id, full_name, email, or member_type_id.
-- Excludes rows with malformed email addresses.
-- Normalizes: email lowercase, member_status uppercase, strings trimmed.
-- ============================================================================
CREATE OR REPLACE VIEW vw_stg_member AS
SELECT
    m.member_id,
    TRIM(m.full_name)                    AS full_name,
    LOWER(TRIM(m.email))                 AS email,
    TRIM(mt.type_name)                   AS member_type,
    UPPER(TRIM(m.member_status))         AS member_status,
    m.registration_date
FROM member m
JOIN member_type mt ON mt.member_type_id = m.member_type_id;
-- We intentionally DO NOT filter business rules here (e.g. member_status)
-- so that the PL/SQL procedure can log the rejects in etl_rejected_rows.

-- ============================================================================
-- VW_STG_RESTAURANT
-- Excludes rows with NULL restaurant_id, restaurant_name, or category.
-- Excludes rows with rating outside valid range (0-5).
-- Normalizes: strings trimmed, halal_status uppercase.
-- ============================================================================
CREATE OR REPLACE VIEW vw_stg_restaurant AS
SELECT
    r.restaurant_id,
    TRIM(r.restaurant_name)              AS restaurant_name,
    TRIM(rc.category_name)               AS category,
    UPPER(TRIM(r.halal_status))          AS halal_status,
    r.rating_avg                         AS rating,
    TRIM(r.location_area)                AS location_area
FROM restaurant r
JOIN restaurant_category rc ON rc.restaurant_category_id = r.restaurant_category_id
WHERE r.restaurant_id        IS NOT NULL
  AND TRIM(r.restaurant_name) IS NOT NULL
  AND rc.category_name        IS NOT NULL
  AND r.rating_avg BETWEEN 0 AND 5;

-- ============================================================================
-- VW_STG_MENU_ITEM
-- Excludes rows with NULL item_id, item_name, or item_category_id.
-- Normalizes: strings trimmed, flag fields uppercase.
-- ============================================================================
CREATE OR REPLACE VIEW vw_stg_menu_item AS
SELECT
    mi.item_id,
    TRIM(mi.item_name)                   AS item_name,
    TRIM(ic.category_name)               AS item_category,
    TRIM(mi.item_type)                   AS item_type,
    UPPER(TRIM(mi.budget_meal_flag))     AS budget_meal,
    UPPER(TRIM(mi.super_deal_flag))      AS super_deal
FROM menu_item mi
JOIN item_category ic ON ic.item_category_id = mi.item_category_id
WHERE mi.item_id         IS NOT NULL
  AND TRIM(mi.item_name) IS NOT NULL
  AND ic.category_name   IS NOT NULL;

-- ============================================================================
-- VW_STG_VOUCHER
-- Excludes rows with NULL voucher_id or voucher_code.
-- Excludes rows with negative discount_amount or minimum_order.
-- Normalizes: strings trimmed, voucher_type uppercase.
-- ============================================================================
CREATE OR REPLACE VIEW vw_stg_voucher AS
SELECT
    voucher_id,
    TRIM(voucher_code)                   AS voucher_code,
    UPPER(TRIM(voucher_type))            AS voucher_type,
    NVL(discount_amount, 0)              AS discount_amount,
    NVL(min_order_amount, 0)             AS minimum_order
FROM voucher
WHERE voucher_id                 IS NOT NULL
  AND TRIM(voucher_code)         IS NOT NULL
  AND NVL(discount_amount, 0)    >= 0
  AND NVL(min_order_amount, 0)   >= 0;

-- ============================================================================
-- VW_STG_DELIVERY_COMPANY
-- Excludes rows with NULL delivery_company_id or company_name.
-- Excludes rows with negative base_fee.
-- Normalizes: strings trimmed, service_status uppercase.
-- ============================================================================
CREATE OR REPLACE VIEW vw_stg_delivery_company AS
SELECT
    delivery_company_id,
    TRIM(company_name)                   AS company_name,
    NVL(base_fee, 0)                     AS base_fee,
    UPPER(TRIM(service_status))          AS service_status
FROM delivery_company
WHERE delivery_company_id      IS NOT NULL
  AND TRIM(company_name)        IS NOT NULL
  AND NVL(base_fee, 0)          >= 0;

-- ============================================================================
-- VW_STG_PAYMENT
-- Excludes rows with NULL payment_id, order_id, or payment_method.
-- Normalizes: payment_method and payment_status trimmed + uppercase.
-- ============================================================================
CREATE OR REPLACE VIEW vw_stg_payment AS
SELECT
    payment_id,
    order_id,
    UPPER(TRIM(payment_method))          AS payment_method,
    UPPER(TRIM(payment_status))          AS payment_status
FROM payment
WHERE payment_id             IS NOT NULL
  AND order_id               IS NOT NULL
  AND TRIM(payment_method)   IS NOT NULL;

-- ============================================================================
-- VW_STG_ORDER_SALES
-- One row per order line item, ready to load into FACT_ORDER_SALES after
-- surrogate key resolution.
--
-- Data quality applied:
--   - Excludes order items with NULL order_id, item_id, or member_id
--   - Excludes rows with quantity <= 0 or unit_price < 0
--   - Excludes rows with NULL or future order_datetime
--   - Excludes rows where order_datetime is before DIM_DATE range (2016-01-01)
--   - NULLIF(co.subtotal, 0) prevents divide-by-zero in proration
--
-- Order-level discount_amount / delivery_fee are prorated across line items
-- in proportion to each line's subtotal share. The item with the highest
-- order_item_id in each order absorbs the rounding remainder so that
-- SUM(total_amount) per order reconciles exactly to customer_order.total_amount.
-- ============================================================================
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
    WHERE oi.order_id          IS NOT NULL
      AND oi.item_id           IS NOT NULL
      AND co.member_id         IS NOT NULL
      AND co.restaurant_id     IS NOT NULL
      AND oi.quantity          > 0
      AND oi.unit_price        >= 0
      AND co.order_datetime    IS NOT NULL
      AND co.order_datetime    <= SYSDATE
      AND co.order_datetime    >= DATE '2016-01-01'
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


-- SHOPGRAB DATA WAREHOUSE ETL
-- STAGING + CONTROL + REJECT-LOG SCHEMA
-- Run ONCE (or deliberately to reset). Never run mid-load.
--
-- stg_member_raw / stg_order_raw removed -- ETL reads directly from
-- VW_STG_* views and validates inline; no physical raw staging buffer needed.
--
-- etl_batch_control  : one row per load run per source table; tracks counts.
-- etl_rejected_rows  : one row per rejected OLTP row; stores reason +
--                      validation_rule + raw snapshot for later triage.

SET DEFINE OFF;

PROMPT Dropping existing staging/control objects...
DROP TABLE etl_rejected_rows CASCADE CONSTRAINTS PURGE;
DROP TABLE etl_batch_control CASCADE CONSTRAINTS PURGE;
DROP SEQUENCE etl_batch_id_seq;
DROP SEQUENCE etl_reject_id_seq;

CREATE SEQUENCE etl_batch_id_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE etl_reject_id_seq START WITH 1 INCREMENT BY 1 NOCACHE;

-- --------------------------------------------------------------------------
-- ETL_BATCH_CONTROL
-- One row per (batch_id, source_name) pair.
-- source_name examples: 'MEMBER', 'RESTAURANT', 'MENU_ITEM',
--                       'VOUCHER', 'DELIVERY_CO', 'PAYMENT', 'ORDER_SALES'
-- --------------------------------------------------------------------------
CREATE TABLE etl_batch_control (
    batch_id        NUMBER(10)     NOT NULL,
    source_name     VARCHAR2(30)   NOT NULL,
    batch_status    VARCHAR2(20)   DEFAULT 'PENDING'  NOT NULL,
    row_count       NUMBER(10)     DEFAULT 0           NOT NULL,
    valid_count     NUMBER(10)     DEFAULT 0           NOT NULL,
    rejected_count  NUMBER(10)     DEFAULT 0           NOT NULL,
    loaded_date     DATE           DEFAULT SYSDATE     NOT NULL,
    processed_date  DATE,
    CONSTRAINT pk_etl_batch        PRIMARY KEY (batch_id, source_name),
    CONSTRAINT ck_etl_batch_status CHECK (batch_status IN ('PENDING','PROCESSED','FAILED'))
);

-- --------------------------------------------------------------------------
-- ETL_REJECTED_ROWS
-- One row per bad OLTP row caught during validation.
--
-- source_row_ref  : human-readable PK of the bad row, e.g. "member_id=42"
-- reject_reason   : plain-English description of what failed
-- validation_rule : short rule code for grouping/filtering, e.g.
--                     'NULL_REQUIRED_FIELD'
--                     'INVALID_EMAIL_FORMAT'
--                     'INVALID_STATUS_VALUE'
--                     'NEGATIVE_QUANTITY'
--                     'FUTURE_ORDER_DATE'
--                     'ZERO_SUBTOTAL'
--                     'OUT_OF_RANGE_RATING'
--                     'DB_CONSTRAINT_ERROR'
-- raw_snapshot    : pipe-delimited field dump of the row as it arrived
-- --------------------------------------------------------------------------
CREATE TABLE etl_rejected_rows (
    reject_id        NUMBER(10)     NOT NULL,
    batch_id         NUMBER(10)     NOT NULL,
    source_name      VARCHAR2(30)   NOT NULL,
    source_row_ref   VARCHAR2(100),
    reject_reason    VARCHAR2(400)  NOT NULL,
    validation_rule  VARCHAR2(60),
    raw_snapshot     VARCHAR2(2000),
    rejected_date    DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_etl_reject PRIMARY KEY (reject_id)
);

PROMPT ======= Staging/control schema created (batch control + reject log only) =======;
