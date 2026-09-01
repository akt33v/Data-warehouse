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
SUM_CSV = os.path.join(HERE, "delivery_quarter_summary.csv")
SHARE_CSV = os.path.join(HERE, "delivery_lifetime_share.csv")

SUM_COLS = ["pv_quarter", "company_name", "day_flag", "order_count", "fee_revenue", "avg_fee"]
SHARE_COLS = ["company_name", "service_status", "order_count", "fee_revenue", "market_share", "share_rank"]

df  = pd.read_csv(SUM_CSV, header=0, names=SUM_COLS)
dfs = pd.read_csv(SHARE_CSV, header=0, names=SHARE_COLS)

for col in ["order_count", "fee_revenue", "avg_fee"]:
    df[col] = pd.to_numeric(df[col], errors="coerce")
for col in ["order_count", "fee_revenue", "market_share", "share_rank"]:
    dfs[col] = pd.to_numeric(dfs[col], errors="coerce")

COMPANIES = list(dfs.sort_values("market_share", ascending=False)["company_name"])
CMAP = plt.cm.tab10(np.linspace(0, 1, max(len(COMPANIES), 1)))
COMPANY_COLORS = {c: CMAP[i] for i, c in enumerate(COMPANIES)}
DAY_COLORS = {"WEEKEND": "#E67E22", "WEEKDAY": "#4C9BE8"}
QUARTERS = sorted(df["pv_quarter"].unique())

fig = plt.figure(figsize=(24, 28))
fig.suptitle(
    "Report 11 — Delivery Partner Performance & Operational Reliance Dashboard",
    fontsize=18, fontweight="bold", y=0.995
)
gs = fig.add_gridspec(3, 2, hspace=0.46, wspace=0.35)

# =============================================================================
# VIZ 1 — Pie/donut: Lifetime market share by delivery company
# =============================================================================
ax1 = fig.add_subplot(gs[0, 0])
colors1 = [COMPANY_COLORS.get(c, "grey") for c in dfs["company_name"]]
wedges, texts, autotexts = ax1.pie(
    dfs["fee_revenue"], labels=dfs["company_name"], autopct="%1.0f%%",
    colors=colors1, startangle=90, pctdistance=0.8,
    wedgeprops=dict(width=0.4, edgecolor="white")
)
plt.setp(autotexts, size=8, weight="bold", color="white")
plt.setp(texts, size=8.5)
ax1.set_title("1 · Lifetime Delivery Fee Revenue Market Share")

# =============================================================================
# VIZ 2 — Line: Quarterly order volume trend by company
# =============================================================================
ax2 = fig.add_subplot(gs[0, 1])
grp2 = df.groupby(["pv_quarter", "company_name"])["order_count"].sum().unstack(fill_value=0).reindex(QUARTERS)
for c in COMPANIES:
    if c in grp2.columns:
        ax2.plot(grp2.index, grp2[c], marker="o", color=COMPANY_COLORS[c], label=c, linewidth=2.0)
ax2.set_xticklabels(grp2.index, rotation=45, ha="right", fontsize=8)
ax2.set_title("2 · Order Volume Trend by Delivery Company")
ax2.set_ylabel("Orders")
ax2.legend(fontsize=7.5, ncol=2)

# =============================================================================
# VIZ 3 — Grouped bar: Weekend vs Weekday order share by company
# =============================================================================
ax3 = fig.add_subplot(gs[1, 0])
grp3 = df.groupby(["company_name", "day_flag"])["order_count"].sum().unstack(fill_value=0)
grp3_pct = grp3.div(grp3.sum(axis=1), axis=0) * 100
grp3_pct = grp3_pct.reindex(COMPANIES)
x3 = np.arange(len(grp3_pct))
bottom = np.zeros(len(grp3_pct))
for flag in ["WEEKDAY", "WEEKEND"]:
    if flag in grp3_pct.columns:
        vals = grp3_pct[flag].values
        ax3.bar(x3, vals, 0.6, bottom=bottom, label=flag, color=DAY_COLORS[flag], alpha=0.88)
        for j, (v, b) in enumerate(zip(vals, bottom)):
            if v > 6:
                ax3.text(j, b + v / 2, f"{v:.0f}%", ha="center", va="center", fontsize=8, color="white", fontweight="bold")
        bottom += vals
