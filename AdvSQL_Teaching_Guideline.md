# Business Analytics SQL Teaching Guideline

**Advanced SQL Patterns for BI & Data Warehousing Instruction**
*Companion to: Sales Star Schema Business Analytics Reports*
*Source Schema: SALES_FACT | CUSTOMER_DIM | PRODUCT_DIM | DATE_DIM | EMPLOYEE_DIM*

## Purpose of This Guideline

This document is a teaching companion for the six business analytics reports already prepared on the sales star schema. Where the reports document focuses on the finished output (SQL + chart + panel mapping), this guideline focuses on the underlying SQL techniques that students need to master before they can build reports like those independently.

Each technique below includes: the concept, why it matters for business analytics and BI tooling specifically, a runnable SQL example against the existing schema, sample output, and suggested teaching points or exercises. Techniques are sequenced from foundational to advanced so they can be taught across multiple sessions.

## Learning Objectives

* Reshape data between long (row-based) and wide (column-based) formats using PIVOT and UNPIVOT.
* Apply window functions (RANK, LAG, running totals) to answer comparative and time-series questions.
* Generate multi-level subtotals automatically using ROLLUP, CUBE, and GROUPING SETS.
* Structure multi-step logic clearly and testably using Common Table Expressions (CTEs).
* Segment customers or products into buckets using NTILE and CASE WHEN.
* Connect each SQL technique to a specific business analytics use case and an appropriate chart type.

## Schema Recap

All examples in this guideline use the same star schema as the reports document: one fact table and four dimensions.

| Table | Key Fields |
| :--- | :--- |
| **SALES_FACT** | DATE_KEY, CUSTOMER_KEY, PRODUCT_KEY, EMPLOYEE_KEY, ORDERID, UNITPRICE, QUANTITY, DISCOUNT, LINE_TOTAL |
| **CUSTOMER_DIM** | CUSTOMER_KEY, CUSTOMERID, COMPANY_NAME, COUNTRY, REGION, CITY, POSTALCODE |
| **PRODUCT_DIM** | PRODUCT_KEY, PRODUCTID, PRODUCT_NAME, CATEGORYNAME, SUP_COMPANYNAME, SUP_COUNTRY, SUP_CITY |
| **DATE_DIM** | DATE_KEY, CAL_DATE, CAL_QUARTER, CAL_MONTH_YEAR, CAL_YEAR, HOLIDAY_IND, WEEKDAY_IND |
| **EMPLOYEE_DIM** | EMPLOYEEKEY, EMPLOYEEID, EMP_NAME, HIREDATE, COUNTRY, CITY |

## Suggested Teaching Sequence

A recommended order for introducing these topics across a typical BA/BI module. Each session assumes ~90 minutes including a live-coding demo and a short student exercise.

| Session | Topic | Difficulty | Builds On |
| :--- | :--- | :--- | :--- |
| 1 | CASE WHEN bucketing + manual PIVOT (already used in Report 1) | Foundational | GROUP BY, aggregate functions |
| 2 | Native PIVOT/UNPIVOT | Foundational-Intermediate | Session 1 |
| 3 | CTEs (WITH clause) | Intermediate | Subqueries |
| 4 | Window functions: RANK, DENSE_RANK, ROW_NUMBER | Intermediate | ORDER BY, GROUP BY |
| 5 | Window functions: running totals, LAG/LEAD | Intermediate-Advanced | Session 4 |
| 6 | ROLLUP, CUBE, GROUPING SETS | Advanced | GROUP BY |
| 7 | NTILE segmentation + capstone mini-project | Advanced | Sessions 1-6 |

## 1. CASE WHEN Bucketing (Foundation for Pivoting)

**Concept:** `CASE WHEN` lets you derive a new categorical value from an existing column—the building block for manual pivoting and for grouping continuous values into buckets.

**Why It Matters for Business Analytics:** Almost every dashboard needs derived categories that don't exist in the raw data (order size tiers, customer segments, quarter columns). Students already saw this in Report 1's manual PIVOT via `SUM(CASE WHEN...)`.

**SQL Example**
```sql
SELECT
  CASE
    WHEN S.LINE_TOTAL < 100 THEN 'Small'
    WHEN S.LINE_TOTAL BETWEEN 100 AND 500 THEN 'Medium'
    ELSE 'Large'
  END AS ORDER_SIZE,
  COUNT(*) AS ORDER_COUNT,
  SUM(S.LINE_TOTAL) AS REVENUE
FROM SALES_FACT S
GROUP BY
  CASE
    WHEN S.LINE_TOTAL < 100 THEN 'Small'
    WHEN S.LINE_TOTAL BETWEEN 100 AND 500 THEN 'Medium'
    ELSE 'Large'
  END;
```

