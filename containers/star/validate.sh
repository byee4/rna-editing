#!/usr/bin/env bash
set -euo pipefail

STAR --version
samtools --version | head -n 1
echo "STAR validation passed"
