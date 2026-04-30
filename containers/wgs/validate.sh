#!/usr/bin/env bash
set -euo pipefail

bwa 2>&1 | head -n 3
samtools --version | head -n 1
bcftools --version | head -n 1
tabix --version 2>&1 | head -n 1
echo "WGS validation passed"