**Sample Output**
| Order Size | Order Count | Revenue |
| :--- | :--- | :--- |
| Small | 1,240 | $62,400 |
| Medium | 980 | $245,100 |
| Large | 310 | $186,700 |

**Teaching Points**
* Show students that the CASE expression must be repeated identically in SELECT and GROUP BY (in engines without alias support in GROUP BY).
* This is the conceptual seed of PIVOT: "What if each bucket became its own column instead of its own row?"
* Ask: what happens if a row doesn't match any WHEN condition and there's no ELSE? (NULL trap - good debugging lesson.)

**Suggested Student Exercise**
Ask students to add a fourth tier ('Extra Large' for LINE_TOTAL > 1000) and recompute the distribution. Then have them chart it as a simple bar chart of ORDER_COUNT by ORDER_SIZE.

## 2. PIVOT and UNPIVOT

**Concept:** `PIVOT` reshapes long/row-based data into a wide/column-based crosstab. `UNPIVOT` reverses this, turning columns back into rows. Most SQL engines (Oracle 11g+, SQL Server) support native syntax; others require the manual CASE WHEN approach from Topic 1.

**Why It Matters for Business Analytics:** BI tools and spreadsheets often expect wide, crosstab-shaped data (one column per quarter/year/category), while a normalized fact table is naturally long. Knowing both directions lets students move fluidly between "database-friendly" and "report-friendly" shapes.

**SQL Example**
*PIVOT: quarters become columns*
```sql
SELECT * FROM (
  SELECT c.COUNTRY, d.CAL_QUARTER, S.LINE_TOTAL
  FROM SALES_FACT s
  JOIN CUSTOMER_DIM c ON s.CUSTOMER_KEY = c.CUSTOMER_KEY
  JOIN DATE_DIM d ON s.DATE_KEY = d.DATE_KEY
)
PIVOT (
  SUM(LINE_TOTAL)
  FOR CAL_QUARTER IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);
```

*UNPIVOT: columns become rows (reverse operation)*
```sql
CREATE TABLE quarterly_pivot_table as
SELECT * FROM (
  SELECT c.COUNTRY, d.CAL_QUARTER, S.LINE_TOTAL
  FROM SALES_FACT s
  JOIN CUSTOMER_DIM c ON s.CUSTOMER_KEY = c.CUSTOMER_KEY
  JOIN DATE_DIM d ON s.DATE_KEY = d.DATE_KEY
)
PIVOT (
  SUM(LINE_TOTAL)
  FOR CAL_QUARTER IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

SELECT COUNTRY, QUARTER, REVENUE
FROM quarterly_pivot_table
UNPIVOT (REVENUE FOR QUARTER IN (Q1, Q2, Q3, Q4));
```

**Sample Output**
| Country | Q1 | Q2 | Q3 | Q4 |
| :--- | :--- | :--- | :--- | :--- |
| USA | $42,000 | $45,000 | $50,000 | $60,000 |
| Germany | $30,000 | $33,000 | $31,000 | $38,000 |
| UK | $27,000 | $25,000 | $29,000 | $34,000 |

**Teaching Points**
* Run the manual CASE WHEN version from Report 1 side-by-side with native PIVOT — same output, less code.
* Not every RDBMS supports PIVOT natively (e.g., MySQL does not) — worth flagging platform differences early.
* UNPIVOT is the more surprising one for students: emphasize it's used far less often but is essential when importing wide spreadsheet data into a normalized table.

**Suggested Student Exercise**
Have students PIVOT the same query by CATEGORYNAME instead of CAL_QUARTER, then UNPIVOT their own result back to the original long format and confirm row counts match.

## 3. Common Table Expressions (CTEs)

**Concept:** A CTE, defined with `WITH`, names a temporary result set that can be referenced later in the same query—like a subquery, but readable top-to-bottom and reusable multiple times.

**Why It Matters for Business Analytics:** Real BI queries often require multiple logical steps (aggregate, then filter, then rank). CTEs let students break a complex query into named, independently testable pieces—a habit that transfers directly to writing maintainable analytics code.

