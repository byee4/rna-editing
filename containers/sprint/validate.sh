#!/usr/bin/env bash
set -euo pipefail

python --version
(bwa 2>&1 | head -n 3) || true
(samtools 2>&1 | head -n 3) || true
test -d /opt/sprint
find /opt/sprint -maxdepth 3 -type f \( -name "*SPRINT*.py" -o -name "sprint*.py" -o -perm -111 \) | head -n 1 | grep -q .
echo "SPRINT validation passed"
