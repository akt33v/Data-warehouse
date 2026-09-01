/* =============================================================================
   DIM_DATE HOLIDAY BACKFILL
   -----------------------------------------------------------------------------
   Root cause: 8_init_load.sql's DIM_DATE insert (PART 1) never populates
   Is_Holiday / Holiday_Name -- those columns are left at their table DEFAULT
   ('N' / NULL, see 4_warehouse_tables.sql), for every one of the 4,018 rows
   spanning 2016-01-01 to 2026-12-31. 10_incremental.sql does not reload
   DIM_DATE at all, so this never gets fixed by a later run either.
   Practical effect: any report that segments by Is_Holiday (e.g. Report 9's
   "holiday vs regular-day" voucher analysis) has nothing to compare against.

   Scope of this fix: only Malaysia's FIXED-DATE national/federal holidays are
   backfilled here -- ones whose calendar date never moves year to year, so
   there is zero risk of an incorrect date:
       Jan 1   New Year's Day
       May 1   Labour Day
       Aug 31  Merdeka Day (National Day)
       Sep 16  Malaysia Day
       Dec 25  Christmas Day

   Deliberately OUT of scope: movable/lunar-calendar holidays -- Chinese New
   Year, Hari Raya Aidilfitri/Aidiladha, Deepavali, Wesak Day, the Agong's
   Birthday (2nd Saturday of June), etc. Their dates shift every year and
   guessing them would risk seeding the warehouse with wrong data. If you want
   those included, pull the verified dates for 2016-2026 from an authoritative
   source (e.g. malaysia.gov.my / date.gov.my) and add matching UPDATE
   statements below using the same pattern (WHERE full_date = DATE '...').

   Safe to re-run: every statement is an idempotent UPDATE keyed on exact
   month/day, so running this twice just re-applies the same flags.

   Run once, any time after 8_init_load.sql has populated DIM_DATE:
       SQL> @"C:\Users\User\OneDrive\Desktop\Data Warehouse\Data-warehouse\dim_date_holidays.sql"
   Then re-run any report/export that segments by Is_Holiday (e.g. Report 9's
   htl\r9export.sql) to pick up the change.
   ============================================================================= */
SET DEFINE OFF
SET FEEDBACK ON

UPDATE dim_date
SET is_holiday   = 'Y',
    holiday_name = 'New Year''s Day'
WHERE month_number = 1 AND day_number = 1;

UPDATE dim_date
SET is_holiday   = 'Y',
    holiday_name = 'Labour Day'
WHERE month_number = 5 AND day_number = 1;

UPDATE dim_date
SET is_holiday   = 'Y',
    holiday_name = 'Merdeka Day (National Day)'
WHERE month_number = 8 AND day_number = 31;

UPDATE dim_date
SET is_holiday   = 'Y',
    holiday_name = 'Malaysia Day'
WHERE month_number = 9 AND day_number = 16;

UPDATE dim_date
SET is_holiday   = 'Y',
    holiday_name = 'Christmas Day'
WHERE month_number = 12 AND day_number = 25;

COMMIT;

PROMPT
PROMPT ======= Holiday backfill complete. Verification: =======
SET PAGESIZE 50 LINESIZE 100
COLUMN holiday_name FORMAT A30
COLUMN full_date FORMAT A12
SELECT TO_CHAR(full_date, 'YYYY-MM-DD') AS full_date, holiday_name
FROM dim_date
WHERE is_holiday = 'Y'
ORDER BY full_date;
