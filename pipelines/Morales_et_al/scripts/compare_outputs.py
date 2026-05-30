#!/usr/bin/env python3
"""
compare_outputs.py — Intersection-based, output-type-aware tool comparison.

Replaces the single mixed tool_correlation heatmap with:
  1. A co-called edit table (positions called by >= --min-tools tools).
  2. Presence Jaccard / overlap-count matrices across ALL tools.
  3. One correlation TSV+PNG per OUTPUT TYPE, comparing only tools that natively
     produce that quantity (apples-to-apples):
        site_fraction  -> per-site-fraction-correlation
        gene_fraction  -> per-gene-fraction-correlation   (aggregated via --gtf)
        quality_score  -> qual-or-score-correlation
        read_count     -> read-count-correlation
        group_score    -> group-or-comparison-score

All correlations use the INTERSECTION of called sites (a>0 AND b>0) — never the
union — and ship a companion *_noverlap table with the pairwise |A∩B|.

The three matrices written by compare_all_tools.py (fraction/score/coverage) are
row- and column-aligned, so they are read in lockstep chunks; the ~4.5 GB files
are never fully materialised.

Run via:
  module load python3essential
  python3 compare_outputs.py \\
      --matrix-dir results/compare_all_tools \\
      --outdir results/correlation \\
      --aligners star bwa hisat2 \\
      --gtf /path/gencode.v40.annotation.gtf \\
      --edit-type AG --min-tools 2
"""

import argparse
import bisect
import os
import sys
from collections import defaultdict

import numpy as np
import pandas as pd
from scipy.stats import spearmanr


# Output type each tool natively produces. Adding a tool/type is one edit here.
TOOL_OUTPUT_TYPES = {
    "reditools":  {"site_fraction", "gene_fraction", "read_count"},
    "reditools3": {"site_fraction", "gene_fraction", "read_count"},
    "red_ml":     {"site_fraction", "gene_fraction", "quality_score"},
    "redinet":    {"site_fraction", "gene_fraction", "quality_score"},
    "sprint":     {"read_count"},
    "bcftools":   {"quality_score"},
    "jacusa2":    {"group_score"},
}

# Tools that report a true editing fraction (0-1).
FRACTION_TOOLS = {"reditools", "reditools3", "red_ml", "redinet"}

# Output type -> output file stem.
TYPE_PLOT = {
    "site_fraction": "per-site-fraction-correlation",
    "gene_fraction": "per-gene-fraction-correlation",
    "quality_score": "qual-or-score-correlation",
    "read_count":    "read-count-correlation",
    "group_score":   "group-or-comparison-score",
}


# ---------------------------------------------------------------------------
# Streaming load
# ---------------------------------------------------------------------------
def stream_records(matrix_dir, aligners, chunksize=100_000):
    """
    Single lockstep pass over fraction/score/coverage matrices.

    Returns data[(aligner, tool)] -> dict[pos_label] -> (frac, cov, score),
    keeping only positions the tool actually called (score > 0 in >=1 sample).
    """
    paths = {
        "frac":  os.path.join(matrix_dir, "edit_fraction_matrix.tsv"),
        "score": os.path.join(matrix_dir, "tool_score_matrix.tsv"),
        "cov":   os.path.join(matrix_dir, "edit_coverage_matrix.tsv"),
    }
    for name, p in paths.items():
        if not os.path.exists(p):
            sys.exit(f"Matrix not found: {p}")

    readers = {
        k: pd.read_csv(v, sep="\t", index_col=0, chunksize=chunksize)
        for k, v in paths.items()
    }

    data = defaultdict(dict)
    groups = None  # (aligner, tool) -> [sample columns]
    try:
        for fchunk, schunk, cchunk in zip(readers["frac"], readers["score"],
                                          readers["cov"]):
            if groups is None:
                groups = defaultdict(list)
                for col in fchunk.columns:
                    tool = col.split(".")[0]
                    if tool not in TOOL_OUTPUT_TYPES:
                        continue
                    for aligner in aligners:
                        if f".{aligner}." in col:
                            groups[(aligner, tool)].append(col)

            idx = fchunk.index.values
            for key, cols in groups.items():
                s_sub = schunk[cols].to_numpy(dtype=np.float64, na_value=0.0)
                present = (s_sub > 0).any(axis=1)
                if not present.any():
                    continue
                f_mean = fchunk[cols].to_numpy(dtype=np.float64, na_value=0.0).mean(axis=1)
                c_mean = cchunk[cols].to_numpy(dtype=np.float64, na_value=0.0).mean(axis=1)
                s_mean = s_sub.mean(axis=1)
                d = data[key]
                for p, fr, cv, sc in zip(idx[present], f_mean[present],
                                         c_mean[present], s_mean[present]):
                    d[p] = (fr, cv, sc)
    finally:
        for r in readers.values():
            r.close()
    return data


