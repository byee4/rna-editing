# PRD: Morales_et_al Pipeline — Snakemake 9+ Correctness & Containerization

## Objective

Bring the `pipelines/Morales_et_all/` Snakemake pipeline to Snakemake 9+ compliance and add container fields for every rule, creating missing Dockerfiles where needed. Ensure Python and Bash scripts are discoverable via config or `workflow.source_path()` rather than hardcoded user-home paths.

## Scope

Files to change:
- `pipelines/Morales_et_all/Snakefile`
- `pipelines/Morales_et_all/preprocessing.smk`
- `pipelines/Morales_et_all/tools.smk`
- `pipelines/Morales_et_all/downstream.smk`
- `pipelines/Morales_et_all/config.yaml`

New files to create:
- `containers/star/Dockerfile` (STAR 2.7.x + samtools)
- `containers/red_ml/Dockerfile` (Perl + R + RED-ML)
- `containers/fastx/Dockerfile` (FASTX-Toolkit)
- `containers/morales_downstream/Dockerfile` (Python 3 + pandas/numpy for Downstream scripts)

## Acceptance Criteria

1. `snakemake --lint` passes on all four .smk files with no errors.
2. `snakemake -n` (dry-run) completes without errors when run from `pipelines/Morales_et_all/`.
3. Every rule has a `container:` directive pointing to a valid `{tool}.sif` via `container_for()`.
4. Every rule has a `log:` directive.
5. `config.yaml` contains a `containers:` block and a `singularity_image_dir:` key matching the editing_wgs pattern.
6. No rule references `~/bin/...` hardcoded paths; all tool executables are resolved from the container image.
7. `Downstream/*.py` scripts are resolved via `config["downstream_scripts_dir"]` or `workflow.source_path()`.
8. Four new Dockerfiles exist (`star`, `red_ml`, `fastx`, `morales_downstream`) with validate scripts.
9. `shell:` commands using pipes include `set -euo pipefail`.

## Non-Goals

- Changing the editing_wgs pipeline (separate pipeline, already containerized).
- Building or validating SIF files (that's a post-commit step).
- Running the pipeline on real data.
