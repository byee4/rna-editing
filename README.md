# RNA Editing Tool Containers

This repository builds Docker and Singularity/Apptainer containers for the RNA
editing tools summarized in `Dockerfile_description.md`.

See `docs/containerization.md` for the build layout, validation workflow, and
artifact locations under `/Volumes/X9Pro/container_data/rna-editing`.

The matched RNA/WGS workflow in `pipelines/editing_wgs` accepts single-end or
paired-end RNA-seq and WGS FASTQs per sample. It produces matched DNA/RNA
comparison calls, WGS-only coverage and germline variant outputs, plus RNA-only
SPRINT, REDItools2 serial, DeepRED, editPredict, and REDI-NET outputs; see
`pipelines/editing_wgs/README.md` for configuration and usage.
