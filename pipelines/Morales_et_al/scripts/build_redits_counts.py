#!/usr/bin/env python3
"""Build the integer per-site edited/total count matrix REDIT-LLR consumes (spec DD3a).

Reads one chosen caller's per-sample outputs and emits, per A-to-I site covered in
ALL samples, a row `chrom  pos  <s1_edited,s1_total>  <s2_...> ...`. Counts are taken
from the caller's NATIVE integer columns — never reconstructed as fraction*coverage,
which would inject rounding noise and be wrong at the 0-vs-1 edited boundary.

Currently supports the REDItools v1 output (the default caller):
  Region Position Reference Strand Coverage-q30 MeanQ BaseCount[A,C,G,T] AllSubs Freq ...
  edited = G count (ref A) or C count (ref T); total = Coverage-q30.
"""
import argparse
import ast
import os


def _open(path):
    import gzip
    return gzip.open(path, "rt") if path.endswith(".gz") else open(path)


# ref base -> the edited base whose count is the A-to-I signal
_EDITED_BASE = {"A": "G", "T": "C"}
_BASE_INDEX = {"A": 0, "C": 1, "G": 2, "T": 3}


def parse_reditools_counts(path):
    """Return {(chrom, pos): (edited, total)} for A-to-I sites in a REDItools output."""
    counts = {}
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return counts
    with _open(path) as fh:
        header = None
        for line in fh:
            if not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if header is None:
                header = [x.strip().lower() for x in c]
                continue
            row = dict(zip(header, c))
            chrom = row.get("region", c[0] if c else "")
            pos = row.get("position", c[1] if len(c) > 1 else "")
            ref = (row.get("reference", "") or "").upper()
            if ref not in _EDITED_BASE:
                continue
            try:
                basecount = ast.literal_eval(row.get("basecount[a,c,g,t]", "[]"))
                total = int(float(row.get("coverage-q30", 0)))
            except (ValueError, SyntaxError):
                continue
            if not isinstance(basecount, list) or len(basecount) < 4:
                continue
            edited = int(basecount[_BASE_INDEX[_EDITED_BASE[ref]]])
            if chrom and pos:
                counts[(chrom, pos)] = (edited, total)
    return counts


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--inputs", nargs="+", required=True,
                    help="per-sample caller outputs, in sample-column order")
    ap.add_argument("--sample-names", nargs="+", required=True,
                    help="column names aligned to --inputs")
    ap.add_argument("--caller", default="reditools")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    if len(args.inputs) != len(args.sample_names):
        raise SystemExit("--inputs and --sample-names must have equal length")
    if args.caller != "reditools":
        raise SystemExit(f"unsupported REDITs caller: {args.caller}")

    per_sample = [parse_reditools_counts(p) for p in args.inputs]
    # Keep only sites covered (total >= 1) in every sample, so REDIT-LLR sees a
    # complete row with no zero-trial samples.
    common = None
    for d in per_sample:
        covered = {k for k, (_, total) in d.items() if total >= 1}
        common = covered if common is None else (common & covered)
    common = common or set()

    def sort_key(k):
        chrom, pos = k
        try:
            return (chrom, int(pos))
        except ValueError:
            return (chrom, 0)

    with open(args.output, "w") as out:
        out.write("chrom\tpos\t" + "\t".join(args.sample_names) + "\n")
        for k in sorted(common, key=sort_key):
            chrom, pos = k
            cells = []
            for d in per_sample:
                edited, total = d[k]
                cells.append(f"{edited},{total}")
            out.write(f"{chrom}\t{pos}\t" + "\t".join(cells) + "\n")


if __name__ == "__main__":
    main()
