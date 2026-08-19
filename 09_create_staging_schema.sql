-- SHOPGRAB DATA WAREHOUSE ETL
-- STEP 9: STAGING + CONTROL + REJECT-LOG SCHEMA FOR SUBSEQUENT (INCREMENTAL)
-- LOADING. Run this ONCE (or deliberately, to wipe the staging area back to
-- empty) -- NOT as part of the routine incremental load job. The repeatable
-- load logic lives in 10_incremental_load_and_scrub.sql, which reads and
-- writes these tables but never drops them; that split is what lets
-- ETL_BATCH_CONTROL actually track "already processed" state across runs
-- instead of losing it every time the load script executes.
--
-- Staging tables are deliberately loosely typed (VARCHAR2 for almost
-- everything) and carry none of the OLTP tables' constraints -- that's the
-- point: they have to be able to hold genuinely dirty incoming data so the
-- scrub step in 10_incremental_load_and_scrub.sql has something real to
-- validate against.

SET DEFINE OFF;

PROMPT Dropping existing staging/control objects...
DROP TABLE stg_order_raw CASCADE CONSTRAINTS PURGE;
DROP TABLE stg_member_raw CASCADE CONSTRAINTS PURGE;
DROP TABLE etl_rejected_rows CASCADE CONSTRAINTS PURGE;
DROP TABLE etl_batch_control CASCADE CONSTRAINTS PURGE;
DROP SEQUENCE etl_batch_id_seq;
DROP SEQUENCE etl_reject_id_seq;

CREATE SEQUENCE etl_batch_id_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE etl_reject_id_seq START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE TABLE etl_batch_control (
    batch_id        NUMBER(10)     NOT NULL,
    source_name     VARCHAR2(30)   NOT NULL,
    batch_status    VARCHAR2(20)   DEFAULT 'PENDING' NOT NULL,
    row_count       NUMBER(10)     DEFAULT 0 NOT NULL,
    valid_count     NUMBER(10)     DEFAULT 0 NOT NULL,
    rejected_count  NUMBER(10)     DEFAULT 0 NOT NULL,
    loaded_date     DATE           DEFAULT SYSDATE NOT NULL,
    processed_date  DATE,
    CONSTRAINT pk_etl_batch PRIMARY KEY (batch_id, source_name),
    CONSTRAINT ck_etl_batch_status CHECK (batch_status IN ('PENDING', 'PROCESSED', 'FAILED'))
);

CREATE TABLE etl_rejected_rows (
    reject_id        NUMBER(10)     NOT NULL,
    batch_id         NUMBER(10)     NOT NULL,
    source_name      VARCHAR2(30)   NOT NULL,
    source_row_ref   VARCHAR2(100),
    reject_reason    VARCHAR2(400)  NOT NULL,
    raw_snapshot     VARCHAR2(1000),
    rejected_date    DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_etl_reject PRIMARY KEY (reject_id)
);

CREATE TABLE stg_member_raw (
    batch_id             NUMBER(10)     NOT NULL,
    stg_row_id           NUMBER(10)     NOT NULL,
    member_type_raw      VARCHAR2(30),
    full_name_raw        VARCHAR2(150),
    email_raw            VARCHAR2(150),
    phone_no_raw         VARCHAR2(50),
    password_hash_raw    VARCHAR2(255),
    registration_dt_raw  VARCHAR2(30),
    member_status_raw    VARCHAR2(30),
    loaded_date          DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_stg_member_raw PRIMARY KEY (batch_id, stg_row_id)
);

CREATE TABLE stg_order_raw (
    batch_id             NUMBER(10)     NOT NULL,
    stg_row_id           NUMBER(10)     NOT NULL,
    member_id_raw        VARCHAR2(30),
    restaurant_id_raw    VARCHAR2(30),
    item_id_raw          VARCHAR2(30),
    quantity_raw         VARCHAR2(30),
    order_type_raw       VARCHAR2(30),
    order_datetime_raw   VARCHAR2(30),
    payment_method_raw   VARCHAR2(30),
    loaded_date          DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_stg_order_raw PRIMARY KEY (batch_id, stg_row_id)
);

PROMPT ======= Staging/control schema created =======;
