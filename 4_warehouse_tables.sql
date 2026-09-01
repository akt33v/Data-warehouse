ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';
DROP TABLE Fact_Order_Sales CASCADE CONSTRAINTS;
DROP TABLE Dim_Payment CASCADE CONSTRAINTS;
DROP TABLE Dim_Delivery_Company CASCADE CONSTRAINTS;
DROP TABLE Dim_Voucher CASCADE CONSTRAINTS;
DROP TABLE Dim_Menu_Item CASCADE CONSTRAINTS;
DROP TABLE dim_restaurant CASCADE CONSTRAINTS;
DROP TABLE dim_member CASCADE CONSTRAINTS;
DROP TABLE Dim_Date CASCADE CONSTRAINTS;

DROP SEQUENCE dim_pay_seq;
DROP SEQUENCE dim_del_seq;
DROP SEQUENCE dim_voucher_seq;
DROP SEQUENCE dim_menu_seq;
DROP SEQUENCE dim_rest_seq;
DROP SEQUENCE dim_member_seq;
DROP SEQUENCE dim_date_seq;



-- =============================================================================
-- DIM_DATE
-- =============================================================================

CREATE SEQUENCE dim_date_seq
START with 1 --assume date key starts from this NUMBER
INCREMENT BY 1;

CREATE TABLE Dim_Date (
    Date_Key            NUMBER(8)       NOT NULL,
    Full_Date           DATE            NOT NULL,
    Day_Number          NUMBER(2),
    Day_Name            VARCHAR2(15),
    Month_Number        NUMBER(2),
    Month_Name          VARCHAR2(15),
    Quarter_Number      NUMBER(1),
    Year_Number         NUMBER(4),
    Week_Number         NUMBER(2),
    Is_Weekend          CHAR(1)         DEFAULT 'N',
    Is_Holiday          CHAR(1)         DEFAULT 'N',
    Holiday_Name        VARCHAR2(50),
    Week_Start_Date     DATE,     -- date period boundaries
    Week_End_Date       DATE,
    Month_Start_Date    DATE,
    Month_End_Date      DATE,
    Quarter_Start_Date  DATE,
    Quarter_End_Date    DATE,
    Is_End_Of_Month     CHAR(1)         DEFAULT 'N',  -- period indicator flags
    Is_End_Of_Quarter   CHAR(1)         DEFAULT 'N',
    Is_End_Of_Year      CHAR(1)         DEFAULT 'N',
    CONSTRAINT PK_Dim_Date          PRIMARY KEY (Date_Key),
    CONSTRAINT CK_Date_Weekend      CHECK (Is_Weekend IN ('Y', 'N')),
    CONSTRAINT CK_Date_Holiday      CHECK (Is_Holiday IN ('Y', 'N')),
    CONSTRAINT CK_Date_EndMonth     CHECK (Is_End_Of_Month IN ('Y', 'N')),
    CONSTRAINT CK_Date_EndQtr       CHECK (Is_End_Of_Quarter IN ('Y', 'N')),
    CONSTRAINT CK_Date_EndYear      CHECK (Is_End_Of_Year IN ('Y', 'N')),
    CONSTRAINT CK_Date_DayNum       CHECK (Day_Number BETWEEN 1 AND 31),
    CONSTRAINT CK_Date_MonthNum     CHECK (Month_Number BETWEEN 1 AND 12),
    CONSTRAINT CK_Date_QuarterNum   CHECK (Quarter_Number BETWEEN 1 AND 4),
    CONSTRAINT CK_Date_WeekNum      CHECK (Week_Number BETWEEN 1 AND 53),
    CONSTRAINT CK_Date_YearNum      CHECK (Year_Number BETWEEN 2000 AND 2100),
    CONSTRAINT CK_Date_WeekRange    CHECK (Week_End_Date >= Week_Start_Date),     -- Period boundary integrity: end date must not precede start date
    CONSTRAINT CK_Date_MonthRange   CHECK (Month_End_Date >= Month_Start_Date),
    CONSTRAINT CK_Date_QuarterRange CHECK (Quarter_End_Date >= Quarter_Start_Date),
    CONSTRAINT CK_Date_InWeek       CHECK (Full_Date BETWEEN Week_Start_Date AND Week_End_Date), -- Full_Date must fall within its own week/month/quarter boundaries
    CONSTRAINT CK_Date_InMonth      CHECK (Full_Date BETWEEN Month_Start_Date AND Month_End_Date),
    CONSTRAINT CK_Date_InQuarter    CHECK (Full_Date BETWEEN Quarter_Start_Date AND Quarter_End_Date)
);

--=============================================================================
-- DIM_MEMBER
--=============================================================================

CREATE SEQUENCE dim_member_seq
START with 10000 --assume product key starts from this NUMBER
INCREMENT BY 1;

