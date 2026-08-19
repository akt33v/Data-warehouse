-- SHOPGRAB ASSIGNMENT DDL
-- STEP 1: CREATE TABLES (PK, FK, NOT NULL, DEFAULT, CHECK, UNIQUE)
-- NOTE: Foreign keys are defined inline in this script (no separate FK script required).

SET DEFINE OFF;

CREATE TABLE member_type (
    member_type_id    NUMBER(6)      NOT NULL,
    type_name         VARCHAR2(20)   NOT NULL,
    monthly_fee       NUMBER(6,2)    DEFAULT 0 NOT NULL,
    benefits_desc     VARCHAR2(200),
    CONSTRAINT pk_member_type PRIMARY KEY (member_type_id),
    CONSTRAINT uq_member_type_name UNIQUE (type_name),
    CONSTRAINT ck_member_type_name CHECK (type_name IN ('NORMAL', 'VIP')),
    CONSTRAINT ck_member_type_fee CHECK (
        (type_name = 'NORMAL' AND monthly_fee = 0) OR
        (type_name = 'VIP' AND monthly_fee = 6)
    )
);

CREATE TABLE member (
    member_id          NUMBER(10)      NOT NULL,
    member_type_id     NUMBER(6)       NOT NULL,
    full_name          VARCHAR2(100)   NOT NULL,
    email              VARCHAR2(120)   NOT NULL,
    phone_no           VARCHAR2(30)    NOT NULL,
    password_hash      VARCHAR2(255)   NOT NULL,
    registration_date  DATE            DEFAULT SYSDATE NOT NULL,
    member_status      VARCHAR2(20)    DEFAULT 'ACTIVE' NOT NULL,
    CONSTRAINT pk_member PRIMARY KEY (member_id),
    CONSTRAINT uq_member_email UNIQUE (email),
    CONSTRAINT fk_member_type FOREIGN KEY (member_type_id)
        REFERENCES member_type (member_type_id),
    CONSTRAINT ck_member_status CHECK (
        member_status IN ('ACTIVE', 'SUSPENDED', 'DEACTIVATED')
    )
);

CREATE TABLE address (
    address_id        NUMBER(10)      NOT NULL,
    member_id         NUMBER(10)      NOT NULL,
    address_line1     VARCHAR2(150)   NOT NULL,
    address_line2     VARCHAR2(150),
    city              VARCHAR2(80)    NOT NULL,
    state             VARCHAR2(80)    NOT NULL,
    postcode          VARCHAR2(12)    NOT NULL,
    address_label     VARCHAR2(30)    DEFAULT 'HOME' NOT NULL,
    is_default        CHAR(1)         DEFAULT 'N' NOT NULL,
    CONSTRAINT pk_address PRIMARY KEY (address_id),
    CONSTRAINT fk_address_member FOREIGN KEY (member_id)
        REFERENCES member (member_id),
    CONSTRAINT ck_address_def CHECK (is_default IN ('Y', 'N'))
);

CREATE TABLE restaurant_category (
    restaurant_category_id  NUMBER(6)      NOT NULL,
    category_name           VARCHAR2(80)   NOT NULL,
    category_desc           VARCHAR2(200),
    CONSTRAINT pk_rest_cat PRIMARY KEY (restaurant_category_id),
    CONSTRAINT uq_rest_cat_name UNIQUE (category_name)
);

CREATE TABLE restaurant (
    restaurant_id           NUMBER(10)      NOT NULL,
    restaurant_category_id  NUMBER(6)       NOT NULL,
    restaurant_name         VARCHAR2(150)   NOT NULL,
    phone_no                VARCHAR2(30),
    halal_status            VARCHAR2(10)    DEFAULT 'HALAL' NOT NULL,
    rating_avg              NUMBER(3,2)     DEFAULT 0 NOT NULL,
    location_area           VARCHAR2(120)   NOT NULL,
    opening_hour            VARCHAR2(20),
    closing_hour            VARCHAR2(20),
    restaurant_status       VARCHAR2(20)    DEFAULT 'ACTIVE' NOT NULL,
    CONSTRAINT pk_restaurant PRIMARY KEY (restaurant_id),
    CONSTRAINT uq_rest_name_area_phone UNIQUE (restaurant_name, location_area, phone_no),
    CONSTRAINT fk_restaurant_cat FOREIGN KEY (restaurant_category_id)
        REFERENCES restaurant_category (restaurant_category_id),
    CONSTRAINT ck_rest_halal CHECK (halal_status IN ('HALAL', 'NON_HALAL')),
    CONSTRAINT ck_rest_rating CHECK (rating_avg BETWEEN 0 AND 5),
    CONSTRAINT ck_rest_status CHECK (restaurant_status IN ('ACTIVE', 'INACTIVE'))
);

