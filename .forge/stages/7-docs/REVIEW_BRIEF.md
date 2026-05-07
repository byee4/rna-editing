# Review Brief: Morales_et_al Pipeline — Snakemake 9+ Containerization

## What Changed

- All 22 non-localrule rules in `pipelines/Morales_et_all/` now have `container:`, `log:`, and `resources:` directives, making the pipeline fully compatible with Snakemake 9 and the TSCC `apptainer` deployment method.
- All user-specific tool paths (`~/bin/`, `/binf-isilon/`) removed from pipeline files; containers provide all tools.
- Four new container build contexts added: `containers/star/`, `containers/red_ml/`, `containers/fastx/`, `containers/morales_downstream/`.
- Samplesheet-driven config added (runtime CSV replaces hard-coded `conditions`/`samples` lists); SE/PE mode auto-detected per sample.
- Three new rule modules added post-implementation: `rules/references.smk` (reference DB generation), `rules/wgs.smk` (WGS alignment and variant calling for SNP DB), and `scripts/build_downstream_dbs.py` (JSON DB builder).

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Direct Retrofit (Approach A) | Mirrors `editing_wgs` convention exactly; smallest diff surface; no out-of-scope changes to the primary pipeline. |
| `container_for(tool)` helper | Consistent with `editing_wgs/Snakefile`; allows per-tool SIF override via `config["containers"]` with a `{SIF_DIR}/{tool}.sif` fallback. |
| `lambda wildcards, attempt: BASE * (1.5 ** (attempt - 1))` resources | Enables Snakemake's retry-on-OOM mechanism; mem floors are tool-specific (32 GB for STAR/JACUSA2, 16 GB for RED-ML/build_dbrna_editing). |
| Two-handle log pattern (`stdout=`, `stderr=`) | Enables independent triage of stdout and stderr on SLURM; matches `editing_wgs` convention. |
| `wgs_samples` key controls WGS rule scheduling | `_WGS_DB_FILES = []` when absent; entire WGS sub-DAG (5 rules) is not scheduled, preventing MissingInputException for users without WGS data. |

## Risk Areas

| File | Risk | Reason |
|------|------|--------|
| `pipelines/Morales_et_all/rules/references.smk` | MEDIUM | `build_dbrna_editing` uses the `morales_downstream` container and calls `scripts/build_downstream_dbs.py` via a relative path (`workflow.basedir`). Path is correct but fragile if workflow is invoked from an unexpected directory. |
| `pipelines/Morales_et_all/downstream.smk` | MEDIUM | All five rules call Python scripts from the Benchmark git submodule. Submodule is empty by default; runtime failure if `git submodule update --init` is not run. This is documented in `config.yaml` comments but not enforced at DAG time. |
| `containers/red_ml/Dockerfile` | LOW | Uses `BGIRED/RED-ML` (not the original `BGI-shenzhen/RED-ML` specified in the original architecture plan). URL deviation is recorded in `spec-deviations.json` D-RED-ML-URL. |
| `pipelines/Morales_et_all/Snakefile` | LOW | `snakemake --lint` exits 1 with 7 informational warnings (false positives + exempt localrule). All warnings are documented; none indicate functional defects. |
| `containers/picard/Dockerfile` | LOW | `mark_duplicates` uses the `picard` wrapper at `/usr/local/bin/picard`. If that wrapper is absent in the SIF, the rule silently fails. Wrapper presence is verified by the existing picard `validate.sh`. |

## Test Coverage

- **Automated**: 38 tests total (1 pre-existing + 37 spec-derived)
  - `tests/test_sprint_to_deepred_vcf.py`: 1 test — PASS
  - `tests/test_morales_pipeline_spec.py`: 37 tests covering all 17 original ACs plus BGIRED URL, submodule config, and config structure — 37/37 PASS
- **Exploratory**: 6 scenarios (happy path, config resolution, negative user-path grep, negative old-params grep, localrule exemption, RED-ML URL deviation)
- **Known gap**: AC-1 (`snakemake --lint` exit 0) is FAIL on exit code; all 7 lint warnings are accepted as informational. AC criterion should be relaxed to "0 actionable errors" per QA report §5.

## Open Items

| Item | Severity | Notes |
|------|----------|-------|
| AC-1 lint exit code | MINOR | `snakemake --lint` exits 1 with 7 informational warnings. QA recommends relaxing AC-1 to "0 actionable errors". No functional impact. |
| Container build (SIF files) | MEDIUM | Four new SIFs (`star`, `red_ml`, `fastx`, `morales_downstream`) must be built post-merge by a human running `TOOLS="..." scripts/validate_containers.sh`. Not gated by CI. |
| task-07 stale BGI-shenzhen references | MINOR | `.forge/stages/2-architect/tasks/task-07-container-red_ml.md` lines 24/75/89 still reference `BGI-shenzhen/RED-ML`. Tracked by `spec-deviations.json` D-RED-ML-URL. Canonical artifacts are correct. |
| Empty submodule runtime enforcement | LOW | No DAG-time check that the Benchmark submodule is populated. Users must read config.yaml comment. |

## Files to Focus On

| File | Lines Changed | What It Does | Risk |
|------|--------------|--------------|------|
| `pipelines/Morales_et_all/Snakefile` | +70 | Adds samplesheet loader, `container_for()`, `is_paired()`, new module includes, wildcard constraints | MEDIUM (samplesheet integration) |
| `pipelines/Morales_et_all/preprocessing.smk` | +100 | 3 rules: `prepare_fastq`, `trim_reads`, `star_mapping`, `mark_duplicates` with containers/log/resources | LOW |
| `pipelines/Morales_et_all/tools.smk` | +130 | 6 rules: reditools, sprint, bcftools, red_ml, add_md_tag, jacusa2 | LOW |
| `pipelines/Morales_et_all/downstream.smk` | +130 | 5 rules: all downstream analysis, all using `morales_downstream` container | MEDIUM (submodule dep) |
| `pipelines/Morales_et_all/rules/references.smk` | +120 | 3 rules: generate_simple_repeat, generate_alu_bed, build_dbrna_editing | MEDIUM (path resolution) |
| `pipelines/Morales_et_all/rules/wgs.smk` | +155 | 5 rules: WGS alignment through VCF → BED conversion | LOW |
| `pipelines/Morales_et_all/config.yaml` | +50 | Adds containers block, wgs_samples, downstream_scripts_dir; removes tools block | MEDIUM (all paths live here) |
| `containers/star/Dockerfile` | +25 | STAR 2.7.11a + SAMtools on ubuntu:22.04 | LOW |
| `containers/red_ml/Dockerfile` | +30 | RED-ML on rocker/r-ver:4.3.2 | LOW (BGIRED URL) |
| `containers/fastx/Dockerfile` | +20 | fastx_toolkit via bioconda on miniforge3 | LOW |
| `containers/morales_downstream/Dockerfile` | +20 | Python 3.11 with pandas/numpy/scipy | LOW |

## How to Verify

1. Dry-run from the pipeline directory:
   ```bash
   cd pipelines/Morales_et_all && snakemake -n --snakefile Snakefile --configfile config.yaml --cores 1
   ```
   Expected: exit 0, 67 jobs planned.

2. Run the test suite:
   ```bash
   python -m unittest tests/test_sprint_to_deepred_vcf.py tests/test_morales_pipeline_spec.py
   ```
   Expected: 38 tests, 0 failures.

3. Post-merge (human step): build and validate four new SIFs:
   ```bash
   TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh
   ```
   Expected: all four `validate-<tool>` scripts exit 0.
