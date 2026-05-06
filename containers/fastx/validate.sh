#!/usr/bin/env bash
set -euo pipefail

# fastx_trimmer prints usage to stderr and exits non-zero with no args, so use -h
fastx_trimmer -h 2>&1 | head -n 5 || true
command -v fastx_trimmer
echo "FASTX-Toolkit validation passed"
