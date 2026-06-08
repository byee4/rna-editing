#!/usr/bin/env python3
"""Stage 3 of the shared candidate-site pipeline (spec DD1a).

Reconciles the merged candidate set (stage 1 output, `candidates.bed.gz`) with the
gene-strand and dbSNP `bedtools intersect` sidecars (stage 2,
`annotate_candidate_strand`) and emits the two retained, gzipped views:

  * GIREMI 6-column SNV list:  chrom  start0  end1  gene|Inte  dbSNP(1/0)  strand(+/-/#)
  * EditPredict positions TSV: chrom  pos(1-based)   (A-to-I subset only)

Strand precedence (DD1a): the A-to-I substitution fixes strand directly (A>G => '+',
T>C => '-'); for all other substitution types strand comes from gene annotation, and
'#' is written only when the site is intergenic (or genic on both strands, i.e.
strand-uninformative). EditPredict only scores the A-to-I class, so its view is the
subset whose substitution-derived strand is '+' or '-'.

candidates.bed.gz columns (no header):
  chrom start0 end1 ref alt cov alt_count fwd_count rev_count sub_strand
"""
import argparse
import gzip


def _open(path, mode="rt"):
    return gzip.open(path, mode) if path.endswith(".gz") else open(path, mode)


def _key(chrom, start0, ref, alt):
    return (chrom, start0, ref, alt)


def load_dbsnp_flags(path):
    """`bedtools intersect -a candidates.bed -b dbsnp.bed -c`: last col is overlap count."""
    flags = {}
    with _open(path) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 11:
                continue
            count = int(f[-1])
            flags[_key(f[0], int(f[1]), f[3], f[4])] = 1 if count > 0 else 0
    return flags


def load_gene_strands(path):
    """`bedtools intersect -a candidates.bed -b gene.bed -loj`.

    Appends the gene BED6 (chrom start end name type strand) or a no-overlap sentinel
    ('.'/'-1'). Collect, per candidate, the set of overlapping gene strands and names.
    """
    strands = {}
    names = {}
    with _open(path) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 16:
                continue
            k = _key(f[0], int(f[1]), f[3], f[4])
            gene_name, gene_strand = f[13], f[15]
            strands.setdefault(k, set())
            names.setdefault(k, [])
            # No-overlap rows from -loj carry '.' / '-1'; skip them.
            if gene_strand in ("+", "-"):
                strands[k].add(gene_strand)
            if gene_name not in (".", "-1", ""):
                names[k].append(gene_name)
    return strands, names


def resolve(sub_strand, gene_strands, gene_names):
    """Return (gene_label, strand) per DD1a precedence."""
    name = gene_names[0] if gene_names else "Inte"
    if sub_strand in ("+", "-"):
        return name, sub_strand
    if gene_strands == {"+"}:
        return name, "+"
    if gene_strands == {"-"}:
        return name, "-"
    # No gene overlap, or genic on both strands (strand-uninformative): '#'.
    label = name if gene_names else "Inte"
    return label, "#"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--candidates", required=True, help="candidates.bed(.gz)")
    ap.add_argument("--gene-intersect", required=True)
    ap.add_argument("--dbsnp-intersect", required=True)
    ap.add_argument("--giremi-out", required=True, help="GIREMI 6-col SNV list (.gz ok)")
    ap.add_argument("--editpredict-out", required=True, help="positions TSV (.gz ok)")
    args = ap.parse_args()

    dbsnp = load_dbsnp_flags(args.dbsnp_intersect)
    gene_strands, gene_names = load_gene_strands(args.gene_intersect)

    seen_positions = set()
    seen_giremi = set()
    with _open(args.candidates) as cin, \
            _open(args.giremi_out, "wt") as gout, \
            _open(args.editpredict_out, "wt") as eout:
        for line in cin:
            f = line.rstrip("\n").split("\t")
            if len(f) < 10:
                continue
            chrom, start0, end1, ref, alt = f[0], int(f[1]), int(f[2]), f[3], f[4]
            sub_strand = f[9]
            k = _key(chrom, start0, ref, alt)
            label, strand = resolve(sub_strand,
                                    gene_strands.get(k, set()),
                                    gene_names.get(k, []))
            flag = dbsnp.get(k, 0)
            # GIREMI keys its SNV list on (chrom, position) only and rejects any
            # repeated coordinate ("error: repeat snv"), regardless of strand. A
            # site can yield multiple candidate rows (different alt, or +/- subs),
            # so collapse to one row per coordinate, keeping the first seen.
            giremi_key = (chrom, start0)
            if giremi_key not in seen_giremi:
                seen_giremi.add(giremi_key)
                gout.write(f"{chrom}\t{start0}\t{end1}\t{label}\t{flag}\t{strand}\n")
            # EditPredict scores the A-to-I class only (substitution-strand resolved).
            if sub_strand in ("+", "-"):
                pos_key = (chrom, end1)
                if pos_key not in seen_positions:
                    seen_positions.add(pos_key)
                    eout.write(f"{chrom}\t{end1}\n")


if __name__ == "__main__":
    main()
