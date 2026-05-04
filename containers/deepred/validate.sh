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
grep -q -- "--input-vcf" /tmp/deepred_predict.help
grep -q -- "--matlab-bin-dir" /tmp/deepred_predict.help
tmpdir=$(mktemp -d)
printf '#CHROM\tPOS\tREF\tALT\nchr1\t1\tA\tG\n' > "${tmpdir}/input.vcf"
if deepred_predict \
    --input-vcf "${tmpdir}/input.vcf" \
    --project smoke \
    --sample smoke \
    --output "${tmpdir}/predictions.txt" \
    >"${tmpdir}/stdout" 2>"${tmpdir}/stderr"; then
    echo "DeepRed unexpectedly succeeded without upstream artifacts" >&2
    exit 1
fi
grep -q "MATLAB executable not found in PATH" "${tmpdir}/stderr"
mkdir -p "${tmpdir}/fake-matlab-bin"
cat > "${tmpdir}/fake-matlab-bin/matlab" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${tmpdir}/fake-matlab-bin/matlab"
if deepred_predict \
    --input-vcf "${tmpdir}/input.vcf" \
    --project smoke \
    --sample smoke \
    --output "${tmpdir}/predictions.txt" \
    --matlab-bin-dir "${tmpdir}/fake-matlab-bin" \
    >"${tmpdir}/stdout.with-matlab" 2>"${tmpdir}/stderr.with-matlab"; then
    echo "DeepRed unexpectedly succeeded without upstream artifacts" >&2
    exit 1
fi
grep -q "DeepRed source code and trained model artifacts are not installed" "${tmpdir}/stderr.with-matlab"
echo "DeepRed scaffold validation passed"
