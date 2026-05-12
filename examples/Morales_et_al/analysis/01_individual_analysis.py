"""
01_individual_analysis.py
=========================
Analyze per-sample (individual) RNA editing site (RES) detection results
from the Morales et al. pipeline and compare trends to the benchmark paper:

  Morales et al. (2023) "A Benchmark of RNA Editing Detection Tools"
  PMC10527054 — https://pmc.ncbi.nlm.nih.gov/articles/PMC10527054/

Data source:
  ../Benchmark-of-RNA-Editing-Detection-Tools/Data_*.json
  Each JSON contains per-clone results indexed as:
    data[aligner][condition][clone][threshold] = {N_RES, N_REDIportal, N_Alu, SNPs}

Tools analyzed (all using STAR aligner output):
  - REDItools2 : per-sample; thresholds = min supporting reads (2, 4, 6, 8, 10)
  - BCFtools   : per-sample; threshold = minor allele frequency (0 = no filter)
  - SPRINT     : per-sample; thresholds = min supporting reads — FAILED (0 sites)
  - RED-ML     : per-sample; thresholds = min P_edit probability — FAILED (0 sites)
  - JACUSA2    : joint WT vs ADAR1KO; thresholds = min supporting reads (2, 4, 6, 8, 10)

SPRINT and RED-ML failures are documented in 03_comparison_to_paper.py.

Outputs (written to ./results/):
  01_individual_summary.csv      — per-tool, per-condition, per-threshold stats
  01_individual_analysis.png     — N_RES and %REDIportal vs threshold (WT)
  01_both_conditions.png         — N_RES side-by-side: WT and ADAR1KO
"""

