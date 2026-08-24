# 12 Multidimensional Strategic Reports for Data Warehouse

Based on the star schema design of your data warehouse (incorporating `Fact_Order_Sales` and its 7 dimensions: `Dim_Date`, `Dim_Member`, `Dim_Restaurant`, `Dim_Menu_Item`, `Dim_Voucher`, `Dim_Delivery_Company`, and `Dim_Payment`), here are 12 multidimensional reports designed to facilitate deep management strategic analysis.

These are categorized into 6 key business areas to help executives make data-driven decisions.

---

## Category 1: Sales & Revenue Analysis (Financial Performance)

### 1. Revenue Growth & Seasonal Trend Analysis
* **Dimensions:** `Dim_Date` (Year, Quarter, Month, Is_Holiday, Is_Weekend)
* **Measures:** `SUM(Total_Amount)`, `SUM(Quantity)`, Year-Over-Year (YoY) Growth %
* **Strategic Value:** Identifies seasonal peaks, holiday impacts on sales, and the overall revenue trajectory. Management can use this to plan inventory, staffing, and marketing budgets ahead of historical peak periods.

### 2. Profitability by Payment Method & Discount Impact
* **Dimensions:** `Dim_Payment` (Payment_Method), `Dim_Voucher` (Voucher_Type), `Dim_Date` (Month)
* **Measures:** `SUM(Subtotal)`, `SUM(Discount_Amount_Prorated)`, `SUM(Total_Amount)`
* **Strategic Value:** Assesses which payment gateways drive the most volume and how much margin is lost to specific voucher campaigns. Helps in negotiating better transaction rates with payment providers and optimizing discount strategies.

---

## Category 2: Customer Insights & Loyalty (Member Analysis)

### 3. VIP vs. Normal Member Lifetime Value & Ordering Habits
* **Dimensions:** `Dim_Member` (Member_Type, Member_Status), `Dim_Date` (Year, Quarter)
* **Measures:** `AVG(Total_Amount)` (Basket Size), `SUM(Quantity)`, `COUNT(DISTINCT Member_Key)`
* **Strategic Value:** Evaluates if the VIP program successfully drives higher order frequency and larger basket sizes compared to Normal members. If VIPs aren't spending significantly more, the loyalty program benefits may need restructuring.

### 4. Member Churn & Activation Status Analysis
* **Dimensions:** `Dim_Member` (Member_Status, Member_Type), `Dim_Date` (Month)
* **Measures:** `SUM(Total_Amount)`, `COUNT(DISTINCT Order_ID)`
* **Strategic Value:** Tracks the revenue lost from suspended or deactivated users. By analyzing the drop-off in ordering frequency before a status change, management can implement targeted retention campaigns for "at-risk" active members.

---

## Category 3: Restaurant Performance & Location Intelligence

### 5. Restaurant Category & Location Sales Heatmap
* **Dimensions:** `Dim_Restaurant` (Location_Area, Category, Halal_Status)
* **Measures:** `SUM(Total_Amount)`, `AVG(Rating)`, `SUM(Quantity)`
* **Strategic Value:** Identifies which geographical locations and cuisine types (e.g., Fast Food vs. Fine Dining) are most profitable. Useful for targeted expansion plans and advising new restaurant partners on where to set up ghost kitchens.

### 6. Top Performing Restaurants & Rating Correlation
* **Dimensions:** `Dim_Restaurant` (Restaurant_Name, Rating), `Dim_Date` (Month)
* **Measures:** `SUM(Total_Amount)`, `COUNT(Order_ID)`
* **Strategic Value:** Determines if higher-rated restaurants consistently generate more revenue. This insight can dictate algorithm changes on the app's home page—prioritizing high-rated, high-revenue restaurants to maximize overall platform sales.

---

## Category 4: Product & Menu Optimization

### 7. Menu Item Category Performance: Budget vs. Premium
* **Dimensions:** `Dim_Menu_Item` (Item_Category, Budget_Meal, Super_Deal), `Dim_Date` (Month)
* **Measures:** `SUM(Subtotal)`, `SUM(Quantity)`, `AVG(Unit_Price)`
* **Strategic Value:** Discovers whether "Budget Meals" drive massive volume over premium items, and analyzes the actual revenue impact of applying the "Super Deal" tag. Helps restaurants optimize their menu engineering.

### 8. Cross-Selling Effectiveness (Food vs. Drink Attachment Rates)
* **Dimensions:** `Dim_Menu_Item` (Item_Type), `Dim_Restaurant` (Category)
* **Measures:** `SUM(Quantity)`, `SUM(Subtotal)`
* **Strategic Value:** Analyzes cross-selling effectiveness. By comparing the ratio of drinks sold to food sold across different restaurant categories, management can prompt restaurants with low attachment rates to create more combo meals.

---

## Category 5: Marketing & Promotion Effectiveness

### 9. Voucher Campaign ROI & Conversion Analysis
* **Dimensions:** `Dim_Voucher` (Voucher_Type: Percent/Fixed/Free Delivery), `Dim_Date` (Is_Holiday, Month)
* **Measures:** `SUM(Discount_Amount_Prorated)`, `SUM(Total_Amount)`, `COUNT(DISTINCT Order_ID)`
* **Strategic Value:** Determines which voucher types yield the highest net revenue and if they are most effective during holidays or regular weekdays. Prevents the business from running expensive campaigns that only attract bargain hunters with low retention.

### 10. Delivery Fee Subsidy Impact on Order Volume
* **Dimensions:** `Dim_Delivery_Company` (Company_Name), `Dim_Voucher` (Voucher_Type - specifically 'FREE_DELIVERY')
* **Measures:** `SUM(Delivery_Fee_Prorated)`, `SUM(Total_Amount)`, `COUNT(Order_ID)`
* **Strategic Value:** Analyzes if subsidizing delivery fees significantly increases order volume and which delivery partners absorb this volume best. Crucial for deciding whether to offer universal free delivery during peak hours.

---

## Category 6: Operational Efficiency & Fulfillment

### 11. Delivery Partner Performance & Reliance
* **Dimensions:** `Dim_Delivery_Company` (Company_Name), `Dim_Date` (Month, Is_Weekend)
* **Measures:** `SUM(Delivery_Fee_Prorated)`, `COUNT(DISTINCT Order_ID)`, `AVG(Delivery_Fee_Prorated)`
* **Strategic Value:** Monitors which delivery companies handle the most volume and their cost to the platform. Uncovers if the platform is overly reliant on a single delivery partner during high-stress periods like weekends.

### 12. Failed/Refunded Order Analysis by Gateway & Restaurant
* **Dimensions:** `Dim_Payment` (Payment_Status, Payment_Method), `Dim_Restaurant` (Restaurant_Name)
* **Measures:** `SUM(Total_Amount)`, `COUNT(DISTINCT Order_ID)`
* **Strategic Value:** Pinpoints critical operational bottlenecks. If specific payment methods have high 'FAILED' rates, technical intervention is needed. If specific restaurants have high 'REFUNDED' rates, it indicates poor food quality or inventory mismanagement that requires immediate penalization or training.
