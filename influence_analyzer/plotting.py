"""
Plots of participant and response, campaign C according to the regimes response curves.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from .campaigns import SHORT, UNITS
from .config import MIN_R2

def response_plots(frame, features, srp, predictions, selected, output, label):
    fig, axes = plt.subplots(1, len(features), figsize=(5 * len(features), 4.2), layout="constrained", squeeze=False)
    for ax, feature in zip(axes[0], features):
        ax.scatter(frame[feature], frame[srp], s=25, color="#1d617a", alpha=.8, edgecolors="white", linewidths=.35)
        ax.set_xlabel(SHORT.get(feature, feature))
        ax.set_ylabel(f"{srp} ({UNITS.get(srp, '')})")
        ax.grid(alpha=.18)
    fig.suptitle(label + " observations (other participants may vary)", fontsize=12)
    fig.savefig(output / "participant_response.png", dpi=170)
    plt.close(fig)

def plot_control_regimes(data, spec, output):
    cells = sorted(data.joint_cell.unique())
    fig, axes = plt.subplots(2, 4, figsize=(15, 7), layout="constrained", sharex=True, sharey=True)
    for ax, cell in zip(axes.flat, cells):
        for rep, sub in data.loc[data.joint_cell.eq(cell)].groupby("representative_id"):
            sub = sub.sort_values("w_gain")
            ax.plot(sub.w_gain, sub[spec['output_srp']], ".-", ms=5, lw=1, label=f"Rep. {rep}")
        ax.set_title(cell.replace("__", " / "))
        ax.set_xlabel("Angular gain")
        ax.set_ylabel("Tracking error RMS (pixel)")
        ax.grid(alpha=.18)
        ax.legend(fontsize=8)
    for ax in list(axes.flat)[len(cells):]:
        ax.axis("off")
    fig.suptitle("Campaign C: individual upstream representatives within each observed joint regime", fontsize=13)
    fig.savefig(output / "C_regime_response_curves.png", dpi=170)
    fig.savefig(output / "C_regime_response_curves.pdf")
    plt.close(fig)
