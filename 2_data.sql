-- ============================================================================
-- SHOPGRAB EXPANDED DATA GENERATION (10-YEAR, ~4000 ORDERS)
-- New script: preserves original 05_generate_sample_data.sql
-- Date range: 2016-01-01 to 2026-08-01
-- Members: 100 | Orders: ~4000 | Growth-weighted distribution
-- ============================================================================

SET DEFINE OFF;
SET SERVEROUTPUT ON;

PROMPT ======= Clearing existing data... =======;
BEGIN
    DELETE FROM voucher_redemption;
    DELETE FROM payment;
    DELETE FROM delivery;
    DELETE FROM order_item;
    DELETE FROM customer_order;
    DELETE FROM group_order_participant;
    DELETE FROM group_order;
    DELETE FROM menu_item;
    DELETE FROM delivery_company;
    DELETE FROM voucher;
    DELETE FROM address;
    DELETE FROM member;
    DELETE FROM item_category;
    DELETE FROM restaurant;
    DELETE FROM restaurant_category;
    DELETE FROM member_type;
END;
/

-- ============================================================================
-- PART 1: BASE LOOKUPS (member_type, restaurant_category, item_category)
-- ============================================================================
PROMPT ======= Inserting base lookup data... =======;
INSERT INTO member_type (member_type_id, type_name, monthly_fee, benefits_desc)
VALUES (1, 'NORMAL', 0, 'Free registration plan');

INSERT INTO member_type (member_type_id, type_name, monthly_fee, benefits_desc)
VALUES (2, 'VIP', 6, 'RM6 monthly plan');

BEGIN
    INSERT INTO restaurant_category VALUES (1, 'Malay Cuisine', 'Traditional Malay meals and rice sets');
    INSERT INTO restaurant_category VALUES (2, 'Chinese Cuisine', 'Wok dishes, noodles, and dim sum inspired meals');
    INSERT INTO restaurant_category VALUES (3, 'Indian Cuisine', 'Banana leaf sets, curries, and tandoori dishes');
    INSERT INTO restaurant_category VALUES (4, 'Korean Street Food', 'Korean rice bowls, fried chicken, and spicy favourites');
    INSERT INTO restaurant_category VALUES (5, 'Japanese Bento', 'Japanese rice bowls, ramen, and bento meals');
    INSERT INTO restaurant_category VALUES (6, 'Thai Kitchen', 'Thai basil, tom yum, and spicy stir-fry favourites');
    INSERT INTO restaurant_category VALUES (7, 'Western Grill', 'Pasta, burgers, grilled meat, and comfort food');
    INSERT INTO restaurant_category VALUES (8, 'Dessert Cafe', 'Waffles, cakes, pastries, and sweet treats');
    INSERT INTO restaurant_category VALUES (9, 'Beverage House', 'Coffee, tea, coolers, and quick cafe bites');
    INSERT INTO restaurant_category VALUES (10, 'Fast Food Express', 'Burgers, wraps, fried chicken, and combo meals');

    INSERT INTO item_category VALUES (1, 'Signature Rice', 'Rice-based signature meals');
    INSERT INTO item_category VALUES (2, 'Noodles', 'Noodle and pasta style meals');
    INSERT INTO item_category VALUES (3, 'Chicken Specials', 'Chicken-based protein dishes');
    INSERT INTO item_category VALUES (4, 'Seafood Specials', 'Seafood and premium protein dishes');
    INSERT INTO item_category VALUES (5, 'Burgers and Wraps', 'Burger, sandwich, and wrap items');
    INSERT INTO item_category VALUES (6, 'Hot Coffee', 'Espresso, latte, and hot coffee drinks');
    INSERT INTO item_category VALUES (7, 'Brewed Tea', 'Milk tea, tea blends, and tea-based drinks');
    INSERT INTO item_category VALUES (8, 'Refreshing Drinks', 'Juices, soda, smoothies, and iced coolers');
    INSERT INTO item_category VALUES (9, 'Desserts', 'Cakes, waffles, pastries, and ice cream');
    INSERT INTO item_category VALUES (10, 'Snacks and Sides', 'Light bites, snacks, and add-ons');
END;
/

-- ============================================================================
-- PART 2: MEMBERS (100) AND ADDRESSES (200)
-- Registration dates staggered from 2016 to 2025
-- ============================================================================
PROMPT ======= Inserting 100 members and 200 addresses... =======;
DECLARE
    TYPE t_name_list IS TABLE OF VARCHAR2(100) INDEX BY PLS_INTEGER;
    v_names t_name_list;
    v_member_type_id NUMBER;
    v_member_status  VARCHAR2(20);
    v_reg_date       DATE;
    -- Pre-computed address variables (fix PLS-00231)
    v_home_city      VARCHAR2(80);
    v_home_state     VARCHAR2(80);
    v_home_postcode  VARCHAR2(12);
    v_alt_city       VARCHAR2(80);
    v_alt_state      VARCHAR2(80);
    v_alt_postcode   VARCHAR2(12);
    v_alt_line1      VARCHAR2(150);
    v_alt_line2      VARCHAR2(150);
    v_alt_label      VARCHAR2(30);

    FUNCTION f_city(p_idx NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_idx, 16)
            WHEN 0 THEN RETURN 'Cyberjaya';
            WHEN 1 THEN RETURN 'Putrajaya';
            WHEN 2 THEN RETURN 'Shah Alam';
            WHEN 3 THEN RETURN 'Subang Jaya';
            WHEN 4 THEN RETURN 'Petaling Jaya';
            WHEN 5 THEN RETURN 'Bangsar';
            WHEN 6 THEN RETURN 'Cheras';
            WHEN 7 THEN RETURN 'Ampang';
            WHEN 8 THEN RETURN 'Johor Bahru';
            WHEN 9 THEN RETURN 'Skudai';
            WHEN 10 THEN RETURN 'George Town';
            WHEN 11 THEN RETURN 'Bayan Lepas';
            WHEN 12 THEN RETURN 'Ipoh';
            WHEN 13 THEN RETURN 'Melaka Tengah';
            WHEN 14 THEN RETURN 'Seremban';
            ELSE RETURN 'Kuantan';
        END CASE;
    END;

    FUNCTION f_state(p_idx NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_idx, 16)
            WHEN 0 THEN RETURN 'Selangor';
            WHEN 1 THEN RETURN 'W.P. Putrajaya';
            WHEN 2 THEN RETURN 'Selangor';
            WHEN 3 THEN RETURN 'Selangor';
            WHEN 4 THEN RETURN 'Selangor';
            WHEN 5 THEN RETURN 'W.P. Kuala Lumpur';
            WHEN 6 THEN RETURN 'W.P. Kuala Lumpur';
            WHEN 7 THEN RETURN 'Selangor';
            WHEN 8 THEN RETURN 'Johor';
            WHEN 9 THEN RETURN 'Johor';
            WHEN 10 THEN RETURN 'Pulau Pinang';
            WHEN 11 THEN RETURN 'Pulau Pinang';
            WHEN 12 THEN RETURN 'Perak';
            WHEN 13 THEN RETURN 'Melaka';
            WHEN 14 THEN RETURN 'Negeri Sembilan';
            ELSE RETURN 'Pahang';
        END CASE;
    END;

    FUNCTION f_postcode(p_idx NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_idx, 16)
            WHEN 0 THEN RETURN '63000';
            WHEN 1 THEN RETURN '62000';
            WHEN 2 THEN RETURN '40100';
            WHEN 3 THEN RETURN '47500';
            WHEN 4 THEN RETURN '47810';
            WHEN 5 THEN RETURN '59000';
            WHEN 6 THEN RETURN '56000';
            WHEN 7 THEN RETURN '68000';
            WHEN 8 THEN RETURN '80200';
            WHEN 9 THEN RETURN '81300';
            WHEN 10 THEN RETURN '10200';
            WHEN 11 THEN RETURN '11900';
            WHEN 12 THEN RETURN '31400';
            WHEN 13 THEN RETURN '75100';
            WHEN 14 THEN RETURN '70300';
            ELSE RETURN '25000';
        END CASE;
    END;

    FUNCTION f_reg_date(p_i NUMBER) RETURN DATE IS
    BEGIN
        IF p_i <= 15 THEN
            RETURN DATE '2016-01-01' + MOD(p_i * 17, 330);
        ELSIF p_i <= 30 THEN
            RETURN DATE '2017-01-01' + MOD(p_i * 19, 360);
        ELSIF p_i <= 45 THEN
            RETURN DATE '2018-06-01' + MOD(p_i * 13, 500);
        ELSIF p_i <= 60 THEN
            RETURN DATE '2019-09-01' + MOD(p_i * 11, 450);
        ELSIF p_i <= 75 THEN
            RETURN DATE '2021-01-01' + MOD(p_i * 23, 580);
        ELSIF p_i <= 90 THEN
            RETURN DATE '2023-01-01' + MOD(p_i * 17, 480);
        ELSE
            RETURN DATE '2025-01-01' + MOD(p_i * 7, 150);
        END IF;
    END;
