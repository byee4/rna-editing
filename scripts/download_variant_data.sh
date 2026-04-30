#!/usr/bin/env bash

# =============================================================================
# HEK293 & HEK293T Dataset Downloader & Scaffolder
# Automatically creates folders by dataset modality and downloads available 
# public mutation data, or generates fetch scripts for database-restricted files.
# =============================================================================

set -euo pipefail

BASE_DIR="HEK293_Variant_Data"

# Define dataset modalities
DIR_WGS="${BASE_DIR}/WGS_Lin_et_al_2014"
DIR_WES_DEPMAP="${BASE_DIR}/WES_DepMap_CCLE"
DIR_TARGETED_GEO="${BASE_DIR}/Targeted_GEO_Processed"

echo "Creating modality-specific directories..."
mkdir -p "$DIR_WGS" "$DIR_WES_DEPMAP" "$DIR_TARGETED_GEO"

# -----------------------------------------------------------------------------
# Modality: Whole Exome Sequencing (WES) / Aggregated CCLE
# Source: Broad Institute DepMap
# -----------------------------------------------------------------------------
echo "Fetching DepMap CCLE Mutations..."
# Using the Figshare public download link for the CCLE_mutations.csv file
DEPMAP_URL="https://ndownloader.figshare.com/files/34989937"
DEPMAP_FILE="${DIR_WES_DEPMAP}/CCLE_mutations.csv"

if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar "$DEPMAP_URL" -o "$DEPMAP_FILE"
elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$DEPMAP_FILE" "$DEPMAP_URL"
else
    echo "Error: Neither curl nor wget is installed."
    exit 1
fi

# Generate an executable script to extract HEK293-specific variants from the CCLE file
cat << 'EOF' > "${DIR_WES_DEPMAP}/extract_hek293.sh"
#!/usr/bin/env bash
set -euo pipefail

# The DepMap cell line ID for HEK293 is ACH-000569.
# This extracts all HEK293 mutations from the bulk CCLE file.

if [[ -f "CCLE_mutations.csv" ]]; then
    grep "ACH-000569" CCLE_mutations.csv > HEK293_mutations_only.csv
    echo "Extracted HEK293 specific variants to HEK293_mutations_only.csv"
else
    echo "CCLE_mutations.csv not found."
fi
EOF
chmod +x "${DIR_WES_DEPMAP}/extract_hek293.sh"

# -----------------------------------------------------------------------------
# Modality: Whole Genome Sequencing (WGS)
# Source: Lin et al. (2014) - PRJNA251508
# -----------------------------------------------------------------------------
echo "Scaffolding WGS fetch instructions..."
# The authors submitted SNPs/InDels to dbSNP (handle: NIBRT_MAMMALIAN) and raw reads to SRA. 
# This scaffolds the SRA-Toolkit commands necessary to pull the parental sequence reads.
cat << 'EOF' > "${DIR_WGS}/fetch_raw_WGS.sh"
#!/usr/bin/env bash
set -euo pipefail

# The generated SNPs and INDELs from Lin et al. 2014 are in dbSNP under the handle NIBRT_MAMMALIAN.
# The raw WGS sequencing reads are on the NCBI Sequence Read Archive (PRJNA251508).

# NOTE: Requires sra-toolkit (e.g., conda install -c bioconda sra-tools)

echo "Downloading parental HEK293 WGS reads (SRR1513220)..."
prefetch SRR1513220
fasterq-dump SRR1513220 --split-files --progress

echo "Raw fastq files are ready for alignment (e.g., BWA-MEM -> hg38) and variant calling."
EOF
chmod +x "${DIR_WGS}/fetch_raw_WGS.sh"

# -----------------------------------------------------------------------------
# Modality: Targeted / Assorted Processed VCFs
# Source: NCBI Gene Expression Omnibus (GEO)
# -----------------------------------------------------------------------------
echo "Scaffolding GEO FTP download template..."
# GEO datasets with VCFs are hosted on NCBI FTP servers. 
cat << 'EOF' > "${DIR_TARGETED_GEO}/fetch_geo_vcf.sh"
#!/usr/bin/env bash
set -euo pipefail

# Replace the URL below with the specific supplementary .vcf.gz file from your target GEO accession.
# Standard format: ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSEnnn/GSEnnn/suppl/GSEnnn_filename.vcf.gz

GEO_FTP_URL="ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSEnnn/GSEnnn/suppl/example_HEK293.vcf.gz"

echo "Attempting to download from placeholder URL..."
wget -q --show-progress "$GEO_FTP_URL" || echo "Please update the placeholder FTP link inside this script to point to a valid GEO accession."
EOF
chmod +x "${DIR_TARGETED_GEO}/fetch_geo_vcf.sh"

echo "==========================================================================="
echo "Setup complete! Directory tree generated in ./${BASE_DIR}/"
echo "DepMap CCLE bulk mutations have been downloaded."
echo "Fetch scripts for WGS and GEO data have been placed in their respective folders."
echo "==========================================================================="
