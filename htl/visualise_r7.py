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
SUM_CSV = os.path.join(HERE, "menu_tier_summary.csv")
ITEM_CSV = os.path.join(HERE, "menu_item_detail.csv")

SUM_COLS = ["pv_quarter", "item_category", "meal_tier", "deal_flag",
            "item_type", "qty_sold", "revenue", "avg_unit_price"]
ITEM_COLS = ["item_name", "item_category", "meal_tier", "deal_flag", "item_type",
             "qty_sold", "revenue", "avg_unit_price", "cat_rank", "price_quartile"]

df  = pd.read_csv(SUM_CSV, header=0, names=SUM_COLS)
dfi = pd.read_csv(ITEM_CSV, header=0, names=ITEM_COLS)

for col in ["qty_sold", "revenue", "avg_unit_price"]:
    df[col] = pd.to_numeric(df[col], errors="coerce")
for col in ["qty_sold", "revenue", "avg_unit_price", "cat_rank", "price_quartile"]:
    dfi[col] = pd.to_numeric(dfi[col], errors="coerce")

TIER_COLORS = {"BUDGET": "#4C9BE8", "PREMIUM": "#F5A623"}
DEAL_COLORS = {"ON DEAL": "#2ECC71", "REGULAR": "#95A5A6"}
QUARTERS = sorted(df["pv_quarter"].unique())

fig = plt.figure(figsize=(24, 28))
fig.suptitle(
    "Report 7 — Menu Item Category Performance: Budget vs Premium Dashboard",
    fontsize=18, fontweight="bold", y=0.995
)
gs = fig.add_gridspec(3, 2, hspace=0.46, wspace=0.35)

# =============================================================================
# VIZ 1 — Stacked bar: Budget vs Premium revenue share by category
# =============================================================================
ax1 = fig.add_subplot(gs[0, 0])
grp1 = df.groupby(["item_category", "meal_tier"])["revenue"].sum().unstack(fill_value=0)
grp1 = grp1.loc[grp1.sum(axis=1).sort_values(ascending=False).index]
x1 = np.arange(len(grp1))
bottom = np.zeros(len(grp1))
for tier in ["BUDGET", "PREMIUM"]:
    if tier in grp1.columns:
        vals = grp1[tier].values
        ax1.bar(x1, vals, 0.6, bottom=bottom, label=tier, color=TIER_COLORS[tier], alpha=0.88)
        bottom += vals
ax1.set_xticks(x1)
ax1.set_xticklabels(grp1.index, rotation=30, ha="right", fontsize=8)
ax1.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax1.set_title("1 · Budget vs Premium Revenue by Category", fontsize=11)
ax1.set_ylabel("Revenue (RM)")
ax1.legend(fontsize=8)

# =============================================================================
# VIZ 2 — Line: Budget vs Premium revenue trend by quarter
# =============================================================================
ax2 = fig.add_subplot(gs[0, 1])
grp2 = df.groupby(["pv_quarter", "meal_tier"])["revenue"].sum().unstack(fill_value=0).reindex(QUARTERS)
for tier in ["BUDGET", "PREMIUM"]:
    if tier in grp2.columns:
        ax2.plot(grp2.index, grp2[tier], marker="o", color=TIER_COLORS[tier], label=tier, linewidth=2.2)
ax2.set_xticklabels(grp2.index, rotation=45, ha="right", fontsize=8)
ax2.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax2.set_title("2 · Budget vs Premium Revenue Trend by Quarter")
ax2.set_ylabel("Revenue (RM)")
ax2.legend(fontsize=9)

# =============================================================================
# VIZ 3 — Grouped bar: Super Deal (ON DEAL) vs Regular revenue by quarter
# =============================================================================
ax3 = fig.add_subplot(gs[1, 0])
grp3 = df.groupby(["pv_quarter", "deal_flag"])["revenue"].sum().unstack(fill_value=0).reindex(QUARTERS)
x3 = np.arange(len(grp3))
w3 = 0.35
for i, flag in enumerate(["REGULAR", "ON DEAL"]):
    if flag in grp3.columns:
        ax3.bar(x3 + i * w3, grp3[flag], w3, label=flag, color=DEAL_COLORS[flag], alpha=0.88)
ax3.set_xticks(x3 + w3 / 2)
ax3.set_xticklabels(grp3.index, rotation=45, ha="right", fontsize=8)
ax3.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax3.set_title("3 · Super Deal vs Regular-Priced Revenue by Quarter")
ax3.set_ylabel("Revenue (RM)")
ax3.legend(fontsize=9)

# =============================================================================
# VIZ 4 — Heatmap: Avg unit price by Category × Meal Tier
# =============================================================================
ax4 = fig.add_subplot(gs[1, 1])
pivot4 = df.groupby(["item_category", "meal_tier"]).apply(
    lambda g: np.average(g["avg_unit_price"], weights=g["qty_sold"].replace(0, np.nan).fillna(1))
).unstack(fill_value=0)
im = ax4.imshow(pivot4.values, cmap="YlOrRd", aspect="auto")
ax4.set_xticks(range(len(pivot4.columns)))
ax4.set_xticklabels(pivot4.columns, fontsize=9)
ax4.set_yticks(range(len(pivot4.index)))
ax4.set_yticklabels(pivot4.index, fontsize=8.5)
for r in range(len(pivot4.index)):
    for c in range(len(pivot4.columns)):
        v = pivot4.values[r, c]
        ax4.text(c, r, f"{v:.1f}", ha="center", va="center", fontsize=8,
                  color="white" if v > pivot4.values.max() * 0.6 else "black")
plt.colorbar(im, ax=ax4, label="Avg Unit Price (RM)", shrink=0.85)
ax4.set_title("4 · Avg Unit Price Heatmap: Category × Meal Tier")

# =============================================================================
# VIZ 5 — Scatter: Item-level revenue vs avg unit price (bubble = qty sold)
# =============================================================================
ax5 = fig.add_subplot(gs[2, 0])
for tier, color in TIER_COLORS.items():
    sub = dfi[dfi["meal_tier"] == tier]
    ax5.scatter(sub["avg_unit_price"], sub["revenue"], s=(sub["qty_sold"] / dfi["qty_sold"].max() * 400).clip(lower=10),
                c=color, alpha=0.65, edgecolors="white", linewidths=0.5, label=tier)
ax5.set_xlabel("Avg Unit Price (RM)")
ax5.set_ylabel("Lifetime Revenue (RM)")
ax5.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax5.set_title("5 · Item Revenue vs Unit Price (bubble = qty sold)")
ax5.legend(fontsize=9)

# =============================================================================
# VIZ 6 — Horizontal bar: Top 15 items lifetime revenue, colored by tier
# =============================================================================
ax6 = fig.add_subplot(gs[2, 1])
top15 = dfi.sort_values("revenue", ascending=False).head(15).iloc[::-1]
colors6 = [TIER_COLORS.get(t, "grey") for t in top15["meal_tier"]]
ax6.barh(top15["item_name"], top15["revenue"], color=colors6, alpha=0.88)
ax6.xaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax6.set_title("6 · Top 15 Menu Items by Lifetime Revenue")
ax6.tick_params(axis="y", labelsize=8)
handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in TIER_COLORS.values()]
ax6.legend(handles, TIER_COLORS.keys(), fontsize=8, loc="lower right")

# ── Save ──────────────────────────────────────────────────────────────────────
plt.tight_layout(rect=[0, 0, 1, 0.987])
out = os.path.join(HERE, "menu_performance_dashboard.png")
plt.savefig(out, dpi=150, bbox_inches="tight")
print(f"Dashboard saved: {out}")
plt.show()
