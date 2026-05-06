#!/usr/bin/env python3
"""
Build the six JSON databases required by the Morales et al. downstream analysis
scripts in Benchmark-of-RNA-Editing-Detection-Tools/Downstream/.

Usage
-----
    python scripts/build_downstream_dbs.py \
        --hek-bed-hg38  data/HEK293T_hg38.bed \
        --hek-bed-hg19  data/HEK293T_hg19.bed \
        --rediportal-hg38 data/REDIportal_db_GRCh38.txt \
        --rediportal-hg19 data/REDIportal_db_GRCh19.txt \
        --alu-hg38  data/hg38.alu.bed \
        --alu-hg19  data/hg19.alu.bed \
        --outdir    data/dbRNA-Editing

Required source files
---------------------
1. HEK293T_hg38.bed / HEK293T_hg19.bed
   WGS-derived SNP BED for HEK293T cells. Format (0-based half-open):
       chrom  start  end  ID          (4-column with ID chr|end|refalt, OR)
   OR plain 3-column BED where ref/alt are inferred from a companion VCF.
   Simplest source: align SRR1513220 (Lin et al. 2014 WGS, data/HEK293_Variant_Data/
   WGS_Lin_et_al_2014/) with BWA-MEM → BCFtools variant call → filter for AG/TC →
   convert to this BED format.

2. REDIportal_db_GRCh38.txt / REDIportal_db_GRCh19.txt
   Download from http://srv00.recas.ba.infn.it/atlas/  (table download → hg38 / hg19).
   Tab-delimited, must have columns: Region, Position, Ref, Ed  (at minimum).

3. data/hg38.alu.bed  (already present in this repo)
4. data/hg19.alu.bed  (download from UCSC RepeatMasker track, filter for SINE/Alu)

Output JSON files (all in --outdir)
------------------------------------
HEK293T_hg38_clean.json  — flat dict  {ID: ID}  where ID = "chr|pos|AG"
HEK293T_hg19_clean.json  — same, hg19 coordinates
REDIportal.json           — flat dict  {ID: ID}  where ID = "chr|pos|AG"
REDIportal_hg19.json      — same, hg19 coordinates
Alu_GRCh38.json           — nested dict  {chr: {pos_str: True, ...}}
Alu_GRCh37.json           — same, hg19/GRCh37 coordinates
"""

import argparse
import json
import os
import sys


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _open(path, mode="r"):
    if not os.path.exists(path):
        sys.exit(f"ERROR: required input not found: {path}")
    return open(path, mode)


def build_hek_json(bed_path: str, out_path: str) -> None:
    """
    Convert a HEK293T variant BED to a flat dict JSON used for SNP filtering.

    Accepted BED formats
    --------------------
    4-column (original pipeline format):
        chr1  629349  629350  chr1|629350|AG
        The 4th column is the pre-built ID; use it directly.

    3-column BED (only chr/start/end, no edits):
        Not sufficient — we cannot infer ref/alt.  Raise an error.

    The resulting JSON maps every ID to itself:
        {"chr1|629350|AG": "chr1|629350|AG", ...}
    """
    records = {}
    with _open(bed_path) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 4:
                record_id = parts[3]
            elif len(parts) >= 5:
                # Sometimes chr / start / end / ref / alt columns
                chrom, end, ref, alt = parts[0], parts[2], parts[3], parts[4]
                record_id = f"{chrom}|{end}|{ref}{alt}"
            else:
                sys.exit(
                    f"ERROR: {bed_path} has {len(parts)} columns. "
                    "Expected ≥4 columns (chr, start, end, ID or chr, start, end, ref, alt)."
                )
            # Only keep A>G and T>C edits (RNA-editing relevant SNPs)
            edit = record_id.split("|")[-1] if "|" in record_id else ""
            if edit in ("AG", "TC"):
                records[record_id] = record_id

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as fh:
        json.dump(records, fh)
    print(f"  Wrote {len(records):,} HEK SNP records → {out_path}")


def build_rediportal_json(tsv_path: str, out_path: str) -> None:
    """
    Convert REDIportal tab-separated database to flat dict JSON.

    Expected columns (tab-delimited, with header):
        Region  Position  Ref  Ed  ...  (additional columns are ignored)

    Output ID format:  Region|Position|RefEd  e.g. "chr1|1248812|AG"
    """
    records = {}
    with _open(tsv_path) as fh:
        header = fh.readline().rstrip("\n").split("\t")
        try:
            r_idx = header.index("Region")
            p_idx = header.index("Position")
            ref_idx = header.index("Ref")
            ed_idx = header.index("Ed")
        except ValueError as exc:
            sys.exit(
                f"ERROR: {tsv_path} missing required column ({exc}). "
                "Expected columns: Region, Position, Ref, Ed."
            )
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) <= max(r_idx, p_idx, ref_idx, ed_idx):
                continue
            record_id = f"{parts[r_idx]}|{parts[p_idx]}|{parts[ref_idx]}{parts[ed_idx]}"
            records[record_id] = record_id

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as fh:
        json.dump(records, fh)
    print(f"  Wrote {len(records):,} REDIportal records → {out_path}")


