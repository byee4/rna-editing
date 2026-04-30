#!/bin/bash

# Required tools: sra-toolkit (prefetch, fasterq-dump)
# Scope: HEK293, HEK293T, HepG2, and K562 cell lines only.

mkdir -p RNA_Editing_Benchmarking
cd RNA_Editing_Benchmarking

# --- 1. HEK293T RNA-Seq Benchmarking (GSE99249) ---
# Primary dataset used for evaluating tool performance with ADAR1 ablation.
echo "Downloading HEK293T WT and ADAR1KO triplicates (GSE99249)..."
declare -A HEK293T_RNA=(
    ["SRR5564274"]="HEK293T_WT_RNA_Rep1"
    ["SRR5564275"]="HEK293T_WT_RNA_Rep2"
    ["SRR5564276"]="HEK293T_WT_RNA_Rep3"
    ["SRR5564272"]="HEK293T_ADAR1KO_RNA_Rep1"
    ["SRR5564273"]="HEK293T_ADAR1KO_RNA_Rep2"
    ["SRR5564268"]="HEK293T_ADAR1KO_RNA_Rep3"
)

for acc in "${!HEK293T_RNA[@]}"; do
    NAME=${HEK293T_RNA[$acc]}
    echo "Retrieving $NAME ($acc)..."
    prefetch "$acc"
    fasterq-dump "$acc" --outdir HEK293T_RNA --split-files --progress
done

# --- 2. HEK293 Direct RNA Nanopore Benchmark (GSE132971) ---
# Used for testing third-generation sequencing tools like DeepEdit and m6Anet.
echo "Downloading HEK293 Nanopore Direct RNA (GSE132971)..."
NANO_ACC="SRR9115663" # Primary HEK293 WT sample
prefetch "$NANO_ACC"
fasterq-dump "$NANO_ACC" --outdir HEK293_NANOPORE --progress
mv "HEK293_NANOPORE/${NANO_ACC}.fastq" "HEK293_NANOPORE/HEK293_DirectRNA_WT.fastq"

# --- 3. HEK293 Lineage Genomic Variability (PRJNA565658 / PRJEB86622) ---
# Comprehensive WGS of 13 samples across the HEK293 lineage.
# Note: These files are large (>30x coverage). 
# Listing the primary parental adherent sample as a representative.
echo "Downloading HEK293 Adherent WGS (PRJNA565658)..."
HEK_WGS_ACC="SRR10137351" 
prefetch "$HEK_WGS_ACC"
fasterq-dump "$HEK_WGS_ACC" --outdir HEK293_WGS --split-files --progress

# --- 4. Multi-Cell Line Transcriptomics (GSE139190 / SRP226501) ---
# RNA-seq for HEK293, HepG2, and K562 cell lines.
echo "Downloading RNA-seq for target cell lines (GSE139190)..."
declare -A MULTI_CELL=(
    ["SRR10291932"]="HEK293_RNA_Rep1"
    ["SRR10291931"]="HepG2_RNA_Rep1"
    ["SRR10291929"]="K562_RNA_Rep1"
)

for acc in "${!MULTI_CELL[@]}"; do
    NAME=${MULTI_CELL[$acc]}
    echo "Retrieving $NAME ($acc)..."
    prefetch "$acc"
    fasterq-dump "$acc" --outdir MULTI_CELL_RNA --split-files --progress
done

echo "Downloads complete. All data organized by cell line and application."