CREATE TABLE item_category (
    item_category_id    NUMBER(6)      NOT NULL,
    category_name       VARCHAR2(80)   NOT NULL,
    category_desc       VARCHAR2(200),
    CONSTRAINT pk_item_cat PRIMARY KEY (item_category_id),
    CONSTRAINT uq_item_cat_name UNIQUE (category_name)
);

CREATE TABLE menu_item (
    item_id               NUMBER(10)      NOT NULL,
    restaurant_id         NUMBER(10)      NOT NULL,
    item_category_id      NUMBER(6)       NOT NULL,
    item_name             VARCHAR2(150)   NOT NULL,
    item_desc             VARCHAR2(300),
    item_type             VARCHAR2(10)    NOT NULL,
    price                 NUMBER(10,2)    NOT NULL,
    availability_status   VARCHAR2(20)    DEFAULT 'AVAILABLE' NOT NULL,
    budget_meal_flag      CHAR(1)         DEFAULT 'N' NOT NULL,
    super_deal_flag       CHAR(1)         DEFAULT 'N' NOT NULL,
    CONSTRAINT pk_menu_item PRIMARY KEY (item_id),
    CONSTRAINT uq_menu_name_rest UNIQUE (restaurant_id, item_name),
    CONSTRAINT fk_menu_rest FOREIGN KEY (restaurant_id)
        REFERENCES restaurant (restaurant_id),
    CONSTRAINT fk_menu_cat FOREIGN KEY (item_category_id)
        REFERENCES item_category (item_category_id),
    CONSTRAINT ck_menu_type CHECK (item_type IN ('FOOD', 'DRINK')),
    CONSTRAINT ck_menu_price CHECK (price >= 0),
    CONSTRAINT ck_menu_avail CHECK (
        availability_status IN ('AVAILABLE', 'OUT_OF_STOCK', 'INACTIVE')
    ),
    CONSTRAINT ck_menu_budget CHECK (budget_meal_flag IN ('Y', 'N')),
    CONSTRAINT ck_menu_deal CHECK (super_deal_flag IN ('Y', 'N'))
);

CREATE TABLE voucher (
    voucher_id          NUMBER(10)      NOT NULL,
    voucher_code        VARCHAR2(40)    NOT NULL,
    voucher_type        VARCHAR2(20)    NOT NULL,
    discount_amount     NUMBER(10,2)    DEFAULT 0 NOT NULL,
    min_order_amount    NUMBER(10,2)    DEFAULT 0 NOT NULL,
    expiry_date         DATE            NOT NULL,
    voucher_status      VARCHAR2(20)    DEFAULT 'ACTIVE' NOT NULL,
    CONSTRAINT pk_voucher PRIMARY KEY (voucher_id),
    CONSTRAINT uq_voucher_code UNIQUE (voucher_code),
    CONSTRAINT ck_voucher_type CHECK (
        voucher_type IN ('PERCENT', 'FIXED', 'FREE_DELIVERY')
    ),
    CONSTRAINT ck_voucher_disc CHECK (
        discount_amount >= 0
        AND (voucher_type <> 'PERCENT' OR discount_amount <= 100)
    ),
    CONSTRAINT ck_voucher_min CHECK (min_order_amount >= 0),
    CONSTRAINT ck_voucher_status CHECK (voucher_status IN ('ACTIVE', 'INACTIVE'))
);

CREATE TABLE group_order (
    group_order_id      NUMBER(10)      NOT NULL,
    leader_member_id    NUMBER(10)      NOT NULL,
    restaurant_id       NUMBER(10)      NOT NULL,
    address_id          NUMBER(10),
    group_title         VARCHAR2(120),
    invite_code         VARCHAR2(30)    NOT NULL,
    created_datetime    DATE            DEFAULT SYSDATE NOT NULL,
    closing_datetime    DATE,
    order_type          VARCHAR2(20)    DEFAULT 'DELIVERY' NOT NULL,
    group_status        VARCHAR2(20)    DEFAULT 'OPEN' NOT NULL,
    remarks             VARCHAR2(300),
    CONSTRAINT pk_group_order PRIMARY KEY (group_order_id),
    CONSTRAINT uq_group_invite UNIQUE (invite_code),
    CONSTRAINT fk_group_leader FOREIGN KEY (leader_member_id)
        REFERENCES member (member_id),
    CONSTRAINT fk_group_rest FOREIGN KEY (restaurant_id)
        REFERENCES restaurant (restaurant_id),
    CONSTRAINT fk_group_addr FOREIGN KEY (address_id)
        REFERENCES address (address_id),
    CONSTRAINT ck_group_type CHECK (order_type IN ('DELIVERY', 'PICKUP')),
    CONSTRAINT ck_group_status CHECK (
        group_status IN ('OPEN', 'CLOSED', 'CHECKED_OUT', 'CANCELLED')
    )
);

