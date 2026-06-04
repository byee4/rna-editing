#!/usr/bin/env python3
"""
compare_all_tools.py — Build position × sample matrices from all RNA editing tools.

Outputs (in --outdir, gzip-compressed):
  edit_coverage_matrix.tsv.gz   read depth at each edited position per sample/tool
  edit_fraction_matrix.tsv.gz   editing fraction (0–1) at each position
  tool_score_matrix.tsv.gz      tool-internal confidence score at each position

Columns are named  {tool}.{aligner}.{condition}_{sample}.
Rows are genomic positions  {chrom}:{pos}  (1-based, as reported by each tool).
Missing values are imputed as 0.

Run via:
  module load python3essential
  python3 compare_all_tools.py --results-dir results/ --outdir results/compare_all_tools/ \
      --aligners star bwa hisat2 --conditions WT ADAR1KO --samples clone1 clone2 clone3
"""

import argparse
import glob
import os
import subprocess
import sys

import numpy as np


# Substitution classes kept by the parsers. Default is A->I (AG) plus its
# reverse-strand complement (TC); overridden by --edit-type in main().
def edit_type_set(edit_type):
    """Return {edit, reverse-complement} in both 'AG' and 'A>G' notations."""
    comp = {"A": "T", "T": "A", "G": "C", "C": "G"}
    et = edit_type.upper()
    rc = comp[et[0]] + comp[et[1]]
    return {et, rc, f"{et[0]}>{et[1]}", f"{rc[0]}>{rc[1]}"}


EDIT_TYPES = edit_type_set("AG")

# How JACUSA2 call-1 sites are filtered (set from --jacusa2-call1-filter in main()):
#   "edit_type"  reditools-style — keep only sites whose ref->alt is in EDIT_TYPES
#   "unfiltered" JACUSA2-style   — keep every site JACUSA2 call-1 reported
JACUSA2_CALL1_FILTER = "edit_type"


# ---------------------------------------------------------------------------
# Per-tool parsers
# Each returns dict[(chrom, pos_str)] -> (coverage, fraction, score)
# ---------------------------------------------------------------------------

def _open(path):
    import gzip
    return gzip.open(path, "rt") if path.endswith(".gz") else open(path)


def parse_reditools2(filepath):
    """
    REDItools2 output: tab-delimited, no header.
    Cols: Region Position Reference Strand Coverage-q30 MeanQ BaseCount AllSubs Frequency ...
    """
    sites = {}
    if not os.path.exists(filepath) or os.path.getsize(filepath) == 0:
        return sites
    with _open(filepath) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) < 9:
                continue
            edit_type = c[7]
            if edit_type not in EDIT_TYPES:
                continue
            try:
                cov = float(c[4])
                frac = float(c[8])
            except ValueError:
                continue
            sites[(c[0], c[1])] = (cov, frac, frac)
    return sites


def parse_reditools3(filepath):
    """
    REDItools3 (reditools analyze) output: tab-delimited.
    Tries REDItools2 column layout first; falls back to header-based parsing.
    """
    sites = {}
    if not os.path.exists(filepath) or os.path.getsize(filepath) == 0:
        return sites
    with _open(filepath) as fh:
        header = None
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            # Detect header row
            if header is None and c[0].lower() in ("region", "chrom", "#region"):
                header = [x.lower().strip("#") for x in c]
                continue
            if header is not None:
                row = dict(zip(header, c))
                edit_type = row.get("allsubs", row.get("type", ""))
                if edit_type not in EDIT_TYPES:
                    continue
                try:
                    cov = float(row.get("coverage-q30", row.get("coverage", 0)))
                    frac = float(row.get("frequency", 0))
                    chrom = row.get("region", row.get("chrom", c[0]))
                    pos = row.get("position", c[1])
                except (ValueError, KeyError):
                    continue
                sites[(chrom, pos)] = (cov, frac, frac)
            else:
                # No header — assume same layout as REDItools2
                if len(c) < 9:
                    continue
                if c[7] not in EDIT_TYPES:
                    continue
                try:
                    cov = float(c[4])
                    frac = float(c[8])
                except ValueError:
                    continue
                sites[(c[0], c[1])] = (cov, frac, frac)
    return sites


