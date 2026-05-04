#!/usr/bin/env bash
set -euo pipefail

java -version
samtools --version | head -n 1
test -s /opt/jacusa2/jacusa2.jar
test "$(stat -c %s /opt/jacusa2/jacusa2.jar)" -gt 5000000
manifest_tmp="$(mktemp -d)"
trap 'rm -rf "${manifest_tmp}"' EXIT
(
  cd "${manifest_tmp}"
  jar xf /opt/jacusa2/jacusa2.jar META-INF/MANIFEST.MF
  grep -q "^Main-Class:" META-INF/MANIFEST.MF
  grep -q "Rsrc-Class-Path:.*commons-cli" META-INF/MANIFEST.MF
  grep -q "^Rsrc-Main-Class: jacusa.JACUSA" META-INF/MANIFEST.MF
)
java -jar /opt/jacusa2/jacusa2.jar >/tmp/jacusa2.help 2>&1
grep -q "call-2" /tmp/jacusa2.help
grep -q "Apache commons-cli" /tmp/jacusa2.help
java -jar /opt/jacusa2/jacusa2.jar call-2 -h >/tmp/jacusa2.call2.help 2>&1
grep -q "FEATURE-FILTER" /tmp/jacusa2.call2.help
echo "JACUSA2 validation passed"
