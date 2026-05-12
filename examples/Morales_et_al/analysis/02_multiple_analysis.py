"""
02_multiple_analysis.py
=======================
Analyze merged-replicate (multiple) RNA editing site detection results from
the Morales et al. pipeline and compare to the benchmark paper (Figure 2,
Table 2):

  Morales et al. (2023) "A Benchmark of RNA Editing Detection Tools"
  PMC10527054 — https://pmc.ncbi.nlm.nih.gov/articles/PMC10527054/

In the "multiple" analysis, all three biological clones per condition are
merged before calling RNA editing sites. This reduces noise and improves
the confidence of each site, at the cost of lower total site counts.

Data source:
  ../Benchmark-of-RNA-Editing-Detection-Tools/Data_*-Multiple.json
  Each JSON is indexed as:
    data[aligner][condition][threshold] = {N_res, N_db, N_Alu}
  (Note: no per-clone level — single merged result per condition)

JACUSA2 does not have a separate multiple-analysis JSON because it already
takes all replicates jointly as input (Data_JACUSA2.json).

Key metric — ADAR1KO/WT ratio:
  A lower ratio means the tool more specifically detects ADAR1-dependent
  editing (true sites lost in KO). A high ratio (approaching 100%) suggests
  the tool detects many background variants that persist regardless of ADAR1.
  BCFtools ratio > 100% indicates it detects more variants in ADAR1KO than WT,
  consistent with it being a generic variant caller (not RNA-editing specific).

Outputs (written to ./results/):
  02_multiple_summary.csv       — per-tool, per-condition, per-threshold stats
  02_ko_wt_ratio.csv            — ADAR1KO/WT ratios at each threshold
  02_multiple_analysis.png      — N_RES, %REDIportal, ADAR1KO/WT ratio plots
"""

