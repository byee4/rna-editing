#!/usr/bin/env python3
"""Stage 1 of the shared candidate-site pipeline (spec DD1).

Reads `samtools mpileup` output (stdin or --pileup) and emits a per-chromosome
provisional candidate table: one row per (site, alternate allele) that clears the
coverage and alt-read-support floors. Strand for the A-to-I edit class is fixed by
the substitution itself (A>G => '+', T>C => '-'); all other substitution types get
'.' here and are strand-assigned downstream from gene annotation (finalize step).

GIREMI needs every substitution type in its candidate list (its mutual-information
step anchors candidate edits against nearby SNPs), so this stage does NOT filter to
A-to-I; it keeps all mismatch alleles. The A-to-I subset is taken later for the
EditPredict view.

Output columns (tab-separated, with header):
    chrom  start0  end1  ref  alt  cov  alt_count  fwd_count  rev_count  sub_strand

Base-quality filtering is applied here from the aligned quality string rather than
relying on `samtools mpileup -Q`, so the `cov`/`alt_count` reported are exactly the
counts that pass `--base-quality`.
"""
import argparse
import sys

_ALLELES = ("A", "C", "G", "T")
# Substitution -> transcript strand for the A-to-I edit class. A>G on a (+) transcript;
# the reverse-strand image of an A>I edit is T>C on the genome, i.e. a (-) transcript.
_AI_STRAND = {("A", "G"): "+", ("T", "C"): "-"}


def parse_site(bases, quals, ref, min_bq):
    """Count per-allele forward/reverse support at one pileup site (BQ-filtered)."""
    fwd = {a: 0 for a in _ALLELES}
    rev = {a: 0 for a in _ALLELES}
    ref = ref.upper()
    i = q = 0
    n = len(bases)
    while i < n:
        c = bases[i]
        if c == "^":
            i += 2
            continue
        if c == "$":
            i += 1
            continue
        if c in "+-":
            i += 1
            num = ""
            while i < n and bases[i].isdigit():
                num += bases[i]
                i += 1
            i += int(num) if num else 0
            continue
        if c == "*":
            q += 1
            i += 1
            continue
        keep = q < len(quals) and (ord(quals[q]) - 33) >= min_bq
        q += 1
        i += 1
        if not keep:
            continue
        if c == ".":
            if ref in fwd:
                fwd[ref] += 1
        elif c == ",":
            if ref in rev:
                rev[ref] += 1
        elif c in "ACGTN":
            if c in fwd:
                fwd[c] += 1
        elif c in "acgtn":
            b = c.upper()
            if b in rev:
                rev[b] += 1
    return fwd, rev


def iter_candidates(pileup_lines, min_cov, min_alt, min_bq):
    """Yield candidate rows from mpileup lines."""
    for line in pileup_lines:
        line = line.rstrip("\n")
        if not line:
            continue
        f = line.split("\t")
        if len(f) < 5:
            continue
        chrom, pos, ref = f[0], f[1], f[2].upper()
        bases = f[4] if len(f) > 4 else ""
        quals = f[5] if len(f) > 5 else ""
        if ref not in _ALLELES:
            continue
        fwd, rev = parse_site(bases, quals, ref, min_bq)
        cov = sum(fwd[a] + rev[a] for a in _ALLELES)
        if cov < min_cov:
            continue
        for alt in _ALLELES:
            if alt == ref:
                continue
            alt_count = fwd[alt] + rev[alt]
            if alt_count < min_alt:
                continue
            sub_strand = _AI_STRAND.get((ref, alt), ".")
            start0 = int(pos) - 1
            yield (chrom, start0, int(pos), ref, alt, cov,
                   alt_count, fwd[alt], rev[alt], sub_strand)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pileup", default="-",
                    help="samtools mpileup output ('-' for stdin)")
    ap.add_argument("--output", default="-", help="output TSV ('-' for stdout)")
    ap.add_argument("--min-coverage", type=int, required=True)
    ap.add_argument("--min-alt-reads", type=int, required=True)
    ap.add_argument("--base-quality", type=int, required=True)
    args = ap.parse_args()

    fin = sys.stdin if args.pileup == "-" else open(args.pileup)
    fout = sys.stdout if args.output == "-" else open(args.output, "w")
    try:
        fout.write("chrom\tstart0\tend1\tref\talt\tcov\talt_count\t"
                   "fwd_count\trev_count\tsub_strand\n")
        for row in iter_candidates(fin, args.min_coverage,
                                   args.min_alt_reads, args.base_quality):
            fout.write("\t".join(str(x) for x in row) + "\n")
    finally:
        if fin is not sys.stdin:
            fin.close()
        if fout is not sys.stdout:
            fout.close()


if __name__ == "__main__":
    main()
