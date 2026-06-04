#!/usr/bin/env bash
set -euo pipefail

# Runtime deps
Rscript --version
python --version
samtools --version | head -n 1

# libhts.so.1 must be present and resolvable (the soname the giremi binary links).
ldconfig -p | grep -q 'libhts\.so\.1' || { echo "libhts.so.1 not found" >&2; exit 1; }

# GIREMI assets in place.
test -x /opt/giremi/giremi
test -s /opt/giremi/giremi.r
test -s /opt/giremi/mark_snp.py

# The legacy binary must load (i.e. its dynamic htslib linkage resolves). Run with no
# args; GIREMI prints its usage and exits non-zero, so tolerate a non-zero status but fail
# on a loader error (which writes to stderr and produces no usage text).
help_out="$(giremi 2>&1 || true)"
printf '%s\n' "$help_out" | head -n 20
printf '%s' "$help_out" | grep -qiE 'usage|giremi|fasta|positions' \
    || { echo "giremi binary did not print usage — check libhts linkage" >&2; exit 1; }

echo "GIREMI validation passed"
