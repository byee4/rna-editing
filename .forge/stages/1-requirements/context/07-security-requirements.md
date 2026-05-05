# Security Requirements

## SEC-1: No User-Specific or Cluster-Specific Paths

All hardcoded user-home paths (`~/bin/...`) and cluster-specific absolute paths (`/binf-isilon/rennie/gsn480/...`) must be eliminated from:
- `pipelines/Morales_et_all/config.yaml`
- `pipelines/Morales_et_all/*.smk`

After the change, `grep -r "~/bin\|/binf-isilon" pipelines/Morales_et_all/` must return no matches.

**Rationale**: Paths like `~/bin/picard-tools/MarkDuplicates.jar` expose the original developer's home directory layout and break execution for anyone else. The `/binf-isilon/` path is a specific cluster mount that does not exist on TSCC or other machines.

## SEC-2: Non-Root Container Execution Where Practical

New Dockerfiles should avoid running processes as root in the final layer unless required by the tool's installation mechanism.

- `morales_downstream`: Use `python:3.11-slim` with default non-root USER if the Python scripts do not require root.
- `fastx`, `star`, `red_ml`: If using conda/mamba base, processes run as root in the container by default. This is acceptable for HPC containers where Apptainer maps the container user to the calling user. No change needed.

**Rationale**: HPC cluster security policies prefer non-root container execution. Apptainer (Singularity) always runs the container as the calling user's UID, which effectively enforces this regardless of the Dockerfile USER directive.

## SEC-3: No Credentials or Tokens in Container Images

New Dockerfiles must not embed credentials, tokens, or private keys. All tool downloads use public URLs (GitHub releases, bioconda packages).

## SEC-4: Shell Injection Prevention

`set -euo pipefail` in all multi-command shell blocks prevents silent failures from propagating. The `bcftools` rule and `star_mapping` rule are known to need this added. All other rules with pipes must also have it.

**Affected rules**:
- `bcftools` (pipe: `bcftools mpileup | bcftools call`) — MISSING, must add
- `star_mapping` (pipe: `samtools view ... | samtools sort ...`) — MISSING, must add
- Other rules with single commands: no pipe, pipefail not strictly necessary but recommended for consistency
