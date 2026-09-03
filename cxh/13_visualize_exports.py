from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "visualizations"


def load_csv(filename: str) -> pd.DataFrame:
    """Load an exported CSV and raise a useful error when it is missing."""

    path = BASE_DIR / filename

    if not path.exists():
        raise FileNotFoundError(
            f"Missing {path.name}. "
            "Run 12_export_visualizations.sql with F5 first."
        )

    return pd.read_csv(path)


# ==========================================================
# DELIVERY VISUALIZATIONS
# ==========================================================

def save_delivery_chart(data: pd.DataFrame) -> plt.Figure:


    # Orders by delivery company across years
    yearly_orders = data.pivot(
        index="YEAR",
        columns="DELIVERY_COMPANY",
        values="TOTAL_ORDERS",
    ).fillna(0)

    # Overall orders by delivery company
    order_totals = (
        data.drop_duplicates("DELIVERY_COMPANY")
        .set_index("DELIVERY_COMPANY")["OVERALL_TOTAL_ORDERS"]
        .sort_values(ascending=True)
    )

        # Average delivery fee by year
    # ==========================================================
    # Average delivery fee by year
    # ==========================================================

    average_fees = (
        data.groupby("YEAR", as_index=False)
        .agg(
            AVERAGE_DELIVERY_FEE_RM=(
                "TOTAL_DELIVERY_FEES_RM",
                "sum",
            ),
            TOTAL_ORDERS=(
                "TOTAL_ORDERS",
                "sum",
            ),
        )
    )

    average_fees["AVERAGE_DELIVERY_FEE_RM"] = (
        average_fees["AVERAGE_DELIVERY_FEE_RM"]
        / average_fees["TOTAL_ORDERS"]
    )

    average_fees["AVERAGE_DELIVERY_FEE_RM"] = (
        average_fees["AVERAGE_DELIVERY_FEE_RM"].round(2)
    )

    average_fees = average_fees.sort_values("YEAR")

    # ==========================================================
    # CREATE FIGURE
    # ==========================================================

    figure, axes = plt.subplots(
        1,
        3,
        figsize=(24, 8),
    )

    # ==========================================================
    # CONSISTENT DELIVERY COMPANY COLORS
    # ==========================================================

    colors = plt.rcParams["axes.prop_cycle"].by_key()["color"]

    company_colors = {
        company: colors[index % len(colors)]
        for index, company in enumerate(yearly_orders.columns)
    }

    # ==========================================================
    # CHART 1 — GROUPED BAR
    # Orders by Delivery Company Across Years
    # ==========================================================

    yearly_orders.plot(
        kind="bar",
        stacked=False,
        ax=axes[0],
        width=0.8,
        color=[
            company_colors[company]
            for company in yearly_orders.columns
        ],
    )

    axes[0].set_title(
        "Orders by Delivery Company Across Years",
        fontsize=13,
    )

    axes[0].set_xlabel(
        "Year",
        fontsize=12,
    )

    axes[0].set_ylabel(
        "Total Orders",
        fontsize=12,
    )

    axes[0].tick_params(
        axis="x",
        rotation=45,
    )

    axes[0].legend(
        title="Delivery Company",
        bbox_to_anchor=(0.5, -0.25),
        loc="upper center",
        ncol=2,
        fontsize=8,
    )

    # ==========================================================
    # CHART 2 — HORIZONTAL BAR
    # Overall Orders by Delivery Company
    # ==========================================================

    bar_colors = [
        company_colors[company]
        for company in order_totals.index
    ]

    axes[1].barh(
        order_totals.index,
        order_totals.values,
        color=bar_colors,
    )

    # Add values at the end of each bar
    for index, value in enumerate(order_totals.values):

        axes[1].text(
            value + 1,
            index,
            str(int(value)),
            va="center",
            fontsize=9,
        )

    axes[1].set_title(
        "Overall Orders by Delivery Company",
        fontsize=13,
    )

    axes[1].set_xlabel(
        "Total Orders",
        fontsize=12,
    )

    axes[1].set_ylabel(
        "Delivery Company",
        fontsize=12,
    )

    legend_handles = [
        plt.Rectangle(
            (0, 0),
            1,
            1,
            color=company_colors[company],
        )
        for company in yearly_orders.columns
    ]

    axes[1].legend(
        legend_handles,
        yearly_orders.columns,
        title="Delivery Company",
        bbox_to_anchor=(0.5, -0.25),
        loc="upper center",
        ncol=2,
        fontsize=8,
    )

    # ==========================================================
    # CHART 3 — LINE
    # Average Delivery Fee by Year
    # ==========================================================

    axes[2].plot(
        average_fees["YEAR"],
        average_fees["AVERAGE_DELIVERY_FEE_RM"],
        marker="o",
    )

    # Add fee values above each point
    for year, fee in zip(
        average_fees["YEAR"],
        average_fees["AVERAGE_DELIVERY_FEE_RM"],
    ):

        axes[2].annotate(
            f"{fee:.2f}",
            (year, fee),
            textcoords="offset points",
            xytext=(0, 12),
            ha="center",
            va="bottom",
            fontsize=8,
            bbox=dict(
                boxstyle="round,pad=0.2",
                facecolor="white",
                edgecolor="none",
                alpha=0.8,
            ),
        )

    axes[2].set_title(
        "Average Delivery Fee by Year",
        fontsize=13,
    )

    axes[2].set_xlabel(
        "Year",
        fontsize=12,
    )

    axes[2].set_ylabel(
        "Average Fee (RM)",
        fontsize=11,
    )

    max_fee = average_fees["AVERAGE_DELIVERY_FEE_RM"].max()

    axes[2].set_ylim(
        0,
        max_fee * 1.20,
    )

    axes[2].tick_params(
        axis="x",
        rotation=45,
    )

    # ==========================================================
    # OVERALL TITLE
    # ==========================================================

    figure.suptitle(
        "Order Fulfilment & Delivery Performance",
        fontsize=18,
    )

    figure.tight_layout(
        rect=[0, 0.08, 1, 0.94]
    )

    # ==========================================================
    # SAVE
    # ==========================================================

    figure.savefig(
        OUTPUT_DIR / "order_fulfilment_delivery_performance.png",
        dpi=150,
        bbox_inches="tight",
    )

    return figure