import json
import os

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR    = os.path.dirname(os.path.abspath(__file__))
MORALES_DIR   = os.path.dirname(SCRIPT_DIR)
BENCHMARK_DIR = os.path.join(MORALES_DIR, "Benchmark-of-RNA-Editing-Detection-Tools")
RESULTS_DIR   = os.path.join(SCRIPT_DIR, "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

ALIGNER    = "star"
CONDITIONS = ["WT", "ADAR1KO"]

# Tool name -> (json filename, x-axis label)
# Keys in the Multiple JSONs use N_res / N_db (lowercase) rather than N_RES / N_REDIportal
MULTIPLE_TOOLS = {
    "REDItools2": ("Data_REDItools2-Multiple.json", "Min. supporting reads"),
    "BCFtools":   ("Data_BCFTools-Multiple.json",   "MAF threshold"),
    "SPRINT":     ("Data_SPRINT-Multiple.json",     "Min. supporting reads"),
    "RED-ML":     ("Data_REDML-Multiple.json",      "Min. P_edit"),
}

# JACUSA2 individual JSON is also used for the joint analysis
JACUSA2_JSON   = "Data_JACUSA2.json"

FAILED_TOOLS   = {"SPRINT", "RED-ML"}

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


def extract_multiple_metrics(data: dict, condition: str) -> dict:
    """
    Extract metrics from a multiple-analysis JSON.
    Returns {float(threshold): {N_res, pct_db, pct_alu}}.
    """
    condition_data = data[ALIGNER][condition]
    thresholds = sorted(condition_data.keys(), key=lambda x: float(x))

    results = {}
    for t in thresholds:
        entry = condition_data[t]
        # Multiple JSONs use lowercase keys: N_res, N_db, N_Alu
        n_res = entry.get("N_res", entry.get("N_RES", 0))
        n_db  = entry.get("N_db",  entry.get("N_REDIportal", 0))
        n_alu = entry.get("N_Alu", 0)
        results[float(t)] = {
            "N_res":   n_res,
            "pct_db":  100 * n_db  / n_res if n_res > 0 else 0.0,
            "pct_alu": 100 * n_alu / n_res if n_res > 0 else 0.0,
        }
    return results


# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

def main():
    all_rows = []
    tool_results = {}   # tool -> condition -> {threshold -> metrics}

    # ---- Load multiple-analysis tools ----------------------------------------
    for tool, (json_file, thresh_label) in MULTIPLE_TOOLS.items():
        json_path = os.path.join(BENCHMARK_DIR, json_file)
        data = load_json(json_path)
        tool_results[tool] = {}

        for condition in CONDITIONS:
            metrics = extract_multiple_metrics(data, condition)
            tool_results[tool][condition] = metrics

            for threshold, vals in metrics.items():
                all_rows.append({
                    "tool":          tool,
                    "condition":     condition,
                    "threshold":     threshold,
                    "N_res":         vals["N_res"],
                    "pct_REDIportal": round(vals["pct_db"],  2),
                    "pct_Alu":       round(vals["pct_alu"], 4),
                    "failed":        tool in FAILED_TOOLS,
                })

    # ---- Load JACUSA2 (uses individual JSON, already joint analysis) ----------
    jacusa2_data = load_json(os.path.join(BENCHMARK_DIR, JACUSA2_JSON))
    tool_results["JACUSA2"] = {}
    for condition in CONDITIONS:
        cond_data  = jacusa2_data[ALIGNER][condition]
        thresholds = sorted(cond_data.keys(), key=lambda x: float(x))
        metrics    = {}
        for t in thresholds:
            entry  = cond_data[t]
            n_res  = entry.get("N_RES", 0)
            n_redi = entry.get("N_REDIportal", 0)
            n_alu  = entry.get("N_Alu", 0)
            metrics[float(t)] = {
                "N_res":   n_res,
                "pct_db":  100 * n_redi / n_res if n_res > 0 else 0.0,
                "pct_alu": 100 * n_alu  / n_res if n_res > 0 else 0.0,
            }
            all_rows.append({
                "tool":          "JACUSA2",
                "condition":     condition,
                "threshold":     float(t),
                "N_res":         n_res,
                "pct_REDIportal": round(100 * n_redi / n_res if n_res > 0 else 0.0, 2),
                "pct_Alu":       round(100 * n_alu  / n_res if n_res > 0 else 0.0, 4),
                "failed":        False,
            })
        tool_results["JACUSA2"][condition] = metrics

    # ---- Save summary CSV ---------------------------------------------------
    df = pd.DataFrame(all_rows)
    csv_path = os.path.join(RESULTS_DIR, "02_multiple_summary.csv")
    df.to_csv(csv_path, index=False)
    print(f"Saved: {csv_path}  ({len(df)} rows)")

    # ---- Compute ADAR1KO/WT ratios ------------------------------------------
    ratio_rows = []
    all_tools  = list(MULTIPLE_TOOLS.keys()) + ["JACUSA2"]

    for tool in all_tools:
        wt_metrics  = tool_results[tool]["WT"]
        ko_metrics  = tool_results[tool]["ADAR1KO"]
        # JACUSA2: WT and ADAR1KO are identical (joint analysis) — ratio = 100%
        for t in sorted(wt_metrics.keys()):
            n_wt = wt_metrics[t]["N_res"]
            n_ko = ko_metrics[t]["N_res"]
            ratio = 100 * n_ko / n_wt if n_wt > 0 else float("nan")
            ratio_rows.append({
                "tool":        tool,
                "threshold":   t,
                "N_WT":        n_wt,
                "N_ADAR1KO":   n_ko,
                "ratio_pct":   round(ratio, 2),
                "failed":      tool in FAILED_TOOLS,
                "note": (
                    "Joint analysis — ratio not meaningful"
                    if tool == "JACUSA2" else ""
                ),
            })

    ratio_df = pd.DataFrame(ratio_rows)
    ratio_csv = os.path.join(RESULTS_DIR, "02_ko_wt_ratio.csv")
    ratio_df.to_csv(ratio_csv, index=False)
    print(f"Saved: {ratio_csv}")

    # ---- Print ratio table for working tools ---------------------------------
    print("\n=== ADAR1KO/WT ratio (merged replicates, STAR, lowest threshold) ===")
    print("Lower ratio = tool more specific to ADAR1-dependent editing")
    print("Ratio > 100% = tool detects more background variants in KO than WT\n")
    lowest = (
        ratio_df.dropna(subset=["ratio_pct"])
        .groupby("tool")
        .apply(lambda g: g.nsmallest(1, "threshold"))
        .reset_index(drop=True)[["tool", "threshold", "N_WT", "N_ADAR1KO", "ratio_pct", "note"]]
    )
    print(lowest.to_string(index=False))

    # ---- Plots ---------------------------------------------------------------
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    fig.suptitle(
        "Merged Replicate (Multiple) Analysis — STAR aligner\n"
        "Morales et al. pipeline results",
        fontsize=12, fontweight="bold"
    )
    ax_nres, ax_redi, ax_ratio = axes

    all_plot_tools = list(MULTIPLE_TOOLS.keys()) + ["JACUSA2"]

    for tool in all_plot_tools:
        wt_metrics  = tool_results[tool]["WT"]
        ko_metrics  = tool_results[tool]["ADAR1KO"]
        thresholds  = sorted(wt_metrics.keys())

        n_res_wt   = [wt_metrics[t]["N_res"]  for t in thresholds]
        pct_redi_wt = [wt_metrics[t]["pct_db"] for t in thresholds]
        ratios = []
        for t in thresholds:
            n_wt = wt_metrics[t]["N_res"]
            n_ko = ko_metrics[t]["N_res"]
            ratios.append(100 * n_ko / n_wt if n_wt > 0 else np.nan)

        ls    = "--" if tool in FAILED_TOOLS else "-"
        lw    = 1.5
        label = f"{tool} (FAILED)" if tool in FAILED_TOOLS else tool

        ax_nres.plot(thresholds, n_res_wt, color=TOOL_COLORS[tool],
                     linestyle=ls, linewidth=lw, marker="o", markersize=5, label=label)
        ax_redi.plot(thresholds, pct_redi_wt, color=TOOL_COLORS[tool],
                     linestyle=ls, linewidth=lw, marker="o", markersize=5, label=label)

        # Only plot ratio for non-JACUSA2, non-failed tools
        if tool not in FAILED_TOOLS and tool != "JACUSA2":
            ax_ratio.plot(thresholds, ratios, color=TOOL_COLORS[tool],
                          linestyle="-", linewidth=2, marker="o", markersize=5, label=tool)

    # Paper-reported ratios at threshold=2 (STAR aligner, Table 2)
    paper_ratios = {"REDItools2": 63.91}
    for tool, paper_val in paper_ratios.items():
        ax_ratio.axhline(paper_val, color=TOOL_COLORS[tool], linestyle=":",
                         linewidth=1.5, alpha=0.7,
                         label=f"{tool} (paper: {paper_val}%)")

    ax_nres.set_xlabel("Threshold")
    ax_nres.set_ylabel("# RES (merged replicates)")
    ax_nres.set_title("Total RES (WT)")
    ax_nres.yaxis.set_major_formatter(
        ticker.FuncFormatter(lambda x, _: f"{x/1e3:.0f}K" if x >= 1000 else f"{x:.0f}")
    )
    ax_nres.legend(fontsize=8)
    ax_nres.grid(axis="y", alpha=0.3)

    ax_redi.set_xlabel("Threshold")
    ax_redi.set_ylabel("% RES in REDIportal")
    ax_redi.set_title("REDIportal database support (WT)")
    ax_redi.set_ylim(0, 105)
    ax_redi.legend(fontsize=8)
    ax_redi.grid(axis="y", alpha=0.3)

    ax_ratio.set_xlabel("Threshold")
    ax_ratio.set_ylabel("ADAR1KO / WT (%)")
    ax_ratio.set_title(
        "ADAR1KO/WT site count ratio\n"
        "(lower = more ADAR1-specific; dotted = paper value)"
    )
    ax_ratio.axhline(100, color="gray", linestyle=":", linewidth=1, alpha=0.5,
                     label="100% reference")
    ax_ratio.legend(fontsize=8)
    ax_ratio.grid(axis="y", alpha=0.3)

    plt.tight_layout()
    plot_path = os.path.join(RESULTS_DIR, "02_multiple_analysis.png")
    plt.savefig(plot_path, dpi=150, bbox_inches="tight")
    print(f"Saved: {plot_path}")
    plt.close()


if __name__ == "__main__":
    main()
