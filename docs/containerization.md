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

## Build and Validate

The validation script writes Docker build cache, Docker image archives, SIF
files, and Apptainer cache data under `/Volumes/X9Pro/container_data` by
default so the nearly-full system disk is not used for large artifacts.
Docker Desktop's default `docker` builder cannot always export BuildKit cache
to a host directory; when that happens, the script retries without external
build-cache export while keeping Docker archives and SIF files on the external
volume.

The containerized Apptainer builder uses a tmpfs-backed `/tmp` for SIF builds
and SIF validation. This avoids growing Docker Desktop's disk image during
Apptainer extraction while still keeping the Docker archives, SIF outputs, and
Apptainer cache on the external drive.

```bash
scripts/validate_containers.sh
```

To validate one or more tools:

```bash
TOOLS="reditools jacusa2" scripts/validate_containers.sh
```

Useful environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONTAINER_DATA_ROOT` | `/Volumes/X9Pro/container_data/rna-editing` | Storage for build cache, Docker archives, SIF files, and temporary files. |
| `DOCKER_PLATFORM` | `linux/amd64` | Platform used for Docker builds and containerized Apptainer runs. |
| `TOOLS` | all tools | Space-separated list of tools to build and validate. |
| `APPTAINER_IMAGE` | `ghcr.io/apptainer/apptainer:1.4.4` | Containerized Apptainer builder used when host Apptainer/Singularity is unavailable. |
| `APPTAINER_TMPFS_SIZE` | `4g` | Size of the tmpfs mounted at `/tmp` for containerized Apptainer builds and SIF validation. |

## Outputs

Successful runs create:

| Artifact | Location |
| --- | --- |
| Docker images | Local Docker daemon as `rna-editing/<tool>:latest` during validation. Images can be removed after their archives are saved. |
| Docker archives | `/Volumes/X9Pro/container_data/rna-editing/images/<tool>.tar` |
| Singularity/Apptainer SIFs | `/Volumes/X9Pro/container_data/rna-editing/sif/<tool>.sif` |
| Build cache | `/Volumes/X9Pro/container_data/rna-editing/docker-cache/<tool>` |

## Notes

Some tools are old and require legacy runtimes. REDItools and SPRINT use Python
2.7; SPRINT compiles BWA 0.7.12 and SAMtools 1.2 from source; SAILOR compiles
SAMtools 1.3.1 and BCFtools 1.2 from source. RED is a Java/R/MySQL application
distributed as a desktop-style jar, so its validation checks the runtime stack
and jar contents rather than attempting to open the GUI.
