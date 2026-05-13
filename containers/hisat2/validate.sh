#!/usr/bin/env bash
set -euo pipefail

hisat2 --version
samtools --version | head -n 1
echo "hisat2 validation passed"
