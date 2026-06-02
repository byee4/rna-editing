#!/usr/bin/env python3
"""
consensus_characteristics.py — Stratify edit characteristics by tool consensus.

Question this answers
---------------------
For every edited position, count how many tools called it (the *consensus
level*). Then compare the characteristics of:

  * the OUTERSECTION  — sites called by exactly ONE tool (private calls), and
  * the INTERSECTION  — sites called by >=2, >=3, ... up to all tools.

Characteristics compared (per-site AND per-gene):
  coverage   total read depth at the position           (cov)
  fraction   editing fraction 0-1                         (frac)
  score      tool-internal confidence / p-value / QUAL    (score)

For MARINE specifically the upstream matrices already encode its semantics:
"count" (edited reads) and "coverage" (total depth) are folded into
fraction = count/coverage and coverage, matching every other tool.

Score / p-value caveat
----------------------
The score matrix carries each tool's *primary statistic*, whose meaning is
tool-specific (this is documented per tool in the emitted report):
  red_ml    -> P_edit          (a probability / p-value)
  redinet   -> ed_proba        (edited-class probability)
  bcftools  -> QUAL            (phred quality)
  jacusa2*  -> test score
  sprint    -> supporting reads
  reditools/reditools3/marine -> editing fraction (score duplicates fraction)
So "score (if provided)" and "p-value (if provided)" are the same column read
through this per-tool lens; no separate p-value matrix exists upstream.

Anticorrelation diagnostic
--------------------------
Some tools are anticorrelated at the gene level (e.g. red_ml vs MARINE in
per-gene-fraction-correlation_star.png). For every fraction-producing tool
pair this script reports, over their shared genes:
  spearman         the per-gene-fraction Spearman (reproduces the heatmap)
  n_shared_genes   sample size behind that Spearman (often tiny -> unstable)
  site_agreement   mean within-gene Jaccard of the SITES each tool called
  n_sites/gene     how many sites each tool aggregates per gene
and an interpretation: anticorrelation usually arises because the two tools
call DIFFERENT sites inside the same gene (low site_agreement), so their
coverage-weighted gene fractions reflect different underlying positions and
their cross-gene rank ordering inverts.

Reuses the streaming matrix loader and gene index from compare_outputs.py so
the ~GB matrices are never fully materialised.

Run via:
  module load python3essential
  python3 consensus_characteristics.py \\
      --matrix-dir results/compare_all_tools \\
      --outdir results/consensus \\
      --aligners star bwa hisat2 \\
      --gtf /path/gencode.gtf --edit-type AG
"""

import argparse
import os
import sys
from collections import defaultdict
from itertools import combinations

import numpy as np
import pandas as pd
from scipy.stats import spearmanr

# Reuse the streaming loader, gene index, and tool metadata from the sibling
# script rather than duplicating ~120 lines of matrix/GTF parsing.
from compare_outputs import (
    FRACTION_TOOLS,
    load_gene_index,
    pos_to_gene,
    stream_records,
)

# Human-readable meaning of each tool's "score" column, surfaced in the report
# so readers know whether they are looking at a p-value, a probability, or a
# quality score.
SCORE_MEANING = {
    "red_ml":        "P_edit (probability / p-value)",
    "redinet":       "ed_proba (edited-class probability)",
    "bcftools":      "QUAL (phred quality)",
    "jacusa2":       "JACUSA2 test score",
    "jacusa2_call1": "JACUSA2 test score",
    "sprint":        "supporting reads",
    "reditools":     "editing fraction (duplicates fraction)",
    "reditools3":    "editing fraction (duplicates fraction)",
    "marine":        "editing fraction (duplicates fraction)",
}

CHARACTERISTICS = ("coverage", "fraction", "score")


# ---------------------------------------------------------------------------
# Stratum definitions
# ---------------------------------------------------------------------------
def consensus_strata(n_tools):
    """
    Return [(label, predicate)] over a site/gene's consensus level.

    outersection: exactly 1 tool (private). intersection: cumulative >=2 ... >=N.
    """
    strata = [("=1 (outersection)", lambda n: n == 1)]
    for k in range(2, n_tools + 1):
        label = f">={k} (all)" if k == n_tools else f">={k}"
        strata.append((label, (lambda n, k=k: n >= k)))
    return strata


