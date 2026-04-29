#!/usr/bin/env bash
set -euo pipefail

python --version
lodei --help >/tmp/lodei.help 2>&1
multiqc --version
cutadapt --version
fastqc --version
STAR --version
samtools --version | head -n 1
echo "LoDEI validation passed"