def parse_sprint(dirpath):
    """
    SPRINT output directory; reads SPRINT_identified_regular.res.
    Cols: Chr Start End Type SupportingReads Strand Ref Alt Category Coverage Freq
    """
    sites = {}
    res_file = os.path.join(dirpath, "SPRINT_identified_regular.res")
    if not os.path.exists(res_file):
        return sites
    with _open(res_file) as fh:
        for line in fh:
            if not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) < 5:
                continue
            edit_type = c[3] if len(c) > 3 else ""
            if edit_type not in EDIT_TYPES:
                continue
            chrom, pos = c[0], c[2]
            try:
                sup = float(c[4])
                cov = float(c[9]) if len(c) > 9 else sup
                frac = float(c[10]) if len(c) > 10 else 0.0
            except ValueError:
                continue
            sites[(chrom, pos)] = (cov, frac, sup)
    return sites


def parse_red_ml(dirpath):
    """
    RED-ML output directory; reads RNA_editing.sites.txt.
    Cols: #Chromosome Position Read_depth Reference Reference_support_reads
          Alternative Alternative_support_reads P_edit
    Coverage is Read_depth; RED-ML emits no fraction column, so it is computed
    as Alternative_support_reads / Read_depth. Score is P_edit.
    """
    sites = {}
    txt = os.path.join(dirpath, "RNA_editing.sites.txt")
    if not os.path.exists(txt):
        return sites
    with _open(txt) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) < 8:
                continue
            ref, alt = c[3], c[5]
            edit_type = ref + alt
            if edit_type not in EDIT_TYPES:
                continue
            try:
                cov = float(c[2])
                alt_support = float(c[6])
                score = float(c[7])
            except ValueError:
                continue
            frac = alt_support / cov if cov else 0.0
            sites[(c[0], c[1])] = (cov, frac, score)
    return sites


def parse_bcftools(bcf_path):
    """
    BCFtools BCF output — convert to VCF via bcftools view subprocess,
    then parse REF→ALT at each site.
    Coverage and fraction not easily available; use QUAL as score.
    Falls back gracefully if bcftools not in PATH.
    """
    sites = {}
    if not os.path.exists(bcf_path):
        return sites
    try:
        proc = subprocess.run(
            ["bcftools", "view", bcf_path],
            capture_output=True, text=True, check=True
        )
        vcf_lines = proc.stdout.splitlines()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return sites
    for line in vcf_lines:
        if line.startswith("#") or not line.strip():
            continue
        c = line.split("\t")
        if len(c) < 8:
            continue
        chrom, pos, ref, alt = c[0], c[1], c[3], c[4]
        edit_type = ref + alt
        if edit_type not in EDIT_TYPES:
            continue
        try:
            score = float(c[5]) if c[5] != "." else 0.0
        except ValueError:
            score = 0.0
        # Try to get DP from INFO
        cov = 0.0
        for field in c[7].split(";"):
            if field.startswith("DP="):
                try:
                    cov = float(field[3:])
                except ValueError:
                    pass
        sites[(chrom, pos)] = (cov, 0.0, score)
    return sites


def parse_jacusa2(filepath):
    """
    JACUSA2 output: tab-delimited, ## header lines, # column-header line.
    Cols: contig start end name score strand ref bases11 bases12 ... info filter
    Returns positions with (0, 0, score) — JACUSA2 compares groups, no per-sample cov/frac.
    """
    sites = {}
    if not os.path.exists(filepath) or os.path.getsize(filepath) == 0:
        return sites
    header = None
    with _open(filepath) as fh:
        for line in fh:
            if line.startswith("##"):
                continue
            if line.startswith("#"):
                header = line.lstrip("#").rstrip("\n").split("\t")
                continue
            if header is None:
                continue
            c = line.rstrip("\n").split("\t")
            row = dict(zip(header, c))
            chrom = row.get("contig", c[0] if c else "")
            pos = str(int(row.get("start", c[1] if len(c) > 1 else 0)) + 1)
            try:
                score = float(row.get("score", c[4] if len(c) > 4 else 0))
            except ValueError:
                score = 0.0
            if chrom and pos:
                sites[(chrom, pos)] = (0.0, 0.0, score)
    return sites


