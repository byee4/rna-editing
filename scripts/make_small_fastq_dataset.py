#!/usr/bin/env python3
"""Generate small example datasets from FASTQ(.gz) files.

Modes:
1) Random sampling (default): sample N reads (or read pairs) from input FASTQ files.
2) Gene-targeted sampling: run permissive STAR alignment, keep reads overlapping
   specified genes from a GTF, then sample up to N reads (or read pairs).

Expected usage environment:
- module load python3essential
- For gene mode, STAR must be available. This script invokes:
  module load star/2.7.6a && STAR ...
"""

from __future__ import annotations

import argparse
import gzip
import random
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import DefaultDict, Dict, Iterator, List, Optional, Sequence, Set, Tuple
import pysam
from tqdm import trange

FASTQRecord = Tuple[bytes, bytes, bytes, bytes]


@dataclass
class GenomicInterval:
    start: int  # 1-based inclusive
    end: int  # 1-based inclusive


def open_maybe_gz(path: Path, mode: str):
    if str(path).endswith(".gz"):
        return gzip.open(path, mode)
    return open(path, mode)


def normalize_qname(name: str) -> str:
    """Normalize read names to match between SAM and FASTQ headers."""
    base = name.split()[0]
    if base.endswith("/1") or base.endswith("/2"):
        base = base[:-2]
    return base


def iter_fastq(path: Path) -> Iterator[FASTQRecord]:
    with open_maybe_gz(path, "rb") as fh:
        while True:
            h = fh.readline()
            if not h:
                break
            s = fh.readline()
            p = fh.readline()
            q = fh.readline()
            if not (s and p and q):
                raise ValueError(f"Malformed FASTQ: truncated record in {path}")
            yield (h, s, p, q)


def parse_fastq_name(header: bytes) -> str:
    # FASTQ header starts with '@'. Keep first whitespace-delimited token.
    token = header[1:].strip().split(b" ", 1)[0].decode("utf-8", errors="replace")
    return normalize_qname(token)


