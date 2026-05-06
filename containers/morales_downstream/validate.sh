#!/usr/bin/env bash
set -euo pipefail

python3 --version
python3 -c 'import pandas, numpy, scipy; print("pandas", pandas.__version__); print("numpy", numpy.__version__); print("scipy", scipy.__version__)'
echo "Morales downstream validation passed"