# ==========================================================
# PAYMENT VISUALIZATIONS
# ==========================================================

def save_payment_chart(data: pd.DataFrame) -> plt.Figure:

    # ==========================================================
    # PREPARE DATA
    # ==========================================================

    order_totals = (
        data.set_index("PAYMENT_METHOD")["TOTAL_ORDERS"]
    )

    sales_totals = (
        data.set_index("PAYMENT_METHOD")["TOTAL_SALES_RM"]
    )

    success_rate = (
        data.set_index("PAYMENT_METHOD")["SUCCESS_RATE"]
    )

    # ==========================================================
    # CONSISTENT PAYMENT METHOD COLORS
    # ==========================================================

    payment_methods = data["PAYMENT_METHOD"].unique()

    colors = plt.rcParams["axes.prop_cycle"].by_key()["color"]

    payment_colors = {
        method: colors[index % len(colors)]
        for index, method in enumerate(payment_methods)
    }

    # ==========================================================
    # CREATE FIGURE
    # ==========================================================

    figure, axes = plt.subplots(
        1,
        3,
        figsize=(18, 6),
    )

    # ==========================================================
    # CHART 1 — ORDERS
    # Highest → Lowest
    # ==========================================================

    order_data = order_totals.sort_values(
        ascending=False
    )

    order_colors = [
        payment_colors[method]
        for method in order_data.index
    ]

    axes[0].bar(
        order_data.index,
        order_data.values,
        color=order_colors,
    )

    axes[0].set_title(
        "Orders by Payment Method",
        fontsize=13,
    )

    axes[0].set_xlabel(
        "Payment Method",
        fontsize=11,
    )

    axes[0].set_ylabel(
        "Number of Orders",
        fontsize=11,
    )

    axes[0].tick_params(
        axis="x",
        rotation=45,
    )

    for index, value in enumerate(order_data.values):
        axes[0].text(
            index,
            value + max(order_data.values) * 0.01,
            str(int(value)),
            ha="center",
            va="bottom",
            fontsize=9,
        )

    # ==========================================================
    # CHART 2 — SALES
    # Highest → Lowest
    # ==========================================================

    sales_data = sales_totals.sort_values(
        ascending=False
    )

    sales_colors = [
        payment_colors[method]
        for method in sales_data.index
    ]

    axes[1].bar(
        sales_data.index,
        sales_data.values,
        color=sales_colors,
    )

    axes[1].set_title(
        "Sales by Payment Method",
        fontsize=13,
    )

    axes[1].set_xlabel(
        "Payment Method",
        fontsize=11,
    )

    axes[1].set_ylabel(
        "Sales (RM)",
        fontsize=11,
    )

    axes[1].tick_params(
        axis="x",
        rotation=45,
    )

    for index, value in enumerate(sales_data.values):
        axes[1].text(
            index,
            value + max(sales_data.values) * 0.01,
            f"{value:,.0f}",
            ha="center",
            va="bottom",
            fontsize=9,
        )

    # ==========================================================
    # CHART 3 — SUCCESS RATE
    # Highest → Lowest
    # ==========================================================

    success_data = success_rate.sort_values(
        ascending=False
    )

    success_colors = [
        payment_colors[method]
        for method in success_data.index
    ]

    axes[2].bar(
        success_data.index,
        success_data.values,
        color=success_colors,
    )

    axes[2].set_title(
        "Successful Order Payment Rate",
        fontsize=13,
    )

    axes[2].set_xlabel(
        "Payment Method",
        fontsize=11,
    )

    axes[2].set_ylabel(
        "Success Rate (%)",
        fontsize=11,
    )

    axes[2].set_ylim(
        0,
        100,
    )

    axes[2].tick_params(
        axis="x",
        rotation=45,
    )

    # Add percentage above bars
    for index, value in enumerate(success_data.values):
        axes[2].text(
            index,
            value + 1,
            f"{value:.1f}",
            ha="center",
            va="bottom",
            fontsize=9,
        )

    # ==========================================================
    # OVERALL TITLE
    # ==========================================================

    figure.suptitle(
        "Payment Method & Order Behaviour",
        fontsize=16,
    )

    figure.tight_layout()

    # ==========================================================
    # SAVE
    # ==========================================================

    figure.savefig(
        OUTPUT_DIR / "payment_method_order_behaviour.png",
        dpi=150,
        bbox_inches="tight",
    )

    return figure


