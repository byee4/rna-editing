# Exploration Report: Morales_et_al Containerization

Generated: 2026-05-05T22:10:00Z
Stage: 2-architect (explore sub-phase)

## Files Analyzed

### Targets of modification (5)

| Path | Lines | Current State |
|------|-------|---------------|
| `pipelines/Morales_et_all/Snakefile` | 21 | No `container_for`, no `SIF_DIR`/`CONTAINERS`, no helper imports |
| `pipelines/Morales_et_all/preprocessing.smk` | 56 | 3 rules (`trim_reads`, `star_mapping`, `mark_duplicates`); 0 container/log/resources directives |
| `pipelines/Morales_et_all/tools.smk` | 94 | 6 rules (`reditools`, `sprint`, `bcftools`, `red_ml`, `add_md_tag`, `jacusa2`); 0 container/log/resources directives |
| `pipelines/Morales_et_all/downstream.smk` | 59 | 5 rules; bare `python Downstream/*.py` shell calls; 0 directives |
| `pipelines/Morales_et_all/config.yaml` | 62 | `tools:` section with 6 user-home / cluster-specific paths; no `containers:` block; no `singularity_image_dir:`; no `downstream_scripts_dir:` |

### Targets of creation (8)

| Path | Purpose |
|------|---------|
| `containers/star/Dockerfile` | STAR 2.7.x + samtools (lean, separate from `lodei.sif`) |
| `containers/star/validate.sh` | Verify `STAR --version` and `samtools --version` |
| `containers/red_ml/Dockerfile` | Perl + R + RED-ML repository with `red_ML.pl` on PATH |
| `containers/red_ml/validate.sh` | Verify `perl --version`, `Rscript --version`, `red_ML.pl` invocable |
| `containers/fastx/Dockerfile` | FASTX-Toolkit via bioconda (`fastx_trimmer`) |
| `containers/fastx/validate.sh` | Verify `fastx_trimmer -h` |
| `containers/morales_downstream/Dockerfile` | Python 3.11 + pandas + numpy |
| `containers/morales_downstream/validate.sh` | Verify `python3 -c 'import pandas, numpy'` |

### Reference patterns (read-only)

| Path | Pattern Extracted |
|------|-------------------|
| `pipelines/editing_wgs/Snakefile` lines 14-25 | `SIF_DIR`, `CONTAINERS`, `container_for(tool)` helper |
| `pipelines/editing_wgs/rna_editing.smk` lines 6-29 | Rule with `container:`, `log: stdout=/stderr=`, `resources: mem_mb=lambda.../runtime=lambda...`, shell with `1> {log.stdout} 2> {log.stderr}` |
| `pipelines/editing_wgs/config.yaml` lines 12-23 | `singularity_image_dir:` + `containers:` block (one entry per tool key) |
| `containers/picard/Dockerfile` | `eclipse-temurin:17-jre-jammy` base; `LABEL`s; wget JAR; `COPY` wrapper to `/usr/local/bin/`; `WORKDIR /work` |
| `containers/wgs/Dockerfile` | `ubuntu:22.04` + apt-get for `bcftools samtools bwa tabix` |
| `containers/jacusa2/Dockerfile` | `condaforge/miniforge3` + mamba install; SHA-256 verification of downloaded JAR |
| `containers/sprint/Dockerfile` | `ubuntu:18.04` + Python 2.7 + git clone to `/opt/sprint/` |
| `containers/reditools/Dockerfile` | `python:2.7-buster` + apt + pip pinned; git clone to `/opt/reditools2/` |
| `containers/picard/validate.sh` | `set -euo pipefail`; tool `--version`; `tool --help > /tmp/...`; echo PASS |
| `containers/picard/picard` | `#!/usr/bin/env bash`; `set -euo pipefail`; `exec java -jar /opt/picard/picard.jar "$@"` |

## Integration Points

1. **TSCC profile (read-only)**: `profiles/tscc2/config.yaml` already declares `software-deployment-method: apptainer`. New rules using `container:` will pick this up automatically. Default `mem_mb=20000` and `runtime=30` apply when a rule omits resources; rules below set explicit values.
2. **Bind paths**: `apptainer-args: "--bind /tscc/projects/,/tscc/nfs/home/,/cm,/etc/passwd"`. Reference paths in `config.yaml` must remain under `/tscc/projects/` or `/tscc/nfs/home/` to be readable inside containers.
3. **`scripts/validate_containers.sh`**: Discovers containers by directory name under `containers/`. New tools added via `TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh`. The script expects `containers/<tool>/Dockerfile` and `containers/<tool>/validate.sh` and runs `validate-<tool>` inside the SIF.
4. **Empty git submodule**: `Benchmark-of-RNA-Editing-Detection-Tools/` is configured as a submodule but contains no scripts in the working checkout. The downstream rules will reference scripts under this path via `config["downstream_scripts_dir"]`. Snakemake dry-run does not validate file existence at planning time.

## Constraints Identified