def write_fastq(records: Sequence[FASTQRecord], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(out_path, "wb") as out:
        for rec in records:
            out.write(rec[0])
            out.write(rec[1])
            out.write(rec[2])
            out.write(rec[3])


def reservoir_sample_single(in_r1: Path, n: int, seed: int) -> List[FASTQRecord]:
    rng = random.Random(seed)
    sample: List[FASTQRecord] = []
    for i, rec in enumerate(iter_fastq(in_r1), start=1):
        if i <= n:
            sample.append(rec)
        else:
            j = rng.randint(1, i)
            if j <= n:
                sample[j - 1] = rec
    return sample


def reservoir_sample_paired(in_r1: Path, in_r2: Path, n: int, seed: int) -> List[Tuple[FASTQRecord, FASTQRecord]]:
    rng = random.Random(seed)
    sample: List[Tuple[FASTQRecord, FASTQRecord]] = []
    it1 = iter_fastq(in_r1)
    it2 = iter_fastq(in_r2)
    progress = trange(n, position=0, leave=False)
    progress.set_description('reservoir_sample_paired')
    i = 0
    while True:
        try:
            rec1 = next(it1)
        except StopIteration:
            try:
                next(it2)
                raise ValueError("R1 ended before R2")
            except StopIteration:
                break

        try:
            rec2 = next(it2)
        except StopIteration:
            raise ValueError("R2 ended before R1")

        i += 1
        if i <= n:
            sample.append((rec1, rec2))
        else:
            j = rng.randint(1, i)
            if j <= n:
                sample[j - 1] = (rec1, rec2)
        progress.update(1)
    return sample


def parse_gtf_gene_intervals(
    gtf: Path, genes: Set[str]
) -> Tuple[DefaultDict[str, List[GenomicInterval]], Set[str]]:
    gene_name_pat = re.compile(r'gene_name "([^"]+)"')
    intervals: DefaultDict[str, List[GenomicInterval]] = defaultdict(list)
    found_genes: Set[str] = set()
    with open(gtf, "rt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9:
                continue
            chrom, _source, feature, start, end, _score, _strand, _frame, attrs = fields
            if feature != "gene":
                continue
            m = gene_name_pat.search(attrs)
            if not m:
                continue
            gene_name = m.group(1)
            if gene_name not in genes:
                continue
            found_genes.add(gene_name)
            intervals[chrom].append(GenomicInterval(int(start), int(end)))
    for chrom in intervals:
        intervals[chrom].sort(key=lambda x: (x.start, x.end))

    missing = genes - found_genes
    if not intervals:
        raise ValueError("No matching gene intervals found in GTF for requested genes")
    return intervals, missing


def interval_overlaps(intervals: List[GenomicInterval], start: int, end: int) -> bool:
    # Linear scan is sufficient for small target-gene lists.
    for iv in intervals:
        if iv.end < start:
            continue
        if iv.start > end:
            return False
        if iv.start <= end and start <= iv.end:
            return True
    return False


def cigar_ref_span(cigar: str) -> int:
    # Operations consuming reference: M, D, N, =, X
    span = 0
    num = ""
    for c in cigar:
        if c.isdigit():
            num += c
            continue
        if not num:
            continue
        n = int(num)
        if c in {"M", "D", "N", "=", "X"}:
            span += n
        num = ""
    return span


def run_star_alignment(
    r1: Path,
    r2: Optional[Path],
    star_index: Path,
    out_prefix: Path,
    threads: int,
) -> Path:
    out_prefix.parent.mkdir(parents=True, exist_ok=True)

    cmd_parts = [
        "module load python3essential",
        "module load star/2.7.6a",
        "STAR",
        f"--runThreadN {threads}",
        f"--genomeDir {star_index}",
        f"--readFilesIn {r1}" + (f" {r2}" if r2 else ""),
        "--readFilesCommand zcat",
        f"--outFileNamePrefix {out_prefix}",
        "--outSAMtype BAM Unsorted",
        "--outFilterMultimapNmax 200",
        "--outFilterMismatchNmax 12",
        "--outFilterMatchNminOverLread 0.3",
        "--outFilterScoreMinOverLread 0.3",
        "--alignIntronMax 1000000",
        "--alignMatesGapMax 1000000",
    ]
    shell_cmd = " && ".join([cmd_parts[0], cmd_parts[1], " ".join(cmd_parts[2:])])
    print(f"Running STAR: {shell_cmd}", file=sys.stderr)

    proc = subprocess.run(["bash", "-lc", shell_cmd], check=False)
    if proc.returncode != 0:
        raise RuntimeError("STAR alignment failed")

    unsorted_bam_path = Path(str(out_prefix) + "Aligned.out.bam")
    if not unsorted_bam_path.exists():
        raise FileNotFoundError(f"Expected STAR BAM output not found: {unsorted_bam_path}")

    sorted_bam_path = Path(str(out_prefix) + "Aligned.sortedByCoord.out.bam")
    print(f"Sorting BAM: {unsorted_bam_path} -> {sorted_bam_path}", file=sys.stderr)
    pysam.sort("-o", str(sorted_bam_path), str(unsorted_bam_path))
    print(f"Indexing BAM: {sorted_bam_path}", file=sys.stderr)
    pysam.index(str(sorted_bam_path))

    # Keep disk usage low by removing the temporary unsorted alignment.
    unsorted_bam_path.unlink()
    return sorted_bam_path


def mapped_reads_overlapping_genes(bam_path: Path, intervals_by_chrom: Dict[str, List[GenomicInterval]]) -> Set[str]:
    keep: Set[str] = set()
    with pysam.AlignmentFile(str(bam_path), "rb") as bam:
        for read in bam.fetch(until_eof=True):
            if read.is_unmapped:
                continue
            if read.reference_name is None:
                continue

            chrom_intervals = intervals_by_chrom.get(read.reference_name)
            if not chrom_intervals:
                continue

            pos = read.reference_start + 1  # pysam uses 0-based start.
            end = read.reference_end  # pysam reference_end is 0-based exclusive; numerically equals 1-based inclusive end.
            if pos <= 0 or end is None or end < pos:
                continue

            if interval_overlaps(chrom_intervals, pos, end):
                keep.add(normalize_qname(read.query_name))

    return keep


def filter_fastq_by_names_single(r1: Path, keep_names: Set[str], n: int, seed: int) -> List[FASTQRecord]:
    rng = random.Random(seed)
    selected: List[FASTQRecord] = []
    seen = 0
    for rec in iter_fastq(r1):
        name = parse_fastq_name(rec[0])
        if name not in keep_names:
            continue
        seen += 1
        if seen <= n:
            selected.append(rec)
        else:
            j = rng.randint(1, seen)
            if j <= n:
                selected[j - 1] = rec
    return selected


def filter_fastq_by_names_paired(r1: Path, r2: Path, keep_names: Set[str], n: int, seed: int) -> List[Tuple[FASTQRecord, FASTQRecord]]:
    rng = random.Random(seed)
    selected: List[Tuple[FASTQRecord, FASTQRecord]] = []
    seen = 0

    it1 = iter_fastq(r1)
    it2 = iter_fastq(r2)

    while True:
        try:
            rec1 = next(it1)
        except StopIteration:
            try:
                next(it2)
                raise ValueError("R1 ended before R2")
            except StopIteration:
                break

        try:
            rec2 = next(it2)
        except StopIteration:
            raise ValueError("R2 ended before R1")

        name1 = parse_fastq_name(rec1[0])
        name2 = parse_fastq_name(rec2[0])
        if name1 != name2:
            raise ValueError(f"Read name mismatch between pairs: {name1} != {name2}")

        if name1 not in keep_names:
            continue

        seen += 1
        if seen <= n:
            selected.append((rec1, rec2))
        else:
            j = rng.randint(1, seen)
            if j <= n:
                selected[j - 1] = (rec1, rec2)

    return selected


def infer_default_output_prefix(r1: Path, paired: bool) -> str:
    stem = r1.name
    for suffix in [".fastq.gz", ".fq.gz", ".fastq", ".fq"]:
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
            break
    mode = "paired" if paired else "single"
    return f"{stem}.small.{mode}"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r1", required=True, type=Path, help="Input R1 FASTQ(.gz)")
    p.add_argument("--r2", type=Path, default=None, help="Input R2 FASTQ(.gz), for paired-end")
    p.add_argument("--outdir", type=Path, default=Path("data/small_examples"), help="Output directory")
    p.add_argument("--prefix", default=None, help="Output filename prefix")
    p.add_argument("--n", type=int, default=1_000_000, help="Number of reads/read-pairs to sample")
    p.add_argument("--seed", type=int, default=42, help="Random seed")
    p.add_argument("--threads", type=int, default=4, help="Threads for STAR in gene-targeted mode")

    p.add_argument("--genes", nargs="+", default=None, help="Target gene names (enables gene-targeted mode)")
    p.add_argument("--gtf", type=Path, default=None, help="GTF annotation path (required with --genes)")
    p.add_argument("--star-index", type=Path, default=None, help="STAR index directory (required with --genes)")
    p.add_argument(
        "--keep-star-output",
        action="store_true",
        help="Keep intermediate STAR output directory (default removes it)",
    )

    args = p.parse_args()

    if not args.r1.exists():
        raise FileNotFoundError(f"R1 does not exist: {args.r1}")
    if args.r2 is not None and not args.r2.exists():
        raise FileNotFoundError(f"R2 does not exist: {args.r2}")
    if args.n <= 0:
        raise ValueError("--n must be > 0")

    paired = args.r2 is not None
    prefix = args.prefix or infer_default_output_prefix(args.r1, paired)
    outdir: Path = args.outdir
    outdir.mkdir(parents=True, exist_ok=True)

    out_r1 = outdir / f"{prefix}_R1.fastq.gz"
    out_r2 = outdir / f"{prefix}_R2.fastq.gz"

    gene_mode = args.genes is not None and len(args.genes) > 0

    if gene_mode:
        if args.gtf is None or args.star_index is None:
            raise ValueError("Gene-targeted mode requires --gtf and --star-index")
        if not args.gtf.exists():
            raise FileNotFoundError(f"GTF does not exist: {args.gtf}")
        if not args.star_index.exists():
            raise FileNotFoundError(f"STAR index does not exist: {args.star_index}")

        genes = set(args.genes)
        print(f"Parsing gene intervals for: {sorted(genes)}", file=sys.stderr)
        intervals, missing = parse_gtf_gene_intervals(args.gtf, genes)
        if missing:
            print(
                f"Warning: some requested genes were not found as 'gene' features in GTF: {sorted(missing)}",
                file=sys.stderr,
            )

        star_tmp = outdir / f"{prefix}.star_tmp"
        star_prefix = star_tmp / "star_"

        bam_path = run_star_alignment(
            r1=args.r1,
            r2=args.r2,
            star_index=args.star_index,
            out_prefix=star_prefix,
            threads=args.threads,
        )

        print("Collecting read names overlapping target genes", file=sys.stderr)
        keep_names = mapped_reads_overlapping_genes(bam_path, intervals)
        print(f"Found {len(keep_names)} mapped read names overlapping target genes", file=sys.stderr)

        if paired:
            pairs = filter_fastq_by_names_paired(args.r1, args.r2, keep_names, args.n, args.seed)
            write_fastq([x[0] for x in pairs], out_r1)
            write_fastq([x[1] for x in pairs], out_r2)
            print(f"Wrote {len(pairs)} read pairs to {out_r1} and {out_r2}", file=sys.stderr)
        else:
            reads = filter_fastq_by_names_single(args.r1, keep_names, args.n, args.seed)
            write_fastq(reads, out_r1)
            print(f"Wrote {len(reads)} reads to {out_r1}", file=sys.stderr)

        if not args.keep_star_output and star_tmp.exists():
            shutil.rmtree(star_tmp)

    else:
        if paired:
            pairs = reservoir_sample_paired(args.r1, args.r2, args.n, args.seed)
            write_fastq([x[0] for x in pairs], out_r1)
            write_fastq([x[1] for x in pairs], out_r2)
            print(f"Wrote {len(pairs)} randomly sampled read pairs to {out_r1} and {out_r2}", file=sys.stderr)
        else:
            reads = reservoir_sample_single(args.r1, args.n, args.seed)
            write_fastq(reads, out_r1)
            print(f"Wrote {len(reads)} randomly sampled reads to {out_r1}", file=sys.stderr)


if __name__ == "__main__":
    main()
