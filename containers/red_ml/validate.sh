#!/usr/bin/env bash
set -euo pipefail

perl --version | head -n 2
Rscript --version
test -f /opt/red_ml/bin/red_ML.pl
test -x /opt/red_ml/bin/MismatchStat
test -x /opt/red_ml/bin/MutDetML
red_ML.pl 2>&1 | head -n 5 || true
Rscript -e 'library(caret); library(data.table); library(ROCR); library(randomForest); cat("R packages OK\n")'
echo "RED-ML validation passed"