# ---------------------------------------------------------------------------
# Gene mapping (GTF)
# ---------------------------------------------------------------------------
def load_gene_index(gtf_path):
    """Parse gene features into per-chrom sorted (starts, ends, gene_ids)."""
    if not gtf_path or not os.path.exists(gtf_path):
        return None
    tmp = defaultdict(list)
    opener = open
    if gtf_path.endswith(".gz"):
        import gzip
        opener = lambda p: gzip.open(p, "rt")
    with opener(gtf_path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) < 9 or c[2] != "gene":
                continue
            chrom, start, end = c[0], int(c[3]), int(c[4])
            gene_id = ""
            for field in c[8].split(";"):
                field = field.strip()
                if field.startswith("gene_id"):
                    gene_id = field.split('"')[1] if '"' in field else field.split()[-1]
                    break
            tmp[chrom].append((start, end, gene_id or f"{chrom}:{start}"))
    index = {}
    for chrom, rows in tmp.items():
        rows.sort()
        index[chrom] = (
            [r[0] for r in rows],
            [r[1] for r in rows],
            [r[2] for r in rows],
        )
    return index


def pos_to_gene(gene_index, pos_label):
    """Map 'chrom:pos' to the first gene whose interval contains it, else None."""
    chrom, _, pos_s = pos_label.rpartition(":")
    if chrom not in gene_index or not pos_s.isdigit():
        return None
    pos = int(pos_s)
    starts, ends, ids = gene_index[chrom]
    i = bisect.bisect_right(starts, pos) - 1
    while i >= 0 and starts[i] <= pos:
        if ends[i] >= pos:
            return ids[i]
        i -= 1
    return None


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
def jaccard_matrix(site_sets, tools):
    n = len(tools)
    jac = np.full((n, n), np.nan)
    cnt = np.zeros((n, n), dtype=np.int64)
    for i in range(n):
        ai = site_sets[tools[i]]
        jac[i, i] = 1.0 if ai else np.nan
        cnt[i, i] = len(ai)
        for j in range(i + 1, n):
            aj = site_sets[tools[j]]
            inter = len(ai & aj)
            union = len(ai | aj)
            j_val = inter / union if union else np.nan
            jac[i, j] = jac[j, i] = j_val
            cnt[i, j] = cnt[j, i] = inter
    return (pd.DataFrame(jac, index=tools, columns=tools),
            pd.DataFrame(cnt, index=tools, columns=tools))


def intersect_spearman(value_maps, tools):
    """Pairwise Spearman over the intersection (a>0 AND b>0)."""
    n = len(tools)
    corr = np.full((n, n), np.nan)
    nov = np.zeros((n, n), dtype=np.int64)
    for i in range(n):
        corr[i, i] = 1.0
        for j in range(i + 1, n):
            mi, mj = value_maps[tools[i]], value_maps[tools[j]]
            shared = [p for p in (mi.keys() & mj.keys())
                      if mi[p] > 0 and mj[p] > 0]
            nov[i, j] = nov[j, i] = len(shared)
            if len(shared) < 3:
                continue
            a = np.array([mi[p] for p in shared])
            b = np.array([mj[p] for p in shared])
            r, _ = spearmanr(a, b)
            corr[i, j] = corr[j, i] = r
    return (pd.DataFrame(corr, index=tools, columns=tools),
            pd.DataFrame(nov, index=tools, columns=tools))


def plot_heatmap(df, title, out_path, vmin=-1, vmax=1):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return
    fig, ax = plt.subplots(figsize=(max(4, len(df)), max(4, len(df))))
    arr = df.values.astype(float)
    cmap = "viridis" if vmin == 0 else "RdBu_r"
    im = ax.imshow(arr, vmin=vmin, vmax=vmax, cmap=cmap, aspect="auto")
    plt.colorbar(im, ax=ax)
    ax.set_xticks(range(len(df.columns)))
    ax.set_yticks(range(len(df.index)))
    ax.set_xticklabels(df.columns, rotation=45, ha="right")
    ax.set_yticklabels(df.index)
    for i in range(len(df)):
        for j in range(len(df.columns)):
            v = arr[i, j]
            if not np.isnan(v):
                ax.text(j, i, f"{v:.2f}", ha="center", va="center", fontsize=8)
    ax.set_title(title)
    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    plt.close()


# ---------------------------------------------------------------------------
# Value extraction per output type
# ---------------------------------------------------------------------------
def value_for(tool, output_type, record):
    """record = (frac, cov, score) -> scalar value for this output type."""
    frac, cov, score = record
    if output_type in ("site_fraction",):
        return frac
    if output_type in ("quality_score", "group_score"):
        return score
    if output_type == "read_count":
        return frac * cov if tool in ("reditools", "reditools3") else score
    return frac  # unused for gene_fraction (handled separately)