BEGIN
    -- 100 Malaysian-realistic names
    v_names(1) := 'Ali Rahman';        v_names(2) := 'Alex Tan';
    v_names(3) := 'Siti Aisyah';       v_names(4) := 'John Lim';
    v_names(5) := 'Nur Amira';         v_names(6) := 'Daniel Lee';
    v_names(7) := 'Farah Iman';        v_names(8) := 'Jason Wong';
    v_names(9) := 'Aina Sofea';        v_names(10) := 'Hafiz Arif';
    v_names(11) := 'Chloe Ng';         v_names(12) := 'Bryan Teo';
    v_names(13) := 'Izzat Hakim';      v_names(14) := 'Maya Devi';
    v_names(15) := 'Ryan Goh';         v_names(16) := 'Puteri Nadia';
    v_names(17) := 'Adam Syah';        v_names(18) := 'Sarah Ong';
    v_names(19) := 'Kevin Chan';       v_names(20) := 'Nabilah Zain';
    v_names(21) := 'Ahmad Firdaus';    v_names(22) := 'Melissa Low';
    v_names(23) := 'Aaron Khoo';       v_names(24) := 'Huda Karim';
    v_names(25) := 'Benjamin Ho';      v_names(26) := 'Zara Nabila';
    v_names(27) := 'Imran Yusuf';      v_names(28) := 'Alicia Tan';
    v_names(29) := 'Hakim Roslan';     v_names(30) := 'Nicole Yap';
    v_names(31) := 'Rizwan Shah';      v_names(32) := 'Emily Chong';
    v_names(33) := 'Amirul Haziq';     v_names(34) := 'Priya Nair';
    v_names(35) := 'Marcus Loh';       v_names(36) := 'Syafiqah Rahim';
    v_names(37) := 'Darren Koh';       v_names(38) := 'Wan Aisyah';
    v_names(39) := 'Ivan Yong';        v_names(40) := 'Liyana Afiqah';
    v_names(41) := 'Samuel Chin';      v_names(42) := 'Nurul Huda';
    v_names(43) := 'Derek Foo';        v_names(44) := 'Ain Batrisyia';
    v_names(45) := 'Patrick Yeoh';     v_names(46) := 'Fatimah Hassan';
    v_names(47) := 'Kelvin Lau';       v_names(48) := 'Rina Suzuki';
    v_names(49) := 'Vincent Phua';     v_names(50) := 'Suhaila Yusof';
    v_names(51) := 'Ethan Sim';        v_names(52) := 'Amani Radzuan';
    v_names(53) := 'Joshua Lai';       v_names(54) := 'Nadira Zulkifli';
    v_names(55) := 'Gabriel Ooi';      v_names(56) := 'Hidayah Wahab';
    v_names(57) := 'Nelson Chew';      v_names(58) := 'Aishah Musa';
    v_names(59) := 'Wesley Tham';      v_names(60) := 'Balqis Anuar';
    v_names(61) := 'Raymond Soo';      v_names(62) := 'Irdina Fauzi';
    v_names(63) := 'Adrian Yeap';      v_names(64) := 'Zahirah Osman';
    v_names(65) := 'Chris Woo';        v_names(66) := 'Safiya Idris';
    v_names(67) := 'Eugene Tay';       v_names(68) := 'Mariam Latif';
    v_names(69) := 'Felix Leong';      v_names(70) := 'Athirah Samad';
    v_names(71) := 'Justin Heng';      v_names(72) := 'Syazwani Isa';
    v_names(73) := 'Gordon Phang';     v_names(74) := 'Nora Azmi';
    v_names(75) := 'Howard Tan';       v_names(76) := 'Diani Harun';
    v_names(77) := 'Ian Quek';         v_names(78) := 'Rashidah Yacob';
    v_names(79) := 'Leon Saw';         v_names(80) := 'Kamalia Bakar';
    v_names(81) := 'Max Teoh';         v_names(82) := 'Tasha Ridzwan';
    v_names(83) := 'Oscar Liew';       v_names(84) := 'Umairah Khalid';
    v_names(85) := 'Peter Soh';        v_names(86) := 'Wardina Razak';
    v_names(87) := 'Shaun Kok';        v_names(88) := 'Yasmin Jalil';
    v_names(89) := 'Timothy Wee';      v_names(90) := 'Amirah Salleh';
    v_names(91) := 'Victor Loke';      v_names(92) := 'Bazilah Nordin';
    v_names(93) := 'Wilson Mah';       v_names(94) := 'Dayana Ishak';
    v_names(95) := 'Xavier Ang';       v_names(96) := 'Elena Zainal';
    v_names(97) := 'Yusuf Hamid';      v_names(98) := 'Fauziah Talib';
    v_names(99) := 'Zack Beh';         v_names(100) := 'Gina Ibrahim';

    FOR i IN 1 .. 100 LOOP
        -- VIP members (about 20%)
        v_member_type_id := CASE
            WHEN i IN (4,5,8,10,15,20,24,25,30,35,40,48,50,55,60,65,70,80,85,95) THEN 2
            ELSE 1
        END;
        v_member_status := CASE
            WHEN i IN (27,29,58,73,89) THEN 'SUSPENDED'
            WHEN i IN (30,60,100) THEN 'DEACTIVATED'
            ELSE 'ACTIVE'
        END;
        v_reg_date := f_reg_date(i);

        -- Pre-compute HOME address fields (PLS-00231 fix)
        v_home_city     := f_city(MOD((i - 1) * 3, 16));
        v_home_state    := f_state(MOD((i - 1) * 3, 16));
        v_home_postcode := f_postcode(MOD((i - 1) * 3, 16));

        -- Pre-compute ALTERNATE address fields
        v_alt_city     := f_city(MOD((i - 1) * 5 + 7, 16));
        v_alt_state    := f_state(MOD((i - 1) * 5 + 7, 16));
        v_alt_postcode := f_postcode(MOD((i - 1) * 5 + 7, 16));
        v_alt_label    := CASE MOD(i, 4) WHEN 0 THEN 'OFFICE' WHEN 1 THEN 'WORK' WHEN 2 THEN 'CAMPUS' ELSE 'FAMILY' END;

        IF MOD(i, 3) = 0 THEN
            v_alt_line1 := 'Suite ' || TO_CHAR(MOD(i, 18) + 2) || '-' || TO_CHAR(MOD(i, 12) + 1) || ', Persiaran Teknologi';
            v_alt_line2 := 'Business Park ' || CASE MOD(i, 4) WHEN 0 THEN 'North' WHEN 1 THEN 'Central' WHEN 2 THEN 'East' ELSE 'South' END;
        ELSE
            v_alt_line1 := 'Unit ' || TO_CHAR(MOD(i, 25) + 1) || ', Residensi ' || v_alt_city;
            v_alt_line2 := 'Residensi ' || CASE MOD(i, 4) WHEN 0 THEN 'Vista' WHEN 1 THEN 'Indah' WHEN 2 THEN 'Sentral' ELSE 'Damai' END;
        END IF;

        INSERT INTO member (
            member_id, member_type_id, full_name, email, phone_no,
            password_hash, registration_date, member_status
        ) VALUES (
            i, v_member_type_id, v_names(i),
            LOWER(REPLACE(v_names(i), ' ', '.')) || '@shopgrab.my',
            CASE MOD(i, 5)
                WHEN 0 THEN '019' WHEN 1 THEN '012' WHEN 2 THEN '013'
                WHEN 3 THEN '014' ELSE '016'
            END || TO_CHAR(520000 + i),
            'hash_member_' || TO_CHAR(i, 'FM000'),
            v_reg_date,
            v_member_status
        );

        -- HOME address (uses pre-computed variables)
        INSERT INTO address (
            address_id, member_id, address_line1, address_line2,
            city, state, postcode, address_label, is_default
        ) VALUES (
            (i - 1) * 2 + 1, i,
            'No. ' || TO_CHAR(10 + i) || ', Jalan ' ||
                CASE MOD(i, 5) WHEN 0 THEN 'Kenanga' WHEN 1 THEN 'Cempaka'
                    WHEN 2 THEN 'Melur' WHEN 3 THEN 'Jasmine' ELSE 'Anggerik' END
                || ' ' || TO_CHAR(MOD(i, 7) + 1) || '/' || TO_CHAR(MOD(i, 9) + 2),
            'Taman ' || CASE MOD(i, 4) WHEN 0 THEN 'Mutiara' WHEN 1 THEN 'Aman'
                WHEN 2 THEN 'Sejahtera' ELSE 'Bestari' END,
            v_home_city, v_home_state, v_home_postcode,
            'HOME', 'Y'
        );

        -- ALTERNATE address (uses pre-computed variables)
        INSERT INTO address (
            address_id, member_id, address_line1, address_line2,
            city, state, postcode, address_label, is_default
        ) VALUES (
            (i - 1) * 2 + 2, i,
            v_alt_line1, v_alt_line2,
            v_alt_city, v_alt_state, v_alt_postcode,
            v_alt_label, 'N'
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted 100 members and 200 addresses.');
END;
/

-- ============================================================================
-- PART 3: RESTAURANTS (20) AND MENU ITEMS (200)
-- Same as original — 20 restaurants x 10 menu items each
-- ============================================================================
PROMPT ======= Inserting restaurants and menu items... =======;
DECLARE
    v_category_id NUMBER;
    v_rest_name VARCHAR2(150);
    v_rest_phone VARCHAR2(30);
    v_rest_halal VARCHAR2(10);
    v_rest_area VARCHAR2(120);
    v_rest_rating NUMBER(3,2);
    v_opening_hour VARCHAR2(20);
    v_closing_hour VARCHAR2(20);
    v_item_category_id NUMBER;
    v_item_name VARCHAR2(150);
    v_item_desc VARCHAR2(300);
    v_item_type VARCHAR2(10);
    v_item_price NUMBER(10,2);
    v_item_availability VARCHAR2(20);
    v_budget_flag CHAR(1);
    v_deal_flag CHAR(1);

    FUNCTION f_rest_name(p_id NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE p_id
            WHEN 1 THEN RETURN 'Warisan Nasi Kukus';
            WHEN 2 THEN RETURN 'Penang Wok House';
            WHEN 3 THEN RETURN 'Banana Leaf Junction';
            WHEN 4 THEN RETURN 'Seoul Sizzle Kitchen';
            WHEN 5 THEN RETURN 'Mori Bento Express';
            WHEN 6 THEN RETURN 'Bangkok Basil Table';
            WHEN 7 THEN RETURN 'Smokehouse Grill Lab';
            WHEN 8 THEN RETURN 'Sweet Crumbs Cafe';
            WHEN 9 THEN RETURN 'Brew & Boba Station';
            WHEN 10 THEN RETURN 'QuickBite Burgers';
            WHEN 11 THEN RETURN 'Kampung Corner Deli';
            WHEN 12 THEN RETURN 'Dim Sum Avenue';
            WHEN 13 THEN RETURN 'Spice Tiffin House';
            WHEN 14 THEN RETURN 'Kimchi Street Kitchen';
            WHEN 15 THEN RETURN 'Tokyo Bento Lane';
            WHEN 16 THEN RETURN 'Siam Wok Express';
            WHEN 17 THEN RETURN 'Urban Charcoal Grill';
            WHEN 18 THEN RETURN 'Gelato & Waffle Room';
            WHEN 19 THEN RETURN 'Teh Tarik & Beans Co';
            ELSE RETURN 'Burger Sprint Drive-In';
        END CASE;
    END;

    FUNCTION f_rest_area(p_id NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE p_id
            WHEN 1 THEN RETURN 'Cyberjaya'; WHEN 2 THEN RETURN 'Subang Jaya';
            WHEN 3 THEN RETURN 'Brickfields'; WHEN 4 THEN RETURN 'Sunway';
            WHEN 5 THEN RETURN 'Putrajaya'; WHEN 6 THEN RETURN 'Damansara';
            WHEN 7 THEN RETURN 'Desa ParkCity'; WHEN 8 THEN RETURN 'KLCC';
            WHEN 9 THEN RETURN 'Cheras'; WHEN 10 THEN RETURN 'Ampang';
            WHEN 11 THEN RETURN 'Shah Alam'; WHEN 12 THEN RETURN 'Puchong';
            WHEN 13 THEN RETURN 'Kajang'; WHEN 14 THEN RETURN 'Bukit Jalil';
            WHEN 15 THEN RETURN 'Johor Bahru'; WHEN 16 THEN RETURN 'George Town';
            WHEN 17 THEN RETURN 'Petaling Jaya'; WHEN 18 THEN RETURN 'Bangsar South';
            WHEN 19 THEN RETURN 'Serdang'; ELSE RETURN 'Seremban';
        END CASE;
    END;

    FUNCTION f_rest_keyword(p_id NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE p_id
            WHEN 1 THEN RETURN 'Warisan'; WHEN 2 THEN RETURN 'Wok';
            WHEN 3 THEN RETURN 'Leaf'; WHEN 4 THEN RETURN 'Seoul';
            WHEN 5 THEN RETURN 'Mori'; WHEN 6 THEN RETURN 'Basil';
            WHEN 7 THEN RETURN 'Smoke'; WHEN 8 THEN RETURN 'Sweet';
            WHEN 9 THEN RETURN 'Boba'; WHEN 10 THEN RETURN 'Quick';
            WHEN 11 THEN RETURN 'Kampung'; WHEN 12 THEN RETURN 'DimSum';
            WHEN 13 THEN RETURN 'Spice'; WHEN 14 THEN RETURN 'Kimchi';
            WHEN 15 THEN RETURN 'Tokyo'; WHEN 16 THEN RETURN 'Siam';
            WHEN 17 THEN RETURN 'Urban'; WHEN 18 THEN RETURN 'Gelato';
            WHEN 19 THEN RETURN 'Tarik'; ELSE RETURN 'Sprint';
        END CASE;
    END;

    FUNCTION f_menu_base_name(p_cat NUMBER, p_slot NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE p_cat
            WHEN 1 THEN CASE p_slot WHEN 1 THEN RETURN 'Nasi Kukus Ayam Berempah'; WHEN 2 THEN RETURN 'Nasi Lemak Rendang Daging'; WHEN 3 THEN RETURN 'Mee Rebus Johor'; WHEN 4 THEN RETURN 'Ayam Penyet Sambal Hijau'; WHEN 5 THEN RETURN 'Set Ikan Bakar Cili'; WHEN 6 THEN RETURN 'Soto Ayam Special'; WHEN 7 THEN RETURN 'Keropok Lekor Cup'; WHEN 8 THEN RETURN 'Teh Ais Limau'; WHEN 9 THEN RETURN 'Sirap Bandung Float'; ELSE RETURN 'Air Jagung Madu'; END CASE;
            WHEN 2 THEN CASE p_slot WHEN 1 THEN RETURN 'Cantonese Kuey Teow'; WHEN 2 THEN RETURN 'Ginger Scallion Chicken Rice'; WHEN 3 THEN RETURN 'Kung Pao Chicken Bowl'; WHEN 4 THEN RETURN 'Salted Egg Fish Fillet'; WHEN 5 THEN RETURN 'Yee Mee Soup'; WHEN 6 THEN RETURN 'Dim Sum Basket'; WHEN 7 THEN RETURN 'Spring Roll Bites'; WHEN 8 THEN RETURN 'Chrysanthemum Tea'; WHEN 9 THEN RETURN 'Soy Bean Milk'; ELSE RETURN 'Plum Lime Cooler'; END CASE;
            WHEN 3 THEN CASE p_slot WHEN 1 THEN RETURN 'Banana Leaf Chicken Curry'; WHEN 2 THEN RETURN 'Mutton Varuval Rice'; WHEN 3 THEN RETURN 'Maggi Goreng Mamak'; WHEN 4 THEN RETURN 'Tandoori Chicken Set'; WHEN 5 THEN RETURN 'Prawn Masala Bowl'; WHEN 6 THEN RETURN 'Roti Canai Double'; WHEN 7 THEN RETURN 'Vadai Snack Plate'; WHEN 8 THEN RETURN 'Teh Tarik Kaw'; WHEN 9 THEN RETURN 'Mango Lassi'; ELSE RETURN 'Masala Lime Soda'; END CASE;
            WHEN 4 THEN CASE p_slot WHEN 1 THEN RETURN 'Bibimbap Bulgogi Bowl'; WHEN 2 THEN RETURN 'Kimchi Fried Rice'; WHEN 3 THEN RETURN 'Ramyeon Cheese Pot'; WHEN 4 THEN RETURN 'Yangnyeom Chicken'; WHEN 5 THEN RETURN 'Dakgalbi Rice Set'; WHEN 6 THEN RETURN 'Tteokbokki Box'; WHEN 7 THEN RETURN 'Seaweed Fries'; WHEN 8 THEN RETURN 'Citron Honey Tea'; WHEN 9 THEN RETURN 'Korean Grape Fizz'; ELSE RETURN 'Iced Peach Ade'; END CASE;
            WHEN 5 THEN CASE p_slot WHEN 1 THEN RETURN 'Chicken Katsu Don'; WHEN 2 THEN RETURN 'Salmon Teriyaki Bento'; WHEN 3 THEN RETURN 'Shoyu Ramen'; WHEN 4 THEN RETURN 'Ebi Tempura Set'; WHEN 5 THEN RETURN 'Mentai Chicken Rice'; WHEN 6 THEN RETURN 'Tamago Sando'; WHEN 7 THEN RETURN 'Takoyaki Tray'; WHEN 8 THEN RETURN 'Matcha Latte'; WHEN 9 THEN RETURN 'Yuzu Soda'; ELSE RETURN 'Hojicha Milk Tea'; END CASE;
            WHEN 6 THEN CASE p_slot WHEN 1 THEN RETURN 'Tom Yum Fried Rice'; WHEN 2 THEN RETURN 'Pad Kra Pao Chicken'; WHEN 3 THEN RETURN 'Pad Thai Prawn'; WHEN 4 THEN RETURN 'Green Curry Seafood'; WHEN 5 THEN RETURN 'Thai Basil Beef'; WHEN 6 THEN RETURN 'Mango Sticky Rice Cup'; WHEN 7 THEN RETURN 'Thai Fish Cake'; WHEN 8 THEN RETURN 'Thai Milk Tea'; WHEN 9 THEN RETURN 'Lemongrass Cooler'; ELSE RETURN 'Coconut Shake'; END CASE;
            WHEN 7 THEN CASE p_slot WHEN 1 THEN RETURN 'Grilled Chicken Chop'; WHEN 2 THEN RETURN 'Creamy Mushroom Pasta'; WHEN 3 THEN RETURN 'Buttermilk Rice Bowl'; WHEN 4 THEN RETURN 'Smoked BBQ Lamb'; WHEN 5 THEN RETURN 'Fish and Chips'; WHEN 6 THEN RETURN 'Loaded Potato Wedges'; WHEN 7 THEN RETURN 'Chicken Caesar Wrap'; WHEN 8 THEN RETURN 'Mocha Latte'; WHEN 9 THEN RETURN 'Sparkling Apple Soda'; ELSE RETURN 'Iced Chocolate'; END CASE;
            WHEN 8 THEN CASE p_slot WHEN 1 THEN RETURN 'Belgian Waffle Stack'; WHEN 2 THEN RETURN 'Burnt Cheesecake Slice'; WHEN 3 THEN RETURN 'Chocolate Lava Cup'; WHEN 4 THEN RETURN 'Tiramisu Dessert Jar'; WHEN 5 THEN RETURN 'Croffle Berry Cream'; WHEN 6 THEN RETURN 'Vanilla Cream Puff'; WHEN 7 THEN RETURN 'Caramel Frappe'; WHEN 8 THEN RETURN 'Strawberry Milk'; WHEN 9 THEN RETURN 'Matcha Frappe'; ELSE RETURN 'Peach Tea Sparkler'; END CASE;
            WHEN 9 THEN CASE p_slot WHEN 1 THEN RETURN 'Butter Kaya Toast'; WHEN 2 THEN RETURN 'Chicken Slice Croissant'; WHEN 3 THEN RETURN 'Mushroom Toastie'; WHEN 4 THEN RETURN 'Americano'; WHEN 5 THEN RETURN 'Caramel Latte'; WHEN 6 THEN RETURN 'Hazelnut Cappuccino'; WHEN 7 THEN RETURN 'Classic Milk Tea'; WHEN 8 THEN RETURN 'Brown Sugar Boba'; WHEN 9 THEN RETURN 'Lemon Mint Soda'; ELSE RETURN 'Passionfruit Cooler'; END CASE;
            ELSE CASE p_slot WHEN 1 THEN RETURN 'Crispy Chicken Burger'; WHEN 2 THEN RETURN 'Double Beef Burger'; WHEN 3 THEN RETURN 'Spicy Chicken Wrap'; WHEN 4 THEN RETURN 'Loaded Cheese Fries'; WHEN 5 THEN RETURN 'Popcorn Chicken Bucket'; WHEN 6 THEN RETURN 'Mayo Shrimp Roll'; WHEN 7 THEN RETURN 'Curly Fries Snack'; WHEN 8 THEN RETURN 'Iced Cola Float'; WHEN 9 THEN RETURN 'Lychee Fizz'; ELSE RETURN 'Lemon Tea Cooler'; END CASE;
        END CASE;
    END;

    FUNCTION f_item_type(p_cat NUMBER, p_slot NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF p_cat = 8 THEN RETURN CASE WHEN p_slot <= 6 THEN 'FOOD' ELSE 'DRINK' END;
        ELSIF p_cat = 9 THEN RETURN CASE WHEN p_slot <= 3 THEN 'FOOD' ELSE 'DRINK' END;
        ELSE RETURN CASE WHEN p_slot <= 7 THEN 'FOOD' ELSE 'DRINK' END;
        END IF;
    END;

    FUNCTION f_item_category(p_cat NUMBER, p_slot NUMBER) RETURN NUMBER IS
    BEGIN
        IF f_item_type(p_cat, p_slot) = 'DRINK' THEN
            CASE p_slot WHEN 8 THEN RETURN 6; WHEN 9 THEN RETURN 7; ELSE RETURN 8; END CASE;
        END IF;
        CASE p_slot
            WHEN 1 THEN RETURN 1;
            WHEN 2 THEN RETURN CASE WHEN p_cat IN (2,6,7) THEN 2 ELSE 1 END;
            WHEN 3 THEN RETURN CASE WHEN p_cat IN (2,5,6,7) THEN 2 ELSE 3 END;
            WHEN 4 THEN RETURN CASE WHEN p_cat IN (7,10) THEN 5 ELSE 4 END;
            WHEN 5 THEN RETURN CASE WHEN p_cat = 8 THEN 9 ELSE 4 END;
            WHEN 6 THEN RETURN CASE WHEN p_cat = 8 THEN 9 ELSE 10 END;
            ELSE RETURN 10;
        END CASE;
    END;

    FUNCTION f_price(p_cat NUMBER, p_slot NUMBER, p_rid NUMBER) RETURN NUMBER IS
        v_base NUMBER(10,2);
    BEGIN
        IF f_item_type(p_cat, p_slot) = 'DRINK' THEN
            v_base := 6 + p_slot;
            IF p_cat IN (8,9) THEN v_base := v_base + 1.5; END IF;
        ELSE
            CASE p_slot WHEN 1 THEN v_base:=13; WHEN 2 THEN v_base:=15; WHEN 3 THEN v_base:=14;
                WHEN 4 THEN v_base:=18; WHEN 5 THEN v_base:=17; WHEN 6 THEN v_base:=9; ELSE v_base:=7; END CASE;
            IF p_cat IN (4,5,7) THEN v_base := v_base + 2;
            ELSIF p_cat IN (8,9) THEN v_base := v_base - 1; END IF;
        END IF;
        RETURN ROUND(v_base + (MOD(p_rid * 7 + p_slot, 4) * 0.8), 2);
    END;
BEGIN
    FOR i IN 1 .. 20 LOOP
        v_category_id := MOD(i - 1, 10) + 1;
        v_rest_name := f_rest_name(i);
        v_rest_phone := '03-77' || TO_CHAR(2000 + i);
        v_rest_halal := CASE i WHEN 2 THEN 'NON_HALAL' WHEN 7 THEN 'NON_HALAL' WHEN 12 THEN 'NON_HALAL' WHEN 15 THEN 'NON_HALAL' ELSE 'HALAL' END;
        v_rest_area := f_rest_area(i);
        v_rest_rating := ROUND(3.6 + MOD(i * 7, 13) / 10, 2);
        v_opening_hour := CASE MOD(i,4) WHEN 0 THEN '08:00' WHEN 1 THEN '09:00' WHEN 2 THEN '10:00' ELSE '11:00' END;
        v_closing_hour := CASE MOD(i,4) WHEN 0 THEN '21:00' WHEN 1 THEN '22:00' WHEN 2 THEN '23:00' ELSE '00:00' END;

        INSERT INTO restaurant (
            restaurant_id, restaurant_category_id, restaurant_name, phone_no,
            halal_status, rating_avg, location_area, opening_hour, closing_hour, restaurant_status
        ) VALUES (
            i, v_category_id, v_rest_name, v_rest_phone,
            v_rest_halal, v_rest_rating, v_rest_area, v_opening_hour, v_closing_hour, 'ACTIVE'
        );

        FOR n IN 1 .. 10 LOOP
            v_item_category_id := f_item_category(v_category_id, n);
            v_item_name := f_rest_keyword(i) || ' ' || f_menu_base_name(v_category_id, n);
            v_item_desc := 'Freshly prepared ' || LOWER(f_menu_base_name(v_category_id, n)) || ' from ' || v_rest_name;
            v_item_type := f_item_type(v_category_id, n);
            v_item_price := f_price(v_category_id, n, i);
            v_item_availability := CASE
                WHEN MOD(i + n, 13) = 0 THEN 'INACTIVE'
                WHEN MOD(i + n, 6) = 0 THEN 'OUT_OF_STOCK'
                ELSE 'AVAILABLE' END;
            v_budget_flag := CASE WHEN v_item_type = 'FOOD' AND n IN (1,6,7) THEN 'Y' ELSE 'N' END;
            v_deal_flag := CASE WHEN n IN (1,2,8) THEN 'Y' ELSE 'N' END;

            INSERT INTO menu_item (
                item_id, restaurant_id, item_category_id, item_name, item_desc,
                item_type, price, availability_status, budget_meal_flag, super_deal_flag
            ) VALUES (
                (i-1)*10+n, i, v_item_category_id, v_item_name, v_item_desc,
                v_item_type, v_item_price, v_item_availability, v_budget_flag, v_deal_flag
            );
        END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted 20 restaurants and 200 menu items.');
END;
/

-- ============================================================================
-- PART 4: VOUCHERS (80) AND DELIVERY COMPANIES (10)
-- 10 seasonal batches x 8 vouchers, spread across 10-year window
-- ============================================================================
PROMPT ======= Inserting vouchers and delivery companies... =======;
BEGIN
    FOR i IN 1 .. 80 LOOP
        INSERT INTO voucher (
            voucher_id, voucher_code, voucher_type, discount_amount,
            min_order_amount, expiry_date, voucher_status
        ) VALUES (
            i,
            -- 10 batches of 8: RAYA, LUNCH, BREW, GROUP, WEEKEND, CNY, MERDEKA, DEEPA, XMAS, YEAR
            CASE
                WHEN i <= 8  THEN 'RAYA' || TO_CHAR(i, 'FM00')
                WHEN i <= 16 THEN 'LUNCH' || TO_CHAR(i - 8, 'FM00')
                WHEN i <= 24 THEN 'BREW' || TO_CHAR(i - 16, 'FM00')
                WHEN i <= 32 THEN 'GROUP' || TO_CHAR(i - 24, 'FM00')
                WHEN i <= 40 THEN 'WEEKEND' || TO_CHAR(i - 32, 'FM00')
                WHEN i <= 48 THEN 'CNY' || TO_CHAR(i - 40, 'FM00')
                WHEN i <= 56 THEN 'MERDEKA' || TO_CHAR(i - 48, 'FM00')
                WHEN i <= 64 THEN 'DEEPA' || TO_CHAR(i - 56, 'FM00')
                WHEN i <= 72 THEN 'XMAS' || TO_CHAR(i - 64, 'FM00')
                ELSE 'YEAR' || TO_CHAR(i - 72, 'FM00')
            END,
            CASE MOD(i, 5)
                WHEN 0 THEN 'FREE_DELIVERY'
                WHEN 1 THEN 'PERCENT'
                WHEN 2 THEN 'FIXED'
                WHEN 3 THEN 'PERCENT'
                ELSE 'FIXED'
            END,
            CASE MOD(i, 5)
                WHEN 0 THEN 0
                WHEN 1 THEN 10
                WHEN 2 THEN 5
                WHEN 3 THEN 15
                ELSE 8
            END,
            CASE
                WHEN i <= 8  THEN 25
                WHEN i <= 16 THEN 18
                WHEN i <= 24 THEN 14
                WHEN i <= 32 THEN 40
                WHEN i <= 40 THEN 20
                WHEN i <= 48 THEN 22
                WHEN i <= 56 THEN 30
                WHEN i <= 64 THEN 16
                WHEN i <= 72 THEN 28
                ELSE 15
            END + MOD(i, 3) * 5,
            -- Expiry dates spread across 2016-2027
            DATE '2016-06-01' + (TRUNC((i - 1) / 8) * 400) + MOD(i * 37, 180),
            CASE
                WHEN MOD(i, 11) = 0 THEN 'INACTIVE'
                ELSE 'ACTIVE'
            END
        );
    END LOOP;

    INSERT INTO delivery_company VALUES (1, 'FlashRider MY', '010-8801001', 4.50, 'ACTIVE');
    INSERT INTO delivery_company VALUES (2, 'Maju Dispatch', '010-8801002', 5.00, 'ACTIVE');
    INSERT INTO delivery_company VALUES (3, 'SwiftDrop KL', '010-8801003', 5.50, 'ACTIVE');
    INSERT INTO delivery_company VALUES (4, 'PandaMove Express', '010-8801004', 5.20, 'ACTIVE');
    INSERT INTO delivery_company VALUES (5, 'TapauRunner', '010-8801005', 4.80, 'ACTIVE');
    INSERT INTO delivery_company VALUES (6, 'GoSend City', '010-8801006', 5.80, 'ACTIVE');
    INSERT INTO delivery_company VALUES (7, 'LajuFood Rider', '010-8801007', 4.90, 'ACTIVE');
    INSERT INTO delivery_company VALUES (8, 'Halo Courier Eats', '010-8801008', 5.60, 'ACTIVE');
    INSERT INTO delivery_company VALUES (9, 'EasyDrop Hub', '010-8801009', 5.10, 'ACTIVE');
    INSERT INTO delivery_company VALUES (10, 'RotiRoad Express', '010-8801010', 4.70, 'ACTIVE');

    DBMS_OUTPUT.PUT_LINE('Inserted 80 vouchers and 10 delivery companies.');
END;
/

-- ============================================================================
-- PART 5: GROUP ORDERS (500) AND PARTICIPANTS (~1500)
-- Growth-weighted dates across 2016-2026
-- ============================================================================
PROMPT ======= Inserting 500 group orders... =======;
DECLARE
    v_leader NUMBER;
    v_restaurant_id NUMBER;
    v_address_id NUMBER;
    v_created_dt DATE;
    v_closing_dt DATE;
    v_order_type VARCHAR2(20);
    v_group_status VARCHAR2(20);
    v_max_member NUMBER;
    v_group_title VARCHAR2(255);

    -- Growth-weighted date: sqrt curve biases orders toward recent years
    FUNCTION f_growth_date(p_idx NUMBER, p_total NUMBER) RETURN DATE IS
        v_ratio NUMBER;
        v_offset NUMBER;
        v_minutes NUMBER;
    BEGIN
        v_ratio := (p_idx - 1) / GREATEST(p_total - 1, 1);
        v_offset := TRUNC(SQRT(v_ratio) * 3850);  -- 3850 days = ~10.5 yrs
        CASE MOD(p_idx, 5)
            WHEN 0 THEN v_minutes := 8 * 60 + 20;
            WHEN 1 THEN v_minutes := 12 * 60 + 15;
            WHEN 2 THEN v_minutes := 15 * 60 + 35;
            WHEN 3 THEN v_minutes := 19 * 60 + 5;
            ELSE v_minutes := 21 * 60 + 10;
        END CASE;
        RETURN TRUNC(DATE '2016-01-01' + v_offset) + v_minutes / (24 * 60);
    END;

    -- Return the max member_id registered before a given date
    FUNCTION f_max_member_at(p_dt DATE) RETURN NUMBER IS
    BEGIN
        IF p_dt < DATE '2017-01-01' THEN RETURN 12;
        ELSIF p_dt < DATE '2018-06-01' THEN RETURN 25;
        ELSIF p_dt < DATE '2020-01-01' THEN RETURN 45;
        ELSIF p_dt < DATE '2021-06-01' THEN RETURN 55;
        ELSIF p_dt < DATE '2023-01-01' THEN RETURN 70;
        ELSIF p_dt < DATE '2025-01-01' THEN RETURN 88;
        ELSE RETURN 97;
        END IF;
    END;

    FUNCTION f_title_prefix(p_idx NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_idx, 10)
            WHEN 0 THEN RETURN 'Office Lunch';
            WHEN 1 THEN RETURN 'Project Supper';
            WHEN 2 THEN RETURN 'Tea Break Run';
            WHEN 3 THEN RETURN 'Family Dinner';
            WHEN 4 THEN RETURN 'Study Session';
            WHEN 5 THEN RETURN 'Weekend Makan';
            WHEN 6 THEN RETURN 'Birthday Treat';
            WHEN 7 THEN RETURN 'Rainy Day Cravings';
            WHEN 8 THEN RETURN 'Late Night Bites';
            ELSE RETURN 'Team Tapau';
        END CASE;
    END;

    FUNCTION f_rest_label(p_id NUMBER) RETURN VARCHAR2 IS
    BEGIN
        CASE p_id
            WHEN 1 THEN RETURN 'Warisan'; WHEN 2 THEN RETURN 'Wok House';
            WHEN 3 THEN RETURN 'Leaf Junction'; WHEN 4 THEN RETURN 'Seoul Sizzle';
            WHEN 5 THEN RETURN 'Mori Bento'; WHEN 6 THEN RETURN 'Bangkok Basil';
            WHEN 7 THEN RETURN 'Smokehouse'; WHEN 8 THEN RETURN 'Sweet Crumbs';
            WHEN 9 THEN RETURN 'Brew Boba'; WHEN 10 THEN RETURN 'QuickBite';
            WHEN 11 THEN RETURN 'Kampung Deli'; WHEN 12 THEN RETURN 'DimSum Ave';
            WHEN 13 THEN RETURN 'Spice Tiffin'; WHEN 14 THEN RETURN 'Kimchi St';
            WHEN 15 THEN RETURN 'Tokyo Lane'; WHEN 16 THEN RETURN 'Siam Wok';
            WHEN 17 THEN RETURN 'Urban Grill'; WHEN 18 THEN RETURN 'Gelato Room';
            WHEN 19 THEN RETURN 'Tarik Beans'; ELSE RETURN 'Burger Sprint';
        END CASE;
    END;
BEGIN
    FOR i IN 1 .. 500 LOOP
        v_created_dt := f_growth_date(i, 500);
        v_max_member := f_max_member_at(v_created_dt);
        v_leader := MOD(i * 3 + 2, v_max_member) + 1;
        v_restaurant_id := MOD(i - 1, 20) + 1;
        v_order_type := CASE WHEN MOD(i, 4) = 0 THEN 'PICKUP' ELSE 'DELIVERY' END;
        v_group_status := CASE
            WHEN MOD(i, 10) IN (0,1,2,3) THEN 'CHECKED_OUT'
            WHEN MOD(i, 10) IN (4,5) THEN 'CLOSED'
            WHEN MOD(i, 10) IN (6,7,8) THEN 'OPEN'
            ELSE 'CANCELLED'
        END;
        v_address_id := CASE
            WHEN v_order_type = 'PICKUP' THEN NULL
            ELSE ((v_leader - 1) * 2 + 1)
        END;
        v_closing_dt := v_created_dt + ((90 + MOD(i, 8) * 20) / 1440);
        -- Pre-compute title (fix PLS-00231: local functions not allowed in SQL VALUES)
        v_group_title := f_title_prefix(i) || ' - ' || f_rest_label(v_restaurant_id);

        INSERT INTO group_order (
            group_order_id, leader_member_id, restaurant_id, address_id,
            group_title, invite_code, created_datetime, closing_datetime,
            order_type, group_status, remarks
        ) VALUES (
            i, v_leader, v_restaurant_id, v_address_id,
            v_group_title,
            'GO' || TO_CHAR(EXTRACT(YEAR FROM v_created_dt)) || TO_CHAR(i, 'FM0000'),
            v_created_dt, v_closing_dt, v_order_type, v_group_status,
            CASE MOD(i, 6)
                WHEN 0 THEN 'Shared meal with colleagues'
                WHEN 1 THEN 'Host collecting orders for the team'
                WHEN 2 THEN 'Dinner order for housemates'
                WHEN 3 THEN 'Weekend group treat'
                WHEN 4 THEN 'Student society snack run'
                ELSE 'Family add-on order'
            END
        );
    END LOOP;

    UPDATE group_order SET address_id = NULL WHERE order_type = 'PICKUP';
    DBMS_OUTPUT.PUT_LINE('Inserted 500 group orders.');
END;
/

PROMPT ======= Inserting group order participants... =======;
DECLARE
    v_pid NUMBER := 0;
    v_candidate NUMBER;
    v_prev1 NUMBER; v_prev2 NUMBER; v_prev3 NUMBER; v_prev4 NUMBER;
    v_count NUMBER;
    v_status VARCHAR2(20);
    v_max_member NUMBER;

    FUNCTION f_max_member_at(p_dt DATE) RETURN NUMBER IS
    BEGIN
        IF p_dt < DATE '2017-01-01' THEN RETURN 12;
        ELSIF p_dt < DATE '2018-06-01' THEN RETURN 25;
        ELSIF p_dt < DATE '2020-01-01' THEN RETURN 45;
        ELSIF p_dt < DATE '2021-06-01' THEN RETURN 55;
        ELSIF p_dt < DATE '2023-01-01' THEN RETURN 70;
        ELSIF p_dt < DATE '2025-01-01' THEN RETURN 88;
        ELSE RETURN 97;
        END IF;
    END;

    FUNCTION f_next_member(p_seed NUMBER, p_max NUMBER, p_leader NUMBER,
        p_p1 NUMBER, p_p2 NUMBER, p_p3 NUMBER, p_p4 NUMBER) RETURN NUMBER IS
        v_m NUMBER;
    BEGIN
        v_m := MOD(p_seed, p_max) + 1;
        LOOP
            EXIT WHEN v_m <> p_leader
                  AND (p_p1 IS NULL OR v_m <> p_p1)
                  AND (p_p2 IS NULL OR v_m <> p_p2)
                  AND (p_p3 IS NULL OR v_m <> p_p3)
                  AND (p_p4 IS NULL OR v_m <> p_p4);
            v_m := MOD(v_m, p_max) + 1;
        END LOOP;
        RETURN v_m;
    END;
BEGIN
    FOR g IN (
        SELECT group_order_id, leader_member_id, created_datetime, group_status
        FROM group_order ORDER BY group_order_id
    ) LOOP
        v_prev1 := NULL; v_prev2 := NULL; v_prev3 := NULL; v_prev4 := NULL;
        v_count := CASE MOD(g.group_order_id, 4)
            WHEN 0 THEN 2 WHEN 1 THEN 3 WHEN 2 THEN 4 ELSE 3 END;
        v_max_member := f_max_member_at(g.created_datetime);

        FOR j IN 1 .. v_count LOOP
            v_candidate := f_next_member(
                g.group_order_id * 9 + j * 5, v_max_member,
                g.leader_member_id, v_prev1, v_prev2, v_prev3, v_prev4
            );

            IF g.group_status = 'CHECKED_OUT' THEN v_status := 'JOINED';
            ELSIF g.group_status = 'CLOSED' THEN
                v_status := CASE WHEN j = v_count AND MOD(g.group_order_id, 5) = 0 THEN 'LEFT' ELSE 'JOINED' END;
            ELSIF g.group_status = 'OPEN' THEN
                v_status := CASE WHEN j = v_count AND MOD(g.group_order_id, 3) = 0 THEN 'LEFT' ELSE 'JOINED' END;
            ELSE
                IF j = 1 THEN v_status := 'JOINED';
                ELSIF MOD(g.group_order_id + j, 2) = 0 THEN v_status := 'LEFT';
                ELSE v_status := 'REMOVED'; END IF;
            END IF;

            v_pid := v_pid + 1;
            INSERT INTO group_order_participant (
                participant_id, group_order_id, member_id,
                join_datetime, participant_status, individual_total
            ) VALUES (
                v_pid, g.group_order_id, v_candidate,
                g.created_datetime + ((j * 12) / 1440), v_status, 0
            );

            CASE j WHEN 1 THEN v_prev1 := v_candidate; WHEN 2 THEN v_prev2 := v_candidate;
                WHEN 3 THEN v_prev3 := v_candidate; ELSE v_prev4 := v_candidate; END CASE;
        END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted ' || v_pid || ' group order participants.');
END;
/

-- ============================================================================
-- PART 6: CUSTOMER ORDERS (~4000)
-- Sources: group leader orders (500) + standalone (2200) + participant (~1200)
-- ============================================================================
PROMPT ======= Inserting customer orders... =======;
DECLARE
    v_order_id NUMBER;
    v_member_id NUMBER;
    v_restaurant_id NUMBER;
    v_order_type VARCHAR2(20);
    v_order_status VARCHAR2(25);
    v_payment_status VARCHAR2(20);
    v_address_id NUMBER;
    v_order_dt DATE;
    v_voucher_id NUMBER;
    v_max_member NUMBER;

    FUNCTION f_max_member_at(p_dt DATE) RETURN NUMBER IS
    BEGIN
        IF p_dt < DATE '2017-01-01' THEN RETURN 12;
        ELSIF p_dt < DATE '2018-06-01' THEN RETURN 25;
        ELSIF p_dt < DATE '2020-01-01' THEN RETURN 45;
        ELSIF p_dt < DATE '2021-06-01' THEN RETURN 55;
        ELSIF p_dt < DATE '2023-01-01' THEN RETURN 70;
        ELSIF p_dt < DATE '2025-01-01' THEN RETURN 88;
        ELSE RETURN 97;
        END IF;
    END;

    -- Growth-weighted date for standalone orders
    FUNCTION f_single_dt(p_idx NUMBER, p_total NUMBER) RETURN DATE IS
        v_ratio NUMBER;
        v_offset NUMBER;
        v_minutes NUMBER;
    BEGIN
        v_ratio := (p_idx - 1) / GREATEST(p_total - 1, 1);
        v_offset := TRUNC(SQRT(v_ratio) * 3850);
        CASE MOD(p_idx, 6)
            WHEN 0 THEN v_minutes := 8*60+15;
            WHEN 1 THEN v_minutes := 11*60+45;
            WHEN 2 THEN v_minutes := 13*60+20;
            WHEN 3 THEN v_minutes := 17*60+30;
            WHEN 4 THEN v_minutes := 19*60+10;
            ELSE v_minutes := 21*60+40;
        END CASE;
        RETURN TRUNC(DATE '2016-01-01' + v_offset + MOD(p_idx * 7, 15) - 7)
               + v_minutes / (24 * 60);
    END;
BEGIN
    -- === A) Group leader orders (order_id = group_order_id, 1..500) ===
    FOR g IN (
        SELECT group_order_id, leader_member_id, restaurant_id, address_id,
               created_datetime, order_type, group_status
        FROM group_order ORDER BY group_order_id
    ) LOOP
        v_voucher_id := CASE
            WHEN g.group_status IN ('CHECKED_OUT','CLOSED') THEN MOD(g.group_order_id * 7, 80) + 1
            WHEN g.group_status = 'OPEN' AND MOD(g.group_order_id, 3) = 0 THEN MOD(g.group_order_id * 5, 80) + 1
            ELSE NULL
        END;

        IF g.group_status = 'CHECKED_OUT' THEN
            v_order_status := 'COMPLETED'; v_payment_status := 'PAID';
        ELSIF g.group_status = 'CLOSED' THEN
            v_order_status := CASE WHEN g.order_type = 'DELIVERY' THEN 'PREPARING' ELSE 'CONFIRMED' END;
            v_payment_status := 'PAID';
        ELSIF g.group_status = 'OPEN' THEN
            v_order_status := CASE WHEN MOD(g.group_order_id, 2) = 0 THEN 'CONFIRMED' ELSE 'PENDING' END;
            v_payment_status := 'UNPAID';
        ELSE
            v_order_status := 'CANCELLED'; v_payment_status := 'FAILED';
        END IF;

        INSERT INTO customer_order (
            order_id, member_id, restaurant_id, voucher_id, address_id,
            group_order_id, order_datetime, order_type, order_status,
            subtotal, delivery_fee, discount_amount, total_amount, payment_status
        ) VALUES (
            g.group_order_id, g.leader_member_id, g.restaurant_id, v_voucher_id,
            CASE WHEN g.order_type = 'DELIVERY' THEN g.address_id ELSE NULL END,
            g.group_order_id, g.created_datetime + (18 / 1440),
            g.order_type, v_order_status, 0, 0, 0, 0, v_payment_status
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted 500 group leader orders (IDs 1-500).');

    -- === B) Standalone individual orders (IDs 501..2700 = 2200 orders) ===
    FOR i IN 501 .. 2700 LOOP
        v_order_dt := f_single_dt(i - 500, 2200);
        -- Ensure order_dt is within valid range
        v_order_dt := GREATEST(v_order_dt, DATE '2016-01-15');
        v_order_dt := LEAST(v_order_dt, DATE '2026-08-01');

        v_max_member := f_max_member_at(v_order_dt);
        v_member_id := MOD((i - 501) * 3 + 5, v_max_member) + 1;
        v_restaurant_id := MOD(i - 501, 20) + 1;
        v_order_type := CASE
            WHEN MOD(v_member_id, 5) IN (1, 4) THEN 'DELIVERY'
            WHEN MOD(i, 4) = 0 THEN 'PICKUP'
            ELSE 'DELIVERY'
        END;
        v_address_id := CASE WHEN v_order_type = 'DELIVERY' THEN ((v_member_id - 1) * 2 + 1) ELSE NULL END;
        v_voucher_id := CASE WHEN MOD(i, 5) <> 0 THEN MOD(i * 11, 80) + 1 ELSE NULL END;

        CASE MOD(i, 20)
            WHEN 0 THEN v_order_status := 'CANCELLED'; v_payment_status := 'FAILED';
            WHEN 1 THEN v_order_status := 'REFUNDED'; v_payment_status := 'REFUNDED';
            WHEN 2 THEN v_order_status := 'CONFIRMED'; v_payment_status := 'PAID';
            WHEN 3 THEN v_order_status := 'PREPARING'; v_payment_status := 'PAID';
            WHEN 4 THEN
                v_order_status := CASE WHEN v_order_type = 'DELIVERY' THEN 'OUT_FOR_DELIVERY' ELSE 'CONFIRMED' END;
                v_payment_status := 'PAID';
            ELSE v_order_status := 'COMPLETED'; v_payment_status := 'PAID';
        END CASE;

        INSERT INTO customer_order (
            order_id, member_id, restaurant_id, voucher_id, address_id,
            group_order_id, order_datetime, order_type, order_status,
            subtotal, delivery_fee, discount_amount, total_amount, payment_status
        ) VALUES (
            i, v_member_id, v_restaurant_id, v_voucher_id, v_address_id,
            NULL, v_order_dt, v_order_type, v_order_status,
            0, 0, 0, 0, v_payment_status
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted 2200 standalone orders (IDs 501-2700).');

    -- === C) Group participant orders (IDs 2701+) ===
    v_order_id := 2700;
    FOR p IN (
        SELECT gp.group_order_id, gp.member_id,
               go.restaurant_id, go.address_id, go.created_datetime,
               go.order_type, go.group_status
        FROM group_order_participant gp
        JOIN group_order go ON go.group_order_id = gp.group_order_id
        WHERE gp.participant_status = 'JOINED'
        ORDER BY gp.group_order_id, gp.member_id
    ) LOOP
        v_order_id := v_order_id + 1;
        v_voucher_id := CASE
            WHEN p.group_status IN ('CHECKED_OUT','CLOSED') AND MOD(v_order_id, 3) <> 0
                THEN MOD(v_order_id * 13, 80) + 1
            WHEN p.group_status = 'OPEN' AND MOD(v_order_id, 7) = 0
                THEN MOD(v_order_id * 9, 80) + 1
            ELSE NULL
        END;

        IF p.group_status = 'CHECKED_OUT' THEN
            v_order_status := 'COMPLETED'; v_payment_status := 'PAID';
        ELSIF p.group_status = 'CLOSED' THEN
            v_order_status := CASE WHEN p.order_type = 'DELIVERY' THEN 'PREPARING' ELSE 'CONFIRMED' END;
            v_payment_status := 'PAID';
        ELSIF p.group_status = 'OPEN' THEN
            v_order_status := CASE WHEN MOD(v_order_id, 2) = 0 THEN 'CONFIRMED' ELSE 'PENDING' END;
            v_payment_status := 'UNPAID';
        ELSE
            v_order_status := 'CANCELLED'; v_payment_status := 'FAILED';
        END IF;

        INSERT INTO customer_order (
            order_id, member_id, restaurant_id, voucher_id, address_id,
            group_order_id, order_datetime, order_type, order_status,
            subtotal, delivery_fee, discount_amount, total_amount, payment_status
        ) VALUES (
            v_order_id, p.member_id, p.restaurant_id, v_voucher_id,
            CASE WHEN p.order_type = 'DELIVERY' THEN p.address_id ELSE NULL END,
            p.group_order_id,
            p.created_datetime + ((MOD(v_order_id, 9) + 22) / 1440),
            p.order_type, v_order_status, 0, 0, 0, 0, v_payment_status
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted participant orders. Total orders: ' || v_order_id);
END;
/

-- ============================================================================
-- PART 7: ORDER ITEMS + SUBTOTAL SYNC
-- ============================================================================
PROMPT ======= Inserting order items... =======;
DECLARE
    v_oi_id NUMBER := 0;
    v_item_count NUMBER;
    v_slot NUMBER;
    v_prev1 NUMBER; v_prev2 NUMBER; v_prev3 NUMBER; v_prev4 NUMBER; v_prev5 NUMBER;
    v_price NUMBER(10,2);
    v_qty NUMBER;
    v_persona NUMBER;
    v_instruction VARCHAR2(100);
BEGIN
    FOR r IN (
        SELECT order_id, member_id, restaurant_id, order_type,
               CASE WHEN group_order_id IS NULL THEN 'N' ELSE 'Y' END AS is_group
        FROM customer_order ORDER BY order_id
    ) LOOP
        v_persona := MOD(r.member_id - 1, 5) + 1;
        v_prev1 := NULL; v_prev2 := NULL; v_prev3 := NULL;
        v_prev4 := NULL; v_prev5 := NULL;

        IF r.order_type = 'PICKUP' THEN
            v_item_count := 1 + MOD(r.order_id + v_persona, 3);
        ELSE
            v_item_count := 2 + MOD(r.order_id + v_persona, 4);
        END IF;
        IF r.is_group = 'Y' AND v_persona IN (3, 5) THEN
            v_item_count := LEAST(v_item_count + 1, 5);
        END IF;

        FOR j IN 1 .. v_item_count LOOP
            IF v_persona = 2 AND (j = 1 OR MOD(r.order_id + j, 2) = 0) THEN
                v_slot := 8 + MOD(r.order_id + j + r.member_id, 3);
            ELSIF v_persona = 4 AND j = 1 THEN
                v_slot := 4 + MOD(r.order_id + r.member_id, 4);
            ELSIF v_persona = 5 AND j = v_item_count THEN
                v_slot := 8 + MOD(r.order_id + j, 3);
            ELSE
                v_slot := MOD(r.order_id + r.member_id * 3 + j * 2, 10) + 1;
            END IF;

            -- Avoid duplicate item slots within same order
            LOOP
                EXIT WHEN (v_prev1 IS NULL OR v_slot <> v_prev1)
                      AND (v_prev2 IS NULL OR v_slot <> v_prev2)
                      AND (v_prev3 IS NULL OR v_slot <> v_prev3)
                      AND (v_prev4 IS NULL OR v_slot <> v_prev4)
                      AND (v_prev5 IS NULL OR v_slot <> v_prev5);
                v_slot := MOD(v_slot, 10) + 1;
            END LOOP;

            SELECT price INTO v_price FROM menu_item
            WHERE item_id = (r.restaurant_id - 1) * 10 + v_slot;

            IF v_persona = 3 THEN v_qty := 2 + MOD(r.order_id + j, 3);
            ELSIF v_slot >= 8 THEN v_qty := 1 + MOD(r.member_id + j, 2);
            ELSIF v_persona = 5 AND j = 1 THEN v_qty := 2 + MOD(r.order_id, 2);
            ELSE v_qty := 1 + MOD(r.order_id + r.member_id + j, 3);
            END IF;

            CASE MOD(r.order_id + r.member_id + j, 8)
                WHEN 0 THEN v_instruction := 'Less spicy, please';
                WHEN 1 THEN v_instruction := 'No onion';
                WHEN 2 THEN v_instruction := 'Extra sauce';
                WHEN 3 THEN v_instruction := 'Separate gravy';
                WHEN 4 THEN v_instruction := 'Add cutlery';
                WHEN 5 THEN v_instruction := 'Less ice for drink';
                WHEN 6 THEN v_instruction := 'No peanuts';
                ELSE v_instruction := 'Normal preparation';
            END CASE;

            v_oi_id := v_oi_id + 1;
            INSERT INTO order_item (
                order_item_id, order_id, item_id, quantity,
                unit_price, subtotal, special_instruction
            ) VALUES (
                v_oi_id, r.order_id,
                (r.restaurant_id - 1) * 10 + v_slot,
                v_qty, v_price, ROUND(v_qty * v_price, 2), v_instruction
            );

            CASE j WHEN 1 THEN v_prev1:=v_slot; WHEN 2 THEN v_prev2:=v_slot;
                WHEN 3 THEN v_prev3:=v_slot; WHEN 4 THEN v_prev4:=v_slot;
                ELSE v_prev5:=v_slot; END CASE;
        END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted ' || v_oi_id || ' order items.');
END;
/

PROMPT ======= Synchronizing order subtotals... =======;
BEGIN
    UPDATE customer_order co
       SET subtotal = (
               SELECT ROUND(SUM(oi.subtotal), 2)
               FROM order_item oi WHERE oi.order_id = co.order_id
           ),
           total_amount = (
               SELECT ROUND(SUM(oi.subtotal), 2)
               FROM order_item oi WHERE oi.order_id = co.order_id
           )
     WHERE EXISTS (
               SELECT 1 FROM order_item oi WHERE oi.order_id = co.order_id
           );
END;
/

-- ============================================================================
-- PART 8: DELIVERIES + DELIVERY FEE UPDATE
-- ============================================================================
PROMPT ======= Inserting deliveries and updating delivery fees... =======;
DECLARE
    v_did NUMBER := 0;
    v_company_id NUMBER;
    v_base_fee NUMBER(10,2);
    v_fee NUMBER(10,2);
    v_status VARCHAR2(20);
BEGIN
    FOR r IN (
        SELECT o.order_id, o.member_id, o.order_status, o.order_datetime,
               o.subtotal, o.address_id, a.state, a.city
        FROM customer_order o
        JOIN address a ON a.address_id = o.address_id
        WHERE o.order_type = 'DELIVERY'
        ORDER BY o.order_id
    ) LOOP
        v_did := v_did + 1;
        v_company_id := MOD(r.order_id * 5 + r.member_id + LENGTH(r.city), 10) + 1;

        SELECT base_fee INTO v_base_fee
        FROM delivery_company WHERE delivery_company_id = v_company_id;

        v_fee := v_base_fee
                 + CASE WHEN r.subtotal >= 90 THEN 2.50
                        WHEN r.subtotal >= 55 THEN 1.50
                        ELSE 0.50 END
                 + CASE WHEN r.state IN ('Johor','Pulau Pinang','Perak','Melaka','Negeri Sembilan','Pahang') THEN 0.80
                        ELSE 0.20 END;

        IF MOD(r.order_id + v_company_id, 11) = 0 THEN v_fee := 0;
        ELSIF MOD(r.order_id + r.member_id, 7) = 0 THEN v_fee := v_fee + 1.20;
        END IF;

        IF r.order_status = 'COMPLETED' THEN v_status := 'DELIVERED';
        ELSIF r.order_status = 'OUT_FOR_DELIVERY' THEN v_status := 'PICKED_UP';
        ELSIF r.order_status = 'PREPARING' THEN v_status := 'ASSIGNED';
        ELSIF r.order_status = 'CONFIRMED' THEN v_status := 'PENDING';
        ELSIF r.order_status = 'REFUNDED' THEN v_status := 'FAILED';
        ELSE v_status := 'CANCELLED';
        END IF;

        UPDATE customer_order
           SET delivery_fee = ROUND(v_fee, 2),
               total_amount = ROUND(subtotal + ROUND(v_fee, 2) - discount_amount, 2)
         WHERE order_id = r.order_id;

        INSERT INTO delivery (
            delivery_id, order_id, delivery_company_id, address_id,
            assigned_rider, delivery_status, tracking_note, delivery_fee, delivered_datetime
        ) VALUES (
            v_did, r.order_id, v_company_id, r.address_id,
            CASE WHEN v_status IN ('PENDING','FAILED','CANCELLED') THEN NULL
                 ELSE 'Rider ' || TO_CHAR(MOD(r.order_id * 3 + v_company_id, 60) + 1) END,
            v_status,
            CASE v_status
                WHEN 'DELIVERED' THEN 'Delivered to customer successfully'
                WHEN 'PICKED_UP' THEN 'Rider picked up the order from restaurant'
                WHEN 'ASSIGNED' THEN 'Rider assigned and heading to restaurant'
                WHEN 'FAILED' THEN 'Delivery failed and customer support notified'
                WHEN 'CANCELLED' THEN 'Delivery cancelled before completion'
                ELSE 'Waiting for rider assignment'
            END,
            ROUND(v_fee, 2),
            CASE WHEN v_status = 'DELIVERED'
                THEN r.order_datetime + ((MOD(r.order_id, 7) + 35) / 1440)
                ELSE NULL END
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted ' || v_did || ' deliveries.');
END;
/

-- ============================================================================
-- PART 9: VOUCHER DISCOUNTS + RECALCULATE TOTALS
-- ============================================================================
PROMPT ======= Applying voucher discounts... =======;
DECLARE
    v_type voucher.voucher_type%TYPE;
    v_disc_val voucher.discount_amount%TYPE;
    v_min_order voucher.min_order_amount%TYPE;
    v_vstatus voucher.voucher_status%TYPE;
    v_discount NUMBER(10,2);
BEGIN
    FOR r IN (
        SELECT order_id, voucher_id, subtotal, delivery_fee, order_status, payment_status
        FROM customer_order WHERE voucher_id IS NOT NULL ORDER BY order_id
    ) LOOP
        v_discount := 0;
        SELECT voucher_type, discount_amount, min_order_amount, voucher_status
          INTO v_type, v_disc_val, v_min_order, v_vstatus
          FROM voucher WHERE voucher_id = r.voucher_id;

        IF v_vstatus = 'ACTIVE' AND r.subtotal >= v_min_order
           AND r.order_status NOT IN ('CANCELLED','REFUNDED')
           AND r.payment_status <> 'FAILED' THEN
            IF v_type = 'PERCENT' THEN
                v_discount := ROUND(r.subtotal * (v_disc_val / 100), 2);
            ELSIF v_type = 'FIXED' THEN
                v_discount := LEAST(v_disc_val, r.subtotal + r.delivery_fee);
            ELSE
                v_discount := r.delivery_fee;
            END IF;
        END IF;

        UPDATE customer_order
           SET discount_amount = ROUND(v_discount, 2),
               total_amount = ROUND(subtotal + delivery_fee - ROUND(v_discount, 2), 2)
         WHERE order_id = r.order_id;
    END LOOP;
END;
/

-- ============================================================================
-- PART 10: SYNC PARTICIPANT TOTALS
-- ============================================================================
PROMPT ======= Syncing participant totals... =======;
BEGIN
    UPDATE group_order_participant gp
       SET individual_total = (
               SELECT ROUND(MAX(co.total_amount), 2)
               FROM customer_order co
               WHERE co.group_order_id = gp.group_order_id
                 AND co.member_id = gp.member_id
           )
     WHERE EXISTS (
               SELECT 1 FROM customer_order co
               WHERE co.group_order_id = gp.group_order_id
                 AND co.member_id = gp.member_id
           );
END;
/

-- ============================================================================
-- PART 11: PAYMENTS (1:1 with customer_order)
-- ============================================================================
PROMPT ======= Inserting payments... =======;
DECLARE
    v_method VARCHAR2(20);
    v_status VARCHAR2(20);
    v_persona NUMBER;
BEGIN
    FOR r IN (
        SELECT order_id, member_id, order_type, order_datetime,
               total_amount, payment_status
        FROM customer_order ORDER BY order_id
    ) LOOP
        v_persona := MOD(r.member_id - 1, 5) + 1;

        IF v_persona = 1 THEN
            v_method := CASE WHEN r.order_type = 'PICKUP' THEN 'FPX' ELSE 'EWALLET' END;
        ELSIF v_persona = 2 THEN v_method := 'EWALLET';
        ELSIF v_persona = 3 THEN v_method := 'CARD';
        ELSIF v_persona = 4 THEN
            v_method := CASE WHEN r.order_type = 'PICKUP' THEN 'CASH' ELSE 'FPX' END;
        ELSE
            v_method := CASE WHEN MOD(r.order_id, 2) = 0 THEN 'CARD' ELSE 'EWALLET' END;
        END IF;

        CASE r.payment_status
            WHEN 'PAID' THEN v_status := 'SUCCESS';
            WHEN 'FAILED' THEN v_status := 'FAILED';
            WHEN 'REFUNDED' THEN v_status := 'REFUNDED';
            ELSE v_status := 'PENDING';
        END CASE;

        INSERT INTO payment (
            payment_id, order_id, payment_method, payment_datetime,
            payment_amount, payment_status, transaction_ref
        ) VALUES (
            r.order_id, r.order_id, v_method,
            r.order_datetime + ((MOD(r.order_id, 8) + 4) / 1440),
            r.total_amount, v_status,
            CASE WHEN v_method = 'CASH' THEN NULL
                 ELSE 'TXN' || TO_CHAR(r.order_id, 'FM000000') END
        );
    END LOOP;
END;
/

-- ============================================================================
-- PART 12: VOUCHER REDEMPTIONS
-- ============================================================================
PROMPT ======= Inserting voucher redemptions... =======;
DECLARE
    v_rid NUMBER := 0;
BEGIN
    FOR r IN (
        SELECT order_id, member_id, voucher_id, order_datetime, discount_amount
        FROM customer_order
        WHERE voucher_id IS NOT NULL AND discount_amount > 0 AND payment_status = 'PAID'
        ORDER BY order_id
    ) LOOP
        v_rid := v_rid + 1;
        INSERT INTO voucher_redemption (
            redemption_id, voucher_id, member_id, order_id,
            redeemed_datetime, discount_applied
        ) VALUES (
            v_rid, r.voucher_id, r.member_id, r.order_id,
            r.order_datetime + (5 / 1440), r.discount_amount
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Inserted ' || v_rid || ' voucher redemptions.');
END;
/

COMMIT;

-- ============================================================================
-- SUMMARY
-- ============================================================================
PROMPT;
PROMPT ======= DATA GENERATION COMPLETE =======;
PROMPT Summary counts:;

SELECT RPAD(table_name, 30) || ' | ' || LPAD(TO_CHAR(row_count), 8) AS summary
FROM (
    SELECT 'MEMBER_TYPE' AS table_name, COUNT(*) AS row_count FROM member_type
    UNION ALL SELECT 'MEMBER', COUNT(*) FROM member
    UNION ALL SELECT 'ADDRESS', COUNT(*) FROM address
    UNION ALL SELECT 'RESTAURANT_CATEGORY', COUNT(*) FROM restaurant_category
    UNION ALL SELECT 'RESTAURANT', COUNT(*) FROM restaurant
    UNION ALL SELECT 'ITEM_CATEGORY', COUNT(*) FROM item_category
    UNION ALL SELECT 'MENU_ITEM', COUNT(*) FROM menu_item
    UNION ALL SELECT 'VOUCHER', COUNT(*) FROM voucher
    UNION ALL SELECT 'DELIVERY_COMPANY', COUNT(*) FROM delivery_company
    UNION ALL SELECT 'GROUP_ORDER', COUNT(*) FROM group_order
    UNION ALL SELECT 'GROUP_ORDER_PARTICIPANT', COUNT(*) FROM group_order_participant
    UNION ALL SELECT 'CUSTOMER_ORDER', COUNT(*) FROM customer_order
    UNION ALL SELECT 'ORDER_ITEM', COUNT(*) FROM order_item
    UNION ALL SELECT 'DELIVERY', COUNT(*) FROM delivery
    UNION ALL SELECT 'PAYMENT', COUNT(*) FROM payment
    UNION ALL SELECT 'VOUCHER_REDEMPTION', COUNT(*) FROM voucher_redemption
    ORDER BY 1
);

PROMPT;
PROMPT Order distribution by year:;

SELECT EXTRACT(YEAR FROM order_datetime) AS yr, COUNT(*) AS cnt
FROM customer_order
GROUP BY EXTRACT(YEAR FROM order_datetime)
ORDER BY 1;
