#!/usr/bin/env bash
set -euo pipefail

python --version
test -s /opt/editpredict/get_seq.py
test -s /opt/editpredict/editPredict.py
test -s /opt/editpredict/editPredict_construction_alu.h5
test -s /opt/editpredict/editPredict_weight_alu.json
editpredict_score --help >/tmp/editpredict_score.help
echo "EditPredict validation passed"
