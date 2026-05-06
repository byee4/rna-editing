# Task 08: Create containers/fastx/ + containers/morales_downstream/ Dockerfiles

<!-- DEPENDENCIES: (none, parallel) -->
<!-- LABELS: phase-3, stage:3-implement, docker -->
<!-- VERIFIES: AC-14, AC-15, FR-17, FR-18, NFR-3, NFR-4, D-3 -->

## Goal

Create two new container build contexts:
1. `containers/fastx/` — FASTX-Toolkit (fastx_trimmer) via bioconda, used by `trim_reads` in `preprocessing.smk`
2. `containers/morales_downstream/` — Python 3.11 with pandas/numpy/scipy, used by all 5 rules in `downstream.smk`

## Files Created

- `containers/fastx/Dockerfile`
- `containers/fastx/validate.sh`
- `containers/morales_downstream/Dockerfile`
- `containers/morales_downstream/validate.sh`

## Exact File Content

### `containers/fastx/Dockerfile`

```dockerfile
FROM condaforge/miniforge3:latest

LABEL org.opencontainers.image.title="FASTX-Toolkit"
LABEL org.opencontainers.image.description="FASTX-Toolkit (fastx_trimmer) installed via bioconda for FASTQ quality trimming in the Morales_et_al pipeline."

ENV PATH="/opt/conda/bin:${PATH}"

RUN mamba install -y -n base -c conda-forge -c bioconda \
        fastx_toolkit \
    && mamba clean -a -y

COPY validate.sh /usr/local/bin/validate-fastx
RUN chmod +x /usr/local/bin/validate-fastx

WORKDIR /work
CMD ["validate-fastx"]
```

### `containers/fastx/validate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# fastx_trimmer prints usage to stderr and exits non-zero with no args, so use -h
fastx_trimmer -h 2>&1 | head -n 5 || true
command -v fastx_trimmer
echo "FASTX-Toolkit validation passed"
```

### `containers/morales_downstream/Dockerfile`

```dockerfile
FROM python:3.11-slim

LABEL org.opencontainers.image.title="Morales Downstream Analysis"
LABEL org.opencontainers.image.description="Python 3.11 with pandas and numpy for the Benchmark-of-RNA-Editing-Detection-Tools/Downstream/*.py scripts called from the Morales_et_al pipeline."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir \
        "numpy>=1.24,<2.0" \
        "pandas>=2.0,<3.0" \
        "scipy>=1.10,<2.0"

COPY validate.sh /usr/local/bin/validate-morales_downstream
RUN chmod +x /usr/local/bin/validate-morales_downstream

WORKDIR /work
CMD ["validate-morales_downstream"]
```

### `containers/morales_downstream/validate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

python3 --version
python3 -c 'import pandas, numpy, scipy; print("pandas", pandas.__version__); print("numpy", numpy.__version__); print("scipy", scipy.__version__)'
echo "Morales downstream validation passed"
```

## Acceptance Criteria

### fastx container

- [ ] `test -f containers/fastx/Dockerfile` exits 0
- [ ] `test -f containers/fastx/validate.sh` exits 0
- [ ] `grep "FROM condaforge/miniforge3:latest" containers/fastx/Dockerfile` returns 1 match
- [ ] `grep "fastx_toolkit" containers/fastx/Dockerfile` returns 1 match
- [ ] `grep "COPY validate.sh /usr/local/bin/validate-fastx" containers/fastx/Dockerfile` returns 1 match
- [ ] `grep "WORKDIR /work" containers/fastx/Dockerfile` returns 1 match
- [ ] `grep "set -euo pipefail" containers/fastx/validate.sh` returns 1 match
- [ ] `grep "fastx_trimmer" containers/fastx/validate.sh` returns at least 1 match
- [ ] `grep "FASTX-Toolkit validation passed" containers/fastx/validate.sh` returns 1 match

### morales_downstream container

- [ ] `test -f containers/morales_downstream/Dockerfile` exits 0
- [ ] `test -f containers/morales_downstream/validate.sh` exits 0
- [ ] `grep "FROM python:3.11-slim" containers/morales_downstream/Dockerfile` returns 1 match
- [ ] `grep "numpy>=1.24" containers/morales_downstream/Dockerfile` returns 1 match
- [ ] `grep "pandas>=2.0" containers/morales_downstream/Dockerfile` returns 1 match
- [ ] `grep "COPY validate.sh /usr/local/bin/validate-morales_downstream" containers/morales_downstream/Dockerfile` returns 1 match
- [ ] `grep "WORKDIR /work" containers/morales_downstream/Dockerfile` returns 1 match
- [ ] `grep "set -euo pipefail" containers/morales_downstream/validate.sh` returns 1 match
- [ ] `grep "import pandas, numpy, scipy" containers/morales_downstream/validate.sh` returns 1 match
- [ ] `grep "Morales downstream validation passed" containers/morales_downstream/validate.sh` returns 1 match

### No other files modified

- [ ] No files outside `containers/fastx/` and `containers/morales_downstream/` are modified

## Verification

```bash
# fastx
test -f containers/fastx/Dockerfile && echo "fastx Dockerfile: PASS"
test -f containers/fastx/validate.sh && echo "fastx validate.sh: PASS"
grep "condaforge/miniforge3\|fastx_toolkit\|validate-fastx\|WORKDIR /work" containers/fastx/Dockerfile
grep "fastx_trimmer\|FASTX-Toolkit validation passed" containers/fastx/validate.sh

# morales_downstream
test -f containers/morales_downstream/Dockerfile && echo "morales_downstream Dockerfile: PASS"
test -f containers/morales_downstream/validate.sh && echo "morales_downstream validate.sh: PASS"
grep "python:3.11-slim\|numpy>=1.24\|pandas>=2.0\|validate-morales_downstream\|WORKDIR /work" containers/morales_downstream/Dockerfile
grep "import pandas, numpy, scipy\|Morales downstream validation passed" containers/morales_downstream/validate.sh
```

## Notes

### fastx container
- D-3 rationale: `bioconda` is the path of least resistance for FASTX-Toolkit; the `fastx_toolkit` package is published for `linux-64` on bioconda. R-3 risk: if bioconda is unavailable on the build host, fall back to compiling from source on `ubuntu:20.04` (requires `./configure && make && make install`).
- `fastx_trimmer -h 2>&1 | head -n 5 || true` in validate.sh: fastx_trimmer exits non-zero with no args; `|| true` prevents set -e abort. `command -v fastx_trimmer` confirms PATH resolution.
- Build for `linux/amd64`: `docker build --platform linux/amd64 -t fastx containers/fastx/`

### morales_downstream container
- `python:3.11-slim` is minimal and sufficient; the Downstream scripts require only pandas, numpy, and scipy.
- Version bounds (`numpy>=1.24,<2.0`, `pandas>=2.0,<3.0`, `scipy>=1.10,<2.0`) allow pip to resolve a compatible set while avoiding breaking API changes (numpy 2.x has breaking changes vs 1.x).
- The Benchmark-of-RNA-Editing-Detection-Tools submodule scripts are NOT baked into the image; they are mounted at runtime from the host (configured via `downstream_scripts_dir` in config.yaml). This keeps the image generic and avoids re-builds when scripts change.
- Build for `linux/amd64`: `docker build --platform linux/amd64 -t morales_downstream containers/morales_downstream/`
