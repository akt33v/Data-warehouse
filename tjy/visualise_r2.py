"""
Report 4 Visualisations: Member Churn & Activation Status Analysis
Data: member_churn_status.csv
Cols: yr_month, member_type, member_status, order_count, total_revenue
"""

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
import os

# ── Load ──────────────────────────────────────────────────────────────────────
CSV = os.path.join(os.path.dirname(__file__), "member_churn_status.csv")

df = pd.read_csv(CSV, header=0, names=[
    "yr_month", "member_type", "member_status", "order_count", "total_revenue"
])
df["yr_month"] = df["yr_month"].astype(str)
df["order_count"] = pd.to_numeric(df["order_count"], errors="coerce")
df["total_revenue"] = pd.to_numeric(df["total_revenue"], errors="coerce")

STATUS_COLORS = {
    "ACTIVE":      "#2ECC71",
    "SUSPENDED":   "#F39C12",
    "DEACTIVATED": "#E74C3C"
}
TYPE_COLORS = {"NORMAL": "#4C9BE8", "VIP": "#F5A623"}

fig = plt.figure(figsize=(22, 28))
fig.suptitle("Report 4 — Member Churn & Activation Status Dashboard",
             fontsize=18, fontweight="bold", y=0.99)

# ══════════════════════════════════════════════════════════════════════════════
# VIZ 1 — Stacked bar: total revenue by status (ACTIVE / SUSPENDED / DEACTIVATED)
# Pattern: how much revenue comes from each status bucket overall
# ══════════════════════════════════════════════════════════════════════════════
ax1 = fig.add_subplot(3, 2, 1)
grp1 = df.groupby(["member_status", "member_type"])["total_revenue"].sum().unstack(fill_value=0)
x = np.arange(len(grp1.index))
w = 0.35
for i, mtype in enumerate(["NORMAL", "VIP"]):
    if mtype in grp1.columns:
        ax1.bar(x + i * w, grp1[mtype], w, label=mtype,
                color=TYPE_COLORS.get(mtype, "grey"), alpha=0.85)

ax1.set_xticks(x + w / 2)
ax1.set_xticklabels(grp1.index)
ax1.set_ylabel("Total Revenue (RM)")
ax1.set_title("1 · Revenue by Status & Member Type", fontweight="bold")
ax1.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f'RM {x/1000:.0f}k'))
ax1.legend()
ax1.grid(axis="y", alpha=0.3)

# ══════════════════════════════════════════════════════════════════════════════
# VIZ 2 — Line: monthly order count trend split by status
# Pattern: when do ACTIVE orders drop? Correlates with churn events
# ══════════════════════════════════════════════════════════════════════════════
ax2 = fig.add_subplot(3, 2, 2)
grp2 = df.groupby(["yr_month", "member_status"])["order_count"].sum().unstack(fill_value=0)
for status, color in STATUS_COLORS.items():
    if status in grp2.columns:
        ax2.plot(grp2.index, grp2[status], label=status, color=color,
                 linewidth=2, marker="o", markersize=3)

step = max(1, len(grp2) // 12)
ax2.set_xticks(range(0, len(grp2), step))
ax2.set_xticklabels(grp2.index[::step], rotation=45, ha="right", fontsize=7)
ax2.set_ylabel("Order Count")
ax2.set_title("2 · Monthly Order Trend by Member Status", fontweight="bold")
ax2.legend()
ax2.grid(axis="y", alpha=0.3)

# ══════════════════════════════════════════════════════════════════════════════
# VIZ 3 — Pie / donut: order share by status
# Pattern: proportion of orders from non-ACTIVE users = lost engagement
# ══════════════════════════════════════════════════════════════════════════════
ax3 = fig.add_subplot(3, 2, 3)
grp3 = df.groupby("member_status")["order_count"].sum()
wedge_colors = [STATUS_COLORS.get(s, "grey") for s in grp3.index]
wedges, texts, autotexts = ax3.pie(
    grp3.values,
    labels=grp3.index,
    autopct="%1.1f%%",
    colors=wedge_colors,
    startangle=90,
    wedgeprops=dict(width=0.55)
)
for at in autotexts:
    at.set_fontsize(9)
ax3.set_title("3 · Order Share by Member Status (Donut)", fontweight="bold")

# ══════════════════════════════════════════════════════════════════════════════
# VIZ 4 — Heatmap: revenue by yr_month x member_status
# Pattern: identify months where SUSPENDED/DEACTIVATED revenue spikes (churn events)
# ══════════════════════════════════════════════════════════════════════════════
ax4 = fig.add_subplot(3, 2, 4)
pivot4 = df.groupby(["member_status", "yr_month"])["total_revenue"].sum().unstack(fill_value=0)
# Sample every N months to keep readable
cols = pivot4.columns
step4 = max(1, len(cols) // 20)
pivot4_sub = pivot4[cols[::step4]]
im = ax4.imshow(pivot4_sub.values, cmap="RdYlGn", aspect="auto")
ax4.set_xticks(range(len(pivot4_sub.columns)))
ax4.set_xticklabels(pivot4_sub.columns, rotation=90, fontsize=6)
ax4.set_yticks(range(len(pivot4_sub.index)))
ax4.set_yticklabels(pivot4_sub.index)
plt.colorbar(im, ax=ax4, label="Revenue (RM)")
ax4.set_title("4 · Revenue Heatmap: Status × Month", fontweight="bold")

# ══════════════════════════════════════════════════════════════════════════════
# VIZ 5 — Stacked area: monthly revenue by status
# Pattern: erosion of ACTIVE revenue base over time; growing SUSPENDED share = warning
# ══════════════════════════════════════════════════════════════════════════════
ax5 = fig.add_subplot(3, 1, 3)
grp5 = df.groupby(["yr_month", "member_status"])["total_revenue"].sum().unstack(fill_value=0)
status_order = ["ACTIVE", "SUSPENDED", "DEACTIVATED"]
colors5 = [STATUS_COLORS[s] for s in status_order if s in grp5.columns]
cols5   = [s for s in status_order if s in grp5.columns]

ax5.stackplot(range(len(grp5)),
              [grp5[s] for s in cols5],
              labels=cols5,
              colors=colors5,
              alpha=0.75)

step5 = max(1, len(grp5) // 12)
ax5.set_xticks(range(0, len(grp5), step5))
ax5.set_xticklabels(grp5.index[::step5], rotation=45, ha="right", fontsize=7)
ax5.set_ylabel("Total Revenue (RM)")
ax5.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f'RM {x/1000:.0f}k'))
ax5.set_title("5 · Monthly Revenue Stack by Status  (shrinking ACTIVE = churn signal)",
              fontweight="bold")
ax5.legend(loc="upper right")
ax5.grid(axis="y", alpha=0.3)

# ── Save ─────────────────────────────────────────────────────────────────────
plt.tight_layout(rect=[0, 0, 1, 0.98])
out = os.path.join(os.path.dirname(__file__), "member_churn_dashboard.png")
plt.savefig(out, dpi=150, bbox_inches="tight")
print(f"Saved: {out}")
plt.show()