def summarize(values):
    """Return distribution summary dict for a 1-D iterable of floats."""
    a = np.asarray([v for v in values if v is not None and np.isfinite(v)],
                   dtype=np.float64)
    if a.size == 0:
        return dict(n=0, mean=np.nan, median=np.nan, q25=np.nan,
                    q75=np.nan, std=np.nan)
    return dict(
        n=int(a.size),
        mean=float(a.mean()),
        median=float(np.median(a)),
        q25=float(np.percentile(a, 25)),
        q75=float(np.percentile(a, 75)),
        std=float(a.std(ddof=0)),
    )


def char_value(record, characteristic):
    frac, cov, score = record
    return {"coverage": cov, "fraction": frac, "score": score}[characteristic]


# ---------------------------------------------------------------------------
# Per-site stratified characteristics
# ---------------------------------------------------------------------------
def site_characteristics(aligner, data, tools, outdir):
    """
    Long table: for each (tool, stratum, characteristic) summarise the tool's
    own values at sites in that consensus stratum, plus a 'consensus_mean'
    pseudo-tool (site-mean across calling tools) for coverage and fraction.
    """
    site_sets = {t: set(data[(aligner, t)]) for t in tools}
    n_called = defaultdict(int)
    for t in tools:
        for p in site_sets[t]:
            n_called[p] += 1

    strata = consensus_strata(len(tools))
    rows = []

    for label, pred in strata:
        sites_in = {p for p, n in n_called.items() if pred(n)}
        # Per-tool distributions.
        for t in tools:
            d = data[(aligner, t)]
            for ch in CHARACTERISTICS:
                vals = [char_value(d[p], ch) for p in site_sets[t] & sites_in]
                s = summarize(vals)
                rows.append(dict(aligner=aligner, scope="site", stratum=label,
                                 tool=t, characteristic=ch, **s))
        # Aggregate pseudo-tool: per-site mean across calling tools.
        for ch in ("coverage", "fraction"):
            agg = []
            for p in sites_in:
                vals = [char_value(data[(aligner, t)][p], ch)
                        for t in tools if p in site_sets[t]]
                if vals:
                    agg.append(float(np.mean(vals)))
            s = summarize(agg)
            rows.append(dict(aligner=aligner, scope="site", stratum=label,
                             tool="consensus_mean", characteristic=ch, **s))

    df = pd.DataFrame(rows)
    path = os.path.join(outdir, f"site_characteristics_{aligner}.tsv")
    df.to_csv(path, sep="\t", index=False, float_format="%.6g")
    return df, n_called


# ---------------------------------------------------------------------------
# Gene aggregation
# ---------------------------------------------------------------------------
def build_gene_tables(aligner, data, tools, gene_index):
    """
    Return:
      gene_val[t][gene]   = (weighted_fraction, total_coverage, mean_score, n_sites)
      gene_sites[t][gene] = set of position labels the tool called in the gene
    weighted_fraction = sum(frac*cov)/sum(cov) (coverage-weighted), matching
    compare_outputs.py's gene aggregation.
    """
    gene_val = {}
    gene_sites = {}
    for t in tools:
        agg = defaultdict(lambda: [0.0, 0.0, 0.0, 0])  # num, cov, score_sum, n
        sites = defaultdict(set)
        for p, (frac, cov, score) in data[(aligner, t)].items():
            g = pos_to_gene(gene_index, p)
            if g is None or cov <= 0:
                continue
            a = agg[g]
            a[0] += frac * cov
            a[1] += cov
            a[2] += score
            a[3] += 1
            sites[g].add(p)
        gene_val[t] = {g: (num / cov, cov, ssum / n, n)
                       for g, (num, cov, ssum, n) in agg.items() if cov > 0}
        gene_sites[t] = dict(sites)
    return gene_val, gene_sites