**SQL Example**
```sql
WITH monthly_revenue AS (
  SELECT d.CAL_MONTH_YEAR, SUM(S.LINE_TOTAL) AS REVENUE
  FROM SALES_FACT S
  JOIN DATE_DIM d ON S.DATE_KEY = d.DATE_KEY
  GROUP BY d.CAL_MONTH_YEAR
)
SELECT CAL_MONTH_YEAR, REVENUE
FROM monthly_revenue
WHERE REVENUE > (SELECT AVG(REVENUE) FROM monthly_revenue)
ORDER BY REVENUE DESC;
```

**Sample Output**
| Month | Revenue |
| :--- | :--- |
| Dec | $68,300 |
| Nov | $61,200 |
| Oct | $55,900 |

**Teaching Points**
* Have students run just the CTE block as a standalone SELECT first — reinforces that a CTE is 'a query you can preview before using it.'
* Contrast with the equivalent nested-subquery version to show CTEs are readability sugar, not new capability, in most engines.
* Multiple CTEs can chain: `WITH a AS (...), b AS (SELECT ... FROM a)` - worth a quick demo for advanced students.

**Suggested Student Exercise**
Ask students to rewrite one of the six existing reports (e.g., Report 6, Customer Value) using a CTE that first computes REVENUE_PER_CUSTOMER, then filters to only countries above the overall average.

## 4. Window Functions: RANK, DENSE_RANK, ROW_NUMBER

**Concept:** Window functions compute a value across a set of rows related to the current row (a "window") without collapsing rows the way GROUP BY does. `PARTITION BY` defines the window; `ORDER BY` defines the ranking order within it.

**Why It Matters for Business Analytics:** Leaderboards, top-N-per-group reports, and "best performer per region" questions are extremely common in BI and are awkward or impossible with plain GROUP BY. This is one of the highest-value skills for analytics interviews.

**SQL Example**
```sql
SELECT e.COUNTRY, e.EMP_NAME,
  SUM(S.LINE_TOTAL) AS TOTAL_SALES,
  RANK() OVER (PARTITION BY e.COUNTRY ORDER BY SUM(s.LINE_TOTAL) DESC) AS RNK,
  DENSE_RANK() OVER (PARTITION BY e.COUNTRY ORDER BY SUM(S.LINE_TOTAL) DESC) AS DENSE_RNK,
  ROW_NUMBER() OVER (PARTITION BY e.COUNTRY ORDER BY SUM(S.LINE_TOTAL) DESC) AS ROW_NUM
FROM SALES_FACT S
JOIN EMPLOYEE_DIM e ON S.EMPLOYEE_KEY = e.EMPLOYEE_KEY
GROUP BY e.COUNTRY, e.EMP_NAME
ORDER BY e.COUNTRY, RNK;
```

**Sample Output**
| Country | Employee | Total Sales | Rank |
| :--- | :--- | :--- | :--- |
| USA | J. Leverling | $105,000 | 1 |
| USA | N. Davolio | $95,000 | 2 |
| USA | A. Fuller | $87,000 | 3 (tie) |
| USA | L. Callahan | $87,000 | 3 (tie) |
| UK | R. King | $71,000 | 1 |

**Teaching Points**
* Deliberately construct or point out a tie in TOTAL_SALES so students see RANK() skip a number (1,2,3,3,5) while DENSE_RANK() does not (1,2,3,3,4).
* ROW_NUMBER() always gives unique numbers even on ties — useful for pagination or picking 'exactly one top row per group.'
* Follow-up query pattern to memorize: wrap this in a CTE and filter `WHERE RNK = 1` to get 'top employee per country' cleanly.

**Suggested Student Exercise**
Have students write a query that returns only the #1 ranked product by revenue within each CATEGORYNAME, using a CTE + RANK() + an outer WHERE RNK = 1 filter.

## 5. Window Functions: Running Totals and LAG/LEAD

**Concept:** `SUM() OVER (ORDER BY ...)` produces a running/cumulative total without collapsing rows. `LAG()` and `LEAD()` let a row see a value from a previous or following row—the basis of period-over-period comparisons.

**Why It Matters for Business Analytics:** Running totals and month-over-month % change are two of the most requested KPIs in any sales or finance dashboard, and are difficult to compute correctly with plain SQL aggregation alone.

