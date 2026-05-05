# Technical Constraints

## Snakemake Version

- **Version**: Snakemake 9+ (confirmed by `profiles/tscc2/config.yaml` using `software-deployment-method`)
- **Deprecated**: `--use-singularity` flag → replaced by `--software-deployment-method apptainer`
- **Deprecated**: `singularity:` rule directive → replaced by `container:`
- **Deprecated**: `workflow.basedir` → replaced by `workflow.source_path(".")`
- **Active**: `container: container_for("toolname")` is the correct directive

## TSCC Profile Constraints (`profiles/tscc2/config.yaml`)

```yaml
software-deployment-method:
  - apptainer
  - conda
  - env-modules
executor: slurm
default-resources:
  slurm_partition: "condo"
  slurm_account: "csd792"
  runtime: 30
  mem_mb: 20000
  slurm_extra: "--qos=condo"
apptainer-args: "--bind /tscc/projects/,/tscc/nfs/home/,/cm,/etc/passwd"
jobs: 30
```

Key constraint: The `--bind` arguments expose `/tscc/projects/` and `/tscc/nfs/home/` inside containers. Reference genome paths must be under these prefixes to be accessible inside containers.

## Container Infrastructure

- SIF files live in `singularity/` at the repo root
- New SIF names (from new Dockerfiles): `star.sif`, `red_ml.sif`, `fastx.sif`, `morales_downstream.sif`
- Existing SIF names (reused): `picard.sif`, `reditools.sif`, `sprint.sif`, `wgs.sif`, `jacusa2.sif`
- The `container_for()` helper falls back to `{SIF_DIR}/{tool}.sif` if no explicit entry in CONTAINERS dict

## Shell Safety

- All shell blocks with pipes (`|`) must include `set -euo pipefail`
- Affected rules: `bcftools`, `star_mapping` (piped samtools commands)
- Best practice: Add `set -euo pipefail` to ALL multi-command shell blocks

## File Path Constraints

- No hardcoded user paths (`~/`, `/binf-isilon/`, other cluster-specific absolute paths)
- Reference genome paths in `config.yaml` are user-supplied (they SHOULD be absolute paths to local files; these are not committed secrets)
- Downstream scripts path: relative to pipeline directory via `config["downstream_scripts_dir"]`

## Snakemake Rule Constraints

- Rule names must be unique across all included `.smk` files
- `log:` directive paths must be deterministic (no random components)
- `resources:` values must be numeric or return numeric from lambdas
- `container:` must be a string path to a `.sif` file (or Docker URI, but `.sif` preferred for HPC)

## Docker/Apptainer Build Constraints

- Build platform: linux/amd64 (TSCC is x86_64)
- No network access during container execution
- Container must work when run with Apptainer's default security model (no `--privileged`)
- WORKDIR convention: `/work` (matches all existing containers in this repo)

## Git Submodule Constraint

- `Benchmark-of-RNA-Editing-Detection-Tools/` is an empty submodule stub
- Downstream script paths are committed as relative paths pointing into this submodule
- Initialization requires: `git submodule update --init` (documented in config.yaml comment)
- This task does NOT initialize the submodule or add the scripts directly

## No Changes to These Files

- `pipelines/editing_wgs/` (any file)
- `profiles/tscc2/config.yaml`
- `containers/picard/`, `containers/reditools/`, `containers/sprint/`, `containers/wgs/`, `containers/jacusa2/` (existing containers)
- `singularity/` (SIF files — build artifacts, not source)