CREATE TABLE group_order_participant (
    participant_id       NUMBER(10)      NOT NULL,
    group_order_id       NUMBER(10)      NOT NULL,
    member_id            NUMBER(10)      NOT NULL,
    join_datetime        DATE            DEFAULT SYSDATE NOT NULL,
    participant_status   VARCHAR2(20)    DEFAULT 'JOINED' NOT NULL,
    individual_total     NUMBER(10,2)    DEFAULT 0 NOT NULL,
    CONSTRAINT pk_group_part PRIMARY KEY (participant_id),
    CONSTRAINT uq_group_part UNIQUE (group_order_id, member_id),
    CONSTRAINT fk_gp_group FOREIGN KEY (group_order_id)
        REFERENCES group_order (group_order_id),
    CONSTRAINT fk_gp_member FOREIGN KEY (member_id)
        REFERENCES member (member_id),
    CONSTRAINT ck_gp_status CHECK (
        participant_status IN ('JOINED', 'LEFT', 'REMOVED')
    ),
    CONSTRAINT ck_gp_total CHECK (individual_total >= 0)
);

CREATE TABLE customer_order (
    order_id            NUMBER(10)      NOT NULL,
    member_id           NUMBER(10)      NOT NULL,
    restaurant_id       NUMBER(10)      NOT NULL,
    voucher_id          NUMBER(10),
    address_id          NUMBER(10),
    group_order_id      NUMBER(10),
    order_datetime      DATE            DEFAULT SYSDATE NOT NULL,
    order_type          VARCHAR2(20)    DEFAULT 'DELIVERY' NOT NULL,
    order_status        VARCHAR2(25)    DEFAULT 'PENDING' NOT NULL,
    subtotal            NUMBER(10,2)    DEFAULT 0 NOT NULL,
    delivery_fee        NUMBER(10,2)    DEFAULT 0 NOT NULL,
    discount_amount     NUMBER(10,2)    DEFAULT 0 NOT NULL,
    total_amount        NUMBER(10,2)    DEFAULT 0 NOT NULL,
    payment_status      VARCHAR2(20)    DEFAULT 'UNPAID' NOT NULL,
    CONSTRAINT pk_cust_order PRIMARY KEY (order_id),
    CONSTRAINT fk_order_member FOREIGN KEY (member_id)
        REFERENCES member (member_id),
    CONSTRAINT fk_order_rest FOREIGN KEY (restaurant_id)
        REFERENCES restaurant (restaurant_id),
    CONSTRAINT fk_order_voucher FOREIGN KEY (voucher_id)
        REFERENCES voucher (voucher_id),
    CONSTRAINT fk_order_addr FOREIGN KEY (address_id)
        REFERENCES address (address_id),
    CONSTRAINT fk_order_group FOREIGN KEY (group_order_id)
        REFERENCES group_order (group_order_id),
    CONSTRAINT ck_order_type CHECK (order_type IN ('DELIVERY', 'PICKUP')),
    CONSTRAINT ck_order_status CHECK (
        order_status IN (
            'PENDING', 'CONFIRMED', 'PREPARING', 'OUT_FOR_DELIVERY',
            'COMPLETED', 'CANCELLED', 'REFUNDED'
        )
    ),
    CONSTRAINT ck_order_money CHECK (
        subtotal >= 0 AND delivery_fee >= 0 AND discount_amount >= 0 AND total_amount >= 0
    ),
    CONSTRAINT ck_order_total CHECK (
        total_amount = (subtotal + delivery_fee - discount_amount)
    ),
    CONSTRAINT ck_order_pay_status CHECK (
        payment_status IN ('UNPAID', 'PAID', 'FAILED', 'REFUNDED')
    ),
    CONSTRAINT ck_order_addr_rule CHECK (
        (order_type = 'DELIVERY' AND address_id IS NOT NULL)
        OR (order_type = 'PICKUP')
    )
);

CREATE TABLE order_item (
    order_item_id         NUMBER(10)      NOT NULL,
    order_id              NUMBER(10)      NOT NULL,
    item_id               NUMBER(10)      NOT NULL,
    quantity              NUMBER(8)       DEFAULT 1 NOT NULL,
    unit_price            NUMBER(10,2)    NOT NULL,
    subtotal              NUMBER(10,2)    NOT NULL,
    special_instruction   VARCHAR2(300),
    CONSTRAINT pk_order_item PRIMARY KEY (order_item_id),
    CONSTRAINT uq_oi_order_item UNIQUE (order_id, item_id),
    CONSTRAINT fk_oi_order FOREIGN KEY (order_id)
        REFERENCES customer_order (order_id),
    CONSTRAINT fk_oi_item FOREIGN KEY (item_id)
        REFERENCES menu_item (item_id),
    CONSTRAINT ck_oi_qty CHECK (quantity > 0),
    CONSTRAINT ck_oi_price CHECK (unit_price >= 0),
    CONSTRAINT ck_oi_sub CHECK (subtotal = quantity * unit_price)
);

