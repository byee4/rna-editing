#!/usr/bin/env python3
"""
tool_correlation.py — Pairwise Spearman correlation between RNA editing tools.

For each aligner, loads the edit_fraction_matrix.tsv produced by
compare_all_tools.py and computes pairwise Spearman r between tools,
collapsing across all samples of that aligner.

Outputs (in --outdir):
  tool_correlation_{aligner}.tsv     n_tools × n_tools correlation matrix
  tool_correlation_{aligner}.png     heatmap (if matplotlib available)

Run via:
  module load python3essential
  python3 tool_correlation.py \\
      --matrix-dir results/compare_all_tools/ \\
      --outdir results/correlation/ \\
      --aligners star bwa hisat2
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


def aligner_tool_matrix(df, aligner):
    """
    For one aligner: average columns across samples that share the same tool,
    returning a DataFrame of positions × tools.
    """
    # Columns: {tool}.{aligner}.{condition}_{sample}
    aligner_cols = [c for c in df.columns if f".{aligner}." in c]
    if not aligner_cols:
        return None
    # Group by tool name (first segment)
    tool_groups = {}
    for col in aligner_cols:
        tool = col.split(".")[0]
        tool_groups.setdefault(tool, []).append(col)
    # Average each tool's columns
    result = {}
    for tool, cols in tool_groups.items():
        result[tool] = df[cols].mean(axis=1)
    return pd.DataFrame(result)


def compute_correlation(tool_df):
    """
    Pairwise Spearman r between tool columns.
    Returns a DataFrame (tools × tools).
    """
    tools = tool_df.columns.tolist()
    n = len(tools)
    corr = np.ones((n, n))
    for i in range(n):
        for j in range(i + 1, n):
            a = tool_df.iloc[:, i].values
            b = tool_df.iloc[:, j].values
            # Only use positions where both tools have nonzero values
            mask = (a > 0) | (b > 0)
            if mask.sum() < 3:
                r = np.nan
            else:
                r, _ = spearmanr(a[mask], b[mask])
            corr[i, j] = corr[j, i] = r
    return pd.DataFrame(corr, index=tools, columns=tools)


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
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    df = load_matrix(args.matrix_dir, "edit_fraction_matrix.tsv")

    for aligner in args.aligners:
        tool_df = aligner_tool_matrix(df, aligner)
        if tool_df is None or tool_df.shape[1] < 2:
            print(f"  [skip] {aligner}: fewer than 2 tools found", file=sys.stderr)
            continue
        print(f"  {aligner}: {tool_df.shape[1]} tools, {tool_df.shape[0]} positions",
              file=sys.stderr)

        corr_df = compute_correlation(tool_df)
        tsv_out = os.path.join(args.outdir, f"tool_correlation_{aligner}.tsv")
        corr_df.to_csv(tsv_out, sep="\t")
        print(f"  Wrote {tsv_out}", file=sys.stderr)

        png_out = os.path.join(args.outdir, f"tool_correlation_{aligner}.png")
        plot_heatmap(corr_df, f"Tool correlation ({aligner})", png_out)


if __name__ == "__main__":
    main()