def gene_characteristics(aligner, gene_val, tools, outdir):
    """Long table of gene-level characteristics stratified by gene consensus."""
    gene_sets = {t: set(gene_val[t]) for t in tools}
    n_called = defaultdict(int)
    for t in tools:
        for g in gene_sets[t]:
            n_called[g] += 1

    # index into the gene_val tuple per characteristic
    idx = {"fraction": 0, "coverage": 1, "score": 2}
    strata = consensus_strata(len(tools))
    rows = []
    for label, pred in strata:
        genes_in = {g for g, n in n_called.items() if pred(n)}
        for t in tools:
            gv = gene_val[t]
            shared = gene_sets[t] & genes_in
            for ch, i in idx.items():
                vals = [gv[g][i] for g in shared]
                s = summarize(vals)
                rows.append(dict(aligner=aligner, scope="gene", stratum=label,
                                 tool=t, characteristic=ch, **s))
            # how many sites the tool aggregates per gene in this stratum
            nsites = [gv[g][3] for g in shared]
            s = summarize(nsites)
            rows.append(dict(aligner=aligner, scope="gene", stratum=label,
                             tool=t, characteristic="n_sites_per_gene", **s))
    df = pd.DataFrame(rows)
    path = os.path.join(outdir, f"gene_characteristics_{aligner}.tsv")
    df.to_csv(path, sep="\t", index=False, float_format="%.6g")
    return df, n_called


# ---------------------------------------------------------------------------
# Anticorrelation diagnostic (gene-level fraction, fraction tools only)
# ---------------------------------------------------------------------------
def anticorrelation(aligner, gene_val, gene_sites, tools, outdir):
    members = [t for t in tools if t in FRACTION_TOOLS]
    rows = []
    pair_detail = {}  # (a,b) -> per-gene DataFrame, kept for the worst pair
    for a, b in combinations(members, 2):
        va, vb = gene_val[a], gene_val[b]
        shared = sorted(set(va) & set(vb))
        n = len(shared)
        fa = np.array([va[g][0] for g in shared])
        fb = np.array([vb[g][0] for g in shared])
        rho = spearmanr(fa, fb)[0] if n >= 3 else np.nan

        # Within-gene site agreement: do they call the same positions?
        jacc = []
        for g in shared:
            sa, sb = gene_sites[a].get(g, set()), gene_sites[b].get(g, set())
            union = sa | sb
            jacc.append(len(sa & sb) / len(union) if union else np.nan)
        site_agreement = float(np.nanmean(jacc)) if jacc else np.nan
        na = float(np.mean([va[g][3] for g in shared])) if shared else np.nan
        nb = float(np.mean([vb[g][3] for g in shared])) if shared else np.nan

        rows.append(dict(
            aligner=aligner, tool_a=a, tool_b=b,
            spearman=rho, n_shared_genes=n,
            site_agreement=site_agreement,
            n_sites_per_gene_a=na, n_sites_per_gene_b=nb,
            interpretation=_interpret(rho, n, site_agreement),
        ))
        if n >= 1:
            pair_detail[(a, b)] = pd.DataFrame({
                "gene": shared,
                f"frac_{a}": fa, f"frac_{b}": fb,
                f"n_sites_{a}": [va[g][3] for g in shared],
                f"n_sites_{b}": [vb[g][3] for g in shared],
                "site_jaccard": jacc,
            })

    df = pd.DataFrame(rows).sort_values("spearman", na_position="last")
    df.to_csv(os.path.join(outdir, f"anticorrelation_gene_fraction_{aligner}.tsv"),
              sep="\t", index=False, float_format="%.6g")

    # Per-gene detail for the most anticorrelated pair with usable n.
    worst = None
    usable = df[(df["n_shared_genes"] >= 3) & df["spearman"].notna()]
    if not usable.empty:
        r = usable.iloc[0]
        worst = (r["tool_a"], r["tool_b"])
        pair_detail[worst].to_csv(
            os.path.join(outdir, f"anticorrelation_detail_{aligner}.tsv"),
            sep="\t", index=False, float_format="%.6g")
    return df, worst, pair_detail