# ==========================================================
# VOUCHER VISUALIZATIONS
# ==========================================================

def save_voucher_chart(data: pd.DataFrame) -> plt.Figure:

    # ==========================================================
    # PREPARE DATA
    # ==========================================================

    voucher_summary = data.copy()

    top_vouchers = (
        voucher_summary[
            voucher_summary["TOP_10"] == 1
        ]
        .sort_values(
            "TOTAL_DISCOUNT_RM",
            ascending=False,
        )
    )

    # ==========================================================
    # CREATE FIGURE
    # ==========================================================

    figure, axes = plt.subplots(
        1,
        2,
        figsize=(16, 6),
    )

    # ==========================================================
    # CHART 1 — TOP VOUCHERS BY DISCOUNT GIVEN
    # Highest → Lowest
    # ==========================================================

    colors = plt.rcParams["axes.prop_cycle"].by_key()["color"]

    voucher_colors = [
        colors[index % len(colors)]
        for index in range(len(top_vouchers))
    ]

    top_vouchers_plot = top_vouchers.iloc[::-1]
    voucher_colors_plot = voucher_colors[::-1]

    axes[0].barh(
        top_vouchers_plot["VOUCHER_CODE"],
        top_vouchers_plot["TOTAL_DISCOUNT_RM"],
        color=voucher_colors_plot,
    )

    max_discount = top_vouchers_plot["TOTAL_DISCOUNT_RM"].max()

    for index, value in enumerate(
        top_vouchers_plot["TOTAL_DISCOUNT_RM"]
    ):

        axes[0].text(
            value + max_discount * 0.01,
            index,
            f"{value:,.2f}",
            va="center",
            fontsize=9,
        )

    axes[0].set_title(
        "Top Vouchers by Discount Given",
        fontsize=13,
    )

    axes[0].set_xlabel(
        "Discount (RM)",
        fontsize=11,
    )

    axes[0].set_ylabel(
        "Voucher Code",
        fontsize=11,
    )

    axes[0].set_xlim(
        0,
        max_discount * 1.18,
    )

    # ==========================================================
    # CHART 2 — PROMOTION COST VS REVENUE
    # ==========================================================

    axes[1].scatter(
        voucher_summary["TOTAL_DISCOUNT_RM"],
        voucher_summary["REVENUE_RM"],
        s=voucher_summary["BUBBLE_SIZE"],
        alpha=0.7,
        color="#66a61e",
    )

    axes[1].set_title(
        "Promotion Cost vs Revenue",
        fontsize=13,
    )

    axes[1].set_xlabel(
        "Discount (RM)",
        fontsize=11,
    )

    axes[1].set_ylabel(
        "Revenue (RM)",
        fontsize=11,
    )

    # ==========================================================
    # OVERALL TITLE
    # ==========================================================

    figure.suptitle(
        "Voucher & Promotion Effectiveness",
        fontsize=16,
    )

    figure.tight_layout()

    # ==========================================================
    # SAVE
    # ==========================================================

    figure.savefig(
        OUTPUT_DIR / "voucher_promotion_effectiveness.png",
        dpi=150,
        bbox_inches="tight",
    )

    return figure

def main(show: bool) -> None:

    OUTPUT_DIR.mkdir(
        exist_ok=True
    )

    delivery = load_csv(
        "order_fulfilment_delivery_performance.csv"
    )

    payment = load_csv(
        "payment_method_order_behaviour.csv"
    )

    voucher = load_csv(
        "voucher_promotion_effectiveness.csv"
    )

    # ==========================================================
    # CREATE ALL VISUALIZATIONS
    # ==========================================================

    figures = [
        save_delivery_chart(delivery),
        save_payment_chart(payment),
        save_voucher_chart(voucher),
    ]

    print(
        f"Visualizations saved to {OUTPUT_DIR}"
    )

    # ==========================================================
    # SHOW CHARTS
    # ==========================================================

    if show:
        plt.show()

    for figure in figures:
        plt.close(figure)


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        description=__doc__
    )

    parser.add_argument(
        "--show",
        action="store_true",
        help="Open chart windows after saving the PNG files.",
    )

    arguments = parser.parse_args()

    main(
        show=arguments.show
    )