| # | Constraint | Source |
|---|-----------|--------|
| C-A | Snakemake 9+ requires `container:` (not deprecated `singularity:`) | Requirements NFR-1, technical-constraints.md |
| C-B | All shell blocks with pipes (`|`) require `set -euo pipefail` | Requirements FR-7, EC-2 |
| C-C | No `~/bin/` or `/binf-isilon/` paths anywhere in committed source | Requirements SEC-1, AC-3 |
| C-D | New SIF names must match `containers:` keys (`star.sif`, `red_ml.sif`, `fastx.sif`, `morales_downstream.sif`) | `container_for()` fallback is `{SIF_DIR}/{tool}.sif` |
| C-E | Existing 5 containers (picard, reditools, sprint, wgs, jacusa2) must not be modified | Requirements §5.4, no-change list |
| C-F | `add_md_tag` uses `wgs` container (not `jacusa2`), per C-005 | Requirements FR-20, AC-17 |
| C-G | `mark_duplicates` must call `picard MarkDuplicates` wrapper, not `java -jar` | Requirements FR-8, AC-8, EC-3 |
| C-H | `jacusa2` rule has no wildcards; log path uses literal name (`results/logs/jacusa2.{out,err}`) | EC-5 |
| C-I | All 5 downstream rules have no per-sample wildcards; log paths use rule names | EC-6 |
| C-J | Resource directives must use `lambda wildcards, attempt:` for retry-aware backoff | Requirements §6 (NFR-5), context/09 |
| C-K | `--bind` mount paths in TSCC profile already include `/tscc/projects/`, `/tscc/nfs/home/`, `/cm`; no profile changes | Requirements compatibility constraint |
| C-L | Total directive count: 14 `container:`, 14 `log:`, 14 `resources:` (3 + 6 + 5 = 14 rules) | Requirements AC-4/5/6 |

## Patterns to Follow

1. **Header pattern** (`Snakefile`): Add `import os`, `import re`; read `SIF_DIR = config.get("singularity_image_dir", "<default>")`, `CONTAINERS = config.get("containers", {})`; define `container_for(tool)`.
2. **Rule directive ordering**: `input:` -> `output:` -> `threads:` -> `resources:` -> `container:` -> `log:` -> `params:` -> `shell:` (matches editing_wgs convention).
3. **Log redirection in shell**: Append `1> {log.stdout} 2> {log.stderr}` to single-command rules; for multi-command rules use `2>> {log.stderr}` for subsequent commands.
4. **Resources defaults** (from context/09): see Resource Defaults Table.
5. **Dockerfile skeleton**: `FROM <base>` -> `LABEL title+description` -> `ENV DEBIAN_FRONTEND=noninteractive` (or equivalent) -> `RUN apt/mamba install ...` -> `RUN install tool to /opt/<tool>/` -> `COPY validate.sh /usr/local/bin/validate-<tool>` -> `RUN chmod +x ...` -> `WORKDIR /work` -> `CMD ["validate-<tool>"]`.
6. **Validate script skeleton**: `#!/usr/bin/env bash` -> `set -euo pipefail` -> `<tool> --version` (or equivalent) -> `echo "<Tool> validation passed"`.

## Key Findings (ranked by importance)

1. **The architecture is mostly fixed by requirements.** FR-1..FR-20 specify exact mechanics for every rule and config change; C-001..C-005 in conflicts-resolved.md commit to the canonical resolution. This is a retrofit task, not a green-field design. Architectural variation is bounded to (a) base-image selection for the 4 new Dockerfiles, (b) log-path style (split stdout/stderr files vs. one combined `.log`), and (c) task-decomposition order/granularity.
2. **`mark_duplicates` wrapper substitution is the single highest-risk shell change.** The current rule passes the JAR path as a parameter; the new rule must call the `picard` wrapper script that the container places at `/usr/local/bin/picard`. If the wrapper isn't on PATH inside the SIF, the rule silently fails at execution. Verified that `containers/picard/Dockerfile` line 17 copies the wrapper.
3. **RED-ML Dockerfile is the most complex new container.** It requires Perl 5, R, and at minimum the R packages `caret`, `data.table`, `ROCR`, `randomForest`. CRAN package versions can drift; pinning is required.
4. **Empty downstream submodule cannot be solved at architect/build time.** Only mitigation is a `config.yaml` comment instructing users to run `git submodule update --init`. Dry-run will pass with empty submodule; only execution fails.
5. **`add_md_tag` and `bcftools` share the `wgs` container.** Per C-005 resolution, samtools and bcftools are both in the `wgs` SIF (apt-installed on `ubuntu:22.04`). No new container is needed for these two rules.
6. **`star_mapping` needs `set -euo pipefail` even though FR-7 only mentions `bcftools`.** G-2 in the open gaps ledger closes this: the piped `samtools view | samtools sort` chain must be guarded too. This appears in EC-2 mitigation. The architect plan must include this.
7. **Hotspot register is irrelevant.** Top-churn files are unrelated test scripts in `tests/` and `scripts/`. No high-churn `.smk` files exist for this pipeline.

## Conflicts Already Resolved (do not re-litigate)

| ID | Topic | Resolution |
|----|-------|-----------|
| C-001 | RED vs RED-ML | Create new `containers/red_ml/`; do not reuse `containers/red/` |
| C-002 | STAR container | Create new `containers/star/` (lean STAR + samtools); don't reuse `lodei.sif` |
| C-003 | Downstream submodule | Add `downstream_scripts_dir:` config + `params.downstream_dir`; document submodule init |
| C-004 | `tools:` section | Remove entirely from config.yaml; replace with `containers:` block |
| C-005 | `add_md_tag` container | Use `wgs` (not `jacusa2`); aligns with `bcftools` |

## Open Items for Design Phase

1. **Log path convention**: D-5 in architect-prompt — choose `results/logs/{condition}_{sample}.{rule}.out`/`.err` (matches editing_wgs `WORKDIR + "/logs/{sample}.{rule}.out"`). Rule for jacusa2 (no wildcards): literal `results/logs/jacusa2.out/.err`. Rule for downstream (no wildcards): literal `results/logs/{rulename}.out/.err`.
2. **Base image selection** for 4 new Dockerfiles: see ADRs.
3. **Task decomposition order**: produce sequential plan with explicit dependencies between Snakefile, config.yaml, and `.smk` files. Container Dockerfiles can be built in parallel once they don't depend on `.smk` changes.

Ready for design phase: YES.