def parse_jacusa2_call1(filepath):
    """
    JACUSA2 call-1 output (one condition vs the reference genome): BED6 plus
    method-specific columns. Relevant columns: contig start end name score strand
    ref bases11 ... where bases11 holds comma-separated A,C,G,T counts for the
    single sample. Unlike call-2 (group contrast), this yields per-site coverage
    (sum of counts) and editing fraction (alt/coverage), so call-1 is comparable
    to the other per-sample tools. When JACUSA2_CALL1_FILTER == "edit_type" only
    sites whose ref->alt is in EDIT_TYPES are kept (reditools-style); "unfiltered"
    keeps every site JACUSA2 reported (JACUSA2-style).
    """
    base_index = {"A": 0, "C": 1, "G": 2, "T": 3}
    sites = {}
    if not os.path.exists(filepath) or os.path.getsize(filepath) == 0:
        return sites
    header = None
    with _open(filepath) as fh:
        for line in fh:
            if line.startswith("##"):
                continue
            if line.startswith("#"):
                header = line.lstrip("#").rstrip("\n").split("\t")
                continue
            if header is None:
                continue
            c = line.rstrip("\n").split("\t")
            row = dict(zip(header, c))
            ref = row.get("ref", "").upper()
            bases = row.get("bases11", "")
            if ref not in base_index or "," not in bases:
                continue
            try:
                counts = [float(x) for x in bases.split(",")]
            except ValueError:
                continue
            if len(counts) < 4:
                continue
            cov = sum(counts[:4])
            if cov <= 0:
                continue
            ref_i = base_index[ref]
            alt_i = max((i for i in range(4) if i != ref_i), key=lambda i: counts[i])
            if JACUSA2_CALL1_FILTER == "edit_type" and (ref + "ACGT"[alt_i]) not in EDIT_TYPES:
                continue
            frac = counts[alt_i] / cov
            try:
                score = float(row.get("score", c[4] if len(c) > 4 else 0))
            except ValueError:
                score = 0.0
            try:
                pos = str(int(row.get("start", c[1])) + 1)
            except (ValueError, IndexError):
                continue
            sites[(row.get("contig", c[0] if c else ""), pos)] = (cov, frac, score)
    return sites


def parse_redinet(filepath):
    """
    REDInet predictions TSV.
    Actual cols from REDInet_Inference_light_ver.py output:
      region  position  Strand  FreqAGrna  [A,C,G,T]  start  stop  int_len  TabixLen  snp_proba  ed_proba  y_hat
    """
    sites = {}
    if not os.path.exists(filepath) or os.path.getsize(filepath) == 0:
        return sites
    with _open(filepath) as fh:
        header = None
        for line in fh:
            if not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if header is None:
                header = [x.lower() for x in c]
                continue
            row = dict(zip(header, c))
            # flexible column name lookup
            chrom = row.get("chrom", row.get("chromosome", row.get("region", c[0] if c else "")))
            pos = row.get("position", row.get("pos", c[1] if len(c) > 1 else ""))
            try:
                cov = float(row.get("coverage", row.get("cov", 0)))
                frac = float(row.get("agfreq", row.get("freqagrna", row.get("frequency", row.get("freq", 0)))))
                score = float(row.get("redinet_probability", row.get("ed_proba", row.get("probability", row.get("score", frac)))))
            except (ValueError, KeyError):
                continue
            if chrom and pos:
                sites[(chrom, pos)] = (cov, frac, score)
    return sites


def parse_marine(filepath):
    """
    MARINE edit-type-filtered site table (final_filtered_site_info.<EDIT_TYPE>.tsv).
    Columns: site_id barcode contig position ref alt strand count coverage
             conversion strand_conversion
    MARINE has no edit-fraction column, so it is computed as count/coverage.
    The file is already restricted to one strand_conversion by the Snakemake
    filter rule; the EDIT_TYPES check below is a defensive no-op.
    """
    sites = {}
    if not os.path.exists(filepath) or os.path.getsize(filepath) == 0:
        return sites
    with _open(filepath) as fh:
        header = None
        for line in fh:
            if not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if header is None:
                header = [x.lower() for x in c]
                continue
            row = dict(zip(header, c))
            chrom = row.get("contig", row.get("chrom", ""))
            pos = row.get("position", row.get("pos", ""))
            conversion = row.get("strand_conversion", row.get("conversion", ""))
            if conversion and conversion not in EDIT_TYPES:
                continue
            try:
                cov = float(row.get("coverage", 0))
                edited = float(row.get("count", 0))
            except (ValueError, KeyError):
                continue
            frac = edited / cov if cov else 0.0
            if chrom and pos:
                sites[(chrom, pos)] = (cov, frac, frac)
    return sites


# ---------------------------------------------------------------------------
# Dispatch table
# ---------------------------------------------------------------------------

