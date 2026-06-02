#!/usr/bin/env bash
set -euo pipefail

# Writable cache dirs — MARINE imports numba/matplotlib which fail to cache
# under a read-only $HOME inside the container.
export NUMBA_CACHE_DIR="${NUMBA_CACHE_DIR:-$(mktemp -d)}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-$(mktemp -d)}"

PY=/opt/conda/envs/marine/bin/python

"$PY" - <<'PY'
import pysam
import pybedtools
import numpy
import pandas
import scipy
print("pysam", pysam.__version__)
print("pybedtools", pybedtools.__version__)
print("numpy", numpy.__version__)
print("pandas", pandas.__version__)
print("scipy", scipy.__version__)
PY

test -f /opt/marine/marine.py
"$PY" /opt/marine/marine.py --help > /dev/null
echo "MARINE validation passed"