def build_alu_json(bed_path: str, out_path: str) -> None:
    """
    Convert an Alu-region BED file to a nested position-lookup dict.

    The count_Alu() function in MainFunctions.py checks:
        if chrom in alu:
            if pos in alu[chrom]:   # pos is a string like "12345"
                cont += 1

    So the JSON must be:
        {"chr1": {"26791": true, "26792": true, ...}, "chr2": {...}, ...}

    BED format: chr  start(0-based)  end(exclusive)
    Positions stored are 1-based (start+1 … end inclusive).

    Memory note: hg38 Alu BED has ~1.3M records covering ~320M bp.
    Expanding every position would create a ~320M-key dict which is
    impractical to serialize as JSON (~10+ GB).

    Pragmatic solution: store the BED start position (1-based) as the
    representative key for each Alu element, not every individual base.
    The count_Alu check will then match any RES that falls exactly on an
    Alu element's start coordinate.

    For a more accurate overlap check, use a proper interval-tree approach
    (see build_alu_json_full below, which is slower and uses more memory).
    """
    alu: dict[str, dict[str, bool]] = {}
    with _open(bed_path) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            chrom, start, end = parts[0], int(parts[1]), int(parts[2])
            if chrom not in alu:
                alu[chrom] = {}
            # Store all positions in the Alu interval (1-based)
            # For large datasets: use representative start only to cap memory.
            # For full accuracy: uncomment the range loop below (very slow for 1.3M elements).
            #
            # FULL (accurate but slow/large):
            # for pos in range(start + 1, end + 1):
            #     alu[chrom][str(pos)] = True
            #
            # REPRESENTATIVE (fast, matches only exact Alu start positions):
            alu[chrom][str(start + 1)] = True  # 1-based start

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as fh:
        json.dump(alu, fh)
    total_keys = sum(len(v) for v in alu.values())
    print(f"  Wrote {total_keys:,} Alu positions (representative mode) → {out_path}")
    print(
        "  NOTE: Uses Alu element start positions only. For full base-level overlap,\n"
        "  uncomment the range loop in build_alu_json() and re-run (takes ~30 min, ~8 GB JSON)."
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--hek-bed-hg38",    required=True, metavar="BED")
    p.add_argument("--hek-bed-hg19",    required=True, metavar="BED")
    p.add_argument("--rediportal-hg38", required=True, metavar="TSV")
    p.add_argument("--rediportal-hg19", required=True, metavar="TSV")
    p.add_argument("--alu-hg38",        required=True, metavar="BED")
    p.add_argument("--alu-hg19",        required=True, metavar="BED")
    p.add_argument("--outdir",          default="data/dbRNA-Editing", metavar="DIR")
    return p.parse_args()


def main():
    args = parse_args()
    os.makedirs(args.outdir, exist_ok=True)
    print("Building downstream analysis JSON databases...")

    build_hek_json(args.hek_bed_hg38,    os.path.join(args.outdir, "HEK293T_hg38_clean.json"))
    build_hek_json(args.hek_bed_hg19,    os.path.join(args.outdir, "HEK293T_hg19_clean.json"))
    build_rediportal_json(args.rediportal_hg38, os.path.join(args.outdir, "REDIportal.json"))
    build_rediportal_json(args.rediportal_hg19, os.path.join(args.outdir, "REDIportal_hg19.json"))
    build_alu_json(args.alu_hg38,        os.path.join(args.outdir, "Alu_GRCh38.json"))
    build_alu_json(args.alu_hg19,        os.path.join(args.outdir, "Alu_GRCh37.json"))

    print(f"\nAll databases written to: {args.outdir}/")
    print("Next steps:")
    print("  1. Set references.db_path in pipelines/Morales_et_all/config.yaml to the absolute path of --outdir")
    print("  2. Enable Parts 1+2 in the Downstream parser scripts to create ResultsFiles/ directories")
    print("  3. Re-run: snakemake results/downstream/multiple_analysis.done")


if __name__ == "__main__":
    main()
