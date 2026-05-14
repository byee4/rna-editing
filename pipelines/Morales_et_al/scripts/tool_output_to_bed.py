#!/usr/bin/env python3
"""
tool_output_to_bed.py — Convert a single tool's output for one sample to BED6.

BED columns: chrom  start(0-based)  end  name(edit_type)  score(0-1000)  strand

Used by the bed_to_bigbed Snakemake rule.

Run via:
  module load python3essential
  python3 tool_output_to_bed.py --tool reditools --input FILE_OR_DIR --output out.bed
"""

import argparse
import os
import subprocess
import sys


def _score1000(frac):
    """Map editing fraction [0,1] to UCSC BED score [0,1000]."""
    try:
        return min(1000, max(0, int(float(frac) * 1000)))
    except (ValueError, TypeError):
        return 0


def to_bed_reditools2(path, out_fh):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return
    with open(path) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) < 9:
                continue
            if c[7] not in ("AG", "TC"):
                continue
            try:
                chrom, pos = c[0], int(c[1])
                score = _score1000(c[8])
                strand = c[3] if c[3] in ("+", "-") else "."
            except (ValueError, IndexError):
                continue
            out_fh.write(f"{chrom}\t{pos-1}\t{pos}\t{c[7]}\t{score}\t{strand}\n")


def to_bed_reditools3(path, out_fh):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return
    with open(path) as f:
        header = None
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if header is None and c[0].lower().strip("#") in ("region", "chrom"):
                header = [x.lower().strip("#") for x in c]
                continue
            if header:
                row = dict(zip(header, c))
                edit_type = row.get("allsubs", row.get("type", ""))
                if edit_type not in ("AG", "TC"):
                    continue
                try:
                    chrom = row.get("region", row.get("chrom", c[0]))
                    pos = int(row.get("position", c[1]))
                    score = _score1000(row.get("frequency", 0))
                    strand = row.get("strand", ".")
                except (ValueError, KeyError):
                    continue
            else:
                if len(c) < 9 or c[7] not in ("AG", "TC"):
                    continue
                try:
                    chrom, pos = c[0], int(c[1])
                    score = _score1000(c[8])
                    strand = c[3] if c[3] in ("+", "-") else "."
                    edit_type = c[7]
                except (ValueError, IndexError):
                    continue
            out_fh.write(f"{chrom}\t{pos-1}\t{pos}\t{edit_type}\t{score}\t{strand}\n")


def to_bed_sprint(dirpath, out_fh):
    res = os.path.join(dirpath, "SPRINT_identified_regular.res")
    if not os.path.exists(res):
        return
    with open(res) as f:
        for line in f:
            if not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) < 5 or c[3] not in ("AG", "TC"):
                continue
            try:
                chrom, pos = c[0], int(c[2])
                frac = float(c[10]) if len(c) > 10 else 0.0
                score = _score1000(frac)
                strand = c[5] if len(c) > 5 and c[5] in ("+", "-") else "."
            except (ValueError, IndexError):
                continue
            out_fh.write(f"{chrom}\t{pos-1}\t{pos}\t{c[3]}\t{score}\t{strand}\n")


def to_bed_red_ml(dirpath, out_fh):
    txt = os.path.join(dirpath, "RNA_editing.sites.txt")
    if not os.path.exists(txt):
        return
    with open(txt) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) < 8:
                continue
            edit_type = c[3] + c[5]
            if edit_type not in ("AG", "TC"):
                continue
            try:
                chrom, pos = c[0], int(c[1])
                score = _score1000(c[7])
                strand = c[2] if c[2] in ("+", "-") else "."
            except (ValueError, IndexError):
                continue
            out_fh.write(f"{chrom}\t{pos-1}\t{pos}\t{edit_type}\t{score}\t{strand}\n")


def to_bed_bcftools(bcf_path, out_fh):
    if not os.path.exists(bcf_path):
        return
    try:
        proc = subprocess.run(
            ["bcftools", "view", bcf_path],
            capture_output=True, text=True, check=True
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return
    for line in proc.stdout.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        c = line.split("\t")
        if len(c) < 5:
            continue
        edit_type = c[3] + c[4]
        if edit_type not in ("AG", "TC"):
            continue
        try:
            chrom, pos = c[0], int(c[1])
            score = _score1000(float(c[5]) / 100.0 if c[5] != "." else 0)
        except (ValueError, IndexError):
            continue
        out_fh.write(f"{chrom}\t{pos-1}\t{pos}\t{edit_type}\t{score}\t.\n")


def to_bed_redinet(path, out_fh):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return
    with open(path) as f:
        header = None
        for line in f:
            if not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if header is None:
                header = [x.lower() for x in c]
                continue
            row = dict(zip(header, c))
            chrom = row.get("chrom", row.get("chromosome", c[0] if c else ""))
            pos_str = row.get("position", row.get("pos", c[1] if len(c) > 1 else ""))
            prob = row.get("redinet_probability", row.get("probability", row.get("score", 0)))
            frac = row.get("agfreq", row.get("frequency", prob))
            strand = row.get("strand", ".")
            if not chrom or not pos_str:
                continue
            try:
                pos = int(pos_str)
                score = _score1000(prob)
            except (ValueError, TypeError):
                continue
            out_fh.write(f"{chrom}\t{pos-1}\t{pos}\tAG\t{score}\t{strand}\n")


def to_bed_marine(path, out_fh):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return
    with open(path) as f:
        header = None
        for line in f:
            if not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if header is None:
                header = [x.lower() for x in c]
                continue
            row = dict(zip(header, c))
            chrom = row.get("contig", row.get("chrom", c[0] if c else ""))
            pos_str = row.get("position", row.get("pos", c[1] if len(c) > 1 else ""))
            edit_type = row.get("editing_type", row.get("type", "AG"))
            if edit_type not in ("AG", "TC", "A>G", "T>C"):
                continue
            edit_type = edit_type.replace(">", "")
            frac = row.get("edit_frequency", row.get("frequency", 0))
            strand = row.get("strand", ".")
            if not chrom or not pos_str:
                continue
            try:
                pos = int(pos_str)
                score = _score1000(frac)
            except (ValueError, TypeError):
                continue
            out_fh.write(f"{chrom}\t{pos-1}\t{pos}\t{edit_type}\t{score}\t{strand}\n")


CONVERTERS = {
    "reditools":  to_bed_reditools2,
    "reditools2": to_bed_reditools2,
    "reditools3": to_bed_reditools3,
    "sprint":     to_bed_sprint,
    "red_ml":     to_bed_red_ml,
    "redml":      to_bed_red_ml,
    "bcftools":   to_bed_bcftools,
    "redinet":    to_bed_redinet,
    "marine":     to_bed_marine,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tool", required=True, choices=list(CONVERTERS))
    ap.add_argument("--input", required=True, help="Tool output file or directory")
    ap.add_argument("--output", required=True, help="Output BED file path")
    args = ap.parse_args()

    fn = CONVERTERS[args.tool]
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)

    with open(args.output, "w") as out_fh:
        fn(args.input, out_fh)

    lines = sum(1 for _ in open(args.output))
    print(f"Wrote {lines} BED records to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
