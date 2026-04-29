#!/usr/bin/env bash
set -euo pipefail

java -version
samtools --version | head -n 1
test -s /opt/jacusa2/jacusa2.jar
java -jar /opt/jacusa2/jacusa2.jar --help >/tmp/jacusa2.help 2>&1 || test -s /tmp/jacusa2.help
echo "JACUSA2 validation passed"