**SQL Example**
*Running total*
```sql
SELECT d.CAL_MONTH_YEAR,
  SUM(S.LINE_TOTAL) AS MONTHLY_REVENUE,
  SUM(SUM(S.LINE_TOTAL)) OVER (ORDER BY d.CAL_MONTH_YEAR) AS RUNNING_TOTAL
FROM SALES_FACT S
JOIN DATE_DIM d ON s.DATE_KEY = d.DATE_KEY
GROUP BY d.CAL_MONTH_YEAR
ORDER BY d.CAL_MONTH_YEAR;
```

*Month-over-month % change using LAG*
```sql
SELECT d.CAL_MONTH_YEAR,
  SUM(S.LINE_TOTAL) AS REVENUE,
  ROUND((SUM(S.LINE_TOTAL) - LAG(SUM(s.LINE_TOTAL)) OVER (ORDER BY d.CAL_MONTH_YEAR)) 
  / LAG(SUM(s.LINE_TOTAL)) OVER (ORDER BY d.CAL_MONTH_YEAR) * 100, 1) AS PCT_CHANGE
FROM SALES_FACT S
JOIN DATE_DIM d ON s.DATE_KEY = d.DATE_KEY
GROUP BY d.CAL_MONTH_YEAR
ORDER BY d.CAL_MONTH_YEAR;
```

**Sample Output**
| Month | Revenue | Running Total | % Change |
| :--- | :--- | :--- | :--- |
| Jan | $41,500 | $41,500 | |
| Feb | $43,100 | $84,600 | 3.9% |
| Mar | $44,800 | $129,400 | 3.9% |
| Apr | $40,200 | $169,600 | -10.3% |

**Teaching Points**
* Point out the double SUM: the inner SUM aggregates line items per month; the outer `SUM() OVER` is the window function running on top of the grouped result.
* The first row of a LAG() column is always NULL - ask students why, and how they'd handle it (COALESCE, or just accept it as 'no prior period').
* This is the natural SQL counterpart to the line chart used in Report 4 — the running total column is literally the data behind a cumulative line chart.

**Suggested Student Exercise**
Ask students to add a 3-month moving average using `AVG(...) OVER (ORDER BY CAL_MONTH_YEAR ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` and plot it alongside monthly revenue.

## 6. ROLLUP, CUBE, and GROUPING SETS

**Concept:** `ROLLUP` produces hierarchical subtotals (e.g., by country, then a grand total). `CUBE` produces every possible combination of subtotals. `GROUPING SETS` lets you specify exactly which subtotal combinations you want, with full control.

**Why It Matters for Business Analytics:** This is the 'real SQL' equivalent of the COMPUTE SUM / BREAK ON subtotals used in the SQL*Plus reports—worth teaching directly after those reports to show the same output can be generated purely in the query, independent of any reporting tool.

**SQL Example**
*ROLLUP: subtotal per country, then grand total*
```sql
SELECT c.COUNTRY, P.CATEGORYNAME, SUM(S.LINE_TOTAL) AS REVENUE
FROM SALES_FACT s
JOIN CUSTOMER_DIM c ON S.CUSTOMER_KEY = c.CUSTOMER_KEY
JOIN PRODUCT_DIM P ON S.PRODUCT_KEY = P.PRODUCT_KEY
GROUP BY ROLLUP (c.COUNTRY, P.CATEGORYNAME);
```

*CUBE: every combination (country-only, category-only, both, grand total)*
```sql
SELECT c.COUNTRY, P.CATEGORYNAME, SUM(S.LINE_TOTAL) AS REVENUE
FROM SALES_FACT S
JOIN CUSTOMER_DIM c ON S.CUSTOMER_KEY = c.CUSTOMER_KEY
JOIN PRODUCT_DIM P ON S.PRODUCT_KEY = P.PRODUCT_KEY
GROUP BY CUBE (c.COUNTRY, P.CATEGORYNAME);
```

*GROUPING SETS: pick exactly the subtotal levels you want*
```sql
SELECT c.COUNTRY, p.CATEGORYNAME, SUM(S.LINE_TOTAL) AS REVENUE
FROM SALES_FACT S
JOIN CUSTOMER_DIM c ON S.CUSTOMER_KEY = c.CUSTOMER_KEY
JOIN PRODUCT_DIM p ON s.PRODUCT_KEY = P.PRODUCT_KEY
GROUP BY GROUPING SETS ((c.COUNTRY, p.CATEGORYNAME), (c.COUNTRY), ());
```

