#!/usr/bin/env bash
set -euo pipefail

conda run -n marine python - <<'PY'
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

test -f /opt/marine/bin/MARINE/marine.py
conda run -n marine python /opt/marine/bin/MARINE/marine.py --help > /dev/null
echo "MARINE validation passed"
