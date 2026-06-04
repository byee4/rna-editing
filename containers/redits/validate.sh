#!/usr/bin/env bash
set -euo pipefail

Rscript --version
test -s "${REDITS_SRC:-/opt/redits-src}/REDIT_LLR.R"
test -s "${REDITS_SRC:-/opt/redits-src}/REDIT_REGRESSION.R" \
  || test -s "${REDITS_SRC:-/opt/redits-src}/REDIT_regression.R"
test -x /opt/redits/redits_llr.R

# End-to-end self-test on a tiny synthetic count matrix: two disease vs two control samples
# with a clear editing difference should yield a finite p-value.
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
printf 'chrom\tpos\ts1\ts2\ts3\ts4\n' >"${tmpdir}/counts.tsv"
printf 'chr1\t100\t2,40\t3,42\t35,40\t38,41\n' >>"${tmpdir}/counts.tsv"

Rscript /opt/redits/redits_llr.R \
  --counts "${tmpdir}/counts.tsv" \
  --groups disease,disease,control,control \
  --output "${tmpdir}/out.tsv"

test -s "${tmpdir}/out.tsv"
head -n 5 "${tmpdir}/out.tsv"
# Output must have the header plus one data row with a numeric p-value.
awk 'NR==2 { if ($3+0==$3 && $3!="") exit 0; else exit 1 }' "${tmpdir}/out.tsv"

echo "REDITs validation passed"
