# Task 06: Create containers/star/ Dockerfile + validate.sh

<!-- DEPENDENCIES: (none, parallel) -->
<!-- LABELS: phase-3, stage:3-implement, docker -->
<!-- VERIFIES: AC-12, FR-15, NFR-3, NFR-4, D-1 -->

## Goal

Create the `containers/star/` build context with a `Dockerfile` (Ubuntu 22.04 + STAR static binary + SAMtools) and a `validate.sh` script. This image will be built as `star.sif` and used by the `star_mapping` rule in `preprocessing.smk`.

## Files Created

- `containers/star/Dockerfile`
- `containers/star/validate.sh`

## Exact File Content

### `containers/star/Dockerfile`

```dockerfile
FROM ubuntu:22.04

LABEL org.opencontainers.image.title="STAR + SAMtools"
LABEL org.opencontainers.image.description="STAR 2.7.x aligner and SAMtools for RNA-seq alignment in the Morales_et_al pipeline."

ENV DEBIAN_FRONTEND=noninteractive \
    STAR_VERSION=2.7.11a \
    PATH="/opt/star/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        samtools \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/star/bin \
    && wget -qO /tmp/star.tar.gz "https://github.com/alexdobin/STAR/archive/refs/tags/${STAR_VERSION}.tar.gz" \
    && tar -xzf /tmp/star.tar.gz -C /tmp \
    && cp "/tmp/STAR-${STAR_VERSION}/bin/Linux_x86_64_static/STAR" /opt/star/bin/STAR \
    && chmod +x /opt/star/bin/STAR \
    && rm -rf /tmp/star.tar.gz "/tmp/STAR-${STAR_VERSION}"

COPY validate.sh /usr/local/bin/validate-star
RUN chmod +x /usr/local/bin/validate-star

WORKDIR /work
CMD ["validate-star"]
```

### `containers/star/validate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

STAR --version
samtools --version | head -n 1
echo "STAR validation passed"
```

## Acceptance Criteria

- [ ] `test -f containers/star/Dockerfile` exits 0
- [ ] `test -f containers/star/validate.sh` exits 0
- [ ] `grep "FROM ubuntu:22.04" containers/star/Dockerfile` returns 1 match
- [ ] `grep "STAR_VERSION=2.7.11a" containers/star/Dockerfile` returns 1 match
- [ ] `grep "COPY validate.sh /usr/local/bin/validate-star" containers/star/Dockerfile` returns 1 match
- [ ] `grep "CMD \[\"validate-star\"\]" containers/star/Dockerfile` returns 1 match
- [ ] `grep "WORKDIR /work" containers/star/Dockerfile` returns 1 match
- [ ] `grep "set -euo pipefail" containers/star/validate.sh` returns 1 match
- [ ] `grep "STAR --version" containers/star/validate.sh` returns 1 match
- [ ] `grep "samtools --version" containers/star/validate.sh` returns 1 match
- [ ] No other file is modified

## Verification

```bash
test -f containers/star/Dockerfile && echo "Dockerfile: PASS"
test -f containers/star/validate.sh && echo "validate.sh: PASS"
grep "FROM ubuntu:22.04\|STAR_VERSION=2.7.11a\|validate-star\|WORKDIR /work" containers/star/Dockerfile
grep "set -euo pipefail\|STAR --version\|samtools --version" containers/star/validate.sh
```

## Notes

- D-1 rationale: `ubuntu:22.04` + apt SAMtools + STAR static binary from the upstream GitHub release tarball is the leanest option. The bioconda approach (`condaforge/miniforge3`) adds ~200 MB of conda env overhead for no benefit.
- The static binary path inside the tarball is `bin/Linux_x86_64_static/STAR`. This path has been stable across STAR releases since 2.5.x.
- Build for `linux/amd64` on Apple Silicon: `docker build --platform linux/amd64 -t star containers/star/`
- `scripts/validate_containers.sh` will enumerate `containers/star/` automatically because it iterates `containers/*/`.
- Do NOT reuse `lodei.sif` for STAR (C-002 in architecture plan: lodei is an accidental dependency).
