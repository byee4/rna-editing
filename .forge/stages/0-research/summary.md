# Stage 0 Research Summary

The Morales_et_all pipeline (4 .smk files, 1 config) was audited for Snakemake 9+ compliance and containerization gaps.

**Critical finding**: Not a single one of the 9 rules in the pipeline has a `container:` directive. The `config.yaml` tools section references `~/bin/` paths that are user-specific and break in containers or on other machines. There is no `container_for()` helper or `containers:` config block — both patterns exist in the sibling `editing_wgs` pipeline and should be adopted here.

**Container gap summary**: 4 new Dockerfiles needed (STAR+samtools, RED-ML Perl/R, FASTX-Toolkit, Downstream Python scripts). 5 existing containers are reusable: `picard`, `reditools`, `sprint`, `wgs` (for samtools/bcftools rules), `jacusa2`.

**Key confusion**: `containers/red/` is for RED (Java app), NOT for RED-ML (Perl+R). These are different tools. The Morales `red_ml` rule calls `red_ML.pl` and needs a new container.

**Script discoverability**: `downstream.smk` calls `python Downstream/*.py` with bare relative paths pointing to an empty git submodule. Must be resolved via `config["downstream_scripts_dir"]`.

**Other Snakemake 9+ issues**: No `log:` or `resources:` directives anywhere; `bcftools` pipe lacks `set -euo pipefail`; `--use-singularity` is deprecated (use `--software-deployment-method apptainer`).

**Path forward**: Architecture stage to decompose into ~8 tasks: add helper + config block, containerize each rule group, create 4 Dockerfiles, fix downstream paths.