def _interpret(rho, n, site_agreement):
    if n < 3:
        return f"too few shared genes (n={n}) for Spearman"
    if n < 5:
        base = f"UNSTABLE: only {n} shared genes — Spearman is high-variance"
    else:
        base = ""
    if np.isnan(rho):
        return base or "no correlation computable"
    if rho >= -0.3:
        return base or "not anticorrelated"
    if not np.isnan(site_agreement) and site_agreement < 0.5:
        mech = (f"anticorrelated (rho={rho:.2f}) via DISJOINT sites: the tools "
                f"call different positions within shared genes (mean within-gene "
                f"site Jaccard={site_agreement:.2f}); coverage-weighted gene "
                f"fractions reflect different underlying sites, so cross-gene "
                f"rank ordering inverts")
    else:
        mech = (f"anticorrelated (rho={rho:.2f}) despite shared sites "
                f"(Jaccard={site_agreement:.2f}); fraction-estimation differences")
    return f"{base}; {mech}" if base else mech


# ---------------------------------------------------------------------------
# Plots (best-effort; guarded like the sibling scripts)
# ---------------------------------------------------------------------------
def _plt():
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        return plt
    except ImportError:
        return None


def plot_site_boxplots(aligner, data, tools, n_called, outdir):
    plt = _plt()
    if plt is None:
        return
    site_sets = {t: set(data[(aligner, t)]) for t in tools}
    strata = consensus_strata(len(tools))
    fig, axes = plt.subplots(1, 2, figsize=(max(8, 1.2 * len(strata)), 5))
    for ax, ch in zip(axes, ("coverage", "fraction")):
        box_data, labels = [], []
        for label, pred in strata:
            sites_in = {p for p, n in n_called.items() if pred(n)}
            vals = []
            for p in sites_in:
                tv = [char_value(data[(aligner, t)][p], ch)
                      for t in tools if p in site_sets[t]]
                if tv:
                    vals.append(float(np.mean(tv)))
            box_data.append(vals or [np.nan])
            labels.append(f"{label}\n(n={len(sites_in)})")
        ax.boxplot(box_data, showfliers=False)
        ax.set_xticklabels(labels, rotation=45, ha="right", fontsize=8)
        ax.set_ylabel(f"per-site mean {ch}")
        ax.set_title(f"{ch} vs consensus ({aligner})")
        if ch == "coverage":
            ax.set_yscale("symlog")
    fig.tight_layout()
    fig.savefig(os.path.join(outdir, f"site_characteristics_{aligner}.png"), dpi=150)
    plt.close(fig)


