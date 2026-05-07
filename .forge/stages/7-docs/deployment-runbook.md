# Deployment Runbook: rna-editing / Morales_et_al Pipeline

## Prerequisites

- [ ] TSCC HPC account with access to `csd792` allocation (`condo` partition)
- [ ] Apptainer/Singularity available (`module load singularitypro`)
- [ ] Snakemake 9 conda environment active (`conda activate snakemake9`)
- [ ] Reference files at paths listed in `config.yaml` under `references:`
- [ ] Samplesheet CSV at `pipelines/Morales_et_all/samplesheet.csv`
- [ ] Four new SIF files built (see Build New Container SIFs below)
- [ ] Git submodule initialized if running downstream rules (see Submodule below)

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `CONTAINER_DATA_ROOT` | No | Root directory for Docker build outputs and SIF output | `/Volumes/X9Pro/container_data` (default) |
| `SIF_OUTPUT_DIR` | No | Directory where `.sif` files are written by `validate_containers.sh` | `${CONTAINER_DATA_ROOT}/singularity_images` (default) |
| `DOCKER_PLATFORM` | No | Docker build platform target; use `linux/amd64` on Apple Silicon | `linux/amd64` |
| `TOOLS` | No | Space-separated list of container directories to build/validate | `star red_ml fastx morales_downstream` |
| `SLURM_JOB_ID` | No | Unset this on interactive nodes to allow Snakemake to submit SLURM jobs | — |

## Build New Container SIFs

The four new containers introduced by the Morales_et_al pipeline must be built before the pipeline runs. Run from the repository root:

```bash
module load singularitypro
TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh
```

Copy the resulting `.sif` files to `singularity/` (or update `singularity_image_dir` in `config.yaml`):

```bash
cp /path/to/sif/output/star.sif singularity/
cp /path/to/sif/output/red_ml.sif singularity/
cp /path/to/sif/output/fastx.sif singularity/
cp /path/to/sif/output/morales_downstream.sif singularity/
```

## Initialize the Downstream Submodule (if running downstream rules)

```bash
git submodule update --init pipelines/Morales_et_all/Benchmark-of-RNA-Editing-Detection-Tools
```

Without this step, the five downstream rules (`run_downstream_parsers`, `update_alu`, `individual_analysis`, `reanalysis_multiple`, `multiple_analysis`) will fail because the Python scripts they call are in the submodule.

## Pre-Deployment Checklist

1. Verify all four new SIFs exist in `singularity/`:
   ```bash
   ls -lh singularity/star.sif singularity/red_ml.sif singularity/fastx.sif singularity/morales_downstream.sif
   ```
2. Verify existing SIFs exist: `picard.sif`, `sprint.sif`, `reditools.sif`, `wgs.sif`, `jacusa2.sif`
3. Verify reference files are accessible (spot-check):
   ```bash
   ls -lh /tscc/projects/ps-yeolab3/bay001/annotations/GRCh38/GRCh38_no_alt_analysis_set_GCA_000001405.15.fasta
   ```
4. Verify samplesheet is present and well-formed:
   ```bash
   head -5 pipelines/Morales_et_all/samplesheet.csv
   ```
5. Dry-run to confirm DAG is valid:
   ```bash
   cd pipelines/Morales_et_all
   snakemake -n --snakefile Snakefile --configfile config.yaml --cores 1
   ```

## Run Steps

Run from the pipeline directory:

```bash
module load singularitypro
conda activate snakemake9
cd pipelines/Morales_et_all
unset SLURM_JOB_ID

snakemake -kps Snakefile \
  --configfile config.yaml \
  --profile /tscc/nfs/home/bay001/projects/codebase/rna-editing/profiles/tscc2 \
  --use-singularity
```

The TSCC profile (`profiles/tscc2/config.yaml`) submits jobs via SLURM to the `condo` partition with the `csd792` account.

## Post-Run Verification

1. Check that the final target exists:
   ```bash
   ls -lh results/downstream/multiple_analysis.done
   ```
2. Check for any SLURM failures:
   ```bash
   ls slurm_logs/*.err | xargs grep -l "Error\|error\|FAILED" 2>/dev/null
   ```
3. Verify reference databases were created (if `wgs_samples` was configured):
   ```bash
   ls -lh data/dbRNA-Editing/*.json
   ```

## Rollback Procedure

The pipeline is idempotent. To rerun from scratch:

```bash
rm -rf results/
snakemake -kps Snakefile --configfile config.yaml --profile /path/to/tscc2 --use-singularity
```

To rerun a specific rule:
```bash
snakemake --snakefile Snakefile --configfile config.yaml --cores 1 --forcerun <rule_name>
```

## Incident Contacts

- On-call: Brian Yee (brian.alan.yee@gmail.com)
- Escalation: TBD (project PI)