ax3.set_xticks(x3)
ax3.set_xticklabels(grp3_pct.index, rotation=25, ha="right", fontsize=8)
ax3.set_ylim(0, 100)
ax3.set_ylabel("% of Company Order Volume")
ax3.set_title("3 · Weekend vs Weekday Reliance by Delivery Company")
ax3.legend(fontsize=9)

# =============================================================================
# VIZ 4 — Bar: Avg delivery fee per order by company
# =============================================================================
ax4 = fig.add_subplot(gs[1, 1])
grp4 = df.groupby("company_name").apply(
    lambda g: g["fee_revenue"].sum() / g["order_count"].sum()
).sort_values(ascending=True)
colors4 = [COMPANY_COLORS.get(c, "grey") for c in grp4.index]
bars4 = ax4.bar(grp4.index, grp4.values, color=colors4, alpha=0.88)
for bar, val in zip(bars4, grp4.values):
    ax4.text(bar.get_x() + bar.get_width() / 2, val + grp4.max() * 0.01, f"RM {val:.2f}",
              ha="center", fontsize=8)
ax4.set_xticklabels(grp4.index, rotation=25, ha="right", fontsize=8)
ax4.set_title("4 · Average Delivery Fee per Order by Company (Ascending)")
ax4.set_ylabel("Avg Fee (RM)")

# =============================================================================
# VIZ 5 — Horizontal bar: Market share ranking (concentration risk)
# =============================================================================
ax5 = fig.add_subplot(gs[2, 0])
dfs_sorted = dfs.sort_values("market_share")
colors5 = [COMPANY_COLORS.get(c, "grey") for c in dfs_sorted["company_name"]]
bars5 = ax5.barh(dfs_sorted["company_name"], dfs_sorted["market_share"], color=colors5, alpha=0.88)
for bar, val in zip(bars5, dfs_sorted["market_share"]):
    ax5.text(val + 0.5, bar.get_y() + bar.get_height() / 2, f"{val:.1f}%", va="center", fontsize=9)
ax5.axvline(x=50, color="red", lw=1, ls="--", alpha=0.5)
ax5.text(50.5, -0.6, "50% concentration threshold", fontsize=7, color="red", style="italic")
ax5.set_xlabel("Lifetime Market Share (%)")
ax5.set_title("5 · Delivery Partner Concentration Risk Ranking")

# =============================================================================
# VIZ 6 — Stacked area: Fee revenue trend by company (fulfilment cost trend)
# =============================================================================
ax6 = fig.add_subplot(gs[2, 1])
grp6 = df.groupby(["pv_quarter", "company_name"])["fee_revenue"].sum().unstack(fill_value=0).reindex(QUARTERS)
series6 = [grp6[c].values if c in grp6.columns else np.zeros(len(grp6)) for c in COMPANIES]
ax6.stackplot(grp6.index, series6, labels=COMPANIES,
              colors=[COMPANY_COLORS[c] for c in COMPANIES], alpha=0.82)
ax6.set_xticklabels(grp6.index, rotation=45, ha="right", fontsize=8)
ax6.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"RM {v/1000:.0f}k"))
ax6.set_title("6 · Delivery Fee Cost Trend by Company (Stacked)")
ax6.set_ylabel("Fee Revenue (RM)")
ax6.legend(fontsize=7.5, loc="upper left", ncol=2)

# ── Save ──────────────────────────────────────────────────────────────────────
plt.tight_layout(rect=[0, 0, 1, 0.987])
out = os.path.join(HERE, "delivery_performance_dashboard.png")
plt.savefig(out, dpi=150, bbox_inches="tight")
print(f"Dashboard saved: {out}")
plt.show()