import json
import os

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# Paths (resolved relative to this script's location)
# ---------------------------------------------------------------------------
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
MORALES_DIR  = os.path.dirname(SCRIPT_DIR)
BENCHMARK_DIR = os.path.join(MORALES_DIR, "Benchmark-of-RNA-Editing-Detection-Tools")
RESULTS_DIR  = os.path.join(SCRIPT_DIR, "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

ALIGNER    = "star"
CONDITIONS = ["WT", "ADAR1KO"]
CLONES     = ["clone1", "clone2", "clone3"]

# Tool name -> (json filename, data layout, x-axis label)
TOOL_CONFIGS = {
    "REDItools2": ("Data_REDItool2.json", "per_clone",     "Min. supporting reads"),
    "BCFtools":   ("Data_BCFTools.json",  "per_clone",     "MAF threshold"),
    "SPRINT":     ("Data_SPRINT.json",    "per_clone",     "Min. supporting reads"),
    "RED-ML":     ("Data_REDML.json",     "per_clone",     "Min. P_edit"),
    "JACUSA2":    ("Data_JACUSA2.json",   "per_condition", "Min. supporting reads"),
}

# Tools that produced no output in our pipeline run
FAILED_TOOLS = {"SPRINT", "RED-ML"}

TOOL_COLORS = {
    "REDItools2": "#2196F3",
    "BCFtools":   "#FF9800",
    "SPRINT":     "#4CAF50",
    "RED-ML":     "#9C27B0",
    "JACUSA2":    "#F44336",
}


# ---------------------------------------------------------------------------
# Data loading helpers
# ---------------------------------------------------------------------------

def load_json(json_path: str) -> dict:
    with open(json_path) as f:
        return json.load(f)


def compute_per_clone_means(data: dict, condition: str) -> dict:
    """
    Average N_RES and REDIportal support across the three biological clones.

    Returns a dict keyed by float threshold:
      {threshold: {N_RES_mean, N_RES_sem, pct_redi_mean, pct_redi_sem, pct_alu_mean, N_SNPs_mean}}
    """
    condition_data = data[ALIGNER][condition]
    # Thresholds are JSON keys — sort numerically
    thresholds = sorted(condition_data[CLONES[0]].keys(), key=lambda x: float(x))

    results = {}
    for t in thresholds:
        n_res_vals, pct_redi_vals, pct_alu_vals, snp_vals = [], [], [], []

        for clone in CLONES:
            entry   = condition_data[clone][t]
            n_res   = entry.get("N_RES", 0)
            n_redi  = entry.get("N_REDIportal", 0)
            n_alu   = entry.get("N_Alu", 0)
            n_snps  = entry.get("SNPs", 0)

            n_res_vals.append(n_res)
            pct_redi_vals.append(100 * n_redi / n_res if n_res > 0 else 0.0)
            pct_alu_vals.append(100 * n_alu  / n_res if n_res > 0 else 0.0)
            snp_vals.append(n_snps)

        results[float(t)] = {
            "N_RES_mean":      float(np.mean(n_res_vals)),
            "N_RES_sem":       float(np.std(n_res_vals, ddof=1) / np.sqrt(3)),
            "pct_redi_mean":   float(np.mean(pct_redi_vals)),
            "pct_redi_sem":    float(np.std(pct_redi_vals, ddof=1) / np.sqrt(3)),
            "pct_alu_mean":    float(np.mean(pct_alu_vals)),
            "N_SNPs_mean":     float(np.mean(snp_vals)),
        }
    return results


def compute_per_condition(data: dict, condition: str) -> dict:
    """
    Extract metrics for tools (JACUSA2) that produce a single result per
    condition rather than per clone.
    """
    condition_data = data[ALIGNER][condition]
    thresholds = sorted(condition_data.keys(), key=lambda x: float(x))

    results = {}
    for t in thresholds:
        entry  = condition_data[t]
        n_res  = entry.get("N_RES", 0)
        n_redi = entry.get("N_REDIportal", 0)
        n_alu  = entry.get("N_Alu", 0)
        results[float(t)] = {
            "N_RES_mean":    float(n_res),
            "N_RES_sem":     0.0,
            "pct_redi_mean": 100 * n_redi / n_res if n_res > 0 else 0.0,
            "pct_redi_sem":  0.0,
            "pct_alu_mean":  100 * n_alu  / n_res if n_res > 0 else 0.0,
            "N_SNPs_mean":   0.0,
        }
    return results


# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

def main():
    # ---- Load all tool data ---------------------------------------------------
    all_rows    = []
    tool_results = {}   # tool -> condition -> {threshold -> metrics}

    for tool, (json_file, data_type, thresh_label) in TOOL_CONFIGS.items():
        json_path = os.path.join(BENCHMARK_DIR, json_file)
        data = load_json(json_path)
        tool_results[tool] = {}

        for condition in CONDITIONS:
            if data_type == "per_clone":
                metrics = compute_per_clone_means(data, condition)
            else:
                metrics = compute_per_condition(data, condition)

            tool_results[tool][condition] = metrics

            for threshold, vals in metrics.items():
                all_rows.append({
                    "tool":             tool,
                    "condition":        condition,
                    "threshold":        threshold,
                    "threshold_label":  thresh_label,
                    "N_RES_mean":       round(vals["N_RES_mean"], 1),
                    "N_RES_sem":        round(vals["N_RES_sem"], 1),
                    "pct_REDIportal":   round(vals["pct_redi_mean"], 2),
                    "pct_REDIportal_sem": round(vals["pct_redi_sem"], 2),
                    "pct_Alu":          round(vals["pct_alu_mean"], 4),
                    "N_SNPs_mean":      round(vals["N_SNPs_mean"], 1),
                    "failed":           tool in FAILED_TOOLS,
                })

    df = pd.DataFrame(all_rows)
    csv_path = os.path.join(RESULTS_DIR, "01_individual_summary.csv")
    df.to_csv(csv_path, index=False)
    print(f"Saved: {csv_path}  ({len(df)} rows)")

    # ---- Print summary table to console -----------------------------------------
    print("\n=== Individual Analysis Summary (STAR, WT, lowest threshold) ===")
    summary = (
        df[(df["condition"] == "WT") & ~df["failed"]]
        .groupby("tool")
        .apply(lambda g: g.nsmallest(1, "threshold"))
        .reset_index(drop=True)[["tool", "threshold", "N_RES_mean", "pct_REDIportal"]]
    )
    print(summary.to_string(index=False))

    print("\n=== Individual Analysis Summary (STAR, ADAR1KO, lowest threshold) ===")
    summary_ko = (
        df[(df["condition"] == "ADAR1KO") & ~df["failed"]]
        .groupby("tool")
        .apply(lambda g: g.nsmallest(1, "threshold"))
        .reset_index(drop=True)[["tool", "threshold", "N_RES_mean", "pct_REDIportal"]]
    )
    print(summary_ko.to_string(index=False))

    # ---- Plot 1: N_RES and %REDIportal vs threshold (WT) ----------------------
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
    fig.suptitle(
        "Individual Sample Analysis — WT condition (STAR aligner)\n"
        "Morales et al. pipeline results",
        fontsize=12, fontweight="bold"
    )

    for tool in TOOL_CONFIGS:
        metrics = tool_results[tool]["WT"]
        thresholds   = sorted(metrics.keys())
        n_res        = [metrics[t]["N_RES_mean"]    for t in thresholds]
        n_res_sem    = [metrics[t]["N_RES_sem"]     for t in thresholds]
        pct_redi     = [metrics[t]["pct_redi_mean"] for t in thresholds]
        pct_redi_sem = [metrics[t]["pct_redi_sem"]  for t in thresholds]

        ls    = "--" if tool in FAILED_TOOLS else "-"
        lw    = 1.5
        label = f"{tool} (FAILED — 0 sites)" if tool in FAILED_TOOLS else tool

        ax1.errorbar(thresholds, n_res, yerr=n_res_sem,
                     color=TOOL_COLORS[tool], linestyle=ls, linewidth=lw,
                     marker="o", markersize=5, label=label, capsize=3)
        ax2.errorbar(thresholds, pct_redi, yerr=pct_redi_sem,
                     color=TOOL_COLORS[tool], linestyle=ls, linewidth=lw,
                     marker="o", markersize=5, label=label, capsize=3)

    ax1.set_xlabel("Threshold (min. supporting reads / P_edit)")
    ax1.set_ylabel("Mean # RES (± SEM across 3 clones)")
    ax1.set_title("Total RES detected")
    ax1.yaxis.set_major_formatter(
        ticker.FuncFormatter(lambda x, _: f"{x/1e3:.0f}K" if x >= 1000 else f"{x:.0f}")
    )
    ax1.legend(fontsize=8)
    ax1.grid(axis="y", alpha=0.3)

    ax2.set_xlabel("Threshold (min. supporting reads / P_edit)")
    ax2.set_ylabel("% RES supported by REDIportal (± SEM)")
    ax2.set_title("REDIportal database support\n(higher = more confident RNA editing sites)")
    ax2.set_ylim(0, 105)
    ax2.legend(fontsize=8)
    ax2.grid(axis="y", alpha=0.3)

    plt.tight_layout()
    plot1_path = os.path.join(RESULTS_DIR, "01_individual_analysis.png")
    plt.savefig(plot1_path, dpi=150, bbox_inches="tight")
    print(f"Saved: {plot1_path}")
    plt.close()

    # ---- Plot 2: WT vs ADAR1KO N_RES side-by-side, for working tools only -----
    working_tools = [t for t in TOOL_CONFIGS if t not in FAILED_TOOLS]
    fig, axes = plt.subplots(1, len(working_tools), figsize=(5 * len(working_tools), 5), sharey=False)
    if len(working_tools) == 1:
        axes = [axes]
    fig.suptitle(
        "Individual Analysis: WT vs ADAR1KO comparison (STAR aligner)\n"
        "Working tools only — SPRINT and RED-ML produced no output",
        fontsize=11, fontweight="bold"
    )

    for ax, tool in zip(axes, working_tools):
        for cond, color, ls in [("WT", "#1565C0", "-"), ("ADAR1KO", "#B71C1C", "--")]:
            metrics   = tool_results[tool][cond]
            thresholds = sorted(metrics.keys())
            n_res     = [metrics[t]["N_RES_mean"] for t in thresholds]
            n_res_sem = [metrics[t]["N_RES_sem"]  for t in thresholds]
            ax.errorbar(thresholds, n_res, yerr=n_res_sem,
                        color=color, linestyle=ls, linewidth=2,
                        marker="o", markersize=5, label=cond, capsize=3)

        ax.set_title(tool)
        ax.set_xlabel("Threshold")
        ax.set_ylabel("Mean # RES")
        ax.yaxis.set_major_formatter(
            ticker.FuncFormatter(lambda x, _: f"{x/1e3:.0f}K" if x >= 1000 else f"{x:.0f}")
        )
        ax.legend(fontsize=9)
        ax.grid(axis="y", alpha=0.3)

    plt.tight_layout()
    plot2_path = os.path.join(RESULTS_DIR, "01_both_conditions.png")
    plt.savefig(plot2_path, dpi=150, bbox_inches="tight")
    print(f"Saved: {plot2_path}")
    plt.close()


if __name__ == "__main__":
    main()
