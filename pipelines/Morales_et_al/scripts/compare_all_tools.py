#!/usr/bin/env python3
"""
compare_all_tools.py — Build position × sample matrices from all RNA editing tools.

Outputs (in --outdir):
  edit_coverage_matrix.tsv   read depth at each edited position per sample/tool
  edit_fraction_matrix.tsv   editing fraction (0–1) at each position
  tool_score_matrix.tsv      tool-internal confidence score at each position

Columns are named  {tool}.{aligner}.{condition}_{sample}.
Rows are genomic positions  {chrom}:{pos}  (1-based, as reported by each tool).
Missing values are imputed as 0.

Run via:
  module load python3essential
  python3 compare_all_tools.py --results-dir results/ --outdir results/compare_all_tools/ \
      --aligners star bwa hisat2 --conditions WT ADAR1KO --samples clone1 clone2 clone3
"""

import argparse
import os
import subprocess
import sys

import numpy as np
import pandas as pd


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
            if edit_type not in ("AG", "TC"):
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
                if edit_type not in ("AG", "TC"):
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
                if c[7] not in ("AG", "TC"):
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
            if edit_type not in ("AG", "TC"):
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
    Cols: #Chr Pos Strand Ref Coverage Alt Freq P_edit
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
            if edit_type not in ("AG", "TC"):
                continue
            try:
                cov = float(c[4])
                frac = float(c[6])
                score = float(c[7])
            except ValueError:
                continue
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
        if edit_type not in ("AG", "TC"):
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


def parse_redinet(filepath):
    """
    REDInet predictions TSV.
    Expected cols (from REDInet_Inference_light_ver.py output):
      chrom  position  strand  coverage  agfreq  REDInet_class  REDInet_probability
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
                frac = float(row.get("agfreq", row.get("frequency", row.get("freq", 0))))
                score = float(row.get("redinet_probability", row.get("probability", row.get("score", frac))))
            except (ValueError, KeyError):
                continue
            if chrom and pos:
                sites[(chrom, pos)] = (cov, frac, score)
    return sites


def parse_marine(filepath):
    """
    MARINE final_filtered_site_info.tsv.
    Expected cols: contig  position  strand  editing_type  coverage  edited_reads
                   edit_frequency  ...
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
            chrom = row.get("contig", row.get("chrom", row.get("chromosome", c[0] if c else "")))
            pos = row.get("position", row.get("pos", c[1] if len(c) > 1 else ""))
            edit_type = row.get("editing_type", row.get("type", row.get("ref_alt", "")))
            if edit_type and edit_type not in ("AG", "TC", "A>G", "T>C"):
                continue
            try:
                cov = float(row.get("coverage", row.get("cov", 0)))
                frac = float(row.get("edit_frequency", row.get("frequency", row.get("freq", 0))))
            except (ValueError, KeyError):
                continue
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
        # reditools2 / reditools3
        os.path.join(base, f"{condition}_{sample}.output"),
        os.path.join(base, f"{condition}_{sample}.txt"),
        # sprint (directory)
        os.path.join(base, f"{condition}_{sample}_output"),
        # red_ml (directory)
        os.path.join(base, f"{condition}_{sample}_output"),
        # bcftools
        os.path.join(base, f"{condition}_{sample}.bcf"),
        # jacusa2 (single file for all samples)
        os.path.join(base, "Jacusa.out"),
        # redinet
        os.path.join(base, f"{condition}_{sample}.predictions.tsv"),
        # marine
        os.path.join(base, f"{condition}_{sample}", "final_filtered_site_info.tsv"),
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
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


def data_to_df(data_dict):
    """
    Convert {col -> {(chrom,pos) -> val}} to a DataFrame with 0-imputed missing values.
    Row index: 'chrom:pos' strings sorted by (chrom, int(pos)).
    """
    all_positions = sorted(
        {pos for col_data in data_dict.values() for pos in col_data},
        key=lambda t: (t[0], int(t[1]) if t[1].isdigit() else 0),
    )
    index = [f"{chrom}:{pos}" for chrom, pos in all_positions]
    cols = list(data_dict.keys())
    arr = np.zeros((len(all_positions), len(cols)), dtype=float)
    for j, col in enumerate(cols):
        col_data = data_dict[col]
        for i, pos_key in enumerate(all_positions):
            arr[i, j] = col_data.get(pos_key, 0.0)
    return pd.DataFrame(arr, index=index, columns=cols)


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
                             "jacusa2", "reditools3", "redinet", "marine"],
                    help="Tools to include")
    ap.add_argument("--aligners", nargs="+", default=["star"],
                    help="Aligners to include")
    ap.add_argument("--conditions", nargs="+", required=True)
    ap.add_argument("--samples", nargs="+", required=True)
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    print("Building matrices...", file=sys.stderr)
    cov_data, frac_data, score_data = build_matrices(
        args.results_dir, args.tools, args.aligners,
        args.conditions, args.samples
    )

    for label, data in [
        ("edit_coverage_matrix", cov_data),
        ("edit_fraction_matrix", frac_data),
        ("tool_score_matrix",    score_data),
    ]:
        df = data_to_df(data)
        out = os.path.join(args.outdir, f"{label}.tsv")
        df.to_csv(out, sep="\t")
        print(f"  Wrote {out}  ({len(df)} positions × {len(df.columns)} columns)",
              file=sys.stderr)


if __name__ == "__main__":
    main()