# ---------------------------------------------------------------------------
# Per-aligner driver
# ---------------------------------------------------------------------------
def process_aligner(aligner, data, gene_index, outdir, min_tools):
    tools = sorted(t for (a, t) in data if a == aligner)
    if not tools:
        print(f"  [skip] {aligner}: no tools", file=sys.stderr)
        return

    inter_dir = os.path.join(outdir, "intersect")
    type_dir = os.path.join(outdir, "by_output_type")
    os.makedirs(inter_dir, exist_ok=True)
    os.makedirs(type_dir, exist_ok=True)

    site_sets = {t: set(data[(aligner, t)].keys()) for t in tools}

    # --- All-tool Jaccard / overlap ---
    jac, cnt = jaccard_matrix(site_sets, tools)
    jac.to_csv(os.path.join(inter_dir, f"tool_jaccard_{aligner}.tsv"), sep="\t")
    cnt.to_csv(os.path.join(inter_dir, f"tool_overlap_counts_{aligner}.tsv"), sep="\t")
    plot_heatmap(jac, f"Site Jaccard ({aligner})",
                 os.path.join(inter_dir, f"tool_jaccard_{aligner}.png"), vmin=0, vmax=1)

    # --- Co-called edit table ---
    called_by = defaultdict(list)
    for t in tools:
        for p in site_sets[t]:
            called_by[p].append(t)
    rows = []
    for p, callers in called_by.items():
        if len(callers) < min_tools:
            continue
        chrom, _, pos = p.rpartition(":")
        row = {"chrom": chrom, "pos": pos, "n_tools": len(callers),
               "tools": ",".join(sorted(callers))}
        for t in tools:
            row[t] = (data[(aligner, t)][p][0]
                      if (t in FRACTION_TOOLS and p in data[(aligner, t)])
                      else np.nan)
        rows.append(row)
    cols = ["chrom", "pos", "n_tools", "tools"] + tools
    table = pd.DataFrame(rows, columns=cols)
    if not table.empty:
        table = table.sort_values(["chrom", "pos"])
    table.to_csv(os.path.join(inter_dir, f"edits_intersect_{aligner}.tsv"),
                 sep="\t", index=False)

    # --- Per-output-type correlation ---
    for output_type, stem in TYPE_PLOT.items():
        members = [t for t in tools if output_type in TOOL_OUTPUT_TYPES.get(t, set())]
        corr_path = os.path.join(type_dir, f"{stem}_{aligner}.tsv")
        if len(members) < 2:
            with open(corr_path, "w") as fh:
                only = members[0] if members else "(none)"
                fh.write(f"# {output_type}: only {len(members)} tool(s) ({only}); "
                         f"no pairwise correlation possible.\n")
            print(f"  [stub] {aligner} {output_type}: {len(members)} tool(s)",
                  file=sys.stderr)
            continue

        if output_type == "gene_fraction":
            if gene_index is None:
                with open(corr_path, "w") as fh:
                    fh.write("# gene_fraction skipped: no GTF provided.\n")
                continue
            value_maps = {}
            for t in members:
                agg = defaultdict(lambda: [0.0, 0.0])  # gene -> [sum(frac*cov), sum(cov)]
                for p, (frac, cov, _) in data[(aligner, t)].items():
                    g = pos_to_gene(gene_index, p)
                    if g is None or cov <= 0:
                        continue
                    agg[g][0] += frac * cov
                    agg[g][1] += cov
                value_maps[t] = {g: num / den for g, (num, den) in agg.items() if den > 0}
        else:
            value_maps = {
                t: {p: value_for(t, output_type, rec)
                    for p, rec in data[(aligner, t)].items()}
                for t in members
            }

        corr, nov = intersect_spearman(value_maps, members)
        corr.to_csv(corr_path, sep="\t")
        nov.to_csv(os.path.join(type_dir, f"{stem}_noverlap_{aligner}.tsv"), sep="\t")
        plot_heatmap(corr, f"{stem} ({aligner})",
                     os.path.join(type_dir, f"{stem}_{aligner}.png"))
        print(f"  {aligner} {output_type}: {len(members)} tools", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--matrix-dir", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--aligners", nargs="+", default=["star"])
    ap.add_argument("--gtf", default="")
    ap.add_argument("--edit-type", default="AG",
                    help="Recorded for provenance; matrices are filtered upstream.")
    ap.add_argument("--min-tools", type=int, default=2)
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    print(f"Streaming matrices (edit_type={args.edit_type})...", file=sys.stderr)
    data = stream_records(args.matrix_dir, args.aligners)
    gene_index = load_gene_index(args.gtf)
    if args.gtf and gene_index is None:
        print(f"  [warn] GTF not found: {args.gtf}; gene_fraction will be skipped.",
              file=sys.stderr)

    for aligner in args.aligners:
        process_aligner(aligner, data, gene_index, args.outdir, args.min_tools)


if __name__ == "__main__":
    main()