CREATE TABLE dim_member (
    Member_Key          NUMBER PRIMARY KEY,
    Member_ID           NUMBER(10)      NOT NULL,
    Full_Name           VARCHAR2(100) NOT NULL,
    Email               VARCHAR2(120) NOT NULL,
    Member_Type         VARCHAR2(20) NOT NULL,
    Member_Status       VARCHAR2(20) NOT NULL,
    Effective_Date      DATE NOT NULL, -- scd type 2 tracking columns allow check whether customer upgrades membership
    Expiry_Date         DATE DEFAULT '9999-12-31' NOT NULL,
    Current_Flag        VARCHAR2(1)         DEFAULT 'Y',
    CONSTRAINT CK_Cust_Flag         CHECK (Current_Flag IN ('Y', 'N')),
    CONSTRAINT CK_Cust_Type         CHECK (Member_Type IN ('NORMAL', 'VIP')),
    CONSTRAINT CK_Cust_Status       CHECK (Member_Status IN ('ACTIVE', 'SUSPENDED', 'DEACTIVATED')),
    CONSTRAINT CK_Cust_Email        CHECK (Email LIKE '%@%.%'),
    CONSTRAINT CK_Cust_Dates        CHECK (Expiry_Date IS NULL OR Expiry_Date > Effective_Date)
);

--=============================================================================
-- DIM_RESTAURANT
--=============================================================================

CREATE SEQUENCE dim_rest_seq
START with 1000 --assume product key starts from this NUMBER
INCREMENT BY 1;

CREATE TABLE dim_restaurant (
    Restaurant_Key      NUMBER PRIMARY KEY,
    Restaurant_ID       NUMBER(10)      NOT NULL,
    Restaurant_Name     VARCHAR2(150)   NOT NULL,
    Category            VARCHAR2(80)    NOT NULL,
    Halal_Status        VARCHAR2(10)    NOT NULL,
    Rating               NUMBER(3,2)     NOT NULL,
    Location_Area       VARCHAR2(120),
    Effective_Date      DATE            NOT NULL,
    Expiry_Date         DATE            DEFAULT DATE '9999-12-31' NOT NULL,
    Current_Flag        CHAR(1)         DEFAULT 'Y' NOT NULL,
    CONSTRAINT CK_Dim_Rest_Halal        CHECK (Halal_Status IN ('HALAL', 'NON_HALAL')),
    CONSTRAINT CK_Dim_Rest_Rating       CHECK (Rating BETWEEN 0 AND 5),
    CONSTRAINT CK_Dim_Rest_Flag         CHECK (Current_Flag IN ('Y','N'))
);

-- =============================================================================
-- DIM_MENU_ITEM
-- =============================================================================

CREATE SEQUENCE dim_menu_seq
START with 10000 --assume product key starts from this NUMBER
INCREMENT BY 1;


CREATE TABLE Dim_Menu_Item (
    Item_Key            NUMBER PRIMARY KEY,
    Item_ID             NUMBER(10) NOT NULL,
    Item_Name           VARCHAR2(150) NOT NULL,
    Item_Category       VARCHAR2(80) NOT NULL,
    Item_Type           VARCHAR2(10) NOT NULL,
    Budget_Meal         CHAR(1)     DEFAULT 'N' NOT NULL,
    Super_Deal          CHAR(1)     DEFAULT 'N' NOT NULL,
    Effective_Date      DATE        NOT NULL,     -- SCD Type 2 tracking columns,
    Expiry_Date         DATE        DEFAULT '9999-12-31' NOT NULL,                     -- allow check menu item price changes, eg: if the price of a menu item has been increased
    Current_Flag        CHAR(1)     DEFAULT 'Y' NOT NULL,
    CONSTRAINT CK_Item_Type         CHECK (Item_Type IN ('FOOD', 'DRINK')),
    CONSTRAINT CK_Item_Budget       CHECK (Budget_Meal IN ('Y', 'N')),
    CONSTRAINT CK_Item_Deal         CHECK (Super_Deal IN ('Y', 'N')),
    CONSTRAINT CK_Item_CurFlag      CHECK (Current_Flag IN ('Y', 'N')),
    CONSTRAINT CK_Item_Dates        CHECK (Expiry_Date IS NULL OR Expiry_Date > Effective_Date)
);
-- =============================================================================
-- DIM_VOUCHER
-- =============================================================================
create sequence dim_voucher_seq
start with 10000
increment by 1;

CREATE TABLE Dim_Voucher (
    Voucher_Key         NUMBER PRIMARY KEY,
    Voucher_ID          NUMBER(10) NOT NULL,
    Voucher_Code        VARCHAR2(40) NOT NULL,
    Voucher_Type        VARCHAR2(20) NOT NULL,
    Discount_Amount     NUMBER(10,2),
    Minimum_Order       NUMBER(10,2) DEFAULT 0,
    CONSTRAINT CK_VoucherType      CHECK (Voucher_Type IN ('PERCENT', 'FIXED', 'FREE_DELIVERY')),
    CONSTRAINT CK_Voucher_MinOrder  CHECK (Minimum_Order >= 0)
);

