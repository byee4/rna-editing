#!/usr/bin/env bash
set -euo pipefail

java -version
R --version | head -n 1
mysql --version
test -s /opt/red/RED.jar
jar tf /opt/red/RED.jar | head -n 5
echo "RED validation passed"
