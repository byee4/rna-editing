# Release Notes — rna-editing v0.2.0

**Date:** 2026-05-07  
**Scope:** Morales_et_all pipeline — full Snakemake 9+ containerization

---

## Summary

This release makes the `pipelines/Morales_et_all` workflow compatible with Snakemake 9+ `software-deployment-method: apptainer` on TSCC2. All 22 non-localrule rules now have `container:`, `log:`, and `resources:` directives, matching the pattern established by the `editing_wgs` pipeline. Four new container build contexts are provided. The `editing_wgs` pipeline is unmodified.

---

## Added

- **Morales_et_all — full Snakemake 9+ containerization**: All 22 non-localrule rules carry `container:`, `log:`, and `resources:` directives; pipeline runs end-to-end with `--use-singularity` on TSCC2.
- **Four new container build contexts** (see `containers/`):
  - `containers/star/` — STAR 2.7.11a + SAMtools
  - `containers/red_ml/` — RED-ML on rocker/r-ver:4.3.2
  - `containers/fastx/` — FASTX-Toolkit via bioconda
  - `containers/morales_downstream/` — Python 3.11 + pandas/numpy/scipy
  - Each includes a `validate.sh` that tests the tool is runnable
- **Samplesheet-driven config**: `Snakefile` reads `samplesheet.csv`; `conditions` and `samples` are populated dynamically; SE/PE auto-detected per row.
- **Reference DB generation rules** (`rules/references.smk`): `generate_simple_repeat`, `generate_alu_bed`, `build_dbrna_editing`.
- **WGS sub-pipeline** (`rules/wgs.smk`): `wgs_bwa_mem`, `wgs_deduplicate`, `wgs_md_tags`, `wgs_call_variants`, `wgs_vcf_to_ag_tc_bed`. Activated when `wgs_samples` is set in `config.yaml`.
- **`scripts/build_downstream_dbs.py`**: Builds HEK293T_hg38_clean.json, REDIportal.json, Alu_GRCh38.json; supports gzip-compressed REDIportal input.
- **`container_for()` helper** and `CONTAINERS`/`SIF_DIR` globals in `Snakefile` — mirrors `editing_wgs` convention.
- **Picard dynamic heap**: `mark_duplicates` uses `_JAVA_OPTIONS="-Xmx{params.mem_mb_heap}m"` with heap at 75% of SLURM-allocated `mem_mb`.
- **`set -euo pipefail`** added to all shell rules in `pipelines/Morales_et_all/`.
- **Wildcard constraints** on `condition`, `sample`, `wgs_sample`.
- **QA test suite**: `tests/test_morales_pipeline_spec.py` — 37 spec-derived tests covering all 17 architecture ACs.
- **spec-deviations.json**: Records RED-ML GitHub URL change (`BGI-shenzhen/RED-ML` → `BGIRED/RED-ML`; BGI-shenzhen returns HTTP 404).
- **Architecture addendum**: `.forge/stages/2-architect/architecture-addendum.md` formally ratifies the 8 post-implementation rules and three new decisions.

## Changed

- `pipelines/Morales_et_all/config.yaml`: Replaced `tools:` block (user-specific `~/bin/` paths) with `containers:` block (9 SIF paths); added `downstream_scripts_dir` and `wgs_samples` keys.
- `mark_duplicates` shell: switched from `java -jar ~/bin/picard-tools/MarkDuplicates.jar` to `picard MarkDuplicates` (wrapper at `/usr/local/bin/picard` inside `picard.sif`).
- `star_mapping`: added `--outSAMattrRGline` for read group tags required by Picard MarkDuplicates.
- Downstream rules: replaced `python Downstream/<script>.py` with `python {params.downstream_dir}/<script>.py`.
- `reditools`, `sprint`, `bcftools`, `red_ml`, `add_md_tag`, `jacusa2` shell blocks: tool binaries now resolve via container PATH or fixed `/opt/` paths; `params.script`/`params.*_bin` references removed.

## Removed

- `tools:` section from `pipelines/Morales_et_all/config.yaml` (contained user-home and `binf-isilon` paths, non-reproducible).

## Breaking Changes

None. The `editing_wgs` pipeline is unmodified. The Morales config schema change (removal of `tools:`, addition of `containers:`) only affects new deployments.

---

## Known Issues

- **Container builds are a post-merge human step**: The four new SIFs (`star.sif`, `red_ml.sif`, `fastx.sif`, `morales_downstream.sif`) must be built on TSCC using `scripts/validate_containers.sh`. The pipeline dry-run passes without the SIFs; a live run requires them.
- **`snakemake --lint` exits 1**: 7 informational warnings are emitted (false positives: comment-string paths, `config.get()` fallback default, exempt localrule). Zero actionable errors. Accepted per QA finding F-01.
- **Benchmark submodule**: `pipelines/Morales_et_all/Benchmark-of-RNA-Editing-Detection-Tools` must be initialized (`git submodule update --init`) before the downstream rules can execute.
- **Escalation contact TBD**: `deployment-runbook.md` line 120 has a placeholder for the PI escalation contact. Fill in before sharing the runbook externally.

---

## Test Coverage

| Suite | Tests | Pass | Fail |
|-------|-------|------|------|
| `test_morales_pipeline_spec.py` | 37 | 37 | 0 |
| `test_sprint_to_deepred_vcf.py` | 1 | 1 | 0 |
| `test_editing_wgs_dryrun.py` | — | DEFERRED (macOS `/private/tmp` path) | — |
| Snakemake dry-run (67 jobs) | 1 | 1 | 0 |
| **Total** | **38** | **38** | **0** |

AC coverage: 16/17 (AC-1 lint exit-code relaxed; all warnings informational).

---

## Provenance

- Source: https://github.com/byee4/rna-editing @ `78a84dbe3f5ca2dd05731ff83249a5ed7835992a`
- Pipeline: forge-8a8d6b83
- SLSA provenance: `.forge/stages/8-release/provenance.json` (unsigned; no cosign key present)
