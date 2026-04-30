#!/usr/bin/env bash
set -euo pipefail

python --version
python - <<'PY'
import numpy
import pandas
import pysam
import sklearn
import tensorflow
print("numpy", numpy.__version__)
print("pandas", pandas.__version__)
print("pysam", pysam.__version__)
print("sklearn", sklearn.__version__)
print("tensorflow", tensorflow.__version__)
PY
test -d /opt/redinet
redinet_classify --help >/tmp/redinet_classify.help
echo "REDInet validation passed"
