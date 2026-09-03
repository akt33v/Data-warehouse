# ShopGrab Food Delivery Platform — Data Warehouse Assignment Execution Guide

**Prepared by:**
- **TAN JIN YUAN** (25WMR12328)
- **HENG TIAN LI** (25WMR12376)
- **CHEN XIANG HUI** (25WMR12896)

This comprehensive guide outlines the exact file execution order and instructions for building, loading, verifying, reporting, and visualizing the Data Warehouse for the **ShopGrab** Food Delivery Platform.

---

## 🛠️ Prerequisites & Environment Setup

- **Database Engine**: Oracle Database (19c / 21c / 23c / XE)
- **SQL Clients**: SQL*Plus, Oracle SQL Developer, or SQLcl
- **Python Environment** (for visualizations): Python 3.8+
  ```bash
  pip install pandas matplotlib seaborn jupyter
  ```
  *(Or activate the virtual environment if configured: `.\dw\Scripts\activate` on Windows)*

---

## 📋 1. Core Data Warehouse Pipeline

Execute the SQL scripts in the root directory in the following sequential order:

| Step | Script | Description |
| :---: | :--- | :--- |
| **0** | `0_reset.sql` | Drops all existing OLTP tables, warehouse tables, sequences, and constraints for a clean slate. |
| **1** | `1_tables.sql` | Creates the OLTP transactional database schema (members, restaurants, menu items, orders, deliveries, vouchers, payments). |
| **2** | `2_data.sql` | Inserts seed and historical operational data into the OLTP transactional tables. |
| **3** | `3_verify.sql` | Verifies OLTP row counts, constraints, primary/foreign key integrity, and business rules. |
| **4** | `4_warehouse_tables.sql` | Creates the Data Warehouse Star Schema dimension tables (`Dim_Member`, `Dim_Restaurant`, `Dim_Menu_Item`, `Dim_Delivery_Company`, `Dim_Voucher`, `Dim_Payment`, `Dim_Date`, `etl_rejected_rows`) and central `Fact_Order_Sales`. |
| **5** | `5_verifyDW.sql` | Audits the initial state and structure of warehouse tables prior to data ingestion. |
| **6** | `6_staging.sql` | Creates staging views (`vw_stg_*`) for data cleansing, text trimming, email validation, and discount/delivery fee proration across order line items. |
| **7** | `7_stored_procs.sql` | Compiles PL/SQL ETL stored procedures with SCD Type 2 versioning logic and error logging into `etl_rejected_rows`. |
| **8** | `8_init_load.sql` | Performs initial historical load: generates calendar date dimension (`Dim_Date`) and populates dimensions and `Fact_Order_Sales` from staging views. |
| **9** | `9_dim_date_holidays.sql` | Populates Malaysian public holidays and calendar boundary flags in `Dim_Date`. |
| **10** | `10_incremental.sql` | Executes incremental delta load using MERGE and SCD2 logic for new/modified records. |
| **11** | `5_verifyDW.sql` | Re-verifies populated warehouse row counts, grain consistency, and measure sums. |

---

## 🔄 2. Slowly Changing Dimension (SCD Type 2) Demonstration

```sql
@scd2_demo.sql
```
- `scd2_demo.sql`: Demonstrates Slowly Changing Dimension (SCD Type 2) lifecycle tracking on `DIM_MEMBER`:
  1. Inserts a brand new member into the OLTP table and synchronizes to `DIM_MEMBER`.
  2. Updates member attributes (e.g., status/email) in OLTP, triggering ETL to expire the old record (`current_flag = 'N'`, `expiry_date` set) and insert a new active version (`current_flag = 'Y'`).
  3. Tests idempotency and data integrity.

---

## 📑 3. Analytical Reports & Data Exports

### 🔹 Heng Tian Li Reports
#### Product Performance, Voucher ROI & Delivery Partner Concentration
```sql
@htl/box_report_utils.sql
@htl/report7.sql
@htl/report9.sql
@htl/report11.sql
@htl/r7export.sql
@htl/r9export.sql
@htl/r11export.sql
```
- `htl/box_report_utils.sql`: Formatter package for ASCII boxed report tables (run once before reports).
- `htl/report7.sql`: **Report 7 — Menu Item Category Performance** (Budget vs. Premium, Super Deals, QoQ growth, price quartiles).
- `htl/report9.sql`: **Report 9 — Voucher Campaign ROI & Conversion Analysis** (Revenue per RM discount, Holiday vs. Weekday).
- `htl/report11.sql`: **Report 11 — Delivery Partner Performance & Operational Reliance** (Market share %, weekend reliance, concentration risk).
- `htl/r7export.sql`, `htl/r9export.sql`, `htl/r11export.sql`: Exports report datasets to CSV for visualization.

### 🔹 Tan Jin Yuan Reports 
#### Customer Lifetime Value, Churn Risk & Restaurant Rankings
```sql
@tjy/report1.sql
@tjy/report2.sql
@tjy/report3.sql
@tjy/r1export.sql
@tjy/r2export.sql
@tjy/r3export.sql
```
- `tjy/report1.sql`: **Report 1 — Customer Value Cube** (Cohort lifetime value by year, member type, restaurant category with interactive drill-down).
- `tjy/report2.sql`: **Report 2 — Member Churn Risk & Retention Analysis** (RFM Recency, churn risk scoring, revenue at risk assessment).
- `tjy/report3.sql`: **Report 3 — Top Performing Restaurants & Rating Correlation** (Window `RANK`, `LAG` QoQ %, `NTILE` performance quartiles).
- `tjy/r1export.sql`, `tjy/r2export.sql`, `tjy/r3export.sql`: Exports report datasets to CSV for dashboards.

### 🔹 Chen Xiang Hui Reports
#### Order Fulfilment, Payment Behavior & Promotion Effectiveness
```sql
@cxh/11_visualization_queries.sql
@cxh/12_export_visualizations.sql
```
- `cxh/11_visualization_queries.sql`: Interactive queries analyzing delivery partner volume & fee trends, payment method success/failure/refund rates, and top voucher discount vs. revenue impact.
- `cxh/12_export_visualizations.sql`: Spools visual datasets into CSV files (`order_fulfilment_delivery_performance.csv`, `payment_method_order_behaviour.csv`, `voucher_promotion_effectiveness.csv`).

---

## 📊 4. Generating Visual Dashboards & Analytics

After running the respective SQL export scripts, generate visual charts and dashboards via Python scripts or Jupyter Notebooks:

### 🐍 Python Scripts (`.py`)
Run standalone Python scripts in your terminal to generate high-resolution dashboard figures:

```bash
# Heng Tian Li's Dashboards
python htl/visualise_r7.py
python htl/visualise_r9.py
python htl/visualise_r11.py

# Chen Xiang Hui's Dashboards
python cxh/13_visualize_exports.py
```

### 📓 Jupyter Notebooks (`.ipynb`)
Open and execute all cells in your preferred notebook environment (VS Code, JupyterLab, or Jupyter Notebook):

- **Tan Jin Yuan's Dashboards**:
  - `tjy/visualise_r1.ipynb` — Customer Value Cube Dashboard
  - `tjy/visualise_r2.ipynb` — Member Churn Risk & Retention Dashboard
  - `tjy/visualise_r3.ipynb` — Restaurant Performance & Rating Correlation Dashboard
- **Chen Xiang Hui's Dashboards**:
  - `cxh/cxh_visualize_exports.ipynb` — Fulfilment, Payment & Voucher Visualizations



