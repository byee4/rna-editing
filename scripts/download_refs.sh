#!/usr/bin/env bash
set -euo pipefail

# Required tools: sra-toolkit (module load sratools)
# Downloads are written under the repository data/ directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${REPO_DIR}/data"
SRA_CACHE="${DATA_DIR}/sra_cache"
SRA_TMP="${DATA_DIR}/sra_tmp"
SRA_MAX_SIZE="${SRA_MAX_SIZE:-200G}"

mkdir -p "${DATA_DIR}" "${SRA_CACHE}" "${SRA_TMP}"

compress_fastq() {
    if command -v pigz >/dev/null 2>&1; then
        pigz -f "$@"
    else
        gzip -f "$@"
    fi
}

fetch_sra() {
    local acc="$1"
    echo "Prefetching ${acc}..."
    prefetch "${acc}" --output-directory "${SRA_CACHE}" --max-size "${SRA_MAX_SIZE}"

    if [[ ! -s "${SRA_CACHE}/${acc}/${acc}.sra" ]]; then
        echo "Error: ${SRA_CACHE}/${acc}/${acc}.sra was not downloaded." >&2
        exit 1
    fi
}

dump_paired() {
    local accession="$1"
    local outdir="$2"
    local workdir="${SRA_TMP}/${accession}.fasterq"
    mkdir -p "${outdir}"

    if [[ -s "${outdir}/${accession}_1.fastq.gz" && -s "${outdir}/${accession}_2.fastq.gz" ]]; then
        echo "Skipping ${accession}; paired FASTQs already exist."
        return
    fi

    fetch_sra "${accession}"
    echo "Converting ${accession} to paired FASTQ..."
    rm -rf "${workdir}"
    mkdir -p "${workdir}"
    fasterq-dump "${SRA_CACHE}/${accession}/${accession}.sra" \
        --outdir "${workdir}" \
        --temp "${SRA_TMP}" \
        --split-files \
        --progress
    mv -f "${workdir}/${accession}_1.fastq" "${outdir}/${accession}_1.fastq"
    mv -f "${workdir}/${accession}_2.fastq" "${outdir}/${accession}_2.fastq"
    rmdir "${workdir}"
    compress_fastq "${outdir}/${accession}_1.fastq" "${outdir}/${accession}_2.fastq"
}

dump_single() {
    local accession="$1"
    local outdir="$2"
    local workdir="${SRA_TMP}/${accession}.fasterq"
    mkdir -p "${outdir}"

    if [[ -s "${outdir}/${accession}.fastq.gz" ]]; then
        echo "Skipping ${accession}; FASTQ already exists."
        return
    fi

    if [[ -s "${outdir}/${accession}.fastq" ]]; then
        echo "Compressing existing ${accession}.fastq..."
        compress_fastq "${outdir}/${accession}.fastq"
        return
    fi

    fetch_sra "${accession}"
    echo "Converting ${accession} to single-end FASTQ..."
    rm -rf "${workdir}"
    mkdir -p "${workdir}"
    fasterq-dump "${SRA_CACHE}/${accession}/${accession}.sra" \
        --outdir "${workdir}" \
        --temp "${SRA_TMP}" \
        --progress
    mv -f "${workdir}/${accession}.fastq" "${outdir}/${accession}.fastq"
    rmdir "${workdir}"
    compress_fastq "${outdir}/${accession}.fastq"
}

echo "Downloading HEK293T WT and ADAR1KO mock RNA-seq triplicates (GSE99249/SRP107094)..."
# NCBI runinfo labels these as mock-treated HEK293T RNA-seq samples.
declare -A HEK293T_RNA=(
    ["SRR5564274"]="HEK293T_WT_mock_RNA_Rep1"
    ["SRR5564275"]="HEK293T_WT_mock_RNA_Rep2"
    ["SRR5564276"]="HEK293T_WT_mock_RNA_Rep3"
    ["SRR5564272"]="HEK293T_ADAR1KO_mock_RNA_Rep1"
    ["SRR5564273"]="HEK293T_ADAR1KO_mock_RNA_Rep2"
    ["SRR5564268"]="HEK293T_ADAR1KO_mock_RNA_Rep3"
)

for acc in "${!HEK293T_RNA[@]}"; do
    echo "Retrieving ${HEK293T_RNA[$acc]} (${acc})..."
    dump_paired "${acc}" "${DATA_DIR}/HEK293T_RNA"
done

echo "Downloading HEK293 direct RNA Nanopore WT sample (GSE132971/SRP213119)..."
dump_single "SRR9646141" "${DATA_DIR}/HEK293_NANOPORE"

echo "Downloading HEK293 WGS sample (PRJNA565658/SRP221975)..."
dump_paired "SRR10129632" "${DATA_DIR}/HEK293_WGS"

echo "Downloading RNA-seq for HEK293, HepG2, and K562 (GSE139190/SRP226501)..."
# GSE139190 RNA-seq libraries are single-end NextSeq runs.
declare -A MULTI_CELL_RNA=(
    ["SRR10319891"]="HEK293_RNA_Rep1"
    ["SRR10319892"]="HEK293_RNA_Rep2"
    ["SRR10319893"]="HepG2_RNA_Rep1"
    ["SRR10319894"]="HepG2_RNA_Rep2"
    ["SRR10319895"]="K562_RNA_Rep1"
    ["SRR10319896"]="K562_RNA_Rep2"
)

for acc in "${!MULTI_CELL_RNA[@]}"; do
    echo "Retrieving ${MULTI_CELL_RNA[$acc]} (${acc})..."
    dump_single "${acc}" "${DATA_DIR}/MULTI_CELL_RNA"
done

echo "Downloads complete."
