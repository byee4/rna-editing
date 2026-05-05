# Codemap: rna-editing
Generated: 2026-05-05 17:13 UTC
Files indexed: 6 | Estimated tokens: ~808

## File Tree
  containers/editpredict/
    fix_upstream.py - Patch upstream EditPredict scripts for the Python 3 containe
  scripts/
    make_small_fastq_dataset.py - Generate small example datasets from FASTQ(.gz) files. Modes
    sprint_to_deepred_vcf.py - Convert SPRINT regular RES output into DeepRed candidate SNV
    sprint_to_editpredict_positions.py - Convert SPRINT regular RES output into EditPredict position 
  tests/
    test_editing_wgs_dryrun.py - 1 class(es): EditingWgsDryRunTest
    test_sprint_to_deepred_vcf.py - 1 class(es): SprintToDeepRedVcfTest

## Key Files
### containers/editpredict/fix_upstream.py
**Purpose**: Patch upstream EditPredict scripts for the Python 3 container runtime.
**Imports**: pathlib
**Classes**: none
**Functions**: `patch_get_seq() -> None`; `patch_edit_predict() -> None`; `main() -> None`

### scripts/make_small_fastq_dataset.py
**Purpose**: Generate small example datasets from FASTQ(.gz) files. Modes: 1) Random sampling (default): sampl...
**Imports**: __future__, argparse, gzip, random, re, shutil, subprocess, sys, collections, dataclasses, pathlib, typing, pysam, tqdm
**Class** `GenomicInterval`: (no methods)
**Functions**: `open_maybe_gz(path: Path, mode: str)`; `normalize_qname(name: str) -> str`; `iter_fastq(path: Path) -> Iterator[FASTQRecord]`; `parse_fastq_name(header: bytes) -> str`; `write_fastq(records: Sequence[FASTQRecord], out_path: Path) -> None`; `reservoir_sample_single(in_r1: Path, n: int, seed: int) -> List[FASTQRecord]`; `reservoir_sample_paired(in_r1: Path, in_r2: Path, n: int, seed: int) -> List[Tuple[FASTQRecord, FASTQRecord]]`; `parse_gtf_gene_intervals(gtf: Path, genes: Set[str]) -> Tuple[DefaultDict[str, List[GenomicInterval]], Set[str]]`; +8 more

### scripts/sprint_to_deepred_vcf.py
**Purpose**: Convert SPRINT regular RES output into DeepRed candidate SNVs. DeepRed's upstream README document...
**Imports**: argparse, os
**Classes**: none
**Functions**: `parse_edit_type(raw_type, input_path, line_number)`; `convert_sprint_res_to_deepred_vcf(input_path, output_path)`; `main()`

### scripts/sprint_to_editpredict_positions.py
**Purpose**: Convert SPRINT regular RES output into EditPredict position input. EditPredict's upstream get_seq...
**Imports**: argparse, os
**Classes**: none
**Functions**: `normalize_chromosome(raw_chromosome)`; `convert_sprint_positions(input_path, output_path)`; `main()`

### tests/test_editing_wgs_dryrun.py
**Purpose**: no docstring
**Imports**: subprocess, tempfile, unittest, pathlib
**Class** `EditingWgsDryRunTest(unittest.TestCase)`: test_all_sample_instance_types_are_schedulable
**Functions**: none

### tests/test_sprint_to_deepred_vcf.py
**Purpose**: no docstring
**Imports**: tempfile, unittest, pathlib, scripts.sprint_to_deepred_vcf
**Class** `SprintToDeepRedVcfTest(unittest.TestCase)`: test_regular_res_rows_are_converted_to_ref_alt_vcf
**Functions**: none

## Dependency Graph
containers/editpredict/fix_upstream.py -> (none)
scripts/make_small_fastq_dataset.py -> (none)
scripts/sprint_to_deepred_vcf.py -> (none)
scripts/sprint_to_editpredict_positions.py -> (none)
tests/test_editing_wgs_dryrun.py -> (none)
tests/test_sprint_to_deepred_vcf.py -> scripts/sprint_to_deepred_vcf.py

## Statistics
Total files: 6
Total lines: 761
Languages: Python (6)
Estimated map tokens: ~808 (vs ~7,610 reading all files)
Compression ratio: 9x
