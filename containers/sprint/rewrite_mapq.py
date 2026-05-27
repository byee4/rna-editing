#!/usr/bin/env python3
"""Rewrite MAPQ=255 to a target value in a BAM file.

Usage: rewrite_mapq.py IN_BAM OUT_BAM TARGET_MAPQ

Replaces SPRINT's utilities/changesammapq.py. That script produces BGZF blocks
that SAMtools 1.2 (inside sprint_from_bam.py) cannot read, causing SPRINT to
produce empty output on STAR/HISAT2-aligned BAMs. pysam writes valid BGZF output.
"""
import sys
import pysam


def main():
    if len(sys.argv) != 4:
        sys.exit("Usage: rewrite_mapq.py IN_BAM OUT_BAM TARGET_MAPQ")
    in_bam, out_bam, new_mapq = sys.argv[1], sys.argv[2], int(sys.argv[3])
    with pysam.AlignmentFile(in_bam, "rb") as f_in:
        with pysam.AlignmentFile(out_bam, "wb", template=f_in) as f_out:
            for read in f_in:
                if read.mapping_quality == 255:
                    read.mapping_quality = new_mapq
                f_out.write(read)


if __name__ == "__main__":
    main()
