# RNA Editing Containerization

This workspace contains one Docker build context per tool described in
`Dockerfile_description.md`. Each image installs the tool plus a small
`validate-*` command that checks the expected runtime, command-line tools, and
tool files. The same validation command is run in Docker and again after the
image is converted to a Singularity/Apptainer SIF.

## Tools

| Tool | Docker context | Validation command |
| --- | --- | --- |
| REDItools / REDItools2 | `containers/reditools` | `validate-reditools` |
| JACUSA2 | `containers/jacusa2` | `validate-jacusa2` |
| SPRINT | `containers/sprint` | `validate-sprint` |
| LoDEI | `containers/lodei` | `validate-lodei` |
| RED | `containers/red` | `validate-red` |
| SAILOR | `containers/sailor` | `validate-sailor` |
| WGS preprocessing | `containers/wgs` | `validate-wgs` |
| DeepRed | `containers/deepred` | `validate-deepred` |
| EditPredict | `containers/editpredict` | `validate-editpredict` |
| REDInet | `containers/redinet` | `validate-redinet` |
| Picard | `containers/picard` | `validate-picard` |

## Build and Validate

The validation script writes Docker build cache, Docker archive output, SIF
files, Buildx config, host temporary files, and
Apptainer/Singularity cache and temporary files under
`/Volumes/X9Pro/container_data` by default so the nearly-full system disk is not
used for large artifacts.

Apptainer itself requires `/tmp` to be a real mount point inside Docker Desktop
on macOS. The builder therefore uses a RAM-backed tmpfs for `/tmp`, which keeps
that extraction pressure off `Macintosh HD`; persistent Apptainer/Singularity
cache and all outputs remain on X9Pro.

The script builds Docker archives directly to the external drive with Buildx
instead of loading each tool image into the Docker daemon. After each SIF is
built and validated, the per-tool Docker archive, build cache, and temporary
Apptainer/Singularity directories are removed. The only intended final
artifacts are the `.sif` files.

Docker Desktop's default `docker` Buildx driver does not always support direct
archive export. The script creates a temporary `docker-container` Buildx builder
for archive generation, disables build cache for each tool, prunes cache after
validation, and removes the temporary builder when the run exits.

```bash
scripts/validate_containers.sh
```

To validate one or more tools:

```bash
TOOLS="reditools jacusa2" scripts/validate_containers.sh
```

The default validation set covers the images already present in
`/Volumes/X9Pro/container_data/singularity_images`. Newly added contexts for
missing Snakefile dependencies can be built explicitly:

```bash
TOOLS="wgs deepred editpredict redinet picard" scripts/validate_containers.sh
```

Useful environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONTAINER_DATA_ROOT` | `/Volumes/X9Pro/container_data` | Storage root for build cache, Docker archives, SIF files, config, and temporary files. |
| `SIF_OUTPUT_DIR` | `/Volumes/X9Pro/container_data/singularity_images` | Final Singularity/Apptainer image output directory. |
| `DOCKER_ARCHIVE_DIR` | `/Volumes/X9Pro/container_data/images` | Temporary Docker archives used as SIF build input. |
| `DOCKER_CACHE_ROOT` | `/Volumes/X9Pro/container_data/docker-cache` | External Buildx cache root. |
| `CONTAINER_TMP_ROOT` | `/Volumes/X9Pro/container_data/tmp` | External temporary root for Buildx, host tmp, and Apptainer/Singularity tmp/cache data. |
| `BUILDX_BUILDER` | `rna-editing-x9pro` | Temporary Buildx builder used for direct archive export. |
| `REUSE_EXISTING_ARCHIVES` | `1` | Reuse an existing non-empty Docker archive after an interrupted run instead of rebuilding it. |
| `APPTAINER_TMPFS_SIZE` | `4g` | RAM-backed `/tmp` size for containerized Apptainer builds and validation. |
| `DOCKER_PLATFORM` | `linux/amd64` | Platform used for Docker builds and containerized Apptainer runs. |
| `TOOLS` | all tools | Space-separated list of tools to build and validate. |
| `APPTAINER_IMAGE` | `ghcr.io/apptainer/apptainer:1.4.4` | Containerized Apptainer builder used when host Apptainer/Singularity is unavailable. |

## Outputs

Successful runs create:

| Artifact | Location |
| --- | --- |
| Singularity/Apptainer SIFs | `/Volumes/X9Pro/container_data/singularity_images/<tool>.sif` |
| Docker archives | `/Volumes/X9Pro/container_data/images/<tool>.tar`, removed after each validated SIF |
| Build cache | `/Volumes/X9Pro/container_data/docker-cache/<tool>`, removed after each validated SIF |
| Temporary files | `/Volumes/X9Pro/container_data/tmp`, per-tool directories removed after each validated SIF |

## Notes

Some tools are old and require legacy runtimes. REDItools and SPRINT use Python
2.7; SPRINT compiles BWA 0.7.12 and SAMtools 1.2 from source; SAILOR compiles
SAMtools 1.3.1 and BCFtools 1.2 from source. JACUSA2 is installed with mamba
from conda-forge/bioconda so the SIF contains OpenJDK 17, the executable
JACUSA2 jar exposed at `/opt/jacusa2/jacusa2.jar`, and SAMtools for the
`editing_wgs` rules that reuse the same image. RED is a Java/R/MySQL
application distributed as a desktop-style jar, so its validation checks the
runtime stack and jar contents rather than attempting to open the GUI.

The DeepRed context is a runtime scaffold because no matching local SIF or
checked-in upstream implementation/model is available. Its wrapper accepts a
DeepRed-ready candidate SNV table, stages it in the upstream `Raw_Data/<project>`
layout next to the `DeepRed` code directory, and runs
`Preprocess_input_data_for_DeepRed.pl` followed by `Run_DeepRed.pl` when the
source and model artifacts are installed under `DEEPRED_ROOT` or `/opt/DeepRed`;
otherwise it fails with a plain-English setup message. EditPredict and REDInet
include upstream checkouts plus thin wrappers, but their input adapters should
be reviewed with real workflow data before production use. Picard is packaged
separately for duplicate marking because no matching Picard SIF exists in the
local image directory.