TOOL_PARSERS = {
    "reditools2": ("reditools", parse_reditools2),
    "reditools":  ("reditools", parse_reditools2),
    "reditools3": ("reditools3", parse_reditools3),
    "sprint":     ("sprint",    parse_sprint),
    "red_ml":     ("red_ml",    parse_red_ml),
    "redml":      ("red_ml",    parse_red_ml),
    "bcftools":   ("bcftools",  parse_bcftools),
    "jacusa2":    ("jacusa2",   parse_jacusa2),
    "jacusa2_call1": ("jacusa2_call1", parse_jacusa2_call1),
    "redinet":    ("redinet",   parse_redinet),
    "marine":     ("marine",    parse_marine),
}


def locate_tool_output(results_dir, tool_dir, aligner, condition, sample):
    """
    Return the path to this tool's primary output file/dir for a given sample.
    Returns None if not found.
    """
    base = os.path.join(results_dir, "tools", aligner, tool_dir)

    candidates = [
        # reditools2 (plain; consumed by the vendored downstream parsers)
        os.path.join(base, f"{condition}_{sample}.output"),
        # reditools3 (gzipped)
        os.path.join(base, f"{condition}_{sample}.txt.gz"),
        os.path.join(base, f"{condition}_{sample}.txt"),
        # sprint (directory)
        os.path.join(base, f"{condition}_{sample}_output"),
        # red_ml (directory)
        os.path.join(base, f"{condition}_{sample}_output"),
        # bcftools
        os.path.join(base, f"{condition}_{sample}.bcf"),
        # jacusa2 (single file for all samples; plain, downstream-consumed)
        os.path.join(base, "Jacusa.out"),
        # jacusa2_call1 (per-sample, one condition vs reference; gzipped)
        os.path.join(base, f"{condition}_{sample}.out.gz"),
        os.path.join(base, f"{condition}_{sample}.out"),
        # redinet (gzipped)
        os.path.join(base, f"{condition}_{sample}.predictions.tsv.gz"),
        os.path.join(base, f"{condition}_{sample}.predictions.tsv"),
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    # marine: edit-type-filtered TSV (edit type baked into filename); match the
    # filtered variant only (final_filtered_site_info.<EDIT>.tsv.gz), never the
    # raw final_filtered_site_info.tsv.gz.
    marine_hits = glob.glob(
        os.path.join(base, f"{condition}_{sample}", "final_filtered_site_info.*.tsv.gz")
    )
    if marine_hits:
        return marine_hits[0]
    return None


def parse_tool_sample(tool_key, path, parse_fn):
    """
    Call parse_fn with path, handle directory vs file dispatch for SPRINT/RED-ML.
    Returns dict[(chrom, pos)] -> (cov, frac, score).
    """
    if os.path.isdir(path):
        return parse_fn(path)
    return parse_fn(path)


# ---------------------------------------------------------------------------
# Matrix builder
# ---------------------------------------------------------------------------

def build_matrices(results_dir, tools, aligners, conditions, samples):
    """
    Returns three dicts: cov_data, frac_data, score_data.
    Each maps column_name -> dict[(chrom, pos)] -> value.
    """
    cov_data = {}
    frac_data = {}
    score_data = {}

    for tool_key in tools:
        if tool_key not in TOOL_PARSERS:
            print(f"  [warn] Unknown tool '{tool_key}', skipping.", file=sys.stderr)
            continue
        tool_dir, parse_fn = TOOL_PARSERS[tool_key]

        if tool_key == "jacusa2":
            # JACUSA2 is per-aligner, not per-sample
            for aligner in aligners:
                jacusa_path = os.path.join(
                    results_dir, "tools", aligner, "jacusa2", "Jacusa.out"
                )
                col = f"jacusa2.{aligner}.all_samples"
                sites = parse_jacusa2(jacusa_path)
                cov_data[col] = {k: v[0] for k, v in sites.items()}
                frac_data[col] = {k: v[1] for k, v in sites.items()}
                score_data[col] = {k: v[2] for k, v in sites.items()}
            continue

        for aligner in aligners:
            for condition in conditions:
                for sample in samples:
                    col = f"{tool_key}.{aligner}.{condition}_{sample}"
                    path = locate_tool_output(
                        results_dir, tool_dir, aligner, condition, sample
                    )
                    if path is None:
                        print(
                            f"  [skip] {col}: no output found in "
                            f"{results_dir}/tools/{aligner}/{tool_dir}/",
                            file=sys.stderr,
                        )
                        cov_data[col] = {}
                        frac_data[col] = {}
                        score_data[col] = {}
                        continue

                    print(f"  [parse] {col} <- {path}", file=sys.stderr)
                    sites = parse_tool_sample(tool_key, path, parse_fn)
                    cov_data[col] = {k: v[0] for k, v in sites.items()}
                    frac_data[col] = {k: v[1] for k, v in sites.items()}
                    score_data[col] = {k: v[2] for k, v in sites.items()}

    return cov_data, frac_data, score_data


def write_matrices_streaming(cov_data, frac_data, score_data, outdir, chunk=50_000):
    """
    Write three position matrices to TSV files in a chunked streaming fashion.

    Avoids allocating a full N×M dense array in memory (which OOMs when reditools
    outputs have millions of positions × ~100 columns).  Instead, processes
    chunk rows at a time across all three output files simultaneously.
    """
    import gc
    import gzip

    cols = list(cov_data.keys())

    # Union of all positions across the three data dicts
    pos_set = set()
    for d in (cov_data, frac_data, score_data):
        for cd in d.values():
            pos_set.update(cd.keys())
    all_positions = sorted(
        pos_set,
        key=lambda t: (t[0], int(t[1]) if t[1].isdigit() else 0),
    )
    del pos_set
    gc.collect()

    n_pos, n_cols = len(all_positions), len(cols)
    header = "\t" + "\t".join(cols) + "\n"

    paths = [
        os.path.join(outdir, "edit_coverage_matrix.tsv.gz"),
        os.path.join(outdir, "edit_fraction_matrix.tsv.gz"),
        os.path.join(outdir, "tool_score_matrix.tsv.gz"),
    ]
    data_dicts = [cov_data, frac_data, score_data]

    with gzip.open(paths[0], "wt") as f0, gzip.open(paths[1], "wt") as f1, gzip.open(paths[2], "wt") as f2:
        handles = [f0, f1, f2]
        for fh in handles:
            fh.write(header)

        for start in range(0, n_pos, chunk):
            chunk_pos = all_positions[start : start + chunk]
            labels = [f"{t[0]}:{t[1]}" for t in chunk_pos]
            for fh, data in zip(handles, data_dicts):
                # Build chunk array (chunk_rows × n_cols) — small and transient
                arr = np.zeros((len(chunk_pos), n_cols), dtype=np.float32)
                for j, col in enumerate(cols):
                    cd = data[col]
                    for i, k in enumerate(chunk_pos):
                        arr[i, j] = cd.get(k, 0.0)
                lines = [
                    labels[i] + "\t" + "\t".join(f"{v:.6g}" for v in arr[i])
                    for i in range(len(chunk_pos))
                ]
                fh.write("\n".join(lines) + "\n")
                del arr

    for path in paths:
        print(f"  Wrote {path}  ({n_pos} positions × {n_cols} columns)", file=sys.stderr)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--results-dir", required=True,
                    help="Pipeline results directory (contains tools/)")
    ap.add_argument("--outdir", required=True,
                    help="Output directory for matrix TSVs")
    ap.add_argument("--tools", nargs="+",
                    default=["reditools", "sprint", "red_ml", "bcftools",
                             "jacusa2", "jacusa2_call1", "reditools3",
                             "redinet", "marine"],
                    help="Tools to include")
    ap.add_argument("--aligners", nargs="+", default=["star"],
                    help="Aligners to include")
    ap.add_argument("--conditions", nargs="+", required=True)
    ap.add_argument("--samples", nargs="+", required=True)
    ap.add_argument("--edit-type", default="AG",
                    help="Substitution to keep (plus its reverse complement). Default AG (A->I).")
    ap.add_argument("--jacusa2-call1-filter", default="edit_type",
                    choices=["edit_type", "unfiltered"],
                    help="JACUSA2 call-1 site filtering: 'edit_type' (reditools-style, "
                         "keep only --edit-type sites) or 'unfiltered' (JACUSA2-style, keep all).")
    args = ap.parse_args()

    global EDIT_TYPES, JACUSA2_CALL1_FILTER
    EDIT_TYPES = edit_type_set(args.edit_type)
    JACUSA2_CALL1_FILTER = args.jacusa2_call1_filter

    os.makedirs(args.outdir, exist_ok=True)

    print(f"Building matrices (edit_type={args.edit_type} -> {sorted(EDIT_TYPES)})...",
          file=sys.stderr)
    cov_data, frac_data, score_data = build_matrices(
        args.results_dir, args.tools, args.aligners,
        args.conditions, args.samples
    )

    write_matrices_streaming(cov_data, frac_data, score_data, args.outdir)


if __name__ == "__main__":
    main()
