# --- Shared Indexing Rules ---

BWA_INDEX_EXTENSIONS = [".amb", ".ann", ".bwt", ".pac", ".sa"]
INDEXED_BAM_PREFIX_PATTERN = re.escape(WORKDIR) + r"/(mapped|dedup)/[^/]+\.(rna|wgs)(\.md)?"


# SAMtools faidx creates the FASTA index required by reference-driven tools.
# Source: https://www.htslib.org/doc/samtools-faidx.html
rule samtools_faidx:
    input:
        ref=REF
    output:
        fai=REF + ".fai"
    container: container_for("samtools")
    shell:
        "samtools faidx {input.ref}"


# BWA requires its five sidecar index files before bwa mem can align reads.
# Source: https://bio-bwa.sourceforge.net/bwa.shtml
rule bwa_index:
    input:
        ref=REF
    output:
        amb=REF + ".amb",
        ann=REF + ".ann",
        bwt=REF + ".bwt",
        pac=REF + ".pac",
        sa=REF + ".sa"
    container: container_for("wgs")
    resources:
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1)),
        mem_mb=lambda wildcards, attempt: 20000 * (1.5 ** (attempt - 1))
    shell:
        "bwa index {input.ref}"


# BAM indexes are consumed by downstream depth, variant, and RNA-editing tools.
# Source: https://www.htslib.org/doc/samtools-index.html
rule samtools_index:
    input:
        bam="{prefix}.bam"
    output:
        bai="{prefix}.bam.bai"
    wildcard_constraints:
        prefix=INDEXED_BAM_PREFIX_PATTERN
    container: container_for("samtools")
    shell:
        "samtools index {input.bam}"