-- =============================================================================
-- DIM_DELIVERY_COMPANY
-- =============================================================================
create sequence dim_del_seq
start with 10000
increment by 1;

CREATE TABLE Dim_Delivery_Company (
    Delivery_Company_Key    NUMBER primary key,
    Delivery_Company_ID     NUMBER(10) NOT NULL,
    Company_Name            VARCHAR2(100) NOT NULL,
    Base_Fee                NUMBER(10,2) NOT NULL,
    service_status        VARCHAR2(20)    DEFAULT 'ACTIVE' NOT NULL,
    CONSTRAINT CK_DelComp_Fee           CHECK (Base_Fee >= 0)
);

-- =============================================================================
-- DIM_PAYMENT
-- =============================================================================
create sequence dim_pay_seq
start with 10000
increment by 1;

CREATE TABLE Dim_Payment (
    Payment_Key         NUMBER primary key,
    Payment_ID          NUMBER(10),           -- Source: payment.payment_id (for audit traceability)
    Payment_Method      VARCHAR2(20),
    Payment_Status      VARCHAR2(20),
    CONSTRAINT CK_Pay_Method        CHECK (Payment_Method IN ('CARD', 'FPX', 'EWALLET', 'CASH')),
    CONSTRAINT CK_Pay_Status        CHECK (Payment_Status IN ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED'))
);
-- =============================================================================
-- FACT_ORDER_SALES
-- =============================================================================
CREATE TABLE Fact_Order_Sales (
    -- Traceability back to OLTP source
    Order_ID         NUMBER(10)      NOT NULL,  -- Source: customer_order.order_id
    Date_Key                NUMBER(8)       NOT NULL,
    Member_Key            NUMBER          NOT NULL,
    Restaurant_Key          NUMBER          NOT NULL,
    Item_Key                NUMBER          NOT NULL,
    Voucher_Key             NUMBER not null,
    Delivery_Company_Key    NUMBER not null,
    Payment_Key             NUMBER not null,
    -- Per line-item measures
    Quantity                NUMBER(8)       NOT NULL,
    Unit_Price              NUMBER(10,2)    NOT NULL,
    Subtotal                NUMBER(10,2)    NOT NULL,
    -- Order-level amounts prorated across line items (proportional to each item's subtotal).
    -- ETL must divide the order total by sum of all item subtotals to avoid double-counting.
    -- for example:
    -- Order Total: RM 100
    -- Item A: RM 60 (60%)
    -- Item B: RM 40 (40%)
    -- Discount: RM 10
    -- Delivery Fee: RM 5
    -- Discount Prorated: 60% * RM 10 = RM 6
    -- Delivery Fee Prorated: 40% * RM 5 = RM 2
    Discount_Amount_Prorated  NUMBER(10,2)  DEFAULT 0,
    Delivery_Fee_Prorated     NUMBER(10,2)  DEFAULT 0,
    Total_Amount              NUMBER(10,2)  NOT NULL,
    CONSTRAINT PK_Fact_Order_Sales  PRIMARY KEY (Order_ID, Item_Key),
    CONSTRAINT FK_Fact_Date
        FOREIGN KEY (Date_Key)
        REFERENCES Dim_Date (Date_Key),
    CONSTRAINT FK_Fact_Member
        FOREIGN KEY (Member_Key)
        REFERENCES Dim_Member (Member_Key),
    CONSTRAINT FK_Fact_Restaurant
        FOREIGN KEY (Restaurant_Key)
        REFERENCES Dim_Restaurant (Restaurant_Key),
    CONSTRAINT FK_Fact_Item
        FOREIGN KEY (Item_Key)
        REFERENCES Dim_Menu_Item (Item_Key),
    CONSTRAINT FK_Fact_Voucher
        FOREIGN KEY (Voucher_Key)
        REFERENCES Dim_Voucher (Voucher_Key),
    CONSTRAINT FK_Fact_Delivery
        FOREIGN KEY (Delivery_Company_Key)
        REFERENCES Dim_Delivery_Company (Delivery_Company_Key),
    CONSTRAINT FK_Fact_Payment
        FOREIGN KEY (Payment_Key)
        REFERENCES Dim_Payment (Payment_Key),
    -- Measure integrity checks
    CONSTRAINT CK_Fact_Qty          CHECK (Quantity > 0),
    CONSTRAINT CK_Fact_Price        CHECK (Unit_Price >= 0),
    CONSTRAINT CK_Fact_Sub          CHECK (Subtotal >= 0),
    CONSTRAINT CK_Fact_DiscProrated CHECK (Discount_Amount_Prorated >= 0),
    CONSTRAINT CK_Fact_FeeProrated  CHECK (Delivery_Fee_Prorated >= 0),
    CONSTRAINT CK_Fact_Total        CHECK (Total_Amount >= 0)
);