**Sample Output**
| Country | Category | Revenue |
| :--- | :--- | :--- |
| USA | Beverages | $33,600 |
| USA | Condiments | $21,900 |
| USA | (subtotal) | $55,500 |
| Germany | Beverages | $19,200 |
| Germany | (subtotal) | $19,200 |
| (grand total) | | $74,700 |

**Teaching Points**
* Have students run ROLLUP and CUBE on the same two columns side-by-side and compare row counts — CUBE will visibly produce more rows (including a category-only subtotal with no country).
* The extra subtotal rows can be identified programmatically using the `GROUPING()` function - worth a brief mention for advanced students building downstream logic.
* Connect this directly back to Report 1 and Report 2's BREAK ON/COMPUTE SUM - same conceptual output, generated differently.

**Suggested Student Exercise**
Ask students to use GROUPING SETS to reproduce exactly the subtotal structure from Report 3 (subtotal per country, no grand total, no category-only rows) and explain why GROUPING SETS was the right tool instead of ROLLUP or CUBE.

## 7. NTILE - Segmentation into Buckets

**Concept:** `NTILE(n)` divides ordered rows into n roughly equal-sized groups and labels each row with its group number—a direct SQL tool for quartiles, quintiles, or any n-way segmentation.

**Why It Matters for Business Analytics:** Customer segmentation (e.g., top-quartile spenders vs. bottom-quartile) is foundational to RFM analysis, loyalty tiering, and targeted marketing—all classic business analytics deliverables.

**SQL Example**
```sql
SELECT c.CUSTOMER_KEY, c.COMPANYNAME,
  SUM(S.LINE_TOTAL) AS TOTAL_SPEND,
  NTILE (4) OVER (ORDER BY SUM(S.LINE_TOTAL) DESC) AS SPEND_QUARTILE
FROM SALES_FACT S
JOIN CUSTOMER_DIM c ON S.CUSTOMER_KEY = c.CUSTOMER_KEY
GROUP BY c.CUSTOMER_KEY, c.COMPANYNAME
ORDER BY SPEND_QUARTILE, TOTAL_SPEND DESC;
```

**Sample Output**
| Customer | Total Spend | Quartile |
| :--- | :--- | :--- |
| Alpha Traders | $18,400 | 1 |
| Beta Foods | $15,200 | 1 |
| Gamma Retail | $9,800 | 2 |
| Delta Mart | $4,100 | 3 |
| Epsilon Co. | $1,200 | 4 |

**Teaching Points**
* If the row count isn't evenly divisible by 4, NTILE distributes the remainder to the earliest groups first — worth demonstrating with a small, odd-sized dataset.
* Quartile 1 here is the 'top' group because of `ORDER BY... DESC` - flag this explicitly, since NTILE labels 1 as 'first in sort order,' not 'best' by default.
* This pairs naturally with a marketing discussion: what campaign would you run differently for quartile 1 vs. quartile 4 customers?

**Suggested Student Exercise**
As a capstone exercise, have students combine everything: use a CTE to compute TOTAL_SPEND per customer, apply NTILE(4), then JOIN back to CUSTOMER_DIM to show COUNTRY alongside quartile - and chart average spend by quartile as a bar chart.

## Quick-Reference: Syntax Cheat Sheet

A condensed reference for students to keep beside them during lab exercises.

| Technique | Minimal Syntax Pattern |
| :--- | :--- |
| **PIVOT** | `SELECT * FROM (subquery) PIVOT (AGG(col) FOR pivot_col IN (val1, val2, ...))` |
| **UNPIVOT** | `SELECT ... FROM table UNPIVOT (value_col FOR label_col IN (col1, col2, ...))` |
| **CTE** | `WITH name AS (SELECT ...) SELECT... FROM name` |
| **RANK/DENSE_RANK/ROW_NUMBER** | `FUNC() OVER (PARTITION BY col ORDER BY col)` |
| **Running Total** | `SUM(measure) OVER (ORDER BY col)` |
| **LAG/LEAD** | `LAG(measure) OVER (ORDER BY col)` |
| **ROLLUP** | `GROUP BY ROLLUP (col1, col2)` |
| **CUBE** | `GROUP BY CUBE (col1, col2)` |
| **GROUPING SETS** | `GROUP BY GROUPING SETS ((col1, col2), (col1), ())` |
| **NTILE** | `NTILE(n) OVER (ORDER BY measure)` |
| **CASE WHEN** | `CASE WHEN cond THEN val ... ELSE default END` |
