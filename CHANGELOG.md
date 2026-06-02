# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added

- **MARINE (marine.py) integration** into the Morales_et_al benchmark suite. New container `containers/marine/` (`marine.sif`, conda env `marine`) and rules in `rules/tools.smk`: `split_marine_md_bam_by_chrom`, `marine_by_chrom`, `join_marine_output`, `filter_marine_by_edit_type`, plus `generate_marine_annotation` in `rules/references.smk`. MARINE runs per-chromosome on the MD-tagged BAM (mirroring REDItools), with `--cores` matched to rule threads, `--strandedness` (default 2) and `--min_read_quality` (20) from config, `--min_base_quality` harmonized to `params.common.base_quality`, and `--paired_end` set per-sample via `is_paired()`.
- **Edit-type filtering for MARINE**: the genome-wide, all-conversion `final_filtered_site_info.tsv` is gzipped, and `filter_marine_by_edit_type` derives a per-edit-type TSV (`final_filtered_site_info.<EDIT_TYPE>.tsv`, e.g. `A>G` from `params.common.edit_type`). The edit type is encoded in the filename so a change to `edit_type` regenerates only the filter step (the TSCC profile uses `rerun-triggers: mtime`).
- MARINE wired into the cross-tool comparison matrices, intersection/correlation, consensus analysis, and BigBed/trackhub outputs (added to `_BED_TOOLS`).

### Fixed

- `containers/marine/validate.sh` pointed at a non-existent `marine.py` path and used `conda run`; corrected to call `/opt/marine/marine.py` via the env's Python with writable `NUMBA_CACHE_DIR`/`MPLCONFIGDIR`.
- `parse_marine` (`scripts/compare_all_tools.py`) and `to_bed_marine` (`scripts/tool_output_to_bed.py`) read non-existent `editing_type`/`edit_frequency` columns; updated to MARINE's actual `strand_conversion`/`count`/`coverage` columns, computing edit fraction as `count / coverage`.

## [0.2.0] - 2026-05-07

### Added

- **Morales_et_all pipeline — full Snakemake 9+ containerization**: All 22 non-localrule rules now have `container:`, `log:`, and `resources:` directives, making the pipeline compatible with `software-deployment-method: apptainer` on TSCC.
- **Four new container build contexts**: `containers/star/` (STAR 2.7.11a + SAMtools), `containers/red_ml/` (RED-ML on rocker/r-ver:4.3.2), `containers/fastx/` (FASTX-Toolkit via bioconda), `containers/morales_downstream/` (Python 3.11 + pandas/numpy/scipy).
- **Samplesheet-driven config**: `Snakefile` reads `samplesheet.csv` at runtime; `conditions` and `samples` config keys are populated dynamically. Single-end and paired-end samples are auto-detected per row.
- **Reference database generation rules** (`rules/references.smk`): `generate_simple_repeat`, `generate_alu_bed`, and `build_dbrna_editing` produce the three JSON databases required by the downstream analysis scripts.
- **WGS alignment sub-pipeline** (`rules/wgs.smk`): `wgs_bwa_mem`, `wgs_deduplicate`, `wgs_md_tags`, `wgs_call_variants`, and `wgs_vcf_to_ag_tc_bed` align WGS FASTQs and produce a filtered A>G / T>C SNP BED for database construction. Activated when `wgs_samples` is set in `config.yaml`.
- **`scripts/build_downstream_dbs.py`**: Builds `HEK293T_hg38_clean.json`, `REDIportal.json`, and `Alu_GRCh38.json` from WGS SNP BED, REDIportal table, and Alu BED inputs. Supports gzip-compressed REDIportal input.
- **`container_for()` helper and `CONTAINERS`/`SIF_DIR` globals** in `Snakefile`: mirrors the `editing_wgs` convention; allows per-tool SIF override via `config["containers"]`.
- **Picard dynamic heap**: `mark_duplicates` uses `_JAVA_OPTIONS="-Xmx{params.mem_mb_heap}m"` with heap at 75 % of SLURM-allocated `mem_mb`.
- **`set -euo pipefail`** added to all shell rules in `pipelines/Morales_et_all/`.
- **Wildcard constraints** on `condition`, `sample`, `wgs_sample` to prevent path-crossing.
- **QA test suite** (`tests/test_morales_pipeline_spec.py`): 37 spec-derived tests covering all 17 architecture ACs plus RED-ML URL, config structure, and BGIRED URL verification.
- **spec-deviations.json**: Records RED-ML GitHub URL change from `BGI-shenzhen/RED-ML` to `BGIRED/RED-ML` (BGI-shenzhen returns 404).
- **Architecture addendum** (`.forge/stages/2-architect/architecture-addendum.md`): Formally ratifies the 8 post-implementation rules and three new decisions (D-13 samplesheet driver, D-14 WGS integration, D-15 reference DB generation).

### Changed

- `pipelines/Morales_et_all/config.yaml`: Replaced `tools:` block (user-specific `~/bin/` paths) with `containers:` block (9 SIF paths) and added `downstream_scripts_dir` and `wgs_samples` keys.
- `mark_duplicates` shell: switched from `java -jar ~/bin/picard-tools/MarkDuplicates.jar` to `picard MarkDuplicates` (wrapper at `/usr/local/bin/picard` in `picard.sif`).
- `reditools`, `sprint`, `bcftools`, `red_ml`, `add_md_tag`, `jacusa2` shells: removed `params.script`, `params.sprint_bin`, `params.jacusa_jar`, `params.samtools_bin`; tools now resolve via container PATH or fixed `/opt/` paths.
- Downstream rules: replaced `python Downstream/<script>.py` with `python {params.downstream_dir}/<script>.py`.
- `star_mapping`: added `--outSAMattrRGline` for read group tags required by Picard MarkDuplicates.

### Removed

- `tools:` section from `config.yaml` (contained user-home and `binf-isilon` paths, non-reproducible).

---

## Older History

Prior to the Snakemake 9 containerization work, the repository history includes:

- `editing_wgs` pipeline: full matched RNA/WGS workflow with STAR, BWA, SPRINT, REDItools2/REDInet, JACUSA2 (DeepRED and editPredict deactivated pending container resolution).
- Container builds for: `picard`, `reditools`, `sprint`, `wgs` (BWA + SAMtools + BCFtools), `jacusa2`, `lodei` (STAR), `deepred`, `editpredict`, `redinet`.
- `scripts/sprint_to_deepred_vcf.py`, `scripts/sprint_to_editpredict_positions.py`: SPRINT RES → DeepRED VCF and EditPredict TSV adapters.
- `containers/editpredict/fix_upstream.py`: Python 3 patches for EditPredict upstream scripts.
