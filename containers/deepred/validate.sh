#!/usr/bin/env bash
set -euo pipefail

python --version
python - <<'PY'
import numpy
import pandas
import sklearn
print("numpy", numpy.__version__)
print("pandas", pandas.__version__)
print("sklearn", sklearn.__version__)
PY
deepred_predict --help >/tmp/deepred_predict.help
echo "DeepRed scaffold validation passed"
