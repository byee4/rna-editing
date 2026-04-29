#!/usr/bin/env bash
set -euo pipefail

python --version
python - <<'PY'
import mpi4py
import numpy
import pysam
import fisher
print("pysam", pysam.__version__)
print("numpy", numpy.__version__)
print("mpi4py", mpi4py.__version__)
print("fisher", getattr(fisher, "__version__", "installed"))
PY
samtools --version | head -n 1
tabix --version 2>&1 | head -n 1
test -s /opt/reditools/main/REDItoolDnaRna.py
test -d /opt/reditools2
python /opt/reditools/main/REDItoolDnaRna.py --help >/tmp/reditools.help 2>&1 || test -s /tmp/reditools.help
echo "REDItools validation passed"
