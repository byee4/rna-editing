#!/usr/bin/env bash
set -euo pipefail

python --version
(samtools 2>&1 | head -n 3) || true
(bcftools 2>&1 | head -n 3) || true
test -d /opt/sailor
find /opt/sailor -maxdepth 3 -type f \( -name "*sailor*" -o -name "*.py" -o -name "*.cwl" \) | head -n 1 | grep -q .
echo "SAILOR validation passed"
