import os
import warnings
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")  # non-interactive backend: save PNG without opening a blocking GUI window
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

warnings.filterwarnings("ignore")
matplotlib.rcParams.update({
    "font.family": "sans-serif",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "grid.alpha": 0.25,
    "axes.labelsize": 10,
    "axes.titlesize": 11,
    "axes.titleweight": "bold",
    "figure.dpi": 130,
})

HERE = os.path.dirname(os.path.abspath(__file__))

# ── Load data ─────────────────────────────────────────────────────────────────
SUM_CSV = os.path.join(HERE, "voucher_quarter_summary.csv")
ROI_CSV = os.path.join(HERE, "voucher_lifetime_roi.csv")

SUM_COLS = ["pv_quarter", "voucher_type", "day_flag", "order_count",
            "discount_given", "gross_revenue", "roi_multiple"]
ROI_COLS = ["voucher_type", "order_count", "discount_given",
            "gross_revenue", "roi_multiple", "roi_rank"]

df  = pd.read_csv(SUM_CSV, header=0, names=SUM_COLS)
dfr = pd.read_csv(ROI_CSV, header=0, names=ROI_COLS)

for col in ["order_count", "discount_given", "gross_revenue", "roi_multiple"]:
    df[col] = pd.to_numeric(df[col], errors="coerce")
for col in ["order_count", "discount_given", "gross_revenue", "roi_multiple", "roi_rank"]:
    dfr[col] = pd.to_numeric(dfr[col], errors="coerce")

TYPE_COLORS = {"PERCENT": "#4C9BE8", "FIXED": "#F5A623", "FREE_DELIVERY": "#2ECC71"}
DAY_COLORS = {"HOLIDAY": "#E74C3C", "REGULAR": "#95A5A6"}
QUARTERS = sorted(df["pv_quarter"].unique())

fig = plt.figure(figsize=(24, 28))
fig.suptitle(
    "Report 9 — Voucher Campaign ROI & Conversion Analysis Dashboard",
    fontsize=18, fontweight="bold", y=0.995
)
gs = fig.add_gridspec(3, 2, hspace=0.46, wspace=0.35)

# =============================================================================
# VIZ 1 — Grouped bar: Discount given vs gross revenue by voucher type
# =============================================================================
ax1 = fig.add_subplot(gs[0, 0])
grp1 = df.groupby("voucher_type")[["discount_given", "gross_revenue"]].sum()
x1 = np.arange(len(grp1))
w1 = 0.35
ax1.bar(x1 - w1 / 2, grp1["discount_given"], w1, label="Discount Given", color="#E74C3C", alpha=0.85)
ax1.bar(x1 + w1 / 2, grp1["gross_revenue"], w1, label="Gross Revenue", color="#2ECC71", alpha=0.85)
ax1.set_xticks(x1)
ax1.set_xticklabels(grp1.index, fontsize=9)
ax1.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax1.set_title("1 · Discount Given vs Gross Revenue by Voucher Type")
ax1.set_ylabel("Amount (RM)")
ax1.legend(fontsize=9)

# =============================================================================
# VIZ 2 — Horizontal bar: Lifetime ROI multiple ranking
# =============================================================================
ax2 = fig.add_subplot(gs[0, 1])
dfr_sorted = dfr.sort_values("roi_multiple")
colors2 = [TYPE_COLORS.get(t, "grey") for t in dfr_sorted["voucher_type"]]
bars2 = ax2.barh(dfr_sorted["voucher_type"], dfr_sorted["roi_multiple"], color=colors2, alpha=0.88)
for bar, val in zip(bars2, dfr_sorted["roi_multiple"]):
    ax2.text(val + 0.05, bar.get_y() + bar.get_height() / 2, f"{val:.2f}x", va="center", fontsize=9)
ax2.axvline(x=1.0, color="grey", lw=1, ls="--", alpha=0.6)
ax2.set_title("2 · Lifetime ROI (RM Revenue per RM Discount)")
ax2.set_xlabel("ROI Multiple")

