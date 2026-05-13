# RNA Editing Tool Containers

This repository builds Docker and Singularity/Apptainer containers for the RNA
editing tools summarized in `Dockerfile_description.md`.

See `docs/containerization.md` for the build layout, validation workflow, and
artifact locations under `/Volumes/X9Pro/container_data/rna-editing`.

The matched RNA/WGS workflow in `pipelines/editing_wgs` accepts single-end or
paired-end RNA-seq and WGS FASTQs per sample. It produces matched DNA/RNA
comparison calls, WGS-only coverage and germline variant outputs, plus RNA-only
SPRINT, REDItools v1 / REDInet, DeepRED, editPredict, and REDI-NET outputs; see
`pipelines/editing_wgs/README.md` for configuration and usage. The workflow
configs are `pipelines/editing_wgs/config.data.example.yaml` for the small
example inputs under `data/small_examples/random` and
`pipelines/editing_wgs/config.yaml` for the full `data/` inputs.

For HEK293-family variant references, `scripts/download_variant_data.sh`
creates modality-specific folders, downloads the public DepMap CCLE mutation
table, and writes follow-up fetch helpers for WGS SRA reads and GEO VCF
supplementary files. Review generated helper scripts before running them because
some sources require database-specific access tools or accession-specific URLs.

Run the pipeline with: 
```bash
module load singularitypro;
conda activate snakemake9;
cd examples;
unset SLURM_JOB_ID # required if running on an interactive node, which is reccomended
snakemake -kps /tscc/nfs/home/bay001/projects/codebase/rna-editing/pipelines/Morales_et_al/Snakefile \
--configfile /tscc/nfs/home/bay001/projects/codebase/rna-editing/examples/Morales_et_al/config_small.yaml \
--profile /tscc/nfs/home/bay001/projects/codebase/rna-editing/profiles/tscc2 \
--use-singularity
```