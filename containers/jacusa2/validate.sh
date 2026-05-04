#!/usr/bin/env bash
set -euo pipefail

java -version
samtools --version | head -n 1
test -s /opt/jacusa2/jacusa2.jar
java -jar /opt/jacusa2/jacusa2.jar >/tmp/jacusa2.help 2>&1
grep -q "call-2" /tmp/jacusa2.help
java -jar /opt/jacusa2/jacusa2.jar call-2 -h >/tmp/jacusa2.call2.help 2>&1
grep -q "FEATURE-FILTER" /tmp/jacusa2.call2.help
echo "JACUSA2 validation passed"