# =============================================================================
# VIZ 3 — Stacked bar: Holiday vs Regular revenue by voucher type
# =============================================================================
ax3 = fig.add_subplot(gs[1, 0])
grp3 = df.groupby(["voucher_type", "day_flag"])["gross_revenue"].sum().unstack(fill_value=0)
x3 = np.arange(len(grp3))
bottom = np.zeros(len(grp3))
for flag in ["REGULAR", "HOLIDAY"]:
    if flag in grp3.columns:
        vals = grp3[flag].values
        ax3.bar(x3, vals, 0.6, bottom=bottom, label=flag, color=DAY_COLORS[flag], alpha=0.88)
        bottom += vals
ax3.set_xticks(x3)
ax3.set_xticklabels(grp3.index, fontsize=9)
ax3.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax3.set_title("3 · Holiday vs Regular-Day Revenue by Voucher Type")
ax3.set_ylabel("Revenue (RM)")
ax3.legend(fontsize=9)

# =============================================================================
# VIZ 4 — Line: Quarterly revenue trend by voucher type
# =============================================================================
ax4 = fig.add_subplot(gs[1, 1])
grp4 = df.groupby(["pv_quarter", "voucher_type"])["gross_revenue"].sum().unstack(fill_value=0).reindex(QUARTERS)
for vtype in TYPE_COLORS:
    if vtype in grp4.columns:
        ax4.plot(grp4.index, grp4[vtype], marker="o", color=TYPE_COLORS[vtype], label=vtype, linewidth=2.2)
ax4.set_xticklabels(grp4.index, rotation=45, ha="right", fontsize=8)
ax4.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax4.set_title("4 · Voucher-Driven Revenue Trend by Quarter")
ax4.set_ylabel("Revenue (RM)")
ax4.legend(fontsize=9)

# =============================================================================
# VIZ 5 — Scatter: Order count vs ROI multiple per quarter/type (bubble = discount)
# =============================================================================
ax5 = fig.add_subplot(gs[2, 0])
for vtype, color in TYPE_COLORS.items():
    sub = df[df["voucher_type"] == vtype]
    ax5.scatter(sub["order_count"], sub["roi_multiple"],
                s=(sub["discount_given"] / df["discount_given"].max() * 500).clip(lower=15),
                c=color, alpha=0.65, edgecolors="white", linewidths=0.5, label=vtype)
ax5.axhline(y=1.0, color="grey", lw=1, ls="--", alpha=0.6)
ax5.set_xlabel("Orders (per Quarter)")
ax5.set_ylabel("ROI Multiple")
ax5.set_title("5 · Orders vs ROI by Voucher Type (bubble = discount RM)")
ax5.legend(fontsize=9)

# =============================================================================
# VIZ 6 — 100% stacked bar: Voucher type share of total discount spend by quarter
# =============================================================================
ax6 = fig.add_subplot(gs[2, 1])
pivot6 = df.groupby(["pv_quarter", "voucher_type"])["discount_given"].sum().unstack(fill_value=0).reindex(QUARTERS)
pivot6_pct = pivot6.div(pivot6.sum(axis=1), axis=0) * 100
bottom = np.zeros(len(pivot6_pct))
for vtype in TYPE_COLORS:
    if vtype in pivot6_pct.columns:
        vals = pivot6_pct[vtype].values
        ax6.bar(pivot6_pct.index, vals, bottom=bottom, label=vtype, color=TYPE_COLORS[vtype], alpha=0.88)
        bottom += vals
ax6.set_xticklabels(pivot6_pct.index, rotation=45, ha="right", fontsize=8)
ax6.set_ylim(0, 100)
ax6.set_ylabel("% of Discount Spend")
ax6.set_title("6 · Discount Spend Share by Voucher Type per Quarter")
ax6.legend(fontsize=8, loc="lower right")

# ── Save ──────────────────────────────────────────────────────────────────────
plt.tight_layout(rect=[0, 0, 1, 0.987])
out = os.path.join(HERE, "voucher_roi_dashboard.png")
plt.savefig(out, dpi=150, bbox_inches="tight")
print(f"Dashboard saved: {out}")
plt.show()
