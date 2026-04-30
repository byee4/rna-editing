#!/usr/bin/env bash
set -euo pipefail

java -version
test -s /opt/picard/picard.jar
picard MarkDuplicates --help >/tmp/picard.MarkDuplicates.help
echo "Picard validation passed"