CREATE TABLE delivery_company (
    delivery_company_id   NUMBER(10)      NOT NULL,
    company_name          VARCHAR2(100)   NOT NULL,
    contact_no            VARCHAR2(30),
    base_fee              NUMBER(10,2)    DEFAULT 0 NOT NULL,
    service_status        VARCHAR2(20)    DEFAULT 'ACTIVE' NOT NULL,
    CONSTRAINT pk_del_comp PRIMARY KEY (delivery_company_id),
    CONSTRAINT uq_del_comp_name UNIQUE (company_name),
    CONSTRAINT ck_del_comp_fee CHECK (base_fee >= 0),
    CONSTRAINT ck_del_comp_status CHECK (service_status IN ('ACTIVE', 'INACTIVE'))
);

CREATE TABLE delivery (
    delivery_id           NUMBER(10)      NOT NULL,
    order_id              NUMBER(10)      NOT NULL,
    delivery_company_id   NUMBER(10)      NOT NULL,
    address_id            NUMBER(10)      NOT NULL,
    assigned_rider        VARCHAR2(100),
    delivery_status       VARCHAR2(20)    DEFAULT 'PENDING' NOT NULL,
    tracking_note         VARCHAR2(300),
    delivery_fee          NUMBER(10,2)    DEFAULT 0 NOT NULL,
    delivered_datetime    DATE,
    CONSTRAINT pk_delivery PRIMARY KEY (delivery_id),
    CONSTRAINT uq_delivery_order UNIQUE (order_id),
    CONSTRAINT fk_delivery_order FOREIGN KEY (order_id)
        REFERENCES customer_order (order_id),
    CONSTRAINT fk_delivery_comp FOREIGN KEY (delivery_company_id)
        REFERENCES delivery_company (delivery_company_id),
    CONSTRAINT fk_delivery_addr FOREIGN KEY (address_id)
        REFERENCES address (address_id),
    CONSTRAINT ck_delivery_status CHECK (
        delivery_status IN ('PENDING', 'ASSIGNED', 'PICKED_UP', 'DELIVERED', 'FAILED', 'CANCELLED')
    ),
    CONSTRAINT ck_delivery_fee CHECK (delivery_fee >= 0)
);

CREATE TABLE payment (
    payment_id          NUMBER(10)      NOT NULL,
    order_id            NUMBER(10)      NOT NULL,
    payment_method      VARCHAR2(20)    NOT NULL,
    payment_datetime    DATE            DEFAULT SYSDATE NOT NULL,
    payment_amount      NUMBER(10,2)    NOT NULL,
    payment_status      VARCHAR2(20)    DEFAULT 'PENDING' NOT NULL,
    transaction_ref     VARCHAR2(100),
    CONSTRAINT pk_payment PRIMARY KEY (payment_id),
    CONSTRAINT uq_payment_ref UNIQUE (transaction_ref),
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id)
        REFERENCES customer_order (order_id),
    CONSTRAINT ck_payment_method CHECK (
        payment_method IN ('CARD', 'FPX', 'EWALLET', 'CASH')
    ),
    CONSTRAINT ck_payment_status CHECK (
        payment_status IN ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED')
    ),
    CONSTRAINT ck_payment_amt CHECK (payment_amount >= 0)
);

CREATE TABLE voucher_redemption (
    redemption_id       NUMBER(10)      NOT NULL,
    voucher_id          NUMBER(10)      NOT NULL,
    member_id           NUMBER(10)      NOT NULL,
    order_id            NUMBER(10)      NOT NULL,
    redeemed_datetime   DATE            DEFAULT SYSDATE NOT NULL,
    discount_applied    NUMBER(10,2)    NOT NULL,
    CONSTRAINT pk_vr PRIMARY KEY (redemption_id),
    CONSTRAINT uq_vr_order UNIQUE (order_id),
    CONSTRAINT fk_vr_voucher FOREIGN KEY (voucher_id)
        REFERENCES voucher (voucher_id),
    CONSTRAINT fk_vr_member FOREIGN KEY (member_id)
        REFERENCES member (member_id),
    CONSTRAINT fk_vr_order FOREIGN KEY (order_id)
        REFERENCES customer_order (order_id),
    CONSTRAINT ck_vr_discount CHECK (discount_applied >= 0)
);