def plot_anticorr_scatter(aligner, worst, pair_detail, outdir):
    plt = _plt()
    if plt is None or worst is None:
        return
    a, b = worst
    df = pair_detail[worst]
    fig, ax = plt.subplots(figsize=(5, 5))
    sc = ax.scatter(df[f"frac_{a}"], df[f"frac_{b}"],
                    c=df["site_jaccard"], cmap="viridis", vmin=0, vmax=1,
                    s=60, edgecolor="k")
    plt.colorbar(sc, ax=ax, label="within-gene site Jaccard")
    ax.set_xlabel(f"{a} gene fraction")
    ax.set_ylabel(f"{b} gene fraction")
    ax.set_title(f"Most anticorrelated gene-fraction pair ({aligner})\n"
                 f"{a} vs {b}")
    fig.tight_layout()
    fig.savefig(os.path.join(outdir, f"anticorrelation_{aligner}.png"), dpi=150)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def write_report(aligner, tools, site_n, gene_n, anti_df, worst, outdir):
    lines = [f"# Consensus characteristics report ({aligner})", ""]
    lines.append(f"Tools present: {', '.join(tools)}")
    lines.append("")
    lines.append("## Consensus distribution")
    site_levels = defaultdict(int)
    for n in site_n.values():
        site_levels[n] += 1
    gene_levels = defaultdict(int)
    for n in gene_n.values():
        gene_levels[n] += 1
    lines.append(f"- Sites by # tools calling: "
                 + ", ".join(f"{k}:{site_levels[k]}" for k in sorted(site_levels)))
    lines.append(f"- Genes by # tools calling: "
                 + ", ".join(f"{k}:{gene_levels[k]}" for k in sorted(gene_levels)))
    n_private = site_levels.get(1, 0)
    n_total = sum(site_levels.values())
    if n_total:
        lines.append(f"- Outersection (private) sites: {n_private}/{n_total} "
                     f"({100 * n_private / n_total:.1f}%)")
    lines.append("")
    lines.append("## Score column meaning (per tool)")
    for t in tools:
        lines.append(f"- {t}: {SCORE_MEANING.get(t, 'tool score')}")
    lines.append("")
    lines.append("## Gene-fraction anticorrelation")
    if anti_df is None or anti_df.empty:
        lines.append("No fraction-tool pairs available.")
    else:
        anti = anti_df[anti_df["spearman"].notna()].copy()
        neg = anti[anti["spearman"] < -0.3]
        if neg.empty:
            lines.append("No tool pair is anticorrelated (Spearman < -0.3).")
        else:
            lines.append("Anticorrelated pairs (Spearman < -0.3):")
            for _, r in neg.iterrows():
                lines.append(f"- **{r['tool_a']} vs {r['tool_b']}**: "
                             f"rho={r['spearman']:.2f}, "
                             f"n_shared_genes={int(r['n_shared_genes'])}, "
                             f"site_agreement={r['site_agreement']:.2f} — "
                             f"{r['interpretation']}")
        if worst is not None:
            lines.append("")
            lines.append(f"Most anticorrelated usable pair: {worst[0]} vs {worst[1]} "
                         f"(see anticorrelation_detail_{aligner}.tsv and "
                         f"anticorrelation_{aligner}.png).")
    lines.append("")
    with open(os.path.join(outdir, f"consensus_report_{aligner}.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
def process_aligner(aligner, data, gene_index, outdir):
    tools = sorted(t for (a, t) in data if a == aligner)
    if not tools:
        print(f"  [skip] {aligner}: no tools", file=sys.stderr)
        # Emit empty stubs so Snakemake outputs exist.
        for stem in ("site_characteristics", "gene_characteristics",
                     "anticorrelation_gene_fraction"):
            open(os.path.join(outdir, f"{stem}_{aligner}.tsv"), "w").close()
        open(os.path.join(outdir, f"consensus_report_{aligner}.md"), "w").close()
        return

    _, site_n = site_characteristics(aligner, data, tools, outdir)

    if gene_index is None:
        # Gene-level analysis needs a GTF; write stubs and a note.
        for stem in ("gene_characteristics", "anticorrelation_gene_fraction"):
            with open(os.path.join(outdir, f"{stem}_{aligner}.tsv"), "w") as fh:
                fh.write("# gene-level analysis skipped: no GTF provided.\n")
        gene_n, anti_df, worst = {}, None, None
    else:
        gene_val, gene_sites = build_gene_tables(aligner, data, tools, gene_index)
        _, gene_n = gene_characteristics(aligner, gene_val, tools, outdir)
        anti_df, worst, pair_detail = anticorrelation(
            aligner, gene_val, gene_sites, tools, outdir)
        plot_anticorr_scatter(aligner, worst, pair_detail, outdir)

    plot_site_boxplots(aligner, data, tools, site_n, outdir)
    write_report(aligner, tools, site_n, gene_n, anti_df, worst, outdir)
    print(f"  {aligner}: {len(tools)} tools, "
          f"{len(site_n)} sites analysed", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--matrix-dir", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--aligners", nargs="+", default=["star"])
    ap.add_argument("--gtf", default="")
    ap.add_argument("--edit-type", default="AG",
                    help="Recorded for provenance; matrices are filtered upstream.")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    print(f"Streaming matrices (edit_type={args.edit_type})...", file=sys.stderr)
    data = stream_records(args.matrix_dir, args.aligners)
    gene_index = load_gene_index(args.gtf)
    if args.gtf and gene_index is None:
        print(f"  [warn] GTF not found: {args.gtf}; gene-level analysis skipped.",
              file=sys.stderr)

    for aligner in args.aligners:
        process_aligner(aligner, data, gene_index, args.outdir)


if __name__ == "__main__":
    main()
