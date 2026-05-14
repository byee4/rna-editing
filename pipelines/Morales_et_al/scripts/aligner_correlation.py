#!/usr/bin/env python3
"""
aligner_correlation.py — Pairwise Spearman correlation between aligners.

For each tool, loads the edit_fraction_matrix.tsv and computes pairwise
Spearman r between aligners, collapsing across samples.

Outputs (in --outdir):
  aligner_correlation_{tool}.tsv     n_aligners × n_aligners matrix
  aligner_correlation_{tool}.png     heatmap (if matplotlib available)

Run via:
  module load python3essential
  python3 aligner_correlation.py \\
      --matrix-dir results/compare_all_tools/ \\
      --outdir results/correlation/ \\
      --aligners star bwa hisat2 \\
      --tools reditools sprint red_ml reditools3 redinet marine
"""

import argparse
import os
import sys

import numpy as np
import pandas as pd
from scipy.stats import spearmanr


def load_matrix(matrix_dir, filename):
    path = os.path.join(matrix_dir, filename)
    if not os.path.exists(path):
        sys.exit(f"Matrix not found: {path}")
    return pd.read_csv(path, sep="\t", index_col=0)


def tool_aligner_matrix(df, tool):
    """
    For one tool: average columns across samples that share the same aligner,
    returning a DataFrame of positions × aligners.
    """
    # Columns: {tool}.{aligner}.{condition}_{sample}
    tool_cols = [c for c in df.columns if c.startswith(f"{tool}.")]
    if not tool_cols:
        return None
    # Group by aligner (second segment)
    aligner_groups = {}
    for col in tool_cols:
        parts = col.split(".")
        if len(parts) < 3:
            continue
        aligner = parts[1]
        aligner_groups.setdefault(aligner, []).append(col)
    if len(aligner_groups) < 2:
        return None
    result = {}
    for aligner, cols in aligner_groups.items():
        result[aligner] = df[cols].mean(axis=1)
    return pd.DataFrame(result)


def compute_correlation(aligner_df):
    aligners = aligner_df.columns.tolist()
    n = len(aligners)
    corr = np.ones((n, n))
    for i in range(n):
        for j in range(i + 1, n):
            a = aligner_df.iloc[:, i].values
            b = aligner_df.iloc[:, j].values
            mask = (a > 0) | (b > 0)
            if mask.sum() < 3:
                r = np.nan
            else:
                r, _ = spearmanr(a[mask], b[mask])
            corr[i, j] = corr[j, i] = r
    return pd.DataFrame(corr, index=aligners, columns=aligners)


def plot_heatmap(corr_df, title, out_path):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return
    fig, ax = plt.subplots(figsize=(max(4, len(corr_df)), max(4, len(corr_df))))
    data = corr_df.values.astype(float)
    im = ax.imshow(data, vmin=-1, vmax=1, cmap="RdBu_r", aspect="auto")
    plt.colorbar(im, ax=ax, label="Spearman r")
    ax.set_xticks(range(len(corr_df.columns)))
    ax.set_yticks(range(len(corr_df.index)))
    ax.set_xticklabels(corr_df.columns, rotation=45, ha="right")
    ax.set_yticklabels(corr_df.index)
    for i in range(len(corr_df)):
        for j in range(len(corr_df.columns)):
            v = data[i, j]
            if not np.isnan(v):
                ax.text(j, i, f"{v:.2f}", ha="center", va="center",
                        fontsize=8, color="black" if abs(v) < 0.7 else "white")
    ax.set_title(title)
    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    plt.close()
    print(f"  Wrote {out_path}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--matrix-dir", required=True,
                    help="Directory with edit_fraction_matrix.tsv")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--aligners", nargs="+", default=["star"])
    ap.add_argument("--tools", nargs="+",
                    default=["reditools", "sprint", "red_ml",
                             "reditools3", "redinet", "marine"])
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    df = load_matrix(args.matrix_dir, "edit_fraction_matrix.tsv")

    for tool in args.tools:
        aligner_df = tool_aligner_matrix(df, tool)
        if aligner_df is None:
            print(f"  [skip] {tool}: fewer than 2 aligners found", file=sys.stderr)
            continue
        print(f"  {tool}: {aligner_df.shape[1]} aligners, {aligner_df.shape[0]} positions",
              file=sys.stderr)

        corr_df = compute_correlation(aligner_df)
        tsv_out = os.path.join(args.outdir, f"aligner_correlation_{tool}.tsv")
        corr_df.to_csv(tsv_out, sep="\t")
        print(f"  Wrote {tsv_out}", file=sys.stderr)

        png_out = os.path.join(args.outdir, f"aligner_correlation_{tool}.png")
        plot_heatmap(corr_df, f"Aligner correlation ({tool})", png_out)


if __name__ == "__main__":
    main()
