#!/usr/bin/env bash
set -euo pipefail

python --version
test -s /opt/editpredict/get_seq.py
test -s /opt/editpredict/editPredict.py
test -s /opt/editpredict/editPredict_construction_alu.h5
test -s /opt/editpredict/editPredict_weight_alu.json
python - <<'PY'
from pathlib import Path

for script in ("/opt/editpredict/get_seq.py", "/opt/editpredict/editPredict.py"):
    path = Path(script)
    compile(path.read_text(), script, "exec")
PY
editpredict_score --help >/tmp/editpredict_score.help
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
cat >"${tmpdir}/ref.fa" <<'FASTA'
>1
ACGTACGTACGTACGTACGTACGTACGT
FASTA
printf '1\t3\n' >"${tmpdir}/positions.tsv"
(
  cd "${tmpdir}"
  python /opt/editpredict/get_seq.py -f ref.fa -p positions.tsv -m b -l 4
)
test -s "${tmpdir}/human_b_flanking_4.txt"
echo "EditPredict validation passed"
