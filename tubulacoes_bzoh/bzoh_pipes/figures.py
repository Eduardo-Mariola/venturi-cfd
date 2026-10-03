"""Figures of the calculation report."""

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt                     # noqa: E402
import numpy as np                                  # noqa: E402
from matplotlib.ticker import FuncFormatter, NullFormatter  # noqa: E402

from .tables import economic_velocity               # noqa: E402

SURFACE, INK, INK_2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
SLOTS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]   # validated categorical order

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 9, "axes.edgecolor": GRID,
    "axes.labelcolor": INK_2, "xtick.color": INK_2, "ytick.color": INK_2,
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
})


def _br(x, _=None):
    return f"{x:g}".replace(".", ",")


def _style(ax, log_x=True):
    ax.grid(True, which="major", color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(False)
    if log_x:
        ax.set_xticks([20, 30, 50, 100, 200, 300])
        ax.xaxis.set_minor_formatter(NullFormatter())
    ax.xaxis.set_major_formatter(FuncFormatter(_br))
    ax.yaxis.set_major_formatter(FuncFormatter(_br))


def plot_velocity_vs_diameter(results, path):
    """Design velocity of every line against the Walas/Turton economic curves."""
    D = np.logspace(np.log10(0.015), np.log10(0.40), 200)
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(12.5, 4.8),
                                 gridspec_kw=dict(wspace=0.28))

    liq_groups = [
        ("Recalque / pressurizada (inclui AR)", SLOTS[0], {"discharge", "cw"}),
        ("Líquido saturado (sucção, refervedor, condensado)", SLOTS[1],
         {"suction", "suction_vac", "reboiler_feed", "condensate"}),
        ("Gravidade (condensado → vaso)", SLOTS[2], {"gravity"}),
    ]
    a1.plot(D * 1e3, economic_velocity("discharge", D), color=SLOTS[0], lw=2,
            alpha=0.55)
    a1.plot(D * 1e3, economic_velocity("suction", D), color=SLOTS[1], lw=2,
            alpha=0.55)
    a1.text(330, economic_velocity("discharge", 0.33) * 1.12,
            "recalque: (5 + D/3) ft/s", color=INK_2, ha="right", fontsize=8)
    a1.text(330, economic_velocity("suction", 0.33) * 0.68,
            "sucção: (1,3 + D/6) ft/s", color=INK_2, ha="right", fontsize=8)
    for label, color, keys in liq_groups:
        rs = [r for r in results if r.line.service in keys]
        a1.scatter([r.chosen.size.ID * 1e3 for r in rs], [r.chosen.v_d for r in rs],
                   s=42, color=color, edgecolor=SURFACE, lw=1.2, label=label, zorder=3)
    rs = [r for r in results if r.line.service == "two_phase"]
    a1.scatter([r.chosen.size.ID * 1e3 for r in rs], [r.chosen.v_d for r in rs],
               s=55, marker="D", facecolor=SURFACE, edgecolor=SLOTS[0], lw=1.8,
               label="Bifásico (correntes 6 e 16)", zorder=3)
    a1.axvline(20.93, color=INK_2, lw=1, ls=(0, (1, 2)))
    a1.text(19.6, 0.0016, 'DN mínimo 3/4"', color=INK_2, fontsize=8, rotation=90,
            va="bottom", ha="right")
    a1.set_xscale("log")
    a1.set_yscale("log")
    a1.set_ylim(1e-3, 10)
    a1.set_xlim(15, 400)
    a1.set_xlabel("Diâmetro interno [mm]")
    a1.set_ylabel("Velocidade na vazão de projeto [m/s]")
    a1.set_title("Linhas de líquido", loc="left", fontsize=10, color=INK)
    _style(a1)
    a1.legend(loc="lower right", frameon=False, fontsize=7.8)

    vap_groups = [
        ("Vapor de processo (≈ 1 atm)", SLOTS[0], {"vapor"}),
        ("Vapor de processo em vácuo", SLOTS[1], {"vapor_vac"}),
        ("Vapor d'água (utilidade)", SLOTS[2], {"steam"}),
    ]
    a2.plot(D * 1e3, economic_velocity("gas", D), color=INK_2, lw=2, alpha=0.5)
    a2.text(110, economic_velocity("gas", 0.11) * 1.05, "20·D ft/s (Walas)",
            color=INK_2, fontsize=8, ha="right")
    a2.axhline(40, color=INK_2, lw=1, ls=(0, (4, 3)))
    a2.text(395, 41.5, "limite 40 m/s", color=INK_2, fontsize=8, ha="right")
    for label, color, keys in vap_groups:
        rs = [r for r in results if r.line.service in keys]
        a2.scatter([r.chosen.size.ID * 1e3 for r in rs], [r.chosen.v_d for r in rs],
                   s=48, color=color, edgecolor=SURFACE, lw=1.2, label=label, zorder=3)
    a2.set_xscale("log")
    a2.set_xlim(15, 400)
    a2.set_ylim(0, 65)
    a2.set_xlabel("Diâmetro interno [mm]")
    a2.set_ylabel("Velocidade na vazão de projeto [m/s]")
    a2.set_title("Linhas de vapor", loc="left", fontsize=10, color=INK)
    _style(a2)
    a2.legend(loc="upper left", frameon=False, fontsize=7.8)
    fig.suptitle("Velocidade de projeto das linhas × velocidade econômica",
                 x=0.06, ha="left", fontsize=11, color=INK, weight="bold")
    fig.savefig(path, dpi=160, bbox_inches="tight")
    plt.close(fig)


def plot_dn_distribution(results, path):
    """Number of lines per nominal size, stacked by piping class."""
    from .tables import B3619
    order = [k for k in B3619 if any(r.chosen.size.label == k for r in results)]
    specs = ["S1", "S2", "C1", "C2"]
    names = {"S1": "S1 - inox 316L", "S2": "S2 - inox 304L",
             "C1": "C1 - aço carbono (Cl. 150)", "C2": "C2 - aço carbono (Cl. 600)"}
    fig, ax = plt.subplots(figsize=(9.5, 3.8))
    bottom = np.zeros(len(order))
    for sp, color in zip(specs, SLOTS):
        cnt = np.array([sum(1 for r in results if r.chosen.size.label == k
                            and r.spec.code == sp) for k in order])
        ax.bar(range(len(order)), cnt, bottom=bottom, width=0.6, color=color,
               edgecolor=SURFACE, lw=2, label=names[sp])
        bottom += cnt
    for i, tot in enumerate(bottom):
        ax.text(i, tot + 0.6, f"{int(tot)}", ha="center", fontsize=8.5, color=INK)
    ax.set_xticks(range(len(order)))
    ax.set_xticklabels(order, color=INK)
    ax.set_ylabel("Número de linhas")
    ax.set_xlabel("Diâmetro nominal (NPS)")
    ax.set_ylim(0, max(bottom) * 1.15)
    ax.grid(axis="y", color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(False)
    ax.legend(frameon=False, fontsize=8.5, loc="upper right")
    ax.set_title("Distribuição dos diâmetros nominais por classe de material",
                 loc="left", fontsize=11, color=INK, weight="bold")
    fig.savefig(path, dpi=160, bbox_inches="tight")
    plt.close(fig)
