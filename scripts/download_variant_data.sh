#!/usr/bin/env bash
set -euo pipefail

# HEK293 & HEK293T variant-data downloader/scaffolder.
# Required tools for raw SRA download: sra-toolkit (module load sratools)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${REPO_DIR}/data"
BASE_DIR="${DATA_DIR}/HEK293_Variant_Data"
SRA_CACHE="${DATA_DIR}/sra_cache"
SRA_TMP="${DATA_DIR}/sra_tmp"
SRA_MAX_SIZE="${SRA_MAX_SIZE:-200G}"

DIR_WGS="${BASE_DIR}/WGS_PRJNA565658"
DIR_WES_DEPMAP="${BASE_DIR}/WES_DepMap_CCLE"
DIR_TARGETED_GEO="${BASE_DIR}/Targeted_GEO_Processed"

mkdir -p "${DIR_WGS}" "${DIR_WES_DEPMAP}" "${DIR_TARGETED_GEO}" "${SRA_CACHE}" "${SRA_TMP}"

echo "Fetching DepMap CCLE Mutations..."
DEPMAP_URL="https://ndownloader.figshare.com/files/34989937"
DEPMAP_FILE="${DIR_WES_DEPMAP}/CCLE_mutations.csv"

if [[ ! -s "${DEPMAP_FILE}" ]]; then
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "${DEPMAP_URL}" -o "${DEPMAP_FILE}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "${DEPMAP_FILE}" "${DEPMAP_URL}"
    else
        echo "Error: Neither curl nor wget is installed." >&2
        exit 1
    fi
else
    echo "Skipping DepMap download; ${DEPMAP_FILE} already exists."
fi

cat > "${DIR_WES_DEPMAP}/extract_hek293.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# The DepMap cell line ID for HEK293 is ACH-000569.
if [[ -f "CCLE_mutations.csv" ]]; then
    grep "ACH-000569" CCLE_mutations.csv > HEK293_mutations_only.csv
    echo "Extracted HEK293-specific variants to HEK293_mutations_only.csv"
else
    echo "CCLE_mutations.csv not found." >&2
    exit 1
fi
EOF
chmod +x "${DIR_WES_DEPMAP}/extract_hek293.sh"

echo "Creating WGS fetch script..."
cat > "${DIR_WGS}/fetch_raw_WGS.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

# Requires: module load sratools
# Source: PRJNA565658 / SRP221975, HEK293 WGS sample WGS_293.
# NCBI runinfo verifies SRR10129632 as Homo sapiens HEK293 paired-end WGS.

DATA_DIR="${DATA_DIR}"
SRA_CACHE="\${DATA_DIR}/sra_cache"
SRA_TMP="\${DATA_DIR}/sra_tmp"
SRA_MAX_SIZE="\${SRA_MAX_SIZE:-${SRA_MAX_SIZE}}"
OUTDIR="\${DATA_DIR}/HEK293_WGS"
ACC="SRR10129632"
WORKDIR="\${SRA_TMP}/\${ACC}.fasterq"

mkdir -p "\${SRA_CACHE}" "\${SRA_TMP}" "\${OUTDIR}"

if [[ -s "\${OUTDIR}/\${ACC}_1.fastq.gz" && -s "\${OUTDIR}/\${ACC}_2.fastq.gz" ]]; then
    echo "Skipping \${ACC}; paired FASTQs already exist."
    exit 0
fi

prefetch "\${ACC}" --output-directory "\${SRA_CACHE}" --max-size "\${SRA_MAX_SIZE}"
if [[ ! -s "\${SRA_CACHE}/\${ACC}/\${ACC}.sra" ]]; then
    echo "Error: \${SRA_CACHE}/\${ACC}/\${ACC}.sra was not downloaded." >&2
    exit 1
fi

rm -rf "\${WORKDIR}"
mkdir -p "\${WORKDIR}"
fasterq-dump "\${SRA_CACHE}/\${ACC}/\${ACC}.sra" \\
    --outdir "\${WORKDIR}" \\
    --temp "\${SRA_TMP}" \\
    --split-files \\
    --progress
mv -f "\${WORKDIR}/\${ACC}_1.fastq" "\${OUTDIR}/\${ACC}_1.fastq"
mv -f "\${WORKDIR}/\${ACC}_2.fastq" "\${OUTDIR}/\${ACC}_2.fastq"
rmdir "\${WORKDIR}"
if command -v pigz >/dev/null 2>&1; then
    pigz -f "\${OUTDIR}/\${ACC}_1.fastq" "\${OUTDIR}/\${ACC}_2.fastq"
else
    gzip -f "\${OUTDIR}/\${ACC}_1.fastq" "\${OUTDIR}/\${ACC}_2.fastq"
fi
EOF
chmod +x "${DIR_WGS}/fetch_raw_WGS.sh"

echo "Creating GEO VCF fetch template..."
cat > "${DIR_TARGETED_GEO}/fetch_geo_vcf.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Replace this placeholder with a real GEO supplementary .vcf.gz URL.
GEO_FTP_URL="ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSEnnn/GSEnnn/suppl/example_HEK293.vcf.gz"

wget -q --show-progress "${GEO_FTP_URL}" || {
    echo "Update GEO_FTP_URL to a valid GEO supplementary VCF." >&2
    exit 1
}
EOF
chmod +x "${DIR_TARGETED_GEO}/fetch_geo_vcf.sh"

echo "Variant-data setup complete under ${BASE_DIR}."
