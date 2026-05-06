# Task 07: Create containers/red_ml/ Dockerfile + validate.sh

<!-- DEPENDENCIES: (none, parallel) -->
<!-- LABELS: phase-3, stage:3-implement, docker -->
<!-- VERIFIES: AC-13, FR-16, NFR-3, NFR-4, D-2 -->

## Goal

Create the `containers/red_ml/` build context with a `Dockerfile` (rocker/r-ver:4.3.2 + Perl + RED-ML + required R packages) and a `validate.sh` script. This image will be built as `red_ml.sif` and used by the `red_ml` rule in `tools.smk`.

## Files Created

- `containers/red_ml/Dockerfile`
- `containers/red_ml/validate.sh`

## Exact File Content

### `containers/red_ml/Dockerfile`

```dockerfile
FROM rocker/r-ver:4.3.2

LABEL org.opencontainers.image.title="RED-ML"
LABEL org.opencontainers.image.description="Perl + R + RED-ML (red_ML.pl) for RNA editing detection by machine learning. Reference: BGI-shenzhen/RED-ML."

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/red_ml/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        perl \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install required R packages (RED-ML uses caret + randomForest + ROCR + data.table)
RUN Rscript -e 'install.packages(c("caret","data.table","ROCR","randomForest","e1071"), repos="https://cloud.r-project.org/", Ncpus=2)'

# Clone RED-ML and place red_ML.pl on PATH
RUN git clone --depth 1 https://github.com/BGIRED/RED-ML.git /opt/red_ml \
    && test -f /opt/red_ml/bin/red_ML.pl \
    && chmod +x /opt/red_ml/bin/red_ML.pl

COPY validate.sh /usr/local/bin/validate-red_ml
RUN chmod +x /usr/local/bin/validate-red_ml

WORKDIR /work
CMD ["validate-red_ml"]
```

### `containers/red_ml/validate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

perl --version | head -n 2
Rscript --version
test -f /opt/red_ml/bin/red_ML.pl
red_ML.pl 2>&1 | head -n 5 || true
Rscript -e 'library(caret); library(data.table); library(ROCR); library(randomForest); cat("R packages OK\n")'
echo "RED-ML validation passed"
```

## Acceptance Criteria

- [ ] `test -f containers/red_ml/Dockerfile` exits 0
- [ ] `test -f containers/red_ml/validate.sh` exits 0
- [ ] `grep "FROM rocker/r-ver:4.3.2" containers/red_ml/Dockerfile` returns 1 match
- [ ] `grep "BGI-shenzhen/RED-ML" containers/red_ml/Dockerfile` returns 1 match
- [ ] `grep "caret.*data.table.*ROCR.*randomForest.*e1071" containers/red_ml/Dockerfile` returns 1 match
- [ ] `grep "COPY validate.sh /usr/local/bin/validate-red_ml" containers/red_ml/Dockerfile` returns 1 match
- [ ] `grep "WORKDIR /work" containers/red_ml/Dockerfile` returns 1 match
- [ ] `grep "set -euo pipefail" containers/red_ml/validate.sh` returns 1 match
- [ ] `grep "red_ML.pl" containers/red_ml/validate.sh` returns at least 1 match
- [ ] `grep "R packages OK" containers/red_ml/validate.sh` returns 1 match
- [ ] No other file is modified

## Verification

```bash
test -f containers/red_ml/Dockerfile && echo "Dockerfile: PASS"
test -f containers/red_ml/validate.sh && echo "validate.sh: PASS"
grep "FROM rocker/r-ver:4.3.2\|BGI-shenzhen/RED-ML\|validate-red_ml\|WORKDIR /work" containers/red_ml/Dockerfile
grep "set -euo pipefail\|red_ML.pl\|R packages OK" containers/red_ml/validate.sh
```

## Notes

- D-2 rationale: `rocker/r-ver:4.3.2` pins R to a specific version with CRAN snapshot support. `ubuntu:22.04` apt r-base lags significantly. Bioconda conda env adds ~200 MB overhead with no version-pinning benefit.
- R-2 risk: CRAN package installs can fail if CRAN snapshots drift. The five packages (`caret`, `data.table`, `ROCR`, `randomForest`, `e1071`) are widely used and stable. If a package fails, try pinning versions or using Posit Public Package Manager: `repos="https://packagemanager.posit.co/cran/__linux__/jammy/latest"`.
- `red_ML.pl 2>&1 | head -n 5 || true` in validate.sh: red_ML.pl exits non-zero with usage message when called with no args; `|| true` prevents set -e from aborting. The `test -f` guard above confirms the file exists.
- Build for `linux/amd64` on Apple Silicon: `docker build --platform linux/amd64 -t red_ml containers/red_ml/`
- This is the slowest container to build (~5-10 min) due to R package compilation. Build in parallel with Task 06 and Task 08.
