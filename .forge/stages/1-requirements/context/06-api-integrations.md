# API Integrations

## N/A for Runtime APIs

This pipeline does not call any external APIs at runtime. All tools are local binaries run inside containers.

## Container Image Sources (Build-Time)

These are the upstream sources for new Dockerfiles — referenced at build time, not run time.

| Container | Source | URL / Package |
|-----------|--------|---------------|
| `star` | STAR GitHub releases | https://github.com/alexdobin/STAR/releases (v2.7.11a recommended) |
| `star` | samtools (apt) | `apt-get install samtools` or bioconda |
| `red_ml` | RED-ML GitHub | https://github.com/BIMIB-DISCo/RED-ML |
| `red_ml` | Perl (apt) | `apt-get install perl` |
| `red_ml` | R (CRAN/apt) | r-base + packages: caret, data.table, ROCR |
| `fastx` | FASTX-Toolkit (bioconda) | `mamba install -c bioconda fastx_toolkit` |
| `morales_downstream` | Python 3 (Docker Hub) | `python:3.11-slim` base image |
| `morales_downstream` | pandas (pip) | `pip install pandas numpy` |

## Existing Container Reuse

| Rule(s) | Existing SIF | Source Container |
|---------|-------------|------------------|
| mark_duplicates | `singularity/picard.sif` | `containers/picard/Dockerfile` |
| reditools | `singularity/reditools.sif` | `containers/reditools/Dockerfile` |
| sprint | `singularity/sprint.sif` | `containers/sprint/Dockerfile` |
| bcftools, add_md_tag | `singularity/wgs.sif` | `containers/wgs/Dockerfile` |
| jacusa2 | `singularity/jacusa2.sif` | `containers/jacusa2/Dockerfile` |

## No External Network Calls at Runtime

The pipeline is designed for air-gapped HPC execution after containers are built. No rules make HTTP requests. Reference genome files are expected to be pre-staged at paths specified in `config.yaml`.
