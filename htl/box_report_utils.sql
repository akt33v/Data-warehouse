/* =============================================================================
   BOX REPORT UTILITIES
   -----------------------------------------------------------------------------
   PRINT_BOXED_TABLE(p_sql, p_title) runs any arbitrary SELECT statement and
   prints its result as an ASCII box-bordered table straight to the SQL*Plus
   console via DBMS_OUTPUT, e.g.:

       +------------+-----------+---------+-----------+---------------+
       | CATEGORY   | MEAL_TIER | TYPE    | QTY_SOLD  | REVENUE (RM)  |
       +------------+-----------+---------+-----------+---------------+
       | Noodles    | BUDGET    | FOOD    |     1,240 |     18,650.00 |
       | Noodles    | PREMIUM   | FOOD    |       410 |     12,300.00 |
       +------------+-----------+---------+-----------+---------------+
       (2 rows)

   Column widths auto-size to the widest header/value. NUMBER columns are
   right-aligned; everything else is left-aligned. Uses DBMS_SQL so it works
   against any query text without needing to know its columns in advance
   (classic dynamic "print_table" pattern).

   Run ONCE per schema (creates the procedure under whichever user you are
   connected as, e.g. SGRAB):
       SQL> @"C:\Users\User\OneDrive\Desktop\Data Warehouse\Data-warehouse\htl\box_report_utils.sql"
   ============================================================================= */
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PROCEDURE print_boxed_table(
    p_sql   IN VARCHAR2,
    p_title IN VARCHAR2 DEFAULT NULL
) IS
    c_cursor    INTEGER;
    d_col_cnt   INTEGER;
    d_desc_tab  DBMS_SQL.DESC_TAB;
    v_status    INTEGER;
    v_value     VARCHAR2(4000);

    TYPE t_str_arr IS TABLE OF VARCHAR2(4000) INDEX BY PLS_INTEGER;
    v_widths     t_str_arr;
    v_headers    t_str_arr;
    v_is_numeric t_str_arr;

    TYPE t_row  IS TABLE OF VARCHAR2(4000) INDEX BY PLS_INTEGER;
    TYPE t_rows IS TABLE OF t_row INDEX BY PLS_INTEGER;
    v_rows       t_rows;
    v_row_count  PLS_INTEGER := 0;

    v_border VARCHAR2(32000);
    v_line   VARCHAR2(32000);
BEGIN
    IF p_title IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(CHR(10) || p_title);
    END IF;

    c_cursor := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(c_cursor, p_sql, DBMS_SQL.NATIVE);
    DBMS_SQL.DESCRIBE_COLUMNS(c_cursor, d_col_cnt, d_desc_tab);

    FOR i IN 1..d_col_cnt LOOP
        -- Define every column as VARCHAR2: DBMS_SQL implicitly TO_CHAR's
        -- NUMBER/DATE columns into it, so this works for any result shape.
        DBMS_SQL.DEFINE_COLUMN(c_cursor, i, v_value, 4000);
        v_headers(i)    := d_desc_tab(i).col_name;
        v_widths(i)     := LENGTH(v_headers(i));
        v_is_numeric(i) := CASE WHEN d_desc_tab(i).col_type IN (2) THEN 'Y' ELSE 'N' END; -- 2 = NUMBER
    END LOOP;

    v_status := DBMS_SQL.EXECUTE(c_cursor);

    LOOP
        EXIT WHEN DBMS_SQL.FETCH_ROWS(c_cursor) = 0;
        v_row_count := v_row_count + 1;
        FOR i IN 1..d_col_cnt LOOP
            DBMS_SQL.COLUMN_VALUE(c_cursor, i, v_value);
            v_rows(v_row_count)(i) := NVL(v_value, '-');
            IF LENGTH(v_rows(v_row_count)(i)) > v_widths(i) THEN
                v_widths(i) := LENGTH(v_rows(v_row_count)(i));
            END IF;
        END LOOP;
    END LOOP;

    DBMS_SQL.CLOSE_CURSOR(c_cursor);

    -- Top border / header row / separator
    v_border := '+';
    FOR i IN 1..d_col_cnt LOOP
        v_border := v_border || RPAD('-', v_widths(i) + 2, '-') || '+';
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(v_border);
    v_line := '|';
    FOR i IN 1..d_col_cnt LOOP
        v_line := v_line || ' ' || RPAD(v_headers(i), v_widths(i)) || ' |';
    END LOOP;
    DBMS_OUTPUT.PUT_LINE(v_line);
    DBMS_OUTPUT.PUT_LINE(v_border);

    -- Data rows
    FOR r IN 1..v_row_count LOOP
        v_line := '|';
        FOR i IN 1..d_col_cnt LOOP
            IF v_is_numeric(i) = 'Y' THEN
                v_line := v_line || ' ' || LPAD(v_rows(r)(i), v_widths(i)) || ' |';
            ELSE
                v_line := v_line || ' ' || RPAD(v_rows(r)(i), v_widths(i)) || ' |';
            END IF;
        END LOOP;
        DBMS_OUTPUT.PUT_LINE(v_line);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(v_border);
    DBMS_OUTPUT.PUT_LINE('(' || v_row_count || CASE WHEN v_row_count = 1 THEN ' row)' ELSE ' rows)' END);

EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_SQL.IS_OPEN(c_cursor) THEN
            DBMS_SQL.CLOSE_CURSOR(c_cursor);
        END IF;
        RAISE;
END print_boxed_table;
/

SHOW ERRORS PROCEDURE print_boxed_table
